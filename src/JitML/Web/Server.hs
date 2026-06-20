{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Server
  ( BrowserCommandPublishers (..)
  , BrowserRuntimeRequest (..)
  , BrowserRuntimeResult (..)
  , BrowserRuntimeSurface (..)
  , BrowserRuntimeHandler
  , bundleEntryPath
  , demoHttpRoutes
  , demoHttpRoutesWithBundle
  , demoHttpRoutesWithRuntime
  , demoListener
  , liveDemoWebSocketRoutes
  , liveEventSnapshotResponse
  , loadBundleEntry
  , renderDemoIndex
  , renderDemoIndexWithBundle
  , serveDemo
  , serveDemoOnce
  , serveDemoWithBridge
  , serveDemoWithBridgeEndpoint
  , serveDemoWithBridgeEndpointWithRuntime
  )
where

import Control.Exception qualified
import Control.Monad.IO.Class qualified
import Data.List (maximumBy, sortOn)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import System.Directory (doesFileExist)
import Text.Read (readMaybe)

import JitML.Cluster.Publication qualified as Publication
import JitML.Proto.Rl qualified as ProtoRl
import JitML.Proto.Training qualified as ProtoTraining
import JitML.Proto.Tune qualified as ProtoTune
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Capabilities
  ( HasPulsar (..)
  , TopicName (..)
  )
import JitML.Service.Endpoints (EndpointResponse (..))
import JitML.Service.Http
  ( HttpRequest (..)
  , HttpRoute (..)
  , WebSocketRoute (..)
  , serveHttpRoutes
  , serveHttpRoutesOnce
  , serveHttpRoutesWithWebSockets
  )
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Web.Contracts qualified as Contracts

data BrowserRuntimeSurface
  = BrowserRuntimeInference
  | BrowserRuntimeGeneric
  | BrowserRuntimeImage
  | BrowserRuntimeAdversarial
  | -- | Sprint 11.10 — checkpoint-compare runs two inferences; its own surface
    -- keeps it on the synchronous publish-and-await path while the
    -- single-inference panels (inference/generic) move to the async stream.
    BrowserRuntimeCompare
  deriving stock (Eq, Show)

data BrowserRuntimeRequest = BrowserRuntimeRequest
  { browserRuntimeSurface :: BrowserRuntimeSurface
  , browserRuntimeExperimentHash :: Text
  , browserRuntimeInput :: [Double]
  }
  deriving stock (Eq, Show)

data BrowserRuntimeResult = BrowserRuntimeResult
  { browserRuntimeCheckpointSha :: Text
  , browserRuntimeOutput :: [Double]
  }
  deriving stock (Eq, Show)

type BrowserRuntimeHandler = BrowserRuntimeRequest -> IO (Either Text BrowserRuntimeResult)

-- | Sprint 11.10 — fire-and-forget publishers for the composite-inference panels
-- (checkpoint compare, adversarial move). When present (the live Webapp role),
-- the endpoints publish an Engine @WorkCommand@ and return an ack; the panel
-- renders the streamed result. When absent (tests), the endpoints fall back to
-- the synchronous runtime-handler path.
data BrowserCommandPublishers = BrowserCommandPublishers
  { publishCompareCommand :: Text -> Text -> [Double] -> IO (Either Text ())
  -- ^ baseline hash, candidate hash, input
  , publishMoveCommand :: Text -> Text -> [Int] -> Int -> Int -> IO (Either Text ())
  -- ^ game, experiment hash, moves, human-is-player, simulations
  }

demoListener :: Text -> Int -> HttpListener
demoListener =
  HttpListener

serveDemo :: Text -> Int -> IO ()
serveDemo host port = do
  bundle <- loadBundleEntry
  serveHttpRoutes (demoListener host port) (demoHttpRoutesWithBundle bundle)

serveDemoOnce :: Text -> Int -> IO ()
serveDemoOnce host port = do
  bundle <- loadBundleEntry
  serveHttpRoutesOnce (demoListener host port) (demoHttpRoutesWithBundle bundle)

-- | Sprint 13.13 — serve the demo HTTP routes plus the live
-- WebSocket-upgrade bridge to a real Pulsar broker. When a live
-- cluster publication is supplied, @/api/ws/{training,tune,rl}@
-- upgrade requests open a Pulsar consumer on the matching
-- @<domain>.event.<substrate>@ topic and forward each delivery as a
-- WebSocket text frame. The HTTP-only routes (the demo shell,
-- @/api@, @/api/inference@, etc.) keep their existing
-- one-request-one-response behaviour.
serveDemoWithBridge :: Text -> Int -> Maybe Publication.ClusterPublication -> IO ()
serveDemoWithBridge host port livePublication =
  serveDemoWithBridgeEndpoint host port livePublication Nothing

-- | Sprint 13.13 — as 'serveDemoWithBridge', but with an explicit Pulsar
-- WebSocket endpoint override. When the demo runs as the in-cluster
-- @jitml-demo@ pod it cannot reach the host edge port; it reaches the
-- broker through the in-cluster service DNS instead (supplied via
-- @JITML_DEMO_PULSAR_WS@). When the override is 'Nothing' the bridge
-- derives the host-edge settings from the publication's leased edge port
-- (the local @jitml-demo@ workflow).
serveDemoWithBridgeEndpoint
  :: Text -> Int -> Maybe Publication.ClusterPublication -> Maybe Text -> IO ()
serveDemoWithBridgeEndpoint host port livePublication endpointOverride =
  serveDemoWithBridgeEndpointWithRuntime host port livePublication endpointOverride Nothing Nothing

serveDemoWithBridgeEndpointWithRuntime
  :: Text
  -> Int
  -> Maybe Publication.ClusterPublication
  -> Maybe Text
  -> Maybe BrowserRuntimeHandler
  -> Maybe BrowserCommandPublishers
  -> IO ()
serveDemoWithBridgeEndpointWithRuntime host port livePublication endpointOverride runtimeHandler publishers = do
  bundle <- loadBundleEntry
  serveHttpRoutesWithWebSockets
    (demoListener host port)
    (demoHttpRoutesWithLiveBundle bundle livePublication endpointOverride runtimeHandler publishers)
    (liveDemoWebSocketRoutes livePublication endpointOverride)

-- | Build the WebSocket route table for the demo. With a live
-- publication the bridges open Pulsar consumers; without one they
-- return a terminal error frame so the WebSocket handshake still
-- completes while making the missing live publication explicit.
liveDemoWebSocketRoutes
  :: Maybe Publication.ClusterPublication -> Maybe Text -> [WebSocketRoute]
liveDemoWebSocketRoutes publication endpointOverride =
  [ webSocketRouteFor "/api/ws" "metrics" publication endpointOverride
  , webSocketRouteFor "/api/ws/training" "training" publication endpointOverride
  , webSocketRouteFor "/api/ws/tune" "tune" publication endpointOverride
  , webSocketRouteFor "/api/ws/rl" "rl" publication endpointOverride
  , -- Sprint 11.10 — the inference result stream: the Webapp publishes an
    -- inference `WorkCommand` to the Engine and the browser panels render the
    -- streamed `WorkResult` (the `inference.result.<substrate>` frames) over this
    -- websocket, instead of a synchronous compute-and-return fetch.
    webSocketRouteFor "/api/ws/inference" "inference" publication endpointOverride
  ]

webSocketRouteFor
  :: Text -> Text -> Maybe Publication.ClusterPublication -> Maybe Text -> WebSocketRoute
webSocketRouteFor path domain publication endpointOverride =
  WebSocketRoute
    { webSocketRoutePath = path
    , webSocketRouteHandler = bridgeHandler domain publication endpointOverride
    }

bridgeHandler
  :: Text
  -> Maybe Publication.ClusterPublication
  -> Maybe Text
  -> (Text -> IO Bool)
  -> IO ()
bridgeHandler domain Nothing _ writeFrame = do
  _ <- writeFrame (liveStreamUnavailableFrame domain)
  pure ()
bridgeHandler domain (Just publication) endpointOverride writeFrame = do
  let substrate = Publication.publicationSubstrate publication
      edgePort = Publication.publicationEdgePort publication
      pulsarSettings =
        case endpointOverride of
          Just endpoint -> PulsarWebSocketSubprocess.pulsarSettingsForEndpoint endpoint
          Nothing -> PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
      topic = TopicName (eventTopicFor domain substrate)
      subscriptionName = "jitml-demo-bridge-" <> domain
  result <-
    PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
      pulsarSettings
      (consumeLoop topic subscriptionName writeFrame)
  case result of
    Right () -> pure ()
    Left err -> do
      -- Forward the error as one terminal frame so the client sees
      -- why the stream stopped.
      _ <-
        writeFrame
          ( "event: error\ndata: bridge consume failed: "
              <> Text.replace "\n" " " (Text.pack err)
              <> "\n\n"
          )
      pure ()

consumeLoop
  :: TopicName
  -> Text
  -> (Text -> IO Bool)
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Either String ())
consumeLoop topic subscriptionName writeFrame = do
  subscribeResult <- pulsarSubscribe topic subscriptionName
  case subscribeResult of
    Left err -> pure (Left (show err))
    Right subId -> drainLoop subId
 where
  drainLoop subId = do
    consumed <- pulsarConsume subId
    case consumed of
      Left err -> pure (Left (show err))
      Right (_topicBack, payload) -> do
        keepGoing <-
          Control.Monad.IO.Class.liftIO (writeFrame payload)
        if keepGoing
          then do
            _ <- pulsarAcknowledge topic payload
            drainLoop subId
          else pure (Right ())

eventTopicFor :: Text -> Substrate -> Text
eventTopicFor "metrics" substrate =
  "persistent://public/default/training.event." <> renderSubstrate substrate
-- Sprint 11.10 — inference results stream off `inference.result.<substrate>`
-- (the Engine's `WorkResult` topic), not an `inference.event` topic.
eventTopicFor "inference" substrate =
  "persistent://public/default/inference.result." <> renderSubstrate substrate
eventTopicFor domain substrate =
  "persistent://public/default/" <> domain <> ".event." <> renderSubstrate substrate

-- | Canonical path to the browser-loadable Halogen entry bundle. The
-- Dockerfile runs `spago build --output dist` (per-module CommonJS
-- CoreFn under `web/dist/<Module>/index.js`) then bundles the `Main`
-- entry into a self-contained IIFE at `web/dist/Main/bundle.js` via
-- esbuild (Sprint 13.13). The demo serves that bundle at
-- `/bundle/main.js`.
bundleEntryPath :: FilePath
bundleEntryPath = "web/dist/Main/bundle.js"

-- | Read the compiled Halogen bundle if a build has produced it,
-- returning Nothing otherwise so the bundle route is omitted.
loadBundleEntry :: IO (Maybe Text)
loadBundleEntry =
  readIfExists bundleEntryPath
 where
  readIfExists path = do
    exists <- doesFileExist path
    if exists
      then
        (Just <$> Text.IO.readFile path)
          `Control.Exception.catch` \(_ :: Control.Exception.SomeException) -> pure Nothing
      else pure Nothing

demoHttpRoutes :: [HttpRoute]
demoHttpRoutes = demoHttpRoutesWithBundle Nothing

-- | Build the demo HTTP route table, optionally embedding the compiled
-- Halogen bundle. `/` always serves the browser shell that loads
-- `/bundle/main.js`; when `Just <js>` is passed, `/bundle/main.js`
-- serves the bundle bytes.
demoHttpRoutesWithBundle :: Maybe Text -> [HttpRoute]
demoHttpRoutesWithBundle bundle =
  demoHttpRoutesWithLiveBundle bundle Nothing Nothing Nothing Nothing

demoHttpRoutesWithRuntime :: BrowserRuntimeHandler -> [HttpRoute]
demoHttpRoutesWithRuntime runtimeHandler =
  demoHttpRoutesWithLiveBundle Nothing Nothing Nothing (Just runtimeHandler) Nothing

demoHttpRoutesWithLiveBundle
  :: Maybe Text
  -> Maybe Publication.ClusterPublication
  -> Maybe Text
  -> Maybe BrowserRuntimeHandler
  -> Maybe BrowserCommandPublishers
  -> [HttpRoute]
demoHttpRoutesWithLiveBundle bundle livePublication endpointOverride runtimeHandler publishers =
  [ htmlRoute "GET" "/" (EndpointResponse 200 (renderDemoIndexWithBundle bundle))
  , textRoute "GET" "/api" (EndpointResponse 200 renderApiIndex)
  , textRouteHandler
      "POST"
      "/api/runs/{runId}/command"
      (workflowCommandResponse livePublication endpointOverride)
  , textRouteHandler "POST" "/api/inference" (browserInferenceResponse runtimeHandler)
  , textRouteHandler "POST" "/api/inference/generic" (browserGenericInferenceResponse runtimeHandler)
  , textRouteHandler "POST" "/api/images" (browserImageResponse runtimeHandler)
  , textRouteHandler
      "POST"
      "/api/checkpoints/compare"
      (browserCheckpointCompareResponse publishers runtimeHandler)
  , textRouteHandler "POST" "/api/connect4/move" (browserAdversarialResponse publishers runtimeHandler)
  , textRoute "GET" "/api/ws" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/training" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/rl" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/tune" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/inference" liveStreamUpgradeRequired
  ]
    <> case bundle of
      Just js ->
        [ HttpRoute
            { httpRouteMethod = "GET"
            , httpRoutePath = "/bundle/main.js"
            , httpRouteContentType = "application/javascript; charset=utf-8"
            , httpRouteHandler = \_request -> pure (EndpointResponse 200 js)
            }
        ]
      Nothing -> []

renderDemoIndex :: Text
renderDemoIndex = renderDemoIndexWithBundle Nothing

-- | HTML shell for the demo `/` route. The compiled Halogen bundle is
-- loaded from `/bundle/main.js`; the Kind image bakes that file into
-- the container.
renderDemoIndexWithBundle :: Maybe Text -> Text
renderDemoIndexWithBundle _bundle =
  Text.unlines
    [ "<!doctype html>"
    , "<html lang=\"en\">"
    , "<head><meta charset=\"utf-8\"><title>jitML Demo</title></head>"
    , "<body>"
    , "<main id=\"app\">"
    , "<script type=\"module\" src=\"/bundle/main.js\"></script>"
    , "</main>"
    , "</body>"
    , "</html>"
    ]

renderApiIndex :: Text
renderApiIndex =
  Text.unlines $
    [ "endpoints:"
    ]
      <> fmap renderEndpoint Contracts.apiEndpoints
 where
  renderEndpoint endpoint =
    "- "
      <> Contracts.endpointMethod endpoint
      <> " "
      <> Contracts.endpointPath endpoint
      <> " "
      <> Contracts.endpointName endpoint

checkpointBackedDemoRequired :: Text -> EndpointResponse
checkpointBackedDemoRequired surface =
  EndpointResponse
    503
    ( Text.unlines
        [ "checkpoint-required: " <> surface
        , "reason: checkpoint-backed runtime publication required"
        ]
    )

data BrowserInferenceRequest = BrowserInferenceRequest
  { birPanel :: Text
  , birModelId :: Text
  , birExperimentHash :: Text
  , birInput :: [Double]
  }
  deriving stock (Eq, Show)

data BrowserImageRequest = BrowserImageRequest
  { bimPanel :: Text
  , bimDataset :: Text
  , bimExperimentHash :: Text
  , bimInput :: [Double]
  }
  deriving stock (Eq, Show)

data BrowserGenericInferenceRequest = BrowserGenericInferenceRequest
  { bgirPanel :: Text
  , bgirExperimentHash :: Text
  , bgirInput :: [Double]
  }
  deriving stock (Eq, Show)

data BrowserCheckpointCompareRequest = BrowserCheckpointCompareRequest
  { bccPanel :: Text
  , bccBaselineExperimentHash :: Text
  , bccCandidateExperimentHash :: Text
  , bccInput :: [Double]
  }
  deriving stock (Eq, Show)

data BrowserAdversarialRequest = BrowserAdversarialRequest
  { barPanel :: Text
  , barGame :: Text
  , barExperimentHash :: Text
  , barMoves :: [Int]
  , barHumanIsPlayer :: Int
  , barSimulationsPerMove :: Int
  }
  deriving stock (Eq, Show)

browserInferenceResponse
  :: Maybe BrowserRuntimeHandler -> HttpRequest -> IO EndpointResponse
browserInferenceResponse runtimeHandler request =
  case parseBrowserInferenceRequest (httpRequestBody request) of
    Left err -> pure (badRequestResponse "inference-request-invalid" err)
    Right inferenceRequest ->
      withTimedRuntime
        runtimeHandler
        "inference"
        ( BrowserRuntimeRequest
            BrowserRuntimeInference
            (birExperimentHash inferenceRequest)
            (birInput inferenceRequest)
        )
        (renderInferenceResultResponse inferenceRequest)

browserGenericInferenceResponse
  :: Maybe BrowserRuntimeHandler -> HttpRequest -> IO EndpointResponse
browserGenericInferenceResponse runtimeHandler request =
  case parseBrowserGenericInferenceRequest (httpRequestBody request) of
    Left err -> pure (badRequestResponse "generic-inference-request-invalid" err)
    Right inferenceRequest ->
      withTimedRuntime
        runtimeHandler
        "generic-inference"
        ( BrowserRuntimeRequest
            BrowserRuntimeGeneric
            (bgirExperimentHash inferenceRequest)
            (bgirInput inferenceRequest)
        )
        (renderGenericInferenceResultResponse inferenceRequest)

browserImageResponse
  :: Maybe BrowserRuntimeHandler -> HttpRequest -> IO EndpointResponse
browserImageResponse runtimeHandler request =
  case parseBrowserImageRequest (httpRequestBody request) of
    Left err -> pure (badRequestResponse "image-request-invalid" err)
    Right imageRequest ->
      withTimedRuntime
        runtimeHandler
        "image"
        ( BrowserRuntimeRequest
            BrowserRuntimeImage
            (bimExperimentHash imageRequest)
            (bimInput imageRequest)
        )
        (renderImageInferenceResultResponse imageRequest)

browserCheckpointCompareResponse
  :: Maybe BrowserCommandPublishers -> Maybe BrowserRuntimeHandler -> HttpRequest -> IO EndpointResponse
browserCheckpointCompareResponse publishers runtimeHandler request =
  case parseBrowserCheckpointCompareRequest (httpRequestBody request) of
    Left err -> pure (badRequestResponse "checkpoint-compare-request-invalid" err)
    Right compareRequest ->
      case publishers of
        Just p -> do
          published <-
            publishCompareCommand
              p
              (bccBaselineExperimentHash compareRequest)
              (bccCandidateExperimentHash compareRequest)
              (bccInput compareRequest)
          pure (publishedAckResponse "CheckpointComparePublished" published)
        Nothing ->
          withTimedCheckpointCompare runtimeHandler compareRequest

browserAdversarialResponse
  :: Maybe BrowserCommandPublishers -> Maybe BrowserRuntimeHandler -> HttpRequest -> IO EndpointResponse
browserAdversarialResponse publishers runtimeHandler request =
  case parseBrowserAdversarialRequest (httpRequestBody request) of
    Left err -> pure (badRequestResponse "adversarial-request-invalid" err)
    Right moveRequest ->
      case publishers of
        Just p -> do
          published <-
            publishMoveCommand
              p
              (barGame moveRequest)
              (barExperimentHash moveRequest)
              (barMoves moveRequest)
              (barHumanIsPlayer moveRequest)
              (barSimulationsPerMove moveRequest)
          pure (publishedAckResponse "AdversarialMovePublished" published)
        Nothing ->
          withTimedRuntime
            runtimeHandler
            "connect4"
            ( BrowserRuntimeRequest
                BrowserRuntimeAdversarial
                (barExperimentHash moveRequest)
                (adversarialRuntimeInput moveRequest)
            )
            (renderAdversarialMoveResultResponse moveRequest)

-- | Sprint 11.10 — ack returned by the fire-and-forget composite-inference
-- endpoints; the decoded result arrives on @/api/ws/inference@.
publishedAckResponse :: Text -> Either Text () -> EndpointResponse
publishedAckResponse kind published =
  case published of
    Left err -> EndpointResponse 502 (Text.unlines ["kind: " <> kind, "status: failed", "error: " <> err])
    Right () -> EndpointResponse 200 (Text.unlines ["kind: " <> kind, "status: published"])

withTimedRuntime
  :: Maybe BrowserRuntimeHandler
  -> Text
  -> BrowserRuntimeRequest
  -> (BrowserRuntimeResult -> Double -> EndpointResponse)
  -> IO EndpointResponse
withTimedRuntime Nothing surface _request _render =
  pure (checkpointBackedDemoRequired surface)
withTimedRuntime (Just runtimeHandler) _surface runtimeRequest renderResponse = do
  started <- getCurrentTime
  result <- runtimeHandler runtimeRequest
  finished <- getCurrentTime
  let latencyMs = realToFrac (diffUTCTime finished started) * (1000.0 :: Double)
  pure $
    case result of
      Left err ->
        EndpointResponse
          503
          ( Text.unlines
              [ "checkpoint-runtime-failed: " <> err
              , "status: failed"
              ]
          )
      Right runtimeResult ->
        renderResponse runtimeResult latencyMs

withTimedCheckpointCompare
  :: Maybe BrowserRuntimeHandler
  -> BrowserCheckpointCompareRequest
  -> IO EndpointResponse
withTimedCheckpointCompare Nothing _request =
  pure (checkpointBackedDemoRequired "checkpoint-compare")
withTimedCheckpointCompare (Just runtimeHandler) request = do
  started <- getCurrentTime
  baselineResult <-
    runtimeHandler
      ( BrowserRuntimeRequest
          BrowserRuntimeCompare
          (bccBaselineExperimentHash request)
          (bccInput request)
      )
  candidateResult <-
    runtimeHandler
      ( BrowserRuntimeRequest
          BrowserRuntimeCompare
          (bccCandidateExperimentHash request)
          (bccInput request)
      )
  finished <- getCurrentTime
  let latencyMs = realToFrac (diffUTCTime finished started) * (1000.0 :: Double)
  pure $
    case (baselineResult, candidateResult) of
      (Left err, _) ->
        checkpointCompareFailed "baseline" err
      (_, Left err) ->
        checkpointCompareFailed "candidate" err
      (Right baseline, Right candidate) ->
        renderCheckpointCompareResultResponse request baseline candidate latencyMs

renderInferenceResultResponse
  :: BrowserInferenceRequest -> BrowserRuntimeResult -> Double -> EndpointResponse
renderInferenceResultResponse request runtimeResult latencyMs =
  let probabilities = probabilityVector (browserRuntimeOutput runtimeResult)
      topClass = topIndex probabilities
      confidence = valueAt topClass probabilities
   in EndpointResponse
        200
        ( Text.unlines
            [ "kind: InferenceResult"
            , "panel: " <> birPanel request
            , "model-id: " <> birModelId request
            , "checkpoint-sha: " <> browserRuntimeCheckpointSha runtimeResult
            , "top-class: " <> Text.pack (show topClass)
            , "confidence: " <> showText confidence
            , "latency-ms: " <> showText latencyMs
            , "probabilities: " <> renderDoubleList probabilities
            , "output: " <> renderDoubleList (browserRuntimeOutput runtimeResult)
            , "status: ok"
            ]
        )

renderGenericInferenceResultResponse
  :: BrowserGenericInferenceRequest -> BrowserRuntimeResult -> Double -> EndpointResponse
renderGenericInferenceResultResponse request runtimeResult latencyMs =
  EndpointResponse
    200
    ( Text.unlines
        [ "kind: GenericInferenceResult"
        , "panel: " <> bgirPanel request
        , "experiment-hash: " <> bgirExperimentHash request
        , "checkpoint-sha: " <> browserRuntimeCheckpointSha runtimeResult
        , "latency-ms: " <> showText latencyMs
        , "output: " <> renderDoubleList (browserRuntimeOutput runtimeResult)
        , "status: ok"
        ]
    )

renderImageInferenceResultResponse
  :: BrowserImageRequest -> BrowserRuntimeResult -> Double -> EndpointResponse
renderImageInferenceResultResponse request runtimeResult latencyMs =
  let probabilities = probabilityVector (browserRuntimeOutput runtimeResult)
      top = topIndices 5 probabilities
   in EndpointResponse
        200
        ( Text.unlines
            [ "kind: ImageInferenceResult"
            , "panel: " <> bimPanel request
            , "dataset: " <> bimDataset request
            , "checkpoint-sha: " <> browserRuntimeCheckpointSha runtimeResult
            , "top-k: " <> renderIntList top
            , "probabilities: " <> renderDoubleList (fmap (`valueAt` probabilities) top)
            , "preprocessing-ms: 0.0"
            , "inference-ms: " <> showText latencyMs
            , "status: ok"
            ]
        )

renderCheckpointCompareResultResponse
  :: BrowserCheckpointCompareRequest
  -> BrowserRuntimeResult
  -> BrowserRuntimeResult
  -> Double
  -> EndpointResponse
renderCheckpointCompareResultResponse request baseline candidate latencyMs =
  let baselineOutput = browserRuntimeOutput baseline
      candidateOutput = browserRuntimeOutput candidate
      deltas = absoluteDeltas baselineOutput candidateOutput
   in EndpointResponse
        200
        ( Text.unlines
            [ "kind: CheckpointCompareResult"
            , "panel: " <> bccPanel request
            , "baseline-checkpoint-sha: " <> browserRuntimeCheckpointSha baseline
            , "candidate-checkpoint-sha: " <> browserRuntimeCheckpointSha candidate
            , "baseline-output: " <> renderDoubleList baselineOutput
            , "candidate-output: " <> renderDoubleList candidateOutput
            , "max-abs-delta: " <> showText (maximumOrZero deltas)
            , "mean-abs-delta: " <> showText (meanOrZero deltas)
            , "latency-ms: " <> showText latencyMs
            , "status: ok"
            ]
        )

checkpointCompareFailed :: Text -> Text -> EndpointResponse
checkpointCompareFailed side err =
  EndpointResponse
    503
    ( Text.unlines
        [ "checkpoint-compare-failed: " <> side <> ": " <> err
        , "status: failed"
        ]
    )

renderAdversarialMoveResultResponse
  :: BrowserAdversarialRequest -> BrowserRuntimeResult -> Double -> EndpointResponse
renderAdversarialMoveResultResponse request runtimeResult _latencyMs =
  let actionCount = actionCountForGame (barGame request)
      state = gameStateAfter (barGame request) (barMoves request)
      legalMoves = filter (\move -> AlphaZero.isLegalMove (barGame request) move state) [0 .. actionCount - 1]
      priors = maskedPriors actionCount legalMoves (browserRuntimeOutput runtimeResult)
      valueEstimate = valueEstimateFromOutput actionCount (browserRuntimeOutput runtimeResult)
      config =
        (Mcts.defaultMctsConfig actionCount) {Mcts.mctsSimulations = max 1 (barSimulationsPerMove request)}
      terminal = AlphaZero.gameIsTerminal state
      root =
        Mcts.runSearchWithPrior
          (const (Mcts.NodeEval priors valueEstimate terminal))
          config
          (length (barMoves request) + barHumanIsPlayer request)
      visitCounts = fmap (visitsFor root) legalMoves
      chosenMove = chooseMove legalMoves visitCounts
   in EndpointResponse
        200
        ( Text.unlines
            [ "kind: AdversarialMoveResult"
            , "panel: " <> barPanel request
            , "game: " <> barGame request
            , "chosen-column: " <> Text.pack (show chosenMove)
            , "legal-moves: " <> renderIntList legalMoves
            , "visit-counts: " <> renderIntList visitCounts
            , "policy-priors: " <> renderDoubleList (fmap (`valueAt` priors) legalMoves)
            , "value-estimate: " <> showText valueEstimate
            , "game-over: " <> renderBool (terminal || null legalMoves)
            , "transcript-id: " <> transcriptId request chosenMove
            ]
        )

parseBrowserInferenceRequest :: Text -> Either Text BrowserInferenceRequest
parseBrowserInferenceRequest payload =
  let fields = parseFields payload
      value key = lookup key fields
   in case value "kind" of
        Just "BrowserInferenceRequest" ->
          BrowserInferenceRequest
            <$> required value "panel"
            <*> required value "model-id"
            <*> required value "experiment-hash"
            <*> requiredParsed value "input" parseDoubleList
        _ -> Left "expected kind: BrowserInferenceRequest"

parseBrowserGenericInferenceRequest :: Text -> Either Text BrowserGenericInferenceRequest
parseBrowserGenericInferenceRequest payload =
  let fields = parseFields payload
      value key = lookup key fields
   in case value "kind" of
        Just "BrowserGenericInferenceRequest" ->
          BrowserGenericInferenceRequest
            <$> required value "panel"
            <*> required value "experiment-hash"
            <*> requiredParsed value "input" parseDoubleList
        _ -> Left "expected kind: BrowserGenericInferenceRequest"

parseBrowserImageRequest :: Text -> Either Text BrowserImageRequest
parseBrowserImageRequest payload =
  let fields = parseFields payload
      value key = lookup key fields
   in case value "kind" of
        Just "BrowserImageRequest" ->
          BrowserImageRequest
            <$> required value "panel"
            <*> required value "dataset"
            <*> required value "experiment-hash"
            <*> requiredParsed value "input" parseDoubleList
        _ -> Left "expected kind: BrowserImageRequest"

parseBrowserCheckpointCompareRequest :: Text -> Either Text BrowserCheckpointCompareRequest
parseBrowserCheckpointCompareRequest payload =
  let fields = parseFields payload
      value key = lookup key fields
   in case value "kind" of
        Just "BrowserCheckpointCompareRequest" ->
          BrowserCheckpointCompareRequest
            <$> required value "panel"
            <*> required value "baseline-experiment-hash"
            <*> required value "candidate-experiment-hash"
            <*> requiredParsed value "input" parseDoubleList
        _ -> Left "expected kind: BrowserCheckpointCompareRequest"

parseBrowserAdversarialRequest :: Text -> Either Text BrowserAdversarialRequest
parseBrowserAdversarialRequest payload =
  let fields = parseFields payload
      value key = lookup key fields
   in case value "kind" of
        Just "BrowserAdversarialMoveRequest" ->
          BrowserAdversarialRequest
            <$> required value "panel"
            <*> required value "game"
            <*> required value "experiment-hash"
            <*> requiredParsed value "moves" parseIntList
            <*> requiredParsed value "human-is-player" readText
            <*> requiredParsed value "simulations-per-move" readText
        _ -> Left "expected kind: BrowserAdversarialMoveRequest"

parseFields :: Text -> [(Text, Text)]
parseFields =
  mapMaybe parseField . Text.lines
 where
  parseField line =
    case Text.breakOn ": " line of
      (key, rest)
        | not (Text.null key) && ": " `Text.isPrefixOf` rest ->
            Just (Text.strip key, Text.strip (Text.drop 2 rest))
      _ -> Nothing

required :: (Text -> Maybe Text) -> Text -> Either Text Text
required value key =
  maybe (Left ("missing field " <> key)) Right (value key)

requiredParsed :: (Text -> Maybe Text) -> Text -> (Text -> Maybe a) -> Either Text a
requiredParsed value key parser =
  case value key of
    Nothing -> Left ("missing field " <> key)
    Just raw ->
      maybe (Left ("invalid field " <> key <> ": " <> raw)) Right (parser raw)

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack . Text.strip

parseIntList :: Text -> Maybe [Int]
parseIntList raw
  | Text.null (Text.strip raw) = Just []
  | otherwise = traverse readText (Text.splitOn "," raw)

parseDoubleList :: Text -> Maybe [Double]
parseDoubleList raw
  | Text.null (Text.strip raw) = Just []
  | otherwise = traverse readText (Text.splitOn "," raw)

badRequestResponse :: Text -> Text -> EndpointResponse
badRequestResponse label err =
  EndpointResponse
    400
    ( Text.unlines
        [ label <> ": " <> err
        , "status: failed"
        ]
    )

probabilityVector :: [Double] -> [Double]
probabilityVector [] = []
probabilityVector values =
  let shifted = fmap (\value -> exp (value - maximum values)) values
      total = sum shifted
   in if total <= 0 then replicate (length values) 0 else fmap (/ total) shifted

topIndex :: [Double] -> Int
topIndex [] = 0
topIndex values =
  fst (maximumBy (comparing snd) (zip [0 ..] values))

topIndices :: Int -> [Double] -> [Int]
topIndices count values =
  take count (fmap fst (sortOn (Down . snd) (zip [0 ..] values)))

valueAt :: Int -> [Double] -> Double
valueAt index values =
  fromMaybe 0.0 (safeIndex index values)

absoluteDeltas :: [Double] -> [Double] -> [Double]
absoluteDeltas baseline candidate =
  let count = max (length baseline) (length candidate)
      padded values = take count (values <> repeat 0.0)
   in zipWith (\left right -> abs (left - right)) (padded baseline) (padded candidate)

maximumOrZero :: [Double] -> Double
maximumOrZero [] = 0.0
maximumOrZero values = maximum values

meanOrZero :: [Double] -> Double
meanOrZero [] = 0.0
meanOrZero values = sum values / fromIntegral (length values)

safeIndex :: Int -> [a] -> Maybe a
safeIndex index values
  | index < 0 = Nothing
  | otherwise =
      case drop index values of
        value : _ -> Just value
        [] -> Nothing

actionCountForGame :: Text -> Int
actionCountForGame =
  AlphaZero.policyHeadSize . AlphaZero.twoHeadedNetworkFor

gameStateAfter :: Text -> [Int] -> AlphaZero.GameState
gameStateAfter game =
  foldl (flip AlphaZero.applyMove) initial
 where
  initial =
    case game of
      "othello" -> AlphaZero.initialOthello
      "hex" -> AlphaZero.initialHex
      "gomoku" -> AlphaZero.initialGomoku
      _ -> AlphaZero.initialConnect4

maskedPriors :: Int -> [Int] -> [Double] -> [Double]
maskedPriors actionCount legalMoves output =
  let base = probabilityVector (take actionCount (output <> repeat 0.0))
      masked =
        [ if action `elem` legalMoves then valueAt action base else 0.0
        | action <- [0 .. actionCount - 1]
        ]
      total = sum masked
   in if total <= 0
        then
          [ if action `elem` legalMoves then 1.0 / fromIntegral (max 1 (length legalMoves)) else 0.0
          | action <- [0 .. actionCount - 1]
          ]
        else fmap (/ total) masked

valueEstimateFromOutput :: Int -> [Double] -> Double
valueEstimateFromOutput actionCount output =
  tanh (valueAt actionCount output)

visitsFor :: Mcts.MctsNode -> Int -> Int
visitsFor root action =
  fromMaybe 0 $ do
    edge <- findByAction action (Mcts.nodeChildren root)
    pure (Mcts.edgeVisits edge)

findByAction :: Int -> [Mcts.MctsEdge] -> Maybe Mcts.MctsEdge
findByAction action =
  go
 where
  go [] = Nothing
  go (edge : rest)
    | Mcts.edgeAction edge == action = Just edge
    | otherwise = go rest

chooseMove :: [Int] -> [Int] -> Int
chooseMove [] _ = 0
chooseMove legalMoves visitCounts =
  fst (maximumBy (comparing snd) (zip legalMoves (visitCounts <> repeat 0)))

adversarialRuntimeInput :: BrowserAdversarialRequest -> [Double]
adversarialRuntimeInput request =
  let actionCount = actionCountForGame (barGame request)
      state = gameStateAfter (barGame request) (barMoves request)
      legalMoves = filter (\move -> AlphaZero.isLegalMove (barGame request) move state) [0 .. actionCount - 1]
   in fmap fromIntegral (barMoves request)
        <> fmap fromIntegral legalMoves
        <> [fromIntegral (barHumanIsPlayer request), fromIntegral (barSimulationsPerMove request)]

transcriptId :: BrowserAdversarialRequest -> Int -> Text
transcriptId request chosenMove =
  Text.intercalate
    ":"
    [ barGame request
    , Text.intercalate "," (fmap (Text.pack . show) (barMoves request <> [chosenMove]))
    , browserSafeExperiment (barExperimentHash request)
    ]

browserSafeExperiment :: Text -> Text
browserSafeExperiment =
  Text.replace "\n" " " . Text.replace "\r" " "

renderIntList :: [Int] -> Text
renderIntList =
  Text.intercalate "," . fmap (Text.pack . show)

renderDoubleList :: [Double] -> Text
renderDoubleList =
  Text.intercalate "," . fmap showText

showText :: (Show a) => a -> Text
showText =
  Text.pack . show

renderBool :: Bool -> Text
renderBool True = "true"
renderBool False = "false"

data WorkflowCommandPublication = WorkflowCommandPublication
  { workflowCommandTopic :: TopicName
  , workflowCommandPayload :: Text
  , workflowCommandName :: Text
  }

workflowCommandResponse
  :: Maybe Publication.ClusterPublication -> Maybe Text -> HttpRequest -> IO EndpointResponse
workflowCommandResponse Nothing _endpointOverride _request =
  pure
    ( EndpointResponse
        503
        ( Text.unlines
            [ "workflow-command-unavailable: cluster publication required"
            , "reason: daemon-backed command publication requires a live cluster publication"
            ]
        )
    )
workflowCommandResponse (Just publication) endpointOverride request =
  case workflowCommandPublicationFor
    substrate
    (normalizeLiveSubstrate substrate (Text.strip (httpRequestBody request))) of
    Left err ->
      pure
        ( EndpointResponse
            400
            ( Text.unlines
                [ "workflow-command-invalid: " <> err
                , "reason: request body must be a typed training, RL, or tune command envelope"
                ]
            )
        )
    Right publicationCommand -> do
      publishResult <-
        PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess pulsarSettings $
          pulsarPublish
            (workflowCommandTopic publicationCommand)
            (workflowCommandPayload publicationCommand)
      case publishResult of
        Right messageId ->
          pure
            ( workflowCommandAccepted
                (runIdFromCommandPath (httpRequestPath request))
                publicationCommand
                messageId
            )
        Left err ->
          pure
            ( EndpointResponse
                503
                ( Text.unlines
                    [ "workflow-command-publish-failed: " <> Text.pack (show err)
                    , "status: failed"
                    ]
                )
            )
 where
  substrate = Publication.publicationSubstrate publication
  edgePort = Publication.publicationEdgePort publication
  pulsarSettings =
    case endpointOverride of
      Just endpoint -> PulsarWebSocketSubprocess.pulsarSettingsForEndpoint endpoint
      Nothing -> PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort

workflowCommandPublicationFor :: Substrate -> Text -> Either Text WorkflowCommandPublication
workflowCommandPublicationFor substrate payload =
  case ProtoTraining.parseTrainingCommand payload of
    Just command -> trainingCommandPublication substrate command
    Nothing ->
      case ProtoRl.parseRlCommand payload of
        Just command -> rlCommandPublication substrate command
        Nothing ->
          case ProtoTune.parseTuneCommand payload of
            Just command -> tuneCommandPublication substrate command
            Nothing -> Left "unrecognized command kind"

normalizeLiveSubstrate :: Substrate -> Text -> Text
normalizeLiveSubstrate substrate =
  Text.replace "substrate: live" ("substrate: " <> renderSubstrate substrate)

trainingCommandPublication
  :: Substrate -> ProtoTraining.TrainingCommand -> Either Text WorkflowCommandPublication
trainingCommandPublication substrate command =
  case command of
    ProtoTraining.TrainingStart start -> do
      ensureCommandSubstrate substrate (ProtoTraining.stSubstrate start)
      pure
        ( makeCommandPublication
            "StartTraining"
            (ProtoTraining.trainingCommandTopic substrate)
            (ProtoTraining.renderTrainingCommand command)
        )
    ProtoTraining.TrainingStop _ ->
      pure
        ( makeCommandPublication
            "StopTraining"
            (ProtoTraining.trainingCommandTopic substrate)
            (ProtoTraining.renderTrainingCommand command)
        )

rlCommandPublication :: Substrate -> ProtoRl.RlCommand -> Either Text WorkflowCommandPublication
rlCommandPublication substrate command =
  case command of
    ProtoRl.RlStart start -> do
      ensureCommandSubstrate substrate (ProtoRl.srlSubstrate start)
      pure
        ( makeCommandPublication
            "StartRLRun"
            (ProtoRl.rlCommandTopic substrate)
            (ProtoRl.renderRlCommand command)
        )
    ProtoRl.RlStop _ ->
      pure
        ( makeCommandPublication
            "StopRLRun"
            (ProtoRl.rlCommandTopic substrate)
            (ProtoRl.renderRlCommand command)
        )

tuneCommandPublication
  :: Substrate -> ProtoTune.TuneCommand -> Either Text WorkflowCommandPublication
tuneCommandPublication substrate command =
  case command of
    ProtoTune.TuneStart start -> do
      ensureCommandSubstrate substrate (ProtoTune.ssSubstrate start)
      pure
        ( makeCommandPublication
            "StartSweep"
            (ProtoTune.tuneCommandTopic substrate)
            (ProtoTune.renderTuneCommand command)
        )
    ProtoTune.TuneStop _ ->
      pure
        ( makeCommandPublication
            "StopSweep"
            (ProtoTune.tuneCommandTopic substrate)
            (ProtoTune.renderTuneCommand command)
        )

makeCommandPublication :: Text -> Text -> Text -> WorkflowCommandPublication
makeCommandPublication commandName topic payload =
  WorkflowCommandPublication
    { workflowCommandTopic = TopicName ("persistent://public/default/" <> topic)
    , workflowCommandPayload = payload
    , workflowCommandName = commandName
    }

ensureCommandSubstrate :: Substrate -> Substrate -> Either Text ()
ensureCommandSubstrate expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( "command substrate "
            <> renderSubstrate actual
            <> " does not match live publication substrate "
            <> renderSubstrate expected
        )

workflowCommandAccepted :: Text -> WorkflowCommandPublication -> Text -> EndpointResponse
workflowCommandAccepted runId publicationCommand messageId =
  EndpointResponse
    200
    ( Text.unlines
        [ "kind: WorkflowCommandAck"
        , "run-id: " <> runId
        , "command: " <> workflowCommandName publicationCommand
        , "status: published"
        , "topic: " <> commandTopicText (workflowCommandTopic publicationCommand)
        , "message-id: " <> messageId
        ]
    )

commandTopicText :: TopicName -> Text
commandTopicText (TopicName topic) =
  topic

runIdFromCommandPath :: Text -> Text
runIdFromCommandPath path =
  case Text.stripPrefix "/api/runs/" path >>= Text.stripSuffix "/command" of
    Just runId | not (Text.null runId) -> runId
    _ -> "unknown"

-- | Sprint 13.13 — render a Server-Sent-Events-shaped frame from a live
-- broker event payload. The browser receives @event: <domain>@ +
-- @data: <payload>@ lines and the panel JS parses them into a typed
-- 'MetricFrame'. Without a live broker payload the response is a
-- visible 503 instead of a deterministic local frame.
--
-- Bridges the current one-request-one-response HTTP server (no
-- chunked transfer) to a polling pattern: the browser fires GET
-- @/api/ws/training@ on a 1s interval and the server returns the
-- latest event the live consumer has cached. The held-open WebSocket
-- proxy that streams Pulsar deliveries in chunked HTTP/1.1 frames is
-- the larger remaining work tracked in
-- "DEVELOPMENT_PLAN/phase-13-linux-cuda-and-cluster-closure.md"
-- Sprint 13.13.
liveEventSnapshotResponse :: Text -> Maybe Text -> EndpointResponse
liveEventSnapshotResponse domain Nothing =
  EndpointResponse 503 (liveStreamUnavailableText domain)
liveEventSnapshotResponse domain (Just payload) =
  EndpointResponse
    200
    ( Text.unlines
        [ "event: " <> domain
        , "data: " <> Text.replace "\n" " " payload
        ]
    )

liveStreamUpgradeRequired :: EndpointResponse
liveStreamUpgradeRequired =
  EndpointResponse 503 "live stream requires WebSocket upgrade\n"

liveStreamUnavailableFrame :: Text -> Text
liveStreamUnavailableFrame domain =
  Text.unlines
    [ "event: error"
    , "data: " <> Text.replace "\n" " " (liveStreamUnavailableText domain)
    ]

liveStreamUnavailableText :: Text -> Text
liveStreamUnavailableText domain =
  "live stream unavailable for "
    <> domain
    <> ": cluster publication required\n"

textRoute :: Text -> Text -> EndpointResponse -> HttpRoute
textRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteHandler = \_request -> pure response
    }

htmlRoute :: Text -> Text -> EndpointResponse -> HttpRoute
htmlRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/html; charset=utf-8"
    , httpRouteHandler = \_request -> pure response
    }

textRouteHandler :: Text -> Text -> (HttpRequest -> IO EndpointResponse) -> HttpRoute
textRouteHandler method path handler =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteHandler = handler
    }

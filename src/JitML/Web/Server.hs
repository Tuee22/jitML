{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Server
  ( bundleEntryPath
  , demoHttpRoutes
  , demoHttpRoutesWithBundle
  , demoListener
  , liveDemoWebSocketRoutes
  , liveEventSnapshotResponse
  , loadBundleEntry
  , renderDemoIndex
  , renderDemoIndexWithBundle
  , serveDemo
  , serveDemoOnce
  , serveDemoWithBridge
  )
where

import Control.Exception qualified
import Control.Monad.IO.Class qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesFileExist)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Cluster.Publication qualified as Publication
import JitML.RL.Algorithms qualified as RL
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.SL.Canonicals qualified as SL
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Capabilities
  ( HasPulsar (..)
  , TopicName (..)
  )
import JitML.Service.Endpoints (EndpointResponse (..))
import JitML.Service.Http
  ( HttpRoute (..)
  , WebSocketRoute (..)
  , serveHttpRoutes
  , serveHttpRoutesOnce
  , serveHttpRoutesWithWebSockets
  )
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Tune.Catalog qualified as Tune
import JitML.Web.Bundle qualified as Bundle
import JitML.Web.Contracts qualified as Contracts

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
serveDemoWithBridge host port livePublication = do
  bundle <- loadBundleEntry
  serveHttpRoutesWithWebSockets
    (demoListener host port)
    (demoHttpRoutesWithBundle bundle)
    (liveDemoWebSocketRoutes livePublication)

-- | Build the WebSocket route table for the demo. With a live
-- publication the bridges open Pulsar consumers; without one they
-- return a single SSE-shaped 'event: ... \ndata: ... \n\n' frame
-- derived from 'liveEventSnapshotResponse'\'s deterministic
-- fallback so the WebSocket handshake still completes.
liveDemoWebSocketRoutes :: Maybe Publication.ClusterPublication -> [WebSocketRoute]
liveDemoWebSocketRoutes publication =
  [ webSocketRouteFor "/api/ws" "metrics" publication
  , webSocketRouteFor "/api/ws/training" "training" publication
  , webSocketRouteFor "/api/ws/tune" "tune" publication
  , webSocketRouteFor "/api/ws/rl" "rl" publication
  ]

webSocketRouteFor
  :: Text -> Text -> Maybe Publication.ClusterPublication -> WebSocketRoute
webSocketRouteFor path domain publication =
  WebSocketRoute
    { webSocketRoutePath = path
    , webSocketRouteHandler = bridgeHandler domain publication
    }

bridgeHandler
  :: Text -> Maybe Publication.ClusterPublication -> (Text -> IO Bool) -> IO ()
bridgeHandler domain Nothing writeFrame = do
  -- No live cluster — write the deterministic fallback frame once
  -- so the upgrade is observable even offline, then exit. The
  -- client treats the close frame as end-of-stream.
  _ <- writeFrame (fallbackFrame domain)
  pure ()
bridgeHandler domain (Just publication) writeFrame = do
  let substrate = Publication.publicationSubstrate publication
      edgePort = Publication.publicationEdgePort publication
      pulsarSettings =
        PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
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
eventTopicFor domain substrate =
  "persistent://public/default/" <> domain <> ".event." <> renderSubstrate substrate

-- | Canonical path to the compiled Halogen entry bundle. `spago build
-- --output web/dist` writes the per-module CoreFn JS under
-- `web/dist/<Module>/index.js`; the demo serves the Main module's entry
-- at `/bundle/main.js`.
bundleEntryPath :: FilePath
bundleEntryPath = "web/dist/Main/index.js"

-- | Read the compiled Halogen bundle if `spago build` has produced it;
-- returns Nothing otherwise so the demo falls back to the placeholder
-- HTML shell.
loadBundleEntry :: IO (Maybe Text)
loadBundleEntry = do
  exists <- doesFileExist bundleEntryPath
  if exists
    then
      (Just <$> Text.IO.readFile bundleEntryPath)
        `Control.Exception.catch` \(_ :: Control.Exception.SomeException) -> pure Nothing
    else pure Nothing

demoHttpRoutes :: [HttpRoute]
demoHttpRoutes = demoHttpRoutesWithBundle Nothing

-- | Build the demo HTTP route table, optionally embedding the compiled
-- Halogen bundle. When `Just <js>` is passed, `/` serves an HTML shell
-- that script-tags `/bundle/main.js`, and `/bundle/main.js` serves the
-- bundle bytes; otherwise the route table falls back to the placeholder
-- HTML shell.
demoHttpRoutesWithBundle :: Maybe Text -> [HttpRoute]
demoHttpRoutesWithBundle bundle =
  [ htmlRoute "GET" "/" (EndpointResponse 200 (renderDemoIndexWithBundle bundle))
  , textRoute "GET" "/api" (EndpointResponse 200 renderApiIndex)
  , textRoute "POST" "/api/inference" (EndpointResponse 200 renderInferenceResponse)
  , textRoute "POST" "/api/images" (EndpointResponse 200 "accepted image upload contract\n")
  , textRoute "POST" "/api/connect4/move" (EndpointResponse 200 renderConnect4Response)
  , textRoute "GET" "/api/ws" (EndpointResponse 200 renderMetricsStream)
  , textRoute "GET" "/api/ws/training" (EndpointResponse 200 renderTrainingStream)
  , textRoute "GET" "/api/ws/tune" (EndpointResponse 200 renderTuneStream)
  ]
    <> case bundle of
      Just js ->
        [ HttpRoute
            { httpRouteMethod = "GET"
            , httpRoutePath = "/bundle/main.js"
            , httpRouteContentType = "application/javascript; charset=utf-8"
            , httpRouteResponse = EndpointResponse 200 js
            }
        ]
      Nothing -> []

renderDemoIndex :: Text
renderDemoIndex = renderDemoIndexWithBundle Nothing

-- | HTML shell for the demo `/` route. When `Just <js>` is supplied, a
-- `<script src="/bundle/main.js">` tag is included that loads the
-- compiled Halogen bundle; otherwise the page renders the placeholder
-- bundle manifest.
renderDemoIndexWithBundle :: Maybe Text -> Text
renderDemoIndexWithBundle bundle =
  Text.unlines
    [ "<!doctype html>"
    , "<html lang=\"en\">"
    , "<head><meta charset=\"utf-8\"><title>jitML Demo</title></head>"
    , "<body>"
    , "<main id=\"app\">"
    , "<h1>jitML Demo</h1>"
    , "<pre>"
    , Bundle.renderBundleManifest
    , "</pre>"
    , case bundle of
        Just _ -> "<script type=\"module\" src=\"/bundle/main.js\"></script>"
        Nothing -> "<!-- bundle not built: run `spago build --output web/dist/` -->"
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

renderInferenceResponse :: Text
renderInferenceResponse =
  let manifest =
        Checkpoint.emptyManifest
          "demo"
          "experiments/mnist.dhall"
          [Checkpoint.TensorBlob "dense.weight" [2, 2] "blob-demo"]
   in "prediction: " <> Text.pack (show (Checkpoint.inferFromManifest manifest [0.2, 0.8])) <> "\n"

renderConnect4Response :: Text
renderConnect4Response =
  "move: "
    <> Text.pack (show firstDemoMove)
    <> "\n"
 where
  firstDemoMove =
    case AlphaZero.gameMoves (AlphaZero.applyMove 0 AlphaZero.initialConnect4) of
      move : _ -> move
      [] -> 0

renderMetricsStream :: Text
renderMetricsStream =
  Text.unlines
    [ "event: metrics"
    , "data: algorithms=" <> Text.pack (show (length RL.algorithmCatalog))
    , "data: canonicalProblems=" <> Text.pack (show (length SL.canonicalProblems))
    ]

renderTrainingStream :: Text
renderTrainingStream =
  Text.unlines
    [ "event: training"
    , "data: problem=" <> problemName
    , "data: finalLoss=" <> Text.pack (show finalLoss)
    ]
 where
  (problemName, finalLoss) =
    case SL.canonicalProblems of
      problem : _ -> (SL.problemName problem, SL.finalLoss problem)
      [] -> ("empty", 0.0)

renderTuneStream :: Text
renderTuneStream =
  Text.unlines
    [ "event: tune"
    , "data: samplers=" <> Text.pack (show (length Tune.samplerCatalog))
    , "data: schedulers=" <> Text.pack (show (length Tune.schedulerCatalog))
    , "data: pruners=" <> Text.pack (show (length Tune.prunerCatalog))
    ]

-- | Sprint 13.13 — render a Server-Sent-Events-shaped frame from a live
-- broker event payload. The browser receives @event: <domain>@ +
-- @data: <payload>@ lines and the panel JS parses them into a typed
-- 'MetricFrame'. The function is pure so the demo route table can
-- emit the same shape regardless of whether the payload came from a
-- live Pulsar consume or from a deterministic fallback frame.
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
  EndpointResponse 200 (fallbackFrame domain)
liveEventSnapshotResponse domain (Just payload) =
  EndpointResponse
    200
    ( Text.unlines
        [ "event: " <> domain
        , "data: " <> Text.replace "\n" " " payload
        ]
    )

fallbackFrame :: Text -> Text
fallbackFrame "training" = renderTrainingStream
fallbackFrame "tune" = renderTuneStream
fallbackFrame _ = renderMetricsStream

textRoute :: Text -> Text -> EndpointResponse -> HttpRoute
textRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteResponse = response
    }

htmlRoute :: Text -> Text -> EndpointResponse -> HttpRoute
htmlRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/html; charset=utf-8"
    , httpRouteResponse = response
    }

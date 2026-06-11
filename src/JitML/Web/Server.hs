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
  , serveDemoWithBridgeEndpoint
  )
where

import Control.Exception qualified
import Control.Monad.IO.Class qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Vector.Unboxed qualified as VU
import System.Directory (doesFileExist)

import JitML.Cluster.Publication qualified as Publication
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
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
serveDemoWithBridgeEndpoint host port livePublication endpointOverride = do
  bundle <- loadBundleEntry
  serveHttpRoutesWithWebSockets
    (demoListener host port)
    (demoHttpRoutesWithBundle bundle)
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
  [ htmlRoute "GET" "/" (EndpointResponse 200 (renderDemoIndexWithBundle bundle))
  , textRoute "GET" "/api" (EndpointResponse 200 renderApiIndex)
  , textRoute "POST" "/api/inference" (EndpointResponse 200 renderInferenceResponse)
  , textRoute "POST" "/api/images" (EndpointResponse 200 "accepted image upload contract\n")
  , textRoute "POST" "/api/connect4/move" (EndpointResponse 200 renderConnect4Response)
  , textRoute "GET" "/api/ws" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/training" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/rl" liveStreamUpgradeRequired
  , textRoute "GET" "/api/ws/tune" liveStreamUpgradeRequired
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

-- | Sprint 11.8 — the demo inference endpoint runs the real policy/value
-- network forward on the initial board (a genuine network forward, not the
-- former synthetic `inferFromManifest`) and reports its value-head estimate.
-- The live-cluster round-trip that serves a real /trained/ checkpoint over the
-- daemon's inference topics is the deeper version (Phase 13).
renderInferenceResponse :: Text
renderInferenceResponse =
  let net = PolicyValueNet.initPolicyValueNet 43 7 16 22
      pv = PolicyValueNet.networkPolicyValue net AlphaZero.initialConnect4
   in "prediction: value="
        <> Text.pack (show (PolicyValueNet.pvValue pv))
        <> " policy="
        <> Text.pack (show (VU.toList (PolicyValueNet.pvPolicy pv)))
        <> "\n"

-- | Sprint 11.8 — the demo Connect 4 endpoint runs the real MCTS tree search
-- (network priors + value-head backups) on the initial board and returns the
-- highest-visit move, instead of echoing a hard-coded column.
renderConnect4Response :: Text
renderConnect4Response =
  let net = PolicyValueNet.initPolicyValueNet 43 7 16 31
      visitDist = PolicyValueNet.mctsVisitDistribution net 64 AlphaZero.initialConnect4 17
   in "move: " <> Text.pack (show (VU.maxIndex visitDist)) <> "\n"

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

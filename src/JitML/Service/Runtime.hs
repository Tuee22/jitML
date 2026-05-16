{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Runtime
  ( DaemonRuntime (..)
  , daemonHttpRoutes
  , defaultDaemonRuntime
  , renderDaemonRuntimeSummary
  , serveDaemon
  , serveDaemonOnce
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , Residency (..)
  , defaultBootConfig
  , renderBootConfigDhall
  )
import JitML.Service.Endpoints
  ( EndpointResponse (..)
  , MetricsSnapshot (..)
  , healthz
  , metrics
  , readyz
  , renderEndpointResponse
  )
import JitML.Service.Http (HttpRoute (..), serveHttpRoutes, serveHttpRoutesOnce)
import JitML.Service.Lifecycle (lifecyclePlan, renderLifecyclePhase)
import JitML.Service.LiveConfig (LiveConfig, defaultLiveConfig, renderLiveConfigDhall)
import JitML.Substrate (Substrate (..))

data DaemonRuntime = DaemonRuntime
  { daemonBootConfig :: BootConfig
  , daemonLiveConfig :: LiveConfig
  , daemonMetrics :: MetricsSnapshot
  , daemonReady :: Bool
  }
  deriving stock (Eq, Show)

defaultDaemonRuntime :: DaemonRuntime
defaultDaemonRuntime =
  DaemonRuntime
    { daemonBootConfig = defaultBootConfig LinuxCPU Cluster
    , daemonLiveConfig = defaultLiveConfig
    , daemonMetrics = MetricsSnapshot 0 1 0
    , daemonReady = True
    }

daemonHttpRoutes :: DaemonRuntime -> [HttpRoute]
daemonHttpRoutes runtime =
  [ textRoute "GET" "/healthz" healthz
  , textRoute "GET" "/readyz" (readyz (daemonReady runtime))
  , textRoute "GET" "/metrics" (metrics (daemonMetrics runtime))
  , textRoute "GET" "/" (EndpointResponse 200 "jitml-service\n")
  ]

serveDaemon :: DaemonRuntime -> IO ()
serveDaemon runtime =
  serveHttpRoutes listener (daemonHttpRoutes runtime)
 where
  listener = runtimeListener runtime

serveDaemonOnce :: DaemonRuntime -> IO ()
serveDaemonOnce runtime =
  serveHttpRoutesOnce listener (daemonHttpRoutes runtime)
 where
  listener = runtimeListener runtime

renderDaemonRuntimeSummary :: DaemonRuntime -> Text
renderDaemonRuntimeSummary runtime =
  Text.unlines
    [ "lifecycle:"
    , "  - " <> Text.intercalate "\n  - " (fmap renderLifecyclePhase lifecyclePlan)
    , "boot_config:"
    , indentText (renderBootConfigDhall (daemonBootConfig runtime))
    , "live_config:"
    , indentText (renderLiveConfigDhall (daemonLiveConfig runtime))
    , "http_listener:"
    , indentText (renderListener (runtimeListener runtime))
    , "routes:"
    , "  - " <> Text.intercalate "\n  - " (fmap renderRoute (daemonHttpRoutes runtime))
    , "healthz:"
    , indentText (renderEndpointResponse healthz)
    , "readyz:"
    , indentText (renderEndpointResponse (readyz (daemonReady runtime)))
    , "metrics:"
    , indentText (renderEndpointResponse (metrics (daemonMetrics runtime)))
    ]

runtimeListener :: DaemonRuntime -> HttpListener
runtimeListener runtime =
  case bootHttpListener (daemonBootConfig runtime) of
    Just listener -> listener
    Nothing -> HttpListener "127.0.0.1" 8080

textRoute :: Text -> Text -> EndpointResponse -> HttpRoute
textRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteResponse = response
    }

renderListener :: HttpListener -> Text
renderListener listener =
  listenerHost listener <> ":" <> Text.pack (show (listenerPort listener))

renderRoute :: HttpRoute -> Text
renderRoute route =
  httpRouteMethod route <> " " <> httpRoutePath route

indentText :: Text -> Text
indentText =
  Text.unlines . fmap ("  " <>) . Text.lines

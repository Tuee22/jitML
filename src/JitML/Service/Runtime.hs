{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Runtime
  ( DaemonRuntime (..)
  , consumerLoopExit
  , daemonTensorBoardDispatcher
  , daemonHttpRoutes
  , defaultDaemonRuntime
  , renderDaemonRuntimeSummary
  , runtimeAfterSignal
  , serveDaemon
  , serveDaemonOnce
  )
where

import Control.Concurrent (myThreadId, throwTo)
import Control.Exception (AsyncException (..), catch, throwIO)
import Data.Text (Text)
import Data.Text qualified as Text

import Data.Foldable (asum)

import JitML.AppError.AppError (AppError (..))
import JitML.Observability.TbSidecar qualified as TbSidecar
import JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , Residency (..)
  , defaultBootConfig
  , renderBootConfigDhall
  )
import JitML.Service.Capabilities (ETag, HasMinIO)
import JitML.Service.Consumer
  ( ConsumerOutcome
  , EventDomain
  , EventId
  , consumerOutcomeError
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
import JitML.Service.Retry (ServiceError)
import JitML.Service.Signal
  ( DaemonSignal
  , DaemonSignalAction (..)
  , applyDaemonSignal
  , daemonSignalAction
  , newDaemonControl
  , renderDaemonSignal
  , renderDaemonSignalAction
  , signalPlan
  , withDaemonSignalHandlers
  )
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
serveDaemon runtime = do
  control <- newDaemonControl (daemonReady runtime)
  mainThread <- myThreadId
  let handleSignal signal = do
        _snapshot <- applyDaemonSignal control signal
        case daemonSignalAction signal of
          BeginGracefulDrain -> throwTo mainThread UserInterrupt
          ReloadLiveConfig -> pure ()
  withDaemonSignalHandlers handleSignal $
    serveHttpRoutes listener (daemonHttpRoutes runtime)
      `catch` handleDaemonInterrupt
 where
  listener = runtimeListener runtime

  handleDaemonInterrupt UserInterrupt = pure ()
  handleDaemonInterrupt exception = throwIO exception

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
    , "signals:"
    , "  - " <> Text.intercalate "\n  - " (fmap renderSignalPlan signalPlan)
    ]

runtimeAfterSignal :: DaemonRuntime -> DaemonSignal -> DaemonRuntime
runtimeAfterSignal runtime signal =
  case daemonSignalAction signal of
    ReloadLiveConfig -> runtime
    BeginGracefulDrain -> runtime {daemonReady = False}

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

renderSignalPlan :: (DaemonSignal, DaemonSignalAction) -> Text
renderSignalPlan (signal, action) =
  renderDaemonSignal signal <> ": " <> renderDaemonSignalAction action

indentText :: Text -> Text
indentText =
  Text.unlines . fmap ("  " <>) . Text.lines

-- | Walk the typed `ConsumerOutcome` list returned from a
-- `runConsumerLoop` batch and surface the first `AppError`. The daemon
-- lifecycle's exit path consumes this: `Nothing` means the batch is
-- entirely clean (dispatched / dedup'd / skipped), `Just err` (typically
-- `PulsarFailed`) propagates to the typed exit code per the doctrine's
-- §Capability Classes and Service Errors.
consumerLoopExit :: [ConsumerOutcome] -> Maybe AppError
consumerLoopExit = asum . fmap consumerOutcomeError

daemonTensorBoardDispatcher
  :: (HasMinIO m)
  => EventDomain
  -> EventId
  -> Text
  -> m (Either ServiceError ())
daemonTensorBoardDispatcher domain _eventId payload = do
  sideEffect <- TbSidecar.dispatchTensorBoardSideEffect domain payload
  pure (sideEffectToUnit sideEffect)

sideEffectToUnit :: Maybe (Either ServiceError ETag) -> Either ServiceError ()
sideEffectToUnit result =
  case result of
    Nothing -> Right ()
    Just (Right _) -> Right ()
    Just (Left err) -> Left err

{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Runtime
  ( DaemonRuntime (..)
  , DaemonClientProbeState (..)
  , DaemonClientProbeStatus (..)
  , DaemonSubscriptionState (..)
  , DaemonSubscriptionStatus (..)
  , acquireDaemonSubscriptions
  , daemonConsumerBatch
  , consumerLoopExit
  , daemonHandlerRouter
  , daemonTensorBoardDispatcher
  , daemonHttpRoutes
  , daemonRuntimeForBootConfig
  , defaultDaemonRuntime
  , probeDaemonServiceClients
  , renderDaemonRuntimeSummary
  , runtimeAfterSignal
  , serveDaemon
  , serveDaemonOnce
  )
where

import Control.Concurrent (myThreadId, throwTo)
import Control.Exception (AsyncException (..), catch, throwIO)
import Control.Monad.IO.Class (MonadIO)
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
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasHarbor
  , HasKubectl
  , HasMinIO
  , HasPulsar
  , ImageRef
  , KubeResource (..)
  , ObjectRef
  , SubscriptionId (..)
  , TopicName (..)
  , harborListImages
  , kubectlGet
  , listObjects
  )
import JitML.Service.Clients
  ( DaemonClientSettings
  , daemonClientSettingsForBootConfig
  , renderDaemonClientSettings
  )
import JitML.Service.Consumer
  ( ConsumerOutcome
  , DaemonSubscription (..)
  , EventDomain
  , EventId
  , HandlerRouter
  , consumerOutcomeError
  , daemonSubscriptionsForBootConfig
  , emptyHandlerRouterWithTtl
  , runConsumerLoop
  , subscribeDaemonTopics
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
import JitML.Service.LiveConfig
  ( LiveConfig
  , defaultLiveConfig
  , liveDedupCacheSize
  , liveDedupCacheTtlSeconds
  , renderLiveConfigDhall
  )
import JitML.Service.Retry (ServiceError (..))
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
  , daemonClientSettings :: DaemonClientSettings
  , daemonClientProbeStatuses :: [DaemonClientProbeStatus]
  , daemonSubscriptions :: [DaemonSubscription]
  , daemonSubscriptionStatuses :: [DaemonSubscriptionStatus]
  , daemonMetrics :: MetricsSnapshot
  , daemonReady :: Bool
  }
  deriving stock (Eq, Show)

data DaemonClientProbeState
  = DaemonClientProbePending
  | DaemonClientProbeSucceeded Text
  | DaemonClientProbeFailed ServiceError
  deriving stock (Eq, Show)

data DaemonClientProbeStatus = DaemonClientProbeStatus
  { daemonClientProbeStatusName :: Text
  , daemonClientProbeStatusState :: DaemonClientProbeState
  }
  deriving stock (Eq, Show)

data DaemonSubscriptionState
  = DaemonSubscriptionPending
  | DaemonSubscriptionAcquired SubscriptionId
  | DaemonSubscriptionFailed ServiceError
  deriving stock (Eq, Show)

data DaemonSubscriptionStatus = DaemonSubscriptionStatus
  { daemonSubscriptionStatusSubscription :: DaemonSubscription
  , daemonSubscriptionStatusState :: DaemonSubscriptionState
  }
  deriving stock (Eq, Show)

defaultDaemonRuntime :: DaemonRuntime
defaultDaemonRuntime =
  daemonRuntimeForBootConfig (defaultBootConfig LinuxCPU Cluster)

daemonRuntimeForBootConfig :: BootConfig -> DaemonRuntime
daemonRuntimeForBootConfig bootConfig =
  let subscriptions = daemonSubscriptionsForBootConfig bootConfig
   in DaemonRuntime
        { daemonBootConfig = bootConfig
        , daemonLiveConfig = defaultLiveConfig
        , daemonClientSettings = daemonClientSettingsForBootConfig bootConfig
        , daemonClientProbeStatuses = pendingClientProbeStatuses
        , daemonSubscriptions = subscriptions
        , daemonSubscriptionStatuses = pendingSubscriptionStatuses subscriptions
        , daemonMetrics = MetricsSnapshot 0 1 0
        , daemonReady = True
        }

acquireDaemonSubscriptions :: (HasPulsar m) => DaemonRuntime -> m DaemonRuntime
acquireDaemonSubscriptions runtime = do
  results <- subscribeDaemonTopics (daemonSubscriptions runtime)
  let statuses = fmap subscriptionResultStatus results
  pure
    runtime
      { daemonSubscriptionStatuses = statuses
      , daemonReady = all subscriptionAcquired statuses
      }

probeDaemonServiceClients
  :: (HasHarbor m, HasKubectl m, HasMinIO m)
  => DaemonRuntime
  -> m DaemonRuntime
probeDaemonServiceClients runtime = do
  minioResult <- listObjects daemonProbeBucket daemonProbePrefix
  harborResult <- harborListImages daemonProbeHarborProject
  kubectlResult <- kubectlGet daemonProbeKubeResource
  let statuses =
        [ minioProbeStatus minioResult
        , harborProbeStatus harborResult
        , kubectlProbeStatus kubectlResult
        ]
  pure
    runtime
      { daemonClientProbeStatuses = statuses
      , daemonReady = daemonReady runtime && all clientProbeSucceeded statuses
      }

pendingSubscriptionStatuses :: [DaemonSubscription] -> [DaemonSubscriptionStatus]
pendingSubscriptionStatuses =
  fmap (`DaemonSubscriptionStatus` DaemonSubscriptionPending)

pendingClientProbeStatuses :: [DaemonClientProbeStatus]
pendingClientProbeStatuses =
  fmap (`DaemonClientProbeStatus` DaemonClientProbePending) daemonClientProbeNames

daemonClientProbeNames :: [Text]
daemonClientProbeNames =
  [ "minio:list jitml-checkpoints"
  , "harbor:list library"
  , "kubectl:get pods"
  ]

daemonProbeBucket :: BucketName
daemonProbeBucket = BucketName "jitml-checkpoints"

daemonProbePrefix :: Text
daemonProbePrefix = "daemon-health/"

daemonProbeHarborProject :: Text
daemonProbeHarborProject = "library"

daemonProbeKubeResource :: KubeResource
daemonProbeKubeResource = KubeResource "pods"

minioProbeStatus :: Either ServiceError [ObjectRef] -> DaemonClientProbeStatus
minioProbeStatus result =
  DaemonClientProbeStatus "minio:list jitml-checkpoints" $
    case result of
      Right refs ->
        DaemonClientProbeSucceeded ("listed " <> Text.pack (show (length refs)) <> " objects")
      Left err -> DaemonClientProbeFailed err

harborProbeStatus :: Either ServiceError [ImageRef] -> DaemonClientProbeStatus
harborProbeStatus result =
  DaemonClientProbeStatus "harbor:list library" $
    case result of
      Right images ->
        DaemonClientProbeSucceeded ("listed " <> Text.pack (show (length images)) <> " images")
      Left err -> DaemonClientProbeFailed err

kubectlProbeStatus :: Either ServiceError Text -> DaemonClientProbeStatus
kubectlProbeStatus result =
  DaemonClientProbeStatus "kubectl:get pods" $
    case result of
      Right output ->
        DaemonClientProbeSucceeded
          ("received " <> Text.pack (show (length (Text.lines output))) <> " lines")
      Left err -> DaemonClientProbeFailed err

subscriptionResultStatus
  :: (DaemonSubscription, Either ServiceError SubscriptionId) -> DaemonSubscriptionStatus
subscriptionResultStatus (subscription, result) =
  DaemonSubscriptionStatus
    { daemonSubscriptionStatusSubscription = subscription
    , daemonSubscriptionStatusState =
        case result of
          Right subscriptionId -> DaemonSubscriptionAcquired subscriptionId
          Left err -> DaemonSubscriptionFailed err
    }

subscriptionAcquired :: DaemonSubscriptionStatus -> Bool
subscriptionAcquired status =
  case daemonSubscriptionStatusState status of
    DaemonSubscriptionAcquired _ -> True
    _ -> False

clientProbeSucceeded :: DaemonClientProbeStatus -> Bool
clientProbeSucceeded status =
  case daemonClientProbeStatusState status of
    DaemonClientProbeSucceeded _ -> True
    _ -> False

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
    , "client_acquisition:"
    , indentText (renderDaemonClientSettings (daemonClientSettings runtime))
    , "client_probe_status:"
    , indentText (renderDaemonClientProbeStatuses (daemonClientProbeStatuses runtime))
    , "pulsar_subscriptions:"
    , indentText (renderDaemonSubscriptions (daemonSubscriptions runtime))
    , "pulsar_subscription_status:"
    , indentText (renderDaemonSubscriptionStatuses (daemonSubscriptionStatuses runtime))
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

renderDaemonSubscriptions :: [DaemonSubscription] -> Text
renderDaemonSubscriptions [] = "(none)\n"
renderDaemonSubscriptions subscriptions =
  Text.unlines (fmap renderDaemonSubscription subscriptions)

renderDaemonSubscription :: DaemonSubscription -> Text
renderDaemonSubscription subscription =
  "- "
    <> unTopicName (daemonSubscriptionTopic subscription)
    <> " as "
    <> daemonSubscriptionName subscription

renderDaemonSubscriptionStatuses :: [DaemonSubscriptionStatus] -> Text
renderDaemonSubscriptionStatuses [] = "(none)\n"
renderDaemonSubscriptionStatuses statuses =
  Text.unlines (fmap renderDaemonSubscriptionStatus statuses)

renderDaemonSubscriptionStatus :: DaemonSubscriptionStatus -> Text
renderDaemonSubscriptionStatus status =
  "- "
    <> unTopicName (daemonSubscriptionTopic subscription)
    <> " as "
    <> daemonSubscriptionName subscription
    <> ": "
    <> renderDaemonSubscriptionState (daemonSubscriptionStatusState status)
 where
  subscription = daemonSubscriptionStatusSubscription status

renderDaemonSubscriptionState :: DaemonSubscriptionState -> Text
renderDaemonSubscriptionState DaemonSubscriptionPending = "pending"
renderDaemonSubscriptionState (DaemonSubscriptionAcquired subscriptionId) =
  "acquired " <> renderSubscriptionId subscriptionId
renderDaemonSubscriptionState (DaemonSubscriptionFailed err) =
  "failed " <> renderServiceError err

renderSubscriptionId :: SubscriptionId -> Text
renderSubscriptionId (SubscriptionId value) =
  Text.replace "\n" " " value

renderServiceError :: ServiceError -> Text
renderServiceError (SEConflict message) = "conflict: " <> message
renderServiceError (SEUnauthorized message) = "unauthorized: " <> message
renderServiceError (SETimeout message) = "timeout: " <> message
renderServiceError (SETransient message) = "transient: " <> message

renderDaemonClientProbeStatuses :: [DaemonClientProbeStatus] -> Text
renderDaemonClientProbeStatuses [] = "(none)\n"
renderDaemonClientProbeStatuses statuses =
  Text.unlines (fmap renderDaemonClientProbeStatus statuses)

renderDaemonClientProbeStatus :: DaemonClientProbeStatus -> Text
renderDaemonClientProbeStatus status =
  "- "
    <> daemonClientProbeStatusName status
    <> ": "
    <> renderDaemonClientProbeState (daemonClientProbeStatusState status)

renderDaemonClientProbeState :: DaemonClientProbeState -> Text
renderDaemonClientProbeState DaemonClientProbePending = "pending"
renderDaemonClientProbeState (DaemonClientProbeSucceeded summary) =
  "ok " <> Text.replace "\n" " " summary
renderDaemonClientProbeState (DaemonClientProbeFailed err) =
  "failed " <> renderServiceError err

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

daemonHandlerRouter :: DaemonRuntime -> HandlerRouter
daemonHandlerRouter runtime =
  emptyHandlerRouterWithTtl
    (liveDedupCacheSize (daemonLiveConfig runtime))
    (liveDedupCacheTtlSeconds (daemonLiveConfig runtime))

daemonConsumerBatch
  :: (HasPulsar m, MonadIO m)
  => DaemonRuntime
  -> Int
  -- ^ Number of envelopes to pull per acquired subscription.
  -> (EventDomain -> EventId -> Text -> m (Either ServiceError ()))
  -> m (HandlerRouter, [ConsumerOutcome])
daemonConsumerBatch runtime budget dispatch =
  go (daemonHandlerRouter runtime) [] acquiredSubscriptions
 where
  acquiredSubscriptions =
    foldMap acquiredSubscriptionId (daemonSubscriptionStatuses runtime)

  go router outcomes [] =
    pure (router, outcomes)
  go router outcomes (subscription : rest)
    | budget <= 0 =
        go router outcomes rest
    | otherwise = do
        (router', batchOutcomes) <-
          runConsumerLoop subscription router budget dispatch
        go router' (outcomes <> batchOutcomes) rest

acquiredSubscriptionId :: DaemonSubscriptionStatus -> [SubscriptionId]
acquiredSubscriptionId status =
  case daemonSubscriptionStatusState status of
    DaemonSubscriptionAcquired subscriptionId -> [subscriptionId]
    _ -> []

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

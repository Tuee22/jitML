{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Runtime
  ( DaemonRuntime (..)
  , AppleMetalAcquireStatus (..)
  , DaemonClientProbeState (..)
  , DaemonClientProbeStatus (..)
  , DaemonSubscriptionState (..)
  , DaemonSubscriptionStatus (..)
  , acquireDaemonSubscriptions
  , daemonConsumerBatch
  , consumerLoopExit
  , daemonHandlerRouter
  , daemonTensorBoardDispatcher
  , daemonWorkloadDispatcher
  , daemonWorkloadDispatcherForwardingInference
  , daemonWorkloadDispatcherHostingAppleInference
  , daemonWorkloadDispatcherWithInference
  , daemonWorkloadDispatcherWithWeightedInference
  , daemonHttpRoutes
  , daemonRuntimeForBootConfig
  , defaultDaemonRuntime
  , probeDaemonServiceClients
  , renderConsumerOutcomes
  , renderDaemonRuntimeSummary
  , runtimeAfterSignal
  , serveDaemon
  , serveDaemonOnce
  )
where

import Control.Concurrent (myThreadId, threadDelay, throwTo)
import Control.Exception (AsyncException (..), catch, throwIO)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (MonadIO)
import Data.Text (Text)
import Data.Text qualified as Text

import Data.Foldable (asum)

import JitML.AppError.AppError (AppError (..))
import JitML.Checkpoint.Format (CheckpointManifest)
import JitML.Observability.TbSidecar qualified as TbSidecar
import JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , InferenceMode (..)
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
  , pulsarPublish
  )
import JitML.Service.Clients
  ( DaemonClientSettings
  , daemonClientSettingsForBootConfig
  , renderDaemonClientSettings
  )
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonSubscription (..)
  , EventDomain (..)
  , EventId (..)
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
import JitML.Service.Workload qualified as Workload
import JitML.Substrate (Substrate (..))

import JitML.Proto.Inference
  ( AppleInferenceCommand
  , InferenceRequest (..)
  , inferenceResultTopic
  , parseAppleInferenceCommand
  , parseAppleInferenceEvent
  , parseInferenceRequest
  )
import JitML.Service.AppleInferenceRpc qualified as AppleRpc

data DaemonRuntime = DaemonRuntime
  { daemonBootConfig :: BootConfig
  , daemonLiveConfig :: LiveConfig
  , daemonAppleMetalAcquireStatus :: AppleMetalAcquireStatus
  , daemonClientSettings :: DaemonClientSettings
  , daemonClientProbeStatuses :: [DaemonClientProbeStatus]
  , daemonSubscriptions :: [DaemonSubscription]
  , daemonSubscriptionStatuses :: [DaemonSubscriptionStatus]
  , daemonMetrics :: MetricsSnapshot
  , daemonReady :: Bool
  }
  deriving stock (Eq, Show)

data AppleMetalAcquireStatus
  = AppleMetalAcquireNotRequired
  | AppleMetalAcquirePending
  | AppleMetalAcquireSucceeded Text
  | AppleMetalAcquireFailed Text
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
        , daemonAppleMetalAcquireStatus = appleMetalAcquireInitialStatus bootConfig
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

appleMetalAcquireInitialStatus :: BootConfig -> AppleMetalAcquireStatus
appleMetalAcquireInitialStatus bootConfig =
  case (bootSubstrate bootConfig, bootInferenceMode bootConfig) of
    (AppleSilicon, SelfInference) -> AppleMetalAcquirePending
    _ -> AppleMetalAcquireNotRequired

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
    runDaemon
      `catch` handleDaemonInterrupt
 where
  runDaemon =
    case runtimeListener runtime of
      Just listener -> serveHttpRoutes listener (daemonHttpRoutes runtime)
      Nothing -> forever (threadDelay maxBound)

  handleDaemonInterrupt UserInterrupt = pure ()
  handleDaemonInterrupt exception = throwIO exception

serveDaemonOnce :: DaemonRuntime -> IO ()
serveDaemonOnce runtime =
  case runtimeListener runtime of
    Just listener -> serveHttpRoutesOnce listener (daemonHttpRoutes runtime)
    Nothing -> pure ()

renderDaemonRuntimeSummary :: DaemonRuntime -> Text
renderDaemonRuntimeSummary runtime =
  Text.unlines
    [ "lifecycle:"
    , "  - " <> Text.intercalate "\n  - " (fmap renderLifecyclePhase lifecyclePlan)
    , "boot_config:"
    , indentText (renderBootConfigDhall (daemonBootConfig runtime))
    , "live_config:"
    , indentText (renderLiveConfigDhall (daemonLiveConfig runtime))
    , "apple_metal_acquire:"
    , indentText (renderAppleMetalAcquireStatus (daemonAppleMetalAcquireStatus runtime))
    , "client_acquisition:"
    , indentText (renderDaemonClientSettings (daemonClientSettings runtime))
    , "client_probe_status:"
    , indentText (renderDaemonClientProbeStatuses (daemonClientProbeStatuses runtime))
    , "pulsar_subscriptions:"
    , indentText (renderDaemonSubscriptions (daemonSubscriptions runtime))
    , "pulsar_subscription_status:"
    , indentText (renderDaemonSubscriptionStatuses (daemonSubscriptionStatuses runtime))
    , "http_listener:"
    , indentText (renderMaybeListener (runtimeListener runtime))
    , "routes:"
    , indentText (renderRoutes (runtimeListener runtime) (daemonHttpRoutes runtime))
    , "healthz:"
    , indentText (renderEndpointResponse healthz)
    , "readyz:"
    , indentText (renderEndpointResponse (readyz (daemonReady runtime)))
    , "metrics:"
    , indentText (renderEndpointResponse (metrics (daemonMetrics runtime)))
    , "signals:"
    , "  - " <> Text.intercalate "\n  - " (fmap renderSignalPlan signalPlan)
    ]

renderAppleMetalAcquireStatus :: AppleMetalAcquireStatus -> Text
renderAppleMetalAcquireStatus AppleMetalAcquireNotRequired = "not_required"
renderAppleMetalAcquireStatus AppleMetalAcquirePending = "pending"
renderAppleMetalAcquireStatus (AppleMetalAcquireSucceeded message) = "ok " <> message
renderAppleMetalAcquireStatus (AppleMetalAcquireFailed message) = "failed " <> message

runtimeAfterSignal :: DaemonRuntime -> DaemonSignal -> DaemonRuntime
runtimeAfterSignal runtime signal =
  case daemonSignalAction signal of
    ReloadLiveConfig -> runtime
    BeginGracefulDrain -> runtime {daemonReady = False}

runtimeListener :: DaemonRuntime -> Maybe HttpListener
runtimeListener runtime =
  bootHttpListener (daemonBootConfig runtime)

textRoute :: Text -> Text -> EndpointResponse -> HttpRoute
textRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteHandler = \_request -> pure response
    }

renderMaybeListener :: Maybe HttpListener -> Text
renderMaybeListener Nothing = "(none)"
renderMaybeListener (Just listener) =
  listenerHost listener <> ":" <> Text.pack (show (listenerPort listener))

renderRoutes :: Maybe HttpListener -> [HttpRoute] -> Text
renderRoutes Nothing _ = "(none)"
renderRoutes (Just _) routes =
  "- " <> Text.intercalate "\n- " (fmap renderRoute routes)

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

renderConsumerOutcomes :: [ConsumerOutcome] -> Text
renderConsumerOutcomes [] = "(none)\n"
renderConsumerOutcomes outcomes =
  Text.unlines (fmap renderConsumerOutcome outcomes)

renderConsumerOutcome :: ConsumerOutcome -> Text
renderConsumerOutcome outcome =
  case outcome of
    ConsumerDispatched domain eventId ->
      "dispatched " <> renderEventDomain domain <> " " <> unEventId eventId
    ConsumerDeduplicated domain eventId ->
      "deduplicated " <> renderEventDomain domain <> " " <> unEventId eventId
    ConsumerSkippedUnroutable topic ->
      "skipped-unroutable " <> topic
    ConsumerError err ->
      "error " <> renderServiceError err

renderEventDomain :: EventDomain -> Text
renderEventDomain domain =
  case domain of
    TrainingDomain -> "training"
    TuneDomain -> "tune"
    RlDomain -> "rl"
    InferenceDomain -> "inference"

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

daemonWorkloadDispatcher
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => EventDomain
  -> EventId
  -> Text
  -> m (Either ServiceError ())
daemonWorkloadDispatcher domain _eventId payload = do
  effectResult <- Workload.dispatchWorkloadPayload payload
  case effectResult of
    Just result ->
      pure (workloadEffectToUnit (Just result))
    Nothing ->
      workloadEffectsToUnit <$> Workload.dispatchDomainPayload domain payload

daemonWorkloadDispatcherWithInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> EventDomain
  -> EventId
  -> Text
  -> m (Either ServiceError ())
daemonWorkloadDispatcherWithInference runInference domain _eventId payload = do
  effectResult <- Workload.dispatchWorkloadPayloadWithInference runInference payload
  case effectResult of
    Just result ->
      pure (workloadEffectToUnit (Just result))
    Nothing ->
      workloadEffectsToUnit <$> Workload.dispatchDomainPayloadWithInference runInference domain payload

-- | Sprint 13.11 — daemon dispatch variant that threads the weighted inference
-- callback (`CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> ...`)
-- so the substrate-bound runners can consume real `.jmw1`-decoded weight
-- tensors instead of the removed manifest-only summary path. Used by
-- `daemonWorkloadDispatcherForRuntime` whenever the loaded `BootConfig`
-- requests `SelfInference` on `LinuxCPU` or `LinuxCUDA`.
daemonWorkloadDispatcherWithWeightedInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => ( CheckpointManifest
       -> [Workload.LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> EventDomain
  -> EventId
  -> Text
  -> m (Either ServiceError ())
daemonWorkloadDispatcherWithWeightedInference runInference domain _eventId payload = do
  effectResult <- Workload.dispatchWorkloadPayloadWithWeightedInference runInference payload
  case effectResult of
    Just result ->
      pure (workloadEffectToUnit (Just result))
    Nothing ->
      workloadEffectsToUnit
        <$> Workload.dispatchDomainPayloadWithWeightedInference runInference domain payload

-- | Sprint 14.4 — cluster-side `ForwardToHost` inference dispatch. Instead of
-- running inference in-cluster, the daemon publishes an `AppleInferenceCommand`
-- on `inference.command.apple-silicon` (via "JitML.Service.AppleInferenceRpc")
-- for the host-native Apple daemon to execute on Metal; the reply event is
-- correlated separately on `inference.event.apple-silicon`. Non-inference
-- payloads fall through to the standard workload dispatcher.
daemonWorkloadDispatcherForwardingInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => EventDomain
  -> EventId
  -> Text
  -> m (Either ServiceError ())
daemonWorkloadDispatcherForwardingInference domain eventId payload =
  case parseAppleInferenceEvent payload of
    -- Closing leg: a host reply event arriving on inference.event.apple-silicon
    -- is correlated (it self-identifies by call-id) and republished to the
    -- client result topic for the frontend. Stateless — the event carries its
    -- own call-id and output references.
    Just _event ->
      void <$> pulsarPublish (TopicName (inferenceResultTopic AppleSilicon)) payload
    Nothing ->
      case parseInferenceRequest payload of
        Just request -> do
          let plan = AppleRpc.appleInferenceRpcPlan (irExperimentHash request) request
          void <$> AppleRpc.publishAppleInferenceRpcCommand plan
        Nothing ->
          daemonWorkloadDispatcher domain eventId payload

-- | Sprint 14.4 — host-native Apple daemon dispatch. When a message off
-- `inference.command.apple-silicon` parses as an `AppleInferenceCommand` (a
-- cluster `ForwardToHost` forward), run it through `handleAppleInferenceCommand`
-- (the injected runner executes the Metal kernel and stages its output to MinIO,
-- returning the output refs) and publish the `AppleInferenceEvent` reply on
-- `inference.event.apple-silicon`. Anything else (a direct `RunInference`) falls
-- through to the weighted self-inference dispatcher.
daemonWorkloadDispatcherHostingAppleInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => (AppleInferenceCommand -> m (Either Text [Text]))
  -> ( CheckpointManifest
       -> [Workload.LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> EventDomain
  -> EventId
  -> Text
  -> m (Either ServiceError ())
daemonWorkloadDispatcherHostingAppleInference runAppleCommand runWeighted domain eventId payload =
  case parseAppleInferenceCommand payload of
    Just command -> do
      event <- AppleRpc.handleAppleInferenceCommand runAppleCommand command
      void <$> AppleRpc.publishAppleInferenceEvent event
    Nothing ->
      daemonWorkloadDispatcherWithWeightedInference runWeighted domain eventId payload

workloadEffectToUnit
  :: Maybe (Either ServiceError Workload.WorkloadEffectResult)
  -> Either ServiceError ()
workloadEffectToUnit result =
  case result of
    Nothing -> Right ()
    Just (Right _) -> Right ()
    Just (Left err) -> Left err

workloadEffectsToUnit
  :: [Either ServiceError Workload.WorkloadEffectResult] -> Either ServiceError ()
workloadEffectsToUnit [] = Right ()
workloadEffectsToUnit (result : rest) =
  case result of
    Left err -> Left err
    Right _ -> workloadEffectsToUnit rest

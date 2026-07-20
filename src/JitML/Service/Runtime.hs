{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Runtime
  ( DaemonRuntime (..)
  , AppleMetalAcquireStatus (..)
  , AppleHostWorkloadStopMode (..)
  , AppleHostWorkloadAction (..)
  , WorkflowStatusProjectionMode (..)
  , DaemonClientProbeState (..)
  , DaemonClientProbeStatus (..)
  , daemonReady
  , daemonConsumerSessionTransition
  , daemonConsumerBatch
  , consumerLoopExit
  , daemonHandlerRouter
  , daemonWorkloadDispatcher
  , daemonWorkloadDispatcherForwardingInference
  , daemonWorkloadDispatcherHostingAppleInference
  , daemonWorkloadDispatcherWithInference
  , daemonWorkloadDispatcherWithWeightedInference
  , appleHostWorkloadActionKey
  , executeAppleHostWorkloadStart
  , executeAppleHostWorkloadStop
  , planAppleHostWorkloadAction
  , applyWorkflowStatusProjectionResult
  , workflowStatusProjectionMode
  , validateDaemonWorkloadDispatchRole
  , validateDaemonCommandDispatchRole
  , daemonHttpRoutes
  , daemonRuntimeForConfigs
  , daemonRuntimeForBootConfig
  , defaultDaemonRuntime
  , probeCoordinatorServiceClients
  , probeEngineServiceClients
  , renderConsumerOutcomes
  , renderDaemonRuntimeSummary
  , runtimeAfterSignal
  , runDaemonWithReloadAndDrain
  , serveDaemon
  , serveDaemonWithDrain
  , serveDaemonWithReloadAndDrain
  , serveDaemonOnce
  )
where

import Control.Concurrent
  ( modifyMVar_
  , newEmptyMVar
  , newMVar
  , takeMVar
  , threadDelay
  , tryPutMVar
  )
import Control.Concurrent.Async (waitEitherCatch, withAsync)
import Control.Exception (throwIO)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (MonadIO)
import Data.Either (fromRight)
import Data.Foldable (asum)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.AppError.AppError (AppError (..))
import JitML.Checkpoint.Format (CheckpointManifest)
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Coordinator.Topology
  ( ProtocolRoute (InferenceHostCommandRoute, InferenceRequestRoute)
  , Topic
  , topicFor
  )
import JitML.Proto.Inference (InferenceCommand)
import JitML.Proto.Rl
  ( RlCommand (..)
  , StartAlphaZeroRun (..)
  , StartRLRun (..)
  , StopRLRun (..)
  )
import JitML.Proto.Training
  ( StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  )
import JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , TuneCommand (..)
  )
import JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , InferenceMode (..)
  , Residency (..)
  , Role (..)
  , defaultBootConfig
  , renderBootConfigDhall
  )
import JitML.Service.Capabilities
  ( BucketName (..)
  , ConsumerSessionEvent (..)
  , HasHarbor
  , HasKubectl
  , HasMinIO
  , HasPulsar
  , ImageRef
  , KubeResource (..)
  , ObjectRef
  , harborListImages
  , kubectlGet
  , listObjects
  , pulsarPublish
  )
import JitML.Service.Clients
  ( DaemonRoleClientSettings
  , daemonRoleClientSettingsForBootConfig
  , renderDaemonRoleClientSettings
  )
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonCommand (..)
  , DaemonSubscription
  , EventDomain (..)
  , EventId
  , HandlerRouter
  , consumerOutcomeError
  , daemonCommandDomain
  , daemonSubscriptionName
  , daemonSubscriptionTopicName
  , daemonSubscriptionsForBootConfig
  , emptyHandlerRouterWithTtl
  , eventIdText
  , runConsumerLoop
  )
import JitML.Service.Endpoints
  ( EndpointResponse (..)
  , MetricsSnapshot (..)
  , healthz
  , metrics
  , readyz
  , renderEndpointResponse
  )
import JitML.Service.HostWorkloadRegistry
  ( HostWorkloadFamily (..)
  , HostWorkloadKey
  , HostWorkloadOutcome (..)
  , HostWorkloadRegistry
  , HostWorkloadRegistryError
  , drainHostWorkloadForEvent
  , joinedHostWorkloadOutcome
  , refineHostWorkloadKey
  , renderHostWorkloadRegistryError
  , startHostWorkload
  , stopHostWorkloadForEvent
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
import JitML.Service.RoleLifecycle
  ( profileComputes
  , profileOwnsTopics
  , profileServesWebsocket
  , roleLabel
  , roleProfile
  )
import JitML.Service.RuntimeState
  ( DaemonState
  , beginDaemonDrain
  , daemonStateDetail
  , daemonStateLabel
  , daemonStateReady
  , initialDaemonStateWithTopicFamily
  , recordClientProbeFailure
  , recordClientProbesSucceeded
  , recordConsumerConnected
  , recordConsumerDisconnected
  , recordRuntimeFailure
  )
import JitML.Service.Signal
  ( DaemonControl
  , DaemonControlSnapshot (snapshotDaemonState)
  , DaemonSignal (..)
  , DaemonSignalAction (..)
  , applyDaemonSignal
  , daemonSignalAction
  , newDaemonControlWithLiveConfig
  , readDaemonControl
  , renderDaemonSignal
  , renderDaemonSignalAction
  , signalPlan
  , withDaemonSignalHandlers
  )
import JitML.Service.Workload qualified as Workload
import JitML.Substrate (Substrate (..))

data DaemonRuntime = DaemonRuntime
  { daemonBootConfig :: BootConfig
  , daemonLiveConfig :: LiveConfig
  , daemonAppleMetalAcquireStatus :: AppleMetalAcquireStatus
  , daemonClientSettings :: DaemonRoleClientSettings
  , daemonClientProbeStatuses :: [DaemonClientProbeStatus]
  , daemonSubscriptions :: [DaemonSubscription]
  , daemonMetrics :: MetricsSnapshot
  , daemonState :: DaemonState
  }
  deriving stock (Eq, Show)

data AppleMetalAcquireStatus
  = AppleMetalAcquireNotRequired
  | AppleMetalAcquirePending
  | AppleMetalAcquireSucceeded Text
  | AppleMetalAcquireFailed Text
  deriving stock (Eq, Show)

-- | A host-Apple command that has a real executable effect. Training, Tune,
-- and RL Starts are registered under their action key before execution. Stops
-- carry the same refined key plus their cancel-or-drain intent and can only be
-- acknowledged after the registry returns the corresponding joined receipt.
-- AlphaZero belongs to the RL family.
data AppleHostWorkloadStopMode
  = CancelAppleHostWorkload
  | DrainAppleHostWorkload
  deriving stock (Eq, Show)

data AppleHostWorkloadAction
  = RunAppleHostTraining StartTraining
  | RunAppleHostTune StartSweep
  | RunAppleHostRl StartRLRun
  | RunAppleHostAlphaZero StartAlphaZeroRun
  | StopAppleHostWorkload AppleHostWorkloadStopMode HostWorkloadKey
  | RunAppleHostInference InferenceCommand
  deriving stock (Eq, Show)

-- | Decide whether command dispatch may ignore workflow-status publication.
-- The Apple Coordinator must not project a Stop that it only forwarded, while
-- the host Engine may acknowledge a Stop only after its joined terminal state
-- has been published. Every other projection remains a best-effort overlay.
data WorkflowStatusProjectionMode
  = SkipWorkflowStatusProjection
  | BestEffortWorkflowStatusProjection
  | RequireWorkflowStatusProjection
  deriving stock (Eq, Show)

workflowStatusProjectionMode
  :: BootConfig
  -> DaemonCommand
  -> WorkflowStatusProjectionMode
workflowStatusProjectionMode bootConfig command
  | commandIsStop command
  , bootActiveRole bootConfig == Coordinator
  , bootSubstrate bootConfig == AppleSilicon =
      SkipWorkflowStatusProjection
  | commandIsStop command
  , bootActiveRole bootConfig == Engine
  , bootSubstrate bootConfig == AppleSilicon
  , bootResidency bootConfig == Host =
      RequireWorkflowStatusProjection
  | otherwise = BestEffortWorkflowStatusProjection

-- | Apply the acknowledgement policy to a completed publication attempt.
-- Required terminal evidence preserves the exact failure; overlay publication
-- failures are deliberately ignored.
applyWorkflowStatusProjectionResult
  :: WorkflowStatusProjectionMode
  -> Either ServiceError ()
  -> Either ServiceError ()
applyWorkflowStatusProjectionResult mode publicationResult =
  case mode of
    RequireWorkflowStatusProjection -> publicationResult
    SkipWorkflowStatusProjection -> Right ()
    BestEffortWorkflowStatusProjection -> Right ()

commandIsStop :: DaemonCommand -> Bool
commandIsStop command =
  case command of
    TrainingDaemonCommand _ (TrainingStop _) -> True
    TuneDaemonCommand _ (TuneStop _) -> True
    RlDaemonCommand _ (RlStop _) -> True
    _ -> False

-- | Refine a decoded daemon command to the closed set the Apple host can
-- execute. Workload identities are refined before any effect can start.
planAppleHostWorkloadAction
  :: DaemonCommand
  -> Either ServiceError AppleHostWorkloadAction
planAppleHostWorkloadAction command =
  case command of
    TrainingDaemonCommand _ (TrainingStart start) -> do
      _ <- plannedHostWorkloadKey TrainingWorkload (stExperimentHash start)
      Right (RunAppleHostTraining start)
    TrainingDaemonCommand _ (TrainingStop stop) -> do
      key <- plannedHostWorkloadKey TrainingWorkload (stopExperimentHash stop)
      Right
        ( StopAppleHostWorkload
            (if stopDrain stop then DrainAppleHostWorkload else CancelAppleHostWorkload)
            key
        )
    TuneDaemonCommand _ (TuneStart start) -> do
      _ <- plannedHostWorkloadKey TuneWorkload (ssExperimentHash start)
      Right (RunAppleHostTune start)
    TuneDaemonCommand _ (TuneStop stop) ->
      StopAppleHostWorkload CancelAppleHostWorkload
        <$> plannedHostWorkloadKey TuneWorkload (ssStopExperimentHash stop)
    RlDaemonCommand _ (RlStart start) -> do
      _ <- plannedHostWorkloadKey RlWorkload (srlExperimentHash start)
      Right (RunAppleHostRl start)
    RlDaemonCommand _ (RlStartAlphaZero start) -> do
      _ <- plannedHostWorkloadKey RlWorkload (sazExperimentHash start)
      Right (RunAppleHostAlphaZero start)
    RlDaemonCommand _ (RlStop stop) -> do
      key <- plannedHostWorkloadKey RlWorkload (srStopExperimentHash stop)
      Right
        ( StopAppleHostWorkload
            (if srStopDrain stop then DrainAppleHostWorkload else CancelAppleHostWorkload)
            key
        )
    InferenceDaemonCommand _ inference ->
      Right (RunAppleHostInference inference)

-- | Recover the registry key for an executable workload action. Inference is
-- deliberately outside this registry because it is request-scoped rather than
-- a long-lived host workload.
appleHostWorkloadActionKey
  :: AppleHostWorkloadAction
  -> Either HostWorkloadRegistryError (Maybe HostWorkloadKey)
appleHostWorkloadActionKey action =
  case action of
    RunAppleHostTraining start ->
      Just <$> refineHostWorkloadKey TrainingWorkload (stExperimentHash start)
    RunAppleHostTune start ->
      Just <$> refineHostWorkloadKey TuneWorkload (ssExperimentHash start)
    RunAppleHostRl start ->
      Just <$> refineHostWorkloadKey RlWorkload (srlExperimentHash start)
    RunAppleHostAlphaZero start ->
      Just <$> refineHostWorkloadKey RlWorkload (sazExperimentHash start)
    StopAppleHostWorkload _mode key -> Right (Just key)
    RunAppleHostInference _inference -> Right Nothing

-- | Register one planned Apple-host Start before its real action can execute.
-- A missing registry, a non-Start action, or an invalid key fails closed and
-- leaves the supplied action untouched. The registry's gated worker makes the
-- handle visible before releasing the action, so a concurrent Stop can never
-- race an unregistered workload.
executeAppleHostWorkloadStart
  :: Maybe HostWorkloadRegistry
  -> AppleHostWorkloadAction
  -> IO ()
  -> IO (Either ServiceError ())
executeAppleHostWorkloadStart Nothing _action _workload =
  pure
    ( Left
        ( SEConflict
            "host workload Start requires the persistent Apple host registry"
        )
    )
executeAppleHostWorkloadStart (Just registry) action workload =
  case appleHostWorkloadStartKey action of
    Left registryError ->
      pure (Left (SEConflict (renderHostWorkloadRegistryError registryError)))
    Right Nothing ->
      pure (Left (SEConflict "host workload Start action has no registry key"))
    Right (Just key) -> do
      registered <- startHostWorkload registry key workload
      pure $
        case registered of
          Left registryError ->
            Left (SEConflict (renderHostWorkloadRegistryError registryError))
          Right _receipt -> Right ()

appleHostWorkloadStartKey
  :: AppleHostWorkloadAction
  -> Either HostWorkloadRegistryError (Maybe HostWorkloadKey)
appleHostWorkloadStartKey action =
  case action of
    RunAppleHostTraining {} -> appleHostWorkloadActionKey action
    RunAppleHostTune {} -> appleHostWorkloadActionKey action
    RunAppleHostRl {} -> appleHostWorkloadActionKey action
    RunAppleHostAlphaZero {} -> appleHostWorkloadActionKey action
    StopAppleHostWorkload {} -> Right Nothing
    RunAppleHostInference {} -> Right Nothing

-- | Execute the production Apple-host Stop decision against the persistent
-- keyed registry. A cancel must observe the cancellation tombstone; a drain
-- must observe natural success. The event-bound registry operation retains a
-- successful joined receipt for same-event redelivery after a required status
-- publication failure, while a distinct event sees the terminal tombstone.
executeAppleHostWorkloadStop
  :: Maybe HostWorkloadRegistry
  -> EventId
  -> AppleHostWorkloadStopMode
  -> HostWorkloadKey
  -> IO (Either ServiceError ())
executeAppleHostWorkloadStop Nothing _eventId _mode _key =
  pure
    ( Left
        ( SEConflict
            "host workload Stop requires the persistent Apple host registry"
        )
    )
executeAppleHostWorkloadStop (Just registry) eventId mode key = do
  stopped <- stopOperation registry eventId key
  pure $
    case stopped of
      Left registryError ->
        Left (SEConflict (renderHostWorkloadRegistryError registryError))
      Right joined
        | joinedHostWorkloadOutcome joined == expectedOutcome -> Right ()
        | otherwise ->
            Left
              ( SEConflict
                  ( "host workload Stop joined with an unexpected outcome: "
                      <> Text.pack (show (joinedHostWorkloadOutcome joined))
                  )
              )
 where
  (stopOperation, expectedOutcome) =
    case mode of
      CancelAppleHostWorkload ->
        (stopHostWorkloadForEvent, HostWorkloadCancelled)
      DrainAppleHostWorkload ->
        (drainHostWorkloadForEvent, HostWorkloadSucceeded)

plannedHostWorkloadKey
  :: HostWorkloadFamily
  -> Text
  -> Either ServiceError HostWorkloadKey
plannedHostWorkloadKey family experimentHash =
  case refineHostWorkloadKey family experimentHash of
    Left registryError ->
      Left
        ( SEConflict
            ( "host Apple workload key refinement failed: "
                <> renderHostWorkloadRegistryError registryError
            )
        )
    Right key -> Right key

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

defaultDaemonRuntime :: DaemonRuntime
defaultDaemonRuntime =
  daemonRuntimeForBootConfig (defaultBootConfig LinuxCPU Cluster)

daemonRuntimeForBootConfig :: BootConfig -> DaemonRuntime
daemonRuntimeForBootConfig bootConfig =
  daemonRuntimeForConfigs bootConfig defaultLiveConfig

daemonRuntimeForConfigs :: BootConfig -> LiveConfig -> DaemonRuntime
daemonRuntimeForConfigs bootConfig liveConfig =
  let subscriptionResult = daemonSubscriptionsForBootConfig bootConfig
      subscriptions = fromRight [] subscriptionResult
      initialState =
        initialDaemonStateWithTopicFamily
          (appleMetalRequired bootConfig)
          (expectedTopicFamily bootConfig)
          ( case subscriptionResult of
              Left err -> ["invalid-subscription-plan:" <> Text.pack (show err)]
              Right _ -> fmap daemonSubscriptionTopicName subscriptions
          )
          (daemonClientProbeNames bootConfig)
      plannedState =
        case subscriptionResult of
          Left err -> recordRuntimeFailure (Text.pack (show err)) initialState
          Right _ -> initialState
   in DaemonRuntime
        { daemonBootConfig = bootConfig
        , daemonLiveConfig = liveConfig
        , daemonAppleMetalAcquireStatus = appleMetalAcquireInitialStatus bootConfig
        , daemonClientSettings = daemonRoleClientSettingsForBootConfig bootConfig
        , daemonClientProbeStatuses = pendingClientProbeStatuses bootConfig
        , daemonSubscriptions = subscriptions
        , daemonMetrics = MetricsSnapshot 0 1 0
        , daemonState = plannedState
        }

-- | Engine acquire probes only its MinIO artifact capability. This narrower
-- signature is what allows the production Engine interpreter to omit Harbor
-- and kubectl instances entirely.
probeEngineServiceClients
  :: (HasMinIO m)
  => DaemonRuntime
  -> m DaemonRuntime
probeEngineServiceClients runtime = do
  minioResult <- listObjects daemonProbeBucket daemonProbePrefix
  pure (applyClientProbeStatuses [minioProbeStatus minioResult] runtime)

-- | Coordinator acquire owns the cluster-orchestration probes.
probeCoordinatorServiceClients
  :: (HasHarbor m, HasKubectl m, HasMinIO m)
  => DaemonRuntime
  -> m DaemonRuntime
probeCoordinatorServiceClients runtime = do
  minioResult <- listObjects daemonProbeBucket daemonProbePrefix
  harborResult <- harborListImages daemonProbeHarborProject
  kubectlResult <- kubectlGet daemonProbeKubeResource
  pure
    ( applyClientProbeStatuses
        [ minioProbeStatus minioResult
        , harborProbeStatus harborResult
        , kubectlProbeStatus kubectlResult
        ]
        runtime
    )

applyClientProbeStatuses
  :: [DaemonClientProbeStatus]
  -> DaemonRuntime
  -> DaemonRuntime
applyClientProbeStatuses statuses runtime =
  runtime
    { daemonClientProbeStatuses = statuses
    , daemonState =
        case firstFailedClientProbe statuses of
          Just (probe, err) ->
            recordClientProbeFailure probe (renderServiceError err) (daemonState runtime)
          Nothing ->
            recordClientProbesSucceeded
              (fmap daemonClientProbeStatusName statuses)
              (daemonState runtime)
    }

pendingClientProbeStatuses :: BootConfig -> [DaemonClientProbeStatus]
pendingClientProbeStatuses bootConfig =
  fmap
    (`DaemonClientProbeStatus` DaemonClientProbePending)
    (daemonClientProbeNames bootConfig)

daemonClientProbeNames :: BootConfig -> [Text]
daemonClientProbeNames bootConfig =
  case bootActiveRole bootConfig of
    Engine -> ["minio:list jitml-checkpoints"]
    Coordinator ->
      [ "minio:list jitml-checkpoints"
      , "harbor:list library"
      , "kubectl:get pods"
      ]
    Webapp -> []

expectedTopicFamily :: BootConfig -> [Text]
expectedTopicFamily bootConfig =
  case bootActiveRole bootConfig of
    Coordinator -> fmap PulsarBootstrap.topicName PulsarBootstrap.pulsarTopics
    Engine -> []
    Webapp -> []

appleMetalAcquireInitialStatus :: BootConfig -> AppleMetalAcquireStatus
appleMetalAcquireInitialStatus bootConfig =
  case (bootSubstrate bootConfig, bootInferenceMode bootConfig) of
    (AppleSilicon, SelfInference) -> AppleMetalAcquirePending
    _ -> AppleMetalAcquireNotRequired

appleMetalRequired :: BootConfig -> Bool
appleMetalRequired bootConfig =
  case (bootSubstrate bootConfig, bootInferenceMode bootConfig) of
    (AppleSilicon, SelfInference) -> True
    _ -> False

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

firstFailedClientProbe
  :: [DaemonClientProbeStatus]
  -> Maybe (Text, ServiceError)
firstFailedClientProbe [] = Nothing
firstFailedClientProbe (status : rest) =
  case daemonClientProbeStatusState status of
    DaemonClientProbeFailed err -> Just (daemonClientProbeStatusName status, err)
    _ -> firstFailedClientProbe rest

daemonReady :: DaemonRuntime -> Bool
daemonReady =
  daemonStateReady . daemonState

daemonConsumerSessionTransition
  :: DaemonSubscription
  -> ConsumerSessionEvent
  -> DaemonState
  -> DaemonState
daemonConsumerSessionTransition subscription sessionEvent state =
  case sessionEvent of
    ConsumerSessionConnected generation ->
      recordConsumerConnected topic generation state
    ConsumerSessionDisconnected detail ->
      recordConsumerDisconnected topic detail state
    ConsumerSessionDraining ->
      recordConsumerDisconnected topic "consumer session is draining" state
    ConsumerSessionDrained ->
      recordConsumerDisconnected topic "consumer session drained" state
 where
  topic = daemonSubscriptionTopicName subscription

daemonHttpRoutes :: DaemonControl -> DaemonRuntime -> [HttpRoute]
daemonHttpRoutes control runtime =
  [ textRoute "GET" "/healthz" healthz
  , liveReadyRoute control
  , textRoute "GET" "/metrics" (metrics (daemonMetrics runtime))
  , textRoute "GET" "/" (EndpointResponse 200 "jitml-service\n")
  ]

serveDaemon :: DaemonControl -> DaemonRuntime -> IO ()
serveDaemon control runtime =
  serveDaemonWithDrain control runtime (pure ())

-- | Serve live endpoints until a termination signal begins graceful drain.
-- Readiness changes atomically in the signal callback, while the listener stays
-- up for the supplied drain action so orchestrators can observe @/readyz = 503@
-- throughout in-flight settlement. The listener closes only after draining
-- completes (or the serving thread fails).
serveDaemonWithDrain :: DaemonControl -> DaemonRuntime -> IO () -> IO ()
serveDaemonWithDrain control runtime drainAction =
  void
    ( serveDaemonWithReloadAndDrain
        control
        runtime
        (pure Nothing)
        drainAction
    )

-- | Serve until a termination signal or a reload result requiring restart.
-- SIGHUP work is serialized outside the POSIX state transition: only the
-- supplied reload action may apply a new LiveConfig generation. A typed reload
-- failure requests the same graceful drain as SIGTERM and is returned after
-- the listener has remained up for that drain, allowing the caller to render a
-- non-zero 'AppError'.
serveDaemonWithReloadAndDrain
  :: DaemonControl
  -> DaemonRuntime
  -> IO (Maybe AppError)
  -> IO ()
  -> IO (Maybe AppError)
serveDaemonWithReloadAndDrain control runtime =
  runDaemonWithReloadAndDrain control runDaemon
 where
  runDaemon =
    case runtimeListener runtime of
      Just listener -> serveHttpRoutes listener (daemonHttpRoutes control runtime)
      Nothing -> forever (threadDelay maxBound)

-- | Apply the daemon's reload/drain signal contract around an arbitrary
-- role-specific server. Leaving the structured async scope cancels and joins
-- the server after the drain action, so Webapp and Engine share identical
-- POSIX lifecycle semantics without sharing HTTP route implementations.
runDaemonWithReloadAndDrain
  :: DaemonControl
  -> IO ()
  -> IO (Maybe AppError)
  -> IO ()
  -> IO (Maybe AppError)
runDaemonWithReloadAndDrain control runDaemon reloadAction drainAction = do
  drainRequested <- newEmptyMVar
  reloadLock <- newMVar ()
  let handleSignal signal = do
        _snapshot <- applyDaemonSignal control signal
        case daemonSignalAction signal of
          BeginGracefulDrain -> void (tryPutMVar drainRequested Nothing)
          ReloadLiveConfig ->
            modifyMVar_ reloadLock $ \() -> do
              reloadFailure <- reloadAction
              case reloadFailure of
                Nothing -> pure ()
                Just appError -> do
                  _ <- applyDaemonSignal control DaemonSigterm
                  void (tryPutMVar drainRequested (Just appError))
              pure ()
  withDaemonSignalHandlers handleSignal $
    withAsync runDaemon $ \server ->
      withAsync (takeMVar drainRequested) $ \drainWaiter -> do
        firstFinished <- waitEitherCatch server drainWaiter
        case firstFinished of
          Left (Left exception) -> throwIO exception
          Left (Right ()) -> pure Nothing
          Right (Left exception) -> throwIO exception
          Right (Right reloadFailure) -> do
            drainAction
            pure reloadFailure

serveDaemonOnce :: DaemonRuntime -> IO ()
serveDaemonOnce runtime = do
  control <-
    newDaemonControlWithLiveConfig
      (daemonState runtime)
      (daemonLiveConfig runtime)
  case runtimeListener runtime of
    Just listener -> serveHttpRoutesOnce listener (daemonHttpRoutes control runtime)
    Nothing -> pure ()

-- | Sprint 5.14 — surface the selected one-binary role and its capability
-- profile in the daemon runtime summary so operators can see which role
-- (Engine / Coordinator / Webapp) this process is running.
renderActiveRole :: Role -> Text
renderActiveRole role =
  Text.intercalate
    "\n"
    [ "role: " <> roleLabel role
    , "computes: " <> boolText (profileComputes profile)
    , "owns_topics: " <> boolText (profileOwnsTopics profile)
    , "serves_websocket: " <> boolText (profileServesWebsocket profile)
    ]
 where
  profile = roleProfile role
  boolText True = "true"
  boolText False = "false"

renderDaemonRuntimeSummary :: DaemonRuntime -> Text
renderDaemonRuntimeSummary runtime =
  Text.unlines
    [ "lifecycle:"
    , "  - " <> Text.intercalate "\n  - " (fmap renderLifecyclePhase lifecyclePlan)
    , "active_role:"
    , indentText (renderActiveRole (bootActiveRole (daemonBootConfig runtime)))
    , "boot_config:"
    , indentText (renderBootConfigDhall (daemonBootConfig runtime))
    , "live_config:"
    , indentText (renderLiveConfigDhall (daemonLiveConfig runtime))
    , "apple_metal_acquire:"
    , indentText (renderAppleMetalAcquireStatus (daemonAppleMetalAcquireStatus runtime))
    , "client_acquisition:"
    , indentText (renderDaemonRoleClientSettings (daemonClientSettings runtime))
    , "client_probe_status:"
    , indentText (renderDaemonClientProbeStatuses (daemonClientProbeStatuses runtime))
    , "pulsar_subscriptions:"
    , indentText (renderDaemonSubscriptions (daemonSubscriptions runtime))
    , "daemon_state:"
    , indentText
        (daemonStateLabel (daemonState runtime) <> " " <> daemonStateDetail (daemonState runtime))
    , "http_listener:"
    , indentText (renderMaybeListener (runtimeListener runtime))
    , "routes:"
    , indentText (renderRouteNames (runtimeListener runtime))
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
    BeginGracefulDrain -> runtime {daemonState = beginDaemonDrain (daemonState runtime)}

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

liveReadyRoute :: DaemonControl -> HttpRoute
liveReadyRoute control =
  HttpRoute
    { httpRouteMethod = "GET"
    , httpRoutePath = "/readyz"
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteHandler = \_request -> do
        snapshot <- readDaemonControl control
        pure (readyz (daemonStateReady (snapshotDaemonState snapshot)))
    }

renderMaybeListener :: Maybe HttpListener -> Text
renderMaybeListener Nothing = "(none)"
renderMaybeListener (Just listener) =
  listenerHost listener <> ":" <> Text.pack (show (listenerPort listener))

renderRouteNames :: Maybe HttpListener -> Text
renderRouteNames Nothing = "(none)"
renderRouteNames (Just _) =
  "- GET /healthz\n- GET /readyz\n- GET /metrics\n- GET /"

renderDaemonSubscriptions :: [DaemonSubscription] -> Text
renderDaemonSubscriptions [] = "(none)\n"
renderDaemonSubscriptions subscriptions =
  Text.unlines (fmap renderDaemonSubscription subscriptions)

renderDaemonSubscription :: DaemonSubscription -> Text
renderDaemonSubscription subscription =
  "- "
    <> daemonSubscriptionTopicName subscription
    <> " as "
    <> daemonSubscriptionName subscription

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
      "dispatched " <> renderEventDomain domain <> " " <> eventIdText eventId
    ConsumerDeduplicated domain eventId ->
      "deduplicated " <> renderEventDomain domain <> " " <> eventIdText eventId
    ConsumerError err ->
      "error " <> renderServiceError err
    ConsumerSessionError failure ->
      "session-error " <> Text.pack (show failure)

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

-- | Defense in depth for the two command-consuming roles. The more specific
-- command-domain check below prevents either role from inheriting the other's
-- effects.
validateDaemonWorkloadDispatchRole :: DaemonRuntime -> Either ServiceError ()
validateDaemonWorkloadDispatchRole runtime =
  case bootActiveRole (daemonBootConfig runtime) of
    Engine -> Right ()
    Coordinator -> Right ()
    Webapp ->
      Left
        ( SEUnauthorized
            ( "workload dispatch requires activeRole=Engine or Coordinator, received "
                <> roleLabel Webapp
            )
        )

validateDaemonCommandDispatchRole
  :: DaemonRuntime
  -> DaemonCommand
  -> Either ServiceError ()
validateDaemonCommandDispatchRole runtime command = do
  validateDaemonWorkloadDispatchRole runtime
  case ( bootActiveRole bootConfig
       , bootSubstrate bootConfig
       , bootResidency bootConfig
       , command
       ) of
    (Engine, AppleSilicon, Host, _) -> Right ()
    (Engine, LinuxCPU, Cluster, InferenceDaemonCommand _ _) -> Right ()
    (Engine, LinuxCUDA, Cluster, InferenceDaemonCommand _ _) -> Right ()
    (Coordinator, AppleSilicon, Cluster, _) -> Right ()
    (Coordinator, _, Cluster, TrainingDaemonCommand _ _) -> Right ()
    (Coordinator, _, Cluster, TuneDaemonCommand _ _) -> Right ()
    (Coordinator, _, Cluster, RlDaemonCommand _ _) -> Right ()
    (role, _, _, _) ->
      Left
        ( SEUnauthorized
            ( "command domain "
                <> renderEventDomain (daemonCommandDomain command)
                <> " is not owned by activeRole="
                <> roleLabel role
            )
        )
 where
  bootConfig = daemonBootConfig runtime

daemonConsumerBatch
  :: (HasPulsar m, MonadIO m)
  => DaemonRuntime
  -> Int
  -- ^ Number of envelopes to pull per acquired subscription.
  -> (DaemonCommand -> EventId -> m (Either ServiceError ()))
  -> m (HandlerRouter, [ConsumerOutcome])
daemonConsumerBatch runtime budget dispatch =
  go (daemonHandlerRouter runtime) [] (daemonSubscriptions runtime)
 where
  go router outcomes [] =
    pure (router, outcomes)
  go router outcomes (subscription : rest)
    | budget <= 0 =
        go router outcomes rest
    | otherwise = do
        batchResult <-
          runConsumerLoop subscription router budget (const (pure ())) dispatch
        case batchResult of
          Left failure ->
            go router (outcomes <> [ConsumerSessionError failure]) rest
          Right (router', batchOutcomes) ->
            go router' (outcomes <> batchOutcomes) rest

daemonWorkloadDispatcher
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcher command _eventId =
  case command of
    TrainingDaemonCommand substrate training ->
      workloadOutcomesToUnit <$> Workload.dispatchTrainingCommand Cluster substrate training
    TuneDaemonCommand substrate tune ->
      workloadOutcomesToUnit <$> Workload.dispatchTuneCommand Cluster substrate tune
    RlDaemonCommand substrate rl ->
      workloadOutcomesToUnit <$> Workload.dispatchRlCommand Cluster substrate rl
    InferenceDaemonCommand substrate inference ->
      dispatchTypedInference substrate inference Workload.dispatchInferenceCommandForTopic

daemonWorkloadDispatcherWithInference
  :: (HasMinIO m, HasPulsar m)
  => ( CheckpointStore.AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [Double]
       -> m (Either Text [Double])
     )
  -> DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcherWithInference runInference command _eventId =
  case command of
    InferenceDaemonCommand substrate inference ->
      dispatchTypedInference
        substrate
        inference
        (Workload.dispatchInferenceCommandForTopicWithInference runInference)
    _nonInference -> rejectEngineNonInference command

-- | Sprint 13.11 — daemon dispatch variant that threads the weighted inference
-- callback (`AdmittedCompletedCheckpoint -> CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> ...`)
-- so the substrate-bound runners can consume real `.jmw1`-decoded weight
-- tensors instead of the removed manifest-only summary path. Used by
-- `daemonWorkloadDispatcherForRuntime` whenever the loaded `BootConfig`
-- requests `SelfInference` on `LinuxCPU` or `LinuxCUDA`.
daemonWorkloadDispatcherWithWeightedInference
  :: (HasMinIO m, HasPulsar m)
  => ( CheckpointStore.AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [Workload.LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcherWithWeightedInference runInference command _eventId =
  case command of
    InferenceDaemonCommand substrate inference ->
      dispatchTypedInference
        substrate
        inference
        (Workload.dispatchInferenceCommandForTopicWithWeightedInference runInference)
    _nonInference -> rejectEngineNonInference command

-- | Sprint 14.4 / Sprint 16.11 — cluster-side `ForwardToHost` inference dispatch.
-- Metal cannot run in-pod, so the in-cluster daemon does not compute: it bridges
-- the client `inference.request.apple-silicon` topic to the host daemon's
-- `inference.command.apple-silicon` topic by publishing the already-decoded
-- typed inference command through that route's canonical encoder. The
-- host-native Apple daemon is the Engine for `apple-silicon`: it consumes the
-- forwarded `RunInference`, runs the Metal weighted kernel, and publishes the
-- `InferenceResult` (inline output values) to the request's reply-topic
-- (`inference.result.apple-silicon`) directly, where the `jitml inference run` CLI
-- and the Webapp panels read it. The `inference.request` topic carries
-- `RunInference`, `CheckpointCompareCommand`, and `AdversarialMoveCommand` (the
-- demo's compare / connect4 panels); forwarding every typed inference-domain
-- command (rather than only `RunInference`) is what lets the host Engine's
-- `dispatchInferenceCommandForTopicWithWeightedInference` retains the consumed
-- typed input topic and publishes the matching
-- `InferenceResult` / `CheckpointCompareResult` / `AdversarialMoveResult` to the
-- request's reply-topic, where the CLI and the Webapp's `/api/ws/inference` stream
-- read it. Non-inference domains (training / tune / rl) still route to the standard
-- dispatcher, which performs the host-command workload placement for Apple
-- Metal-backed work.
daemonWorkloadDispatcherForwardingInference
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m)
  => DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcherForwardingInference command eventId =
  case command of
    InferenceDaemonCommand substrate inference ->
      case topicFor InferenceHostCommandRoute substrate of
        Left err -> pure (Left (SETransient (Text.pack (show err))))
        Right topic -> void <$> pulsarPublish topic inference
    _ -> daemonWorkloadDispatcher command eventId

-- | Sprint 14.4 — host-native Apple daemon dispatch. The host daemon is the
-- Engine for `apple-silicon`: it consumes the cluster-forwarded inference command
-- off `inference.command.apple-silicon` (a typed `RunInference` /
-- `CheckpointCompareCommand` / `AdversarialMoveCommand`), runs the Metal weighted
-- kernel, and publishes the matching `InferenceResult` / `CheckpointCompareResult`
-- / `AdversarialMoveResult` to the request's reply-topic directly (the converged
-- values model). This is an alias for the weighted self-inference dispatcher.
daemonWorkloadDispatcherHostingAppleInference
  :: (HasMinIO m, HasPulsar m)
  => ( CheckpointStore.AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [Workload.LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcherHostingAppleInference =
  daemonWorkloadDispatcherWithWeightedInference

rejectEngineNonInference
  :: (Applicative m)
  => DaemonCommand
  -> m (Either ServiceError ())
rejectEngineNonInference command =
  pure
    ( Left
        ( SEUnauthorized
            ( "Engine inference dispatcher cannot execute "
                <> renderEventDomain (daemonCommandDomain command)
                <> " orchestration"
            )
        )
    )

dispatchTypedInference
  :: (Monad m)
  => Substrate
  -> InferenceCommand
  -> ( Topic InferenceCommand
       -> InferenceCommand
       -> m (Either Workload.WorkloadDecodeError (NonEmpty Workload.SomeWorkloadOutcome))
     )
  -> m (Either ServiceError ())
dispatchTypedInference substrate command dispatch =
  case topicFor InferenceRequestRoute substrate of
    Left topicError ->
      pure
        (Left (SETransient ("inference input topic resolution failed: " <> Text.pack (show topicError))))
    Right inputTopic ->
      workloadOutcomesToUnit <$> dispatch inputTopic command

workloadOutcomesToUnit
  :: Either Workload.WorkloadDecodeError (NonEmpty Workload.SomeWorkloadOutcome)
  -> Either ServiceError ()
workloadOutcomesToUnit result =
  case result of
    Left decodeError ->
      Left (SETransient ("workload decode failed: " <> Text.pack (show decodeError)))
    Right outcomes ->
      case firstWorkloadOutcomeError (NonEmpty.toList outcomes) of
        Nothing -> Right ()
        Just err -> Left err

firstWorkloadOutcomeError :: [Workload.SomeWorkloadOutcome] -> Maybe ServiceError
firstWorkloadOutcomeError [] = Nothing
firstWorkloadOutcomeError (outcome : rest) =
  case Workload.workloadOutcomeError outcome of
    Just err -> Just err
    Nothing -> firstWorkloadOutcomeError rest

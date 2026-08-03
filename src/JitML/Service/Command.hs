{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Command
  ( ServiceCommandRuntime (..)
  , ServiceInvocation (..)
  , currentTimestampNs
  , engineWeightedInference
  , publishPulsarEvent
  , runInstallMetalBridge
  , runService
  , serviceRoleInvocationError
  , trainingCandidateCheckpointEventEnvelope
  , trainingCompletedCheckpointEventEnvelope
  , trainingCheckpointMetrics
  , waitForConsumeOnceHostWorkloads
  )
where

import Control.Concurrent (ThreadId, forkFinally, forkIO, killThread, threadDelay)
import Control.Concurrent.Async (concurrently)
import Control.Concurrent.MVar
  ( MVar
  , modifyMVar
  , modifyMVar_
  , newEmptyMVar
  , newMVar
  , putMVar
  , readMVar
  , tryPutMVar
  , tryReadMVar
  , tryTakeMVar
  )
import Control.Exception.Safe
  ( bracket
  , displayException
  , finally
  , mask_
  , throwIO
  , tryAny
  )
import Control.Monad (unless, void)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Data.Bifunctor (second)
import Data.Bool (bool)
import Data.Foldable (for_, traverse_)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory (doesFileExist)
import System.FilePath (takeDirectory, (</>))
import System.IO qualified
import System.Timeout (timeout)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output
  ( exitWithError
  , renderError
  , writeLine
  , writeLineIO
  , writeText
  )
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Cluster.Publication (defaultPublication)
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Coordinator.Topology qualified as Topology
import JitML.Engines.CudaLocal (runCudaWeightedCheckpointInference)
import JitML.Engines.Local
  ( runLinuxCpuWeightedCheckpointInference
  )
import JitML.Engines.MetalBridge qualified as MetalBridge
import JitML.Engines.MetalLocal (runMetalWeightedCheckpointInference)
import JitML.Engines.MetalRuntime (metalRuntimeAvailable, probeMetalRuntime)
import JitML.Env.Env (App, Env)
import JitML.Inference.Command qualified as InferenceCommand
import JitML.Numerics.Mlp (AdamState)
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate, rlDeviceForSubstrate)
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSeeds
  , runPlanSubjectId
  , seedCohortValues
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Prerequisite.Nodes.Container qualified as ContainerPrerequisites
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Pipeline qualified as ProductPipeline
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl qualified as ProtoRl
import JitML.Proto.Training qualified as ProtoTraining
import JitML.Proto.Tune qualified as ProtoTune
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.Command qualified as RlCommand
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.TrainerExecution (trainerRunEpisodes)
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.SL.Canonicals qualified as SL
import JitML.SL.TrainingExecution (TrainingMetrics (..))
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , EventId
  , HandlerRouter
  , consumerStep
  )
import JitML.Service.Consumer qualified as Consumer
import JitML.Service.HostWorkloadRegistry qualified as HostWorkloadRegistry
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.InferenceBatch qualified as InferenceBatch
import JitML.Service.Lifecycle qualified as ServiceLifecycle
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Logger qualified as ServiceLogger
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.Retry qualified as ServiceRetry
import JitML.Service.Runtime qualified as ServiceRuntime
import JitML.Service.RuntimeState qualified as RuntimeState
import JitML.Service.Signal qualified as ServiceSignal
import JitML.Service.WorkflowStatus qualified as WorkflowStatus
import JitML.Service.Workload qualified as Workload
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as Tune
import JitML.Web.Server qualified as WebServer

newtype ServiceCommandRuntime = ServiceCommandRuntime
  { serviceTrainingExecutionRuntime :: TrainingExecution.TrainingExecutionRuntime
  }

data ServiceInvocation = ServiceInvocation
  { serviceInvocationConfigPath :: Text
  , serviceInvocationExplicitConfig :: Bool
  , serviceInvocationConsumeOnceRequested :: Bool
  , serviceInvocationConsumeOnceBudget :: Int
  }

-- | Sprint 10.7 (Pulsar ML-Workflow convergence) — THE single Engine inference
-- compute: the one place that picks the substrate's weighted checkpoint runner
-- and runs the kernel. The demo HTTP handler, the `jitml inference run` CLI, and
-- the daemon consumer all route through this function, so the
-- @load→pick-runner→run-kernel@ pick-runner step is no longer copied across three
-- sites (it lives here). Per the contract the Engine (daemon) is the role that
-- actually serves this compute in production; the demo/CLI publish-only,
-- websocket-async routing is owned by Phase `11` Sprint `11.10`.
engineWeightedInference
  :: Env
  -> Substrate
  -> ProductPipeline.InferenceEligibleRef
  -> Checkpoint.CheckpointManifest
  -> [CheckpointStore.LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
engineWeightedInference env substrate _modelRef manifest weights values =
  case substrate of
    LinuxCPU ->
      runLinuxCpuWeightedCheckpointInference env manifest weights values
    LinuxCUDA ->
      runCudaWeightedCheckpointInference env manifest weights values
    AppleSilicon ->
      runMetalWeightedCheckpointInference env manifest weights values
{-# NOINLINE engineWeightedInference #-}

runService :: ServiceCommandRuntime -> ServiceInvocation -> App ()
runService commandRuntime invocation = do
  -- Sprint 13.3 dedup observation — Kubernetes pipes the daemon
  -- container's stdout into the kubelet log stream, which makes
  -- GHC's default block-buffering swallow per-delivery
  -- `service: <outcome>` lines until ~4 KB accumulates. Switch to
  -- line-buffered output so `kubectl logs deploy/jitml-service` sees
  -- every consumer outcome as it lands (the dedup live assertion
  -- depends on this).
  liftIO (System.IO.hSetBuffering System.IO.stdout System.IO.LineBuffering)
  liftIO (System.IO.hSetBuffering System.IO.stderr System.IO.LineBuffering)
  let configPath = serviceInvocationConfigPath invocation
      explicitConfig = serviceInvocationExplicitConfig invocation
      consumeOnceRequested = serviceInvocationConsumeOnceRequested invocation
      consumeOnceBudget = serviceInvocationConsumeOnceBudget invocation
  env <- ask
  (bootConfig, liveConfig) <- loadServiceConfigs configPath explicitConfig
  let activeRole = BootConfig.bootActiveRole bootConfig
  for_ (serviceRoleInvocationError activeRole consumeOnceRequested) $
    exitWithError . InvalidConfig
  -- Role selection is exhaustive and happens before a daemon runtime exists.
  -- Engine and Coordinator share the resource-safe lifecycle shell but acquire
  -- disjoint prerequisites and command plans.
  case activeRole of
    BootConfig.Engine ->
      runDaemonCommandRoleServe
        commandRuntime
        env
        configPath
        consumeOnceRequested
        consumeOnceBudget
        (ServiceRuntime.daemonRuntimeForConfigs bootConfig liveConfig)
    BootConfig.Coordinator ->
      runDaemonCommandRoleServe
        commandRuntime
        env
        configPath
        consumeOnceRequested
        consumeOnceBudget
        (ServiceRuntime.daemonRuntimeForConfigs bootConfig liveConfig)
    BootConfig.Webapp -> runWebappRole configPath bootConfig liveConfig
{-# NOINLINE runService #-}

serviceRoleInvocationError :: BootConfig.Role -> Bool -> Maybe Text
serviceRoleInvocationError role consumeOnceRequested
  | consumeOnceRequested && role /= BootConfig.Engine =
      Just "service --consume-once is available only when activeRole=Engine"
serviceRoleInvocationError BootConfig.Coordinator _ = Nothing
serviceRoleInvocationError BootConfig.Engine _ = Nothing
serviceRoleInvocationError BootConfig.Webapp _ = Nothing
{-# NOINLINE serviceRoleInvocationError #-}

-- | Sprint 11.10 — the Webapp role: serve the compiled browser bundle + the
-- held-open @/api/ws@ Pulsar bridge, deriving host/port/substrate/WS endpoint
-- from the typed Dhall 'BootConfig'. The browser-runtime handler __publishes__
-- an inference @WorkCommand@ to the Engine (via
-- 'InferenceCommand.requestInferenceViaEngine') and
-- renders the streamed result; the Webapp itself computes no inference.
runWebappRole :: Text -> BootConfig.BootConfig -> LiveConfig.LiveConfig -> App ()
runWebappRole configPath boot liveConfig = do
  listener <-
    case BootConfig.bootHttpListener boot of
      Just configuredListener -> pure configuredListener
      Nothing ->
        exitWithError
          (InvalidConfig "validated Webapp BootConfig has no HTTP listener")
  wsEndpoint <-
    case BootConfig.bootWebappPulsarWsUrl boot of
      Just endpoint -> pure endpoint
      Nothing ->
        exitWithError
          (InvalidConfig "validated Webapp BootConfig has no Pulsar WebSocket URL")
  let substrate = BootConfig.bootSubstrate boot
      host = BootConfig.listenerHost listener
      port = BootConfig.listenerPort listener
      publication = defaultPublication substrate
      pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForEndpoint wsEndpoint
      handler request =
        fmap
          ( fmap
              ( \output ->
                  WebServer.BrowserRuntimeResult
                    { WebServer.browserRuntimeCheckpointSha =
                        WebServer.browserRuntimeExperimentHash request
                    , WebServer.browserRuntimeOutput = output
                    }
              )
          )
          ( InferenceCommand.requestInferenceViaEngine
              pulsarSettings
              substrate
              (WebServer.browserRuntimeExperimentHash request)
              (WebServer.browserRuntimeInput request)
          )
      publishers =
        WebServer.BrowserCommandPublishers
          { WebServer.publishCompareCommand =
              InferenceCommand.publishCheckpointCompareCommandOnly pulsarSettings substrate
          , WebServer.publishMoveCommand =
              InferenceCommand.publishAdversarialMoveCommandOnly pulsarSettings substrate
          , WebServer.publishListCheckpointsCommand =
              InferenceCommand.publishListCheckpointsCommandOnly pulsarSettings substrate
          , WebServer.publishLoadTranscriptCommand =
              InferenceCommand.publishLoadTranscriptCommandOnly pulsarSettings substrate
          }
  writeLine ("webapp: serving " <> host <> ":" <> Text.pack (show port))
  let runtime = ServiceRuntime.daemonRuntimeForConfigs boot liveConfig
      serveWebapp =
        WebServer.serveDemoWithBridgeEndpointWithRuntime
          host
          port
          (Just publication)
          (Just wsEndpoint)
          (Just handler)
          (Just publishers)
  control <-
    liftIO
      ( ServiceSignal.newDaemonControlWithLiveConfig
          (ServiceRuntime.daemonState runtime)
          liveConfig
      )
  reloadFailure <-
    liftIO
      ( ServiceRuntime.runDaemonWithReloadAndDrain
          control
          serveWebapp
          (reloadServiceConfigs configPath control (const (pure ())) boot)
          (pure ())
      )
  for_ reloadFailure exitWithError

runDaemonCommandRoleServe
  :: ServiceCommandRuntime
  -> Env
  -> Text
  -> Bool
  -> Int
  -> ServiceRuntime.DaemonRuntime
  -> App ()
runDaemonCommandRoleServe
  commandRuntime
  env
  configPath
  consumeOnceRequested
  consumeOnceBudget
  runtime = do
    daemonLogger <- liftIO ServiceLogger.newDaemonLogger
    hostWorkloadRegistry <- liftIO (hostWorkloadRegistryForRuntime runtime)
    acquireResult <- acquireDaemonRole runtime
    acquiredRuntime <-
      case acquireResult of
        Right readyRuntime -> pure readyRuntime
        Left (failedRuntime, err) -> do
          writeLine ("service config: " <> configPath)
          writeText (ServiceRuntime.renderDaemonRuntimeSummary failedRuntime)
          exitWithError err
    if consumeOnceRequested
      then do
        engineClientSettings <-
          case ServiceClients.engineRoleClientSettings
            (ServiceRuntime.daemonClientSettings acquiredRuntime) of
            Just settings -> pure settings
            Nothing ->
              exitWithError
                (InvalidConfig "Engine consume-once runtime has no Engine client settings")
        (_, outcomes) <-
          liftIO
            ( ServiceClients.runEngineServiceClient
                engineClientSettings
                ( ServiceRuntime.daemonConsumerBatch
                    acquiredRuntime
                    consumeOnceBudget
                    ( engineDaemonWorkloadDispatcherForRuntime
                        commandRuntime
                        env
                        acquiredRuntime
                        hostWorkloadRegistry
                    )
                )
            )
        hostWorkloadFailure <-
          liftIO (waitForConsumeOnceHostWorkloads hostWorkloadRegistry)
        writeLine ("service config: " <> configPath)
        writeText (ServiceRuntime.renderDaemonRuntimeSummary acquiredRuntime)
        writeLine
          ( "service: consume-once drained "
              <> Text.pack (show consumeOnceBudget)
              <> " message(s) per planned subscription"
          )
        writeText (ServiceRuntime.renderConsumerOutcomes outcomes)
        case ServiceRuntime.consumerLoopExit outcomes of
          Just consumerFailure -> exitWithError consumerFailure
          Nothing -> for_ hostWorkloadFailure exitWithError
      else do
        control <-
          liftIO
            ( ServiceSignal.newDaemonControlWithLiveConfig
                (ServiceRuntime.daemonState acquiredRuntime)
                (ServiceRuntime.daemonLiveConfig acquiredRuntime)
            )
        consumerWorkers <-
          liftIO
            ( startDaemonConsumerWorkers
                commandRuntime
                env
                control
                daemonLogger
                acquiredRuntime
                hostWorkloadRegistry
            )
        connected <- liftIO (waitForDaemonConsumerConnections consumerWorkers)
        unless connected $ do
          liftIO $ do
            void
              ( ServiceSignal.modifyDaemonState
                  control
                  ( RuntimeState.recordRuntimeFailure
                      "persistent Pulsar consumers did not connect before startup deadline"
                  )
              )
            stopDaemonConsumerWorkers control consumerWorkers
          writeLine ("service config: " <> configPath)
          writeText (ServiceRuntime.renderDaemonRuntimeSummary acquiredRuntime)
          exitWithError
            (PulsarFailed "persistent Pulsar consumers did not connect before startup deadline")
        connectedSnapshot <- liftIO (ServiceSignal.readDaemonControl control)
        let connectedRuntime =
              acquiredRuntime
                { ServiceRuntime.daemonState =
                    ServiceSignal.snapshotDaemonState connectedSnapshot
                }
        probeResultRuntime <-
          case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig connectedRuntime) of
            BootConfig.Engine ->
              case ServiceClients.engineRoleClientSettings
                (ServiceRuntime.daemonClientSettings connectedRuntime) of
                Just settings ->
                  liftIO
                    ( ServiceClients.runEngineServiceClient
                        settings
                        (ServiceRuntime.probeEngineServiceClients connectedRuntime)
                    )
                Nothing ->
                  exitWithError
                    (InvalidConfig "Engine runtime has no Engine client settings")
            BootConfig.Coordinator ->
              case ServiceClients.coordinatorRoleClientSettings
                (ServiceRuntime.daemonClientSettings connectedRuntime) of
                Just settings ->
                  liftIO
                    ( ServiceClients.runDaemonServiceClient
                        settings
                        (ServiceRuntime.probeCoordinatorServiceClients connectedRuntime)
                    )
                Nothing ->
                  exitWithError
                    (InvalidConfig "Coordinator runtime has no Coordinator client settings")
            BootConfig.Webapp ->
              exitWithError
                (InvalidConfig "Webapp cannot probe command-role daemon clients")
        reconnectedAfterProbes <- liftIO (waitForDaemonConsumerConnections consumerWorkers)
        unless reconnectedAfterProbes $ do
          liftIO (stopDaemonConsumerWorkers control consumerWorkers)
          exitWithError
            (PulsarFailed "persistent Pulsar consumers disconnected during client probes")
        liftIO
          ( void
              ( ServiceSignal.modifyDaemonState
                  control
                  ( applyDaemonClientProbeStatuses
                      (ServiceRuntime.daemonClientProbeStatuses probeResultRuntime)
                  )
              )
          )
        finalSnapshot <- liftIO (ServiceSignal.readDaemonControl control)
        let probedRuntime =
              probeResultRuntime
                { ServiceRuntime.daemonState =
                    ServiceSignal.snapshotDaemonState finalSnapshot
                }
        writeLine ("service config: " <> configPath)
        writeText (ServiceRuntime.renderDaemonRuntimeSummary probedRuntime)
        unless (ServiceRuntime.daemonReady probedRuntime) $ do
          liftIO (stopDaemonConsumerWorkers control consumerWorkers)
          exitWithError
            ( PrerequisiteUnmet
                "service.readiness"
                (RuntimeState.daemonStateDetail (ServiceRuntime.daemonState probedRuntime))
                (Just "restore every persistent consumer connection and service-client probe")
            )
        liftIO
          ( void
              ( emitDaemonControlLog
                  daemonLogger
                  control
                  LiveConfig.Info
                  ServiceLifecycle.Ready
                  ( "role ready: "
                      <> BootConfig.renderRole (BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig probedRuntime))
                  )
              )
          )
        writeLine (serviceListeningLine probedRuntime)
        workerCleanup <- liftIO (newMVar False)
        cleanupFailure <- liftIO (newMVar Nothing)
        let stopDaemonResourcesOnce =
              modifyMVar_ workerCleanup $ \stopped ->
                if stopped
                  then pure True
                  else do
                    (_, registryFailure) <-
                      concurrently
                        (stopDaemonConsumerWorkers control consumerWorkers)
                        (drainHostWorkloads control hostWorkloadRegistry)
                    modifyMVar_ cleanupFailure (const (pure registryFailure))
                    pure True
        reloadFailure <-
          liftIO
            ( ServiceRuntime.serveDaemonWithReloadAndDrain
                control
                probedRuntime
                ( reloadServiceConfigs
                    configPath
                    control
                    (`refreshIdleDaemonConsumerRouters` consumerWorkers)
                    (ServiceRuntime.daemonBootConfig probedRuntime)
                )
                stopDaemonResourcesOnce
                `finally` stopDaemonResourcesOnce
            )
        resourceFailure <- liftIO (readMVar cleanupFailure)
        case reloadFailure of
          Just primaryFailure -> exitWithError primaryFailure
          Nothing -> for_ resourceFailure exitWithError

hostWorkloadRegistryForRuntime
  :: ServiceRuntime.DaemonRuntime
  -> IO (Maybe HostWorkloadRegistry.HostWorkloadRegistry)
hostWorkloadRegistryForRuntime runtime =
  whenMaybe
    (bootConfigIsAppleHostEngine (ServiceRuntime.daemonBootConfig runtime))
    HostWorkloadRegistry.newHostWorkloadRegistry

whenMaybe :: (Applicative f) => Bool -> f a -> f (Maybe a)
whenMaybe condition action =
  bool (pure Nothing) (Just <$> action) condition

-- | A bounded consume-once pull may register asynchronous Apple host Starts.
-- Once every subscription has returned, no further registrations can race the
-- snapshot, so wait for every retained handle and surface any worker failure
-- before the process reports success.
waitForConsumeOnceHostWorkloads
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO (Maybe AppError)
waitForConsumeOnceHostWorkloads Nothing = pure Nothing
waitForConsumeOnceHostWorkloads (Just registry) = do
  snapshots <- HostWorkloadRegistry.hostWorkloadRegistrySnapshots registry
  results <-
    traverse
      ( \(key, _snapshot) -> do
          outcome <- HostWorkloadRegistry.waitHostWorkload registry key
          pure (fmap (key,) outcome)
      )
      snapshots
  pure $
    case sequence results of
      Left registryError ->
        Just
          ( PrerequisiteUnmet
              "service.apple-host-workload.consume-once"
              (HostWorkloadRegistry.renderHostWorkloadRegistryError registryError)
              (Just "restore the process-local Apple host workload registry and retry")
          )
      Right outcomes ->
        case [ renderHostWorkloadFailure key failure
             | (key, HostWorkloadRegistry.HostWorkloadFailed failure) <- outcomes
             ] of
          [] -> Nothing
          failures ->
            Just
              ( PrerequisiteUnmet
                  "service.apple-host-workload.consume-once"
                  (Text.intercalate "; " failures)
                  (Just "correct the failed Apple host workload inputs and retry")
              )
 where
  renderHostWorkloadFailure key failure =
    HostWorkloadRegistry.hostWorkloadFamilyLabel
      (HostWorkloadRegistry.hostWorkloadFamily key)
      <> "/"
      <> HostWorkloadRegistry.hostWorkloadExperimentHash key
      <> ": "
      <> failure
{-# NOINLINE waitForConsumeOnceHostWorkloads #-}

bootConfigIsAppleHostEngine :: BootConfig.BootConfig -> Bool
bootConfigIsAppleHostEngine bootConfig =
  BootConfig.bootActiveRole bootConfig == BootConfig.Engine
    && BootConfig.bootSubstrate bootConfig == AppleSilicon
    && BootConfig.bootResidency bootConfig == BootConfig.Host

drainHostWorkloads
  :: ServiceSignal.DaemonControl
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO (Maybe AppError)
drainHostWorkloads _control Nothing = pure Nothing
drainHostWorkloads control (Just registry) = do
  snapshot <- ServiceSignal.readDaemonControl control
  result <-
    HostWorkloadRegistry.drainHostWorkloadRegistry
      registry
      (fromIntegral (LiveConfig.liveDrainDeadlineMicros (ServiceSignal.snapshotLiveConfig snapshot)))
  pure $
    case result of
      Right _report -> Nothing
      Left registryError ->
        Just
          ( PrerequisiteUnmet
              "service.apple-host-workload-drain"
              (HostWorkloadRegistry.renderHostWorkloadRegistryError registryError)
              (Just "allow the keyed Apple host workloads to cancel and join before the drain deadline")
          )

acquireDaemonRole
  :: ServiceRuntime.DaemonRuntime
  -> App (Either (ServiceRuntime.DaemonRuntime, AppError) ServiceRuntime.DaemonRuntime)
acquireDaemonRole runtime =
  case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig runtime) of
    BootConfig.Engine -> acquireAppleMetalBridge runtime
    BootConfig.Coordinator -> acquireCoordinatorTopicFamily runtime
    BootConfig.Webapp ->
      pure
        ( Left
            ( runtime
            , InvalidConfig "Webapp cannot enter the command-role daemon lifecycle"
            )
        )

acquireCoordinatorTopicFamily
  :: ServiceRuntime.DaemonRuntime
  -> App (Either (ServiceRuntime.DaemonRuntime, AppError) ServiceRuntime.DaemonRuntime)
acquireCoordinatorTopicFamily runtime = do
  result <-
    liftIO
      ( PulsarBootstrap.runCoordinatorPulsarTopicReconcileIO
          (LiveConfig.liveRetryPolicy (ServiceRuntime.daemonLiveConfig runtime))
      )
  pure $
    case result of
      Right evidence ->
        Right
          runtime
            { ServiceRuntime.daemonState =
                RuntimeState.recordTopicFamilyReconciled
                  (PulsarBootstrap.topicFamilyEvidenceTopics evidence)
                  (ServiceRuntime.daemonState runtime)
            }
      Left reconcileError ->
        let detail = Text.pack (show reconcileError)
         in Left
              ( runtime
                  { ServiceRuntime.daemonState =
                      RuntimeState.recordTopicFamilyFailure
                        detail
                        (ServiceRuntime.daemonState runtime)
                  }
              , PrerequisiteUnmet
                  "service.coordinator.topic-family"
                  detail
                  (Just "restore Pulsar and the Coordinator's in-cluster topic reconcile capability")
              )

serviceListeningLine :: ServiceRuntime.DaemonRuntime -> Text
serviceListeningLine runtime =
  case BootConfig.bootHttpListener (ServiceRuntime.daemonBootConfig runtime) of
    Nothing -> "service: running without HTTP listener"
    Just listener ->
      "service: listening on "
        <> BootConfig.listenerHost listener
        <> ":"
        <> Text.pack (show (BootConfig.listenerPort listener))

data DaemonConsumerWorker = DaemonConsumerWorker
  { daemonConsumerWorkerThreadId :: ThreadId
  , daemonConsumerWorkerRouter :: MVar HandlerRouter
  , daemonConsumerWorkerConnected :: MVar Bool
  , daemonConsumerWorkerInFlight :: MVar Bool
  , daemonConsumerWorkerFinished :: MVar ()
  }

startDaemonConsumerWorkers
  :: ServiceCommandRuntime
  -> Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO [DaemonConsumerWorker]
startDaemonConsumerWorkers commandRuntime env control daemonLogger runtime hostWorkloadRegistry =
  -- Sprint 16.11 — one dedup-cache MVar PER worker, not one shared across every
  -- worker. The dispatch compute runs inside `modifyMVar routerRef`
  -- (`handleDaemonConsumerDelivery`), so a single shared MVar serialized all
  -- workers: a long host Metal training/RL/tune workload (dispatched on its own
  -- `*.host-command` topic, 10s-100s of compute) held the one MVar and blocked the
  -- `inference.command` worker for the whole duration — so under a backlog of
  -- placement-dispatched host workloads a client's bounded inference reply poll
  -- timed out (head-of-line blocking across domains). Each subscription maps to a
  -- single topic/domain and redeliveries return to the same worker, so a
  -- per-worker router gives identical dedup semantics with no cross-worker lock.
  traverse startWorker (ServiceRuntime.daemonSubscriptions runtime)
 where
  startWorker subscription = do
    routerRef <- newMVar (ServiceRuntime.daemonHandlerRouter runtime)
    connectedRef <- newMVar False
    inFlightRef <- newMVar False
    finishedRef <- newEmptyMVar
    workerThread <-
      forkFinally
        ( daemonConsumerWorkerLoop
            commandRuntime
            env
            control
            daemonLogger
            runtime
            hostWorkloadRegistry
            routerRef
            connectedRef
            inFlightRef
            subscription
        )
        (const (void (tryPutMVar finishedRef ())))
    pure
      DaemonConsumerWorker
        { daemonConsumerWorkerThreadId = workerThread
        , daemonConsumerWorkerRouter = routerRef
        , daemonConsumerWorkerConnected = connectedRef
        , daemonConsumerWorkerInFlight = inFlightRef
        , daemonConsumerWorkerFinished = finishedRef
        }

stopDaemonConsumerWorkers :: ServiceSignal.DaemonControl -> [DaemonConsumerWorker] -> IO ()
stopDaemonConsumerWorkers control workers = do
  void (ServiceSignal.modifyDaemonState control RuntimeState.beginDaemonDrain)
  -- Idle workers can close their bridge immediately. In-flight handlers are
  -- left alone: after dispatch they observe the draining state, return a
  -- terminal disposition, and let the bridge confirm settlement before exit.
  for_ workers $ \worker -> do
    inFlight <- readMVar (daemonConsumerWorkerInFlight worker)
    unless inFlight (requestDaemonConsumerWorkerCancellation worker)
  controlSnapshot <- ServiceSignal.readDaemonControl control
  let deadline =
        LiveConfig.liveDrainDeadlineMicros
          (ServiceSignal.snapshotLiveConfig controlSnapshot)
  drained <-
    timeout
      deadline
      (traverse_ (readMVar . daemonConsumerWorkerFinished) workers)
  case drained of
    Just () -> pure ()
    Nothing ->
      -- A stuck handler or bridge must not hold process shutdown past the
      -- configured deadline. Issue cancellation from detached thrower threads:
      -- 'throwTo' is synchronous and could otherwise block this coordinator on
      -- an uninterruptible native call before the timeout can take effect.
      do
        traverse_ requestDaemonConsumerWorkerCancellation workers
        forcedCleanup <-
          timeout
            daemonConsumerForcedCleanupJoinMicros
            (traverse_ (readMVar . daemonConsumerWorkerFinished) workers)
        case forcedCleanup of
          Just () -> pure ()
          Nothing ->
            writeLineIO
              "service: forced consumer cleanup did not join before the post-cancel deadline"

requestDaemonConsumerWorkerCancellation :: DaemonConsumerWorker -> IO ()
requestDaemonConsumerWorkerCancellation worker = do
  finished <- tryReadMVar (daemonConsumerWorkerFinished worker)
  case finished of
    Just () -> pure ()
    Nothing -> void (forkIO (killThread (daemonConsumerWorkerThreadId worker)))

daemonConsumerForcedCleanupJoinMicros :: Int
daemonConsumerForcedCleanupJoinMicros = 5 * 1000 * 1000

reloadServiceConfigs
  :: Text
  -> ServiceSignal.DaemonControl
  -> (LiveConfig.LiveConfig -> IO ())
  -> BootConfig.BootConfig
  -> IO (Maybe AppError)
reloadServiceConfigs configPath control applyLiveConfig initialBootConfig = do
  let bootConfigPath = Text.unpack configPath
      liveConfigPath = takeDirectory bootConfigPath </> "LiveConfig.dhall"
  bootResult <- tryAny (BootConfig.loadBootConfig bootConfigPath)
  case bootResult of
    Left err ->
      restartRequired
        "invalid boot config"
        ( "failed to reload service config "
            <> configPath
            <> ": "
            <> Text.pack (displayException err)
        )
    Right nextBootConfig
      | nextBootConfig /= initialBootConfig ->
          restartRequired
            "boot config changed"
            "BootConfig changed under SIGHUP"
      | otherwise -> do
          liveResult <- tryAny (LiveConfig.loadLiveConfig liveConfigPath)
          case liveResult of
            Left err -> do
              generation <- currentReloadGeneration control
              writeLineIO
                ( "reload: ignored; reason=invalid live config; generation="
                    <> Text.pack (show generation)
                )
              writeLineIO
                ( "reload: invalid live config detail="
                    <> Text.pack (displayException err)
                )
              pure Nothing
            Right nextLiveConfig -> do
              decision <- ServiceSignal.applyDaemonLiveConfig control nextLiveConfig
              writeLineIO (HotReload.renderReloadDecision decision)
              case decision of
                HotReload.ReloadIgnored _reason -> pure ()
                HotReload.ReloadApplied snapshot -> do
                  applyLiveConfig nextLiveConfig
                  writeLineIO
                    ( "reload: active live config; log-level="
                        <> Text.pack (show (LiveConfig.liveLogLevel nextLiveConfig))
                        <> "; retry-policy="
                        <> Text.pack (show (LiveConfig.liveRetryPolicy nextLiveConfig))
                        <> "; inference-batch-size="
                        <> Text.pack (show (LiveConfig.liveInferenceBatchSize nextLiveConfig))
                        <> "; inference-max-latency-millis="
                        <> Text.pack (show (LiveConfig.liveInferenceMaxLatencyMillis nextLiveConfig))
                        <> "; dedup-cache-size="
                        <> Text.pack (show (LiveConfig.liveDedupCacheSize nextLiveConfig))
                        <> "; dedup-cache-ttl-seconds="
                        <> Text.pack (show (LiveConfig.liveDedupCacheTtlSeconds nextLiveConfig))
                        <> "; drain-deadline-seconds="
                        <> Text.pack (show (LiveConfig.liveDrainDeadlineSeconds nextLiveConfig))
                        <> "; generation="
                        <> Text.pack (show (HotReload.snapshotGeneration snapshot))
                    )
              pure Nothing
 where
  restartRequired reason detail = do
    generation <- currentReloadGeneration control
    writeLineIO
      ( "reload: restart-required; reason="
          <> reason
          <> "; generation="
          <> Text.pack (show generation)
      )
    pure (Just (InvalidConfig detail))

currentReloadGeneration :: ServiceSignal.DaemonControl -> IO Int
currentReloadGeneration control =
  ServiceSignal.snapshotReloadGeneration
    <$> ServiceSignal.readDaemonControl control

refreshIdleDaemonConsumerRouters :: LiveConfig.LiveConfig -> [DaemonConsumerWorker] -> IO ()
refreshIdleDaemonConsumerRouters liveConfig =
  traverse_ refreshWorker
 where
  refreshWorker worker = mask_ $ do
    maybeRouter <- tryTakeMVar (daemonConsumerWorkerRouter worker)
    case maybeRouter of
      Nothing -> pure ()
      Just router -> do
        configuredRouter <-
          Consumer.reconfigureHandlerRouter
            (LiveConfig.liveDedupCacheSize liveConfig)
            (LiveConfig.liveDedupCacheTtlSeconds liveConfig)
            router
        putMVar (daemonConsumerWorkerRouter worker) configuredRouter

waitForDaemonConsumerConnections :: [DaemonConsumerWorker] -> IO Bool
waitForDaemonConsumerConnections workers =
  go daemonConsumerStartupPollAttempts
 where
  go attempts = do
    connected <- traverse (readMVar . daemonConsumerWorkerConnected) workers
    if and connected
      then pure True
      else
        if attempts <= 0
          then pure False
          else do
            threadDelay daemonConsumerStartupPollMicros
            go (attempts - 1)

daemonConsumerWorkerLoop
  :: ServiceCommandRuntime
  -> Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> MVar HandlerRouter
  -> MVar Bool
  -> MVar Bool
  -> Consumer.DaemonSubscription
  -> IO ()
daemonConsumerWorkerLoop
  commandRuntime
  env
  control
  daemonLogger
  runtime
  hostWorkloadRegistry
  routerRef
  connectedRef
  inFlightRef
  subscription =
    runWorker
   where
    runWorker =
      case ServiceClients.rolePulsarSettings (ServiceRuntime.daemonClientSettings runtime) of
        Nothing ->
          ioError
            ( userError
                "command-role daemon runtime has no Pulsar client settings"
            )
        Just pulsarSettings -> do
          workerResult <-
            PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
              pulsarSettings
              consumeSubscription
          case workerResult of
            Right _ -> pure ()
            Left failure -> do
              modifyMVar_ connectedRef (const (pure False))
              void
                ( ServiceSignal.modifyDaemonState
                    control
                    (RuntimeState.recordRuntimeFailure (Text.pack (show failure)))
                )
              snapshot <- ServiceSignal.readDaemonControl control
              unless (ServiceSignal.snapshotDraining snapshot) $ do
                void
                  ( emitDaemonControlLog
                      daemonLogger
                      control
                      LiveConfig.Error
                      ServiceLifecycle.Serve
                      ( "consumer worker error: "
                          <> Text.strip
                            (ServiceRuntime.renderConsumerOutcomes [ConsumerSessionError failure])
                      )
                  )
                threadDelay daemonConsumerErrorDelayMicros
                runWorker

    consumeSubscription =
      case Consumer.daemonSubscriptionDomain subscription of
        Consumer.InferenceDomain ->
          Consumer.consumeDaemonSubscriptionBatches
            subscription
            (liftIO (readInferenceBatchPolicy control))
            inferenceBatchCompatibility
            (observeDaemonConsumerSession control connectedRef subscription)
            ( handleDaemonConsumerBatch
                commandRuntime
                env
                control
                daemonLogger
                runtime
                hostWorkloadRegistry
                routerRef
                inFlightRef
            )
        _ ->
          Consumer.consumeDaemonSubscription
            subscription
            (observeDaemonConsumerSession control connectedRef subscription)
            ( handleDaemonConsumerDelivery
                commandRuntime
                env
                control
                daemonLogger
                runtime
                hostWorkloadRegistry
                routerRef
                inFlightRef
            )

observeDaemonConsumerSession
  :: ServiceSignal.DaemonControl
  -> MVar Bool
  -> Consumer.DaemonSubscription
  -> Capabilities.ConsumerSessionEvent
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess ()
observeDaemonConsumerSession control connectedRef subscription sessionEvent =
  liftIO $ do
    modifyMVar_ connectedRef (const (pure (sessionConnected sessionEvent)))
    void
      ( ServiceSignal.modifyDaemonState
          control
          (ServiceRuntime.daemonConsumerSessionTransition subscription sessionEvent)
      )
 where
  sessionConnected event =
    case event of
      Capabilities.ConsumerSessionConnected _ -> True
      Capabilities.ConsumerSessionDisconnected _ -> False
      Capabilities.ConsumerSessionDraining -> False
      Capabilities.ConsumerSessionDrained -> False

handleDaemonConsumerDelivery
  :: ServiceCommandRuntime
  -> Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> MVar HandlerRouter
  -> MVar Bool
  -> Consumer.DaemonCommand
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Capabilities.ConsumerDecision ())
handleDaemonConsumerDelivery
  commandRuntime
  env
  control
  daemonLogger
  runtime
  hostWorkloadRegistry
  routerRef
  inFlightRef
  command = do
    liftIO $
      bracket
        (modifyMVar_ inFlightRef (const (pure True)))
        (const (modifyMVar_ inFlightRef (const (pure False))))
        ( \() -> do
            initialSnapshot <- ServiceSignal.readDaemonControl control
            if ServiceSignal.snapshotDraining initialSnapshot
              then
                pure
                  ( Capabilities.done
                      (Capabilities.nack Capabilities.DrainRequested)
                      ()
                  )
              else modifyMVar routerRef $ \router -> do
                liveSnapshot <- ServiceSignal.readDaemonControl control
                let liveConfig = ServiceSignal.snapshotLiveConfig liveSnapshot
                configuredRouter <-
                  Consumer.reconfigureHandlerRouter
                    (LiveConfig.liveDedupCacheSize liveConfig)
                    (LiveConfig.liveDedupCacheTtlSeconds liveConfig)
                    router
                (router', outcome, disposition) <-
                  consumerStep
                    configuredRouter
                    command
                    ( dispatchDaemonCommandWithRetry
                        commandRuntime
                        env
                        runtime
                        hostWorkloadRegistry
                        liveConfig
                        Nothing
                    )
                void
                  ( emitDaemonControlLog
                      daemonLogger
                      control
                      LiveConfig.Info
                      ServiceLifecycle.Serve
                      (Text.strip (ServiceRuntime.renderConsumerOutcomes [outcome]))
                  )
                for_ (ServiceRuntime.consumerLoopExit [outcome]) $ \appError ->
                  void
                    ( emitDaemonControlLog
                        daemonLogger
                        control
                        LiveConfig.Error
                        ServiceLifecycle.Serve
                        ("consumer outcome error: " <> renderError appError)
                    )
                completedSnapshot <- ServiceSignal.readDaemonControl control
                let decision =
                      if ServiceSignal.snapshotDraining completedSnapshot
                        then Capabilities.done disposition ()
                        else Capabilities.continue disposition
                pure (router', decision)
        )

data InferenceBatchCompatibility
  = CompatibleRunInference Text Int
  | IsolatedInferenceCommand Text
  deriving stock (Eq)

inferenceBatchCompatibility :: Consumer.DaemonCommand -> InferenceBatchCompatibility
inferenceBatchCompatibility command =
  case command of
    Consumer.InferenceDaemonCommand _ (Inference.RunInference request) ->
      CompatibleRunInference
        (Inference.irExperimentHash request)
        (length (Inference.irInput request))
    _ -> IsolatedInferenceCommand (Consumer.daemonCommandPayload command)

readInferenceBatchPolicy
  :: ServiceSignal.DaemonControl
  -> IO InferenceBatch.BatchPolicy
readInferenceBatchPolicy control = do
  snapshot <- ServiceSignal.readDaemonControl control
  let liveConfig = ServiceSignal.snapshotLiveConfig snapshot
  case InferenceBatch.mkBatchPolicy
    (fromIntegral (LiveConfig.liveInferenceBatchSize liveConfig))
    (fromIntegral (LiveConfig.liveInferenceMaxLatencyMillis liveConfig) * 1000) of
    Right policy -> pure policy
    Left policyError ->
      ioError
        ( userError
            ( "validated LiveConfig produced an invalid inference batch policy: "
                <> show policyError
            )
        )

data DaemonBatchFailure
  = DaemonBatchSloExpired
  | DaemonBatchDispatchFailed AppError

handleDaemonConsumerBatch
  :: ServiceCommandRuntime
  -> Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> MVar HandlerRouter
  -> MVar Bool
  -> Capabilities.DeliveryBatch Consumer.DaemonCommand
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Capabilities.ConsumerBatchDecision ())
handleDaemonConsumerBatch
  commandRuntime
  env
  control
  daemonLogger
  runtime
  hostWorkloadRegistry
  routerRef
  inFlightRef
  batch =
    liftIO $
      bracket
        (modifyMVar_ inFlightRef (const (pure True)))
        (const (modifyMVar_ inFlightRef (const (pure False))))
        ( \() -> do
            initialSnapshot <- ServiceSignal.readDaemonControl control
            if ServiceSignal.snapshotDraining initialSnapshot
              then
                pure
                  ( Capabilities.doneBatch
                      (Capabilities.nack Capabilities.DrainRequested)
                      ()
                  )
              else do
                liveSnapshot <- ServiceSignal.readDaemonControl control
                let liveConfig = ServiceSignal.snapshotLiveConfig liveSnapshot
                modifyMVar_ routerRef $ \router ->
                  Consumer.reconfigureHandlerRouter
                    (LiveConfig.liveDedupCacheSize liveConfig)
                    (LiveConfig.liveDedupCacheTtlSeconds liveConfig)
                    router
                (_outcomes, batchFailure) <-
                  runDaemonConsumerBatch
                    commandRuntime
                    env
                    runtime
                    hostWorkloadRegistry
                    liveConfig
                    (Capabilities.deliveryBatchWindow batch)
                    (emitOutcomeLog control daemonLogger)
                    routerRef
                    (Capabilities.deliveryBatchEvents batch)
                completedSnapshot <- ServiceSignal.readDaemonControl control
                let disposition = daemonBatchDisposition batchFailure
                    decision =
                      if ServiceSignal.snapshotDraining completedSnapshot
                        then Capabilities.doneBatch disposition ()
                        else Capabilities.continueBatch disposition
                pure decision
        )

runDaemonConsumerBatch
  :: ServiceCommandRuntime
  -> Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> LiveConfig.LiveConfig
  -> InferenceBatch.BatchWindow
  -> (ConsumerOutcome -> IO ())
  -> MVar HandlerRouter
  -> NonEmpty.NonEmpty Consumer.DaemonCommand
  -> IO ([ConsumerOutcome], Maybe DaemonBatchFailure)
runDaemonConsumerBatch
  commandRuntime
  env
  runtime
  hostWorkloadRegistry
  liveConfig
  window
  observeOutcome
  routerRef
  initialCommands =
    go [] (NonEmpty.toList initialCommands)
   where
    go outcomes pendingCommands =
      case pendingCommands of
        [] -> pure (reverse outcomes, Nothing)
        command : remaining -> do
          now <- getMonotonicTimeNSec
          if InferenceBatch.batchWindowExpiredAt now window
            then pure (reverse outcomes, Just DaemonBatchSloExpired)
            else do
              (outcome, _disposition) <-
                Consumer.consumerStepCommitted
                  routerRef
                  command
                  ( dispatchDaemonCommandWithRetry
                      commandRuntime
                      env
                      runtime
                      hostWorkloadRegistry
                      liveConfig
                      (Just (InferenceBatch.batchWindowDeadlineNanoseconds window))
                  )
              observeOutcome outcome
              case Consumer.consumerOutcomeError outcome of
                Just appError ->
                  pure
                    ( reverse (outcome : outcomes)
                    , Just (DaemonBatchDispatchFailed appError)
                    )
                Nothing -> go (outcome : outcomes) remaining

daemonBatchDisposition :: Maybe DaemonBatchFailure -> Capabilities.Disposition
daemonBatchDisposition batchFailure =
  case batchFailure of
    Nothing -> Capabilities.ack
    Just DaemonBatchSloExpired ->
      Capabilities.nack
        (Capabilities.RetryRequested "inference batch latency SLO expired")
    Just (DaemonBatchDispatchFailed appError) ->
      Capabilities.nack
        (Capabilities.HandlerRejected (Text.strip (renderError appError)))

emitOutcomeLog
  :: ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ConsumerOutcome
  -> IO ()
emitOutcomeLog control daemonLogger outcome = do
  void
    ( emitDaemonControlLog
        daemonLogger
        control
        LiveConfig.Info
        ServiceLifecycle.Serve
        (Text.strip (ServiceRuntime.renderConsumerOutcomes [outcome]))
    )
  for_ (Consumer.consumerOutcomeError outcome) $ \appError ->
    void
      ( emitDaemonControlLog
          daemonLogger
          control
          LiveConfig.Error
          ServiceLifecycle.Serve
          ("consumer outcome error: " <> renderError appError)
      )

dispatchDaemonCommandWithRetry
  :: ServiceCommandRuntime
  -> Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> LiveConfig.LiveConfig
  -> Maybe Integer
  -> Consumer.DaemonCommand
  -> EventId
  -> IO (Either ServiceError ())
dispatchDaemonCommandWithRetry
  commandRuntime
  env
  runtime
  hostWorkloadRegistry
  liveConfig
  publicationDeadline
  command
  eventId =
    ServiceRetry.retryServiceActionEither
      (LiveConfig.liveRetryPolicy liveConfig)
      ( \() ->
          dispatchDaemonCommandForRole
            commandRuntime
            env
            runtime
            hostWorkloadRegistry
            publicationDeadline
            command
            eventId
      )
      ()

dispatchDaemonCommandForRole
  :: ServiceCommandRuntime
  -> Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> Maybe Integer
  -> Consumer.DaemonCommand
  -> EventId
  -> IO (Either ServiceError ())
dispatchDaemonCommandForRole
  commandRuntime
  env
  runtime
  hostWorkloadRegistry
  publicationDeadline
  command
  eventId =
    case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig runtime) of
      BootConfig.Engine ->
        case ServiceClients.engineRoleClientSettings
          (ServiceRuntime.daemonClientSettings runtime) of
          Just settings ->
            ServiceClients.runEngineServiceClient
              ( maybe
                  settings
                  (`ServiceClients.engineClientSettingsWithPublicationDeadline` settings)
                  publicationDeadline
              )
              ( engineDaemonWorkloadDispatcherForRuntime
                  commandRuntime
                  env
                  runtime
                  hostWorkloadRegistry
                  command
                  eventId
              )
          Nothing -> pure (Left (SEConflict "Engine runtime has no Engine client settings"))
      BootConfig.Coordinator ->
        case ServiceClients.coordinatorRoleClientSettings
          (ServiceRuntime.daemonClientSettings runtime) of
          Just settings ->
            ServiceClients.runDaemonServiceClient
              settings
              (coordinatorDaemonWorkloadDispatcherForRuntime runtime command eventId)
          Nothing ->
            pure (Left (SEConflict "Coordinator runtime has no Coordinator client settings"))
      BootConfig.Webapp ->
        pure (Left (SEUnauthorized "Webapp cannot dispatch daemon commands"))

daemonConsumerErrorDelayMicros :: Int
daemonConsumerErrorDelayMicros = 1000000

daemonConsumerStartupPollMicros :: Int
daemonConsumerStartupPollMicros = 100000

daemonConsumerStartupPollAttempts :: Int
daemonConsumerStartupPollAttempts = 300

emitDaemonControlLog
  :: ServiceLogger.DaemonLogger
  -> ServiceSignal.DaemonControl
  -> LiveConfig.LogLevel
  -> ServiceLifecycle.LifecyclePhase
  -> Text
  -> IO Bool
emitDaemonControlLog logger control =
  ServiceLogger.emitDaemonLog
    logger
    (ServiceSignal.snapshotLiveConfig <$> ServiceSignal.readDaemonControl control)

applyDaemonClientProbeStatuses
  :: [ServiceRuntime.DaemonClientProbeStatus]
  -> RuntimeState.DaemonState
  -> RuntimeState.DaemonState
applyDaemonClientProbeStatuses statuses state =
  case failedProbe statuses of
    Just (name, err) ->
      RuntimeState.recordClientProbeFailure name (Text.pack (show err)) state
    Nothing
      | all probeSucceeded statuses ->
          RuntimeState.recordClientProbesSucceeded
            (fmap ServiceRuntime.daemonClientProbeStatusName statuses)
            state
      | otherwise ->
          RuntimeState.recordRuntimeFailure
            "client probing returned a pending status"
            state
 where
  failedProbe [] = Nothing
  failedProbe (status : rest) =
    case ServiceRuntime.daemonClientProbeStatusState status of
      ServiceRuntime.DaemonClientProbeFailed err ->
        Just (ServiceRuntime.daemonClientProbeStatusName status, err)
      _ -> failedProbe rest

  probeSucceeded status =
    case ServiceRuntime.daemonClientProbeStatusState status of
      ServiceRuntime.DaemonClientProbeSucceeded _ -> True
      _ -> False

daemonWorkloadDispatcherForRuntime
  :: (Capabilities.HasPulsar m)
  => ServiceRuntime.DaemonRuntime
  -> (Consumer.DaemonCommand -> EventId -> m (Either ServiceError ()))
  -> Consumer.DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcherForRuntime runtime innerDispatcher command eventId
  | Left roleError <- ServiceRuntime.validateDaemonCommandDispatchRole runtime command =
      pure (Left roleError)
  | incomingSubstrate /= configuredSubstrate =
      pure
        ( Left
            ( SETransient
                ( "consumer delivery substrate mismatch: expected "
                    <> renderSubstrate configuredSubstrate
                    <> ", received "
                    <> renderSubstrate incomingSubstrate
                )
            )
        )
  | otherwise = do
      -- Sprint 14.1 (Feature C) — the Engine's workflow-status projector: alongside
      -- the underlying command dispatch, project the observed training / tune / rl
      -- lifecycle transition into a reconciled `WorkflowStatus` frame and republish
      -- it onto `workflow.status.<substrate>`, which the workflow panel renders live.
      dispatchResult <- innerDispatcher command eventId
      case dispatchResult of
        Left err -> pure (Left err)
        Right () ->
          case projectionMode of
            ServiceRuntime.SkipWorkflowStatusProjection -> pure (Right ())
            _projectionRequiredOrBestEffort ->
              ServiceRuntime.applyWorkflowStatusProjectionResult projectionMode
                <$> projectWorkflowStatus command
 where
  incomingSubstrate = Consumer.daemonCommandSubstrate command
  bootConfig = ServiceRuntime.daemonBootConfig runtime
  projectionMode =
    ServiceRuntime.workflowStatusProjectionMode bootConfig command
  configuredSubstrate = BootConfig.bootSubstrate bootConfig

coordinatorDaemonWorkloadDispatcherForRuntime
  :: ServiceRuntime.DaemonRuntime
  -> Consumer.DaemonCommand
  -> EventId
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
coordinatorDaemonWorkloadDispatcherForRuntime runtime =
  daemonWorkloadDispatcherForRuntime runtime coordinatorDispatcher
 where
  coordinatorDispatcher =
    case BootConfig.bootSubstrate
      (ServiceRuntime.daemonBootConfig runtime) of
      AppleSilicon -> ServiceRuntime.daemonWorkloadDispatcherForwardingInference
      LinuxCPU -> ServiceRuntime.daemonWorkloadDispatcher
      LinuxCUDA -> ServiceRuntime.daemonWorkloadDispatcher

engineDaemonWorkloadDispatcherForRuntime
  :: ServiceCommandRuntime
  -> Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> Consumer.DaemonCommand
  -> EventId
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
engineDaemonWorkloadDispatcherForRuntime commandRuntime env runtime hostWorkloadRegistry =
  daemonWorkloadDispatcherForRuntime runtime engineDispatcher
 where
  bootConfig = ServiceRuntime.daemonBootConfig runtime
  configuredSubstrate = BootConfig.bootSubstrate bootConfig
  engineDispatcher =
    case (configuredSubstrate, BootConfig.bootInferenceMode bootConfig) of
      -- Sprint 13.11 — both Linux substrates route SelfInference through the
      -- weighted runners so the daemon executes the substrate-specific weighted
      -- kernel against `.jmw1`-decoded tensors instead of the deterministic
      -- summary path.
      (LinuxCPU, BootConfig.SelfInference) ->
        ServiceRuntime.daemonWorkloadDispatcherWithWeightedInference $ \admitted manifest weights input ->
          liftIO
            ( engineWeightedInference
                env
                LinuxCPU
                (ProductPipeline.inferenceEligibleModelRef admitted)
                manifest
                weights
                input
            )
      (LinuxCUDA, BootConfig.SelfInference) ->
        ServiceRuntime.daemonWorkloadDispatcherWithWeightedInference $ \admitted manifest weights input ->
          liftIO
            ( engineWeightedInference
                env
                LinuxCUDA
                (ProductPipeline.inferenceEligibleModelRef admitted)
                manifest
                weights
                input
            )
      -- Sprint 14.5 — the Apple host-native daemon (`Host + SelfInference`)
      -- routes inference through the Metal weighted runner so it executes the
      -- generated `jitml_weighted_kernel` against `.jmw1`-decoded tensors. The host
      -- daemon is the Engine for `apple-silicon`: it consumes the cluster-forwarded
      -- inference command off `inference.command.apple-silicon`, runs the Metal
      -- weighted kernel, and publishes the matching `InferenceResult` to the
      -- request's reply-topic directly (the converged values model). Sprint 5.11
      -- extends that host-resident execution rule to Metal-backed training/RL/tune
      -- command envelopes forwarded by the in-cluster Apple daemon on the
      -- host-command topics.
      (AppleSilicon, BootConfig.SelfInference) ->
        daemonWorkloadDispatcherHostingAppleWorkloads commandRuntime env hostWorkloadRegistry
      _ -> \_command _eventId ->
        pure
          ( Left
              ( SEUnauthorized
                  "Engine client cannot execute Coordinator orchestration"
              )
          )

-- | Sprint 14.1 (Feature C) — project an observed lifecycle transition into a
-- reconciled `WorkflowStatus` frame and publish it onto
-- `workflow.status.<substrate>`. The caller selects whether a failure is a
-- best-effort overlay or required terminal evidence for acknowledgement.
-- Inference-domain payloads carry no run status and are skipped.
projectWorkflowStatus
  :: (Capabilities.HasPulsar m)
  => Consumer.DaemonCommand
  -> m (Either ServiceError ())
projectWorkflowStatus command =
  case WorkflowStatus.workflowStatusFrameForDaemonCommand command of
    Nothing -> pure (Right ())
    Just frame ->
      case Topology.mkWorkflowStatusMessage
        (WorkflowStatus.renderWorkflowStatusFrame frame) of
        Left decodeError ->
          pure
            ( Left
                ( SEConflict
                    ( "workflow status frame encoding failed: "
                        <> Text.pack (show decodeError)
                    )
                )
            )
        Right message ->
          publishProtocolEvent
            Topology.WorkflowStatusRoute
            (Consumer.daemonCommandSubstrate command)
            message

daemonWorkloadDispatcherHostingAppleWorkloads
  :: ServiceCommandRuntime
  -> Env
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> Consumer.DaemonCommand
  -> EventId
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
daemonWorkloadDispatcherHostingAppleWorkloads commandRuntime env hostWorkloadRegistry command eventId
  | substrate /= AppleSilicon =
      pure (Left (SETransient "host Apple dispatcher received a non-apple-silicon delivery"))
  | otherwise =
      case ServiceRuntime.planAppleHostWorkloadAction command of
        Left err -> pure (Left err)
        Right action ->
          case action of
            ServiceRuntime.RunAppleHostTraining start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleTraining commandRuntime env start)
            ServiceRuntime.RunAppleHostTune start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleTune env start)
            ServiceRuntime.RunAppleHostRl start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleRl env start)
            ServiceRuntime.RunAppleHostAlphaZero start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleAlphaZero env start)
            ServiceRuntime.StopAppleHostWorkload mode key ->
              stopAppleHostWorkload hostWorkloadRegistry eventId mode key
            ServiceRuntime.RunAppleHostInference _ ->
              hostInferenceFallback command eventId
 where
  substrate = Consumer.daemonCommandSubstrate command
  hostInferenceFallback =
    ServiceRuntime.daemonWorkloadDispatcherHostingAppleInference
      ( \admitted manifest weights input ->
          liftIO
            ( engineWeightedInference
                env
                AppleSilicon
                (ProductPipeline.inferenceEligibleModelRef admitted)
                manifest
                weights
                input
            )
      )

superviseAppleHostWorkload
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> ServiceRuntime.AppleHostWorkloadAction
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
superviseAppleHostWorkload registry action workload = do
  clientSettings <- ask
  liftIO
    ( ServiceRuntime.executeAppleHostWorkloadStart registry action $ do
        workloadResult <-
          ServiceClients.runEngineServiceClient clientSettings workload
        case workloadResult of
          Right () -> pure ()
          Left serviceError ->
            throwIO
              ( userError
                  ( "Apple host workload failed: "
                      <> show serviceError
                  )
              )
    )

stopAppleHostWorkload
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> EventId
  -> ServiceRuntime.AppleHostWorkloadStopMode
  -> HostWorkloadRegistry.HostWorkloadKey
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
stopAppleHostWorkload registry eventId mode key =
  liftIO
    ( ServiceRuntime.executeAppleHostWorkloadStop
        registry
        eventId
        mode
        key
    )

runHostAppleTraining
  :: ServiceCommandRuntime
  -> Env
  -> ProtoTraining.StartTraining
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleTraining commandRuntime env start
  | ProtoTraining.stSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple training received a non-apple-silicon command"))
  | otherwise = case PlanCommand.validateStartTraining start of
      Left err ->
        pure (Left (SETransient ("host Apple supervised plan refinement failed: " <> err)))
      Right plan -> do
        problemE <-
          liftIO
            ( SL.loadCanonicalProblemExperiment
                ( Text.unpack
                    (runPlanSubjectId (WorkloadPlan.supervisedPlanRunPlan plan))
                )
            )
        case problemE of
          Left err -> pure (Left (SETransient ("host Apple training experiment decode failed: " <> err)))
          Right problem -> do
            case TrainingExecution.supervisedExecutionBudget plan of
              Left err -> pure (Left (SETransient err))
              Right (trainLimit, epochs, testLimit, batchSize) -> do
                result <-
                  liftIO
                    ( runReaderT
                        ( TrainingExecution.runDeviceMnistTrainingWithLimitsAndLearningRate
                            (serviceTrainingExecutionRuntime commandRuntime)
                            AppleSilicon
                            problem
                            trainLimit
                            epochs
                            testLimit
                            batchSize
                            Nothing
                        )
                        env
                    )
                case result of
                  Left err -> pure (Left (SETransient ("host Apple training failed: " <> err)))
                  Right metrics -> do
                    epochResult <- publishTrainingEpoch start metrics
                    case epochResult of
                      Left err -> pure (Left err)
                      Right () -> publishTrainingCheckpoint problem plan start metrics

publishTrainingEpoch
  :: ProtoTraining.StartTraining
  -> TrainingMetrics
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishTrainingEpoch start metrics = do
  timestampNs <- liftIO currentTimestampNs
  let epochNumber = fromIntegral (tmCompletedUnits metrics)
      envelope =
        ProtoTraining.TrainingEpoch
          ( ProtoTraining.EpochCompleted
              { ProtoTraining.ecExperimentHash = ProtoTraining.stExperimentHash start
              , ProtoTraining.ecEpoch = epochNumber
              , -- Sprint 8.13 — real train + held-out validation loss.
                ProtoTraining.ecLoss = tmTrainLoss metrics
              , ProtoTraining.ecValidationLoss = tmValidationLoss metrics
              , ProtoTraining.ecTimestampNs = timestampNs
              }
          )
  publishProtocolEvent Topology.TrainingEventRoute AppleSilicon envelope

publishTrainingCheckpoint
  :: SL.CanonicalProblem
  -> WorkloadPlan.SupervisedPlan
  -> ProtoTraining.StartTraining
  -> TrainingMetrics
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishTrainingCheckpoint problem plan start metrics = do
  let experimentHash = ProtoTraining.stExperimentHash start
      step = tmCompletedUnits metrics
      metricRows = trainingCheckpointMetrics metrics
  case CheckpointWriter.attemptGenericSupervisedRuntimeForTraining
    plan
    problem
    metrics
    experimentHash
    metricRows of
    Left err ->
      pure (Left (SETransient ("invalid supervised V2 checkpoint: " <> err)))
    Right (CheckpointWriter.SupervisedRuntimeCompletionMiss _) ->
      pure (Right ())
    Right (CheckpointWriter.SupervisedRuntimeCompleted completedTraining runtimeArtifact) -> do
      settings <- asks ServiceClients.engineMinIOSettings
      expectedPointer <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              settings
              ( MinIOSubprocess.minioObjectETag
                  ( CheckpointStore.checkpointObjectRef
                      (Checkpoint.latestPointerKey experimentHash)
                  )
              )
          )
      case expectedPointer of
        Left err -> pure (Left err)
        Right expected -> do
          checkpointResult <-
            CheckpointWriter.writeMinIOCompletedSupervisedCheckpoint
              expected
              completedTraining
              experimentHash
              metricRows
              runtimeArtifact
          case checkpointResult of
            Left err -> pure (Left err)
            Right stored ->
              case trainingCompletedCheckpointEventEnvelope
                experimentHash
                step
                metricRows
                completedTraining
                stored of
                Left err -> pure (Left (SETransient ("host Apple checkpoint event failed: " <> err)))
                Right envelope ->
                  publishProtocolEvent Topology.TrainingEventRoute AppleSilicon envelope

runHostAppleTune
  :: Env
  -> ProtoTune.StartSweep
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleTune env start
  | ProtoTune.ssSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple tune received a non-apple-silicon command"))
  | otherwise = case PlanCommand.validateStartSweep start of
      Left err -> pure (Left (SETransient ("host Apple tuning plan validation failed: " <> err)))
      Right plan -> case tuningExecutionCountsService "host Apple tuning" plan of
        Left err -> pure (Left err)
        Right (_trialCount, _parallelism, promotions, _updates) -> do
          let executionSpec = WorkloadPlan.tuningPlanExecutionSpec plan
              runSeedWord =
                NonEmpty.head
                  (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan)))
          if Tune.tuningExecutionDataset executionSpec /= "synthetic"
            then
              pure
                ( Left
                    ( SETransient
                        "host Apple exact tuning requires the spec-selected verified dataset; synthetic legacy plans are the only host-local dataset capability"
                    )
                )
            else case word64ToIntService "host Apple tuning seed" runSeedWord of
              Left err -> pure (Left err)
              Right runSeed -> do
                trialResultsE <-
                  liftIO
                    ( Tune.trialObjectiveResultsWithDeviceForSyntheticExecutionSpec
                        (mlpDeviceForSubstrate AppleSilicon env)
                        runSeed
                        executionSpec
                    )
                case trialResultsE of
                  Left err -> pure (Left (SETransient ("host Apple tune failed: " <> err)))
                  Right trialResults ->
                    case Tune.trialExecutionsForExecutionSpec executionSpec promotions trialResults of
                      Left err -> pure (Left (SETransient ("host Apple tune failed: " <> err)))
                      Right executions ->
                        publishHostTuneEvents
                          plan
                          Tune.syntheticTuningDatasetSha256
                          executions

publishHostTuneEvents
  :: WorkloadPlan.TuningPlan
  -> Text
  -> [Tune.TrialExecution]
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishHostTuneEvents plan datasetShaAtRead trialResults = do
  baseSeed <- case word64ToIntService
    "host Apple tuning seed"
    (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan)))) of
    Left err -> pure (Left err)
    Right value -> pure (Right value)
  case baseSeed of
    Left err -> pure (Left err)
    Right resolvedSeed -> publishWithSeed resolvedSeed
 where
  planId = planIdText (WorkloadPlan.tuningPlanId plan)
  experimentHash = runPlanExperimentId (WorkloadPlan.tuningPlanRunPlan plan)
  publishWithSeed baseSeed = do
    let
      promotedResults =
        [ Tune.trialExecutionResult execution
        | execution <- trialResults
        , Tune.trialExecutionPromoted execution
        ]
      prunedCount = length (filter Tune.trialExecutionPruned trialResults)
      promotedCount = length promotedResults
    publishedResults <- traverse (publishTrial baseSeed) trialResults
    case firstLeft publishedResults of
      Just err -> pure (Left err)
      Nothing ->
        case Tune.selectBestTrialResultForExecutionSpec
          (WorkloadPlan.tuningPlanExecutionSpec plan)
          promotedResults of
          Nothing ->
            pure (Left (SETransient "host Apple tuning produced no promoted ceiling-reaching trial"))
          Just bestResult -> do
            let completed = fromIntegral (length trialResults)
                bestObjective = Tune.trialResultObjective bestResult
                finished =
                  ProtoTune.SweepFinished
                    { ProtoTune.sfExperimentHash = experimentHash
                    , ProtoTune.sfPlanId = planId
                    , ProtoTune.sfTrialsCompleted = completed
                    , ProtoTune.sfTrialsPruned = fromIntegral prunedCount
                    , ProtoTune.sfTrialsPromoted = fromIntegral promotedCount
                    , ProtoTune.sfBestObjective = bestObjective
                    }
            case ProductCompletion.tuneSweepCompletedTraining
              plan
              experimentHash
              datasetShaAtRead
              completed
              bestResult of
              Left err -> pure (Left (SETransient ("host Apple tuning completion failed: " <> err)))
              Right completedTraining ->
                case ProtoTune.completeSweep finished completedTraining of
                  Left err -> pure (Left (SETransient ("host Apple tuning event failed: " <> err)))
                  Right completedSweep ->
                    publishProtocolEvent
                      Topology.TuneEventRoute
                      AppleSilicon
                      (ProtoTune.TuneSweepCompleted completedSweep)

  publishTrial baseSeed execution = do
    timestampStart <- liftIO currentTimestampNs
    let trialResult = Tune.trialExecutionResult execution
        trialIndex = Tune.trialResultIndex trialResult
        trialSeed = baseSeed + trialIndex
        objective = Tune.trialResultObjective trialResult
        started =
          ProtoTune.TuneTrialStarted
            ( ProtoTune.TrialStarted
                { ProtoTune.tsExperimentHash = experimentHash
                , ProtoTune.tsPlanId = planId
                , ProtoTune.tsTrial = fromIntegral trialIndex
                , ProtoTune.tsTrialSeed = fromIntegral trialSeed
                , ProtoTune.tsParametersJson =
                    "{\"sampler\":\""
                      <> Text.pack (show (WorkloadPlan.tuningPlanSampler plan))
                      <> "\",\"scheduler\":\""
                      <> Text.pack (show (WorkloadPlan.tuningPlanScheduler plan))
                      <> "\",\"pruner\":\""
                      <> Text.pack (show (WorkloadPlan.tuningPlanPruner plan))
                      <> "\",\"parallelism\":"
                      <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanParallelism plan)))
                      <> ",\"promotions\":"
                      <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanPromotions plan)))
                      <> ",\"perTrialOptimizerUpdates\":"
                      <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan)))
                      <> "}"
                , ProtoTune.tsTimestampNs = timestampStart
                }
            )
    startResult <-
      publishProtocolEvent Topology.TuneEventRoute AppleSilicon started
    case startResult of
      Left err -> pure (Left err)
      Right () -> do
        persistResult <-
          Tune.persistTrialTranscript
            (Tune.terminalTrialTranscript experimentHash trialSeed trialResult)
        case persistResult of
          Left err -> pure (Left err)
          Right _ -> do
            checkpointResult <-
              if Tune.trialExecutionPromoted execution
                then
                  void
                    <$> CheckpointWriter.writeMinIOCandidateWeightCheckpoint
                      experimentHash
                      "tune-trial-weights"
                      (fromIntegral trialSeed)
                      [("objective", objective)]
                      (Tune.trialResultWeights trialResult)
                else pure (Right ())
            case checkpointResult of
              Left err -> pure (Left err)
              Right () -> do
                timestampEnd <- liftIO currentTimestampNs
                let finished =
                      ProtoTune.TuneTrialFinished
                        ( ProtoTune.TrialFinished
                            { ProtoTune.tfTuneExperimentHash = experimentHash
                            , ProtoTune.tfTunePlanId = planId
                            , ProtoTune.tfTuneTrial = fromIntegral trialIndex
                            , ProtoTune.tfTuneObjective = objective
                            , ProtoTune.tfTunePruned = Tune.trialExecutionPruned execution
                            , ProtoTune.tfTuneTranscriptObjectKey =
                                Tune.trialStorageKey experimentHash trialSeed
                            , ProtoTune.tfTuneTimestampNs = timestampEnd
                            }
                        )
                publishProtocolEvent Topology.TuneEventRoute AppleSilicon finished

tuningExecutionCountsService
  :: Text
  -> WorkloadPlan.TuningPlan
  -> Either ServiceError (Int, Int, Int, Int)
tuningExecutionCountsService label plan =
  (,,,)
    <$> word64ToIntService (label <> " trial count") (quantityValue (WorkloadPlan.tuningPlanTrials plan))
    <*> word64ToIntService
      (label <> " parallelism")
      (quantityValue (WorkloadPlan.tuningPlanParallelism plan))
    <*> word64ToIntService (label <> " promotions") (quantityValue (WorkloadPlan.tuningPlanPromotions plan))
    <*> word64ToIntService
      (label <> " per-trial updates")
      (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan))

word64ToIntService :: Text -> Word64 -> Either ServiceError Int
word64ToIntService label value
  | toInteger value > toInteger (maxBound :: Int) =
      Left (SETransient (label <> " exceeds the platform Int range"))
  | otherwise = Right (fromIntegral value)

runHostAppleRl
  :: Env
  -> ProtoRl.StartRLRun
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleRl env start
  | ProtoRl.srlSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple RL received a non-apple-silicon command"))
  | otherwise =
      case Workload.rlPlanForStart start of
        Left err -> pure (Left (SETransient ("host Apple RL plan invalid: " <> err)))
        Right plan -> do
          let device = rlDeviceForSubstrate AppleSilicon env
          episodesE <-
            liftIO (TrainerExecution.runTrainerEpisodesForPlan AppleSilicon device Nothing plan)
          case episodesE of
            Left err -> pure (Left (SETransient ("host Apple RL failed: " <> err)))
            Right trainerRun -> do
              let planId = ProductBudget.compiledRlPlanId plan
              iterationResults <-
                case trainerRun of
                  TrainerExecution.EvaluationOnly _ -> pure []
                  TrainerExecution.Trained artifact ->
                    traverse
                      (publishHostRlIteration start planId)
                      ( Framework.learningCurveSummaries
                          (TrainerExecution.trainedArtifactLearningCurve artifact)
                      )
              evaluationResults <-
                traverse
                  (publishHostRlEvaluationOutcome start planId)
                  (trainerRunEpisodes trainerRun)
              pure $
                maybe
                  (Right ())
                  Left
                  (firstLeft (iterationResults <> evaluationResults))

runHostAppleAlphaZero
  :: Env
  -> ProtoRl.StartAlphaZeroRun
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleAlphaZero env start
  | ProtoRl.sazSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple AlphaZero received a non-apple-silicon command"))
  | otherwise = case PlanCommand.validateStartAlphaZeroRun start of
      Left err -> pure (Left (SETransient ("host Apple AlphaZero plan validation failed: " <> err)))
      Right plan ->
        case alphaZeroHostInputs plan of
          Left err -> pure (Left err)
          Right (generations, games, sims, maxPlies, updates, arenaGames, seed) -> do
            let gameName = WorkloadPlan.renderAlphaZeroGame (WorkloadPlan.alphaZeroPlanGame plan)
                experimentHash = runPlanExperimentId (WorkloadPlan.alphaZeroPlanRunPlan plan)
                planId = planIdText (WorkloadPlan.alphaZeroPlanId plan)
                initialState = AlphaZero.initialStateFor gameName
                device = rlDeviceForSubstrate AppleSilicon env
                net0 =
                  PolicyValueNet.initPolicyValueNet
                    (AlphaZero.observationSizeFor gameName)
                    (AlphaZero.actionCountFor gameName)
                    16
                    seed
                adam0 = PolicyValueNet.initAdamFor net0
            probe <- liftIO (probeMlpDevice device)
            case probe of
              Left err -> pure (Left (SETransient ("host Apple AlphaZero device failed: " <> err)))
              Right () -> do
                trained <-
                  trainHostAlphaZeroGenerations
                    experimentHash
                    planId
                    initialState
                    device
                    net0
                    adam0
                    generations
                    games
                    sims
                    maxPlies
                    updates
                    seed
                case trained of
                  Left err -> pure (Left err)
                  Right (trainedNet, samples) -> do
                    let winRate =
                          PolicyValueNet.arenaWinRateAgainstUniformFrom
                            initialState
                            trainedNet
                            arenaGames
                            maxPlies
                            (seed + 7919)
                        completedGenerations = fromIntegral generations
                        checkpointStep =
                          ProductCompletion.alphaZeroArtifactStep
                            completedGenerations
                            (length samples)
                        metrics =
                          [ ("arena_win_rate", winRate)
                          , ("legal_move_rate", 1.0)
                          , ("mcts_simulations_per_move", fromIntegral sims)
                          , ("self_play_games", fromIntegral games)
                          , ("self_play_generations", fromIntegral generations)
                          , ("self_play_samples", fromIntegral (length samples))
                          ]
                        initialWeights = PolicyValueNet.policyValueNetToFlat net0
                        finalWeights = PolicyValueNet.policyValueNetToFlat trainedNet
                        completed =
                          do
                            budget <- eitherToMaybe (ProductCompletion.alphaZeroCompletionBudget plan)
                            updatesPerGeneration <-
                              eitherToMaybe
                                ( ProductCompletion.checkedPositiveWord64FromInt
                                    "AlphaZero optimizer updates per generation"
                                    updates
                                )
                            optimizerUpdateCount <-
                              eitherToMaybe
                                ( ProductCompletion.checkedWord64Product
                                    "AlphaZero optimizer update evidence"
                                    completedGenerations
                                    updatesPerGeneration
                                )
                            eitherToMaybe
                              ( ProductCompletion.alphaZeroCompletedTraining
                                  (WorkloadPlan.alphaZeroPlanId plan)
                                  budget
                                  experimentHash
                                  completedGenerations
                                  optimizerUpdateCount
                                  (PolicyValueNet.policyValueTrainingSamplesSha256 samples)
                                  metrics
                                  initialWeights
                                  finalWeights
                              )
                    checkpoint <-
                      case completed of
                        Nothing ->
                          fmap
                            void
                            ( CheckpointWriter.writeMinIOCandidateWeightCheckpoint
                                experimentHash
                                ("alphazero-" <> gameName <> "-policy-value-weights")
                                checkpointStep
                                metrics
                                finalWeights
                            )
                        Just completedTraining ->
                          fmap
                            void
                            ( CheckpointWriter.writeMinIOCompletedWeightCheckpoint
                                Nothing
                                completedTraining
                                experimentHash
                                ("alphazero-" <> gameName <> "-policy-value-weights")
                                checkpointStep
                                metrics
                                finalWeights
                            )
                    case checkpoint of
                      Left err -> pure (Left err)
                      Right _ ->
                        publishProtocolEvent
                          Topology.RlEventRoute
                          AppleSilicon
                          ( ProtoRl.RlArenaCompleted
                              ProtoRl.ArenaCompleted
                                { ProtoRl.acPlanId = planId
                                , ProtoRl.acExperimentHash = experimentHash
                                , ProtoRl.acArenaGames = fromIntegral arenaGames
                                , ProtoRl.acWinRate = winRate
                                }
                          )
 where
  alphaZeroHostInputs plan = do
    generations <-
      convert "host Apple AlphaZero generations" (WorkloadPlan.alphaZeroPlanGenerations plan)
    games <-
      convert "host Apple AlphaZero self-play games" (WorkloadPlan.alphaZeroPlanSelfPlayGames plan)
    sims <-
      convert "host Apple AlphaZero MCTS simulations" (WorkloadPlan.alphaZeroPlanMctsSimulations plan)
    maxPlies <- convert "host Apple AlphaZero max plies" (WorkloadPlan.alphaZeroPlanMaxPlies plan)
    updates <- convert "host Apple AlphaZero optimizer updates" (WorkloadPlan.alphaZeroPlanUpdates plan)
    arenaGames <- convert "host Apple AlphaZero arena games" (WorkloadPlan.alphaZeroPlanArenaGames plan)
    seed <-
      word64ToIntService
        "host Apple AlphaZero seed"
        (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.alphaZeroPlanRunPlan plan))))
    pure (generations, games, sims, maxPlies, updates, arenaGames, seed)
  convert label = word64ToIntService label . quantityValue

trainHostAlphaZeroGenerations
  :: Text
  -> Text
  -> AlphaZero.GameState
  -> MlpDevice
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> ServiceClients.EngineServiceClient
       (Either ServiceError (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample]))
trainHostAlphaZeroGenerations experimentHash planId initialState device = go 0
 where
  go generation net adam generationTarget games sims maxPlies updates seed
    | generation >= generationTarget = pure (Right (net, []))
    | otherwise = do
        sampleResults <-
          liftIO $
            traverse
              ( \gameIndex ->
                  PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                    initialState
                    device
                    net
                    (seed + generation * 7919 + gameIndex)
                    sims
                    maxPlies
              )
              [0 .. games - 1]
        case sequence sampleResults of
          Left err -> pure (Left (SETransient ("host Apple AlphaZero self-play failed: " <> err)))
          Right batches -> do
            let generationSamples = concat batches
            if null generationSamples
              then pure (Left (SETransient "host Apple AlphaZero self-play produced no samples"))
              else do
                trained <-
                  liftIO
                    ( PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
                        device
                        net
                        adam
                        1.0e-3
                        updates
                        generationSamples
                    )
                case trained of
                  Left err -> pure (Left (SETransient ("host Apple AlphaZero training failed: " <> err)))
                  Right (trainedNet, trainedAdam) -> do
                    published <-
                      publishProtocolEvent
                        Topology.RlEventRoute
                        AppleSilicon
                        ( ProtoRl.RlGenerationCompleted
                            ProtoRl.GenerationCompleted
                              { ProtoRl.gcPlanId = planId
                              , ProtoRl.gcExperimentHash = experimentHash
                              , ProtoRl.gcGeneration = fromIntegral generation
                              , ProtoRl.gcSelfPlayGames = fromIntegral games
                              , ProtoRl.gcSamples = fromIntegral (length generationSamples)
                              }
                        )
                    case published of
                      Left err -> pure (Left err)
                      Right () -> do
                        later <-
                          go
                            (generation + 1)
                            trainedNet
                            trainedAdam
                            generationTarget
                            games
                            sims
                            maxPlies
                            updates
                            seed
                        pure (fmap (second (generationSamples <>)) later)

publishHostRlEvaluationOutcome
  :: ProtoRl.StartRLRun
  -> Text
  -> EpisodeEnvelope.SimulatedEpisode
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishHostRlEvaluationOutcome start planId episode = do
  timestampNs <- liftIO currentTimestampNs
  let envelope =
        ProtoRl.RlEvaluation
          ( ProtoRl.EvaluationOutcome
              { ProtoRl.eoPlanId = planId
              , ProtoRl.eoExperimentHash = ProtoRl.srlExperimentHash start
              , ProtoRl.eoEpisodeId = fromIntegral (EpisodeEnvelope.simEpisodeIndex episode)
              , ProtoRl.eoReward = EpisodeEnvelope.simEpisodeReward episode
              , ProtoRl.eoSteps = fromIntegral (EpisodeEnvelope.simEpisodeSteps episode)
              , ProtoRl.eoDone = EpisodeEnvelope.simEpisodeDone episode
              , ProtoRl.eoTimestampNs = timestampNs
              }
          )
      animationEnvelopes =
        fmap
          ( RlCommand.rlAnimationEnvelope
              (ProtoRl.srlExperimentHash start)
              (ProtoRl.srlEnvironment start)
              timestampNs
          )
          (EpisodeEnvelope.simEpisodeFrames episode)
  episodeResult <- publishProtocolEvent Topology.RlEventRoute AppleSilicon envelope
  frameResults <-
    traverse
      (publishProtocolEvent Topology.RlEventRoute AppleSilicon)
      animationEnvelopes
  pure $ maybe (Right ()) Left (firstLeft (episodeResult : frameResults))

publishHostRlIteration
  :: ProtoRl.StartRLRun
  -> Text
  -> Framework.IterationSummary
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishHostRlIteration start planId summary = do
  timestampNs <- liftIO currentTimestampNs
  publishProtocolEvent
    Topology.RlEventRoute
    AppleSilicon
    ( ProtoRl.RlIteration
        ProtoRl.IterationSummary
          { ProtoRl.isPlanId = planId
          , ProtoRl.isExperimentHash = ProtoRl.srlExperimentHash start
          , ProtoRl.isIteration = Framework.iterationSummaryIndex summary
          , ProtoRl.isMetricName = Framework.iterationSummaryMetricName summary
          , ProtoRl.isMetricValue = Framework.iterationSummaryMetricValue summary
          , ProtoRl.isTimestampNs = timestampNs
          }
    )

publishProtocolEvent
  :: (Capabilities.HasPulsar m)
  => Topology.ProtocolRoute event
  -> Substrate
  -> event
  -> m (Either ServiceError ())
publishProtocolEvent route substrate event =
  case Topology.topicFor route substrate of
    Left err ->
      pure (Left (SETransient ("Pulsar topic resolution failed: " <> Text.pack (show err))))
    Right topic ->
      fmap void (Capabilities.pulsarPublish topic event)

publishPulsarEvent
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Topology.ProtocolRoute event
  -> Substrate
  -> event
  -> IO (Either ServiceError Text)
publishPulsarEvent settings route substrate event =
  case Topology.topicFor route substrate of
    Left err ->
      pure (Left (SETransient ("Pulsar topic resolution failed: " <> Text.pack (show err))))
    Right topic ->
      PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
        settings
        (Capabilities.pulsarPublish topic event)
{-# NOINLINE publishPulsarEvent #-}

firstLeft :: [Either a b] -> Maybe a
firstLeft [] = Nothing
firstLeft (Left err : _) = Just err
firstLeft (Right _ : rest) = firstLeft rest

-- | Sprint 5.10 — the host-native Apple daemon acquires only the fixed Metal
-- bridge and the host OS Metal runtime. If the fixed bridge is absent, jitML
-- makes one headless source-build attempt for that process-stable bridge before
-- subscribing to work. Kernel cache misses still only write source metadata and
-- call the bridge.
acquireAppleMetalBridge
  :: ServiceRuntime.DaemonRuntime
  -> App (Either (ServiceRuntime.DaemonRuntime, AppError) ServiceRuntime.DaemonRuntime)
acquireAppleMetalBridge runtime =
  case (BootConfig.bootSubstrate boot, BootConfig.bootInferenceMode boot) of
    (AppleSilicon, BootConfig.SelfInference) -> do
      metalProbe <- liftIO probeMetalRuntime
      bridgeAcquire <- liftIO acquireFixedBridge
      let runtimeAvailable = metalRuntimeAvailable metalProbe
          bridgeAvailable = bridgeAcquireAvailable bridgeAcquire
          statusText =
            "apple.metal-runtime="
              <> renderAcquireBool runtimeAvailable
              <> " apple.metal-bridge="
              <> renderAcquireBool bridgeAvailable
              <> bridgeAcquireSummary bridgeAcquire
          acquired =
            runtime
              { ServiceRuntime.daemonAppleMetalAcquireStatus =
                  if runtimeAvailable && bridgeAvailable
                    then ServiceRuntime.AppleMetalAcquireSucceeded statusText
                    else ServiceRuntime.AppleMetalAcquireFailed statusText
              , ServiceRuntime.daemonState =
                  if runtimeAvailable && bridgeAvailable
                    then
                      RuntimeState.recordMetalAcquired
                        statusText
                        (ServiceRuntime.daemonState runtime)
                    else
                      RuntimeState.recordMetalFailure
                        statusText
                        (ServiceRuntime.daemonState runtime)
              }
      pure $
        if runtimeAvailable && bridgeAvailable
          then Right acquired
          else
            Left
              ( acquired
              , appleMetalAcquireError runtimeAvailable bridgeAvailable
              )
    _ ->
      pure
        ( Right
            runtime
              { ServiceRuntime.daemonState =
                  RuntimeState.recordMetalNotRequired
                    (ServiceRuntime.daemonState runtime)
              }
        )
 where
  boot = ServiceRuntime.daemonBootConfig runtime

acquireFixedBridge :: IO BridgeAcquireResult
acquireFixedBridge = do
  bridgeAvailable <- ContainerPrerequisites.probeFixedMetalBridge
  if bridgeAvailable
    then pure BridgeAlreadyAvailable
    else do
      installed <- MetalBridge.installFixedMetalBridge
      case installed of
        Right path -> do
          verified <- ContainerPrerequisites.probeFixedMetalBridge
          pure $
            if verified
              then BridgeInstalled path
              else BridgeInstallFailed "installed bridge did not pass probe"
        Left err -> pure (BridgeInstallFailed (MetalBridge.renderMetalBridgeInstallError err))

data BridgeAcquireResult
  = BridgeAlreadyAvailable
  | BridgeInstalled FilePath
  | BridgeInstallFailed Text
  deriving stock (Eq, Show)

bridgeAcquireAvailable :: BridgeAcquireResult -> Bool
bridgeAcquireAvailable BridgeAlreadyAvailable = True
bridgeAcquireAvailable BridgeInstalled {} = True
bridgeAcquireAvailable BridgeInstallFailed {} = False

bridgeAcquireSummary :: BridgeAcquireResult -> Text
bridgeAcquireSummary BridgeAlreadyAvailable = " bridge_source=existing"
bridgeAcquireSummary (BridgeInstalled path) = " bridge_source=installed:" <> Text.pack path
bridgeAcquireSummary (BridgeInstallFailed err) = " bridge_install_error=" <> err

appleMetalAcquireError :: Bool -> Bool -> AppError
appleMetalAcquireError runtimeAvailable bridgeAvailable
  | not runtimeAvailable =
      PrerequisiteUnmet
        "apple.metal-runtime"
        "Apple host Metal runtime is unavailable to jitml service."
        ( Just
            "run on Apple Silicon with a visible Metal device; jitML will not use VM, generated package, login-keychain, or full-Xcode remediation for this prerequisite"
        )
  | not bridgeAvailable =
      PrerequisiteUnmet
        "apple.metal-bridge"
        "Fixed jitML Metal bridge dylib is unavailable or its probe failed."
        (Just "build or install the fixed jitML Metal bridge dylib before starting the Apple host daemon")
  | otherwise =
      InvalidConfig "apple Metal acquire failed unexpectedly"

renderAcquireBool :: Bool -> Text
renderAcquireBool True = "yes"
renderAcquireBool False = "no"

runInstallMetalBridge :: App ()
runInstallMetalBridge = do
  installed <- liftIO MetalBridge.installFixedMetalBridge
  case installed of
    Left (MetalBridge.MetalBridgeBuildFailed failure) ->
      exitWithError (SubprocessFailed failure)
    Left err ->
      exitWithError (InvalidConfig (MetalBridge.renderMetalBridgeInstallError err))
    Right path -> do
      writeLine ("metal_bridge: " <> Text.pack path)
      writeLine "metal_bridge_probe: ok"
{-# NOINLINE runInstallMetalBridge #-}

loadServiceConfigs
  :: Text
  -> Bool
  -> App (BootConfig.BootConfig, LiveConfig.LiveConfig)
loadServiceConfigs configPath explicitConfig = do
  let path = Text.unpack configPath
      liveConfigPath = takeDirectory path </> "LiveConfig.dhall"
  exists <- liftIO (doesFileExist path)
  if exists
    then do
      bootResult <- liftIO (tryAny (BootConfig.loadBootConfig path))
      bootConfig <-
        case bootResult of
          Right loaded -> pure loaded
          Left err ->
            exitWithError
              ( InvalidConfig
                  ( "failed to load service config "
                      <> configPath
                      <> ": "
                      <> Text.pack (displayException err)
                  )
              )
      liveExists <- liftIO (doesFileExist liveConfigPath)
      unless liveExists $
        exitWithError
          ( InvalidConfig
              ( "service live config does not exist: "
                  <> Text.pack liveConfigPath
              )
          )
      liveResult <- liftIO (tryAny (LiveConfig.loadLiveConfig liveConfigPath))
      case liveResult of
        Right liveConfig ->
          pure (bootConfig, liveConfig)
        Left err ->
          exitWithError
            ( InvalidConfig
                ( "failed to load service live config "
                    <> Text.pack liveConfigPath
                    <> ": "
                    <> Text.pack (displayException err)
                )
            )
    else
      if explicitConfig
        then exitWithError (InvalidConfig ("service config does not exist: " <> configPath))
        else
          pure
            ( ServiceRuntime.daemonBootConfig ServiceRuntime.defaultDaemonRuntime
            , ServiceRuntime.daemonLiveConfig ServiceRuntime.defaultDaemonRuntime
            )

trainingCandidateCheckpointEventEnvelope
  :: Text
  -> Word64
  -> [(Text, Double)]
  -> CheckpointStore.StoredCandidateCheckpoint
  -> Either Text ProtoTraining.TrainingEvent
trainingCandidateCheckpointEventEnvelope experimentHash step metricRows stored =
  Right
    ( ProtoTraining.TrainingCheckpoint
        ( trainingCheckpointDone
            experimentHash
            step
            metricRows
            (CheckpointStore.candidateStoredCheckpoint stored)
        )
    )
{-# NOINLINE trainingCandidateCheckpointEventEnvelope #-}

trainingCompletedCheckpointEventEnvelope
  :: Text
  -> Word64
  -> [(Text, Double)]
  -> TrainingBudget.CompletedTraining
  -> CheckpointStore.StoredCompletedCheckpoint
  -> Either Text ProtoTraining.TrainingEvent
trainingCompletedCheckpointEventEnvelope experimentHash step metricRows completed stored =
  ProtoTraining.TrainingCompletedCheckpoint
    <$> ProtoTraining.completeCheckpointDone
      ( trainingCheckpointDone
          experimentHash
          step
          metricRows
          (CheckpointStore.completedStoredCheckpoint stored)
      )
      completed
{-# NOINLINE trainingCompletedCheckpointEventEnvelope #-}

trainingCheckpointDone
  :: Text
  -> Word64
  -> [(Text, Double)]
  -> CheckpointStore.StoredCheckpoint
  -> ProtoTraining.CheckpointDone
trainingCheckpointDone experimentHash step metricRows stored =
  ProtoTraining.CheckpointDone
    { ProtoTraining.cdExperimentHash = experimentHash
    , ProtoTraining.cdManifestSha = CheckpointStore.storedManifestSha stored
    , ProtoTraining.cdStep = step
    , ProtoTraining.cdPointerKey = Checkpoint.latestPointerKey experimentHash
    , ProtoTraining.cdEpoch = fromIntegral step
    , ProtoTraining.cdTrialSha = Nothing
    , ProtoTraining.cdRunUuid = "training-" <> experimentHash
    , ProtoTraining.cdMetricsAtStep = metricRows
    }

trainingCheckpointMetrics :: TrainingMetrics -> [(Text, Double)]
trainingCheckpointMetrics metrics =
  [ ("train_loss", tmTrainLoss metrics)
  , ("validation_loss", tmValidationLoss metrics)
  , ("examples_processed", fromIntegral (tmExamplesProcessed metrics))
  ]
    <> maybe [] pure (tmHeldOutMetric metrics)
{-# NOINLINE trainingCheckpointMetrics #-}

currentTimestampNs :: IO Word64
currentTimestampNs = do
  posix <- getPOSIXTime
  pure (floor (posix * 1_000_000_000))
{-# NOINLINE currentTimestampNs #-}

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

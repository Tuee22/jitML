{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Scripted workflow scenarios for the lifecycle negative controls.
--
-- A scenario runs the production interpreter
-- ('JitML.Test.LiveWorkflow.runLiveWorkflow') against a transport, a backend,
-- and a consumer whose every hook is a value the control supplies, so a control
-- can make exactly one thing go wrong (a refused establishment, a failed
-- settlement, a workload that never terminates, a cleanup that fails) and read
-- back what the interpreter did about it.  Nothing here re-implements the
-- interpreter: the scenario builds inputs and records what the interpreter
-- asked its hooks to do.
--
-- Two logs are kept apart on purpose.  The /interpreter log/ holds the hooks the
-- interpreter drives from its own thread (acquire, establish, publish,
-- diagnostics, release, placement, and the local precondition, execute, and
-- resolve hooks); that thread is sequential, so the order is exact.  The
-- /consumer log/ holds what the scripted consumer thread saw.  The consumer and
-- the workload observer run concurrently with the interpreter, so their
-- relative order against the interpreter's is never compared; where a control
-- must force an order between them it does so with the gates of
-- 'ScriptedDelivery' and 'scenarioObserve', which make the order a fact of the
-- scenario and not of the scheduler.
--
-- The baselines ('baselineWorkload', 'baselineRequest', 'baselineLocal') are
-- complete, valid runs.  A control perturbs one field of a baseline, so the
-- rejection it observes is attributable to that field, and the lifecycle
-- baseline guard proves the baselines themselves complete.
--
-- These scenarios stand beside, and do not replace, the HUnit fakes of
-- "JitML.Test.RunContract" and the scripted broker of
-- "JitML.Test.LiveWorkflowEstablishment": those report a mismatch by throwing
-- an HUnit failure and are fixed to one workflow shape, whereas a control needs
-- a verdict it can compare whole, gates that force an arrival order, and the
-- placement, completion mode, and consumer behaviour to vary.
module JitML.Test.LifecycleFixtures
  ( AfterDeliveries (..)
  , BrokerScenario (..)
  , ConsumerEvent (..)
  , Lane (..)
  , LocalScenario (..)
  , Observation (..)
  , ObservationKind (..)
  , PlacementChoice (..)
  , PlanChoice (..)
  , ScenarioCompleted
  , ScenarioEvidence
  , ScenarioFailure
  , ScenarioPrimary
  , ScriptedDelivery (..)
  , Trace (..)
  , awaitThreadFinished
  , baselineLocal
  , baselineRequest
  , baselineWorkload
  , boundedRun
  , classifyJournalEvent
  , completedTrace
  , delivery
  , epochLabel
  , foreignPlan
  , neverTerminal
  , observationKind
  , ownPlan
  , renderPlacement
  , runBrokerScenario
  , runBrokerSourceOnLocalTransport
  , runLocalScenario
  , runLocalSourceOnBrokerTransport
  , sourceLabel
  , terminalName
  , traceOfJournal
  )
where

import Control.Concurrent (ThreadId, threadDelay)
import Control.Concurrent.Async (AsyncCancelled (..))
import Control.Concurrent.MVar
  ( MVar
  , modifyMVar_
  , newEmptyMVar
  , newMVar
  , readMVar
  )
import Control.Exception (mask, throwIO, try)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32)
import GHC.Conc (ThreadStatus (..), threadStatus)
import System.Timeout (timeout)

import JitML.Coordinator.Topology (ProtocolRoute (..), topicFor, topicName)
import JitML.Plan.Plan (PlanId, Validation (..))
import JitML.Proto.Training qualified as Training
import JitML.Service.Capabilities
  ( ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , mkSubscription
  )
import JitML.Service.Pulsar.Internal qualified as PulsarInternal
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.ContractFixtures (planA, planB)
import JitML.Test.LiveWorkflow qualified as LiveWorkflow

-- Scenario result types ------------------------------------------------------

-- | What a scenario's reducer hands back as completed evidence: the events it
-- accepted, rendered, in arrival order ('epochLabel' for a broker delivery, the
-- resolved text for a local run).  The evidence is a real value, not a unit, so
-- a control that compares two completions, or pins what survived a cleanup
-- failure, can tell an interpreter that minted the wrong evidence from one that
-- minted the right one.
type ScenarioEvidence = [Text]

-- | The interpreter instantiated at text terminals, the accepted events as
-- evidence, and text violations and missing-evidence diagnostics, which is all
-- a lifecycle control needs to name what went wrong.
type ScenarioFailure = LiveWorkflow.LiveRunFailure Text ScenarioEvidence Text Text

type ScenarioCompleted = LiveWorkflow.CompletedRunEvidence Text ScenarioEvidence Text Text

type ScenarioPrimary = LiveWorkflow.LivePrimaryFailure Text Text Text

type ScenarioRecord = LiveWorkflow.LiveJournalRecord Text Text Text

-- | Everything a control reads back from one run.
data Observation = Observation
  { obsResult :: Either ScenarioFailure ScenarioCompleted
  , obsInterpreterHooks :: [Text]
  -- ^ The hooks the interpreter drove from its own thread, in order.
  , obsConsumerLog :: [ConsumerEvent]
  -- ^ What the scripted consumer saw, in order.
  , obsPolls :: Int
  -- ^ How many times the interpreter observed the workload.
  }

-- | What the scripted consumer thread observed.
data ConsumerEvent
  = -- | The interpreter attached the consumer to the established source.
    ConsumerAttached
  | -- | The interpreter's decision for one delivery, as the transport would settle it.
    ConsumerSettled PulsarInternal.Disposition
  | -- | The interpreter stopped the consumer.
    ConsumerStopped
  deriving stock (Eq, Show)

-- Scenario description -------------------------------------------------------

-- | Which placement the backend acquires.
data PlacementChoice
  = ClusterPlacement
  | RequestPlacement
  | HostPlacement
  deriving stock (Eq, Show)

-- | Whether the acquired placement belongs to the workflow's plan.
data PlanChoice
  = OwnPlan
  | ForeignPlan
  deriving stock (Eq, Show)

-- | One delivery the scripted consumer hands to the interpreter.
data ScriptedDelivery = ScriptedDelivery
  { deliveryEpoch :: Word32
  , deliveryBefore :: IO ()
  -- ^ Runs in the consumer thread before the delivery is handed over.  A gate
  -- here makes the delivery wait for a fact of the scenario.
  , deliveryAfter :: IO ()
  -- ^ Runs in the consumer thread after the interpreter returned its decision,
  -- so the evidence is already recorded when it runs.
  }

-- | What the consumer does once its deliveries are exhausted.
data AfterDeliveries
  = -- | Stay attached until the interpreter stops it, then rethrow the stop.
    StayAttached
  | -- | Stay attached, and report this failure when the interpreter stops it:
    -- what a transport returns when its final settlement cannot be confirmed
    -- during the drain.
    ReportOnStop ConsumerFailure
  | -- | Fail immediately with this failure.
    FailNow ConsumerFailure
  | -- | Throw a synchronous exception carrying this text.
    RaiseNow Text

-- | A broker-backed run.  The workflow completes when @scenarioRequired@ events
-- have been accepted by its reducer, and its completed evidence is those events
-- in arrival order ('epochLabel'); the epoch @scenarioRejectedEpoch@, when set,
-- is refused by the reducer.
data BrokerScenario = BrokerScenario
  { scenarioCompletion :: LiveWorkflow.LiveCompletionMode
  , scenarioPlacement :: PlacementChoice
  , scenarioPlacementPlan :: PlanChoice
  , scenarioAcquire :: IO (Either LiveWorkflow.ResourceFailure ())
  , scenarioEstablish :: IO (Either ServiceError ())
  , scenarioPublish :: IO (Either ServiceError Text)
  , scenarioReleaseSource :: IO (Either ConsumerFailure ())
  , scenarioDeliveries :: [ScriptedDelivery]
  , scenarioAfterDeliveries :: AfterDeliveries
  , scenarioRequired :: Int
  , scenarioRejectedEpoch :: Maybe Word32
  , scenarioObserve :: Int -> IO (LiveWorkflow.WorkloadObservation Text)
  -- ^ The workload observation for the n-th poll (1-based).
  , scenarioAttempts :: Int
  , scenarioDelayMicros :: Int
  , scenarioTimeoutMicros :: Int
  , scenarioDiagnostics :: IO (Either LiveWorkflow.CleanupIssue [LiveWorkflow.LiveDiagnostic])
  , scenarioReleasePlacement :: IO [LiveWorkflow.CleanupIssue]
  , scenarioOwnedCleanup :: Maybe (IO [LiveWorkflow.CleanupIssue])
  -- ^ A resource owned outside the placement (an object-store fixture) whose
  -- cleanup runs around the whole interpreter call.
  }

-- | A host-executable run with a local evidence source.  The command is never
-- started for real: the interpreter's execute hook is a value.  The completed
-- evidence is the resolved evidence text the reducer accepted.
data LocalScenario = LocalScenario
  { localPlacement :: PlacementChoice
  , localPrecondition :: IO (Either ServiceError Text)
  , localExecute :: IO (Either ServiceError Text)
  , localResolve :: IO (Either ServiceError Text)
  , localRequired :: Int
  , localRejectsEvidence :: Bool
  , localTimeoutMicros :: Int
  , localDiagnostics :: IO (Either LiveWorkflow.CleanupIssue [LiveWorkflow.LiveDiagnostic])
  , localReleasePlacement :: IO [LiveWorkflow.CleanupIssue]
  }

-- | The plan every scenario runs under.
ownPlan :: PlanId
ownPlan = planA

-- | A different plan, for a placement that belongs to somebody else.
foreignPlan :: PlanId
foreignPlan = planB

-- | A delivery with no gates.
delivery :: Word32 -> ScriptedDelivery
delivery epoch =
  ScriptedDelivery
    { deliveryEpoch = epoch
    , deliveryBefore = pure ()
    , deliveryAfter = pure ()
    }

-- | A workload that never reaches a terminal state within any test's lifetime:
-- it reports @Running@ and is polled until the interpreter cancels it.  A
-- scenario uses it when the outcome under test must not depend on the observer.
neverTerminal :: BrokerScenario -> BrokerScenario
neverTerminal scenario =
  scenario
    { scenarioObserve = \_ -> pure (LiveWorkflow.Running (LiveWorkflow.LiveDiagnostic "still running"))
    , scenarioAttempts = 1_000_000
    , scenarioDelayMicros = 5_000
    }

terminalName :: Text
terminalName = "workload-terminal"

-- | The reference run: an independently observed workload on a cluster job, one
-- delivery that completes the evidence, and a workload that succeeds at once.
-- A healthy run takes milliseconds; the five-second workflow timeout is what
-- turns an interpreter that stops reporting a failure into a typed timeout the
-- control can name, instead of a hang.
baselineWorkload :: BrokerScenario
baselineWorkload =
  BrokerScenario
    { scenarioCompletion = LiveWorkflow.ObserveIndependentWorkload
    , scenarioPlacement = ClusterPlacement
    , scenarioPlacementPlan = OwnPlan
    , scenarioAcquire = pure (Right ())
    , scenarioEstablish = pure (Right ())
    , scenarioPublish = pure (Right "scripted-ack")
    , scenarioReleaseSource = pure (Right ())
    , scenarioDeliveries = [delivery 1]
    , scenarioAfterDeliveries = StayAttached
    , scenarioRequired = 1
    , scenarioRejectedEpoch = Nothing
    , scenarioObserve = \_ -> pure (LiveWorkflow.Succeeded terminalName)
    , scenarioAttempts = 1
    , scenarioDelayMicros = 0
    , scenarioTimeoutMicros = 5_000_000
    , scenarioDiagnostics = pure (Right [LiveWorkflow.LiveDiagnostic "scripted diagnostics"])
    , scenarioReleasePlacement = pure []
    , scenarioOwnedCleanup = Nothing
    }

-- | The reference request/reply run: the validated response is itself the
-- completion, so no workload is ever observed.
baselineRequest :: BrokerScenario
baselineRequest =
  baselineWorkload
    { scenarioCompletion = LiveWorkflow.ResponseCompletesRequest
    , scenarioPlacement = RequestPlacement
    }

-- | The reference local run: precondition, command, and one resolved evidence
-- value.
baselineLocal :: LocalScenario
baselineLocal =
  LocalScenario
    { localPlacement = HostPlacement
    , localPrecondition = pure (Right "precondition-observed")
    , localExecute = pure (Right "executed")
    , localResolve = pure (Right "resolved-evidence")
    , localRequired = 1
    , localRejectsEvidence = False
    , localTimeoutMicros = 5_000_000
    , localDiagnostics = pure (Right [LiveWorkflow.LiveDiagnostic "scripted diagnostics"])
    , localReleasePlacement = pure []
    }

-- Logs ------------------------------------------------------------------------

data Logs = Logs
  { interpreterLog :: MVar [Text]
  , consumerLog :: MVar [ConsumerEvent]
  , pollCounter :: IORef Int
  }

newLogs :: IO Logs
newLogs = Logs <$> newMVar [] <*> newMVar [] <*> newIORef 0

interpreterHook :: Logs -> Text -> IO ()
interpreterHook logs label = modifyMVar_ (interpreterLog logs) (pure . (label :))

consumerEvent :: Logs -> ConsumerEvent -> IO ()
consumerEvent logs event = modifyMVar_ (consumerLog logs) (pure . (event :))

observationOf
  :: Logs
  -> Either ScenarioFailure ScenarioCompleted
  -> IO Observation
observationOf logs result = do
  hooks <- readMVar (interpreterLog logs)
  consumer <- readMVar (consumerLog logs)
  polls <- readIORef (pollCounter logs)
  pure
    Observation
      { obsResult = result
      , obsInterpreterHooks = reverse hooks
      , obsConsumerLog = reverse consumer
      , obsPolls = polls
      }

-- Broker scenarios -------------------------------------------------------------

-- | How an accepted epoch appears in a scenario's completed evidence.
epochLabel :: Word32 -> Text
epochLabel epoch = "epoch-" <> Text.pack (show epoch)

-- | The event a delivery of this epoch carries.
epochEvent :: Word32 -> Training.TrainingEvent
epochEvent epoch =
  Training.TrainingEpoch
    Training.EpochCompleted
      { Training.ecExperimentHash = "lifecycle-control"
      , Training.ecEpoch = epoch
      , Training.ecLoss = 0.5
      , Training.ecValidationLoss = 0.25
      , Training.ecTimestampNs = fromIntegral epoch
      }

scriptedDelivery :: Word32 -> PulsarInternal.Delivery Training.TrainingEvent
scriptedDelivery epoch =
  PulsarInternal.Delivery
    { PulsarInternal.deliveryEventInternal = epochEvent epoch
    , PulsarInternal.deliveryReceiptInternal =
        PulsarInternal.DeliveryReceipt
          { PulsarInternal.receiptSessionInternal = "lifecycle-session"
          , PulsarInternal.receiptGenerationInternal = 1
          , PulsarInternal.receiptDeliveryIdInternal =
              "lifecycle-delivery-" <> Text.pack (show epoch)
          }
    , PulsarInternal.deliveryRedeliveryCountInternal = 0
    }

placementFor
  :: PlacementChoice
  -> PlanId
  -> IO LiveWorkflow.Placement
placementFor choice plan =
  case choice of
    ClusterPlacement ->
      LiveWorkflow.ClusterJob <$> requireRight (LiveWorkflow.mkJobHandle plan "jitml-lifecycle-control")
    RequestPlacement ->
      LiveWorkflow.RequestReply <$> requireRight (LiveWorkflow.mkRequestHandle plan "lifecycle-request")
    HostPlacement ->
      LiveWorkflow.HostRun <$> requireRight (LiveWorkflow.mkHostRunHandle plan "lifecycle-host")

-- | A fixture that cannot be built is an exception, which the harness reports
-- as a broken fixture.
requireRight :: (Show err) => Either err value -> IO value
requireRight result =
  case result of
    Right value -> pure value
    Left err -> ioError (userError ("lifecycle fixture could not be built: " <> show err))

-- | The rendered name of a source and its address, as the interpreter labels it
-- in cleanup diagnostics.
sourceLabel :: IO Text
sourceLabel = do
  eventTopic <- requireRight (topicFor TrainingEventRoute LinuxCPU)
  pure (sourceName <> " on " <> topicName eventTopic)

sourceName :: Text
sourceName = "lifecycle-control"

renderPlacement :: LiveWorkflow.Placement -> Text
renderPlacement placement =
  case placement of
    LiveWorkflow.ClusterJob handle -> "cluster-job:" <> LiveWorkflow.jobHandleName handle
    LiveWorkflow.HostRun handle -> "host-run:" <> LiveWorkflow.hostRunHandleKey handle
    LiveWorkflow.RequestReply handle -> "request-reply:" <> LiveWorkflow.requestHandleKey handle

-- | The disposition the interpreter chose for a delivery.
dispositionOf :: PulsarInternal.ConsumerDecision result -> PulsarInternal.Disposition
dispositionOf decision =
  case decision of
    PulsarInternal.ContinueInternal disposition -> disposition
    PulsarInternal.DoneInternal disposition _result -> disposition

-- | Run the production interpreter over a scripted broker scenario.
runBrokerScenario :: BrokerScenario -> IO Observation
runBrokerScenario scenario = do
  logs <- newLogs
  commandTopic <- requireRight (topicFor TrainingCommandRoute LinuxCPU)
  eventTopic <- requireRight (topicFor TrainingEventRoute LinuxCPU)
  owned <- requireRight (mkSubscription eventTopic sourceName FromLatest Owned)
  borrowed <- requireRight (mkSubscription eventTopic sourceName FromLatest Borrowed)
  placement <-
    placementFor
      (scenarioPlacement scenario)
      ( case scenarioPlacementPlan scenario of
          OwnPlan -> ownPlan
          ForeignPlan -> foreignPlan
      )
  neverReleased <- newEmptyMVar :: IO (MVar ())
  let command =
        Training.TrainingStop
          Training.StopTraining
            { Training.stopExperimentHash = "lifecycle-control"
            , Training.stopDrain = True
            }
      transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.liveEstablishEventSource = \_command _source -> do
              interpreterHook logs "establish"
              established <- scenarioEstablish scenario
              pure $ case established of
                Left failure -> Left failure
                Right () ->
                  Right
                    ( LiveWorkflow.establishedEventSource
                        (LiveWorkflow.pulsarEventSource borrowed)
                        ( \_published -> do
                            interpreterHook logs "publish"
                            scenarioPublish scenario
                        )
                        ( do
                            interpreterHook logs "release"
                            scenarioReleaseSource scenario
                        )
                    )
          , LiveWorkflow.liveConsumeEvents = \_established observe handleDelivery -> do
              -- The whole consumer runs masked, unmasking only where it waits,
              -- so the interpreter's stop is never delivered in the gap between
              -- an evidence signal and the wait that turns it into a result.
              mask $ \unmasked -> do
                consumerEvent logs ConsumerAttached
                observe (ConsumerSessionConnected 1)
                let deliverAll scripted =
                      case scripted of
                        [] -> afterDeliveries unmasked
                        next : rest -> do
                          unmasked (deliveryBefore next)
                          decision <- handleDelivery (scriptedDelivery (deliveryEpoch next))
                          consumerEvent logs (ConsumerSettled (dispositionOf decision))
                          deliveryAfter next
                          case decision of
                            PulsarInternal.DoneInternal _ result -> pure (Right result)
                            PulsarInternal.ContinueInternal _ -> deliverAll rest
                    afterDeliveries unmask' =
                      case scenarioAfterDeliveries scenario of
                        StayAttached -> stayAttached unmask' Nothing
                        ReportOnStop failure -> stayAttached unmask' (Just failure)
                        FailNow failure -> pure (Left failure)
                        RaiseNow detail -> ioError (userError (Text.unpack detail))
                    stayAttached unmask' reported = do
                      interrupted <-
                        try (unmask' (readMVar neverReleased))
                          :: IO (Either AsyncCancelled ())
                      case interrupted of
                        Left cancelled -> do
                          consumerEvent logs ConsumerStopped
                          maybe (throwIO cancelled) (pure . Left) reported
                        Right () ->
                          pure (Left (ConsumerProtocolFailure "scripted consumer block was released unexpectedly"))
                deliverAll (scenarioDeliveries scenario)
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId = ownPlan
          , LiveWorkflow.liveWorkflowCommand = LiveWorkflow.ProtocolCommand commandTopic command
          , LiveWorkflow.liveWorkflowEventSource = LiveWorkflow.pulsarEventSource owned
          , LiveWorkflow.liveWorkflowInitialProgress = [] :: ScenarioEvidence
          , LiveWorkflow.liveWorkflowIngest = \progress event ->
              case event of
                Training.TrainingEpoch epoch
                  | Just (Training.ecEpoch epoch) == scenarioRejectedEpoch scenario ->
                      Left ("rejected epoch " <> Text.pack (show (Training.ecEpoch epoch)))
                  | otherwise -> Right (progress <> [epochLabel (Training.ecEpoch epoch)])
                _ -> Left "unscripted event"
          , LiveWorkflow.liveWorkflowFinish = \progress ->
              if length progress >= scenarioRequired scenario
                then Success progress
                else
                  Failure
                    ( "evidence incomplete: "
                        <> Text.pack (show (length progress))
                        <> " of "
                        <> Text.pack (show (scenarioRequired scenario))
                    )
          , LiveWorkflow.liveWorkflowRenderViolation = id
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement = do
              interpreterHook logs "acquire"
              acquired <- scenarioAcquire scenario
              pure (placement <$ acquired)
          , LiveWorkflow.liveCompletionMode = scenarioCompletion scenario
          , LiveWorkflow.liveObserveWorkload = \_placement -> do
              poll <- atomicModifyIORef' (pollCounter logs) (\count -> (count + 1, count + 1))
              scenarioObserve scenario poll
          , LiveWorkflow.liveGatherDiagnostics = \_placement -> do
              interpreterHook logs "diagnostics"
              scenarioDiagnostics scenario
          , LiveWorkflow.liveReleasePlacement = \_placement -> do
              interpreterHook logs "placement"
              scenarioReleasePlacement scenario
          , LiveWorkflow.liveObservationAttempts = scenarioAttempts scenario
          , LiveWorkflow.liveObservationDelayMicros = scenarioDelayMicros scenario
          , LiveWorkflow.liveWorkflowTimeoutMicros = scenarioTimeoutMicros scenario
          }
      run = LiveWorkflow.runLiveWorkflow workflow transport backend
  result <- maybe run (`LiveWorkflow.withOwnedCleanup` run) (scenarioOwnedCleanup scenario)
  observationOf logs result

-- Local scenarios --------------------------------------------------------------

-- | Run the production interpreter over a scripted host-executable scenario.
runLocalScenario :: LocalScenario -> IO Observation
runLocalScenario scenario = do
  logs <- newLogs
  placement <- placementFor (localPlacement scenario) ownPlan
  source <-
    requireRight
      (LiveWorkflow.localEventSource "lifecycle-local" "lifecycle-local-address" id)
  let transport =
        LiveWorkflow.LocalExecutableTransport
          { LiveWorkflow.liveObserveLocalPrecondition = \_command -> do
              interpreterHook logs "observe-precondition"
              localPrecondition scenario
          , LiveWorkflow.liveExecuteLocalCommand = \_command -> do
              interpreterHook logs "execute"
              localExecute scenario
          , LiveWorkflow.liveResolveLocalEvidence = \_command -> do
              interpreterHook logs "resolve"
              localResolve scenario
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId = ownPlan
          , LiveWorkflow.liveWorkflowCommand =
              LiveWorkflow.ExecutableCommand (subprocess "/usr/bin/true" [])
          , LiveWorkflow.liveWorkflowEventSource = source
          , LiveWorkflow.liveWorkflowInitialProgress = [] :: ScenarioEvidence
          , LiveWorkflow.liveWorkflowIngest = \progress event ->
              if localRejectsEvidence scenario
                then Left "rejected local evidence"
                else Right (progress <> [event])
          , LiveWorkflow.liveWorkflowFinish = \progress ->
              if length progress >= localRequired scenario
                then Success progress
                else
                  Failure
                    ( "evidence incomplete: "
                        <> Text.pack (show (length progress))
                        <> " of "
                        <> Text.pack (show (localRequired scenario))
                    )
          , LiveWorkflow.liveWorkflowRenderViolation = id
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement = do
              interpreterHook logs "acquire"
              pure (Right placement)
          , LiveWorkflow.liveCompletionMode = LiveWorkflow.ObserveIndependentWorkload
          , LiveWorkflow.liveObserveWorkload = \_placement -> do
              _ <- atomicModifyIORef' (pollCounter logs) (\count -> (count + 1, ()))
              pure (LiveWorkflow.Succeeded terminalName)
          , LiveWorkflow.liveGatherDiagnostics = \_placement -> do
              interpreterHook logs "diagnostics"
              localDiagnostics scenario
          , LiveWorkflow.liveReleasePlacement = \_placement -> do
              interpreterHook logs "placement"
              localReleasePlacement scenario
          , LiveWorkflow.liveObservationAttempts = 1
          , LiveWorkflow.liveObservationDelayMicros = 0
          , LiveWorkflow.liveWorkflowTimeoutMicros = localTimeoutMicros scenario
          }
  result <- LiveWorkflow.runLiveWorkflow workflow transport backend
  observationOf logs result

-- | A broker evidence source paired with a local executable transport.  The
-- interpreter must refuse the pairing before any of the transport's hooks run.
runBrokerSourceOnLocalTransport :: IO Observation
runBrokerSourceOnLocalTransport = do
  logs <- newLogs
  eventTopic <- requireRight (topicFor TrainingEventRoute LinuxCPU)
  subscription <- requireRight (mkSubscription eventTopic sourceName FromLatest Owned)
  placement <- placementFor HostPlacement ownPlan
  let transport =
        LiveWorkflow.LocalExecutableTransport
          { LiveWorkflow.liveObserveLocalPrecondition = \_command -> do
              interpreterHook logs "observe-precondition"
              pure (Right "observed")
          , LiveWorkflow.liveExecuteLocalCommand = \_command -> do
              interpreterHook logs "execute"
              pure (Right "executed")
          , LiveWorkflow.liveResolveLocalEvidence = \_command -> do
              interpreterHook logs "resolve"
              pure (Left (SEConflict "resolution must not be reached"))
          }
      workflow =
        mismatchedWorkflow (LiveWorkflow.pulsarEventSource subscription)
  result <- LiveWorkflow.runLiveWorkflow workflow transport (mismatchBackend logs placement)
  observationOf logs result

-- | A local evidence source paired with a broker transport.  The interpreter
-- must refuse the pairing before establishing or consuming anything.
runLocalSourceOnBrokerTransport :: IO Observation
runLocalSourceOnBrokerTransport = do
  logs <- newLogs
  placement <- placementFor HostPlacement ownPlan
  source <-
    requireRight
      (LiveWorkflow.localEventSource "lifecycle-local" "lifecycle-local-address" id)
  let transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.liveEstablishEventSource = \_command _source -> do
              interpreterHook logs "establish"
              pure (Left (SEConflict "establishment must not be reached"))
          , LiveWorkflow.liveConsumeEvents = \_established _observe _handle -> do
              consumerEvent logs ConsumerAttached
              pure (Left (ConsumerProtocolFailure "consumption must not be reached"))
          }
      workflow = mismatchedWorkflow source
  result <- LiveWorkflow.runLiveWorkflow workflow transport (mismatchBackend logs placement)
  observationOf logs result

-- | A host-executable workflow over the given evidence source.  It is never
-- allowed to run: the two mismatch scenarios use it to pair a source and a
-- transport of different kinds.
mismatchedWorkflow
  :: LiveWorkflow.LiveEventSource Subprocess event
  -> LiveWorkflow.LiveWorkflow Subprocess event ScenarioEvidence ScenarioEvidence Text Text
mismatchedWorkflow source =
  LiveWorkflow.LiveWorkflow
    { LiveWorkflow.liveWorkflowPlanId = ownPlan
    , LiveWorkflow.liveWorkflowCommand =
        LiveWorkflow.ExecutableCommand (subprocess "/usr/bin/true" [])
    , LiveWorkflow.liveWorkflowEventSource = source
    , LiveWorkflow.liveWorkflowInitialProgress = []
    , LiveWorkflow.liveWorkflowIngest = \progress _event -> Right (progress <> ["evidence observed"])
    , LiveWorkflow.liveWorkflowFinish = \progress ->
        if null progress then Failure "no evidence observed" else Success progress
    , LiveWorkflow.liveWorkflowRenderViolation = id
    }

mismatchBackend :: Logs -> LiveWorkflow.Placement -> LiveWorkflow.LiveBackend Text
mismatchBackend logs placement =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement = do
        interpreterHook logs "acquire"
        pure (Right placement)
    , LiveWorkflow.liveCompletionMode = LiveWorkflow.ObserveIndependentWorkload
    , LiveWorkflow.liveObserveWorkload = \_placement ->
        pure (LiveWorkflow.Succeeded terminalName)
    , LiveWorkflow.liveGatherDiagnostics = \_placement -> do
        interpreterHook logs "diagnostics"
        pure (Right [LiveWorkflow.LiveDiagnostic "scripted diagnostics"])
    , LiveWorkflow.liveReleasePlacement = \_placement -> do
        interpreterHook logs "placement"
        pure []
    , LiveWorkflow.liveObservationAttempts = 1
    , LiveWorkflow.liveObservationDelayMicros = 0
    , LiveWorkflow.liveWorkflowTimeoutMicros = 5_000_000
    }

-- Time bounds ------------------------------------------------------------------

-- | Bound a scenario's wall-clock time.  A run that does not finish is a hung
-- interpreter, not a verdict: it is raised, and the harness reports it as a
-- control whose fixture could not be run.
boundedRun :: IO value -> IO value
boundedRun action = do
  result <- timeout 20_000_000 action
  case result of
    Just value -> pure value
    Nothing -> ioError (userError "the scripted scenario did not finish within 20 seconds")

-- | Wait until a thread has finished.  A scenario uses it to make the workload
-- observer's terminal fact a fact of the journal before any evidence is
-- delivered.
awaitThreadFinished :: ThreadId -> IO ()
awaitThreadFinished thread = go (4_000 :: Int)
 where
  go remaining = do
    status <- threadStatus thread
    case status of
      ThreadFinished -> pure ()
      ThreadDied -> pure ()
      ThreadRunning -> retry remaining
      ThreadBlocked _reason -> retry remaining
  retry remaining
    | remaining <= 0 = ioError (userError "the observer thread never finished")
    | otherwise = threadDelay 500 >> go (remaining - 1)

-- Journal projection -----------------------------------------------------------

-- | The three concurrent writers of the journal.  Each lane is written by one
-- thread, so the order within a lane is exact; the order across lanes is not
-- compared.
data Lane
  = -- | The interpreter's own thread.
    SpineLane
  | -- | The evidence consumer: deliveries, reducer verdicts, dispositions.
    ConsumerLane
  | -- | The workload observer.
    ObserverLane
  deriving stock (Eq, Show)

-- | The state of a workload, without its payload.
data ObservationKind
  = ObservedMissing
  | ObservedPending
  | ObservedRunning
  | ObservedSucceeded
  | ObservedFailed
  | ObservedProbeFailed
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Total over the closed observation sum: a new observation state must be
-- given a kind here before the module compiles.
observationKind :: LiveWorkflow.WorkloadObservation terminal -> ObservationKind
observationKind observation =
  case observation of
    LiveWorkflow.Missing _ -> ObservedMissing
    LiveWorkflow.Pending _ -> ObservedPending
    LiveWorkflow.Running _ -> ObservedRunning
    LiveWorkflow.Succeeded _ -> ObservedSucceeded
    LiveWorkflow.Failed _ -> ObservedFailed
    LiveWorkflow.ProbeFailed _ -> ObservedProbeFailed

-- | Which lane wrote a journal event, and its milestone label.  Total over
-- every journal event constructor.
classifyJournalEvent
  :: LiveWorkflow.LiveJournalEvent terminal violation missing
  -> (Lane, Text)
classifyJournalEvent event =
  case event of
    LiveWorkflow.PlacementAcquired _ -> (SpineLane, "placement-acquired")
    LiveWorkflow.ConsumerSessionObserved _ -> (ConsumerLane, "consumer-session")
    LiveWorkflow.EventSourceEstablished _ _ -> (SpineLane, "source-established")
    LiveWorkflow.EventSourceEstablishmentFailed _ -> (SpineLane, "source-establishment-failed")
    LiveWorkflow.SubscriptionReleased _ -> (SpineLane, "source-released")
    LiveWorkflow.LocalEvidenceSourceReady _ _ -> (SpineLane, "local-source-ready")
    LiveWorkflow.LocalPreconditionObserved _ -> (SpineLane, "local-precondition-observed")
    LiveWorkflow.LocalPreconditionObservationFailed _ -> (SpineLane, "local-precondition-failed")
    LiveWorkflow.CommandPublicationStarted _ _ -> (SpineLane, "publication-started")
    LiveWorkflow.CommandPublished {} -> (SpineLane, "published")
    LiveWorkflow.CommandPublicationFailed _ -> (SpineLane, "publication-failed")
    LiveWorkflow.DeliveryObserved {} -> (ConsumerLane, "delivery-observed")
    LiveWorkflow.DeliveryDispositionSelected _ LiveWorkflow.LiveAck -> (ConsumerLane, "ack")
    LiveWorkflow.DeliveryDispositionSelected _ (LiveWorkflow.LiveNack _) -> (ConsumerLane, "nack")
    LiveWorkflow.ProtocolEvidenceAccepted -> (ConsumerLane, "evidence-accepted")
    LiveWorkflow.ProtocolEvidenceIncomplete _ -> (ConsumerLane, "evidence-incomplete")
    LiveWorkflow.ProtocolEvidenceRejected _ -> (ConsumerLane, "evidence-rejected")
    LiveWorkflow.ProtocolEvidenceCompleted -> (ConsumerLane, "evidence-completed")
    LiveWorkflow.LocalEvidenceResolutionStarted _ -> (SpineLane, "local-resolution-started")
    LiveWorkflow.LocalEvidenceResolutionFailed _ -> (SpineLane, "local-resolution-failed")
    LiveWorkflow.LocalEvidenceObserved _ _ -> (SpineLane, "local-evidence-observed")
    LiveWorkflow.WorkloadStateObserved _ -> (ObserverLane, "workload-observed")
    LiveWorkflow.DiagnosticsGathered _ -> (SpineLane, "diagnostics")
    LiveWorkflow.PlacementReleased _ -> (SpineLane, "placement-released")
    LiveWorkflow.CleanupRecorded _ -> (SpineLane, "cleanup-recorded")

-- | The journal reduced to what is deterministic: the interpreter's own
-- milestones, the consumer's evidence trace, and the distinct workload states in
-- the order they were first observed (a poll count is not a fact of the run).
data Trace = Trace
  { traceSpine :: [Text]
  , traceConsumer :: [Text]
  , traceWorkload :: [ObservationKind]
  }
  deriving stock (Eq, Show)

traceOfJournal :: [ScenarioRecord] -> Trace
traceOfJournal journal =
  Trace
    { traceSpine = [label | (SpineLane, label) <- classified]
    , traceConsumer = [label | (ConsumerLane, label) <- classified]
    , traceWorkload =
        nub
          [ observationKind observation
          | LiveWorkflow.WorkloadStateObserved observation <-
              fmap LiveWorkflow.liveJournalEvent journal
          ]
    }
 where
  classified = fmap (classifyJournalEvent . LiveWorkflow.liveJournalEvent) journal

-- | The trace of a completed run.
completedTrace :: ScenarioCompleted -> Trace
completedTrace = traceOfJournal . LiveWorkflow.completedRunJournal

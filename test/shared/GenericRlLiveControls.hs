{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Actual production CLI and live daemon controls, shared without importing
-- either suite Main or any retained-lane/aggregate test resource. Missing live
-- publication/runtime fails; fixture lifecycle controls remain separate.
module GenericRlLiveControls
  ( genericRlWorkflowMatrixCase
  , genericRlDaemonEventCase
  , genericRlDaemonConvergenceCase
  , genericRlLiveTestCases
  , GenericRlCliPin
  , GenericRlImagePin
  , captureGenericRlCliPin
  , verifyGenericRlCliPin
  , captureGenericRlImagePin
  , verifyGenericRlWorker
  , requireGenericRlRemoteSettings
  , requireGenericRlSelectedSubstrate
  , requireGenericRlCliDefaults
  , genericRlRemotePreflight
  , readGenericRlTrajectory
  , genericRecordBytes
  , ProcessStream (..)
  , OwnedScenarioCleanupFailure (..)
  , JobFailureObservation (..)
  , JobPodObservation (..)
  , requirePreparedCandidateSnapshot
  , preparedSnapshotObjectRefs
  , experimentGcFenceRef
  , assertProcessExitCode
  , assertProcessNotSuccessful
  , assertProcessStreamContains
  , processExitCode
  , processTranscript
  , processStream
  , streamLabel
  , topologyTopic
  , subscriptionFixture
  , withOwnedScenarioCleanup
  , withOwnedScenarioCleanupObserved
  , reportAsyncCleanupIssues
  , tryAnyIntegration
  , runTypedExecutableWorkflowMatrixCell
  , withWorkflowMatrixCheckpoint
  , assertWorkflowMatrixDatasetVerified
  , requireLivePublication
  , validateLivePublication
  , pickRandomSuffix
  , renderJobFailureObservation
  , indentBlock
  , jobStatusIndicatesFailure
  , kubectl
  , kubectlOutput
  , observeFailedJob
  , observeJobPod
  , assertJobDoesNotAppear
  , cleanupMinioObjects
  , withTemporaryMinioObjects
  , renderObjectRef
  , clusterJobBackend
  , observeLivePlacement
  , observeLiveJob
  , statusFieldPositive
  , gatherLivePlacementDiagnostics
  , renderJobPodDiagnostic
  , releaseLivePlacement
  , assertEstablishBeforePublish
  , requireCompletedLiveWorkflow
  , assertAppleHostForwardingSmoke
  , publishThroughCursorOrFail
  , kubectlJobExists
  , cleanupTemporaryKubernetesJob
  , temporaryKubernetesJobCleanupCommands
  , substrateUrlSegment
  , assertFailureWithIO
  , plannedRlEnvironmentSteps
  , pulsarSubscriptionBacklog
  , pulsarSubscriptionNamesWithPrefix
  , pulsarTopicAbsentFromStats
  , locateJitmlBinary
  , installedBinaryPath
  , currentArchDir
  , matchesCurrentPlatform
  , searchForBinary
  ) where

import Control.Concurrent qualified
import Control.Exception qualified
import Control.Exception.Safe qualified as SafeException
import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (eitherDecode)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Bifunctor qualified as Bifunctor
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Either (lefts)
import Data.Foldable (toList, traverse_)
import Data.IORef qualified as IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Unique (hashUnique, newUnique)
import Data.Word (Word64)
import GenericRlPhysicalProof qualified as Physical
import JitML.CLI.Output qualified as Output
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Cluster.Publication qualified as Publication
import JitML.Coordinator.Topology (ProtocolRoute (..), Topic, topicFor, topicName)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Plan.Plan (PlanId, finiteMeasurementValue, refinePlanIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.SourceDigest qualified as SourceDigest
import JitML.Product.ValidationRecord (hexBytes, sha256Hex)
import JitML.Proto.Rl qualified as ProtoRl
import JitML.RL.ConvergenceThresholds
  ( ConvergenceThreshold (..)
  , cohortThreshold
  , passesConvergence
  )
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.Run.Contract (finishContract, initialProgress)
import JitML.SL.Dataset qualified as Dataset
import JitML.Service.Capabilities
  ( BucketName (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , Subscription
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , ack
  , continue
  , deliveryEvent
  , done
  , mkSubscription
  )
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.WorkerPublication qualified as WorkerPublication
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , processFailureExitCode
  , processFailureTranscript
  , renderProcessOutcome
  )
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Sub.Subprocess qualified
import JitML.Substrate (Substrate (..))
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Test.LivePulsarTransport (livePulsarTransport)
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.WorkflowMatrix qualified as WorkflowMatrix
import JitML.Training.Budget qualified as TrainingBudget
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesFileExist
  , listDirectory
  , makeAbsolute
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Info qualified as SystemInfo
import System.Timeout qualified as Timeout
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

genericRlLiveTestCases :: [TestTree]
genericRlLiveTestCases =
  [ genericRlWorkflowMatrixCase
  , genericRlDaemonEventCase
  , genericRlDaemonConvergenceCase
  ]

genericRlWorkflowMatrixCase :: TestTree
genericRlWorkflowMatrixCase =
  testCase
    "live typed-executable WorkflowMatrix executes every current-substrate CLI cell fail-closed (Sprint 12.11)"
    $ do
      publication <- requireLivePublication
      jitmlBinary <- locateJitmlBinary
      binary <- case jitmlBinary of
        Nothing ->
          assertFailure
            "jitml binary not found — needed for Sprint 12.11 WorkflowMatrix live execution"
        Just path -> pure path
      repoRoot <- makeAbsolute "."
      let substrate = Publication.publicationSubstrate publication
          cells =
            filter
              ((== substrate) . WorkflowMatrix.cellSubstrate)
              WorkflowMatrix.workflowMatrix
          inferenceReplyTopic = topologyTopic InferenceResultRoute substrate
          inferenceRequestTopic = topologyTopic InferenceRequestRoute substrate
      length cells @?= length WorkflowMatrix.allWorkflows
      inferenceSubscriptionsBefore <-
        pulsarSubscriptionNamesWithPrefix inferenceReplyTopic "jitml-infer-"
      requestBacklogBefore <-
        pulsarSubscriptionBacklog inferenceRequestTopic "jitml-engine"
      traverse_ (runTypedExecutableWorkflowMatrixCell repoRoot binary publication) cells
      inferenceSubscriptionsAfter <-
        pulsarSubscriptionNamesWithPrefix inferenceReplyTopic "jitml-infer-"
      let leakedSubscriptions =
            filter (`notElem` inferenceSubscriptionsBefore) inferenceSubscriptionsAfter
      leakedSubscriptions @?= []
      -- The matrix's inference cell deliberately targets a checkpoint
      -- that is never admitted. The Engine must ANSWER that request
      -- terminally, not nack it forever: an unsettled request stays on
      -- the shared `jitml-engine` subscription and starves every other
      -- inference command, and the leak compounds on every run.
      requestBacklogAfter <-
        pulsarSubscriptionBacklog inferenceRequestTopic "jitml-engine"
      assertBool
        ( "WorkflowMatrix leaked an unsettled inference request onto the shared "
            <> "jitml-engine subscription: backlog "
            <> show requestBacklogBefore
            <> " -> "
            <> show requestBacklogAfter
        )
        (requestBacklogAfter <= requestBacklogBefore)

genericRlDaemonEventCase :: TestTree
genericRlDaemonEventCase =
  testCase
    "live daemon places StartRLRun by substrate and Linux emits rl.event episodes (Sprint 13.5/13.6/12.12)"
    $ do
      publication <- requireLivePublication
      let edgePort = Publication.publicationEdgePort publication
          pulsarSettings =
            PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          substrate = Publication.publicationSubstrate publication
          commandTopic = topologyTopic RlCommandRoute substrate
          eventTopic = topologyTopic RlEventRoute substrate
      uniqueSuffix <- pickRandomSuffix
      let experimentHash =
            Text.take 16 ("liverl" <> uniqueSuffix <> "abcdef0123456789")
          subscription = "live-rl-event-sub-" <> uniqueSuffix
          evalEpisodes = 2 :: Int
          command =
            ProtoRl.RlStart
              ProtoRl.StartRLRun
                { ProtoRl.srlExperimentHash = experimentHash
                , ProtoRl.srlAlgorithm = "PPO"
                , ProtoRl.srlEnvironment = "cartpole"
                , ProtoRl.srlSubstrate = substrate
                , ProtoRl.srlSeed = 7
                , ProtoRl.srlMaxSteps = 64
                , ProtoRl.srlEvalEpisodes = fromIntegral evalEpisodes
                }
          expectedJobName = "jitml-rl-" <> experimentHash
      case substrate of
        AppleSilicon -> do
          assertAppleHostForwardingSmoke
            pulsarSettings
            commandTopic
            (topologyTopic RlHostCommandRoute AppleSilicon)
            ("live-rl-host-command-sub-" <> uniqueSuffix)
            experimentHash
            command
            (publishThroughCursorOrFail commandTopic "StartRLRun")
            20
          assertJobDoesNotAppear expectedJobName 5
        _ -> do
          rlRunConfig <-
            case command of
              ProtoRl.RlStart start ->
                case Workload.rlRunConfigFor start of
                  Left err ->
                    assertFailureWithIO ("invalid live RL plan: " <> Text.unpack err)
                  Right value -> pure value
              _ -> assertFailureWithIO "live RL fixture did not build StartRLRun"
          let compiledRlPlanId = RunConfig.rlcPlanId rlRunConfig
          contractPlanId <-
            case refinePlanIdText compiledRlPlanId of
              Left err ->
                assertFailureWithIO
                  ("invalid compiled RL PlanId: " <> Text.unpack err)
              Right value -> pure value
          plannedSteps <- plannedRlEnvironmentSteps command
          contract <-
            case LiveEvidence.rlLiveContractForSteps
              contractPlanId
              (fromIntegral evalEpisodes)
              plannedSteps of
              Left err ->
                assertFailureWithIO
                  ("invalid live RL evidence contract: " <> show err)
              Right value -> pure value
          let eventSubscription =
                subscriptionFixture eventTopic subscription FromLatest Owned
              workflow =
                LiveWorkflow.LiveWorkflow
                  { LiveWorkflow.liveWorkflowPlanId = contractPlanId
                  , LiveWorkflow.liveWorkflowCommand =
                      LiveWorkflow.ProtocolCommand commandTopic command
                  , LiveWorkflow.liveWorkflowEventSource =
                      LiveWorkflow.pulsarEventSource eventSubscription
                  , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                  , LiveWorkflow.liveWorkflowIngest =
                      LiveEvidence.ingestRlLiveEvent
                        contractPlanId
                        experimentHash
                        contract
                  , LiveWorkflow.liveWorkflowFinish = finishContract contract
                  , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                  }
              backend =
                clusterJobBackend contractPlanId expectedJobName 600 600
          (proofBackend, verifyPhysical) <-
            prepareGenericRlProducerProof publication command backend
          result <-
            LiveWorkflow.runLiveWorkflow
              workflow
              (livePulsarTransport pulsarSettings)
              proofBackend
          completed <- requireCompletedLiveWorkflow "live RL workflow" result
          let evidence = LiveWorkflow.completedRunEvidence completed
          verifyPhysical evidence
          Map.keys (LiveEvidence.rlCompletedEvaluationSet evidence)
            @?= [0 .. fromIntegral evalEpisodes - 1]

genericRlDaemonConvergenceCase :: TestTree
genericRlDaemonConvergenceCase =
  testCase
    "live PPO cartpole convergence through daemon dispatch clears the literature threshold (Sprint 13.6)"
    $ do
      -- Sprint 13.6 closure for the PPO/cartpole cohort. Publishes a
      -- StartRLRun with a real convergence budget (the compiled plan's
      -- 150 PPO iterations × 2048 rollout steps × 16 vector
      -- environments), waits for the daemon-dispatched Job to
      -- complete, collects the exact plan-bound EvaluationOutcome
      -- cohort off rl.event.<substrate>, and asserts the median of
      -- the complete cohort clears the in-code literature threshold
      -- − slack for (PPO, cartpole). No committed reward fixtures —
      -- the bar is the in-code threshold table and the data is the
      -- live daemon-dispatched run.
      publication <- requireLivePublication
      let edgePort = Publication.publicationEdgePort publication
          pulsarSettings =
            PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          substrate = Publication.publicationSubstrate publication
          commandTopic = topologyTopic RlCommandRoute substrate
          eventTopic = topologyTopic RlEventRoute substrate
      uniqueSuffix <- pickRandomSuffix
      let experimentHash =
            Text.take 16 ("livecv" <> uniqueSuffix <> "abcdef0123456789")
          subscription = "live-rl-convergence-sub-" <> uniqueSuffix
          evalEpisodes = 200 :: Int
          maxSteps = 2048 :: Int
          command =
            ProtoRl.RlStart
              ProtoRl.StartRLRun
                { ProtoRl.srlExperimentHash = experimentHash
                , ProtoRl.srlAlgorithm = "PPO"
                , ProtoRl.srlEnvironment = "cartpole"
                , ProtoRl.srlSubstrate = substrate
                , ProtoRl.srlSeed = 42
                , ProtoRl.srlMaxSteps = fromIntegral maxSteps
                , ProtoRl.srlEvalEpisodes = fromIntegral evalEpisodes
                }
          expectedJobName = "jitml-rl-" <> experimentHash
      threshold <-
        case cohortThreshold "PPO" "cartpole" of
          Just t -> pure t
          Nothing ->
            assertFailure
              "missing PPO/cartpole entry in JitML.RL.ConvergenceThresholds"
              >> pure (ConvergenceThreshold 0 0)
      case substrate of
        AppleSilicon -> do
          assertAppleHostForwardingSmoke
            pulsarSettings
            commandTopic
            (topologyTopic RlHostCommandRoute AppleSilicon)
            ("live-rl-convergence-host-command-sub-" <> uniqueSuffix)
            experimentHash
            command
            ( publishThroughCursorOrFail
                commandTopic
                "StartRLRun convergence"
            )
            20
          assertJobDoesNotAppear expectedJobName 5
        _ -> do
          rlRunConfig <-
            case command of
              ProtoRl.RlStart start ->
                case Workload.rlRunConfigFor start of
                  Left err ->
                    assertFailureWithIO ("invalid live convergence RL plan: " <> Text.unpack err)
                  Right value -> pure value
              _ -> assertFailureWithIO "live convergence fixture did not build StartRLRun"
          let compiledRlPlanId = RunConfig.rlcPlanId rlRunConfig
          contractPlanId <-
            case refinePlanIdText compiledRlPlanId of
              Left err ->
                assertFailureWithIO
                  ("invalid compiled RL PlanId: " <> Text.unpack err)
              Right value -> pure value
          plannedSteps <- plannedRlEnvironmentSteps command
          contract <-
            case LiveEvidence.rlLiveContractForSteps
              contractPlanId
              (fromIntegral evalEpisodes)
              plannedSteps of
              Left err ->
                assertFailureWithIO
                  ("invalid live convergence evidence contract: " <> show err)
              Right value -> pure value
          let eventSubscription =
                subscriptionFixture eventTopic subscription FromLatest Owned
              workflow =
                LiveWorkflow.LiveWorkflow
                  { LiveWorkflow.liveWorkflowPlanId = contractPlanId
                  , LiveWorkflow.liveWorkflowCommand =
                      LiveWorkflow.ProtocolCommand commandTopic command
                  , LiveWorkflow.liveWorkflowEventSource =
                      LiveWorkflow.pulsarEventSource eventSubscription
                  , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                  , LiveWorkflow.liveWorkflowIngest =
                      LiveEvidence.ingestRlLiveEvent
                        contractPlanId
                        experimentHash
                        contract
                  , LiveWorkflow.liveWorkflowFinish = finishContract contract
                  , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                  }
              backend =
                clusterJobBackend contractPlanId expectedJobName 7200 7200
          (proofBackend, verifyPhysical) <-
            prepareGenericRlProducerProof publication command backend
          result <-
            LiveWorkflow.runLiveWorkflow
              workflow
              (livePulsarTransport pulsarSettings)
              proofBackend
          completed <-
            requireCompletedLiveWorkflow "live PPO convergence workflow" result
          let evidence = LiveWorkflow.completedRunEvidence completed
              medianReward =
                finiteMeasurementValue
                  (LiveEvidence.rlCompletedMedianReward evidence)
              episodeCount =
                Map.size (LiveEvidence.rlCompletedEvaluationSet evidence)
          verifyPhysical evidence
          assertBool
            ( "live PPO/cartpole full evaluation median = "
                <> show medianReward
                <> " must clear "
                <> show (literatureTarget threshold - slack threshold)
                <> " ("
                <> show episodeCount
                <> " exact evaluation episodes collected)"
            )
            (passesConvergence threshold medianReward)

-- | Prepare the exact candidate snapshot graph used by both filesystem and
-- live MinIO integration fixtures.  Keeping preparation in the fixture makes
-- cleanup and GC expectations name the writer's snapshot-scoped objects and
-- durable commit, rather than the caller's legacy logical keys.
requirePreparedCandidateSnapshot
  :: Checkpoint.CheckpointManifest
  -> [(Text, ByteString.Lazy.ByteString)]
  -> IO CheckpointStore.PreparedCheckpointSnapshot
requirePreparedCandidateSnapshot manifest payloads =
  case CheckpointStore.prepareCheckpointSnapshot
    CheckpointStore.WriterCandidateSnapshot
    CheckpointStore.WriterNoPointerIntent
    manifest
    payloads of
    Left err ->
      assertFailureWithIO
        ("could not prepare snapshot-scoped checkpoint fixture: " <> Text.unpack err)
    Right prepared -> pure prepared

preparedSnapshotObjectRefs
  :: CheckpointStore.PreparedCheckpointSnapshot
  -> [ObjectRef]
preparedSnapshotObjectRefs prepared =
  fmap
    (CheckpointStore.checkpointObjectRef . fst)
    (CheckpointStore.preparedSnapshotPayloads prepared)
    <> [ CheckpointStore.checkpointObjectRef
           ( Checkpoint.manifestKey
               ( Checkpoint.manifestExperiment
                   (CheckpointStore.preparedSnapshotManifest prepared)
               )
               (CheckpointStore.preparedSnapshotManifestSha prepared)
           )
       , CheckpointStore.checkpointObjectRef
           ( CheckpointStore.writerCommitObjectKey
               (CheckpointStore.preparedSnapshotCommit prepared)
           )
       ]

experimentGcFenceRef :: Text -> ObjectRef
experimentGcFenceRef =
  CheckpointStore.checkpointObjectRef . CheckpointStore.experimentGcFenceObjectKey

data ProcessStream
  = ProcessStdout
  | ProcessStderr

assertProcessExitCode :: String -> ExitCode -> ProcessOutcome -> Assertion
assertProcessExitCode label expected outcome
  | processExitCode outcome == expected = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected exit "
            <> show expected
            <> ", got:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

assertProcessNotSuccessful :: String -> ProcessOutcome -> Assertion
assertProcessNotSuccessful label outcome
  | processExitCode outcome /= ExitSuccess = pure ()
  | otherwise =
      assertFailure
        (label <> ": expected a non-zero exit, got:\n" <> Text.unpack (renderProcessOutcome outcome))

assertProcessStreamContains :: String -> ProcessStream -> Text -> ProcessOutcome -> Assertion
assertProcessStreamContains label stream needle outcome
  | needle `Text.isInfixOf` processStream stream outcome = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected "
            <> streamLabel stream
            <> " to contain "
            <> show needle
            <> ", got:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

processExitCode :: ProcessOutcome -> ExitCode
processExitCode (ProcessSucceeded _) = ExitSuccess
processExitCode (ProcessFailed failure) = processFailureExitCode failure

processTranscript :: ProcessOutcome -> ProcessTranscript
processTranscript (ProcessSucceeded transcript) = transcript
processTranscript (ProcessFailed failure) = processFailureTranscript failure

processStream :: ProcessStream -> ProcessOutcome -> Text
processStream ProcessStdout = processTranscriptStdout . processTranscript
processStream ProcessStderr = processTranscriptStderr . processTranscript

streamLabel :: ProcessStream -> String
streamLabel ProcessStdout = "stdout"
streamLabel ProcessStderr = "stderr"

topologyTopic :: ProtocolRoute event -> Substrate -> Topic event
topologyTopic route substrate =
  case topicFor route substrate of
    Left err -> error ("integration topology invariant failed: " <> show err)
    Right topic -> topic

subscriptionFixture
  :: Topic event
  -> Text
  -> SubscriptionStart
  -> SubscriptionOwnership
  -> Subscription event
subscriptionFixture topic name start ownership =
  case mkSubscription topic name start ownership of
    Left err -> error ("invalid integration subscription fixture: " <> show err)
    Right subscription -> subscription

-- | A synchronous scenario failure and every typed cleanup failure remain
-- visible together.  When cleanup succeeds, the original exception is
-- rethrown unchanged.  This is the assertion-level counterpart to
-- 'LiveWorkflow.withOwnedCleanup' for live fixtures that do not themselves
-- produce a typed workflow result.  An asynchronous primary is never wrapped;
-- concurrent cleanup issues go to an explicit observer before the exact async
-- exception is rethrown.
data OwnedScenarioCleanupFailure = OwnedScenarioCleanupFailure
  { ownedScenarioLabel :: Text
  , ownedScenarioPrimary :: Maybe Control.Exception.SomeException
  , ownedScenarioCleanupIssues :: [LiveWorkflow.CleanupIssue]
  }

instance Show OwnedScenarioCleanupFailure where
  show failure =
    Text.unpack
      ( Text.unlines
          ( [ownedScenarioLabel failure <> " owned-resource cleanup failed"]
              <> maybe
                []
                (\primary -> ["primary failure: " <> Text.pack (show primary)])
                (ownedScenarioPrimary failure)
              <> fmap
                (\issue -> "cleanup failure: " <> LiveWorkflow.unCleanupIssue issue)
                (ownedScenarioCleanupIssues failure)
          )
      )

instance Control.Exception.Exception OwnedScenarioCleanupFailure

withOwnedScenarioCleanup
  :: Text
  -> IO [LiveWorkflow.CleanupIssue]
  -> IO value
  -> IO value
withOwnedScenarioCleanup ownerLabel =
  withOwnedScenarioCleanupObserved
    (reportAsyncCleanupIssues ownerLabel)
    ownerLabel

withOwnedScenarioCleanupObserved
  :: ([LiveWorkflow.CleanupIssue] -> IO ())
  -> Text
  -> IO [LiveWorkflow.CleanupIssue]
  -> IO value
  -> IO value
withOwnedScenarioCleanupObserved observeAsyncCleanup ownerLabel cleanup action = do
  (actionResult, cleanupIssues) <-
    SafeException.generalBracket
      (pure ())
      (\() _exitCase -> safeCleanup)
      (\() -> tryAnyIntegration action)
  case (actionResult, cleanupIssues) of
    (Right value, []) -> pure value
    (Left primary, issues)
      | Just _asyncException <-
          (Control.Exception.fromException primary :: Maybe Control.Exception.SomeAsyncException) -> do
          case issues of
            [] -> pure ()
            _ -> do
              -- Cancellation identity wins.  The cleanup evidence remains
              -- observable through the caller-selected side channel rather
              -- than being hidden inside a replacement exception.
              _ <- tryAnyIntegration (observeAsyncCleanup issues)
              pure ()
          Control.Exception.throwIO primary
    (Left primary, []) -> Control.Exception.throwIO primary
    (Right _value, issues) ->
      Control.Exception.throwIO
        OwnedScenarioCleanupFailure
          { ownedScenarioLabel = ownerLabel
          , ownedScenarioPrimary = Nothing
          , ownedScenarioCleanupIssues = issues
          }
    (Left primary, issues) ->
      Control.Exception.throwIO
        OwnedScenarioCleanupFailure
          { ownedScenarioLabel = ownerLabel
          , ownedScenarioPrimary = Just primary
          , ownedScenarioCleanupIssues = issues
          }
 where
  safeCleanup = do
    attempted <- tryAnyIntegration cleanup
    case attempted of
      Left exception ->
        case Control.Exception.fromException exception of
          Just asyncException ->
            Control.Exception.throwIO
              (asyncException :: Control.Exception.SomeAsyncException)
          Nothing ->
            pure
              [ LiveWorkflow.CleanupIssue
                  ( ownerLabel
                      <> " cleanup threw: "
                      <> Text.pack (show exception)
                  )
              ]
      Right issues -> pure issues

reportAsyncCleanupIssues
  :: Text
  -> [LiveWorkflow.CleanupIssue]
  -> IO ()
reportAsyncCleanupIssues ownerLabel =
  traverse_
    ( \issue ->
        Output.writeErrorLineIO
          ( ownerLabel
              <> " asynchronous cleanup failure: "
              <> LiveWorkflow.unCleanupIssue issue
          )
    )

tryAnyIntegration
  :: IO value
  -> IO (Either Control.Exception.SomeException value)
tryAnyIntegration = Control.Exception.try

-- | Sprint 12.11's matrix is public-CLI execution coverage.  Each cell is a
-- typed executable command whose successful process outcome and documented
-- stdout are the contract; it is deliberately not given a fabricated broker
-- subscription or workload terminal witness.  Protocol completion is covered
-- by the dedicated daemon-dispatch scenarios below through 'runLiveWorkflow'.
runTypedExecutableWorkflowMatrixCell
  :: FilePath
  -> FilePath
  -> Publication.ClusterPublication
  -> WorkflowMatrix.WorkflowCell
  -> IO ()
runTypedExecutableWorkflowMatrixCell repoRoot binary publication cell =
  case WorkflowMatrix.cellWorkflow cell of
    WorkflowMatrix.SlTrain -> do
      assertWorkflowMatrixDatasetVerified minioSettings
      runWorkflowCommandExpecting ["train:", "substrate=" <> substrateUrlSegment substrate]
    WorkflowMatrix.SlEval ->
      withWorkflowMatrixCheckpoint
        minioSettings
        "workflow-matrix-eval"
        runWorkflowCommandExpectingAdmissionFailure
    WorkflowMatrix.RlTrain ->
      runWorkflowCommandExpecting ["rl train:", "avg-reward:", "rl-replay-artifact-key:"]
    WorkflowMatrix.RlEval ->
      withWorkflowMatrixCheckpoint
        minioSettings
        "workflow-matrix-eval"
        runWorkflowCommandExpectingAdmissionFailure
    WorkflowMatrix.RlRollout ->
      runWorkflowCommandExpecting ["rl rollout:", "rewards=", "rl-rollout-artifact-key:"]
    WorkflowMatrix.Tune ->
      runWorkflowCommandExpecting
        [ "sampler: TPE"
        , "objectives:"
        , "trial-checkpoint-manifest-sha:"
        , "tune-trials-artifact-key:"
        ]
    WorkflowMatrix.Inference ->
      withWorkflowMatrixCheckpoint
        minioSettings
        "workflow-matrix-inference"
        runWorkflowCommandExpectingAdmissionFailure
    WorkflowMatrix.AlphaZeroSelfPlay ->
      runWorkflowCommandExpecting
        [ "rl alphazero self-play:"
        , "samples:"
        , "arena-win-rate:"
        , "checkpoint-manifest-sha:"
        , "alphazero-transcript-artifact-key:"
        ]
 where
  substrate = Publication.publicationSubstrate publication
  minioSettings =
    MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
  runWorkflowCommandExpecting snippets = do
    cliPin <- case WorkflowMatrix.cellWorkflow cell of
      WorkflowMatrix.RlTrain -> do
        requireGenericRlCliDefaults
        pin <- captureGenericRlCliPin (pure (Just binary))
        start <- genericRlCliStart publication
        settings <- requireGenericRlRemoteSettings substrate
        genericRlRemotePreflight settings start pin
        pure (Just (pin, start, settings))
      _ -> pure Nothing
    let command =
          (subprocess binary (WorkflowMatrix.cellCommand cell))
            { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
            }
        executableCommand = LiveWorkflow.ExecutableCommand command
        canonicalCommand = LiveWorkflow.liveCommandCanonicalText executableCommand
    outcome <- runStreaming defaultSubprocessEnv command
    assertProcessExitCode
      ("WorkflowMatrix cell " <> Text.unpack canonicalCommand)
      ExitSuccess
      outcome
    traverse_
      ( \snippet ->
          assertProcessStreamContains
            ("WorkflowMatrix cell " <> Text.unpack canonicalCommand)
            ProcessStdout
            snippet
            outcome
      )
      snippets
    case cliPin of
      Nothing -> pure ()
      Just (pin, start, settings) ->
        assertGenericRlCliPublication
          publication
          pin
          start
          settings
          (processTranscriptStdout (processTranscript outcome))
  runWorkflowCommandExpectingAdmissionFailure = do
    let command =
          (subprocess binary (WorkflowMatrix.cellCommand cell))
            { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
            }
    outcome <- runStreaming defaultSubprocessEnv command
    assertProcessNotSuccessful
      "WorkflowMatrix candidate checkpoint is not inference-admitted"
      outcome

withWorkflowMatrixCheckpoint
  :: MinIOSubprocess.MinIOSettings
  -> Text
  -> IO value
  -> IO value
withWorkflowMatrixCheckpoint settings experimentHash action = do
  let payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
      blobObjectKey =
        Checkpoint.blobKey
          experimentHash
          (WeightCodec.jmw1ContentSha payload)
      manifest =
        ( Checkpoint.emptyManifest
            "workflow-matrix"
            experimentHash
            [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
        )
          { Checkpoint.manifestStep = 1
          , Checkpoint.manifestMetrics = [("validation_accuracy", 0.9)]
          }
      ownerLabel = "WorkflowMatrix checkpoint " <> experimentHash
  prepared <-
    requirePreparedCandidateSnapshot
      manifest
      [(blobObjectKey, payload)]
  let ownedObjects =
        preparedSnapshotObjectRefs prepared
          <> [experimentGcFenceRef experimentHash]
  withTemporaryMinioObjects settings ownerLabel ownedObjects $ do
    staleCleanupIssues <- cleanupMinioObjects settings ownerLabel ownedObjects
    case staleCleanupIssues of
      [] -> pure ()
      issues ->
        Control.Exception.throwIO
          OwnedScenarioCleanupFailure
            { ownedScenarioLabel = ownerLabel
            , ownedScenarioPrimary = Nothing
            , ownedScenarioCleanupIssues = issues
            }
    MinIOSubprocess.runMinIOSubprocess settings $ do
      written <-
        CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
          manifest
          [(blobObjectKey, payload)]
      liftIO $ case written of
        Right _ -> pure ()
        Left err ->
          assertFailure
            ( "WorkflowMatrix checkpoint staging failed for "
                <> Text.unpack experimentHash
                <> ": "
                <> show err
            )
    -- The inference cell publishes a durable request against this deliberately
    -- unadmitted checkpoint, and the bracket below deletes the staged objects as
    -- soon as this returns. That is safe only because the Engine now ANSWERS an
    -- absent checkpoint terminally: `jitml inference run` returns once its reply
    -- arrives, so the request is already settled here. The enclosing test's
    -- `jitml-engine` backlog assertion is what holds that guarantee to account.
    action

assertWorkflowMatrixDatasetVerified :: MinIOSubprocess.MinIOSettings -> IO ()
assertWorkflowMatrixDatasetVerified settings =
  MinIOSubprocess.runMinIOSubprocess settings $ do
    results <-
      traverse
        (uncurry Dataset.fetchVerifiedDatasetArtifactBytes)
        [ (trainRef, Dataset.ImagesArtifact)
        , (trainRef, Dataset.LabelsArtifact)
        , (testRef, Dataset.ImagesArtifact)
        , (testRef, Dataset.LabelsArtifact)
        ]
    liftIO $
      case lefts results of
        [] -> pure ()
        err : _ ->
          assertFailure
            ( "WorkflowMatrix SL training requires real canonical MNIST bytes staged through "
                <> "`jitml internal upload-dataset`; synthetic canonical-key payloads are forbidden. Got: "
                <> show err
            )
 where
  trainRef = Dataset.DatasetRef "MNIST" Dataset.TrainSplit 0 "ignored"
  testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}

-- | Read the live cluster publication artifact written by
-- `JitML.Bootstrap.liveExecutePhasedRollout`. Used by Sprint 13.2's `Live`
-- tests so each capability-class assertion targets the actually-leased edge
-- port and the actually-bootstrapped substrate. Fails the test with a clear
-- message when the file is missing — `-p Live` is an explicit opt-in and
-- silently passing without a cluster up would defeat the validation.
requireLivePublication :: IO Publication.ClusterPublication
requireLivePublication = do
  let path = ".build/runtime/cluster-publication.json"
  exists <- doesFileExist path
  if not exists
    then
      assertFailureWithIO
        ( "cluster-publication.json not found at "
            <> path
            <> "; bring the cluster up via `jitml bootstrap --<substrate>` "
            <> "before running `-p Live` tests"
        )
    else do
      bytes <- ByteString.Lazy.readFile path
      case eitherDecode bytes of
        Left err -> assertFailureWithIO ("failed to decode cluster-publication.json: " <> err)
        Right publication ->
          case validateLivePublication publication of
            Left err -> assertFailureWithIO err
            Right livePublication -> pure livePublication

-- | Fail closed after JSON decoding: a syntactically valid publication is not
-- sufficient authority to run the live integration suite. The bootstrap must
-- have published its marker together with exactly one ready row for every
-- required component.
validateLivePublication
  :: Publication.ClusterPublication
  -> Either String Publication.ClusterPublication
validateLivePublication publication
  | Publication.publicationHasLiveEvidence publication = Right publication
  | otherwise =
      Left
        ( "cluster-publication.json does not contain complete live-readiness evidence; "
            <> "bring the cluster up via `jitml bootstrap --<substrate>` before running `-p Live` tests"
        )

-- | Per-run unique suffix so a re-run on the same cluster does not collide
-- with a still-present object/subscription from a prior run.
pickRandomSuffix :: IO Text
pickRandomSuffix = do
  micros <- round . (* 1_000_000) <$> getPOSIXTime :: IO Integer
  unique <- hashUnique <$> newUnique
  pure (Text.pack (show micros <> "-" <> show unique))

data JobFailureObservation = JobFailureObservation
  { failedJobName :: Text
  , failedJobStatus :: Text
  , failedJobDescribe :: Text
  , failedJobPods :: [JobPodObservation]
  }
  deriving stock (Eq, Show)

data JobPodObservation = JobPodObservation
  { observedPodName :: Text
  , observedPodDescribe :: Text
  , observedPodLogs :: Text
  }
  deriving stock (Eq, Show)

renderJobFailureObservation :: JobFailureObservation -> Text
renderJobFailureObservation observation =
  Text.unlines $
    [ "Kubernetes Job "
        <> failedJobName observation
        <> " failed before the live test completed."
    , "Job status:"
    , indentBlock (failedJobStatus observation)
    , "Job describe:"
    , indentBlock (failedJobDescribe observation)
    , "Owning pods:"
    ]
      <> podSections
 where
  podSections =
    case failedJobPods observation of
      [] -> ["  <none>"]
      pods -> concatMap renderPod pods
  renderPod pod =
    [ "  " <> observedPodName pod
    , "  Pod describe:"
    , indentBlock (observedPodDescribe pod)
    , "  Pod logs:"
    , indentBlock (observedPodLogs pod)
    ]

indentBlock :: Text -> Text
indentBlock block =
  Text.unlines (fmap ("  " <>) (Text.lines (Text.strip block)))

jobStatusIndicatesFailure :: Text -> Bool
jobStatusIndicatesFailure statusText =
  "Failed:True" `Text.isInfixOf` statusText
    || "BackoffLimitExceeded" `Text.isInfixOf` statusText
    || "DeadlineExceeded" `Text.isInfixOf` statusText

kubectl :: [Text] -> IO ProcessOutcome
kubectl args =
  runStreaming
    defaultSubprocessEnv
    ( subprocess
        "kubectl"
        (["--kubeconfig", "./.build/jitml.kubeconfig"] <> args)
    )

kubectlOutput :: ProcessOutcome -> Text
kubectlOutput = renderProcessOutcome

observeFailedJob :: Text -> IO (Maybe JobFailureObservation)
observeFailedJob jobName = do
  statusOutcome <-
    kubectl
      [ "get"
      , "job"
      , jobName
      , "-n"
      , "platform"
      , "--ignore-not-found"
      , "-o"
      , "jsonpath={range .status.conditions[*]}{.type}:{.status}:{.reason}{\"\\n\"}{end}"
      ]
  case statusOutcome of
    ProcessFailed _ -> do
      _ <-
        assertFailure
          ( "kubectl failed while observing Job status for "
              <> Text.unpack jobName
              <> ":\n"
              <> Text.unpack (renderProcessOutcome statusOutcome)
          )
      pure Nothing
    ProcessSucceeded statusTranscript ->
      if not (jobStatusIndicatesFailure (processTranscriptStdout statusTranscript))
        then pure Nothing
        else do
          describeOutcome <- kubectl ["describe", "job", jobName, "-n", "platform"]
          podOutcome <-
            kubectl
              [ "get"
              , "pods"
              , "-n"
              , "platform"
              , "-l"
              , "job-name=" <> jobName
              , "-o"
              , "name"
              ]
          let podNames =
                case podOutcome of
                  ProcessSucceeded transcript ->
                    filter
                      (not . Text.null)
                      (fmap Text.strip (Text.lines (processTranscriptStdout transcript)))
                  ProcessFailed _ -> []
          podObservations <- traverse observeJobPod podNames
          let podListing =
                if processExitCode podOutcome == ExitSuccess
                  then ""
                  else "\nPod listing failed:\n" <> kubectlOutput podOutcome
          pure
            ( Just
                JobFailureObservation
                  { failedJobName = jobName
                  , failedJobStatus = kubectlOutput statusOutcome
                  , failedJobDescribe = kubectlOutput describeOutcome <> podListing
                  , failedJobPods = podObservations
                  }
            )

observeJobPod :: Text -> IO JobPodObservation
observeJobPod podName = do
  describeOutcome <- kubectl ["describe", podName, "-n", "platform"]
  logsOutcome <-
    kubectl
      [ "logs"
      , podName
      , "-n"
      , "platform"
      , "--all-containers=true"
      , "--tail=200"
      ]
  pure
    JobPodObservation
      { observedPodName = podName
      , observedPodDescribe = kubectlOutput describeOutcome
      , observedPodLogs = kubectlOutput logsOutcome
      }

assertJobDoesNotAppear :: Text -> Int -> IO ()
assertJobDoesNotAppear jobName remaining
  | remaining <= 0 = pure ()
  | otherwise = do
      exists <- kubectlJobExists jobName
      if exists
        then do
          failed <- observeFailedJob jobName
          case failed of
            Just observation ->
              assertFailure
                ( Text.unpack
                    ( "unexpected Apple host-resident workload Job appeared:\n"
                        <> renderJobFailureObservation observation
                    )
                )
            Nothing -> do
              describeOutcome <- kubectl ["describe", "job", jobName, "-n", "platform"]
              assertFailure
                ( Text.unpack
                    ( Text.unlines
                        [ "unexpected Apple host-resident workload Job appeared: " <> jobName
                        , kubectlOutput describeOutcome
                        ]
                    )
                )
        else do
          Control.Concurrent.threadDelay 1_000_000
          assertJobDoesNotAppear jobName (remaining - 1)

cleanupMinioObjects
  :: MinIOSubprocess.MinIOSettings
  -> Text
  -> [ObjectRef]
  -> IO [LiveWorkflow.CleanupIssue]
cleanupMinioObjects settings ownerLabel refs =
  concat <$> traverse cleanupOne refs
 where
  cleanupOne ref = do
    attempted <-
      Control.Exception.try
        ( MinIOSubprocess.runMinIOSubprocess
            settings
            (deleteObject ref)
        )
        :: IO
             ( Either
                 Control.Exception.SomeException
                 (Either ServiceError ())
             )
    case attempted of
      Left exception ->
        case Control.Exception.fromException exception of
          Just asyncException ->
            Control.Exception.throwIO
              (asyncException :: Control.Exception.SomeAsyncException)
          Nothing ->
            pure
              [ LiveWorkflow.CleanupIssue
                  ( ownerLabel
                      <> " failed to delete temporary object "
                      <> renderObjectRef ref
                      <> ": "
                      <> Text.pack (show exception)
                  )
              ]
      Right (Left failure) ->
        pure
          [ LiveWorkflow.CleanupIssue
              ( ownerLabel
                  <> " failed to delete temporary object "
                  <> renderObjectRef ref
                  <> ": "
                  <> Text.pack (show failure)
              )
          ]
      Right (Right ()) -> pure []

withTemporaryMinioObjects
  :: MinIOSubprocess.MinIOSettings
  -> Text
  -> [ObjectRef]
  -> IO value
  -> IO value
withTemporaryMinioObjects settings ownerLabel refs =
  withOwnedScenarioCleanup
    ownerLabel
    (cleanupMinioObjects settings ownerLabel refs)

renderObjectRef :: ObjectRef -> Text
renderObjectRef ref =
  unBucketName (objectBucket ref)
    <> "/"
    <> unObjectKey (objectKey ref)

clusterJobBackend
  :: PlanId
  -> Text
  -> Int
  -> Int
  -> LiveWorkflow.LiveBackend Text
clusterJobBackend planId jobName observationAttempts timeoutSeconds =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement =
        pure
          ( Bifunctor.first
              (LiveWorkflow.ResourceFailure . Text.pack . show)
              (LiveWorkflow.ClusterJob <$> LiveWorkflow.mkJobHandle planId jobName)
          )
    , LiveWorkflow.liveCompletionMode =
        LiveWorkflow.ObserveIndependentWorkload
    , LiveWorkflow.liveObserveWorkload = observeLivePlacement
    , LiveWorkflow.liveGatherDiagnostics = gatherLivePlacementDiagnostics
    , LiveWorkflow.liveReleasePlacement = releaseLivePlacement
    , LiveWorkflow.liveObservationAttempts = max 1 observationAttempts
    , LiveWorkflow.liveObservationDelayMicros = 1_000_000
    , LiveWorkflow.liveWorkflowTimeoutMicros = max 1 timeoutSeconds * 1_000_000
    }

observeLivePlacement :: LiveWorkflow.Placement -> IO (LiveWorkflow.WorkloadObservation Text)
observeLivePlacement placement =
  case placement of
    LiveWorkflow.HostRun handle ->
      pure
        ( LiveWorkflow.ProbeFailed
            ( LiveWorkflow.ProbeFailure
                ( "cluster observer received host handle "
                    <> LiveWorkflow.hostRunHandleKey handle
                )
            )
        )
    LiveWorkflow.RequestReply handle ->
      pure
        ( LiveWorkflow.ProbeFailed
            ( LiveWorkflow.ProbeFailure
                ( "cluster observer received request handle "
                    <> LiveWorkflow.requestHandleKey handle
                )
            )
        )
    LiveWorkflow.ClusterJob handle -> observeLiveJob (LiveWorkflow.jobHandleName handle)

observeLiveJob :: Text -> IO (LiveWorkflow.WorkloadObservation Text)
observeLiveJob jobName = do
  outcome <-
    kubectl
      [ "get"
      , "job"
      , jobName
      , "-n"
      , "platform"
      , "--ignore-not-found"
      , "-o"
      , Text.concat
          [ "jsonpath={.metadata.name}{\"\\n\"}"
          , "{range .status.conditions[*]}{.type}:{.status}:{.reason}{\"\\n\"}{end}"
          , "active={.status.active}{\"\\n\"}"
          , "succeeded={.status.succeeded}{\"\\n\"}"
          , "failed={.status.failed}{\"\\n\"}"
          ]
      ]
  case outcome of
    ProcessFailed _ ->
      pure
        ( LiveWorkflow.ProbeFailed
            (LiveWorkflow.ProbeFailure (renderProcessOutcome outcome))
        )
    ProcessSucceeded transcript -> do
      let status = Text.strip (processTranscriptStdout transcript)
          diagnostic = LiveWorkflow.LiveDiagnostic status
      if Text.null status
        then pure (LiveWorkflow.Missing (LiveWorkflow.LiveDiagnostic ("missing Job " <> jobName)))
        else
          if jobStatusIndicatesFailure status || statusFieldPositive "failed" status
            then
              pure
                ( LiveWorkflow.Failed
                    (LiveWorkflow.WorkloadFailure status)
                )
            else
              if "Complete:True" `Text.isInfixOf` status
                || statusFieldPositive "succeeded" status
                then pure (LiveWorkflow.Succeeded status)
                else
                  if statusFieldPositive "active" status
                    then pure (LiveWorkflow.Running diagnostic)
                    else pure (LiveWorkflow.Pending diagnostic)

statusFieldPositive :: Text -> Text -> Bool
statusFieldPositive fieldName status =
  any positiveLine (Text.lines status)
 where
  prefix = fieldName <> "="
  positiveLine line =
    case reads (Text.unpack (Text.drop (Text.length prefix) line)) of
      [(value :: Int, "")] -> prefix `Text.isPrefixOf` line && value > 0
      _ -> False

gatherLivePlacementDiagnostics
  :: LiveWorkflow.Placement
  -> IO (Either LiveWorkflow.CleanupIssue [LiveWorkflow.LiveDiagnostic])
gatherLivePlacementDiagnostics placement =
  case placement of
    LiveWorkflow.HostRun handle ->
      pure
        ( Right
            [ LiveWorkflow.LiveDiagnostic
                ("host-run-key: " <> LiveWorkflow.hostRunHandleKey handle)
            ]
        )
    LiveWorkflow.RequestReply handle ->
      pure
        ( Right
            [ LiveWorkflow.LiveDiagnostic
                ("request-key: " <> LiveWorkflow.requestHandleKey handle)
            ]
        )
    LiveWorkflow.ClusterJob handle -> do
      let jobName = LiveWorkflow.jobHandleName handle
      describeOutcome <- kubectl ["describe", "job", jobName, "-n", "platform"]
      podOutcome <-
        kubectl
          [ "get"
          , "pods"
          , "-n"
          , "platform"
          , "-l"
          , "job-name=" <> jobName
          , "-o"
          , "name"
          ]
      let podNames =
            case podOutcome of
              ProcessSucceeded transcript ->
                filter
                  (not . Text.null)
                  (fmap Text.strip (Text.lines (processTranscriptStdout transcript)))
              ProcessFailed _ -> []
      pods <- traverse observeJobPod podNames
      pure
        ( Right
            ( LiveWorkflow.LiveDiagnostic (renderProcessOutcome describeOutcome)
                : LiveWorkflow.LiveDiagnostic (renderProcessOutcome podOutcome)
                : fmap
                  (LiveWorkflow.LiveDiagnostic . renderJobPodDiagnostic)
                  pods
            )
        )

renderJobPodDiagnostic :: JobPodObservation -> Text
renderJobPodDiagnostic pod =
  Text.unlines
    [ observedPodName pod
    , observedPodDescribe pod
    , observedPodLogs pod
    ]

releaseLivePlacement
  :: LiveWorkflow.Placement
  -> IO [LiveWorkflow.CleanupIssue]
releaseLivePlacement placement =
  case placement of
    LiveWorkflow.HostRun _ -> pure []
    LiveWorkflow.RequestReply _ -> pure []
    LiveWorkflow.ClusterJob handle -> do
      let jobName = LiveWorkflow.jobHandleName handle
      cleanupTemporaryKubernetesJob "live workflow placement" jobName

-- | The event source is established (the broker acknowledged the durable
-- cursor) before the command is published.  A socket-open lifecycle record is
-- deliberately not consulted: it is not evidence that the cursor exists.
assertEstablishBeforePublish
  :: (Show terminal, Show violation, Show missing)
  => LiveWorkflow.CompletedRunEvidence terminal evidence violation missing
  -> Assertion
assertEstablishBeforePublish completed = do
  let entries = LiveWorkflow.completedRunJournal completed
      establishmentSequences =
        [ LiveWorkflow.liveJournalSequence entry
        | entry <- entries
        , LiveWorkflow.EventSourceEstablished _ _ <- [LiveWorkflow.liveJournalEvent entry]
        ]
      publicationSequences =
        [ LiveWorkflow.liveJournalSequence entry
        | entry <- entries
        , LiveWorkflow.CommandPublicationStarted {} <- [LiveWorkflow.liveJournalEvent entry]
        ]
  case (establishmentSequences, publicationSequences) of
    (establishmentSequence : _, publicationSequence : _) ->
      assertBool
        "live workflow event source must be established before command publication"
        (establishmentSequence < publicationSequence)
    _ ->
      assertFailure
        ("live workflow journal lacks establish/publish evidence: " <> show entries)

requireCompletedLiveWorkflow
  :: (Show terminal, Show evidence, Show violation, Show missing)
  => Text
  -> Either
       (LiveWorkflow.LiveRunFailure terminal evidence violation missing)
       (LiveWorkflow.CompletedRunEvidence terminal evidence violation missing)
  -> IO (LiveWorkflow.CompletedRunEvidence terminal evidence violation missing)
requireCompletedLiveWorkflow label result =
  case result of
    Left failure ->
      assertFailureWithIO
        (Text.unpack label <> " failed:\n" <> show failure)
    Right completed -> do
      assertEstablishBeforePublish completed
      pure completed

-- | Apple placement smoke only: prove the Coordinator forwarded the exact
-- decoded typed command to the host route.  This helper intentionally does not
-- claim host workload completion; evidence-bearing Apple workflows must use a
-- terminal/event scenario on an Apple runner.
--
-- The forwarded command is expected on the host topic, so the reply cursor is
-- established on the host topic with the Coordinator's command topic as the
-- request topic.  The acknowledged admin CREATE precedes the publication, which
-- the start action performs only through the supplied publish-through-cursor
-- action; a socket-open lifecycle event gates nothing.  The @Owned@ cursor is
-- released on every exit.
assertAppleHostForwardingSmoke
  :: (Eq command)
  => PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Topic command
  -> Topic command
  -> Text
  -> Text
  -> command
  -> (IO (Either ServiceError Text) -> IO ())
  -> Int
  -> IO ()
assertAppleHostForwardingSmoke settings requestTopic hostTopic subscriptionName experimentHash expectedCommand startAction attempts = do
  let subscription = subscriptionFixture hostTopic subscriptionName FromLatest Owned
  established <-
    PulsarWebSocketSubprocess.establishReplyCursor
      settings
      requestTopic
      subscription
  cursor <-
    case established of
      Left err ->
        assertFailure
          ( "host workload reply cursor CREATE failed on "
              <> Text.unpack (topicName hostTopic)
              <> ": "
              <> show err
          )
      Right value -> pure value
  ( do
      startAction
        ( PulsarWebSocketSubprocess.publishWithReplyCursor
            settings
            cursor
            (const expectedCommand)
        )
      consumed <-
        Timeout.timeout (max 1 attempts * 5_000_000) $
          PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $
            pulsarConsumeUntil
              (PulsarWebSocketSubprocess.replyCursorSubscription cursor)
              (const (pure ()))
              ( \delivery -> do
                  if deliveryEvent delivery == expectedCommand
                    then pure (done ack ())
                    else pure (continue ack)
              )
      case consumed of
        Nothing ->
          assertFailure
            ( "timed out waiting for host workload command for "
                <> Text.unpack experimentHash
                <> " on "
                <> Text.unpack (topicName hostTopic)
            )
        Just (Left err) ->
          assertFailure
            ( "host workload consumer failed on "
                <> Text.unpack (topicName hostTopic)
                <> ": "
                <> show err
            )
        Just (Right ()) -> pure ()
    )
    `SafeException.finally` do
      released <- PulsarWebSocketSubprocess.releaseReplyCursor settings cursor
      released @?= Right ()

-- | Publish through an established reply cursor, naming the request topic and
-- the typed error when the broker refuses.
publishThroughCursorOrFail
  :: Topic command
  -> Text
  -> IO (Either ServiceError Text)
  -> IO ()
publishThroughCursorOrFail requestTopic label publish = do
  result <- publish
  case result of
    Right _ -> pure ()
    Left err ->
      assertFailure
        ( Text.unpack
            ( label
                <> " publish through the reply cursor failed live on "
                <> topicName requestTopic
                <> ": "
                <> Text.pack (show err)
            )
        )

kubectlJobExists :: Text -> IO Bool
kubectlJobExists jobName = do
  let command =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "get"
          , "job"
          , jobName
          , "-n"
          , "platform"
          , "--ignore-not-found"
          , "-o"
          , "name"
          ]
  outcome <- runStreaming defaultSubprocessEnv command
  case outcome of
    ProcessSucceeded transcript ->
      pure (not (Text.null (Text.strip (processTranscriptStdout transcript))))
    ProcessFailed _ -> do
      _ <-
        assertFailure
          ( "kubectl failed while checking whether Job exists: "
              <> Text.unpack jobName
              <> "\n"
              <> Text.unpack (renderProcessOutcome outcome)
          )
      pure False

cleanupTemporaryKubernetesJob
  :: Text
  -> Text
  -> IO [LiveWorkflow.CleanupIssue]
cleanupTemporaryKubernetesJob ownerLabel jobName =
  concat
    <$> traverse
      cleanupResource
      (zip resourceLabels (temporaryKubernetesJobCleanupCommands jobName))
 where
  resourceLabels =
    [ "temporary Job " <> jobName
    , "temporary RunConfig ConfigMap runconfig-" <> jobName
    ]
  cleanupResource (resourceLabel, command) = do
    attempted <- tryAnyIntegration (runStreaming defaultSubprocessEnv command)
    case attempted of
      Left exception ->
        case Control.Exception.fromException exception of
          Just asyncException ->
            Control.Exception.throwIO
              (asyncException :: Control.Exception.SomeAsyncException)
          Nothing ->
            pure
              [ LiveWorkflow.CleanupIssue
                  ( ownerLabel
                      <> " failed to delete "
                      <> resourceLabel
                      <> ": "
                      <> Text.pack (show exception)
                  )
              ]
      Right (ProcessSucceeded _) -> pure []
      Right failed@ProcessFailed {} ->
        pure
          [ LiveWorkflow.CleanupIssue
              ( ownerLabel
                  <> " failed to delete "
                  <> resourceLabel
                  <> ":\n"
                  <> renderProcessOutcome failed
              )
          ]

temporaryKubernetesJobCleanupCommands :: Text -> [Subprocess]
temporaryKubernetesJobCleanupCommands jobName =
  fmap
    ( \(resourceType, resourceName) ->
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "delete"
          , resourceType
          , resourceName
          , "-n"
          , "platform"
          , "--ignore-not-found"
          ]
    )
    [ ("job", jobName)
    , ("configmap", "runconfig-" <> jobName)
    ]

-- | Map `Substrate` to the lower-case URL segment used in Pulsar topic
-- names (`training.command.linux-cuda`, etc).
substrateUrlSegment :: Substrate -> Text
substrateUrlSegment = \case
  AppleSilicon -> "apple-silicon"
  LinuxCPU -> "linux-cpu"
  LinuxCUDA -> "linux-cuda"

-- | `assertFailure` raises an exception inside `IO`. Wrap it so the type
-- checker accepts it where the caller expects a plain `IO a`.
assertFailureWithIO :: String -> IO a
assertFailureWithIO message = assertFailure message >> error "unreachable"

-- | The environment-step total the compiled plan schedules for a live
-- @StartRLRun@: the exact count the dispatched worker's completed checkpoint
-- must carry as both its declared budget target and its observed units.
plannedRlEnvironmentSteps :: ProtoRl.RlCommand -> IO Word64
plannedRlEnvironmentSteps command =
  case command of
    ProtoRl.RlStart start ->
      case Workload.rlPlanForStart start of
        Left err -> assertFailureWithIO ("invalid live RL plan: " <> Text.unpack err)
        Right plan ->
          case ProductBudget.compiledRlSchedule plan of
            Nothing -> assertFailureWithIO "the live RL plan schedules no environment steps"
            Just schedule -> pure (ProductBudget.scheduleObservedEnvironmentSteps schedule)
    _ -> assertFailureWithIO "live RL fixture did not build StartRLRun"

-- | Undelivered message count for one named subscription.
--
-- The result-side inventory above proves reply cursors are not leaked. This is
-- its request-side counterpart: a request that is nacked forever never leaves
-- the backlog, so it occupies the Engine's shared subscription indefinitely and
-- starves every other command on it. An absent topic or subscription is zero —
-- nothing has been published, which is exactly the empty state.
pulsarSubscriptionBacklog :: Topic event -> Text -> IO Integer
pulsarSubscriptionBacklog topic subscription = do
  let statsCommand =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "exec"
          , "-n"
          , "platform"
          , "pulsar-toolset-0"
          , "--"
          , "/pulsar/bin/pulsar-admin"
          , "topics"
          , "stats"
          , topicName topic
          ]
  outcome <- runStreaming defaultSubprocessEnv statsCommand
  case outcome of
    ProcessSucceeded transcript ->
      case eitherDecode
        (ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
        Right (Aeson.Object objectValue)
          | Just (Aeson.Object subscriptions) <-
              AesonKeyMap.lookup "subscriptions" objectValue ->
              case AesonKeyMap.lookup (AesonKey.fromText subscription) subscriptions of
                Nothing -> pure 0
                Just (Aeson.Object stats) ->
                  case AesonKeyMap.lookup "msgBacklog" stats of
                    Just (Aeson.Number backlog) -> pure (truncate backlog)
                    other ->
                      assertFailureWithIO
                        ( "Pulsar subscription "
                            <> Text.unpack subscription
                            <> " on "
                            <> Text.unpack (topicName topic)
                            <> " has no numeric msgBacklog: "
                            <> show other
                        )
                other ->
                  assertFailureWithIO
                    ( "Pulsar subscription "
                        <> Text.unpack subscription
                        <> " stats are not an object: "
                        <> show other
                    )
        parsed ->
          assertFailureWithIO
            ( "failed to decode Pulsar subscription backlog for "
                <> Text.unpack (topicName topic)
                <> ": "
                <> show parsed
            )
    ProcessFailed _
      | pulsarTopicAbsentFromStats topic outcome -> pure 0
      | otherwise ->
          assertFailureWithIO
            ( "failed to inspect Pulsar subscription backlog for "
                <> Text.unpack (topicName topic)
                <> ":\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )

pulsarSubscriptionNamesWithPrefix :: Topic event -> Text -> IO [Text]
pulsarSubscriptionNamesWithPrefix topic prefix = do
  let statsCommand =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "exec"
          , "-n"
          , "platform"
          , "pulsar-toolset-0"
          , "--"
          , "/pulsar/bin/pulsar-admin"
          , "topics"
          , "stats"
          , topicName topic
          ]
  outcome <- runStreaming defaultSubprocessEnv statsCommand
  case outcome of
    ProcessSucceeded transcript ->
      case eitherDecode
        (ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
        Right (Aeson.Object objectValue)
          | Just (Aeson.Object subscriptions) <-
              AesonKeyMap.lookup "subscriptions" objectValue ->
              pure
                [ subscriptionName
                | subscriptionKey <- AesonKeyMap.keys subscriptions
                , let subscriptionName = AesonKey.toText subscriptionKey
                , prefix `Text.isPrefixOf` subscriptionName
                ]
        parsed ->
          assertFailureWithIO
            ( "failed to decode Pulsar subscription inventory for "
                <> Text.unpack (topicName topic)
                <> ": "
                <> show parsed
            )
    ProcessFailed _
      | pulsarTopicAbsentFromStats topic outcome -> pure []
      | otherwise ->
          assertFailureWithIO
            ( "failed to inspect Pulsar subscription inventory for "
                <> Text.unpack (topicName topic)
                <> ":\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )

-- | Pulsar may auto-delete a non-partitioned result topic after the last owned
-- reply subscription closes.  For a prefix inventory that absence is exactly
-- the empty-cursor state; every other admin failure remains fail-closed.
pulsarTopicAbsentFromStats :: Topic event -> ProcessOutcome -> Bool
pulsarTopicAbsentFromStats topic outcome =
  ("Topic " <> topicName topic <> " not found")
    `Text.isInfixOf` renderProcessOutcome outcome

locateJitmlBinary :: IO (Maybe FilePath)
locateJitmlBinary = do
  let preferred =
        "dist-newstyle/build/"
          <> currentArchDir
          <> "/ghc-9.12.4/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist preferred
  if exists
    then Just <$> makeAbsolute preferred
    else do
      base <-
        (Just <$> listDirectory "dist-newstyle/build")
          `Control.Exception.catch` (\(_ :: IOError) -> pure Nothing)
      case base of
        Just archEntries -> do
          built <- searchForBinary (filter matchesCurrentPlatform archEntries)
          case built of
            Just path -> pure (Just path)
            Nothing -> installedFallback
        Nothing -> installedFallback
 where
  installedFallback = do
    installed <- doesFileExist installedBinaryPath
    traverse makeAbsolute (if installed then Just installedBinaryPath else Nothing)

installedBinaryPath :: FilePath
installedBinaryPath = "/usr/local/bin/jitml"

-- | Cabal's @dist-newstyle@ arch directory suffix for the current host.
-- macOS reports @darwin@ from 'SystemInfo.os', but cabal writes @osx@; Linux
-- uses @linux@ verbatim.
currentArchDir :: FilePath
currentArchDir = SystemInfo.arch <> "-" <> cabalOsSuffix
 where
  cabalOsSuffix = case SystemInfo.os of
    "darwin" -> "osx"
    other -> other

-- | Reject @dist-newstyle@ arch directories that don't match the running
-- host, so a Linux container running the test stanza ignores the macOS
-- binary the host bind-mount exposes (and vice versa).
matchesCurrentPlatform :: FilePath -> Bool
matchesCurrentPlatform arch = arch == currentArchDir

searchForBinary :: [FilePath] -> IO (Maybe FilePath)
searchForBinary [] = pure Nothing
searchForBinary (arch : rest) = do
  let path = "dist-newstyle/build" </> arch </> "ghc-9.12.4/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist path
  if exists
    then Just <$> makeAbsolute path
    else searchForBinary rest

-- Strengthened GenericRL proof. These values are private to the shared tests:
-- they arise from actual filesystem/image/API/Store observations, never from
-- a caller-supplied Boolean or a reconstructed CompletedTraining value.
data GenericRlCliPin = GenericRlCliPin FilePath Text SourceDigest.SourceStamp

data GenericRlImagePin = GenericRlImagePin GenericRlCliPin Text [(Text, Text)]

data GenericRlPhysicalCheckpoint
  = GenericRlPhysicalCheckpoint
      CheckpointStore.AdmittedCheckpoint
      TrainingBudget.CompletedTraining
      Framework.EvaluationSet
      Text

captureGenericRlCliPin :: IO (Maybe FilePath) -> IO GenericRlCliPin
captureGenericRlCliPin discover = do
  located <-
    discover >>= maybe (assertFailureWithIO "GenericRL needs the current dist-newstyle CLI") pure
  path <- canonicalizePath located
  repo <- canonicalizePath "."
  genericExpect (Physical.validateCliPath repo ("build" </> currentArchDir) path)
  bytes <- StrictByteString.readFile path
  expectedMagic <- case SystemInfo.os of
    "linux" -> pure (StrictByteString.pack [127, 69, 76, 70])
    "darwin" -> pure (StrictByteString.pack [207, 250, 237, 254])
    _ -> assertFailureWithIO "GenericRL needs the actual current-platform executable"
  genericExpect (Physical.validateCliMagic expectedMagic bytes)
  stamp <- SourceDigest.computeSourceStamp >>= genericExpect
  pure (GenericRlCliPin path (sha256Hex bytes) stamp)

verifyGenericRlCliPin :: GenericRlCliPin -> Assertion
verifyGenericRlCliPin (GenericRlCliPin path digest stamp) = do
  bytes <- StrictByteString.readFile path
  sha256Hex bytes @?= digest
  SourceDigest.computeSourceStamp >>= genericExpect >>= (@?= stamp)

captureGenericRlImagePin :: GenericRlCliPin -> Substrate -> IO GenericRlImagePin
captureGenericRlImagePin cliPin@(GenericRlCliPin _ expectedCli expectedSource) substrate = do
  genericRequire
    "cluster GenericRL image proof requires the real Linux lane"
    (SystemInfo.os == "linux")
  architecture <- case SystemInfo.arch of
    "aarch64" -> pure "arm64"
    "x86_64" -> pure "amd64"
    _ -> assertFailureWithIO "unsupported current Linux image architecture"
  target <-
    Text.strip
      <$> genericCommand "docker" ["image", "inspect", "--format={{.Descriptor.digest}}", "jitml:local"]
  genericExpect (Physical.validateImageTarget target)
  -- Create from the digest, never from the mutable tag. This owned container
  -- executes only `command -v`; it cannot train or publish anything.
  container <-
    Text.strip
      <$> genericCommand
        "docker"
        [ "create"
        , "--pull"
        , "never"
        , "--platform"
        , "linux/" <> architecture
        , "--entrypoint"
        , "/bin/sh"
        , target
        , "-c"
        , "command -v jitml"
        ]
  genericExpect (Physical.validateOwnedContainerId container)
  withOwnedScenarioCleanup
    "GenericRL immutable image capability"
    ( do
        outcome <- runStreaming defaultSubprocessEnv (subprocess "docker" ["rm", "--force", container])
        pure $ case outcome of
          ProcessSucceeded _ -> []
          ProcessFailed _ -> [LiveWorkflow.CleanupIssue (renderProcessOutcome outcome)]
    )
    ( withSystemTempDirectory "jitml-generic-image-proof" $ \directory -> do
        let executable = directory </> "jitml"
            sourceRoot = directory </> "source"
        inspected <- genericJsonCommand "immutable-image-container" "docker" ["inspect", container]
        description <- case inspected of
          Aeson.Array values | [value] <- toList values -> pure value
          _ -> assertFailureWithIO "docker inspect did not identify the one owned image container"
        config <- genericField description "Config"
        genericExpect (Physical.validateImageDescriptor target config)
        _ <- genericCommand "docker" ["cp", container <> ":/usr/local/bin/jitml", Text.pack executable]
        actualBytes <- StrictByteString.readFile executable
        genericExpect (Physical.validateImageExecutable expectedCli actualBytes)
        -- Copy the source roots already present in this immutable image; the
        -- public SourceDigest algorithm rejects missing roots and symlinks.
        createDirectoryIfMissing True sourceRoot
        traverse_
          ( \root ->
              void $
                genericCommand
                  "docker"
                  ["cp", container <> ":/jitml/" <> Text.pack root, Text.pack (sourceRoot </> root)]
          )
          (SourceDigest.sourceDigestDirectoryRoots <> SourceDigest.sourceDigestFileRoots)
        actualSource <- SourceDigest.computeSourceStampIn sourceRoot >>= genericExpect
        genericExpect (Physical.validateImageSource expectedSource actualSource)
        resolved <- Text.strip <$> genericCommand "docker" ["start", "--attach", container]
        genericExpect (Physical.validateResolvedExecutable resolved)
        pure ()
    )
  nodes <-
    genericJsonCommand
      "prelaunch-nodes"
      "kubectl"
      ["--kubeconfig", "./.build/jitml.kubeconfig", "get", "nodes", "-o", "json"]
  values <- genericField nodes "items" >>= genericAs
  genericRequire "the published cluster has no nodes" (not (null (values :: [Aeson.Value])))
  nodePins <-
    traverse
      ( \node -> do
          name <- genericExpect (Physical.validateNode substrate architecture node)
          let actualArchitecture = architecture
          config <- verifyGenericRlNodeImage target name actualArchitecture
          pure (name, config)
      )
      values
  verifyGenericRlCliPin cliPin
  pure (GenericRlImagePin cliPin target nodePins)

-- Docker's OCI target/index, its selected platform manifest and CRI config id
-- are distinct. Follow the hash-checked actual node content graph; never infer
-- their equality from a tag or an image label.
verifyGenericRlNodeImage :: Text -> Text -> Text -> IO Text
verifyGenericRlNodeImage target node architecture = do
  listing <-
    genericCommand
      "docker"
      ["exec", node, "ctr", "-n", "k8s.io", "images", "ls", "name==docker.io/library/jitml:local"]
  genericExpect (Physical.imageTargetFromListing target listing)
  root <- genericNodeContent node target
  selected <- genericExpect (Physical.platformManifestDigest architecture root)
  manifest <- maybe (pure root) (genericNodeContent node) selected
  configDescriptor <- genericField manifest "config"
  configDigest <- genericText configDescriptor "digest"
  config <- genericNodeContent node configDigest
  genericExpect (Physical.validateOciConfig architecture config)
  cri <-
    genericJsonCommand "node-cri-image" "docker" ["exec", node, "crictl", "inspecti", "jitml:local"]
  genericExpect (Physical.validateCriImage configDigest cri)
  pure configDigest

genericNodeContent :: Text -> Text -> IO Aeson.Value
genericNodeContent node digest = do
  genericRequire "noncanonical OCI content digest" (genericImageDigest digest)
  raw <- genericCommand "docker" ["exec", node, "ctr", "-n", "k8s.io", "content", "get", digest]
  let bytes = Text.Encoding.encodeUtf8 raw
  ("sha256:" <> sha256Hex bytes) @?= digest
  genericRecordBytes ("node-content-" <> digest) bytes
  genericExpect (Physical.decodeOciContent digest bytes)

prepareGenericRlProducerProof
  :: Publication.ClusterPublication
  -> ProtoRl.RlCommand
  -> LiveWorkflow.LiveBackend Text
  -> IO (LiveWorkflow.LiveBackend Text, LiveEvidence.RlLiveEvidence -> Assertion)
prepareGenericRlProducerProof publication command backend = do
  start <- case command of
    ProtoRl.RlStart value -> pure value
    _ -> assertFailureWithIO "GenericRL producer proof requires the actual StartRLRun"
  ProtoRl.srlSubstrate start @?= Publication.publicationSubstrate publication
  requireGenericRlSelectedSubstrate (ProtoRl.srlSubstrate start)
  genericRequire
    "the strengthened daemon proof requires a real cluster-compute lane"
    (ProtoRl.srlSubstrate start /= AppleSilicon)
  settings <- requireGenericRlRemoteSettings (ProtoRl.srlSubstrate start)
  existing <-
    MinIOSubprocess.runMinIOSubprocess
      settings
      (listObjects (BucketName "jitml-checkpoints") (ProtoRl.srlExperimentHash start <> "/"))
      >>= genericExpect
  existing @?= []
  cliPin <- captureGenericRlCliPin locateJitmlBinary
  imagePin <- captureGenericRlImagePin cliPin (ProtoRl.srlSubstrate start)
  genericRlRemotePreflight settings start cliPin
  captured <- IORef.newIORef Nothing
  let strengthened =
        backend
          { LiveWorkflow.liveReleasePlacement = \placement ->
              withOwnedScenarioCleanup
                "GenericRL pre-cleanup physical producer proof"
                (LiveWorkflow.liveReleasePlacement backend placement)
                ( do
                    verifyGenericRlWorker imagePin start placement
                    proof <- captureGenericRlPublishedCheckpoint settings start Nothing
                    IORef.writeIORef captured (Just proof)
                    pure []
                )
          }
      verify evidence = do
        proof <-
          IORef.readIORef captured
            >>= maybe
              (assertFailureWithIO "GenericRL checkpoint was not physically captured before worker cleanup")
              pure
        assertGenericRlPublishedEvidence start proof evidence
        verifyGenericRlCliPin cliPin
  pure (strengthened, verify)

requireGenericRlRemoteSettings :: Substrate -> IO MinIOSubprocess.MinIOSettings
requireGenericRlRemoteSettings substrate = do
  resolved <-
    WorkerPublication.resolveWorkerLiveContextAt WorkerPublication.workerServiceBootConfigPath "."
      >>= genericExpect
  context <-
    maybe
      (assertFailureWithIO "GenericRL physical proof requires genuine configured remote publication")
      pure
      resolved
  Publication.publicationSubstrate (WorkerPublication.workerLivePublication context) @?= substrate
  pure (WorkerPublication.workerLiveMinIOSettings context)

verifyGenericRlWorker
  :: GenericRlImagePin -> ProtoRl.StartRLRun -> LiveWorkflow.Placement -> Assertion
verifyGenericRlWorker (GenericRlImagePin cliPin target nodePins) start placement = do
  jobName <- case placement of
    LiveWorkflow.ClusterJob handle -> pure (LiveWorkflow.jobHandleName handle)
    _ -> assertFailureWithIO "GenericRL physical proof has no actual cluster Job"
  jobName @?= "jitml-rl-" <> ProtoRl.srlExperimentHash start
  job <-
    genericJsonCommand
      "owned-rl-job"
      "kubectl"
      ["--kubeconfig", "./.build/jitml.kubeconfig", "get", "job", jobName, "-n", "platform", "-o", "json"]
  jobUid <- genericExpect (Physical.validateJob start job)
  podList <-
    genericJsonCommand
      "owned-rl-pods"
      "kubectl"
      [ "--kubeconfig"
      , "./.build/jitml.kubeconfig"
      , "get"
      , "pods"
      , "-n"
      , "platform"
      , "-l"
      , "job-name=" <> jobName
      , "-o"
      , "json"
      ]
  pod <- genericExpect (Physical.selectOwnedPod jobName jobUid podList)
  (node, config) <- genericExpect (Physical.validatePodPlacement start nodePins pod)
  nodeStatus <-
    genericJsonCommand
      "actual-worker-node"
      "kubectl"
      ["--kubeconfig", "./.build/jitml.kubeconfig", "get", "node", node, "-o", "json"]
  architecture <-
    genericField nodeStatus "status" >>= (`genericField` "nodeInfo") >>= (`genericText` "architecture")
  verifyGenericRlNodeImage target node architecture >>= (@?= config)
  genericExpect (Physical.validatePodRuntime config pod)
  verifyGenericRlCliPin cliPin

captureGenericRlPublishedCheckpoint
  :: MinIOSubprocess.MinIOSettings
  -> ProtoRl.StartRLRun
  -> Maybe (Text, Text)
  -> IO GenericRlPhysicalCheckpoint
captureGenericRlPublishedCheckpoint settings start receipt = do
  expected <- genericExpect (Workload.rlPlanForStart start)
  genericRequire
    "this live generic control requires the unchanged PPO/cartpole cohort"
    ( ProductBudget.compiledRlTrainerKind expected == "ppo"
        && ProductBudget.compiledRlEnvironment expected == "cartpole"
    )
  let experiment = ProtoRl.srlExperimentHash start
  genericRequire
    "generic RL checkpoint must not claim a canonical ProductRow"
    (case ProductMatrix.productRowForExperimentHash experiment of Nothing -> True; Just _ -> False)
  latest <-
    MinIOSubprocess.runMinIOSubprocess settings (CheckpointStore.admitLatestCheckpoint experiment)
      >>= genericExpect
  let digest = CheckpointStore.admittedCheckpointManifestSha latest
  case receipt of
    Nothing -> pure ()
    Just (expectedDigest, _) -> digest @?= expectedDigest
  exact <-
    MinIOSubprocess.runMinIOSubprocess settings (CheckpointStore.admitCheckpointAt experiment digest)
      >>= genericExpect
  exact @?= latest
  completed <- genericExpect (Physical.validateAdmittedCheckpoint start exact)
  rawBytes <-
    MinIOSubprocess.runMinIOSubprocess
      settings
      (minioReadBytes (CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experiment digest)))
      >>= genericExpect
  genericExpect (Physical.validateRawEnvelope start exact rawBytes)
  genericRecordBytes "generic-checkpoint-envelope" rawBytes
  (evaluation, trajectoryDigest) <- readGenericRlTrajectory settings start (snd <$> receipt)
  genericExpect (Physical.validateCheckpointEvaluation start exact completed evaluation)
  pure (GenericRlPhysicalCheckpoint exact completed evaluation trajectoryDigest)

assertGenericRlPublishedEvidence
  :: ProtoRl.StartRLRun -> GenericRlPhysicalCheckpoint -> LiveEvidence.RlLiveEvidence -> Assertion
assertGenericRlPublishedEvidence start (GenericRlPhysicalCheckpoint admitted completed evaluation _) evidence = do
  let observed =
        [ ( key
          , finiteMeasurementValue (LiveEvidence.rlEvaluationReward outcome)
          , LiveEvidence.rlEvaluationSteps outcome
          , LiveEvidence.rlEvaluationDone outcome
          )
        | (key, outcome) <- Map.toAscList (LiveEvidence.rlCompletedEvaluationSet evidence)
        ]
  genericExpect
    ( Physical.validateEventProjection
        start
        admitted
        completed
        evaluation
        (LiveEvidence.rlCompletedCheckpoint evidence)
        observed
        (finiteMeasurementValue (LiveEvidence.rlCompletedMedianReward evidence))
    )

readGenericRlTrajectory
  :: MinIOSubprocess.MinIOSettings
  -> ProtoRl.StartRLRun
  -> Maybe Text
  -> IO (Framework.EvaluationSet, Text)
readGenericRlTrajectory settings start expectedSha = do
  let experiment = ProtoRl.srlExperimentHash start
      prefix = experiment <> "/artifacts/rl-trajectory/"
  objects <-
    MinIOSubprocess.runMinIOSubprocess settings (listObjects (BucketName "jitml-checkpoints") prefix)
      >>= genericExpect
  ref <- case expectedSha of
    Nothing -> case objects of
      [value] -> pure value
      _ -> assertFailureWithIO "fresh generic RL namespace has no unique actual trajectory artifact"
    Just digest -> do
      genericRequire "CLI trajectory address is not canonical" (genericSha digest)
      let expected = ObjectRef (BucketName "jitml-checkpoints") (ObjectKey (prefix <> digest <> ".txt"))
      genericRequire
        "actual CLI trajectory receipt is absent from the real object inventory"
        (expected `elem` objects)
      pure expected
  bytes <- MinIOSubprocess.runMinIOSubprocess settings (minioReadBytes ref) >>= genericExpect
  unObjectKey (objectKey ref) @?= prefix <> sha256Hex bytes <> ".txt"
  outcomes <- genericExpect (Physical.parseTrajectoryRows start (unObjectKey (objectKey ref)) bytes)
  genericRecordBytes "generic-rl-trajectory" bytes
  evaluation <- genericExpect (Physical.refineTrajectoryOutcomes start outcomes)
  pure (evaluation, sha256Hex bytes)

-- The orchestrator binds every stanza to its explicit selected lane. The live
-- publication alone cannot choose a different lane for this standing gate.
requireGenericRlSelectedSubstrate :: Substrate -> Assertion
requireGenericRlSelectedSubstrate substrate =
  lookupEnv "JITML_SUBSTRATE" >>= genericExpect . Physical.validateSelectedSubstrate substrate

requireGenericRlCliDefaults :: Assertion
requireGenericRlCliDefaults = do
  mounted <- doesFileExist "/etc/jitml/run/RunConfig.dhall"
  genericExpect (Physical.validateNoMountedRunConfig mounted)
  traverse_
    ( \name -> do
        value <- lookupEnv name
        genericExpect (Physical.validateNoSemanticOverride name value)
    )
    ["JITML_MAX_STEPS", "JITML_EVAL_EPISODES", "JITML_PRODUCT_RL_VEC_ENVS", "JITML_EXPERIMENT_HASH"]

genericRlCliStart :: Publication.ClusterPublication -> IO ProtoRl.StartRLRun
genericRlCliStart publication = do
  requireGenericRlSelectedSubstrate (Publication.publicationSubstrate publication)
  experiment <-
    genericExpect =<< ProductExperiment.loadRlExperimentByPath "experiments/cartpole.dhall"
  genericRequire
    "canonical CLI experiment seed exceeds the public plan's Int/Word64 domains"
    ( toInteger (ProductExperiment.rlExperimentSeed experiment)
        <= min (toInteger (maxBound :: Int)) (toInteger (maxBound :: Word64))
    )
  let substrate = Publication.publicationSubstrate publication
      trainer = Workload.rlTrainerForAlgorithm (ProductExperiment.rlExperimentAlgorithm experiment)
      name =
        Checkpoint.deriveExperimentHash
          "experiments/cartpole.dhall"
          ( substrateUrlSegment substrate
              <> ":"
              <> trainer
              <> ":"
              <> ProductExperiment.rlExperimentEnvironment experiment
          )
  pure
    ( ProtoRl.StartRLRun
        name
        (ProductExperiment.rlExperimentAlgorithm experiment)
        (ProductExperiment.rlExperimentEnvironment experiment)
        substrate
        (fromIntegral (ProductExperiment.rlExperimentSeed experiment))
        200
        4
    )

assertGenericRlCliPublication
  :: Publication.ClusterPublication
  -> GenericRlCliPin
  -> ProtoRl.StartRLRun
  -> MinIOSubprocess.MinIOSettings
  -> Text
  -> Assertion
assertGenericRlCliPublication publication cliPin start settings output = do
  requireGenericRlCliDefaults
  genericRlCliStart publication >>= (@?= start)
  let name = ProtoRl.srlExperimentHash start
      trainer = Workload.rlTrainerForAlgorithm (ProtoRl.srlAlgorithm start)
  expected <- genericExpect (Workload.rlPlanForStart start)
  -- Independently use the exact public traditional compiler too; the explicit
  -- default guard forbids an inherited vector/episode override.
  actualPlan <-
    TrainerExecution.compileTraditionalRlPlan
      trainer
      (ProtoRl.srlEnvironment start)
      (fromIntegral (ProtoRl.srlSeed start))
      4
      200
      Nothing
      >>= genericExpect
  actualPlan @?= expected
  genericOutputField "checkpoint-experiment-hash" output >>= (@?= name)
  digest <- genericOutputField "checkpoint-manifest-sha" output
  genericRequire "CLI did not return a canonical immutable manifest SHA" (genericSha digest)
  trajectorySha <- genericOutputField "rl-replay-artifact-sha" output
  GenericRlPhysicalCheckpoint admitted _ _ actualTrajectorySha <-
    captureGenericRlPublishedCheckpoint settings start (Just (digest, trajectorySha))
  CheckpointStore.admittedCheckpointManifestSha admitted @?= digest
  trajectorySha @?= actualTrajectorySha
  genericOutputField "rl-replay-artifact-key" output
    >>= (@?= "jitml-checkpoints/" <> name <> "/artifacts/rl-trajectory/" <> trajectorySha <> ".txt")
  genericOutputField "rl-replay-artifact-live-minio" output >>= (@?= "yes")
  -- The real remote trajectory was hashed/replayed above. stdout contributes
  -- immutable addresses only, never a rebuilt completion or omitted-history claim.
  verifyGenericRlCliPin cliPin

genericRlRemotePreflight
  :: MinIOSubprocess.MinIOSettings -> ProtoRl.StartRLRun -> GenericRlCliPin -> Assertion
genericRlRemotePreflight settings start (GenericRlCliPin _ executableSha sourceStamp) = do
  nonce <- pickRandomSuffix
  expected <- genericExpect (Workload.rlPlanForStart start)
  let payload =
        Text.Encoding.encodeUtf8
          ( Text.intercalate
              "\n"
              [ "kind: generic-rl-producer-preflight-v1"
              , "experiment: " <> ProtoRl.srlExperimentHash start
              , "nonce: " <> nonce
              , "executable-sha256: " <> executableSha
              , "source-sha256: " <> SourceDigest.stampSha256 sourceStamp
              , "expected-plan: " <> ProductBudget.renderCompiledRlPlanTransport expected
              ]
          )
      key =
        "jitml-checkpoints/"
          <> ProtoRl.srlExperimentHash start
          <> "/artifacts/generic-producer-preflight/"
          <> sha256Hex payload
          <> ".txt"
      ref = CheckpointStore.checkpointObjectRef key
  -- A new random-identity test preflight object exercises actual create-only
  -- publication/readback before this expensive request. It is not training evidence.
  MinIOSubprocess.runMinIOSubprocess settings (Physical.publishPreflight ref payload)
    >>= genericExpect
  genericRecordBytes "generic-producer-preflight" payload

genericOutputField :: Text -> Text -> IO Text
genericOutputField key output = genericExpect (Physical.parseReceiptField key output)

genericRecordBytes :: Text -> StrictByteString.ByteString -> IO ()
genericRecordBytes label bytes =
  Output.writeErrorLineIO
    ( Text.intercalate
        "\t"
        [ "jitml-generic-proof-blob-v1"
        , label
        , Text.pack (show (StrictByteString.length bytes))
        , sha256Hex bytes
        , hexBytes bytes
        ]
    )

genericCommand :: FilePath -> [Text] -> IO Text
genericCommand binary arguments = do
  outcome <- runStreaming defaultSubprocessEnv (subprocess binary arguments)
  case outcome of
    ProcessSucceeded transcript -> pure (processTranscriptStdout transcript)
    ProcessFailed _ ->
      assertFailureWithIO
        ("GenericRL proof command failed: " <> Text.unpack (renderProcessOutcome outcome))

genericJsonCommand :: Text -> FilePath -> [Text] -> IO Aeson.Value
genericJsonCommand label binary arguments = do
  raw <- genericCommand binary arguments
  let bytes = Text.Encoding.encodeUtf8 raw
  genericRecordBytes label bytes
  either (assertFailureWithIO . ("invalid observed JSON: " <>)) pure (Aeson.eitherDecodeStrict' bytes)

genericField :: Aeson.Value -> Text -> IO Aeson.Value
genericField value key =
  maybe
    (assertFailureWithIO ("observed object lacks " <> Text.unpack key))
    pure
    (genericOptional value key)

genericOptional :: Aeson.Value -> Text -> Maybe Aeson.Value
genericOptional (Aeson.Object values) key = AesonKeyMap.lookup (AesonKey.fromText key) values
genericOptional _ _ = Nothing

genericText :: Aeson.Value -> Text -> IO Text
genericText value key = genericField value key >>= genericAs

genericAs :: (Aeson.FromJSON value) => Aeson.Value -> IO value
genericAs value = case Aeson.fromJSON value of
  Aeson.Success result -> pure result
  Aeson.Error reason -> assertFailureWithIO ("observed field has wrong JSON type: " <> reason)

genericExpect :: (Show failure) => Either failure value -> IO value
genericExpect = either (assertFailureWithIO . show) pure

genericRequire :: String -> Bool -> Assertion
genericRequire = assertBool

genericSha :: Text -> Bool
genericSha value = Text.length value == 64 && Text.all (\char -> char `elem` ("0123456789abcdef" :: String)) value

genericImageDigest :: Text -> Bool
genericImageDigest value = maybe False genericSha (Text.stripPrefix "sha256:" value)

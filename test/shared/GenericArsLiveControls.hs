{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Actual generic host execution, separate from canonical native qualification.
-- No fixtures or parsed records can create either actual Store or process caps.
module GenericArsLiveControls
  ( genericArsCliCase
  , genericArsDaemonCase
  , genericArsLiveTestCases
  ) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef qualified as IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import GenericRlLiveControls qualified as Generic
import GenericRlPhysicalProof qualified as Physical
import JitML.Checkpoint.ArsHostPhysical qualified as ArsPhysical
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as Store
import JitML.Cluster.Publication qualified as Publication
import JitML.Coordinator.Topology (ProtocolRoute (..))
import JitML.Plan.Plan (finiteMeasurementValue, refinePlanIdText)
import JitML.Product.ArsHostReference qualified as Reference
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.ExternalBars qualified as Bars
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Proto.Rl qualified as Rl
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerExecution qualified as Trainer
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Run.Contract (finishContract, initialProgress)
import JitML.Service.Capabilities
  ( BucketName (..)
  , HasMinIO (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  )
import JitML.Service.MinIOSubprocess qualified as MinIO
import JitML.Service.PulsarWebSocketSubprocess qualified as Pulsar
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Outcome (processTranscriptStdout)
import JitML.Sub.Stream qualified as Stream
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.LiveEvidence qualified as Evidence
import JitML.Test.LivePulsarTransport (livePulsarTransport)
import JitML.Test.LiveWorkflow qualified as Live
import JitML.Training.Budget qualified as Training
import System.Directory (canonicalizePath)
import System.Exit (ExitCode (..))
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))

genericArsLiveTestCases :: [TestTree]
genericArsLiveTestCases = [genericArsCliCase, genericArsDaemonCase]

-- Actual collector pins; no public construction route is exported.
data ArsCliPin = ArsCliPin Generic.GenericRlCliPin FilePath Text Source.SourceStamp

data ArsPhysicalCheckpoint
  = ArsPhysicalCheckpoint
      Store.AdmittedExecutionCheckpoint
      Framework.EvaluationSet
      Text

genericArsCliCase :: TestTree
genericArsCliCase = testCase
  "live generic ARS CLI binds actual host execution to its full compiled checkpoint and trajectory"
  $ do
    publication <- Generic.requireLivePublication
    let lane = Publication.publicationSubstrate publication
    Generic.requireGenericRlSelectedSubstrate lane
    Generic.requireGenericRlCliDefaults
    binary <-
      Generic.locateJitmlBinary
        >>= maybe
          (Generic.assertFailureWithIO "generic ARS CLI needs the current dist-newstyle CLI")
          pure
    pin@(ArsCliPin cliPin path _ _) <- capturePin binary
    root <- canonicalizePath "."
    let start =
          Rl.StartRLRun
            ( Checkpoint.deriveExperimentHash
                "experiments/cartpole.dhall"
                (renderSubstrate lane <> ":ars:cartpole")
            )
            "ARS"
            "cartpole"
            lane
            42
            200
            4
        arguments =
          [ "rl"
          , "train"
          , "experiments/cartpole.dhall"
          , "--algorithm"
          , "ARS"
          , "--seed"
          , "42"
          , "--substrate"
          , renderSubstrate lane
          ]
        command = (subprocess path arguments) {subprocessWorkingDirectory = Just root}
    plan <- expect (Workload.rlPlanForStart start)
    independentlyCompiled <-
      Trainer.compileTraditionalRlPlan "ars" "cartpole" 42 4 200 Nothing >>= expect
    independentlyCompiled @?= plan
    settings <- Generic.requireGenericRlRemoteSettings lane
    Generic.genericRlRemotePreflight settings start cliPin
    actual <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
    let outcome = Stream.nativeSpawnResultOutcome actual
        output = processTranscriptStdout (Generic.processTranscript outcome)
    Generic.assertProcessExitCode "generic ARS actual CLI" ExitSuccess outcome
    spawned <-
      maybe
        (Generic.assertFailureWithIO "generic ARS launch has no actual PID receipt")
        pure
        (Stream.nativeSpawnResultObservation actual)
    Stream.nativeSpawnExecutablePath spawned @?= path
    Stream.nativeSpawnArguments spawned @?= arguments
    Stream.nativeSpawnWorkingDirectory spawned @?= Just root
    Stream.nativeSpawnEnvironmentRemovals spawned @?= []
    Stream.nativeSpawnEnvironmentOverrideNames spawned @?= []
    assertBool "generic ARS CLI actual PID is positive" (Stream.nativeSpawnProcessId spawned > 0)
    digest <- field "checkpoint-manifest-sha" output
    field "checkpoint-experiment-hash" output >>= (@?= Rl.srlExperimentHash start)
    trajectorySha <- field "rl-replay-artifact-sha" output
    hostSha <- field "ars-host-artifact-sha" output
    ArsPhysicalCheckpoint admitted _ actualTrajectorySha <-
      captureCheckpoint settings start pin (Just (digest, trajectorySha))
    let base = Store.admittedExecutionCheckpoint admitted
    Store.admittedCheckpointManifestSha base @?= digest
    actualTrajectorySha @?= trajectorySha
    host <- hostTrace admitted
    Reference.arsHostReferenceContentSha256 (Store.admittedArsHostReference host) @?= hostSha
    field "ars-host-artifact-key" output
      >>= (@?= Reference.arsHostReferenceObjectKey (Store.admittedArsHostReference host))
    field "ars-host-artifact-live-minio" output >>= (@?= "yes")
    fetchedTrace <-
      MinIO.runMinIOSubprocess
        settings
        ( minioReadBytes
            ( Store.checkpointObjectRef
                (Reference.arsHostReferenceObjectKey (Store.admittedArsHostReference host))
            )
        )
        >>= expect
    fetchedTrace @?= Trace.encodeArsHostTrace (Store.admittedArsHostTrace host)
    field "rl-replay-artifact-key" output >>= (@?= trajectoryKey start trajectorySha)
    field "rl-replay-artifact-live-minio" output >>= (@?= "yes")
    let context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext (Store.admittedArsHostTrace host))
    Trace.rawArsHostProcessId context @?= Text.pack (show (Stream.nativeSpawnProcessId spawned))
    -- Preserve literal process bytes; no decoded/re-encoded raw receipt claim.
    recordBytes "generic-ars-cli-stdout" (LBS.toStrict (Stream.nativeSpawnResultStdoutBytes actual))
    recordBytes "generic-ars-cli-stderr" (LBS.toStrict (Stream.nativeSpawnResultStderrBytes actual))
    verifyPin pin

genericArsDaemonCase :: TestTree
genericArsDaemonCase = testCase
  "live generic ARS daemon binds Linux host publication or actual Apple host forwarding"
  $ do
    publication <- Generic.requireLivePublication
    let lane = Publication.publicationSubstrate publication
        pulsar = Pulsar.pulsarSettingsForLocalEdge (Publication.publicationEdgePort publication)
        commandTopic = Generic.topologyTopic RlCommandRoute lane
        eventTopic = Generic.topologyTopic RlEventRoute lane
    Generic.requireGenericRlSelectedSubstrate lane
    suffix <- Generic.pickRandomSuffix
    let experiment = Text.take 16 ("livears" <> suffix <> "abcdef0123456789")
        start = Rl.StartRLRun experiment "ARS" "cartpole" lane 42 200 4
        command = Rl.RlStart start
        jobName = "jitml-rl-" <> experiment
    case lane of
      AppleSilicon -> do
        -- Actual forwarding scope only; separate CLI test proves host execution.
        Generic.assertAppleHostForwardingSmoke
          pulsar
          commandTopic
          (Generic.topologyTopic RlHostCommandRoute AppleSilicon)
          ("live-ars-host-command-sub-" <> suffix)
          experiment
          command
          (Generic.publishThroughCursorOrFail commandTopic "StartRLRun generic ARS")
          20
        Generic.assertJobDoesNotAppear jobName 5
      _ -> do
        binary <-
          Generic.locateJitmlBinary
            >>= maybe
              (Generic.assertFailureWithIO "generic ARS daemon needs the current dist-newstyle CLI")
              pure
        pin@(ArsCliPin cliPin _ _ _) <- capturePin binary
        imagePin <- Generic.captureGenericRlImagePin cliPin lane
        settings <- Generic.requireGenericRlRemoteSettings lane
        MinIO.runMinIOSubprocess settings (listObjects (BucketName "jitml-checkpoints") (experiment <> "/"))
          >>= expect
          >>= (@?= [])
        Generic.genericRlRemotePreflight settings start cliPin
        plan <- expect (Workload.rlPlanForStart start)
        planId <- expect (refinePlanIdText (Budget.compiledRlPlanId plan))
        schedule <- scheduleFor plan
        contract <-
          expect (Evidence.rlLiveContractForSteps planId 4 (Budget.scheduleObservedEnvironmentSteps schedule))
        captured <- IORef.newIORef Nothing
        let backend = Generic.clusterJobBackend planId jobName 7200 7200
            actualBackend =
              backend
                { Live.liveReleasePlacement = \placement ->
                    Generic.withOwnedScenarioCleanup
                      "generic ARS pre-cleanup physical proof"
                      (Live.liveReleasePlacement backend placement)
                      ( do
                          Generic.verifyGenericRlWorker imagePin start placement
                          proof <- captureCheckpoint settings start pin Nothing
                          IORef.writeIORef captured (Just proof)
                          pure []
                      )
                }
            workflow =
              Live.LiveWorkflow
                { Live.liveWorkflowPlanId = planId
                , Live.liveWorkflowCommand = Live.ProtocolCommand commandTopic command
                , Live.liveWorkflowEventSource =
                    Live.pulsarEventSource
                      (Generic.subscriptionFixture eventTopic ("live-ars-event-sub-" <> suffix) FromLatest Owned)
                , Live.liveWorkflowInitialProgress = initialProgress contract
                , Live.liveWorkflowIngest = Evidence.ingestRlLiveEvent planId experiment contract
                , Live.liveWorkflowFinish = finishContract contract
                , Live.liveWorkflowRenderViolation = Text.pack . show
                }
        result <- Live.runLiveWorkflow workflow (livePulsarTransport pulsar) actualBackend
        completed <- Generic.requireCompletedLiveWorkflow "live generic ARS daemon workflow" result
        ArsPhysicalCheckpoint actual evaluation _ <-
          IORef.readIORef captured
            >>= maybe
              (Generic.assertFailureWithIO "actual generic ARS graph was not captured before worker cleanup")
              pure
        verifyPin pin
        let evidence = Live.completedRunEvidence completed
            observed =
              [ ( key
                , finiteMeasurementValue (Evidence.rlEvaluationReward value)
                , Evidence.rlEvaluationSteps value
                , Evidence.rlEvaluationDone value
                )
              | (key, value) <- Map.toAscList (Evidence.rlCompletedEvaluationSet evidence)
              ]
        expect
          ( Physical.validateEventProjection
              start
              (Store.admittedExecutionCheckpoint actual)
              (Store.admittedExecutionCompletedTraining actual)
              evaluation
              (Evidence.rlCompletedCheckpoint evidence)
              observed
              (finiteMeasurementValue (Evidence.rlCompletedMedianReward evidence))
          )

capturePin :: FilePath -> IO ArsCliPin
capturePin binary = do
  path <- canonicalizePath binary
  actual <- Generic.captureGenericRlCliPin (pure (Just path))
  bytes <- BS.readFile path
  source <- Source.computeSourceStamp >>= expect
  Generic.verifyGenericRlCliPin actual
  pure (ArsCliPin actual path (sha256Hex bytes) source)

verifyPin :: ArsCliPin -> Assertion
verifyPin (ArsCliPin actual path sha source) = do
  Generic.verifyGenericRlCliPin actual
  BS.readFile path >>= ((@?= sha) . sha256Hex)
  Source.computeSourceStamp >>= expect >>= (@?= source)

hostTrace :: Store.AdmittedExecutionCheckpoint -> IO Store.AdmittedArsHostTrace
hostTrace actual = case Store.admittedExecutionProvenance actual of
  ArsHostLinearExecution host -> pure host
  NeuralDeviceExecution _ ->
    Generic.assertFailureWithIO
      "generic ARS must retain actual host provenance, never an MLP device witness"

scheduleFor :: Budget.CompiledRlPlan -> IO Budget.RlTrainingSchedule
scheduleFor plan = case Budget.compiledRlSchedule plan of
  Just schedule@Budget.ArsTrainingSchedule {} -> pure schedule
  _ -> Generic.assertFailureWithIO "generic ARS has no exact compiled ARS schedule"

captureCheckpoint
  :: MinIO.MinIOSettings
  -> Rl.StartRLRun
  -> ArsCliPin
  -> Maybe (Text, Text)
  -> IO ArsPhysicalCheckpoint
captureCheckpoint settings start pin receipt = do
  latest <-
    MinIO.runMinIOSubprocess settings (Store.admitLatestCheckpoint (Rl.srlExperimentHash start))
      >>= expect
  let digest = Store.admittedCheckpointManifestSha latest
  case receipt of
    Nothing -> pure ()
    Just (expected, _) -> digest @?= expected
  actual <-
    MinIO.runMinIOSubprocess
      settings
      (Store.admitExecutionCheckpointAt (Rl.srlExperimentHash start) digest)
      >>= expect
  Store.admittedExecutionCheckpoint actual @?= latest
  bytes <-
    MinIO.runMinIOSubprocess
      settings
      ( minioReadBytes
          (Store.checkpointObjectRef (Checkpoint.manifestKey (Rl.srlExperimentHash start) digest))
      )
      >>= expect
  expect (Physical.validateRawEnvelope start (Store.admittedExecutionCheckpoint actual) bytes)
  recordBytes "generic-ars-checkpoint-envelope" bytes
  (evaluation, sha) <- Generic.readGenericRlTrajectory settings start (snd <$> receipt)
  let proof = ArsPhysicalCheckpoint actual evaluation sha
  plan <- expect (Workload.rlPlanForStart start)
  assertCheckpoint plan start pin proof
  pure proof

assertCheckpoint
  :: Budget.CompiledRlPlan -> Rl.StartRLRun -> ArsCliPin -> ArsPhysicalCheckpoint -> Assertion
assertCheckpoint expected start pin@(ArsCliPin _ _ exe source) (ArsPhysicalCheckpoint actual evaluation _) = do
  let base = Store.admittedExecutionCheckpoint actual
      completed = Store.admittedExecutionCompletedTraining actual
      experiment = Rl.srlExperimentHash start
  plan <- expect (ArsPhysical.validateGenericArsHostCompletionData experiment completed)
  plan @?= expected
  schedule <- scheduleFor plan
  let steps = Budget.scheduleObservedEnvironmentSteps schedule
      budget = Training.completedTrainingBudget completed
  Training.trainingBudgetKind budget @?= Training.RlEnvironmentStepBudget
  Training.trainingBudgetTargetUnits budget @?= steps
  Training.completedTrainingObservedUnits completed @?= steps
  Checkpoint.manifestStep (Store.admittedCheckpointManifest base) @?= steps
  Budget.compiledRlSeed plan @?= fromIntegral (Rl.srlSeed start)
  Bars.assertRlConvergenceObservationsExternal plan (Training.completedTrainingMetrics completed)
    @?= []
  host <- hostTrace actual
  let trace = Store.admittedArsHostTrace host
      reference = Store.admittedArsHostReference host
      context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext trace)
      raw = Trace.arsHostTraceObservation trace
      counters = Common.rawTrainerCounters raw
  Trace.rawArsHostExecutionBinding context @?= "generic-compiled-plan-attempt-v1"
  Trace.rawArsHostRowId context @?= "generic-ars/cartpole"
  Trace.rawArsHostExperiment context @?= experiment
  Trace.rawArsHostPlanId context @?= Budget.compiledRlPlanId plan
  Trace.rawArsHostCompiledTransport context @?= Budget.renderCompiledRlPlanTransport plan
  Reference.arsHostReferenceLane reference @?= Rl.srlSubstrate start
  Trace.rawArsHostSourceSha256 context @?= Source.stampSha256 source
  Trace.rawArsHostExecutableSha256 context @?= exe
  Common.observedEnvironmentTransitionCount counters @?= steps
  Training.completedTrainingUpdateCount completed
    @?= fromIntegral (Budget.scheduleArsIterations schedule)
  Common.observedOptimizerUpdateCount counters @?= Training.completedTrainingUpdateCount completed
  assertBool
    "generic ARS actual weights must move"
    ( Training.completedTrainingInitialWeightHash completed
        /= Training.completedTrainingFinalWeightHash completed
    )
  finalBytes <- case Store.admittedCheckpointWeights base of
    [loaded] -> do
      Checkpoint.tensorName (Store.loadedWeightTensor loaded) @?= "rl-ars-weights"
      assertBool
        "generic ARS physical weights must be nonempty"
        (not (null (Store.loadedWeightValues loaded)))
      pure (Store.loadedWeightJmw1Bytes loaded)
    _ -> Generic.assertFailureWithIO "generic ARS needs exactly one actual loaded tensor"
  expect (ArsPhysical.validateArsHostCheckpointData experiment completed finalBytes reference trace)
  expect (Physical.validateCheckpointEvaluation start base completed evaluation)
  recordBytes "generic-ars-host-trace" (Trace.encodeArsHostTrace trace)
  -- Public returned-policy getters expose observed weights only, never restore.
  assertBool
    "generic ARS full initial and final vectors are retained"
    ( not (null (Observation.returnedInitialWeights (Observation.ReturnedArs raw)))
        && not (null (Observation.returnedFinalWeights (Observation.ReturnedArs raw)))
    )
  verifyPin pin

trajectoryKey :: Rl.StartRLRun -> Text -> Text
trajectoryKey start sha =
  "jitml-checkpoints/" <> Rl.srlExperimentHash start <> "/artifacts/rl-trajectory/" <> sha <> ".txt"

expect :: (Show failure) => Either failure value -> IO value
expect = either (Generic.assertFailureWithIO . show) pure

field :: Text -> Text -> IO Text
field key = expect . Physical.parseReceiptField key

recordBytes :: Text -> BS.ByteString -> IO ()
recordBytes = Generic.genericRecordBytes

{-# LANGUAGE OverloadedStrings #-}

-- One pooled actual generic host run, not five-run/native qualification.
-- No raw DTO is used to construct an actual origin or a Store capability.
module GenericArsHostPublication (genericArsHostPublicationTests) where

import Control.Exception (AsyncException (UserInterrupt), SomeException, fromException, throw, try)
import Control.Monad (forM_)
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import System.Directory (removeFile)
import System.IO (IOMode (WriteMode), hSetFileSize, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.ArsHostPhysical qualified as Physical
import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weight
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as Reference
import JitML.Product.Completion qualified as Completion
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerExecution qualified as Execution
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.ModelConvergence qualified as ModelConvergence
import JitML.Training.Budget qualified as Training

data Fixture = Fixture
  { fixturePlan :: !Budget.CompiledRlPlan
  , fixtureAttempt :: !Execution.GenericArsAttempt
  , fixtureOrigin :: !Execution.ProducedGenericArsHostExecution
  , fixtureRun :: !Execution.TrainerRun
  , fixtureCompleted :: !Training.CompletedTraining
  , fixtureManifest :: !Format.CheckpointManifest
  , fixturePayloads :: ![(Text, LBS.ByteString)]
  , fixtureFinal :: !BS.ByteString
  }

genericArsHostPublicationTests :: TestTree
genericArsHostPublicationTests = withResource acquire (const (pure ())) $ \get ->
  testGroup
    "generic ARS actual host publication"
    [ pooled get "actual public run owns its exact generic experiment and compiled identity" $ \f -> do
        Execution.producedGenericArsHostExperiment (fixtureOrigin f) @?= experiment
        Execution.producedGenericArsHostCompiledPlan (fixtureOrigin f) @?= fixturePlan f
        selected <- right =<< ModelConvergence.selectedModelConvergenceSubstrate
        Reference.arsHostReferenceLane (reference f) @?= selected
        Matrix.productRowForExperimentHash experiment @?= Nothing
        Training.completedTrainingRlPlan (fixtureCompleted f) @?= Just (fixturePlan f)
        Plan.planIdText (Training.completedTrainingPlanId (fixtureCompleted f))
          @?= Budget.compiledRlPlanId (fixturePlan f)
    , pooled get "actual strict evidence retains host provenance and no neural witness" $ \f -> do
        artifact <- trained (fixtureRun f)
        Evidence.evidenceExecutionProvenance (Execution.trainedArtifactEvidence artifact)
          @?= Right (Just (ArsHostLinearExecution (reference f)))
        assertLeft
          "does not carry a neural device witness"
          (Evidence.evidenceDeviceWitness (Execution.trainedArtifactEvidence artifact))
    , pooled
        get
        "actual full raw return keeps all fifty applied updates and eight hundred thousand transitions"
        $ \f -> do
          raw <- present "actual raw return" (Execution.genericArsAttemptRawReturn (fixtureAttempt f))
          let counters = Common.rawTrainerCounters raw
          Common.observedEnvironmentTransitionCount counters @?= 800000
          Common.observedOptimizerUpdateCount counters @?= 50
          length (Common.rawTrainerStats raw) @?= 50
          raw @?= Trace.arsHostTraceObservation (trace f)
    , pooled get "actual evaluation retains all twenty one outcomes without the Product-only twenty cap" $ \f -> do
        evaluation <-
          present "actual complete evaluation" (Execution.genericArsAttemptEvaluation (fixtureAttempt f))
        case evaluation of
          Observation.EvaluationReturned episodes -> fmap Episode.simEpisodeIndex episodes @?= [0 .. 20]
          _ -> assertFailure "actual host evaluation was not a complete ordinary return"
        artifact <- trained (fixtureRun f)
        length (Execution.evaluationSetEpisodes (Execution.trainedArtifactEvaluationSet artifact)) @?= 21
    , pooled get "actual process and source FILE observations agree before and after the run" $ \f -> do
        let before = Execution.producedGenericArsHostBeforeProcess (fixtureOrigin f)
            after = Execution.producedGenericArsHostAfterProcess (fixtureOrigin f)
        Process.compareProducerProcessObservations before after @?= Right ()
        assertBool "actual process id absent" (Process.producerProcessId before > 0)
        (_, stamp) <- present "actual observed source" (Process.producerObservedSource before)
        let context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext (trace f))
        Trace.rawArsHostSourceSha256 context @?= Source.stampSha256 stamp
        Trace.rawArsHostExecutableSha256 context @?= Process.producerExecutableFileSha256 before
    , pooled get "actual trace roundtrip retains complete bytes and same-runtime arithmetic" $ \f -> do
        decoded <- right (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace (trace f)))
        Trace.encodeArsHostTrace decoded @?= Trace.encodeArsHostTrace (trace f)
        Trace.validateArsHostTraceLocal decoded @?= Right ()
        Trace.validateArsHostTracePlan (fixturePlan f) decoded @?= Right ()
    , pooled get "actual initial and final parameter bits agree with completion and trained weights" $ \f -> do
        artifact <- trained (fixtureRun f)
        let raw = Trace.arsHostTraceObservation (trace f)
            initial = Weight.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams raw))
            final = Weight.encodeJmw1 (VU.toList (Common.rawTrainerFinalParams raw))
        Weight.jmw1ContentSha initial @?= Training.completedTrainingInitialWeightHash (fixtureCompleted f)
        LBS.toStrict final @?= fixtureFinal f
        Weight.jmw1ContentSha final @?= Training.completedTrainingFinalWeightHash (fixtureCompleted f)
        fmap castDoubleToWord64 (Execution.trainedArtifactWeights artifact)
          @?= fmap castDoubleToWord64 (VU.toList (Common.rawTrainerFinalParams raw))
    , pooled
        get
        "actual generic trace refines recorded and live physical data without canonical relabelling"
        $ \f -> do
          Physical.validateArsHostCheckpointRecordedData
            experiment
            (fixtureCompleted f)
            (fixtureFinal f)
            (reference f)
            (trace f)
            @?= Right ()
          Physical.validateArsHostCheckpointData
            experiment
            (fixtureCompleted f)
            (fixtureFinal f)
            (reference f)
            (trace f)
            @?= Right ()
          let context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext (trace f))
          Trace.rawArsHostRowId context @?= "generic-ars/cartpole"
          Trace.rawArsHostExecutionBinding context @?= "generic-compiled-plan-attempt-v1"
    , pooled get "real local snapshot admits a closed generic host execution and complete transcript" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        admitted <- right =<< Store.admitLocalExecutionCheckpointAt root experiment sha
        assertActualHost f admitted
        length
          ( Format.manifestTranscriptPointers
              (Store.admittedCheckpointManifest (Store.admittedExecutionCheckpoint admitted))
          )
          @?= 1
    , pooled get "filesystem HasMinIO fetches the same closed generic host trace" $ \f -> fresh $ \root -> do
        stored <-
          right
            =<< runFilesystemMinIO
              root
              ( Store.writeCompletedCheckpointSnapshotWithMinIO
                  Nothing
                  (fixtureCompleted f)
                  (fixtureManifest f)
                  (fixturePayloads f)
              )
        let sha = Store.storedManifestSha (Store.completedStoredCheckpoint stored)
        admitted <- right =<< runFilesystemMinIO root (Store.admitExecutionCheckpointAt experiment sha)
        assertActualHost f admitted
    , pooled get "old neural-only Store admission still rejects generic host provenance" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        ordinary <- right =<< Store.admitLocalCheckpointAt root experiment sha
        assertLeft "ARS host linear execution" (Store.requireAdmittedCompletedCheckpoint ordinary)
    , pooled get "missing host replay pointer refuses closed generic execution" $ \f -> fresh $ \root -> do
        let manifest = (fixtureManifest f) {Format.manifestReplayPointers = []}
        sha <- persist root f manifest
        assertLeft "one exact snapshot-bound ars-host-execution replay pointer"
          =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "wrong host replay kind refuses even when bytes are physically present" $ \f -> fresh $ \root -> do
        pointer <- only (Format.manifestReplayPointers (fixtureManifest f))
        let manifest =
              (fixtureManifest f)
                { Format.manifestReplayPointers = [pointer {Format.artifactPointerKind = "foreign-host"}]
                }
        sha <- persist root f manifest
        assertLeft "one exact snapshot-bound ars-host-execution replay pointer"
          =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "missing trajectory refuses closed generic completion" $ \f -> fresh $ \root -> do
        sha <- persist root f ((fixtureManifest f) {Format.manifestTranscriptPointers = []})
        assertLeft "one exact actual rl-trajectory transcript"
          =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "foreign trajectory kind cannot enter generic host completion" $ \f -> fresh $ \root -> do
        pointer <- only (Format.manifestTranscriptPointers (fixtureManifest f))
        sha <-
          persist
            root
            f
            ( (fixtureManifest f)
                { Format.manifestTranscriptPointers = [pointer {Format.artifactPointerKind = "foreign-trajectory"}]
                }
            )
        assertLeft "transcript kind differs from rl-trajectory"
          =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "actual missing trace file fails physical readback" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        pointer <- physicalPointer root sha
        path <- right (Store.objectPathForKey root (Format.artifactPointerObjectKey pointer))
        removeFile path
        assertLeft "AdmissionBlobReadFailed" =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "actual corrupt trace bytes fail their committed physical hash" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        pointer <- physicalPointer root sha
        path <- right (Store.objectPathForKey root (Format.artifactPointerObjectKey pointer))
        bytes <- BS.readFile path
        case BS.uncons bytes of
          Nothing -> assertFailure "actual encoded trace was empty"
          Just (first, rest) -> BS.writeFile path (BS.cons (first `xor` 1) rest)
        assertLeft "writer-commit SHA-256 mismatch"
          =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "actual trace over its recorded bound refuses before strict materialization" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        pointer <- physicalPointer root sha
        path <- right (Store.objectPathForKey root (Format.artifactPointerObjectKey pointer))
        withBinaryFile path WriteMode $ \handle -> hSetFileSize handle (toInteger (Reference.arsHostReferenceByteLength (reference f)) + 1)
        assertLeft "trace exceeds its recorded byte limit before materialization"
          =<< Store.admitLocalExecutionCheckpointAt root experiment sha
    , pooled get "different actual final JMW1 bytes refuse the same trace and completion" $ \f ->
        assertLeft
          "final JMW1 bytes differ"
          ( Physical.validateArsHostCheckpointRecordedData
              experiment
              (fixtureCompleted f)
              (fixtureFinal f <> "\NUL")
              (reference f)
              (trace f)
          )
    , pooled get "generic recorded completion cannot borrow any canonical ProductRow experiment" $ \f -> do
        canonical <- canonicalExperiment
        assertLeft
          "cannot occupy any canonical ProductRow experiment"
          (Physical.validateGenericArsHostCompletionData canonical (fixtureCompleted f))
    , pooled get "generic tag cannot use the old ProductRow label" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (trace f)
            context = (Trace.rawArsHostTraceContext raw) {Trace.rawArsHostRowId = "ARS/cartpole"}
        assertLeft
          "generic ARS host context differs"
          (Trace.refineArsHostTrace raw {Trace.rawArsHostTraceContext = context})
    , pooled get "generic label cannot borrow the canonical direct invocation tag" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (trace f)
            context = (Trace.rawArsHostTraceContext raw) {Trace.rawArsHostExecutionBinding = "direct-local-attempt-v1"}
        assertLeft
          "row differs from its recorded compiled ARS plan"
          (Trace.refineArsHostTrace raw {Trace.rawArsHostTraceContext = context})
    , pooled get "missing compiled completion binding cannot reach generic physical admission" $ \f -> do
        let actualRaw = Training.completedTrainingToRaw (fixtureCompleted f)
        assertLeft
          "completed-training V3 requires a compiled RL plan"
          (Training.refineCompletedTraining actualRaw {Training.rawCompletedTrainingRlPlan = Nothing})
        -- Ordinary supported V2 DATA, never a restored actual origin/capability.
        changed <-
          right
            ( Training.refineCompletedTraining
                actualRaw
                  { Training.rawCompletedTrainingVersion = 2
                  , Training.rawCompletedTrainingRlPlan = Nothing
                  }
            )
        assertLeft
          "no exact compiled RL plan"
          (Physical.validateGenericArsHostCompletionData experiment changed)
    , pooled get "foreign compiled seed cannot rebind the actual generic completion" $ \f -> do
        otherPlan <- compiled "cartpole" 43 21 64
        assertLeft
          "compiled RL plan PlanId differs"
          (Training.bindCompletedTrainingToRlPlan otherPlan (fixtureCompleted f))
    , pooled get "foreign-runtime ordinary recorded data stays separate from current live admission" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (trace f)
            otherRuntime = (Trace.rawArsHostTraceRuntime raw) {Ars.arsRuntimeCompilerVersion = "different-recorded-version"}
            observed = Trace.rawArsHostTraceObservation raw
            change observation =
              observation
                { Ars.arsObservationAppliedStep =
                    (Ars.arsObservationAppliedStep observation)
                      { Ars.arsStepNumericalRuntime = otherRuntime
                      }
                }
        changed <-
          right
            ( Trace.refineArsHostTrace
                raw
                  { Trace.rawArsHostTraceRuntime = otherRuntime
                  , Trace.rawArsHostTraceObservation =
                      observed
                        { Common.rawTrainerStats = fmap change (Common.rawTrainerStats observed)
                        }
                  }
            )
        otherReference <- right (Trace.arsHostTraceRecordedReference changed)
        let completed = fixtureCompleted f
        base <-
          right
            ( Evidence.mkTrainingEvidence
                (Training.completedTrainingInitialWeightHash completed)
                (Training.completedTrainingFinalWeightHash completed)
                (Training.completedTrainingUpdateCount completed)
                (Training.completedTrainingDatasetShaAtRead completed)
            )
        recorded <- right (Evidence.attachRecordedArsHostReference otherReference base)
        changedCompletion <-
          right
            ( Training.refineCompletedTraining
                (Training.completedTrainingToRaw completed)
                  { Training.rawCompletedTrainingEvidence = recorded
                  }
            )
        Physical.validateArsHostCheckpointRecordedData
          experiment
          changedCompletion
          (fixtureFinal f)
          otherReference
          changed
          @?= Right ()
        assertLeft
          "numerical runtime differs from the current replay runtime"
          ( Physical.validateArsHostCheckpointData
              experiment
              changedCompletion
              (fixtureFinal f)
              otherReference
              changed
          )
    , pooled get "truncated final evaluation is rejected without reminting an actual origin" $ \f -> do
        raw <- present "actual raw return" (Execution.genericArsAttemptRawReturn (fixtureAttempt f))
        artifact <- trained (fixtureRun f)
        let episodes = take 20 (Execution.evaluationSetEpisodes (Execution.trainedArtifactEvaluationSet artifact))
            ordinary =
              Observation.TrainerReturned
                ( Observation.RawTrainerObservation
                    (fixturePlan f)
                    (Observation.ReturnedArs raw)
                    (Observation.EvaluationReturned episodes)
                )
        assertBool
          "ordinary truncated data unexpectedly refined"
          ( case Execution.refineStrictRecordedTrainerObservation
              (Reference.arsHostReferenceLane (reference f))
              ordinary of
              Left _ -> True
              Right _ -> False
          )
        assertBool
          "ordinary mutation destroyed original actual origin"
          (case Execution.genericArsAttemptOrigin (fixtureAttempt f) of Just _ -> True; Nothing -> False)
    , testCase
        "public ARS compiler preserves all current supported environments and positive evaluation counts"
        $ forM_ ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
        $ \environment ->
          forM_ [1, 21, 200] $ \count -> do
            plan <- compiled environment 42 count 64
            Budget.compiledRlEvaluationEpisodes plan @?= count
            _ <- right (Trace.resolveArsHostPlanData plan)
            pure ()
    , testCase "public generic ARS derived horizon and fifty-iteration floor remain unchanged" $ do
        small <- compiled "cartpole" 42 21 1
        large <- compiled "cartpole" 42 21 501
        smallSchedule <- present "small full ARS schedule" (Budget.compiledRlSchedule small)
        largeSchedule <- present "large full ARS schedule" (Budget.compiledRlSchedule large)
        Budget.scheduleArsMaxEpisodeSteps smallSchedule @?= 500
        Budget.scheduleArsMaxEpisodeSteps largeSchedule @?= 501
        Budget.scheduleArsIterations smallSchedule @?= 50
        Budget.scheduleArsIterations largeSchedule @?= 50
        Budget.scheduleObservedEnvironmentSteps largeSchedule @?= 50 * 2 * 16 * 501
    , testCase "actual generic entry rejects canonical experiment before any source or trainer access" $ do
        plan <- compiled "cartpole" 42 21 64
        canonical <- canonicalExperiment
        actual <-
          Execution.runGenericArsAttemptForPlan
            LinuxCPU
            canonical
            (error "canonical preflight touched source")
            plan
        assertFailureStage Execution.ArsSuppliedContext actual
    , testCase "actual generic entry retains synchronous source refusal without a fabricated origin" $ do
        plan <- compiled "cartpole" 42 21 64
        actual <-
          Execution.runGenericArsAttemptForPlan
            LinuxCPU
            experiment
            (error "generic source refusal sentinel")
            plan
        assertFailureStage Execution.ArsBeforeProcess actual
    , testCase "actual generic entry propagates asynchronous source failure" $ do
        plan <- compiled "cartpole" 42 21 64
        actual <-
          try (Execution.runGenericArsAttemptForPlan LinuxCPU experiment (throw UserInterrupt) plan)
            :: IO (Either SomeException Execution.GenericArsAttempt)
        case actual of
          Left exception -> (fromException exception :: Maybe AsyncException) @?= Just UserInterrupt
          Right _ -> assertFailure "asynchronous source failure became an ordinary attempt"
    ]

experiment :: Text
experiment = "unit-generic-ars-host-actual"

compiled :: Text -> Int -> Int -> Int -> IO Budget.CompiledRlPlan
compiled environment seed evaluations horizon =
  right $
    Budget.compileRlPlan
      Budget.TrainingPlan
        { Budget.trainingPlanTrainerKind = "ars"
        , Budget.trainingPlanEnvironment = environment
        , Budget.trainingPlanSeed = seed
        , Budget.trainingPlanMaxEpisodeSteps = horizon
        , Budget.trainingPlanEpisodeBudgetFloor = Budget.productRlDefaultTrainingEpisodeFloor
        , Budget.trainingPlanVectorEnvironments = Nothing
        , Budget.trainingPlanRequestedTransitionFloor = Nothing
        , Budget.trainingPlanExactTransitionTarget = Nothing
        }
      (Budget.EvaluationPlan evaluations)

acquire :: IO Fixture
acquire = do
  plan <- compiled "cartpole" 42 21 64
  selected <- right =<< ModelConvergence.selectedModelConvergenceSubstrate
  attempt <- Execution.runGenericArsAttemptForPlan selected experiment "." plan
  origin <- present "actual generic origin" (Execution.genericArsAttemptOrigin attempt)
  run <- right (Execution.genericArsAttemptStrictResult attempt)
  artifact <- trained run
  let counters = Execution.trainedArtifactCounters artifact
      steps = Common.measuredEnvironmentTransitionCount counters
  metrics <-
    right
      (Completion.rlCompletionMetrics "ars" counters (Execution.trainedArtifactEvaluationSet artifact))
  planId <- right (Plan.refinePlanIdText (Budget.compiledRlPlanId plan))
  actualCompletion <-
    right
      ( Completion.rlCompletedTraining
          planId
          Writer.checkpointTrainingBudgetForTensor
          "ars"
          "cartpole"
          experiment
          "rl-ars-weights"
          steps
          metrics
          (Execution.trainedArtifactEvidence artifact)
      )
  completion <-
    present ("actual generic quality completion; measured metrics=" <> show metrics) actualCompletion
  completed <- right (Training.bindCompletedTrainingToRlPlan plan completion)
  let actualTrace = Execution.producedGenericArsHostTrace origin
      actualReference = Execution.producedGenericArsHostReference origin
      trajectory =
        UTF8.encodeUtf8
          ( renderActualTrajectory
              (Execution.evaluationSetEpisodes (Execution.trainedArtifactEvaluationSet artifact))
          )
      trajectorySha = Weight.jmw1ContentSha (LBS.fromStrict trajectory)
      trajectoryKey = "jitml-checkpoints/" <> experiment <> "/artifacts/rl-trajectory/" <> trajectorySha <> ".txt"
      companion = Format.ArtifactPointer "rl-trajectory" trajectoryKey (Just trajectorySha)
      host =
        Format.ArtifactPointer
          "ars-host-execution"
          (Reference.arsHostReferenceObjectKey actualReference)
          (Just (Reference.arsHostReferenceContentSha256 actualReference))
      actualWeights = Execution.trainedArtifactWeights artifact
      weightPayload = Weight.encodeJmw1 actualWeights
      weightKey = Format.blobKey experiment (Weight.jmw1ContentSha weightPayload)
      weightTensor = Format.TensorBlob "rl-ars-weights" [length actualWeights] weightKey
      base =
        Format.attachCompletedTraining
          completed
          ( (Format.emptyManifest ("checkpoint-" <> Text.pack (show steps)) experiment [weightTensor])
              { Format.manifestModelFamily = Format.ReinforcementLearningPolicyFamily
              , Format.manifestArchitecture =
                  (Format.defaultArchitectureMetadata Format.ReinforcementLearningPolicyFamily)
                    { Format.architectureName = "rl-policy"
                    }
              , Format.manifestOutputDecoders =
                  [Format.OutputDecoder "policy" Format.PolicyDistributionOutput [] Nothing Nothing]
              , Format.manifestStep = steps
              , Format.manifestMetrics = metrics
              }
          )
      weights = [(weightKey, weightPayload)]
      manifest = base {Format.manifestTranscriptPointers = [companion], Format.manifestReplayPointers = [host]}
      payloads =
        weights
          <> [ (trajectoryKey, LBS.fromStrict trajectory)
             ,
               ( Reference.arsHostReferenceObjectKey actualReference
               , LBS.fromStrict (Trace.encodeArsHostTrace actualTrace)
               )
             ]
      final = LBS.toStrict (Weight.encodeJmw1 (Execution.trainedArtifactWeights artifact))
  pure (Fixture plan attempt origin run completed manifest payloads final)

renderActualTrajectory :: [Episode.SimulatedEpisode] -> Text
renderActualTrajectory episodes =
  Text.unlines $
    [ "kind: rl-trajectory-v1"
    , "experiment-hash: " <> experiment
    , "environment: cartpole"
    , "trainer: ars"
    , "seed: 42"
    , "episodes: " <> Text.pack (show (length episodes))
    ]
      <> concatMap
        ( \episode ->
            [ "episode: " <> Text.pack (show (Episode.simEpisodeIndex episode))
            , "episode-steps: " <> Text.pack (show (Episode.simEpisodeSteps episode))
            , "episode-reward: " <> Text.pack (show (Episode.simEpisodeReward episode))
            , "episode-done: " <> Text.pack (show (Episode.simEpisodeDone episode))
            , "episode-frame-count: " <> Text.pack (show (length (Episode.simEpisodeFrames episode)))
            ]
        )
        episodes

trace :: Fixture -> Trace.ArsHostTrace
trace = Execution.producedGenericArsHostTrace . fixtureOrigin
reference :: Fixture -> Reference.ArsHostReference
reference = Execution.producedGenericArsHostReference . fixtureOrigin
assertActualHost :: Fixture -> Store.AdmittedExecutionCheckpoint -> Assertion
assertActualHost f admitted = do
  Store.admittedExecutionCompletedTraining admitted @?= fixtureCompleted f
  case Store.admittedExecutionProvenance admitted of
    ArsHostLinearExecution actual -> do
      Store.admittedArsHostReference actual @?= reference f
      Trace.encodeArsHostTrace (Store.admittedArsHostTrace actual) @?= Trace.encodeArsHostTrace (trace f)
    NeuralDeviceExecution _ -> assertFailure "generic ARS acquired an invented neural witness"
persist :: FilePath -> Fixture -> Format.CheckpointManifest -> IO Text
persist root f manifest = do
  let keys =
        fmap Format.tensorBlobKey (Format.manifestTensors manifest)
          <> fmap
            Format.artifactPointerObjectKey
            (Format.manifestReplayPointers manifest <> Format.manifestTranscriptPointers manifest)
      payloads = filter ((`elem` keys) . fst) (fixturePayloads f)
  stored <-
    right =<< Store.writeCompletedCheckpointSnapshot root (fixtureCompleted f) manifest payloads Nothing
  pure (Store.storedManifestSha (Store.completedStoredCheckpoint stored))
physicalPointer :: FilePath -> Text -> IO Format.ArtifactPointer
physicalPointer root sha = do
  actual <- right =<< Store.admitLocalCheckpointAt root experiment sha
  only (Format.manifestReplayPointers (Store.admittedCheckpointManifest actual))
canonicalExperiment :: IO Text
canonicalExperiment = case find ((== "ARS/cartpole") . Matrix.rowId) Matrix.allProductRows of
  Nothing -> assertFailure "actual canonical ARS row absent" >> fail "canonical row"
  Just row -> pure (Matrix.productRowExperimentHash row)
assertFailureStage :: Execution.ArsAttemptStage -> Execution.GenericArsAttempt -> Assertion
assertFailureStage stage actual = do
  case Execution.genericArsAttemptFailure actual of
    Just (Execution.ArsAttemptFailure observed _) -> observed @?= stage
    Nothing -> assertFailure "actual failed entry had no failure stage"
  case Execution.genericArsAttemptOrigin actual of
    Nothing -> pure ()
    Just _ -> assertFailure "preflight/source failure manufactured an actual origin"
  case Execution.genericArsAttemptStrictResult actual of
    Left _ -> pure ()
    Right _ -> assertFailure "preflight/source failure manufactured a strict trained run"
pooled :: IO Fixture -> String -> (Fixture -> Assertion) -> TestTree
pooled get title body = testCase title (get >>= body)
fresh :: (FilePath -> IO a) -> IO a
fresh = withSystemTempDirectory "jitml-generic-ars-host"
trained :: Execution.TrainerRun -> IO Execution.TrainedArtifact
trained (Execution.Trained actual) = pure actual
trained (Execution.EvaluationOnly _) = assertFailure "actual ARS run was evaluation-only" >> fail "actual trained artifact"
present :: String -> Maybe a -> IO a
present _ (Just value) = pure value
present label Nothing = assertFailure ("missing " <> label) >> fail label
right :: (Show e) => Either e a -> IO a
right (Right value) = pure value
right (Left reason) = assertFailure (show reason) >> fail "expected Right"
only :: [a] -> IO a
only [value] = pure value
only _ = assertFailure "expected one actual object" >> fail "cardinality"
assertLeft :: (Show e) => String -> Either e a -> Assertion
assertLeft expected (Left reason) = assertBool (show reason) (Text.pack expected `Text.isInfixOf` Text.pack (show reason))
assertLeft _ (Right _) = assertFailure "unexpected successful boundary"

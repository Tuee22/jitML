{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | One pooled actual full canonical ARS numerical trace, then physical Store
-- fixtures with explicitly synthetic quality measurements. These are offline
-- DATA/byte-admission controls, not five-model learning or producer authority.
module ArsHostPhysicalAdmission (arsHostPhysicalAdmissionTests) where

import Control.Exception (fromException)
import Control.Exception.Safe (tryAny)
import Control.Monad.Reader (runReaderT)
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import System.Directory (doesDirectoryExist, removeFile)
import System.Exit (ExitCode (..))
import System.IO (IOMode (WriteMode), hSetFileSize, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.ArsHostPhysical qualified as Physical
import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weight
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as Reference
import JitML.Product.Completion qualified as Completion
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.ContractFixtures qualified as Fixtures
import JitML.Training.Budget qualified as Budget

data Fixture = Fixture
  { fixtureExperiment :: !Text
  , fixtureTrace :: !Trace.ArsHostTrace
  , fixtureReference :: !Reference.ArsHostReference
  , fixtureCompleted :: !Budget.CompletedTraining
  , fixtureFinal :: !BS.ByteString
  , fixtureManifest :: !Format.CheckpointManifest
  , fixturePayloads :: ![(Text, LBS.ByteString)]
  }

arsHostPhysicalAdmissionTests :: TestTree
arsHostPhysicalAdmissionTests = withResource acquire (const (pure ())) $ \get ->
  testGroup
    "ARS physical execution admission"
    [ pooled get "actual full canonical trace binds recorded data without a neural witness" $ \f -> do
        Physical.validateArsHostCheckpointData
          (fixtureExperiment f)
          (fixtureCompleted f)
          (fixtureFinal f)
          (fixtureReference f)
          (fixtureTrace f)
          @?= Right ()
        assertLeft
          "does not carry a neural device witness"
          (Budget.completedTrainingDeviceWitness (fixtureCompleted f))
        Budget.completedTrainingRlPlan (fixtureCompleted f) @?= Nothing
    , pooled get "portable recorded DATA checks the actual complete canonical trace and exact final bytes" $ \f -> do
        Physical.validateArsHostCheckpointRecordedData
          (fixtureExperiment f)
          (fixtureCompleted f)
          (fixtureFinal f)
          (fixtureReference f)
          (fixtureTrace f)
          @?= Right ()
        assertLeft
          "final JMW1 bytes differ"
          ( Physical.validateArsHostCheckpointRecordedData
              (fixtureExperiment f)
              (fixtureCompleted f)
              BS.empty
              (fixtureReference f)
              (fixtureTrace f)
          )
    , pooled get "portable recorded DATA retains foreign runtime without claiming local arithmetic replay" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (fixtureTrace f)
            runtime = (Trace.rawArsHostTraceRuntime raw) {Ars.arsRuntimeCompilerVersion = "different-recorded-version"}
            observed = Trace.rawArsHostTraceObservation raw
            change item =
              item
                { Ars.arsObservationAppliedStep =
                    (Ars.arsObservationAppliedStep item) {Ars.arsStepNumericalRuntime = runtime}
                }
        changed <-
          right
            ( Trace.refineArsHostTrace
                raw
                  { Trace.rawArsHostTraceRuntime = runtime
                  , Trace.rawArsHostTraceObservation =
                      observed {Common.rawTrainerStats = fmap change (Common.rawTrainerStats observed)}
                  }
            )
        reference <- right (Trace.arsHostTraceRecordedReference changed)
        completed <- withReference f reference
        Physical.validateArsHostCheckpointRecordedData
          (fixtureExperiment f)
          completed
          (fixtureFinal f)
          reference
          changed
          @?= Right ()
        assertLeft
          "numerical runtime differs from the current replay runtime"
          (validate f completed (fixtureFinal f) reference changed (fixtureExperiment f))
    , pooled get "canonical host completion structurally retains its exact context lane" $ \f -> do
        _ <- right (Format.validateCheckpointCompletion (fixtureManifest f))
        Reference.arsHostReferenceLane (fixtureReference f) @?= LinuxCPU
    , pooled get "actual local snapshot admits a closed physically fetched host trace" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        admitted <- right =<< Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
        Store.admittedExecutionCompletedTraining admitted @?= fixtureCompleted f
        case Store.admittedExecutionProvenance admitted of
          NeuralDeviceExecution _ -> assertFailure "host admission manufactured a neural witness"
          ArsHostLinearExecution bound -> do
            Store.admittedArsHostReference bound @?= fixtureReference f
            Trace.encodeArsHostTrace (Store.admittedArsHostTrace bound)
              @?= Trace.encodeArsHostTrace (fixtureTrace f)
            assertBool
              "actual trace address was not snapshot-scoped"
              (Store.admittedArsHostObjectKey bound /= Reference.arsHostReferenceObjectKey (fixtureReference f))
            case Store.admittedCheckpointWeights (Store.admittedExecutionCheckpoint admitted) of
              [loaded] -> Store.loadedWeightJmw1Bytes loaded @?= fixtureFinal f
              _ -> assertFailure "physical final tensor count differs"
    , pooled get "HasMinIO filesystem snapshot uses the same actual host admission boundary" $ \f -> fresh $ \root -> do
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
        admitted <-
          right =<< runFilesystemMinIO root (Store.admitExecutionCheckpointAt (fixtureExperiment f) sha)
        case Store.admittedExecutionProvenance admitted of
          ArsHostLinearExecution bound -> Store.admittedArsHostReference bound @?= fixtureReference f
          NeuralDeviceExecution _ -> assertFailure "host HasMinIO admission manufactured a neural witness"
    , pooled get "old neural-only admission rejects the host branch explicitly" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        physical <- right =<< Store.admitLocalCheckpointAt root (fixtureExperiment f) sha
        assertLeft "ARS host linear execution" (Store.requireAdmittedCompletedCheckpoint physical)
    , testCase "new closed neural alternative preserves an existing exact supervised admission" $
        Fixtures.withAdmittedProductProjection $ \root _ projection _ _ original -> do
          let experiment = Matrix.productProjectionExperimentHash projection
              sha = Store.admittedCheckpointManifestSha (Store.admittedCompletedCheckpoint original)
          admitted <- right =<< Store.admitLocalExecutionCheckpointAt root experiment sha
          Store.admittedExecutionCheckpoint admitted @?= Store.admittedCompletedCheckpoint original
          case Store.admittedExecutionProvenance admitted of
            NeuralDeviceExecution witness -> witness @?= Store.admittedCompletedDeviceWitness original
            ArsHostLinearExecution _ -> assertFailure "neural fixture changed execution kind"
    , pooled get "missing host replay pointer cannot enter closed completion admission" $ \f -> fresh $ \root -> do
        let changed = (fixtureManifest f) {Format.manifestReplayPointers = []}
        sha <- persist root f changed
        result <- Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
        assertLeft "one exact snapshot-bound ars-host-execution replay pointer" result
    , pooled get "wrong host replay kind cannot borrow a physical transcript" $ \f -> fresh $ \root -> do
        pointer <- only (Format.manifestReplayPointers (fixtureManifest f))
        let changed =
              (fixtureManifest f)
                { Format.manifestReplayPointers = [pointer {Format.artifactPointerKind = "caller-says-host"}]
                }
        sha <- persist root f changed
        assertLeft "one exact snapshot-bound ars-host-execution replay pointer"
          =<< Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
    , pooled get "duplicate replay objects fail the real snapshot writer" $ \f -> fresh $ \root -> do
        pointer <- only (Format.manifestReplayPointers (fixtureManifest f))
        let changed = (fixtureManifest f) {Format.manifestReplayPointers = [pointer, pointer]}
        result <-
          Store.writeCompletedCheckpointSnapshot root (fixtureCompleted f) changed (fixturePayloads f) Nothing
        assertLeft "duplicate physical object key" result
        doesDirectoryExist (root <> "/jitml-checkpoints") >>= (@?= False)
    , pooled get "missing actual trace file fails physical readback" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        pointer <- actualPointer root f sha
        path <- right (Store.objectPathForKey root (Format.artifactPointerObjectKey pointer))
        removeFile path
        result <- Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
        case result of
          Left (Store.AdmissionBlobReadFailed key _) -> key @?= Format.artifactPointerObjectKey pointer
          other -> assertFailure ("expected actual trace read failure: " <> show other)
    , pooled get "altered trace bytes fail their committed physical digest" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        pointer <- actualPointer root f sha
        path <- right (Store.objectPathForKey root (Format.artifactPointerObjectKey pointer))
        bytes <- BS.readFile path
        case BS.uncons bytes of
          Nothing -> assertFailure "actual trace bytes were empty"
          Just (first, rest) -> BS.writeFile path (BS.cons (first `xor` 1) rest)
        assertLeft "writer-commit SHA-256 mismatch"
          =<< Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
    , pooled get "oversized actual trace is refused during the first bounded physical bind" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        pointer <- actualPointer root f sha
        path <- right (Store.objectPathForKey root (Format.artifactPointerObjectKey pointer))
        -- Sparse ordinary fixture file; no giant ByteString is manufactured.
        withBinaryFile path WriteMode $ \handle ->
          hSetFileSize handle (toInteger (Reference.arsHostReferenceByteLength (fixtureReference f)) + 1)
        assertLeft "ARS physical trace exceeds its recorded byte limit before materialization"
          =<< Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
    , pooled get "altered final JMW1 bytes fail actual physical admission" $ \f -> fresh $ \root -> do
        sha <- persist root f (fixtureManifest f)
        physical <- right =<< Store.admitLocalCheckpointAt root (fixtureExperiment f) sha
        tensor <- only (Format.manifestTensors (Store.admittedCheckpointManifest physical))
        path <- right (Store.objectPathForKey root (Format.tensorBlobKey tensor))
        BS.appendFile path "\NUL"
        result <- Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
        assertBool
          "physical JMW1 substitution admitted"
          (case result of Left Store.AdmissionBlobInvalid {} -> True; _ -> False)
    , pooled get "exact recorded experiment cannot be rebound by the pure DATA validator" $ \f -> do
        otherRow <-
          maybe
            (assertFailure "alternate canonical ARS row absent" >> fail "row")
            pure
            (find ((== "ARS/mountain-car") . Matrix.rowId) Matrix.allProductRows)
        let otherExperiment = Matrix.productRowExperimentHash otherRow
        assertBool
          "alternate canonical ARS experiment did not differ"
          (otherExperiment /= fixtureExperiment f)
        assertLeft
          "trace experiment differs"
          ( validate
              f
              (fixtureCompleted f)
              (fixtureFinal f)
              (fixtureReference f)
              (fixtureTrace f)
              otherExperiment
          )
    , pooled get "a changed recorded context cannot borrow the original reference" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (fixtureTrace f)
            context = (Trace.rawArsHostTraceContext raw) {Trace.rawArsHostSourceSha256 = digest "f"}
        changed <- right (Trace.refineArsHostTrace raw {Trace.rawArsHostTraceContext = context})
        assertLeft
          "ARS host trace reference object key differs"
          (validate f (fixtureCompleted f) (fixtureFinal f) (fixtureReference f) changed (fixtureExperiment f))
    , pooled get "initial signed-zero JMW1 substitution remains a distinct hash" $ \f -> do
        let actual = Common.rawTrainerInitialParams (Trace.arsHostTraceObservation (fixtureTrace f))
        assertBool
          "actual lexical initializer is not nonempty numeric zero"
          (not (VU.null actual) && VU.all (== 0) actual)
        let minus = VU.map (toggleSign 0x8000000000000000) actual
            alternate = Weight.jmw1ContentSha (Weight.encodeJmw1 (VU.toList minus))
        assertBool "signed-zero numeric values changed" (VU.toList minus == VU.toList actual)
        vectorBits minus @?= replicate (VU.length actual) 0x8000000000000000
        assertBool "signed-zero bits did not differ" (vectorBits minus /= vectorBits actual)
        assertBool
          "initial signed-zero digest did not differ"
          (alternate /= Budget.completedTrainingInitialWeightHash (fixtureCompleted f))
        evidence <- evidenceFor (fixtureReference f) alternate (fixtureCompleted f)
        changed <- replaceEvidence evidence (fixtureCompleted f)
        assertLeft
          "initial JMW1 differs"
          (validate f changed (fixtureFinal f) (fixtureReference f) (fixtureTrace f) (fixtureExperiment f))
    , pooled get "wrong trace physical counters cannot be relabeled as the plan budget" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (fixtureTrace f)
            observed = Trace.rawArsHostTraceObservation raw
            old = Common.rawTrainerCounters observed
        counters <-
          right
            ( Common.mkObservedTrainerCounters
                (toInteger (Common.observedEnvironmentTransitionCount old) - 1)
                (toInteger (Common.observedOptimizerUpdateCount old))
            )
        changed <-
          right
            ( Trace.refineArsHostTrace
                raw {Trace.rawArsHostTraceObservation = observed {Common.rawTrainerCounters = counters}}
            )
        reference <- right (Trace.arsHostTraceRecordedReference changed)
        completed <- withReference f reference
        assertLeft
          "physical counter differs from the supplied plan budget"
          (validate f completed (fixtureFinal f) reference changed (fixtureExperiment f))
    , pooled get "different recorded numerical runtime cannot become local arithmetic replay" $ \f -> do
        let raw = Trace.arsHostTraceToRaw (fixtureTrace f)
            runtime = (Trace.rawArsHostTraceRuntime raw) {Ars.arsRuntimeCompilerVersion = "different-recorded-version"}
            observed = Trace.rawArsHostTraceObservation raw
            change item =
              item
                { Ars.arsObservationAppliedStep =
                    (Ars.arsObservationAppliedStep item) {Ars.arsStepNumericalRuntime = runtime}
                }
        changed <-
          right
            ( Trace.refineArsHostTrace
                raw
                  { Trace.rawArsHostTraceRuntime = runtime
                  , Trace.rawArsHostTraceObservation =
                      observed {Common.rawTrainerStats = fmap change (Common.rawTrainerStats observed)}
                  }
            )
        reference <- right (Trace.arsHostTraceRecordedReference changed)
        completed <- withReference f reference
        assertLeft
          "numerical runtime differs from the current replay runtime"
          (validate f completed (fixtureFinal f) reference changed (fixtureExperiment f))
    , pooled get "concrete host writer rejects a foreign experiment before consulting its environment" $ \f -> do
        attempted <-
          tryAny
            ( runReaderT
                ( Writer.writeLocalCompletedArsHostCheckpoint
                    (fixtureCompleted f)
                    "foreign"
                    "rl-ars-cartpole-weights"
                    (Budget.completedTrainingObservedUnits (fixtureCompleted f))
                    []
                    (fixtureTrace f)
                    []
                )
                (error "invalid host writer reached its environment")
            )
        case attempted of
          Left exception -> case fromException exception of
            Just (ExitFailure _) -> pure ()
            _ -> assertFailure ("unexpected writer exception: " <> show exception)
          Right _ -> assertFailure "foreign host writer returned a stored checkpoint"
    , pooled get "canonical ARS neural fixture cannot use the new native execution admission" $ \f -> fresh $ \root -> do
        witness <- Fixtures.reportFixtureDeviceWitness
        let old = fixtureCompleted f
        initial <-
          right
            ( Evidence.mkTrainingEvidence
                (Budget.completedTrainingInitialWeightHash old)
                (Budget.completedTrainingFinalWeightHash old)
                (Budget.completedTrainingUpdateCount old)
                (Budget.completedTrainingDatasetShaAtRead old)
            )
        evidence <- right (Evidence.attachDeviceExecutionWitness witness initial)
        completed <- replaceEvidence evidence old
        let manifest =
              (Format.attachCompletedTraining completed (fixtureManifest f)) {Format.manifestReplayPointers = []}
        stored <-
          right
            =<< Store.writeCompletedCheckpointSnapshot root completed manifest (payloadsFor f manifest) Nothing
        let sha = Store.storedManifestSha (Store.completedStoredCheckpoint stored)
        assertLeft "native canonical ARS execution admission requires host linear provenance"
          =<< Store.admitLocalExecutionCheckpointAt root (fixtureExperiment f) sha
    ]
 where
  pooled get name action = testCase name (get >>= action)

-- One actual full public canonical schedule, never a shortened/fabricated
-- recipe. Its returned quality is NOT used as the synthetic byte-fixture bar.
acquire :: IO Fixture
acquire = do
  row <-
    maybe
      (assertFailure "canonical ARS row absent" >> fail "row")
      pure
      (find ((== "ARS/cartpole") . Matrix.rowId) Matrix.allProductRows)
  projected <- right (Plan.validationToEither (Matrix.projectProductRow LinuxCPU row))
  case projected of
    Matrix.SomeProductProjection Plan.ReinforcementLearningWitness projection ->
      case Matrix.productProjectionResolvedPlan projection of
        Matrix.ResolvedRlProductPlan _ -> do
          batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
          cohort <-
            maybe
              (assertFailure "canonical ARS cohort absent" >> fail "cohort")
              pure
              ( find
                  ((== "ARS/cartpole") . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
                  (Cohort.nativeRlCohortBatchPlans batch)
              )
          let serving = Cohort.nativeRlCohortServingChild cohort
          plan <-
            maybe
              (assertFailure "canonical ARS serving recipe absent" >> fail "recipe")
              pure
              (Cohort.nativeRlSeedPlanCompiledReturn serving)
          Cohort.nativeRlSeedPlanTrainingBudget serving @?= Matrix.productProjectionTrainingBudget projection
          assertBool
            "whole canonical PlanId was relabeled as its compiled recipe"
            (Plan.planIdText (Matrix.productProjectionPlanId projection) /= ProductBudget.compiledRlPlanId plan)
          (environment, config) <- right (Trace.resolveArsHostPlanData plan)
          observed <- Ars.trainArsOnEnvironmentRaw environment config
          let experiment = Matrix.productProjectionExperimentHash projection
              context =
                Trace.RawArsHostContext
                  "ARS/cartpole"
                  experiment
                  (Plan.planIdText (Matrix.productProjectionPlanId projection))
                  (ProductBudget.renderCompiledRlPlanTransport plan)
                  "linux-cpu"
                  (digest "1")
                  (digest "2")
                  (digest "3")
                  "direct-local-attempt-v1"
                  "offline-fixture-os"
                  "offline-fixture-arch"
                  "offline-fixture-release"
                  "actual-public-simulator-fixture"
                  "offline-fixture-pid"
                  "offline-fixture-attempt"
          trace <-
            right
              (Trace.refineArsHostTrace (Trace.RawArsHostTrace context Ars.arsNativeNumericalRuntime observed))
          Trace.validateArsHostTraceLocal trace @?= Right ()
          Trace.validateArsHostTracePlan plan trace @?= Right ()
          reference <- right (Trace.arsHostTraceRecordedReference trace)
          let initial = Weight.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams observed))
              final = Weight.encodeJmw1 (VU.toList (Common.rawTrainerFinalParams observed))
              bar = Matrix.convergenceBar row
              metrics = [(Convergence.convergenceMetricName bar, Convergence.convergenceLiteratureTarget bar)]
              observedSteps = Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters observed)
          -- Refuse a motionless fixture rather than replacing actual parameters.
          assertBool
            "actual full ARS fixture returned motionless parameters"
            (Weight.jmw1ContentSha initial /= Weight.jmw1ContentSha final)
          evidence0 <-
            right
              ( Evidence.mkTrainingEvidence
                  (Weight.jmw1ContentSha initial)
                  (Weight.jmw1ContentSha final)
                  (Common.observedOptimizerUpdateCount (Common.rawTrainerCounters observed))
                  (digest "4")
              )
          evidence <- right (Evidence.attachRecordedArsHostReference reference evidence0)
          completed <-
            maybe
              (assertFailure "synthetic external-bar fixture did not refine" >> fail "completion")
              pure
              ( Completion.rlCompletedTrainingWithBudget
                  (Matrix.productProjectionPlanId projection)
                  (Matrix.productProjectionTrainingBudget projection)
                  "ars"
                  "cartpole"
                  experiment
                  "rl-ars-cartpole-weights"
                  observedSteps
                  metrics
                  evidence
              )
          let finalSha = Weight.jmw1ContentSha final
              tensor =
                Format.TensorBlob
                  "rl-ars-cartpole-weights"
                  [length (VU.toList (Common.rawTrainerFinalParams observed))]
                  (Format.blobKey experiment finalSha)
              transcript = "offline physical byte fixture; synthetic quality is not observed training quality"
              transcriptSha = Weight.jmw1ContentSha transcript
              transcriptKey = Store.canonicalProductCompanionObjectKey experiment "rl-trajectory" transcriptSha
              trajectory = Format.ArtifactPointer "rl-trajectory" transcriptKey (Just transcriptSha)
              host =
                Format.ArtifactPointer
                  "ars-host-execution"
                  (Reference.arsHostReferenceObjectKey reference)
                  (Just (Reference.arsHostReferenceContentSha256 reference))
              base = Format.emptyManifest "offline-ars-physical" experiment [tensor]
              manifest =
                Format.attachCompletedTraining
                  completed
                  base
                    { Format.manifestModelFamily = Format.ReinforcementLearningPolicyFamily
                    , Format.manifestArchitecture =
                        (Format.manifestArchitecture base)
                          { Format.architectureModelFamily = Format.ReinforcementLearningPolicyFamily
                          }
                    , Format.manifestStep = observedSteps
                    , Format.manifestMetrics = metrics
                    , Format.manifestReplayPointers = [host]
                    , Format.manifestTranscriptPointers = [trajectory]
                    }
          pure
            ( Fixture
                experiment
                trace
                reference
                completed
                (LBS.toStrict final)
                manifest
                [ (Format.tensorBlobKey tensor, final)
                , (transcriptKey, transcript)
                , (Reference.arsHostReferenceObjectKey reference, LBS.fromStrict (Trace.encodeArsHostTrace trace))
                ]
            )
    _ -> assertFailure "canonical ARS projection changed kind" >> fail "projection"

validate
  :: Fixture
  -> Budget.CompletedTraining
  -> BS.ByteString
  -> Reference.ArsHostReference
  -> Trace.ArsHostTrace
  -> Text
  -> Either Text ()
validate _ completed bytes reference trace experiment = Physical.validateArsHostCheckpointData experiment completed bytes reference trace

evidenceFor
  :: Reference.ArsHostReference -> Text -> Budget.CompletedTraining -> IO Evidence.TrainingEvidence
evidenceFor reference initial completed = do
  base <-
    right
      ( Evidence.mkTrainingEvidence
          initial
          (Budget.completedTrainingFinalWeightHash completed)
          (Budget.completedTrainingUpdateCount completed)
          (Budget.completedTrainingDatasetShaAtRead completed)
      )
  right (Evidence.attachRecordedArsHostReference reference base)
withReference :: Fixture -> Reference.ArsHostReference -> IO Budget.CompletedTraining
withReference f reference =
  evidenceFor
    reference
    (Budget.completedTrainingInitialWeightHash (fixtureCompleted f))
    (fixtureCompleted f)
    >>= \evidence -> replaceEvidence evidence (fixtureCompleted f)
replaceEvidence
  :: Evidence.TrainingEvidence -> Budget.CompletedTraining -> IO Budget.CompletedTraining
replaceEvidence evidence completed =
  right
    ( Budget.refineCompletedTraining
        (Budget.completedTrainingToRaw completed) {Budget.rawCompletedTrainingEvidence = evidence}
    )

payloadsFor :: Fixture -> Format.CheckpointManifest -> [(Text, LBS.ByteString)]
payloadsFor f manifest = filter ((`elem` keys) . fst) (fixturePayloads f)
 where
  keys =
    fmap Format.tensorBlobKey (Format.manifestTensors manifest)
      <> fmap
        Format.artifactPointerObjectKey
        (Format.manifestReplayPointers manifest <> Format.manifestTranscriptPointers manifest)
persist :: FilePath -> Fixture -> Format.CheckpointManifest -> IO Text
persist root f manifest =
  Store.storedManifestSha . Store.completedStoredCheckpoint
    <$> ( right
            =<< Store.writeCompletedCheckpointSnapshot
              root
              (fixtureCompleted f)
              manifest
              (payloadsFor f manifest)
              Nothing
        )
actualPointer :: FilePath -> Fixture -> Text -> IO Format.ArtifactPointer
actualPointer root f sha = do
  admitted <- right =<< Store.admitLocalCheckpointAt root (fixtureExperiment f) sha
  only (Format.manifestReplayPointers (Store.admittedCheckpointManifest admitted))
fresh :: (FilePath -> IO a) -> IO a
fresh = withSystemTempDirectory "jitml-ars-physical"
digest :: Text -> Text
digest = Text.replicate 64
only :: [a] -> IO a
only [value] = pure value
only _ = assertFailure "expected one actual object" >> fail "cardinality"
right :: (Show e) => Either e a -> IO a
right (Right value) = pure value
right (Left reason) = assertFailure (show reason) >> fail "expected Right"
assertLeft :: (Show e) => String -> Either e a -> Assertion
assertLeft expected (Left reason) = assertBool (show reason) (Text.pack expected `Text.isInfixOf` Text.pack (show reason))
assertLeft _ (Right _) = assertFailure "unexpected successful boundary"

-- Same opaque primitive boundary as the previously measured signed-zero
-- diagnostic; the mutation consumes actual runtime-returned initial values.
{-# NOINLINE vectorBits #-}
vectorBits :: VU.Vector Double -> [Word64]
vectorBits = map castDoubleToWord64 . VU.toList
{-# NOINLINE toggleSign #-}
toggleSign :: Word64 -> Double -> Double
toggleSign mask value = castWord64ToDouble (castDoubleToWord64 value `xor` mask)

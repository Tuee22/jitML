{-# LANGUAGE OverloadedStrings #-}

-- | Connect an actual replayed/assessed cohort to the unchanged strict numeric
-- serving prerequisites for index zero. A candidate is not CompletedTraining,
-- an authenticated publication, physical artifact replay or Store admission.
module JitML.Product.NativeRlServingCandidate
  ( NativeServingCandidate
  , NativeServingCandidateModel (..)
  , NativeServingCandidateFailure (..)
  , prepareNativeServingCandidate
  , nativeServingCandidateAssessment
  , nativeServingCandidateModel
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, void)
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.WeightCodec qualified as Weights
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.NativeHerEvaluation qualified as HerEvaluation
import JitML.RL.NativeHerReferences qualified as HerReference
import JitML.RL.NativeReturnEvaluation qualified as ReturnEvaluation
import JitML.RL.NativeReturnReferences qualified as ReturnReference
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerExecution qualified as Strict
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Training.Budget qualified as Training

-- These exposed alternatives are ordinary inspection data. Rewrapping a
-- modified artifact cannot construct the enclosing private candidate.
data NativeServingCandidateModel
  = NativeReturnServingCandidateData
      !Cohort.NativeRlSeedPlan
      !Strict.TrainedArtifact
      !(Maybe Trace.ArsHostTrace)
  | NativeArenaServingCandidateData
      !Cohort.NativeRlSeedPlan
      !Arena.NativeAlphaZeroEvaluatedData

data NativeServingCandidate
  = NativeServingCandidate
      !Assessment.NativeCohortAssessment
      !NativeServingCandidateModel

data NativeServingCandidateFailure
  = NativeServingLearningRefusal ![Text]
  | NativeServingDataRefusal !Failure.NativeDiagnosticData
  | NativeServingSynchronousFailure !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)

nativeServingCandidateAssessment :: NativeServingCandidate -> Assessment.NativeCohortAssessment
nativeServingCandidateAssessment (NativeServingCandidate value _) = value

nativeServingCandidateModel :: NativeServingCandidate -> NativeServingCandidateModel
nativeServingCandidateModel (NativeServingCandidate _ value) = value

-- No supplied weights, metrics, evaluator, witness, store or result callbacks.
-- Failed assessment data already remains retained by its actual acquisition;
-- denying a serving candidate never replaces or drops a training member.
prepareNativeServingCandidate
  :: Assessment.NativeCohortAssessment
  -> IO (Either NativeServingCandidateFailure NativeServingCandidate)
prepareNativeServingCandidate assessment = do
  attempted <- tryAny $ do
    built <- evaluate (buildCandidate assessment)
    case built of
      Left findings -> do
        mapM_ (evaluate . Text.length) findings
        pure (Left (NativeServingLearningRefusal findings))
      Right (Left reason) -> Left . NativeServingDataRefusal <$> Failure.captureNativeDiagnostic reason
      Right (Right model) -> do
        forceModel model
        pure (Right (NativeServingCandidate assessment model))
  case attempted of
    Left exception -> Left . NativeServingSynchronousFailure <$> Failure.captureNativeExceptionDiagnostic exception
    Right result -> pure result

buildCandidate
  :: Assessment.NativeCohortAssessment
  -> Either [Text] (Either Text NativeServingCandidateModel)
buildCandidate assessment =
  case Assessment.nativeAssessmentLearningFindings assessment of
    [] -> Right $ do
      let replay = Assessment.nativeAssessmentReplay assessment
          produced = Replay.nativeEvaluationReplayedProducer replay
          children = Producer.nativeProducedChildren produced
      unless
        ( fmap
            (Cohort.nativeSeedIndexValue . Producer.nativeChildIndex . Producer.nativeProducedChildData)
            children
            == [0 .. 4]
        )
        (Left "native serving requires the complete original five-child order")
      mapM_ validateActualBudgetData children
      case children of
        served : _ -> buildModel served
        [] -> Left "native serving has no original index-zero child"
    findings -> Left findings

buildModel :: Producer.NativeProducedChild -> Either Text NativeServingCandidateModel
buildModel served = case Producer.nativeProducedModelData served of
  Producer.NativeNeuralNumericalData actual -> do
    let returned = Neural.nativeEvaluatedReturnedData actual
        child = Neural.nativeReturnedChild returned
        seed = Neural.nativeNeuralChildSeedPlan child
        lane =
          Cohort.nativeRlCohortBatchSubstrate
            (Neural.nativeNeuralRowBatch (Neural.nativeNeuralChildRow child))
        plan = Neural.nativeNeuralChildCompiledPlan child
    checkedServingIndex seed
    evaluation <- neuralEvaluationData (Neural.nativeEvaluatedFinalEvaluation actual)
    artifact <- strictArtifact lane plan (Neural.nativeReturnedPolicy returned) evaluation
    evidence <- case Producer.nativeChildDevice (Producer.nativeProducedChildData served) of
      Producer.NativeDeviceReturned (Just witness) -> Evidence.attachDeviceExecutionWitness witness (Strict.trainedArtifactEvidence artifact)
      _ -> Left "actual native neural serving child lacks its own produced execution witness"
    pure
      (NativeReturnServingCandidateData seed (artifact {Strict.trainedArtifactEvidence = evidence}) Nothing)
  Producer.NativeArsNumericalData actual -> do
    let returned = Ars.nativeArsFinalReturned actual
        child = Ars.nativeArsReturnedChild returned
        seed = Ars.nativeArsChildSeedPlan child
        lane = Cohort.nativeRlCohortBatchSubstrate (Ars.nativeArsRowBatch (Ars.nativeArsChildRow child))
        plan = Ars.nativeArsChildCompiledPlan child
    checkedServingIndex seed
    evaluation <-
      maybe
        (Left "actual native ARS serving evaluation is absent")
        returnEvaluationData
        (Ars.nativeArsFinalEvaluation actual)
    artifact <-
      strictArtifact lane plan (Observation.ReturnedArs (Ars.nativeArsReturnedPolicy returned)) evaluation
    origin <-
      mapLeft
        (("actual native ARS serving origin failed: " <>) . Ars.nativeArsFailureDetail)
        (Ars.nativeArsFinalOrigin actual)
    trace <- actualArsTrace origin
    reference <- Trace.arsHostTraceRecordedReference trace
    Trace.validateArsHostTraceReference reference trace
    evidence <-
      Evidence.attachRecordedArsHostReference reference (Strict.trainedArtifactEvidence artifact)
    pure
      ( NativeReturnServingCandidateData
          seed
          (artifact {Strict.trainedArtifactEvidence = evidence})
          (Just trace)
      )
  Producer.NativeArenaNumericalData actual -> do
    let returned = Arena.nativeAlphaZeroEvaluatedReturnedData actual
        seed = Arena.nativeAlphaZeroChildSeedPlan (Arena.nativeAlphaZeroReturnedChild returned)
    checkedServingIndex seed
    -- The existing AlphaZero completion producer still owns its strict work,
    -- sample/weight/evidence guards. This candidate cannot manufacture it.
    pure (NativeArenaServingCandidateData seed actual)

checkedServingIndex :: Cohort.NativeRlSeedPlan -> Either Text ()
checkedServingIndex seed =
  unless
    (Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex seed) == 0)
    (Left "native serving may use only original prescribed index zero")

-- Every member must actually complete its prescribed physical budget. This
-- does not impose index-zero's legacy positive-update/curve/evidence gates on
-- the four auxiliary outcomes, or require five individual quality successes.
-- Finite nonlearning/zero-update auxiliary data still participates in the
-- unchanged full-five median and three-joint-success policy.
validateActualBudgetData :: Producer.NativeProducedChild -> Either Text ()
validateActualBudgetData produced = case Producer.nativeProducedModelData produced of
  Producer.NativeNeuralNumericalData actual -> do
    let returned = Neural.nativeEvaluatedReturnedData actual
        plan = Neural.nativeNeuralChildCompiledPlan (Neural.nativeReturnedChild returned)
    evaluation <- neuralEvaluationData (Neural.nativeEvaluatedFinalEvaluation actual)
    void
      ( Observation.refineBudgetCompleteTrainerObservation
          (Observation.RawTrainerObservation plan (Neural.nativeReturnedPolicy returned) evaluation)
      )
  Producer.NativeArsNumericalData actual -> do
    let returned = Ars.nativeArsFinalReturned actual
        plan = Ars.nativeArsChildCompiledPlan (Ars.nativeArsReturnedChild returned)
    evaluation <-
      maybe
        (Left "native ARS cohort member has no final evaluation")
        returnEvaluationData
        (Ars.nativeArsFinalEvaluation actual)
    void
      ( Observation.refineBudgetCompleteTrainerObservation
          ( Observation.RawTrainerObservation
              plan
              (Observation.ReturnedArs (Ars.nativeArsReturnedPolicy returned))
              evaluation
          )
      )
  Producer.NativeArenaNumericalData actual -> do
    let returned = Arena.nativeAlphaZeroEvaluatedReturnedData actual
    Arena.validateNativeAlphaZeroReturnedData
      (Arena.nativeAlphaZeroReturnedChild returned)
      (Arena.nativeAlphaZeroReturnedSnapshot returned)
      (Arena.nativeAlphaZeroReturnedRawObservation returned)

strictArtifact
  :: Substrate
  -> Budget.CompiledRlPlan
  -> Observation.ReturnedPolicy
  -> Observation.RawEvaluation
  -> Either Text Strict.TrainedArtifact
strictArtifact lane plan policy evaluation = do
  let raw = Observation.RawTrainerObservation plan policy evaluation
  -- Physical-budget/finite data consistency remains distinct from the original
  -- stricter positive-counter/curve/weight/evidence checks; preserve both.
  _ <- Observation.refineBudgetCompleteTrainerObservation raw
  result <- Strict.refineStrictRecordedTrainerObservation lane (Observation.TrainerReturned raw)
  case result of
    Strict.Trained artifact -> Right artifact
    Strict.EvaluationOnly _ -> Left "native actual trained serving result was evaluation-only"

neuralEvaluationData :: Neural.NativeEvaluationData -> Either Text Observation.RawEvaluation
neuralEvaluationData evaluation = case evaluation of
  Neural.NativeReturnEvaluation actual -> returnEvaluationData actual
  Neural.NativeHerEvaluation actual -> do
    unless
      (HerEvaluation.nativeHerEvaluationStatus actual == HerEvaluation.NativeHerEvaluationComplete)
      (Left "native HER serving evaluation is incomplete")
    pure
      ( Observation.HerEvaluationReturned
          [ ( HerReference.nativeHerOutcomeSuccess result
            , HerReference.nativeHerOutcomeNormalizedDistance result
            , HerReference.nativeHerOutcomeSteps result
            )
          | result <- HerEvaluation.nativeHerEvaluationOutcomes actual
          ]
      )

returnEvaluationData
  :: ReturnEvaluation.RawNativeReturnEvaluation -> Either Text Observation.RawEvaluation
returnEvaluationData actual = do
  unless
    (ReturnEvaluation.nativeEvaluationStatus actual == ReturnEvaluation.NativeEvaluationComplete)
    (Left "native RETURN serving evaluation is incomplete")
  -- The native evaluator records complete episode summaries and forwards, not
  -- EpisodeEnvelope frames. Preserve that actual absence; never invent frames.
  pure
    ( Observation.EvaluationReturned
        [ Episode.SimulatedEpisode
            { Episode.simEpisodeIndex = ReturnReference.nativeReturnEpisodeId result
            , Episode.simEpisodeSteps = ReturnReference.nativeReturnEpisodeSteps result
            , Episode.simEpisodeReward = ReturnReference.nativeReturnEpisodeReward result
            , Episode.simEpisodeDone = ReturnReference.nativeReturnEpisodeTerminated result
            , Episode.simEpisodeFrames = []
            }
        | result <- ReturnEvaluation.nativeEvaluationEpisodes actual
        ]
    )

-- This lossless recorded trace is derived only from the actual private ARS
-- origin attached to the same serving child. Its own public refiners remain
-- DATA checks; a later writer must retain its exact bytes and address before
-- completion/publication, and the parent must authenticate the full inventory.
actualArsTrace :: Ars.NativeArsExecutionOrigin -> Either Text Trace.ArsHostTrace
actualArsTrace origin = do
  let child = Ars.nativeArsOriginChild origin
      seed = Ars.nativeArsChildSeedPlan child
      singleton = Cohort.nativeRlSeedPlanSingleton seed
      compiled = Ars.nativeArsChildCompiledPlan child
      row = Ars.nativeArsChildRow child
      before = Ars.nativeArsOriginBeforeProcess origin
      invocation =
        Association.nativeAssociationInvocation
          <$> Ars.nativeArsContextAssociation (Ars.nativeArsOriginContext origin)
      stamp = case Ars.nativeArsOriginSourceCoverage origin of
        Ars.NativeArsObservedLocal _ value -> value
        Ars.NativeArsUnauthenticatedParentSource value -> value
  checkedServingIndex seed
  run <-
    maybe
      (Left "native ARS serving singleton is not an RL plan")
      Right
      (Native.nativeSingletonRlPlan singleton)
  trace <-
    Trace.refineArsHostTrace
      ( Trace.RawArsHostTrace
          ( Trace.RawArsHostContext
              { Trace.rawArsHostRowId = Ars.nativeArsRowId row
              , Trace.rawArsHostExperiment = Plan.runPlanExperimentId run
              , Trace.rawArsHostPlanId = Plan.planIdText (Native.nativeSingletonPlanId singleton)
              , Trace.rawArsHostCompiledTransport = Budget.renderCompiledRlPlanTransport compiled
              , Trace.rawArsHostLane =
                  renderSubstrate (Cohort.nativeRlCohortBatchSubstrate (Ars.nativeArsRowBatch row))
              , Trace.rawArsHostSourceSha256 = Source.stampSha256 stamp
              , Trace.rawArsHostExecutableSha256 = Process.producerExecutableFileSha256 before
              , Trace.rawArsHostInvocationSha256 =
                  maybe (Ars.nativeArsOriginContextDigest origin) Training.productScenarioInvocationDigest invocation
              , Trace.rawArsHostExecutionBinding =
                  maybe "direct-local-attempt-v1" (const "product-scenario-invocation-v1") invocation
              , Trace.rawArsHostKernelOS = Process.producerKernelOperatingSystem before
              , Trace.rawArsHostKernelMachine = Process.producerKernelMachine before
              , Trace.rawArsHostKernelRelease = Process.producerKernelRelease before
              , Trace.rawArsHostSimulatorContract =
                  "jitml-known-discrete-simulator-ars-v1:" <> Budget.compiledRlEnvironment compiled
              , Trace.rawArsHostProcessId = Text.pack (show (Process.producerProcessId before))
              , Trace.rawArsHostAttemptId = Ars.nativeArsOriginAttemptId origin
              }
          )
          (Ars.nativeArsOriginNumericalRuntime origin)
          (Ars.nativeArsOriginPolicy origin)
      )
  Trace.validateArsHostTracePlan compiled trace
  Trace.validateArsHostTraceLocal trace
  pure trace

forceModel :: NativeServingCandidateModel -> IO ()
forceModel model = case model of
  NativeReturnServingCandidateData _ artifact host -> do
    _ <- evaluate (LBS.length (Weights.encodeJmw1 (Strict.trainedArtifactWeights artifact)))
    let evidence = Strict.trainedArtifactEvidence artifact
    _ <-
      evaluate
        ( Text.length (Evidence.evidenceInitialWeightHash evidence)
            + Text.length (Evidence.evidenceFinalWeightHash evidence)
            + Text.length (Evidence.evidenceDatasetShaAtRead evidence)
        )
    _ <- evaluate (Evidence.evidenceUpdateCount evidence)
    case host of
      Nothing -> pure ()
      Just trace -> do
        _ <- evaluate (Trace.arsHostTraceSha256 trace)
        pure ()
  NativeArenaServingCandidateData _ actual ->
    void (evaluate (Arena.nativeAlphaZeroEvaluatedReturnedData actual))

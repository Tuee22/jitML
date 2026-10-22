{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Concrete original-index-zero completion, derived only from an actual
-- replayed, assessed serving candidate. This is neither storage, a physical
-- served-byte replay, parent authentication nor native qualification.
module JitML.Product.NativeRlCompletedServing
  ( NativeCompletedServing
  , NativeCompletedServingFailure (..)
  , prepareNativeCompletedServing
  , nativeCompletedCandidate
  , nativeCompletedTraining
  , nativeCompletedExperiment
  , nativeCompletedTensorName
  , nativeCompletedStep
  , nativeCompletedMetrics
  , nativeCompletedWeights
  , nativeCompletedHostTrace
  , nativeCompletedInvocation
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, void)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.WeightCodec qualified as Weights
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Product.Completion qualified as Completion
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativeReferenceCalibration qualified as Reference
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlServingCandidate qualified as Candidate
import JitML.RL.Algorithms.Common qualified as Counters
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as ArenaEvaluation
import JitML.RL.AlphaZero.NativeArenaReferences qualified as ArenaReference
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.AlphaZero.PreparedTrainer qualified as ArenaLow
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.ProductBudget qualified as RlBudget
import JitML.RL.TrainerExecution qualified as Trainer
import JitML.Training.Budget qualified as Training

data CompletedFields
  = CompletedFields
      !Training.CompletedTraining
      !Text
      !Text
      !Word64
      ![(Text, Double)]
      ![Double]
      !(Maybe Trace.ArsHostTrace)
      !(Maybe Training.ProductScenarioInvocation)

data NativeCompletedServing
  = NativeCompletedServing
      !Candidate.NativeServingCandidate
      !CompletedFields

data NativeCompletedServingFailure
  = NativeCompletionRefused !Failure.NativeDiagnosticData
  | NativeCompletionSynchronousFailure !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)

nativeCompletedCandidate :: NativeCompletedServing -> Candidate.NativeServingCandidate
nativeCompletedCandidate (NativeCompletedServing actual _) = actual
nativeCompletedTraining :: NativeCompletedServing -> Training.CompletedTraining
nativeCompletedTraining (NativeCompletedServing _ (CompletedFields actual _ _ _ _ _ _ _)) = actual
nativeCompletedExperiment :: NativeCompletedServing -> Text
nativeCompletedExperiment (NativeCompletedServing _ (CompletedFields _ actual _ _ _ _ _ _)) = actual
nativeCompletedTensorName :: NativeCompletedServing -> Text
nativeCompletedTensorName (NativeCompletedServing _ (CompletedFields _ _ actual _ _ _ _ _)) = actual
nativeCompletedStep :: NativeCompletedServing -> Word64
nativeCompletedStep (NativeCompletedServing _ (CompletedFields _ _ _ actual _ _ _ _)) = actual
nativeCompletedMetrics :: NativeCompletedServing -> [(Text, Double)]
nativeCompletedMetrics (NativeCompletedServing _ (CompletedFields _ _ _ _ actual _ _ _)) = actual
nativeCompletedWeights :: NativeCompletedServing -> [Double]
nativeCompletedWeights (NativeCompletedServing _ (CompletedFields _ _ _ _ _ actual _ _)) = actual
nativeCompletedHostTrace :: NativeCompletedServing -> Maybe Trace.ArsHostTrace
nativeCompletedHostTrace (NativeCompletedServing _ (CompletedFields _ _ _ _ _ _ actual _)) = actual
nativeCompletedInvocation :: NativeCompletedServing -> Maybe Training.ProductScenarioInvocation
nativeCompletedInvocation (NativeCompletedServing _ (CompletedFields _ _ _ _ _ _ _ actual)) = actual

-- No callback, supplied weights, completion or replacement invocation enters
-- this boundary. The binding comes from the SAME actual producer's context.
prepareNativeCompletedServing
  :: Candidate.NativeServingCandidate
  -> IO (Either NativeCompletedServingFailure NativeCompletedServing)
prepareNativeCompletedServing candidate = do
  attempted <- tryAny $ do
    result <- evaluate (buildCompleted candidate)
    case result of
      Left reason -> Left . NativeCompletionRefused <$> Failure.captureNativeDiagnostic reason
      Right fields@(CompletedFields completed experiment tensor step metrics weights host invocation) -> do
        _ <- evaluate (LBS.length (Weights.encodeJmw1 weights))
        _ <- evaluate (Text.length experiment + Text.length tensor)
        _ <- evaluate step
        mapM_ (\(name, value) -> evaluate (Text.length name) >> evaluate value >> pure ()) metrics
        _ <- evaluate (Training.completedTrainingUpdateCount completed)
        _ <- evaluate (Training.completedTrainingObservedUnits completed)
        case host of
          Nothing -> pure ()
          Just trace -> void (evaluate (Text.length (Trace.arsHostTraceSha256 trace)))
        case invocation of
          Nothing -> pure ()
          Just actual -> void (evaluate (Text.length (Training.productScenarioInvocationDigest actual)))
        pure (Right (NativeCompletedServing candidate fields))
  case attempted of
    Left exception -> Left . NativeCompletionSynchronousFailure <$> Failure.captureNativeExceptionDiagnostic exception
    Right result -> pure result

buildCompleted :: Candidate.NativeServingCandidate -> Either Text CompletedFields
buildCompleted candidate = do
  let produced =
        Replay.nativeEvaluationReplayedProducer
          (Assessment.nativeAssessmentReplay (Candidate.nativeServingCandidateAssessment candidate))
      references = Producer.nativeProducedReferences produced
      -- The cohort used below is the same private reference/child cohort that
      -- assessment already checked. No caller can provide a replacement plan.
      cohort = Reference.nativeCapturedReferenceCohort references
  case Cohort.nativeRlCohortPlanProjection cohort of
    Matrix.SomeProductProjection _ projection -> buildForProjection candidate produced cohort projection

buildForProjection
  :: Candidate.NativeServingCandidate
  -> Producer.NativeProducedCohort
  -> Cohort.NativeRlCohortPlan
  -> Matrix.ProductProjection kind
  -> Either Text CompletedFields
buildForProjection candidate produced cohort projection = do
  let experiment = Matrix.productProjectionExperimentHash projection
      served = Cohort.nativeRlCohortServingChild cohort
      singleton = Cohort.nativeRlSeedPlanSingleton served
      budget = Cohort.nativeRlSeedPlanTrainingBudget served
      planId = Singleton.nativeSingletonPlanId singleton
  require
    (Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex served) == 0)
    "native completion requires original serving index zero"
  require
    ( planId == Matrix.productProjectionPlanId projection
        && Singleton.nativeSingletonExperiment singleton == experiment
    )
    "native completion serving plan or experiment differs from its whole canonical projection"
  invocation <- actualInvocation produced projection
  case Candidate.nativeServingCandidateModel candidate of
    Candidate.NativeReturnServingCandidateData seed artifact host -> do
      require (seed == served) "native RETURN completion selected a different prescribed child"
      compiled <-
        maybe
          (Left "native RETURN completion has no compiled plan")
          Right
          (Cohort.nativeRlSeedPlanCompiledReturn seed)
      let trainer = RlBudget.compiledRlTrainerKind compiled
          environment = RlBudget.compiledRlEnvironment compiled
          counters = Trainer.trainedArtifactCounters artifact
          evaluation = Trainer.trainedArtifactEvaluationSet artifact
          step = Counters.measuredEnvironmentTransitionCount counters
          weights = Trainer.trainedArtifactWeights artifact
          evidence = Trainer.trainedArtifactEvidence artifact
          tensor = "rl-" <> Text.toLower trainer <> "-weights"
      metrics <- Completion.rlCompletionMetrics trainer counters evaluation
      completed <-
        maybe
          (Left (Completion.rlCompletedTrainingFailureMessage trainer environment metrics))
          Right
          ( Completion.rlCompletedTrainingWithBudget
              planId
              budget
              trainer
              environment
              experiment
              tensor
              step
              metrics
              evidence
          )
      bound <- bindActualInvocation invocation completed
      pure (CompletedFields bound experiment tensor step metrics weights host invocation)
    Candidate.NativeArenaServingCandidateData seed actual -> do
      require (seed == served) "native arena completion selected a different prescribed child"
      let returned = Arena.nativeAlphaZeroEvaluatedReturnedData actual
          raw = Arena.nativeAlphaZeroReturnedRawObservation returned
          snapshot = Arena.nativeAlphaZeroReturnedSnapshot returned
          finalEvaluation = Arena.nativeAlphaZeroEvaluatedFinalEvaluation actual
          generations = ArenaLow.alphaZeroObservedGenerationCount raw
          delta = ArenaLow.alphaZeroObservedOptimizerApplicationDelta raw
          samples = ArenaLow.alphaZeroObservedSamples raw
          initialWeights = Net.policyValueNetToFlat (ArenaLow.alphaZeroPreparedInitialNet snapshot)
          finalWeights = Net.policyValueNetToFlat (ArenaLow.alphaZeroObservedFinalNet raw)
          child = Arena.nativeAlphaZeroReturnedChild returned
          game = ArenaLow.alphaZeroPreparedGame snapshot
      Arena.validateNativeAlphaZeroReturnedData child snapshot raw
      require (not (null samples)) "native arena completion returned no self-play samples"
      generationCount <- positiveWord "actual completed arena generations" (toInteger generations)
      updateCount <- positiveWord "actual arena optimizer application delta" delta
      updatesPerGeneration <-
        Completion.checkedPositiveWord64FromInt
          "arena updates per generation"
          (ArenaLow.alphaZeroObservedUpdates raw)
      expectedUpdates <-
        Completion.checkedWord64Product
          "arena prescribed optimizer applications"
          generationCount
          updatesPerGeneration
      require
        (updateCount == expectedUpdates)
        "native arena actual optimizer applications differ from its complete prescribed schedule"
      score <-
        maybe
          (Left "native arena completion has no complete final score")
          Right
          (ArenaEvaluation.nativeArenaEvaluationScore finalEvaluation)
      let decisions =
            concatMap
              ArenaReference.nativeArenaEpisodeDecisions
              (ArenaEvaluation.nativeArenaEvaluationEpisodes finalEvaluation)
          legal =
            length
              [ ()
              | d <- decisions
              , ArenaReference.nativeArenaDecisionAction d `elem` ArenaReference.nativeArenaDecisionLegalActions d
              ]
      require
        (not (null decisions) && legal == length decisions)
        "native arena completion has absent or illegal actual final decisions"
      witness <- case Producer.nativeProducedChildren produced of
        first : _ -> case Producer.nativeChildDevice (Producer.nativeProducedChildData first) of
          Producer.NativeDeviceReturned (Just value) -> Right value
          _ -> Left "native arena completion has no actual serving-child device witness"
        [] -> Left "native arena completion has no actual serving child"
      let metrics =
            [ ("arena_win_rate", score)
            , ("legal_move_rate", fromIntegral legal / fromIntegral (length decisions))
            , ("mcts_simulations_per_move", fromIntegral (ArenaLow.alphaZeroObservedSimulations raw))
            , ("self_play_games", fromIntegral (ArenaLow.alphaZeroObservedGames raw))
            , ("self_play_generations", fromIntegral generations)
            , ("self_play_samples", fromIntegral (length samples))
            , ("optimizer_applications", fromIntegral updateCount)
            ]
      completed <-
        Completion.alphaZeroCompletedTraining
          planId
          budget
          experiment
          generationCount
          updateCount
          (Net.policyValueTrainingSamplesSha256 samples)
          metrics
          initialWeights
          finalWeights
          (Just witness)
      bound <- bindActualInvocation invocation completed
      pure
        ( CompletedFields
            bound
            experiment
            ("alphazero-" <> game <> "-policy-value-weights")
            generationCount
            metrics
            finalWeights
            Nothing
            invocation
        )

actualInvocation
  :: Producer.NativeProducedCohort
  -> Matrix.ProductProjection kind
  -> Either Text (Maybe Training.ProductScenarioInvocation)
actualInvocation produced projection = case Producer.nativeProducedAssociation produced of
  Context.DirectLocalContext acquisition -> do
    let sameDirect = case Retain.nativeAllocationContext scope of
          Retain.NativeDirectLocalAcquisition actual -> Context.digestFromCanonicalText actual == Right acquisition
          _ -> False
    require
      sameDirect
      "native completion direct context differs from the actual allocation scope"
    pure Nothing
  Context.SuppliedScenarioContext invocation -> do
    require
      ( Training.productScenarioInvocationRowId invocation == Matrix.productProjectionRowId projection
          && Training.productScenarioInvocationPlanId invocation == Matrix.productProjectionPlanId projection
          && Training.productScenarioInvocationSubstrate invocation
            == Matrix.productProjectionSubstrate projection
      )
      "native completion actual invocation differs from its exact projection"
    require
      ( Retain.nativeAllocationContext scope
          == Retain.NativeSuppliedScenarioDigest (Training.productScenarioInvocationDigest invocation)
          && Training.productScenarioInvocationExecutableSha256 invocation
            == Process.producerExecutableFileSha256 (Producer.nativeProducedBeforeProcess produced)
      )
      "native completion actual invocation differs from allocation or observed executable"
    pure (Just invocation)
 where
  scope = Producer.nativeProducedAcquisitionScope produced

bindActualInvocation
  :: Maybe Training.ProductScenarioInvocation
  -> Training.CompletedTraining
  -> Either Text Training.CompletedTraining
bindActualInvocation Nothing actual = Right actual
bindActualInvocation (Just invocation) actual = Training.bindCompletedTrainingToProductScenarioInvocation invocation actual

positiveWord :: Text -> Integer -> Either Text Word64
positiveWord label value = do
  require
    (value > 0 && value <= toInteger (maxBound :: Word64))
    (label <> " is outside positive Word64 scope")
  pure (fromInteger value)

require :: Bool -> Text -> Either Text ()
require condition detail = unless condition (Left detail)

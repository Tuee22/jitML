{-# LANGUAGE OverloadedStrings #-}

-- | Compare actual Store-admitted completion facts with the SAME original
-- serving child's independently decoded DATA. No CompletedTraining is decoded,
-- refined or constructed here. This grants no parent/authentication capability.
module JitML.Product.NativeParentCompletionData
  ( checkNativeParentCompletionData
  , NativeCompletionScalarData (..)
  , compareNativeCompletionScalarData
  ) where

import Control.Monad (unless)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentPolicyData qualified as Policy
import JitML.Checkpoint.NativeParentPolicyData.ArenaRaw qualified as ArenaRaw
import JitML.Checkpoint.NativePhase.Types (Resource (AggregateSequenceElements), boundedLength)
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weights
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Completion qualified as Completion
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as ArenaRef
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.NativeHerEvaluation qualified as Her
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef
import JitML.RL.ProductBudget qualified as Product
import JitML.RL.TrainerExecution qualified as Strict
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Training.Budget qualified as Training

-- Explicitly forgeable ordinary scalar DATA for comparison/mutation controls.
-- Equal records do NOT admit a checkpoint or create a completion/parent cap.
data NativeCompletionScalarData = NativeCompletionScalarData
  { completionDataPlan :: !Text
  , completionDataBudget :: !Training.RawTrainingBudget
  , completionDataObservedUnits :: !Word64
  , completionDataInitialWeightHash :: !Text
  , completionDataFinalWeightHash :: !Text
  , completionDataUpdateCount :: !Word64
  , completionDataDatasetHash :: !Text
  , completionDataCriteria :: ![Training.RawConvergenceObservation]
  , completionDataTensorBoard :: !Training.TensorBoardRunMetadata
  , completionDataInvocation :: !(Maybe Text)
  , completionDataCompiledPlan :: !(Maybe Text)
  , completionDataManifestStep :: !Word64
  , completionDataManifestMetrics :: ![(Text, Double)]
  }
  deriving stock (Show)

compareNativeCompletionScalarData
  :: NativeCompletionScalarData -> NativeCompletionScalarData -> Either Text ()
compareNativeCompletionScalarData expected actual = do
  mapM_ finiteData [expected, actual]
  require
    (completionDataPlan expected == completionDataPlan actual)
    "parent completion whole plan differs from serving child0"
  require
    (completionDataBudget expected == completionDataBudget actual)
    "parent completion full seeded budget differs from serving child0"
  require
    ( completionDataObservedUnits expected == completionDataObservedUnits actual
        && completionDataManifestStep expected == completionDataManifestStep actual
    )
    "parent completion observed units or manifest step differ from original child0 work"
  require
    ( completionDataInitialWeightHash expected == completionDataInitialWeightHash actual
        && completionDataFinalWeightHash expected == completionDataFinalWeightHash actual
    )
    "parent completion initial or final JMW1 identity differs from original child0"
  require
    (completionDataUpdateCount expected == completionDataUpdateCount actual)
    "parent completion optimizer count differs from original child0"
  require
    (completionDataDatasetHash expected == completionDataDatasetHash actual)
    "parent completion training-input evidence digest differs from original child0"
  require
    ( map criterionKey (completionDataCriteria expected)
        == map criterionKey (completionDataCriteria actual)
    )
    "parent completion exact criterion order rule threshold or measurement bits differ"
  require
    (completionDataTensorBoard expected == completionDataTensorBoard actual)
    "parent completion TensorBoard run prefix or scalar tags differ"
  require
    ( completionDataInvocation expected == completionDataInvocation actual
        && completionDataCompiledPlan expected == completionDataCompiledPlan actual
    )
    "parent completion original invocation or whole-versus-compiled binding differs"
  require
    ( metricKeys (completionDataManifestMetrics expected)
        == metricKeys (completionDataManifestMetrics actual)
    )
    "parent completion full manifest metric order names or binary64 values differ"
 where
  finiteData value = do
    _ <- bounded "completion criteria" (completionDataCriteria value)
    _ <- bounded "completion metrics" (completionDataManifestMetrics value)
    _ <- bounded "TensorBoard scalar tags" (Training.tbrScalarTags (completionDataTensorBoard value))
    require
      (not (null (completionDataCriteria value)) && not (null (completionDataManifestMetrics value)))
      "parent completion scalar DATA has an empty criterion or metric inventory"
    require
      ( all (finite . snd) (completionDataManifestMetrics value)
          && all finiteCriterion (completionDataCriteria value)
      )
      "parent completion scalar DATA is nonfinite"
  bounded name =
    either (const (Left ("parent " <> name <> " exceeds its closed16-field bound"))) Right
      . boundedLength AggregateSequenceElements 16

criterionKey
  :: Training.RawConvergenceObservation -> (Text, (Int, Maybe Word64, Maybe Word64), Word64, Word64)
criterionKey value =
  ( Training.rawCriterionName value
  , ruleKey (Training.rawCriterionRule value)
  , castDoubleToWord64 (Training.rawCriterionThreshold value)
  , castDoubleToWord64 (Training.rawMeasurementValue value)
  )
 where
  ruleKey Training.RawCriterionAtLeast = (0, Nothing, Nothing)
  ruleKey Training.RawCriterionAtMost = (1, Nothing, Nothing)
  ruleKey (Training.RawCriterionAtLeastExcluding centre distance) = (2, Just (castDoubleToWord64 centre), Just (castDoubleToWord64 distance))
finiteCriterion :: Training.RawConvergenceObservation -> Bool
finiteCriterion value =
  all
    finite
    ( [Training.rawCriterionThreshold value, Training.rawMeasurementValue value] <> case Training.rawCriterionRule value of
        Training.RawCriterionAtLeastExcluding centre distance -> [centre, distance]
        _ -> []
    )

-- Keep the tuple pattern demand before constructing each bit-exact metric pair.
{- HLINT ignore metricKeys "Use second" -}
metricKeys :: [(Text, Double)] -> [(Text, Word64)]
metricKeys = map (\(name, value) -> (name, castDoubleToWord64 value))

checkNativeParentCompletionData
  :: Policy.NativeParentPolicyData -> Store.AdmittedExecutionCheckpoint -> Either Text ()
checkNativeParentCompletionData policy admitted = do
  require
    (null (Policy.nativeParentPolicyFindings policy))
    "parent completion source policy retains learning findings"
  let binding = Policy.nativeParentPolicyBinding policy
      cohort = Binding.nativeParentBindingCohort binding
      metadata = Metadata.nativeQualificationReceiptFields (Binding.nativeParentBindingMetadata binding)
      served = Cohort.nativeRlCohortServingChild cohort
      singleton = Cohort.nativeRlSeedPlanSingleton served
      completed = Store.admittedExecutionCompletedTraining admitted
      manifest = Store.admittedCheckpointManifest (Store.admittedExecutionCheckpoint admitted)
      children = Policy.nativeParentPolicyChildren policy
  require
    (map childIndex children == [0 .. 4])
    "parent completion source requires all original five children"
  child <- case children of first : _ -> Right first; [] -> Left "parent completion serving child0 is absent"
  require
    ( childSeed child == Cohort.nativeRlSeedPlanSeed served
        && Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex served) == 0
    )
    "parent completion selected a different original serving seed"
  require
    (Training.encodeCompletedTraining completed == Metadata.nativeReceiptCompletedTrainingBytes metadata)
    "parent actual completion bytes differ from original metadata"
  require
    ( Format.manifestExperiment manifest == Singleton.nativeSingletonExperiment singleton
        && Format.manifestPlanId manifest == Just (Singleton.nativeSingletonPlanId singleton)
    )
    "parent completion manifest whole experiment or PlanId differs"
  manifestCompleted <-
    maybe
      (Left "parent completion manifest has no actual completed training")
      Right
      (Format.manifestCompletedTraining manifest)
  require
    (Training.encodeCompletedTraining manifestCompleted == Training.encodeCompletedTraining completed)
    "parent completion manifest and actual Store capability disagree"
  expected <- expectedData cohort metadata child
  require
    ( Format.manifestInitialWeightHash manifest == Just (completionDataInitialWeightHash expected)
        && Format.manifestFinalWeightHash manifest == Just (completionDataFinalWeightHash expected)
        && Format.manifestUpdateCount manifest == Just (completionDataUpdateCount expected)
        && Format.manifestDatasetShaAtRead manifest == Just (completionDataDatasetHash expected)
    )
    "parent manifest evidence duplicates differ from original child0"
  compareNativeCompletionScalarData expected (actualData manifest completed)
  compareProvenance child admitted completed

actualData :: Format.CheckpointManifest -> Training.CompletedTraining -> NativeCompletionScalarData
actualData manifest completed =
  NativeCompletionScalarData
    (Plan.planIdText (Training.completedTrainingPlanId completed))
    (Training.trainingBudgetToRaw (Training.completedTrainingBudget completed))
    (Training.completedTrainingObservedUnits completed)
    (Training.completedTrainingInitialWeightHash completed)
    (Training.completedTrainingFinalWeightHash completed)
    (Training.completedTrainingUpdateCount completed)
    (Training.completedTrainingDatasetShaAtRead completed)
    (map Training.convergenceObservationToRaw (Training.completedTrainingMetrics completed))
    (Training.completedTrainingTensorBoard completed)
    ( Training.renderProductScenarioInvocation
        <$> Training.completedTrainingProductScenarioInvocation completed
    )
    (Product.renderCompiledRlPlanTransport <$> Training.completedTrainingRlPlan completed)
    (Format.manifestStep manifest)
    (Format.manifestMetrics manifest)

expectedData
  :: Cohort.NativeRlCohortPlan
  -> Metadata.NativeQualificationReceiptFields
  -> Policy.NativeParentChildPolicyData
  -> Either Text NativeCompletionScalarData
expectedData cohort metadata child = do
  let served = Cohort.nativeRlCohortServingChild cohort
      singleton = Cohort.nativeRlSeedPlanSingleton served
      experiment = Singleton.nativeSingletonExperiment singleton
      build units updates initialHash finalHash dataset metrics criteria =
        NativeCompletionScalarData
          (Plan.planIdText (Singleton.nativeSingletonPlanId singleton))
          (Training.trainingBudgetToRaw (Cohort.nativeRlSeedPlanTrainingBudget served))
          units
          initialHash
          finalHash
          updates
          dataset
          (map Training.convergenceObservationToRaw criteria)
          ( Training.TensorBoardRunMetadata
              experiment
              ("jitml-tensorboard/" <> experiment)
              (map Training.coMetricName criteria)
          )
          ( case Metadata.nativeReceiptAssociation metadata of
              Metadata.NativeReceiptDirectData _ -> Nothing
              Metadata.NativeReceiptScenarioData text -> Just text
          )
          -- Addressed manifests use Format.canonicalManifest's name ordering.
          -- Criteria/TensorBoard above retain the original semantic order.
          Nothing
          units
          (sortOn fst metrics)
      -- Canonical native completion uses the WHOLE singleton PlanId. Never
      -- bind its distinct compiled recipe ID through the legacy V3 constructor.
      rl returned evaluation = do
        compiled <-
          maybe
            (Left "parent completion source compiled recipe is absent")
            Right
            (Cohort.nativeRlSeedPlanCompiledReturn served)
        let lane = Singleton.nativeSingletonSubstrate singleton
        _ <-
          Observation.refineBudgetCompleteTrainerObservation
            (Observation.RawTrainerObservation compiled returned evaluation)
        trained <-
          Strict.refineStrictRecordedTrainerObservation
            lane
            (Observation.TrainerReturned (Observation.RawTrainerObservation compiled returned evaluation))
        artifact <- case trained of
          Strict.Trained actual -> Right actual
          Strict.EvaluationOnly _ -> Left "parent original child0 strict result is evaluation-only"
        let counters = Strict.trainedArtifactCounters artifact
            evidence = Strict.trainedArtifactEvidence artifact
            trainer = Product.compiledRlTrainerKind compiled
        metrics <-
          Completion.rlCompletionMetrics trainer counters (Strict.trainedArtifactEvaluationSet artifact)
        criteria <-
          Completion.rlConvergenceObservations trainer (Product.compiledRlEnvironment compiled) metrics
        pure
          ( build
              (Common.measuredEnvironmentTransitionCount counters)
              (Evidence.evidenceUpdateCount evidence)
              (Evidence.evidenceInitialWeightHash evidence)
              (Evidence.evidenceFinalWeightHash evidence)
              (Evidence.evidenceDatasetShaAtRead evidence)
              metrics
              criteria
          )
  case child of
    Policy.NativeParentReturnChild _ _ _ final returned _ _ -> rl returned (returnEvaluation final)
    Policy.NativeParentHerChild _ _ _ final returned _ ->
      rl
        returned
        ( Observation.HerEvaluationReturned
            [ ( HerRef.nativeHerOutcomeSuccess value
              , HerRef.nativeHerOutcomeNormalizedDistance value
              , HerRef.nativeHerOutcomeSteps value
              )
            | value <- Her.nativeHerEvaluationOutcomes final
            ]
        )
    Policy.NativeParentArenaChild _ _ _ final raw _ -> do
      generations <-
        positive
          "parent actual arena generations"
          (toInteger (ArenaRaw.nativeParentArenaGenerationCount raw))
      updates <-
        positive
          "parent actual arena optimizer delta"
          ( toInteger (Mlp.adamStep_ (ArenaRaw.nativeParentArenaFinalAdam raw))
              - toInteger (Mlp.adamStep_ (ArenaRaw.nativeParentArenaInitialAdam raw))
          )
      perGeneration <-
        Completion.checkedPositiveWord64FromInt
          "parent arena prescribed updates"
          (ArenaRaw.nativeParentArenaUpdates raw)
      expectedUpdates <-
        Completion.checkedWord64Product "parent arena prescribed applications" generations perGeneration
      require
        (updates == expectedUpdates)
        "parent actual arena optimizer applications differ from prescribed schedule"
      let samples = ArenaRaw.nativeParentArenaSamples raw
          initial = Net.policyValueNetToFlat (ArenaRaw.nativeParentArenaInitialPolicy raw)
          finalWeights = Net.policyValueNetToFlat (ArenaRaw.nativeParentArenaFinalPolicy raw)
          decisions = concatMap ArenaRef.nativeArenaEpisodeDecisions (Arena.nativeArenaEvaluationEpisodes final)
          legal =
            length
              [ ()
              | value <- decisions
              , ArenaRef.nativeArenaDecisionAction value `elem` ArenaRef.nativeArenaDecisionLegalActions value
              ]
      require
        (not (null samples) && not (null decisions) && legal == length decisions)
        "parent arena completion samples or legal decisions are absent"
      score <-
        maybe
          (Left "parent arena final evaluation score is absent")
          Right
          (Arena.nativeArenaEvaluationScore final)
      -- Exact df05 completion metric order/operations; training math is not run.
      let metrics =
            [ ("arena_win_rate", score)
            , ("legal_move_rate", fromIntegral legal / fromIntegral (length decisions))
            , ("mcts_simulations_per_move", fromIntegral (ArenaRaw.nativeParentArenaSimulations raw))
            , ("self_play_games", fromIntegral (ArenaRaw.nativeParentArenaGames raw))
            , ("self_play_generations", fromIntegral generations)
            , ("self_play_samples", fromIntegral (length samples))
            , ("optimizer_applications", fromIntegral updates)
            ]
      criteria <- Completion.alphaZeroConvergenceObservations metrics
      pure
        ( build
            generations
            updates
            (weightHash initial)
            (weightHash finalWeights)
            (Net.policyValueTrainingSamplesSha256 samples)
            metrics
            criteria
        )

compareProvenance
  :: Policy.NativeParentChildPolicyData
  -> Store.AdmittedExecutionCheckpoint
  -> Training.CompletedTraining
  -> Either Text ()
compareProvenance child admitted completed = do
  actual <- Training.completedTrainingExecutionProvenance completed
  case (childDevice child, Store.admittedExecutionProvenance admitted, actual) of
    ( Policy.NativeHostNoMlpData
      , ArsHostLinearExecution physical
      , Just (ArsHostLinearExecution recorded)
      ) ->
        require
          (recorded == Store.admittedArsHostReference physical)
          "parent completion ARS reference differs from actual physical host admission"
    ( Policy.NativeRecordedDeviceData expected
      , NeuralDeviceExecution physical
      , Just (NeuralDeviceExecution recorded)
      ) ->
        require
          ( Witness.deviceExecutionWitnessToRaw physical == expected
              && Witness.deviceExecutionWitnessToRaw recorded == expected
          )
          "parent completion or physical neural witness differs from original serving child0"
    _ -> Left "parent completion execution provenance differs from original serving family"

childIndex :: Policy.NativeParentChildPolicyData -> Int
childIndex value = case value of
  Policy.NativeParentReturnChild index _ _ _ _ _ _ -> index
  Policy.NativeParentHerChild index _ _ _ _ _ -> index
  Policy.NativeParentArenaChild index _ _ _ _ _ -> index
childSeed :: Policy.NativeParentChildPolicyData -> Word64
childSeed value = case value of
  Policy.NativeParentReturnChild _ seed _ _ _ _ _ -> seed
  Policy.NativeParentHerChild _ seed _ _ _ _ -> seed
  Policy.NativeParentArenaChild _ seed _ _ _ _ -> seed
childDevice :: Policy.NativeParentChildPolicyData -> Policy.NativeDeviceObservationData
childDevice value = case value of
  Policy.NativeParentReturnChild _ _ _ _ _ device _ -> device
  Policy.NativeParentHerChild _ _ _ _ _ device -> device
  Policy.NativeParentArenaChild _ _ _ _ _ device -> device
returnEvaluation :: Return.RawNativeReturnEvaluation -> Observation.RawEvaluation
returnEvaluation value =
  Observation.EvaluationReturned
    [ Episode.SimulatedEpisode
        (ReturnRef.nativeReturnEpisodeId e)
        (ReturnRef.nativeReturnEpisodeSteps e)
        (ReturnRef.nativeReturnEpisodeReward e)
        (ReturnRef.nativeReturnEpisodeTerminated e)
        []
    | e <- Return.nativeEvaluationEpisodes value
    ]
weightHash :: [Double] -> Text
weightHash = Weights.jmw1ContentSha . Weights.encodeJmw1
positive :: Text -> Integer -> Either Text Word64
positive label value = do
  require
    (value > 0 && value <= toInteger (maxBound :: Word64))
    (label <> " exceeds positive Word64 scope")
  pure (fromInteger value)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

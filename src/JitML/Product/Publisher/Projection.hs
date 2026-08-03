{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Projection
  ( ProjectedRlExecution (..)
  , checkedPositiveWord64FromInt
  , checkedWord64Product
  , intPlanValue
  , productTrainingBudgetForProjection
  , projectedRlExecution
  , projectedRunSeed
  , requireProjectedValue
  , validateProjectionRowAssociation
  , validateTuningProductExperiment
  )
where

import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError)
import JitML.Env.Env (App)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Plan.Plan
  ( RunKind (..)
  , RunPlan
  , quantityValue
  , runPlanExperimentId
  , runPlanId
  , runPlanRlBudget
  , runPlanSeeds
  , runPlanSubstrate
  , seedCohortValues
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.Substrate (Substrate)
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

validateProjectionRowAssociation
  :: ProductMatrix.ProductRow state
  -> ProductMatrix.ProductProjection kind
  -> Either Text ()
validateProjectionRowAssociation row projection = do
  requireProjectedValue
    "ProductRow id"
    (ProductMatrix.rowId row)
    (ProductMatrix.productProjectionRowId projection)
  requireProjectedValue
    "ProductRow experiment config"
    (ProductMatrix.experimentConfig row)
    (ProductMatrix.productProjectionExperimentConfig projection)
  requireProjectedValue
    "ProductRow experiment hash"
    (ProductMatrix.productRowExperimentHash row)
    (ProductMatrix.productProjectionExperimentHash projection)
  requireProjectedValue
    "ProductRow training budget"
    (ProductMatrix.trainingBudget row)
    (ProductMatrix.productProjectionTrainingBudget projection)
  let runPlan = ProductMatrix.productProjectionRunPlan projection
  requireProjectedValue
    "projected substrate"
    (ProductMatrix.productProjectionSubstrate projection)
    (runPlanSubstrate runPlan)
  requireProjectedValue
    "projected experiment hash"
    (ProductMatrix.productProjectionExperimentHash projection)
    (runPlanExperimentId runPlan)
{-# NOINLINE validateProjectionRowAssociation #-}

requireProjectedValue :: (Eq value, Show value) => Text -> value -> value -> Either Text ()
requireProjectedValue label expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( label
            <> " mismatch: projected "
            <> Text.pack (show expected)
            <> ", resolved "
            <> Text.pack (show actual)
        )
{-# NOINLINE requireProjectedValue #-}

projectedRunSeed :: RunPlan kind -> Word64
projectedRunSeed = NonEmpty.head . seedCohortValues . runPlanSeeds

productTrainingBudgetForProjection
  :: ProductMatrix.ProductProjection kind
  -> TrainingBudget.BudgetKind
  -> Word64
  -> Word64
  -> Either Text TrainingBudget.TrainingBudget
productTrainingBudgetForProjection projection kind target seed = do
  let budget = ProductMatrix.productProjectionTrainingBudget projection
  requireProjectedValue "ProductRow resolved budget kind" kind (TrainingBudget.tbKind budget)
  requireProjectedValue
    "ProductRow resolved budget target"
    target
    (TrainingBudget.tbTargetUnits budget)
  case TrainingBudget.tbSeed budget of
    Nothing -> Right ()
    Just declaredSeed ->
      requireProjectedValue "ProductRow resolved budget seed" declaredSeed seed
  Right budget
{-# NOINLINE productTrainingBudgetForProjection #-}

data ProjectedRlExecution = ProjectedRlExecution
  { projectedRlTrainerKind :: !Text
  , projectedRlEnvironment :: !Text
  , projectedRlSubstrate :: !Substrate
  , projectedRlSeed :: !Int
  , projectedRlPlan :: !ProductBudget.CompiledRlPlan
  , projectedRlTrainingBudget :: !TrainingBudget.TrainingBudget
  }
  deriving stock (Eq, Show)

projectedRlExecution
  :: ProductMatrix.ProductRow state
  -> ProductMatrix.ProductProjection 'ReinforcementLearning
  -> ProductMatrix.ProductPlanDescriptor 'ReinforcementLearning
  -> RunPlan 'ReinforcementLearning
  -> Either Text ProjectedRlExecution
projectedRlExecution row projection descriptor runPlan =
  case descriptor of
    ProductMatrix.RlProductDescriptor
      algorithm
      environment
      descriptorRollout
      descriptorVectors
      descriptorEpisode
      descriptorEvaluation -> do
        validateProjectionRowAssociation row projection
        requireProjectedValue
          "RL PlanId"
          (ProductMatrix.productProjectionPlanId projection)
          (runPlanId runPlan)
        let ( transitionsQuantity
              , rolloutQuantity
              , vectorQuantity
              , episodeQuantity
              , evaluationQuantity
              ) =
                runPlanRlBudget runPlan
            transitions = quantityValue transitionsQuantity
            rolloutTicks = quantityValue rolloutQuantity
            vectorEnvironmentsWord = quantityValue vectorQuantity
            episodeStepsWord = quantityValue episodeQuantity
            evaluationEpisodesWord = quantityValue evaluationQuantity
            seedWord = projectedRunSeed runPlan
            trainerKind = ProductBudget.trainerKindForAlgorithm algorithm
        requireProjectedValue "RL rollout ticks per environment" descriptorRollout rolloutTicks
        requireProjectedValue "RL vector environments" descriptorVectors vectorEnvironmentsWord
        requireProjectedValue "RL episode steps" descriptorEpisode episodeStepsWord
        requireProjectedValue "RL evaluation episodes" descriptorEvaluation evaluationEpisodesWord
        vectorEnvironments <- word64ToIntEither "RL vector environments" vectorEnvironmentsWord
        episodeSteps <- word64ToIntEither "RL episode steps" episodeStepsWord
        evaluationEpisodes <- word64ToIntEither "RL evaluation episodes" evaluationEpisodesWord
        seed <- word64ToIntEither "RL seed" seedWord
        budget <-
          productTrainingBudgetForProjection
            projection
            TrainingBudget.RlEnvironmentStepBudget
            transitions
            seedWord
        -- Phase 251 — compile the exact-target plan once; the schedule the
        -- descriptor is cross-checked against is the plan's own derived
        -- schedule, and the same plan is what the worker executes. The
        -- training episode-budget floor is the canonical training constant, so
        -- the evaluation episode count only feeds the plan's EvaluationPlan.
        plan <-
          ProductBudget.compileRlPlan
            ProductBudget.TrainingPlan
              { ProductBudget.trainingPlanTrainerKind = trainerKind
              , ProductBudget.trainingPlanEnvironment = environment
              , ProductBudget.trainingPlanSeed = seed
              , ProductBudget.trainingPlanMaxEpisodeSteps = episodeSteps
              , ProductBudget.trainingPlanEpisodeBudgetFloor =
                  ProductBudget.productRlDefaultTrainingEpisodeFloor
              , ProductBudget.trainingPlanVectorEnvironments = Just vectorEnvironments
              , ProductBudget.trainingPlanRequestedTransitionFloor = Just transitions
              , ProductBudget.trainingPlanExactTransitionTarget = Just transitions
              }
            (ProductBudget.EvaluationPlan evaluationEpisodes)
        schedule <-
          maybe
            (Left "projected RL plan is missing a training schedule")
            Right
            (ProductBudget.compiledRlSchedule plan)
        validateProjectedRlSchedule
          rolloutTicks
          vectorEnvironmentsWord
          episodeStepsWord
          schedule
        Right
          ProjectedRlExecution
            { projectedRlTrainerKind = trainerKind
            , projectedRlEnvironment = environment
            , projectedRlSubstrate = runPlanSubstrate runPlan
            , projectedRlSeed = seed
            , projectedRlPlan = plan
            , projectedRlTrainingBudget = budget
            }
{-# NOINLINE projectedRlExecution #-}

validateProjectedRlSchedule
  :: Word64
  -> Word64
  -> Word64
  -> ProductBudget.RlTrainingSchedule
  -> Either Text ()
validateProjectedRlSchedule rolloutTicks vectorEnvironments episodeSteps schedule =
  case schedule of
    ProductBudget.OnPolicyTrainingSchedule {} -> do
      requireProjectedValue
        "RL scheduled rollout ticks"
        rolloutTicks
        (fromIntegral (ProductBudget.scheduleOnPolicyRolloutSteps schedule))
      requireProjectedValue
        "RL scheduled vector environments"
        vectorEnvironments
        (fromIntegral (ProductBudget.scheduleOnPolicyVectorEnvironments schedule))
      requireProjectedValue
        "RL scheduled episode steps"
        episodeSteps
        (fromIntegral (ProductBudget.scheduleOnPolicyMaxEpisodeSteps schedule))
    ProductBudget.FixedStepTrainingSchedule {} -> do
      requireProjectedValue "RL scheduled rollout ticks" rolloutTicks 1
      requireProjectedValue "RL scheduled vector environments" vectorEnvironments 1
      requireProjectedValue
        "RL scheduled episode steps"
        episodeSteps
        (fromIntegral (ProductBudget.scheduleFixedMaxEpisodeSteps schedule))
    ProductBudget.ArsTrainingSchedule {} -> do
      requireProjectedValue
        "RL scheduled rollout ticks"
        rolloutTicks
        (fromIntegral (ProductBudget.scheduleArsMaxEpisodeSteps schedule))
      requireProjectedValue "RL scheduled vector environments" vectorEnvironments 1
      requireProjectedValue
        "RL scheduled episode steps"
        episodeSteps
        (fromIntegral (ProductBudget.scheduleArsMaxEpisodeSteps schedule))
    ProductBudget.HerTrainingSchedule {} -> do
      requireProjectedValue
        "RL scheduled rollout ticks"
        rolloutTicks
        (fromIntegral (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule))
      requireProjectedValue "RL scheduled vector environments" vectorEnvironments 1
      requireProjectedValue
        "RL scheduled episode steps"
        episodeSteps
        (fromIntegral (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule))

validateTuningProductExperiment
  :: WorkloadPlan.TuningPlan
  -> Word64
  -> ProductExperiment.ProductExperiment
  -> Either Text Tune.TuningExperiment
validateTuningProductExperiment plan seed productExperiment = do
  experiment <-
    case productExperiment of
      ProductExperiment.ProductTuningExperiment tuning -> Right tuning
      _ -> Left "projected tuning row loaded a non-tuning experiment config"
  decodedSpec <- Tune.tuningExecutionSpecForExperiment experiment
  requireProjectedValue
    "tuning experiment seed"
    seed
    (fromIntegral (Tune.tuningExperimentSeed experiment))
  requireProjectedValue
    "complete tuning execution spec"
    (WorkloadPlan.tuningPlanExecutionSpec plan)
    decodedSpec
  Right experiment
{-# NOINLINE validateTuningProductExperiment #-}

word64ToIntEither :: Text -> Word64 -> Either Text Int
word64ToIntEither label value
  | toInteger value > toInteger (maxBound :: Int) =
      Left (label <> " exceeds the platform Int range")
  | otherwise = Right (fromIntegral value)

intPlanValue :: Text -> Word64 -> App Int
intPlanValue label value =
  case word64ToIntEither label value of
    Left err -> exitWithError (InvalidConfig err)
    Right result -> pure result

checkedWord64Product :: Text -> Word64 -> Word64 -> Either Text Word64
checkedWord64Product label left right
  | left == 0 || right == 0 = Left (label <> " factors must be positive")
  | left > maxBound `div` right = Left (label <> " exceeds the Word64 range")
  | otherwise = Right (left * right)

checkedPositiveWord64FromInt :: Text -> Int -> Either Text Word64
checkedPositiveWord64FromInt label value
  | value <= 0 = Left (label <> " must be positive")
  | toInteger value > toInteger (maxBound :: Word64) = Left (label <> " exceeds the Word64 range")
  | otherwise = Right (fromIntegral value)

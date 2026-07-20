{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Workload-specific resolved plans for supervised training,
-- hyperparameter tuning, and AlphaZero.
--
-- External command, Dhall, and mounted-worker values stay in the exported raw
-- records.  The resolved constructors are private and can be obtained only by
-- accumulated semantic refinement or by parsing the versioned transport text,
-- which re-runs that same refinement and verifies the declared 'PlanId'.
module JitML.Plan.Workload
  ( AlphaZeroGame (..)
  , AlphaZeroPlan
  , Pruner (..)
  , RawAlphaZeroPlan (..)
  , RawSupervisedPlan (..)
  , RawTuningPlan (..)
  , Sampler (..)
  , Scheduler (..)
  , SupervisedPlan
  , TuningPlan
  , WorkloadPlanError (..)
  , alphaZeroPlanArenaGames
  , alphaZeroPlanGame
  , alphaZeroPlanGenerations
  , alphaZeroPlanId
  , alphaZeroPlanMaxPlies
  , alphaZeroPlanMctsSimulations
  , alphaZeroPlanRunPlan
  , alphaZeroPlanSelfPlayGames
  , alphaZeroPlanUpdates
  , parseAlphaZeroPlanTransport
  , parseSupervisedPlanTransport
  , parseTuningPlanTransport
  , renderAlphaZeroGame
  , renderAlphaZeroPlanTransport
  , renderSupervisedPlanTransport
  , renderTuningPlanTransport
  , resolveAlphaZeroPlan
  , resolveSupervisedPlan
  , resolveTuningPlan
  , resolveTuningPlanWithExecutionSpec
  , supervisedPlanBatchExamples
  , supervisedPlanEpochs
  , supervisedPlanEvaluationExamples
  , supervisedPlanId
  , supervisedPlanOptimizerUpdates
  , supervisedPlanRunPlan
  , supervisedPlanTrainingExamples
  , tuningPlanId
  , tuningPlanExecutionSpec
  , tuningPlanMaxPerTrialUpdates
  , tuningPlanParallelism
  , tuningPlanPerTrialUpdates
  , tuningPlanPromotions
  , tuningPlanPruner
  , tuningPlanRunPlan
  , tuningPlanSampler
  , tuningPlanScheduler
  , tuningPlanTrials
  )
where

import Control.Applicative ((<|>))
import Data.ByteString qualified as ByteString
import Data.Char (digitToInt, intToDigit, isHexDigit)
import Data.Either.Combinators (rightToMaybe)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import Numeric.Natural (Natural)
import Text.Read (readMaybe)

import JitML.Plan.Plan
  ( PlanError
  , PlanId
  , Quantity
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKind (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , RunPlan
  , Unit (..)
  , Validation (..)
  , planIdFromCanonicalText
  , planIdText
  , quantityValue
  , resolveRun
  , runPlanAlphaZeroBudget
  , runPlanArtifactId
  , runPlanExperimentId
  , runPlanId
  , runPlanPlacement
  , runPlanSeeds
  , runPlanSubjectId
  , runPlanSubstrate
  , runPlanSupervisedBudget
  , runPlanTopicId
  , runPlanTuningBudget
  , runPlanVersion
  , seedCohortValues
  )
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as Canonicals
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Tune.Catalog
  ( Pruner (..)
  , Sampler (..)
  , Scheduler (..)
  , TuningExecutionSpec (..)
  , legacyTuningExecutionSpec
  , parseTuningExecutionSpec
  , prunerCatalog
  , prunerFromText
  , renderTuningExecutionSpec
  , samplerCatalog
  , samplerFromText
  , schedulerCatalog
  , schedulerFromText
  , tuningPrunerKind
  , tuningSamplerKind
  , tuningSamplerSeed
  , tuningSchedulerEta
  , tuningSchedulerKind
  , tuningSchedulerMaxBudget
  , tuningSchedulerParallelism
  , validateTuningExecutionSpec
  )

-- | Raw supervised semantics from a command boundary.  The wrapper keeps the
-- workload transport parallel with tuning and AlphaZero while the common run
-- request owns all supervised dimensions.
newtype RawSupervisedPlan = RawSupervisedPlan
  { rawSupervisedRun :: RawRunRequest 'SupervisedTraining
  }
  deriving stock (Eq, Show)

-- | A fully refined supervised plan.  Its constructor is private; workers can
-- obtain one only by resolving raw command values or by parsing and
-- re-refining the canonical versioned transport.
data SupervisedPlan = SupervisedPlan
  { internalSupervisedPlanRunPlan :: RunPlan 'SupervisedTraining
  , internalSupervisedPlanId :: PlanId
  }
  deriving stock (Eq, Show)

supervisedPlanRunPlan :: SupervisedPlan -> RunPlan 'SupervisedTraining
supervisedPlanRunPlan = internalSupervisedPlanRunPlan

supervisedPlanId :: SupervisedPlan -> PlanId
supervisedPlanId = internalSupervisedPlanId

supervisedPlanEpochs :: SupervisedPlan -> Quantity 'Epoch
supervisedPlanEpochs plan =
  let (epochs, _, _, _, _) = runPlanSupervisedBudget (supervisedPlanRunPlan plan)
   in epochs

supervisedPlanTrainingExamples :: SupervisedPlan -> Quantity 'TrainingExample
supervisedPlanTrainingExamples plan =
  let (_, examples, _, _, _) = runPlanSupervisedBudget (supervisedPlanRunPlan plan)
   in examples

supervisedPlanEvaluationExamples :: SupervisedPlan -> Quantity 'EvaluationExample
supervisedPlanEvaluationExamples plan =
  let (_, _, examples, _, _) = runPlanSupervisedBudget (supervisedPlanRunPlan plan)
   in examples

supervisedPlanBatchExamples :: SupervisedPlan -> Quantity 'BatchExample
supervisedPlanBatchExamples plan =
  let (_, _, _, examples, _) = runPlanSupervisedBudget (supervisedPlanRunPlan plan)
   in examples

supervisedPlanOptimizerUpdates :: SupervisedPlan -> Quantity 'OptimizerUpdate
supervisedPlanOptimizerUpdates plan =
  let (_, _, _, _, updates) = runPlanSupervisedBudget (supervisedPlanRunPlan plan)
   in updates

resolveSupervisedPlan
  :: RawSupervisedPlan
  -> Validation (NonEmpty WorkloadPlanError) SupervisedPlan
resolveSupervisedPlan raw =
  flattenValidation $
    assemble
      <$> mapValidationErrors CommonRunPlanError (resolveRun (rawSupervisedRun raw))
 where
  assemble runPlan =
    SupervisedPlan runPlan
      <$> workloadPlanId
        "jitml-supervised-plan-v1"
        (runPlanId runPlan)
        []

-- | Raw tuning axes surround the common raw run request.  Axis text stays raw
-- until 'resolveTuningPlan' selects a constructor from the closed catalogs.
data RawTuningPlan = RawTuningPlan
  { rawTuningRun :: RawRunRequest 'HyperparameterTuning
  , rawTuningSampler :: Text
  , rawTuningScheduler :: Text
  , rawTuningPruner :: Text
  }
  deriving stock (Eq, Show)

-- | A fully refined tuning plan.  Its identity covers the common run plan and
-- all three closed axes; operational endpoints deliberately live outside it.
data TuningPlan = TuningPlan
  { internalTuningPlanRunPlan :: RunPlan 'HyperparameterTuning
  , internalTuningPlanSampler :: Sampler
  , internalTuningPlanScheduler :: Scheduler
  , internalTuningPlanPruner :: Pruner
  , internalTuningPlanExecutionSpec :: TuningExecutionSpec
  , internalTuningPlanId :: PlanId
  }
  deriving stock (Eq, Show)

tuningPlanRunPlan :: TuningPlan -> RunPlan 'HyperparameterTuning
tuningPlanRunPlan = internalTuningPlanRunPlan

tuningPlanSampler :: TuningPlan -> Sampler
tuningPlanSampler = internalTuningPlanSampler

tuningPlanScheduler :: TuningPlan -> Scheduler
tuningPlanScheduler = internalTuningPlanScheduler

tuningPlanPruner :: TuningPlan -> Pruner
tuningPlanPruner = internalTuningPlanPruner

tuningPlanExecutionSpec :: TuningPlan -> TuningExecutionSpec
tuningPlanExecutionSpec = internalTuningPlanExecutionSpec

tuningPlanId :: TuningPlan -> PlanId
tuningPlanId = internalTuningPlanId

tuningPlanTrials :: TuningPlan -> Quantity 'Trial
tuningPlanTrials plan =
  let (trials, _, _, _) = runPlanTuningBudget (tuningPlanRunPlan plan)
   in trials

tuningPlanParallelism :: TuningPlan -> Quantity 'ParallelTrial
tuningPlanParallelism plan =
  let (_, parallelism, _, _) = runPlanTuningBudget (tuningPlanRunPlan plan)
   in parallelism

tuningPlanPromotions :: TuningPlan -> Quantity 'Promotion
tuningPlanPromotions plan =
  let (_, _, promotions, _) = runPlanTuningBudget (tuningPlanRunPlan plan)
   in promotions

tuningPlanPerTrialUpdates :: TuningPlan -> Quantity 'PerTrialOptimizerUpdate
tuningPlanPerTrialUpdates = tuningPlanMaxPerTrialUpdates

-- | Per-trial optimizer-update ceiling.  Early scheduler/pruner termination
-- may produce a lower observed update count for an individual trial.
tuningPlanMaxPerTrialUpdates :: TuningPlan -> Quantity 'PerTrialOptimizerUpdate
tuningPlanMaxPerTrialUpdates plan =
  let (_, _, _, updates) = runPlanTuningBudget (tuningPlanRunPlan plan)
   in updates

data AlphaZeroGame
  = Connect4
  | Othello
  | Hex
  | Gomoku
  deriving stock (Eq, Ord, Show)

renderAlphaZeroGame :: AlphaZeroGame -> Text
renderAlphaZeroGame Connect4 = "connect4"
renderAlphaZeroGame Othello = "othello"
renderAlphaZeroGame Hex = "hex"
renderAlphaZeroGame Gomoku = "gomoku"

data RawAlphaZeroPlan = RawAlphaZeroPlan
  { rawAlphaZeroRun :: RawRunRequest 'AlphaZeroSelfPlay
  , rawAlphaZeroGame :: Text
  }
  deriving stock (Eq, Show)

data AlphaZeroPlan = AlphaZeroPlan
  { internalAlphaZeroPlanRunPlan :: RunPlan 'AlphaZeroSelfPlay
  , internalAlphaZeroPlanGame :: AlphaZeroGame
  , internalAlphaZeroPlanId :: PlanId
  }
  deriving stock (Eq, Show)

alphaZeroPlanRunPlan :: AlphaZeroPlan -> RunPlan 'AlphaZeroSelfPlay
alphaZeroPlanRunPlan = internalAlphaZeroPlanRunPlan

alphaZeroPlanGame :: AlphaZeroPlan -> AlphaZeroGame
alphaZeroPlanGame = internalAlphaZeroPlanGame

alphaZeroPlanId :: AlphaZeroPlan -> PlanId
alphaZeroPlanId = internalAlphaZeroPlanId

alphaZeroPlanGenerations :: AlphaZeroPlan -> Quantity 'Generation
alphaZeroPlanGenerations plan =
  let (generations, _, _, _, _, _) = runPlanAlphaZeroBudget (alphaZeroPlanRunPlan plan)
   in generations

alphaZeroPlanSelfPlayGames :: AlphaZeroPlan -> Quantity 'SelfPlayGame
alphaZeroPlanSelfPlayGames plan =
  let (_, games, _, _, _, _) = runPlanAlphaZeroBudget (alphaZeroPlanRunPlan plan)
   in games

alphaZeroPlanMctsSimulations :: AlphaZeroPlan -> Quantity 'MctsSimulationPerMove
alphaZeroPlanMctsSimulations plan =
  let (_, _, simulations, _, _, _) = runPlanAlphaZeroBudget (alphaZeroPlanRunPlan plan)
   in simulations

alphaZeroPlanMaxPlies :: AlphaZeroPlan -> Quantity 'AlphaZeroPly
alphaZeroPlanMaxPlies plan =
  let (_, _, _, maxPlies, _, _) = runPlanAlphaZeroBudget (alphaZeroPlanRunPlan plan)
   in maxPlies

alphaZeroPlanUpdates :: AlphaZeroPlan -> Quantity 'AlphaZeroOptimizerUpdate
alphaZeroPlanUpdates plan =
  let (_, _, _, _, updates, _) = runPlanAlphaZeroBudget (alphaZeroPlanRunPlan plan)
   in updates

alphaZeroPlanArenaGames :: AlphaZeroPlan -> Quantity 'ArenaGame
alphaZeroPlanArenaGames plan =
  let (_, _, _, _, _, arenaGames) = runPlanAlphaZeroBudget (alphaZeroPlanRunPlan plan)
   in arenaGames

data WorkloadPlanError
  = CommonRunPlanError PlanError
  | UnknownTuningSampler Text
  | UnknownTuningScheduler Text
  | UnknownTuningPruner Text
  | InvalidTuningExecutionSpec Text
  | UnknownAlphaZeroGame Text
  | InvalidTransportLine Int Text
  | DuplicateTransportField Text
  | UnknownTransportField Text
  | MissingTransportField Text
  | InvalidTransportValue Text Text
  | UnsupportedTransportVersion Word64
  | TransportKindMismatch Text Text
  | TransportPlanIdMismatch Text Text
  deriving stock (Eq, Ord, Show)

resolveTuningPlan
  :: RawTuningPlan
  -> Validation (NonEmpty WorkloadPlanError) TuningPlan
resolveTuningPlan raw =
  flattenValidation $
    assemble
      <$> mapValidationErrors CommonRunPlanError (resolveRun (rawTuningRun raw))
      <*> validateSampler (rawTuningSampler raw)
      <*> validateScheduler (rawTuningScheduler raw)
      <*> validatePruner (rawTuningPruner raw)
 where
  assemble runPlan sampler scheduler pruner =
    let (trials, parallelism, _, updates) = runPlanTuningBudget runPlan
        runSeed = fromIntegral (NonEmpty.head (seedCohortValues (runPlanSeeds runPlan)))
        spec =
          legacyTuningExecutionSpec
            sampler
            scheduler
            pruner
            runSeed
            (fromIntegral (quantityValue trials))
            (fromIntegral (quantityValue parallelism))
            (fromIntegral (quantityValue updates))
     in assembleTuningPlan runPlan sampler scheduler pruner spec

-- | Refine a tuning request with its complete normalized execution spec.
-- ProductRow/Dhall callers use this boundary so all semantics that can change
-- execution are validated against the common run budget and bound into PlanId.
resolveTuningPlanWithExecutionSpec
  :: TuningExecutionSpec
  -> RawTuningPlan
  -> Validation (NonEmpty WorkloadPlanError) TuningPlan
resolveTuningPlanWithExecutionSpec executionSpec raw =
  flattenValidation $
    assemble
      <$> mapValidationErrors CommonRunPlanError (resolveRun (rawTuningRun raw))
      <*> validateSampler (rawTuningSampler raw)
      <*> validateScheduler (rawTuningScheduler raw)
      <*> validatePruner (rawTuningPruner raw)
 where
  assemble runPlan sampler scheduler pruner =
    andThenValidation
      (validateResolvedTuningExecutionSpec runPlan sampler scheduler pruner executionSpec)
      (\() -> assembleTuningPlan runPlan sampler scheduler pruner executionSpec)

assembleTuningPlan
  :: RunPlan 'HyperparameterTuning
  -> Sampler
  -> Scheduler
  -> Pruner
  -> TuningExecutionSpec
  -> Validation (NonEmpty WorkloadPlanError) TuningPlan
assembleTuningPlan runPlan sampler scheduler pruner executionSpec =
  TuningPlan runPlan sampler scheduler pruner executionSpec
    <$> workloadPlanId
      "jitml-tuning-plan-v2"
      (runPlanId runPlan)
      [renderTuningExecutionSpec executionSpec]

validateResolvedTuningExecutionSpec
  :: RunPlan 'HyperparameterTuning
  -> Sampler
  -> Scheduler
  -> Pruner
  -> TuningExecutionSpec
  -> Validation (NonEmpty WorkloadPlanError) ()
validateResolvedTuningExecutionSpec runPlan sampler scheduler pruner spec =
  case validateTuningExecutionSpec spec >> validateBindings of
    Left err -> workloadFailure (InvalidTuningExecutionSpec err)
    Right () -> Success ()
 where
  (trials, parallelism, promotions, updates) = runPlanTuningBudget runPlan
  runSeed = NonEmpty.head (seedCohortValues (runPlanSeeds runPlan))
  specSampler = tuningExecutionSampler spec
  specScheduler = tuningExecutionScheduler spec
  specPruner = tuningExecutionPruner spec
  guaranteedPromotionCapacity =
    guaranteedReachedCeilingTrials spec
  validateBindings = do
    requireEqual "sampler kind" sampler (tuningSamplerKind specSampler)
    requireEqual "scheduler kind" scheduler (tuningSchedulerKind specScheduler)
    requireEqual "pruner kind" pruner (tuningPrunerKind specPruner)
    requireInteger "run seed" (toInteger runSeed) (toInteger (tuningSamplerSeed specSampler))
    architectureHeadroom <- tuningArchitectureSeedHeadroom spec
    if toInteger runSeed
      + toInteger (tuningExecutionTrials spec)
      - 1
      + architectureHeadroom
      > toInteger (maxBound :: Int)
      then
        Left
          ( "run seed plus the zero-based trial index and architecture seed headroom exceeds the platform Int range: headroom="
              <> showText architectureHeadroom
          )
      else Right ()
    requireInteger
      "trial count"
      (toInteger (quantityValue trials))
      (toInteger (tuningExecutionTrials spec))
    requireInteger
      "parallelism"
      (toInteger (quantityValue parallelism))
      (toInteger (tuningExecutionParallelism spec))
    requireInteger
      "scheduler parallelism"
      (toInteger (quantityValue parallelism))
      (toInteger (tuningSchedulerParallelism specScheduler))
    if quantityValue promotions == 0
      then Left "promotion count must be positive"
      else
        if toInteger (quantityValue promotions) > toInteger guaranteedPromotionCapacity
          then
            Left
              ( "promotion count exceeds the scheduler/pruner guaranteed frontier: plan="
                  <> showText (quantityValue promotions)
                  <> ", guaranteed="
                  <> showText guaranteedPromotionCapacity
              )
          else Right ()
    requireInteger
      "max optimizer updates per trial"
      (toInteger (quantityValue updates))
      (toInteger (tuningSchedulerMaxBudget specScheduler))
  requireEqual label expected observed
    | expected == observed = Right ()
    | otherwise =
        Left
          ( label
              <> " mismatch: plan="
              <> showText expected
              <> ", execution-spec="
              <> showText observed
          )
  requireInteger label expected observed
    | expected == observed = Right ()
    | otherwise =
        Left
          ( label
              <> " mismatch: plan="
              <> showText expected
              <> ", execution-spec="
              <> showText observed
          )

-- A promotion can only name a trial that actually reaches the configured
-- per-trial ceiling.  With an active pruner, objective values can make every
-- eligible trial except the first same-rung observation stop, so one is the
-- only value guaranteed independently of metrics.  Without a pruner, the
-- scheduler's deterministic cohort/rung reductions give a tighter bound.
guaranteedReachedCeilingTrials :: TuningExecutionSpec -> Natural
guaranteedReachedCeilingTrials spec
  | tuningPrunerKind (tuningExecutionPruner spec) /= NoPruner = 1
  | schedulerKind == Fifo = trials
  | schedulerRungs == 0 = trials
  | schedulerKind == SuccessiveHalving = reduceAcrossRungs trials
  | schedulerKind == ASHA = 1
  | schedulerKind == Hyperband = 0
  | otherwise =
      let (fullCohorts, remainder) = trials `divMod` cohortWidth
          fullSurvivors = fullCohorts * reduceAcrossRungs cohortWidth
          remainderSurvivors = if remainder == 0 then 0 else reduceAcrossRungs remainder
       in fullSurvivors + remainderSurvivors
 where
  trials = tuningExecutionTrials spec
  parallelism = tuningExecutionParallelism spec
  scheduler = tuningExecutionScheduler spec
  schedulerKind = tuningSchedulerKind scheduler
  eta = tuningSchedulerEta scheduler
  maxBudget = tuningSchedulerMaxBudget scheduler
  schedulerRungs = countSchedulerRungs eta maxBudget
  cohortWidth =
    case schedulerKind of
      ASHA -> parallelism
      Hyperband -> parallelism
      _ -> trials
  reduceAcrossRungs = applyN schedulerRungs (`ceilNatural` eta)

countSchedulerRungs :: Natural -> Natural -> Natural
countSchedulerRungs eta maxBudget = go 1 0
 where
  go current count
    | current >= maxBudget = count
    | current > maxBudget `div` eta = count + 1
    | otherwise = go (current * eta) (count + 1)

ceilNatural :: Natural -> Natural -> Natural
ceilNatural numerator denominator =
  (numerator + denominator - 1) `div` denominator

applyN :: Natural -> (value -> value) -> value -> value
applyN 0 _ value = value
applyN count step value = applyN (count - 1) step (step value)

tuningArchitectureSeedHeadroom :: TuningExecutionSpec -> Either Text Integer
tuningArchitectureSeedHeadroom spec =
  case matchingProblems of
    [problem] -> Right (Architecture.architectureSeedHeadroomForProblem problem)
    []
      | tuningExecutionDataset spec == "synthetic"
          && tuningExecutionModel spec == "Dense" ->
          Right
            ( Architecture.architectureSeedHeadroomForProblem
                (Canonicals.CanonicalProblem "legacy-tune-dense" "synthetic" "Dense" 0)
            )
      | otherwise ->
          Left
            ( "tuning execution spec has no canonical dataset/model problem: "
                <> tuningExecutionDataset spec
                <> "/"
                <> tuningExecutionModel spec
            )
    _ -> Left "tuning execution spec dataset/model resolves ambiguously"
 where
  matchingProblems =
    [ problem
    | problem <- Canonicals.canonicalProblems
    , Canonicals.problemDataset problem == tuningExecutionDataset spec
    , Canonicals.problemModel problem == tuningExecutionModel spec
    ]

resolveAlphaZeroPlan
  :: RawAlphaZeroPlan
  -> Validation (NonEmpty WorkloadPlanError) AlphaZeroPlan
resolveAlphaZeroPlan raw =
  flattenValidation $
    assemble
      <$> mapValidationErrors CommonRunPlanError (resolveRun (rawAlphaZeroRun raw))
      <*> validateAlphaZeroGame (rawAlphaZeroGame raw)
 where
  assemble runPlan game =
    AlphaZeroPlan runPlan game
      <$> workloadPlanId
        "jitml-alphazero-plan-v1"
        (runPlanId runPlan)
        [renderAlphaZeroGame game]

validateSampler :: Text -> Validation (NonEmpty WorkloadPlanError) Sampler
validateSampler raw =
  maybe
    (workloadFailure (UnknownTuningSampler normalized))
    Success
    ( samplerFromText normalized
        <|> find (sameName normalized . showText) samplerCatalog
    )
 where
  normalized = Text.strip raw

validateScheduler :: Text -> Validation (NonEmpty WorkloadPlanError) Scheduler
validateScheduler raw =
  maybe
    (workloadFailure (UnknownTuningScheduler normalized))
    Success
    ( schedulerFromText normalized
        <|> find (sameName normalized . showText) schedulerCatalog
    )
 where
  normalized = Text.strip raw

validatePruner :: Text -> Validation (NonEmpty WorkloadPlanError) Pruner
validatePruner raw =
  maybe
    (workloadFailure (UnknownTuningPruner normalized))
    Success
    ( prunerFromText normalized
        <|> find
          ( \candidate ->
              sameName normalized (showText candidate)
                || sameName normalized (Text.replace "Pruner" "" (showText candidate))
          )
          prunerCatalog
    )
 where
  normalized = Text.strip raw

sameName :: Text -> Text -> Bool
sameName left right = Text.toCaseFold (Text.strip left) == Text.toCaseFold (Text.strip right)

validateAlphaZeroGame
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) AlphaZeroGame
validateAlphaZeroGame raw =
  case Text.toLower (Text.strip raw) of
    "connect4" -> Success Connect4
    "connect 4" -> Success Connect4
    "othello" -> Success Othello
    "othello (reversi)" -> Success Othello
    "hex" -> Success Hex
    "gomoku" -> Success Gomoku
    other -> workloadFailure (UnknownAlphaZeroGame other)

workloadPlanId
  :: Text
  -> PlanId
  -> [Text]
  -> Validation (NonEmpty WorkloadPlanError) PlanId
workloadPlanId kind basePlanId fields =
  mapValidationErrors
    CommonRunPlanError
    ( planIdFromCanonicalText
        (Text.intercalate "\NUL" (kind : planIdText basePlanId : fields))
    )

renderSupervisedPlanTransport :: SupervisedPlan -> Text
renderSupervisedPlanTransport plan =
  let runPlan = supervisedPlanRunPlan plan
   in renderTransportFields
        [ ("transport-version", "1")
        , ("kind", "supervised-training")
        , ("plan-id", planIdText (supervisedPlanId plan))
        , ("run-version", showText (runPlanVersion runPlan))
        , ("experiment-id-hex", encodeTextHex (runPlanExperimentId runPlan))
        , ("subject-id-hex", encodeTextHex (runPlanSubjectId runPlan))
        , ("artifact-id-hex", encodeTextHex (runPlanArtifactId runPlan))
        , ("topic-id-hex", encodeTextHex (runPlanTopicId runPlan))
        , ("substrate", renderSubstrate (runPlanSubstrate runPlan))
        , ("placement", renderPlacement (runPlanPlacement runPlan))
        , ("seeds", renderSeeds runPlan)
        , ("epochs", showQuantity (supervisedPlanEpochs plan))
        , ("training-examples", showQuantity (supervisedPlanTrainingExamples plan))
        , ("evaluation-examples", showQuantity (supervisedPlanEvaluationExamples plan))
        , ("batch-examples", showQuantity (supervisedPlanBatchExamples plan))
        , ("optimizer-updates", showQuantity (supervisedPlanOptimizerUpdates plan))
        ]

renderTuningPlanTransport :: TuningPlan -> Text
renderTuningPlanTransport plan =
  let runPlan = tuningPlanRunPlan plan
   in renderTransportFields
        [ ("transport-version", "1")
        , ("kind", "hyperparameter-tuning")
        , ("plan-id", planIdText (tuningPlanId plan))
        , ("run-version", showText (runPlanVersion runPlan))
        , ("experiment-id-hex", encodeTextHex (runPlanExperimentId runPlan))
        , ("subject-id-hex", encodeTextHex (runPlanSubjectId runPlan))
        , ("artifact-id-hex", encodeTextHex (runPlanArtifactId runPlan))
        , ("topic-id-hex", encodeTextHex (runPlanTopicId runPlan))
        , ("substrate", renderSubstrate (runPlanSubstrate runPlan))
        , ("placement", renderPlacement (runPlanPlacement runPlan))
        , ("seeds", renderSeeds runPlan)
        , ("sampler", showText (tuningPlanSampler plan))
        , ("scheduler", showText (tuningPlanScheduler plan))
        , ("pruner", showText (tuningPlanPruner plan))
        , ("execution-spec-hex", encodeTextHex (renderTuningExecutionSpec (tuningPlanExecutionSpec plan)))
        , ("trials", showQuantity (tuningPlanTrials plan))
        , ("parallel-trials", showQuantity (tuningPlanParallelism plan))
        , ("promotions", showQuantity (tuningPlanPromotions plan))
        , ("max-optimizer-updates-per-trial", showQuantity (tuningPlanMaxPerTrialUpdates plan))
        ]

renderAlphaZeroPlanTransport :: AlphaZeroPlan -> Text
renderAlphaZeroPlanTransport plan =
  let runPlan = alphaZeroPlanRunPlan plan
   in renderTransportFields
        [ ("transport-version", "1")
        , ("kind", "alphazero-self-play")
        , ("plan-id", planIdText (alphaZeroPlanId plan))
        , ("run-version", showText (runPlanVersion runPlan))
        , ("experiment-id-hex", encodeTextHex (runPlanExperimentId runPlan))
        , ("subject-id-hex", encodeTextHex (runPlanSubjectId runPlan))
        , ("artifact-id-hex", encodeTextHex (runPlanArtifactId runPlan))
        , ("topic-id-hex", encodeTextHex (runPlanTopicId runPlan))
        , ("substrate", renderSubstrate (runPlanSubstrate runPlan))
        , ("placement", renderPlacement (runPlanPlacement runPlan))
        , ("seeds", renderSeeds runPlan)
        , ("game", renderAlphaZeroGame (alphaZeroPlanGame plan))
        , ("generations", showQuantity (alphaZeroPlanGenerations plan))
        , ("self-play-games-per-generation", showQuantity (alphaZeroPlanSelfPlayGames plan))
        , ("mcts-simulations-per-move", showQuantity (alphaZeroPlanMctsSimulations plan))
        , ("max-plies-per-game", showQuantity (alphaZeroPlanMaxPlies plan))
        , ("optimizer-updates-per-generation", showQuantity (alphaZeroPlanUpdates plan))
        , ("arena-games", showQuantity (alphaZeroPlanArenaGames plan))
        ]

parseSupervisedPlanTransport
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) SupervisedPlan
parseSupervisedPlanTransport input =
  andThenValidation
    (parseSupervisedRawTransport input)
    ( \(declaredPlanId, raw) ->
        andThenValidation
          (resolveSupervisedPlan raw)
          (verifySupervisedPlanId declaredPlanId)
    )

parseTuningPlanTransport
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) TuningPlan
parseTuningPlanTransport input =
  andThenValidation
    (parseTuningRawTransport input)
    ( \(declaredPlanId, raw, executionSpec) ->
        andThenValidation
          (resolveTuningPlanWithExecutionSpec executionSpec raw)
          (verifyTuningPlanId declaredPlanId)
    )

parseAlphaZeroPlanTransport
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) AlphaZeroPlan
parseAlphaZeroPlanTransport input =
  andThenValidation
    (parseAlphaZeroRawTransport input)
    ( \(declaredPlanId, raw) ->
        andThenValidation
          (resolveAlphaZeroPlan raw)
          (verifyAlphaZeroPlanId declaredPlanId)
    )

verifySupervisedPlanId
  :: Text
  -> SupervisedPlan
  -> Validation (NonEmpty WorkloadPlanError) SupervisedPlan
verifySupervisedPlanId declared plan
  | declared == derived = Success plan
  | otherwise = workloadFailure (TransportPlanIdMismatch declared derived)
 where
  derived = planIdText (supervisedPlanId plan)

verifyTuningPlanId
  :: Text
  -> TuningPlan
  -> Validation (NonEmpty WorkloadPlanError) TuningPlan
verifyTuningPlanId declared plan
  | declared == derived = Success plan
  | otherwise = workloadFailure (TransportPlanIdMismatch declared derived)
 where
  derived = planIdText (tuningPlanId plan)

verifyAlphaZeroPlanId
  :: Text
  -> AlphaZeroPlan
  -> Validation (NonEmpty WorkloadPlanError) AlphaZeroPlan
verifyAlphaZeroPlanId declared plan
  | declared == derived = Success plan
  | otherwise = workloadFailure (TransportPlanIdMismatch declared derived)
 where
  derived = planIdText (alphaZeroPlanId plan)

parseSupervisedRawTransport
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) (Text, RawSupervisedPlan)
parseSupervisedRawTransport input =
  andThenValidation
    (parseTransportFields supervisedTransportFields input)
    ( \fields ->
        build
          <$> requiredField "plan-id" fields
          <*> transportVersion fields
          <*> transportKind "supervised-training" fields
          <*> supervisedRawRun fields
    )
 where
  build declaredPlanId _version _kind runPlan =
    (declaredPlanId, RawSupervisedPlan runPlan)

parseTuningRawTransport
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) (Text, RawTuningPlan, TuningExecutionSpec)
parseTuningRawTransport input =
  andThenValidation
    (parseTransportFields tuningTransportFields input)
    ( \fields ->
        build
          <$> requiredField "plan-id" fields
          <*> transportVersion fields
          <*> transportKind "hyperparameter-tuning" fields
          <*> tuningRawRun fields
          <*> requiredField "sampler" fields
          <*> requiredField "scheduler" fields
          <*> requiredField "pruner" fields
          <*> tuningExecutionSpecField fields
    )
 where
  build declaredPlanId _version _kind runPlan sampler scheduler pruner executionSpec =
    (declaredPlanId, RawTuningPlan runPlan sampler scheduler pruner, executionSpec)

tuningExecutionSpecField
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) TuningExecutionSpec
tuningExecutionSpecField fields =
  andThenValidation (hexTextField "execution-spec-hex" fields) $ \encoded ->
    case parseTuningExecutionSpec encoded of
      Left err -> workloadFailure (InvalidTuningExecutionSpec err)
      Right spec -> Success spec

parseAlphaZeroRawTransport
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) (Text, RawAlphaZeroPlan)
parseAlphaZeroRawTransport input =
  andThenValidation
    (parseTransportFields alphaZeroTransportFields input)
    ( \fields ->
        build
          <$> requiredField "plan-id" fields
          <*> transportVersion fields
          <*> transportKind "alphazero-self-play" fields
          <*> alphaZeroRawRun fields
          <*> requiredField "game" fields
    )
 where
  build declaredPlanId _version _kind runPlan game =
    (declaredPlanId, RawAlphaZeroPlan runPlan game)

supervisedRawRun
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) (RawRunRequest 'SupervisedTraining)
supervisedRawRun fields =
  RawRunRequest
    <$> word64Field "run-version" fields
    <*> pure SupervisedTrainingWitness
    <*> hexTextField "experiment-id-hex" fields
    <*> hexTextField "subject-id-hex" fields
    <*> hexTextField "artifact-id-hex" fields
    <*> hexTextField "topic-id-hex" fields
    <*> substrateField fields
    <*> placementField fields
    <*> seedsField fields
    <*> ( RawSupervisedBudget
            <$> integerField "epochs" fields
            <*> integerField "training-examples" fields
            <*> integerField "evaluation-examples" fields
            <*> integerField "batch-examples" fields
            <*> integerField "optimizer-updates" fields
        )

tuningRawRun
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) (RawRunRequest 'HyperparameterTuning)
tuningRawRun fields =
  RawRunRequest
    <$> word64Field "run-version" fields
    <*> pure HyperparameterTuningWitness
    <*> hexTextField "experiment-id-hex" fields
    <*> hexTextField "subject-id-hex" fields
    <*> hexTextField "artifact-id-hex" fields
    <*> hexTextField "topic-id-hex" fields
    <*> substrateField fields
    <*> placementField fields
    <*> seedsField fields
    <*> ( RawTuningBudget
            <$> integerField "trials" fields
            <*> integerField "parallel-trials" fields
            <*> integerField "promotions" fields
            <*> integerField "max-optimizer-updates-per-trial" fields
        )

alphaZeroRawRun
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) (RawRunRequest 'AlphaZeroSelfPlay)
alphaZeroRawRun fields =
  RawRunRequest
    <$> word64Field "run-version" fields
    <*> pure AlphaZeroSelfPlayWitness
    <*> hexTextField "experiment-id-hex" fields
    <*> hexTextField "subject-id-hex" fields
    <*> hexTextField "artifact-id-hex" fields
    <*> hexTextField "topic-id-hex" fields
    <*> substrateField fields
    <*> placementField fields
    <*> seedsField fields
    <*> ( RawAlphaZeroBudget
            <$> integerField "generations" fields
            <*> integerField "self-play-games-per-generation" fields
            <*> integerField "mcts-simulations-per-move" fields
            <*> integerField "max-plies-per-game" fields
            <*> integerField "optimizer-updates-per-generation" fields
            <*> integerField "arena-games" fields
        )

supervisedTransportFields :: [Text]
supervisedTransportFields =
  commonTransportFields
    <> [ "epochs"
       , "training-examples"
       , "evaluation-examples"
       , "batch-examples"
       , "optimizer-updates"
       ]

tuningTransportFields :: [Text]
tuningTransportFields =
  commonTransportFields
    <> [ "sampler"
       , "scheduler"
       , "pruner"
       , "execution-spec-hex"
       , "trials"
       , "parallel-trials"
       , "promotions"
       , "max-optimizer-updates-per-trial"
       ]

alphaZeroTransportFields :: [Text]
alphaZeroTransportFields =
  commonTransportFields
    <> [ "game"
       , "generations"
       , "self-play-games-per-generation"
       , "mcts-simulations-per-move"
       , "max-plies-per-game"
       , "optimizer-updates-per-generation"
       , "arena-games"
       ]

commonTransportFields :: [Text]
commonTransportFields =
  [ "transport-version"
  , "kind"
  , "plan-id"
  , "run-version"
  , "experiment-id-hex"
  , "subject-id-hex"
  , "artifact-id-hex"
  , "topic-id-hex"
  , "substrate"
  , "placement"
  , "seeds"
  ]

parseTransportFields
  :: [Text]
  -> Text
  -> Validation (NonEmpty WorkloadPlanError) (Map Text Text)
parseTransportFields expected input =
  case errors of
    [] -> Success fields
    firstError : restErrors -> Failure (firstError :| restErrors)
 where
  expectedSet = Set.fromList expected
  (fields, errors) =
    foldl
      collectLine
      (Map.empty, [])
      (zip [1 ..] (Text.splitOn "|" input))

  collectLine (currentFields, currentErrors) (fieldNumber, fieldText) =
    let (rawKey, rawValue) = Text.breakOn "=" fieldText
        key = Text.strip rawKey
     in if Text.null rawValue || Text.null key
          then
            ( currentFields
            , currentErrors <> [InvalidTransportLine fieldNumber fieldText]
            )
          else
            if key `Set.notMember` expectedSet
              then
                ( currentFields
                , currentErrors <> [UnknownTransportField key]
                )
              else
                if Map.member key currentFields
                  then
                    ( currentFields
                    , currentErrors <> [DuplicateTransportField key]
                    )
                  else
                    ( Map.insert key (Text.strip (Text.drop 1 rawValue)) currentFields
                    , currentErrors
                    )

requiredField
  :: Text
  -> Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Text
requiredField key fields =
  case Map.lookup key fields of
    Nothing -> workloadFailure (MissingTransportField key)
    Just value
      | Text.null value -> workloadFailure (InvalidTransportValue key value)
      | otherwise -> Success value

transportVersion
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Word64
transportVersion fields =
  andThenValidation (word64Field "transport-version" fields) $ \version ->
    if version == 1
      then Success version
      else workloadFailure (UnsupportedTransportVersion version)

transportKind
  :: Text
  -> Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Text
transportKind expected fields =
  andThenValidation (requiredField "kind" fields) $ \observed ->
    if observed == expected
      then Success observed
      else workloadFailure (TransportKindMismatch expected observed)

word64Field
  :: Text
  -> Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Word64
word64Field key fields =
  parseFieldValue key fields readMaybe

integerField
  :: Text
  -> Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Integer
integerField key fields =
  parseFieldValue key fields readMaybe

parseFieldValue
  :: Text
  -> Map Text Text
  -> (String -> Maybe value)
  -> Validation (NonEmpty WorkloadPlanError) value
parseFieldValue key fields parseValue =
  andThenValidation (requiredField key fields) $ \raw ->
    maybe
      (workloadFailure (InvalidTransportValue key raw))
      Success
      (parseValue (Text.unpack raw))

hexTextField
  :: Text
  -> Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Text
hexTextField key fields =
  andThenValidation (requiredField key fields) $ \raw ->
    case decodeTextHex raw of
      Nothing -> workloadFailure (InvalidTransportValue key raw)
      Just value -> Success value

substrateField
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) Substrate
substrateField fields =
  andThenValidation (requiredField "substrate" fields) $ \raw ->
    maybe
      (workloadFailure (InvalidTransportValue "substrate" raw))
      Success
      (parseSubstrate raw)

placementField
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) RunPlacement
placementField fields =
  andThenValidation (requiredField "placement" fields) $ \raw ->
    case raw of
      "cluster" -> Success ClusterRun
      "host" -> Success HostRun
      "in-process" -> Success InProcessRun
      _ -> workloadFailure (InvalidTransportValue "placement" raw)

seedsField
  :: Map Text Text
  -> Validation (NonEmpty WorkloadPlanError) [Word64]
seedsField fields =
  andThenValidation (requiredField "seeds" fields) $ \raw ->
    if Text.null raw
      then Success []
      else traverse (parseSeed raw) (Text.splitOn "," raw)
 where
  parseSeed fullRaw token =
    maybe
      (workloadFailure (InvalidTransportValue "seeds" fullRaw))
      Success
      (readMaybe (Text.unpack token))

renderTransportFields :: [(Text, Text)] -> Text
renderTransportFields =
  Text.intercalate "|" . fmap (\(key, value) -> key <> "=" <> value)

renderPlacement :: RunPlacement -> Text
renderPlacement ClusterRun = "cluster"
renderPlacement HostRun = "host"
renderPlacement InProcessRun = "in-process"

renderSeeds :: RunPlan kind -> Text
renderSeeds =
  Text.intercalate ","
    . fmap showText
    . nonEmptyToList
    . seedCohortValues
    . runPlanSeeds

showQuantity :: Quantity unit -> Text
showQuantity = showText . quantityValue

showText :: (Show value) => value -> Text
showText = Text.pack . show

encodeTextHex :: Text -> Text
encodeTextHex =
  Text.pack
    . concatMap byteHex
    . ByteString.unpack
    . Text.Encoding.encodeUtf8
 where
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

decodeTextHex :: Text -> Maybe Text
decodeTextHex encoded
  | odd (Text.length encoded) = Nothing
  | not (Text.all isHexDigit encoded) = Nothing
  | otherwise =
      rightToMaybe
        (Text.Encoding.decodeUtf8' (ByteString.pack (decodeBytes (Text.unpack encoded))))
 where
  decodeBytes [] = []
  decodeBytes (high : low : rest) =
    fromIntegral (digitToInt high * 16 + digitToInt low) : decodeBytes rest
  decodeBytes [_] = []

mapValidationErrors
  :: (leftError -> rightError)
  -> Validation (NonEmpty leftError) value
  -> Validation (NonEmpty rightError) value
mapValidationErrors transform result =
  case result of
    Failure errors -> Failure (fmap transform errors)
    Success value -> Success value

andThenValidation
  :: Validation error value
  -> (value -> Validation error next)
  -> Validation error next
andThenValidation result next =
  case result of
    Failure errors -> Failure errors
    Success value -> next value

flattenValidation
  :: Validation error (Validation error value)
  -> Validation error value
flattenValidation result =
  andThenValidation result id

workloadFailure :: WorkloadPlanError -> Validation (NonEmpty WorkloadPlanError) value
workloadFailure err = Failure (err :| [])

nonEmptyToList :: NonEmpty value -> [value]
nonEmptyToList (firstValue :| restValues) = firstValue : restValues

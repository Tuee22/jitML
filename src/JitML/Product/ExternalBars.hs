{-# LANGUAGE OverloadedStrings #-}

-- | Phase 278 (Sprint 278.1) — the external convergence-bar predicates.
--
-- The 2026-07-05 realness audit found that the product path built each row's
-- convergence bar from the /measured/ value with zero slack
-- (@mkConvergenceBar name Maximise measuredValue 0.0@ in @JitML.App@), so the
-- pass check @value >= threshold@ reduced to @value >= value@ — a tautology that
-- passes at any accuracy. This module holds the predicates that grade a stored
-- convergence measurement against a bar that is independent of it, as required
-- by [Exit Definition item 26](../../../DEVELOPMENT_PLAN/README.md#exit-definition)
-- and [Phase 278](../../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md):
-- a convergence threshold must never be a function of the value it checks.
--
-- ProductRow bars are built by 'JitML.Product.Matrix' from the canonical tables
-- 'JitML.RL.ConvergenceThresholds' and 'JitML.SL.ConvergenceThresholds' (and the
-- literal HER, AlphaZero, regression, and tuning constants beside them); those
-- tables are the single source of external ground truth for a ProductRow. The
-- per-metric bars in 'convergenceBarForMetric' are a separate fixed fallback for
-- observations that carry no ProductRow identity; they are literals declared in
-- this module, and a unit cross-check pins the ones that overlap a ProductRow bar.
--
-- This module adds the invariants a stored bar and observation must satisfy: a
-- product bar has positive slack and finite, internally consistent fields
-- ('assertProductBarExternal'), and a completed observation set contains exactly
-- one observation of the row's metric, whose criterion and value agree with the
-- row's own bar ('assertConvergenceObservationsAgainstBar'). Those checks are
-- necessary but do not establish provenance: the source lint
-- ('JitML.Lint.ProductTruth') and the canonical row tables must also rule out a
-- measured-derived target. Literature targets are external references; their
-- slack values are project-calibrated tolerances and require separate review.
--
-- Phase 285 adds two committed, typed surfaces that per-model completed-run
-- evidence ('JitML.Test.ModelEvidence') is graded against:
--
-- * 'externalCriteriaFor' re-derives a row's convergence criterion directly from
--   the canonical threshold tables, keyed by the row's identity rather than read
--   from its 'JitML.Product.Matrix.ProductRow' bar, so a registry edit and a
--   table edit must agree before any evidence can pass; and
-- * 'PerformanceBound' ('AtLeast' | 'AtMost') requirements over deterministic,
--   non-wall-clock work counts that the completed run records. A bound is a
--   function of the plan's exact planned quantities and of nothing the run
--   reports, so it can never be derived from the value it grades.
module JitML.Product.ExternalBars
  ( assertProductBarExternal
  , assertConvergenceObservationsAgainstBar
  , assertConvergenceObservationsExternal
  , convergenceBarForMetric
  , convergenceObservationForMetric
  , convergenceObservationsForMetrics
  , CompletedWork (..)
  , ExternalCriterion (..)
  , PerformanceBound (..)
  , PerformanceMetric (..)
  , PerformanceRequirement (..)
  , PlannedWork (..)
  , externalCriteriaFor
  , externalCriterionGoal
  , externalCriterionPasses
  , performanceBoundHolds
  , performanceObservationsFor
  , performanceRequirementsFor
  , plannedWorkFor
  , renderPerformanceBound
  , renderPerformanceMetric
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence
  ( ConvergenceBar
  , MeasuredMetrics (..)
  , convergenceLiteratureTarget
  , convergenceMetricGoal
  , convergenceMetricName
  , convergenceSlack
  , convergenceThreshold
  , evaluateConvergence
  , mkConvergenceBar
  )
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.SL.ConvergenceThresholds qualified as SLConvergence
import JitML.Training.Budget qualified as TrainingBudget

-- | Fail-list form for the lint / negative-control suite. Returns one message
-- per violated clause; an externally-anchored bar returns @[]@.
--
-- Positive slack catches the historical zero-slack tautology, but it cannot
-- prove that the target came from an external source. A real measurement may
-- also equal an external target exactly, so runtime equality of the value and
-- the target is not evidence of self-reference.
assertProductBarExternal :: ConvergenceBar -> Double -> [Text]
assertProductBarExternal bar measuredValue =
  [ "convergence bar for "
      <> convergenceMetricName bar
      <> " has non-positive slack ("
      <> showDouble (convergenceSlack bar)
      <> ") — a self-referential/tautological bar (Exit Definition item 26)"
  | convergenceSlack bar <= 0.0
  ]
    <> [ "convergence bar for "
           <> convergenceMetricName bar
           <> " has non-finite target, slack, threshold, or measurement"
       | not
           ( all
               finite
               [ convergenceLiteratureTarget bar
               , convergenceSlack bar
               , convergenceThreshold bar
               , measuredValue
               ]
           )
       ]
    <> [ "convergence bar for "
           <> convergenceMetricName bar
           <> " has a threshold inconsistent with its target and slack"
       | all finite [convergenceLiteratureTarget bar, convergenceSlack bar, convergenceThreshold bar]
       , let expected =
               case convergenceMetricGoal bar of
                 TrainingBudget.MetricMaximise -> convergenceLiteratureTarget bar - convergenceSlack bar
                 TrainingBudget.MetricMinimise -> convergenceLiteratureTarget bar + convergenceSlack bar
       , abs (convergenceThreshold bar - expected)
           > 1.0e-12 * max 1.0 (max (abs expected) (abs (convergenceThreshold bar)))
       ]

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

showDouble :: Double -> Text
showDouble = Text.pack . show

convergenceBarForMetric :: Text -> Maybe ConvergenceBar
convergenceBarForMetric name =
  case name of
    "test_accuracy" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 0.90 0.05)
    "test_acc" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 0.90 0.05)
    "train_accuracy" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 0.90 0.05)
    "validation_accuracy" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 0.90 0.05)
    "rmse" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMinimise 0.90 0.10)
    "best_objective" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 1.0 0.05)
    "objective" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 1.0 0.05)
    "arena_win_rate" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 0.45 0.05)
    "legal_move_rate" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 1.0 0.01)
    "goal_success_rate" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMaximise 0.90 0.05)
    "achieved_goal_distance" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMinimise 0.04 0.01)
    "train_loss" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMinimise 2.0 0.10)
    "validation_loss" ->
      Just (mkConvergenceBar name TrainingBudget.MetricMinimise 2.0 0.10)
    _ -> Nothing

convergenceObservationForMetric
  :: (Text, Double)
  -> Either Text TrainingBudget.ConvergenceObservation
convergenceObservationForMetric metric@(name, _) =
  case convergenceBarForMetric name of
    Nothing -> Left ("missing external convergence bar for metric: " <> name)
    Just bar -> do
      observation <- evaluateConvergence bar (MeasuredMetrics [metric])
      let observationWithMetricSpecificGate =
            if name == "arena_win_rate"
              then
                TrainingBudget.measureCriterionExcluding
                  name
                  TrainingBudget.MetricMaximise
                  (TrainingBudget.coThreshold observation)
                  0.5
                  1.0e-12
                  (TrainingBudget.coMetricValue observation)
              else Right observation
      refinedObservation <- observationWithMetricSpecificGate
      case assertProductBarExternal bar (TrainingBudget.coMetricValue refinedObservation) of
        [] -> Right refinedObservation
        failures -> Left (Text.intercalate "; " failures)

convergenceObservationsForMetrics
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsForMetrics =
  traverse convergenceObservationForMetric

assertConvergenceObservationsExternal
  :: [TrainingBudget.ConvergenceObservation]
  -> [Text]
assertConvergenceObservationsExternal =
  concatMap validateObservation
 where
  validateObservation observation
    | TrainingBudget.coMetricName observation == rlMedianFinalRewardMetric =
        assertFrozenRlRewardObservationExternal observation
    | otherwise =
        case convergenceObservationForMetric
          (TrainingBudget.coMetricName observation, TrainingBudget.coMetricValue observation) of
          Left err -> [err]
          Right expected ->
            [ "stored convergence observation for "
                <> TrainingBudget.coMetricName observation
                <> " does not match the external bar"
            | TrainingBudget.coMetricGoal observation /= TrainingBudget.coMetricGoal expected
                || TrainingBudget.coThreshold observation /= TrainingBudget.coThreshold expected
                || TrainingBudget.convergencePassed observation
                  /= TrainingBudget.convergencePassed expected
            ]

-- | RL final-return convergence uses a per-(algorithm, environment) literature
-- anchor rather than a single universal value, so 'convergenceBarForMetric' has
-- no @median_final_reward@ entry. A generic (non-ProductRow) run has no cohort
-- identity, so the generic fallback verifies only what it can: the observation
-- maximises the environment return and its threshold equals one of the frozen
-- external cohort anchors. It cannot tell which cohort's anchor applies, so a
-- generic run may still claim another cohort's anchor; canonical rows are
-- checked against their own ProductRow bar by
-- 'assertConvergenceObservationsAgainstBar', and the legacy ledger tracks carrying
-- the cohort identity so this fallback can be deleted.
rlMedianFinalRewardMetric :: Text
rlMedianFinalRewardMetric = "median_final_reward"

assertFrozenRlRewardObservationExternal
  :: TrainingBudget.ConvergenceObservation -> [Text]
assertFrozenRlRewardObservationExternal observation =
  [ "stored RL "
      <> rlMedianFinalRewardMetric
      <> " observation must maximise the environment return"
  | TrainingBudget.coMetricGoal observation /= TrainingBudget.MetricMaximise
  ]
    <> [ "stored RL "
           <> rlMedianFinalRewardMetric
           <> " threshold "
           <> showDouble (TrainingBudget.coThreshold observation)
           <> " is not a frozen external cohort anchor (literatureTarget - slack)"
           <> " from JitML.RL.ConvergenceThresholds"
       | TrainingBudget.coThreshold observation `notElem` frozenRlRewardThresholds
       ]

-- | Every frozen external cohort anchor: the canonical table's literature
-- target less its project-calibrated slack.
frozenRlRewardThresholds :: [Double]
frozenRlRewardThresholds =
  [ RLConvergence.literatureTarget threshold - RLConvergence.slack threshold
  | (_, threshold) <- RLConvergence.cohortThresholds
  ]

-- | Grade a completed observation set against one ProductRow's own bar.
--
-- The bar's metric must be observed exactly once: 'evaluateConvergence'
-- resolves a metric by its first match, so a second observation of the same
-- metric would otherwise be accepted without being graded by anything. The
-- single observation must carry the bar's goal and threshold, the value the
-- bar is evaluated with, and the verdict re-derived from that value rather than
-- the stored one. Observations of other metrics are not this bar's concern.
assertConvergenceObservationsAgainstBar
  :: ConvergenceBar
  -> [TrainingBudget.ConvergenceObservation]
  -> [Text]
assertConvergenceObservationsAgainstBar bar observations =
  case evaluateConvergence bar (MeasuredMetrics measured) of
    Left err -> [err]
    Right expected ->
      assertProductBarExternal bar (TrainingBudget.coMetricValue expected)
        <> [ "convergence observations must contain exactly one observation of "
               <> convergenceMetricName bar
               <> ", found "
               <> Text.pack (show (length matchingObservations))
           | length matchingObservations /= 1
           ]
        <> concatMap (observationFailures expected) matchingObservations
 where
  measured =
    [ (TrainingBudget.coMetricName observation, TrainingBudget.coMetricValue observation)
    | observation <- observations
    ]
  matchingObservations =
    filter
      ((== convergenceMetricName bar) . TrainingBudget.coMetricName)
      observations
  observationFailures expected observation =
    [ "stored convergence observation for "
        <> TrainingBudget.coMetricName observation
        <> " does not match the product-row external bar"
    | TrainingBudget.coMetricGoal observation /= TrainingBudget.coMetricGoal expected
        || TrainingBudget.coThreshold observation /= TrainingBudget.coThreshold expected
        || TrainingBudget.convergencePassed observation
          /= TrainingBudget.convergencePassed expected
    ]
      <> [ "stored convergence observation for "
             <> TrainingBudget.coMetricName observation
             <> " carries value "
             <> showDouble (TrainingBudget.coMetricValue observation)
             <> ", not the value the product-row bar was evaluated with ("
             <> showDouble (TrainingBudget.coMetricValue expected)
             <> ")"
         | TrainingBudget.coMetricValue observation /= TrainingBudget.coMetricValue expected
         ]

-- | One externally derived convergence criterion: the metric name, the closed
-- comparison rule, and the finite threshold a completed run had to be graded
-- against. It is looked up from the canonical tables by row identity; it is
-- never read from a 'ProductMatrix.ProductRow' bar or from a completed run.
data ExternalCriterion = ExternalCriterion
  { externalCriterionName :: !Text
  , externalCriterionRule :: !TrainingBudget.RawCriterionRule
  , externalCriterionThreshold :: !Double
  }
  deriving stock (Eq, Show)

externalCriterionGoal :: ExternalCriterion -> TrainingBudget.MetricGoal
externalCriterionGoal criterion =
  case externalCriterionRule criterion of
    TrainingBudget.RawCriterionAtLeast -> TrainingBudget.MetricMaximise
    TrainingBudget.RawCriterionAtMost -> TrainingBudget.MetricMinimise
    TrainingBudget.RawCriterionAtLeastExcluding _ _ -> TrainingBudget.MetricMaximise

-- | Grade a cohort statistic with the same closed rule semantics that
-- 'TrainingBudget.convergencePassed' applies to a single observation.
externalCriterionPasses :: ExternalCriterion -> Double -> Bool
externalCriterionPasses criterion value =
  case externalCriterionRule criterion of
    TrainingBudget.RawCriterionAtLeast -> value >= limit
    TrainingBudget.RawCriterionAtMost -> value <= limit
    TrainingBudget.RawCriterionAtLeastExcluding excluded tolerance ->
      value >= limit && abs (value - excluded) > tolerance
 where
  limit = externalCriterionThreshold criterion

-- | Re-derive every convergence criterion a product row's completed run must
-- carry, directly from the canonical threshold tables. The first criterion is
-- the row's primary bar; HER additionally carries its achieved-goal-distance
-- companion. The row identity is the SL cohort key; the row class selects the
-- RL/HER/AlphaZero/tuning entry. The registry bar of the row is deliberately
-- not consulted here so that a registry edit and a table edit must agree.
externalCriteriaFor
  :: Text
  -> ProductMatrix.RowClass
  -> Either Text (NonEmpty ExternalCriterion)
externalCriteriaFor rowIdentity rowClass' =
  case rowClass' of
    ProductMatrix.SupervisedClassification _ _ ->
      case SLConvergence.slCohortThreshold rowIdentity of
        Nothing -> Left ("no supervised cohort threshold for row " <> rowIdentity)
        Just cohort ->
          Right
            ( ExternalCriterion
                "test_accuracy"
                TrainingBudget.RawCriterionAtLeast
                (SLConvergence.slLiteratureTarget cohort - SLConvergence.slSlack cohort)
                :| []
            )
    ProductMatrix.SupervisedRegression _ _ -> metricBarCriterion "rmse"
    ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
      case RLConvergence.cohortThreshold algorithm environment of
        Nothing ->
          Left ("no RL cohort threshold for " <> algorithm <> "/" <> environment)
        Just cohort ->
          Right
            ( ExternalCriterion
                "median_final_reward"
                TrainingBudget.RawCriterionAtLeast
                (RLConvergence.literatureTarget cohort - RLConvergence.slack cohort)
                :| []
            )
    ProductMatrix.RlGoalConditioned environment
      | environment == RLConvergence.hgmEnvironment RLConvergence.herGoalMetric ->
          Right
            ( observationCriterion (RLConvergence.hgmSuccessRate RLConvergence.herGoalMetric)
                :| [ observationCriterion
                       (RLConvergence.hgmAchievedGoalDistance RLConvergence.herGoalMetric)
                   ]
            )
      | otherwise -> Left ("no HER goal metric for environment " <> environment)
    ProductMatrix.AlphaZeroGame game ->
      case [ row
           | row <- RLConvergence.alphaZeroGameConvergenceRows
           , RLConvergence.azgGame row == game
           ] of
        row : _ -> Right (observationCriterion (RLConvergence.azgArenaWinRate row) :| [])
        [] -> Left ("no AlphaZero arena threshold for game " <> game)
    ProductMatrix.HyperparameterTuning _ -> metricBarCriterion "best_objective"
 where
  metricBarCriterion name =
    case convergenceBarForMetric name of
      Nothing -> Left ("missing external convergence bar for metric: " <> name)
      Just bar ->
        Right
          ( ExternalCriterion
              (convergenceMetricName bar)
              ( case convergenceMetricGoal bar of
                  TrainingBudget.MetricMaximise -> TrainingBudget.RawCriterionAtLeast
                  TrainingBudget.MetricMinimise -> TrainingBudget.RawCriterionAtMost
              )
              (convergenceThreshold bar)
              :| []
          )

-- | Read the criterion out of a canonical-table observation. Only the criterion
-- (name, closed rule, threshold) is used; the observation's own value is the
-- table's literature anchor and is ignored.
observationCriterion :: TrainingBudget.ConvergenceObservation -> ExternalCriterion
observationCriterion observation =
  ExternalCriterion
    { externalCriterionName = TrainingBudget.rawCriterionName raw
    , externalCriterionRule = TrainingBudget.rawCriterionRule raw
    , externalCriterionThreshold = TrainingBudget.rawCriterionThreshold raw
    }
 where
  raw = TrainingBudget.convergenceObservationToRaw observation

-- | The deterministic, non-wall-clock work counts a completed run records in
-- its 'TrainingBudget.CompletedTraining': the primary budget units it observed
-- and the trainer-observed optimizer-update count. No timer, throughput rate,
-- or served-inference latency is an input to any performance bound.
data CompletedWork = CompletedWork
  { completedWorkObservedUnits :: !Word64
  , completedWorkOptimizerUpdates :: !Word64
  }
  deriving stock (Eq, Show)

-- | The plan's exact planned quantities, read from the validated resolved
-- plan. 'plannedOptimizerUpdates' is 'Nothing' where the plan defines no
-- optimizer-update quantity (traditional RL counts transitions, not updates).
data PlannedWork = PlannedWork
  { plannedUnits :: !Integer
  , plannedOptimizerUpdates :: !(Maybe Integer)
  }
  deriving stock (Eq, Show)

plannedWorkFor :: ProductMatrix.ProductResolvedPlan kind -> PlannedWork
plannedWorkFor resolved =
  case resolved of
    ProductMatrix.ResolvedSupervisedProductPlan plan ->
      PlannedWork
        { plannedUnits = quantityInteger (WorkloadPlan.supervisedPlanEpochs plan)
        , plannedOptimizerUpdates =
            Just (quantityInteger (WorkloadPlan.supervisedPlanOptimizerUpdates plan))
        }
    ProductMatrix.ResolvedRlProductPlan plan ->
      let (transitions, _, _, _, _) = Plan.runPlanRlBudget plan
       in PlannedWork
            { plannedUnits = quantityInteger transitions
            , plannedOptimizerUpdates = Nothing
            }
    ProductMatrix.ResolvedTuningProductPlan plan ->
      PlannedWork
        { plannedUnits = quantityInteger (WorkloadPlan.tuningPlanTrials plan)
        , plannedOptimizerUpdates =
            Just (quantityInteger (WorkloadPlan.tuningPlanMaxPerTrialUpdates plan))
        }
    ProductMatrix.ResolvedAlphaZeroProductPlan plan ->
      PlannedWork
        { plannedUnits = quantityInteger (WorkloadPlan.alphaZeroPlanGenerations plan)
        , plannedOptimizerUpdates =
            Just
              ( quantityInteger (WorkloadPlan.alphaZeroPlanGenerations plan)
                  * quantityInteger (WorkloadPlan.alphaZeroPlanUpdates plan)
              )
        }

quantityInteger :: Plan.Quantity unit -> Integer
quantityInteger = toInteger . Plan.quantityValue

-- | The closed set of deterministic performance metrics. Each is a work count
-- rather than a rate:
--
-- * 'PerformanceExamplesSeen' (supervised): training examples consumed, i.e.
--   the observed epoch count times the plan's training examples per epoch;
-- * 'PerformanceEnvironmentTransitions' (RL): physical environment transitions
--   the trainer counted, the sample-efficiency quantity;
-- * 'PerformanceAlphaZeroOptimizerUpdates' (AlphaZero): trainer-observed
--   optimizer applications across all self-play generations;
-- * 'PerformancePromotedTrialOptimizerUpdates' (tuning): trainer-observed
--   optimizer applications of the promoted trial.
data PerformanceMetric
  = PerformanceExamplesSeen
  | PerformanceEnvironmentTransitions
  | PerformanceAlphaZeroOptimizerUpdates
  | PerformancePromotedTrialOptimizerUpdates
  deriving stock (Eq, Ord, Show, Enum, Bounded)

renderPerformanceMetric :: PerformanceMetric -> Text
renderPerformanceMetric metric =
  case metric of
    PerformanceExamplesSeen -> "examples_seen"
    PerformanceEnvironmentTransitions -> "environment_transitions"
    PerformanceAlphaZeroOptimizerUpdates -> "alphazero_optimizer_updates"
    PerformancePromotedTrialOptimizerUpdates -> "promoted_trial_optimizer_updates"

-- | A committed bound over a deterministic work count. It is built from the
-- plan's exact planned quantities and never from the count it grades.
data PerformanceBound
  = AtLeast !Integer
  | AtMost !Integer
  deriving stock (Eq, Show)

performanceBoundHolds :: PerformanceBound -> Integer -> Bool
performanceBoundHolds bound observed =
  case bound of
    AtLeast floorValue -> observed >= floorValue
    AtMost ceilingValue -> observed <= ceilingValue

renderPerformanceBound :: PerformanceBound -> Text
renderPerformanceBound bound =
  case bound of
    AtLeast floorValue -> "at least " <> Text.pack (show floorValue)
    AtMost ceilingValue -> "at most " <> Text.pack (show ceilingValue)

data PerformanceRequirement = PerformanceRequirement
  { requirementMetric :: !PerformanceMetric
  , requirementBound :: !PerformanceBound
  }
  deriving stock (Eq, Show)

-- | The committed per-family performance requirements of one validated plan:
--
-- * supervised: 'AtLeast' the plan's epochs times training examples (a floor
--   on examples seen, so an underrun cannot pass);
-- * RL: 'AtMost' the plan's environment-transition budget (a sample-efficiency
--   ceiling; a lane journal keeps no per-iteration curve, so the tightest
--   provable ceiling is the exact budget the run consumed);
-- * AlphaZero: 'AtLeast' the plan's generations times optimizer updates per
--   generation;
-- * tuning: 'AtLeast' and 'AtMost' the plan's per-trial optimizer-update
--   ceiling (the promoted trial must have reached, and not exceeded, it).
performanceRequirementsFor
  :: ProductMatrix.ProductResolvedPlan kind
  -> [PerformanceRequirement]
performanceRequirementsFor resolved =
  case resolved of
    ProductMatrix.ResolvedSupervisedProductPlan plan ->
      [ PerformanceRequirement
          PerformanceExamplesSeen
          ( AtLeast
              ( quantityInteger (WorkloadPlan.supervisedPlanEpochs plan)
                  * quantityInteger (WorkloadPlan.supervisedPlanTrainingExamples plan)
              )
          )
      ]
    ProductMatrix.ResolvedRlProductPlan plan ->
      let (transitions, _, _, _, _) = Plan.runPlanRlBudget plan
       in [ PerformanceRequirement
              PerformanceEnvironmentTransitions
              (AtMost (quantityInteger transitions))
          ]
    ProductMatrix.ResolvedTuningProductPlan plan ->
      let ceilingUpdates = quantityInteger (WorkloadPlan.tuningPlanMaxPerTrialUpdates plan)
       in [ PerformanceRequirement PerformancePromotedTrialOptimizerUpdates (AtLeast ceilingUpdates)
          , PerformanceRequirement PerformancePromotedTrialOptimizerUpdates (AtMost ceilingUpdates)
          ]
    ProductMatrix.ResolvedAlphaZeroProductPlan plan ->
      [ PerformanceRequirement
          PerformanceAlphaZeroOptimizerUpdates
          ( AtLeast
              ( quantityInteger (WorkloadPlan.alphaZeroPlanGenerations plan)
                  * quantityInteger (WorkloadPlan.alphaZeroPlanUpdates plan)
              )
          )
      ]

-- | The deterministic quantities a completed run records for each metric its
-- family is graded on, taken from 'CompletedWork' and, for supervised rows,
-- the plan's fixed training-split size (each example is consumed exactly once
-- per epoch; see the training-metrics document).
performanceObservationsFor
  :: ProductMatrix.ProductResolvedPlan kind
  -> CompletedWork
  -> [(PerformanceMetric, Integer)]
performanceObservationsFor resolved work =
  case resolved of
    ProductMatrix.ResolvedSupervisedProductPlan plan ->
      [
        ( PerformanceExamplesSeen
        , toInteger (completedWorkObservedUnits work)
            * quantityInteger (WorkloadPlan.supervisedPlanTrainingExamples plan)
        )
      ]
    ProductMatrix.ResolvedRlProductPlan _ ->
      [(PerformanceEnvironmentTransitions, toInteger (completedWorkObservedUnits work))]
    ProductMatrix.ResolvedTuningProductPlan _ ->
      [
        ( PerformancePromotedTrialOptimizerUpdates
        , toInteger (completedWorkOptimizerUpdates work)
        )
      ]
    ProductMatrix.ResolvedAlphaZeroProductPlan _ ->
      [
        ( PerformanceAlphaZeroOptimizerUpdates
        , toInteger (completedWorkOptimizerUpdates work)
        )
      ]

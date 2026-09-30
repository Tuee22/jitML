{-# LANGUAGE OverloadedStrings #-}

-- | Phase 32 (Sprint 32.2) — the anti-self-referential convergence-bar invariant.
--
-- The 2026-07-05 realness audit found that the product path built each row's
-- convergence bar from the /measured/ value with zero slack
-- (@mkConvergenceBar name Maximise measuredValue 0.0@ in @JitML.App@), so the
-- pass check @value >= threshold@ reduced to @value >= value@ — a tautology that
-- passes at any accuracy. This module is the frozen-external-bar primitive
-- referenced by [Exit Definition item 26](../../../DEVELOPMENT_PLAN/README.md#exit-definition)
-- and [Phase 278](../../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md):
-- a convergence threshold must never be a function of the value it checks.
--
-- The literature targets themselves live in the existing external tables
-- 'JitML.RL.ConvergenceThresholds' and 'JitML.SL.ConvergenceThresholds'; those
-- are the single source of external ground truth. This module adds the invariant
-- that a product bar has positive slack and finite, internally consistent
-- fields. Those checks are necessary but do not establish provenance: the
-- source lint and canonical row tables must also rule out a measured-derived
-- target. Literature targets are external references; their slack values are
-- project-calibrated tolerances and require separate review.
module JitML.Product.ExternalBars
  ( barIsSelfReferential
  , assertProductBarExternal
  , assertConvergenceObservationsAgainstBar
  , assertConvergenceObservationsExternal
  , convergenceBarForMetric
  , convergenceObservationForMetric
  , convergenceObservationsForMetrics
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

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
import JitML.Training.Budget qualified as TrainingBudget

-- | Reject a bar with non-positive slack. This catches the historical
-- zero-slack tautology, but positive slack alone cannot prove that the target
-- came from an external source. A real measurement may equal an external
-- target exactly, so runtime equality is not evidence of self-reference.
barIsSelfReferential :: ConvergenceBar -> Double -> Bool
barIsSelfReferential bar _measuredValue =
  convergenceSlack bar <= 0.0

-- | Fail-list form for the lint / negative-control suite. Returns one message
-- per violated clause; an externally-anchored bar returns @[]@.
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
        [ "stored RL median_final_reward has no canonical cohort identity; "
            <> "its external bar cannot be verified"
        ]
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
-- no @median_final_reward@ entry. The generic fallback has no cohort identity
-- and must reject a reward observation; canonical rows are checked against
-- their own ProductRow bar by 'assertConvergenceObservationsAgainstBar'.
rlMedianFinalRewardMetric :: Text
rlMedianFinalRewardMetric = "median_final_reward"

assertConvergenceObservationsAgainstBar
  :: ConvergenceBar
  -> [TrainingBudget.ConvergenceObservation]
  -> [Text]
assertConvergenceObservationsAgainstBar bar observations =
  case evaluateConvergence bar (MeasuredMetrics measured) of
    Left err -> [err]
    Right expected ->
      assertProductBarExternal bar (TrainingBudget.coMetricValue expected)
        <> [ "stored convergence observation for "
               <> TrainingBudget.coMetricName observation
               <> " does not match the product-row external bar"
           | observation <- matchingObservations
           , TrainingBudget.coMetricGoal observation /= TrainingBudget.coMetricGoal expected
               || TrainingBudget.coThreshold observation /= TrainingBudget.coThreshold expected
               || TrainingBudget.convergencePassed observation
                 /= TrainingBudget.convergencePassed expected
           ]
 where
  measured =
    [ (TrainingBudget.coMetricName observation, TrainingBudget.coMetricValue observation)
    | observation <- observations
    ]
  matchingObservations =
    filter
      ((== convergenceMetricName bar) . TrainingBudget.coMetricName)
      observations

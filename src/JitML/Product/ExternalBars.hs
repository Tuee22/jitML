{-# LANGUAGE OverloadedStrings #-}

-- | Phase 32 (Sprint 32.2) — the anti-self-referential convergence-bar invariant.
--
-- The 2026-07-05 realness audit found that the product path built each row's
-- convergence bar from the /measured/ value with zero slack
-- (@mkConvergenceBar name Maximise measuredValue 0.0@ in @JitML.App@), so the
-- pass check @value >= threshold@ reduced to @value >= value@ — a tautology that
-- passes at any accuracy. This module is the frozen-external-bar primitive
-- referenced by [Exit Definition item 26](../../DEVELOPMENT_PLAN/README.md#exit-definition)
-- and [phase-32-external-truth-realness-harness.md](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md):
-- a convergence threshold must never be a function of the value it checks.
--
-- The literature targets themselves live in the existing external tables
-- 'JitML.RL.ConvergenceThresholds' and 'JitML.SL.ConvergenceThresholds'; those
-- are the single source of external ground truth. This module adds the invariant
-- that a product bar is /externally anchored/ (positive slack) so the lint in
-- 'JitML.Lint.ProductTruth' and the negative-control suite can reject a
-- self-referential bar.
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
  , convergenceMetricName
  , convergenceSlack
  , evaluateConvergence
  , mkConvergenceBar
  )
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.Training.Budget qualified as TrainingBudget

-- | A convergence bar is self-referential (tautological) when its slack is
-- non-positive — so @threshold == literatureTarget@ and the boundary
-- @value >= threshold@ is satisfied by the target itself. Equality between a
-- measured value and a positive-slack external target is allowed: a real run can
-- land exactly on its literature target.
barIsSelfReferential :: ConvergenceBar -> Double -> Bool
barIsSelfReferential bar _measuredValue =
  convergenceSlack bar <= 0.0

-- | Fail-list form for the lint / negative-control suite. Returns one message
-- per violated clause; an externally-anchored bar returns @[]@.
assertProductBarExternal :: ConvergenceBar -> Double -> [Text]
assertProductBarExternal bar _measuredValue =
  [ "convergence bar for "
      <> convergenceMetricName bar
      <> " has non-positive slack ("
      <> showDouble (convergenceSlack bar)
      <> ") — a self-referential/tautological bar (Exit Definition item 26)"
  | convergenceSlack bar <= 0.0
  ]
    <> []

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
-- no @median_final_reward@ entry (a single universal reward target would be
-- wrong — env rewards differ by orders of magnitude). A stored RL reward
-- observation is externally anchored iff it maximises the return and its
-- threshold is one of the frozen @literatureTarget - slack@ anchors in
-- 'RLConvergence.cohortThresholds' — the single source of external RL ground
-- truth this module's docstring references. Because that set is fixed and
-- value-independent, the threshold can never be a self-referential
-- @threshold == measuredValue@ bar except by an astronomically unlikely
-- coincidence with a frozen anchor.
rlMedianFinalRewardMetric :: Text
rlMedianFinalRewardMetric = "median_final_reward"

frozenRlRewardThresholds :: [Double]
frozenRlRewardThresholds =
  [ RLConvergence.literatureTarget threshold - RLConvergence.slack threshold
  | (_, threshold) <- RLConvergence.cohortThresholds
  ]

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

assertConvergenceObservationsAgainstBar
  :: ConvergenceBar
  -> [TrainingBudget.ConvergenceObservation]
  -> [Text]
assertConvergenceObservationsAgainstBar bar observations =
  case evaluateConvergence bar (MeasuredMetrics measured) of
    Left err -> [err]
    Right expected ->
      [ "stored convergence observation for "
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

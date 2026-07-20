{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Convergence
  ( ConvergenceBar (..)
  , ConvergenceBarError (..)
  , MeasuredMetrics (..)
  , ValidatedConvergenceBar
  , barFromObservation
  , classificationAccuracyBar
  , evaluateConvergence
  , mkConvergenceBar
  , regressionRmseBar
  , validateConvergenceBar
  , validatedConvergenceBar
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan (Validation (..))
import JitML.SL.ConvergenceThresholds (SlConvergenceThreshold (..))
import JitML.Training.Budget
  ( ConvergenceObservation
  , MetricGoal (..)
  , coMetricGoal
  , coMetricName
  , coMetricValue
  , coThreshold
  , measureCriterion
  )

data ConvergenceBar = ConvergenceBar
  { convergenceMetricName :: Text
  , convergenceMetricGoal :: MetricGoal
  , convergenceLiteratureTarget :: Double
  , convergenceSlack :: Double
  , convergenceThreshold :: Double
  }
  deriving stock (Eq, Show)

-- | Raw convergence declarations remain constructible because ProductRow
-- constructor hiding belongs to Sprint 21.4.  A declaration crosses into an
-- executable product projection only after these relational and finite-value
-- checks succeed.
data ConvergenceBarError
  = EmptyConvergenceMetricName
  | NonFiniteConvergenceLiteratureTarget Double
  | NonFiniteConvergenceSlack Double
  | NegativeConvergenceSlack Double
  | NonFiniteConvergenceThreshold Double
  | InconsistentConvergenceThreshold
      { expectedConvergenceThreshold :: Double
      , observedConvergenceThreshold :: Double
      }
  deriving stock (Eq, Show)

-- | A convergence declaration refined at the product-plan boundary.  The
-- constructor is deliberately private; callers can inspect the original bar
-- but cannot bypass validation when constructing a ProductProjection.
newtype ValidatedConvergenceBar = ValidatedConvergenceBar ConvergenceBar
  deriving stock (Eq, Show)

validatedConvergenceBar :: ValidatedConvergenceBar -> ConvergenceBar
validatedConvergenceBar (ValidatedConvergenceBar bar) = bar

validateConvergenceBar
  :: ConvergenceBar
  -> Validation (NonEmpty ConvergenceBarError) ValidatedConvergenceBar
validateConvergenceBar bar =
  case errors of
    [] -> Success (ValidatedConvergenceBar bar)
    first : rest -> Failure (first :| rest)
 where
  target = convergenceLiteratureTarget bar
  slack = convergenceSlack bar
  threshold = convergenceThreshold bar
  expectedThreshold =
    case convergenceMetricGoal bar of
      MetricMaximise -> target - slack
      MetricMinimise -> target + slack
  errors =
    [ EmptyConvergenceMetricName
    | Text.null (Text.strip (convergenceMetricName bar))
    ]
      <> [ NonFiniteConvergenceLiteratureTarget target
         | not (finite target)
         ]
      <> [ NonFiniteConvergenceSlack slack
         | not (finite slack)
         ]
      <> [ NegativeConvergenceSlack slack
         | finite slack
         , slack < 0
         ]
      <> [ NonFiniteConvergenceThreshold threshold
         | not (finite threshold)
         ]
      <> [ InconsistentConvergenceThreshold expectedThreshold threshold
         | finite target
         , finite slack
         , finite threshold
         , not (approximatelyEqual expectedThreshold threshold)
         ]

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

approximatelyEqual :: Double -> Double -> Bool
approximatelyEqual left right =
  abs (left - right) <= 1.0e-12 * max 1.0 (max (abs left) (abs right))

newtype MeasuredMetrics = MeasuredMetrics
  { unMeasuredMetrics :: [(Text, Double)]
  }
  deriving stock (Eq, Show)

mkConvergenceBar :: Text -> MetricGoal -> Double -> Double -> ConvergenceBar
mkConvergenceBar metricName goal target slack =
  ConvergenceBar
    { convergenceMetricName = metricName
    , convergenceMetricGoal = goal
    , convergenceLiteratureTarget = target
    , convergenceSlack = slack
    , convergenceThreshold = threshold
    }
 where
  threshold =
    case goal of
      MetricMaximise -> target - slack
      MetricMinimise -> target + slack

barFromObservation :: Double -> ConvergenceObservation -> ConvergenceBar
barFromObservation slack observation =
  ConvergenceBar
    { convergenceMetricName = coMetricName observation
    , convergenceMetricGoal = coMetricGoal observation
    , convergenceLiteratureTarget = coMetricValue observation
    , convergenceSlack = slack
    , convergenceThreshold = coThreshold observation
    }

classificationAccuracyBar :: Text -> SlConvergenceThreshold -> ConvergenceBar
classificationAccuracyBar metricName threshold =
  mkConvergenceBar
    metricName
    MetricMaximise
    (slLiteratureTarget threshold)
    (slSlack threshold)

regressionRmseBar :: Text -> Double -> Double -> ConvergenceBar
regressionRmseBar metricName =
  mkConvergenceBar metricName MetricMinimise

evaluateConvergence :: ConvergenceBar -> MeasuredMetrics -> Either Text ConvergenceObservation
evaluateConvergence bar (MeasuredMetrics metrics) =
  case lookup (convergenceMetricName bar) metrics of
    Nothing ->
      Left ("missing convergence metric: " <> convergenceMetricName bar)
    Just value ->
      measureCriterion
        (convergenceMetricName bar)
        (convergenceMetricGoal bar)
        (convergenceThreshold bar)
        value

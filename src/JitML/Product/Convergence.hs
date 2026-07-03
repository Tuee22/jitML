{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Convergence
  ( ConvergenceBar (..)
  , MeasuredMetrics (..)
  , barFromObservation
  , classificationAccuracyBar
  , evaluateConvergence
  , mkConvergenceBar
  , regressionRmseBar
  )
where

import Data.Text (Text)

import JitML.SL.ConvergenceThresholds (SlConvergenceThreshold (..))
import JitML.Training.Budget
  ( ConvergenceObservation (..)
  , MetricGoal (..)
  )

data ConvergenceBar = ConvergenceBar
  { convergenceMetricName :: Text
  , convergenceMetricGoal :: MetricGoal
  , convergenceLiteratureTarget :: Double
  , convergenceSlack :: Double
  , convergenceThreshold :: Double
  , convergencePinnedObservation :: ConvergenceObservation
  }
  deriving stock (Eq, Show)

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
    , convergencePinnedObservation =
        ConvergenceObservation
          { coMetricName = metricName
          , coMetricValue = target
          , coMetricGoal = goal
          , coThreshold = Just threshold
          , coPassed = True
          }
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
    , convergenceThreshold =
        case coThreshold observation of
          Just threshold -> threshold
          Nothing ->
            case coMetricGoal observation of
              MetricMaximise -> coMetricValue observation - slack
              MetricMinimise -> coMetricValue observation + slack
    , convergencePinnedObservation = observation
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
      Right
        ConvergenceObservation
          { coMetricName = convergenceMetricName bar
          , coMetricValue = value
          , coMetricGoal = convergenceMetricGoal bar
          , coThreshold = Just (convergenceThreshold bar)
          , coPassed = passes value
          }
 where
  passes value =
    case convergenceMetricGoal bar of
      MetricMaximise -> value >= convergenceThreshold bar
      MetricMinimise -> value <= convergenceThreshold bar

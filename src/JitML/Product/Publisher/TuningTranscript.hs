{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.TuningTranscript
  ( productTuneTrialArtifact
  )
where

import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan (PlanId, RunKind (HyperparameterTuning), planIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

productTuneTrialArtifact
  :: ProductMatrix.ProductProjection 'HyperparameterTuning
  -> TrainingBudget.CompletedTraining
  -> Text
  -> Tune.TuningExperiment
  -> Tune.Sampler
  -> [Tune.TrialExecution]
  -> Tune.TrialObjectiveResult
  -> Either Text Text
productTuneTrialArtifact projection completed datasetSha experiment sampler executions best = do
  let experimentHash = ProductMatrix.productProjectionExperimentHash projection
      planId = ProductMatrix.productProjectionPlanId projection
      results = fmap Tune.trialExecutionResult executions
      indices = fmap Tune.trialResultIndex results
      bestIndex = Tune.trialResultIndex best
      bestFinalSha = WeightCodec.jmw1ContentSha (WeightCodec.encodeJmw1 (Tune.trialResultWeights best))
      promotedExecutions =
        [ execution
        | execution <- executions
        , Tune.trialExecutionPromoted execution
        ]
  unlessEither (not (null executions)) "tuning v2 transcript has no trial executions"
  unlessEither
    (indices == [0 .. length executions - 1])
    ( "tuning v2 transcript trial indices are not the exact contiguous range: "
        <> Text.pack (show indices)
    )
  unlessEither
    (case promotedExecutions of [execution] -> Tune.trialExecutionResult execution == best; _ -> False)
    ( "tuning v2 transcript best trial "
        <> Text.pack (show bestIndex)
        <> " is not exactly one promoted execution"
    )
  traverse_ validateFiniteExecution executions
  requireProjectedValue
    "tuning transcript experiment"
    experimentHash
    (ProductMatrix.productProjectionExperimentHash projection)
  requireProjectedValue
    "tuning transcript PlanId"
    planId
    (TrainingBudget.completedTrainingPlanId completed)
  requireProjectedValue
    "tuning transcript dataset-at-read digest"
    datasetSha
    (TrainingBudget.completedTrainingDatasetShaAtRead completed)
  requireProjectedValue
    "tuning transcript best final JMW1 digest"
    bestFinalSha
    (TrainingBudget.completedTrainingFinalWeightHash completed)
  requireProjectedValue
    "tuning transcript completed trial count"
    (fromIntegral (length executions) :: Word64)
    (TrainingBudget.completedTrainingObservedUnits completed)
  expectedUpdates <-
    checkedPositiveWord64FromInt
      "tuning transcript best-trial optimizer update evidence"
      (Tune.trialResultUpdatesExecuted best)
  requireProjectedValue
    "tuning transcript best-trial optimizer updates"
    expectedUpdates
    (TrainingBudget.completedTrainingUpdateCount completed)
  case [ observation
       | observation <- TrainingBudget.completedTrainingMetrics completed
       , TrainingBudget.coMetricName observation == "best_objective"
       ] of
    [observation] ->
      requireProjectedValue
        "tuning transcript best objective"
        (Tune.trialResultObjective best)
        (TrainingBudget.coMetricValue observation)
    _ -> Left "tuning transcript completion must contain exactly one best_objective observation"
  Right
    ( renderTuneTrialArtifact
        (ProductMatrix.productProjectionRowId projection)
        planId
        experimentHash
        datasetSha
        bestFinalSha
        experiment
        sampler
        executions
        best
    )
 where
  validateFiniteExecution execution = do
    let result = Tune.trialExecutionResult execution
        hyperparameters = Tune.trialResultHyperparameters result
        finite value = not (isNaN value || isInfinite value)
        scalars =
          Tune.trialResultObjective result
            : Tune.trialLearningRate hyperparameters
            : Tune.trialDropout hyperparameters
            : fmap Tune.trialObservationObjective (Tune.trialResultObservations result)
              <> Tune.trialResultInitialWeights result
              <> Tune.trialResultWeights result
    unlessEither
      (all finite scalars)
      ( "tuning v2 transcript contains a non-finite value in trial "
          <> Text.pack (show (Tune.trialResultIndex result))
      )
{-# NOINLINE productTuneTrialArtifact #-}

renderTuneTrialArtifact
  :: Text
  -> PlanId
  -> Text
  -> Text
  -> Text
  -> Tune.TuningExperiment
  -> Tune.Sampler
  -> [Tune.TrialExecution]
  -> Tune.TrialObjectiveResult
  -> Text
renderTuneTrialArtifact rowId planId experimentHash datasetSha bestFinalSha experiment sampler executions best =
  Text.unlines $
    [ "kind: tune-trials-v2"
    , "row-id: " <> rowId
    , "plan-id: " <> planIdText planId
    , "experiment-hash: " <> experimentHash
    , "dataset-sha-at-read: " <> datasetSha
    , "best-final-jmw1-sha: " <> bestFinalSha
    , "name: " <> Tune.tuningExperimentName experiment
    , "sampler: " <> Text.pack (show sampler)
    , "trial-count: " <> Text.pack (show (length executions))
    , "pruner-stopped-count: " <> Text.pack (show (length (filter isPrunerStopped executions)))
    , "scheduler-stopped-count: " <> Text.pack (show (length (filter isSchedulerStopped executions)))
    , "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
    , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
    ]
      <> concatMap renderTrial executions
 where
  renderTrial execution =
    let result = Tune.trialExecutionResult execution
     in [ "trial: " <> Text.pack (show (Tune.trialResultIndex result))
        , "objective: " <> Text.pack (show (Tune.trialResultObjective result))
        , "learning-rate: "
            <> Text.pack (show (Tune.trialLearningRate (Tune.trialResultHyperparameters result)))
        , "batch-size: " <> Text.pack (show (Tune.trialBatchSize (Tune.trialResultHyperparameters result)))
        , "dropout: " <> Text.pack (show (Tune.trialDropout (Tune.trialResultHyperparameters result)))
        , "optimizer: " <> Tune.trialOptimizer (Tune.trialResultHyperparameters result)
        , "updates-executed: " <> Text.pack (show (Tune.trialResultUpdatesExecuted result))
        , "disposition: " <> renderTuneTrialDisposition (Tune.trialResultDisposition result)
        , "rung-count: " <> Text.pack (show (length (Tune.trialResultObservations result)))
        , "pruned: " <> Text.pack (show (Tune.trialExecutionPruned execution))
        , "promoted: " <> Text.pack (show (Tune.trialExecutionPromoted execution))
        , "weight-count: " <> Text.pack (show (length (Tune.trialResultWeights result)))
        ]
          <> [ "rung: updates="
                 <> Text.pack (show (Tune.trialObservationUpdates observation))
                 <> ",objective="
                 <> Text.pack (show (Tune.trialObservationObjective observation))
             | observation <- Tune.trialResultObservations result
             ]
  isPrunerStopped execution =
    case Tune.trialResultDisposition (Tune.trialExecutionResult execution) of
      Tune.PrunerStopped _ _ -> True
      _ -> False
  isSchedulerStopped execution =
    case Tune.trialResultDisposition (Tune.trialExecutionResult execution) of
      Tune.SchedulerStopped _ _ -> True
      _ -> False

renderTuneTrialDisposition :: Tune.TrialDisposition -> Text
renderTuneTrialDisposition Tune.ReachedMaxBudget = "reached-max-budget"
renderTuneTrialDisposition (Tune.SchedulerStopped scheduler rung) =
  "scheduler-stopped:" <> Text.pack (show scheduler) <> ":" <> Text.pack (show rung)
renderTuneTrialDisposition (Tune.PrunerStopped pruner rung) =
  "pruner-stopped:" <> Text.pack (show pruner) <> ":" <> Text.pack (show rung)

checkedPositiveWord64FromInt :: Text -> Int -> Either Text Word64
checkedPositiveWord64FromInt label value
  | value <= 0 = Left (label <> " must be positive")
  | toInteger value > toInteger (maxBound :: Word64) = Left (label <> " exceeds the Word64 range")
  | otherwise = Right (fromIntegral value)

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

unlessEither :: Bool -> Text -> Either Text ()
unlessEither condition message
  | condition = Right ()
  | otherwise = Left message

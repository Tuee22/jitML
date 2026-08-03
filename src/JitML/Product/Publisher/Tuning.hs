{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Tuning
  ( trainAndPublishTuningProductRow
  )
where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Text qualified as Text

import JitML.Env.Env (App)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Plan.Plan
  ( RunKind (..)
  , quantityValue
  , runPlanExperimentId
  , runPlanSubstrate
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.Audit
  ( ProductPublishResult
  , productArtifactPointer
  , validateProductCompletedTrainingPlanId
  )
import JitML.Product.Publisher.Common
  ( admitPublishedProductCheckpoint
  , bindProductScenarioCompletion
  , productPublishEligible
  , productPublishError
  , writeProductTextArtifact
  )
import JitML.Product.Publisher.Projection
  ( checkedPositiveWord64FromInt
  , intPlanValue
  , productTrainingBudgetForProjection
  , projectedRunSeed
  , requireProjectedValue
  , validateProjectionRowAssociation
  , validateTuningProductExperiment
  )
import JitML.Product.Publisher.Runtime
  ( ProductPublisherRuntime (..)
  , TuningPublishDataset (..)
  )
import JitML.Product.Publisher.TuningTranscript (productTuneTrialArtifact)
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

trainAndPublishTuningProductRow
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'HyperparameterTuning
  -> Tune.TuningExperiment
  -> App ProductPublishResult
trainAndPublishTuningProductRow invocation runtime row projection experiment =
  case ( ProductMatrix.productProjectionDescriptor projection
       , ProductMatrix.productProjectionResolvedPlan projection
       ) of
    ( ProductMatrix.TuningProductDescriptor
        descriptorExecutionSpec
        descriptorParallel
        descriptorPromotions
        descriptorUpdates
      , ProductMatrix.ResolvedTuningProductPlan plan
      ) -> do
        let runPlan = WorkloadPlan.tuningPlanRunPlan plan
            sampler = WorkloadPlan.tuningPlanSampler plan
            executionSpec = WorkloadPlan.tuningPlanExecutionSpec plan
            trialsWord = quantityValue (WorkloadPlan.tuningPlanTrials plan)
            parallelWord = quantityValue (WorkloadPlan.tuningPlanParallelism plan)
            promotionsWord = quantityValue (WorkloadPlan.tuningPlanPromotions plan)
            updatesWord = quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan)
            seedWord = projectedRunSeed runPlan
            projectionValidation = do
              validateProjectionRowAssociation row projection
              requireProjectedValue "tuning execution spec" descriptorExecutionSpec executionSpec
              requireProjectedValue "tuning parallel trials" descriptorParallel parallelWord
              requireProjectedValue "tuning promotions" descriptorPromotions promotionsWord
              requireProjectedValue "tuning per-trial updates" descriptorUpdates updatesWord
              requireProjectedValue
                "tuning PlanId"
                (ProductMatrix.productProjectionPlanId projection)
                (WorkloadPlan.tuningPlanId plan)
              productTrainingBudgetForProjection
                projection
                TrainingBudget.TuningTrialBudget
                trialsWord
                seedWord
        case projectionValidation of
          Left err -> pure (productPublishError projection err)
          Right budget -> do
            promotions <- intPlanValue "product tuning promotions" promotionsWord
            seed <- intPlanValue "product tuning seed" seedWord
            case validateTuningProductExperiment
              plan
              seedWord
              (ProductExperiment.ProductTuningExperiment experiment) of
              Left err -> pure (productPublishError projection err)
              Right _ -> do
                env <- ask
                datasetE <- publisherLoadTuningDataset runtime executionSpec
                case datasetE of
                  Left err -> pure (productPublishError projection err)
                  Right dataset -> do
                    resultsE <-
                      liftIO
                        ( Tune.trialObjectiveResultsWithDeviceForExecutionSpec
                            (mlpDeviceForSubstrate (runPlanSubstrate runPlan) env)
                            seed
                            executionSpec
                            (tuningPublishProblem dataset)
                            (tuningPublishBaseConfig dataset)
                            (tuningPublishTrainSet dataset)
                            (tuningPublishValidationSet dataset)
                        )
                    case resultsE of
                      Left err -> pure (productPublishError projection err)
                      Right trialResults -> do
                        let observedTrials = fromIntegral (length trialResults)
                        if observedTrials /= trialsWord
                          then
                            pure
                              ( productPublishError
                                  projection
                                  ( "tuning executor completed "
                                      <> Text.pack (show observedTrials)
                                      <> " trials; resolved budget requires "
                                      <> Text.pack (show trialsWord)
                                  )
                              )
                          else case Tune.trialExecutionsForExecutionSpec executionSpec promotions trialResults of
                            Left err -> pure (productPublishError projection err)
                            Right executions -> do
                              let promotedResults =
                                    [ Tune.trialExecutionResult execution
                                    | execution <- executions
                                    , Tune.trialExecutionPromoted execution
                                    ]
                                  observedPromotions = length promotedResults
                              if observedPromotions /= promotions
                                then
                                  pure
                                    ( productPublishError
                                        projection
                                        ( "tuning executor promoted "
                                            <> Text.pack (show observedPromotions)
                                            <> " trials; resolved budget requires "
                                            <> Text.pack (show promotions)
                                        )
                                    )
                                else case Tune.selectBestTrialResultForExecutionSpec
                                  executionSpec
                                  promotedResults of
                                  Nothing ->
                                    pure
                                      (productPublishError projection "tuning row produced no promoted trial result")
                                  Just best -> do
                                    let experimentHash = runPlanExperimentId runPlan
                                        trialsCompleted = observedTrials
                                        metricRows = [("best_objective", Tune.trialResultObjective best)]
                                        completedTraining = do
                                          trainingUpdateCount <-
                                            checkedPositiveWord64FromInt
                                              "tuning best-trial optimizer update evidence"
                                              (Tune.trialResultUpdatesExecuted best)
                                          completed <-
                                            publisherCompleteProductRow
                                              runtime
                                              (WorkloadPlan.tuningPlanId plan)
                                              budget
                                              row
                                              (tuningPublishDatasetShaAtRead dataset)
                                              experimentHash
                                              "tune-trial-weights"
                                              trialsCompleted
                                              trainingUpdateCount
                                              metricRows
                                              (Tune.trialResultInitialWeights best)
                                              (Tune.trialResultWeights best)
                                          validateProductCompletedTrainingPlanId projection completed
                                          bindProductScenarioCompletion invocation projection completed
                                    case completedTraining of
                                      Left err ->
                                        pure
                                          ( productPublishError
                                              projection
                                              ( "tuning row did not produce passing CompletedTraining evidence: "
                                                  <> err
                                              )
                                          )
                                      Right completed -> do
                                        case productTuneTrialArtifact
                                          projection
                                          completed
                                          (tuningPublishDatasetShaAtRead dataset)
                                          experiment
                                          sampler
                                          executions
                                          best of
                                          Left err ->
                                            pure
                                              ( productPublishError
                                                  projection
                                                  ("tuning v2 transcript validation failed: " <> err)
                                              )
                                          Right transcriptPayload -> do
                                            transcript <-
                                              writeProductTextArtifact
                                                runtime
                                                experimentHash
                                                "tune-trials"
                                                transcriptPayload
                                            stored <-
                                              publisherWriteCompletedWeightCheckpoint
                                                runtime
                                                completed
                                                experimentHash
                                                "tune-trial-weights"
                                                trialsCompleted
                                                metricRows
                                                (Tune.trialResultWeights best)
                                                [productArtifactPointer transcript]
                                            admission <-
                                              admitPublishedProductCheckpoint runtime projection completed stored
                                            pure $
                                              case admission of
                                                Left err ->
                                                  productPublishError
                                                    projection
                                                    ("tuning checkpoint storage succeeded but exact Store admission failed: " <> err)
                                                Right admitted ->
                                                  productPublishEligible
                                                    projection
                                                    admitted
                                                    [transcript]
                                                    "tuning promoted artifact and v2 transcript stored and admitted"
{-# NOINLINE trainAndPublishTuningProductRow #-}

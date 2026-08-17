{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Supervised
  ( supervisedPublishMetricRows
  , trainAndPublishSupervisedProductRow
  , validateSupervisedPublishUpdateCount
  )
where

import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Env.Env (App)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Plan.Plan
  ( RunKind (..)
  , planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSubstrate
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.Audit
  ( ProductPublishResult
  , validateProductCompletedTrainingPlanId
  )
import JitML.Product.Publisher.Common
  ( admitPublishedProductCheckpoint
  , bindProductScenarioCompletion
  , productPublishEligible
  , productPublishError
  )
import JitML.Product.Publisher.Projection
  ( intPlanValue
  , productTrainingBudgetForProjection
  , projectedRunSeed
  , requireProjectedValue
  , validateProjectionRowAssociation
  )
import JitML.Product.Publisher.Runtime
  ( ProductPublisherRuntime (..)
  , SupervisedPublishRun (..)
  )
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Training.Budget qualified as TrainingBudget

trainAndPublishSupervisedProductRow
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> ProductExperiment.SupervisedExperiment
  -> SL.CanonicalProblem
  -> App ProductPublishResult
trainAndPublishSupervisedProductRow invocation runtime row projection experiment problem =
  case ( ProductMatrix.productProjectionDescriptor projection
       , ProductMatrix.productProjectionResolvedPlan projection
       ) of
    ( ProductMatrix.SupervisedProductDescriptor
        descriptorTraining
        descriptorEvaluation
        descriptorBatch
        descriptorLearningRate
      , ProductMatrix.ResolvedSupervisedProductPlan plan
      ) -> do
        let runPlan = WorkloadPlan.supervisedPlanRunPlan plan
            planTraining = quantityValue (WorkloadPlan.supervisedPlanTrainingExamples plan)
            planEvaluation = quantityValue (WorkloadPlan.supervisedPlanEvaluationExamples plan)
            planBatch = quantityValue (WorkloadPlan.supervisedPlanBatchExamples plan)
            planEpochs = quantityValue (WorkloadPlan.supervisedPlanEpochs plan)
            planId = WorkloadPlan.supervisedPlanId plan
            seed = projectedRunSeed runPlan
            projectionValidation = do
              validateProjectionRowAssociation row projection
              requireProjectedValue "supervised training examples" descriptorTraining planTraining
              requireProjectedValue "supervised evaluation examples" descriptorEvaluation planEvaluation
              requireProjectedValue "supervised batch examples" descriptorBatch planBatch
              requireProjectedValue
                "supervised executor seed"
                (toInteger seed)
                (toInteger (SL.problemSeed problem))
              requireProjectedValue
                "supervised retained config seed"
                (toInteger seed)
                (toInteger (ProductExperiment.supervisedExperimentSeed experiment))
              requireProjectedValue
                "supervised PlanId"
                (ProductMatrix.productProjectionPlanId projection)
                planId
              productTrainingBudgetForProjection
                projection
                TrainingBudget.SupervisedEpochBudget
                planEpochs
                seed
        case projectionValidation of
          Left err -> pure (productPublishError projection err)
          Right budget -> do
            trainLimit <- intPlanValue "product supervised training examples" planTraining
            epochs <- intPlanValue "product supervised epochs" planEpochs
            testLimit <- intPlanValue "product supervised evaluation examples" planEvaluation
            batchSize <- intPlanValue "product supervised batch examples" planBatch
            trained <-
              publisherRunSupervisedTraining
                runtime
                (runPlanSubstrate runPlan)
                problem
                trainLimit
                epochs
                testLimit
                batchSize
                descriptorLearningRate
            case trained of
              Left err -> pure (productPublishError projection err)
              Right run -> do
                let experimentHash = runPlanExperimentId runPlan
                    initialBytes = supervisedPublishInitialJmw1Bytes run
                    finalBytes = supervisedPublishFinalJmw1Bytes run
                    initialSha = WeightCodec.jmw1ContentSha initialBytes
                    finalSha = WeightCodec.jmw1ContentSha finalBytes
                    datasetShaAtRead =
                      supervisedPublishVerifiedDatasetShaAtRead run
                    runtimeArtifact = do
                      validateSupervisedPublishUpdateCount plan run
                      validateTransitionalSupervisedProjections run
                      RuntimeArtifact.refineTrainingRuntimeArtifact
                        RuntimeArtifact.RawTrainingRuntimeArtifact
                          { RuntimeArtifact.rawTrainingArtifactPayload =
                              RuntimeArtifact.RawSupervisedRuntimePayload
                                { RuntimeArtifact.rawRuntimePayloadRowId =
                                    ProductMatrix.rowId row
                                , RuntimeArtifact.rawRuntimePayloadOrigin =
                                    RuntimeArtifact.RawProductRowProjectionOrigin
                                , RuntimeArtifact.rawRuntimePayloadPlanId =
                                    planIdText planId
                                , RuntimeArtifact.rawRuntimePayloadDatasetSha256 =
                                    datasetShaAtRead
                                , RuntimeArtifact.rawRuntimePayloadInitialJmw1Sha256 =
                                    initialSha
                                , RuntimeArtifact.rawRuntimePayloadFinalJmw1Sha256 =
                                    finalSha
                                , RuntimeArtifact.rawRuntimePayloadRuntime =
                                    supervisedPublishRuntimeProgram run
                                , RuntimeArtifact.rawRuntimePayloadLayerGraphMetadata =
                                    supervisedPublishLayerGraphMetadata run
                                }
                          , RuntimeArtifact.rawTrainingArtifactInitialJmw1Bytes =
                              LazyByteString.toStrict initialBytes
                          , RuntimeArtifact.rawTrainingArtifactFinalJmw1Bytes =
                              LazyByteString.toStrict finalBytes
                          }
                    completedTraining metricRows artifact = do
                      completed <-
                        publisherCompleteSupervisedProductRowWithWeightHashes
                          runtime
                          planId
                          budget
                          row
                          datasetShaAtRead
                          experimentHash
                          (supervisedPublishCompletedUnits run)
                          (supervisedPublishOptimizerUpdatesExecuted run)
                          metricRows
                          initialSha
                          finalSha
                          (supervisedPublishDeviceWitness run)
                      validateProductCompletedTrainingPlanId projection completed
                      if TrainingBudget.completedTrainingUpdateCount completed
                        == supervisedPublishOptimizerUpdatesExecuted run
                        then Right ()
                        else
                          Left
                            "completed supervised ProductRow update count differs from the training-returned executed count"
                      validateSupervisedArtifactCompletion artifact completed
                      bindProductScenarioCompletion invocation projection completed
                    validatedPublication = do
                      validateSupervisedPublishDatasetSha problem run
                      metricRows <- supervisedPublishMetricRows row plan run
                      artifact <- runtimeArtifact
                      completed <- completedTraining metricRows artifact
                      Right (metricRows, artifact, completed)
                case validatedPublication of
                  Left err ->
                    pure
                      ( productPublishError
                          projection
                          ( "supervised row did not produce an exact V2 runtime and passing CompletedTraining evidence: "
                              <> err
                          )
                      )
                  Right (metricRows, artifact, completed) -> do
                    stored <-
                      publisherWriteCompletedSupervisedCheckpoint
                        runtime
                        completed
                        experimentHash
                        metricRows
                        artifact
                    admission <-
                      admitPublishedProductCheckpoint runtime projection completed stored
                    pure $
                      case admission of
                        Left err ->
                          productPublishError
                            projection
                            ("supervised checkpoint storage succeeded but exact Store admission failed: " <> err)
                        Right admitted ->
                          productPublishEligible
                            projection
                            admitted
                            []
                            "supervised V2 runtime artifact stored and admitted"

validateSupervisedPublishUpdateCount
  :: WorkloadPlan.SupervisedPlan
  -> SupervisedPublishRun
  -> Either Text ()
validateSupervisedPublishUpdateCount plan run
  | executed == authoritative = Right ()
  | otherwise =
      Left
        ( "training-returned executed optimizer-update count does not match the authoritative supervised ProductRow plan (executed="
            <> Text.pack (show executed)
            <> ", authoritative="
            <> Text.pack (show authoritative)
            <> ")"
        )
 where
  executed = supervisedPublishOptimizerUpdatesExecuted run
  authoritative =
    quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)

-- | Close Product-origin metric evidence over the exact observations returned
-- by the supervised trainer. The names and order are publisher-owned: callers
-- cannot substitute an arbitrary metric vector. Integer arithmetic binds the
-- processed-example observation to the complete plan without overflowing the
-- platform 'Int' or the plan's bounded quantity representation.
supervisedPublishMetricRows
  :: ProductMatrix.ProductRow state
  -> WorkloadPlan.SupervisedPlan
  -> SupervisedPublishRun
  -> Either Text [(Text, Double)]
supervisedPublishMetricRows row plan run = do
  if observedExamples == expectedExamples
    then Right ()
    else
      Left
        ( "training-returned processed-example count does not match epochs * training examples (observed="
            <> Text.pack (show observedExamples)
            <> ", expected="
            <> Text.pack (show expectedExamples)
            <> ")"
        )
  heldOutMetric <-
    maybe
      (Left "supervised ProductRow publication requires exactly one held-out metric")
      Right
      (supervisedPublishHeldOutMetric run)
  let expectedHeldOutName =
        ProductConvergence.convergenceMetricName
          (ProductMatrix.convergenceBar row)
      (heldOutName, _) = heldOutMetric
  if heldOutName == expectedHeldOutName
    then Right ()
    else
      Left
        ( "training-returned held-out metric name differs from the authoritative ProductRow convergence metric (observed="
            <> heldOutName
            <> ", expected="
            <> expectedHeldOutName
            <> ")"
        )
  let metricRows =
        [ ("train_loss", supervisedPublishTrainLoss run)
        , ("validation_loss", supervisedPublishValidationLoss run)
        , ("examples_processed", fromIntegral (supervisedPublishExamplesProcessed run))
        , heldOutMetric
        ]
      metricNames = fmap fst metricRows
      expectedMetricNames =
        [ "train_loss"
        , "validation_loss"
        , "examples_processed"
        , expectedHeldOutName
        ]
  if metricNames == expectedMetricNames && length metricRows == 4
    then Right ()
    else Left "supervised ProductRow metric vector does not have the exact canonical four-row shape"
  if length metricNames == length (List.nub metricNames)
    then Right ()
    else Left "supervised ProductRow metric vector contains duplicate metric names"
  mapM_ requireFiniteMetric metricRows
  Right metricRows
 where
  observedExamples = toInteger (supervisedPublishExamplesProcessed run)
  expectedExamples =
    toInteger
      (quantityValue (WorkloadPlan.supervisedPlanEpochs plan))
      * toInteger
        (quantityValue (WorkloadPlan.supervisedPlanTrainingExamples plan))
  requireFiniteMetric (name, value)
    | isNaN value || isInfinite value =
        Left ("supervised ProductRow metric " <> name <> " must be finite")
    | otherwise = Right ()

validateSupervisedPublishDatasetSha
  :: SL.CanonicalProblem
  -> SupervisedPublishRun
  -> Either Text ()
validateSupervisedPublishDatasetSha problem run = do
  expectedSha <- Dataset.canonicalDatasetReadShaForProblem problem
  let observedSha = supervisedPublishVerifiedDatasetShaAtRead run
  if observedSha == expectedSha
    then Right ()
    else
      Left
        ( "training-returned verified dataset-at-read SHA-256 differs from the canonical problem digest (observed="
            <> observedSha
            <> ", expected="
            <> expectedSha
            <> ")"
        )

validateTransitionalSupervisedProjections
  :: SupervisedPublishRun -> Either Text ()
validateTransitionalSupervisedProjections run = do
  initialValues <-
    first
      ("initial supervised JMW1 decode failed: " <>)
      (WeightCodec.decodeJmw1 (supervisedPublishInitialJmw1Bytes run))
  finalValues <-
    first
      ("final supervised JMW1 decode failed: " <>)
      (WeightCodec.decodeJmw1 (supervisedPublishFinalJmw1Bytes run))
  requireOptionalProjection
    "initial weight list"
    initialValues
    (supervisedPublishInitialWeights run)
  requireOptionalProjection
    "final weight list"
    finalValues
    (supervisedPublishCheckpointWeights run)
  requireOptionalProjection
    "dataset-at-read SHA-256"
    (supervisedPublishVerifiedDatasetShaAtRead run)
    (supervisedPublishDatasetShaAtRead run)
 where
  requireOptionalProjection _ _ Nothing = Right ()
  requireOptionalProjection label exact (Just projected)
    | projected == exact = Right ()
    | otherwise = Left ("transitional supervised " <> label <> " disagrees with exact runtime artifact")

validateSupervisedArtifactCompletion
  :: RuntimeArtifact.TrainingRuntimeArtifact
  -> TrainingBudget.CompletedTraining
  -> Either Text ()
validateSupervisedArtifactCompletion artifact completed = do
  let payload = RuntimeArtifact.trainingArtifactPayload artifact
  requireExactBinding
    "PlanId"
    (RuntimeArtifact.payloadPlanId payload)
    (TrainingBudget.completedTrainingPlanId completed)
  requireExactBinding
    "dataset-at-read SHA-256"
    (RuntimeArtifact.payloadDatasetSha256 payload)
    (TrainingBudget.completedTrainingDatasetShaAtRead completed)
  requireExactBinding
    "initial JMW1 SHA-256"
    (RuntimeArtifact.payloadInitialJmw1Sha256 payload)
    (TrainingBudget.completedTrainingInitialWeightHash completed)
  requireExactBinding
    "final JMW1 SHA-256"
    (RuntimeArtifact.payloadFinalJmw1Sha256 payload)
    (TrainingBudget.completedTrainingFinalWeightHash completed)
 where
  requireExactBinding label expected actual
    | expected == actual = Right ()
    | otherwise = Left ("supervised runtime " <> label <> " disagrees with completed training")

{-# NOINLINE supervisedPublishMetricRows #-}
{-# NOINLINE trainAndPublishSupervisedProductRow #-}
{-# NOINLINE validateSupervisedPublishUpdateCount #-}

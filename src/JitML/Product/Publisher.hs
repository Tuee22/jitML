{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher
  ( ProductPublisherRuntime (..)
  , RlPublishRun (..)
  , SupervisedPublishRun (..)
  , TuningPublishDataset (..)
  , productTuneTrialArtifact
  , runTrainAndPublishProductRows
  , selectInternalProductRows
  , validateAdmittedProductCheckpoint
  , validateProductCompletedTrainingPlanId
  , supervisedPublishMetricRows
  , validateSupervisedPublishUpdateCount
  )
where

import Control.Monad (void, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError, writeLine, writeText)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Env.Env (App)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Numerics.Mlp (AdamState)
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate, rlDeviceForSubstrate)
import JitML.Plan.Plan
  ( PlanId
  , RunKind (..)
  , RunKindWitness (..)
  , RunPlan
  , planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanId
  , runPlanRlBudget
  , runPlanSeeds
  , runPlanSubstrate
  , seedCohortValues
  , validationToEither
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.Audit
  ( ProductArtifactReceipt (..)
  , ProductPublishDisposition (..)
  , ProductPublishResult (..)
  , productArtifactPointer
  , productPublishStatus
  , renderProductInventoryEntry
  , renderProductPublishResult
  , validateAdmittedProductCheckpoint
  , validateProductCompletedTrainingPlanId
  , validateProductPublishBatch
  )
import JitML.Product.Publisher.TuningTranscript (productTuneTrialArtifact)
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

-- | App-owned effects consumed by the ProductRow publisher.  Keeping this
-- boundary explicit lets the exact ProductRow orchestration compile in its own
-- module without creating an App/Publisher import cycle.
data ProductPublisherRuntime = ProductPublisherRuntime
  { publisherRunSupervisedTraining
      :: Substrate
      -> SL.CanonicalProblem
      -> Int
      -> Int
      -> Int
      -> Int
      -> Double
      -> App (Either Text SupervisedPublishRun)
  , publisherRunRlTraining
      :: Substrate
      -> MlpDevice
      -> Text
      -> Text
      -> Int
      -> Int
      -> Int
      -> Word64
      -> Int
      -> IO (Either Text RlPublishRun)
  , publisherCompleteProductRow
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> ProductMatrix.ProductRow 'ProductMatrix.Declared
      -> Text
      -> Text
      -> Text
      -> Word64
      -> Word64
      -> [(Text, Double)]
      -> [Double]
      -> [Double]
      -> Either Text TrainingBudget.CompletedTraining
  , publisherCompleteSupervisedProductRowWithWeightHashes
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> ProductMatrix.ProductRow 'ProductMatrix.Declared
      -> Text
      -> Text
      -> Word64
      -> Word64
      -> [(Text, Double)]
      -> Text
      -> Text
      -> Either Text TrainingBudget.CompletedTraining
  , publisherRlCompletionMetrics
      :: Text
      -> Word64
      -> [EpisodeEnvelope.SimulatedEpisode]
      -> Either Text [(Text, Double)]
  , publisherRlCompletedTraining
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> Text
      -> Text
      -> Text
      -> Text
      -> Word64
      -> [(Text, Double)]
      -> ProductEvidence.TrainingEvidence
      -> Maybe TrainingBudget.CompletedTraining
  , publisherRlCompletionFailure
      :: Text
      -> Text
      -> [(Text, Double)]
      -> Text
  , publisherAlphaZeroCompletedTraining
      :: PlanId
      -> TrainingBudget.TrainingBudget
      -> Text
      -> Word64
      -> Word64
      -> Text
      -> [(Text, Double)]
      -> [Double]
      -> [Double]
      -> Either Text TrainingBudget.CompletedTraining
  , publisherWriteCompletedWeightCheckpoint
      :: TrainingBudget.CompletedTraining
      -> Text
      -> Text
      -> Word64
      -> [(Text, Double)]
      -> [Double]
      -> [Checkpoint.ArtifactPointer]
      -> App CheckpointStore.StoredCompletedCheckpoint
  , publisherWriteCompletedSupervisedCheckpoint
      :: TrainingBudget.CompletedTraining
      -> Text
      -> [(Text, Double)]
      -> RuntimeArtifact.TrainingRuntimeArtifact
      -> App CheckpointStore.StoredCompletedCheckpoint
  , publisherAdmitCompletedCheckpoint
      :: Text
      -> CheckpointStore.StoredCompletedCheckpoint
      -> App
           ( Either
               CheckpointStore.CheckpointAdmissionError
               CheckpointStore.AdmittedCompletedCheckpoint
           )
  , publisherWriteTextArtifact :: Text -> Text -> Text -> App (Text, Text)
  , publisherLoadTuningDataset
      :: Tune.TuningExecutionSpec
      -> App (Either Text TuningPublishDataset)
  }

data SupervisedPublishRun = SupervisedPublishRun
  { supervisedPublishTrainLoss :: !Double
  , supervisedPublishValidationLoss :: !Double
  , supervisedPublishExamplesProcessed :: !Int
  , supervisedPublishHeldOutMetric :: !(Maybe (Text, Double))
  , supervisedPublishCompletedUnits :: !Word64
  , supervisedPublishOptimizerUpdatesExecuted :: !Word64
  , supervisedPublishRuntimeProgram :: !RuntimeArtifact.RawSupervisedRuntime
  , supervisedPublishInitialJmw1Bytes :: !LazyByteString.ByteString
  , supervisedPublishFinalJmw1Bytes :: !LazyByteString.ByteString
  , supervisedPublishVerifiedDatasetShaAtRead :: !Text
  , -- Transitional projections are retained for callers which still display
    -- lists.  The publisher never reconstructs V2 identity from them; when a
    -- projection is present it must agree exactly with the canonical bytes.
    supervisedPublishInitialWeights :: !(Maybe [Double])
  , supervisedPublishCheckpointWeights :: !(Maybe [Double])
  , supervisedPublishDatasetShaAtRead :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data RlPublishRun = RlPublishRun
  { rlPublishEpisodes :: ![EpisodeEnvelope.SimulatedEpisode]
  , rlPublishObservedUnits :: !Word64
  , rlPublishWeights :: !(Maybe [Double])
  , rlPublishEvidence :: !(Maybe ProductEvidence.TrainingEvidence)
  }
  deriving stock (Eq, Show)

data TuningPublishDataset = TuningPublishDataset
  { tuningPublishProblem :: !SL.CanonicalProblem
  , tuningPublishBaseConfig :: !Classifier.ClassifierConfig
  , tuningPublishTrainSet :: !Classifier.Dataset
  , tuningPublishValidationSet :: !Classifier.Dataset
  , tuningPublishDatasetShaAtRead :: !Text
  }
  deriving stock (Eq, Show)

data PreparedProductProjection where
  PreparedProductProjection
    :: ProductMatrix.ProductRow 'ProductMatrix.Declared
    -> RunKindWitness kind
    -> ProductMatrix.ProductProjection kind
    -> ProductExperiment.PreparedProductExperiment kind
    -> PreparedProductProjection

runTrainAndPublishProductRows
  :: ProductPublisherRuntime
  -> Substrate
  -> [ProductMatrix.ProductRow 'ProductMatrix.Declared]
  -> App ()
runTrainAndPublishProductRows runtime substrate selectedRows = do
  projectedBatch <-
    case validationToEither (ProductMatrix.projectProductRows substrate selectedRows) of
      Left errors ->
        exitWithError
          ( InvalidConfig
              ( Text.unlines
                  ( "train-and-publish-product-rows projection failed:"
                      : fmap
                        (("- " <>) . ProductMatrix.renderProductMatrixError)
                        (NonEmpty.toList errors)
                  )
              )
          )
      Right batch -> pure batch
  let projectedRows = ProductMatrix.productProjectionBatchProjections projectedBatch
      projectedIds = ProductMatrix.productProjectionBatchRowIds projectedBatch
      selectedIds = fmap ProductMatrix.rowId selectedRows
  when
    ( ProductMatrix.productProjectionBatchSubstrate projectedBatch /= substrate
        || projectedIds /= selectedIds
        || length projectedRows /= length selectedRows
    )
    ( exitWithError
        ( InvalidConfig
            "train-and-publish-product-rows projection batch did not preserve the selected row/substrate identity"
        )
    )
  executionResult <-
    ProductExperiment.preflightAllThenExecute
      (\(row, projection) -> liftIO (prepareProductProjection row projection))
      ( \prepared@(PreparedProductProjection row _ _ _) -> do
          writeLine ("train-and-publish-product-rows: row=" <> ProductMatrix.rowId row)
          trainAndPublishProductProjection runtime prepared
      )
      (zip selectedRows projectedRows)
  results <-
    case executionResult of
      Left preparationErrors ->
        exitWithError
          ( InvalidConfig
              ( Text.unlines
                  ( "train-and-publish-product-rows experiment preflight failed before execution:"
                      : fmap ("- " <>) preparationErrors
                  )
              )
          )
      Right values -> pure values
  let eligibleCount = length [() | result <- results, productPublishStatus result == "eligible"]
      unsupportedCount = length [() | result <- results, productPublishStatus result == "unsupported"]
      errorCount = length [() | result <- results, productPublishStatus result == "error"]
      tuningTranscriptCount =
        length
          [ ()
          | result <- results
          , receipt <- productPublishArtifacts result
          , productArtifactKind receipt == "tune-trials"
          ]
      inventoryLines = concatMap renderProductInventoryEntry results
      auditResult = validateProductPublishBatch projectedBatch results
  writeText $
    Text.unlines
      ( [ "train-and-publish-product-rows: substrate=" <> renderSubstrate substrate
        , "rows: " <> Text.pack (show (length results))
        , "eligible: " <> Text.pack (show eligibleCount)
        , "unsupported: " <> Text.pack (show unsupportedCount)
        , "errors: " <> Text.pack (show errorCount)
        , "admitted-inventory-entries: " <> Text.pack (show eligibleCount)
        , "tune-trials-v2-transcripts: " <> Text.pack (show tuningTranscriptCount)
        ]
          <> fmap renderProductPublishResult results
          <> inventoryLines
      )
  case auditResult of
    Left err ->
      exitWithError
        (InvalidConfig ("train-and-publish-product-rows admitted inventory audit failed: " <> err))
    Right () -> pure ()
{-# NOINLINE runTrainAndPublishProductRows #-}

prepareProductProjection
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.SomeProductProjection
  -> IO (Either Text PreparedProductProjection)
prepareProductProjection row (ProductMatrix.SomeProductProjection witness projection) = do
  preparedE <- ProductExperiment.prepareProductExperiment projection
  pure $ do
    prepared <-
      first
        (\err -> ProductMatrix.rowId row <> ": " <> err)
        preparedE
    validatePreparedProductExperiment row witness projection prepared
    Right (PreparedProductProjection row witness projection prepared)

validatePreparedProductExperiment
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> RunKindWitness kind
  -> ProductMatrix.ProductProjection kind
  -> ProductExperiment.PreparedProductExperiment kind
  -> Either Text ()
validatePreparedProductExperiment row witness projection prepared = do
  first ((ProductMatrix.rowId row <> ": ") <>) (validateProjectionRowAssociation row projection)
  case witness of
    HyperparameterTuningWitness ->
      case ProductMatrix.productProjectionResolvedPlan projection of
        ProductMatrix.ResolvedTuningProductPlan plan ->
          void
            ( validateTuningProductExperiment
                plan
                (projectedRunSeed (WorkloadPlan.tuningPlanRunPlan plan))
                ( ProductExperiment.ProductTuningExperiment
                    (ProductExperiment.preparedTuningProductExperiment prepared)
                )
            )
    _ -> Right ()

selectInternalProductRows
  :: Maybe Text
  -> Maybe Text
  -> Either Text [ProductMatrix.ProductRow 'ProductMatrix.Declared]
selectInternalProductRows commandRow environmentFilter =
  case commandRow of
    Nothing -> ProductMatrix.selectProductRows normalizedEnvironmentFilter
    Just rowIdentity -> do
      selected <- ProductMatrix.selectProductRows (Just rowIdentity)
      case selected of
        [row]
          | ProductMatrix.rowId row == rowIdentity ->
              case normalizedEnvironmentFilter of
                Nothing -> Right selected
                Just rawFilter -> do
                  environmentSelected <- ProductMatrix.selectProductRows (Just rawFilter)
                  let environmentIds = fmap ProductMatrix.rowId environmentSelected
                  if environmentIds == [rowIdentity]
                    then Right selected
                    else
                      Left
                        ( "--row "
                            <> rowIdentity
                            <> " conflicts with JITML_PRODUCT_ROW_FILTER (selected: "
                            <> Text.intercalate ", " environmentIds
                            <> ")"
                        )
        _ ->
          Left "--row must name exactly one canonical ProductRow (comma-separated row lists are not accepted)"
 where
  normalizedEnvironmentFilter =
    environmentFilter >>= \raw ->
      if Text.null (Text.strip raw)
        then Nothing
        else Just raw

trainAndPublishProductProjection
  :: ProductPublisherRuntime
  -> PreparedProductProjection
  -> App ProductPublishResult
trainAndPublishProductProjection runtime (PreparedProductProjection row witness projection prepared) =
  case witness of
    SupervisedTrainingWitness ->
      let (experiment, problem) = ProductExperiment.preparedSupervisedProductExperiment prepared
       in trainAndPublishSupervisedProductRow runtime row projection experiment problem
    ReinforcementLearningWitness ->
      trainAndPublishRlProductRow runtime row projection
    HyperparameterTuningWitness ->
      trainAndPublishTuningProductRow
        runtime
        row
        projection
        (ProductExperiment.preparedTuningProductExperiment prepared)
    AlphaZeroSelfPlayWitness ->
      trainAndPublishAlphaZeroProductRow runtime row projection

trainAndPublishSupervisedProductRow
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> ProductExperiment.SupervisedExperiment
  -> SL.CanonicalProblem
  -> App ProductPublishResult
trainAndPublishSupervisedProductRow runtime row projection experiment problem =
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
                      validateProductCompletedTrainingPlanId projection completed
                      if TrainingBudget.completedTrainingUpdateCount completed
                        == supervisedPublishOptimizerUpdatesExecuted run
                        then Right ()
                        else
                          Left
                            "completed supervised ProductRow update count differs from the training-returned executed count"
                      validateSupervisedArtifactCompletion artifact completed
                      Right completed
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

trainAndPublishRlProductRow
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'ReinforcementLearning
  -> App ProductPublishResult
trainAndPublishRlProductRow runtime row projection =
  case ( ProductMatrix.productProjectionDescriptor projection
       , ProductMatrix.productProjectionResolvedPlan projection
       ) of
    ( descriptor@ProductMatrix.RlProductDescriptor {}
      , ProductMatrix.ResolvedRlProductPlan runPlan
      ) ->
        case projectedRlExecution row projection descriptor runPlan of
          Left err -> pure (productPublishError projection err)
          Right execution ->
            let trainerKind = projectedRlTrainerKind execution
                environment = projectedRlEnvironment execution
                substrate = projectedRlSubstrate execution
                seed = projectedRlSeed execution
                evaluationEpisodes = projectedRlEvaluationEpisodes execution
                episodeSteps = projectedRlEpisodeSteps execution
                targetTransitions = projectedRlTargetTransitions execution
                vectorEnvironments = projectedRlVectorEnvironments execution
                budget = projectedRlTrainingBudget execution
             in case ProductBudget.rlTrainerEnvironmentCompatibilityError trainerKind environment of
                  Just err -> pure (productPublishUnsupported projection err)
                  Nothing -> do
                    env <- ask
                    trainerRunE <-
                      liftIO
                        ( publisherRunRlTraining
                            runtime
                            substrate
                            (rlDeviceForSubstrate substrate env)
                            trainerKind
                            environment
                            seed
                            evaluationEpisodes
                            episodeSteps
                            targetTransitions
                            vectorEnvironments
                        )
                    case trainerRunE of
                      Left err -> pure (productPublishError projection err)
                      Right trainerRun ->
                        case (rlPublishWeights trainerRun, rlPublishEvidence trainerRun) of
                          (Just weights, Just evidence) -> do
                            let experimentHash = runPlanExperimentId runPlan
                                tensorName = "rl-" <> Text.toLower trainerKind <> "-weights"
                            case publisherRlCompletionMetrics
                              runtime
                              trainerKind
                              (rlPublishObservedUnits trainerRun)
                              (rlPublishEpisodes trainerRun) of
                              Left err -> pure (productPublishError projection err)
                              Right metrics -> do
                                let checkpointStep = rlPublishObservedUnits trainerRun
                                    completedTraining = do
                                      completed <-
                                        maybe
                                          ( Left
                                              ( publisherRlCompletionFailure
                                                  runtime
                                                  trainerKind
                                                  environment
                                                  metrics
                                              )
                                          )
                                          Right
                                          ( publisherRlCompletedTraining
                                              runtime
                                              (ProductMatrix.productProjectionPlanId projection)
                                              budget
                                              trainerKind
                                              environment
                                              experimentHash
                                              tensorName
                                              checkpointStep
                                              metrics
                                              evidence
                                          )
                                      validateProductCompletedTrainingPlanId projection completed
                                      Right completed
                                case completedTraining of
                                  Left err -> pure (productPublishError projection err)
                                  Right completed -> do
                                    trajectory <-
                                      writeProductTextArtifact
                                        runtime
                                        experimentHash
                                        "rl-trajectory"
                                        ( renderRlTrajectoryArtifact
                                            experimentHash
                                            environment
                                            trainerKind
                                            seed
                                            (rlPublishEpisodes trainerRun)
                                        )
                                    stored <-
                                      publisherWriteCompletedWeightCheckpoint
                                        runtime
                                        completed
                                        experimentHash
                                        tensorName
                                        checkpointStep
                                        metrics
                                        weights
                                        [productArtifactPointer trajectory]
                                    admission <-
                                      admitPublishedProductCheckpoint runtime projection completed stored
                                    pure $
                                      case admission of
                                        Left err ->
                                          productPublishError
                                            projection
                                            ("RL checkpoint storage succeeded but exact Store admission failed: " <> err)
                                        Right admitted ->
                                          productPublishEligible
                                            projection
                                            admitted
                                            [trajectory]
                                            "RL policy artifact and trajectory stored and admitted"
                          _ ->
                            pure
                              (productPublishUnsupported projection "RL row produced no checkpointable policy weights")

trainAndPublishAlphaZeroProductRow
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'AlphaZeroSelfPlay
  -> App ProductPublishResult
trainAndPublishAlphaZeroProductRow runtime row projection =
  case ( ProductMatrix.productProjectionDescriptor projection
       , ProductMatrix.productProjectionResolvedPlan projection
       ) of
    ( ProductMatrix.AlphaZeroProductDescriptor
        descriptorGame
        descriptorGames
        descriptorSims
        descriptorMaxPlies
        descriptorUpdates
        descriptorArenaGames
      , ProductMatrix.ResolvedAlphaZeroProductPlan plan
      ) -> do
        let runPlan = WorkloadPlan.alphaZeroPlanRunPlan plan
            game = WorkloadPlan.renderAlphaZeroGame (WorkloadPlan.alphaZeroPlanGame plan)
            generationTargetWord = quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan)
            gamesWord = quantityValue (WorkloadPlan.alphaZeroPlanSelfPlayGames plan)
            simsWord = quantityValue (WorkloadPlan.alphaZeroPlanMctsSimulations plan)
            maxPliesWord = quantityValue (WorkloadPlan.alphaZeroPlanMaxPlies plan)
            updatesWord = quantityValue (WorkloadPlan.alphaZeroPlanUpdates plan)
            arenaGamesWord = quantityValue (WorkloadPlan.alphaZeroPlanArenaGames plan)
            seedWord = projectedRunSeed runPlan
            projectionValidation = do
              validateProjectionRowAssociation row projection
              requireProjectedValue "AlphaZero game" descriptorGame game
              requireProjectedValue "AlphaZero self-play games" descriptorGames gamesWord
              requireProjectedValue "AlphaZero simulations" descriptorSims simsWord
              requireProjectedValue "AlphaZero maximum plies" descriptorMaxPlies maxPliesWord
              requireProjectedValue "AlphaZero optimizer updates" descriptorUpdates updatesWord
              requireProjectedValue "AlphaZero arena games" descriptorArenaGames arenaGamesWord
              requireProjectedValue
                "AlphaZero PlanId"
                (ProductMatrix.productProjectionPlanId projection)
                (WorkloadPlan.alphaZeroPlanId plan)
              productTrainingBudgetForProjection
                projection
                TrainingBudget.AlphaZeroSelfPlayBudget
                generationTargetWord
                seedWord
        case projectionValidation of
          Left err -> pure (productPublishError projection err)
          Right budget -> do
            generationTarget <- intPlanValue "product AlphaZero generations" generationTargetWord
            games <- intPlanValue "product AlphaZero self-play games" gamesWord
            sims <- intPlanValue "product AlphaZero simulations" simsWord
            maxPlies <- intPlanValue "product AlphaZero maximum plies" maxPliesWord
            updates <- intPlanValue "product AlphaZero optimizer updates" updatesWord
            arenaGames <- intPlanValue "product AlphaZero arena games" arenaGamesWord
            seed <- intPlanValue "product AlphaZero seed" seedWord
            env <- ask
            let substrate = runPlanSubstrate runPlan
                device = rlDeviceForSubstrate substrate env
                initialState = AlphaZero.initialStateFor game
                observationSize = AlphaZero.observationSizeFor game
                actionCount = AlphaZero.actionCountFor game
                net0 = PolicyValueNet.initPolicyValueNet observationSize actionCount 16 seed
                adam0 = PolicyValueNet.initAdamFor net0
            probe <- liftIO (probeMlpDevice device)
            case probe of
              Left err ->
                pure (productPublishError projection ("AlphaZero substrate device unavailable: " <> err))
              Right () -> do
                generationResult <-
                  liftIO $
                    trainAlphaZeroGenerationsWithDevice
                      device
                      initialState
                      net0
                      adam0
                      generationTarget
                      games
                      sims
                      maxPlies
                      updates
                      seed
                case generationResult of
                  Left err -> pure (productPublishError projection ("AlphaZero self-play failed: " <> err))
                  Right (trainedNet, samples, generationCount)
                    | generationCount /= generationTarget ->
                        pure
                          ( productPublishError
                              projection
                              ( "AlphaZero executor completed "
                                  <> Text.pack (show generationCount)
                                  <> " generations; resolved budget requires "
                                  <> Text.pack (show generationTarget)
                              )
                          )
                    | null samples -> pure (productPublishError projection "AlphaZero self-play produced no samples")
                    | otherwise -> do
                        let winRate =
                              PolicyValueNet.arenaWinRateAgainstUniformFrom
                                initialState
                                trainedNet
                                arenaGames
                                maxPlies
                                (seed + 7919)
                            experimentHash = runPlanExperimentId runPlan
                            completedGenerations = fromIntegral generationCount
                            checkpointStep = completedGenerations
                            metrics =
                              [ ("arena_win_rate", winRate)
                              , ("legal_move_rate", 1.0)
                              , ("mcts_simulations_per_move", fromIntegral sims)
                              , ("self_play_games", fromIntegral games)
                              , ("self_play_generations", fromIntegral generationCount)
                              , ("self_play_samples", fromIntegral (length samples))
                              ]
                            initialWeights = PolicyValueNet.policyValueNetToFlat net0
                            finalWeights = PolicyValueNet.policyValueNetToFlat trainedNet
                            sampleDigest = PolicyValueNet.policyValueTrainingSamplesSha256 samples
                            completedTraining = do
                              updatesPerGeneration <-
                                checkedPositiveWord64FromInt
                                  "AlphaZero optimizer updates per generation"
                                  updates
                              optimizerUpdateCount <-
                                checkedWord64Product
                                  "AlphaZero optimizer update evidence"
                                  completedGenerations
                                  updatesPerGeneration
                              completed <-
                                publisherAlphaZeroCompletedTraining
                                  runtime
                                  (WorkloadPlan.alphaZeroPlanId plan)
                                  budget
                                  experimentHash
                                  completedGenerations
                                  optimizerUpdateCount
                                  sampleDigest
                                  metrics
                                  initialWeights
                                  finalWeights
                              validateProductCompletedTrainingPlanId projection completed
                              Right completed
                        case completedTraining of
                          Left err -> pure (productPublishError projection err)
                          Right completed -> do
                            transcript <-
                              writeProductTextArtifact
                                runtime
                                experimentHash
                                "alphazero-transcript"
                                (renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples)
                            stored <-
                              publisherWriteCompletedWeightCheckpoint
                                runtime
                                completed
                                experimentHash
                                ("alphazero-" <> game <> "-policy-value-weights")
                                checkpointStep
                                metrics
                                finalWeights
                                [productArtifactPointer transcript]
                            admission <-
                              admitPublishedProductCheckpoint runtime projection completed stored
                            pure $
                              case admission of
                                Left err ->
                                  productPublishError
                                    projection
                                    ("AlphaZero checkpoint storage succeeded but exact Store admission failed: " <> err)
                                Right admitted ->
                                  productPublishEligible
                                    projection
                                    admitted
                                    [transcript]
                                    "AlphaZero policy-value artifact and transcript stored and admitted"

trainAlphaZeroGenerationsWithDevice
  :: MlpDevice
  -> AlphaZero.GameState
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> IO (Either Text (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample], Int))
trainAlphaZeroGenerationsWithDevice device initialState net0 adam0 generationTarget games sims maxPlies updates seed =
  go 0 net0 adam0 []
 where
  go generation net adam allSamples
    | generation >= generationTarget =
        pure (Right (net, allSamples, generation))
    | otherwise = do
        sampleResults <-
          traverse
            ( \gameIndex ->
                PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                  initialState
                  device
                  net
                  (seed + generation * 7919 + gameIndex)
                  sims
                  maxPlies
            )
            [0 .. games - 1]
        case sequence sampleResults of
          Left err -> pure (Left err)
          Right batches -> do
            let generationSamples = concat batches
            trainedE <-
              PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
                device
                net
                adam
                1.0e-3
                updates
                generationSamples
            case trainedE of
              Left err -> pure (Left err)
              Right (trainedNet, trainedAdam) ->
                go (generation + 1) trainedNet trainedAdam (allSamples <> generationSamples)

trainAndPublishTuningProductRow
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'HyperparameterTuning
  -> Tune.TuningExperiment
  -> App ProductPublishResult
trainAndPublishTuningProductRow runtime row projection experiment =
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
                                          Right completed
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

data ProjectedRlExecution = ProjectedRlExecution
  { projectedRlTrainerKind :: !Text
  , projectedRlEnvironment :: !Text
  , projectedRlSubstrate :: !Substrate
  , projectedRlSeed :: !Int
  , projectedRlEvaluationEpisodes :: !Int
  , projectedRlEpisodeSteps :: !Int
  , projectedRlTargetTransitions :: !Word64
  , projectedRlVectorEnvironments :: !Int
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
      descriptorEvaluation
      descriptorUpdates -> do
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
              , updatesQuantity
              ) =
                runPlanRlBudget runPlan
            transitions = quantityValue transitionsQuantity
            rolloutTicks = quantityValue rolloutQuantity
            vectorEnvironmentsWord = quantityValue vectorQuantity
            episodeStepsWord = quantityValue episodeQuantity
            evaluationEpisodesWord = quantityValue evaluationQuantity
            optimizerUpdates = quantityValue updatesQuantity
            seedWord = projectedRunSeed runPlan
            trainerKind = ProductBudget.trainerKindForAlgorithm algorithm
        requireProjectedValue "RL rollout ticks per environment" descriptorRollout rolloutTicks
        requireProjectedValue "RL vector environments" descriptorVectors vectorEnvironmentsWord
        requireProjectedValue "RL episode steps" descriptorEpisode episodeStepsWord
        requireProjectedValue "RL evaluation episodes" descriptorEvaluation evaluationEpisodesWord
        requireProjectedValue "RL optimizer updates" descriptorUpdates optimizerUpdates
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
        schedule <-
          ProductBudget.planExactRlTrainingSchedule
            trainerKind
            environment
            evaluationEpisodes
            episodeSteps
            (Just vectorEnvironments)
            transitions
        validateProjectedRlSchedule
          rolloutTicks
          vectorEnvironmentsWord
          episodeStepsWord
          optimizerUpdates
          schedule
        Right
          ProjectedRlExecution
            { projectedRlTrainerKind = trainerKind
            , projectedRlEnvironment = environment
            , projectedRlSubstrate = runPlanSubstrate runPlan
            , projectedRlSeed = seed
            , projectedRlEvaluationEpisodes = evaluationEpisodes
            , projectedRlEpisodeSteps = episodeSteps
            , projectedRlTargetTransitions = transitions
            , projectedRlVectorEnvironments = vectorEnvironments
            , projectedRlTrainingBudget = budget
            }

validateProjectedRlSchedule
  :: Word64
  -> Word64
  -> Word64
  -> Word64
  -> ProductBudget.RlTrainingSchedule
  -> Either Text ()
validateProjectedRlSchedule rolloutTicks vectorEnvironments episodeSteps optimizerUpdates schedule =
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
      requireProjectedValue
        "RL scheduled optimizer updates"
        optimizerUpdates
        (fromIntegral (ProductBudget.scheduleOnPolicyIterations schedule))
    ProductBudget.FixedStepTrainingSchedule {} -> do
      requireProjectedValue "RL scheduled rollout ticks" rolloutTicks 1
      requireProjectedValue "RL scheduled vector environments" vectorEnvironments 1
      requireProjectedValue
        "RL scheduled episode steps"
        episodeSteps
        (fromIntegral (ProductBudget.scheduleFixedMaxEpisodeSteps schedule))
      requireProjectedValue
        "RL scheduled optimizer updates"
        optimizerUpdates
        (fromIntegral (ProductBudget.scheduleFixedSteps schedule))
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
      requireProjectedValue
        "RL scheduled optimizer updates"
        optimizerUpdates
        (fromIntegral (ProductBudget.scheduleArsIterations schedule))
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
      requireProjectedValue
        "RL scheduled optimizer updates"
        optimizerUpdates
        (fromIntegral (ProductBudget.scheduleHerEpisodes schedule))

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

admitPublishedProductCheckpoint
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductProjection kind
  -> TrainingBudget.CompletedTraining
  -> CheckpointStore.StoredCompletedCheckpoint
  -> App (Either Text CheckpointStore.AdmittedCompletedCheckpoint)
admitPublishedProductCheckpoint runtime projection completed stored = do
  admission <-
    publisherAdmitCompletedCheckpoint
      runtime
      (ProductMatrix.productProjectionExperimentHash projection)
      stored
  pure $ do
    admitted <- first CheckpointStore.renderCheckpointAdmissionError admission
    validateAdmittedProductCheckpoint projection completed stored admitted
    Right admitted

writeProductTextArtifact
  :: ProductPublisherRuntime
  -> Text
  -> Text
  -> Text
  -> App ProductArtifactReceipt
writeProductTextArtifact runtime experimentHash kind payload = do
  (sha, objectKey) <- publisherWriteTextArtifact runtime experimentHash kind payload
  pure
    ProductArtifactReceipt
      { productArtifactExperimentHash = experimentHash
      , productArtifactKind = kind
      , productArtifactSha = sha
      , productArtifactObjectKey = objectKey
      }

productPublishEligible
  :: ProductMatrix.ProductProjection kind
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> [ProductArtifactReceipt]
  -> Text
  -> ProductPublishResult
productPublishEligible projection admitted artifacts message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.productProjectionRowId projection
    , productPublishExperimentHash = ProductMatrix.productProjectionExperimentHash projection
    , productPublishDisposition = ProductPublishEligible admitted
    , productPublishArtifacts = artifacts
    , productPublishMessage = message
    }

productPublishUnsupported :: ProductMatrix.ProductProjection kind -> Text -> ProductPublishResult
productPublishUnsupported projection message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.productProjectionRowId projection
    , productPublishExperimentHash = ProductMatrix.productProjectionExperimentHash projection
    , productPublishDisposition = ProductPublishUnsupported message
    , productPublishArtifacts = []
    , productPublishMessage = message
    }

productPublishError :: ProductMatrix.ProductProjection kind -> Text -> ProductPublishResult
productPublishError projection message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.productProjectionRowId projection
    , productPublishExperimentHash = ProductMatrix.productProjectionExperimentHash projection
    , productPublishDisposition = ProductPublishError message
    , productPublishArtifacts = []
    , productPublishMessage = message
    }

renderRlTrajectoryArtifact
  :: Text
  -> Text
  -> Text
  -> Int
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Text
renderRlTrajectoryArtifact experimentHash environment trainer seed episodes =
  Text.unlines $
    [ "kind: rl-trajectory-v1"
    , "experiment-hash: " <> experimentHash
    , "environment: " <> environment
    , "trainer: " <> trainer
    , "seed: " <> Text.pack (show seed)
    , "episodes: " <> Text.pack (show (length episodes))
    ]
      <> concatMap renderEpisode episodes
 where
  renderEpisode episode =
    [ "episode: " <> Text.pack (show (EpisodeEnvelope.simEpisodeIndex episode))
    , "episode-steps: " <> Text.pack (show (EpisodeEnvelope.simEpisodeSteps episode))
    , "episode-reward: " <> Text.pack (show (EpisodeEnvelope.simEpisodeReward episode))
    , "episode-done: " <> Text.pack (show (EpisodeEnvelope.simEpisodeDone episode))
    , "episode-frame-count: "
        <> Text.pack (show (length (EpisodeEnvelope.simEpisodeFrames episode)))
    ]
      <> concatMap renderFrame (EpisodeEnvelope.simEpisodeFrames episode)
  renderFrame frame =
    [ "frame-episode: " <> Text.pack (show (EpisodeEnvelope.simFrameEpisodeIndex frame))
    , "frame-step: " <> Text.pack (show (EpisodeEnvelope.simFrameStepIndex frame))
    , "frame-action: " <> Text.pack (show (EpisodeEnvelope.simFrameAction frame))
    , "frame-reward: " <> Text.pack (show (EpisodeEnvelope.simFrameReward frame))
    , "frame-done: " <> Text.pack (show (EpisodeEnvelope.simFrameDone frame))
    , "frame-observation: " <> Text.pack (show (EpisodeEnvelope.simFrameObservation frame))
    , "frame-next-observation: "
        <> Text.pack (show (EpisodeEnvelope.simFrameNextObservation frame))
    , "frame-action-probabilities: "
        <> Text.pack (show (EpisodeEnvelope.simFrameActionProbabilities frame))
    , "frame-caption: " <> EpisodeEnvelope.simFrameCaption frame
    ]

renderAlphaZeroTranscriptArtifact
  :: Text
  -> Int
  -> Int
  -> Int
  -> [PolicyValueNet.PolicyValueTrainingSample]
  -> Text
renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples =
  Text.unlines $
    [ "kind: alphazero-transcript-v1"
    , "experiment-hash: " <> experimentHash
    , "game: " <> maybe "unknown" (AlphaZero.gameName . PolicyValueNet.sampleState) (listToMaybe samples)
    , "seed: " <> Text.pack (show seed)
    , "mcts-sims: " <> Text.pack (show sims)
    , "max-plies: " <> Text.pack (show maxPlies)
    , "samples: " <> Text.pack (show (length samples))
    ]
      <> concatMap renderSample (zip [0 :: Int ..] samples)
 where
  renderSample (index, sample) =
    [ "sample: " <> Text.pack (show index)
    , "state: " <> Text.pack (show (PolicyValueNet.sampleState sample))
    , "visit-distribution: "
        <> Text.pack (show (VU.toList (PolicyValueNet.sampleVisitDist sample)))
    , "outcome: " <> Text.pack (show (PolicyValueNet.sampleOutcome sample))
    ]

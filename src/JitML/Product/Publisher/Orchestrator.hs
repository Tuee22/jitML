{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Orchestrator
  ( runTrainAndPublishProductRows
  , runTrainAndPublishProductRowsForInvocation
  , selectInternalProductRows
  )
where

import Control.Monad (void, when)
import Control.Monad.IO.Class (liftIO)
import Data.Bifunctor (first)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError, writeLine, writeText)
import JitML.Env.Env (App)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Plan.Plan
  ( RunKindWitness (..)
  , validationToEither
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.AlphaZero (trainAndPublishAlphaZeroProductRow)
import JitML.Product.Publisher.Audit
  ( ProductArtifactReceipt (..)
  , ProductPublishResult (..)
  , productPublishStatus
  , renderProductInventoryEntry
  , renderProductPublishResult
  , validateAdmittedProjectionIdentity
  , validateProductPublishBatch
  )
import JitML.Product.Publisher.Common
  ( reuseProductPublishResult
  , validateProductScenarioInvocation
  )
import JitML.Product.Publisher.Projection
  ( projectedRunSeed
  , validateProjectionRowAssociation
  , validateTuningProductExperiment
  )
import JitML.Product.Publisher.RL (trainAndPublishRlProductRow)
import JitML.Product.Publisher.Runtime (ProductPublisherRuntime (..))
import JitML.Product.Publisher.Supervised (trainAndPublishSupervisedProductRow)
import JitML.Product.Publisher.Tuning (trainAndPublishTuningProductRow)
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget

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
  runTrainAndPublishProductRowsWithInvocation Nothing runtime substrate selectedRows
{-# NOINLINE runTrainAndPublishProductRows #-}

-- | ProductScenario-only entry point.  The opaque invocation is checked
-- against the sole projected row, disables deterministic checkpoint reuse,
-- and is attached to the completed proof before the checkpoint writer sees
-- it.
runTrainAndPublishProductRowsForInvocation
  :: TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> Substrate
  -> [ProductMatrix.ProductRow 'ProductMatrix.Declared]
  -> App ()
runTrainAndPublishProductRowsForInvocation invocation =
  runTrainAndPublishProductRowsWithInvocation (Just invocation)
{-# NOINLINE runTrainAndPublishProductRowsForInvocation #-}

runTrainAndPublishProductRowsWithInvocation
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> Substrate
  -> [ProductMatrix.ProductRow 'ProductMatrix.Declared]
  -> App ()
runTrainAndPublishProductRowsWithInvocation invocation runtime substrate selectedRows = do
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
  case invocation of
    Nothing -> pure ()
    Just invoked ->
      case projectedRows of
        [ProductMatrix.SomeProductProjection _ projection] ->
          case validateProductScenarioInvocation projection invoked of
            Left err ->
              exitWithError
                (InvalidConfig ("ProductScenario invocation does not match projected row: " <> err))
            Right () -> pure ()
        _ ->
          exitWithError
            (InvalidConfig "ProductScenario invocation requires exactly one projected ProductRow")
  executionResult <-
    ProductExperiment.preflightAllThenExecute
      (\(row, projection) -> liftIO (prepareProductProjection row projection))
      ( \prepared@(PreparedProductProjection row _ _ _) -> do
          writeLine ("train-and-publish-product-rows: row=" <> ProductMatrix.rowId row)
          trainAndPublishProductProjection invocation runtime prepared
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
{-# NOINLINE runTrainAndPublishProductRowsWithInvocation #-}

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
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> PreparedProductProjection
  -> App ProductPublishResult
trainAndPublishProductProjection invocation runtime prepared@(PreparedProductProjection _ _ projection _) = do
  reuse <- case invocation of
    -- A ProductScenario invocation proves work from this command execution;
    -- an otherwise valid deterministic checkpoint from an earlier run cannot
    -- satisfy it.
    Just _ -> pure Nothing
    Nothing ->
      publisherReuseAdmittedCheckpoint
        runtime
        (ProductMatrix.productProjectionExperimentHash projection)
  case reuse of
    Just admitted
      | Right () <- validateAdmittedProjectionIdentity projection admitted ->
          pure (reuseProductPublishResult projection admitted)
    _ -> trainAndPublishProductProjectionFresh invocation runtime prepared

-- | Reconstruct the eligible publish result from a re-admitted checkpoint
-- without re-training.  The companion receipts are read back from the admitted
-- manifest's own transcript pointers, so they equal what a fresh publish would
-- have bound and the batch audit's pointer/kind equalities still hold.
trainAndPublishProductProjectionFresh
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> PreparedProductProjection
  -> App ProductPublishResult
trainAndPublishProductProjectionFresh invocation runtime (PreparedProductProjection row witness projection prepared) =
  case witness of
    SupervisedTrainingWitness ->
      let (experiment, problem) = ProductExperiment.preparedSupervisedProductExperiment prepared
       in trainAndPublishSupervisedProductRow invocation runtime row projection experiment problem
    ReinforcementLearningWitness ->
      trainAndPublishRlProductRow invocation runtime row projection
    HyperparameterTuningWitness ->
      trainAndPublishTuningProductRow
        invocation
        runtime
        row
        projection
        (ProductExperiment.preparedTuningProductExperiment prepared)
    AlphaZeroSelfPlayWitness ->
      trainAndPublishAlphaZeroProductRow invocation runtime row projection

{-# NOINLINE trainAndPublishProductProjection #-}
{-# NOINLINE trainAndPublishProductProjectionFresh #-}

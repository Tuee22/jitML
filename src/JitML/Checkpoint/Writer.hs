{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Writer
  ( StoredArtifact
  , SupervisedRuntimeCompletion (..)
  , admitLocalStoredCompletedCheckpoint
  , attemptGenericSupervisedRuntimeForTraining
  , checkpointTrainingBudgetForTensor
  , completedSupervisedRuntimeForTraining
  , completedTrainingForSupervisedProblem
  , localCheckpointRoot
  , renderStoredArtifactLines
  , renderStoredCheckpointLines
  , renderStoredCheckpointLinesWithPrefix
  , storedArtifactMirroredToLive
  , storedArtifactObjectKey
  , storedArtifactSha
  , validateGenericV1CandidateWriterRequest
  , validateGenericV1CompletedWriterRequest
  , writeLocalCandidateWeightCheckpoint
  , writeLocalCompletedProductWeightCheckpoint
  , writeLocalCompletedWeightCheckpoint
  , writeLocalCompletedSupervisedCheckpoint
  , writeMinIOCandidateWeightCheckpoint
  , writeMinIOCompletedWeightCheckpoint
  , writeMinIOCompletedSupervisedCheckpoint
  , writeTextArtifact
  )
where

import Control.Monad.Reader (asks, liftIO)
import Crypto.Hash.SHA256 qualified
import Data.ByteString qualified
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (traverse_)
import Data.List (find)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import Path (toFilePath)
import System.FilePath ((</>))

import JitML.AppError.AppError (AppError (..))
import JitML.Bootstrap (readExistingLivePublication)
import JitML.CLI.Output (exitWithError)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Cluster.Publication qualified as Publication
import JitML.Env.Env (App, Env (envCacheDir))
import JitML.Plan.Plan
  ( planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSeeds
  , seedCohortValues
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.SL.TrainingExecution (TrainingMetrics (..))
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Training.Budget qualified as TrainingBudget

data SupervisedRuntimeCompletion
  = SupervisedRuntimeCompletionMiss
      !(NonEmpty.NonEmpty TrainingBudget.ConvergenceObservation)
  | SupervisedRuntimeCompleted
      !TrainingBudget.CompletedTraining
      !RuntimeArtifact.TrainingRuntimeArtifact
  deriving stock (Eq, Show)

-- | Re-admit the exact immutable address returned by a completed local write.
-- A storage receipt alone is not product eligibility: callers receive opaque
-- completed evidence only after Store has re-read and rebound the addressed
-- manifest and every physical blob. The explicit stored/admitted SHA check
-- prevents a future admission implementation from silently substituting a
-- different address.
admitLocalStoredCompletedCheckpoint
  :: Text
  -> CheckpointStore.StoredCompletedCheckpoint
  -> App
       ( Either
           CheckpointStore.CheckpointAdmissionError
           CheckpointStore.AdmittedCompletedCheckpoint
       )
admitLocalStoredCompletedCheckpoint experimentHash storedCompleted = do
  checkpointRoot <- localCheckpointRoot
  let stored = CheckpointStore.completedStoredCheckpoint storedCompleted
      storedSha = CheckpointStore.storedManifestSha stored
      expectedObjectKey = Checkpoint.manifestKey experimentHash storedSha
  if CheckpointStore.storedManifestObjectKey stored /= expectedObjectKey
    then
      pure
        ( Left
            ( CheckpointStore.AdmissionStoredCheckpointMismatch
                ( "stored manifest key "
                    <> CheckpointStore.storedManifestObjectKey stored
                    <> " does not equal the experiment/address binding "
                    <> expectedObjectKey
                )
            )
        )
    else do
      admittedResult <-
        liftIO
          ( CheckpointStore.admitLocalCheckpointAt
              checkpointRoot
              experimentHash
              storedSha
          )
      pure $ do
        admitted <- admittedResult
        completed <-
          CheckpointStore.requireAdmittedCompletedCheckpoint admitted
        let admittedSha =
              CheckpointStore.admittedCheckpointManifestSha
                (CheckpointStore.admittedCompletedCheckpoint completed)
        if admittedSha == storedSha
          then Right completed
          else
            Left
              ( CheckpointStore.AdmissionStoredCheckpointMismatch
                  ( "stored manifest SHA "
                      <> storedSha
                      <> " differs from re-admitted SHA "
                      <> admittedSha
                  )
              )
{-# NOINLINE admitLocalStoredCompletedCheckpoint #-}

-- | Refine the mandatory exact runtime returned by supervised training and
-- mint the matching ProductRow completion witness from its byte identities.
-- This strict boundary is reserved for an authoritative ProductProjection;
-- callers never rebuild a completion hash from a transitional @[Double]@.
completedSupervisedRuntimeForTraining
  :: WorkloadPlan.SupervisedPlan
  -> SL.CanonicalProblem
  -> TrainingMetrics
  -> Text
  -> [(Text, Double)]
  -> Either
       Text
       (TrainingBudget.CompletedTraining, RuntimeArtifact.TrainingRuntimeArtifact)
completedSupervisedRuntimeForTraining plan problem metrics experimentHash metricRows = do
  (row, budget, artifact) <-
    supervisedRuntimeArtifactForTraining
      RuntimeArtifact.RawProductRowProjectionOrigin
      plan
      problem
      metrics
      experimentHash
      metricRows
  completed <-
    ProductCompletion.completedTrainingForProductRowWithWeightHashes
      (WorkloadPlan.supervisedPlanId plan)
      budget
      row
      (tmVerifiedDatasetShaAtRead metrics)
      experimentHash
      (tmCompletedUnits metrics)
      (tmOptimizerUpdatesExecuted metrics)
      metricRows
      (WeightCodec.jmw1ContentSha (tmInitialJmw1Bytes metrics))
      (WeightCodec.jmw1ContentSha (tmFinalJmw1Bytes metrics))
  validateCompletedSupervisedBindings
    completed
    (RuntimeArtifact.trainingArtifactPayload artifact)
    metricRows
  if TrainingBudget.completedTrainingUpdateCount completed
    == tmOptimizerUpdatesExecuted metrics
    then Right ()
    else Left "completed supervised update count differs from the training-returned executed count"
  Right (completed, artifact)
{-# NOINLINE completedSupervisedRuntimeForTraining #-}

-- | Assess a public/daemon supervised command without relabelling its exact
-- plan as a ProductRow projection.  A finite below-bar run is successful
-- training but produces no completed V2 artifact; every structural mismatch
-- remains a hard failure.
attemptGenericSupervisedRuntimeForTraining
  :: WorkloadPlan.SupervisedPlan
  -> SL.CanonicalProblem
  -> TrainingMetrics
  -> Text
  -> [(Text, Double)]
  -> Either Text SupervisedRuntimeCompletion
attemptGenericSupervisedRuntimeForTraining plan problem metrics experimentHash metricRows = do
  let planExperimentHash =
        runPlanExperimentId (WorkloadPlan.supervisedPlanRunPlan plan)
  if experimentHash == planExperimentHash
    then Right ()
    else
      Left
        ( "generic supervised checkpoint experiment does not equal the exact SupervisedPlan experiment (checkpoint="
            <> experimentHash
            <> ", plan="
            <> planExperimentHash
            <> ")"
        )
  (row, budget, artifact) <-
    supervisedRuntimeArtifactForTraining
      ( RuntimeArtifact.RawGenericSupervisedExecutionOrigin
          (SL.problemName problem)
          (WorkloadPlan.renderSupervisedPlanTransport plan)
      )
      plan
      problem
      metrics
      experimentHash
      metricRows
  attempt <-
    ProductCompletion.attemptCompletedTrainingForProductRowWithWeightHashes
      (WorkloadPlan.supervisedPlanId plan)
      budget
      row
      (tmVerifiedDatasetShaAtRead metrics)
      experimentHash
      (tmCompletedUnits metrics)
      (tmOptimizerUpdatesExecuted metrics)
      metricRows
      (WeightCodec.jmw1ContentSha (tmInitialJmw1Bytes metrics))
      (WeightCodec.jmw1ContentSha (tmFinalJmw1Bytes metrics))
  case attempt of
    ProductCompletion.SupervisedCompletionMiss observations ->
      Right (SupervisedRuntimeCompletionMiss observations)
    ProductCompletion.SupervisedCompletionPassed completed -> do
      validateCompletedSupervisedBindings
        completed
        (RuntimeArtifact.trainingArtifactPayload artifact)
        metricRows
      Right (SupervisedRuntimeCompleted completed artifact)
{-# NOINLINE attemptGenericSupervisedRuntimeForTraining #-}

supervisedRuntimeArtifactForTraining
  :: RuntimeArtifact.RawSupervisedRuntimeOrigin
  -> WorkloadPlan.SupervisedPlan
  -> SL.CanonicalProblem
  -> TrainingMetrics
  -> Text
  -> [(Text, Double)]
  -> Either
       Text
       ( ProductMatrix.ProductRow 'ProductMatrix.Declared
       , TrainingBudget.TrainingBudget
       , RuntimeArtifact.TrainingRuntimeArtifact
       )
supervisedRuntimeArtifactForTraining origin plan problem metrics experimentHash metricRows = do
  canonicalProblem <-
    maybe
      (Left ("missing exact canonical supervised problem " <> SL.problemName problem))
      Right
      (find ((== SL.problemName problem) . SL.problemName) SL.canonicalProblems)
  if problem == canonicalProblem
    then Right ()
    else
      Left
        ( "supervised checkpoint problem record differs from the authoritative canonical problem for "
            <> SL.problemName problem
        )
  expectedDatasetSha <- Dataset.canonicalDatasetReadShaForProblem canonicalProblem
  if tmVerifiedDatasetShaAtRead metrics == expectedDatasetSha
    then Right ()
    else
      Left
        ( "supervised training-returned dataset SHA-256 does not equal the canonical training/evaluation read identity for "
            <> SL.problemName canonicalProblem
        )
  row <-
    maybe
      (Left ("missing ProductRow for supervised problem " <> SL.problemName problem))
      Right
      (ProductCompletion.supervisedProductRowForProblem problem)
  case origin of
    RuntimeArtifact.RawProductRowProjectionOrigin ->
      if experimentHash == ProductMatrix.productRowExperimentHash row
        then Right ()
        else
          Left
            ( "Product-origin supervised checkpoint experiment does not equal the authoritative ProductRow experiment (checkpoint="
                <> experimentHash
                <> ", authoritative="
                <> ProductMatrix.productRowExperimentHash row
                <> ")"
            )
    RuntimeArtifact.RawGenericSupervisedExecutionOrigin originRowId _ -> do
      if originRowId == SL.problemName canonicalProblem
        then Right ()
        else
          Left
            "generic supervised execution origin row differs from the exact canonical training problem"
      let planExperiment =
            runPlanExperimentId (WorkloadPlan.supervisedPlanRunPlan plan)
      if experimentHash == planExperiment
        then Right ()
        else
          Left
            "generic supervised checkpoint experiment differs from its exact plan"
  budget <-
    TrainingBudget.mkTrainingBudget
      TrainingBudget.SupervisedEpochBudget
      (quantityValue (WorkloadPlan.supervisedPlanEpochs plan))
      (Just (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.supervisedPlanRunPlan plan)))))
  let authoritativeOptimizerUpdates =
        quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
  if tmOptimizerUpdatesExecuted metrics == authoritativeOptimizerUpdates
    then Right ()
    else
      Left
        ( "training-returned executed optimizer-update count does not match the authoritative SupervisedPlan (executed="
            <> Text.pack (show (tmOptimizerUpdatesExecuted metrics))
            <> ", authoritative="
            <> Text.pack (show authoritativeOptimizerUpdates)
            <> ")"
        )
  let authoritativeEpochs =
        quantityValue (WorkloadPlan.supervisedPlanEpochs plan)
      authoritativeExamples =
        toInteger authoritativeEpochs
          * toInteger (quantityValue (WorkloadPlan.supervisedPlanTrainingExamples plan))
  if tmCompletedUnits metrics == authoritativeEpochs
    then Right ()
    else Left "training-returned completed epoch count does not match the authoritative SupervisedPlan"
  if toInteger (tmExamplesProcessed metrics) == authoritativeExamples
    then Right ()
    else
      Left "training-returned processed-example count does not match the authoritative SupervisedPlan"
  let exactMetricRows =
        [ ("train_loss", tmTrainLoss metrics)
        , ("validation_loss", tmValidationLoss metrics)
        , ("examples_processed", fromIntegral (tmExamplesProcessed metrics))
        ]
          <> maybe [] pure (tmHeldOutMetric metrics)
  if metricRows == exactMetricRows
    then Right ()
    else Left "supervised checkpoint metrics do not equal the exact training-returned metrics"
  if all (isFinite . snd) exactMetricRows
    then Right ()
    else Left "supervised checkpoint metrics must all be finite"
  validateTrainingMetricProjections metrics
  let planId = WorkloadPlan.supervisedPlanId plan
      initialBytes = tmInitialJmw1Bytes metrics
      finalBytes = tmFinalJmw1Bytes metrics
      initialSha = WeightCodec.jmw1ContentSha initialBytes
      finalSha = WeightCodec.jmw1ContentSha finalBytes
      datasetShaAtRead = tmVerifiedDatasetShaAtRead metrics
  artifact <-
    RuntimeArtifact.refineTrainingRuntimeArtifact
      RuntimeArtifact.RawTrainingRuntimeArtifact
        { RuntimeArtifact.rawTrainingArtifactPayload =
            RuntimeArtifact.RawSupervisedRuntimePayload
              { RuntimeArtifact.rawRuntimePayloadRowId = ProductMatrix.rowId row
              , RuntimeArtifact.rawRuntimePayloadOrigin = origin
              , RuntimeArtifact.rawRuntimePayloadPlanId = planIdText planId
              , RuntimeArtifact.rawRuntimePayloadDatasetSha256 = datasetShaAtRead
              , RuntimeArtifact.rawRuntimePayloadInitialJmw1Sha256 = initialSha
              , RuntimeArtifact.rawRuntimePayloadFinalJmw1Sha256 = finalSha
              , RuntimeArtifact.rawRuntimePayloadRuntime = tmSupervisedRuntimeProgram metrics
              }
        , RuntimeArtifact.rawTrainingArtifactInitialJmw1Bytes =
            LazyByteString.toStrict initialBytes
        , RuntimeArtifact.rawTrainingArtifactFinalJmw1Bytes =
            LazyByteString.toStrict finalBytes
        }
  _ <-
    Checkpoint.canonicalSupervisedRuntimeManifestMetadata
      (RuntimeArtifact.trainingArtifactPayload artifact)
  Right (row, budget, artifact)
 where
  isFinite value = not (isNaN value || isInfinite value)

validateTrainingMetricProjections :: TrainingMetrics -> Either Text ()
validateTrainingMetricProjections metrics = do
  initialValues <-
    mapLeftText
      "initial supervised JMW1 decode failed: "
      (WeightCodec.decodeJmw1 (tmInitialJmw1Bytes metrics))
  finalValues <-
    mapLeftText
      "final supervised JMW1 decode failed: "
      (WeightCodec.decodeJmw1 (tmFinalJmw1Bytes metrics))
  requireOptionalProjection
    "initial weight list"
    initialValues
    (tmInitialCheckpointWeights metrics)
  requireOptionalProjection
    "final weight list"
    finalValues
    (tmCheckpointWeights metrics)
  requireOptionalProjection
    "dataset-at-read SHA-256"
    (tmVerifiedDatasetShaAtRead metrics)
    (tmDatasetShaAtRead metrics)
 where
  requireOptionalProjection _ _ Nothing = Right ()
  requireOptionalProjection label exact (Just projected)
    | exact == projected = Right ()
    | otherwise =
        Left
          ( "transitional supervised "
              <> label
              <> " disagrees with the exact runtime artifact"
          )

mapLeftText :: Text -> Either Text a -> Either Text a
mapLeftText prefix outcome =
  case outcome of
    Left err -> Left (prefix <> err)
    Right value -> Right value

-- | Persist one completed supervised V2 checkpoint locally.
--
-- Unlike the retained generic V1 writer below, this boundary has no optional
-- completion argument and accepts no weight-list reconstruction.  The exact
-- bytes, their identities, and the executable topology must already have been
-- refined together as a 'RuntimeArtifact.TrainingRuntimeArtifact'.
writeLocalCompletedSupervisedCheckpoint
  :: TrainingBudget.CompletedTraining
  -> Text
  -> [(Text, Double)]
  -> RuntimeArtifact.TrainingRuntimeArtifact
  -> App CheckpointStore.StoredCompletedCheckpoint
writeLocalCompletedSupervisedCheckpoint completed experimentHash metrics artifact = do
  (manifest, payloads) <-
    case buildCompletedSupervisedCheckpointSnapshot completed experimentHash metrics artifact of
      Left err ->
        exitWithError (InvalidConfig ("supervised V2 checkpoint: " <> err))
      Right snapshot -> pure snapshot
  checkpointRoot <- localCheckpointRoot
  expectedPointer <- localLatestPointerExpectation checkpointRoot experimentHash
  writeResult <-
    liftIO
      ( CheckpointStore.writeCompletedCheckpointSnapshot
          checkpointRoot
          completed
          manifest
          payloads
          expectedPointer
      )
  case writeResult of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "supervised V2 checkpoint write: "
                <> CheckpointStore.renderCheckpointWriteError err
            )
        )
    Right stored -> do
      _ <- mirrorCompletedCheckpointToLiveIfPublished completed manifest payloads
      pure stored
{-# NOINLINE writeLocalCompletedSupervisedCheckpoint #-}

-- | Persist one completed supervised V2 checkpoint through the MinIO
-- capability.  Construction failures are returned before any blob or manifest
-- write is attempted.
writeMinIOCompletedSupervisedCheckpoint
  :: (Capabilities.HasMinIO m)
  => Maybe Capabilities.ETag
  -> TrainingBudget.CompletedTraining
  -> Text
  -> [(Text, Double)]
  -> RuntimeArtifact.TrainingRuntimeArtifact
  -> m (Either ServiceError CheckpointStore.StoredCompletedCheckpoint)
writeMinIOCompletedSupervisedCheckpoint expectedPointer completed experimentHash metrics artifact =
  case buildCompletedSupervisedCheckpointSnapshot completed experimentHash metrics artifact of
    Left err ->
      pure (Left (SETransient ("invalid supervised V2 checkpoint: " <> err)))
    Right (manifest, payloads) -> do
      CheckpointStore.writeCompletedCheckpointSnapshotWithMinIO
        expectedPointer
        completed
        manifest
        payloads
{-# NOINLINE writeMinIOCompletedSupervisedCheckpoint #-}

buildCompletedSupervisedCheckpointSnapshot
  :: TrainingBudget.CompletedTraining
  -> Text
  -> [(Text, Double)]
  -> RuntimeArtifact.TrainingRuntimeArtifact
  -> Either
       Text
       (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildCompletedSupervisedCheckpointSnapshot completed experimentHash metrics artifact = do
  _ <- RuntimeArtifact.loadTrainingRuntimeArtifact artifact
  let payload = RuntimeArtifact.trainingArtifactPayload artifact
  runtimeMetadata <- Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload
  let runtime = RuntimeArtifact.payloadRuntime payload
      finalBytes = RuntimeArtifact.trainingArtifactFinalJmw1Bytes artifact
      finalSha = RuntimeArtifact.payloadFinalJmw1Sha256 payload
      parameterCount = RuntimeArtifact.supervisedRuntimeParameterCount runtime
      blobObjectKey = Checkpoint.blobKey experimentHash finalSha
      weightTensor =
        Checkpoint.TensorBlob
          { Checkpoint.tensorName = "supervised.weights"
          , Checkpoint.tensorShape = [parameterCount]
          , Checkpoint.tensorBlobKey = blobObjectKey
          }
      virtualLayout =
        fmap
          runtimeVirtualSliceTensorSpec
          (RuntimeArtifact.supervisedRuntimeVirtualSlices runtime)
      baseManifest =
        ( Checkpoint.emptyManifest
            ( "checkpoint-"
                <> Text.pack
                  (show (TrainingBudget.completedTrainingObservedUnits completed))
            )
            experimentHash
            [weightTensor]
        )
          { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
          , Checkpoint.manifestArchitecture =
              Checkpoint.supervisedRuntimeArchitectureMetadata runtimeMetadata
          , Checkpoint.manifestPreprocessing =
              Checkpoint.supervisedRuntimePreprocessingMetadata runtimeMetadata
          , Checkpoint.manifestOutputDecoders =
              Checkpoint.supervisedRuntimeOutputDecoderMetadata runtimeMetadata
          , Checkpoint.manifestWeightLayout =
              Checkpoint.FlatWeightLayout virtualLayout
          , Checkpoint.manifestStep =
              TrainingBudget.completedTrainingObservedUnits completed
          , Checkpoint.manifestMetrics = metrics
          , Checkpoint.manifestSupervisedRuntime = Just payload
          }
      manifest = Checkpoint.attachCompletedTraining completed baseManifest
  validateCompletedSupervisedBindings completed payload metrics
  case Checkpoint.validateSupervisedManifestShapeLayout manifest of
    [] -> Right ()
    errors ->
      Left
        ( "supervised V2 manifest bindings are invalid: "
            <> Text.intercalate "; " errors
        )
  _ <- Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor manifest)
  Right (manifest, [(blobObjectKey, finalBytes)])

validateCompletedSupervisedBindings
  :: TrainingBudget.CompletedTraining
  -> RuntimeArtifact.SupervisedRuntimePayload
  -> [(Text, Double)]
  -> Either Text ()
validateCompletedSupervisedBindings completed payload metrics = do
  requireEqual
    "PlanId"
    (RuntimeArtifact.payloadPlanId payload)
    (TrainingBudget.completedTrainingPlanId completed)
  requireEqual
    "dataset-at-read SHA-256"
    (RuntimeArtifact.payloadDatasetSha256 payload)
    (TrainingBudget.completedTrainingDatasetShaAtRead completed)
  requireEqual
    "initial JMW1 SHA-256"
    (RuntimeArtifact.payloadInitialJmw1Sha256 payload)
    (TrainingBudget.completedTrainingInitialWeightHash completed)
  requireEqual
    "final JMW1 SHA-256"
    (RuntimeArtifact.payloadFinalJmw1Sha256 payload)
    (TrainingBudget.completedTrainingFinalWeightHash completed)
  if TrainingBudget.completedTrainingUpdateCount completed == 0
    then Left "completed supervised update count must be positive"
    else Right ()
  if TrainingBudget.completedTrainingObservedUnits completed == 0
    then Left "completed supervised checkpoint step must be positive"
    else Right ()
  traverse_
    requireCompletionMetric
    (TrainingBudget.completedTrainingMetrics completed)
 where
  requireCompletionMetric observation =
    let name = TrainingBudget.coMetricName observation
        value = TrainingBudget.coMetricValue observation
     in case lookup name metrics of
          Just observed
            | observed == value -> Right ()
            | otherwise ->
                Left
                  ( "manifest metric "
                      <> name
                      <> " does not equal completed-training measurement"
                  )
          Nothing ->
            Left ("manifest metrics are missing completed-training measurement " <> name)

requireEqual :: (Eq a) => Text -> a -> a -> Either Text ()
requireEqual label expected actual
  | expected == actual = Right ()
  | otherwise = Left (label <> " does not match the completed-training witness")

runtimeVirtualSliceTensorSpec
  :: RuntimeArtifact.RuntimeVirtualSlice -> Checkpoint.TensorSpec
runtimeVirtualSliceTensorSpec slice =
  Checkpoint.TensorSpec
    { Checkpoint.tensorSpecName =
        RuntimeArtifact.runtimeVirtualSliceQualifiedName slice
    , Checkpoint.tensorSpecShape = RuntimeArtifact.runtimeVirtualSliceShape slice
    , Checkpoint.tensorSpecDtype = "F64"
    }

-- | Persist a generic V1 candidate checkpoint.  This boundary cannot carry a
-- completion witness, so the resulting manifest is never relabelled as a
-- completed checkpoint by the writer.
writeLocalCandidateWeightCheckpoint
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> App CheckpointStore.StoredCandidateCheckpoint
writeLocalCandidateWeightCheckpoint experimentHash tensorName step metrics weights = do
  case validateGenericV1CandidateWriterRequest experimentHash tensorName of
    Left err ->
      exitWithError (InvalidConfig err)
    Right () -> pure ()
  checkpointRoot <- localCheckpointRoot
  let (manifest, payloads) =
        buildCandidateWeightCheckpointSnapshot
          experimentHash
          tensorName
          step
          metrics
          weights
  writeResult <-
    liftIO
      ( CheckpointStore.writeCandidateCheckpointSnapshot
          checkpointRoot
          manifest
          payloads
      )
  case writeResult of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "candidate checkpoint write: "
                <> CheckpointStore.renderCheckpointWriteError err
            )
        )
    Right stored -> do
      _ <- mirrorCandidateCheckpointToLiveIfPublished manifest payloads
      pure stored
{-# NOINLINE writeLocalCandidateWeightCheckpoint #-}

-- | Persist a generic V1 completed checkpoint.  Unlike the candidate writer,
-- this API requires a concrete completion witness and reports a pointer-CAS
-- loss as failure rather than returning a value that callers could publish as
-- completed.
writeLocalCompletedWeightCheckpoint
  :: TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> App CheckpointStore.StoredCompletedCheckpoint
writeLocalCompletedWeightCheckpoint completed experimentHash tensorName step metrics weights =
  writeLocalCompletedWeightCheckpointWithTranscripts
    completed
    experimentHash
    tensorName
    step
    metrics
    weights
    []
{-# NOINLINE writeLocalCompletedWeightCheckpoint #-}

-- | Product-only V1 writer which binds already-persisted companion evidence
-- into the immutable checkpoint manifest. Each transcript pointer is resolved
-- from the local object store and its exact bytes are revalidated by Store
-- before the completed pointer can advance. The generic public writer above
-- deliberately retains its existing transcript-free behavior.
writeLocalCompletedProductWeightCheckpoint
  :: TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Checkpoint.ArtifactPointer]
  -> App CheckpointStore.StoredCompletedCheckpoint
writeLocalCompletedProductWeightCheckpoint completed experimentHash tensorName step metrics weights transcriptPointers = do
  case ProductMatrix.productRowForExperimentHash experimentHash of
    Just row
      | ProductMatrix.family row /= ProductMatrix.Supervised -> pure ()
    _ ->
      exitWithError
        ( InvalidConfig
            ( "completed Product V1 checkpoint requires a canonical non-supervised ProductRow experiment: "
                <> experimentHash
            )
        )
  writeLocalCompletedWeightCheckpointWithTranscripts
    completed
    experimentHash
    tensorName
    step
    metrics
    weights
    transcriptPointers
{-# NOINLINE writeLocalCompletedProductWeightCheckpoint #-}

writeLocalCompletedWeightCheckpointWithTranscripts
  :: TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Checkpoint.ArtifactPointer]
  -> App CheckpointStore.StoredCompletedCheckpoint
writeLocalCompletedWeightCheckpointWithTranscripts completed experimentHash tensorName step metrics weights transcriptPointers = do
  case validateGenericV1CompletedWriterRequest completed experimentHash tensorName of
    Left err ->
      exitWithError (InvalidConfig err)
    Right () -> pure ()
  checkpointRoot <- localCheckpointRoot
  transcriptPayloads <-
    traverse
      ( \pointer -> do
          payloadResult <-
            liftIO
              ( CheckpointStore.readObject
                  checkpointRoot
                  (Checkpoint.artifactPointerObjectKey pointer)
              )
          case payloadResult of
            Left err ->
              exitWithError
                ( InvalidConfig
                    ( "completed checkpoint transcript read failed for "
                        <> Checkpoint.artifactPointerObjectKey pointer
                        <> ": "
                        <> err
                    )
                )
            Right payload ->
              pure (Checkpoint.artifactPointerObjectKey pointer, payload)
      )
      transcriptPointers
  let (baseManifest, weightPayloads) =
        buildCompletedWeightCheckpointSnapshot
          completed
          experimentHash
          tensorName
          step
          metrics
          weights
      manifest =
        baseManifest
          { Checkpoint.manifestTranscriptPointers = transcriptPointers
          }
      payloads = weightPayloads <> transcriptPayloads
  expectedPointer <- localLatestPointerExpectation checkpointRoot experimentHash
  writeResult <-
    liftIO
      ( CheckpointStore.writeCompletedCheckpointSnapshot
          checkpointRoot
          completed
          manifest
          payloads
          expectedPointer
      )
  case writeResult of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "completed checkpoint write: "
                <> CheckpointStore.renderCheckpointWriteError err
            )
        )
    Right stored -> do
      _ <- mirrorCompletedCheckpointToLiveIfPublished completed manifest payloads
      pure stored
{-# NOINLINE writeLocalCompletedWeightCheckpointWithTranscripts #-}

localLatestPointerExpectation :: FilePath -> Text -> App (Maybe Text)
localLatestPointerExpectation checkpointRoot experimentHash = do
  pointerResult <-
    liftIO
      ( CheckpointStore.readCheckpointPointer
          checkpointRoot
          (Checkpoint.latestPointerKey experimentHash)
      )
  case pointerResult of
    Left err ->
      exitWithError (InvalidConfig ("checkpoint pointer read: " <> err))
    Right currentPointer -> pure currentPointer

-- | MinIO-backed candidate writer.  It has no completion argument by design.
writeMinIOCandidateWeightCheckpoint
  :: (Capabilities.HasMinIO m)
  => Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> m (Either ServiceError CheckpointStore.StoredCandidateCheckpoint)
writeMinIOCandidateWeightCheckpoint experimentHash tensorName step metrics weights =
  case validateGenericV1CandidateWriterRequest experimentHash tensorName of
    Left err -> pure (Left (SETransient err))
    Right () ->
      let (manifest, payloads) =
            buildCandidateWeightCheckpointSnapshot
              experimentHash
              tensorName
              step
              metrics
              weights
       in CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO manifest payloads
{-# NOINLINE writeMinIOCandidateWeightCheckpoint #-}

-- | MinIO-backed completed writer.  Completion and the expected pointer ETag
-- are explicit; a losing CAS is a typed conflict and cannot be published as a
-- completed checkpoint.
writeMinIOCompletedWeightCheckpoint
  :: (Capabilities.HasMinIO m)
  => Maybe Capabilities.ETag
  -> TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> m (Either ServiceError CheckpointStore.StoredCompletedCheckpoint)
writeMinIOCompletedWeightCheckpoint expectedPointer completed experimentHash tensorName step metrics weights =
  case validateGenericV1CompletedWriterRequest completed experimentHash tensorName of
    Left err -> pure (Left (SETransient err))
    Right () ->
      let (manifest, payloads) =
            buildCompletedWeightCheckpointSnapshot
              completed
              experimentHash
              tensorName
              step
              metrics
              weights
       in CheckpointStore.writeCompletedCheckpointSnapshotWithMinIO
            expectedPointer
            completed
            manifest
            payloads
{-# NOINLINE writeMinIOCompletedWeightCheckpoint #-}

-- | Fail closed before a generic V1 writer constructs bytes for any
-- authoritative supervised row or for a tensor identity reserved by the V2
-- supervised format.  RL, AlphaZero and tuning retain their existing generic
-- writer paths; historical supervised V1 remains decode/inspect-only.
validateGenericV1CandidateWriterRequest
  :: Text
  -> Text
  -> Either Text ()
validateGenericV1CandidateWriterRequest = validateGenericV1WriterTarget

validateGenericV1CompletedWriterRequest
  :: TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Either Text ()
validateGenericV1CompletedWriterRequest completed experimentHash tensorName
  | TrainingBudget.trainingBudgetKind
      (TrainingBudget.completedTrainingBudget completed)
      == TrainingBudget.SupervisedEpochBudget =
      Left
        "generic V1 checkpoint writer cannot emit a supervised completed-training witness; use the completed supervised V2 writer"
  | otherwise = validateGenericV1WriterTarget experimentHash tensorName

validateGenericV1WriterTarget :: Text -> Text -> Either Text ()
validateGenericV1WriterTarget experimentHash tensorName
  | Just row <- ProductMatrix.productRowForExperimentHash experimentHash
  , ProductMatrix.family row == ProductMatrix.Supervised =
      Left
        ( "generic V1 checkpoint writer cannot emit authoritative supervised ProductRow "
            <> ProductMatrix.rowId row
            <> "; use the completed supervised V2 writer"
        )
  | isReservedSupervisedTensorName tensorName =
      Left
        ( "generic V1 checkpoint writer cannot emit reserved supervised tensor identity "
            <> tensorName
            <> "; use the completed supervised V2 writer"
        )
  | otherwise = Right ()

isReservedSupervisedTensorName :: Text -> Bool
isReservedSupervisedTensorName tensorName =
  normalized == "supervised.weights"
    || normalized == "sl-weights"
    || "-sl-weights" `Text.isSuffixOf` normalized
 where
  normalized = Text.toLower (Text.strip tensorName)

buildCandidateWeightCheckpointSnapshot
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildCandidateWeightCheckpointSnapshot = buildWeightCheckpointSnapshot

buildCompletedWeightCheckpointSnapshot
  :: TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildCompletedWeightCheckpointSnapshot completed experimentHash tensorName step metrics weights =
  let (candidate, payloads) =
        buildWeightCheckpointSnapshot experimentHash tensorName step metrics weights
   in (Checkpoint.attachCompletedTraining completed candidate, payloads)

buildWeightCheckpointSnapshot
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildWeightCheckpointSnapshot experimentHash tensorName step metrics weights =
  let payload = Checkpoint.encodeJmw1 weights
      blobSha = hexEncodeBytes (Crypto.Hash.SHA256.hash (LazyByteString.toStrict payload))
      blobObjectKey = Checkpoint.blobKey experimentHash blobSha
      weightTensor = Checkpoint.TensorBlob tensorName [length weights] blobObjectKey
      modelFamily = checkpointModelFamilyForTensor tensorName
      baseManifest =
        ( Checkpoint.emptyManifest
            ("checkpoint-" <> Text.pack (show step))
            experimentHash
            [weightTensor]
        )
          { Checkpoint.manifestModelFamily = modelFamily
          , Checkpoint.manifestArchitecture =
              Checkpoint.ArchitectureMetadata
                { Checkpoint.architectureName = checkpointArchitectureName modelFamily
                , Checkpoint.architectureModelFamily = modelFamily
                , Checkpoint.architectureInputs = []
                , Checkpoint.architectureOutputs = []
                , Checkpoint.architectureLayerGraph = Nothing
                }
          , Checkpoint.manifestOutputDecoders = checkpointOutputDecoders modelFamily
          , Checkpoint.manifestWeightLayout =
              Checkpoint.NamedTensorWeightLayout [Checkpoint.tensorSpecFromBlob weightTensor]
          , Checkpoint.manifestStep = step
          , Checkpoint.manifestMetrics = metrics
          }
   in (baseManifest, [(blobObjectKey, payload)])

completedTrainingForSupervisedProblem
  :: WorkloadPlan.SupervisedPlan
  -> SL.CanonicalProblem
  -> TrainingMetrics
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForSupervisedProblem plan problem metrics experimentHash _tensorName step metricRows finalWeights = do
  if step == tmCompletedUnits metrics
    then Right ()
    else Left "legacy supervised checkpoint step disagrees with exact training runtime"
  exactFinalWeights <-
    mapLeftText
      "final supervised JMW1 decode failed: "
      (WeightCodec.decodeJmw1 (tmFinalJmw1Bytes metrics))
  if finalWeights == exactFinalWeights
    then Right ()
    else Left "legacy supervised final weight list disagrees with exact JMW1 bytes"
  fst
    <$> completedSupervisedRuntimeForTraining
      plan
      problem
      metrics
      experimentHash
      metricRows
{-# NOINLINE completedTrainingForSupervisedProblem #-}

checkpointTrainingBudgetForTensor
  :: Text
  -> Word64
  -> Either Text TrainingBudget.TrainingBudget
checkpointTrainingBudgetForTensor tensorName step =
  let kind =
        case checkpointModelFamilyForTensor tensorName of
          Checkpoint.ReinforcementLearningPolicyFamily ->
            TrainingBudget.RlEnvironmentStepBudget
          Checkpoint.AlphaZeroPolicyValueFamily ->
            TrainingBudget.AlphaZeroSelfPlayBudget
          Checkpoint.HyperparameterTuningFamily ->
            TrainingBudget.TuningTrialBudget
          Checkpoint.SupervisedModelFamily ->
            TrainingBudget.SupervisedEpochBudget
          Checkpoint.GenericModelFamily ->
            TrainingBudget.SupervisedEpochBudget
   in TrainingBudget.mkTrainingBudget kind step Nothing
{-# NOINLINE checkpointTrainingBudgetForTensor #-}

checkpointModelFamilyForTensor :: Text -> Checkpoint.ModelFamily
checkpointModelFamilyForTensor tensorName
  | "alphazero" `Text.isInfixOf` lowered =
      Checkpoint.AlphaZeroPolicyValueFamily
  | "rl-" `Text.isPrefixOf` lowered =
      Checkpoint.ReinforcementLearningPolicyFamily
  | "tune" `Text.isInfixOf` lowered =
      Checkpoint.HyperparameterTuningFamily
  | otherwise =
      Checkpoint.GenericModelFamily
 where
  lowered = Text.toLower tensorName

checkpointArchitectureName :: Checkpoint.ModelFamily -> Text
checkpointArchitectureName family =
  case family of
    Checkpoint.SupervisedModelFamily -> "supervised-weighted-model"
    Checkpoint.ReinforcementLearningPolicyFamily -> "rl-policy"
    Checkpoint.AlphaZeroPolicyValueFamily -> "alphazero-policy-value"
    Checkpoint.HyperparameterTuningFamily -> "tuning-surrogate-or-trial"
    Checkpoint.GenericModelFamily -> "generic-weighted-model"

checkpointOutputDecoders :: Checkpoint.ModelFamily -> [Checkpoint.OutputDecoder]
checkpointOutputDecoders family =
  case family of
    Checkpoint.SupervisedModelFamily ->
      [decoder "prediction" Checkpoint.ClassificationOutput]
    Checkpoint.ReinforcementLearningPolicyFamily ->
      [decoder "policy" Checkpoint.PolicyDistributionOutput]
    Checkpoint.AlphaZeroPolicyValueFamily ->
      [ decoder "policy" Checkpoint.PolicyDistributionOutput
      , decoder "value" Checkpoint.ValueEstimateOutput
      , decoder "mcts-visits" Checkpoint.MctsVisitDistributionOutput
      ]
    Checkpoint.HyperparameterTuningFamily ->
      [decoder "objective" Checkpoint.RegressionOutput]
    Checkpoint.GenericModelFamily ->
      [decoder "output" Checkpoint.GenericOutput]
 where
  decoder name kind =
    Checkpoint.OutputDecoder
      { Checkpoint.outputDecoderName = name
      , Checkpoint.outputDecoderKind = kind
      , Checkpoint.outputDecoderLabels = []
      , Checkpoint.outputDecoderUnits = Nothing
      , Checkpoint.outputDecoderArtifactKind = Nothing
      }

mirrorCandidateCheckpointToLiveIfPublished
  :: Checkpoint.CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> App Bool
mirrorCandidateCheckpointToLiveIfPublished manifest payloads = do
  publicationMaybe <- liftIO (readExistingLivePublication ".")
  case publicationMaybe of
    Nothing -> pure False
    Just publication -> do
      let minioSettings = MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO manifest payloads)
          )
      case result of
        Right _ -> pure True
        Left err ->
          exitWithError (MinIOFailed ("candidate checkpoint mirror failed: " <> Text.pack (show err)))

mirrorCompletedCheckpointToLiveIfPublished
  :: TrainingBudget.CompletedTraining
  -> Checkpoint.CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> App Bool
mirrorCompletedCheckpointToLiveIfPublished completed manifest payloads = do
  publicationMaybe <- liftIO (readExistingLivePublication ".")
  case publicationMaybe of
    Nothing -> pure False
    Just publication -> do
      let minioSettings = MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              ( do
                  expectedPointer <-
                    MinIOSubprocess.minioObjectETag
                      ( CheckpointStore.checkpointObjectRef
                          (Checkpoint.latestPointerKey (Checkpoint.manifestExperiment manifest))
                      )
                  case expectedPointer of
                    Left err -> pure (Left err)
                    Right expected ->
                      CheckpointStore.writeCompletedCheckpointSnapshotWithMinIO
                        expected
                        completed
                        manifest
                        payloads
              )
          )
      case result of
        Right _ -> pure True
        Left err ->
          exitWithError (MinIOFailed ("completed checkpoint mirror failed: " <> Text.pack (show err)))

renderStoredCheckpointLines :: Text -> CheckpointStore.StoredCheckpoint -> [Text]
renderStoredCheckpointLines = renderStoredCheckpointLinesWithPrefix "checkpoint"

renderStoredCheckpointLinesWithPrefix :: Text -> Text -> CheckpointStore.StoredCheckpoint -> [Text]
renderStoredCheckpointLinesWithPrefix prefix experimentHash stored =
  [ prefix <> "-experiment-hash: " <> experimentHash
  , prefix <> "-manifest-sha: " <> CheckpointStore.storedManifestSha stored
  , prefix
      <> "-manifest-body-sha: "
      <> fromMaybe "absent (V1/legacy)" (CheckpointStore.storedManifestBodySha stored)
  , prefix <> "-manifest-key: " <> CheckpointStore.storedManifestObjectKey stored
  , prefix <> "-pointer-key: " <> Checkpoint.latestPointerKey experimentHash
  ]

writeTextArtifact :: Text -> Text -> Text -> App StoredArtifact
writeTextArtifact experimentHash kind payloadText = do
  checkpointRoot <- localCheckpointRoot
  let payload = Text.Encoding.encodeUtf8 payloadText
      sha = hexEncodeBytes (Crypto.Hash.SHA256.hash payload)
      objectKey =
        "jitml-checkpoints/"
          <> experimentHash
          <> "/artifacts/"
          <> kind
          <> "/"
          <> sha
          <> ".txt"
  writeResult <-
    liftIO
      (CheckpointStore.writeObjectIfAbsent checkpointRoot objectKey (LazyByteString.fromStrict payload))
  case writeResult of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "artifact write: "
                <> CheckpointStore.renderCheckpointWriteError err
            )
        )
    Right _ ->
      pure ()
  mirrored <- mirrorObjectToLiveIfPublished objectKey payload
  pure
    StoredArtifact
      { storedArtifactSha = sha
      , storedArtifactObjectKey = objectKey
      , storedArtifactMirroredToLive = mirrored
      }
{-# NOINLINE writeTextArtifact #-}

mirrorObjectToLiveIfPublished :: Text -> Data.ByteString.ByteString -> App Bool
mirrorObjectToLiveIfPublished objectKey payload = do
  publicationMaybe <- liftIO (readExistingLivePublication ".")
  case publicationMaybe of
    Nothing -> pure False
    Just publication -> do
      let minioSettings = MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
          ref = CheckpointStore.checkpointObjectRef objectKey
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              ( do
                  write <- Capabilities.putBlobBytesIfAbsent ref payload
                  case write of
                    Right _ -> pure (Right ())
                    Left (SEConflict _) -> do
                      existing <- Capabilities.minioReadBytes ref
                      pure $
                        case existing of
                          Right bytes
                            | bytes == payload -> Right ()
                            | otherwise ->
                                Left
                                  (SEConflict "artifact object exists with different bytes")
                          Left err ->
                            Left
                              ( SEConflict
                                  ( "artifact object exists but exact-byte comparison failed: "
                                      <> Text.pack (show err)
                                  )
                              )
                    Left err -> pure (Left err)
              )
          )
      case result of
        Right () -> pure True
        Left err ->
          exitWithError (MinIOFailed ("artifact mirror failed: " <> Text.pack (show err)))

renderStoredArtifactLines :: Text -> StoredArtifact -> [Text]
renderStoredArtifactLines prefix artifact =
  [ prefix <> "-artifact-sha: " <> storedArtifactSha artifact
  , prefix <> "-artifact-key: " <> storedArtifactObjectKey artifact
  , prefix
      <> "-artifact-live-minio: "
      <> if storedArtifactMirroredToLive artifact then "yes" else "no"
  ]

data StoredArtifact = StoredArtifact
  { storedArtifactSha :: !Text
  , storedArtifactObjectKey :: !Text
  , storedArtifactMirroredToLive :: !Bool
  }
  deriving stock (Eq, Show)

localCheckpointRoot :: App FilePath
localCheckpointRoot = do
  cacheDir <- asks envCacheDir
  pure (toFilePath cacheDir </> "checkpoints")

hexEncodeBytes :: Data.ByteString.ByteString -> Text
hexEncodeBytes =
  Text.pack
    . concatMap (\b -> [hexDigit (fromIntegral b `div` 16), hexDigit (fromIntegral b `mod` 16)])
    . Data.ByteString.unpack
 where
  hexDigit n
    | n < 10 = toEnum (fromEnum '0' + n)
    | otherwise = toEnum (fromEnum 'a' + n - 10)

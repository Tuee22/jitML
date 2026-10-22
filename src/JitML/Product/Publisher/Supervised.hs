{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Supervised
  ( trainSupervisedCohort
  , supervisedPublishMetricRows
  , trainAndPublishSupervisedProductRow
  , validateSupervisedPublishUpdateCount
  , validateSupervisedServedMetricExampleCount
  , verifyAdmittedSupervisedServedMetric
  )
where

import Codec.Serialise (serialise)
import Control.Monad.IO.Class (liftIO)
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Env.Env (App)
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Plan.Plan
  ( RunKind (..)
  , planIdText
  , quantityValue
  , runPlanExperimentId
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.Audit
  ( ProductPublishDisposition (..)
  , ProductPublishResult (..)
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
import JitML.Product.ServedMetric qualified as ServedMetric
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.SupervisedQualificationPolicy qualified as QualificationPolicy
import JitML.Product.SupervisedQualificationReceipt qualified as QualificationReceipt
import JitML.SL.Canonicals qualified as SL
import JitML.SL.ConvergenceThresholds qualified as SlThresholds
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.InitialComparison qualified as InitialComparison
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Training.Budget qualified as TrainingBudget

-- | Exactly five prescribed in-process executions, retaining raw material as
-- each returns. This deliberately does not apply individual convergence bars
-- to auxiliary children or discard finite non-improving/below-floor outcomes.
-- The returned primary run is the actual index-0 result, never a reconstruction
-- or the best-scoring member. Mathematical qualification happens separately.
trainSupervisedCohort
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> SL.CanonicalProblem
  -> Cohort.SupervisedCohortPlan
  -> App (Either Text (SupervisedPublishRun, Qualification.SupervisedQualification, Text, Text))
trainSupervisedCohort invocation runtime row problem cohort = do
  producerResult <- publisherSupervisedQualificationProducer runtime invocation
  case producerResult of
    Left err -> pure (Left err)
    Right producer -> do
      started <-
        writeRaw
          "supervised-qualification-attempt"
          (serialise (1 :: Int, "started" :: Text, Cohort.supervisedCohortPlanTransport cohort, producer))
      case started of
        Left err -> pure (Left err)
        Right _ -> go producer Nothing [] (Cohort.supervisedCohortPlanChildren cohort)
 where
  projection = Cohort.supervisedCohortPlanProjection cohort
  experimentHash = ProductMatrix.productProjectionExperimentHash projection
  writeRaw kind payload = do
    (storedSha, objectKey) <- publisherWriteBinaryArtifact runtime experimentHash kind payload
    pure $
      if storedSha == WeightCodec.jmw1ContentSha payload
        then Right (storedSha, objectKey)
        else Left "supervised qualification raw writer returned a substituted payload identity"
  failed producer child err = do
    retained <-
      writeRaw
        "supervised-qualification-attempt"
        ( serialise
            ( 1 :: Int
            , "failed" :: Text
            , Qualification.prescribedSupervisedChildAttempt
                (Qualification.rawQualificationInvocationSha256 producer)
                child
            , err
            )
        )
    pure (retained >> Left err)
  failedCohort producer err = do
    retained <-
      writeRaw
        "supervised-qualification-attempt"
        (serialise (1 :: Int, ["failed", Cohort.supervisedCohortPlanTransport cohort, err], producer))
    pure (retained >> Left err)
  go producer primaryMaybe reversed [] =
    case primaryMaybe of
      Nothing -> failedCohort producer "supervised cohort executed no prescribed index-0 run"
      Just primary ->
        case requireGraph primary of
          Left err -> failedCohort producer err
          Right graph ->
            case Qualification.buildSupervisedQualification
              cohort
              producer
              (evaluation primary)
              (supervisedPublishRuntimeProgram primary)
              graph
              (reverse reversed) of
              Left err -> failedCohort producer err
              Right qualification -> do
                written <-
                  writeRaw
                    "supervised-qualification"
                    (LazyByteString.fromStrict (Qualification.encodeSupervisedQualification qualification))
                case written of
                  Left err -> failedCohort producer err
                  Right (sha, key)
                    | key == QualificationReceipt.supervisedQualificationObjectKey cohort sha ->
                        pure (Right (primary, qualification, sha, key))
                    | otherwise ->
                        failedCohort
                          producer
                          "supervised qualification writer returned a noncanonical detached object address"
  go producer primaryMaybe reversed (child : rest) = do
    trained <- publisherRunSupervisedTraining runtime child
    case trained of
      Left err -> failed producer child err
      Right run -> do
        -- Preserve the actual returned bytes and observations even when their
        -- subsequent refinement fails. This object makes no completion claim.
        returned <- writeRaw "supervised-seed-return" (rawReturnedChild child run)
        case returned of
          Left err -> failed producer child err
          Right _ -> case refineRawChild producer child run of
            Left err -> failed producer child err
            Right raw -> do
              shared <- case primaryMaybe of
                Nothing -> writeRaw "supervised-qualification-evaluation" (serialise (evaluation run))
                Just _ -> pure (Right ("", ""))
              case shared of
                Left err -> failed producer child err
                Right _ -> do
                  stored <- writeRaw "supervised-seed-outcome" (serialise raw)
                  case stored of
                    Left err -> failed producer child err
                    Right _ ->
                      go
                        producer
                        (case primaryMaybe of Nothing -> Just run; Just primary -> Just primary)
                        (raw : reversed)
                        rest
  rawReturnedChild child run =
    serialise
      ( 1 :: Int
      , WorkloadPlan.renderSupervisedPlanTransport (Cohort.supervisedSeedPlanWorkload child)
      ,
        (
          ( supervisedPublishCompletedUnits run
          , supervisedPublishExamplesProcessed run
          , supervisedPublishOptimizerUpdatesExecuted run
          )
        ,
          (
            ( supervisedPublishTrainLoss run
            , supervisedPublishValidationLoss run
            , supervisedPublishHeldOutMetric run
            )
          ,
            (
              ( supervisedPublishRuntimeProgram run
              , supervisedPublishInitialLayerGraphMetadata run
              , supervisedPublishLayerGraphMetadata run
              )
            ,
              ( (supervisedPublishInitialJmw1Bytes run, supervisedPublishFinalJmw1Bytes run)
              ,
                ( supervisedPublishVerifiedDatasetShaAtRead run
                , fmap DeviceWitness.deviceExecutionWitnessToRaw (supervisedPublishDeviceWitness run)
                , evaluation run
                )
              )
            )
          )
        )
      )
  refineRawChild producer child run = do
    let workload = Cohort.supervisedSeedPlanWorkload child
    validateSupervisedPublishDatasetSha problem run
    validateSupervisedPublishUpdateCount workload run
    _ <- supervisedPublishMetricRows row workload run
    validateTransitionalSupervisedProjections run
    requireProjectedValue
      "supervised child observed epochs"
      (quantityValue (WorkloadPlan.supervisedPlanEpochs workload))
      (supervisedPublishCompletedUnits run)
    requireProjectedValue
      "supervised child held-out example count"
      (toInteger (quantityValue (WorkloadPlan.supervisedPlanEvaluationExamples workload)))
      (toInteger (ServedMetric.heldOutExampleCount (supervisedPublishHeldOutExamples run)))
    graph <- requireGraph run
    snapshot <-
      InitialComparison.refineInitialComparisonSnapshot
        InitialComparison.RawInitialComparisonSnapshot
          { InitialComparison.rawInitialComparisonVersion = 1
          , InitialComparison.rawInitialComparisonRuntime = supervisedPublishRuntimeProgram run
          , InitialComparison.rawInitialComparisonGraphMetadata = supervisedPublishInitialLayerGraphMetadata run
          , InitialComparison.rawInitialComparisonJmw1Bytes =
              LazyByteString.toStrict (supervisedPublishInitialJmw1Bytes run)
          }
    _ <-
      InitialComparison.prepareSupervisedComparison
        snapshot
        (supervisedPublishRuntimeProgram run)
        graph
        (LazyByteString.toStrict (supervisedPublishFinalJmw1Bytes run))
    witness <-
      maybe
        (Left "supervised child produced no device execution witness")
        Right
        (supervisedPublishDeviceWitness run)
    Right
      Qualification.RawSupervisedSeedOutcome
        { Qualification.rawSeedIndex =
            QualificationPolicy.supervisedSeedIndexValue (Cohort.supervisedSeedPlanIndex child)
        , Qualification.rawSeedValue = Cohort.supervisedSeedPlanSeed child
        , Qualification.rawSeedPlanId = planIdText (WorkloadPlan.supervisedPlanId workload)
        , Qualification.rawSeedPlanTransport = WorkloadPlan.renderSupervisedPlanTransport workload
        , Qualification.rawSeedAttemptIdentity =
            Qualification.prescribedSupervisedChildAttempt
              (Qualification.rawQualificationInvocationSha256 producer)
              child
        , Qualification.rawSeedObservedEpochs = supervisedPublishCompletedUnits run
        , Qualification.rawSeedObservedExamples = fromIntegral (supervisedPublishExamplesProcessed run)
        , Qualification.rawSeedObservedOptimizerUpdates = supervisedPublishOptimizerUpdatesExecuted run
        , Qualification.rawSeedDatasetSha256 = supervisedPublishVerifiedDatasetShaAtRead run
        , Qualification.rawSeedEvaluationSha256 = Qualification.qualificationEvaluationSha256 (evaluation run)
        , Qualification.rawSeedFinalRuntimeSha256 =
            Qualification.qualificationRuntimeSha256 (supervisedPublishRuntimeProgram run)
        , Qualification.rawSeedFinalGraphSha256 = Qualification.qualificationGraphSha256 graph
        , Qualification.rawSeedDeviceWitness = DeviceWitness.deviceExecutionWitnessToRaw witness
        , Qualification.rawSeedInitialSnapshotBytes =
            InitialComparison.encodeInitialComparisonSnapshot snapshot
        , Qualification.rawSeedFinalJmw1Bytes = LazyByteString.toStrict (supervisedPublishFinalJmw1Bytes run)
        }
  requireGraph run =
    maybe
      (Left "supervised child produced no final graph descriptor")
      Right
      (supervisedPublishLayerGraphMetadata run)
  evaluation run = case supervisedPublishHeldOutExamples run of
    ServedMetric.HeldOutClassification examples -> Qualification.RawClassificationEvaluation examples
    ServedMetric.HeldOutRegression scale examples -> Qualification.RawRegressionEvaluation scale examples

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
        _descriptorLearningRate
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
              budget <-
                productTrainingBudgetForProjection
                  projection
                  TrainingBudget.SupervisedEpochBudget
                  planEpochs
                  seed
              cohort <- Cohort.mkSupervisedCohortPlan projection
              Right (budget, cohort)
        case projectionValidation of
          Left err -> pure (productPublishError projection err)
          Right (budget, cohort) -> do
            testLimit <- intPlanValue "product supervised evaluation examples" planEvaluation
            trained <- trainSupervisedCohort invocation runtime row problem cohort
            case trained of
              Left err -> pure (productPublishError projection err)
              Right (run, qualification, qualificationSha, qualificationKey) -> do
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
                      -- Total after the line above: a missing held-out metric was
                      -- already rejected there, so the post-admission check below
                      -- receives the metric itself rather than a 'Maybe'.
                      heldOutMetric <- requireHeldOutMetric run
                      validateSupervisedServedMetricExampleCount
                        testLimit
                        (supervisedPublishHeldOutExamples run)
                      artifact <- runtimeArtifact
                      completed <- completedTraining metricRows artifact
                      Right (metricRows, heldOutMetric, artifact, completed)
                case validatedPublication of
                  Left err ->
                    denySupervisedQualification
                      runtime
                      projection
                      cohort
                      qualification
                      qualificationSha
                      qualificationKey
                      Nothing
                      ("supervised row did not produce an exact V2 runtime and passing CompletedTraining evidence: " <> err)
                  Right (metricRows, heldOutMetric, artifact, completed) -> do
                    stored <-
                      publisherWriteCompletedSupervisedCheckpoint
                        runtime
                        completed
                        experimentHash
                        metricRows
                        artifact
                    admission <-
                      admitPublishedProductCheckpoint runtime projection completed stored
                    case admission of
                      Left err ->
                        denySupervisedQualification
                          runtime
                          projection
                          cohort
                          qualification
                          qualificationSha
                          qualificationKey
                          Nothing
                          ("supervised checkpoint storage succeeded but exact Store admission failed: " <> err)
                      Right admitted -> do
                        -- The served-byte gate can only run on an admitted checkpoint, so a
                        -- rejection here leaves that checkpoint in Store (see the gate).
                        servedResult <-
                          liftIO
                            ( verifyAdmittedSupervisedServedMetric
                                projection
                                admitted
                                heldOutMetric
                                (supervisedPublishHeldOutExamples run)
                            )
                        finalizeSupervisedQualification
                          runtime
                          projection
                          cohort
                          qualification
                          qualificationSha
                          qualificationKey
                          admitted
                          servedResult

-- | Preserve the existing Store/served-metric boundary, then require the
-- complete five-run result and its exact admitted index-0 binding. A denied
-- publication may leave an individually completed checkpoint in Store; it
-- never gains a qualified ProductRow/report reference.
finalizeSupervisedQualification
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> Cohort.SupervisedCohortPlan
  -> Qualification.SupervisedQualification
  -> Text
  -> Text
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> ProductPublishResult
  -> App ProductPublishResult
finalizeSupervisedQualification runtime projection cohort qualification sha key admitted servedResult = do
  let publication = case productPublishDisposition servedResult of
        ProductPublishEligible _ -> do
          qualified <- Qualification.qualifySupervisedCohort qualification
          QualificationReceipt.bindSupervisedQualificationPublication cohort qualified key admitted
        _ -> Left (productPublishMessage servedResult)
      (verdict, reason) = case publication of
        Right _ -> ("qualified" :: Text, "all five prescribed runs and the actual served seed pass" :: Text)
        Left err -> ("denied", err)
  retained <-
    recordSupervisedQualificationVerdict
      runtime
      projection
      cohort
      qualification
      sha
      key
      ( Just
          (CheckpointStore.admittedCheckpointManifestSha (CheckpointStore.admittedCompletedCheckpoint admitted))
      )
      verdict
      reason
  pure $
    case retained of
      Left err -> productPublishError projection err
      Right () -> case publication of
        Left err ->
          productPublishError
            projection
            ("supervised five-run qualification denied: " <> err <> " (raw=" <> sha <> ")")
        Right bound ->
          servedResult
            { productPublishSupervisedQualification = Just bound
            , productPublishMessage =
                "five prescribed compact runs qualify; original served seed is independently admitted and replayed"
            }

denySupervisedQualification
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> Cohort.SupervisedCohortPlan
  -> Qualification.SupervisedQualification
  -> Text
  -> Text
  -> Maybe Text
  -> Text
  -> App ProductPublishResult
denySupervisedQualification runtime projection cohort qualification sha key manifest err = do
  retained <-
    recordSupervisedQualificationVerdict
      runtime
      projection
      cohort
      qualification
      sha
      key
      manifest
      "denied"
      err
  pure
    ( productPublishError
        projection
        (either (\ledgerErr -> err <> "; " <> ledgerErr) (const err) retained)
    )

recordSupervisedQualificationVerdict
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> Cohort.SupervisedCohortPlan
  -> Qualification.SupervisedQualification
  -> Text
  -> Text
  -> Maybe Text
  -> Text
  -> Text
  -> App (Either Text ())
recordSupervisedQualificationVerdict runtime projection cohort qualification sha key manifest verdict reason = do
  let producer = Qualification.rawQualificationProducer (Qualification.supervisedQualificationToRaw qualification)
      ledger =
        serialise
          ( 1 :: Int
          , [verdict, Cohort.supervisedCohortPlanTransport cohort, sha, key, reason]
          , (producer, manifest)
          )
  (ledgerSha, _) <-
    publisherWriteBinaryArtifact
      runtime
      (ProductMatrix.productProjectionExperimentHash projection)
      "supervised-qualification-attempt"
      ledger
  pure $
    if ledgerSha == WeightCodec.jmw1ContentSha ledger
      then Right ()
      else Left "supervised qualification verdict ledger returned a substituted identity"

-- | The verified held-out examples the served-metric check replays must be
-- exactly the plan's evaluation budget: a shorter, longer, or substituted set
-- would make the recomputed metric a statement about a different evaluation.
-- This runs before the checkpoint is written, so a mismatch never reaches Store.
validateSupervisedServedMetricExampleCount
  :: Int
  -> ServedMetric.HeldOutExamples
  -> Either Text ()
validateSupervisedServedMetricExampleCount plannedExamples evidence =
  requireProjectedValue
    "supervised exact served-metric evaluation examples"
    plannedExamples
    (ServedMetric.heldOutExampleCount evidence)

-- | The post-admission gate on ProductRow eligibility. It recomputes the
-- reported held-out metric through the serving graph and physical weights of
-- the checkpoint Store just re-admitted, and produces the row's publish result:
-- eligible only when the recomputation agrees with the reported metric, and a
-- typed publish error carrying the served-versus-reported diagnostic otherwise.
--
-- The check runs AFTER the checkpoint was written and admitted, because only an
-- admitted checkpoint can be served. A rejected checkpoint therefore remains in
-- Store: the row is denied eligibility, but the persisted objects are not
-- removed. Reuse of that checkpoint by a later run is closed elsewhere: the
-- orchestrator never reuses a supervised checkpoint, because a persisted
-- manifest carries no held-out example set to verify.
verifyAdmittedSupervisedServedMetric
  :: ProductMatrix.ProductProjection 'SupervisedTraining
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> (Text, Double)
  -> ServedMetric.HeldOutExamples
  -> IO ProductPublishResult
verifyAdmittedSupervisedServedMetric projection admitted (metricName, reported) evidence = do
  served <-
    ServedMetric.assertAdmittedHeldOutMetricAndLearningSignal
      admitted
      (SlThresholds.slClassCount (ProductMatrix.productProjectionRowId projection))
      metricName
      reported
      evidence
  pure $
    case served of
      Left err ->
        productPublishError
          projection
          ("supervised held-out metric failed exact admitted served-byte verification: " <> err)
      Right () ->
        productPublishEligible
          projection
          admitted
          []
          "supervised V2 runtime artifact stored, admitted, and held-out metric recomputed from served bytes"

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
  heldOutMetric <- requireHeldOutMetric run
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

requireHeldOutMetric :: SupervisedPublishRun -> Either Text (Text, Double)
requireHeldOutMetric run =
  maybe
    (Left "supervised ProductRow publication requires exactly one held-out metric")
    Right
    (supervisedPublishHeldOutMetric run)

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
{-# NOINLINE validateSupervisedServedMetricExampleCount #-}
{-# NOINLINE verifyAdmittedSupervisedServedMetric #-}

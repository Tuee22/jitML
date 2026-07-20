{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.SL.TrainingExecution
  ( TrainingExecutionRuntime (..)
  , TrainingMetrics (..)
  , applyCifar10RgbInputTransform
  , californiaHousingRuntimeProgram
  , datasetFetchFailure
  , fitCifar10RgbInputTransform
  , hasCanonicalLabels
  , runDeviceMnistTraining
  , runDeviceMnistTrainingWithLimitsAndLearningRate
  , supervisedExecutionBudget
  , supervisedExecutionSeed
  )
where

import Control.Monad.Reader (ask, liftIO)
import Data.ByteString qualified
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (traverse_)
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)

import JitML.CLI.Output (writeText)
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Env.Env (App)
import JitML.Numerics.Mlp
  ( MlpParams (paramShape)
  , MlpShape (..)
  , mlpInit
  , mlpParamsToFlat
  )
import JitML.Numerics.MlpDevice (MlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Plan.Plan (quantityValue, runPlanSeeds, seedCohortValues)
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.Regression qualified as Regression
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.SL.TinyImageNet qualified as TinyImageNet
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Substrate (Substrate, renderSubstrate)

-- | App-owned live-storage resolution consumed by supervised execution. This
-- narrow effect boundary keeps the training engine independent of
-- "JitML.App" while preserving host and worker publication resolution.
newtype TrainingExecutionRuntime = TrainingExecutionRuntime
  { trainingResolveMinIOSettings :: App (Maybe MinIOSubprocess.MinIOSettings)
  }

supervisedExecutionBudget
  :: WorkloadPlan.SupervisedPlan
  -> Either Text (Int, Int, Int, Int)
supervisedExecutionBudget plan = do
  trainingExamples <-
    boundedInt "supervised training examples" (WorkloadPlan.supervisedPlanTrainingExamples plan)
  epochs <- boundedInt "supervised epochs" (WorkloadPlan.supervisedPlanEpochs plan)
  evaluationExamples <-
    boundedInt "supervised evaluation examples" (WorkloadPlan.supervisedPlanEvaluationExamples plan)
  batchExamples <-
    boundedInt "supervised batch examples" (WorkloadPlan.supervisedPlanBatchExamples plan)
  pure (trainingExamples, epochs, evaluationExamples, batchExamples)
 where
  boundedInt label quantity
    | value > toInteger (maxBound :: Int) = Left (label <> " exceeds the platform Int range")
    | otherwise = Right (fromIntegral (quantityValue quantity))
   where
    value = toInteger (quantityValue quantity)

-- | Extract the one execution seed carried by a supervised plan.  The common
-- run-plan type also serves multi-seed workloads, so supervised execution
-- closes that wider representation here rather than silently selecting one
-- member.  Device trainers consume 'Int' seeds; rejecting the overflow at this
-- pure boundary keeps platform-dependent truncation out of initialization.
supervisedExecutionSeed :: WorkloadPlan.SupervisedPlan -> Either Text Int
supervisedExecutionSeed plan =
  case NonEmpty.toList seeds of
    [seed]
      | toInteger seed > toInteger (maxBound :: Int) ->
          Left "supervised execution seed exceeds the platform Int range"
      | otherwise -> Right (fromIntegral seed)
    _ -> Left "supervised execution requires exactly one refined plan seed"
 where
  seeds =
    seedCohortValues
      (runPlanSeeds (WorkloadPlan.supervisedPlanRunPlan plan))

-- | Sprint 8.13 — the real supervised-learning run metrics surfaced by
-- @jitml train@. The published loss is a measured cross-entropy (classifier)
-- or MSE (regression) value, never @1 − accuracy@; the validation loss is a
-- real held-out measurement on the validation partition (the quantity that
-- drives validation-driven model selection); the throughput field is a
-- deterministic, non-wall-clock performance metric (train examples × epochs);
-- and the held-out metric is the test-partition accuracy/error reported once on
-- the selected model.
data TrainingMetrics = TrainingMetrics
  { tmTrainLoss :: !Double
  , tmValidationLoss :: !Double
  , tmExamplesProcessed :: !Int
  , tmHeldOutMetric :: !(Maybe (Text, Double))
  , tmCompletedUnits :: !Word64
  , tmOptimizerUpdatesExecuted :: !Word64
  -- ^ Exact mini-batch optimizer updates completed by the successful training
  -- call.  This is recorded only after every requested epoch/batch loop has
  -- returned successfully; checkpoint completion must consume this value
  -- rather than re-minting an update count from the plan.
  , tmInitialCheckpointWeights :: !(Maybe [Double])
  , tmCheckpointWeights :: !(Maybe [Double])
  , tmDatasetShaAtRead :: !(Maybe Text)
  , tmSupervisedRuntimeProgram :: !RuntimeArtifact.RawSupervisedRuntime
  -- ^ Transitional list projections retained for existing checkpoint call
  -- sites above are optional.  These fields are the mandatory Sprint 10.6
  -- success contract: the exact trained program, its byte-exact initial/final
  -- JMW1 tensors, and the verified dataset digest always travel together.
  , tmInitialJmw1Bytes :: !LazyByteString.ByteString
  , tmFinalJmw1Bytes :: !LazyByteString.ByteString
  , tmVerifiedDatasetShaAtRead :: !Text
  , tmParityProbeInput :: ![Double]
  -- ^ One exact held-out input in the persisted runtime's ingress units.
  , tmParityProbeOutput :: ![Double]
  -- ^ The corresponding semantic numerical output produced immediately from
  -- the training-returned model (after only the persisted output transform,
  -- and before decoder label/unit interpretation).  This mandatory pair lets
  -- the V2 parity gate compare training and Store-loaded inference without
  -- reconstructing a model or inventing a synthetic probe.
  }
  deriving stock (Eq, Show)

-- | Materialize a deterministic held-out selection slice in addition to the
-- exact gradient-example budget.  Only the first @trainingExamples@ values
-- enter optimizer updates; the remainder is validation-only.
trainingMaterializationLimit :: Int -> Either Text Int
trainingMaterializationLimit trainingExamples
  | trainingExamples <= 0 = Left "supervised training-example budget must be positive"
  | validationExamples <= 0 =
      Left "supervised training-example budget is too small to derive a non-empty validation partition"
  | trainingExamples > maxBound - validationExamples =
      Left "supervised training/validation materialization limit exceeds the platform Int range"
  | otherwise = Right (trainingExamples + validationExamples)
 where
  validationExamples = trainingExamples `div` 5

regressionMaterializationLimit :: Int -> Int -> Either Text Int
regressionMaterializationLimit trainingExamples evaluationExamples
  | trainingExamples <= 0 = Left "regression training-example budget must be positive"
  | evaluationExamples <= 0 = Left "regression evaluation-example budget must be positive"
  | trainingExamples > maxBound - evaluationExamples =
      Left "regression train/evaluation materialization limit exceeds the platform Int range"
  | otherwise = Right (trainingExamples + evaluationExamples)

-- | Fit the canonical CIFAR-10 ViT ingress transform from the training
-- partition alone.  CIFAR decoding has already transposed the archive's three
-- planes into pixel-major interleaved RGB and scaled every channel to @[0,1]@;
-- this boundary validates that exact representation before interpreting
-- @index mod 3@ as the channel.  Population statistics are accumulated over
-- every pixel of every supplied training image, then repeated in pixel-major
-- RGB order so the persisted transform has the full 3072-element input width.
fitCifar10RgbInputTransform
  :: Classifier.Dataset
  -> Either Text RuntimeArtifact.RawRuntimeInputTransform
fitCifar10RgbInputTransform [] =
  Left "CIFAR-10 RGB standardization requires a non-empty training partition"
fitCifar10RgbInputTransform trainingSet = do
  traverse_ validateCifar10Example trainingSet
  channelStats <- traverse fitChannel [0 .. cifar10ChannelCount - 1]
  let rgbMeans = fmap fst channelStats
      rgbScales = fmap snd channelStats
      means = concat (replicate cifar10PixelsPerImage rgbMeans)
      scales = concat (replicate cifar10PixelsPerImage rgbScales)
  pure (RuntimeArtifact.RawStandardizeInput means scales)
 where
  fitChannel channel = do
    let count =
          fromInteger
            (toInteger (length trainingSet) * toInteger cifar10PixelsPerImage)
        total = foldCifarChannel channel (+) 0.0 trainingSet
        meanValue = total / count
        squaredDeviation value = (value - meanValue) * (value - meanValue)
        variance =
          foldCifarChannel channel (\acc value -> acc + squaredDeviation value) 0.0 trainingSet
            / count
        scale = sqrt variance
    requireFiniteCifarValue "channel mean" meanValue
    requireFiniteCifarValue "channel variance" variance
    requireFiniteCifarValue "channel scale" scale
    if scale > 0.0
      then Right (meanValue, scale)
      else Left "CIFAR-10 RGB standardization channel scale must be positive"

-- | Apply an already-fitted full-width CIFAR-10 RGB transform.  Callers pass
-- the transform fitted from the training partition to train, validation, and
-- test datasets; this function deliberately has no refitting path.
applyCifar10RgbInputTransform
  :: RuntimeArtifact.RawRuntimeInputTransform
  -> Classifier.Dataset
  -> Either Text Classifier.Dataset
applyCifar10RgbInputTransform rawTransform dataset = do
  (means, scales) <-
    case rawTransform of
      RuntimeArtifact.RawStandardizeInput rawMeans rawScales
        | length rawMeans /= cifar10FeatureWidth ->
            Left "CIFAR-10 RGB standardization mean width must be exactly 3072"
        | length rawScales /= cifar10FeatureWidth ->
            Left "CIFAR-10 RGB standardization scale width must be exactly 3072"
        | otherwise -> do
            traverse_ (requireFiniteCifarValue "input mean") rawMeans
            traverse_ requirePositiveCifarScale rawScales
            Right (VU.fromList rawMeans, VU.fromList rawScales)
      _ -> Left "CIFAR-10 RGB standardization requires a standardize-input transform"
  traverse (standardizeExample means scales) dataset
 where
  standardizeExample means scales example = do
    validateCifar10Example example
    let standardized =
          VU.zipWith3
            (\value meanValue scale -> (value - meanValue) / scale)
            (Classifier.exampleFeatures example)
            means
            scales
    if VU.all isFiniteCifarValue standardized
      then
        Right
          example
            { Classifier.exampleFeatures = standardized
            }
      else Left "CIFAR-10 RGB standardization produced a non-finite value"

cifar10FeatureWidth :: Int
cifar10FeatureWidth = 3072

cifar10ChannelCount :: Int
cifar10ChannelCount = 3

cifar10PixelsPerImage :: Int
cifar10PixelsPerImage = cifar10FeatureWidth `div` cifar10ChannelCount

validateCifar10Example :: Classifier.LabeledExample -> Either Text ()
validateCifar10Example example
  | VU.length features /= cifar10FeatureWidth =
      Left
        ( "CIFAR-10 RGB input width must be exactly 3072 (actual="
            <> Text.pack (show (VU.length features))
            <> ")"
        )
  | not (VU.all isFiniteCifarValue features) =
      Left "CIFAR-10 RGB input contains a non-finite value"
  | not (VU.all (\value -> value >= 0.0 && value <= 1.0) features) =
      Left "CIFAR-10 RGB input must remain in decoded [0,1] units"
  | otherwise = Right ()
 where
  features = Classifier.exampleFeatures example

foldCifarChannel
  :: Int
  -> (Double -> Double -> Double)
  -> Double
  -> Classifier.Dataset
  -> Double
foldCifarChannel channel step =
  List.foldl'
    ( \total example ->
        VU.ifoldl'
          ( \subtotal index value ->
              if index `mod` cifar10ChannelCount == channel
                then step subtotal value
                else subtotal
          )
          total
          (Classifier.exampleFeatures example)
    )

requirePositiveCifarScale :: Double -> Either Text ()
requirePositiveCifarScale scale = do
  requireFiniteCifarValue "input scale" scale
  if scale > 0.0
    then Right ()
    else Left "CIFAR-10 RGB standardization input scale must be positive"

requireFiniteCifarValue :: Text -> Double -> Either Text ()
requireFiniteCifarValue label value
  | isFiniteCifarValue value = Right ()
  | otherwise = Left ("CIFAR-10 RGB standardization " <> label <> " must be finite")

isFiniteCifarValue :: Double -> Bool
isFiniteCifarValue value = not (isNaN value || isInfinite value)

-- | Sprint 8.13 — promote the architecture's 'Architecture.SlRunMetrics' plus
-- the held-out test metric into the training-execution 'TrainingMetrics' the publishers
-- consume.
trainingMetricsFor
  :: Int
  -> Text
  -> Architecture.TrainedArchitecture
  -> Architecture.SlRunMetrics
  -> Maybe Double
  -> Text
  -> VU.Vector Double
  -> VU.Vector Double
  -> Either Text TrainingMetrics
trainingMetricsFor completedEpochs datasetShaAtRead trained metrics heldOut metricLabel probeInput probeOutput = do
  if completedEpochs <= 0
    then Left "supervised completed epoch count must be positive"
    else Right ()
  if Architecture.slmOptimizerUpdatesExecuted metrics <= 0
    then Left "supervised executed optimizer-update count must be positive"
    else Right ()
  runtime <- Architecture.projectTrainedArchitectureRuntime trained
  validateTrainingParityProbe runtime probeInput probeOutput
  let initialWeights = Architecture.slmInitialWeights metrics
      finalWeights = Architecture.trainedArchitectureWeights trained
  (initialBytes, finalBytes) <-
    exactRuntimeWeightBytes runtime initialWeights finalWeights
  Right
    TrainingMetrics
      { tmTrainLoss = Architecture.slmTrainLoss metrics
      , tmValidationLoss = Architecture.slmValidationLoss metrics
      , tmExamplesProcessed = Architecture.slmExamplesProcessed metrics
      , tmHeldOutMetric = fmap (metricLabel,) heldOut
      , tmCompletedUnits = fromIntegral completedEpochs
      , tmOptimizerUpdatesExecuted = Architecture.slmOptimizerUpdatesExecuted metrics
      , tmInitialCheckpointWeights = Just initialWeights
      , tmCheckpointWeights = Just finalWeights
      , tmDatasetShaAtRead = Just datasetShaAtRead
      , tmSupervisedRuntimeProgram = runtime
      , tmInitialJmw1Bytes = initialBytes
      , tmFinalJmw1Bytes = finalBytes
      , tmVerifiedDatasetShaAtRead = datasetShaAtRead
      , tmParityProbeInput = VU.toList probeInput
      , tmParityProbeOutput = VU.toList probeOutput
      }

validateTrainingParityProbe
  :: RuntimeArtifact.RawSupervisedRuntime
  -> VU.Vector Double
  -> VU.Vector Double
  -> Either Text ()
validateTrainingParityProbe rawRuntime probeInput probeOutput = do
  runtime <- RuntimeArtifact.refineSupervisedRuntime rawRuntime
  requireWidth
    "input"
    (RuntimeArtifact.supervisedRuntimeInputWidth runtime)
    probeInput
  requireWidth
    "output"
    ( RuntimeArtifact.runtimeTaskSemanticWidth
        (RuntimeArtifact.supervisedRuntimeTask runtime)
    )
    probeOutput
  requireFiniteVector "input" probeInput
  requireFiniteVector "output" probeOutput
 where
  requireWidth label expected actual
    | VU.length actual == expected = Right ()
    | otherwise =
        Left
          ( "supervised parity probe "
              <> label
              <> " width differs from the runtime contract (expected="
              <> Text.pack (show expected)
              <> ", actual="
              <> Text.pack (show (VU.length actual))
              <> ")"
          )
  requireFiniteVector label values
    | VU.all (\value -> not (isNaN value || isInfinite value)) values = Right ()
    | otherwise = Left ("supervised parity probe " <> label <> " contains a non-finite value")

exactRuntimeWeightBytes
  :: RuntimeArtifact.RawSupervisedRuntime
  -> [Double]
  -> [Double]
  -> Either Text (LazyByteString.ByteString, LazyByteString.ByteString)
exactRuntimeWeightBytes rawRuntime initialWeights finalWeights = do
  runtime <- RuntimeArtifact.refineSupervisedRuntime rawRuntime
  let expected = RuntimeArtifact.supervisedRuntimeParameterCount runtime
  requireCount "initial" expected initialWeights
  requireCount "final" expected finalWeights
  let initialBytes = WeightCodec.encodeJmw1 initialWeights
      finalBytes = WeightCodec.encodeJmw1 finalWeights
  decodedInitial <- WeightCodec.decodeJmw1 initialBytes
  decodedFinal <- WeightCodec.decodeJmw1 finalBytes
  if WeightCodec.encodeJmw1 decodedInitial == initialBytes
    && WeightCodec.encodeJmw1 decodedFinal == finalBytes
    then Right (initialBytes, finalBytes)
    else Left "supervised exact JMW1 bytes were not canonical under decode/re-encode"
 where
  requireCount label expected actual
    | length actual == expected = Right ()
    | otherwise =
        Left
          ( "supervised "
              <> label
              <> " weight count differs from runtime graph (expected="
              <> Text.pack (show expected)
              <> ", actual="
              <> Text.pack (show (length actual))
              <> ")"
          )

-- | Sprint 8.13 — render the @jitml train@ stdout summary with the real
-- cross-entropy train/validation losses, the deterministic throughput metric,
-- the train accuracy, and the held-out test metric. Replaces the prior
-- @train_acc=…@-only line that hid the faked loss.
renderTrainingMetricsLine
  :: Substrate
  -> SL.CanonicalProblem
  -> Maybe Text
  -> Int
  -> Int
  -> Architecture.SlRunMetrics
  -> Maybe Double
  -> Text
  -> Text
renderTrainingMetricsLine substrate problem archiveName trainLimit epochs metrics heldOut metricLabel =
  "train: "
    <> SL.problemName problem
    <> " model="
    <> SL.problemModel problem
    <> " substrate="
    <> renderSubstrate substrate
    <> maybe "" (" archive=" <>) archiveName
    <> " limit="
    <> Text.pack (show trainLimit)
    <> " epochs="
    <> Text.pack (show epochs)
    <> " train_loss="
    <> Text.pack (show (Architecture.slmTrainLoss metrics))
    <> " val_loss="
    <> Text.pack (show (Architecture.slmValidationLoss metrics))
    <> " train_acc="
    <> Text.pack (show (Architecture.slmTrainAccuracy metrics))
    <> " examples_processed="
    <> Text.pack (show (Architecture.slmExamplesProcessed metrics))
    <> maybe "" (\a -> " " <> metricLabel <> "=" <> Text.pack (show a)) heldOut
    <> "\n"

-- | Sprint 8.10 — drive the substrate-backed differentiable SL classifier
-- over the canonical dataset bytes staged in MinIO. Returns @Right metrics@
-- (real cross-entropy train + held-out validation loss, deterministic
-- throughput, and the held-out test accuracy) when real device training ran, or
-- @Left reason@ when a hard prerequisite (live publication, staged dataset ref,
-- staged bytes) is absent or the device training itself failed. There is no
-- synthetic fallback: a missing prerequisite is a 'Left', never a fabricated
-- curve. The exact example, epoch, evaluation, and batch quantities come from
-- one re-refined supervised plan; the worker never reconstructs or clamps
-- primitive mounted values.
runDeviceMnistTraining
  :: TrainingExecutionRuntime
  -> Substrate
  -> SL.CanonicalProblem
  -> WorkloadPlan.SupervisedPlan
  -> App (Either Text TrainingMetrics)
runDeviceMnistTraining runtime substrate problem plan =
  case (,) <$> supervisedExecutionBudget plan <*> supervisedExecutionSeed plan of
    Left err -> pure (Left err)
    Right ((trainLimit, epochs, testLimit, batchSize), executionSeed) ->
      runDeviceMnistTrainingWithSeedAndLimitsAndLearningRate
        runtime
        substrate
        problem
        executionSeed
        trainLimit
        epochs
        testLimit
        batchSize
        Nothing
{-# NOINLINE runDeviceMnistTraining #-}

-- | ProductRow/public exact-budget helper.  Product projections already bind
-- the canonical problem seed, so this compatibility boundary deliberately
-- retains that seed while the generic resolved-plan entrypoint above supplies
-- its own exact plan seed.
runDeviceMnistTrainingWithLimitsAndLearningRate
  :: TrainingExecutionRuntime
  -> Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Int
  -> Int
  -> Int
  -> Maybe Double
  -> App (Either Text TrainingMetrics)
runDeviceMnistTrainingWithLimitsAndLearningRate runtime substrate problem =
  runDeviceMnistTrainingWithSeedAndLimitsAndLearningRate
    runtime
    substrate
    problem
    (SL.problemSeed problem)
{-# NOINLINE runDeviceMnistTrainingWithLimitsAndLearningRate #-}

runDeviceMnistTrainingWithSeedAndLimitsAndLearningRate
  :: TrainingExecutionRuntime
  -> Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Maybe Double
  -> App (Either Text TrainingMetrics)
runDeviceMnistTrainingWithSeedAndLimitsAndLearningRate runtime substrate problem executionSeed trainLimit epochs testLimit batchSize learningRateOverride = do
  env <- ask
  minioSettingsMaybe <- trainingResolveMinIOSettings runtime
  case minioSettingsMaybe of
    Nothing ->
      pure (Left "no live cluster publication (run `jitml bootstrap --<substrate>`)")
    Just minioSettings ->
      case Dataset.datasetForProblem problem of
        Just trainRef
          | hasCanonicalLabels trainRef -> do
              let run :: MinIOSubprocess.MinIOSubprocess a -> App a
                  run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
              imagesE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
              labelsE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
              case (imagesE, labelsE) of
                (Right imgArtifact, Right lblArtifact) -> do
                  let config =
                        ( Classifier.defaultClassifierConfig
                            { Classifier.clfSeed = executionSeed
                            , Classifier.clfEpochs = epochs
                            , Classifier.clfBatchSize = batchSize
                            }
                        )
                          { Classifier.clfLearningRate =
                              fromMaybe
                                (Classifier.clfLearningRate Classifier.defaultClassifierConfig)
                                learningRateOverride
                          }
                      device = mlpDeviceForSubstrate substrate env
                      decodedE =
                        case trainingMaterializationLimit trainLimit of
                          Left err -> Left err
                          Right materializationLimit ->
                            case Classifier.decodeBoundedDataset
                              config
                              (Just materializationLimit)
                              (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload imgArtifact))
                              (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload lblArtifact)) of
                              Left err -> Left (Text.pack err)
                              Right value -> Right value
                  case decodedE of
                    Left err -> pure (Left err)
                    Right (configForData, dataset) -> do
                      let spec = Architecture.architectureSpecForProblem configForData problem
                          trainSet = take trainLimit dataset
                          validationSet = drop trainLimit dataset
                      if length trainSet /= trainLimit || null validationSet
                        then pure (Left "supervised dataset cannot satisfy exact training/validation example budgets")
                        else do
                          trainedE <-
                            liftIO
                              ( Architecture.trainCanonicalArchitectureWithDeviceSelected
                                  device
                                  spec
                                  configForData
                                  trainSet
                                  validationSet
                              )
                          case trainedE of
                            Left err -> pure (Left ("substrate training failed: " <> err))
                            Right (trained, metrics) -> do
                              testAccE <-
                                evaluateTestSplitDevice
                                  device
                                  minioSettings
                                  trainRef
                                  trained
                                  testLimit
                              case testAccE of
                                Left err -> pure (Left err)
                                Right (testAcc, testArtifacts, probeInput, probeOutput) ->
                                  let datasetShaAtRead =
                                        Dataset.datasetReadShaForArtifacts
                                          ([imgArtifact, lblArtifact] <> testArtifacts)
                                   in case trainingMetricsFor
                                        epochs
                                        datasetShaAtRead
                                        trained
                                        metrics
                                        testAcc
                                        "test_accuracy"
                                        probeInput
                                        probeOutput of
                                        Left err -> pure (Left err)
                                        Right trainingMetrics -> do
                                          writeText
                                            ( renderTrainingMetricsLine
                                                substrate
                                                problem
                                                Nothing
                                                trainLimit
                                                epochs
                                                metrics
                                                testAcc
                                                "test_accuracy"
                                            )
                                          pure (Right trainingMetrics)
                _ ->
                  pure
                    ( Left
                        ( datasetFetchFailure
                            ("dataset bytes not staged in MinIO for " <> Dataset.datasetName trainRef)
                            [imagesE, labelsE]
                        )
                    )
          | Dataset.datasetName trainRef == "CIFAR-10" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                executionSeed
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                learningRateOverride
                minioSettings
                Classifier.decodeCifar10ArchiveBoundedDataset
          | Dataset.datasetName trainRef == "CIFAR-100" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                executionSeed
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                learningRateOverride
                minioSettings
                Classifier.decodeCifar100ArchiveBoundedDataset
          | Dataset.datasetName trainRef == "Tiny ImageNet" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                executionSeed
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                learningRateOverride
                minioSettings
                TinyImageNet.decodeTinyImageNetArchiveBoundedClassificationDataset
          | Dataset.datasetName trainRef == "California Housing" && hasCanonicalArchive trainRef ->
              runDeviceCaliforniaHousingTraining
                substrate
                problem
                executionSeed
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                ( fromMaybe
                    (Regression.regLearningRate Regression.defaultRegressionConfig)
                    learningRateOverride
                )
                minioSettings
        _ ->
          pure
            (Left ("no staged canonical dataset for problem " <> SL.problemName problem))
{-# NOINLINE runDeviceMnistTrainingWithSeedAndLimitsAndLearningRate #-}

runDeviceArchiveClassifierTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> Int
  -> Int
  -> Maybe Double
  -> MinIOSubprocess.MinIOSettings
  -> ( Classifier.ClassifierConfig
       -> Dataset.DatasetSplit
       -> Maybe Int
       -> Data.ByteString.ByteString
       -> Either String (Classifier.ClassifierConfig, Classifier.Dataset)
     )
  -> App (Either Text TrainingMetrics)
runDeviceArchiveClassifierTraining substrate problem executionSeed trainRef trainLimit epochs testLimit batchSize learningRateOverride minioSettings decodeArchive = do
  env <- ask
  let run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      config =
        ( Classifier.defaultClassifierConfig
            { Classifier.clfSeed = executionSeed
            , Classifier.clfEpochs = epochs
            , Classifier.clfBatchSize = batchSize
            }
        )
          { Classifier.clfLearningRate =
              fromMaybe
                (Classifier.clfLearningRate Classifier.defaultClassifierConfig)
                learningRateOverride
          }
      device = mlpDeviceForSubstrate substrate env
  archiveE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left err ->
      pure
        ( Left
            ( datasetFetchFailure
                ("dataset archive not staged in MinIO for " <> Dataset.datasetName trainRef)
                [Left err]
            )
        )
    Right archiveArtifact ->
      let archiveBytes = Dataset.fetchedArtifactPayload archiveArtifact
          datasetShaAtRead = Dataset.datasetReadShaForArtifacts [archiveArtifact]
       in case trainingMaterializationLimit trainLimit of
            Left err -> pure (Left err)
            Right materializationLimit ->
              case decodeArchive
                config
                Dataset.TrainSplit
                (Just materializationLimit)
                archiveBytes of
                Left err -> pure (Left (Text.pack err))
                Right (configForData, dataset) -> do
                  let spec = Architecture.architectureSpecForProblem configForData problem
                      rawTrainSet = take trainLimit dataset
                      rawValidationSet = drop trainLimit dataset
                  if length rawTrainSet /= trainLimit || null rawValidationSet
                    then pure (Left "supervised archive cannot satisfy exact training/validation example budgets")
                    else case archiveClassifierTrainingInput
                      problem
                      rawTrainSet
                      rawValidationSet of
                      Left err -> pure (Left err)
                      Right (inputTransform, trainSet, validationSet) -> do
                        trainedE <-
                          liftIO
                            ( Architecture.trainCanonicalArchitectureWithDeviceSelected
                                device
                                spec
                                configForData
                                trainSet
                                validationSet
                            )
                        case trainedE of
                          Left err -> pure (Left ("substrate archive training failed: " <> err))
                          Right (unboundTrained, metrics) ->
                            case bindArchiveClassifierInputTransform inputTransform unboundTrained of
                              Left err -> pure (Left err)
                              Right trained ->
                                case decodeArchive configForData Dataset.TestSplit (Just testLimit) archiveBytes of
                                  Left err -> pure (Left (Text.pack err))
                                  Right (_, rawTestSet)
                                    | length rawTestSet /= testLimit ->
                                        pure (Left "supervised archive cannot satisfy exact evaluation-example budget")
                                    | otherwise ->
                                        case applyArchiveClassifierInputTransform inputTransform rawTestSet of
                                          Left err -> pure (Left err)
                                          Right testSet -> do
                                            testAccE <-
                                              liftIO
                                                (Architecture.accuracyArchitectureWithDevice device trained testSet)
                                            case (rawTestSet, testSet) of
                                              ([], _) -> pure (Left "supervised archive produced no parity probe")
                                              (_, []) -> pure (Left "supervised archive produced no parity probe")
                                              (rawProbe : _, probe : _) -> do
                                                predictionE <-
                                                  liftIO
                                                    ( Architecture.predictArchitectureWithDevice
                                                        device
                                                        trained
                                                        (Classifier.exampleFeatures probe)
                                                    )
                                                case (testAccE, predictionE) of
                                                  (Left err, _) -> pure (Left err)
                                                  (_, Left err) -> pure (Left err)
                                                  (Right testAcc, Right rawPrediction) ->
                                                    let semanticWidth = Classifier.clfClasses configForData
                                                     in if VU.length rawPrediction < semanticWidth
                                                          then
                                                            pure
                                                              ( Left
                                                                  "training-returned archive classifier output is narrower than its semantic class width"
                                                              )
                                                          else case trainingMetricsFor
                                                            epochs
                                                            datasetShaAtRead
                                                            trained
                                                            metrics
                                                            (Just testAcc)
                                                            "test_accuracy"
                                                            (Classifier.exampleFeatures rawProbe)
                                                            (VU.take semanticWidth rawPrediction) of
                                                            Left err -> pure (Left err)
                                                            Right trainingMetrics -> do
                                                              writeText
                                                                ( renderTrainingMetricsLine
                                                                    substrate
                                                                    problem
                                                                    (Just (Dataset.datasetName trainRef))
                                                                    trainLimit
                                                                    epochs
                                                                    metrics
                                                                    (Just testAcc)
                                                                    "test_accuracy"
                                                                )
                                                              pure (Right trainingMetrics)

archiveClassifierTrainingInput
  :: SL.CanonicalProblem
  -> Classifier.Dataset
  -> Classifier.Dataset
  -> Either
       Text
       ( Maybe RuntimeArtifact.RawRuntimeInputTransform
       , Classifier.Dataset
       , Classifier.Dataset
       )
archiveClassifierTrainingInput problem rawTrainSet rawValidationSet
  | SL.problemName problem == "cifar10-vit" = do
      inputTransform <- fitCifar10RgbInputTransform rawTrainSet
      trainSet <- applyCifar10RgbInputTransform inputTransform rawTrainSet
      validationSet <- applyCifar10RgbInputTransform inputTransform rawValidationSet
      Right (Just inputTransform, trainSet, validationSet)
  | otherwise = Right (Nothing, rawTrainSet, rawValidationSet)

applyArchiveClassifierInputTransform
  :: Maybe RuntimeArtifact.RawRuntimeInputTransform
  -> Classifier.Dataset
  -> Either Text Classifier.Dataset
applyArchiveClassifierInputTransform inputTransform dataset =
  case inputTransform of
    Nothing -> Right dataset
    Just transform -> applyCifar10RgbInputTransform transform dataset

bindArchiveClassifierInputTransform
  :: Maybe RuntimeArtifact.RawRuntimeInputTransform
  -> Architecture.TrainedArchitecture
  -> Either Text Architecture.TrainedArchitecture
bindArchiveClassifierInputTransform inputTransform trained =
  case inputTransform of
    Nothing -> Right trained
    Just transform -> Architecture.bindTrainedArchitectureInputTransform transform trained

runDeviceCaliforniaHousingTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> Int
  -> Int
  -> Double
  -> MinIOSubprocess.MinIOSettings
  -> App (Either Text TrainingMetrics)
runDeviceCaliforniaHousingTraining substrate problem executionSeed trainRef trainLimit epochs testLimit batchSize learningRate minioSettings = do
  env <- ask
  let run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      device = mlpDeviceForSubstrate substrate env
  archiveE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left err ->
      pure
        ( Left
            ( datasetFetchFailure
                ("dataset archive not staged in MinIO for " <> Dataset.datasetName trainRef)
                [Left err]
            )
        )
    Right archiveArtifact ->
      let archiveBytes = Dataset.fetchedArtifactPayload archiveArtifact
          datasetShaAtRead = Dataset.datasetReadShaForArtifacts [archiveArtifact]
       in case regressionMaterializationLimit trainLimit testLimit of
            Left err -> pure (Left err)
            Right materializationLimit ->
              case Regression.decodeCaliforniaHousingArchiveBoundedData (Just materializationLimit) archiveBytes of
                Left err -> pure (Left (Text.pack err))
                Right dataset ->
                  finishCaliforniaHousingTraining
                    substrate
                    problem
                    executionSeed
                    trainRef
                    trainLimit
                    epochs
                    testLimit
                    batchSize
                    learningRate
                    device
                    datasetShaAtRead
                    dataset

finishCaliforniaHousingTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> Int
  -> Int
  -> Double
  -> MlpDevice
  -> Text
  -> [Regression.RegressionExample]
  -> App (Either Text TrainingMetrics)
finishCaliforniaHousingTraining substrate problem executionSeed trainRef trainLimit epochs testLimit batchSize learningRate device datasetShaAtRead dataset =
  case listToMaybe dataset of
    Nothing -> pure (Left "California Housing archive produced no rows")
    Just firstExample -> do
      let rawTrainSet = take trainLimit dataset
          rawValidationSet = take testLimit (drop trainLimit dataset)
          config =
            Regression.defaultRegressionConfig
              { Regression.regSeed = executionSeed
              , Regression.regInputs = VU.length (Regression.regressionFeatures firstExample)
              , Regression.regEpochs = epochs
              , Regression.regBatchSize = batchSize
              , Regression.regLearningRate = learningRate
              }
      if length rawTrainSet /= trainLimit || length rawValidationSet /= testLimit
        then pure (Left "supervised regression cannot satisfy exact train/evaluation budgets")
        else case Regression.fitRegressionStandardization rawTrainSet of
          Left err -> pure (Left ("regression training-statistics fit failed: " <> err))
          Right standardization ->
            case ( Regression.applyRegressionStandardizationDataset standardization rawTrainSet
                 , Regression.applyRegressionStandardizationDataset standardization rawValidationSet
                 ) of
              (Left err, _) -> pure (Left ("regression training transform failed: " <> err))
              (_, Left err) -> pure (Left ("regression held-out transform failed: " <> err))
              (Right trainSet, Right validationSet) -> do
                trainedE <- liftIO (Regression.trainRegressorWithDevice device config trainSet)
                case trainedE of
                  Left err -> pure (Left ("substrate regression training failed: " <> err))
                  Right (trained, regressionMetrics) -> do
                    let trainMse = Regression.regressionTrainMse regressionMetrics
                        optimizerUpdatesExecuted =
                          Regression.regressionOptimizerUpdatesExecuted regressionMetrics
                    validationMseE <-
                      liftIO
                        ( Regression.meanSquaredErrorWithDevice
                            device
                            trained
                            validationSet
                        )
                    case validationMseE of
                      Left err -> pure (Left ("held-out regression evaluation failed: " <> err))
                      Right validationMse -> do
                        if optimizerUpdatesExecuted <= 0
                          then pure (Left "regression executed optimizer-update count must be positive")
                          else do
                            probeE <-
                              liftIO
                                ( californiaHousingParityProbe
                                    device
                                    standardization
                                    trained
                                    rawValidationSet
                                    validationSet
                                )
                            case probeE of
                              Left err -> pure (Left err)
                              Right (probeInput, probeOutput) ->
                                let examplesProcessed = length trainSet * epochs
                                    initialShape =
                                      MlpShape
                                        { mlpInputs = Regression.regInputs config
                                        , mlpHidden = Regression.regHidden config
                                        , mlpOutputs = 1
                                        }
                                    initialWeights =
                                      mlpParamsToFlat (mlpInit initialShape (Regression.regSeed config))
                                    finalWeights =
                                      mlpParamsToFlat (Regression.trainedRegressorParams trained)
                                 in case californiaHousingRuntimeProgram problem config standardization trained of
                                      Left err -> pure (Left err)
                                      Right runtime ->
                                        case validateTrainingParityProbe runtime probeInput probeOutput of
                                          Left err -> pure (Left err)
                                          Right () ->
                                            case exactRuntimeWeightBytes runtime initialWeights finalWeights of
                                              Left err -> pure (Left err)
                                              Right (initialBytes, finalBytes) -> do
                                                writeText
                                                  ( "train: "
                                                      <> SL.problemName problem
                                                      <> " model="
                                                      <> SL.problemModel problem
                                                      <> " substrate="
                                                      <> renderSubstrate substrate
                                                      <> " archive="
                                                      <> Dataset.datasetName trainRef
                                                      <> " limit="
                                                      <> Text.pack (show trainLimit)
                                                      <> " epochs="
                                                      <> Text.pack (show epochs)
                                                      <> " train_mse="
                                                      <> Text.pack (show trainMse)
                                                      <> " val_mse="
                                                      <> Text.pack (show validationMse)
                                                      <> " examples_processed="
                                                      <> Text.pack (show examplesProcessed)
                                                      <> "\n"
                                                  )
                                                pure
                                                  ( Right
                                                      TrainingMetrics
                                                        { tmTrainLoss = trainMse
                                                        , tmValidationLoss = validationMse
                                                        , tmExamplesProcessed = examplesProcessed
                                                        , tmHeldOutMetric = Just ("rmse", sqrt validationMse)
                                                        , tmCompletedUnits = fromIntegral epochs
                                                        , tmOptimizerUpdatesExecuted = optimizerUpdatesExecuted
                                                        , tmInitialCheckpointWeights = Just initialWeights
                                                        , tmCheckpointWeights = Just finalWeights
                                                        , tmDatasetShaAtRead = Just datasetShaAtRead
                                                        , tmSupervisedRuntimeProgram = runtime
                                                        , tmInitialJmw1Bytes = initialBytes
                                                        , tmFinalJmw1Bytes = finalBytes
                                                        , tmVerifiedDatasetShaAtRead = datasetShaAtRead
                                                        , tmParityProbeInput = VU.toList probeInput
                                                        , tmParityProbeOutput = VU.toList probeOutput
                                                        }
                                                  )

californiaHousingParityProbe
  :: MlpDevice
  -> Regression.RegressionStandardization
  -> Regression.TrainedRegressor
  -> [Regression.RegressionExample]
  -> [Regression.RegressionExample]
  -> IO (Either Text (VU.Vector Double, VU.Vector Double))
californiaHousingParityProbe device standardization trained rawHeldOut standardizedHeldOut =
  case (listToMaybe rawHeldOut, listToMaybe standardizedHeldOut) of
    (Just rawProbe, Just standardizedProbe) -> do
      predictionE <-
        Regression.predictRegressorWithDevice
          device
          trained
          (Regression.regressionFeatures standardizedProbe)
      pure $ do
        standardizedPrediction <- predictionE
        rawPrediction <-
          Regression.inverseRegressionTarget standardization standardizedPrediction
        Right
          ( Regression.regressionFeatures rawProbe
          , VU.singleton rawPrediction
          )
    _ -> pure (Left "supervised regression produced no held-out parity probe")

californiaHousingRuntimeProgram
  :: SL.CanonicalProblem
  -> Regression.RegressionConfig
  -> Regression.RegressionStandardization
  -> Regression.TrainedRegressor
  -> Either Text RuntimeArtifact.RawSupervisedRuntime
californiaHousingRuntimeProgram problem expectedConfig standardization trained = do
  if problem `elem` SL.canonicalProblems
    then Right ()
    else
      Left
        ( "tabular-regression runtime problem is not an exact canonical row: "
            <> SL.problemName problem
        )
  if SL.problemDataset problem == "California Housing"
    && SL.problemModel problem == "Dense"
    then Right ()
    else
      Left
        ( "tabular-regression runtime requires the exact California Housing/Dense row, got "
            <> SL.problemDataset problem
            <> "/"
            <> SL.problemModel problem
        )
  let actualConfig = Regression.trainedRegressorConfig trained
      params = Regression.trainedRegressorParams trained
      expectedShape =
        MlpShape
          { mlpInputs = Regression.regInputs actualConfig
          , mlpHidden = Regression.regHidden actualConfig
          , mlpOutputs = 1
          }
  if actualConfig == expectedConfig
    then Right ()
    else Left "tabular-regression trained config differs from the config supplied to training"
  if paramShape params == expectedShape
    then Right ()
    else
      Left
        ( "tabular-regression parameter shape differs from the trained config (expected="
            <> Text.pack (show expectedShape)
            <> ", actual="
            <> Text.pack (show (paramShape params))
            <> ")"
        )
  let rawRuntime =
        RuntimeArtifact.RawSupervisedRuntime
          { RuntimeArtifact.rawSupervisedRuntimeFamily =
              RuntimeArtifact.RawTabularRegressionRuntimeFamily
          , RuntimeArtifact.rawSupervisedRuntimeTask =
              RuntimeArtifact.RawRegressionRuntimeTask 1
          , RuntimeArtifact.rawSupervisedRuntimeInputTransform =
              RuntimeArtifact.RawStandardizeInput
                (Regression.regressionFeatureMeans standardization)
                (Regression.regressionFeatureScales standardization)
          , RuntimeArtifact.rawSupervisedRuntimeOutputTransform =
              RuntimeArtifact.RawDestandardizeOutput
                [Regression.regressionTargetMean standardization]
                [Regression.regressionTargetScale standardization]
          , RuntimeArtifact.rawSupervisedRuntimeLayers =
              [ RuntimeArtifact.RawDenseLayer
                  "regressor"
                  RuntimeArtifact.RawRuntimeMlpShape
                    { RuntimeArtifact.rawRuntimeMlpInputs = mlpInputs (paramShape params)
                    , RuntimeArtifact.rawRuntimeMlpHidden = mlpHidden (paramShape params)
                    , RuntimeArtifact.rawRuntimeMlpOutputs = mlpOutputs (paramShape params)
                    }
              ]
          }
  refined <- RuntimeArtifact.refineSupervisedRuntime rawRuntime
  if RuntimeArtifact.supervisedRuntimeToRaw refined == rawRuntime
    then Right rawRuntime
    else Left "tabular-regression runtime did not survive exact refinement"

-- | True when a problem's dataset has a published canonical label SHA, i.e.
-- real label bytes are stageable in MinIO (not the synthetic per-(name,
-- split, size) fixture).
hasCanonicalLabels :: Dataset.DatasetRef -> Bool
hasCanonicalLabels ref =
  isJust
    ( Dataset.canonicalArtifactSha256For
        (Dataset.datasetName ref)
        Dataset.TrainSplit
        Dataset.LabelsArtifact
    )

hasCanonicalArchive :: Dataset.DatasetRef -> Bool
hasCanonicalArchive ref =
  isJust
    ( Dataset.canonicalArtifactSha256For
        (Dataset.datasetName ref)
        Dataset.TrainSplit
        Dataset.ArchiveArtifact
    )

-- | Fetch the verified test images and labels, retain both exact artifact
-- identities for the completion digest, and report held-out accuracy through
-- the selected device. Missing, substituted, or malformed objects fail closed.
evaluateTestSplitDevice
  :: MlpDevice
  -> MinIOSubprocess.MinIOSettings
  -> Dataset.DatasetRef
  -> Architecture.TrainedArchitecture
  -> Int
  -> App
       ( Either
           Text
           ( Maybe Double
           , [Dataset.DatasetArtifactBytes]
           , VU.Vector Double
           , VU.Vector Double
           )
       )
evaluateTestSplitDevice device minioSettings trainRef trained limit = do
  let testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
      run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
  testImgE <- run (Dataset.fetchVerifiedDatasetArtifactBytes testRef Dataset.ImagesArtifact)
  testLblE <- run (Dataset.fetchVerifiedDatasetArtifactBytes testRef Dataset.LabelsArtifact)
  case (testImgE, testLblE) of
    (Right tiArtifact, Right tlArtifact) ->
      case ( Classifier.parseIdxImages (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload tiArtifact))
           , Classifier.parseIdxLabels (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload tlArtifact))
           ) of
        (Right (_, images), Right labels) -> do
          let testSet = take limit (Classifier.zipImagesLabels images labels)
          if length testSet /= limit
            then pure (Left "supervised test split cannot satisfy exact evaluation-example budget")
            else do
              accE <- liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
              case testSet of
                [] -> pure (Left "supervised test split produced no parity probe")
                probe : _ -> do
                  predictionE <-
                    liftIO
                      ( Architecture.predictArchitectureWithDevice
                          device
                          trained
                          (Classifier.exampleFeatures probe)
                      )
                  pure $ do
                    accuracy <- accE
                    rawPrediction <- predictionE
                    let semanticWidth =
                          Classifier.clfClasses
                            (Architecture.trainedArchConfig trained)
                    if VU.length rawPrediction < semanticWidth
                      then
                        Left
                          "training-returned classifier output is narrower than its semantic class width"
                      else
                        Right
                          ( Just accuracy
                          , [tiArtifact, tlArtifact]
                          , Classifier.exampleFeatures probe
                          , VU.take semanticWidth rawPrediction
                          )
        _ -> pure (Left "supervised test split IDX decode failed")
    _ ->
      pure
        ( Left
            ( datasetFetchFailure
                ("test dataset bytes not staged in MinIO for " <> Dataset.datasetName testRef)
                [testImgE, testLblE]
            )
        )

datasetFetchFailure :: Text -> [Either ServiceError a] -> Text
datasetFetchFailure fallback results =
  case [message | Left (SEConflict message) <- results] of
    message : _ -> message
    [] -> fallback

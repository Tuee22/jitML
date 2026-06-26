{-# LANGUAGE OverloadedStrings #-}

module Main where

import Codec.Archive.Zip qualified as Zip
import Codec.Compression.GZip qualified as GZip
import Codec.Picture qualified as Picture
import Control.Monad (forM_)
import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (lefts)
import Data.Maybe qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64, Word8)
import Numeric (showOct)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.SL.Classifier
  ( ClassifierConfig (..)
  , Dataset
  , LabeledExample (..)
  , accuracy
  , classify
  , crossEntropyLoss
  , decodeBoundedDataset
  , decodeCifar100ArchiveBoundedDataset
  , decodeCifar100BoundedDataset
  , decodeCifar10ArchiveBoundedDataset
  , decodeCifar10BoundedDataset
  , defaultClassifierConfig
  , parseCifar100BinaryBatch
  , parseCifar10BinaryBatch
  , parseIdxImages
  , parseIdxLabels
  , trainClassifier
  , trainClassifierFromIdxBounded
  , trainClassifierWithDevice
  , zipImagesLabels
  )

import JitML.Bootstrap (readExistingLivePublication)
import JitML.Cluster.Publication (publicationEdgePort, publicationSubstrate)
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Proto.Training
  ( CheckpointDone (..)
  , EpochCompleted (..)
  , StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , TrainingEvent (..)
  , TrainingFailed (..)
  , decodeTrainingCommandProto
  , decodeTrainingEventProto
  , encodeTrainingCommandProto
  , encodeTrainingEventProto
  , parseTrainingCommand
  , renderTrainingCommand
  )
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals
  ( canonicalProblems
  , problemName
  , trainableCanonicalCohort
  )
import JitML.SL.Canonicals qualified as SL
import JitML.SL.ConvergenceThresholds
  ( SlConvergenceThreshold (..)
  , passesSlConvergence
  , slCohortThreshold
  , slCohortThresholds
  )
import JitML.SL.Dataset
  ( datasetFixtureBytes
  , datasetForProblem
  , datasetObjectRef
  , datasetRefHash
  , fetchDatasetRef
  , fetchedSha256
  )
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.Regression qualified as Regression
import JitML.SL.TinyImageNet qualified as TinyImageNet
import JitML.Service.Capabilities (HasMinIO (..))
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.MinIOSubprocess
  ( MinIOSubprocess
  , minioSettingsForLocalEdge
  , runMinIOSubprocess
  )
import JitML.Service.Retry (ServiceError)
import JitML.Substrate (Substrate (..))
import JitML.Test.Report
  ( ReportCardKnobs (..)
  , loadReportCardKnobs
  )
import JitML.Training.Budget qualified as TrainingBudget

completedTrainingFixture
  :: TrainingBudget.BudgetKind
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> TrainingBudget.CompletedTraining
completedTrainingFixture kind experimentHash observedUnits metrics =
  either
    (error . Text.unpack)
    id
    ( TrainingBudget.completedTrainingFromMetrics
        TrainingBudget.TrainingBudget
          { TrainingBudget.tbKind = kind
          , TrainingBudget.tbTargetUnits = max 1 observedUnits
          , TrainingBudget.tbUnitLabel = "units"
          , TrainingBudget.tbSeed = Nothing
          }
        observedUnits
        metrics
        TrainingBudget.TensorBoardRunMetadata
          { TrainingBudget.tbrRunId = experimentHash
          , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
          , TrainingBudget.tbrScalarTags = fmap fst metrics
          }
    )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-sl-canonicals"
      [ testCase "canonical supervised problems are populated" $
          fmap problemName canonicalProblems
            @?= [ "mnist-shallow-mlp"
                , "mnist-deep-mlp"
                , "mnist-lenet"
                , "fashion-mnist-mlp"
                , "fashion-mnist-resnet"
                , "cifar10-resnet20"
                , "cifar10-resnet56"
                , "cifar100-wide-resnet"
                , "cifar10-vit"
                , "tiny-imagenet-resnet50"
                , "california-housing-mlp"
                ]
      , testCase "trainable canonical SL cohort covers every product row (Sprint 8.12)" $ do
          fmap problemName trainableCanonicalCohort @?= fmap problemName canonicalProblems
          let config =
                defaultClassifierConfig
                  { clfInputs = 16
                  , clfHidden = 8
                  , clfClasses = 3
                  }
              specs = Architecture.allCanonicalArchitectureSpecs config
          fmap (problemName . Architecture.archProblem) specs @?= fmap problemName canonicalProblems
      , testCase "supervised experiment Dhall resolves the canonical problem row (Sprint 8.12)" $ do
          mnist <- SL.loadCanonicalProblemExperiment "experiments/mnist.dhall"
          fmap problemName mnist @?= Right "mnist-shallow-mlp"
          withSystemTempDirectory "jitml-sl-experiment" $ \dir -> do
            let path = dir <> "/deep.dhall"
            Text.IO.writeFile
              path
              ( Text.unlines
                  [ "{ name = \"mnist-deep-smoke\""
                  , ", dataset = \"MNIST\""
                  , ", model = \"DeepDense\""
                  , ", seed = 1002"
                  , "}"
                  ]
              )
            deep <- SL.loadCanonicalProblemExperiment path
            fmap problemName deep @?= Right "mnist-deep-mlp"
      , testCase "Fashion-MNIST carries real train/test image and label SHA pins (Sprint 8.12)" $ do
          let sha = Dataset.canonicalArtifactSha256For "Fashion-MNIST"
          assertBool
            "train images are pinned"
            (Data.Maybe.isJust (sha Dataset.TrainSplit Dataset.ImagesArtifact))
          assertBool
            "train labels are pinned"
            (Data.Maybe.isJust (sha Dataset.TrainSplit Dataset.LabelsArtifact))
          assertBool
            "test images are pinned"
            (Data.Maybe.isJust (sha Dataset.TestSplit Dataset.ImagesArtifact))
          assertBool
            "test labels are pinned"
            (Data.Maybe.isJust (sha Dataset.TestSplit Dataset.LabelsArtifact))
      , testCase "CIFAR archives carry real SHA pins and parse binary batches (Sprint 8.12)" $ do
          Dataset.canonicalArtifactSha256For "CIFAR-10" Dataset.TrainSplit Dataset.ArchiveArtifact
            @?= Just "c4a38c50a1bc5f3a1c5537f2155ab9d68f9f25eb1ed8d9ddda3db29a59bca1dd"
          Dataset.canonicalArtifactSha256For "CIFAR-100" Dataset.TrainSplit Dataset.ArchiveArtifact
            @?= Just "58a81ae192c23a4be8b1804d68e518ed807d710a4eb253b1f2a199162a40d8ec"
          Dataset.datasetArtifactFileName Dataset.ArchiveArtifact @?= "archive.tar.gz"

          let cifar10Bytes =
                ByteString.pack $
                  cifar10Record 3 [0, 255, 128, 64]
                    <> cifar10Record 7 [10, 20, 30, 40]
              cifar100Bytes =
                ByteString.pack $
                  cifar100Record 2 42 [5, 15, 25, 35]
                    <> cifar100Record 9 17 [45, 55, 65, 75]
          case parseCifar10BinaryBatch cifar10Bytes of
            Left err -> assertFailure ("CIFAR-10 parse failed: " <> err)
            Right examples -> do
              fmap exampleLabel examples @?= [3, 7]
              case examples of
                first : _ -> do
                  VU.length (exampleFeatures first) @?= 3072
                  VU.take 4 (exampleFeatures first) @?= VU.fromList [0.0, 1.0, 128.0 / 255.0, 64.0 / 255.0]
                [] -> assertFailure "expected CIFAR-10 examples"
          case parseCifar100BinaryBatch cifar100Bytes of
            Left err -> assertFailure ("CIFAR-100 parse failed: " <> err)
            Right examples ->
              fmap exampleLabel examples @?= [42, 17]
          case decodeCifar10BoundedDataset defaultClassifierConfig (Just 1) cifar10Bytes of
            Left err -> assertFailure ("CIFAR-10 bounded decode failed: " <> err)
            Right (config, examples) -> do
              clfInputs config @?= 3072
              clfClasses config @?= 10
              length examples @?= 1
          case decodeCifar100BoundedDataset defaultClassifierConfig (Just 1) cifar100Bytes of
            Left err -> assertFailure ("CIFAR-100 bounded decode failed: " <> err)
            Right (config, examples) -> do
              clfInputs config @?= 3072
              clfClasses config @?= 100
              length examples @?= 1
          let cifar10Archive =
                tarArchive
                  ( [ ( "cifar-10-batches-bin/data_batch_" <> show i <> ".bin"
                      , ByteString.pack (cifar10Record (fromIntegral i) [fromIntegral i, 255])
                      )
                    | i <- [1 .. 5 :: Int]
                    ]
                      <> [
                           ( "cifar-10-batches-bin/test_batch.bin"
                           , ByteString.pack (cifar10Record 9 [9, 255])
                           )
                         ]
                  )
              cifar100Archive =
                tarArchive
                  [ ("cifar-100-binary/train.bin", ByteString.pack (cifar100Record 1 11 [1, 255]))
                  , ("cifar-100-binary/test.bin", ByteString.pack (cifar100Record 2 22 [2, 255]))
                  ]
          case decodeCifar10ArchiveBoundedDataset
            defaultClassifierConfig
            Dataset.TrainSplit
            (Just 2)
            cifar10Archive of
            Left err -> assertFailure ("CIFAR-10 archive decode failed: " <> err)
            Right (config, examples) -> do
              clfInputs config @?= 3072
              clfClasses config @?= 10
              fmap exampleLabel examples @?= [1, 2]
          case decodeCifar100ArchiveBoundedDataset
            defaultClassifierConfig
            Dataset.TestSplit
            (Just 1)
            cifar100Archive of
            Left err -> assertFailure ("CIFAR-100 archive decode failed: " <> err)
            Right (config, examples) -> do
              clfInputs config @?= 3072
              clfClasses config @?= 100
              fmap exampleLabel examples @?= [22]
      , testCase "California Housing archive pin and regression parser use real row format (Sprint 8.12)" $ do
          Dataset.canonicalArtifactSha256For "California Housing" Dataset.TrainSplit Dataset.ArchiveArtifact
            @?= Just "aaa5c9a6afe2225cc2aed2723682ae403280c4a3695a2ddda4ffb5d8215ea681"
          let payload =
                Text.Encoding.encodeUtf8 $
                  Text.unlines
                    [ "-122.230000,37.880000,41.000000,880.000000,129.000000,322.000000,126.000000,8.325200,452600.000000"
                    , "-122.220000,37.860000,21.000000,7099.000000,1106.000000,2401.000000,1138.000000,8.301400,358500.000000"
                    ]
          case Regression.parseCaliforniaHousingData payload of
            Left err -> assertFailure ("California Housing parse failed: " <> err)
            Right examples -> do
              length examples @?= 2
              case examples of
                first : _ -> do
                  VU.length (Regression.regressionFeatures first) @?= 8
                  VU.take 2 (Regression.regressionFeatures first) @?= VU.fromList [-122.23, 37.88]
                  Regression.regressionTarget first @?= 452600.0
                [] -> assertFailure "expected California Housing examples"
          case Regression.decodeCaliforniaHousingBoundedData (Just 1) payload of
            Left err -> assertFailure ("California Housing bounded decode failed: " <> err)
            Right examples -> length examples @?= 1
          case Regression.decodeCaliforniaHousingArchiveBoundedData
            (Just 1)
            (tarArchive [("CaliforniaHousing/cal_housing.data", payload)]) of
            Left err -> assertFailure ("California Housing archive decode failed: " <> err)
            Right examples -> length examples @?= 1
      , testCase "Tiny ImageNet archive pin and metadata parsers use real file formats (Sprint 8.12)" $ do
          Dataset.canonicalArtifactSha256For "Tiny ImageNet" Dataset.TrainSplit Dataset.ArchiveArtifact
            @?= Just "6198c8ae015e2b3e007c7841da39ec069199b9aa3bfa943a462022fe5e43c821"
          let wnids =
                Text.Encoding.encodeUtf8 $
                  Text.unlines
                    [ "n01443537"
                    , "n01629819"
                    ]
              wordsFile =
                Text.Encoding.encodeUtf8 $
                  Text.unlines
                    [ "n01443537\tgoldfish, Carassius auratus"
                    , "n01629819\tEuropean fire salamander, Salamandra salamandra"
                    ]
              valAnnotations =
                Text.Encoding.encodeUtf8 $
                  Text.unlines
                    [ "val_0.JPEG\tn01443537\t0\t0\t63\t63"
                    , "val_1.JPEG\tn01629819\t3\t4\t60\t61"
                    ]
          TinyImageNet.parseTinyImageNetWnids wnids @?= Right ["n01443537", "n01629819"]
          case TinyImageNet.parseTinyImageNetWords wordsFile of
            Left err -> assertFailure ("Tiny ImageNet words parse failed: " <> err)
            Right classes -> do
              fmap TinyImageNet.tinyClassId classes @?= ["n01443537", "n01629819"]
              case classes of
                first : _ ->
                  TinyImageNet.tinyClassNames first @?= ["goldfish", "Carassius auratus"]
                [] -> assertFailure "expected Tiny ImageNet classes"
          case TinyImageNet.parseTinyImageNetValAnnotations valAnnotations of
            Left err -> assertFailure ("Tiny ImageNet val_annotations parse failed: " <> err)
            Right annotations -> do
              fmap TinyImageNet.tinyValImage annotations @?= ["val_0.JPEG", "val_1.JPEG"]
              fmap TinyImageNet.tinyValClassId annotations @?= ["n01443537", "n01629819"]
              fmap TinyImageNet.tinyValBoxX1 annotations @?= [63, 60]
          let trainJpeg = tinyJpeg 10 20 30
              valJpeg = tinyJpeg 40 50 60
              archiveBytes =
                zipArchive
                  [ ("tiny-imagenet-200/wnids.txt", wnids)
                  , ("tiny-imagenet-200/train/n01443537/images/n01443537_0.JPEG", trainJpeg)
                  , ("tiny-imagenet-200/val/val_annotations.txt", valAnnotations)
                  , ("tiny-imagenet-200/val/images/val_0.JPEG", valJpeg)
                  , ("tiny-imagenet-200/val/images/val_1.JPEG", valJpeg)
                  ]
          case TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TrainSplit (Just 1) archiveBytes of
            Left err -> assertFailure ("Tiny ImageNet train archive decode failed: " <> err)
            Right examples -> do
              fmap exampleLabel examples @?= [0]
              case examples of
                first : _ -> VU.length (exampleFeatures first) @?= 3
                [] -> assertFailure "expected Tiny ImageNet train example"
          case TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TestSplit (Just 1) archiveBytes of
            Left err -> assertFailure ("Tiny ImageNet validation archive decode failed: " <> err)
            Right examples ->
              fmap exampleLabel examples @?= [0]
      , testCase "dataset refs fetch and SHA-verify through HasMinIO" $
          withSystemTempDirectory "jitml-sl-dataset" $ \dir ->
            -- Sprint 13.4 — the round-trip test runs against a problem
            -- whose dataset still uses the synthetic per-(name, split,
            -- size) SHA. MNIST now carries the canonical upstream SHA
            -- (`Dataset.canonicalSha256For`) so synthetic bytes no
            -- longer hash to its `datasetExpectedSha256`. The first
            -- problem without a canonical SHA in the catalog drives the
            -- assertion; MNIST's live MinIO round-trip is exercised by
            -- the `jitml internal upload-dataset` CLI path against a
            -- real-byte payload.
            case firstSyntheticProblem of
              Just problem ->
                case datasetForProblem problem of
                  Nothing -> assertFailure "expected canonical dataset ref"
                  Just ref -> do
                    writeResult <-
                      runFilesystemMinIO dir $
                        putBlobBytesIfAbsent (datasetObjectRef ref) (datasetFixtureBytes ref)
                    case writeResult of
                      Left err -> assertFailure ("dataset fixture write failed: " <> show err)
                      Right _ -> pure ()
                    fetchResult <- runFilesystemMinIO dir (fetchDatasetRef ref)
                    case fetchResult of
                      Left err -> assertFailure ("dataset fetch failed: " <> show err)
                      Right fetched ->
                        fetchedSha256 fetched @?= datasetRefHash ref
              Nothing -> assertFailure "expected at least one canonical problem with synthetic SHA"
      , testCase "sl-canonicals consumes cabal.project sl_epochs and sl_batch knobs" $ do
          loaded <- loadReportCardKnobs "cabal.project"
          case loaded of
            Left err ->
              assertFailure ("failed to load report-card knobs: " <> Text.unpack err)
            Right knobs -> do
              assertBool
                "sl_epochs knob is positive"
                (knobSlEpochs knobs > 0)
              assertBool
                "sl_batch knob is positive"
                (knobSlBatch knobs > 0)
              assertBool
                "sl_epochs covers at least one device epoch"
                (knobSlEpochs knobs >= 1)
      , testCase "training command envelopes parse after render" $ do
          let start =
                TrainingStart
                  StartTraining
                    { stExperimentHash = "sha256:mnist"
                    , stDhallObjectKey = "experiments/mnist.dhall"
                    , stSubstrate = LinuxCPU
                    , stSeed = 42
                    , stEpochs = 5
                    , stBatchSize = 64
                    }
              stop =
                TrainingStop
                  StopTraining
                    { stopExperimentHash = "sha256:mnist"
                    , stopDrain = True
                    }
          parseTrainingCommand (renderTrainingCommand start) @?= Just start
          parseTrainingCommand (renderTrainingCommand stop) @?= Just stop
          parseTrainingCommand "kind: UnknownTrainingCommand\n" @?= Nothing
          decodeTrainingCommandProto (encodeTrainingCommandProto start) @?= Right start
          decodeTrainingCommandProto (encodeTrainingCommandProto stop) @?= Right stop
      , testCase "training event envelopes round-trip through proto3-compatible bytes" $ do
          let epoch =
                TrainingEpoch
                  EpochCompleted
                    { ecExperimentHash = "sha256:mnist"
                    , ecEpoch = 4
                    , ecLoss = 0.125
                    , ecValidationLoss = 0.25
                    , ecTimestampNs = 123456789
                    }
              checkpoint =
                TrainingCheckpoint
                  CheckpointDone
                    { cdExperimentHash = "sha256:mnist"
                    , cdManifestSha = "sha256:manifest"
                    , cdStep = 4096
                    , cdPointerKey = "checkpoints/mnist/latest"
                    , cdEpoch = 4
                    , cdTrialSha = Just "sha256:trial"
                    , cdRunUuid = "run-0001"
                    , cdMetricsAtStep = [("loss", 0.125), ("accuracy", 0.875)]
                    , cdCompletedTraining =
                        Just
                          ( completedTrainingFixture
                              TrainingBudget.SupervisedEpochBudget
                              "sha256:mnist"
                              4096
                              [("loss", 0.125), ("accuracy", 0.875)]
                          )
                    }
              failure =
                TrainingFailure
                  TrainingFailed
                    { tfExperimentHash = "sha256:mnist"
                    , tfErrorCode = "DatasetUnavailable"
                    , tfErrorText = "missing fixture"
                    , tfTimestampNs = 987654321
                    }
          decodeTrainingEventProto (encodeTrainingEventProto epoch) @?= Right epoch
          decodeTrainingEventProto (encodeTrainingEventProto checkpoint) @?= Right checkpoint
          decodeTrainingEventProto (encodeTrainingEventProto failure) @?= Right failure
      , testCase "SL classifier converges on a separable synthetic task (Sprint 13.4 network seam)" $ do
          -- Sprint 13.4 — drive the real differentiable softmax-cross-entropy
          -- classifier (`JitML.SL.Classifier`, built on the MLP seam) over a
          -- deterministic, linearly-separable 3-class dataset and assert it
          -- learns: train accuracy crosses a high threshold and the
          -- cross-entropy loss drops well below its log(3) random baseline.
          let dataset = syntheticDataset
              config =
                defaultClassifierConfig
                  { clfSeed = 7
                  , clfInputs = 4
                  , clfHidden = 16
                  , clfClasses = 3
                  , clfEpochs = 60
                  , clfLearningRate = 5.0e-3
                  }
              trained = trainClassifier config dataset
              acc = accuracy trained dataset
              loss = crossEntropyLoss trained dataset
          assertBool
            ("expected train accuracy >= 0.95, got " <> show acc)
            (acc >= 0.95)
          assertBool
            ("expected cross-entropy loss < 0.5 (random ~1.10), got " <> show loss)
            (loss < 0.5)
      , testCase "SL classifier converges through the substrate JIT device (Sprint 8.10 --linux-cpu)" $ do
          -- Sprint 8.10 device-backed convergence. Routes the softmax
          -- cross-entropy classifier through the resolved substrate's
          -- JIT-compiled MLP device (oneDNN under `--linux-cpu`, Metal under
          -- `--apple-silicon`) and asserts it learns the separable synthetic
          -- task. On a host without the substrate toolchain the device probe
          -- returns Left and the case skips with a passing message, matching
          -- the live-test skip convention. No committed fixtures.
          env <- buildEnv defaultGlobalFlags
          let device = mlpDeviceForSubstrate LinuxCPU env
          probe <- probeMlpDevice device
          case probe of
            Left _ ->
              assertBool "linux-cpu JIT device unavailable; device convergence skipped" True
            Right () -> do
              let config =
                    defaultClassifierConfig
                      { clfSeed = 7
                      , clfInputs = 4
                      , clfHidden = 16
                      , clfClasses = 3
                      , clfEpochs = 400
                      , clfLearningRate = 1.0e-2
                      }
              result <- trainClassifierWithDevice device config syntheticDataset
              case result of
                Left err -> assertFailure ("device training failed: " <> Text.unpack err)
                Right (_, acc) ->
                  assertBool
                    ("expected device train accuracy >= 0.9, got " <> show acc)
                    (acc >= 0.9)
      , testCase "real SL metrics: validation-driven selection, real CE loss, throughput (Sprint 8.13)" $ do
          -- Sprint 8.13 — exercise the real-metric SL path through whichever
          -- substrate JIT device is real on this host: Apple Metal on the Mac
          -- host (`--apple-silicon`), oneDNN in the linux-cpu container
          -- (`--linux-cpu`). Asserts the published loss is a real mean softmax
          -- cross-entropy that dropped below its log(numClasses) random baseline
          -- (never `1 − accuracy`); the held-out validation loss is a real,
          -- finite measurement on a partition the trainer never updated on; the
          -- throughput metric is the deterministic train-examples × epochs count
          -- (non-wall-clock, inside the determinism contract); and a fresh
          -- device cross-entropy on the validation-selected model reproduces the
          -- published train loss. Skips with a passing message on a host with no
          -- substrate device. No committed fixtures.
          env <- buildEnv defaultGlobalFlags
          let firstDevice [] = pure Nothing
              firstDevice (substrate : rest) = do
                let candidate = mlpDeviceForSubstrate substrate env
                probe <- probeMlpDevice candidate
                case probe of
                  Right () -> pure (Just candidate)
                  Left _ -> firstDevice rest
          deviceMaybe <- firstDevice [AppleSilicon, LinuxCPU]
          case deviceMaybe of
            Nothing ->
              assertBool "no substrate JIT device available; real-metric SL path skipped" True
            Just device -> do
              let config =
                    defaultClassifierConfig
                      { clfSeed = 11
                      , clfInputs = 4
                      , clfHidden = 16
                      , clfClasses = 3
                      , clfEpochs = 40
                      , clfLearningRate = 1.0e-2
                      }
                  denseProblem =
                    case filter ((== "Dense") . SL.problemModel) canonicalProblems of
                      (p : _) -> p
                      [] -> SL.CanonicalProblem "mnist-shallow-mlp" "MNIST" "Dense" 1001
                  spec = Architecture.architectureSpecForProblem config denseProblem
                  examples = syntheticDataset
                  valCount = max 1 (length examples `div` 6)
                  trainCount = length examples - valCount
                  trainSet = take trainCount examples
                  validationSet = drop trainCount examples
              result <-
                Architecture.trainArchitectureWithDeviceSelected device spec config trainSet validationSet
              case result of
                Left err -> assertFailure ("real-metric SL training failed: " <> Text.unpack err)
                Right (trained, metrics) -> do
                  assertBool
                    ( "expected a real train cross-entropy in (0, log 3 ~ 1.0986), got "
                        <> show (Architecture.slmTrainLoss metrics)
                    )
                    (Architecture.slmTrainLoss metrics > 0 && Architecture.slmTrainLoss metrics < log 3)
                  assertBool
                    ( "expected a finite held-out validation loss >= 0, got "
                        <> show (Architecture.slmValidationLoss metrics)
                    )
                    ( Architecture.slmValidationLoss metrics >= 0
                        && not (isNaN (Architecture.slmValidationLoss metrics))
                        && not (isInfinite (Architecture.slmValidationLoss metrics))
                    )
                  Architecture.slmExamplesProcessed metrics @?= trainCount * clfEpochs config
                  reMeasured <- Architecture.crossEntropyArchitectureWithDevice device trained trainSet
                  case reMeasured of
                    Left err -> assertFailure ("re-measured device cross-entropy failed: " <> Text.unpack err)
                    Right ce ->
                      assertBool
                        ( "expected re-measured CE to reproduce the published train loss, got "
                            <> show ce
                            <> " vs "
                            <> show (Architecture.slmTrainLoss metrics)
                        )
                        (abs (ce - Architecture.slmTrainLoss metrics) < 1.0e-9)
      , testCase "SL regression converges through the substrate JIT device (Sprint 8.12 --linux-cpu)" $ do
          env <- buildEnv defaultGlobalFlags
          let device = mlpDeviceForSubstrate LinuxCPU env
          probe <- probeMlpDevice device
          case probe of
            Left _ ->
              assertBool "linux-cpu JIT device unavailable; regression convergence skipped" True
            Right () -> do
              let config =
                    Regression.defaultRegressionConfig
                      { Regression.regSeed = 23
                      , Regression.regInputs = 2
                      , Regression.regHidden = 12
                      , Regression.regEpochs = 300
                      , Regression.regLearningRate = 5.0e-2
                      }
              result <- Regression.trainRegressorWithDevice device config regressionSyntheticDataset
              case result of
                Left err -> assertFailure ("device regression training failed: " <> Text.unpack err)
                Right (_, mse) ->
                  assertBool
                    ("expected device regression MSE < 0.02, got " <> show mse)
                    (mse < 0.02)
      , testCase
          "all canonical SL architectures execute a substrate-backed train step (Sprint 8.12 --linux-cpu)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let device = mlpDeviceForSubstrate LinuxCPU env
            probe <- probeMlpDevice device
            case probe of
              Left _ ->
                assertBool "linux-cpu JIT device unavailable; architecture train step skipped" True
              Right () -> do
                let config =
                      defaultClassifierConfig
                        { clfSeed = 17
                        , clfInputs = 16
                        , clfHidden = 8
                        , clfClasses = 3
                        , clfEpochs = 1
                        , clfLearningRate = 5.0e-3
                        }
                forM_ canonicalProblems $ \problem -> do
                  let spec = Architecture.architectureSpecForProblem config problem
                  result <-
                    Architecture.trainArchitectureWithDevice
                      device
                      spec
                      config
                      architectureSyntheticDataset
                  case result of
                    Left err ->
                      assertFailure
                        ( "architecture train failed for "
                            <> Text.unpack (problemName problem)
                            <> ": "
                            <> Text.unpack err
                        )
                    Right (_, acc) ->
                      assertBool
                        ( "expected finite accuracy for "
                            <> Text.unpack (problemName problem)
                            <> ", got "
                            <> show acc
                        )
                        (acc >= 0.0 && acc <= 1.0 && not (isNaN acc))
      , testCase "SL classifier training is run-to-run deterministic (Sprint 13.4)" $ do
          let config = defaultClassifierConfig {clfInputs = 4, clfHidden = 16, clfClasses = 3, clfEpochs = 20}
              dataset = syntheticDataset
              a = trainClassifier config dataset
              b = trainClassifier config dataset
          fmap (classify a . exampleFeatures) dataset
            @?= fmap (classify b . exampleFeatures) dataset
      , testCase "IDX image + label parsers round-trip the canonical MNIST format (Sprint 13.4)" $ do
          -- Build a tiny synthetic IDX3 (2 images, 2x2) + IDX1 (2 labels)
          -- payload in the canonical big-endian header format and assert the
          -- parsers recover the pixel/label content the live MNIST upload
          -- (Sprint 13.4 upload half) stages in MinIO.
          let imageBytes =
                ByteString.pack $
                  be32Bytes 0x0803 -- magic IDX3
                    <> be32Bytes 2 -- count
                    <> be32Bytes 2 -- rows
                    <> be32Bytes 2 -- cols
                    <> [0, 255, 128, 64, 10, 20, 30, 40] -- two 2x2 images
              labelBytes =
                ByteString.pack $
                  be32Bytes 0x0801 -- magic IDX1
                    <> be32Bytes 2 -- count
                    <> [7, 3] -- two labels
          case (parseIdxImages imageBytes, parseIdxLabels labelBytes) of
            (Right (pixelsPer, images), Right labels) -> do
              pixelsPer @?= 4
              length images @?= 2
              labels @?= [7, 3]
              -- first pixel of image 0 is 0/255 = 0.0; second is 255/255 = 1.0
              case images of
                firstImage : _ ->
                  VU.toList firstImage @?= [0.0, 1.0, 128.0 / 255.0, 64.0 / 255.0]
                [] -> assertFailure "expected parsed IDX image"
              let examples = zipImagesLabels images labels
              fmap exampleLabel examples @?= [7, 3]
            (imgErr, lblErr) ->
              assertFailure ("IDX parse failed: " <> show imgErr <> " / " <> show lblErr)
      , testCase "gunzip transparently decompresses the canonical compressed blob (Sprint 13.4)" $ do
          -- The canonical MNIST blobs are distributed gzip-compressed; the
          -- worker's fetch path calls `maybeGunzip` before IDX parsing. Assert
          -- a gzip-magic payload round-trips and a raw payload is unchanged.
          let raw = ByteString.pack [0x00, 0x01, 0x02, 0x03, 0x04]
              gz = LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict raw))
          Dataset.maybeGunzip gz @?= raw
          Dataset.maybeGunzip raw @?= raw
      , testCase "classifier trains over (gzipped) IDX bytes through the bounded entry (Sprint 13.4)" $ do
          -- End-to-end exercise of the live worker path: build a synthetic but
          -- learnable IDX3 image + IDX1 label payload, gzip it (as the canonical
          -- MNIST upload stages), gunzip + IDX-parse + train through
          -- `trainClassifierFromIdxBounded`, and assert the bounded subset is
          -- learned. No committed fixtures (numerical-fixture prohibition).
          let imageBytes =
                ByteString.pack $
                  be32Bytes 0x0803 -- magic IDX3
                    <> be32Bytes 6 -- count
                    <> be32Bytes 1 -- rows
                    <> be32Bytes 2 -- cols
                    -- three class-0 (high first pixel) + three class-1 (high second pixel)
                    <> [250, 5, 240, 10, 255, 0, 5, 250, 10, 240, 0, 255]
              labelBytes =
                ByteString.pack $
                  be32Bytes 0x0801 -- magic IDX1
                    <> be32Bytes 6 -- count
                    <> [0, 0, 0, 1, 1, 1]
              gzImages = LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict imageBytes))
              gzLabels = LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict labelBytes))
              config =
                defaultClassifierConfig
                  { clfSeed = 11
                  , clfInputs = 2
                  , clfHidden = 8
                  , clfClasses = 2
                  , clfEpochs = 80
                  , clfLearningRate = 5.0e-3
                  }
          case trainClassifierFromIdxBounded
            config
            (Just 6)
            (Dataset.maybeGunzip gzImages)
            (Dataset.maybeGunzip gzLabels) of
            Left err -> assertFailure ("bounded IDX training failed: " <> err)
            Right (_, acc) ->
              assertBool
                ("expected bounded-subset train accuracy >= 0.83, got " <> show acc)
                (acc >= 0.83)
      , testCase "SL convergence threshold table covers the classification problems (Sprint 13.4)" $ do
          -- Every MNIST / Fashion-MNIST / CIFAR / Tiny-ImageNet classification
          -- problem has a literature-anchored threshold; the regression
          -- problem (california-housing) is intentionally omitted.
          assertBool
            "mnist-shallow-mlp has a threshold"
            (Data.Maybe.isJust (slCohortThreshold "mnist-shallow-mlp"))
          assertBool
            "fashion-mnist-mlp has a threshold"
            (Data.Maybe.isJust (slCohortThreshold "fashion-mnist-mlp"))
          assertBool
            "california-housing (regression) is omitted"
            (Data.Maybe.isNothing (slCohortThreshold "california-housing-mlp"))
          assertBool
            "every threshold has positive slack and a target in (0, 1]"
            ( all
                (\(_, t) -> slSlack t > 0 && slLiteratureTarget t > 0 && slLiteratureTarget t <= 1.0)
                slCohortThresholds
            )
      , testCase "passesSlConvergence accepts target and rejects below the slack band (Sprint 13.4)" $ do
          let threshold = SlConvergenceThreshold 0.97 0.07
          assertBool "accepts the literature target" (passesSlConvergence threshold 0.97)
          assertBool "accepts target - slack (lower bar)" (passesSlConvergence threshold 0.90)
          assertBool
            "rejects a measured median below the slack band"
            (not (passesSlConvergence threshold 0.80))
      , testCase "live MNIST SL training clears the convergence threshold (Sprint 13.4 Live)" $ do
          -- Sprint 8.12 live convergence assertion. With a live cluster
          -- publication present, fetch the real MNIST bytes from MinIO,
          -- gunzip + IDX-parse + train the canonical row through the
          -- substrate-backed Architecture runtime over a bounded budget, and
          -- assert the measured test accuracy clears the in-code literature
          -- threshold − slack. Offline (no publication) the case skips with a
          -- passing message, matching the live-test convention in the
          -- integration / playwright stanzas. No committed fixtures — the data
          -- is the canonical MinIO-staged MNIST and the bar is the in-code
          -- threshold.
          publication <- readExistingLivePublication "."
          case publication of
            Nothing ->
              assertBool
                "no live cluster publication; live SL convergence assertion skipped"
                True
            Just pub ->
              case ( Data.Maybe.listToMaybe canonicalProblems
                   , Data.Maybe.listToMaybe canonicalProblems >>= Dataset.datasetForProblem
                   , slCohortThreshold "mnist-shallow-mlp"
                   ) of
                (Just problem, Just trainRef, Just threshold) -> do
                  let settings = minioSettingsForLocalEdge (publicationEdgePort pub)
                      testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
                      run = runMinIOSubprocess settings
                  trainImg <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
                  trainLbl <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
                  testImg <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.ImagesArtifact)
                  testLbl <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.LabelsArtifact)
                  case (trainImg, trainLbl, testImg, testLbl) of
                    (Right ti, Right tl, Right vi, Right vl) -> do
                      env <- buildEnv defaultGlobalFlags
                      -- Sprint 16.11 — run the live MNIST convergence on the
                      -- publication's substrate device, not a hardcoded
                      -- `LinuxCPU` (oneDNN) device. On the Mac host the linux-cpu
                      -- oneDNN kernel cannot link (`library 'dnnl' not found`), so
                      -- the apple-silicon lane must train through the Metal device
                      -- the cluster actually runs; on the linux-cpu lane this
                      -- resolves to the same oneDNN device as before.
                      let device = mlpDeviceForSubstrate (publicationSubstrate pub) env
                          config =
                            defaultClassifierConfig
                              { clfEpochs = 60
                              , clfLearningRate = 1.0e-2
                              }
                      case decodeBoundedDataset
                        config
                        (Just 10000)
                        (Dataset.maybeGunzip ti)
                        (Dataset.maybeGunzip tl) of
                        Left err -> assertFailure ("live MNIST training failed: " <> err)
                        Right (configForData, trainSet) -> do
                          let spec = Architecture.architectureSpecForProblem configForData problem
                          trainedE <- Architecture.trainArchitectureWithDevice device spec configForData trainSet
                          case trainedE of
                            Left err ->
                              assertFailure ("live MNIST device architecture training failed: " <> Text.unpack err)
                            Right (trained, _trainAcc) -> do
                              testAccE <-
                                case ( parseIdxImages (Dataset.maybeGunzip vi)
                                     , parseIdxLabels (Dataset.maybeGunzip vl)
                                     ) of
                                  (Right (_, images), Right labels) ->
                                    Architecture.accuracyArchitectureWithDevice
                                      device
                                      trained
                                      (take 5000 (zipImagesLabels images labels))
                                  _ -> pure (Right 0.0)
                              case testAccE of
                                Left err ->
                                  assertFailure ("live MNIST device evaluation failed: " <> Text.unpack err)
                                Right testAcc ->
                                  assertBool
                                    ( "live MNIST test_acc "
                                        <> show testAcc
                                        <> " must clear threshold − slack = "
                                        <> show (slLiteratureTarget threshold - slSlack threshold)
                                    )
                                    (passesSlConvergence threshold testAcc)
                    _ ->
                      -- A stale publication can survive `jitml cluster down`;
                      -- when MinIO is unreachable / the bytes aren't staged the
                      -- fetch returns Left, so the live assertion skips rather
                      -- than failing offline.
                      assertBool
                        "live MNIST bytes unavailable (cluster down or not staged); skipped"
                        True
                _ -> assertFailure "missing MNIST dataset ref or convergence threshold"
      , testCase
          "live all canonical SL rows materialize staged bytes and train through the substrate runtime (Sprint 8.12 Live)"
          $ do
            publication <- readExistingLivePublication "."
            case publication of
              Nothing ->
                assertBool
                  "no live cluster publication; live all-row SL matrix skipped"
                  True
              Just pub -> do
                env <- buildEnv defaultGlobalFlags
                let device = mlpDeviceForSubstrate LinuxCPU env
                probe <- probeMlpDevice device
                case probe of
                  Left _ ->
                    assertBool "linux-cpu JIT device unavailable; live all-row matrix skipped" True
                  Right () -> do
                    let settings = minioSettingsForLocalEdge (publicationEdgePort pub)
                        run = runMinIOSubprocess settings
                        trainProblem problem =
                          case Dataset.datasetForProblem problem of
                            Nothing ->
                              pure
                                ( Left
                                    ( "missing dataset ref for "
                                        <> Text.unpack (problemName problem)
                                    )
                                )
                            Just trainRef
                              | SL.problemDataset problem == "California Housing" ->
                                  trainLiveCalifornia run device problem trainRef
                              | SL.problemDataset problem == "MNIST"
                                  || SL.problemDataset problem == "Fashion-MNIST" ->
                                  trainLiveIdx run device problem trainRef
                              | SL.problemDataset problem == "CIFAR-10" ->
                                  trainLiveArchiveClassifier
                                    run
                                    device
                                    problem
                                    trainRef
                                    decodeCifar10ArchiveBoundedDataset
                              | SL.problemDataset problem == "CIFAR-100" ->
                                  trainLiveArchiveClassifier
                                    run
                                    device
                                    problem
                                    trainRef
                                    decodeCifar100ArchiveBoundedDataset
                              | SL.problemDataset problem == "Tiny ImageNet" ->
                                  trainLiveArchiveClassifier
                                    run
                                    device
                                    problem
                                    trainRef
                                    TinyImageNet.decodeTinyImageNetArchiveBoundedClassificationDataset
                              | otherwise ->
                                  pure
                                    ( Left
                                        ( "unhandled dataset for "
                                            <> Text.unpack (problemName problem)
                                        )
                                    )
                    results <- traverse trainProblem canonicalProblems
                    case lefts results of
                      [] -> pure ()
                      errs -> assertFailure (unlines errs)
      ]

trainLiveIdx
  :: (MinIOSubprocess (Either ServiceError ByteString) -> IO (Either ServiceError ByteString))
  -> MlpDevice
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> IO (Either String ())
trainLiveIdx run device problem trainRef = do
  let (trainLimit, testLimit, epochs, minimumTrainAccuracy) = liveClassifierBudget problem
      testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
      config = defaultClassifierConfig {clfEpochs = epochs}
  trainImg <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
  trainLbl <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
  testImg <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.ImagesArtifact)
  testLbl <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.LabelsArtifact)
  case (trainImg, trainLbl, testImg, testLbl) of
    (Right ti, Right tl, Right vi, Right vl) ->
      case ( decodeBoundedDataset
               config
               (Just trainLimit)
               (Dataset.maybeGunzip ti)
               (Dataset.maybeGunzip tl)
           , decodeBoundedDataset
               config
               (Just testLimit)
               (Dataset.maybeGunzip vi)
               (Dataset.maybeGunzip vl)
           ) of
        (Right (configForData, trainSet), Right (_, testSet)) ->
          trainLiveClassifierDataset
            device
            problem
            configForData
            minimumTrainAccuracy
            trainSet
            testSet
        (Left err, _) ->
          pure (Left (problemLabel problem <> " IDX train decode failed: " <> err))
        (_, Left err) ->
          pure (Left (problemLabel problem <> " IDX test decode failed: " <> err))
    _ ->
      pure (Left (problemLabel problem <> " staged IDX image/label bytes are missing"))

trainLiveArchiveClassifier
  :: (MinIOSubprocess (Either ServiceError ByteString) -> IO (Either ServiceError ByteString))
  -> MlpDevice
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> ( ClassifierConfig
       -> Dataset.DatasetSplit
       -> Maybe Int
       -> ByteString
       -> Either String (ClassifierConfig, Dataset)
     )
  -> IO (Either String ())
trainLiveArchiveClassifier run device problem trainRef decodeArchive = do
  let (trainLimit, testLimit, epochs, minimumTrainAccuracy) = liveClassifierBudget problem
      config = defaultClassifierConfig {clfEpochs = epochs}
  archiveE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left _ ->
      pure (Left (problemLabel problem <> " staged archive bytes are missing"))
    Right archiveBytes ->
      case ( decodeArchive config Dataset.TrainSplit (Just trainLimit) archiveBytes
           , decodeArchive config Dataset.TestSplit (Just testLimit) archiveBytes
           ) of
        (Right (configForData, trainSet), Right (_, testSet)) ->
          trainLiveClassifierDataset
            device
            problem
            configForData
            minimumTrainAccuracy
            trainSet
            testSet
        (Left err, _) ->
          pure (Left (problemLabel problem <> " archive train decode failed: " <> err))
        (_, Left err) ->
          pure (Left (problemLabel problem <> " archive test decode failed: " <> err))

trainLiveClassifierDataset
  :: MlpDevice
  -> SL.CanonicalProblem
  -> ClassifierConfig
  -> Double
  -> Dataset
  -> Dataset
  -> IO (Either String ())
trainLiveClassifierDataset device problem config minimumTrainAccuracy trainSet testSet = do
  let spec = Architecture.architectureSpecForProblem config problem
  trainedE <- Architecture.trainArchitectureWithDevice device spec config trainSet
  case trainedE of
    Left err ->
      pure (Left (problemLabel problem <> " device training failed: " <> Text.unpack err))
    Right (trained, trainAcc) -> do
      testAccE <- Architecture.accuracyArchitectureWithDevice device trained testSet
      case testAccE of
        Left err ->
          pure (Left (problemLabel problem <> " device evaluation failed: " <> Text.unpack err))
        Right testAcc
          | not (finiteDouble trainAcc) ->
              pure (Left (problemLabel problem <> " train accuracy was not finite: " <> show trainAcc))
          | not (finiteDouble testAcc) ->
              pure (Left (problemLabel problem <> " test accuracy was not finite: " <> show testAcc))
          | trainAcc < minimumTrainAccuracy ->
              pure
                ( Left
                    ( problemLabel problem
                        <> " train accuracy "
                        <> show trainAcc
                        <> " was below live smoke minimum "
                        <> show minimumTrainAccuracy
                    )
                )
          | otherwise -> pure (Right ())

trainLiveCalifornia
  :: (MinIOSubprocess (Either ServiceError ByteString) -> IO (Either ServiceError ByteString))
  -> MlpDevice
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> IO (Either String ())
trainLiveCalifornia run device problem trainRef = do
  archiveE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left _ ->
      pure (Left (problemLabel problem <> " staged archive bytes are missing"))
    Right archiveBytes ->
      case Regression.decodeCaliforniaHousingArchiveBoundedData (Just 512) archiveBytes of
        Left err ->
          pure (Left (problemLabel problem <> " archive decode failed: " <> err))
        Right dataset ->
          case dataset of
            [] -> pure (Left (problemLabel problem <> " archive produced no examples"))
            firstExample : _ -> do
              let normalizedDataset = Regression.standardizeRegressionExamples dataset
                  config =
                    Regression.defaultRegressionConfig
                      { Regression.regInputs = VU.length (Regression.regressionFeatures firstExample)
                      , Regression.regHidden = 24
                      , Regression.regEpochs = 120
                      , Regression.regLearningRate = 5.0e-3
                      }
              trainedE <- Regression.trainRegressorWithDevice device config normalizedDataset
              case trainedE of
                Left err ->
                  pure (Left (problemLabel problem <> " regression training failed: " <> Text.unpack err))
                Right (_, mse)
                  | not (finiteDouble mse) ->
                      pure (Left (problemLabel problem <> " regression MSE was not finite: " <> show mse))
                  | mse >= 5.0 ->
                      pure (Left (problemLabel problem <> " regression MSE too high: " <> show mse))
                  | otherwise -> pure (Right ())

liveClassifierBudget :: SL.CanonicalProblem -> (Int, Int, Int, Double)
liveClassifierBudget problem =
  case SL.problemDataset problem of
    "MNIST" -> (512, 256, 2, 0.0)
    "Fashion-MNIST" -> (512, 256, 2, 0.0)
    "CIFAR-10" -> (64, 64, 1, 0.0)
    "CIFAR-100" -> (64, 64, 1, 0.0)
    "Tiny ImageNet" -> (16, 16, 1, 0.0)
    _ -> (64, 64, 1, 0.0)

problemLabel :: SL.CanonicalProblem -> String
problemLabel problem =
  Text.unpack (problemName problem)

finiteDouble :: Double -> Bool
finiteDouble value =
  not (isNaN value) && not (isInfinite value)

-- | Deterministic, linearly-separable 3-class dataset: each class is a
-- tight cluster around a distinct corner of the 4-D unit cube. Used by
-- the Sprint 13.4 SL convergence assertion (no committed fixtures — the
-- data is generated in-code per the numerical-fixture prohibition).
syntheticDataset :: [LabeledExample]
syntheticDataset =
  [ LabeledExample (VU.fromList (classCentre c i)) c
  | c <- [0, 1, 2]
  , i <- [0 .. 19 :: Int]
  ]
 where
  classCentre c i =
    let jitter k = fromIntegral ((c * 31 + i * 7 + k * 13) `mod` 5) / 100.0
        base = case c of
          0 -> [1.0, 0.0, 0.0, 0.0]
          1 -> [0.0, 1.0, 0.0, 0.0]
          _ -> [0.0, 0.0, 1.0, 1.0]
     in zipWith (\b k -> b + jitter k) base [0 ..]

-- | Small image-shaped classification dataset for the Sprint 8.12
-- architecture runtime. The 16 features form a 4×4 single-channel image so
-- patch-convolution and ViT paths produce multiple tokens, while the first
-- three high-signal positions make the task separable for a one-epoch
-- substrate smoke train.
architectureSyntheticDataset :: [LabeledExample]
architectureSyntheticDataset =
  [ LabeledExample (VU.fromList (features c i)) c
  | c <- [0, 1, 2]
  , i <- [0 .. 5 :: Int]
  ]
 where
  features c i =
    [ signal j + jitter j
    | j <- [0 .. 15]
    ]
   where
    signal j
      | j == c = 1.0
      | j == c + 4 = 0.75
      | j == c + 8 = 0.5
      | otherwise = 0.0
    jitter j = fromIntegral ((c * 19 + i * 5 + j * 3) `mod` 7) / 200.0

regressionSyntheticDataset :: [Regression.RegressionExample]
regressionSyntheticDataset =
  [ Regression.RegressionExample
      { Regression.regressionFeatures = VU.fromList [x, y]
      , Regression.regressionTarget = 0.2 + 0.45 * x + 0.3 * y
      }
  | xi <- [0 .. 4 :: Int]
  , let x = fromIntegral xi / 4.0
  , yi <- [0 .. 4 :: Int]
  , let y = fromIntegral yi / 4.0
  ]

-- | Big-endian 4-byte encoding for the synthetic IDX header test.
be32Bytes :: Int -> [Word8]
be32Bytes n =
  [ fromIntegral ((n `shiftR` 24) .&. 0xff)
  , fromIntegral ((n `shiftR` 16) .&. 0xff)
  , fromIntegral ((n `shiftR` 8) .&. 0xff)
  , fromIntegral (n .&. 0xff)
  ]

cifar10Record :: Word8 -> [Word8] -> [Word8]
cifar10Record label patternBytes =
  label : take 3072 (cycle patternBytes)

cifar100Record :: Word8 -> Word8 -> [Word8] -> [Word8]
cifar100Record coarseLabel fineLabel patternBytes =
  coarseLabel : fineLabel : take 3072 (cycle patternBytes)

tarArchive :: [(String, ByteString.ByteString)] -> ByteString.ByteString
tarArchive entries =
  ByteString.concat (map tarEntry entries) <> ByteString.replicate 1024 0

tarEntry :: (String, ByteString.ByteString) -> ByteString.ByteString
tarEntry (name, payload) =
  tarHeader name payload <> payload <> ByteString.replicate padding 0
 where
  padding = (512 - ByteString.length payload `mod` 512) `mod` 512

tarHeader :: String -> ByteString.ByteString -> ByteString.ByteString
tarHeader name payload =
  ByteString.pack [headerByte i | i <- [0 .. 511]]
 where
  nameBytes = ByteString.Char8.pack name
  sizeBytes =
    ByteString.Char8.pack $
      replicate (11 - length octalSize) '0'
        <> octalSize
        <> "\NUL"
  octalSize = showOct (ByteString.length payload) ""
  headerByte i
    | i < ByteString.length nameBytes = ByteString.index nameBytes i
    | i >= 124 && i < 124 + ByteString.length sizeBytes =
        ByteString.index sizeBytes (i - 124)
    | otherwise = 0

tinyJpeg :: Word8 -> Word8 -> Word8 -> ByteString.ByteString
tinyJpeg r g b =
  LazyByteString.toStrict $
    Picture.encodeJpeg $
      Picture.generateImage
        (\_ _ -> Picture.PixelYCbCr8 r g b)
        1
        1

zipArchive :: [(FilePath, ByteString.ByteString)] -> ByteString.ByteString
zipArchive entries =
  LazyByteString.toStrict (Zip.fromArchive (foldr addEntry Zip.emptyArchive entries))
 where
  addEntry (path, payload) =
    Zip.addEntryToArchive
      (Zip.toEntry path 0 (LazyByteString.fromStrict payload))

-- | The first canonical problem whose dataset does not have a
-- published canonical SHA in 'Dataset.canonicalSha256For'. Such a
-- problem's `datasetFixtureBytes` still hashes to its synthetic
-- `datasetExpectedSha256`, so the filesystem-backed MinIO round-trip
-- test can exercise the full encode/verify path without real bytes.
firstSyntheticProblem :: Maybe SL.CanonicalProblem
firstSyntheticProblem =
  case filter usesSyntheticSha canonicalProblems of
    p : _ -> Just p
    [] -> Nothing
 where
  usesSyntheticSha problem =
    case datasetForProblem problem of
      Just ref ->
        Data.Maybe.isNothing
          ( Dataset.canonicalSha256For
              (Dataset.datasetName ref)
              (Dataset.datasetSplit ref)
          )
      Nothing -> False

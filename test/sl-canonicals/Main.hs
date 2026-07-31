{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Codec.Archive.Zip qualified as Zip
import Codec.Compression.GZip qualified as GZip
import Codec.Picture qualified as Picture
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (runReaderT)
import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (lefts, rights)
import Data.List qualified as List
import Data.Maybe qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64, Word8)
import Numeric (showOct)
import System.Environment (lookupEnv)
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
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Cluster.Publication (publicationEdgePort, publicationSubstrate)
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalLocal qualified as MetalLocal
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env)
import JitML.Inference.Decode qualified as InferenceDecode
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Proto.Training
  ( CheckpointDone (..)
  , EpochCompleted (..)
  , StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , TrainingEvent (..)
  , TrainingFailed (..)
  , completeCheckpointDone
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
  , slBarIsNonVacuous
  , slCohortThreshold
  , slCohortThresholds
  , slEffectiveBar
  , slRandomBaseline
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
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.SL.TinyImageNet qualified as TinyImageNet
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Service.Capabilities (HasMinIO (..))
import JitML.Service.Command qualified as ServiceCommand
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.MinIOSubprocess
  ( MinIOSettings
  , MinIOSubprocess
  , minioSettingsForLocalEdge
  , runMinIOSubprocess
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Test.Report
  ( ReportCardKnobs (..)
  , loadReportCardKnobs
  )
import JitML.Test.RowAssertions qualified as RowAssertions
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
    ( TrainingBudget.completedTraining
        fixturePlanId
        (budgetFixture kind (max 1 observedUnits))
        observedUnits
        (trainingEvidenceFixture experimentHash observedUnits)
        (convergenceObservationsFixture metrics)
        TrainingBudget.TensorBoardRunMetadata
          { TrainingBudget.tbrRunId = experimentHash
          , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
          , TrainingBudget.tbrScalarTags = fmap fst metrics
          }
    )

budgetFixture
  :: TrainingBudget.BudgetKind -> Word64 -> TrainingBudget.TrainingBudget
budgetFixture kind target =
  either
    (error . Text.unpack)
    id
    (TrainingBudget.mkTrainingBudget kind target Nothing)

fixturePlanId :: Plan.PlanId
fixturePlanId =
  either (error . Text.unpack) id (Plan.refinePlanIdText (Text.replicate 64 "a"))

trainingEvidenceFixture :: Text -> Word64 -> ProductEvidence.TrainingEvidence
trainingEvidenceFixture experimentHash observedUnits =
  either
    (error . Text.unpack)
    id
    ( ProductEvidence.mkTrainingEvidence
        ("sl-initial-" <> experimentHash)
        ("sl-final-" <> experimentHash <> "-" <> Text.pack (show observedUnits))
        (max 1 observedUnits)
        ("sl-dataset-" <> experimentHash)
    )

convergenceObservationsFixture :: [(Text, Double)] -> [TrainingBudget.ConvergenceObservation]
convergenceObservationsFixture metrics =
  either
    (error . Text.unpack)
    id
    ( traverse
        ( \metric@(name, value) ->
            ProductConvergence.evaluateConvergence
              (ProductConvergence.mkConvergenceBar name TrainingBudget.MetricMaximise value 0.0)
              (ProductConvergence.MeasuredMetrics [metric])
        )
        metrics
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
      , testCase "canonical epoch permutation is seeded, exact, and sample-preserving (Sprint 10.6)" $ do
          let examples =
                [ LabeledExample (VU.singleton (fromIntegral index)) index
                | index <- [0 .. 15]
                ]
              epochOne = Architecture.canonicalEpochPermutation 1009 1 examples
              epochOneReplay = Architecture.canonicalEpochPermutation 1009 1 examples
              epochTwo = Architecture.canonicalEpochPermutation 1009 2 examples
              labels = fmap exampleLabel
          labels epochOne
            @?= [14, 1, 8, 12, 15, 7, 2, 0, 11, 9, 4, 6, 5, 13, 3, 10]
          labels epochTwo
            @?= [7, 5, 3, 13, 9, 0, 8, 1, 12, 11, 2, 14, 4, 10, 15, 6]
          epochOneReplay @?= epochOne
          assertBool "successive epochs must use distinct orders" (epochTwo /= epochOne)
          List.sortOn exampleLabel epochOne @?= examples
          List.sortOn exampleLabel epochTwo @?= examples
      , testCase "CIFAR ViT served graph retains its exact trained parameter layout (Sprint 10.6)" $ do
          case List.find ((== "cifar10-vit") . problemName) canonicalProblems of
            Nothing -> assertFailure "missing cifar10-vit canonical problem"
            Just problem -> do
              let config =
                    defaultClassifierConfig
                      { clfInputs = 3072
                      , clfClasses = 10
                      , clfSeed = SL.problemSeed problem
                      }
              case Architecture.canonicalClassificationRuntimeContract config problem of
                Left err ->
                  assertFailure
                    ("failed to refine the exact CIFAR ViT runtime: " <> Text.unpack err)
                Right runtime ->
                  do
                    -- Phase 239 retired the V2 token op-program; the trained typed
                    -- 'LayerGraph' is now the sole served supervised representation.
                    -- The canonical runtime contract (task + input/output transforms)
                    -- still refines and round-trips, and the served graph carries the
                    -- exact trained parameter count (computed from the spec, not the
                    -- obsolete 123595 token count).
                    refined <-
                      expectText
                        "refine exact compact CIFAR ViT runtime"
                        (RuntimeArtifact.refineSupervisedRuntime runtime)
                    RuntimeArtifact.supervisedRuntimeToRaw refined @?= runtime
                    let spec = Architecture.architectureSpecForProblem config problem
                        graph = Architecture.archLayerGraph spec
                        graphParameterCount =
                          VU.length (LayerGraph.graphParameterVector graph)
                        metadataParameterCount =
                          Checkpoint.layerGraphMetadataParameterCount
                            (Checkpoint.layerGraphMetadataFromGraph graph)
                    assertBool
                      "cifar10-vit served graph has a positive trained parameter count"
                      (graphParameterCount > 0)
                    graphParameterCount @?= metadataParameterCount
      , testCase "ProductRow architecture features match literal LayerGraph topology (Sprint 24.1)" $ do
          let config =
                defaultClassifierConfig
                  { clfInputs = 16
                  , clfHidden = 8
                  , clfClasses = 3
                  }
              specs = Architecture.allCanonicalArchitectureSpecs config
              supervisedRows =
                [ row
                | row <- ProductMatrix.allProductRows
                , ProductMatrix.family row == ProductMatrix.Supervised
                ]
              specFor row =
                List.find
                  ((== ProductMatrix.rowId row) . problemName . Architecture.archProblem)
                  specs
              rowFailures row =
                case specFor row of
                  Nothing ->
                    [ProductMatrix.rowId row <> " has no canonical ArchitectureSpec"]
                  Just spec ->
                    let claimed = ProductMatrix.rowArchitectureFeatures row
                        expected = Architecture.architectureClaimedFeatures spec
                     in Architecture.validateArchitectureFeatureParity spec claimed
                          <> [ ProductMatrix.rowId row
                                 <> " records "
                                 <> Text.pack (show (fmap Architecture.renderArchitectureFeature claimed))
                                 <> " but architecture declares "
                                 <> Text.pack (show (fmap Architecture.renderArchitectureFeature expected))
                             | claimed /= expected
                             ]
              failures = concatMap rowFailures supervisedRows
          failures @?= []
      , testCase "literal supervised graph topologies carry documented named blocks (Sprint 24.1)" $ do
          let config =
                defaultClassifierConfig
                  { clfInputs = 16
                  , clfHidden = 8
                  , clfClasses = 3
                  }
              specs = Architecture.allCanonicalArchitectureSpecs config
              specNamed name =
                List.find ((== name) . problemName . Architecture.archProblem) specs
              countNodes name predicate =
                case specNamed name of
                  Nothing -> assertFailure ("missing canonical ArchitectureSpec for " <> Text.unpack name)
                  Just spec ->
                    pure
                      ( length
                          [ ()
                          | node <- LayerGraph.layerGraphNodes (Architecture.archLayerGraph spec)
                          , predicate (LayerGraph.layerNodeKind node)
                          ]
                      )
              assertCount name label predicate expected = do
                actual <- countNodes name predicate
                assertBool
                  ( Text.unpack name
                      <> " expected "
                      <> show expected
                      <> " "
                      <> label
                      <> " nodes, got "
                      <> show actual
                  )
                  (actual == expected)
              assertAtLeast name label predicate expected = do
                actual <- countNodes name predicate
                assertBool
                  ( Text.unpack name
                      <> " expected at least "
                      <> show expected
                      <> " "
                      <> label
                      <> " nodes, got "
                      <> show actual
                  )
                  (actual >= expected)
          -- Phases 242–244: the literal correct-operator graphs. mnist-deep-mlp
          -- keeps its two real BatchNorm + two real Dropout nodes; the conv/token
          -- families are the compact real-operator builders (correctOpsConvLeNetGraph
          -- / correctOpsVitGraph / correctOpsResNetGraph), so their per-kind node
          -- counts are the real topology, not the retired dense-lowered depth.
          assertCount "mnist-deep-mlp" "BatchNorm" isBatchNorm 2
          assertCount "mnist-deep-mlp" "Dropout" isDropout 2
          assertAtLeast "mnist-lenet" "Conv2D" isConv2D 2
          assertAtLeast "mnist-lenet" "pooling" isPool 2
          assertCount "fashion-mnist-resnet" "BasicBlock" isBasicBlock 2
          assertAtLeast "fashion-mnist-resnet" "BatchNorm" isBatchNorm 1
          assertAtLeast "fashion-mnist-resnet" "Conv2D" isConv2D 2
          assertAtLeast "fashion-mnist-resnet" "LayerNorm" isLayerNorm 1
          assertAtLeast "fashion-mnist-resnet" "token-mixing MLP" isGeGLU 1
          assertAtLeast "fashion-mnist-resnet" "attention" isAttention 1
          assertCount "cifar10-resnet20" "BasicBlock" isBasicBlock 2
          assertAtLeast "cifar10-resnet20" "Conv2D" isConv2D 2
          assertAtLeast "cifar10-resnet20" "LayerNorm" isLayerNorm 1
          assertAtLeast "cifar10-resnet20" "token-mixing MLP" isGeGLU 1
          assertCount "cifar10-resnet56" "BasicBlock" isBasicBlock 2
          assertAtLeast "cifar10-resnet56" "Conv2D" isConv2D 2
          assertAtLeast "cifar10-resnet56" "LayerNorm" isLayerNorm 1
          assertAtLeast "cifar10-resnet56" "token-mixing MLP" isGeGLU 1
          assertCount "cifar100-wide-resnet" "BasicBlock" isBasicBlock 2
          assertAtLeast "cifar100-wide-resnet" "GroupNorm" isGroupNorm 1
          assertAtLeast "cifar100-wide-resnet" "Conv2D" isConv2D 2
          assertAtLeast "cifar100-wide-resnet" "LayerNorm" isLayerNorm 1
          assertAtLeast "cifar100-wide-resnet" "token-mixing MLP" isGeGLU 1
          assertCount "cifar10-vit" "MultiHeadAttention" isAttention 1
          assertCount "cifar10-vit" "LayerNorm" isLayerNorm 1
          assertCount "cifar10-vit" "GeGLU" isGeGLU 1
          assertCount "tiny-imagenet-resnet50" "BottleneckBlock" isBottleneckBlock 2
          assertAtLeast "tiny-imagenet-resnet50" "BatchNorm" isBatchNorm 1
          assertAtLeast "tiny-imagenet-resnet50" "Conv2D" isConv2D 2
          assertAtLeast "tiny-imagenet-resnet50" "LayerNorm" isLayerNorm 1
          assertAtLeast "tiny-imagenet-resnet50" "token-mixing MLP" isGeGLU 1
          assertAtLeast "tiny-imagenet-resnet50" "attention" isAttention 1
      , testCase "feature parity rejects a simplified graph for a richer row (Sprint 24.1)" $ do
          let config =
                defaultClassifierConfig
                  { clfInputs = 16
                  , clfHidden = 8
                  , clfClasses = 3
                  }
              specs = Architecture.allCanonicalArchitectureSpecs config
              rows = ProductMatrix.allProductRows
              denseSpec =
                List.find ((== "mnist-shallow-mlp") . problemName . Architecture.archProblem) specs
              lenetRow =
                List.find ((== "mnist-lenet") . ProductMatrix.rowId) rows
          case (denseSpec, lenetRow) of
            (Just spec, Just row) -> do
              let failures =
                    Architecture.validateArchitectureFeatureParity
                      spec
                      (ProductMatrix.rowArchitectureFeatures row)
              assertBool
                "Dense-only graph must not satisfy the LeNet Conv2D/pooling feature claim"
                (not (null failures))
            _ -> assertFailure "missing dense spec or LeNet ProductRow"
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
                  cifar10Record
                    3
                    ( cifarPlanarPayload
                        [(0, 1), (1, 4), (31, 7), (32, 10), (1023, 13)]
                        [(0, 2), (1, 5), (31, 8), (32, 11), (1023, 14)]
                        [(0, 3), (1, 6), (31, 9), (32, 12), (1023, 15)]
                    )
                    <> cifar10Record
                      7
                      ( cifarPlanarPayload
                          [(0, 16)]
                          [(0, 17)]
                          [(0, 18)]
                      )
              cifar100Bytes =
                ByteString.pack $
                  cifar100Record
                    2
                    42
                    ( cifarPlanarPayload
                        [(0, 21), (1, 24), (31, 27), (32, 30), (1023, 33)]
                        [(0, 22), (1, 25), (31, 28), (32, 31), (1023, 34)]
                        [(0, 23), (1, 26), (31, 29), (32, 32), (1023, 35)]
                    )
                    <> cifar100Record
                      9
                      17
                      ( cifarPlanarPayload
                          [(0, 36)]
                          [(0, 37)]
                          [(0, 38)]
                      )
              sentinelPixels = [0, 1, 31, 32, 1023]
              decodedSentinels features =
                VU.fromList
                  [ features VU.! (pixel * 3 + channel)
                  | pixel <- sentinelPixels
                  , channel <- [0 .. 2]
                  ]
              scaledSentinels :: [Word8] -> VU.Vector Double
              scaledSentinels values =
                VU.fromList [fromIntegral value / 255.0 | value <- values]
          case parseCifar10BinaryBatch cifar10Bytes of
            Left err -> assertFailure ("CIFAR-10 parse failed: " <> err)
            Right examples -> do
              fmap exampleLabel examples @?= [3, 7]
              case examples of
                first : _ -> do
                  VU.length (exampleFeatures first) @?= 3072
                  decodedSentinels (exampleFeatures first)
                    @?= scaledSentinels [1 .. 15]
                [] -> assertFailure "expected CIFAR-10 examples"
          case parseCifar100BinaryBatch cifar100Bytes of
            Left err -> assertFailure ("CIFAR-100 parse failed: " <> err)
            Right examples -> do
              fmap exampleLabel examples @?= [42, 17]
              case examples of
                first : _ ->
                  decodedSentinels (exampleFeatures first)
                    @?= scaledSentinels [21 .. 35]
                [] -> assertFailure "expected CIFAR-100 examples"
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
      , testCase "verified artifact reads reject corrupt canonical bytes before decode (Sprint 22.3)" $
          withSystemTempDirectory "jitml-sl-corrupt-dataset" $ \dir -> do
            let ref = Dataset.DatasetRef "MNIST" Dataset.TrainSplit 0 "ignored"
                payload = ByteString.Char8.pack "not the canonical MNIST train image gzip"
            result <-
              runFilesystemMinIO dir $ do
                _ <- putBlobBytesIfAbsent (Dataset.datasetArtifactObjectRef ref Dataset.ImagesArtifact) payload
                Dataset.fetchVerifiedDatasetArtifactBytes ref Dataset.ImagesArtifact
            case result of
              Left (SEConflict message) ->
                assertBool
                  "corrupt canonical bytes fail before decode with a SHA diagnostic"
                  ("dataset SHA mismatch for MNIST/train/images" `Text.isInfixOf` message)
              Left err ->
                assertFailure ("expected SHA conflict, got " <> show err)
              Right _ ->
                assertFailure "corrupt canonical bytes unexpectedly verified"
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
          let rawStart =
                StartTraining
                  { stExperimentHash = "sha256:mnist"
                  , stDhallObjectKey = "experiments/mnist.dhall"
                  , stSubstrate = LinuxCPU
                  , stSeed = 42
                  , stEpochs = 5
                  , stBatchSize = 64
                  , stPlanId = ""
                  , stResolvedPlan = ""
                  , stTrainingExamples = 4096
                  , stEvaluationExamples = 1024
                  }
              start =
                TrainingStart
                  ( either
                      (error . Text.unpack)
                      fst
                      (PlanCommand.prepareStartTraining rawStart)
                  )
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
              checkpointCandidate =
                CheckpointDone
                  { cdExperimentHash = "sha256:mnist"
                  , cdManifestSha = "sha256:manifest"
                  , cdStep = 4096
                  , cdPointerKey = "checkpoints/mnist/latest"
                  , cdEpoch = 4
                  , cdTrialSha = Just "sha256:trial"
                  , cdRunUuid = "run-0001"
                  , cdMetricsAtStep = [("loss", 0.125), ("accuracy", 0.875)]
                  }
              completedTraining =
                completedTrainingFixture
                  TrainingBudget.SupervisedEpochBudget
                  "sha256:mnist"
                  4096
                  [("loss", 0.125), ("accuracy", 0.875)]
              checkpoint = TrainingCheckpoint checkpointCandidate
              completedCheckpoint =
                TrainingCompletedCheckpoint
                  ( either
                      (error . Text.unpack)
                      id
                      (completeCheckpointDone checkpointCandidate completedTraining)
                  )
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
          decodeTrainingEventProto (encodeTrainingEventProto completedCheckpoint)
            @?= Right completedCheckpoint
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
          -- cross-entropy classifier through the selected substrate's
          -- JIT-compiled MLP device and asserts it learns the separable
          -- synthetic task. Missing substrate runtime is a hard test failure:
          -- the suite must not pass by silently falling back or skipping.
          env <- buildEnv defaultGlobalFlags
          substrate <- selectedTestSubstrate
          let device = mlpDeviceForSubstrate substrate env
          requireMlpDevice substrate device
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
          -- published train loss. Missing substrate runtime fails closed.
          env <- buildEnv defaultGlobalFlags
          substrate <- selectedTestSubstrate
          let device = mlpDeviceForSubstrate substrate env
          requireMlpDevice substrate device
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
              Architecture.slmOptimizerUpdatesExecuted metrics
                @?= fromIntegral
                  ( clfEpochs config
                      * ( (trainCount + clfBatchSize config - 1)
                            `div` clfBatchSize config
                        )
                  )
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
      , testCase
          "canonical permuted device training replays weights, metrics, and update count (Sprint 10.6)"
          $ do
            env <- buildEnv defaultGlobalFlags
            substrate <- selectedTestSubstrate
            let device = mlpDeviceForSubstrate substrate env
            requireMlpDevice substrate device
            let denseProblem =
                  case filter ((== "Dense") . SL.problemModel) canonicalProblems of
                    (problem : _) -> problem
                    [] -> SL.CanonicalProblem "mnist-shallow-mlp" "MNIST" "Dense" 1001
                config =
                  defaultClassifierConfig
                    { clfSeed = SL.problemSeed denseProblem
                    , clfInputs = 4
                    , clfHidden = 8
                    , clfClasses = 3
                    , clfEpochs = 3
                    , clfBatchSize = 7
                    , clfLearningRate = 1.0e-2
                    }
                spec = Architecture.architectureSpecForProblem config denseProblem
                trainSet = take 50 syntheticDataset
                validationSet = drop 50 syntheticDataset
                expectedUpdates =
                  fromIntegral
                    ( clfEpochs config
                        * ( (length trainSet + clfBatchSize config - 1)
                              `div` clfBatchSize config
                          )
                    )
            firstE <-
              Architecture.trainCanonicalArchitectureWithDeviceSelected
                device
                spec
                config
                trainSet
                validationSet
            replayE <-
              Architecture.trainCanonicalArchitectureWithDeviceSelected
                device
                spec
                config
                trainSet
                validationSet
            (firstTrained, firstMetrics) <- expectText "first canonical permuted training" firstE
            (replayTrained, replayMetrics) <- expectText "replayed canonical permuted training" replayE
            Architecture.trainedArchitectureWeights replayTrained
              @?= Architecture.trainedArchitectureWeights firstTrained
            replayMetrics @?= firstMetrics
            Architecture.slmExamplesProcessed firstMetrics
              @?= length trainSet
              * clfEpochs config
            Architecture.slmOptimizerUpdatesExecuted firstMetrics @?= expectedUpdates
            let fittedTransform =
                  RuntimeArtifact.RawStandardizeInput
                    [0.1, 0.2, 0.3, 0.4]
                    [0.5, 0.6, 0.7, 0.8]
            bound <-
              expectText
                "bind exact trained classification transform"
                ( Architecture.bindTrainedArchitectureInputTransform
                    fittedTransform
                    firstTrained
                )
            -- Phase 239 retired 'projectTrainedArchitectureRuntime'; the bound
            -- input transform now lives directly on the 'TrainedArchitecture', so
            -- read it back to prove the fitted transform round-trips through binding.
            Architecture.trainedArchInputTransform bound @?= fittedTransform
            assertBool
              "trained classification transform binding must reject width drift"
              ( case Architecture.bindTrainedArchitectureInputTransform
                  (RuntimeArtifact.RawStandardizeInput [0.1] [0.5])
                  firstTrained of
                  Left _ -> True
                  Right _ -> False
              )
      , testCase
          "supervised row evidence assertions cover split, throughput, hashes, and convergence (Sprint 24.2)"
          $ do
            env <- buildEnv defaultGlobalFlags
            substrate <- selectedTestSubstrate
            let device = mlpDeviceForSubstrate substrate env
            requireMlpDevice substrate device
            let config =
                  defaultClassifierConfig
                    { clfSeed = 29
                    , clfInputs = 16
                    , clfHidden = 16
                    , clfClasses = 3
                    , clfEpochs = 400
                    , clfLearningRate = 1.0e-2
                    }
                denseProblem =
                  case filter ((== "Dense") . SL.problemModel) canonicalProblems of
                    (p : _) -> p
                    [] -> SL.CanonicalProblem "mnist-shallow-mlp" "MNIST" "Dense" 1001
                spec = Architecture.architectureSpecForProblem config denseProblem
                (trainSet, validationSet, testSet) = architectureEvidenceSplits
            threshold <-
              case slCohortThreshold (problemName denseProblem) of
                Just value -> pure value
                Nothing -> assertFailure "missing Dense SL convergence threshold"
            result <-
              Architecture.trainArchitectureWithDeviceSelected device spec config trainSet validationSet
            case result of
              Left err -> assertFailure ("evidence SL training failed: " <> Text.unpack err)
              Right (trained, metrics) -> do
                testAccE <- Architecture.accuracyArchitectureWithDevice device trained testSet
                case testAccE of
                  Left err -> assertFailure ("evidence test accuracy failed: " <> Text.unpack err)
                  Right testAcc -> do
                    let finalWeights = Architecture.trainedArchitectureWeights trained
                        evidence =
                          RowAssertions.SupervisedRowEvidence
                            { RowAssertions.sreRowId = problemName denseProblem
                            , RowAssertions.sreInitialWeightHash =
                                weightDigest
                                  ( VU.toList
                                      (LayerGraph.graphParameterVector (Architecture.archLayerGraph spec))
                                  )
                            , RowAssertions.sreFinalWeightHash = weightDigest finalWeights
                            , RowAssertions.sreUpdateCount =
                                fromIntegral (Architecture.slmExamplesProcessed metrics)
                            , RowAssertions.sreTrainExamples = length trainSet
                            , RowAssertions.sreValidationExamples = length validationSet
                            , RowAssertions.sreTestExamples = length testSet
                            , RowAssertions.sreExamplesSeen =
                                fromIntegral (Architecture.slmExamplesProcessed metrics)
                            , RowAssertions.sreThroughputExamples =
                                fromIntegral (Architecture.slmExamplesProcessed metrics)
                            , RowAssertions.sreTrainLoss = Architecture.slmTrainLoss metrics
                            , RowAssertions.sreValidationLoss = Architecture.slmValidationLoss metrics
                            , RowAssertions.sreTestMetricName = "test_accuracy"
                            , RowAssertions.sreTestMetricGoal = TrainingBudget.MetricMaximise
                            , RowAssertions.sreTestMetricValue = testAcc
                            , RowAssertions.sreConvergenceThreshold = slLiteratureTarget threshold
                            , RowAssertions.sreConvergenceSlack = slSlack threshold
                            , RowAssertions.sreGradientNorm = vectorMagnitude finalWeights
                            , RowAssertions.sreSmokeThreshold = False
                            }
                    RowAssertions.assertSupervisedRowEvidence evidence @?= []
      , testCase "supervised row assertions reject invalid or smoke-only learning evidence (Sprint 24.2)" $ do
          let failures =
                RowAssertions.assertSupervisedRowEvidence
                  validSupervisedEvidence
                    { RowAssertions.sreFinalWeightHash = RowAssertions.sreInitialWeightHash validSupervisedEvidence
                    , RowAssertions.sreUpdateCount = 0
                    , RowAssertions.sreValidationExamples = 0
                    , RowAssertions.sreGradientNorm = 0.0
                    , RowAssertions.sreSmokeThreshold = True
                    }
          assertBool
            "equal initial/final hashes are rejected"
            ("final weight hash equals initial weight hash" `elem` failures)
          assertBool
            "zero updates are rejected"
            ("update count must be positive" `elem` failures)
          assertBool
            "missing validation partition is rejected"
            ("validation examples must be positive" `elem` failures)
          assertBool
            "zero gradients are rejected"
            ("gradient norm must be finite and positive" `elem` failures)
          assertBool
            "smoke thresholds are rejected"
            ("uses a smoke threshold rather than a literature/slack bar" `elem` failures)
      , testCase "underpowered two-step supervised evidence fails the literature bar (Sprint 24.2)" $ do
          let failures =
                RowAssertions.assertSupervisedRowEvidence
                  validSupervisedEvidence
                    { RowAssertions.sreRowId = "underpowered-2-step"
                    , RowAssertions.sreUpdateCount = 2
                    , RowAssertions.sreExamplesSeen = 2
                    , RowAssertions.sreTestMetricValue = 0.10
                    }
          assertBool
            "two-step model must fail the convergence bar"
            ( any
                ("test_accuracy failed convergence" `Text.isPrefixOf`)
                failures
            )
      , testCase "SL regression converges through the substrate JIT device (Sprint 8.12 --linux-cpu)" $ do
          env <- buildEnv defaultGlobalFlags
          substrate <- selectedTestSubstrate
          let device = mlpDeviceForSubstrate substrate env
          requireMlpDevice substrate device
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
            Right (_, regressionMetrics) -> do
              let mse = Regression.regressionTrainMse regressionMetrics
              assertBool
                ("expected device regression MSE < 0.02, got " <> show mse)
                (mse < 0.02)
              Regression.regressionOptimizerUpdatesExecuted regressionMetrics
                @?= fromIntegral
                  ( Regression.regEpochs config
                      * ( (length regressionSyntheticDataset + Regression.regBatchSize config - 1)
                            `div` Regression.regBatchSize config
                        )
                  )
      , testCase
          "all canonical SL architectures execute a substrate-backed train step (Sprint 8.12 --linux-cpu)"
          $ do
            env <- buildEnv defaultGlobalFlags
            substrate <- selectedTestSubstrate
            let device = mlpDeviceForSubstrate substrate env
            requireMlpDevice substrate device
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
      , testCase
          "all eleven trained canonical programs equal Store-loaded V2 inference on the same substrate (Sprint 10.6)"
          $ withSystemTempDirectory "jitml-sl-v2-parity"
          $ \checkpointRoot -> do
            publication <- readExistingLivePublication "."
            case publication of
              Nothing ->
                assertFailure
                  "no live cluster publication; exact Sprint 10.6 parity requires verified staged canonical artifacts"
              Just published -> do
                env <- buildEnv defaultGlobalFlags
                selectedSubstrate <- selectedTestSubstrate
                let substrate = publicationSubstrate published
                    device = mlpDeviceForSubstrate substrate env
                    settings = minioSettingsForLocalEdge (publicationEdgePort published)
                    floorRowIds =
                      ProductMatrix.floorSupervisedRows ProductMatrix.matrixFloor
                    floorRows =
                      [ row
                      | row <- ProductMatrix.allProductRows
                      , ProductMatrix.rowId row `elem` floorRowIds
                      ]
                    floorProblems =
                      [ problem
                      | rowId <- floorRowIds
                      , problem <- canonicalProblems
                      , problemName problem == rowId
                      ]
                substrate @?= selectedSubstrate
                requireMlpDevice substrate device
                fmap ProductMatrix.rowId floorRows @?= floorRowIds
                fmap problemName floorProblems @?= floorRowIds
                forM_ floorProblems $ \problem ->
                  case List.find ((== problemName problem) . ProductMatrix.rowId) floorRows of
                    Nothing ->
                      assertFailure
                        ("missing supervised ProductRow " <> Text.unpack (problemName problem))
                    Just row ->
                      assertProductionV2Parity
                        checkpointRoot
                        env
                        substrate
                        settings
                        row
                        problem
      , testCase
          "all eleven live supervised latest pointers load exact V2 runtime identity (Sprint 10.6 Live)"
          $ do
            publication <- readExistingLivePublication "."
            case publication of
              Nothing ->
                assertFailure
                  "no live cluster publication; Sprint 10.6 latest-pointer proof requires live MinIO"
              Just published -> do
                selectedSubstrate <- selectedTestSubstrate
                let substrate = publicationSubstrate published
                    settings = minioSettingsForLocalEdge (publicationEdgePort published)
                    floorRowIds =
                      ProductMatrix.floorSupervisedRows ProductMatrix.matrixFloor
                    floorRows =
                      [ row
                      | row <- ProductMatrix.allProductRows
                      , ProductMatrix.rowId row `elem` floorRowIds
                      ]
                substrate @?= selectedSubstrate
                length floorRowIds @?= 11
                fmap ProductMatrix.rowId floorRows @?= floorRowIds
                forM_ floorRows $
                  assertLiveLatestSupervisedV2Pointer substrate settings
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
          -- Sprint 23.1 anti-vacuity gate: every cohort's effective bar
          -- (target - slack) must sit strictly above its random-classification
          -- floor (1 / classes), so an untrained chance-level classifier fails
          -- every bar. This rejects the fabrication-prone
          -- @tiny-imagenet-resnet50@ effective 0.00 the audit flagged.
          forM_ slCohortThresholds $ \(problem, t) ->
            assertBool
              ( Text.unpack problem
                  <> " effective bar "
                  <> show (slEffectiveBar t)
                  <> " must exceed its random-classification floor "
                  <> show (slRandomBaseline problem)
              )
              (slBarIsNonVacuous problem t)
      , testCase "passesSlConvergence accepts target and rejects below the slack band (Sprint 13.4)" $ do
          let threshold = SlConvergenceThreshold 0.97 0.07
          assertBool "accepts the literature target" (passesSlConvergence threshold 0.97)
          assertBool "accepts target - slack (lower bar)" (passesSlConvergence threshold 0.90)
          assertBool
            "rejects a measured median below the slack band"
            (not (passesSlConvergence threshold 0.80))
      , testCase
          "live all canonical SL rows materialize staged bytes and train through the substrate runtime (Sprint 8.12 Live)"
          $ do
            publication <- readExistingLivePublication "."
            case publication of
              Nothing ->
                assertFailure "no live cluster publication; live all-row SL matrix cannot run"
              Just pub -> do
                env <- buildEnv defaultGlobalFlags
                let substrate = publicationSubstrate pub
                    device = mlpDeviceForSubstrate substrate env
                requireMlpDevice substrate device
                let settings = minioSettingsForLocalEdge (publicationEdgePort pub)
                    run = runMinIOSubprocess settings
                fetched <- traverse (fetchLiveSlProblemBytes run) canonicalProblems
                case lefts fetched of
                  [] -> do
                    results <- traverse (trainLiveProblemBytes device) (rights fetched)
                    case lefts results of
                      [] -> pure ()
                      errs -> assertFailure (unlines errs)
                  errs -> assertFailure (unlines errs)
      , testCase "live MNIST SL training clears the convergence threshold (Sprint 13.4 Live)" $ do
          -- Sprint 8.12 live convergence assertion. With a live cluster
          -- publication present, fetch the real MNIST bytes from MinIO,
          -- gunzip + IDX-parse + train the canonical row through the
          -- substrate-backed Architecture runtime over a bounded budget, and
          -- assert the measured test accuracy clears the in-code literature
          -- threshold − slack. No committed fixtures — the data is the
          -- canonical MinIO-staged MNIST and the bar is the in-code threshold.
          -- Missing publication or staged bytes fail closed.
          publication <- readExistingLivePublication "."
          case publication of
            Nothing ->
              assertFailure "no live cluster publication; live SL convergence assertion cannot run"
            Just pub ->
              case ( Data.Maybe.listToMaybe canonicalProblems
                   , Data.Maybe.listToMaybe canonicalProblems >>= Dataset.datasetForProblem
                   , slCohortThreshold "mnist-shallow-mlp"
                   ) of
                (Just problem, Just trainRef, Just threshold) -> do
                  let settings = minioSettingsForLocalEdge (publicationEdgePort pub)
                      testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
                      run = runMinIOSubprocess settings
                  trainImg <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
                  trainLbl <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
                  testImg <- run (Dataset.fetchVerifiedDatasetArtifactBytes testRef Dataset.ImagesArtifact)
                  testLbl <- run (Dataset.fetchVerifiedDatasetArtifactBytes testRef Dataset.LabelsArtifact)
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
                              { clfEpochs = liveMnistConvergenceEpochs
                              , clfLearningRate = 1.0e-2
                              }
                      case decodeBoundedDataset
                        config
                        (Just liveMnistTrainLimit)
                        (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload ti))
                        (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload tl)) of
                        Left err -> assertFailure ("live MNIST training failed: " <> err)
                        Right (configForData, trainSet) -> do
                          let spec = Architecture.architectureSpecForProblem configForData problem
                          trainedE <- Architecture.trainArchitectureWithDevice device spec configForData trainSet
                          case trainedE of
                            Left err ->
                              assertFailure ("live MNIST device architecture training failed: " <> Text.unpack err)
                            Right (trained, _trainAcc) -> do
                              testAccE <-
                                case ( parseIdxImages (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload vi))
                                     , parseIdxLabels (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload vl))
                                     ) of
                                  (Right (_, images), Right labels) ->
                                    Architecture.accuracyArchitectureWithDevice
                                      device
                                      trained
                                      (take liveMnistTestLimit (zipImagesLabels images labels))
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
                      assertFailure "live MNIST bytes unavailable from MinIO; staged dataset is required"
                _ -> assertFailure "missing MNIST dataset ref or convergence threshold"
      ]

assertProductionV2Parity
  :: FilePath
  -> Env
  -> Substrate
  -> MinIOSettings
  -> ProductMatrix.ProductRow state
  -> SL.CanonicalProblem
  -> IO ()
assertProductionV2Parity checkpointRoot env substrate minioSettings row problem = do
  projection <-
    expectText
      ("authoritative supervised ProductRow projection for " <> problemLabel problem)
      (supervisedProjectionFor substrate row)
  plan <-
    expectText
      ("authoritative SupervisedPlan for " <> problemLabel problem)
      (supervisedPlanForProjection projection)
  ProductMatrix.productProjectionRowId projection @?= problemName problem
  ProductMatrix.productProjectionPlanId projection
    @?= WorkloadPlan.supervisedPlanId plan
  (trainingExamples, epochs, evaluationExamples, batchExamples) <-
    expectText
      ("exact supervised execution budget for " <> problemLabel problem)
      (TrainingExecution.supervisedExecutionBudget plan)
  descriptorLearningRate <-
    case ProductMatrix.productProjectionDescriptor projection of
      ProductMatrix.SupervisedProductDescriptor _ _ _ learningRate ->
        pure learningRate
  let executionRuntime =
        TrainingExecution.TrainingExecutionRuntime
          { TrainingExecution.trainingResolveMinIOSettings =
              pure (Just minioSettings)
          }
  trainingResult <-
    runReaderT
      ( TrainingExecution.runDeviceMnistTrainingWithLimitsAndLearningRate
          executionRuntime
          substrate
          problem
          trainingExamples
          epochs
          evaluationExamples
          batchExamples
          (Just descriptorLearningRate)
      )
      env
  metrics <-
    expectText
      ("production supervised execution for " <> problemLabel problem)
      trainingResult
  TrainingExecution.tmCompletedUnits metrics @?= fromIntegral epochs
  TrainingExecution.tmExamplesProcessed metrics
    @?= trainingExamples
    * epochs
  assertBool
    (problemLabel problem <> " did not execute a positive evaluation-example budget")
    (evaluationExamples > 0)
  assertBool
    (problemLabel problem <> " did not execute a positive batch-example budget")
    (batchExamples > 0)
  assertBool
    (problemLabel problem <> " trainer did not observe any optimizer updates")
    (TrainingExecution.tmOptimizerUpdatesExecuted metrics > 0)
  Plan.quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
    @?= TrainingExecution.tmOptimizerUpdatesExecuted metrics
  assertBool
    (problemLabel problem <> " production parity probe input is empty")
    (not (null (TrainingExecution.tmParityProbeInput metrics)))
  assertBool
    (problemLabel problem <> " production parity probe output is empty")
    (not (null (TrainingExecution.tmParityProbeOutput metrics)))
  let experimentHash =
        ProductMatrix.productProjectionExperimentHash projection
      metricRows = ServiceCommand.trainingCheckpointMetrics metrics
  (completed, artifact) <-
    expectText
      ("exact ProductRow completion/runtime artifact for " <> problemLabel problem)
      ( CheckpointWriter.completedSupervisedRuntimeForTraining
          plan
          problem
          metrics
          experimentHash
          metricRows
      )
  let payload = RuntimeArtifact.trainingArtifactPayload artifact
      initialBytes = RuntimeArtifact.trainingArtifactInitialJmw1Bytes artifact
      finalBytes = RuntimeArtifact.trainingArtifactFinalJmw1Bytes artifact
  RuntimeArtifact.payloadRowId payload @?= ProductMatrix.rowId row
  RuntimeArtifact.payloadPlanId payload @?= WorkloadPlan.supervisedPlanId plan
  RuntimeArtifact.payloadDatasetSha256 payload
    @?= TrainingExecution.tmVerifiedDatasetShaAtRead metrics
  RuntimeArtifact.supervisedRuntimeToRaw (RuntimeArtifact.payloadRuntime payload)
    @?= TrainingExecution.tmSupervisedRuntimeProgram metrics
  initialBytes @?= TrainingExecution.tmInitialJmw1Bytes metrics
  finalBytes @?= TrainingExecution.tmFinalJmw1Bytes metrics
  assertBool
    (problemLabel problem <> " training did not move its exact JMW1 identity")
    ( WeightCodec.jmw1ContentSha (TrainingExecution.tmInitialJmw1Bytes metrics)
        /= WeightCodec.jmw1ContentSha (TrainingExecution.tmFinalJmw1Bytes metrics)
    )
  assertPersistedV2Parity
    checkpointRoot
    env
    substrate
    row
    projection
    completed
    metricRows
    artifact
    (TrainingExecution.tmParityProbeInput metrics)
    (VU.fromList (TrainingExecution.tmParityProbeOutput metrics))

supervisedPlanForProjection
  :: ProductMatrix.ProductProjection 'Plan.SupervisedTraining
  -> Either Text WorkloadPlan.SupervisedPlan
supervisedPlanForProjection projection =
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedSupervisedProductPlan plan -> Right plan

supervisedProjectionFor
  :: Substrate
  -> ProductMatrix.ProductRow state
  -> Either Text (ProductMatrix.ProductProjection 'Plan.SupervisedTraining)
supervisedProjectionFor substrate row =
  case ProductMatrix.projectProductRow substrate row of
    Plan.Failure errors ->
      Left
        ( "ProductRow projection failed for "
            <> ProductMatrix.rowId row
            <> ": "
            <> Text.pack (show errors)
        )
    Plan.Success
      ( ProductMatrix.SomeProductProjection
          Plan.SupervisedTrainingWitness
          projection
        ) -> Right projection
    Plan.Success _ ->
      Left ("ProductRow is not supervised: " <> ProductMatrix.rowId row)

assertLiveLatestSupervisedV2Pointer
  :: Substrate
  -> MinIOSettings
  -> ProductMatrix.ProductRow state
  -> IO ()
assertLiveLatestSupervisedV2Pointer substrate minioSettings row = do
  let rowId = ProductMatrix.rowId row
      experimentHash = ProductMatrix.productRowExperimentHash row
  projection <-
    expectText
      ("canonical substrate-specific ProductRow projection for " <> Text.unpack rowId)
      (supervisedProjectionFor substrate row)
  problem <-
    expectText
      ("canonical supervised problem for " <> Text.unpack rowId)
      ( case List.find ((== rowId) . problemName) canonicalProblems of
          Nothing -> Left (rowId <> ": no canonical supervised problem")
          Just value -> Right value
      )
  expectedInputTransform <-
    expectText
      ("live classification input transform for " <> Text.unpack rowId)
      =<< expectedLiveClassificationInputTransform
        minioSettings
        problem
        projection
  let expectedPlanId = ProductMatrix.productProjectionPlanId projection
  loaded <-
    runMinIOSubprocess minioSettings $
      CheckpointStore.loadInferenceCheckpointWithWeights
        ( \_ manifest weights _ ->
            pure $ do
              -- Phase 239: 'loadSupervisedRuntimeFromCheckpoint' is now the
              -- admission gate (validates the weight blob against the graph
              -- parameter count and returns ()); the supervised payload is read
              -- off the decoded manifest via 'manifestSupervisedRuntime', whose
              -- 'Nothing' still marks a runtime-free/V1 supervised checkpoint.
              _ <-
                CheckpointStore.loadSupervisedRuntimeFromCheckpoint manifest weights
              payload <-
                case Checkpoint.manifestSupervisedRuntime manifest of
                  Nothing ->
                    Left
                      ( rowId
                          <> ": live latest pointer targets a runtime-free/V1 supervised checkpoint"
                      )
                  Just value -> Right value
              let actualRowId = RuntimeArtifact.payloadRowId payload
                  actualPlanId = RuntimeArtifact.payloadPlanId payload
                  actualRuntime = RuntimeArtifact.payloadRuntime payload
              if actualRowId == rowId
                then Right ()
                else
                  Left
                    ( rowId
                        <> ": persisted V2 row ID mismatch: expected "
                        <> rowId
                        <> ", got "
                        <> actualRowId
                    )
              if Checkpoint.manifestPlanId manifest == Just expectedPlanId
                then Right ()
                else
                  Left
                    ( rowId
                        <> ": persisted manifest PlanId mismatch: expected "
                        <> Plan.planIdText expectedPlanId
                        <> ", got "
                        <> maybe
                          "<missing>"
                          Plan.planIdText
                          (Checkpoint.manifestPlanId manifest)
                    )
              if actualPlanId == expectedPlanId
                then Right ()
                else
                  Left
                    ( rowId
                        <> ": persisted V2 runtime PlanId mismatch: expected "
                        <> Plan.planIdText expectedPlanId
                        <> ", got "
                        <> Plan.planIdText actualPlanId
                    )
              if SL.problemDataset problem == "California Housing"
                then Right ()
                else do
                  if RuntimeArtifact.runtimeTaskIsClassification
                    (RuntimeArtifact.supervisedRuntimeTask actualRuntime)
                    then Right ()
                    else Left (rowId <> ": persisted V2 runtime is not classification")
                  let config =
                        defaultClassifierConfig
                          { clfSeed = SL.problemSeed problem
                          , clfInputs = RuntimeArtifact.supervisedRuntimeInputWidth actualRuntime
                          , clfClasses =
                              RuntimeArtifact.runtimeTaskSemanticWidth
                                (RuntimeArtifact.supervisedRuntimeTask actualRuntime)
                          }
                  expectedRuntime <-
                    Architecture.canonicalClassificationRuntimeContract config problem
                  let expectedRuntimeWithFittedInput =
                        case expectedInputTransform of
                          Nothing -> expectedRuntime
                          Just inputTransform ->
                            expectedRuntime
                              { RuntimeArtifact.rawSupervisedRuntimeInputTransform =
                                  inputTransform
                              }
                      actualRawRuntime = RuntimeArtifact.supervisedRuntimeToRaw actualRuntime
                  if actualRawRuntime == expectedRuntimeWithFittedInput
                    then Right ()
                    else
                      Left
                        ( rowId
                            <> ": persisted V2 executable differs from the current canonical runtime contract"
                        )
              Right []
        )
        experimentHash
        []
  _ <-
    expectText
      ("live latest V2 pointer for " <> Text.unpack rowId)
      loaded
  pure ()

-- | Derive the only fitted classification ingress program from the same
-- verified staged archive, exact ProductRow budget, and train/validation split
-- used by production training.  Every other classifier retains the canonical
-- unit-image contract; California Housing remains on its separate regression
-- projection above.
expectedLiveClassificationInputTransform
  :: MinIOSettings
  -> SL.CanonicalProblem
  -> ProductMatrix.ProductProjection 'Plan.SupervisedTraining
  -> IO (Either Text (Maybe RuntimeArtifact.RawRuntimeInputTransform))
expectedLiveClassificationInputTransform minioSettings problem projection
  | SL.problemName problem /= "cifar10-vit" = pure (Right Nothing)
  | otherwise =
      case Dataset.datasetForProblem problem of
        Nothing -> pure (Left "cifar10-vit has no canonical staged dataset reference")
        Just trainRef
          | Dataset.datasetName trainRef /= "CIFAR-10"
              || Dataset.datasetSplit trainRef /= Dataset.TrainSplit ->
              pure (Left "cifar10-vit does not resolve to the canonical CIFAR-10 train archive")
          | otherwise ->
              case supervisedPlanForProjection projection
                >>= TrainingExecution.supervisedExecutionBudget of
                Left err -> pure (Left err)
                Right (trainingExamples, epochs, _evaluationExamples, batchExamples) ->
                  case liveTrainingMaterializationLimit trainingExamples of
                    Left err -> pure (Left err)
                    Right materializationLimit -> do
                      archiveE <-
                        runMinIOSubprocess
                          minioSettings
                          ( Dataset.fetchVerifiedDatasetArtifactBytes
                              trainRef
                              Dataset.ArchiveArtifact
                          )
                      pure $ do
                        archiveArtifact <-
                          case archiveE of
                            Left err ->
                              Left
                                ( "verified staged CIFAR-10 train archive is unavailable: "
                                    <> Text.pack (show err)
                                )
                            Right value -> Right value
                        let config =
                              defaultClassifierConfig
                                { clfSeed = SL.problemSeed problem
                                , clfEpochs = epochs
                                , clfBatchSize = batchExamples
                                }
                        (_configForData, materialized) <-
                          case decodeCifar10ArchiveBoundedDataset
                            config
                            Dataset.TrainSplit
                            (Just materializationLimit)
                            (Dataset.fetchedArtifactPayload archiveArtifact) of
                            Left err -> Left (Text.pack err)
                            Right value -> Right value
                        let rawTrainSet = take trainingExamples materialized
                            rawValidationSet = drop trainingExamples materialized
                        if length rawTrainSet /= trainingExamples || null rawValidationSet
                          then
                            Left
                              "verified staged CIFAR-10 archive cannot satisfy the exact train/validation budget"
                          else
                            Just
                              <$> TrainingExecution.fitCifar10RgbInputTransform rawTrainSet

liveTrainingMaterializationLimit :: Int -> Either Text Int
liveTrainingMaterializationLimit trainingExamples
  | trainingExamples <= 0 = Left "supervised training-example budget must be positive"
  | validationExamples <= 0 =
      Left "supervised training-example budget is too small to derive a validation partition"
  | trainingExamples > maxBound - validationExamples =
      Left "supervised training/validation materialization limit exceeds the platform Int range"
  | otherwise = Right (trainingExamples + validationExamples)
 where
  validationExamples = trainingExamples `div` 5

assertPersistedV2Parity
  :: FilePath
  -> Env
  -> Substrate
  -> ProductMatrix.ProductRow state
  -> ProductMatrix.ProductProjection 'Plan.SupervisedTraining
  -> TrainingBudget.CompletedTraining
  -> [(Text, Double)]
  -> RuntimeArtifact.TrainingRuntimeArtifact
  -> [Double]
  -> VU.Vector Double
  -> IO ()
assertPersistedV2Parity checkpointRoot env substrate row projection completed metricRows artifact input expected = do
  let experimentHash = ProductMatrix.productProjectionExperimentHash projection
      payload = RuntimeArtifact.trainingArtifactPayload artifact
      runtime = RuntimeArtifact.payloadRuntime payload
      finalBytes = RuntimeArtifact.trainingArtifactFinalJmw1Bytes artifact
  writeResult <-
    runFilesystemMinIO checkpointRoot $
      CheckpointWriter.writeMinIOCompletedSupervisedCheckpoint
        Nothing
        completed
        experimentHash
        metricRows
        artifact
  stored <-
    case writeResult of
      Left err ->
        assertFailure
          ( Text.unpack (ProductMatrix.rowId row)
              <> " V2 write failed: "
              <> show err
          )
      Right value -> pure (CheckpointStore.completedStoredCheckpoint value)
  exactOuterBytes <-
    CheckpointStore.readObject
      checkpointRoot
      (CheckpointStore.storedManifestObjectKey stored)
      >>= expectText
        ("exact stored V2 outer bytes for " <> Text.unpack (ProductMatrix.rowId row))
  addressed <-
    expectText
      ("exact addressed V2 decode for " <> Text.unpack (ProductMatrix.rowId row))
      (Checkpoint.decodeAddressedManifestCbor exactOuterBytes)
  Checkpoint.addressedManifestWireVersion addressed
    @?= Checkpoint.checkpointWireVersionV2
  Checkpoint.addressedManifestBytes addressed @?= exactOuterBytes
  Checkpoint.addressedManifestSha addressed
    @?= CheckpointStore.storedManifestSha stored
  Checkpoint.addressedManifestBodySha addressed
    @?= CheckpointStore.storedManifestBodySha stored
  loadedResult <-
    runFilesystemMinIO checkpointRoot $
      CheckpointStore.loadInferenceCheckpointDecodedWithWeights
        ( \_ manifest weights values -> do
            liftIO $
              assertLoadedV2Bindings
                row
                projection
                stored
                artifact
                manifest
                weights
            liftIO (runSelectedWeightedEngine env substrate manifest weights values)
        )
        experimentHash
        input
  (loaded, decoded) <-
    expectText
      ("Store-loaded V2 inference for " <> Text.unpack (ProductMatrix.rowId row))
      loadedResult
  let tolerance = sameSubstrateV2Tolerance substrate
  assertVectorWithin
    (ProductMatrix.rowId row)
    tolerance
    expected
    (VU.fromList loaded)
  assertDecodedWithin
    (ProductMatrix.rowId row)
    tolerance
    runtime
    expected
    decoded
  RuntimeArtifact.payloadRowId payload @?= ProductMatrix.rowId row
  RuntimeArtifact.payloadPlanId payload @?= ProductMatrix.productProjectionPlanId projection
  RuntimeArtifact.payloadDatasetSha256 payload
    @?= TrainingBudget.completedTrainingDatasetShaAtRead completed
  RuntimeArtifact.payloadInitialJmw1Sha256 payload
    @?= TrainingBudget.completedTrainingInitialWeightHash completed
  RuntimeArtifact.payloadFinalJmw1Sha256 payload
    @?= TrainingBudget.completedTrainingFinalWeightHash completed
  WeightCodec.jmw1ContentSha finalBytes
    @?= RuntimeArtifact.payloadFinalJmw1Sha256 payload
  -- Phase 239: the served representation is the trained graph, so the parameter
  -- count is the graph parameter count carried by the payload's graph metadata.
  -- Prove the trained final weight vector fully covers that declared count.
  parameterCount <-
    expectText
      (Text.unpack (ProductMatrix.rowId row) <> " served graph parameter count")
      (RuntimeArtifact.supervisedPayloadParameterCount payload)
  finalValues <-
    expectText
      (Text.unpack (ProductMatrix.rowId row) <> " exact final JMW1 decode")
      (WeightCodec.decodeJmw1 finalBytes)
  length finalValues @?= parameterCount

assertLoadedV2Bindings
  :: ProductMatrix.ProductRow state
  -> ProductMatrix.ProductProjection 'Plan.SupervisedTraining
  -> CheckpointStore.StoredCheckpoint
  -> RuntimeArtifact.TrainingRuntimeArtifact
  -> Checkpoint.CheckpointManifest
  -> [CheckpointStore.LoadedWeightTensor]
  -> IO ()
assertLoadedV2Bindings row projection stored artifact manifest weights = do
  let payload = RuntimeArtifact.trainingArtifactPayload artifact
      runtime = RuntimeArtifact.payloadRuntime payload
      finalBytes = RuntimeArtifact.trainingArtifactFinalJmw1Bytes artifact
  -- Phase 239: the persisted weight layout is one graph-ordered
  -- @supervised.weights@ flat spec whose length is the served graph parameter
  -- count (matching Writer.buildCompletedSupervisedCheckpointSnapshot), and the
  -- single physical tensor has that same shape.
  parameterCount <-
    expectText
      (Text.unpack (ProductMatrix.rowId row) <> " served graph parameter count")
      (RuntimeArtifact.supervisedPayloadParameterCount payload)
  let expectedLayout =
        Checkpoint.FlatWeightLayout
          [ Checkpoint.TensorSpec
              "supervised.weights"
              [parameterCount]
              "F64"
          ]
      expectedTensor =
        Checkpoint.TensorBlob
          "supervised.weights"
          [parameterCount]
          ( Checkpoint.blobKey
              (ProductMatrix.productProjectionExperimentHash projection)
              (RuntimeArtifact.payloadFinalJmw1Sha256 payload)
          )
      isClassification =
        RuntimeArtifact.runtimeTaskIsClassification
          (RuntimeArtifact.supervisedRuntimeTask runtime)
      semanticWidth =
        RuntimeArtifact.runtimeTaskSemanticWidth
          (RuntimeArtifact.supervisedRuntimeTask runtime)
      expectedDecoderLabels =
        if isClassification
          then fmap (("class-" <>) . Text.pack . show) [0 .. semanticWidth - 1]
          else []
      expectedDecoderUnits =
        if isClassification then Nothing else Just "median-house-value"
  Checkpoint.manifestContentSha manifest
    @?= CheckpointStore.storedManifestSha stored
  Checkpoint.manifestExperiment manifest
    @?= ProductMatrix.productProjectionExperimentHash projection
  Checkpoint.manifestPlanId manifest
    @?= Just (ProductMatrix.productProjectionPlanId projection)
  Checkpoint.manifestSupervisedRuntime manifest @?= Just payload
  Checkpoint.manifestWeightLayout manifest @?= expectedLayout
  Checkpoint.validateSupervisedManifestShapeLayout manifest @?= []
  Checkpoint.manifestTensors manifest @?= [expectedTensor]
  expectedValues <-
    expectText
      ("exact final JMW1 decode for " <> Text.unpack (ProductMatrix.rowId row))
      (WeightCodec.decodeJmw1 finalBytes)
  case Checkpoint.manifestOutputDecoders manifest of
    [decoder] -> do
      Checkpoint.outputDecoderName decoder @?= "prediction"
      Checkpoint.outputDecoderLabels decoder @?= expectedDecoderLabels
      Checkpoint.outputDecoderUnits decoder @?= expectedDecoderUnits
      Checkpoint.outputDecoderKind decoder
        @?= if isClassification
          then Checkpoint.ClassificationOutput
          else Checkpoint.RegressionOutput
    decoders ->
      assertFailure
        ( Text.unpack (ProductMatrix.rowId row)
            <> " expected one persisted output decoder, got "
            <> show decoders
        )
  case weights of
    [loaded] -> do
      CheckpointStore.loadedWeightTensor loaded @?= expectedTensor
      CheckpointStore.loadedWeightJmw1Bytes loaded
        @?= LazyByteString.toStrict finalBytes
      CheckpointStore.loadedWeightValues loaded @?= expectedValues
    _ ->
      assertFailure
        ( Text.unpack (ProductMatrix.rowId row)
            <> " expected one Store-loaded physical tensor, got "
            <> show (length weights)
        )

runSelectedWeightedEngine
  :: Env
  -> Substrate
  -> Checkpoint.CheckpointManifest
  -> [CheckpointStore.LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runSelectedWeightedEngine env substrate manifest weights input =
  case substrate of
    AppleSilicon ->
      MetalLocal.runMetalWeightedCheckpointInference env manifest weights input
    LinuxCPU ->
      Local.runLinuxCpuWeightedCheckpointInference env manifest weights input
    LinuxCUDA ->
      CudaLocal.runCudaWeightedCheckpointInference env manifest weights input

assertVectorWithin
  :: Text
  -> Double
  -> VU.Vector Double
  -> VU.Vector Double
  -> IO ()
assertVectorWithin rowId tolerance expected actual = do
  VU.length actual @?= VU.length expected
  let differences = VU.zipWith (\left right -> abs (left - right)) expected actual
      maximumDifference = if VU.null differences then 0.0 else VU.maximum differences
  assertBool
    ( Text.unpack rowId
        <> " same-substrate trained/Store V2 parity exceeded tolerance "
        <> show tolerance
        <> ": max difference="
        <> show maximumDifference
        <> ", trained="
        <> show (VU.toList expected)
        <> ", loaded="
        <> show (VU.toList actual)
    )
    (maximumDifference <= tolerance)

assertDecodedWithin
  :: Text
  -> Double
  -> RuntimeArtifact.SupervisedRuntime
  -> VU.Vector Double
  -> InferenceDecode.DecodedInference
  -> IO ()
assertDecodedWithin rowId tolerance runtime expected decoded
  | RuntimeArtifact.runtimeTaskIsClassification
      (RuntimeArtifact.supervisedRuntimeTask runtime) =
      case decoded of
        InferenceDecode.DecodedClassification top confidence probabilities labels -> do
          let expectedValues = VU.toList expected
              expectedProbabilities = InferenceDecode.softmax expectedValues
              expectedTop = InferenceDecode.argmax expectedProbabilities
              expectedLabels =
                fmap
                  (("class-" <>) . Text.pack . show)
                  [0 .. RuntimeArtifact.runtimeTaskSemanticWidth (RuntimeArtifact.supervisedRuntimeTask runtime) - 1]
              expectedConfidence =
                case drop expectedTop expectedProbabilities of
                  value : _ -> value
                  [] -> 0.0
          top @?= expectedTop
          labels @?= expectedLabels
          assertBool
            ( Text.unpack rowId
                <> " decoded confidence exceeded same-substrate tolerance"
            )
            (abs (confidence - expectedConfidence) <= tolerance)
          assertVectorWithin
            (rowId <> "/decoded-probabilities")
            tolerance
            (VU.fromList expectedProbabilities)
            (VU.fromList probabilities)
        other ->
          assertFailure
            ( Text.unpack rowId
                <> " expected decoded classification, got "
                <> show other
            )
  | otherwise =
      case decoded of
        InferenceDecode.DecodedRegression values units -> do
          units @?= Just "median-house-value"
          assertVectorWithin
            (rowId <> "/decoded-regression")
            tolerance
            expected
            (VU.fromList values)
        other ->
          assertFailure
            ( Text.unpack rowId
                <> " expected decoded regression, got "
                <> show other
            )

expectText :: String -> Either Text value -> IO value
expectText label result =
  case result of
    Left err -> assertFailure (label <> " failed: " <> Text.unpack err)
    Right value -> pure value

-- Both sides execute the same exact weights through the same selected
-- substrate engine. CPU and CUDA structural kernels use the shared Double
-- ABI. Metal necessarily transports and reduces fp32 values through the fixed
-- bridge, so its explicit tolerance reflects that physical precision contract;
-- Sprint 30.4 owns retesting it on a real Apple lane.
sameSubstrateV2Tolerance :: Substrate -> Double
sameSubstrateV2Tolerance substrate =
  case substrate of
    AppleSilicon -> 1.0e-5
    LinuxCPU -> 1.0e-9
    LinuxCUDA -> 1.0e-9

selectedTestSubstrate :: IO Substrate
selectedTestSubstrate = do
  value <- lookupEnv "JITML_SUBSTRATE"
  case value of
    Nothing -> pure LinuxCPU
    Just raw ->
      case parseSubstrate (Text.pack raw) of
        Just substrate -> pure substrate
        Nothing -> assertFailure ("invalid JITML_SUBSTRATE: " <> raw)

requireMlpDevice :: Substrate -> MlpDevice -> IO ()
requireMlpDevice substrate device = do
  probe <- probeMlpDevice device
  case probe of
    Right () -> pure ()
    Left err ->
      assertFailure
        ( Text.unpack
            ( renderSubstrate substrate
                <> " JIT device unavailable: "
                <> err
            )
        )

data LiveSlProblemBytes
  = LiveSlIdx SL.CanonicalProblem ByteString ByteString ByteString ByteString
  | LiveSlArchive SL.CanonicalProblem ByteString

fetchLiveSlProblemBytes
  :: ( MinIOSubprocess (Either ServiceError Dataset.DatasetArtifactBytes)
       -> IO (Either ServiceError Dataset.DatasetArtifactBytes)
     )
  -> SL.CanonicalProblem
  -> IO (Either String LiveSlProblemBytes)
fetchLiveSlProblemBytes run problem =
  case Dataset.datasetForProblem problem of
    Nothing ->
      pure (Left ("missing dataset ref for " <> problemLabel problem))
    Just trainRef
      | SL.problemDataset problem == "MNIST"
          || SL.problemDataset problem == "Fashion-MNIST" -> do
          let testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
          trainImg <- fetchLivePayload run problem trainRef Dataset.ImagesArtifact "train images"
          trainLbl <- fetchLivePayload run problem trainRef Dataset.LabelsArtifact "train labels"
          testImg <- fetchLivePayload run problem testRef Dataset.ImagesArtifact "test images"
          testLbl <- fetchLivePayload run problem testRef Dataset.LabelsArtifact "test labels"
          pure (LiveSlIdx problem <$> trainImg <*> trainLbl <*> testImg <*> testLbl)
      | SL.problemDataset problem == "California Housing"
          || SL.problemDataset problem == "CIFAR-10"
          || SL.problemDataset problem == "CIFAR-100"
          || SL.problemDataset problem == "Tiny ImageNet" -> do
          archive <- fetchLivePayload run problem trainRef Dataset.ArchiveArtifact "archive"
          pure (LiveSlArchive problem <$> archive)
      | otherwise ->
          pure (Left ("unhandled dataset for " <> problemLabel problem))

fetchLivePayload
  :: ( MinIOSubprocess (Either ServiceError Dataset.DatasetArtifactBytes)
       -> IO (Either ServiceError Dataset.DatasetArtifactBytes)
     )
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> Dataset.DatasetArtifact
  -> String
  -> IO (Either String ByteString)
fetchLivePayload run problem ref artifact label = do
  fetched <- run (Dataset.fetchVerifiedDatasetArtifactBytes ref artifact)
  pure $
    case fetched of
      Left err ->
        Left
          ( problemLabel problem
              <> " staged "
              <> label
              <> " bytes are missing: "
              <> show err
          )
      Right bytes ->
        Right (Dataset.fetchedArtifactPayload bytes)

trainLiveProblemBytes :: MlpDevice -> LiveSlProblemBytes -> IO (Either String ())
trainLiveProblemBytes device bytes =
  case bytes of
    LiveSlIdx problem trainImg trainLbl testImg testLbl ->
      trainLiveIdxBytes device problem trainImg trainLbl testImg testLbl
    LiveSlArchive problem archiveBytes
      | SL.problemDataset problem == "California Housing" ->
          trainLiveCaliforniaBytes device problem archiveBytes
      | SL.problemDataset problem == "CIFAR-10" ->
          trainLiveArchiveClassifierBytes
            device
            problem
            archiveBytes
            decodeCifar10ArchiveBoundedDataset
      | SL.problemDataset problem == "CIFAR-100" ->
          trainLiveArchiveClassifierBytes
            device
            problem
            archiveBytes
            decodeCifar100ArchiveBoundedDataset
      | SL.problemDataset problem == "Tiny ImageNet" ->
          trainLiveArchiveClassifierBytes
            device
            problem
            archiveBytes
            TinyImageNet.decodeTinyImageNetArchiveBoundedClassificationDataset
      | otherwise ->
          pure (Left ("unhandled dataset for " <> problemLabel problem))

trainLiveIdxBytes
  :: MlpDevice
  -> SL.CanonicalProblem
  -> ByteString
  -> ByteString
  -> ByteString
  -> ByteString
  -> IO (Either String ())
trainLiveIdxBytes device problem trainImg trainLbl testImg testLbl = do
  let (trainLimit, testLimit, epochs, minimumTrainAccuracy) = liveClassifierBudget problem
      config = defaultClassifierConfig {clfEpochs = epochs}
  case ( decodeBoundedDataset
           config
           (Just trainLimit)
           (Dataset.maybeGunzip trainImg)
           (Dataset.maybeGunzip trainLbl)
       , decodeBoundedDataset
           config
           (Just testLimit)
           (Dataset.maybeGunzip testImg)
           (Dataset.maybeGunzip testLbl)
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

trainLiveArchiveClassifierBytes
  :: MlpDevice
  -> SL.CanonicalProblem
  -> ByteString
  -> ( ClassifierConfig
       -> Dataset.DatasetSplit
       -> Maybe Int
       -> ByteString
       -> Either String (ClassifierConfig, Dataset)
     )
  -> IO (Either String ())
trainLiveArchiveClassifierBytes device problem archiveBytes decodeArchive = do
  let (trainLimit, testLimit, epochs, minimumTrainAccuracy) = liveClassifierBudget problem
      config = defaultClassifierConfig {clfEpochs = epochs}
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

trainLiveCaliforniaBytes
  :: MlpDevice
  -> SL.CanonicalProblem
  -> ByteString
  -> IO (Either String ())
trainLiveCaliforniaBytes device problem archiveBytes =
  case Regression.decodeCaliforniaHousingArchiveBoundedData (Just liveCaliforniaTrainLimit) archiveBytes of
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
                  , Regression.regEpochs = liveCaliforniaEpochs
                  , Regression.regLearningRate = 5.0e-3
                  }
          trainedE <- Regression.trainRegressorWithDevice device config normalizedDataset
          case trainedE of
            Left err ->
              pure (Left (problemLabel problem <> " regression training failed: " <> Text.unpack err))
            Right (_, regressionMetrics) ->
              let mse = Regression.regressionTrainMse regressionMetrics
               in if not (finiteDouble mse)
                    then
                      pure
                        (Left (problemLabel problem <> " regression MSE was not finite: " <> show mse))
                    else
                      if mse >= 5.0
                        then
                          pure (Left (problemLabel problem <> " regression MSE too high: " <> show mse))
                        else pure (Right ())

liveClassifierBudget :: SL.CanonicalProblem -> (Int, Int, Int, Double)
liveClassifierBudget problem =
  case SL.problemDataset problem of
    "MNIST" -> (64, 64, 1, 0.0)
    "Fashion-MNIST" -> (64, 64, 1, 0.0)
    "CIFAR-10" -> (8, 8, 1, 0.0)
    "CIFAR-100" -> (8, 8, 1, 0.0)
    "Tiny ImageNet" -> (4, 4, 1, 0.0)
    _ -> (16, 16, 1, 0.0)

liveMnistTrainLimit :: Int
liveMnistTrainLimit = 10000

liveMnistTestLimit :: Int
liveMnistTestLimit = 5000

liveMnistConvergenceEpochs :: Int
liveMnistConvergenceEpochs = 60

liveCaliforniaTrainLimit :: Int
liveCaliforniaTrainLimit = 64

liveCaliforniaEpochs :: Int
liveCaliforniaEpochs = 40

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

architectureEvidenceSplits :: (Dataset, Dataset, Dataset)
architectureEvidenceSplits =
  (concatMap (take 4 . classExamples) [0, 1, 2], validationSet, testSet)
 where
  classExamples label =
    filter ((== label) . exampleLabel) architectureSyntheticDataset
  validationSet =
    concatMap (take 1 . drop 4 . classExamples) [0, 1, 2]
  testSet =
    concatMap (take 1 . drop 5 . classExamples) [0, 1, 2]

validSupervisedEvidence :: RowAssertions.SupervisedRowEvidence
validSupervisedEvidence =
  RowAssertions.SupervisedRowEvidence
    { RowAssertions.sreRowId = "mnist-shallow-mlp"
    , RowAssertions.sreInitialWeightHash = "initial-hash"
    , RowAssertions.sreFinalWeightHash = "final-hash"
    , RowAssertions.sreUpdateCount = 12
    , RowAssertions.sreTrainExamples = 6
    , RowAssertions.sreValidationExamples = 3
    , RowAssertions.sreTestExamples = 3
    , RowAssertions.sreExamplesSeen = 12
    , RowAssertions.sreThroughputExamples = 12.0
    , RowAssertions.sreTrainLoss = 0.25
    , RowAssertions.sreValidationLoss = 0.30
    , RowAssertions.sreTestMetricName = "test_accuracy"
    , RowAssertions.sreTestMetricGoal = TrainingBudget.MetricMaximise
    , RowAssertions.sreTestMetricValue = 0.95
    , RowAssertions.sreConvergenceThreshold = 0.97
    , RowAssertions.sreConvergenceSlack = 0.07
    , RowAssertions.sreGradientNorm = 1.0
    , RowAssertions.sreSmokeThreshold = False
    }

weightDigest :: [Double] -> Text
weightDigest weights =
  Text.intercalate
    ":"
    [ "weights"
    , Text.pack (show (length weights))
    , Text.pack (show (sum weights))
    , Text.pack (show (sum (fmap (\value -> value * value) weights)))
    ]

vectorMagnitude :: [Double] -> Double
vectorMagnitude =
  sum . fmap abs

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

cifarPlanarPayload
  :: [(Int, Word8)]
  -> [(Int, Word8)]
  -> [(Int, Word8)]
  -> [Word8]
cifarPlanarPayload redSentinels greenSentinels blueSentinels =
  concatMap channelPlane [redSentinels, greenSentinels, blueSentinels]
 where
  channelPlane sentinels =
    [ Data.Maybe.fromMaybe 0 (lookup pixel sentinels)
    | pixel <- [0 .. 1023]
    ]

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

isBatchNorm :: LayerGraph.LayerKind -> Bool
isBatchNorm (LayerGraph.NormLayer LayerGraph.BatchNorm) = True
isBatchNorm _ = False

isDropout :: LayerGraph.LayerKind -> Bool
isDropout (LayerGraph.DropoutLayer _) = True
isDropout _ = False

isConv2D :: LayerGraph.LayerKind -> Bool
isConv2D LayerGraph.Conv2DLayer = True
isConv2D _ = False

isPool :: LayerGraph.LayerKind -> Bool
isPool (LayerGraph.PoolLayer _) = True
isPool _ = False

isBasicBlock :: LayerGraph.LayerKind -> Bool
isBasicBlock (LayerGraph.BasicBlockLayer _) = True
isBasicBlock _ = False

isBottleneckBlock :: LayerGraph.LayerKind -> Bool
isBottleneckBlock (LayerGraph.BottleneckBlockLayer _) = True
isBottleneckBlock _ = False

isGroupNorm :: LayerGraph.LayerKind -> Bool
isGroupNorm (LayerGraph.NormLayer (LayerGraph.GroupNorm _)) = True
isGroupNorm _ = False

isAttention :: LayerGraph.LayerKind -> Bool
isAttention (LayerGraph.MultiHeadAttentionLayer _) = True
isAttention _ = False

isLayerNorm :: LayerGraph.LayerKind -> Bool
isLayerNorm (LayerGraph.NormLayer LayerGraph.LayerNorm) = True
isLayerNorm _ = False

isGeGLU :: LayerGraph.LayerKind -> Bool
isGeGLU LayerGraph.GeGLULayer = True
isGeGLU _ = False

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

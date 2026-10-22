{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module InitialSnapshotOwnership (initialSnapshotOwnershipTests) where

import Codec.Serialise (serialise)
import Data.Foldable (for_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Numerics.LayerGraphMetadata
  ( LayerGraphModeMetadata (..)
  , layerGraphMetadataFromGraph
  , layerGraphMetadataNodes
  , layerGraphNodeMode
  )
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Plan.Plan (RunKindWitness (..), Validation (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Regression qualified as Regression
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Substrate (Substrate (LinuxCPU))

initialSnapshotOwnershipTests :: TestTree
initialSnapshotOwnershipTests =
  testGroup
    "trainer-owned initial snapshots"
    [ testCase "regression returns the actual first device parameters and exact initial bytes" $ do
        forwards <- newIORef []
        gradients <- newIORef []
        let reference = pureReferenceMlpDevice
            device =
              reference
                { mlpdForwardBatch = \params inputs -> do
                    modifyIORef' forwards (<> [params])
                    mlpdForwardBatch reference params inputs
                , mlpdBatchGradient = \params samples -> do
                    modifyIORef' gradients (<> [params])
                    mlpdBatchGradient reference params samples
                }
            config =
              Regression.defaultRegressionConfig
                { Regression.regSeed = 17
                , Regression.regInputs = 2
                , Regression.regHidden = 3
                , Regression.regEpochs = 2
                , Regression.regBatchSize = 1
                , Regression.regLearningRate = 0.01
                }
            examples =
              [ Regression.RegressionExample (VU.fromList [1.0, 0.0]) 2.0
              , Regression.RegressionExample (VU.fromList [0.0, 1.0]) (-1.0)
              ]
        (trained, metrics) <- expectRight =<< Regression.trainRegressorWithDevice device config examples
        actualForwards <- readIORef forwards
        actualGradients <- readIORef gradients
        length actualForwards @?= 5
        length actualGradients @?= 4
        firstForward <- firstObserved "first regression forward" actualForwards
        firstGradient <- firstObserved "first regression gradient" actualGradients
        Regression.regressionInitialParams metrics @?= firstForward
        firstGradient @?= firstForward
        Regression.regressionOptimizerUpdatesExecuted metrics @?= 4
        assertBool
          "the controlled training run must change its initial state"
          (Regression.trainedRegressorParams trained /= firstForward)
        let captured = WeightCodec.encodeJmw1 (Mlp.mlpParamsToFlat firstForward)
            returned = WeightCodec.encodeJmw1 (Mlp.mlpParamsToFlat (Regression.regressionInitialParams metrics))
        returned @?= captured
        WeightCodec.decodeJmw1 returned @?= Right (Mlp.mlpParamsToFlat firstForward)
    , testCase "resumed architecture updates preserve the original graph descriptor and weights" $ do
        (config, spec, examples) <- architectureFixture SL.DenseFamily 29
        initial <-
          expectRight
            =<< Architecture.initialiseExactArchitectureTraining
              spec
              config
              Architecture.ArchitectureAdam
              0.0
              examples
              examples
        let originalWeights = Architecture.exactArchitectureInitialWeights initial
            originalDescriptor = Architecture.exactArchitectureInitialLayerGraphMetadata initial
        Architecture.exactArchitectureUpdatesExecuted initial @?= 0
        first <-
          expectRight =<< Architecture.advanceExactArchitectureTraining pureReferenceMlpDevice 1 initial
        resumed <-
          expectRight =<< Architecture.advanceExactArchitectureTraining pureReferenceMlpDevice 2 first
        Architecture.exactArchitectureUpdatesExecuted resumed @?= 3
        Architecture.exactArchitectureInitialWeights resumed @?= originalWeights
        Architecture.exactArchitectureInitialLayerGraphMetadata resumed @?= originalDescriptor
        assertBool
          "successful updates must move the trained fixture parameters"
          (Architecture.exactArchitectureTrainedWeights resumed /= originalWeights)
        (zeroModel, zeroMetrics) <- runExact spec config 0 examples
        Architecture.slmInitialWeights zeroMetrics @?= originalWeights
        Architecture.slmInitialLayerGraphMetadata zeroMetrics @?= originalDescriptor
        layerGraphMetadataFromGraph (Architecture.trainedArchGraph zeroModel) @?= originalDescriptor
        assertBool
          "the fixture must distinguish actual expanded graph0 from its builder template"
          (originalDescriptor /= layerGraphMetadataFromGraph (Architecture.archLayerGraph spec))
        (fullModel, fullMetrics) <- runExact spec config 3 examples
        Architecture.trainedArchitectureWeights fullModel
          @?= Architecture.exactArchitectureTrainedWeights resumed
        Architecture.slmInitialWeights fullMetrics @?= originalWeights
        Architecture.slmInitialLayerGraphMetadata fullMetrics @?= originalDescriptor
        Architecture.slmOptimizerUpdatesExecuted fullMetrics @?= 3
    , testCase
        "epoch selection retains actual initialization and an explicit seed changes initial weights"
        $ do
          (config, spec, examples) <- architectureFixture SL.DenseFamily 37
          (zeroModel, zeroMetrics) <- runExact spec config 0 examples
          (selected, metrics) <-
            expectRight
              =<< Architecture.trainArchitectureWithDeviceSelected
                pureReferenceMlpDevice
                spec
                config
                examples
                (reverse examples)
          Architecture.slmInitialWeights metrics @?= Architecture.trainedArchitectureWeights zeroModel
          Architecture.slmInitialLayerGraphMetadata metrics
            @?= Architecture.slmInitialLayerGraphMetadata zeroMetrics
          layerGraphMetadataFromGraph (Architecture.trainedArchGraph selected)
            @?= Architecture.slmInitialLayerGraphMetadata metrics
          Architecture.slmOptimizerUpdatesExecuted metrics @?= 4
          assertBool
            "the selected trained model must differ from initialization"
            (Architecture.trainedArchitectureWeights selected /= Architecture.slmInitialWeights metrics)
          (otherConfig, otherSpec, otherExamples) <- architectureFixture SL.DenseFamily 38
          (_, otherMetrics) <- runExact otherSpec otherConfig 0 otherExamples
          assertBool
            "changing the explicit execution seed must reach the actual initializer"
            (Architecture.slmInitialWeights otherMetrics /= Architecture.slmInitialWeights metrics)
          Architecture.slmInitialLayerGraphMetadata otherMetrics
            @?= Architecture.slmInitialLayerGraphMetadata metrics
    , testCase "literal architecture serving modes survive initial snapshot and training unchanged" $ do
        (config, spec, examples) <- architectureFixture SL.DeepDenseFamily 41
        (zeroModel, zeroMetrics) <- runExact spec config 0 examples
        (trained, metrics) <- runExact spec config 1 examples
        let descriptor = Architecture.slmInitialLayerGraphMetadata zeroMetrics
        assertBool
          "the fixture must include an actual TrainingMode node"
          (any ((== LayerGraphTrainingMode) . layerGraphNodeMode) (layerGraphMetadataNodes descriptor))
        layerGraphMetadataFromGraph (Architecture.trainedArchGraph zeroModel) @?= descriptor
        Architecture.slmInitialLayerGraphMetadata metrics @?= descriptor
        Architecture.slmInitialWeights metrics @?= Architecture.slmInitialWeights zeroMetrics
        layerGraphMetadataFromGraph (Architecture.trainedArchGraph trained) @?= descriptor
    , testCase
        "all canonical classification descriptors are identical across the five prescribed initialization seeds"
        $ for_
          (filter ((/= "California Housing") . SL.problemDataset) SL.canonicalProblems)
          checkCanonicalSeedDescriptors
    ]

architectureFixture
  :: SL.ArchitectureFamily
  -> Int
  -> IO (Classifier.ClassifierConfig, Architecture.ArchitectureSpec, Classifier.Dataset)
architectureFixture family seed = do
  let config =
        Classifier.defaultClassifierConfig
          { Classifier.clfSeed = seed
          , Classifier.clfInputs = 2
          , Classifier.clfHidden = 3
          , Classifier.clfClasses = 2
          , Classifier.clfEpochs = 2
          , Classifier.clfBatchSize = 1
          , Classifier.clfLearningRate = 0.01
          }
      problem = SL.CanonicalProblem "initial-snapshot-fixture" "MNIST" "Dense" family seed
      examples =
        [ Classifier.LabeledExample (VU.fromList [1.0, 0.0]) 0
        , Classifier.LabeledExample (VU.fromList [0.0, 1.0]) 1
        ]
  spec <- expectRight (Architecture.architectureSpecForProblem config problem)
  pure (config, spec, examples)

runExact
  :: Architecture.ArchitectureSpec
  -> Classifier.ClassifierConfig
  -> Int
  -> Classifier.Dataset
  -> IO (Architecture.TrainedArchitecture, Architecture.SlRunMetrics)
runExact spec config updates examples =
  expectRight
    =<< Architecture.trainArchitectureWithDeviceForExactUpdates
      pureReferenceMlpDevice
      spec
      config
      Architecture.ArchitectureAdam
      0.0
      updates
      examples
      examples

expectRight :: Either Text value -> IO value
expectRight = either (assertFailure . Text.unpack) pure

firstObserved :: String -> [value] -> IO value
firstObserved label values = case values of
  first : _ -> pure first
  [] -> assertFailure ("no actual device call observed: " <> label)

-- Uses production architecture constructors and actual initialized graph0 at
-- canonical input/class dimensions. It executes no training/device calls and
-- makes no cohort-learning claim. Parameter payloads are deliberately excluded
-- by the full metadata serialization, while existing controls prove seed reach.
checkCanonicalSeedDescriptors :: SL.CanonicalProblem -> IO ()
checkCanonicalSeedDescriptors problem = do
  row <-
    maybe
      (assertFailure "missing canonical classification row")
      pure
      (find ((== SL.problemName problem) . Matrix.rowId) Matrix.allProductRows)
  case Matrix.projectProductRow LinuxCPU row of
    Failure failures -> assertFailure ("classification projection failed: " <> show failures)
    Success (Matrix.SomeProductProjection SupervisedTrainingWitness projection) -> do
      cohort <- expectRight (Cohort.mkSupervisedCohortPlan projection)
      length (Cohort.supervisedCohortPlanChildren cohort) @?= 5
      (inputs, classes) <- expectRight (canonicalDimensions problem)
      descriptors <-
        traverse
          ( \child -> do
              executionSeed <-
                expectRight (TrainingExecution.supervisedExecutionSeed (Cohort.supervisedSeedPlanWorkload child))
              toInteger executionSeed @?= toInteger (Cohort.supervisedSeedPlanSeed child)
              let config =
                    Classifier.defaultClassifierConfig
                      { Classifier.clfInputs = inputs
                      , Classifier.clfClasses = classes
                      , Classifier.clfSeed = executionSeed
                      }
                  examples = [Classifier.LabeledExample (VU.replicate inputs 0) 0]
              spec <- expectRight (Architecture.architectureSpecForProblem config problem)
              initialized <-
                expectRight
                  =<< Architecture.initialiseExactArchitectureTraining
                    spec
                    config
                    Architecture.ArchitectureAdam
                    0
                    examples
                    examples
              pure
                ( serialise (layerGraphMetadataFromGraph (Architecture.archLayerGraph spec))
                , serialise (Architecture.exactArchitectureInitialLayerGraphMetadata initialized)
                )
          )
          (Cohort.supervisedCohortPlanChildren cohort)
      first <- firstObserved "canonical initial descriptor" descriptors
      for_ descriptors (@?= first)
    Success _ -> assertFailure "canonical classifier projected as a different run kind"

canonicalDimensions :: SL.CanonicalProblem -> Either Text (Int, Int)
canonicalDimensions problem = case SL.problemDataset problem of
  "MNIST" -> Right (784, 10)
  "Fashion-MNIST" -> Right (784, 10)
  "CIFAR-10" -> Right (3072, 10)
  "CIFAR-100" -> Right (3072, 100)
  "Tiny ImageNet" -> Right (12288, 200)
  other -> Left ("unrecognized canonical classification dimensions: " <> other)

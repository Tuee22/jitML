{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module SupervisedTrainingSeed
  ( supervisedTrainingSeedTests
  )
where

import Data.List (find)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( RawRunBudget (..)
  , RawRunRequest (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , Validation (..)
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Matrix qualified as Product
import JitML.Proto.Training (StartTraining (..))
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

supervisedTrainingSeedTests :: TestTree
supervisedTrainingSeedTests =
  testGroup
    "supervised execution seed"
    [ testCase "extracts the exact generic SupervisedPlan seed" $ do
        plan <- preparedPlan 1729
        TrainingExecution.supervisedExecutionSeed plan @?= Right 1729
    , testCase "rejects a generic seed outside the platform Int range" $ do
        plan <- preparedPlan (maxBound :: Word64)
        TrainingExecution.supervisedExecutionSeed plan
          @?= Left "supervised execution seed exceeds the platform Int range"
    , testCase "rejects a refined supervised plan with more than one seed" $ do
        plan <-
          case WorkloadPlan.resolveSupervisedPlan multiSeedRawPlan of
            Failure errors ->
              assertFailure ("multi-seed fixture did not refine: " <> show errors)
                >> fail "unreachable multi-seed refinement failure"
            Success value -> pure value
        TrainingExecution.supervisedExecutionSeed plan
          @?= Left "supervised execution requires exactly one refined plan seed"
    , testCase "generic initialization seed changes state but not persisted topology" $ do
        problem <- requireCanonicalProblem "mnist-shallow-mlp"
        let canonicalConfig = classifierConfig (SL.problemSeed problem)
            genericConfig = classifierConfig 1729
            canonicalSpec = Architecture.architectureSpecForProblem canonicalConfig problem
            genericSpec = Architecture.architectureSpecForProblem genericConfig problem
        assertBool
          "distinct exact execution seeds reused the same initialization graph"
          (Architecture.archLayerGraph canonicalSpec /= Architecture.archLayerGraph genericSpec)
        canonicalRuntime <-
          either
            (assertFailure . Text.unpack)
            pure
            (Architecture.canonicalClassificationRuntimeContract canonicalConfig problem)
        genericRuntime <-
          either
            (assertFailure . Text.unpack)
            pure
            (Architecture.canonicalClassificationRuntimeContract genericConfig problem)
        genericRuntime @?= canonicalRuntime
    , testCase "ProductRow experiment loading still rejects a changed projected seed" $ do
        row <- requireProductRow "mnist-shallow-mlp"
        let budget = Product.trainingBudget row
        changedBudget <-
          either
            (assertFailure . Text.unpack)
            pure
            ( Budget.mkTrainingBudget
                (Budget.trainingBudgetKind budget)
                (Budget.trainingBudgetTargetUnits budget)
                (Just 1729)
            )
        case Product.projectProductRow LinuxCPU row {Product.trainingBudget = changedBudget} of
          Failure errors ->
            assertFailure ("changed-seed ProductRow did not project: " <> show errors)
          Success (Product.SomeProductProjection SupervisedTrainingWitness projection) -> do
            loaded <- ProductExperiment.loadSupervisedProductExperiment projection
            case loaded of
              Left err ->
                assertBool
                  ("unexpected ProductRow seed rejection: " <> Text.unpack err)
                  ("supervised experiment seed mismatch" `Text.isInfixOf` err)
              Right _ ->
                assertFailure "changed projected ProductRow seed passed exact experiment loading"
          Success (Product.SomeProductProjection witness _) ->
            assertFailure ("supervised ProductRow projected with the wrong witness: " <> show witness)
    ]

preparedPlan :: Word64 -> IO WorkloadPlan.SupervisedPlan
preparedPlan seed =
  case PlanCommand.prepareStartTraining (baseStartTraining seed) of
    Left err -> assertFailure (Text.unpack err) >> fail "unreachable plan preparation failure"
    Right (_, plan) -> pure plan

baseStartTraining :: Word64 -> StartTraining
baseStartTraining seed =
  StartTraining
    { stExperimentHash = "generic-supervised-seed-test"
    , stDhallObjectKey = "experiments/mnist.dhall"
    , stSubstrate = LinuxCPU
    , stSeed = seed
    , stEpochs = 1
    , stBatchSize = 1
    , stPlanId = ""
    , stResolvedPlan = ""
    , stTrainingExamples = 1
    , stEvaluationExamples = 1
    }

multiSeedRawPlan :: WorkloadPlan.RawSupervisedPlan
multiSeedRawPlan =
  WorkloadPlan.RawSupervisedPlan
    RawRunRequest
      { rawRunVersion = 1
      , rawRunKind = SupervisedTrainingWitness
      , rawRunExperimentId = "generic-supervised-multi-seed-test"
      , rawRunSubjectId = "experiments/mnist.dhall"
      , rawRunArtifactId = "experiments/mnist.dhall"
      , rawRunTopicId = "training.linux-cpu"
      , rawRunSubstrate = LinuxCPU
      , rawRunPlacement = ClusterRun
      , rawRunSeeds = [11, 12]
      , rawRunBudget = RawSupervisedBudget 1 1 1 1 1
      }

classifierConfig :: Int -> Classifier.ClassifierConfig
classifierConfig seed =
  Classifier.defaultClassifierConfig
    { Classifier.clfSeed = seed
    , Classifier.clfInputs = 784
    , Classifier.clfClasses = 10
    }

requireCanonicalProblem :: Text.Text -> IO SL.CanonicalProblem
requireCanonicalProblem identity =
  case find ((== identity) . SL.problemName) SL.canonicalProblems of
    Nothing -> assertFailure ("missing canonical problem " <> Text.unpack identity) >> fail "unreachable"
    Just problem -> pure problem

requireProductRow :: Text.Text -> IO (Product.ProductRow 'Product.Declared)
requireProductRow identity =
  case find ((== identity) . Product.rowId) Product.allProductRows of
    Nothing -> assertFailure ("missing ProductRow " <> Text.unpack identity) >> fail "unreachable"
    Just row -> pure row

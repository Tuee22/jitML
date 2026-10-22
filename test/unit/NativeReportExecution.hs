{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- Actual existing filesystem-admitted supervised fixture, inspected as
-- immutable DATA only. No native child/parent/publication cap is fabricated.
module NativeReportExecution (nativeReportExecutionTests) where

import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Store qualified as Store
import JitML.Plan.Plan (RunKind (SupervisedTraining))
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.Pipeline qualified as Pipeline
import JitML.Test.ContractFixtures (withAdmittedProductProjection)
import JitML.Test.Report qualified as Report

data Fixture
  = Fixture
      !(Matrix.ProductProjection 'SupervisedTraining)
      !(Report.ProductScenarioPrecondition 'SupervisedTraining)
      !(Report.AddressedProductScenarioCompletion 'SupervisedTraining)
      !Store.AdmittedCompletedCheckpoint

nativeReportExecutionTests :: TestTree
nativeReportExecutionTests =
  testGroup
    "total product execution admission"
    [ withResource acquire (const (pure ())) $ \get ->
        testGroup
          "actual retained neural fixture DATA"
          [ testCase "actual neural admission embeds and recovers without changing identity" $ do
              Fixture _ _ _ admitted <- get
              Store.admittedExecutionNeuralCompletion (Store.admittedExecutionFromNeural admitted)
                @?= Just admitted
          , testCase "total admission retains the exact admitted manifest and completion" $ do
              Fixture _ _ _ admitted <- get
              let total = Store.admittedExecutionFromNeural admitted
              Store.admittedExecutionCheckpoint total @?= Store.admittedCompletedCheckpoint admitted
              Store.admittedExecutionCompletedTraining total @?= Store.admittedCompletedTraining admitted
          , testCase "total neural provenance is the same actual old witness" $ do
              Fixture _ _ _ admitted <- get
              Store.admittedExecutionProvenance (Store.admittedExecutionFromNeural admitted)
                @?= NeuralDeviceExecution (Store.admittedCompletedDeviceWitness admitted)
          , testCase "total inference reference preserves the old neural reference exactly" $ do
              Fixture _ _ _ admitted <- get
              Pipeline.inferenceEligibleExecutionModelRef (Store.admittedExecutionFromNeural admitted)
                @?= Pipeline.inferenceEligibleModelRef admitted
          , testCase "total inference transition preserves the old completion and experiment guards" $ do
              Fixture _ _ _ admitted <- get
              let completed = Store.admittedCompletedTraining admitted
                  oldRef = Pipeline.inferenceEligibleModelRef admitted
                  started =
                    Pipeline.startTraining
                      (Pipeline.declareModel (Pipeline.declareExperiment (Pipeline.modelRefExperimentHash oldRef)))
                  trained = Pipeline.completeTraining started completed
                  foreignStarted = Pipeline.startTraining (Pipeline.declareModel (Pipeline.declareExperiment "another-experiment"))
                  foreignTrained = Pipeline.completeTraining foreignStarted completed
                  total = Store.admittedExecutionFromNeural admitted
              Pipeline.markExecutionInferenceEligible total trained
                @?= Pipeline.markInferenceEligible admitted trained
              Pipeline.markExecutionInferenceEligible total foreignTrained
                @?= Pipeline.markInferenceEligible admitted foreignTrained
              assertBool
                "foreign experiment must remain rejected"
                ( case Pipeline.markExecutionInferenceEligible total foreignTrained of
                    Left _ -> True
                    Right _ -> False
                )
          , testCase "shared total completion preserves all old supervised numerical guards" $ do
              Fixture projection _ _ admitted <- get
              Report.productScenarioExecutionCompletion projection (Store.admittedExecutionFromNeural admitted)
                @?= Report.productScenarioCompletion projection admitted
          , testCase "addressed completion exposes total admission and a safe actual neural view" $ do
              Fixture _ _ addressed admitted <- get
              Report.addressedProductScenarioAdmittedExecution addressed
                @?= Store.admittedExecutionFromNeural admitted
              Report.addressedProductScenarioAdmittedCompletion addressed @?= Just admitted
          , testCase
              "native certificate attachment refuses a genuine supervised result before poisoned native arguments"
              $ do
                Fixture projection precondition addressed _ <- get
                executed <- case Report.executedProductScenarioCompletion precondition projection addressed of
                  Left errors -> assertFailure (show errors)
                  Right actual -> pure actual
                case Report.attachExecutedProductScenarioNativeCertificate
                  (error "non-native refusal must not demand the native expected source")
                  (error "non-native refusal must not demand an arbitrary native certificate")
                  executed of
                  Left errors ->
                    assertBool
                      "actual supervised result must refuse native certificate attachment"
                      ("non-native projection" `Text.isInfixOf` Text.pack (show errors))
                  Right _ -> assertFailure "native certificate attached to supervised result"
          ]
    ]
 where
  -- withAdmittedProductProjection performs the real existing fixture write /
  -- Store admission while the directory is live. The pooled fields below are
  -- immutable getters; no control performs a later physical read after its
  -- bracket cleans up, nor claims successful native execution or restoration.
  acquire = withAdmittedProductProjection $ \_ _ projection precondition addressed admitted ->
    pure (Fixture projection precondition addressed admitted)

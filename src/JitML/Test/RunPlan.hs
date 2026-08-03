{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.RunPlan
  ( runPlanTests
  )
where

import Control.Monad (void)
import Data.Foldable (traverse_)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan
  ( EventId
  , PlanError (..)
  , Quantity
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKind (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , RunPlan
  , Unit (..)
  , Validation (..)
  , deriveEventId
  , eventIdText
  , finiteMeasurementValue
  , mkFiniteMeasurement
  , mkQuantity
  , planIdText
  , quantityValue
  , resolveRun
  , runPlanBudgetSummary
  , runPlanId
  , runPlanSeeds
  , seedCohortValues
  )
import JitML.Substrate (Substrate (..))

runPlanTests :: TestTree
runPlanTests =
  testGroup
    "validated run plans (Sprint 8.16)"
    [ testCase "resolveRun accumulates every independent plan error" $ do
        let invalid =
              RawRunRequest
                { rawRunVersion = 0
                , rawRunKind = SupervisedTrainingWitness
                , rawRunExperimentId = " "
                , rawRunSubjectId = ""
                , rawRunArtifactId = "\t"
                , rawRunTopicId = ""
                , rawRunSubstrate = LinuxCPU
                , rawRunPlacement = HostRun
                , rawRunSeeds = []
                , rawRunBudget = RawSupervisedBudget 0 0 0 0 0
                }
        case resolveRun invalid of
          Success _ -> assertFailure "invalid plan unexpectedly resolved"
          Failure errors -> do
            let allErrors = NonEmpty.toList errors
            length allErrors @?= 12
            assertBool
              "unsupported raw-plan version reported"
              (UnsupportedRunPlanVersion 0 `elem` allErrors)
            assertBool "all empty identifiers reported" (length (filter isEmptyField allErrors) == 4)
            assertBool "all zero quantities reported" (length (filter isNonPositive allErrors) == 5)
            assertBool "empty seed cohort reported" (EmptySeedCohort `elem` allErrors)
            assertBool
              "placement mismatch reported"
              (InvalidRunPlacement LinuxCPU HostRun `elem` allErrors)
    , testCase "positive quantities reject non-positive and out-of-range values" $ do
        traverse_
          ( \invalid ->
              case (mkQuantity "epochs" invalid :: Validation (NonEmpty.NonEmpty PlanError) (Quantity 'Epoch)) of
                Failure (NonPositiveQuantity "epochs" NonEmpty.:| []) -> pure ()
                other -> assertFailure ("unexpected non-positive quantity result: " <> show other)
          )
          [0, -1]
        let tooLarge = toInteger (maxBound :: Word64) + 1
        case (mkQuantity "epochs" tooLarge :: Validation (NonEmpty.NonEmpty PlanError) (Quantity 'Epoch)) of
          Failure (QuantityOutOfRange "epochs" value NonEmpty.:| []) -> value @?= tooLarge
          other -> assertFailure ("unexpected out-of-range quantity result: " <> show other)
        case (mkQuantity "epochs" 3 :: Validation (NonEmpty.NonEmpty PlanError) (Quantity 'Epoch)) of
          Success quantity -> quantityValue quantity @?= 3
          Failure errors -> assertFailure (show errors)
    , testCase "finite measurements reject NaN and infinities" $ do
        traverse_ assertNonFinite [0 / 0, 1 / 0, -(1 / 0)]
        case mkFiniteMeasurement "loss" 0.25 of
          Success measurement -> finiteMeasurementValue measurement @?= 0.25
          Failure errors -> assertFailure (show errors)
    , testCase "seed cohorts reject duplicates and canonicalize order" $ do
        case resolveRun (validSupervised [3, 3]) of
          Failure (DuplicateSeed 3 NonEmpty.:| []) -> pure ()
          other -> assertFailure ("unexpected duplicate-seed result: " <> show other)
        left <- expectResolved (validSupervised [9, 2, 5])
        right <- expectResolved (validSupervised [5, 9, 2])
        seedCohortValues (runPlanSeeds left) @?= (2 NonEmpty.:| [5, 9])
        runPlanId left @?= runPlanId right
    , testCase "resolved plans normalize identifiers and derive stable content ids" $ do
        left <- expectResolved (validSupervised [7])
        right <-
          expectResolved
            ( (validSupervised [7])
                { rawRunExperimentId = "  exp-8-16 "
                , rawRunSubjectId = " mnist "
                }
            )
        planIdText (runPlanId left) @?= planIdText (runPlanId right)
        Text.length (planIdText (runPlanId left)) @?= 64
    , testCase "every semantically relevant budget change changes PlanId" $ do
        baseline <- expectResolved (validSupervised [7])
        let changedBudgets =
              [ RawSupervisedBudget 3 32 4 8 12
              , RawSupervisedBudget 2 33 4 8 10
              , RawSupervisedBudget 2 32 5 8 8
              , RawSupervisedBudget 2 32 4 9 8
              ]
        changed <-
          traverse
            (\budget -> expectResolved ((validSupervised [7]) {rawRunBudget = budget}))
            changedBudgets
        traverse_
          (\plan -> assertBool "changed plan id" (runPlanId plan /= runPlanId baseline))
          changed
        case resolveRun ((validSupervised [7]) {rawRunBudget = RawSupervisedBudget 2 32 4 8 9}) of
          Failure (DerivedQuantityMismatch "optimizer-updates" 8 9 NonEmpty.:| []) -> pure ()
          other -> assertFailure ("unexpected derived-update result: " <> show other)
    , testCase "identity, placement, and seed changes each change PlanId" $ do
        baseline <- expectResolved (validSupervised [7])
        changed <-
          traverse
            expectResolved
            [ (validSupervised [7]) {rawRunExperimentId = "other-experiment"}
            , (validSupervised [7]) {rawRunSubjectId = "fashion-mnist"}
            , (validSupervised [7]) {rawRunArtifactId = "artifact-b"}
            , (validSupervised [7]) {rawRunTopicId = "training.command.other"}
            , validSupervised [8]
            , (validSupervised [7]) {rawRunSubstrate = AppleSilicon, rawRunPlacement = HostRun}
            ]
        traverse_
          (\plan -> assertBool "changed plan id" (runPlanId plan /= runPlanId baseline))
          changed
    , testCase "direct in-process placement is valid on every substrate" $
        traverse_
          ( \substrate ->
              void
                ( expectResolved
                    ( (validSupervised [7])
                        { rawRunSubstrate = substrate
                        , rawRunPlacement = InProcessRun
                        }
                    )
                )
          )
          [AppleSilicon, LinuxCPU, LinuxCUDA]
    , testCase "SL and RL budgets retain distinct unit labels" $ do
        supervised <- expectResolved (validSupervised [7])
        reinforcement <- expectResolved validRl
        runPlanBudgetSummary supervised
          @?= [ ("epochs", 2)
              , ("training-examples", 32)
              , ("evaluation-examples", 4)
              , ("batch-examples", 8)
              , ("optimizer-updates", 8)
              ]
        runPlanBudgetSummary reinforcement
          @?= [ ("environment-transitions", 4096)
              , ("rollout-ticks-per-environment", 128)
              , ("vector-environments", 8)
              , ("episode-steps", 500)
              , ("evaluation-episodes", 20)
              ]
    , testCase "RL vector-environment width is positive and participates in PlanId" $ do
        baseline <- expectResolved validRl
        widened <-
          expectResolved
            (validRl {rawRunBudget = RawRlBudget 4096 128 9 500 20})
        assertBool
          "vector-environment width changes semantic identity"
          (runPlanId widened /= runPlanId baseline)
        case resolveRun (validRl {rawRunBudget = RawRlBudget 4096 128 0 500 20}) of
          Failure (NonPositiveQuantity "vector-environments" NonEmpty.:| []) -> pure ()
          other -> assertFailure ("unexpected vector-environment refinement: " <> show other)
    , testCase "tuning trials and self-play generations have distinct positive units" $ do
        trial <-
          expectQuantity
            (mkQuantity "trials" 12 :: Validation (NonEmpty.NonEmpty PlanError) (Quantity 'Trial))
        generation <-
          expectQuantity
            (mkQuantity "generations" 7 :: Validation (NonEmpty.NonEmpty PlanError) (Quantity 'Generation))
        quantityValue trial @?= 12
        quantityValue generation @?= 7
    , testCase "semantic EventId depends independently on plan, kind, and key" $ do
        firstPlan <- expectResolved (validSupervised [7])
        secondPlan <- expectResolved ((validSupervised [7]) {rawRunArtifactId = "artifact-b"})
        first <- expectEventId (deriveEventId firstPlan "EpochDone" "epoch-1")
        same <- expectEventId (deriveEventId firstPlan " EpochDone " " epoch-1 ")
        otherPlan <- expectEventId (deriveEventId secondPlan "EpochDone" "epoch-1")
        otherKind <- expectEventId (deriveEventId firstPlan "CheckpointDone" "epoch-1")
        otherKey <- expectEventId (deriveEventId firstPlan "EpochDone" "epoch-2")
        first @?= same
        assertBool "plan changes EventId" (first /= otherPlan)
        assertBool "kind changes EventId" (first /= otherKind)
        assertBool "logical key changes EventId" (first /= otherKey)
        Text.length (eventIdText first) @?= 64
    , testCase "semantic EventId accumulates empty kind and logical-key errors" $ do
        plan <- expectResolved (validSupervised [7])
        deriveEventId plan " " "\t"
          @?= Failure (EmptyEventKind NonEmpty.:| [EmptyEventLogicalKey])
    ]

validSupervised :: [Word64] -> RawRunRequest 'SupervisedTraining
validSupervised seeds =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = SupervisedTrainingWitness
    , rawRunExperimentId = "exp-8-16"
    , rawRunSubjectId = "mnist"
    , rawRunArtifactId = "artifact-a"
    , rawRunTopicId = "training.command.linux-cpu"
    , rawRunSubstrate = LinuxCPU
    , rawRunPlacement = ClusterRun
    , rawRunSeeds = seeds
    , rawRunBudget = RawSupervisedBudget 2 32 4 8 8
    }

validRl :: RawRunRequest 'ReinforcementLearning
validRl =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = ReinforcementLearningWitness
    , rawRunExperimentId = "rl-exp-8-16"
    , rawRunSubjectId = "ppo/cartpole"
    , rawRunArtifactId = "rl-artifact"
    , rawRunTopicId = "rl.command.linux-cpu"
    , rawRunSubstrate = LinuxCPU
    , rawRunPlacement = ClusterRun
    , rawRunSeeds = [11, 13]
    , rawRunBudget = RawRlBudget 4096 128 8 500 20
    }

expectResolved
  :: RawRunRequest kind
  -> IO (RunPlan kind)
expectResolved raw =
  case resolveRun raw of
    Failure errors -> assertFailure (show errors) >> fail "unreachable"
    Success plan -> pure plan

expectEventId
  :: Validation (NonEmpty.NonEmpty PlanError) EventId
  -> IO EventId
expectEventId result =
  case result of
    Failure errors -> assertFailure (show errors) >> fail "unreachable"
    Success eventId -> pure eventId

expectQuantity
  :: Validation (NonEmpty.NonEmpty PlanError) (Quantity unit)
  -> IO (Quantity unit)
expectQuantity result =
  case result of
    Failure errors -> assertFailure (show errors) >> fail "unreachable"
    Success quantity -> pure quantity

assertNonFinite :: Double -> IO ()
assertNonFinite value =
  case mkFiniteMeasurement "metric" value of
    Failure (NonFiniteMeasurement "metric" NonEmpty.:| []) -> pure ()
    other -> assertFailure ("unexpected finite-measurement result: " <> show other)

isEmptyField :: PlanError -> Bool
isEmptyField (EmptyPlanField _) = True
isEmptyField _ = False

isNonPositive :: PlanError -> Bool
isNonPositive (NonPositiveQuantity _) = True
isNonPositive _ = False

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 280 — the completed-checkpoint budget binding of the live reducers.
--
-- The supervised and RL live reducers used to compare only the 'PlanId' a
-- completed checkpoint claims, so a completion of a smaller (or larger)
-- self-consistent budget stamped with the true plan identity joined a
-- terminal epoch snapshot and completed the run.  These tests build realistic
-- events with the same constructors the workers use and pin the fix: the
-- completed checkpoint's own budget must be denominated in the plan's unit and
-- carry exactly the plan's total, and each positive case proves the rejection
-- cases below it are rejected for the budget and not for something else.
module JitML.Test.LiveEvidenceBudget
  ( liveEvidenceBudgetTests
  )
where

import Control.Monad (foldM)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Run.Contract
  ( MissingEvidence (..)
  , finishContract
  , initialProgress
  )
import JitML.Test.ContractFixtures
  ( expectRight
  , planA
  , rlCompletedCheckpointEvent
  , supervisedCompletedCheckpointEvent
  , supervisedEpochEvent
  )
import JitML.Test.ControlFixtures
  ( rlCompletedCheckpointFor
  , rlEvaluationEvent
  , rlMetricEvent
  , supervisedCompletedCheckpointFor
  )
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Training.Budget qualified as TrainingBudget

liveEvidenceBudgetTests :: TestTree
liveEvidenceBudgetTests =
  testGroup
    "live evidence binds the completed checkpoint budget to the plan"
    [ testCase "supervised evidence completes when the checkpoint carries exactly the planned epochs" $ do
        evidence <- supervisedOutcome 3 (supervisedCompletedCheckpointEvent planA 3 supervisedExperiment)
        case evidence of
          Success completed ->
            Map.keys (LiveEvidence.supervisedTerminalEpochSnapshot completed) @?= [3]
          Failure missing -> assertFailure ("an exact-budget run stayed incomplete: " <> show missing)
    , testCase "supervised evidence rejects a checkpoint whose budget is below the planned epochs" $ do
        evidence <- supervisedOutcome 3 (supervisedCompletedCheckpointEvent planA 1 supervisedExperiment)
        evidence
          @?= Failure
            ( InvalidEvidence
                "supervised completed checkpoint budget does not match the plan: plan requires 3, completed budget targets 1 with 1 observed"
                :| []
            )
    , testCase "supervised evidence rejects a checkpoint whose budget is above the planned epochs" $ do
        evidence <- supervisedOutcome 3 (supervisedCompletedCheckpointEvent planA 5 supervisedExperiment)
        evidence
          @?= Failure
            ( InvalidEvidence
                "supervised completed checkpoint budget does not match the plan: plan requires 3, completed budget targets 5 with 5 observed"
                :| []
            )
    , testCase "supervised evidence rejects a checkpoint denominated in another unit" $ do
        wrongUnit <-
          expectRight
            ( supervisedCompletedCheckpointFor
                planA
                TrainingBudget.RlEnvironmentStepBudget
                3
                supervisedExperiment
            )
        evidence <- supervisedOutcome 3 wrongUnit
        evidence
          @?= Failure
            ( InvalidEvidence
                "supervised completed checkpoint budget kind mismatch: plan supervised-epochs, completed rl-environment-steps"
                :| []
            )
    , testCase "RL evidence completes when the checkpoint carries exactly the planned environment steps" $ do
        evidence <- rlOutcome (LiveEvidence.rlLiveContractForSteps planA 2 4) (rlCheckpoint 4)
        case evidence of
          Success completed ->
            Map.keys (LiveEvidence.rlCompletedEvaluationSet completed) @?= [0, 1]
          Failure missing -> assertFailure ("an exact-budget RL run stayed incomplete: " <> show missing)
    , testCase "RL evidence rejects a checkpoint of fewer environment steps than the plan schedules" $ do
        evidence <- rlOutcome (LiveEvidence.rlLiveContractForSteps planA 2 1000) (rlCheckpoint 4)
        evidence
          @?= Failure
            ( InvalidEvidence
                "RL completed checkpoint budget does not match the plan: plan requires 1000, completed budget targets 4 with 4 observed"
                :| []
            )
    , testCase "RL evidence rejects a checkpoint of more environment steps than the plan schedules" $ do
        evidence <- rlOutcome (LiveEvidence.rlLiveContractForSteps planA 2 4) (rlCheckpoint 8)
        evidence
          @?= Failure
            ( InvalidEvidence
                "RL completed checkpoint budget does not match the plan: plan requires 4, completed budget targets 8 with 8 observed"
                :| []
            )
    , testCase
        "RL evidence rejects a checkpoint denominated in another unit, with or without a step total"
        $ do
          wrongUnit <-
            expectRight
              (rlCompletedCheckpointFor planA TrainingBudget.SupervisedEpochBudget 4 rlExperiment)
          let expected =
                Failure
                  ( InvalidEvidence
                      "RL completed checkpoint budget kind mismatch: plan rl-environment-steps, completed supervised-epochs"
                      :| []
                  )
          unbounded <- rlOutcome (LiveEvidence.rlLiveContract planA 2) wrongUnit
          unbounded @?= expected
          bounded <- rlOutcome (LiveEvidence.rlLiveContractForSteps planA 2 4) wrongUnit
          bounded @?= expected
    , testCase "the step-free RL contract accepts any step total in the right unit" $ do
        evidence <- rlOutcome (LiveEvidence.rlLiveContract planA 2) (rlCheckpoint 1000)
        case evidence of
          Success _ -> pure ()
          Failure missing -> assertFailure ("a right-unit RL checkpoint stayed incomplete: " <> show missing)
    ]

supervisedExperiment :: Text
supervisedExperiment = "live-evidence-budget-supervised"

rlExperiment :: Text
rlExperiment = "live-evidence-budget-rl"

-- | Run a supervised stream (the terminal epoch of a plan of @epochs@ epochs,
-- then the given completed checkpoint) and return the completion verdict.
supervisedOutcome
  :: Word64
  -> Training.TrainingEvent
  -> IO (Validation (NonEmpty MissingEvidence) LiveEvidence.SupervisedLiveEvidence)
supervisedOutcome epochs checkpoint = do
  contract <- expectRight (LiveEvidence.supervisedLiveContract planA (fromIntegral epochs))
  progress <-
    expectRight
      ( foldM
          (LiveEvidence.ingestSupervisedLiveEvent planA supervisedExperiment contract)
          (initialProgress contract)
          [supervisedEpochEvent supervisedExperiment (fromIntegral epochs) 0.25, checkpoint]
      )
  pure (finishContract contract progress)

-- | A completed RL checkpoint of @steps@ environment steps for 'planA'.
rlCheckpoint :: Word64 -> Rl.RlEvent
rlCheckpoint steps = rlCompletedCheckpointEvent planA steps rlExperiment

-- | Run a two-episode RL stream (median 1.5) ending in the given completed
-- checkpoint against the contract and return the completion verdict.
rlOutcome
  :: Either LiveEvidence.LiveEvidenceViolation LiveEvidence.RlLiveContract
  -> Rl.RlEvent
  -> IO (Validation (NonEmpty MissingEvidence) LiveEvidence.RlLiveEvidence)
rlOutcome built checkpoint = do
  contract <- expectRight built
  progress <-
    expectRight
      ( foldM
          (LiveEvidence.ingestRlLiveEvent planA rlExperiment contract)
          (initialProgress contract)
          [ rlEvaluationEvent (planIdText planA) rlExperiment 0 1.0 4
          , rlEvaluationEvent (planIdText planA) rlExperiment 1 2.0 4
          , rlMetricEvent (planIdText planA) rlExperiment 1.5
          , checkpoint
          ]
      )
  pure (finishContract contract progress)

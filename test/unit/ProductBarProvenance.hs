{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 278 unit coverage for the external-bar predicates over real data.
--
-- * The retained CUDA lane journal is the regression net for the observation
--   gate: it is admitted through the production journal reader, and every one
--   of its 55 rows' completed observations must pass the gate against that
--   row's own bar. The gate may therefore only ever get stricter about
--   duplicated or substituted observations, never about a genuine run.
-- * The bar cross-check rebuilds every ProductRow bar from the canonical
--   threshold tables without calling the code that builds it, so an edit to a
--   registry constant that is not an edit to the table it claims to read fails.
module ProductBarProvenance (productBarProvenanceTests) where

import Codec.CBOR.Encoding qualified as CborEncoding
import Codec.CBOR.Write qualified as CborWrite
import Codec.Serialise (encode)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (for_)
import Data.List (find, nub, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertEqual
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Plan.Plan (Validation (..), planIdText, refinePlanIdText)
import JitML.Product.Convergence (ConvergenceBar (..))
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as Product
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.SL.ConvergenceThresholds qualified as SLConvergence
import JitML.Substrate (Substrate (..))
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Training.Budget (MetricGoal (..))
import JitML.Training.Budget qualified as Budget

import SupervisedCheckpointV2 (Fixture (..), expectRight, makeFixture)

productBarProvenanceTests :: TestTree
productBarProvenanceTests =
  testGroup
    "External bar provenance (Phase 278)"
    [ retainedCudaJournalTests
    , observationGateTests
    , completionGateTests
    , genericRlCompletionTests
    , barCrossCheckTests
    ]

-- ---------------------------------------------------------------------------
-- The retained CUDA journal as a regression net

-- | The retained CUDA journal, admitted through the production reader against
-- the current linux-cuda projection. Path and pin come from the aggregation's
-- own registry, so a re-issued journal is followed rather than contradicted.
admittedCudaRows :: IO [Lane.ProductLaneJournalRow]
admittedCudaRows = admittedLaneRows LinuxCUDA

admittedLaneRows :: Substrate -> IO [Lane.ProductLaneJournalRow]
admittedLaneRows substrate = do
  input <-
    maybe
      ( assertFailure ("the aggregation registers no " <> show substrate <> " journal")
          >> fail "unreachable"
      )
      pure
      (find ((== substrate) . Aggregate.productLaneInputSubstrate) Aggregate.productLaneInputs)
  bytes <- ByteString.readFile (Aggregate.productLaneInputPath input)
  batch <-
    case Product.projectProductRows substrate Product.allProductRows of
      Failure errors -> assertFailure (show errors) >> fail "unreachable"
      Success projected -> pure projected
  case Lane.admitProductLaneJournal (Aggregate.productLaneInputSha256 input) batch bytes of
    Left errors -> assertFailure (show errors) >> fail "unreachable"
    Right admitted -> pure (Lane.admittedProductLaneJournalRows admitted)

rowNamed :: Text -> IO (Product.ProductRow 'Product.Declared)
rowNamed name =
  maybe
    (assertFailure ("missing ProductRow " <> Text.unpack name) >> fail "unreachable")
    pure
    (find ((== name) . Product.rowId) Product.allProductRows)

retainedCudaJournalTests :: TestTree
retainedCudaJournalTests =
  testGroup
    "retained linux-cuda journal (pinned, admitted through the production reader)"
    [ testCase "all 55 rows are admitted in product order" $ do
        rows <- admittedCudaRows
        fmap Lane.productLaneJournalRowRowId rows @?= Product.productRowIds
        length rows @?= 55
    , testCase "every row's completed observations pass the gate against that row's own bar" $ do
        rows <- admittedCudaRows
        for_ rows $ \laneRow -> do
          row <- rowNamed (Lane.productLaneJournalRowRowId laneRow)
          let observations =
                Budget.completedTrainingMetrics (Lane.productLaneJournalRowCompletedTraining laneRow)
          assertEqual
            (Text.unpack (Product.rowId row) <> ": gate failures")
            []
            (ExternalBars.assertConvergenceObservationsAgainstBar (Product.convergenceBar row) observations)
    , testCase "every row carries exactly one observation of its bar's metric, and it passed" $ do
        rows <- admittedCudaRows
        for_ rows $ \laneRow -> do
          row <- rowNamed (Lane.productLaneJournalRowRowId laneRow)
          let metric = convergenceMetricName (Product.convergenceBar row)
              observations =
                Budget.completedTrainingMetrics (Lane.productLaneJournalRowCompletedTraining laneRow)
              barObservations = filter ((== metric) . Budget.coMetricName) observations
          assertEqual
            (Text.unpack (Product.rowId row) <> ": observations of " <> Text.unpack metric)
            1
            (length barObservations)
          assertBool
            (Text.unpack (Product.rowId row) <> ": the bar observation passed")
            (all Budget.convergencePassed barObservations)
    , testCase "duplicating a real row's observation is rejected for every one of the 55 rows" $ do
        rows <- admittedCudaRows
        for_ rows $ \laneRow -> do
          row <- rowNamed (Lane.productLaneJournalRowRowId laneRow)
          let bar = Product.convergenceBar row
              metric = convergenceMetricName bar
              observations =
                Budget.completedTrainingMetrics (Lane.productLaneJournalRowCompletedTraining laneRow)
          assertMentions
            (Text.unpack (Product.rowId row))
            ("exactly one observation of " <> metric <> ", found 2")
            (gate bar (observations <> filter ((== metric) . Budget.coMetricName) observations))
    ]

-- ---------------------------------------------------------------------------
-- The observation gate on constructed observations

-- | A passing observation of the row's own metric, evaluated against its own
-- goal and threshold.
observationAt :: ConvergenceBar -> Double -> IO Budget.ConvergenceObservation
observationAt bar value =
  either
    (\err -> assertFailure (Text.unpack err) >> fail "unreachable")
    pure
    ( Budget.measureCriterion
        (convergenceMetricName bar)
        (convergenceMetricGoal bar)
        (convergenceThreshold bar)
        value
    )

gate :: ConvergenceBar -> [Budget.ConvergenceObservation] -> [Text]
gate = ExternalBars.assertConvergenceObservationsAgainstBar

anyContains :: Text -> [Text] -> Bool
anyContains needle = any (needle `Text.isInfixOf`)

assertMentions :: String -> Text -> [Text] -> Assertion
assertMentions label needle failures =
  assertBool
    (label <> ": expected a failure containing " <> show needle <> ", got " <> show failures)
    (anyContains needle failures)

-- | 'ExternalBars.assertConvergenceObservationsAgainstBar' re-derives the value
-- the bar is evaluated with from the observations themselves, resolving a
-- metric by its first match. A second observation of the same metric would then
-- pass unchecked, so exactly one observation of the bar's metric is required
-- and every observation must carry the value the bar was evaluated with.
observationGateTests :: TestTree
observationGateTests =
  testGroup
    "observation gate"
    [ testCase "exactly one passing observation of the bar's metric is accepted" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        observation <- observationAt bar 0.95
        gate bar [observation] @?= []
    , testCase "observations of other metrics do not disturb the bar's own" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        observation <- observationAt bar 0.95
        other <-
          either
            (\err -> assertFailure (Text.unpack err) >> fail "unreachable")
            pure
            (Budget.measureCriterion "train_loss" MetricMinimise 2.0 0.1)
        gate bar [other, observation] @?= []
        gate bar [observation, other] @?= []
    , testCase "a missing observation of the bar's metric is rejected" $ do
        row <- rowNamed "mnist-shallow-mlp"
        other <-
          either
            (\err -> assertFailure (Text.unpack err) >> fail "unreachable")
            pure
            (Budget.measureCriterion "train_loss" MetricMinimise 2.0 0.1)
        gate (Product.convergenceBar row) [other] @?= ["missing convergence metric: test_accuracy"]
        gate (Product.convergenceBar row) [] @?= ["missing convergence metric: test_accuracy"]
    , testCase "an identical duplicate observation is rejected" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        observation <- observationAt bar 0.95
        gate bar [observation, observation]
          @?= ["convergence observations must contain exactly one observation of test_accuracy, found 2"]
    , testCase "a duplicate carrying a different passing value is rejected for both reasons" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        first <- observationAt bar 0.95
        second <- observationAt bar 0.99
        for_ [[first, second], [second, first]] $ \observations -> do
          let failures = gate bar observations
          assertMentions "duplicate" "exactly one observation of test_accuracy, found 2" failures
          assertMentions "value" "carries value" failures
          assertMentions "value" "not the value the product-row bar was evaluated with" failures
    , testCase "the value failure names both the stored value and the evaluated value" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        first <- observationAt bar 0.95
        second <- observationAt bar 0.99
        -- The bar is evaluated with the first observation's value, so the
        -- second is the one carrying a value the bar was not evaluated with.
        assertMentions
          "value"
          "carries value 0.99, not the value the product-row bar was evaluated with (0.95)"
          (gate bar [first, second])
    , testCase "a duplicate that would fail the bar is still rejected" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        passing <- observationAt bar 0.95
        failing <- observationAt bar 0.10
        let failures = gate bar [passing, failing]
        assertMentions "duplicate" "found 2" failures
        assertMentions "verdict" "does not match the product-row external bar" failures
    , testCase "a single observation with a substituted threshold is still rejected" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
        loosened <-
          either
            (\err -> assertFailure (Text.unpack err) >> fail "unreachable")
            pure
            ( Budget.measureCriterion
                (convergenceMetricName bar)
                (convergenceMetricGoal bar)
                (convergenceThreshold bar - 0.5)
                0.95
            )
        gate bar [loosened]
          @?= ["stored convergence observation for test_accuracy does not match the product-row external bar"]
    , testCase "a single observation with the opposite goal is rejected on the goal alone" $ do
        row <- rowNamed "mnist-shallow-mlp"
        let bar = Product.convergenceBar row
            opposite =
              case convergenceMetricGoal bar of
                MetricMaximise -> MetricMinimise
                MetricMinimise -> MetricMaximise
        -- Measured at the bar's own threshold, an at-most criterion passes just
        -- as the row's at-least criterion does, and it carries the same
        -- threshold and value: the goal is the only field that differs.
        flipped <-
          either
            (\err -> assertFailure (Text.unpack err) >> fail "unreachable")
            pure
            ( Budget.measureCriterion
                (convergenceMetricName bar)
                opposite
                (convergenceThreshold bar)
                (convergenceThreshold bar)
            )
        assertBool "the flipped observation passes its own criterion" (Budget.convergencePassed flipped)
        gate bar [flipped]
          @?= ["stored convergence observation for test_accuracy does not match the product-row external bar"]
    ]

-- ---------------------------------------------------------------------------
-- The gate at the checkpoint boundary

-- | The observation gate is not only a predicate: 'Checkpoint.validateCheckpointCompletion'
-- calls it for every checkpoint Store admits. A genuine supervised completion
-- passes, and the same completion with the row's observation repeated is
-- rejected as an external-bar mismatch before any served-byte check runs.
completionGateTests :: TestTree
completionGateTests =
  testGroup
    "checkpoint completion validation"
    [ testCase
        "a genuine completion is accepted and its repeated observation is a mismatch"
        repeatedObservationIsRejectedAtCompletion
    ]

repeatedObservationIsRejectedAtCompletion :: Assertion
repeatedObservationIsRejectedAtCompletion = do
  fixture <- expectRight =<< makeFixture
  let manifest = fixtureManifest fixture
  completed <-
    maybe
      (assertFailure "the fixture manifest carries no completed training" >> fail "unreachable")
      pure
      (Checkpoint.manifestCompletedTraining manifest)
  case Checkpoint.validateCheckpointCompletion manifest of
    Right _ -> pure ()
    Left err -> assertFailure ("the control completion was rejected: " <> show err)
  let raw = Budget.completedTrainingToRaw completed
      measurements = Budget.rawCompletedTrainingMeasurements raw
      duplicated = raw {Budget.rawCompletedTrainingMeasurements = measurements <> take 1 measurements}
  refined <-
    either
      (\err -> assertFailure (Text.unpack err) >> fail "unreachable")
      pure
      (Budget.refineCompletedTraining duplicated)
  case Checkpoint.validateCheckpointCompletion (Checkpoint.attachCompletedTraining refined manifest) of
    Left (Checkpoint.CompletedTrainingExternalBarMismatch errors) ->
      errors
        @?= ["convergence observations must contain exactly one observation of test_accuracy, found 2"]
    Left err -> assertFailure ("expected an external-bar mismatch, got " <> show err)
    Right _ -> assertFailure "the duplicated completion was accepted"

-- ---------------------------------------------------------------------------
-- Generic RL admission requires the exact compiled algorithm/environment plan.

genericRlCompletionTests :: TestTree
genericRlCompletionTests =
  testGroup
    "generic RL checkpoint cohort identity"
    [ testCase "PPO/cartpole with its own reward criterion is admitted" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward]
        Budget.completedTrainingRlPlan completed @?= Just plan
        assertCompletionAccepted completed
    , testCase "a passing reward without compiled cohort identity is rejected" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- unboundRlCompletion plan [reward]
        assertCompletionRejected completed
    , testCase "either RL policy family claim rejects a completion with a non-RL budget" $ do
        planId <- expectRight (refinePlanIdText (Text.replicate 64 "a"))
        budget <- expectRight (Budget.mkTrainingBudget Budget.TuningTrialBudget 3 Nothing)
        evidence <-
          expectRight (Evidence.mkTrainingEvidence "initial-weights" "trained-weights" 3 "dataset-at-read")
        loss <- expectRight (ExternalBars.convergenceObservationForMetric ("train_loss", 0.1))
        ExternalBars.assertConvergenceObservationsExternal [loss] @?= []
        completed <-
          expectRight
            ( Budget.completedTraining
                planId
                budget
                3
                evidence
                [loss]
                (Budget.TensorBoardRunMetadata "generic-tuning" "tensorboard/generic-tuning" ["train_loss"])
            )
        let manifest = genericRlManifest completed
            architecture = Checkpoint.manifestArchitecture manifest
        assertManifestAccepted manifest
        for_
          [ manifest {Checkpoint.manifestModelFamily = Checkpoint.ReinforcementLearningPolicyFamily}
          , manifest
              { Checkpoint.manifestArchitecture =
                  architecture {Checkpoint.architectureModelFamily = Checkpoint.ReinforcementLearningPolicyFamily}
              }
          ]
          assertManifestRejected
    , testCase "a canonical RL namespace cannot admit a generic-family completion with a tuning budget" $ do
        planId <- expectRight (refinePlanIdText (Text.replicate 64 "a"))
        budget <- expectRight (Budget.mkTrainingBudget Budget.TuningTrialBudget 3 Nothing)
        evidence <-
          expectRight (Evidence.mkTrainingEvidence "initial-weights" "trained-weights" 3 "dataset-at-read")
        borrowed <- measure "median_final_reward" MetricMaximise 435 440
        completed <-
          expectRight
            ( Budget.completedTraining
                planId
                budget
                3
                evidence
                [borrowed]
                (Budget.TensorBoardRunMetadata "generic-tuning" "tensorboard/generic-tuning" ["median_final_reward"])
            )
        a2c <- rowNamed "A2C/cartpole"
        gate (Product.convergenceBar a2c) [borrowed] @?= []
        let manifest =
              (genericRlManifest completed)
                { Checkpoint.manifestExperiment = Product.productRowExperimentHash a2c
                }
        Checkpoint.manifestModelFamily manifest @?= Checkpoint.GenericModelFamily
        Checkpoint.architectureModelFamily (Checkpoint.manifestArchitecture manifest)
          @?= Checkpoint.GenericModelFamily
        Budget.completedTrainingRlPlan completed @?= Nothing
        assertManifestRejected manifest
    , testCase "PPO cannot borrow A2C/cartpole's easier 435 reward threshold" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        borrowed <- measure "median_final_reward" MetricMaximise 435 440
        assertBool "the borrowed criterion passes" (Budget.convergencePassed borrowed)
        completed <- genericRlCompletion plan [borrowed]
        assertCompletionRejected completed
    , testCase "a bound PPO plan cannot borrow A2C's bar by changing the experiment namespace" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        borrowed <- measure "median_final_reward" MetricMaximise 435 440
        completed <- genericRlCompletion plan [borrowed]
        a2c <- rowNamed "A2C/cartpole"
        gate (Product.convergenceBar a2c) [borrowed] @?= []
        assertManifestRejected
          ( (genericRlManifest completed)
              { Checkpoint.manifestExperiment = Product.productRowExperimentHash a2c
              }
          )
    , testCase "a bound PPO completion passing its own bar still cannot claim A2C's canonical identity" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        ExternalBars.assertRlConvergenceObservationsExternal plan [reward] @?= []
        completed <- genericRlCompletion plan [reward]
        a2c <- rowNamed "A2C/cartpole"
        assertManifestRejected
          ( (genericRlManifest completed)
              { Checkpoint.manifestExperiment = Product.productRowExperimentHash a2c
              }
          )
    , testCase "an RL completion cannot claim a canonical tuning identity through either metric dispatch" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        tuning <- rowNamed "hyperparameter-tuning"
        objective <- expectRight (ExternalBars.convergenceObservationForMetric ("best_objective", 1))
        gate (Product.convergenceBar tuning) [objective] @?= []
        unbound <- unboundRlCompletion plan [objective]
        reward <- measure "median_final_reward" MetricMaximise 450 475
        ExternalBars.assertRlConvergenceObservationsExternal plan [reward] @?= []
        bound <- genericRlCompletion plan [reward]
        for_ [unbound, bound] $ \completed ->
          assertManifestRejected
            ( (genericRlManifest completed)
                { Checkpoint.manifestExperiment = Product.productRowExperimentHash tuning
                }
            )
    , testCase "an unbound generic PPO plan cannot enter A2C's canonical namespace" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        borrowed <- measure "median_final_reward" MetricMaximise 435 440
        completed <- unboundRlCompletion plan [borrowed]
        a2c <- rowNamed "A2C/cartpole"
        gate (Product.convergenceBar a2c) [borrowed] @?= []
        assertManifestRejected
          ( (genericRlManifest completed)
              { Checkpoint.manifestExperiment = Product.productRowExperimentHash a2c
              }
          )
    , testCase "a forged canonical PPO PlanId with a real device witness cannot enter A2C's namespace" $
        for_ [LinuxCPU, LinuxCUDA] $ \substrate -> do
          retained <- retainedRlCompletion substrate "PPO/cartpole"
          assertBool "the retained PPO completion has a device execution witness" $
            case Budget.completedTrainingDeviceWitness retained of
              Right (Just _) -> True
              _ -> False
          plan <- genericRlPlan "ppo" "cartpole"
          borrowed <- measure "median_final_reward" MetricMaximise 435 440
          generic <- unboundRlCompletion plan [borrowed]
          let forgedRaw =
                (Budget.completedTrainingToRaw generic)
                  { Budget.rawCompletedTrainingPlanId = planIdText (Budget.completedTrainingPlanId retained)
                  , Budget.rawCompletedTrainingEvidence = Budget.completedTrainingEvidence retained
                  }
          forged <- expectRight (Budget.refineCompletedTraining forgedRaw)
          a2c <- rowNamed "A2C/cartpole"
          gate (Product.convergenceBar a2c) (Budget.completedTrainingMetrics forged) @?= []
          assertManifestRejected
            ( (genericRlManifest forged)
                { Checkpoint.manifestExperiment = Product.productRowExperimentHash a2c
                }
            )
    , testCase "canonical CPU and CUDA RL publisher completions admit before an invocation is attached" $
        for_ [LinuxCPU, LinuxCUDA] $ \substrate -> do
          retained <- retainedRlCompletion substrate "PPO/cartpole"
          let raw = Budget.completedTrainingToRaw retained
          Budget.rawCompletedTrainingVersion raw @?= 2
          completed <-
            expectRight
              ( Budget.refineCompletedTraining
                  raw {Budget.rawCompletedTrainingProductScenarioInvocation = Nothing}
              )
          Budget.completedTrainingProductScenarioInvocation completed @?= Nothing
          Budget.completedTrainingRlPlan completed @?= Nothing
          Budget.completedTrainingDeviceWitness completed @?= Budget.completedTrainingDeviceWitness retained
          Budget.completedTrainingPlanId completed @?= Budget.completedTrainingPlanId retained
          ppo <- rowNamed "PPO/cartpole"
          assertManifestAccepted
            ( (genericRlManifest completed)
                { Checkpoint.manifestExperiment = Product.productRowExperimentHash ppo
                }
            )
    , testCase "PPO cannot borrow the lowest reward threshold from another environment" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        borrowed <- measure "median_final_reward" MetricMaximise (-380) 0
        assertBool "the borrowed criterion passes" (Budget.convergencePassed borrowed)
        completed <- genericRlCompletion plan [borrowed]
        assertCompletionRejected completed
    , testCase "a training-loss metric cannot replace the cohort reward" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        loss <- measure "train_loss" MetricMinimise 1 0.1
        assertMentions
          "missing reward"
          "exactly one observation of median_final_reward, found 0"
          (ExternalBars.assertRlConvergenceObservationsExternal plan [])
        completed <- genericRlCompletion plan [loss]
        assertCompletionRejected completed
    , testCase "identical duplicate reward observations are rejected at admission" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward, reward]
        assertCompletionRejected completed
    , testCase "a reward criterion with the opposite goal is rejected" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        flipped <- measure "median_final_reward" MetricMinimise 450 450
        assertBool "the opposite-goal criterion passes" (Budget.convergencePassed flipped)
        completed <- genericRlCompletion plan [flipped]
        assertCompletionRejected completed
    , testCase "binding rejects a different algorithm or environment PlanId" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        unbound <- unboundRlCompletion plan [reward]
        bound <- expectRight (Budget.bindCompletedTrainingToRlPlan plan unbound)
        for_ [("a2c", "cartpole"), ("ppo", "mountain-car")] $ \(algorithm, environment) -> do
          other <- genericRlPlan algorithm environment
          assertLeftResult "binding a different plan" (Budget.bindCompletedTrainingToRlPlan other unbound)
          assertLeftResult "replacing the bound plan" (Budget.bindCompletedTrainingToRlPlan other bound)
    , testCase "a forged in-memory schedule cannot preserve an otherwise valid PlanId" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        unbound <- unboundRlCompletion plan [reward]
        let forged = plan {ProductBudget.compiledRlSchedule = Nothing}
        ProductBudget.compiledRlPlanId forged @?= ProductBudget.compiledRlPlanId plan
        assertLeftResult "forged schedule" (Budget.bindCompletedTrainingToRlPlan forged unbound)
    , testCase "a bound RL completion cannot substitute a contradictory budget seed" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward]
        let raw = Budget.completedTrainingToRaw completed
            budget = Budget.rawCompletedTrainingBudget raw
        assertRawCompletionRejected
          raw
            { Budget.rawCompletedTrainingBudget =
                budget {Budget.rawTrainingBudgetSeed = Just 8}
            }
    , testCase "a completion budget without its own seed can bind the compiled plan seed" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- unboundRlCompletion plan [reward]
        let raw = Budget.completedTrainingToRaw completed
            budget = Budget.rawCompletedTrainingBudget raw
        seedless <-
          expectRight
            ( Budget.refineCompletedTraining
                raw
                  { Budget.rawCompletedTrainingBudget =
                      budget {Budget.rawTrainingBudgetSeed = Nothing}
                  }
            )
        bound <- expectRight (Budget.bindCompletedTrainingToRlPlan plan seedless)
        Budget.trainingBudgetSeed (Budget.completedTrainingBudget bound) @?= Nothing
        Budget.completedTrainingRlPlan bound @?= Just plan
        Budget.decodeCompletedTraining (Budget.encodeCompletedTraining bound) @?= Right bound
        assertCompletionAccepted bound
    , testCase "HER with both goal-success and achieved-distance criteria is admitted" $ do
        plan <- genericRlPlan "her" "goal-reaching"
        completed <- genericRlCompletion plan herObservations
        assertCompletionAccepted completed
    , testCase "HER requires each criterion exactly once" $ do
        plan <- genericRlPlan "her" "goal-reaching"
        let success = RLConvergence.hgmSuccessRate RLConvergence.herGoalMetric
            distance = RLConvergence.hgmAchievedGoalDistance RLConvergence.herGoalMetric
        for_ [[success], [distance], [success, success, distance], [success, distance, distance]] $ \observations -> do
          completed <- genericRlCompletion plan observations
          assertCompletionRejected completed
    , testCase "HER rejects an easier threshold for either of its own criteria" $ do
        plan <- genericRlPlan "her" "goal-reaching"
        easierDistance <- measure "achieved_goal_distance" MetricMinimise 0.10 0.08
        easierSuccess <- measure "goal_success_rate" MetricMaximise 0.50 0.60
        let success = RLConvergence.hgmSuccessRate RLConvergence.herGoalMetric
            distance = RLConvergence.hgmAchievedGoalDistance RLConvergence.herGoalMetric
        for_ [[success, easierDistance], [easierSuccess, distance]] $ \observations -> do
          completed <- genericRlCompletion plan observations
          assertCompletionRejected completed
    , testCase "the bound V3 completion round-trips with its cohort proof and admits" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward]
        let raw = Budget.completedTrainingToRaw completed
        Budget.rawCompletedTrainingVersion raw @?= 3
        Budget.rawCompletedTrainingRlPlan raw @?= Just (ProductBudget.renderCompiledRlPlanTransport plan)
        decoded <- expectRight (Budget.decodeCompletedTraining (Budget.encodeCompletedTraining completed))
        decoded @?= completed
        Budget.encodeCompletedTraining decoded @?= Budget.encodeCompletedTraining completed
        assertCompletionAccepted decoded
    , testCase "changing plan transport without changing its declared identity is rejected" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward]
        let raw = Budget.completedTrainingToRaw completed
            transport = ProductBudget.renderCompiledRlPlanTransport plan
            altered = Text.replace "|seed=7|" "|seed=8|" transport
        assertBool "the seed edit changed the transported plan" (altered /= transport)
        assertRawCompletionRejected raw {Budget.rawCompletedTrainingRlPlan = Just altered}
    , testCase "a valid substitute plan cannot retain the original completion PlanId" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward]
        let raw = Budget.completedTrainingToRaw completed
        for_ [("a2c", "cartpole"), ("ppo", "mountain-car")] $ \(algorithm, environment) -> do
          other <- genericRlPlan algorithm environment
          assertRawCompletionRejected
            raw {Budget.rawCompletedTrainingRlPlan = Just (ProductBudget.renderCompiledRlPlanTransport other)}
    , testCase "V3 cannot omit the plan proof and V2 cannot silently discard it" $ do
        plan <- genericRlPlan "ppo" "cartpole"
        reward <- measure "median_final_reward" MetricMaximise 450 475
        completed <- genericRlCompletion plan [reward]
        let raw = Budget.completedTrainingToRaw completed
        assertRawCompletionRejected raw {Budget.rawCompletedTrainingRlPlan = Nothing}
        assertRawCompletionRejected raw {Budget.rawCompletedTrainingVersion = 2}
    , testCase "retained CPU and CUDA completions retain their exact V2 tuple encoding" $
        for_ [LinuxCPU, LinuxCUDA] $ \substrate -> do
          rows <- admittedLaneRows substrate
          for_ rows $ \row -> do
            let completed = Lane.productLaneJournalRowCompletedTraining row
                raw = Budget.completedTrainingToRaw completed
            Budget.rawCompletedTrainingVersion raw @?= 2
            Budget.rawCompletedTrainingRlPlan raw @?= Nothing
            assertEqual
              (show substrate <> "/" <> Text.unpack (Lane.productLaneJournalRowRowId row))
              (legacyV2CompletionBytes raw)
              (Budget.encodeCompletedTraining completed)
    ]

-- No trainer runs in these boundary tests. The real plan compiler supplies an
-- executable schedule; the completion's count, seed, and PlanId all follow it.
genericRlPlan :: Text -> Text -> IO ProductBudget.CompiledRlPlan
genericRlPlan trainer environment = do
  let training =
        ProductBudget.TrainingPlan
          { ProductBudget.trainingPlanTrainerKind = trainer
          , ProductBudget.trainingPlanEnvironment = environment
          , ProductBudget.trainingPlanSeed = 7
          , ProductBudget.trainingPlanMaxEpisodeSteps = 128
          , ProductBudget.trainingPlanEpisodeBudgetFloor = 1
          , ProductBudget.trainingPlanVectorEnvironments = Just 1
          , ProductBudget.trainingPlanRequestedTransitionFloor = Nothing
          , ProductBudget.trainingPlanExactTransitionTarget = Nothing
          }
      evaluation = ProductBudget.EvaluationPlan 4
  preliminary <- expectRight (ProductBudget.compileRlPlan training evaluation)
  schedule <-
    maybe
      (assertFailure "the generic RL fixture requires a neural trainer schedule" >> fail "unreachable")
      pure
      (ProductBudget.compiledRlSchedule preliminary)
  expectRight
    ( ProductBudget.compileRlPlan
        training
          { ProductBudget.trainingPlanExactTransitionTarget =
              Just (ProductBudget.scheduleObservedEnvironmentSteps schedule)
          }
        evaluation
    )

measure :: Text -> MetricGoal -> Double -> Double -> IO Budget.ConvergenceObservation
measure metric goal threshold value = expectRight (Budget.measureCriterion metric goal threshold value)

herObservations :: [Budget.ConvergenceObservation]
herObservations =
  [ RLConvergence.hgmSuccessRate RLConvergence.herGoalMetric
  , RLConvergence.hgmAchievedGoalDistance RLConvergence.herGoalMetric
  ]

unboundRlCompletion
  :: ProductBudget.CompiledRlPlan
  -> [Budget.ConvergenceObservation]
  -> IO Budget.CompletedTraining
unboundRlCompletion plan observations = do
  planId <- expectRight (refinePlanIdText (ProductBudget.compiledRlPlanId plan))
  schedule <-
    maybe
      (assertFailure "the generic RL fixture has no schedule" >> fail "unreachable")
      pure
      (ProductBudget.compiledRlSchedule plan)
  let target = ProductBudget.scheduleObservedEnvironmentSteps schedule
  budget <- expectRight (Budget.mkTrainingBudget Budget.RlEnvironmentStepBudget target (Just 7))
  evidence <-
    expectRight
      (Evidence.mkTrainingEvidence "initial-weights" "trained-weights" 3 "environment-at-read")
  expectRight
    ( Budget.completedTraining
        planId
        budget
        target
        evidence
        observations
        ( Budget.TensorBoardRunMetadata
            "generic-rl"
            "tensorboard/generic-rl"
            (fmap Budget.coMetricName observations)
        )
    )

genericRlCompletion
  :: ProductBudget.CompiledRlPlan
  -> [Budget.ConvergenceObservation]
  -> IO Budget.CompletedTraining
genericRlCompletion plan observations =
  unboundRlCompletion plan observations >>= expectRight . Budget.bindCompletedTrainingToRlPlan plan

genericRlManifest :: Budget.CompletedTraining -> Checkpoint.CheckpointManifest
genericRlManifest completed =
  Checkpoint.attachCompletedTraining
    completed
    ( (Checkpoint.emptyManifest "generic-rl-checkpoint" "generic-rl-experiment" [])
        { Checkpoint.manifestStep = Budget.completedTrainingObservedUnits completed
        }
    )

retainedRlCompletion :: Substrate -> Text -> IO Budget.CompletedTraining
retainedRlCompletion substrate name = do
  rows <- admittedLaneRows substrate
  maybe
    ( assertFailure ("missing retained " <> show substrate <> "/" <> Text.unpack name)
        >> fail "unreachable"
    )
    (pure . Lane.productLaneJournalRowCompletedTraining)
    (find ((== name) . Lane.productLaneJournalRowRowId) rows)

assertCompletionAccepted :: Budget.CompletedTraining -> Assertion
assertCompletionAccepted = assertManifestAccepted . genericRlManifest

assertManifestAccepted :: Checkpoint.CheckpointManifest -> Assertion
assertManifestAccepted manifest =
  case Checkpoint.validateCheckpointCompletion manifest of
    Right _ -> pure ()
    Left err -> assertFailure ("the control completion was rejected: " <> show err)

assertCompletionRejected :: Budget.CompletedTraining -> Assertion
assertCompletionRejected = assertManifestRejected . genericRlManifest

assertManifestRejected :: Checkpoint.CheckpointManifest -> Assertion
assertManifestRejected manifest =
  case Checkpoint.validateCheckpointCompletion manifest of
    Left (Checkpoint.CompletedTrainingExternalBarMismatch errors) ->
      assertBool "cohort mismatch must explain the rejected criterion" (not (null errors))
    Left err -> assertFailure ("expected an external-bar mismatch, got " <> show err)
    Right _ -> assertFailure "the completion with substituted or missing cohort evidence was admitted"

assertLeftResult :: (Show value) => String -> Either Text value -> Assertion
assertLeftResult label result =
  case result of
    Left _ -> pure ()
    Right value -> assertFailure (label <> ": expected rejection, got " <> show value)

assertRawCompletionRejected :: Budget.RawCompletedTraining -> Assertion
assertRawCompletionRejected raw = do
  assertLeftResult "raw refinement" (Budget.refineCompletedTraining raw)
  assertLeftResult
    "wire refinement"
    (Budget.decodeCompletedTraining (Budget.encodeRawCompletedTraining raw))

-- Independently pin the historical CBOR shape whose bytes determine retained
-- journal completion digests. A V3-only field must not alter any V2 tuple.
legacyV2CompletionBytes :: Budget.RawCompletedTraining -> ByteString.ByteString
legacyV2CompletionBytes raw =
  LazyByteString.toStrict
    ( CborWrite.toLazyByteString
        ( CborEncoding.encodeListLen 11
            <> CborEncoding.encodeWord 0
            <> encode (2 :: Word)
            <> encode (Budget.rawCompletedTrainingPlanId raw)
            <> encode (Budget.rawCompletedTrainingBudget raw)
            <> encode (Budget.rawCompletedTrainingObservedKind raw)
            <> encode (Budget.rawCompletedTrainingObservedUnits raw)
            <> encode (Budget.rawCompletedTrainingObservedUnitLabel raw)
            <> encode (Budget.rawCompletedTrainingEvidence raw)
            <> encode (Budget.rawCompletedTrainingMeasurements raw)
            <> encode (Budget.rawCompletedTrainingTensorBoard raw)
            <> encode (Budget.rawCompletedTrainingProductScenarioInvocation raw)
        )
    )

-- ---------------------------------------------------------------------------
-- Bar cross-check

-- | The bar of one ProductRow rebuilt from the canonical threshold tables.
-- 'Product.mkConvergenceBar' and the registry's row builders are deliberately
-- not used, so this is a second derivation rather than a restatement. The
-- regression and tuning rows have no cohort table: their reference constants
-- are stated here, so changing either registry constant requires changing this
-- pin too.
expectedBar :: Product.ProductRow state -> Either String ConvergenceBar
expectedBar row =
  case Product.rowClass row of
    Product.SupervisedClassification _ _ ->
      case SLConvergence.slCohortThreshold name of
        Nothing -> Left "no SL cohort threshold"
        Just threshold ->
          Right
            ( bar
                "test_accuracy"
                MetricMaximise
                (SLConvergence.slLiteratureTarget threshold)
                (SLConvergence.slSlack threshold)
            )
    Product.SupervisedRegression _ _ ->
      Right (bar "rmse" MetricMinimise 0.90 0.10)
    Product.RlAlgorithmEnvironment algorithm environment ->
      case RLConvergence.cohortThreshold algorithm environment of
        Nothing -> Left "no RL cohort threshold"
        Just threshold ->
          Right
            ( bar
                "median_final_reward"
                MetricMaximise
                (RLConvergence.literatureTarget threshold)
                (RLConvergence.slack threshold)
            )
    Product.RlGoalConditioned _ ->
      Right
        ( bar
            "goal_success_rate"
            MetricMaximise
            (RLConvergence.literatureTarget RLConvergence.herGoalSuccessThreshold)
            (RLConvergence.slack RLConvergence.herGoalSuccessThreshold)
        )
    Product.AlphaZeroGame _ ->
      Right
        ( bar
            "arena_win_rate"
            MetricMaximise
            (RLConvergence.azTargetWinRate RLConvergence.alphaZeroArenaThreshold)
            (RLConvergence.azSlack RLConvergence.alphaZeroArenaThreshold)
        )
    Product.HyperparameterTuning _ ->
      Right (bar "best_objective" MetricMaximise 1.0 0.05)
 where
  name = Product.rowId row
  bar metric goal target slack =
    ConvergenceBar
      { convergenceMetricName = metric
      , convergenceMetricGoal = goal
      , convergenceLiteratureTarget = target
      , convergenceSlack = slack
      , convergenceThreshold =
          case goal of
            MetricMaximise -> target - slack
            MetricMinimise -> target + slack
      }

barCrossCheckTests :: TestTree
barCrossCheckTests =
  testGroup
    "ProductRow bars against the canonical tables"
    [ testCase "the registry has the 55 rows, split 11 / 39 / 4 / 1" $ do
        length Product.allProductRows @?= 55
        let count family = length (filter ((== family) . Product.family) Product.allProductRows)
        ( count Product.Supervised
          , count Product.ReinforcementLearning
          , count Product.AlphaZero
          , count Product.Tuning
          )
          @?= (11, 39, 4, 1)
    , testCase "every row's bar equals the bar rebuilt from the canonical tables" $
        for_ Product.allProductRows $ \row ->
          case expectedBar row of
            Left err -> assertFailure (Text.unpack (Product.rowId row) <> ": " <> err)
            Right expected ->
              assertEqual
                (Text.unpack (Product.rowId row) <> ": bar")
                expected
                (Product.convergenceBar row)
    , testCase "every rebuilt bar is externally anchored and internally consistent" $
        for_ Product.allProductRows $ \row ->
          case expectedBar row of
            Left err -> assertFailure (Text.unpack (Product.rowId row) <> ": " <> err)
            Right expected ->
              assertEqual
                (Text.unpack (Product.rowId row) <> ": external-bar failures")
                []
                (ExternalBars.assertProductBarExternal expected (convergenceThreshold expected))
    , testCase "every RL cohort-table entry is exactly one row, and every RL row is a table entry" $ do
        let tableRows =
              [algorithm <> "/" <> environment | ((algorithm, environment), _) <- RLConvergence.cohortThresholds]
            rlRows =
              [ Product.rowId row
              | row <- Product.allProductRows
              , isCohortRowClass (Product.rowClass row)
              ]
        length (nub tableRows) @?= length tableRows
        rlRows @?= tableRows
    , testCase
        "every SL cohort-table entry is a classification row and California is the sole regression row"
        $ do
          let classification =
                [ Product.rowId row
                | row <- Product.allProductRows
                , Product.family row == Product.Supervised
                , case Product.rowClass row of
                    Product.SupervisedClassification _ _ -> True
                    _ -> False
                ]
              regression =
                [ Product.rowId row
                | row <- Product.allProductRows
                , case Product.rowClass row of
                    Product.SupervisedRegression _ _ -> True
                    _ -> False
                ]
          -- The registry and the table order the two CIFAR rows differently; the
          -- correspondence under test is membership.
          sort classification @?= sort (fmap fst SLConvergence.slCohortThresholds)
          regression @?= ["california-housing-mlp"]
    , testCase "the projected bar of every row is the registry bar on every substrate" $
        for_ [LinuxCPU, LinuxCUDA, AppleSilicon] $ \substrate ->
          case Product.projectProductRows substrate Product.allProductRows of
            Failure errors -> assertFailure (show errors)
            Success batch ->
              assertEqual
                (show substrate <> ": projected bars")
                (fmap Product.convergenceBar Product.allProductRows)
                [ Product.productProjectionConvergenceBar projection
                | Product.SomeProductProjection _ projection <- Product.productProjectionBatchProjections batch
                ]
    , testCase "the generic per-metric bars agree with the ProductRow bars they overlap" $ do
        let overlap metric rowName = do
              row <- rowNamed rowName
              case ExternalBars.convergenceBarForMetric metric of
                Nothing -> assertFailure ("no generic bar for " <> Text.unpack metric)
                Just generic ->
                  assertEqual
                    (Text.unpack metric <> " generic bar against " <> Text.unpack rowName)
                    (Product.convergenceBar row)
                    generic
        overlap "arena_win_rate" "connect4"
        overlap "goal_success_rate" "HER/goal-reaching"
        overlap "best_objective" "hyperparameter-tuning"
        overlap "rmse" "california-housing-mlp"
    ]

isCohortRowClass :: Product.RowClass -> Bool
isCohortRowClass rowClass =
  case rowClass of
    Product.RlAlgorithmEnvironment _ _ -> True
    Product.SupervisedClassification _ _ -> False
    Product.SupervisedRegression _ _ -> False
    Product.RlGoalConditioned _ -> False
    Product.AlphaZeroGame _ -> False
    Product.HyperparameterTuning _ -> False

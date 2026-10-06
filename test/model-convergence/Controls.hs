{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-x-model-evidence-raw #-}

-- | Phase 285 — field-level mutation controls and lane-independent guards for the
-- per-model evidence layer.
--
-- The controls start from the /real/ rows of the retained @linux-cuda@ lane
-- journal (admitted through the production reader, see "ControlSupport") and
-- minimally corrupt one field at the forgeable raw boundary. Every control first
-- proves its unmutated baseline grades clean, so a control cannot pass merely
-- because its baseline was already rejected for an unrelated reason, and then
-- asserts the /specific/ typed failure constructor. The @linux-cuda@ journal is
-- the baseline whatever lane the stanza grades, so a stale lane fails only the
-- cases that depend on that lane's evidence. "WiringControls" holds the controls
-- of the per-row case wiring, the criterion boundaries, and the k > 1 cohort;
-- "GateControls" holds those of the gate's own fail-closed guards (loading a
-- lane, the criterion lookup, the receipt binding). This module also holds the
-- lane-independent guards, among them the one that asserts which modules may
-- import the raw evidence boundary and the one that pins how the stanza selects
-- its lane.
module Controls
  ( controlTests
  , independentTests
  )
where

import Control.Exception (bracket)
import Control.Monad (filterM)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import ControlSupport
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate (..))
import JitML.Test.ModelConvergence (assertRegistryCoverageOf, selectedModelConvergenceSubstrate)
import JitML.Test.ModelEvidence
import JitML.Test.ModelEvidence.Raw
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as Budget
import SourceScan
  ( importedModules
  , lexSource
  , optionsGhcFlags
  , pragmaBodies
  , readSourceUtf8
  , sourceFiles
  )

-- ---------------------------------------------------------------------------
-- Mutation controls on the retained linux-cuda journal

controlTests :: TestTree
controlTests =
  withResource loadBaseline (const (pure ())) $ \loaded ->
    testGroup
      "mutation controls (retained linux-cuda journal rows)"
      [ joinControls loaded
      , seedControls loaded
      , finalQualityControls loaded
      , separationControls loaded
      , rowAssertionsControls loaded
      , learningControls loaded
      , performanceControls loaded
      , bindingControls loaded
      ]

joinControls :: IO (Either String Baseline) -> TestTree
joinControls loaded =
  testGroup
    "typed join: Missing, Duplicate, Orphan, WrongPlan, WrongLane, StaleContract"
    [ testCase "the unmutated journal rows join into exactly one evidence value per ProductRow" $
        withBaseline loaded $ \baseline -> do
          set <- joinedSet baseline (baselineRaw baseline)
          fmap someModelEvidenceRowId (modelEvidenceSetRows set) @?= ProductMatrix.productRowIds
          modelEvidenceSetLane set @?= LinuxCUDA
    , testCase
        "the unmutated evidence grades clean for every ProductRow across all four assertion families"
        $ withBaseline loaded
        $ \baseline -> do
          set <- joinedSet baseline (baselineRaw baseline)
          let failures =
                [ someProjectionRowId projection <> ": " <> renderModelAssertionFailure failure
                | projection <- ProductMatrix.productProjectionBatchProjections (baselineBatch baseline)
                , Just evidence <- [lookupModelEvidence (someProjectionRowId projection) set]
                , failure <- assertSomeModelRowEvidence projection evidence
                ]
          failures @?= []
    , testCase "minting directly from an admitted journal row equals the joined evidence for every row" $ do
        loadedLane <- loadLaneJournal LinuxCUDA >>= either (assertFailure . show) pure
        set <- either (assertFailure . show) pure (admitLaneEvidence loadedLane)
        let admittedRows = Lane.admittedProductLaneJournalRows (loadedLaneJournal loadedLane)
        mapM_
          ( \(ProductMatrix.SomeProductProjection witness projection) -> do
              let rowId = ProductMatrix.productProjectionRowId projection
              journalRow <-
                maybe
                  (assertFailure ("journal has no row " <> Text.unpack rowId))
                  pure
                  (find ((== rowId) . Lane.productLaneJournalRowRowId) admittedRows)
              direct <-
                either
                  (assertFailure . show)
                  (pure . SomeModelRowEvidence witness)
                  (modelEvidenceFromJournalRow projection journalRow)
              lookupModelEvidence rowId (laneEvidenceSet set) @?= Just direct
          )
          (ProductMatrix.productProjectionBatchProjections (loadedLaneBatch loadedLane))
    , testCase "input order cannot alter the joined evidence" $
        withBaseline loaded $ \baseline -> do
          forward <- joinedSet baseline (baselineRaw baseline)
          backward <- joinedSet baseline (reverse (baselineRaw baseline))
          backward @?= forward
    , testCase "no evidence at all leaves every ProductRow typed as missing" $
        withBaseline loaded $ \baseline -> do
          failures <- joinRejections baseline []
          length failures @?= length ProductMatrix.productRowIds
          length [() | MissingModelEvidence {} <- failures] @?= length failures
    , testCase "a dropped row is a typed MissingModelEvidence naming its expected plan" $
        withBaseline loaded $ \baseline -> do
          projection <- projectionFor baseline "PPO/cartpole"
          failures <-
            joinRejections
              baseline
              (filter ((/= "PPO/cartpole") . rmeRowId) (baselineRaw baseline))
          failures @?= [MissingModelEvidence "PPO/cartpole" (someProjectionPlanId projection)]
    , testCase "a duplicated row is a typed DuplicateModelEvidence" $
        withBaseline loaded $ \baseline -> do
          raw <- rawRow baseline "PPO/cartpole"
          failures <- joinRejections baseline (baselineRaw baseline <> [raw])
          failures @?= [DuplicateModelEvidence "PPO/cartpole"]
    , testCase "a row that is not a projected ProductRow is an orphan and leaves its slot missing" $
        withBaseline loaded $ \baseline -> do
          projection <- projectionFor baseline "PPO/cartpole"
          raw <- rawRow baseline "PPO/cartpole"
          failures <-
            joinRejections
              baseline
              (mutateRow "PPO/cartpole" (\row -> row {rmeRowId = "not-a-product-row"}) (baselineRaw baseline))
          failures
            @?= [ MissingModelEvidence "PPO/cartpole" (someProjectionPlanId projection)
                , OrphanModelEvidence "not-a-product-row" (rmePlanId raw)
                ]
    , testCase "another row's PlanId is a typed cross-plan WrongPlanModelEvidence" $
        withBaseline loaded $ \baseline -> do
          expected <- someProjectionPlanId <$> projectionFor baseline "PPO/cartpole"
          other <- rmePlanId <$> rawRow baseline "A2C/cartpole"
          failures <-
            joinRejections
              baseline
              (mutateRow "PPO/cartpole" (\row -> row {rmePlanId = other}) (baselineRaw baseline))
          failures @?= [WrongPlanModelEvidence "PPO/cartpole" expected other]
    , testCase "evidence claiming another lane is a typed WrongLaneModelEvidence" $
        withBaseline loaded $ \baseline -> do
          failures <-
            joinRejections
              baseline
              (mutateRow "PPO/cartpole" (\row -> row {rmeLane = LinuxCPU}) (baselineRaw baseline))
          failures @?= [WrongLaneModelEvidence "PPO/cartpole" LinuxCUDA LinuxCPU]
    , testCase "another row's contract digest is a typed StaleContractModelEvidence" $
        withBaseline loaded $ \baseline -> do
          other <- rmeContractDigest <$> rawRow baseline "A2C/cartpole"
          failures <-
            joinRejections
              baseline
              (mutateRow "PPO/cartpole" (\row -> row {rmeContractDigest = other}) (baselineRaw baseline))
          failures @?= [StaleContractModelEvidence "PPO/cartpole"]
    , testCase "linux-cuda evidence offered for the linux-cpu projection is rejected row by row" $
        withBaseline loaded $ \baseline ->
          case ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows of
            Plan.Failure errors ->
              assertFailure ("linux-cpu projection failed: " <> show errors)
            Plan.Success cpuBatch ->
              case joinModelEvidence cpuBatch (baselineRaw baseline) of
                Right _ -> assertFailure "cross-lane evidence was admitted"
                Left errors -> do
                  let failures = NonEmpty.toList errors
                      rows = length ProductMatrix.productRowIds
                  length [() | WrongLaneModelEvidence {} <- failures] @?= rows
                  length [() | WrongPlanModelEvidence {} <- failures] @?= rows
    ]

seedControls :: IO (Either String Baseline) -> TestTree
seedControls loaded =
  testGroup
    "seed cohort coverage against runPlanSeeds"
    [ testCase "a row with no seed evidence is an empty cohort with the planned seed missing" $
        withBaseline loaded $ \baseline -> do
          failures <- rowRejection baseline "PPO/cartpole" (\row -> row {rmeSeeds = []})
          failures
            @?= [ RowBindingRejected (BindingSeedCohort EmptySeedCohort)
                , RowBindingRejected (BindingSeedCohort (MissingSeedEvidence 42))
                ]
    , testCase "evidence for a seed the plan never declared leaves the planned seed missing" $
        withBaseline loaded $ \baseline -> do
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (mutateSeeds (\seed -> seed {rseSeed = 43}))
          failures
            @?= [ RowBindingRejected (BindingSeedCohort (MissingSeedEvidence 42))
                , RowBindingRejected (BindingSeedCohort (UnplannedSeedEvidence 43))
                ]
    , testCase "a seed observed twice is a duplicate seed evidence" $
        withBaseline loaded $ \baseline -> do
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeSeeds = rmeSeeds row <> rmeSeeds row})
          failures @?= [RowBindingRejected (BindingSeedCohort (DuplicateSeedEvidence 42))]
    , testCase "k > 1: exact coverage of a three-seed plan cohort has no issue" $ do
        cohort <- threeSeedCohort
        checkSeedCoverage cohort [3, 1, 2] @?= []
    , testCase "k > 1: a seed gap, an extra seed, a duplicate, and an empty cohort are each typed" $ do
        cohort <- threeSeedCohort
        checkSeedCoverage cohort [1, 3] @?= [MissingSeedEvidence 2]
        checkSeedCoverage cohort [1, 2, 3, 4] @?= [UnplannedSeedEvidence 4]
        checkSeedCoverage cohort [1, 2, 2, 3] @?= [DuplicateSeedEvidence 2]
        checkSeedCoverage cohort []
          @?= [EmptySeedCohort, MissingSeedEvidence 1, MissingSeedEvidence 2, MissingSeedEvidence 3]
    ]

finalQualityControls :: IO (Either String Baseline) -> TestTree
finalQualityControls loaded =
  testGroup
    "final quality against the independent external criterion"
    [ testCase "PPO/cartpole: the unmutated evidence grades clean" $
        withBaseline loaded $ \baseline ->
          finalQualityAfter baseline "PPO/cartpole" id >>= (@?= [])
    , testCase "a value below the canonical bar is BelowBar and nothing else" $
        withBaseline loaded $ \baseline -> do
          failures <-
            finalQualityAfter baseline "PPO/cartpole" (mutateFinal (fmap (setValue 449.0)))
          failures @?= [BelowBar "median_final_reward" 449.0 ppoCartpoleCriterion]
    , testCase "a value exactly on the canonical threshold passes (the bar is inclusive)" $
        withBaseline loaded $ \baseline ->
          finalQualityAfter baseline "PPO/cartpole" (mutateFinal (fmap (setValue 450.0)))
            >>= (@?= [])
    , testCase "lowering the recorded threshold cannot rescue a below-bar value" $
        withBaseline loaded $ \baseline -> do
          failures <-
            finalQualityAfter
              baseline
              "PPO/cartpole"
              ( mutateFinal
                  ( fmap
                      ( \observation ->
                          observation
                            { Budget.rawCriterionThreshold = 400.0
                            , Budget.rawMeasurementValue = 420.0
                            }
                      )
                  )
              )
          failures
            @?= [ CriterionMismatch
                    42
                    "median_final_reward"
                    (Budget.RawCriterionAtLeast, 450.0)
                    (Budget.RawCriterionAtLeast, 400.0)
                , BelowBar "median_final_reward" 420.0 ppoCartpoleCriterion
                ]
    , testCase "a flipped comparison goal is a CriterionMismatch even when the value passes" $
        withBaseline loaded $ \baseline -> do
          failures <-
            finalQualityAfter
              baseline
              "PPO/cartpole"
              ( mutateFinal
                  (fmap (\observation -> observation {Budget.rawCriterionRule = Budget.RawCriterionAtMost}))
              )
          failures
            @?= [ CriterionMismatch
                    42
                    "median_final_reward"
                    (Budget.RawCriterionAtLeast, 450.0)
                    (Budget.RawCriterionAtMost, 450.0)
                ]
    , testCase "a missing metric is MissingMetric" $
        withBaseline loaded $ \baseline ->
          finalQualityAfter baseline "PPO/cartpole" (mutateFinal (const []))
            >>= (@?= [MissingMetric 42 "median_final_reward"])
    , testCase "a duplicated metric is DuplicateMetric" $
        withBaseline loaded $ \baseline ->
          finalQualityAfter
            baseline
            "PPO/cartpole"
            (mutateFinal (\observations -> observations <> observations))
            >>= (@?= [DuplicateMetric 42 "median_final_reward"])
    , testCase "an unexpected extra metric is UnexpectedMetric" $
        withBaseline loaded $ \baseline ->
          finalQualityAfter
            baseline
            "PPO/cartpole"
            (mutateFinal (<> [Budget.RawConvergenceObservation "avg_reward" Budget.RawCriterionAtLeast 0.0 1.0]))
            >>= (@?= [UnexpectedMetric 42 "avg_reward"])
    , testCase "a NaN, +Infinity, or -Infinity measurement cannot become evidence" $
        withBaseline loaded $ \baseline ->
          mapM_
            ( \value -> do
                failures <-
                  rowRejection baseline "PPO/cartpole" (mutateFinal (fmap (setValue value)))
                failures @?= [RowNonFiniteEvidence 42 "median_final_reward" "value"]
            )
            [0 / 0, 1 / 0, negate (1 / 0)]
    , testCase "a non-finite recorded threshold cannot become evidence" $
        withBaseline loaded $ \baseline -> do
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (mutateFinal (fmap (\observation -> observation {Budget.rawCriterionThreshold = 1 / 0})))
          failures @?= [RowNonFiniteEvidence 42 "median_final_reward" "threshold"]
    , testCase
        "AlphaZero: the all-draw sentinel 0.5 fails the exclusion rule even though it exceeds the bar"
        $ withBaseline loaded
        $ \baseline -> do
          finalQualityAfter baseline "connect4" id >>= (@?= [])
          failures <- finalQualityAfter baseline "connect4" (mutateFinal (fmap (setValue 0.5)))
          failures @?= [BelowBar "arena_win_rate" 0.5 alphaZeroCriterion]
    , testCase "AlphaZero: dropping the recorded exclusion rule is a CriterionMismatch" $
        withBaseline loaded $ \baseline -> do
          failures <-
            finalQualityAfter
              baseline
              "connect4"
              ( mutateFinal
                  ( fmap
                      ( \observation ->
                          observation
                            { Budget.rawCriterionRule = Budget.RawCriterionAtLeast
                            , Budget.rawMeasurementValue = 0.5
                            }
                      )
                  )
              )
          failures
            @?= [ CriterionMismatch
                    42
                    "arena_win_rate"
                    (Budget.RawCriterionAtLeastExcluding 0.5 1.0e-12, 0.45 - 0.05)
                    (Budget.RawCriterionAtLeast, 0.45 - 0.05)
                , BelowBar "arena_win_rate" 0.5 alphaZeroCriterion
                ]
    , testCase "HER: the achieved-goal-distance companion is required and graded" $
        withBaseline loaded $ \baseline -> do
          finalQualityAfter baseline "HER/goal-reaching" id >>= (@?= [])
          dropped <-
            finalQualityAfter
              baseline
              "HER/goal-reaching"
              (mutateFinal (filter ((/= "achieved_goal_distance") . Budget.rawCriterionName)))
          dropped @?= [MissingMetric 42 "achieved_goal_distance"]
          farther <-
            finalQualityAfter
              baseline
              "HER/goal-reaching"
              ( mutateFinal
                  ( fmap
                      ( \observation ->
                          if Budget.rawCriterionName observation == "achieved_goal_distance"
                            then setValue 0.06 observation
                            else observation
                      )
                  )
              )
          farther
            @?= [ BelowBar
                    "achieved_goal_distance"
                    0.06
                    (criterion "achieved_goal_distance" Budget.RawCriterionAtMost 0.05)
                ]
    , testCase "supervised accuracy, regression RMSE, and tuning objective each fail their own table bar" $
        withBaseline loaded $ \baseline -> do
          accuracy <-
            finalQualityAfter baseline "mnist-shallow-mlp" (mutateFinal (fmap (setValue 0.85)))
          accuracy
            @?= [ BelowBar
                    "test_accuracy"
                    0.85
                    (criterion "test_accuracy" Budget.RawCriterionAtLeast (0.97 - 0.07))
                ]
          rmse <-
            finalQualityAfter baseline "california-housing-mlp" (mutateFinal (fmap (setValue 1.5)))
          rmse
            @?= [ BelowBar
                    "rmse"
                    1.5
                    (criterion "rmse" Budget.RawCriterionAtMost (0.90 + 0.10))
                ]
          objective <-
            finalQualityAfter baseline "hyperparameter-tuning" (mutateFinal (fmap (setValue 0.94)))
          objective
            @?= [ BelowBar
                    "best_objective"
                    0.94
                    (criterion "best_objective" Budget.RawCriterionAtLeast (1.0 - 0.05))
                ]
    , testCase "a registry bar edited away from the canonical table is RegistryBarDrift and nothing else" $
        withBaseline loaded $ \baseline -> do
          raw <- rawRow baseline "PPO/cartpole"
          row <- registryRow "PPO/cartpole"
          let editedBar =
                Convergence.mkConvergenceBar
                  "median_final_reward"
                  Budget.MetricMaximise
                  475.0
                  100.0
              edited = row {ProductMatrix.convergenceBar = editedBar}
          case ProductMatrix.projectProductRow LinuxCUDA edited of
            Plan.Failure errors ->
              assertFailure ("edited row did not project: " <> show errors)
            Plan.Success (ProductMatrix.SomeProductProjection _ projection) -> do
              -- The contract digest covers the bar, so the forged raw view carries
              -- the edited projection's digest; everything else is the real row.
              let forged =
                    raw
                      { rmeContractDigest =
                          Report.productScenarioProjectionContractDigest projection
                      }
              case refineModelRowEvidence projection forged of
                Left errors -> assertFailure ("edited registry row rejected: " <> show errors)
                Right evidence ->
                  assertModelConvergence evidence
                    @?= [RegistryBarDrift ppoCartpoleCriterion editedBar]
    ]

separationControls :: IO (Either String Baseline) -> TestTree
separationControls loaded =
  testGroup
    "RL learning telemetry and final quality are separate evidence"
    [ testCase "good learning with a below-bar final quality fails only the final-quality assertion" $
        withBaseline loaded $ \baseline -> do
          let mutation = mutateFinal (fmap (setValue 449.0))
          finalQualityAfter baseline "PPO/cartpole" mutation
            >>= (@?= [BelowBar "median_final_reward" 449.0 ppoCartpoleCriterion])
          learningAfter baseline "PPO/cartpole" mutation >>= (@?= [])
          performanceAfter baseline "PPO/cartpole" mutation >>= (@?= [])
    , testCase "an excellent final quality with no learning fails only the learning assertion" $
        withBaseline loaded $ \baseline -> do
          let mutation =
                mutateLearning
                  ( \telemetry ->
                      telemetry
                        { rltUpdateCount = 0
                        , rltFinalWeightHash = rltInitialWeightHash telemetry
                        }
                  )
          learningAfter baseline "PPO/cartpole" mutation
            >>= (@?= [NoOptimizerUpdates 42, WeightsUnchanged 42])
          finalQualityAfter baseline "PPO/cartpole" mutation >>= (@?= [])
    , testCase "a learning payload offered as final-quality evidence is ChannelSubstituted" $
        withBaseline loaded $ \baseline -> do
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              ( mutateSeeds
                  ( \seed ->
                      seed
                        { rseFinalQuality =
                            (rseFinalQuality seed) {rfqChannel = LearningIterationChannel}
                        }
                  )
              )
          failures @?= [RowChannelSubstituted 42 FinalQualitySlot LearningIterationChannel]
    , testCase "a final-evaluation payload offered as learning telemetry is ChannelSubstituted" $
        withBaseline loaded $ \baseline -> do
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              ( mutateSeeds
                  ( \seed ->
                      seed {rseLearning = (rseLearning seed) {rltChannel = FinalEvaluationChannel}}
                  )
              )
          failures @?= [RowChannelSubstituted 42 LearningSlot FinalEvaluationChannel]
    , testCase "a learning counter that numerically clears the bar is still not final quality" $
        withBaseline loaded $ \baseline -> do
          let transitionsAsReward channel =
                mutateSeeds
                  ( \seed ->
                      seed
                        { rseFinalQuality =
                            RawFinalQuality
                              { rfqChannel = channel
                              , rfqObservations =
                                  fmap
                                    (setValue (fromIntegral (rltObservedUnits (rseLearning seed))))
                                    (rfqObservations (rseFinalQuality seed))
                              }
                        }
                  )
          -- With the payload tagged as what it is, the counter is rejected at the
          -- raw boundary ...
          rejected <-
            rowRejection baseline "PPO/cartpole" (transitionsAsReward LearningIterationChannel)
          rejected @?= [RowChannelSubstituted 42 FinalQualitySlot LearningIterationChannel]
          -- ... and only the channel tag stands between it and the bar: the same
          -- number forged onto the final channel would pass numerically.
          finalQualityAfter baseline "PPO/cartpole" (transitionsAsReward FinalEvaluationChannel)
            >>= (@?= [])
    ]

-- | 'RowAssertions.assertCompletedRowEvidence' is the opaque-evidence entry point
-- of the legacy row-assertion module: it must accept clean completed evidence
-- and report each defective channel under its own prefix.
rowAssertionsControls :: IO (Either String Baseline) -> TestTree
rowAssertionsControls loaded =
  testGroup
    "RowAssertions opaque entry point"
    [ testCase "clean completed evidence of every family passes" $
        withBaseline loaded $ \baseline ->
          mapM_
            (\rowId -> rowAssertionsAfter baseline rowId id >>= (@?= []))
            ["mnist-shallow-mlp", "PPO/cartpole", "HER/goal-reaching", "connect4", "hyperparameter-tuning"]
    , testCase "each defective channel is reported under its own prefix" $
        withBaseline loaded $ \baseline -> do
          quality <-
            rowAssertionsAfter baseline "PPO/cartpole" (mutateFinal (fmap (setValue 449.0)))
          length quality @?= 1
          assertBool "final-quality prefix" (all ("final quality: " `Text.isPrefixOf`) quality)
          learning <-
            rowAssertionsAfter
              baseline
              "PPO/cartpole"
              (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 0}))
          length learning @?= 1
          assertBool "learning prefix" (all ("learning: " `Text.isPrefixOf`) learning)
          performance <-
            rowAssertionsAfter
              baseline
              "PPO/cartpole"
              (mutateLearning (\telemetry -> telemetry {rltObservedUnits = rltObservedUnits telemetry + 1}))
          -- an overrun is both a learning failure (exact units) and a performance failure (ceiling)
          length performance @?= 2
          assertBool
            "learning and performance prefixes"
            ( any ("learning: " `Text.isPrefixOf`) performance
                && any ("performance: " `Text.isPrefixOf`) performance
            )
    ]

learningControls :: IO (Either String Baseline) -> TestTree
learningControls loaded =
  testGroup
    "learning telemetry"
    [ testCase "the unmutated evidence of every family grades clean" $
        withBaseline loaded $ \baseline ->
          mapM_
            (\rowId -> learningAfter baseline rowId id >>= (@?= []))
            [ "mnist-shallow-mlp"
            , "california-housing-mlp"
            , "PPO/cartpole"
            , "HER/goal-reaching"
            , "connect4"
            , "hyperparameter-tuning"
            ]
    , testCase "an underrun budget is ObservedUnitsMismatch against the plan's exact units" $
        withBaseline loaded $ \baseline ->
          learningAfter
            baseline
            "mnist-shallow-mlp"
            (mutateLearning (\telemetry -> telemetry {rltObservedUnits = 9}))
            >>= (@?= [ObservedUnitsMismatch 1001 10 9])
    , testCase "an overrun budget is ObservedUnitsMismatch too" $
        withBaseline loaded $ \baseline ->
          learningAfter
            baseline
            "PPO/cartpole"
            (mutateLearning (\telemetry -> telemetry {rltObservedUnits = rltObservedUnits telemetry + 1}))
            >>= (@?= [ObservedUnitsMismatch 42 1228800 1228801])
    , testCase "a budget counted in another unit is UnitKindMismatch" $
        withBaseline loaded $ \baseline ->
          learningAfter
            baseline
            "mnist-shallow-mlp"
            (mutateLearning (\telemetry -> telemetry {rltBudgetKind = Budget.RlEnvironmentStepBudget}))
            >>= (@?= [UnitKindMismatch 1001 Budget.SupervisedEpochBudget Budget.RlEnvironmentStepBudget])
    , testCase
        "an update count off the plan's exact optimizer updates is UpdateCountMismatch (supervised, AlphaZero, tuning)"
        $ withBaseline loaded
        $ \baseline -> do
          learningAfter
            baseline
            "mnist-shallow-mlp"
            (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 549}))
            >>= (@?= [UpdateCountMismatch 1001 550 549])
          learningAfter
            baseline
            "connect4"
            (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 511}))
            >>= (@?= [UpdateCountMismatch 42 512 511])
          learningAfter
            baseline
            "hyperparameter-tuning"
            (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 999}))
            >>= (@?= [UpdateCountMismatch 1729 1000 999])
    , testCase "a missing weight hash is WeightHashMissing, not WeightsUnchanged" $
        withBaseline loaded $ \baseline ->
          learningAfter
            baseline
            "mnist-shallow-mlp"
            (mutateLearning (\telemetry -> telemetry {rltInitialWeightHash = ""}))
            >>= (@?= [WeightHashMissing 1001])
    ]

performanceControls :: IO (Either String Baseline) -> TestTree
performanceControls loaded =
  testGroup
    "committed performance bounds over deterministic non-wall-clock counts"
    [ testCase "the unmutated evidence of every family satisfies its bounds" $
        withBaseline loaded $ \baseline ->
          mapM_
            (\rowId -> performanceAfter baseline rowId id >>= (@?= []))
            [ "mnist-shallow-mlp"
            , "california-housing-mlp"
            , "PPO/cartpole"
            , "HER/goal-reaching"
            , "connect4"
            , "hyperparameter-tuning"
            ]
    , testCase "supervised: a run that saw fewer examples than planned violates the AtLeast floor" $
        withBaseline loaded $ \baseline ->
          performanceAfter
            baseline
            "mnist-shallow-mlp"
            (mutateLearning (\telemetry -> telemetry {rltObservedUnits = 9}))
            >>= ( @?=
                    [ PerformanceBoundViolated
                        1001
                        ExternalBars.PerformanceExamplesSeen
                        (ExternalBars.AtLeast 70000)
                        63000
                    ]
                )
    , testCase "RL: more environment transitions than the plan's budget violates the AtMost ceiling" $
        withBaseline loaded $ \baseline ->
          performanceAfter
            baseline
            "PPO/cartpole"
            (mutateLearning (\telemetry -> telemetry {rltObservedUnits = rltObservedUnits telemetry + 1}))
            >>= ( @?=
                    [ PerformanceBoundViolated
                        42
                        ExternalBars.PerformanceEnvironmentTransitions
                        (ExternalBars.AtMost 1228800)
                        1228801
                    ]
                )
    , testCase
        "AlphaZero: fewer optimizer updates than generations times updates violates the AtLeast floor"
        $ withBaseline loaded
        $ \baseline ->
          performanceAfter
            baseline
            "connect4"
            (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 511}))
            >>= ( @?=
                    [ PerformanceBoundViolated
                        42
                        ExternalBars.PerformanceAlphaZeroOptimizerUpdates
                        (ExternalBars.AtLeast 512)
                        511
                    ]
                )
    , testCase "tuning: the promoted trial must reach and not exceed the per-trial update ceiling" $
        withBaseline loaded $ \baseline -> do
          performanceAfter
            baseline
            "hyperparameter-tuning"
            (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 999}))
            >>= ( @?=
                    [ PerformanceBoundViolated
                        1729
                        ExternalBars.PerformancePromotedTrialOptimizerUpdates
                        (ExternalBars.AtLeast 1000)
                        999
                    ]
                )
          performanceAfter
            baseline
            "hyperparameter-tuning"
            (mutateLearning (\telemetry -> telemetry {rltUpdateCount = 1001}))
            >>= ( @?=
                    [ PerformanceBoundViolated
                        1729
                        ExternalBars.PerformancePromotedTrialOptimizerUpdates
                        (ExternalBars.AtMost 1000)
                        1001
                    ]
                )
    , testCase "a performance defect is invisible to the final-quality assertion and vice versa" $
        withBaseline loaded $ \baseline -> do
          let underrun = mutateLearning (\telemetry -> telemetry {rltObservedUnits = 9})
          finalQualityAfter baseline "mnist-shallow-mlp" underrun >>= (@?= [])
          performanceAfter baseline "mnist-shallow-mlp" (mutateFinal (fmap (setValue 0.85)))
            >>= (@?= [])
    , testCase "receipts bind every measurement to the row's plan, experiment, and manifest identity" $
        withBaseline loaded $ \baseline -> do
          set <- joinedSet baseline (baselineRaw baseline)
          mapM_ (checkReceipts baseline) (modelEvidenceSetRows set)
    ]

-- | Each receipt must carry the identity of the validated projection (plan,
-- experiment) and of the journal row's admitted manifest, read through paths
-- independent of the receipt itself.
checkReceipts :: Baseline -> SomeModelRowEvidence -> IO ()
checkReceipts baseline (SomeModelRowEvidence _ evidence) = do
  let rowId = modelEvidenceRowId evidence
      receipts = modelPerformanceReceipts evidence
  projection <- projectionFor baseline rowId
  raw <- rawRow baseline rowId
  assertBool ("no performance receipt for " <> Text.unpack rowId) (not (null receipts))
  mapM_
    ( \receipt -> do
        receiptRowId receipt @?= rowId
        receiptPlanId receipt @?= someProjectionPlanId projection
        receiptExperimentHash receipt @?= someProjectionExperiment projection
        receiptManifestSha receipt @?= rmeManifestSha raw
    )
    receipts

bindingControls :: IO (Either String Baseline) -> TestTree
bindingControls loaded =
  testGroup
    "plan, experiment, manifest and completion binding"
    [ testCase "an inference manifest that differs from the admitted manifest is a typed mismatch" $
        withBaseline loaded $ \baseline -> do
          admitted <- rmeManifestSha <$> rawRow baseline "PPO/cartpole"
          other <- rmeManifestSha <$> rawRow baseline "A2C/cartpole"
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeInferenceManifestSha = other})
          failures
            @?= [RowBindingRejected (BindingMismatch BindingInferenceManifest admitted other)]
    , testCase "a non-canonical manifest identity is a typed malformed digest" $
        withBaseline loaded $ \baseline -> do
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeManifestSha = "abc", rmeInferenceManifestSha = "abc"})
          failures
            @?= [ RowBindingRejected (BindingDigestMalformed BindingAdmittedManifest "abc")
                , RowBindingRejected (BindingDigestMalformed BindingInferenceManifest "abc")
                ]
    , testCase "an experiment hash the completion did not record is a typed mismatch" $
        withBaseline loaded $ \baseline -> do
          expected <- someProjectionExperiment <$> projectionFor baseline "PPO/cartpole"
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              ( \row ->
                  row {rmeCompletion = (rmeCompletion row) {rciExperimentHash = "product-row-other"}}
              )
          failures
            @?= [ RowBindingRejected
                    (BindingMismatch BindingCompletionExperiment expected "product-row-other")
                ]
    , testCase "a completion recorded for another plan is a typed mismatch" $
        withBaseline loaded $ \baseline -> do
          expected <- someProjectionPlanId <$> projectionFor baseline "PPO/cartpole"
          other <- rmePlanId <$> rawRow baseline "A2C/cartpole"
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeCompletion = (rmeCompletion row) {rciPlanId = other}})
          failures
            @?= [ RowBindingRejected
                    ( BindingMismatch
                        BindingCompletionPlan
                        (Plan.planIdText expected)
                        (Plan.planIdText other)
                    )
                ]
    , testCase "an invocation for another row is a typed mismatch and an absent invocation is missing" $
        withBaseline loaded $ \baseline -> do
          wrongRow <-
            rowRejection
              baseline
              "PPO/cartpole"
              ( \row ->
                  row
                    { rmeCompletion =
                        (rmeCompletion row)
                          { rciInvocation =
                              (\invocation -> invocation {riiRowId = "A2C/cartpole"})
                                <$> rciInvocation (rmeCompletion row)
                          }
                    }
              )
          wrongRow
            @?= [ RowBindingRejected
                    (BindingMismatch BindingInvocationRow "PPO/cartpole" "A2C/cartpole")
                ]
          absent <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeCompletion = (rmeCompletion row) {rciInvocation = Nothing}})
          absent @?= [RowBindingRejected (BindingMissing BindingInvocationRow)]
    , testCase "a device witness from another lane, or none, is rejected" $
        withBaseline loaded $ \baseline -> do
          wrongLane <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeCompletion = (rmeCompletion row) {rciDeviceSubstrate = Just LinuxCPU}})
          wrongLane
            @?= [ RowBindingRejected
                    (BindingMismatch BindingDeviceWitnessLane "linux-cuda" "linux-cpu")
                ]
          absent <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeCompletion = (rmeCompletion row) {rciDeviceSubstrate = Nothing}})
          absent @?= [RowBindingRejected (BindingMissing BindingDeviceWitnessLane)]
    , testCase "a measured digest that is not the digest of the consumed completion is a typed mismatch" $
        withBaseline loaded $ \baseline -> do
          raw <- rawRow baseline "PPO/cartpole"
          other <- rmeMeasuredDigest <$> rawRow baseline "A2C/cartpole"
          failures <-
            rowRejection
              baseline
              "PPO/cartpole"
              (\row -> row {rmeRecomputedMeasuredDigest = other})
          failures
            @?= [ RowBindingRejected
                    (BindingMismatch BindingMeasuredDigest other (rmeMeasuredDigest raw))
                ]
    , testCase
        "evidence offered against another row's projection, or another run kind's, fails the binding assertion"
        $ withBaseline loaded
        $ \baseline -> do
          set <- joinedSet baseline (baselineRaw baseline)
          evidence <-
            maybe
              (assertFailure "no PPO/cartpole evidence")
              pure
              (lookupModelEvidence "PPO/cartpole" set)
          anotherRl <- projectionFor baseline "A2C/cartpole"
          supervised <- projectionFor baseline "mnist-shallow-mlp"
          assertBool
            "evidence bound to A2C/cartpole's projection"
            ( BindingMismatch BindingRowId "A2C/cartpole" "PPO/cartpole"
                `elem` assertSomeModelBinding anotherRl evidence
            )
          assertSomeModelBinding supervised evidence
            @?= [BindingMismatch BindingRunKind "supervised-training" "reinforcement-learning"]
    ]

-- ---------------------------------------------------------------------------
-- Lane-independent guards

requireBatch :: IO ProductMatrix.ProductProjectionBatch
requireBatch =
  case ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows of
    Plan.Failure errors -> assertFailure ("registry does not project: " <> show errors)
    Plan.Success batch -> pure batch

requirementsFor :: Text -> IO [ExternalBars.PerformanceRequirement]
requirementsFor rowId = do
  batch <- requireBatch
  case find ((== rowId) . someProjectionRowId) (ProductMatrix.productProjectionBatchProjections batch) of
    Just (ProductMatrix.SomeProductProjection _ projection) ->
      pure
        ( ExternalBars.performanceRequirementsFor
            (ProductMatrix.productProjectionResolvedPlan projection)
        )
    Nothing -> assertFailure ("registry has no row " <> Text.unpack rowId)

criteriaFor :: Text -> IO [ExternalBars.ExternalCriterion]
criteriaFor rowId = do
  batch <- requireBatch
  case find ((== rowId) . someProjectionRowId) (ProductMatrix.productProjectionBatchProjections batch) of
    Just (ProductMatrix.SomeProductProjection _ projection) ->
      case ExternalBars.externalCriteriaFor
        rowId
        (ProductMatrix.productProjectionRowClass projection) of
        Left reason -> assertFailure (Text.unpack reason)
        Right criteria -> pure (NonEmpty.toList criteria)
    Nothing -> assertFailure ("registry has no row " <> Text.unpack rowId)

-- | Every Haskell source under @src@, @app@ and @test@ whose text mentions the
-- needle and satisfies the predicate, as a sorted list of repository-relative
-- paths. The predicate (a tokenising scan) only runs on files that mention the
-- needle at all: a module cannot be imported, or a flag set, without its name
-- appearing in the file.
sourcesMentioning :: Text -> (Text -> Bool) -> IO [FilePath]
sourcesMentioning needle predicate = do
  files <- sourceFiles ["src", "app", "test"]
  filterM
    (fmap (\source -> needle `Text.isInfixOf` source && predicate source) . readSourceUtf8)
    files

-- | Every source that imports the named module, in any import syntax.
importersOf :: Text -> IO [FilePath]
importersOf moduleName = sourcesMentioning moduleName (elem moduleName . importedModules)

-- | Every source with an @OPTIONS_GHC@ pragma that sets the flag.
optOutsOf :: Text -> IO [FilePath]
optOutsOf flag = sourcesMentioning flag (elem flag . optionsGhcFlags)

-- | The modules allowed to import the raw evidence boundary: the mutation
-- control modules, each of which opts out of its compile-time warning.
controlModules :: [FilePath]
controlModules =
  [ "test/model-convergence/ControlSupport.hs"
  , "test/model-convergence/Controls.hs"
  , "test/model-convergence/GateControls.hs"
  , "test/model-convergence/WiringControls.hs"
  ]

-- | The warning category the raw evidence module carries, and the flag that
-- opts one module out of it.
rawWarningCategory, rawWarningFlag :: Text
rawWarningCategory = "x-model-evidence-raw"
rawWarningFlag = "-Wno-" <> rawWarningCategory

-- | Every import form the scanner must see, each importing the raw module and
-- nothing else. The layouts a line-based matcher misses are all here.
importForms :: [(String, Text)]
importForms =
  [ ("a plain import", "import JitML.Test.ModelEvidence.Raw\n")
  , ("a qualified import", "import qualified JitML.Test.ModelEvidence.Raw as R\n")
  , ("a post-positive qualified import", "import JitML.Test.ModelEvidence.Raw qualified as R\n")
  , ("a safe import", "import safe JitML.Test.ModelEvidence.Raw\n")
  , ("a package import", "import \"jitml\" JitML.Test.ModelEvidence.Raw\n")
  , ("a SOURCE import", "import {-# SOURCE #-} JitML.Test.ModelEvidence.Raw\n")
  ,
    ( "an import whose keywords sit on separate lines"
    , "import\n  qualified\n  JitML.Test.ModelEvidence.Raw as R\n"
    )
  ,
    ( "an import list over several lines"
    , "import JitML.Test.ModelEvidence.Raw\n  ( RawModelEvidence (..)\n  , joinModelEvidence\n  )\n"
    )
  ,
    ( "every qualifier at once"
    , "import {-# SOURCE #-} safe qualified \"jitml\" JitML.Test.ModelEvidence.Raw as R\n"
    )
  ]

-- | Text that mentions the raw module without importing it, with the imports
-- it does make (only the module named after the raw one, or its parent).
nonImportForms :: [(String, Text, [Text])]
nonImportForms =
  [ ("a line comment", "-- import JitML.Test.ModelEvidence.Raw\n", [])
  , ("a haddock comment", "-- | import JitML.Test.ModelEvidence.Raw\n", [])
  , ("a block comment", "{- import JitML.Test.ModelEvidence.Raw -}\n", [])
  , ("a nested block comment", "{- outer {- inner -} import JitML.Test.ModelEvidence.Raw -}\n", [])
  , ("a string literal", "banner = \"import JitML.Test.ModelEvidence.Raw\"\n", [])
  ,
    ( "a module named after it"
    , "import JitML.Test.ModelEvidence.RawExtra\n"
    , ["JitML.Test.ModelEvidence.RawExtra"]
    )
  , ("its parent module", "import JitML.Test.ModelEvidence\n", ["JitML.Test.ModelEvidence"])
  ,
    ( "a qualified name in an expression"
    , "value = JitML.Test.ModelEvidence.Raw.joinModelEvidence\n"
    , []
    )
  ]

-- | A source that strings, escapes, character literals, and a promoted
-- constructor must not derail: each import after one is still found, and no
-- import-looking text inside a comment or string is.
scannerFixture :: Text
scannerFixture =
  Text.unlines
    [ "{-# LANGUAGE OverloadedStrings #-}"
    , "{-# OPTIONS_GHC -Wall -Wno-x-model-evidence-raw #-}"
    , "-- import Commented.Line"
    , "{- import Commented.Block"
    , "   {- import Commented.Nested -}"
    , "   import Commented.AfterNested -}"
    , "module Fixture where"
    , "import Plain.One"
    , "import qualified Qualified.Two as Q"
    , "import Post.Three qualified as P"
    , "import safe Safe.Four"
    , "import \"jitml\" Package.Five"
    , "import {-# SOURCE #-} Source.Six"
    , "import"
    , "  qualified"
    , "  Split.Seven as S"
    , "import Listed.Eight"
    , "  ( first"
    , "  , second"
    , "  )"
    , "import {-# SOURCE #-} safe qualified \"pkg\" Everything.Nine as E"
    , "banner :: String"
    , "banner = \"import Inside.String\""
    , "quote :: Char"
    , "quote = '\"'"
    , "import Late.AfterQuote"
    , "escaped :: String"
    , "escaped = \"quote \\\" import Inside.Escaped \\\" end\""
    , "import Late.AfterEscape"
    , "promoted :: Proxy 'Declared"
    , "import Late.AfterPromoted"
    ]

-- | Run an action with @JITML_SUBSTRATE@ set (or unset), restoring the caller's
-- value afterwards. The stanza reads the variable once, in @main@, so no other
-- case observes the change.
withLaneVariable :: Maybe String -> IO result -> IO result
withLaneVariable desired action =
  bracket
    (lookupEnv laneVariable)
    (maybe (unsetEnv laneVariable) (setEnv laneVariable))
    (\_ -> maybe (unsetEnv laneVariable) (setEnv laneVariable) desired >> action)
 where
  laneVariable = "JITML_SUBSTRATE"

independentTests :: TestTree
independentTests =
  testGroup
    "lane-independent guards"
    [ testGroup
        "canonical criteria and committed bounds"
        [ testCase "every ProductRow resolves canonical criteria, and the primary equals its registry bar" $ do
            batch <- requireBatch
            let disagreements =
                  [ rowId <> ": " <> reason
                  | ProductMatrix.SomeProductProjection _ projection <-
                      ProductMatrix.productProjectionBatchProjections batch
                  , let rowId = ProductMatrix.productProjectionRowId projection
                  , let bar = ProductMatrix.productProjectionConvergenceBar projection
                  , Just reason <-
                      [ case ExternalBars.externalCriteriaFor
                          rowId
                          (ProductMatrix.productProjectionRowClass projection) of
                          Left err -> Just err
                          Right (primary :| _)
                            | ExternalBars.externalCriterionName primary
                                == Convergence.convergenceMetricName bar
                                && ExternalBars.externalCriterionGoal primary
                                  == Convergence.convergenceMetricGoal bar
                                && ExternalBars.externalCriterionThreshold primary
                                  == Convergence.convergenceThreshold bar ->
                                Nothing
                            | otherwise -> Just "the canonical criterion differs from the registry bar"
                      ]
                  ]
            disagreements @?= []
        , testCase "canonical criteria are the documented table entries for every family" $ do
            criteriaFor "mnist-shallow-mlp"
              >>= (@?= [criterion "test_accuracy" Budget.RawCriterionAtLeast (0.97 - 0.07)])
            criteriaFor "california-housing-mlp"
              >>= (@?= [criterion "rmse" Budget.RawCriterionAtMost (0.90 + 0.10)])
            criteriaFor "PPO/cartpole" >>= (@?= [ppoCartpoleCriterion])
            criteriaFor "TRPO/cartpole"
              >>= (@?= [criterion "median_final_reward" Budget.RawCriterionAtLeast (475.0 - 75.0)])
            criteriaFor "HER/goal-reaching"
              >>= ( @?=
                      [ criterion "goal_success_rate" Budget.RawCriterionAtLeast (0.90 - 0.05)
                      , criterion "achieved_goal_distance" Budget.RawCriterionAtMost 0.05
                      ]
                  )
            criteriaFor "connect4" >>= (@?= [alphaZeroCriterion])
            criteriaFor "hyperparameter-tuning"
              >>= (@?= [criterion "best_objective" Budget.RawCriterionAtLeast (1.0 - 0.05)])
        , testCase "committed performance bounds are plan quantities, not measurements" $ do
            requirementsFor "mnist-shallow-mlp"
              >>= (@?= [requirement ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 70000)])
            requirementsFor "cifar10-resnet20"
              >>= (@?= [requirement ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 40000)])
            requirementsFor "cifar10-vit"
              >>= (@?= [requirement ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 80000)])
            requirementsFor "tiny-imagenet-resnet50"
              >>= (@?= [requirement ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 120000)])
            requirementsFor "PPO/cartpole"
              >>= ( @?=
                      [requirement ExternalBars.PerformanceEnvironmentTransitions (ExternalBars.AtMost 1228800)]
                  )
            requirementsFor "SAC/pendulum"
              >>= ( @?=
                      [requirement ExternalBars.PerformanceEnvironmentTransitions (ExternalBars.AtMost 4000)]
                  )
            requirementsFor "connect4"
              >>= ( @?=
                      [requirement ExternalBars.PerformanceAlphaZeroOptimizerUpdates (ExternalBars.AtLeast 512)]
                  )
            requirementsFor "othello"
              >>= ( @?=
                      [requirement ExternalBars.PerformanceAlphaZeroOptimizerUpdates (ExternalBars.AtLeast 1536)]
                  )
            requirementsFor "hyperparameter-tuning"
              >>= ( @?=
                      [ requirement ExternalBars.PerformancePromotedTrialOptimizerUpdates (ExternalBars.AtLeast 1000)
                      , requirement ExternalBars.PerformancePromotedTrialOptimizerUpdates (ExternalBars.AtMost 1000)
                      ]
                  )
        , testCase "every ProductRow has a performance requirement and a singleton plan cohort" $ do
            batch <- requireBatch
            let problems =
                  [ ProductMatrix.productProjectionRowId projection
                  | ProductMatrix.SomeProductProjection _ projection <-
                      ProductMatrix.productProjectionBatchProjections batch
                  , null
                      ( ExternalBars.performanceRequirementsFor
                          (ProductMatrix.productProjectionResolvedPlan projection)
                      )
                      || length
                        ( NonEmpty.toList
                            ( Plan.seedCohortValues
                                (Plan.runPlanSeeds (ProductMatrix.productProjectionRunPlan projection))
                            )
                        )
                        /= 1
                  ]
            problems @?= []
        ]
    , testGroup
        "registry projection coverage guard"
        [ testCase "the full registry projects to exactly its rows on every lane" $
            mapM_
              (\lane -> assertRegistryCoverageOf lane ProductMatrix.allProductRows @?= [])
              [LinuxCPU, LinuxCUDA, AppleSilicon]
        , testCase "a registry slice missing a row is reported as dropped" $
            assertRegistryCoverageOf LinuxCPU (dropLast ProductMatrix.allProductRows)
              @?= ["projection dropped ProductRow hyperparameter-tuning"]
        , testCase "a duplicated row makes the registry unprojectable and is reported by name" $
            case ProductMatrix.allProductRows of
              first : _ ->
                assertBool
                  "duplicate row id was not reported"
                  ( any
                      (Text.isInfixOf ("duplicate row id: " <> ProductMatrix.rowId first))
                      (assertRegistryCoverageOf LinuxCPU (ProductMatrix.allProductRows <> [first]))
                  )
              [] -> assertFailure "registry is empty"
        , testCase "an unprojectable row is reported by name" $ do
            row <- registryRow "PPO/cartpole"
            let broken = row {ProductMatrix.implementation = "not.the.canonical.implementation"}
                others = filter ((/= "PPO/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows
            assertBool
              "implementation mismatch was not reported"
              ( any
                  (Text.isInfixOf "PPO/cartpole")
                  (assertRegistryCoverageOf LinuxCPU (broken : others))
              )
        ]
    , testGroup
        "raw evidence mint import guard"
        [ testCase "only the mutation control modules import the raw evidence mint" $
            importersOf "JitML.Test.ModelEvidence.Raw" >>= (@?= controlModules)
        , testCase "exactly those modules opt out of the raw evidence warning" $
            optOutsOf rawWarningFlag >>= (@?= controlModules)
        , testCase "the raw evidence module still carries the warning the compiler enforces" $ do
            source <- readSourceUtf8 "src/JitML/Test/ModelEvidence/Raw.hs"
            assertBool
              ("src/JitML/Test/ModelEvidence/Raw.hs has no WARNING in " <> show rawWarningCategory)
              (any (("\"" <> rawWarningCategory <> "\"") `Text.isInfixOf`) (pragmaBodies "WARNING" source))
        , testCase "only the two evidence facades import the hidden implementation module" $
            importersOf "JitML.Test.ModelEvidence.Internal"
              >>= ( @?=
                      [ "src/JitML/Test/ModelEvidence.hs"
                      , "src/JitML/Test/ModelEvidence/Raw.hs"
                      ]
                  )
        ]
    , testGroup
        "source scanner behind the import guard"
        ( [ testCase ("finds " <> label) $
              importedModules source @?= ["JitML.Test.ModelEvidence.Raw"]
          | (label, source) <- importForms
          ]
            <> [ testCase ("does not mistake " <> label <> " for an import of it") $
                   importedModules source @?= imports
               | (label, source, imports) <- nonImportForms
               ]
            <> [ testCase "keeps lexing after strings, escapes, character literals, and promoted constructors" $
                   importedModules scannerFixture
                     @?= [ "Plain.One"
                         , "Qualified.Two"
                         , "Post.Three"
                         , "Safe.Four"
                         , "Package.Five"
                         , "Source.Six"
                         , "Split.Seven"
                         , "Listed.Eight"
                         , "Everything.Nine"
                         , "Late.AfterQuote"
                         , "Late.AfterEscape"
                         , "Late.AfterPromoted"
                         ]
               , testCase "reads the flags of every OPTIONS_GHC pragma and of nothing else" $ do
                   optionsGhcFlags scannerFixture @?= ["-Wall", "-Wno-x-model-evidence-raw"]
                   optionsGhcFlags "-- {-# OPTIONS_GHC -Wall #-}\nvalue = \"{-# OPTIONS_GHC -Wall #-}\"\n"
                     @?= []
                   optionsGhcFlags "{-# OPTIONS_GHC -Wall #-}\n{-# OPTIONS_GHC -Werror #-}\n"
                     @?= ["-Wall", "-Werror"]
               , testCase "tokenises a source that ends inside a comment, a string, or a pragma" $ do
                   lexSource "{- never closed import JitML.Test.ModelEvidence.Raw" @?= []
                   importedModules "import Closed.One\nvalue = \"never closed import Open.Two" @?= ["Closed.One"]
                   importedModules "import Closed.One\n{-# LANGUAGE never closed import Open.Two"
                     @?= ["Closed.One"]
               , testCase "reads sources as UTF-8 whatever the locale" $ do
                   -- The scan crashed under LC_ALL=C when it read sources with the locale's
                   -- encoding; some source of the repository carries non-ASCII text.
                   files <- sourceFiles ["src"]
                   sources <- mapM readSourceUtf8 files
                   assertBool
                     "no source under src carries non-ASCII text, so this control proves nothing"
                     (any (Text.any (> '\x7f')) sources)
               ]
        )
    , testGroup
        "lane selection (JITML_SUBSTRATE)"
        [ testCase "an unset variable selects linux-cpu, the default lane" $
            withLaneVariable Nothing selectedModelConvergenceSubstrate >>= (@?= Right LinuxCPU)
        , testCase "each named lane is selected" $
            mapM_
              ( \(name, lane) ->
                  withLaneVariable (Just name) selectedModelConvergenceSubstrate >>= (@?= Right lane)
              )
              [("linux-cpu", LinuxCPU), ("linux-cuda", LinuxCUDA), ("apple-silicon", AppleSilicon)]
        , testCase "an unknown lane is a typed failure, never the default lane" $
            withLaneVariable (Just "bogus") selectedModelConvergenceSubstrate
              >>= (@?= Left "invalid JITML_SUBSTRATE: bogus")
        ]
    , testGroup
        "seed cohort statistic (k > 1 fixtures)"
        [ testCase "the cohort median is the middle value, and the mean of the middle two" $ do
            cohortMedian (5 :| []) @?= 5
            cohortMedian (3 :| [1, 2]) @?= 2
            cohortMedian (4 :| [1, 3, 2]) @?= 2.5
        , testCase "the cohort statistic is the median across seeds, not the mean or the worst seed" $ do
            -- Median 1.0 clears 0.75 although the mean (0.667) would not.
            gradeCohortCriteria (accuracyBar 0.75 :| []) (cohortOf 0.75 [(1, 1.0), (2, 1.0), (3, 0.0)]) @?= []
            -- Median 0.0 misses 0.25 although the mean (0.333) would clear it.
            gradeCohortCriteria (accuracyBar 0.25 :| []) (cohortOf 0.25 [(1, 1.0), (2, 0.0), (3, 0.0)])
              @?= [BelowBar "test_accuracy" 0.0 (accuracyBar 0.25)]
            -- An even cohort takes the mean of its two middle values: 0.5 clears 0.5 (inclusive).
            gradeCohortCriteria (accuracyBar 0.5 :| []) (cohortOf 0.5 [(1, 0.25), (2, 0.75)]) @?= []
            gradeCohortCriteria (accuracyBar 0.5 :| []) (cohortOf 0.5 [(1, 0.25), (2, 0.5)])
              @?= [BelowBar "test_accuracy" 0.375 (accuracyBar 0.5)]
        , testCase
            "a seed with no observation, a duplicate, an extra metric, or a foreign criterion is typed per seed"
            $ do
              let bar = accuracyBar 0.5
                  good seed = (seed, [accuracyObservation 0.5 0.9])
              gradeCohortCriteria (bar :| []) [good 1, (2, []), good 3] @?= [MissingMetric 2 "test_accuracy"]
              gradeCohortCriteria
                (bar :| [])
                [good 1, good 2, (3, [accuracyObservation 0.5 0.9, accuracyObservation 0.5 0.9])]
                @?= [DuplicateMetric 3 "test_accuracy"]
              gradeCohortCriteria
                (bar :| [])
                [ good 1
                ,
                  ( 2
                  ,
                    [ accuracyObservation 0.5 0.9
                    , Budget.RawConvergenceObservation "avg_reward" Budget.RawCriterionAtLeast 0.0 1.0
                    ]
                  )
                , good 3
                ]
                @?= [UnexpectedMetric 2 "avg_reward"]
              gradeCohortCriteria (bar :| []) [good 1, (2, [accuracyObservation 0.1 0.9]), good 3]
                @?= [ CriterionMismatch
                        2
                        "test_accuracy"
                        (Budget.RawCriterionAtLeast, 0.5)
                        (Budget.RawCriterionAtLeast, 0.1)
                    ]
        ]
    ]
 where
  requirement = ExternalBars.PerformanceRequirement
  accuracyBar = criterion "test_accuracy" Budget.RawCriterionAtLeast
  accuracyObservation =
    Budget.RawConvergenceObservation "test_accuracy" Budget.RawCriterionAtLeast
  cohortOf threshold values =
    [(seed, [accuracyObservation threshold value]) | (seed, value) <- values :: [(Word64, Double)]]
  dropLast rows = take (length rows - 1) rows

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-x-model-evidence-raw #-}

-- | Phase 285 — controls for the parts of the evidence layer that field-level
-- mutations of one row cannot reach.
--
-- * The per-row case wiring ('rowCheckFailures') is what the stanza's
--   @55 x 4@ lane cases run. On clean evidence it always answers @[]@, so a
--   wiring that silently dropped an assertion would stay green. These controls
--   rebuild the 'LaneEvidence' around one corrupted row and require each of the
--   four checks to report exactly the failures of its own channel.
-- * The closed comparison rules ('externalCriterionPasses',
--   'performanceBoundHolds') are pinned at their boundaries, one representable
--   step either side, so an inclusive rule cannot become exclusive or gain a
--   tolerance.
-- * Every identity field the mint compares against the validated projection is
--   offered wrong on its own, straight to the mint, so that the join's earlier
--   plan/lane/contract answers cannot mask a missing field-level check.
-- * The registry-drift check is pinned per component (name, goal, threshold),
--   and the requirement-without-measurement case of the performance grading is
--   pinned directly, because no real completed row can reach either.
-- * A seed cohort larger than one, which no ProductRow plans today, is minted
--   end to end from a real multi-seed plan cohort and graded with the cohort
--   statistic.
module WiringControls
  ( wiringTests
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import ControlSupport
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate (..))
import JitML.Test.ModelConvergence
  ( RowCheck (..)
  , allRowChecks
  , assertLaneEvidenceCoverage
  , assertRegistryCoverageOf
  , modelConvergenceRowIds
  , rowCheckFailures
  )
import JitML.Test.ModelEvidence
import JitML.Test.ModelEvidence.Raw
import JitML.Training.Budget qualified as Budget

wiringTests :: TestTree
wiringTests =
  withResource loadBaseline (const (pure ())) $ \loaded ->
    testGroup
      "wiring, boundary, and cohort controls"
      [ caseWiringControls loaded
      , identityControls loaded
      , registryOrderControls
      , boundaryControls
      , driftControls
      , exclusionParameterControls loaded
      , evidenceBoundaryControls loaded
      , performanceGradingControls
      , cohortControls loaded
      ]

-- ---------------------------------------------------------------------------
-- Per-row case wiring

-- | The lane evidence the stanza would grade, rebuilt around the baseline with
-- one row's raw view corrupted. The mutation must still mint (the join accepts
-- it), so what is under test is the grading, not the refusal.
laneEvidenceAfter
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO LaneEvidence
laneEvidenceAfter baseline rowId mutation = do
  set <- joinedSet baseline (mutateRow rowId mutation (baselineRaw baseline))
  pure (LaneEvidence (baselineLane baseline) set)

-- | Every check's rendered failures for one row, in check order.
checksOf :: LaneEvidence -> Text -> [(RowCheck, [Text])]
checksOf laneEvidence rowId =
  [(check, rowCheckFailures check laneEvidence rowId) | check <- allRowChecks]

caseWiringControls :: IO (Either String Baseline) -> TestTree
caseWiringControls loaded =
  testGroup
    "per-row case wiring reports each channel's failures and only those"
    [ testCase "unmutated evidence passes all four checks of every ProductRow" $
        withBaseline loaded $ \baseline -> do
          laneEvidence <- laneEvidenceAfter baseline "PPO/cartpole" id
          [ (rowId, check, failures)
            | rowId <- modelConvergenceRowIds
            , check <- allRowChecks
            , let failures = rowCheckFailures check laneEvidence rowId
            , not (null failures)
            ]
            @?= []
    , testCase "a below-bar final quality fails the convergence check of that row only" $
        withBaseline loaded $ \baseline -> do
          laneEvidence <-
            laneEvidenceAfter baseline "PPO/cartpole" (mutateFinal (fmap (setValue 449.0)))
          checksOf laneEvidence "PPO/cartpole"
            @?= [
                  ( ConvergenceCheck
                  , [renderFinalQualityFailure (BelowBar "median_final_reward" 449.0 ppoCartpoleCriterion)]
                  )
                , (LearningCheck, [])
                , (PerformanceCheck, [])
                , (BindingCheck, [])
                ]
          checksOf laneEvidence "A2C/cartpole"
            @?= [(check, []) | check <- allRowChecks]
    , testCase "an update-free run fails the learning check of that row only" $
        withBaseline loaded $ \baseline -> do
          laneEvidence <-
            laneEvidenceAfter
              baseline
              "PPO/cartpole"
              ( mutateLearning
                  ( \telemetry ->
                      telemetry
                        { rltUpdateCount = 0
                        , rltFinalWeightHash = rltInitialWeightHash telemetry
                        }
                  )
              )
          checksOf laneEvidence "PPO/cartpole"
            @?= [ (ConvergenceCheck, [])
                , (LearningCheck, fmap renderLearningFailure [NoOptimizerUpdates 42, WeightsUnchanged 42])
                , (PerformanceCheck, [])
                , (BindingCheck, [])
                ]
    , testCase "a transition overrun fails the learning and performance checks and no others" $
        withBaseline loaded $ \baseline -> do
          laneEvidence <-
            laneEvidenceAfter
              baseline
              "PPO/cartpole"
              (mutateLearning (\telemetry -> telemetry {rltObservedUnits = rltObservedUnits telemetry + 1}))
          checksOf laneEvidence "PPO/cartpole"
            @?= [ (ConvergenceCheck, [])
                , (LearningCheck, [renderLearningFailure (ObservedUnitsMismatch 42 1228800 1228801)])
                ,
                  ( PerformanceCheck
                  ,
                    [ renderPerformanceFailure
                        ( PerformanceBoundViolated
                            42
                            ExternalBars.PerformanceEnvironmentTransitions
                            (ExternalBars.AtMost 1228800)
                            1228801
                        )
                    ]
                  )
                , (BindingCheck, [])
                ]
    , testCase "a receipt whose manifest is not the admitted journal row's fails the performance check" $
        withBaseline loaded $ \baseline -> do
          clean <- laneEvidenceAfter baseline "PPO/cartpole" id
          rowCheckFailures PerformanceCheck clean "PPO/cartpole" @?= []
          admittedManifest <- rmeManifestSha <$> rawRow baseline "PPO/cartpole"
          foreignManifest <- rmeManifestSha <$> rawRow baseline "A2C/cartpole"
          laneEvidence <-
            laneEvidenceAfter
              baseline
              "PPO/cartpole"
              (\row -> row {rmeManifestSha = foreignManifest, rmeInferenceManifestSha = foreignManifest})
          rowCheckFailures PerformanceCheck laneEvidence "PPO/cartpole"
            @?= [ renderReceiptBindingFailure
                    (ReceiptNotBound BindingAdmittedManifest admittedManifest foreignManifest)
                ]
          -- The manifest is still a canonical digest, so no other channel objects.
          [ check
            | check <- [ConvergenceCheck, LearningCheck, BindingCheck]
            , not (null (rowCheckFailures check laneEvidence "PPO/cartpole"))
            ]
            @?= []
    , testCase "evidence graded against another lane's projection fails the binding check" $
        withBaseline loaded $ \baseline ->
          case ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows of
            Plan.Failure errors -> assertFailure ("linux-cpu projection failed: " <> show errors)
            Plan.Success cpuBatch -> do
              clean <- laneEvidenceAfter baseline "PPO/cartpole" id
              rowCheckFailures BindingCheck clean "PPO/cartpole" @?= []
              let crossed =
                    LaneEvidence
                      ((baselineLane baseline) {loadedLaneBatch = cpuBatch})
                      (laneEvidenceSet clean)
              assertBool
                "the lane mismatch was not reported by the binding check"
                ( renderBindingFailure (BindingMismatch BindingJournalLane "linux-cpu" "linux-cuda")
                    `elem` rowCheckFailures BindingCheck crossed "PPO/cartpole"
                )
    , testCase "a shorter evidence set is reported, and its missing row has no evidence to grade" $
        withBaseline loaded $ \baseline ->
          case ProductMatrix.projectProductRows LinuxCUDA (dropLast ProductMatrix.allProductRows) of
            Plan.Failure errors -> assertFailure ("slice projection failed: " <> show errors)
            Plan.Success sliceBatch -> do
              full <- laneEvidenceAfter baseline "PPO/cartpole" id
              assertLaneEvidenceCoverage full @?= []
              sliceSet <-
                either
                  (assertFailure . ("slice did not join: " <>) . show)
                  pure
                  ( joinModelEvidence
                      sliceBatch
                      (filter ((/= "hyperparameter-tuning") . rmeRowId) (baselineRaw baseline))
                  )
              let short = LaneEvidence (baselineLane baseline) sliceSet
              assertLaneEvidenceCoverage short
                @?= ["evidence set row order or coverage differs from the validated projection"]
              rowCheckFailures ConvergenceCheck short "hyperparameter-tuning"
                @?= ["no admitted evidence for row hyperparameter-tuning"]
    , testCase "a row absent from the projection is reported by every check, not graded" $
        withBaseline loaded $ \baseline ->
          case ProductMatrix.projectProductRows LinuxCUDA (dropLast ProductMatrix.allProductRows) of
            Plan.Failure errors -> assertFailure ("slice projection failed: " <> show errors)
            Plan.Success sliceBatch -> do
              full <- laneEvidenceAfter baseline "PPO/cartpole" id
              checksOf full "hyperparameter-tuning" @?= [(check, []) | check <- allRowChecks]
              -- The evidence set still holds hyperparameter-tuning; only the batch
              -- it is graded against no longer projects it.
              let unprojected =
                    LaneEvidence
                      ((baselineLane baseline) {loadedLaneBatch = sliceBatch})
                      (laneEvidenceSet full)
              checksOf unprojected "hyperparameter-tuning"
                @?= [ (check, ["no validated projection for row hyperparameter-tuning"])
                    | check <- allRowChecks
                    ]
    ]

-- | The registry must project, for a lane, to exactly its rows in order.
registryOrderControls :: TestTree
registryOrderControls =
  testGroup
    "registry projection order guard"
    [ testCase "a reordered registry is reported as a row-order difference" $ do
        assertRegistryCoverageOf LinuxCPU ProductMatrix.allProductRows @?= []
        assertRegistryCoverageOf LinuxCPU (reverse ProductMatrix.allProductRows)
          @?= ["projection row order differs from the registry"]
    ]

dropLast :: [value] -> [value]
dropLast values = take (length values - 1) values

-- ---------------------------------------------------------------------------
-- Identity fields at the mint boundary

-- | Offer a raw view straight to the mint, bypassing the join whose plan, lane,
-- and contract checks would otherwise answer first, and return the typed reasons
-- it was refused. 'Left' always carries at least one reason, so an empty list
-- means the view minted.
mintRefusals :: ProductMatrix.SomeProductProjection -> RawModelEvidence -> [RowEvidenceError]
mintRefusals (ProductMatrix.SomeProductProjection _ projection) raw =
  either NonEmpty.toList (const []) (refineModelRowEvidence projection raw)

onInvocation
  :: (RawInvocationIdentity -> RawInvocationIdentity)
  -> RawModelEvidence
  -> RawModelEvidence
onInvocation change raw =
  raw
    { rmeCompletion =
        (rmeCompletion raw) {rciInvocation = change <$> rciInvocation (rmeCompletion raw)}
    }

-- | Each case corrupts exactly one identity field of the real PPO/cartpole view
-- and states the one typed mismatch it must produce. The expected values come
-- from the validated projection and from another real row, never from the
-- mutated value.
identityCases
  :: [(String, Baseline -> IO (RawModelEvidence -> RawModelEvidence, [BindingFailure]))]
identityCases =
  [
    ( "row id"
    , \_ ->
        pure
          ( \raw -> raw {rmeRowId = "A2C/cartpole"}
          , [BindingMismatch BindingRowId "PPO/cartpole" "A2C/cartpole"]
          )
    )
  ,
    ( "journal PlanId"
    , \baseline -> do
        expected <- someProjectionPlanId <$> projectionFor baseline "PPO/cartpole"
        other <- rmePlanId <$> rawRow baseline "A2C/cartpole"
        pure
          ( \raw -> raw {rmePlanId = other}
          , [BindingMismatch BindingJournalPlan (Plan.planIdText expected) (Plan.planIdText other)]
          )
    )
  ,
    ( "journal lane"
    , \_ ->
        pure
          ( \raw -> raw {rmeLane = LinuxCPU}
          , [BindingMismatch BindingJournalLane "linux-cuda" "linux-cpu"]
          )
    )
  ,
    ( "journal experiment hash"
    , \baseline -> do
        expected <- someProjectionExperiment <$> projectionFor baseline "PPO/cartpole"
        pure
          ( \raw -> raw {rmeExperimentHash = "product-row-other"}
          , [BindingMismatch BindingJournalExperiment expected "product-row-other"]
          )
    )
  ,
    ( "contract digest"
    , \baseline -> do
        expected <- rmeContractDigest <$> rawRow baseline "PPO/cartpole"
        other <- rmeContractDigest <$> rawRow baseline "A2C/cartpole"
        pure
          ( \raw -> raw {rmeContractDigest = other}
          , [BindingMismatch BindingContractDigest expected other]
          )
    )
  ,
    ( "invocation PlanId"
    , \baseline -> do
        expected <- someProjectionPlanId <$> projectionFor baseline "PPO/cartpole"
        other <- rmePlanId <$> rawRow baseline "A2C/cartpole"
        pure
          ( onInvocation (\invocation -> invocation {riiPlanId = other})
          , [BindingMismatch BindingInvocationPlan (Plan.planIdText expected) (Plan.planIdText other)]
          )
    )
  ,
    ( "invocation lane"
    , \_ ->
        pure
          ( onInvocation (\invocation -> invocation {riiSubstrate = LinuxCPU})
          , [BindingMismatch BindingInvocationLane "linux-cuda" "linux-cpu"]
          )
    )
  ,
    ( "completion journal digest (malformed)"
    , \_ ->
        pure
          ( \raw -> raw {rmeCompletionJournalDigest = "abc"}
          , [BindingDigestMalformed BindingCompletionJournalDigest "abc"]
          )
    )
  ,
    ( "completion journal digest (upper-case hex is not canonical)"
    , \_ ->
        pure
          ( \raw -> raw {rmeCompletionJournalDigest = Text.replicate 64 "A"}
          , [BindingDigestMalformed BindingCompletionJournalDigest (Text.replicate 64 "A")]
          )
    )
  ,
    ( "completion journal digest (65 hex characters is not canonical)"
    , \_ ->
        pure
          ( \raw -> raw {rmeCompletionJournalDigest = Text.replicate 65 "a"}
          , [BindingDigestMalformed BindingCompletionJournalDigest (Text.replicate 65 "a")]
          )
    )
  ,
    ( "measured digest (malformed, and not the digest of the completion)"
    , \baseline -> do
        recomputed <- rmeRecomputedMeasuredDigest <$> rawRow baseline "PPO/cartpole"
        pure
          ( \raw -> raw {rmeMeasuredDigest = "abc"}
          ,
            [ BindingDigestMalformed BindingMeasuredDigest "abc"
            , BindingMismatch BindingMeasuredDigest recomputed "abc"
            ]
          )
    )
  ]

identityControls :: IO (Either String Baseline) -> TestTree
identityControls loaded =
  testGroup
    "identity fields are compared individually at the mint boundary"
    ( testCase "every row's own raw view mints against its own validated projection" ownViewsMint
        : testCase
          "evidence re-checked against another row's projection reports the seed cohort difference"
          seedCohortRecheck
        : [ testCase ("offering a wrong " <> label <> " is one typed mismatch and nothing else") $
              withBaseline loaded $ \baseline -> do
                projection <- projectionFor baseline "PPO/cartpole"
                raw <- rawRow baseline "PPO/cartpole"
                (mutation, expected) <- expectation baseline
                mintRefusals projection (mutation raw) @?= fmap RowBindingRejected expected
          | (label, expectation) <- identityCases
          ]
    )
 where
  ownViewsMint =
    withBaseline loaded $ \baseline -> do
      refusals <-
        traverse
          ( \rawView -> do
              projection <- projectionFor baseline (rmeRowId rawView)
              pure [(rmeRowId rawView, reason) | reason <- mintRefusals projection rawView]
          )
          (baselineRaw baseline)
      concat refusals @?= []
  -- Every SL row plans its own seed (1001, 1002, ...), so evidence for one SL
  -- row offered against another SL row's projection must name both seeds.
  seedCohortRecheck =
    withBaseline loaded $ \baseline -> do
      set <- joinedSet baseline (baselineRaw baseline)
      evidence <-
        maybe
          (assertFailure "no mnist-shallow-mlp evidence")
          pure
          (lookupModelEvidence "mnist-shallow-mlp" set)
      own <- projectionFor baseline "mnist-shallow-mlp"
      other <- projectionFor baseline "mnist-deep-mlp"
      assertSomeModelBinding own evidence @?= []
      let failures = assertSomeModelBinding other evidence
      assertBool
        ("the planned seed 1002 was not reported missing: " <> show failures)
        (BindingSeedCohort (MissingSeedEvidence 1002) `elem` failures)
      assertBool
        ("the observed seed 1001 was not reported unplanned: " <> show failures)
        (BindingSeedCohort (UnplannedSeedEvidence 1001) `elem` failures)

-- ---------------------------------------------------------------------------
-- Closed-rule boundaries

-- | The neighbouring representable doubles of a positive finite number.
nextUp, nextDown :: Double -> Double
nextUp value = castWord64ToDouble (castDoubleToWord64 value + 1)
nextDown value = castWord64ToDouble (castDoubleToWord64 value - 1)

boundaryControls :: TestTree
boundaryControls =
  testGroup
    "criterion and bound boundaries are inclusive and exact"
    [ testCase "an at-least criterion passes on its threshold and fails one step below" $ do
        let atLeast = criterion "m" Budget.RawCriterionAtLeast 0.75
        ExternalBars.externalCriterionPasses atLeast 0.75 @?= True
        ExternalBars.externalCriterionPasses atLeast (nextUp 0.75) @?= True
        ExternalBars.externalCriterionPasses atLeast (nextDown 0.75) @?= False
    , testCase "an at-most criterion passes on its threshold and fails one step above" $ do
        let atMost = criterion "m" Budget.RawCriterionAtMost 0.05
        ExternalBars.externalCriterionPasses atMost 0.05 @?= True
        ExternalBars.externalCriterionPasses atMost (nextDown 0.05) @?= True
        ExternalBars.externalCriterionPasses atMost (nextUp 0.05) @?= False
    , testCase "an exclusion criterion rejects the sentinel band, symmetric and edge-inclusive" $ do
        -- Sentinel 0.5, tolerance 0.125 (exactly representable), threshold 0.25.
        let band = criterion "m" (Budget.RawCriterionAtLeastExcluding 0.5 0.125) 0.25
            passes = ExternalBars.externalCriterionPasses band
        passes 0.5 @?= False
        -- The band is excluded up to and including its edges, on both sides.
        passes 0.625 @?= False
        passes 0.375 @?= False
        passes (nextUp 0.625) @?= True
        passes (nextDown 0.375) @?= True
        passes 0.75 @?= True
        -- The threshold itself is inclusive, one step below it is not.
        passes 0.25 @?= True
        passes (nextDown 0.25) @?= False
    , testCase "the comparison goal follows the rule" $ do
        ExternalBars.externalCriterionGoal (criterion "m" Budget.RawCriterionAtLeast 1.0)
          @?= Budget.MetricMaximise
        ExternalBars.externalCriterionGoal (criterion "m" Budget.RawCriterionAtMost 1.0)
          @?= Budget.MetricMinimise
        ExternalBars.externalCriterionGoal
          (criterion "m" (Budget.RawCriterionAtLeastExcluding 0.5 1.0e-12) 1.0)
          @?= Budget.MetricMaximise
    , testCase "performance bounds are inclusive at their limit" $ do
        ExternalBars.performanceBoundHolds (ExternalBars.AtLeast 5) 5 @?= True
        ExternalBars.performanceBoundHolds (ExternalBars.AtLeast 5) 4 @?= False
        ExternalBars.performanceBoundHolds (ExternalBars.AtMost 5) 5 @?= True
        ExternalBars.performanceBoundHolds (ExternalBars.AtMost 5) 6 @?= False
    ]

-- ---------------------------------------------------------------------------
-- Registry drift, per component

driftControls :: TestTree
driftControls =
  testGroup
    "registry bar drift is detected per component"
    [ testCase "a bar equal to the canonical criterion is not drift" $
        registryBarDrift
          ppoCartpoleCriterion
          (Convergence.mkConvergenceBar "median_final_reward" Budget.MetricMaximise 475.0 25.0)
          @?= []
    , testCase "a renamed metric alone is drift" $
        driftOf (Convergence.mkConvergenceBar "avg_reward" Budget.MetricMaximise 475.0 25.0)
    , testCase "a flipped goal alone is drift" $ do
        -- Target 425 plus slack 25 gives the same threshold (450) with the goal flipped.
        let flipped = Convergence.mkConvergenceBar "median_final_reward" Budget.MetricMinimise 425.0 25.0
        Convergence.convergenceThreshold flipped @?= 450.0
        driftOf flipped
    , testCase "a moved threshold alone is drift" $
        driftOf (Convergence.mkConvergenceBar "median_final_reward" Budget.MetricMaximise 475.0 100.0)
    ]
 where
  driftOf bar =
    registryBarDrift ppoCartpoleCriterion bar @?= [RegistryBarDrift ppoCartpoleCriterion bar]

-- ---------------------------------------------------------------------------
-- Exclusion parameters

exclusionParameterControls :: IO (Either String Baseline) -> TestTree
exclusionParameterControls loaded =
  testGroup
    "AlphaZero exclusion rule parameters"
    [ testCase "a non-finite exclusion sentinel or tolerance cannot become evidence" $
        withBaseline loaded $ \baseline -> do
          finalQualityAfter baseline "connect4" id >>= (@?= [])
          let withRule rule =
                mutateFinal (fmap (\observation -> observation {Budget.rawCriterionRule = rule}))
              rejectedBy rule =
                rowRejection baseline "connect4" (withRule rule)
              nan = 0 / 0
              infinity = 1 / 0
          rejectedBy (Budget.RawCriterionAtLeastExcluding nan 1.0e-12)
            >>= (@?= [RowNonFiniteEvidence 42 "arena_win_rate" "exclusion sentinel"])
          rejectedBy (Budget.RawCriterionAtLeastExcluding 0.5 infinity)
            >>= (@?= [RowNonFiniteEvidence 42 "arena_win_rate" "exclusion tolerance"])
          rejectedBy (Budget.RawCriterionAtLeastExcluding nan infinity)
            >>= ( @?=
                    [ RowNonFiniteEvidence 42 "arena_win_rate" "exclusion sentinel"
                    , RowNonFiniteEvidence 42 "arena_win_rate" "exclusion tolerance"
                    ]
                )
    ]

-- | Real rows graded one representable step either side of their bar.
evidenceBoundaryControls :: IO (Either String Baseline) -> TestTree
evidenceBoundaryControls loaded =
  testGroup
    "graded rows at their boundaries"
    [ testCase "a win rate just inside the recorded exclusion tolerance is excluded, just outside passes" $
        withBaseline loaded $ \baseline -> do
          inside <- finalQualityAfter baseline "connect4" (mutateFinal (fmap (setValue (0.5 + 5.0e-13))))
          inside @?= [BelowBar "arena_win_rate" (0.5 + 5.0e-13) alphaZeroCriterion]
          finalQualityAfter baseline "connect4" (mutateFinal (fmap (setValue (0.5 + 2.0e-12))))
            >>= (@?= [])
    , testCase "an at-most companion metric passes on its threshold and fails one step above" $
        withBaseline loaded $ \baseline -> do
          let distance value =
                mutateFinal
                  ( fmap
                      ( \observation ->
                          if Budget.rawCriterionName observation == "achieved_goal_distance"
                            then setValue value observation
                            else observation
                      )
                  )
          finalQualityAfter baseline "HER/goal-reaching" (distance 0.05) >>= (@?= [])
          finalQualityAfter baseline "HER/goal-reaching" (distance (nextUp 0.05))
            >>= ( @?=
                    [ BelowBar
                        "achieved_goal_distance"
                        (nextUp 0.05)
                        (criterion "achieved_goal_distance" Budget.RawCriterionAtMost 0.05)
                    ]
                )
    ]

-- ---------------------------------------------------------------------------
-- Performance grading

performanceGradingControls :: TestTree
performanceGradingControls =
  testGroup
    "performance grading of recorded work counts"
    [ testCase "a requirement whose metric the run did not record is unmeasured, never a pass" $ do
        let requirement = ExternalBars.PerformanceRequirement ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 5)
        gradePerformanceObservations 42 [requirement] []
          @?= [PerformanceMetricUnmeasured 42 ExternalBars.PerformanceExamplesSeen]
        -- Another metric's count cannot stand in for the missing one.
        gradePerformanceObservations 42 [requirement] [(ExternalBars.PerformanceEnvironmentTransitions, 10)]
          @?= [PerformanceMetricUnmeasured 42 ExternalBars.PerformanceExamplesSeen]
    , testCase "a recorded count is graded against its own metric's bound" $ do
        let atLeast = ExternalBars.PerformanceRequirement ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 5)
            atMost =
              ExternalBars.PerformanceRequirement
                ExternalBars.PerformanceEnvironmentTransitions
                (ExternalBars.AtMost 5)
            observed = [(ExternalBars.PerformanceExamplesSeen, 5), (ExternalBars.PerformanceEnvironmentTransitions, 5)]
        gradePerformanceObservations 42 [atLeast, atMost] observed @?= []
        gradePerformanceObservations
          42
          [atLeast, atMost]
          [(ExternalBars.PerformanceExamplesSeen, 4), (ExternalBars.PerformanceEnvironmentTransitions, 6)]
          @?= [ PerformanceBoundViolated 42 ExternalBars.PerformanceExamplesSeen (ExternalBars.AtLeast 5) 4
              , PerformanceBoundViolated 42 ExternalBars.PerformanceEnvironmentTransitions (ExternalBars.AtMost 5) 6
              ]
    ]

-- ---------------------------------------------------------------------------
-- Seed cohorts larger than one

-- | The baseline's real PPO/cartpole seed evidence, the template every
-- multi-seed fixture below is cut from.
seedTemplate :: Baseline -> IO RawSeedEvidence
seedTemplate baseline = do
  raw <- rawRow baseline "PPO/cartpole"
  case rmeSeeds raw of
    [seed] -> pure seed
    other ->
      assertFailure
        ("expected a singleton PPO/cartpole cohort, observed " <> show (length other) <> " seeds")

withSeed :: Word64 -> RawSeedEvidence -> RawSeedEvidence
withSeed seed evidence = evidence {rseSeed = seed}

withReward :: Double -> RawSeedEvidence -> RawSeedEvidence
withReward value evidence =
  evidence
    { rseFinalQuality =
        (rseFinalQuality evidence)
          { rfqObservations = fmap (setValue value) (rfqObservations (rseFinalQuality evidence))
          }
    }

cohortControls :: IO (Either String Baseline) -> TestTree
cohortControls loaded =
  testGroup
    "k > 1: a three-seed plan cohort minted end to end"
    [ testCase "exact coverage mints one evidence value per seed, in the given order" $
        withBaseline loaded $ \baseline -> do
          cohort <- threeSeedCohort
          template <- seedTemplate baseline
          case refineSeedCohort cohort [withSeed seed template | seed <- [3, 1, 2]] of
            Left errors -> assertFailure ("exact coverage was refused: " <> show errors)
            Right seeds -> fmap seedEvidenceSeed (NonEmpty.toList seeds) @?= [3, 1, 2]
    , testCase "a seed gap, an extra seed, a duplicate, and an empty cohort are each refused by name" $
        withBaseline loaded $ \baseline -> do
          cohort <- threeSeedCohort
          template <- seedTemplate baseline
          let coverage = RowBindingRejected . BindingSeedCohort
              seedsOf = fmap (`withSeed` template)
          refusal cohort (seedsOf [1, 3]) >>= (@?= [coverage (MissingSeedEvidence 2)])
          refusal cohort (seedsOf [1, 2, 3, 4]) >>= (@?= [coverage (UnplannedSeedEvidence 4)])
          refusal cohort (seedsOf [1, 2, 2, 3]) >>= (@?= [coverage (DuplicateSeedEvidence 2)])
          refusal cohort []
            >>= ( @?=
                    [ coverage EmptySeedCohort
                    , coverage (MissingSeedEvidence 1)
                    , coverage (MissingSeedEvidence 2)
                    , coverage (MissingSeedEvidence 3)
                    ]
                )
    , testCase "a defect names the seed it belongs to, whatever the cohort size" $
        withBaseline loaded $ \baseline -> do
          cohort <- threeSeedCohort
          template <- seedTemplate baseline
          let seedsWith seedTwo seedThree = [withSeed 1 template, seedTwo, seedThree]
              two = withSeed 2 template
              three = withSeed 3 template
          refusal cohort (seedsWith (withReward (0 / 0) two) three)
            >>= (@?= [RowNonFiniteEvidence 2 "median_final_reward" "value"])
          refusal
            cohort
            (seedsWith two three {rseLearning = (rseLearning three) {rltChannel = FinalEvaluationChannel}})
            >>= (@?= [RowChannelSubstituted 3 LearningSlot FinalEvaluationChannel])
    , testCase "coverage and per-seed defects accumulate in one refusal" $
        withBaseline loaded $ \baseline -> do
          cohort <- threeSeedCohort
          template <- seedTemplate baseline
          refusal cohort [withReward (0 / 0) (withSeed 1 template), withSeed 2 template]
            >>= ( @?=
                    [ RowBindingRejected (BindingSeedCohort (MissingSeedEvidence 3))
                    , RowNonFiniteEvidence 1 "median_final_reward" "value"
                    ]
                )
    , testCase "an incomplete cohort reports its structural gap and no cohort statistic" $ do
        -- Seeds 1 and 3 sit far below the 0.5 bar and seed 2 recorded nothing. The
        -- gap is the defect: a statistic over the two remaining seeds would grade
        -- a cohort the plan never asked for.
        let bar = criterion "test_accuracy" Budget.RawCriterionAtLeast 0.5
            observation =
              Budget.RawConvergenceObservation "test_accuracy" Budget.RawCriterionAtLeast 0.5
        gradeCohortCriteria (bar :| []) [(1, [observation 0.1]), (2, []), (3, [observation 0.2])]
          @?= [MissingMetric 2 "test_accuracy"]
    , testCase "the cohort statistic of minted seeds is their median, not a mean or a worst seed" $
        withBaseline loaded $ \baseline -> do
          -- Median 500 clears the 450 bar although one seed is far below it ...
          gradedCohort baseline [500.0, 500.0, 100.0] >>= (@?= [])
          -- ... and median 100 fails it although one seed is far above it.
          gradedCohort baseline [100.0, 100.0, 500.0]
            >>= (@?= [BelowBar "median_final_reward" 100.0 ppoCartpoleCriterion])
    ]

-- | Why a defective raw cohort was refused.
refusal :: Plan.SeedCohort -> [RawSeedEvidence] -> IO [RowEvidenceError]
refusal cohort seeds =
  case refineSeedCohort cohort seeds of
    Left errors -> pure (NonEmpty.toList errors)
    Right _ -> assertFailure "a defective seed cohort was minted"

-- | Mint a three-seed cohort with the given rewards and grade it against the
-- canonical PPO/cartpole criterion.
gradedCohort :: Baseline -> [Double] -> IO [FinalQualityFailure]
gradedCohort baseline rewards = do
  cohort <- threeSeedCohort
  template <- seedTemplate baseline
  case refineSeedCohort
    cohort
    [withReward reward (withSeed seed template) | (seed, reward) <- zip [1, 2, 3] rewards] of
    Left errors -> assertFailure ("cohort was refused: " <> show errors)
    Right seeds ->
      pure
        ( gradeCohortCriteria
            (ppoCartpoleCriterion :| [])
            [ (seedEvidenceSeed seed, finalQualityObservations (seedEvidenceFinalQuality seed))
            | seed <- NonEmpty.toList seeds
            ]
        )

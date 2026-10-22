{-# LANGUAGE OverloadedStrings #-}

-- Complete recorded-DATA controls. Scripted scalar callbacks are offline
-- numerical fixtures, never learned models, real provider witnesses or origin.
module NativeHerLearningPolicy (nativeHerLearningPolicyTests) where

import Control.Monad (forM, forM_)
import Data.Bits (xor)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, sort)
import Data.Maybe (fromMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp (MlpForward (..), MlpParams (..))
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeHerLearningPolicy qualified as P
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.Framework qualified as Framework
import JitML.RL.NativeHerEvaluation qualified as E
import JitML.RL.NativeHerReferences qualified as R
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget qualified as Budget

data Member = Member
  { memberIndex :: !Int
  , memberInitial :: !E.RawNativeHerEvaluation
  , memberPerfect :: !E.RawNativeHerEvaluation
  , memberLowSuccess :: !E.RawNativeHerEvaluation
  , memberLowDistance :: !E.RawNativeHerEvaluation
  }

-- Only immutable completed observations are pooled. No stage/capsule, pending
-- continuation or stateful callback is shared between unordered Tasty leaves.
data Fixture = Fixture
  { fixtureSchedule :: !R.NativeHerGoalSchedule
  , fixtureReferences :: !R.NativeHerReferenceFamily
  , fixtureMembers :: ![Member]
  , fixtureTied :: !E.RawNativeHerEvaluation
  , fixtureRejected :: !E.RawNativeHerEvaluation
  }

right :: (Show problem) => Either problem value -> IO value
right result = case result of
  Left problem -> assertFailure (show problem) >> fail "unreachable"
  Right value -> pure value

expectLeft :: Text -> Either Text value -> Assertion
expectLeft expected result = case result of
  Left actual ->
    assertBool
      ("expected reason " <> Text.unpack expected <> ", got " <> Text.unpack actual)
      (expected `Text.isInfixOf` actual)
  Right _ -> assertFailure ("unexpected accepted DATA, expected " <> Text.unpack expected)

firstOrFail :: [value] -> IO value
firstOrFail values = case values of
  first : _ -> pure first
  [] -> assertFailure "frozen complete fixture unexpectedly empty" >> fail "unreachable"

mapFirst :: (value -> value) -> [value] -> [value]
mapFirst change values = case values of
  first : rest -> change first : rest
  [] -> []

{-# NOINLINE vectorBits #-}
vectorBits :: VU.Vector Double -> [Word64]
vectorBits = map castDoubleToWord64 . VU.toList
{-# NOINLINE toggleSign #-}
toggleSign :: Word64 -> Double -> Double
toggleSign mask value = castWord64ToDouble (castDoubleToWord64 value `xor` mask)

configFor :: Int -> Her.HerTrainConfig
configFor index = Her.defaultHerTrainConfig {Her.herSeed = 42 + index, Her.herHiddenUnits = 2}

-- The small hidden width is an explicit numerical DATA fixture. No execution
-- of the canonical learner or budget-complete training is asserted here.
runScript
  :: R.NativeHerGoalSchedule
  -> Int
  -> Bool
  -> [R.NativeHerReferenceOutcome]
  -> IO E.RawNativeHerEvaluation
runScript schedule index tieLater outcomes = do
  remaining <- newIORef (concatMap R.nativeHerOutcomeConsumedActions outcomes)
  witnessCalls <- newIORef (0 :: Int)
  let config = configFor index
      params = Her.initialHerParams config
      device =
        pureReferenceMlpDevice
          { mlpdForward = \_ input -> do
              actions <- readIORef remaining
              case actions of
                [] -> pure (Left "offline action prefix unexpectedly exhausted")
                action : rest -> do
                  writeIORef remaining rest
                  let output = VU.generate 6 (\slot -> if slot == action || (tieLater && slot > action) then 1 else 0)
                  pure (Right (MlpForward input VU.empty VU.empty output))
          , mlpdExecutionWitness = modifyIORef' witnessCalls (+ 1) >> pure (Right Nothing)
          }
  observed <- E.evaluateNativeHerPolicy device schedule config params
  E.nativeHerEvaluationStatus observed @?= E.NativeHerEvaluationComplete
  E.nativeHerEvaluationOutcomes observed @?= outcomes
  readIORef remaining >>= (@?= [])
  readIORef witnessCalls >>= (@?= 0)
  E.nativeHerObservedForwardCalls observed
    @?= sum (map (toInteger . R.nativeHerOutcomeSteps) outcomes)
  pure observed

perfectOutcome :: R.RawNativeHerGoalCase -> IO R.NativeHerReferenceOutcome
perfectOutcome one = do
  let goal = R.rawNativeHerGoal one
      flips = [index | (index, value) <- zip [0 ..] (VU.toList goal), value == 1]
  outcome <- right (R.evaluateHerSequenceFixture goal (flips <> replicate (6 - length flips) 0))
  R.nativeHerOutcomeSuccess outcome @?= True
  R.nativeHerOutcomeHammingDistance outcome @?= 0
  pure (outcome {R.nativeHerOutcomeCaseId = R.rawNativeHerCaseId one})

-- Select public-rule fixture traces, not a product controller or winning seed.
-- All sequences already belong to the fixed complete reference enumeration.
worstOutcome :: [R.NativeHerReferenceOutcome] -> IO R.NativeHerReferenceOutcome
worstOutcome values = do
  first <- firstOrFail values
  pure
    ( foldl'
        ( \old candidate ->
            if R.nativeHerOutcomeHammingDistance candidate > R.nativeHerOutcomeHammingDistance old
              then candidate
              else old
        )
        first
        values
    )

setup :: IO Fixture
setup = do
  spec <- right R.canonicalNativeHerReferenceSpec
  schedule <- right (R.generateNativeHerGoalSchedule spec)
  references <- right (R.evaluateNativeHerReferenceFamily schedule)
  length (R.nativeHerObservedReferences references) @?= 46656
  let cases = R.nativeHerScheduleCases schedule
      outcomesAt index =
        [ outcome
        | reference <- R.nativeHerObservedReferences references
        , outcome <- R.nativeHerObservedOutcomes reference
        , R.nativeHerOutcomeCaseId outcome == index
        ]
  perfect <- traverse perfectOutcome cases
  worst <- traverse (worstOutcome . outcomesAt . R.rawNativeHerCaseId) cases
  -- Four genuine one-bit-away failures yield 16/20 successes and low mean
  -- distance. Selection is fixed by canonical case order and public state
  -- geometry; it never chooses a training run, seed or acceptance criterion.
  let oneAway =
        [ (R.rawNativeHerCaseId one, outcome)
        | one <- cases
        , Just outcome <-
            [find ((== 1) . R.nativeHerOutcomeHammingDistance) (outcomesAt (R.rawNativeHerCaseId one))]
        ]
      selectedOneAway = take 4 oneAway
  length selectedOneAway @?= 4
  let lowSuccess =
        [ fromMaybe outcome (lookup (R.nativeHerOutcomeCaseId outcome) selectedOneAway)
        | outcome <- perfect
        ]
      lowDistance = take 17 perfect <> drop 17 worst
  members <- forM [0 .. 4] $ \index -> do
    initial <- runScript schedule index False worst
    final <- runScript schedule index False perfect
    lowS <- runScript schedule index False lowSuccess
    lowD <- runScript schedule index False lowDistance
    pure (Member index initial final lowS lowD)
  tied <- runScript schedule 0 True perfect
  let failedDevice = pureReferenceMlpDevice {mlpdForward = \_ _ -> pure (Left "actual offline callback rejection")}
      config = configFor 0
  rejected <- E.evaluateNativeHerPolicy failedDevice schedule config (Her.initialHerParams config)
  pure (Fixture schedule references members tied rejected)

observations :: (Member -> E.RawNativeHerEvaluation) -> Fixture -> [P.NativeHerSeedObservation]
observations final fixture =
  [ P.NativeHerSeedObservation
      (memberIndex member)
      (fromIntegral (42 + memberIndex member))
      (memberInitial member)
      (final member)
  | member <- fixtureMembers fixture
  ]

perfectInputs :: Fixture -> [P.NativeHerSeedObservation]
perfectInputs = observations memberPerfect

compareInputs :: Fixture -> [P.NativeHerSeedObservation] -> IO P.NativeHerCohortComparison
compareInputs fixture = right . P.compareNativeHerCohort (fixtureReferences fixture)

editFinal
  :: (E.RawNativeHerEvaluation -> E.RawNativeHerEvaluation)
  -> [P.NativeHerSeedObservation]
  -> [P.NativeHerSeedObservation]
editFinal change = mapFirst (\one -> one {P.nativeHerObservedFinal = change (P.nativeHerObservedFinal one)})

editOutcome
  :: (R.NativeHerReferenceOutcome -> R.NativeHerReferenceOutcome)
  -> E.RawNativeHerEvaluation
  -> E.RawNativeHerEvaluation
editOutcome change raw = raw {E.nativeHerEvaluationOutcomes = mapFirst change (E.nativeHerEvaluationOutcomes raw)}

editForward
  :: (E.NativeHerForwardObservation -> E.NativeHerForwardObservation)
  -> E.RawNativeHerEvaluation
  -> E.RawNativeHerEvaluation
editForward change raw = raw {E.nativeHerEvaluationForwards = mapFirst change (E.nativeHerEvaluationForwards raw)}

rejectFinal
  :: Fixture -> Text -> (E.RawNativeHerEvaluation -> E.RawNativeHerEvaluation) -> Assertion
rejectFinal fixture reason change =
  expectLeft
    reason
    (P.compareNativeHerCohort (fixtureReferences fixture) (editFinal change (perfectInputs fixture)))

editReference
  :: (R.NativeHerReferenceObservation -> R.NativeHerReferenceObservation)
  -> R.NativeHerReferenceFamily
  -> R.NativeHerReferenceFamily
editReference change family = family {R.nativeHerObservedReferences = mapFirst change (R.nativeHerObservedReferences family)}

rejectReference
  :: Fixture -> Text -> (R.NativeHerReferenceFamily -> R.NativeHerReferenceFamily) -> Assertion
rejectReference fixture reason change =
  expectLeft
    reason
    (P.compareNativeHerCohort (change (fixtureReferences fixture)) (perfectInputs fixture))

relationBits :: P.NativeHerLearningRelation -> [Bool]
relationBits relation =
  [ P.nativeHerRelationInitialSuccessGain relation
  , P.nativeHerRelationInitialDistanceGain relation
  , P.nativeHerRelationSuccessReference relation
  , P.nativeHerRelationDistanceReference relation
  ]

stats :: Int -> Rational -> P.NativeHerLearningStatisticsData
stats = P.NativeHerLearningStatisticsData

assertFindings :: Text -> [Text] -> Assertion
assertFindings wanted actual = assertBool ("missing finding " <> Text.unpack wanted) (any (Text.isInfixOf wanted) actual)

qualityBits :: E.RawNativeHerEvaluation -> IO (Double, Double)
qualityBits raw = do
  let outcomes = E.nativeHerEvaluationOutcomes raw
      count = length outcomes
      successes = length (filter R.nativeHerOutcomeSuccess outcomes)
      rewards = map ((1.0 -) . R.nativeHerOutcomeNormalizedDistance) outcomes
  evaluation <-
    right
      ( Framework.mkEvaluationSet
          (fromIntegral count)
          [ ( fromIntegral (R.nativeHerOutcomeCaseId one)
            , 1.0 - R.nativeHerOutcomeNormalizedDistance one
            , R.nativeHerOutcomeSteps one
            , R.nativeHerOutcomeTerminated one
            )
          | one <- outcomes
          ]
      )
  -- This explicit observer pins the legacy mean's operation order. Exact
  -- learning distance uses per-binary64 Rational and is deliberately separate.
  castDoubleToWord64 (Framework.evaluationSetMeanReward evaluation)
    @?= castDoubleToWord64 (sum (map (/ fromIntegral count) rewards))
  pure
    ( max 0 (min 1 (fromIntegral successes / fromIntegral count))
    , max 0 (min 1 (1.0 - Framework.evaluationSetMeanReward evaluation))
    )

qualityPasses :: (Double, Double) -> IO (Bool, Bool)
qualityPasses (success, distance) = do
  successObserved <-
    right (Budget.remeasureCriterion success (Thresholds.hgmSuccessRate Thresholds.herGoalMetric))
  distanceObserved <-
    right
      (Budget.remeasureCriterion distance (Thresholds.hgmAchievedGoalDistance Thresholds.herGoalMetric))
  pure (Budget.convergencePassed successObserved, Budget.convergencePassed distanceObserved)

-- Keep total base drop at the three negative-fixture sites; no extra package
-- or partial tail is needed to remove a first element, including an empty list.
{- HLINT ignore nativeHerLearningPolicyTests "Use drop1" -}
nativeHerLearningPolicyTests :: TestTree
nativeHerLearningPolicyTests = withResource setup (const (pure ())) $ \getFixture ->
  testGroup
    "native HER five-run learning policy"
    [ testCase
        "complete fixed references and five actual offline evaluation traces pass the mathematical boundary"
        $ do
          fixture <- getFixture
          let supplied = perfectInputs fixture
          compared <- compareInputs fixture supplied
          P.nativeHerComparisonFailures compared @?= []
          P.nativeHerComparisonJointCount compared @?= 5
          P.nativeHerComparisonObservations compared @?= supplied
          P.nativeHerComparisonReferences compared @?= fixtureReferences fixture
          map P.nativeHerSeedComparisonIndex (P.nativeHerComparisonSeeds compared) @?= [0 .. 4]
          forM_ (P.nativeHerComparisonSeeds compared) $ \one -> do
            P.nativeHerSeedComparisonFinalSuccessCount one @?= 20
            P.nativeHerSeedComparisonFinalExactMeanDistance one @?= 0
            assertBool
              "both strict initial gains are real fixture inequalities"
              ( P.nativeHerSeedComparisonInitialSuccessCount one < 20
                  && P.nativeHerSeedComparisonInitialExactMeanDistance one > 0
              )
            P.nativeHerSeedComparisonJointLearning one @?= True
    , testCase "three same-seed successes pass with both finite non-improving members retained" $ do
        fixture <- getFixture
        let supplied =
              observations
                (\member -> if memberIndex member < 3 then memberPerfect member else memberInitial member)
                fixture
        compared <- compareInputs fixture supplied
        P.nativeHerComparisonJointCount compared @?= 3
        P.nativeHerComparisonFailures compared @?= []
        P.nativeHerComparisonObservations compared @?= supplied
        map P.nativeHerSeedComparisonJointLearning (P.nativeHerComparisonSeeds compared)
          @?= [True, True, True, False, False]
        forM_ (drop 3 (P.nativeHerComparisonSeeds compared)) $ \one ->
          assertFindings "paired initial" (P.nativeHerSeedComparisonFindings one)
    , testCase "two successes retain all five and fail the whole-five median and joint count" $ do
        fixture <- getFixture
        let supplied =
              observations
                (\member -> if memberIndex member < 2 then memberPerfect member else memberInitial member)
                fixture
        compared <- compareInputs fixture supplied
        P.nativeHerComparisonJointCount compared @?= 2
        P.nativeHerComparisonObservations compared @?= supplied
        assertFindings "fewer than three" (P.nativeHerComparisonFailures compared)
        assertFindings "whole-five" (P.nativeHerComparisonFailures compared)
    , testCase "four better auxiliaries cannot replace the predetermined failing served index zero" $ do
        fixture <- getFixture
        compared <-
          compareInputs
            fixture
            ( observations
                (\member -> if memberIndex member == 0 then memberInitial member else memberPerfect member)
                fixture
            )
        P.nativeHerComparisonJointCount compared @?= 4
        assertFindings "served index0 fails" (P.nativeHerComparisonFailures compared)
        assertBool
          "passing whole-five medians do not hide the served failure"
          (not (any (Text.isInfixOf "whole-five") (P.nativeHerComparisonFailures compared)))
    , testCase "all finite unchanged initial-final traces remain inspectable mathematical failures" $ do
        fixture <- getFixture
        let supplied = observations memberInitial fixture
        compared <- compareInputs fixture supplied
        P.nativeHerComparisonJointCount compared @?= 0
        P.nativeHerComparisonObservations compared @?= supplied
        length (P.nativeHerComparisonSeeds compared) @?= 5
        assertFindings "fewer than three" (P.nativeHerComparisonFailures compared)
    , testCase
        "unchanged success bar can independently fail despite strict learning and passing distance bar"
        $ do
          fixture <- getFixture
          compared <- compareInputs fixture (observations memberLowSuccess fixture)
          P.nativeHerComparisonJointCount compared @?= 5
          first <- firstOrFail (fixtureMembers fixture)
          actualQuality <- qualityBits (memberLowSuccess first)
          qualityPasses actualQuality >>= (@?= (False, True))
          assertFindings "whole-five success-quality" (P.nativeHerComparisonFailures compared)
          assertBool
            "distance quality independently passes"
            (not (any (Text.isInfixOf "whole-five distance-quality") (P.nativeHerComparisonFailures compared)))
    , testCase
        "unchanged distance bar can independently fail despite strict learning and passing success bar"
        $ do
          fixture <- getFixture
          compared <- compareInputs fixture (observations memberLowDistance fixture)
          P.nativeHerComparisonJointCount compared @?= 5
          first <- firstOrFail (fixtureMembers fixture)
          actualQuality <- qualityBits (memberLowDistance first)
          qualityPasses actualQuality >>= (@?= (True, False))
          assertFindings "whole-five distance-quality" (P.nativeHerComparisonFailures compared)
          assertBool
            "success quality independently passes"
            (not (any (Text.isInfixOf "whole-five success-quality") (P.nativeHerComparisonFailures compared)))
    , testCase
        "legacy metrics keep exact public mean operation order separate from exact learning distance"
        $ do
          fixture <- getFixture
          compared <- compareInputs fixture (observations memberLowSuccess fixture)
          forM_ (zip (fixtureMembers fixture) (P.nativeHerComparisonSeeds compared)) $ \(member, comparison) -> do
            let raw = memberLowSuccess member
                distances = map R.nativeHerOutcomeNormalizedDistance (E.nativeHerEvaluationOutcomes raw)
            (success, distance) <- qualityBits raw
            castDoubleToWord64 (P.nativeHerSeedComparisonLegacySuccessQuality comparison)
              @?= castDoubleToWord64 success
            castDoubleToWord64 (P.nativeHerSeedComparisonLegacyDistanceQuality comparison)
              @?= castDoubleToWord64 distance
            P.nativeHerSeedComparisonFinalExactMeanDistance comparison @?= sum (map toRational distances) / 20
          let successValues = sort (map P.nativeHerSeedComparisonLegacySuccessQuality (P.nativeHerComparisonSeeds compared))
              distanceValues = sort (map P.nativeHerSeedComparisonLegacyDistanceQuality (P.nativeHerComparisonSeeds compared))
          case (successValues, distanceValues) of
            ([_, _, success, _, _], [_, _, distance, _, _]) -> do
              P.nativeHerComparisonMedianSuccessQuality compared @?= success
              P.nativeHerComparisonMedianDistanceQuality compared @?= distance
            _ -> assertFailure "comparison omitted a finite member"
    , testCase
        "full child plans retain five seeded budgets while the fixed reference budget stays seedless"
        $ do
          fixture <- getFixture
          batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
          cohort <-
            maybe
              (assertFailure "canonical HER cohort missing" >> fail "unreachable")
              pure
              ( find
                  ((== "HER/goal-reaching") . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
                  (Cohort.nativeRlCohortBatchPlans batch)
              )
          let children = Cohort.nativeRlCohortPlanChildren cohort
              budget = R.nativeHerSpecTrainingBudget (R.nativeHerScheduleSpec (fixtureSchedule fixture))
          Budget.trainingBudgetSeed budget @?= Nothing
          map (Cohort.nativeSeedIndexValue . Cohort.nativeRlSeedPlanIndex) children @?= [0 .. 4]
          map Cohort.nativeRlSeedPlanSeed children @?= [42 .. 46]
          forM_ children $ \child -> do
            seeded <-
              right
                ( Budget.mkTrainingBudget
                    (Budget.trainingBudgetKind budget)
                    (Budget.trainingBudgetTargetUnits budget)
                    (Just (Cohort.nativeRlSeedPlanSeed child))
                )
            Cohort.nativeRlSeedPlanTrainingBudget child @?= seeded
    , testCase "maximum-only equality is allowed by the shared arithmetic after both strict initial gains" $ do
        relation <- right (P.compareNativeHerLearningStatisticsData (stats 0 1) (stats 20 0) (stats 20 0))
        relationBits relation @?= replicate 4 True
        P.nativeHerRelationJointLearning relation @?= True
    , testCase "already optimal initial statistics never pass either strict gain" $ do
        relation <- right (P.compareNativeHerLearningStatisticsData (stats 20 0) (stats 20 0) (stats 20 0))
        relationBits relation @?= [False, False, True, True]
        P.nativeHerRelationJointLearning relation @?= False
    , testCase "equal suboptimal reference values fail both reference predicates without epsilon" $ do
        relation <-
          right
            (P.compareNativeHerLearningStatisticsData (stats 0 1) (stats 19 (1 % 120)) (stats 19 (1 % 120)))
        relationBits relation @?= [True, True, False, False]
        P.nativeHerRelationJointLearning relation @?= False
    , testCase "each strict initial component and reference component is independently necessary" $ do
        let cases =
              [ (stats 10 (3 % 4), stats 10 (1 % 4), stats 9 (1 % 2), [False, True, True, True])
              , (stats 9 (1 % 4), stats 10 (1 % 4), stats 9 (1 % 2), [True, False, True, True])
              , (stats 0 1, stats 10 (1 % 4), stats 10 (1 % 2), [True, True, False, True])
              , (stats 0 1, stats 10 (1 % 4), stats 9 (1 % 4), [True, True, True, False])
              ]
        forM_ cases $ \(initial, final, reference, expected) -> do
          relation <- right (P.compareNativeHerLearningStatisticsData initial final reference)
          relationBits relation @?= expected
          P.nativeHerRelationJointLearning relation @?= False
    , testCase "scalar DATA rejects invalid ranges and inconsistent global endpoints in every position" $ do
        let valid = stats 10 (1 % 2)
            invalid =
              [ (stats (-1) (1 % 2), "success count")
              , (stats 21 (1 % 2), "success count")
              , (stats 10 ((-1) % 3), "mean distance")
              , (stats 10 (4 % 3), "mean distance")
              , (stats 20 (1 % 120), "endpoint pair")
              , (stats 19 0, "endpoint pair")
              ]
        forM_ invalid $ \(value, reason) -> do
          expectLeft reason (P.compareNativeHerLearningStatisticsData value valid valid)
          expectLeft reason (P.compareNativeHerLearningStatisticsData valid value valid)
          expectLeft reason (P.compareNativeHerLearningStatisticsData valid valid value)
    , testCase "tiny exact Rational improvement is retained and never replaced by a tolerance" $ do
        let tiny = 1 % (2 ^ (200 :: Int))
        relation <-
          right
            ( P.compareNativeHerLearningStatisticsData
                (stats 9 (1 % 2))
                (stats 10 (1 % 2 - tiny))
                (stats 9 (1 % 2))
            )
        relationBits relation @?= replicate 4 True
    , testCase
        "missing extra duplicate and reordered reference sequences are rejected before any model comparison"
        $ do
          fixture <- getFixture
          let refs = R.nativeHerObservedReferences (fixtureReferences fixture)
          first <- firstOrFail refs
          rejectReference fixture "all46656" (\family -> family {R.nativeHerObservedReferences = drop 1 refs})
          rejectReference
            fixture
            "all46656"
            (\family -> family {R.nativeHerObservedReferences = refs <> [first]})
          rejectReference
            fixture
            "sequence inventory"
            (\family -> family {R.nativeHerObservedReferences = first : first : drop 2 refs})
          rejectReference
            fixture
            "sequence inventory"
            (\family -> family {R.nativeHerObservedReferences = reverse refs})
    , testCase "reference raw action-rule state scalar summary and work changes fail public replay" $ do
        fixture <- getFixture
        let mutateOutcome change =
              editReference
                ( \reference ->
                    reference {R.nativeHerObservedOutcomes = mapFirst change (R.nativeHerObservedOutcomes reference)}
                )
        rejectReference
          fixture
          "public-rule replay"
          (mutateOutcome (\one -> one {R.nativeHerOutcomeFinalState = VU.replicate 6 1}))
        rejectReference
          fixture
          "public-rule replay"
          ( mutateOutcome
              ( \one ->
                  one {R.nativeHerOutcomeConsumedActions = mapFirst (const 6) (R.nativeHerOutcomeConsumedActions one)}
              )
          )
        rejectReference
          fixture
          "public-rule replay"
          (mutateOutcome (\one -> one {R.nativeHerOutcomeNormalizedDistance = 0 / 0}))
        rejectReference
          fixture
          "public-rule replay"
          ( editReference
              ( \reference -> reference {R.nativeHerObservedSuccessCount = R.nativeHerObservedSuccessCount reference + 1}
              )
          )
        rejectReference
          fixture
          "public-rule replay"
          ( editReference
              ( \reference ->
                  reference
                    { R.nativeHerObservedEvaluationTransitions = R.nativeHerObservedEvaluationTransitions reference + 1
                    }
              )
          )
    , testCase "caller extrema and omitted attaining IDs are not accepted as their own proof" $ do
        fixture <- getFixture
        let changeExtrema change family = family {R.nativeHerObservedExtrema = change (R.nativeHerObservedExtrema family)}
        rejectReference
          fixture
          "extrema or all attaining"
          ( changeExtrema
              (\value -> value {R.nativeHerMaximumSuccessCount = R.nativeHerMaximumSuccessCount value + 1})
          )
        rejectReference
          fixture
          "extrema or all attaining"
          ( changeExtrema
              ( \value -> value {R.nativeHerMinimumExactMeanDistance = R.nativeHerMinimumExactMeanDistance value + 1}
              )
          )
        rejectReference
          fixture
          "extrema or all attaining"
          (changeExtrema (\value -> value {R.nativeHerMaximumSuccessSequenceIds = []}))
        rejectReference
          fixture
          "extrema or all attaining"
          (changeExtrema (\value -> value {R.nativeHerMinimumDistanceSequenceIds = []}))
    , testCase "whole reference work is derived from all replayed transitions" $ do
        fixture <- getFixture
        rejectReference
          fixture
          "whole reference transition count"
          ( \family ->
              family {R.nativeHerTotalEvaluationTransitions = R.nativeHerTotalEvaluationTransitions family + 1}
          )
    , testCase
        "five prescribed ordered indices and exact base-plus-index seeds cannot be censored or substituted"
        $ do
          fixture <- getFixture
          let supplied = perfectInputs fixture
              compareBad = P.compareNativeHerCohort (fixtureReferences fixture)
          first <- firstOrFail supplied
          expectLeft "ordered indices" (compareBad (drop 1 supplied))
          expectLeft "ordered indices" (compareBad (supplied <> [first]))
          expectLeft "ordered indices" (compareBad (reverse supplied))
          expectLeft "ordered indices" (compareBad (first : first : drop 2 supplied))
          expectLeft
            "prescribed42+index"
            (compareBad (mapFirst (\one -> one {P.nativeHerObservedSeed = 43}) supplied))
    , testCase "paired configuration changes and binary64 signed zero cannot be substituted" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "configuration fields differ"
          ( \raw ->
              raw
                { E.nativeHerEvaluationConfig =
                    (E.nativeHerEvaluationConfig raw)
                      { Her.herReplayCapacity = Her.herReplayCapacity (E.nativeHerEvaluationConfig raw) + 1
                      }
                }
          )
        let changeEpsilon value raw = raw {E.nativeHerEvaluationConfig = (E.nativeHerEvaluationConfig raw) {Her.herEpsilon = value}}
            signed =
              mapFirst
                ( \one ->
                    one
                      { P.nativeHerObservedInitial = changeEpsilon 0 (P.nativeHerObservedInitial one)
                      , P.nativeHerObservedFinal =
                          changeEpsilon (castWord64ToDouble 0x8000000000000000) (P.nativeHerObservedFinal one)
                      }
                )
                (perfectInputs fixture)
        expectLeft
          "configuration fields differ"
          (P.compareNativeHerCohort (fixtureReferences fixture) signed)
    , testCase "matching paired config still rejects a foreign child seed or nonfinite numerical field" $ do
        fixture <- getFixture
        let changeBoth change =
              mapFirst
                ( \one ->
                    one
                      { P.nativeHerObservedInitial = change (P.nativeHerObservedInitial one)
                      , P.nativeHerObservedFinal = change (P.nativeHerObservedFinal one)
                      }
                )
                (perfectInputs fixture)
            configChange change raw = raw {E.nativeHerEvaluationConfig = change (E.nativeHerEvaluationConfig raw)}
            foreignSeedInputs = changeBoth (configChange (\config -> config {Her.herSeed = 43}))
            nonfinite = changeBoth (configChange (\config -> config {Her.herGamma = 1 / 0}))
        expectLeft
          "configuration seed differs"
          (P.compareNativeHerCohort (fixtureReferences fixture) foreignSeedInputs)
        expectLeft
          "configuration is nonfinite"
          (P.compareNativeHerCohort (fixtureReferences fixture) nonfinite)
    , testCase "actual rejected evaluation remains incomplete even if other four members are perfect" $ do
        fixture <- getFixture
        case E.nativeHerEvaluationStatus (fixtureRejected fixture) of
          E.NativeHerEvaluationFailed 0 E.NativeHerDeviceRejected message -> message @?= "native HER device forward failed: actual offline callback rejection"
          status -> assertFailure ("callback fixture did not reach actual device rejection: " <> show status)
        rejectFinal fixture "evaluation is incomplete" (const (fixtureRejected fixture))
    , testCase "raw policy context rejects malformed tensors and nonfinite Float32 parameters" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "parameter tensors differ"
          ( \raw ->
              raw {E.nativeHerEvaluationParameters = (E.nativeHerEvaluationParameters raw) {paramB2 = VU.empty}}
          )
        forM_ [0 / 0, 1e300] $ \value ->
          rejectFinal
            fixture
            "parameters are nonfinite or overflow"
            ( \raw ->
                raw
                  { E.nativeHerEvaluationParameters =
                      (E.nativeHerEvaluationParameters raw) {paramB2 = VU.replicate 6 value}
                  }
            )
    , testCase "complete status cannot conceal retained failed progress" $ do
        fixture <- getFixture
        let progress = E.nativeHerEvaluationFailedProgress (fixtureRejected fixture)
        assertBool
          "real failed callback supplies progress"
          (case progress of Just _ -> True; Nothing -> False)
        rejectFinal
          fixture
          "retains failed progress"
          (\raw -> raw {E.nativeHerEvaluationFailedProgress = progress})
    , testCase "learned cases reject missing duplicate reordered and foreign identifiers" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "missing duplicated foreign or reordered cases"
          (\raw -> raw {E.nativeHerEvaluationOutcomes = drop 1 (E.nativeHerEvaluationOutcomes raw)})
        rejectFinal
          fixture
          "missing duplicated foreign or reordered cases"
          (\raw -> raw {E.nativeHerEvaluationOutcomes = reverse (E.nativeHerEvaluationOutcomes raw)})
        rejectFinal
          fixture
          "missing duplicated foreign or reordered cases"
          ( \raw ->
              raw
                { E.nativeHerEvaluationOutcomes =
                    take 1 (E.nativeHerEvaluationOutcomes raw)
                      <> take 1 (E.nativeHerEvaluationOutcomes raw)
                      <> drop 2 (E.nativeHerEvaluationOutcomes raw)
                }
          )
        rejectFinal
          fixture
          "missing duplicated foreign or reordered cases"
          (editOutcome (\one -> one {R.nativeHerOutcomeCaseId = 20}))
    , testCase "exact planned goal and final-state bytes cannot be substituted" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "goal differs"
          (editOutcome (\one -> one {R.nativeHerOutcomeGoal = VU.replicate 6 0}))
        rejectFinal
          fixture
          "final state differs"
          (editOutcome (\one -> one {R.nativeHerOutcomeFinalState = VU.replicate 6 0}))
    , testCase "consumed actions require exact prefix length actual domain and no actions after success" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "consumed action prefix"
          (editOutcome (\one -> one {R.nativeHerOutcomeSteps = 0}))
        rejectFinal
          fixture
          "outside the actual domain"
          ( editOutcome
              ( \one ->
                  one {R.nativeHerOutcomeConsumedActions = mapFirst (const 6) (R.nativeHerOutcomeConsumedActions one)}
              )
          )
        let appendAction one =
              one
                { R.nativeHerOutcomeSteps = R.nativeHerOutcomeSteps one + 1
                , R.nativeHerOutcomeConsumedActions = R.nativeHerOutcomeConsumedActions one <> [0]
                }
        -- Pick a real early-success case; preserve earlier case records/forwards
        -- so the failure is precisely post-success rather than a missing trace.
        let appendFirstEarly raw =
              raw
                { E.nativeHerEvaluationOutcomes =
                    changeFirstMatching
                      ((< 6) . R.nativeHerOutcomeSteps)
                      appendAction
                      (E.nativeHerEvaluationOutcomes raw)
                }
        assertBool
          "actual fixed goals include an early success"
          ( any
              (any ((< 6) . R.nativeHerOutcomeSteps) . E.nativeHerEvaluationOutcomes . memberPerfect)
              (fixtureMembers fixture)
          )
        rejectFinal fixture "action follows an already reached goal" appendFirstEarly
    , testCase
        "learned normalized distances reject NaN infinity and bit changes before Rational conversion"
        $ do
          fixture <- getFixture
          forM_ [0 / 0, 1 / 0, castWord64ToDouble 1] $ \value ->
            rejectFinal
              fixture
              "normalized or Hamming distance differs"
              (editOutcome (\one -> one {R.nativeHerOutcomeNormalizedDistance = value}))
          rejectFinal
            fixture
            "normalized or Hamming distance differs"
            (editOutcome (\one -> one {R.nativeHerOutcomeHammingDistance = 1}))
    , testCase "success and termination flags are recomputed from the actual public transition state" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "success termination or horizon"
          (editOutcome (\one -> one {R.nativeHerOutcomeSuccess = False}))
        rejectFinal
          fixture
          "success termination or horizon"
          (editOutcome (\one -> one {R.nativeHerOutcomeTerminated = False}))
    , testCase
        "missing extra foreign and misordered forward observations are not hidden by correct rewards"
        $ do
          fixture <- getFixture
          rejectFinal fixture "no recorded forward" (\raw -> raw {E.nativeHerEvaluationForwards = []})
          rejectFinal
            fixture
            "extra or foreign forward"
            ( \raw ->
                raw
                  { E.nativeHerEvaluationForwards =
                      E.nativeHerEvaluationForwards raw <> take 1 (E.nativeHerEvaluationForwards raw)
                  }
            )
          rejectFinal
            fixture
            "case or within-case ordinal"
            (editForward (\one -> one {E.nativeHerForwardCaseId = 19}))
          rejectFinal
            fixture
            "case or within-case ordinal"
            (editForward (\one -> one {E.nativeHerForwardCallIndex = 1}))
    , testCase "retained callback parameter and exact observation bytes bind the evaluated policy" $ do
        fixture <- getFixture
        firstMember <- firstOrFail (fixtureMembers fixture)
        firstForward <- firstOrFail (E.nativeHerEvaluationForwards (memberPerfect firstMember))
        let originalBias = paramB2 (E.nativeHerForwardParameters firstForward)
            signedBias = VU.map (toggleSign 0x8000000000000000) originalBias
        assertBool "signed-zero original bias is nonempty" (not (VU.null originalBias))
        assertBool "signed-zero original bias is numerically zero" (VU.all (== 0) originalBias)
        signedBias @?= originalBias
        assertBool
          "signed-zero bias mutation changes actual stored bits"
          (vectorBits signedBias /= vectorBits originalBias)
        rejectFinal
          fixture
          "parameters differ"
          ( editForward
              ( \one ->
                  one
                    { E.nativeHerForwardParameters =
                        (E.nativeHerForwardParameters one)
                          { paramB2 = signedBias
                          }
                    }
              )
          )
        let originalInput = E.nativeHerForwardInput firstForward
            signedInput =
              VU.imap
                (\index value -> if index == 0 then toggleSign 0x8000000000000000 value else value)
                originalInput
        assertBool "signed-zero original input is nonempty" (not (VU.null originalInput))
        firstInput <- firstOrFail (VU.toList originalInput)
        firstInput @?= 0
        signedInput @?= originalInput
        assertBool
          "signed-zero input mutation changes actual stored bits"
          (vectorBits signedInput /= vectorBits originalInput)
        rejectFinal
          fixture
          "input differs"
          ( editForward
              ( \one ->
                  one
                    { E.nativeHerForwardInput = signedInput
                    }
              )
          )
    , testCase "complete transcripts reject Left exception malformed and nonfinite callback payloads" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "rejected or throwing forward"
          ( editForward
              (\one -> one {E.nativeHerForwardOutcome = E.NativeHerForwardReturned (Left "injected rejection")})
          )
        rejectFinal
          fixture
          "rejected or throwing forward"
          ( editForward
              (\one -> one {E.nativeHerForwardOutcome = E.NativeHerForwardException "injected synchronous failure"})
          )
        forM_ [VU.empty, VU.replicate 6 (0 / 0), VU.replicate 6 (1 / 0), VU.replicate 6 1e300] $ \output ->
          rejectFinal
            fixture
            "malformed or nonfinite Float32"
            (editForward (\one -> one {E.nativeHerForwardOutcome = E.NativeHerForwardReturned (Right output)}))
    , testCase "recorded outputs must select the actual consumed action with the leftmost tie rule" $ do
        fixture <- getFixture
        let substitute raw =
              raw
                { E.nativeHerEvaluationForwards =
                    changeFirstMatching hasPositiveChoice addEarlierTie (E.nativeHerEvaluationForwards raw)
                }
        assertBool
          "perfect fixed trace contains a nonzero chosen action"
          ( any
              (any hasPositiveChoice . E.nativeHerEvaluationForwards . memberPerfect)
              (fixtureMembers fixture)
          )
        rejectFinal fixture "leftmost maximum" substitute
        compared <- compareInputs fixture (editFinal (const (fixtureTied fixture)) (perfectInputs fixture))
        P.nativeHerComparisonFailures compared @?= []
    , testCase "complete learned work must equal actual replayed transitions rather than a copied budget" $ do
        fixture <- getFixture
        rejectFinal
          fixture
          "complete transition work differs"
          (\raw -> raw {E.nativeHerEvaluationWork = E.NativeHerCompleteWork 2004})
    ]

changeFirstMatching :: (value -> Bool) -> (value -> value) -> [value] -> [value]
changeFirstMatching predicate change values = case values of
  [] -> []
  first : rest
    | predicate first -> change first : rest
    | otherwise -> first : changeFirstMatching predicate change rest

hasPositiveChoice :: E.NativeHerForwardObservation -> Bool
hasPositiveChoice observed = case E.nativeHerForwardOutcome observed of
  E.NativeHerForwardReturned (Right output) -> case VU.toList output of
    first : _ -> first == 0 && VU.any (== 1) output
    [] -> False
  _ -> False

addEarlierTie :: E.NativeHerForwardObservation -> E.NativeHerForwardObservation
addEarlierTie observed = case E.nativeHerForwardOutcome observed of
  E.NativeHerForwardReturned (Right output) ->
    observed
      { E.nativeHerForwardOutcome =
          E.NativeHerForwardReturned
            (Right (VU.imap (\index value -> if index == 0 then 1 else value) output))
      }
  _ -> observed

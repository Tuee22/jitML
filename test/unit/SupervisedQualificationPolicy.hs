{-# LANGUAGE OverloadedStrings #-}

module SupervisedQualificationPolicy (supervisedQualificationPolicyTests) where

import Control.Monad (replicateM)
import Data.Either (isLeft)
import Data.Foldable (for_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Product.SupervisedQualificationPolicy qualified as Policy

supervisedQualificationPolicyTests :: TestTree
supervisedQualificationPolicyTests =
  testGroup
    "compact supervised qualification policy"
    [ seedAndWorkTests
    , classificationTests
    , regressionTests
    , malformedObservationTests
    ]

seedAndWorkTests :: TestTree
seedAndWorkTests =
  testGroup
    "fixed seed and work semantics"
    [ testCase "only ordered indices zero through four exist and preserve the canonical base seed" $ do
        fmap Policy.supervisedSeedIndexValue Policy.supervisedSeedIndices @?= [0 .. 4]
        traverse (Policy.supervisedSeedForIndex 1001 0) Policy.supervisedSeedIndices
          @?= Right [1001 .. 1005]
        for_ [-1, 5, minBound, maxBound] $ \invalid ->
          assertRejected (Policy.supervisedSeedIndex invalid)
    , testCase "seed addition reserves architecture headroom without wrapping Word64 or Int" $ do
        zero <- expectRight (Policy.supervisedSeedIndex 0)
        four <- expectRight (Policy.supervisedSeedIndex 4)
        let largestInt = fromIntegral (maxBound :: Int) :: Word64
        Policy.supervisedSeedForIndex (largestInt - 4) 0 four @?= Right largestInt
        assertRejected (Policy.supervisedSeedForIndex (largestInt - 4) 1 four)
        assertRejected (Policy.supervisedSeedForIndex largestInt 0 four)
        assertRejected (Policy.supervisedSeedForIndex maxBound 0 four)
        assertRejected (Policy.supervisedSeedForIndex 1001 (-1) zero)
    , testCase "partial batches preserve the exact unchanged seven-thousand-example budget" $ do
        work <- expectRight (Policy.supervisedExpectedWork 10 7000 128)
        Policy.supervisedExpectedEpochs work @?= 10
        Policy.supervisedExpectedTrainingExamples work @?= 7000
        Policy.supervisedExpectedBatchExamples work @?= 128
        Policy.supervisedExpectedExamplesProcessed work @?= 70000
        Policy.supervisedExpectedOptimizerUpdates work @?= 550
        tiny <- expectRight (Policy.supervisedExpectedWork 15 8000 128)
        Policy.supervisedExpectedOptimizerUpdates tiny @?= 945
        Policy.supervisedExpectedExamplesProcessed tiny @?= 120000
    , testCase "zero or overflowing planned work cannot be supplied as an easy target" $ do
        for_ [(0, 7000, 128), (10, 0, 128), (10, 7000, 0), (2, maxBound, 1)] $ \(epochs, examples, batch) ->
          assertRejected (Policy.supervisedExpectedWork epochs examples batch)
    , testCase "the contract explicitly binds the new five-seed rule and stricter per-seed alpha" $ do
        for_ ["compact-predictive-learning-v2", "served-index-0", "joint-at-least-3-of-5", "alpha-1/5000"] $ \fragment ->
          assertBool
            (Text.unpack fragment)
            (fragment `Text.isInfixOf` Policy.supervisedQualificationPolicyContract)
    ]

classificationTests :: TestTree
classificationTests =
  testGroup
    "classification whole-cohort and served-run separation"
    [ testCase "five improving predictions keep the index-zero metric distinct from their median" $ do
        assessment <-
          expectRight
            ( assess
                (classificationEvaluation 0.25)
                (classificationObservations (replicate 5 100) [250, 260, 270, 280, 290])
            )
        Policy.supervisedCohortFailures assessment @?= []
        Policy.supervisedCohortJointSuccessCount assessment @?= 5
        Policy.supervisedCohortMedian assessment @?= 0.27
        Policy.supervisedCohortServedMetric assessment @?= 0.25
    , testCase "finite below-bar and below-signal outcomes stay in the exact five-member median" $ do
        let observations = classificationObservations (replicate 5 100) [250, 90, 110, 280, 300]
        assessment <- expectRight (assess (classificationEvaluation 0.25) observations)
        Policy.supervisedCohortObservations assessment @?= observations
        Policy.supervisedCohortJointSuccessCount assessment @?= 3
        Policy.supervisedCohortMedian assessment @?= 0.25
        Policy.supervisedCohortFailures assessment @?= []
        assertBool "failing members disappeared from diagnostics" $
          not (any (null . snd) (take 2 (withoutFirst (Policy.supervisedCohortSeedFindings assessment))))
    , testCase
        "a majority above the historical Tiny floor still fails when only two seeds beat the new random control"
        $ do
          let evaluation = Policy.ClassificationEvaluation 200 (take 1000 (cycle [0 .. 199])) 0.008
          assessment <-
            expectRight (assess evaluation (classificationObservations (replicate 5 5) [16, 16, 12, 12, 12]))
          Policy.supervisedCohortMedian assessment @?= 0.012
          Policy.supervisedCohortJointSuccessCount assessment @?= 2
          assertFinding "fewer than three" assessment
    , testCase
        "different signal and improvement majorities cannot stand in for three jointly successful runs"
        $ do
          assessment <-
            expectRight
              ( assess
                  (classificationEvaluation 0.25)
                  (classificationObservations [250, 250, 100, 100, 100] [250, 250, 250, 110, 110])
              )
          Policy.supervisedCohortJointSuccessCount assessment @?= 1
          assertFinding "fewer than three" assessment
    , testCase "a good median cannot publish index zero below its own unchanged floor" $ do
        assessment <-
          expectRight
            ( assess
                (classificationEvaluation 0.25)
                (classificationObservations (replicate 5 100) [200, 300, 300, 300, 300])
            )
        Policy.supervisedCohortMedian assessment @?= 0.3
        Policy.supervisedCohortServedMetric assessment @?= 0.2
        Policy.supervisedCohortJointSuccessCount assessment @?= 5
        assertFinding "served index0 fails: final primary metric" assessment
    , testCase "index zero cannot borrow the other seeds' signal or improvement" $ do
        let tinyEvaluation = Policy.ClassificationEvaluation 200 (take 1000 (cycle [0 .. 199])) 0.008
        weak <-
          expectRight
            (assess tinyEvaluation (classificationObservations (replicate 5 5) [12, 16, 16, 16, 16]))
        Policy.supervisedCohortJointSuccessCount weak @?= 4
        assertFinding "served index0 fails: final predictor fails" weak
        unchanged <-
          expectRight
            ( assess
                (classificationEvaluation 0.25)
                (classificationObservations [300, 100, 100, 100, 100] (replicate 5 300))
            )
        Policy.supervisedCohortJointSuccessCount unchanged @?= 4
        assertFinding "served index0 fails: final predictor does not strictly improve" unchanged
    , testCase "a passing served model does not permit dropping three below-floor members" $ do
        assessment <-
          expectRight
            ( assess
                (classificationEvaluation 0.25)
                (classificationObservations (replicate 5 100) [260, 200, 200, 200, 300])
            )
        Policy.supervisedCohortJointSuccessCount assessment @?= 5
        Policy.supervisedCohortMedian assessment @?= 0.2
        Policy.supervisedCohortServedMetric assessment @?= 0.26
        assertFinding "whole-five median" assessment
    , testCase "all thirty-two improvement patterns obey the three-joint and mandatory-index-zero rule" $
        for_ (replicateM 5 [False, True]) $ \improvements -> do
          let initial = fmap (\improves -> if improves then 100 else 300) improvements
          assessment <-
            expectRight
              (assess (classificationEvaluation 0.25) (classificationObservations initial (replicate 5 300)))
          let expectedCount = length (filter id improvements)
          Policy.supervisedCohortJointSuccessCount assessment @?= expectedCount
          case improvements of
            servedImproves : _ -> null (Policy.supervisedCohortFailures assessment) @?= (servedImproves && expectedCount >= 3)
            [] -> fail "the exhaustive five-seed fixture unexpectedly became empty"
    ]

regressionTests :: TestTree
regressionTests =
  testGroup
    "regression paired exact errors"
    [ testCase "finite constant-predictor failures remain alongside three improving positive-skill runs" $ do
        let pairs =
              [ ([0, 0], [-0.5, 0.5])
              , ([0, 0], [0, 0])
              , ([0, 0], [0, 0])
              , ([0, 0], [-0.5, 0.5])
              , ([0, 0], [-0.5, 0.5])
              ]
            observations = regressionObservations pairs
        assessment <- expectRight (assess regressionEvaluation observations)
        Policy.supervisedCohortObservations assessment @?= observations
        Policy.supervisedCohortMedian assessment @?= 0.5
        Policy.supervisedCohortJointSuccessCount assessment @?= 3
        Policy.supervisedCohortFailures assessment @?= []
    , testCase "the old RMSE ceiling and a good cohort cannot admit a zero-skill index zero" $ do
        let pairs = ([2, 2], [0, 0]) : replicate 4 ([0, 0], [-0.5, 0.5])
        assessment <- expectRight (assess regressionEvaluation (regressionObservations pairs))
        Policy.supervisedCohortServedMetric assessment @?= 1
        Policy.supervisedCohortJointSuccessCount assessment @?= 4
        assertFinding "served index0 fails: final predictor fails" assessment
    , testCase "an unchanged positive-skill regressor cannot claim training improvement" $ do
        assessment <-
          expectRight
            (assess regressionEvaluation (regressionObservations (replicate 5 ([-0.5, 0.5], [-0.5, 0.5]))))
        Policy.supervisedCohortMedian assessment @?= 0.5
        Policy.supervisedCohortJointSuccessCount assessment @?= 0
        assertFinding "does not strictly improve" assessment
    , testCase "strict rational skill and improvement remain visible when display RMSE rounds to one" $ do
        let smallest = encodeFloat 1 (-1074)
            pair = ([0, 0], [-smallest, smallest])
        assessment <- expectRight (assess regressionEvaluation (regressionObservations (replicate 5 pair)))
        Policy.supervisedCohortMedian assessment @?= 1
        Policy.supervisedCohortJointSuccessCount assessment @?= 5
        Policy.supervisedCohortFailures assessment @?= []
    , testCase "subnormal target errors cannot vanish into a false paired equality" $ do
        let smallest = encodeFloat 1 (-1074)
            targets = [0, smallest]
            evaluation = Policy.RegressionEvaluation 1 targets 1
        assessment <-
          expectRight (assess evaluation (regressionObservations (replicate 5 ([0, 0], targets))))
        Policy.supervisedCohortJointSuccessCount assessment @?= 5
        Policy.supervisedCohortFailures assessment @?= []
    ]

malformedObservationTests :: TestTree
malformedObservationTests =
  testGroup
    "malformed observations are not finite failing members"
    [ testCase "missing, duplicated, reordered or substituted seeds cannot form the cohort" $ do
        let valid = classificationObservations (replicate 5 100) (replicate 5 300)
        first <- expectFirst valid
        for_
          [ take 4 valid
          , valid <> [first]
          , reverse valid
          , first : first : drop 2 valid
          , first {Policy.observationSeed = 9999} : withoutFirst valid
          ]
          $ \invalid ->
            assertRejected (assess (classificationEvaluation 0.25) invalid)
    , testCase "every observed budget field must match the original per-run plan" $ do
        let valid = classificationObservations (replicate 5 100) (replicate 5 300)
        first <- expectFirst valid
        for_
          [ first {Policy.observationCompletedEpochs = 9}
          , first {Policy.observationExamplesProcessed = 69999}
          , first {Policy.observationOptimizerUpdates = 549}
          ]
          $ \invalid ->
            assertRejected (assess (classificationEvaluation 0.25) (invalid : withoutFirst valid))
    , testCase "wrong prediction kind and impossible initial/final correct counts fail before grading" $ do
        let valid = classificationObservations (replicate 5 100) (replicate 5 300)
        first <- expectFirst valid
        for_
          [ Policy.ClassificationPredictionPair (-1) 300
          , Policy.ClassificationPredictionPair 100 1001
          , Policy.RegressionPredictionPair [0, 0] [-1, 1]
          ]
          $ \invalid ->
            assertRejected
              ( assess
                  (classificationEvaluation 0.25)
                  (first {Policy.observationPredictions = invalid} : withoutFirst valid)
              )
    , testCase "invalid labels, floors, target variance and standardization fail closed" $ do
        let valid = classificationObservations (replicate 5 100) (replicate 5 300)
        for_
          [ Policy.ClassificationEvaluation 1 [0] 0.25
          , Policy.ClassificationEvaluation 10 [] 0.25
          , Policy.ClassificationEvaluation 10 [10] 0.25
          , classificationEvaluation nan
          , classificationEvaluation (-0.1)
          , classificationEvaluation 1.1
          , Policy.RegressionEvaluation 1 [1, 1] 1
          , Policy.RegressionEvaluation 0 [-1, 1] 1
          , Policy.RegressionEvaluation 1 [-1, 1] nan
          ]
          $ \invalid ->
            assertRejected (assess invalid valid)
    , testCase "nonfinite or missing initial predictions never create an infinitely easy baseline" $ do
        let valid = regressionObservations (replicate 5 ([0, 0], [-0.5, 0.5]))
        first <- expectFirst valid
        for_
          [ Policy.RegressionPredictionPair [nan, 0] [-0.5, 0.5]
          , Policy.RegressionPredictionPair [infinity, 0] [-0.5, 0.5]
          , Policy.RegressionPredictionPair [0] [-0.5, 0.5]
          , Policy.RegressionPredictionPair [0, 0] [infinity, 0]
          ]
          $ \invalid ->
            assertRejected
              (assess regressionEvaluation (first {Policy.observationPredictions = invalid} : withoutFirst valid))
    ]

classificationEvaluation :: Double -> Policy.SupervisedEvaluation
classificationEvaluation = Policy.ClassificationEvaluation 10 (take 1000 (cycle [0 .. 9]))

regressionEvaluation :: Policy.SupervisedEvaluation
regressionEvaluation = Policy.RegressionEvaluation 1 [-1, 1] 1

assess
  :: Policy.SupervisedEvaluation
  -> [Policy.SupervisedSeedObservation]
  -> Either Text Policy.SupervisedCohortAssessment
assess evaluation observations = do
  work <- Policy.supervisedExpectedWork 10 7000 128
  Policy.assessSupervisedCohort 1001 0 work evaluation observations

classificationObservations :: [Int] -> [Int] -> [Policy.SupervisedSeedObservation]
classificationObservations =
  zipWith3
    (\index initial final -> observation index (Policy.ClassificationPredictionPair initial final))
    [0 .. 4]

regressionObservations :: [([Double], [Double])] -> [Policy.SupervisedSeedObservation]
regressionObservations =
  zipWith
    (\index (initial, final) -> observation index (Policy.RegressionPredictionPair initial final))
    [0 .. 4]

observation :: Int -> Policy.SupervisedPredictionPair -> Policy.SupervisedSeedObservation
observation index predictions =
  Policy.SupervisedSeedObservation
    { Policy.observationSeedIndex = index
    , Policy.observationSeed = 1001 + fromIntegral index
    , Policy.observationCompletedEpochs = 10
    , Policy.observationExamplesProcessed = 70000
    , Policy.observationOptimizerUpdates = 550
    , Policy.observationPredictions = predictions
    }

expectFirst :: [value] -> IO value
expectFirst (first : _) = pure first
expectFirst [] = fail "the five-seed fixture unexpectedly became empty"

expectRight :: Either Text value -> IO value
expectRight = either (fail . Text.unpack) pure

assertRejected :: Either error value -> IO ()
assertRejected = assertBool "invalid raw observations unexpectedly passed refinement" . isLeft

assertFinding :: Text -> Policy.SupervisedCohortAssessment -> IO ()
assertFinding fragment assessment =
  assertBool ("missing qualification diagnostic: " <> Text.unpack fragment) $
    any (Text.isInfixOf fragment) (Policy.supervisedCohortFailures assessment)

nan :: Double
nan = 0 / 0

infinity :: Double
infinity = 1 / 0

-- | Total base-only drop-one, preserving the adversarial fixture order.
withoutFirst :: [value] -> [value]
withoutFirst [] = []
withoutFirst (_ : rest) = rest

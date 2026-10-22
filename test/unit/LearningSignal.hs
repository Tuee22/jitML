{-# LANGUAGE OverloadedStrings #-}

module LearningSignal (learningSignalTests) where

import Data.Either (isLeft)
import Data.Foldable (for_)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Product.LearningSignal qualified as LearningSignal

learningSignalTests :: TestTree
learningSignalTests =
  testGroup
    "Additional supervised learning signal"
    [ classificationTests
    , regressionTests
    , improvementTests
    ]

classificationTests :: TestTree
classificationTests =
  testGroup
    "classification"
    [ testCase "ten-class exact random boundary is 136 correct of 1000" $ do
        let labels = take 1000 (cycle [0 .. 9])
        LearningSignal.classificationMinimumCorrect 10 labels @?= Right 136
        assertRejected (LearningSignal.assertClassificationLearningSignal 10 labels 135)
        LearningSignal.assertClassificationLearningSignal 10 labels 136 @?= Right ()
    , testCase "100-class exact random boundary is 24 correct of 1000" $ do
        let labels = take 1000 (cycle [0 .. 99])
        LearningSignal.classificationMinimumCorrect 100 labels @?= Right 24
        assertRejected (LearningSignal.assertClassificationLearningSignal 100 labels 23)
        LearningSignal.assertClassificationLearningSignal 100 labels 24 @?= Right ()
    , testCase "200-class exact random boundary is 16 correct of 1000" $ do
        let labels = take 1000 (cycle [0 .. 199])
        LearningSignal.classificationMinimumCorrect 200 labels @?= Right 16
        assertRejected (LearningSignal.assertClassificationLearningSignal 200 labels 15)
        LearningSignal.assertClassificationLearningSignal 200 labels 16 @?= Right ()
    , testCase "every constant classifier fails even when it chooses the held-out majority" $ do
        let labels = replicate 900 7 <> take 100 (cycle [0 .. 9])
        LearningSignal.classificationMinimumCorrect 10 labels @?= Right 911
        for_ [0 .. 9] $ \constant ->
          assertRejected
            (LearningSignal.assertClassificationLearningSignal 10 labels (length (filter (== constant) labels)))
        LearningSignal.assertClassificationLearningSignal 10 labels 911 @?= Right ()
    , testCase "a one-class held-out set cannot supply positive signal" $ do
        let labels = replicate 1000 4
        LearningSignal.classificationMinimumCorrect 10 labels @?= Right 1001
        assertRejected (LearningSignal.assertClassificationLearningSignal 10 labels 1000)
    , testCase "a tiny evaluation cannot bypass the exact random control" $ do
        LearningSignal.classificationMinimumCorrect 10 [0] @?= Right 2
        assertRejected (LearningSignal.assertClassificationLearningSignal 10 [0] 1)
    , testCase "invalid classes, labels, and served counts fail closed" $ do
        for_ [0, 1, -1] $ \classes ->
          assertRejected (LearningSignal.classificationMinimumCorrect classes [0])
        assertRejected (LearningSignal.classificationMinimumCorrect 10 [])
        assertRejected (LearningSignal.classificationMinimumCorrect 10 [-1, 0])
        assertRejected (LearningSignal.classificationMinimumCorrect 10 [0, 10])
        let labels = take 1000 (cycle [0 .. 9])
        assertRejected (LearningSignal.assertClassificationLearningSignal 10 labels (-1))
        assertRejected (LearningSignal.assertClassificationLearningSignal 10 labels 1001)
    ]

regressionTests :: TestTree
regressionTests =
  testGroup
    "regression"
    [ testCase "the held-out mean and every other constant are rejected" $ do
        let targets = [95, 105, 95, 105]
        for_ [0, 95, 99, 100, 101, 105, 1000] $ \constant ->
          assertRejected (LearningSignal.assertRegressionLearningSignal 5 targets (replicate 4 constant))
    , testCase "zero-skill equality is rejected for a nonconstant predictor too" $ do
        -- Both sums of squared deviations are exactly 50; the prediction
        -- vector is deliberately not constant, so a constant-only check fails.
        assertRejected (LearningSignal.assertRegressionLearningSignal 5 [95, 105] [96, 98])
    , testCase "strict improvement and perfect predictions pass" $ do
        LearningSignal.assertRegressionLearningSignal 5 [95, 105] [96, 104] @?= Right ()
        LearningSignal.assertRegressionLearningSignal 5 [95, 105] [95, 105] @?= Right ()
    , testCase "scale cancels without squared-error overflow or underflow" $ do
        for_ [1.0e-300, 1.0e300] $ \magnitude -> do
          let targets = [-magnitude, magnitude]
          LearningSignal.assertRegressionLearningSignal magnitude targets targets @?= Right ()
          assertRejected (LearningSignal.assertRegressionLearningSignal magnitude targets [0, 0])
          LearningSignal.assertRegressionLearningSignal magnitude targets [-(magnitude / 2), magnitude / 2]
            @?= Right ()
    , testCase "opposite largest finite targets do not overflow the mean or deviations" $ do
        let largest = encodeFloat (2 ^ (53 :: Int) - 1) (1024 - 53)
            targets = [-largest, largest]
        LearningSignal.assertRegressionLearningSignal 1 targets targets @?= Right ()
        assertRejected (LearningSignal.assertRegressionLearningSignal 1 targets [0, 0])
    , testCase "subnormal target differences retain their variance" $ do
        let smallest = encodeFloat 1 (-1074)
            targets = [0, smallest]
        LearningSignal.assertRegressionLearningSignal 1 targets targets @?= Right ()
        assertRejected (LearningSignal.assertRegressionLearningSignal 1 targets [0, 0])
    , testCase "degenerate targets, missing predictions, and nonfinite values fail closed" $ do
        assertRejected (LearningSignal.assertRegressionLearningSignal 1 [] [])
        assertRejected (LearningSignal.assertRegressionLearningSignal 1 [1, 2] [1])
        assertRejected (LearningSignal.assertRegressionLearningSignal 1 [1, 1] [1, 1])
        assertRejected (LearningSignal.assertRegressionLearningSignal 1 [1] [1])
        for_ [0, -1, nan, infinity] $ \scale ->
          assertRejected (LearningSignal.assertRegressionLearningSignal scale [1, 2] [1, 2])
        for_ [nan, infinity, negate infinity] $ \invalid -> do
          assertRejected (LearningSignal.assertRegressionLearningSignal 1 [invalid, 2] [1, 2])
          assertRejected (LearningSignal.assertRegressionLearningSignal 1 [1, 2] [1, invalid])
    ]

improvementTests :: TestTree
improvementTests =
  testGroup
    "paired initial-to-final improvement"
    [ testCase "classification equality and lower accuracy cannot pass as training improvement" $ do
        assertRejected (LearningSignal.assertClassificationImprovement 1000 500 500)
        assertRejected (LearningSignal.assertClassificationImprovement 1000 501 500)
        LearningSignal.assertClassificationImprovement 1000 500 501 @?= Right ()
    , testCase "classification malformed initial counts cannot create an easy baseline" $ do
        for_ [(0, 0, 0), (1000, -1, 500), (1000, 1001, 1000), (1000, 0, 1001)] $ \(n, initial, final) ->
          assertRejected (LearningSignal.assertClassificationImprovement n initial final)
    , testCase "regression equal errors fail even with different prediction vectors" $ do
        assertRejected (LearningSignal.assertRegressionImprovement 1 [-1, 1] [0, 0] [-2, 2])
        assertRejected (LearningSignal.assertRegressionImprovement 1 [-1, 1] [-0.5, 0.5] [-0.5, 0.5])
        LearningSignal.assertRegressionImprovement 1 [-1, 1] [0, 0] [-0.5, 0.5] @?= Right ()
    , testCase "exact paired squared error survives subnormal underflow and large-value overflow" $ do
        for_ [encodeFloat 1 (-1074), 1.0e300] $ \magnitude -> do
          let targets = [-magnitude, magnitude]
          LearningSignal.assertRegressionImprovement 1 targets [0, 0] targets @?= Right ()
          assertRejected (LearningSignal.assertRegressionImprovement 1 targets targets [0, 0])
    , testCase "nonfinite or malformed initial predictions do not become infinite-error baselines" $ do
        for_ [nan, infinity, negate infinity] $ \invalid ->
          assertRejected (LearningSignal.assertRegressionImprovement 1 [-1, 1] [invalid, 0] [-1, 1])
        assertRejected (LearningSignal.assertRegressionImprovement 1 [-1, 1] [0] [-1, 1])
        assertRejected (LearningSignal.assertRegressionImprovement 1 [1, 1] [0, 0] [1, 1])
    ]

assertRejected :: Either error value -> IO ()
assertRejected = assertBool "the additional learning-signal guard must reject this predictor" . isLeft

nan :: Double
nan = 0 / 0

infinity :: Double
infinity = 1 / 0

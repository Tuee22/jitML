{-# LANGUAGE OverloadedStrings #-}

-- | Pure comparison policy for the fixed compact supervised cohort. Inputs
-- are unauthenticated exact observations, not proof that a producer trained a
-- model. Artifact/source/device admission must authenticate them separately.
-- Finite below-floor and non-improving members remain in the assessment.
module JitML.Product.SupervisedQualificationPolicy
  ( SupervisedSeedIndex
  , supervisedSeedIndex
  , supervisedSeedIndexValue
  , supervisedSeedIndices
  , supervisedSeedForIndex
  , supervisedQualificationPolicyContract
  , SupervisedExpectedWork
  , supervisedExpectedWork
  , supervisedExpectedEpochs
  , supervisedExpectedTrainingExamples
  , supervisedExpectedBatchExamples
  , supervisedExpectedExamplesProcessed
  , supervisedExpectedOptimizerUpdates
  , SupervisedEvaluation (..)
  , SupervisedPredictionPair (..)
  , SupervisedSeedObservation (..)
  , SupervisedCohortAssessment
  , assessSupervisedCohort
  , supervisedCohortObservations
  , supervisedCohortJointSuccessCount
  , supervisedCohortMedian
  , supervisedCohortServedMetric
  , supervisedCohortSeedFindings
  , supervisedCohortFailures
  )
where

import Data.Either (isRight)
import Data.List qualified as List
import Data.Text (Text)
import Data.Word (Word64)

import JitML.Product.LearningSignal qualified as LearningSignal

newtype SupervisedSeedIndex = SupervisedSeedIndex Int
  deriving stock (Eq, Ord, Show)

supervisedSeedIndex :: Int -> Either Text SupervisedSeedIndex
supervisedSeedIndex index
  | index >= 0 && index <= 4 = Right (SupervisedSeedIndex index)
  | otherwise = Left "supervised seed index must lie in 0..4"

supervisedSeedIndexValue :: SupervisedSeedIndex -> Int
supervisedSeedIndexValue (SupervisedSeedIndex index) = index

supervisedSeedIndices :: [SupervisedSeedIndex]
supervisedSeedIndices = fmap SupervisedSeedIndex [0 .. 4]

-- | Checked base + index, reserving the caller's additional architecture seed
-- headroom. The index offset is already added here: do not add it twice to
-- headroom. No Word64 wrapping or Int overflow is allowed.
supervisedSeedForIndex :: Word64 -> Integer -> SupervisedSeedIndex -> Either Text Word64
supervisedSeedForIndex base headroom index
  | headroom < 0 = Left "supervised seed headroom must be nonnegative"
  | shifted > toInteger (maxBound :: Word64) = Left "supervised child seed exceeds Word64 range"
  | shifted + headroom > toInteger (maxBound :: Int) =
      Left "supervised child seed plus architecture headroom exceeds Int range"
  | otherwise = Right (fromInteger shifted)
 where
  shifted = toInteger base + toInteger (supervisedSeedIndexValue index)

supervisedQualificationPolicyContract :: Text
supervisedQualificationPolicyContract =
  "compact-predictive-learning-v2:canonical-base-plus-offsets-0..4;served-index-0;paired-strict;joint-at-least-3-of-5;whole-five-median-unchanged-floor;index0-independently-eligible;"
    <> LearningSignal.learningSignalPolicyContract

data SupervisedExpectedWork = SupervisedExpectedWork
  { internalExpectedEpochs :: !Word64
  , internalExpectedTrainingExamples :: !Word64
  , internalExpectedBatchExamples :: !Word64
  , internalExpectedExamplesProcessed :: !Word64
  , internalExpectedOptimizerUpdates :: !Word64
  }
  deriving stock (Eq, Show)

supervisedExpectedEpochs :: SupervisedExpectedWork -> Word64
supervisedExpectedEpochs = internalExpectedEpochs

supervisedExpectedTrainingExamples :: SupervisedExpectedWork -> Word64
supervisedExpectedTrainingExamples = internalExpectedTrainingExamples

supervisedExpectedBatchExamples :: SupervisedExpectedWork -> Word64
supervisedExpectedBatchExamples = internalExpectedBatchExamples

supervisedExpectedExamplesProcessed :: SupervisedExpectedWork -> Word64
supervisedExpectedExamplesProcessed = internalExpectedExamplesProcessed

supervisedExpectedOptimizerUpdates :: SupervisedExpectedWork -> Word64
supervisedExpectedOptimizerUpdates = internalExpectedOptimizerUpdates

-- | Derive unchanged per-run work from planned quantities, never observations.
supervisedExpectedWork :: Word64 -> Word64 -> Word64 -> Either Text SupervisedExpectedWork
supervisedExpectedWork epochs trainingExamples batchExamples
  | 0 `elem` [epochs, trainingExamples, batchExamples] =
      Left "supervised expected epochs, training examples and batch must be positive"
  | examples > limit || updates > limit = Left "supervised expected work exceeds Word64 range"
  | otherwise =
      Right
        SupervisedExpectedWork
          { internalExpectedEpochs = epochs
          , internalExpectedTrainingExamples = trainingExamples
          , internalExpectedBatchExamples = batchExamples
          , internalExpectedExamplesProcessed = fromInteger examples
          , internalExpectedOptimizerUpdates = fromInteger updates
          }
 where
  examples = toInteger epochs * toInteger trainingExamples
  batches = (toInteger trainingExamples + toInteger batchExamples - 1) `div` toInteger batchExamples
  updates = toInteger epochs * batches
  limit = toInteger (maxBound :: Word64)

-- | Labels/targets are common to every seed. The final Double is the unchanged
-- historical accuracy floor or standardized-RMSE ceiling from the plan policy.
data SupervisedEvaluation
  = ClassificationEvaluation !Int ![Int] !Double
  | RegressionEvaluation !Double ![Double] !Double
  deriving stock (Eq, Show)

data SupervisedPredictionPair
  = ClassificationPredictionPair !Int !Int
  | RegressionPredictionPair ![Double] ![Double]
  deriving stock (Eq, Show)

-- | Raw exact observations: no pass/eligible/completed boolean is accepted.
-- Counts must later be authenticated against actual producer/event evidence;
-- equality with expected work alone does not prove execution occurred.
data SupervisedSeedObservation = SupervisedSeedObservation
  { observationSeedIndex :: !Int
  , observationSeed :: !Word64
  , observationCompletedEpochs :: !Word64
  , observationExamplesProcessed :: !Word64
  , observationOptimizerUpdates :: !Word64
  , observationPredictions :: !SupervisedPredictionPair
  }
  deriving stock (Eq, Show)

data SupervisedCohortAssessment = SupervisedCohortAssessment
  { internalCohortObservations :: ![SupervisedSeedObservation]
  , internalCohortJointSuccessCount :: !Int
  , internalCohortMedian :: !Double
  , internalCohortServedMetric :: !Double
  , internalCohortSeedFindings :: ![(Int, [Text])]
  , internalCohortFailures :: ![Text]
  }
  deriving stock (Eq, Show)

supervisedCohortObservations :: SupervisedCohortAssessment -> [SupervisedSeedObservation]
supervisedCohortObservations = internalCohortObservations

supervisedCohortJointSuccessCount :: SupervisedCohortAssessment -> Int
supervisedCohortJointSuccessCount = internalCohortJointSuccessCount

supervisedCohortMedian :: SupervisedCohortAssessment -> Double
supervisedCohortMedian = internalCohortMedian

supervisedCohortServedMetric :: SupervisedCohortAssessment -> Double
supervisedCohortServedMetric = internalCohortServedMetric

supervisedCohortSeedFindings :: SupervisedCohortAssessment -> [(Int, [Text])]
supervisedCohortSeedFindings = internalCohortSeedFindings

supervisedCohortFailures :: SupervisedCohortAssessment -> [Text]
supervisedCohortFailures = internalCohortFailures

data EvaluationPolicy
  = ClassificationPolicy !Int !Int !Double
  | RegressionPolicy !Double ![Double] !Double

-- | Grade exactly five ordered, budget-complete finite observations. A Right
-- value retains all members even when its derived failure list is nonempty.
-- No Store admission, producer authentication or population claim is minted.
assessSupervisedCohort
  :: Word64
  -> Integer
  -> SupervisedExpectedWork
  -> SupervisedEvaluation
  -> [SupervisedSeedObservation]
  -> Either Text SupervisedCohortAssessment
assessSupervisedCohort base headroom work evaluation observations = do
  policy <- refineEvaluation evaluation
  if fmap observationSeedIndex observations == [0 .. 4]
    then Right ()
    else Left "supervised cohort requires exactly five observations in index order 0..4"
  graded <- traverse (gradeObservation policy) observations
  case graded of
    (servedMetric, servedFindings, _) : _ -> do
      let metrics = fmap (\(metric, _, _) -> metric) graded
          jointCount = length (filter (\(_, _, joint) -> joint) graded)
          findings =
            zipWith
              (\observation (_, messages, _) -> (observationSeedIndex observation, messages))
              observations
              graded
      median <- middleOfFive (List.sort metrics)
      Right
        SupervisedCohortAssessment
          { internalCohortObservations = observations
          , internalCohortJointSuccessCount = jointCount
          , internalCohortMedian = median
          , internalCohortServedMetric = servedMetric
          , internalCohortSeedFindings = findings
          , internalCohortFailures =
              ["supervised cohort has fewer than three joint signal-and-improvement successes" | jointCount < 3]
                <> [ "supervised whole-five median fails the unchanged historical floor"
                   | not (passesFloor policy median)
                   ]
                <> fmap ("supervised served index0 fails: " <>) servedFindings
          }
    [] -> Left "supervised cohort contains no served index0 observation"
 where
  gradeObservation policy observation = do
    index <- supervisedSeedIndex (observationSeedIndex observation)
    expectedSeed <- supervisedSeedForIndex base headroom index
    requireEqual
      "supervised child seed differs from canonical base plus index"
      expectedSeed
      (observationSeed observation)
    requireEqual
      "supervised observed epoch count differs from the unchanged plan"
      (supervisedExpectedEpochs work)
      (observationCompletedEpochs observation)
    requireEqual
      "supervised observed example count differs from the unchanged plan"
      (supervisedExpectedExamplesProcessed work)
      (observationExamplesProcessed observation)
    requireEqual
      "supervised observed optimizer updates differ from the unchanged plan"
      (supervisedExpectedOptimizerUpdates work)
      (observationOptimizerUpdates observation)
    (metric, signal, improves) <- gradePair policy (observationPredictions observation)
    let messages =
          ["final predictor fails the independent learning-signal control" | not signal]
            <> ["final predictor does not strictly improve over its own initialization" | not improves]
            <> ["final primary metric fails the unchanged historical floor" | not (passesFloor policy metric)]
    Right (metric, messages, signal && improves)

refineEvaluation :: SupervisedEvaluation -> Either Text EvaluationPolicy
refineEvaluation evaluation =
  case evaluation of
    ClassificationEvaluation classes labels floorValue -> do
      if finite floorValue && floorValue >= 0 && floorValue <= 1
        then Right ()
        else Left "classification historical floor must be finite and lie in [0,1]"
      minimumCorrect <- LearningSignal.classificationMinimumCorrect classes labels
      Right (ClassificationPolicy (length labels) minimumCorrect floorValue)
    RegressionEvaluation scale targets ceilingValue -> do
      if finite ceilingValue && ceilingValue > 0
        then Right ()
        else Left "regression historical RMSE ceiling must be positive and finite"
      LearningSignal.assertRegressionLearningSignal scale targets targets
      Right (RegressionPolicy scale targets ceilingValue)

gradePair :: EvaluationPolicy -> SupervisedPredictionPair -> Either Text (Double, Bool, Bool)
gradePair policy pair =
  case (policy, pair) of
    ( ClassificationPolicy examples minimumCorrect _
      , ClassificationPredictionPair initialCorrect finalCorrect
      ) -> do
        if all (\count -> count >= 0 && count <= examples) [initialCorrect, finalCorrect]
          then Right ()
          else Left "classification initial/final count lies outside the evaluation budget"
        Right
          ( fromIntegral finalCorrect / fromIntegral examples
          , finalCorrect >= minimumCorrect
          , isRight (LearningSignal.assertClassificationImprovement examples initialCorrect finalCorrect)
          )
    (RegressionPolicy scale targets _, RegressionPredictionPair initialPredictions finalPredictions) -> do
      if length initialPredictions == length targets && length finalPredictions == length targets
        then Right ()
        else Left "regression initial/final predictions differ from the evaluation count"
      if all finite initialPredictions && all finite finalPredictions
        then Right ()
        else Left "regression initial/final prediction is non-finite"
      -- Match the existing served primary-metric arithmetic. Exact rational
      -- signal/improvement comparisons are separate and cannot borrow its
      -- rounding or the serving parity tolerance.
      let squaredErrors =
            zipWith
              (\prediction target -> ((prediction - target) / scale) ^ (2 :: Int))
              finalPredictions
              targets
          rmse = sqrt (sum squaredErrors / fromIntegral (length targets))
      if finite rmse
        then
          Right
            ( rmse
            , isRight (LearningSignal.assertRegressionLearningSignal scale targets finalPredictions)
            , isRight
                (LearningSignal.assertRegressionImprovement scale targets initialPredictions finalPredictions)
            )
        else Left "regression final served primary metric is non-finite"
    _ -> Left "supervised prediction kind differs from the cohort evaluation"

passesFloor :: EvaluationPolicy -> Double -> Bool
passesFloor policy value =
  case policy of
    ClassificationPolicy _ _ floorValue -> value >= floorValue
    RegressionPolicy _ _ ceilingValue -> value <= ceilingValue

middleOfFive :: [Double] -> Either Text Double
middleOfFive [_, _, middle, _, _] = Right middle
middleOfFive _ = Left "supervised median requires exactly five finite observations"

requireEqual :: (Eq value) => Text -> value -> value -> Either Text ()
requireEqual message expected observed
  | expected == observed = Right ()
  | otherwise = Left message

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

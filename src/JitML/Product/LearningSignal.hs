{-# LANGUAGE OverloadedStrings #-}

-- | Additional finite-evaluation learning-signal guards. These reject trivial
-- predictors; they do not establish convergence to a published model result.
-- Existing, stronger convergence requirements must still be checked.
module JitML.Product.LearningSignal
  ( assertClassificationLearningSignal
  , assertClassificationImprovement
  , assertRegressionLearningSignal
  , assertRegressionImprovement
  , classificationMinimumCorrect
  , learningSignalPolicyContract
  )
where

import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Text (Text)

-- | Versioned per-seed reference controls. At alpha 1/5000, requiring three
-- joint signal/improvement successes among five seeds gives an all-five-null
-- cohort bound of 1/3000 by Markov's inequality; thirty classification cohorts
-- have a union bound of 0.01. This assumes independent uniform guesses across
-- examples within each seed, not independence between seeds. It does not cover
-- mixed nulls, arbitrary random neural networks, regression, adaptive attempts
-- or a population-accuracy claim.
learningSignalPolicyContract :: Text
learningSignalPolicyContract =
  "supervised-learning-signal-v2:majority-strict;uniform-binomial-exact-alpha-1/5000;held-out-r2-strict-exact-binary64;paired-initial-final-strict"

-- | The stronger of the exact held-out majority count plus one and the exact
-- uniform-random binomial critical count. The latter is the smallest integer
-- k with P[Binomial(n, 1/classes) >= k] <= 1/5000. Integer weights make the
-- tail decision exact, independently of model outputs and floating rounding.
--
-- A small evaluation may have no attainable critical count: n + 1 deliberately
-- denotes that no prediction vector can supply enough evidence to pass.
classificationMinimumCorrect :: Int -> [Int] -> Either Text Int
classificationMinimumCorrect classes labels
  | classes < 2 = Left "classification learning signal requires at least two classes"
  | null labels = Left "classification learning-signal labels are empty"
  | any (\label -> label < 0 || label >= classes) labels =
      Left "classification learning-signal label lies outside the semantic classes"
  | otherwise = Right (max (majorityCount + 1) randomMinimum)
 where
  examples = length labels
  majorityCount = maximum (Map.elems (Map.fromListWith (+) [(label, 1 :: Int) | label <- labels]))
  classAlternatives = toInteger classes - 1
  denominator = toInteger classes ^ examples
  weights =
    List.scanl'
      ( \weight index -> weight * toInteger (examples - index) `div` ((toInteger index + 1) * classAlternatives)
      )
      (classAlternatives ^ examples)
      [0 .. examples - 1]
  tailWeights = scanr (+) 0 weights
  randomMinimum =
    length (takeWhile (\tailWeight -> tailWeight * 5000 > denominator) tailWeights)

-- | Grade the integer count obtained from the admitted serving graph. A
-- reported or tolerance-adjusted accuracy is not an input to this guard.
assertClassificationLearningSignal :: Int -> [Int] -> Int -> Either Text ()
assertClassificationLearningSignal classes labels correct = do
  minimumCorrect <- classificationMinimumCorrect classes labels
  if correct < 0 || correct > length labels
    then Left "classification learning-signal correct count lies outside the evaluation budget"
    else
      if correct >= minimumCorrect
        then Right ()
        else
          Left "admitted classifier does not beat the held-out majority and exact uniform-random controls"

-- | Descriptive, paired strict improvement on the same held-out examples.
-- Counts are exact evaluator observations, not rounded accuracies. This does
-- not authenticate their producer or assign population confidence.
assertClassificationImprovement :: Int -> Int -> Int -> Either Text ()
assertClassificationImprovement examples initialCorrect finalCorrect
  | examples <= 0 = Left "classification improvement requires a nonempty evaluation"
  | any (\count -> count < 0 || count > examples) [initialCorrect, finalCorrect] =
      Left "classification improvement correct count lies outside the evaluation budget"
  | finalCorrect > initialCorrect = Right ()
  | otherwise = Left "final classifier does not strictly improve over its initial predictor"

-- | Strictly positive held-out R-squared: the exact served predictions must
-- have lower squared error than the best constant on these exact targets.
-- Finite binary64 values are compared as exact rationals, so the comparison
-- cannot overflow, underflow, or turn equality into positive skill by rounding
-- an RMSE. The positive target scale cancels from both squared-error sums;
-- validating it keeps this guard bound to the trainer's standardized units.
assertRegressionLearningSignal :: Double -> [Double] -> [Double] -> Either Text ()
assertRegressionLearningSignal scale targets predictions = do
  (squaredError, targetSquaredDeviation) <- regressionSquaredErrors scale targets predictions
  if squaredError < targetSquaredDeviation
    then Right ()
    else Left "admitted regressor does not strictly beat the best held-out constant predictor"

-- | Compare exact squared errors of finite binary64 prediction vectors.
-- An unchanged predictor, a tie, or an invalid initial vector cannot pass.
assertRegressionImprovement :: Double -> [Double] -> [Double] -> [Double] -> Either Text ()
assertRegressionImprovement scale targets initialPredictions finalPredictions = do
  (initialError, _) <- regressionSquaredErrors scale targets initialPredictions
  (finalError, _) <- regressionSquaredErrors scale targets finalPredictions
  if finalError < initialError
    then Right ()
    else Left "final regressor does not strictly improve over its initial predictor"

regressionSquaredErrors :: Double -> [Double] -> [Double] -> Either Text (Rational, Rational)
regressionSquaredErrors scale targets predictions
  | not (finite scale) || scale <= 0 =
      Left "regression learning-signal target scale must be positive and finite"
  | null targets = Left "regression learning-signal targets are empty"
  | length targets /= length predictions =
      Left "regression learning-signal predictions do not match the evaluation budget"
  | not (all finite targets) = Left "regression learning-signal target is non-finite"
  | not (all finite predictions) = Left "regression learning-signal prediction is non-finite"
  | targetSquaredDeviation <= 0 =
      Left "regression learning signal requires positive held-out target variance"
  | otherwise = Right (squaredError, targetSquaredDeviation)
 where
  exactTargets = fmap toRational targets
  targetMean = sum exactTargets / toRational (length targets)
  targetSquaredDeviation = sum [square (target - targetMean) | target <- exactTargets]
  squaredError =
    sum
      (zipWith (\prediction target -> square (toRational prediction - target)) predictions exactTargets)
  square value = value * value

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

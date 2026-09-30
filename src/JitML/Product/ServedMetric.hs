{-# LANGUAGE OverloadedStrings #-}

-- | Recompute a ProductRow's held-out measurement through the exact runtime
-- and weight tensor re-admitted from its persisted checkpoint. The constructor
-- of 'AdmittedCompletedCheckpoint' is private to Store, so a training-returned
-- model or a decoded but unaddressed manifest cannot enter this check.
module JitML.Product.ServedMetric
  ( HeldOutExamples (..)
  , assertAdmittedHeldOutMetric
  , heldOutExampleCount
  , recomputeAdmittedHeldOutMetric
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.Store qualified as CheckpointStore

-- | Inputs stay in the persisted runtime's ingress units. Classification
-- labels are class indices. Regression targets are in served output units;
-- the positive scale converts their error back to the standardized RMSE unit
-- in which the trainer reports its held-out metric.
data HeldOutExamples
  = HeldOutClassification ![([Double], Int)]
  | HeldOutRegression !Double ![([Double], Double)]
  deriving stock (Eq, Show)

heldOutExampleCount :: HeldOutExamples -> Int
heldOutExampleCount evidence =
  case evidence of
    HeldOutClassification examples -> length examples
    HeldOutRegression _ examples -> length examples

-- | The production serving path reconstructs the graph from the admitted
-- manifest and physical @supervised.weights@ tensor once, then evaluates the
-- verified held-out inputs. Store rejects substitution at an existing address;
-- a coherently readdressed replacement whose behavior changes the metric
-- fails this independent check before the row becomes eligible.
recomputeAdmittedHeldOutMetric
  :: CheckpointStore.AdmittedCompletedCheckpoint
  -> HeldOutExamples
  -> IO (Either Text Double)
recomputeAdmittedHeldOutMetric admitted evidence =
  pure $ do
    infer <-
      CheckpointStore.prepareSupervisedGraphCheckpointInference manifest weights
    case evidence of
      HeldOutClassification [] -> Left "held-out classification examples are empty"
      HeldOutClassification examples -> do
        predicted <- traverse (inferClassification infer . fst) examples
        let labels = fmap snd examples
        if or (zipWith (\label output -> label < 0 || label >= length output) labels predicted)
          then Left "held-out classification label lies outside the admitted runtime output"
          else
            let winners = fmap (VU.maxIndex . VU.fromList) predicted
                correct = length (filter id (zipWith (==) winners labels))
             in Right (fromIntegral correct / fromIntegral (length examples))
      HeldOutRegression scale [] ->
        if validScale scale
          then Left "held-out regression examples are empty"
          else Left "held-out regression target scale must be positive and finite"
      HeldOutRegression scale examples
        | not (validScale scale) ->
            Left "held-out regression target scale must be positive and finite"
        | otherwise -> do
            predicted <- traverse (inferRegression infer . fst) examples
            let targets = fmap snd examples
            if not (all finite targets)
              then Left "held-out regression target is non-finite"
              else
                let squaredErrors =
                      zipWith
                        (\prediction target -> ((prediction - target) / scale) ^ (2 :: Int))
                        predicted
                        targets
                    rmse = sqrt (sum squaredErrors / fromIntegral (length examples))
                 in if finite rmse
                      then Right rmse
                      else Left "admitted regression metric is non-finite"
 where
  checkpoint = CheckpointStore.admittedCompletedCheckpoint admitted
  manifest = CheckpointStore.admittedCheckpointManifest checkpoint
  weights = CheckpointStore.admittedCheckpointWeights checkpoint
  inferClassification infer input = do
    output <- infer input
    if null output || not (all finite output)
      then Left "admitted classification output is empty or non-finite"
      else Right output
  inferRegression infer input = do
    output <- infer input
    case output of
      [value] | finite value -> Right value
      _ -> Left "admitted regression output is not one finite scalar"

assertAdmittedHeldOutMetric
  :: CheckpointStore.AdmittedCompletedCheckpoint
  -> Text
  -> Double
  -> HeldOutExamples
  -> IO (Either Text ())
assertAdmittedHeldOutMetric admitted metricName reported evidence = do
  recomputed <- recomputeAdmittedHeldOutMetric admitted evidence
  pure $ do
    case evidence of
      HeldOutClassification _
        | metricName /= "test_accuracy" ->
            Left "classification held-out examples require test_accuracy"
      HeldOutRegression _ _
        | metricName /= "rmse" ->
            Left "regression held-out examples require rmse"
      _ -> Right ()
    measured <- recomputed
    if not (finite reported)
      then Left "reported held-out metric is non-finite"
      else
        let tolerance =
              case evidence of
                -- One borderline class decision is the maximum allowed
                -- divergence between the device trainer and the pure served
                -- graph on a fixed finite evaluation set.
                HeldOutClassification examples ->
                  min 0.01 (1.0 / fromIntegral (length examples) + 1.0e-9)
                HeldOutRegression _ _ -> 0.005 * max 1.0 (abs reported)
         in if abs (measured - reported) <= tolerance
              then Right ()
              else
                Left
                  ( "reported "
                      <> metricName
                      <> " does not match exact admitted served bytes (manifest="
                      <> CheckpointStore.admittedCheckpointManifestSha
                        (CheckpointStore.admittedCompletedCheckpoint admitted)
                      <> ", reported="
                      <> Text.pack (show reported)
                      <> ", served="
                      <> Text.pack (show measured)
                      <> ")"
                  )

validScale :: Double -> Bool
validScale value = finite value && value > 0.0

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

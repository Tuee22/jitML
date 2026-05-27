{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Ppo
  ( ppoLossForRollout
  , ppoModule
  , ppoHyperparameters
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , AlgorithmRollout (..)
  , hyperparameterRow
  , trajectoryRollout
  )
import JitML.RL.Algorithms.PpoLoss qualified as PpoLoss

ppoModule :: AlgorithmModule
ppoModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "PPO" OnPolicy False
    , moduleHyperparameters = ppoHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "PPO"
    }

-- | Sprint 13.8 — compute the real PPO total loss against a generated
-- 'AlgorithmRollout'. The function projects synthetic policy/value
-- inputs from the rollout's deterministic rewards so the loss is
-- reproducible without requiring a live network forward pass; the
-- real-network seam (Sprint 13.9 + 13.8 Remaining Work) replaces the
-- synthetic projection without changing the function shape callers
-- depend on. Two fresh calls with the same rollout produce
-- bit-equal output.
ppoLossForRollout :: AlgorithmRollout -> Double
ppoLossForRollout rollout =
  let rewards = rolloutRewards rollout
      values = fmap (* 0.5) rewards
      nextValues = case values of
        _ : rest -> rest <> [0.0]
        [] -> [0.0]
      advantages =
        PpoLoss.normaliseAdvantages
          (PpoLoss.gaeAdvantages 0.99 0.95 rewards values nextValues)
      oldLogProbs = fmap negate rewards
      newLogProbs = fmap (\r -> negate r + 0.01) rewards
   in PpoLoss.ppoTotalLoss
        0.2
        0.5
        0.01
        oldLogProbs
        newLogProbs
        advantages
        values
        rewards
        0.5

ppoHyperparameters :: [AlgorithmHyperparameter]
ppoHyperparameters =
  [ hyperparameterRow "clip-ratio" "0.2" True
  , hyperparameterRow "gae-lambda" "0.95" True
  , hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "value-coef" "0.5" True
  , hyperparameterRow "entropy-coef" "0.0" True
  , hyperparameterRow "kl-early-stop" "0.015" True
  , hyperparameterRow "optimizer" "AdamW" True
  , hyperparameterRow "rollout-length" "2048" True
  , hyperparameterRow "mini-batches" "32" True
  , hyperparameterRow "epochs-per-update" "10" True
  ]

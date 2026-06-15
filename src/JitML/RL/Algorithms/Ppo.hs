{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Ppo
  ( ppoModule
  , ppoHyperparameters
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

ppoModule :: AlgorithmModule
ppoModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "PPO" OnPolicy False
    , moduleHyperparameters = ppoHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "PPO"
    }

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

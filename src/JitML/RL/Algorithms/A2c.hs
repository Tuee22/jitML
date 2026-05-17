{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.A2c
  ( a2cHyperparameters
  , a2cModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

a2cModule :: AlgorithmModule
a2cModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "A2C" OnPolicy False
    , moduleHyperparameters = a2cHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "A2C"
    }

a2cHyperparameters :: [AlgorithmHyperparameter]
a2cHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "value-coef" "0.5" True
  , hyperparameterRow "entropy-coef" "0.01" True
  , hyperparameterRow "max-grad-norm" "0.5" True
  , hyperparameterRow "optimizer" "RMSProp" True
  , hyperparameterRow "rollout-length" "5" True
  , hyperparameterRow "lr" "0.0007" True
  ]

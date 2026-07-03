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
  , updateContract
  )

a2cModule :: AlgorithmModule
a2cModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "A2C" OnPolicy False
    , moduleHyperparameters = a2cHyperparameters
    , moduleUpdateContract =
        updateContract
          "on-policy.a2c.unclipped-advantage-actor-critic"
          "JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpole/VariantA2C"
          "rollout-buffer.gae.cartpole"
          "mlp-policy-value"
          ["unclipped-policy-gradient", "value-loss", "synchronous-actor-critic"]
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

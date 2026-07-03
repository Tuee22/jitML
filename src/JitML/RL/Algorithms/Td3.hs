{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Td3
  ( td3Hyperparameters
  , td3Module
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , updateContract
  )

td3Module :: AlgorithmModule
td3Module =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "TD3" OffPolicy True
    , moduleHyperparameters = td3Hyperparameters
    , moduleUpdateContract =
        updateContract
          "off-policy.td3.clipped-double-q-delayed-policy"
          "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantTD3"
          "replay-buffer.continuous-actions"
          "mlp-actor-twin-critic"
          ["twin-critics", "target-policy-smoothing", "delayed-actor-update"]
    }

td3Hyperparameters :: [AlgorithmHyperparameter]
td3Hyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "tau" "0.005" True
  , hyperparameterRow "policy-delay" "2" True
  , hyperparameterRow "target-policy-noise" "0.2" True
  , hyperparameterRow "target-noise-clip" "0.5" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "batch-size" "100" True
  ]

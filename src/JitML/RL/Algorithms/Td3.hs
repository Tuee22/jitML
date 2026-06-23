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
  )

td3Module :: AlgorithmModule
td3Module =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "TD3" OffPolicy True
    , moduleHyperparameters = td3Hyperparameters
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

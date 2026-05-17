{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Ddpg
  ( ddpgHyperparameters
  , ddpgModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

ddpgModule :: AlgorithmModule
ddpgModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "DDPG" OffPolicy True
    , moduleHyperparameters = ddpgHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "DDPG"
    }

ddpgHyperparameters :: [AlgorithmHyperparameter]
ddpgHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "tau" "0.005" True
  , hyperparameterRow "actor-lr" "0.0001" True
  , hyperparameterRow "critic-lr" "0.001" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "noise" "ornstein-uhlenbeck:0.2" True
  , hyperparameterRow "batch-size" "100" True
  ]

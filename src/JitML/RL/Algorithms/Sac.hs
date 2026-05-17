{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Sac
  ( sacHyperparameters
  , sacModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

sacModule :: AlgorithmModule
sacModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "SAC" OffPolicy True
    , moduleHyperparameters = sacHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "SAC"
    }

sacHyperparameters :: [AlgorithmHyperparameter]
sacHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "tau" "0.005" True
  , hyperparameterRow "alpha" "auto" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "batch-size" "256" True
  , hyperparameterRow "target-entropy" "-action-dim" True
  , hyperparameterRow "lr" "0.0003" True
  ]

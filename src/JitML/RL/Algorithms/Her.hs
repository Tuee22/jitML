{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Her
  ( herHyperparameters
  , herModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

herModule :: AlgorithmModule
herModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "HER" Specialized True
    , moduleHyperparameters = herHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "HER"
    }

herHyperparameters :: [AlgorithmHyperparameter]
herHyperparameters =
  [ hyperparameterRow "goal-selection-strategy" "future" True
  , hyperparameterRow "n-sampled-goal" "4" True
  , hyperparameterRow "wrapped-algorithm" "SAC" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "batch-size" "256" True
  ]

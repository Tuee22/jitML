{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Tqc
  ( tqcHyperparameters
  , tqcModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

tqcModule :: AlgorithmModule
tqcModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "TQC" Specialized True
    , moduleHyperparameters = tqcHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "TQC"
    }

tqcHyperparameters :: [AlgorithmHyperparameter]
tqcHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "num-critics" "5" True
  , hyperparameterRow "num-quantiles-per-critic" "25" True
  , hyperparameterRow "num-quantiles-to-drop" "2" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "batch-size" "256" True
  ]

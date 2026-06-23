{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.CrossQ
  ( crossQHyperparameters
  , crossQModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  )

crossQModule :: AlgorithmModule
crossQModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "CrossQ" Specialized True
    , moduleHyperparameters = crossQHyperparameters
    }

crossQHyperparameters :: [AlgorithmHyperparameter]
crossQHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "batch-renorm" "true" True
  , hyperparameterRow "target-network" "none" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "batch-size" "256" True
  , hyperparameterRow "lr" "0.001" True
  ]

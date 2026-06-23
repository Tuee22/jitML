{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Ars
  ( arsHyperparameters
  , arsModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  )

arsModule :: AlgorithmModule
arsModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "ARS" Specialized False
    , moduleHyperparameters = arsHyperparameters
    }

arsHyperparameters :: [AlgorithmHyperparameter]
arsHyperparameters =
  [ hyperparameterRow "noise-std" "0.025" True
  , hyperparameterRow "num-deltas" "16" True
  , hyperparameterRow "num-top-deltas" "8" True
  , hyperparameterRow "lr" "0.02" True
  , hyperparameterRow "linear-policy-only" "true" True
  ]

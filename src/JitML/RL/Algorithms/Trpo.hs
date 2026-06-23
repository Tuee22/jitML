{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Trpo
  ( trpoHyperparameters
  , trpoModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  )

trpoModule :: AlgorithmModule
trpoModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "TRPO" OnPolicy False
    , moduleHyperparameters = trpoHyperparameters
    }

trpoHyperparameters :: [AlgorithmHyperparameter]
trpoHyperparameters =
  [ hyperparameterRow "max-kl" "0.01" True
  , hyperparameterRow "cg-iterations" "10" True
  , hyperparameterRow "cg-residual-tol" "1e-10" True
  , hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "gae-lambda" "0.95" True
  , hyperparameterRow "backtrack-iterations" "10" True
  , hyperparameterRow "backtrack-coef" "0.8" True
  ]

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
  , updateContract
  )

crossQModule :: AlgorithmModule
crossQModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "CrossQ" Specialized True
    , moduleHyperparameters = crossQHyperparameters
    , moduleUpdateContract =
        updateContract
          "off-policy.crossq.batch-renorm-no-target-network"
          "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantCrossQ"
          "replay-buffer.continuous-actions"
          "mlp-stochastic-actor-online-twin-critic"
          ["batch-renormalized-q-target", "no-target-network", "entropy-regularized-target"]
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

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
  , updateContract
  )

sacModule :: AlgorithmModule
sacModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "SAC" OffPolicy True
    , moduleHyperparameters = sacHyperparameters
    , moduleUpdateContract =
        updateContract
          "off-policy.sac.entropy-regularized-twin-critic"
          "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantSAC"
          "replay-buffer.continuous-actions"
          "mlp-stochastic-actor-twin-critic"
          ["entropy-regularized-target", "twin-critics", "temperature-weighted-policy-loss"]
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

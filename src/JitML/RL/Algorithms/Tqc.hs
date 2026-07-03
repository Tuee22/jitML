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
  , updateContract
  )

tqcModule :: AlgorithmModule
tqcModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "TQC" Specialized True
    , moduleHyperparameters = tqcHyperparameters
    , moduleUpdateContract =
        updateContract
          "off-policy.tqc.truncated-quantile-critics"
          "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantTQC"
          "replay-buffer.continuous-actions"
          "mlp-stochastic-actor-quantile-critics"
          ["pooled-critic-atoms", "top-atom-truncation", "entropy-regularized-target"]
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

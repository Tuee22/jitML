{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Dqn
  ( dqnHyperparameters
  , dqnModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , updateContract
  )

dqnModule :: AlgorithmModule
dqnModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "DQN" OffPolicy True
    , moduleHyperparameters = dqnHyperparameters
    , moduleUpdateContract =
        updateContract
          "off-policy.dqn.scalar-bellman-target-network"
          "JitML.RL.Algorithms.DqnTrainer.trainDqnOnCartpole"
          "replay-buffer.epsilon-greedy"
          "mlp-q-network"
          ["scalar-q-head", "hard-target-network", "td-residual"]
    }

dqnHyperparameters :: [AlgorithmHyperparameter]
dqnHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "epsilon-start" "1.0" True
  , hyperparameterRow "epsilon-final" "0.05" True
  , hyperparameterRow "epsilon-decay-steps" "10000" True
  , hyperparameterRow "buffer-capacity" "100000" True
  , hyperparameterRow "target-update-interval" "1000" True
  , hyperparameterRow "double-q" "true" True
  , hyperparameterRow "optimizer" "Adam" True
  , hyperparameterRow "lr" "0.00025" True
  ]

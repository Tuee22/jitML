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
  , updateContract
  )

herModule :: AlgorithmModule
herModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "HER" Specialized True
    , moduleHyperparameters = herHyperparameters
    , moduleUpdateContract =
        updateContract
          "goal-conditioned.her.future-relabeling-off-policy-wrapper"
          "JitML.RL.Algorithms.HerTrainer.trainHerOnBitFlip"
          "her-wrapper.replay-buffer.goal-conditioned"
          "goal-conditioned-q-network"
          ["future-goal-relabeling", "sparse-goal-reward", "off-policy-q-update"]
    }

herHyperparameters :: [AlgorithmHyperparameter]
herHyperparameters =
  [ hyperparameterRow "goal-selection-strategy" "future" True
  , hyperparameterRow "n-sampled-goal" "4" True
  , hyperparameterRow "wrapped-algorithm" "SAC" True
  , hyperparameterRow "buffer-capacity" "1000000" True
  , hyperparameterRow "batch-size" "256" True
  ]

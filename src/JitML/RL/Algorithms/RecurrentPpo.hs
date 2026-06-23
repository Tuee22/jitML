{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.RecurrentPpo
  ( recurrentPpoHyperparameters
  , recurrentPpoModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  )

recurrentPpoModule :: AlgorithmModule
recurrentPpoModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "RecurrentPPO" OnPolicy False
    , moduleHyperparameters = recurrentPpoHyperparameters
    }

recurrentPpoHyperparameters :: [AlgorithmHyperparameter]
recurrentPpoHyperparameters =
  [ hyperparameterRow "clip-ratio" "0.2" True
  , hyperparameterRow "gae-lambda" "0.95" True
  , hyperparameterRow "lstm-hidden" "128" True
  , hyperparameterRow "sequence-length" "16" True
  , hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "rollout-length" "2048" True
  ]

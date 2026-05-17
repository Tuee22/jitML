{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.QrDqn
  ( qrDqnHyperparameters
  , qrDqnModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , trajectoryRollout
  )

qrDqnModule :: AlgorithmModule
qrDqnModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "QR-DQN" OffPolicy True
    , moduleHyperparameters = qrDqnHyperparameters
    , moduleRolloutGenerator = trajectoryRollout "QR-DQN"
    }

qrDqnHyperparameters :: [AlgorithmHyperparameter]
qrDqnHyperparameters =
  [ hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "num-quantiles" "200" True
  , hyperparameterRow "kappa" "1.0" True
  , hyperparameterRow "buffer-capacity" "100000" True
  , hyperparameterRow "target-update-interval" "1000" True
  , hyperparameterRow "huber-loss" "true" True
  ]

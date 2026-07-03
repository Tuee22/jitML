{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.MaskablePpo
  ( maskablePpoHyperparameters
  , maskablePpoModule
  )
where

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter
  , AlgorithmModule (..)
  , hyperparameterRow
  , updateContract
  )

maskablePpoModule :: AlgorithmModule
maskablePpoModule =
  AlgorithmModule
    { moduleAlgorithm = RLAlgorithm "MaskablePPO" OnPolicy False
    , moduleHyperparameters = maskablePpoHyperparameters
    , moduleUpdateContract =
        updateContract
          "on-policy.maskable-ppo.masked-categorical-clipped-surrogate"
          "JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpole/VariantMaskablePPO"
          "rollout-buffer.gae.action-mask"
          "mlp-policy-value"
          ["masked-categorical", "clipped-surrogate", "invalid-action-elimination"]
    }

maskablePpoHyperparameters :: [AlgorithmHyperparameter]
maskablePpoHyperparameters =
  [ hyperparameterRow "clip-ratio" "0.2" True
  , hyperparameterRow "gae-lambda" "0.95" True
  , hyperparameterRow "discount-gamma" "0.99" True
  , hyperparameterRow "action-mask" "boolean" True
  , hyperparameterRow "invalid-action-penalty" "-inf" True
  , hyperparameterRow "rollout-length" "2048" True
  ]

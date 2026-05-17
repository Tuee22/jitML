-- | Training-progress panel. Streams `EpochCompleted` events from the daemon
-- via `/api/ws` and animates the loss curve.
module Panels.Training where

import Prelude

import Effect (Effect)

type TrainingFrame =
  { panel :: String
  , experimentHash :: String
  , epoch :: Int
  , trainingLoss :: Number
  , validationLoss :: Number
  , timestampNs :: Int
  }

panelName :: String
panelName = "training-progress"

renderFrame :: String -> Int -> Number -> Number -> Int -> TrainingFrame
renderFrame experimentHash epoch trainingLoss validationLoss timestampNs =
  { panel: panelName
  , experimentHash
  , epoch
  , trainingLoss
  , validationLoss
  , timestampNs
  }

mount :: Effect Unit
mount = pure unit

-- | Hyperparameter-sweep panel. Renders trial transcripts streamed from
-- `tune.event.<mode>` via `/api/ws`.
module Panels.Tune where

import Prelude

import Effect (Effect)

type TuneTrialFrame =
  { panel :: String
  , trialIndex :: Int
  , trialSeed :: Int
  , objective :: Number
  , pruned :: Boolean
  , parametersJson :: String
  }

type TuneSweepDoneFrame =
  { panel :: String
  , trialsCompleted :: Int
  , trialsPruned :: Int
  , bestObjective :: Number
  }

panelName :: String
panelName = "hyperparameter-sweep"

renderTrialFrame :: Int -> Int -> Number -> Boolean -> String -> TuneTrialFrame
renderTrialFrame trialIndex trialSeed objective pruned parametersJson =
  { panel: panelName
  , trialIndex
  , trialSeed
  , objective
  , pruned
  , parametersJson
  }

mount :: Effect Unit
mount = pure unit

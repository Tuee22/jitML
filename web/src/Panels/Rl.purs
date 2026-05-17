-- | RL rollout trajectory panel. Streams per-step env observations and
-- per-episode reward from the daemon's RlHandler via `/api/ws`.
module Panels.Rl where

import Prelude

import Effect (Effect)

type RlStreamFrame =
  { panel :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , reward :: Number
  , done :: Boolean
  , observationHash :: Int
  }

panelName :: String
panelName = "rl-trajectory"

renderFrame :: Int -> Int -> Number -> Boolean -> Int -> RlStreamFrame
renderFrame episodeIndex stepIndex reward done observationHash =
  { panel: panelName
  , episodeIndex
  , stepIndex
  , reward
  , done
  , observationHash
  }

mount :: Effect Unit
mount = pure unit

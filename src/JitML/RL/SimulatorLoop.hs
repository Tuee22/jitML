{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Episode driver for the pure-Haskell simulators under
-- "JitML.RL.Simulator". Sprint 13.5 — the worker-side @jitml rl train@
-- entry point runs this loop against the simulator chosen by the
-- @JITML_ENVIRONMENT@ env var for cartpole / mountain-car / lunar-lander /
-- key-door-grid, publishes a per-episode @RlEpisode@ event to the broker, and
-- prints the summary. The @atari-subset@ environment is ALE-backed in
-- "JitML.RL.ALE".
-- The policy is the
-- deterministic
-- @action = (stepIx + episodeId + seed) `mod` actionCount@ rule from the
-- existing 'JitML.RL.Loop.runRLLoop' so a real RL math implementation
-- (Sprint 13.8) plugs in without changing the driver shape.
module JitML.RL.SimulatorLoop
  ( SimulatedEnvByName (..)
  , SimulatedEpisode (..)
  , lookupSimulatedEnvByName
  , runSimulatedEpisode
  , runSimulatedEpisodes
  , runSimulatedEpisodesByName
  , simulatedEnvCatalog
  )
where

import Data.Text (Text)

import JitML.RL.Simulator
  ( SimStep (..)
  , SimulatedEnvironment (..)
  , cartPoleEnvironment
  , keyDoorGridEnvironment
  , lunarLanderEnvironment
  , mountainCarEnvironment
  )

data SimulatedEpisode = SimulatedEpisode
  { simEpisodeIndex :: Int
  , simEpisodeSteps :: Int
  , simEpisodeReward :: Double
  , simEpisodeDone :: Bool
  }
  deriving stock (Eq, Show)

-- | Existential wrapper around the native pure-Haskell canonical simulators so callers
-- look an environment up by name without having to plumb the per-env
-- state type through their own signatures.
data SimulatedEnvByName
  = forall state. SimulatedEnvByName Text (SimulatedEnvironment state)

simulatedEnvCatalog :: [(Text, SimulatedEnvByName)]
simulatedEnvCatalog =
  [ ("cartpole", SimulatedEnvByName "cartpole" cartPoleEnvironment)
  , ("mountain-car", SimulatedEnvByName "mountain-car" mountainCarEnvironment)
  , ("lunar-lander", SimulatedEnvByName "lunar-lander" lunarLanderEnvironment)
  , ("key-door-grid", SimulatedEnvByName "key-door-grid" keyDoorGridEnvironment)
  , ("KeyDoorGrid-v0", SimulatedEnvByName "key-door-grid" keyDoorGridEnvironment)
  ]

lookupSimulatedEnvByName :: Text -> Maybe SimulatedEnvByName
lookupSimulatedEnvByName name = lookup name simulatedEnvCatalog

-- | Run one episode against the supplied simulator. The policy is the
-- deterministic @action = (stepIx + episodeId + seed) `mod` actionCount@
-- selector — the same shape the pre-sprint @runRLLoop@ used. A real
-- RL policy plugs in by replacing the policy expression with a JIT-engine
-- forward pass (Sprint 13.8).
runSimulatedEpisode
  :: SimulatedEnvironment state -> Int -> Int -> Int -> SimulatedEpisode
runSimulatedEpisode env seed episodeId maxSteps =
  go (envInitial env) 0.0 0
 where
  actionCount = max 1 (envActionCount env)
  go state acc stepIx
    | stepIx >= maxSteps =
        SimulatedEpisode
          { simEpisodeIndex = episodeId
          , simEpisodeSteps = stepIx
          , simEpisodeReward = acc
          , simEpisodeDone = False
          }
    | otherwise =
        let action = (stepIx + episodeId + seed) `mod` actionCount
            step = envStep env state action
            acc' = acc + simStepReward step
         in if simStepDone step
              then
                SimulatedEpisode
                  { simEpisodeIndex = episodeId
                  , simEpisodeSteps = stepIx + 1
                  , simEpisodeReward = acc'
                  , simEpisodeDone = True
                  }
              else go (simStepState step) acc' (stepIx + 1)

runSimulatedEpisodes
  :: SimulatedEnvironment state -> Int -> Int -> Int -> [SimulatedEpisode]
runSimulatedEpisodes env seed count maxSteps =
  [runSimulatedEpisode env seed episodeId maxSteps | episodeId <- [0 .. count - 1]]

runSimulatedEpisodesByName
  :: SimulatedEnvByName -> Int -> Int -> Int -> [SimulatedEpisode]
runSimulatedEpisodesByName (SimulatedEnvByName _name env) =
  runSimulatedEpisodes env

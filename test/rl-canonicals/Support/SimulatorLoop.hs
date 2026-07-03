{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Test-support driver for the pure-Haskell simulators under
-- "JitML.RL.Simulator". Product RL dispatch does not import this module; it is
-- kept for scaffolding-labeled deterministic canonical checks.
module Support.SimulatorLoop
  ( SimulatedEnvByName (..)
  , SimulatedEpisode (..)
  , SimulatedFrame (..)
  , lookupSimulatedEnvByName
  , runSimulatedEpisode
  , runSimulatedEpisodes
  , runSimulatedEpisodesByName
  , simulatedEnvCatalog
  )
where

import Data.Text (Text)

import JitML.RL.EpisodeEnvelope (SimulatedEpisode (..), SimulatedFrame (..))
import JitML.RL.Simulator
  ( SimStep (..)
  , SimulatedEnvironment (..)
  , acrobotEnvironment
  , cartPoleEnvironment
  , gridWorldEnvironment
  , keyDoorGridEnvironment
  , lunarLanderEnvironment
  , mountainCarEnvironment
  , pendulumDiscreteEnvironment
  , renderCaption
  , renderObservation
  )

-- | Existential wrapper around the native pure-Haskell canonical simulators so callers
-- look an environment up by name without having to plumb the per-env
-- state type through their own signatures.
data SimulatedEnvByName
  = forall state. SimulatedEnvByName Text (SimulatedEnvironment state)

simulatedEnvCatalog :: [(Text, SimulatedEnvByName)]
simulatedEnvCatalog =
  [ ("cartpole", SimulatedEnvByName "cartpole" cartPoleEnvironment)
  , ("mountain-car", SimulatedEnvByName "mountain-car" mountainCarEnvironment)
  , ("acrobot", SimulatedEnvByName "acrobot" acrobotEnvironment)
  , ("pendulum", SimulatedEnvByName "pendulum" pendulumDiscreteEnvironment)
  , ("lunar-lander", SimulatedEnvByName "lunar-lander" lunarLanderEnvironment)
  , ("key-door-grid", SimulatedEnvByName "key-door-grid" keyDoorGridEnvironment)
  , ("KeyDoorGrid-v0", SimulatedEnvByName "key-door-grid" keyDoorGridEnvironment)
  , ("gridworld-deterministic", SimulatedEnvByName "gridworld-deterministic" gridWorldEnvironment)
  , ("GridWorld-Deterministic-v0", SimulatedEnvByName "gridworld-deterministic" gridWorldEnvironment)
  ]

lookupSimulatedEnvByName :: Text -> Maybe SimulatedEnvByName
lookupSimulatedEnvByName name = lookup name simulatedEnvCatalog

runSimulatedEpisode
  :: SimulatedEnvironment state -> Int -> Int -> Int -> SimulatedEpisode
runSimulatedEpisode env seed episodeId maxSteps =
  go (envInitial env) 0.0 0 []
 where
  actionCount = max 1 (envActionCount env)
  go state acc stepIx frames
    | stepIx >= maxSteps =
        SimulatedEpisode
          { simEpisodeIndex = episodeId
          , simEpisodeSteps = stepIx
          , simEpisodeReward = acc
          , simEpisodeDone = False
          , simEpisodeFrames = reverse frames
          }
    | otherwise =
        let action = (stepIx + episodeId + seed) `mod` actionCount
            currentFrame = envRenderFrame env state
            step = envStep env state action
            nextFrame = envRenderFrame env (simStepState step)
            acc' = acc + simStepReward step
            emittedFrame =
              SimulatedFrame
                { simFrameEpisodeIndex = episodeId
                , simFrameStepIndex = stepIx
                , simFrameAction = action
                , simFrameReward = simStepReward step
                , simFrameDone = simStepDone step
                , simFrameObservation = renderObservation currentFrame
                , simFrameNextObservation = renderObservation nextFrame
                , simFrameActionProbabilities =
                    [ if actionIx == action then 1.0 else 0.0
                    | actionIx <- [0 .. actionCount - 1]
                    ]
                , simFrameCaption = renderCaption nextFrame
                }
            frames' = emittedFrame : frames
         in if simStepDone step
              then
                SimulatedEpisode
                  { simEpisodeIndex = episodeId
                  , simEpisodeSteps = stepIx + 1
                  , simEpisodeReward = acc'
                  , simEpisodeDone = True
                  , simEpisodeFrames = reverse frames'
                  }
              else go (simStepState step) acc' (stepIx + 1) frames'

runSimulatedEpisodes
  :: SimulatedEnvironment state -> Int -> Int -> Int -> [SimulatedEpisode]
runSimulatedEpisodes env seed count maxSteps =
  [runSimulatedEpisode env seed episodeId maxSteps | episodeId <- [0 .. count - 1]]

runSimulatedEpisodesByName
  :: SimulatedEnvByName -> Int -> Int -> Int -> [SimulatedEpisode]
runSimulatedEpisodesByName (SimulatedEnvByName _name env) =
  runSimulatedEpisodes env

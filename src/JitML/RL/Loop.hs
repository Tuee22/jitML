{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Loop
  ( EpisodeResult (..)
  , RLConfig (..)
  , RLLoop (..)
  , RLLoopResult (..)
  , defaultRLConfig
  , renderRLLoopResult
  , rlEpisodes
  , runRLLoop
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Algorithms (RLAlgorithm (..))
import JitML.RL.Buffer (BufferKind (..), ReplayBuffer, Transition (..), bufferInsert, emptyBuffer)
import JitML.RL.Environments (EnvStep (..), RLEnvironment (..), deterministicStep)
import JitML.RL.Framework (RLRunPhase (..), rlRunPlan)
import JitML.RL.Policy (Policy, policyName)

data RLConfig = RLConfig
  { rlSeed :: Int
  , rlMaxEpisodes :: Int
  , rlMaxStepsPerEpisode :: Int
  , rlBufferCapacity :: Int
  , rlEvalEpisodes :: Int
  , rlRewardTarget :: Double
  }
  deriving stock (Eq, Show)

defaultRLConfig :: RLConfig
defaultRLConfig =
  RLConfig
    { rlSeed = 42
    , rlMaxEpisodes = 8
    , rlMaxStepsPerEpisode = 64
    , rlBufferCapacity = 1024
    , rlEvalEpisodes = 4
    , rlRewardTarget = 0.0
    }

data RLLoop = RLLoop
  { loopAlgorithm :: RLAlgorithm
  , loopPolicy :: Policy
  , loopEnvironment :: RLEnvironment
  , loopConfig :: RLConfig
  }
  deriving stock (Eq, Show)

data EpisodeResult = EpisodeResult
  { episodeIndex :: Int
  , episodeReward :: Double
  , episodeSteps :: Int
  , episodeDone :: Bool
  , episodeTransitions :: [Transition]
  }
  deriving stock (Eq, Show)

data RLLoopResult = RLLoopResult
  { resultAlgorithmName :: Text
  , resultPolicyName :: Text
  , resultEnvironmentName :: Text
  , resultEpisodes :: [EpisodeResult]
  , resultFinalAverageReward :: Double
  , resultBuffer :: ReplayBuffer
  , resultPhases :: [RLRunPhase]
  }
  deriving stock (Eq, Show)

runRLLoop :: RLLoop -> RLLoopResult
runRLLoop loop =
  let episodes = rlEpisodes loop
      avg =
        if null episodes
          then 0.0
          else sum (fmap episodeReward episodes) / fromIntegral (length episodes)
      bufferKind =
        if algorithmReplayBased (loopAlgorithm loop) then OffPolicyReplay else OnPolicyRollout
      buffer =
        foldl
          (flip bufferInsert)
          (emptyBuffer bufferKind (rlBufferCapacity (loopConfig loop)))
          (concatMap episodeTransitions episodes)
   in RLLoopResult
        { resultAlgorithmName = algorithmName (loopAlgorithm loop)
        , resultPolicyName = policyName (loopPolicy loop)
        , resultEnvironmentName = environmentName (loopEnvironment loop)
        , resultEpisodes = episodes
        , resultFinalAverageReward = avg
        , resultBuffer = buffer
        , resultPhases = rlRunPlan
        }

rlEpisodes :: RLLoop -> [EpisodeResult]
rlEpisodes loop =
  [ runOneEpisode loop episodeId
  | episodeId <- [0 .. rlMaxEpisodes (loopConfig loop) - 1]
  ]

runOneEpisode :: RLLoop -> Int -> EpisodeResult
runOneEpisode loop episodeId =
  let environment = loopEnvironment loop
      maxSteps = rlMaxStepsPerEpisode (loopConfig loop)
      seed = rlSeed (loopConfig loop) + episodeId
      walk acc transitions stepIx
        | stepIx >= maxSteps = finalize acc transitions stepIx False
        | otherwise =
            let action = (stepIx + episodeId) `mod` max 1 (environmentActionCount environment)
                step = deterministicStep environment seed action
                transition =
                  Transition
                    { transitionStep = stepIx
                    , transitionAction = action
                    , transitionReward = stepReward step
                    , transitionObservation = stepObservationHash step
                    , transitionDone = stepDone step
                    }
                acc' = acc + stepReward step
                transitions' = transition : transitions
             in if stepDone step
                  then finalize acc' transitions' (stepIx + 1) True
                  else walk acc' transitions' (stepIx + 1)
      finalize acc transitions steps done =
        EpisodeResult
          { episodeIndex = episodeId
          , episodeReward = acc
          , episodeSteps = steps
          , episodeDone = done
          , episodeTransitions = reverse transitions
          }
   in walk 0.0 [] 0

renderRLLoopResult :: RLLoopResult -> Text
renderRLLoopResult result =
  Text.unlines
    [ "algorithm: " <> resultAlgorithmName result
    , "policy: " <> resultPolicyName result
    , "environment: " <> resultEnvironmentName result
    , "episodes: " <> Text.pack (show (length (resultEpisodes result)))
    , "avg-reward: " <> Text.pack (show (resultFinalAverageReward result))
    , "phases: " <> Text.intercalate "->" (fmap (Text.pack . show) (resultPhases result))
    ]

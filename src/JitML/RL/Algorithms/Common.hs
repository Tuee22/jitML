{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter (..)
  , AlgorithmModule (..)
  , AlgorithmRollout (..)
  , hyperparameterRow
  , renderAlgorithmModule
  , renderHyperparameters
  , renderRollout
  , trajectoryRollout
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))
import JitML.RL.SimulatorLoop qualified as SimulatorLoop

data AlgorithmHyperparameter = AlgorithmHyperparameter
  { hyperName :: Text
  , hyperValue :: Text
  , hyperDeterministicOnly :: Bool
  }
  deriving stock (Eq, Show)

data AlgorithmRollout = AlgorithmRollout
  { rolloutAlgorithm :: Text
  , rolloutEnvironment :: Text
  , rolloutSeed :: Int
  , rolloutActions :: [Int]
  , rolloutRewards :: [Double]
  }
  deriving stock (Eq, Show)

data AlgorithmModule = AlgorithmModule
  { moduleAlgorithm :: RLAlgorithm
  , moduleHyperparameters :: [AlgorithmHyperparameter]
  , moduleRolloutGenerator :: Text -> Int -> Int -> AlgorithmRollout
  -- ^ environmentName -> seed -> horizon -> rollout
  }

hyperparameterRow :: Text -> Text -> Bool -> AlgorithmHyperparameter
hyperparameterRow = AlgorithmHyperparameter

renderHyperparameters :: [AlgorithmHyperparameter] -> Text
renderHyperparameters hyperparameters =
  Text.unlines
    [ "  - " <> hyperName h <> " = " <> hyperValue h <> deterministicMarker h
    | h <- hyperparameters
    ]
 where
  deterministicMarker h
    | hyperDeterministicOnly h = "  [deterministic-only]"
    | otherwise = ""

renderRollout :: AlgorithmRollout -> Text
renderRollout rollout =
  Text.unlines $
    "actions:"
      : ["  - " <> Text.pack (show a) | a <- rolloutActions rollout]
        <> ("rewards:" : ["  - " <> Text.pack (show r) | r <- rolloutRewards rollout])

renderAlgorithmModule :: AlgorithmModule -> Text
renderAlgorithmModule m =
  Text.unlines
    [ "algorithm: " <> algorithmName (moduleAlgorithm m)
    , "family: " <> renderFamily (algorithmFamily (moduleAlgorithm m))
    , "replay-based: " <> if algorithmReplayBased (moduleAlgorithm m) then "yes" else "no"
    , "hyperparameters:"
    , renderHyperparameters (moduleHyperparameters m)
    ]
 where
  renderFamily OnPolicy = "on-policy"
  renderFamily OffPolicy = "off-policy"
  renderFamily Specialized = "specialised"
  renderFamily SelfPlay = "self-play"

-- | Sprint 9.9 — the canonical rollout generator used by every algorithm
-- module. It steps the __real__ named environment dynamics
-- ('JitML.RL.SimulatorLoop.realRolloutByName') for @horizon@ steps with a
-- deterministic seeded policy, returning the real per-step actions + rewards —
-- replacing the former per-sampler LCG. The per-algorithm module derives its own
-- seed perturbation (the algorithm-name length is folded into the policy seed)
-- so each algorithm × env rollout is distinct yet deterministic. The
-- substrate-device-backed /trained/ policy rollout is the live follow-on
-- (Phase 13); this surface exercises real environment dynamics with a
-- deterministic policy.
trajectoryRollout :: Text -> Text -> Int -> Int -> AlgorithmRollout
trajectoryRollout algoName envName seed horizon =
  let (actions, rewards) =
        fromMaybe
          ([], [])
          (SimulatorLoop.realRolloutByName envName (seed + Text.length algoName) (max 1 horizon))
   in AlgorithmRollout
        { rolloutAlgorithm = algoName
        , rolloutEnvironment = envName
        , rolloutSeed = seed
        , rolloutActions = actions
        , rolloutRewards = rewards
        }

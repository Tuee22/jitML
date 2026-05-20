{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter (..)
  , AlgorithmModule (..)
  , AlgorithmRollout (..)
  , goldenTrajectoryPath
  , hyperparameterRow
  , renderAlgorithmModule
  , renderHyperparameters
  , renderRollout
  , rolloutGoldenLines
  , trajectoryRollout
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))

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

goldenTrajectoryPath :: AlgorithmRollout -> FilePath
goldenTrajectoryPath rollout =
  "test/golden/rl/"
    <> Text.unpack (Text.toLower (rolloutAlgorithm rollout))
    <> "/"
    <> Text.unpack (rolloutEnvironment rollout)
    <> "/trajectory.txt"

rolloutGoldenLines :: AlgorithmRollout -> [Text]
rolloutGoldenLines rollout =
  [ "# " <> rolloutAlgorithm rollout <> "/" <> rolloutEnvironment rollout
  , "# seed=" <> Text.pack (show (rolloutSeed rollout))
  ]
    <> [ Text.pack (show a) <> " " <> Text.pack (show r)
       | (a, r) <- zip (rolloutActions rollout) (rolloutRewards rollout)
       ]

-- | Default rollout generator used by every algorithm module. The per-algorithm
-- module derives its own seed perturbation (added in `seed` argument) so each
-- algorithm × env fixture is distinct yet deterministic.
trajectoryRollout :: Text -> Text -> Int -> Int -> AlgorithmRollout
trajectoryRollout algoName envName seed horizon =
  AlgorithmRollout
    { rolloutAlgorithm = algoName
    , rolloutEnvironment = envName
    , rolloutSeed = seed
    , rolloutActions = take horizon (iterate stepAction seed)
    , rolloutRewards =
        take horizon (zipWith rewardFor (iterate stepAction seed) [0 :: Int ..])
    }
 where
  stepAction value = (value * 1103515245 + 12345 + Text.length algoName) `mod` 9973
  rewardFor a step =
    let base = fromIntegral (a `mod` 1009) / 1009.0
        decay = 1.0 - fromIntegral step / fromIntegral (max 1 horizon)
     in base * decay

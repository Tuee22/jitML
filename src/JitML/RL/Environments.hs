{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Environments
  ( EnvironmentKind (..)
  , EnvStep (..)
  , RLEnvironment (..)
  , canonicalEnvironments
  , deterministicStep
  , renderEnvironmentCatalog
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data EnvironmentKind
  = ClassicControl
  | Box2D
  | Atari
  deriving stock (Eq, Show)

data RLEnvironment = RLEnvironment
  { environmentName :: Text
  , environmentKind :: EnvironmentKind
  , environmentObservationSize :: Int
  , environmentActionCount :: Int
  , environmentRewardTarget :: Double
  }
  deriving stock (Eq, Show)

data EnvStep = EnvStep
  { stepObservationHash :: Int
  , stepReward :: Double
  , stepDone :: Bool
  }
  deriving stock (Eq, Show)

canonicalEnvironments :: [RLEnvironment]
canonicalEnvironments =
  [ RLEnvironment "cartpole" ClassicControl 4 2 475.0
  , RLEnvironment "mountain-car" ClassicControl 2 3 (-110.0)
  , RLEnvironment "lunar-lander" Box2D 8 4 200.0
  , RLEnvironment "atari-subset" Atari 128 18 20.0
  ]

deterministicStep :: RLEnvironment -> Int -> Int -> EnvStep
deterministicStep environment seed action =
  EnvStep
    { stepObservationHash = observationHash
    , stepReward = reward
    , stepDone = observationHash `mod` 17 == 0
    }
 where
  observationHash =
    (seed * 1103515245 + action * 97 + environmentActionCount environment) `mod` 65521
  reward =
    fromIntegral (observationHash `mod` 100) / 100.0
      + fromIntegral (Text.length (environmentName environment)) / 1000.0

renderEnvironmentCatalog :: Text
renderEnvironmentCatalog =
  Text.unlines $
    [ "| Environment | Kind | Actions |"
    , "|-------------|------|---------|"
    ]
      <> fmap renderRow canonicalEnvironments
 where
  renderRow environment =
    "| `"
      <> environmentName environment
      <> "` | "
      <> Text.pack (show (environmentKind environment))
      <> " | "
      <> Text.pack (show (environmentActionCount environment))
      <> " |"

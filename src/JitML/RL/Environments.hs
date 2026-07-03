{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Environments
  ( ActionSpace (..)
  , EnvironmentKind (..)
  , EnvStep (..)
  , RLEnvironment (..)
  , canonicalEnvironments
  , renderEnvironmentCatalog
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data EnvironmentKind
  = ClassicControl
  | Box2D
  | GridWorld
  | Atari
  deriving stock (Eq, Show)

data ActionSpace
  = DiscreteActions Int
  | ContinuousActions Int Double Double
  deriving stock (Eq, Show)

data RLEnvironment = RLEnvironment
  { environmentName :: Text
  , environmentKind :: EnvironmentKind
  , environmentObservationSize :: Int
  , environmentActionCount :: Int
  , environmentActionSpace :: ActionSpace
  , environmentRewardTarget :: Double
  , environmentRewardFunction :: Text
  , environmentTermination :: Text
  , environmentHorizon :: Int
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
  [ RLEnvironment
      "cartpole"
      ClassicControl
      4
      2
      (DiscreteActions 2)
      475.0
      "+1 per nonterminal step"
      "cart position or pole angle out of bounds"
      500
  , RLEnvironment
      "mountain-car"
      ClassicControl
      2
      3
      (DiscreteActions 3)
      (-110.0)
      "-1 per step until goal"
      "position reaches the hilltop goal"
      200
  , RLEnvironment
      "acrobot"
      ClassicControl
      6
      3
      (DiscreteActions 3)
      (-100.0)
      "-1 per swing-up step"
      "tip height rises above the target line"
      500
  , RLEnvironment
      "pendulum"
      ClassicControl
      3
      1
      (ContinuousActions 1 (-2.0) 2.0)
      (-200.0)
      "negative angle/velocity/torque cost"
      "fixed horizon"
      200
  , RLEnvironment
      "lunar-lander"
      Box2D
      8
      4
      (DiscreteActions 4)
      200.0
      "Gym-style shaping plus landing/crash terminal bonus"
      "crash, soft landing, or out-of-bounds"
      1000
  , RLEnvironment
      "key-door-grid"
      GridWorld
      127
      6
      (DiscreteActions 6)
      1.0
      "step cost with key, door, and goal bonuses"
      "goal reached after key pickup and door open"
      64
  , RLEnvironment
      "gridworld-deterministic"
      GridWorld
      16
      4
      (DiscreteActions 4)
      1.0
      "step cost with terminal goal reward"
      "goal reached or horizon exhausted"
      100
  ]

renderEnvironmentCatalog :: Text
renderEnvironmentCatalog =
  Text.unlines $
    [ "| Environment | Kind | Actions | Horizon |"
    , "|-------------|------|---------|---------|"
    ]
      <> fmap renderRow canonicalEnvironments
 where
  renderRow environment =
    "| `"
      <> environmentName environment
      <> "` | "
      <> Text.pack (show (environmentKind environment))
      <> " | "
      <> renderActionSpace (environmentActionSpace environment)
      <> " | "
      <> Text.pack (show (environmentHorizon environment))
      <> " |"

  renderActionSpace (DiscreteActions n) = "Discrete(" <> Text.pack (show n) <> ")"
  renderActionSpace (ContinuousActions dims low high) =
    "Box("
      <> Text.pack (show dims)
      <> ", "
      <> Text.pack (show low)
      <> ", "
      <> Text.pack (show high)
      <> ")"

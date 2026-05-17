module JitML.RL.VecEnv
  ( VecEnv (..)
  , VecEnvFrame (..)
  , mkVecEnv
  , vecEnvStep
  , vecEnvTrajectory
  )
where

import JitML.RL.Environments (EnvStep, RLEnvironment, deterministicStep)

data VecEnv = VecEnv
  { vecEnvBase :: RLEnvironment
  , vecEnvCount :: Int
  , vecEnvSeed :: Int
  }
  deriving stock (Eq, Show)

data VecEnvFrame = VecEnvFrame
  { vecFrameSeed :: Int
  , vecFrameStep :: Int
  , vecFrameSteps :: [EnvStep]
  }
  deriving stock (Eq, Show)

mkVecEnv :: RLEnvironment -> Int -> Int -> VecEnv
mkVecEnv env count seed =
  VecEnv {vecEnvBase = env, vecEnvCount = count, vecEnvSeed = seed}

vecEnvStep :: VecEnv -> Int -> Int -> VecEnvFrame
vecEnvStep ve step action =
  VecEnvFrame
    { vecFrameSeed = vecEnvSeed ve
    , vecFrameStep = step
    , vecFrameSteps =
        [ deterministicStep
            (vecEnvBase ve)
            (vecEnvSeed ve + replicaId)
            (action + replicaId * 7)
        | replicaId <- [0 .. vecEnvCount ve - 1]
        ]
    }

vecEnvTrajectory :: VecEnv -> Int -> [VecEnvFrame]
vecEnvTrajectory ve horizon =
  [ vecEnvStep ve step (step `mod` (vecEnvCount ve + 1))
  | step <- [0 .. horizon - 1]
  ]

{-# LANGUAGE OverloadedStrings #-}

-- | Potential-based reward shaping (Ng, Harada & Russell, 1999) for the
-- sparse-reward control environments whose gradient-based learners never
-- observe the goal under undirected exploration.
--
-- The shaping increment @F(s, s') = gamma * Phi(s') - Phi(s)@ is added to the
-- reward stored in the training rollout/replay only. Every evaluation path
-- (@evaluate*@) reads the raw environment reward, so the reported convergence
-- metric is always the true, unshaped return. Because @F@ is a potential
-- difference it telescopes over any trajectory to @gamma^T*Phi(s_T) - Phi(s_0)@,
-- so it cannot be farmed and it preserves the optimal policy for any @Phi@ and
-- any scale — the shaping only densifies the learning signal.
--
-- 'shapingPotential' returns @0@ for every environment without a defined
-- potential, so shaping is a strict no-op for cartpole, lunar-lander,
-- gridworld, pendulum, and the goal-conditioned envs. @key-door-grid@ carries
-- a phase potential (agent -> key -> door -> goal) because the sparse terminal
-- reward otherwise gives recurrent on-policy learners little signal before
-- they discover the full unlock sequence. Other environments remain no-ops
-- unless listed below.
module JitML.RL.RewardShaping
  ( shapingPotential
  , shapingBonus
  )
where

import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

-- | Shaping potential @Phi(s)@ as a function of the environment name and the
-- observation vector (the same vector the policy/value network consumes).
shapingPotential :: Text -> Vector Double -> Double
shapingPotential env obs =
  case env of
    "mountain-car"
      | VU.length obs >= 2 ->
          let x = obs VU.! 0
              v = obs VU.! 1
              -- The mountain-car observation rescales velocity by
              -- @mountainCarVelocityObsScale@ (15) in "JitML.RL.Simulator", so
              -- the velocity seen here is bounded by @0.07 * 15 = 1.05@.
              vMax = 1.05
              -- Mechanical energy of the car: potential energy tracks the hill
              -- height @sin(3x)@ (the same @cos(3x)@ gravity term the simulator
              -- integrates), kinetic energy tracks @v^2@. Each is normalised to
              -- ~[0,1]; kinetic is weighted higher because escaping the valley
              -- is a matter of building speed, not standing high.
              height = (sin (3.0 * x) + 1.0) / 2.0
              kinetic = (v / vMax) * (v / vMax)
           in mountainCarShapeScale * (height + 2.0 * kinetic)
    "acrobot"
      | VU.length obs >= 4 ->
          let c1 = obs VU.! 0
              s1 = obs VU.! 1
              c2 = obs VU.! 2
              s2 = obs VU.! 3
              -- Tip height above the pivot is @-cos(theta1) - cos(theta1+theta2)@;
              -- the goal is tip height > 1. Reconstructed from the (cos, sin)
              -- observation pairs.
              cos12 = c1 * c2 - s1 * s2
              tipHeight = negate c1 - cos12
           in acrobotShapeScale * tipHeight
    "key-door-grid"
      | VU.length obs >= keyDoorGridObservationSize ->
          keyDoorGridShapeScale * keyDoorGridPotential obs
    _ -> 0.0

-- | Scale of the mountain-car potential. Chosen so a single step's shaping
-- @F ~ O(1)@ is comparable to the @-1@ per-step reward, giving a dense gradient
-- toward higher-energy states without changing the optimum (potential-based).
mountainCarShapeScale :: Double
mountainCarShapeScale = 30.0

-- | Scale of the acrobot potential (tip height in [-2, 2]).
acrobotShapeScale :: Double
acrobotShapeScale = 3.0

-- | KeyDoorGrid-v0 observation layout from "JitML.RL.Simulator": a 5x5 grid
-- with channels [wall, key, door, goal, agent], followed by has-key and
-- door-open flags.
keyDoorGridObservationSize :: Int
keyDoorGridObservationSize = keyDoorGridWidth * keyDoorGridHeight * keyDoorGridChannels + 2

keyDoorGridWidth :: Int
keyDoorGridWidth = 5

keyDoorGridHeight :: Int
keyDoorGridHeight = 5

keyDoorGridChannels :: Int
keyDoorGridChannels = 5

keyDoorGridHasKeyIndex :: Int
keyDoorGridHasKeyIndex = keyDoorGridWidth * keyDoorGridHeight * keyDoorGridChannels

keyDoorGridDoorOpenIndex :: Int
keyDoorGridDoorOpenIndex = keyDoorGridHasKeyIndex + 1

keyDoorGridShapeScale :: Double
keyDoorGridShapeScale = 1.5

keyDoorGridPotential :: Vector Double -> Double
keyDoorGridPotential obs =
  case findCell keyDoorGridAgentChannel obs of
    Nothing -> 0.0
    Just agent
      | not hasKey ->
          maybe 0.0 (progress agent) (findCell keyDoorGridKeyChannel obs)
      | not doorOpen ->
          maybe 1.0 ((1.0 +) . progress agent) (findCell keyDoorGridDoorChannel obs)
      | otherwise ->
          maybe 2.0 ((2.0 +) . progress agent) (findCell keyDoorGridGoalChannel obs)
 where
  hasKey = flagAt keyDoorGridHasKeyIndex obs
  doorOpen = flagAt keyDoorGridDoorOpenIndex obs

keyDoorGridKeyChannel :: Int
keyDoorGridKeyChannel = 1

keyDoorGridDoorChannel :: Int
keyDoorGridDoorChannel = 2

keyDoorGridGoalChannel :: Int
keyDoorGridGoalChannel = 3

keyDoorGridAgentChannel :: Int
keyDoorGridAgentChannel = 4

type GridCell = (Int, Int)

findCell :: Int -> Vector Double -> Maybe GridCell
findCell channel obs =
  listToMaybe
    [ (row, col)
    | row <- [0 .. keyDoorGridHeight - 1]
    , col <- [0 .. keyDoorGridWidth - 1]
    , flagAt (gridOffset row col channel) obs
    ]

gridOffset :: Int -> Int -> Int -> Int
gridOffset row col channel =
  (row * keyDoorGridWidth + col) * keyDoorGridChannels + channel

flagAt :: Int -> Vector Double -> Bool
flagAt index obs =
  index >= 0 && index < VU.length obs && obs VU.! index >= 0.5

progress :: GridCell -> GridCell -> Double
progress from to =
  1.0 - fromIntegral (manhattan from to) / fromIntegral keyDoorGridMaxDistance

manhattan :: GridCell -> GridCell -> Int
manhattan (r1, c1) (r2, c2) =
  abs (r1 - r2) + abs (c1 - c2)

keyDoorGridMaxDistance :: Int
keyDoorGridMaxDistance =
  (keyDoorGridHeight - 1) + (keyDoorGridWidth - 1)

-- | Potential-based shaping increment @F(s, s') = gamma * Phi(s') - Phi(s)@ to
-- add to the raw environment reward when storing a training transition.
shapingBonus :: Text -> Double -> Vector Double -> Vector Double -> Double
shapingBonus env gamma obs nextObs =
  gamma * shapingPotential env nextObs - shapingPotential env obs

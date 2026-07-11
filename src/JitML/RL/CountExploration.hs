{-# LANGUAGE OverloadedStrings #-}

-- | Count-based intrinsic exploration (MBIE-EB style) for the on-policy
-- learners on sparse-reward environments.
--
-- Potential-based reward shaping ('JitML.RL.RewardShaping') provably gives an
-- on-policy advantage learner /zero/ benefit once its value baseline converges
-- (the shaping telescopes and @delta_shaped == delta_true@), so it cannot break
-- the mountain-car exploration wall: the goal is never reached under undirected
-- exploration, so there is no learning signal at all. A count-based novelty
-- bonus is a /direct/ reward for reaching an under-visited state — not a
-- potential difference — so it is not cancelled by the baseline and it actively
-- drives the policy to cover the state space until the goal is discovered. As
-- cells fill, counts grow and the bonus fades as @1/sqrt@, letting the true
-- reward dominate.
--
-- The bonus is added to the training reward only; the reported episode return
-- and every evaluation path read the raw environment reward, so the convergence
-- metric is unaffected.
module JitML.RL.CountExploration
  ( CountTable
  , newCountTable
  , countExplorationBonus
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

-- | Per-training-run state-visitation table. Created fresh per training call and
-- mutated in place across that call's rollouts, so counts accumulate over the
-- run but never leak between product rows. Deterministic given the seed (the
-- visitation sequence is a pure function of the rollouts).
newtype CountTable = CountTable (IORef (Map (Int, Int) Int))

newCountTable :: IO CountTable
newCountTable = CountTable <$> newIORef Map.empty

-- | Novelty bonus @beta / sqrt(count + 1)@ for the observation's grid cell, and
-- increment that cell's count. @beta@ is supplied by the caller because the
-- optimal exploration intensity is per-algorithm (a clipped conservative learner
-- needs a stronger push than a KL-constrained one). Returns @0@ (and touches
-- nothing) when @beta <= 0@ or the environment has no defined binning.
countExplorationBonus :: CountTable -> Double -> Text -> Vector Double -> IO Double
countExplorationBonus (CountTable ref) beta env obs
  | beta <= 0.0 = pure 0.0
  | otherwise =
      case binFor env obs of
        Nothing -> pure 0.0
        Just cell -> do
          counts <- readIORef ref
          let n = Map.findWithDefault 0 cell counts
          writeIORef ref $! Map.insert cell (n + 1) counts
          pure (beta / sqrt (fromIntegral (n + 1)))

-- | Discrete grid cell for an observation, per environment. Mountain-car:
-- position in @[-1.2, 0.6]@ and the observation-scaled velocity in ~@[-1.05,
-- 1.05]@ (see 'JitML.RL.Simulator.mountainCarVelocityObsScale') into a 40x20
-- grid — fine enough to distinguish momentum-building states, coarse enough that
-- counts accumulate.
binFor :: Text -> Vector Double -> Maybe (Int, Int)
binFor env obs =
  case env of
    "mountain-car"
      | VU.length obs >= 2 ->
          let x = obs VU.! 0
              v = obs VU.! 1
              xBin = clampBin 39 (floor ((x + 1.2) / 1.8 * 40.0))
              vBin = clampBin 19 (floor ((v + 1.05) / 2.1 * 20.0))
           in Just (xBin, vBin)
    -- Pendulum observation is @[cos theta, sin theta, theta_dot]@; bin the
    -- reconstructed angle in @[-pi, pi]@ and angular velocity in ~@[-8, 8]@ so
    -- novelty drives the swing-up through the rarely-visited upright/high-speed
    -- cells the fixed Gaussian exploration seldom reaches on its own.
    "pendulum"
      | VU.length obs >= 3 ->
          let theta = atan2 (obs VU.! 1) (obs VU.! 0)
              thetaDot = obs VU.! 2
              tBin = clampBin 29 (floor ((theta + pi) / (2.0 * pi) * 30.0))
              wBin = clampBin 19 (floor ((thetaDot + 8.0) / 16.0 * 20.0))
           in Just (tBin, wBin)
    "key-door-grid"
      | VU.length obs >= keyDoorGridObservationSize -> do
          (row, col) <- keyDoorGridAgentCell obs
          let hasKey = if flagAt keyDoorGridHasKeyIndex obs then 1 else 0
              doorOpen = if flagAt keyDoorGridDoorOpenIndex obs then 1 else 0
              phase = hasKey + 2 * doorOpen
          Just (row * keyDoorGridWidth + col, phase)
    _ -> Nothing

clampBin :: Int -> Int -> Int
clampBin hi = max 0 . min hi

keyDoorGridWidth :: Int
keyDoorGridWidth = 5

keyDoorGridHeight :: Int
keyDoorGridHeight = 5

keyDoorGridChannels :: Int
keyDoorGridChannels = 5

keyDoorGridObservationSize :: Int
keyDoorGridObservationSize = keyDoorGridWidth * keyDoorGridHeight * keyDoorGridChannels + 2

keyDoorGridHasKeyIndex :: Int
keyDoorGridHasKeyIndex = keyDoorGridWidth * keyDoorGridHeight * keyDoorGridChannels

keyDoorGridDoorOpenIndex :: Int
keyDoorGridDoorOpenIndex = keyDoorGridHasKeyIndex + 1

keyDoorGridAgentChannel :: Int
keyDoorGridAgentChannel = 4

keyDoorGridAgentCell :: Vector Double -> Maybe (Int, Int)
keyDoorGridAgentCell obs =
  go 0 0
 where
  go row col
    | row >= keyDoorGridHeight = Nothing
    | col >= keyDoorGridWidth = go (row + 1) 0
    | flagAt (gridOffset row col keyDoorGridAgentChannel) obs = Just (row, col)
    | otherwise = go row (col + 1)

gridOffset :: Int -> Int -> Int -> Int
gridOffset row col channel =
  (row * keyDoorGridWidth + col) * keyDoorGridChannels + channel

flagAt :: Int -> Vector Double -> Bool
flagAt index obs =
  index >= 0 && index < VU.length obs && obs VU.! index >= 0.5

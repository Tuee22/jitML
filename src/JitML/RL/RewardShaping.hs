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
-- key-door-grid, gridworld, pendulum, and the goal-conditioned envs. Only
-- @mountain-car@ and @acrobot@ — where the goal is otherwise never reached, so
-- the return sits pinned on its @-200@/@-500@ floor — carry a potential. This
-- scopes the blast radius of shaping to exactly the rows it is meant to rescue.
module JitML.RL.RewardShaping
  ( shapingPotential
  , shapingBonus
  )
where

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
    _ -> 0.0

-- | Scale of the mountain-car potential. Chosen so a single step's shaping
-- @F ~ O(1)@ is comparable to the @-1@ per-step reward, giving a dense gradient
-- toward higher-energy states without changing the optimum (potential-based).
mountainCarShapeScale :: Double
mountainCarShapeScale = 30.0

-- | Scale of the acrobot potential (tip height in [-2, 2]).
acrobotShapeScale :: Double
acrobotShapeScale = 3.0

-- | Potential-based shaping increment @F(s, s') = gamma * Phi(s') - Phi(s)@ to
-- add to the raw environment reward when storing a training transition.
shapingBonus :: Text -> Double -> Vector Double -> Vector Double -> Double
shapingBonus env gamma obs nextObs =
  gamma * shapingPotential env nextObs - shapingPotential env obs

-- | Sprint 13.8 — real TD3 loss math (Fujimoto et al. 2018,
-- "Addressing Function Approximation Error in Actor-Critic Methods").
--
-- TD3 extends DDPG with three modifications:
--
--   1. Clipped double Q-learning — two critics @Q1@, @Q2@ are trained
--      against
--      @y_t = r_t + gamma * min(Q1_target, Q2_target)@
--      where both targets are evaluated at the target-policy action.
--   2. Delayed policy updates — the actor and target networks update
--      every @policyDelay@ critic steps (orchestration, not in the
--      loss shape).
--   3. Target-policy smoothing — Gaussian noise is added to the
--      target action and clipped to a fixed range:
--      @a' = clip(mu_target(s') + clip(epsilon, -c, c), a_low, a_high)@.
--      The noise is the caller's responsibility; this module exposes
--      'td3SmoothTargetActions' as a deterministic helper.
module JitML.RL.Algorithms.Td3Loss
  ( td3ClippedDoubleTarget
  , td3CriticLoss
  , td3SmoothTargetActions
  )
where

import JitML.RL.Algorithms.DqnLoss (dqnBellmanTarget, dqnTdLoss)

-- | Clipped-double-Q Bellman target: take the minimum of the two
-- target critics' projections per step.
td3ClippedDoubleTarget
  :: Double
  -- ^ discount factor gamma
  -> [Double]
  -- ^ rewards
  -> [Bool]
  -- ^ terminal flags
  -> [Double]
  -- ^ @Q1_target(s', a')@
  -> [Double]
  -- ^ @Q2_target(s', a')@
  -> [Double]
td3ClippedDoubleTarget gamma rewards terminals q1Targets q2Targets =
  let minTargets = zipWith min q1Targets q2Targets
   in zipWith3 (dqnBellmanTarget gamma) rewards terminals minTargets

td3CriticLoss :: [Double] -> [Double] -> Double
td3CriticLoss = dqnTdLoss

-- | Target-policy smoothing: add clipped per-step noise to the
-- target-policy actions, then clip the result into the action range.
-- Deterministic in the sense that bit-identical noise + actions
-- produce bit-identical output (the noise comes from a typed RNG the
-- caller controls).
td3SmoothTargetActions
  :: Double
  -- ^ noise clip range @c@
  -> Double
  -- ^ action low bound
  -> Double
  -- ^ action high bound
  -> [Double]
  -- ^ target actions @mu_target(s')@
  -> [Double]
  -- ^ Gaussian noise samples @epsilon@
  -> [Double]
td3SmoothTargetActions noiseClip actionLow actionHigh targetActions noise =
  let clip lo hi x = max lo (min hi x)
   in zipWith
        (\mu eps -> clip actionLow actionHigh (mu + clip (-noiseClip) noiseClip eps))
        targetActions
        noise

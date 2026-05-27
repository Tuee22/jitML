-- | Sprint 13.8 — real DDPG loss math (Lillicrap et al. 2016,
-- "Continuous Control with Deep Reinforcement Learning").
--
-- DDPG is an off-policy actor-critic algorithm for continuous action
-- spaces. Two losses are minimised jointly per gradient step:
--
--   * Critic loss — mean-squared TD error against the deterministic-
--     policy Bellman target
--     @y_t = r_t + gamma * Q_target(s_{t+1}, mu_target(s_{t+1}))@.
--     Reuses 'dqnTdLoss' via 'ddpgCriticLoss'.
--
--   * Actor loss — the deterministic-policy gradient
--     @L^pi = -mean(Q(s_t, mu(s_t)))@ (Silver et al. 2014).
module JitML.RL.Algorithms.DdpgLoss
  ( ddpgActorLoss
  , ddpgCriticLoss
  , ddpgCriticTarget
  )
where

import JitML.RL.Algorithms.DqnLoss (dqnBellmanTarget, dqnTdLoss)

-- | The deterministic-policy Bellman target. @muTargetActions@ are the
-- target policy network's outputs at @s_{t+1}@; the caller has already
-- projected them through @Q_target@ to get @targetQValues@.
ddpgCriticTarget
  :: Double
  -- ^ discount factor gamma
  -> [Double]
  -- ^ rewards @r_t@
  -> [Bool]
  -- ^ terminal flags
  -> [Double]
  -- ^ @Q_target(s_{t+1}, mu_target(s_{t+1}))@ per step
  -> [Double]
ddpgCriticTarget gamma =
  zipWith3 (dqnBellmanTarget gamma)

ddpgCriticLoss :: [Double] -> [Double] -> Double
ddpgCriticLoss = dqnTdLoss

-- | Deterministic-policy actor loss. Caller supplies the online
-- critic's evaluation of the online actor's outputs:
-- @actorQ_t = Q(s_t, mu(s_t))@.
ddpgActorLoss :: [Double] -> Double
ddpgActorLoss actorQValues
  | null actorQValues = 0.0
  | otherwise =
      let n = fromIntegral (length actorQValues) :: Double
       in negate (sum actorQValues / n)

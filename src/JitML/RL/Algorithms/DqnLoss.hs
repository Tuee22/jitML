-- | Sprint 13.8 — real DQN loss math.
--
-- DQN ("Playing Atari with Deep Reinforcement Learning", Mnih et al.
-- 2013) updates its Q-network against the Bellman target:
--
-- @y_t = r_t + gamma * max_{a'} Q_target(s_{t+1}, a')@
--
-- and the per-step loss is the mean-squared TD error:
--
-- @L^DQN = mean( (Q(s_t, a_t) - y_t)^2 )@
--
-- Inputs are already projected by the live network forward pass.
-- 'dqnDoubleBellmanTarget' implements the Double-DQN variant where
-- action selection uses the online network and value evaluation uses
-- the target network, removing the Q-value overestimation bias.
module JitML.RL.Algorithms.DqnLoss
  ( dqnBellmanTarget
  , dqnDoubleBellmanTarget
  , dqnHuberLoss
  , dqnTdLoss
  , dqnTdResidual
  )
where

-- | Standard Bellman target: @r + gamma * max_a Q_target(s', a)@ for
-- non-terminal steps, just @r@ for terminal steps.
dqnBellmanTarget
  :: Double
  -- ^ discount factor gamma
  -> Double
  -- ^ reward @r_t@
  -> Bool
  -- ^ terminal flag (True → no bootstrap)
  -> Double
  -- ^ @max_a Q_target(s_{t+1}, a)@
  -> Double
dqnBellmanTarget _ reward True _ = reward
dqnBellmanTarget gamma reward False maxNextQ =
  reward + gamma * maxNextQ

-- | Double-DQN target — action is chosen by the online network and
-- evaluated by the target network. Removes the maximisation bias of
-- vanilla DQN by decoupling the two networks for the bootstrap.
--
-- The caller projects the chosen action via online network @argmax@
-- and supplies the target network's value at that action.
dqnDoubleBellmanTarget
  :: Double
  -- ^ discount factor gamma
  -> Double
  -- ^ reward @r_t@
  -> Bool
  -- ^ terminal flag
  -> Double
  -- ^ @Q_target(s_{t+1}, argmax_a Q_online(s_{t+1}, a))@
  -> Double
dqnDoubleBellmanTarget = dqnBellmanTarget

-- | Per-step temporal-difference residual @Q(s_t, a_t) - y_t@.
dqnTdResidual :: Double -> Double -> Double
dqnTdResidual qValue target = qValue - target

-- | Mean-squared TD error: the canonical DQN loss.
dqnTdLoss :: [Double] -> [Double] -> Double
dqnTdLoss qValues targets
  | null targets = 0.0
  | otherwise =
      let n = fromIntegral (length targets) :: Double
          residuals = zipWith dqnTdResidual qValues targets
       in sum (fmap (\r -> r * r) residuals) / n

-- | Huber loss with the canonical @kappa = 1.0@ from the DQN reference
-- implementation. Combines L2 behaviour near the origin with L1
-- behaviour far from it, reducing the gradient magnitude on outlier TD
-- residuals.
dqnHuberLoss :: Double -> [Double] -> [Double] -> Double
dqnHuberLoss kappa qValues targets
  | null targets = 0.0
  | otherwise =
      let n = fromIntegral (length targets) :: Double
          residuals = zipWith dqnTdResidual qValues targets
          term r
            | abs r <= kappa = 0.5 * r * r
            | otherwise = kappa * (abs r - 0.5 * kappa)
       in sum (fmap term residuals) / n

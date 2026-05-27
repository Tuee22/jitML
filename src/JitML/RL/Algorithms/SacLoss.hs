-- | Sprint 13.8 — real SAC loss math (Haarnoja et al. 2018,
-- "Soft Actor-Critic: Off-Policy Maximum Entropy Deep RL").
--
-- SAC trains two critics @Q1@, @Q2@ and a stochastic policy @pi@ with
-- entropy regularisation. The three losses minimised per gradient
-- step are:
--
--   * Critic loss — MSE against the soft Bellman target
--     @y_t = r_t + gamma * (min(Q1_target(s', a'), Q2_target(s', a'))
--                          - alpha * log_pi(a' | s'))@
--     where @a' ~ pi(. | s')@ is the policy's sampled action at
--     @s_{t+1}@.
--
--   * Actor loss — minimise the KL between the policy and the
--     Boltzmann-softmax of @Q_min@:
--     @L^pi = mean(alpha * log_pi(a | s) - Q_min(s, a))@.
--
--   * Temperature loss — automatic-entropy variant from Haarnoja et al.
--     2018b: @L^alpha = -mean(alpha * (log_pi + target_entropy))@.
module JitML.RL.Algorithms.SacLoss
  ( sacActorLoss
  , sacCriticTarget
  , sacCriticLoss
  , sacTemperatureLoss
  )
where

import JitML.RL.Algorithms.DqnLoss (dqnBellmanTarget, dqnTdLoss)

sacCriticTarget
  :: Double
  -- ^ discount factor gamma
  -> Double
  -- ^ temperature alpha
  -> [Double]
  -- ^ rewards
  -> [Bool]
  -- ^ terminal flags
  -> [Double]
  -- ^ @Q1_target(s', a')@
  -> [Double]
  -- ^ @Q2_target(s', a')@
  -> [Double]
  -- ^ @log pi(a' | s')@
  -> [Double]
sacCriticTarget gamma alpha rewards terminals q1Targets q2Targets nextLogProbs =
  let softMins =
        zipWith3
          (\q1 q2 lp -> min q1 q2 - alpha * lp)
          q1Targets
          q2Targets
          nextLogProbs
   in zipWith3 (dqnBellmanTarget gamma) rewards terminals softMins

sacCriticLoss :: [Double] -> [Double] -> Double
sacCriticLoss = dqnTdLoss

-- | Actor loss: minimise @alpha * log_pi - Q_min(s, a_sampled)@.
sacActorLoss :: Double -> [Double] -> [Double] -> Double
sacActorLoss alpha logProbs qMins
  | null logProbs = 0.0
  | otherwise =
      let n = fromIntegral (length logProbs) :: Double
          terms = zipWith (\lp q -> alpha * lp - q) logProbs qMins
       in sum terms / n

-- | Temperature loss: drive @alpha@ to satisfy the target-entropy
-- constraint. Caller supplies @log_pi@ from the current policy and the
-- desired @target_entropy@ (typically @-|A|@ for an @|A|@-dimensional
-- continuous action space).
sacTemperatureLoss :: Double -> Double -> [Double] -> Double
sacTemperatureLoss alpha targetEntropy logProbs
  | null logProbs = 0.0
  | otherwise =
      let n = fromIntegral (length logProbs) :: Double
          terms = fmap (\lp -> negate alpha * (lp + targetEntropy)) logProbs
       in sum terms / n

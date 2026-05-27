-- | Sprint 13.8 — real CrossQ loss math (Bhatt et al. 2024,
-- "CrossQ: Batch Normalization in Deep Reinforcement Learning").
--
-- CrossQ replaces SAC's target networks with batch normalisation
-- statistics. The critic is updated against the soft Bellman target
-- computed from the current online network plus a normalised running
-- statistic of recent Q values; no target network is maintained.
--
-- The math here exposes the per-step CrossQ target:
--
-- @y_t = r_t + gamma * (Q_normalised(s_{t+1}, a') - alpha * log_pi(a'|s'))@
--
-- where @Q_normalised@ is the batch-normalised online Q output. The
-- normalisation statistics (running mean / variance) are the caller's
-- responsibility; this module just exposes the typed target.
module JitML.RL.Algorithms.CrossQLoss
  ( crossQNormalise
  , crossQTarget
  )
where

import JitML.RL.Algorithms.DqnLoss (dqnBellmanTarget)

-- | Batch-normalise a vector of Q values: subtract the running mean
-- and divide by sqrt(running_var + eps).
crossQNormalise
  :: Double
  -- ^ running mean
  -> Double
  -- ^ running variance
  -> Double
  -- ^ epsilon for numerical stability
  -> [Double]
  -> [Double]
crossQNormalise mean variance eps =
  fmap (\q -> (q - mean) / sqrt (variance + eps))

-- | CrossQ Bellman target — same shape as SAC's, but uses the
-- normalised online Q value instead of a target-network projection.
crossQTarget
  :: Double
  -- ^ discount factor gamma
  -> Double
  -- ^ temperature alpha
  -> [Double]
  -- ^ rewards
  -> [Bool]
  -- ^ terminal flags
  -> [Double]
  -- ^ normalised online Q values at @(s', a')@
  -> [Double]
  -- ^ @log pi(a' | s')@
  -> [Double]
crossQTarget gamma alpha rewards terminals qNormalised nextLogProbs =
  let softTerms =
        zipWith (\q lp -> q - alpha * lp) qNormalised nextLogProbs
   in zipWith3 (dqnBellmanTarget gamma) rewards terminals softTerms

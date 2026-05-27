-- | Sprint 13.8 — real TQC loss math (Kuznetsov et al. 2020,
-- "Controlling Overestimation Bias with Truncated Mixture of Continuous
-- Distributional Quantile Critics").
--
-- TQC trains @numCritics@ distributional critics (each with
-- @numQuantiles@ atoms) and truncates the top-@droppedAtoms@ highest
-- quantiles from the *pooled* multi-critic distribution before
-- computing the soft Bellman target. The truncation removes the
-- overestimation bias of vanilla SAC-style multi-Q averaging.
--
-- The loss math here exposes the truncation step plus the quantile
-- Huber loss reuse from QR-DQN.
module JitML.RL.Algorithms.TqcLoss
  ( poolAndTruncate
  , tqcTarget
  )
where

import Data.List (sort)

-- | Pool the quantile atoms from all critics and drop the
-- @droppedPerCritic * numCritics@ highest values. Returns the
-- truncated, sorted pool.
poolAndTruncate :: Int -> [[Double]] -> [Double]
poolAndTruncate droppedPerCritic critics =
  let allAtoms = concat critics
      numCritics = length critics
      dropTotal = droppedPerCritic * numCritics
      sorted = sort allAtoms
   in take (length sorted - max 0 dropTotal) sorted

-- | TQC Bellman target for a single transition. Caller supplies the
-- per-critic quantile atoms at @s_{t+1}@, the per-step reward and
-- terminal flag, and the canonical SAC entropy term
-- @alpha * log_pi(a' | s')@.
tqcTarget
  :: Double
  -- ^ discount factor gamma
  -> Int
  -- ^ atoms to drop per critic from the top tail
  -> Double
  -- ^ reward
  -> Bool
  -- ^ terminal flag
  -> [[Double]]
  -- ^ per-critic quantile atoms at @(s', a')@
  -> Double
  -- ^ @alpha * log_pi(a' | s')@
  -> [Double]
  -- ^ truncated target quantile atoms
tqcTarget _ _ reward True _ _ =
  -- Terminal step: the target distribution collapses to a point mass
  -- at the reward. We return a single-atom list so downstream
  -- quantile-Huber averaging is well-defined.
  [reward]
tqcTarget gamma droppedPerCritic reward False critics softTerm =
  let truncated = poolAndTruncate droppedPerCritic critics
      shifted = fmap (\q -> reward + gamma * (q - softTerm)) truncated
   in shifted

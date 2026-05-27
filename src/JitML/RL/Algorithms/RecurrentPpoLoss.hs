-- | Sprint 13.8 — real RecurrentPPO loss math.
--
-- RecurrentPPO is PPO with an LSTM/GRU policy. The loss math is
-- identical to PPO; what differs is the *backpropagation through time*
-- (BPTT) window — the trainer cuts the trajectory into BPTT-windowed
-- sub-sequences and computes the surrogate per window. This module
-- exposes the windowing helper plus the per-window loss alias.
module JitML.RL.Algorithms.RecurrentPpoLoss
  ( bpttWindows
  , recurrentSurrogateLoss
  )
where

import JitML.RL.Algorithms.PpoLoss (clippedSurrogateLoss)

-- | Split a trajectory into BPTT windows of length @windowLen@. The
-- last window may be shorter than @windowLen@. The trainer detaches
-- the LSTM hidden state at the start of each window.
bpttWindows :: Int -> [a] -> [[a]]
bpttWindows windowLen xs
  | windowLen <= 0 = [xs]
  | null xs = []
  | otherwise =
      let (window, rest) = splitAt windowLen xs
       in window : bpttWindows windowLen rest

-- | RecurrentPPO surrogate per window: same shape as PPO's
-- 'clippedSurrogateLoss'. The trainer averages per-window losses
-- across the trajectory before applying the gradient step.
recurrentSurrogateLoss
  :: Double -> [Double] -> [Double] -> [Double] -> Double
recurrentSurrogateLoss = clippedSurrogateLoss

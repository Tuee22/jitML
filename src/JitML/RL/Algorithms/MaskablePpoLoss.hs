-- | Sprint 13.8 — real MaskablePPO loss math.
--
-- MaskablePPO is PPO with action masking: a per-step mask vector
-- @mask_t :: [Bool]@ identifies which actions are legal at the current
-- state. The policy distribution is renormalised over only the legal
-- actions, and the surrogate is computed against the masked-renormalised
-- log probabilities. The clip-and-value losses are unchanged from PPO.
module JitML.RL.Algorithms.MaskablePpoLoss
  ( applyActionMask
  , maskableSurrogateLoss
  )
where

import JitML.RL.Algorithms.PpoLoss (clippedSurrogateLoss)

-- | Re-normalise a policy distribution after action masking: illegal
-- actions are set to zero; the legal-action probabilities are
-- rescaled to sum to 1. Returns the resulting probabilities in the
-- original action order.
applyActionMask :: [Bool] -> [Double] -> [Double]
applyActionMask mask probs
  | length mask /= length probs = probs
  | otherwise =
      let masked = zipWith (\m p -> if m then p else 0.0) mask probs
          total = sum masked
       in if total <= 0
            then masked
            else fmap (/ total) masked

-- | MaskablePPO surrogate: same shape as PPO's
-- 'clippedSurrogateLoss', but the caller has already projected the
-- old / new log probabilities through 'applyActionMask' before
-- computing them.
maskableSurrogateLoss
  :: Double -> [Double] -> [Double] -> [Double] -> Double
maskableSurrogateLoss = clippedSurrogateLoss

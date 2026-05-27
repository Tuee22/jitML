-- | Sprint 13.8 — real TRPO loss math (Schulman et al. 2015,
-- "Trust Region Policy Optimization").
--
-- TRPO maximises the unclipped surrogate
--
-- @L^TRPO = mean( exp(log_pi - log_pi_old) * A )@
--
-- subject to a hard KL constraint
--
-- @D_KL(pi_old || pi) <= delta@
--
-- typically enforced via a natural-gradient + line-search step. The
-- loss math here is the unclipped surrogate plus the approximate KL
-- guard; the line-search orchestration lives at the trainer level.
module JitML.RL.Algorithms.TrpoLoss
  ( trpoSurrogate
  , trpoKlConstraintSatisfied
  )
where

import JitML.RL.Algorithms.PpoLoss (approxKlDivergence)

-- | Unclipped TRPO surrogate. Returns the negated mean so a gradient-
-- descent optimiser minimises the result.
trpoSurrogate :: [Double] -> [Double] -> [Double] -> Double
trpoSurrogate oldLogProbs newLogProbs advantages
  | null advantages = 0.0
  | otherwise =
      let n = fromIntegral (length advantages) :: Double
          ratios = zipWith (\nlp olp -> exp (nlp - olp)) newLogProbs oldLogProbs
          terms = zipWith (*) ratios advantages
       in negate (sum terms / n)

-- | The hard KL trust-region check the line search applies after each
-- candidate step: accept the step iff @approxKL(pi_old, pi) <= delta@.
trpoKlConstraintSatisfied :: Double -> [Double] -> [Double] -> Bool
trpoKlConstraintSatisfied delta oldLogProbs newLogProbs =
  approxKlDivergence oldLogProbs newLogProbs <= delta

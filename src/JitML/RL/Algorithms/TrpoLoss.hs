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
-- loss math here is the unclipped surrogate plus the exact categorical KL
-- guard; the line-search orchestration lives at the trainer level.
module JitML.RL.Algorithms.TrpoLoss
  ( categoricalKlDivergence
  , trpoSurrogate
  , trpoKlConstraintSatisfied
  )
where

-- | Unclipped TRPO surrogate. Returns the negated mean so a gradient-
-- descent optimiser minimises the result.
trpoSurrogate :: [Double] -> [Double] -> [Double] -> Double
trpoSurrogate oldLogProbs newLogProbs advantages
  | null advantages = positiveInfinity
  | length oldLogProbs /= sampleCount = positiveInfinity
  | length newLogProbs /= sampleCount = positiveInfinity
  | not (all finite (oldLogProbs <> newLogProbs <> advantages)) = positiveInfinity
  | not (all finite ratios) = positiveInfinity
  | not (all finite terms) = positiveInfinity
  | otherwise =
      negate (sum terms / fromIntegral sampleCount)
 where
  sampleCount = length advantages
  ratios = zipWith (\nlp olp -> exp (nlp - olp)) newLogProbs oldLogProbs
  terms = zipWith (*) ratios advantages
  finite value = not (isNaN value) && not (isInfinite value)
  positiveInfinity = 1.0 / 0.0

-- | Mean exact categorical KL divergence over a rollout batch.
--
-- TRPO's trust region is a constraint over the complete action
-- distributions, not the sampled actions alone.  A sampled
-- @mean(oldLogProb - newLogProb)@ estimate can be negative and therefore admit
-- an arbitrarily distant candidate.  Shape mismatches and candidates that put
-- zero mass under an action with positive old-policy mass fail closed as
-- positive infinity.
categoricalKlDivergence :: [[Double]] -> [[Double]] -> Double
categoricalKlDivergence oldPolicies newPolicies
  | null oldPolicies = positiveInfinity
  | length oldPolicies /= length newPolicies = 1.0 / 0.0
  | otherwise =
      sum (zipWith rowKl oldPolicies newPolicies)
        / fromIntegral (length oldPolicies)
 where
  rowKl oldPolicy newPolicy
    | not (validPolicy oldPolicy) = positiveInfinity
    | not (validPolicy newPolicy) = positiveInfinity
    | length oldPolicy /= length newPolicy = 1.0 / 0.0
    | otherwise = max 0.0 (sum (zipWith term oldPolicy newPolicy))
  term oldProbability newProbability
    | oldProbability <= 0.0 = 0.0
    | newProbability <= 0.0 = positiveInfinity
    | otherwise = oldProbability * (log oldProbability - log newProbability)
  validPolicy policy =
    not (null policy)
      && all finiteNonnegative policy
      && abs (sum policy - 1.0) <= 1.0e-8
  finiteNonnegative probability =
    probability >= 0.0
      && not (isNaN probability)
      && not (isInfinite probability)
  positiveInfinity = 1.0 / 0.0

-- | The hard KL trust-region check the line search applies after each
-- candidate step: accept the step iff the exact mean categorical
-- @KL(pi_old || pi_candidate)@ is finite and no greater than @delta@.
trpoKlConstraintSatisfied :: Double -> [[Double]] -> [[Double]] -> Bool
trpoKlConstraintSatisfied delta oldPolicies newPolicies =
  let divergence = categoricalKlDivergence oldPolicies newPolicies
   in not (null oldPolicies)
        && delta >= 0.0
        && not (isNaN delta)
        && not (isInfinite delta)
        && not (isNaN divergence)
        && not (isInfinite divergence)
        && divergence <= delta

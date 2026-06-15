-- | Sprint 13.8 — real PPO loss math.
--
-- Provides the clipped surrogate objective, value-function loss,
-- generalised advantage estimation (GAE), and approximate KL divergence
-- that the canonical PPO algorithm uses. Pure functions so the
-- determinism contract holds: two runs with the same inputs produce
-- bit-equal outputs.
--
-- The broader catalog now has dedicated trainer/loss paths, and canonical
-- validation feeds this module with trained-network inputs from real simulator
-- rollouts rather than reward-derived projection fixtures.
--
-- Inputs are aligned by time index — the @t@-th entry of @rewards@,
-- @values@, @nextValues@, @oldLogProbs@, @newLogProbs@ describes the
-- same trajectory step.
module JitML.RL.Algorithms.PpoLoss
  ( approxKlDivergence
  , clippedSurrogateLoss
  , gaeAdvantages
  , normaliseAdvantages
  , ppoTotalLoss
  , valueFunctionLoss
  )
where

-- | The clipped surrogate objective from Schulman et al. (2017,
-- "Proximal Policy Optimization Algorithms", Eq. 7). For each
-- trajectory step:
--
-- @ratio_t = exp(new_log_prob_t - old_log_prob_t)@
-- @clipped_t = clamp(ratio_t, 1 - eps, 1 + eps)@
-- @term_t = min(ratio_t * A_t, clipped_t * A_t)@
--
-- Returns the negated mean over the batch so a gradient *descent*
-- optimiser minimises the result (the literature presents the objective
-- as a *maximisation* target).
clippedSurrogateLoss
  :: Double
  -- ^ epsilon (PPO clip range; the canonical value is @0.2@)
  -> [Double]
  -- ^ old log probabilities @log π_old(a_t | s_t)@
  -> [Double]
  -- ^ new log probabilities @log π(a_t | s_t)@
  -> [Double]
  -- ^ advantages @A_t@ (typically GAE)
  -> Double
clippedSurrogateLoss eps oldLogProbs newLogProbs advantages
  | null advantages = 0.0
  | otherwise =
      let ratios =
            zipWith
              (\n o -> exp (n - o))
              newLogProbs
              oldLogProbs
          clipped r = max (1 - eps) (min (1 + eps) r)
          term r a = min (r * a) (clipped r * a)
          terms = zipWith term ratios advantages
       in negate (sum terms / fromIntegral (length advantages))

-- | Mean-squared value-function loss (Schulman et al. Eq. 9):
--
-- @L^VF_t = (V_θ(s_t) - V_target_t)^2@
--
-- Returns the mean over the batch.
valueFunctionLoss :: [Double] -> [Double] -> Double
valueFunctionLoss predicted targets
  | null targets = 0.0
  | otherwise =
      let sq (p, t) = (p - t) * (p - t)
       in sum (fmap sq (zip predicted targets)) / fromIntegral (length targets)

-- | Generalised Advantage Estimation (Schulman et al. 2016, "High-
-- Dimensional Continuous Control Using Generalized Advantage Estimation",
-- Eq. 11). For each trajectory step:
--
-- @delta_t = r_t + gamma * V(s_{t+1}) - V(s_t)@
-- @A_t = delta_t + gamma * lambda * A_{t+1}@
--
-- The recursion walks the trajectory backwards; the terminal
-- advantage @A_{T+1}@ is zero.
gaeAdvantages
  :: Double
  -- ^ discount factor gamma
  -> Double
  -- ^ GAE smoothing lambda
  -> [Double]
  -- ^ rewards @r_t@
  -> [Double]
  -- ^ value estimates @V(s_t)@
  -> [Double]
  -- ^ next-state value estimates @V(s_{t+1})@; the terminal step's
  -- next-value is conventionally zero
  -> [Double]
gaeAdvantages gamma lam rewards values nextValues =
  let deltas =
        zipWith3
          (\r nv v -> r + gamma * nv - v)
          rewards
          nextValues
          values
      reversed = walkBackwards (reverse deltas) 0.0 []
   in reversed
 where
  walkBackwards [] _ acc = acc
  walkBackwards (d : ds) nextGae acc =
    let gae = d + gamma * lam * nextGae
     in walkBackwards ds gae (gae : acc)

-- | Standardise advantages to zero mean / unit variance. PPO reference
-- implementations apply this per minibatch before computing the
-- surrogate loss; without it, the clip range interacts badly with
-- advantages whose absolute scale drifts across batches.
normaliseAdvantages :: [Double] -> [Double]
normaliseAdvantages [] = []
normaliseAdvantages xs =
  let n = fromIntegral (length xs) :: Double
      meanX = sum xs / n
      sqDev x = (x - meanX) * (x - meanX)
      varX = sum (fmap sqDev xs) / n
      stdX = sqrt (varX + 1.0e-8)
   in fmap (\x -> (x - meanX) / stdX) xs

-- | Approximate KL divergence between the old and new policies used by
-- the canonical PPO early-stop guard:
--
-- @KL_approx = mean(old_log_prob - new_log_prob)@
--
-- A more accurate but more expensive form is
-- @KL_approx = mean(exp(log_ratio) - 1 - log_ratio)@; the simpler form
-- matches the literature reference and is what the trainer pauses
-- updates against when @KL > kl-early-stop@.
approxKlDivergence :: [Double] -> [Double] -> Double
approxKlDivergence oldLogProbs newLogProbs
  | null oldLogProbs = 0.0
  | otherwise =
      let n = fromIntegral (length oldLogProbs) :: Double
       in sum (zipWith (-) oldLogProbs newLogProbs) / n

-- | The full PPO loss minimised per update step:
--
-- @L = -L^CLIP + c_v * L^VF - c_h * S[π]@
--
-- where @c_v@ is the value coefficient and @c_h@ is the entropy
-- coefficient. The @entropyBonus@ argument is the mean per-step entropy
-- of the current policy (positive); the term is *subtracted* to
-- encourage exploration. The returned value is what an SGD optimiser
-- consumes (the surrogate term is already negated by
-- 'clippedSurrogateLoss').
ppoTotalLoss
  :: Double
  -- ^ clip epsilon
  -> Double
  -- ^ value coefficient @c_v@
  -> Double
  -- ^ entropy coefficient @c_h@
  -> [Double]
  -- ^ old log probabilities
  -> [Double]
  -- ^ new log probabilities
  -> [Double]
  -- ^ advantages (typically normalised GAE)
  -> [Double]
  -- ^ predicted values @V_θ(s_t)@
  -> [Double]
  -- ^ value targets @R_t@
  -> Double
  -- ^ policy entropy bonus (positive mean entropy)
  -> Double
ppoTotalLoss eps valueCoef entropyCoef oldLogProbs newLogProbs advantages predicted targets entropyBonus =
  let surrogate = clippedSurrogateLoss eps oldLogProbs newLogProbs advantages
      vfLoss = valueFunctionLoss predicted targets
   in surrogate + valueCoef * vfLoss - entropyCoef * entropyBonus

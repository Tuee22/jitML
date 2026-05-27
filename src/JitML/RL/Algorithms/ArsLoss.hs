-- | Sprint 13.8 — real ARS update math (Mania et al. 2018,
-- "Simple random search provides a competitive approach to
-- reinforcement learning").
--
-- ARS is a gradient-free black-box optimiser. The "loss" surface is
-- finite-difference estimated by sampling perturbation directions
-- @delta_k@ around the current policy parameters @theta@, evaluating
-- the return @R(theta + nu*delta_k)@ and @R(theta - nu*delta_k)@ for
-- each, and updating
--
-- @theta_{t+1} = theta_t + (alpha / (b * sigma_R)) *
--                sum_k (R_plus_k - R_minus_k) * delta_k@
--
-- where @b@ is the number of top-performing perturbations kept,
-- @sigma_R@ is the standard deviation of the kept returns, @alpha@
-- is the learning rate, and @nu@ is the perturbation magnitude.
module JitML.RL.Algorithms.ArsLoss
  ( arsUpdateDirection
  , arsTopDirections
  )
where

import Data.List (sortBy)
import Data.Ord (Down (..), comparing)

-- | Pick the top-@b@ perturbation directions by max(R_plus, R_minus).
-- Returns the @(R_plus, R_minus, delta)@ triples that drive the
-- update.
arsTopDirections
  :: Int
  -- ^ top-b retention count
  -> [(Double, Double, [Double])]
  -- ^ @(R_plus, R_minus, delta)@ triples
  -> [(Double, Double, [Double])]
arsTopDirections b triples =
  let ranked = sortBy (comparing (Down . maxRet)) triples
   in take (max 0 b) ranked
 where
  maxRet (plusR, minusR, _) = max plusR minusR

-- | Aggregate the kept-direction returns into a single update vector
-- of the same dimensionality as the perturbations. Returns the
-- parameter-space step the optimiser applies; the caller is
-- responsible for the @alpha / (b * sigma_R)@ scaling.
arsUpdateDirection :: [(Double, Double, [Double])] -> [Double]
arsUpdateDirection [] = []
arsUpdateDirection triples@((_, _, firstDelta) : _) =
  foldr step (replicate (length firstDelta) 0.0) triples
 where
  step (plusR, minusR, delta) acc =
    let scale = plusR - minusR
        weighted = fmap (* scale) delta
     in zipWith (+) acc weighted

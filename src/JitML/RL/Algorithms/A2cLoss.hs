-- | Sprint 13.8 — real A2C loss math.
--
-- A2C ("Advantage Actor-Critic", Mnih et al. 2016) shares the value-
-- function loss and advantage estimation with PPO but replaces the
-- clipped surrogate with the plain policy-gradient term:
--
-- @L^PG = -mean(log π(a_t | s_t) * A_t)@
--
-- and adds an entropy bonus to encourage exploration:
--
-- @L^A2C = L^PG + c_v * L^VF - c_h * S[π]@
--
-- where @S[π]@ is the mean per-step entropy of the current policy.
-- Returns the loss value an SGD optimiser consumes (already negated
-- where necessary).
module JitML.RL.Algorithms.A2cLoss
  ( a2cPolicyGradientLoss
  , a2cTotalLoss
  )
where

import JitML.RL.Algorithms.PpoLoss (valueFunctionLoss)

-- | Vanilla policy-gradient loss term used by A2C and the on-policy
-- backbone of similar algorithms. Returns the negated mean so a
-- gradient-descent optimiser minimises the result.
a2cPolicyGradientLoss :: [Double] -> [Double] -> Double
a2cPolicyGradientLoss newLogProbs advantages
  | null advantages = 0.0
  | otherwise =
      let n = fromIntegral (length advantages) :: Double
          terms = zipWith (*) newLogProbs advantages
       in negate (sum terms / n)

-- | Combined A2C loss minimised per update step.
a2cTotalLoss
  :: Double
  -- ^ value coefficient @c_v@
  -> Double
  -- ^ entropy coefficient @c_h@
  -> [Double]
  -- ^ new log probabilities
  -> [Double]
  -- ^ advantages
  -> [Double]
  -- ^ predicted values
  -> [Double]
  -- ^ value targets
  -> Double
  -- ^ policy entropy bonus (positive mean entropy)
  -> Double
a2cTotalLoss valueCoef entropyCoef newLogProbs advantages predicted targets entropyBonus =
  let pg = a2cPolicyGradientLoss newLogProbs advantages
      vf = valueFunctionLoss predicted targets
   in pg + valueCoef * vf - entropyCoef * entropyBonus

-- | Sprint 13.8 — real QR-DQN loss math (Dabney et al. 2017,
-- "Distributional Reinforcement Learning with Quantile Regression").
--
-- QR-DQN replaces the scalar Q-value with a distribution over
-- @numQuantiles@ atoms parameterised by quantile midpoints
-- @tau_i = (i + 0.5) / numQuantiles@. The per-step loss is the
-- quantile-Huber regression of the predicted quantiles against the
-- Bellman-projected target distribution.
module JitML.RL.Algorithms.QrDqnLoss
  ( quantileMidpoints
  , quantileHuberLoss
  , qrDqnLoss
  )
where

-- | Quantile midpoints @(i + 0.5) / N@ for @N@ atoms.
quantileMidpoints :: Int -> [Double]
quantileMidpoints n
  | n <= 0 = []
  | otherwise =
      let denom = fromIntegral n :: Double
       in [(fromIntegral i + 0.5) / denom | i <- [0 .. n - 1]]

-- | Asymmetric quantile-Huber loss applied to a single residual:
--
-- @rho_tau(u) = |tau - 1{u < 0}| * Huber_kappa(u)@
--
-- where Huber switches between L2 (within @kappa@) and L1 (beyond).
quantileHuberLoss :: Double -> Double -> Double -> Double
quantileHuberLoss kappa tau residual =
  let asymmetric =
        if residual < 0
          then abs (tau - 1.0)
          else abs tau
      huber
        | abs residual <= kappa = 0.5 * residual * residual
        | otherwise = kappa * (abs residual - 0.5 * kappa)
   in asymmetric * huber

-- | Total QR-DQN loss across @N@ predicted quantiles and @N@ target
-- quantiles. Mean over the @N x N@ pairs per step, averaged over the
-- batch.
qrDqnLoss :: Double -> [[Double]] -> [[Double]] -> Double
qrDqnLoss kappa predictedAtoms targetAtoms
  | null predictedAtoms = 0.0
  | otherwise =
      let stepCount = fromIntegral (length predictedAtoms) :: Double
          stepLoss predicted targets =
            let n = length predicted
                taus = quantileMidpoints n
                pairs =
                  [ quantileHuberLoss kappa tau (theta_t - theta_p)
                  | (tau, theta_p) <- zip taus predicted
                  , theta_t <- targets
                  ]
             in sum pairs / fromIntegral (length pairs)
       in sum (zipWith stepLoss predictedAtoms targetAtoms) / stepCount

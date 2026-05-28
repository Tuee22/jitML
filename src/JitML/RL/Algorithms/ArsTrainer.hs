{-# LANGUAGE BangPatterns #-}

-- | Sprint 13.8 — real ARS (Augmented Random Search, Mania et al. 2018)
-- training loop, the gradient-free / evolution-strategy member of the
-- specialised family. ARS optimises a /linear/ policy by finite-
-- difference: it samples perturbation directions around the current
-- parameters, evaluates the episode return for the @+nu*delta@ and
-- @-nu*delta@ rollouts, keeps the top-@b@ directions, and steps the
-- parameters along the return-weighted direction sum.
--
-- The update math (top-b retention + direction aggregation) comes from
-- "JitML.RL.Algorithms.ArsLoss"; this module supplies the linear-policy
-- rollout on the canonical cartpole simulator and the @alpha / (b *
-- sigma_R)@ scaling.
--
-- Bit-deterministic on the same substrate / same seed (seeded Gaussian
-- perturbations, deterministic rollouts from the fixed cartpole start).
module JitML.RL.Algorithms.ArsTrainer
  ( ArsTrainConfig (..)
  , defaultArsTrainConfig
  , ArsTrainResult (..)
  , ArsIterationStat (..)
  , trainArsOnCartpole
  )
where

import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.RL.Algorithms.ArsLoss (arsTopDirections, arsUpdateDirection)
import JitML.RL.Simulator
  ( CartPoleState (..)
  , SimStep (..)
  , cartPoleInitial
  , cartPoleStep
  )

data ArsTrainConfig = ArsTrainConfig
  { arsSeed :: !Int
  , arsIterations :: !Int
  , arsNumDirections :: !Int
  , arsTopB :: !Int
  , arsStepSize :: !Double -- alpha
  , arsNoiseStd :: !Double -- nu
  , arsMaxEpisodeSteps :: !Int
  , arsActionCount :: !Int
  , arsObsSize :: !Int
  }
  deriving stock (Eq, Show)

defaultArsTrainConfig :: ArsTrainConfig
defaultArsTrainConfig =
  ArsTrainConfig
    { arsSeed = 42
    , arsIterations = 50
    , arsNumDirections = 16
    , arsTopB = 8
    , arsStepSize = 0.05
    , arsNoiseStd = 0.1
    , arsMaxEpisodeSteps = 500
    , arsActionCount = 2
    , arsObsSize = 4
    }

data ArsIterationStat = ArsIterationStat
  { arsIterIndex :: !Int
  , arsIterMeanReturn :: !Double
  , arsIterBestReturn :: !Double
  }
  deriving stock (Eq, Show)

data ArsTrainResult = ArsTrainResult
  { arsResultStats :: ![ArsIterationStat]
  , arsResultFinalParams :: !(Vector Double)
  , arsResultConfig :: !ArsTrainConfig
  }
  deriving stock (Eq, Show)

-- | The linear policy parameters are a flat @actionCount * obsSize@
-- matrix (row-major); the action is @argmax (theta `matVec` obs)@.
paramDim :: ArsTrainConfig -> Int
paramDim config = arsActionCount config * arsObsSize config

trainArsOnCartpole :: ArsTrainConfig -> IO ArsTrainResult
trainArsOnCartpole config = do
  let theta0 = VU.replicate (paramDim config) 0.0
      gen0 = Random.mkStdGen (arsSeed config)
  pure (go config theta0 gen0 0 [])

go
  :: ArsTrainConfig
  -> Vector Double
  -> Random.StdGen
  -> Int
  -> [ArsIterationStat]
  -> ArsTrainResult
go config theta gen iteration stats
  | iteration >= arsIterations config =
      ArsTrainResult
        { arsResultStats = reverse stats
        , arsResultFinalParams = theta
        , arsResultConfig = config
        }
  | otherwise =
      let (deltas, gen') = sampleDirections config gen
          nu = arsNoiseStd config
          triples =
            [ ( evaluatePolicy config (VU.zipWith (\t d -> t + nu * d) theta delta)
              , evaluatePolicy config (VU.zipWith (\t d -> t - nu * d) theta delta)
              , VU.toList delta
              )
            | delta <- deltas
            ]
          kept = arsTopDirections (arsTopB config) triples
          keptReturns = concatMap (\(p, m, _) -> [p, m]) kept
          sigmaR = max 1.0e-6 (stddev keptReturns)
          updateVec = arsUpdateDirection kept
          scale = arsStepSize config / (fromIntegral (max 1 (arsTopB config)) * sigmaR)
          thetaNext =
            VU.zipWith
              (\t u -> t + scale * u)
              theta
              (VU.fromList updateVec)
          allReturns = concatMap (\(p, m, _) -> [p, m]) triples
          meanR =
            if null allReturns then 0.0 else sum allReturns / fromIntegral (length allReturns)
          bestR = if null allReturns then 0.0 else maximum allReturns
          stat = ArsIterationStat iteration meanR bestR
       in go config thetaNext gen' (iteration + 1) (stat : stats)

-- | Evaluate one episode's return under the deterministic linear-argmax
-- policy from the fixed cartpole start.
evaluatePolicy :: ArsTrainConfig -> Vector Double -> Double
evaluatePolicy config theta = loop cartPoleInitial 0 0.0
 where
  loop !state !len !ret
    | len >= arsMaxEpisodeSteps config = ret
    | otherwise =
        let action = linearAction config theta (obsVector state)
            stepResult = cartPoleStep state action
            ret' = ret + simStepReward stepResult
         in if simStepDone stepResult
              then ret'
              else loop (simStepState stepResult) (len + 1) ret'

linearAction :: ArsTrainConfig -> Vector Double -> Vector Double -> Int
linearAction config theta obs =
  let obsSize = arsObsSize config
      scoreFor a =
        let row = VU.slice (a * obsSize) obsSize theta
         in VU.sum (VU.zipWith (*) row obs)
      scores = [scoreFor a | a <- [0 .. arsActionCount config - 1]]
   in argmax scores

argmax :: (Ord a) => [a] -> Int
argmax [] = 0
argmax xs = snd (foldr1 stepMax (zip xs [0 ..]))
 where
  stepMax (v1, i1) (v2, i2)
    | v1 >= v2 = (v1, i1)
    | otherwise = (v2, i2)

sampleDirections :: ArsTrainConfig -> Random.StdGen -> ([Vector Double], Random.StdGen)
sampleDirections config gen0 =
  goDir (arsNumDirections config) gen0 []
 where
  dim = paramDim config
  goDir 0 g acc = (reverse acc, g)
  goDir k g acc =
    let (vec, g') = gaussianVector dim g
     in goDir (k - 1) g' (vec : acc)

gaussianVector :: Int -> Random.StdGen -> (Vector Double, Random.StdGen)
gaussianVector n gen0 = goVec n gen0 []
 where
  goVec 0 g acc = (VU.fromList (reverse acc), g)
  goVec k g acc =
    let (x, g') = gaussian g
     in goVec (k - 1) g' (x : acc)

gaussian :: Random.StdGen -> (Double, Random.StdGen)
gaussian g0 =
  let (u1, g1) = Random.uniformR (1.0e-12, 1.0 :: Double) g0
      (u2, g2) = Random.uniformR (0.0, 1.0 :: Double) g1
   in (sqrt (-(2.0 * log u1)) * cos (2.0 * pi * u2), g2)

stddev :: [Double] -> Double
stddev [] = 0.0
stddev xs =
  let n = fromIntegral (length xs)
      meanX = sum xs / n
      varX = sum (map (\x -> (x - meanX) ^ (2 :: Int)) xs) / n
   in sqrt varX

obsVector :: CartPoleState -> Vector Double
obsVector state =
  VU.fromList
    [ cartPosition state
    , cartVelocity state
    , poleAngle state
    , poleAngularVelocity state
    ]

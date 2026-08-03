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
  , initialArsParams
  , trainArsOnCartpole
  , trainArsOnEnvironment
  , evaluateArsPolicyWithEnvironment
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.RL.Algorithms.ArsLoss (arsTopDirections, arsUpdateDirection)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Simulator
  ( SimStep (..)
  , SimulatedEnvironment (..)
  , SomeSimulatedEnvironment (..)
  , cartPoleEnvironment
  , renderObservation
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
  , arsResultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Exact physical perturbation-rollout transitions and applied linear-policy
  -- updates, accumulated by the trainer loop rather than reconstructed from its
  -- configuration.
  , arsResultConfig :: !ArsTrainConfig
  }
  deriving stock (Eq, Show)

-- | The linear policy parameters are a flat @actionCount * obsSize@
-- matrix (row-major); the action is @argmax (theta `matVec` obs)@.
paramDim :: ArsTrainConfig -> Int
paramDim config = arsActionCount config * arsObsSize config

trainArsOnCartpole :: ArsTrainConfig -> IO ArsTrainResult
trainArsOnCartpole =
  trainArsOnSimulatedEnvironment cartPoleEnvironment

trainArsOnEnvironment :: SomeSimulatedEnvironment -> ArsTrainConfig -> IO ArsTrainResult
trainArsOnEnvironment (SomeSimulatedEnvironment environment) =
  trainArsOnSimulatedEnvironment environment

evaluateArsPolicyWithEnvironment
  :: SomeSimulatedEnvironment
  -> ArsTrainConfig
  -> Vector Double
  -> Int
  -> [Common.EvaluationEpisodeResult]
evaluateArsPolicyWithEnvironment (SomeSimulatedEnvironment environment) config theta episodeCount =
  replicate (max 1 episodeCount) (evaluatePolicyEpisode environment config theta)

trainArsOnSimulatedEnvironment :: SimulatedEnvironment state -> ArsTrainConfig -> IO ArsTrainResult
trainArsOnSimulatedEnvironment environment config = do
  let theta0 = initialArsParams config
      gen0 = Random.mkStdGen (arsSeed config)
  either
    (fail . Text.unpack)
    pure
    (go environment config theta0 gen0 0 0 0 [])

initialArsParams :: ArsTrainConfig -> Vector Double
initialArsParams config =
  VU.replicate (paramDim config) 0.0

go
  :: SimulatedEnvironment state
  -> ArsTrainConfig
  -> Vector Double
  -> Random.StdGen
  -> Int
  -> Integer
  -> Integer
  -> [ArsIterationStat]
  -> Either Text ArsTrainResult
go environment config theta gen iteration observedTransitions appliedUpdates stats
  | iteration >= arsIterations config = do
      measuredCounters <-
        Common.mkMeasuredTrainerCounters observedTransitions appliedUpdates
      pure
        ArsTrainResult
          { arsResultStats = reverse stats
          , arsResultFinalParams = theta
          , arsResultMeasuredCounters = measuredCounters
          , arsResultConfig = config
          }
  | otherwise =
      let (deltas, gen') = sampleDirections config gen
          nu = arsNoiseStd config
          evaluated =
            [ ( evaluateTrainingPolicy
                  environment
                  config
                  (VU.zipWith (\t d -> t + nu * d) theta delta)
              , evaluateTrainingPolicy
                  environment
                  config
                  (VU.zipWith (\t d -> t - nu * d) theta delta)
              , VU.toList delta
              )
            | delta <- deltas
            ]
          triples =
            [ (plusReturn, minusReturn, delta)
            | ((plusReturn, _), (minusReturn, _), delta) <- evaluated
            ]
          transitionCount =
            sum
              [ toInteger plusSteps + toInteger minusSteps
              | ((_, plusSteps), (_, minusSteps), _) <- evaluated
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
       in go
            environment
            config
            thetaNext
            gen'
            (iteration + 1)
            (observedTransitions + transitionCount)
            (appliedUpdates + 1)
            (stat : stats)

-- | Evaluate one perturbation for exactly the scheduled number of physical
-- environment transitions. A terminal state closes that episode and the next
-- transition starts from the environment's canonical initial state; no
-- post-terminal horizon slots are reported as if they had executed. The
-- perturbation score is the mean of its completed (plus final partial) episode
-- returns, preserving episodic duration as signal in constant-per-step-reward
-- environments such as cartpole and mountain-car.
evaluateTrainingPolicy
  :: SimulatedEnvironment state -> ArsTrainConfig -> Vector Double -> (Double, Int)
evaluateTrainingPolicy environment config theta =
  loop (envInitial environment) 0 (0 :: Int) 0.0 []
 where
  loop !state !totalSteps !episodeSteps !episodeReturn !completedReturns
    | totalSteps >= arsMaxEpisodeSteps config =
        let scoredReturns =
              if episodeSteps > 0
                then episodeReturn : completedReturns
                else completedReturns
            score =
              if null scoredReturns
                then 0.0
                else sum scoredReturns / fromIntegral (length scoredReturns)
         in (score, totalSteps)
    | otherwise =
        let action = linearAction environment config state theta (obsVector environment state)
            stepResult = envStep environment state action
            episodeReturn' = episodeReturn + simStepReward stepResult
            totalSteps' = totalSteps + 1
         in if simStepDone stepResult
              then
                loop
                  (envInitial environment)
                  totalSteps'
                  0
                  0.0
                  (episodeReturn' : completedReturns)
              else
                loop
                  (simStepState stepResult)
                  totalSteps'
                  (episodeSteps + 1)
                  episodeReturn'
                  completedReturns

evaluatePolicyEpisode
  :: SimulatedEnvironment state
  -> ArsTrainConfig
  -> Vector Double
  -> Common.EvaluationEpisodeResult
evaluatePolicyEpisode environment config theta = loop (envInitial environment) 0 0.0
 where
  loop !state !len !ret
    | len >= arsMaxEpisodeSteps config =
        Common.EvaluationEpisodeResult ret len False
    | otherwise =
        let action = linearAction environment config state theta (obsVector environment state)
            stepResult = envStep environment state action
            ret' = ret + simStepReward stepResult
            len' = len + 1
         in if simStepDone stepResult
              then Common.EvaluationEpisodeResult ret' len' True
              else loop (simStepState stepResult) len' ret'

linearAction
  :: SimulatedEnvironment state -> ArsTrainConfig -> state -> Vector Double -> Vector Double -> Int
linearAction environment config state theta obs =
  let obsSize = arsObsSize config
      mask = envActionMask environment <*> Just state
      scoreFor a =
        let row = VU.slice (a * obsSize) obsSize theta
         in case mask of
              Just legal | a < length legal && not (legal !! a) -> -1.0e12
              _ -> VU.sum (VU.zipWith (*) row obs)
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

obsVector :: SimulatedEnvironment state -> state -> Vector Double
obsVector environment =
  VU.fromList . renderObservation . envRenderFrame environment

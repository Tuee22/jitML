{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

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
  , ArsTrainObservation
  , PreparedArsTraining
  , ArsPreparedSnapshot
  , prepareArsOnEnvironment
  , preparedArsSnapshot
  , arsPreparedConfig
  , arsPreparedInitialParams
  , arsPreparedGenerator
  , arsPreparedInitialFrame
  , continuePreparedArsRaw
  , ArsIterationObservation (..)
  , ArsAppliedStep (..)
  , ArsNumericalRuntime (..)
  , arsNativeNumericalRuntime
  , validateArsAppliedStep
  , validateArsTrainObservation
  , refineArsTrainObservation
  , trainArsOnEnvironmentRaw
  , trainArsOnCartpoleRaw
  )
where

import Control.Monad (foldM, unless, zipWithM_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Version (showVersion)
import GHC.Float (castDoubleToWord64)
import System.Info qualified as SystemInfo
import System.Random qualified as Random

import JitML.Execution.SingleUse qualified as SingleUse
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
  , arsResultInitialParams :: !(Vector Double)
  , arsResultFinalParams :: !(Vector Double)
  , arsResultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Exact physical perturbation-rollout transitions and applied linear-policy
  -- updates, accumulated by the trainer loop rather than reconstructed from its
  -- configuration.
  , arsResultConfig :: !ArsTrainConfig
  }
  deriving stock (Eq, Show)

-- | Uncensored numerical return; no producer/device/learning authority.
type ArsTrainObservation =
  Common.RawTrainerResult (Vector Double) ArsIterationObservation ArsTrainConfig

refineArsTrainObservation :: ArsTrainObservation -> Either Text ArsTrainResult
refineArsTrainObservation observed = do
  counters <- Common.refineObservedTrainerCounters (Common.rawTrainerCounters observed)
  pure
    ArsTrainResult
      { arsResultStats = fmap arsObservationStatistic (Common.rawTrainerStats observed)
      , arsResultInitialParams = Common.rawTrainerInitialParams observed
      , arsResultFinalParams = Common.rawTrainerFinalParams observed
      , arsResultMeasuredCounters = counters
      , arsResultConfig = Common.rawTrainerConfig observed
      }

-- BEGIN ARS RAW APPLIED-STEP TYPES

-- | Descriptive current runtime tuple, not executable/libm authentication.
-- Equal tuples do not prove equal libm implementations or compiler flags.
data ArsNumericalRuntime = ArsNumericalRuntime
  { arsRuntimeOperatingSystem :: !Text
  , arsRuntimeArchitecture :: !Text
  , arsRuntimeCompiler :: !Text
  , arsRuntimeCompilerVersion :: !Text
  , arsRuntimeArithmeticRecipe :: !Text
  }
  deriving stock (Eq, Show)

arsNativeNumericalRuntime :: ArsNumericalRuntime
arsNativeNumericalRuntime =
  ArsNumericalRuntime
    { arsRuntimeOperatingSystem = Text.pack SystemInfo.os
    , arsRuntimeArchitecture = Text.pack SystemInfo.arch
    , arsRuntimeCompiler = Text.pack SystemInfo.compilerName
    , arsRuntimeCompilerVersion = Text.pack (showVersion SystemInfo.compilerVersion)
    , arsRuntimeArithmeticRecipe = "ars-native-double-box-muller-population-stddev-v1"
    }

-- | Deliberately forgeable numerical data, captured from the actual lexical
-- values in one optimizer application. It is neither an accepted-step bit nor
-- authenticated execution, eligibility, or evidence of return improvement.
data ArsAppliedStep = ArsAppliedStep
  { arsStepConfig :: !ArsTrainConfig
  , arsStepNumericalRuntime :: !ArsNumericalRuntime
  , arsStepIndex :: !Int
  , arsStepThetaBefore :: !(Vector Double)
  , arsStepThetaAfter :: !(Vector Double)
  , arsStepSampledDirections :: ![Vector Double]
  , arsStepEvaluatedPerturbations :: ![((Double, Int), (Double, Int), [Double])]
  , arsStepKeptDirections :: ![(Double, Double, [Double])]
  , arsStepNoiseStd :: !Double
  , arsStepReturnStdDev :: !Double
  , arsStepUpdateDirection :: ![Double]
  , arsStepScale :: !Double
  , arsStepObservedTransitions :: !Integer
  }
  deriving stock (Eq, Show)

-- | The legacy statistic remains unchanged inside each raw observation.
data ArsIterationObservation = ArsIterationObservation
  { arsObservationStatistic :: !ArsIterationStat
  , arsObservationAppliedStep :: !ArsAppliedStep
  }
  deriving stock (Eq, Show)

-- END ARS RAW APPLIED-STEP TYPES

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
  observed <- trainArsOnSimulatedEnvironmentRaw environment config
  either (fail . Text.unpack) pure (refineArsTrainObservation observed)

trainArsOnSimulatedEnvironmentRaw
  :: SimulatedEnvironment state -> ArsTrainConfig -> IO ArsTrainObservation
trainArsOnSimulatedEnvironmentRaw environment config = do
  prepared <- prepareArsOnSimulatedEnvironment environment config
  result <- continuePreparedArsRaw prepared
  either (fail . Text.unpack) pure result

-- | The actual immutable values captured by preparation. This is observable
-- numerical state, not an execution, durable-publication or origin capability.
-- The frame is the initial rendered observation, not a general resume codec.
-- Fields stay lazy for the ordinary wrappers' historical evaluation order;
-- a durable producer must fully serialize this snapshot before continuing.
data ArsPreparedSnapshot
  = ArsPreparedSnapshot
      ArsTrainConfig
      (Vector Double)
      Random.StdGen
      (Vector Double)

-- The constructor and fields are private. A caller cannot substitute a raw
-- snapshot, environment, generator or trainer callback into a prepared run.
data PreparedArsTraining where
  PreparedArsTraining
    :: SimulatedEnvironment state
    -> ArsPreparedSnapshot
    -> SingleUse.SingleUse
    -> PreparedArsTraining

prepareArsOnEnvironment
  :: SomeSimulatedEnvironment -> ArsTrainConfig -> IO PreparedArsTraining
prepareArsOnEnvironment (SomeSimulatedEnvironment environment) =
  prepareArsOnSimulatedEnvironment environment

prepareArsOnSimulatedEnvironment
  :: SimulatedEnvironment state -> ArsTrainConfig -> IO PreparedArsTraining
prepareArsOnSimulatedEnvironment environment config = do
  let theta0 = initialArsParams config
      gen0 = Random.mkStdGen (arsSeed config)
      snapshot =
        ArsPreparedSnapshot
          config
          theta0
          gen0
          (obsVector environment (envInitial environment))
  PreparedArsTraining environment snapshot <$> SingleUse.newSingleUse

preparedArsSnapshot :: PreparedArsTraining -> ArsPreparedSnapshot
preparedArsSnapshot (PreparedArsTraining _ snapshot _) = snapshot

arsPreparedConfig :: ArsPreparedSnapshot -> ArsTrainConfig
arsPreparedConfig (ArsPreparedSnapshot config _ _ _) = config

arsPreparedInitialParams :: ArsPreparedSnapshot -> Vector Double
arsPreparedInitialParams (ArsPreparedSnapshot _ theta0 _ _) = theta0

arsPreparedGenerator :: ArsPreparedSnapshot -> Random.StdGen
arsPreparedGenerator (ArsPreparedSnapshot _ _ gen0 _) = gen0

arsPreparedInitialFrame :: ArsPreparedSnapshot -> Vector Double
arsPreparedInitialFrame (ArsPreparedSnapshot _ _ _ frame) = frame

-- | Consume once, using the same actual prepared values in the unchanged
-- numerical loop. Cancellation or failure does not make this state reusable.
-- Raw results remain numerical data and supply no completion or origin proof.
continuePreparedArsRaw
  :: PreparedArsTraining -> IO (Either Text ArsTrainObservation)
continuePreparedArsRaw (PreparedArsTraining environment snapshot singleUse) = do
  first <- SingleUse.tryConsumeSingleUse singleUse
  if first
    then
      let config = arsPreparedConfig snapshot
          theta0 = arsPreparedInitialParams snapshot
          gen0 = arsPreparedGenerator snapshot
       in pure (go theta0 environment config theta0 gen0 0 0 0 [])
    else pure (Left "ARS prepared training was already consumed")

initialArsParams :: ArsTrainConfig -> Vector Double
initialArsParams config =
  VU.replicate (paramDim config) 0.0

go
  :: Vector Double
  -> SimulatedEnvironment state
  -> ArsTrainConfig
  -> Vector Double
  -> Random.StdGen
  -> Int
  -> Integer
  -> Integer
  -> [ArsIterationObservation]
  -> Either Text ArsTrainObservation
go initialSnapshot environment config theta gen iteration observedTransitions appliedUpdates stats
  | iteration >= arsIterations config = do
      measuredCounters <-
        Common.mkObservedTrainerCounters observedTransitions appliedUpdates
      pure
        Common.RawTrainerResult
          { Common.rawTrainerInitialParams = initialSnapshot
          , Common.rawTrainerFinalParams = theta
          , Common.rawTrainerStats = reverse stats
          , Common.rawTrainerCounters = measuredCounters
          , Common.rawTrainerConfig = config
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
          -- Capture existing lexical values only; this performs no extra
          -- environment transition, evaluation, sampling, or optimizer update.
          appliedStep =
            ArsAppliedStep
              { arsStepConfig = config
              , arsStepNumericalRuntime = arsNativeNumericalRuntime
              , arsStepIndex = iteration
              , arsStepThetaBefore = theta
              , arsStepThetaAfter = thetaNext
              , arsStepSampledDirections = deltas
              , arsStepEvaluatedPerturbations = evaluated
              , arsStepKeptDirections = kept
              , arsStepNoiseStd = nu
              , arsStepReturnStdDev = sigmaR
              , arsStepUpdateDirection = updateVec
              , arsStepScale = scale
              , arsStepObservedTransitions = transitionCount
              }
          observation = ArsIterationObservation stat appliedStep
       in go
            initialSnapshot
            environment
            config
            thetaNext
            gen'
            (iteration + 1)
            (observedTransitions + transitionCount)
            (appliedUpdates + 1)
            (observation : stats)

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

trainArsOnEnvironmentRaw :: SomeSimulatedEnvironment -> ArsTrainConfig -> IO ArsTrainObservation
trainArsOnEnvironmentRaw (SomeSimulatedEnvironment environment) = trainArsOnSimulatedEnvironmentRaw environment

trainArsOnCartpoleRaw :: ArsTrainConfig -> IO ArsTrainObservation
trainArsOnCartpoleRaw = trainArsOnSimulatedEnvironmentRaw cartPoleEnvironment

-- BEGIN ARS RAW APPLIED-STEP VALIDATION

-- | Replay finite numerical data exactly. This does not re-run the environment
-- or authenticate where the recorded rewards, process, or source came from.
-- Binary64 comparison includes signed zero; there is no tolerance allowance.
validateArsAppliedStep :: ArsAppliedStep -> Either Text ()
validateArsAppliedStep step = do
  let config = arsStepConfig step
      directions = arsStepSampledDirections step
      evaluated = arsStepEvaluatedPerturbations step
      kept = arsStepKeptDirections step
      dimensions = toInteger (arsActionCount config) * toInteger (arsObsSize config)
  validateArsObservationConfig config
  requireArsObservation
    (arsStepNumericalRuntime step == arsNativeNumericalRuntime)
    "ARS applied-step numerical runtime differs from the current replay runtime"
  requireArsObservation
    (arsStepIndex step >= 0 && arsStepIndex step < arsIterations config)
    "ARS applied-step index is outside its configuration"
  requireArsObservation
    ( validArsVector dimensions (arsStepThetaBefore step)
        && validArsVector dimensions (arsStepThetaAfter step)
    )
    "ARS applied-step theta shape or finite values differ"
  requireArsObservation
    (length directions == arsNumDirections config)
    "ARS applied-step sampled direction count differs"
  requireArsObservation
    (all (validArsVector dimensions) directions)
    "ARS applied-step sampled direction shape or finite values differ"
  requireArsObservation
    (length evaluated == arsNumDirections config)
    "ARS applied-step perturbation count differs"
  zipWithM_ (validateArsPerturbation config dimensions) directions evaluated
  let triples = [(plusReturn, minusReturn, delta) | ((plusReturn, _), (minusReturn, _), delta) <- evaluated]
      expectedKept = arsTopDirections (arsTopB config) triples
      keptReturns = concatMap (\(plusReturn, minusReturn, _) -> [plusReturn, minusReturn]) expectedKept
      expectedSigma = max 1.0e-6 (stddev keptReturns)
      expectedUpdate = arsUpdateDirection expectedKept
      expectedScale = arsStepSize config / (fromIntegral (max 1 (arsTopB config)) * expectedSigma)
      expectedTheta =
        VU.zipWith
          (\theta update -> theta + expectedScale * update)
          (arsStepThetaBefore step)
          (VU.fromList expectedUpdate)
      transitions =
        sum [toInteger plusSteps + toInteger minusSteps | ((_, plusSteps), (_, minusSteps), _) <- evaluated]
      configuredTransitions = 2 * toInteger (arsNumDirections config) * toInteger (arsMaxEpisodeSteps config)
  requireArsObservation
    (sameArsTriples kept expectedKept)
    "ARS applied-step kept directions or order differ"
  requireArsObservation
    (sameArsDouble (arsStepNoiseStd step) (arsNoiseStd config))
    "ARS applied-step noise standard deviation differs"
  requireArsObservation
    (finiteArsDouble expectedSigma && sameArsDouble (arsStepReturnStdDev step) expectedSigma)
    "ARS applied-step return standard deviation differs"
  requireArsObservation
    (all finiteArsDouble expectedUpdate && sameArsDoubles (arsStepUpdateDirection step) expectedUpdate)
    "ARS applied-step aggregate update differs"
  requireArsObservation
    (finiteArsDouble expectedScale && sameArsDouble (arsStepScale step) expectedScale)
    "ARS applied-step scale differs"
  requireArsObservation
    (VU.all finiteArsDouble expectedTheta && sameArsVector (arsStepThetaAfter step) expectedTheta)
    "ARS applied-step theta arithmetic differs"
  requireArsObservation
    (arsStepObservedTransitions step == transitions && transitions == configuredTransitions)
    "ARS applied-step physical transition count differs"

validateArsPerturbation
  :: ArsTrainConfig
  -> Integer
  -> Vector Double
  -> ((Double, Int), (Double, Int), [Double])
  -> Either Text ()
validateArsPerturbation config dimensions direction ((plusReturn, plusSteps), (minusReturn, minusSteps), delta) = do
  requireArsObservation
    ( toInteger (length delta) == dimensions
        && all finiteArsDouble delta
        && sameArsDoubles delta (VU.toList direction)
    )
    "ARS applied-step evaluated direction differs from sampled direction"
  requireArsObservation
    (finiteArsDouble plusReturn && finiteArsDouble minusReturn)
    "ARS applied-step perturbation return is nonfinite"
  requireArsObservation
    (plusSteps == arsMaxEpisodeSteps config && minusSteps == arsMaxEpisodeSteps config)
    "ARS applied-step perturbation physical steps differ"

-- | Validate the complete retained initial -> every actual application -> final
-- chain, seeded direction order, legacy statistics and observed counters.
-- Finite no-op and worsening updates are deliberately accepted as data.
validateArsTrainObservation :: ArsTrainObservation -> Either Text ()
validateArsTrainObservation observed = do
  let config = Common.rawTrainerConfig observed
      observations = Common.rawTrainerStats observed
      initial = Common.rawTrainerInitialParams observed
      final = Common.rawTrainerFinalParams observed
      dimensions = toInteger (arsActionCount config) * toInteger (arsObsSize config)
  validateArsObservationConfig config
  requireArsObservation
    (validArsVector dimensions initial && validArsVector dimensions final)
    "ARS trace initial/final shape or finite values differ"
  requireArsObservation
    (sameArsVector initial (initialArsParams config))
    "ARS trace initial parameters differ from the configured initializer"
  requireArsObservation
    (length observations == arsIterations config)
    "ARS trace iteration count differs"
  (_, finalTheta, transitions) <-
    foldM
      (validateArsChainStep config)
      (Random.mkStdGen (arsSeed config), initial, 0)
      (zip [0 :: Int ..] observations)
  requireArsObservation
    (sameArsVector final finalTheta)
    "ARS trace final parameters differ from its applied-step chain"
  requireArsObservation
    ( toInteger (Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters observed))
        == transitions
    )
    "ARS trace observed physical transition count differs"
  requireArsObservation
    ( toInteger (Common.observedOptimizerUpdateCount (Common.rawTrainerCounters observed))
        == toInteger (length observations)
    )
    "ARS trace observed optimizer update count differs"

validateArsChainStep
  :: ArsTrainConfig
  -> (Random.StdGen, Vector Double, Integer)
  -> (Int, ArsIterationObservation)
  -> Either Text (Random.StdGen, Vector Double, Integer)
validateArsChainStep config (generator, theta, transitions) (index, observation) = do
  let step = arsObservationAppliedStep observation
      stat = arsObservationStatistic observation
  requireArsObservation
    (sameArsConfig config (arsStepConfig step))
    "ARS trace applied-step configuration differs"
  requireArsObservation
    (arsStepIndex step == index && arsIterIndex stat == index)
    "ARS trace iteration index differs"
  requireArsObservation
    (sameArsVector theta (arsStepThetaBefore step))
    "ARS trace applied-step chain is discontinuous"
  validateArsAppliedStep step
  let (expectedDirections, nextGenerator) = sampleDirections config generator
      allReturns =
        concatMap
          (\((plusReturn, _), (minusReturn, _), _) -> [plusReturn, minusReturn])
          (arsStepEvaluatedPerturbations step)
      expectedMean = if null allReturns then 0.0 else sum allReturns / fromIntegral (length allReturns)
      expectedBest = if null allReturns then 0.0 else maximum allReturns
  requireArsObservation
    ( length expectedDirections == length (arsStepSampledDirections step)
        && and (zipWith sameArsVector expectedDirections (arsStepSampledDirections step))
    )
    "ARS trace sampled directions differ from its configured RNG sequence"
  requireArsObservation
    ( all finiteArsDouble [arsIterMeanReturn stat, arsIterBestReturn stat, expectedMean, expectedBest]
        && sameArsDouble (arsIterMeanReturn stat) expectedMean
        && sameArsDouble (arsIterBestReturn stat) expectedBest
    )
    "ARS trace legacy perturbation statistics differ"
  pure (nextGenerator, arsStepThetaAfter step, transitions + arsStepObservedTransitions step)

validateArsObservationConfig :: ArsTrainConfig -> Either Text ()
validateArsObservationConfig config =
  requireArsObservation
    ( arsIterations config >= 0
        && all
          (> 0)
          [ arsNumDirections config
          , arsTopB config
          , arsMaxEpisodeSteps config
          , arsActionCount config
          , arsObsSize config
          ]
        && arsTopB config <= arsNumDirections config
        && toInteger (arsActionCount config) * toInteger (arsObsSize config) <= toInteger (maxBound :: Int)
        && all finiteArsDouble [arsStepSize config, arsNoiseStd config]
        && arsStepSize config >= 0
        && arsNoiseStd config > 0
    )
    "ARS trace configuration is invalid"

requireArsObservation :: Bool -> Text -> Either Text ()
requireArsObservation condition reason = unless condition (Left reason)

finiteArsDouble :: Double -> Bool
finiteArsDouble value = not (isNaN value || isInfinite value)

validArsVector :: Integer -> Vector Double -> Bool
validArsVector dimensions values = toInteger (VU.length values) == dimensions && VU.all finiteArsDouble values

sameArsDouble :: Double -> Double -> Bool
sameArsDouble left right = castDoubleToWord64 left == castDoubleToWord64 right

sameArsDoubles :: [Double] -> [Double] -> Bool
sameArsDoubles left right = fmap castDoubleToWord64 left == fmap castDoubleToWord64 right

sameArsVector :: Vector Double -> Vector Double -> Bool
sameArsVector left right = sameArsDoubles (VU.toList left) (VU.toList right)

sameArsTriples :: [(Double, Double, [Double])] -> [(Double, Double, [Double])] -> Bool
sameArsTriples left right =
  length left == length right && and (zipWith same left right)
 where
  same (leftPlus, leftMinus, leftDelta) (rightPlus, rightMinus, rightDelta) =
    sameArsDouble leftPlus rightPlus
      && sameArsDouble leftMinus rightMinus
      && sameArsDoubles leftDelta rightDelta

sameArsConfig :: ArsTrainConfig -> ArsTrainConfig -> Bool
sameArsConfig left right =
  left {arsStepSize = 0, arsNoiseStd = 0} == right {arsStepSize = 0, arsNoiseStd = 0}
    && sameArsDouble (arsStepSize left) (arsStepSize right)
    && sameArsDouble (arsNoiseStd left) (arsNoiseStd right)

-- END ARS RAW APPLIED-STEP VALIDATION

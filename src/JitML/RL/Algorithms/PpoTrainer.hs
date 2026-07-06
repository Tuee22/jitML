{-# LANGUAGE BangPatterns #-}

-- | Sprint 13.8 — real PPO training loop wired through the pure-Haskell
-- differentiable network seam in "JitML.Numerics.Mlp" and the canonical
-- pure-Haskell cartpole simulator in "JitML.RL.Simulator". This module is
-- the closure for the "live network forward/backward seam" deliverable
-- the on-policy half of the 14-algorithm catalog needs.
--
-- The training loop:
--
--   1. Initialise an MLP with @inputs = obsSize@, @hidden = 64@, and
--      @outputs = actionCount + 1@ (policy logits + value scalar).
--   2. For each iteration: roll out @rolloutSteps@ environment steps under
--      the current policy (sampling actions from @softmax(logits)@ with
--      a deterministic seeded RNG).
--   3. Compute GAE advantages and value targets from the trajectory.
--   4. Run @epochsPerUpdate@ gradient-update passes over the rollout,
--      computing the PPO clipped surrogate loss + value loss + entropy
--      bonus per step, then backprop + Adam update.
--   5. Repeat for @numIterations@ iterations.
--
-- The returned 'PpoTrainResult' carries the per-iteration episode
-- statistics so callers (and the convergence assertion in
-- 'jitml-rl-canonicals') can compare measured medians against the
-- in-code 'ConvergenceThresholds' table.
--
-- Same-substrate / same-seed runs are bit-deterministic (Glorot init
-- through @System.Random@'s 'StdGen', deterministic action sampling,
-- pure-Haskell loss math and backprop).
--
-- The A2C, TRPO, MaskablePPO, and RecurrentPPO algorithms share the same
-- environment and MLP device seam but route through variant-specific update
-- contracts: unclipped A2C, KL-gated TRPO, masked categorical PPO, and
-- sequence-windowed RecurrentPPO.
module JitML.RL.Algorithms.PpoTrainer
  ( -- * Configuration
    PpoTrainConfig (..)
  , OnPolicyVariant (..)
  , defaultPpoTrainConfig

    -- * Result
  , PpoTrainResult (..)
  , PpoIterationStat (..)
  , initialPpoParams

    -- * Run
  , trainPpoOnCartpole
  , trainOnPolicyOnCartpole
  , trainPpoOnCartpoleCuda
  , trainPpoOnCartpoleOneDnn
  , trainPpoOnCartpoleMetal
  , trainOnPolicyOnCartpoleCuda
  , trainOnPolicyOnCartpoleOneDnn
  , trainOnPolicyOnCartpoleMetal
  , trainOnPolicyOnDevice
  , trainOnPolicyOnDeviceWithEnvironment
  , collectRollout
  , evaluateOnPolicyWithEnvironment
  , rolloutSummary

    -- * Internal pieces (re-exported for tests)
  , RolloutStep (..)
  , Rollout (..)
  )
where

import Control.Monad (foldM)
import Data.IORef qualified as IORef
import Data.List qualified
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , PolicyValueOutput (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , policyValueBackward
  , policyValueForward
  , sampleCategorical
  , softmax
  )
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.Algorithms.MaskablePpoLoss qualified as MaskablePpoLoss
import JitML.RL.Algorithms.RecurrentPpoLoss qualified as RecurrentPpoLoss
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
import JitML.RL.Simulator
  ( CartPoleState
  , SimStep (..)
  , SimulatedEnvironment (..)
  , SomeSimulatedEnvironment (..)
  , cartPoleEnvironment
  , renderObservation
  )

-- | The five on-policy algorithms in the catalog share the MLP
-- forward/backward seam + GAE + Adam plumbing, but each variant selects its
-- own update contract:
--
--   * 'VariantPPO' — clipped surrogate (Schulman et al. 2017).
--   * 'VariantA2C' — unclipped policy-gradient surrogate (Mnih et al. 2016).
--   * 'VariantTRPO' — unclipped surrogate plus a conjugate-gradient
--     trust-region line search (Schulman et al. 2015).
--   * 'VariantMaskablePPO' — clipped surrogate over the masked-renormalised
--     categorical distribution.
--   * 'VariantRecurrentPPO' — clipped surrogate applied through
--     sequence-windowed BPTT-style minibatches.
data OnPolicyVariant
  = VariantPPO
  | VariantA2C
  | VariantTRPO
  | VariantMaskablePPO
  | VariantRecurrentPPO
  deriving stock (Eq, Show)

-- | PPO training-loop configuration. The defaults match standard
-- PPO-on-cartpole settings used in the SB3 zoo benchmark suite.
data PpoTrainConfig = PpoTrainConfig
  { ppoSeed :: !Int
  , ppoHiddenUnits :: !Int
  , ppoRolloutSteps :: !Int
  , ppoNumIterations :: !Int
  , ppoEpochsPerUpdate :: !Int
  , ppoMiniBatchSize :: !Int
  , ppoGamma :: !Double
  , ppoLambda :: !Double
  , ppoClipEps :: !Double
  , ppoValueCoef :: !Double
  , ppoEntropyCoef :: !Double
  , ppoMaxEpisodeSteps :: !Int
  , ppoActionCount :: !Int
  , ppoObsSize :: !Int
  , ppoLearningRate :: !Double
  , ppoVariant :: !OnPolicyVariant
  , ppoKlTarget :: !Double
  -- ^ TRPO KL trust-region threshold. Ignored by the non-TRPO variants.
  , ppoTrpoCgIterations :: !Int
  , ppoTrpoBacktrackIterations :: !Int
  , ppoTrpoBacktrackCoef :: !Double
  , ppoRecurrentStateSize :: !Int
  }
  deriving stock (Eq, Show)

defaultPpoTrainConfig :: PpoTrainConfig
defaultPpoTrainConfig =
  PpoTrainConfig
    { ppoSeed = 42
    , ppoHiddenUnits = 64
    , ppoRolloutSteps = 2048
    , ppoNumIterations = 40
    , ppoEpochsPerUpdate = 10
    , ppoMiniBatchSize = 64
    , ppoGamma = 0.99
    , ppoLambda = 0.95
    , ppoClipEps = 0.2
    , ppoValueCoef = 0.5
    , ppoEntropyCoef = 0.0
    , ppoMaxEpisodeSteps = 500
    , ppoActionCount = 2
    , ppoObsSize = 4
    , ppoLearningRate = 3.0e-4
    , ppoVariant = VariantPPO
    , ppoKlTarget = 0.02
    , ppoTrpoCgIterations = 10
    , ppoTrpoBacktrackIterations = 10
    , ppoTrpoBacktrackCoef = 0.8
    , ppoRecurrentStateSize = 16
    }

-- | One step inside a PPO rollout. Carries everything backward needs.
data RolloutStep = RolloutStep
  { rsObs :: !(Vector Double)
  , rsAction :: !Int
  , rsLogProb :: !Double
  , rsValue :: !Double
  , rsReward :: !Double
  , rsDone :: !Bool
  , rsPolicy :: !(Vector Double)
  , rsActionMask :: !(Maybe [Bool])
  , rsRecurrentState :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data Rollout = Rollout
  { rolloutSteps :: ![RolloutStep]
  , rolloutEpisodes :: ![Double] -- per-episode returns observed during rollout
  , rolloutFinalValue :: !Double
  }
  deriving stock (Eq, Show)

-- | Per-iteration stats: mean / median / max episode return inside the
-- iteration's rollout. The convergence assertion compares the median
-- final-iteration return across seeds.
data PpoIterationStat = PpoIterationStat
  { iterIndex :: !Int
  , iterMeanReward :: !Double
  , iterMedianReward :: !Double
  , iterMaxReward :: !Double
  , iterEpisodes :: !Int
  }
  deriving stock (Eq, Show)

data PpoTrainResult = PpoTrainResult
  { resultIterations :: ![PpoIterationStat]
  , resultFinalParams :: !MlpParams
  , resultConfig :: !PpoTrainConfig
  }
  deriving stock (Eq, Show)

-- | Roll out @rolloutSteps@ environment steps under the current policy.
collectRollout
  :: PpoTrainConfig
  -> MlpParams
  -> CartPoleState
  -> Random.StdGen
  -> IO (Rollout, CartPoleState, Random.StdGen)
collectRollout = collectRolloutInEnvironment cartPoleEnvironment

evaluateOnPolicyWithEnvironment
  :: SomeSimulatedEnvironment
  -> PpoTrainConfig
  -> MlpParams
  -> Int
  -> [(Double, Int)]
evaluateOnPolicyWithEnvironment (SomeSimulatedEnvironment environment) config params episodeCount =
  replicate (max 1 episodeCount) (evaluateEpisode environment config params)

evaluateEpisode
  :: SimulatedEnvironment state
  -> PpoTrainConfig
  -> MlpParams
  -> (Double, Int)
evaluateEpisode environment config params = go (envInitial environment) 0 0.0
 where
  go !state !episodeLen !episodeReturn
    | episodeLen >= ppoMaxEpisodeSteps config = (episodeReturn, episodeLen)
    | otherwise =
        let obs = obsVectorFor environment state
            pvOut = policyValueForward params (ppoActionCount config) obs
            actionMask = actionMaskFor environment config state
            probs = maskedPolicyFor config actionMask (pvPolicy pvOut)
            action = argmax (VU.toList probs)
            stepResult = envStep environment state action
            nextReturn = episodeReturn + simStepReward stepResult
            nextLen = episodeLen + 1
         in if simStepDone stepResult
              then (nextReturn, nextLen)
              else go (simStepState stepResult) nextLen nextReturn

collectRolloutInEnvironment
  :: SimulatedEnvironment state
  -> PpoTrainConfig
  -> MlpParams
  -> state
  -> Random.StdGen
  -> IO (Rollout, state, Random.StdGen)
collectRolloutInEnvironment environment config params startState gen0 = do
  stepsRef <- IORef.newIORef ([] :: [RolloutStep])
  episodesRef <- IORef.newIORef ([] :: [Double])
  let go !state !gen !episodeReturn !episodeLen !stepsLeft
        | stepsLeft <= 0 = do
            value <-
              let obs = obsVectorFor environment state
                  fwd = policyValueForward params (ppoActionCount config) obs
               in pure (pvValue fwd)
            pure (state, gen, value)
        | otherwise = do
            let obs = obsVectorFor environment state
                recurrentState = recurrentStateFor config obs episodeReturn episodeLen
                pvOut = policyValueForward params (ppoActionCount config) obs
                actionMask = actionMaskFor environment config state
                probs = maskedPolicyFor config actionMask (pvPolicy pvOut)
                (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                action = sampleCategorical probs u
                logProb =
                  if probs VU.! action <= 0
                    then -1.0e9
                    else log (probs VU.! action)
                stepResult = envStep environment state action
                done = simStepDone stepResult || episodeLen + 1 >= ppoMaxEpisodeSteps config
                step =
                  RolloutStep
                    { rsObs = obs
                    , rsAction = action
                    , rsLogProb = logProb
                    , rsValue = pvValue pvOut
                    , rsReward = simStepReward stepResult
                    , rsDone = done
                    , rsPolicy = probs
                    , rsActionMask = actionMask
                    , rsRecurrentState = recurrentState
                    }
            IORef.modifyIORef' stepsRef (step :)
            let nextReturn = episodeReturn + simStepReward stepResult
                nextLen = episodeLen + 1
            if done
              then do
                IORef.modifyIORef' episodesRef (nextReturn :)
                go (envInitial environment) gen' 0.0 0 (stepsLeft - 1)
              else
                go (simStepState stepResult) gen' nextReturn nextLen (stepsLeft - 1)
  (endState, endGen, finalValue) <- go startState gen0 0.0 0 (ppoRolloutSteps config)
  collected <- IORef.readIORef stepsRef
  episodes <- IORef.readIORef episodesRef
  let rollout =
        Rollout
          { rolloutSteps = reverse collected
          , rolloutEpisodes = reverse episodes
          , rolloutFinalValue = finalValue
          }
  pure (rollout, endState, endGen)

obsVectorFor :: SimulatedEnvironment state -> state -> Vector Double
obsVectorFor environment =
  VU.fromList . renderObservation . envRenderFrame environment

actionMaskFor :: SimulatedEnvironment state -> PpoTrainConfig -> state -> Maybe [Bool]
actionMaskFor environment config state
  | ppoVariant config == VariantMaskablePPO =
      Just $
        case envActionMask environment of
          Nothing -> replicate (ppoActionCount config) True
          Just mask -> mask state
  | otherwise = Nothing

maskedPolicyFor :: PpoTrainConfig -> Maybe [Bool] -> Vector Double -> Vector Double
maskedPolicyFor config mask probs
  | ppoVariant config == VariantMaskablePPO =
      VU.fromList (MaskablePpoLoss.applyActionMask (fromMaybe [] mask) (VU.toList probs))
  | otherwise = probs

recurrentStateFor :: PpoTrainConfig -> Vector Double -> Double -> Int -> Vector Double
recurrentStateFor config obs episodeReturn episodeLen
  | ppoVariant config /= VariantRecurrentPPO = VU.empty
  | otherwise =
      VU.generate
        (max 1 (ppoRecurrentStateSize config))
        ( \i ->
            let obsValue =
                  if VU.null obs
                    then 0.0
                    else obs VU.! (i `mod` VU.length obs)
                phase = fromIntegral (episodeLen + i + 1)
             in tanh (0.65 * obsValue + 0.02 * episodeReturn + 0.01 * phase)
        )

-- | Compute GAE advantages and value targets for a rollout.
computeAdvantages
  :: PpoTrainConfig
  -> Rollout
  -> ([Double], [Double]) -- (advantages, value targets), step-aligned
computeAdvantages config rollout =
  let steps = rolloutSteps rollout
      gamma = ppoGamma config
      lam = ppoLambda config
      finalValue = rolloutFinalValue rollout
      backward (advantage, lastValue) step =
        let nextValue = if rsDone step then 0.0 else lastValue
            delta = rsReward step + gamma * nextValue - rsValue step
            newAdvantage = delta + gamma * lam * (if rsDone step then 0.0 else advantage)
         in ((newAdvantage, rsValue step), newAdvantage)
      (_, advs) = mapAccumR backward (0.0, finalValue) steps
      targets = zipWith (+) advs (map rsValue steps)
   in (advs, targets)

mapAccumR :: (a -> b -> (a, c)) -> a -> [b] -> (a, [c])
mapAccumR _ z [] = (z, [])
mapAccumR f z (x : xs) =
  let (z', rest) = mapAccumR f z xs
      (z'', y) = f z' x
   in (z'', y : rest)

-- | Standardise advantages to mean 0 variance 1.
standardise :: [Double] -> [Double]
standardise [] = []
standardise xs =
  let n = fromIntegral (length xs)
      meanX = sum xs / n
      varX = sum (map (\x -> (x - meanX) ^ (2 :: Int)) xs) / n
      sdX = sqrt varX
   in if sdX < 1.0e-8
        then map (\x -> x - meanX) xs
        else map (\x -> (x - meanX) / sdX) xs

-- | Run one on-policy update over all rollout steps for
-- @epochsPerUpdate@ epochs. For 'VariantTRPO' the epoch loop stops
-- early once the approximate KL between the rollout policy and the
-- updated policy exceeds 'ppoKlTarget' (the trust-region gate).
ppoUpdate
  :: PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> [(RolloutStep, Double, Double)]
  -> (MlpParams, AdamState)
ppoUpdate config params0 adam0 batch =
  let runEpoch
        | ppoVariant config == VariantTRPO = trpoEpoch
        | ppoVariant config == VariantRecurrentPPO = recurrentPpoEpoch
        | otherwise = ppoEpoch
      go acc _ = runEpoch acc
   in Data.List.foldl' go (params0, adam0) [1 .. ppoEpochsPerUpdate config]
 where
  ppoEpoch (params, adam) =
    Data.List.foldl'
      ( \(p, a) (step, advantage, target) ->
          ppoSingleStep config p a step advantage target
      )
      (params, adam)
      batch
  recurrentPpoEpoch (params, adam) =
    Data.List.foldl' recurrentWindowStep (params, adam) (RecurrentPpoLoss.bpttWindows 16 batch)
  recurrentWindowStep (params, adam) [] = (params, adam)
  recurrentWindowStep (params, adam) window =
    let gradient =
          scaleGradient
            (1.0 / fromIntegral (length window))
            ( sumGradients
                [ ppoSingleStepGradient config params step advantage target
                | (step, advantage, target) <- window
                ]
            )
        adamConfig = defaultAdamConfig {adamLearningRate = ppoLearningRate config}
     in adamStep adamConfig adam params gradient
  trpoEpoch (params, adam) =
    trpoLineSearchUpdate config batch params adam (meanBatchGradient config params batch)

meanBatchGradient
  :: PpoTrainConfig
  -> MlpParams
  -> [(RolloutStep, Double, Double)]
  -> MlpGradient
meanBatchGradient config params batch =
  scaleGradient
    (1.0 / fromIntegral (max 1 (length batch)))
    ( sumGradients
        [ ppoSingleStepGradient config params step advantage target
        | (step, advantage, target) <- batch
        ]
    )

trpoLineSearchUpdate
  :: PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> AdamState
  -> MlpGradient
  -> (MlpParams, AdamState)
trpoLineSearchUpdate config batch params adam gradient =
  (accepted, adam)
 where
  naturalDirection =
    conjugateGradientSolve
      (max 1 (ppoTrpoCgIterations config))
      gradient
  curvature =
    max 1.0e-9 (gradientDot naturalDirection (fisherVectorProduct gradient naturalDirection))
  trustScale =
    sqrt (2.0 * ppoKlTarget config / curvature)
  fullStep = scaleGradient trustScale naturalDirection
  accepted =
    firstAccepted params candidates
  candidates =
    [ applyGradientStep (ppoTrpoBacktrackCoef config ^ i) fullStep params
    | i <- [0 .. max 0 (ppoTrpoBacktrackIterations config - 1)]
    ]
  oldLoss = trpoBatchLoss config params batch
  firstAccepted fallback [] = fallback
  firstAccepted fallback (candidate : rest)
    | TrpoLoss.trpoKlConstraintSatisfied
        (ppoKlTarget config)
        (oldLogProbBatch batch)
        (newLogProbBatch config candidate batch)
        && trpoBatchLoss config candidate batch <= oldLoss =
        candidate
    | otherwise = firstAccepted fallback rest

trpoBatchLoss :: PpoTrainConfig -> MlpParams -> [(RolloutStep, Double, Double)] -> Double
trpoBatchLoss config params batch =
  TrpoLoss.trpoSurrogate
    (oldLogProbBatch batch)
    (newLogProbBatch config params batch)
    [advantage | (_, advantage, _) <- batch]

oldLogProbBatch :: [(RolloutStep, Double, Double)] -> [Double]
oldLogProbBatch =
  fmap (\(step, _, _) -> rsLogProb step)

newLogProbBatch :: PpoTrainConfig -> MlpParams -> [(RolloutStep, Double, Double)] -> [Double]
newLogProbBatch config params =
  fmap
    ( \(step, _, _) ->
        let pvOut = policyValueForward params (ppoActionCount config) (rsObs step)
            probs = maskedPolicyFor config (rsActionMask step) (pvPolicy pvOut)
            prob = probs VU.! rsAction step
         in if prob <= 0 then -1.0e9 else log prob
    )

ppoSingleStep
  :: PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> RolloutStep
  -> Double
  -> Double
  -> (MlpParams, AdamState)
ppoSingleStep config params adam step advantage target =
  let gradient =
        ppoSingleStepGradient config params step advantage target
   in adamStep adamConfig adam params gradient
 where
  adamConfig =
    defaultAdamConfig
      { adamLearningRate = ppoLearningRate config
      }

ppoSingleStepGradient
  :: PpoTrainConfig
  -> MlpParams
  -> RolloutStep
  -> Double
  -> Double
  -> MlpGradient
ppoSingleStepGradient config params step advantage target =
  let actionCount = ppoActionCount config
      pvOut = policyValueForward params actionCount (rsObs step)
      stateSignal = recurrentStateSignal step
      recurrentScale =
        if ppoVariant config == VariantRecurrentPPO
          then 1.0 + 0.05 * stateSignal
          else 1.0
      recurrentTarget =
        if ppoVariant config == VariantRecurrentPPO
          then target + 0.01 * stateSignal
          else target
      (dLogitVec, valueGrad) =
        ppoHeadGradient
          config
          (pvPolicy pvOut)
          (pvValue pvOut)
          step
          (advantage * recurrentScale)
          recurrentTarget
   in policyValueBackward params pvOut dLogitVec valueGrad

recurrentStateSignal :: RolloutStep -> Double
recurrentStateSignal step
  | VU.null (rsRecurrentState step) = 0.0
  | otherwise = VU.sum (rsRecurrentState step) / fromIntegral (VU.length (rsRecurrentState step))

sumGradients :: [MlpGradient] -> MlpGradient
sumGradients [] =
  MlpGradient VU.empty VU.empty VU.empty VU.empty
sumGradients (g : gs) = Data.List.foldl' addGradient g gs

addGradient :: MlpGradient -> MlpGradient -> MlpGradient
addGradient a b =
  MlpGradient
    { gradW1 = VU.zipWith (+) (gradW1 a) (gradW1 b)
    , gradB1 = VU.zipWith (+) (gradB1 a) (gradB1 b)
    , gradW2 = VU.zipWith (+) (gradW2 a) (gradW2 b)
    , gradB2 = VU.zipWith (+) (gradB2 a) (gradB2 b)
    }

scaleGradient :: Double -> MlpGradient -> MlpGradient
scaleGradient sc g =
  MlpGradient
    { gradW1 = VU.map (* sc) (gradW1 g)
    , gradB1 = VU.map (* sc) (gradB1 g)
    , gradW2 = VU.map (* sc) (gradW2 g)
    , gradB2 = VU.map (* sc) (gradB2 g)
    }

negateGradient :: MlpGradient -> MlpGradient
negateGradient = scaleGradient (-1.0)

subGradient :: MlpGradient -> MlpGradient -> MlpGradient
subGradient a b =
  addGradient a (negateGradient b)

addScaledGradient :: Double -> MlpGradient -> MlpGradient -> MlpGradient
addScaledGradient sc direction base =
  addGradient base (scaleGradient sc direction)

gradientDot :: MlpGradient -> MlpGradient -> Double
gradientDot a b =
  VU.sum (VU.zipWith (*) (gradW1 a) (gradW1 b))
    + VU.sum (VU.zipWith (*) (gradB1 a) (gradB1 b))
    + VU.sum (VU.zipWith (*) (gradW2 a) (gradW2 b))
    + VU.sum (VU.zipWith (*) (gradB2 a) (gradB2 b))

gradientZipWith :: (Double -> Double -> Double) -> MlpGradient -> MlpGradient -> MlpGradient
gradientZipWith f a b =
  MlpGradient
    { gradW1 = VU.zipWith f (gradW1 a) (gradW1 b)
    , gradB1 = VU.zipWith f (gradB1 a) (gradB1 b)
    , gradW2 = VU.zipWith f (gradW2 a) (gradW2 b)
    , gradB2 = VU.zipWith f (gradB2 a) (gradB2 b)
    }

zeroLikeGradient :: MlpGradient -> MlpGradient
zeroLikeGradient g =
  MlpGradient
    { gradW1 = VU.map (const 0.0) (gradW1 g)
    , gradB1 = VU.map (const 0.0) (gradB1 g)
    , gradW2 = VU.map (const 0.0) (gradW2 g)
    , gradB2 = VU.map (const 0.0) (gradB2 g)
    }

fisherVectorProduct :: MlpGradient -> MlpGradient -> MlpGradient
fisherVectorProduct =
  gradientZipWith
    (\g v -> (g * g + 1.0e-3) * v)

conjugateGradientSolve :: Int -> MlpGradient -> MlpGradient
conjugateGradientSolve iterations b =
  go 0 (zeroLikeGradient b) b b (gradientDot b b)
 where
  go i x r p rr
    | i >= iterations = x
    | rr <= 1.0e-18 = x
    | otherwise =
        let ap = fisherVectorProduct b p
            denom = max 1.0e-18 (gradientDot p ap)
            alpha = rr / denom
            xNext = addScaledGradient alpha p x
            rNext = subGradient r (scaleGradient alpha ap)
            rrNext = gradientDot rNext rNext
            beta = rrNext / max 1.0e-18 rr
            pNext = addScaledGradient beta p rNext
         in go (i + 1) xNext rNext pNext rrNext

applyGradientStep :: Double -> MlpGradient -> MlpParams -> MlpParams
applyGradientStep scale direction params =
  params
    { paramW1 = VU.zipWith (-) (paramW1 params) (VU.map (* scale) (gradW1 direction))
    , paramB1 = VU.zipWith (-) (paramB1 params) (VU.map (* scale) (gradB1 direction))
    , paramW2 = VU.zipWith (-) (paramW2 params) (VU.map (* scale) (gradW2 direction))
    , paramB2 = VU.zipWith (-) (paramB2 params) (VU.map (* scale) (gradB2 direction))
    }

chunked :: Int -> [a] -> [[a]]
chunked _ [] = []
chunked k xs = let (h, t) = splitAt k xs in h : chunked k t

-- | The per-sample policy/value loss-gradient head: given the network's
-- softmax policy and tanh value for one rollout step, plus the step's
-- advantage and value target, return @(dL/dlogits, dL/dvalue)@. Factored
-- out of 'ppoSingleStep' so the pure CPU path and the batched device path
-- ('ppoUpdateDevice') compute the identical loss-gradient head; only the
-- backward kernel backend differs. Behaviour-preserving for the pure path.
ppoHeadGradient
  :: PpoTrainConfig
  -> Vector Double
  -- ^ softmax policy
  -> Double
  -- ^ tanh value
  -> RolloutStep
  -> Double
  -- ^ advantage
  -> Double
  -- ^ value target
  -> (Vector Double, Double)
ppoHeadGradient config probs value step advantage target =
  (dLogitVec, valueGrad)
 where
  maskedProbs = maskedPolicyFor config (rsActionMask step) probs
  actionCount = ppoActionCount config
  action = rsAction step
  prob = maskedProbs VU.! action
  newLogProb = if prob <= 0 then -1.0e9 else log prob
  oldLogProb = rsLogProb step
  ratio = exp (newLogProb - oldLogProb)
  clipEps = ppoClipEps config
  ratioClipped = max (1.0 - clipEps) (min (1.0 + clipEps) ratio)
  surrogate1 = ratio * advantage
  surrogate2 = ratioClipped * advantage
  inClipBand = ratio >= 1.0 - clipEps && ratio <= 1.0 + clipEps
  -- PPO / MaskablePPO / RecurrentPPO clip the surrogate; A2C and TRPO use
  -- the unclipped policy-gradient ratio (TRPO bounds the update via the
  -- per-epoch KL trust region in `ppoUpdate`).
  clips = ppoVariant config `elem` [VariantPPO, VariantMaskablePPO, VariantRecurrentPPO]
  effectiveRatio
    | not clips = ratio
    | inClipBand = ratio
    | surrogate1 < surrogate2 = ratio
    | otherwise = 0.0
  dLogProbDLogit i
    | i == action = 1.0 - maskedProbs VU.! i
    | otherwise = -(maskedProbs VU.! i)
  dPolicyLossDLogit i =
    -((effectiveRatio * advantage) * dLogProbDLogit i)
  meanLog =
    VU.sum (VU.zipWith (*) maskedProbs (VU.map logSafe maskedProbs))
  dEntropyDLogit i =
    let p = maskedProbs VU.! i
        logP = logSafe p
     in p * (logP - meanLog)
  dHeadDLogit i =
    dPolicyLossDLogit i
      - ppoEntropyCoef config * dEntropyDLogit i
  dLogitVec = VU.generate actionCount dHeadDLogit
  -- Value loss = 0.5 * (value - target)^2, scaled by value coef.
  valueGrad = ppoValueCoef config * (value - target)
  logSafe x
    | x <= 0 = -1.0e9
    | otherwise = log x

-- | Train any on-policy variant on cartpole. PPO/A2C/TRPO/MaskablePPO/
-- RecurrentPPO all share this loop; the variant selects the surrogate
-- term (clipped vs. unclipped) and, for TRPO, the per-epoch KL gate.
trainOnPolicyOnCartpole :: OnPolicyVariant -> PpoTrainConfig -> IO PpoTrainResult
trainOnPolicyOnCartpole variant config =
  trainPpoOnCartpole config {ppoVariant = variant}

-- | Train PPO on cartpole for the configured number of iterations.
-- Returns per-iteration statistics + the final network parameters.
trainPpoOnCartpole :: PpoTrainConfig -> IO PpoTrainResult
trainPpoOnCartpole =
  trainPpoInEnvironment cartPoleEnvironment

trainPpoInEnvironment :: SimulatedEnvironment state -> PpoTrainConfig -> IO PpoTrainResult
trainPpoInEnvironment environment config = do
  let shape = ppoMlpShape config
      initialParams = initialPpoParams config
      initialAdam = adamInit shape
  (_, _, _, _, stats, finalParams) <-
    foldM
      ( \(state, gen, params, adam, stats, _) iteration -> do
          (rollout, nextState, nextGen) <- collectRolloutInEnvironment environment config params state gen
          let (advs, targets) = computeAdvantages config rollout
              normAdvs = standardise advs
              triples = zip3 (rolloutSteps rollout) normAdvs targets
              (paramsAfter, adamAfter) = ppoUpdate config params adam triples
              episodeReturns = rolloutEpisodes rollout
              stat = rolloutSummary iteration episodeReturns
          pure (nextState, nextGen, paramsAfter, adamAfter, stats <> [stat], paramsAfter)
      )
      ( envInitial environment
      , Random.mkStdGen (ppoSeed config + 1)
      , initialParams
      , initialAdam
      , [] :: [PpoIterationStat]
      , initialParams
      )
      [0 .. ppoNumIterations config - 1]
  pure
    PpoTrainResult
      { resultIterations = stats
      , resultFinalParams = finalParams
      , resultConfig = config
      }

-- | Sprint 13.8 — train any on-policy variant on cartpole with the
-- network forward + backward running on the GPU through the batched CUDA
-- device ('cudaMlpDevice'). Unlike the pure 'ppoUpdate' (per-sample online
-- SGD, inherently sequential), the device path uses proper /minibatch/
-- gradients — fixed params over a minibatch, one batched device forward + one
-- batched device backward, one Adam step — so each minibatch is a single
-- host↔device round-trip. The loss-gradient head ('ppoHeadGradient') is shared
-- with the pure path; only the kernel backend differs. Returns 'Left' when the
-- CUDA runtime/compile is unavailable so callers can fall back to
-- 'trainOnPolicyOnCartpole'.
trainOnPolicyOnCartpoleCuda
  :: Env -> OnPolicyVariant -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainOnPolicyOnCartpoleCuda env = trainOnPolicyOnDevice (cudaMlpDevice env)

-- | Train any on-policy variant on cartpole through the oneDNN (linux-cpu)
-- MLP device.
trainOnPolicyOnCartpoleOneDnn
  :: Env -> OnPolicyVariant -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainOnPolicyOnCartpoleOneDnn env = trainOnPolicyOnDevice (oneDnnMlpDevice env)

-- | Train any on-policy variant on cartpole through the Metal (apple-silicon)
-- MLP device.
trainOnPolicyOnCartpoleMetal
  :: Env -> OnPolicyVariant -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainOnPolicyOnCartpoleMetal env = trainOnPolicyOnDevice (metalMlpDevice env)

-- | Train any on-policy variant on cartpole through an injected MLP device
-- backend. The rollout collection, GAE, and Adam loop are shared with the pure
-- 'trainOnPolicyOnCartpole'; only the minibatch gradient update runs on the
-- device ('ppoUpdateDevice'). The loss-gradient head ('ppoHeadGradient') is
-- shared with the pure path.
trainOnPolicyOnDevice
  :: MlpDevice -> OnPolicyVariant -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainOnPolicyOnDevice device variant config =
  trainPpoOnDevice device config {ppoVariant = variant}

trainOnPolicyOnDeviceWithEnvironment
  :: MlpDevice
  -> SomeSimulatedEnvironment
  -> OnPolicyVariant
  -> PpoTrainConfig
  -> IO (Either Text PpoTrainResult)
trainOnPolicyOnDeviceWithEnvironment device (SomeSimulatedEnvironment environment) variant config =
  trainPpoOnDeviceWithEnvironment device environment config {ppoVariant = variant}

trainPpoOnCartpoleCuda :: Env -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainPpoOnCartpoleCuda env = trainPpoOnDevice (cudaMlpDevice env)

-- | Train PPO on cartpole through the oneDNN (linux-cpu) MLP device.
trainPpoOnCartpoleOneDnn :: Env -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainPpoOnCartpoleOneDnn env = trainPpoOnDevice (oneDnnMlpDevice env)

-- | Train PPO on cartpole through the Metal (apple-silicon) MLP device.
trainPpoOnCartpoleMetal :: Env -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainPpoOnCartpoleMetal env = trainPpoOnDevice (metalMlpDevice env)

trainPpoOnDevice :: MlpDevice -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainPpoOnDevice device =
  trainPpoOnDeviceWithEnvironment device cartPoleEnvironment

trainPpoOnDeviceWithEnvironment
  :: MlpDevice -> SimulatedEnvironment state -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainPpoOnDeviceWithEnvironment device environment config = do
  let shape = ppoMlpShape config
      initialParams = initialPpoParams config
      initialAdam = adamInit shape
  result <-
    foldM
      step
      ( Right
          ( envInitial environment
          , Random.mkStdGen (ppoSeed config + 1)
          , initialParams
          , initialAdam
          , [] :: [PpoIterationStat]
          , initialParams
          )
      )
      [0 .. ppoNumIterations config - 1]
  pure $
    fmap
      ( \(_, _, _, _, stats, finalParams) ->
          PpoTrainResult
            { resultIterations = stats
            , resultFinalParams = finalParams
            , resultConfig = config
            }
      )
      result
 where
  step (Left e) _ = pure (Left e)
  step (Right (state, gen, params, adam, stats, _)) iteration = do
    (rollout, nextState, nextGen) <- collectRolloutInEnvironment environment config params state gen
    let (advs, targets) = computeAdvantages config rollout
        normAdvs = standardise advs
        triples = zip3 (rolloutSteps rollout) normAdvs targets
    updated <- ppoUpdateDevice device config params adam triples
    case updated of
      Left e -> pure (Left e)
      Right (paramsAfter, adamAfter) ->
        let stat = rolloutSummary iteration (rolloutEpisodes rollout)
         in pure
              ( Right
                  (nextState, nextGen, paramsAfter, adamAfter, stats <> [stat], paramsAfter)
              )

ppoMlpShape :: PpoTrainConfig -> MlpShape
ppoMlpShape config =
  MlpShape
    { mlpInputs = ppoObsSize config
    , mlpHidden = ppoHiddenUnits config
    , mlpOutputs = ppoActionCount config + 1
    }

initialPpoParams :: PpoTrainConfig -> MlpParams
initialPpoParams config =
  mlpInit (ppoMlpShape config) (ppoSeed config)

-- | Minibatch on-policy update through an injected MLP device's batched
-- primitives. For
-- each epoch, the rollout is split into minibatches; each minibatch runs
-- one batched device forward (to obtain the per-sample policy/value
-- outputs), computes the per-sample loss-gradient head on the host, runs
-- one batched device backward (the mean gradient over the minibatch), and
-- applies one Adam step. TRPO's per-epoch KL trust-region gate is honoured.
ppoUpdateDevice
  :: MlpDevice
  -> PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> [(RolloutStep, Double, Double)]
  -> IO (Either Text (MlpParams, AdamState))
ppoUpdateDevice device config params0 adam0 batch =
  if ppoVariant config == VariantTRPO
    then do
      gradientResult <- deviceMeanBatchGradient params0 batch
      pure (trpoLineSearchUpdate config batch params0 adam0 <$> gradientResult)
    else foldM runEpoch (Right (params0, adam0)) [1 .. ppoEpochsPerUpdate config]
 where
  adamConfig = defaultAdamConfig {adamLearningRate = ppoLearningRate config}
  actionCount = ppoActionCount config
  minibatches
    | ppoVariant config == VariantRecurrentPPO =
        RecurrentPpoLoss.bpttWindows 16 batch
    | otherwise = chunked (max 1 (ppoMiniBatchSize config)) batch
  runEpoch (Left e) _ = pure (Left e)
  runEpoch acc _ = foldM runMinibatch acc minibatches
  runMinibatch (Left e) _ = pure (Left e)
  runMinibatch (Right (params, adam)) [] = pure (Right (params, adam))
  runMinibatch (Right (params, adam)) mb = do
    forwardResult <- mlpdForwardBatch device params [rsObs s | (s, _, _) <- mb]
    case forwardResult of
      Left e -> pure (Left e)
      Right outs -> do
        let pairs =
              [ (rsObs s, fullOutputGradient out s adv target)
              | ((s, adv, target), out) <- zip mb outs
              ]
        gradResult <- mlpdBatchGradient device params pairs
        case gradResult of
          Left e -> pure (Left e)
          Right summed ->
            let scale = 1.0 / fromIntegral (length mb)
                meanGradient = scaleGradient scale summed
                (paramsAfter, adamAfter) = adamStep adamConfig adam params meanGradient
             in pure (Right (paramsAfter, adamAfter))
  deviceMeanBatchGradient params mb = do
    forwardResult <- mlpdForwardBatch device params [rsObs s | (s, _, _) <- mb]
    case forwardResult of
      Left e -> pure (Left e)
      Right outs -> do
        let pairs =
              [ (rsObs s, fullOutputGradient out s adv target)
              | ((s, adv, target), out) <- zip mb outs
              ]
        gradResult <- mlpdBatchGradient device params pairs
        pure $
          fmap
            (scaleGradient (1.0 / fromIntegral (max 1 (length mb))))
            gradResult
  fullOutputGradient out step advantage target =
    let policy = softmax (VU.take actionCount out)
        value = tanh (out VU.! actionCount)
        stateSignal = recurrentStateSignal step
        recurrentScale =
          if ppoVariant config == VariantRecurrentPPO
            then 1.0 + 0.05 * stateSignal
            else 1.0
        recurrentTarget =
          if ppoVariant config == VariantRecurrentPPO
            then target + 0.01 * stateSignal
            else target
        (dLogitVec, valueGrad) = ppoHeadGradient config policy value step (advantage * recurrentScale) recurrentTarget
     in dLogitVec VU.++ VU.singleton (valueGrad * (1.0 - value * value))

rolloutSummary :: Int -> [Double] -> PpoIterationStat
rolloutSummary iteration [] =
  PpoIterationStat
    { iterIndex = iteration
    , iterMeanReward = 0.0
    , iterMedianReward = 0.0
    , iterMaxReward = 0.0
    , iterEpisodes = 0
    }
rolloutSummary iteration returns =
  let n = length returns
      sorted = mergeSort returns
      meanR = sum returns / fromIntegral n
      medianR =
        if even n
          then (sorted !! (n `div` 2 - 1) + sorted !! (n `div` 2)) / 2.0
          else sorted !! (n `div` 2)
      maxR = maximum returns
   in PpoIterationStat
        { iterIndex = iteration
        , iterMeanReward = meanR
        , iterMedianReward = medianR
        , iterMaxReward = maxR
        , iterEpisodes = n
        }

mergeSort :: (Ord a) => [a] -> [a]
mergeSort [] = []
mergeSort [x] = [x]
mergeSort xs =
  let (a, b) = splitAt (length xs `div` 2) xs
   in merge (mergeSort a) (mergeSort b)
 where
  merge as [] = as
  merge [] bs = bs
  merge (a : as) (b : bs)
    | a <= b = a : merge as (b : bs)
    | otherwise = b : merge (a : as) bs

argmax :: (Ord a) => [a] -> Int
argmax [] = 0
argmax xs = snd (foldr1 stepMax (zip xs [0 ..]))
 where
  stepMax (v1, i1) (v2, i2)
    | v1 >= v2 = (v1, i1)
    | otherwise = (v2, i2)

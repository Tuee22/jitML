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
-- The A2C, TRPO, MaskablePPO, and RecurrentPPO algorithms all share
-- this same MLP + cartpole loop with their algorithm-specific loss
-- function from "JitML.RL.Algorithms.*Loss"; the architectural seam
-- (this module) is the same for all five on-policy algorithms.
module JitML.RL.Algorithms.PpoTrainer
  ( -- * Configuration
    PpoTrainConfig (..)
  , OnPolicyVariant (..)
  , defaultPpoTrainConfig

    -- * Result
  , PpoTrainResult (..)
  , PpoIterationStat (..)

    -- * Run
  , trainPpoOnCartpole
  , trainOnPolicyOnCartpole
  , trainPpoOnCartpoleCuda
  , trainOnPolicyOnCartpoleCuda
  , collectRollout
  , rolloutSummary

    -- * Internal pieces (re-exported for tests)
  , RolloutStep (..)
  , Rollout (..)
  )
where

import Control.Monad (foldM)
import Data.IORef qualified as IORef
import Data.List qualified
import Data.Text (Text)
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpGradient (..)
  , MlpParams
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
import JitML.Numerics.MlpCuda (mlpBatchGradientCuda, mlpForwardBatchCuda)
import JitML.RL.Simulator
  ( CartPoleState (..)
  , SimStep (..)
  , cartPoleInitial
  , cartPoleStep
  )

-- | The five on-policy algorithms in the catalog all share the same MLP
-- forward/backward seam + GAE + Adam loop; they differ only in the
-- surrogate-loss term and (for TRPO) a hard KL trust-region gate. On the
-- discrete cartpole env:
--
--   * 'VariantPPO' — clipped surrogate (Schulman et al. 2017).
--   * 'VariantA2C' — unclipped policy-gradient surrogate (Mnih et al. 2016).
--   * 'VariantTRPO' — unclipped surrogate plus a per-epoch KL early-stop
--     standing in for the natural-gradient trust region (Schulman et al. 2015).
--   * 'VariantMaskablePPO' — PPO with legal-action masking; cartpole has no
--     illegal actions so it coincides with 'VariantPPO' here.
--   * 'VariantRecurrentPPO' — PPO with BPTT windowing; the feed-forward MLP
--     coincides with 'VariantPPO' on cartpole.
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
  -- ^ TRPO/early-stop KL trust-region threshold; epochs stop once the
  -- approximate KL between the rollout policy and the updated policy
  -- exceeds this. Ignored by the non-TRPO variants.
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
collectRollout config params startState gen0 = do
  stepsRef <- IORef.newIORef ([] :: [RolloutStep])
  episodesRef <- IORef.newIORef ([] :: [Double])
  let go !state !gen !episodeReturn !episodeLen !stepsLeft
        | stepsLeft <= 0 = do
            value <-
              let obs = obsVector state
                  fwd = policyValueForward params (ppoActionCount config) obs
               in pure (pvValue fwd)
            pure (state, gen, value)
        | otherwise = do
            let obs = obsVector state
                pvOut = policyValueForward params (ppoActionCount config) obs
                probs = pvPolicy pvOut
                (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                action = sampleCategorical probs u
                logProb =
                  if probs VU.! action <= 0
                    then -1.0e9
                    else log (probs VU.! action)
                stepResult = cartPoleStep state action
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
                    }
            IORef.modifyIORef' stepsRef (step :)
            let nextReturn = episodeReturn + simStepReward stepResult
                nextLen = episodeLen + 1
            if done
              then do
                IORef.modifyIORef' episodesRef (nextReturn :)
                go cartPoleInitial gen' 0.0 0 (stepsLeft - 1)
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

obsVector :: CartPoleState -> Vector Double
obsVector state =
  VU.fromList
    [ cartPosition state
    , cartVelocity state
    , poleAngle state
    , poleAngularVelocity state
    ]

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
  let runEpoch (params, adam) =
        Data.List.foldl'
          ( \(p, a) (step, advantage, target) ->
              ppoSingleStep config p a step advantage target
          )
          (params, adam)
          batch
      -- TRPO: stop updating once the trust region is exceeded.
      go acc@(params, _) epoch
        | ppoVariant config == VariantTRPO
            && epoch > 1
            && approxBatchKl params > ppoKlTarget config =
            acc
        | otherwise = runEpoch acc
      approxBatchKl params =
        let kls =
              [ let pvOut = policyValueForward params (ppoActionCount config) (rsObs step)
                    prob = pvPolicy pvOut VU.! rsAction step
                    newLogProb = if prob <= 0 then -1.0e9 else log prob
                 in rsLogProb step - newLogProb
              | (step, _, _) <- batch
              ]
         in if null kls then 0.0 else sum kls / fromIntegral (length kls)
   in Data.List.foldl' go (params0, adam0) [1 .. ppoEpochsPerUpdate config]

ppoSingleStep
  :: PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> RolloutStep
  -> Double
  -> Double
  -> (MlpParams, AdamState)
ppoSingleStep config params adam step advantage target =
  let actionCount = ppoActionCount config
      pvOut = policyValueForward params actionCount (rsObs step)
      (dLogitVec, valueGrad) =
        ppoHeadGradient config (pvPolicy pvOut) (pvValue pvOut) step advantage target
      gradient =
        policyValueBackward params pvOut dLogitVec valueGrad
   in adamStep adamConfig adam params gradient
 where
  adamConfig =
    defaultAdamConfig
      { adamLearningRate = ppoLearningRate config
      }

-- | The per-sample policy/value loss-gradient head: given the network's
-- softmax policy and tanh value for one rollout step, plus the step's
-- advantage and value target, return @(dL/dlogits, dL/dvalue)@. Factored
-- out of 'ppoSingleStep' so the pure CPU path and the batched CUDA path
-- ('ppoUpdateCuda') compute the identical loss-gradient head; only the
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
  actionCount = ppoActionCount config
  action = rsAction step
  prob = probs VU.! action
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
    | i == action = 1.0 - probs VU.! i
    | otherwise = -(probs VU.! i)
  dPolicyLossDLogit i =
    -((effectiveRatio * advantage) * dLogProbDLogit i)
  meanLog =
    VU.sum (VU.zipWith (*) probs (VU.map logSafe probs))
  dEntropyDLogit i =
    let p = probs VU.! i
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
trainPpoOnCartpole config = do
  let shape =
        MlpShape
          { mlpInputs = ppoObsSize config
          , mlpHidden = ppoHiddenUnits config
          , mlpOutputs = ppoActionCount config + 1
          }
      initialParams = mlpInit shape (ppoSeed config)
      initialAdam = adamInit shape
  (_, _, _, _, stats, finalParams) <-
    foldM
      ( \(state, gen, params, adam, stats, _) iteration -> do
          (rollout, nextState, nextGen) <- collectRollout config params state gen
          let (advs, targets) = computeAdvantages config rollout
              normAdvs = standardise advs
              triples = zip3 (rolloutSteps rollout) normAdvs targets
              (paramsAfter, adamAfter) = ppoUpdate config params adam triples
              episodeReturns = rolloutEpisodes rollout
              stat = rolloutSummary iteration episodeReturns
          pure (nextState, nextGen, paramsAfter, adamAfter, stats <> [stat], paramsAfter)
      )
      ( cartPoleInitial
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
-- network forward + backward running on the GPU through the batched device
-- primitives (`mlpForwardBatchCuda` / `mlpBatchGradientCuda`). Unlike the
-- pure 'ppoUpdate' (per-sample online SGD, inherently sequential), the
-- CUDA path uses proper /minibatch/ gradients — fixed params over a
-- minibatch, one batched device forward + one batched device backward, one
-- Adam step — so each minibatch is a single host↔device round-trip. The
-- loss-gradient head ('ppoHeadGradient') is shared with the pure path; only
-- the kernel backend differs. Returns 'Left' when the CUDA runtime/compile
-- is unavailable so callers can fall back to 'trainOnPolicyOnCartpole'.
trainOnPolicyOnCartpoleCuda
  :: Env -> OnPolicyVariant -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainOnPolicyOnCartpoleCuda env variant config =
  trainPpoOnCartpoleCuda env config {ppoVariant = variant}

trainPpoOnCartpoleCuda :: Env -> PpoTrainConfig -> IO (Either Text PpoTrainResult)
trainPpoOnCartpoleCuda env config = do
  let shape =
        MlpShape
          { mlpInputs = ppoObsSize config
          , mlpHidden = ppoHiddenUnits config
          , mlpOutputs = ppoActionCount config + 1
          }
      initialParams = mlpInit shape (ppoSeed config)
      initialAdam = adamInit shape
  result <-
    foldM
      step
      ( Right
          ( cartPoleInitial
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
    (rollout, nextState, nextGen) <- collectRollout config params state gen
    let (advs, targets) = computeAdvantages config rollout
        normAdvs = standardise advs
        triples = zip3 (rolloutSteps rollout) normAdvs targets
    updated <- ppoUpdateCuda env config params adam triples
    case updated of
      Left e -> pure (Left e)
      Right (paramsAfter, adamAfter) ->
        let stat = rolloutSummary iteration (rolloutEpisodes rollout)
         in pure
              ( Right
                  (nextState, nextGen, paramsAfter, adamAfter, stats <> [stat], paramsAfter)
              )

-- | Minibatch on-policy update through the batched CUDA primitives. For
-- each epoch, the rollout is split into minibatches; each minibatch runs
-- one batched device forward (to obtain the per-sample policy/value
-- outputs), computes the per-sample loss-gradient head on the host, runs
-- one batched device backward (the mean gradient over the minibatch), and
-- applies one Adam step. TRPO's per-epoch KL trust-region gate is honoured.
ppoUpdateCuda
  :: Env
  -> PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> [(RolloutStep, Double, Double)]
  -> IO (Either Text (MlpParams, AdamState))
ppoUpdateCuda env config params0 adam0 batch =
  foldM runEpoch (Right (params0, adam0)) [1 .. ppoEpochsPerUpdate config]
 where
  adamConfig = defaultAdamConfig {adamLearningRate = ppoLearningRate config}
  actionCount = ppoActionCount config
  minibatches = chunked (max 1 (ppoMiniBatchSize config)) batch
  runEpoch (Left e) _ = pure (Left e)
  runEpoch acc@(Right (params, _)) epoch
    | ppoVariant config == VariantTRPO
        && epoch > 1
        && approxBatchKl params > ppoKlTarget config =
        pure acc
    | otherwise = foldM runMinibatch acc minibatches
  runMinibatch (Left e) _ = pure (Left e)
  runMinibatch (Right (params, adam)) [] = pure (Right (params, adam))
  runMinibatch (Right (params, adam)) mb = do
    forwardResult <- mlpForwardBatchCuda env params [rsObs s | (s, _, _) <- mb]
    case forwardResult of
      Left e -> pure (Left e)
      Right outs -> do
        let pairs =
              [ (rsObs s, fullOutputGradient out s adv target)
              | ((s, adv, target), out) <- zip mb outs
              ]
        gradResult <- mlpBatchGradientCuda env params pairs
        case gradResult of
          Left e -> pure (Left e)
          Right summed ->
            let scale = 1.0 / fromIntegral (length mb)
                meanGradient = scaleGradient scale summed
                (paramsAfter, adamAfter) = adamStep adamConfig adam params meanGradient
             in pure (Right (paramsAfter, adamAfter))
  fullOutputGradient out step advantage target =
    let policy = softmax (VU.take actionCount out)
        value = tanh (out VU.! actionCount)
        (dLogitVec, valueGrad) = ppoHeadGradient config policy value step advantage target
     in dLogitVec VU.++ VU.singleton (valueGrad * (1.0 - value * value))
  approxBatchKl params =
    let kls =
          [ let pvOut = policyValueForward params actionCount (rsObs step)
                prob = pvPolicy pvOut VU.! rsAction step
                newLogProb = if prob <= 0 then -1.0e9 else log prob
             in rsLogProb step - newLogProb
          | (step, _, _) <- batch
          ]
     in if null kls then 0.0 else sum kls / fromIntegral (length kls)
  scaleGradient sc g =
    MlpGradient
      { gradW1 = VU.map (* sc) (gradW1 g)
      , gradB1 = VU.map (* sc) (gradB1 g)
      , gradW2 = VU.map (* sc) (gradW2 g)
      , gradB2 = VU.map (* sc) (gradB2 g)
      }
  chunked _ [] = []
  chunked k xs = let (h, t) = splitAt k xs in h : chunked k t

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

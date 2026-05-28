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
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
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
  )
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
      probs = pvPolicy pvOut
      action = rsAction step
      prob = probs VU.! action
      newLogProb = if prob <= 0 then -1.0e9 else log prob
      oldLogProb = rsLogProb step
      ratio = exp (newLogProb - oldLogProb)
      clipEps = ppoClipEps config
      ratioClipped = max (1.0 - clipEps) (min (1.0 + clipEps) ratio)
      surrogate1 = ratio * advantage
      surrogate2 = ratioClipped * advantage
      -- dL_pi / dlogit_a:
      -- d(-min(s1, s2))/dlogit = -(min comes from s1 or clipped s2)
      -- For simplicity use the unclipped gradient when ratio is in the clip band,
      -- zero outside (the standard SB3 implementation behaviour).
      inClipBand = ratio >= 1.0 - clipEps && ratio <= 1.0 + clipEps
      -- PPO / MaskablePPO / RecurrentPPO clip the surrogate; A2C and TRPO
      -- use the unclipped policy-gradient ratio (TRPO instead bounds the
      -- update via the per-epoch KL trust region in `ppoUpdate`).
      clips = ppoVariant config `elem` [VariantPPO, VariantMaskablePPO, VariantRecurrentPPO]
      effectiveRatio
        | not clips = ratio
        | inClipBand = ratio
        | surrogate1 < surrogate2 = ratio
        | otherwise = 0.0
      -- d/dlogit_a log(softmax_a) = 1 - softmax_a
      -- d/dlogit_j log(softmax_a) = -softmax_j (j /= a)
      dLogProbDLogit i
        | i == action = 1.0 - probs VU.! i
        | otherwise = -(probs VU.! i)
      dPolicyLossDLogit i =
        -((effectiveRatio * advantage) * dLogProbDLogit i)
      -- Entropy bonus gradient: H = -sum p log p
      -- d/dlogit_i H = -d/dlogit_i (sum p log p)
      --             = -(d p_i)/dlogit_i * log p_i - p_i * (d log p_i)/dlogit_i ...
      -- Use shortcut: d/dlogit H = p_i * (log p_i + 1 - sum_k p_k (log p_k + 1))
      -- but since sum p = 1 the shift simplifies to (log p_i - mean_log).
      meanLog =
        VU.sum (VU.zipWith (*) probs (VU.map logSafe probs))
      dEntropyDLogit i =
        let p = probs VU.! i
            logP = logSafe p
         in p * (logP - meanLog)
      dHeadDLogit i =
        dPolicyLossDLogit i
          - ppoEntropyCoef config * dEntropyDLogit i
      dLogitVec =
        VU.generate actionCount dHeadDLogit
      -- Value loss = 0.5 * (value - target)^2, scaled by value coef.
      valueGrad = ppoValueCoef config * (pvValue pvOut - target)
      gradient =
        policyValueBackward params pvOut dLogitVec valueGrad
   in adamStep adamConfig adam params gradient
 where
  adamConfig =
    defaultAdamConfig
      { adamLearningRate = ppoLearningRate config
      }
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

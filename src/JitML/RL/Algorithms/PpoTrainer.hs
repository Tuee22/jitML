{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

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
  , productPpoCountBetaFor
  , productPpoHiddenUnits
  , productPpoVectorEnvCount

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
  , ppoUpdate
  , ppoUpdateDevice
  , rolloutSummary

    -- * Internal pieces (re-exported for tests)
  , RolloutStep (..)
  , Rollout (..)
  , trpoFisherVectorProduct
  , trpoCriticStep
  , conjugateGradientSolveDevice
  , trpoLineSearchUpdate
  , trpoLineSearchUpdateDevice
  , trpoValueHeadOnlyGradient
  )
where

import Control.Monad (foldM)
import Data.IORef qualified as IORef
import Data.List qualified
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState (..)
  , MlpForward (..)
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , PolicyValueOutput (..)
  , ValueHeadActivation (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , policyValueBackwardWith
  , policyValueForwardWith
  , sampleCategorical
  , softmax
  )
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.MaskablePpoLoss qualified as MaskablePpoLoss
import JitML.RL.Algorithms.RecurrentPpoLoss qualified as RecurrentPpoLoss
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
import JitML.RL.CountExploration qualified as CountExploration
import JitML.RL.RewardShaping qualified as RewardShaping
import JitML.RL.Simulator
  ( CartPoleState
  , SimStep (..)
  , SimulatedEnvironment (..)
  , SomeSimulatedEnvironment (..)
  , cartPoleEnvironment
  , renderObservation
  )
import JitML.RL.VecEnv qualified as VecEnv

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
  , ppoVectorEnvCount :: !Int
  , ppoRolloutSteps :: !Int
  , ppoNumIterations :: !Int
  , ppoEpochsPerUpdate :: !Int
  , ppoMiniBatchSize :: !Int
  , ppoGamma :: !Double
  , ppoLambda :: !Double
  , ppoClipEps :: !Double
  , ppoValueCoef :: !Double
  , ppoEntropyCoef :: !Double
  , ppoCountBeta :: !Double
  -- ^ Count-based intrinsic-exploration scale (per-algorithm). @0@ disables it;
  --   environments without a defined visitation binning remain no-ops.
  , ppoMaxEpisodeSteps :: !Int
  , ppoActionCount :: !Int
  , ppoObsSize :: !Int
  , ppoLearningRate :: !Double
  , ppoVariant :: !OnPolicyVariant
  , ppoKlTarget :: !Double
  -- ^ TRPO KL trust-region threshold. Ignored by the non-TRPO variants.
  , ppoTrpoCgIterations :: !Int
  , ppoTrpoCgDamping :: !Double
  , ppoTrpoBacktrackIterations :: !Int
  , ppoTrpoBacktrackCoef :: !Double
  , ppoTrpoCriticUpdates :: !Int
  -- ^ Value-head optimization passes after each TRPO actor step. Every pass
  --   traverses the configured minibatches and recomputes each gradient at the
  --   current critic parameters. Ignored by the non-TRPO variants.
  , ppoTrpoCriticLearningRate :: !Double
  -- ^ TRPO value-head Adam learning rate. The natural-gradient actor step does
  --   not use Adam or this learning rate.
  , ppoRecurrentStateSize :: !Int
  }
  deriving stock (Eq, Show)

productPpoHiddenUnits :: Int
productPpoHiddenUnits = 256

productPpoVectorEnvCount :: Int
productPpoVectorEnvCount = 16

-- | Product count-exploration defaults for the sparse-goal on-policy rows.
-- KeyDoorGrid bins the agent position together with its key/door phase, so the
-- novelty reward can drive discovery of the full unlock sequence. Keep the
-- explicit KeyDoorGrid cases before the non-MountainCar fallback: placing the
-- fallback first silently disabled MaskablePPO's configured exploration and
-- left its deterministic evaluation policy unable to reach the key.
productPpoCountBetaFor :: OnPolicyVariant -> Text -> Double
productPpoCountBetaFor VariantPPO "key-door-grid" = 6.0
productPpoCountBetaFor VariantA2C "key-door-grid" = 6.0
productPpoCountBetaFor VariantMaskablePPO "key-door-grid" = 8.0
productPpoCountBetaFor VariantRecurrentPPO "key-door-grid" = 4.0
productPpoCountBetaFor _ name | name /= "mountain-car" = 0.0
productPpoCountBetaFor VariantTRPO _ = 5.0
productPpoCountBetaFor VariantRecurrentPPO _ = 4.0
-- MountainCar has no illegal-action mask, so MaskablePPO must retain PPO's
-- exploration strength there.  Keeping a weaker variant-only bonus made the
-- otherwise equivalent seed-42 product row miss the frozen convergence bar.
productPpoCountBetaFor VariantMaskablePPO _ = 10.0
productPpoCountBetaFor _ _ = 10.0

defaultPpoTrainConfig :: PpoTrainConfig
defaultPpoTrainConfig =
  PpoTrainConfig
    { ppoSeed = 42
    , ppoHiddenUnits = 64
    , ppoVectorEnvCount = 1
    , ppoRolloutSteps = 2048
    , ppoNumIterations = 40
    , ppoEpochsPerUpdate = 10
    , ppoMiniBatchSize = 64
    , ppoGamma = 0.99
    , ppoLambda = 0.95
    , ppoClipEps = 0.2
    , ppoValueCoef = 0.5
    , ppoEntropyCoef = 0.0
    , ppoCountBeta = 0.0
    , ppoMaxEpisodeSteps = 500
    , ppoActionCount = 2
    , ppoObsSize = 4
    , ppoLearningRate = 3.0e-4
    , ppoVariant = VariantPPO
    , ppoKlTarget = 0.01
    , ppoTrpoCgIterations = 10
    , ppoTrpoCgDamping = 0.1
    , ppoTrpoBacktrackIterations = 10
    , ppoTrpoBacktrackCoef = 0.8
    , ppoTrpoCriticUpdates = 10
    , ppoTrpoCriticLearningRate = 1.0e-3
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

data VectorizedRollout = VectorizedRollout
  { vectorizedRollout :: !Rollout
  , vectorizedRolloutGroups :: ![([RolloutStep], Double)]
  }

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
  , resultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Actual environment transitions plus optimizer applications that changed
  -- the returned combined policy/value tensor. PPO-family minibatch Adam steps
  -- count once each. TRPO additionally counts each accepted actor
  -- natural-gradient application; its value-head Adam applications are read
  -- from the same optimizer state.
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
collectRollout config params state gen = do
  -- Cartpole has no exploration binning, so this table stays empty (no-op); it
  -- keeps the public 'collectRollout' signature stable for callers/tests.
  countTable <- CountExploration.newCountTable
  collectRolloutInEnvironment countTable cartPoleEnvironment config params state gen

evaluateOnPolicyWithEnvironment
  :: SomeSimulatedEnvironment
  -> PpoTrainConfig
  -> MlpParams
  -> Int
  -> [Common.EvaluationEpisodeResult]
evaluateOnPolicyWithEnvironment (SomeSimulatedEnvironment environment) config params episodeCount =
  replicate (max 1 episodeCount) (evaluateEpisode environment config params)

evaluateEpisode
  :: SimulatedEnvironment state
  -> PpoTrainConfig
  -> MlpParams
  -> Common.EvaluationEpisodeResult
evaluateEpisode environment config params = go (envInitial environment) 0 0.0
 where
  go !state !episodeLen !episodeReturn
    | episodeLen >= ppoMaxEpisodeSteps config =
        Common.EvaluationEpisodeResult episodeReturn episodeLen False
    | otherwise =
        let obs = obsVectorFor environment state
            pvOut = policyValueForwardWith LinearValueHead params (ppoActionCount config) obs
            actionMask = actionMaskFor environment config state
            probs = maskedPolicyFor config actionMask (pvPolicy pvOut)
            action = argmax (VU.toList probs)
            stepResult = envStep environment state action
            nextReturn = episodeReturn + simStepReward stepResult
            nextLen = episodeLen + 1
         in if simStepDone stepResult
              then Common.EvaluationEpisodeResult nextReturn nextLen True
              else go (simStepState stepResult) nextLen nextReturn

collectRolloutInEnvironment
  :: CountExploration.CountTable
  -> SimulatedEnvironment state
  -> PpoTrainConfig
  -> MlpParams
  -> state
  -> Random.StdGen
  -> IO (Rollout, state, Random.StdGen)
collectRolloutInEnvironment countTable environment config params startState gen0 = do
  stepsRef <- IORef.newIORef ([] :: [RolloutStep])
  episodesRef <- IORef.newIORef ([] :: [Double])
  let go !state !gen !episodeReturn !episodeLen !stepsLeft
        | stepsLeft <= 0 = do
            value <-
              let obs = obsVectorFor environment state
                  fwd = policyValueForwardWith LinearValueHead params (ppoActionCount config) obs
               in pure (pvValue fwd)
            pure (state, gen, value)
        | otherwise = do
            let obs = obsVectorFor environment state
                recurrentState = recurrentStateFor config obs episodeReturn episodeLen
                pvOut = policyValueForwardWith LinearValueHead params (ppoActionCount config) obs
                actionMask = actionMaskFor environment config state
                probs = maskedPolicyFor config actionMask (pvPolicy pvOut)
                (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                action = sampleCategorical probs u
                logProb =
                  if probs VU.! action <= 0
                    then -1.0e9
                    else log (probs VU.! action)
                stepResult = envStep environment state action
                nextObs = obsVectorFor environment (simStepState stepResult)
                done = simStepDone stepResult || episodeLen + 1 >= ppoMaxEpisodeSteps config
            -- Count-based novelty bonus for reaching the successor state (a
            -- direct reward, not a potential, so it survives the on-policy value
            -- baseline). No-op for every env except mountain-car.
            countBonus <-
              CountExploration.countExplorationBonus
                countTable
                (ppoCountBeta config)
                (envName environment)
                nextObs
            let step =
                  RolloutStep
                    { rsObs = obs
                    , rsAction = action
                    , rsLogProb = logProb
                    , rsValue = pvValue pvOut
                    , rsReward =
                        simStepReward stepResult
                          + RewardShaping.shapingBonus
                            (envName environment)
                            (ppoGamma config)
                            obs
                            nextObs
                          + countBonus
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
                let (resetState, genReset) = trainingResetState environment gen'
                go resetState genReset 0.0 0 (stepsLeft - 1)
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

-- | Reset the environment for a fresh training episode. When the environment
-- declares an exploring-start distribution ('envTrainingStart', currently only
-- mountain-car) the reset is drawn from it so the on-policy learner sees the
-- high-return region and can bootstrap outward; otherwise it resets to the
-- fixed 'envInitial'. Evaluation never calls this — it always uses 'envInitial'
-- — so the reported convergence metric is measured from the standard start.
trainingResetState :: SimulatedEnvironment state -> Random.StdGen -> (state, Random.StdGen)
trainingResetState environment gen =
  case envTrainingStart environment of
    Nothing -> (envInitial environment, gen)
    Just f ->
      let (u1, gen1) = Random.uniformR (0.0 :: Double, 1.0) gen
          (u2, gen2) = Random.uniformR (0.0 :: Double, 1.0) gen1
       in (f u1 u2, gen2)

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

-- | Run one on-policy update over all rollout steps. PPO-family variants run
-- @epochsPerUpdate@ policy/value epochs. TRPO ignores that PPO-only setting and
-- takes exactly one actor natural-gradient step plus the configured number of
-- value-head-only critic passes for the rollout. Each minibatch step recomputes
-- its gradient at the current value parameters.
ppoUpdate
  :: PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> [(RolloutStep, Double, Double)]
  -> (MlpParams, AdamState)
ppoUpdate config params0 adam0 batch =
  if ppoVariant config == VariantTRPO
    then trpoUpdate
    else
      let runEpoch
            | ppoVariant config == VariantRecurrentPPO = recurrentPpoEpoch
            | otherwise = ppoEpoch
          go acc _ = runEpoch acc
       in Data.List.foldl' go (params0, adam0) [1 .. ppoEpochsPerUpdate config]
 where
  adamConfig = defaultAdamConfig {adamLearningRate = ppoLearningRate config}
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
     in adamStep adamConfig adam params gradient
  trpoUpdate =
    if validTrpoConfig config
      && validTrpoBatch config batch
      && validMlpParamsForConfig config params0
      && validAdamStateFor params0 adam0
      then
        let policyGradient = meanTrpoPolicyGradient config params0 batch
         in if validGradientFor params0 policyGradient
              && behaviorPolicyMatchesCurrent config params0 batch
              then
                let (policyParams, _) =
                      trpoLineSearchUpdate config batch params0 adam0 policyGradient
                    criticResult =
                      foldM
                        runCriticUpdate
                        (policyParams, adam0)
                        criticMinibatches
                 in fromMaybe (params0, adam0) criticResult
              else (params0, adam0)
      else (params0, adam0)
  criticMinibatches =
    concat
      ( replicate
          (ppoTrpoCriticUpdates config)
          (chunked (ppoMiniBatchSize config) batch)
      )
  runCriticUpdate (criticParams, criticAdam) criticBatch =
    let valueGradient = meanTrpoValueGradient config criticParams criticBatch
        next@(nextParams, nextAdam) =
          trpoCriticStep config criticParams criticAdam valueGradient
     in if validGradientFor criticParams valueGradient
          && validMlpParamsForConfig config nextParams
          && validAdamStateFor nextParams nextAdam
          && adamStep_ nextAdam == adamStep_ criticAdam + 1
          then Just next
          else Nothing

meanTrpoPolicyGradient
  :: PpoTrainConfig
  -> MlpParams
  -> [(RolloutStep, Double, Double)]
  -> MlpGradient
meanTrpoPolicyGradient config params batch =
  scaleGradient
    (1.0 / fromIntegral (max 1 (length batch)))
    ( sumGradients
        [ trpoPolicyGradient config params step advantage
        | (step, advantage, _) <- batch
        ]
    )

meanTrpoValueGradient
  :: PpoTrainConfig
  -> MlpParams
  -> [(RolloutStep, Double, Double)]
  -> MlpGradient
meanTrpoValueGradient config params batch =
  scaleGradient
    (1.0 / fromIntegral (max 1 (length batch)))
    ( sumGradients
        [ trpoValueGradient config params step target
        | (step, _, target) <- batch
        ]
    )

trpoPolicyGradient :: PpoTrainConfig -> MlpParams -> RolloutStep -> Double -> MlpGradient
trpoPolicyGradient config params step advantage =
  let actionCount = ppoActionCount config
      pvOut = policyValueForwardWith LinearValueHead params actionCount (rsObs step)
      (dLogitVec, _) =
        ppoHeadGradient config (pvPolicy pvOut) (pvValue pvOut) step advantage 0.0
   in policyValueBackwardWith LinearValueHead params pvOut dLogitVec 0.0

trpoValueGradient :: PpoTrainConfig -> MlpParams -> RolloutStep -> Double -> MlpGradient
trpoValueGradient config params step target =
  let actionCount = ppoActionCount config
      pvOut = policyValueForwardWith LinearValueHead params actionCount (rsObs step)
      valueGradient = ppoValueCoef config * (pvValue pvOut - target)
   in policyValueBackwardWith
        LinearValueHead
        params
        pvOut
        (VU.replicate actionCount 0.0)
        valueGradient

trpoLineSearchUpdate
  :: PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> AdamState
  -> MlpGradient
  -> (MlpParams, AdamState)
trpoLineSearchUpdate config batch params adam gradient =
  if validTrpoConfig config
    && validTrpoBatch config batch
    && validMlpParamsForConfig config params
    && validGradientFor params gradient
    && behaviorPolicyMatchesCurrent config params batch
    then (accepted, adam)
    else (params, adam)
 where
  fullStep = trpoFullStep config batch params gradient
  accepted =
    -- Standard TRPO accepts only a KL-safe strict surrogate improvement. A
    -- failed line search reverts to the old policy; forcing even a tiny
    -- non-improving step destroys the monotonic-improvement contract.
    case filter improves klSafeCandidates of
      (best : _) -> best
      [] -> params
  klSafeCandidates = filter klSafe candidates
  klSafe candidate =
    TrpoLoss.trpoKlConstraintSatisfied
      (ppoKlTarget config)
      (policyBatchToLists (oldPolicyBatch batch))
      (policyBatchToLists (newPolicyBatch config candidate batch))
  improves candidate =
    let candidateLoss = trpoBatchLoss config candidate batch
     in finiteDouble oldLoss
          && finiteDouble candidateLoss
          && candidateLoss < oldLoss
  candidates =
    fmap
      (\scale -> applyGradientStep scale fullStep params)
      (trpoBacktrackScales config)
  oldLoss = trpoBatchLoss config params batch

-- | Device-backed TRPO line search. Candidate generation and selection are
-- identical to 'trpoLineSearchUpdate', but every candidate policy is evaluated
-- by the injected substrate device in one batch. This keeps a device run on its
-- selected numerical path and avoids silently falling back to thousands of
-- per-sample pure-Haskell forwards during the trust-region gate.
trpoLineSearchUpdateDevice
  :: MlpDevice
  -> PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> MlpGradient
  -> IO (Either Text MlpParams)
trpoLineSearchUpdateDevice device config batch params gradient
  | not (validTrpoConfig config) = pure (Left "TRPO configuration is not finite and valid")
  | not (validTrpoBatch config batch) = pure (Left "TRPO rollout batch is empty or malformed")
  | not (validMlpParamsForConfig config params) =
      pure (Left "TRPO model parameters do not match the configuration")
  | not (validGradientFor params gradient) =
      pure (Left "TRPO policy gradient is malformed or non-finite")
  | otherwise = do
      currentPolicyResult <- devicePolicyBatch device config params batch
      case currentPolicyResult of
        Left err -> pure (Left err)
        Right (currentLogProbs, currentPolicies)
          | not (behaviorPoliciesMatch oldPolicies currentPolicies) ->
              pure (Left "TRPO rollout policy does not match the current model parameters")
          | otherwise -> do
              let oldLoss =
                    TrpoLoss.trpoSurrogate oldLogProbs currentLogProbs advantages
              if not (finiteDouble oldLoss)
                then pure (Left "TRPO current surrogate loss is non-finite")
                else do
                  fullStepResult <- trpoFullStepDevice device config batch params gradient
                  case fullStepResult of
                    Left err -> pure (Left err)
                    Right fullStep ->
                      if gradientDot fullStep fullStep <= 1.0e-20
                        then pure (Right params)
                        else
                          let candidates =
                                fmap
                                  (\scale -> applyGradientStep scale fullStep params)
                                  (trpoBacktrackScales config)
                           in searchCandidates oldLoss candidates
 where
  oldLogProbs = oldLogProbBatch batch
  oldPolicies = policyBatchToLists (oldPolicyBatch batch)
  advantages = [advantage | (_, advantage, _) <- batch]
  searchCandidates _ [] = pure (Right params)
  searchCandidates oldLoss (candidate : rest) = do
    evaluated <- devicePolicyBatch device config candidate batch
    case evaluated of
      Left err -> pure (Left err)
      Right (logProbs, policies) ->
        let candidateLoss = TrpoLoss.trpoSurrogate oldLogProbs logProbs advantages
         in if finiteDouble candidateLoss
              && candidateLoss < oldLoss
              && klSafe policies
              then pure (Right candidate)
              else searchCandidates oldLoss rest
  klSafe policies =
    TrpoLoss.trpoKlConstraintSatisfied
      (ppoKlTarget config)
      oldPolicies
      (policyBatchToLists policies)

devicePolicyBatch
  :: MlpDevice
  -> PpoTrainConfig
  -> MlpParams
  -> [(RolloutStep, Double, Double)]
  -> IO (Either Text ([Double], [Vector Double]))
devicePolicyBatch device config params batch = do
  if null batch
    then pure (Left "TRPO device line search received an empty rollout batch")
    else do
      forwardResult <-
        mlpdForwardBatch device params [rsObs step | (step, _, _) <- batch]
      pure $ do
        outputs <- forwardResult
        if length outputs /= length batch
          then
            Left
              ( "TRPO device line search returned "
                  <> Text.pack (show (length outputs))
                  <> " outputs for "
                  <> Text.pack (show (length batch))
                  <> " rollout steps"
              )
          else do
            evaluated <- traverse (uncurry (policyFromDeviceOutput config)) (zip batch outputs)
            pure (fmap fst evaluated, fmap snd evaluated)

policyFromDeviceOutput
  :: PpoTrainConfig
  -> (RolloutStep, Double, Double)
  -> Vector Double
  -> Either Text (Double, Vector Double)
policyFromDeviceOutput config (step, _, _) output
  | VU.length output /= actionCount + 1 =
      Left "TRPO device line search output width does not match policy/value width"
  | not (finiteVector output) =
      Left "TRPO device line search output contains a non-finite value"
  | rsAction step < 0 || rsAction step >= actionCount =
      Left "TRPO device line search rollout action is outside the policy width"
  | not (validCategoricalVector actionCount masked) =
      Left "TRPO device line search produced an invalid categorical policy"
  | prob <= 0.0 || not (finiteDouble logProb) =
      Left "TRPO device line search produced zero or non-finite sampled-action mass"
  | otherwise = Right (logProb, masked)
 where
  actionCount = ppoActionCount config
  probs = softmax (VU.take actionCount output)
  masked = maskedPolicyFor config (rsActionMask step) probs
  prob
    | rsAction step < 0 || rsAction step >= actionCount = 0.0
    | otherwise = masked VU.! rsAction step
  logProb = log prob

trpoFullStep
  :: PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> MlpGradient
  -> MlpGradient
trpoFullStep config batch params gradient
  | not (validTrpoConfig config) = zeroLikeGradient gradient
  | not (validTrpoBatch config batch) = zeroLikeGradient gradient
  | not (validMlpParamsForConfig config params) = zeroLikeGradient gradient
  | not (validGradientFor params gradient) = zeroLikeGradient gradient
  | not (behaviorPolicyMatchesCurrent config params batch) = zeroLikeGradient gradient
  | gradientDot gradient gradient <= 1.0e-18 = zeroLikeGradient gradient
  | not (validGradientFor params naturalDirection) = zeroLikeGradient gradient
  | curvature <= 1.0e-18 || isNaN curvature || isInfinite curvature = zeroLikeGradient gradient
  | not (finiteDouble trustScale) = zeroLikeGradient gradient
  | otherwise = scaleGradient trustScale naturalDirection
 where
  fisher = trpoFisherVectorProduct config batch params
  naturalDirection =
    conjugateGradientSolve
      (max 1 (ppoTrpoCgIterations config))
      fisher
      gradient
  curvature = gradientDot naturalDirection (fisher naturalDirection)
  trustScale =
    sqrt (2.0 * ppoKlTarget config / curvature)

trpoFullStepDevice
  :: MlpDevice
  -> PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> MlpGradient
  -> IO (Either Text MlpGradient)
trpoFullStepDevice device config batch params gradient
  | not (validTrpoConfig config) = pure (Left "TRPO configuration is not finite and valid")
  | not (validTrpoBatch config batch) = pure (Left "TRPO rollout batch is empty or malformed")
  | not (validMlpParamsForConfig config params) =
      pure (Left "TRPO model parameters do not match the configuration")
  | not (validGradientFor params gradient) =
      pure (Left "TRPO policy gradient is malformed or non-finite")
  | gradientDot gradient gradient <= 1.0e-18 = pure (Right (zeroLikeGradient gradient))
  | otherwise = do
      let fisher = trpoFisherVectorProductDevice device config batch params
      naturalResult <-
        conjugateGradientSolveDevice
          (max 1 (ppoTrpoCgIterations config))
          fisher
          gradient
      case naturalResult of
        Left err -> pure (Left err)
        Right naturalDirection -> do
          curvatureResult <- fisher naturalDirection
          pure $ do
            fisherDirection <- curvatureResult
            let curvature = gradientDot naturalDirection fisherDirection
            if curvature <= 1.0e-18 || not (finiteDouble curvature)
              then Left "TRPO Fisher curvature is not finite and positive"
              else
                let step =
                      scaleGradient
                        (sqrt (2.0 * ppoKlTarget config / curvature))
                        naturalDirection
                 in if validGradientFor params step
                      then Right step
                      else Left "TRPO natural-gradient step is non-finite"

trpoBacktrackScales :: PpoTrainConfig -> [Double]
trpoBacktrackScales config =
  [ ppoTrpoBacktrackCoef config ^ i
  | i <- [0 .. max 0 (ppoTrpoBacktrackIterations config - 1)]
  ]

trpoBatchLoss :: PpoTrainConfig -> MlpParams -> [(RolloutStep, Double, Double)] -> Double
trpoBatchLoss config params batch =
  TrpoLoss.trpoSurrogate
    (oldLogProbBatch batch)
    (newLogProbBatch config params batch)
    [advantage | (_, advantage, _) <- batch]

oldLogProbBatch :: [(RolloutStep, Double, Double)] -> [Double]
oldLogProbBatch =
  fmap (\(step, _, _) -> rsLogProb step)

oldPolicyBatch :: [(RolloutStep, Double, Double)] -> [Vector Double]
oldPolicyBatch = fmap (rsPolicy . firstOfTriple)
 where
  firstOfTriple (step, _, _) = step

newLogProbBatch :: PpoTrainConfig -> MlpParams -> [(RolloutStep, Double, Double)] -> [Double]
newLogProbBatch config params =
  fmap
    ( \(step, _, _) ->
        let pvOut = policyValueForwardWith LinearValueHead params (ppoActionCount config) (rsObs step)
            probs = maskedPolicyFor config (rsActionMask step) (pvPolicy pvOut)
            prob = probs VU.! rsAction step
         in if prob <= 0 then -1.0e9 else log prob
    )

newPolicyBatch
  :: PpoTrainConfig
  -> MlpParams
  -> [(RolloutStep, Double, Double)]
  -> [Vector Double]
newPolicyBatch config params =
  fmap
    ( \(step, _, _) ->
        let pvOut = policyValueForwardWith LinearValueHead params (ppoActionCount config) (rsObs step)
         in maskedPolicyFor config (rsActionMask step) (pvPolicy pvOut)
    )

policyBatchToLists :: [Vector Double] -> [[Double]]
policyBatchToLists = fmap VU.toList

finiteDouble :: Double -> Bool
finiteDouble value = not (isNaN value) && not (isInfinite value)

finiteVector :: Vector Double -> Bool
finiteVector = VU.all finiteDouble

validCategoricalVector :: Int -> Vector Double -> Bool
validCategoricalVector actionCount policy =
  actionCount > 0
    && VU.length policy == actionCount
    && finiteVector policy
    && VU.all (>= 0.0) policy
    && abs (VU.sum policy - 1.0) <= 1.0e-8

validTrpoConfig :: PpoTrainConfig -> Bool
validTrpoConfig config =
  ppoVariant config == VariantTRPO
    && ppoActionCount config > 0
    && ppoObsSize config > 0
    && ppoHiddenUnits config > 0
    && finiteDouble (ppoKlTarget config)
    && ppoKlTarget config > 0.0
    && ppoTrpoCgIterations config > 0
    && finiteDouble (ppoTrpoCgDamping config)
    && ppoTrpoCgDamping config >= 0.0
    && ppoTrpoBacktrackIterations config > 0
    && finiteDouble (ppoTrpoBacktrackCoef config)
    && ppoTrpoBacktrackCoef config > 0.0
    && ppoTrpoBacktrackCoef config < 1.0
    && ppoTrpoCriticUpdates config > 0
    && ppoMiniBatchSize config > 0
    && finiteDouble (ppoTrpoCriticLearningRate config)
    && ppoTrpoCriticLearningRate config > 0.0
    && finiteDouble (ppoValueCoef config)
    && ppoValueCoef config >= 0.0

validTrpoBatch :: PpoTrainConfig -> [(RolloutStep, Double, Double)] -> Bool
validTrpoBatch config batch =
  validTrpoFisherBatch config batch && all validSampleScalars batch
 where
  validSampleScalars (step, advantage, target) =
    finiteDouble (rsLogProb step)
      && abs (rsLogProb step - log (rsPolicy step VU.! rsAction step)) <= behaviorPolicyTolerance
      && finiteDouble advantage
      && finiteDouble target

-- Fisher curvature depends only on rollout observations and old policies, not
-- on advantages or value targets.
validTrpoFisherBatch :: PpoTrainConfig -> [(RolloutStep, Double, Double)] -> Bool
validTrpoFisherBatch config batch = not (null batch) && all validSample batch
 where
  actionCount = ppoActionCount config
  validSample (step, _, _) =
    VU.length (rsObs step) == ppoObsSize config
      && finiteVector (rsObs step)
      && rsAction step >= 0
      && rsAction step < actionCount
      && validCategoricalVector actionCount (rsPolicy step)
      && rsPolicy step VU.! rsAction step > 0.0

validGradientFor :: MlpParams -> MlpGradient -> Bool
validGradientFor params gradient =
  finiteVector (paramW1 params)
    && finiteVector (paramB1 params)
    && finiteVector (paramW2 params)
    && finiteVector (paramB2 params)
    && sameFinite (paramW1 params) (gradW1 gradient)
    && sameFinite (paramB1 params) (gradB1 gradient)
    && sameFinite (paramW2 params) (gradW2 gradient)
    && sameFinite (paramB2 params) (gradB2 gradient)
 where
  sameFinite expected actual =
    VU.length expected == VU.length actual && finiteVector actual

validMlpParamsForConfig :: PpoTrainConfig -> MlpParams -> Bool
validMlpParamsForConfig config params =
  mlpInputs shape == ppoObsSize config
    && mlpHidden shape == ppoHiddenUnits config
    && mlpOutputs shape == ppoActionCount config + 1
    && VU.length (paramW1 params) == mlpHidden shape * mlpInputs shape
    && VU.length (paramB1 params) == mlpHidden shape
    && VU.length (paramW2 params) == mlpOutputs shape * mlpHidden shape
    && VU.length (paramB2 params) == mlpOutputs shape
    && finiteVector (paramW1 params)
    && finiteVector (paramB1 params)
    && finiteVector (paramW2 params)
    && finiteVector (paramB2 params)
 where
  shape = paramShape params

validAdamStateFor :: MlpParams -> AdamState -> Bool
validAdamStateFor params state =
  adamStep_ state >= 0
    && validGradientFor params (adamM state)
    && validGradientFor params (adamV state)
    && gradientAllNonNegative (adamV state)

gradientAllNonNegative :: MlpGradient -> Bool
gradientAllNonNegative gradient =
  VU.all (>= 0.0) (gradW1 gradient)
    && VU.all (>= 0.0) (gradB1 gradient)
    && VU.all (>= 0.0) (gradW2 gradient)
    && VU.all (>= 0.0) (gradB2 gradient)

validateDeviceOutputBatch
  :: Text
  -> MlpParams
  -> Int
  -> [Vector Double]
  -> Either Text ()
validateDeviceOutputBatch label params expectedCount outputs
  | length outputs /= expectedCount =
      Left (label <> " returned an unexpected output count")
  | any ((/= expectedWidth) . VU.length) outputs =
      Left (label <> " returned an unexpected output width")
  | not (all finiteVector outputs) =
      Left (label <> " returned a non-finite output")
  | otherwise = Right ()
 where
  expectedWidth = mlpOutputs (paramShape params)

validateDeviceUpstreamBatch
  :: Text
  -> MlpParams
  -> [Vector Double]
  -> Either Text ()
validateDeviceUpstreamBatch label params upstream
  | any ((/= expectedWidth) . VU.length) upstream =
      Left (label <> " produced an unexpected gradient-head width")
  | not (all finiteVector upstream) =
      Left (label <> " produced a non-finite gradient head")
  | otherwise = Right ()
 where
  expectedWidth = mlpOutputs (paramShape params)

behaviorPolicyTolerance :: Double
behaviorPolicyTolerance = 1.0e-10

behaviorPolicyMatchesCurrent
  :: PpoTrainConfig
  -> MlpParams
  -> [(RolloutStep, Double, Double)]
  -> Bool
behaviorPolicyMatchesCurrent config params batch =
  behaviorPoliciesMatch
    (policyBatchToLists (oldPolicyBatch batch))
    (newPolicyBatch config params batch)

behaviorPoliciesMatch :: [[Double]] -> [Vector Double] -> Bool
behaviorPoliciesMatch oldPolicies currentPolicies =
  TrpoLoss.trpoKlConstraintSatisfied
    behaviorPolicyTolerance
    oldPolicies
    (policyBatchToLists currentPolicies)

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
      pvOut = policyValueForwardWith LinearValueHead params actionCount (rsObs step)
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
   in policyValueBackwardWith LinearValueHead params pvOut dLogitVec valueGrad

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

zeroLikeGradient :: MlpGradient -> MlpGradient
zeroLikeGradient g =
  MlpGradient
    { gradW1 = VU.map (const 0.0) (gradW1 g)
    , gradB1 = VU.map (const 0.0) (gradB1 g)
    , gradW2 = VU.map (const 0.0) (gradW2 g)
    , gradB2 = VU.map (const 0.0) (gradB2 g)
    }

-- | Exact categorical-policy Fisher-vector product for the two-layer policy
-- MLP. For each rollout state this computes @J' C J v@, where @J@ is the
-- policy-logit Jacobian and @C = diag(p) - p p'@ is the categorical Fisher in
-- logit space. The value output is excluded, and explicit damping makes the
-- conjugate-gradient system positive definite.
trpoFisherVectorProduct
  :: PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> MlpGradient
  -> MlpGradient
trpoFisherVectorProduct config batch params direction =
  if validGradientFor params direction
    && validTrpoFisherBatch config batch
    && validMlpParamsForConfig config params
    && behaviorPolicyMatchesCurrent config params batch
    then addGradient meanFisher (scaleGradient damping direction)
    else scaleGradient damping direction
 where
  damping
    | finiteDouble (ppoTrpoCgDamping config) = max 0.0 (ppoTrpoCgDamping config)
    | otherwise = 0.0
  meanFisher =
    scaleGradient
      (1.0 / fromIntegral (max 1 (length batch)))
      ( sumGradients
          [ fisherGradientForStep step
          | (step, _, _) <- batch
          ]
      )
  fisherGradientForStep step =
    let actionCount = ppoActionCount config
        forward = policyValueForwardWith LinearValueHead params actionCount (rsObs step)
        logitDirection = trpoPolicyLogitJvp params direction (pvForward forward) actionCount
     in case categoricalFisherOutput (rsPolicy step) logitDirection actionCount of
          Nothing -> zeroLikeGradient direction
          Just fisherOutput ->
            policyValueBackwardWith
              LinearValueHead
              params
              forward
              (VU.take actionCount fisherOutput)
              0.0

-- | Device-backed categorical Fisher-vector product. Directional logits are
-- obtained by symmetric finite differences through the selected backend, then
-- the backend's batched gradient computes @J' C J v@. No update-critical
-- forward/backward operation falls back to the pure-Haskell MLP.
trpoFisherVectorProductDevice
  :: MlpDevice
  -> PpoTrainConfig
  -> [(RolloutStep, Double, Double)]
  -> MlpParams
  -> MlpGradient
  -> IO (Either Text MlpGradient)
trpoFisherVectorProductDevice device config batch params direction
  | not (validTrpoFisherBatch config batch) =
      pure (Left "TRPO device Fisher received an empty or malformed rollout batch")
  | not (validGradientFor params direction) =
      pure (Left "TRPO device Fisher direction is malformed or non-finite")
  | otherwise = do
      let directionNorm = sqrt (max 0.0 (gradientDot direction direction))
          epsilon = 1.0e-3 / max 1.0 directionNorm
          plusParams = applyGradientStep (-epsilon) direction params
          minusParams = applyGradientStep epsilon direction params
          observations = [rsObs step | (step, _, _) <- batch]
      plusResult <- mlpdForwardBatch device plusParams observations
      minusResult <- mlpdForwardBatch device minusParams observations
      case (plusResult, minusResult) of
        (Left err, _) -> pure (Left err)
        (_, Left err) -> pure (Left err)
        (Right plusOutputs, Right minusOutputs)
          | length plusOutputs /= length batch || length minusOutputs /= length batch ->
              pure (Left "TRPO device Fisher forward returned an unexpected output count")
          | otherwise -> do
              let upstreamResult =
                    traverse
                      (fisherUpstream epsilon)
                      (zip3 batch plusOutputs minusOutputs)
              case upstreamResult of
                Left err -> pure (Left err)
                Right upstream -> do
                  gradientResult <-
                    mlpdBatchGradient
                      device
                      params
                      (zip observations upstream)
                  pure $ do
                    summed <- gradientResult
                    if not (validGradientFor params summed)
                      then Left "TRPO device Fisher gradient is malformed or non-finite"
                      else
                        let productGradient =
                              addGradient
                                (scaleGradient (1.0 / fromIntegral (length batch)) summed)
                                (scaleGradient (ppoTrpoCgDamping config) direction)
                         in if validGradientFor params productGradient
                              then Right productGradient
                              else Left "TRPO device Fisher product is non-finite"
 where
  actionCount = ppoActionCount config
  fisherUpstream epsilon ((step, _, _), plusOutput, minusOutput)
    | VU.length plusOutput /= actionCount + 1 || VU.length minusOutput /= actionCount + 1 =
        Left "TRPO device Fisher output width does not match policy/value width"
    | not (finiteVector plusOutput) || not (finiteVector minusOutput) =
        Left "TRPO device Fisher output contains a non-finite value"
    | otherwise =
        let logitDirection =
              VU.zipWith
                (\plusValue minusValue -> (plusValue - minusValue) / (2.0 * epsilon))
                (VU.take actionCount plusOutput)
                (VU.take actionCount minusOutput)
         in case categoricalFisherOutput (rsPolicy step) logitDirection actionCount of
              Nothing -> Left "TRPO device Fisher received an invalid categorical policy"
              Just output -> Right output

-- | Directional derivative of the policy logits for the two-layer tanh MLP.
trpoPolicyLogitJvp
  :: MlpParams
  -> MlpGradient
  -> MlpForward
  -> Int
  -> Vector Double
trpoPolicyLogitJvp params direction forward actionCount =
  VU.generate actionCount directionalOutput
 where
  shape = paramShape params
  inputCount = mlpInputs shape
  hiddenCount = mlpHidden shape
  input = forwardInput forward
  hidden = forwardHiddenAct forward
  hiddenPreDirection =
    VU.generate
      hiddenCount
      ( \hiddenIndex ->
          (gradB1 direction VU.! hiddenIndex)
            + sum
              [ (gradW1 direction VU.! (hiddenIndex * inputCount + inputIndex))
                  * (input VU.! inputIndex)
              | inputIndex <- [0 .. inputCount - 1]
              ]
      )
  hiddenDirection =
    VU.zipWith
      (\hiddenValue preDirection -> (1.0 - hiddenValue * hiddenValue) * preDirection)
      hidden
      hiddenPreDirection
  directionalOutput outputIndex =
    (gradB2 direction VU.! outputIndex)
      + sum
        [ (gradW2 direction VU.! (outputIndex * hiddenCount + hiddenIndex))
            * (hidden VU.! hiddenIndex)
            + (paramW2 params VU.! (outputIndex * hiddenCount + hiddenIndex))
              * (hiddenDirection VU.! hiddenIndex)
        | hiddenIndex <- [0 .. hiddenCount - 1]
        ]

categoricalFisherOutput :: Vector Double -> Vector Double -> Int -> Maybe (Vector Double)
categoricalFisherOutput policyRaw logitDirection actionCount =
  if VU.length logitDirection /= actionCount || not (finiteVector logitDirection)
    then Nothing
    else do
      policy <- normaliseCategorical actionCount policyRaw
      let centered = VU.sum (VU.zipWith (*) policy logitDirection)
          output =
            VU.zipWith
              (\probability directional -> probability * (directional - centered))
              policy
              logitDirection
              VU.++ VU.singleton 0.0
      if finiteVector output then Just output else Nothing

normaliseCategorical :: Int -> Vector Double -> Maybe (Vector Double)
normaliseCategorical actionCount policyRaw
  | not (validCategoricalVector actionCount policyRaw) = Nothing
  | otherwise = Just (VU.map (/ total) policyRaw)
 where
  total = VU.sum policyRaw

conjugateGradientSolve
  :: Int
  -> (MlpGradient -> MlpGradient)
  -> MlpGradient
  -> MlpGradient
conjugateGradientSolve iterations fisher b =
  go 0 (zeroLikeGradient b) b b (gradientDot b b)
 where
  go i x r p rr
    | i >= iterations = x
    | not (finiteDouble rr) = x
    | rr <= 1.0e-20 = x
    | otherwise =
        let ap = fisher p
            denom = gradientDot p ap
         in if denom <= 1.0e-20 || not (finiteDouble denom)
              then x
              else
                let alpha = rr / denom
                    xNext = addScaledGradient alpha p x
                    rNext = subGradient r (scaleGradient alpha ap)
                    rrNext = gradientDot rNext rNext
                    beta = rrNext / rr
                    pNext = addScaledGradient beta p rNext
                 in if all finiteDouble [alpha, rrNext, beta]
                      then go (i + 1) xNext rNext pNext rrNext
                      else x

conjugateGradientSolveDevice
  :: Int
  -> (MlpGradient -> IO (Either Text MlpGradient))
  -> MlpGradient
  -> IO (Either Text MlpGradient)
conjugateGradientSolveDevice iterations fisher b =
  go 0 (zeroLikeGradient b) b b (gradientDot b b)
 where
  go i x r p rr
    | i >= iterations = pure (Right x)
    | not (finiteDouble rr) = pure (Left "TRPO conjugate-gradient residual is non-finite")
    | rr <= 1.0e-20 = pure (Right x)
    | otherwise = do
        productResult <- fisher p
        case productResult of
          Left err -> pure (Left err)
          Right ap ->
            let denom = gradientDot p ap
             in if not (finiteDouble denom)
                  then pure (Left "TRPO conjugate-gradient curvature is not finite")
                  else
                    if denom <= 1.0e-20
                      then
                        -- Device Fisher products obtain their logit JVP through
                        -- finite differences over float-backed kernels.  The
                        -- resulting operator is positive definite in exact
                        -- arithmetic (explicit damping is included), but after
                        -- one or more useful CG iterations round-off can break
                        -- conjugacy and make a tail direction report zero or
                        -- slightly negative curvature.  Truncated CG keeps the
                        -- finite iterate already accumulated; the caller then
                        -- recomputes and validates that iterate's full Fisher
                        -- curvature before it may become a policy step.  An
                        -- invalid first direction still fails closed.
                        if i == 0
                          then pure (Left "TRPO conjugate-gradient curvature is not positive")
                          else pure (Right x)
                      else
                        let alpha = rr / denom
                            xNext = addScaledGradient alpha p x
                            rNext = subGradient r (scaleGradient alpha ap)
                            rrNext = gradientDot rNext rNext
                            beta = rrNext / rr
                            pNext = addScaledGradient beta p rNext
                         in if all finiteDouble [alpha, rrNext, beta]
                              then go (i + 1) xNext rNext pNext rrNext
                              else pure (Left "TRPO conjugate-gradient update became non-finite")

-- | Keep critic optimization off every parameter that can affect the policy.
-- The compact MLP shares its first layer between actor and critic, so a valid
-- TRPO critic step may update only the value output row and value bias.
trpoValueHeadOnlyGradient :: PpoTrainConfig -> MlpGradient -> MlpGradient
trpoValueHeadOnlyGradient config gradient =
  MlpGradient
    { gradW1 = VU.map (const 0.0) (gradW1 gradient)
    , gradB1 = VU.map (const 0.0) (gradB1 gradient)
    , gradW2 =
        VU.imap
          ( \index value ->
              if index >= valueRowStart && index < valueRowEnd
                then value
                else 0.0
          )
          (gradW2 gradient)
    , gradB2 =
        VU.imap
          (\index value -> if index == actionCount then value else 0.0)
          (gradB2 gradient)
    }
 where
  actionCount = ppoActionCount config
  hiddenCount = VU.length (gradB1 gradient)
  valueRowStart = actionCount * hiddenCount
  valueRowEnd = valueRowStart + hiddenCount

-- | Apply one TRPO critic update without allowing either a supplied
-- gradient or stale Adam moments to move actor parameters. Restoring the actor
-- slices after Adam is intentional defence in depth: the policy is bit-equal
-- before and after this function even when the incoming optimizer state was
-- populated by an older shared-parameter implementation.
trpoCriticStep
  :: PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> MlpGradient
  -> (MlpParams, AdamState)
trpoCriticStep config params adam gradient
  | not (validTrpoConfig config) = (params, adam)
  | not (validMlpParamsForConfig config params) = (params, adam)
  | not (validAdamStateFor params adam) = (params, adam)
  | not (validGradientFor params gradient) = (params, adam)
  | validMlpParamsForConfig config restoredParams
      && validAdamStateFor restoredParams restoredAdam =
      (restoredParams, restoredAdam)
  | otherwise = (params, adam)
 where
  adamConfig =
    defaultAdamConfig
      { adamLearningRate = ppoTrpoCriticLearningRate config
      }
  valueOnlyAdam state =
    state
      { adamM = trpoValueHeadOnlyGradient config (adamM state)
      , adamV = trpoValueHeadOnlyGradient config (adamV state)
      }
  (candidateParams, candidateAdam) =
    adamStep
      adamConfig
      (valueOnlyAdam adam)
      params
      (trpoValueHeadOnlyGradient config gradient)
  restoredParams = restoreActorParams params candidateParams
  restoredAdam = valueOnlyAdam candidateAdam
  actionCount = ppoActionCount config
  hiddenCount = mlpHidden (paramShape params)
  valueRowStart = actionCount * hiddenCount
  valueRowEnd = valueRowStart + hiddenCount
  restoreActorParams old candidate =
    candidate
      { paramW1 = paramW1 old
      , paramB1 = paramB1 old
      , paramW2 =
          VU.imap
            ( \index value ->
                if index >= valueRowStart && index < valueRowEnd
                  then value
                  else paramW2 old VU.! index
            )
            (paramW2 candidate)
      , paramB2 =
          VU.imap
            ( \index value ->
                if index == actionCount
                  then value
                  else paramB2 old VU.! index
            )
            (paramB2 candidate)
      }

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
-- softmax policy and linear, unbounded value for one rollout step, plus the step's
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
  -- single per-rollout KL trust region in `ppoUpdate`).
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
    -- Entropy BONUS (add, not subtract): `dPolicyLossDLogit` is a loss gradient
    -- descended by Adam, and `dEntropyDLogit = p*(logP - meanLog) = -dH/dz`, so
    -- the entropy-bonus loss term `-coef*H` contributes `+coef*dEntropyDLogit`.
    -- The old `- coef*dEntropyDLogit` was an entropy PENALTY that collapsed the
    -- policy to a peaked/deterministic action, suppressing exploration (this hit
    -- both the pure and linux-cuda device paths via `ppoHeadGradient`).
    dPolicyLossDLogit i
      + entropyCoefficient * dEntropyDLogit i
  -- The TRPO line search optimises the unclipped surrogate alone. Including an
  -- entropy term in its direction while evaluating a different objective would
  -- make the acceptance test internally inconsistent.
  entropyCoefficient
    | ppoVariant config == VariantTRPO = 0.0
    | otherwise = ppoEntropyCoef config
  dLogitVec = VU.generate actionCount dHeadDLogit
  -- Value loss = 0.5 * (value - target)^2, scaled by value coef.
  valueGrad = ppoValueCoef config * (value - target)
  logSafe x
    | x <= 0 = -1.0e9
    | otherwise = log x

-- | Train any on-policy variant on cartpole. PPO/A2C/TRPO/MaskablePPO/
-- RecurrentPPO all share this loop; the variant selects the surrogate
-- term (clipped vs. unclipped) and, for TRPO, the single per-rollout KL gate.
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
  -- One visitation table for the whole run, mutated across rollouts.
  countTable <- CountExploration.newCountTable
  (_, _, _, finalAdam, stats, finalParams, trpoActorSteps, measuredTransitions) <-
    foldM
      ( \(state, gen, params, adam, stats, _, actorSteps, transitions) iteration -> do
          (rollout, nextState, nextGen) <-
            collectRolloutInEnvironment countTable environment config params state gen
          let (advs, targets) = computeAdvantages config rollout
              normAdvs = standardise advs
              triples = zip3 (rolloutSteps rollout) normAdvs targets
              (paramsAfter, adamAfter) = ppoUpdate config params adam triples
              actorStepsAfter =
                actorSteps
                  + if trpoActorParametersChanged config params paramsAfter then 1 else 0
              transitionsAfter = transitions + toInteger (length (rolloutSteps rollout))
              episodeReturns = rolloutEpisodes rollout
              stat = rolloutSummary iteration episodeReturns
          pure
            ( nextState
            , nextGen
            , paramsAfter
            , adamAfter
            , stats <> [stat]
            , paramsAfter
            , actorStepsAfter
            , transitionsAfter
            )
      )
      ( envInitial environment
      , Random.mkStdGen (ppoSeed config + 1)
      , initialParams
      , initialAdam
      , [] :: [PpoIterationStat]
      , initialParams
      , 0 :: Int
      , 0 :: Integer
      )
      [0 .. ppoNumIterations config - 1]
  counters <-
    either (fail . Text.unpack) pure $
      Common.mkMeasuredTrainerCounters
        measuredTransitions
        (toInteger (adamStep_ finalAdam + trpoActorSteps))
  pure
    PpoTrainResult
      { resultIterations = stats
      , resultFinalParams = finalParams
      , resultMeasuredCounters = counters
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
-- CUDA runtime/compile is unavailable; callers propagate that device failure
-- rather than changing substrates or falling back to pure execution.
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
      (initialVecEnv, initialGen) =
        VecEnv.mkVecEnv
          environment
          (max 1 (ppoVectorEnvCount config))
          (Random.mkStdGen (ppoSeed config + 1))
  -- One visitation table for the whole run, mutated across rollouts.
  countTable <- CountExploration.newCountTable
  result <-
    foldM
      (step countTable)
      ( Right
          ( initialVecEnv
          , initialGen
          , initialParams
          , initialAdam
          , [] :: [PpoIterationStat]
          , initialParams
          , 0 :: Int
          , 0 :: Integer
          )
      )
      [0 .. ppoNumIterations config - 1]
  pure $ do
    (_, _, _, finalAdam, stats, finalParams, trpoActorSteps, measuredTransitions) <- result
    counters <-
      Common.mkMeasuredTrainerCounters
        measuredTransitions
        (toInteger (adamStep_ finalAdam + trpoActorSteps))
    pure
      PpoTrainResult
        { resultIterations = stats
        , resultFinalParams = finalParams
        , resultMeasuredCounters = counters
        , resultConfig = config
        }
 where
  step _ (Left e) _ = pure (Left e)
  step countTable (Right (vecEnv, gen, params, adam, stats, _, actorSteps, transitions)) iteration = do
    collected <-
      collectRolloutVectorizedOnDevice
        device
        countTable
        environment
        config
        params
        vecEnv
        gen
    case collected of
      Left e -> pure (Left e)
      Right (vectorized, nextVecEnv, nextGen) -> do
        let rollout = vectorizedRollout vectorized
            triples = vectorizedRolloutTriples config (vectorizedRolloutGroups vectorized)
        updated <- ppoUpdateDevice device config params adam triples
        case updated of
          Left e -> pure (Left e)
          Right (paramsAfter, adamAfter) ->
            let actorStepsAfter =
                  actorSteps
                    + if trpoActorParametersChanged config params paramsAfter then 1 else 0
                transitionsAfter = transitions + toInteger (length (rolloutSteps rollout))
                stat = rolloutSummary iteration (rolloutEpisodes rollout)
             in pure
                  ( Right
                      ( nextVecEnv
                      , nextGen
                      , paramsAfter
                      , adamAfter
                      , stats <> [stat]
                      , paramsAfter
                      , actorStepsAfter
                      , transitionsAfter
                      )
                  )

-- | TRPO's critic pass restores the shared trunk and policy-output slices
-- exactly, so a difference in any of those slices after a complete rollout
-- update proves that the actor line search accepted and applied one step.
trpoActorParametersChanged :: PpoTrainConfig -> MlpParams -> MlpParams -> Bool
trpoActorParametersChanged config before after =
  ppoVariant config == VariantTRPO
    && ( paramW1 before /= paramW1 after
           || paramB1 before /= paramB1 after
           || VU.take policyWeightCount (paramW2 before)
             /= VU.take policyWeightCount (paramW2 after)
           || VU.take actionCount (paramB2 before)
             /= VU.take actionCount (paramB2 after)
       )
 where
  actionCount = ppoActionCount config
  policyWeightCount = actionCount * mlpHidden (paramShape before)

collectRolloutVectorizedOnDevice
  :: MlpDevice
  -> CountExploration.CountTable
  -> SimulatedEnvironment state
  -> PpoTrainConfig
  -> MlpParams
  -> VecEnv.VecEnv state
  -> Random.StdGen
  -> IO (Either Text (VectorizedRollout, VecEnv.VecEnv state, Random.StdGen))
collectRolloutVectorizedOnDevice device countTable environment config params vecEnv0 gen0 =
  go 0 vecEnv0 gen0 emptyGroups []
 where
  vectorSteps = max 1 (ppoRolloutSteps config)
  actionCount = ppoActionCount config
  emptyGroups = replicate (VecEnv.vecEnvSize vecEnv0) []
  go stepIndex vecEnv gen groups completedEpisodes
    | stepIndex >= vectorSteps = do
        finalValuesE <- finalValuesFor vecEnv
        pure $
          fmap
            ( \finalValues ->
                let grouped = zipWith (\steps finalValue -> (reverse steps, finalValue)) groups finalValues
                    flatSteps = concatMap fst grouped
                    rollout =
                      Rollout
                        { rolloutSteps = flatSteps
                        , rolloutEpisodes = reverse completedEpisodes
                        , rolloutFinalValue = mean finalValues
                        }
                 in (VectorizedRollout rollout grouped, vecEnv, gen)
            )
            finalValuesE
    | otherwise = do
        let observations = VecEnv.vecEnvObservations vecEnv
            slots = VecEnv.vecEnvSlots vecEnv
            masks = fmap (actionMaskFor environment config . VecEnv.vecSlotState) slots
        forwardResult <- mlpdForwardBatch device params observations
        case forwardResult of
          Left err -> pure (Left err)
          Right outs -> do
            let policies = fmap (softmax . VU.take actionCount) outs
                values = fmap (`VU.unsafeIndex` actionCount) outs
                maskedPolicies = zipWith (maskedPolicyFor config) masks policies
                (actions, logProbs, genAfterActions) = sampleActions maskedPolicies gen
                (vecEnv', transitions, genAfterStep) =
                  VecEnv.vecEnvStep (ppoMaxEpisodeSteps config) vecEnv actions genAfterActions
            indexedSteps <-
              traverse
                (uncurry5 transitionToRolloutStep)
                (zip5 transitions actions logProbs values maskedPolicies masks)
            let groups' = foldl appendStep groups indexedSteps
                completedEpisodes' =
                  foldl
                    ( \acc transition ->
                        case VecEnv.vecTransitionCompletedReturn transition of
                          Nothing -> acc
                          Just reward -> reward : acc
                    )
                    completedEpisodes
                    transitions
            go (stepIndex + 1) vecEnv' genAfterStep groups' completedEpisodes'
  finalValuesFor vecEnv = do
    forwardResult <- mlpdForwardBatch device params (VecEnv.vecEnvObservations vecEnv)
    pure $
      fmap
        (fmap (`VU.unsafeIndex` actionCount))
        forwardResult
  transitionToRolloutStep transition action logProb value probs mask = do
    countBonus <-
      CountExploration.countExplorationBonus
        countTable
        (ppoCountBeta config)
        (envName environment)
        (VecEnv.vecTransitionNextObservation transition)
    let obs = VecEnv.vecTransitionObservation transition
        nextObs = VecEnv.vecTransitionNextObservation transition
        recurrentState =
          recurrentStateFor
            config
            obs
            (VecEnv.vecTransitionEpisodeReturnBefore transition)
            (VecEnv.vecTransitionEpisodeLengthBefore transition)
        reward =
          VecEnv.vecTransitionReward transition
            + RewardShaping.shapingBonus
              (envName environment)
              (ppoGamma config)
              obs
              nextObs
            + countBonus
    pure
      ( VecEnv.vecTransitionIndex transition
      , RolloutStep
          { rsObs = obs
          , rsAction = clamp 0 (max 0 (actionCount - 1)) action
          , rsLogProb = logProb
          , rsValue = value
          , rsReward = reward
          , rsDone = VecEnv.vecTransitionDone transition
          , rsPolicy = probs
          , rsActionMask = mask
          , rsRecurrentState = recurrentState
          }
      )

vectorizedRolloutTriples
  :: PpoTrainConfig
  -> [([RolloutStep], Double)]
  -> [(RolloutStep, Double, Double)]
vectorizedRolloutTriples config groups =
  zipWith
    (\(step, _, target) advantage -> (step, advantage, target))
    rawTriples
    normAdvs
 where
  rawTriples =
    concatMap
      ( \(steps, finalValue) ->
          let (advs, targets) =
                computeAdvantages
                  config
                  Rollout
                    { rolloutSteps = steps
                    , rolloutEpisodes = []
                    , rolloutFinalValue = finalValue
                    }
           in zip3 steps advs targets
      )
      groups
  normAdvs = standardise [advantage | (_, advantage, _) <- rawTriples]

sampleActions :: [Vector Double] -> Random.StdGen -> ([Int], [Double], Random.StdGen)
sampleActions [] gen = ([], [], gen)
sampleActions (probs : rest) gen =
  let (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
      action = sampleCategorical probs u
      prob = probs VU.! action
      logProb = if prob <= 0 then -1.0e9 else log prob
      (actions, logProbs, genN) = sampleActions rest gen'
   in (action : actions, logProb : logProbs, genN)

appendStep :: [[RolloutStep]] -> (Int, RolloutStep) -> [[RolloutStep]]
appendStep groups (index, step) =
  let targetIndex = max 0 (min (length groups - 1) index)
   in updateAt targetIndex (step :) groups

updateAt :: Int -> (a -> a) -> [a] -> [a]
updateAt _ _ [] = []
updateAt 0 f (x : xs) = f x : xs
updateAt n f (x : xs) = x : updateAt (n - 1) f xs

zip5 :: [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [(a, b, c, d, e, f)]
zip5 (a : as) (b : bs) (c : cs) (d : ds) (e : es) (f : fs) = (a, b, c, d, e, f) : zip5 as bs cs ds es fs
zip5 _ _ _ _ _ _ = []

uncurry5 :: (a -> b -> c -> d -> e -> f -> g) -> (a, b, c, d, e, f) -> g
uncurry5 f (a, b, c, d, e, g) = f a b c d e g

mean :: [Double] -> Double
mean [] = 0.0
mean xs = sum xs / fromIntegral (length xs)

clamp :: (Ord a) => a -> a -> a -> a
clamp lo hi = max lo . min hi

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
-- primitives. For each PPO-family epoch, the rollout is split into minibatches;
-- each minibatch runs
-- one batched device forward (to obtain the per-sample policy/value
-- outputs), computes the per-sample loss-gradient head on the host, runs
-- one batched device backward (the mean gradient over the minibatch), and
-- applies one Adam step. TRPO ignores PPO epoching and performs one actor
-- trust-region step followed by its configured value-head-only critic passes
-- over the rollout minibatches.
ppoUpdateDevice
  :: MlpDevice
  -> PpoTrainConfig
  -> MlpParams
  -> AdamState
  -> [(RolloutStep, Double, Double)]
  -> IO (Either Text (MlpParams, AdamState))
ppoUpdateDevice device config params0 adam0 batch =
  if ppoVariant config == VariantTRPO
    then runTrpoUpdate
    else foldM runEpoch (Right (params0, adam0)) [1 .. ppoEpochsPerUpdate config]
 where
  adamConfig = defaultAdamConfig {adamLearningRate = ppoLearningRate config}
  actionCount = ppoActionCount config
  minibatches
    | ppoVariant config == VariantRecurrentPPO =
        RecurrentPpoLoss.bpttWindows 16 batch
    | otherwise = chunked (max 1 (ppoMiniBatchSize config)) batch
  trpoCriticMinibatches =
    concat
      ( replicate
          (ppoTrpoCriticUpdates config)
          (chunked (ppoMiniBatchSize config) batch)
      )
  runEpoch (Left e) _ = pure (Left e)
  runEpoch acc _ = foldM runMinibatch acc minibatches
  -- TRPO keeps the policy and value updates separate. It performs exactly one
  -- actor trust-region update, then recomputes the value gradient for every
  -- minibatch in each configured critic pass. @ppoEpochsPerUpdate@ is PPO-only.
  runTrpoUpdate = do
    if not (validTrpoConfig config)
      then pure (Left "TRPO configuration is not finite and valid")
      else
        if not (validTrpoBatch config batch)
          then pure (Left "TRPO rollout batch is empty or malformed")
          else
            if not (validMlpParamsForConfig config params0)
              then pure (Left "TRPO model parameters do not match the configuration")
              else
                if not (validAdamStateFor params0 adam0)
                  then pure (Left "TRPO Adam state is malformed or non-finite")
                  else do
                    policyGradientResult <-
                      deviceMeanBatchGradientWith trpoPolicyOutputGradient params0 batch
                    case policyGradientResult of
                      Left e -> pure (Left e)
                      Right policyGradient -> do
                        policyParamsResult <-
                          trpoLineSearchUpdateDevice device config batch params0 policyGradient
                        case policyParamsResult of
                          Left e -> pure (Left e)
                          Right policyParams ->
                            foldM
                              runTrpoCriticUpdate
                              (Right (policyParams, adam0))
                              trpoCriticMinibatches
  runTrpoCriticUpdate (Left e) _ = pure (Left e)
  runTrpoCriticUpdate (Right (criticParams, criticAdam)) criticBatch = do
    valueGradientResult <-
      deviceMeanBatchGradientWith trpoValueOutputGradient criticParams criticBatch
    pure $ do
      valueGradient <- valueGradientResult
      if not (validGradientFor criticParams valueGradient)
        then Left "TRPO value gradient is malformed or non-finite"
        else
          let criticResult@(nextParams, nextAdam) =
                trpoCriticStep config criticParams criticAdam valueGradient
           in if validMlpParamsForConfig config nextParams
                && validAdamStateFor nextParams nextAdam
                && adamStep_ nextAdam == adamStep_ criticAdam + 1
                then Right criticResult
                else Left "TRPO critic update produced non-finite state"
  runMinibatch (Left e) _ = pure (Left e)
  runMinibatch (Right (params, adam)) [] = pure (Right (params, adam))
  runMinibatch (Right (params, adam)) mb = do
    forwardResult <- mlpdForwardBatch device params [rsObs s | (s, _, _) <- mb]
    case forwardResult of
      Left e -> pure (Left e)
      Right outs ->
        case validateDeviceOutputBatch "on-policy device update" params (length mb) outs of
          Left e -> pure (Left e)
          Right () -> do
            let upstream =
                  [ fullOutputGradient out s adv target
                  | ((s, adv, target), out) <- zip mb outs
                  ]
                pairs = zip [rsObs s | (s, _, _) <- mb] upstream
            case validateDeviceUpstreamBatch "on-policy device update" params upstream of
              Left e -> pure (Left e)
              Right () -> do
                gradResult <- mlpdBatchGradient device params pairs
                case gradResult of
                  Left e -> pure (Left e)
                  Right summed
                    | not (validGradientFor params summed) ->
                        pure (Left "on-policy device update returned a malformed or non-finite gradient")
                    | otherwise ->
                        let scale = 1.0 / fromIntegral (length mb)
                            meanGradient = scaleGradient scale summed
                            (paramsAfter, adamAfter) = adamStep adamConfig adam params meanGradient
                         in pure (Right (paramsAfter, adamAfter))
  deviceMeanBatchGradientWith headGradient params mb = do
    forwardResult <- mlpdForwardBatch device params [rsObs s | (s, _, _) <- mb]
    case forwardResult of
      Left e -> pure (Left e)
      Right outs ->
        case validateDeviceOutputBatch "TRPO device update" params (length mb) outs of
          Left e -> pure (Left e)
          Right () -> do
            let upstream =
                  [ headGradient out s adv target
                  | ((s, adv, target), out) <- zip mb outs
                  ]
                pairs = zip [rsObs s | (s, _, _) <- mb] upstream
            case validateDeviceUpstreamBatch "TRPO device update" params upstream of
              Left e -> pure (Left e)
              Right () -> do
                gradResult <- mlpdBatchGradient device params pairs
                pure $ do
                  summed <- gradResult
                  if not (validGradientFor params summed)
                    then Left "TRPO device update returned a malformed or non-finite gradient"
                    else
                      let meanGradient =
                            scaleGradient (1.0 / fromIntegral (length mb)) summed
                       in if validGradientFor params meanGradient
                            then Right meanGradient
                            else Left "TRPO device update produced a non-finite mean gradient"
  trpoPolicyOutputGradient out step advantage target =
    let full = fullOutputGradient out step advantage target
     in VU.take actionCount full VU.++ VU.singleton 0.0
  trpoValueOutputGradient out _step _advantage target =
    let value = out VU.! actionCount
        valueGrad = ppoValueCoef config * (value - target)
     in VU.replicate actionCount 0.0 VU.++ VU.singleton valueGrad
  fullOutputGradient out step advantage target =
    let policy = softmax (VU.take actionCount out)
        -- Linear critic (matches 'policyValueFromForward'): the device value
        -- readout is unbounded, so no tanh here and no tanh derivative below.
        value = out VU.! actionCount
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
     in dLogitVec VU.++ VU.singleton valueGrad

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

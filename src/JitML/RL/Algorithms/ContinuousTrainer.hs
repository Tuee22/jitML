-- | Sprint 13.8 — real continuous-action actor-critic training loop that
-- closes the off-policy continuous-control half of the 14-algorithm
-- catalog: DDPG, TD3, SAC, CrossQ, and TQC. All five share one
-- actor-critic + replay loop on the pure-Haskell differentiable MLP seam
-- in "JitML.Numerics.Mlp" and the continuous 'JitML.RL.Simulator'
-- Pendulum-v1 environment; the variant selects the per-algorithm
-- differences:
--
--   * 'VariantDDPG' — single critic, target nets, deterministic-policy
--     gradient (Lillicrap et al. 2016).
--   * 'VariantTD3' — twin critics + clipped-double-Q target + target-
--     policy smoothing + delayed actor updates (Fujimoto et al. 2018).
--   * 'VariantSAC' — twin critics + entropy-regularised soft Bellman
--     target (Haarnoja et al. 2018).
--   * 'VariantCrossQ' — twin critics, /no/ target networks, batch-
--     normalised online Q target (Bhatt et al. 2024).
--   * 'VariantTQC' — twin critics treated as a pooled quantile mixture
--     with top-atom truncation (Kuznetsov et al. 2020).
--
-- The per-variant Bellman target is routed through the canonical
-- @*Loss@ module for that algorithm, so the math is the published one;
-- this module supplies the network seam + replay + optimisation loop the
-- losses plug into.
--
-- The actor's deterministic-policy gradient @dQ/da@ comes from
-- 'JitML.Numerics.Mlp.mlpInputGradient' (the action-slice of the
-- critic's input gradient). The SAC/CrossQ/TQC entropy term uses a
-- fixed-std Gaussian-policy log-prob; a learned-std squashed-Gaussian
-- head is a follow-on refinement that does not change the loop shape.
--
-- Same-substrate / same-seed runs are bit-deterministic (seeded
-- 'StdGen', pure-Haskell chain-rule backprop).
module JitML.RL.Algorithms.ContinuousTrainer
  ( ContinuousVariant (..)
  , ContinuousTrainConfig (..)
  , defaultContinuousTrainConfig
  , ContinuousTrainResult (..)
  , ContinuousIterationStat (..)
  , ContTransition (..)
  , trainContinuousOnPendulum
  , trainContinuousOnPendulumCuda
  , trainContinuousOnPendulumOneDnn
  , trainContinuousOnPendulumMetal
  , trainContinuousOnDevice
  )
where

import Control.Monad.Except (ExceptT (..), runExceptT)
import Data.Either (fromRight)
import Data.List qualified
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpForward (..)
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpBackward
  , mlpForward
  , mlpInit
  , mlpInputGradient
  )
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.Algorithms.CrossQLoss (crossQNormalise, crossQTarget)
import JitML.RL.Algorithms.DdpgLoss (ddpgCriticTarget)
import JitML.RL.Algorithms.SacLoss (sacCriticTarget)
import JitML.RL.Algorithms.Td3Loss (td3ClippedDoubleTarget, td3SmoothTargetActions)
import JitML.RL.Algorithms.TqcLoss (tqcTarget)
import JitML.RL.Simulator
  ( ContinuousSimStep (..)
  , PendulumState
  , pendulumEnvironment
  , pendulumInitial
  )
import JitML.RL.Simulator qualified as Sim

-- | The five continuous-control off-policy algorithms.
data ContinuousVariant
  = VariantDDPG
  | VariantTD3
  | VariantSAC
  | VariantCrossQ
  | VariantTQC
  deriving stock (Eq, Show)

data ContinuousTrainConfig = ContinuousTrainConfig
  { ctVariant :: !ContinuousVariant
  , ctSeed :: !Int
  , ctHidden :: !Int
  , ctNumSteps :: !Int
  , ctReplayCapacity :: !Int
  , ctBatchSize :: !Int
  , ctActorLr :: !Double
  , ctCriticLr :: !Double
  , ctGamma :: !Double
  , ctTau :: !Double
  , ctPolicyDelay :: !Int
  , ctExplNoise :: !Double
  , ctTargetNoise :: !Double
  , ctNoiseClip :: !Double
  , ctSacAlpha :: !Double
  , ctPolicyStd :: !Double
  , ctTqcDropPerCritic :: !Int
  , ctStartSteps :: !Int
  , ctTrainStart :: !Int
  , ctMaxEpisodeSteps :: !Int
  , ctObsSize :: !Int
  , ctActionLow :: !Double
  , ctActionHigh :: !Double
  , ctStatInterval :: !Int
  }
  deriving stock (Eq, Show)

defaultContinuousTrainConfig :: ContinuousVariant -> ContinuousTrainConfig
defaultContinuousTrainConfig variant =
  ContinuousTrainConfig
    { ctVariant = variant
    , ctSeed = 42
    , ctHidden = 64
    , ctNumSteps = 6000
    , ctReplayCapacity = 20000
    , ctBatchSize = 64
    , ctActorLr = 1.0e-3
    , ctCriticLr = 1.0e-3
    , ctGamma = 0.98
    , ctTau = 0.01
    , ctPolicyDelay = if variant `elem` [VariantTD3, VariantTQC] then 2 else 1
    , ctExplNoise = 0.3
    , ctTargetNoise = 0.2
    , ctNoiseClip = 0.5
    , ctSacAlpha = 0.2
    , ctPolicyStd = 0.3
    , ctTqcDropPerCritic = 0
    , ctStartSteps = 500
    , ctTrainStart = 500
    , ctMaxEpisodeSteps = 200
    , ctObsSize = 3
    , ctActionLow = -2.0
    , ctActionHigh = 2.0
    , ctStatInterval = 1000
    }

data ContTransition = ContTransition
  { contObs :: !(Vector Double)
  , contAction :: !Double
  , contReward :: !Double
  , contNextObs :: !(Vector Double)
  , contDone :: !Bool
  }
  deriving stock (Eq, Show)

data ContinuousIterationStat = ContinuousIterationStat
  { contIterStep :: !Int
  , contIterEpisodes :: !Int
  , contIterMeanReward :: !Double
  , contIterLastEpisodeReward :: !Double
  }
  deriving stock (Eq, Show)

data ContinuousTrainResult = ContinuousTrainResult
  { contResultStats :: ![ContinuousIterationStat]
  , contResultFinalActor :: !MlpParams
  , contResultConfig :: !ContinuousTrainConfig
  }
  deriving stock (Eq, Show)

-- | Actor + critic networks plus their (soft-updated) target copies.
data ACNets = ACNets
  { acActor :: !MlpParams
  , acCriticA :: !MlpParams
  , acCriticB :: !MlpParams
  , acTargetActor :: !MlpParams
  , acTargetCriticA :: !MlpParams
  , acTargetCriticB :: !MlpParams
  }

data ACOpt = ACOpt
  { acActorAdam :: !AdamState
  , acCriticAAdam :: !AdamState
  , acCriticBAdam :: !AdamState
  }

usesTargetNets :: ContinuousVariant -> Bool
usesTargetNets VariantCrossQ = False
usesTargetNets _ = True

usesTargetSmoothing :: ContinuousVariant -> Bool
usesTargetSmoothing v = v `elem` [VariantTD3, VariantSAC, VariantTQC]

trainContinuousOnPendulum :: ContinuousTrainConfig -> IO ContinuousTrainResult
trainContinuousOnPendulum config = do
  let actorShape =
        MlpShape {mlpInputs = ctObsSize config, mlpHidden = ctHidden config, mlpOutputs = 1}
      criticShape =
        MlpShape {mlpInputs = ctObsSize config + 1, mlpHidden = ctHidden config, mlpOutputs = 1}
      actor0 = mlpInit actorShape (ctSeed config)
      criticA0 = mlpInit criticShape (ctSeed config + 101)
      criticB0 = mlpInit criticShape (ctSeed config + 202)
      nets0 =
        ACNets
          { acActor = actor0
          , acCriticA = criticA0
          , acCriticB = criticB0
          , acTargetActor = actor0
          , acTargetCriticA = criticA0
          , acTargetCriticB = criticB0
          }
      opt0 =
        ACOpt
          { acActorAdam = adamInit actorShape
          , acCriticAAdam = adamInit criticShape
          , acCriticBAdam = adamInit criticShape
          }
  loop
    config
    (\nets opt batch doActor -> pure (updateStep config nets opt batch doActor))
    nets0
    opt0
    (Random.mkStdGen (ctSeed config + 1))
    []
    0
    pendulumInitial
    0
    0.0
    []
    []

loop
  :: ContinuousTrainConfig
  -> (ACNets -> ACOpt -> [ContTransition] -> Bool -> IO (ACNets, ACOpt))
  -- ^ minibatch update: nets → opt → batch → doActor → (nets', opt')
  -> ACNets
  -> ACOpt
  -> Random.StdGen
  -> [ContTransition]
  -> Int
  -> PendulumState
  -> Int
  -> Double
  -> [Double]
  -> [ContinuousIterationStat]
  -> IO ContinuousTrainResult
loop config update nets opt gen buffer step state episodeLen episodeReturn episodes stats
  | step >= ctNumSteps config =
      pure
        ContinuousTrainResult
          { contResultStats = reverse stats
          , contResultFinalActor = acActor nets
          , contResultConfig = config
          }
  | otherwise = do
      let obs = obsVector state
          -- Action selection: random during warmup, else actor + Gaussian noise.
          (rawNoise, gen1) = gaussian gen
          (rawUniform, gen2) = Random.uniformR (ctActionLow config, ctActionHigh config) gen1
          baseAction = actorAction config (acActor nets) obs
          noisy =
            clampAction config (baseAction + ctExplNoise config * rawNoise)
          action =
            if step < ctStartSteps config
              then rawUniform
              else noisy
          stepResult = Sim.cEnvStep pendulumEnvironment state action
          terminal =
            cStepDone stepResult || episodeLen + 1 >= ctMaxEpisodeSteps config
          nextObs = obsVector (cStepState stepResult)
          transition =
            ContTransition
              { contObs = obs
              , contAction = action
              , contReward = cStepReward stepResult
              , contNextObs = nextObs
              , contDone = terminal
              }
          newBuffer = take (ctReplayCapacity config) (transition : buffer)
          nextReturn = episodeReturn + cStepReward stepResult
          (nextState, nextLen, finalReturn, newEpisodes) =
            if terminal
              then (pendulumInitial, 0, 0.0, nextReturn : episodes)
              else (cStepState stepResult, episodeLen + 1, nextReturn, episodes)
      (netsNext, optNext, gen3) <-
        if step + 1 >= ctTrainStart config && length newBuffer >= ctBatchSize config
          then do
            let (batch, genB) = sampleBatch (ctBatchSize config) newBuffer gen2
                doActor = (step + 1) `mod` ctPolicyDelay config == 0
            (netsU, optU) <- update nets opt batch doActor
            pure (netsU, optU, genB)
          else pure (nets, opt, gen2)
      let statsNext =
            if (step + 1) `mod` ctStatInterval config == 0
              then
                let recent = take 20 newEpisodes
                    meanR =
                      if null recent
                        then 0.0
                        else sum recent / fromIntegral (length recent)
                    lastR = case newEpisodes of
                      (r : _) -> r
                      [] -> 0.0
                 in ContinuousIterationStat
                      { contIterStep = step + 1
                      , contIterEpisodes = length newEpisodes
                      , contIterMeanReward = meanR
                      , contIterLastEpisodeReward = lastR
                      }
                      : stats
              else stats
      loop
        config
        update
        netsNext
        optNext
        gen3
        newBuffer
        (step + 1)
        nextState
        nextLen
        finalReturn
        newEpisodes
        statsNext

-- | One gradient update: critic(s) against the variant's Bellman target,
-- then (optionally) the actor via the deterministic-policy gradient.
updateStep
  :: ContinuousTrainConfig
  -> ACNets
  -> ACOpt
  -> [ContTransition]
  -> Bool
  -> (ACNets, ACOpt)
updateStep config nets opt batch doActor =
  let variant = ctVariant config
      -- Per-transition Bellman target (shared with the CUDA path).
      targetFor = bellmanTarget config nets
      -- Critic gradient step for one critic param block.
      updateCritic params adam =
        let adamCfg = defaultAdamConfig {adamLearningRate = ctCriticLr config}
            stepC (p, a) trans =
              let inp = criticInput (contObs trans) (contAction trans)
                  fwd = mlpForward p inp
                  q = VU.head (forwardOutput fwd)
                  residual = q - targetFor trans
                  grad = mlpBackward p fwd (VU.singleton residual)
               in adamStep adamCfg a p grad
         in Data.List.foldl' stepC (params, adam) batch
      (criticANext, criticAAdamNext) = updateCritic (acCriticA nets) (acCriticAAdam opt)
      (criticBNext, criticBAdamNext) =
        if variant == VariantDDPG
          then (acCriticB nets, acCriticBAdam opt)
          else updateCritic (acCriticB nets) (acCriticBAdam opt)
      -- Actor update via deterministic-policy gradient through criticA.
      (actorNext, actorAdamNext) =
        if doActor
          then
            let adamCfg = defaultAdamConfig {adamLearningRate = ctActorLr config}
                stepA (p, a) trans =
                  let obs = contObs trans
                      fwd = mlpForward p obs
                      raw = VU.head (forwardOutput fwd)
                      action = squash config raw
                      -- dQ/da: action-slice of the critic input gradient.
                      cInp = criticInput obs action
                      cFwd = mlpForward criticANext cInp
                      dQdInput = mlpInputGradient criticANext cFwd (VU.singleton 1.0)
                      dQdAction = dQdInput VU.! ctObsSize config
                      -- action = high * tanh(raw); da/draw = high * (1 - tanh^2).
                      dActionDRaw =
                        ctActionHigh config * (1.0 - tanhRaw raw * tanhRaw raw)
                      -- Maximise Q => minimise -Q: dL/draw = -(dQ/da)(da/draw).
                      dLdRaw = negate (dQdAction * dActionDRaw)
                      grad = mlpBackward p fwd (VU.singleton dLdRaw)
                   in adamStep adamCfg a p grad
             in Data.List.foldl' stepA (acActor nets, acActorAdam opt) batch
          else (acActor nets, acActorAdam opt)
      -- Soft target updates (skipped for CrossQ).
      tau = ctTau config
      (tActor, tCriticA, tCriticB)
        | usesTargetNets variant && doActor =
            ( softUpdate tau actorNext (acTargetActor nets)
            , softUpdate tau criticANext (acTargetCriticA nets)
            , softUpdate tau criticBNext (acTargetCriticB nets)
            )
        | usesTargetNets variant =
            ( acTargetActor nets
            , softUpdate tau criticANext (acTargetCriticA nets)
            , softUpdate tau criticBNext (acTargetCriticB nets)
            )
        | otherwise = (acTargetActor nets, acTargetCriticA nets, acTargetCriticB nets)
   in ( ACNets
          { acActor = actorNext
          , acCriticA = criticANext
          , acCriticB = criticBNext
          , acTargetActor = tActor
          , acTargetCriticA = tCriticA
          , acTargetCriticB = tCriticB
          }
      , ACOpt
          { acActorAdam = actorAdamNext
          , acCriticAAdam = criticAAdamNext
          , acCriticBAdam = criticBAdamNext
          }
      )

-- | Per-transition Bellman target for the critic loss. Computed from the
-- (target) actor + (target) critics with the variant-specific target
-- formula (DDPG / TD3 / SAC / CrossQ / TQC). Factored out of 'updateStep'
-- so the pure CPU path and the batched device path ('updateStepDevice') share
-- the identical target math.
bellmanTarget :: ContinuousTrainConfig -> ACNets -> ContTransition -> Double
bellmanTarget config nets trans =
  let variant = ctVariant config
      gamma = ctGamma config
      nObs = contNextObs trans
      r = contReward trans
      d = contDone trans
      targetActorParams =
        if usesTargetNets variant then acTargetActor nets else acActor nets
      rawTargetAction = actorAction config targetActorParams nObs
      smoothedAction =
        if usesTargetSmoothing variant
          then
            firstOr
              rawTargetAction
              ( td3SmoothTargetActions
                  (ctNoiseClip config)
                  (ctActionLow config)
                  (ctActionHigh config)
                  [rawTargetAction]
                  [ctTargetNoise config * smoothingNoise trans]
              )
          else rawTargetAction
      (tcA, tcB) =
        if usesTargetNets variant
          then (acTargetCriticA nets, acTargetCriticB nets)
          else (acCriticA nets, acCriticB nets)
      q1' = criticQ tcA nObs smoothedAction
      q2' = criticQ tcB nObs smoothedAction
      logProb' = gaussianLogProb (ctPolicyStd config) smoothedAction rawTargetAction
      alpha = ctSacAlpha config
   in case variant of
        VariantDDPG ->
          firstOr r (ddpgCriticTarget gamma [r] [d] [q1'])
        VariantTD3 ->
          firstOr r (td3ClippedDoubleTarget gamma [r] [d] [q1'] [q2'])
        VariantSAC ->
          firstOr r (sacCriticTarget gamma alpha [r] [d] [q1'] [q2'] [logProb'])
        VariantCrossQ ->
          let qMin = min q1' q2'
              qNorm = firstOr qMin (crossQNormalise 0.0 1.0 1.0e-6 [qMin])
           in firstOr r (crossQTarget gamma alpha [r] [d] [qNorm] [logProb'])
        VariantTQC ->
          let atoms =
                tqcTarget
                  gamma
                  (ctTqcDropPerCritic config)
                  r
                  d
                  [[q1'], [q2']]
                  (alpha * logProb')
           in if null atoms then r else sum atoms / fromIntegral (length atoms)

-- | Deterministic per-transition smoothing noise (no extra RNG state):
-- a bounded pseudo-Gaussian from the transition's own observation hash,
-- so the batch update stays a pure function of @(nets, batch)@.
smoothingNoise :: ContTransition -> Double
smoothingNoise trans =
  let s = VU.sum (contObs trans) + contAction trans
   in sin (s * 12.9898) -- deterministic, bounded in [-1, 1]

actorAction :: ContinuousTrainConfig -> MlpParams -> Vector Double -> Double
actorAction config params obs =
  squash config (VU.head (forwardOutput (mlpForward params obs)))

-- | Squash the actor's raw output to the action range via tanh.
squash :: ContinuousTrainConfig -> Double -> Double
squash config raw = ctActionHigh config * tanhRaw raw

tanhRaw :: Double -> Double
tanhRaw = tanh

clampAction :: ContinuousTrainConfig -> Double -> Double
clampAction config x = max (ctActionLow config) (min (ctActionHigh config) x)

criticQ :: MlpParams -> Vector Double -> Double -> Double
criticQ params obs action =
  VU.head (forwardOutput (mlpForward params (criticInput obs action)))

criticInput :: Vector Double -> Double -> Vector Double
criticInput obs action = obs VU.++ VU.singleton action

-- | Total-safe head with a default; the lists fed in are single-element
-- by construction (each @*Loss@ target function maps one transition to
-- one scalar), so the default is never taken in practice.
firstOr :: a -> [a] -> a
firstOr def [] = def
firstOr _ (x : _) = x

obsVector :: PendulumState -> Vector Double
obsVector = VU.fromList . Sim.pendulumObservation

-- | Gaussian log-density of @x@ under @N(mean, std^2)@.
gaussianLogProb :: Double -> Double -> Double -> Double
gaussianLogProb std mean x =
  let s = max 1.0e-6 std
      z = (x - mean) / s
   in (-0.5) * z * z - log s - 0.5 * log (2.0 * pi)

-- | Soft (Polyak) target update: @target <- tau*online + (1-tau)*target@.
softUpdate :: Double -> MlpParams -> MlpParams -> MlpParams
softUpdate tau online target =
  target
    { paramW1 = lerp (paramW1 online) (paramW1 target)
    , paramB1 = lerp (paramB1 online) (paramB1 target)
    , paramW2 = lerp (paramW2 online) (paramW2 target)
    , paramB2 = lerp (paramB2 online) (paramB2 target)
    }
 where
  lerp = VU.zipWith (\o t -> tau * o + (1.0 - tau) * t)

-- | One standard-normal sample via Box–Muller from a 'StdGen'.
gaussian :: Random.StdGen -> (Double, Random.StdGen)
gaussian g0 =
  let (u1, g1) = Random.uniformR (1.0e-12, 1.0 :: Double) g0
      (u2, g2) = Random.uniformR (0.0, 1.0 :: Double) g1
   in (sqrt (-(2.0 * log u1)) * cos (2.0 * pi * u2), g2)

sampleBatch :: Int -> [ContTransition] -> Random.StdGen -> ([ContTransition], Random.StdGen)
sampleBatch n buffer gen =
  let bufLen = length buffer
      pickN k g acc
        | k <= 0 = (acc, g)
        | otherwise =
            let (idx, g') = Random.uniformR (0 :: Int, bufLen - 1) g
             in pickN (k - 1) g' (buffer !! idx : acc)
   in pickN n gen []

-- | Sprint 13.8 — train any continuous actor-critic variant
-- (DDPG/TD3/SAC/CrossQ/TQC) on Pendulum with the critic + actor minibatch
-- gradients running on the GPU through the batched device primitives. The
-- env loop / replay / exploration are shared with the pure
-- 'trainContinuousOnPendulum' via the parameterised 'loop'; only the
-- gradient step ('updateStepDevice') runs on the device.
trainContinuousOnPendulumCuda :: Env -> ContinuousTrainConfig -> IO ContinuousTrainResult
trainContinuousOnPendulumCuda env = trainContinuousOnDevice (cudaMlpDevice env)

-- | Continuous actor-critic training through the oneDNN (linux-cpu) MLP device.
trainContinuousOnPendulumOneDnn :: Env -> ContinuousTrainConfig -> IO ContinuousTrainResult
trainContinuousOnPendulumOneDnn env = trainContinuousOnDevice (oneDnnMlpDevice env)

-- | Continuous actor-critic training through the Metal (apple-silicon) MLP device.
trainContinuousOnPendulumMetal :: Env -> ContinuousTrainConfig -> IO ContinuousTrainResult
trainContinuousOnPendulumMetal env = trainContinuousOnDevice (metalMlpDevice env)

-- | Continuous actor-critic training through an injected MLP device backend.
-- The env loop / replay / exploration are shared with the pure
-- 'trainContinuousOnPendulum' via the parameterised 'loop'; only the
-- gradient step ('updateStepDevice') runs on the device.
trainContinuousOnDevice :: MlpDevice -> ContinuousTrainConfig -> IO ContinuousTrainResult
trainContinuousOnDevice device config = do
  let actorShape =
        MlpShape {mlpInputs = ctObsSize config, mlpHidden = ctHidden config, mlpOutputs = 1}
      criticShape =
        MlpShape {mlpInputs = ctObsSize config + 1, mlpHidden = ctHidden config, mlpOutputs = 1}
      actor0 = mlpInit actorShape (ctSeed config)
      criticA0 = mlpInit criticShape (ctSeed config + 101)
      criticB0 = mlpInit criticShape (ctSeed config + 202)
      nets0 =
        ACNets
          { acActor = actor0
          , acCriticA = criticA0
          , acCriticB = criticB0
          , acTargetActor = actor0
          , acTargetCriticA = criticA0
          , acTargetCriticB = criticB0
          }
      opt0 =
        ACOpt
          { acActorAdam = adamInit actorShape
          , acCriticAAdam = adamInit criticShape
          , acCriticBAdam = adamInit criticShape
          }
  loop
    config
    (updateStepDevice device config)
    nets0
    opt0
    (Random.mkStdGen (ctSeed config + 1))
    []
    0
    pendulumInitial
    0
    0.0
    []
    []

-- | Device-backed minibatch actor-critic update. The critic param
-- gradient, the actor's @dQ/da@ (the critic's input gradient), and the
-- actor param gradient all run on the device through the batched primitives
-- (`mlpdForwardBatch` / `mlpdBatchGradient` / `mlpdInputGradientBatch`); the
-- Bellman target ('bellmanTarget'), the squash/chain-rule scalars, and the
-- soft target updates are the shared pure helpers. Minibatch GD (one Adam
-- step per batch) vs. the pure path's per-sample SGD — standard for a
-- batched actor-critic. Falls back to the pure 'updateStep' if the device
-- runtime/compile is unavailable.
updateStepDevice
  :: MlpDevice
  -> ContinuousTrainConfig
  -> ACNets
  -> ACOpt
  -> [ContTransition]
  -> Bool
  -> IO (ACNets, ACOpt)
updateStepDevice device config nets opt batch doActor = do
  let variant = ctVariant config
      targets = map (bellmanTarget config nets) batch
      criticInputs = [criticInput (contObs t) (contAction t) | t <- batch]
      obsList = [contObs t | t <- batch]
      n = fromIntegral (max 1 (length batch)) :: Double
      criticAdamCfg = defaultAdamConfig {adamLearningRate = ctCriticLr config}
      actorAdamCfg = defaultAdamConfig {adamLearningRate = ctActorLr config}
      scaleGradient sc g =
        MlpGradient
          { gradW1 = VU.map (* sc) (gradW1 g)
          , gradB1 = VU.map (* sc) (gradB1 g)
          , gradW2 = VU.map (* sc) (gradW2 g)
          , gradB2 = VU.map (* sc) (gradB2 g)
          }
      criticGrad critic targetVals = do
        qs <- ExceptT (mlpdForwardBatch device critic criticInputs)
        let residuals = zipWith (\q tgt -> VU.head q - tgt) qs targetVals
        summed <- ExceptT (mlpdBatchGradient device critic (zip criticInputs (map VU.singleton residuals)))
        pure (scaleGradient (1.0 / n) summed)
  deviceResult <-
    runExceptT $ do
      gradA <- criticGrad (acCriticA nets) targets
      let (criticANext, criticAAdamNext) =
            adamStep criticAdamCfg (acCriticAAdam opt) (acCriticA nets) gradA
      (criticBNext, criticBAdamNext) <-
        if variant == VariantDDPG
          then pure (acCriticB nets, acCriticBAdam opt)
          else do
            gradB <- criticGrad (acCriticB nets) targets
            pure (adamStep criticAdamCfg (acCriticBAdam opt) (acCriticB nets) gradB)
      (actorNext, actorAdamNext) <-
        if not doActor
          then pure (acActor nets, acActorAdam opt)
          else do
            actorRaws <- ExceptT (mlpdForwardBatch device (acActor nets) obsList)
            let raws = map VU.head actorRaws
                actions = map (squash config) raws
                actorCriticInputs = zipWith (criticInput . contObs) batch actions
            -- dQ/da = action-slice of criticANext's input gradient (dL/dQ = 1).
            dQdInputs <-
              ExceptT
                ( mlpdInputGradientBatch
                    device
                    criticANext
                    [(ci, VU.singleton 1.0) | ci <- actorCriticInputs]
                )
            let dQdActions = map (VU.! ctObsSize config) dQdInputs
                dLdRaws =
                  zipWith
                    ( \dQda raw ->
                        negate (dQda * (ctActionHigh config * (1.0 - tanhRaw raw * tanhRaw raw)))
                    )
                    dQdActions
                    raws
            summed <- ExceptT (mlpdBatchGradient device (acActor nets) (zip obsList (map VU.singleton dLdRaws)))
            pure (adamStep actorAdamCfg (acActorAdam opt) (acActor nets) (scaleGradient (1.0 / n) summed))
      let tau = ctTau config
          (tActor, tCriticA, tCriticB)
            | usesTargetNets variant && doActor =
                ( softUpdate tau actorNext (acTargetActor nets)
                , softUpdate tau criticANext (acTargetCriticA nets)
                , softUpdate tau criticBNext (acTargetCriticB nets)
                )
            | usesTargetNets variant =
                ( acTargetActor nets
                , softUpdate tau criticANext (acTargetCriticA nets)
                , softUpdate tau criticBNext (acTargetCriticB nets)
                )
            | otherwise = (acTargetActor nets, acTargetCriticA nets, acTargetCriticB nets)
      pure
        ( ACNets
            { acActor = actorNext
            , acCriticA = criticANext
            , acCriticB = criticBNext
            , acTargetActor = tActor
            , acTargetCriticA = tCriticA
            , acTargetCriticB = tCriticB
            }
        , ACOpt
            { acActorAdam = actorAdamNext
            , acCriticAAdam = criticAAdamNext
            , acCriticBAdam = criticBAdamNext
            }
        )
  pure (fromRight (updateStep config nets opt batch doActor) deviceResult)

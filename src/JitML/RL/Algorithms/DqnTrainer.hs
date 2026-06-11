-- | Sprint 13.8 — real DQN-style off-policy training loop that closes
-- the network forward/backward seam for the off-policy half of the
-- 14-algorithm catalog (DQN, QR-DQN, DDPG, TD3, SAC, CrossQ, TQC).
--
-- The trainer wires:
--
--   * online Q network: MLP from "JitML.Numerics.Mlp"
--   * target Q network: periodic hard copy of the online net
--   * replay buffer: ring buffer of @(obs, action, reward, next_obs, done)@
--   * Bellman residual: from "JitML.RL.Algorithms.DqnLoss"
--   * epsilon-greedy exploration over the action space
--   * Adam optimiser for the online net
--
-- Each off-policy algorithm in the catalog plugs in its own
-- algorithm-specific Bellman target (Double-DQN, QR-DQN quantile
-- target, TD3 twin-min target, SAC soft target) by replacing
-- 'targetFromOnline' with the algorithm's variant. The trainer's
-- forward/backward and replay buffer surface is the same across all
-- 7 off-policy algorithms; the variation is the target formula.
--
-- Bit-deterministic on the same substrate / same seed (pure Haskell
-- chain-rule backprop, seeded 'StdGen').
module JitML.RL.Algorithms.DqnTrainer
  ( DqnTrainConfig (..)
  , defaultDqnTrainConfig
  , DqnTrainResult (..)
  , DqnIterationStat (..)
  , Transition (..)
  , trainDqnOnCartpole
  , trainDqnOnCartpoleCuda
  , trainDqnOnCartpoleOneDnn
  , trainDqnOnCartpoleMetal
  , trainDqnOnDevice
  )
where

import Data.List qualified
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
  , adamInit
  , adamStep
  , defaultAdamConfig
  , forwardOutput
  , mlpBackward
  , mlpForward
  , mlpInit
  )
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.Algorithms.DqnLoss qualified as DqnLoss
import JitML.RL.Simulator
  ( CartPoleState (..)
  , SimStep (..)
  , cartPoleInitial
  , cartPoleStep
  )

-- | DQN training configuration.
data DqnTrainConfig = DqnTrainConfig
  { dqnSeed :: !Int
  , dqnHiddenUnits :: !Int
  , dqnNumSteps :: !Int -- total env steps in the run
  , dqnReplayCapacity :: !Int
  , dqnBatchSize :: !Int
  , dqnLearningRate :: !Double
  , dqnGamma :: !Double
  , dqnTargetUpdateInterval :: !Int
  , dqnEpsilonStart :: !Double
  , dqnEpsilonEnd :: !Double
  , dqnEpsilonDecaySteps :: !Int
  , dqnTrainStart :: !Int -- begin gradient updates after this many env steps
  , dqnUpdateFrequency :: !Int
  , dqnMaxEpisodeSteps :: !Int
  , dqnActionCount :: !Int
  , dqnObsSize :: !Int
  , dqnStatInterval :: !Int -- emit a stat every N env steps
  , dqnUseDouble :: !Bool -- Double-DQN target (van Hasselt 2016) when True
  }
  deriving stock (Eq, Show)

defaultDqnTrainConfig :: DqnTrainConfig
defaultDqnTrainConfig =
  DqnTrainConfig
    { dqnSeed = 42
    , dqnHiddenUnits = 128
    , dqnNumSteps = 20000
    , dqnReplayCapacity = 10000
    , dqnBatchSize = 64
    , dqnLearningRate = 1.0e-3
    , dqnGamma = 0.99
    , dqnTargetUpdateInterval = 250
    , dqnEpsilonStart = 1.0
    , dqnEpsilonEnd = 0.02
    , dqnEpsilonDecaySteps = 10000
    , dqnTrainStart = 1000
    , dqnUpdateFrequency = 1
    , dqnMaxEpisodeSteps = 500
    , dqnActionCount = 2
    , dqnObsSize = 4
    , dqnStatInterval = 1000
    , dqnUseDouble = False
    }

data Transition = Transition
  { transObs :: !(Vector Double)
  , transAction :: !Int
  , transReward :: !Double
  , transNextObs :: !(Vector Double)
  , transDone :: !Bool
  }
  deriving stock (Eq, Show)

data DqnIterationStat = DqnIterationStat
  { dqnIterStep :: !Int
  , dqnIterEpisodes :: !Int
  , dqnIterMeanReward :: !Double
  , dqnIterLastEpisodeReward :: !Double
  }
  deriving stock (Eq, Show)

data DqnTrainResult = DqnTrainResult
  { dqnResultStats :: ![DqnIterationStat]
  , dqnResultFinalParams :: !MlpParams
  , dqnResultConfig :: !DqnTrainConfig
  }
  deriving stock (Eq, Show)

trainDqnOnCartpole :: DqnTrainConfig -> IO DqnTrainResult
trainDqnOnCartpole config = do
  let shape =
        MlpShape
          { mlpInputs = dqnObsSize config
          , mlpHidden = dqnHiddenUnits config
          , mlpOutputs = dqnActionCount config
          }
      initialParams = mlpInit shape (dqnSeed config)
  -- Replay buffer carried as a list (ring-buffer semantics via take + cons).
  loop
    config
    (\online target adam batch -> pure (dqnUpdate config online target adam batch))
    initialParams
    initialParams
    (adamInit shape)
    (Random.mkStdGen (dqnSeed config + 1))
    []
    0
    cartPoleInitial
    0
    0.0
    [] -- per-episode return list
    [] -- iteration stats

loop
  :: DqnTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (MlpParams, AdamState))
  -- ^ minibatch update: online → target → adam → batch → (online', adam')
  -> MlpParams -- online net
  -> MlpParams -- target net
  -> AdamState
  -> Random.StdGen
  -> [Transition] -- replay buffer (most-recent first)
  -> Int -- step counter
  -> CartPoleState
  -> Int -- current episode step count
  -> Double -- current episode return
  -> [Double] -- recent episode returns
  -> [DqnIterationStat]
  -> IO DqnTrainResult
loop config update online target adam gen buffer step state episodeLen episodeReturn episodes stats
  | step >= dqnNumSteps config =
      pure
        DqnTrainResult
          { dqnResultStats = reverse stats
          , dqnResultFinalParams = online
          , dqnResultConfig = config
          }
  | otherwise = do
      let epsilon = currentEpsilon config step
          obs = obsVector state
          (u, gen1) = Random.uniformR (0.0 :: Double, 1.0) gen
          (actionU, gen2) =
            Random.uniformR (0 :: Int, dqnActionCount config - 1) gen1
          qValues =
            VU.toList
              (forwardOutput (mlpForward online obs))
          greedyAction =
            argmax qValues
          action =
            if u < epsilon
              then actionU
              else greedyAction
          stepResult = cartPoleStep state action
          -- True environment termination (pole fell / out of bounds). Only
          -- this stops Bellman bootstrapping.
          envDone = simStepDone stepResult
          -- Episode reset also fires on the time limit, but a time-limit
          -- truncation is NOT a terminal state: bootstrapping must continue
          -- through it, otherwise the net learns that long-survival states
          -- are worth only their immediate reward and never reaches 500.
          timeLimit = episodeLen + 1 >= dqnMaxEpisodeSteps config
          terminal = envDone || timeLimit
          nextObs = obsVector (simStepState stepResult)
          transition =
            Transition
              { transObs = obs
              , transAction = action
              , transReward = simStepReward stepResult
              , transNextObs = nextObs
              , transDone = envDone
              }
          newBuffer =
            take (dqnReplayCapacity config) (transition : buffer)
          nextEpisodeReturn = episodeReturn + simStepReward stepResult
          (nextState, nextEpisodeLen, finalReturn, newEpisodes) =
            if terminal
              then
                ( cartPoleInitial
                , 0
                , 0.0
                , nextEpisodeReturn : episodes
                )
              else
                ( simStepState stepResult
                , episodeLen + 1
                , nextEpisodeReturn
                , episodes
                )
      -- Do a gradient update if we've collected enough transitions.
      (onlineNext, adamNext, gen3) <-
        if step + 1 >= dqnTrainStart config
          && (step + 1) `mod` dqnUpdateFrequency config == 0
          && length newBuffer >= dqnBatchSize config
          then do
            let (batch, gen2b) =
                  sampleBatch (dqnBatchSize config) newBuffer gen2
            (onlineUpd, adamUpd) <- update online target adam batch
            pure (onlineUpd, adamUpd, gen2b)
          else pure (online, adam, gen2)
      -- Periodic target-net hard copy.
      let targetNext =
            if (step + 1) `mod` dqnTargetUpdateInterval config == 0
              then onlineNext
              else target
      -- Record stat at intervals.
      let statsNext =
            if (step + 1) `mod` dqnStatInterval config == 0
              then
                let recent = take 100 newEpisodes
                    meanR =
                      if null recent
                        then 0.0
                        else sum recent / fromIntegral (length recent)
                    lastR = case newEpisodes of
                      (r : _) -> r
                      [] -> 0.0
                 in DqnIterationStat
                      { dqnIterStep = step + 1
                      , dqnIterEpisodes = length newEpisodes
                      , dqnIterMeanReward = meanR
                      , dqnIterLastEpisodeReward = lastR
                      }
                      : stats
              else stats
      loop
        config
        update
        onlineNext
        targetNext
        adamNext
        gen3
        newBuffer
        (step + 1)
        nextState
        nextEpisodeLen
        finalReturn
        newEpisodes
        statsNext

currentEpsilon :: DqnTrainConfig -> Int -> Double
currentEpsilon config step =
  let frac =
        min
          1.0
          (fromIntegral step / fromIntegral (max 1 (dqnEpsilonDecaySteps config)))
   in dqnEpsilonStart config
        + frac
          * (dqnEpsilonEnd config - dqnEpsilonStart config)

sampleBatch :: Int -> [Transition] -> Random.StdGen -> ([Transition], Random.StdGen)
sampleBatch n buffer gen =
  let bufLen = length buffer
      bufArr = buffer
      pickN k g acc
        | k <= 0 = (acc, g)
        | otherwise =
            let (idx, g') = Random.uniformR (0 :: Int, bufLen - 1) g
             in pickN (k - 1) g' (bufArr !! idx : acc)
   in pickN n gen []

argmax :: (Ord a) => [a] -> Int
argmax [] = 0
argmax xs = snd (foldr1 step (zip xs [0 ..]))
 where
  step (v1, i1) (v2, i2)
    | v1 >= v2 = (v1, i1)
    | otherwise = (v2, i2)

-- | DQN gradient update on a single batch.
dqnUpdate
  :: DqnTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> [Transition]
  -> (MlpParams, AdamState)
dqnUpdate config online target adam batch =
  let adamConfig =
        defaultAdamConfig {adamLearningRate = dqnLearningRate config}
      -- All per-sample gradients are evaluated at the *same* online params
      -- (a true minibatch gradient), then averaged for one Adam step. This
      -- matches the batched CUDA path ('dqnUpdateCuda') exactly and is the
      -- standard DQN update — the previous per-transition Adam step (one
      -- optimiser step per batch element) over-fit each minibatch and
      -- destabilised learning.
      perSampleGradient trans =
        let fwd = mlpForward online (transObs trans)
            qVec = VU.toList (forwardOutput fwd)
            nextQ = VU.toList (forwardOutput (mlpForward target (transNextObs trans)))
            onlineNextQ = VU.toList (forwardOutput (mlpForward online (transNextObs trans)))
            dLdy = dqnResidualDLdy config qVec nextQ onlineNextQ trans
         in mlpBackward online fwd dLdy
      scale = 1.0 / fromIntegral (max 1 (length batch))
      meanGradient = scaleGradient scale (sumGradients (map perSampleGradient batch))
   in adamStep adamConfig adam online meanGradient

-- | The per-transition DQN loss gradient w.r.t. the Q-network output: the
-- TD residual @Q(s,a) - target@ placed at the taken-action index, zero
-- elsewhere. The Bellman target uses the target net's next-state Q
-- (@nextQ@); Double-DQN (van Hasselt et al. 2016) selects the next action
-- with the online net (@onlineNextQ@, forced only when @dqnUseDouble@) and
-- evaluates it with the target net. Factored out of 'dqnUpdate' so the
-- pure CPU path and the batched CUDA path ('dqnUpdateCuda') compute the
-- identical loss gradient; only the backward backend differs.
dqnResidualDLdy
  :: DqnTrainConfig
  -> [Double]
  -- ^ online Q(s, ·)
  -> [Double]
  -- ^ target net Q(s', ·)
  -> [Double]
  -- ^ online Q(s', ·) (Double-DQN action selection; lazy)
  -> Transition
  -> Vector Double
dqnResidualDLdy config qVec nextQ onlineNextQ trans =
  VU.generate (length qVec) (\i -> if i == actionIx then residual else 0.0)
 where
  actionIx = transAction trans
  qSa
    | actionIx >= 0 && actionIx < length qVec = qVec !! actionIx
    | otherwise = 0.0
  bootstrapNextQ
    | dqnUseDouble config =
        let onlineArgmax = argmax onlineNextQ
         in if onlineArgmax >= 0 && onlineArgmax < length nextQ
              then nextQ !! onlineArgmax
              else 0.0
    | otherwise = maximum (0 : nextQ)
  tdTarget =
    ( if dqnUseDouble config
        then DqnLoss.dqnDoubleBellmanTarget
        else DqnLoss.dqnBellmanTarget
    )
      (dqnGamma config)
      (transReward trans)
      (transDone trans)
      bootstrapNextQ
  residual = qSa - tdTarget

-- | Sum a non-empty list of MLP gradients component-wise. Used to form the
-- minibatch gradient before averaging in 'dqnUpdate'.
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

obsVector :: CartPoleState -> Vector Double
obsVector state =
  VU.fromList
    [ cartPosition state
    , cartVelocity state
    , poleAngle state
    , poleAngularVelocity state
    ]

-- | Sprint 13.8 — train DQN (and the discrete off-policy family it
-- templates) on cartpole with the Q-network forward + backward running on
-- the GPU through the batched device primitives. The env loop, replay
-- buffer, epsilon-greedy, and target-net copy are unchanged (shared with
-- the pure 'trainDqnOnCartpole' via the parameterised 'loop'); only the
-- minibatch gradient update runs on the device ('dqnUpdateCuda'). The
-- loss-gradient head ('dqnResidualDLdy') is shared with the pure path.
trainDqnOnCartpoleCuda :: Env -> DqnTrainConfig -> IO DqnTrainResult
trainDqnOnCartpoleCuda env = trainDqnOnDevice (cudaMlpDevice env)

-- | DQN training through the oneDNN (linux-cpu) MLP device.
trainDqnOnCartpoleOneDnn :: Env -> DqnTrainConfig -> IO DqnTrainResult
trainDqnOnCartpoleOneDnn env = trainDqnOnDevice (oneDnnMlpDevice env)

-- | DQN training through the Metal (apple-silicon) MLP device.
trainDqnOnCartpoleMetal :: Env -> DqnTrainConfig -> IO DqnTrainResult
trainDqnOnCartpoleMetal env = trainDqnOnDevice (metalMlpDevice env)

-- | DQN training through an injected MLP device backend. The env loop, replay
-- buffer, epsilon-greedy, and target-net copy are shared with the pure
-- 'trainDqnOnCartpole' via the parameterised 'loop'; only the minibatch
-- gradient update runs on the device ('dqnUpdateDevice').
trainDqnOnDevice :: MlpDevice -> DqnTrainConfig -> IO DqnTrainResult
trainDqnOnDevice device config = do
  let shape =
        MlpShape
          { mlpInputs = dqnObsSize config
          , mlpHidden = dqnHiddenUnits config
          , mlpOutputs = dqnActionCount config
          }
      initialParams = mlpInit shape (dqnSeed config)
  loop
    config
    (dqnUpdateDevice device config)
    initialParams
    initialParams
    (adamInit shape)
    (Random.mkStdGen (dqnSeed config + 1))
    []
    0
    cartPoleInitial
    0
    0.0
    []
    []

-- | Minibatch DQN gradient update through the batched CUDA primitives:
-- batched forward of the online net at the batch states (Q(s,·)) and the
-- target net at the next states (Q(s',·)) — plus the online net at the
-- next states for Double-DQN action selection — then the per-sample TD
-- residual gradient ('dqnResidualDLdy'), one batched device backward (mean
-- gradient over the minibatch), and one Adam step. Fails closed on a device
-- `Left` (Sprint 8.11) — the dispatch `probeMlpDevice` gate already confirmed
-- the kernel runs, so a mid-run fault is genuine, not a pure-fallback cue.
-- (Minibatch GD vs. the pure path's per-sample online SGD — standard for a
-- batched DQN.)
dqnUpdateDevice
  :: MlpDevice
  -> DqnTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> [Transition]
  -> IO (MlpParams, AdamState)
dqnUpdateDevice device config online target adam batch = do
  let obsList = map transObs batch
      nextObsList = map transNextObs batch
  onlineQE <- mlpdForwardBatch device online obsList
  targetQE <- mlpdForwardBatch device target nextObsList
  onlineNextQE <-
    if dqnUseDouble config
      then mlpdForwardBatch device online nextObsList
      else pure (Right (map (const VU.empty) batch))
  case (onlineQE, targetQE, onlineNextQE) of
    (Right onlineQs, Right targetQs, Right onlineNextQs) -> do
      let pairs =
            [ ( transObs trans
              , dqnResidualDLdy config (VU.toList qv) (VU.toList nq) (VU.toList onq) trans
              )
            | (trans, qv, nq, onq) <- Data.List.zip4 batch onlineQs targetQs onlineNextQs
            ]
      gradResult <- mlpdBatchGradient device online pairs
      case gradResult of
        Right summed ->
          let scale = 1.0 / fromIntegral (length batch)
              meanGradient = scaleGradient scale summed
              adamConfig = defaultAdamConfig {adamLearningRate = dqnLearningRate config}
              (onlineAfter, adamAfter) = adamStep adamConfig adam online meanGradient
           in pure (onlineAfter, adamAfter)
        -- Sprint 8.11 — fail closed: the dispatch-level `probeMlpDevice` gate
        -- guarantees the kernel compiles/runs before training starts, so a
        -- mid-run device `Left` is a genuine fault, not a cue to silently
        -- degrade to the pure update.
        Left err -> error ("dqn device gradient kernel failed mid-run: " <> show err)
    _ -> error "dqn device forward kernel failed mid-run"

-- | Sprint 13.8 — real QR-DQN (Dabney et al. 2017) off-policy training
-- loop, the distributional member of the discrete off-policy family.
--
-- QR-DQN replaces DQN's scalar Q head with a per-action distribution of
-- @numQuantiles@ atoms. The network emits @actionCount * numQuantiles@
-- outputs; @Q(s, a)@ is the mean of action @a@'s atoms. The Bellman
-- target projects the greedy next action's target-net atoms; the loss is
-- the quantile-Huber regression from "JitML.RL.Algorithms.QrDqnLoss".
--
-- The trainer reuses the same replay buffer + target-network + epsilon-
-- greedy + Adam surface as "JitML.RL.Algorithms.DqnTrainer"; the only
-- difference is the distributional head and the quantile-Huber gradient.
--
-- Bit-deterministic on the same substrate / same seed.
module JitML.RL.Algorithms.QrDqnTrainer
  ( QrDqnTrainConfig (..)
  , defaultQrDqnTrainConfig
  , QrDqnTrainResult (..)
  , QrDqnIterationStat (..)
  , trainQrDqnOnCartpole
  , trainQrDqnOnCartpoleCuda
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
import JitML.Numerics.MlpCuda (mlpBatchGradientCuda, mlpForwardBatchCuda)
import JitML.RL.Algorithms.QrDqnLoss (quantileMidpoints)
import JitML.RL.Simulator
  ( CartPoleState (..)
  , SimStep (..)
  , cartPoleInitial
  , cartPoleStep
  )

data QrDqnTrainConfig = QrDqnTrainConfig
  { qrSeed :: !Int
  , qrHiddenUnits :: !Int
  , qrNumQuantiles :: !Int
  , qrNumSteps :: !Int
  , qrReplayCapacity :: !Int
  , qrBatchSize :: !Int
  , qrLearningRate :: !Double
  , qrGamma :: !Double
  , qrKappa :: !Double
  , qrTargetUpdateInterval :: !Int
  , qrEpsilonStart :: !Double
  , qrEpsilonEnd :: !Double
  , qrEpsilonDecaySteps :: !Int
  , qrTrainStart :: !Int
  , qrUpdateFrequency :: !Int
  , qrMaxEpisodeSteps :: !Int
  , qrActionCount :: !Int
  , qrObsSize :: !Int
  , qrStatInterval :: !Int
  }
  deriving stock (Eq, Show)

defaultQrDqnTrainConfig :: QrDqnTrainConfig
defaultQrDqnTrainConfig =
  QrDqnTrainConfig
    { qrSeed = 42
    , qrHiddenUnits = 64
    , qrNumQuantiles = 8
    , qrNumSteps = 20000
    , qrReplayCapacity = 10000
    , qrBatchSize = 32
    , qrLearningRate = 1.0e-3
    , qrGamma = 0.99
    , qrKappa = 1.0
    , qrTargetUpdateInterval = 500
    , qrEpsilonStart = 1.0
    , qrEpsilonEnd = 0.05
    , qrEpsilonDecaySteps = 5000
    , qrTrainStart = 1000
    , qrUpdateFrequency = 4
    , qrMaxEpisodeSteps = 500
    , qrActionCount = 2
    , qrObsSize = 4
    , qrStatInterval = 1000
    }

data Transition = Transition
  { transObs :: !(Vector Double)
  , transAction :: !Int
  , transReward :: !Double
  , transNextObs :: !(Vector Double)
  , transDone :: !Bool
  }
  deriving stock (Eq, Show)

data QrDqnIterationStat = QrDqnIterationStat
  { qrIterStep :: !Int
  , qrIterEpisodes :: !Int
  , qrIterMeanReward :: !Double
  }
  deriving stock (Eq, Show)

data QrDqnTrainResult = QrDqnTrainResult
  { qrResultStats :: ![QrDqnIterationStat]
  , qrResultFinalParams :: !MlpParams
  , qrResultConfig :: !QrDqnTrainConfig
  }
  deriving stock (Eq, Show)

trainQrDqnOnCartpole :: QrDqnTrainConfig -> IO QrDqnTrainResult
trainQrDqnOnCartpole config = do
  let shape =
        MlpShape
          { mlpInputs = qrObsSize config
          , mlpHidden = qrHiddenUnits config
          , mlpOutputs = qrActionCount config * qrNumQuantiles config
          }
      initialParams = mlpInit shape (qrSeed config)
  loop
    config
    (\online target adam batch -> pure (qrUpdate config online target adam batch))
    initialParams
    initialParams
    (adamInit shape)
    (Random.mkStdGen (qrSeed config + 1))
    []
    0
    cartPoleInitial
    0
    0.0
    []
    []

loop
  :: QrDqnTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (MlpParams, AdamState))
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> Random.StdGen
  -> [Transition]
  -> Int
  -> CartPoleState
  -> Int
  -> Double
  -> [Double]
  -> [QrDqnIterationStat]
  -> IO QrDqnTrainResult
loop config update online target adam gen buffer step state episodeLen episodeReturn episodes stats
  | step >= qrNumSteps config =
      pure
        QrDqnTrainResult
          { qrResultStats = reverse stats
          , qrResultFinalParams = online
          , qrResultConfig = config
          }
  | otherwise = do
      let epsilon = currentEpsilon config step
          obs = obsVector state
          (u, gen1) = Random.uniformR (0.0 :: Double, 1.0) gen
          (actionU, gen2) = Random.uniformR (0 :: Int, qrActionCount config - 1) gen1
          greedyAction = greedyActionFor config online obs
          action = if u < epsilon then actionU else greedyAction
          stepResult = cartPoleStep state action
          terminal = simStepDone stepResult || episodeLen + 1 >= qrMaxEpisodeSteps config
          nextObs = obsVector (simStepState stepResult)
          transition =
            Transition obs action (simStepReward stepResult) nextObs terminal
          newBuffer = take (qrReplayCapacity config) (transition : buffer)
          nextReturn = episodeReturn + simStepReward stepResult
          (nextState, nextLen, finalReturn, newEpisodes) =
            if terminal
              then (cartPoleInitial, 0, 0.0, nextReturn : episodes)
              else (simStepState stepResult, episodeLen + 1, nextReturn, episodes)
      (onlineNext, adamNext, gen3) <-
        if step + 1 >= qrTrainStart config
          && (step + 1) `mod` qrUpdateFrequency config == 0
          && length newBuffer >= qrBatchSize config
          then do
            let (batch, genB) = sampleBatch (qrBatchSize config) newBuffer gen2
            (onlineUpd, adamUpd) <- update online target adam batch
            pure (onlineUpd, adamUpd, genB)
          else pure (online, adam, gen2)
      let targetNext =
            if (step + 1) `mod` qrTargetUpdateInterval config == 0
              then onlineNext
              else target
          statsNext =
            if (step + 1) `mod` qrStatInterval config == 0
              then
                let recent = take 100 newEpisodes
                    meanR =
                      if null recent
                        then 0.0
                        else sum recent / fromIntegral (length recent)
                 in QrDqnIterationStat (step + 1) (length newEpisodes) meanR : stats
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
        nextLen
        finalReturn
        newEpisodes
        statsNext

currentEpsilon :: QrDqnTrainConfig -> Int -> Double
currentEpsilon config step =
  let frac = min 1.0 (fromIntegral step / fromIntegral (max 1 (qrEpsilonDecaySteps config)))
   in qrEpsilonStart config + frac * (qrEpsilonEnd config - qrEpsilonStart config)

-- | The per-action atoms of the network output: action @a@ occupies the
-- slice @[a*N .. a*N + N - 1]@.
actionAtoms :: QrDqnTrainConfig -> Vector Double -> Int -> Vector Double
actionAtoms config output a =
  VU.slice (a * qrNumQuantiles config) (qrNumQuantiles config) output

actionMeanQ :: QrDqnTrainConfig -> Vector Double -> Int -> Double
actionMeanQ config output a =
  let atoms = actionAtoms config output a
   in VU.sum atoms / fromIntegral (qrNumQuantiles config)

greedyActionFor :: QrDqnTrainConfig -> MlpParams -> Vector Double -> Int
greedyActionFor config params obs =
  let output = forwardOutput (mlpForward params obs)
      qs = [actionMeanQ config output a | a <- [0 .. qrActionCount config - 1]]
   in argmax qs

argmax :: (Ord a) => [a] -> Int
argmax [] = 0
argmax xs = snd (foldr1 step (zip xs [0 ..]))
 where
  step (v1, i1) (v2, i2)
    | v1 >= v2 = (v1, i1)
    | otherwise = (v2, i2)

-- | QR-DQN gradient update on one batch. The quantile-Huber gradient for
-- each predicted atom @theta_p_i@ of the taken action is
-- @-(1/N) * sum_j |tau_i - 1{u<0}| * clip(u, -kappa, kappa)@ where
-- @u = theta_t_j - theta_p_i@ and the target atoms @theta_t_j@ are the
-- greedy next action's target-net atoms shifted by the Bellman backup.
qrUpdate
  :: QrDqnTrainConfig -> MlpParams -> MlpParams -> AdamState -> [Transition] -> (MlpParams, AdamState)
qrUpdate config online target adam batch =
  let adamCfg = defaultAdamConfig {adamLearningRate = qrLearningRate config}
      stepUpdate (params, a) trans =
        let fwd = mlpForward params (transObs trans)
            output = forwardOutput fwd
            targetOutput = forwardOutput (mlpForward target (transNextObs trans))
            dLdy = qrResidualDLdy config output targetOutput trans
            grad = mlpBackward params fwd dLdy
         in adamStep adamCfg a params grad
   in Data.List.foldl' stepUpdate (online, adam) batch

-- | The per-transition QR-DQN loss gradient w.r.t. the quantile-network
-- output: the quantile-Huber gradient placed at the taken action's atom
-- slots, zero elsewhere. Takes the online output at the state and the
-- target-net output at the next state (the greedy next action is read off
-- the target output via 'actionMeanQ', so no extra forward is needed).
-- Factored out of 'qrUpdate' so the pure CPU path and the batched CUDA
-- path ('qrUpdateCuda') compute the identical loss gradient.
qrResidualDLdy
  :: QrDqnTrainConfig
  -> Vector Double
  -- ^ online output Q-atoms at the state
  -> Vector Double
  -- ^ target-net output Q-atoms at the next state
  -> Transition
  -> Vector Double
qrResidualDLdy config output targetOutput trans =
  VU.generate outputs $ \k ->
    let (act, qi) = k `divMod` n
     in if act == actionIx then actionGrads !! qi else 0.0
 where
  n = qrNumQuantiles config
  outputs = qrActionCount config * n
  gamma = qrGamma config
  kappa = qrKappa config
  taus = quantileMidpoints n
  actionIx = transAction trans
  predicted = VU.toList (actionAtoms config output actionIx)
  nextGreedy = argmax [actionMeanQ config targetOutput a | a <- [0 .. qrActionCount config - 1]]
  nextAtoms = VU.toList (actionAtoms config targetOutput nextGreedy)
  targetAtoms =
    if transDone trans
      then replicate n (transReward trans)
      else fmap (\q -> transReward trans + gamma * q) nextAtoms
  atomGrad tau thetaP =
    let contrib thetaT =
          let uu = thetaT - thetaP
              asym = if uu < 0 then abs (tau - 1.0) else abs tau
              clipped = max (-kappa) (min kappa uu)
           in asym * clipped
     in negate (sum (fmap contrib targetAtoms)) / fromIntegral n
  actionGrads = zipWith atomGrad taus predicted

sampleBatch :: Int -> [Transition] -> Random.StdGen -> ([Transition], Random.StdGen)
sampleBatch n buffer gen =
  let bufLen = length buffer
      pickN k g acc
        | k <= 0 = (acc, g)
        | otherwise =
            let (idx, g') = Random.uniformR (0 :: Int, bufLen - 1) g
             in pickN (k - 1) g' (buffer !! idx : acc)
   in pickN n gen []

obsVector :: CartPoleState -> Vector Double
obsVector state =
  VU.fromList
    [ cartPosition state
    , cartVelocity state
    , poleAngle state
    , poleAngularVelocity state
    ]

-- | Sprint 13.8 — train QR-DQN on cartpole with the quantile network's
-- forward + backward running on the GPU through the batched device
-- primitives. Same env loop / replay / target-copy as the pure
-- 'trainQrDqnOnCartpole' (shared via the parameterised 'loop'); only the
-- minibatch gradient update runs on the device ('qrUpdateCuda'), reusing
-- the shared quantile-Huber head 'qrResidualDLdy'.
trainQrDqnOnCartpoleCuda :: Env -> QrDqnTrainConfig -> IO QrDqnTrainResult
trainQrDqnOnCartpoleCuda env config = do
  let shape =
        MlpShape
          { mlpInputs = qrObsSize config
          , mlpHidden = qrHiddenUnits config
          , mlpOutputs = qrActionCount config * qrNumQuantiles config
          }
      initialParams = mlpInit shape (qrSeed config)
  loop
    config
    (qrUpdateCuda env config)
    initialParams
    initialParams
    (adamInit shape)
    (Random.mkStdGen (qrSeed config + 1))
    []
    0
    cartPoleInitial
    0
    0.0
    []
    []

-- | Minibatch QR-DQN gradient update through the batched CUDA primitives:
-- batched online forward at the states + target forward at the next states,
-- the per-sample quantile-Huber gradient ('qrResidualDLdy'), one batched
-- device backward (mean gradient), and one Adam step. Falls back to the
-- pure 'qrUpdate' if the CUDA runtime/compile is unavailable.
qrUpdateCuda
  :: Env
  -> QrDqnTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> [Transition]
  -> IO (MlpParams, AdamState)
qrUpdateCuda env config online target adam batch = do
  onlineOutE <- mlpForwardBatchCuda env online (map transObs batch)
  targetOutE <- mlpForwardBatchCuda env target (map transNextObs batch)
  case (onlineOutE, targetOutE) of
    (Right onlineOuts, Right targetOuts) -> do
      let pairs =
            [ (transObs trans, qrResidualDLdy config onOut tgOut trans)
            | (trans, onOut, tgOut) <- zip3 batch onlineOuts targetOuts
            ]
      gradResult <- mlpBatchGradientCuda env online pairs
      case gradResult of
        Right summed ->
          let scale = 1.0 / fromIntegral (length batch)
              meanGradient = scaleGradient scale summed
              adamCfg = defaultAdamConfig {adamLearningRate = qrLearningRate config}
              (onlineAfter, adamAfter) = adamStep adamCfg adam online meanGradient
           in pure (onlineAfter, adamAfter)
        Left _ -> pure (qrUpdate config online target adam batch)
    _ -> pure (qrUpdate config online target adam batch)
 where
  scaleGradient sc g =
    MlpGradient
      { gradW1 = VU.map (* sc) (gradW1 g)
      , gradB1 = VU.map (* sc) (gradB1 g)
      , gradW2 = VU.map (* sc) (gradW2 g)
      , gradB2 = VU.map (* sc) (gradB2 g)
      }

{-# LANGUAGE OverloadedStrings #-}

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
  , productQrDqnHiddenUnits
  , QrDqnTrainResult (..)
  , QrDqnIterationStat (..)
  , initialQrDqnParams
  , trainQrDqnOnCartpole
  , trainQrDqnOnCartpoleCuda
  , trainQrDqnOnCartpoleOneDnn
  , trainQrDqnOnCartpoleMetal
  , trainQrDqnOnDevice
  , trainQrDqnOnDeviceWithEnvironment
  , evaluateQrDqnPolicyWithEnvironment
  , qrDqnEvaluationContract
  , evaluateQrDqnPolicyOnDeviceWithEnvironment
  , QrDqnTrainObservation
  , refineQrDqnTrainObservation
  , trainQrDqnOnCartpoleRaw
  , trainQrDqnOnDeviceWithEnvironmentRaw
  , PreparedQrDqn
  , QrDqnPreparedSnapshot
  , preparedQrDqnSnapshot
  , continuePreparedQrDqnRaw
  , prepareQrDqnOnCartpole
  , prepareQrDqnOnDeviceWithEnvironment
  , qrDqnPreparedConfig
  , qrDqnPreparedInitialParams
  , qrDqnPreparedOnlineParams
  , qrDqnPreparedTargetParams
  , qrDqnPreparedAdam
  , qrDqnPreparedGenerator
  , qrDqnPreparedReplay
  , qrDqnPreparedStep
  , qrDqnPreparedState
  , qrDqnPreparedEpisodeLength
  , qrDqnPreparedEpisodeReturn
  , qrDqnPreparedRecentReturns
  , qrDqnPreparedStatistics
  , qrDqnPreparedEnvironmentName
  , qrDqnPreparedObservationWidth
  , qrDqnPreparedActionCount
  , qrDqnPreparedFrame
  )
where

import Data.List qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as VB
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState (..)
  , MlpGradient (..)
  , MlpParams (..)
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
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.QrDqnLoss (quantileMidpoints)
import JitML.RL.RewardShaping qualified as RewardShaping
import JitML.RL.Simulator
  ( CartPoleState
  , SimStep (..)
  , SimulatedEnvironment (..)
  , SomeSimulatedEnvironment (..)
  , cartPoleEnvironment
  , renderObservation
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

productQrDqnHiddenUnits :: Int
productQrDqnHiddenUnits = 256

defaultQrDqnTrainConfig :: QrDqnTrainConfig
defaultQrDqnTrainConfig =
  QrDqnTrainConfig
    { qrSeed = 42
    , qrHiddenUnits = 64
    , qrNumQuantiles = 8
    , qrNumSteps = 20000
    , qrReplayCapacity = 10000
    , qrBatchSize = 64
    , qrLearningRate = 1.0e-3
    , qrGamma = 0.99
    , qrKappa = 1.0
    , -- Keep the slower target sync and the 0.05 exploration floor of the
      -- original config: dropping them (with the update-frequency bump below)
      -- rescued cartpole/mountain-car but collapsed the sparse-reward
      -- key-door-grid policy. Only the per-step update frequency and the larger
      -- batch are changed from the pre-tuning defaults.
      qrTargetUpdateInterval = 500
    , qrEpsilonStart = 1.0
    , qrEpsilonEnd = 0.05
    , qrEpsilonDecaySteps = 5000
    , qrTrainStart = 1000
    , qrUpdateFrequency = 1
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
  , qrResultInitialParams :: !MlpParams
  , qrResultFinalParams :: !MlpParams
  , qrResultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Actual environment transitions plus Adam applications executed against
  -- the final online quantile-Q tensor.
  , qrResultConfig :: !QrDqnTrainConfig
  }
  deriving stock (Eq, Show)

-- | Uncensored numerical return; no producer/device/learning authority.
type QrDqnTrainObservation = Common.RawTrainerResult MlpParams QrDqnIterationStat QrDqnTrainConfig

refineQrDqnTrainObservation :: QrDqnTrainObservation -> Either Text QrDqnTrainResult
refineQrDqnTrainObservation observed = do
  counters <- Common.refineObservedTrainerCounters (Common.rawTrainerCounters observed)
  pure
    QrDqnTrainResult
      { qrResultStats = Common.rawTrainerStats observed
      , qrResultInitialParams = Common.rawTrainerInitialParams observed
      , qrResultFinalParams = Common.rawTrainerFinalParams observed
      , qrResultMeasuredCounters = counters
      , qrResultConfig = Common.rawTrainerConfig observed
      }

trainQrDqnOnCartpole :: QrDqnTrainConfig -> IO QrDqnTrainResult
trainQrDqnOnCartpole config = do
  observed <- trainQrDqnOnCartpoleRaw config
  either (fail . Text.unpack) pure (refineQrDqnTrainObservation observed)

-- | Captured numerical state only. No producer, device, durable or completion authority.
-- Fields stay lazy so old wrappers do not acquire new forcing/exception order.
data QrDqnPreparedSnapshot state = QrDqnPreparedSnapshot
  { internalQrDqnConfig :: QrDqnTrainConfig
  , internalQrDqnInitialParams :: MlpParams
  , internalQrDqnOnlineParams :: MlpParams
  , internalQrDqnTargetParams :: MlpParams
  , internalQrDqnAdam :: AdamState
  , internalQrDqnGenerator :: Random.StdGen
  , internalQrDqnReplay :: [Transition]
  , internalQrDqnStep :: Int
  , internalQrDqnState :: state
  , internalQrDqnEpisodeLength :: Int
  , internalQrDqnEpisodeReturn :: Double
  , internalQrDqnRecentReturns :: [Double]
  , internalQrDqnStatistics :: [QrDqnIterationStat]
  , internalQrDqnEnvironmentName :: Text
  , internalQrDqnObservationWidth :: Int
  , internalQrDqnActionCount :: Int
  , internalQrDqnFrame :: Vector Double
  }
  deriving stock (Eq, Show)

-- Constructor and continuation are private; no parsed snapshot can reconstruct one.
data PreparedQrDqn state
  = PreparedQrDqn
      (QrDqnPreparedSnapshot state)
      SingleUse.SingleUse
      (IO (Either Text QrDqnTrainObservation))

preparedQrDqnSnapshot :: PreparedQrDqn state -> QrDqnPreparedSnapshot state
preparedQrDqnSnapshot (PreparedQrDqn snapshot _ _) = snapshot

continuePreparedQrDqnRaw :: PreparedQrDqn state -> IO (Either Text QrDqnTrainObservation)
continuePreparedQrDqnRaw (PreparedQrDqn _ guard action) = do
  consumed <- SingleUse.tryConsumeSingleUse guard
  if consumed then action else pure (Left "prepared QrDqn continuation has already been consumed")

qrDqnPreparedConfig :: QrDqnPreparedSnapshot state -> QrDqnTrainConfig
qrDqnPreparedConfig = internalQrDqnConfig

qrDqnPreparedInitialParams :: QrDqnPreparedSnapshot state -> MlpParams
qrDqnPreparedInitialParams = internalQrDqnInitialParams

qrDqnPreparedOnlineParams :: QrDqnPreparedSnapshot state -> MlpParams
qrDqnPreparedOnlineParams = internalQrDqnOnlineParams

qrDqnPreparedTargetParams :: QrDqnPreparedSnapshot state -> MlpParams
qrDqnPreparedTargetParams = internalQrDqnTargetParams

qrDqnPreparedAdam :: QrDqnPreparedSnapshot state -> AdamState
qrDqnPreparedAdam = internalQrDqnAdam

qrDqnPreparedGenerator :: QrDqnPreparedSnapshot state -> Random.StdGen
qrDqnPreparedGenerator = internalQrDqnGenerator

qrDqnPreparedReplay
  :: QrDqnPreparedSnapshot state -> [(Vector Double, Int, Double, Vector Double, Bool)]
qrDqnPreparedReplay =
  fmap
    ( \transition ->
        ( transObs transition
        , transAction transition
        , transReward transition
        , transNextObs transition
        , transDone transition
        )
    )
    . internalQrDqnReplay

qrDqnPreparedStep :: QrDqnPreparedSnapshot state -> Int
qrDqnPreparedStep = internalQrDqnStep

qrDqnPreparedState :: QrDqnPreparedSnapshot state -> state
qrDqnPreparedState = internalQrDqnState

qrDqnPreparedEpisodeLength :: QrDqnPreparedSnapshot state -> Int
qrDqnPreparedEpisodeLength = internalQrDqnEpisodeLength

qrDqnPreparedEpisodeReturn :: QrDqnPreparedSnapshot state -> Double
qrDqnPreparedEpisodeReturn = internalQrDqnEpisodeReturn

qrDqnPreparedRecentReturns :: QrDqnPreparedSnapshot state -> [Double]
qrDqnPreparedRecentReturns = internalQrDqnRecentReturns

qrDqnPreparedStatistics :: QrDqnPreparedSnapshot state -> [QrDqnIterationStat]
qrDqnPreparedStatistics = internalQrDqnStatistics

qrDqnPreparedEnvironmentName :: QrDqnPreparedSnapshot state -> Text
qrDqnPreparedEnvironmentName = internalQrDqnEnvironmentName

qrDqnPreparedObservationWidth :: QrDqnPreparedSnapshot state -> Int
qrDqnPreparedObservationWidth = internalQrDqnObservationWidth

qrDqnPreparedActionCount :: QrDqnPreparedSnapshot state -> Int
qrDqnPreparedActionCount = internalQrDqnActionCount

qrDqnPreparedFrame :: QrDqnPreparedSnapshot state -> Vector Double
qrDqnPreparedFrame = internalQrDqnFrame

trainQrDqnOnCartpoleRaw :: QrDqnTrainConfig -> IO QrDqnTrainObservation
trainQrDqnOnCartpoleRaw config = do
  prepared <- prepareQrDqnOnCartpole config
  result <- continuePreparedQrDqnRaw prepared
  either (fail . Text.unpack) pure result

prepareQrDqnOnCartpole :: QrDqnTrainConfig -> IO (PreparedQrDqn CartPoleState)
prepareQrDqnOnCartpole config = do
  let shape = qrDqnMlpShape config
      initialParams = initialQrDqnParams config
      initialOnline = initialParams
      initialTarget = initialParams
      initialAdam = adamInit shape
      initialGenerator = Random.mkStdGen (qrSeed config + 1)
      initialReplay = []
      initialStep = 0
      initialState = envInitial cartPoleEnvironment
      initialEpisodeLength = 0
      initialEpisodeReturn = 0.0
      initialRecentReturns = []
      initialStatistics = []
  guard <- SingleUse.newSingleUse
  let snapshot =
        QrDqnPreparedSnapshot
          config
          initialParams
          initialOnline
          initialTarget
          initialAdam
          initialGenerator
          initialReplay
          initialStep
          initialState
          initialEpisodeLength
          initialEpisodeReturn
          initialRecentReturns
          initialStatistics
          (envName cartPoleEnvironment)
          (envObservationSize cartPoleEnvironment)
          (envActionCount cartPoleEnvironment)
          (obsVector cartPoleEnvironment initialState)
      action =
        Right
          <$> loop
            initialParams
            cartPoleEnvironment
            config
            (\online target adam batch -> pure (qrUpdate config online target adam batch))
            initialOnline
            initialTarget
            initialAdam
            initialGenerator
            initialReplay
            initialStep
            initialState
            initialEpisodeLength
            initialEpisodeReturn
            initialRecentReturns
            initialStatistics
  pure (PreparedQrDqn snapshot guard action)

loop
  :: MlpParams
  -> SimulatedEnvironment state
  -> QrDqnTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (MlpParams, AdamState))
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> Random.StdGen
  -> [Transition]
  -> Int
  -> state
  -> Int
  -> Double
  -> [Double]
  -> [QrDqnIterationStat]
  -> IO QrDqnTrainObservation
loop initialSnapshot environment config update online target adam gen buffer step state episodeLen episodeReturn episodes stats = do
  result <-
    loopEither
      initialSnapshot
      environment
      config
      (\o t a batch -> Right <$> update o t a batch)
      online
      target
      adam
      gen
      buffer
      step
      state
      episodeLen
      episodeReturn
      episodes
      stats
  either (fail . Text.unpack) pure result

loopEither
  :: MlpParams
  -> SimulatedEnvironment state
  -> QrDqnTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (Either Text (MlpParams, AdamState)))
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> Random.StdGen
  -> [Transition]
  -> Int
  -> state
  -> Int
  -> Double
  -> [Double]
  -> [QrDqnIterationStat]
  -> IO (Either Text QrDqnTrainObservation)
loopEither initialSnapshot environment config update online target adam gen buffer step state episodeLen episodeReturn episodes stats
  | step >= qrNumSteps config =
      pure $ do
        counters <-
          Common.mkObservedTrainerCounters
            (toInteger step)
            (toInteger (adamStep_ adam))
        pure
          Common.RawTrainerResult
            { Common.rawTrainerInitialParams = initialSnapshot
            , Common.rawTrainerFinalParams = online
            , Common.rawTrainerStats = reverse stats
            , Common.rawTrainerCounters = counters
            , Common.rawTrainerConfig = config
            }
  | otherwise = do
      let epsilon = currentEpsilon config step
          obs = obsVector environment state
          (u, gen1) = Random.uniformR (0.0 :: Double, 1.0) gen
          (actionU, gen2) = Random.uniformR (0 :: Int, qrActionCount config - 1) gen1
          greedyAction = greedyActionFor config online obs
          action = if u < epsilon then actionU else greedyAction
          stepResult = envStep environment state action
          -- True environment termination only stops Bellman bootstrapping; a
          -- time-limit truncation resets the episode but is NOT terminal, so the
          -- net keeps bootstrapping through the horizon cap and can learn values
          -- that reach the 500-step cap (matches DqnTrainer's transDone).
          envDone = simStepDone stepResult
          timeLimit = episodeLen + 1 >= qrMaxEpisodeSteps config
          terminal = envDone || timeLimit
          nextObs = obsVector environment (simStepState stepResult)
          transition =
            Transition
              obs
              action
              ( simStepReward stepResult
                  + RewardShaping.shapingBonus (envName environment) (qrGamma config) obs nextObs
              )
              nextObs
              envDone
          newBuffer = take (qrReplayCapacity config) (transition : buffer)
          nextReturn = episodeReturn + simStepReward stepResult
          (nextState, nextLen, finalReturn, newEpisodes) =
            if terminal
              then (envInitial environment, 0, 0.0, nextReturn : episodes)
              else (simStepState stepResult, episodeLen + 1, nextReturn, episodes)
      updateResult <-
        if step + 1 >= qrTrainStart config
          && (step + 1) `mod` qrUpdateFrequency config == 0
          && length newBuffer >= qrBatchSize config
          then do
            let (batch, genB) = sampleBatch (qrBatchSize config) newBuffer gen2
            fmap (\(onlineUpd, adamUpd) -> (onlineUpd, adamUpd, genB)) <$> update online target adam batch
          else pure (Right (online, adam, gen2))
      case updateResult of
        Left err -> pure (Left err)
        Right (onlineNext, adamNext, gen3) -> do
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
          loopEither
            initialSnapshot
            environment
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

maskedArgmax :: Maybe [Bool] -> [Double] -> Int
maskedArgmax Nothing values = argmax values
maskedArgmax (Just mask) values =
  argmax
    [ if ix < length mask && not (mask !! ix)
        then -1.0e12
        else value
    | (ix, value) <- zip [0 ..] values
    ]

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
-- Factored out of 'qrUpdate' so the pure CPU path and the batched device
-- path ('qrUpdateDevice') compute the identical loss gradient.
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
  -- O(1) replay indexing via a boxed-Vector snapshot (see DqnTrainer.sampleBatch).
  let bufArr = VB.fromList buffer
      bufLen = VB.length bufArr
      pickN k g acc
        | k <= 0 || bufLen <= 0 = (acc, g)
        | otherwise =
            let (idx, g') = Random.uniformR (0 :: Int, bufLen - 1) g
             in pickN (k - 1) g' (bufArr VB.! idx : acc)
   in pickN n gen []

obsVector :: SimulatedEnvironment state -> state -> Vector Double
obsVector environment =
  VU.fromList . renderObservation . envRenderFrame environment

-- | Sprint 13.8 — train QR-DQN on cartpole with the quantile network's
-- forward + backward running on the GPU through the batched device
-- primitives. Same env loop / replay / target-copy as the pure
-- 'trainQrDqnOnCartpole' (shared via the parameterised 'loop'); only the
-- minibatch gradient update runs on the device ('qrUpdateDevice'), reusing
-- the shared quantile-Huber head 'qrResidualDLdy'.
trainQrDqnOnCartpoleCuda :: Env -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainResult)
trainQrDqnOnCartpoleCuda env = trainQrDqnOnDevice (cudaMlpDevice env)

-- | QR-DQN training through the oneDNN (linux-cpu) MLP device.
trainQrDqnOnCartpoleOneDnn :: Env -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainResult)
trainQrDqnOnCartpoleOneDnn env = trainQrDqnOnDevice (oneDnnMlpDevice env)

-- | QR-DQN training through the Metal (apple-silicon) MLP device.
trainQrDqnOnCartpoleMetal :: Env -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainResult)
trainQrDqnOnCartpoleMetal env = trainQrDqnOnDevice (metalMlpDevice env)

-- | QR-DQN training through an injected MLP device backend. Same env loop /
-- replay / target-copy as the pure 'trainQrDqnOnCartpole' (shared via the
-- parameterised 'loop'); only the minibatch gradient update runs on the
-- device ('qrUpdateDevice'), reusing the shared quantile-Huber head
-- 'qrResidualDLdy'.
trainQrDqnOnDevice :: MlpDevice -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainResult)
trainQrDqnOnDevice device =
  trainQrDqnOnDeviceWithSimulatedEnvironment device cartPoleEnvironment

trainQrDqnOnDeviceWithEnvironment
  :: MlpDevice -> SomeSimulatedEnvironment -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainResult)
trainQrDqnOnDeviceWithEnvironment device (SomeSimulatedEnvironment environment) =
  trainQrDqnOnDeviceWithSimulatedEnvironment device environment

trainQrDqnOnDeviceWithSimulatedEnvironment
  :: MlpDevice -> SimulatedEnvironment state -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainResult)
trainQrDqnOnDeviceWithSimulatedEnvironment device environment config = do
  observed <- trainQrDqnOnDeviceWithSimulatedEnvironmentRaw device environment config
  pure (observed >>= refineQrDqnTrainObservation)

trainQrDqnOnDeviceWithSimulatedEnvironmentRaw
  :: MlpDevice
  -> SimulatedEnvironment state
  -> QrDqnTrainConfig
  -> IO (Either Text QrDqnTrainObservation)
trainQrDqnOnDeviceWithSimulatedEnvironmentRaw device environment config = do
  prepared <- prepareQrDqnOnDeviceWithEnvironment device environment config
  continuePreparedQrDqnRaw prepared

prepareQrDqnOnDeviceWithEnvironment
  :: MlpDevice -> SimulatedEnvironment state -> QrDqnTrainConfig -> IO (PreparedQrDqn state)
prepareQrDqnOnDeviceWithEnvironment device environment config = do
  let shape = qrDqnMlpShape config
      initialParams = initialQrDqnParams config
      initialOnline = initialParams
      initialTarget = initialParams
      initialAdam = adamInit shape
      initialGenerator = Random.mkStdGen (qrSeed config + 1)
      initialReplay = []
      initialStep = 0
      initialState = envInitial environment
      initialEpisodeLength = 0
      initialEpisodeReturn = 0.0
      initialRecentReturns = []
      initialStatistics = []
  guard <- SingleUse.newSingleUse
  let snapshot =
        QrDqnPreparedSnapshot
          config
          initialParams
          initialOnline
          initialTarget
          initialAdam
          initialGenerator
          initialReplay
          initialStep
          initialState
          initialEpisodeLength
          initialEpisodeReturn
          initialRecentReturns
          initialStatistics
          (envName environment)
          (envObservationSize environment)
          (envActionCount environment)
          (obsVector environment initialState)
      action =
        loopEither
          initialParams
          environment
          config
          (qrUpdateDevice device config)
          initialOnline
          initialTarget
          initialAdam
          initialGenerator
          initialReplay
          initialStep
          initialState
          initialEpisodeLength
          initialEpisodeReturn
          initialRecentReturns
          initialStatistics
  pure (PreparedQrDqn snapshot guard action)

qrDqnMlpShape :: QrDqnTrainConfig -> MlpShape
qrDqnMlpShape config =
  MlpShape
    { mlpInputs = qrObsSize config
    , mlpHidden = qrHiddenUnits config
    , mlpOutputs = qrActionCount config * qrNumQuantiles config
    }

initialQrDqnParams :: QrDqnTrainConfig -> MlpParams
initialQrDqnParams config =
  mlpInit (qrDqnMlpShape config) (qrSeed config)

evaluateQrDqnPolicyWithEnvironment
  :: SomeSimulatedEnvironment
  -> QrDqnTrainConfig
  -> MlpParams
  -> Int
  -> [Common.EvaluationEpisodeResult]
evaluateQrDqnPolicyWithEnvironment (SomeSimulatedEnvironment environment) config params episodeCount =
  replicate (max 1 episodeCount) (evaluateEpisode environment config params)

evaluateEpisode
  :: SimulatedEnvironment state
  -> QrDqnTrainConfig
  -> MlpParams
  -> Common.EvaluationEpisodeResult
evaluateEpisode environment config params = go (envInitial environment) 0 0.0
 where
  go state episodeLen episodeReturn
    | episodeLen >= qrMaxEpisodeSteps config =
        Common.EvaluationEpisodeResult episodeReturn episodeLen False
    | otherwise =
        let obs = obsVector environment state
            output = forwardOutput (mlpForward params obs)
            qValues = [actionMeanQ config output actionIndex | actionIndex <- [0 .. qrActionCount config - 1]]
            action = maskedArgmax (envActionMask environment <*> Just state) qValues
            stepResult = envStep environment state action
            nextReturn = episodeReturn + simStepReward stepResult
            nextLen = episodeLen + 1
         in if simStepDone stepResult
              then Common.EvaluationEpisodeResult nextReturn nextLen True
              else go (simStepState stepResult) nextLen nextReturn

-- | Minibatch QR-DQN gradient update through the batched device primitives:
-- batched online forward at the states + target forward at the next states,
-- the per-sample quantile-Huber gradient ('qrResidualDLdy'), one batched
-- device backward (mean gradient), and one Adam step. Fails closed with a
-- typed `Left` on any mid-run device fault.
qrUpdateDevice
  :: MlpDevice
  -> QrDqnTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> [Transition]
  -> IO (Either Text (MlpParams, AdamState))
qrUpdateDevice device config online target adam batch = do
  onlineOutE <- mlpdForwardBatch device online (map transObs batch)
  targetOutE <- mlpdForwardBatch device target (map transNextObs batch)
  case (onlineOutE, targetOutE) of
    (Right onlineOuts, Right targetOuts) -> do
      let pairs =
            [ (transObs trans, qrResidualDLdy config onOut tgOut trans)
            | (trans, onOut, tgOut) <- zip3 batch onlineOuts targetOuts
            ]
      gradResult <- mlpdBatchGradient device online pairs
      case gradResult of
        Right summed ->
          let scale = 1.0 / fromIntegral (length batch)
              meanGradient = scaleGradient scale summed
              adamCfg = defaultAdamConfig {adamLearningRate = qrLearningRate config}
              (onlineAfter, adamAfter) = adamStep adamCfg adam online meanGradient
           in pure (Right (onlineAfter, adamAfter))
        Left err -> pure (Left ("qr-dqn device batch-gradient kernel failed mid-run: " <> err))
    (Left err, _) -> pure (Left ("qr-dqn device forward kernel failed mid-run (online batch): " <> err))
    (_, Left err) -> pure (Left ("qr-dqn device forward kernel failed mid-run (target batch): " <> err))
 where
  scaleGradient sc g =
    MlpGradient
      { gradW1 = VU.map (* sc) (gradW1 g)
      , gradB1 = VU.map (* sc) (gradB1 g)
      , gradW2 = VU.map (* sc) (gradW2 g)
      , gradB2 = VU.map (* sc) (gradB2 g)
      }

-- | Versioned identity of final-policy scoring; training and the pure oracle
-- above retain their original semantics.
qrDqnEvaluationContract :: Text
qrDqnEvaluationContract = "qrdqn-selected-device-final-evaluation-v1"

-- | Score every frozen quantile-Q policy forward through the supplied device.
-- Quantile means, masks, leftmost ties, resets, rewards and horizon are shared
-- with the existing pure oracle. A failed member rejects the entire cohort.
evaluateQrDqnPolicyOnDeviceWithEnvironment
  :: MlpDevice
  -> SomeSimulatedEnvironment
  -> QrDqnTrainConfig
  -> MlpParams
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
evaluateQrDqnPolicyOnDeviceWithEnvironment device (SomeSimulatedEnvironment environment) config params episodeCount
  | episodeCount <= 0
      || qrMaxEpisodeSteps config <= 0
      || qrObsSize config <= 0
      || qrHiddenUnits config <= 0
      || qrActionCount config <= 0
      || qrNumQuantiles config <= 0
      || toInteger (qrActionCount config) * toInteger (qrNumQuantiles config) > toInteger (maxBound :: Int)
      || envObservationSize environment /= qrObsSize config
      || envActionCount environment /= qrActionCount config =
      pure (Left "QR-DQN device evaluation configuration does not match the environment")
  | not (qrEvaluationParams (qrDqnMlpShape config) params) =
      pure (Left "QR-DQN device evaluation parameters are malformed or overflow the Float32 ABI")
  | otherwise = collect episodeCount []
 where
  collect remaining episodes
    | remaining <= 0 = pure (Right (reverse episodes))
    | otherwise = do
        evaluated <- go (envInitial environment) 0 0.0
        case evaluated of
          Left err -> pure (Left err)
          Right episode -> collect (remaining - 1) (episode : episodes)
  go state episodeLen episodeReturn
    | episodeLen >= qrMaxEpisodeSteps config =
        pure (Right (Common.EvaluationEpisodeResult episodeReturn episodeLen False))
    | VU.length observation /= qrObsSize config || not (qrEvaluationVector observation) =
        pure (Left "QR-DQN device evaluation observation is malformed or overflows the Float32 ABI")
    | Just mask <- actionMask
    , length mask /= qrActionCount config || not (or mask) =
        pure (Left "QR-DQN device evaluation action mask is malformed or has no legal action")
    | otherwise = do
        forwarded <- mlpdForward device params observation
        case forwarded of
          Left err -> pure (Left ("QR-DQN device forward failed during evaluation: " <> err))
          Right forward
            | VU.length (forwardOutput forward) /= qrActionCount config * qrNumQuantiles config
                || not (qrEvaluationVector (forwardOutput forward)) ->
                pure (Left "QR-DQN device evaluation output has the wrong shape or is not finite Float32")
            | otherwise -> do
                let output = forwardOutput forward
                    qValues = [actionMeanQ config output actionIndex | actionIndex <- [0 .. qrActionCount config - 1]]
                case qrEvaluationLegalArgmax actionMask qValues of
                  Left err -> pure (Left err)
                  Right action -> do
                    let stepResult = envStep environment state action
                        nextReturn = episodeReturn + simStepReward stepResult
                        nextLen = episodeLen + 1
                    if not (qrEvaluationFinite (simStepReward stepResult) && qrEvaluationFinite nextReturn)
                      then pure (Left "QR-DQN device evaluation produced a non-finite reward")
                      else
                        if simStepDone stepResult
                          then pure (Right (Common.EvaluationEpisodeResult nextReturn nextLen True))
                          else go (simStepState stepResult) nextLen nextReturn
   where
    observation = obsVector environment state
    actionMask = envActionMask environment <*> Just state

-- Float32 is the selected MLP ABI. Finite binary64 values are accepted when
-- conversion remains finite; underflow/rounding is allowed, exact Float32
-- representability is not required. Environment rewards stay finite Double.
qrEvaluationFinite :: Double -> Bool
qrEvaluationFinite value = not (isNaN value || isInfinite value)

qrEvaluationVector :: Vector Double -> Bool
qrEvaluationVector =
  VU.all
    ( \value ->
        qrEvaluationFinite value
          && let encoded = realToFrac value :: Float in not (isNaN encoded || isInfinite encoded)
    )

qrEvaluationParams :: MlpShape -> MlpParams -> Bool
qrEvaluationParams shape params =
  paramShape params == shape
    && toInteger (VU.length (paramW1 params)) == toInteger (mlpHidden shape) * toInteger (mlpInputs shape)
    && VU.length (paramB1 params) == mlpHidden shape
    && toInteger (VU.length (paramW2 params)) == toInteger (mlpOutputs shape) * toInteger (mlpHidden shape)
    && VU.length (paramB2 params) == mlpOutputs shape
    && all qrEvaluationVector [paramW1 params, paramB1 params, paramW2 params, paramB2 params]

-- Filter illegal actions rather than assigning a finite sentinel: every legal
-- Q may be below any such sentinel. Original indices and leftmost ties survive.
qrEvaluationLegalArgmax :: Maybe [Bool] -> [Double] -> Either Text Int
qrEvaluationLegalArgmax mask values
  | not (all qrEvaluationFinite values) =
      Left "QR-DQN device evaluation produced a non-finite action mean"
  | Just legal <- mask
  , length legal /= length values =
      Left "QR-DQN device evaluation action mask width does not match action means"
  | otherwise = case eligible of
      [] -> Left "QR-DQN device evaluation has no legal action"
      first : rest -> Right (snd (Data.List.foldl' choose first rest))
 where
  eligible = [(value, index) | (value, index) <- zip values [0 ..], maybe True (!! index) mask]
  choose left right = if fst right > fst left then right else left

trainQrDqnOnDeviceWithEnvironmentRaw
  :: MlpDevice -> SomeSimulatedEnvironment -> QrDqnTrainConfig -> IO (Either Text QrDqnTrainObservation)
trainQrDqnOnDeviceWithEnvironmentRaw device (SomeSimulatedEnvironment environment) =
  trainQrDqnOnDeviceWithSimulatedEnvironmentRaw device environment

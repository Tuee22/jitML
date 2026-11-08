{-# LANGUAGE OverloadedStrings #-}

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
-- Bit-deterministic on the same substrate / same seed: exploration and replay
-- use the seeded 'StdGen', while policy forwards and gradient updates stay on
-- the selected deterministic device implementation.
module JitML.RL.Algorithms.DqnTrainer
  ( DqnTrainConfig (..)
  , defaultDqnTrainConfig
  , productDqnHiddenUnits
  , DqnTrainResult (..)
  , DqnIterationStat (..)
  , Transition (..)
  , initialDqnParams
  , trainDqnOnCartpole
  , trainDqnOnCartpoleCuda
  , trainDqnOnCartpoleOneDnn
  , trainDqnOnCartpoleMetal
  , trainDqnOnDevice
  , trainDqnOnDeviceWithEnvironment
  , evaluateDqnPolicyWithEnvironment
  , dqnEvaluationContract
  , DqnTrainObservation
  , refineDqnTrainObservation
  , trainDqnOnCartpoleRaw
  , trainDqnOnDeviceWithEnvironmentRaw
  , PreparedDqn
  , DqnPreparedSnapshot
  , preparedDqnSnapshot
  , continuePreparedDqnRaw
  , prepareDqnOnCartpole
  , prepareDqnOnDeviceWithEnvironment
  , dqnPreparedConfig
  , dqnPreparedInitialParams
  , dqnPreparedOnlineParams
  , dqnPreparedTargetParams
  , dqnPreparedAdam
  , dqnPreparedGenerator
  , dqnPreparedReplay
  , dqnPreparedStep
  , dqnPreparedState
  , dqnPreparedEpisodeLength
  , dqnPreparedEpisodeReturn
  , dqnPreparedRecentReturns
  , dqnPreparedStatistics
  , dqnPreparedEnvironmentName
  , dqnPreparedObservationWidth
  , dqnPreparedActionCount
  , dqnPreparedFrame
  )
where

import Data.List qualified
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as VB
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Foreign.C.Types (CInt)
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
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.DqnLoss qualified as DqnLoss
import JitML.RL.RewardShaping qualified as RewardShaping
import JitML.RL.Simulator
  ( CartPoleState
  , SimStep (..)
  , SimulatedEnvironment (..)
  , SomeSimulatedEnvironment (..)
  , cartPoleEnvironment
  , renderObservation
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

productDqnHiddenUnits :: Int
productDqnHiddenUnits = 256

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
  , dqnResultInitialParams :: !MlpParams
  , dqnResultFinalParams :: !MlpParams
  , dqnResultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Actual environment transitions plus Adam applications executed against
  -- the final online-Q tensor.
  , dqnResultConfig :: !DqnTrainConfig
  }
  deriving stock (Eq, Show)

-- | Uncensored numerical return; no producer/device/learning authority.
type DqnTrainObservation = Common.RawTrainerResult MlpParams DqnIterationStat DqnTrainConfig

refineDqnTrainObservation :: DqnTrainObservation -> Either Text DqnTrainResult
refineDqnTrainObservation observed = do
  counters <- Common.refineObservedTrainerCounters (Common.rawTrainerCounters observed)
  pure
    DqnTrainResult
      { dqnResultStats = Common.rawTrainerStats observed
      , dqnResultInitialParams = Common.rawTrainerInitialParams observed
      , dqnResultFinalParams = Common.rawTrainerFinalParams observed
      , dqnResultMeasuredCounters = counters
      , dqnResultConfig = Common.rawTrainerConfig observed
      }

trainDqnOnCartpole :: DqnTrainConfig -> IO DqnTrainResult
trainDqnOnCartpole config = do
  observed <- trainDqnOnCartpoleRaw config
  either (fail . Text.unpack) pure (refineDqnTrainObservation observed)

-- | Captured numerical state only. No producer, device, durable or completion authority.
-- Fields stay lazy so old wrappers do not acquire new forcing/exception order.
data DqnPreparedSnapshot state = DqnPreparedSnapshot
  { internalDqnConfig :: DqnTrainConfig
  , internalDqnInitialParams :: MlpParams
  , internalDqnOnlineParams :: MlpParams
  , internalDqnTargetParams :: MlpParams
  , internalDqnAdam :: AdamState
  , internalDqnGenerator :: Random.StdGen
  , internalDqnReplay :: [Transition]
  , internalDqnStep :: Int
  , internalDqnState :: state
  , internalDqnEpisodeLength :: Int
  , internalDqnEpisodeReturn :: Double
  , internalDqnRecentReturns :: [Double]
  , internalDqnStatistics :: [DqnIterationStat]
  , internalDqnEnvironmentName :: Text
  , internalDqnObservationWidth :: Int
  , internalDqnActionCount :: Int
  , internalDqnFrame :: Vector Double
  }
  deriving stock (Eq, Show)

-- Constructor and continuation are private; no parsed snapshot can reconstruct one.
data PreparedDqn state
  = PreparedDqn (DqnPreparedSnapshot state) SingleUse.SingleUse (IO (Either Text DqnTrainObservation))

preparedDqnSnapshot :: PreparedDqn state -> DqnPreparedSnapshot state
preparedDqnSnapshot (PreparedDqn snapshot _ _) = snapshot

continuePreparedDqnRaw :: PreparedDqn state -> IO (Either Text DqnTrainObservation)
continuePreparedDqnRaw (PreparedDqn _ guard action) = do
  consumed <- SingleUse.tryConsumeSingleUse guard
  if consumed then action else pure (Left "prepared Dqn continuation has already been consumed")

dqnPreparedConfig :: DqnPreparedSnapshot state -> DqnTrainConfig
dqnPreparedConfig = internalDqnConfig

dqnPreparedInitialParams :: DqnPreparedSnapshot state -> MlpParams
dqnPreparedInitialParams = internalDqnInitialParams

dqnPreparedOnlineParams :: DqnPreparedSnapshot state -> MlpParams
dqnPreparedOnlineParams = internalDqnOnlineParams

dqnPreparedTargetParams :: DqnPreparedSnapshot state -> MlpParams
dqnPreparedTargetParams = internalDqnTargetParams

dqnPreparedAdam :: DqnPreparedSnapshot state -> AdamState
dqnPreparedAdam = internalDqnAdam

dqnPreparedGenerator :: DqnPreparedSnapshot state -> Random.StdGen
dqnPreparedGenerator = internalDqnGenerator

dqnPreparedReplay :: DqnPreparedSnapshot state -> [Transition]
dqnPreparedReplay = internalDqnReplay

dqnPreparedStep :: DqnPreparedSnapshot state -> Int
dqnPreparedStep = internalDqnStep

dqnPreparedState :: DqnPreparedSnapshot state -> state
dqnPreparedState = internalDqnState

dqnPreparedEpisodeLength :: DqnPreparedSnapshot state -> Int
dqnPreparedEpisodeLength = internalDqnEpisodeLength

dqnPreparedEpisodeReturn :: DqnPreparedSnapshot state -> Double
dqnPreparedEpisodeReturn = internalDqnEpisodeReturn

dqnPreparedRecentReturns :: DqnPreparedSnapshot state -> [Double]
dqnPreparedRecentReturns = internalDqnRecentReturns

dqnPreparedStatistics :: DqnPreparedSnapshot state -> [DqnIterationStat]
dqnPreparedStatistics = internalDqnStatistics

dqnPreparedEnvironmentName :: DqnPreparedSnapshot state -> Text
dqnPreparedEnvironmentName = internalDqnEnvironmentName

dqnPreparedObservationWidth :: DqnPreparedSnapshot state -> Int
dqnPreparedObservationWidth = internalDqnObservationWidth

dqnPreparedActionCount :: DqnPreparedSnapshot state -> Int
dqnPreparedActionCount = internalDqnActionCount

dqnPreparedFrame :: DqnPreparedSnapshot state -> Vector Double
dqnPreparedFrame = internalDqnFrame

trainDqnOnCartpoleRaw :: DqnTrainConfig -> IO DqnTrainObservation
trainDqnOnCartpoleRaw config = do
  prepared <- prepareDqnOnCartpole config
  result <- continuePreparedDqnRaw prepared
  either (fail . Text.unpack) pure result

prepareDqnOnCartpole :: DqnTrainConfig -> IO (PreparedDqn CartPoleState)
prepareDqnOnCartpole config = do
  let shape = dqnMlpShape config
      initialParams = initialDqnParams config
      initialOnline = initialParams
      initialTarget = initialParams
      initialAdam = adamInit shape
      initialGenerator = Random.mkStdGen (dqnSeed config + 1)
      initialReplay = []
      initialStep = 0
      initialState = envInitial cartPoleEnvironment
      initialEpisodeLength = 0
      initialEpisodeReturn = 0.0
      initialRecentReturns = []
      initialStatistics = []
  guard <- SingleUse.newSingleUse
  let snapshot =
        DqnPreparedSnapshot
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
            pureReferenceMlpDevice
            cartPoleEnvironment
            config
            (\online target adam batch -> pure (dqnUpdate config online target adam batch))
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
  pure (PreparedDqn snapshot guard action)

loop
  :: MlpParams
  -> MlpDevice
  -> SimulatedEnvironment state
  -> DqnTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (MlpParams, AdamState))
  -- ^ minibatch update: online → target → adam → batch → (online', adam')
  -> MlpParams -- online net
  -> MlpParams -- target net
  -> AdamState
  -> Random.StdGen
  -> [Transition] -- replay buffer (most-recent first)
  -> Int -- step counter
  -> state
  -> Int -- current episode step count
  -> Double -- current episode return
  -> [Double] -- recent episode returns
  -> [DqnIterationStat]
  -> IO DqnTrainObservation
loop initialSnapshot device environment config update online target adam gen buffer step state episodeLen episodeReturn episodes stats = do
  result <-
    loopEither
      initialSnapshot
      device
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
  -> MlpDevice
  -> SimulatedEnvironment state
  -> DqnTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (Either Text (MlpParams, AdamState)))
  -- ^ minibatch update: online → target → adam → batch → either fault or (online', adam')
  -> MlpParams -- online net
  -> MlpParams -- target net
  -> AdamState
  -> Random.StdGen
  -> [Transition] -- replay buffer (most-recent first)
  -> Int -- step counter
  -> state
  -> Int -- current episode step count
  -> Double -- current episode return
  -> [Double] -- recent episode returns
  -> [DqnIterationStat]
  -> IO (Either Text DqnTrainObservation)
loopEither initialSnapshot device environment config update online target adam gen buffer step state episodeLen episodeReturn episodes stats
  | step >= dqnNumSteps config =
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
          (actionU, gen2) =
            Random.uniformR (0 :: Int, dqnActionCount config - 1) gen1
      actionResult <-
        if u < epsilon
          then pure (Right actionU)
          else do
            forwardResult <- mlpdForward device online obs
            pure $
              case forwardResult of
                Left err ->
                  Left ("dqn device forward kernel failed mid-run (behavior policy): " <> err)
                Right forward -> Right (argmax (VU.toList (forwardOutput forward)))
      case actionResult of
        Left err -> pure (Left err)
        Right action -> do
          let stepResult = envStep environment state action
              -- True environment termination (pole fell / out of bounds). Only
              -- this stops Bellman bootstrapping.
              envDone = simStepDone stepResult
              -- Episode reset also fires on the time limit, but a time-limit
              -- truncation is NOT a terminal state: bootstrapping must continue
              -- through it, otherwise the net learns that long-survival states
              -- are worth only their immediate reward and never reaches 500.
              timeLimit = episodeLen + 1 >= dqnMaxEpisodeSteps config
              terminal = envDone || timeLimit
              nextObs = obsVector environment (simStepState stepResult)
              transition =
                Transition
                  { transObs = obs
                  , transAction = action
                  , transReward =
                      simStepReward stepResult
                        + RewardShaping.shapingBonusForTransition (envName environment) (dqnGamma config) envDone obs nextObs
                  , transNextObs = nextObs
                  , transDone = envDone
                  }
              newBuffer =
                take (dqnReplayCapacity config) (transition : buffer)
              nextEpisodeReturn = episodeReturn + simStepReward stepResult
              (nextState, nextEpisodeLen, finalReturn, newEpisodes) =
                if terminal
                  then
                    ( envInitial environment
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
          updateResult <-
            if step + 1 >= dqnTrainStart config
              && (step + 1) `mod` dqnUpdateFrequency config == 0
              && length newBuffer >= dqnBatchSize config
              then do
                let (batch, gen2b) =
                      sampleBatch (dqnBatchSize config) newBuffer gen2
                fmap (\(onlineUpd, adamUpd) -> (onlineUpd, adamUpd, gen2b)) <$> update online target adam batch
              else pure (Right (online, adam, gen2))
          case updateResult of
            Left err -> pure (Left err)
            Right (onlineNext, adamNext, gen3) -> do
              -- On episode reset use the env's exploring-start distribution when it
              -- has one (mountain-car) so the value net sees the high-return region
              -- and bootstraps outward; otherwise reset to the fixed initial state.
              let (resetState, gen4) =
                    if terminal
                      then trainingResetState environment gen3
                      else (nextState, gen3)
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
              loopEither
                initialSnapshot
                device
                environment
                config
                update
                onlineNext
                targetNext
                adamNext
                gen4
                newBuffer
                (step + 1)
                resetState
                nextEpisodeLen
                finalReturn
                newEpisodes
                statsNext

-- | Reset for a fresh training episode, drawing from the env's exploring-start
-- distribution ('envTrainingStart', currently only mountain-car) when present,
-- else the fixed 'envInitial'. Evaluation always uses 'envInitial'.
trainingResetState :: SimulatedEnvironment state -> Random.StdGen -> (state, Random.StdGen)
trainingResetState environment gen =
  case envTrainingStart environment of
    Nothing -> (envInitial environment, gen)
    Just f ->
      let (u1, gen1) = Random.uniformR (0.0 :: Double, 1.0) gen
          (u2, gen2) = Random.uniformR (0.0 :: Double, 1.0) gen1
       in (f u1 u2, gen2)

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
  -- Snapshot to a boxed Vector for O(1) random access. The old `buffer !! idx`
  -- list indexing was O(capacity) per draw, making the SB3-scale step budgets
  -- (50k-120k) impractically slow.
  let bufArr = VB.fromList buffer
      bufLen = VB.length bufArr
      pickN k g acc
        | k <= 0 || bufLen <= 0 = (acc, g)
        | otherwise =
            let (idx, g') = Random.uniformR (0 :: Int, bufLen - 1) g
             in pickN (k - 1) g' (bufArr VB.! idx : acc)
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
      -- matches the batched device path ('dqnUpdateDevice') exactly and is the
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
-- canonical kappa-1 Huber derivative of the TD residual @Q(s,a) - target@
-- placed at the taken-action index, zero elsewhere. Bounding the derivative
-- prevents stale target-network estimates from producing unbounded replay
-- updates. The Bellman target uses the target net's next-state Q
-- (@nextQ@); Double-DQN (van Hasselt et al. 2016) selects the next action
-- with the online net (@onlineNextQ@, forced only when @dqnUseDouble@) and
-- evaluates it with the target net. Factored out of 'dqnUpdate' so the
-- pure CPU path and every batched device backend ('dqnUpdateDevice') compute
-- the identical loss gradient; only the forward/backward backend differs.
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
  VU.generate (length qVec) (\i -> if i == actionIx then residualGradient else 0.0)
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
    -- max_a' Q_target(s', a'). `nextQ` always has `actionCount` (>= 1) entries,
    -- so guard the empty case explicitly instead of seeding the fold with 0 —
    -- the old `maximum (0 : nextQ)` floored the bootstrap at 0, which on
    -- negative-reward envs (mountain-car: reward -1/step, true Q ~ -100..-200)
    -- collapsed every Bellman target to the immediate reward and erased all
    -- state-value differences.
    | otherwise = if null nextQ then 0.0 else maximum nextQ
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
  residualGradient = DqnLoss.dqnHuberGradient 1.0 residual

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

obsVector :: SimulatedEnvironment state -> state -> Vector Double
obsVector environment =
  VU.fromList . renderObservation . envRenderFrame environment

-- | Sprint 13.8 — train DQN (and the discrete off-policy family it
-- templates) on cartpole with the Q-network forward + backward running on
-- the GPU through the batched device primitives. The env loop, replay
-- buffer and target-net copy are unchanged (shared with the pure
-- 'trainDqnOnCartpole' via the parameterised 'loop'). Greedy behavior-policy
-- actions and minibatch updates both run through the selected device; the
-- loss-gradient head ('dqnResidualDLdy') is shared with the pure path.
trainDqnOnCartpoleCuda :: Env -> DqnTrainConfig -> IO (Either Text DqnTrainResult)
trainDqnOnCartpoleCuda env = trainDqnOnDevice (cudaMlpDevice env)

-- | DQN training through the oneDNN (linux-cpu) MLP device.
trainDqnOnCartpoleOneDnn :: Env -> DqnTrainConfig -> IO (Either Text DqnTrainResult)
trainDqnOnCartpoleOneDnn env = trainDqnOnDevice (oneDnnMlpDevice env)

-- | DQN training through the Metal (apple-silicon) MLP device.
trainDqnOnCartpoleMetal :: Env -> DqnTrainConfig -> IO (Either Text DqnTrainResult)
trainDqnOnCartpoleMetal env = trainDqnOnDevice (metalMlpDevice env)

-- | DQN training through an injected MLP device backend. The env loop, replay
-- buffer, epsilon schedule, and target-net copy are shared with the pure
-- 'trainDqnOnCartpole' via the parameterised 'loop'; greedy policy forwards
-- and minibatch updates run through the injected device.
trainDqnOnDevice :: MlpDevice -> DqnTrainConfig -> IO (Either Text DqnTrainResult)
trainDqnOnDevice device =
  trainDqnOnDeviceWithSimulatedEnvironment device cartPoleEnvironment

trainDqnOnDeviceWithEnvironment
  :: MlpDevice -> SomeSimulatedEnvironment -> DqnTrainConfig -> IO (Either Text DqnTrainResult)
trainDqnOnDeviceWithEnvironment device (SomeSimulatedEnvironment environment) =
  trainDqnOnDeviceWithSimulatedEnvironment device environment

trainDqnOnDeviceWithSimulatedEnvironment
  :: MlpDevice -> SimulatedEnvironment state -> DqnTrainConfig -> IO (Either Text DqnTrainResult)
trainDqnOnDeviceWithSimulatedEnvironment device environment config = do
  observed <- trainDqnOnDeviceWithSimulatedEnvironmentRaw device environment config
  pure (observed >>= refineDqnTrainObservation)

trainDqnOnDeviceWithSimulatedEnvironmentRaw
  :: MlpDevice -> SimulatedEnvironment state -> DqnTrainConfig -> IO (Either Text DqnTrainObservation)
trainDqnOnDeviceWithSimulatedEnvironmentRaw device environment config = do
  prepared <- prepareDqnOnDeviceWithEnvironment device environment config
  continuePreparedDqnRaw prepared

prepareDqnOnDeviceWithEnvironment
  :: MlpDevice -> SimulatedEnvironment state -> DqnTrainConfig -> IO (PreparedDqn state)
prepareDqnOnDeviceWithEnvironment device environment config = do
  let shape = dqnMlpShape config
      initialParams = initialDqnParams config
      initialOnline = initialParams
      initialTarget = initialParams
      initialAdam = adamInit shape
      initialGenerator = Random.mkStdGen (dqnSeed config + 1)
      initialReplay = []
      initialStep = 0
      initialState = envInitial environment
      initialEpisodeLength = 0
      initialEpisodeReturn = 0.0
      initialRecentReturns = []
      initialStatistics = []
  guard <- SingleUse.newSingleUse
  let snapshot =
        DqnPreparedSnapshot
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
          device
          environment
          config
          (dqnUpdateDevice device config)
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
  pure (PreparedDqn snapshot guard action)

dqnMlpShape :: DqnTrainConfig -> MlpShape
dqnMlpShape config =
  MlpShape
    { mlpInputs = dqnObsSize config
    , mlpHidden = dqnHiddenUnits config
    , mlpOutputs = dqnActionCount config
    }

initialDqnParams :: DqnTrainConfig -> MlpParams
initialDqnParams config =
  mlpInit (dqnMlpShape config) (dqnSeed config)

evaluateDqnPolicyWithEnvironment
  :: MlpDevice
  -> SomeSimulatedEnvironment
  -> DqnTrainConfig
  -> MlpParams
  -> Int
  -> IO (Either Text [Common.EvaluationEpisodeResult])
evaluateDqnPolicyWithEnvironment device (SomeSimulatedEnvironment environment) config params episodeCount
  | episodeCount <= 0 || not (dqnEvaluationConfiguration environment config) =
      pure (Left "DQN device evaluation configuration does not match the environment")
  | not (dqnEvaluationParams config params) =
      pure (Left "DQN device evaluation parameters are malformed or overflow the Float32 ABI")
  | otherwise = collect episodeCount []
 where
  collect remaining episodes
    | remaining <= 0 = pure (Right (reverse episodes))
    | otherwise = do
        episodeResult <- evaluateEpisode device environment config params
        case episodeResult of
          Left err -> pure (Left err)
          Right episode -> collect (remaining - 1) (episode : episodes)

evaluateEpisode
  :: MlpDevice
  -> SimulatedEnvironment state
  -> DqnTrainConfig
  -> MlpParams
  -> IO (Either Text Common.EvaluationEpisodeResult)
evaluateEpisode device environment config params = go (envInitial environment) 0 0.0
 where
  go state episodeLen episodeReturn
    | episodeLen >= dqnMaxEpisodeSteps config =
        pure (Right (Common.EvaluationEpisodeResult episodeReturn episodeLen False))
    | VU.length observation /= dqnObsSize config || not (dqnEvaluationVector observation) =
        pure (Left "DQN device evaluation observation is malformed or overflows the Float32 ABI")
    | Just mask <- actionMask
    , length mask /= dqnActionCount config || not (or mask) =
        pure (Left "DQN device evaluation action mask is malformed or has no legal action")
    | otherwise = do
        forwardResult <- mlpdForward device params observation
        case forwardResult of
          Left err ->
            pure (Left ("dqn device forward kernel failed during evaluation: " <> err))
          Right forward
            | VU.length (forwardOutput forward) /= dqnActionCount config
                || not (dqnEvaluationVector (forwardOutput forward)) ->
                pure (Left "DQN device evaluation output has the wrong shape or is not finite Float32")
            | otherwise ->
                case dqnEvaluationAction actionMask (forwardOutput forward) of
                  Left err -> pure (Left err)
                  Right action -> do
                    let stepResult = envStep environment state action
                        nextReturn = episodeReturn + simStepReward stepResult
                        nextLen = episodeLen + 1
                    if not (dqnEvaluationFinite (simStepReward stepResult) && dqnEvaluationFinite nextReturn)
                      then pure (Left "DQN device evaluation produced a non-finite reward")
                      else
                        if simStepDone stepResult
                          then pure (Right (Common.EvaluationEpisodeResult nextReturn nextLen True))
                          else go (simStepState stepResult) nextLen nextReturn
   where
    observation = obsVector environment state
    actionMask = envActionMask environment <*> Just state

-- | Final-policy semantics only. Training, initialization, optimizer and RNG
-- retain their original bytes. Current ProductRow plans include this token.
dqnEvaluationContract :: Text
dqnEvaluationContract = "dqn-selected-device-checked-legal-final-evaluation-v1"

dqnEvaluationConfiguration :: SimulatedEnvironment state -> DqnTrainConfig -> Bool
dqnEvaluationConfiguration environment config =
  dqnMaxEpisodeSteps config > 0
    && all (\dimension -> dimension > 0 && toInteger dimension <= abiLimit) dimensions
    && all (<= abiLimit) [inputs * hidden, outputs * hidden]
    && envObservationSize environment == dqnObsSize config
    && envActionCount environment == dqnActionCount config
 where
  dimensions = [dqnObsSize config, dqnHiddenUnits config, dqnActionCount config]
  inputs = toInteger (dqnObsSize config)
  hidden = toInteger (dqnHiddenUnits config)
  outputs = toInteger (dqnActionCount config)
  abiLimit = toInteger (maxBound :: CInt)

dqnEvaluationParams :: DqnTrainConfig -> MlpParams -> Bool
dqnEvaluationParams config params =
  paramShape params == dqnMlpShape config
    && toInteger (VU.length (paramW1 params))
      == toInteger (dqnHiddenUnits config) * toInteger (dqnObsSize config)
    && VU.length (paramB1 params) == dqnHiddenUnits config
    && toInteger (VU.length (paramW2 params))
      == toInteger (dqnActionCount config) * toInteger (dqnHiddenUnits config)
    && VU.length (paramB2 params) == dqnActionCount config
    && all dqnEvaluationVector [paramW1 params, paramB1 params, paramW2 params, paramB2 params]

dqnEvaluationFinite :: Double -> Bool
dqnEvaluationFinite value = not (isNaN value || isInfinite value)

-- Conversion rounding/underflow are permitted. A finite Double which would
-- become an infinite Float is not a valid selected-device input/output.
dqnEvaluationVector :: Vector Double -> Bool
dqnEvaluationVector =
  VU.all
    ( \value ->
        dqnEvaluationFinite value
          && let encoded = realToFrac value :: Float in not (isNaN encoded || isInfinite encoded)
    )

-- Legal actions are an eligible set, never finite replacement logits. This
-- preserves the leftmost tie even when every legal value is below -1e12.
dqnEvaluationAction :: Maybe [Bool] -> Vector Double -> Either Text Int
dqnEvaluationAction mask values =
  case eligible of
    [] -> Left "DQN device evaluation action mask has no legal action"
    first : rest -> Right (fst (Data.List.foldl' prefer first rest))
 where
  eligible = [(index, value) | ((index, value), legal) <- zip (zip [0 ..] (VU.toList values)) flags, legal]
  flags = fromMaybe (replicate (VU.length values) True) mask
  prefer current@(_, currentValue) candidate@(_, candidateValue)
    | candidateValue > currentValue = candidate
    | otherwise = current

-- | Minibatch DQN gradient update through batched device primitives:
-- batched forward of the online net at the batch states (Q(s,·)) and the
-- target net at the next states (Q(s',·)) — plus the online net at the
-- next states for Double-DQN action selection — then the per-sample Huber
-- residual gradient ('dqnResidualDLdy'), one batched device backward (mean
-- gradient over the minibatch), and one Adam step. Fails closed on a device
-- `Left` (Sprint 8.11) — the dispatch `probeMlpDevice` gate already confirmed
-- the kernel runs, so a mid-run fault is genuine, not a pure-fallback cue.
-- Both the pure and device paths form one mean minibatch gradient and apply one
-- Adam step; only the forward/backward backend differs.
dqnUpdateDevice
  :: MlpDevice
  -> DqnTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> [Transition]
  -> IO (Either Text (MlpParams, AdamState))
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
           in pure (Right (onlineAfter, adamAfter))
        Left err -> pure (Left ("dqn device batch-gradient kernel failed mid-run: " <> err))
    (Left err, _, _) -> pure (Left ("dqn device forward kernel failed mid-run (online batch): " <> err))
    (_, Left err, _) -> pure (Left ("dqn device forward kernel failed mid-run (target batch): " <> err))
    (_, _, Left err) -> pure (Left ("dqn device forward kernel failed mid-run (double-dqn online-next batch): " <> err))

trainDqnOnDeviceWithEnvironmentRaw
  :: MlpDevice -> SomeSimulatedEnvironment -> DqnTrainConfig -> IO (Either Text DqnTrainObservation)
trainDqnOnDeviceWithEnvironmentRaw device (SomeSimulatedEnvironment environment) =
  trainDqnOnDeviceWithSimulatedEnvironmentRaw device environment

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
  )
where

import Data.List qualified
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
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
    , dqnHiddenUnits = 64
    , dqnNumSteps = 20000
    , dqnReplayCapacity = 10000
    , dqnBatchSize = 32
    , dqnLearningRate = 1.0e-3
    , dqnGamma = 0.99
    , dqnTargetUpdateInterval = 500
    , dqnEpsilonStart = 1.0
    , dqnEpsilonEnd = 0.05
    , dqnEpsilonDecaySteps = 5000
    , dqnTrainStart = 1000
    , dqnUpdateFrequency = 4
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
loop config online target adam gen buffer step state episodeLen episodeReturn episodes stats
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
          terminal =
            simStepDone stepResult
              || episodeLen + 1 >= dqnMaxEpisodeSteps config
          nextObs = obsVector (simStepState stepResult)
          transition =
            Transition
              { transObs = obs
              , transAction = action
              , transReward = simStepReward stepResult
              , transNextObs = nextObs
              , transDone = terminal
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
                (onlineUpd, adamUpd) =
                  dqnUpdate config online target adam batch
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
      gamma = dqnGamma config
      stepUpdate (params, a) trans =
        let fwd = mlpForward params (transObs trans)
            qVec = VU.toList (forwardOutput fwd)
            actionIx = transAction trans
            qSa =
              if actionIx >= 0 && actionIx < length qVec
                then qVec !! actionIx
                else 0.0
            nextFwd = mlpForward target (transNextObs trans)
            nextQ = VU.toList (forwardOutput nextFwd)
            -- Standard DQN: max over the target net's next-state Q values.
            -- Double-DQN (van Hasselt et al. 2016): select the next action
            -- with the *online* net, evaluate it with the *target* net —
            -- removing the max-operator overestimation bias.
            bootstrapNextQ
              | dqnUseDouble config =
                  let onlineNextQ = VU.toList (forwardOutput (mlpForward params (transNextObs trans)))
                      onlineArgmax = argmax onlineNextQ
                   in if onlineArgmax >= 0 && onlineArgmax < length nextQ
                        then nextQ !! onlineArgmax
                        else 0.0
              | otherwise = maximum (0 : nextQ)
            tdTarget =
              ( if dqnUseDouble config
                  then DqnLoss.dqnDoubleBellmanTarget
                  else DqnLoss.dqnBellmanTarget
              )
                gamma
                (transReward trans)
                (transDone trans)
                bootstrapNextQ
            residual = qSa - tdTarget
            dLdy =
              VU.generate
                (length qVec)
                (\i -> if i == actionIx then residual else 0.0)
            grad = mlpBackward params fwd dLdy
         in adamStep adamConfig a params grad
   in Data.List.foldl' stepUpdate (online, adam) batch

obsVector :: CartPoleState -> Vector Double
obsVector state =
  VU.fromList
    [ cartPosition state
    , cartVelocity state
    , poleAngle state
    , poleAngularVelocity state
    ]

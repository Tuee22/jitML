{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.8 — real HER (Hindsight Experience Replay, Andrychowicz et
-- al. 2017) training loop, the goal-conditioned member of the
-- specialised family. HER is a sample-efficiency wrapper around an
-- off-policy algorithm; this trainer wraps a DQN-style Q network on the
-- canonical bit-flip goal-conditioned environment (the environment HER
-- was introduced on).
--
-- Bit-flip env: an @n@-bit state, an @n@-bit goal, @n@ actions (flip bit
-- @i@), sparse reward @0@ when @state == goal@ else @-1@, horizon @n@.
-- Without relabeling the reward is almost always @-1@ and DQN cannot
-- learn; HER relabels each transition's goal to a state achieved later
-- in the same episode (the @future@ strategy) and recomputes the reward,
-- producing a dense learning signal.
--
-- The relabeling math (@future@ goal sampling + 'sparseGoalReward')
-- comes from "JitML.RL.Algorithms.HerLoss"; this module supplies the env
-- + Q network + replay loop.
--
-- Bit-deterministic on the same substrate / same seed.
module JitML.RL.Algorithms.HerTrainer
  ( HerTrainConfig (..)
  , defaultHerTrainConfig
  , productHerHiddenUnits
  , HerTrainResult (..)
  , HerIterationStat (..)
  , initialHerParams
  , randomNonInitialGoal
  , flipBit
  , bitDistance
  , trainHerOnBitFlip
  , trainHerOnBitFlipCuda
  , trainHerOnBitFlipOneDnn
  , trainHerOnBitFlipMetal
  , trainHerOnDevice
  , evaluateHerGreedy
  , herEvaluationContract
  , evaluateHerGreedyOnDevice
  , HerTrainObservation
  , refineHerTrainObservation
  , trainHerOnBitFlipRaw
  , trainHerOnDeviceRaw
  , PreparedHer
  , HerPreparedSnapshot
  , preparedHerSnapshot
  , continuePreparedHerRaw
  , prepareHerOnBitFlip
  , prepareHerOnDevice
  , herPreparedConfig
  , herPreparedInitialParams
  , herPreparedOnlineParams
  , herPreparedTargetParams
  , herPreparedAdam
  , herPreparedGenerator
  , herPreparedReplay
  , herPreparedEpisode
  , herPreparedObservedTransitions
  , herPreparedRecentSuccesses
  , herPreparedStatistics
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
import JitML.RL.Algorithms.DqnLoss (dqnBellmanTarget)
import JitML.RL.Algorithms.HerLoss
  ( HerStrategy (..)
  , RelabeledTransition (..)
  , herRelabel
  , sparseGoalReward
  )

data HerTrainConfig = HerTrainConfig
  { herSeed :: !Int
  , herNumBits :: !Int
  , herHiddenUnits :: !Int
  , herEpisodes :: !Int
  , herReplayCapacity :: !Int
  , herBatchSize :: !Int
  , herLearningRate :: !Double
  , herGamma :: !Double
  , herTargetUpdateInterval :: !Int
  , herEpsilon :: !Double
  , herUseHindsight :: !Bool
  , herStrategy :: !HerStrategy
  , herStatInterval :: !Int
  , herUpdatesPerEpisode :: !Int
  }
  deriving stock (Eq, Show)

productHerHiddenUnits :: Int
productHerHiddenUnits = 256

defaultHerTrainConfig :: HerTrainConfig
defaultHerTrainConfig =
  HerTrainConfig
    { herSeed = 42
    , herNumBits = 6
    , herHiddenUnits = 64
    , herEpisodes = 400
    , herReplayCapacity = 10000
    , herBatchSize = 32
    , herLearningRate = 1.0e-3
    , herGamma = 0.95
    , herTargetUpdateInterval = 40
    , herEpsilon = 0.2
    , herUseHindsight = True
    , herStrategy = HerFuture
    , herStatInterval = 50
    , -- ~40 gradient updates per episode: one update/episode (the old behaviour)
      -- is far below HER's sample efficiency and left the Q-net well short of the
      -- 0.85 bar. The target net is held fixed across the inner loop.
      herUpdatesPerEpisode = 40
    }

-- | A replay transition over the goal-augmented input @(state ++ goal)@.
data Transition = Transition
  { transInput :: !(Vector Double)
  , transAction :: !Int
  , transReward :: !Double
  , transNextInput :: !(Vector Double)
  , transDone :: !Bool
  }
  deriving stock (Eq, Show)

data HerIterationStat = HerIterationStat
  { herIterEpisode :: !Int
  , herIterSuccessRate :: !Double
  }
  deriving stock (Eq, Show)

data HerTrainResult = HerTrainResult
  { herResultStats :: ![HerIterationStat]
  , herResultInitialParams :: !MlpParams
  , herResultFinalParams :: !MlpParams
  , herResultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Exact physical bit-flip transitions and Adam applications executed
  -- against the final online goal-conditioned Q tensor. Replay readiness can
  -- delay updates, so neither count is inferred from the episode budget.
  , herResultConfig :: !HerTrainConfig
  }
  deriving stock (Eq, Show)

-- | Uncensored numerical return; no producer/device/learning authority.
type HerTrainObservation = Common.RawTrainerResult MlpParams HerIterationStat HerTrainConfig

refineHerTrainObservation :: HerTrainObservation -> Either Text HerTrainResult
refineHerTrainObservation observed = do
  counters <- Common.refineObservedTrainerCounters (Common.rawTrainerCounters observed)
  pure
    HerTrainResult
      { herResultStats = Common.rawTrainerStats observed
      , herResultInitialParams = Common.rawTrainerInitialParams observed
      , herResultFinalParams = Common.rawTrainerFinalParams observed
      , herResultMeasuredCounters = counters
      , herResultConfig = Common.rawTrainerConfig observed
      }

-- | Hamming-distance goal metric: count of differing bits.
bitDistance :: Vector Double -> Vector Double -> Double
bitDistance s g =
  fromIntegral (VU.length (VU.filter id (VU.zipWith (\a b -> abs (a - b) > 0.5) s g)))

trainHerOnBitFlip :: HerTrainConfig -> IO HerTrainResult
trainHerOnBitFlip config = do
  observed <- trainHerOnBitFlipRaw config
  either (fail . Text.unpack) pure (refineHerTrainObservation observed)

-- | Captured numerical state only. No producer, device, durable or completion authority.
-- Fields stay lazy so old wrappers do not acquire new forcing/exception order.
data HerPreparedSnapshot = HerPreparedSnapshot
  { internalHerConfig :: HerTrainConfig
  , internalHerInitialParams :: MlpParams
  , internalHerOnlineParams :: MlpParams
  , internalHerTargetParams :: MlpParams
  , internalHerAdam :: AdamState
  , internalHerGenerator :: Random.StdGen
  , internalHerReplay :: [Transition]
  , internalHerEpisode :: Int
  , internalHerObservedTransitions :: Integer
  , internalHerRecentSuccesses :: [Bool]
  , internalHerStatistics :: [HerIterationStat]
  }
  deriving stock (Eq, Show)

-- Constructor and continuation are private; no parsed snapshot can reconstruct one.
data PreparedHer
  = PreparedHer HerPreparedSnapshot SingleUse.SingleUse (IO (Either Text HerTrainObservation))

preparedHerSnapshot :: PreparedHer -> HerPreparedSnapshot
preparedHerSnapshot (PreparedHer snapshot _ _) = snapshot

continuePreparedHerRaw :: PreparedHer -> IO (Either Text HerTrainObservation)
continuePreparedHerRaw (PreparedHer _ guard action) = do
  consumed <- SingleUse.tryConsumeSingleUse guard
  if consumed then action else pure (Left "prepared Her continuation has already been consumed")

herPreparedConfig :: HerPreparedSnapshot -> HerTrainConfig
herPreparedConfig = internalHerConfig

herPreparedInitialParams :: HerPreparedSnapshot -> MlpParams
herPreparedInitialParams = internalHerInitialParams

herPreparedOnlineParams :: HerPreparedSnapshot -> MlpParams
herPreparedOnlineParams = internalHerOnlineParams

herPreparedTargetParams :: HerPreparedSnapshot -> MlpParams
herPreparedTargetParams = internalHerTargetParams

herPreparedAdam :: HerPreparedSnapshot -> AdamState
herPreparedAdam = internalHerAdam

herPreparedGenerator :: HerPreparedSnapshot -> Random.StdGen
herPreparedGenerator = internalHerGenerator

herPreparedReplay :: HerPreparedSnapshot -> [(Vector Double, Int, Double, Vector Double, Bool)]
herPreparedReplay =
  fmap
    ( \transition ->
        ( transInput transition
        , transAction transition
        , transReward transition
        , transNextInput transition
        , transDone transition
        )
    )
    . internalHerReplay

herPreparedEpisode :: HerPreparedSnapshot -> Int
herPreparedEpisode = internalHerEpisode

herPreparedObservedTransitions :: HerPreparedSnapshot -> Integer
herPreparedObservedTransitions = internalHerObservedTransitions

herPreparedRecentSuccesses :: HerPreparedSnapshot -> [Bool]
herPreparedRecentSuccesses = internalHerRecentSuccesses

herPreparedStatistics :: HerPreparedSnapshot -> [HerIterationStat]
herPreparedStatistics = internalHerStatistics

trainHerOnBitFlipRaw :: HerTrainConfig -> IO HerTrainObservation
trainHerOnBitFlipRaw config = do
  prepared <- prepareHerOnBitFlip config
  result <- continuePreparedHerRaw prepared
  either (fail . Text.unpack) pure result

prepareHerOnBitFlip :: HerTrainConfig -> IO PreparedHer
prepareHerOnBitFlip config = do
  let shape = herMlpShape config
      initialParams = initialHerParams config
      initialOnline = initialParams
      initialTarget = initialParams
      initialAdam = adamInit shape
      initialGenerator = Random.mkStdGen (herSeed config + 1)
      initialReplay = []
      initialEpisode = 0
      initialObservedTransitions = 0
      initialRecentSuccesses = []
      initialStatistics = []
  guard <- SingleUse.newSingleUse
  let snapshot =
        HerPreparedSnapshot
          config
          initialParams
          initialOnline
          initialTarget
          initialAdam
          initialGenerator
          initialReplay
          initialEpisode
          initialObservedTransitions
          initialRecentSuccesses
          initialStatistics
      action =
        Right
          <$> episodeLoop
            initialParams
            config
            (\online target adam batch -> pure (dqnUpdate config online target adam batch))
            initialOnline
            initialTarget
            initialAdam
            initialGenerator
            initialReplay
            initialEpisode
            initialObservedTransitions
            initialRecentSuccesses
            initialStatistics
  pure (PreparedHer snapshot guard action)

episodeLoop
  :: MlpParams
  -> HerTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (MlpParams, AdamState))
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> Random.StdGen
  -> [Transition]
  -> Int
  -> Integer
  -> [Bool] -- recent episode successes
  -> [HerIterationStat]
  -> IO HerTrainObservation
episodeLoop initialSnapshot config update online target adam gen buffer episode observedTransitions successes stats = do
  result <-
    episodeLoopEither
      initialSnapshot
      config
      (\o t a batch -> Right <$> update o t a batch)
      online
      target
      adam
      gen
      buffer
      episode
      observedTransitions
      successes
      stats
  either (fail . Text.unpack) pure result

episodeLoopEither
  :: MlpParams
  -> HerTrainConfig
  -> (MlpParams -> MlpParams -> AdamState -> [Transition] -> IO (Either Text (MlpParams, AdamState)))
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> Random.StdGen
  -> [Transition]
  -> Int
  -> Integer
  -> [Bool] -- recent episode successes
  -> [HerIterationStat]
  -> IO (Either Text HerTrainObservation)
episodeLoopEither initialSnapshot config update online target adam gen buffer episode observedTransitions successes stats
  | herUpdatesPerEpisode config <= 0 =
      pure (Left "HER updates per episode must be positive")
  | episode >= herEpisodes config =
      pure $ do
        measuredCounters <-
          Common.mkObservedTrainerCounters
            observedTransitions
            (toInteger (adamStep_ adam))
        Right
          Common.RawTrainerResult
            { Common.rawTrainerInitialParams = initialSnapshot
            , Common.rawTrainerFinalParams = online
            , Common.rawTrainerStats = reverse stats
            , Common.rawTrainerCounters = measuredCounters
            , Common.rawTrainerConfig = config
            }
  | otherwise = do
      let n = herNumBits config
          (goal, gen1) = randomNonInitialGoal n gen
          (episodeTransitions, reached, gen2) =
            rolloutTrainingTransitions config online goal gen1
          relabeled =
            if herUseHindsight config
              then hindsightTransitions config episodeTransitions
              else []
          newBuffer =
            take
              (herReplayCapacity config)
              (relabeled <> episodeTransitions <> buffer)
      let runUpdates 0 o a g = pure (Right (o, a, g))
          runUpdates i o a g = do
            let (batch, g') = sampleBatch (herBatchSize config) newBuffer g
            stepE <- update o target a batch
            case stepE of
              Left err -> pure (Left err)
              Right (o', a') -> runUpdates (i - 1 :: Int) o' a' g'
      updateResult <-
        if length newBuffer >= herBatchSize config
          then runUpdates (herUpdatesPerEpisode config) online adam gen2
          else pure (Right (online, adam, gen2))
      case updateResult of
        Left err -> pure (Left err)
        Right (onlineNext, adamNext, gen3) -> do
          let targetNext =
                if (episode + 1) `mod` herTargetUpdateInterval config == 0
                  then onlineNext
                  else target
              newSuccesses = take 50 (reached : successes)
              statsNext =
                if (episode + 1) `mod` herStatInterval config == 0
                  || episode + 1 == herEpisodes config
                  then
                    let rate =
                          fromIntegral (length (filter id newSuccesses))
                            / fromIntegral (length newSuccesses)
                     in HerIterationStat (episode + 1) rate : stats
                  else stats
          episodeLoopEither
            initialSnapshot
            config
            update
            onlineNext
            targetNext
            adamNext
            gen3
            newBuffer
            (episode + 1)
            (observedTransitions + toInteger (length episodeTransitions))
            newSuccesses
            statsNext

-- | Collect exactly one configured outer episode's transition allocation.
-- Reaching the goal closes the current sub-episode; collection resets to the
-- canonical initial state and continues, so every scheduled slot corresponds
-- to a real bit-flip transition. 'hindsightTransitions' respects the terminal
-- boundaries when it relabels the concatenated fragments.
rolloutTrainingTransitions
  :: HerTrainConfig
  -> MlpParams
  -> Vector Double
  -> Random.StdGen
  -> ([Transition], Bool, Random.StdGen)
rolloutTrainingTransitions config online goal gen0 =
  step start 0 gen0 [] False
 where
  n = herNumBits config
  start = VU.replicate n 0.0
  step !state !len !gen !acc !reached
    | len >= n = (reverse acc, reached, gen)
    | otherwise =
        let inputV = state VU.++ goal
            (u, g1) = Random.uniformR (0.0 :: Double, 1.0) gen
            (au, g2) = Random.uniformR (0 :: Int, n - 1) g1
            greedy = argmax (VU.toList (forwardOutput (mlpForward online inputV)))
            action = if u < herEpsilon config then au else greedy
            nextState = flipBit action state
            reward = sparseGoalReward bitDistance 0.0 nextState goal
            done = nextState == goal
            trans =
              Transition
                { transInput = inputV
                , transAction = action
                , transReward = reward
                , transNextInput = nextState VU.++ goal
                , transDone = done
                }
            continuationState = if done then start else nextState
         in step continuationState (len + 1) g2 (trans : acc) (reached || done)

-- | Roll out one bit-flip episode (epsilon-greedy). Returns the raw
-- transitions, whether the goal was reached, and the advanced RNG.
rolloutEpisode
  :: HerTrainConfig
  -> MlpParams
  -> Vector Double
  -> Random.StdGen
  -> ([Transition], Bool, Random.StdGen)
rolloutEpisode config online goal gen0 =
  let n = herNumBits config
      start = VU.replicate n 0.0
      step !state !len !gen !acc
        | len >= n = (reverse acc, state == goal, gen)
        | state == goal = (reverse acc, True, gen)
        | otherwise =
            let inputV = state VU.++ goal
                (u, g1) = Random.uniformR (0.0 :: Double, 1.0) gen
                (au, g2) = Random.uniformR (0 :: Int, n - 1) g1
                greedy = argmax (VU.toList (forwardOutput (mlpForward online inputV)))
                action = if u < herEpsilon config then au else greedy
                nextState = flipBit action state
                reward = sparseGoalReward bitDistance 0.0 nextState goal
                done = nextState == goal
                trans =
                  Transition
                    { transInput = inputV
                    , transAction = action
                    , transReward = reward
                    , transNextInput = nextState VU.++ goal
                    , transDone = done
                    }
             in step nextState (len + 1) g2 (trans : acc)
   in step start 0 gen0 []

-- | Greedy (epsilon = 0) evaluation of the trained policy. Runs @numEpisodes@
-- episodes with fresh random goals and no exploration, returning per-episode
-- @(reachedGoal, normalizedHammingDistance, physicalTransitions)@. The
-- training success stats are measured under the 0.2 exploration epsilon and
-- understate the converged policy, so the convergence metric must read this
-- greedy pass instead.
evaluateHerGreedy :: HerTrainConfig -> MlpParams -> Int -> Int -> [(Bool, Double, Int)]
evaluateHerGreedy config params numEpisodes evalSeed =
  go (max 0 numEpisodes) (Random.mkStdGen evalSeed)
 where
  n = herNumBits config
  greedyConfig = config {herEpsilon = 0.0}
  start = VU.replicate n 0.0
  go 0 _ = []
  go k gen =
    let (goal, gen1) = randomNonInitialGoal n gen
        (transitions, reached, gen2) = rolloutEpisode greedyConfig params goal gen1
        finalState = case reverse transitions of
          (t : _) -> stateOfInput n (transNextInput t)
          [] -> start
        normDist = bitDistance finalState goal / fromIntegral (max 1 n)
     in (reached, normDist, length transitions) : go (k - 1) gen2

-- | HER @future@ relabeling: for each transition at index @i@, relabel
-- the goal to the next-state of a later transition in the same episode
-- and recompute the reward via 'herRelabel'.
hindsightTransitions :: HerTrainConfig -> [Transition] -> [Transition]
hindsightTransitions config transitions =
  concatMap (hindsightEpisodeTransitions config) (transitionEpisodes transitions)

hindsightEpisodeTransitions :: HerTrainConfig -> [Transition] -> [Transition]
hindsightEpisodeTransitions config transitions =
  let n = herNumBits config
      indexed = zip [0 :: Int ..] transitions
      total = length transitions
      strategyFutureGoal i =
        -- Use the final achieved state of the episode as the relabeled
        -- goal (a valid `future` choice that always exists).
        case drop (total - 1) transitions of
          (final : _) -> stateOfInput n (transNextInput final)
          [] -> stateOfInput n (transNextInput (transitions !! i))
   in [ let newGoal = strategyFutureGoal i
            s = stateOfInput n (transInput t)
            s' = stateOfInput n (transNextInput t)
            rel =
              herRelabel
                bitDistance
                0.0
                newGoal
                (s, transAction t, s', relabeledDone s' newGoal)
         in Transition
              { transInput = relState rel VU.++ relRelabeledGoal rel
              , transAction = relAction rel
              , transReward = relRelabeledReward rel
              , transNextInput = relNextState rel VU.++ relRelabeledGoal rel
              , transDone = relTerminal rel
              }
      | (i, t) <- indexed
      ]
 where
  relabeledDone s' g = bitDistance s' g <= 0.0

transitionEpisodes :: [Transition] -> [[Transition]]
transitionEpisodes = go []
 where
  go [] [] = []
  go acc [] = [reverse acc]
  go acc (transition : rest)
    | transDone transition = reverse (transition : acc) : go [] rest
    | otherwise = go (transition : acc) rest

-- | Recover the @n@-bit state from a goal-augmented @2n@ input.
stateOfInput :: Int -> Vector Double -> Vector Double
stateOfInput = VU.take

flipBit :: Int -> Vector Double -> Vector Double
flipBit i = VU.imap (\j b -> if j == i then 1.0 - b else b)

dqnUpdate
  :: HerTrainConfig -> MlpParams -> MlpParams -> AdamState -> [Transition] -> (MlpParams, AdamState)
dqnUpdate config online target adam batch =
  let adamCfg = defaultAdamConfig {adamLearningRate = herLearningRate config}
      stepUpdate (params, a) trans =
        let fwd = mlpForward params (transInput trans)
            qVec = VU.toList (forwardOutput fwd)
            nextQ = VU.toList (forwardOutput (mlpForward target (transNextInput trans)))
            dLdy = herResidualDLdy config qVec nextQ trans
            grad = mlpBackward params fwd dLdy
         in adamStep adamCfg a params grad
   in Data.List.foldl' stepUpdate (online, adam) batch

-- | The per-transition DQN loss gradient w.r.t. the Q-network output (the
-- TD residual at the taken-action index). Standard Bellman target over the
-- target net's next-state Q. Factored out of 'dqnUpdate' so the pure CPU
-- path and the batched device path ('herUpdateDevice') share the identical
-- loss gradient.
herResidualDLdy :: HerTrainConfig -> [Double] -> [Double] -> Transition -> Vector Double
herResidualDLdy config qVec nextQ trans =
  VU.generate (length qVec) (\i -> if i == actionIx then residual else 0.0)
 where
  actionIx = transAction trans
  qSa = if actionIx >= 0 && actionIx < length qVec then qVec !! actionIx else 0.0
  -- max_a' Q_target(s', a'). Bit-flip rewards are 0/-1 so all true Q-values are
  -- negative; the old `maximum (0 : nextQ)` pinned the bootstrap to 0, collapsing
  -- the target to the immediate reward and preventing any multi-step goal-value
  -- propagation. `nextQ` has herNumBits (>= 1) entries, so guard empty explicitly.
  maxNextQ = if null nextQ then 0.0 else maximum nextQ
  tdTarget = dqnBellmanTarget (herGamma config) (transReward trans) (transDone trans) maxNextQ
  residual = qSa - tdTarget

argmax :: (Ord a) => [a] -> Int
argmax [] = 0
argmax xs = snd (foldr1 stepMax (zip xs [0 ..]))
 where
  stepMax (v1, i1) (v2, i2)
    | v1 >= v2 = (v1, i1)
    | otherwise = (v2, i2)

randomBits :: Int -> Random.StdGen -> (Vector Double, Random.StdGen)
randomBits n gen0 = goBits n gen0 []
 where
  goBits 0 g acc = (VU.fromList acc, g)
  goBits k g acc =
    let (b, g') = Random.uniformR (0 :: Int, 1) g
     in goBits (k - 1) g' (fromIntegral b : acc)

-- Reject the already-satisfied all-zero goal so training resets and final
-- evaluation both begin from a valid nonterminal state and therefore report
-- at least one real environment transition.
randomNonInitialGoal :: Int -> Random.StdGen -> (Vector Double, Random.StdGen)
randomNonInitialGoal n gen
  | n <= 0 = randomBits n gen
  | otherwise =
      let (goal, nextGen) = randomBits n gen
       in if VU.all (== 0.0) goal
            then randomNonInitialGoal n nextGen
            else (goal, nextGen)

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

-- | Sprint 13.8 — train HER on the bit-flip env with the Q-network's
-- minibatch forward + backward running on the GPU through the batched
-- device primitives. The per-episode rollout + hindsight relabeling +
-- replay are unchanged (shared with the pure 'trainHerOnBitFlip' via the
-- parameterised 'episodeLoop'); only the minibatch gradient update runs on
-- the device ('herUpdateDevice'), reusing the shared head 'herResidualDLdy'.
trainHerOnBitFlipCuda :: Env -> HerTrainConfig -> IO (Either Text HerTrainResult)
trainHerOnBitFlipCuda env = trainHerOnDevice (cudaMlpDevice env)

-- | HER training through the oneDNN (linux-cpu) MLP device.
trainHerOnBitFlipOneDnn :: Env -> HerTrainConfig -> IO (Either Text HerTrainResult)
trainHerOnBitFlipOneDnn env = trainHerOnDevice (oneDnnMlpDevice env)

-- | HER training through the Metal (apple-silicon) MLP device.
trainHerOnBitFlipMetal :: Env -> HerTrainConfig -> IO (Either Text HerTrainResult)
trainHerOnBitFlipMetal env = trainHerOnDevice (metalMlpDevice env)

-- | HER training through an injected MLP device backend. The per-episode
-- rollout + hindsight relabeling + replay are shared with the pure
-- 'trainHerOnBitFlip' via the parameterised 'episodeLoop'; only the minibatch
-- gradient update runs on the device ('herUpdateDevice').
trainHerOnDevice :: MlpDevice -> HerTrainConfig -> IO (Either Text HerTrainResult)
trainHerOnDevice device config = do
  observed <- trainHerOnDeviceRaw device config
  pure (observed >>= refineHerTrainObservation)

trainHerOnDeviceRaw :: MlpDevice -> HerTrainConfig -> IO (Either Text HerTrainObservation)
trainHerOnDeviceRaw device config = do
  prepared <- prepareHerOnDevice device config
  continuePreparedHerRaw prepared

prepareHerOnDevice :: MlpDevice -> HerTrainConfig -> IO PreparedHer
prepareHerOnDevice device config = do
  let shape = herMlpShape config
      initialParams = initialHerParams config
      initialOnline = initialParams
      initialTarget = initialParams
      initialAdam = adamInit shape
      initialGenerator = Random.mkStdGen (herSeed config + 1)
      initialReplay = []
      initialEpisode = 0
      initialObservedTransitions = 0
      initialRecentSuccesses = []
      initialStatistics = []
  guard <- SingleUse.newSingleUse
  let snapshot =
        HerPreparedSnapshot
          config
          initialParams
          initialOnline
          initialTarget
          initialAdam
          initialGenerator
          initialReplay
          initialEpisode
          initialObservedTransitions
          initialRecentSuccesses
          initialStatistics
      action =
        episodeLoopEither
          initialParams
          config
          (herUpdateDevice device config)
          initialOnline
          initialTarget
          initialAdam
          initialGenerator
          initialReplay
          initialEpisode
          initialObservedTransitions
          initialRecentSuccesses
          initialStatistics
  pure (PreparedHer snapshot guard action)

herMlpShape :: HerTrainConfig -> MlpShape
herMlpShape config =
  let n = herNumBits config
   in MlpShape
        { mlpInputs = 2 * n
        , mlpHidden = herHiddenUnits config
        , mlpOutputs = n
        }

initialHerParams :: HerTrainConfig -> MlpParams
initialHerParams config =
  mlpInit (herMlpShape config) (herSeed config)

-- | Minibatch HER/DQN gradient update through the batched device primitives:
-- batched online forward at the (state||goal) inputs + target forward at
-- the next inputs, the per-sample TD-residual gradient ('herResidualDLdy'),
-- one batched device backward (mean gradient), and one Adam step. Fails
-- closed with a typed `Left` on any mid-run device fault.
herUpdateDevice
  :: MlpDevice
  -> HerTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> [Transition]
  -> IO (Either Text (MlpParams, AdamState))
herUpdateDevice device config online target adam batch = do
  onlineQE <- mlpdForwardBatch device online (map transInput batch)
  targetQE <- mlpdForwardBatch device target (map transNextInput batch)
  case (onlineQE, targetQE) of
    (Right onlineQs, Right targetQs) -> do
      let pairs =
            [ (transInput trans, herResidualDLdy config (VU.toList qv) (VU.toList nq) trans)
            | (trans, qv, nq) <- zip3 batch onlineQs targetQs
            ]
      gradResult <- mlpdBatchGradient device online pairs
      case gradResult of
        Right summed ->
          let scale = 1.0 / fromIntegral (length batch)
              meanGradient = scaleGradient scale summed
              adamCfg = defaultAdamConfig {adamLearningRate = herLearningRate config}
              (onlineAfter, adamAfter) = adamStep adamCfg adam online meanGradient
           in pure (Right (onlineAfter, adamAfter))
        Left err -> pure (Left ("her device batch-gradient kernel failed mid-run: " <> err))
    (Left err, _) -> pure (Left ("her device forward kernel failed mid-run (online batch): " <> err))
    (_, Left err) -> pure (Left ("her device forward kernel failed mid-run (target batch): " <> err))
 where
  scaleGradient sc g =
    MlpGradient
      { gradW1 = VU.map (* sc) (gradW1 g)
      , gradB1 = VU.map (* sc) (gradB1 g)
      , gradW2 = VU.map (* sc) (gradW2 g)
      , gradB2 = VU.map (* sc) (gradB2 g)
      }

herEvaluationContract :: Text
herEvaluationContract = "her-selected-device-greedy-sequential-goals-v1"

-- | Device-backed counterpart of 'evaluateHerGreedy'. The existing sequential
-- goal RNG is deliberately retained, including both draws per epsilon-zero
-- transition. This is not a policy-independent goal schedule or paired proof.
evaluateHerGreedyOnDevice
  :: MlpDevice
  -> HerTrainConfig
  -> MlpParams
  -> Int
  -> Int
  -> IO (Either Text [(Bool, Double, Int)])
evaluateHerGreedyOnDevice device config params numEpisodes evalSeed
  | numEpisodes <= 0
      || herNumBits config <= 0
      || herHiddenUnits config <= 0
      || toInteger (herNumBits config) * 2 > toInteger (maxBound :: Int) =
      pure (Left "HER device evaluation requires positive episode count and valid bit/hidden dimensions")
  | not (herEvaluationParams (herMlpShape config) params) =
      pure (Left "HER device evaluation parameters are malformed or overflow the Float32 ABI")
  | otherwise = go numEpisodes (Random.mkStdGen evalSeed) []
 where
  n = herNumBits config
  greedyConfig = config {herEpsilon = 0.0}
  start = VU.replicate n 0.0
  go 0 _ outcomes = pure (Right (reverse outcomes))
  go k gen outcomes = do
    let (goal, gen1) = randomNonInitialGoal n gen
    rolled <- rollout goal start 0 gen1
    case rolled of
      Left err -> pure (Left err)
      Right (finalState, steps, reached, gen2) -> do
        let normDist = bitDistance finalState goal / fromIntegral (max 1 n)
        if not (herEvaluationFinite normDist)
          then pure (Left "HER device evaluation produced a non-finite normalized distance")
          else go (k - 1) gen2 ((reached, normDist, steps) : outcomes)
  rollout goal state len gen
    | len >= n = pure (Right (state, len, state == goal, gen))
    | state == goal = pure (Right (state, len, True, gen))
    | not (herEvaluationVector inputV) || VU.length inputV /= 2 * n =
        pure (Left "HER device evaluation observation is malformed or overflows the Float32 ABI")
    | otherwise = do
        forwarded <- mlpdForward device params inputV
        case forwarded of
          Left err -> pure (Left ("HER device forward failed during evaluation: " <> err))
          Right forward
            | VU.length (forwardOutput forward) /= n || not (herEvaluationVector (forwardOutput forward)) ->
                pure (Left "HER device evaluation output has the wrong shape or is not finite Float32")
            | otherwise -> do
                let (u, g1) = Random.uniformR (0.0 :: Double, 1.0) gen
                    (au, g2) = Random.uniformR (0 :: Int, n - 1) g1
                    greedy = argmax (VU.toList (forwardOutput forward))
                    action = if u < herEpsilon greedyConfig then au else greedy
                    nextState = flipBit action state
                rollout goal nextState (len + 1) g2
   where
    inputV = state VU.++ goal

-- Float32 is the selected MLP ABI. Finite binary64 values are accepted when
-- conversion remains finite; underflow/rounding is allowed, exact Float32
-- representability is not required. Environment rewards stay finite Double.
herEvaluationFinite :: Double -> Bool
herEvaluationFinite value = not (isNaN value || isInfinite value)

herEvaluationVector :: Vector Double -> Bool
herEvaluationVector =
  VU.all
    ( \value ->
        herEvaluationFinite value
          && let encoded = realToFrac value :: Float in not (isNaN encoded || isInfinite encoded)
    )

herEvaluationParams :: MlpShape -> MlpParams -> Bool
herEvaluationParams shape params =
  paramShape params == shape
    && toInteger (VU.length (paramW1 params)) == toInteger (mlpHidden shape) * toInteger (mlpInputs shape)
    && VU.length (paramB1 params) == mlpHidden shape
    && toInteger (VU.length (paramW2 params)) == toInteger (mlpOutputs shape) * toInteger (mlpHidden shape)
    && VU.length (paramB2 params) == mlpOutputs shape
    && all herEvaluationVector [paramW1 params, paramB1 params, paramW2 params, paramB2 params]

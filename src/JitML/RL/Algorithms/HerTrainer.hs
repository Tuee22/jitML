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
  , trainHerOnBitFlip
  , trainHerOnBitFlipCuda
  , trainHerOnBitFlipOneDnn
  , trainHerOnBitFlipMetal
  , trainHerOnDevice
  , evaluateHerGreedy
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
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState (..)
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
  , herResultFinalParams :: !MlpParams
  , herResultMeasuredCounters :: !Common.MeasuredTrainerCounters
  -- ^ Exact physical bit-flip transitions and Adam applications executed
  -- against the final online goal-conditioned Q tensor. Replay readiness can
  -- delay updates, so neither count is inferred from the episode budget.
  , herResultConfig :: !HerTrainConfig
  }
  deriving stock (Eq, Show)

-- | Hamming-distance goal metric: count of differing bits.
bitDistance :: Vector Double -> Vector Double -> Double
bitDistance s g =
  fromIntegral (VU.length (VU.filter id (VU.zipWith (\a b -> abs (a - b) > 0.5) s g)))

trainHerOnBitFlip :: HerTrainConfig -> IO HerTrainResult
trainHerOnBitFlip config = do
  let shape = herMlpShape config
      initialParams = initialHerParams config
  episodeLoop
    config
    (\online target adam batch -> pure (dqnUpdate config online target adam batch))
    initialParams
    initialParams
    (adamInit shape)
    (Random.mkStdGen (herSeed config + 1))
    []
    0
    0
    []
    []

episodeLoop
  :: HerTrainConfig
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
  -> IO HerTrainResult
episodeLoop config update online target adam gen buffer episode observedTransitions successes stats = do
  result <-
    episodeLoopEither
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
  :: HerTrainConfig
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
  -> IO (Either Text HerTrainResult)
episodeLoopEither config update online target adam gen buffer episode observedTransitions successes stats
  | herUpdatesPerEpisode config <= 0 =
      pure (Left "HER updates per episode must be positive")
  | episode >= herEpisodes config =
      pure $ do
        measuredCounters <-
          Common.mkMeasuredTrainerCounters
            observedTransitions
            (toInteger (adamStep_ adam))
        Right
          HerTrainResult
            { herResultStats = reverse stats
            , herResultFinalParams = online
            , herResultMeasuredCounters = measuredCounters
            , herResultConfig = config
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
  let shape = herMlpShape config
      initialParams = initialHerParams config
  episodeLoopEither
    config
    (herUpdateDevice device config)
    initialParams
    initialParams
    (adamInit shape)
    (Random.mkStdGen (herSeed config + 1))
    []
    0
    0
    []
    []

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

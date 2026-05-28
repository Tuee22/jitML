{-# LANGUAGE BangPatterns #-}

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
  , HerTrainResult (..)
  , HerIterationStat (..)
  , trainHerOnBitFlip
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
  }
  deriving stock (Eq, Show)

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
  , herResultConfig :: !HerTrainConfig
  }
  deriving stock (Eq, Show)

-- | Hamming-distance goal metric: count of differing bits.
bitDistance :: Vector Double -> Vector Double -> Double
bitDistance s g =
  fromIntegral (VU.length (VU.filter id (VU.zipWith (\a b -> abs (a - b) > 0.5) s g)))

trainHerOnBitFlip :: HerTrainConfig -> IO HerTrainResult
trainHerOnBitFlip config = do
  let n = herNumBits config
      shape =
        MlpShape
          { mlpInputs = 2 * n
          , mlpHidden = herHiddenUnits config
          , mlpOutputs = n
          }
      initialParams = mlpInit shape (herSeed config)
  pure $
    episodeLoop
      config
      initialParams
      initialParams
      (adamInit shape)
      (Random.mkStdGen (herSeed config + 1))
      []
      0
      []
      []

episodeLoop
  :: HerTrainConfig
  -> MlpParams
  -> MlpParams
  -> AdamState
  -> Random.StdGen
  -> [Transition]
  -> Int
  -> [Bool] -- recent episode successes
  -> [HerIterationStat]
  -> HerTrainResult
episodeLoop config online target adam gen buffer episode successes stats
  | episode >= herEpisodes config =
      HerTrainResult
        { herResultStats = reverse stats
        , herResultFinalParams = online
        , herResultConfig = config
        }
  | otherwise =
      let n = herNumBits config
          (goal, gen1) = randomBits n gen
          (episodeTransitions, reached, gen2) =
            rolloutEpisode config online goal gen1
          relabeled =
            if herUseHindsight config
              then hindsightTransitions config episodeTransitions
              else []
          newBuffer =
            take
              (herReplayCapacity config)
              (relabeled <> episodeTransitions <> buffer)
          (onlineNext, adamNext, gen3) =
            if length newBuffer >= herBatchSize config
              then
                let (batch, genB) = sampleBatch (herBatchSize config) newBuffer gen2
                    (o, a) = dqnUpdate config online target adam batch
                 in (o, a, genB)
              else (online, adam, gen2)
          targetNext =
            if (episode + 1) `mod` herTargetUpdateInterval config == 0
              then onlineNext
              else target
          newSuccesses = take 50 (reached : successes)
          statsNext =
            if (episode + 1) `mod` herStatInterval config == 0
              then
                let rate =
                      fromIntegral (length (filter id newSuccesses))
                        / fromIntegral (length newSuccesses)
                 in HerIterationStat (episode + 1) rate : stats
              else stats
       in episodeLoop
            config
            onlineNext
            targetNext
            adamNext
            gen3
            newBuffer
            (episode + 1)
            newSuccesses
            statsNext

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

-- | HER @future@ relabeling: for each transition at index @i@, relabel
-- the goal to the next-state of a later transition in the same episode
-- and recompute the reward via 'herRelabel'.
hindsightTransitions :: HerTrainConfig -> [Transition] -> [Transition]
hindsightTransitions config transitions =
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

-- | Recover the @n@-bit state from a goal-augmented @2n@ input.
stateOfInput :: Int -> Vector Double -> Vector Double
stateOfInput = VU.take

flipBit :: Int -> Vector Double -> Vector Double
flipBit i = VU.imap (\j b -> if j == i then 1.0 - b else b)

dqnUpdate
  :: HerTrainConfig -> MlpParams -> MlpParams -> AdamState -> [Transition] -> (MlpParams, AdamState)
dqnUpdate config online target adam batch =
  let adamCfg = defaultAdamConfig {adamLearningRate = herLearningRate config}
      gamma = herGamma config
      stepUpdate (params, a) trans =
        let fwd = mlpForward params (transInput trans)
            qVec = VU.toList (forwardOutput fwd)
            actionIx = transAction trans
            qSa = if actionIx < length qVec then qVec !! actionIx else 0.0
            nextQ = VU.toList (forwardOutput (mlpForward target (transNextInput trans)))
            maxNextQ = maximum (0 : nextQ)
            tdTarget = dqnBellmanTarget gamma (transReward trans) (transDone trans) maxNextQ
            residual = qSa - tdTarget
            dLdy = VU.generate (length qVec) (\i -> if i == actionIx then residual else 0.0)
            grad = mlpBackward params fwd dLdy
         in adamStep adamCfg a params grad
   in Data.List.foldl' stepUpdate (online, adam) batch

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

sampleBatch :: Int -> [Transition] -> Random.StdGen -> ([Transition], Random.StdGen)
sampleBatch n buffer gen =
  let bufLen = length buffer
      pickN k g acc
        | k <= 0 = (acc, g)
        | otherwise =
            let (idx, g') = Random.uniformR (0 :: Int, bufLen - 1) g
             in pickN (k - 1) g' (buffer !! idx : acc)
   in pickN n gen []

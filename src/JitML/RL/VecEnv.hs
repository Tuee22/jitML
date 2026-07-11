-- | Product-reachable vectorized environment seam for RL trainers.
--
-- A 'VecEnv' owns N live simulator states for one canonical environment and
-- advances them as one batched step. The neural trainer can then evaluate the
-- N observations in one device batch, choose N actions, and apply all actions
-- through this module before the next network call.
module JitML.RL.VecEnv
  ( VecEnv (..)
  , VecEnvSlot (..)
  , VecEnvTransition (..)
  , mkVecEnv
  , vecEnvObservations
  , vecEnvSize
  , vecEnvStep
  )
where

import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.RL.Simulator
  ( RenderFrame (..)
  , SimStep (..)
  , SimulatedEnvironment (..)
  )

data VecEnv state = VecEnv
  { vecEnvEnvironment :: !(SimulatedEnvironment state)
  , vecEnvSlots :: ![VecEnvSlot state]
  }

data VecEnvSlot state = VecEnvSlot
  { vecSlotState :: !state
  , vecSlotEpisodeReturn :: !Double
  , vecSlotEpisodeLength :: !Int
  }

data VecEnvTransition state = VecEnvTransition
  { vecTransitionIndex :: !Int
  , vecTransitionState :: !state
  , vecTransitionNextState :: !state
  , vecTransitionObservation :: !(Vector Double)
  , vecTransitionNextObservation :: !(Vector Double)
  , vecTransitionReward :: !Double
  , vecTransitionDone :: !Bool
  , vecTransitionEpisodeReturnBefore :: !Double
  , vecTransitionEpisodeLengthBefore :: !Int
  , vecTransitionCompletedReturn :: !(Maybe Double)
  , vecTransitionCompletedLength :: !(Maybe Int)
  }

mkVecEnv :: SimulatedEnvironment state -> Int -> Random.StdGen -> (VecEnv state, Random.StdGen)
mkVecEnv environment requestedSize gen0 =
  let (genN, slots) =
        mapAccumL
          ( \gen _ ->
              let (state, gen') = resetState environment gen
               in (gen', VecEnvSlot state 0.0 0)
          )
          gen0
          [1 .. max 1 requestedSize]
   in (VecEnv environment slots, genN)

vecEnvSize :: VecEnv state -> Int
vecEnvSize = length . vecEnvSlots

vecEnvObservations :: VecEnv state -> [Vector Double]
vecEnvObservations vecEnv =
  fmap (observationFor (vecEnvEnvironment vecEnv) . vecSlotState) (vecEnvSlots vecEnv)

vecEnvStep
  :: Int
  -> VecEnv state
  -> [Int]
  -> Random.StdGen
  -> (VecEnv state, [VecEnvTransition state], Random.StdGen)
vecEnvStep maxEpisodeSteps vecEnv actions gen0 =
  let environment = vecEnvEnvironment vecEnv
      paddedActions = take (length (vecEnvSlots vecEnv)) (actions <> repeat 0)
      (slots, transitions, genN) =
        stepSlots environment maxEpisodeSteps gen0 (zip3 [0 ..] (vecEnvSlots vecEnv) paddedActions)
   in (VecEnv environment slots, transitions, genN)

stepSlots
  :: SimulatedEnvironment state
  -> Int
  -> Random.StdGen
  -> [(Int, VecEnvSlot state, Int)]
  -> ([VecEnvSlot state], [VecEnvTransition state], Random.StdGen)
stepSlots _ _ gen [] = ([], [], gen)
stepSlots environment maxEpisodeSteps gen ((index, slot, action) : rest) =
  let action' = clamp 0 (max 0 (envActionCount environment - 1)) action
      state0 = vecSlotState slot
      obs0 = observationFor environment state0
      stepped = envStep environment state0 action'
      nextState = simStepState stepped
      nextObs = observationFor environment nextState
      nextReturn = vecSlotEpisodeReturn slot + simStepReward stepped
      nextLength = vecSlotEpisodeLength slot + 1
      done = simStepDone stepped || nextLength >= max 1 maxEpisodeSteps
      (slot', completedReturn, completedLength, gen') =
        if done
          then
            let (reset, genReset) = resetState environment gen
             in (VecEnvSlot reset 0.0 0, Just nextReturn, Just nextLength, genReset)
          else (VecEnvSlot nextState nextReturn nextLength, Nothing, Nothing, gen)
      transition =
        VecEnvTransition
          { vecTransitionIndex = index
          , vecTransitionState = state0
          , vecTransitionNextState = nextState
          , vecTransitionObservation = obs0
          , vecTransitionNextObservation = nextObs
          , vecTransitionReward = simStepReward stepped
          , vecTransitionDone = done
          , vecTransitionEpisodeReturnBefore = vecSlotEpisodeReturn slot
          , vecTransitionEpisodeLengthBefore = vecSlotEpisodeLength slot
          , vecTransitionCompletedReturn = completedReturn
          , vecTransitionCompletedLength = completedLength
          }
      (slots, transitions, genN) = stepSlots environment maxEpisodeSteps gen' rest
   in (slot' : slots, transition : transitions, genN)

resetState :: SimulatedEnvironment state -> Random.StdGen -> (state, Random.StdGen)
resetState environment gen =
  case envTrainingStart environment of
    Nothing -> (envInitial environment, gen)
    Just f ->
      let (u1, gen1) = Random.uniformR (0.0 :: Double, 1.0) gen
          (u2, gen2) = Random.uniformR (0.0 :: Double, 1.0) gen1
       in (f u1 u2, gen2)

observationFor :: SimulatedEnvironment state -> state -> Vector Double
observationFor environment =
  VU.fromList . renderObservation . envRenderFrame environment

clamp :: (Ord a) => a -> a -> a -> a
clamp lo hi = max lo . min hi

mapAccumL :: (acc -> x -> (acc, y)) -> acc -> [x] -> (acc, [y])
mapAccumL _ acc [] = (acc, [])
mapAccumL f acc (x : xs) =
  let (acc', y) = f acc x
      (acc'', ys) = mapAccumL f acc' xs
   in (acc'', y : ys)

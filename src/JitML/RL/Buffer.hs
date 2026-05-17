module JitML.RL.Buffer
  ( BufferKind (..)
  , ReplayBuffer (..)
  , Transition (..)
  , bufferInsert
  , bufferSample
  , bufferSize
  , emptyBuffer
  , transitionsFromTrajectory
  )
where

import JitML.RL.Environments (EnvStep (..))

data Transition = Transition
  { transitionStep :: Int
  , transitionAction :: Int
  , transitionReward :: Double
  , transitionObservation :: Int
  , transitionDone :: Bool
  }
  deriving stock (Eq, Show)

data BufferKind
  = OnPolicyRollout
  | OffPolicyReplay
  deriving stock (Eq, Show)

data ReplayBuffer = ReplayBuffer
  { bufferKind :: BufferKind
  , bufferCapacity :: Int
  , bufferTransitions :: [Transition]
  }
  deriving stock (Eq, Show)

emptyBuffer :: BufferKind -> Int -> ReplayBuffer
emptyBuffer kind capacity =
  ReplayBuffer {bufferKind = kind, bufferCapacity = capacity, bufferTransitions = []}

bufferInsert :: Transition -> ReplayBuffer -> ReplayBuffer
bufferInsert transition buffer =
  buffer
    { bufferTransitions =
        take (bufferCapacity buffer) (transition : bufferTransitions buffer)
    }

bufferSize :: ReplayBuffer -> Int
bufferSize = length . bufferTransitions

-- | Deterministic sampling: walk the buffer with a fixed stride derived from
-- the seed; preserves order so per-seed transcripts are reproducible.
bufferSample :: Int -> Int -> ReplayBuffer -> [Transition]
bufferSample seed count buffer =
  take count $ drop offset (bufferTransitions buffer ++ bufferTransitions buffer)
 where
  stride =
    if bufferSize buffer == 0 then 1 else 1 + abs seed `mod` max 1 (bufferSize buffer)
  offset = abs seed `mod` max 1 (bufferSize buffer) `div` max 1 stride

transitionsFromTrajectory :: [(Int, EnvStep)] -> [Transition]
transitionsFromTrajectory =
  fmap toTransition
 where
  toTransition (action, step) =
    Transition
      { transitionStep = stepObservationHash step
      , transitionAction = action
      , transitionReward = stepReward step
      , transitionObservation = stepObservationHash step
      , transitionDone = stepDone step
      }

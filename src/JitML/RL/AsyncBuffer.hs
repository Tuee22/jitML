{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AsyncBuffer
  ( AsyncBuffer (..)
  , AsyncSink (..)
  , AsyncWriteResult (..)
  , drainAsync
  , insertAsync
  , newAsyncBuffer
  , pendingAsyncCount
  )
where

import Control.Concurrent.Async (Async, async, wait)
import Control.Concurrent.STM (STM, TVar, atomically, modifyTVar', newTVarIO, readTVar, readTVarIO)
import Control.Monad (forM)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Buffer (BufferKind, ReplayBuffer (..), Transition, bufferInsert, emptyBuffer)

-- | A capability-shaped sink for async transcript writes. The production
-- implementation will be backed by `HasMinIO.putBlobBytesIfAbsent`; the
-- test surface uses a deterministic IORef-backed sink. The contract is
-- that `asyncSink` is called for every batch of transitions the env loop
-- has accumulated, and the call may block.
newtype AsyncSink = AsyncSink
  { unAsyncSink :: [Transition] -> IO AsyncWriteResult
  }

data AsyncWriteResult
  = AsyncWriteOk Text
  | AsyncWriteFailed Text
  deriving stock (Eq, Show)

-- | Bounded async replay buffer. The env loop calls `insertAsync` which
-- (1) updates the typed `ReplayBuffer` in-place and (2) spawns an async
-- write of the latest batch to the sink. The async handle is registered
-- with the buffer so `drainAsync` can wait for all pending writes at the
-- end of an episode without blocking the hot path.
data AsyncBuffer = AsyncBuffer
  { asyncReplay :: TVar ReplayBuffer
  , asyncPending :: TVar [Async AsyncWriteResult]
  , asyncSink :: AsyncSink
  }

newAsyncBuffer :: BufferKind -> Int -> AsyncSink -> IO AsyncBuffer
newAsyncBuffer kind capacity sink = do
  replay <- newTVarIO (emptyBuffer kind capacity)
  pending <- newTVarIO []
  pure
    AsyncBuffer
      { asyncReplay = replay
      , asyncPending = pending
      , asyncSink = sink
      }

-- | Insert a transition into the buffer and spawn an async write of the
-- updated buffer's tail through the sink. The function returns
-- immediately; the env loop is not blocked on the I/O.
insertAsync :: AsyncBuffer -> Transition -> IO ()
insertAsync buffer transition = do
  newBatch <- atomically $ do
    modifyTVar' (asyncReplay buffer) (bufferInsert transition)
    fmap bufferTransitions (readTVar (asyncReplay buffer))
  handle <- async (unAsyncSink (asyncSink buffer) newBatch)
  atomically $ modifyTVar' (asyncPending buffer) (handle :)

-- | Drain all pending async writes. Called at episode-end / drain
-- boundaries. Returns each write's result in spawn-order.
drainAsync :: AsyncBuffer -> IO [AsyncWriteResult]
drainAsync buffer = do
  handles <- atomically $ do
    current <- readTVar (asyncPending buffer)
    modifyTVar' (asyncPending buffer) (const [])
    pure (reverse current)
  forM handles wait

pendingAsyncCount :: AsyncBuffer -> IO Int
pendingAsyncCount buffer =
  fmap length (readTVarIO (asyncPending buffer))

-- Re-export-ish helper used by tests.
_unused :: Text
_unused = Text.pack ""

-- silence "STM unused" since modifyTVar' is enough
_silenceStmUsage :: STM ()
_silenceStmUsage = pure ()

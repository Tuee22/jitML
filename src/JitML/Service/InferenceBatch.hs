-- | Receipt-independent admission and latency fencing for live inference
-- batches. Transport interpreters retain broker receipts; this module decides
-- which compatible requests share one handler window and exposes the captured
-- absolute deadline used by the real handler and publication seams.
module JitML.Service.InferenceBatch
  ( BatchPolicy
  , BatchPolicyError (..)
  , batchMaximumLatencyMicros
  , batchMaximumSize
  , mkBatchPolicy
  , BatchFlushReason (..)
  , OpenBatch
  , BatchOffer (..)
  , openBatch
  , offerBatch
  , batchAdmissionNanoseconds
  , batchCollectionDeadlineNanoseconds
  , batchDeadlineNanoseconds
  , batchItems
  , batchKey
  , batchPolicy
  , batchFlushReason
  , BatchWindow
  , batchWindow
  , batchWindowAdmissionNanoseconds
  , batchWindowDeadlineNanoseconds
  , batchWindowPolicy
  , batchDeadlineExpiredAt
  , batchWindowExpiredAt
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Word (Word64)
import Numeric.Natural (Natural)

-- | Limits read atomically when the first request enters a batch.  Keeping the
-- constructor private makes zero-sized and zero-latency windows
-- unrepresentable at the transport boundary.
data BatchPolicy = BatchPolicy
  { batchMaximumSize :: Natural
  , batchMaximumLatencyMicros :: Natural
  }
  deriving stock (Eq, Show)

data BatchPolicyError
  = BatchSizeMustBePositive
  | BatchLatencyMustBePositive
  deriving stock (Eq, Show)

mkBatchPolicy :: Natural -> Natural -> Either BatchPolicyError BatchPolicy
mkBatchPolicy maximumSize maximumLatencyMicros
  | maximumSize == 0 = Left BatchSizeMustBePositive
  | maximumLatencyMicros == 0 = Left BatchLatencyMustBePositive
  | otherwise =
      Right
        BatchPolicy
          { batchMaximumSize = maximumSize
          , batchMaximumLatencyMicros = maximumLatencyMicros
          }

data BatchFlushReason
  = BatchSizeReached
  | BatchDeadlineReached
  | BatchCompatibilityChanged
  deriving stock (Eq, Show)

-- | One compatible request group.  The policy and absolute deadline are
-- captured exactly once at admission; a later live-config reload cannot alter
-- a batch already in flight.
data OpenBatch key item = OpenBatch
  { batchPolicy :: BatchPolicy
  , batchKey :: key
  , batchAdmissionNanoseconds :: Word64
  , batchDeadlineNanoseconds :: Integer
  , batchItems :: NonEmpty item
  }
  deriving stock (Eq, Show)

-- | Offering an item either keeps the batch open or flushes it.  An item that
-- arrived after the old window closed is returned as carry-over so the caller
-- can admit it under a fresh policy snapshot.
data BatchOffer key item
  = BatchKept (OpenBatch key item)
  | BatchReady BatchFlushReason (OpenBatch key item) (Maybe (key, item))
  deriving stock (Eq, Show)

-- | Opaque, receipt-free projection safe to hand to an inference handler.  It
-- carries the exact policy snapshot and absolute deadline of the transport
-- batch without exposing its compatibility key or broker identities.
data BatchWindow = BatchWindow
  { batchWindowPolicy :: BatchPolicy
  , batchWindowAdmissionNanoseconds :: Word64
  , batchWindowDeadlineNanoseconds :: Integer
  }
  deriving stock (Eq, Show)

openBatch :: Word64 -> BatchPolicy -> key -> item -> OpenBatch key item
openBatch admittedAt policy compatibilityKey item =
  OpenBatch
    { batchPolicy = policy
    , batchKey = compatibilityKey
    , batchAdmissionNanoseconds = admittedAt
    , batchDeadlineNanoseconds =
        toInteger admittedAt
          + toInteger (batchMaximumLatencyMicros policy) * nanosecondsPerMicrosecond
    , batchItems = item :| []
    }

offerBatch
  :: (Eq key)
  => Word64
  -> key
  -> item
  -> OpenBatch key item
  -> BatchOffer key item
offerBatch now compatibilityKey item batch =
  case batchFlushReason now batch of
    Just reason -> BatchReady reason batch (Just (compatibilityKey, item))
    Nothing
      | compatibilityKey /= batchKey batch ->
          BatchReady BatchCompatibilityChanged batch (Just (compatibilityKey, item))
      | otherwise ->
          let expanded =
                batch
                  { batchItems = batchItems batch <> (item :| [])
                  }
           in case batchFlushReason now expanded of
                Just reason -> BatchReady reason expanded Nothing
                Nothing -> BatchKept expanded

batchFlushReason :: Word64 -> OpenBatch key item -> Maybe BatchFlushReason
batchFlushReason now batch
  | fromIntegral (NonEmpty.length (batchItems batch))
      >= batchMaximumSize (batchPolicy batch) =
      Just BatchSizeReached
  | toInteger now >= batchDeadlineNanoseconds batch = Just BatchDeadlineReached
  | otherwise = Nothing

-- | Stop waiting for another compatible delivery while execution and
-- publication entry still retain almost all of the captured handler budget.
-- A sparse batch must not consume its complete deadline merely waiting to
-- reach 'batchMaximumSize': doing so would make the handler unreachable and
-- turn every singleton request into an endless negative-acknowledgement loop.
-- The collection window is therefore the smaller of one millisecond and one
-- tenth of the captured latency budget. Size and compatibility changes can
-- still close the batch earlier; the captured handler/publication-entry
-- deadline is unchanged.
batchCollectionDeadlineNanoseconds :: OpenBatch key item -> Integer
batchCollectionDeadlineNanoseconds batch =
  min
    (batchDeadlineNanoseconds batch - 1)
    (toInteger (batchAdmissionNanoseconds batch) + collectionWindowNanoseconds)
 where
  latencyNanoseconds =
    toInteger (batchMaximumLatencyMicros (batchPolicy batch))
      * nanosecondsPerMicrosecond
  collectionWindowNanoseconds =
    max 1 (min maximumCollectionWindowNanoseconds (latencyNanoseconds `div` 10))

maximumCollectionWindowNanoseconds :: Integer
maximumCollectionWindowNanoseconds = 1_000_000

batchWindow :: OpenBatch key item -> BatchWindow
batchWindow batch =
  BatchWindow
    { batchWindowPolicy = batchPolicy batch
    , batchWindowAdmissionNanoseconds = batchAdmissionNanoseconds batch
    , batchWindowDeadlineNanoseconds = batchDeadlineNanoseconds batch
    }

-- | Compare one monotonic sample with a captured absolute batch deadline.
-- Production uses this same predicate both before entering another handler
-- dispatch and immediately before an Engine publication side effect.
batchDeadlineExpiredAt :: Word64 -> Integer -> Bool
batchDeadlineExpiredAt now deadline = toInteger now >= deadline

batchWindowExpiredAt :: Word64 -> BatchWindow -> Bool
batchWindowExpiredAt now window =
  batchDeadlineExpiredAt now (batchWindowDeadlineNanoseconds window)

nanosecondsPerMicrosecond :: Integer
nanosecondsPerMicrosecond = 1000

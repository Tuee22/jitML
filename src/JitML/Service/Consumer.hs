{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DedupCache (..)
  , EventDomain (..)
  , EventId (..)
  , HandlerRouter (..)
  , consumerOutcomeError
  , consumerStep
  , dedupCacheCapacity
  , dedupCacheInsert
  , dedupCacheKnown
  , domainFor
  , emptyHandlerRouter
  , eventIdFromPayload
  , emptyDedupCache
  , processAtLeastOnce
  , routeByKind
  , runConsumerLoop
  )
where

import Control.Monad.IO.Class (MonadIO)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString qualified as StrictByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding

import JitML.AppError.AppError (AppError (..))
import JitML.Service.Capabilities
  ( HasPulsar (..)
  , SubscriptionId
  , TopicName (..)
  )
import JitML.Service.Retry (ServiceError, serviceErrorToAppError)

newtype EventId = EventId
  { unEventId :: Text
  }
  deriving stock (Eq, Ord, Show)

eventIdFromPayload :: ByteString.ByteString -> EventId
eventIdFromPayload payload =
  EventId (Text.Encoding.decodeUtf8 (hexEncode (SHA256.hash payload)))

processAtLeastOnce :: (Ord eventId) => [eventId] -> [eventId]
processAtLeastOnce = reverse . foldl insertIfMissing []
 where
  insertIfMissing seen eventId
    | eventId `elem` seen = seen
    | otherwise = eventId : seen

hexEncode :: StrictByteString.ByteString -> StrictByteString.ByteString
hexEncode =
  StrictByteString.pack . concatMap byteToHex . StrictByteString.unpack
 where
  byteToHex byte =
    [ fromIntegral (fromEnum (intToDigit (fromIntegral (byte `div` 16))))
    , fromIntegral (fromEnum (intToDigit (fromIntegral (byte `mod` 16))))
    ]

-- | The four per-domain handlers the consumer dispatches to.
data EventDomain
  = TrainingDomain
  | TuneDomain
  | RlDomain
  | InferenceDomain
  deriving stock (Eq, Show)

-- | Pure routing — given a topic name (e.g.
-- `"training.command.linux-cpu"`), return the per-domain handler bucket.
domainFor :: Text -> Maybe EventDomain
domainFor topic
  | "training." `isPrefix` topic = Just TrainingDomain
  | "tune." `isPrefix` topic = Just TuneDomain
  | "rl." `isPrefix` topic = Just RlDomain
  | "inference." `isPrefix` topic = Just InferenceDomain
  | otherwise = Nothing
 where
  isPrefix prefix t =
    Text.Encoding.encodeUtf8 prefix `StrictByteString.isPrefixOf` Text.Encoding.encodeUtf8 t

-- | Per-handler LRU dedup cache. The capacity + TTL come from the LiveConfig.
-- The implementation is a bounded list of recently-seen `EventId` values; an
-- insert evicts the oldest entry past the capacity.
data DedupCache = DedupCache
  { dedupCacheEntries :: [EventId]
  , dedupCacheLimit :: Int
  }
  deriving stock (Eq, Show)

emptyDedupCache :: Int -> DedupCache
emptyDedupCache limit = DedupCache {dedupCacheEntries = [], dedupCacheLimit = limit}

dedupCacheCapacity :: DedupCache -> Int
dedupCacheCapacity = dedupCacheLimit

dedupCacheKnown :: EventId -> DedupCache -> Bool
dedupCacheKnown eventId cache = eventId `elem` dedupCacheEntries cache

dedupCacheInsert :: EventId -> DedupCache -> DedupCache
dedupCacheInsert eventId cache
  | dedupCacheKnown eventId cache = cache
  | otherwise =
      cache
        { dedupCacheEntries =
            take (dedupCacheLimit cache) (eventId : dedupCacheEntries cache)
        }

-- | The handler router carries one dedup cache per domain. The daemon's
-- consumer threads each event through the router, which checks the per-domain
-- cache before dispatch.
data HandlerRouter = HandlerRouter
  { trainingCache :: DedupCache
  , tuneCache :: DedupCache
  , rlCache :: DedupCache
  , inferenceCache :: DedupCache
  }
  deriving stock (Eq, Show)

routeByKind :: HandlerRouter -> EventDomain -> EventId -> (HandlerRouter, Bool)
routeByKind router domain eventId =
  case domain of
    TrainingDomain ->
      let cache = trainingCache router
       in if dedupCacheKnown eventId cache
            then (router, False)
            else (router {trainingCache = dedupCacheInsert eventId cache}, True)
    TuneDomain ->
      let cache = tuneCache router
       in if dedupCacheKnown eventId cache
            then (router, False)
            else (router {tuneCache = dedupCacheInsert eventId cache}, True)
    RlDomain ->
      let cache = rlCache router
       in if dedupCacheKnown eventId cache
            then (router, False)
            else (router {rlCache = dedupCacheInsert eventId cache}, True)
    InferenceDomain ->
      let cache = inferenceCache router
       in if dedupCacheKnown eventId cache
            then (router, False)
            else (router {inferenceCache = dedupCacheInsert eventId cache}, True)

emptyHandlerRouter :: Int -> HandlerRouter
emptyHandlerRouter limit =
  HandlerRouter
    { trainingCache = emptyDedupCache limit
    , tuneCache = emptyDedupCache limit
    , rlCache = emptyDedupCache limit
    , inferenceCache = emptyDedupCache limit
    }

-- | The outcome of a single consumer step. The daemon's `Consumer` IO loop
-- runs `pulsarSubscribe` once, then walks `consumerStep` per delivered
-- envelope. The typed record names what happened so the daemon's tests can
-- assert ack-after-dispatch + dedup-on-redelivery without binding to a
-- live broker.
data ConsumerOutcome
  = -- | Fresh event for the named domain; the handler was invoked + acked.
    ConsumerDispatched EventDomain EventId
  | -- | Pulsar redelivery; the handler was skipped, the event was still acked.
    ConsumerDeduplicated EventDomain EventId
  | -- | Topic name didn't match any of the four domains; the event was acked
    -- and skipped (idempotent no-op).
    ConsumerSkippedUnroutable Text
  | -- | The capability call failed beyond the retry budget.
    ConsumerError ServiceError
  deriving stock (Eq, Show)

-- | Process one Pulsar envelope through the typed pipeline:
-- (1) compute the payload-hash `EventID`, (2) route by topic prefix to the
-- per-domain cache, (3) on first-seen dispatch the handler (caller-supplied,
-- IO action), (4) ack the envelope through `HasPulsar.pulsarAcknowledge`.
-- On dedup-hit, skip dispatch but still ack (Pulsar redelivery semantics).
consumerStep
  :: (HasPulsar m, MonadIO m)
  => SubscriptionId
  -> HandlerRouter
  -> TopicName
  -> Text
  -- ^ payload bytes (Pulsar message body)
  -> (EventDomain -> EventId -> Text -> m ())
  -- ^ per-domain dispatcher
  -> m (HandlerRouter, ConsumerOutcome)
consumerStep _subscription router topic payload dispatch = do
  let eventId = eventIdFromPayload (Text.Encoding.encodeUtf8 payload)
  case domainFor (unTopicName topic) of
    Nothing -> do
      ackResult <- pulsarAcknowledge topic payload
      case ackResult of
        Left err -> pure (router, ConsumerError err)
        Right () -> pure (router, ConsumerSkippedUnroutable (unTopicName topic))
    Just domain -> do
      let (router', isFresh) = routeByKind router domain eventId
      if isFresh
        then do
          dispatch domain eventId payload
          ackResult <- pulsarAcknowledge topic payload
          case ackResult of
            Left err -> pure (router', ConsumerError err)
            Right () -> pure (router', ConsumerDispatched domain eventId)
        else do
          ackResult <- pulsarAcknowledge topic payload
          case ackResult of
            Left err -> pure (router', ConsumerError err)
            Right () -> pure (router', ConsumerDeduplicated domain eventId)

-- | Map a `ConsumerOutcome` to an `AppError` for the daemon's exit path.
-- An ack failure beyond the `RetryPolicy` budget surfaces `PulsarFailed`
-- per doctrine §Capability Classes and Service Errors. Successful
-- dispatch / dedup / skip outcomes return `Nothing`.
consumerOutcomeError :: ConsumerOutcome -> Maybe AppError
consumerOutcomeError outcome =
  case outcome of
    ConsumerError serviceErr -> Just (serviceErrorToAppError serviceErr)
    _ -> Nothing

-- | Drain the subscription cursor through `consumerStep` for `n` envelopes;
-- returns the final router state and the in-order outcome list. The daemon's
-- production loop calls this in an `infinitely`-style loop with batch
-- pulls; the bounded variant is what `jitml-daemon-lifecycle` uses to
-- assert the dispatcher + dedup behavior against a synthetic broker.
runConsumerLoop
  :: (HasPulsar m, MonadIO m)
  => SubscriptionId
  -> HandlerRouter
  -> Int
  -- ^ envelopes to pull
  -> (EventDomain -> EventId -> Text -> m ())
  -> m (HandlerRouter, [ConsumerOutcome])
runConsumerLoop subscription router0 budget dispatch =
  go router0 [] budget
 where
  go router outcomes 0 = pure (router, reverse outcomes)
  go router outcomes remaining = do
    consumed <- pulsarConsume subscription
    case consumed of
      Left err -> pure (router, reverse (ConsumerError err : outcomes))
      Right (topicText, payload) -> do
        (router', outcome) <-
          consumerStep subscription router (TopicName topicText) payload dispatch
        go router' (outcome : outcomes) (remaining - 1)

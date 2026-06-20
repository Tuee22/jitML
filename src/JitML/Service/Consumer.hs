{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonSubscription (..)
  , DedupCache (..)
  , EventDomain (..)
  , EventId (..)
  , HandlerRouter (..)
  , consumerOutcomeError
  , consumerStep
  , consumerStepWithActions
  , dedupCacheCapacity
  , dedupCacheExpireAt
  , dedupCacheInsert
  , dedupCacheInsertAt
  , dedupCacheKnown
  , dedupCacheKnownAt
  , daemonSubscriptionsForBootConfig
  , domainFor
  , emptyHandlerRouter
  , emptyHandlerRouterWithTtl
  , eventIdFromPayload
  , emptyDedupCache
  , emptyDedupCacheWithTtl
  , processAtLeastOnce
  , routeByKind
  , routeByKindAt
  , runConsumerLoop
  , subscribeDaemonTopics
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString qualified as StrictByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding
import System.Posix.Time (epochTime)

import JitML.AppError.AppError (AppError (..))
import JitML.Coordinator.Topology
  ( Phase (..)
  , Workflow (..)
  , defaultNamespace
  , defaultTenant
  , topicFor
  , topicName
  )
import JitML.Service.BootConfig
  ( BootConfig (..)
  , Residency (..)
  )
import JitML.Service.Capabilities
  ( HasPulsar (..)
  , SubscriptionId
  , TopicName (..)
  )
import JitML.Service.Retry (ServiceError, serviceErrorToAppError)
import JitML.Substrate (Substrate (..))

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
  | "training." `isPrefix` normalizedTopic = Just TrainingDomain
  | "tune." `isPrefix` normalizedTopic = Just TuneDomain
  | "rl." `isPrefix` normalizedTopic = Just RlDomain
  | "inference." `isPrefix` normalizedTopic = Just InferenceDomain
  | otherwise = Nothing
 where
  normalizedTopic = stripPulsarPrefix topic
  isPrefix prefix t =
    Text.Encoding.encodeUtf8 prefix `StrictByteString.isPrefixOf` Text.Encoding.encodeUtf8 t

stripPulsarPrefix :: Text -> Text
stripPulsarPrefix topic =
  maybe
    topic
    Text.Encoding.decodeUtf8
    (StrictByteString.stripPrefix prefix (Text.Encoding.encodeUtf8 topic))
 where
  prefix = Text.Encoding.encodeUtf8 ("persistent://public/default/" :: Text)

data DaemonSubscription = DaemonSubscription
  { daemonSubscriptionTopic :: TopicName
  , daemonSubscriptionName :: Text
  }
  deriving stock (Eq, Show)

-- Sprint 5.13 — the daemon subscription plan derives every topic from the
-- Coordinator's validated topic algebra ('topicFor'), not ad-hoc string prefixes,
-- so the subscriptions cannot drift from the reconciled topic set.
daemonSubscriptionsForBootConfig :: BootConfig -> [DaemonSubscription]
daemonSubscriptionsForBootConfig bootConfig =
  case (bootSubstrate bootConfig, bootResidency bootConfig) of
    (AppleSilicon, Host) ->
      [ daemonSubscription Infer Command AppleSilicon "jitml-host"
      , daemonSubscription Train HostCommand AppleSilicon "jitml-host"
      , daemonSubscription Tune HostCommand AppleSilicon "jitml-host"
      , daemonSubscription Rl HostCommand AppleSilicon "jitml-host"
      ]
    -- Sprint 14.4 — the Apple in-cluster (`ForwardToHost`) daemon also subscribes
    -- to `inference.event.apple-silicon` so it receives the host's reply events
    -- and republishes the correlated result on the client result topic.
    (AppleSilicon, Cluster) ->
      fmap
        (\(workflow, phase) -> daemonSubscription workflow phase AppleSilicon "jitml-service")
        [ (Train, Command)
        , (Tune, Command)
        , (Rl, Command)
        , (Infer, Request)
        , (Infer, Event)
        ]
    _ ->
      fmap
        (\(workflow, phase) -> daemonSubscription workflow phase (bootSubstrate bootConfig) "jitml-service")
        [ (Train, Command)
        , (Tune, Command)
        , (Rl, Command)
        , (Infer, Request)
        ]

subscribeDaemonTopics
  :: (HasPulsar m)
  => [DaemonSubscription]
  -> m [(DaemonSubscription, Either ServiceError SubscriptionId)]
subscribeDaemonTopics =
  traverse subscribeOne
 where
  subscribeOne subscription = do
    result <-
      pulsarSubscribe
        (daemonSubscriptionTopic subscription)
        (daemonSubscriptionName subscription)
    pure (subscription, result)

daemonSubscription :: Workflow -> Phase -> Substrate -> Text -> DaemonSubscription
daemonSubscription workflow phase substrate subscriptionName =
  DaemonSubscription
    { daemonSubscriptionTopic =
        TopicName (topicName (topicFor defaultTenant defaultNamespace workflow phase substrate))
    , daemonSubscriptionName = subscriptionName
    }

-- | Per-handler LRU dedup cache. The capacity + TTL come from the LiveConfig.
-- The implementation is a bounded list of recently-seen `EventId` values with
-- their wall-clock insertion time in seconds.
data DedupCache = DedupCache
  { dedupCacheEntries :: [(EventId, Int)]
  , dedupCacheLimit :: Int
  , dedupCacheTtlSeconds :: Int
  }
  deriving stock (Eq, Show)

emptyDedupCache :: Int -> DedupCache
emptyDedupCache limit = emptyDedupCacheWithTtl limit maxBound

emptyDedupCacheWithTtl :: Int -> Int -> DedupCache
emptyDedupCacheWithTtl limit ttlSeconds =
  DedupCache
    { dedupCacheEntries = []
    , dedupCacheLimit = max 0 limit
    , dedupCacheTtlSeconds = max 0 ttlSeconds
    }

dedupCacheCapacity :: DedupCache -> Int
dedupCacheCapacity = dedupCacheLimit

dedupCacheKnown :: EventId -> DedupCache -> Bool
dedupCacheKnown eventId cache =
  eventId `elem` fmap fst (dedupCacheEntries cache)

dedupCacheKnownAt :: Int -> EventId -> DedupCache -> Bool
dedupCacheKnownAt nowSeconds eventId cache =
  dedupCacheKnown eventId (dedupCacheExpireAt nowSeconds cache)

dedupCacheInsert :: EventId -> DedupCache -> DedupCache
dedupCacheInsert eventId cache
  | dedupCacheKnown eventId cache = cache
  | dedupCacheLimit cache <= 0 = cache {dedupCacheEntries = []}
  | otherwise =
      cache
        { dedupCacheEntries =
            take (dedupCacheLimit cache) ((eventId, 0) : dedupCacheEntries cache)
        }

dedupCacheInsertAt :: Int -> EventId -> DedupCache -> DedupCache
dedupCacheInsertAt nowSeconds eventId cache
  | dedupCacheKnown eventId freshCache = freshCache
  | dedupCacheLimit freshCache <= 0 = freshCache {dedupCacheEntries = []}
  | otherwise =
      freshCache
        { dedupCacheEntries =
            take
              (dedupCacheLimit freshCache)
              ((eventId, nowSeconds) : dedupCacheEntries freshCache)
        }
 where
  freshCache = dedupCacheExpireAt nowSeconds cache

dedupCacheExpireAt :: Int -> DedupCache -> DedupCache
dedupCacheExpireAt nowSeconds cache =
  cache
    { dedupCacheEntries =
        filter (entryIsLive nowSeconds (dedupCacheTtlSeconds cache)) (dedupCacheEntries cache)
    }

entryIsLive :: Int -> Int -> (EventId, Int) -> Bool
entryIsLive _nowSeconds ttlSeconds _entry
  | ttlSeconds <= 0 = False
entryIsLive nowSeconds ttlSeconds (_eventId, insertedAtSeconds) =
  nowSeconds - insertedAtSeconds < ttlSeconds

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
routeByKind =
  routeByKindWith
    dedupCacheKnown
    dedupCacheInsert

routeByKindAt :: Int -> HandlerRouter -> EventDomain -> EventId -> (HandlerRouter, Bool)
routeByKindAt nowSeconds router =
  routeByKindWith
    (dedupCacheKnownAt nowSeconds)
    (dedupCacheInsertAt nowSeconds)
    (expireRouterAt nowSeconds router)

routeByKindWith
  :: (EventId -> DedupCache -> Bool)
  -> (EventId -> DedupCache -> DedupCache)
  -> HandlerRouter
  -> EventDomain
  -> EventId
  -> (HandlerRouter, Bool)
routeByKindWith known insert router domain eventId =
  case domain of
    TrainingDomain ->
      let cache = trainingCache router
       in if known eventId cache
            then (router, False)
            else (router {trainingCache = insert eventId cache}, True)
    TuneDomain ->
      let cache = tuneCache router
       in if known eventId cache
            then (router, False)
            else (router {tuneCache = insert eventId cache}, True)
    RlDomain ->
      let cache = rlCache router
       in if known eventId cache
            then (router, False)
            else (router {rlCache = insert eventId cache}, True)
    InferenceDomain ->
      let cache = inferenceCache router
       in if known eventId cache
            then (router, False)
            else (router {inferenceCache = insert eventId cache}, True)

emptyHandlerRouter :: Int -> HandlerRouter
emptyHandlerRouter limit = emptyHandlerRouterWithTtl limit maxBound

emptyHandlerRouterWithTtl :: Int -> Int -> HandlerRouter
emptyHandlerRouterWithTtl limit ttlSeconds =
  HandlerRouter
    { trainingCache = emptyDedupCacheWithTtl limit ttlSeconds
    , tuneCache = emptyDedupCacheWithTtl limit ttlSeconds
    , rlCache = emptyDedupCacheWithTtl limit ttlSeconds
    , inferenceCache = emptyDedupCacheWithTtl limit ttlSeconds
    }

expireRouterAt :: Int -> HandlerRouter -> HandlerRouter
expireRouterAt nowSeconds router =
  HandlerRouter
    { trainingCache = dedupCacheExpireAt nowSeconds (trainingCache router)
    , tuneCache = dedupCacheExpireAt nowSeconds (tuneCache router)
    , rlCache = dedupCacheExpireAt nowSeconds (rlCache router)
    , inferenceCache = dedupCacheExpireAt nowSeconds (inferenceCache router)
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
  | -- | Dispatch or ack failed beyond the retry budget.
    ConsumerError ServiceError
  deriving stock (Eq, Show)

-- | Process one Pulsar envelope through the typed pipeline:
-- (1) compute the payload-hash `EventID`, (2) route by topic prefix to the
-- per-domain cache, (3) on first-seen dispatch the handler (caller-supplied,
-- IO action), (4) ack the envelope through `HasPulsar.pulsarAcknowledge`
-- only after dispatch succeeds. On dedup-hit, skip dispatch but still ack
-- (Pulsar redelivery semantics). A failed dispatch leaves the dedup cache
-- unchanged and seeks the subscription cursor back to the computed event id,
-- so redelivery cannot be mistaken for an already-applied side effect.
consumerStep
  :: (HasPulsar m, MonadIO m)
  => SubscriptionId
  -> HandlerRouter
  -> TopicName
  -> Text
  -- ^ payload bytes (Pulsar message body)
  -> (EventDomain -> EventId -> Text -> m (Either ServiceError ()))
  -- ^ per-domain dispatcher
  -> m (HandlerRouter, ConsumerOutcome)
consumerStep subscription router topic payload dispatch = do
  consumerStepWithActions
    subscription
    router
    topic
    payload
    (pulsarAcknowledge topic payload)
    (pulsarSeek subscription)
    dispatch

consumerStepWithActions
  :: (MonadIO m)
  => SubscriptionId
  -> HandlerRouter
  -> TopicName
  -> Text
  -- ^ payload bytes (Pulsar message body)
  -> m (Either ServiceError ())
  -- ^ explicit ack action for the concrete delivery
  -> (Text -> m (Either ServiceError ()))
  -- ^ cursor redelivery / seek action, called with the computed event id
  -> (EventDomain -> EventId -> Text -> m (Either ServiceError ()))
  -- ^ per-domain dispatcher
  -> m (HandlerRouter, ConsumerOutcome)
consumerStepWithActions _subscription router topic payload ackDelivery seekDelivery dispatch = do
  let eventId = eventIdFromPayload (Text.Encoding.encodeUtf8 payload)
  case domainFor (unTopicName topic) of
    Nothing -> do
      ackResult <- ackDelivery
      case ackResult of
        Left err -> pure (router, ConsumerError err)
        Right () -> pure (router, ConsumerSkippedUnroutable (unTopicName topic))
    Just domain -> do
      nowSeconds <- liftIO currentEpochSeconds
      let (routerAfterInsert, isFresh) = routeByKindAt nowSeconds router domain eventId
      if isFresh
        then do
          dispatchResult <- dispatch domain eventId payload
          case dispatchResult of
            Left err -> do
              seekResult <- seekDelivery (unEventId eventId)
              case seekResult of
                Left seekErr -> pure (router, ConsumerError seekErr)
                Right () -> pure (router, ConsumerError err)
            Right () -> do
              ackResult <- ackDelivery
              case ackResult of
                Left err -> pure (routerAfterInsert, ConsumerError err)
                Right () -> pure (routerAfterInsert, ConsumerDispatched domain eventId)
        else do
          ackResult <- ackDelivery
          case ackResult of
            Left err -> pure (routerAfterInsert, ConsumerError err)
            Right () -> pure (routerAfterInsert, ConsumerDeduplicated domain eventId)

-- | Map a `ConsumerOutcome` to an `AppError` for the daemon's exit path.
-- A dispatch/ack failure beyond the `RetryPolicy` budget surfaces `PulsarFailed`
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
  -> (EventDomain -> EventId -> Text -> m (Either ServiceError ()))
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

currentEpochSeconds :: IO Int
currentEpochSeconds = do
  now <- epochTime
  pure (floor (realToFrac now :: Double))

{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Consumer
  ( DedupCache (..)
  , EventDomain (..)
  , EventId (..)
  , HandlerRouter (..)
  , dedupCacheCapacity
  , dedupCacheInsert
  , dedupCacheKnown
  , domainFor
  , eventIdFromPayload
  , emptyDedupCache
  , processAtLeastOnce
  , routeByKind
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString qualified as StrictByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding

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

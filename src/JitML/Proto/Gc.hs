{-# LANGUAGE OverloadedStrings #-}

-- | `gc.event.<substrate>` envelope shape and topic registration.
--
-- The `jitml internal gc` reconciler emits one `GcReapedEvent` per
-- reaped manifest after the corresponding MinIO `deleteObject` calls
-- complete. The envelope names the substrate that ran the reap, the
-- experiment hash, the reaped manifest's content sha and its addressed
-- blob keys, the monotonic step the reaped manifest carried, and the
-- wall-clock timestamp the reap completed at. Consumers subscribe to
-- `gc.event.<substrate>` to follow the reconciler's deletion stream.
--
-- This is Phase 13 Sprint `13.7`'s `gc_reaped` Pulsar event surface; the
-- topic is registered in `JitML.Cluster.PulsarBootstrap.substrateTopics`
-- and the envelope is published from `JitML.App.runInternalGc` after
-- each reap. See [../README.md → At-Least-Once Event Processing](../../../README.md).
module JitML.Proto.Gc
  ( GcReapedEvent (..)
  , decodeGcReapedEventProto
  , encodeGcReapedEventProto
  , gcEventTopic
  , parseGcReapedEvent
  , renderGcReapedEvent
  )
where

import Data.ByteString (ByteString)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import Text.Read (readMaybe)

import JitML.Proto.Wire
  ( ProtoField
  , decodeMessage
  , encodeMessage
  , fieldMessages
  , fieldString
  , fieldWord64
  , stringField
  , uint64Field
  )
import JitML.Substrate (Substrate, renderSubstrate)

-- | One reaped manifest's wire envelope.
data GcReapedEvent = GcReapedEvent
  { gcEventExperimentHash :: Text
  , gcEventManifestSha :: Text
  , gcEventReapedBlobShas :: [Text]
  , gcEventStepAtReap :: Word64
  , gcEventSubstrate :: Text
  , gcEventTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

-- | Substrate-scoped topic name. Matches the persistent path registered
-- by `JitML.Cluster.PulsarBootstrap.substrateTopics`.
gcEventTopic :: Substrate -> Text
gcEventTopic substrate =
  "persistent://public/default/gc.event." <> renderSubstrate substrate

renderGcReapedEvent :: GcReapedEvent -> Text
renderGcReapedEvent event =
  Text.unlines
    [ "envelope: GcReapedEvent"
    , "experiment-hash: " <> gcEventExperimentHash event
    , "manifest-sha: " <> gcEventManifestSha event
    , "reaped-blob-shas: " <> Text.intercalate "," (gcEventReapedBlobShas event)
    , "step-at-reap: " <> Text.pack (show (gcEventStepAtReap event))
    , "substrate: " <> gcEventSubstrate event
    , "timestamp-ns: " <> Text.pack (show (gcEventTimestampNs event))
    ]

parseGcReapedEvent :: Text -> Maybe GcReapedEvent
parseGcReapedEvent payload = do
  let fields = mapMaybe parseLineField (Text.lines payload)
      value key = lookup key fields
  "GcReapedEvent" <- value "envelope"
  GcReapedEvent
    <$> value "experiment-hash"
    <*> value "manifest-sha"
    <*> fmap parseBlobShaList (value "reaped-blob-shas")
    <*> (value "step-at-reap" >>= readWord64)
    <*> value "substrate"
    <*> (value "timestamp-ns" >>= readWord64)

encodeGcReapedEventProto :: GcReapedEvent -> ByteString
encodeGcReapedEventProto event =
  encodeMessage $
    [ stringField 1 (gcEventExperimentHash event)
    , stringField 2 (gcEventManifestSha event)
    ]
      <> fmap (stringField 3) (gcEventReapedBlobShas event)
      <> [ uint64Field 4 (gcEventStepAtReap event)
         , stringField 5 (gcEventSubstrate event)
         , uint64Field 6 (gcEventTimestampNs event)
         ]

decodeGcReapedEventProto :: ByteString -> Either Text GcReapedEvent
decodeGcReapedEventProto bytes = do
  fields <- decodeMessage bytes
  experimentHash <- require "experiment_hash" (fieldString 1 fields)
  manifestSha <- require "manifest_sha" (fieldString 2 fields)
  blobShas <- require "reaped_blob_shas" (decodeStrings 3 fields)
  stepAtReap <- require "step_at_reap" (fieldWord64 4 fields)
  substrate <- require "substrate" (fieldString 5 fields)
  timestampNs <- require "timestamp_ns" (fieldWord64 6 fields)
  Right
    GcReapedEvent
      { gcEventExperimentHash = experimentHash
      , gcEventManifestSha = manifestSha
      , gcEventReapedBlobShas = blobShas
      , gcEventStepAtReap = stepAtReap
      , gcEventSubstrate = substrate
      , gcEventTimestampNs = timestampNs
      }

-- | Decode every length-delimited entry on `fieldNumber` as UTF-8 text.
-- proto3 repeated strings emit one length-delimited field per entry; an
-- absent field is `Just []` so the proto3 default for repeated holds.
decodeStrings :: Word64 -> [ProtoField] -> Maybe [Text]
decodeStrings fieldNumber fields = do
  raw <- fieldMessages fieldNumber fields
  traverse decodeOne raw
 where
  decodeOne bs =
    case Text.Encoding.decodeUtf8' bs of
      Left _ -> Nothing
      Right t -> Just t

parseBlobShaList :: Text -> [Text]
parseBlobShaList raw
  | Text.null raw = []
  | otherwise =
      filter (not . Text.null)
        . fmap Text.strip
        $ Text.splitOn "," raw

parseLineField :: Text -> Maybe (Text, Text)
parseLineField line =
  case Text.breakOn ":" line of
    (_, "") -> Nothing
    (key, rest) -> Just (Text.strip key, Text.strip (Text.drop 1 rest))

readWord64 :: Text -> Maybe Word64
readWord64 = readMaybe . Text.unpack

require :: Text -> Maybe a -> Either Text a
require label Nothing = Left ("missing field: " <> label)
require _ (Just value) = Right value

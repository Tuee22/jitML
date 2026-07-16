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
-- topic is registered in `JitML.Cluster.PulsarBootstrap.pulsarTopics`
-- and the envelope is published from `JitML.App.runInternalGc` after
-- each reap. See [../README.md → At-Least-Once Event Processing](../../../README.md).
module JitML.Proto.Gc
  ( GcReapedEvent (..)
  , decodeGcReapedEventProto
  , encodeGcReapedEventProto
  , parseGcReapedEvent
  , renderGcReapedEvent
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import Text.Read (readMaybe)

import JitML.Proto.Wire
  ( ProtoField (..)
  , ProtoValue (..)
  , decodeMessage
  , encodeMessage
  , stringField
  , uint64Field
  )
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- | One reaped manifest's wire envelope.
data GcReapedEvent = GcReapedEvent
  { gcEventExperimentHash :: Text
  , gcEventManifestSha :: Text
  , gcEventReapedBlobShas :: [Text]
  , gcEventStepAtReap :: Word64
  , gcEventSubstrate :: Substrate
  , gcEventTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

renderGcReapedEvent :: GcReapedEvent -> Text
renderGcReapedEvent event =
  Text.unlines
    [ "envelope: GcReapedEvent"
    , "experiment-hash: " <> gcEventExperimentHash event
    , "manifest-sha: " <> gcEventManifestSha event
    , "reaped-blob-shas: " <> Text.intercalate "," (gcEventReapedBlobShas event)
    , "step-at-reap: " <> Text.pack (show (gcEventStepAtReap event))
    , "substrate: " <> renderSubstrate (gcEventSubstrate event)
    , "timestamp-ns: " <> Text.pack (show (gcEventTimestampNs event))
    ]

-- | Decode exactly the text shape emitted by 'renderGcReapedEvent'. Unknown,
-- duplicate, malformed, missing, and empty scalar fields are rejected. The
-- reaped-blob list is the one deliberately empty-capable field because a
-- manifest can be reaped while all of its blobs remain live through another
-- manifest.
parseGcReapedEvent :: Text -> Either Text GcReapedEvent
parseGcReapedEvent payload = do
  fields <- traverse parseLineField (Text.lines payload)
  requireOnlyFields gcEventFieldNames fields
  envelope <- requiredField "envelope" fields
  if envelope == "GcReapedEvent"
    then Right ()
    else Left "invalid field: envelope"
  experimentHash <- requiredField "experiment-hash" fields
  manifestSha <- requiredField "manifest-sha" fields
  blobShas <- requiredBlobShaList fields
  stepAtReap <- requiredReadField "step-at-reap" fields
  substrateText <- requiredField "substrate" fields
  substrate <-
    maybe
      (Left "invalid field: substrate")
      Right
      (parseSubstrate substrateText)
  timestampNs <- requiredReadField "timestamp-ns" fields
  Right
    GcReapedEvent
      { gcEventExperimentHash = experimentHash
      , gcEventManifestSha = manifestSha
      , gcEventReapedBlobShas = blobShas
      , gcEventStepAtReap = stepAtReap
      , gcEventSubstrate = substrate
      , gcEventTimestampNs = timestampNs
      }

encodeGcReapedEventProto :: GcReapedEvent -> ByteString
encodeGcReapedEventProto event =
  encodeMessage $
    [ stringField 1 (gcEventExperimentHash event)
    , stringField 2 (gcEventManifestSha event)
    ]
      <> fmap (stringField 3) (gcEventReapedBlobShas event)
      <> [ uint64Field 4 (gcEventStepAtReap event)
         , stringField 5 (renderSubstrate (gcEventSubstrate event))
         , uint64Field 6 (gcEventTimestampNs event)
         ]

decodeGcReapedEventProto :: ByteString -> Either Text GcReapedEvent
decodeGcReapedEventProto bytes = do
  fields <- decodeMessage bytes
  requireOnlyProtoFields fields
  experimentHash <- requiredProtoString "experiment_hash" 1 fields
  manifestSha <- requiredProtoString "manifest_sha" 2 fields
  blobShas <- repeatedProtoStrings "reaped_blob_shas" 3 fields
  stepAtReap <- requiredProtoWord64 "step_at_reap" 4 fields
  substrateText <- requiredProtoString "substrate" 5 fields
  substrate <-
    maybe
      (Left "invalid protobuf field: substrate")
      Right
      (parseSubstrate substrateText)
  timestampNs <- requiredProtoWord64 "timestamp_ns" 6 fields
  Right
    GcReapedEvent
      { gcEventExperimentHash = experimentHash
      , gcEventManifestSha = manifestSha
      , gcEventReapedBlobShas = blobShas
      , gcEventStepAtReap = stepAtReap
      , gcEventSubstrate = substrate
      , gcEventTimestampNs = timestampNs
      }

gcEventFieldNames :: [Text]
gcEventFieldNames =
  [ "envelope"
  , "experiment-hash"
  , "manifest-sha"
  , "reaped-blob-shas"
  , "step-at-reap"
  , "substrate"
  , "timestamp-ns"
  ]

parseBlobShaList :: Text -> Either Text [Text]
parseBlobShaList raw
  | Text.null raw = Right []
  | otherwise = traverse requireBlobSha (Text.splitOn "," raw)
 where
  requireBlobSha encoded =
    let blobSha = Text.strip encoded
     in if Text.null blobSha
          then Left "empty reaped blob sha"
          else Right blobSha

fieldValues :: Text -> [(Text, Text)] -> [Text]
fieldValues key fields =
  [value | (candidate, value) <- fields, candidate == key]

requiredField :: Text -> [(Text, Text)] -> Either Text Text
requiredField key fields =
  case fieldValues key fields of
    [] -> Left ("missing field: " <> key)
    [value]
      | Text.null value -> Left ("empty field: " <> key)
      | otherwise -> Right value
    _ -> Left ("duplicate field: " <> key)

requiredBlobShaList :: [(Text, Text)] -> Either Text [Text]
requiredBlobShaList fields =
  case fieldValues "reaped-blob-shas" fields of
    [] -> Left "missing field: reaped-blob-shas"
    [value] -> parseBlobShaList value
    _ -> Left "duplicate field: reaped-blob-shas"

requiredReadField :: (Read value) => Text -> [(Text, Text)] -> Either Text value
requiredReadField key fields = do
  encoded <- requiredField key fields
  maybe (Left ("malformed field: " <> key)) Right (readMaybe (Text.unpack encoded))

requireOnlyFields :: [Text] -> [(Text, Text)] -> Either Text ()
requireOnlyFields allowed fields =
  case [key | (key, _value) <- fields, key `notElem` allowed] of
    [] -> Right ()
    unknown : _ -> Left ("unknown field: " <> unknown)

parseLineField :: Text -> Either Text (Text, Text)
parseLineField line =
  case Text.breakOn ":" line of
    (_, "") -> Left ("malformed field line: " <> line)
    (rawKey, rest) ->
      let key = Text.strip rawKey
       in if Text.null key
            then Left "empty field name"
            else Right (key, Text.strip (Text.drop 1 rest))

requireOnlyProtoFields :: [ProtoField] -> Either Text ()
requireOnlyProtoFields fields =
  case [number | ProtoField number _value <- fields, number `notElem` [1 .. 6]] of
    [] -> Right ()
    unknown : _ -> Left ("unknown protobuf field: " <> Text.pack (show unknown))

requiredProtoString :: Text -> Word64 -> [ProtoField] -> Either Text Text
requiredProtoString label fieldNumber fields =
  case protoValues fieldNumber fields of
    [] -> Left ("missing protobuf field: " <> label)
    [LengthDelimited bytes] ->
      case Text.Encoding.decodeUtf8' bytes of
        Left _ -> Left ("malformed protobuf field: " <> label)
        Right value
          | Text.null value -> Left ("empty protobuf field: " <> label)
          | otherwise -> Right value
    [_wrongWireType] -> Left ("malformed protobuf field: " <> label)
    _ -> Left ("duplicate protobuf field: " <> label)

requiredProtoWord64 :: Text -> Word64 -> [ProtoField] -> Either Text Word64
requiredProtoWord64 label fieldNumber fields =
  case protoValues fieldNumber fields of
    [] -> Left ("missing protobuf field: " <> label)
    [Varint value] -> Right value
    [_wrongWireType] -> Left ("malformed protobuf field: " <> label)
    _ -> Left ("duplicate protobuf field: " <> label)

repeatedProtoStrings :: Text -> Word64 -> [ProtoField] -> Either Text [Text]
repeatedProtoStrings label fieldNumber fields =
  traverse decodeOne (protoValues fieldNumber fields)
 where
  decodeOne (LengthDelimited bytes) =
    case Text.Encoding.decodeUtf8' bytes of
      Left _ -> Left ("malformed protobuf field: " <> label)
      Right value
        | Text.null value -> Left ("empty protobuf field: " <> label)
        | otherwise -> Right value
  decodeOne _ = Left ("malformed protobuf field: " <> label)

protoValues :: Word64 -> [ProtoField] -> [ProtoValue]
protoValues fieldNumber fields =
  [value | ProtoField number value <- fields, number == fieldNumber]

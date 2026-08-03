{-# LANGUAGE OverloadedStrings #-}

-- | `gc.event.<substrate>` envelope shape and topic registration.
--
-- The `jitml internal gc` reconciler emits one `GcReapedEvent` per
-- reaped manifest after the corresponding MinIO `deleteObject` calls
-- complete. The envelope names the substrate that ran the reap, the
-- experiment hash, the reaped manifest's content sha and its exact addressed
-- physical-object keys, the monotonic step the reaped manifest carried, the
-- wall-clock timestamp the reap completed at, and a stable semantic event id.
-- Consumers subscribe to
-- `gc.event.<substrate>` to follow the reconciler's deletion stream.
--
-- The broker-facing 'Text' codec is a lowercase hexadecimal rendering of the
-- canonical protobuf bytes. This keeps delimiter-rich S3 key text length-delimited
-- instead of placing it in an ambiguous delimiter-separated text field.
--
-- This is Phase 13 Sprint `13.7`'s `gc_reaped` Pulsar event surface; the
-- topic is registered in `JitML.Cluster.PulsarBootstrap.pulsarTopics`
-- and the envelope is published from `JitML.App.runInternalGc` after
-- each reap. See [../README.md → At-Least-Once Event Processing](../../../README.md).
module JitML.Proto.Gc
  ( GcReapedEvent (..)
  , decodeGcReapedEventProto
  , encodeGcReapedEventProto
  , gcReapedEventSemanticId
  , parseGcReapedEvent
  , renderGcReapedEvent
  )
where

import Codec.Serialise (serialise)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (digitToInt, intToDigit, isControl)
import Data.Foldable (traverse_)
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
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
  { gcEventId :: Text
  , gcEventExperimentHash :: Text
  , gcEventManifestSha :: Text
  , gcEventReapedObjectKeys :: [Text]
  , gcEventStepAtReap :: Word64
  , gcEventSubstrate :: Substrate
  , gcEventTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

-- | Render one canonical, length-safe topic payload. Encoding canonicalizes
-- the physical-key set and recomputes the semantic event id rather than
-- trusting either caller-supplied representation.
renderGcReapedEvent :: GcReapedEvent -> Text
renderGcReapedEvent event =
  gcEventTextPrefix <> hexEncodeBytes (encodeGcReapedEventProto event)

-- | Decode exactly the canonical topic representation emitted by
-- 'renderGcReapedEvent'. Non-hex, noncanonical protobuf, invalid physical
-- keys, noncanonical key sets, and forged event identities are rejected.
parseGcReapedEvent :: Text -> Either Text GcReapedEvent
parseGcReapedEvent payload = do
  encoded <-
    maybe
      (Left "invalid GC event text envelope")
      Right
      (Text.stripPrefix gcEventTextPrefix payload)
  bytes <- hexDecodeBytes encoded
  event <- decodeGcReapedEventProto bytes
  if encodeGcReapedEventProto event == bytes
    then Right event
    else Left "GC event text envelope does not contain canonical protobuf bytes"

-- | Stable semantic identity for one exact GC deletion set. This deliberately
-- mirrors `JitML.Checkpoint.Store.gcEventId` without importing Store (which
-- would couple the broker codec to persistence): canonical CBOR supplies the
-- length boundaries and substrate/completion time do not participate.
gcReapedEventSemanticId :: GcReapedEvent -> Text
gcReapedEventSemanticId event =
  WeightCodec.jmw1ContentSha
    ( serialise
        ( "jitml-gc-reaped-event-id-v1" :: Text
        , gcEventExperimentHash event
        , gcEventManifestSha event
        , gcEventStepAtReap event
        , canonicalObjectKeys event
        )
    )

-- | Encode canonical proto3-compatible bytes. The caller-provided id and key
-- ordering are not serialized: keys are sorted/deduplicated first and the id
-- is recomputed from that exact canonical deletion set.
encodeGcReapedEventProto :: GcReapedEvent -> ByteString
encodeGcReapedEventProto suppliedEvent =
  let event = canonicalGcReapedEvent suppliedEvent
   in encodeMessage $
        [ stringField 1 (gcEventExperimentHash event)
        , stringField 2 (gcEventManifestSha event)
        ]
          <> fmap (stringField 3) (gcEventReapedObjectKeys event)
          <> [ uint64Field 4 (gcEventStepAtReap event)
             , stringField 5 (renderSubstrate (gcEventSubstrate event))
             , uint64Field 6 (gcEventTimestampNs event)
             , stringField 7 (gcEventId event)
             ]

decodeGcReapedEventProto :: ByteString -> Either Text GcReapedEvent
decodeGcReapedEventProto bytes = do
  fields <- decodeMessage bytes
  requireOnlyProtoFields fields
  eventId <- requiredProtoString "event_id" 7 fields
  experimentHash <- requiredProtoString "experiment_hash" 1 fields
  manifestSha <- requiredProtoString "manifest_sha" 2 fields
  objectKeys <- repeatedProtoStrings "reaped_object_keys" 3 fields
  stepAtReap <- requiredProtoWord64 "step_at_reap" 4 fields
  substrateText <- requiredProtoString "substrate" 5 fields
  substrate <-
    maybe
      (Left "invalid protobuf field: substrate")
      Right
      (parseSubstrate substrateText)
  timestampNs <- requiredProtoWord64 "timestamp_ns" 6 fields
  event <-
    validateGcReapedEvent
      GcReapedEvent
        { gcEventId = eventId
        , gcEventExperimentHash = experimentHash
        , gcEventManifestSha = manifestSha
        , gcEventReapedObjectKeys = objectKeys
        , gcEventStepAtReap = stepAtReap
        , gcEventSubstrate = substrate
        , gcEventTimestampNs = timestampNs
        }
  if encodeGcReapedEventProto event == bytes
    then Right event
    else Left "GC event protobuf bytes are not canonical"

gcEventTextPrefix :: Text
gcEventTextPrefix = "jitml-gc-reaped-event-protobuf-hex-v1:"

canonicalGcReapedEvent :: GcReapedEvent -> GcReapedEvent
canonicalGcReapedEvent event =
  let withCanonicalKeys =
        event
          { gcEventReapedObjectKeys = canonicalObjectKeys event
          }
   in withCanonicalKeys
        { gcEventId = gcReapedEventSemanticId withCanonicalKeys
        }

canonicalObjectKeys :: GcReapedEvent -> [Text]
canonicalObjectKeys =
  Set.toAscList . Set.fromList . gcEventReapedObjectKeys

validateGcReapedEvent :: GcReapedEvent -> Either Text GcReapedEvent
validateGcReapedEvent event = do
  validateGcExperimentHash (gcEventExperimentHash event)
  validateCanonicalManifestSha (gcEventManifestSha event)
  if gcEventReapedObjectKeys event == canonicalObjectKeys event
    then Right ()
    else Left "protobuf field reaped_object_keys is not sorted and unique"
  traverse_
    (validateGcObjectKey (gcEventExperimentHash event))
    (gcEventReapedObjectKeys event)
  validateGcSnapshotKeySet
    (gcEventExperimentHash event)
    (gcEventReapedObjectKeys event)
  if gcEventId event == gcReapedEventSemanticId event
    then Right event
    else Left "protobuf field event_id does not bind the canonical GC event"

validateCanonicalManifestSha :: Text -> Either Text ()
validateCanonicalManifestSha manifestSha
  | Text.length manifestSha /= 64 =
      Left "invalid protobuf field: manifest_sha must be 64 lowercase hexadecimal characters"
  | Text.all isLowerHex manifestSha = Right ()
  | otherwise =
      Left "invalid protobuf field: manifest_sha must be 64 lowercase hexadecimal characters"

validateGcObjectKey :: Text -> Text -> Either Text ()
validateGcObjectKey experimentHash fullKey = do
  canonical <- canonicalGcPhysicalObjectKey experimentHash fullKey
  if fullKey == canonical
    then Right ()
    else
      Left
        ( "GC physical object key is not the canonical full bucket key: "
            <> fullKey
            <> "; expected "
            <> canonical
        )

-- Keep decoder-side key validation exactly aligned with the durable Store
-- contract. Store accepts the relative spelling only while constructing its
-- physical graph, then persists the canonical bucket-qualified spelling. A
-- broker event therefore must already carry that full spelling; accepting an
-- alias here would give one physical object more than one wire identity.
canonicalGcPhysicalObjectKey :: Text -> Text -> Either Text Text
canonicalGcPhysicalObjectKey experimentHash rawKey = do
  validateGcExperimentHash experimentHash
  let bucketPrefix = "jitml-checkpoints/"
      relativeKey = fromMaybe rawKey (Text.stripPrefix bucketPrefix rawKey)
      segments = Text.splitOn "/" relativeKey
  traverse_ (validateGcPathSegment "physical object key") segments
  case segments of
    keyExperiment : firstObjectSegment : remainingObjectSegments
      | keyExperiment /= experimentHash ->
          Left
            ( "GC physical object is outside its experiment: "
                <> rawKey
            )
      | firstObjectSegment `elem` ["manifests", "pointers", "gc"] ->
          Left
            ( "GC physical object occupies a reserved control prefix: "
                <> rawKey
            )
      | firstObjectSegment == "snapshots" -> do
          case remainingObjectSegments of
            [snapshotId, "objects", originalKeySha] -> do
              validateCanonicalSha256 "storage snapshot id" snapshotId
              validateCanonicalSha256
                "snapshot original-key SHA-256"
                originalKeySha
            [snapshotId, "committed.cbor"] ->
              validateCanonicalSha256 "storage snapshot id" snapshotId
            _ ->
              Left
                ( "GC physical object occupies an invalid snapshot path: "
                    <> rawKey
                )
          Right
            ( bucketPrefix
                <> Text.intercalate
                  "/"
                  (keyExperiment : firstObjectSegment : remainingObjectSegments)
            )
      | otherwise ->
          Left
            ( "GC physical object is not owned by a committed storage snapshot: "
                <> rawKey
            )
    [_] -> Left ("GC physical object has no object path: " <> rawKey)
    [] -> Left "GC physical object key is empty"

validateGcExperimentHash :: Text -> Either Text ()
validateGcExperimentHash = validateGcPathSegment "experiment hash"

validateGcSnapshotKeySet :: Text -> [Text] -> Either Text ()
validateGcSnapshotKeySet experimentHash objectKeys = do
  snapshotIds <- traverse snapshotIdForKey objectKeys
  case Set.toAscList (Set.fromList snapshotIds) of
    [] -> Left "GC event has no committed storage-snapshot object set"
    [_snapshotId] -> Right ()
    _ -> Left "GC event mixes physical objects from multiple storage snapshots"
  case filter ("/committed.cbor" `Text.isSuffixOf`) objectKeys of
    [_commitKey] -> Right ()
    [] -> Left "GC event must contain its exact storage-snapshot commit object"
    _ -> Left "GC event contains more than one storage-snapshot commit object"
 where
  snapshotPrefix = "jitml-checkpoints/" <> experimentHash <> "/snapshots/"

  snapshotIdForKey objectKey = do
    remainder <-
      maybe
        (Left "GC event contains a non-snapshot physical object")
        Right
        (Text.stripPrefix snapshotPrefix objectKey)
    case Text.splitOn "/" remainder of
      snapshotId : _ -> Right snapshotId
      [] -> Left "GC event contains an empty storage snapshot path"

validateCanonicalSha256 :: Text -> Text -> Either Text ()
validateCanonicalSha256 label value
  | Text.length value == 64 && Text.all isLowerHex value = Right ()
  | otherwise = Left (label <> " is not 64 lowercase hexadecimal characters")

validateGcPathSegment :: Text -> Text -> Either Text ()
validateGcPathSegment label segment
  | Text.null segment = Left (label <> " contains an empty path segment")
  | segment == "." = Left (label <> " contains a dot path segment")
  | segment == ".." = Left (label <> " contains a dot-dot path segment")
  | Text.any (\character -> character == '/' || character == '\\') segment =
      Left (label <> " contains a path separator")
  | Text.any isControl segment = Left (label <> " contains a control character")
  | otherwise = Right ()

requireOnlyProtoFields :: [ProtoField] -> Either Text ()
requireOnlyProtoFields fields =
  case [number | ProtoField number _value <- fields, number `notElem` [1 .. 7]] of
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

hexEncodeBytes :: ByteString -> Text
hexEncodeBytes =
  Text.pack . concatMap byteToHex . ByteString.unpack
 where
  byteToHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

hexDecodeBytes :: Text -> Either Text ByteString
hexDecodeBytes encoded
  | Text.null encoded = Left "empty GC event protobuf hex payload"
  | odd (Text.length encoded) = Left "GC event protobuf hex payload has odd length"
  | otherwise = ByteString.pack <$> go (Text.unpack encoded)
 where
  go [] = Right []
  go (high : low : remaining)
    | isLowerHex high && isLowerHex low = do
        decoded <- go remaining
        Right (fromIntegral (digitToInt high * 16 + digitToInt low) : decoded)
    | otherwise = Left "GC event protobuf payload is not canonical lowercase hexadecimal"
  go [_] = Left "GC event protobuf hex payload has odd length"

isLowerHex :: Char -> Bool
isLowerHex character =
  character `elem` ("0123456789abcdef" :: String)

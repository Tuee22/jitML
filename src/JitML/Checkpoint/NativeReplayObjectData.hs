{-# LANGUAGE OverloadedStrings #-}

-- | Bounded ordinary graph DATA for separately retained evaluation replays.
-- A valid graph or matching digest grants no execution, retention, source,
-- learning, publication or parent-authentication capability.
module JitML.Checkpoint.NativeReplayObjectData
  ( NativeReplayObjectData
  , NativeReplayObjectStage (..)
  , refineNativeReplayObjectData
  , decodeNativeReplayObjectData
  , nativeReplayObjectBytes
  , nativeReplayObjectStage
  , nativeReplayObjectIndex
  , nativeReplayObjectAllocation
  , nativeReplayObjectAttempt
  , nativeReplayObjectRoot
  , nativeReplayObjectEntries
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (foldM, replicateM, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types

data NativeReplayObjectStage = InitialModelReplay | FinalModelReplay | StoredFinalModelReplay
  deriving stock (Eq, Show)

-- Private DATA constructor prevents record updates bypassing the checks; pure
-- refinement remains deliberately public and cannot mint an execution result.
data NativeReplayObjectData
  = NativeReplayObjectData
      !NativeReplayObjectStage
      !Word64
      !Digest
      !Digest
      !Digest
      ![(Digest, ByteString)]
      !ByteString
  deriving stock (Eq, Show)

nativeReplayObjectStage :: NativeReplayObjectData -> NativeReplayObjectStage
nativeReplayObjectStage (NativeReplayObjectData actual _ _ _ _ _ _) = actual
nativeReplayObjectIndex :: NativeReplayObjectData -> Word64
nativeReplayObjectIndex (NativeReplayObjectData _ actual _ _ _ _ _) = actual
nativeReplayObjectAllocation :: NativeReplayObjectData -> Digest
nativeReplayObjectAllocation (NativeReplayObjectData _ _ actual _ _ _ _) = actual
nativeReplayObjectAttempt :: NativeReplayObjectData -> Digest
nativeReplayObjectAttempt (NativeReplayObjectData _ _ _ actual _ _ _) = actual
nativeReplayObjectRoot :: NativeReplayObjectData -> Digest
nativeReplayObjectRoot (NativeReplayObjectData _ _ _ _ actual _ _) = actual
nativeReplayObjectEntries :: NativeReplayObjectData -> [(Digest, ByteString)]
nativeReplayObjectEntries (NativeReplayObjectData _ _ _ _ _ actual _) = actual
nativeReplayObjectBytes :: NativeReplayObjectData -> ByteString
nativeReplayObjectBytes (NativeReplayObjectData _ _ _ _ _ _ actual) = actual

domain :: Text
domain = "jitml-native-evaluation-replay-object-v1"

refineNativeReplayObjectData
  :: NativeReplayObjectStage
  -> Word64
  -> Digest
  -> Digest
  -> Digest
  -> [(Digest, ByteString)]
  -> Either CodecError NativeReplayObjectData
refineNativeReplayObjectData stage index allocation attempt root entries = do
  unless (index < 5) (Left (Malformed "replay object child index is outside the original five"))
  unless
    (stage /= StoredFinalModelReplay || index == 0)
    (Left (Malformed "stored final replay object must describe serving index zero"))
  count <- boundedLength PoolNodes (nativePhaseLimit PoolNodes) entries
  -- Compute the exact definite-CBOR size before allocating its encoded buffer.
  -- Node byte buffers are already supplied ordinary DATA. No graph is expanded.
  let framing =
        headerBytes 8
          + textBytes domain
          + headerBytes 1
          + headerBytes (stageCode stage)
          + headerBytes index
          + 3 * digestSize
          + headerBytes (fromIntegral count)
  total <- foldM addEntry framing entries
  checkLimit WholePayloadBytes total
  pool <- foldM insertEntry Graph.emptyNodePool entries
  selected <- Graph.reachableNodePool [root] pool
  let selectedEntries = [(digest, bytes) | (digest, _, bytes) <- Graph.nodePoolEntries selected]
  unless
    (selectedEntries == entries)
    (Left (NonCanonical "replay object entries are not the complete sorted unique reachable pool"))
  rootNode <- maybe (Left (MissingReference root)) Right (Graph.lookupNode root selected)
  unless
    (Schema.nodeKind rootNode `elem` [NReturnEvaluation, NHerEvaluation, NArenaEvaluation])
    (Left (Malformed "replay object root is not an evaluation"))
  let encoded = encodeData stage index allocation attempt root entries
  unless
    (toInteger (BS.length encoded) == total)
    (Left (Malformed "replay object exact encoded-size accounting differs"))
  pure (NativeReplayObjectData stage index allocation attempt root entries encoded)
 where
  addEntry total (_, bytes) = do
    let size = toInteger (BS.length bytes)
        next = total + headerBytes 2 + digestSize + headerBytes (fromIntegral (BS.length bytes)) + size
    checkLimit WholePayloadBytes next
    pure next
  insertEntry pool (expected, bytes) = do
    node <- Schema.decodeNodeData bytes
    unless
      (Schema.nodeCanonicalBytes node == bytes)
      (Left (NonCanonical "replay object node bytes differ from their canonical encoding"))
    (actual, next) <- Graph.internNode node pool
    unless (actual == expected) (Left (Malformed "replay object node SHA differs from its bytes"))
    pure next

decodeNativeReplayObjectData :: ByteString -> Either CodecError NativeReplayObjectData
decodeNativeReplayObjectData bytes = do
  (stage, index, allocation, attempt, root, entries) <- Wire.runParser parser bytes
  actual <- refineNativeReplayObjectData stage index allocation attempt root entries
  unless
    (nativeReplayObjectBytes actual == bytes)
    (Left (NonCanonical "replay object whole bytes differ from canonical encoding"))
  pure actual
 where
  parser = do
    Wire.expectList 8
    actualDomain <- Wire.getText GeneralTextBytes 64
    unless (actualDomain == domain) (Wire.parserFailure (Malformed "replay object domain differs"))
    version <- Wire.getWord
    unless (version == 1) (Wire.parserFailure (Malformed "replay object version differs"))
    code <- Wire.getWord
    stage <- Wire.liftEither (stageFromCode code)
    index <- Wire.getWord
    unless
      (index < 5 && (stage /= StoredFinalModelReplay || index == 0))
      (Wire.parserFailure (Malformed "replay object child index differs"))
    allocation <- Wire.getDigest
    attempt <- Wire.getDigest
    root <- Wire.getDigest
    count <- Wire.getListLength PoolNodes (nativePhaseLimit PoolNodes)
    Wire.ensureMinimumItems (fromIntegral count) 36
    entries <- replicateM count entry
    pure (stage, index, allocation, attempt, root, entries)
  entry = do
    Wire.expectList 2
    digest <- Wire.getDigest
    node <- Wire.getBytes WholePayloadBytes (nativePhaseLimit WholePayloadBytes)
    pure (digest, node)

encodeData
  :: NativeReplayObjectStage
  -> Word64
  -> Digest
  -> Digest
  -> Digest
  -> [(Digest, ByteString)]
  -> ByteString
encodeData stage index allocation attempt root entries =
  Wire.encodeStrict
    ( CBOR.encodeListLen 8
        <> CBOR.encodeString domain
        <> CBOR.encodeWord64 1
        <> CBOR.encodeWord64 (stageCode stage)
        <> CBOR.encodeWord64 index
        <> CBOR.encodeBytes (digestBytes allocation)
        <> CBOR.encodeBytes (digestBytes attempt)
        <> CBOR.encodeBytes (digestBytes root)
        <> CBOR.encodeListLen (fromIntegral (length entries))
        <> foldMap
          ( \(digest, node) ->
              CBOR.encodeListLen 2
                <> CBOR.encodeBytes (digestBytes digest)
                <> CBOR.encodeBytes node
          )
          entries
    )

stageCode :: NativeReplayObjectStage -> Word64
stageCode value = case value of InitialModelReplay -> 0; FinalModelReplay -> 1; StoredFinalModelReplay -> 2
stageFromCode :: Word64 -> Either CodecError NativeReplayObjectStage
stageFromCode value = case value of
  0 -> Right InitialModelReplay
  1 -> Right FinalModelReplay
  2 -> Right StoredFinalModelReplay
  _ -> Left (Malformed "unknown replay object stage")

digestSize :: Integer
digestSize = headerBytes 32 + 32
textBytes :: Text -> Integer
textBytes value =
  let count = BS.length (UTF8.encodeUtf8 value) in headerBytes (fromIntegral count) + toInteger count
headerBytes :: Word64 -> Integer
headerBytes value
  | value < 24 = 1
  | value <= 0xff = 2
  | value <= 0xffff = 3
  | value <= 0xffffffff = 5
  | otherwise = 9

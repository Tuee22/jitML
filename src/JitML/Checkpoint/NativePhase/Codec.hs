{-# LANGUAGE OverloadedStrings #-}

-- | Self-contained canonical phase DATA. The decoder cannot construct an
-- execution stage, observed origin, durable acknowledgement or eligibility.
module JitML.Checkpoint.NativePhase.Codec
  ( PhaseData
  , mkPhaseData
  , encodePhaseData
  , decodePhaseData
  , phaseDataPhase
  , phaseDataContext
  , phaseDataPrevious
  , phaseDataRoot
  , phaseDataPool
  , phaseDataUsage
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (unless, void, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph
import JitML.Checkpoint.NativePhase.Schema
import JitML.Checkpoint.NativePhase.SchemaTable
import JitML.Checkpoint.NativePhase.Types

phaseDomain :: Text
phaseDomain = "jitml-native-rl-phase-data"

data PhaseData = PhaseData !PhaseTag !ContextData !(Maybe Digest) !Digest !NodePool !GraphUsage

phaseDataPhase :: PhaseData -> PhaseTag
phaseDataPhase (PhaseData phase _ _ _ _ _) = phase

phaseDataContext :: PhaseData -> ContextData
phaseDataContext (PhaseData _ context _ _ _ _) = context

phaseDataPrevious :: PhaseData -> Maybe Digest
phaseDataPrevious (PhaseData _ _ previous _ _ _) = previous

phaseDataRoot :: PhaseData -> Digest
phaseDataRoot (PhaseData _ _ _ root _ _) = root

phaseDataPool :: PhaseData -> NodePool
phaseDataPool (PhaseData _ _ _ _ pool _) = pool

phaseDataUsage :: PhaseData -> GraphUsage
phaseDataUsage (PhaseData _ _ _ _ _ usage) = usage

mkPhaseData
  :: PhaseTag -> ContextData -> Maybe Digest -> Digest -> NodePool -> Either CodecError PhaseData
mkPhaseData phase context previous root pool = do
  contextRoots <- contextReferences context
  usage <- validateTypedRoots ((NodeTargets (allowedPhaseKinds phase), root) : contextRoots) pool
  case contextRoots of
    [(NodeTargets [NProducerContextBundle], producer)] -> void (producerClosureBytes producer pool)
    _ -> Left (Malformed "context must retain exactly one producer bundle reference")
  body <- maybe (Left (MissingReference root)) Right (lookupNode root pool)
  case (phase, nodeKind body, nodeFields body) of
    (ColdSnapshotPhase, NContinuousSnapshot, VWord stage : _) -> unless (stage == 0) (Left (Malformed "cold phase contains effective continuous snapshot"))
    (EffectiveSnapshotPhase, NContinuousSnapshot, VWord stage : _) -> unless (stage == 1) (Left (Malformed "effective phase contains cold continuous snapshot"))
    _ -> pure ()
  let value = PhaseData phase context previous root pool usage
      bytes = encodedSize value
  checkLimit WholePayloadBytes bytes
  let actualUsage = usage {usageEncodedBytes = bytes}
  pure (PhaseData phase context previous root pool actualUsage)

prefixEncoding :: PhaseData -> CBOR.Encoding
prefixEncoding (PhaseData phase context previous root _ _) =
  CBOR.encodeListLen 8
    <> CBOR.encodeString phaseDomain
    <> CBOR.encodeWord64 1
    <> CBOR.encodeWord64 (phaseTag phase)
    <> Wire.rawValueEncoding (VList (contextFields context))
    <> Wire.rawValueEncoding (VList [VWord 0, VWord 0, VWord 0, VWord 0])
    <> maybe CBOR.encodeNull (CBOR.encodeBytes . digestBytes) previous
    <> CBOR.encodeBytes (digestBytes root)

argumentBytes :: Integer -> Integer
argumentBytes value
  | value < 24 = 1
  | value <= 255 = 2
  | value <= 65535 = 3
  | value <= 4294967295 = 5
  | otherwise = 9

-- Includes pool array, pair arrays, digest byte headers, node-byte headers,
-- context and the complete envelope. Preflight happens before whole encoding.
encodedSize :: PhaseData -> Integer
encodedSize phase =
  let entries = nodePoolEntries (phaseDataPool phase)
      pair (_, _, bytes) = 1 + 34 + argumentBytes (toInteger (BS.length bytes)) + toInteger (BS.length bytes)
   in toInteger (BS.length (Wire.encodeStrict (prefixEncoding phase)))
        + argumentBytes (toInteger (length entries))
        + sum (fmap pair entries)

encodePhaseData :: PhaseData -> ByteString
encodePhaseData phase =
  let entries = nodePoolEntries (phaseDataPool phase)
      pair (digest, _, bytes) = CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes
   in Wire.encodeStrict
        (prefixEncoding phase <> CBOR.encodeListLen (fromIntegral (length entries)) <> foldMap pair entries)

decodePhaseData :: ByteString -> Either CodecError PhaseData
decodePhaseData = Wire.runParser $ do
  Wire.expectList 8
  domain <- Wire.getText GeneralTextBytes 64
  unless (domain == phaseDomain) (Wire.parserFailure (Malformed "wrong native phase domain"))
  version <- Wire.getWord
  unless (version == 1) (Wire.parserFailure (Malformed "unsupported native phase version"))
  phase <- Wire.getWord >>= Wire.liftEither . phaseFromTag
  context <- parseContextData
  coverage <- parseValue (TNamed "Coverage")
  unless
    (coverage == VList [VWord 0, VWord 0, VWord 0, VWord 0])
    (Wire.parserFailure (Malformed "unsupported phase coverage"))
  absent <- Wire.nextIsNull
  previous <- if absent then Wire.getNull >> pure Nothing else Just <$> Wire.getDigest
  root <- Wire.getDigest
  count <- Wire.getListLength PoolNodes (nativePhaseLimit PoolNodes)
  -- Smallest permitted node is four bytes; each pair needs1+34+1+4 bytes.
  Wire.ensureMinimumItems (fromIntegral count) 40
  contextRoots <- Wire.liftEither (contextReferences context)
  let initialUsage = emptyUsage {usageEdges = 1 + toInteger (length contextRoots)}
  pool <- parsePool count Nothing emptyNodePool initialUsage
  Wire.liftEither (mkPhaseData phase context previous root pool)
 where
  parsePool 0 _ pool _ = pure pool
  parsePool remaining previous pool usage = do
    Wire.expectList 2
    digest <- Wire.getDigest
    case previous of
      Just before -> when (digest <= before) (Wire.parserFailure (NonCanonical "pool keys duplicate or unordered"))
      Nothing -> pure ()
    bytes <- Wire.getBytes WholePayloadBytes (nativePhaseLimit WholePayloadBytes)
    unless (hashBytes bytes == digest) (Wire.parserFailure (HashMismatch digest))
    node <- Wire.liftEither (decodeNodeData bytes)
    localUsage <- Wire.liftEither (nodeLocalUsage node)
    let afterUsage = addGraphUsage usage localUsage
    -- Charge each unique sorted member before storing it in the memoized map.
    -- Temporary node tuples/pages are individually bounded by the schema; no
    -- sequence/tensor is logically expanded while obtaining these counts.
    Wire.liftEither (checkGraphUsage afterUsage)
    (actual, after) <- Wire.liftEither (internNode node pool)
    unless (actual == digest) (Wire.parserFailure (HashMismatch digest))
    parsePool (remaining - 1) (Just digest) after afterUsage

{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary decoded retention DATA and exact byte/link checks only. No read,
-- ACK, origin, restored cursor, parent authentication or admission capability
-- is constructed. The caller must capture actual bounded physical bytes.
module JitML.Checkpoint.NativeRetentionReader
  ( NativeRetentionEnvelopeError (..)
  , NativeDecodedAllocation (..)
  , NativeDecodedRetentionPhase (..)
  , maximumNativeRetentionEnvelopeBytes
  , decodeNativeAllocationEnvelope
  , decodeNativeRetentionPhaseEnvelope
  , validateNativeRetentionPhaseLink
  ) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
  ( CodecError (Malformed)
  , Resource (GeneralTextBytes, ProducerBundleBytes, WholePayloadBytes)
  )
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)

data NativeRetentionEnvelopeError
  = NativeRetentionEnvelopeRejected !Text
  | NativeRetentionEnvelopeCodec !CodecError
  deriving stock (Eq, Show)

-- Deliberately public ordinary data. Mutating/decoding it cannot mint an ACK.
data NativeDecodedAllocation = NativeDecodedAllocation
  { decodedAllocationObject :: !Retain.NativeRetainedObjectData
  , decodedAllocationScope :: !Retain.NativeAllocationScope
  , decodedAllocationPublication :: !Retain.NativePublicationData
  , decodedAllocationPayload :: !ByteString
  }
  deriving stock (Eq, Show)

data NativeDecodedRetentionPhase = NativeDecodedRetentionPhase
  { decodedPhaseObject :: !Retain.NativeRetainedObjectData
  , decodedPhaseClaimKey :: !Text
  , decodedPhaseClaimSha256 :: !Text
  , decodedPhasePublication :: !Retain.NativePublicationData
  , decodedPhaseOrdinal :: !Word64
  , decodedPhasePreviousKey :: !Text
  , decodedPhasePreviousSha256 :: !Text
  , decodedPhaseLabel :: !Text
  , decodedPhasePayload :: !ByteString
  }
  deriving stock (Eq, Show)

-- Retention bounds its RAW payload at256MiB. Its outer envelope necessarily
-- adds bytes. All v1 metadata is ASCII or hex: two bounded keys, three SHA256
-- strings, a64-character label, a bounded scope/publication and shortest CBOR
-- heads occupy less than4096 bytes. This is not a larger child-codec limit.
maximumHeaderBytes :: Int
maximumHeaderBytes = 4096

maximumNativeRetentionEnvelopeBytes :: Integer
maximumNativeRetentionEnvelopeBytes = toInteger Retain.maximumNativeRetentionPayloadBytes + toInteger maximumHeaderBytes

decodeNativeAllocationEnvelope
  :: Retain.NativeRetainedObjectData
  -> ByteString
  -> Either NativeRetentionEnvelopeError NativeDecodedAllocation
decodeNativeAllocationEnvelope expected bytes = do
  checkPhysicalSize expected bytes
  ((scopeBytes, publicationBytes, payloadLength), offset) <-
    codec
      (Wire.runParserPrefix allocationHeader (BS.take maximumHeaderBytes bytes))
  payload <- exactPayload offset payloadLength bytes
  scope <- decodeScope scopeBytes
  address <- rejected (Retain.mkNativeAllocationAddress scope)
  publication <- decodePublication publicationBytes
  require
    (Retain.nativeRetainedObjectKey expected == Retain.nativeAllocationAddressKey address)
    "allocation physical key differs from the exact recorded scope"
  checkPhysicalHashAndPublication expected publication bytes
  pure (NativeDecodedAllocation expected scope publication payload)

decodeNativeRetentionPhaseEnvelope
  :: Retain.NativeRetainedObjectData
  -> ByteString
  -> Either NativeRetentionEnvelopeError NativeDecodedRetentionPhase
decodeNativeRetentionPhaseEnvelope expected bytes = do
  checkPhysicalSize expected bytes
  ( (claimKey, claimSha, publicationBytes, ordinal, previousKey, previousSha, label, payloadLength)
    , offset
    ) <-
    codec
      (Wire.runParserPrefix phaseHeader (BS.take maximumHeaderBytes bytes))
  payload <- exactPayload offset payloadLength bytes
  namespace <- claimNamespace claimKey
  require (ordinal /= maxBound) "phase ordinal is the writer-exhausted reserved value"
  require
    (canonicalSha claimSha && canonicalSha previousSha)
    "phase claim or predecessor SHA is not canonical"
  require (validPhaseLabel label) "phase label differs from the closed writer alphabet/length"
  publication <- decodePublication publicationBytes
  require
    ( Retain.nativeRetainedObjectKey expected
        == namespace <> "/phases/" <> Retain.nativeRetainedObjectSha256 expected <> ".cbor"
    )
    "phase physical key differs from its allocation namespace and exact outer object SHA"
  require
    ( previousKey == claimKey
        || previousKey == namespace <> "/phases/" <> previousSha <> ".cbor"
    )
    "phase predecessor key escapes its exact allocation namespace or SHA"
  checkPhysicalHashAndPublication expected publication bytes
  pure
    ( NativeDecodedRetentionPhase
        expected
        claimKey
        claimSha
        publication
        ordinal
        previousKey
        previousSha
        label
        payload
    )

-- This compares one explicitly selected link. It does not claim that a caller
-- supplied an exhaustive inventory; the authenticated parent must start at the
-- actual claim and consume every physical ordinal through its actual terminal.
validateNativeRetentionPhaseLink
  :: NativeDecodedAllocation
  -> Retain.NativeRetainedObjectData
  -> Word64
  -> NativeDecodedRetentionPhase
  -> Either NativeRetentionEnvelopeError ()
validateNativeRetentionPhaseLink allocation previous ordinal phase = do
  let claim = decodedAllocationObject allocation
  require
    ( decodedPhaseClaimKey phase == Retain.nativeRetainedObjectKey claim
        && decodedPhaseClaimSha256 phase == Retain.nativeRetainedObjectSha256 claim
        && decodedPhasePublication phase == decodedAllocationPublication allocation
    )
    "phase claim/publication differs from the selected actual allocation DATA"
  require
    (decodedPhaseOrdinal phase == ordinal)
    "phase ordinal differs from the selected complete chain position"
  require
    ( decodedPhasePreviousKey phase == Retain.nativeRetainedObjectKey previous
        && decodedPhasePreviousSha256 phase == Retain.nativeRetainedObjectSha256 previous
        && Retain.nativeRetainedObjectPublication previous == decodedAllocationPublication allocation
    )
    "phase predecessor differs from the selected preceding physical object DATA"
  if ordinal == 0
    then require (previous == claim) "first phase must follow the exact claim object"
    else
      require
        (Retain.nativeRetainedObjectKey previous /= Retain.nativeRetainedObjectKey claim)
        "later phase cannot skip its physical predecessor back to the claim"

allocationHeader :: Wire.Parser (ByteString, ByteString, Word64)
allocationHeader = do
  Wire.expectList 4
  expectText "jitml-native-allocation-claim-v1"
  scope <- Wire.getBytes ProducerBundleBytes 1024
  publication <- Wire.getBytes ProducerBundleBytes 1024
  size <- Wire.getBytesLength WholePayloadBytes (toInteger Retain.maximumNativeRetentionPayloadBytes)
  pure (scope, publication, size)

phaseHeader :: Wire.Parser (Text, Text, ByteString, Word64, Text, Text, Text, Word64)
phaseHeader = do
  Wire.expectList 9
  expectText "jitml-native-retention-phase-v1"
  claim <- Wire.getText GeneralTextBytes 256
  claimSha <- Wire.getText GeneralTextBytes 64
  publication <- Wire.getBytes ProducerBundleBytes 1024
  ordinal <- Wire.getWord
  previous <- Wire.getText GeneralTextBytes 256
  previousSha <- Wire.getText GeneralTextBytes 64
  label <- Wire.getText GeneralTextBytes 64
  size <- Wire.getBytesLength WholePayloadBytes (toInteger Retain.maximumNativeRetentionPayloadBytes)
  pure (claim, claimSha, publication, ordinal, previous, previousSha, label, size)

decodeScope :: ByteString -> Either NativeRetentionEnvelopeError Retain.NativeAllocationScope
decodeScope bytes = do
  value <- codec (Wire.runParser parser bytes)
  _ <- rejected (Retain.mkNativeAllocationAddress value)
  pure value
 where
  parser = do
    Wire.expectList 8
    expectText "jitml-native-allocation-scope-v1"
    kind <- Wire.getText GeneralTextBytes 32
    context <- Wire.getText GeneralTextBytes 128
    sourceContext <- case kind of
      "supplied-scenario" -> pure (Retain.NativeSuppliedScenarioDigest context)
      "direct-local" -> pure (Retain.NativeDirectLocalAcquisition context)
      _ -> Wire.parserFailure (malformed "allocation context kind differs")
    row <- Wire.getText GeneralTextBytes 128
    algorithm <- Wire.getWord
    sourceSha <- Wire.getText GeneralTextBytes 64
    recipeSha <- Wire.getText GeneralTextBytes 64
    acquisition <- Wire.getText GeneralTextBytes 128
    pure
      ( Retain.NativeAllocationScope
          sourceContext
          row
          (Source.SourceStamp algorithm sourceSha)
          recipeSha
          acquisition
      )

decodePublication :: ByteString -> Either NativeRetentionEnvelopeError Retain.NativePublicationData
decodePublication bytes = do
  (resolutionBytes, kind, root, endpoint, fromBoot) <- codec (Wire.runParser parser bytes)
  resolution <- decodeResolution resolutionBytes
  require (canonicalSha root) "publication root identity is not canonical SHA256"
  case kind of
    "local" -> do
      require
        (Text.null endpoint && not fromBoot)
        "local publication has foreign endpoint or mounted-service claims"
      pure (Retain.NativeLocalPublication resolution root)
    "configured" -> do
      require (canonicalSha endpoint) "configured publication endpoint identity is not canonical SHA256"
      pure (Retain.NativeConfiguredPublication resolution root endpoint fromBoot)
    _ -> Left (NativeRetentionEnvelopeRejected "publication kind differs")
 where
  parser = do
    Wire.expectList 7
    expectText "jitml-native-retention-publication-v1"
    expectText "jitml-checkpoints"
    resolution <- Wire.getBytes ProducerBundleBytes 256
    kind <- Wire.getText GeneralTextBytes 32
    root <- Wire.getText GeneralTextBytes 64
    endpoint <- Wire.getText GeneralTextBytes 64
    fromBoot <- Wire.getBool
    pure (resolution, kind, root, endpoint, fromBoot)

decodeResolution
  :: ByteString -> Either NativeRetentionEnvelopeError Retain.NativePublicationResolution
decodeResolution bytes = do
  (kind, identity) <- codec (Wire.runParser parser bytes)
  case kind of
    "default" -> do
      require (Text.null identity) "default resolution has a foreign identity"
      pure Retain.NativeDefaultPublicationResolution
    "explicit-filesystem" -> do
      require (canonicalSha identity) "explicit filesystem resolution identity is not canonical SHA256"
      pure (Retain.NativeExplicitPublicationResolution identity)
    _ -> Left (NativeRetentionEnvelopeRejected "publication resolution kind differs")
 where
  parser = do
    Wire.expectList 2
    kind <- Wire.getText GeneralTextBytes 32
    identity <- Wire.getText GeneralTextBytes 64
    pure (kind, identity)

checkPhysicalSize
  :: Retain.NativeRetainedObjectData -> ByteString -> Either NativeRetentionEnvelopeError ()
checkPhysicalSize expected bytes = do
  require
    (toInteger (BS.length bytes) <= maximumNativeRetentionEnvelopeBytes)
    "retention outer object exceeds its payload-plus-header bound"
  require
    (toInteger (Retain.nativeRetainedObjectBytes expected) == toInteger (BS.length bytes))
    "retention outer object differs from its exact recorded byte count"
  require
    (canonicalSha (Retain.nativeRetainedObjectSha256 expected))
    "retention object SHA is not canonical lowercase SHA256"

checkPhysicalHashAndPublication
  :: Retain.NativeRetainedObjectData
  -> Retain.NativePublicationData
  -> ByteString
  -> Either NativeRetentionEnvelopeError ()
checkPhysicalHashAndPublication expected publication bytes = do
  require
    (sha256Hex bytes == Retain.nativeRetainedObjectSha256 expected)
    "retention physical bytes differ from recorded outer object SHA"
  require
    (publication == Retain.nativeRetainedObjectPublication expected)
    "retention publication differs from the recorded object scope"

exactPayload :: Int -> Word64 -> ByteString -> Either NativeRetentionEnvelopeError ByteString
exactPayload offset count bytes = do
  require
    ( offset <= maximumHeaderBytes
        && toInteger offset + toInteger count == toInteger (BS.length bytes)
    )
    "retention payload is truncated, trailing or outside its bounded header"
  pure (BS.drop offset bytes)

claimNamespace :: Text -> Either NativeRetentionEnvelopeError Text
claimNamespace key = case Text.splitOn "/" key of
  ["jitml-checkpoints", "native-rl-allocations-v1", scopeSha, "claim.cbor"]
    | canonicalSha scopeSha ->
        pure ("jitml-checkpoints/native-rl-allocations-v1/" <> scopeSha)
  _ -> Left (NativeRetentionEnvelopeRejected "phase claim key is not a canonical allocation address")

validPhaseLabel :: Text -> Bool
validPhaseLabel value =
  not (Text.null value)
    && Text.length value <= 64
    && Text.all (`elem` ("abcdefghijklmnopqrstuvwxyz0123456789.-" :: String)) value

canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

expectText :: Text -> Wire.Parser ()
expectText expected = do
  actual <- Wire.getText GeneralTextBytes 64
  unless (actual == expected) (Wire.parserFailure (malformed "retention envelope domain differs"))

codec :: Either CodecError a -> Either NativeRetentionEnvelopeError a
codec = mapLeft NativeRetentionEnvelopeCodec

rejected :: Either Text a -> Either NativeRetentionEnvelopeError a
rejected = mapLeft NativeRetentionEnvelopeRejected

require :: Bool -> Text -> Either NativeRetentionEnvelopeError ()
require condition message = unless condition (Left (NativeRetentionEnvelopeRejected message))

malformed :: Text -> CodecError
malformed = Malformed

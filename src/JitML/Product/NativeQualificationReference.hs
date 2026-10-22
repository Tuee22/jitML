{-# LANGUAGE OverloadedStrings #-}

-- | Closed ordinary reference DATA for a separately retained native receipt.
-- Parsing/refinement fetches nothing and authenticates no source, invocation,
-- run, training, assessment, publication, checkpoint or parent journal.
module JitML.Product.NativeQualificationReference
  ( NativeQualificationReference
  , NativeQualificationReferenceData (..)
  , NativeReferenceBinding (..)
  , nativeQualificationReceiptPrefix
  , nativeQualificationReferenceData
  , nativeQualificationReferenceBytes
  , refineNativeQualificationReference
  , decodeNativeQualificationReference
  , renderNativeQualificationReference
  , parseNativeQualificationReference
  , maximumNativeQualificationBytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64, Word8)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Product.SourceDigest qualified as Source
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

data NativeReferenceBinding = NativeReferenceDirect | NativeReferenceScenario
  deriving stock (Eq, Show)

-- Deliberately public ordinary recorded fields, never an execution capability.
data NativeQualificationReferenceData = NativeQualificationReferenceData
  { nativeReferenceRow :: !Text
  , nativeReferenceLane :: !Substrate
  , nativeReferencePlan :: !Text
  , nativeReferenceExperiment :: !Text
  , nativeReferenceManifest :: !Text
  , nativeReferenceSource :: !Source.SourceStamp
  , nativeReferenceExecutable :: !Text
  , nativeReferenceInvocation :: !Text
  , nativeReferenceCohort :: !Text
  , nativeReferenceArtifact :: !Text
  , nativeReferenceObjectKey :: !Text
  , nativeReferenceObjectBytes :: !Word64
  , nativeReferencePublication :: !Text
  , nativeReferenceBinding :: !NativeReferenceBinding
  , nativeReferenceAllocationKey :: !Text
  , nativeReferenceAllocationSha :: !Text
  , nativeReferenceAllocationBytes :: !Word64
  }
  deriving stock (Eq, Show)

data NativeQualificationReference
  = NativeQualificationReference
      !NativeQualificationReferenceData
      !ByteString
  deriving stock (Eq, Show)

nativeQualificationReferenceData :: NativeQualificationReference -> NativeQualificationReferenceData
nativeQualificationReferenceData (NativeQualificationReference actual _) = actual
nativeQualificationReferenceBytes :: NativeQualificationReference -> ByteString
nativeQualificationReferenceBytes (NativeQualificationReference _ actual) = actual

nativeQualificationReceiptPrefix :: Text
nativeQualificationReceiptPrefix = "native-qualification-receipt: "

maximumReferenceBytes, maximumNativeQualificationBytes :: Integer
maximumReferenceBytes = 16384
maximumNativeQualificationBytes = 4 * 1024 * 1024

refineNativeQualificationReference
  :: NativeQualificationReferenceData -> Either CodecError NativeQualificationReference
refineNativeQualificationReference value = do
  require (validText 128 (nativeReferenceRow value)) "native receipt reference row text differs"
  require
    (validExperiment (nativeReferenceExperiment value))
    "native receipt reference experiment namespace differs"
  mapM_
    (\sha -> require (canonicalSha sha) "native receipt reference SHA is not canonical lowercase SHA256")
    [ nativeReferencePlan value
    , nativeReferenceManifest value
    , Source.stampSha256 (nativeReferenceSource value)
    , nativeReferenceExecutable value
    , nativeReferenceInvocation value
    , nativeReferenceCohort value
    , nativeReferenceArtifact value
    , nativeReferencePublication value
    , nativeReferenceAllocationSha value
    ]
  require
    (Source.stampAlgorithm (nativeReferenceSource value) == Source.sourceDigestAlgorithm)
    "native receipt reference source algorithm differs"
  require
    ( nativeReferenceObjectKey value
        == "jitml-checkpoints/"
          <> nativeReferenceExperiment value
          <> "/artifacts/native-qualification/"
          <> nativeReferenceArtifact value
          <> ".cbor"
    )
    "native receipt reference detached key differs from exact experiment and content address"
  require
    ( nativeReferenceObjectBytes value > 0
        && toInteger (nativeReferenceObjectBytes value) <= maximumNativeQualificationBytes
    )
    "native receipt reference detached byte count exceeds the closed bound"
  require
    (validAllocationKey (nativeReferenceAllocationKey value))
    "native receipt reference allocation key differs from its exact canonical namespace"
  require
    ( nativeReferenceAllocationBytes value > 0
        && toInteger (nativeReferenceAllocationBytes value)
          <= toInteger Retain.maximumNativeRetentionPayloadBytes + 4096
    )
    "native receipt reference allocation byte count exceeds its envelope bound"
  let bytes = encoding value
  require
    (toInteger (BS.length bytes) <= maximumReferenceBytes)
    "native receipt reference exceeds16KiB"
  pure (NativeQualificationReference value bytes)

encoding :: NativeQualificationReferenceData -> ByteString
encoding value =
  Wire.encodeStrict
    ( CBOR.encodeListLen 20
        <> CBOR.encodeString "jitml-native-qualification-reference-v1"
        <> CBOR.encodeWord64 1
        <> CBOR.encodeString (nativeReferenceRow value)
        <> CBOR.encodeString (renderSubstrate (nativeReferenceLane value))
        <> CBOR.encodeString (nativeReferencePlan value)
        <> CBOR.encodeString (nativeReferenceExperiment value)
        <> CBOR.encodeString (nativeReferenceManifest value)
        <> CBOR.encodeWord64 (Source.stampAlgorithm (nativeReferenceSource value))
        <> CBOR.encodeString (Source.stampSha256 (nativeReferenceSource value))
        <> CBOR.encodeString (nativeReferenceExecutable value)
        <> CBOR.encodeString (nativeReferenceInvocation value)
        <> CBOR.encodeString (nativeReferenceCohort value)
        <> CBOR.encodeString (nativeReferenceArtifact value)
        <> CBOR.encodeString (nativeReferenceObjectKey value)
        <> CBOR.encodeWord64 (nativeReferenceObjectBytes value)
        <> CBOR.encodeString (nativeReferencePublication value)
        <> CBOR.encodeWord64
          (case nativeReferenceBinding value of NativeReferenceDirect -> 0; NativeReferenceScenario -> 1)
        <> CBOR.encodeString (nativeReferenceAllocationKey value)
        <> CBOR.encodeString (nativeReferenceAllocationSha value)
        <> CBOR.encodeWord64 (nativeReferenceAllocationBytes value)
    )

decodeNativeQualificationReference :: ByteString -> Either CodecError NativeQualificationReference
decodeNativeQualificationReference bytes = do
  require
    (toInteger (BS.length bytes) <= maximumReferenceBytes)
    "native receipt reference exceeds16KiB"
  value <- Wire.runParser parser bytes
  result <- refineNativeQualificationReference value
  require
    (nativeQualificationReferenceBytes result == bytes)
    "native receipt reference encoding is not canonical"
  pure result
 where
  parser = do
    Wire.expectList 20
    domain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    Wire.liftEither
      ( require
          (domain == "jitml-native-qualification-reference-v1" && version == 1)
          "native receipt reference domain/version differs"
      )
    row <- Wire.getText GeneralTextBytes 128
    laneText <- Wire.getText GeneralTextBytes 32
    lane <-
      maybe
        (Wire.parserFailure (Malformed "native receipt reference lane differs"))
        pure
        (parseSubstrate laneText)
    plan <- sha
    experiment <- Wire.getText GeneralTextBytes 1024
    manifest <- sha
    algorithm <- Wire.getWord
    source <- sha
    executable <- sha
    invocation <- sha
    cohort <- sha
    artifact <- sha
    key <- Wire.getText PathTextBytes 4096
    bytesCount <- Wire.getWord
    publication <- sha
    code <- Wire.getWord
    binding <- case code of
      0 -> pure NativeReferenceDirect
      1 -> pure NativeReferenceScenario
      _ -> Wire.parserFailure (Malformed "native receipt reference binding differs")
    allocation <- Wire.getText GeneralTextBytes 256
    allocationSha <- sha
    NativeQualificationReferenceData
      row
      lane
      plan
      experiment
      manifest
      (Source.SourceStamp algorithm source)
      executable
      invocation
      cohort
      artifact
      key
      bytesCount
      publication
      binding
      allocation
      allocationSha
      <$> Wire.getWord
  sha = Wire.getText GeneralTextBytes 64

renderNativeQualificationReference :: NativeQualificationReference -> Text
renderNativeQualificationReference reference =
  nativeQualificationReceiptPrefix
    <> Text.pack (concatMap pair (BS.unpack (nativeQualificationReferenceBytes reference)))
 where
  pair byte = [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]

-- Keep the canonical wire grammar explicitly restricted to ASCII digits.
{- HLINT ignore parseNativeQualificationReference "Use isDigit" -}
parseNativeQualificationReference :: Text -> Either CodecError NativeQualificationReference
parseNativeQualificationReference line = do
  body <-
    maybe
      (Left (Malformed "native receipt reference line prefix differs"))
      Right
      (Text.stripPrefix nativeQualificationReceiptPrefix line)
  require
    (toInteger (Text.length body) <= 2 * maximumReferenceBytes && even (Text.length body))
    "native receipt reference hex length differs"
  bytes <- BS.pack <$> pairs (Text.unpack body)
  decodeNativeQualificationReference bytes
 where
  pairs [] = Right []
  pairs (a : b : rest) = do
    x <- digit a
    y <- digit b
    ((x * 16 + y) :) <$> pairs rest
  pairs _ = Left (Malformed "native receipt reference hex is odd")
  digit :: Char -> Either CodecError Word8
  digit value
    | value >= '0' && value <= '9' = Right (fromIntegral (fromEnum value - fromEnum '0'))
    | value >= 'a' && value <= 'f' = Right (fromIntegral (fromEnum value - fromEnum 'a' + 10))
    | otherwise = Left (Malformed "native receipt reference hex is not lowercase canonical ASCII")

validText :: Int -> Text -> Bool
validText cap value =
  not (Text.null value)
    && Text.length value <= cap
    && Text.all (\c -> c >= '!' && c <= '~') value
validExperiment :: Text -> Bool
validExperiment value =
  validText 1024 value
    && value /= "."
    && value /= ".."
    && Text.all
      (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" :: String))
      value
canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value
validAllocationKey :: Text -> Bool
validAllocationKey value = case Text.splitOn "/" value of
  ["jitml-checkpoints", "native-rl-allocations-v1", sha, "claim.cbor"] -> canonicalSha sha
  _ -> False
require :: Bool -> Text -> Either CodecError ()
require condition detail = unless condition (Left (Malformed detail))

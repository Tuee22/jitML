{-# LANGUAGE OverloadedStrings #-}

-- | Closed ordinary metadata only. Decode/refinement performs no IO and
-- creates no completion, checked cohort, stage, execution or publication.
module JitML.Checkpoint.NativeQualificationReceiptData
  ( NativeQualificationReceiptData
  , NativeQualificationReceiptFields (..)
  , NativeReceiptAssociationData (..)
  , NativeReceiptReplayReference (..)
  , refineNativeQualificationReceiptData
  , decodeNativeQualificationReceiptData
  , nativeQualificationReceiptFields
  , nativeQualificationReceiptBytes
  , nativeQualificationReceiptPublicationDigest
  , maximumNativeQualificationReceiptBytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM, unless, zipWithM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Product.SourceDigest qualified as Source
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

data NativeReceiptAssociationData
  = NativeReceiptDirectData !Digest
  | NativeReceiptScenarioData !Text
  deriving stock (Eq, Show)

data NativeReceiptReplayReference = NativeReceiptReplayReference
  { nativeReceiptReplayStage :: !Replay.NativeReplayObjectStage
  , nativeReceiptReplayIndex :: !Word64
  , nativeReceiptReplayAttempt :: !Digest
  , nativeReceiptReplayObject :: !Retain.NativeRetainedObjectData
  }
  deriving stock (Eq, Show)

-- Public raw DATA fields. They confer no truth/current-source/Matrix claim.
data NativeQualificationReceiptFields = NativeQualificationReceiptFields
  { nativeReceiptRow :: !Text
  , nativeReceiptLane :: !Substrate
  , nativeReceiptWholePlan :: !Digest
  , nativeReceiptExperiment :: !Text
  , nativeReceiptCohortId :: !Digest
  , nativeReceiptCohortTransport :: !ByteString
  , nativeReceiptManifest :: !Digest
  , nativeReceiptCompletedTrainingBytes :: !ByteString
  , nativeReceiptPublication :: !Retain.NativePublicationData
  , nativeReceiptAssociation :: !NativeReceiptAssociationData
  , nativeReceiptObservedSource :: !(Maybe Source.SourceStamp)
  , nativeReceiptSuppliedSource :: !(Maybe Source.SourceStamp)
  , nativeReceiptAllocation :: !Retain.NativeRetainedObjectData
  , nativeReceiptPhases :: ![Retain.NativeRetainedObjectData]
  , nativeReceiptReplays :: ![NativeReceiptReplayReference]
  }
  deriving stock (Eq, Show)

data NativeQualificationReceiptData
  = NativeQualificationReceiptData
      !NativeQualificationReceiptFields
      !ByteString
  deriving stock (Eq, Show)

nativeQualificationReceiptFields
  :: NativeQualificationReceiptData -> NativeQualificationReceiptFields
nativeQualificationReceiptFields (NativeQualificationReceiptData value _) = value
nativeQualificationReceiptBytes :: NativeQualificationReceiptData -> ByteString
nativeQualificationReceiptBytes (NativeQualificationReceiptData _ value) = value
nativeQualificationReceiptPublicationDigest :: NativeQualificationReceiptData -> Text
nativeQualificationReceiptPublicationDigest = Retain.nativePublicationDigest . nativeReceiptPublication . nativeQualificationReceiptFields

maximumNativeQualificationReceiptBytes :: Integer
maximumNativeQualificationReceiptBytes = 4 * 1024 * 1024
domain :: Text
domain = "jitml-native-qualification-metadata-v1"
opaqueLimit :: Integer
opaqueLimit = 1024 * 1024
physicalLimit :: Word64
physicalLimit = fromIntegral Retain.maximumNativeRetentionPayloadBytes + 4096

refineNativeQualificationReceiptData
  :: NativeQualificationReceiptFields -> Either CodecError NativeQualificationReceiptData
refineNativeQualificationReceiptData fields = do
  -- Reject impossible spines before traversing/encoding any supplied list.
  phaseCount <- boundedLength AggregateSequenceElements 128 (nativeReceiptPhases fields)
  require (phaseCount > 0) "native metadata phase inventory is empty"
  replayCount <- boundedLength AggregateSequenceElements 11 (nativeReceiptReplays fields)
  require (replayCount == 11) "native metadata requires exactly eleven replay references"
  asciiText 128 (nativeReceiptRow fields)
  require
    (experimentText (nativeReceiptExperiment fields))
    "native metadata experiment namespace differs"
  opaque (nativeReceiptCohortTransport fields)
  opaque (nativeReceiptCompletedTrainingBytes fields)
  validatePublication (nativeReceiptPublication fields)
  case nativeReceiptAssociation fields of
    NativeReceiptDirectData _ -> pure ()
    NativeReceiptScenarioData text -> do
      textBound 8192 text
      require (not (Text.null text)) "native metadata scenario text is empty"
  mapM_ validateSource [nativeReceiptObservedSource fields, nativeReceiptSuppliedSource fields]
  require
    (isJust (nativeReceiptObservedSource fields) || isJust (nativeReceiptSuppliedSource fields))
    "native metadata omits both original source roles"
  let publication = nativeReceiptPublication fields
      allocation = nativeReceiptAllocation fields
  validateReference publication physicalLimit allocation
  scope <- case Text.splitOn "/" (Retain.nativeRetainedObjectKey allocation) of
    ["jitml-checkpoints", "native-rl-allocations-v1", identity, "claim.cbor"]
      | canonicalSha identity -> Right identity
    _ -> Left (Malformed "native metadata allocation address differs")
  mapM_ (validatePhase publication scope) (nativeReceiptPhases fields)
  uniqueKeys (nativeReceiptPhases fields)
  validateReplays fields
  -- Integer cost includes every inline occurrence; no sharing assumption.
  let total = encodedSize fields
  cap WholePayloadBytes maximumNativeQualificationReceiptBytes total
  let encoded = encodeFields fields
  require
    (toInteger (BS.length encoded) == total)
    "native metadata exact encoded-size accounting differs"
  pure (NativeQualificationReceiptData fields encoded)

validatePhase
  :: Retain.NativePublicationData -> Text -> Retain.NativeRetainedObjectData -> Either CodecError ()
validatePhase publication scope value = do
  validateReference publication physicalLimit value
  require
    ( Retain.nativeRetainedObjectKey value
        == "jitml-checkpoints/native-rl-allocations-v1/"
          <> scope
          <> "/phases/"
          <> Retain.nativeRetainedObjectSha256 value
          <> ".cbor"
    )
    "native metadata phase is outside its exact allocation scope or content address"

validateReplays :: NativeQualificationReceiptFields -> Either CodecError ()
validateReplays fields = do
  let entries = nativeReceiptReplays fields
      expected =
        concatMap
          (\index -> [(Replay.InitialModelReplay, index), (Replay.FinalModelReplay, index)])
          [0 .. 4]
          <> [(Replay.StoredFinalModelReplay, 0)]
  zipWithM_
    ( \(stage, index) value -> do
        require
          (nativeReceiptReplayStage value == stage && nativeReceiptReplayIndex value == index)
          "native metadata replay role or original index order differs"
        let kind = case stage of
              Replay.StoredFinalModelReplay -> Retain.NativeStoreLoadedReplayArtifact
              _ -> Retain.NativeEvaluationReplayArtifact
            object = nativeReceiptReplayObject value
        validateReference
          (nativeReceiptPublication fields)
          (Retain.maximumNativeDetachedArtifactBytes kind)
          object
        key <-
          either
            (const (Left (Malformed "native metadata detached replay address differs")))
            Right
            ( Retain.nativeDetachedArtifactKey
                kind
                (nativeReceiptExperiment fields)
                (Retain.nativeRetainedObjectSha256 object)
            )
        require (Retain.nativeRetainedObjectKey object == key) "native metadata replay detached key differs"
    )
    expected
    entries
  case entries of
    [a, b, c, d, e, f, g, h, i, j, k] -> do
      mapM_
        ( \(initial, final) ->
            require
              (nativeReceiptReplayAttempt initial == nativeReceiptReplayAttempt final)
              "native metadata replay pair attempts differ"
        )
        [(a, b), (c, d), (e, f), (g, h), (i, j)]
      let attempts = fmap nativeReceiptReplayAttempt [a, c, e, g, i]
      require
        (Set.size (Set.fromList attempts) == 5)
        "native metadata original five attempts are not distinct"
      require
        (nativeReceiptReplayAttempt k == nativeReceiptReplayAttempt a)
        "native metadata stored replay is not the serving attempt"
    _ -> Left (Malformed "native metadata replay count differs")
  uniqueKeys (fmap nativeReceiptReplayObject entries)

validateReference
  :: Retain.NativePublicationData -> Word64 -> Retain.NativeRetainedObjectData -> Either CodecError ()
validateReference publication maximumBytes value = do
  require
    (Retain.nativeRetainedObjectPublication value == publication)
    "native metadata reference publication differs before common-descriptor omission"
  textBound 4096 (Retain.nativeRetainedObjectKey value)
  require
    (canonicalSha (Retain.nativeRetainedObjectSha256 value))
    "native metadata reference SHA differs"
  require
    (Retain.nativeRetainedObjectBytes value > 0 && Retain.nativeRetainedObjectBytes value <= maximumBytes)
    "native metadata physical reference byte count differs"

uniqueKeys :: [Retain.NativeRetainedObjectData] -> Either CodecError ()
uniqueKeys values =
  require
    (Set.size (Set.fromList (fmap Retain.nativeRetainedObjectKey values)) == length values)
    "native metadata repeats a physical address"

validateSource :: Maybe Source.SourceStamp -> Either CodecError ()
validateSource Nothing = pure ()
validateSource (Just value) =
  require
    ( Source.stampAlgorithm value == Source.sourceDigestAlgorithm
        && canonicalSha (Source.stampSha256 value)
    )
    "native metadata source algorithm or SHA differs"

validatePublication :: Retain.NativePublicationData -> Either CodecError ()
validatePublication value = case value of
  Retain.NativeLocalPublication resolution root -> validateResolution resolution >> sha root
  Retain.NativeConfiguredPublication resolution root endpoint _ -> validateResolution resolution >> sha root >> sha endpoint
 where
  sha text = require (canonicalSha text) "native metadata publication identity differs"
  validateResolution Retain.NativeDefaultPublicationResolution = pure ()
  validateResolution (Retain.NativeExplicitPublicationResolution identity) = sha identity

decodeNativeQualificationReceiptData
  :: ByteString -> Either CodecError NativeQualificationReceiptData
decodeNativeQualificationReceiptData bytes = do
  cap WholePayloadBytes maximumNativeQualificationReceiptBytes (toInteger (BS.length bytes))
  fields <- Wire.runParser parser bytes
  actual <- refineNativeQualificationReceiptData fields
  unless
    (nativeQualificationReceiptBytes actual == bytes)
    (Left (NonCanonical "native metadata bytes differ from their canonical encoding"))
  pure actual
 where
  parser = do
    Wire.expectList 9
    actualDomain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    requireP (actualDomain == domain && version == 1) "native metadata domain/version differs"
    Wire.expectList 8
    row <- Wire.getText GeneralTextBytes 128
    laneText <- Wire.getText GeneralTextBytes 32
    lane <-
      maybe (Wire.parserFailure (Malformed "native metadata lane differs")) pure (parseSubstrate laneText)
    plan <- Wire.getDigest
    experiment <- Wire.getText GeneralTextBytes 1024
    cohort <- Wire.getDigest
    cohortBytes <- Wire.getBytes CohortTransportBytes opaqueLimit
    manifest <- Wire.getDigest
    completedBytes <- Wire.getBytes WholePayloadBytes opaqueLimit
    publication <- getPublication
    association <- getAssociation
    Wire.expectList 2
    observed <- getSource
    supplied <- getSource
    allocation <- getReference publication
    count <- Wire.getListLength AggregateSequenceElements 128
    requireP (count > 0) "native metadata phase inventory is empty"
    Wire.ensureMinimumItems (fromIntegral count) 37
    phases <- replicateM count (getReference publication)
    Wire.expectList 11
    Wire.ensureMinimumItems 11 75
    replays <- replicateM 11 (getReplay publication)
    pure
      ( NativeQualificationReceiptFields
          row
          lane
          plan
          experiment
          cohort
          cohortBytes
          manifest
          completedBytes
          publication
          association
          observed
          supplied
          allocation
          phases
          replays
      )

getReference :: Retain.NativePublicationData -> Wire.Parser Retain.NativeRetainedObjectData
getReference publication = do
  Wire.expectList 3
  key <- Wire.getText PathTextBytes 4096
  sha <- hexText . digestBytes <$> Wire.getDigest
  count <- Wire.getWord
  pure (Retain.NativeRetainedObjectData key sha count publication)
getReplay :: Retain.NativePublicationData -> Wire.Parser NativeReceiptReplayReference
getReplay publication = do
  Wire.expectList 4
  code <- Wire.getWord
  stage <- case code of
    0 -> pure Replay.InitialModelReplay
    1 -> pure Replay.FinalModelReplay
    2 -> pure Replay.StoredFinalModelReplay
    _ -> Wire.parserFailure (Malformed "native metadata replay role differs")
  index <- Wire.getWord
  requireP
    (index < 5 && (stage /= Replay.StoredFinalModelReplay || index == 0))
    "native metadata replay original index differs"
  attempt <- Wire.getDigest
  NativeReceiptReplayReference stage index attempt <$> getReference publication
getSource :: Wire.Parser (Maybe Source.SourceStamp)
getSource = do
  absent <- Wire.nextIsNull
  if absent
    then Wire.getNull >> pure Nothing
    else do
      Wire.expectList 2
      algorithm <- Wire.getWord
      sha <- hexText . digestBytes <$> Wire.getDigest
      pure (Just (Source.SourceStamp algorithm sha))
getAssociation :: Wire.Parser NativeReceiptAssociationData
getAssociation = do
  Wire.expectList 2
  code <- Wire.getWord
  case code of
    0 -> NativeReceiptDirectData <$> Wire.getDigest
    1 -> NativeReceiptScenarioData <$> Wire.getText InvocationTextBytes 8192
    _ -> Wire.parserFailure (Malformed "native metadata association tag differs")
getPublication :: Wire.Parser Retain.NativePublicationData
getPublication = do
  Wire.expectList 6
  resolutionCode <- Wire.getWord
  resolutionIdentity <- optionalDigest
  mode <- Wire.getWord
  root <- hexText . digestBytes <$> Wire.getDigest
  endpoint <- optionalDigest
  mounted <- Wire.getBool
  resolution <- case (resolutionCode, resolutionIdentity) of
    (0, Nothing) -> pure Retain.NativeDefaultPublicationResolution
    (1, Just value) -> pure (Retain.NativeExplicitPublicationResolution value)
    _ -> Wire.parserFailure (Malformed "native metadata publication resolution differs")
  case (mode, endpoint, mounted) of
    (0, Nothing, False) -> pure (Retain.NativeLocalPublication resolution root)
    (1, Just value, _) -> pure (Retain.NativeConfiguredPublication resolution root value mounted)
    _ -> Wire.parserFailure (Malformed "native metadata publication mode differs")
 where
  optionalDigest = do
    absent <- Wire.nextIsNull
    if absent then Wire.getNull >> pure Nothing else Just . hexText . digestBytes <$> Wire.getDigest

encodeFields :: NativeQualificationReceiptFields -> ByteString
encodeFields fields =
  Wire.encodeStrict
    ( CBOR.encodeListLen 9
        <> CBOR.encodeString domain
        <> CBOR.encodeWord64 1
        <> CBOR.encodeListLen 8
        <> CBOR.encodeString (nativeReceiptRow fields)
        <> CBOR.encodeString (renderSubstrate (nativeReceiptLane fields))
        <> dig (nativeReceiptWholePlan fields)
        <> CBOR.encodeString (nativeReceiptExperiment fields)
        <> dig (nativeReceiptCohortId fields)
        <> CBOR.encodeBytes (nativeReceiptCohortTransport fields)
        <> dig (nativeReceiptManifest fields)
        <> CBOR.encodeBytes (nativeReceiptCompletedTrainingBytes fields)
        <> encodePublication (nativeReceiptPublication fields)
        <> encodeAssociation (nativeReceiptAssociation fields)
        <> CBOR.encodeListLen 2
        <> encodeSource (nativeReceiptObservedSource fields)
        <> encodeSource (nativeReceiptSuppliedSource fields)
        <> encodeReference (nativeReceiptAllocation fields)
        <> CBOR.encodeListLen (fromIntegral (length (nativeReceiptPhases fields)))
        <> foldMap encodeReference (nativeReceiptPhases fields)
        <> CBOR.encodeListLen 11
        <> foldMap encodeReplay (nativeReceiptReplays fields)
    )
 where
  dig = CBOR.encodeBytes . digestBytes
  encodeAssociation (NativeReceiptDirectData value) = CBOR.encodeListLen 2 <> CBOR.encodeWord64 0 <> dig value
  encodeAssociation (NativeReceiptScenarioData value) = CBOR.encodeListLen 2 <> CBOR.encodeWord64 1 <> CBOR.encodeString value
  encodeSource Nothing = CBOR.encodeNull
  encodeSource (Just value) =
    CBOR.encodeListLen 2
      <> CBOR.encodeWord64 (Source.stampAlgorithm value)
      <> rawSha (Source.stampSha256 value)
  encodeReference value =
    CBOR.encodeListLen 3
      <> CBOR.encodeString (Retain.nativeRetainedObjectKey value)
      <> rawSha (Retain.nativeRetainedObjectSha256 value)
      <> CBOR.encodeWord64 (Retain.nativeRetainedObjectBytes value)
  encodeReplay value =
    CBOR.encodeListLen 4
      <> CBOR.encodeWord64 (stageCode (nativeReceiptReplayStage value))
      <> CBOR.encodeWord64 (nativeReceiptReplayIndex value)
      <> dig (nativeReceiptReplayAttempt value)
      <> encodeReference (nativeReceiptReplayObject value)

encodePublication :: Retain.NativePublicationData -> CBOR.Encoding
encodePublication publication =
  CBOR.encodeListLen 6 <> case publication of
    Retain.NativeLocalPublication resolution root ->
      encodeResolution resolution
        <> CBOR.encodeWord64 0
        <> rawSha root
        <> CBOR.encodeNull
        <> CBOR.encodeBool False
    Retain.NativeConfiguredPublication resolution root endpoint mounted ->
      encodeResolution resolution
        <> CBOR.encodeWord64 1
        <> rawSha root
        <> rawSha endpoint
        <> CBOR.encodeBool mounted
 where
  encodeResolution Retain.NativeDefaultPublicationResolution = CBOR.encodeWord64 0 <> CBOR.encodeNull
  encodeResolution (Retain.NativeExplicitPublicationResolution identity) = CBOR.encodeWord64 1 <> rawSha identity

-- Exact definite-CBOR cost of every inline occurrence, after field validation.
encodedSize :: NativeQualificationReceiptFields -> Integer
encodedSize fields =
  1
    + textSize domain
    + 1
    + 1
    + textSize (nativeReceiptRow fields)
    + textSize (renderSubstrate (nativeReceiptLane fields))
    + 34
    + textSize (nativeReceiptExperiment fields)
    + 34
    + bytesSize (nativeReceiptCohortTransport fields)
    + 34
    + bytesSize (nativeReceiptCompletedTrainingBytes fields)
    + publicationSize (nativeReceiptPublication fields)
    + associationSize (nativeReceiptAssociation fields)
    + 1
    + sourceSize (nativeReceiptObservedSource fields)
    + sourceSize (nativeReceiptSuppliedSource fields)
    + referenceSize (nativeReceiptAllocation fields)
    + header (fromIntegral (length (nativeReceiptPhases fields)))
    + sum (fmap referenceSize (nativeReceiptPhases fields))
    + 1
    + sum (fmap replaySize (nativeReceiptReplays fields))
 where
  associationSize (NativeReceiptDirectData _) = 1 + 1 + 34
  associationSize (NativeReceiptScenarioData value) = 1 + 1 + textSize value
  sourceSize Nothing = 1
  sourceSize (Just value) = 1 + header (Source.stampAlgorithm value) + 34
  referenceSize value =
    1
      + textSize (Retain.nativeRetainedObjectKey value)
      + 34
      + header (Retain.nativeRetainedObjectBytes value)
  replaySize value =
    1
      + header (stageCode (nativeReceiptReplayStage value))
      + header (nativeReceiptReplayIndex value)
      + 34
      + referenceSize (nativeReceiptReplayObject value)
  publicationSize value =
    1 + case value of
      Retain.NativeLocalPublication resolution _ -> resolutionSize resolution + 1 + 34 + 1 + 1
      Retain.NativeConfiguredPublication resolution _ _ _ -> resolutionSize resolution + 1 + 34 + 34 + 1
  resolutionSize Retain.NativeDefaultPublicationResolution = 1 + 1
  resolutionSize (Retain.NativeExplicitPublicationResolution _) = 1 + 34

stageCode :: Replay.NativeReplayObjectStage -> Word64
stageCode stage = case stage of
  Replay.InitialModelReplay -> 0
  Replay.FinalModelReplay -> 1
  Replay.StoredFinalModelReplay -> 2
rawSha :: Text -> CBOR.Encoding
rawSha = CBOR.encodeBytes . BS.pack . pairs . Text.unpack
 where
  pairs (a : b : rest) = (digit a * 16 + digit b) : pairs rest
  pairs _ = [] -- Only prevalidated64-digit SHA values enter the encoder.
  digit c
    | c <= '9' = fromIntegral (fromEnum c - fromEnum '0')
    | otherwise = fromIntegral (fromEnum c - fromEnum 'a' + 10)
hexText :: ByteString -> Text
hexText =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value
experimentText :: Text -> Bool
experimentText value =
  not (Text.null value)
    && Text.length value <= 1024
    && value /= "."
    && value /= ".."
    && Text.all
      (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" :: String))
      value
asciiText :: Int -> Text -> Either CodecError ()
asciiText maximumBytes value =
  require
    ( not (Text.null value)
        && Text.length value <= maximumBytes
        && Text.all (\c -> c >= '!' && c <= '~') value
    )
    "native metadata ASCII text differs"
textBound :: Integer -> Text -> Either CodecError ()
textBound maximumBytes value = do
  cap GeneralTextBytes maximumBytes (toInteger (Text.length value))
  cap GeneralTextBytes maximumBytes (toInteger (BS.length (UTF8.encodeUtf8 value)))
opaque :: ByteString -> Either CodecError ()
opaque value = do
  require (not (BS.null value)) "native metadata opaque encoding is empty"
  cap WholePayloadBytes opaqueLimit (toInteger (BS.length value))
textSize :: Text -> Integer
textSize = bytesSize . UTF8.encodeUtf8
bytesSize :: ByteString -> Integer
bytesSize value = header (fromIntegral (BS.length value)) + toInteger (BS.length value)
header :: Word64 -> Integer
header value
  | value < 24 = 1
  | value <= 0xff = 2
  | value <= 0xffff = 3
  | value <= 0xffffffff = 5
  | otherwise = 9
cap :: Resource -> Integer -> Integer -> Either CodecError ()
cap resource maximumBytes actual = unless (actual <= maximumBytes) (Left (ResourceExceeded resource maximumBytes actual))
require :: Bool -> Text -> Either CodecError ()
require condition detail = unless condition (Left (Malformed detail))
requireP :: Bool -> Text -> Wire.Parser ()
requireP condition detail = unless condition (Wire.parserFailure (Malformed detail))

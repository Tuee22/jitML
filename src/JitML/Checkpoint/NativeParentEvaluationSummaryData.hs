{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary historical summary DATA only. A decoded summary proves no
-- evaluation, source, process, device, admission or qualification. Its use in
-- a journal additionally requires authentication of the ORIGINAL owned parent
-- and independent admission of the complete physical object closure.
module JitML.Checkpoint.NativeParentEvaluationSummaryData
  ( NativeParentEvaluationSummaryData (..)
  , NativeParentEvaluationMatchData (..)
  , refineNativeParentEvaluationSummaryData
  , encodeNativeParentEvaluationSummaryData
  , decodeNativeParentEvaluationSummaryData
  , checkNativeParentEvaluationSummaryData
  , maximumNativeParentEvaluationSummaryBytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM, unless, zipWithM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Product.DeviceWitness qualified as Witness

data NativeParentEvaluationMatchData = NativeParentEvaluationMatchData
  { parentSummaryOrdinal :: !Word64
  , parentSummaryStage :: !Replay.NativeReplayObjectStage
  , parentSummaryIndex :: !Word64
  , parentSummaryExpectedRoot :: !Digest
  , parentSummaryActualRoot :: !Digest
  , parentSummaryDevice :: !(Maybe Witness.RawDeviceExecutionWitness)
  }
  deriving stock (Eq, Show)

data NativeParentEvaluationSummaryData = NativeParentEvaluationSummaryData
  { parentSummaryArenaReference :: !(Maybe Digest)
  , parentSummaryMatches :: ![NativeParentEvaluationMatchData]
  }
  deriving stock (Eq, Show)

maximumNativeParentEvaluationSummaryBytes :: Integer
maximumNativeParentEvaluationSummaryBytes = 65536

refineNativeParentEvaluationSummaryData
  :: NativeParentEvaluationSummaryData -> Either CodecError NativeParentEvaluationSummaryData
refineNativeParentEvaluationSummaryData value = do
  count <- boundedLength AggregateSequenceElements 11 (parentSummaryMatches value)
  require (count == 11) "parent evaluation summary requires exactly eleven original matches"
  zipWithM_ one [0 .. 10] (parentSummaryMatches value)
  require
    (toInteger (BS.length (encodeUnchecked value)) <= maximumNativeParentEvaluationSummaryBytes)
    "parent evaluation summary exceeds64KiB"
  pure value
 where
  one ordinal actual = do
    let (stage, index) = expectedPosition ordinal
    require
      ( parentSummaryOrdinal actual == ordinal
          && parentSummaryStage actual == stage
          && parentSummaryIndex actual == index
      )
      "parent evaluation summary ordinal stage or original index differs"
    require
      (parentSummaryExpectedRoot actual == parentSummaryActualRoot actual)
      "parent evaluation summary actual root differs from original expected root"
    case parentSummaryDevice actual of
      Nothing -> pure ()
      Just raw -> do
        boundedText 32 (Witness.rawWitnessSubstrate raw)
        boundedText 256 (Witness.rawWitnessBackend raw)
        boundedText 64 (Witness.rawWitnessKernelHash raw)
        boundedText 4096 (Witness.rawWitnessArtifactPath raw)
        boundedText 64 (Witness.rawWitnessArtifactSha256 raw)
        boundedText 256 (Witness.rawWitnessExecutedIdentity raw)
        _ <- mapLeft Malformed (Witness.refineRawDeviceExecutionWitness raw)
        pure ()

-- All expected arguments are deliberately ordinary DATA. Only the higher
-- authenticated journal boundary may use this comparison for admission.
checkNativeParentEvaluationSummaryData
  :: [Replay.NativeReplayObjectData]
  -> [Maybe Witness.RawDeviceExecutionWitness]
  -> Maybe Digest
  -> NativeParentEvaluationSummaryData
  -> Either CodecError ()
checkNativeParentEvaluationSummaryData replays devices reference summary = do
  _ <- refineNativeParentEvaluationSummaryData summary
  replayCount <- boundedLength AggregateSequenceElements 11 replays
  deviceCount <- boundedLength AggregateSequenceElements 11 devices
  require
    (replayCount == 11 && deviceCount == 11)
    "parent summary comparison requires all eleven original replay and device records"
  require
    (parentSummaryArenaReference summary == reference)
    "parent summary original arena reference differs"
  zipWithM_ one (zip replays devices) (parentSummaryMatches summary)
 where
  one (replay, device) actual =
    require
      ( parentSummaryStage actual == Replay.nativeReplayObjectStage replay
          && parentSummaryIndex actual == Replay.nativeReplayObjectIndex replay
          && parentSummaryExpectedRoot actual == Replay.nativeReplayObjectRoot replay
          && parentSummaryActualRoot actual == Replay.nativeReplayObjectRoot replay
          && parentSummaryDevice actual == device
      )
      "parent summary differs from complete original replay root stage index or all device fields"

encodeNativeParentEvaluationSummaryData
  :: NativeParentEvaluationSummaryData -> Either CodecError ByteString
encodeNativeParentEvaluationSummaryData value = do
  checked <- refineNativeParentEvaluationSummaryData value
  pure (encodeUnchecked checked)

-- Private builder: only refinement after bounded complete shape/text checks,
-- or decoding after that refinement, may call this function.
encodeUnchecked :: NativeParentEvaluationSummaryData -> ByteString
encodeUnchecked value =
  Wire.encodeStrict
    ( CBOR.encodeListLen 4
        <> CBOR.encodeString "jitml-native-parent-evaluation-summary-v1"
        <> CBOR.encodeWord 1
        <> maybe CBOR.encodeNull digest (parentSummaryArenaReference value)
        <> CBOR.encodeListLen (fromIntegral (length (parentSummaryMatches value)))
        <> foldMap item (parentSummaryMatches value)
    )
 where
  digest = CBOR.encodeBytes . digestBytes
  item actual =
    CBOR.encodeListLen 6
      <> CBOR.encodeWord64 (parentSummaryOrdinal actual)
      <> CBOR.encodeWord64 (stageCode (parentSummaryStage actual))
      <> CBOR.encodeWord64 (parentSummaryIndex actual)
      <> digest (parentSummaryExpectedRoot actual)
      <> digest (parentSummaryActualRoot actual)
      <> maybe CBOR.encodeNull device (parentSummaryDevice actual)
  device raw =
    CBOR.encodeListLen 6
      <> foldMap
        CBOR.encodeString
        [ Witness.rawWitnessSubstrate raw
        , Witness.rawWitnessBackend raw
        , Witness.rawWitnessKernelHash raw
        , Witness.rawWitnessArtifactPath raw
        , Witness.rawWitnessArtifactSha256 raw
        , Witness.rawWitnessExecutedIdentity raw
        ]

decodeNativeParentEvaluationSummaryData
  :: ByteString -> Either CodecError NativeParentEvaluationSummaryData
decodeNativeParentEvaluationSummaryData bytes = do
  require
    (toInteger (BS.length bytes) <= maximumNativeParentEvaluationSummaryBytes)
    "parent evaluation summary exceeds64KiB"
  value <- Wire.runParser parser bytes >>= refineNativeParentEvaluationSummaryData
  require
    (encodeUnchecked value == bytes)
    "parent evaluation summary encoding is not canonical"
  pure value
 where
  parser = do
    Wire.expectList 4
    domain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    Wire.liftEither
      ( require
          (domain == "jitml-native-parent-evaluation-summary-v1" && version == 1)
          "parent evaluation summary domain/version differs"
      )
    reference <- optional Wire.getDigest
    Wire.expectList 11
    NativeParentEvaluationSummaryData reference <$> replicateM 11 item
  item = do
    Wire.expectList 6
    ordinal <- Wire.getWord
    stage <- Wire.getWord >>= Wire.liftEither . stageFromCode
    index <- Wire.getWord
    expected <- Wire.getDigest
    actual <- Wire.getDigest
    device <- optional $ do
      Wire.expectList 6
      Witness.RawDeviceExecutionWitness
        <$> Wire.getText GeneralTextBytes 32
        <*> Wire.getText GeneralTextBytes 256
        <*> Wire.getText GeneralTextBytes 64
        <*> Wire.getText PathTextBytes 4096
        <*> Wire.getText GeneralTextBytes 64
        <*> Wire.getText GeneralTextBytes 256
    pure (NativeParentEvaluationMatchData ordinal stage index expected actual device)
  optional action = do
    absent <- Wire.nextIsNull
    if absent then Wire.getNull >> pure Nothing else Just <$> action

stageCode :: Replay.NativeReplayObjectStage -> Word64
stageCode Replay.InitialModelReplay = 0
stageCode Replay.FinalModelReplay = 1
stageCode Replay.StoredFinalModelReplay = 2

stageFromCode :: Word64 -> Either CodecError Replay.NativeReplayObjectStage
stageFromCode 0 = Right Replay.InitialModelReplay
stageFromCode 1 = Right Replay.FinalModelReplay
stageFromCode 2 = Right Replay.StoredFinalModelReplay
stageFromCode _ = Left (Malformed "parent evaluation summary stage differs")

expectedPosition :: Word64 -> (Replay.NativeReplayObjectStage, Word64)
expectedPosition ordinal
  | ordinal < 10 =
      (if even ordinal then Replay.InitialModelReplay else Replay.FinalModelReplay, ordinal `div` 2)
  | otherwise = (Replay.StoredFinalModelReplay, 0)

boundedText :: Integer -> Text -> Either CodecError ()
boundedText cap value =
  require
    ( not (Text.null value)
        && toInteger (Text.length value) <= cap
        && toInteger (BS.length (UTF8.encodeUtf8 value)) <= cap
    )
    "parent evaluation summary witness text is empty or exceeds its byte limit"

require :: Bool -> Text -> Either CodecError ()
require condition detail = unless condition (Left (Malformed detail))

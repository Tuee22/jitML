{-# LANGUAGE OverloadedStrings #-}

-- | Bounded ordinary selected review DATA. No decoding operation grants review,
-- execution, admission or qualification authority.
module JitML.Product.CriterionReviewData
  ( CriterionReviewScope (..)
  , CriterionReviewIdentityData (..)
  , CriterionReviewSelectionData (..)
  , CriterionReviewReceiptData (..)
  , criterionReviewSelectionPath
  , criterionReviewScopeText
  , criterionReviewIdentityTuple
  , refineCriterionReviewIdentityData
  , encodeCriterionReviewIdentityData
  , decodeCriterionReviewIdentityData
  , encodeCriterionReviewSelectionData
  , decodeCriterionReviewSelectionData
  , encodeCriterionReviewReceiptData
  , decodeCriterionReviewReceiptData
  , renderCriterionReviewIdentityData
  , parseCriterionReviewIdentityData
  , criterionReviewReceiptContractsSha256
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isControl, ord)
import Data.Either.Combinators (mapLeft)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
  ( CodecError (Malformed)
  , Resource (AggregateSequenceElements, GeneralTextBytes, PathTextBytes)
  , boundedLength
  )
import JitML.Product.LaneRegistrationData (LaneRowContractData (..), SelectedLaneFileData (..))
import JitML.Product.LaneRegistrationData qualified as Registration
import JitML.Product.SourceDigest (SourceStamp (..), sourceDigestAlgorithm)
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import System.FilePath (isRelative, normalise, splitDirectories)

data CriterionReviewScope = SupervisedCriterionReview | NativeCriterionReview
  deriving stock (Eq, Show)
data CriterionReviewIdentityData = CriterionReviewIdentityData
  { criterionReviewScope :: !CriterionReviewScope
  , criterionReviewSubstrate :: !Substrate
  , criterionReviewSource :: !SourceStamp
  , criterionReviewSelection :: !SelectedLaneFileData
  , criterionReviewReceipt :: !SelectedLaneFileData
  , criterionReviewContractSetSha256 :: !Text
  }
  deriving stock (Eq, Show)
data CriterionReviewSelectionData = CriterionReviewSelectionData
  { reviewSelectionScope :: !CriterionReviewScope
  , reviewSelectionSubstrate :: !Substrate
  , reviewSelectionSource :: !SourceStamp
  , reviewSelectionReceipt :: !SelectedLaneFileData
  }
  deriving stock (Eq, Show)
data CriterionReviewReceiptData = CriterionReviewReceiptData
  { reviewReceiptScope :: !CriterionReviewScope
  , reviewReceiptSubstrate :: !Substrate
  , reviewReceiptSource :: !SourceStamp
  , reviewReceiptRows :: ![LaneRowContractData]
  , reviewReceiptArtifacts :: ![SelectedLaneFileData]
  }
  deriving stock (Eq, Show)

criterionReviewScopeText :: CriterionReviewScope -> Text
criterionReviewScopeText SupervisedCriterionReview = "supervised"
criterionReviewScopeText NativeCriterionReview = "native"
reviewRoot :: SourceStamp -> Substrate -> CriterionReviewScope -> Text
reviewRoot source lane scope =
  "DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-validation/criterion-reviews/"
    <> stampSha256 source
    <> "/"
    <> renderSubstrate lane
    <> "/"
    <> criterionReviewScopeText scope
    <> "/"
criterionReviewSelectionPath :: SourceStamp -> Substrate -> CriterionReviewScope -> FilePath
criterionReviewSelectionPath source lane scope = Text.unpack (reviewRoot source lane scope <> "selection.cbor")
criterionReviewIdentityTuple :: CriterionReviewIdentityData -> (Text, Text, Text)
criterionReviewIdentityTuple value =
  ( selectedLaneFileSha256 (criterionReviewSelection value)
  , selectedLaneFileSha256 (criterionReviewReceipt value)
  , criterionReviewContractSetSha256 value
  )

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
sha :: Text -> Either Text ()
sha value =
  require
    (Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value)
    "criterion review SHA256 is not canonical lowercase64"
sourceCheck :: SourceStamp -> Either Text ()
sourceCheck value = do
  require (stampAlgorithm value == sourceDigestAlgorithm) "criterion review source algorithm differs"
  sha (stampSha256 value)
fileCheck
  :: Integer
  -> SourceStamp
  -> Substrate
  -> CriterionReviewScope
  -> SelectedLaneFileData
  -> Either Text ()
fileCheck cap source lane scope value = do
  let path = selectedLaneFilePath value
      raw = Text.unpack path
  require (Text.length path <= 4096) "criterion review path exceeds character cap"
  require (BS.length (UTF8.encodeUtf8 path) <= 4096) "criterion review path exceeds byte cap"
  require
    (Text.all (\c -> not (isControl c) && not (ord c >= 0xd800 && ord c <= 0xdfff)) path)
    "criterion review path contains non-scalar or control character"
  require
    (isRelative raw && normalise raw == raw && all (`notElem` [".", "..", ""]) (splitDirectories raw))
    "criterion review path is not canonical relative DATA"
  require
    (reviewRoot source lane scope `Text.isPrefixOf` path)
    "criterion review file is outside exact source lane scope subtree"
  sha (selectedLaneFileSha256 value)
  require
    (selectedLaneFileBytes value > 0 && toInteger (selectedLaneFileBytes value) <= cap)
    "criterion review file byte count exceeds its role cap"

refineCriterionReviewIdentityData
  :: CriterionReviewIdentityData -> Either Text CriterionReviewIdentityData
refineCriterionReviewIdentityData value = do
  let source = criterionReviewSource value
      lane = criterionReviewSubstrate value
      scope = criterionReviewScope value
  sourceCheck source
  fileCheck 16384 source lane scope (criterionReviewSelection value)
  require
    ( selectedLaneFilePath (criterionReviewSelection value)
        == Text.pack (criterionReviewSelectionPath source lane scope)
    )
    "criterion review selection path differs from fixed path"
  fileCheck 65536 source lane scope (criterionReviewReceipt value)
  require
    ( selectedLaneFilePath (criterionReviewSelection value)
        /= selectedLaneFilePath (criterionReviewReceipt value)
    )
    "criterion review selection cannot refer to itself as receipt"
  sha (criterionReviewContractSetSha256 value)
  pure value
selectionCheck :: CriterionReviewSelectionData -> Either Text ()
selectionCheck value = do
  sourceCheck (reviewSelectionSource value)
  fileCheck
    65536
    (reviewSelectionSource value)
    (reviewSelectionSubstrate value)
    (reviewSelectionScope value)
    (reviewSelectionReceipt value)
  require
    ( selectedLaneFilePath (reviewSelectionReceipt value)
        /= Text.pack
          ( criterionReviewSelectionPath
              (reviewSelectionSource value)
              (reviewSelectionSubstrate value)
              (reviewSelectionScope value)
          )
    )
    "criterion review selection receipt is circular"
criterionReviewReceiptContractsSha256 :: CriterionReviewReceiptData -> Either Text Text
criterionReviewReceiptContractsSha256 = mapLeft (Text.pack . show) . Registration.laneRowContractsSha256 . reviewReceiptRows
receiptCheck :: CriterionReviewReceiptData -> Either Text ()
receiptCheck value = do
  sourceCheck (reviewReceiptSource value)
  _ <- criterionReviewReceiptContractsSha256 value
  count <-
    mapLeft
      (Text.pack . show)
      (boundedLength AggregateSequenceElements 16 (reviewReceiptArtifacts value))
  require (count > 0) "criterion review requires retained independent review artifacts"
  mapM_
    ( fileCheck
        (4 * 1024 * 1024)
        (reviewReceiptSource value)
        (reviewReceiptSubstrate value)
        (reviewReceiptScope value)
    )
    (reviewReceiptArtifacts value)
  let refs = reviewReceiptArtifacts value
  require
    (length (nub (map selectedLaneFilePath refs)) == length refs)
    "criterion review duplicates an artifact path"
  require
    (sum (map (toInteger . selectedLaneFileBytes) refs) <= 16 * 1024 * 1024)
    "criterion review artifact aggregate exceeds16MiB"
  require
    ( all
        ( ( /=
              Text.pack
                ( criterionReviewSelectionPath
                    (reviewReceiptSource value)
                    (reviewReceiptSubstrate value)
                    (reviewReceiptScope value)
                )
          )
            . selectedLaneFilePath
        )
        refs
    )
    "criterion review artifact is selection itself"

fileEncoding :: SelectedLaneFileData -> CBOR.Encoding
fileEncoding value =
  CBOR.encodeListLen 3
    <> CBOR.encodeString (selectedLaneFilePath value)
    <> CBOR.encodeString (selectedLaneFileSha256 value)
    <> CBOR.encodeWord64 (selectedLaneFileBytes value)
common :: Text -> CriterionReviewScope -> Substrate -> SourceStamp -> CBOR.Encoding
common domain scope lane source =
  CBOR.encodeString domain
    <> CBOR.encodeWord 1
    <> CBOR.encodeString (criterionReviewScopeText scope)
    <> CBOR.encodeString (renderSubstrate lane)
    <> CBOR.encodeWord64 (stampAlgorithm source)
    <> CBOR.encodeString (stampSha256 source)
encodeCriterionReviewIdentityData :: CriterionReviewIdentityData -> Either Text ByteString
encodeCriterionReviewIdentityData value = do
  _ <- refineCriterionReviewIdentityData value
  pure
    ( Wire.encodeStrict
        ( CBOR.encodeListLen 9
            <> common
              "jitml-criterion-review-identity-v1"
              (criterionReviewScope value)
              (criterionReviewSubstrate value)
              (criterionReviewSource value)
            <> fileEncoding (criterionReviewSelection value)
            <> fileEncoding (criterionReviewReceipt value)
            <> CBOR.encodeString (criterionReviewContractSetSha256 value)
        )
    )
encodeCriterionReviewSelectionData :: CriterionReviewSelectionData -> Either Text ByteString
encodeCriterionReviewSelectionData value = do
  selectionCheck value
  pure
    ( Wire.encodeStrict
        ( CBOR.encodeListLen 7
            <> common
              "jitml-criterion-review-selection-v1"
              (reviewSelectionScope value)
              (reviewSelectionSubstrate value)
              (reviewSelectionSource value)
            <> fileEncoding (reviewSelectionReceipt value)
        )
    )
encodeCriterionReviewReceiptData :: CriterionReviewReceiptData -> Either Text ByteString
encodeCriterionReviewReceiptData value = do
  receiptCheck value
  let rows = reviewReceiptRows value
      artifacts = reviewReceiptArtifacts value
      encoded =
        Wire.encodeStrict
          ( CBOR.encodeListLen 10
              <> common
                "jitml-criterion-review-receipt-v1"
                (reviewReceiptScope value)
                (reviewReceiptSubstrate value)
                (reviewReceiptSource value)
              <> CBOR.encodeString
                ( case reviewReceiptScope value of
                    SupervisedCriterionReview -> "compact-supervised-v2"
                    NativeCriterionReview -> "finite-native-v1"
                )
              <> CBOR.encodeString "historical-calibrated-floors-remain-unproven;finite-canonical-claims-only"
              <> CBOR.encodeListLen 55
              <> foldMap row rows
              <> CBOR.encodeListLen (fromIntegral (length artifacts))
              <> foldMap fileEncoding artifacts
          )
  require (BS.length encoded <= 65536) "criterion review receipt exceeds64KiB"
  pure encoded
 where
  row contractRow =
    CBOR.encodeListLen 3
      <> CBOR.encodeString (laneRowId contractRow)
      <> CBOR.encodeString (laneRowPlanId contractRow)
      <> CBOR.encodeString (laneRowContractSha256 contractRow)

getCommon :: Text -> Wire.Parser (CriterionReviewScope, Substrate, SourceStamp)
getCommon expected = do
  domain <- Wire.getText GeneralTextBytes 64
  version <- Wire.getWord
  Wire.liftEither
    ( mapLeft
        Malformed
        (require (domain == expected && version == 1) "criterion review domain/version differs")
    )
  scopeText <- Wire.getText GeneralTextBytes 16
  scope <-
    Wire.liftEither
      ( case scopeText of
          "supervised" -> Right SupervisedCriterionReview
          "native" -> Right NativeCriterionReview
          _ -> Left (Malformed "unknown criterion review scope")
      )
  laneText <- Wire.getText GeneralTextBytes 32
  lane <-
    Wire.liftEither
      (maybe (Left (Malformed "unknown criterion review substrate")) Right (parseSubstrate laneText))
  source <- SourceStamp <$> Wire.getWord <*> Wire.getText GeneralTextBytes 64
  pure (scope, lane, source)
getFile :: Wire.Parser SelectedLaneFileData
getFile = do
  Wire.expectList 3
  SelectedLaneFileData
    <$> Wire.getText PathTextBytes 4096
    <*> Wire.getText GeneralTextBytes 64
    <*> Wire.getWord
checkedDecode
  :: Integer -> Wire.Parser a -> (a -> Either Text ByteString) -> ByteString -> Either Text a
checkedDecode cap parser encoder bytes = do
  require (toInteger (BS.length bytes) <= cap) "criterion review DATA exceeds role byte cap"
  value <- mapLeft (Text.pack . show) (Wire.runParser parser bytes)
  canonical <- encoder value
  require (canonical == bytes) "criterion review DATA is not canonical"
  pure value

decodeCriterionReviewIdentityData :: ByteString -> Either Text CriterionReviewIdentityData
decodeCriterionReviewIdentityData = checkedDecode 16384 parser encodeCriterionReviewIdentityData
 where
  parser = do
    Wire.expectList 9
    (scope, lane, source) <- getCommon "jitml-criterion-review-identity-v1"
    CriterionReviewIdentityData scope lane source
      <$> getFile
      <*> getFile
      <*> Wire.getText GeneralTextBytes 64
decodeCriterionReviewSelectionData :: ByteString -> Either Text CriterionReviewSelectionData
decodeCriterionReviewSelectionData = checkedDecode 16384 parser encodeCriterionReviewSelectionData
 where
  parser = do
    Wire.expectList 7
    (scope, lane, source) <- getCommon "jitml-criterion-review-selection-v1"
    CriterionReviewSelectionData scope lane source <$> getFile
decodeCriterionReviewReceiptData :: ByteString -> Either Text CriterionReviewReceiptData
decodeCriterionReviewReceiptData = checkedDecode 65536 parser encodeCriterionReviewReceiptData
 where
  parser = do
    Wire.expectList 10
    (scope, lane, source) <- getCommon "jitml-criterion-review-receipt-v1"
    policy <- Wire.getText GeneralTextBytes 64
    provenance <- Wire.getText GeneralTextBytes 128
    Wire.liftEither
      ( mapLeft
          Malformed
          ( require
              ( policy
                  == ( case scope of
                         SupervisedCriterionReview -> "compact-supervised-v2"
                         NativeCriterionReview -> "finite-native-v1"
                     )
                  && provenance == "historical-calibrated-floors-remain-unproven;finite-canonical-claims-only"
              )
              "criterion review policy or finite-claim provenance differs"
          )
      )
    Wire.expectList 55
    rows <-
      replicateM
        55
        ( Wire.expectList 3
            >> ( LaneRowContractData
                   <$> Wire.getText GeneralTextBytes 256
                   <*> Wire.getText GeneralTextBytes 64
                   <*> Wire.getText GeneralTextBytes 64
               )
        )
    count <- Wire.getListLength AggregateSequenceElements 16
    artifacts <- replicateM count getFile
    pure (CriterionReviewReceiptData scope lane source rows artifacts)

-- Explicitly ordinary environment transport; this is not a FILE observation.
renderCriterionReviewIdentityData :: CriterionReviewIdentityData -> Either Text Text
renderCriterionReviewIdentityData value = do
  bytes <- encodeCriterionReviewIdentityData value
  pure ("criterion-review-v1:" <> Text.pack (concatMap octet (BS.unpack bytes)))
 where
  digits = "0123456789abcdef"
  octet octetValue = [at (fromIntegral octetValue `div` 16), at (fromIntegral octetValue `mod` 16)]
  at index = case drop index digits of digitChar : _ -> digitChar; [] -> '0'
parseCriterionReviewIdentityData :: String -> Either Text CriterionReviewIdentityData
parseCriterionReviewIdentityData raw = do
  let prefix = take 32800 raw
  require (length prefix <= 32788) "criterion review handoff exceeds bounded character transport"
  body <-
    maybe
      (Left "criterion review handoff prefix differs")
      Right
      (Text.stripPrefix "criterion-review-v1:" (Text.pack prefix))
  bytes <- pairs (Text.unpack body)
  decodeCriterionReviewIdentityData (BS.pack bytes)
 where
  nibble value = case lookup value (zip ("0123456789abcdef" :: String) [0 .. 15]) of
    Nothing -> Left "criterion review handoff is not lowercase hex"
    Just code -> Right code
  pairs [] = Right []
  pairs (a : b : rest) = do x <- nibble a; y <- nibble b; more <- pairs rest; pure (16 * x + y : more)
  pairs _ = Left "criterion review handoff has an odd hex extent"

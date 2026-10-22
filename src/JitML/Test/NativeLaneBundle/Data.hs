{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary bounded portable DATA; no authentication or execution restoration.
module JitML.Test.NativeLaneBundle.Data
  ( NativeBundleObjectData (..)
  , NativeBundleRootData (..)
  , NativeBundleReferenceData (..)
  , maximumNativeBundleRootBytes
  , maximumNativeBundleObjects
  , refineNativeBundleRootData
  , encodeNativeBundleRootData
  , decodeNativeBundleRootData
  , nativeBundleRootReference
  , renderNativeBundleReferenceData
  , parseNativeBundleReferenceData
  , nativeBundleObjectBasename
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit, ord)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Text.Read qualified as TextRead
import Data.Word (Word64)
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Test.NativeScenarioJournalBindingData qualified as Binding
import JitML.Test.NativeScenarioReceiptData qualified as Receipt

data NativeBundleObjectData = NativeBundleObjectData
  { nativeBundleObjectKey :: !Text
  , nativeBundleObjectSha256 :: !Text
  , nativeBundleObjectBytes :: !Word64
  }
  deriving stock (Eq, Show)
data NativeBundleRootData = NativeBundleRootData
  { nativeBundleBinding :: !Binding.NativeScenarioJournalBindingData
  , nativeBundleReceipt :: !Receipt.NativeScenarioReceiptData
  , nativeBundleObjects :: ![NativeBundleObjectData]
  }
  deriving stock (Eq, Show)
data NativeBundleReferenceData = NativeBundleReferenceData
  { nativeBundleReferenceSha256 :: !Text
  , nativeBundleReferenceBytes :: !Word64
  }
  deriving stock (Eq, Show)

maximumNativeBundleRootBytes, maximumNativeBundleObjects :: Integer
maximumNativeBundleRootBytes = 1048576
maximumNativeBundleObjects = 163

refineNativeBundleRootData :: NativeBundleRootData -> Either CodecError NativeBundleRootData
refineNativeBundleRootData root = do
  count <-
    boundedLength AggregateSequenceElements maximumNativeBundleObjects (nativeBundleObjects root)
  require (count > 0) "native portable bundle has no physical objects"
  _ <- Receipt.refineNativeScenarioReceiptData (nativeBundleReceipt root)
  _ <- bindingFields (nativeBundleBinding root)
  mapM_ object (nativeBundleObjects root)
  increasing Nothing (nativeBundleObjects root)
  cost <- rootCost root
  require (cost <= maximumNativeBundleRootBytes) "native portable bundle root exceeds1MiB"
  pure root
 where
  object value = do
    boundedText 4096 (nativeBundleObjectKey value)
    require
      (safeObjectKey (nativeBundleObjectKey value))
      "native portable bundle object key is not canonical"
    require
      (canonicalSha (nativeBundleObjectSha256 value))
      "native portable bundle object SHA is not canonical"
  increasing _ [] = pure ()
  increasing previous (value : rest) = do
    require
      (maybe True (< nativeBundleObjectKey value) previous)
      "native portable bundle keys are not strictly ordered and unique"
    increasing (Just (nativeBundleObjectKey value)) rest

encodeNativeBundleRootData :: NativeBundleRootData -> Either CodecError ByteString
encodeNativeBundleRootData root = do
  actual <- refineNativeBundleRootData root
  receipt <- Receipt.encodeNativeScenarioReceiptData (nativeBundleReceipt actual)
  binding <- encodeBinding (nativeBundleBinding actual)
  pure
    ( Wire.encodeStrict
        ( CBOR.encodeListLen 5
            <> CBOR.encodeString domain
            <> CBOR.encodeWord 1
            <> binding
            <> CBOR.encodeBytes receipt
            <> CBOR.encodeListLen (fromIntegral (length (nativeBundleObjects actual)))
            <> foldMap encodeObject (nativeBundleObjects actual)
        )
    )

decodeNativeBundleRootData :: ByteString -> Either CodecError NativeBundleRootData
decodeNativeBundleRootData bytes = do
  require
    (toInteger (BS.length bytes) <= maximumNativeBundleRootBytes)
    "native portable bundle root exceeds1MiB"
  root <- Wire.runParser parser bytes >>= refineNativeBundleRootData
  canonical <- encodeNativeBundleRootData root
  require (canonical == bytes) "native portable bundle root is not canonical"
  pure root
 where
  parser = do
    Wire.expectList 5
    observedDomain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    Wire.liftEither
      ( require
          (observedDomain == domain && version == 1)
          "native portable bundle root domain/version differs"
      )
    binding <- parseBinding
    receipt <-
      Wire.getBytes WholePayloadBytes Receipt.maximumNativeScenarioReceiptBytes
        >>= Wire.liftEither . Receipt.decodeNativeScenarioReceiptData
    count <- Wire.getListLength AggregateSequenceElements maximumNativeBundleObjects
    objects <- replicateM count $ do
      Wire.expectList 3
      NativeBundleObjectData
        <$> Wire.getText PathTextBytes 4096
        <*> (hex <$> Wire.getBytes WholePayloadBytes 32)
        <*> Wire.getWord
    pure (NativeBundleRootData binding receipt objects)

nativeBundleRootReference :: NativeBundleRootData -> Either CodecError NativeBundleReferenceData
nativeBundleRootReference root = do
  bytes <- encodeNativeBundleRootData root
  pure (NativeBundleReferenceData (sha256Hex bytes) (fromIntegral (BS.length bytes)))

renderNativeBundleReferenceData :: NativeBundleReferenceData -> Either CodecError Text
renderNativeBundleReferenceData reference = do
  checkReference reference
  pure
    ( referencePrefix
        <> nativeBundleReferenceSha256 reference
        <> ":"
        <> Text.pack (show (nativeBundleReferenceBytes reference))
    )

parseNativeBundleReferenceData :: Text -> Either CodecError NativeBundleReferenceData
parseNativeBundleReferenceData text = do
  require (Text.length text <= 128) "native portable bundle reference is too long"
  body <-
    maybe
      (Left (Malformed "native portable bundle reference prefix differs"))
      Right
      (Text.stripPrefix referencePrefix text)
  case Text.splitOn ":" body of
    [sha, countText] -> do
      count <- case TextRead.decimal countText of
        Right (value, rest)
          | Text.null rest
              && value >= (0 :: Integer)
              && value <= toInteger (maxBound :: Word64) ->
              Right (fromInteger value)
        _ -> Left (Malformed "native portable bundle reference count is invalid")
      let value = NativeBundleReferenceData sha count
      checkReference value
      canonical <- renderNativeBundleReferenceData value
      require (canonical == text) "native portable bundle reference is not canonical"
      pure value
    _ -> Left (Malformed "native portable bundle reference shape differs")

-- Only checked SHA basenames enter IO. Object keys/original paths never
-- become destination path components.
nativeBundleObjectBasename :: Text -> Either CodecError FilePath
nativeBundleObjectBasename sha = do
  require (canonicalSha sha) "native portable bundle filename SHA is not canonical"
  pure (Text.unpack sha <> ".cbor")

checkReference :: NativeBundleReferenceData -> Either CodecError ()
checkReference reference = do
  require
    (canonicalSha (nativeBundleReferenceSha256 reference))
    "native portable bundle reference SHA is invalid"
  require
    ( nativeBundleReferenceBytes reference > 0
        && toInteger (nativeBundleReferenceBytes reference) <= maximumNativeBundleRootBytes
    )
    "native portable bundle reference byte count is outside its bound"

domain, referencePrefix :: Text
domain = "jitml-native-lane-bundle-v1"
referencePrefix = "native-lane-bundle-v1:"

encodeObject :: NativeBundleObjectData -> CBOR.Encoding
encodeObject value =
  CBOR.encodeListLen 3
    <> CBOR.encodeString (nativeBundleObjectKey value)
    <> CBOR.encodeBytes (shaBytes (nativeBundleObjectSha256 value))
    <> CBOR.encodeWord64 (nativeBundleObjectBytes value)

-- Fifteen texts, one Boolean and three unsigned sequence words. A bounded
-- path conversion precedes Text.pack even on hostile ordinary Strings.
bindingFields :: Binding.NativeScenarioJournalBindingData -> Either CodecError [Text]
bindingFields value = do
  path <- boundedPath (Binding.nativeScenarioBindingExecutablePath value)
  let fields =
        [ Binding.nativeScenarioBindingRowId value
        , Binding.nativeScenarioBindingRunId value
        , Binding.nativeScenarioBindingPlanId value
        , Binding.nativeScenarioBindingSubstrate value
        , path
        , Binding.nativeScenarioBindingExecutableSha256 value
        , Binding.nativeScenarioBindingInvocationDigest value
        , Binding.nativeScenarioBindingExperimentHash value
        , Binding.nativeScenarioBindingManifestSha256 value
        , Binding.nativeScenarioBindingCommand value
        , Binding.nativeScenarioBindingContractSha256 value
        , Binding.nativeScenarioBindingCheckpointScopeSha256 value
        , Binding.nativeScenarioBindingExecutionJournalReceipt value
        , Binding.nativeScenarioBindingExecutionJournalSha256 value
        , Binding.nativeScenarioBindingInferenceManifestSha256 value
        ]
  mapM_ (uncurry boundedText) (zip bindingTextCaps fields)
  let cost = 1 + sum (map textCost fields) + 1 + 3 * 9
  require (cost <= 65536) "native portable full semantic binding exceeds64KiB"
  pure fields

bindingTextCaps :: [Integer]
bindingTextCaps = [1024, 256, 64, 32, 4096, 64, 64, 1024, 64, 8192, 64, 64, 32768, 64, 64]

encodeBinding :: Binding.NativeScenarioJournalBindingData -> Either CodecError CBOR.Encoding
encodeBinding value = do
  fields <- bindingFields value
  pure
    ( CBOR.encodeListLen 19
        <> foldMap CBOR.encodeString fields
        <> CBOR.encodeBool (Binding.nativeScenarioBindingPreconditionRejected value)
        <> CBOR.encodeWord64 (Binding.nativeScenarioBindingPreconditionSequence value)
        <> CBOR.encodeWord64 (Binding.nativeScenarioBindingInferenceSequence value)
        <> CBOR.encodeWord64 (Binding.nativeScenarioBindingCompletionSequence value)
    )

parseBinding :: Wire.Parser Binding.NativeScenarioJournalBindingData
parseBinding = do
  Wire.expectList 19
  Binding.NativeScenarioJournalBindingData
    <$> text GeneralTextBytes 1024
    <*> text GeneralTextBytes 256
    <*> text GeneralTextBytes 64
    <*> text GeneralTextBytes 32
    <*> (Text.unpack <$> text PathTextBytes 4096)
    <*> text GeneralTextBytes 64
    <*> text GeneralTextBytes 64
    <*> text GeneralTextBytes 1024
    <*> text GeneralTextBytes 64
    <*> text InvocationTextBytes 8192
    <*> text GeneralTextBytes 64
    <*> text GeneralTextBytes 64
    <*> text DiagnosticTextBytes 32768
    <*> text GeneralTextBytes 64
    <*> text GeneralTextBytes 64
    <*> Wire.getBool
    <*> Wire.getWord
    <*> Wire.getWord
    <*> Wire.getWord
 where
  text = Wire.getText

rootCost :: NativeBundleRootData -> Either CodecError Integer
rootCost root = do
  fields <- bindingFields (nativeBundleBinding root)
  receipt <- Receipt.encodeNativeScenarioReceiptData (nativeBundleReceipt root)
  let bindingCost = 1 + sum (map textCost fields) + 1 + 3 * 9
      objectCost value = 1 + textCost (nativeBundleObjectKey value) + 34 + 9
  pure
    ( 1
        + textCost domain
        + 9
        + bindingCost
        + 9
        + toInteger (BS.length receipt)
        + 9
        + sum (map objectCost (nativeBundleObjects root))
    )

textCost :: Text -> Integer
textCost text = 9 + toInteger (BS.length (UTF8.encodeUtf8 text))

boundedText :: Integer -> Text -> Either CodecError ()
boundedText cap text =
  require
    (toInteger (BS.length (UTF8.encodeUtf8 (Text.take (fromInteger cap + 1) text))) <= cap)
    "native portable bundle text exceeds its UTF8 byte cap"

boundedPath :: FilePath -> Either CodecError Text
boundedPath path = do
  let prefix = take 4097 path
  require (length prefix <= 4096) "native portable binding path exceeds its character preflight"
  require
    (all (\c -> ord c < 0xd800 || ord c > 0xdfff) prefix)
    "native portable binding path contains a non-scalar character"
  let text = Text.pack prefix
  boundedText 4096 text
  pure text

safeObjectKey :: Text -> Bool
safeObjectKey key =
  not (Text.null key)
    && Text.all (\c -> c >= '!' && c <= '~' && fromEnum c /= 92) key
    && all (\part -> not (Text.null part) && part /= "." && part /= "..") (Text.splitOn "/" key)

canonicalSha :: Text -> Bool
canonicalSha value =
  Text.length value == 64
    && Text.all (\c -> c `elem` ("0123456789abcdef" :: String)) value

-- Called only after exact lowercase-hex refinement.
shaBytes :: Text -> ByteString
shaBytes = BS.pack . pairs . Text.unpack
 where
  pairs (a : b : rest) = fromIntegral (digit a * 16 + digit b) : pairs rest
  pairs _ = []
  digit c
    | isAsciiDecimalDigit c = fromEnum c - fromEnum '0'
    | otherwise = fromEnum c - fromEnum 'a' + 10

-- Preserve the ASCII-only wire alphabet; Unicode decimal digits are excluded.
isAsciiDecimalDigit :: Char -> Bool
isAsciiDecimalDigit value =
  let code = ord value
   in code >= 48 && code <= 57

hex :: ByteString -> Text
hex =
  Text.pack
    . concatMap
      ( \byte ->
          [intToDigit (div (fromIntegral byte) 16), intToDigit (mod (fromIntegral byte) 16)]
      )
    . BS.unpack

require :: Bool -> Text -> Either CodecError ()
require condition message = unless condition (Left (Malformed message))

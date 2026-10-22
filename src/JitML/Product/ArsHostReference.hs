{-# LANGUAGE OverloadedStrings #-}

-- | Canonical recorded reference only. Refinement/decoding establishes neither
-- execution, producer origin, physical checkpoint admission nor authentication.
module JitML.Product.ArsHostReference
  ( ArsHostReference
  , RawArsHostReference (..)
  , refineArsHostReference
  , arsHostReferenceToRaw
  , encodeArsHostReference
  , decodeArsHostReference
  , arsHostObjectKey
  , arsHostReferenceObjectKey
  , arsHostReferenceContentSha256
  , arsHostReferenceByteLength
  , arsHostReferenceContextSha256
  , arsHostReferencePlanId
  , arsHostReferenceLane
  , arsHostReferenceSourceSha256
  , arsHostReferenceExecutableSha256
  , arsHostReferenceInvocationSha256
  ) where

import Control.Monad (unless)
import Control.Monad.State.Strict (StateT (StateT), get, put, runStateT)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64, Word8)

import JitML.Plan.Plan (PlanId, planIdText, refinePlanIdText)
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- Deliberately public untrusted DTO; never a producer witness.
data RawArsHostReference = RawArsHostReference
  { rawArsHostReferenceObjectKey :: !Text
  , rawArsHostReferenceContentSha256 :: !Text
  , rawArsHostReferenceByteLength :: !Word64
  , rawArsHostReferenceContextSha256 :: !Text
  , rawArsHostReferencePlanId :: !Text
  , rawArsHostReferenceLane :: !Text
  , rawArsHostReferenceSourceSha256 :: !Text
  , rawArsHostReferenceExecutableSha256 :: !Text
  , rawArsHostReferenceInvocationSha256 :: !Text
  }
  deriving stock (Eq, Ord, Show)

-- Private fields prevent post-refinement record updates.
data ArsHostReference = ArsHostReference !RawArsHostReference !PlanId !Substrate !Digests
  deriving stock (Eq, Ord, Show)

data Digests = Digests !BS.ByteString !BS.ByteString !BS.ByteString !BS.ByteString !BS.ByteString
  deriving stock (Eq, Ord, Show)

arsHostReferenceToRaw :: ArsHostReference -> RawArsHostReference
arsHostReferenceToRaw (ArsHostReference raw _ _ _) = raw

arsHostReferenceObjectKey
  , arsHostReferenceContentSha256
  , arsHostReferenceContextSha256
  , arsHostReferenceSourceSha256
  , arsHostReferenceExecutableSha256
  , arsHostReferenceInvocationSha256
    :: ArsHostReference -> Text
arsHostReferenceObjectKey = rawArsHostReferenceObjectKey . arsHostReferenceToRaw
arsHostReferenceContentSha256 = rawArsHostReferenceContentSha256 . arsHostReferenceToRaw
arsHostReferenceContextSha256 = rawArsHostReferenceContextSha256 . arsHostReferenceToRaw
arsHostReferenceSourceSha256 = rawArsHostReferenceSourceSha256 . arsHostReferenceToRaw
arsHostReferenceExecutableSha256 = rawArsHostReferenceExecutableSha256 . arsHostReferenceToRaw
arsHostReferenceInvocationSha256 = rawArsHostReferenceInvocationSha256 . arsHostReferenceToRaw

arsHostReferenceByteLength :: ArsHostReference -> Word64
arsHostReferenceByteLength = rawArsHostReferenceByteLength . arsHostReferenceToRaw

arsHostReferencePlanId :: ArsHostReference -> PlanId
arsHostReferencePlanId (ArsHostReference _ plan _ _) = plan

arsHostReferenceLane :: ArsHostReference -> Substrate
arsHostReferenceLane (ArsHostReference _ _ lane _) = lane

arsHostObjectKey :: Text -> Text -> Either Text Text
arsHostObjectKey experiment contentSha = do
  -- One exact ASCII path component, including actual canonical names such as
  -- product-row-ARS.cartpole. Do not case-fold, normalize or decode escapes.
  -- General Plan IDs and slash-containing child namespaces remain unsupported.
  ensure
    ( not (Text.null experiment)
        && experiment /= "."
        && experiment /= ".."
        && Text.length experiment <= 1024
        && Text.all
          (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" :: String))
          experiment
    )
    "ARS host reference experiment namespace is not canonical"
  _ <- shaBytes "content" contentSha
  let key = "jitml-checkpoints/" <> experiment <> "/artifacts/ars-host-execution/" <> contentSha <> ".cbor"
  ensure
    (BS.length (UTF8.encodeUtf8 key) <= 1024)
    "ARS host reference object key exceeds its byte limit"
  pure key

refineArsHostReference :: RawArsHostReference -> Either Text ArsHostReference
refineArsHostReference raw = do
  plan <- refinePlanIdText (rawArsHostReferencePlanId raw)
  lane <-
    maybe
      (Left "ARS host reference lane is unknown")
      Right
      (parseSubstrate (rawArsHostReferenceLane raw))
  ensure
    (renderSubstrate lane == rawArsHostReferenceLane raw)
    "ARS host reference lane is not canonical"
  content <- shaBytes "content" (rawArsHostReferenceContentSha256 raw)
  context <- shaBytes "context" (rawArsHostReferenceContextSha256 raw)
  source <- shaBytes "source" (rawArsHostReferenceSourceSha256 raw)
  executable <- shaBytes "executable" (rawArsHostReferenceExecutableSha256 raw)
  invocation <- shaBytes "invocation" (rawArsHostReferenceInvocationSha256 raw)
  ensure
    (rawArsHostReferenceByteLength raw > 0 && rawArsHostReferenceByteLength raw <= 67108864)
    "ARS host reference byte length is outside its resource limit"
  ensure
    (Text.length (rawArsHostReferenceObjectKey raw) <= 1024)
    "ARS host reference object key exceeds its byte limit"
  experiment <- case Text.splitOn "/" (rawArsHostReferenceObjectKey raw) of
    ["jitml-checkpoints", value, "artifacts", "ars-host-execution", _] -> Right value
    _ -> Left "ARS host reference object key has the wrong structure"
  expected <- arsHostObjectKey experiment (rawArsHostReferenceContentSha256 raw)
  ensure
    (expected == rawArsHostReferenceObjectKey raw)
    "ARS host reference object key differs from its exact content address"
  pure (ArsHostReference raw plan lane (Digests content context source executable invocation))

encodeArsHostReference :: ArsHostReference -> BS.ByteString
encodeArsHostReference reference@(ArsHostReference _ _ _ (Digests content context source executable invocation)) =
  LBS.toStrict . B.toLazyByteString $
    header 4 11
      <> text "jitml-ars-host-reference"
      <> header 0 1
      <> text (arsHostReferenceObjectKey reference)
      <> bytes content
      <> header 0 (arsHostReferenceByteLength reference)
      <> bytes context
      <> text (planIdText (arsHostReferencePlanId reference))
      <> text (renderSubstrate (arsHostReferenceLane reference))
      <> bytes source
      <> bytes executable
      <> bytes invocation

decodeArsHostReference :: BS.ByteString -> Either Text ArsHostReference
decodeArsHostReference input = do
  ensure (BS.length input <= 8192) "ARS host reference input exceeds its byte limit"
  (raw, (_, offset)) <- runStateT parse (input, 0)
  ensure (offset == BS.length input) "ARS host reference has trailing bytes"
  reference <- refineArsHostReference raw
  ensure (encodeArsHostReference reference == input) "ARS host reference is not canonical CBOR"
  pure reference
 where
  parse = do
    expectHead 4 11
    domain <- readText 64
    unless (domain == "jitml-ars-host-reference") (reject "ARS host reference domain differs")
    expectHead 0 1
    RawArsHostReference
      <$> readText 1024
      <*> readDigest
      <*> readHead 0
      <*> readDigest
      <*> readText 256
      <*> readText 32
      <*> readDigest
      <*> readDigest
      <*> readDigest

ensure :: Bool -> Text -> Either Text ()
ensure condition message = unless condition (Left message)

shaBytes :: Text -> Text -> Either Text BS.ByteString
shaBytes label value = do
  ensure
    (Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value)
    ("ARS host reference " <> label <> " SHA-256 is not canonical")
  pure (BS.pack (pairs (Text.unpack value)))
 where
  pairs (a : b : rest) = (nibble a * 16 + nibble b) : pairs rest
  pairs _ = []
  nibble c = fromIntegral (fromEnum c - if c <= '9' then fromEnum '0' else fromEnum 'a' - 10)

hex :: BS.ByteString -> Text
hex =
  Text.pack
    . concatMap (\v -> [intToDigit (fromIntegral v `div` 16), intToDigit (fromIntegral v `mod` 16)])
    . BS.unpack

header :: Word8 -> Word64 -> B.Builder
header major value
  | value < 24 = B.word8 (major * 32 + fromIntegral value)
  | value <= 255 = B.word8 (major * 32 + 24) <> B.word8 (fromIntegral value)
  | value <= 65535 = B.word8 (major * 32 + 25) <> B.word16BE (fromIntegral value)
  | value <= 4294967295 = B.word8 (major * 32 + 26) <> B.word32BE (fromIntegral value)
  | otherwise = B.word8 (major * 32 + 27) <> B.word64BE value

bytes :: BS.ByteString -> B.Builder
bytes value = header 2 (fromIntegral (BS.length value)) <> B.byteString value

text :: Text -> B.Builder
text value =
  let encoded = UTF8.encodeUtf8 value
   in header 3 (fromIntegral (BS.length encoded)) <> B.byteString encoded

type Reader = StateT (BS.ByteString, Int) (Either Text)

checked :: Either Text a -> Reader a
checked result = StateT (\state -> fmap (,state) result)

reject :: Text -> Reader a
reject = checked . Left

takeBytes :: Word64 -> Reader BS.ByteString
takeBytes count = do
  (input, offset) <- get
  unless
    (toInteger count <= toInteger (BS.length input - offset))
    (reject "ARS host reference is truncated")
  let n = fromIntegral count
  put (input, offset + n)
  pure (BS.take n (BS.drop offset input))

readHead :: Word8 -> Reader Word64
readHead expected = do
  first <- BS.head <$> takeBytes 1
  unless (first `shiftR` 5 == expected) (reject "ARS host reference CBOR type differs")
  let additional = first .&. 31
  if additional < 24
    then pure (fromIntegral additional)
    else do
      (width, minimumValue) <- case additional of
        24 -> pure (1, 24)
        25 -> pure (2, 256)
        26 -> pure (4, 65536)
        27 -> pure (8, 4294967296)
        _ -> reject "ARS host reference indefinite or reserved CBOR header"
      value <- BS.foldl' (\acc byte -> (acc `shiftL` 8) .|. fromIntegral byte) 0 <$> takeBytes width
      unless (value >= minimumValue) (reject "ARS host reference noncanonical CBOR width")
      pure value

expectHead :: Word8 -> Word64 -> Reader ()
expectHead major count = do
  actual <- readHead major
  unless (actual == count) (reject "ARS host reference CBOR field count differs")

readText :: Word64 -> Reader Text
readText bound = do
  count <- readHead 3
  unless (count <= bound) (reject "ARS host reference text exceeds its byte limit")
  encoded <- takeBytes count
  either (const (reject "ARS host reference UTF-8 is invalid")) pure (UTF8.decodeUtf8' encoded)

readDigest :: Reader Text
readDigest = do
  expectHead 2 32
  hex <$> takeBytes 32

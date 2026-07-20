{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The frozen JMW1 weight-vector codec.
--
-- This module deliberately owns no checkpoint-manifest types.  Its encoder is
-- byte-for-byte identical to the original V1 implementation in
-- "JitML.Checkpoint.Format": the @JMW1@ magic, a little-endian CBOR-header
-- length, the generic-serialised @F64@ header, and little-endian IEEE-754
-- doubles.  Keeping this small boundary independent lets V2 use the exact
-- physical weight bytes without importing or re-encoding a V1 manifest.
module JitML.Checkpoint.WeightCodec
  ( encodeJmw1
  , decodeJmw1
  , jmw1ContentSha
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (Bits, shiftL, shiftR, (.&.))
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word32, Word64, Word8)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import GHC.Generics (Generic)

data Jmw1Header = Jmw1Header
  { jmw1Dtype :: Text
  , jmw1TensorCount :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Encode one physical flat F64 tensor in the frozen JMW1 representation.
encodeJmw1 :: [Double] -> LazyByteString.ByteString
encodeJmw1 values =
  LazyByteString.fromStrict $
    StrictByteString.concat
      [ Text.Encoding.encodeUtf8 "JMW1"
      , word32Le (fromIntegral (LazyByteString.length header))
      , LazyByteString.toStrict header
      , StrictByteString.concat (fmap doubleLe values)
      ]
 where
  header =
    serialise
      Jmw1Header
        { jmw1Dtype = "F64"
        , jmw1TensorCount = length values
        }

-- | Decode one complete JMW1 tensor.  The decoder rejects trailing bytes,
-- truncation, non-F64 payloads, and non-finite values; it never pads or trims.
decodeJmw1 :: LazyByteString.ByteString -> Either Text [Double]
decodeJmw1 payload = do
  let strict = LazyByteString.toStrict payload
      (magic, afterMagic) = StrictByteString.splitAt 4 strict
      (headerLengthBytes, afterHeaderLength) =
        StrictByteString.splitAt 4 afterMagic
  if magic /= Text.Encoding.encodeUtf8 "JMW1"
    then Left "unsupported .jmw1 magic"
    else do
      headerLength <-
        maybeToEither
          "truncated .jmw1 header length"
          (word32FromLe headerLengthBytes)
      let requestedHeaderLength = fromIntegral headerLength
          (headerBytes, tensorBytes) =
            StrictByteString.splitAt requestedHeaderLength afterHeaderLength
      if StrictByteString.length headerBytes /= requestedHeaderLength
        then Left "truncated .jmw1 header"
        else do
          header <- decodeJmw1Header (LazyByteString.fromStrict headerBytes)
          if jmw1Dtype header /= "F64"
            then Left ("unsupported .jmw1 dtype: " <> jmw1Dtype header)
            else decodeJmw1Doubles (jmw1TensorCount header) tensorBytes

-- | SHA-256 of the exact observed JMW1 bytes, rendered as canonical lowercase
-- hexadecimal.  This intentionally does not decode and re-encode the tensor.
jmw1ContentSha :: LazyByteString.ByteString -> Text
jmw1ContentSha = hexBytes . SHA256.hashlazy

decodeJmw1Header :: LazyByteString.ByteString -> Either Text Jmw1Header
decodeJmw1Header bytes =
  case deserialiseOrFail bytes of
    Left failure -> Left ("invalid .jmw1 header: " <> Text.pack (show failure))
    Right header -> Right header

decodeJmw1Doubles :: Int -> StrictByteString.ByteString -> Either Text [Double]
decodeJmw1Doubles count bytes
  | count < 0 = Left "invalid .jmw1 tensor count"
  | StrictByteString.length bytes /= count * 8 =
      Left "unexpected .jmw1 tensor payload length"
  | otherwise = traverse decodeDoubleAt [0 .. count - 1]
 where
  decodeDoubleAt index = do
    value <-
      castWord64ToDouble
        <$> maybeToEither
          "truncated .jmw1 double payload"
          ( word64FromLe
              (StrictByteString.take 8 (StrictByteString.drop (index * 8) bytes))
          )
    if isNaN value || isInfinite value
      then Left ".jmw1 tensor values must be finite"
      else Right value

hexBytes :: StrictByteString.ByteString -> Text
hexBytes = Text.pack . concatMap hexWord8 . StrictByteString.unpack

hexWord8 :: Word8 -> String
hexWord8 byte =
  [ intToDigit (fromIntegral byte `div` 16)
  , intToDigit (fromIntegral byte `mod` 16)
  ]

doubleLe :: Double -> StrictByteString.ByteString
doubleLe = word64Le . castDoubleToWord64

word32Le :: Word32 -> StrictByteString.ByteString
word32Le word =
  StrictByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    ]

word64Le :: Word64 -> StrictByteString.ByteString
word64Le word =
  StrictByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    , byteAt 32 word
    , byteAt 40 word
    , byteAt 48 word
    , byteAt 56 word
    ]

byteAt :: (Integral a, Bits a) => Int -> a -> Word8
byteAt offset word =
  fromIntegral ((word `shiftR` offset) .&. 0xff)

word32FromLe :: StrictByteString.ByteString -> Maybe Word32
word32FromLe bytes =
  case StrictByteString.unpack bytes of
    [b0, b1, b2, b3] ->
      Just
        ( fromIntegral b0
            + (fromIntegral b1 `shiftL` 8)
            + (fromIntegral b2 `shiftL` 16)
            + (fromIntegral b3 `shiftL` 24)
        )
    _ -> Nothing

word64FromLe :: StrictByteString.ByteString -> Maybe Word64
word64FromLe bytes =
  case StrictByteString.unpack bytes of
    [b0, b1, b2, b3, b4, b5, b6, b7] ->
      Just
        ( fromIntegral b0
            + (fromIntegral b1 `shiftL` 8)
            + (fromIntegral b2 `shiftL` 16)
            + (fromIntegral b3 `shiftL` 24)
            + (fromIntegral b4 `shiftL` 32)
            + (fromIntegral b5 `shiftL` 40)
            + (fromIntegral b6 `shiftL` 48)
            + (fromIntegral b7 `shiftL` 56)
        )
    _ -> Nothing

maybeToEither :: Text -> Maybe value -> Either Text value
maybeToEither message = maybe (Left message) Right

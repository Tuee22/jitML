{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , TensorBlob (..)
  , applyPointerWrite
  , bestPointerKey
  , blobKey
  , decodeManifestCbor
  , encodeJmw1
  , encodeManifestCbor
  , inferFromManifest
  , latestPointerKey
  , manifestContentSha
  , manifestKey
  , manifestPointer
  , trialPointerKey
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (Bits, shiftR, (.&.))
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word32, Word64, Word8)
import GHC.Float (castDoubleToWord64)
import GHC.Generics (Generic)

data TensorBlob = TensorBlob
  { tensorName :: Text
  , tensorShape :: [Int]
  , tensorBlobKey :: Text
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data CheckpointManifest = CheckpointManifest
  { manifestId :: Text
  , manifestExperiment :: Text
  , manifestTensors :: [TensorBlob]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data PointerWrite = PointerWrite
  { pointerWriteKey :: Text
  , pointerWriteExpectedETag :: Maybe Text
  , pointerWriteManifestSha :: Text
  }
  deriving stock (Eq, Show)

data PointerWriteResult
  = PointerWritten Text
  | PointerConflict Text
  deriving stock (Eq, Show)

data Jmw1Header = Jmw1Header
  { jmw1Dtype :: Text
  , jmw1TensorCount :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

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

encodeManifestCbor :: CheckpointManifest -> LazyByteString.ByteString
encodeManifestCbor =
  serialise . canonicalManifest

decodeManifestCbor :: LazyByteString.ByteString -> Either Text CheckpointManifest
decodeManifestCbor payload =
  case deserialiseOrFail payload of
    Left failure -> Left (Text.pack (show failure))
    Right manifest -> Right manifest

manifestContentSha :: CheckpointManifest -> Text
manifestContentSha =
  hexBytes . SHA256.hashlazy . encodeManifestCbor

blobKey :: Text -> Text -> Text
blobKey experimentHash blobSha =
  "jitml-checkpoints/" <> experimentHash <> "/blobs/" <> blobSha

manifestKey :: Text -> Text -> Text
manifestKey experimentHash manifestSha =
  "jitml-checkpoints/" <> experimentHash <> "/manifests/" <> manifestSha <> ".cbor"

latestPointerKey :: Text -> Text
latestPointerKey experimentHash =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/latest"

bestPointerKey :: Text -> Text -> Text
bestPointerKey experimentHash metricName =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/best/" <> metricName

trialPointerKey :: Text -> Text -> Text
trialPointerKey experimentHash trialId =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/trial/" <> trialId

manifestPointer :: CheckpointManifest -> Text
manifestPointer manifest =
  "jitml-checkpoints/"
    <> manifestExperiment manifest
    <> "/"
    <> manifestId manifest
    <> ".manifest.cbor"

inferFromManifest :: CheckpointManifest -> [Double] -> [Double]
inferFromManifest manifest =
  fmap (+ bias)
 where
  bias = fromIntegral (length (manifestTensors manifest)) / 100.0

applyPointerWrite :: Maybe Text -> PointerWrite -> PointerWriteResult
applyPointerWrite currentETag write
  | currentETag == pointerWriteExpectedETag write =
      PointerWritten (pointerWriteManifestSha write)
  | otherwise =
      PointerConflict (pointerWriteKey write)

canonicalManifest :: CheckpointManifest -> CheckpointManifest
canonicalManifest manifest =
  manifest {manifestTensors = sortOn tensorName (manifestTensors manifest)}

hexBytes :: StrictByteString.ByteString -> Text
hexBytes =
  Text.pack . concatMap hexWord8 . StrictByteString.unpack

doubleLe :: Double -> StrictByteString.ByteString
doubleLe =
  word64Le . castDoubleToWord64

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

hexWord8 :: Word8 -> String
hexWord8 byte =
  [hexDigit (byte `div` 16), hexDigit (byte `mod` 16)]

hexDigit :: Word8 -> Char
hexDigit nibble
  | nibble < 10 = toEnum (fromEnum '0' + fromIntegral nibble)
  | otherwise = toEnum (fromEnum 'a' + fromIntegral nibble - 10)

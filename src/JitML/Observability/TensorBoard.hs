{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.TensorBoard
  ( ShardRotationDecision (..)
  , ShardRotationLimits (..)
  , TbCheckpointMarker (..)
  , TensorBoardEvent (..)
  , canonicalProjection
  , checkpointSidecarKey
  , crc32cCastagnoli
  , defaultShardRotationLimits
  , encodeTbCheckpointMarker
  , encodeTfRecord
  , encodeTfRecordBatch
  , maskedCrc32c
  , renderTensorBoardDeployment
  , renderTensorBoardService
  , shardKey
  , shouldRotateShard
  )
where

import Codec.Serialise (Serialise, serialise)
import Data.Bits (Bits, shiftL, shiftR, xor, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64, Word8)
import GHC.Generics (Generic)

data TensorBoardEvent = TensorBoardEvent
  { tbTag :: Text
  , tbStep :: Int
  , tbValue :: Double
  }
  deriving stock (Eq, Show)

canonicalProjection :: [TensorBoardEvent] -> [(Text, Int, Double)]
canonicalProjection =
  fmap project . sortOn (\event -> (tbTag event, tbStep event))
 where
  project event = (tbTag event, tbStep event, tbValue event)

shardKey :: Text -> Int -> Text
shardKey experimentHash shardSeq =
  "jitml-tensorboard/" <> experimentHash <> "/events/" <> Text.pack (show shardSeq) <> ".tfevents"

checkpointSidecarKey :: Text -> Int -> Text -> Text
checkpointSidecarKey experimentHash step manifestSha =
  "jitml-tensorboard/"
    <> experimentHash
    <> "/checkpoints/"
    <> Text.pack (show step)
    <> "-"
    <> manifestSha
    <> ".cbor"

renderTensorBoardDeployment :: Text
renderTensorBoardDeployment =
  Text.unlines
    [ "apiVersion: apps/v1"
    , "kind: Deployment"
    , "metadata:"
    , "  name: tensorboard"
    , "  namespace: platform"
    , "spec:"
    , "  replicas: 1"
    , "  selector:"
    , "    matchLabels:"
    , "      app: tensorboard"
    , "  template:"
    , "    metadata:"
    , "      labels:"
    , "        app: tensorboard"
    , "    spec:"
    , "      containers:"
    , "        - name: tensorboard"
    , "          image: tensorboard:local"
    , "          args: [\"--logdir\", \"s3://jitml-tensorboard\"]"
    , "          ports:"
    , "            - name: http"
    , "              containerPort: 6006"
    ]

-- | TensorBoard Service backing the `/tensorboard` HTTPRoute. Routes Envoy
-- Gateway traffic to the Deployment's container port 6006 (TensorBoard's
-- default HTTP listener).
renderTensorBoardService :: Text
renderTensorBoardService =
  Text.unlines
    [ "apiVersion: v1"
    , "kind: Service"
    , "metadata:"
    , "  name: tensorboard"
    , "  namespace: platform"
    , "spec:"
    , "  selector:"
    , "    app: tensorboard"
    , "  ports:"
    , "    - name: http"
    , "      port: 80"
    , "      targetPort: http"
    ]

-- | TFRecord frame: `uint64 LE length` + `uint32 LE masked-CRC32C(8-byte LE length)`
-- + `payload` + `uint32 LE masked-CRC32C(payload)`. The format is dictated by
-- TensorBoard's reader; this is the writer the per-substrate `jitml service`
-- daemon uses to push events into MinIO bucket `jitml-tensorboard`.
encodeTfRecord :: ByteString -> LazyByteString.ByteString
encodeTfRecord payload =
  LazyByteString.fromStrict $
    ByteString.concat
      [ lengthLe
      , word32Le (maskedCrc32c lengthLe)
      , payload
      , word32Le (maskedCrc32c payload)
      ]
 where
  lengthLe = word64Le (fromIntegral (ByteString.length payload))

encodeTfRecordBatch :: [ByteString] -> LazyByteString.ByteString
encodeTfRecordBatch =
  LazyByteString.concat . fmap encodeTfRecord

-- | TF's standard masked CRC: `((crc >> 15) | (crc << 17)) + 0xa282ead8` mod 2^32.
maskedCrc32c :: ByteString -> Word32
maskedCrc32c payload =
  let crc = crc32cCastagnoli payload
      rotated = (crc `shiftR` 15) .|. (crc `shiftL` 17)
   in rotated + 0xa282ead8

-- | Castagnoli CRC32C over a `ByteString`. Bit-reversed reflection of input
-- and output to match TF/TensorBoard's wire convention. The standard
-- protocol: init 0xFFFFFFFF, fold each byte through 8 right-shifted XOR steps,
-- final XOR with 0xFFFFFFFF. Slow (one byte per iteration) but correct —
-- the daemon's hot path batches many events into one TFRecord shard, so the
-- per-byte cost is amortised.
crc32cCastagnoli :: ByteString -> Word32
crc32cCastagnoli payload =
  ByteString.foldl' step 0xFFFFFFFF payload `xor` 0xFFFFFFFF
 where
  step crc byte = stepByte (crc `xor` fromIntegral byte)

  stepByte :: Word32 -> Word32
  stepByte = applyTimes 8 advanceBit

  advanceBit :: Word32 -> Word32
  advanceBit value
    | value .&. 1 == 1 = (value `shiftR` 1) `xor` 0x82F63B78
    | otherwise = value `shiftR` 1

applyTimes :: Int -> (a -> a) -> a -> a
applyTimes 0 _ acc = acc
applyTimes n f acc = applyTimes (n - 1) f (f acc)

word32Le :: Word32 -> ByteString
word32Le word =
  ByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    ]

word64Le :: Word64 -> ByteString
word64Le word =
  ByteString.pack
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

-- | Typed `TbCheckpointMarker` CBOR sidecar payload. Written under
-- `jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`
-- whenever the daemon's training loop emits `CheckpointDone`. The sidecar
-- lets TensorBoard's UI thread map a particular displayed loss step back
-- to the manifest content SHA so the operator can replay or fork from
-- that point.
data TbCheckpointMarker = TbCheckpointMarker
  { tcmStep :: Word64
  , tcmEpoch :: Word32
  , tcmManifestSha :: Text
  , tcmExperimentSha :: Text
  , tcmTrialSha :: Maybe Text
  , tcmRunUuid :: Text
  , tcmMetricsAtStep :: [(Text, Double)]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

encodeTbCheckpointMarker :: TbCheckpointMarker -> LazyByteString.ByteString
encodeTbCheckpointMarker = serialise

-- | Shard-rotation policy knobs. The daemon rotates the active TFRecord
-- shard when ANY of the limits is exceeded; the `shardExplicitFlush`
-- flag is set when the trainer requests an immediate flush (e.g.
-- `CheckpointDone`, graceful drain, SIGTERM).
data ShardRotationLimits = ShardRotationLimits
  { shardMaxBytes :: Word64
  , shardMaxElapsedSeconds :: Int
  , shardExplicitFlush :: Bool
  }
  deriving stock (Eq, Show)

defaultShardRotationLimits :: ShardRotationLimits
defaultShardRotationLimits =
  ShardRotationLimits
    { shardMaxBytes = 4 * 1024 * 1024 -- 4 MiB
    , shardMaxElapsedSeconds = 10
    , shardExplicitFlush = False
    }

data ShardRotationDecision
  = ShardKeepOpen
  | -- | current vs limit
    ShardRotateForBytes Word64 Word64
  | -- | current vs limit
    ShardRotateForElapsed Int Int
  | ShardRotateForExplicit
  deriving stock (Eq, Show)

-- | Pure rotation predicate. The explicit flush takes precedence;
-- otherwise the byte limit; otherwise the elapsed limit; otherwise the
-- shard stays open.
shouldRotateShard :: Word64 -> Int -> ShardRotationLimits -> ShardRotationDecision
shouldRotateShard currentBytes elapsedSeconds limits
  | shardExplicitFlush limits = ShardRotateForExplicit
  | currentBytes >= shardMaxBytes limits =
      ShardRotateForBytes currentBytes (shardMaxBytes limits)
  | elapsedSeconds >= shardMaxElapsedSeconds limits =
      ShardRotateForElapsed elapsedSeconds (shardMaxElapsedSeconds limits)
  | otherwise = ShardKeepOpen

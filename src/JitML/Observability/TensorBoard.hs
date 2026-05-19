{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.TensorBoard
  ( TensorBoardFlushResult (..)
  , TensorBoardWriterState (..)
  , ShardRotationDecision (..)
  , ShardRotationLimits (..)
  , TbCheckpointMarker (..)
  , TensorBoardEvent (..)
  , appendTensorBoardEvent
  , canonicalProjection
  , checkpointSidecarKey
  , crc32cCastagnoli
  , defaultShardRotationLimits
  , emptyTensorBoardWriterState
  , encodeTbCheckpointMarker
  , encodeTensorBoardEventProto
  , encodeTfRecord
  , encodeTfRecordBatch
  , flushTensorBoardWriter
  , maskedCrc32c
  , renderTensorBoardDeployment
  , renderTensorBoardService
  , shardKey
  , shouldRotateShard
  , tensorBoardShardObjectRef
  , writeTensorBoardEvent
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

import JitML.Proto.TensorBoard
  ( TensorBoardEvent (..)
  , encodeTensorBoardEventProto
  , encodeTensorBoardFileVersionProto
  )
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))

canonicalProjection :: [TensorBoardEvent] -> [(Text, Word64, Double)]
canonicalProjection =
  fmap project . sortOn (\event -> (tbTag event, tbStep event))
 where
  project event = (tbTag event, tbStep event, tbValue event)

shardKey :: Text -> Text -> Word64 -> Text
shardKey experimentHash writerId shardSeq =
  "jitml-tensorboard/"
    <> experimentHash
    <> "/shards/"
    <> writerId
    <> "-"
    <> Text.pack (show shardSeq)
    <> ".tfevents"

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
    , "          image: python:3.11-slim"
    , "          command: [\"sh\", \"-c\"]"
    , "          args:"
    , "            - >-"
    , "              pip install --no-cache-dir setuptools==69.5.1 'numpy<2' tensorboard==2.16.2"
    , "              >/tmp/tensorboard-pip.log 2>&1 &&"
    , "              tensorboard --logdir /tensorboard/logs --bind_all --port 6006"
    , "          ports:"
    , "            - name: http"
    , "              containerPort: 6006"
    , "          readinessProbe:"
    , "            httpGet:"
    , "              path: /"
    , "              port: http"
    , "            initialDelaySeconds: 5"
    , "            periodSeconds: 5"
    , "          volumeMounts:"
    , "            - name: tensorboard-logs"
    , "              mountPath: /tensorboard/logs"
    , "        - name: minio-sync"
    , "          image: bitnamilegacy/minio-client:2024.10.29-debian-12-r1"
    , "          command: [\"sh\", \"-c\"]"
    , "          args:"
    , "            - >-"
    , "              set -eu; /opt/bitnami/minio-client/bin/mc alias set jitml-minio http://minio.platform.svc.cluster.local:9000 minio minioadmin >/dev/null; while true; do /opt/bitnami/minio-client/bin/mc mirror --overwrite jitml-minio/jitml-tensorboard /tensorboard/logs >/dev/null || true; sleep 5; done"
    , "          volumeMounts:"
    , "            - name: tensorboard-logs"
    , "              mountPath: /tensorboard/logs"
    , "      volumes:"
    , "        - name: tensorboard-logs"
    , "          emptyDir: {}"
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

data TensorBoardWriterState = TensorBoardWriterState
  { tbwsExperimentHash :: Text
  , tbwsWriterId :: Text
  , tbwsShardSeq :: Word64
  , tbwsStartedAtSeconds :: Int
  , tbwsBufferedFramesNewestFirst :: [ByteString]
  , tbwsBufferedBytes :: Word64
  , tbwsNeedsFileVersion :: Bool
  }
  deriving stock (Eq, Show)

data TensorBoardFlushResult
  = TensorBoardFlushSkippedEmpty
  | TensorBoardFlushStored ObjectRef ETag
  | TensorBoardFlushAlreadyPresent ObjectRef
  deriving stock (Eq, Show)

emptyTensorBoardWriterState :: Text -> Text -> Word64 -> Int -> TensorBoardWriterState
emptyTensorBoardWriterState experimentHash writerId shardSeq startedAtSeconds =
  TensorBoardWriterState
    { tbwsExperimentHash = experimentHash
    , tbwsWriterId = writerId
    , tbwsShardSeq = shardSeq
    , tbwsStartedAtSeconds = startedAtSeconds
    , tbwsBufferedFramesNewestFirst = []
    , tbwsBufferedBytes = 0
    , tbwsNeedsFileVersion = True
    }

appendTensorBoardEvent :: TensorBoardEvent -> TensorBoardWriterState -> TensorBoardWriterState
appendTensorBoardEvent event state =
  state
    { tbwsBufferedFramesNewestFirst =
        newFrames <> tbwsBufferedFramesNewestFirst state
    , tbwsBufferedBytes =
        tbwsBufferedBytes state + fromIntegral (sum (fmap ByteString.length newFrames))
    , tbwsNeedsFileVersion = False
    }
 where
  newFrames =
    scalarFrame
      : [fileVersionFrame | tbwsNeedsFileVersion state]

  scalarFrame = tfRecordFrame (encodeTensorBoardEventProto event)

  fileVersionFrame = tfRecordFrame (encodeTensorBoardFileVersionProto (tbWallTime event))

tfRecordFrame :: ByteString -> ByteString
tfRecordFrame =
  LazyByteString.toStrict . encodeTfRecord

tensorBoardShardObjectRef :: TensorBoardWriterState -> ObjectRef
tensorBoardShardObjectRef state =
  ObjectRef
    (BucketName "jitml-tensorboard")
    ( ObjectKey
        ( shardKey
            (tbwsExperimentHash state)
            (tbwsWriterId state)
            (tbwsShardSeq state)
        )
    )

flushTensorBoardWriter
  :: (HasMinIO m)
  => Int
  -> TensorBoardWriterState
  -> m (Either ServiceError (TensorBoardFlushResult, TensorBoardWriterState))
flushTensorBoardWriter nowSeconds state
  | null (tbwsBufferedFramesNewestFirst state) =
      pure
        ( Right
            ( TensorBoardFlushSkippedEmpty
            , state {tbwsStartedAtSeconds = nowSeconds}
            )
        )
  | otherwise = do
      let ref = tensorBoardShardObjectRef state
          payload = ByteString.concat (reverse (tbwsBufferedFramesNewestFirst state))
          nextState = nextTensorBoardShard nowSeconds state
      putResult <- putBlobBytesIfAbsent ref payload
      pure $
        case putResult of
          Right etag -> Right (TensorBoardFlushStored ref etag, nextState)
          Left (SEConflict _) -> Right (TensorBoardFlushAlreadyPresent ref, nextState)
          Left err -> Left err

writeTensorBoardEvent
  :: (HasMinIO m)
  => Int
  -> ShardRotationLimits
  -> TensorBoardWriterState
  -> TensorBoardEvent
  -> m (Either ServiceError (Maybe TensorBoardFlushResult, TensorBoardWriterState))
writeTensorBoardEvent nowSeconds limits state event =
  let state' = appendTensorBoardEvent event state
      elapsedSeconds = max 0 (nowSeconds - tbwsStartedAtSeconds state')
   in case shouldRotateShard (tbwsBufferedBytes state') elapsedSeconds limits of
        ShardKeepOpen -> pure (Right (Nothing, state'))
        _ -> do
          flushResult <- flushTensorBoardWriter nowSeconds state'
          pure (firstFlushResult <$> flushResult)

firstFlushResult
  :: (TensorBoardFlushResult, TensorBoardWriterState)
  -> (Maybe TensorBoardFlushResult, TensorBoardWriterState)
firstFlushResult (result, state) =
  (Just result, state)

nextTensorBoardShard :: Int -> TensorBoardWriterState -> TensorBoardWriterState
nextTensorBoardShard nowSeconds state =
  state
    { tbwsShardSeq = tbwsShardSeq state + 1
    , tbwsStartedAtSeconds = nowSeconds
    , tbwsBufferedFramesNewestFirst = []
    , tbwsBufferedBytes = 0
    }

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

{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , TensorBlob (..)
  , applyPointerWrite
  , bestPointerKey
  , blobKey
  , encodeJmw1
  , inferFromManifest
  , latestPointerKey
  , manifestKey
  , manifestPointer
  , trialPointerKey
  )
where

import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding

data TensorBlob = TensorBlob
  { tensorName :: Text
  , tensorShape :: [Int]
  , tensorBlobKey :: Text
  }
  deriving stock (Eq, Show)

data CheckpointManifest = CheckpointManifest
  { manifestId :: Text
  , manifestExperiment :: Text
  , manifestTensors :: [TensorBlob]
  }
  deriving stock (Eq, Show)

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

encodeJmw1 :: [Double] -> LazyByteString.ByteString
encodeJmw1 values =
  LazyByteString.fromStrict $
    Text.Encoding.encodeUtf8 $
      Text.unlines ("JMW1" : fmap (Text.pack . show) values)

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

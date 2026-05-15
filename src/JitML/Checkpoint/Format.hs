{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , TensorBlob (..)
  , encodeJmw1
  , inferFromManifest
  , manifestPointer
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

encodeJmw1 :: [Double] -> LazyByteString.ByteString
encodeJmw1 values =
  LazyByteString.fromStrict $
    Text.Encoding.encodeUtf8 $
      Text.unlines ("JMW1" : fmap (Text.pack . show) values)

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

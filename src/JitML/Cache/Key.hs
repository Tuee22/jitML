{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Cache.Key
  ( Extension (..)
  , Hash
  , KernelSpec (..)
  , Kind (..)
  , ModelId (..)
  , RuntimeSourcePayload (..)
  , Substrate (..)
  , ToolchainFingerprint (..)
  , TuningChoice (..)
  , cacheKey
  , cacheKeyMaterial
  , defaultTuningChoice
  , extensionFileSuffix
  , hashBytes
  , hashFromHex
  , hashHex
  , kindText
  , substrateText
  )
where

import Codec.Serialise (Serialise, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (FromJSON (..), ToJSON (..), Value (..), withText)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt, intToDigit, isHexDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)
import GHC.Generics (Generic)

newtype KernelSpec = KernelSpec
  { kernelSpecPayload :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

data Kind
  = Training
  | Inference
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

data Substrate
  = AppleSilicon
  | LinuxCPU
  | LinuxCUDA
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

newtype ToolchainFingerprint = ToolchainFingerprint
  { unToolchainFingerprint :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

newtype RuntimeSourcePayload = RuntimeSourcePayload
  { unRuntimeSourcePayload :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

newtype TuningChoice = TuningChoice
  { unTuningChoice :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

newtype ModelId = ModelId
  { unModelId :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

newtype Extension = Extension
  { unExtension :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Serialise)

newtype Hash = Hash
  { hashBytes :: ByteString
  }
  deriving stock (Eq, Ord, Show)

cacheKey
  :: KernelSpec
  -> Kind
  -> Substrate
  -> ToolchainFingerprint
  -> RuntimeSourcePayload
  -> TuningChoice
  -> Hash
cacheKey kernelSpec kind substrate fingerprint sourcePayload tuningChoice =
  Hash
    (SHA256.hash (cacheKeyMaterial kernelSpec kind substrate fingerprint sourcePayload tuningChoice))

cacheKeyMaterial
  :: KernelSpec
  -> Kind
  -> Substrate
  -> ToolchainFingerprint
  -> RuntimeSourcePayload
  -> TuningChoice
  -> ByteString
cacheKeyMaterial kernelSpec kind substrate fingerprint sourcePayload tuningChoice =
  ByteString.concat
    [ LazyByteString.toStrict (serialise kernelSpec)
    , Text.Encoding.encodeUtf8 (kindText kind)
    , Text.Encoding.encodeUtf8 (substrateText substrate)
    , Text.Encoding.encodeUtf8 (unToolchainFingerprint fingerprint)
    , LazyByteString.toStrict (serialise sourcePayload)
    , LazyByteString.toStrict (serialise tuningChoice)
    ]

defaultTuningChoice :: TuningChoice
defaultTuningChoice =
  TuningChoice "default"

kindText :: Kind -> Text
kindText Training = "training"
kindText Inference = "inference"

substrateText :: Substrate -> Text
substrateText AppleSilicon = "apple-silicon"
substrateText LinuxCPU = "linux-cpu"
substrateText LinuxCUDA = "linux-cuda"

extensionFileSuffix :: Extension -> Text
extensionFileSuffix (Extension extension)
  | "." `Text.isPrefixOf` extension = extension
  | otherwise = "." <> extension

hashHex :: Hash -> Text
hashHex =
  Text.pack . concatMap byteHex . ByteString.unpack . hashBytes
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

hashFromHex :: Text -> Maybe Hash
hashFromHex value
  | Text.length value /= 64 = Nothing
  | not (Text.all isHexDigit value) = Nothing
  | otherwise =
      Hash . ByteString.pack <$> parseBytes (Text.unpack value)
 where
  parseBytes :: String -> Maybe [Word8]
  parseBytes [] = Just []
  parseBytes (high : low : rest) =
    let byte = fromIntegral (digitToInt high * 16 + digitToInt low)
     in (byte :) <$> parseBytes rest
  parseBytes [_] = Nothing

instance ToJSON Kind where
  toJSON = String . kindText

instance FromJSON Kind where
  parseJSON =
    withText "Kind" $ \value ->
      case value of
        "training" -> pure Training
        "inference" -> pure Inference
        _ -> fail ("unknown kernel kind: " <> Text.unpack value)

instance ToJSON Substrate where
  toJSON = String . substrateText

instance FromJSON Substrate where
  parseJSON =
    withText "Substrate" $ \value ->
      case value of
        "apple-silicon" -> pure AppleSilicon
        "linux-cpu" -> pure LinuxCPU
        "linux-cuda" -> pure LinuxCUDA
        _ -> fail ("unknown substrate: " <> Text.unpack value)

instance ToJSON ToolchainFingerprint where
  toJSON = String . unToolchainFingerprint

instance FromJSON ToolchainFingerprint where
  parseJSON = withText "ToolchainFingerprint" (pure . ToolchainFingerprint)

instance ToJSON ModelId where
  toJSON = String . unModelId

instance FromJSON ModelId where
  parseJSON = withText "ModelId" (pure . ModelId)

instance ToJSON Extension where
  toJSON = String . unExtension

instance FromJSON Extension where
  parseJSON = withText "Extension" (pure . Extension)

instance ToJSON TuningChoice where
  toJSON = String . unTuningChoice

instance FromJSON TuningChoice where
  parseJSON = withText "TuningChoice" (pure . TuningChoice)

instance ToJSON Hash where
  toJSON = String . hashHex

instance FromJSON Hash where
  parseJSON =
    withText "Hash" $ \value ->
      case hashFromHex value of
        Just hash -> pure hash
        Nothing -> fail ("invalid sha256 hex digest: " <> Text.unpack value)

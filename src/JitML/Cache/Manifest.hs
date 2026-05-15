{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Cache.Manifest
  ( Manifest (..)
  , ManifestEntry (..)
  , ManifestKey (..)
  , emptyManifest
  , lookupManifest
  , manifestEntryKey
  , readManifest
  , upsertManifest
  , writeManifestAtomic
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), eitherDecode, encode, object, withObject, (.:), (.=))
import Data.ByteString.Lazy qualified as LazyByteString
import GHC.Generics (Generic)
import Path (Abs, Dir, Path, toFilePath)
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (takeDirectory)

import JitML.Cache.Key (Hash, Kind, ModelId, Substrate, ToolchainFingerprint)
import JitML.Cache.Layout (manifestPath)

newtype Manifest = Manifest
  { manifestEntries :: [ManifestEntry]
  }
  deriving stock (Eq, Show, Generic)

data ManifestEntry = ManifestEntry
  { manifestEntryModelId :: ModelId
  , manifestEntryKind :: Kind
  , manifestEntrySubstrate :: Substrate
  , manifestEntryToolchain :: ToolchainFingerprint
  , manifestEntryHash :: Hash
  }
  deriving stock (Eq, Show, Generic)

data ManifestKey = ManifestKey
  { manifestKeyModelId :: ModelId
  , manifestKeyKind :: Kind
  , manifestKeySubstrate :: Substrate
  , manifestKeyToolchain :: ToolchainFingerprint
  }
  deriving stock (Eq, Show)

emptyManifest :: Manifest
emptyManifest = Manifest []

manifestEntryKey :: ManifestEntry -> ManifestKey
manifestEntryKey entry =
  ManifestKey
    { manifestKeyModelId = manifestEntryModelId entry
    , manifestKeyKind = manifestEntryKind entry
    , manifestKeySubstrate = manifestEntrySubstrate entry
    , manifestKeyToolchain = manifestEntryToolchain entry
    }

lookupManifest :: ManifestKey -> Manifest -> Maybe Hash
lookupManifest key =
  go . manifestEntries
 where
  go [] = Nothing
  go (entry : rest)
    | manifestEntryKey entry == key = Just (manifestEntryHash entry)
    | otherwise = go rest

upsertManifest :: ManifestEntry -> Manifest -> Manifest
upsertManifest entry manifest =
  Manifest
    (entry : filter ((/= manifestEntryKey entry) . manifestEntryKey) (manifestEntries manifest))

readManifest :: Path Abs Dir -> IO (Either String Manifest)
readManifest buildRoot = do
  path <- manifestPath buildRoot
  exists <- doesFileExist (toFilePath path)
  if exists
    then eitherDecode <$> LazyByteString.readFile (toFilePath path)
    else pure (Right emptyManifest)

writeManifestAtomic :: Path Abs Dir -> Manifest -> IO ()
writeManifestAtomic buildRoot manifest = do
  path <- manifestPath buildRoot
  let pathText = toFilePath path
      tmpPath = pathText <> ".tmp"
  createDirectoryIfMissing True (takeDirectory pathText)
  LazyByteString.writeFile tmpPath (encode manifest)
  renameFile tmpPath pathText

instance ToJSON Manifest where
  toJSON manifest =
    object ["entries" .= manifestEntries manifest]

instance FromJSON Manifest where
  parseJSON =
    withObject "Manifest" $ \record ->
      Manifest <$> record .: "entries"

instance ToJSON ManifestEntry where
  toJSON entry =
    object
      [ "modelId" .= manifestEntryModelId entry
      , "kind" .= manifestEntryKind entry
      , "substrate" .= manifestEntrySubstrate entry
      , "toolchain" .= manifestEntryToolchain entry
      , "hash" .= manifestEntryHash entry
      ]

instance FromJSON ManifestEntry where
  parseJSON =
    withObject "ManifestEntry" $ \record ->
      ManifestEntry
        <$> record .: "modelId"
        <*> record .: "kind"
        <*> record .: "substrate"
        <*> record .: "toolchain"
        <*> record .: "hash"

{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Store
  ( ObjectWriteResult (..)
  , StoredCheckpoint (..)
  , inferFromLatestCheckpoint
  , objectPathForKey
  , readCheckpointManifest
  , readCheckpointPointer
  , readObject
  , writeCheckpointSnapshot
  , writeObjectIfAbsent
  )
where

import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (isRelative, normalise, takeDirectory, (</>))

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , applyPointerWrite
  , decodeManifestCbor
  , encodeManifestCbor
  , inferFromManifest
  , latestPointerKey
  , manifestContentSha
  , manifestKey
  )

data ObjectWriteResult
  = ObjectCreated Text
  | ObjectAlreadyPresent Text
  deriving stock (Eq, Show)

data StoredCheckpoint = StoredCheckpoint
  { storedManifestSha :: Text
  , storedManifestObjectKey :: Text
  , storedPointerResult :: PointerWriteResult
  }
  deriving stock (Eq, Show)

writeCheckpointSnapshot
  :: FilePath
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Maybe Text
  -> IO StoredCheckpoint
writeCheckpointSnapshot root manifest tensorPayloads expectedPointerETag = do
  mapM_ (uncurry (writeObjectIfAbsent root)) tensorPayloads
  let manifestSha = manifestContentSha manifest
      manifestObjectKey = manifestKey (checkpointExperiment manifest) manifestSha
      pointerKey = latestPointerKey (checkpointExperiment manifest)
  _manifestWrite <- writeObjectIfAbsent root manifestObjectKey (encodeManifestCbor manifest)
  currentPointer <- readCheckpointPointer root pointerKey
  let pointerWrite =
        PointerWrite
          { pointerWriteKey = pointerKey
          , pointerWriteExpectedETag = expectedPointerETag
          , pointerWriteManifestSha = manifestSha
          }
      pointerResult = applyPointerWrite currentPointer pointerWrite
  case pointerResult of
    PointerWritten pointerSha ->
      writeObject root pointerKey (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 pointerSha))
    PointerConflict _ ->
      pure ()
  pure
    StoredCheckpoint
      { storedManifestSha = manifestSha
      , storedManifestObjectKey = manifestObjectKey
      , storedPointerResult = pointerResult
      }

readCheckpointManifest :: FilePath -> Text -> Text -> IO (Either Text CheckpointManifest)
readCheckpointManifest root experimentHash manifestSha = do
  payload <- readObject root (manifestKey experimentHash manifestSha)
  pure (payload >>= decodeManifestCbor)

readCheckpointPointer :: FilePath -> Text -> IO (Maybe Text)
readCheckpointPointer root pointerKey = do
  result <- readObject root pointerKey
  pure $
    case result of
      Left _ -> Nothing
      Right payload ->
        Just (Text.strip (Text.Encoding.decodeUtf8 (LazyByteString.toStrict payload)))

inferFromLatestCheckpoint :: FilePath -> Text -> [Double] -> IO (Either Text [Double])
inferFromLatestCheckpoint root experimentHash input = do
  pointer <- readCheckpointPointer root (latestPointerKey experimentHash)
  case pointer of
    Nothing ->
      pure (Left ("missing checkpoint pointer for " <> experimentHash))
    Just manifestSha -> do
      manifest <- readCheckpointManifest root experimentHash manifestSha
      pure (inferFromManifest <$> manifest <*> pure input)

writeObjectIfAbsent :: FilePath -> Text -> LazyByteString.ByteString -> IO ObjectWriteResult
writeObjectIfAbsent root objectKey payload = do
  let path = objectPathForKey root objectKey
  exists <- doesFileExist path
  if exists
    then pure (ObjectAlreadyPresent objectKey)
    else do
      writeObject root objectKey payload
      pure (ObjectCreated objectKey)

readObject :: FilePath -> Text -> IO (Either Text LazyByteString.ByteString)
readObject root objectKey = do
  let path = objectPathForKey root objectKey
  exists <- doesFileExist path
  if exists
    then Right <$> LazyByteString.readFile path
    else pure (Left ("missing object: " <> objectKey))

writeObject :: FilePath -> Text -> LazyByteString.ByteString -> IO ()
writeObject root objectKey payload = do
  let path = objectPathForKey root objectKey
      tmpPath = path <> ".tmp"
  createDirectoryIfMissing True (takeDirectory path)
  LazyByteString.writeFile tmpPath payload
  renameFile tmpPath path

objectPathForKey :: FilePath -> Text -> FilePath
objectPathForKey root objectKey =
  root </> safeRelativePath objectKey

safeRelativePath :: Text -> FilePath
safeRelativePath objectKey =
  let path = normalise (Text.unpack objectKey)
   in if null path || path == "." || not (isRelative path) || ".." `elem` splitPathSegments path
        then error ("unsafe object key: " <> Text.unpack objectKey)
        else path

splitPathSegments :: FilePath -> [FilePath]
splitPathSegments =
  filter (`notElem` ["", "."]) . splitOnSlash

splitOnSlash :: FilePath -> [FilePath]
splitOnSlash [] = []
splitOnSlash path =
  let (segment, rest) = break (== '/') path
   in case rest of
        [] -> [segment]
        _slash : remainder -> segment : splitOnSlash remainder

checkpointExperiment :: CheckpointManifest -> Text
checkpointExperiment =
  manifestExperiment

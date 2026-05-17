{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Store
  ( GcEvent (..)
  , GcPlan (..)
  , ObjectWriteResult (..)
  , RetentionPolicy (..)
  , StoredCheckpoint (..)
  , applyRetentionPolicy
  , buildGcPlan
  , inferFromLatestCheckpoint
  , inferWeightsOnlyFromLatestCheckpoint
  , objectPathForKey
  , readCheckpointManifest
  , readCheckpointPointer
  , readObject
  , walkLiveSet
  , writeCheckpointSnapshot
  , writeObjectIfAbsent
  )
where

import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (nub, sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (isRelative, normalise, takeDirectory, (</>))

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , TensorBlob (..)
  , applyPointerWrite
  , decodeManifestCbor
  , encodeManifestCbor
  , inferFromManifest
  , latestPointerKey
  , manifestContentSha
  , manifestKey
  , weightOnlyTensors
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

-- | Weight-only inference: loads only the weight tensors from the addressed
-- manifest and skips optimizer / RNG split-blob parts (the inference path does
-- not need them).
inferWeightsOnlyFromLatestCheckpoint
  :: FilePath -> Text -> [Double] -> IO (Either Text [Double])
inferWeightsOnlyFromLatestCheckpoint root experimentHash input = do
  pointer <- readCheckpointPointer root (latestPointerKey experimentHash)
  case pointer of
    Nothing ->
      pure (Left ("missing checkpoint pointer for " <> experimentHash))
    Just manifestSha -> do
      manifest <- readCheckpointManifest root experimentHash manifestSha
      case manifest of
        Left err -> pure (Left err)
        Right m ->
          let weightOnlyManifest = m {manifestOptimizer = [], manifestRng = []}
              _ = weightOnlyTensors m -- explicit use of the inference predicate
           in pure (Right (inferFromManifest weightOnlyManifest input))

-- | Retention policy applied by `jitml internal gc <experiment-hash>` per
-- README → Retention and GC.
data RetentionPolicy
  = KeepAll
  | LastN Int
  deriving stock (Eq, Show)

-- | Live-set traversal: the trainer follows `pointers/latest`, every
-- `pointers/best/<m>`, and every `pointers/trial/<...>` plus the parent-manifest
-- chain. The result is the set of manifest SHAs whose blobs must not be reaped.
walkLiveSet :: [CheckpointManifest] -> [Text]
walkLiveSet manifests =
  nub
    [ sha
    | manifest <- manifests
    , sha <- manifestContentSha manifest : maybeToList (manifestParentManifestSha manifest)
    ]
 where
  maybeToList Nothing = []
  maybeToList (Just t) = [t]

-- | Apply `LastN k` retention to a list of manifests sorted by step descending.
-- `pointers/best/<m>` and `pointers/trial/<m>` targets must be in the input as
-- additional "always live" manifests.
applyRetentionPolicy
  :: RetentionPolicy
  -> [CheckpointManifest]
  -- ^ candidates on the `latest` chain
  -> [CheckpointManifest]
  -- ^ always-live (best / trial pointer targets)
  -> [Text]
  -- ^ manifest SHAs to keep
applyRetentionPolicy policy chain alwaysLive =
  let alwaysLiveSet = walkLiveSet alwaysLive
      kept =
        case policy of
          KeepAll -> chain
          LastN k -> take k (sortOn (Down . manifestStep) chain)
   in nub (alwaysLiveSet <> walkLiveSet kept)

data GcEvent = GcEvent
  { gcReapedManifestSha :: Text
  , gcReapedBlobShas :: [Text]
  , gcExperimentHash :: Text
  , gcStepAtReap :: Word64
  }
  deriving stock (Eq, Show)

data GcPlan = GcPlan
  { gcKeptManifestShas :: [Text]
  , gcReapEvents :: [GcEvent]
  , gcNoOp :: Bool
  }
  deriving stock (Eq, Show)

-- | Build the GC reconciler plan from the candidate manifests, always-live
-- pointer targets, and the retention policy. A second invocation against the
-- same input is a no-op (`gcNoOp = True`) per README → Reconcilers.
buildGcPlan
  :: Text
  -- ^ experiment hash
  -> RetentionPolicy
  -> [CheckpointManifest]
  -- ^ all manifests under this experiment
  -> [CheckpointManifest]
  -- ^ pointer-target manifests (best / trial)
  -> GcPlan
buildGcPlan experimentHash policy allManifests alwaysLive =
  let kept = applyRetentionPolicy policy allManifests alwaysLive
      reapTargets =
        [ manifest
        | manifest <- allManifests
        , manifestContentSha manifest `notElem` kept
        ]
      events =
        [ GcEvent
            { gcReapedManifestSha = manifestContentSha manifest
            , gcReapedBlobShas =
                fmap tensorBlobKey (manifestTensors manifest)
            , gcExperimentHash = experimentHash
            , gcStepAtReap = manifestStep manifest
            }
        | manifest <- reapTargets
        ]
   in GcPlan
        { gcKeptManifestShas = kept
        , gcReapEvents = events
        , gcNoOp = null events
        }

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

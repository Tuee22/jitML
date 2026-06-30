{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Store
  ( GcEvent (..)
  , GcExecutionResult (..)
  , GcPlan (..)
  , LoadedWeightTensor (..)
  , ObjectWriteResult (..)
  , RetentionPolicy (..)
  , StoredCheckpoint (..)
  , applyRetentionPolicy
  , buildGcPlan
  , checkpointObjectKey
  , checkpointObjectRef
  , executeGcPlan
  , listCheckpointManifests
  , listCheckpointManifestsMinIO
  , loadInferenceCheckpointWith
  , loadInferenceCheckpointWithWeights
  , loadInferenceCheckpointDecodedWithWeights
  , loadWeightTensors
  , objectPathForKey
  , readCheckpointManifest
  , readCheckpointPointer
  , readObject
  , walkLiveSet
  , writeCheckpointSnapshot
  , writeCheckpointSnapshotWithMinIO
  , writeObjectIfAbsent
  )
where

import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (nub, sortOn)
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , renameFile
  )
import System.FilePath (isRelative, normalise, takeDirectory, (</>))

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , TensorBlob (..)
  , applyPointerWrite
  , blobKey
  , decodeJmw1
  , decodeManifestCbor
  , eligibleCheckpointManifest
  , encodeManifestCbor
  , latestPointerKey
  , manifestContentSha
  , manifestKey
  , renderEligibilityError
  , requireInferenceEligibleCheckpoint
  , weightOnlyTensors
  )
import JitML.Inference.Decode (DecodedInference, decodeManifestOutput)
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))

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

data LoadedWeightTensor = LoadedWeightTensor
  { loadedWeightTensor :: TensorBlob
  , loadedWeightValues :: [Double]
  }
  deriving stock (Eq, Show)

writeCheckpointSnapshot
  :: FilePath
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Maybe Text
  -> IO (Either Text StoredCheckpoint)
writeCheckpointSnapshot root manifest tensorPayloads expectedPointerETag = do
  tensorWrites <- traverse (uncurry (writeObjectIfAbsent root)) tensorPayloads
  case sequence tensorWrites of
    Left err ->
      pure (Left err)
    Right _ -> do
      let manifestSha = manifestContentSha manifest
          manifestObjectKey = manifestKey (checkpointExperiment manifest) manifestSha
          pointerKey = latestPointerKey (checkpointExperiment manifest)
      manifestWrite <- writeObjectIfAbsent root manifestObjectKey (encodeManifestCbor manifest)
      case manifestWrite of
        Left err ->
          pure (Left err)
        Right _ -> do
          currentPointerResult <- readCheckpointPointer root pointerKey
          case currentPointerResult of
            Left err ->
              pure (Left err)
            Right currentPointer -> do
              let pointerWrite =
                    PointerWrite
                      { pointerWriteKey = pointerKey
                      , pointerWriteExpectedETag = expectedPointerETag
                      , pointerWriteManifestSha = manifestSha
                      }
                  pointerResult = applyPointerWrite currentPointer pointerWrite
                  stored =
                    StoredCheckpoint
                      { storedManifestSha = manifestSha
                      , storedManifestObjectKey = manifestObjectKey
                      , storedPointerResult = pointerResult
                      }
              case pointerResult of
                PointerWritten pointerSha -> do
                  pointerWriteResult <-
                    writeObject
                      root
                      pointerKey
                      (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 pointerSha))
                  pure (stored <$ pointerWriteResult)
                PointerConflict _ ->
                  pure (Right stored)

-- | Checkpoint snapshot writer over the production `HasMinIO` capability
-- boundary. Split blobs and manifests are byte-faithful write-once objects;
-- the latest pointer advances through `casPointer`.
writeCheckpointSnapshotWithMinIO
  :: (HasMinIO m)
  => CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Maybe ETag
  -> m (Either ServiceError StoredCheckpoint)
writeCheckpointSnapshotWithMinIO manifest tensorPayloads expectedPointerETag = do
  blobWrites <-
    traverse
      ( \(objectKey, payload) ->
          putObjectBytesIfAbsentOrSame
            (checkpointObjectRef objectKey)
            (LazyByteString.toStrict payload)
      )
      tensorPayloads
  case sequence blobWrites of
    Left err ->
      pure (Left err)
    Right _ -> do
      let manifestSha = manifestContentSha manifest
          manifestObjectKey = manifestKey (checkpointExperiment manifest) manifestSha
          pointerKey = latestPointerKey (checkpointExperiment manifest)
      manifestWrite <-
        putObjectBytesIfAbsentOrSame
          (checkpointObjectRef manifestObjectKey)
          (LazyByteString.toStrict (encodeManifestCbor manifest))
      case manifestWrite of
        Left err ->
          pure (Left err)
        Right () -> do
          pointerWrite <- casPointer (checkpointObjectRef pointerKey) expectedPointerETag manifestSha
          case pointerWrite of
            Right _ ->
              pure $
                Right
                  StoredCheckpoint
                    { storedManifestSha = manifestSha
                    , storedManifestObjectKey = manifestObjectKey
                    , storedPointerResult = PointerWritten manifestSha
                    }
            Left (SEConflict _) ->
              pure $
                Right
                  StoredCheckpoint
                    { storedManifestSha = manifestSha
                    , storedManifestObjectKey = manifestObjectKey
                    , storedPointerResult = PointerConflict pointerKey
                    }
            Left err ->
              pure (Left err)

putObjectBytesIfAbsentOrSame
  :: (HasMinIO m)
  => ObjectRef
  -> StrictByteString.ByteString
  -> m (Either ServiceError ())
putObjectBytesIfAbsentOrSame ref payload = do
  write <- putBlobBytesIfAbsent ref payload
  case write of
    Right _ ->
      pure (Right ())
    Left (SEConflict _) -> do
      existing <- minioReadBytes ref
      case existing of
        Right bytes
          | bytes == payload ->
              pure (Right ())
          | otherwise ->
              pure (Left (SEConflict "object exists with different bytes"))
        Left err ->
          pure (Left err)
    Left err ->
      pure (Left err)

readCheckpointManifest :: FilePath -> Text -> Text -> IO (Either Text CheckpointManifest)
readCheckpointManifest root experimentHash manifestSha = do
  payload <- readObject root (manifestKey experimentHash manifestSha)
  pure (payload >>= decodeManifestCbor)

readCheckpointPointer :: FilePath -> Text -> IO (Either Text (Maybe Text))
readCheckpointPointer root pointerKey = do
  case objectPathForKey root pointerKey of
    Left err ->
      pure (Left err)
    Right path -> do
      exists <- doesFileExist path
      if exists
        then do
          payload <- LazyByteString.readFile path
          pure (Right (Just (Text.strip (Text.Encoding.decodeUtf8 (LazyByteString.toStrict payload)))))
        else pure (Right Nothing)

listCheckpointManifests :: FilePath -> Text -> IO (Either Text [CheckpointManifest])
listCheckpointManifests root experimentHash = do
  let manifestDirKey = "jitml-checkpoints/" <> experimentHash <> "/manifests"
  case objectPathForKey root manifestDirKey of
    Left err ->
      pure (Left err)
    Right manifestDir -> do
      exists <- doesDirectoryExist manifestDir
      if not exists
        then pure (Right [])
        else do
          entries <- listDirectory manifestDir
          decoded <- traverse (readManifestEntry manifestDir) (filter isManifestFile entries)
          pure (sequence decoded)
 where
  isManifestFile path = ".cbor" `Text.isSuffixOf` Text.pack path

  readManifestEntry manifestDir entry = do
    payload <- LazyByteString.readFile (manifestDir </> entry)
    pure (decodeManifestCbor payload)

-- | MinIO-backed variant of `listCheckpointManifests`. Used by the live
-- `jitml internal gc` reconciler against the cluster broker so the
-- reconciler walks objects under
-- `jitml-checkpoints/<experiment-hash>/manifests/` through
-- `HasMinIO.listObjects` and decodes each manifest body through
-- `minioReadBytes`. Returns the typed `ServiceError` on the first transport
-- failure or `Text` decode failure (wrapped as `SETransient`); a missing
-- prefix yields the empty list, matching the local-fs path.
listCheckpointManifestsMinIO
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [CheckpointManifest])
listCheckpointManifestsMinIO experimentHash = do
  let bucket = BucketName "jitml-checkpoints"
      prefix = experimentHash <> "/manifests/"
  listing <- listObjects bucket prefix
  case listing of
    Left err -> pure (Left err)
    Right refs -> do
      decoded <- traverse readAndDecode refs
      pure (sequence decoded)
 where
  readAndDecode ref = do
    bytes <- minioReadBytes ref
    case bytes of
      Left err -> pure (Left err)
      Right payload ->
        case decodeManifestCbor (LazyByteString.fromStrict payload) of
          Left err ->
            pure
              ( Left
                  ( SETransient
                      ( "decodeManifestCbor failed for "
                          <> Text.pack (show ref)
                          <> ": "
                          <> err
                      )
                  )
              )
          Right manifest -> pure (Right manifest)

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

-- | Outcome of executing a GC plan through `HasMinIO`. The reaped tally
-- counts manifests + per-blob deletes; the failed list names objects the
-- broker reported on (e.g. 404 on a blob that was already missing).
data GcExecutionResult = GcExecutionResult
  { gcExecutedReapedManifests :: Int
  , gcExecutedReapedBlobs :: Int
  , gcExecutedDeleteFailures :: [(Text, ServiceError)]
  }
  deriving stock (Eq, Show)

-- | Execute a `GcPlan` through the typed `HasMinIO` capability boundary.
-- For each reap event the executor calls `deleteObject` against the
-- manifest object key and each referenced blob key. Failed deletes are
-- recorded but do not short-circuit the loop (the broker may have already
-- garbage-collected a partial write); the executor returns the per-class
-- tally + failure list.
executeGcPlan :: (HasMinIO m) => GcPlan -> m GcExecutionResult
executeGcPlan plan =
  go 0 0 [] (gcReapEvents plan)
 where
  go reapedManifests reapedBlobs failures [] =
    pure
      GcExecutionResult
        { gcExecutedReapedManifests = reapedManifests
        , gcExecutedReapedBlobs = reapedBlobs
        , gcExecutedDeleteFailures = reverse failures
        }
  go reapedManifests reapedBlobs failures (event : rest) = do
    let manifestRef =
          checkpointObjectRef (manifestKey (gcExperimentHash event) (gcReapedManifestSha event))
    manifestResult <- deleteObject manifestRef
    let failuresAfterManifest =
          case manifestResult of
            Left err -> (manifestKey (gcExperimentHash event) (gcReapedManifestSha event), err) : failures
            Right () -> failures
    blobOutcomes <- traverse (deleteBlob (gcExperimentHash event)) (gcReapedBlobShas event)
    let blobFailures = [(k, err) | Left (k, err) <- blobOutcomes]
        deletedBlobCount = length [() | Right () <- blobOutcomes]
    go
      (reapedManifests + 1)
      (reapedBlobs + deletedBlobCount)
      (reverse blobFailures <> failuresAfterManifest)
      rest

  deleteBlob experimentHash blobSha = do
    let ref = checkpointObjectRef (blobKey experimentHash blobSha)
    outcome <- deleteObject ref
    case outcome of
      Left err -> pure (Left (blobKey experimentHash blobSha, err))
      Right () -> pure (Right ())

-- | Latest-pointer read path for callers that provide an explicit inference
-- runner after the manifest has been loaded. Production self-inference uses
-- `loadInferenceCheckpointWithWeights` so generated substrate kernels consume
-- decoded `.jmw1` weight tensors; this unweighted hook remains for explicit
-- injected runners and tests.
loadInferenceCheckpointWith
  :: (HasMinIO m)
  => (CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> Text
  -- ^ experiment hash
  -> [Double]
  -- ^ inference input
  -> m (Either Text [Double])
loadInferenceCheckpointWith runInference experimentHash input = do
  let pointerRef = checkpointObjectRef (latestPointerKey experimentHash)
  pointerResult <- minioReadObject pointerRef
  case pointerResult of
    Left err -> pure (Left ("pointer read failed: " <> Text.pack (show err)))
    Right rawPointer -> do
      let manifestSha = Text.strip rawPointer
          manifestRef = checkpointObjectRef (manifestKey experimentHash manifestSha)
      manifestPayload <- minioReadBytes manifestRef
      case manifestPayload of
        Left err -> pure (Left ("manifest read failed: " <> Text.pack (show err)))
        Right rawManifest ->
          case decodeManifestCbor (LazyByteString.fromStrict rawManifest) of
            Left err -> pure (Left ("manifest decode failed: " <> err))
            Right manifest ->
              case validateLoadedManifest experimentHash manifestSha manifest of
                Left err -> pure (Left err)
                Right validManifest ->
                  case requireInferenceEligibleCheckpoint manifestSha validManifest of
                    Left err ->
                      pure (Left ("manifest not inference eligible: " <> renderEligibilityError err))
                    Right eligible ->
                      let weightOnly =
                            (eligibleCheckpointManifest eligible)
                              { manifestOptimizer = []
                              , manifestRng = []
                              }
                          _ = weightOnlyTensors validManifest
                       in runInference weightOnly input

-- | Variant of `loadInferenceCheckpointWith` that also reads and decodes
-- weight-only `.jmw1` tensor blobs before invoking the supplied runner.
loadInferenceCheckpointWithWeights
  :: (HasMinIO m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> Text
  -- ^ experiment hash
  -> [Double]
  -- ^ inference input
  -> m (Either Text [Double])
loadInferenceCheckpointWithWeights runInference experimentHash input =
  withWeightedCheckpoint
    (\manifest weights -> runInference manifest weights input)
    experimentHash

-- | Sprint 11.10 — variant that, after running weighted inference, applies the
-- manifest's __output decoder__ in the Engine and returns the typed
-- 'DecodedInference' alongside the raw output. This is the single place output
-- decoding happens; the webapp and browser panels render the decoded value
-- without computing.
loadInferenceCheckpointDecodedWithWeights
  :: (HasMinIO m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> [Double] -> m (Either Text [Double]))
  -> Text
  -- ^ experiment hash
  -> [Double]
  -- ^ inference input
  -> m (Either Text ([Double], DecodedInference))
loadInferenceCheckpointDecodedWithWeights runInference experimentHash input =
  withWeightedCheckpoint
    ( \manifest weights ->
        fmap
          (fmap (\output -> (output, decodeManifestOutput manifest output)))
          (runInference manifest weights input)
    )
    experimentHash

-- | Shared core for the weighted-inference loaders: read + validate the latest
-- manifest, decode the weight-only tensors, and run a continuation with both.
withWeightedCheckpoint
  :: (HasMinIO m)
  => (CheckpointManifest -> [LoadedWeightTensor] -> m (Either Text a))
  -> Text
  -> m (Either Text a)
withWeightedCheckpoint continuation experimentHash = do
  let pointerRef = checkpointObjectRef (latestPointerKey experimentHash)
  pointerResult <- minioReadObject pointerRef
  case pointerResult of
    Left err -> pure (Left ("pointer read failed: " <> Text.pack (show err)))
    Right rawPointer -> do
      let manifestSha = Text.strip rawPointer
          manifestRef = checkpointObjectRef (manifestKey experimentHash manifestSha)
      manifestPayload <- minioReadBytes manifestRef
      case manifestPayload of
        Left err -> pure (Left ("manifest read failed: " <> Text.pack (show err)))
        Right rawManifest ->
          case decodeManifestCbor (LazyByteString.fromStrict rawManifest) of
            Left err -> pure (Left ("manifest decode failed: " <> err))
            Right manifest ->
              case validateLoadedManifest experimentHash manifestSha manifest of
                Left err -> pure (Left err)
                Right validManifest ->
                  case requireInferenceEligibleCheckpoint manifestSha validManifest of
                    Left err ->
                      pure (Left ("manifest not inference eligible: " <> renderEligibilityError err))
                    Right eligible -> do
                      let weightOnly =
                            (eligibleCheckpointManifest eligible)
                              { manifestOptimizer = []
                              , manifestRng = []
                              }
                      loadedWeights <- loadWeightTensors weightOnly
                      case loadedWeights of
                        Left err -> pure (Left err)
                        Right weights -> continuation weightOnly weights

loadWeightTensors
  :: (HasMinIO m)
  => CheckpointManifest
  -> m (Either Text [LoadedWeightTensor])
loadWeightTensors manifest = do
  loaded <- traverse loadOne (weightOnlyTensors manifest)
  pure (sequence loaded)
 where
  loadOne tensor = do
    payload <- minioReadBytes (checkpointObjectRef (tensorBlobKey tensor))
    pure $
      case payload of
        Left err ->
          Left
            ( "weight blob read failed for "
                <> tensorName tensor
                <> ": "
                <> Text.pack (show err)
            )
        Right bytes ->
          case decodeJmw1 (LazyByteString.fromStrict bytes) of
            Left err -> Left err
            Right values -> do
              validateTensorPayloadShape tensor values
              Right (LoadedWeightTensor tensor values)

validateLoadedManifest :: Text -> Text -> CheckpointManifest -> Either Text CheckpointManifest
validateLoadedManifest experimentHash manifestSha manifest
  | manifestExperiment manifest /= experimentHash =
      Left
        ( "manifest incompatible: experiment mismatch, requested "
            <> experimentHash
            <> " but manifest records "
            <> manifestExperiment manifest
        )
  | manifestContentSha manifest /= manifestSha =
      Left
        ( "manifest incompatible: content sha mismatch, pointer addressed "
            <> manifestSha
            <> " but body hashes to "
            <> manifestContentSha manifest
        )
  | null (manifestTensors manifest) =
      Left "manifest incompatible: no weight tensors"
  | otherwise =
      Right manifest

validateTensorPayloadShape :: TensorBlob -> [Double] -> Either Text ()
validateTensorPayloadShape tensor values
  | any (< 0) (tensorShape tensor) =
      Left ("weight blob incompatible for " <> tensorName tensor <> ": negative tensor dimension")
  | expected /= actual =
      Left
        ( "weight blob incompatible for "
            <> tensorName tensor
            <> ": expected "
            <> Text.pack (show expected)
            <> " values from shape "
            <> Text.pack (show (tensorShape tensor))
            <> ", got "
            <> Text.pack (show actual)
        )
  | otherwise =
      Right ()
 where
  expected = product (tensorShape tensor)
  actual = length values

checkpointObjectRef :: Text -> ObjectRef
checkpointObjectRef objectKey =
  ObjectRef (BucketName "jitml-checkpoints") (ObjectKey (checkpointObjectKey objectKey))

checkpointObjectKey :: Text -> Text
checkpointObjectKey objectKey =
  fromMaybe objectKey (Text.stripPrefix "jitml-checkpoints/" objectKey)

writeObjectIfAbsent
  :: FilePath -> Text -> LazyByteString.ByteString -> IO (Either Text ObjectWriteResult)
writeObjectIfAbsent root objectKey payload = do
  case objectPathForKey root objectKey of
    Left err ->
      pure (Left err)
    Right path -> do
      exists <- doesFileExist path
      if exists
        then pure (Right (ObjectAlreadyPresent objectKey))
        else do
          writeObjectAt path payload
          pure (Right (ObjectCreated objectKey))

readObject :: FilePath -> Text -> IO (Either Text LazyByteString.ByteString)
readObject root objectKey = do
  case objectPathForKey root objectKey of
    Left err ->
      pure (Left err)
    Right path -> do
      exists <- doesFileExist path
      if exists
        then Right <$> LazyByteString.readFile path
        else pure (Left ("missing object: " <> objectKey))

writeObject :: FilePath -> Text -> LazyByteString.ByteString -> IO (Either Text ())
writeObject root objectKey payload = do
  case objectPathForKey root objectKey of
    Left err ->
      pure (Left err)
    Right path -> do
      writeObjectAt path payload
      pure (Right ())

writeObjectAt :: FilePath -> LazyByteString.ByteString -> IO ()
writeObjectAt path payload = do
  let tmpPath = path <> ".tmp"
  createDirectoryIfMissing True (takeDirectory path)
  LazyByteString.writeFile tmpPath payload
  renameFile tmpPath path

objectPathForKey :: FilePath -> Text -> Either Text FilePath
objectPathForKey root objectKey =
  fmap (root </>) (safeRelativePath objectKey)

safeRelativePath :: Text -> Either Text FilePath
safeRelativePath objectKey =
  let rawPath = Text.unpack objectKey
      path = normalise rawPath
      rawSegments = splitPathSegments rawPath
   in if null rawPath
        || null path
        || path == "."
        || not (isRelative rawPath)
        || not (isRelative path)
        || ".." `elem` rawSegments
        then Left ("unsafe object key: " <> objectKey)
        else Right path

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

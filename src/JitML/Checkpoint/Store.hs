{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Store
  ( AdmittedCheckpoint
  , AdmittedCompletedCheckpoint
  , CheckpointAdmissionError (..)
  , CheckpointWriteError (..)
  , GcEvent (..)
  , GcExecutionResult (..)
  , GcPlan (..)
  , LoadedWeightTensor (..)
  , ObjectWriteResult (..)
  , RetentionPolicy (..)
  , StoredCandidateCheckpoint
  , StoredCheckpoint (..)
  , StoredCompletedCheckpoint
  , admitCheckpointAt
  , admitLatestCheckpoint
  , admitLatestCompletedCheckpoint
  , admitLocalCheckpointAt
  , admitLocalLatestCheckpoint
  , admittedCheckpointManifest
  , admittedCheckpointManifestBodySha
  , admittedCheckpointManifestSha
  , admittedCheckpointWeights
  , admittedCompletedCheckpoint
  , admittedCompletedTraining
  , applyRetentionPolicy
  , buildGcPlan
  , checkpointObjectKey
  , checkpointObjectRef
  , candidateStoredCheckpoint
  , completedStoredCheckpoint
  , executeGcPlan
  , listCheckpointManifests
  , listCheckpointManifestsMinIO
  , loadInferenceCheckpointWith
  , loadInferenceCheckpointWithWeights
  , loadInferenceCheckpointDecodedWithWeights
  , loadSupervisedRuntimeFromCheckpoint
  , layerGraphFromCheckpoint
  , objectPathForKey
  , readCheckpointManifest
  , readCheckpointPointer
  , readObject
  , renderCheckpointAdmissionError
  , renderCheckpointWriteError
  , requireAdmittedCompletedCheckpoint
  , walkLiveSet
  , writeCandidateCheckpointSnapshot
  , writeCandidateCheckpointSnapshotWithMinIO
  , writeCompletedCheckpointSnapshot
  , writeCompletedCheckpointSnapshotWithMinIO
  , writeObjectIfAbsent
  )
where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (IOException, bracket, bracket_, try)
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either.Combinators (mapLeft)
import Data.Foldable (traverse_)
import Data.List (group, nub, sort, sortOn)
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , doesPathExist
  , listDirectory
  , renameFile
  )
import System.FilePath (isRelative, normalise, takeDirectory, (</>))
import System.IO (SeekMode (AbsoluteSeek), hFlush)
import System.IO.Temp (withTempFile)
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.Files (createLink)
import System.Posix.IO
  ( LockRequest (Unlock, WriteLock)
  , OpenFileFlags (creat)
  , OpenMode (WriteOnly)
  , closeFd
  , defaultFileFlags
  , openFd
  , setLock
  , waitToSetLock
  )

import JitML.Checkpoint.Format
  ( AddressedCheckpointManifest
  , ArchitectureMetadata (..)
  , ArtifactPointer (..)
  , CheckpointManifest (..)
  , LayerGraphActivationMetadata (..)
  , LayerGraphKindMetadata (..)
  , LayerGraphMetadata (..)
  , LayerGraphModeMetadata (..)
  , LayerGraphNodeMetadata (..)
  , ModelFamily (..)
  , OptimizerBlob (..)
  , PointerWriteResult (..)
  , RngBlob (..)
  , SubstrateArtifact (..)
  , TensorBlob (..)
  , ValidatedCheckpointCompletion
  , addressedManifest
  , addressedManifestBodySha
  , addressedManifestSha
  , addressedManifestWireVersion
  , blobKey
  , checkpointWireVersion
  , checkpointWireVersionV2
  , decodeAddressedManifestCbor
  , decodeJmw1
  , encodeManifestCbor
  , latestPointerKey
  , manifestContentSha
  , manifestKey
  , renderCheckpointCompletionValidationError
  , validateCheckpointCompletion
  , validatedCheckpointCompletedTraining
  )
import JitML.Checkpoint.WeightCodec (encodeJmw1, jmw1ContentSha)
import JitML.Inference.Decode (DecodedInference, decodeManifestOutput)
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Training.Budget
  ( CompletedTraining
  , completedTrainingFinalWeightHash
  )

-- | Exact persisted checkpoint graph admitted by Store.  The constructor is
-- intentionally private: a decoded or caller-built manifest is not evidence
-- that these bytes occupied their declared immutable addresses.
data AdmittedCheckpoint = AdmittedCheckpoint
  { admittedAddressedManifestInternal :: AddressedCheckpointManifest
  , admittedCheckpointWeightsInternal :: [LoadedWeightTensor]
  }
  deriving stock (Eq, Show)

-- | A persisted admission whose completion witness was re-refined only after
-- pointer stability and physical-blob binding.  This is the sole value that
-- may cross into Product Pipeline inference eligibility.
data AdmittedCompletedCheckpoint = AdmittedCompletedCheckpoint
  { admittedCompletedCheckpointInternal :: AdmittedCheckpoint
  , admittedCompletionValidationInternal :: ValidatedCheckpointCompletion
  }
  deriving stock (Eq, Show)

-- | Typed failures for exact persisted-checkpoint admission.  In particular,
-- 'AdmissionPointerChanged' is retryable snapshot contention rather than a
-- malformed-manifest verdict.
data CheckpointAdmissionError
  = AdmissionPointerReadFailed Text ServiceError
  | AdmissionPointerMalformed Text
  | AdmissionPointerChanged Text Text
  | AdmissionManifestAddressMalformed Text
  | AdmissionManifestReadFailed Text ServiceError
  | AdmissionManifestInvalid Text
  | AdmissionManifestVersionUnsupported Word64
  | AdmissionCompletedV1ProductRowRequired Text
  | AdmissionCompletedV1CompanionInvalid Text
  | AdmissionStoredCheckpointMismatch Text
  | AdmissionBlobReadFailed Text ServiceError
  | AdmissionBlobInvalid Text
  | AdmissionCompletionInvalid Text
  deriving stock (Eq, Show)

-- | Local checkpoint persistence failures retain their semantic identity.
-- Immutable-object and pointer-CAS conflicts are deliberately separate from
-- invalid requests and filesystem failures so callers cannot mistake
-- contention for malformed checkpoint data.
data CheckpointWriteError
  = CheckpointWriteInvalid Text
  | CheckpointWriteObjectConflict Text Text
  | CheckpointWritePointerConflict Text
  | CheckpointWriteIOFailure Text Text
  deriving stock (Eq, Show)

admittedCheckpointManifest :: AdmittedCheckpoint -> CheckpointManifest
admittedCheckpointManifest =
  addressedManifest . admittedAddressedManifestInternal

admittedCheckpointManifestSha :: AdmittedCheckpoint -> Text
admittedCheckpointManifestSha =
  addressedManifestSha . admittedAddressedManifestInternal

admittedCheckpointManifestBodySha :: AdmittedCheckpoint -> Maybe Text
admittedCheckpointManifestBodySha =
  addressedManifestBodySha . admittedAddressedManifestInternal

admittedCheckpointWeights :: AdmittedCheckpoint -> [LoadedWeightTensor]
admittedCheckpointWeights = admittedCheckpointWeightsInternal

admittedCompletedCheckpoint :: AdmittedCompletedCheckpoint -> AdmittedCheckpoint
admittedCompletedCheckpoint = admittedCompletedCheckpointInternal

admittedCompletedTraining :: AdmittedCompletedCheckpoint -> CompletedTraining
admittedCompletedTraining =
  validatedCheckpointCompletedTraining . admittedCompletionValidationInternal

renderCheckpointAdmissionError :: CheckpointAdmissionError -> Text
renderCheckpointAdmissionError admissionError =
  case admissionError of
    AdmissionPointerReadFailed stage err ->
      stage <> " pointer read failed: " <> Text.pack (show err)
    AdmissionPointerMalformed reason ->
      "pointer body is not one canonical SHA-256 address: " <> reason
    AdmissionPointerChanged p1 p2 ->
      "latest pointer changed during manifest admission (exact P1="
        <> p1
        <> ", P2="
        <> p2
        <> "); retry admission"
    AdmissionManifestAddressMalformed reason ->
      "manifest address is not one canonical SHA-256 address: " <> reason
    AdmissionManifestReadFailed objectKey err ->
      "manifest read failed for " <> objectKey <> ": " <> Text.pack (show err)
    AdmissionManifestInvalid reason -> "manifest admission failed: " <> reason
    AdmissionManifestVersionUnsupported version ->
      "checkpoint admission requires canonical V1 or V2, got wire version "
        <> Text.pack (show version)
    AdmissionCompletedV1ProductRowRequired experimentHash ->
      "completed V1 admission requires a canonical non-supervised ProductRow experiment, got "
        <> experimentHash
    AdmissionCompletedV1CompanionInvalid reason ->
      "completed ProductRow V1 companion admission failed: " <> reason
    AdmissionStoredCheckpointMismatch reason ->
      "stored completed checkpoint admission mismatch: " <> reason
    AdmissionBlobReadFailed objectKey err ->
      "checkpoint blob read failed for " <> objectKey <> ": " <> Text.pack (show err)
    AdmissionBlobInvalid reason -> "checkpoint blob admission failed: " <> reason
    AdmissionCompletionInvalid reason ->
      "checkpoint completion admission failed: " <> reason

renderCheckpointWriteError :: CheckpointWriteError -> Text
renderCheckpointWriteError checkpointWriteError =
  case checkpointWriteError of
    CheckpointWriteInvalid reason ->
      "invalid checkpoint write: " <> reason
    CheckpointWriteObjectConflict objectKey reason ->
      "immutable object conflict at " <> objectKey <> ": " <> reason
    CheckpointWritePointerConflict pointerKey ->
      "checkpoint pointer CAS conflicted: " <> pointerKey
    CheckpointWriteIOFailure subject reason ->
      "checkpoint filesystem write failed for " <> subject <> ": " <> reason

data ObjectWriteResult
  = ObjectCreated Text
  | ObjectAlreadyPresent Text
  deriving stock (Eq, Show)

data StoredCheckpoint = StoredCheckpoint
  { storedManifestSha :: Text
  , storedManifestBodySha :: Maybe Text
  , storedManifestObjectKey :: Text
  , storedPointerResult :: PointerWriteResult
  }
  deriving stock (Eq, Show)

-- | Candidate persistence has no completion input and never updates the
-- inference-selected latest pointer.  The constructor is hidden so a generic
-- snapshot result cannot be relabelled as this transaction outcome.
newtype StoredCandidateCheckpoint = StoredCandidateCheckpoint
  { candidateStoredCheckpoint :: StoredCheckpoint
  }
  deriving stock (Eq, Show)

-- | Completed persistence requires an exact witness and exists only after its
-- latest-pointer CAS adopted the same manifest SHA.  The constructor is hidden.
newtype StoredCompletedCheckpoint = StoredCompletedCheckpoint
  { completedStoredCheckpoint :: StoredCheckpoint
  }
  deriving stock (Eq, Show)

-- | Persist an inspectable/resumable candidate without touching the
-- inference-selected latest pointer.
writeCandidateCheckpointSnapshot
  :: FilePath
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> IO (Either CheckpointWriteError StoredCandidateCheckpoint)
writeCandidateCheckpointSnapshot root manifest payloads =
  case validateCandidateSnapshot manifest payloads of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right () -> do
      stored <- writeSnapshotObjectsLocal root manifest payloads
      pure $
        fmap
          ( \snapshot ->
              StoredCandidateCheckpoint
                snapshot
                  { storedPointerResult =
                      PointerNotWritten
                        (latestPointerKey (manifestExperiment manifest))
                  }
          )
          stored

-- | Persist a completed checkpoint and adopt it through exact local CAS.  A
-- stale expectation is a failure and cannot inhabit 'StoredCompletedCheckpoint'.
writeCompletedCheckpointSnapshot
  :: FilePath
  -> CompletedTraining
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Maybe Text
  -> IO (Either CheckpointWriteError StoredCompletedCheckpoint)
writeCompletedCheckpointSnapshot root completed manifest payloads expectedPointer =
  case validateCompletedSnapshot completed manifest payloads of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right () -> do
      stored <- writeCompletedSnapshotAndPointerLocal root manifest payloads expectedPointer
      pure $ do
        snapshot <- stored
        case storedPointerResult snapshot of
          PointerWritten sha
            | sha == storedManifestSha snapshot ->
                Right (StoredCompletedCheckpoint snapshot)
            | otherwise ->
                Left
                  ( CheckpointWriteIOFailure
                      (latestPointerKey (manifestExperiment manifest))
                      "pointer acknowledged a different manifest"
                  )
          PointerConflict pointerKey ->
            Left (CheckpointWritePointerConflict pointerKey)
          PointerNotWritten pointerKey ->
            Left
              ( CheckpointWriteIOFailure
                  pointerKey
                  "completed checkpoint did not update its pointer"
              )

writeCandidateCheckpointSnapshotWithMinIO
  :: (HasMinIO m)
  => CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> m (Either ServiceError StoredCandidateCheckpoint)
writeCandidateCheckpointSnapshotWithMinIO manifest payloads =
  case validateCandidateSnapshot manifest payloads of
    Left err -> pure (Left (SETransient err))
    Right () -> do
      stored <- writeSnapshotObjectsMinIO manifest payloads
      pure $
        fmap
          ( \snapshot ->
              StoredCandidateCheckpoint
                snapshot
                  { storedPointerResult =
                      PointerNotWritten
                        (latestPointerKey (manifestExperiment manifest))
                  }
          )
          stored

writeCompletedCheckpointSnapshotWithMinIO
  :: (HasMinIO m)
  => Maybe ETag
  -> CompletedTraining
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> m (Either ServiceError StoredCompletedCheckpoint)
writeCompletedCheckpointSnapshotWithMinIO expectedPointer completed manifest payloads =
  case validateCompletedSnapshot completed manifest payloads of
    Left err -> pure (Left (SETransient err))
    Right () -> do
      stored <- writeCompletedSnapshotAndPointerMinIO manifest payloads expectedPointer
      pure $ do
        snapshot <- stored
        case storedPointerResult snapshot of
          PointerWritten sha
            | sha == storedManifestSha snapshot ->
                Right (StoredCompletedCheckpoint snapshot)
            | otherwise ->
                Left
                  (SETransient "completed checkpoint pointer acknowledged a different manifest")
          PointerConflict pointerKey ->
            Left (SEConflict ("completed checkpoint pointer CAS conflicted: " <> pointerKey))
          PointerNotWritten pointerKey ->
            Left (SETransient ("completed checkpoint did not update pointer: " <> pointerKey))

validateCandidateSnapshot
  :: CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Either Text ()
validateCandidateSnapshot manifest payloads = do
  case manifestCompletedTraining manifest of
    Nothing -> Right ()
    Just _ -> Left "candidate checkpoint cannot contain completed training"
  _ <- validateSnapshotPayloads manifest payloads
  Right ()

validateCompletedSnapshot
  :: CompletedTraining
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Either Text ()
validateCompletedSnapshot completed manifest payloads = do
  if manifestCompletedTraining manifest == Just completed
    then Right ()
    else Left "completed checkpoint manifest does not contain the required completion witness"
  let manifestBytes = encodeManifestCbor manifest
  _ <- decodeAddressedManifestCbor manifestBytes
  case validateCheckpointCompletion manifest of
    Left err ->
      Left
        ( "completed checkpoint is structurally invalid: "
            <> renderCheckpointCompletionValidationError err
        )
    Right _ -> Right ()
  weights <- validateSnapshotPayloads manifest payloads
  case validateBoundRuntimeAndCompletion manifest weights of
    Left err -> Left (renderCheckpointAdmissionError err)
    Right () -> Right ()

validateSnapshotPayloads
  :: CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Either Text [LoadedWeightTensor]
validateSnapshotPayloads manifest payloads = do
  case validatePhysicalDeclarations manifest of
    Left err -> Left (renderCheckpointAdmissionError err)
    Right () -> Right ()
  let rawBindings = physicalRawBlobBindings manifest
      expectedKeys =
        fmap tensorBlobKey (manifestTensors manifest)
          <> fmap (rawBlobObjectKey . fst) rawBindings
      providedKeys = fmap fst payloads
  case duplicateValues providedKeys of
    [] -> Right ()
    duplicates ->
      Left ("snapshot contains duplicate payload keys: " <> Text.intercalate ", " duplicates)
  if sort providedKeys == sort expectedKeys
    then Right ()
    else
      Left
        ( "snapshot payload keys do not exactly equal the manifest physical graph; expected "
            <> Text.pack (show (sort expectedKeys))
            <> ", got "
            <> Text.pack (show (sort providedKeys))
        )
  weights <-
    traverse
      ( \tensor -> do
          bytes <- lookupSnapshotPayload (tensorBlobKey tensor)
          decodeLoadedWeightTensor manifest tensor bytes
      )
      (manifestTensors manifest)
  traverse_
    ( \(binding, expectedLength) -> do
        bytes <- lookupSnapshotPayload (rawBlobObjectKey binding)
        case verifyRawBlobBinding manifest binding expectedLength bytes of
          Left err -> Left (renderCheckpointAdmissionError err)
          Right () -> Right ()
    )
    rawBindings
  Right weights
 where
  lookupSnapshotPayload objectKey =
    case lookup objectKey payloads of
      Nothing -> Left ("snapshot is missing payload " <> objectKey)
      Just bytes -> Right (LazyByteString.toStrict bytes)

writeSnapshotObjectsLocal
  :: FilePath
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> IO (Either CheckpointWriteError StoredCheckpoint)
writeSnapshotObjectsLocal root manifest payloads =
  case encodeAddressedManifest manifest of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right (manifestBytes, manifestSha, manifestBodySha) -> do
      payloadWrites <- traverse (uncurry (writeObjectIfAbsent root)) payloads
      case sequence payloadWrites of
        Left err -> pure (Left err)
        Right _ -> do
          let manifestObjectKey = manifestKey (manifestExperiment manifest) manifestSha
          manifestWrite <- writeObjectIfAbsent root manifestObjectKey manifestBytes
          pure $ do
            _ <- manifestWrite
            Right
              StoredCheckpoint
                { storedManifestSha = manifestSha
                , storedManifestBodySha = manifestBodySha
                , storedManifestObjectKey = manifestObjectKey
                , storedPointerResult =
                    PointerNotWritten (latestPointerKey (manifestExperiment manifest))
                }

writeSnapshotObjectsMinIO
  :: (HasMinIO m)
  => CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> m (Either ServiceError StoredCheckpoint)
writeSnapshotObjectsMinIO manifest payloads =
  case encodeAddressedManifest manifest of
    Left err -> pure (Left (SETransient err))
    Right (manifestBytes, manifestSha, manifestBodySha) -> do
      payloadWrites <-
        traverse
          ( \(objectKey, payload) ->
              putObjectBytesIfAbsentOrSame
                (checkpointObjectRef objectKey)
                (LazyByteString.toStrict payload)
          )
          payloads
      case sequence payloadWrites of
        Left err -> pure (Left err)
        Right _ -> do
          let manifestObjectKey = manifestKey (manifestExperiment manifest) manifestSha
          manifestWrite <-
            putObjectBytesIfAbsentOrSame
              (checkpointObjectRef manifestObjectKey)
              (LazyByteString.toStrict manifestBytes)
          pure $ do
            _ <- manifestWrite
            Right
              StoredCheckpoint
                { storedManifestSha = manifestSha
                , storedManifestBodySha = manifestBodySha
                , storedManifestObjectKey = manifestObjectKey
                , storedPointerResult =
                    PointerNotWritten (latestPointerKey (manifestExperiment manifest))
                }

data LoadedWeightTensor = LoadedWeightTensor
  { loadedWeightTensor :: TensorBlob
  , loadedWeightValues :: [Double]
  , loadedWeightJmw1Bytes :: StrictByteString.ByteString
  }
  deriving stock (Eq, Show)

writeCompletedSnapshotAndPointerLocal
  :: FilePath
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Maybe Text
  -> IO (Either CheckpointWriteError StoredCheckpoint)
writeCompletedSnapshotAndPointerLocal root manifest tensorPayloads expectedPointerETag =
  case encodeAddressedManifest manifest of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right (manifestBytes, manifestSha, manifestBodySha) -> do
      tensorWrites <- traverse (uncurry (writeObjectIfAbsent root)) tensorPayloads
      case sequence tensorWrites of
        Left err ->
          pure (Left err)
        Right _ -> do
          let manifestObjectKey = manifestKey (checkpointExperiment manifest) manifestSha
              pointerKey = latestPointerKey (checkpointExperiment manifest)
          manifestWrite <- writeObjectIfAbsent root manifestObjectKey manifestBytes
          case manifestWrite of
            Left err ->
              pure (Left err)
            Right _ -> do
              pointerWriteResult <-
                writePointerCasLocal
                  root
                  pointerKey
                  expectedPointerETag
                  manifestSha
              pure $ do
                pointerResult <- pointerWriteResult
                Right
                  StoredCheckpoint
                    { storedManifestSha = manifestSha
                    , storedManifestBodySha = manifestBodySha
                    , storedManifestObjectKey = manifestObjectKey
                    , storedPointerResult = pointerResult
                    }

-- | Checkpoint snapshot writer over the production `HasMinIO` capability
-- boundary. Split blobs and manifests are byte-faithful write-once objects;
-- the latest pointer advances through `casPointer`.
writeCompletedSnapshotAndPointerMinIO
  :: (HasMinIO m)
  => CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Maybe ETag
  -> m (Either ServiceError StoredCheckpoint)
writeCompletedSnapshotAndPointerMinIO manifest tensorPayloads expectedPointerETag =
  case encodeAddressedManifest manifest of
    Left err -> pure (Left (SETransient err))
    Right (manifestBytes, manifestSha, manifestBodySha) -> do
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
          let manifestObjectKey = manifestKey (checkpointExperiment manifest) manifestSha
              pointerKey = latestPointerKey (checkpointExperiment manifest)
          manifestWrite <-
            putObjectBytesIfAbsentOrSame
              (checkpointObjectRef manifestObjectKey)
              (LazyByteString.toStrict manifestBytes)
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
                        , storedManifestBodySha = manifestBodySha
                        , storedManifestObjectKey = manifestObjectKey
                        , storedPointerResult = PointerWritten manifestSha
                        }
                Left (SEConflict _) ->
                  pure $
                    Right
                      StoredCheckpoint
                        { storedManifestSha = manifestSha
                        , storedManifestBodySha = manifestBodySha
                        , storedManifestObjectKey = manifestObjectKey
                        , storedPointerResult = PointerConflict pointerKey
                        }
                Left err ->
                  pure (Left err)

encodeAddressedManifest
  :: CheckpointManifest
  -> Either Text (LazyByteString.ByteString, Text, Maybe Text)
encodeAddressedManifest manifest = do
  let manifestBytes = encodeManifestCbor manifest
  addressed <- decodeAddressedManifestCbor manifestBytes
  Right
    ( manifestBytes
    , addressedManifestSha addressed
    , addressedManifestBodySha addressed
    )

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
          pure
            ( Left
                ( SEConflict
                    ( "object exists but exact-byte comparison failed: "
                        <> Text.pack (show err)
                    )
                )
            )
    Left err ->
      pure (Left err)

-- | Admit the immutable checkpoint graph addressed by the exact current
-- latest-pointer body.  Blob I/O deliberately starts only after the second
-- pointer read proves that the manifest body was selected by one stable
-- pointer snapshot.
admitLatestCheckpoint
  :: (HasMinIO m)
  => Text
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
admitLatestCheckpoint = admitLatestCheckpointGated (const (Right ()))

-- | 'admitLatestCheckpoint' with a manifest-structural gate that runs on the
-- pointer-stable addressed manifest __before__ any physical blob I/O.  Generic
-- admission passes a no-op gate; the completed-checkpoint path threads the
-- completion-legality gate so an illegal completed manifest is rejected before
-- a weight or runner fetch.
admitLatestCheckpointGated
  :: (HasMinIO m)
  => (AddressedCheckpointManifest -> Either CheckpointAdmissionError ())
  -> Text
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
admitLatestCheckpointGated preBindGate experimentHash = do
  let pointerKey = latestPointerKey experimentHash
      pointerRef = checkpointObjectRef pointerKey
  p1Result <- minioReadBytes pointerRef
  case p1Result of
    Left err -> pure (Left (AdmissionPointerReadFailed "P1" err))
    Right p1Bytes ->
      case parseCanonicalPointerBody p1Bytes of
        Left err -> pure (Left err)
        Right manifestSha -> do
          addressedResult <- readAddressedCheckpoint experimentHash manifestSha
          case addressedResult of
            Left err -> pure (Left err)
            Right addressed -> do
              p2Result <- minioReadBytes pointerRef
              case p2Result of
                Left err -> pure (Left (AdmissionPointerReadFailed "P2" err))
                Right p2Bytes
                  | p1Bytes /= p2Bytes ->
                      pure
                        ( Left
                            ( AdmissionPointerChanged
                                (exactBytesSha p1Bytes)
                                (exactBytesSha p2Bytes)
                            )
                        )
                  | otherwise ->
                      case preBindGate addressed of
                        Left err -> pure (Left err)
                        Right () -> bindAddressedCheckpointMinIO addressed

-- | Known-address admission for immutable event/checkpoint identifiers.  It
-- applies the same exact manifest and physical-blob binding as latest
-- admission, but performs no pointer reads.
admitCheckpointAt
  :: (HasMinIO m)
  => Text
  -> Text
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
admitCheckpointAt experimentHash manifestSha = do
  case validateCanonicalManifestAddress manifestSha of
    Left err -> pure (Left err)
    Right canonicalManifestSha -> do
      addressedResult <- readAddressedCheckpoint experimentHash canonicalManifestSha
      case addressedResult of
        Left err -> pure (Left err)
        Right addressed -> bindAddressedCheckpointMinIO addressed

admitLatestCompletedCheckpoint
  :: (HasMinIO m)
  => Text
  -> m (Either CheckpointAdmissionError AdmittedCompletedCheckpoint)
admitLatestCompletedCheckpoint experimentHash = do
  admitted <- admitLatestCheckpointGated completionStructuralGate experimentHash
  pure (admitted >>= requireAdmittedCompletedCheckpoint)

-- | Manifest-structural completion legality, evaluated on the addressed
-- manifest before any physical blob I/O.  An illegal completed-checkpoint
-- manifest (no completed-training witness, inspection-only supervised V1,
-- missing weight-delta evidence, ...) is a pure property of the manifest, so it
-- is rejected here before a weight or runner fetch.  Structurally legal
-- manifests still undergo the full physical binding and the exact
-- 'requireAdmittedCompletedCheckpoint' refinement, so this never admits a
-- manifest that refinement would reject.
completionStructuralGate
  :: AddressedCheckpointManifest -> Either CheckpointAdmissionError ()
completionStructuralGate addressed =
  case validateCheckpointCompletion (addressedManifest addressed) of
    Left err ->
      Left (AdmissionCompletionInvalid (renderCheckpointCompletionValidationError err))
    Right _ -> Right ()

readAddressedCheckpoint
  :: (HasMinIO m)
  => Text
  -> Text
  -> m (Either CheckpointAdmissionError AddressedCheckpointManifest)
readAddressedCheckpoint experimentHash manifestSha = do
  let objectKey = manifestKey experimentHash manifestSha
  payload <- minioReadBytes (checkpointObjectRef objectKey)
  pure $
    case payload of
      Left err -> Left (AdmissionManifestReadFailed objectKey err)
      Right bytes ->
        decodeAddressedForAdmission
          experimentHash
          manifestSha
          (LazyByteString.fromStrict bytes)

bindAddressedCheckpointMinIO
  :: (HasMinIO m)
  => AddressedCheckpointManifest
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
bindAddressedCheckpointMinIO =
  bindAddressedCheckpointWith
    ( \objectKey -> do
        payload <- minioReadBytes (checkpointObjectRef objectKey)
        pure $
          case payload of
            Left err -> Left (AdmissionBlobReadFailed objectKey err)
            Right bytes -> Right bytes
    )

-- | Filesystem analogue of 'admitLatestCheckpoint'.  It exists for local
-- writers and deterministic race/tamper tests; its snapshot ordering and exact
-- byte checks are identical to the MinIO capability path.
admitLocalLatestCheckpoint
  :: FilePath
  -> Text
  -> IO (Either CheckpointAdmissionError AdmittedCheckpoint)
admitLocalLatestCheckpoint root experimentHash = do
  let pointerKey = latestPointerKey experimentHash
  p1Result <- readObjectStrict root pointerKey
  case p1Result of
    Left err -> pure (Left (AdmissionPointerReadFailed "P1" (SETransient err)))
    Right p1Bytes ->
      case parseCanonicalPointerBody p1Bytes of
        Left err -> pure (Left err)
        Right manifestSha -> do
          let objectKey = manifestKey experimentHash manifestSha
          manifestResult <- readObject root objectKey
          case manifestResult of
            Left err ->
              pure
                ( Left
                    (AdmissionManifestReadFailed objectKey (SETransient err))
                )
            Right bytes ->
              case decodeAddressedForAdmission experimentHash manifestSha bytes of
                Left err -> pure (Left err)
                Right addressed -> do
                  p2Result <- readObjectStrict root pointerKey
                  case p2Result of
                    Left err ->
                      pure (Left (AdmissionPointerReadFailed "P2" (SETransient err)))
                    Right p2Bytes
                      | p1Bytes /= p2Bytes ->
                          pure
                            ( Left
                                ( AdmissionPointerChanged
                                    (exactBytesSha p1Bytes)
                                    (exactBytesSha p2Bytes)
                                )
                            )
                      | otherwise -> bindAddressedCheckpointLocal root addressed

admitLocalCheckpointAt
  :: FilePath
  -> Text
  -> Text
  -> IO (Either CheckpointAdmissionError AdmittedCheckpoint)
admitLocalCheckpointAt root experimentHash manifestSha = do
  case validateCanonicalManifestAddress manifestSha of
    Left err -> pure (Left err)
    Right canonicalManifestSha -> do
      let objectKey = manifestKey experimentHash canonicalManifestSha
      manifestResult <- readObject root objectKey
      case manifestResult of
        Left err ->
          pure (Left (AdmissionManifestReadFailed objectKey (SETransient err)))
        Right bytes ->
          case decodeAddressedForAdmission experimentHash canonicalManifestSha bytes of
            Left err -> pure (Left err)
            Right addressed -> bindAddressedCheckpointLocal root addressed

bindAddressedCheckpointLocal
  :: FilePath
  -> AddressedCheckpointManifest
  -> IO (Either CheckpointAdmissionError AdmittedCheckpoint)
bindAddressedCheckpointLocal root =
  bindAddressedCheckpointWith
    ( \objectKey -> do
        payload <- readObjectStrict root objectKey
        pure $
          case payload of
            Left err -> Left (AdmissionBlobReadFailed objectKey (SETransient err))
            Right bytes -> Right bytes
    )

readObjectStrict :: FilePath -> Text -> IO (Either Text StrictByteString.ByteString)
readObjectStrict root objectKey =
  fmap (fmap LazyByteString.toStrict) (readObject root objectKey)

parseCanonicalPointerBody
  :: StrictByteString.ByteString
  -> Either CheckpointAdmissionError Text
parseCanonicalPointerBody bytes =
  case Text.Encoding.decodeUtf8' bytes of
    Left err -> Left (AdmissionPointerMalformed (Text.pack (show err)))
    Right pointerBody
      | Text.length pointerBody /= 64 ->
          Left
            ( AdmissionPointerMalformed
                ( "expected 64 lowercase hexadecimal characters, got length "
                    <> Text.pack (show (Text.length pointerBody))
                )
            )
      | Text.all isLowerHex pointerBody -> Right pointerBody
      | otherwise ->
          Left
            ( AdmissionPointerMalformed
                "address contains whitespace, uppercase, or non-hexadecimal bytes"
            )
 where
  isLowerHex character =
    character `elem` ("0123456789abcdef" :: String)

validateCanonicalManifestAddress
  :: Text
  -> Either CheckpointAdmissionError Text
validateCanonicalManifestAddress manifestSha =
  case parseCanonicalPointerBody (Text.Encoding.encodeUtf8 manifestSha) of
    Left (AdmissionPointerMalformed reason) ->
      Left (AdmissionManifestAddressMalformed reason)
    Left other -> Left other
    Right canonicalManifestSha -> Right canonicalManifestSha

decodeAddressedForAdmission
  :: Text
  -> Text
  -> LazyByteString.ByteString
  -> Either CheckpointAdmissionError AddressedCheckpointManifest
decodeAddressedForAdmission experimentHash expectedManifestSha bytes = do
  addressed <-
    case decodeAddressedManifestCbor bytes of
      Left err -> Left (AdmissionManifestInvalid err)
      Right value -> Right value
  let manifest = addressedManifest addressed
      wireVersion = addressedManifestWireVersion addressed
  if wireVersion == checkpointWireVersion
    || wireVersion == checkpointWireVersionV2
    then Right ()
    else Left (AdmissionManifestVersionUnsupported wireVersion)
  case validateLoadedManifest
    experimentHash
    expectedManifestSha
    (addressedManifestSha addressed)
    manifest of
    Left err -> Left (AdmissionManifestInvalid err)
    Right _ -> Right addressed

bindAddressedCheckpointWith
  :: (Monad m)
  => (Text -> m (Either CheckpointAdmissionError StrictByteString.ByteString))
  -> AddressedCheckpointManifest
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
bindAddressedCheckpointWith fetch addressed = do
  let manifest = addressedManifest addressed
  case validatePhysicalDeclarations manifest of
    Left err -> pure (Left err)
    Right () -> do
      loadedWeightResults <-
        traverse
          ( \tensor -> do
              payload <- fetch (tensorBlobKey tensor)
              pure $
                payload >>= \bytes ->
                  mapAdmissionBlobError
                    (decodeLoadedWeightTensor manifest tensor bytes)
          )
          (manifestTensors manifest)
      case sequence loadedWeightResults of
        Left err -> pure (Left err)
        Right weights -> do
          rawResults <-
            traverse
              (uncurry fetchAndVerifyRawBlob)
              (physicalRawBlobBindings manifest)
          case sequence rawResults of
            Left err -> pure (Left err)
            Right _ ->
              case validateBoundRuntimeAndCompletion manifest weights of
                Left err -> pure (Left err)
                Right () ->
                  pure
                    ( Right
                        AdmittedCheckpoint
                          { admittedAddressedManifestInternal = addressed
                          , admittedCheckpointWeightsInternal = weights
                          }
                    )
 where
  fetchAndVerifyRawBlob binding expectedLength = do
    payload <- fetch (rawBlobObjectKey binding)
    pure $ do
      bytes <- payload
      verifyRawBlobBinding
        (addressedManifest addressed)
        binding
        expectedLength
        bytes

data RawBlobBinding = RawBlobBinding
  { rawBlobLabel :: Text
  , rawBlobObjectKey :: Text
  , rawBlobExpectedSha :: Maybe Text
  }

physicalRawBlobBindings :: CheckpointManifest -> [(RawBlobBinding, Maybe Int)]
physicalRawBlobBindings manifest =
  fmap
    ( \optimizer ->
        ( RawBlobBinding
            { rawBlobLabel = "optimizer " <> optimizerKind optimizer
            , rawBlobObjectKey = optimizerBlobKey optimizer
            , rawBlobExpectedSha = Nothing
            }
        , Just (optimizerStateSize optimizer)
        )
    )
    (manifestOptimizer manifest)
    <> fmap
      ( \rng ->
          ( RawBlobBinding
              { rawBlobLabel = "RNG stream " <> rngStreamId rng
              , rawBlobObjectKey = rngBlobKey rng
              , rawBlobExpectedSha = Nothing
              }
          , Just (rngWordCount rng * 8)
          )
      )
      (manifestRng manifest)
    <> fmap artifactBinding (manifestReplayPointers manifest)
    <> fmap artifactBinding (manifestTranscriptPointers manifest)
    <> [ ( RawBlobBinding
             { rawBlobLabel =
                 "substrate artifact "
                   <> substrateArtifactSubstrate artifact
                   <> "/"
                   <> substrateArtifactKind artifact
             , rawBlobObjectKey = objectKey
             , rawBlobExpectedSha = Just (substrateArtifactCacheKey artifact)
             }
         , Nothing
         )
       | artifact <- manifestSubstrateArtifacts manifest
       , Just objectKey <- [substrateArtifactObjectKey artifact]
       ]
 where
  artifactBinding pointer =
    ( RawBlobBinding
        { rawBlobLabel = "artifact " <> artifactPointerKind pointer
        , rawBlobObjectKey = artifactPointerObjectKey pointer
        , rawBlobExpectedSha = artifactPointerSha pointer
        }
    , Nothing
    )

validatePhysicalDeclarations
  :: CheckpointManifest -> Either CheckpointAdmissionError ()
validatePhysicalDeclarations manifest = do
  requireUnique "tensor name" (fmap tensorName (manifestTensors manifest))
  requireUnique "physical object key" allObjectKeys
  traverse_ requireOptimizerSize (manifestOptimizer manifest)
  traverse_ requireRngSize (manifestRng manifest)
  traverse_
    requireArtifactSha
    (manifestReplayPointers manifest <> manifestTranscriptPointers manifest)
 where
  allObjectKeys =
    fmap tensorBlobKey (manifestTensors manifest)
      <> fmap optimizerBlobKey (manifestOptimizer manifest)
      <> fmap rngBlobKey (manifestRng manifest)
      <> fmap
        artifactPointerObjectKey
        (manifestReplayPointers manifest <> manifestTranscriptPointers manifest)
      <> [ key
         | artifact <- manifestSubstrateArtifacts manifest
         , Just key <- [substrateArtifactObjectKey artifact]
         ]

  requireUnique label values =
    case duplicateValues values of
      [] -> Right ()
      duplicates ->
        Left
          ( AdmissionBlobInvalid
              ( "duplicate "
                  <> label
                  <> " declarations: "
                  <> Text.intercalate ", " duplicates
              )
          )

  requireOptimizerSize optimizer
    | optimizerStateSize optimizer < 0 =
        Left
          ( AdmissionBlobInvalid
              ("negative optimizer byte length for " <> optimizerKind optimizer)
          )
    | otherwise = Right ()

  requireRngSize rng
    | rngWordCount rng < 0 =
        Left
          ( AdmissionBlobInvalid
              ("negative RNG word count for " <> rngStreamId rng)
          )
    | rngWordCount rng > maxBound `div` 8 =
        Left
          ( AdmissionBlobInvalid
              ("RNG byte length overflows Int for " <> rngStreamId rng)
          )
    | otherwise = Right ()

  requireArtifactSha pointer =
    case artifactPointerSha pointer of
      Nothing ->
        Left
          ( AdmissionBlobInvalid
              ( "artifact pointer has no exact content SHA-256: "
                  <> artifactPointerKind pointer
              )
          )
      Just _ -> Right ()

duplicateValues :: [Text] -> [Text]
duplicateValues values =
  [ value
  | value : _ : _ <- group (sort values)
  ]

verifyRawBlobBinding
  :: CheckpointManifest
  -> RawBlobBinding
  -> Maybe Int
  -> StrictByteString.ByteString
  -> Either CheckpointAdmissionError ()
verifyRawBlobBinding manifest binding expectedLength bytes = do
  let actualSha = exactBytesSha bytes
      canonicalKey = blobKey (manifestExperiment manifest) actualSha
  case rawBlobExpectedSha binding of
    Nothing ->
      if rawBlobObjectKey binding == canonicalKey
        then Right ()
        else
          Left
            ( AdmissionBlobInvalid
                ( rawBlobLabel binding
                    <> " key does not address its exact fetched bytes: expected "
                    <> canonicalKey
                    <> ", got "
                    <> rawBlobObjectKey binding
                )
            )
    Just expectedSha ->
      if expectedSha == actualSha
        then Right ()
        else
          Left
            ( AdmissionBlobInvalid
                ( rawBlobLabel binding
                    <> " SHA-256 mismatch: expected "
                    <> expectedSha
                    <> ", got "
                    <> actualSha
                )
            )
  case expectedLength of
    Nothing -> Right ()
    Just expected
      | StrictByteString.length bytes == expected -> Right ()
      | otherwise ->
          Left
            ( AdmissionBlobInvalid
                ( rawBlobLabel binding
                    <> " byte-length mismatch: expected "
                    <> Text.pack (show expected)
                    <> ", got "
                    <> Text.pack (show (StrictByteString.length bytes))
                )
            )

validateBoundRuntimeAndCompletion
  :: CheckpointManifest
  -> [LoadedWeightTensor]
  -> Either CheckpointAdmissionError ()
validateBoundRuntimeAndCompletion manifest weights = do
  case loadSupervisedRuntimeFromCheckpoint manifest weights of
    Left err -> Left (AdmissionBlobInvalid err)
    Right _ -> Right ()
  case manifestCompletedTraining manifest of
    Nothing -> Right ()
    Just completed ->
      case weights of
        [loaded]
          | exactBytesSha (loadedWeightJmw1Bytes loaded)
              == completedTrainingFinalWeightHash completed ->
              Right ()
          | otherwise ->
              Left
                ( AdmissionBlobInvalid
                    "exact fetched weight bytes do not match completed training final-weight SHA-256"
                )
        _ ->
          Left
            ( AdmissionBlobInvalid
                "completed checkpoint admission requires one exact physical final-weight vector"
            )

mapAdmissionBlobError :: Either Text a -> Either CheckpointAdmissionError a
mapAdmissionBlobError =
  mapLeft AdmissionBlobInvalid

requireAdmittedCompletedCheckpoint
  :: AdmittedCheckpoint
  -> Either CheckpointAdmissionError AdmittedCompletedCheckpoint
requireAdmittedCompletedCheckpoint admitted = do
  validateCompletedAdmissionScope admitted
  case validateCheckpointCompletion (admittedCheckpointManifest admitted) of
    Left err ->
      Left
        ( AdmissionCompletionInvalid
            (renderCheckpointCompletionValidationError err)
        )
    Right validation ->
      Right
        AdmittedCompletedCheckpoint
          { admittedCompletedCheckpointInternal = admitted
          , admittedCompletionValidationInternal = validation
          }

-- | V1 remains the canonical completed wire format for the non-supervised
-- ProductRow writers (RL, AlphaZero, and tuning). Exact Store admission may
-- bind any canonical V1 object graph for inspection, but only an authoritative
-- ProductRow identity with its exact family companion may proceed to structural
-- completion refinement.
-- Historical and generic supervised V1 then fails that refinement because it
-- lacks the exact V2 runtime artifact; only non-supervised ProductRows can
-- therefore inhabit 'AdmittedCompletedCheckpoint'.
validateCompletedAdmissionScope
  :: AdmittedCheckpoint
  -> Either CheckpointAdmissionError ()
validateCompletedAdmissionScope admitted =
  case addressedManifestWireVersion
    (admittedAddressedManifestInternal admitted) of
    wireVersion
      | wireVersion == checkpointWireVersion ->
          case ProductMatrix.productRowForExperimentHash experimentHash of
            Just row
              | ProductMatrix.family row == ProductMatrix.Supervised -> Right ()
              | otherwise ->
                  validateCompletedV1ProductCompanion
                    row
                    (admittedCheckpointManifest admitted)
            Nothing -> Left (AdmissionCompletedV1ProductRowRequired experimentHash)
      | wireVersion == checkpointWireVersionV2 -> Right ()
      | otherwise -> Left (AdmissionManifestVersionUnsupported wireVersion)
 where
  experimentHash =
    manifestExperiment (admittedCheckpointManifest admitted)

-- | A canonical non-supervised ProductRow V1 is completion-admissible only
-- when its one family-owned companion is part of the exact persisted graph.
-- Store performs this check after physical binding, so the pointer's declared
-- SHA has already been compared with the fetched bytes; this refinement also
-- fixes the semantic kind and canonical Product artifact address.
validateCompletedV1ProductCompanion
  :: ProductMatrix.ProductRow state
  -> CheckpointManifest
  -> Either CheckpointAdmissionError ()
validateCompletedV1ProductCompanion row manifest = do
  (expectedKind, expectedModelFamily) <-
    case ProductMatrix.family row of
      ProductMatrix.ReinforcementLearning ->
        Right ("rl-trajectory", ReinforcementLearningPolicyFamily)
      ProductMatrix.AlphaZero ->
        Right ("alphazero-transcript", AlphaZeroPolicyValueFamily)
      ProductMatrix.Tuning ->
        Right ("tune-trials", HyperparameterTuningFamily)
      ProductMatrix.Supervised ->
        Left
          ( AdmissionCompletedV1CompanionInvalid
              "supervised ProductRows require the exact V2 runtime and cannot use Product V1 companion admission"
          )
  if manifestModelFamily manifest == expectedModelFamily
    then Right ()
    else
      Left
        ( AdmissionCompletedV1CompanionInvalid
            ( "manifest model family for "
                <> ProductMatrix.rowId row
                <> " does not match its canonical ProductRow family: expected "
                <> Text.pack (show expectedModelFamily)
                <> ", got "
                <> Text.pack (show (manifestModelFamily manifest))
            )
        )
  if architectureModelFamily (manifestArchitecture manifest) == expectedModelFamily
    then Right ()
    else
      Left
        ( AdmissionCompletedV1CompanionInvalid
            ( "manifest architecture family for "
                <> ProductMatrix.rowId row
                <> " does not match its canonical ProductRow family: expected "
                <> Text.pack (show expectedModelFamily)
                <> ", got "
                <> Text.pack
                  (show (architectureModelFamily (manifestArchitecture manifest)))
            )
        )
  case manifestReplayPointers manifest of
    [] -> Right ()
    pointers ->
      Left
        ( AdmissionCompletedV1CompanionInvalid
            ( "expected no replay pointers for "
                <> ProductMatrix.rowId row
                <> ", got "
                <> Text.pack (show (length pointers))
            )
        )
  pointer <-
    case manifestTranscriptPointers manifest of
      [value] -> Right value
      values ->
        Left
          ( AdmissionCompletedV1CompanionInvalid
              ( "expected exactly one "
                  <> expectedKind
                  <> " transcript pointer for "
                  <> ProductMatrix.rowId row
                  <> ", got "
                  <> Text.pack (show (length values))
              )
          )
  if artifactPointerKind pointer == expectedKind
    then Right ()
    else
      Left
        ( AdmissionCompletedV1CompanionInvalid
            ( "expected companion kind "
                <> expectedKind
                <> " for "
                <> ProductMatrix.rowId row
                <> ", got "
                <> artifactPointerKind pointer
            )
        )
  pointerSha <-
    case artifactPointerSha pointer of
      Just value -> Right value
      Nothing ->
        Left
          ( AdmissionCompletedV1CompanionInvalid
              ("companion pointer has no exact SHA-256 for " <> ProductMatrix.rowId row)
          )
  let expectedObjectKey =
        canonicalProductCompanionObjectKey
          (manifestExperiment manifest)
          expectedKind
          pointerSha
  if artifactPointerObjectKey pointer == expectedObjectKey
    then Right ()
    else
      Left
        ( AdmissionCompletedV1CompanionInvalid
            ( "companion object key for "
                <> ProductMatrix.rowId row
                <> " is not its canonical content address: expected "
                <> expectedObjectKey
                <> ", got "
                <> artifactPointerObjectKey pointer
            )
        )

canonicalProductCompanionObjectKey :: Text -> Text -> Text -> Text
canonicalProductCompanionObjectKey experimentHash kind sha =
  "jitml-checkpoints/"
    <> experimentHash
    <> "/artifacts/"
    <> kind
    <> "/"
    <> sha
    <> ".txt"

exactBytesSha :: StrictByteString.ByteString -> Text
exactBytesSha =
  jmw1ContentSha . LazyByteString.fromStrict

readCheckpointManifest :: FilePath -> Text -> Text -> IO (Either Text CheckpointManifest)
readCheckpointManifest root experimentHash manifestSha = do
  payload <- readObject root (manifestKey experimentHash manifestSha)
  pure $ do
    bytes <- payload
    addressed <- decodeAddressedManifestCbor bytes
    validateAddressedManifest
      experimentHash
      manifestSha
      (addressedManifestSha addressed)
      (addressedManifest addressed)

readCheckpointPointer :: FilePath -> Text -> IO (Either Text (Maybe Text))
readCheckpointPointer root pointerKey = do
  case objectPathForKey root pointerKey of
    Left err ->
      pure (Left err)
    Right path -> do
      exists <- doesFileExist path
      if exists
        then do
          payloadResult <-
            try (LazyByteString.readFile path)
              :: IO (Either IOException LazyByteString.ByteString)
          pure $ do
            payload <-
              case payloadResult of
                Left err -> Left ("pointer read failed: " <> Text.pack (show err))
                Right value -> Right value
            case parseCanonicalPointerBody (LazyByteString.toStrict payload) of
              Left err -> Left (renderCheckpointAdmissionError err)
              Right manifestSha -> Right (Just manifestSha)
        else pure (Right Nothing)

-- | Cross-process local compare-and-swap.  The advisory lock covers the exact
-- read/compare/atomic-rename interval, so two jitML writers cannot both win
-- from the same expected pointer body.
writePointerCasLocal
  :: FilePath
  -> Text
  -> Maybe Text
  -> Text
  -> IO (Either CheckpointWriteError PointerWriteResult)
writePointerCasLocal root pointerKey expectedManifestSha proposedManifestSha =
  case objectPathForKey root pointerKey of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right pointerPath -> do
      outcome <-
        try
          ( withMVar localPointerCasProcessLock $ \() -> do
              createDirectoryIfMissing True (takeDirectory pointerPath)
              let lockPath = pointerPath <> ".lock"
                  lock = (WriteLock, AbsoluteSeek, 0, 0)
              bracket
                (openFd lockPath WriteOnly defaultFileFlags {creat = Just 0o600})
                closeFd
                ( \lockFd ->
                    bracket_
                      (waitToSetLock lockFd lock)
                      (setLock lockFd (Unlock, AbsoluteSeek, 0, 0))
                      ( do
                          currentResult <- readPointerForCas pointerKey pointerPath
                          case currentResult of
                            Left err -> pure (Left err)
                            Right currentManifestSha
                              | currentManifestSha /= expectedManifestSha ->
                                  pure (Left (CheckpointWritePointerConflict pointerKey))
                              | otherwise -> do
                                  writeObjectAt
                                    pointerPath
                                    ( LazyByteString.fromStrict
                                        (Text.Encoding.encodeUtf8 proposedManifestSha)
                                    )
                                  pure (Right (PointerWritten proposedManifestSha))
                      )
                )
          )
          :: IO
               ( Either
                   IOException
                   (Either CheckpointWriteError PointerWriteResult)
               )
      pure $
        case outcome of
          Left err ->
            Left
              ( CheckpointWriteIOFailure
                  pointerKey
                  (Text.pack (show err))
              )
          Right result -> result

-- POSIX record locks are process-scoped and therefore do not serialize two
-- Haskell threads in this process.  This mutex supplies that missing level;
-- the per-pointer fcntl lock still serializes independent jitML processes.
localPointerCasProcessLock :: MVar ()
localPointerCasProcessLock = unsafePerformIO (newMVar ())
{-# NOINLINE localPointerCasProcessLock #-}

readPointerForCas
  :: Text
  -> FilePath
  -> IO (Either CheckpointWriteError (Maybe Text))
readPointerForCas pointerKey pointerPath = do
  exists <- doesPathExist pointerPath
  if not exists
    then pure (Right Nothing)
    else do
      payloadResult <-
        try (StrictByteString.readFile pointerPath)
          :: IO (Either IOException StrictByteString.ByteString)
      pure $ do
        payload <-
          case payloadResult of
            Left err ->
              Left
                ( CheckpointWriteIOFailure
                    pointerKey
                    ("pointer read failed: " <> Text.pack (show err))
                )
            Right value -> Right value
        case parseCanonicalPointerBody payload of
          Left err ->
            Left
              ( CheckpointWriteInvalid
                  ("current pointer is malformed: " <> renderCheckpointAdmissionError err)
              )
          Right manifestSha -> Right (Just manifestSha)

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
    pure $ do
      expectedSha <-
        case Text.stripSuffix ".cbor" (Text.pack entry) of
          Nothing -> Left ("invalid manifest filename: " <> Text.pack entry)
          Just sha -> Right sha
      addressed <- decodeAddressedManifestCbor payload
      validateAddressedManifest
        experimentHash
        expectedSha
        (addressedManifestSha addressed)
        (addressedManifest addressed)

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
        case decodeAddressedManifestCbor (LazyByteString.fromStrict payload) of
          Left err ->
            pure
              ( Left
                  ( SETransient
                      ( "decodeAddressedManifestCbor failed for "
                          <> Text.pack (show ref)
                          <> ": "
                          <> err
                      )
                  )
              )
          Right addressed ->
            pure $ do
              expectedSha <-
                manifestShaFromObjectRef
                  (experimentHash <> "/manifests/")
                  ref
              let validation =
                    validateAddressedManifest
                      experimentHash
                      expectedSha
                      (addressedManifestSha addressed)
                      (addressedManifest addressed)
              case validation of
                Left err -> Left (SETransient err)
                Right manifest -> Right manifest

  manifestShaFromObjectRef prefixText ref = do
    relative <-
      case Text.stripPrefix prefixText (unObjectKey (objectKey ref)) of
        Nothing ->
          Left
            ( SETransient
                ( "manifest object is outside requested prefix: "
                    <> unObjectKey (objectKey ref)
                )
            )
        Just value -> Right value
    case Text.stripSuffix ".cbor" relative of
      Nothing ->
        Left
          ( SETransient
              ("invalid manifest object key: " <> unObjectKey (objectKey ref))
          )
      Just sha -> Right sha

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
  => (AdmittedCompletedCheckpoint -> CheckpointManifest -> [Double] -> m (Either Text [Double]))
  -> Text
  -- ^ experiment hash
  -> [Double]
  -- ^ inference input
  -> m (Either Text [Double])
loadInferenceCheckpointWith runInference experimentHash input = do
  admission <- admitLatestCompletedCheckpoint experimentHash
  case admission of
    Left err -> pure (Left (renderCheckpointAdmissionError err))
    Right admitted ->
      let manifest =
            admittedCheckpointManifest
              (admittedCompletedCheckpoint admitted)
       in case manifestSupervisedRuntime manifest of
            Just _ ->
              pure
                ( Left
                    "V2 supervised inference requires the exact weighted runtime loader"
                )
            Nothing -> runInference admitted manifest input

-- | Variant of `loadInferenceCheckpointWith` that also reads and decodes
-- weight-only `.jmw1` tensor blobs before invoking the supplied runner.
loadInferenceCheckpointWithWeights
  :: (HasMinIO m)
  => ( AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> Text
  -- ^ experiment hash
  -> [Double]
  -- ^ inference input
  -> m (Either Text [Double])
loadInferenceCheckpointWithWeights runInference experimentHash input =
  withWeightedCheckpoint
    (\modelRef manifest weights -> runInference modelRef manifest weights input)
    experimentHash

-- | Sprint 11.10 — variant that, after running weighted inference, applies the
-- manifest's __output decoder__ in the Engine and returns the typed
-- 'DecodedInference' alongside the raw output. This is the single place output
-- decoding happens; the webapp and browser panels render the decoded value
-- without computing.
loadInferenceCheckpointDecodedWithWeights
  :: (HasMinIO m)
  => ( AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> Text
  -- ^ experiment hash
  -> [Double]
  -- ^ inference input
  -> m (Either Text ([Double], DecodedInference))
loadInferenceCheckpointDecodedWithWeights runInference experimentHash input =
  withWeightedCheckpoint
    ( \modelRef manifest weights ->
        fmap
          (fmap (\output -> (output, decodeManifestOutput manifest output)))
          (runInference modelRef manifest weights input)
    )
    experimentHash

-- | Shared core for the weighted-inference loaders: read + validate the latest
-- manifest, decode the weight-only tensors, and run a continuation with both.
withWeightedCheckpoint
  :: (HasMinIO m)
  => ( AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [LoadedWeightTensor]
       -> m (Either Text a)
     )
  -> Text
  -> m (Either Text a)
withWeightedCheckpoint continuation experimentHash = do
  admission <- admitLatestCompletedCheckpoint experimentHash
  case admission of
    Left err -> pure (Left (renderCheckpointAdmissionError err))
    Right admitted ->
      let checkpoint = admittedCompletedCheckpoint admitted
       in continuation
            admitted
            (admittedCheckpointManifest checkpoint)
            (admittedCheckpointWeights checkpoint)

decodeLoadedWeightTensor
  :: CheckpointManifest
  -> TensorBlob
  -> StrictByteString.ByteString
  -> Either Text LoadedWeightTensor
decodeLoadedWeightTensor manifest tensor bytes = do
  let lazyBytes = LazyByteString.fromStrict bytes
      actualSha = jmw1ContentSha lazyBytes
      expectedKey = blobKey (manifestExperiment manifest) actualSha
  if tensorBlobKey tensor /= expectedKey
    then
      Left
        ( "weight blob identity mismatch for "
            <> tensorName tensor
            <> ": manifest records "
            <> tensorBlobKey tensor
            <> ", exact fetched bytes require "
            <> expectedKey
        )
    else Right ()
  values <- decodeJmw1 lazyBytes
  if encodeJmw1 values /= lazyBytes
    then
      Left
        ( "weight blob incompatible for "
            <> tensorName tensor
            <> ": JMW1 bytes are not the canonical frozen encoding"
        )
    else Right ()
  validateTensorPayloadShape tensor values
  Right
    LoadedWeightTensor
      { loadedWeightTensor = tensor
      , loadedWeightValues = values
      , loadedWeightJmw1Bytes = bytes
      }

-- | Reconstruct a V2 supervised runtime solely from its persisted refined
-- payload and the one exact physical @supervised.weights@ JMW1 blob.  A
-- runtime-free V1 manifest deliberately returns 'Nothing' so legacy engine
-- fallbacks remain isolated from the strict V2 path.
loadSupervisedRuntimeFromCheckpoint
  :: CheckpointManifest
  -> [LoadedWeightTensor]
  -> Either Text (Maybe RuntimeArtifact.LoadedRuntime)
loadSupervisedRuntimeFromCheckpoint manifest weights =
  case manifestSupervisedRuntime manifest of
    Nothing -> Right Nothing
    Just payload ->
      case weights of
        [loaded] ->
          let tensor = loadedWeightTensor loaded
           in if tensorName tensor /= "supervised.weights"
                then
                  Left
                    ( "V2 supervised runtime requires the one physical tensor "
                        <> "supervised.weights, got "
                        <> tensorName tensor
                    )
                else
                  if tensorShape tensor /= [parameterCount]
                    then
                      Left
                        ( "V2 supervised.weights shape mismatch: expected ["
                            <> Text.pack (show parameterCount)
                            <> "], got "
                            <> Text.pack (show (tensorShape tensor))
                        )
                    else
                      Just
                        <$> RuntimeArtifact.loadSupervisedRuntime
                          payload
                          (LazyByteString.fromStrict (loadedWeightJmw1Bytes loaded))
        [] -> Left "V2 supervised runtime is missing supervised.weights"
        _ ->
          Left
            ( "V2 supervised runtime requires exactly one physical weight "
                <> "blob, got "
                <> Text.pack (show (length weights))
            )
     where
      parameterCount =
        RuntimeArtifact.supervisedRuntimeParameterCount
          (RuntimeArtifact.payloadRuntime payload)

layerGraphFromCheckpoint
  :: CheckpointManifest -> [LoadedWeightTensor] -> Either Text (Maybe LayerGraph.LayerGraph)
layerGraphFromCheckpoint manifest weights =
  case architectureLayerGraph (manifestArchitecture manifest) of
    Nothing -> Right Nothing
    Just metadata -> Just <$> rebuildLayerGraph metadata weights

rebuildLayerGraph
  :: LayerGraphMetadata -> [LoadedWeightTensor] -> Either Text LayerGraph.LayerGraph
rebuildLayerGraph metadata weights = do
  nodes <- traverse (rebuildLayerNode weights) (layerGraphMetadataNodes metadata)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = layerGraphMetadataName metadata
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape (layerGraphMetadataInputShape metadata)
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape (layerGraphMetadataOutputShape metadata)
      , LayerGraph.layerGraphNodes = nodes
      }

rebuildLayerNode
  :: [LoadedWeightTensor] -> LayerGraphNodeMetadata -> Either Text LayerGraph.LayerNode
rebuildLayerNode weights metadata = do
  kind <- layerKindFromMetadata (layerGraphNodeKind metadata)
  mode <- layerModeFromMetadata (layerGraphNodeMode metadata)
  activation <- layerActivationFromMetadata (layerGraphNodeActivation metadata)
  params <- layerParametersFromMetadata weights metadata
  pure
    LayerGraph.LayerNode
      { LayerGraph.layerNodeName = layerGraphNodeName metadata
      , LayerGraph.layerNodeKind = kind
      , LayerGraph.layerNodeOp = maybe LayerGraph.IdentityOp (const LayerGraph.DenseOp) params
      , LayerGraph.layerInputShape = LayerGraph.TensorShape (layerGraphNodeInputShape metadata)
      , LayerGraph.layerOutputShape = LayerGraph.TensorShape (layerGraphNodeOutputShape metadata)
      , LayerGraph.layerMode = mode
      , LayerGraph.layerActivation = activation
      , LayerGraph.layerParameters = params
      }

layerParametersFromMetadata
  :: [LoadedWeightTensor] -> LayerGraphNodeMetadata -> Either Text (Maybe LayerGraph.LayerParameters)
layerParametersFromMetadata weights metadata =
  case (layerGraphNodeWeightTensor metadata, layerGraphNodeBiasTensor metadata) of
    (Nothing, Nothing) -> Right Nothing
    (Just weightName, Just biasName) -> do
      inputWidth <-
        LayerGraph.tensorShapeWidth (LayerGraph.TensorShape (layerGraphNodeInputShape metadata))
      outputWidth <-
        LayerGraph.tensorShapeWidth (LayerGraph.TensorShape (layerGraphNodeOutputShape metadata))
      weightValues <- lookupGraphTensor weights weightName [outputWidth, inputWidth]
      biasValues <- lookupGraphTensor weights biasName [outputWidth]
      Right
        ( Just
            LayerGraph.LayerParameters
              { LayerGraph.layerWeights = VU.fromList weightValues
              , LayerGraph.layerBias = VU.fromList biasValues
              }
        )
    _ ->
      Left
        ( "layer graph checkpoint node "
            <> layerGraphNodeName metadata
            <> " must declare both weight and bias tensors or neither"
        )

lookupGraphTensor :: [LoadedWeightTensor] -> Text -> [Int] -> Either Text [Double]
lookupGraphTensor weights name expectedShape =
  case filter ((== name) . tensorName . loadedWeightTensor) weights of
    [] -> Left ("layer graph checkpoint missing tensor " <> name)
    [loaded]
      | tensorShape (loadedWeightTensor loaded) /= expectedShape ->
          Left
            ( "layer graph checkpoint tensor "
                <> name
                <> " has shape "
                <> Text.pack (show (tensorShape (loadedWeightTensor loaded)))
                <> ", expected "
                <> Text.pack (show expectedShape)
            )
      | otherwise -> Right (loadedWeightValues loaded)
    _ -> Left ("layer graph checkpoint has duplicate tensor " <> name)

layerModeFromMetadata :: LayerGraphModeMetadata -> Either Text LayerGraph.LayerMode
layerModeFromMetadata LayerGraphTrainingMode = Right LayerGraph.TrainingMode
layerModeFromMetadata LayerGraphInferenceMode = Right LayerGraph.InferenceMode

layerActivationFromMetadata
  :: LayerGraphActivationMetadata -> Either Text LayerGraph.LayerActivation
layerActivationFromMetadata LayerGraphLinearActivation = Right LayerGraph.LinearActivation
layerActivationFromMetadata LayerGraphTanhActivation = Right LayerGraph.TanhActivation
layerActivationFromMetadata LayerGraphReluActivation = Right LayerGraph.ReluActivation
layerActivationFromMetadata LayerGraphSoftmaxActivation = Right LayerGraph.SoftmaxActivation

layerKindFromMetadata :: LayerGraphKindMetadata -> Either Text LayerGraph.LayerKind
layerKindFromMetadata LayerGraphDenseLayer = Right LayerGraph.DenseLayer
layerKindFromMetadata LayerGraphConv2DLayer = Right LayerGraph.Conv2DLayer
layerKindFromMetadata LayerGraphConv3DLayer = Right LayerGraph.Conv3DLayer
layerKindFromMetadata LayerGraphMaxPoolLayer = Right (LayerGraph.PoolLayer LayerGraph.MaxPool)
layerKindFromMetadata LayerGraphAvgPoolLayer = Right (LayerGraph.PoolLayer LayerGraph.AvgPool)
layerKindFromMetadata LayerGraphGlobalAvgPoolLayer = Right (LayerGraph.PoolLayer LayerGraph.GlobalAvgPool)
layerKindFromMetadata LayerGraphBatchNormLayer = Right (LayerGraph.NormLayer LayerGraph.BatchNorm)
layerKindFromMetadata LayerGraphLayerNormLayer = Right (LayerGraph.NormLayer LayerGraph.LayerNorm)
layerKindFromMetadata (LayerGraphGroupNormLayer groups) =
  Right (LayerGraph.NormLayer (LayerGraph.GroupNorm groups))
layerKindFromMetadata (LayerGraphDropoutLayer rate) = Right (LayerGraph.DropoutLayer rate)
layerKindFromMetadata (LayerGraphResidualLayer scale) = Right (LayerGraph.ResidualLayer scale)
layerKindFromMetadata (LayerGraphBasicBlockLayer scale) = Right (LayerGraph.BasicBlockLayer scale)
layerKindFromMetadata (LayerGraphBottleneckBlockLayer scale) =
  Right (LayerGraph.BottleneckBlockLayer scale)
layerKindFromMetadata (LayerGraphMultiHeadAttentionLayer heads) =
  Right (LayerGraph.MultiHeadAttentionLayer heads)
layerKindFromMetadata LayerGraphGeGLULayer = Right LayerGraph.GeGLULayer
layerKindFromMetadata LayerGraphPatchEmbedLayer = Right LayerGraph.PatchEmbedLayer

validateLoadedManifest
  :: Text
  -> Text
  -> Text
  -> CheckpointManifest
  -> Either Text CheckpointManifest
validateLoadedManifest experimentHash expectedManifestSha actualManifestSha manifest = do
  addressed <-
    validateAddressedManifest
      experimentHash
      expectedManifestSha
      actualManifestSha
      manifest
  if null (manifestTensors addressed)
    then Left "manifest incompatible: no weight tensors"
    else Right addressed

validateAddressedManifest
  :: Text
  -> Text
  -> Text
  -> CheckpointManifest
  -> Either Text CheckpointManifest
validateAddressedManifest experimentHash expectedManifestSha actualManifestSha manifest
  | manifestExperiment manifest /= experimentHash =
      Left
        ( "manifest incompatible: experiment mismatch, requested "
            <> experimentHash
            <> " but manifest records "
            <> manifestExperiment manifest
        )
  | actualManifestSha /= expectedManifestSha =
      Left
        ( "manifest incompatible: content sha mismatch, pointer addressed "
            <> expectedManifestSha
            <> " but exact fetched bytes hash to "
            <> actualManifestSha
        )
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
  :: FilePath
  -> Text
  -> LazyByteString.ByteString
  -> IO (Either CheckpointWriteError ObjectWriteResult)
writeObjectIfAbsent root objectKey payload = do
  case objectPathForKey root objectKey of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right path -> do
      outcome <-
        try (writeAtPath path)
          :: IO
               ( Either
                   IOException
                   (Either CheckpointWriteError ObjectWriteResult)
               )
      pure $
        case outcome of
          Left err ->
            Left
              ( CheckpointWriteIOFailure
                  objectKey
                  (Text.pack (show err))
              )
          Right result -> result
 where
  writeAtPath path = do
    exists <- doesPathExist path
    if exists
      then existingObjectResult path
      else do
        createDirectoryIfMissing True (takeDirectory path)
        created <-
          try
            ( withTempFile (takeDirectory path) ".jitml-object.tmp" $ \tempPath handle -> do
                LazyByteString.hPut handle payload
                hFlush handle
                createLink tempPath path
            )
            :: IO (Either IOException ())
        case created of
          Right () -> pure (Right (ObjectCreated objectKey))
          Left createError -> do
            nowExists <- doesPathExist path
            if nowExists
              then existingObjectResult path
              else
                pure
                  ( Left
                      ( CheckpointWriteIOFailure
                          objectKey
                          (Text.pack (show createError))
                      )
                  )

  existingObjectResult path = do
    existingResult <-
      try (StrictByteString.readFile path)
        :: IO (Either IOException StrictByteString.ByteString)
    pure $
      case existingResult of
        Right existing
          | existing == LazyByteString.toStrict payload ->
              Right (ObjectAlreadyPresent objectKey)
          | otherwise ->
              Left
                ( CheckpointWriteObjectConflict
                    objectKey
                    "existing bytes differ"
                )
        Left err ->
          Left
            ( CheckpointWriteObjectConflict
                objectKey
                ( "existing bytes could not be compared: "
                    <> Text.pack (show err)
                )
            )

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

{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Store
  ( AdmittedCheckpoint
  , AdmittedCompletedCheckpoint
  , CheckpointAdmissionError (..)
  , CheckpointWriteError (..)
  , GcEvent (..)
  , GcIntent (..)
  , GcAuthorizationResult (..)
  , GcPromotionResult (..)
  , GcReadyEvent (..)
  , GcDeleteOutcome (..)
  , GcEventExecution (..)
  , GcExecutionResult (..)
  , GcPlan (..)
  , LoadedWeightTensor (..)
  , ObjectWriteResult (..)
  , RetentionPolicy (..)
  , PreparedCheckpointSnapshot (..)
  , WriterCommit (..)
  , WriterPhysicalObject (..)
  , WriterPointerIntent (..)
  , WriterReservation (..)
  , WriterReservationTemplate (..)
  , WriterSnapshotKind (..)
  , ExperimentGcFence (..)
  , GcFenceEpoch
  , GcFenceDecision (..)
  , GcFenceDecisionPhase (..)
  , AuthorizedGcIntent
  , RevalidatedGcIntent
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
  , gcCompletedExecutions
  , gcEventId
  , gcExecutionFailures
  , gcCancelledObjectKey
  , gcFenceOperationId
  , gcIntentObjectKey
  , gcPlanIntents
  , gcPublishedObjectKey
  , gcReadyObjectKey
  , experimentGcFenceObjectKey
  , checkpointStorageSnapshotId
  , checkpointObjectKey
  , checkpointObjectRef
  , candidateStoredCheckpoint
  , completedStoredCheckpoint
  , decodeWriterCommit
  , decodeWriterReservation
  , decodeExperimentGcFence
  , encodeWriterCommit
  , encodeWriterReservation
  , encodeExperimentGcFence
  , executeAuthorizedGcIntents
  , authorizeRevalidatedGcIntents
  , loadCheckpointPointerGcRoots
  , loadGcFenceEpoch
  , loadGcCancelledIntents
  , loadGcIntents
  , loadGcPublishedEvents
  , loadGcReadyEvents
  , loadActiveWriterReservations
  , loadWriterCommits
  , persistGcPlanIntents
  , persistGcIntents
  , cancelGcIntents
  , helpGcCancellations
  , revalidateGcIntents
  , revalidatedGcIntent
  , promoteGcIntents
  , acknowledgeGcReadyEvent
  , listCheckpointManifests
  , listCheckpointManifestsMinIO
  , loadInferenceCheckpointWith
  , loadInferenceCheckpointWithWeights
  , loadInferenceCheckpointDecodedWithWeights
  , loadInferenceCheckpointDecodedWithWeightsTyped
  , CheckpointLoadError (..)
  , renderCheckpointLoadError
  , checkpointLoadErrorTerminal
  , checkpointAdmissionErrorTerminal
  , checkpointRequestInputRejection
  , withWeightedCheckpointTyped
  , loadSupervisedRuntimeFromCheckpoint
  , reconstructSupervisedGraphFromCheckpoint
  , runSupervisedGraphCheckpointInference
  , objectPathForKey
  , prepareCheckpointSnapshot
  , readCheckpointManifest
  , readCheckpointPointer
  , readObject
  , renderCheckpointAdmissionError
  , renderCheckpointWriteError
  , requireAdmittedCompletedCheckpoint
  , validateWriterCommit
  , validateWriterReservation
  , validateGcTerminalRelations
  , walkLiveSet
  , writerCommitObjectKey
  , writerReservationOverlapsGcEvent
  , writerReservationId
  , instantiateWriterReservation
  , writerReservationObjectKey
  , writeCandidateCheckpointSnapshot
  , writeCandidateCheckpointSnapshotWithMinIO
  , writeCompletedCheckpointSnapshot
  , writeCompletedCheckpointSnapshotWithMinIO
  , writeObjectIfAbsent
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (IOException, bracket, bracket_, try)
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt, isAscii, isControl, isDigit)
import Data.Either (lefts, rights)
import Data.Either.Combinators (mapLeft)
import Data.Foldable (traverse_)
import Data.List (group, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Ord (Down (..))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64, Word8)
import GHC.Generics (Generic)
import Numeric (showHex)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , doesPathExist
  , listDirectory
  , removeFile
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
  , checkpointWireVersionV2
  , decodeAddressedManifestCbor
  , decodeJmw1
  , encodeManifestCbor
  , latestPointerKey
  , layerGraphFromMetadata
  , layerGraphMetadataParameterCount
  , manifestContentSha
  , manifestKey
  , renderCheckpointCompletionValidationError
  , snapshotPhysicalObjectKey
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
import JitML.Service.Retry (ServiceError (..), serviceErrorPermanent)
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
  | AdmissionSnapshotCommitInvalid Text
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

-- | Why a checkpoint load failed, keeping admission failures typed.
--
-- The rendered 'Text' form loses whether the checkpoint was absent, which is
-- exactly the fact a durable consumer needs in order to settle rather than
-- redeliver forever.
data CheckpointLoadError
  = CheckpointLoadAdmissionFailed CheckpointAdmissionError
  | -- | The request's input lies outside the input domain the admitted runtime
    -- declares. Both operands — the request bytes and the immutable admitted
    -- checkpoint — are fixed, so this verdict cannot change on a later attempt.
    CheckpointLoadInputRejected Text
  | CheckpointLoadRunnerFailed Text
  deriving stock (Eq, Show)

renderCheckpointLoadError :: CheckpointLoadError -> Text
renderCheckpointLoadError loadError =
  case loadError of
    CheckpointLoadAdmissionFailed err -> renderCheckpointAdmissionError err
    CheckpointLoadInputRejected reason -> "request input rejected: " <> reason
    CheckpointLoadRunnerFailed message -> message

-- | Is this load permanently unsatisfiable for the addressed experiment?
--
-- True when the store proved the object ABSENT, or when the admitted runtime
-- rejected the request's own input. Both are decided entirely by immutable
-- operands, so redelivering the identical request can only reproduce them. A
-- malformed or unauthorized read, and any runner-side execution failure, stay
-- retryable: a redelivery can still complete the work once the underlying
-- condition clears.
checkpointLoadErrorTerminal :: CheckpointLoadError -> Bool
checkpointLoadErrorTerminal loadError =
  case loadError of
    CheckpointLoadAdmissionFailed err -> checkpointAdmissionErrorTerminal err
    CheckpointLoadInputRejected _ -> True
    CheckpointLoadRunnerFailed _ -> False

-- | An admission failure is terminal exactly when the underlying read proved
-- the object absent. The runner-side and structural variants are not terminal:
-- they describe state that a later attempt may legitimately find different.
checkpointAdmissionErrorTerminal :: CheckpointAdmissionError -> Bool
checkpointAdmissionErrorTerminal admissionError =
  case admissionError of
    AdmissionPointerReadFailed _ err -> serviceErrorPermanent err
    AdmissionManifestReadFailed _ err -> serviceErrorPermanent err
    AdmissionBlobReadFailed _ err -> serviceErrorPermanent err
    _ -> False

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
    AdmissionSnapshotCommitInvalid reason ->
      "checkpoint storage snapshot commit admission failed: " <> reason
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

-- | The durable role of one snapshot write.  A candidate deliberately has no
-- selector mutation; a completed write owns the latest-pointer transition.
data WriterSnapshotKind
  = WriterCandidateSnapshot
  | WriterCompletedSnapshot
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Exact selector mutation intended by the writer.  Attempt-local CAS tokens
-- are deliberately excluded from durable transaction identity.
data WriterPointerIntent
  = WriterNoPointerIntent
  | WriterLatestPointerIntent
      { writerPointerObjectKey :: Text
      }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | One exact physical payload binding in a snapshot namespace.
data WriterPhysicalObject = WriterPhysicalObject
  { writerPhysicalObjectOriginalKey :: Text
  , writerPhysicalObjectKey :: Text
  , writerPhysicalObjectSha :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Deterministic reservation content shared by every attempt to write the
-- same exact snapshot.  It is not itself a persisted active marker.
data WriterReservationTemplate = WriterReservationTemplate
  { writerReservationTemplateExperimentHash :: Text
  , writerReservationTemplateSnapshotId :: Text
  , writerReservationTemplateManifestObjectKey :: Text
  , writerReservationTemplateManifestSha :: Text
  , writerReservationTemplateParentManifestSha :: Maybe Text
  , writerReservationTemplatePhysicalObjects :: [WriterPhysicalObject]
  , writerReservationTemplateKind :: WriterSnapshotKind
  , writerReservationTemplatePointerIntent :: WriterPointerIntent
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Durable per-attempt before-image for a checkpoint write.  Every concurrent
-- writer owns a distinct marker and removes only that marker, so one exact
-- writer cannot expose another writer's in-flight repair to GC.
data WriterReservation = WriterReservation
  { writerReservationAttemptId :: Text
  , writerReservationExperimentHash :: Text
  , writerReservationSnapshotId :: Text
  , writerReservationManifestObjectKey :: Text
  , writerReservationManifestSha :: Text
  , writerReservationParentManifestSha :: Maybe Text
  , writerReservationPhysicalObjects :: [WriterPhysicalObject]
  , writerReservationKind :: WriterSnapshotKind
  , writerReservationPointerIntent :: WriterPointerIntent
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | One experiment-wide writer/GC linearization point.  A writer reservation
-- may protect its own storage snapshot, its parent manifest in another
-- snapshot, or an exact shared object.  Keeping the complete active set and
-- every per-event decision in one CAS record makes all of those overlaps
-- contend on the same ETag.  Absence of an event decision is its Open state.
data ExperimentGcFence = ExperimentGcFence
  { experimentGcFenceVersion :: Word64
  , experimentGcFenceRevision :: Word64
  , experimentGcFenceWriterEpoch :: Word64
  , experimentGcFenceExperimentHash :: Text
  , experimentGcFenceReservations :: [WriterReservation]
  , experimentGcFenceDecisions :: [GcFenceDecision]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | One observation of the monotonic writer/root-activity epoch.  The
-- constructor is private: callers bracket a complete GC root view with
-- 'loadGcFenceEpoch', and only an unchanged pair can mint a destructive
-- revalidation witness. GC-only decisions do not invalidate sibling intents.
newtype GcFenceEpoch = GcFenceEpoch
  { gcFenceEpochFence :: ExperimentGcFence
  }
  deriving stock (Show)

instance Eq GcFenceEpoch where
  first == second =
    let firstFence = gcFenceEpochFence first
        secondFence = gcFenceEpochFence second
     in experimentGcFenceExperimentHash firstFence
          == experimentGcFenceExperimentHash secondFence
          && experimentGcFenceWriterEpoch firstFence
            == experimentGcFenceWriterEpoch secondFence

data GcFenceDecision = GcFenceDecision
  { gcFenceDecisionGeneration :: Word64
  , gcFenceDecisionIntent :: GcIntent
  , gcFenceDecisionOperationId :: Text
  , gcFenceDecisionPhase :: GcFenceDecisionPhase
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data GcFenceDecisionPhase
  = GcFencePlanned
  | GcFenceCancelling
  | GcFenceCancelled
  | GcFenceExecuting
  | GcFenceReaped
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Proof that one exact intent survived a caller-supplied fresh complete
-- root/reservation/terminal revalidation.  The constructor stays private so a
-- raw durable intent cannot cross the destructive API boundary.
data RevalidatedGcIntent = RevalidatedGcIntent
  { revalidatedGcIntent :: GcIntent
  , revalidatedGcFenceEpoch :: GcFenceEpoch
  }
  deriving stock (Eq, Show)

-- | Proof that the experiment fence records this exact operation as Executing
-- (or already Reaped).  Only the Store authorizer constructs this value.
data AuthorizedGcIntent = AuthorizedGcIntent
  { authorizedGcIntentValue :: GcIntent
  , authorizedGcGeneration :: Word64
  , authorizedGcOperationId :: Text
  }
  deriving stock (Eq, Ord, Show)

data GcAuthorizationResult = GcAuthorizationResult
  { gcAuthorizedIntents :: [AuthorizedGcIntent]
  , gcAuthorizationCancelledIntents :: [GcIntent]
  , gcAuthorizationFailures :: [(Text, ServiceError)]
  }
  deriving stock (Eq, Show)

-- | Durable completion marker.  It contains no timestamp or attempt-local
-- value, so an exact retry recreates the same bytes.  A matching commit proves
-- every write step completed, while any still-present per-attempt reservation
-- remains an active GC fence until its owning writer deletes it.
data WriterCommit = WriterCommit
  { writerCommitExperimentHash :: Text
  , writerCommitSnapshotId :: Text
  , writerCommitReservationId :: Text
  , writerCommitManifestSha :: Text
  , writerCommitPhysicalObjects :: [WriterPhysicalObject]
  , writerCommitKind :: WriterSnapshotKind
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Pure, backend-independent preparation result.  Local and MinIO writers
-- both consume this value, guaranteeing identical snapshot ids, physical
-- addresses, manifest bytes, and manifest SHA for the same logical input.
data PreparedCheckpointSnapshot = PreparedCheckpointSnapshot
  { preparedSnapshotId :: Text
  , preparedSnapshotManifest :: CheckpointManifest
  , preparedSnapshotPayloads :: [(Text, LazyByteString.ByteString)]
  , preparedSnapshotManifestBytes :: LazyByteString.ByteString
  , preparedSnapshotManifestSha :: Text
  , preparedSnapshotManifestBodySha :: Maybe Text
  , preparedSnapshotReservationTemplate :: WriterReservationTemplate
  , preparedSnapshotCommit :: WriterCommit
  }
  deriving stock (Eq, Show)

writerRecordWireVersion :: Word64
writerRecordWireVersion = 1

data WriterReservationEnvelope = WriterReservationEnvelope
  { writerReservationEnvelopeVersion :: Word64
  , writerReservationEnvelopeValue :: WriterReservation
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data WriterCommitEnvelope = WriterCommitEnvelope
  { writerCommitEnvelopeVersion :: Word64
  , writerCommitEnvelopeValue :: WriterCommit
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

encodeWriterReservation :: WriterReservation -> StrictByteString.ByteString
encodeWriterReservation =
  LazyByteString.toStrict
    . serialise
    . WriterReservationEnvelope writerRecordWireVersion

encodeWriterCommit :: WriterCommit -> StrictByteString.ByteString
encodeWriterCommit =
  LazyByteString.toStrict
    . serialise
    . WriterCommitEnvelope writerRecordWireVersion

decodeWriterReservation :: StrictByteString.ByteString -> Either Text WriterReservation
decodeWriterReservation bytes = do
  envelope <-
    mapLeft (Text.pack . show) (deserialiseOrFail (LazyByteString.fromStrict bytes))
  if writerReservationEnvelopeVersion envelope == writerRecordWireVersion
    then Right ()
    else Left "unsupported writer reservation wire version"
  let reservation = writerReservationEnvelopeValue envelope
  if encodeWriterReservation reservation == bytes
    then validateWriterReservation reservation
    else Left "writer reservation is not canonical CBOR"

decodeWriterCommit :: StrictByteString.ByteString -> Either Text WriterCommit
decodeWriterCommit bytes = do
  envelope <-
    mapLeft (Text.pack . show) (deserialiseOrFail (LazyByteString.fromStrict bytes))
  if writerCommitEnvelopeVersion envelope == writerRecordWireVersion
    then Right ()
    else Left "unsupported writer commit wire version"
  let commit = writerCommitEnvelopeValue envelope
  if encodeWriterCommit commit == bytes
    then validateWriterCommit commit
    else Left "writer commit is not canonical CBOR"

experimentGcFenceWireVersion :: Word64
experimentGcFenceWireVersion = 1

experimentGcFenceTextPrefix :: Text
experimentGcFenceTextPrefix = "jitml-experiment-gc-fence-v1:"

-- | Text-safe canonical envelope used with the existing textual MinIO CAS.
-- The payload is canonical CBOR rendered as lowercase hexadecimal bytes.
encodeExperimentGcFence :: ExperimentGcFence -> Text
encodeExperimentGcFence fence =
  experimentGcFenceTextPrefix
    <> encodeLowerHex
      (LazyByteString.toStrict (serialise fence))

decodeExperimentGcFence :: Text -> Either Text ExperimentGcFence
decodeExperimentGcFence encoded = do
  payloadHex <-
    maybe
      (Left "experiment GC fence has an unsupported text-envelope prefix")
      Right
      (Text.stripPrefix experimentGcFenceTextPrefix encoded)
  payload <- decodeLowerHex payloadHex
  fence <-
    mapLeft
      (Text.pack . show)
      (deserialiseOrFail (LazyByteString.fromStrict payload))
  if encodeExperimentGcFence fence == encoded
    then validateExperimentGcFence fence
    else Left "experiment GC fence is not canonical text/CBOR"

encodeLowerHex :: StrictByteString.ByteString -> Text
encodeLowerHex =
  Text.pack . concatMap encodeByte . StrictByteString.unpack
 where
  encodeByte :: Word8 -> String
  encodeByte byte =
    [ lowerHexDigit (fromIntegral byte `div` 16)
    , lowerHexDigit (fromIntegral byte `mod` 16)
    ]
  lowerHexDigit nibble
    | nibble < 10 = toEnum (fromEnum '0' + nibble)
    | otherwise = toEnum (fromEnum 'a' + nibble - 10)

decodeLowerHex :: Text -> Either Text StrictByteString.ByteString
decodeLowerHex encoded
  | odd (Text.length encoded) = Left "experiment GC fence hex payload has odd length"
  | Text.any (not . isLowerHexDigit) encoded =
      Left "experiment GC fence hex payload is not lowercase hexadecimal"
  | otherwise =
      Right
        ( StrictByteString.pack
            (decodePairs (Text.unpack encoded))
        )
 where
  isLowerHexDigit character =
    isAscii character && isDigit character
      || character >= 'a' && character <= 'f'
  decodePairs [] = []
  decodePairs (high : low : rest) =
    fromIntegral (digitToInt high * 16 + digitToInt low) : decodePairs rest
  decodePairs [_] = []

experimentGcFenceObjectKey :: Text -> Text
experimentGcFenceObjectKey experimentHash =
  "jitml-checkpoints/"
    <> experimentHash
    <> "/gc/coordination-fence.txt"

gcFenceOperationId :: Word64 -> GcIntent -> Text
gcFenceOperationId generation intent =
  jmw1ContentSha
    ( serialise
        ( "jitml-experiment-gc-fence-operation-v1" :: Text
        , generation
        , intent
        )
    )

validateExperimentGcFence :: ExperimentGcFence -> Either Text ExperimentGcFence
validateExperimentGcFence fence = do
  if experimentGcFenceVersion fence == experimentGcFenceWireVersion
    then Right ()
    else Left "unsupported experiment GC fence version"
  if experimentGcFenceWriterEpoch fence <= experimentGcFenceRevision fence
    then Right ()
    else Left "experiment GC fence writer epoch exceeds its CAS revision"
  validateGcExperimentHash (experimentGcFenceExperimentHash fence)
  let reservations = experimentGcFenceReservations fence
      reservationKeys = fmap writerReservationObjectKey reservations
  if reservations == Set.toAscList (Set.fromList reservations)
    then Right ()
    else Left "experiment GC fence reservations are not canonical and unique"
  if length reservationKeys == Set.size (Set.fromList reservationKeys)
    then Right ()
    else Left "experiment GC fence contains duplicate writer reservation keys"
  traverse_ validateFenceReservation reservations
  let decisions = experimentGcFenceDecisions fence
      decisionKeys = fmap gcFenceDecisionKey decisions
  if decisions == sortOn gcFenceDecisionKey decisions
    then Right ()
    else Left "experiment GC fence decisions are not in canonical event/generation order"
  if length decisionKeys == Set.size (Set.fromList decisionKeys)
    then Right ()
    else Left "experiment GC fence contains a duplicate event generation"
  traverse_ (validateDecision reservations) decisions
  traverse_ validateDecisionHistory (groupDecisionsByEvent decisions)
  validateNonoverlappingDestructiveDecisions (latestGcFenceDecisions decisions)
  Right fence
 where
  validateFenceReservation reservation = do
    _ <- validateWriterReservation reservation
    if writerReservationExperimentHash reservation
      == experimentGcFenceExperimentHash fence
      then Right ()
      else Left "experiment GC fence reservation belongs to another experiment"

  validateDecision reservations decision = do
    let generation = gcFenceDecisionGeneration decision
        intent = gcFenceDecisionIntent decision
        operationId = gcFenceDecisionOperationId decision
    _ <- validateGcIntent intent
    if gcExperimentHash (gcIntentEvent intent) == experimentGcFenceExperimentHash fence
      then Right ()
      else Left "experiment GC fence decision belongs to another experiment"
    if operationId == gcFenceOperationId generation intent
      then Right ()
      else Left "experiment GC fence operation id does not bind generation and intent"
    case gcFenceDecisionPhase decision of
      GcFenceCancelling -> Right ()
      GcFenceCancelled -> Right ()
      _
        | any
            (\reservation -> writerReservationOverlapsGcEvent reservation (gcIntentEvent intent))
            reservations ->
            Left "active writer overlaps a non-cancelled experiment GC fence decision"
        | otherwise -> Right ()

  validateNonoverlappingDestructiveDecisions decisions =
    traverse_
      ( \(first, second) ->
          if gcEventsOverlap
            (gcIntentEvent (gcFenceDecisionIntent first))
            (gcIntentEvent (gcFenceDecisionIntent second))
            then Left "overlapping experiment GC fence decisions are both destructive"
            else Right ()
      )
      [ (first, second)
      | (index, first) <- zip [(0 :: Int) ..] decisions
      , gcFenceDecisionPhase first `elem` [GcFencePlanned, GcFenceExecuting, GcFenceReaped]
      , second <- drop (index + 1) decisions
      , gcFenceDecisionPhase second `elem` [GcFencePlanned, GcFenceExecuting, GcFenceReaped]
      ]

  validateDecisionHistory [] = Right ()
  validateDecisionHistory history@(first : _) = do
    let expectedGenerations = [0 .. fromIntegral (length history - 1)]
        observedGenerations = fmap gcFenceDecisionGeneration history
        expectedIntent = gcFenceDecisionIntent first
    if observedGenerations == expectedGenerations
      then Right ()
      else Left "experiment GC fence decision generations are not contiguous from zero"
    if all ((== expectedIntent) . gcFenceDecisionIntent) history
      then Right ()
      else Left "experiment GC fence generations do not bind one byte-identical intent"
    if all ((== GcFenceCancelled) . gcFenceDecisionPhase) (init history)
      then Right ()
      else Left "only the latest experiment GC fence generation may be non-cancelled"

gcFenceDecisionKey :: GcFenceDecision -> (Text, Word64)
gcFenceDecisionKey decision =
  ( gcIntentEventId (gcFenceDecisionIntent decision)
  , gcFenceDecisionGeneration decision
  )

groupDecisionsByEvent :: [GcFenceDecision] -> [[GcFenceDecision]]
groupDecisionsByEvent =
  groupByEvent . sortOn gcFenceDecisionKey
 where
  groupByEvent [] = []
  groupByEvent (decision : rest) =
    let eventId = gcIntentEventId (gcFenceDecisionIntent decision)
        (sameEvent, remaining) =
          span
            ((== eventId) . gcIntentEventId . gcFenceDecisionIntent)
            rest
     in (decision : sameEvent) : groupByEvent remaining

latestGcFenceDecisions :: [GcFenceDecision] -> [GcFenceDecision]
latestGcFenceDecisions = fmap last . groupDecisionsByEvent

writerReservationId :: WriterReservation -> Text
writerReservationId reservation =
  writerReservationTemplateId (reservationTemplateFromReservation reservation)

writerReservationTemplateId :: WriterReservationTemplate -> Text
writerReservationTemplateId template =
  jmw1ContentSha
    ( serialise
        ( "jitml-checkpoint-writer-reservation-id-v1" :: Text
        , template
        )
    )

reservationTemplateFromReservation :: WriterReservation -> WriterReservationTemplate
reservationTemplateFromReservation reservation =
  WriterReservationTemplate
    { writerReservationTemplateExperimentHash = writerReservationExperimentHash reservation
    , writerReservationTemplateSnapshotId = writerReservationSnapshotId reservation
    , writerReservationTemplateManifestObjectKey = writerReservationManifestObjectKey reservation
    , writerReservationTemplateManifestSha = writerReservationManifestSha reservation
    , writerReservationTemplateParentManifestSha = writerReservationParentManifestSha reservation
    , writerReservationTemplatePhysicalObjects = writerReservationPhysicalObjects reservation
    , writerReservationTemplateKind = writerReservationKind reservation
    , writerReservationTemplatePointerIntent = writerReservationPointerIntent reservation
    }

instantiateWriterReservation
  :: Text
  -> WriterReservationTemplate
  -> Either Text WriterReservation
instantiateWriterReservation attemptId template =
  validateWriterReservation
    WriterReservation
      { writerReservationAttemptId = attemptId
      , writerReservationExperimentHash = writerReservationTemplateExperimentHash template
      , writerReservationSnapshotId = writerReservationTemplateSnapshotId template
      , writerReservationManifestObjectKey = writerReservationTemplateManifestObjectKey template
      , writerReservationManifestSha = writerReservationTemplateManifestSha template
      , writerReservationParentManifestSha = writerReservationTemplateParentManifestSha template
      , writerReservationPhysicalObjects = writerReservationTemplatePhysicalObjects template
      , writerReservationKind = writerReservationTemplateKind template
      , writerReservationPointerIntent = writerReservationTemplatePointerIntent template
      }

writerAttemptIdForSlot :: Int -> Text
writerAttemptIdForSlot slot =
  Text.justifyRight 64 '0' (Text.pack (showHex slot ""))

writerReservationObjectKey :: WriterReservation -> Text
writerReservationObjectKey reservation =
  "jitml-checkpoints/"
    <> writerReservationExperimentHash reservation
    <> "/snapshots/"
    <> writerReservationSnapshotId reservation
    <> "/reservations/"
    <> writerReservationAttemptId reservation
    <> ".cbor"

writerCommitObjectKey :: WriterCommit -> Text
writerCommitObjectKey commit =
  snapshotControlObjectKey
    (writerCommitExperimentHash commit)
    (writerCommitSnapshotId commit)
    "committed.cbor"

snapshotControlObjectKey :: Text -> Text -> Text -> Text
snapshotControlObjectKey experimentHash snapshotId leaf =
  "jitml-checkpoints/"
    <> experimentHash
    <> "/snapshots/"
    <> snapshotId
    <> "/"
    <> leaf

deriveCheckpointStorageSnapshotId
  :: CheckpointManifest
  -> [(Text, Text)]
  -> Text
deriveCheckpointStorageSnapshotId logicalManifest originalBindings =
  jmw1ContentSha
    ( serialise
        ( "jitml-snapshot-v1" :: Text
        , LazyByteString.toStrict (encodeManifestCbor logicalManifest)
        , sortOn fst originalBindings
        )
    )

-- | Derive the single storage snapshot id shared by every physical key in a
-- prepared manifest.  Legacy unscoped manifests return 'Nothing'; a mixed,
-- malformed, or cross-snapshot namespace is rejected.
checkpointStorageSnapshotId
  :: CheckpointManifest
  -> Either Text (Maybe Text)
checkpointStorageSnapshotId manifest =
  case manifestPhysicalObjectKeys manifest of
    [] -> Right Nothing
    keys -> do
      classifications <- traverse classifyKey keys
      case Set.toAscList (Set.fromList classifications) of
        [Nothing] -> Right Nothing
        [Just snapshotId] -> Right (Just snapshotId)
        _ -> Left "checkpoint physical graph mixes storage snapshot namespaces"
 where
  classifyKey objectKey = do
    canonical <- canonicalGcPhysicalObjectKey (manifestExperiment manifest) objectKey
    if canonical /= objectKey
      then Left ("checkpoint physical key is not canonical: " <> objectKey)
      else
        if snapshotPhysicalPrefix `Text.isPrefixOf` objectKey
          then Just <$> snapshotIdFromPhysicalKey (manifestExperiment manifest) objectKey
          else Right Nothing
  snapshotPhysicalPrefix =
    "jitml-checkpoints/" <> manifestExperiment manifest <> "/snapshots/"

snapshotIdFromPhysicalKey :: Text -> Text -> Either Text Text
snapshotIdFromPhysicalKey experimentHash objectKey = do
  let expectedPrefix =
        "jitml-checkpoints/" <> experimentHash <> "/snapshots/"
  remainder <-
    maybe
      (Left ("checkpoint physical key is not snapshot-scoped: " <> objectKey))
      Right
      (Text.stripPrefix expectedPrefix objectKey)
  case Text.splitOn "/" remainder of
    [snapshotId, "objects", originalKeySha] -> do
      validateCanonicalSha256 "storage snapshot id" snapshotId
      validateCanonicalSha256 "snapshot original-key SHA-256" originalKeySha
      Right snapshotId
    _ -> Left ("checkpoint physical key has an invalid snapshot namespace: " <> objectKey)

-- | Deterministically turn a logical checkpoint graph into one isolated
-- storage snapshot.  Snapshot identity binds canonical logical manifest bytes
-- plus the sorted original-full-key/exact-payload-hash table.  Object address
-- hashes bind original keys (rather than payload bytes), so every declared
-- physical class is isolated even when two snapshots contain identical bytes.
prepareCheckpointSnapshot
  :: WriterSnapshotKind
  -> WriterPointerIntent
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Either Text PreparedCheckpointSnapshot
prepareCheckpointSnapshot kind pointerIntent logicalManifest logicalPayloads = do
  validateWriterSnapshotKindForManifest kind logicalManifest
  validateWriterPointerIntent
    (manifestExperiment logicalManifest)
    kind
    pointerIntent
  _ <- validateSnapshotPayloads logicalManifest logicalPayloads
  originalKeys <- traverse canonicalLogicalPhysicalKey (manifestPhysicalObjectKeys logicalManifest)
  let payloadByOriginalKey = Map.fromList logicalPayloads
      originalBindings =
        sortOn
          fst
          [ (originalKey, jmw1ContentSha payload)
          | originalKey <- originalKeys
          , Just payload <- [Map.lookup originalKey payloadByOriginalKey]
          ]
  if length originalBindings == length originalKeys
    then Right ()
    else Left "snapshot preparation lost one or more physical payload bindings"
  let snapshotId =
        deriveCheckpointStorageSnapshotId logicalManifest originalBindings
      rebasedKeyByOriginal =
        Map.fromList
          [ ( originalKey
            , snapshotPhysicalObjectKey
                (manifestExperiment logicalManifest)
                snapshotId
                originalKey
            )
          | originalKey <- originalKeys
          ]
  rebasedManifest <- rebaseManifestPhysicalKeys rebasedKeyByOriginal logicalManifest
  derivedSnapshotId <- checkpointStorageSnapshotId rebasedManifest
  case (originalKeys, derivedSnapshotId) of
    ([], Nothing) -> Right ()
    (_ : _, Just actualSnapshotId)
      | actualSnapshotId == snapshotId -> Right ()
    _ -> Left "prepared checkpoint does not have one exact storage snapshot namespace"
  let rebasedPayloads =
        sortOn
          fst
          [ (rebasedKey, payload)
          | (originalKey, payload) <- logicalPayloads
          , Just rebasedKey <- [Map.lookup originalKey rebasedKeyByOriginal]
          ]
  if length rebasedPayloads == length logicalPayloads
    then Right ()
    else Left "snapshot preparation could not rebase every physical payload"
  let preparedHashes =
        Map.fromList
          [ (objectKey, jmw1ContentSha payload)
          | (objectKey, payload) <- rebasedPayloads
          ]
  _ <-
    validateSnapshotPayloadsWithSnapshotHashes
      (Just preparedHashes)
      rebasedManifest
      rebasedPayloads
  (manifestBytes, manifestSha, manifestBodySha) <- encodeAddressedManifest rebasedManifest
  let physicalObjects =
        sortOn
          writerPhysicalObjectKey
          [ WriterPhysicalObject
              { writerPhysicalObjectOriginalKey = originalKey
              , writerPhysicalObjectKey = rebasedKey
              , writerPhysicalObjectSha = payloadSha
              }
          | (originalKey, payloadSha) <- originalBindings
          , Just rebasedKey <- [Map.lookup originalKey rebasedKeyByOriginal]
          ]
      reservationTemplate =
        WriterReservationTemplate
          { writerReservationTemplateExperimentHash = manifestExperiment rebasedManifest
          , writerReservationTemplateSnapshotId = snapshotId
          , writerReservationTemplateManifestObjectKey =
              manifestKey (manifestExperiment rebasedManifest) manifestSha
          , writerReservationTemplateManifestSha = manifestSha
          , writerReservationTemplateParentManifestSha = manifestParentManifestSha rebasedManifest
          , writerReservationTemplatePhysicalObjects = physicalObjects
          , writerReservationTemplateKind = kind
          , writerReservationTemplatePointerIntent = pointerIntent
          }
      commit =
        WriterCommit
          { writerCommitExperimentHash = manifestExperiment rebasedManifest
          , writerCommitSnapshotId = snapshotId
          , writerCommitReservationId = writerReservationTemplateId reservationTemplate
          , writerCommitManifestSha = manifestSha
          , writerCommitPhysicalObjects = physicalObjects
          , writerCommitKind = kind
          }
  _ <- validateWriterCommit commit
  Right
    PreparedCheckpointSnapshot
      { preparedSnapshotId = snapshotId
      , preparedSnapshotManifest = rebasedManifest
      , preparedSnapshotPayloads = rebasedPayloads
      , preparedSnapshotManifestBytes = manifestBytes
      , preparedSnapshotManifestSha = manifestSha
      , preparedSnapshotManifestBodySha = manifestBodySha
      , preparedSnapshotReservationTemplate = reservationTemplate
      , preparedSnapshotCommit = commit
      }
 where
  canonicalLogicalPhysicalKey objectKey = do
    canonical <- canonicalGcPhysicalObjectKey (manifestExperiment logicalManifest) objectKey
    if canonical /= objectKey
      then Left ("checkpoint logical physical key is not canonical: " <> objectKey)
      else
        if ( "jitml-checkpoints/"
               <> manifestExperiment logicalManifest
               <> "/snapshots/"
           )
          `Text.isPrefixOf` objectKey
          then Left ("checkpoint logical physical key is already snapshot-scoped: " <> objectKey)
          else Right canonical

rebaseManifestPhysicalKeys
  :: Map.Map Text Text
  -> CheckpointManifest
  -> Either Text CheckpointManifest
rebaseManifestPhysicalKeys keyMap manifest = do
  tensors <- traverse rebaseTensor (manifestTensors manifest)
  optimizer <- traverse rebaseOptimizer (manifestOptimizer manifest)
  rng <- traverse rebaseRng (manifestRng manifest)
  replay <- traverse rebasePointer (manifestReplayPointers manifest)
  transcripts <- traverse rebasePointer (manifestTranscriptPointers manifest)
  substrateArtifacts <- traverse rebaseSubstrateArtifact (manifestSubstrateArtifacts manifest)
  Right
    manifest
      { manifestTensors = tensors
      , manifestOptimizer = optimizer
      , manifestRng = rng
      , manifestReplayPointers = replay
      , manifestTranscriptPointers = transcripts
      , manifestSubstrateArtifacts = substrateArtifacts
      }
 where
  rebaseKey objectKey =
    maybe
      (Left ("snapshot rebase is missing physical key " <> objectKey))
      Right
      (Map.lookup objectKey keyMap)
  rebaseTensor tensor = do
    key <- rebaseKey (tensorBlobKey tensor)
    Right tensor {tensorBlobKey = key}
  rebaseOptimizer value = do
    key <- rebaseKey (optimizerBlobKey value)
    Right value {optimizerBlobKey = key}
  rebaseRng value = do
    key <- rebaseKey (rngBlobKey value)
    Right value {rngBlobKey = key}
  rebasePointer value = do
    key <- rebaseKey (artifactPointerObjectKey value)
    Right value {artifactPointerObjectKey = key}
  rebaseSubstrateArtifact value = do
    key <- traverse rebaseKey (substrateArtifactObjectKey value)
    Right value {substrateArtifactObjectKey = key}

manifestPhysicalObjectKeys :: CheckpointManifest -> [Text]
manifestPhysicalObjectKeys manifest =
  fmap tensorBlobKey (manifestTensors manifest)
    <> fmap optimizerBlobKey (manifestOptimizer manifest)
    <> fmap rngBlobKey (manifestRng manifest)
    <> fmap
      artifactPointerObjectKey
      (manifestReplayPointers manifest <> manifestTranscriptPointers manifest)
    <> [ objectKey
       | artifact <- manifestSubstrateArtifacts manifest
       , Just objectKey <- [substrateArtifactObjectKey artifact]
       ]

validateWriterReservation :: WriterReservation -> Either Text WriterReservation
validateWriterReservation reservation = do
  validateGcExperimentHash (writerReservationExperimentHash reservation)
  validateCanonicalSha256
    "writer reservation attempt id"
    (writerReservationAttemptId reservation)
  validateCanonicalSha256
    "writer reservation snapshot id"
    (writerReservationSnapshotId reservation)
  validateCanonicalSha256
    "writer reservation manifest SHA-256"
    (writerReservationManifestSha reservation)
  traverse_
    (validateCanonicalSha256 "writer reservation parent manifest SHA-256")
    (writerReservationParentManifestSha reservation)
  let expectedManifestKey =
        manifestKey
          (writerReservationExperimentHash reservation)
          (writerReservationManifestSha reservation)
  if writerReservationManifestObjectKey reservation == expectedManifestKey
    then Right ()
    else Left "writer reservation manifest object key does not bind its manifest SHA-256"
  validateWriterPointerIntent
    (writerReservationExperimentHash reservation)
    (writerReservationKind reservation)
    (writerReservationPointerIntent reservation)
  let physicalObjects = writerReservationPhysicalObjects reservation
      physicalObjectKeys = fmap writerPhysicalObjectKey physicalObjects
      originalKeys = fmap writerPhysicalObjectOriginalKey physicalObjects
  if physicalObjectKeys == Set.toAscList (Set.fromList physicalObjectKeys)
    then Right ()
    else Left "writer reservation physical objects are not canonical and unique"
  if length originalKeys == Set.size (Set.fromList originalKeys)
    then Right ()
    else Left "writer reservation original physical keys are not unique"
  traverse_
    ( validateWriterPhysicalObject
        (writerReservationExperimentHash reservation)
        (writerReservationSnapshotId reservation)
    )
    physicalObjects
  Right reservation

validateWriterCommit :: WriterCommit -> Either Text WriterCommit
validateWriterCommit commit = do
  validateGcExperimentHash (writerCommitExperimentHash commit)
  validateCanonicalSha256 "writer commit snapshot id" (writerCommitSnapshotId commit)
  validateCanonicalSha256
    "writer commit reservation id"
    (writerCommitReservationId commit)
  validateCanonicalSha256 "writer commit manifest SHA-256" (writerCommitManifestSha commit)
  let physicalObjects = writerCommitPhysicalObjects commit
      physicalObjectKeys = fmap writerPhysicalObjectKey physicalObjects
      originalKeys = fmap writerPhysicalObjectOriginalKey physicalObjects
  if physicalObjectKeys == Set.toAscList (Set.fromList physicalObjectKeys)
    then Right ()
    else Left "writer commit physical objects are not canonical and unique"
  if length originalKeys == Set.size (Set.fromList originalKeys)
    then Right ()
    else Left "writer commit original physical keys are not unique"
  traverse_
    ( validateWriterPhysicalObject
        (writerCommitExperimentHash commit)
        (writerCommitSnapshotId commit)
    )
    physicalObjects
  Right commit

validateWriterPhysicalObject
  :: Text
  -> Text
  -> WriterPhysicalObject
  -> Either Text ()
validateWriterPhysicalObject experimentHash snapshotId physicalObject = do
  let originalKey = writerPhysicalObjectOriginalKey physicalObject
      scopedKey = writerPhysicalObjectKey physicalObject
  canonicalOriginal <- canonicalGcPhysicalObjectKey experimentHash originalKey
  if canonicalOriginal == originalKey
    then Right ()
    else Left "writer physical object's original key is not canonical"
  if ("jitml-checkpoints/" <> experimentHash <> "/snapshots/")
    `Text.isPrefixOf` originalKey
    then Left "writer physical object's original key is already snapshot-scoped"
    else Right ()
  if scopedKey == snapshotPhysicalObjectKey experimentHash snapshotId originalKey
    then Right ()
    else Left "writer physical object's scoped key does not bind its original key"
  validateCanonicalSha256
    "writer physical object SHA-256"
    (writerPhysicalObjectSha physicalObject)

validateWriterPointerIntent
  :: Text
  -> WriterSnapshotKind
  -> WriterPointerIntent
  -> Either Text ()
validateWriterPointerIntent experimentHash kind pointerIntent =
  case (kind, pointerIntent) of
    (WriterCandidateSnapshot, WriterNoPointerIntent) -> Right ()
    (WriterCompletedSnapshot, WriterLatestPointerIntent pointerKey)
      | pointerKey /= latestPointerKey experimentHash ->
          Left "completed writer reservation does not target the exact latest pointer"
      | otherwise -> Right ()
    (WriterCandidateSnapshot, _) ->
      Left "candidate writer reservation must not contain a pointer intent"
    (WriterCompletedSnapshot, _) ->
      Left "completed writer reservation must contain the exact latest-pointer intent"

-- | Bind the durable transaction kind to the manifest's completion state.
-- Candidate commits are deliberately pointer-free and may never carry a
-- completion witness; a completed commit is legal only for a manifest that
-- carries that witness. Admission repeats this check over persisted bytes so a
-- forged candidate commit cannot bypass the completed-writer pointer CAS.
validateWriterSnapshotKindForManifest
  :: WriterSnapshotKind
  -> CheckpointManifest
  -> Either Text ()
validateWriterSnapshotKindForManifest kind manifest =
  case (kind, manifestCompletedTraining manifest) of
    (WriterCandidateSnapshot, Nothing) -> Right ()
    (WriterCompletedSnapshot, Just _) -> Right ()
    (WriterCandidateSnapshot, Just _) ->
      Left "candidate writer transaction cannot carry completed training"
    (WriterCompletedSnapshot, Nothing) ->
      Left "completed writer transaction requires completed training"

validateCanonicalSha256 :: Text -> Text -> Either Text ()
validateCanonicalSha256 label value
  | Text.length value == 64
      && Text.all (`elem` ("0123456789abcdef" :: String)) value =
      Right ()
  | otherwise = Left (label <> " is not 64 lowercase hexadecimal characters")

-- | True when a terminal or active GC record names any part of the exact
-- snapshot write.  Callers apply this uniformly to intent, ready, and
-- published event sets; cancelled records are intentionally nonterminal.
writerReservationOverlapsGcEvent :: WriterReservation -> GcEvent -> Bool
writerReservationOverlapsGcEvent reservation event =
  gcExperimentHash event == writerReservationExperimentHash reservation
    && ( gcReapedManifestSha event == writerReservationManifestSha reservation
           || Just (gcReapedManifestSha event)
             == writerReservationParentManifestSha reservation
           || not
             ( Set.null
                 ( Set.intersection
                     (Set.fromList (gcReapedObjectKeys event))
                     ( Set.fromList
                         ( snapshotControlObjectKey
                             (writerReservationExperimentHash reservation)
                             (writerReservationSnapshotId reservation)
                             "committed.cbor"
                             : fmap
                               writerPhysicalObjectKey
                               (writerReservationPhysicalObjects reservation)
                         )
                     )
                 )
             )
       )

gcEventsOverlap :: GcEvent -> GcEvent -> Bool
gcEventsOverlap first second =
  gcExperimentHash first == gcExperimentHash second
    && ( gcReapedManifestSha first == gcReapedManifestSha second
           || not
             ( Set.null
                 ( Set.intersection
                     (Set.fromList (gcReapedObjectKeys first))
                     (Set.fromList (gcReapedObjectKeys second))
                 )
             )
       )

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
    Right () ->
      case prepareCheckpointSnapshot
        WriterCandidateSnapshot
        WriterNoPointerIntent
        manifest
        payloads of
        Left err -> pure (Left (CheckpointWriteInvalid err))
        Right prepared -> do
          stored <- writeSnapshotObjectsLocal root prepared
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
    Right () ->
      let pointerIntent =
            WriterLatestPointerIntent
              (latestPointerKey (manifestExperiment manifest))
       in case prepareCheckpointSnapshot
            WriterCompletedSnapshot
            pointerIntent
            manifest
            payloads of
            Left err -> pure (Left (CheckpointWriteInvalid err))
            Right prepared -> do
              stored <- writeCompletedSnapshotAndPointerLocal root prepared expectedPointer
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
    Right () ->
      case prepareCheckpointSnapshot
        WriterCandidateSnapshot
        WriterNoPointerIntent
        manifest
        payloads of
        Left err -> pure (Left (SETransient err))
        Right prepared -> do
          stored <- writeSnapshotObjectsMinIO prepared
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
    Right () ->
      let pointerIntent =
            WriterLatestPointerIntent
              (latestPointerKey (manifestExperiment manifest))
       in case prepareCheckpointSnapshot
            WriterCompletedSnapshot
            pointerIntent
            manifest
            payloads of
            Left err -> pure (Left (SETransient err))
            Right prepared -> do
              stored <- writeCompletedSnapshotAndPointerMinIO prepared expectedPointer
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
validateSnapshotPayloads = validateSnapshotPayloadsWithSnapshotHashes Nothing

validateSnapshotPayloadsWithSnapshotHashes
  :: Maybe (Map.Map Text Text)
  -> CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> Either Text [LoadedWeightTensor]
validateSnapshotPayloadsWithSnapshotHashes snapshotHashes manifest payloads = do
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
          decodeLoadedWeightTensorWithSnapshotHashes snapshotHashes manifest tensor bytes
      )
      (manifestTensors manifest)
  traverse_
    ( \(binding, expectedLength) -> do
        bytes <- lookupSnapshotPayload (rawBlobObjectKey binding)
        case verifyRawBlobBinding snapshotHashes manifest binding expectedLength bytes of
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
  -> PreparedCheckpointSnapshot
  -> IO (Either CheckpointWriteError StoredCheckpoint)
writeSnapshotObjectsLocal root prepared = do
  started <-
    persistWriterReservationLocal root (preparedSnapshotReservationTemplate prepared)
  case started of
    Left err -> pure (Left err)
    Right reservation -> do
      committed <- loadMatchingWriterCommitLocal root prepared
      case committed of
        Left err -> pure (Left err)
        Right _ -> do
          payloadWrites <-
            traverse
              (uncurry (writeObjectIfAbsent root))
              (preparedSnapshotPayloads prepared)
          case sequence payloadWrites of
            Left err -> pure (Left err)
            Right _ -> do
              manifestWrite <-
                writeObjectIfAbsent
                  root
                  (writerReservationManifestObjectKey reservation)
                  (preparedSnapshotManifestBytes prepared)
              case manifestWrite of
                Left err -> pure (Left err)
                Right _ -> finishPreparedSnapshotLocal root prepared reservation

writeSnapshotObjectsMinIO
  :: (HasMinIO m)
  => PreparedCheckpointSnapshot
  -> m (Either ServiceError StoredCheckpoint)
writeSnapshotObjectsMinIO prepared = do
  started <-
    persistWriterReservationMinIO (preparedSnapshotReservationTemplate prepared)
  case started of
    Left err -> pure (Left err)
    Right reservation -> do
      safeToWrite <- writerReservationHasNoGcConflict reservation
      case safeToWrite of
        Left err -> pure (Left err)
        Right False ->
          pure (Left (SEConflict "checkpoint snapshot overlaps a GC terminal or active record"))
        Right True -> do
          committed <- loadMatchingWriterCommitMinIO prepared
          case committed of
            Left err -> pure (Left err)
            Right _ -> do
              payloadWrites <-
                traverse
                  ( \(objectKey, payload) ->
                      putObjectBytesIfAbsentOrSame
                        (checkpointObjectRef objectKey)
                        (LazyByteString.toStrict payload)
                  )
                  (preparedSnapshotPayloads prepared)
              case sequence payloadWrites of
                Left err -> pure (Left err)
                Right _ -> do
                  manifestWrite <-
                    putObjectBytesIfAbsentOrSame
                      ( checkpointObjectRef
                          ( writerReservationManifestObjectKey
                              reservation
                          )
                      )
                      (LazyByteString.toStrict (preparedSnapshotManifestBytes prepared))
                  case manifestWrite of
                    Left err -> pure (Left err)
                    Right () -> finishPreparedSnapshotMinIO prepared reservation

data LoadedWeightTensor = LoadedWeightTensor
  { loadedWeightTensor :: TensorBlob
  , loadedWeightValues :: [Double]
  , loadedWeightJmw1Bytes :: StrictByteString.ByteString
  }
  deriving stock (Eq, Show)

writeCompletedSnapshotAndPointerLocal
  :: FilePath
  -> PreparedCheckpointSnapshot
  -> Maybe Text
  -> IO (Either CheckpointWriteError StoredCheckpoint)
writeCompletedSnapshotAndPointerLocal root prepared expectedPointer = do
  started <-
    persistWriterReservationLocal root (preparedSnapshotReservationTemplate prepared)
  case started of
    Left err -> pure (Left err)
    Right reservation -> do
      committed <- loadMatchingWriterCommitLocal root prepared
      case committed of
        Left err -> pure (Left err)
        Right _ -> do
          payloadWrites <-
            traverse
              (uncurry (writeObjectIfAbsent root))
              (preparedSnapshotPayloads prepared)
          case sequence payloadWrites of
            Left err -> pure (Left err)
            Right _ -> do
              manifestWrite <-
                writeObjectIfAbsent
                  root
                  (writerReservationManifestObjectKey reservation)
                  (preparedSnapshotManifestBytes prepared)
              case manifestWrite of
                Left err -> pure (Left err)
                Right _ -> do
                  pointerWrite <-
                    writePointerCasLocalIdempotent
                      root
                      (latestPointerKey (manifestExperiment (preparedSnapshotManifest prepared)))
                      expectedPointer
                      (preparedSnapshotManifestSha prepared)
                  case pointerWrite of
                    Left err -> pure (Left err)
                    Right pointerResult -> do
                      finished <- finishPreparedSnapshotLocal root prepared reservation
                      pure $
                        fmap
                          (\stored -> stored {storedPointerResult = pointerResult})
                          finished

-- | Checkpoint snapshot writer over the production `HasMinIO` capability
-- boundary. Split blobs and manifests are byte-faithful write-once objects;
-- the latest pointer advances through `casPointer`.
writeCompletedSnapshotAndPointerMinIO
  :: (HasMinIO m)
  => PreparedCheckpointSnapshot
  -> Maybe ETag
  -> m (Either ServiceError StoredCheckpoint)
writeCompletedSnapshotAndPointerMinIO prepared expectedPointer = do
  started <-
    persistWriterReservationMinIO (preparedSnapshotReservationTemplate prepared)
  case started of
    Left err -> pure (Left err)
    Right reservation -> do
      safeToWrite <- writerReservationHasNoGcConflict reservation
      case safeToWrite of
        Left err -> pure (Left err)
        Right False ->
          pure (Left (SEConflict "checkpoint snapshot overlaps a GC terminal or active record"))
        Right True -> do
          committed <- loadMatchingWriterCommitMinIO prepared
          case committed of
            Left err -> pure (Left err)
            Right _ -> do
              blobWrites <-
                traverse
                  ( \(objectKey, payload) ->
                      putObjectBytesIfAbsentOrSame
                        (checkpointObjectRef objectKey)
                        (LazyByteString.toStrict payload)
                  )
                  (preparedSnapshotPayloads prepared)
              case sequence blobWrites of
                Left err -> pure (Left err)
                Right _ -> do
                  manifestWrite <-
                    putObjectBytesIfAbsentOrSame
                      ( checkpointObjectRef
                          ( writerReservationManifestObjectKey
                              reservation
                          )
                      )
                      (LazyByteString.toStrict (preparedSnapshotManifestBytes prepared))
                  case manifestWrite of
                    Left err -> pure (Left err)
                    Right () -> do
                      let pointerKey =
                            latestPointerKey
                              (manifestExperiment (preparedSnapshotManifest prepared))
                      pointerWrite <-
                        writePointerCasMinIOIdempotent
                          pointerKey
                          expectedPointer
                          (preparedSnapshotManifestSha prepared)
                      case pointerWrite of
                        Left err -> pure (Left err)
                        Right pointerResult -> do
                          finished <- finishPreparedSnapshotMinIO prepared reservation
                          pure $
                            fmap
                              (\stored -> stored {storedPointerResult = pointerResult})
                              finished

storedCheckpointFromPrepared :: PreparedCheckpointSnapshot -> StoredCheckpoint
storedCheckpointFromPrepared prepared =
  StoredCheckpoint
    { storedManifestSha = preparedSnapshotManifestSha prepared
    , storedManifestBodySha = preparedSnapshotManifestBodySha prepared
    , storedManifestObjectKey =
        writerReservationTemplateManifestObjectKey
          (preparedSnapshotReservationTemplate prepared)
    , storedPointerResult =
        PointerNotWritten
          (latestPointerKey (manifestExperiment (preparedSnapshotManifest prepared)))
    }

data ExperimentFenceMutation value
  = ExperimentFenceUnchanged value
  | ExperimentFenceChanged ExperimentGcFence value

emptyExperimentGcFence :: Text -> ExperimentGcFence
emptyExperimentGcFence experimentHash =
  ExperimentGcFence
    { experimentGcFenceVersion = experimentGcFenceWireVersion
    , experimentGcFenceRevision = 0
    , experimentGcFenceWriterEpoch = 0
    , experimentGcFenceExperimentHash = experimentHash
    , experimentGcFenceReservations = []
    , experimentGcFenceDecisions = []
    }

readExperimentGcFence
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError (ExperimentGcFence, ETag))
readExperimentGcFence experimentHash = do
  let ref = checkpointObjectRef (experimentGcFenceObjectKey experimentHash)
  loaded <- minioReadBytesWithETag ref
  pure $ do
    (bytes, etag) <- loaded
    encoded <-
      mapLeft
        (SETransient . ("experiment GC fence is not UTF-8: " <>) . Text.pack . show)
        (Text.Encoding.decodeUtf8' bytes)
    fence <-
      mapLeft
        (SETransient . ("invalid experiment GC fence: " <>))
        (decodeExperimentGcFence encoded)
    if experimentGcFenceExperimentHash fence == experimentHash
      then Right (fence, etag)
      else Left (SETransient "experiment GC fence address does not match its payload")

updateExperimentGcFence
  :: (HasMinIO m)
  => Text
  -> (ExperimentGcFence -> Either ServiceError (ExperimentFenceMutation value))
  -> m (Either ServiceError value)
updateExperimentGcFence experimentHash mutate = do
  let empty = emptyExperimentGcFence experimentHash
  bootstrapped <- casPointer ref Nothing (encodeExperimentGcFence empty)
  case bootstrapped of
    Right etag -> go (0 :: Int) empty etag
    Left (SEConflict _) -> do
      loaded <- readExperimentGcFence experimentHash
      case loaded of
        Left err -> pure (Left err)
        Right (fence, etag) -> go (0 :: Int) fence etag
    Left err -> pure (Left err)
 where
  ref = checkpointObjectRef (experimentGcFenceObjectKey experimentHash)

  go attempt base expectedEtag
    | attempt >= 4096 =
        pure (Left (SETransient "experiment GC fence CAS did not converge"))
    | otherwise = do
        case mutate base of
          Left err -> pure (Left err)
          Right (ExperimentFenceUnchanged value) -> pure (Right value)
          Right (ExperimentFenceChanged proposed value) ->
            if experimentGcFenceRevision base == maxBound
              then pure (Left (SETransient "experiment GC fence revision overflow"))
              else do
                let updated =
                      proposed
                        { experimentGcFenceVersion = experimentGcFenceWireVersion
                        , experimentGcFenceRevision = experimentGcFenceRevision base + 1
                        , experimentGcFenceExperimentHash = experimentHash
                        , experimentGcFenceReservations =
                            Set.toAscList
                              (Set.fromList (experimentGcFenceReservations proposed))
                        , experimentGcFenceDecisions =
                            sortOn gcFenceDecisionKey (experimentGcFenceDecisions proposed)
                        }
                case validateExperimentGcFence updated of
                  Left reason ->
                    pure (Left (SETransient ("invalid experiment GC fence transition: " <> reason)))
                  Right canonical -> do
                    written <-
                      casPointer
                        ref
                        (Just expectedEtag)
                        (encodeExperimentGcFence canonical)
                    case written of
                      Right _ -> pure (Right value)
                      Left (SEConflict _) -> do
                        latest <- readExperimentGcFence experimentHash
                        case latest of
                          Left err -> pure (Left err)
                          Right (observed, etag) -> go (attempt + 1) observed etag
                      Left err -> pure (Left err)

-- | Observe the monotonic writer/root-activity epoch. A first observation also
-- creates the canonical empty fence, so absence never acts as an unversioned
-- authorization state.
loadGcFenceEpoch
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError GcFenceEpoch)
loadGcFenceEpoch experimentHash = do
  bootstrapped <-
    updateExperimentGcFence experimentHash $ \_ ->
      Right (ExperimentFenceUnchanged ())
  case bootstrapped of
    Left err -> pure (Left err)
    Right () -> do
      loaded <- readExperimentGcFence experimentHash
      pure $ do
        (fence, _) <- loaded
        Right
          GcFenceEpoch
            { gcFenceEpochFence = fence
            }

data WriterFenceRegistration
  = WriterFenceSlotOccupied
  | WriterFenceRegistered [GcIntent]

registerNewWriterReservation
  :: (HasMinIO m)
  => WriterReservation
  -> m (Either ServiceError WriterFenceRegistration)
registerNewWriterReservation reservation =
  updateExperimentGcFence experimentHash $ \fence -> do
    let reservations = experimentGcFenceReservations fence
        sameAttempt =
          filter
            ((== writerReservationObjectKey reservation) . writerReservationObjectKey)
            reservations
    case sameAttempt of
      [observed]
        | observed == reservation ->
            Right (ExperimentFenceUnchanged WriterFenceSlotOccupied)
        | otherwise ->
            Left (SEConflict "experiment fence contains a substituted writer reservation")
      _ : _ -> Left (SETransient "experiment fence contains duplicate writer reservation keys")
      [] -> do
        if experimentGcFenceWriterEpoch fence == maxBound
          then Left (SETransient "experiment GC fence writer epoch overflow")
          else Right ()
        let overlappingDecisions =
              filter
                ( writerReservationOverlapsGcEvent reservation
                    . gcIntentEvent
                    . gcFenceDecisionIntent
                )
                (latestGcFenceDecisions (experimentGcFenceDecisions fence))
        case [ decision
             | decision <- overlappingDecisions
             , gcFenceDecisionPhase decision `elem` [GcFenceExecuting, GcFenceReaped]
             ] of
          [] -> Right ()
          _ ->
            Left
              ( SEConflict
                  "writer reservation overlaps an executing or reaped GC decision"
              )
        let cancelDecision decision
              | gcFenceDecisionKey decision
                  `elem` fmap gcFenceDecisionKey overlappingDecisions
              , gcFenceDecisionPhase decision == GcFencePlanned =
                  decision {gcFenceDecisionPhase = GcFenceCancelling}
              | otherwise = decision
            decisions = fmap cancelDecision (experimentGcFenceDecisions fence)
            cancellations =
              [ gcFenceDecisionIntent decision
              | decision <- latestGcFenceDecisions decisions
              , gcFenceDecisionKey decision
                  `elem` fmap gcFenceDecisionKey overlappingDecisions
              , gcFenceDecisionPhase decision == GcFenceCancelling
              ]
            updated =
              fence
                { experimentGcFenceWriterEpoch =
                    experimentGcFenceWriterEpoch fence + 1
                , experimentGcFenceReservations = reservation : reservations
                , experimentGcFenceDecisions = decisions
                }
        Right
          ( ExperimentFenceChanged
              updated
              (WriterFenceRegistered (Set.toAscList (Set.fromList cancellations)))
          )
 where
  experimentHash = writerReservationExperimentHash reservation

removeWriterReservationFromFence
  :: (HasMinIO m)
  => WriterReservation
  -> m (Either ServiceError ())
removeWriterReservationFromFence reservation =
  updateExperimentGcFence (writerReservationExperimentHash reservation) $ \fence -> do
    let matching =
          filter
            ((== writerReservationObjectKey reservation) . writerReservationObjectKey)
            (experimentGcFenceReservations fence)
    case matching of
      [] ->
        Left (SEConflict "writer reservation is absent from the experiment fence")
      [observed]
        | observed /= reservation ->
            Left (SEConflict "writer reservation key belongs to a different reservation")
        | experimentGcFenceWriterEpoch fence == maxBound ->
            Left (SETransient "experiment GC fence writer epoch overflow")
        | otherwise ->
            let remaining =
                  filter (/= reservation) (experimentGcFenceReservations fence)
             in Right
                  ( ExperimentFenceChanged
                      fence
                        { experimentGcFenceWriterEpoch =
                            experimentGcFenceWriterEpoch fence + 1
                        , experimentGcFenceReservations = remaining
                        }
                      ()
                  )
      _ -> Left (SETransient "duplicate writer reservation keys in the experiment fence")

persistWriterReservationLocal
  :: FilePath
  -> WriterReservationTemplate
  -> IO (Either CheckpointWriteError WriterReservation)
persistWriterReservationLocal root template = go (0 :: Int)
 where
  go slot
    | slot >= 4096 =
        pure
          ( Left
              ( CheckpointWriteIOFailure
                  (writerReservationTemplateSnapshotId template)
                  "could not allocate a unique writer-attempt reservation"
              )
          )
    | otherwise =
        case instantiateWriterReservation
          (writerAttemptIdForSlot slot)
          template of
          Left err -> pure (Left (CheckpointWriteInvalid err))
          Right reservation -> do
            written <-
              writeObjectIfAbsent
                root
                (writerReservationObjectKey reservation)
                (LazyByteString.fromStrict (encodeWriterReservation reservation))
            case written of
              Right (ObjectCreated _) -> pure (Right reservation)
              Right (ObjectAlreadyPresent _) -> go (slot + 1)
              Left (CheckpointWriteObjectConflict _ _) -> go (slot + 1)
              Left err -> pure (Left err)

persistWriterReservationMinIO
  :: (HasMinIO m)
  => WriterReservationTemplate
  -> m (Either ServiceError WriterReservation)
persistWriterReservationMinIO template = go (0 :: Int)
 where
  go slot
    | slot >= 4096 =
        pure (Left (SETransient "could not allocate a unique writer-attempt reservation"))
    | otherwise =
        case instantiateWriterReservation
          (writerAttemptIdForSlot slot)
          template of
          Left err -> pure (Left (SETransient err))
          Right reservation -> do
            registered <- registerNewWriterReservation reservation
            case registered of
              Left err -> pure (Left err)
              Right WriterFenceSlotOccupied -> go (slot + 1)
              Right (WriterFenceRegistered cancellations) -> do
                cancelled <- cancelGcIntents cancellations
                case cancelled of
                  Left failures ->
                    pure
                      ( Left
                          ( SETransient
                              ( "writer registered but GC cancellation persistence failed: "
                                  <> Text.pack (show failures)
                              )
                          )
                      )
                  Right _ -> do
                    written <-
                      putBlobBytesIfAbsent
                        (checkpointObjectRef (writerReservationObjectKey reservation))
                        (encodeWriterReservation reservation)
                    case written of
                      Left (SEConflict _) -> go (slot + 1)
                      Left err -> pure (Left err)
                      Right _ -> do
                        settled <- settleWriterGcConflicts reservation
                        pure (reservation <$ settled)

finishPreparedSnapshotLocal
  :: FilePath
  -> PreparedCheckpointSnapshot
  -> WriterReservation
  -> IO (Either CheckpointWriteError StoredCheckpoint)
finishPreparedSnapshotLocal root prepared reservation = do
  committed <-
    writeObjectIfAbsent
      root
      (writerCommitObjectKey (preparedSnapshotCommit prepared))
      (LazyByteString.fromStrict (encodeWriterCommit (preparedSnapshotCommit prepared)))
  case committed of
    Left err -> pure (Left err)
    Right _ -> do
      cleaned <-
        deleteLocalObject
          root
          (writerReservationObjectKey reservation)
      pure (storedCheckpointFromPrepared prepared <$ cleaned)

finishPreparedSnapshotMinIO
  :: (HasMinIO m)
  => PreparedCheckpointSnapshot
  -> WriterReservation
  -> m (Either ServiceError StoredCheckpoint)
finishPreparedSnapshotMinIO prepared reservation = do
  committed <-
    putObjectBytesIfAbsentOrSame
      (checkpointObjectRef (writerCommitObjectKey (preparedSnapshotCommit prepared)))
      (encodeWriterCommit (preparedSnapshotCommit prepared))
  case committed of
    Left err -> pure (Left err)
    Right () -> finishCommittedRetryMinIO prepared reservation

finishCommittedRetryMinIO
  :: (HasMinIO m)
  => PreparedCheckpointSnapshot
  -> WriterReservation
  -> m (Either ServiceError StoredCheckpoint)
finishCommittedRetryMinIO prepared reservation = do
  -- Re-read the durable GC handshake after every payload/manifest/pointer/
  -- commit mutation and immediately before releasing this attempt's marker.
  -- If GC installed an intent after the writer's initial scan, keeping the
  -- marker makes the GC fresh-view pass cancel that whole intent. Conversely,
  -- if GC already observed the marker and durably cancelled its intent, this
  -- scan sees the cancellation and may release the completed transaction.
  finalFence <- writerReservationHasNoGcConflict reservation
  case finalFence of
    Left err -> pure (Left err)
    Right False ->
      pure
        ( Left
            ( SEConflict
                "checkpoint snapshot completed but remains fenced by a GC terminal or active record"
            )
        )
    Right True -> do
      cleaned <-
        deleteObject
          (checkpointObjectRef (writerReservationObjectKey reservation))
      case cleaned of
        Left err -> pure (Left err)
        Right () -> do
          released <- removeWriterReservationFromFence reservation
          pure (storedCheckpointFromPrepared prepared <$ released)

deleteLocalObject
  :: FilePath
  -> Text
  -> IO (Either CheckpointWriteError ())
deleteLocalObject root objectKey =
  case objectPathForKey root objectKey of
    Left err -> pure (Left (CheckpointWriteInvalid err))
    Right path -> do
      exists <- doesFileExist path
      if not exists
        then pure (Right ())
        else do
          deleted <- try (removeFile path) :: IO (Either IOException ())
          pure $
            mapLeft
              (CheckpointWriteIOFailure objectKey . Text.pack . show)
              deleted

loadMatchingWriterCommitLocal
  :: FilePath
  -> PreparedCheckpointSnapshot
  -> IO (Either CheckpointWriteError Bool)
loadMatchingWriterCommitLocal root prepared =
  let expected = preparedSnapshotCommit prepared
      objectKey = writerCommitObjectKey expected
   in case objectPathForKey root objectKey of
        Left err -> pure (Left (CheckpointWriteInvalid err))
        Right path -> do
          exists <- doesFileExist path
          if not exists
            then pure (Right False)
            else do
              bytesResult <-
                try (StrictByteString.readFile path)
                  :: IO (Either IOException StrictByteString.ByteString)
              pure $ do
                bytes <-
                  mapLeft
                    (CheckpointWriteIOFailure objectKey . Text.pack . show)
                    bytesResult
                observed <-
                  mapLeft
                    (CheckpointWriteObjectConflict objectKey)
                    (decodeWriterCommit bytes)
                if observed == expected
                  then Right True
                  else
                    Left
                      ( CheckpointWriteObjectConflict
                          objectKey
                          "existing commit belongs to a different exact snapshot write"
                      )

loadMatchingWriterCommitMinIO
  :: (HasMinIO m)
  => PreparedCheckpointSnapshot
  -> m (Either ServiceError Bool)
loadMatchingWriterCommitMinIO prepared = do
  commits <-
    loadWriterCommits
      (writerCommitExperimentHash (preparedSnapshotCommit prepared))
  pure $ do
    values <- commits
    case filter
      ( (== writerCommitSnapshotId (preparedSnapshotCommit prepared))
          . writerCommitSnapshotId
      )
      values of
      [] -> Right False
      [observed]
        | observed == preparedSnapshotCommit prepared -> Right True
        | otherwise ->
            Left (SEConflict "existing writer commit belongs to a different exact snapshot write")
      _ -> Left (SETransient "duplicate writer commits for one storage snapshot")

writerReservationHasNoGcConflict
  :: (HasMinIO m)
  => WriterReservation
  -> m (Either ServiceError Bool)
writerReservationHasNoGcConflict reservation = do
  settled <- settleWriterGcConflicts reservation
  pure (True <$ settled)

settleWriterGcConflicts
  :: (HasMinIO m)
  => WriterReservation
  -> m (Either ServiceError ())
settleWriterGcConflicts reservation = go (0 :: Int)
 where
  experimentHash = writerReservationExperimentHash reservation

  go attempt
    | attempt >= 4096 =
        pure (Left (SETransient "writer GC-conflict settlement did not converge"))
    | otherwise = do
        registered <- writerIsRegisteredInFence reservation
        case registered of
          Left err -> pure (Left err)
          Right () -> do
            pendingResult <- loadGcIntents experimentHash
            cancelledResult <- loadGcCancelledIntents experimentHash
            readyResult <- loadGcReadyEvents experimentHash
            publishedResult <- loadGcPublishedEvents experimentHash
            case (,,,)
              <$> pendingResult
              <*> cancelledResult
              <*> readyResult
              <*> publishedResult of
              Left err -> pure (Left err)
              Right (pending, cancelled, ready, published) ->
                case validateGcTerminalRelations pending cancelled ready published of
                  Left err -> pure (Left err)
                  Right () -> do
                    helped <- helpGcCancellations cancelled
                    case helped of
                      Left failures ->
                        pure
                          ( Left
                              ( SETransient
                                  ( "writer GC cancellation recovery failed: "
                                      <> Text.pack (show failures)
                                  )
                              )
                          )
                      Right completed
                        | not (null completed) -> go (attempt + 1)
                      Right _ -> settlePending attempt pending cancelled ready published

  settlePending attempt pending cancelled ready published = do
    let terminalEvents = fmap gcReadyEvent (ready <> published)
    if any (writerReservationOverlapsGcEvent reservation) terminalEvents
      then
        pure
          ( Left
              ( SEConflict
                  "writer reservation overlaps a publish-ready or published GC event"
              )
          )
      else do
        let cancelledIds =
              Set.fromList (fmap gcIntentEventId cancelled)
            overlaps =
              [ intent
              | intent <- pending
              , gcIntentEventId intent `Set.notMember` cancelledIds
              , writerReservationOverlapsGcEvent reservation (gcIntentEvent intent)
              ]
        if null overlaps
          then writerIsRegisteredInFence reservation
          else do
            cancelledNow <- cancelGcIntents overlaps
            case cancelledNow of
              Left failures ->
                pure
                  ( Left
                      ( SETransient
                          ( "writer GC cancellation failed: "
                              <> Text.pack (show failures)
                          )
                      )
                  )
              Right _ -> go (attempt + 1)

writerIsRegisteredInFence
  :: (HasMinIO m)
  => WriterReservation
  -> m (Either ServiceError ())
writerIsRegisteredInFence reservation = do
  loaded <- readExperimentGcFence (writerReservationExperimentHash reservation)
  pure $ do
    (fence, _) <- loaded
    let matching =
          filter
            ((== writerReservationObjectKey reservation) . writerReservationObjectKey)
            (experimentGcFenceReservations fence)
    case matching of
      [observed]
        | observed == reservation -> Right ()
        | otherwise -> Left (SEConflict "experiment fence contains a substituted writer reservation")
      [] -> Left (SEConflict "writer reservation is absent from the experiment fence")
      _ -> Left (SETransient "experiment fence contains duplicate writer reservation keys")

validateGcTerminalRelations
  :: [GcIntent]
  -> [GcIntent]
  -> [GcReadyEvent]
  -> [GcReadyEvent]
  -> Either ServiceError ()
validateGcTerminalRelations intents cancelled ready published = do
  validateUniqueIds "active intent" gcIntentEventId intents
  validateUniqueIds "cancelled intent" gcIntentEventId cancelled
  validateUniqueIds "ready event" gcReadyEventId ready
  validateUniqueIds "published event" gcReadyEventId published
  if Set.null (Set.intersection cancelledIds readyIds)
    then Right ()
    else Left (SEConflict "GC event is both cancelled and publish-ready")
  if Set.null (Set.intersection cancelledIds publishedIds)
    then Right ()
    else Left (SEConflict "GC event is both cancelled and published")
  traverse_ validateCancelled cancelled
  traverse_ validateReady ready
  traverse_ validatePublished published
 where
  intentsById = Map.fromList [(gcIntentEventId value, value) | value <- intents]
  readyById = Map.fromList [(gcReadyEventId value, value) | value <- ready]
  cancelledIds = Set.fromList (fmap gcIntentEventId cancelled)
  readyIds = Set.fromList (fmap gcReadyEventId ready)
  publishedIds = Set.fromList (fmap gcReadyEventId published)

  validateUniqueIds label identify values =
    let ids = fmap identify values
     in if length ids == Set.size (Set.fromList ids)
          then Right ()
          else Left (SEConflict ("duplicate GC " <> label <> " event id"))

  validateCancelled value =
    case Map.lookup (gcIntentEventId value) intentsById of
      Nothing -> Right ()
      Just active
        | active == value -> Right ()
        | otherwise -> Left (SEConflict "GC cancellation conflicts with its active intent")

  validateReady value =
    case Map.lookup (gcReadyEventId value) intentsById of
      Nothing -> Right ()
      Just active
        | gcIntentEvent active == gcReadyEvent value -> Right ()
        | otherwise -> Left (SEConflict "GC ready event conflicts with its active intent")

  validatePublished value = do
    case Map.lookup (gcReadyEventId value) intentsById of
      Nothing -> Right ()
      Just active
        | gcIntentEvent active == gcReadyEvent value -> Right ()
        | otherwise -> Left (SEConflict "published GC tombstone conflicts with its intent")
    case Map.lookup (gcReadyEventId value) readyById of
      Nothing -> Right ()
      Just pendingReady
        | pendingReady == value -> Right ()
        | otherwise -> Left (SEConflict "published GC tombstone differs from ready state")

writePointerCasLocalIdempotent
  :: FilePath
  -> Text
  -> Maybe Text
  -> Text
  -> IO (Either CheckpointWriteError PointerWriteResult)
writePointerCasLocalIdempotent root pointerKey expectedPointer proposedManifestSha = do
  written <-
    writePointerCasLocal
      root
      pointerKey
      expectedPointer
      proposedManifestSha
  case written of
    Left (CheckpointWritePointerConflict _) -> do
      current <- readCheckpointPointer root pointerKey
      pure $
        case current of
          Right (Just currentSha)
            | currentSha == proposedManifestSha -> Right (PointerWritten proposedManifestSha)
          Right _ -> Right (PointerConflict pointerKey)
          Left err -> Left (CheckpointWriteIOFailure pointerKey err)
    other -> pure other

writePointerCasMinIOIdempotent
  :: (HasMinIO m)
  => Text
  -> Maybe ETag
  -> Text
  -> m (Either ServiceError PointerWriteResult)
writePointerCasMinIOIdempotent pointerKey expectedPointer proposedManifestSha = do
  written <-
    casPointer
      (checkpointObjectRef pointerKey)
      expectedPointer
      proposedManifestSha
  case written of
    Right _ -> pure (Right (PointerWritten proposedManifestSha))
    Left (SEConflict _) -> do
      current <- minioReadBytes (checkpointObjectRef pointerKey)
      pure $ do
        bytes <- current
        case parseCanonicalPointerBody bytes of
          Right currentSha
            | currentSha == proposedManifestSha -> Right (PointerWritten proposedManifestSha)
          _ -> Right (PointerConflict pointerKey)
    Left err -> pure (Left err)

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
                        Right () -> do
                          committed <- validateSnapshotCommitForAdmissionMinIO addressed
                          case committed of
                            Left err -> pure (Left err)
                            Right commit -> bindAddressedCheckpointMinIO commit addressed

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
        Right addressed -> do
          committed <- validateSnapshotCommitForAdmissionMinIO addressed
          case committed of
            Left err -> pure (Left err)
            Right commit -> bindAddressedCheckpointMinIO commit addressed

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

validateSnapshotCommitForAdmissionMinIO
  :: (HasMinIO m)
  => AddressedCheckpointManifest
  -> m (Either CheckpointAdmissionError WriterCommit)
validateSnapshotCommitForAdmissionMinIO addressed =
  do
    commitsResult <-
      loadWriterCommits (manifestExperiment (addressedManifest addressed))
    pure $ do
      commits <-
        mapLeft
          (AdmissionSnapshotCommitInvalid . Text.pack . show)
          commitsResult
      validateSnapshotCommitForAdmissionWithCommits addressed commits

validateSnapshotCommitForAdmissionWithCommits
  :: AddressedCheckpointManifest
  -> [WriterCommit]
  -> Either CheckpointAdmissionError WriterCommit
validateSnapshotCommitForAdmissionWithCommits addressed commits = do
  snapshotId <-
    mapLeft
      AdmissionSnapshotCommitInvalid
      (requiredStorageSnapshotIdForAdmission (addressedManifest addressed))
  requireMatchingSnapshotCommit addressed snapshotId commits

requireMatchingSnapshotCommit
  :: AddressedCheckpointManifest
  -> Text
  -> [WriterCommit]
  -> Either CheckpointAdmissionError WriterCommit
requireMatchingSnapshotCommit addressed snapshotId commits =
  case [ commit
       | commit <- commits
       , writerCommitSnapshotId commit == snapshotId
       ] of
    [commit]
      | writerCommitExperimentHash commit /= manifestExperiment manifest ->
          Left (AdmissionSnapshotCommitInvalid "commit experiment does not match manifest")
      | writerCommitManifestSha commit /= addressedManifestSha addressed ->
          Left (AdmissionSnapshotCommitInvalid "commit does not bind the exact manifest bytes")
      | otherwise -> do
          validateCommitPhysicalGraph manifest commit
          Right commit
    [] ->
      Left
        ( AdmissionSnapshotCommitInvalid
            ("snapshot " <> snapshotId <> " has no durable commit")
        )
    _ ->
      Left
        ( AdmissionSnapshotCommitInvalid
            ("snapshot " <> snapshotId <> " has duplicate durable commits")
        )
 where
  manifest = addressedManifest addressed

validateCommitPhysicalGraph
  :: CheckpointManifest
  -> WriterCommit
  -> Either CheckpointAdmissionError ()
validateCommitPhysicalGraph manifest commit = do
  mapLeft AdmissionSnapshotCommitInvalid $
    validateWriterSnapshotKindForManifest (writerCommitKind commit) manifest
  snapshotId <-
    mapLeft AdmissionSnapshotCommitInvalid (requiredStorageSnapshotIdForAdmission manifest)
  if snapshotId == writerCommitSnapshotId commit
    then Right ()
    else
      Left
        (AdmissionSnapshotCommitInvalid "commit snapshot id does not match manifest namespace")
  let expectedKeys = sort (manifestPhysicalObjectKeys manifest)
      observedKeys = fmap writerPhysicalObjectKey (writerCommitPhysicalObjects commit)
  if observedKeys == expectedKeys
    then Right ()
    else
      Left
        ( AdmissionSnapshotCommitInvalid
            "commit physical-object table does not exactly equal the manifest graph"
        )
  mapLeft AdmissionSnapshotCommitInvalid $
    validateSnapshotDescriptor manifest snapshotId (writerCommitPhysicalObjects commit)
  let expectedPointerIntent =
        case writerCommitKind commit of
          WriterCandidateSnapshot -> WriterNoPointerIntent
          WriterCompletedSnapshot ->
            WriterLatestPointerIntent (latestPointerKey (manifestExperiment manifest))
      expectedReservationTemplate =
        WriterReservationTemplate
          { writerReservationTemplateExperimentHash = manifestExperiment manifest
          , writerReservationTemplateSnapshotId = snapshotId
          , writerReservationTemplateManifestObjectKey =
              manifestKey (manifestExperiment manifest) (writerCommitManifestSha commit)
          , writerReservationTemplateManifestSha = writerCommitManifestSha commit
          , writerReservationTemplateParentManifestSha = manifestParentManifestSha manifest
          , writerReservationTemplatePhysicalObjects = writerCommitPhysicalObjects commit
          , writerReservationTemplateKind = writerCommitKind commit
          , writerReservationTemplatePointerIntent = expectedPointerIntent
          }
  if writerCommitReservationId commit
    == writerReservationTemplateId expectedReservationTemplate
    then Right ()
    else
      Left
        ( AdmissionSnapshotCommitInvalid
            "commit reservation identity does not bind the exact manifest transaction"
        )

validateReservationPhysicalGraph
  :: AddressedCheckpointManifest
  -> Text
  -> WriterReservation
  -> Either Text ()
validateReservationPhysicalGraph addressed snapshotId reservation = do
  let manifest = addressedManifest addressed
      expectedKeys = sort (manifestPhysicalObjectKeys manifest)
      observedKeys = fmap writerPhysicalObjectKey (writerReservationPhysicalObjects reservation)
  validateWriterSnapshotKindForManifest (writerReservationKind reservation) manifest
  if writerReservationExperimentHash reservation == manifestExperiment manifest
    then Right ()
    else Left "active writer reservation experiment does not match manifest"
  if writerReservationSnapshotId reservation == snapshotId
    then Right ()
    else Left "active writer reservation snapshot id does not match manifest"
  if writerReservationManifestSha reservation == addressedManifestSha addressed
    then Right ()
    else Left "active writer reservation does not bind the exact manifest bytes"
  if writerReservationManifestObjectKey reservation
    == manifestKey (manifestExperiment manifest) (addressedManifestSha addressed)
    then Right ()
    else Left "active writer reservation manifest object key does not match"
  if writerReservationParentManifestSha reservation == manifestParentManifestSha manifest
    then Right ()
    else Left "active writer reservation parent manifest does not match"
  if observedKeys == expectedKeys
    then Right ()
    else Left "active writer reservation physical-object table does not equal manifest graph"
  validateSnapshotDescriptor
    manifest
    snapshotId
    (writerReservationPhysicalObjects reservation)

-- | Reconstruct the pre-rebase logical manifest from the persisted
-- original-to-scoped ownership table and rederive the snapshot namespace. This
-- turns the snapshot id into a checkable content identity at admission/GC time
-- instead of trusting the path prefix recorded by the writer.
validateSnapshotDescriptor
  :: CheckpointManifest
  -> Text
  -> [WriterPhysicalObject]
  -> Either Text ()
validateSnapshotDescriptor storedManifest snapshotId physicalObjects = do
  let originalByScoped =
        Map.fromList
          [ (writerPhysicalObjectKey physicalObject, writerPhysicalObjectOriginalKey physicalObject)
          | physicalObject <- physicalObjects
          ]
  if Map.size originalByScoped == length physicalObjects
    then Right ()
    else Left "snapshot descriptor repeats a scoped physical key"
  logicalManifest <- rebaseManifestPhysicalKeys originalByScoped storedManifest
  let originalBindings =
        [ (writerPhysicalObjectOriginalKey physicalObject, writerPhysicalObjectSha physicalObject)
        | physicalObject <- physicalObjects
        ]
      derivedSnapshotId =
        deriveCheckpointStorageSnapshotId logicalManifest originalBindings
  if derivedSnapshotId == snapshotId
    then Right ()
    else Left "snapshot id does not bind the reconstructed logical manifest and payload table"

bindAddressedCheckpointMinIO
  :: (HasMinIO m)
  => WriterCommit
  -> AddressedCheckpointManifest
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
bindAddressedCheckpointMinIO commit =
  bindAddressedCheckpointWith
    commit
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
                      | otherwise -> do
                          committed <- validateSnapshotCommitForAdmissionLocal root addressed
                          case committed of
                            Left err -> pure (Left err)
                            Right commit -> bindAddressedCheckpointLocal root commit addressed

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
            Right addressed -> do
              committed <- validateSnapshotCommitForAdmissionLocal root addressed
              case committed of
                Left err -> pure (Left err)
                Right commit -> bindAddressedCheckpointLocal root commit addressed

validateSnapshotCommitForAdmissionLocal
  :: FilePath
  -> AddressedCheckpointManifest
  -> IO (Either CheckpointAdmissionError WriterCommit)
validateSnapshotCommitForAdmissionLocal root addressed =
  case requiredStorageSnapshotIdForAdmission (addressedManifest addressed) of
    Left err -> pure (Left (AdmissionSnapshotCommitInvalid err))
    Right snapshotId -> do
      let experimentHash = manifestExperiment (addressedManifest addressed)
          objectKey = snapshotControlObjectKey experimentHash snapshotId "committed.cbor"
      bytesResult <- readObjectStrict root objectKey
      pure $ do
        bytes <-
          mapLeft
            ( \reason ->
                AdmissionSnapshotCommitInvalid
                  ("cannot read exact commit " <> objectKey <> ": " <> reason)
            )
            bytesResult
        commit <-
          mapLeft AdmissionSnapshotCommitInvalid (decodeWriterCommit bytes)
        requireMatchingSnapshotCommit addressed snapshotId [commit]

requiredStorageSnapshotIdForAdmission
  :: CheckpointManifest
  -> Either Text Text
requiredStorageSnapshotIdForAdmission manifest = do
  storageSnapshotId <- checkpointStorageSnapshotId manifest
  case storageSnapshotId of
    Just snapshotId -> Right snapshotId
    Nothing
      | null (manifestPhysicalObjectKeys manifest) ->
          Right (deriveCheckpointStorageSnapshotId manifest [])
      | otherwise ->
          Left "legacy unscoped manifests are readable but cannot be admitted"

bindAddressedCheckpointLocal
  :: FilePath
  -> WriterCommit
  -> AddressedCheckpointManifest
  -> IO (Either CheckpointAdmissionError AdmittedCheckpoint)
bindAddressedCheckpointLocal root commit =
  bindAddressedCheckpointWith
    commit
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
  -- The one self-describing envelope decodes to exactly two payload variants
  -- (weight-only and supervised-graph), both structurally admissible; there is
  -- no per-version allow-list. Payload-variant classification happens once, at
  -- the completed-admission boundary (`validateCompletedAdmissionScope`).
  let manifest = addressedManifest addressed
  case validateLoadedManifest
    experimentHash
    expectedManifestSha
    (addressedManifestSha addressed)
    manifest of
    Left err -> Left (AdmissionManifestInvalid err)
    Right _ -> Right addressed

bindAddressedCheckpointWith
  :: (Monad m)
  => WriterCommit
  -> (Text -> m (Either CheckpointAdmissionError StrictByteString.ByteString))
  -> AddressedCheckpointManifest
  -> m (Either CheckpointAdmissionError AdmittedCheckpoint)
bindAddressedCheckpointWith commit fetch addressed = do
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
                    (decodeLoadedWeightTensorWithSnapshotHashes snapshotHashes manifest tensor bytes)
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
  snapshotHashes =
    Just
      ( Map.fromList
          [ (writerPhysicalObjectKey physicalObject, writerPhysicalObjectSha physicalObject)
          | physicalObject <- writerCommitPhysicalObjects commit
          ]
      )
  fetchAndVerifyRawBlob binding expectedLength = do
    payload <- fetch (rawBlobObjectKey binding)
    pure $ do
      bytes <- payload
      verifyRawBlobBinding
        snapshotHashes
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
  :: Maybe (Map.Map Text Text)
  -> CheckpointManifest
  -> RawBlobBinding
  -> Maybe Int
  -> StrictByteString.ByteString
  -> Either CheckpointAdmissionError ()
verifyRawBlobBinding snapshotHashes manifest binding expectedLength bytes = do
  let actualSha = exactBytesSha bytes
      canonicalKey = blobKey (manifestExperiment manifest) actualSha
  case snapshotHashes of
    Just hashes ->
      requireSnapshotPayloadHash
        hashes
        (rawBlobObjectKey binding)
        actualSha
        (rawBlobLabel binding)
    Nothing ->
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
        Just _ -> Right ()
  case rawBlobExpectedSha binding of
    Nothing -> Right ()
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

requireSnapshotPayloadHash
  :: Map.Map Text Text
  -> Text
  -> Text
  -> Text
  -> Either CheckpointAdmissionError ()
requireSnapshotPayloadHash hashes objectKey actualSha label =
  case Map.lookup objectKey hashes of
    Nothing ->
      Left
        ( AdmissionBlobInvalid
            (label <> " has no exact payload hash in its writer commit")
        )
    Just expectedSha
      | expectedSha == actualSha -> Right ()
      | otherwise ->
          Left
            ( AdmissionBlobInvalid
                ( label
                    <> " writer-commit SHA-256 mismatch: expected "
                    <> expectedSha
                    <> ", got "
                    <> actualSha
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
validateCompletedAdmissionScope admitted
  | addressedManifestWireVersion (admittedAddressedManifestInternal admitted)
      == checkpointWireVersionV2 =
      -- Supervised-graph payload: admissible only with no companion pointer; the
      -- supervised weights are the whole payload, so a stray replay/transcript
      -- companion is a category error.
      if null (manifestReplayPointers manifest)
        && null (manifestTranscriptPointers manifest)
        then Right ()
        else
          Left
            ( AdmissionCompletedV1CompanionInvalid
                "supervised-graph checkpoint must not carry a companion pointer"
            )
  | otherwise =
      -- Weight-only payload: only an authoritative non-supervised ProductRow
      -- with its exact family companion may proceed to structural completion.
      -- Historical or generic supervised weight-only then fails that refinement
      -- because it lacks the exact supervised runtime artifact.
      case ProductMatrix.productRowForExperimentHash experimentHash of
        Just row
          | ProductMatrix.family row == ProductMatrix.Supervised -> Right ()
          | otherwise -> validateCompletedV1ProductCompanion row manifest
        Nothing -> Left (AdmissionCompletedV1ProductRowRequired experimentHash)
 where
  manifest = admittedCheckpointManifest admitted
  experimentHash = manifestExperiment manifest

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
  storageSnapshotId <-
    mapLeft AdmissionCompletedV1CompanionInvalid (checkpointStorageSnapshotId manifest)
  case storageSnapshotId of
    Nothing -> do
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
                ( "legacy companion object key for "
                    <> ProductMatrix.rowId row
                    <> " is not its canonical content address: expected "
                    <> expectedObjectKey
                    <> ", got "
                    <> artifactPointerObjectKey pointer
                )
            )
    Just snapshotId -> do
      let expectedOriginalKey =
            canonicalProductCompanionObjectKey
              (manifestExperiment manifest)
              expectedKind
              pointerSha
          expectedScopedKey =
            snapshotPhysicalObjectKey
              (manifestExperiment manifest)
              snapshotId
              expectedOriginalKey
      if artifactPointerObjectKey pointer == expectedScopedKey
        then Right ()
        else
          Left
            ( AdmissionCompletedV1CompanionInvalid
                ( "companion object key for "
                    <> ProductMatrix.rowId row
                    <> " is not the exact snapshot-scoped canonical content address: expected "
                    <> expectedScopedKey
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
          pure (catMaybes <$> sequence decoded)
 where
  isManifestFile path = ".cbor" `Text.isSuffixOf` Text.pack path

  readManifestEntry manifestDir entry = do
    payload <- LazyByteString.readFile (manifestDir </> entry)
    case do
      expectedSha <-
        case Text.stripSuffix ".cbor" (Text.pack entry) of
          Nothing -> Left ("invalid manifest filename: " <> Text.pack entry)
          Just sha -> Right sha
      addressed <- decodeAddressedManifestCbor payload
      _ <-
        validateAddressedManifest
          experimentHash
          expectedSha
          (addressedManifestSha addressed)
          (addressedManifest addressed)
      Right addressed of
      Left err -> pure (Left err)
      Right addressed -> do
        gcEligibleManifestLocal root addressed

gcEligibleManifestLocal
  :: FilePath
  -> AddressedCheckpointManifest
  -> IO (Either Text (Maybe CheckpointManifest))
gcEligibleManifestLocal root addressed =
  case checkpointStorageSnapshotId manifest of
    Left err -> pure (Left err)
    Right Nothing
      | not (null (manifestPhysicalObjectKeys manifest)) -> pure (Right Nothing)
    Right _ ->
      case requiredStorageSnapshotIdForAdmission manifest of
        Left err -> pure (Left err)
        Right snapshotId -> do
          let commitKey = snapshotControlObjectKey experimentHash snapshotId "committed.cbor"
              commitPathResult = objectPathForKey root commitKey
          case commitPathResult of
            Left err -> pure (Left err)
            Right commitPath -> do
              commitExists <- doesFileExist commitPath
              if commitExists
                then do
                  commitBytes <- StrictByteString.readFile commitPath
                  pure $ do
                    commit <- decodeWriterCommit commitBytes
                    _ <-
                      mapLeft
                        renderCheckpointAdmissionError
                        (requireMatchingSnapshotCommit addressed snapshotId [commit])
                    Right (Just manifest)
                else do
                  reservations <- loadLocalWriterReservations root experimentHash snapshotId
                  pure $ do
                    active <- reservations
                    if null active
                      then
                        if null (manifestPhysicalObjectKeys manifest)
                          then Right Nothing
                          else
                            Left
                              ( "snapshot manifest has neither a commit nor an active reservation: "
                                  <> addressedManifestSha addressed
                              )
                      else do
                        traverse_
                          (validateReservationPhysicalGraph addressed snapshotId)
                          active
                        Right Nothing
 where
  manifest = addressedManifest addressed
  experimentHash = manifestExperiment manifest

loadLocalWriterReservations
  :: FilePath
  -> Text
  -> Text
  -> IO (Either Text [WriterReservation])
loadLocalWriterReservations root experimentHash snapshotId =
  let directoryKey =
        "jitml-checkpoints/"
          <> experimentHash
          <> "/snapshots/"
          <> snapshotId
          <> "/reservations"
   in case objectPathForKey root directoryKey of
        Left err -> pure (Left err)
        Right directory -> do
          exists <- doesDirectoryExist directory
          if not exists
            then pure (Right [])
            else do
              entries <- listDirectory directory
              decoded <-
                traverse
                  ( \entry -> do
                      bytes <- StrictByteString.readFile (directory </> entry)
                      pure $ do
                        reservation <- decodeWriterReservation bytes
                        let actualKey =
                              directoryKey <> "/" <> Text.pack entry
                        if actualKey == writerReservationObjectKey reservation
                          then Right reservation
                          else Left "local writer reservation address does not match payload"
                  )
                  (filter (\entry -> ".cbor" `Text.isSuffixOf` Text.pack entry) entries)
              pure (sequence decoded)

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
      commitsResult <- loadWriterCommits experimentHash
      reservationsResult <- loadActiveWriterReservations experimentHash
      case (commitsResult, reservationsResult) of
        (Left err, _) -> pure (Left err)
        (_, Left err) -> pure (Left err)
        (Right commits, Right reservations) -> do
          decoded <- traverse (readAndDecode commits reservations) refs
          pure (catMaybes <$> sequence decoded)
 where
  readAndDecode commits reservations ref = do
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
            case do
              expectedSha <-
                manifestShaFromObjectRef
                  (experimentHash <> "/manifests/")
                  ref
              mapLeft SETransient $
                validateAddressedManifest
                  experimentHash
                  expectedSha
                  (addressedManifestSha addressed)
                  (addressedManifest addressed) of
              Left err -> pure (Left err)
              Right manifest -> do
                pure
                  ( gcEligibleManifest
                      addressed
                      manifest
                      commits
                      reservations
                  )

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

  gcEligibleManifest addressed manifest commits reservations = do
    storageSnapshotId <-
      mapLeft SETransient (checkpointStorageSnapshotId manifest)
    case storageSnapshotId of
      Nothing
        | not (null (manifestPhysicalObjectKeys manifest)) ->
            Right Nothing
      _ -> do
        snapshotId <-
          mapLeft SETransient (requiredStorageSnapshotIdForAdmission manifest)
        let matchingCommits =
              filter ((== snapshotId) . writerCommitSnapshotId) commits
            matchingReservations =
              filter ((== snapshotId) . writerReservationSnapshotId) reservations
        case matchingCommits of
          _ : _ -> do
            _ <-
              mapLeft
                (SETransient . renderCheckpointAdmissionError)
                (requireMatchingSnapshotCommit addressed snapshotId commits)
            Right (Just manifest)
          [] ->
            case matchingReservations of
              [] ->
                if null (manifestPhysicalObjectKeys manifest)
                  then Right Nothing
                  else
                    Left
                      ( SETransient
                          ( "snapshot manifest has neither a commit nor an active reservation: "
                              <> addressedManifestSha addressed
                          )
                      )
              values -> do
                traverse_
                  (mapLeft SETransient . validateReservationPhysicalGraph addressed snapshotId)
                  values
                Right Nothing

-- | Resolve every mutable checkpoint selector from one fresh complete pointer
-- listing. Immutable browser-catalogue archival roots are validated by their
-- owning module and are deliberately excluded here. Unknown pointer shapes,
-- malformed bodies, or unresolved manifest addresses fail the GC pass closed.
loadCheckpointPointerGcRoots
  :: (HasMinIO m)
  => Text
  -> [CheckpointManifest]
  -> m (Either ServiceError [CheckpointManifest])
loadCheckpointPointerGcRoots experimentHash manifests = do
  let bucket = BucketName "jitml-checkpoints"
      prefix = experimentHash <> "/pointers/"
      manifestsBySha =
        Map.fromList
          [ (manifestContentSha manifest, manifest)
          | manifest <- canonicalManifestSet manifests
          ]
  listed <- listObjects bucket prefix
  case listed of
    Left err -> pure (Left err)
    Right refs -> do
      roots <- traverse (loadPointerRoot prefix manifestsBySha) refs
      pure
        ( Map.elems
            . Map.fromList
            . fmap (\manifest -> (manifestContentSha manifest, manifest))
            . catMaybes
            <$> sequence roots
        )
 where
  loadPointerRoot prefix manifestsBySha ref =
    case classifyPointerRef prefix ref of
      Left err -> pure (Left err)
      Right Nothing -> pure (Right Nothing)
      Right (Just ()) -> do
        payload <- minioReadBytes ref
        pure $ do
          bytes <- payload
          manifestSha <-
            mapLeft
              (SETransient . renderCheckpointAdmissionError)
              (parseCanonicalPointerBody bytes)
          case Map.lookup manifestSha manifestsBySha of
            Nothing ->
              Left
                ( SETransient
                    ( "checkpoint pointer does not resolve to an eligible committed manifest: "
                        <> unObjectKey (objectKey ref)
                        <> " -> "
                        <> manifestSha
                    )
                )
            Just manifest -> Right (Just manifest)

  classifyPointerRef prefix ref
    | objectBucket ref /= BucketName "jitml-checkpoints" =
        Left (SETransient "checkpoint pointer listing returned the wrong bucket")
    | otherwise =
        case Text.stripPrefix prefix (unObjectKey (objectKey ref)) of
          Nothing ->
            Left
              ( SETransient
                  ( "checkpoint pointer is outside the requested prefix: "
                      <> unObjectKey (objectKey ref)
                  )
              )
          Just suffix
            | "browser-catalogues/" `Text.isPrefixOf` suffix -> Right Nothing
            | otherwise ->
                case Text.splitOn "/" suffix of
                  ["latest"] -> Right (Just ())
                  ["best", metric] -> validateSegments [metric]
                  ["trial", trialId] -> validateSegments [trialId]
                  ["trial", trialId, "latest"] -> validateSegments [trialId]
                  ["trial", trialId, "best", metric] ->
                    validateSegments [trialId, metric]
                  _ ->
                    Left
                      ( SETransient
                          ( "checkpoint pointer has an unsupported control path: "
                              <> unObjectKey (objectKey ref)
                          )
                      )

  validateSegments segments =
    case traverse_ (validateGcPathSegment "checkpoint pointer segment") segments of
      Left err -> Left (SETransient err)
      Right () -> Right (Just ())

-- | Retention policy applied by `jitml internal gc <experiment-hash>` per
-- README → Retention and GC.
data RetentionPolicy
  = KeepAll
  | LastN Int
  deriving stock (Eq, Show)

-- | Expand each selected manifest to itself plus its immediate parent. The
-- result is in canonical SHA order and is independent of discovery order. The
-- caller decides which manifests are candidates and which are always-live
-- roots; this helper does not read selectors or traverse a transitive chain.
walkLiveSet :: [CheckpointManifest] -> [Text]
walkLiveSet manifests =
  Set.toAscList . Set.fromList $
    [ sha
    | manifest <- canonicalManifestSet manifests
    , sha <- manifestContentSha manifest : maybeToList (manifestParentManifestSha manifest)
    ]
 where
  maybeToList Nothing = []
  maybeToList (Just t) = [t]

-- | Apply `LastN k` retention to the candidate manifests by descending step.
-- Any independently admitted roots must be supplied as additional
-- always-live manifests.
applyRetentionPolicy
  :: RetentionPolicy
  -> [CheckpointManifest]
  -- ^ retention candidates
  -> [CheckpointManifest]
  -- ^ independently admitted always-live roots
  -> [Text]
  -- ^ manifest SHAs to keep
applyRetentionPolicy policy candidates alwaysLive =
  let canonicalCandidates = canonicalManifestSet candidates
      canonicalAlwaysLive = canonicalManifestSet alwaysLive
      alwaysLiveSet = walkLiveSet canonicalAlwaysLive
      kept =
        case policy of
          KeepAll -> canonicalCandidates
          LastN k ->
            take
              (max 0 k)
              ( sortOn
                  (\manifest -> (Down (manifestStep manifest), manifestContentSha manifest))
                  canonicalCandidates
              )
   in Set.toAscList (Set.fromList (alwaysLiveSet <> walkLiveSet kept))

data GcEvent = GcEvent
  { gcReapedManifestSha :: Text
  , gcReapedObjectKeys :: [Text]
  , gcExperimentHash :: Text
  , gcStepAtReap :: Word64
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Durable deletion intent. The event id binds the complete canonical
-- deletion set and is therefore stable across process and broker retries.
data GcIntent = GcIntent
  { gcIntentEvent :: GcEvent
  , gcIntentEventId :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | Publish-ready event. The substrate and completion timestamp are fixed
-- exactly once before this value is persisted, so a retry republishes the same
-- semantic event rather than manufacturing a conflicting payload.
data GcReadyEvent = GcReadyEvent
  { gcReadyEvent :: GcEvent
  , gcReadyEventId :: Text
  , gcReadySubstrate :: Text
  , gcReadyTimestampNs :: Word64
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data GcPlan = GcPlan
  { gcKeptManifestShas :: [Text]
  , gcReapEvents :: [GcEvent]
  , gcPlanValidationFailures :: [Text]
  , gcNoOp :: Bool
  }
  deriving stock (Eq, Show)

-- | Build the GC reconciler plan from the candidate manifests, always-live
-- roots, and the retention policy. After a successful reap, a second invocation
-- against the refreshed post-delete listing is a no-op per README →
-- Reconcilers.
buildGcPlan
  :: Text
  -- ^ experiment hash
  -> RetentionPolicy
  -> [CheckpointManifest]
  -- ^ all manifests under this experiment
  -> [CheckpointManifest]
  -- ^ independently admitted always-live roots
  -> GcPlan
buildGcPlan experimentHash policy allManifests alwaysLive =
  let canonicalManifests = canonicalManifestSet allManifests
      -- A completed canonical ProductRow can enter BrowserCatalogue
      -- publication immediately after this snapshot. Keeping it intrinsically
      -- closes that root-publication/GC TOCTOU; append-only catalogue roots
      -- remain the durable audit/index surface and protect registry drift.
      intrinsicProductRoots =
        [ manifest
        | manifest <- canonicalManifests
        , either (const False) (const True) (validateCheckpointCompletion manifest)
        , isJust (ProductMatrix.productRowForExperimentHash (manifestExperiment manifest))
        ]
      canonicalRoots = canonicalManifestSet (alwaysLive <> intrinsicProductRoots)
      kept = applyRetentionPolicy policy canonicalManifests canonicalRoots
      keptSet = Set.fromList kept
      physicalKeyResults =
        [ ( manifestContentSha manifest
          , canonicalManifestPhysicalObjectKeys experimentHash manifest
          )
        | manifest <- canonicalManifestSet (canonicalManifests <> canonicalRoots)
        ]
      validationFailures =
        Set.toAscList . Set.fromList $
          either (: []) (const []) (validateGcExperimentHash experimentHash)
            <> [ "GC manifest " <> manifestSha <> " is invalid: " <> reason
               | (manifestSha, Left reason) <- physicalKeyResults
               ]
      physicalKeysByManifest =
        Map.fromList
          [ (manifestSha, objectKeys)
          | (manifestSha, Right objectKeys) <- physicalKeyResults
          ]
      physicalKeysFor manifest =
        Map.findWithDefault [] (manifestContentSha manifest) physicalKeysByManifest
      keptObjectSet =
        Set.fromList
          [ objectKey
          | manifest <- canonicalManifestSet (canonicalManifests <> canonicalRoots)
          , manifestContentSha manifest `Set.member` keptSet
          , objectKey <- physicalKeysFor manifest
          ]
      reapTargets =
        [ manifest
        | manifest <- canonicalManifests
        , manifestContentSha manifest `Set.notMember` keptSet
        ]
      candidateEvents =
        [ GcEvent
            { gcReapedManifestSha = manifestContentSha manifest
            , gcReapedObjectKeys = objectKeys
            , gcExperimentHash = experimentHash
            , gcStepAtReap = manifestStep manifest
            }
        | (manifest, objectKeys) <-
            assignReapedObjects physicalKeysFor keptObjectSet Set.empty reapTargets
        ]
      -- A malformed declaration anywhere in the considered graph poisons the
      -- whole pass. In particular, a retained spelling such as
      -- @experiment/a/../blobs/x@ cannot be ignored while a reap target names
      -- the same physical object canonically. The validation failures are
      -- surfaced by 'persistGcPlanIntents'; exposing no event also makes every
      -- direct @gcPlanIntents@ execution path fail closed.
      events = if null validationFailures then candidateEvents else []
   in GcPlan
        { gcKeptManifestShas = kept
        , gcReapEvents = events
        , gcPlanValidationFailures = validationFailures
        , gcNoOp = null events && null validationFailures
        }
 where
  -- A physical object can be shared by multiple manifests. Delete it at most
  -- once, and never when any retained or always-live manifest still references
  -- it. Reap targets and object keys are both canonical, so shared-object
  -- attribution is independent of filesystem/S3 discovery order.
  assignReapedObjects _ _ _ [] = []
  assignReapedObjects physicalKeysFor keptObjectSet seenObjectSet (manifest : rest) =
    let manifestObjectKeys = physicalKeysFor manifest
        deletableObjectKeys =
          [ objectKey
          | objectKey <- manifestObjectKeys
          , objectKey `Set.notMember` keptObjectSet
          , objectKey `Set.notMember` seenObjectSet
          ]
        seenObjectSet' = foldr Set.insert seenObjectSet manifestObjectKeys
     in (manifest, deletableObjectKeys)
          : assignReapedObjects physicalKeysFor keptObjectSet seenObjectSet' rest

canonicalManifestSet :: [CheckpointManifest] -> [CheckpointManifest]
canonicalManifestSet manifests =
  Map.elems
    ( Map.fromList
        [ (manifestContentSha manifest, manifest)
        | manifest <- manifests
        ]
    )

canonicalManifestPhysicalObjectKeys
  :: Text
  -> CheckpointManifest
  -> Either Text [Text]
canonicalManifestPhysicalObjectKeys experimentHash manifest = do
  if manifestExperiment manifest == experimentHash
    then Right ()
    else
      Left
        ( "experiment mismatch: expected "
            <> experimentHash
            <> ", got "
            <> manifestExperiment manifest
        )
  storageSnapshotId <- checkpointStorageSnapshotId manifest
  case storageSnapshotId of
    Nothing
      | not (null (manifestPhysicalObjectKeys manifest)) ->
          Left "legacy unscoped manifest is not GC/retention eligible"
    _ -> Right ()
  let gcSnapshotId =
        case storageSnapshotId of
          Just snapshotId -> Just snapshotId
          Nothing
            | null (manifestPhysicalObjectKeys manifest) ->
                Just (deriveCheckpointStorageSnapshotId manifest [])
            | otherwise -> Nothing
  let rawKeys =
        manifestPhysicalObjectKeys manifest
          <> case gcSnapshotId of
            Just snapshotId ->
              [snapshotControlObjectKey experimentHash snapshotId "committed.cbor"]
            Nothing -> []
  canonicalKeys <- traverse (canonicalGcPhysicalObjectKey experimentHash) rawKeys
  Right (Set.toAscList (Set.fromList canonicalKeys))

-- | Stable semantic identity for one exact GC deletion set. Canonical CBOR
-- gives every field an unambiguous length boundary; substrate, completion
-- time, retry count, and broker receipt deliberately do not participate.
gcEventId :: GcEvent -> Text
gcEventId event =
  jmw1ContentSha
    ( serialise
        ( "jitml-gc-reaped-event-id-v1" :: Text
        , gcExperimentHash event
        , gcReapedManifestSha event
        , gcStepAtReap event
        , gcReapedObjectKeys event
        )
    )

gcPlanIntents :: GcPlan -> [GcIntent]
gcPlanIntents plan =
  if null (gcPlanValidationFailures plan)
    then
      [ GcIntent
          { gcIntentEventId = gcEventId event
          , gcIntentEvent = event
          }
      | event <- gcReapEvents plan
      ]
    else []

gcIntentObjectKey :: GcIntent -> Text
gcIntentObjectKey intent =
  "jitml-checkpoints/"
    <> gcExperimentHash (gcIntentEvent intent)
    <> "/gc/intents/"
    <> gcIntentEventId intent
    <> ".cbor"

gcCancelledObjectKey :: GcIntent -> Text
gcCancelledObjectKey intent =
  "jitml-checkpoints/"
    <> gcExperimentHash (gcIntentEvent intent)
    <> "/gc/cancelled/"
    <> gcIntentEventId intent
    <> ".cbor"

gcReadyObjectKey :: GcReadyEvent -> Text
gcReadyObjectKey ready =
  "jitml-checkpoints/"
    <> gcExperimentHash (gcReadyEvent ready)
    <> "/gc/ready/"
    <> gcReadyEventId ready
    <> ".cbor"

gcPublishedObjectKey :: GcReadyEvent -> Text
gcPublishedObjectKey ready =
  "jitml-checkpoints/"
    <> gcExperimentHash (gcReadyEvent ready)
    <> "/gc/published/"
    <> gcReadyEventId ready
    <> ".cbor"

data GcIntentEnvelope = GcIntentEnvelope
  { gcIntentWireVersion :: Word64
  , gcIntentEnvelopeValue :: GcIntent
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data GcReadyEnvelope = GcReadyEnvelope
  { gcReadyWireVersion :: Word64
  , gcReadyEnvelopeValue :: GcReadyEvent
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

gcOutboxWireVersion :: Word64
gcOutboxWireVersion = 1

encodeGcIntent :: GcIntent -> StrictByteString.ByteString
encodeGcIntent =
  LazyByteString.toStrict
    . serialise
    . GcIntentEnvelope gcOutboxWireVersion

encodeGcReadyEvent :: GcReadyEvent -> StrictByteString.ByteString
encodeGcReadyEvent =
  LazyByteString.toStrict
    . serialise
    . GcReadyEnvelope gcOutboxWireVersion

decodeGcIntent :: StrictByteString.ByteString -> Either Text GcIntent
decodeGcIntent bytes = do
  envelope <-
    mapLeft (Text.pack . show) (deserialiseOrFail (LazyByteString.fromStrict bytes))
  if gcIntentWireVersion envelope == gcOutboxWireVersion
    then Right ()
    else Left "unsupported GC intent wire version"
  let canonical = encodeGcIntent (gcIntentEnvelopeValue envelope)
  if canonical == bytes
    then validateGcIntent (gcIntentEnvelopeValue envelope)
    else Left "GC intent is not canonical CBOR"

decodeGcReadyEvent :: StrictByteString.ByteString -> Either Text GcReadyEvent
decodeGcReadyEvent bytes = do
  envelope <-
    mapLeft (Text.pack . show) (deserialiseOrFail (LazyByteString.fromStrict bytes))
  if gcReadyWireVersion envelope == gcOutboxWireVersion
    then Right ()
    else Left "unsupported GC ready-event wire version"
  let canonical = encodeGcReadyEvent (gcReadyEnvelopeValue envelope)
  if canonical == bytes
    then validateGcReadyEvent (gcReadyEnvelopeValue envelope)
    else Left "GC ready event is not canonical CBOR"

validateGcIntent :: GcIntent -> Either Text GcIntent
validateGcIntent intent = do
  validateGcEvent (gcIntentEvent intent)
  if gcIntentEventId intent == gcEventId (gcIntentEvent intent)
    then Right intent
    else Left "GC intent event id does not bind its canonical event"

validateGcReadyEvent :: GcReadyEvent -> Either Text GcReadyEvent
validateGcReadyEvent ready = do
  validateGcEvent (gcReadyEvent ready)
  if gcReadyEventId ready /= gcEventId (gcReadyEvent ready)
    then Left "GC ready event id does not bind its canonical event"
    else
      if gcReadySubstrate ready
        `notElem` ["linux-cpu", "linux-cuda", "apple-silicon"]
        then Left "GC ready event substrate is not canonical"
        else Right ready

validateGcEvent :: GcEvent -> Either Text ()
validateGcEvent event = do
  validateGcExperimentHash (gcExperimentHash event)
  case validateCanonicalManifestAddress (gcReapedManifestSha event) of
    Left err -> Left ("GC event manifest address is invalid: " <> Text.pack (show err))
    Right _ -> Right ()
  let objectKeys = gcReapedObjectKeys event
  if objectKeys == Set.toAscList (Set.fromList objectKeys)
    then Right ()
    else Left "GC event object keys are not canonical and unique"
  traverse_ (validateGcObjectKey (gcExperimentHash event)) objectKeys
  validateGcSnapshotKeySet (gcExperimentHash event) objectKeys

validateGcSnapshotKeySet :: Text -> [Text] -> Either Text ()
validateGcSnapshotKeySet experimentHash objectKeys = do
  classifications <- traverse classify objectKeys
  let snapshotIds = Set.fromList (catMaybes classifications)
      hasLegacy = Nothing `elem` classifications
      commitKeys = filter ("/committed.cbor" `Text.isSuffixOf`) objectKeys
  if Set.size snapshotIds > 1
    then Left "GC event mixes physical objects from multiple storage snapshots"
    else Right ()
  if hasLegacy && not (Set.null snapshotIds)
    then Left "GC event mixes legacy and snapshot-scoped physical objects"
    else Right ()
  if Set.null snapshotIds
    then Left "GC event must name one committed storage snapshot"
    else Right ()
  if length commitKeys > 1
    then Left "GC event contains more than one storage snapshot commit"
    else Right ()
  if not (Set.null snapshotIds) && length commitKeys /= 1
    then Left "GC event for a storage snapshot must contain its exact commit object"
    else Right ()
 where
  snapshotPrefix = "jitml-checkpoints/" <> experimentHash <> "/snapshots/"
  classify objectKey
    | snapshotPrefix `Text.isPrefixOf` objectKey =
        case Text.stripPrefix snapshotPrefix objectKey of
          Just remainder ->
            case Text.splitOn "/" remainder of
              snapshotId : _ -> Right (Just snapshotId)
              [] -> Left "GC event contains an empty storage snapshot path"
          Nothing -> Left "GC event contains an invalid storage snapshot path"
    | otherwise = Right Nothing

validateGcObjectKey :: Text -> Text -> Either Text ()
validateGcObjectKey experimentHash fullKey = do
  canonical <- canonicalGcPhysicalObjectKey experimentHash fullKey
  if fullKey == canonical
    then Right ()
    else
      Left
        ( "GC physical object key is not the canonical full bucket key: "
            <> fullKey
            <> "; expected "
            <> canonical
        )

-- | Normalize the one tolerated storage alias (a key with or without the
-- checkpoint bucket prefix) before graph identity comparisons. The result is
-- always a full bucket-qualified key suitable for a durable event. Path
-- traversal, ambiguous separators, control characters, reserved control
-- namespaces, and cross-experiment references are rejected rather than
-- normalized away.
canonicalGcPhysicalObjectKey :: Text -> Text -> Either Text Text
canonicalGcPhysicalObjectKey experimentHash rawKey = do
  validateGcExperimentHash experimentHash
  let bucketPrefix = "jitml-checkpoints/"
      relativeKey = fromMaybe rawKey (Text.stripPrefix bucketPrefix rawKey)
      segments = Text.splitOn "/" relativeKey
  traverse_ (validateGcPathSegment "physical object key") segments
  case segments of
    keyExperiment : firstObjectSegment : remainingObjectSegments
      | keyExperiment /= experimentHash ->
          Left
            ( "GC physical object is outside its experiment: "
                <> rawKey
            )
      | firstObjectSegment `elem` ["manifests", "pointers", "gc"] ->
          Left
            ( "GC physical object occupies a reserved control prefix: "
                <> rawKey
            )
      | firstObjectSegment == "snapshots" -> do
          case remainingObjectSegments of
            [snapshotId, "objects", originalKeySha] -> do
              validateCanonicalSha256 "storage snapshot id" snapshotId
              validateCanonicalSha256 "snapshot original-key SHA-256" originalKeySha
            [snapshotId, "committed.cbor"] ->
              validateCanonicalSha256 "storage snapshot id" snapshotId
            _ ->
              Left
                ( "GC physical object occupies an invalid snapshot path: "
                    <> rawKey
                )
          Right
            ( bucketPrefix
                <> Text.intercalate
                  "/"
                  (keyExperiment : firstObjectSegment : remainingObjectSegments)
            )
      | otherwise ->
          Right
            ( bucketPrefix
                <> Text.intercalate
                  "/"
                  (keyExperiment : firstObjectSegment : remainingObjectSegments)
            )
    [_] -> Left ("GC physical object has no object path: " <> rawKey)
    [] -> Left "GC physical object key is empty"

validateGcExperimentHash :: Text -> Either Text ()
validateGcExperimentHash = validateGcPathSegment "experiment hash"

validateGcPathSegment :: Text -> Text -> Either Text ()
validateGcPathSegment label segment
  | Text.null segment = Left (label <> " contains an empty path segment")
  | segment == "." = Left (label <> " contains a dot path segment")
  | segment == ".." = Left (label <> " contains a dot-dot path segment")
  | Text.any (\character -> character == '/' || character == '\\') segment =
      Left (label <> " contains a path separator")
  | Text.any isControl segment = Left (label <> " contains a control character")
  | otherwise = Right ()

-- | Load every durable writer commit for an experiment, validating canonical
-- bytes and the exact content-derived control-object address.
loadWriterCommits
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [WriterCommit])
loadWriterCommits experimentHash =
  loadWriterRecords
    experimentHash
    ("/committed.cbor" `Text.isSuffixOf`)
    decodeWriterCommit
    writerCommitObjectKey

-- | Load every present reservation as active. An exact retry allocates a fresh
-- per-attempt marker before repairing a previously committed snapshot, so a
-- matching commit cannot deactivate any extant marker. Only its owning
-- writer's successful cleanup releases that marker's GC fence.
loadActiveWriterReservations
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [WriterReservation])
loadActiveWriterReservations experimentHash = do
  markers <-
    loadWriterRecords
      experimentHash
      ( \objectKey ->
          "/reservations/" `Text.isInfixOf` objectKey
            && ".cbor" `Text.isSuffixOf` objectKey
      )
      decodeWriterReservation
      writerReservationObjectKey
  fenced <-
    updateExperimentGcFence experimentHash $ \fence ->
      Right
        ( ExperimentFenceUnchanged
            (experimentGcFenceReservations fence)
        )
  pure $ do
    markerValues <- markers
    fenceValues <- fenced
    let grouped =
          Map.elems
            ( Map.fromListWith
                (<>)
                [ (writerReservationObjectKey reservation, [reservation])
                | reservation <- markerValues <> fenceValues
                ]
            )
    traverse exactReservationForKey grouped
 where
  exactReservationForKey [] = Left (SETransient "empty writer reservation group")
  exactReservationForKey values@(first : _)
    | all (== first) values = Right first
    | otherwise = Left (SEConflict "marker and experiment fence bind different reservations")

loadWriterRecords
  :: (HasMinIO m, Ord value)
  => Text
  -> (Text -> Bool)
  -> (StrictByteString.ByteString -> Either Text value)
  -> (value -> Text)
  -> m (Either ServiceError [value])
loadWriterRecords experimentHash isRecordKey decodeRecord recordKey =
  case validateGcExperimentHash experimentHash of
    Left err -> pure (Left (SETransient err))
    Right () -> do
      let prefix = experimentHash <> "/snapshots/"
      listed <- listObjects (BucketName "jitml-checkpoints") prefix
      case listed of
        Left err -> pure (Left err)
        Right allRefs -> do
          let refs =
                sortOn
                  (unObjectKey . objectKey)
                  [ ref
                  | ref <- allRefs
                  , isRecordKey (unObjectKey (objectKey ref))
                  ]
          decoded <- traverse readRecord refs
          pure $ do
            values <- sequence decoded
            let canonical = Set.toAscList (Set.fromList values)
            if length canonical == length values
              then Right canonical
              else Left (SETransient ("duplicate writer records under " <> prefix))
 where
  readRecord ref = do
    bytes <- minioReadBytes ref
    pure $ do
      payload <- bytes
      value <-
        mapLeft
          (SETransient . ("invalid writer record: " <>))
          (decodeRecord payload)
      let expectedRef = checkpointObjectRef (recordKey value)
      if ref == expectedRef
        then Right value
        else
          Left
            ( SETransient
                ( "writer record address does not match its payload: expected "
                    <> Text.pack (show expectedRef)
                    <> ", got "
                    <> Text.pack (show ref)
                )
            )

loadGcIntents
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [GcIntent])
loadGcIntents experimentHash =
  case validateGcExperimentHash experimentHash of
    Left err -> pure (Left (SETransient err))
    Right () ->
      loadGcRecords
        (experimentHash <> "/gc/intents/")
        decodeGcIntent
        gcIntentObjectKey

loadGcCancelledIntents
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [GcIntent])
loadGcCancelledIntents experimentHash =
  case validateGcExperimentHash experimentHash of
    Left err -> pure (Left (SETransient err))
    Right () -> do
      tombstones <-
        loadGcRecords
          (experimentHash <> "/gc/cancelled/")
          decodeGcIntent
          gcCancelledObjectKey
      epochResult <- loadGcFenceEpoch experimentHash
      pure $ do
        values <- tombstones
        epoch <- epochResult
        let latest =
              latestGcFenceDecisions
                (experimentGcFenceDecisions (gcFenceEpochFence epoch))
        catMaybes <$> traverse (activeCancellation latest) values
 where
  activeCancellation latest intent =
    case [ decision
         | decision <- latest
         , gcIntentEventId (gcFenceDecisionIntent decision) == gcIntentEventId intent
         ] of
      -- A tombstone written before the experiment fence existed remains
      -- visible so the helper path can adopt it as generation zero.
      [] -> Right (Just intent)
      [decision]
        | gcFenceDecisionIntent decision /= intent ->
            Left (SEConflict "cancellation tombstone binds different fence intent bytes")
        | gcFenceDecisionPhase decision `elem` [GcFenceCancelling, GcFenceCancelled] ->
            Right (Just intent)
        | otherwise -> Right Nothing
      _ -> Left (SETransient "duplicate latest decisions for cancellation tombstone")

loadGcReadyEvents
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [GcReadyEvent])
loadGcReadyEvents experimentHash =
  case validateGcExperimentHash experimentHash of
    Left err -> pure (Left (SETransient err))
    Right () ->
      loadGcRecords
        (experimentHash <> "/gc/ready/")
        decodeGcReadyEvent
        gcReadyObjectKey

loadGcPublishedEvents
  :: (HasMinIO m)
  => Text
  -> m (Either ServiceError [GcReadyEvent])
loadGcPublishedEvents experimentHash =
  case validateGcExperimentHash experimentHash of
    Left err -> pure (Left (SETransient err))
    Right () ->
      loadGcRecords
        (experimentHash <> "/gc/published/")
        decodeGcReadyEvent
        gcPublishedObjectKey

loadGcRecords
  :: (HasMinIO m, Ord value)
  => Text
  -> (StrictByteString.ByteString -> Either Text value)
  -> (value -> Text)
  -> m (Either ServiceError [value])
loadGcRecords prefix decodeRecord recordKey = do
  listed <- listObjects (BucketName "jitml-checkpoints") prefix
  case listed of
    Left err -> pure (Left err)
    Right refs -> do
      decoded <- traverse readRecord (sortOn (unObjectKey . objectKey) refs)
      pure $ do
        values <- sequence decoded
        let canonical = Set.toAscList (Set.fromList values)
        if length canonical /= length values
          then Left (SETransient ("duplicate GC records under " <> prefix))
          else Right canonical
 where
  readRecord ref = do
    bytes <- minioReadBytes ref
    pure $ do
      payload <- bytes
      value <- mapLeft (SETransient . ("invalid GC record: " <>)) (decodeRecord payload)
      let expectedRef = checkpointObjectRef (recordKey value)
      if ref == expectedRef
        then Right value
        else
          Left
            ( SETransient
                ( "GC record address does not match its payload: expected "
                    <> Text.pack (show expectedRef)
                    <> ", got "
                    <> Text.pack (show ref)
                )
            )

persistGcPlanIntents
  :: (HasMinIO m)
  => GcPlan
  -> m (Either [(Text, ServiceError)] [GcIntent])
persistGcPlanIntents plan =
  case gcPlanValidationFailures plan of
    [] -> persistGcIntents (gcPlanIntents plan)
    failures ->
      pure
        ( Left
            [ ("gc plan validation", SETransient reason)
            | reason <- failures
            ]
        )

persistGcIntents
  :: (HasMinIO m)
  => [GcIntent]
  -> m (Either [(Text, ServiceError)] [GcIntent])
persistGcIntents intents =
  case validateGcIntentBatch intents of
    Left failures -> pure (Left failures)
    Right validated -> do
      outcomes <-
        traverse
          ( \intent -> do
              outcome <-
                putObjectBytesIfAbsentOrSame
                  (checkpointObjectRef (gcIntentObjectKey intent))
                  (encodeGcIntent intent)
              pure (intent, outcome)
          )
          validated
      let failures =
            [ (gcIntentObjectKey intent, err)
            | (intent, Left err) <- outcomes
            ]
      pure $
        if null failures
          then Right validated
          else Left failures

-- | Cancel complete stale intents.  The experiment CAS decision is installed
-- first, followed by the immutable cancellation outbox record.  Both the
-- semantic intent and cancellation artifact remain stable across generations:
-- the latest fence phase decides which one is logically active.  Consequently
-- a delayed duplicate helper can only repeat an idempotent PUT; it can neither
-- delete a re-armed intent nor recreate an active old-generation tombstone.
cancelGcIntents
  :: (HasMinIO m)
  => [GcIntent]
  -> m (Either [(Text, ServiceError)] [GcIntent])
cancelGcIntents intents =
  case validateGcIntentBatch intents of
    Left failures -> pure (Left failures)
    Right validated -> do
      fenced <-
        traverse
          (\intent -> fmap (pairWithIntent intent) (installGcCancellationInFence intent))
          validated
      let fenceFailures =
            [ (experimentGcFenceObjectKey (gcExperimentHash (gcIntentEvent intent)), err)
            | (intent, Left err) <- fenced
            ]
      if not (null fenceFailures)
        then pure (Left fenceFailures)
        else do
          let cancellationWork =
                [ (intent, decision)
                | (intent, Right (Just decision)) <- fenced
                ]
          persisted <-
            traverse
              ( \(intent, owned) -> do
                  written <-
                    putObjectBytesIfAbsentOrSame
                      (checkpointObjectRef (gcCancelledObjectKey intent))
                      (encodeGcIntent intent)
                  pure (intent, owned, written)
              )
              cancellationWork
          let persistFailures =
                [ (gcCancelledObjectKey intent, err)
                | (intent, _, Left err) <- persisted
                ]
          if not (null persistFailures)
            then pure (Left persistFailures)
            else do
              completed <-
                traverse
                  ( \(intent, owned) -> do
                      outcome <- completeGcCancellationInFence owned
                      pure (intent, outcome)
                  )
                  cancellationWork
              let completionFailures =
                    [ (experimentGcFenceObjectKey (gcExperimentHash (gcIntentEvent intent)), err)
                    | (intent, Left err) <- completed
                    ]
              pure $
                if null completionFailures
                  then Right (fmap fst cancellationWork)
                  else Left completionFailures
 where
  pairWithIntent intent decision = (intent, decision)

-- | Exact ownership of one durably installed Cancelling generation.  This
-- constructor never leaves this module, so recovery cannot accidentally turn
-- a stable, generation-agnostic tombstone into authority over a later re-arm.
newtype OwnedGcCancellation = OwnedGcCancellation
  { ownedGcCancellationDecision :: GcFenceDecision
  }

-- | Recover only the exact generations already durably in Cancelling.  A
-- tombstone from an older completed generation is never allowed to cancel a
-- newly Planned or Executing re-arm.  The pre-fence migration case is the only
-- exception: absence may atomically install generation zero (or cancel a
-- concurrently-created generation-zero Planned decision), after which the
-- helper carries that exact decision through persistence and completion.
helpGcCancellations
  :: (HasMinIO m)
  => [GcIntent]
  -> m (Either [(Text, ServiceError)] [GcIntent])
helpGcCancellations rawIntents =
  case validateGcIntentBatch rawIntents of
    Left failures -> pure (Left failures)
    Right intents -> do
      claimed <- traverse claimGcCancellationForHelp intents
      let failures =
            [ (experimentGcFenceObjectKey (gcExperimentHash (gcIntentEvent intent)), err)
            | (intent, Left err) <- zip intents claimed
            ]
          cancellationWork =
            [ (intent, owned)
            | (intent, Right (Just owned)) <- zip intents claimed
            ]
      if not (null failures)
        then pure (Left failures)
        else do
          persisted <-
            traverse
              ( \(intent, owned) -> do
                  written <-
                    putObjectBytesIfAbsentOrSame
                      (checkpointObjectRef (gcCancelledObjectKey intent))
                      (encodeGcIntent intent)
                  pure (intent, owned, written)
              )
              cancellationWork
          let persistFailures =
                [ (gcCancelledObjectKey intent, err)
                | (intent, _, Left err) <- persisted
                ]
          if not (null persistFailures)
            then pure (Left persistFailures)
            else do
              completed <-
                traverse
                  ( \(intent, owned) -> do
                      outcome <- completeGcCancellationInFence owned
                      pure (intent, outcome)
                  )
                  cancellationWork
              let completionFailures =
                    [ (experimentGcFenceObjectKey (gcExperimentHash (gcIntentEvent intent)), err)
                    | (intent, Left err) <- completed
                    ]
              pure $
                if null completionFailures
                  then Right (fmap fst cancellationWork)
                  else Left completionFailures

claimGcCancellationForHelp
  :: (HasMinIO m)
  => GcIntent
  -> m (Either ServiceError (Maybe OwnedGcCancellation))
claimGcCancellationForHelp intent =
  updateExperimentGcFence experimentHash $ \fence -> do
    let histories = groupDecisionsByEvent (experimentGcFenceDecisions fence)
        matchingHistory =
          [ history
          | history@(decision : _) <- histories
          , gcIntentEventId (gcFenceDecisionIntent decision) == gcIntentEventId intent
          ]
    case matchingHistory of
      [] ->
        let cancelling = gcFenceDecision 0 GcFenceCancelling intent
         in Right
              ( ExperimentFenceChanged
                  fence
                    { experimentGcFenceDecisions =
                        cancelling : experimentGcFenceDecisions fence
                    }
                  (Just (OwnedGcCancellation cancelling))
              )
      [history] -> do
        let latest = last history
        if gcFenceDecisionIntent latest == intent
          then Right ()
          else Left (SEConflict "cancellation tombstone binds different fence intent bytes")
        case gcFenceDecisionPhase latest of
          GcFenceCancelling ->
            Right
              ( ExperimentFenceUnchanged
                  (Just (OwnedGcCancellation latest))
              )
          GcFencePlanned
            | gcFenceDecisionGeneration latest == 0 ->
                let cancelling = latest {gcFenceDecisionPhase = GcFenceCancelling}
                 in Right
                      ( ExperimentFenceChanged
                          (replaceGcFenceDecision latest cancelling fence)
                          (Just (OwnedGcCancellation cancelling))
                      )
          _ -> Right (ExperimentFenceUnchanged Nothing)
      _ -> Left (SETransient "duplicate GC decision histories for cancellation tombstone")
 where
  experimentHash = gcExperimentHash (gcIntentEvent intent)

installGcCancellationInFence
  :: (HasMinIO m)
  => GcIntent
  -> m (Either ServiceError (Maybe OwnedGcCancellation))
installGcCancellationInFence intent =
  updateExperimentGcFence experimentHash $ \fence -> do
    let histories = groupDecisionsByEvent (experimentGcFenceDecisions fence)
        matchingHistory =
          [ history
          | history@(decision : _) <- histories
          , gcIntentEventId (gcFenceDecisionIntent decision) == gcIntentEventId intent
          ]
        otherLatest =
          [ decision
          | decision <- latestGcFenceDecisions (experimentGcFenceDecisions fence)
          , gcIntentEventId (gcFenceDecisionIntent decision) /= gcIntentEventId intent
          ]
    if any
      ( \decision ->
          gcFenceDecisionPhase decision `elem` [GcFenceExecuting, GcFenceReaped]
            && gcEventsOverlap
              (gcIntentEvent (gcFenceDecisionIntent decision))
              (gcIntentEvent intent)
      )
      otherLatest
      then Left (SEConflict "GC cancellation overlaps another executing or reaped decision")
      else Right ()
    case matchingHistory of
      [] ->
        let decision = gcFenceDecision 0 GcFenceCancelling intent
         in Right
              ( ExperimentFenceChanged
                  fence
                    { experimentGcFenceDecisions =
                        decision : experimentGcFenceDecisions fence
                    }
                  (Just (OwnedGcCancellation decision))
              )
      [history] ->
        let latest = last history
         in if gcFenceDecisionIntent latest /= intent
              then Left (SEConflict "GC cancellation event id binds different intent bytes")
              else case gcFenceDecisionPhase latest of
                GcFenceCancelled -> Right (ExperimentFenceUnchanged Nothing)
                GcFenceCancelling ->
                  Right
                    ( ExperimentFenceUnchanged
                        (Just (OwnedGcCancellation latest))
                    )
                GcFencePlanned ->
                  let cancelling = latest {gcFenceDecisionPhase = GcFenceCancelling}
                      decisions =
                        fmap
                          ( \decision -> if gcFenceDecisionKey decision == gcFenceDecisionKey latest then cancelling else decision
                          )
                          (experimentGcFenceDecisions fence)
                   in Right
                        ( ExperimentFenceChanged
                            fence {experimentGcFenceDecisions = decisions}
                            (Just (OwnedGcCancellation cancelling))
                        )
                GcFenceExecuting ->
                  Left (SEConflict "cannot cancel an executing GC generation")
                GcFenceReaped ->
                  Left (SEConflict "cannot cancel a reaped GC generation")
      _ -> Left (SETransient "duplicate GC decision histories for one event id")
 where
  experimentHash = gcExperimentHash (gcIntentEvent intent)

completeGcCancellationInFence
  :: (HasMinIO m)
  => OwnedGcCancellation
  -> m (Either ServiceError ())
completeGcCancellationInFence owned =
  updateExperimentGcFence experimentHash $ \fence -> do
    let eventId = gcIntentEventId (gcFenceDecisionIntent ownedDecision)
        matching =
          [ decision
          | decision <- latestGcFenceDecisions (experimentGcFenceDecisions fence)
          , gcIntentEventId (gcFenceDecisionIntent decision) == eventId
          ]
    case matching of
      [latest]
        | gcFenceDecisionIntent latest /= gcFenceDecisionIntent ownedDecision ->
            Left (SEConflict "GC cancellation completion binds different intent bytes")
        | gcFenceDecisionGeneration latest < gcFenceDecisionGeneration ownedDecision ->
            Left (SEConflict "GC cancellation completion generation is ahead of the fence")
        | gcFenceDecisionGeneration latest > gcFenceDecisionGeneration ownedDecision ->
            -- Another helper completed this generation before a later fresh
            -- re-arm. The semantic intent and cancellation artifact are
            -- immutable and retained, so this delayed helper has no
            -- generation-sensitive side effect left to perform.
            Right (ExperimentFenceUnchanged ())
        | gcFenceDecisionOperationId latest /= gcFenceDecisionOperationId ownedDecision ->
            Left (SEConflict "GC cancellation completion operation id is forged")
        | gcFenceDecisionPhase latest == GcFenceCancelled ->
            Right (ExperimentFenceUnchanged ())
        | gcFenceDecisionPhase latest == GcFenceCancelling ->
            let completed = latest {gcFenceDecisionPhase = GcFenceCancelled}
             in Right
                  ( ExperimentFenceChanged
                      (replaceGcFenceDecision latest completed fence)
                      ()
                  )
        | otherwise ->
            Left (SEConflict "GC cancellation completion does not own a cancelling phase")
      [] -> Left (SEConflict "GC cancellation decision disappeared from the fence")
      _ -> Left (SETransient "duplicate latest GC cancellation decisions")
 where
  ownedDecision = ownedGcCancellationDecision owned
  experimentHash = gcExperimentHash (gcIntentEvent (gcFenceDecisionIntent ownedDecision))

gcFenceDecision :: Word64 -> GcFenceDecisionPhase -> GcIntent -> GcFenceDecision
gcFenceDecision generation phase intent =
  GcFenceDecision
    { gcFenceDecisionGeneration = generation
    , gcFenceDecisionIntent = intent
    , gcFenceDecisionOperationId = gcFenceOperationId generation intent
    , gcFenceDecisionPhase = phase
    }

validateGcIntentBatch
  :: [GcIntent]
  -> Either [(Text, ServiceError)] [GcIntent]
validateGcIntentBatch rawIntents =
  let canonicalIntents = Set.toAscList (Set.fromList rawIntents)
      validations =
        [ (index, validateGcIntent intent)
        | (index, intent) <- zip [(0 :: Int) ..] canonicalIntents
        ]
      failures =
        [ ( "gc intent validation[" <> Text.pack (show index) <> "]"
          , SETransient reason
          )
        | (index, Left reason) <- validations
        ]
   in if null failures
        then Right canonicalIntents
        else Left failures

-- | Re-prove durable intents against one freshly listed retention/root view.
-- The result never trims an intent: it either returns the original exact
-- record as executable or returns that whole record for durable cancellation.
-- A target whose manifest was already removed by an earlier partial execution
-- may continue only when the latest experiment-fence history already records
-- this byte-identical generation as Executing or Reaped and no current
-- manifest, root, writer marker, or terminal outbox event protects it. Mere
-- manifest absence is never authority to mint a new destructive operation.
revalidateGcIntents
  :: GcFenceEpoch
  -> GcFenceEpoch
  -> GcPlan
  -> [CheckpointManifest]
  -> [CheckpointManifest]
  -> [WriterReservation]
  -> [GcEvent]
  -> [GcIntent]
  -> Either [Text] ([RevalidatedGcIntent], [GcIntent])
revalidateGcIntents beforeEpoch afterEpoch freshPlan currentManifests alwaysLive reservations terminalEvents rawIntents = do
  if beforeEpoch == afterEpoch
    then Right ()
    else Left ["experiment GC fence changed during the complete fresh root view"]
  let experimentHash =
        experimentGcFenceExperimentHash
          (gcFenceEpochFence beforeEpoch)
      effectiveReservations =
        Set.toAscList
          ( Set.fromList
              ( reservations
                  <> experimentGcFenceReservations (gcFenceEpochFence afterEpoch)
              )
          )
  if null (gcPlanValidationFailures freshPlan)
    then Right ()
    else
      Left
        ["fresh GC plan is invalid: " <> reason | reason <- gcPlanValidationFailures freshPlan]
  intents <-
    case validateGcIntentBatch rawIntents of
      Left failures -> Left [key <> ": " <> Text.pack (show err) | (key, err) <- failures]
      Right values -> Right values
  if all
    ((== experimentHash) . gcExperimentHash . gcIntentEvent)
    intents
    && all ((== experimentHash) . manifestExperiment) (currentManifests <> alwaysLive)
    && all ((== experimentHash) . writerReservationExperimentHash) effectiveReservations
    && all ((== experimentHash) . gcExperimentHash) terminalEvents
    then Right ()
    else Left ["fresh GC view crosses its experiment fence epoch"]
  mapLeft (: []) (traverse_ validateGcEvent terminalEvents)
  protectedManifestEvents <-
    mapLeft (: []) $
      traverse
        ( \manifest -> do
            keys <-
              canonicalManifestPhysicalObjectKeys
                (manifestExperiment manifest)
                manifest
            Right (manifest, Set.fromList keys)
        )
        (canonicalManifestSet (currentManifests <> alwaysLive))
  let freshById =
        Map.fromList
          [ (gcIntentEventId intent, intent)
          | intent <- gcPlanIntents freshPlan
          ]
      currentShas =
        Set.fromList (fmap manifestContentSha currentManifests)
      latestFenceById =
        Map.fromList
          [ (gcIntentEventId (gcFenceDecisionIntent decision), decision)
          | decision <-
              latestGcFenceDecisions
                ( experimentGcFenceDecisions
                    (gcFenceEpochFence afterEpoch)
                )
          ]
      (executable, cancelled) =
        foldr
          ( classifyIntent
              freshById
              currentShas
              latestFenceById
              protectedManifestEvents
              effectiveReservations
          )
          ([], [])
          intents
  Right
    ( fmap
        (`RevalidatedGcIntent` beforeEpoch)
        executable
    , cancelled
    )
 where
  classifyIntent freshById currentShas latestFenceById protectedManifests effectiveReservations intent (executable, cancelled)
    | protectedByReservation intent = (executable, intent : cancelled)
    | protectedByTerminal intent = (executable, intent : cancelled)
    | targetPresent =
        case Map.lookup (gcIntentEventId intent) freshById of
          Just current
            | current == intent
            , not (protectedByOtherManifest intent) ->
                (intent : executable, cancelled)
          _ -> (executable, intent : cancelled)
    | protectedByOtherManifest intent = (executable, intent : cancelled)
    | hasExactRecoveryHistory = (intent : executable, cancelled)
    | otherwise = (executable, intent : cancelled)
   where
    event = gcIntentEvent intent
    targetPresent = gcReapedManifestSha event `Set.member` currentShas
    hasExactRecoveryHistory =
      case Map.lookup (gcIntentEventId intent) latestFenceById of
        Just decision ->
          gcFenceDecisionIntent decision == intent
            && gcFenceDecisionPhase decision
              `elem` [GcFenceExecuting, GcFenceReaped]
        Nothing -> False

    protectedByReservation candidate =
      any
        (\reservation -> writerReservationOverlapsGcEvent reservation (gcIntentEvent candidate))
        effectiveReservations

    protectedByTerminal candidate =
      any (gcEventsOverlap (gcIntentEvent candidate)) terminalEvents

    protectedByOtherManifest candidate =
      any
        (manifestProtectsIntent (gcIntentEvent candidate))
        [ pair
        | pair@(manifest, _) <- protectedManifests
        , manifestContentSha manifest /= gcReapedManifestSha (gcIntentEvent candidate)
        ]

  manifestProtectsIntent event (manifest, physicalKeys) =
    manifestParentManifestSha manifest == Just (gcReapedManifestSha event)
      || not
        ( Set.null
            ( Set.intersection
                physicalKeys
                (Set.fromList (gcReapedObjectKeys event))
            )
        )

data GcAuthorizationAdvance
  = GcAuthorizationContinue
  | GcAuthorizationCancelled
  | GcAuthorizationGranted AuthorizedGcIntent

-- | Linearize each freshly revalidated intent against the experiment-wide
-- writer/GC fence. Absence of a history is Open. The only destructive path is
-- Open -> Planned -> Executing; Planned can instead become Cancelled, and a
-- freshly revalidated byte-identical cancellation re-arms at generation n+1.
-- Every first Planned transition must still observe the witness's monotonic
-- writer/root epoch. Once Planned is durable, any later overlapping writer
-- atomically converts that exact operation to Cancelling.
authorizeRevalidatedGcIntents
  :: (HasMinIO m)
  => [RevalidatedGcIntent]
  -> m GcAuthorizationResult
authorizeRevalidatedGcIntents revalidated = do
  outcomes <- traverse authorizeOne canonical
  pure
    GcAuthorizationResult
      { gcAuthorizedIntents =
          Set.toAscList
            (Set.fromList [authorized | Right (Right authorized) <- outcomes])
      , gcAuthorizationCancelledIntents =
          Set.toAscList
            ( Set.fromList
                [ revalidatedGcIntent witness
                | (witness, Right (Left ())) <- zip canonical outcomes
                ]
            )
      , gcAuthorizationFailures =
          canonicalizationFailures
            <> [ (experimentGcFenceObjectKey experimentHash, err)
               | (witness, Left err) <- zip canonical outcomes
               , let experimentHash = gcExperimentHash (gcIntentEvent (revalidatedGcIntent witness))
               ]
      }
 where
  grouped =
    Map.elems
      ( Map.fromListWith
          (<>)
          [ (revalidatedGcIntent witness, [witness])
          | witness <- revalidated
          ]
      )
  classified = fmap classifyWitnessGroup grouped
  canonical = sortOn revalidatedGcIntent (rights classified)
  canonicalizationFailures = lefts classified

  classifyWitnessGroup [] =
    Left
      ( "gc revalidation witness"
      , SETransient "empty GC revalidation witness group"
      )
  classifyWitnessGroup (witness : duplicates)
    | all
        ((== revalidatedGcFenceEpoch witness) . revalidatedGcFenceEpoch)
        duplicates =
        Right witness
    | otherwise =
        Left
          ( experimentGcFenceObjectKey
              (gcExperimentHash (gcIntentEvent (revalidatedGcIntent witness)))
          , SEConflict "duplicate GC witnesses bind different writer/root epochs"
          )

  authorizeOne witness = do
    let intent = revalidatedGcIntent witness
        ref = checkpointObjectRef (gcIntentObjectKey intent)
    durable <- minioReadBytes ref
    case durable of
      Left err -> pure (Left err)
      Right bytes ->
        case decodeGcIntent bytes of
          Left reason -> pure (Left (SETransient ("invalid durable GC intent: " <> reason)))
          Right observed
            | observed /= intent ->
                pure (Left (SEConflict "durable GC intent bytes differ from fresh witness"))
            | otherwise -> do
                activeReservations <-
                  loadActiveWriterReservations
                    (gcExperimentHash (gcIntentEvent intent))
                case activeReservations of
                  Left err -> pure (Left err)
                  Right reservations ->
                    advanceAuthorization reservations (0 :: Int) witness

  advanceAuthorization activeReservations attempt witness
    | attempt >= 4096 =
        pure (Left (SETransient "GC authorization did not converge"))
    | otherwise = do
        let intent = revalidatedGcIntent witness
        advanced <-
          updateExperimentGcFence
            (gcExperimentHash (gcIntentEvent intent))
            (advanceGcAuthorization (revalidatedGcFenceEpoch witness) activeReservations intent)
        case advanced of
          Left err -> pure (Left err)
          Right GcAuthorizationContinue ->
            advanceAuthorization activeReservations (attempt + 1) witness
          Right GcAuthorizationCancelled -> pure (Right (Left ()))
          Right (GcAuthorizationGranted authorized) ->
            pure (Right (Right authorized))

advanceGcAuthorization
  :: GcFenceEpoch
  -> [WriterReservation]
  -> GcIntent
  -> ExperimentGcFence
  -> Either ServiceError (ExperimentFenceMutation GcAuthorizationAdvance)
advanceGcAuthorization witnessEpoch observedReservations intent fence = do
  let histories = groupDecisionsByEvent (experimentGcFenceDecisions fence)
      eventId = gcIntentEventId intent
      matchingHistory =
        [ history
        | history@(decision : _) <- histories
        , gcIntentEventId (gcFenceDecisionIntent decision) == eventId
        ]
      latestOthers =
        [ decision
        | decision <- latestGcFenceDecisions (experimentGcFenceDecisions fence)
        , gcIntentEventId (gcFenceDecisionIntent decision) /= eventId
        ]
      blockers =
        filter
          (\reservation -> writerReservationOverlapsGcEvent reservation (gcIntentEvent intent))
          ( Set.toAscList
              ( Set.fromList
                  (observedReservations <> experimentGcFenceReservations fence)
              )
          )
      destructiveOverlap decision =
        gcFenceDecisionPhase decision `elem` [GcFencePlanned, GcFenceExecuting, GcFenceReaped]
          && gcEventsOverlap
            (gcIntentEvent (gcFenceDecisionIntent decision))
            (gcIntentEvent intent)
  if any destructiveOverlap latestOthers
    then Left (SEConflict "GC authorization overlaps another planned/executing/reaped decision")
    else Right ()
  case matchingHistory of
    [] ->
      let phase = if null blockers then GcFencePlanned else GcFenceCancelling
          decision = gcFenceDecision 0 phase intent
          updated =
            fence
              { experimentGcFenceDecisions =
                  decision : experimentGcFenceDecisions fence
              }
          outcome =
            if phase == GcFencePlanned
              then GcAuthorizationContinue
              else GcAuthorizationCancelled
       in if phase == GcFencePlanned
            then do
              requireCurrentWriterEpoch witnessEpoch fence
              Right (ExperimentFenceChanged updated outcome)
            else Right (ExperimentFenceChanged updated outcome)
    [history] -> do
      let latest = last history
      if gcFenceDecisionIntent latest == intent
        then Right ()
        else Left (SEConflict "GC fence event id binds different intent bytes")
      case gcFenceDecisionPhase latest of
        GcFenceCancelled
          | null blockers ->
              do
                requireCurrentWriterEpoch witnessEpoch fence
                if gcFenceDecisionGeneration latest == maxBound
                  then Left (SETransient "GC fence generation overflow")
                  else
                    let generation = gcFenceDecisionGeneration latest + 1
                        planned = gcFenceDecision generation GcFencePlanned intent
                     in Right
                          ( ExperimentFenceChanged
                              fence
                                { experimentGcFenceDecisions =
                                    planned : experimentGcFenceDecisions fence
                                }
                              GcAuthorizationContinue
                          )
          | otherwise -> Right (ExperimentFenceUnchanged GcAuthorizationCancelled)
        GcFenceCancelling ->
          Right (ExperimentFenceUnchanged GcAuthorizationCancelled)
        GcFencePlanned
          | null blockers ->
              let executing = latest {gcFenceDecisionPhase = GcFenceExecuting}
               in Right
                    ( ExperimentFenceChanged
                        (replaceGcFenceDecision latest executing fence)
                        (GcAuthorizationGranted (authorizedFromDecision executing))
                    )
          | otherwise ->
              let cancelled = latest {gcFenceDecisionPhase = GcFenceCancelling}
               in Right
                    ( ExperimentFenceChanged
                        (replaceGcFenceDecision latest cancelled fence)
                        GcAuthorizationCancelled
                    )
        GcFenceExecuting
          | null blockers ->
              Right
                ( ExperimentFenceUnchanged
                    (GcAuthorizationGranted (authorizedFromDecision latest))
                )
          | otherwise ->
              Left (SETransient "executing GC decision contains an impossible writer overlap")
        GcFenceReaped
          | null blockers ->
              Right
                ( ExperimentFenceUnchanged
                    (GcAuthorizationGranted (authorizedFromDecision latest))
                )
          | otherwise ->
              Left (SETransient "reaped GC decision contains an impossible writer overlap")
    _ -> Left (SETransient "duplicate GC decision histories for one event id")

requireCurrentWriterEpoch
  :: GcFenceEpoch
  -> ExperimentGcFence
  -> Either ServiceError ()
requireCurrentWriterEpoch witnessEpoch fence =
  let observed = gcFenceEpochFence witnessEpoch
   in if experimentGcFenceExperimentHash observed
        == experimentGcFenceExperimentHash fence
        && experimentGcFenceWriterEpoch observed
          == experimentGcFenceWriterEpoch fence
        then Right ()
        else
          Left
            ( SEConflict
                "GC writer/root epoch changed after fresh revalidation; rebuild the complete view"
            )

replaceGcFenceDecision
  :: GcFenceDecision
  -> GcFenceDecision
  -> ExperimentGcFence
  -> ExperimentGcFence
replaceGcFenceDecision before after fence =
  fence
    { experimentGcFenceDecisions =
        fmap
          (\decision -> if gcFenceDecisionKey decision == gcFenceDecisionKey before then after else decision)
          (experimentGcFenceDecisions fence)
    }

authorizedFromDecision :: GcFenceDecision -> AuthorizedGcIntent
authorizedFromDecision decision =
  AuthorizedGcIntent
    { authorizedGcIntentValue = gcFenceDecisionIntent decision
    , authorizedGcGeneration = gcFenceDecisionGeneration decision
    , authorizedGcOperationId = gcFenceDecisionOperationId decision
    }

data GcDeleteOutcome
  = GcDeleteAcknowledged
  | GcDeleteFailed ServiceError
  | GcDeleteDeferred
  deriving stock (Eq, Show)

data GcEventExecution = GcEventExecution
  { gcExecutionIntent :: GcIntent
  , gcManifestDeleteOutcome :: GcDeleteOutcome
  , gcObjectDeleteOutcomes :: [(Text, GcDeleteOutcome)]
  }
  deriving stock (Eq, Show)

data GcExecutionResult = GcExecutionResult
  { gcEventExecutions :: [GcEventExecution]
  , gcExecutionPreparationFailures :: [(Text, ServiceError)]
  }
  deriving stock (Eq, Show)

gcCompletedExecutions :: GcExecutionResult -> [GcEventExecution]
gcCompletedExecutions result =
  [ execution
  | execution <- gcEventExecutions result
  , gcManifestDeleteOutcome execution == GcDeleteAcknowledged
  , all ((== GcDeleteAcknowledged) . snd) (gcObjectDeleteOutcomes execution)
  ]

gcExecutionFailures :: GcExecutionResult -> [(Text, ServiceError)]
gcExecutionFailures result =
  gcExecutionPreparationFailures result
    <> concatMap executionFailures (gcEventExecutions result)
 where
  executionFailures execution =
    manifestFailure <> objectFailures
   where
    event = gcIntentEvent (gcExecutionIntent execution)
    manifestFailure =
      case gcManifestDeleteOutcome execution of
        GcDeleteFailed err ->
          [(manifestKey (gcExperimentHash event) (gcReapedManifestSha event), err)]
        _ -> []
    objectFailures =
      [ (key, err)
      | (key, GcDeleteFailed err) <- gcObjectDeleteOutcomes execution
      ]

deferredGcExecution :: GcIntent -> GcEventExecution
deferredGcExecution intent =
  GcEventExecution
    { gcExecutionIntent = intent
    , gcManifestDeleteOutcome = GcDeleteDeferred
    , gcObjectDeleteOutcomes =
        [ (key, GcDeleteDeferred)
        | key <- gcReapedObjectKeys (gcIntentEvent intent)
        ]
    }

-- | Execute only opaque authorization proofs. Every proof is checked against
-- the exact current Executing/Reaped decision immediately before deletion.
-- All manifests form a global barrier; physical objects are untouched when
-- any manifest delete fails. Exact successful deletion is followed by the CAS
-- Executing -> Reaped transition before the execution is publishable.
executeAuthorizedGcIntents
  :: (HasMinIO m)
  => [AuthorizedGcIntent]
  -> m GcExecutionResult
executeAuthorizedGcIntents rawAuthorized = do
  let authorized = Set.toAscList (Set.fromList rawAuthorized)
  defended <- traverse defendWithValue authorized
  let defenseFailures =
        [ (experimentGcFenceObjectKey experimentHash, err)
        | (value, Left err) <- defended
        , let intent = authorizedGcIntentValue value
              experimentHash = gcExperimentHash (gcIntentEvent intent)
        ]
  if not (null defenseFailures)
    then
      pure
        GcExecutionResult
          { gcEventExecutions = fmap (deferredGcExecution . authorizedGcIntentValue) authorized
          , gcExecutionPreparationFailures = defenseFailures
          }
    else do
      let states = [(value, alreadyReaped) | (value, Right alreadyReaped) <- defended]
      manifestOutcomes <- traverse deleteManifest states
      if any (isDeleteFailure . third) manifestOutcomes
        then
          pure
            GcExecutionResult
              { gcEventExecutions =
                  [ GcEventExecution
                      { gcExecutionIntent = authorizedGcIntentValue value
                      , gcManifestDeleteOutcome = outcome
                      , gcObjectDeleteOutcomes =
                          [ (key, objectOutcome)
                          | key <- gcReapedObjectKeys (gcIntentEvent (authorizedGcIntentValue value))
                          ]
                      }
                  | (value, alreadyReaped, outcome) <- manifestOutcomes
                  , let objectOutcome =
                          if alreadyReaped
                            then GcDeleteAcknowledged
                            else GcDeleteDeferred
                  ]
              , gcExecutionPreparationFailures = []
              }
        else do
          executions <- traverse completeAuthorized manifestOutcomes
          pure
            GcExecutionResult
              { gcEventExecutions = executions
              , gcExecutionPreparationFailures = []
              }
 where
  defendWithValue value = fmap (pairWithValue value) (defendAuthorizedGcIntent value)
  pairWithValue value defended = (value, defended)

  third (_, _, value) = value

  deleteManifest (value, alreadyReaped)
    | alreadyReaped = pure (value, True, GcDeleteAcknowledged)
    | otherwise = do
        let event = gcIntentEvent (authorizedGcIntentValue value)
            ref =
              checkpointObjectRef
                (manifestKey (gcExperimentHash event) (gcReapedManifestSha event))
        deleted <- deleteObject ref
        pure (value, False, either GcDeleteFailed (const GcDeleteAcknowledged) deleted)

  completeAuthorized (value, alreadyReaped, manifestOutcome)
    | alreadyReaped =
        pure
          GcEventExecution
            { gcExecutionIntent = authorizedGcIntentValue value
            , gcManifestDeleteOutcome = manifestOutcome
            , gcObjectDeleteOutcomes =
                [ (key, GcDeleteAcknowledged)
                | key <- gcReapedObjectKeys (gcIntentEvent (authorizedGcIntentValue value))
                ]
            }
    | otherwise = do
        defendedAgain <- defendAuthorizedGcIntent value
        case defendedAgain of
          Left err -> pure (failedExecution value manifestOutcome err)
          Right True ->
            pure
              GcEventExecution
                { gcExecutionIntent = authorizedGcIntentValue value
                , gcManifestDeleteOutcome = manifestOutcome
                , gcObjectDeleteOutcomes =
                    [ (key, GcDeleteAcknowledged)
                    | key <- gcReapedObjectKeys (gcIntentEvent (authorizedGcIntentValue value))
                    ]
                }
          Right False -> do
            outcomes <-
              traverse
                ( \key -> do
                    deleted <- deleteObject (checkpointObjectRef key)
                    pure (key, either GcDeleteFailed (const GcDeleteAcknowledged) deleted)
                )
                (gcReapedObjectKeys (gcIntentEvent (authorizedGcIntentValue value)))
            if any (isDeleteFailure . snd) outcomes
              then
                pure
                  GcEventExecution
                    { gcExecutionIntent = authorizedGcIntentValue value
                    , gcManifestDeleteOutcome = manifestOutcome
                    , gcObjectDeleteOutcomes = outcomes
                    }
              else do
                reaped <- markAuthorizedGcIntentReaped value
                pure $ case reaped of
                  Left err ->
                    GcEventExecution
                      { gcExecutionIntent = authorizedGcIntentValue value
                      , gcManifestDeleteOutcome = GcDeleteFailed err
                      , gcObjectDeleteOutcomes = outcomes
                      }
                  Right () ->
                    GcEventExecution
                      { gcExecutionIntent = authorizedGcIntentValue value
                      , gcManifestDeleteOutcome = manifestOutcome
                      , gcObjectDeleteOutcomes = outcomes
                      }

  failedExecution value _manifestOutcome err =
    GcEventExecution
      { gcExecutionIntent = authorizedGcIntentValue value
      , gcManifestDeleteOutcome = GcDeleteFailed err
      , gcObjectDeleteOutcomes =
          [ (key, GcDeleteDeferred)
          | key <- gcReapedObjectKeys (gcIntentEvent (authorizedGcIntentValue value))
          ]
      }

  isDeleteFailure (GcDeleteFailed _) = True
  isDeleteFailure _ = False

defendAuthorizedGcIntent
  :: (HasMinIO m)
  => AuthorizedGcIntent
  -> m (Either ServiceError Bool)
defendAuthorizedGcIntent authorized = do
  let intent = authorizedGcIntentValue authorized
  loaded <- readExperimentGcFence (gcExperimentHash (gcIntentEvent intent))
  pure $ do
    (fence, _) <- loaded
    decision <- exactAuthorizedDecision authorized fence
    case gcFenceDecisionPhase decision of
      GcFenceExecuting -> Right False
      GcFenceReaped -> Right True
      _ -> Left (SEConflict "authorized GC operation is no longer Executing/Reaped")

exactAuthorizedDecision
  :: AuthorizedGcIntent
  -> ExperimentGcFence
  -> Either ServiceError GcFenceDecision
exactAuthorizedDecision authorized fence =
  let intent = authorizedGcIntentValue authorized
      matching =
        [ decision
        | decision <- latestGcFenceDecisions (experimentGcFenceDecisions fence)
        , gcIntentEventId (gcFenceDecisionIntent decision) == gcIntentEventId intent
        ]
   in case matching of
        [decision]
          | gcFenceDecisionIntent decision /= intent ->
              Left (SEConflict "authorized GC event id binds different intent bytes")
          | gcFenceDecisionGeneration decision /= authorizedGcGeneration authorized ->
              Left (SEConflict "authorized GC generation is stale")
          | gcFenceDecisionOperationId decision /= authorizedGcOperationId authorized ->
              Left (SEConflict "authorized GC operation id is stale or forged")
          | otherwise -> Right decision
        [] -> Left (SEConflict "authorized GC decision is absent from experiment fence")
        _ -> Left (SETransient "duplicate latest GC decisions for one event id")

markAuthorizedGcIntentReaped
  :: (HasMinIO m)
  => AuthorizedGcIntent
  -> m (Either ServiceError ())
markAuthorizedGcIntentReaped authorized =
  updateExperimentGcFence experimentHash $ \fence -> do
    decision <- exactAuthorizedDecision authorized fence
    case gcFenceDecisionPhase decision of
      GcFenceReaped -> Right (ExperimentFenceUnchanged ())
      GcFenceExecuting ->
        let reaped = decision {gcFenceDecisionPhase = GcFenceReaped}
         in Right
              ( ExperimentFenceChanged
                  (replaceGcFenceDecision decision reaped fence)
                  ()
              )
      _ -> Left (SEConflict "only an executing GC generation may become reaped")
 where
  intent = authorizedGcIntentValue authorized
  experimentHash = gcExperimentHash (gcIntentEvent intent)

data GcPromotionResult = GcPromotionResult
  { gcPromotedReadyEvents :: [GcReadyEvent]
  , gcPromotionFailures :: [(Text, ServiceError)]
  }
  deriving stock (Eq, Show)

-- | Move completed durable intents to publish-ready records. A permanent
-- published tombstone is checked before and after the immutable ready PUT. If
-- another reconciler already won the ready write, that first record (including
-- its stored substrate and timestamp) wins. Cleanup failures never hide an
-- already-durable ready event from the caller.
promoteGcIntents
  :: (HasMinIO m)
  => Text
  -> Word64
  -> [GcIntent]
  -> m GcPromotionResult
promoteGcIntents substrate timestampNs rawIntents =
  case validateGcPromotionBatch substrate timestampNs rawIntents of
    Left failures ->
      pure
        GcPromotionResult
          { gcPromotedReadyEvents = []
          , gcPromotionFailures = failures
          }
    Right candidates -> do
      outcomes <- traverse promoteOne candidates
      pure
        GcPromotionResult
          { gcPromotedReadyEvents =
              Set.toAscList
                (Set.fromList [ready | (Just ready, _) <- outcomes])
          , gcPromotionFailures = concatMap snd outcomes
          }
 where
  promoteOne (intent, candidate) = do
    reaped <- gcIntentHasReapedFenceDecision intent
    case reaped of
      Left err -> pure (Nothing, [(experimentGcFenceObjectKey (gcExperimentHash (gcIntentEvent intent)), err)])
      Right () -> do
        before <- matchingPublishedEvent candidate
        case before of
          Left err -> pure (Nothing, [(gcPublishedObjectKey candidate, err)])
          Right (Just published) -> do
            failures <- cleanupPublishedTransientState intent published
            pure (Nothing, failures)
          Right Nothing -> do
            let readyRef = checkpointObjectRef (gcReadyObjectKey candidate)
            readyResult <- putReadyIfAbsentOrCompatible readyRef candidate
            case readyResult of
              Left err -> pure (Nothing, [(gcReadyObjectKey candidate, err)])
              Right ready -> do
                after <- matchingPublishedEvent ready
                case after of
                  Left err -> pure (Just ready, [(gcPublishedObjectKey ready, err)])
                  Right (Just published)
                    | published /= ready ->
                        pure
                          ( Just ready
                          ,
                            [
                              ( gcPublishedObjectKey ready
                              , SEConflict
                                  "published GC tombstone does not equal the persisted ready event"
                              )
                            ]
                          )
                    | otherwise -> do
                        failures <- cleanupPublishedTransientState intent published
                        pure (Nothing, failures)
                  Right Nothing -> do
                    -- The semantic intent remains durable with the ready
                    -- record until broker success is acknowledged by a
                    -- permanent published tombstone. This preserves the
                    -- complete retry input across broker failures.
                    pure (Just ready, [])

  matchingPublishedEvent candidate = do
    loaded <-
      loadGcPublishedEvents
        (gcExperimentHash (gcReadyEvent candidate))
    pure $ do
      published <- loaded
      case [ value
           | value <- published
           , gcReadyEventId value == gcReadyEventId candidate
           ] of
        [] -> Right Nothing
        [value]
          | gcReadyEvent value == gcReadyEvent candidate -> Right (Just value)
          | otherwise ->
              Left (SEConflict "published GC tombstone conflicts with the intent event")
        _ -> Left (SETransient "duplicate published GC tombstones for one event id")

  cleanupPublishedTransientState intent published = do
    readyRemoved <-
      deleteObject (checkpointObjectRef (gcReadyObjectKey published))
    intentRemoved <-
      deleteObject (checkpointObjectRef (gcIntentObjectKey intent))
    pure
      ( [ (gcReadyObjectKey published, err)
        | Left err <- [readyRemoved]
        ]
          <> [ (gcIntentObjectKey intent, err)
             | Left err <- [intentRemoved]
             ]
      )

gcIntentHasReapedFenceDecision
  :: (HasMinIO m)
  => GcIntent
  -> m (Either ServiceError ())
gcIntentHasReapedFenceDecision intent = do
  loaded <- readExperimentGcFence (gcExperimentHash (gcIntentEvent intent))
  pure $ do
    (fence, _) <- loaded
    let matching =
          [ decision
          | decision <- latestGcFenceDecisions (experimentGcFenceDecisions fence)
          , gcIntentEventId (gcFenceDecisionIntent decision) == gcIntentEventId intent
          ]
    case matching of
      [decision]
        | gcFenceDecisionIntent decision /= intent ->
            Left (SEConflict "reaped fence decision binds different intent bytes")
        | gcFenceDecisionPhase decision /= GcFenceReaped ->
            Left (SEConflict "GC intent is not durably Reaped")
        | otherwise -> Right ()
      [] -> Left (SEConflict "GC intent has no experiment-fence decision")
      _ -> Left (SETransient "duplicate latest GC decisions for promotion")

validateGcPromotionBatch
  :: Text
  -> Word64
  -> [GcIntent]
  -> Either [(Text, ServiceError)] [(GcIntent, GcReadyEvent)]
validateGcPromotionBatch substrate timestampNs rawIntents =
  let canonicalIntents = Set.toAscList (Set.fromList rawIntents)
      candidates =
        [ ( intent
          , GcReadyEvent
              { gcReadyEventId = gcIntentEventId intent
              , gcReadyEvent = gcIntentEvent intent
              , gcReadySubstrate = substrate
              , gcReadyTimestampNs = timestampNs
              }
          )
        | intent <- canonicalIntents
        ]
      validations =
        [ (index, validateGcIntent intent >> validateGcReadyEvent ready)
        | (index, (intent, ready)) <- zip [(0 :: Int) ..] candidates
        ]
      failures =
        [ ( "gc promotion validation[" <> Text.pack (show index) <> "]"
          , SETransient reason
          )
        | (index, Left reason) <- validations
        ]
   in if null failures then Right candidates else Left failures

putReadyIfAbsentOrCompatible
  :: (HasMinIO m)
  => ObjectRef
  -> GcReadyEvent
  -> m (Either ServiceError GcReadyEvent)
putReadyIfAbsentOrCompatible ref candidate = do
  written <- putBlobBytesIfAbsent ref (encodeGcReadyEvent candidate)
  case written of
    Right _ -> pure (Right candidate)
    Left (SEConflict _) -> do
      existingBytes <- minioReadBytes ref
      pure $ do
        bytes <- existingBytes
        existing <-
          mapLeft (SEConflict . ("invalid existing GC ready event: " <>)) (decodeGcReadyEvent bytes)
        if gcReadyEventId existing == gcReadyEventId candidate
          && gcReadyEvent existing == gcReadyEvent candidate
          then Right existing
          else Left (SEConflict "GC ready event exists with conflicting logical fields")
    Left err -> pure (Left err)

acknowledgeGcReadyEvent
  :: (HasMinIO m)
  => GcReadyEvent
  -> m (Either ServiceError ())
acknowledgeGcReadyEvent ready =
  case validateGcReadyEvent ready of
    Left err -> pure (Left (SETransient err))
    Right validated -> do
      let intent =
            GcIntent
              { gcIntentEvent = gcReadyEvent validated
              , gcIntentEventId = gcReadyEventId validated
              }
          readyRef = checkpointObjectRef (gcReadyObjectKey validated)
          publishedRef = checkpointObjectRef (gcPublishedObjectKey validated)
      reaped <- gcIntentHasReapedFenceDecision intent
      case reaped of
        Left err -> pure (Left err)
        Right () -> do
          durableReady <- readExactGcReadyEvent readyRef validated
          durablePublished <- readExactGcReadyEvent publishedRef validated
          publication <-
            case (durableReady, durablePublished) of
              (Right (), _) ->
                putObjectBytesIfAbsentOrSame
                  publishedRef
                  (encodeGcReadyEvent validated)
              (Left _, Right ()) -> pure (Right ())
              (Left readyErr, Left publishedErr) ->
                pure
                  ( Left
                      ( SETransient
                          ( "GC acknowledgement has neither its exact durable ready record nor published tombstone: "
                              <> Text.pack (show (readyErr, publishedErr))
                          )
                      )
                  )
          case publication of
            Left err -> pure (Left err)
            Right () -> do
              readyRemoved <- deleteObject readyRef
              intentRemoved <-
                deleteObject (checkpointObjectRef (gcIntentObjectKey intent))
              pure $
                case lefts [readyRemoved, intentRemoved] of
                  [] -> Right ()
                  [err] -> Left err
                  errors ->
                    Left
                      ( SETransient
                          ( "published GC tombstone persisted but transient cleanup failed: "
                              <> Text.pack (show errors)
                          )
                      )
 where
  readExactGcReadyEvent ref expected = do
    loaded <- minioReadBytes ref
    pure $ do
      bytes <- loaded
      observed <-
        mapLeft
          (SETransient . ("invalid durable GC ready record: " <>))
          (decodeGcReadyEvent bytes)
      if observed == expected
        then Right ()
        else Left (SEConflict "durable GC ready record differs from acknowledgement")

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
  fmap
    (mapLeft renderCheckpointLoadError)
    (loadInferenceCheckpointDecodedWithWeightsTyped runInference experimentHash input)

-- | Typed sibling of 'loadInferenceCheckpointDecodedWithWeights'. The Engine
-- uses this so it can settle a permanently-unsatisfiable request terminally
-- instead of nacking it forever onto a shared subscription.
loadInferenceCheckpointDecodedWithWeightsTyped
  :: (HasMinIO m)
  => ( AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [LoadedWeightTensor]
       -> [Double]
       -> m (Either Text [Double])
     )
  -> Text
  -> [Double]
  -> m (Either CheckpointLoadError ([Double], DecodedInference))
loadInferenceCheckpointDecodedWithWeightsTyped runInference experimentHash input =
  withWeightedCheckpointLoadTyped
    ( \modelRef manifest weights ->
        case checkpointRequestInputRejection manifest input of
          -- Classify before the runner so the verdict is attributable. The
          -- runner reaches the same conclusion, but only as an untyped 'Text'
          -- failure indistinguishable from a device error — and a device error
          -- must stay retryable while this must not.
          Just reason -> pure (Left (CheckpointLoadInputRejected reason))
          Nothing ->
            fmap
              ( mapLeft CheckpointLoadRunnerFailed
                  . fmap (\output -> (output, decodeManifestOutput manifest output))
              )
              (runInference modelRef manifest weights input)
    )
    experimentHash

-- | Does the admitted manifest's declared runtime reject this request's input?
--
-- The served path applies the runtime's input transform, so its domain — the
-- declared width, the unit-image @[0,1]@ range, standardization finiteness — is
-- part of the request contract rather than a runtime hazard. Answering the
-- question here, against the same transform the served path uses, is what lets
-- the Engine tell a request it can never satisfy from one it merely failed to
-- satisfy this time. A manifest with no supervised runtime declares no input
-- domain, so it rejects nothing and the runner remains the sole judge.
checkpointRequestInputRejection :: CheckpointManifest -> [Double] -> Maybe Text
checkpointRequestInputRejection manifest input =
  case manifestSupervisedRuntime manifest of
    Nothing -> Nothing
    Just payload ->
      case RuntimeArtifact.applyRuntimeInputTransform
        ( RuntimeArtifact.supervisedRuntimeInputTransform
            (RuntimeArtifact.payloadRuntime payload)
        )
        (VU.fromList input) of
        Left reason -> Just reason
        Right _ -> Nothing

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
withWeightedCheckpoint continuation experimentHash =
  fmap
    (mapLeft renderCheckpointLoadError)
    (withWeightedCheckpointTyped continuation experimentHash)

-- | Typed core of 'withWeightedCheckpoint'.
--
-- 'withWeightedCheckpoint' renders its failure to 'Text', which discards
-- whether the checkpoint was ABSENT or merely unreadable. Callers that settle
-- durable work need that distinction: an absent checkpoint can never be
-- satisfied by a retry, while a transient read failure can. This variant keeps
-- the admission error intact so 'checkpointLoadErrorTerminal' can decide.
withWeightedCheckpointTyped
  :: (HasMinIO m)
  => ( AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [LoadedWeightTensor]
       -> m (Either Text a)
     )
  -> Text
  -> m (Either CheckpointLoadError a)
withWeightedCheckpointTyped continuation =
  withWeightedCheckpointLoadTyped
    ( \admitted manifest weights ->
        fmap
          (mapLeft CheckpointLoadRunnerFailed)
          (continuation admitted manifest weights)
    )

-- | Admit the latest completed checkpoint and hand it to a continuation that
-- already classifies its own failures. 'withWeightedCheckpointTyped' is the
-- special case whose continuation can only fail as a runner.
withWeightedCheckpointLoadTyped
  :: (HasMinIO m)
  => ( AdmittedCompletedCheckpoint
       -> CheckpointManifest
       -> [LoadedWeightTensor]
       -> m (Either CheckpointLoadError a)
     )
  -> Text
  -> m (Either CheckpointLoadError a)
withWeightedCheckpointLoadTyped continuation experimentHash = do
  admission <- admitLatestCompletedCheckpoint experimentHash
  case admission of
    Left err -> pure (Left (CheckpointLoadAdmissionFailed err))
    Right admitted ->
      let checkpoint = admittedCompletedCheckpoint admitted
       in continuation
            admitted
            (admittedCheckpointManifest checkpoint)
            (admittedCheckpointWeights checkpoint)

decodeLoadedWeightTensorWithSnapshotHashes
  :: Maybe (Map.Map Text Text)
  -> CheckpointManifest
  -> TensorBlob
  -> StrictByteString.ByteString
  -> Either Text LoadedWeightTensor
decodeLoadedWeightTensorWithSnapshotHashes snapshotHashes manifest tensor bytes = do
  let lazyBytes = LazyByteString.fromStrict bytes
      actualSha = jmw1ContentSha lazyBytes
      expectedKey = blobKey (manifestExperiment manifest) actualSha
  case snapshotHashes of
    Just hashes ->
      mapLeft
        renderCheckpointAdmissionError
        ( requireSnapshotPayloadHash
            hashes
            (tensorBlobKey tensor)
            actualSha
            ("weight tensor " <> tensorName tensor)
        )
    Nothing ->
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

-- | Validate that a manifest's persisted supervised runtime and its one exact
-- physical @supervised.weights@ blob are coherent.  A runtime-free manifest (RL,
-- AlphaZero, tuning) deliberately returns @()@ so weight-only engine paths stay
-- isolated from the supervised-graph path.
--
-- Phase 239: every supervised checkpoint advertises a trained layer graph
-- (@architectureLayerGraph@), so the @supervised.weights@ blob is the
-- graph-ordered parameter vector and its length is anchored to the graph's
-- parameter count.  Serving reconstructs and runs the graph directly
-- ('runSupervisedGraphCheckpointInference'); there is no token-runtime
-- reconstruction.  This function performs the physical-tensor and graph-count
-- admission checks.
loadSupervisedRuntimeFromCheckpoint
  :: CheckpointManifest
  -> [LoadedWeightTensor]
  -> Either Text ()
loadSupervisedRuntimeFromCheckpoint manifest weights =
  case manifestSupervisedRuntime manifest of
    Nothing -> Right ()
    Just _payload ->
      case architectureLayerGraph (manifestArchitecture manifest) of
        Just graphMeta -> do
          _ <- requireSupervisedWeightsTensor weights (layerGraphMetadataParameterCount graphMeta)
          Right ()
        Nothing ->
          Left "supervised checkpoint is missing its trained layer-graph metadata"

-- | Validate the one physical @supervised.weights@ tensor against the expected
-- (graph-ordered or token-op) parameter count and return its loaded values.
requireSupervisedWeightsTensor
  :: [LoadedWeightTensor] -> Int -> Either Text LoadedWeightTensor
requireSupervisedWeightsTensor weights parameterCount =
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
                else Right loaded
    [] -> Left "V2 supervised runtime is missing supervised.weights"
    _ ->
      Left
        ( "V2 supervised runtime requires exactly one physical weight "
            <> "blob, got "
            <> Text.pack (show (length weights))
        )

-- | Phase 239 — reconstruct the served trained dense 'LayerGraph.LayerGraph'
-- from a checkpoint's layer-graph metadata and inject the one physical
-- @supervised.weights@ blob as its graph-ordered parameter vector.  The
-- returned graph is ready for 'LayerGraph.runLayerGraph'; the input/output
-- transforms stay outside the graph and are applied by the engine backend.
reconstructSupervisedGraphFromCheckpoint
  :: CheckpointManifest
  -> [LoadedWeightTensor]
  -> Either Text (RuntimeArtifact.SupervisedRuntimePayload, LayerGraph.LayerGraph)
reconstructSupervisedGraphFromCheckpoint manifest weights = do
  payload <-
    maybe
      (Left "supervised graph checkpoint is missing its runtime payload")
      Right
      (manifestSupervisedRuntime manifest)
  graphMeta <-
    maybe
      (Left "supervised graph checkpoint is missing its layer graph metadata")
      Right
      (architectureLayerGraph (manifestArchitecture manifest))
  loaded <-
    requireSupervisedWeightsTensor weights (layerGraphMetadataParameterCount graphMeta)
  graph <- layerGraphFromMetadata graphMeta
  injected <-
    LayerGraph.replaceGraphParameterVector
      graph
      (VU.fromList (loadedWeightValues loaded))
  Right (payload, injected)

-- | Phase 239/240 — full served inference for a supervised-graph checkpoint:
-- reconstruct the trained typed graph, inject the persisted parameters, gate the
-- reloaded graph through 'LayerGraph.refineReloadedLayerGraph' (a tampered or
-- structurally malformed envelope fails closed), then apply the exact input
-- transform, run the graph, and apply the exact output transform.  Serving is a
-- pure deterministic function of the checkpoint and input; the transforms ride
-- outside the graph and the graph is run through the pure reference executor
-- 'LayerGraph.runLayerGraph' (via 'RuntimeArtifact.executeSupervisedGraphRuntime'),
-- which handles every correct operator.  This is the sole supervised serving
-- path — the linux-cuda and apple-silicon engines delegate to it — and is
-- substrate-independent (bit-identical across substrates); the V2 token-runtime
-- engine path has been retired.
runSupervisedGraphCheckpointInference
  :: CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runSupervisedGraphCheckpointInference manifest weights input =
  pure $
    case reconstructSupervisedGraphFromCheckpoint manifest weights of
      Left err -> Left err
      Right (payload, reloadedGraph) ->
        case LayerGraph.refineReloadedLayerGraph reloadedGraph of
          Left err -> Left ("reloaded supervised graph refinement failed: " <> err)
          Right graph ->
            fmap
              VU.toList
              ( RuntimeArtifact.executeSupervisedGraphRuntime
                  payload
                  graph
                  (VU.fromList input)
              )

validateLoadedManifest
  :: Text
  -> Text
  -> Text
  -> CheckpointManifest
  -> Either Text CheckpointManifest
validateLoadedManifest = validateAddressedManifest

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

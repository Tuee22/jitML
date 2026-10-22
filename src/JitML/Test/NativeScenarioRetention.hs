{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Historical HMAC authentication plus actual same-host physical re-audit.
-- This is distinct from the original owned-execution certificate. No parsed
-- receipt restores a process, selected-device replay or original Root result.
module JitML.Test.NativeScenarioRetention
  ( module Receipt
  , AuthenticatedRetainedNativeQualification
  , NativeScenarioRetentionFailure (..)
  , NativeScenarioRetentionStage (..)
  , NativeScenarioPortableFileData (..)
  , NativeScenarioPortableInventory (..)
  , reauditNativeScenarioQualification
  , renderNativeScenarioRetentionFailure
  , retainedNativeScenarioReceiptData
  , retainedNativeScenarioBinding
  , retainedNativeScenarioAdmitted
  , retainedNativeScenarioPortableInventory
  , nativeScenarioRecordedIssuedBytes
  , nativeScenarioRecordedRawAvailabilityBytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (bracket, evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (runReaderT)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (find, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Directory (canonicalizePath, doesDirectoryExist)
import System.FilePath (splitDirectories, (</>))
import System.IO (IOMode (ReadMode), hFileSize, withBinaryFile)
import System.Posix.Directory qualified as Directory
import System.Posix.Files (getSymbolicLinkStatus, isDirectory, isRegularFile, isSymbolicLink)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativeParentPhysicalRead qualified as Physical
import JitML.Checkpoint.NativeParentPolicyData qualified as Policy
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (AggregateSequenceElements), boundedLength)
import JitML.Checkpoint.NativeReferences qualified as References
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Env.Build qualified as Env
import JitML.Execution.NativeParentAttemptRetention qualified as Attempt
import JitML.Plan.Plan qualified as Plan
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeParentCompletionData qualified as Completion
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (renderSubstrate)
import JitML.Test.NativeScenarioJournalBindingData qualified as Journal
import JitML.Test.NativeScenarioReceiptData as Receipt
import JitML.Test.ProductScenarioAuthorization qualified as Authorization
import JitML.Training.Budget qualified as Training

data NativeScenarioRetentionStage
  = NativeRetentionInput
  | NativeRetentionAuthentication
  | NativeRetentionIdentity
  | NativeRetentionAttemptFiles
  | NativeRetentionPhysical
  | NativeRetentionPolicy
  | NativeRetentionSummary
  | NativeRetentionPortableInventory
  | NativeRetentionFinished
  deriving stock (Eq, Show)
data NativeScenarioRetentionFailure
  = NativeScenarioRetentionFailure
      !NativeScenarioRetentionStage
      !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)

-- Copy-plan DATA describes already read physical files. It is compact and
-- never embeds a multi-GiB report/raw stream in every retained report row.
data NativeScenarioPortableFileData = NativeScenarioPortableFileData
  { nativePortableObjectKey :: !Text
  , nativePortableOriginalPath :: !FilePath
  , nativePortableObjectBytes :: !Word64
  , nativePortableObjectSha256 :: !Text
  , nativePortableObjectMaximumBytes :: !Integer
  }
  deriving stock (Eq, Show)
newtype NativeScenarioPortableInventory = NativeScenarioPortableInventory
  {nativePortableFiles :: [NativeScenarioPortableFileData]}
  deriving stock (Eq, Show)

data AuthenticatedRetainedNativeQualification
  = AuthenticatedRetainedNativeQualification
      !Receipt.NativeScenarioReceiptData
      !Journal.NativeScenarioJournalBindingData
      !Store.AdmittedExecutionCheckpoint
      !NativeScenarioPortableInventory
  deriving stock (Eq, Show)

retainedNativeScenarioReceiptData
  :: AuthenticatedRetainedNativeQualification -> Receipt.NativeScenarioReceiptData
retainedNativeScenarioReceiptData (AuthenticatedRetainedNativeQualification actual _ _ _) = actual
retainedNativeScenarioBinding
  :: AuthenticatedRetainedNativeQualification -> Journal.NativeScenarioJournalBindingData
retainedNativeScenarioBinding (AuthenticatedRetainedNativeQualification _ actual _ _) = actual
retainedNativeScenarioAdmitted
  :: AuthenticatedRetainedNativeQualification -> Store.AdmittedExecutionCheckpoint
retainedNativeScenarioAdmitted (AuthenticatedRetainedNativeQualification _ _ actual _) = actual
retainedNativeScenarioPortableInventory
  :: AuthenticatedRetainedNativeQualification -> NativeScenarioPortableInventory
retainedNativeScenarioPortableInventory (AuthenticatedRetainedNativeQualification _ _ _ actual) = actual
renderNativeScenarioRetentionFailure :: NativeScenarioRetentionFailure -> Text
renderNativeScenarioRetentionFailure = Text.pack . show

type Program = ExceptT Text IO

reauditNativeScenarioQualification
  :: Authorization.AuthenticatedProductScenarioJournalRow
  -> Journal.NativeScenarioJournalBindingData
  -> Matrix.ProductProjection kind
  -> FilePath
  -> Store.AdmittedExecutionCheckpoint
  -> Receipt.NativeScenarioReceiptData
  -> IO (Either NativeScenarioRetentionFailure AuthenticatedRetainedNativeQualification)
reauditNativeScenarioQualification authenticated journal projection checkpointRoot admitted receipt = do
  progress <- newIORef NativeRetentionInput
  result <-
    tryAny
      (runExceptT (program progress authenticated journal projection checkpointRoot admitted receipt))
  case result of
    Left exception -> do
      diagnostic <- Failure.captureNativeExceptionDiagnostic exception
      Left . (`NativeScenarioRetentionFailure` diagnostic) <$> readIORef progress
    Right (Left reason) -> do
      diagnostic <- Failure.captureNativeDiagnostic reason
      Left . (`NativeScenarioRetentionFailure` diagnostic) <$> readIORef progress
    Right (Right actual) -> pure (Right actual)

program
  :: IORef NativeScenarioRetentionStage
  -> Authorization.AuthenticatedProductScenarioJournalRow
  -> Journal.NativeScenarioJournalBindingData
  -> Matrix.ProductProjection kind
  -> FilePath
  -> Store.AdmittedExecutionCheckpoint
  -> Receipt.NativeScenarioReceiptData
  -> Program AuthenticatedRetainedNativeQualification
program progress authenticated journal projection checkpointRoot admitted receipt = do
  _ <- liftIO (evaluate receipt)
  _ <- checkedCodec (Receipt.refineNativeScenarioReceiptData receipt)
  stage progress NativeRetentionAuthentication
  rendered <- checkedCodec (Receipt.renderNativeScenarioReceiptData receipt)
  require
    ( Authorization.authenticatedProductScenarioJournalRowRunId authenticated
        == Journal.nativeScenarioBindingRunId journal
        && Authorization.authenticatedProductScenarioJournalRowMaterialMatches
          authenticated
          (Journal.nativeScenarioJournalBindingMaterial journal rendered)
    )
    "native retained receipt differs from the original authenticated semantic row"
  stage progress NativeRetentionIdentity
  _ <- liftIO (evaluate admitted)
  let request = Receipt.nativeScenarioReceiptRequest receipt
      reference = Receipt.nativeScenarioReceiptReference receipt
      raw = Reference.nativeQualificationReferenceData reference
      invocation = Parent.nativeParentRequestInvocation request
      workdir = Parent.nativeParentRequestWorkdir request
      source = Parent.nativeParentRequestSource request
      completed = Store.admittedExecutionCompletedTraining admitted
      manifest = Store.admittedExecutionCheckpoint admitted
      row = Matrix.productProjectionRowId projection
  require
    (Matrix.productProjectionFamily projection `elem` [Matrix.ReinforcementLearning, Matrix.AlphaZero])
    "native retained qualification received a foreign model family"
  require
    (checkpointRoot == workdir </> ".build" </> "checkpoints")
    "native retained checkpoint scope differs from original child"
  liftIO (canonicalDirectory workdir >> canonicalDirectory checkpointRoot)
  require
    ( Reference.nativeReferenceRow raw == row
        && Reference.nativeReferenceLane raw == Matrix.productProjectionSubstrate projection
        && Reference.nativeReferencePlan raw == Plan.planIdText (Matrix.productProjectionPlanId projection)
        && Reference.nativeReferenceExperiment raw == Matrix.productProjectionExperimentHash projection
        && Reference.nativeReferenceManifest raw == Store.admittedCheckpointManifestSha manifest
        && Training.completedTrainingProductScenarioInvocation completed == Just invocation
        && Receipt.nativeScenarioReceiptArguments receipt == Matrix.productProjectionCommand projection
    )
    "native retained original identities differ from current projection or actual Store admission"
  require
    ( Journal.nativeScenarioBindingRowId journal == row
        && Journal.nativeScenarioBindingRunId journal == Training.productScenarioInvocationRunId invocation
        && Journal.nativeScenarioBindingPlanId journal == Reference.nativeReferencePlan raw
        && Journal.nativeScenarioBindingSubstrate journal
          == renderSubstrate (Reference.nativeReferenceLane raw)
        && Journal.nativeScenarioBindingExecutableSha256 journal == Reference.nativeReferenceExecutable raw
        && Journal.nativeScenarioBindingInvocationDigest journal == Reference.nativeReferenceInvocation raw
        && Journal.nativeScenarioBindingExperimentHash journal == Reference.nativeReferenceExperiment raw
        && Journal.nativeScenarioBindingManifestSha256 journal == Reference.nativeReferenceManifest raw
        && Journal.nativeScenarioBindingInferenceManifestSha256 journal
          == Reference.nativeReferenceManifest raw
        && Journal.nativeScenarioBindingCheckpointScopeSha256 journal
          == Training.productScenarioInvocationCheckpointScopeDigest invocation
        && Journal.nativeScenarioBindingCommand journal
          == renderSubprocess (subprocess "jitml" (Matrix.productProjectionCommand projection))
        && Journal.nativeScenarioBindingPreconditionRejected journal
        && ( Journal.nativeScenarioBindingPreconditionSequence journal
           , Journal.nativeScenarioBindingInferenceSequence journal
           , Journal.nativeScenarioBindingCompletionSequence journal
           )
          == (3, 7, 9)
    )
    "native retained authenticated row differs from original complete scenario identity"
  batch <- checked (Cohort.mkCanonicalNativeRlCohorts (Matrix.productProjectionSubstrate projection))
  cohort <-
    maybe
      (throwError "native retained row is absent from complete current canonical batch")
      pure
      ( find
          ((== row) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  stage progress NativeRetentionAttemptFiles
  attemptFiles <- auditAttemptFiles cohort receipt
  stage progress NativeRetentionPhysical
  env <-
    liftIO (Env.buildEnv (Env.defaultGlobalFlags {Env.globalCacheDir = Just (workdir </> ".build")}))
  physical <-
    liftIO (runReaderT (Physical.readNativeParentQualificationPayloads workdir reference) env)
      >>= either (throwError . Text.pack . show . Physical.nativeParentReadFailureReport) pure
  require
    (Physical.nativeParentPhysicalAdmitted physical == admitted)
    "native retained complete physical re-read differs from original addressed Store admission"
  binding <-
    checked
      ( Binding.checkNativeParentBindingData
          batch
          row
          ( Binding.NativeParentExpectedData
              source
              (Reference.nativeReferenceExecutable raw)
              invocation
              (Reference.nativeReferenceManifest raw)
              (Training.encodeCompletedTraining completed)
          )
          reference
          (Physical.nativeParentPhysicalPayloads physical)
      )
  stage progress NativeRetentionPolicy
  executable <-
    checkedCodec (Context.digestFromCanonicalText (Reference.nativeReferenceExecutable raw))
  policy <-
    liftIO
      ( Policy.verifyNativeParentPolicyData
          batch
          ( Policy.NativeParentExpectations
              source
              executable
              (Context.SuppliedScenarioContext invocation)
              (Context.NativeContextSources Nothing (Just source))
              ( Receipt.nativeScenarioReceiptProcessId receipt
              , Receipt.nativeScenarioReceiptParentProcessId receipt
              )
          )
          binding
      )
      >>= either (throwError . Text.pack . show) pure
  require
    (null (Policy.nativeParentPolicyFindings policy))
    "native retained original cohort has learning findings"
  checked (Completion.checkNativeParentCompletionData policy admitted)
  stage progress NativeRetentionSummary
  let children = Policy.nativeParentPolicyChildren policy
      devices =
        concatMap (\child -> [childDevice child, childDevice child]) children
          <> case children of first : _ -> [childDevice first]; [] -> []
      arenaReference = case children of
        Policy.NativeParentArenaChild {} : _ ->
          Just
            ( shaDigest
                ( References.nativeReferenceDataBytes
                    (Acquisition.acquisitionReferences (Binding.nativeParentBindingAcquisition binding))
                )
            )
        _ -> Nothing
  referenceRoot <- traverse checkedCodec arenaReference
  checkedCodec
    ( Summary.checkNativeParentEvaluationSummaryData
        (Binding.nativeParentBindingReplays binding)
        devices
        referenceRoot
        (Receipt.nativeScenarioReceiptEvaluationSummary receipt)
    )
  stage progress NativeRetentionPortableInventory
  portable <- collectPortableInventory checkpointRoot receipt physical attemptFiles
  stage progress NativeRetentionFinished
  pure (AuthenticatedRetainedNativeQualification receipt journal admitted portable)
 where
  childDevice child = case child of
    Policy.NativeParentReturnChild _ _ _ _ _ device _ -> deviceRaw device
    Policy.NativeParentHerChild _ _ _ _ _ device -> deviceRaw device
    Policy.NativeParentArenaChild _ _ _ _ _ device -> deviceRaw device
  deviceRaw Policy.NativeHostNoMlpData = Nothing
  deviceRaw (Policy.NativeRecordedDeviceData raw) = Just raw
  shaDigest = Context.digestFromCanonicalText . sha256Hex

collectPortableInventory
  :: FilePath
  -> Receipt.NativeScenarioReceiptData
  -> Physical.NativeParentPhysicalPayloads
  -> [NativeScenarioPortableFileData]
  -> Program NativeScenarioPortableInventory
collectPortableInventory checkpointRoot receipt physical attemptFiles = do
  let reference = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference receipt)
      limits = Store.nativeRecordedCheckpointLimits
      objectReads = Physical.parentReadActualObjects (Physical.nativeParentPhysicalReport physical)
      actualAdmitted = Physical.nativeParentPhysicalAdmitted physical
      actualManifest = Store.admittedCheckpointManifest (Store.admittedExecutionCheckpoint actualAdmitted)
      experiment = Reference.nativeReferenceExperiment reference
      manifestSha = Reference.nativeReferenceManifest reference
      manifestKey = Format.manifestKey experiment manifestSha
  _ <- checkedCodec (boundedLength AggregateSequenceElements 141 objectReads)
  detached <-
    mapM
      ( \actual -> do
          let original = Physical.parentReadOriginalReference actual
          path <- objectPath checkpointRoot (Retain.nativeRetainedObjectKey original)
          let planned =
                NativeScenarioPortableFileData
                  (Retain.nativeRetainedObjectKey original)
                  path
                  (Retain.nativeRetainedObjectBytes original)
                  (Retain.nativeRetainedObjectSha256 original)
                  Physical.maximumNativeParentReadBytes
          liftIO (verifyPhysicalFile planned)
          pure planned
      )
      objectReads
  manifestPath <- objectPath checkpointRoot manifestKey
  manifestBytes <- liftIO (readSmallFile (Store.recordedManifestByteLimit limits) manifestPath)
  require
    (sha256Hex manifestBytes == manifestSha)
    "native retained manifest FILE differs from exact addressed digest"
  snapshot <-
    checked (Store.checkpointStorageSnapshotId actualManifest)
      >>= maybe (throwError "native retained checkpoint has no exact storage snapshot") pure
  let commitKey = "jitml-checkpoints/" <> experiment <> "/snapshots/" <> snapshot <> "/committed.cbor"
  commitPath <- objectPath checkpointRoot commitKey
  commitBytes <- liftIO (readSmallFile (Store.recordedCommitByteLimit limits) commitPath)
  (recordedManifest, commit) <-
    checked
      ( Store.checkNativeRecordedSnapshotCommitData
          experiment
          manifestSha
          (LBS.fromStrict manifestBytes)
          commitBytes
      )
  require
    (recordedManifest == actualManifest && Store.writerCommitObjectKey commit == commitKey)
    "native retained recorded commit differs from actual complete Store manifest"
  _ <-
    checkedCodec
      ( boundedLength
          AggregateSequenceElements
          (toInteger (Store.recordedPayloadObjectLimit limits))
          (Store.writerCommitPhysicalObjects commit)
      )
  payloads <-
    mapM
      ( \actual -> do
          let key = Store.writerPhysicalObjectKey actual
          path <- objectPath checkpointRoot key
          -- These portable FILE acceptance caps do not alter live Store admission.
          let cap = max (Store.recordedTensorByteLimit limits) (Store.recordedCompanionByteLimit limits)
          liftIO (ensureRegularPath path)
          (digest, count) <- liftIO (hashFile cap path)
          require
            (digest == Store.writerPhysicalObjectSha actual)
            "native retained snapshot physical FILE differs from exact commit hash"
          pure (NativeScenarioPortableFileData key path (fromInteger count) digest cap)
      )
      (Store.writerCommitPhysicalObjects commit)
  let controls =
        [ NativeScenarioPortableFileData
            manifestKey
            manifestPath
            (fromIntegral (BS.length manifestBytes))
            manifestSha
            (Store.recordedManifestByteLimit limits)
        , NativeScenarioPortableFileData
            commitKey
            commitPath
            (fromIntegral (BS.length commitBytes))
            (sha256Hex commitBytes)
            (Store.recordedCommitByteLimit limits)
        ]
  assets <- auditOriginalAssets receipt
  let allFiles = detached <> controls <> payloads <> attemptFiles <> assets
  _ <- checkedCodec (boundedLength AggregateSequenceElements 163 allFiles)
  unique <- foldFiles Map.empty allFiles
  -- Original artifacts are compared to their exact count/SHA again while
  -- copying; this compact value grants no ongoing filesystem immutability.
  pure (NativeScenarioPortableInventory (Map.elems unique))
 where
  foldFiles actual [] = pure actual
  foldFiles actual (value : rest) = case Map.lookup (nativePortableObjectKey value) actual of
    Nothing -> foldFiles (Map.insert (nativePortableObjectKey value) value actual) rest
    Just previous -> do
      require
        ( nativePortableObjectBytes previous == nativePortableObjectBytes value
            && nativePortableObjectSha256 previous == nativePortableObjectSha256 value
        )
        "native retained portable inventory has conflicting duplicate keys"
      let retained =
            previous
              { nativePortableObjectMaximumBytes =
                  min
                    (nativePortableObjectMaximumBytes previous)
                    (nativePortableObjectMaximumBytes value)
              }
      foldFiles (Map.insert (nativePortableObjectKey value) retained actual) rest

-- Retain the actual pinned executable and actual artifact FILEs named by the
-- original observed device witnesses. Re-reading their bytes is a FILE audit,
-- never a second kernel dispatch or proof of a newly loaded process image.
auditOriginalAssets :: Receipt.NativeScenarioReceiptData -> Program [NativeScenarioPortableFileData]
auditOriginalAssets receipt = do
  let request = Receipt.nativeScenarioReceiptRequest receipt
      reference = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference receipt)
      executable =
        (Parent.nativeParentRequestPinnedExecutable request, Reference.nativeReferenceExecutable reference)
      devices =
        [ (Text.unpack (Witness.rawWitnessArtifactPath raw), Witness.rawWitnessArtifactSha256 raw)
        | item <- Summary.parentSummaryMatches (Receipt.nativeScenarioReceiptEvaluationSummary receipt)
        , Just raw <- [Summary.parentSummaryDevice item]
        ]
  mapM one (executable : devices)
 where
  one (path, expected) = do
    liftIO (ensureRegularPath path)
    actual <- liftIO (canonicalizePath path)
    require (actual == path) "native retained original artifact FILE path is not physically canonical"
    (digest, count) <- liftIO (hashFile 1073741824 path)
    require
      (digest == expected && count > 0)
      "native retained original executable or device artifact FILE differs from original observation"
    pure
      ( NativeScenarioPortableFileData
          ("native-qualified-assets-v1/" <> digest <> ".bin")
          path
          (fromInteger count)
          digest
          1073741824
      )

objectPath :: FilePath -> Text -> Program FilePath
objectPath root key = checked (Store.objectPathForKey root key)

auditAttemptFiles
  :: Cohort.NativeRlCohortPlan
  -> Receipt.NativeScenarioReceiptData
  -> Program [NativeScenarioPortableFileData]
auditAttemptFiles cohort receipt = do
  let inventory = Receipt.nativeScenarioReceiptAttemptInventory receipt
      workdir = Parent.nativeParentRequestWorkdir (Receipt.nativeScenarioReceiptRequest receipt)
      scope = Receipt.nativeScenarioReceiptAttemptScope receipt
      directory = workdir </> ".build" </> "native-parent-attempts" </> Text.unpack scope
      prefix = "native-parent-attempts-v1/" <> scope <> "/"
      mandatory =
        [ ("issued.cbor", 65536, Attempt.nativeParentAttemptIssuedFile inventory)
        , ("report.utf8", 4294967296, Attempt.nativeParentAttemptReportFile inventory)
        , ("availability.cbor", 4096, Attempt.nativeParentAttemptAvailabilityFile inventory)
        ]
  streams <- case (Attempt.nativeParentAttemptStdoutFile inventory, Attempt.nativeParentAttemptStderrFile inventory) of
    (Just stdoutFile, Just stderrFile) ->
      pure
        [("stdout.bin", 1073741824, stdoutFile), ("stderr.bin", 1073741824, stderrFile)]
    _ -> throwError "native retained success lacks both original raw streams"
  liftIO $ do
    exactMembers directory ["issued.cbor", "result"]
    exactMembers
      (directory </> "result")
      ["report.utf8", "availability.cbor", "stdout.bin", "stderr.bin"]
  files <-
    mapM
      ( \(leaf, cap, actual) -> do
          let planned =
                NativeScenarioPortableFileData
                  (prefix <> leaf)
                  (Attempt.nativeParentAttemptFilePath actual)
                  (Attempt.nativeParentAttemptFileBytes actual)
                  (Attempt.nativeParentAttemptFileSha256 actual)
                  cap
          liftIO (verifyPhysicalFile planned)
          pure planned
      )
      (mandatory <> streams)
  issued <-
    liftIO
      ( readSmallFile
          65536
          (Attempt.nativeParentAttemptFilePath (Attempt.nativeParentAttemptIssuedFile inventory))
      )
  expectedIssued <- checked (originalIssuedRecord cohort receipt)
  require
    (issued == expectedIssued)
    "native retained issued bytes differ from exact original request"
  availability <-
    liftIO
      ( readSmallFile
          4096
          (Attempt.nativeParentAttemptFilePath (Attempt.nativeParentAttemptAvailabilityFile inventory))
      )
  require
    ( availability
        == Wire.encodeStrict
          ( CBOR.encodeListLen 4
              <> CBOR.encodeString "jitml-native-parent-raw-availability-v1"
              <> CBOR.encodeWord 1
              <> CBOR.encodeBool True
              <> CBOR.encodeBool True
          )
    )
    "native retained raw availability differs from successful original capture"
  pure files

-- Exact original canonical12-field issued DATA, never a restored reservation.
originalIssuedRecord
  :: Cohort.NativeRlCohortPlan -> Receipt.NativeScenarioReceiptData -> Either Text ByteString
originalIssuedRecord cohort receipt = do
  reviewBytes <-
    traverse
      Review.encodeCriterionReviewIdentityData
      (Receipt.nativeScenarioReceiptCriterionReview receipt)
  pure
    ( Wire.encodeStrict
        ( CBOR.encodeListLen (case reviewBytes of Nothing -> 12; Just _ -> 13)
            <> CBOR.encodeString
              ( case reviewBytes of
                  Nothing -> "jitml-native-parent-issued-request-v1"
                  Just _ -> "jitml-native-parent-issued-request-v2"
              )
            <> CBOR.encodeWord (case reviewBytes of Nothing -> 1; Just _ -> 2)
            <> CBOR.encodeString (Text.pack (Parent.nativeParentRequestSourceRoot request))
            <> CBOR.encodeString (Text.pack (Parent.nativeParentRequestWorkdir request))
            <> CBOR.encodeString (Text.pack (Parent.nativeParentRequestPinnedExecutable request))
            <> CBOR.encodeWord64 (Source.stampAlgorithm (Parent.nativeParentRequestSource request))
            <> CBOR.encodeString (Source.stampSha256 (Parent.nativeParentRequestSource request))
            <> CBOR.encodeString
              (Training.renderProductScenarioInvocation (Parent.nativeParentRequestInvocation request))
            <> CBOR.encodeString (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
            <> CBOR.encodeString
              ( Reference.nativeReferenceAllocationKey
                  (Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference receipt))
              )
            <> CBOR.encodeString "supplied-source-only"
            <> maybe mempty CBOR.encodeBytes reviewBytes
            <> CBOR.encodeListLen (fromIntegral (length arguments))
            <> foldMap CBOR.encodeString arguments
        )
    )
 where
  request = Receipt.nativeScenarioReceiptRequest receipt
  arguments = Receipt.nativeScenarioReceiptArguments receipt

verifyPhysicalFile :: NativeScenarioPortableFileData -> IO ()
verifyPhysicalFile planned = do
  ensureRegularPath (nativePortableOriginalPath planned)
  (digest, count) <-
    hashFile (nativePortableObjectMaximumBytes planned) (nativePortableOriginalPath planned)
  ioRequire
    ( count == toInteger (nativePortableObjectBytes planned)
        && digest == nativePortableObjectSha256 planned
    )
    "native retained file actual count or SHA differs"
  ensureRegularPath (nativePortableOriginalPath planned)

hashFile :: Integer -> FilePath -> IO (Text, Integer)
hashFile cap path = withBinaryFile path ReadMode $ \handle -> do
  size <- hFileSize handle
  ioRequire
    (size >= 0 && size <= cap)
    "native retained physical file exceeds its role cap before streaming"
  let loop !context !count = do
        chunk <- BS.hGetSome handle 65536
        if BS.null chunk
          then pure (hex (SHA256.finalize context), count)
          else do
            let next = count + toInteger (BS.length chunk)
            ioRequire (next <= cap) "native retained physical file grew beyond its role cap"
            loop (SHA256.update context chunk) next
  loop SHA256.init 0

readSmallFile :: Integer -> FilePath -> IO ByteString
readSmallFile cap path = do
  ensureRegularPath path
  withBinaryFile path ReadMode $ \handle -> do
    bytes <- BS.hGet handle (fromInteger cap + 1)
    ioRequire (toInteger (BS.length bytes) <= cap) "native retained bounded physical buffer exceeds cap"
    pure bytes

canonicalDirectory :: FilePath -> IO ()
canonicalDirectory path = do
  mapM_ ensureDirectory (pathPrefixes path)
  actual <- canonicalizePath path
  exists <- doesDirectoryExist path
  ioRequire (exists && actual == path) "native retained scope is not a real canonical directory"

ensureRegularPath :: FilePath -> IO ()
ensureRegularPath path = case reverse (pathPrefixes path) of
  [] -> ioRequire False "native retained physical path is empty"
  final : parents -> do
    mapM_ ensureDirectory (reverse parents)
    status <- getSymbolicLinkStatus final
    ioRequire
      (isRegularFile status && not (isSymbolicLink status))
      "native retained physical file is not a real regular nonlink"

ensureDirectory :: FilePath -> IO ()
ensureDirectory path = do
  status <- getSymbolicLinkStatus path
  ioRequire
    (isDirectory status && not (isSymbolicLink status))
    "native retained path prefix is not a real directory"

pathPrefixes :: FilePath -> [FilePath]
pathPrefixes = filter (not . null) . scanl (</>) "" . splitDirectories

exactMembers :: FilePath -> [FilePath] -> IO ()
exactMembers directory expected = do
  canonicalDirectory directory
  actual <-
    bracket (Directory.openDirStream directory) Directory.closeDirStream (collect (length expected) [])
  ioRequire (sort actual == sort expected) "native retained directory has missing or foreign members"
 where
  collect remaining actual stream = do
    entry <- Directory.readDirStream stream
    if null entry
      then pure actual
      else
        if entry == "." || entry == ".."
          then collect remaining actual stream
          else do
            ioRequire (remaining > 0) "native retained directory exceeds exact member bound"
            collect (remaining - 1) (entry : actual) stream

ioRequire :: Bool -> String -> IO ()
ioRequire predicate reason = unless predicate (ioError (userError reason))
hex :: ByteString -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack

stage :: IORef NativeScenarioRetentionStage -> NativeScenarioRetentionStage -> Program ()
stage progress = liftIO . writeIORef progress
require :: Bool -> Text -> Program ()
require predicate reason = unless predicate (throwError reason)
checked :: Either Text a -> Program a
checked = either throwError pure
checkedCodec :: (Show e) => Either e a -> Program a
checkedCodec = checked . mapLeft (Text.pack . show)

-- | Ordinary original reservation DATA only; no reserved handle or authority.
nativeScenarioRecordedIssuedBytes
  :: Cohort.NativeRlCohortPlan -> Receipt.NativeScenarioReceiptData -> Either Text ByteString
nativeScenarioRecordedIssuedBytes = originalIssuedRecord

-- | Exact successful original raw-stream availability DATA.
nativeScenarioRecordedRawAvailabilityBytes :: ByteString
nativeScenarioRecordedRawAvailabilityBytes =
  Wire.encodeStrict
    ( CBOR.encodeListLen 4
        <> CBOR.encodeString "jitml-native-parent-raw-availability-v1"
        <> CBOR.encodeWord 1
        <> CBOR.encodeBool True
        <> CBOR.encodeBool True
    )

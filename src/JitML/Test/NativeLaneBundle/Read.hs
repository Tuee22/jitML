{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Actual portable FILE audit of an externally pinned historical Lane root.
-- Success is a private recorded-bundle audit, never live Store or RootOwned.
module JitML.Test.NativeLaneBundle.Read
  ( NativeBundleAudit
  , readNativeLaneBundle
  , nativeBundleAuditMainSha256
  , nativeBundleAuditReference
  , nativeBundleAuditRoot
  , nativeBundleAuditCompleted
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (foldM, foldM_, unless, (>=>))
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Combinators (mapLeft)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Execution.NativeParentAttemptRetention qualified as Attempt
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Test.NativeLaneBundle.Data
import JitML.Test.NativeLaneBundle.Recorded qualified as Recorded
import JitML.Test.NativeLaneBundle.Write qualified as Files
import JitML.Test.NativeScenarioReceiptData qualified as Receipt
import JitML.Test.NativeScenarioRetention qualified as Retained
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as Training

data NativeBundleAudit
  = NativeBundleAudit
      !Text
      !NativeBundleReferenceData
      !NativeBundleRootData
      !Training.CompletedTraining
  deriving stock (Eq, Show)
nativeBundleAuditMainSha256 :: NativeBundleAudit -> Text
nativeBundleAuditMainSha256 (NativeBundleAudit value _ _ _) = value
nativeBundleAuditReference :: NativeBundleAudit -> NativeBundleReferenceData
nativeBundleAuditReference (NativeBundleAudit _ value _ _) = value
nativeBundleAuditRoot :: NativeBundleAudit -> NativeBundleRootData
nativeBundleAuditRoot (NativeBundleAudit _ _ value _) = value
nativeBundleAuditCompleted :: NativeBundleAudit -> Training.CompletedTraining
nativeBundleAuditCompleted (NativeBundleAudit _ _ _ value) = value

type Program = ExceptT Text IO
type Expected = (NativeBundleObjectData, Integer)

-- Lane must first validate its current canonical main wire and the reference's
-- exact row. This reader additionally binds the same original main bytes/pin.
-- The raw pin is DATA; only registered production pins supply provenance.
readNativeLaneBundle
  :: FilePath
  -> Text
  -> ByteString
  -> NativeBundleReferenceData
  -> Matrix.ProductProjection kind
  -> IO (Either Failure.NativeDiagnosticData NativeBundleAudit)
readNativeLaneBundle journalPath mainSha mainBytes reference projection = do
  attempted <- tryAny (runExceptT (program journalPath mainSha mainBytes reference projection))
  case attempted of
    Left exception -> Left <$> Failure.captureNativeExceptionDiagnostic exception
    Right (Left reason) -> Left <$> Failure.captureNativeDiagnostic reason
    Right (Right value) -> pure (Right value)

program
  :: FilePath
  -> Text
  -> ByteString
  -> NativeBundleReferenceData
  -> Matrix.ProductProjection kind
  -> Program NativeBundleAudit
program journalPath mainSha mainBytes reference projection = do
  let prefix = take 4097 journalPath
  require (length prefix <= 4096) "portable Lane journal path exceeds its preflight"
  _ <- liftIO (evaluate projection)
  _ <- codec (nativeBundleObjectBasename mainSha)
  _ <- codec (renderNativeBundleReferenceData reference)
  require (sha256Hex mainBytes == mainSha) "portable Lane main bytes differ from external pin"
  let directory = prefix <> ".qualifications"
      rootObject =
        NativeBundleObjectData
          "native-lane-bundle-root"
          (nativeBundleReferenceSha256 reference)
          (nativeBundleReferenceBytes reference)
  rootBytes <-
    liftIO (Files.readNativeBundleObjectBytes directory rootObject maximumNativeBundleRootBytes)
  root <- codec (decodeNativeBundleRootData rootBytes)
  let receipt = nativeBundleReceipt root
      referenceData = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference receipt)
      objects = Map.fromList [(nativeBundleObjectKey object, object) | object <- nativeBundleObjects root]
      experiment = Reference.nativeReferenceExperiment referenceData
      manifestSha = Reference.nativeReferenceManifest referenceData
      limits = Store.nativeRecordedCheckpointLimits
  checked
    (Report.checkNativeRecordedScenarioBindingData projection (nativeBundleBinding root) receipt)
  metadataObject <-
    expected
      objects
      (Reference.nativeReferenceObjectKey referenceData)
      (Reference.nativeReferenceArtifact referenceData)
      (Just (toInteger (Reference.nativeReferenceObjectBytes referenceData)))
      Metadata.maximumNativeQualificationReceiptBytes
  metadataBytes <- readExpected directory metadataObject
  metadata <- codec (Metadata.decodeNativeQualificationReceiptData metadataBytes)
  let fields = Metadata.nativeQualificationReceiptFields metadata
      detached =
        Metadata.nativeReceiptAllocation fields
          : Metadata.nativeReceiptPhases fields
            <> map Metadata.nativeReceiptReplayObject (Metadata.nativeReceiptReplays fields)
  detachedObjects <- traverse (retainedExpected objects) detached
  foldM_ reservation (toInteger (BS.length metadataBytes)) detachedObjects
  manifestObject <-
    keyExpected
      objects
      (Format.manifestKey experiment manifestSha)
      manifestSha
      (Store.recordedManifestByteLimit limits)
  manifestBytes <- readExpected directory manifestObject
  preliminary <- checked (Format.decodeManifestCbor (LBS.fromStrict manifestBytes))
  snapshot <-
    checked (Store.checkpointStorageSnapshotId preliminary)
      >>= maybe (throwError "portable native manifest has no exact snapshot") pure
  let commitKey = "jitml-checkpoints/" <> experiment <> "/snapshots/" <> snapshot <> "/committed.cbor"
  commitObject <- anyExpected objects commitKey (Store.recordedCommitByteLimit limits)
  commitBytes <- readExpected directory commitObject
  (manifest, commit) <-
    checked
      ( Store.checkNativeRecordedSnapshotCommitData
          experiment
          manifestSha
          (LBS.fromStrict manifestBytes)
          commitBytes
      )
  payloadObjects <- snapshotExpected objects limits manifest commit
  originalFiles <- attemptExpected objects receipt
  assets <- assetExpected objects receipt
  expectedMap <-
    foldM
      insertExpected
      Map.empty
      ( metadataObject
          : manifestObject
          : commitObject
          : detachedObjects <> payloadObjects <> originalFiles <> assets
      )
  require
    (Map.keys expectedMap == Map.keys objects)
    "portable native root has a missing or foreign physical file"
  -- Stream every exact role before loading graph/snapshot buffers. Parent
  -- report/raw and executable/artifacts NEVER enter the strict payload map.
  liftIO
    ( mapM_
        (\pair -> pair `seq` uncurry (Files.verifyNativeBundleObjectFile directory) pair)
        (Map.elems expectedMap)
    )
  allocationBytes <-
    readExpected directory =<< retainedExpected objects (Metadata.nativeReceiptAllocation fields)
  phaseBytes <-
    traverse
      (retainedExpected objects >=> readExpected directory)
      (Metadata.nativeReceiptPhases fields)
  replayBytes <-
    traverse
      ( \item ->
          retainedExpected objects (Metadata.nativeReceiptReplayObject item)
            >>= readExpected directory
      )
      (Metadata.nativeReceiptReplays fields)
  payloads <-
    traverse
      (\item@(object, _) -> (,) (nativeBundleObjectKey object) <$> readExpected directory item)
      payloadObjects
  (actualManifest, _actualCommit, weights, completed, recordedTrace) <-
    checked
      ( Store.checkNativeRecordedCheckpointPayloadData
          experiment
          manifestSha
          (LBS.fromStrict manifestBytes)
          commitBytes
          payloads
      )
  require (actualManifest == manifest) "portable native recorded manifest changed across checks"
  batch <- checked (Cohort.mkCanonicalNativeRlCohorts (Matrix.productProjectionSubstrate projection))
  let request = Receipt.nativeScenarioReceiptRequest receipt
      invocation = Parent.nativeParentRequestInvocation request
  binding <-
    checked
      ( Binding.checkNativeParentBindingData
          batch
          (Matrix.productProjectionRowId projection)
          ( Binding.NativeParentExpectedData
              (Parent.nativeParentRequestSource request)
              (Reference.nativeReferenceExecutable referenceData)
              invocation
              manifestSha
              (Training.encodeCompletedTraining completed)
          )
          (Receipt.nativeScenarioReceiptReference receipt)
          (Binding.NativeParentPayloadData metadataBytes allocationBytes phaseBytes replayBytes)
      )
  codec (Recorded.checkRecordedEvaluationClosure batch receipt binding)
  traceCheck <- liftIO (Recorded.checkRecordedServingTrace receipt binding recordedTrace)
  codec traceCheck
  case weights of
    [one] -> codec (Recorded.checkRecordedServingWeights binding (Store.loadedWeightJmw1Bytes one))
    _ -> throwError "portable native snapshot has no unique exact final JMW1"
  cohort <-
    maybe
      (throwError "portable original issued row is absent")
      pure
      ( find
          ((== Matrix.productProjectionRowId projection) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  issued <-
    readExpected directory
      =<< findAttempt
        objects
        receipt
        "issued.cbor"
        (Attempt.nativeParentAttemptIssuedFile (Receipt.nativeScenarioReceiptAttemptInventory receipt))
        65536
  availability <-
    readExpected directory
      =<< findAttempt
        objects
        receipt
        "availability.cbor"
        (Attempt.nativeParentAttemptAvailabilityFile (Receipt.nativeScenarioReceiptAttemptInventory receipt))
        4096
  expectedIssued <- checked (Retained.nativeScenarioRecordedIssuedBytes cohort receipt)
  require
    ( issued == expectedIssued
        && availability == Retained.nativeScenarioRecordedRawAvailabilityBytes
    )
    "portable original issued or raw availability DATA differs"
  pure (NativeBundleAudit mainSha reference root completed)

snapshotExpected
  :: Map.Map Text NativeBundleObjectData
  -> Store.NativeRecordedCheckpointLimits
  -> Format.CheckpointManifest
  -> Store.WriterCommit
  -> Program [Expected]
snapshotExpected objects limits manifest commit = do
  _ <- codec (boundedLength AggregateSequenceElements 3 (Store.writerCommitPhysicalObjects commit))
  tensor <- case Format.manifestTensors manifest of
    [value] -> pure value
    _ -> throwError "portable native snapshot lacks one final tensor"
  companion <- case Format.manifestTranscriptPointers manifest of
    [value] -> pure value
    _ -> throwError "portable native snapshot lacks one exact companion"
  replay <- case Format.manifestReplayPointers manifest of
    [] -> pure []
    [value] -> pure [(Format.artifactPointerObjectKey value, Store.recordedArsTraceByteLimit limits)]
    _ -> throwError "portable native snapshot has an unsupported replay inventory"
  let roles =
        [ (Format.tensorBlobKey tensor, Store.recordedTensorByteLimit limits)
        , (Format.artifactPointerObjectKey companion, Store.recordedCompanionByteLimit limits)
        ]
          <> replay
      physical = Store.writerCommitPhysicalObjects commit
      actualKeys =
        Map.fromList
          [(Store.writerPhysicalObjectKey value, Store.writerPhysicalObjectSha value) | value <- physical]
  require
    (Map.size actualKeys == length physical && Map.keys actualKeys == Map.keys (Map.fromList roles))
    "portable native snapshot roles differ from complete actual commit"
  traverse
    ( \(key, cap) -> do
        sha <- maybe (throwError "portable native commit role is absent") pure (Map.lookup key actualKeys)
        keyExpected objects key sha cap
    )
    roles

attemptExpected
  :: Map.Map Text NativeBundleObjectData -> Receipt.NativeScenarioReceiptData -> Program [Expected]
attemptExpected objects receipt = do
  let inventory = Receipt.nativeScenarioReceiptAttemptInventory receipt
      one leaf cap file = findAttempt objects receipt leaf file cap
  mandatory <-
    sequence
      [ one "issued.cbor" 65536 (Attempt.nativeParentAttemptIssuedFile inventory)
      , one "report.utf8" 4294967296 (Attempt.nativeParentAttemptReportFile inventory)
      , one "availability.cbor" 4096 (Attempt.nativeParentAttemptAvailabilityFile inventory)
      ]
  streams <- case (Attempt.nativeParentAttemptStdoutFile inventory, Attempt.nativeParentAttemptStderrFile inventory) of
    (Just stdoutFile, Just stderrFile) ->
      sequence
        [one "stdout.bin" 1073741824 stdoutFile, one "stderr.bin" 1073741824 stderrFile]
    _ -> throwError "portable original successful attempt lacks both raw streams"
  pure (mandatory <> streams)

findAttempt
  :: Map.Map Text NativeBundleObjectData
  -> Receipt.NativeScenarioReceiptData
  -> Text
  -> Attempt.NativeParentAttemptFileData
  -> Integer
  -> Program Expected
findAttempt objects receipt leaf file =
  expected
    objects
    ("native-parent-attempts-v1/" <> Receipt.nativeScenarioReceiptAttemptScope receipt <> "/" <> leaf)
    (Attempt.nativeParentAttemptFileSha256 file)
    (Just (toInteger (Attempt.nativeParentAttemptFileBytes file)))

assetExpected
  :: Map.Map Text NativeBundleObjectData -> Receipt.NativeScenarioReceiptData -> Program [Expected]
assetExpected objects receipt = do
  let reference = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference receipt)
      devices =
        [ Witness.rawWitnessArtifactSha256 device
        | item <- Summary.parentSummaryMatches (Receipt.nativeScenarioReceiptEvaluationSummary receipt)
        , Just device <- [Summary.parentSummaryDevice item]
        ]
  traverse one (Reference.nativeReferenceExecutable reference : devices)
 where
  one sha = do
    item@(object, _) <-
      keyExpected objects ("native-qualified-assets-v1/" <> sha <> ".bin") sha 1073741824
    require (nativeBundleObjectBytes object > 0) "portable original executable/device artifact is empty"
    pure item

reservation :: Integer -> Expected -> Program Integer
reservation total (object, _) = do
  let next = total + toInteger (nativeBundleObjectBytes object)
  require (next <= 4294967296) "portable complete detached graph reservation exceeds4GiB"
  pure next

readExpected :: FilePath -> Expected -> Program ByteString
readExpected directory (object, cap) = liftIO (Files.readNativeBundleObjectBytes directory object cap)
retainedExpected
  :: Map.Map Text NativeBundleObjectData -> Retain.NativeRetainedObjectData -> Program Expected
retainedExpected objects reference =
  expected
    objects
    (Retain.nativeRetainedObjectKey reference)
    (Retain.nativeRetainedObjectSha256 reference)
    (Just (toInteger (Retain.nativeRetainedObjectBytes reference)))
    (toInteger Retain.maximumNativeRetentionPayloadBytes + 4096)
keyExpected :: Map.Map Text NativeBundleObjectData -> Text -> Text -> Integer -> Program Expected
keyExpected objects key sha = expected objects key sha Nothing
anyExpected :: Map.Map Text NativeBundleObjectData -> Text -> Integer -> Program Expected
anyExpected objects key cap = do
  value <- maybe (throwError "portable required object key is absent") pure (Map.lookup key objects)
  expected objects key (nativeBundleObjectSha256 value) Nothing cap
expected
  :: Map.Map Text NativeBundleObjectData -> Text -> Text -> Maybe Integer -> Integer -> Program Expected
expected objects key sha count cap = do
  value <- maybe (throwError "portable required object key is absent") pure (Map.lookup key objects)
  require
    ( nativeBundleObjectSha256 value == sha
        && maybe True (== toInteger (nativeBundleObjectBytes value)) count
        && toInteger (nativeBundleObjectBytes value) <= cap
    )
    "portable object digest/count differs or exceeds its exact role cap"
  pure (value, cap)
insertExpected :: Map.Map Text Expected -> Expected -> Program (Map.Map Text Expected)
insertExpected values item@(object, cap) = case Map.lookup (nativeBundleObjectKey object) values of
  Nothing -> pure (Map.insert (nativeBundleObjectKey object) item values)
  Just (previous, previousCap) -> do
    require (object == previous) "portable duplicate physical role has conflicting bytes"
    pure (Map.insert (nativeBundleObjectKey object) (object, min cap previousCap) values)

require :: Bool -> Text -> Program ()
require condition message = unless condition (throwError message)
checked :: Either Text a -> Program a
checked = either throwError pure
codec :: (Show error) => Either error a -> Program a
codec = checked . mapLeft (Text.pack . show)

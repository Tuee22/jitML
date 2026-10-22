{-# LANGUAGE OverloadedStrings #-}

-- | Actual parent-side local/configured-remote bytes only. Parent explicit
-- filesystem resolution remains distinct from the recorded child default
-- resolution. No child session/ACK, source observation, stage, numerical
-- policy, authenticated attempt or qualification is restored from DATA.
module JitML.Checkpoint.NativeParentPhysicalRead
  ( NativeParentPhysicalPayloads
  , NativeParentReadFailure
  , NativeParentReadStage (..)
  , NativeParentReadReport (..)
  , NativeParentObjectReadData (..)
  , readNativeParentQualificationPayloads
  , nativeParentPhysicalPayloads
  , nativeParentPhysicalCheckpoint
  , nativeParentPhysicalAdmitted
  , nativeParentPhysicalReport
  , nativeParentReadFailureReport
  , nativeParentDefaultPublicationViewData
  , maximumNativeParentReadBytes
  , nativeParentReadReservationData
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (foldM, unless)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Trans.Class (lift)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Directory (canonicalizePath)
import System.FilePath ((</>))

import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (AggregateSequenceElements), boundedLength)
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Env (App)
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Service.WorkerPublication qualified as Worker

data NativeParentReadStage
  = ParentReadInput
  | ParentReadCaptureBefore
  | ParentReadMetadata
  | ParentReadAllocation
  | ParentReadPhase !Int
  | ParentReadReplay !Int
  | ParentReadCheckpoint
  | ParentReadCaptureAfter
  | ParentReadFinished
  deriving stock (Eq, Show)

-- Both descriptors are retained. A read under actual parent explicit paths
-- never becomes an original child default-session physical-read capsule.
data NativeParentObjectReadData = NativeParentObjectReadData
  { parentReadOriginalReference :: !Retain.NativeRetainedObjectData
  , parentReadActualReference :: !Retain.NativeRetainedObjectData
  }
  deriving stock (Eq, Show)

data NativeParentReadReport = NativeParentReadReport
  { parentReadStage :: !NativeParentReadStage
  , parentReadBeforePublication :: !(Maybe Retain.NativePublicationData)
  , parentReadAfterPublication :: !(Maybe Retain.NativePublicationData)
  , parentReadChildDefaultView :: !(Maybe Retain.NativePublicationData)
  , parentReadActualObjects :: ![NativeParentObjectReadData]
  , parentReadPhysicalFailure :: !(Maybe Retain.NativePhysicalReadFailure)
  , parentReadCaptureFailure :: !(Maybe Retain.NativeRetentionFailure)
  , parentReadRefusal :: !(Maybe Text)
  , parentReadDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)

data NativeParentPhysicalPayloads
  = NativeParentPhysicalPayloads
      !Binding.NativeParentPayloadData
      !Retain.NativeReadCheckpoint
      !NativeParentReadReport
newtype NativeParentReadFailure = NativeParentReadFailure NativeParentReadReport

nativeParentPhysicalPayloads :: NativeParentPhysicalPayloads -> Binding.NativeParentPayloadData
nativeParentPhysicalPayloads (NativeParentPhysicalPayloads actual _ _) = actual
nativeParentPhysicalCheckpoint :: NativeParentPhysicalPayloads -> Retain.NativeReadCheckpoint
nativeParentPhysicalCheckpoint (NativeParentPhysicalPayloads _ actual _) = actual
nativeParentPhysicalAdmitted :: NativeParentPhysicalPayloads -> Store.AdmittedExecutionCheckpoint
nativeParentPhysicalAdmitted = Retain.nativeReadCheckpointEffective . nativeParentPhysicalCheckpoint
nativeParentPhysicalReport :: NativeParentPhysicalPayloads -> NativeParentReadReport
nativeParentPhysicalReport (NativeParentPhysicalPayloads _ _ actual) = actual
nativeParentReadFailureReport :: NativeParentReadFailure -> NativeParentReadReport
nativeParentReadFailureReport (NativeParentReadFailure actual) = actual

emptyReport :: NativeParentReadReport
emptyReport = NativeParentReadReport ParentReadInput Nothing Nothing Nothing [] Nothing Nothing Nothing Nothing
type Program = ExceptT Text App

-- Ordinary comparison view, never a session/settings/reader/cursor factory.
-- Actual parent path resolution is retained separately in the report. Only
-- explicit parent observations can supply the default-child comparison view.
nativeParentDefaultPublicationViewData
  :: Retain.NativePublicationData -> Either Text Retain.NativePublicationData
nativeParentDefaultPublicationViewData value = case value of
  Retain.NativeLocalPublication (Retain.NativeExplicitPublicationResolution _) root ->
    Right (Retain.NativeLocalPublication Retain.NativeDefaultPublicationResolution root)
  Retain.NativeConfiguredPublication
    (Retain.NativeExplicitPublicationResolution _)
    root
    endpoint
    mounted ->
      Right
        (Retain.NativeConfiguredPublication Retain.NativeDefaultPublicationResolution root endpoint mounted)
  _ -> Left "parent read requires its own explicit filesystem publication observation"

-- A separate parent read reservation, fixed before fetching the referenced
-- detached/acquisition payloads. This bounds only their raw metadata, claim,
-- phase and replay buffers. General Store checkpoint/completion/JMW1 buffers
-- are separate and excluded. No measured heap or remote streaming allocation
-- bound is claimed, and no numerical budget changes.
maximumNativeParentReadBytes :: Integer
maximumNativeParentReadBytes = 4 * 1024 * 1024 * 1024

nativeParentReadReservationData :: [Word64] -> Either Text Integer
nativeParentReadReservationData counts = do
  _ <- mapLeft (Text.pack . show) (boundedLength AggregateSequenceElements 141 counts)
  foldM add 0 counts
 where
  add total count = do
    let next = total + toInteger count
    unless
      (next <= maximumNativeParentReadBytes)
      (Left "parent complete physical payload reservation exceeds4GiB")
    pure next

-- The caller's actual Env cache MUST be the canonical child's .build. The
-- fixed boot config and child-root live publication are resolved from actual
-- files, with RequireLive; no child endpoint/settings/callback is accepted.
-- HasMinIO is strict: its network allocation precedes post-read count/hash
-- checks. Local reads retain their existing count+1-before-strict bounds.
readNativeParentQualificationPayloads
  :: FilePath
  -> Reference.NativeQualificationReference
  -> App (Either NativeParentReadFailure NativeParentPhysicalPayloads)
readNativeParentQualificationPayloads childWorkdir reference = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    attempted <- tryAny (runReaderT (runExceptT (program report childWorkdir reference)) env)
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \actual ->
              actual
                { parentReadRefusal = Just "synchronous parent physical read failure"
                , parentReadDiagnostic = Just diagnostic
                }
          )
        Left . NativeParentReadFailure <$> readIORef report
      Right (Left reason) -> do
        diagnostic <- Failure.captureNativeDiagnostic reason
        modifyIORef'
          report
          (\actual -> actual {parentReadRefusal = Just reason, parentReadDiagnostic = Just diagnostic})
        Left . NativeParentReadFailure <$> readIORef report
      Right (Right (payload, checkpoint)) -> do
        actual <- readIORef report
        pure (Right (NativeParentPhysicalPayloads payload checkpoint actual))

program
  :: IORef NativeParentReadReport
  -> FilePath
  -> Reference.NativeQualificationReference
  -> Program (Binding.NativeParentPayloadData, Retain.NativeReadCheckpoint)
program report childWorkdir reference = do
  _ <- liftIO (evaluate reference)
  _ <- liftIO (evaluate (length childWorkdir))
  let raw = Reference.nativeQualificationReferenceData reference
  require
    (Reference.nativeReferenceBinding raw == Reference.NativeReferenceScenario)
    "parent physical reader requires the scenario receipt alternative"
  child <- liftIO (canonicalizePath childWorkdir)
  root <- lift Writer.localCheckpointRoot
  actualRoot <- liftIO (canonicalizePath root)
  require
    (actualRoot == child </> ".build" </> "checkpoints")
    "parent actual cache root differs from canonical child checkpoint root"
  stage report ParentReadCaptureBefore
  session <- capture report child
  let before = Retain.nativeRetentionPublication session
  update report (\actual -> actual {parentReadBeforePublication = Just before})
  childView <- checked (nativeParentDefaultPublicationViewData before)
  update report (\actual -> actual {parentReadChildDefaultView = Just childView})
  require
    (Retain.nativePublicationDigest childView == Reference.nativeReferencePublication raw)
    "recorded child default publication differs from actual parent root endpoint or mounted context"
  let metadataObject =
        Retain.NativeRetainedObjectData
          (Reference.nativeReferenceObjectKey raw)
          (Reference.nativeReferenceArtifact raw)
          (Reference.nativeReferenceObjectBytes raw)
          childView
  stage report ParentReadMetadata
  metadataBytes <- readDetached report session Retain.NativeQualificationArtifact metadataObject
  metadata <-
    either
      (const (throwError "actual parent metadata decode refused"))
      pure
      (Metadata.decodeNativeQualificationReceiptData metadataBytes)
  let fields = Metadata.nativeQualificationReceiptFields metadata
  require
    (Metadata.nativeReceiptPublication fields == childView)
    "actual metadata full child descriptor differs from independently observed parent default view"
  _ <-
    checked
      ( nativeParentReadReservationData
          ( fromIntegral (BS.length metadataBytes)
              : map
                Retain.nativeRetainedObjectBytes
                ( Metadata.nativeReceiptAllocation fields
                    : Metadata.nativeReceiptPhases fields
                      <> map Metadata.nativeReceiptReplayObject (Metadata.nativeReceiptReplays fields)
                )
          )
      )
  stage report ParentReadAllocation
  allocation <- readPhase report session (Metadata.nativeReceiptAllocation fields)
  phases <-
    traverse
      (\(index, object) -> stage report (ParentReadPhase index) >> readPhase report session object)
      (zip [0 ..] (Metadata.nativeReceiptPhases fields))
  replays <-
    traverse
      ( \(index, object) -> do
          stage report (ParentReadReplay index)
          let kind = case Metadata.nativeReceiptReplayStage object of
                Replay.StoredFinalModelReplay -> Retain.NativeStoreLoadedReplayArtifact
                _ -> Retain.NativeEvaluationReplayArtifact
          readDetached report session kind (Metadata.nativeReceiptReplayObject object)
      )
      (zip [0 ..] (Metadata.nativeReceiptReplays fields))
  -- The same actual parent session admits BOTH the local addressed checkpoint
  -- and its configured remote counterpart, comparing complete completion and
  -- actual tensor bytes through Retain. This is never a child read/ACK capsule.
  stage report ParentReadCheckpoint
  checkpointResult <-
    liftIO
      ( Retain.readNativeExecutionCheckpoint
          session
          (Reference.nativeReferenceExperiment raw)
          (Reference.nativeReferenceManifest raw)
      )
  checkpoint <- case checkpointResult of
    Left failure -> physicalFailure report failure
    Right actual -> pure actual
  require
    (Retain.nativeReadCheckpointPublication checkpoint == before)
    "actual parent addressed checkpoint used a different captured publication"
  stage report ParentReadCaptureAfter
  afterSession <- capture report child
  let after = Retain.nativeRetentionPublication afterSession
  update report (\actual -> actual {parentReadAfterPublication = Just after})
  require (after == before) "actual parent publication changed during complete physical acquisition"
  stage report ParentReadFinished
  pure (Binding.NativeParentPayloadData metadataBytes allocation phases replays, checkpoint)

-- Only publication DATA is rebound for the actual explicit parent read. Key,
-- count and SHA remain original. Original-envelope decoders subsequently use
-- ORIGINAL references, never the parent's separately recorded physical cap.
readPhase
  :: IORef NativeParentReadReport
  -> Retain.NativeRetentionSession
  -> Retain.NativeRetainedObjectData
  -> Program ByteString
readPhase report session original = do
  actual <- readReference session original
  outcome <- liftIO (Retain.readNativeRetainedObject session actual)
  case outcome of
    Left failure -> physicalFailure report failure
    Right value -> do
      require
        (Retain.nativeReadObjectReference value == actual)
        "actual parent phase reader returned another reference"
      observed report original actual
      pure (Retain.nativeReadObjectBytes value)

readDetached
  :: IORef NativeParentReadReport
  -> Retain.NativeRetentionSession
  -> Retain.NativeDetachedArtifactKind
  -> Retain.NativeRetainedObjectData
  -> Program ByteString
readDetached report session kind original = do
  actual <- readReference session original
  outcome <- liftIO (Retain.readNativeDetachedArtifact session kind actual)
  case outcome of
    Left failure -> physicalFailure report failure
    Right value -> do
      require
        ( Retain.nativeReadDetachedArtifactReference value == actual
            && Retain.nativeReadDetachedArtifactKind value == kind
        )
        "actual parent detached reader returned another reference or kind"
      observed report original actual
      pure (Retain.nativeReadDetachedArtifactBytes value)

readReference
  :: Retain.NativeRetentionSession
  -> Retain.NativeRetainedObjectData
  -> Program Retain.NativeRetainedObjectData
readReference session original = do
  let actual = Retain.nativeRetentionPublication session
  childView <- checked (nativeParentDefaultPublicationViewData actual)
  require
    (Retain.nativeRetainedObjectPublication original == childView)
    "original object publication differs from independently observed child default view"
  pure original {Retain.nativeRetainedObjectPublication = actual}

capture :: IORef NativeParentReadReport -> FilePath -> Program Retain.NativeRetentionSession
capture report child = do
  outcome <-
    lift
      ( Retain.captureNativeRetentionSessionAt
          Retain.RequireLiveNativeRetention
          Worker.workerServiceBootConfigPath
          child
      )
  case outcome of
    Right actual -> pure actual
    Left failure -> do
      update report (\actual -> actual {parentReadCaptureFailure = Just failure})
      throwError "actual parent live publication capture refused"

physicalFailure :: IORef NativeParentReadReport -> Retain.NativePhysicalReadFailure -> Program a
physicalFailure report failure = do
  update report (\actual -> actual {parentReadPhysicalFailure = Just failure})
  throwError "actual parent physical object read refused"

observed
  :: IORef NativeParentReadReport
  -> Retain.NativeRetainedObjectData
  -> Retain.NativeRetainedObjectData
  -> Program ()
observed report original actual =
  update
    report
    ( \value ->
        value
          { parentReadActualObjects =
              parentReadActualObjects value <> [NativeParentObjectReadData original actual]
          }
    )
stage :: IORef NativeParentReadReport -> NativeParentReadStage -> Program ()
stage report value = update report (\actual -> actual {parentReadStage = value})
update
  :: IORef NativeParentReadReport -> (NativeParentReadReport -> NativeParentReadReport) -> Program ()
update report = liftIO . modifyIORef' report
require :: Bool -> Text -> Program ()
require condition reason = unless condition (throwError reason)
checked :: Either Text a -> Program a
checked = either throwError pure

{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Actual CHILD metadata publication only. No parent authentication,
-- source/build coherence, journal admission or independent-policy authority
-- is established. A parsed reference or ordinary DATA cannot mint this cap.
module JitML.Product.NativeQualificationPublication
  ( NativeQualificationPublication
  , NativeQualificationPublicationFailure
  , NativeQualificationStage (..)
  , NativeQualificationFinding (..)
  , NativeQualificationPublicationReport (..)
  , publishNativeQualification
  , nativeQualificationPublicationReplays
  , nativeQualificationPublicationMetadata
  , nativeQualificationPublicationPhysical
  , nativeQualificationPublicationReference
  , nativeQualificationPublicationArtifact
  , nativeQualificationPublicationReport
  , nativeQualificationPublicationFailureReport
  ) where

import Control.Exception (Exception, evaluate, toException)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, void)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Trans.Class (lift)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (CodecError, Digest, digestBytes)
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReplayObjectData qualified as ReplayData
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.NativeRetentionReader qualified as Envelope
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Env (App)
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeReferenceCalibration qualified as References
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlCompletedServing qualified as Completed
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlReplayRetention qualified as Retained
import JitML.Product.NativeRlServingCandidate qualified as Candidate
import JitML.Product.NativeRlStoredServing qualified as Stored
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Training.Budget qualified as Training

data NativeQualificationStage
  = QualificationInput
  | QualificationCaptureBefore
  | QualificationMetadata
  | QualificationWrite
  | QualificationPhysicalRead
  | QualificationDecode
  | QualificationReference
  | QualificationCaptureAfter
  | QualificationFinished
  deriving stock (Eq, Show)
data NativeQualificationFinding
  = QualificationBindingRefused
  | QualificationCaptureRefused
  | QualificationPublicationDiffers
  | QualificationMetadataRefused
  | QualificationWriteReceiptDiffers
  | QualificationNotMirrored
  | QualificationPhysicalRefused
  | QualificationDecodeRefused
  | QualificationReferenceRefused
  | QualificationSynchronousFailure
  deriving stock (Eq, Show)

data NativeQualificationPublicationReport = NativeQualificationPublicationReport
  { qualificationStage :: !NativeQualificationStage
  , qualificationBeforePublication :: !(Maybe Retain.NativePublicationData)
  , qualificationAfterPublication :: !(Maybe Retain.NativePublicationData)
  , qualificationWrittenObject :: !(Maybe Retain.NativeRetainedObjectData)
  , qualificationCaptureFailure :: !(Maybe Retain.NativeRetentionFailure)
  , qualificationPhysicalFailure :: !(Maybe Retain.NativePhysicalReadFailure)
  , qualificationFinding :: !(Maybe NativeQualificationFinding)
  , qualificationDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)

data NativeQualificationPublication
  = NativeQualificationPublication
      !Retained.NativeRetainedServingReplays
      !Metadata.NativeQualificationReceiptData
      !Retain.NativeReadDetachedArtifact
      !Reference.NativeQualificationReference
      !Writer.StoredArtifact
      !NativeQualificationPublicationReport
newtype NativeQualificationPublicationFailure
  = NativeQualificationPublicationFailure NativeQualificationPublicationReport

nativeQualificationPublicationReplays
  :: NativeQualificationPublication -> Retained.NativeRetainedServingReplays
nativeQualificationPublicationReplays (NativeQualificationPublication value _ _ _ _ _) = value
nativeQualificationPublicationMetadata
  :: NativeQualificationPublication -> Metadata.NativeQualificationReceiptData
nativeQualificationPublicationMetadata (NativeQualificationPublication _ value _ _ _ _) = value
nativeQualificationPublicationPhysical
  :: NativeQualificationPublication -> Retain.NativeReadDetachedArtifact
nativeQualificationPublicationPhysical (NativeQualificationPublication _ _ value _ _ _) = value
nativeQualificationPublicationReference
  :: NativeQualificationPublication -> Reference.NativeQualificationReference
nativeQualificationPublicationReference (NativeQualificationPublication _ _ _ value _ _) = value
nativeQualificationPublicationArtifact :: NativeQualificationPublication -> Writer.StoredArtifact
nativeQualificationPublicationArtifact (NativeQualificationPublication _ _ _ _ value _) = value
nativeQualificationPublicationReport
  :: NativeQualificationPublication -> NativeQualificationPublicationReport
nativeQualificationPublicationReport (NativeQualificationPublication _ _ _ _ _ value) = value
nativeQualificationPublicationFailureReport
  :: NativeQualificationPublicationFailure -> NativeQualificationPublicationReport
nativeQualificationPublicationFailureReport (NativeQualificationPublicationFailure value) = value

emptyReport :: NativeQualificationPublicationReport
emptyReport =
  NativeQualificationPublicationReport
    QualificationInput
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
type Program = ExceptT NativeQualificationFinding App

-- No receipt/source/weights/completion/reference/ACK/evaluator/Writer or
-- fetcher replacement is accepted. All effects run in the same actual Env.
publishNativeQualification
  :: Retained.NativeRetainedServingReplays
  -> App (Either NativeQualificationPublicationFailure NativeQualificationPublication)
publishNativeQualification retained = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    attempted <- tryAny (runReaderT (runExceptT (program report retained)) env)
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \value ->
              value
                { qualificationFinding = Just QualificationSynchronousFailure
                , qualificationDiagnostic = Just diagnostic
                }
          )
        Left . NativeQualificationPublicationFailure <$> readIORef report
      Right (Left finding) -> do
        modifyIORef' report (\value -> value {qualificationFinding = Just finding})
        Left . NativeQualificationPublicationFailure <$> readIORef report
      Right (Right (metadata, physical, reference, written)) -> do
        final <- readIORef report
        pure (Right (NativeQualificationPublication retained metadata physical reference written final))

program
  :: IORef NativeQualificationPublicationReport
  -> Retained.NativeRetainedServingReplays
  -> Program
       ( Metadata.NativeQualificationReceiptData
       , Retain.NativeReadDetachedArtifact
       , Reference.NativeQualificationReference
       , Writer.StoredArtifact
       )
program report retained = do
  _ <- liftIO (evaluate retained)
  facts@(PublicationFacts fields _ _ _ _ mode) <- checkedBinding report (deriveFacts retained)
  let originalPublication = Metadata.nativeReceiptPublication fields
      experiment = Metadata.nativeReceiptExperiment fields
  stage report QualificationCaptureBefore
  session <- capture report mode
  let before = Retain.nativeRetentionPublication session
  liftIO $
    forcePublication before
      >> modifyIORef' report (\value -> value {qualificationBeforePublication = Just before})
  require QualificationPublicationDiffers (before == originalPublication)
  stage report QualificationMetadata
  metadata <-
    checkedCodec
      report
      QualificationMetadataRefused
      (Metadata.refineNativeQualificationReceiptData fields)
  let bytes = Metadata.nativeQualificationReceiptBytes metadata
      sha = sha256Hex bytes
      count = fromIntegral (BS.length bytes)
      kind = Retain.NativeQualificationArtifact
  key <-
    checkedBinding
      report
      ( either
          (const (Left "closed qualification metadata key refused"))
          Right
          (Retain.nativeDetachedArtifactKey kind experiment sha)
      )
  stage report QualificationWrite
  written <-
    lift (Writer.writeBinaryArtifact experiment "native-qualification" (LBS.fromStrict bytes))
  let actualSha = Writer.storedArtifactSha written
      actualKey = Writer.storedArtifactObjectKey written
      mirrored = Writer.storedArtifactMirroredToLive written
  liftIO $ do
    _ <- evaluate (Text.length actualSha + Text.length actualKey)
    _ <- evaluate mirrored
    -- Count is the exact input buffer size; this ordinary failure report is
    -- not a physical-read ACK. Success independently reads the exact bytes.
    modifyIORef'
      report
      ( \value ->
          value
            { qualificationWrittenObject =
                Just
                  (Retain.NativeRetainedObjectData actualKey actualSha count before)
            }
      )
  require QualificationWriteReceiptDiffers (actualSha == sha && actualKey == key)
  require QualificationNotMirrored (not (configured before) || mirrored)
  let object = Retain.NativeRetainedObjectData key sha count before
  stage report QualificationPhysicalRead
  readResult <- liftIO (Retain.readNativeDetachedArtifact session kind object)
  physical <- case readResult of
    Left failure -> do
      _ <- liftIO (evaluate failure)
      liftIO $ modifyIORef' report (\value -> value {qualificationPhysicalFailure = Just failure})
      throwError QualificationPhysicalRefused
    Right value -> pure value
  require
    QualificationDecodeRefused
    ( Retain.nativeReadDetachedArtifactKind physical == kind
        && Retain.nativeReadDetachedArtifactReference physical == object
        && Retain.nativeReadDetachedArtifactBytes physical == bytes
    )
  stage report QualificationDecode
  decoded <-
    checkedCodec
      report
      QualificationDecodeRefused
      (Metadata.decodeNativeQualificationReceiptData (Retain.nativeReadDetachedArtifactBytes physical))
  require QualificationDecodeRefused (decoded == metadata)
  stage report QualificationReference
  reference <-
    checkedCodec
      report
      QualificationReferenceRefused
      (Reference.refineNativeQualificationReference (referenceFields facts object))
  -- Force the exact ordinary reference bytes beneath the safe boundary.
  _ <- liftIO (evaluate (BS.length (Reference.nativeQualificationReferenceBytes reference)))
  stage report QualificationCaptureAfter
  afterSession <- capture report mode
  let after = Retain.nativeRetentionPublication afterSession
  liftIO $
    forcePublication after
      >> modifyIORef' report (\value -> value {qualificationAfterPublication = Just after})
  require QualificationPublicationDiffers (after == before && after == originalPublication)
  stage report QualificationFinished
  pure (metadata, physical, reference, written)

data PublicationFacts
  = PublicationFacts
      !Metadata.NativeQualificationReceiptFields
      !Source.SourceStamp
      !Text
      !Text
      !Reference.NativeReferenceBinding
      !Retain.NativeRetentionMode

deriveFacts :: Retained.NativeRetainedServingReplays -> Either Text PublicationFacts
deriveFacts retained = do
  let stored = Retained.nativeRetainedReplayServing retained
      completed = Stored.nativeStoredCompletedServing stored
      training = Completed.nativeCompletedTraining completed
      produced =
        Replay.nativeEvaluationReplayedProducer
          ( Assessment.nativeAssessmentReplay
              (Candidate.nativeServingCandidateAssessment (Completed.nativeCompletedCandidate completed))
          )
      inventory = Producer.nativeProducedInventory produced
      allocation = Producer.nativeInventoryAllocation inventory
      phases =
        Producer.nativeInventoryPreludeObjects inventory
          <> concatMap Producer.nativeChildObjects (Producer.nativeInventoryChildren inventory)
          <> [Producer.nativeInventoryTerminal inventory]
      cohort = References.nativeCapturedReferenceCohort (Producer.nativeProducedReferences produced)
      singleton = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
      lane = Singleton.nativeSingletonSubstrate singleton
      row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
      experiment = Completed.nativeCompletedExperiment completed
      address = Store.completedStoredCheckpoint (Stored.nativeStoredCheckpoint stored)
      manifest = Store.storedManifestSha address
      sources = Producer.nativeProducedSources produced
      association = Producer.nativeProducedAssociation produced
      executable = Process.producerExecutableFileSha256 (Producer.nativeProducedBeforeProcess produced)
  requireData
    (isNothing (Retained.replayRetentionRefusal (Retained.nativeRetainedReplayReport retained)))
    "retained replay result carries a refusal"
  requireData
    ( fmap
        Envelope.decodedPhaseObject
        (Acquisition.acquisitionPhases (Retained.nativeRetainedReplayAcquisition retained))
        == phases
    )
    "same private acquisition does not retain the original ordered phase references"
  requireData
    ( Singleton.nativeSingletonPlanId singleton == Training.completedTrainingPlanId training
        && Singleton.nativeSingletonExperiment singleton == experiment
        && Cohort.nativeRlSeedPlanTrainingBudget (Cohort.nativeRlCohortServingChild cohort)
          == Training.completedTrainingBudget training
    )
    "same completed serving whole plan experiment or budget differs from its original cohort"
  case Cohort.nativeRlCohortPlanProjection cohort of
    Matrix.SomeProductProjection _ projection ->
      requireData
        ( Matrix.productProjectionPlanId projection == Training.completedTrainingPlanId training
            && Matrix.productProjectionExperimentHash projection == experiment
            && Matrix.productProjectionRowId projection == row
            && Matrix.productProjectionSubstrate projection == lane
        )
        "original complete canonical projection differs from completed serving"
  selectedSource <- case (Context.nativeContextObservedSource sources, Context.nativeContextSuppliedSource sources) of
    (Just actual, _) -> Right actual
    (_, Just actual) -> Right actual
    _ -> Left "same original producer has neither observed nor supplied source DATA"
  requireData
    (selectedSource == Retain.nativeAllocationSource (Producer.nativeProducedAcquisitionScope produced))
    "selected source differs from the same original acquisition scope"
  (metadataAssociation, invocation, binding, mode) <- case (association, Completed.nativeCompletedInvocation completed) of
    (Context.DirectLocalContext actual, Nothing) ->
      Right
        ( Metadata.NativeReceiptDirectData actual
        , hexDigest actual
        , Reference.NativeReferenceDirect
        , Retain.AllowLocalNativeRetention
        )
    (Context.SuppliedScenarioContext actual, Just same) -> do
      requireData (actual == same) "completed invocation differs from same original supplied association"
      Right
        ( Metadata.NativeReceiptScenarioData (Training.renderProductScenarioInvocation actual)
        , Training.productScenarioInvocationDigest actual
        , Reference.NativeReferenceScenario
        , Retain.RequireLiveNativeRetention
        )
    _ -> Left "same original direct/scenario association and completion invocation differ"
  plan <- digestText (Plan.planIdText (Training.completedTrainingPlanId training))
  cohortId <- digestText (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
  manifestId <- digestText manifest
  replays <- traverse replayReference (Retained.nativeRetainedReplayObjects retained)
  let fields =
        Metadata.NativeQualificationReceiptFields
          row
          lane
          plan
          experiment
          cohortId
          (Cohort.nativeRlCohortPlanTransport cohort)
          manifestId
          (Training.encodeCompletedTraining training)
          (Retain.nativeRetainedObjectPublication allocation)
          metadataAssociation
          (Context.nativeContextObservedSource sources)
          (Context.nativeContextSuppliedSource sources)
          allocation
          phases
          replays
  pure (PublicationFacts fields selectedSource executable invocation binding mode)
 where
  digestText =
    either (const (Left "same original identity is not canonical SHA256")) Right
      . Context.digestFromCanonicalText
  replayReference actual = do
    let value = Retained.nativeRetainedReplayData actual
        physical = Retained.nativeRetainedReplayPhysical actual
        expectedKind = case ReplayData.nativeReplayObjectStage value of
          ReplayData.StoredFinalModelReplay -> Retain.NativeStoreLoadedReplayArtifact
          _ -> Retain.NativeEvaluationReplayArtifact
    requireData
      ( Retain.nativeReadDetachedArtifactKind physical == expectedKind
          && Retain.nativeReadDetachedArtifactBytes physical == ReplayData.nativeReplayObjectBytes value
      )
      "same retained replay DATA and private physical bytes differ"
    pure
      ( Metadata.NativeReceiptReplayReference
          (ReplayData.nativeReplayObjectStage value)
          (ReplayData.nativeReplayObjectIndex value)
          (ReplayData.nativeReplayObjectAttempt value)
          (Retain.nativeReadDetachedArtifactReference physical)
      )

referenceFields
  :: PublicationFacts -> Retain.NativeRetainedObjectData -> Reference.NativeQualificationReferenceData
referenceFields (PublicationFacts fields source executable invocation binding _) object =
  Reference.NativeQualificationReferenceData
    (Metadata.nativeReceiptRow fields)
    (Metadata.nativeReceiptLane fields)
    (hexDigest (Metadata.nativeReceiptWholePlan fields))
    (Metadata.nativeReceiptExperiment fields)
    (hexDigest (Metadata.nativeReceiptManifest fields))
    source
    executable
    invocation
    (hexDigest (Metadata.nativeReceiptCohortId fields))
    (Retain.nativeRetainedObjectSha256 object)
    (Retain.nativeRetainedObjectKey object)
    (Retain.nativeRetainedObjectBytes object)
    (Retain.nativePublicationDigest (Metadata.nativeReceiptPublication fields))
    binding
    (Retain.nativeRetainedObjectKey (Metadata.nativeReceiptAllocation fields))
    (Retain.nativeRetainedObjectSha256 (Metadata.nativeReceiptAllocation fields))
    (Retain.nativeRetainedObjectBytes (Metadata.nativeReceiptAllocation fields))

capture
  :: IORef NativeQualificationPublicationReport
  -> Retain.NativeRetentionMode
  -> Program Retain.NativeRetentionSession
capture report mode = do
  result <- lift (Retain.captureNativeRetentionSession mode)
  case result of
    Right actual -> pure actual
    Left failure -> do
      _ <- liftIO (evaluate failure)
      liftIO $ modifyIORef' report (\value -> value {qualificationCaptureFailure = Just failure})
      throwError QualificationCaptureRefused

-- Preserve the boxed exception boundary and its existing forcing behavior.
{- HLINT ignore CodecDiagnostic "Use newtype instead of data" -}
data CodecDiagnostic = CodecDiagnostic CodecError deriving stock (Show)
instance Exception CodecDiagnostic
checkedCodec
  :: IORef NativeQualificationPublicationReport
  -> NativeQualificationFinding
  -> Either CodecError a
  -> Program a
checkedCodec report finding value = case value of
  Right actual -> pure actual
  Left failure -> do
    diagnostic <-
      liftIO (Failure.captureNativeExceptionDiagnostic (toException (CodecDiagnostic failure)))
    liftIO $ modifyIORef' report (\actual -> actual {qualificationDiagnostic = Just diagnostic})
    throwError finding
checkedBinding :: IORef NativeQualificationPublicationReport -> Either Text a -> Program a
checkedBinding report value = case value of
  Right actual -> pure actual
  Left reason -> do
    diagnostic <- liftIO (Failure.captureNativeDiagnostic reason)
    liftIO $ modifyIORef' report (\actual -> actual {qualificationDiagnostic = Just diagnostic})
    throwError QualificationBindingRefused
require :: NativeQualificationFinding -> Bool -> Program ()
require finding condition = unless condition (throwError finding)
requireData :: Bool -> Text -> Either Text ()
requireData condition detail = unless condition (Left detail)
stage :: IORef NativeQualificationPublicationReport -> NativeQualificationStage -> Program ()
stage report value = liftIO (modifyIORef' report (\actual -> actual {qualificationStage = value}))
hexDigest :: Digest -> Text
hexDigest =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
    . digestBytes
configured :: Retain.NativePublicationData -> Bool
configured Retain.NativeLocalPublication {} = False
configured Retain.NativeConfiguredPublication {} = True
forcePublication :: Retain.NativePublicationData -> IO ()
forcePublication value = case value of
  Retain.NativeLocalPublication resolution root -> forceResolution resolution >> evaluate (Text.length root) >> pure ()
  Retain.NativeConfiguredPublication resolution root endpoint mounted -> do
    forceResolution resolution
    _ <- evaluate (Text.length root + Text.length endpoint)
    _ <- evaluate mounted
    pure ()
 where
  forceResolution Retain.NativeDefaultPublicationResolution = pure ()
  forceResolution (Retain.NativeExplicitPublicationResolution identity) = void (evaluate (Text.length identity))

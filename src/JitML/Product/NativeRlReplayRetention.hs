{-# LANGUAGE OverloadedStrings #-}

-- | Retain the actual ten in-memory and one Store-loaded replay graphs from
-- the same private stored-serving result, binding them to physical acquisition
-- bytes first. This is neither a detached qualification receipt nor parent
-- authentication, source/build coherence, fsync or a journal publication.
module JitML.Product.NativeRlReplayRetention
  ( NativeRetainedServingReplays
  , NativeReplayRetentionFailure
  , NativeReplayRetentionStage (..)
  , NativeReplayRetentionReport (..)
  , NativeRetainedReplay
  , retainNativeServingReplays
  , nativeRetainedReplayServing
  , nativeRetainedReplayAcquisition
  , nativeRetainedReplayObjects
  , nativeRetainedReplayReport
  , nativeRetainedReplayData
  , nativeRetainedReplayPhysical
  , nativeReplayRetentionFailureReport
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, void, zipWithM)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Trans.Class (lift)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativePhase.Codec qualified as Phase
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReplayObjectData qualified as ReplayData
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Env (App)
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeReferenceCalibration qualified as References
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlCompletedServing qualified as Completed
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlServingCandidate qualified as Candidate
import JitML.Product.NativeRlStoreLoadedReplay qualified as Loaded
import JitML.Product.NativeRlStoredServing qualified as Stored
import JitML.Product.ValidationRecord (sha256Hex)

data NativeReplayRetentionStage
  = ReplayRetentionInput
  | ReplayRetentionCaptureBefore
  | ReplayRetentionPhysicalAcquisition
  | ReplayRetentionCompare
  | ReplayRetentionWrite !Int
  | ReplayRetentionRead !Int
  | ReplayRetentionCaptureAfter
  | ReplayRetentionFinished
  deriving stock (Eq, Show)

-- Failure DATA contains only safely observed metadata, never a poisoned
-- capsule or an invented successful replay/write/physical observation.
data NativeReplayRetentionReport = NativeReplayRetentionReport
  { replayRetentionStage :: !NativeReplayRetentionStage
  , replayRetentionBeforePublication :: !(Maybe Retain.NativePublicationData)
  , replayRetentionAfterPublication :: !(Maybe Retain.NativePublicationData)
  , replayRetentionWrittenObjects :: ![Retain.NativeRetainedObjectData]
  , replayRetentionPhysicalFailure :: !(Maybe Retain.NativePhysicalReadFailure)
  , replayRetentionRefusal :: !(Maybe Text)
  , replayRetentionDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)

data NativeRetainedReplay
  = NativeRetainedReplay
      !ReplayData.NativeReplayObjectData
      !Retain.NativeReadDetachedArtifact
data NativeRetainedServingReplays
  = NativeRetainedServingReplays
      !Stored.NativeStoredServing
      !Acquisition.NativeAcquisitionData
      ![NativeRetainedReplay]
      !NativeReplayRetentionReport
newtype NativeReplayRetentionFailure = NativeReplayRetentionFailure NativeReplayRetentionReport

nativeRetainedReplayServing :: NativeRetainedServingReplays -> Stored.NativeStoredServing
nativeRetainedReplayServing (NativeRetainedServingReplays actual _ _ _) = actual
nativeRetainedReplayAcquisition :: NativeRetainedServingReplays -> Acquisition.NativeAcquisitionData
nativeRetainedReplayAcquisition (NativeRetainedServingReplays _ actual _ _) = actual
nativeRetainedReplayObjects :: NativeRetainedServingReplays -> [NativeRetainedReplay]
nativeRetainedReplayObjects (NativeRetainedServingReplays _ _ actual _) = actual
nativeRetainedReplayReport :: NativeRetainedServingReplays -> NativeReplayRetentionReport
nativeRetainedReplayReport (NativeRetainedServingReplays _ _ _ actual) = actual
nativeRetainedReplayData :: NativeRetainedReplay -> ReplayData.NativeReplayObjectData
nativeRetainedReplayData (NativeRetainedReplay actual _) = actual
nativeRetainedReplayPhysical :: NativeRetainedReplay -> Retain.NativeReadDetachedArtifact
nativeRetainedReplayPhysical (NativeRetainedReplay _ actual) = actual
nativeReplayRetentionFailureReport :: NativeReplayRetentionFailure -> NativeReplayRetentionReport
nativeReplayRetentionFailureReport (NativeReplayRetentionFailure actual) = actual

type Program = ExceptT Text App
emptyReport :: NativeReplayRetentionReport
emptyReport = NativeReplayRetentionReport ReplayRetentionInput Nothing Nothing [] Nothing Nothing Nothing

-- No ordinary bytes, model, completion, writer, fetcher, evaluator, device,
-- reference, ACK or replacement invocation is supplied by the caller.
retainNativeServingReplays
  :: Stored.NativeStoredServing
  -> App (Either NativeReplayRetentionFailure NativeRetainedServingReplays)
retainNativeServingReplays serving = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    attempted <- tryAny (runReaderT (runExceptT (program report serving)) env)
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \value ->
              value
                { replayRetentionRefusal = Just "synchronous replay retention failure"
                , replayRetentionDiagnostic = Just diagnostic
                }
          )
        Left . NativeReplayRetentionFailure <$> readIORef report
      Right (Left reason) -> do
        diagnostic <- Failure.captureNativeDiagnostic reason
        modifyIORef'
          report
          ( \value ->
              value
                { replayRetentionRefusal = Just reason
                , replayRetentionDiagnostic = Just diagnostic
                }
          )
        Left . NativeReplayRetentionFailure <$> readIORef report
      Right (Right (acquisition, objects)) -> do
        observed <- readIORef report
        pure (Right (NativeRetainedServingReplays serving acquisition objects observed))

program
  :: IORef NativeReplayRetentionReport
  -> Stored.NativeStoredServing
  -> Program (Acquisition.NativeAcquisitionData, [NativeRetainedReplay])
program report serving = do
  _ <- liftIO (evaluate serving)
  let completed = Stored.nativeStoredCompletedServing serving
      assessment = Candidate.nativeServingCandidateAssessment (Completed.nativeCompletedCandidate completed)
      matching = Assessment.nativeAssessmentReplay assessment
      produced = Replay.nativeEvaluationReplayedProducer matching
      inventory = Producer.nativeProducedInventory produced
      allocation = Producer.nativeInventoryAllocation inventory
      publication = Retain.nativeRetainedObjectPublication allocation
      cohort = References.nativeCapturedReferenceCohort (Producer.nativeProducedReferences produced)
      lane =
        Singleton.nativeSingletonSubstrate
          (Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort))
      row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
      mode = case Completed.nativeCompletedInvocation completed of
        Nothing -> Retain.AllowLocalNativeRetention
        Just _ -> Retain.RequireLiveNativeRetention
  require
    (null (Assessment.nativeAssessmentLearningFindings assessment))
    "same serving assessment retains learning findings"
  batch <- checked "current complete native batch refused" (Cohort.mkCanonicalNativeRlCohorts lane)
  stage report ReplayRetentionCaptureBefore
  session <- capture mode
  let before = Retain.nativeRetentionPublication session
  liftIO $
    forcePublication before
      >> modifyIORef'
        report
        (\value -> value {replayRetentionBeforePublication = Just before})
  require
    (before == publication)
    "actual replay-retention publication differs from original allocation"
  stage report ReplayRetentionPhysicalAcquisition
  let references =
        Producer.nativeInventoryPreludeObjects inventory
          <> concatMap Producer.nativeChildObjects (Producer.nativeInventoryChildren inventory)
          <> [Producer.nativeInventoryTerminal inventory]
  _ <-
    checked
      "physical acquisition object count exceeds128"
      (boundedLength AggregateSequenceElements 128 references)
  actualAllocation <- physical report =<< liftIO (Retain.readNativeRetainedObject session allocation)
  actualPhases <-
    traverse
      (\reference -> physical report =<< liftIO (Retain.readNativeRetainedObject session reference))
      references
  acquisition <-
    checked
      "complete physical acquisition DATA refused"
      ( Acquisition.checkNativeAcquisitionData
          batch
          row
          (Producer.nativeProducedAssociation produced)
          (Producer.nativeProducedSources produced)
          (Retain.nativeReadObjectReference actualAllocation)
          (Retain.nativeReadObjectBytes actualAllocation)
          [ (Retain.nativeReadObjectReference value, Retain.nativeReadObjectBytes value) | value <- actualPhases
          ]
      )
  stage report ReplayRetentionCompare
  allocationDigest <-
    checked
      "actual allocation physical SHA refused"
      (Context.digestFromCanonicalText (Retain.nativeRetainedObjectSha256 allocation))
  dataObjects <-
    checked
      "actual replay graphs differ from complete physical acquisition"
      (replayObjects allocationDigest acquisition matching (Stored.nativeStoredLoadedReplay serving))
  require (length dataObjects == 11) "actual replay object cardinality differs from eleven"
  objects <-
    traverse
      (retainObject report session (Completed.nativeCompletedExperiment completed))
      (zip [0 ..] dataObjects)
  stage report ReplayRetentionCaptureAfter
  afterSession <- capture mode
  let after = Retain.nativeRetentionPublication afterSession
  liftIO $
    forcePublication after
      >> modifyIORef'
        report
        (\value -> value {replayRetentionAfterPublication = Just after})
  require (after == before && after == publication) "actual replay-retention publication changed"
  stage report ReplayRetentionFinished
  pure (acquisition, objects)

replayObjects
  :: Digest
  -> Acquisition.NativeAcquisitionData
  -> Replay.NativeEvaluationReplayedCohort
  -> Loaded.NativeStoreLoadedReplay
  -> Either Text [ReplayData.NativeReplayObjectData]
replayObjects allocation acquisition matching loaded = do
  let physicalChildren = Acquisition.acquisitionChildren acquisition
      report = Replay.nativeEvaluationReplayedReport matching
      actualChildren = Replay.nativeReplayChildren report
  requireData
    (length physicalChildren == 5 && fmap Acquisition.acquisitionChildIndex physicalChildren == [0 .. 4])
    "physical acquisition original five indices differ"
  requireData
    ( null (Replay.nativeReplayReportFindings report)
        && fmap Replay.nativeReplayChildIndex actualChildren == [0 .. 4]
    )
    "same original ten-replay report has findings or different indices"
  pairs <- zipWithM child physicalChildren actualChildren
  physicalZero <- case physicalChildren of
    first : _ -> pure first
    [] -> Left "physical acquisition has no serving zero"
  let final = Loaded.nativeStoreLoadedReport loaded
  requireData (null (Loaded.loadedReplayFindings final)) "same Store-loaded replay has findings"
  case (Loaded.loadedReplayExpectedCapture final, Loaded.loadedReplayActualCapture final) of
    ( Just (Loaded.NativeLoadedReplayCapture expected expectedEntries)
      , Just (Loaded.NativeLoadedReplayCapture actual actualEntries)
      ) -> do
        requireData
          (expected == actual && expectedEntries == actualEntries)
          "Store-loaded canonical captures differ"
        comparePhysical physicalZero "final" actual actualEntries
        object <-
          codec
            ( ReplayData.refineNativeReplayObjectData
                ReplayData.StoredFinalModelReplay
                0
                allocation
                (Acquisition.acquisitionChildAttempt physicalZero)
                actual
                actualEntries
            )
        pure (concat pairs <> [object])
    _ -> Left "Store-loaded replay lacks either actual complete capture"
 where
  child physicalChild replayed = do
    let index = Acquisition.acquisitionChildIndex physicalChild
        attempt = Acquisition.acquisitionChildAttempt physicalChild
    requireData
      ( Replay.nativeReplayChildIndex replayed == index
          && Replay.nativeReplayChildAttempt replayed == attempt
          && null (Replay.nativeReplayChildFindings replayed)
      )
      "replay original child association differs"
    case Replay.nativeReplayChildEvaluations replayed of
      [initial, final] ->
        zipWithM
          (evaluation physicalChild index attempt)
          [ (Replay.ReplayInitialEvaluation, ReplayData.InitialModelReplay, "initial")
          , (Replay.ReplayFinalEvaluation, ReplayData.FinalModelReplay, "final")
          ]
          [initial, final]
      _ -> Left "replay child does not retain exactly its original initial and final evaluation"
  evaluation physicalChild index attempt (expectedStage, retainedStage, label) observed = do
    requireData
      (Replay.nativeReplayStage observed == expectedStage && null (Replay.nativeReplayFindings observed))
      "replay evaluation stage or findings differ"
    case (Replay.nativeReplayExpectedRoot observed, Replay.nativeReplayActualCapture observed) of
      (Just expected, Just (Replay.NativeReplayCapture actual entries)) -> do
        requireData (expected == actual) "actual replay root differs from its expected root"
        comparePhysical physicalChild label actual entries
        codec
          ( ReplayData.refineNativeReplayObjectData
              retainedStage
              (fromIntegral index)
              allocation
              attempt
              actual
              entries
          )
      _ -> Left "replay evaluation lacks a complete expected and actual capture"
  comparePhysical physicalChild suffix root entries = do
    let label = "child" <> Text.pack (show (Acquisition.acquisitionChildIndex physicalChild)) <> "." <> suffix
    phase <-
      maybe
        (Left "physical original evaluation phase is absent")
        Right
        (lookup label (Acquisition.acquisitionChildPhases physicalChild))
    requireData
      (Phase.phaseDataRoot phase == root)
      "physical original evaluation root differs from actual replay"
    selected <- codec (Graph.reachableNodePool [root] (Phase.phaseDataPool phase))
    requireData
      ([(digest, bytes) | (digest, _, bytes) <- Graph.nodePoolEntries selected] == entries)
      "physical original evaluation canonical node bytes differ from actual replay"

retainObject
  :: IORef NativeReplayRetentionReport
  -> Retain.NativeRetentionSession
  -> Text
  -> (Int, ReplayData.NativeReplayObjectData)
  -> Program NativeRetainedReplay
retainObject report session experiment (ordinal, object) = do
  let kind = case ReplayData.nativeReplayObjectStage object of
        ReplayData.StoredFinalModelReplay -> Retain.NativeStoreLoadedReplayArtifact
        _ -> Retain.NativeEvaluationReplayArtifact
      tag = case kind of
        Retain.NativeStoreLoadedReplayArtifact -> "native-store-loaded-replay"
        _ -> "native-evaluation-replay"
      bytes = ReplayData.nativeReplayObjectBytes object
      sha = sha256Hex bytes
      publication = Retain.nativeRetentionPublication session
  expectedKey <-
    checked "closed replay artifact key refused" (Retain.nativeDetachedArtifactKey kind experiment sha)
  stage report (ReplayRetentionWrite ordinal)
  written <- lift (Writer.writeBinaryArtifact experiment tag (LBS.fromStrict bytes))
  let actualSha = Writer.storedArtifactSha written
      actualKey = Writer.storedArtifactObjectKey written
      mirrored = Writer.storedArtifactMirroredToLive written
  liftIO $ do
    _ <- evaluate (Text.length actualSha + Text.length actualKey)
    _ <- evaluate mirrored
    -- Record observed Writer metadata before refusing an unexpected receipt.
    modifyIORef'
      report
      ( \value ->
          value
            { replayRetentionWrittenObjects =
                replayRetentionWrittenObjects value
                  <> [Retain.NativeRetainedObjectData actualKey actualSha (fromIntegral (BS.length bytes)) publication]
            }
      )
  require
    (actualSha == sha && actualKey == expectedKey)
    "concrete replay writer returned a different address"
  require
    (not (configured publication) || mirrored)
    "concrete replay artifact was not mirrored to configured publication"
  let reference = Retain.NativeRetainedObjectData expectedKey sha (fromIntegral (BS.length bytes)) publication
  stage report (ReplayRetentionRead ordinal)
  actual <- physical report =<< liftIO (Retain.readNativeDetachedArtifact session kind reference)
  require
    (Retain.nativeReadDetachedArtifactBytes actual == bytes)
    "physical replay artifact bytes differ from actual graph encoding"
  decoded <-
    checked
      "physically fetched replay graph DATA refused"
      (ReplayData.decodeNativeReplayObjectData (Retain.nativeReadDetachedArtifactBytes actual))
  require (decoded == object) "physically fetched replay graph fields differ from same actual replay"
  pure (NativeRetainedReplay object actual)

capture :: Retain.NativeRetentionMode -> Program Retain.NativeRetentionSession
capture mode =
  checked "actual replay-retention session capture refused"
    =<< lift (Retain.captureNativeRetentionSession mode)
physical
  :: IORef NativeReplayRetentionReport -> Either Retain.NativePhysicalReadFailure a -> Program a
physical report value = case value of
  Right actual -> pure actual
  Left failure -> do
    liftIO $ modifyIORef' report (\actual -> actual {replayRetentionPhysicalFailure = Just failure})
    throwError "actual replay-retention physical read refused"
checked :: Text -> Either e a -> Program a
checked reason = either (const (throwError reason)) pure
require :: Bool -> Text -> Program ()
require condition detail = unless condition (throwError detail)
requireData :: Bool -> Text -> Either Text ()
requireData condition detail = unless condition (Left detail)
codec :: Either CodecError a -> Either Text a
codec = either (const (Left "replay graph DATA codec refused")) Right
stage :: IORef NativeReplayRetentionReport -> NativeReplayRetentionStage -> Program ()
stage report value = liftIO (modifyIORef' report (\actual -> actual {replayRetentionStage = value}))
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
  forceResolution (Retain.NativeExplicitPublicationResolution sha) = void (evaluate (Text.length sha))

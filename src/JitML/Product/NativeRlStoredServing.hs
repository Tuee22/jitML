{-# LANGUAGE OverloadedStrings #-}

-- | Concrete final-serving persistence and physical replay. This private
-- result is neither NativePublication, parent authentication, qualification
-- nor an fsync claim. It accepts only the actual completed-serving capsule;
-- no writer, fetcher, evaluator, weights, completion or ACK callback enters.
module JitML.Product.NativeRlStoredServing
  ( NativeStoredServing
  , NativeStoredServingFailure
  , NativeStoredServingStage (..)
  , NativeStoredServingFinding (..)
  , NativeStoredServingReport (..)
  , NativeStoredCompanionData (..)
  , storeNativeCompletedServing
  , nativeStoredCompletedServing
  , nativeStoredCheckpoint
  , nativeStoredPhysicalCheckpoint
  , nativeStoredLoadedReplay
  , nativeStoredCompanion
  , nativeStoredServingReport
  , nativeStoredServingFailureReport
  , validateNativeStoredAddressData
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, void)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Trans.Class (lift)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Env (App)
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlCompletedServing qualified as Completed
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlServingCandidate qualified as Candidate
import JitML.Product.NativeRlStoreLoadedReplay qualified as Loaded
import JitML.Product.Publisher.NativeCompanion qualified as Companion
import JitML.RL.AlphaZero.PreparedTrainer qualified as ArenaLow
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerExecution qualified as Trainer
import JitML.Training.Budget qualified as Training

data NativeStoredServingStage
  = StoredInput
  | StoredCaptureBefore
  | StoredCompanionWrite
  | StoredCheckpointWrite
  | StoredPhysicalRead
  | StoredFinalLoadedReplay
  | StoredCaptureAfter
  | StoredFinished
  deriving stock (Eq, Show)
data NativeStoredServingFinding
  = StoredInputRejected
  | StoredPublicationCaptureRefused
  | StoredPublicationDiffers
  | StoredCompanionReceiptDiffers
  | StoredCompanionNotMirrored
  | StoredAddressRejected
  | StoredPhysicalReadRefused
  | StoredLoadedReplayRefused
  | StoredSynchronousFailure
  deriving stock (Eq, Show)

-- Ordinary, fully forced observations. Failure reports retain no input,
-- output or partially evaluated capability and cannot be promoted to one.
data NativeStoredCompanionData = NativeStoredCompanionData
  { storedCompanionKind :: !Text
  , storedCompanionObjectKey :: !Text
  , storedCompanionSha256 :: !Text
  , storedCompanionMirroredToLive :: !Bool
  }
  deriving stock (Eq, Show)
data NativeStoredServingReport = NativeStoredServingReport
  { storedServingStage :: !NativeStoredServingStage
  , storedServingExperiment :: !(Maybe Text)
  , storedServingBeforePublication :: !(Maybe Retain.NativePublicationData)
  , storedServingAfterPublication :: !(Maybe Retain.NativePublicationData)
  , storedServingCompanionData :: !(Maybe NativeStoredCompanionData)
  , storedServingManifestSha :: !(Maybe Text)
  , storedServingManifestKey :: !(Maybe Text)
  , storedServingPhysicalFailure :: !(Maybe Retain.NativePhysicalReadFailure)
  , storedServingLoadedReport :: !(Maybe Loaded.NativeLoadedReplayReport)
  , storedServingFindings :: ![NativeStoredServingFinding]
  , storedServingDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)

data NativeStoredServing
  = NativeStoredServing
      !Completed.NativeCompletedServing
      !Store.StoredCompletedCheckpoint
      !Retain.NativeReadCheckpoint
      !Loaded.NativeStoreLoadedReplay
      !Writer.StoredArtifact
      !NativeStoredServingReport
newtype NativeStoredServingFailure = NativeStoredServingFailure NativeStoredServingReport

nativeStoredCompletedServing :: NativeStoredServing -> Completed.NativeCompletedServing
nativeStoredCompletedServing (NativeStoredServing value _ _ _ _ _) = value
nativeStoredCheckpoint :: NativeStoredServing -> Store.StoredCompletedCheckpoint
nativeStoredCheckpoint (NativeStoredServing _ value _ _ _ _) = value
nativeStoredPhysicalCheckpoint :: NativeStoredServing -> Retain.NativeReadCheckpoint
nativeStoredPhysicalCheckpoint (NativeStoredServing _ _ value _ _ _) = value
nativeStoredLoadedReplay :: NativeStoredServing -> Loaded.NativeStoreLoadedReplay
nativeStoredLoadedReplay (NativeStoredServing _ _ _ value _ _) = value
nativeStoredCompanion :: NativeStoredServing -> Writer.StoredArtifact
nativeStoredCompanion (NativeStoredServing _ _ _ _ value _) = value
nativeStoredServingReport :: NativeStoredServing -> NativeStoredServingReport
nativeStoredServingReport (NativeStoredServing _ _ _ _ _ value) = value
nativeStoredServingFailureReport :: NativeStoredServingFailure -> NativeStoredServingReport
nativeStoredServingFailureReport (NativeStoredServingFailure value) = value

emptyReport :: NativeStoredServingReport
emptyReport =
  NativeStoredServingReport
    StoredInput
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    []
    Nothing

type Program = ExceptT NativeStoredServingFinding App

-- This is an actual persistence operation, not a preparatory DATA builder.
-- Writer's existing completed snapshot/CAS semantics remain authoritative.
-- Repeating this entry is not claimed to be a fresh acquisition or once-only
-- publication: the underlying immutable/idempotent writer rules still apply.
storeNativeCompletedServing
  :: Completed.NativeCompletedServing
  -> App (Either NativeStoredServingFailure NativeStoredServing)
storeNativeCompletedServing completed = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    -- All concrete App effects use this same Env under safe-exceptions.
    -- Async exceptions propagate, including cancellation during a write;
    -- successful earlier writes are not rolled back or relabelled failed.
    attempted <- tryAny (runReaderT (runExceptT (program report completed)) env)
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \actual ->
              actual
                { storedServingFindings = storedServingFindings actual <> [StoredSynchronousFailure]
                , storedServingDiagnostic = Just diagnostic
                }
          )
        Left . NativeStoredServingFailure <$> readIORef report
      Right (Left finding) -> do
        modifyIORef'
          report
          ( \actual ->
              actual
                { storedServingFindings = storedServingFindings actual <> [finding]
                }
          )
        Left . NativeStoredServingFailure <$> readIORef report
      Right (Right (stored, physical, replayed, companion)) -> do
        final <- readIORef report
        pure (Right (NativeStoredServing completed stored physical replayed companion final))

program
  :: IORef NativeStoredServingReport
  -> Completed.NativeCompletedServing
  -> Program
       ( Store.StoredCompletedCheckpoint
       , Retain.NativeReadCheckpoint
       , Loaded.NativeStoreLoadedReplay
       , Writer.StoredArtifact
       )
program report completed = do
  _ <- liftIO (evaluate completed)
  let experiment = Completed.nativeCompletedExperiment completed
      candidate = Completed.nativeCompletedCandidate completed
      produced =
        Replay.nativeEvaluationReplayedProducer
          (Assessment.nativeAssessmentReplay (Candidate.nativeServingCandidateAssessment candidate))
      expectedPublication =
        Retain.nativeRetainedObjectPublication
          (Producer.nativeInventoryAllocation (Producer.nativeProducedInventory produced))
      mode = case Completed.nativeCompletedInvocation completed of
        Nothing -> Retain.AllowLocalNativeRetention
        Just _ -> Retain.RequireLiveNativeRetention
  liftIO $ do
    _ <- evaluate (Text.length experiment)
    forcePublication expectedPublication
    modifyIORef' report (\actual -> actual {storedServingExperiment = Just experiment})
  stage report StoredCaptureBefore
  session <- captureSession report mode
  let publication = Retain.nativeRetentionPublication session
  liftIO $ do
    forcePublication publication
    modifyIORef' report (\actual -> actual {storedServingBeforePublication = Just publication})
  require StoredPublicationDiffers (publication == expectedPublication)
  (kind, payload) <- checked report StoredInputRejected (companionPayload completed)
  -- Force the SAME complete text before writing it; no reconstruction from
  -- scores, fabricated frames, sampler or replacement evaluation is used.
  (expectedSha, expectedKey) <- liftIO $ do
    _ <- evaluate (Text.length kind + Text.length payload)
    let sha = sha256Text payload
        key = companionKey experiment kind sha
    _ <- evaluate (Text.length sha + Text.length key)
    pure (sha, key)
  stage report StoredCompanionWrite
  companion <- lift (Writer.writeTextArtifact experiment kind payload)
  observed <- liftIO (forceCompanion kind companion)
  liftIO $ modifyIORef' report (\actual -> actual {storedServingCompanionData = Just observed})
  require
    StoredCompanionReceiptDiffers
    (storedCompanionSha256 observed == expectedSha && storedCompanionObjectKey observed == expectedKey)
  require
    StoredCompanionNotMirrored
    (not (configured publication) || storedCompanionMirroredToLive observed)
  let pointer = Format.ArtifactPointer kind expectedKey (Just expectedSha)
  stage report StoredCheckpointWrite
  stored <- case Completed.nativeCompletedHostTrace completed of
    Nothing ->
      lift
        ( Writer.writeLocalCompletedProductWeightCheckpoint
            (Completed.nativeCompletedTraining completed)
            experiment
            (Completed.nativeCompletedTensorName completed)
            (Completed.nativeCompletedStep completed)
            (Completed.nativeCompletedMetrics completed)
            (Completed.nativeCompletedWeights completed)
            [pointer]
        )
    Just trace ->
      lift
        ( Writer.writeLocalCompletedArsHostCheckpoint
            (Completed.nativeCompletedTraining completed)
            experiment
            (Completed.nativeCompletedTensorName completed)
            (Completed.nativeCompletedStep completed)
            (Completed.nativeCompletedMetrics completed)
            trace
            [pointer]
        )
  let address = Store.completedStoredCheckpoint stored
      sha = Store.storedManifestSha address
      key = Store.storedManifestObjectKey address
  liftIO $ do
    _ <- evaluate (Text.length sha + Text.length key)
    modifyIORef'
      report
      (\actual -> actual {storedServingManifestSha = Just sha, storedServingManifestKey = Just key})
  checked report StoredAddressRejected (validateNativeStoredAddressData experiment address)
  stage report StoredPhysicalRead
  physicalResult <- liftIO (Retain.readNativeExecutionCheckpoint session experiment sha >>= evaluate)
  physical <- case physicalResult of
    Left failure -> do
      _ <- liftIO (evaluate failure)
      liftIO $ modifyIORef' report (\actual -> actual {storedServingPhysicalFailure = Just failure})
      throwError StoredPhysicalReadRefused
    Right actual -> pure actual
  require StoredPublicationDiffers (Retain.nativeReadCheckpointPublication physical == publication)
  -- Both real reads have already compared completion and exact physical
  -- tensor bytes. Independently bind the effective addressed manifest to
  -- this same completed value and its sole immutable companion pointer.
  checked report StoredAddressRejected (bindPhysical completed address pointer physical)
  stage report StoredFinalLoadedReplay
  replayResult <-
    lift
      (Loaded.replayNativeStoreLoadedServing completed (Retain.nativeReadCheckpointEffective physical))
  replayed <- case replayResult of
    Left failure -> do
      let actual = Loaded.nativeStoreLoadedFailureReport failure
      liftIO $ modifyIORef' report (\value -> value {storedServingLoadedReport = Just actual})
      throwError StoredLoadedReplayRefused
    Right actual -> do
      liftIO $
        modifyIORef'
          report
          (\value -> value {storedServingLoadedReport = Just (Loaded.nativeStoreLoadedReport actual)})
      pure actual
  stage report StoredCaptureAfter
  afterSession <- captureSession report mode
  let after = Retain.nativeRetentionPublication afterSession
  liftIO $ do
    forcePublication after
    modifyIORef' report (\actual -> actual {storedServingAfterPublication = Just after})
  require StoredPublicationDiffers (after == publication && after == expectedPublication)
  stage report StoredFinished
  pure (stored, physical, replayed, companion)

-- Unit-only address DATA check. It cannot create a writer receipt, Store
-- admission, loaded replay or NativeStoredServing.
validateNativeStoredAddressData :: Text -> Store.StoredCheckpoint -> Either Text ()
validateNativeStoredAddressData experiment stored = do
  requireData (canonicalExperiment experiment) "stored experiment namespace is not canonical"
  requireData (canonicalSha (Store.storedManifestSha stored)) "stored manifest SHA is not canonical"
  requireData
    (Store.storedPointerResult stored == Format.PointerWritten (Store.storedManifestSha stored))
    "stored completed write has no matching successful pointer result"
  requireData
    ( Store.storedManifestObjectKey stored
        == Format.manifestKey experiment (Store.storedManifestSha stored)
    )
    "stored manifest key differs from its exact experiment/SHA address"

bindPhysical
  :: Completed.NativeCompletedServing
  -> Store.StoredCheckpoint
  -> Format.ArtifactPointer
  -> Retain.NativeReadCheckpoint
  -> Either Text ()
bindPhysical completed stored companion physical = do
  let admitted = Retain.nativeReadCheckpointEffective physical
      base = Store.admittedExecutionCheckpoint admitted
      manifest = Store.admittedCheckpointManifest base
      experiment = Completed.nativeCompletedExperiment completed
      expectedCompletion = Training.encodeCompletedTraining (Completed.nativeCompletedTraining completed)
  validateNativeStoredAddressData experiment stored
  requireData
    ( Store.admittedCheckpointManifestSha base == Store.storedManifestSha stored
        && Store.admittedCheckpointManifestBodySha base == Store.storedManifestBodySha stored
        && Format.manifestExperiment manifest == experiment
    )
    "physically admitted manifest address or body SHA differs from the actual write"
  requireData
    ( Training.encodeCompletedTraining (Store.admittedExecutionCompletedTraining admitted)
        == expectedCompletion
    )
    "physically admitted complete training differs from the same serving completion"
  case Format.manifestCompletedTraining manifest of
    Just actual ->
      requireData
        (Training.encodeCompletedTraining actual == expectedCompletion)
        "physically admitted manifest completion differs from the same serving completion"
    Nothing -> Left "physically admitted manifest has no completed training"
  snapshot <-
    Store.checkpointStorageSnapshotId manifest
      >>= maybe
        (Left "newly written completed checkpoint has no immutable storage snapshot")
        Right
  let expectedPointer =
        companion
          { Format.artifactPointerObjectKey =
              Format.snapshotPhysicalObjectKey
                experiment
                snapshot
                (Format.artifactPointerObjectKey companion)
          }
  requireData
    (Format.manifestTranscriptPointers manifest == [expectedPointer])
    "physically admitted checkpoint does not contain the sole exact serving companion"

companionPayload :: Completed.NativeCompletedServing -> Either Text (Text, Text)
companionPayload completed = case Candidate.nativeServingCandidateModel (Completed.nativeCompletedCandidate completed) of
  Candidate.NativeReturnServingCandidateData child artifact _ -> do
    plan <-
      maybe
        (Left "serving child has no compiled RETURN recipe")
        Right
        (Cohort.nativeRlSeedPlanCompiledReturn child)
    seed <- checkedSeed (Cohort.nativeRlSeedPlanSeed child)
    Right
      ( "rl-trajectory"
      , Companion.renderRlTrajectoryArtifact
          (Completed.nativeCompletedExperiment completed)
          (Budget.compiledRlEnvironment plan)
          (Budget.compiledRlTrainerKind plan)
          seed
          (Trainer.evaluationSetEpisodes (Trainer.trainedArtifactEvaluationSet artifact))
      )
  Candidate.NativeArenaServingCandidateData child evaluated -> do
    seed <- checkedSeed (Cohort.nativeRlSeedPlanSeed child)
    let returned = Arena.nativeAlphaZeroEvaluatedReturnedData evaluated
        raw = Arena.nativeAlphaZeroReturnedRawObservation returned
    Right
      ( "alphazero-transcript"
      , Companion.renderAlphaZeroTranscriptArtifact
          (Completed.nativeCompletedExperiment completed)
          seed
          (ArenaLow.alphaZeroObservedSimulations raw)
          (ArenaLow.alphaZeroObservedMaxPlies raw)
          (ArenaLow.alphaZeroObservedSamples raw)
      )
 where
  checkedSeed value = do
    requireData
      (toInteger value <= toInteger (maxBound :: Int))
      "actual serving seed exceeds renderer Int scope"
    Right (fromIntegral value)

captureSession
  :: IORef NativeStoredServingReport
  -> Retain.NativeRetentionMode
  -> Program Retain.NativeRetentionSession
captureSession report mode = do
  result <- lift (Retain.captureNativeRetentionSession mode)
  case result of
    Right session -> pure session
    Left reason -> do
      diagnostic <- liftIO (Failure.captureNativeDiagnostic (Text.pack (show reason)))
      liftIO $ modifyIORef' report (\actual -> actual {storedServingDiagnostic = Just diagnostic})
      throwError StoredPublicationCaptureRefused

forceCompanion :: Text -> Writer.StoredArtifact -> IO NativeStoredCompanionData
forceCompanion kind actual = do
  let sha = Writer.storedArtifactSha actual
      key = Writer.storedArtifactObjectKey actual
      mirrored = Writer.storedArtifactMirroredToLive actual
  _ <- evaluate (Text.length kind + Text.length sha + Text.length key)
  _ <- evaluate mirrored
  pure (NativeStoredCompanionData kind key sha mirrored)

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

configured :: Retain.NativePublicationData -> Bool
configured Retain.NativeLocalPublication {} = False
configured Retain.NativeConfiguredPublication {} = True

canonicalExperiment :: Text -> Bool
canonicalExperiment value =
  not (Text.null value)
    && Text.length value <= 1024
    && value /= "."
    && value /= ".."
    && Text.all
      (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" :: String))
      value

canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

companionKey :: Text -> Text -> Text -> Text
companionKey experiment kind sha = "jitml-checkpoints/" <> experiment <> "/artifacts/" <> kind <> "/" <> sha <> ".txt"

sha256Text :: Text -> Text
sha256Text =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
    . SHA256.hash
    . Encoding.encodeUtf8

stage :: IORef NativeStoredServingReport -> NativeStoredServingStage -> Program ()
stage report value = liftIO (modifyIORef' report (\actual -> actual {storedServingStage = value}))

checked
  :: IORef NativeStoredServingReport -> NativeStoredServingFinding -> Either Text a -> Program a
checked report finding value = case value of
  Right actual -> pure actual
  Left reason -> do
    diagnostic <- liftIO (Failure.captureNativeDiagnostic reason)
    liftIO $ modifyIORef' report (\actual -> actual {storedServingDiagnostic = Just diagnostic})
    throwError finding

require :: NativeStoredServingFinding -> Bool -> Program ()
require finding condition = unless condition (throwError finding)
requireData :: Bool -> Text -> Either Text ()
requireData condition detail = unless condition (Left detail)

{-# LANGUAGE OverloadedStrings #-}

-- | Concrete child execution, ending at a physically read CHILD receipt.
-- This does not authenticate a parent, bind a loaded image to source, issue a
-- ProductRow/report result, or establish a journal qualification. There is no
-- supplied trainer, evaluator, device, writer, reader, completion or result.
module JitML.Product.NativeRlExecution
  ( NativeRlExecutionResult
  , NativeRlExecutionReport (..)
  , NativeRlExecutionStage (..)
  , executeNativeRlPublication
  , nativeRlExecutionReport
  , nativeRlExecutionPublication
  , renderNativeChildPipelineRefusal
  ) where

import Control.Exception (Exception, evaluate, toException)
import Control.Exception.Safe (tryAny)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Trans.Class (lift)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Env.Env (App)
import JitML.Product.NativeQualificationPublication qualified as Publication
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlCompletedServing qualified as Completed
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlReplayRetention qualified as Retained
import JitML.Product.NativeRlServingCandidate qualified as Candidate
import JitML.Product.NativeRlStoredServing qualified as Stored

data NativeRlExecutionStage
  = NativeExecutionInput
  | NativeExecutionProduce
  | NativeExecutionReplay
  | NativeExecutionAssess
  | NativeExecutionCandidate
  | NativeExecutionComplete
  | NativeExecutionStore
  | NativeExecutionRetainReplays
  | NativeExecutionPublishChild
  | NativeExecutionFinished
  deriving stock (Eq, Show)

-- Original successful earlier observations survive a later refusal. In
-- particular the actual five child reports and finite learning failures are
-- not replaced, retried, shortened or converted to a qualifying pass. These
-- in-memory values are inspection/history only; no report is accepted as input.
data NativeRlExecutionReport = NativeRlExecutionReport
  { nativeExecutionStage :: !NativeRlExecutionStage
  , nativeExecutionProducer :: !(Maybe Producer.NativeProducerResult)
  , nativeExecutionReplay :: !(Maybe Replay.NativeEvaluationReplayReport)
  , nativeExecutionAssessment :: !(Maybe Assessment.NativeCohortAssessment)
  , nativeExecutionAssessmentFailure :: !(Maybe Assessment.NativeAssessmentFailure)
  , nativeExecutionCandidateFailure :: !(Maybe Candidate.NativeServingCandidateFailure)
  , nativeExecutionCompletionFailure :: !(Maybe Completed.NativeCompletedServingFailure)
  , nativeExecutionStored :: !(Maybe Stored.NativeStoredServingReport)
  , nativeExecutionRetained :: !(Maybe Retained.NativeReplayRetentionReport)
  , nativeExecutionPublication :: !(Maybe Publication.NativeQualificationPublicationReport)
  , nativeExecutionRefusedAt :: !(Maybe NativeRlExecutionStage)
  , nativeExecutionDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }

data NativeRlExecutionResult
  = NativeRlExecutionResult
      !NativeRlExecutionReport
      !(Maybe Publication.NativeQualificationPublication)

nativeRlExecutionReport :: NativeRlExecutionResult -> NativeRlExecutionReport
nativeRlExecutionReport (NativeRlExecutionResult report _) = report

nativeRlExecutionPublication
  :: NativeRlExecutionResult -> Maybe Publication.NativeQualificationPublication
nativeRlExecutionPublication (NativeRlExecutionResult _ publication) = publication

-- | Render only already observed refusal detail, never the complete producer
-- report or any referenced object. Candidate findings keep their typed reason;
-- an unavailable/oversized rendering falls back to the captured outer detail.
renderNativeChildPipelineRefusal :: NativeRlExecutionReport -> IO Text.Text
renderNativeChildPipelineRefusal report = do
  detail <- selectDetail (candidateDetails <> outerDetails)
  pure (prefix <> maybe "" (": " <>) detail)
 where
  prefix =
    "native canonical child pipeline refused at "
      <> Text.pack (show (nativeExecutionStage report))
  candidateDetails = case nativeExecutionCandidateFailure report of
    Nothing -> []
    Just failure -> [Failure.captureNativeExceptionDiagnostic (toException (CandidateRefusalDiagnostic failure))]
  outerDetails = case nativeExecutionDiagnostic report of
    Nothing -> []
    Just diagnostic -> [captureOriginal diagnostic]
  captureOriginal (Failure.CompleteNativeDiagnostic text) = Failure.captureNativeDiagnostic text
  captureOriginal other = pure other
  selectDetail [] = pure Nothing
  selectDetail (capture : rest) = do
    captured <- capture
    case captured of
      Failure.CompleteNativeDiagnostic text -> pure (Just text)
      _ -> selectDetail rest

-- The existing exception capture bounds a lazy Show renderer before packing
-- Text, so an endless findings list cannot escape the diagnostic byte limit.
newtype CandidateRefusalDiagnostic = CandidateRefusalDiagnostic Candidate.NativeServingCandidateFailure
instance Show CandidateRefusalDiagnostic where
  show (CandidateRefusalDiagnostic failure) = show failure
instance Exception CandidateRefusalDiagnostic

emptyReport :: NativeRlExecutionReport
emptyReport =
  NativeRlExecutionReport
    NativeExecutionInput
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing

type Program = ExceptT NativeRlExecutionStage App

-- All concrete App effects use the SAME actual Env. A scenario's real opaque
-- invocation/source distinction is passed unchanged to the sole producer.
-- Neither this result nor its child receipt is a parent eligibility factory.
executeNativeRlPublication
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> Producer.NativeProducerContext
  -> App NativeRlExecutionResult
executeNativeRlPublication batch row context = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    attempted <- tryAny (runReaderT (runExceptT (program report batch row context)) env)
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \actual ->
              actual
                { nativeExecutionRefusedAt = Just (nativeExecutionStage actual)
                , nativeExecutionDiagnostic = Just diagnostic
                }
          )
        actual <- readIORef report
        pure (NativeRlExecutionResult actual Nothing)
      Right (Left refused) -> do
        modifyIORef' report (\actual -> actual {nativeExecutionRefusedAt = Just refused})
        actual <- readIORef report
        pure (NativeRlExecutionResult actual Nothing)
      Right (Right publication) -> do
        actual <- readIORef report
        pure (NativeRlExecutionResult actual (Just publication))

program
  :: IORef NativeRlExecutionReport
  -> Cohort.NativeRlCohortBatch
  -> Text
  -> Producer.NativeProducerContext
  -> Program Publication.NativeQualificationPublication
program report batch row context = do
  -- Demand the public input heads under the async-safe exception boundary,
  -- before running a producer or observing the environment.
  _ <- liftIO (evaluate batch)
  _ <- liftIO (evaluate (Text.length row))
  _ <- liftIO (evaluate context)
  stage report NativeExecutionProduce
  producedResult <- lift (Producer.produceNativeRlCohort batch row context)
  update report (\actual -> actual {nativeExecutionProducer = Just producedResult})
  produced <-
    maybe
      (throwError NativeExecutionProduce)
      pure
      (Producer.nativeProducerProducedCohort producedResult)

  stage report NativeExecutionReplay
  replayResult <- lift (Replay.replayNativeProducedEvaluations produced)
  update
    report
    (\actual -> actual {nativeExecutionReplay = Just (Replay.nativeEvaluationReplayReport replayResult)})
  replayed <-
    maybe
      (throwError NativeExecutionReplay)
      pure
      (Replay.nativeEvaluationReplayedCohort replayResult)

  stage report NativeExecutionAssess
  assessed <- liftIO (Assessment.assessNativeReplayedCohort replayed)
  assessment <- case assessed of
    Left failure -> do
      update report (\actual -> actual {nativeExecutionAssessmentFailure = Just failure})
      throwError NativeExecutionAssess
    Right actual -> do
      update report (\value -> value {nativeExecutionAssessment = Just actual})
      pure actual

  stage report NativeExecutionCandidate
  prepared <- liftIO (Candidate.prepareNativeServingCandidate assessment)
  candidate <- case prepared of
    Left failure -> do
      update report (\actual -> actual {nativeExecutionCandidateFailure = Just failure})
      throwError NativeExecutionCandidate
    Right actual -> pure actual

  stage report NativeExecutionComplete
  completion <- liftIO (Completed.prepareNativeCompletedServing candidate)
  completed <- case completion of
    Left failure -> do
      update report (\actual -> actual {nativeExecutionCompletionFailure = Just failure})
      throwError NativeExecutionComplete
    Right actual -> pure actual

  stage report NativeExecutionStore
  storedResult <- lift (Stored.storeNativeCompletedServing completed)
  stored <- case storedResult of
    Left failure -> do
      update
        report
        (\actual -> actual {nativeExecutionStored = Just (Stored.nativeStoredServingFailureReport failure)})
      throwError NativeExecutionStore
    Right actual -> do
      update
        report
        (\value -> value {nativeExecutionStored = Just (Stored.nativeStoredServingReport actual)})
      pure actual

  stage report NativeExecutionRetainReplays
  retainedResult <- lift (Retained.retainNativeServingReplays stored)
  retained <- case retainedResult of
    Left failure -> do
      update
        report
        ( \actual -> actual {nativeExecutionRetained = Just (Retained.nativeReplayRetentionFailureReport failure)}
        )
      throwError NativeExecutionRetainReplays
    Right actual -> do
      update
        report
        (\value -> value {nativeExecutionRetained = Just (Retained.nativeRetainedReplayReport actual)})
      pure actual

  stage report NativeExecutionPublishChild
  published <- lift (Publication.publishNativeQualification retained)
  publication <- case published of
    Left failure -> do
      update
        report
        ( \actual ->
            actual
              { nativeExecutionPublication = Just (Publication.nativeQualificationPublicationFailureReport failure)
              }
        )
      throwError NativeExecutionPublishChild
    Right actual -> do
      update
        report
        ( \value ->
            value {nativeExecutionPublication = Just (Publication.nativeQualificationPublicationReport actual)}
        )
      pure actual
  stage report NativeExecutionFinished
  pure publication

stage :: IORef NativeRlExecutionReport -> NativeRlExecutionStage -> Program ()
stage report value = update report (\actual -> actual {nativeExecutionStage = value})

update
  :: IORef NativeRlExecutionReport -> (NativeRlExecutionReport -> NativeRlExecutionReport) -> Program ()
update report = liftIO . modifyIORef' report

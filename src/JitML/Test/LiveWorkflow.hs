{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | The single resource-safe interpreter used by live workflow tests.
--
-- The protocol and evidence reducer stay pure.  This module owns only the IO
-- shell: it acquires a validated placement, waits for the typed subscription
-- to connect before publishing, settles every receipt through the persistent
-- consumer, and gathers diagnostics before releasing owned resources.
-- Workload workflows join independently observed terminal success with the
-- latest complete evidence; typed executable commands use successful process
-- completion, while request/reply workflows treat their validated response as
-- completion without inventing a workload.  Both successful and failed runs
-- retain their complete append-only scenario journal.
module JitML.Test.LiveWorkflow
  ( CleanupIssue (..)
  , CompletedRunEvidence
  , CompletionJoin
  , CompletionJoinError (..)
  , HostRunHandle
  , JobHandle
  , LiveBackend (..)
  , LiveCommand (..)
  , LiveCompletionMode (..)
  , LiveDiagnostic (..)
  , LiveDisposition (..)
  , LiveJournalEvent (..)
  , LiveJournalRecord (..)
  , LivePrimaryFailure (..)
  , LiveRunFailure (..)
  , LiveTransport (..)
  , LiveTerminalFact (..)
  , LiveWorkflow (..)
  , Placement (..)
  , PlacementHandleError (..)
  , ProbeFailure (..)
  , RequestHandle
  , ResourceFailure (..)
  , WorkloadFailure (..)
  , WorkloadObservation (..)
  , completedRunDiagnostics
  , completedRunEvidence
  , completedRunJournal
  , completedRunPlanId
  , completedRunPlacement
  , completedRunTerminal
  , completionJoinEvidence
  , completionJoinTerminal
  , emptyCompletionJoin
  , hostRunHandleKey
  , hostRunHandlePlanId
  , jobHandleName
  , jobHandlePlanId
  , joinedCompletion
  , liveCommandCanonicalText
  , mkHostRunHandle
  , mkJobHandle
  , mkRequestHandle
  , placementPlanId
  , requestHandleKey
  , requestHandlePlanId
  , runLiveWorkflow
  , withOwnedCleanup
  , withOwnedCleanupObserved
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async
  ( Async
  , cancel
  , wait
  , waitCatch
  , waitEitherCatch
  , withAsync
  )
import Control.Concurrent.MVar
  ( MVar
  , newEmptyMVar
  , putMVar
  , readMVar
  , tryPutMVar
  )
import Control.Exception
  ( SomeAsyncException
  , SomeException
  , bracket
  , fromException
  , mask
  , throwIO
  , try
  )
import Control.Exception.Safe (generalBracket)
import Control.Monad (void, when)
import Data.Char (isAsciiLower, isDigit)
import Data.IORef
  ( IORef
  , atomicModifyIORef'
  , newIORef
  , readIORef
  , writeIORef
  )
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Timeout qualified as Timeout

import JitML.CLI.Output qualified as Output
import JitML.Coordinator.Topology
  ( Topic
  , encodeTopicPayload
  , topicName
  )
import JitML.Plan.Plan (PlanId, Validation (..))
import JitML.Service.Capabilities
  ( ConsumerDecision
  , ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , Delivery
  , NackReason (..)
  , Subscription
  , ack
  , continue
  , deliveryEvent
  , deliveryReceipt
  , deliveryReceiptFingerprint
  , deliveryRedeliveryCount
  , done
  , nack
  , subscriptionName
  , subscriptionTopic
  )
import JitML.Service.Retry (ServiceError)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..))

-- | A Kubernetes Job name coupled to the plan that is allowed to observe and
-- clean it up.  The constructor is private; Kubernetes DNS-label validation
-- happens once at the raw boundary.
data JobHandle = JobHandle
  { jobPlanIdValue :: PlanId
  , jobNameValue :: Text
  }
  deriving stock (Eq, Show)

-- | A host-resident action key coupled to the plan that owns it.  The opaque
-- key is validated as non-empty and bounded before entering the interpreter.
data HostRunHandle = HostRunHandle
  { hostPlanIdValue :: PlanId
  , hostKeyValue :: Text
  }
  deriving stock (Eq, Show)

-- | A request/reply identity coupled to its plan.  Unlike 'HostRunHandle',
-- this does not claim that a long-running host workload exists; the reply
-- evidence itself is the terminal fact for this placement.
data RequestHandle = RequestHandle
  { requestPlanIdValue :: PlanId
  , requestKeyValue :: Text
  }
  deriving stock (Eq, Show)

data PlacementHandleError
  = EmptyPlacementHandle
  | PlacementHandleTooLong Int
  | InvalidJobHandleCharacter Char
  | InvalidJobHandleBoundary
  deriving stock (Eq, Show)

mkJobHandle :: PlanId -> Text -> Either PlacementHandleError JobHandle
mkJobHandle planId rawName = do
  let name = Text.strip rawName
  validateHandleLength name 63
  case Text.find (not . validJobCharacter) name of
    Just character -> Left (InvalidJobHandleCharacter character)
    Nothing -> Right ()
  case (Text.uncons name, Text.unsnoc name) of
    (Just (first, _), Just (_, lastCharacter))
      | validJobBoundary first && validJobBoundary lastCharacter ->
          Right JobHandle {jobPlanIdValue = planId, jobNameValue = name}
    _ -> Left InvalidJobHandleBoundary
 where
  validJobCharacter character =
    isAsciiLower character || isDigit character || character == '-'
  validJobBoundary character = isAsciiLower character || isDigit character

mkHostRunHandle :: PlanId -> Text -> Either PlacementHandleError HostRunHandle
mkHostRunHandle planId rawKey = do
  let key = Text.strip rawKey
  validateHandleLength key 128
  Right HostRunHandle {hostPlanIdValue = planId, hostKeyValue = key}

mkRequestHandle :: PlanId -> Text -> Either PlacementHandleError RequestHandle
mkRequestHandle planId rawKey = do
  let key = Text.strip rawKey
  validateHandleLength key 128
  Right RequestHandle {requestPlanIdValue = planId, requestKeyValue = key}

-- These are ordinary read-only functions rather than exported record labels.
-- A hidden constructor is still record-updateable downstream when one of its
-- labels is exported, which would let a validated handle be rebound to a
-- different plan or raw key after refinement.
jobHandlePlanId :: JobHandle -> PlanId
jobHandlePlanId = jobPlanIdValue

jobHandleName :: JobHandle -> Text
jobHandleName = jobNameValue

hostRunHandlePlanId :: HostRunHandle -> PlanId
hostRunHandlePlanId = hostPlanIdValue

hostRunHandleKey :: HostRunHandle -> Text
hostRunHandleKey = hostKeyValue

requestHandlePlanId :: RequestHandle -> PlanId
requestHandlePlanId = requestPlanIdValue

requestHandleKey :: RequestHandle -> Text
requestHandleKey = requestKeyValue

validateHandleLength :: Text -> Int -> Either PlacementHandleError ()
validateHandleLength value maximumLength
  | Text.null value = Left EmptyPlacementHandle
  | Text.length value > maximumLength = Left (PlacementHandleTooLong (Text.length value))
  | otherwise = Right ()

-- | Placement is a closed sum.  Host work can never accidentally flow through
-- cluster-only cleanup, and absence is represented by 'WorkloadObservation'.
data Placement
  = ClusterJob JobHandle
  | HostRun HostRunHandle
  | RequestReply RequestHandle
  deriving stock (Eq, Show)

placementPlanId :: Placement -> PlanId
placementPlanId placement =
  case placement of
    ClusterJob handle -> jobHandlePlanId handle
    HostRun handle -> hostRunHandlePlanId handle
    RequestReply handle -> requestHandlePlanId handle

newtype LiveDiagnostic = LiveDiagnostic {unLiveDiagnostic :: Text}
  deriving stock (Eq, Show)

newtype WorkloadFailure = WorkloadFailure {unWorkloadFailure :: Text}
  deriving stock (Eq, Show)

newtype ProbeFailure = ProbeFailure {unProbeFailure :: Text}
  deriving stock (Eq, Show)

newtype ResourceFailure = ResourceFailure {unResourceFailure :: Text}
  deriving stock (Eq, Show)

newtype CleanupIssue = CleanupIssue {unCleanupIssue :: Text}
  deriving stock (Eq, Show)

-- | Every legal observation is explicit.  In particular, a failed probe is
-- not collapsed into a missing resource and success carries its terminal
-- witness rather than a Boolean.
data WorkloadObservation terminal
  = Missing LiveDiagnostic
  | Pending LiveDiagnostic
  | Running LiveDiagnostic
  | Succeeded terminal
  | Failed WorkloadFailure
  | ProbeFailed ProbeFailure
  deriving stock (Eq, Show)

-- | Pure, arrival-order-independent join of the two independent completion
-- facts.  Duplicate equal facts are idempotent; conflicting duplicates fail.
data CompletionJoin terminal evidence
  = AwaitingTerminalAndEvidence
  | AwaitingTerminal evidence
  | AwaitingEvidence terminal
  | CompletionJoined terminal evidence
  deriving stock (Eq, Show)

data CompletionJoinError
  = ConflictingTerminalObservation
  | ConflictingCompletedEvidence
  deriving stock (Eq, Show)

emptyCompletionJoin :: CompletionJoin terminal evidence
emptyCompletionJoin = AwaitingTerminalAndEvidence

completionJoinTerminal
  :: (Eq terminal)
  => terminal
  -> CompletionJoin terminal evidence
  -> Either CompletionJoinError (CompletionJoin terminal evidence)
completionJoinTerminal terminal joinState =
  case joinState of
    AwaitingTerminalAndEvidence -> Right (AwaitingEvidence terminal)
    AwaitingTerminal evidence -> Right (CompletionJoined terminal evidence)
    AwaitingEvidence existing
      | existing == terminal -> Right joinState
      | otherwise -> Left ConflictingTerminalObservation
    CompletionJoined existing _
      | existing == terminal -> Right joinState
      | otherwise -> Left ConflictingTerminalObservation

completionJoinEvidence
  :: (Eq evidence)
  => evidence
  -> CompletionJoin terminal evidence
  -> Either CompletionJoinError (CompletionJoin terminal evidence)
completionJoinEvidence evidence joinState =
  case joinState of
    AwaitingTerminalAndEvidence -> Right (AwaitingTerminal evidence)
    AwaitingTerminal existing
      | existing == evidence -> Right joinState
      | otherwise -> Left ConflictingCompletedEvidence
    AwaitingEvidence terminal -> Right (CompletionJoined terminal evidence)
    CompletionJoined _ existing
      | existing == evidence -> Right joinState
      | otherwise -> Left ConflictingCompletedEvidence

joinedCompletion :: CompletionJoin terminal evidence -> Maybe (terminal, evidence)
joinedCompletion joinState =
  case joinState of
    CompletionJoined terminal evidence -> Just (terminal, evidence)
    _ -> Nothing

-- | Effectful protocol transport fixed to one command type and one event
-- type.  Integration backends instantiate these fields through 'HasPulsar';
-- callers cannot publish a command on an event topic or decode an unrelated
-- event type.
data LiveCommand command where
  ProtocolCommand :: Topic command -> command -> LiveCommand command
  -- | A typed executable command.  Its journal representation is always
  -- derived from the 'Subprocess' value by the canonical renderer; callers
  -- cannot supply a second raw label/payload that can drift from execution.
  ExecutableCommand :: Subprocess -> LiveCommand Subprocess

data LiveTransport command event = LiveTransport
  { livePublishCommand :: LiveCommand command -> IO (Either ServiceError Text)
  , liveConsumeEvents
      :: forall result
       . Subscription event
      -> (ConsumerSessionEvent -> IO ())
      -> (Delivery event -> IO (ConsumerDecision result))
      -> IO (Either ConsumerFailure result)
  }

-- | Pure protocol/evidence surface for one already-refined plan.  Protocol
-- topic witnesses render bytes, while executable commands use the canonical
-- typed subprocess renderer.  No second caller-supplied payload is accepted.
data LiveWorkflow command event progress evidence violation missing = LiveWorkflow
  { liveWorkflowPlanId :: PlanId
  , liveWorkflowCommand :: LiveCommand command
  , liveWorkflowEventSubscription :: Subscription event
  , liveWorkflowInitialProgress :: progress
  , liveWorkflowIngest :: progress -> event -> Either violation progress
  , liveWorkflowFinish :: progress -> Validation missing evidence
  , liveWorkflowRenderViolation :: violation -> Text
  }

-- | Placement-specific shell callbacks.  Independent workload observation is
-- polled in a separate supervised action from evidence consumption.  Request
-- completion never calls that observer, and executable completion is derived
-- from the typed process result.  Diagnostics always run before release.
data LiveBackend terminal = LiveBackend
  { liveAcquirePlacement :: IO (Either ResourceFailure Placement)
  , liveCompletionMode :: LiveCompletionMode
  , liveObserveWorkload :: Placement -> IO (WorkloadObservation terminal)
  , liveGatherDiagnostics :: Placement -> IO (Either CleanupIssue [LiveDiagnostic])
  , liveReleasePlacement :: Placement -> IO [CleanupIssue]
  , liveObservationAttempts :: Int
  , liveObservationDelayMicros :: Int
  , liveWorkflowTimeoutMicros :: Int
  }

-- | Protocol workflows either require an independently observed workload
-- terminal or are request/reply operations whose validated response evidence
-- is itself completion.  Executable commands have a third implicit mode: a
-- successful typed subprocess publication is their real terminal fact.
data LiveCompletionMode
  = ObserveIndependentWorkload
  | ResponseCompletesRequest
  deriving stock (Eq, Show)

data LiveTerminalFact terminal
  = IndependentWorkloadSucceeded terminal
  | ExecutableCommandSucceeded Text
  | RequestResponseCompleted
  deriving stock (Eq, Show)

data LiveJournalEvent terminal violation missing
  = PlacementAcquired Placement
  | ConsumerSessionObserved ConsumerSessionEvent
  | SubscriptionReady Text Text
  | SubscriptionReleased Text
  | CommandPublicationStarted Text Text
  | CommandPublished Text Text Text
  | CommandPublicationFailed ServiceError
  | DeliveryObserved Text Text Int Text
  | DeliveryDispositionSelected Text LiveDisposition
  | ProtocolEvidenceAccepted
  | ProtocolEvidenceIncomplete missing
  | ProtocolEvidenceRejected violation
  | ProtocolEvidenceCompleted
  | WorkloadStateObserved (WorkloadObservation terminal)
  | DiagnosticsGathered [LiveDiagnostic]
  | PlacementReleased Placement
  | CleanupRecorded CleanupIssue
  deriving stock (Eq, Show)

data LiveDisposition
  = LiveAck
  | LiveNack Text
  deriving stock (Eq, Show)

data LiveJournalRecord terminal violation missing = LiveJournalRecord
  { liveJournalSequence :: Word64
  , liveJournalEvent :: LiveJournalEvent terminal violation missing
  }
  deriving stock (Eq, Show)

data LivePrimaryFailure terminal violation missing
  = LiveAcquireFailed ResourceFailure
  | LivePlacementPlanMismatch PlanId PlanId
  | LivePublishFailed ServiceError
  | LiveConsumerFailed ConsumerFailure
  | LiveReducerRejected violation
  | LiveCompletionBoundaryMismatch Text
  | LiveWorkloadFailed WorkloadFailure
  | LiveProbeFailed ProbeFailure
  | LiveObservationExhausted (WorkloadObservation terminal)
  | LiveTimedOut (Maybe missing) (Maybe (WorkloadObservation terminal))
  | LiveInterpreterException Text
  deriving stock (Eq, Show)

-- | Failure keeps the primary reason, any successfully joined facts that
-- existed before cleanup, diagnostics, cleanup issues, and the full journal.
-- A cleanup-only failure has 'Nothing' in 'liveFailurePrimary' and a completed
-- pair in 'liveFailureCompletion'; cleanup can never overwrite the primary.
data LiveRunFailure terminal evidence violation missing = LiveRunFailure
  { liveFailurePrimary :: Maybe (LivePrimaryFailure terminal violation missing)
  , liveFailurePlacement :: Maybe Placement
  , liveFailureCompletion :: Maybe (LiveTerminalFact terminal, evidence)
  , liveFailureDiagnostics :: [LiveDiagnostic]
  , liveFailureCleanupIssues :: [CleanupIssue]
  , liveFailureJournal :: [LiveJournalRecord terminal violation missing]
  }
  deriving stock (Eq, Show)

-- | Internal result of the placed body and its subscription shutdown.  The
-- two fields are deliberately independent: a transport failure discovered
-- while shutting down must not erase terminal/evidence facts that were
-- already joined successfully by the body.
data PlacedRunResult terminal evidence violation missing = PlacedRunResult
  { placedRunPrimary :: Maybe (LivePrimaryFailure terminal violation missing)
  , placedRunCompletion :: Maybe (LiveTerminalFact terminal, evidence)
  }

-- | The constructor is private: only the interpreter can mint completed run
-- evidence after the completion mode's real terminal fact and cleanup have
-- succeeded.
data CompletedRunEvidence terminal evidence violation missing = CompletedRunEvidence
  { completedPlacementValue :: Placement
  , completedTerminalValue :: LiveTerminalFact terminal
  , completedEvidenceValue :: evidence
  , completedDiagnosticsValue :: [LiveDiagnostic]
  , completedJournalValue :: [LiveJournalRecord terminal violation missing]
  }
  deriving stock (Eq, Show)

-- | The semantic identity of the validated plan whose placement completed.
-- Keeping this accessor on the opaque completion value lets report projections
-- prove row/plan correlation without reopening the interpreter-owned
-- constructor.
completedRunPlanId :: CompletedRunEvidence terminal evidence violation missing -> PlanId
completedRunPlanId = placementPlanId . completedRunPlacement

-- Ordinary projections preserve the existing read API without exporting
-- record labels that could rewrite interpreter-owned completion evidence.
completedRunPlacement
  :: CompletedRunEvidence terminal evidence violation missing
  -> Placement
completedRunPlacement = completedPlacementValue

completedRunTerminal
  :: CompletedRunEvidence terminal evidence violation missing
  -> LiveTerminalFact terminal
completedRunTerminal = completedTerminalValue

completedRunEvidence
  :: CompletedRunEvidence terminal evidence violation missing
  -> evidence
completedRunEvidence = completedEvidenceValue

completedRunDiagnostics
  :: CompletedRunEvidence terminal evidence violation missing
  -> [LiveDiagnostic]
completedRunDiagnostics = completedDiagnosticsValue

completedRunJournal
  :: CompletedRunEvidence terminal evidence violation missing
  -> [LiveJournalRecord terminal violation missing]
completedRunJournal = completedJournalValue

runLiveWorkflow
  :: (Eq terminal, Eq evidence)
  => LiveWorkflow command event progress evidence violation missing
  -> LiveTransport command event
  -> LiveBackend terminal
  -> IO
       ( Either
           (LiveRunFailure terminal evidence violation missing)
           (CompletedRunEvidence terminal evidence violation missing)
       )
runLiveWorkflow workflow transport backend =
  do
    journalRef <- newIORef []
    sequenceRef <- newIORef 0
    diagnosticsRef <- newIORef Nothing
    releaseRef <- newIORef []
    subscriptionCleanupRef <- newIORef []
    let record = appendJournal journalRef sequenceRef
        gatherBeforeRelease placement = do
          existing <- readIORef diagnosticsRef
          case existing of
            Just _ -> pure ()
            Nothing -> do
              gathered <- gatherDiagnostics backend record placement
              writeIORef diagnosticsRef (Just gathered)
        releaseResource acquired =
          case acquired of
            Left _ -> pure ()
            Right placement -> do
              -- This is the final fallback for cancellation before the placed
              -- body starts.  On the normal path 'runPlaced' gathers while its
              -- subscription is still owned, so every later release is after
              -- diagnostics in the journal.
              gatherBeforeRelease placement
              releaseResult <- releasePlacement backend record placement
              writeIORef releaseRef releaseResult
        useResource acquired =
          case acquired of
            Left failure -> pure (Left failure)
            Right placement -> do
              record (PlacementAcquired placement)
              primaryResult <-
                if placementPlanId placement /= liveWorkflowPlanId workflow
                  then do
                    gatherBeforeRelease placement
                    pure
                      PlacedRunResult
                        { placedRunPrimary =
                            Just
                              ( LivePlacementPlanMismatch
                                  (liveWorkflowPlanId workflow)
                                  (placementPlanId placement)
                              )
                        , placedRunCompletion = Nothing
                        }
                  else do
                    actionResult <-
                      tryAny
                        ( runPlaced
                            workflow
                            transport
                            backend
                            record
                            subscriptionCleanupRef
                            (gatherBeforeRelease placement)
                            placement
                        )
                    -- Allocation failures before the consumer exists still
                    -- require diagnostics before the outer placement release.
                    gatherBeforeRelease placement
                    case actionResult of
                      Left exception ->
                        case (fromException exception :: Maybe SomeAsyncException) of
                          Just _asyncException ->
                            throwIO exception
                          Nothing ->
                            pure
                              PlacedRunResult
                                { placedRunPrimary =
                                    Just
                                      ( LiveInterpreterException
                                          (exceptionText exception)
                                      )
                                , placedRunCompletion = Nothing
                                }
                      Right result -> pure result
              pure (Right (placement, primaryResult))
    bracketed <-
      tryAny
        ( bracket
            (liveAcquirePlacement backend)
            releaseResource
            useResource
        )
    case bracketed of
      Left exception ->
        case (fromException exception :: Maybe SomeAsyncException) of
          Just _asyncException -> throwIO exception
          Nothing ->
            finishWithoutPlacement
              journalRef
              (LiveInterpreterException (exceptionText exception))
      Right (Left failure) ->
        finishWithoutPlacement journalRef (LiveAcquireFailed failure)
      Right (Right (placement, primaryResult)) -> do
        gathered <- readIORef diagnosticsRef
        placementCleanupIssues <- readIORef releaseRef
        subscriptionCleanupIssues <- readIORef subscriptionCleanupRef
        let (diagnostics, diagnosticIssues) =
              fromMaybe ([], []) gathered
        assembleResult
          journalRef
          placement
          ( diagnostics
          , diagnosticIssues
              <> subscriptionCleanupIssues
              <> placementCleanupIssues
          )
          primaryResult

-- | Scope resources that are owned by a live scenario but acquired outside
-- the placement backend, such as temporary object-store fixtures.  Cleanup is
-- run by 'generalBracket' on every exit.  On a normal interpreter return, all
-- cleanup issues are appended to the journal and the typed outcome without
-- replacing an existing primary or discarding completed facts.  A synchronous
-- exception before the interpreter can return becomes the primary failure;
-- asynchronous cancellation retains its identity after bracketed cleanup.
withOwnedCleanup
  :: IO [CleanupIssue]
  -> IO
       ( Either
           (LiveRunFailure terminal evidence violation missing)
           (CompletedRunEvidence terminal evidence violation missing)
       )
  -> IO
       ( Either
           (LiveRunFailure terminal evidence violation missing)
           (CompletedRunEvidence terminal evidence violation missing)
       )
withOwnedCleanup =
  withOwnedCleanupObserved reportAsyncCleanupIssues

withOwnedCleanupObserved
  :: ([CleanupIssue] -> IO ())
  -> IO [CleanupIssue]
  -> IO
       ( Either
           (LiveRunFailure terminal evidence violation missing)
           (CompletedRunEvidence terminal evidence violation missing)
       )
  -> IO
       ( Either
           (LiveRunFailure terminal evidence violation missing)
           (CompletedRunEvidence terminal evidence violation missing)
       )
withOwnedCleanupObserved observeAsyncCleanup cleanup action = do
  (actionResult, cleanupIssues) <-
    generalBracket
      (pure ())
      (\() _exitCase -> safeCleanup)
      (\() -> tryAny action)
  case actionResult of
    Left exception ->
      case (fromException exception :: Maybe SomeAsyncException) of
        Just _asyncException -> do
          case cleanupIssues of
            [] -> pure ()
            _ -> do
              _ <- tryAny (observeAsyncCleanup cleanupIssues)
              pure ()
          throwIO exception
        Nothing ->
          pure
            ( Left
                LiveRunFailure
                  { liveFailurePrimary =
                      Just (LiveInterpreterException (exceptionText exception))
                  , liveFailurePlacement = Nothing
                  , liveFailureCompletion = Nothing
                  , liveFailureDiagnostics = []
                  , liveFailureCleanupIssues = cleanupIssues
                  , liveFailureJournal = appendCleanupJournal [] cleanupIssues
                  }
            )
    Right result -> pure (retainCleanupIssues cleanupIssues result)
 where
  safeCleanup = do
    cleanupResult <- trySync cleanup
    pure $ case cleanupResult of
      Left exception ->
        [ CleanupIssue
            ("owned-resource cleanup threw: " <> exceptionText exception)
        ]
      Right issues -> issues

reportAsyncCleanupIssues :: [CleanupIssue] -> IO ()
reportAsyncCleanupIssues =
  mapM_
    ( \issue ->
        Output.writeErrorLineIO
          ("live workflow asynchronous cleanup failure: " <> unCleanupIssue issue)
    )

retainCleanupIssues
  :: [CleanupIssue]
  -> Either
       (LiveRunFailure terminal evidence violation missing)
       (CompletedRunEvidence terminal evidence violation missing)
  -> Either
       (LiveRunFailure terminal evidence violation missing)
       (CompletedRunEvidence terminal evidence violation missing)
retainCleanupIssues [] result = result
retainCleanupIssues issues result =
  case result of
    Left failure ->
      Left
        failure
          { liveFailureCleanupIssues =
              liveFailureCleanupIssues failure <> issues
          , liveFailureJournal =
              appendCleanupJournal (liveFailureJournal failure) issues
          }
    Right completed ->
      Left
        LiveRunFailure
          { liveFailurePrimary = Nothing
          , liveFailurePlacement = Just (completedRunPlacement completed)
          , liveFailureCompletion =
              Just
                ( completedRunTerminal completed
                , completedRunEvidence completed
                )
          , liveFailureDiagnostics = completedRunDiagnostics completed
          , liveFailureCleanupIssues = issues
          , liveFailureJournal =
              appendCleanupJournal (completedRunJournal completed) issues
          }

appendCleanupJournal
  :: [LiveJournalRecord terminal violation missing]
  -> [CleanupIssue]
  -> [LiveJournalRecord terminal violation missing]
appendCleanupJournal journal issues =
  journal
    <> cleanupRecords lastSequence issues
 where
  lastSequence =
    foldr
      (max . liveJournalSequence)
      0
      journal
  cleanupRecords _ [] = []
  cleanupRecords previousSequence (issue : remaining) =
    let sequenceNumber = previousSequence + 1
     in LiveJournalRecord sequenceNumber (CleanupRecorded issue)
          : cleanupRecords sequenceNumber remaining

finishWithoutPlacement
  :: IORef [LiveJournalRecord terminal violation missing]
  -> LivePrimaryFailure terminal violation missing
  -> IO (Either (LiveRunFailure terminal evidence violation missing) completed)
finishWithoutPlacement journalRef primary = do
  journal <- readJournal journalRef
  pure
    ( Left
        LiveRunFailure
          { liveFailurePrimary = Just primary
          , liveFailurePlacement = Nothing
          , liveFailureCompletion = Nothing
          , liveFailureDiagnostics = []
          , liveFailureCleanupIssues = []
          , liveFailureJournal = journal
          }
    )

runPlaced
  :: (Eq terminal, Eq evidence)
  => LiveWorkflow command event progress evidence violation missing
  -> LiveTransport command event
  -> LiveBackend terminal
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> IORef [CleanupIssue]
  -> IO ()
  -> Placement
  -> IO (PlacedRunResult terminal evidence violation missing)
runPlaced workflow transport backend record subscriptionCleanupRef gatherBeforeRelease placement = do
  case validateCompletionBoundary
    (liveWorkflowCommand workflow)
    (liveCompletionMode backend)
    placement of
    Left detail -> do
      gatherBeforeRelease
      pure
        PlacedRunResult
          { placedRunPrimary = Just (LiveCompletionBoundaryMismatch detail)
          , placedRunCompletion = Nothing
          }
    Right () -> do
      connected <- newEmptyMVar
      published <- newEmptyMVar
      evidenceReady <- newEmptyMVar
      evidenceRef <- newIORef Nothing
      progressRef <- newIORef (liveWorkflowInitialProgress workflow)
      observationRef <- newIORef Nothing
      let consume =
            consumeEvidence
              workflow
              transport
              record
              connected
              published
              evidenceReady
              evidenceRef
              progressRef
      withAsync consume $ \consumer ->
        -- Keep cancellation masked around the ownership hand-off.  The body is
        -- restored to its normal interruptibility, but every exit then cancels
        -- and reads the Async result before the outer scope can discard it.
        mask $ \restore -> do
          bodyAttempt <-
            tryAny . restore $
              withAsync (readMVar connected) $ \connection -> do
                connectionResult <- waitEitherCatch connection consumer
                case connectionResult of
                  Left (Left exception) ->
                    pure (Left (LiveInterpreterException (exceptionText exception)))
                  Left (Right ()) -> do
                    let (commandAddress, commandPayload) =
                          renderLiveCommand (liveWorkflowCommand workflow)
                    record (CommandPublicationStarted commandAddress commandPayload)
                    publication <-
                      livePublishCommand
                        transport
                        (liveWorkflowCommand workflow)
                    case publication of
                      Left failure -> do
                        record (CommandPublicationFailed failure)
                        pure (Left (LivePublishFailed failure))
                      Right acknowledgement -> do
                        record
                          ( CommandPublished
                              commandAddress
                              commandPayload
                              acknowledgement
                          )
                        putMVar published ()
                        joined <-
                          Timeout.timeout
                            (max 1 (liveWorkflowTimeoutMicros backend))
                            ( case liveWorkflowCommand workflow of
                                ExecutableCommand _ ->
                                  awaitEvidenceWhileConsuming
                                    consumer
                                    evidenceReady
                                    evidenceRef
                                    (ExecutableCommandSucceeded acknowledgement)
                                ProtocolCommand _ _ ->
                                  case liveCompletionMode backend of
                                    ResponseCompletesRequest ->
                                      awaitEvidenceWhileConsuming
                                        consumer
                                        evidenceReady
                                        evidenceRef
                                        RequestResponseCompleted
                                    ObserveIndependentWorkload ->
                                      awaitIndependentCompletion
                                        backend
                                        record
                                        observationRef
                                        placement
                                        consumer
                                        evidenceReady
                                        evidenceRef
                            )
                        case joined of
                          Just result -> pure result
                          Nothing -> do
                            progress <- readIORef progressRef
                            latestObservation <- readIORef observationRef
                            let missing =
                                  case liveWorkflowFinish workflow progress of
                                    Failure value -> Just value
                                    Success _ -> Nothing
                            pure (Left (LiveTimedOut missing latestObservation))
                  Right consumerResult -> do
                    cancel connection
                    pure (unexpectedConsumerCompletion "before command publication" consumerResult)
          -- Diagnostics belong to the still-live ownership scope.  A masked
          -- region can still receive cancellation at an interruptible
          -- diagnostics subprocess, so catch that exact exception, complete a
          -- masked retry while the consumer is still owned, and rethrow only
          -- after subscription shutdown.  The usual single-cancellation
          -- bracket guarantee therefore cannot let 'withAsync' release the
          -- subscription ahead of diagnostics.
          firstDiagnosticsAttempt <- tryAny gatherBeforeRelease
          diagnosticsCancellation <-
            case firstDiagnosticsAttempt of
              Right () -> pure Nothing
              Left exception ->
                case (fromException exception :: Maybe SomeAsyncException) of
                  Nothing -> pure (Just exception)
                  Just _asyncException -> do
                    gatherBeforeRelease
                    pure (Just exception)
          shutdownFailure <-
            shutdownEvidenceConsumer
              workflow
              record
              subscriptionCleanupRef
              consumer
          case bodyAttempt of
            Left exception -> throwIO exception
            Right bodyResult ->
              case diagnosticsCancellation of
                Just exception -> throwIO exception
                Nothing ->
                  pure $ case bodyResult of
                    Left primary ->
                      PlacedRunResult
                        { placedRunPrimary = Just primary
                        , placedRunCompletion = Nothing
                        }
                    Right completion ->
                      PlacedRunResult
                        { placedRunPrimary = shutdownFailure
                        , placedRunCompletion = Just completion
                        }

validateCompletionBoundary
  :: LiveCommand command
  -> LiveCompletionMode
  -> Placement
  -> Either Text ()
validateCompletionBoundary command completionMode placement =
  case (command, completionMode, placement) of
    (ExecutableCommand _, _, HostRun _) -> Right ()
    (ExecutableCommand _, _, _) ->
      Left "typed executable command requires a HostRun placement"
    (ProtocolCommand _ _, ResponseCompletesRequest, RequestReply _) -> Right ()
    (ProtocolCommand _ _, ResponseCompletesRequest, _) ->
      Left "request/response completion requires a RequestReply placement"
    (ProtocolCommand _ _, ObserveIndependentWorkload, RequestReply _) ->
      Left "RequestReply placement cannot claim an independent workload terminal"
    (ProtocolCommand _ _, ObserveIndependentWorkload, _) -> Right ()

awaitEvidenceWhileConsuming
  :: Async (Either (LivePrimaryFailure terminal violation missing) evidence)
  -> MVar ()
  -> IORef (Maybe evidence)
  -> LiveTerminalFact terminal
  -> IO
       ( Either
           (LivePrimaryFailure terminal violation missing)
           (LiveTerminalFact terminal, evidence)
       )
awaitEvidenceWhileConsuming consumer evidenceReady evidenceRef terminalFact =
  withAsync (readCompletedEvidence evidenceReady evidenceRef) $ \evidenceAsync -> do
    first <- waitEitherCatch consumer evidenceAsync
    case first of
      Left consumerResult -> do
        cancel evidenceAsync
        pure (unexpectedConsumerCompletion "before completion" consumerResult)
      Right evidenceResult -> do
        pure $ case evidenceResult of
          Left exception -> Left (LiveInterpreterException (exceptionText exception))
          Right evidence -> Right (terminalFact, evidence)

awaitIndependentCompletion
  :: (Eq terminal, Eq evidence)
  => LiveBackend terminal
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> IORef (Maybe (WorkloadObservation terminal))
  -> Placement
  -> Async (Either (LivePrimaryFailure terminal violation missing) evidence)
  -> MVar ()
  -> IORef (Maybe evidence)
  -> IO
       ( Either
           (LivePrimaryFailure terminal violation missing)
           (LiveTerminalFact terminal, evidence)
       )
awaitIndependentCompletion backend record observationRef placement consumer evidenceReady evidenceRef =
  withAsync (Right <$> readMVar evidenceReady) $ \evidenceAsync ->
    withAsync (observeTerminal backend record observationRef placement) $ \terminalAsync ->
      withAsync (joinEvidenceAndTerminal evidenceAsync terminalAsync) $ \completionAsync -> do
        first <- waitEitherCatch consumer completionAsync
        case first of
          Left consumerResult -> do
            cancel completionAsync
            pure (unexpectedConsumerCompletion "before independent terminal success" consumerResult)
          Right completionResult -> do
            case asyncResult completionResult of
              Left failure -> pure (Left failure)
              Right (terminal, ()) -> do
                evidence <- readIORef evidenceRef
                pure $ case evidence of
                  Nothing ->
                    Left
                      ( LiveInterpreterException
                          "independent terminal joined without stored evidence"
                      )
                  Just latestEvidence ->
                    Right
                      ( IndependentWorkloadSucceeded terminal
                      , latestEvidence
                      )

readCompletedEvidence :: MVar () -> IORef (Maybe evidence) -> IO evidence
readCompletedEvidence evidenceReady evidenceRef = do
  readMVar evidenceReady
  evidence <- readIORef evidenceRef
  case evidence of
    Just value -> pure value
    Nothing ->
      ioError
        ( userError
            "live workflow signalled completed evidence without storing it"
        )

unexpectedConsumerCompletion
  :: Text
  -> Either
       SomeException
       (Either (LivePrimaryFailure terminal violation missing) evidence)
  -> Either
       (LivePrimaryFailure terminal violation missing)
       completed
unexpectedConsumerCompletion context consumerResult =
  case asyncResult consumerResult of
    Left failure -> Left failure
    Right _ ->
      Left
        ( LiveInterpreterException
            ("event consumer completed " <> context)
        )

consumeEvidence
  :: LiveWorkflow command event progress evidence violation missing
  -> LiveTransport command event
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> MVar ()
  -> MVar ()
  -> MVar ()
  -> IORef (Maybe evidence)
  -> IORef progress
  -> IO (Either (LivePrimaryFailure terminal violation missing) evidence)
consumeEvidence workflow transport record connected published evidenceReady evidenceRef progressRef = do
  result <-
    liveConsumeEvents
      transport
      (liveWorkflowEventSubscription workflow)
      observeSession
      handleDelivery
  pure (consumerResultToPrimary result)
 where
  observeSession event = do
    record (ConsumerSessionObserved event)
    case event of
      ConsumerSessionConnected _generation -> do
        firstConnection <- tryPutMVar connected ()
        when firstConnection $
          record
            ( SubscriptionReady
                (subscriptionName (liveWorkflowEventSubscription workflow))
                ( topicName
                    (subscriptionTopic (liveWorkflowEventSubscription workflow))
                )
            )
      _ -> pure ()

  handleDelivery delivery = do
    -- No delivery can enter the reducer until publication has succeeded.
    readMVar published
    let event = deliveryEvent delivery
        receiptFingerprint =
          deliveryReceiptFingerprint (deliveryReceipt delivery)
    record
      ( DeliveryObserved
          ( topicName
              (subscriptionTopic (liveWorkflowEventSubscription workflow))
          )
          receiptFingerprint
          (deliveryRedeliveryCount delivery)
          ( encodeTopicPayload
              (subscriptionTopic (liveWorkflowEventSubscription workflow))
              event
          )
      )
    progress <- readIORef progressRef
    case liveWorkflowIngest workflow progress event of
      Left violation -> do
        let reason = liveWorkflowRenderViolation workflow violation
        record (ProtocolEvidenceRejected violation)
        record (DeliveryDispositionSelected receiptFingerprint (LiveNack reason))
        pure
          ( done
              (nack (HandlerRejected reason))
              (Left (LiveReducerRejected violation))
          )
      Right next -> do
        writeIORef progressRef next
        record ProtocolEvidenceAccepted
        case liveWorkflowFinish workflow next of
          Failure missing -> do
            record (ProtocolEvidenceIncomplete missing)
            record (DeliveryDispositionSelected receiptFingerprint LiveAck)
            pure (continue ack)
          Success evidence -> do
            writeIORef evidenceRef (Just evidence)
            record (DeliveryDispositionSelected receiptFingerprint LiveAck)
            record ProtocolEvidenceCompleted
            _ <- tryPutMVar evidenceReady ()
            pure (continue ack)

-- | Cancel the scoped event consumer and inspect its durable transport result.
-- 'consumePersistent' rethrows cancellation only after successful cleanup; an
-- owned-subscription deletion failure instead returns a typed cleanup failure.
-- Consequently an async exception confirms release, while the two cleanup
-- constructors must be retained and may never mint completed evidence.
shutdownEvidenceConsumer
  :: LiveWorkflow command event progress evidence violation missing
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> IORef [CleanupIssue]
  -> Async (Either (LivePrimaryFailure terminal violation missing) evidence)
  -> IO (Maybe (LivePrimaryFailure terminal violation missing))
shutdownEvidenceConsumer workflow record cleanupRef consumer = do
  cancel consumer
  result <- waitCatch consumer
  case result of
    Left exception ->
      case (fromException exception :: Maybe SomeAsyncException) of
        Just _asyncException -> released >> pure Nothing
        Nothing -> do
          let issue =
                CleanupIssue
                  ( "subscription cleanup was not confirmed after consumer exception for "
                      <> subscriptionLabel
                      <> ": "
                      <> exceptionText exception
                  )
          retain issue
          pure (Just (LiveInterpreterException (exceptionText exception)))
    Right (Right _evidence) -> released >> pure Nothing
    Right (Left primary) ->
      case primary of
        LiveConsumerFailed (ConsumerCleanupFailure cleanupError) -> do
          retain (cleanupIssue cleanupError)
          pure Nothing
        LiveConsumerFailed (ConsumerCleanupContextFailure consumerPrimary cleanupError) -> do
          retain (cleanupIssue cleanupError)
          pure (Just (LiveConsumerFailed consumerPrimary))
        _ -> released >> pure (Just primary)
 where
  subscription = liveWorkflowEventSubscription workflow
  subscriptionLabel =
    subscriptionName subscription
      <> " on "
      <> topicName (subscriptionTopic subscription)

  released = record (SubscriptionReleased (subscriptionName subscription))

  cleanupIssue cleanupError =
    CleanupIssue
      ( "subscription cleanup failed for "
          <> subscriptionLabel
          <> ": "
          <> Text.pack (show cleanupError)
      )

  retain issue = do
    atomicModifyIORef' cleanupRef $ \issues -> (issues <> [issue], ())
    record (CleanupRecorded issue)

observeTerminal
  :: LiveBackend terminal
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> IORef (Maybe (WorkloadObservation terminal))
  -> Placement
  -> IO (Either (LivePrimaryFailure terminal violation missing) terminal)
observeTerminal backend record observationRef placement =
  go (max 1 (liveObservationAttempts backend))
 where
  go remaining = do
    observation <- liveObserveWorkload backend placement
    writeIORef observationRef (Just observation)
    record (WorkloadStateObserved observation)
    case observation of
      Succeeded terminal -> pure (Right terminal)
      Failed failure -> pure (Left (LiveWorkloadFailed failure))
      ProbeFailed failure -> pure (Left (LiveProbeFailed failure))
      Missing _ -> continuePolling remaining observation
      Pending _ -> continuePolling remaining observation
      Running _ -> continuePolling remaining observation

  continuePolling remaining observation
    | remaining <= 1 = pure (Left (LiveObservationExhausted observation))
    | otherwise = do
        threadDelay (max 0 (liveObservationDelayMicros backend))
        go (remaining - 1)

joinEvidenceAndTerminal
  :: (Eq terminal, Eq evidence)
  => Async (Either (LivePrimaryFailure terminal violation missing) evidence)
  -> Async (Either (LivePrimaryFailure terminal violation missing) terminal)
  -> IO
       ( Either
           (LivePrimaryFailure terminal violation missing)
           (terminal, evidence)
       )
joinEvidenceAndTerminal evidenceAsync terminalAsync = do
  first <- waitEitherCatch evidenceAsync terminalAsync
  case first of
    Left evidenceResult ->
      case asyncResult evidenceResult of
        Left failure -> cancel terminalAsync >> pure (Left failure)
        Right evidence -> do
          terminalResult <- wait terminalAsync
          pure (terminalResult >>= completeEvidenceFirst evidence)
    Right terminalResult ->
      case asyncResult terminalResult of
        Left failure -> cancel evidenceAsync >> pure (Left failure)
        Right terminal -> do
          evidenceResult <- wait evidenceAsync
          pure (evidenceResult >>= completeTerminalFirst terminal)

completeEvidenceFirst
  :: (Eq terminal, Eq evidence)
  => evidence
  -> terminal
  -> Either (LivePrimaryFailure terminal violation missing) (terminal, evidence)
completeEvidenceFirst evidence terminal =
  completionPair $ do
    evidenceOnly <- completionJoinEvidence evidence emptyCompletionJoin
    completionJoinTerminal terminal evidenceOnly

completeTerminalFirst
  :: (Eq terminal, Eq evidence)
  => terminal
  -> evidence
  -> Either (LivePrimaryFailure terminal violation missing) (terminal, evidence)
completeTerminalFirst terminal evidence =
  completionPair $ do
    terminalOnly <- completionJoinTerminal terminal emptyCompletionJoin
    completionJoinEvidence evidence terminalOnly

completionPair
  :: Either CompletionJoinError (CompletionJoin terminal evidence)
  -> Either (LivePrimaryFailure terminal violation missing) (terminal, evidence)
completionPair result =
  case result >>= maybe (Left ConflictingCompletedEvidence) Right . joinedCompletion of
    Left failure -> Left (LiveInterpreterException (Text.pack (show failure)))
    Right pair -> Right pair

asyncResult
  :: Either
       SomeException
       (Either (LivePrimaryFailure terminal violation missing) value)
  -> Either (LivePrimaryFailure terminal violation missing) value
asyncResult result =
  case result of
    Left exception -> Left (LiveInterpreterException (exceptionText exception))
    Right value -> value

consumerResultToPrimary
  :: Either ConsumerFailure (Either (LivePrimaryFailure terminal violation missing) evidence)
  -> Either (LivePrimaryFailure terminal violation missing) evidence
consumerResultToPrimary result =
  case result of
    Left failure -> Left (LiveConsumerFailed failure)
    Right value -> value

renderLiveCommand :: LiveCommand command -> (Text, Text)
renderLiveCommand command =
  case command of
    ProtocolCommand topic payload ->
      (topicName topic, encodeTopicPayload topic payload)
    ExecutableCommand subprocessValue ->
      ( "subprocess:" <> Text.pack (subprocessPath subprocessValue)
      , renderSubprocess subprocessValue
      )

liveCommandCanonicalText :: LiveCommand command -> Text
liveCommandCanonicalText = snd . renderLiveCommand

gatherDiagnostics
  :: LiveBackend terminal
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> Placement
  -> IO ([LiveDiagnostic], [CleanupIssue])
gatherDiagnostics backend record placement = do
  diagnosticsResult <- trySync (liveGatherDiagnostics backend placement)
  case diagnosticsResult of
    Left exception -> do
      let issue = CleanupIssue ("diagnostics threw: " <> exceptionText exception)
      record (CleanupRecorded issue)
      pure ([], [issue])
    Right (Left issue) -> do
      record (CleanupRecorded issue)
      pure ([], [issue])
    Right (Right values) -> do
      record (DiagnosticsGathered values)
      pure (values, [])

releasePlacement
  :: LiveBackend terminal
  -> (LiveJournalEvent terminal violation missing -> IO ())
  -> Placement
  -> IO [CleanupIssue]
releasePlacement backend record placement = do
  cleanupResult <- trySync (liveReleasePlacement backend placement)
  case cleanupResult of
    Left exception -> do
      let issue = CleanupIssue ("placement cleanup threw: " <> exceptionText exception)
      record (CleanupRecorded issue)
      pure [issue]
    Right [] -> do
      record (PlacementReleased placement)
      pure []
    Right issues -> do
      mapM_ (record . CleanupRecorded) issues
      pure issues

assembleResult
  :: IORef [LiveJournalRecord terminal violation missing]
  -> Placement
  -> ([LiveDiagnostic], [CleanupIssue])
  -> PlacedRunResult terminal evidence violation missing
  -> IO
       ( Either
           (LiveRunFailure terminal evidence violation missing)
           (CompletedRunEvidence terminal evidence violation missing)
       )
assembleResult journalRef placement (diagnostics, cleanupIssues) result = do
  journal <- readJournal journalRef
  case (placedRunPrimary result, placedRunCompletion result, cleanupIssues) of
    (Nothing, Just (terminal, evidence), []) ->
      pure
        ( Right
            CompletedRunEvidence
              { completedPlacementValue = placement
              , completedTerminalValue = terminal
              , completedEvidenceValue = evidence
              , completedDiagnosticsValue = diagnostics
              , completedJournalValue = journal
              }
        )
    _ ->
      pure
        ( Left
            LiveRunFailure
              { liveFailurePrimary = placedRunPrimary result
              , liveFailurePlacement = Just placement
              , liveFailureCompletion = placedRunCompletion result
              , liveFailureDiagnostics = diagnostics
              , liveFailureCleanupIssues = cleanupIssues
              , liveFailureJournal = journal
              }
        )

appendJournal
  :: IORef [LiveJournalRecord terminal violation missing]
  -> IORef Word64
  -> LiveJournalEvent terminal violation missing
  -> IO ()
appendJournal journalRef sequenceRef event = do
  sequenceNumber <-
    atomicModifyIORef' sequenceRef $ \current ->
      let next = current + 1
       in (next, next)
  void $
    atomicModifyIORef' journalRef $ \records ->
      let updated = LiveJournalRecord sequenceNumber event : records
       in (updated, updated)

readJournal
  :: IORef [LiveJournalRecord terminal violation missing]
  -> IO [LiveJournalRecord terminal violation missing]
readJournal journalRef = reverse <$> readIORef journalRef

exceptionText :: SomeException -> Text
exceptionText = Text.pack . show

tryAny :: IO value -> IO (Either SomeException value)
tryAny = try

trySync :: IO value -> IO (Either SomeException value)
trySync action = do
  result <- tryAny action
  case result of
    Left exception ->
      case (fromException exception :: Maybe SomeAsyncException) of
        Just _asyncException -> throwIO exception
        Nothing -> pure (Left exception)
    Right value -> pure (Right value)

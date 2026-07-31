{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module JitML.Test.RunContract
  ( runContractTests
  )
where

import Control.Concurrent.Async (AsyncCancelled (..), async, cancel, waitCatch)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar)
import Control.Exception (fromException, throwIO, try)
import Data.Foldable (traverse_)
import Data.IORef (atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, permutations)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Coordinator.Topology (ProtocolRoute (..), topicFor)
import JitML.Numerics.LayerGraphMetadata
  ( layerGraphMetadataFromGraph
  , layerGraphMetadataParameterCount
  )
import JitML.Plan.Plan
  ( EventId
  , FiniteMeasurement
  , PlanId
  , Quantity
  , RunKind (..)
  , RunKindWitness (..)
  , Unit (..)
  , Validation (..)
  , deriveEventIdForPlanId
  , finiteMeasurementValue
  , mkFiniteMeasurement
  , mkQuantity
  , planIdFromCanonicalText
  , planIdText
  , quantityValue
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Run.Contract
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Service.Capabilities
  ( ConsumerSessionEvent (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , mkSubscription
  )
import JitML.Service.Pulsar.Internal qualified as PulsarInternal
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as TrainingBudget

runContractTests :: TestTree
runContractTests =
  testGroup
    "RunContract"
    [ testCase "exactlyOne reports missing evidence" $ do
        let contract = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
        finishContract contract (initialProgress contract)
          @?= Failure (MissingExactlyOne "terminal-checkpoint" :| [])
    , testCase "exactlyOne accepts one event" $ do
        let contract = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
            event = refinedEvidence planA "checkpoint" () ("manifest-a" :: Text)
        progress <- expectRight (ingestEvent contract (initialProgress contract) event)
        exactlyOneValue
          <$> finishContract contract progress
            @?= Success "manifest-a"
    , testCase "same EventId redelivery is idempotent" $ do
        let contract = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
            event = refinedEvidence planA "checkpoint" () ("manifest-a" :: Text)
        once <- expectRight (ingestEvent contract (initialProgress contract) event)
        twice <- expectRight (ingestEvent contract once event)
        twice @?= once
        exactlyOneValue
          <$> finishContract contract twice
            @?= Success "manifest-a"
    , testCase "same EventId with conflicting value is rejected" $ do
        let contract = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
            first = refinedEvidence planA "checkpoint" () ("manifest-a" :: Text)
            conflicting = refinedEvidence planA "checkpoint" () ("manifest-b" :: Text)
        progress <- expectRight (ingestEvent contract (initialProgress contract) first)
        ingestEvent contract progress conflicting
          @?= Left
            ConflictingDuplicate
              { violationRequirement = "terminal-checkpoint"
              , violationKey = "()"
              , violationExistingEventId = checkpointEventId
              , violationIncomingEventId = checkpointEventId
              }
    , testCase "same key with a different EventId is rejected" $ do
        let contract = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
            first = refinedEvidence planA "checkpoint" () ("manifest-a" :: Text)
            duplicate = refinedEvidence planA "checkpoint-alternate" () ("manifest-a" :: Text)
        progress <- expectRight (ingestEvent contract (initialProgress contract) first)
        ingestEvent contract progress duplicate
          @?= Left
            ConflictingDuplicate
              { violationRequirement = "terminal-checkpoint"
              , violationKey = "()"
              , violationExistingEventId = checkpointEventId
              , violationIncomingEventId = secondCheckpointEventId
              }
    , testCase "wrong-plan evidence is rejected before insertion" $ do
        let contract = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
            event = refinedEvidence planB "checkpoint" () ("manifest-a" :: Text)
        ingestEvent contract (initialProgress contract) event
          @?= Left
            WrongPlan
              { violationRequirement = "terminal-checkpoint"
              , violationExpectedPlan = planA
              , violationObservedPlan = planB
              }
    , testCase "atLeastOne rejects empty and accepts keyed evidence" $ do
        let contract = atLeastOne "telemetry" planA :: AtLeastTextContract
            first = refinedEvidence planA "telemetry" (0 :: Int) ("loss=1.0" :: Text)
            second = refinedEvidence planA "telemetry" 1 ("loss=0.5" :: Text)
        finishContract contract (initialProgress contract)
          @?= Failure (MissingAtLeastOne "telemetry" :| [])
        progress1 <- expectRight (ingestEvent contract (initialProgress contract) second)
        progress2 <- expectRight (ingestEvent contract progress1 first)
        atLeastOneValues
          <$> finishContract contract progress2
            @?= Success ((0, "loss=1.0") :| [(1, "loss=0.5")])
    , testCase "exactKeyedRange is arrival-order independent" $ do
        let contract = exactKeyedRange "evaluation-cohort" planA (0 :| [1, 2]) :: ExactIntContract
            event0 = refinedEvidence planA "evaluation" 0 (10.0 :: Double)
            event1 = refinedEvidence planA "evaluation" 1 20.0
            event2 = refinedEvidence planA "evaluation" 2 30.0
            expected = Success (Map.fromList [(0, 10.0), (1, 20.0), (2, 30.0)])
        traverse_
          ( \arrivalOrder -> do
              progress <- ingestAll contract arrivalOrder
              exactKeyedValues <$> finishContract contract progress @?= expected
          )
          (permutations [event0, event1, event2])
    , testCase "exactKeyedRange rejects out-of-range keys" $ do
        let contract = exactKeyedRange "evaluation-cohort" planA (0 :| [1, 2]) :: ExactIntContract
            event = refinedEvidence planA "evaluation" 3 (40.0 :: Double)
        ingestEvent contract (initialProgress contract) event
          @?= Left
            OutOfRangeKey
              { violationRequirement = "evaluation-cohort"
              , violationKey = "3"
              }
    , testCase "exactKeyedRange reports every missing key" $ do
        let contract = exactKeyedRange "evaluation-cohort" planA (0 :| [1, 2]) :: ExactIntContract
            event = refinedEvidence planA "evaluation" 0 (10.0 :: Double)
        progress <- expectRight (ingestEvent contract (initialProgress contract) event)
        finishContract contract progress
          @?= Failure (MissingKeys "evaluation-cohort" ("1" :| ["2"]) :| [])
    , testCase "exactKeyedRange rejects conflicting keyed duplicates" $ do
        let contract = exactKeyedRange "evaluation-cohort" planA (0 :| [1]) :: ExactIntContract
            first = refinedEvidence planA "evaluation" 0 (10.0 :: Double)
            conflicting = refinedEvidence planA "telemetry" 0 11.0
        progress <- expectRight (ingestEvent contract (initialProgress contract) first)
        ingestEvent contract progress conflicting
          @?= Left
            ConflictingDuplicate
              { violationRequirement = "evaluation-cohort"
              , violationKey = "0"
              , violationExistingEventId = evaluationEvent0
              , violationIncomingEventId = telemetryEvent0
              }
    , testCase "productContract accumulates independent missing evidence" $ do
        let checkpoint = exactlyOne "terminal-checkpoint" planA :: ExactlyTextContract
            terminalMetric = exactlyOne "terminal-metric" planA :: ExactlyTextContract
            contract = productContract checkpoint terminalMetric
        finishContract contract (initialProgress contract)
          @?= Failure
            ( MissingExactlyOne "terminal-checkpoint"
                :| [MissingExactlyOne "terminal-metric"]
            )
    , testCase "progress, learning-curve, and final-evaluation evidence are nominally distinct" $ do
        let progress = trainingProgress updateEventId oneOptimizerUpdate
            curve = learningCurveObservation curveEventId curveMeasurement
            final = finalEvaluationObservation evaluationEvent0 finalMeasurement
        trainingProgressEventId progress @?= updateEventId
        quantityValue (trainingProgressQuantity progress) @?= 1
        learningCurveEventId curve @?= curveEventId
        finiteMeasurementValue (learningCurveMeasurement curve) @?= 0.75
        finalEvaluationEventId final @?= evaluationEvent0
        finiteMeasurementValue (finalEvaluationMeasurement final) @?= 42.0
    , testCase "terminal success and complete evidence join in either arrival order" $ do
        let evidenceFirst = do
              awaitingTerminal <-
                LiveWorkflow.completionJoinEvidence
                  ("checkpoint-proof" :: Text)
                  LiveWorkflow.emptyCompletionJoin
              LiveWorkflow.completionJoinTerminal ("job-succeeded" :: Text) awaitingTerminal
            terminalFirst = do
              awaitingEvidence <-
                LiveWorkflow.completionJoinTerminal
                  ("job-succeeded" :: Text)
                  LiveWorkflow.emptyCompletionJoin
              LiveWorkflow.completionJoinEvidence ("checkpoint-proof" :: Text) awaitingEvidence
        (LiveWorkflow.joinedCompletion =<< eitherToMaybe evidenceFirst)
          @?= Just ("job-succeeded", "checkpoint-proof")
        (LiveWorkflow.joinedCompletion =<< eitherToMaybe terminalFirst)
          @?= Just ("job-succeeded", "checkpoint-proof")
    , testCase "neither terminal success nor evidence alone completes a run" $ do
        let terminalOnly =
              LiveWorkflow.completionJoinTerminal
                ("job-succeeded" :: Text)
                (LiveWorkflow.emptyCompletionJoin :: LiveWorkflow.CompletionJoin Text Text)
            evidenceOnly =
              LiveWorkflow.completionJoinEvidence
                ("checkpoint-proof" :: Text)
                (LiveWorkflow.emptyCompletionJoin :: LiveWorkflow.CompletionJoin Text Text)
        (terminalOnly >>= maybeToEither . LiveWorkflow.joinedCompletion)
          @?= Left LiveWorkflow.ConflictingCompletedEvidence
        (evidenceOnly >>= maybeToEither . LiveWorkflow.joinedCompletion)
          @?= Left LiveWorkflow.ConflictingCompletedEvidence
    , testCase "completion join rejects conflicting duplicate facts" $ do
        let terminalConflict = do
              once <-
                LiveWorkflow.completionJoinTerminal
                  ("job-a" :: Text)
                  (LiveWorkflow.emptyCompletionJoin :: LiveWorkflow.CompletionJoin Text Text)
              LiveWorkflow.completionJoinTerminal "job-b" once
            evidenceConflict = do
              once <-
                LiveWorkflow.completionJoinEvidence
                  ("proof-a" :: Text)
                  (LiveWorkflow.emptyCompletionJoin :: LiveWorkflow.CompletionJoin Text Text)
              LiveWorkflow.completionJoinEvidence "proof-b" once
        terminalConflict @?= Left LiveWorkflow.ConflictingTerminalObservation
        evidenceConflict @?= Left LiveWorkflow.ConflictingCompletedEvidence
    , testCase "placement handles validate keys before cleanup can address them" $ do
        case LiveWorkflow.mkJobHandle planA "jitml-train-plan-a" of
          Left err -> assertFailure ("expected valid Job handle, got " <> show err)
          Right handle -> do
            LiveWorkflow.jobHandlePlanId handle @?= planA
            LiveWorkflow.jobHandleName handle @?= "jitml-train-plan-a"
        LiveWorkflow.mkJobHandle planA "JitML-invalid"
          @?= Left (LiveWorkflow.InvalidJobHandleCharacter 'J')
        LiveWorkflow.mkHostRunHandle planA "   "
          @?= Left LiveWorkflow.EmptyPlacementHandle
    , testCase "typed executable commands have one canonical renderer" $ do
        let command = subprocess "jitml" ["internal", "gc", "example"]
            liveCommand = LiveWorkflow.ExecutableCommand command
        LiveWorkflow.liveCommandCanonicalText liveCommand
          @?= renderSubprocess command
    , testCase "request/reply completion mints no synthetic host workload terminal" $ do
        (result, observerCalls) <- runFakeRequestWorkflow
        observerCalls @?= 0
        case result of
          Left _ -> assertFailure "expected completed request/reply workflow"
          Right completed -> do
            LiveWorkflow.completedRunTerminal completed
              @?= LiveWorkflow.RequestResponseCompleted
            case LiveWorkflow.completedRunPlacement completed of
              LiveWorkflow.RequestReply handle ->
                LiveWorkflow.requestHandleKey handle @?= "fake-request"
              placement ->
                assertFailure ("request used a non-request placement: " <> show placement)
    , testCase "live RL evidence rejects gaps, out-of-range keys, and non-finite rewards" $ do
        contract <- expectRight (LiveEvidence.rlLiveContract planA 2)
        let outOfRange =
              Rl.RlEpisode
                Rl.EpisodeDone
                  { Rl.edExperimentHash = "rl-live"
                  , Rl.edEpisode = 2
                  , Rl.edReward = 1.0
                  , Rl.edSteps = 4
                  , Rl.edTimestampNs = 1
                  }
            notFinite =
              Rl.RlEpisode
                Rl.EpisodeDone
                  { Rl.edExperimentHash = "rl-live"
                  , Rl.edEpisode = 0
                  , Rl.edReward = 0 / 0
                  , Rl.edSteps = 4
                  , Rl.edTimestampNs = 1
                  }
            ingest =
              LiveEvidence.ingestRlLiveEvent
                planA
                Nothing
                "rl-live"
                contract
                (initialProgress contract)
        ingest outOfRange
          @?= Left
            ( LiveEvidence.LiveEvidenceContractViolation
                OutOfRangeKey
                  { violationRequirement = "rl-final-evaluation"
                  , violationKey = "2"
                  }
            )
        case ingest notFinite of
          Left (LiveEvidence.LiveEvidenceMalformed _) -> pure ()
          result -> assertFailure ("expected non-finite reward rejection, got " <> show result)
    , testCase "supervised live evidence is one terminal snapshot plus completed checkpoint" $ do
        contract <- expectRight (LiveEvidence.supervisedLiveContract planA 3)
        let initial = initialProgress contract
            ingest =
              LiveEvidence.ingestSupervisedLiveEvent
                planA
                "supervised-live"
                contract
            terminalEpoch = supervisedEpochEvent "supervised-live" 3 0.25
            earlierEpoch = supervisedEpochEvent "supervised-live" 2 0.5
            nonFiniteEpoch = supervisedEpochEvent "supervised-live" 3 (0 / 0)
            completedCheckpoint =
              supervisedCompletedCheckpointEvent
                planA
                3
                "supervised-live"
            wrongPlanCheckpoint =
              supervisedCompletedCheckpointEvent
                planB
                3
                "supervised-live"
        ingest initial earlierEpoch
          @?= Left
            ( LiveEvidence.LiveEvidenceContractViolation
                OutOfRangeKey
                  { violationRequirement = "supervised-terminal-epoch"
                  , violationKey = "2"
                  }
            )
        case ingest initial nonFiniteEpoch of
          Left (LiveEvidence.LiveEvidenceMalformed _) -> pure ()
          result ->
            assertFailure
              ("expected non-finite terminal epoch rejection, got " <> show result)
        terminalProgress <- expectRight (ingest initial terminalEpoch)
        finishContract contract terminalProgress
          @?= Failure
            ( MissingExactlyOne "supervised-completed-checkpoint"
                :| []
            )
        ingest terminalProgress wrongPlanCheckpoint
          @?= Left (LiveEvidence.LiveEvidencePlanMismatch planA planB)
        completedProgress <-
          expectRight (ingest terminalProgress completedCheckpoint)
        case finishContract contract completedProgress of
          Failure missing ->
            assertFailure
              ("terminal snapshot plus completed checkpoint stayed incomplete: " <> show missing)
          Success evidence -> do
            Map.keys (LiveEvidence.supervisedTerminalEpochSnapshot evidence)
              @?= [3]
            Training.ccdCheckpoint
              (LiveEvidence.supervisedCompletedCheckpoint evidence)
              @?= trainingCheckpointEvent 3 "supervised-live"
    , testCase "runLiveWorkflow subscribes before publish and releases exactly once" $ do
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planA
            (LiveWorkflow.Succeeded "job-complete")
            []
            Nothing
        releaseCount @?= 1
        case result of
          Left failure -> assertFailure ("expected completed fake workflow, got " <> show failure)
          Right completed -> do
            exactlyOneValue (LiveWorkflow.completedRunEvidence completed)
              @?= "proof"
            let journal = LiveWorkflow.completedRunJournal completed
                subscribed =
                  [ LiveWorkflow.liveJournalSequence record
                  | record <- journal
                  , LiveWorkflow.SubscriptionReady {} <- [LiveWorkflow.liveJournalEvent record]
                  ]
                published =
                  [ LiveWorkflow.liveJournalSequence record
                  | record <- journal
                  , LiveWorkflow.CommandPublished {} <- [LiveWorkflow.liveJournalEvent record]
                  ]
            case (subscribed, published) of
              (subscribedAt : _, publishedAt : _) ->
                assertBool
                  "subscription readiness precedes command publication"
                  (subscribedAt < publishedAt)
              _ -> assertFailure ("missing subscribe/publish journal entries: " <> show journal)
    , testCase "runLiveWorkflow rejects a conflicting event after evidence completes but before terminal" $ do
        let contract = exactlyOne "late-conflict" planA :: ExactlyTextContract
            completeEvent = trainingEvidenceEvent 1 0.5
            conflictingEvent = trainingEvidenceEvent 2 0.75
            ingest progress event =
              ingestEvent
                contract
                progress
                ( refinedEvidence
                    planA
                    "late-conflict"
                    ()
                    ( if event == completeEvent
                        then "proof-a"
                        else "proof-b"
                    )
                )
        assertLateEvidenceRejected
          completeEvent
          conflictingEvent
          (initialProgress contract)
          ingest
          (finishContract contract)
          (\case ConflictingDuplicate {} -> True; _ -> False)
    , testCase
        "runLiveWorkflow rejects an out-of-range event after evidence completes but before terminal"
        $ do
          let contract =
                exactKeyedRange "late-range" planA (0 :| [])
                  :: Contract (EvidenceEvent Int Text) (RequirementState Int Text) (ExactKeyed Int Text)
              completeEvent = trainingEvidenceEvent 0 0.5
              outOfRangeEvent = trainingEvidenceEvent 1 0.75
              ingest progress event =
                let key = fromIntegral (trainingEventEpoch event)
                 in ingestEvent
                      contract
                      progress
                      (refinedEvidence planA "late-range" key ("proof" :: Text))
          assertLateEvidenceRejected
            completeEvent
            outOfRangeEvent
            (initialProgress contract)
            ingest
            (finishContract contract)
            (\case OutOfRangeKey {} -> True; _ -> False)
    , testCase "runLiveWorkflow preserves primary and every placement cleanup failure" $ do
        let primary = LiveWorkflow.WorkloadFailure "worker failed"
            cleanupIssues =
              [ LiveWorkflow.CleanupIssue "Job deletion failed"
              , LiveWorkflow.CleanupIssue "RunConfig ConfigMap deletion failed"
              ]
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planA
            (LiveWorkflow.Failed primary)
            cleanupIssues
            Nothing
        releaseCount @?= 1
        case result of
          Right completed -> assertFailure ("failed fake workflow completed: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure
              @?= Just (LiveWorkflow.LiveWorkloadFailed primary)
            LiveWorkflow.liveFailureCleanupIssues failure @?= cleanupIssues
            let journalCleanupIssues =
                  [ issue
                  | record <- LiveWorkflow.liveFailureJournal failure
                  , LiveWorkflow.CleanupRecorded issue <- [LiveWorkflow.liveJournalEvent record]
                  ]
            journalCleanupIssues @?= cleanupIssues
            assertBool
              "failure journal retains diagnostics before cleanup failure"
              ( diagnosticsBeforeCleanup
                  (LiveWorkflow.liveFailureJournal failure)
              )
    , testCase "runLiveWorkflow journals diagnostics before every owned-resource release" $ do
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planA
            (LiveWorkflow.Succeeded "job-complete")
            []
            Nothing
        releaseCount @?= 1
        case result of
          Left failure ->
            assertFailure ("successful fake workflow failed: " <> show failure)
          Right completed ->
            releaseLifecycleOrder (LiveWorkflow.completedRunJournal completed)
              @?= ["diagnostics", "subscription", "placement"]
    , testCase "cancellation during diagnostics cannot release the subscription first" $ do
        diagnosticsEntered <- newEmptyMVar
        diagnosticsBlock <- newEmptyMVar :: IO (MVar ())
        diagnosticsCalls <- newIORef (0 :: Int)
        lifecycleOrder <- newIORef ([] :: [Text])
        let observeLifecycle label
              | label == "diagnostics" = do
                  callNumber <-
                    atomicModifyIORef' diagnosticsCalls $ \current ->
                      let next = current + 1
                       in (next, next)
                  if callNumber == 1
                    then do
                      putMVar diagnosticsEntered ()
                      readMVar diagnosticsBlock
                    else modifyIORef' lifecycleOrder (<> [label])
              | otherwise = modifyIORef' lifecycleOrder (<> [label])
        runner <-
          async
            ( runFakeLiveWorkflowWithLifecycle
                observeLifecycle
                planA
                (LiveWorkflow.Succeeded "job-complete")
                []
                Nothing
            )
        readMVar diagnosticsEntered
        cancel runner
        cancelled <- waitCatch runner
        case cancelled of
          Right result ->
            assertFailure
              ("diagnostics cancellation returned a workflow result: " <> show result)
          Left exception ->
            case (fromException exception :: Maybe AsyncCancelled) of
              Nothing ->
                assertFailure
                  ("diagnostics cancellation changed identity: " <> show exception)
              Just _ -> pure ()
        readIORef diagnosticsCalls >>= (@?= 2)
        readIORef lifecycleOrder
          >>= (@?= ["diagnostics", "subscription", "placement"])
    , testCase "runLiveWorkflow rejects and releases a placement owned by another plan" $ do
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planB
            (LiveWorkflow.Succeeded "job-complete")
            []
            Nothing
        releaseCount @?= 1
        case result of
          Right completed -> assertFailure ("mismatched placement completed: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure
              @?= Just (LiveWorkflow.LivePlacementPlanMismatch planA planB)
            assertBool
              "a plan-mismatched placement is never published"
              ( all
                  ( \record ->
                      case LiveWorkflow.liveJournalEvent record of
                        LiveWorkflow.CommandPublicationStarted {} -> False
                        _ -> True
                  )
                  (LiveWorkflow.liveFailureJournal failure)
              )
    , testCase "runLiveWorkflow retains owned-subscription cleanup failure with completed facts" $ do
        let cleanupError = SETransient "owned subscription DELETE failed"
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planA
            (LiveWorkflow.Succeeded "job-complete")
            []
            (Just (PulsarInternal.ConsumerCleanupFailure cleanupError))
        releaseCount @?= 1
        case result of
          Right completed ->
            assertFailure
              ("subscription cleanup failure minted completion: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure @?= Nothing
            case LiveWorkflow.liveFailureCompletion failure of
              Nothing -> assertFailure "completed facts were lost with subscription cleanup failure"
              Just (terminal, evidence) -> do
                terminal
                  @?= LiveWorkflow.IndependentWorkloadSucceeded "job-complete"
                exactlyOneValue evidence @?= "proof"
            case LiveWorkflow.liveFailureCleanupIssues failure of
              [LiveWorkflow.CleanupIssue detail] -> do
                assertBool
                  "subscription cleanup detail was lost"
                  ( "owned subscription DELETE failed" `Text.isInfixOf` detail
                      && "run-live-workflow-unit" `Text.isInfixOf` detail
                  )
              issues -> assertFailure ("unexpected subscription cleanup issues: " <> show issues)
            let events =
                  fmap
                    LiveWorkflow.liveJournalEvent
                    (LiveWorkflow.liveFailureJournal failure)
            assertBool
              "failed subscription cleanup was falsely journalled as released"
              ( all
                  (\case LiveWorkflow.SubscriptionReleased {} -> False; _ -> True)
                  events
              )
            assertBool
              "subscription cleanup failure is absent from the journal"
              ( any
                  (\case LiveWorkflow.CleanupRecorded {} -> True; _ -> False)
                  events
              )
    , testCase "runLiveWorkflow preserves workload primary beside subscription cleanup failure" $ do
        let primary = LiveWorkflow.WorkloadFailure "worker failed first"
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planA
            (LiveWorkflow.Failed primary)
            []
            ( Just
                ( PulsarInternal.ConsumerCleanupFailure
                    (SETransient "subscription cleanup failed second")
                )
            )
        releaseCount @?= 1
        case result of
          Right completed -> assertFailure ("failed workflow completed: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure
              @?= Just (LiveWorkflow.LiveWorkloadFailed primary)
            case LiveWorkflow.liveFailureCleanupIssues failure of
              [LiveWorkflow.CleanupIssue detail] ->
                assertBool
                  "secondary subscription cleanup failure was lost"
                  ("subscription cleanup failed second" `Text.isInfixOf` detail)
              issues -> assertFailure ("unexpected subscription cleanup issues: " <> show issues)
    , testCase "runLiveWorkflow retains completed facts when shutdown finds a consumer primary" $ do
        let shutdownPrimary =
              PulsarInternal.ConsumerProtocolFailure
                "consumer failed after completion joined"
        (result, releaseCount) <-
          runFakeLiveWorkflow
            planA
            (LiveWorkflow.Succeeded "job-complete")
            []
            (Just shutdownPrimary)
        releaseCount @?= 1
        case result of
          Right completed ->
            assertFailure
              ("consumer shutdown failure minted completion: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure
              @?= Just (LiveWorkflow.LiveConsumerFailed shutdownPrimary)
            case LiveWorkflow.liveFailureCompletion failure of
              Nothing ->
                assertFailure
                  "completed facts were lost when shutdown returned a consumer primary"
              Just (terminal, evidence) -> do
                terminal
                  @?= LiveWorkflow.IndependentWorkloadSucceeded "job-complete"
                exactlyOneValue evidence @?= "proof"
            LiveWorkflow.liveFailureCleanupIssues failure @?= []
    , testCase "withOwnedCleanup retains completed facts and journals object cleanup failure" $ do
        let cleanupIssue =
              LiveWorkflow.CleanupIssue
                "temporary object deletion failed: checkpoints/blob"
        result <-
          LiveWorkflow.withOwnedCleanup
            (pure [cleanupIssue])
            ( fst
                <$> runFakeLiveWorkflow
                  planA
                  (LiveWorkflow.Succeeded "job-complete")
                  []
                  Nothing
            )
        case result of
          Right completed ->
            assertFailure
              ("owned-object cleanup failure minted completion: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure @?= Nothing
            LiveWorkflow.liveFailureCleanupIssues failure @?= [cleanupIssue]
            case LiveWorkflow.liveFailureCompletion failure of
              Nothing ->
                assertFailure
                  "completed facts were lost with owned-object cleanup failure"
              Just (terminal, evidence) -> do
                terminal
                  @?= LiveWorkflow.IndependentWorkloadSucceeded "job-complete"
                exactlyOneValue evidence @?= "proof"
            case reverse (LiveWorkflow.liveFailureJournal failure) of
              record : _ ->
                LiveWorkflow.liveJournalEvent record
                  @?= LiveWorkflow.CleanupRecorded cleanupIssue
              [] -> assertFailure "cleanup failure journal was empty"
    , testCase "withOwnedCleanup keeps a workload primary ahead of object cleanup failure" $ do
        let primary = LiveWorkflow.WorkloadFailure "workload failed first"
            cleanupIssue =
              LiveWorkflow.CleanupIssue
                "temporary object deletion failed second"
        result <-
          LiveWorkflow.withOwnedCleanup
            (pure [cleanupIssue])
            ( fst
                <$> runFakeLiveWorkflow
                  planA
                  (LiveWorkflow.Failed primary)
                  []
                  Nothing
            )
        case result of
          Right completed ->
            assertFailure ("failed owned-object workflow completed: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure
              @?= Just (LiveWorkflow.LiveWorkloadFailed primary)
            LiveWorkflow.liveFailureCleanupIssues failure @?= [cleanupIssue]
    , testCase "withOwnedCleanup retains cleanup failure beside a synchronous staging primary" $ do
        cleanupCalls <- newIORef (0 :: Int)
        let cleanupIssue =
              LiveWorkflow.CleanupIssue
                "partial staging object deletion failed"
            failingStage =
              ioError (userError "temporary object staging exploded")
                :: IO (Either FakeLiveFailure FakeLiveCompleted)
        result <-
          LiveWorkflow.withOwnedCleanup
            ( do
                modifyIORef' cleanupCalls (+ 1)
                pure [cleanupIssue]
            )
            failingStage
        readIORef cleanupCalls >>= (@?= 1)
        case result of
          Right completed ->
            assertFailure ("failed staging action completed: " <> show completed)
          Left failure -> do
            case LiveWorkflow.liveFailurePrimary failure of
              Just (LiveWorkflow.LiveInterpreterException detail) ->
                assertBool
                  "synchronous staging exception detail was lost"
                  ("temporary object staging exploded" `Text.isInfixOf` detail)
              primary ->
                assertFailure ("unexpected staging primary: " <> show primary)
            LiveWorkflow.liveFailurePlacement failure @?= Nothing
            LiveWorkflow.liveFailureCompletion failure @?= Nothing
            LiveWorkflow.liveFailureCleanupIssues failure @?= [cleanupIssue]
            fmap
              LiveWorkflow.liveJournalEvent
              (LiveWorkflow.liveFailureJournal failure)
              @?= [LiveWorkflow.CleanupRecorded cleanupIssue]
    , testCase "withOwnedCleanup preserves async identity and observes cleanup failure" $ do
        let cleanupIssue =
              LiveWorkflow.CleanupIssue
                "asynchronous temporary-object cleanup failed"
            cancelledAction =
              throwIO AsyncCancelled
                :: IO (Either FakeLiveFailure FakeLiveCompleted)
        observedCleanup <- newIORef []
        attempted <-
          try
            ( LiveWorkflow.withOwnedCleanupObserved
                (writeIORef observedCleanup)
                (pure [cleanupIssue])
                cancelledAction
            )
            :: IO
                 ( Either
                     AsyncCancelled
                     (Either FakeLiveFailure FakeLiveCompleted)
                 )
        case attempted of
          Right _ -> assertFailure "owned cleanup replaced cancellation with a result"
          Left _sameAsyncType -> pure ()
        readIORef observedCleanup >>= (@?= [cleanupIssue])
    , productScenarioReportTests
    ]

productScenarioReportTests :: TestTree
productScenarioReportTests =
  testGroup
    "ProductScenarioReport"
    [ testCase "Store-admitted completion and live completion mint an opaque report" $
        withAdmittedProductProjection $ \row projection admitted -> do
          scenarioCompletion <-
            expectRight (Report.productScenarioCompletion projection admitted)
          liveResult <- runProductScenarioWorkflow projection scenarioCompletion
          evidence <-
            expectRight
              (Report.completedProductScenarioEvidence projection liveResult)
          let batch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCPU [row])
          report <-
            expectRight
              (Report.projectCompletedProductScenarioReport batch [evidence])
          Report.completedProductScenarioRowId evidence
            @?= ProductMatrix.productProjectionRowId projection
          Report.completedProductScenarioPlanId evidence
            @?= ProductMatrix.productProjectionPlanId projection
          Report.completedProductScenarioLane evidence @?= LinuxCPU
          let expectedManifestSha =
                CheckpointStore.admittedCheckpointManifestSha
                  (CheckpointStore.admittedCompletedCheckpoint admitted)
          Report.completedProductScenarioManifestSha evidence
            @?= expectedManifestSha
          assertBool
            "validated product report omitted persisted artifact identity"
            ( expectedManifestSha
                `Text.isInfixOf` Report.renderCompletedProductScenarioEvidence report
            )
    , testCase "typed completion rejects another experiment or substrate plan" $
        withAdmittedProductProjection $ \row projection admitted -> do
          _ <- expectRight (Report.productScenarioCompletion projection admitted)
          withProjectedRow LinuxCUDA row $ \cudaProjection -> do
            assertProductCompletionError
              isCompletionPlanMismatch
              (Report.productScenarioCompletion cudaProjection admitted)
            assertProductCompletionError
              isCompletionManifestPlanMismatch
              (Report.productScenarioCompletion cudaProjection admitted)
          withDifferentProductProjection row $ \otherProjection -> do
            let rejected = Report.productScenarioCompletion otherProjection admitted
            assertProductCompletionError isCompletionExperimentMismatch rejected
            assertProductCompletionError isCompletionCanonicalRowMismatch rejected
    , testCase "AlphaZero update-count multiplication fails closed on Word64 overflow" $
        withAdmittedProductProjection $ \_admittedRow _admittedProjection admitted ->
          case [ row
               | row <- ProductMatrix.allProductRows
               , case ProductMatrix.rowClass row of
                   ProductMatrix.AlphaZeroGame _ -> True
                   _ -> False
               ] of
            [] -> assertFailure "ProductRow registry has no AlphaZero row"
            row : _ ->
              case ProductMatrix.productCapability row of
                ProductMatrix.ExecutableProduct
                  (ProductMatrix.AlphaZeroProductDescriptor game _ _ _ _ _)
                  ProductMatrix.AlphaZeroProductEvidence -> do
                    let largeQuantity = 5_000_000_000
                        overflowRow =
                          row
                            { ProductMatrix.trainingBudget =
                                trainingBudgetFixture
                                  TrainingBudget.AlphaZeroSelfPlayBudget
                                  largeQuantity
                                  ( TrainingBudget.trainingBudgetSeed
                                      (ProductMatrix.trainingBudget row)
                                  )
                            , ProductMatrix.productCapability =
                                ProductMatrix.ExecutableProduct
                                  ( ProductMatrix.AlphaZeroProductDescriptor
                                      game
                                      1
                                      1
                                      1
                                      largeQuantity
                                      1
                                  )
                                  ProductMatrix.AlphaZeroProductEvidence
                            }
                    withProjectedRow LinuxCPU overflowRow $ \projection ->
                      assertProductCompletionError
                        isCompletionUpdateCountOverflow
                        (Report.productScenarioCompletion projection admitted)
                other ->
                  assertFailure
                    ("unexpected AlphaZero ProductCapability: " <> show other)
    , testCase "declaration or non-completed run cannot mint scenario evidence" $
        withFirstProductProjection $ \_row projection ->
          incompleteProductScenarioEvidence projection
            @?= Left
              ( Report.ProductScenarioDidNotComplete
                  (ProductMatrix.productProjectionRowId projection)
              )
    , testCase "scenario evidence independently rejects the live plan and projection" $ do
        withAdmittedProductProjection $ \_row projection admitted -> do
          let completion =
                expectEitherRight
                  ( Report.productScenarioCompletion
                      projection
                      admitted
                  )
              expectedPlanId = ProductMatrix.productProjectionPlanId projection
              wrongPlanId = if expectedPlanId == planA then planB else planA
          liveResult <-
            runProductScenarioWorkflowAtPlan wrongPlanId projection completion
          Report.completedProductScenarioEvidence projection liveResult
            @?= Left
              ( Report.ProductScenarioPlanMismatch
                  (ProductMatrix.productProjectionRowId projection)
                  expectedPlanId
                  wrongPlanId
              )
          withDifferentSupervisedProductProjection projection $ \secondProjection -> do
            let secondProjectionCompletion =
                  expectEitherRight
                    ( Report.productScenarioCompletion
                        projection
                        admitted
                    )
            secondProjectionLiveResult <-
              runProductScenarioWorkflowAtPlan
                (ProductMatrix.productProjectionPlanId secondProjection)
                projection
                secondProjectionCompletion
            Report.completedProductScenarioEvidence
              secondProjection
              secondProjectionLiveResult
              @?= Left
                ( Report.ProductScenarioProjectionMismatch
                    (ProductMatrix.productProjectionRowId secondProjection)
                )
    , testCase "projection batch rejects duplicate and unprojectable registry rows" $
        case ProductMatrix.allProductRows of
          [] -> assertFailure "ProductRow registry is unexpectedly empty"
          row : _ -> do
            assertProductMatrixError
              (\case ProductMatrix.DuplicateProductRowId _ -> True; _ -> False)
              (ProductMatrix.projectProductRows LinuxCPU [row, row])
            let unsupported =
                  row
                    { ProductMatrix.productCapability =
                        ProductMatrix.UnsupportedProduct "unit unprojectable fixture"
                    }
            assertProductMatrixError
              (\case ProductMatrix.UnprojectableProductRow _ -> True; _ -> False)
              (ProductMatrix.projectProductRows LinuxCPU [unsupported])
    , testCase "validated report rejects missing, duplicate, orphan, wrong-plan, and wrong-lane evidence" $
        withAdmittedProductProjection $ \firstRow firstProjection admitted -> do
          secondRow <-
            case filter ((/= ProductMatrix.rowId firstRow) . ProductMatrix.rowId) ProductMatrix.allProductRows of
              [] -> assertFailure "ProductRow registry needs at least two rows"
              row : _ -> pure row
          let completion =
                expectEitherRight
                  (Report.productScenarioCompletion firstProjection admitted)
          liveResult <- runProductScenarioWorkflow firstProjection completion
          evidence <-
            expectRight
              (Report.completedProductScenarioEvidence firstProjection liveResult)
          let firstBatch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCPU [firstRow])
              secondBatch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCPU [secondRow])
              cudaBatch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCUDA [firstRow])
          assertProductReportError
            (\case Report.MissingCompletedProductScenario {} -> True; _ -> False)
            (Report.projectCompletedProductScenarioReport firstBatch [])
          assertProductReportError
            (\case Report.DuplicateCompletedProductScenario {} -> True; _ -> False)
            (Report.projectCompletedProductScenarioReport firstBatch [evidence, evidence])
          assertProductReportError
            (\case Report.OrphanCompletedProductScenario {} -> True; _ -> False)
            (Report.projectCompletedProductScenarioReport secondBatch [evidence])
          assertProductReportError
            (\case Report.WrongPlanCompletedProductScenario {} -> True; _ -> False)
            (Report.projectCompletedProductScenarioReport cudaBatch [evidence])
          assertProductReportError
            (\case Report.WrongLaneCompletedProductScenario {} -> True; _ -> False)
            (Report.projectCompletedProductScenarioReport cudaBatch [evidence])
    , testCase "validated report rejects evidence minted under a stale report contract" $
        withAdmittedProductProjection $ \row projection admitted -> do
          let completion =
                expectEitherRight
                  ( Report.productScenarioCompletion
                      projection
                      admitted
                  )
          liveResult <- runProductScenarioWorkflow projection completion
          evidence <-
            expectRight
              (Report.completedProductScenarioEvidence projection liveResult)
          let changedScenarioIds =
                row
                  { ProductMatrix.integrationTest =
                      ProductMatrix.integrationTest row <> ".changed"
                  , ProductMatrix.e2eTest =
                      ProductMatrix.e2eTest row <> ".changed"
                  }
              originalBar = ProductMatrix.convergenceBar row
              changedCriterion =
                row
                  { ProductMatrix.convergenceBar =
                      originalBar
                        { ProductConvergence.convergenceLiteratureTarget =
                            ProductConvergence.convergenceLiteratureTarget originalBar + 0.001
                        , ProductConvergence.convergenceThreshold =
                            ProductConvergence.convergenceThreshold originalBar + 0.001
                        }
                  }
              changedDemoPanel =
                row
                  { ProductMatrix.demoPanel =
                      ProductMatrix.demoPanel row <> ".changed"
                  }
              changedScenarioBatch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCPU [changedScenarioIds])
              changedCriterionBatch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCPU [changedCriterion])
              changedDemoPanelBatch =
                expectSuccess
                  (ProductMatrix.projectProductRows LinuxCPU [changedDemoPanel])
              isStaleContract =
                \case
                  Report.StaleContractCompletedProductScenario {} -> True
                  _ -> False
          assertProductReportError
            isStaleContract
            ( Report.projectCompletedProductScenarioReport
                changedScenarioBatch
                [evidence]
            )
          assertProductReportError
            isStaleContract
            ( Report.projectCompletedProductScenarioReport
                changedCriterionBatch
                [evidence]
            )
          assertProductReportError
            isStaleContract
            ( Report.projectCompletedProductScenarioReport
                changedDemoPanelBatch
                [evidence]
            )
    ]

-- The report boundary deliberately accepts no caller-built completion.  Unit
-- tests therefore persist and re-admit one exact ProductRow V2 graph instead
-- of using a privileged constructor or a decoded-manifest shortcut.
withAdmittedProductProjection
  :: ( ProductMatrix.ProductRow 'ProductMatrix.Declared
       -> ProductMatrix.ProductProjection 'SupervisedTraining
       -> CheckpointStore.AdmittedCompletedCheckpoint
       -> IO result
     )
  -> IO result
withAdmittedProductProjection action =
  withSystemTempDirectory "jitml-report-admission" $ \root -> do
    row <-
      maybe
        (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
        pure
        ( find
            ((== "mnist-shallow-mlp") . ProductMatrix.rowId)
            ProductMatrix.allProductRows
        )
    problem <-
      maybe
        (assertFailure "missing canonical mnist-shallow-mlp problem")
        pure
        (find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems)
    projection <-
      case ProductMatrix.projectProductRow LinuxCPU row of
        Failure errors ->
          assertFailure ("ProductRow projection failed: " <> show errors)
        Success
          ( ProductMatrix.SomeProductProjection
              SupervisedTrainingWitness
              exactProjection
            ) -> pure exactProjection
        Success _ ->
          assertFailure "mnist-shallow-mlp projection is not supervised"
    admitted <-
      persistAndAdmitProductCompletion root row problem projection
    action row projection admitted

persistAndAdmitProductCompletion
  :: FilePath
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> SL.CanonicalProblem
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> IO CheckpointStore.AdmittedCompletedCheckpoint
persistAndAdmitProductCompletion root row problem projection = do
  datasetSha <- expectRight (Dataset.canonicalDatasetReadShaForProblem problem)
  let plan =
        case ProductMatrix.productProjectionResolvedPlan projection of
          ProductMatrix.ResolvedSupervisedProductPlan resolved -> resolved
      -- Phase 239: the fixture checkpoint is the trained dense mnist-shallow-mlp
      -- graph.  Its graph-ordered parameter count anchors the synthetic weight
      -- blobs, the flat weight layout, and admission.
      fixtureConfig =
        Classifier.defaultClassifierConfig
          { Classifier.clfInputs = 784
          , Classifier.clfClasses = 10
          , Classifier.clfSeed = SL.problemSeed problem
          }
      graphMeta =
        layerGraphMetadataFromGraph
          ( Architecture.archLayerGraph
              (Architecture.architectureSpecForProblem fixtureConfig problem)
          )
      parameterCount = layerGraphMetadataParameterCount graphMeta
      initialBytes = WeightCodec.encodeJmw1 (replicate parameterCount 0.0)
      finalBytes =
        WeightCodec.encodeJmw1
          (0.25 : replicate (parameterCount - 1) 0.0)
      initialSha = WeightCodec.jmw1ContentSha initialBytes
      finalSha = WeightCodec.jmw1ContentSha finalBytes
      experiment = ProductMatrix.productProjectionExperimentHash projection
      planId = ProductMatrix.productProjectionPlanId projection
      budget = ProductMatrix.productProjectionTrainingBudget projection
      observedUnits = TrainingBudget.trainingBudgetTargetUnits budget
      optimizerUpdates =
        quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
      bar = ProductMatrix.productProjectionConvergenceBar projection
      metrics =
        [
          ( ProductConvergence.convergenceMetricName bar
          , ProductConvergence.convergenceThreshold bar
          )
        ]
  payload <-
    expectRight
      ( RuntimeArtifact.refineSupervisedRuntimePayload
          RuntimeArtifact.RawSupervisedRuntimePayload
            { RuntimeArtifact.rawRuntimePayloadRowId = ProductMatrix.rowId row
            , RuntimeArtifact.rawRuntimePayloadOrigin =
                RuntimeArtifact.RawProductRowProjectionOrigin
            , RuntimeArtifact.rawRuntimePayloadPlanId = planIdText planId
            , RuntimeArtifact.rawRuntimePayloadDatasetSha256 = datasetSha
            , RuntimeArtifact.rawRuntimePayloadInitialJmw1Sha256 = initialSha
            , RuntimeArtifact.rawRuntimePayloadFinalJmw1Sha256 = finalSha
            , RuntimeArtifact.rawRuntimePayloadRuntime = reportFixtureRuntime
            , RuntimeArtifact.rawRuntimePayloadLayerGraphMetadata = Just graphMeta
            }
      )
  metadata <-
    expectRight (Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload)
  completed <-
    expectRight
      ( ProductCompletion.completedTrainingForProductRowWithWeightHashes
          planId
          budget
          row
          datasetSha
          experiment
          observedUnits
          optimizerUpdates
          metrics
          initialSha
          finalSha
      )
  let tensor =
        Checkpoint.TensorBlob
          "supervised.weights"
          [parameterCount]
          (Checkpoint.blobKey experiment finalSha)
      manifest =
        Checkpoint.attachCompletedTraining completed $
          (Checkpoint.emptyManifest "report-admission" experiment [tensor])
            { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
            , Checkpoint.manifestArchitecture =
                Checkpoint.supervisedRuntimeArchitectureMetadata metadata
            , Checkpoint.manifestPreprocessing =
                Checkpoint.supervisedRuntimePreprocessingMetadata metadata
            , Checkpoint.manifestOutputDecoders =
                Checkpoint.supervisedRuntimeOutputDecoderMetadata metadata
            , Checkpoint.manifestWeightLayout =
                Checkpoint.FlatWeightLayout
                  [ Checkpoint.TensorSpec
                      { Checkpoint.tensorSpecName = "supervised.weights"
                      , Checkpoint.tensorSpecShape = [parameterCount]
                      , Checkpoint.tensorSpecDtype = "F64"
                      }
                  ]
            , Checkpoint.manifestStep = observedUnits
            , Checkpoint.manifestMetrics = metrics
            , Checkpoint.manifestSupervisedRuntime = Just payload
            }
  _ <-
    expectRight
      =<< CheckpointStore.writeCompletedCheckpointSnapshot
        root
        completed
        manifest
        [(Checkpoint.tensorBlobKey tensor, finalBytes)]
        Nothing
  admittedCheckpoint <-
    expectRight
      =<< CheckpointStore.admitLocalLatestCheckpoint root experiment
  expectRight
    (CheckpointStore.requireAdmittedCompletedCheckpoint admittedCheckpoint)

reportFixtureRuntime :: RuntimeArtifact.RawSupervisedRuntime
reportFixtureRuntime =
  RuntimeArtifact.RawSupervisedRuntime
    { RuntimeArtifact.rawSupervisedRuntimeTask =
        RuntimeArtifact.RawClassificationRuntimeTask 10
    , RuntimeArtifact.rawSupervisedRuntimeInputTransform =
        RuntimeArtifact.RawUnitImageInput
          (RuntimeArtifact.RawRuntimeImageGeometry 28 28 1)
    , RuntimeArtifact.rawSupervisedRuntimeOutputTransform =
        RuntimeArtifact.RawSemanticPrefixOutput 10
    }

withDifferentProductProjection
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> (forall kind. ProductMatrix.ProductProjection kind -> IO result)
  -> IO result
withDifferentProductProjection admittedRow action =
  case filter ((/= ProductMatrix.rowId admittedRow) . ProductMatrix.rowId) ProductMatrix.allProductRows of
    [] -> assertFailure "ProductRow registry needs at least two rows"
    row : _ -> withProjectedRow LinuxCPU row action

withDifferentSupervisedProductProjection
  :: ProductMatrix.ProductProjection 'SupervisedTraining
  -> (ProductMatrix.ProductProjection 'SupervisedTraining -> IO result)
  -> IO result
withDifferentSupervisedProductProjection admittedProjection action =
  findDifferent
    ( ProductMatrix.productProjectionBatchProjections
        (expectSuccess (ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows))
    )
 where
  findDifferent projections =
    case projections of
      [] -> assertFailure "ProductRow registry needs two supervised projections"
      ProductMatrix.SomeProductProjection SupervisedTrainingWitness projection : rest
        | projection /= admittedProjection -> action projection
        | otherwise -> findDifferent rest
      _other : rest -> findDifferent rest

withFirstProductProjection
  :: ( forall kind
        . ProductMatrix.ProductRow 'ProductMatrix.Declared
       -> ProductMatrix.ProductProjection kind
       -> IO result
     )
  -> IO result
withFirstProductProjection action =
  case ProductMatrix.allProductRows of
    [] -> assertFailure "ProductRow registry is unexpectedly empty"
    row : _ -> withProjectedRow LinuxCPU row (action row)

withProjectedRow
  :: Substrate
  -> ProductMatrix.ProductRow state
  -> (forall kind. ProductMatrix.ProductProjection kind -> IO result)
  -> IO result
withProjectedRow substrate row action =
  case ProductMatrix.projectProductRow substrate row of
    Failure errors ->
      assertFailure ("ProductRow projection failed: " <> show errors)
    Success (ProductMatrix.SomeProductProjection _witness projection) ->
      action projection

trainingBudgetFixture
  :: TrainingBudget.BudgetKind
  -> Word64
  -> Maybe Word64
  -> TrainingBudget.TrainingBudget
trainingBudgetFixture kind target seed =
  expectTextRight
    "product training budget"
    (TrainingBudget.mkTrainingBudget kind target seed)

expectEitherRight :: (Show error) => Either error value -> value
expectEitherRight result =
  case result of
    Left err -> error ("expected Right, got Left " <> show err)
    Right value -> value

incompleteProductScenarioEvidence
  :: forall kind
   . ProductMatrix.ProductProjection kind
  -> Either Report.ProductScenarioEvidenceError Report.CompletedProductScenarioEvidence
incompleteProductScenarioEvidence projection =
  Report.completedProductScenarioEvidence
    projection
    ( Left ()
        :: Either
             ()
             ( LiveWorkflow.CompletedRunEvidence
                 Text
                 (Report.ProductScenarioCompletion kind)
                 Text
                 Text
             )
    )

assertProductCompletionError
  :: (Report.ProductScenarioCompletionError -> Bool)
  -> Either
       (NonEmpty Report.ProductScenarioCompletionError)
       (Report.ProductScenarioCompletion kind)
  -> IO ()
assertProductCompletionError predicate result =
  case result of
    Left errors -> assertBool "expected typed product-completion error" (any predicate errors)
    Right _ -> assertFailure "misbound admitted checkpoint minted ProductScenarioCompletion"

assertProductMatrixError
  :: (ProductMatrix.ProductMatrixError -> Bool)
  -> Validation (NonEmpty ProductMatrix.ProductMatrixError) ProductMatrix.ProductProjectionBatch
  -> IO ()
assertProductMatrixError predicate result =
  case result of
    Failure errors -> assertBool "expected typed product-matrix error" (any predicate errors)
    Success _ -> assertFailure "invalid ProductRow registry minted ProductProjectionBatch"

assertProductReportError
  :: (Report.ProductScenarioReportError -> Bool)
  -> Either
       (NonEmpty Report.ProductScenarioReportError)
       Report.CompletedProductScenarioReport
  -> IO ()
assertProductReportError predicate result =
  case result of
    Left errors -> assertBool "expected typed product-report error" (any predicate errors)
    Right _ -> assertFailure "invalid evidence minted CompletedProductScenarioReport"

isCompletionPlanMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionPlanMismatch Report.ProductCompletionPlanMismatch {} = True
isCompletionPlanMismatch _ = False

isCompletionExperimentMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionExperimentMismatch Report.ProductCompletionExperimentMismatch {} = True
isCompletionExperimentMismatch _ = False

isCompletionCanonicalRowMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionCanonicalRowMismatch Report.ProductCompletionCanonicalRowMismatch {} = True
isCompletionCanonicalRowMismatch _ = False

isCompletionManifestPlanMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionManifestPlanMismatch Report.ProductCompletionManifestPlanMismatch {} = True
isCompletionManifestPlanMismatch _ = False

isCompletionUpdateCountOverflow :: Report.ProductScenarioCompletionError -> Bool
isCompletionUpdateCountOverflow Report.ProductCompletionUpdateCountOverflow {} = True
isCompletionUpdateCountOverflow _ = False

runProductScenarioWorkflow
  :: ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioCompletion kind
  -> IO
       ( Either
           ( LiveWorkflow.LiveRunFailure
               Text
               (Report.ProductScenarioCompletion kind)
               Text
               Text
           )
           ( LiveWorkflow.CompletedRunEvidence
               Text
               (Report.ProductScenarioCompletion kind)
               Text
               Text
           )
       )
runProductScenarioWorkflow projection =
  runProductScenarioWorkflowAtPlan
    (ProductMatrix.productProjectionPlanId projection)
    projection

runProductScenarioWorkflowAtPlan
  :: PlanId
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioCompletion kind
  -> IO
       ( Either
           ( LiveWorkflow.LiveRunFailure
               Text
               (Report.ProductScenarioCompletion kind)
               Text
               Text
           )
           ( LiveWorkflow.CompletedRunEvidence
               Text
               (Report.ProductScenarioCompletion kind)
               Text
               Text
           )
       )
runProductScenarioWorkflowAtPlan livePlanId projection scenarioCompletion = do
  commandTopic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
  eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
  subscription <-
    expectRight
      (mkSubscription eventTopic "product-scenario-unit" FromLatest Borrowed)
  handle <-
    expectRight
      ( LiveWorkflow.mkJobHandle
          livePlanId
          "jitml-product-scenario-unit"
      )
  consumerBlock <- newEmptyMVar :: IO (MVar ())
  let command =
        Training.TrainingStop
          Training.StopTraining
            { Training.stopExperimentHash =
                ProductMatrix.productProjectionExperimentHash projection
            , Training.stopDrain = True
            }
      event =
        Training.TrainingEpoch
          Training.EpochCompleted
            { Training.ecExperimentHash =
                ProductMatrix.productProjectionExperimentHash projection
            , Training.ecEpoch = 1
            , Training.ecLoss = 0.25
            , Training.ecValidationLoss = 0.2
            , Training.ecTimestampNs = 1
            }
      delivery =
        PulsarInternal.Delivery
          { PulsarInternal.deliveryEventInternal = event
          , PulsarInternal.deliveryReceiptInternal =
              PulsarInternal.DeliveryReceipt
                { PulsarInternal.receiptSessionInternal = "product-scenario-session"
                , PulsarInternal.receiptGenerationInternal = 1
                , PulsarInternal.receiptDeliveryIdInternal = "product-scenario-delivery"
                }
          , PulsarInternal.deliveryRedeliveryCountInternal = 0
          }
      transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.livePublishCommand = const (pure (Right "product-scenario-ack"))
          , LiveWorkflow.liveConsumeEvents = \_ observe handleDelivery -> do
              observe (ConsumerSessionConnected 1)
              decision <- handleDelivery delivery
              case decision of
                PulsarInternal.DoneInternal _ result -> pure (Right result)
                PulsarInternal.ContinueInternal _ -> do
                  interrupted <-
                    try (readMVar consumerBlock)
                      :: IO (Either AsyncCancelled ())
                  case interrupted of
                    Left cancelled -> throwIO cancelled
                    Right () ->
                      pure
                        ( Left
                            ( PulsarInternal.ConsumerProtocolFailure
                                "product scenario consumer block released unexpectedly"
                            )
                        )
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId =
              livePlanId
          , LiveWorkflow.liveWorkflowCommand =
              LiveWorkflow.ProtocolCommand commandTopic command
          , LiveWorkflow.liveWorkflowEventSubscription = subscription
          , LiveWorkflow.liveWorkflowInitialProgress = False
          , LiveWorkflow.liveWorkflowIngest = \_progress _event -> Right True
          , LiveWorkflow.liveWorkflowFinish = \complete ->
              if complete
                then Success scenarioCompletion
                else Failure "product scenario evidence missing"
          , LiveWorkflow.liveWorkflowRenderViolation = id
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement =
              pure (Right (LiveWorkflow.ClusterJob handle))
          , LiveWorkflow.liveCompletionMode =
              LiveWorkflow.ObserveIndependentWorkload
          , LiveWorkflow.liveObserveWorkload =
              const (pure (LiveWorkflow.Succeeded "product-scenario-complete"))
          , LiveWorkflow.liveGatherDiagnostics = const (pure (Right []))
          , LiveWorkflow.liveReleasePlacement = const (pure [])
          , LiveWorkflow.liveObservationAttempts = 1
          , LiveWorkflow.liveObservationDelayMicros = 0
          , LiveWorkflow.liveWorkflowTimeoutMicros = 1_000_000
          }
  LiveWorkflow.runLiveWorkflow workflow transport backend

type ExactlyTextContract =
  Contract
    (EvidenceEvent () Text)
    (RequirementState () Text)
    (ExactlyOne Text)

type AtLeastTextContract =
  Contract
    (EvidenceEvent Int Text)
    (RequirementState Int Text)
    (AtLeastOne Int Text)

type ExactIntContract =
  Contract
    (EvidenceEvent Int Double)
    (RequirementState Int Double)
    (ExactKeyed Int Double)

ingestAll
  :: Contract event progress evidence
  -> [event]
  -> IO progress
ingestAll contract = go (initialProgress contract)
 where
  go progress [] = pure progress
  go progress (event : rest) = do
    next <- expectRight (ingestEvent contract progress event)
    go next rest

expectRight :: (Show error) => Either error value -> IO value
expectRight result =
  case result of
    Right value -> pure value
    Left err -> assertFailure ("expected Right, got Left " <> show err) >> error "unreachable"

expectSuccess :: (Show error) => Validation error value -> value
expectSuccess result =
  case result of
    Success value -> value
    Failure err -> error ("expected Success, got Failure " <> show err)

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe result =
  case result of
    Left _ -> Nothing
    Right value -> Just value

maybeToEither
  :: Maybe value
  -> Either LiveWorkflow.CompletionJoinError value
maybeToEither = maybe (Left LiveWorkflow.ConflictingCompletedEvidence) Right

type FakeLiveFailure =
  LiveWorkflow.LiveRunFailure
    Text
    (ExactlyOne Text)
    ContractViolation
    (NonEmpty MissingEvidence)

type FakeLiveCompleted =
  LiveWorkflow.CompletedRunEvidence
    Text
    (ExactlyOne Text)
    ContractViolation
    (NonEmpty MissingEvidence)

runFakeLiveWorkflow
  :: PlanId
  -> LiveWorkflow.WorkloadObservation Text
  -> [LiveWorkflow.CleanupIssue]
  -> Maybe PulsarInternal.ConsumerFailure
  -> IO (Either FakeLiveFailure FakeLiveCompleted, Int)
runFakeLiveWorkflow acquiredPlanId terminalObservation cleanupResult subscriptionCleanupError = do
  runFakeLiveWorkflowWithLifecycle
    (const (pure ()))
    acquiredPlanId
    terminalObservation
    cleanupResult
    subscriptionCleanupError

runFakeLiveWorkflowWithLifecycle
  :: (Text -> IO ())
  -> PlanId
  -> LiveWorkflow.WorkloadObservation Text
  -> [LiveWorkflow.CleanupIssue]
  -> Maybe PulsarInternal.ConsumerFailure
  -> IO (Either FakeLiveFailure FakeLiveCompleted, Int)
runFakeLiveWorkflowWithLifecycle observeLifecycle acquiredPlanId terminalObservation cleanupResult subscriptionCleanupError = do
  commandTopic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
  eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
  subscription <-
    expectRight
      (mkSubscription eventTopic "run-live-workflow-unit" FromLatest Owned)
  handle <- expectRight (LiveWorkflow.mkJobHandle acquiredPlanId "jitml-run-live-unit")
  releaseCountRef <- newIORef (0 :: Int)
  consumerBlock <- newEmptyMVar :: IO (MVar ())
  let contract = exactlyOne "fake-live-proof" planA
      command =
        Training.TrainingStop
          Training.StopTraining
            { Training.stopExperimentHash = "fake-live"
            , Training.stopDrain = True
            }
      event =
        Training.TrainingEpoch
          Training.EpochCompleted
            { Training.ecExperimentHash = "fake-live"
            , Training.ecEpoch = 1
            , Training.ecLoss = 0.5
            , Training.ecValidationLoss = 0.25
            , Training.ecTimestampNs = 1
            }
      delivery =
        PulsarInternal.Delivery
          { PulsarInternal.deliveryEventInternal = event
          , PulsarInternal.deliveryReceiptInternal =
              PulsarInternal.DeliveryReceipt
                { PulsarInternal.receiptSessionInternal = "fake-session"
                , PulsarInternal.receiptGenerationInternal = 1
                , PulsarInternal.receiptDeliveryIdInternal = "fake-delivery"
                }
          , PulsarInternal.deliveryRedeliveryCountInternal = 0
          }
      transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.livePublishCommand = const (pure (Right "fake-ack"))
          , LiveWorkflow.liveConsumeEvents = \_ observe handleDelivery -> do
              observe (ConsumerSessionConnected 1)
              decision <- handleDelivery delivery
              case decision of
                PulsarInternal.DoneInternal _ result -> pure (Right result)
                PulsarInternal.ContinueInternal _ -> do
                  interrupted <-
                    try (readMVar consumerBlock)
                      :: IO (Either AsyncCancelled ())
                  case (interrupted, subscriptionCleanupError) of
                    (Left _cancelled, Just shutdownFailure) ->
                      observeLifecycle "subscription"
                        >> pure (Left shutdownFailure)
                    (Left cancelled, Nothing) ->
                      -- Re-raise successful controlled cancellation so the
                      -- interpreter can treat the Async result as proof that
                      -- transport cleanup completed.
                      observeLifecycle "subscription" >> throwIO cancelled
                    (Right (), _) ->
                      pure
                        ( Left
                            ( PulsarInternal.ConsumerProtocolFailure
                                "fake transport completion block was released unexpectedly"
                            )
                        )
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId = planA
          , LiveWorkflow.liveWorkflowCommand =
              LiveWorkflow.ProtocolCommand commandTopic command
          , LiveWorkflow.liveWorkflowEventSubscription = subscription
          , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
          , LiveWorkflow.liveWorkflowIngest = \progress _ ->
              ingestEvent
                contract
                progress
                (refinedEvidence planA "fake-live-proof" () ("proof" :: Text))
          , LiveWorkflow.liveWorkflowFinish = finishContract contract
          , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement =
              pure (Right (LiveWorkflow.ClusterJob handle))
          , LiveWorkflow.liveCompletionMode =
              LiveWorkflow.ObserveIndependentWorkload
          , LiveWorkflow.liveObserveWorkload = const (pure terminalObservation)
          , LiveWorkflow.liveGatherDiagnostics =
              const $ do
                observeLifecycle "diagnostics"
                pure (Right [LiveWorkflow.LiveDiagnostic "fake diagnostics"])
          , LiveWorkflow.liveReleasePlacement = \_ -> do
              observeLifecycle "placement"
              modifyIORef' releaseCountRef (+ 1)
              pure cleanupResult
          , LiveWorkflow.liveObservationAttempts = 1
          , LiveWorkflow.liveObservationDelayMicros = 0
          , LiveWorkflow.liveWorkflowTimeoutMicros = 1_000_000
          }
  result <- LiveWorkflow.runLiveWorkflow workflow transport backend
  releaseCount <- readIORef releaseCountRef
  pure (result, releaseCount)

runFakeRequestWorkflow :: IO (Either FakeLiveFailure FakeLiveCompleted, Int)
runFakeRequestWorkflow = do
  commandTopic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
  eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
  subscription <-
    expectRight
      (mkSubscription eventTopic "run-live-request-unit" FromLatest Owned)
  requestHandle <- expectRight (LiveWorkflow.mkRequestHandle planA "fake-request")
  observerCallsRef <- newIORef (0 :: Int)
  consumerBlock <- newEmptyMVar :: IO (MVar ())
  let contract = exactlyOne "fake-request-proof" planA
      command =
        Training.TrainingStop
          Training.StopTraining
            { Training.stopExperimentHash = "fake-request"
            , Training.stopDrain = True
            }
      event = trainingEvidenceEvent 1 0.5
      delivery =
        PulsarInternal.Delivery
          { PulsarInternal.deliveryEventInternal = event
          , PulsarInternal.deliveryReceiptInternal =
              PulsarInternal.DeliveryReceipt
                { PulsarInternal.receiptSessionInternal = "request-session"
                , PulsarInternal.receiptGenerationInternal = 1
                , PulsarInternal.receiptDeliveryIdInternal = "request-delivery"
                }
          , PulsarInternal.deliveryRedeliveryCountInternal = 0
          }
      transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.livePublishCommand = const (pure (Right "request-ack"))
          , LiveWorkflow.liveConsumeEvents = \_ observe handleDelivery -> do
              observe (ConsumerSessionConnected 1)
              decision <- handleDelivery delivery
              case decision of
                PulsarInternal.DoneInternal _ result -> pure (Right result)
                PulsarInternal.ContinueInternal _ ->
                  readMVar consumerBlock
                    >> pure
                      ( Left
                          ( PulsarInternal.ConsumerProtocolFailure
                              "request consumer block was released unexpectedly"
                          )
                      )
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId = planA
          , LiveWorkflow.liveWorkflowCommand =
              LiveWorkflow.ProtocolCommand commandTopic command
          , LiveWorkflow.liveWorkflowEventSubscription = subscription
          , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
          , LiveWorkflow.liveWorkflowIngest = \progress _ ->
              ingestEvent
                contract
                progress
                (refinedEvidence planA "fake-request-proof" () ("proof" :: Text))
          , LiveWorkflow.liveWorkflowFinish = finishContract contract
          , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement =
              pure (Right (LiveWorkflow.RequestReply requestHandle))
          , LiveWorkflow.liveCompletionMode =
              LiveWorkflow.ResponseCompletesRequest
          , LiveWorkflow.liveObserveWorkload = \_ -> do
              modifyIORef' observerCallsRef (+ 1)
              pure (LiveWorkflow.Succeeded "synthetic-host-terminal")
          , LiveWorkflow.liveGatherDiagnostics = const (pure (Right []))
          , LiveWorkflow.liveReleasePlacement = const (pure [])
          , LiveWorkflow.liveObservationAttempts = 1
          , LiveWorkflow.liveObservationDelayMicros = 0
          , LiveWorkflow.liveWorkflowTimeoutMicros = 1_000_000
          }
  result <- LiveWorkflow.runLiveWorkflow workflow transport backend
  observerCalls <- readIORef observerCallsRef
  pure (result, observerCalls)

assertLateEvidenceRejected
  :: (Eq evidence)
  => Training.TrainingEvent
  -> Training.TrainingEvent
  -> progress
  -> (progress -> Training.TrainingEvent -> Either ContractViolation progress)
  -> (progress -> Validation (NonEmpty MissingEvidence) evidence)
  -> (ContractViolation -> Bool)
  -> IO ()
assertLateEvidenceRejected completeEvent lateEvent initial ingest finish isExpectedViolation = do
  commandTopic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
  eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
  subscription <-
    expectRight
      (mkSubscription eventTopic "run-live-late-evidence" FromLatest Owned)
  handle <- expectRight (LiveWorkflow.mkJobHandle planA "jitml-run-live-late")
  terminalBlock <- newEmptyMVar :: IO (MVar (LiveWorkflow.WorkloadObservation Text))
  let command =
        Training.TrainingStop
          Training.StopTraining
            { Training.stopExperimentHash = "late-evidence"
            , Training.stopDrain = True
            }
      delivery deliveryId event =
        PulsarInternal.Delivery
          { PulsarInternal.deliveryEventInternal = event
          , PulsarInternal.deliveryReceiptInternal =
              PulsarInternal.DeliveryReceipt
                { PulsarInternal.receiptSessionInternal = "late-session"
                , PulsarInternal.receiptGenerationInternal = 1
                , PulsarInternal.receiptDeliveryIdInternal = deliveryId
                }
          , PulsarInternal.deliveryRedeliveryCountInternal = 0
          }
      transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.livePublishCommand = const (pure (Right "late-ack"))
          , LiveWorkflow.liveConsumeEvents = \_ observe handleDelivery -> do
              observe (ConsumerSessionConnected 1)
              first <- handleDelivery (delivery "complete" completeEvent)
              case first of
                PulsarInternal.DoneInternal _ result -> pure (Right result)
                PulsarInternal.ContinueInternal _ -> do
                  second <- handleDelivery (delivery "late" lateEvent)
                  pure $ case second of
                    PulsarInternal.DoneInternal _ result -> Right result
                    PulsarInternal.ContinueInternal _ ->
                      Left
                        ( PulsarInternal.ConsumerProtocolFailure
                            "late invalid evidence unexpectedly continued"
                        )
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId = planA
          , LiveWorkflow.liveWorkflowCommand =
              LiveWorkflow.ProtocolCommand commandTopic command
          , LiveWorkflow.liveWorkflowEventSubscription = subscription
          , LiveWorkflow.liveWorkflowInitialProgress = initial
          , LiveWorkflow.liveWorkflowIngest = ingest
          , LiveWorkflow.liveWorkflowFinish = finish
          , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement =
              pure (Right (LiveWorkflow.ClusterJob handle))
          , LiveWorkflow.liveCompletionMode =
              LiveWorkflow.ObserveIndependentWorkload
          , LiveWorkflow.liveObserveWorkload = const (readMVar terminalBlock)
          , LiveWorkflow.liveGatherDiagnostics = const (pure (Right []))
          , LiveWorkflow.liveReleasePlacement = const (pure [])
          , LiveWorkflow.liveObservationAttempts = 1
          , LiveWorkflow.liveObservationDelayMicros = 0
          , LiveWorkflow.liveWorkflowTimeoutMicros = 1_000_000
          }
  result <- LiveWorkflow.runLiveWorkflow workflow transport backend
  case result of
    Right _ -> assertFailure "late invalid evidence unexpectedly completed the workflow"
    Left failure -> do
      case LiveWorkflow.liveFailurePrimary failure of
        Just (LiveWorkflow.LiveReducerRejected violation) ->
          assertBool
            ("unexpected late evidence violation: " <> show violation)
            (isExpectedViolation violation)
        other -> assertFailure ("unexpected late evidence failure: " <> show other)
      let journal = LiveWorkflow.liveFailureJournal failure
          completed =
            [ LiveWorkflow.liveJournalSequence record
            | record <- journal
            , LiveWorkflow.ProtocolEvidenceCompleted <- [LiveWorkflow.liveJournalEvent record]
            ]
          rejected =
            [ LiveWorkflow.liveJournalSequence record
            | record <- journal
            , LiveWorkflow.ProtocolEvidenceRejected {} <- [LiveWorkflow.liveJournalEvent record]
            ]
      case (completed, rejected) of
        (completedAt : _, rejectedAt : _) ->
          assertBool
            "late evidence was rejected after the first complete evidence state"
            (completedAt < rejectedAt)
        _ -> assertFailure "late evidence journal lacks completion/rejection ordering"

supervisedEpochEvent :: Text -> Word32 -> Double -> Training.TrainingEvent
supervisedEpochEvent experimentHash epoch loss =
  Training.TrainingEpoch
    Training.EpochCompleted
      { Training.ecExperimentHash = experimentHash
      , Training.ecEpoch = epoch
      , Training.ecLoss = loss
      , Training.ecValidationLoss = loss
      , Training.ecTimestampNs = fromIntegral epoch + 1
      }

supervisedCompletedCheckpointEvent
  :: PlanId
  -> Word32
  -> Text
  -> Training.TrainingEvent
supervisedCompletedCheckpointEvent completionPlanId epoch experimentHash =
  Training.TrainingCompletedCheckpoint
    ( expectTextRight "completed supervised checkpoint" $ do
        budget <-
          TrainingBudget.mkTrainingBudget
            TrainingBudget.SupervisedEpochBudget
            (fromIntegral epoch)
            (Just 7)
        evidence <-
          ProductEvidence.mkTrainingEvidence
            "supervised-initial-weights"
            "supervised-final-weights"
            (fromIntegral epoch)
            "supervised-dataset-at-read"
        measurement <-
          TrainingBudget.measureCriterion
            "accuracy"
            TrainingBudget.MetricMaximise
            0.5
            0.9
        completed <-
          TrainingBudget.completedTraining
            completionPlanId
            budget
            (fromIntegral epoch)
            evidence
            [measurement]
            TrainingBudget.TensorBoardRunMetadata
              { TrainingBudget.tbrRunId = "supervised-live-run"
              , TrainingBudget.tbrLogPrefix = "tensorboard/supervised-live-run"
              , TrainingBudget.tbrScalarTags = ["accuracy"]
              }
        Training.completeCheckpointDone
          (trainingCheckpointEvent epoch experimentHash)
          completed
    )

trainingCheckpointEvent :: Word32 -> Text -> Training.CheckpointDone
trainingCheckpointEvent epoch experimentHash =
  Training.CheckpointDone
    { Training.cdExperimentHash = experimentHash
    , Training.cdManifestSha = "supervised-live-manifest"
    , Training.cdStep = fromIntegral epoch
    , Training.cdPointerKey = "checkpoints/supervised-live/latest"
    , Training.cdEpoch = epoch
    , Training.cdTrialSha = Nothing
    , Training.cdRunUuid = "supervised-live-run"
    , Training.cdMetricsAtStep = [("accuracy", 0.9)]
    }

expectTextRight :: Text -> Either Text value -> value
expectTextRight label result =
  case result of
    Left failure ->
      error (Text.unpack (label <> ": " <> failure))
    Right value -> value

trainingEvidenceEvent :: Word32 -> Double -> Training.TrainingEvent
trainingEvidenceEvent =
  supervisedEpochEvent "late-evidence"

trainingEventEpoch :: Training.TrainingEvent -> Word32
trainingEventEpoch event =
  case event of
    Training.TrainingEpoch epoch -> Training.ecEpoch epoch
    _ -> 0

diagnosticsBeforeCleanup
  :: [LiveWorkflow.LiveJournalRecord terminal violation missing]
  -> Bool
diagnosticsBeforeCleanup journal =
  case (diagnosticSequences, cleanupSequences) of
    (diagnostic : _, cleanup : _) -> diagnostic < cleanup
    _ -> False
 where
  diagnosticSequences =
    [ LiveWorkflow.liveJournalSequence record
    | record <- journal
    , LiveWorkflow.DiagnosticsGathered {} <- [LiveWorkflow.liveJournalEvent record]
    ]
  cleanupSequences =
    [ LiveWorkflow.liveJournalSequence record
    | record <- journal
    , LiveWorkflow.CleanupRecorded {} <- [LiveWorkflow.liveJournalEvent record]
    ]

releaseLifecycleOrder
  :: [LiveWorkflow.LiveJournalRecord terminal violation missing]
  -> [Text]
releaseLifecycleOrder journal =
  [ label
  | record <- journal
  , Just label <- [releaseLabel (LiveWorkflow.liveJournalEvent record)]
  ]
 where
  releaseLabel event =
    case event of
      LiveWorkflow.DiagnosticsGathered {} -> Just "diagnostics"
      LiveWorkflow.SubscriptionReleased {} -> Just "subscription"
      LiveWorkflow.PlacementReleased {} -> Just "placement"
      _ -> Nothing

refinedEvidence
  :: (Show key)
  => PlanId
  -> Text
  -> key
  -> value
  -> EvidenceEvent key value
refinedEvidence plan kind key value =
  expectSuccess (evidenceEvent plan kind key value)

planA :: PlanId
planA = expectSuccess (planIdFromCanonicalText "run-contract-plan-a")

planB :: PlanId
planB = expectSuccess (planIdFromCanonicalText "run-contract-plan-b")

eventId :: PlanId -> Text -> Text -> EventId
eventId plan kind key =
  expectSuccess (deriveEventIdForPlanId plan kind key)

checkpointEventId :: EventId
checkpointEventId = eventId planA "checkpoint" "()"

secondCheckpointEventId :: EventId
secondCheckpointEventId = eventId planA "checkpoint-alternate" "()"

telemetryEvent0 :: EventId
telemetryEvent0 = eventId planA "telemetry" "0"

evaluationEvent0 :: EventId
evaluationEvent0 = eventId planA "evaluation" "0"

updateEventId :: EventId
updateEventId = eventId planA "training-progress" "1"

curveEventId :: EventId
curveEventId = eventId planA "learning-curve" "1"

oneOptimizerUpdate :: Quantity 'OptimizerUpdate
oneOptimizerUpdate = expectSuccess (mkQuantity "optimizer-update" 1)

curveMeasurement :: FiniteMeasurement
curveMeasurement = expectSuccess (mkFiniteMeasurement "training-loss" 0.75)

finalMeasurement :: FiniteMeasurement
finalMeasurement = expectSuccess (mkFiniteMeasurement "final-return" 42.0)

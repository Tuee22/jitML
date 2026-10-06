{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Contract tests for the established event source of 'runLiveWorkflow'.
--
-- A correlated harness request is published only after the transport has
-- established the evidence source (for a broker source, after the durable
-- cursor exists), never on the strength of the diagnostic
-- 'ConsumerSessionConnected' socket-open event.  These tests drive the
-- interpreter through a scripted broker transport whose every hook is
-- observable, so the ordering, the exactly-once release, the cancellation
-- identity, and the failure typing are asserted on the interpreter itself and
-- not on the wire.  The offline fake-node and fake-admin tests in
-- "JitML.Test.PulsarTransport" prove the same order on the real Pulsar
-- harness transport.
--
-- The scripted broker transport is private to this module. The lifecycle controls
-- drive their own scripted scenarios ("JitML.Test.LifecycleFixtures"); the two fakes
-- overlap and are candidates for consolidation.
module JitML.Test.LiveWorkflowEstablishment
  ( completedMilestones
  , journalMilestones
  , liveWorkflowEstablishmentTests
  )
where

import Control.Concurrent (ThreadId, threadDelay, throwTo)
import Control.Concurrent.Async
  ( AsyncCancelled (..)
  , async
  , asyncThreadId
  , cancel
  , wait
  , waitCatch
  )
import Control.Concurrent.MVar
  ( MVar
  , modifyMVar_
  , newEmptyMVar
  , newMVar
  , putMVar
  , readMVar
  , takeMVar
  )
import Control.Exception
  ( SomeException
  , fromException
  , mask
  , throwIO
  , try
  , uninterruptibleMask_
  )
import Control.Monad (when)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Conc (BlockReason (..), ThreadStatus (..), threadStatus)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertEqual
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Coordinator.Topology (ProtocolRoute (..), topicFor, topicName)
import JitML.Plan.Plan (PlanId, Validation (..), planIdFromCanonicalText)
import JitML.Proto.Training qualified as Training
import JitML.Service.Capabilities
  ( ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , mkSubscription
  , subscriptionOwnership
  )
import JitML.Service.Pulsar.Internal qualified as PulsarInternal
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.LiveWorkflow qualified as LiveWorkflow

-- | The ordered record of what the scripted transport and backend were asked
-- to do.  Appends are atomic so the consumer thread and the interpreter thread
-- can both write it.
newtype BrokerLog = BrokerLog (MVar [Text])

newBrokerLog :: IO BrokerLog
newBrokerLog = BrokerLog <$> newMVar []

logEvent :: BrokerLog -> Text -> IO ()
logEvent (BrokerLog ref) label = modifyMVar_ ref (pure . (label :))

readBrokerLog :: BrokerLog -> IO [Text]
readBrokerLog (BrokerLog ref) = reverse <$> readMVar ref

-- | What each hook of the scripted transport does.  Every hook writes its own
-- label to the 'BrokerLog' (the diagnostics gather only once it completes), so
-- a hook that is never called, or is interrupted, leaves no label.
data BrokerScript = BrokerScript
  { scriptEstablish :: IO (Either ServiceError ())
  -- ^ Runs inside the establishment hook; 'Right' mints the token.
  , scriptPublish :: IO (Either ServiceError Text)
  -- ^ The publication through the established token.
  , scriptRelease :: IO (Either ConsumerFailure ())
  -- ^ The single release of the established token.
  , scriptDiagnostics :: IO ()
  -- ^ Effect performed by the backend's diagnostics gather before it completes
  -- (and logs), so an interrupted gather leaves no label.
  , scriptReportsConnected :: Bool
  -- ^ Whether the consumer reports the diagnostic socket-open event.
  , scriptConsumerFailure :: Maybe ConsumerFailure
  -- ^ When present, the consumer fails with it right after attaching to the
  -- established view: no socket-open event is reported and no delivery arrives.
  , scriptConsumerShutdownFailure :: Maybe ConsumerFailure
  -- ^ When present, a consumer that has delivered its evidence reports it when
  -- the interpreter stops it, instead of rethrowing the cancellation: what a
  -- consumer of an @Owned@ view returns when its own cleanup fails.  A
  -- transport may hand the consumer such a view, so the interpreter must retain
  -- these failures wherever they are reported.
  , scriptCompletionMode :: LiveWorkflow.LiveCompletionMode
  -- ^ The backend's completion mode; a mode that disagrees with the
  -- @RequestReply@ placement is a boundary mismatch.
  , scriptPlacementOwnedByAnotherPlan :: Bool
  -- ^ Whether the acquired placement belongs to a different plan.
  }

-- | A transport that establishes, publishes, and releases successfully and whose
-- consumer reports the socket-open event.
defaultBrokerScript :: BrokerScript
defaultBrokerScript =
  BrokerScript
    { scriptEstablish = pure (Right ())
    , scriptPublish = pure (Right "scripted-ack")
    , scriptRelease = pure (Right ())
    , scriptDiagnostics = pure ()
    , scriptReportsConnected = True
    , scriptConsumerFailure = Nothing
    , scriptConsumerShutdownFailure = Nothing
    , scriptCompletionMode = LiveWorkflow.ResponseCompletesRequest
    , scriptPlacementOwnedByAnotherPlan = False
    }

type BrokerFailure = LiveWorkflow.LiveRunFailure Text () Text Text

type BrokerCompleted = LiveWorkflow.CompletedRunEvidence Text () Text Text

type BrokerJournal = [LiveWorkflow.LiveJournalRecord Text Text Text]

-- | The outcome of one scripted run.
data BrokerRun = BrokerRun
  { brokerResult :: Either BrokerFailure BrokerCompleted
  , brokerPlacementReleases :: Int
  , brokerOwnershipSeenByConsumer :: Maybe SubscriptionOwnership
  , brokerPublishedCommands :: [Text]
  -- ^ The canonical text of every command published through the token.
  }

runBrokerScript :: BrokerLog -> BrokerScript -> IO BrokerRun
runBrokerScript brokerLog script = do
  planA <- planFixture
  otherPlan <- otherPlanFixture
  commandTopic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
  eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
  owned <- expectRight (mkSubscription eventTopic "broker-script-owned" FromLatest Owned)
  borrowed <- expectRight (mkSubscription eventTopic "broker-script-owned" FromLatest Borrowed)
  requestHandle <-
    expectRight
      ( LiveWorkflow.mkRequestHandle
          (if scriptPlacementOwnedByAnotherPlan script then otherPlan else planA)
          "broker-script"
      )
  placementReleases <- newIORef (0 :: Int)
  ownershipSeen <- newIORef Nothing
  publishedCommands <- newIORef ([] :: [Text])
  consumerBlock <- newEmptyMVar :: IO (MVar ())
  let command =
        Training.TrainingStop
          Training.StopTraining
            { Training.stopExperimentHash = "broker-script"
            , Training.stopDrain = True
            }
      event =
        Training.TrainingEpoch
          Training.EpochCompleted
            { Training.ecExperimentHash = "broker-script"
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
                { PulsarInternal.receiptSessionInternal = "broker-script-session"
                , PulsarInternal.receiptGenerationInternal = 1
                , PulsarInternal.receiptDeliveryIdInternal = "broker-script-delivery"
                }
          , PulsarInternal.deliveryRedeliveryCountInternal = 0
          }
      transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.liveEstablishEventSource = \_command _source -> do
              logEvent brokerLog "establish"
              established <- scriptEstablish script
              pure $ case established of
                Left failure -> Left failure
                Right () ->
                  Right
                    ( LiveWorkflow.establishedEventSource
                        (LiveWorkflow.pulsarEventSource borrowed)
                        ( \publishedCommand -> do
                            logEvent brokerLog "publish"
                            atomicModifyIORef'
                              publishedCommands
                              ( \texts ->
                                  ( texts <> [LiveWorkflow.liveCommandCanonicalText publishedCommand]
                                  , ()
                                  )
                              )
                            scriptPublish script
                        )
                        ( do
                            logEvent brokerLog "release"
                            scriptRelease script
                        )
                    )
          , LiveWorkflow.liveConsumeEvents = \established observe handleDelivery -> do
              logEvent brokerLog "consume"
              atomicModifyIORef'
                ownershipSeen
                ( const
                    ( subscriptionOwnership
                        <$> LiveWorkflow.liveEventSourceSubscription
                          (LiveWorkflow.establishedEventSourceView established)
                    , ()
                    )
                )
              case scriptConsumerFailure script of
                Just failure -> pure (Left failure)
                Nothing -> mask $ \unmasked -> do
                  when (scriptReportsConnected script) (observe (ConsumerSessionConnected 1))
                  decision <- handleDelivery delivery
                  case decision of
                    PulsarInternal.DoneInternal _ result -> pure (Right result)
                    PulsarInternal.ContinueInternal _ -> do
                      -- The delivery has already signalled completed evidence, so
                      -- the interpreter may stop this consumer at any moment from
                      -- here on.  Staying masked until the block below delivers
                      -- such a stop inside the handler, never in the gap before it.
                      interrupted <-
                        try (unmasked (readMVar consumerBlock))
                          :: IO (Either AsyncCancelled ())
                      case interrupted of
                        Left cancelled -> do
                          logEvent brokerLog "consumer-stopped"
                          case scriptConsumerShutdownFailure script of
                            Just failure -> pure (Left failure)
                            Nothing -> throwIO cancelled
                        Right () ->
                          pure
                            ( Left
                                ( ConsumerProtocolFailure
                                    "scripted consumer block was released unexpectedly"
                                )
                            )
          }
      workflow =
        LiveWorkflow.LiveWorkflow
          { LiveWorkflow.liveWorkflowPlanId = planA
          , LiveWorkflow.liveWorkflowCommand =
              LiveWorkflow.ProtocolCommand commandTopic command
          , LiveWorkflow.liveWorkflowEventSource =
              LiveWorkflow.pulsarEventSource owned
          , LiveWorkflow.liveWorkflowInitialProgress = False
          , LiveWorkflow.liveWorkflowIngest = \_ _ -> Right True
          , LiveWorkflow.liveWorkflowFinish = \seen ->
              if seen then Success () else Failure "no evidence observed"
          , LiveWorkflow.liveWorkflowRenderViolation = id
          }
      backend =
        LiveWorkflow.LiveBackend
          { LiveWorkflow.liveAcquirePlacement =
              pure (Right (LiveWorkflow.RequestReply requestHandle))
          , LiveWorkflow.liveCompletionMode = scriptCompletionMode script
          , LiveWorkflow.liveObserveWorkload =
              const (pure (LiveWorkflow.Succeeded "unused-request-terminal"))
          , LiveWorkflow.liveGatherDiagnostics = const $ do
              scriptDiagnostics script
              logEvent brokerLog "diagnostics"
              pure (Right [LiveWorkflow.LiveDiagnostic "scripted diagnostics"])
          , LiveWorkflow.liveReleasePlacement = const $ do
              logEvent brokerLog "placement"
              atomicModifyIORef' placementReleases (\count -> (count + 1, ()))
              pure []
          , LiveWorkflow.liveObservationAttempts = 1
          , LiveWorkflow.liveObservationDelayMicros = 0
          , LiveWorkflow.liveWorkflowTimeoutMicros = 5_000_000
          }
  result <- LiveWorkflow.runLiveWorkflow workflow transport backend
  releases <- readIORef placementReleases
  seen <- readIORef ownershipSeen
  commands <- readIORef publishedCommands
  pure
    BrokerRun
      { brokerResult = result
      , brokerPlacementReleases = releases
      , brokerOwnershipSeenByConsumer = seen
      , brokerPublishedCommands = commands
      }

liveWorkflowEstablishmentTests :: TestTree
liveWorkflowEstablishmentTests =
  testGroup
    "LiveWorkflow event-source establishment"
    [ testCase "completes although ConsumerSessionConnected never fires" $ do
        brokerLog <- newBrokerLog
        run <-
          withinTimeout $
            runBrokerScript brokerLog defaultBrokerScript {scriptReportsConnected = False}
        completed <- requireCompleted run
        assertBool
          "the consumer was scripted never to report the socket-open event"
          ( not
              ( any
                  ( \case
                      LiveWorkflow.ConsumerSessionObserved (ConsumerSessionConnected _) -> True
                      _ -> False
                  )
                  (journalEvents (LiveWorkflow.completedRunJournal completed))
              )
          )
        journalMilestones (LiveWorkflow.completedRunJournal completed)
          @?= completedMilestones
    , testCase "socket-open observation is journalled as a diagnostic and gates nothing" $ do
        brokerLog <- newBrokerLog
        run <- withinTimeout (runBrokerScript brokerLog defaultBrokerScript)
        completed <- requireCompleted run
        assertBool
          "an observed socket-open event stays in the journal as a diagnostic"
          ( any
              ( \case
                  LiveWorkflow.ConsumerSessionObserved (ConsumerSessionConnected _) -> True
                  _ -> False
              )
              (journalEvents (LiveWorkflow.completedRunJournal completed))
          )
        journalMilestones (LiveWorkflow.completedRunJournal completed)
          @?= completedMilestones
    , testCase "establishes strictly before publishing and releases once after diagnostics" $ do
        brokerLog <- newBrokerLog
        run <- withinTimeout (runBrokerScript brokerLog defaultBrokerScript)
        completed <- requireCompleted run
        -- The interpreter's own journal.
        journalMilestones (LiveWorkflow.completedRunJournal completed)
          @?= completedMilestones
        -- The transport's view of the same order.  The consumer thread runs
        -- concurrently, so only the interpreter-driven hooks are compared.
        driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
        driven @?= ["establish", "publish", "diagnostics", "release", "placement"]
        brokerPlacementReleases run @?= 1
        -- The token publishes exactly the command the journal recorded, and the
        -- journalled source is the workflow's own.
        eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
        let journal = LiveWorkflow.completedRunJournal completed
        brokerPublishedCommands run
          @?= [ payload
              | LiveWorkflow.CommandPublicationStarted _address payload <- journalEvents journal
              ]
        assertBool
          "the established source keeps the workflow source's name and address"
          ( LiveWorkflow.EventSourceEstablished "broker-script-owned" (topicName eventTopic)
              `elem` journalEvents journal
          )
    , testCase "the consumer attaches to the established borrowed view, not the workflow source" $ do
        brokerLog <- newBrokerLog
        run <- withinTimeout (runBrokerScript brokerLog defaultBrokerScript)
        _completed <- requireCompleted run
        -- The workflow's source is Owned; the token's view is Borrowed.
        brokerOwnershipSeenByConsumer run @?= Just Borrowed
    , testCase "the consumer stops before the established source is released" $ do
        brokerLog <- newBrokerLog
        run <- withinTimeout (runBrokerScript brokerLog defaultBrokerScript)
        _completed <- requireCompleted run
        labels <- readBrokerLog brokerLog
        assertBool
          ("the consumer must be joined before release: " <> show labels)
          (orderedSubsequence ["consumer-stopped", "release", "placement"] labels)
    , testCase "establishment failure publishes nothing and releases the placement once" $ do
        brokerLog <- newBrokerLog
        let refusal = SEConflict "cursor CREATE refused"
        run <-
          withinTimeout $
            runBrokerScript brokerLog defaultBrokerScript {scriptEstablish = pure (Left refusal)}
        failure <- requireFailure run
        LiveWorkflow.liveFailurePrimary failure
          @?= Just (LiveWorkflow.LiveEstablishFailed refusal)
        LiveWorkflow.liveFailureCompletion failure @?= Nothing
        LiveWorkflow.liveFailureCleanupIssues failure @?= []
        let journal = LiveWorkflow.liveFailureJournal failure
        journalMilestones journal
          @?= [ "placement-acquired"
              , "source-establishment-failed"
              , "diagnostics"
              , "placement-released"
              ]
        assertBool
          "the typed refusal is journalled"
          ( LiveWorkflow.EventSourceEstablishmentFailed refusal
              `elem` journalEvents journal
          )
        -- Nothing after the refused establishment ran: no publish, no
        -- consumer, no release of a token that never existed.
        readBrokerLog brokerLog
          >>= (@?= ["establish", "diagnostics", "placement"])
        brokerPlacementReleases run @?= 1
    , testCase "every typed establishment failure class reaches the primary failure unchanged" $
        mapM_
          ( \refusal -> do
              brokerLog <- newBrokerLog
              run <-
                withinTimeout $
                  runBrokerScript brokerLog defaultBrokerScript {scriptEstablish = pure (Left refusal)}
              failure <- requireFailure run
              LiveWorkflow.liveFailurePrimary failure
                @?= Just (LiveWorkflow.LiveEstablishFailed refusal)
              brokerPlacementReleases run @?= 1
          )
          [ SEConflict "must be Owned"
          , SETransient "admin CREATE unreachable"
          , SETimeout "admin CREATE timed out"
          , SEUnauthorized "admin CREATE forbidden"
          , SENotFound "tenant missing"
          ]
    , testCase "an establishment hook that throws is an interpreter failure with nothing published" $ do
        brokerLog <- newBrokerLog
        run <-
          withinTimeout $
            runBrokerScript
              brokerLog
              defaultBrokerScript {scriptEstablish = ioError (userError "CREATE exploded")}
        failure <- requireFailure run
        -- A thrown exception is not a typed refusal: it is an interpreter
        -- failure, and no token exists to release.
        case LiveWorkflow.liveFailurePrimary failure of
          Just (LiveWorkflow.LiveInterpreterException detail) ->
            assertBool
              ("the hook exception was lost: " <> Text.unpack detail)
              ("CREATE exploded" `Text.isInfixOf` detail)
          other -> assertFailure ("unexpected primary failure: " <> show other)
        LiveWorkflow.liveFailureCompletion failure @?= Nothing
        LiveWorkflow.liveFailureCleanupIssues failure @?= []
        journalMilestones (LiveWorkflow.liveFailureJournal failure)
          @?= ["placement-acquired", "diagnostics", "placement-released"]
        readBrokerLog brokerLog
          >>= (@?= ["establish", "diagnostics", "placement"])
        brokerPlacementReleases run @?= 1
    , testCase "a completion-boundary mismatch is refused before any establishment" $ do
        brokerLog <- newBrokerLog
        run <-
          withinTimeout $
            runBrokerScript
              brokerLog
              defaultBrokerScript
                { scriptCompletionMode = LiveWorkflow.ObserveIndependentWorkload
                }
        failure <- requireFailure run
        LiveWorkflow.liveFailurePrimary failure
          @?= Just
            ( LiveWorkflow.LiveCompletionBoundaryMismatch
                "RequestReply placement cannot claim an independent workload terminal"
            )
        journalMilestones (LiveWorkflow.liveFailureJournal failure)
          @?= ["placement-acquired", "diagnostics", "placement-released"]
        readBrokerLog brokerLog >>= (@?= ["diagnostics", "placement"])
        brokerPlacementReleases run @?= 1
    , testCase "a placement owned by another plan is released without establishing anything" $ do
        brokerLog <- newBrokerLog
        run <-
          withinTimeout $
            runBrokerScript
              brokerLog
              defaultBrokerScript {scriptPlacementOwnedByAnotherPlan = True}
        failure <- requireFailure run
        case LiveWorkflow.liveFailurePrimary failure of
          Just (LiveWorkflow.LivePlacementPlanMismatch _expected _actual) -> pure ()
          other -> assertFailure ("unexpected primary failure: " <> show other)
        journalMilestones (LiveWorkflow.liveFailureJournal failure)
          @?= ["placement-acquired", "diagnostics", "placement-released"]
        readBrokerLog brokerLog >>= (@?= ["diagnostics", "placement"])
        brokerPlacementReleases run @?= 1
    , testCase "publication failure after establishment releases the source exactly once" $ do
        brokerLog <- newBrokerLog
        let refusal = SETransient "broker refused the publish"
        run <-
          withinTimeout $
            runBrokerScript brokerLog defaultBrokerScript {scriptPublish = pure (Left refusal)}
        failure <- requireFailure run
        LiveWorkflow.liveFailurePrimary failure
          @?= Just (LiveWorkflow.LivePublishFailed refusal)
        LiveWorkflow.liveFailureCleanupIssues failure @?= []
        journalMilestones (LiveWorkflow.liveFailureJournal failure)
          @?= [ "placement-acquired"
              , "source-established"
              , "publication-started"
              , "publication-failed"
              , "diagnostics"
              , "source-released"
              , "placement-released"
              ]
        driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
        driven @?= ["establish", "publish", "diagnostics", "release", "placement"]
        brokerPlacementReleases run @?= 1
    , testCase
        "a consumer that fails right after establishment is the primary failure and the source is still released once"
        $ do
          brokerLog <- newBrokerLog
          let consumerFailure =
                ConsumerProtocolFailure "scripted consumer died after establishment"
          run <-
            withinTimeout $
              runBrokerScript
                brokerLog
                defaultBrokerScript {scriptConsumerFailure = Just consumerFailure}
          failure <- requireFailure run
          LiveWorkflow.liveFailurePrimary failure
            @?= Just (LiveWorkflow.LiveConsumerFailed consumerFailure)
          LiveWorkflow.liveFailureCompletion failure @?= Nothing
          LiveWorkflow.liveFailureCleanupIssues failure @?= []
          -- Nothing gates publication on the consumer: the command is published
          -- once the source is established, and the dead consumer surfaces when
          -- the evidence is awaited.  The source is nevertheless released once,
          -- after the diagnostics and before the placement.
          journalMilestones (LiveWorkflow.liveFailureJournal failure)
            @?= [ "placement-acquired"
                , "source-established"
                , "publication-started"
                , "published"
                , "diagnostics"
                , "source-released"
                , "placement-released"
                ]
          driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
          driven @?= ["establish", "publish", "diagnostics", "release", "placement"]
          brokerPlacementReleases run @?= 1
    , testCase "cancellation after establishment releases once, after diagnostics, keeping its identity" $ do
        brokerLog <- newBrokerLog
        publishEntered <- newEmptyMVar :: IO (MVar ())
        publishGate <- newEmptyMVar :: IO (MVar ())
        runner <-
          async
            ( runBrokerScript
                brokerLog
                defaultBrokerScript
                  { scriptPublish = putMVar publishEntered () >> readMVar publishGate >> pure (Right "never")
                  }
            )
        withinTimeout (readMVar publishEntered)
        cancel runner
        cancelled <- withinTimeout (waitCatch runner)
        requireCancellation cancelled
        driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
        driven @?= ["establish", "publish", "diagnostics", "release", "placement"]
    , testCase
        "cancellation racing an uninterruptible establishment is delivered after the token exists and releases it once"
        $ do
          brokerLog <- newBrokerLog
          establishing <- newEmptyMVar :: IO (MVar ())
          establishGate <- newEmptyMVar :: IO (MVar ())
          runner <-
            async
              ( runBrokerScript
                  brokerLog
                  defaultBrokerScript
                    { scriptEstablish =
                        uninterruptibleMask_
                          (putMVar establishing () >> readMVar establishGate >> pure (Right ()))
                    }
              )
          withinTimeout (readMVar establishing)
          canceller <- async (cancel runner)
          awaitBlockedOnException (asyncThreadId canceller)
          -- The cancellation is now queued behind the uninterruptible CREATE.
          putMVar establishGate ()
          withinTimeout (wait canceller)
          cancelled <- withinTimeout (waitCatch runner)
          requireCancellation cancelled
          -- The token existed, so it was released; publication never started;
          -- diagnostics still preceded the release.
          driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
          driven @?= ["establish", "diagnostics", "release", "placement"]
    , testCase "repeated cancellation cannot skip the release of an established source or its diagnostics" $ do
        brokerLog <- newBrokerLog
        publishEntered <- newEmptyMVar :: IO (MVar ())
        publishGate <- newEmptyMVar :: IO (MVar ())
        diagnosticsEntered <- newEmptyMVar :: IO (MVar ())
        diagnosticsGate <- newEmptyMVar :: IO (MVar ())
        diagnosticsCalls <- newIORef (0 :: Int)
        let gatherWhileBeingCancelled = do
              call <-
                atomicModifyIORef' diagnosticsCalls (\count -> (count + 1, count + 1))
              -- The first two gathers block until they are interrupted; the
              -- third, which the interpreter runs after the consumer scope
              -- was torn down by the third cancellation, completes.
              when (call <= 2) (putMVar diagnosticsEntered () >> readMVar diagnosticsGate)
        runner <-
          async
            ( runBrokerScript
                brokerLog
                defaultBrokerScript
                  { scriptPublish = putMVar publishEntered () >> readMVar publishGate >> pure (Right "never")
                  , scriptDiagnostics = gatherWhileBeingCancelled
                  }
            )
        let interrupt = throwTo (asyncThreadId runner) AsyncCancelled
        -- Cancellation 1 lands in the blocked publication.
        withinTimeout (readMVar publishEntered)
        interrupt
        -- Cancellation 2 lands in the first (in-scope) diagnostics gather.
        withinTimeout (takeMVar diagnosticsEntered)
        interrupt
        -- Cancellation 3 lands in the masked retry and escapes the consumer
        -- scope, which the interpreter must still close out.
        withinTimeout (takeMVar diagnosticsEntered)
        interrupt
        cancelled <- withinTimeout (waitCatch runner)
        requireCancellation cancelled
        readIORef diagnosticsCalls >>= (@?= 3)
        driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
        driven @?= ["establish", "publish", "diagnostics", "release", "placement"]
    , testCase "cancellation interrupting an establishment that returned no token has nothing to release" $ do
        brokerLog <- newBrokerLog
        establishing <- newEmptyMVar :: IO (MVar ())
        establishGate <- newEmptyMVar :: IO (MVar ())
        runner <-
          async
            ( runBrokerScript
                brokerLog
                defaultBrokerScript
                  { scriptEstablish =
                      putMVar establishing () >> readMVar establishGate >> pure (Right ())
                  }
            )
        withinTimeout (readMVar establishing)
        cancel runner
        cancelled <- withinTimeout (waitCatch runner)
        requireCancellation cancelled
        -- An interruptible hook owns its own cleanup until it returns a token:
        -- the interpreter releases nothing it was never given, and the placement
        -- is still released after diagnostics.
        driven <- filter (`elem` interpreterHooks) <$> readBrokerLog brokerLog
        driven @?= ["establish", "diagnostics", "placement"]
    , testCase "a release that reports a cleanup failure is retained and withholds completion" $ do
        brokerLog <- newBrokerLog
        let cleanupFailure = ConsumerCleanupFailure (SETransient "cursor DELETE returned 500")
        run <-
          withinTimeout $
            runBrokerScript brokerLog defaultBrokerScript {scriptRelease = pure (Left cleanupFailure)}
        failure <- requireFailure run
        LiveWorkflow.liveFailurePrimary failure @?= Nothing
        LiveWorkflow.liveFailureCompletion failure
          @?= Just (LiveWorkflow.RequestResponseCompleted, ())
        case LiveWorkflow.liveFailureCleanupIssues failure of
          [LiveWorkflow.CleanupIssue detail] ->
            assertBool
              ("release failure detail was lost: " <> Text.unpack detail)
              ( "cursor DELETE returned 500" `Text.isInfixOf` detail
                  && "broker-script-owned" `Text.isInfixOf` detail
              )
          issues -> assertFailure ("unexpected cleanup issues: " <> show issues)
        assertBool
          "a failed release is never journalled as a release"
          ( not
              ( any
                  ( \case
                      LiveWorkflow.SubscriptionReleased {} -> True
                      _ -> False
                  )
                  (journalEvents (LiveWorkflow.liveFailureJournal failure))
              )
          )
        brokerPlacementReleases run @?= 1
    , testCase "a release that throws is retained as a cleanup issue, not lost" $
        assertReleaseRetained
          "a thrown release"
          (ioError (userError "DELETE exploded"))
          ["DELETE exploded"]
    , testCase
        "a release that fails with a non-cleanup failure is retained, never journalled as a release, and withholds completion"
        $ mapM_
          (uncurry assertReleaseFailureRetained)
          [
            ( ConsumerProtocolFailure "cursor DELETE answered with garbage"
            , ["cursor DELETE answered with garbage"]
            )
          ,
            ( ConsumerHandlerFailure "release handler exploded"
            , ["release handler exploded"]
            )
          ,
            ( ConsumerPermitFailure (SETransient "permit refused during release")
            , ["permit refused during release"]
            )
          ]
    , testCase
        "a release that fails with a cleanup-context failure keeps both its context and its cleanup detail"
        $ assertReleaseFailureRetained
          ( ConsumerCleanupContextFailure
              (ConsumerProtocolFailure "release context lost")
              (SETransient "cursor DELETE returned 500")
          )
          ["release context lost", "cursor DELETE returned 500"]
    , testCase
        "a consumer that reports a cleanup failure when stopped is retained and withholds completion"
        $ do
          brokerLog <- newBrokerLog
          let cleanupError = SETransient "consumer-owned cursor DELETE returned 500"
          run <-
            withinTimeout $
              runBrokerScript
                brokerLog
                defaultBrokerScript
                  { scriptConsumerShutdownFailure = Just (ConsumerCleanupFailure cleanupError)
                  }
          failure <-
            requireRetainedCleanup
              ["consumer-owned cursor DELETE returned 500", "broker-script-owned"]
              run
          -- A cleanup failure never replaces the primary: this workflow had none.
          LiveWorkflow.liveFailurePrimary failure @?= Nothing
          -- The failure really was reported by the consumer the interpreter stopped.
          labels <- readBrokerLog brokerLog
          assertBool
            ("the consumer must have been stopped by the interpreter: " <> show labels)
            ("consumer-stopped" `elem` labels)
    , testCase
        "a consumer that reports a cleanup-context failure when stopped keeps its own primary and retains the cleanup"
        $ do
          brokerLog <- newBrokerLog
          let consumerPrimary = ConsumerProtocolFailure "consumer died while being stopped"
              cleanupError = SETransient "consumer-owned cursor DELETE returned 500"
          run <-
            withinTimeout $
              runBrokerScript
                brokerLog
                defaultBrokerScript
                  { scriptConsumerShutdownFailure =
                      Just (ConsumerCleanupContextFailure consumerPrimary cleanupError)
                  }
          failure <-
            requireRetainedCleanup
              ["consumer-owned cursor DELETE returned 500", "broker-script-owned"]
              run
          -- The consumer's own failure is the primary, unwrapped from its cleanup
          -- context; the cleanup failure is retained beside it.
          LiveWorkflow.liveFailurePrimary failure
            @?= Just (LiveWorkflow.LiveConsumerFailed consumerPrimary)
          labels <- readBrokerLog brokerLog
          assertBool
            ("the consumer must have been stopped by the interpreter: " <> show labels)
            ("consumer-stopped" `elem` labels)
    , testCase "a local evidence source never reaches a broker transport's establishment hook" $ do
        brokerLog <- newBrokerLog
        result <- withinTimeout (runLocalSourceOnBrokerTransport brokerLog)
        case result of
          Right completed ->
            assertFailure ("mismatched local source completed: " <> show completed)
          Left failure -> do
            LiveWorkflow.liveFailurePrimary failure
              @?= Just
                ( LiveWorkflow.LiveCompletionBoundaryMismatch
                    "local evidence source cannot use a broker transport"
                )
        readBrokerLog brokerLog >>= (@?= ["diagnostics", "placement"])
    , testCase "a broker evidence source never reaches a local transport" $ do
        brokerLog <- newBrokerLog
        result <- withinTimeout (runBrokerSourceOnLocalTransport brokerLog)
        case result of
          Right completed ->
            assertFailure ("mismatched broker source completed: " <> show completed)
          Left failure ->
            LiveWorkflow.liveFailurePrimary failure
              @?= Just
                ( LiveWorkflow.LiveCompletionBoundaryMismatch
                    "Pulsar evidence source cannot use a local executable transport"
                )
        readBrokerLog brokerLog >>= (@?= ["diagnostics", "placement"])
    , testCase "a local source completes without any establishment or release record" $ do
        brokerLog <- newBrokerLog
        result <- withinTimeout (runLocalSourceOnLocalTransport brokerLog)
        case result of
          Left failure -> assertFailure ("local workflow failed: " <> show failure)
          Right completed -> do
            let labels =
                  journalMilestones (LiveWorkflow.completedRunJournal completed)
            assertBool
              ("a local source must not journal establishment or release: " <> show labels)
              ( all
                  ( `notElem`
                      [ "source-established"
                      , "source-establishment-failed"
                      , "source-released"
                      ]
                  )
                  labels
              )
            assertBool
              "the local source journals its own readiness"
              ( any
                  ( \case
                      LiveWorkflow.LocalEvidenceSourceReady {} -> True
                      _ -> False
                  )
                  (journalEvents (LiveWorkflow.completedRunJournal completed))
              )
        readBrokerLog brokerLog >>= (@?= ["execute", "diagnostics", "placement"])
    ]

-- The interpreter drives these hooks in a single thread; the consumer hooks are
-- concurrent and therefore excluded from ordered comparisons.
interpreterHooks :: [Text]
interpreterHooks = ["establish", "publish", "diagnostics", "release", "placement"]

-- | The journal milestones of a run that completed with everything succeeding.
completedMilestones :: [Text]
completedMilestones =
  [ "placement-acquired"
  , "source-established"
  , "publication-started"
  , "published"
  , "evidence-completed"
  , "diagnostics"
  , "source-released"
  , "placement-released"
  ]

-- | The journal reduced to the records that pin the establish, publish, and
-- release order.
journalMilestones
  :: [LiveWorkflow.LiveJournalRecord terminal violation missing]
  -> [Text]
journalMilestones journal =
  [ label
  | record <- journal
  , Just label <- [milestone (LiveWorkflow.liveJournalEvent record)]
  ]
 where
  milestone event =
    case event of
      LiveWorkflow.PlacementAcquired {} -> Just "placement-acquired"
      LiveWorkflow.EventSourceEstablished {} -> Just "source-established"
      LiveWorkflow.EventSourceEstablishmentFailed {} -> Just "source-establishment-failed"
      LiveWorkflow.CommandPublicationStarted {} -> Just "publication-started"
      LiveWorkflow.CommandPublished {} -> Just "published"
      LiveWorkflow.CommandPublicationFailed {} -> Just "publication-failed"
      LiveWorkflow.ProtocolEvidenceCompleted -> Just "evidence-completed"
      LiveWorkflow.DiagnosticsGathered {} -> Just "diagnostics"
      LiveWorkflow.SubscriptionReleased {} -> Just "source-released"
      LiveWorkflow.PlacementReleased {} -> Just "placement-released"
      _ -> Nothing

journalEvents :: BrokerJournal -> [LiveWorkflow.LiveJournalEvent Text Text Text]
journalEvents = fmap LiveWorkflow.liveJournalEvent

-- | A local evidence source paired with a broker transport: a boundary
-- mismatch that must be refused before the establishment hook exists to be
-- called.
runLocalSourceOnBrokerTransport
  :: BrokerLog
  -> IO (Either BrokerFailure BrokerCompleted)
runLocalSourceOnBrokerTransport brokerLog = do
  planA <- planFixture
  source <-
    expectRight (LiveWorkflow.localEventSource "local-source" "local-address" (const "rendered"))
  handle <- expectRight (LiveWorkflow.mkHostRunHandle planA "local-on-broker")
  let transport =
        LiveWorkflow.LiveTransport
          { LiveWorkflow.liveEstablishEventSource = \_command _source -> do
              logEvent brokerLog "establish"
              pure (Left (SEConflict "establishment must not be reached"))
          , LiveWorkflow.liveConsumeEvents = \_established _observe _handle -> do
              logEvent brokerLog "consume"
              pure (Left (ConsumerProtocolFailure "consumption must not be reached"))
          }
  LiveWorkflow.runLiveWorkflow
    (localWorkflow planA source)
    transport
    (localBackend brokerLog (LiveWorkflow.HostRun handle))

-- | A broker evidence source paired with a local transport, whose three hooks
-- must never run.
runBrokerSourceOnLocalTransport
  :: BrokerLog
  -> IO (Either BrokerFailure BrokerCompleted)
runBrokerSourceOnLocalTransport brokerLog = do
  planA <- planFixture
  eventTopic <- expectRight (topicFor TrainingEventRoute LinuxCPU)
  subscription <-
    expectRight (mkSubscription eventTopic "local-transport-broker-source" FromLatest Owned)
  handle <- expectRight (LiveWorkflow.mkHostRunHandle planA "broker-on-local")
  let transport =
        LiveWorkflow.LocalExecutableTransport
          { LiveWorkflow.liveObserveLocalPrecondition = \_ -> do
              logEvent brokerLog "observe"
              pure (Right "observed")
          , LiveWorkflow.liveExecuteLocalCommand = \_ -> do
              logEvent brokerLog "execute"
              pure (Right "executed")
          , LiveWorkflow.liveResolveLocalEvidence = \_ -> do
              logEvent brokerLog "resolve"
              pure (Left (SEConflict "resolution must not be reached"))
          }
      workflow =
        localWorkflow planA (LiveWorkflow.pulsarEventSource subscription)
  LiveWorkflow.runLiveWorkflow
    workflow
    transport
    (localBackend brokerLog (LiveWorkflow.HostRun handle))

-- | The ordinary local flow: precondition, exact command, and one resolved
-- evidence value, with no broker anywhere.
runLocalSourceOnLocalTransport
  :: BrokerLog
  -> IO (Either BrokerFailure BrokerCompleted)
runLocalSourceOnLocalTransport brokerLog = do
  planA <- planFixture
  source <- expectRight (LiveWorkflow.localEventSource "local-source" "local-address" id)
  handle <- expectRight (LiveWorkflow.mkHostRunHandle planA "local-on-local")
  let transport =
        LiveWorkflow.LocalExecutableTransport
          { LiveWorkflow.liveObserveLocalPrecondition = \_ -> pure (Right "precondition-observed")
          , LiveWorkflow.liveExecuteLocalCommand = \_ -> do
              logEvent brokerLog "execute"
              pure (Right "executed")
          , LiveWorkflow.liveResolveLocalEvidence = \_ -> pure (Right "resolved-evidence")
          }
  LiveWorkflow.runLiveWorkflow
    (localWorkflow planA source)
    transport
    (localBackend brokerLog (LiveWorkflow.HostRun handle))

localWorkflow
  :: PlanId
  -> LiveWorkflow.LiveEventSource Subprocess event
  -> LiveWorkflow.LiveWorkflow Subprocess event Bool () Text Text
localWorkflow planA source =
  LiveWorkflow.LiveWorkflow
    { LiveWorkflow.liveWorkflowPlanId = planA
    , LiveWorkflow.liveWorkflowCommand =
        LiveWorkflow.ExecutableCommand (subprocess "/usr/bin/true" [])
    , LiveWorkflow.liveWorkflowEventSource = source
    , LiveWorkflow.liveWorkflowInitialProgress = False
    , LiveWorkflow.liveWorkflowIngest = \_ _ -> Right True
    , LiveWorkflow.liveWorkflowFinish = \seen ->
        if seen then Success () else Failure "no evidence observed"
    , LiveWorkflow.liveWorkflowRenderViolation = id
    }

localBackend :: BrokerLog -> LiveWorkflow.Placement -> LiveWorkflow.LiveBackend Text
localBackend brokerLog placement =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement = pure (Right placement)
    , LiveWorkflow.liveCompletionMode = LiveWorkflow.ObserveIndependentWorkload
    , LiveWorkflow.liveObserveWorkload =
        const (pure (LiveWorkflow.Succeeded "local-terminal"))
    , LiveWorkflow.liveGatherDiagnostics = const $ do
        logEvent brokerLog "diagnostics"
        pure (Right [])
    , LiveWorkflow.liveReleasePlacement = const $ do
        logEvent brokerLog "placement"
        pure []
    , LiveWorkflow.liveObservationAttempts = 1
    , LiveWorkflow.liveObservationDelayMicros = 0
    , LiveWorkflow.liveWorkflowTimeoutMicros = 5_000_000
    }

requireCompleted :: BrokerRun -> IO BrokerCompleted
requireCompleted run =
  case brokerResult run of
    Right completed -> pure completed
    Left failure -> assertFailure ("expected a completed workflow, got " <> show failure)

requireFailure :: BrokerRun -> IO BrokerFailure
requireFailure run =
  case brokerResult run of
    Left failure -> pure failure
    Right completed -> assertFailure ("expected a failed workflow, got " <> show completed)

-- | A run whose workflow completed but whose cleanup did not.  Completion is
-- withheld (the run is a failure), the completed facts survive beside it, and
-- exactly one cleanup issue is retained, journalled, and names every needle
-- (the failure's own detail and the source it belongs to).  The placement is
-- released once.  The primary failure is left to the caller.
requireRetainedCleanup :: [Text] -> BrokerRun -> IO BrokerFailure
requireRetainedCleanup needles run = do
  failure <- requireFailure run
  LiveWorkflow.liveFailureCompletion failure
    @?= Just (LiveWorkflow.RequestResponseCompleted, ())
  case LiveWorkflow.liveFailureCleanupIssues failure of
    [issue@(LiveWorkflow.CleanupIssue detail)] -> do
      mapM_
        ( \needle ->
            assertBool
              ("cleanup detail lost " <> show needle <> ": " <> Text.unpack detail)
              (needle `Text.isInfixOf` detail)
        )
        needles
      assertBool
        "the retained cleanup issue is journalled"
        ( LiveWorkflow.CleanupRecorded issue
            `elem` journalEvents (LiveWorkflow.liveFailureJournal failure)
        )
    issues -> assertFailure ("unexpected cleanup issues: " <> show issues)
  brokerPlacementReleases run @?= 1
  pure failure

-- | The single release of the established source fails as scripted, by
-- returning a failure or by throwing.  The failure is retained as a cleanup
-- issue that names the source and carries the needles; it never becomes the
-- primary failure, and the release is never journalled as one.  The release
-- hook itself ran exactly once.  The label names the scripted release in every
-- assertion message.
assertReleaseRetained :: String -> IO (Either ConsumerFailure ()) -> [Text] -> Assertion
assertReleaseRetained label release needles = do
  brokerLog <- newBrokerLog
  run <-
    withinTimeout $
      runBrokerScript brokerLog defaultBrokerScript {scriptRelease = release}
  failure <- requireRetainedCleanup ("broker-script-owned" : needles) run
  assertEqual
    ("a release failure must never be the primary: " <> label)
    Nothing
    (LiveWorkflow.liveFailurePrimary failure)
  assertEqual
    ("a failed release must never be journalled as a release: " <> label)
    (filter (/= "source-released") completedMilestones)
    (journalMilestones (LiveWorkflow.liveFailureJournal failure))
  labels <- readBrokerLog brokerLog
  assertEqual
    ("the release hook must run exactly once: " <> label)
    1
    (length (filter (== "release") labels))

-- | 'assertReleaseRetained' for a release that returns the given failure, which
-- is not a plain cleanup failure.
assertReleaseFailureRetained :: ConsumerFailure -> [Text] -> Assertion
assertReleaseFailureRetained releaseFailure =
  assertReleaseRetained (show releaseFailure) (pure (Left releaseFailure))

-- | The runner must end by rethrowing exactly 'AsyncCancelled', not a wrapped
-- or converted exception and not a result.
requireCancellation :: Either SomeException BrokerRun -> Assertion
requireCancellation outcome =
  case outcome of
    Right run ->
      assertFailure
        ( "cancellation produced a workflow result: "
            <> show (brokerResult run)
        )
    Left exception ->
      case fromException exception :: Maybe AsyncCancelled of
        Just AsyncCancelled -> pure ()
        Nothing ->
          assertFailure ("cancellation changed identity: " <> show exception)

-- | Wait until a thread is blocked delivering an asynchronous exception, so the
-- cancellation is known to be queued rather than merely requested.
awaitBlockedOnException :: ThreadId -> IO ()
awaitBlockedOnException thread = go (2_000 :: Int)
 where
  go remaining = do
    status <- threadStatus thread
    case status of
      ThreadBlocked BlockedOnException -> pure ()
      _
        | remaining <= 0 ->
            assertFailure "the canceller never blocked delivering its exception"
        | otherwise -> threadDelay 5_000 >> go (remaining - 1)

withinTimeout :: IO value -> IO value
withinTimeout action = do
  result <- timeout 30_000_000 action
  case result of
    Just value -> pure value
    Nothing -> assertFailure "scripted live workflow did not finish within the fixture timeout"

orderedSubsequence :: (Eq value) => [value] -> [value] -> Bool
orderedSubsequence [] _actual = True
orderedSubsequence _expected [] = False
orderedSubsequence expected@(next : rest) (actual : remaining)
  | next == actual = orderedSubsequence rest remaining
  | otherwise = orderedSubsequence expected remaining

expectRight :: (Show err) => Either err value -> IO value
expectRight result =
  case result of
    Right value -> pure value
    Left err -> assertFailure ("expected Right, got Left " <> show err)

planFixture :: IO PlanId
planFixture = planFromText "live-workflow-establishment-plan"

otherPlanFixture :: IO PlanId
otherPlanFixture = planFromText "live-workflow-establishment-other-plan"

planFromText :: Text -> IO PlanId
planFromText canonical =
  case planIdFromCanonicalText canonical of
    Success planId -> pure planId
    Failure errors -> assertFailure ("invalid establishment fixture plan: " <> show errors)

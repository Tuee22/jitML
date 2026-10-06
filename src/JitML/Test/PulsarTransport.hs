{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.PulsarTransport
  ( pulsarTransportTests
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (AsyncCancelled (..), async, cancel, waitCatch)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, bracket, fromException)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Network.Socket qualified as Socket
import Network.Socket.ByteString qualified as Socket.ByteString
import System.Directory (doesFileExist, getPermissions, setOwnerExecutable, setPermissions)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Coordinator.Topology
  ( ProtocolRoute (..)
  , Topic
  , WorkflowStatusMessage
  , mkWorkflowStatusMessage
  , topicFor
  , topicName
  )
import JitML.Plan.Plan (PlanId, Validation (..), planIdFromCanonicalText)
import JitML.Service.Capabilities
  ( ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , HasPulsar (..)
  , Subscription
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , ack
  , continue
  , deliveryBatchEvents
  , deliveryBatchSize
  , deliveryBatchWindow
  , deliveryReceipt
  , deliveryReceiptFingerprint
  , deliveryRedeliveryCount
  , done
  , doneBatch
  , mkSubscription
  , subscriptionName
  , subscriptionOwnership
  , subscriptionStart
  , subscriptionTopic
  )
import JitML.Service.InferenceBatch
  ( BatchDeadlineMode (..)
  , batchMaximumSize
  , batchWindowAdmissionNanoseconds
  , batchWindowDeadlineNanoseconds
  , batchWindowPolicy
  , mkBatchPolicy
  )
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Pulsar.Bridge
  ( BridgeErrorScope (..)
  , BridgeState
  , BridgeStateError (..)
  , ChildFrame (..)
  , ParentCommand (..)
  , Settlement (..)
  , SettlementKind (..)
  , applyChildFrame
  , applyParentCommand
  , decodeChildFrame
  , decodeParentCommand
  , emptyBridgeState
  , encodeChildFrame
  )
import JitML.Service.Pulsar.Internal (DeliveryReceipt (..))
import JitML.Service.PulsarWebSocketSubprocess
  ( PulsarWebSocketSettings (..)
  , establishReplyCursor
  , publishWithReplyCursor
  , pulsarBatchConsumerBridgeScript
  , pulsarConsumerBridgeScript
  , pulsarConsumerSubprocess
  , pulsarCreateSubscriptionSubprocess
  , pulsarPublishSubprocess
  , releaseReplyCursor
  , replyCursorSubscription
  , runPulsarWebSocketSubprocess
  , subscriptionCleanupSubprocess
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessDuration (..)
  , processFailureCommand
  , processFailureDuration
  , processFailureExitCode
  , processFailureStderr
  , processFailureStdout
  , processFailureWorkingDirectory
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.LivePulsarTransport (livePulsarTransport, liveSubprocessTransport)
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.LiveWorkflowEstablishment (completedMilestones, journalMilestones)

pulsarTransportTests :: TestTree
pulsarTransportTests =
  testGroup
    "PulsarTransport"
    [ testCase "bridge delivery codec preserves arbitrary payload bytes" $ do
        let payload = ByteString.pack [0, 255, 10, 13, 128, 42]
            frame = Delivery receipt1 payload 4
        decodeChildFrame (encodeChildFrame frame) @?= Right frame
    , testCase "equal payloads with distinct receipts invoke the handler twice" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (twoDeliveryScript validWorkflowPayload) $ \settings -> do
            handled <- newIORef (0 :: Int)
            observedReceipts <- newIORef []
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeUntil
                      subscription
                      (const (pure ()))
                      ( \delivery -> do
                          count <- liftIO $ do
                            modifyIORef' handled (+ 1)
                            modifyIORef'
                              observedReceipts
                              ( <>
                                  [
                                    ( deliveryReceiptFingerprint (deliveryReceipt delivery)
                                    , deliveryRedeliveryCount delivery
                                    )
                                  ]
                              )
                            readIORef handled
                          pure (if count == 1 then continue ack else done ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            readIORef handled >>= (@?= 2)
            receiptObservations <- readIORef observedReceipts
            fmap snd receiptObservations @?= [0, 2]
            case fmap fst receiptObservations of
              [firstFingerprint, secondFingerprint] ->
                assertBool
                  "equal payloads reused one receipt"
                  (firstFingerprint /= secondFingerprint)
              other -> assertFailure ("expected two receipt fingerprints, got " <> show other)
    , testCase "Done settles once then drains with lifecycle observations" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (terminalScript AckKind validWorkflowPayload) $ \settings -> do
            observed <- newIORef []
            result <-
              withinFixtureTimeout $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (\event -> liftIO (modifyIORef' observed (<> [event])))
                    (const (pure (done ack ("complete" :: Text))))
            result @?= Right ("complete" :: Text)
            readIORef observed
              >>= ( @?=
                      [ ConsumerSessionConnected 1
                      , ConsumerSessionDraining
                      , ConsumerSessionDrained
                      ]
                  )
    , testCase "batch consume groups compatible deliveries and settles every hidden receipt once" $
        withWorkflowFixture Borrowed $ \_topic fixtureEvent subscription ->
          withFakeNode (twoDeliveryBatchScript validWorkflowPayload) $ \settings -> do
            batches <- newIORef []
            windows <- newIORef []
            observed <- newIORef []
            let policy = either (error . show) id (mkBatchPolicy 2 1_000_000)
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeBatchesUntil
                      (pure policy)
                      (const ())
                      (const BatchDeadlineEnforced)
                      subscription
                      (\sessionEvent -> liftIO (modifyIORef' observed (<> [sessionEvent])))
                      ( \batch -> do
                          liftIO $ do
                            modifyIORef'
                              batches
                              (<> [(deliveryBatchSize batch, NonEmpty.toList (deliveryBatchEvents batch))])
                            let window = deliveryBatchWindow batch
                            modifyIORef'
                              windows
                              ( <>
                                  [
                                    ( batchMaximumSize (batchWindowPolicy window)
                                    , batchWindowAdmissionNanoseconds window
                                    , batchWindowDeadlineNanoseconds window
                                    )
                                  ]
                              )
                          pure (doneBatch ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            batchObservations <- readIORef batches
            case batchObservations of
              [(size, events)] -> do
                size @?= 2
                length events @?= 2
                events @?= [fixtureEvent, fixtureEvent]
              other -> assertFailure ("expected one two-request batch, got " <> show other)
            windowObservations <- readIORef windows
            case windowObservations of
              [(maximumSize, admittedAt, deadline)] -> do
                maximumSize @?= 2
                assertBool "opaque batch deadline did not follow admission" (deadline > toInteger admittedAt)
              other -> assertFailure ("expected one opaque batch window, got " <> show other)
            readIORef observed
              >>= ( @?=
                      [ ConsumerSessionConnected 1
                      , ConsumerSessionDraining
                      , ConsumerSessionDrained
                      ]
                  )
    , testCase "production under-capacity batch leaves cold-path handler time before the SLO fence" $
        withWorkflowFixture Borrowed $ \_topic fixtureEvent subscription ->
          withFakeNode (singletonBatchScript validWorkflowPayload) $ \settings -> do
            handlerCalls <- newIORef (0 :: Int)
            let liveConfig = LiveConfig.defaultLiveConfig
                policy =
                  either
                    (error . show)
                    id
                    ( mkBatchPolicy
                        (fromIntegral (LiveConfig.liveInferenceBatchSize liveConfig))
                        ( fromIntegral (LiveConfig.liveInferenceMaxLatencyMillis liveConfig)
                            * 1_000
                        )
                    )
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeBatchesUntil
                      (pure policy)
                      (const ())
                      (const BatchDeadlineEnforced)
                      subscription
                      (const (pure ()))
                      ( \batch -> do
                          liftIO (modifyIORef' handlerCalls (+ 1))
                          liftIO (deliveryBatchSize batch @?= 1)
                          liftIO (NonEmpty.toList (deliveryBatchEvents batch) @?= [fixtureEvent])
                          -- Exceed the retired 25 ms default while remaining
                          -- comfortably inside the deployed cold-path budget.
                          liftIO (threadDelay 50_000)
                          pure (doneBatch ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            readIORef handlerCalls >>= (@?= 1)
    , testCase "batch SLO cancels late handler work before publication and Nacks every receipt" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (sloRecoveryBatchScript validWorkflowPayload) $ \settings -> do
            policies <-
              newIORef
                [ either (error . show) id (mkBatchPolicy 1 1000)
                , either (error . show) id (mkBatchPolicy 1 1_000_000)
                ]
            handlerCalls <- newIORef (0 :: Int)
            latePublication <- newIORef False
            let readNextPolicy = liftIO $ do
                  remaining <- readIORef policies
                  case remaining of
                    [] -> ioError (userError "batch policy fixture exhausted")
                    next : rest -> writeIORef policies rest >> pure next
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeBatchesUntil
                      readNextPolicy
                      (const ())
                      (const BatchDeadlineEnforced)
                      subscription
                      (const (pure ()))
                      ( \_batch -> do
                          call <- liftIO $ do
                            modifyIORef' handlerCalls (+ 1)
                            readIORef handlerCalls
                          when (call == 1) $
                            liftIO (threadDelay 100000 >> writeIORef latePublication True)
                          pure (doneBatch ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            readIORef handlerCalls >>= (@?= 2)
            readIORef latePublication >>= (@?= False)
    , testCase "isolated control handler can outlive the inference batch deadline and Ack once" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (singletonBatchScript validWorkflowPayload) $ \settings -> do
            let policy = either (error . show) id (mkBatchPolicy 64 1000)
            handlerCalls <- newIORef (0 :: Int)
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeBatchesUntil
                      (pure policy)
                      (const ())
                      (const BatchDeadlineIgnored)
                      subscription
                      (const (pure ()))
                      ( \_batch -> do
                          liftIO (modifyIORef' handlerCalls (+ 1))
                          liftIO (threadDelay 100000)
                          pure (doneBatch ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            readIORef handlerCalls >>= (@?= 1)
    , testCase "decode failure is negative-acked, confirmed, and drained" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (terminalScript NackKind "not-a-workflow-status") $ \settings -> do
            result <-
              withinFixtureTimeout $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    ( \_delivery -> do
                        _ <- liftIO (assertFailure "decode failure reached handler")
                        pure (done ack ())
                    )
            case result of
              Left (ConsumerDecodeFailure _decodeError) -> pure ()
              other -> assertFailure ("expected ConsumerDecodeFailure, got " <> show other)
    , testCase "handler exception is negative-acked before failure returns" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (terminalScript NackKind validWorkflowPayload) $ \settings -> do
            result <-
              withinFixtureTimeout $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    ( \_delivery -> do
                        liftIO (ioError (userError "handler exploded") :: IO ())
                        pure (done ack ())
                    )
            case result of
              Left (ConsumerHandlerFailure message) ->
                assertBool "handler exception text was lost" ("handler exploded" `Text.isInfixOf` message)
              other -> assertFailure ("expected ConsumerHandlerFailure, got " <> show other)
    , testCase "settlement bridge error remains a settlement failure" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (settlementFailureScript validWorkflowPayload) $ \settings -> do
            result <-
              withinFixtureTimeout $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    (const (pure (done ack ())))
            case result of
              Left (ConsumerSettlementFailure message (SETransient detail)) -> do
                assertBool "settlement scope was lost" ("settlement" `Text.isInfixOf` message)
                detail @?= "broker rejected settlement"
              other -> assertFailure ("expected ConsumerSettlementFailure, got " <> show other)
    , testCase "child pipe closure retains settlement classification and process outcome" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (closedBeforeSettlementScript validWorkflowPayload) $ \settings -> do
            result <-
              withinFixtureTimeout $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    ( \_delivery -> do
                        liftIO (threadDelay 100000)
                        pure (done ack ())
                    )
            case result of
              Left
                ( ConsumerTransportContextFailure
                    (ConsumerSettlementFailure message (SETransient detail))
                    processFailure
                  ) -> do
                  assertContains "settlement class" "pipe write failed" message
                  assertBool "pipe failure omitted its OS detail" (not (Text.null detail))
                  processFailureExitCode processFailure @?= ExitFailure 29
                  processFailureCommand processFailure
                    @?= renderSubprocess (pulsarConsumerSubprocess settings subscription)
                  assertContains
                    "delivery transcript"
                    "\"type\":\"delivery\""
                    (processFailureStdout processFailure)
                  processFailureStderr processFailure @?= "bridge closed before settlement"
                  processFailureWorkingDirectory processFailure @?= Nothing
              other ->
                assertFailure
                  ("expected typed settlement failure with process context, got " <> show other)
    , testCase "state rejects unknown and opposite settlement" $
        withBridgeDelivery $ \delivered -> do
          applyParentCommand delivered (Settle unknownReceipt Ack)
            @?= Left (UnknownReceipt unknownReceipt)
          expectRight (applyParentCommand delivered (Settle receipt1 Ack)) $ \requested ->
            applyChildFrame requested (Settled receipt1 NackKind)
              @?= Left (OppositeSettlement receipt1 AckKind NackKind)
    , testCase "Node bridge keeps broker ids private and reconnect ordering explicit" $
        withWorkflowFixture Borrowed $ \_topic _event subscription -> do
          let source = pulsarConsumerBridgeScript
              command = pulsarConsumerSubprocess testSettings subscription
          assertBool "receipt token map missing" ("receiptToMessageId = new Map()" `Text.isInfixOf` source)
          assertBool
            "payload is not forwarded byte-faithfully"
            ("payloadBase64: message.payload" `Text.isInfixOf` source)
          assertBool "bridge decodes payload to UTF-8" (not ("toString('utf8')" `Text.isInfixOf` source))
          assertBool
            "pending settlement is not flushed before reconnect permit"
            ( "if (pendingSettlement !== null) flushPendingSettlement();\n    else if (draining) finishDrainIfIdle();\n    else permitOne();"
                `Text.isInfixOf` source
            )
          countOccurrences "reconnectTimer = setTimeout" source @?= 1
          assertBool "explicit single permit missing" ("permitMessages: 1" `Text.isInfixOf` source)
          assertBool
            "single bridge accepts an unsolicited delivery"
            ("delivery arrived without a permit" `Text.isInfixOf` source)
          assertBool
            "flush confirmation does not inspect bufferedAmount"
            ("bufferedAmount !== 0" `Text.isInfixOf` source)
          assertBool
            "settlement is not bound to its sending socket"
            ("settlementSocket === socket" `Text.isInfixOf` source)
          assertBool "fatal protocol errors do not terminate" ("process.exit(1)" `Text.isInfixOf` source)
          assertBool
            "stdin cancellation drain is missing"
            ("process.stdin.on('end', drainAfterParentExit)" `Text.isInfixOf` source)
          assertBool
            "SIGTERM cancellation drain is missing"
            ("process.on('SIGTERM', drainAfterParentExit)" `Text.isInfixOf` source)
          assertBool
            "cancellation does not mint a typed drain-requested Nack"
            ( "settlement: { type: 'nack', reason: 'drain-requested' }"
                `Text.isInfixOf` source
            )
          case reverse (subprocessArguments command) of
            consumerEndpoint : _rest -> do
              assertBool "Failover missing" ("subscriptionType=Failover" `Text.isInfixOf` consumerEndpoint)
              assertBool "pull queue is not one" ("receiverQueueSize=1" `Text.isInfixOf` consumerEndpoint)
              assertBool "pull mode missing" ("pullMode=true" `Text.isInfixOf` consumerEndpoint)
              assertBool "ack timeout must be disabled" (not ("ackTimeout" `Text.isInfixOf` consumerEndpoint))
            [] -> assertFailure "consumer subprocess has no endpoint argument"
    , testCase "batch bridge retains drain-race Nacks until their socket flushes" $ do
        let source = pulsarBatchConsumerBridgeScript
        assertBool
          "drain-race delivery is not entered into the hidden receipt map"
          ( "receiptToMessageId.set(deliveryId, { receipt, messageId: message.messageId })"
              `Text.isInfixOf` source
          )
        assertBool
          "drain-race settlement is not retained for reconnect"
          ("internalDrainRace: true" `Text.isInfixOf` source)
        assertBool
          "drain-race settlement leaks an unknown receipt to the parent"
          ("if (!command.internalDrainRace) emit({ type: 'settled'" `Text.isInfixOf` source)
        assertBool
          "drain can finish before pending settlements flush"
          ("receiptToMessageId.size !== 0 || pendingSettlements.size !== 0" `Text.isInfixOf` source)
        assertBool
          "protocol drain does not yield one event-loop turn to an already queued delivery"
          ("setImmediate(finishDrainIfIdle)" `Text.isInfixOf` source)
    , testCase "actual batch bridge confirms a raced drain Nack before closing" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withRealBatchDrainRaceBridge validWorkflowPayload $ \settings logPath -> do
            let policy = either (error . show) id (mkBatchPolicy 64 100_000)
            handled <- newIORef (0 :: Int)
            observed <- newIORef []
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeBatchesUntil
                      (pure policy)
                      (const ())
                      (const BatchDeadlineEnforced)
                      subscription
                      (\event -> liftIO (modifyIORef' observed (<> [event])))
                      ( \batch -> do
                          liftIO (deliveryBatchSize batch @?= 1)
                          liftIO (modifyIORef' handled (+ 1))
                          pure (doneBatch ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            readIORef handled >>= (@?= 1)
            readIORef observed
              >>= ( @?=
                      [ ConsumerSessionConnected 1
                      , ConsumerSessionDraining
                      , ConsumerSessionDrained
                      ]
                  )
            bridgeLog <- Text.lines <$> Text.IO.readFile logPath
            assertOrderedLog
              bridgeLog
              [ "ack:1:broker-1"
              , "delivery:2"
              , "nack:1:broker-2"
              , "nack-flushed:1"
              , "close:1"
              ]
            assertBool
              "batch bridge closed while the raced Nack was still buffered"
              ("close-while-buffered:1" `notElem` bridgeLog)
    , testCase "actual Node bridge reconnects and flushes pending settlement before permit" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withRealNodeBridge validWorkflowPayload $ \settings logPath -> do
            handled <- newIORef (0 :: Int)
            observed <- newIORef []
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeUntil
                      subscription
                      (\event -> liftIO (modifyIORef' observed (<> [event])))
                      ( \_delivery -> do
                          liftIO (modifyIORef' handled (+ 1))
                          pure (done ack ())
                      )
              )
                :: IO (Either ConsumerFailure ())
            result @?= Right ()
            readIORef handled >>= (@?= 1)
            lifecycle <- readIORef observed
            case lifecycle of
              [ ConsumerSessionConnected 1
                , ConsumerSessionDraining
                , ConsumerSessionDisconnected message
                , ConsumerSessionConnected 2
                , ConsumerSessionDrained
                ] ->
                  assertBool
                    "disconnect reason did not cross the real bridge"
                    ("injected-drop" `Text.isInfixOf` message)
              other ->
                assertFailure ("unexpected reconnect lifecycle: " <> show other)
            bridgeLog <- Text.lines <$> Text.IO.readFile logPath
            filter (Text.isPrefixOf "delivery:") bridgeLog @?= ["delivery:1"]
            filter (Text.isPrefixOf "permit:") bridgeLog @?= ["permit:1"]
            filter (Text.isPrefixOf "ack:") bridgeLog
              @?= ["ack:1:broker-secret", "ack:2:broker-secret"]
            assertOrderedLog
              bridgeLog
              [ "ack:1:broker-secret"
              , "drop:1"
              , "socket:2"
              , "ack:2:broker-secret"
              ]
    , testCase "Borrowed closes only; Owned renders explicit admin DELETE" $
        withWorkflowFixture Borrowed $ \topic event borrowed ->
          case mkSubscription topic "owned-unit" FromEarliest Owned of
            Left err -> assertFailure ("failed to build owned subscription: " <> show err)
            Right owned -> do
              subscriptionCleanupSubprocess testSettings borrowed @?= Nothing
              let createCommand = pulsarCreateSubscriptionSubprocess testSettings owned
              subprocessPath createCommand @?= "curl"
              assertBool "cursor creation is not PUT" ("PUT" `elem` subprocessArguments createCommand)
              -- MessageId.latest is (Long.MAX_VALUE, Long.MAX_VALUE, -1).
              -- (-1, -1, -1) is MessageId.earliest, which creates the cursor at
              -- the head of the topic and replays every message already
              -- published to it, so a reply the requester never asked for is
              -- delivered as if it answered the correlated command.
              assertBool
                "cursor creation does not carry MessageId.latest"
                ( subprocessStdin createCommand
                    == Just
                      "{\"ledgerId\":9223372036854775807,\"entryId\":9223372036854775807,\"partitionIndex\":-1}"
                )
              assertBool
                "cursor creation carries the MessageId.earliest sentinel"
                (subprocessStdin createCommand /= Just "{\"ledgerId\":-1,\"entryId\":-1,\"partitionIndex\":-1}")
              assertBool
                "cursor creation URL is not the exact admin subscription resource"
                ( any
                    ( Text.isSuffixOf
                        "/admin/v2/persistent/public/default/workflow.status.linux-cpu/subscription/owned-unit"
                    )
                    (subprocessArguments createCommand)
                )
              assertBool
                "cursor creation inherited the DELETE-only force query"
                (not (any (Text.isInfixOf "force=true") (subprocessArguments createCommand)))
              case subscriptionCleanupSubprocess testSettings owned of
                Nothing -> assertFailure "owned subscription omitted cleanup"
                Just command -> do
                  subprocessPath command @?= "curl"
                  assertBool "cleanup is not DELETE" ("DELETE" `elem` subprocessArguments command)
                  assertOrderedLog
                    (subprocessArguments command)
                    [ "--location"
                    , "--max-redirs"
                    , "5"
                    , "--proto-redir"
                    , "=http,https"
                    , "--connect-timeout"
                    , "10"
                    , "--max-time"
                    , "30"
                    ]
                  assertBool
                    "cleanup URL is not the admin subscription resource"
                    ( any
                        ( Text.isInfixOf
                            "/admin/v2/persistent/public/default/workflow.status.linux-cpu/subscription/owned-unit"
                        )
                        (subprocessArguments command)
                    )
                  assertBool
                    "owned cleanup is not forced after consumer close"
                    (any (Text.isSuffixOf "?force=true") (subprocessArguments command))
              assertBool
                "typed publisher does not carry the encoded event on stdin"
                (subprocessStdin (pulsarPublishSubprocess testSettings topic event) == Just validWorkflowPayload)
    , testCase "Owned cleanup follows a bounded Pulsar HTTP 307 redirect" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withFakeNode (terminalScript AckKind validWorkflowPayload) $ \settings ->
            withRedirectingSuccessfulAdmin $ \adminEndpoint requestsObserved -> do
              result <-
                withinFixtureTimeout $
                  runPulsarWebSocketSubprocess
                    (settings {pulsarAdminEndpoint = adminEndpoint})
                    ( pulsarConsumeUntil
                        subscription
                        (const (pure ()))
                        (const (pure (done ack ())))
                    )
              result @?= Right ()
              requests <- withinFixtureTimeout (takeMVar requestsObserved)
              case fmap Text.Encoding.decodeUtf8 requests of
                [initialRequest, redirectedRequest] -> do
                  assertBool
                    "initial cleanup request was not DELETE"
                    ("DELETE /admin/v2/" `Text.isPrefixOf` initialRequest)
                  assertBool
                    "redirected cleanup did not preserve DELETE"
                    ("DELETE /redirected-cleanup " `Text.isPrefixOf` redirectedRequest)
                other ->
                  assertFailure ("unexpected redirected cleanup requests: " <> show other)
    , testCase "acknowledged reply-cursor CREATE mints a borrowed consumer view and releases it" $
        withWorkflowFixture Owned $ \topic _event _fixtureSubscription ->
          withReplySubscription topic "reply-cursor-unit" $ \subscription ->
            withAdminResponses [httpNoContent, httpNoContent] $ \adminEndpoint requestsObserved -> do
              let settings = testSettings {pulsarAdminEndpoint = adminEndpoint}
              established <- establishReplyCursor settings topic subscription
              case established of
                Left err -> assertFailure ("reply cursor was not established: " <> show err)
                Right cursor -> do
                  let consumerSubscription = replyCursorSubscription cursor
                  subscriptionTopic consumerSubscription @?= topic
                  subscriptionName consumerSubscription @?= subscriptionName subscription
                  subscriptionStart consumerSubscription @?= FromLatest
                  subscriptionOwnership consumerSubscription @?= Borrowed
                  released <- releaseReplyCursor settings cursor
                  released @?= Right ()
              requests <- withinFixtureTimeout (takeMVar requestsObserved)
              case requests of
                [createRequest, deleteRequest] -> do
                  assertBool
                    "reply cursor was not established by admin PUT"
                    ("PUT /admin/v2/" `Text.isPrefixOf` Text.Encoding.decodeUtf8 createRequest)
                  assertBool
                    "reply cursor release was not admin DELETE"
                    ("DELETE /admin/v2/" `Text.isPrefixOf` Text.Encoding.decodeUtf8 deleteRequest)
                other -> assertFailure ("unexpected cursor admin request sequence: " <> show other)
    , testCase "offline reply-cursor broker drops a pre-cursor reply and delivers the post-cursor reply" $
        withWorkflowFixture Owned $ \topic event _fixtureSubscription ->
          withReplySubscription topic "reply-cursor-offline-negative" $ \subscription ->
            withSystemTempDirectory "jitml-reply-cursor-offline" $ \directory -> do
              let cursorPath = directory </> "cursor-created"
                  messagePath = directory </> "cursor-message"
                  eventLogPath = directory </> "cursor-events.log"
                  appendEvent eventName = Text.IO.appendFile eventLogPath (eventName <> "\n")
                  createCursor = do
                    Text.IO.writeFile cursorPath "created"
                    appendEvent "create"
                  deleteCursor = appendEvent "delete"
              withFakeNode
                (replyCursorBrokerScript validWorkflowPayload cursorPath messagePath eventLogPath)
                $ \nodeSettings ->
                  withAdminResponseEffects
                    [(httpNoContent, createCursor), (httpNoContent, deleteCursor)]
                    $ \adminEndpoint requestsObserved -> do
                      let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                      preCursor <-
                        runPulsarWebSocketSubprocess settings (pulsarPublish topic event)
                      preCursor @?= Right "reply-publish-ack"
                      doesFileExist messagePath >>= (@?= False)
                      established <- establishReplyCursor settings topic subscription
                      cursor <-
                        case established of
                          Left err -> assertFailure ("offline reply cursor was not established: " <> show err)
                          Right establishedCursor -> pure establishedCursor
                      published <- publishWithReplyCursor settings cursor (const event)
                      published @?= Right "reply-publish-ack"
                      consumed <-
                        runPulsarWebSocketSubprocess settings $
                          pulsarConsumeUntil
                            (replyCursorSubscription cursor)
                            (const (pure ()))
                            (const (pure (done ack ())))
                      consumed @?= Right ()
                      released <- releaseReplyCursor settings cursor
                      released @?= Right ()
                      requests <- withinFixtureTimeout (takeMVar requestsObserved)
                      length requests @?= 2
                      events <- Text.lines <$> Text.IO.readFile eventLogPath
                      assertOrderedLog
                        events
                        [ "publish-without-cursor"
                        , "create"
                        , "publish-with-cursor"
                        , "delivery"
                        , "delete"
                        ]
    , testCase "reply-cursor CREATE accepts HTTP 409 as proof of an existing cursor" $
        withWorkflowFixture Owned $ \topic _event _fixtureSubscription ->
          withReplySubscription topic "reply-cursor-conflict" $ \subscription ->
            withAdminResponses [httpConflict, httpNoContent] $ \adminEndpoint _requestsObserved -> do
              let settings = testSettings {pulsarAdminEndpoint = adminEndpoint}
              established <- establishReplyCursor settings topic subscription
              case established of
                Left err -> assertFailure ("existing reply cursor was rejected: " <> show err)
                Right cursor -> do
                  released <- releaseReplyCursor settings cursor
                  released @?= Right ()
    , testCase "correlated publish obtains both topics only from the acknowledged ReplyCursor" $
        withWorkflowFixture Owned $ \topic event _fixtureSubscription ->
          withReplySubscription topic "reply-cursor-publish" $ \subscription ->
            withFakeNode publisherSuccessScript $ \nodeSettings ->
              withAdminResponses [httpNoContent, httpNoContent] $ \adminEndpoint _requestsObserved -> do
                let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                established <- establishReplyCursor settings topic subscription
                case established of
                  Left err -> assertFailure ("reply cursor was not established: " <> show err)
                  Right cursor -> do
                    published <-
                      publishWithReplyCursor settings cursor $ \replyTopic ->
                        if replyTopic == topicName topic
                          then event
                          else error "ReplyCursor exposed a mismatched reply topic"
                    published @?= Right "correlated-publish-ack"
                    released <- releaseReplyCursor settings cursor
                    released @?= Right ()
    , testCase "reply-cursor CREATE failure cannot mint a correlated-publish token" $
        withWorkflowFixture Owned $ \topic _event _fixtureSubscription ->
          withReplySubscription topic "reply-cursor-failure" $ \subscription ->
            withSystemTempDirectory "jitml-reply-cursor-create-failure" $ \directory -> do
              let publishMarker = directory </> "publisher-invoked"
              withFakeNode (publisherInvocationMarkerScript publishMarker) $ \nodeSettings ->
                withAdminResponses [httpInternalError] $ \adminEndpoint requestsObserved -> do
                  let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                  established <- establishReplyCursor settings topic subscription
                  case established of
                    Left (SETransient detail) ->
                      assertBool
                        "cursor failure omitted the broker status"
                        ("500" `Text.isInfixOf` detail)
                    Left other -> assertFailure ("unexpected cursor failure class: " <> show other)
                    Right _cursor -> assertFailure "failed admin CREATE minted a ReplyCursor"
                  requests <- withinFixtureTimeout (takeMVar requestsObserved)
                  length requests @?= 1
                  doesFileExist publishMarker >>= (@?= False)
    , testCase
        "harness transport creates the reply cursor before the first publish and deletes it after the consumer stops"
        $ withWorkflowFixture Owned
        $ \topic event _fixtureSubscription ->
          withReplySubscription topic "harness-cursor-order" $ \subscription ->
            withSystemTempDirectory "jitml-harness-cursor-order" $ \directory -> do
              let paths = harnessPaths directory
              withFakeNode (liveWorkflowBrokerScript validWorkflowPayload paths) $ \nodeSettings ->
                withAdminResponseEffects
                  [ (httpNoContent, harnessCreateCursor paths)
                  , (httpNoContent, harnessAppend paths "delete")
                  ]
                  $ \adminEndpoint requestsObserved -> do
                    let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                    result <-
                      withinFixtureTimeout $
                        harnessProtocolWorkflow
                          settings
                          topic
                          event
                          subscription
                    completed <- expectHarnessCompleted result
                    -- The broker's own order: CREATE, then the first publish
                    -- (which finds the cursor), then the delivery, then DELETE.
                    events <- Text.lines <$> Text.IO.readFile (harnessEventLog paths)
                    events @?= ["create", "publish-with-cursor", "delivery", "delete"]
                    requests <- withinFixtureTimeout (takeMVar requestsObserved)
                    requestMethods requests @?= ["PUT", "DELETE"]
                    -- CREATE and DELETE name the very subscription the consumer
                    -- attached to, and the DELETE is the forced owned cleanup.
                    let resource =
                          "/admin/v2/persistent/public/default/workflow.status.linux-cpu/subscription/harness-cursor-order"
                    case fmap Text.Encoding.decodeUtf8 requests of
                      [createRequest, deleteRequest] -> do
                        assertBool
                          ("CREATE did not target the subscription resource: " <> Text.unpack createRequest)
                          (("PUT " <> resource <> " ") `Text.isPrefixOf` createRequest)
                        assertBool
                          ("DELETE was not the forced cleanup of the same resource: " <> Text.unpack deleteRequest)
                          (("DELETE " <> resource <> "?force=true ") `Text.isPrefixOf` deleteRequest)
                      other -> assertFailure ("unexpected admin requests: " <> show other)
                    consumerUrl <- Text.IO.readFile (harnessConsumerUrl paths)
                    assertBool
                      ("the consumer did not attach to the established subscription: " <> Text.unpack consumerUrl)
                      ( "/consumer/persistent/public/default/workflow.status.linux-cpu/harness-cursor-order?"
                          `Text.isInfixOf` consumerUrl
                      )
                    -- The interpreter's own order agrees.
                    journalMilestones (LiveWorkflow.completedRunJournal completed)
                      @?= completedMilestones
    , testCase "harness transport does not publish when the cursor CREATE is refused" $
        withWorkflowFixture Owned $ \topic event _fixtureSubscription ->
          withReplySubscription topic "harness-cursor-refused" $ \subscription ->
            withSystemTempDirectory "jitml-harness-cursor-refused" $ \directory -> do
              let paths = harnessPaths directory
                  nodeInvoked = directory </> "node-invoked"
              withFakeNode (publisherInvocationMarkerScript nodeInvoked) $ \nodeSettings ->
                withAdminResponses [httpInternalError] $ \adminEndpoint requestsObserved -> do
                  let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                  result <-
                    withinFixtureTimeout $
                      harnessProtocolWorkflow settings topic event subscription
                  failure <- expectHarnessFailure result
                  case LiveWorkflow.liveFailurePrimary failure of
                    Just (LiveWorkflow.LiveEstablishFailed (SETransient detail)) ->
                      assertBool
                        "the refused CREATE status was lost"
                        ("500" `Text.isInfixOf` detail)
                    other -> assertFailure ("unexpected primary failure: " <> show other)
                  LiveWorkflow.liveFailureCompletion failure @?= Nothing
                  journalMilestones (LiveWorkflow.liveFailureJournal failure)
                    @?= [ "placement-acquired"
                        , "source-establishment-failed"
                        , "diagnostics"
                        , "placement-released"
                        ]
                  -- Neither a publisher nor a consumer process ever started,
                  -- and there is no cursor to DELETE.
                  doesFileExist nodeInvoked >>= (@?= False)
                  doesFileExist (harnessEventLog paths) >>= (@?= False)
                  requests <- withinFixtureTimeout (takeMVar requestsObserved)
                  length requests @?= 1
    , testCase "harness transport refuses a borrowed source before any broker call" $
        withWorkflowFixture Owned $ \topic event _fixtureSubscription ->
          case mkSubscription topic "harness-borrowed" FromLatest Borrowed of
            Left err -> assertFailure ("failed to build borrowed subscription: " <> show err)
            Right borrowed -> do
              -- testSettings points at unresolvable hosts: any attempted broker
              -- call would surface as a transient transport failure instead of
              -- the typed refusal asserted here.
              result <-
                withinFixtureTimeout $
                  harnessProtocolWorkflow testSettings topic event borrowed
              failure <- expectHarnessFailure result
              LiveWorkflow.liveFailurePrimary failure
                @?= Just
                  ( LiveWorkflow.LiveEstablishFailed
                      (SEConflict "reply cursor subscription must be Owned")
                  )
    , testCase
        "harness transport refuses a typed executable on the protocol transport before any broker call"
        $ withWorkflowFixture Owned
        $ \_topic _event subscription -> do
          planId <- harnessPlan
          handle <- expectHarnessRight (LiveWorkflow.mkHostRunHandle planId "harness-executable-refused")
          let command = LiveWorkflow.ExecutableCommand (subprocess "/usr/bin/true" [])
          result <-
            withinFixtureTimeout $
              LiveWorkflow.runLiveWorkflow
                (harnessWorkflow planId command (LiveWorkflow.pulsarEventSource subscription))
                (livePulsarTransport testSettings)
                (harnessBackend (LiveWorkflow.HostRun handle) LiveWorkflow.ObserveIndependentWorkload)
          failure <- expectHarnessFailure result
          case LiveWorkflow.liveFailurePrimary failure of
            Just (LiveWorkflow.LiveEstablishFailed (SETransient detail)) ->
              assertBool
                "the typed-executable refusal was lost"
                ("cannot execute typed command" `Text.isInfixOf` detail)
            other -> assertFailure ("unexpected primary failure: " <> show other)
    , testCase "harness transport retains a failed cursor DELETE and withholds completion" $
        withWorkflowFixture Owned $ \topic event _fixtureSubscription ->
          withReplySubscription topic "harness-cursor-delete-failure" $ \subscription ->
            withSystemTempDirectory "jitml-harness-cursor-delete-failure" $ \directory -> do
              let paths = harnessPaths directory
              withFakeNode (liveWorkflowBrokerScript validWorkflowPayload paths) $ \nodeSettings ->
                withAdminResponseEffects
                  [ (httpNoContent, harnessCreateCursor paths)
                  , (httpInternalError, harnessAppend paths "delete-refused")
                  ]
                  $ \adminEndpoint requestsObserved -> do
                    let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                    result <-
                      withinFixtureTimeout $
                        harnessProtocolWorkflow settings topic event subscription
                    failure <- expectHarnessFailure result
                    LiveWorkflow.liveFailurePrimary failure @?= Nothing
                    LiveWorkflow.liveFailureCompletion failure
                      @?= Just (LiveWorkflow.RequestResponseCompleted, ())
                    case LiveWorkflow.liveFailureCleanupIssues failure of
                      [LiveWorkflow.CleanupIssue detail] -> do
                        assertContains "cleanup status" "unexpected HTTP status" detail
                        assertContains "cleanup response" "500" detail
                      issues -> assertFailure ("unexpected cleanup issues: " <> show issues)
                    -- The refused DELETE is never journalled as a release.
                    journalMilestones (LiveWorkflow.liveFailureJournal failure)
                      @?= [ "placement-acquired"
                          , "source-established"
                          , "publication-started"
                          , "published"
                          , "evidence-completed"
                          , "diagnostics"
                          , "placement-released"
                          ]
                    events <- Text.lines <$> Text.IO.readFile (harnessEventLog paths)
                    events @?= ["create", "publish-with-cursor", "delivery", "delete-refused"]
                    requests <- withinFixtureTimeout (takeMVar requestsObserved)
                    length requests @?= 2
    , testCase "harness transport releases the cursor when a cancellation races its CREATE" $
        withWorkflowFixture Owned $ \topic event _fixtureSubscription ->
          withReplySubscription topic "harness-cursor-cancelled" $ \subscription ->
            withSystemTempDirectory "jitml-harness-cursor-cancelled" $ \directory -> do
              let paths = harnessPaths directory
              createReceived <- newEmptyMVar
              withFakeNode idleConsumerScript $ \nodeSettings ->
                withAdminResponseEffects
                  [
                    ( httpNoContent
                    , do
                        -- The broker has the CREATE and is still creating the
                        -- cursor when the cancellation arrives.
                        putMVar createReceived ()
                        threadDelay 300000
                        harnessCreateCursor paths
                    )
                  , (httpNoContent, harnessAppend paths "delete")
                  ]
                  $ \adminEndpoint requestsObserved -> do
                    let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                    runner <-
                      async (harnessProtocolWorkflow settings topic event subscription)
                    withinFixtureTimeout (takeMVar createReceived)
                    -- The CREATE is uninterruptible, so this cancellation is
                    -- delivered once the cursor token exists and the
                    -- interpreter releases it exactly once.
                    cancel runner
                    cancelled <- withinFixtureTimeout (waitCatch runner)
                    requireHarnessCancellation cancelled
                    readHarnessEvents paths >>= (@?= ["create", "delete"])
                    requests <- withinFixtureTimeout (takeMVar requestsObserved)
                    requestMethods requests @?= ["PUT", "DELETE"]
    , testCase
        "harness transport releases the subscription-only cursor when a cancellation races a typed executable's CREATE"
        $ withWorkflowFixture Owned
        $ \topic _event _fixtureSubscription ->
          withReplySubscription topic "harness-executable-cancelled" $ \subscription ->
            withSystemTempDirectory "jitml-harness-executable-cancelled" $ \directory -> do
              let paths = harnessPaths directory
              createReceived <- newEmptyMVar
              withFakeNode idleConsumerScript $ \nodeSettings ->
                withAdminResponseEffects
                  [
                    ( httpNoContent
                    , do
                        -- The broker has the CREATE and is still creating the
                        -- cursor when the cancellation arrives.
                        putMVar createReceived ()
                        threadDelay 300000
                        harnessCreateCursor paths
                    )
                  , (httpNoContent, harnessAppend paths "delete")
                  ]
                  $ \adminEndpoint requestsObserved -> do
                    let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                    planId <- harnessPlan
                    handle <- expectHarnessRight (LiveWorkflow.mkHostRunHandle planId "harness-executable-cancelled")
                    runner <-
                      async
                        ( LiveWorkflow.runLiveWorkflow
                            ( harnessWorkflow
                                planId
                                (LiveWorkflow.ExecutableCommand (harnessExecutable paths))
                                (LiveWorkflow.pulsarEventSource subscription)
                            )
                            (liveSubprocessTransport settings)
                            (harnessBackend (LiveWorkflow.HostRun handle) LiveWorkflow.ObserveIndependentWorkload)
                        )
                    withinFixtureTimeout (takeMVar createReceived)
                    -- The subscription-only CREATE of a typed executable is
                    -- uninterruptible exactly like the correlated one: this
                    -- cancellation is delivered once the token exists, where
                    -- the interpreter releases the cursor exactly once.
                    cancel runner
                    cancelled <- withinFixtureTimeout (waitCatch runner)
                    requireHarnessCancellation cancelled
                    -- The cursor was created, the executable never ran (it
                    -- would have logged "execute"), and the cursor was deleted.
                    readHarnessEvents paths >>= (@?= ["create", "delete"])
                    requests <- withinFixtureTimeout (takeMVar requestsObserved)
                    requestMethods requests @?= ["PUT", "DELETE"]
    , testCase "harness transport establishes a subscription-only cursor before a typed executable runs" $
        withWorkflowFixture Owned $ \topic _event _fixtureSubscription ->
          withReplySubscription topic "harness-executable-order" $ \subscription ->
            withSystemTempDirectory "jitml-harness-executable-order" $ \directory -> do
              let paths = harnessPaths directory
                  executable = harnessExecutable paths
              withFakeNode (liveWorkflowBrokerScript validWorkflowPayload paths) $ \nodeSettings ->
                withAdminResponseEffects
                  [ (httpNoContent, harnessCreateCursor paths)
                  , (httpNoContent, harnessAppend paths "delete")
                  ]
                  $ \adminEndpoint requestsObserved -> do
                    let settings = nodeSettings {pulsarAdminEndpoint = adminEndpoint}
                    planId <- harnessPlan
                    handle <- expectHarnessRight (LiveWorkflow.mkHostRunHandle planId "harness-executable")
                    result <-
                      withinFixtureTimeout $
                        LiveWorkflow.runLiveWorkflow
                          ( harnessWorkflow
                              planId
                              (LiveWorkflow.ExecutableCommand executable)
                              (LiveWorkflow.pulsarEventSource subscription)
                          )
                          (liveSubprocessTransport settings)
                          (harnessBackend (LiveWorkflow.HostRun handle) LiveWorkflow.ObserveIndependentWorkload)
                    completed <- expectHarnessCompleted result
                    -- CREATE precedes the executable, which has no request
                    -- topic and no producer of its own.
                    events <- Text.lines <$> Text.IO.readFile (harnessEventLog paths)
                    events @?= ["create", "execute", "delivery", "delete"]
                    requests <- withinFixtureTimeout (takeMVar requestsObserved)
                    requestMethods requests @?= ["PUT", "DELETE"]
                    journalMilestones (LiveWorkflow.completedRunJournal completed)
                      @?= completedMilestones
    , testCase "publisher failure retains the complete process outcome" $
        withWorkflowFixture Borrowed $ \topic event _subscription ->
          withFakeNode publisherFailureScript $ \settings -> do
            result <-
              runPulsarWebSocketSubprocess settings (pulsarPublish topic event)
            case result of
              Left (SETransient message) -> do
                assertContains "command" "command:" message
                assertContains "exit" "exit: 19" message
                assertContains "stdout" "stdout: partial-out" message
                assertContains "stderr" "stderr: producer exploded" message
                assertContains "cwd" "working-directory: (inherited)" message
                assertContains "duration" "duration-nanoseconds:" message
              other -> assertFailure ("expected structured publisher failure, got " <> show other)
    , testCase "fatal bridge failure retains semantic context and complete process failure" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode fatalProtocolScript $ \settings -> do
            result <-
              ( withinFixtureTimeout $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeUntil
                      subscription
                      (const (pure ()))
                      (\_delivery -> pure (done ack ()))
              )
                :: IO (Either ConsumerFailure ())
            case result of
              Left (ConsumerTransportContextFailure context processFailure) -> do
                assertContains
                  "semantic context"
                  "bridge error in protocol"
                  (Text.pack (show context))
                processFailureExitCode processFailure @?= ExitFailure 23
                processFailureCommand processFailure
                  @?= renderSubprocess (pulsarConsumerSubprocess settings subscription)
                assertContains "stdout frame" "\"type\":\"bridge-error\"" (processFailureStdout processFailure)
                processFailureStderr processFailure @?= "fatal bridge"
                processFailureWorkingDirectory processFailure @?= Nothing
                case processFailureDuration processFailure of
                  ProcessDuration nanoseconds ->
                    assertBool "fatal bridge duration was not retained" (nanoseconds > 0)
              other ->
                assertFailure
                  ("expected ConsumerTransportContextFailure, got " <> show other)
    , testCase "async cancellation is rethrown and does not deadlock an in-flight Borrowed delivery" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withSystemTempDirectory "jitml-cancellation-commands" $ \directory -> do
            let commandLogPath = directory </> "commands.log"
            withFakeNode (cancellationScript validWorkflowPayload commandLogPath) $ \settings -> do
              handlerEntered <- newEmptyMVar
              handlerRelease <- newEmptyMVar
              observed <- newIORef []
              worker <-
                async $
                  runPulsarWebSocketSubprocess settings $
                    pulsarConsumeUntil
                      subscription
                      (\event -> liftIO (modifyIORef' observed (<> [event])))
                      ( \_delivery -> do
                          liftIO (putMVar handlerEntered ())
                          _ <- liftIO (takeMVar handlerRelease)
                          pure (done ack ())
                      )
              withinFixtureTimeout (takeMVar handlerEntered)
              cancellationResult <-
                withinFixtureTimeout $ do
                  cancel worker
                  waitCatch worker
              case cancellationResult of
                Left _asyncException -> pure ()
                Right result ->
                  assertFailure
                    ("cancellation was converted into a consumer result: " <> show result)
              readIORef observed
                >>= ( @?=
                        [ ConsumerSessionConnected 1
                        , ConsumerSessionDraining
                        , ConsumerSessionDrained
                        ]
                    )
              commands <- Text.lines <$> Text.IO.readFile commandLogPath
              traverse (decodeParentCommand . Text.Encoding.encodeUtf8) commands
                @?= Right [Settle receipt1 (Nack "drain-requested"), Drain]
    , testCase "async cancellation returns a failed drain settlement instead of hiding it" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (cancellationSettlementFailureScript validWorkflowPayload) $ \settings -> do
            handlerEntered <- newEmptyMVar
            neverRelease <- newEmptyMVar
            worker <-
              async $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    ( \_delivery -> do
                        liftIO (putMVar handlerEntered ())
                        _ <- liftIO (takeMVar neverRelease)
                        pure (done ack ())
                    )
            withinFixtureTimeout (takeMVar handlerEntered)
            cancellationResult <-
              withinFixtureTimeout (cancel worker >> waitCatch worker)
            assertCancellationSettlementFailure "single consumer" cancellationResult
    , testCase "async cancellation returns a post-drain bridge failure instead of hiding it" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (cancellationPostDrainFailureScript validWorkflowPayload) $ \settings -> do
            handlerEntered <- newEmptyMVar
            neverRelease <- newEmptyMVar
            worker <-
              async $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    ( \_delivery -> do
                        liftIO (putMVar handlerEntered ())
                        _ <- liftIO (takeMVar neverRelease)
                        pure (done ack ())
                    )
            withinFixtureTimeout (takeMVar handlerEntered)
            cancellationResult <-
              withinFixtureTimeout $ do
                cancel worker
                waitCatch worker
            assertCancellationTransportFailure "single consumer" cancellationResult
    , testCase "async cancellation returns an Owned subscription cleanup failure" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withSystemTempDirectory "jitml-owned-cancellation-commands" $ \directory -> do
            let commandLogPath = directory </> "commands.log"
            withFakeNode (cancellationScript validWorkflowPayload commandLogPath) $ \settings -> do
              handlerEntered <- newEmptyMVar
              neverRelease <- newEmptyMVar
              worker <-
                async
                  $ runPulsarWebSocketSubprocess
                    ( settings
                        { pulsarAdminEndpoint = "http://127.0.0.1:1/admin/v2"
                        }
                    )
                  $ pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    ( \_delivery -> do
                        liftIO (putMVar handlerEntered ())
                        _ <- liftIO (takeMVar neverRelease)
                        pure (done ack ())
                    )
              withinFixtureTimeout (takeMVar handlerEntered)
              cancellationResult <-
                withinFixtureTimeout $ do
                  cancel worker
                  waitCatch worker
              case cancellationResult of
                Right (Left (ConsumerCleanupFailure (SETransient detail))) -> do
                  assertContains "cleanup command" "curl" detail
                  assertContains "cleanup exit" "exit:" detail
                  assertContains "owned subscription" "borrowed-unit" detail
                other ->
                  assertFailure
                    ("expected typed Owned cleanup failure after cancellation, got " <> show other)
              commands <- Text.lines <$> Text.IO.readFile commandLogPath
              traverse (decodeParentCommand . Text.Encoding.encodeUtf8) commands
                @?= Right [Settle receipt1 (Nack "drain-requested"), Drain]
    , testCase "batch cancellation returns an Owned subscription cleanup failure" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withSystemTempDirectory "jitml-owned-batch-cancellation-commands" $ \directory -> do
            let commandLogPath = directory </> "commands.log"
                policy = either (error . show) id (mkBatchPolicy 1 1_000_000)
            withFakeNode (batchCancellationScript validWorkflowPayload commandLogPath) $ \settings -> do
              handlerEntered <- newEmptyMVar
              neverRelease <- newEmptyMVar
              worker <-
                async
                  $ runPulsarWebSocketSubprocess
                    ( settings
                        { pulsarAdminEndpoint = "http://127.0.0.1:1/admin/v2"
                        }
                    )
                  $ pulsarConsumeBatchesUntil
                    (pure policy)
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    ( \_batch -> do
                        liftIO (putMVar handlerEntered ())
                        _ <- liftIO (takeMVar neverRelease)
                        pure (doneBatch ack ())
                    )
              withinFixtureTimeout (takeMVar handlerEntered)
              cancellationResult <-
                withinFixtureTimeout $ do
                  cancel worker
                  waitCatch worker
              case cancellationResult of
                Right (Left (ConsumerCleanupFailure (SETransient detail))) ->
                  assertContains "batch cleanup command" "curl" detail
                other ->
                  assertFailure
                    ("expected typed Owned batch cleanup failure after cancellation, got " <> show other)
              commands <- Text.lines <$> Text.IO.readFile commandLogPath
              traverse (decodeParentCommand . Text.Encoding.encodeUtf8) commands
                @?= Right [Permit 1, Settle receipt1 (Nack "drain-requested"), Drain]
    , testCase "batch handler cancellation returns a failed drain settlement" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (batchCancellationSettlementFailureScript validWorkflowPayload) $ \settings -> do
            let policy = either (error . show) id (mkBatchPolicy 1 1_000_000)
            handlerEntered <- newEmptyMVar
            neverRelease <- newEmptyMVar
            worker <-
              async $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeBatchesUntil
                    (pure policy)
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    ( \_batch -> do
                        liftIO (putMVar handlerEntered ())
                        _ <- liftIO (takeMVar neverRelease)
                        pure (doneBatch ack ())
                    )
            withinFixtureTimeout (takeMVar handlerEntered)
            cancellationResult <-
              withinFixtureTimeout (cancel worker >> waitCatch worker)
            assertCancellationSettlementFailure "batch handler" cancellationResult
    , testCase "batch handler cancellation returns a post-drain bridge failure" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (batchCancellationPostDrainFailureScript validWorkflowPayload) $ \settings -> do
            let policy = either (error . show) id (mkBatchPolicy 1 1_000_000)
            handlerEntered <- newEmptyMVar
            neverRelease <- newEmptyMVar
            worker <-
              async $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeBatchesUntil
                    (pure policy)
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    ( \_batch -> do
                        liftIO (putMVar handlerEntered ())
                        _ <- liftIO (takeMVar neverRelease)
                        pure (doneBatch ack ())
                    )
            withinFixtureTimeout (takeMVar handlerEntered)
            cancellationResult <-
              withinFixtureTimeout $ do
                cancel worker
                waitCatch worker
            assertCancellationTransportFailure "batch handler" cancellationResult
    , testCase "batch policy cancellation returns a failed drain settlement" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (batchCancellationSettlementFailureScript validWorkflowPayload) $ \settings -> do
            policyEntered <- newEmptyMVar
            neverReturnPolicy <- newEmptyMVar
            let readPolicy = do
                  liftIO (putMVar policyEntered ())
                  liftIO (takeMVar neverReturnPolicy)
            worker <-
              async $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeBatchesUntil
                    readPolicy
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    (const (pure (doneBatch ack ())))
            withinFixtureTimeout (takeMVar policyEntered)
            cancellationResult <-
              withinFixtureTimeout (cancel worker >> waitCatch worker)
            assertCancellationSettlementFailure "batch policy" cancellationResult
    , testCase "batch policy cancellation returns a post-drain bridge failure" $
        withWorkflowFixture Borrowed $ \_topic _event subscription ->
          withFakeNode (batchCancellationPostDrainFailureScript validWorkflowPayload) $ \settings -> do
            policyEntered <- newEmptyMVar
            neverReturnPolicy <- newEmptyMVar
            let readPolicy = do
                  liftIO (putMVar policyEntered ())
                  liftIO (takeMVar neverReturnPolicy)
            worker <-
              async $
                runPulsarWebSocketSubprocess settings $
                  pulsarConsumeBatchesUntil
                    readPolicy
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    (const (pure (doneBatch ack ())))
            withinFixtureTimeout (takeMVar policyEntered)
            cancellationResult <-
              withinFixtureTimeout $ do
                cancel worker
                waitCatch worker
            assertCancellationTransportFailure "batch policy" cancellationResult
    , testCase "late cancellation cannot hide a failing Owned subscription DELETE" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withFakeNode (terminalScript AckKind validWorkflowPayload) $ \settings ->
            withDelayedFailingAdmin $ \adminEndpoint deleteStarted -> do
              worker <-
                async
                  $ runPulsarWebSocketSubprocess
                    (settings {pulsarAdminEndpoint = adminEndpoint})
                  $ pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    (const (pure (done ack ())))
              withinFixtureTimeout (takeMVar deleteStarted)
              cancellationResult <-
                withinFixtureTimeout $ do
                  cancel worker
                  waitCatch worker
              assertLateCleanupFailure "single consumer" cancellationResult
    , testCase "late cancellation cannot hide a failing Owned batch subscription DELETE" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withFakeNode (singletonBatchScript validWorkflowPayload) $ \settings ->
            withDelayedFailingAdmin $ \adminEndpoint deleteStarted -> do
              let policy = either (error . show) id (mkBatchPolicy 64 100_000)
              worker <-
                async
                  $ runPulsarWebSocketSubprocess
                    (settings {pulsarAdminEndpoint = adminEndpoint})
                  $ pulsarConsumeBatchesUntil
                    (pure policy)
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    (const (pure (doneBatch ack ())))
              withinFixtureTimeout (takeMVar deleteStarted)
              cancellationResult <-
                withinFixtureTimeout $ do
                  cancel worker
                  waitCatch worker
              assertLateCleanupFailure "batch consumer" cancellationResult
    , testCase "late cancellation cannot hide a finalized single settlement failure" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withFakeNode (settlementFailureScript validWorkflowPayload) $ \settings ->
            withDelayedSuccessfulAdmin $ \adminEndpoint deleteStarted -> do
              worker <-
                async
                  $ runPulsarWebSocketSubprocess
                    (settings {pulsarAdminEndpoint = adminEndpoint})
                  $ pulsarConsumeUntil
                    subscription
                    (const (pure ()))
                    (const (pure (done ack ())))
              withinFixtureTimeout (takeMVar deleteStarted)
              cancellationResult <-
                withinFixtureTimeout (cancel worker >> waitCatch worker)
              assertRetainedSettlementFailure "single consumer" cancellationResult
    , testCase "late cancellation cannot hide a finalized batch settlement failure" $
        withWorkflowFixture Owned $ \_topic _event subscription ->
          withFakeNode (batchSettlementFailureScript validWorkflowPayload) $ \settings ->
            withDelayedSuccessfulAdmin $ \adminEndpoint deleteStarted -> do
              let policy = either (error . show) id (mkBatchPolicy 1 1_000_000)
              worker <-
                async
                  $ runPulsarWebSocketSubprocess
                    (settings {pulsarAdminEndpoint = adminEndpoint})
                  $ pulsarConsumeBatchesUntil
                    (pure policy)
                    (const ())
                    (const BatchDeadlineEnforced)
                    subscription
                    (const (pure ()))
                    (const (pure (doneBatch ack ())))
              withinFixtureTimeout (takeMVar deleteStarted)
              cancellationResult <-
                withinFixtureTimeout (cancel worker >> waitCatch worker)
              assertRetainedSettlementFailure "batch consumer" cancellationResult
    ]

withWorkflowFixture
  :: SubscriptionOwnership
  -> ( Topic WorkflowStatusMessage
       -> WorkflowStatusMessage
       -> Subscription WorkflowStatusMessage
       -> Assertion
     )
  -> Assertion
withWorkflowFixture ownership assertion =
  case topicFor WorkflowStatusRoute LinuxCPU of
    Left err -> assertFailure ("failed to resolve workflow-status topic: " <> show err)
    Right topic ->
      case mkWorkflowStatusMessage validWorkflowPayload of
        Left err -> assertFailure ("failed to build workflow-status event: " <> Text.unpack err)
        Right event ->
          case mkSubscription topic "borrowed-unit" FromEarliest ownership of
            Left err -> assertFailure ("failed to build subscription: " <> show err)
            Right subscription -> assertion topic event subscription

withReplySubscription
  :: Topic event
  -> Text
  -> (Subscription event -> Assertion)
  -> Assertion
withReplySubscription topic name assertion =
  case mkSubscription topic name FromLatest Owned of
    Left err -> assertFailure ("failed to build reply subscription: " <> show err)
    Right subscription -> assertion subscription

withFakeNode :: Text -> (PulsarWebSocketSettings -> Assertion) -> Assertion
withFakeNode script assertion =
  withSystemTempDirectory "jitml-fake-pulsar-node" $ \directory -> do
    let path = directory </> "fake-node"
    Text.IO.writeFile path script
    permissions <- getPermissions path
    setPermissions path (setOwnerExecutable True permissions)
    -- Overlay-backed container files can retain a short write lease after the
    -- close performed by writeFile; wait before posix_spawn executes it.
    threadDelay 50000
    assertion testSettings {pulsarNodeBinary = path}

withDelayedFailingAdmin :: (Text -> MVar () -> Assertion) -> Assertion
withDelayedFailingAdmin assertion =
  Socket.withSocketsDo $
    bracket openListener Socket.close $ \listener -> do
      address <- Socket.getSocketName listener
      port <-
        case address of
          Socket.SockAddrInet listenerPort _host -> pure listenerPort
          other -> ioError (userError ("expected IPv4 test listener, got " <> show other))
      deleteStarted <- newEmptyMVar
      let endpoint = "http://127.0.0.1:" <> Text.pack (show port) <> "/admin/v2"
          serveFailure = do
            (connection, _peer) <- Socket.accept listener
            bracket (pure connection) Socket.close $ \client -> do
              _request <- Socket.ByteString.recv client 8192
              putMVar deleteStarted ()
              threadDelay 200000
              Socket.ByteString.sendAll
                client
                "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      bracket (async serveFailure) cancel $ \_server ->
        assertion endpoint deleteStarted
 where
  openListener = do
    listener <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
    Socket.setSocketOption listener Socket.ReuseAddr 1
    Socket.bind
      listener
      (Socket.SockAddrInet 0 (Socket.tupleToHostAddress (127, 0, 0, 1)))
    Socket.listen listener 1
    pure listener

withDelayedSuccessfulAdmin :: (Text -> MVar () -> Assertion) -> Assertion
withDelayedSuccessfulAdmin assertion =
  Socket.withSocketsDo $
    bracket openListener Socket.close $ \listener -> do
      address <- Socket.getSocketName listener
      port <-
        case address of
          Socket.SockAddrInet listenerPort _host -> pure listenerPort
          other -> ioError (userError ("expected IPv4 test listener, got " <> show other))
      deleteStarted <- newEmptyMVar
      let endpoint = "http://127.0.0.1:" <> Text.pack (show port) <> "/admin/v2"
          serveSuccess = do
            (connection, _peer) <- Socket.accept listener
            bracket (pure connection) Socket.close $ \client -> do
              _request <- Socket.ByteString.recv client 8192
              putMVar deleteStarted ()
              threadDelay 200000
              Socket.ByteString.sendAll
                client
                "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      bracket (async serveSuccess) cancel $ \_server ->
        assertion endpoint deleteStarted
 where
  openListener = do
    listener <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
    Socket.setSocketOption listener Socket.ReuseAddr 1
    Socket.bind
      listener
      (Socket.SockAddrInet 0 (Socket.tupleToHostAddress (127, 0, 0, 1)))
    Socket.listen listener 1
    pure listener

withRedirectingSuccessfulAdmin
  :: (Text -> MVar [ByteString] -> Assertion)
  -> Assertion
withRedirectingSuccessfulAdmin assertion =
  Socket.withSocketsDo $
    bracket openListener Socket.close $ \listener -> do
      address <- Socket.getSocketName listener
      port <-
        case address of
          Socket.SockAddrInet listenerPort _host -> pure listenerPort
          other -> ioError (userError ("expected IPv4 test listener, got " <> show other))
      requestsObserved <- newEmptyMVar
      let endpoint = "http://127.0.0.1:" <> Text.pack (show port) <> "/admin/v2"
          redirected = "http://127.0.0.1:" <> Text.pack (show port) <> "/redirected-cleanup"
          serveRedirect = do
            initialRequest <- acceptRequest listener
            sendResponse
              initialRequest
              ( "HTTP/1.1 307 Temporary Redirect\r\nLocation: "
                  <> Text.Encoding.encodeUtf8 redirected
                  <> "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
              )
            redirectedRequest <- acceptRequest listener
            sendResponse
              redirectedRequest
              "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            putMVar requestsObserved [fst initialRequest, fst redirectedRequest]
      bracket (async serveRedirect) cancel $ \_server ->
        assertion endpoint requestsObserved
 where
  openListener = do
    listener <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
    Socket.setSocketOption listener Socket.ReuseAddr 1
    Socket.bind
      listener
      (Socket.SockAddrInet 0 (Socket.tupleToHostAddress (127, 0, 0, 1)))
    Socket.listen listener 2
    pure listener

  acceptRequest listener = do
    (connection, _peer) <- Socket.accept listener
    request <- Socket.ByteString.recv connection 8192
    pure (request, connection)

  sendResponse (_request, connection) response =
    bracket (pure connection) Socket.close $ \client -> do
      Socket.ByteString.sendAll client response

withAdminResponses
  :: [ByteString]
  -> (Text -> MVar [ByteString] -> Assertion)
  -> Assertion
withAdminResponses responses =
  withAdminResponseEffects [(response, pure ()) | response <- responses]

withAdminResponseEffects
  :: [(ByteString, IO ())]
  -> (Text -> MVar [ByteString] -> Assertion)
  -> Assertion
withAdminResponseEffects responseEffects assertion =
  Socket.withSocketsDo $
    bracket openListener Socket.close $ \listener -> do
      address <- Socket.getSocketName listener
      port <-
        case address of
          Socket.SockAddrInet listenerPort _host -> pure listenerPort
          other -> ioError (userError ("expected IPv4 test listener, got " <> show other))
      requestsObserved <- newEmptyMVar
      let endpoint = "http://127.0.0.1:" <> Text.pack (show port) <> "/admin/v2"
          serve [] observed = putMVar requestsObserved (reverse observed)
          serve ((response, effect) : remaining) observed = do
            (connection, _peer) <- Socket.accept listener
            request <-
              bracket (pure connection) Socket.close $ \client -> do
                received <- Socket.ByteString.recv client 8192
                effect
                Socket.ByteString.sendAll client response
                pure received
            serve remaining (request : observed)
      bracket (async (serve responseEffects [])) cancel $ \_server ->
        assertion endpoint requestsObserved
 where
  openListener = do
    listener <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
    Socket.setSocketOption listener Socket.ReuseAddr 1
    Socket.bind
      listener
      (Socket.SockAddrInet 0 (Socket.tupleToHostAddress (127, 0, 0, 1)))
    Socket.listen listener (max 1 (length responseEffects))
    pure listener

httpNoContent :: ByteString
httpNoContent =
  "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

httpConflict :: ByteString
httpConflict =
  "HTTP/1.1 409 Conflict\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

httpInternalError :: ByteString
httpInternalError =
  "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

assertLateCleanupFailure
  :: String
  -> Either SomeException (Either ConsumerFailure ())
  -> Assertion
assertLateCleanupFailure label result =
  case result of
    Right (Left (ConsumerCleanupFailure (SETransient detail))) -> do
      assertContains (label <> " late cleanup status") "unexpected HTTP status" detail
      assertContains (label <> " late cleanup response") "500" detail
    other ->
      assertFailure
        ( "expected typed Owned cleanup failure after cancellation during DELETE for "
            <> label
            <> ", got "
            <> show other
        )

assertCancellationSettlementFailure
  :: String
  -> Either SomeException (Either ConsumerFailure ())
  -> Assertion
assertCancellationSettlementFailure label result =
  case result of
    Right (Left (ConsumerSettlementFailure message (SETransient detail))) -> do
      assertContains (label <> " settlement class") "settlement" message
      assertContains (label <> " settlement detail") "forced cancellation settlement failure" detail
    other ->
      assertFailure
        ( "expected typed cancellation settlement failure for "
            <> label
            <> ", got "
            <> show other
        )

assertCancellationTransportFailure
  :: String
  -> Either SomeException (Either ConsumerFailure ())
  -> Assertion
assertCancellationTransportFailure label result =
  case result of
    Right (Left (ConsumerTransportFailure processFailure)) -> do
      processFailureExitCode processFailure @?= ExitFailure 29
      assertContains
        (label <> " post-drain stdout")
        "\"type\":\"drained\""
        (processFailureStdout processFailure)
      processFailureStderr processFailure @?= "post-drain bridge failure"
    other ->
      assertFailure
        ( "expected typed post-drain transport failure for "
            <> label
            <> ", got "
            <> show other
        )

assertRetainedSettlementFailure
  :: String
  -> Either SomeException (Either ConsumerFailure ())
  -> Assertion
assertRetainedSettlementFailure label result =
  case result of
    Right (Left (ConsumerSettlementFailure message (SETransient detail))) -> do
      assertContains (label <> " retained settlement class") "settlement" message
      assertContains (label <> " retained settlement detail") "broker rejected" detail
    other ->
      assertFailure
        ( "expected retained settlement failure after late cancellation for "
            <> label
            <> ", got "
            <> show other
        )

withRealNodeBridge
  :: Text
  -> (PulsarWebSocketSettings -> FilePath -> Assertion)
  -> Assertion
withRealNodeBridge payload assertion =
  withSystemTempDirectory "jitml-real-node-pulsar-bridge" $ \directory -> do
    let preloadPath = directory </> "fake-websocket-preload.js"
        wrapperPath = directory </> "node-with-fake-websocket"
        logPath = directory </> "websocket.log"
    Text.IO.writeFile preloadPath (fakeWebSocketPreload logPath payload)
    Text.IO.writeFile
      wrapperPath
      ( Text.unlines
          [ "#!/bin/sh"
          , "exec node --require " <> shellQuote (Text.pack preloadPath) <> " \"$@\""
          ]
      )
    permissions <- getPermissions wrapperPath
    setPermissions wrapperPath (setOwnerExecutable True permissions)
    threadDelay 50000
    assertion
      testSettings {pulsarNodeBinary = wrapperPath}
      logPath

withRealBatchDrainRaceBridge
  :: Text
  -> (PulsarWebSocketSettings -> FilePath -> Assertion)
  -> Assertion
withRealBatchDrainRaceBridge payload assertion =
  withSystemTempDirectory "jitml-real-batch-drain-race" $ \directory -> do
    let preloadPath = directory </> "fake-batch-websocket-preload.js"
        wrapperPath = directory </> "node-with-fake-batch-websocket"
        logPath = directory </> "websocket.log"
    Text.IO.writeFile preloadPath (fakeBatchDrainRaceWebSocketPreload logPath payload)
    Text.IO.writeFile
      wrapperPath
      ( Text.unlines
          [ "#!/bin/sh"
          , "exec node --require " <> shellQuote (Text.pack preloadPath) <> " \"$@\""
          ]
      )
    permissions <- getPermissions wrapperPath
    setPermissions wrapperPath (setOwnerExecutable True permissions)
    threadDelay 50000
    assertion
      testSettings {pulsarNodeBinary = wrapperPath}
      logPath

fakeWebSocketPreload :: FilePath -> Text -> Text
fakeWebSocketPreload logPath payload =
  Text.unlines
    [ "const fs = require('fs');"
    , "const logPath = " <> javascriptString (Text.pack logPath) <> ";"
    , "const deliveryPayload = Buffer.from(" <> javascriptString payload <> ").toString('base64');"
    , "let socketCount = 0;"
    , "const append = (line) => fs.appendFileSync(logPath, String(line) + '\\n');"
    , "class FakeWebSocket {"
    , "  constructor(_url) {"
    , "    this.id = ++socketCount;"
    , "    this.readyState = 0;"
    , "    this.bufferedAmount = 0;"
    , "    this.listeners = new Map();"
    , "    append(`socket:${this.id}`);"
    , "    setImmediate(() => { this.readyState = 1; this.emit('open', {}); });"
    , "  }"
    , "  addEventListener(kind, listener) {"
    , "    const listeners = this.listeners.get(kind) || [];"
    , "    listeners.push(listener);"
    , "    this.listeners.set(kind, listeners);"
    , "  }"
    , "  emit(kind, event) {"
    , "    for (const listener of this.listeners.get(kind) || []) listener(event);"
    , "  }"
    , "  send(rawCommand) {"
    , "    const command = JSON.parse(String(rawCommand));"
    , "    if (command.type === 'permit') {"
    , "      append(`permit:${this.id}`);"
    , "      if (this.id !== 1) { append(`unexpected-permit:${this.id}`); return; }"
    , "      setImmediate(() => {"
    , "        append(`delivery:${this.id}`);"
    , "        this.emit('message', { data: JSON.stringify({ messageId: 'broker-secret', payload: deliveryPayload, redeliveryCount: 0 }) });"
    , "      });"
    , "      return;"
    , "    }"
    , "    if (command.messageId) {"
    , "      append(`ack:${this.id}:${command.messageId}`);"
    , "      if (this.id === 1) {"
    , "        this.bufferedAmount = 1;"
    , "        queueMicrotask(() => {"
    , "          if (this.readyState !== 1) return;"
    , "          this.readyState = 3;"
    , "          append('drop:1');"
    , "          this.emit('close', { code: 1006, reason: 'injected-drop' });"
    , "        });"
    , "      } else {"
    , "        this.bufferedAmount = 0;"
    , "      }"
    , "      return;"
    , "    }"
    , "    append(`unexpected-send:${this.id}:${rawCommand}`);"
    , "  }"
    , "  close() {"
    , "    append(`close:${this.id}`);"
    , "    if (this.readyState >= 2) return;"
    , "    this.readyState = 3;"
    , "    setImmediate(() => this.emit('close', { code: 1000, reason: 'drained' }));"
    , "  }"
    , "}"
    , "globalThis.WebSocket = FakeWebSocket;"
    ]

fakeBatchDrainRaceWebSocketPreload :: FilePath -> Text -> Text
fakeBatchDrainRaceWebSocketPreload logPath payload =
  Text.unlines
    [ "const fs = require('fs');"
    , "const logPath = " <> javascriptString (Text.pack logPath) <> ";"
    , "const deliveryPayload = Buffer.from(" <> javascriptString payload <> ").toString('base64');"
    , "const append = (line) => fs.appendFileSync(logPath, String(line) + '\\n');"
    , "class FakeWebSocket {"
    , "  constructor(_url) {"
    , "    this.id = 1;"
    , "    this.readyState = 0;"
    , "    this.bufferedAmount = 0;"
    , "    this.listeners = new Map();"
    , "    this.permitCount = 0;"
    , "    append('socket:1');"
    , "    setImmediate(() => { this.readyState = 1; this.emit('open', {}); });"
    , "  }"
    , "  addEventListener(kind, listener) {"
    , "    const listeners = this.listeners.get(kind) || [];"
    , "    listeners.push(listener);"
    , "    this.listeners.set(kind, listeners);"
    , "  }"
    , "  emit(kind, event) {"
    , "    for (const listener of this.listeners.get(kind) || []) listener(event);"
    , "  }"
    , "  deliver(index) {"
    , "    append(`delivery:${index}`);"
    , "    this.emit('message', { data: JSON.stringify({ messageId: `broker-${index}`, payload: deliveryPayload, redeliveryCount: 0 }) });"
    , "  }"
    , "  send(rawCommand) {"
    , "    const command = JSON.parse(String(rawCommand));"
    , "    if (command.type === 'permit') {"
    , "      this.permitCount += 1;"
    , "      append(`permit:${this.permitCount}`);"
    , "      if (this.permitCount === 1) setImmediate(() => this.deliver(1));"
    , "      return;"
    , "    }"
    , "    if (command.type === 'negativeAcknowledge') {"
    , "      append(`nack:${this.id}:${command.messageId}`);"
    , "      this.bufferedAmount = 1;"
    , "      setTimeout(() => { this.bufferedAmount = 0; append(`nack-flushed:${this.id}`); }, 50);"
    , "      return;"
    , "    }"
    , "    if (command.messageId) {"
    , "      append(`ack:${this.id}:${command.messageId}`);"
    , "      if (command.messageId === 'broker-1') setImmediate(() => this.deliver(2));"
    , "      return;"
    , "    }"
    , "    append(`unexpected-send:${this.id}:${rawCommand}`);"
    , "  }"
    , "  close() {"
    , "    append(`close:${this.id}`);"
    , "    if (this.bufferedAmount !== 0) append(`close-while-buffered:${this.id}`);"
    , "    if (this.readyState >= 2) return;"
    , "    this.readyState = 3;"
    , "    setImmediate(() => this.emit('close', { code: 1000, reason: 'drained' }));"
    , "  }"
    , "}"
    , "globalThis.WebSocket = FakeWebSocket;"
    ]

javascriptString :: Text -> Text
javascriptString = Text.pack . show . Text.unpack

assertOrderedLog :: [Text] -> [Text] -> Assertion
assertOrderedLog actual expected =
  assertBool
    ("expected ordered bridge log " <> show expected <> ", got " <> show actual)
    (orderedSubsequence expected actual)

orderedSubsequence :: (Eq value) => [value] -> [value] -> Bool
orderedSubsequence [] _actual = True
orderedSubsequence _expected [] = False
orderedSubsequence expected@(next : rest) (actual : remaining)
  | next == actual = orderedSubsequence rest remaining
  | otherwise = orderedSubsequence expected remaining

withinFixtureTimeout :: IO value -> IO value
withinFixtureTimeout action = do
  maybeResult <- timeout fixtureTimeoutMicroseconds action
  case maybeResult of
    Nothing -> ioError (userError "fake Pulsar transport timed out")
    Just result -> pure result

terminalScript :: SettlementKind -> Text -> Text
terminalScript settlementKind payload =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" (settlementKindText settlementKind)
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt1 settlementKind)
    , emitFrame Drained
    ]

twoDeliveryScript :: Text -> Text
twoDeliveryScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 encodedPayload 0)
    , readCommand "settlement1" "settle"
    , requireCommandKind "settlement1" "ack"
    , emitFrame (Settled receipt1 AckKind)
    , emitFrame (Delivery receipt2 encodedPayload 2)
    , readCommand "settlement2" "settle"
    , requireCommandKind "settlement2" "ack"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt2 AckKind)
    , emitFrame Drained
    ]
 where
  encodedPayload = Text.Encoding.encodeUtf8 payload

twoDeliveryBatchScript :: Text -> Text
twoDeliveryBatchScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit1" "permit"
    , emitFrame (Delivery receipt1 encodedPayload 0)
    , readCommand "permit2" "permit"
    , emitFrame (Delivery receipt2 encodedPayload 0)
    , readCommand "settlement1" "settle"
    , requireCommandKind "settlement1" "ack"
    , requireCommandReceipt "settlement1" "delivery-1"
    , readCommand "settlement2" "settle"
    , requireCommandKind "settlement2" "ack"
    , requireCommandReceipt "settlement2" "delivery-2"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt1 AckKind)
    , emitFrame (Settled receipt2 AckKind)
    , emitFrame Drained
    ]
 where
  encodedPayload = Text.Encoding.encodeUtf8 payload

singletonBatchScript :: Text -> Text
singletonBatchScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit1" "permit"
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "permit2" "permit"
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "ack"
    , requireCommandReceipt "settlement" "delivery-1"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt1 AckKind)
    , emitFrame Drained
    ]

sloRecoveryBatchScript :: Text -> Text
sloRecoveryBatchScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit1" "permit"
    , emitFrame (Delivery receipt1 encodedPayload 0)
    , readCommand "settlement1" "settle"
    , requireCommandKind "settlement1" "nack"
    , requireCommandReceipt "settlement1" "delivery-1"
    , emitFrame (Settled receipt1 NackKind)
    , readCommand "permit2" "permit"
    , emitFrame (Delivery receipt2 encodedPayload 0)
    , readCommand "settlement2" "settle"
    , requireCommandKind "settlement2" "ack"
    , requireCommandReceipt "settlement2" "delivery-2"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt2 AckKind)
    , emitFrame Drained
    ]
 where
  encodedPayload = Text.Encoding.encodeUtf8 payload

settlementFailureScript :: Text -> Text
settlementFailureScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , readCommand "drain" "drain"
    , emitFrame (BridgeError SettlementScope (Just receipt1) True "broker rejected settlement")
    ]

batchSettlementFailureScript :: Text -> Text
batchSettlementFailureScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit" "permit"
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "ack"
    , readCommand "drain" "drain"
    , emitFrame
        ( BridgeError
            SettlementScope
            (Just receipt1)
            True
            "broker rejected batch settlement"
        )
    ]

closedBeforeSettlementScript :: Text -> Text
closedBeforeSettlementScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , "exec 0<&-"
    , "printf '%s' 'bridge closed before settlement' >&2"
    , "exit 29"
    ]

cancellationScript :: Text -> FilePath -> Text
cancellationScript payload commandLogPath =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , recordCommand commandLogPath "settlement"
    , requireCommandKind "settlement" "nack"
    , requireCommandReason "settlement" "drain-requested"
    , readCommand "drain" "drain"
    , recordCommand commandLogPath "drain"
    , emitFrame (Settled receipt1 NackKind)
    , emitFrame Drained
    ]

batchCancellationScript :: Text -> FilePath -> Text
batchCancellationScript payload commandLogPath =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit" "permit"
    , recordCommand commandLogPath "permit"
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , recordCommand commandLogPath "settlement"
    , requireCommandKind "settlement" "nack"
    , requireCommandReason "settlement" "drain-requested"
    , readCommand "drain" "drain"
    , recordCommand commandLogPath "drain"
    , emitFrame (Settled receipt1 NackKind)
    , emitFrame Drained
    ]

cancellationSettlementFailureScript :: Text -> Text
cancellationSettlementFailureScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "nack"
    , readCommand "drain" "drain"
    , emitFrame
        ( BridgeError
            SettlementScope
            (Just receipt1)
            True
            "forced cancellation settlement failure"
        )
    ]

cancellationPostDrainFailureScript :: Text -> Text
cancellationPostDrainFailureScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "nack"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt1 NackKind)
    , emitFrame Drained
    , "printf '%s' 'post-drain bridge failure' >&2"
    , "exit 29"
    ]

batchCancellationSettlementFailureScript :: Text -> Text
batchCancellationSettlementFailureScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit" "permit"
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "nack"
    , readCommand "drain" "drain"
    , emitFrame
        ( BridgeError
            SettlementScope
            (Just receipt1)
            True
            "forced cancellation settlement failure"
        )
    ]

batchCancellationPostDrainFailureScript :: Text -> Text
batchCancellationPostDrainFailureScript payload =
  shellScript
    [ emitFrame (Connected 1)
    , readCommand "permit" "permit"
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "nack"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt1 NackKind)
    , emitFrame Drained
    , "printf '%s' 'post-drain bridge failure' >&2"
    , "exit 29"
    ]

publisherFailureScript :: Text
publisherFailureScript =
  shellScript
    [ "cat >/dev/null"
    , "printf '%s' 'partial-out'"
    , "printf '%s' 'producer exploded' >&2"
    , "exit 19"
    ]

publisherSuccessScript :: Text
publisherSuccessScript =
  shellScript
    [ "cat >/dev/null"
    , "printf '%s' 'correlated-publish-ack'"
    ]

publisherInvocationMarkerScript :: FilePath -> Text
publisherInvocationMarkerScript markerPath =
  shellScript
    [ "touch " <> shellQuote (Text.pack markerPath)
    , "cat >/dev/null"
    , "printf '%s' 'unexpected-publish'"
    ]

replyCursorBrokerScript :: Text -> FilePath -> FilePath -> FilePath -> Text
replyCursorBrokerScript payload cursorPath messagePath eventLogPath =
  shellScript
    [ "case \"$3\" in"
    , "  */producer/*)"
    , "    if [ -e " <> shellQuote (Text.pack cursorPath) <> " ]; then"
    , "      cat > " <> shellQuote (Text.pack messagePath)
    , "      printf '%s\\n' 'publish-with-cursor' >> " <> shellQuote (Text.pack eventLogPath)
    , "    else"
    , "      cat >/dev/null"
    , "      printf '%s\\n' 'publish-without-cursor' >> " <> shellQuote (Text.pack eventLogPath)
    , "    fi"
    , "    printf '%s' 'reply-publish-ack'"
    , "    ;;"
    , "  */consumer/*)"
    , "    test -s " <> shellQuote (Text.pack messagePath)
    , "    printf '%s\\n' 'delivery' >> " <> shellQuote (Text.pack eventLogPath)
    , emitFrame (Connected 1)
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "ack"
    , readCommand "drain" "drain"
    , emitFrame (Settled receipt1 AckKind)
    , emitFrame Drained
    , "    ;;"
    , "  *)"
    , "    echo 'unexpected fake reply-cursor URL' >&2"
    , "    exit 41"
    , "    ;;"
    , "esac"
    ]

-- | The files the fake broker and fake admin API share for one harness run.
data HarnessPaths = HarnessPaths
  { harnessCursor :: FilePath
  , harnessMessage :: FilePath
  , harnessEventLog :: FilePath
  , harnessConsumerUrl :: FilePath
  }

harnessPaths :: FilePath -> HarnessPaths
harnessPaths directory =
  HarnessPaths
    { harnessCursor = directory </> "cursor-created"
    , harnessMessage = directory </> "cursor-message"
    , harnessEventLog = directory </> "cursor-events.log"
    , harnessConsumerUrl = directory </> "consumer-url"
    }

harnessAppend :: HarnessPaths -> Text -> IO ()
harnessAppend paths eventName =
  Text.IO.appendFile (harnessEventLog paths) (eventName <> "\n")

-- | The fake admin API's CREATE: the cursor now exists for later publishers.
harnessCreateCursor :: HarnessPaths -> IO ()
harnessCreateCursor paths = do
  Text.IO.writeFile (harnessCursor paths) "created"
  harnessAppend paths "create"

-- | The broker-side event log of a harness run, oldest first.  A run that never
-- reached the broker has no log yet, which reads as no events, so an assertion
-- on the order fails with the actual (empty) sequence rather than an
-- exception about a missing file.
readHarnessEvents :: HarnessPaths -> IO [Text]
readHarnessEvents paths = do
  exists <- doesFileExist (harnessEventLog paths)
  if exists
    then Text.lines <$> Text.IO.readFile (harnessEventLog paths)
    else pure []

-- | The HTTP method of each admin request the fake admin API received.
requestMethods :: [ByteString] -> [Text]
requestMethods = fmap (Text.takeWhile (/= ' ') . Text.Encoding.decodeUtf8)

-- | A typed executable that appends @execute@ to the broker event log and
-- writes the message the fake consumer delivers: it is the publisher of a
-- typed-executable workflow, and the log records whether it ever ran.
harnessExecutable :: HarnessPaths -> Subprocess
harnessExecutable paths =
  subprocess
    "/bin/sh"
    [ "-c"
    , "printf '%s\\n' 'execute' >> "
        <> shellQuote (Text.pack (harnessEventLog paths))
        <> "; printf '%s' 'published-by-executable' > "
        <> shellQuote (Text.pack (harnessMessage paths))
    ]

-- | A cancelled harness run must end by rethrowing exactly 'AsyncCancelled',
-- not a wrapped or converted exception and not a workflow result.
requireHarnessCancellation :: Either SomeException HarnessResult -> Assertion
requireHarnessCancellation outcome =
  case outcome of
    Left exception
      | Just AsyncCancelled <- fromException exception -> pure ()
      | otherwise ->
          assertFailure ("cancellation changed identity: " <> show exception)
    Right _result ->
      assertFailure "cancellation produced a workflow result"

-- | A fake node for @runLiveWorkflow@ over the harness transport.  The
-- producer records whether the reply cursor already exists when it is invoked
-- and keeps the published message; the consumer reports its socket open at once
-- (as a real socket would), delivers only after a publication has landed, and
-- then idles until the interpreter stops it.  The producer appends its event
-- log line BEFORE the message becomes visible to the consumer: the consumer
-- polls the message file from another process, so logging afterwards would let
-- a delivery be logged ahead of the publication that caused it.
liveWorkflowBrokerScript :: Text -> HarnessPaths -> Text
liveWorkflowBrokerScript payload paths =
  shellScript
    [ "case \"$3\" in"
    , "  */producer/*)"
    , "    if [ -e " <> shellQuote (Text.pack (harnessCursor paths)) <> " ]; then"
    , "      printf '%s\\n' 'publish-with-cursor' >> " <> shellQuote (Text.pack (harnessEventLog paths))
    , "      cat > " <> shellQuote (Text.pack (harnessMessage paths))
    , "    else"
    , "      cat >/dev/null"
    , "      printf '%s\\n' 'publish-without-cursor' >> "
        <> shellQuote (Text.pack (harnessEventLog paths))
    , "    fi"
    , "    printf '%s' 'reply-publish-ack'"
    , "    ;;"
    , "  */consumer/*)"
    , "    printf '%s' \"$3\" > " <> shellQuote (Text.pack (harnessConsumerUrl paths))
    , emitFrame (Connected 1)
    , "    waited=0"
    , "    while [ ! -s " <> shellQuote (Text.pack (harnessMessage paths)) <> " ]; do"
    , "      waited=$((waited + 1))"
    , "      if [ \"$waited\" -gt 400 ]; then echo 'no publication reached the fake broker' >&2; exit 42; fi"
    , "      sleep 0.05"
    , "    done"
    , "    printf '%s\\n' 'delivery' >> " <> shellQuote (Text.pack (harnessEventLog paths))
    , emitFrame (Delivery receipt1 (Text.Encoding.encodeUtf8 payload) 0)
    , readCommand "settlement" "settle"
    , requireCommandKind "settlement" "ack"
    , emitFrame (Settled receipt1 AckKind)
    , "    IFS= read -r idle || true"
    , "    ;;"
    , "  *)"
    , "    echo 'unexpected fake harness URL' >&2"
    , "    exit 41"
    , "    ;;"
    , "esac"
    ]

-- | A fake node whose consumer opens its socket and then waits for the
-- interpreter to stop it: no delivery ever arrives.
idleConsumerScript :: Text
idleConsumerScript =
  shellScript
    [ "case \"$3\" in"
    , "  */consumer/*)"
    , emitFrame (Connected 1)
    , "    IFS= read -r idle || true"
    , "    ;;"
    , "  *)"
    , "    echo 'unexpected fake idle URL' >&2"
    , "    exit 41"
    , "    ;;"
    , "esac"
    ]

type HarnessResult =
  Either
    (LiveWorkflow.LiveRunFailure Text () Text Text)
    (LiveWorkflow.CompletedRunEvidence Text () Text Text)

-- | A request/reply protocol workflow over the real harness transport: the
-- first delivery is the completed evidence.
harnessProtocolWorkflow
  :: PulsarWebSocketSettings
  -> Topic WorkflowStatusMessage
  -> WorkflowStatusMessage
  -> Subscription WorkflowStatusMessage
  -> IO HarnessResult
harnessProtocolWorkflow settings topic event subscription = do
  planId <- harnessPlan
  handle <- expectHarnessRight (LiveWorkflow.mkRequestHandle planId "harness-request")
  LiveWorkflow.runLiveWorkflow
    ( harnessWorkflow
        planId
        (LiveWorkflow.ProtocolCommand topic event)
        (LiveWorkflow.pulsarEventSource subscription)
    )
    (livePulsarTransport settings)
    (harnessBackend (LiveWorkflow.RequestReply handle) LiveWorkflow.ResponseCompletesRequest)

harnessWorkflow
  :: PlanId
  -> LiveWorkflow.LiveCommand command
  -> LiveWorkflow.LiveEventSource command WorkflowStatusMessage
  -> LiveWorkflow.LiveWorkflow command WorkflowStatusMessage Bool () Text Text
harnessWorkflow planId command source =
  LiveWorkflow.LiveWorkflow
    { LiveWorkflow.liveWorkflowPlanId = planId
    , LiveWorkflow.liveWorkflowCommand = command
    , LiveWorkflow.liveWorkflowEventSource = source
    , LiveWorkflow.liveWorkflowInitialProgress = False
    , LiveWorkflow.liveWorkflowIngest = \_ _ -> Right True
    , LiveWorkflow.liveWorkflowFinish = \seen ->
        if seen then Success () else Failure "no evidence observed"
    , LiveWorkflow.liveWorkflowRenderViolation = id
    }

harnessBackend
  :: LiveWorkflow.Placement
  -> LiveWorkflow.LiveCompletionMode
  -> LiveWorkflow.LiveBackend Text
harnessBackend placement completionMode =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement = pure (Right placement)
    , LiveWorkflow.liveCompletionMode = completionMode
    , LiveWorkflow.liveObserveWorkload =
        const (pure (LiveWorkflow.Succeeded "unused-harness-terminal"))
    , LiveWorkflow.liveGatherDiagnostics =
        const (pure (Right [LiveWorkflow.LiveDiagnostic "harness diagnostics"]))
    , LiveWorkflow.liveReleasePlacement = const (pure [])
    , LiveWorkflow.liveObservationAttempts = 1
    , LiveWorkflow.liveObservationDelayMicros = 0
    , LiveWorkflow.liveWorkflowTimeoutMicros = fixtureTimeoutMicroseconds
    }

harnessPlan :: IO PlanId
harnessPlan =
  case planIdFromCanonicalText "pulsar-transport-harness-plan" of
    Success planId -> pure planId
    Failure errors -> assertFailure ("invalid harness fixture plan: " <> show errors)

expectHarnessRight :: (Show err) => Either err value -> IO value
expectHarnessRight result =
  case result of
    Right value -> pure value
    Left err -> assertFailure ("expected Right, got Left " <> show err)

expectHarnessCompleted
  :: HarnessResult
  -> IO (LiveWorkflow.CompletedRunEvidence Text () Text Text)
expectHarnessCompleted result =
  case result of
    Right completed -> pure completed
    Left failure -> assertFailure ("expected a completed harness workflow, got " <> show failure)

expectHarnessFailure
  :: HarnessResult
  -> IO (LiveWorkflow.LiveRunFailure Text () Text Text)
expectHarnessFailure result =
  case result of
    Left failure -> pure failure
    Right completed -> assertFailure ("expected a failed harness workflow, got " <> show completed)

fatalProtocolScript :: Text
fatalProtocolScript =
  shellScript
    [ emitFrame (Connected 1)
    , emitFrame (BridgeError ProtocolScope Nothing True "fatal protocol frame")
    , "printf '%s' 'fatal bridge' >&2"
    , "exit 23"
    ]

shellScript :: [Text] -> Text
shellScript body =
  Text.unlines (["#!/bin/sh", "set -eu"] <> body)

emitFrame :: ChildFrame -> Text
emitFrame frame =
  "printf '%s\\n' " <> shellQuote (stripNdjsonTerminator (encodeChildFrame frame))

stripNdjsonTerminator :: ByteString -> Text
stripNdjsonTerminator = Text.dropWhileEnd (== '\n') . Text.Encoding.decodeUtf8

shellQuote :: Text -> Text
shellQuote value =
  "'" <> Text.replace "'" "'\"'\"'" value <> "'"

readCommand :: Text -> Text -> Text
readCommand variable messageType =
  Text.unlines
    [ "IFS= read -r " <> variable
    , "case \"$"
        <> variable
        <> "\" in *'\"type\":\""
        <> messageType
        <> "\"'*) ;; *) echo 'wrong command' >&2; exit 31 ;; esac"
    ]

recordCommand :: FilePath -> Text -> Text
recordCommand path variable =
  "printf '%s\\n' \"$" <> variable <> "\" >> " <> shellQuote (Text.pack path)

requireCommandKind :: Text -> Text -> Text
requireCommandKind variable settlementKind =
  "case \"$"
    <> variable
    <> "\" in *'\"type\":\""
    <> settlementKind
    <> "\"'*) ;; *) echo 'wrong settlement' >&2; exit 32 ;; esac"

requireCommandReason :: Text -> Text -> Text
requireCommandReason variable reason =
  "case \"$"
    <> variable
    <> "\" in *'\"reason\":\""
    <> reason
    <> "\"'*) ;; *) echo 'wrong settlement reason' >&2; exit 33 ;; esac"

requireCommandReceipt :: Text -> Text -> Text
requireCommandReceipt variable deliveryId =
  "case \"$"
    <> variable
    <> "\" in *'\"deliveryId\":\""
    <> deliveryId
    <> "\"'*) ;; *) echo 'wrong settlement receipt' >&2; exit 34 ;; esac"

settlementKindText :: SettlementKind -> Text
settlementKindText AckKind = "ack"
settlementKindText NackKind = "nack"

receipt1 :: DeliveryReceipt
receipt1 = receipt "session-unit" 1 "delivery-1"

receipt2 :: DeliveryReceipt
receipt2 = receipt "session-unit" 1 "delivery-2"

unknownReceipt :: DeliveryReceipt
unknownReceipt = receipt "session-unit" 1 "unknown"

receipt :: Text -> Word -> Text -> DeliveryReceipt
receipt session generation deliveryId =
  DeliveryReceipt
    { receiptSessionInternal = session
    , receiptGenerationInternal = fromIntegral generation
    , receiptDeliveryIdInternal = deliveryId
    }

withBridgeDelivery :: (BridgeState -> Assertion) -> Assertion
withBridgeDelivery assertion =
  expectRight (applyChildFrame emptyBridgeState (Connected 1)) $ \connected ->
    expectRight (applyChildFrame connected (Delivery receipt1 "payload" 0)) assertion

expectRight :: (Show err) => Either err value -> (value -> Assertion) -> Assertion
expectRight result assertion =
  case result of
    Left err -> assertFailure ("expected Right, got Left " <> show err)
    Right value -> assertion value

countOccurrences :: Text -> Text -> Int
countOccurrences needle = length . Text.breakOnAll needle

assertContains :: String -> Text -> Text -> Assertion
assertContains label needle haystack =
  assertBool (label <> " missing from structured outcome") (needle `Text.isInfixOf` haystack)

testSettings :: PulsarWebSocketSettings
testSettings =
  PulsarWebSocketSettings
    { pulsarNodeBinary = "/usr/bin/false"
    , pulsarWebSocketEndpoint = "ws://unused.invalid/ws"
    , pulsarAdminEndpoint = "http://unused.invalid/admin/v2"
    }

validWorkflowPayload :: Text
validWorkflowPayload =
  Text.unlines
    [ "kind: WorkflowStatus"
    , "panel: workflow-status"
    , "run-id: transport-unit"
    , "status: done"
    , "detail: complete"
    ]

fixtureTimeoutMicroseconds :: Int
fixtureTimeoutMicroseconds = 5 * 1000 * 1000

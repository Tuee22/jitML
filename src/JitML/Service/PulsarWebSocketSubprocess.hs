{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.PulsarWebSocketSubprocess
  ( PulsarWebSocketSettings (..)
  , PulsarWebSocketSubprocess (..)
  , ReplyCursor
  , establishReplyCursor
  , publishWithReplyCursor
  , releaseReplyCursor
  , replyCursorSubscription
  , defaultPulsarWebSocketSettings
  , pulsarBatchConsumerBridgeScript
  , pulsarBatchConsumerSubprocess
  , pulsarConsumerBridgeScript
  , pulsarConsumerSubprocess
  , pulsarCreateSubscriptionSubprocess
  , pulsarDeleteSubscriptionSubprocess
  , pulsarProducerScript
  , pulsarPublishSubprocess
  , pulsarSettingsForEndpoint
  , pulsarSettingsForLocalEdge
  , runPulsarWebSocketSubprocess
  , subscriptionCleanupSubprocess
  )
where

import Control.Exception
  ( SomeAsyncException
  , SomeException
  , displayException
  , fromException
  , mask
  , throwIO
  , try
  , uninterruptibleMask_
  )
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..), ask, runReaderT)
import Data.ByteString (ByteString)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (UnicodeException)
import GHC.Clock (getMonotonicTimeNSec)
import System.Timeout (timeout)

import JitML.Coordinator.Topology
  ( Topic
  , TopicDecodeError (..)
  , decodeTopicPayload
  , encodeTopicPayload
  , topicName
  )
import JitML.Service.Capabilities (HasPulsar (..))
import JitML.Service.InferenceBatch
  ( BatchOffer (..)
  , BatchPolicy
  , OpenBatch
  , batchCollectionDeadlineNanoseconds
  , batchDeadlineNanoseconds
  , batchFlushReason
  , batchItems
  , batchWindow
  , offerBatch
  , openBatch
  )
import JitML.Service.Pulsar.Bridge
  ( BridgeErrorScope (..)
  , BridgeState
  , ChildFrame (..)
  , ParentCommand (..)
  , Settlement (..)
  , SettlementKind (..)
  , applyChildFrame
  , applyParentCommand
  , decodeChildFrame
  , emptyBridgeState
  , encodeParentCommand
  )
import JitML.Service.Pulsar.Internal
  ( ConsumerBatchDecision (..)
  , ConsumerDecision (..)
  , ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , Delivery
  , DeliveryBatch (..)
  , DeliveryReceipt
  , Disposition (..)
  , NackReason (..)
  , Subscription (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  )
import JitML.Service.Pulsar.Internal qualified as PulsarInternal
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , renderProcessOutcome
  )
import JitML.Sub.Piped
  ( PipedActionException (..)
  , PipedSession
  , PipedSessionError (..)
  , readPipedStdoutLine
  , runPipedProcess
  , writePipedStdin
  )
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess, subprocessWithStdin)

data PulsarWebSocketSettings = PulsarWebSocketSettings
  { pulsarNodeBinary :: FilePath
  , pulsarWebSocketEndpoint :: Text
  , pulsarAdminEndpoint :: Text
  }
  deriving stock (Eq, Show)

-- | Proof that the broker has created the exact @Owned@, @FromLatest@
-- subscription which receives a correlated command's reply.  The constructor
-- is intentionally hidden: only an acknowledged admin CREATE below can mint
-- the token, and the correlated publisher reads both topics from the token.
data ReplyCursor command result = ReplyCursor
  { replyCursorRequestTopicInternal :: Topic command
  , replyCursorOwnedSubscriptionInternal :: Subscription result
  }

defaultPulsarWebSocketSettings :: PulsarWebSocketSettings
defaultPulsarWebSocketSettings =
  pulsarSettingsForLocalEdge 9090

pulsarSettingsForLocalEdge :: Int -> PulsarWebSocketSettings
pulsarSettingsForLocalEdge edgePort =
  pulsarSettingsForEndpoint
    ("pulsar://127.0.0.1:" <> Text.pack (show edgePort) <> "/pulsar")

pulsarSettingsForEndpoint :: Text -> PulsarWebSocketSettings
pulsarSettingsForEndpoint endpoint =
  PulsarWebSocketSettings
    { pulsarNodeBinary = "node"
    , pulsarWebSocketEndpoint = websocketEndpointFromServiceUrl endpoint
    , pulsarAdminEndpoint = adminEndpointFromServiceUrl endpoint
    }

newtype PulsarWebSocketSubprocess a = PulsarWebSocketSubprocess
  { unPulsarWebSocketSubprocess :: ReaderT PulsarWebSocketSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader PulsarWebSocketSettings
    )

runPulsarWebSocketSubprocess :: PulsarWebSocketSettings -> PulsarWebSocketSubprocess a -> IO a
runPulsarWebSocketSubprocess settings action =
  runReaderT (unPulsarWebSocketSubprocess action) settings

instance HasPulsar PulsarWebSocketSubprocess where
  pulsarPublish topic event = do
    settings <- ask
    outcomeResult <-
      liftIO
        ( tryProcessOutcome
            (runStreaming defaultSubprocessEnv (pulsarPublishSubprocess settings topic event))
        )
    pure $ do
      outcome <- outcomeResult
      case outcome of
        ProcessFailed _failure ->
          Left (SETransient ("pulsar publish failed:\n" <> renderProcessOutcome outcome))
        ProcessSucceeded transcript ->
          let acknowledgement = Text.strip (processTranscriptStdout transcript)
           in if Text.null acknowledgement
                then
                  Left
                    ( SETransient
                        ("pulsar publish returned no acknowledgement:\n" <> renderProcessOutcome outcome)
                    )
                else Right acknowledgement

  pulsarConsumeUntil subscription observe handler = do
    settings <- ask
    liftIO
      ( consumePersistent
          settings
          subscription
          (runPulsarWebSocketSubprocess settings . observe)
          (runPulsarWebSocketSubprocess settings . handler)
      )

  pulsarConsumeBatchesUntil readPolicy compatibilityKey subscription observe handler = do
    settings <- ask
    liftIO
      ( consumePersistentBatches
          settings
          subscription
          (runPulsarWebSocketSubprocess settings readPolicy)
          compatibilityKey
          (runPulsarWebSocketSubprocess settings . observe)
          (runPulsarWebSocketSubprocess settings . handler)
      )

pulsarPublishSubprocess
  :: PulsarWebSocketSettings
  -> Topic event
  -> event
  -> Subprocess
pulsarPublishSubprocess settings topic event =
  subprocessWithStdin
    (pulsarNodeBinary settings)
    [ "--eval"
    , pulsarProducerScript
    , producerUrl settings topic
    ]
    (encodeTopicPayload topic event)

-- | Establish an owned, from-latest reply subscription through the broker's
-- admin API.  HTTP 409 is success: an already-existing subscription still
-- proves that the cursor exists.  No token is returned for any other failure,
-- so the correlated publish cannot be attempted.
establishReplyCursor
  :: PulsarWebSocketSettings
  -> Topic command
  -> Subscription result
  -> IO (Either ServiceError (ReplyCursor command result))
establishReplyCursor settings requestTopic subscription
  | subscriptionStartInternal subscription /= FromLatest =
      pure (Left (SEConflict "reply cursor subscription must start FromLatest"))
  | subscriptionOwnershipInternal subscription /= Owned =
      pure (Left (SEConflict "reply cursor subscription must be Owned"))
  | otherwise = do
      outcomeResult <-
        tryProcessOutcome
          ( runStreaming
              defaultSubprocessEnv
              (pulsarCreateSubscriptionSubprocess settings subscription)
          )
      pure $ do
        outcome <- outcomeResult
        case outcome of
          ProcessFailed _failure ->
            Left
              ( SETransient
                  ("reply cursor creation failed:\n" <> renderProcessOutcome outcome)
              )
          ProcessSucceeded transcript
            | createHttpStatusIsSuccess (Text.strip (processTranscriptStdout transcript)) ->
                Right (ReplyCursor requestTopic subscription)
            | otherwise ->
                Left
                  ( SETransient
                      ( "reply cursor creation returned an unexpected HTTP status:\n"
                          <> renderProcessOutcome outcome
                      )
                  )

-- | Publish a command which names the exact result topic protected by this
-- cursor.  Callers cannot provide either topic independently.
publishWithReplyCursor
  :: PulsarWebSocketSettings
  -> ReplyCursor command result
  -> (Text -> command)
  -> IO (Either ServiceError Text)
publishWithReplyCursor settings cursor buildCommand =
  runPulsarWebSocketSubprocess settings $
    pulsarPublish
      (replyCursorRequestTopicInternal cursor)
      ( buildCommand
          ( topicName
              (subscriptionTopicInternal (replyCursorOwnedSubscriptionInternal cursor))
          )
      )

-- | Consumer view of an established cursor.  Cleanup remains with the cursor
-- owner below, so cancellation before the consumer thread starts cannot leak
-- the admin-created subscription.
replyCursorSubscription :: ReplyCursor command result -> Subscription result
replyCursorSubscription cursor =
  (replyCursorOwnedSubscriptionInternal cursor)
    { subscriptionOwnershipInternal = Borrowed
    }

-- | Release the owned cursor on every scope exit.  The bounded DELETE is the
-- same cancellation-safe cleanup used by ordinary owned consumers.
releaseReplyCursor
  :: PulsarWebSocketSettings
  -> ReplyCursor command result
  -> IO (Either ConsumerFailure ())
releaseReplyCursor settings =
  cleanupSubscription settings . replyCursorOwnedSubscriptionInternal

pulsarConsumerSubprocess
  :: PulsarWebSocketSettings
  -> Subscription event
  -> Subprocess
pulsarConsumerSubprocess settings subscription =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , pulsarConsumerBridgeScript
    , consumerUrl settings subscription
    ]

pulsarBatchConsumerSubprocess
  :: PulsarWebSocketSettings
  -> Subscription event
  -> Subprocess
pulsarBatchConsumerSubprocess settings subscription =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , pulsarBatchConsumerBridgeScript
    , consumerUrl settings subscription
    ]

pulsarCreateSubscriptionSubprocess
  :: PulsarWebSocketSettings
  -> Subscription event
  -> Subprocess
pulsarCreateSubscriptionSubprocess settings subscription =
  subprocessWithStdin
    "curl"
    [ "--silent"
    , "--show-error"
    , "--location"
    , "--max-redirs"
    , "5"
    , "--proto-redir"
    , "=http,https"
    , "--connect-timeout"
    , "10"
    , "--max-time"
    , "30"
    , "--output"
    , "/dev/null"
    , "--write-out"
    , "%{http_code}"
    , "--header"
    , "Content-Type: application/json"
    , "--request"
    , "PUT"
    , "--data-binary"
    , "@-"
    , subscriptionAdminResourceUrl settings subscription
    ]
    latestMessageIdJson

pulsarDeleteSubscriptionSubprocess
  :: PulsarWebSocketSettings
  -> Subscription event
  -> Subprocess
pulsarDeleteSubscriptionSubprocess settings subscription =
  subprocess
    "curl"
    [ "--silent"
    , "--show-error"
    , "--location"
    , "--max-redirs"
    , "5"
    , "--proto-redir"
    , "=http,https"
    , "--connect-timeout"
    , "10"
    , "--max-time"
    , "30"
    , "--output"
    , "/dev/null"
    , "--write-out"
    , "%{http_code}"
    , "--request"
    , "DELETE"
    , subscriptionAdminResourceUrl settings subscription <> "?force=true"
    ]

subscriptionCleanupSubprocess
  :: PulsarWebSocketSettings
  -> Subscription event
  -> Maybe Subprocess
subscriptionCleanupSubprocess settings subscription =
  case subscriptionOwnershipInternal subscription of
    Borrowed -> Nothing
    Owned -> Just (pulsarDeleteSubscriptionSubprocess settings subscription)

data ConsumeActionResult result
  = ConsumeCompleted result
  | ConsumeCancelled SomeAsyncException
  | ConsumeFailed ConsumerFailure
  | ConsumeExitedBeforeDrain

data ConsumeProcessResult result
  = ConsumeProcessFinished (Either ConsumerFailure result)
  | ConsumeProcessCancelled SomeAsyncException

consumePersistent
  :: PulsarWebSocketSettings
  -> Subscription event
  -> (ConsumerSessionEvent -> IO ())
  -> (Delivery event -> IO (ConsumerDecision result))
  -> IO (Either ConsumerFailure result)
consumePersistent settings subscription observe handler = do
  retainedFailure <- newIORef Nothing
  preserveLateFailure retainedFailure $ mask $ \restore -> do
    processResult <-
      tryAny
        ( restore
            ( runPipedProcess
                (pulsarConsumerSubprocess settings subscription)
                ( \session ->
                    consumeFrames
                      (subscriptionTopicInternal subscription)
                      observe
                      handler
                      session
                      emptyBridgeState
                )
            )
        )
    let consumed = finalizeProcessResult processResult
    cleanupResult <- cleanupSubscription settings subscription
    finalResult <- finalizeConsumeCleanup consumed cleanupResult
    retainFailure retainedFailure finalResult

data DeferredBatchDelivery event
  = DeferredDecoded (Delivery event)
  | DeferredDecodeFailure DeliveryReceipt TopicDecodeError

data BatchTransportState event = BatchTransportState
  { batchBridgeState :: BridgeState
  , batchConnected :: Bool
  , batchPermitOutstanding :: Bool
  , batchDeferredDeliveries :: [DeferredBatchDelivery event]
  }

data AwaitBatchDelivery event
  = BatchDeliveryArrived (BatchTransportState event) (DeferredBatchDelivery event)
  | BatchDeliveryDeadline (BatchTransportState event)
  | BatchDeliveryFailed ConsumerFailure
  | BatchDeliveryExited

data TimedBridgeFrame
  = TimedBridgeDeadline
  | TimedBridgeResult (Either ConsumerFailure (Maybe ChildFrame))

consumePersistentBatches
  :: (Eq key)
  => PulsarWebSocketSettings
  -> Subscription event
  -> IO BatchPolicy
  -> (event -> key)
  -> (ConsumerSessionEvent -> IO ())
  -> (DeliveryBatch event -> IO (ConsumerBatchDecision result))
  -> IO (Either ConsumerFailure result)
consumePersistentBatches settings subscription readPolicy compatibilityKey observe handler = do
  retainedFailure <- newIORef Nothing
  preserveLateFailure retainedFailure $ mask $ \restore -> do
    processResult <-
      tryAny
        ( restore
            ( runPipedProcess
                (pulsarBatchConsumerSubprocess settings subscription)
                ( \session ->
                    consumeBatchLoop
                      (subscriptionTopicInternal subscription)
                      readPolicy
                      compatibilityKey
                      observe
                      handler
                      session
                      BatchTransportState
                        { batchBridgeState = emptyBridgeState
                        , batchConnected = False
                        , batchPermitOutstanding = False
                        , batchDeferredDeliveries = []
                        }
                )
            )
        )
    let consumed = finalizeProcessResult processResult
    cleanupResult <- cleanupSubscription settings subscription
    finalResult <- finalizeConsumeCleanup consumed cleanupResult
    retainFailure retainedFailure finalResult

finalizeProcessResult
  :: Either SomeException (ConsumeActionResult result, ProcessOutcome)
  -> ConsumeProcessResult result
finalizeProcessResult processResult =
  case processResult of
    Left exception
      | Just asyncException <- fromException exception ->
          ConsumeProcessCancelled asyncException
      | otherwise ->
          ConsumeProcessFinished (Left (pipedProcessExceptionFailure exception))
    Right (actionResult, outcome) -> finalizeConsume actionResult outcome

finalizeConsumeCleanup
  :: ConsumeProcessResult result
  -> Either ConsumerFailure ()
  -> IO (Either ConsumerFailure result)
finalizeConsumeCleanup processResult cleanupResult =
  case processResult of
    ConsumeProcessCancelled asyncException ->
      case cleanupResult of
        -- Controlled cancellation is observable by the owner only when
        -- owned-subscription cleanup fails. Returning that typed failure lets
        -- the cancelling scope retain it; successful cleanup keeps the original
        -- async-exception identity.
        Left cleanupFailure -> pure (Left cleanupFailure)
        Right () -> throwIO asyncException
    ConsumeProcessFinished consumed ->
      pure (combineConsumeCleanup consumed cleanupResult)

combineConsumeCleanup
  :: Either ConsumerFailure result
  -> Either ConsumerFailure ()
  -> Either ConsumerFailure result
combineConsumeCleanup consumed cleanupResult =
  case (consumed, cleanupResult) of
    (Left primaryFailure, Left (ConsumerCleanupFailure cleanupError)) ->
      Left (ConsumerCleanupContextFailure primaryFailure cleanupError)
    (Left primaryFailure, Left cleanupFailure) ->
      Left
        ( ConsumerCleanupContextFailure
            primaryFailure
            (SETransient (Text.pack (show cleanupFailure)))
        )
    (Right _result, Left cleanupFailure) -> Left cleanupFailure
    (consumedResult, Right ()) -> consumedResult

-- | A cancellation that arrives while the bounded, uninterruptible DELETE is
-- running is delivered when the outer mask restores. Retain any typed failure
-- already finalized before that boundary; only an otherwise successful
-- consumer rethrows the deferred cancellation.
preserveLateFailure
  :: IORef (Maybe ConsumerFailure)
  -> IO (Either ConsumerFailure result)
  -> IO (Either ConsumerFailure result)
preserveLateFailure retainedFailure action = do
  attempt <- tryAny action
  case attempt of
    Right result -> pure result
    Left exception
      | Just asyncException <- fromException exception -> do
          retained <- readIORef retainedFailure
          case retained of
            Just failure -> pure (Left failure)
            Nothing -> throwIO (asyncException :: SomeAsyncException)
      | otherwise -> throwIO exception

retainFailure
  :: IORef (Maybe ConsumerFailure)
  -> Either ConsumerFailure result
  -> IO (Either ConsumerFailure result)
retainFailure retainedFailure result = do
  case result of
    Left failure -> writeIORef retainedFailure (Just failure)
    _ -> pure ()
  pure result

consumeBatchLoop
  :: (Eq key)
  => Topic event
  -> IO BatchPolicy
  -> (event -> key)
  -> (ConsumerSessionEvent -> IO ())
  -> (DeliveryBatch event -> IO (ConsumerBatchDecision result))
  -> PipedSession
  -> BatchTransportState event
  -> IO (ConsumeActionResult result)
consumeBatchLoop topic readPolicy compatibilityKey observe handler session transport =
  case batchDeferredDeliveries transport of
    deferred : remaining ->
      admitDeferred
        transport {batchDeferredDeliveries = remaining}
        deferred
    [] -> do
      awaited <- awaitBatchDelivery topic observe session Nothing transport
      case awaited of
        BatchDeliveryArrived nextTransport deferred -> admitDeferred nextTransport deferred
        BatchDeliveryDeadline _nextTransport ->
          pure
            ( ConsumeFailed
                (ConsumerProtocolFailure "unbounded batch admission reached a deadline")
            )
        BatchDeliveryFailed failure -> pure (ConsumeFailed failure)
        BatchDeliveryExited -> pure ConsumeExitedBeforeDrain
 where
  admitDeferred nextTransport deferred =
    case deferred of
      DeferredDecodeFailure receipt decodeFailure ->
        settleBatchTerminal
          topic
          observe
          session
          nextTransport
          (receipt :| [])
          (NackInternal (DecodeRejected (Text.pack (show decodeFailure))))
          (ConsumeFailed (ConsumerDecodeFailure decodeFailure))
      DeferredDecoded delivery -> do
        admittedAt <- getMonotonicTimeNSec
        policyResult <- tryAny readPolicy
        case policyResult of
          Left exception
            | Just asyncException <- fromException exception ->
                settleBatchTerminal
                  topic
                  observe
                  session
                  nextTransport
                  (PulsarInternal.deliveryReceiptInternal delivery :| [])
                  (NackInternal DrainRequested)
                  (ConsumeCancelled asyncException)
            | otherwise ->
                settleBatchTerminal
                  topic
                  observe
                  session
                  nextTransport
                  (PulsarInternal.deliveryReceiptInternal delivery :| [])
                  (NackInternal (HandlerRejected (exceptionText exception)))
                  ( ConsumeFailed
                      (ConsumerHandlerFailure ("batch policy reader threw: " <> exceptionText exception))
                  )
          Right policy ->
            collectOpenBatch
              topic
              readPolicy
              compatibilityKey
              observe
              handler
              session
              nextTransport
              ( openBatch
                  admittedAt
                  policy
                  (compatibilityKey (PulsarInternal.deliveryEventInternal delivery))
                  delivery
              )

collectOpenBatch
  :: (Eq key)
  => Topic event
  -> IO BatchPolicy
  -> (event -> key)
  -> (ConsumerSessionEvent -> IO ())
  -> (DeliveryBatch event -> IO (ConsumerBatchDecision result))
  -> PipedSession
  -> BatchTransportState event
  -> OpenBatch key (Delivery event)
  -> IO (ConsumeActionResult result)
collectOpenBatch topic readPolicy compatibilityKey observe handler session transport batch = do
  now <- getMonotonicTimeNSec
  case batchFlushReason now batch of
    Just _reason -> handleOpenBatch
    Nothing -> do
      awaited <-
        awaitBatchDelivery
          topic
          observe
          session
          (Just (batchCollectionDeadlineNanoseconds batch))
          transport
      case awaited of
        BatchDeliveryDeadline nextTransport ->
          handleOpenBatchWith nextTransport batch
        BatchDeliveryFailed failure -> pure (ConsumeFailed failure)
        BatchDeliveryExited -> pure ConsumeExitedBeforeDrain
        BatchDeliveryArrived nextTransport deferred ->
          case deferred of
            DeferredDecodeFailure receipt decodeFailure ->
              settleBatchTerminal
                topic
                observe
                session
                nextTransport
                (fmap PulsarInternal.deliveryReceiptInternal (batchItems batch) <> (receipt :| []))
                (NackInternal (DecodeRejected (Text.pack (show decodeFailure))))
                (ConsumeFailed (ConsumerDecodeFailure decodeFailure))
            DeferredDecoded delivery -> do
              offeredAt <- getMonotonicTimeNSec
              case offerBatch
                offeredAt
                (compatibilityKey (PulsarInternal.deliveryEventInternal delivery))
                delivery
                batch of
                BatchKept expanded ->
                  collectOpenBatch
                    topic
                    readPolicy
                    compatibilityKey
                    observe
                    handler
                    session
                    nextTransport
                    expanded
                BatchReady _reason ready carry ->
                  let carriedTransport =
                        case carry of
                          Nothing -> nextTransport
                          Just (_key, carriedDelivery) ->
                            nextTransport
                              { batchDeferredDeliveries =
                                  batchDeferredDeliveries nextTransport
                                    <> [DeferredDecoded carriedDelivery]
                              }
                   in handleOpenBatchWith carriedTransport ready
 where
  handleOpenBatch = handleOpenBatchWith transport batch

  handleOpenBatchWith nextTransport ready = do
    beforeHandler <- getMonotonicTimeNSec
    let remainingNanoseconds =
          batchDeadlineNanoseconds ready - toInteger beforeHandler
    handlerResult <-
      if remainingNanoseconds <= 0
        then pure (Right Nothing)
        else
          tryAny
            ( timeout
                (boundedMicroseconds remainingNanoseconds)
                (handler (DeliveryBatch (batchWindow ready) (batchItems ready)))
            )
    case handlerResult of
      Left exception
        | Just asyncException <- fromException exception ->
            settleBatchTerminal
              topic
              observe
              session
              nextTransport
              (fmap PulsarInternal.deliveryReceiptInternal (batchItems ready))
              (NackInternal DrainRequested)
              (ConsumeCancelled asyncException)
        | otherwise ->
            let message = "batch handler threw: " <> exceptionText exception
             in settleBatchTerminal
                  topic
                  observe
                  session
                  nextTransport
                  (fmap PulsarInternal.deliveryReceiptInternal (batchItems ready))
                  (NackInternal (HandlerRejected message))
                  (ConsumeFailed (ConsumerHandlerFailure message))
      Right Nothing -> rejectSloExpiredBatch nextTransport ready
      Right (Just decision) ->
        -- The timeout above owns the execution fence. A returned success may
        -- already include an externally visible publication, so retroactively
        -- converting it to a Nack would redeliver committed work.
        case decision of
          ContinueBatchInternal disposition -> do
            settled <-
              settleBatchReceipts
                topic
                observe
                session
                nextTransport
                (fmap PulsarInternal.deliveryReceiptInternal (batchItems ready))
                disposition
                False
            case settled of
              Left failure -> pure (ConsumeFailed failure)
              Right settledTransport ->
                consumeBatchLoop
                  topic
                  readPolicy
                  compatibilityKey
                  observe
                  handler
                  session
                  settledTransport
          DoneBatchInternal disposition result ->
            settleBatchTerminal
              topic
              observe
              session
              nextTransport
              (fmap PulsarInternal.deliveryReceiptInternal (batchItems ready))
              disposition
              (ConsumeCompleted result)

  rejectSloExpiredBatch nextTransport ready = do
    settled <-
      settleBatchReceipts
        topic
        observe
        session
        nextTransport
        (fmap PulsarInternal.deliveryReceiptInternal (batchItems ready))
        (NackInternal (RetryRequested "inference batch latency SLO expired"))
        False
    case settled of
      Left failure -> pure (ConsumeFailed failure)
      Right settledTransport ->
        consumeBatchLoop
          topic
          readPolicy
          compatibilityKey
          observe
          handler
          session
          settledTransport

settleBatchTerminal
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BatchTransportState event
  -> NonEmpty DeliveryReceipt
  -> Disposition
  -> ConsumeActionResult result
  -> IO (ConsumeActionResult result)
settleBatchTerminal topic observe session transport receipts disposition terminalResult = do
  settled <-
    settleBatchReceipts
      topic
      observe
      session
      transport
      receipts
      disposition
      True
  case settled of
    Left failure -> pure (ConsumeFailed failure)
    Right settledTransport ->
      awaitBatchDrained topic observe session settledTransport terminalResult

settleBatchReceipts
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BatchTransportState event
  -> NonEmpty DeliveryReceipt
  -> Disposition
  -> Bool
  -> IO (Either ConsumerFailure (BatchTransportState event))
settleBatchReceipts topic observe session transport receipts disposition terminal =
  case prepareCommands of
    Left stateError -> pure (Left (settlementStateFailure stateError))
    Right (requestedState, preparedCommands) -> do
      observerResult <-
        if terminal
          then notifyObserver observe ConsumerSessionDraining
          else pure (Right ())
      case observerResult of
        Left failure -> pure (Left failure)
        Right () -> do
          writeResult <- writePipedStdin session (foldMap encodeParentCommand preparedCommands)
          case writeResult of
            Left PipedStdinClosed ->
              pure
                ( Left
                    ( ConsumerSettlementFailure
                        "bridge stdin closed before batch settlement"
                        (SETransient "bridge stdin is closed")
                    )
                )
            Left (PipedWriteFailed detail) ->
              pure
                ( Left
                    ( ConsumerSettlementFailure
                        "bridge pipe write failed before batch settlement"
                        (SETransient detail)
                    )
                )
            Right () ->
              awaitBatchSettlements
                topic
                observe
                session
                transport {batchBridgeState = requestedState}
                terminal
                (fmap (,expectedKind) (NonEmpty.toList receipts))
 where
  settlement = dispositionSettlement disposition
  expectedKind =
    case settlement of
      Ack -> AckKind
      Nack _reason -> NackKind
  settlementCommands = fmap (`Settle` settlement) (NonEmpty.toList receipts)
  allCommands = settlementCommands <> [Drain | terminal]
  prepareCommands = do
    settlementState <-
      foldl'
        (\state command -> state >>= (`applyParentCommand` command))
        (Right (batchBridgeState transport))
        settlementCommands
    finalState <-
      if terminal
        then applyParentCommand settlementState Drain
        else Right settlementState
    pure (finalState, allCommands)

awaitBatchSettlements
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BatchTransportState event
  -> Bool
  -> [(DeliveryReceipt, SettlementKind)]
  -> IO (Either ConsumerFailure (BatchTransportState event))
awaitBatchSettlements _topic _observe _session transport _terminal [] = pure (Right transport)
awaitBatchSettlements topic observe session transport terminal expectedSettlements = do
  frameResult <- readBridgeFrame session
  case frameResult of
    Left failure -> pure (Left failure)
    Right Nothing ->
      pure
        ( Left
            ( ConsumerSettlementFailure
                "bridge exited before all batch settlements were confirmed"
                (SETransient "unexpected end of bridge stdout")
            )
        )
    Right (Just frame) ->
      case applyChildFrame (batchBridgeState transport) frame of
        Left stateError -> pure (Left (settlementStateFailure stateError))
        Right nextBridgeState ->
          let nextTransport = transport {batchBridgeState = nextBridgeState}
           in case frame of
                Connected generation -> do
                  observerResult <- notifyObserver observe (ConsumerSessionConnected generation)
                  case observerResult of
                    Left failure -> pure (Left failure)
                    Right () ->
                      awaitBatchSettlements
                        topic
                        observe
                        session
                        nextTransport
                          { batchConnected = True
                          , batchPermitOutstanding = False
                          }
                        terminal
                        expectedSettlements
                BridgeError ConnectionScope _receipt False message -> do
                  observerResult <- notifyObserver observe (ConsumerSessionDisconnected message)
                  case observerResult of
                    Left failure -> pure (Left failure)
                    Right () ->
                      awaitBatchSettlements
                        topic
                        observe
                        session
                        nextTransport
                          { batchConnected = False
                          , batchPermitOutstanding = False
                          }
                        terminal
                        expectedSettlements
                BridgeError scope _receipt _fatal message ->
                  pure (Left (bridgeSettlementFailure scope message))
                Settled receipt actualKind ->
                  case lookup receipt expectedSettlements of
                    Nothing ->
                      pure
                        ( Left
                            ( ConsumerSettlementFailure
                                "bridge confirmed a receipt outside the active batch"
                                (SETransient "unexpected batch receipt confirmation")
                            )
                        )
                    Just expectedKind
                      | expectedKind /= actualKind ->
                          pure
                            ( Left
                                ( ConsumerSettlementFailure
                                    "bridge confirmed the opposite batch settlement"
                                    (SETransient "batch settlement kind did not match")
                                )
                            )
                      | otherwise ->
                          awaitBatchSettlements
                            topic
                            observe
                            session
                            nextTransport
                            terminal
                            (filter ((/= receipt) . fst) expectedSettlements)
                Delivery receipt payload redeliveryCount
                  | terminal ->
                      settleLateDrainDelivery
                        nextTransport {batchPermitOutstanding = False}
                        receipt
                  | otherwise ->
                      let deferred =
                            case decodeDelivery topic payload of
                              Left decodeFailure -> DeferredDecodeFailure receipt decodeFailure
                              Right event ->
                                DeferredDecoded
                                  PulsarInternal.Delivery
                                    { deliveryEventInternal = event
                                    , deliveryReceiptInternal = receipt
                                    , deliveryRedeliveryCountInternal = redeliveryCount
                                    }
                       in awaitBatchSettlements
                            topic
                            observe
                            session
                            nextTransport
                              { batchPermitOutstanding = False
                              , batchDeferredDeliveries =
                                  batchDeferredDeliveries nextTransport <> [deferred]
                              }
                            terminal
                            expectedSettlements
                Drained ->
                  pure
                    ( Left
                        ( ConsumerSettlementFailure
                            "bridge drained before all batch settlements were confirmed"
                            (SETransient "batch settlement was not confirmed")
                        )
                    )
 where
  settleLateDrainDelivery nextTransport receipt =
    let settlement = Nack "drain-requested"
        command = Settle receipt settlement
     in case applyParentCommand (batchBridgeState nextTransport) command of
          Left stateError -> pure (Left (settlementStateFailure stateError))
          Right requestedState -> do
            writeResult <- writePipedStdin session (encodeParentCommand command)
            case writeResult of
              Left PipedStdinClosed ->
                pure
                  ( Left
                      ( ConsumerSettlementFailure
                          "bridge stdin closed before raced drain settlement"
                          (SETransient "bridge stdin is closed")
                      )
                  )
              Left (PipedWriteFailed detail) ->
                pure
                  ( Left
                      ( ConsumerSettlementFailure
                          "bridge pipe write failed before raced drain settlement"
                          (SETransient detail)
                      )
                  )
              Right () ->
                awaitBatchSettlements
                  topic
                  observe
                  session
                  nextTransport {batchBridgeState = requestedState}
                  terminal
                  (expectedSettlements <> [(receipt, NackKind)])

awaitBatchDrained
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BatchTransportState event
  -> ConsumeActionResult result
  -> IO (ConsumeActionResult result)
awaitBatchDrained topic observe session transport terminalResult = do
  frameResult <- readBridgeFrame session
  case frameResult of
    Left failure -> pure (ConsumeFailed failure)
    Right Nothing -> pure ConsumeExitedBeforeDrain
    Right (Just frame) ->
      case applyChildFrame (batchBridgeState transport) frame of
        Left stateError -> pure (protocolStateFailure stateError)
        Right nextBridgeState ->
          let nextTransport = transport {batchBridgeState = nextBridgeState}
           in case frame of
                Connected generation -> do
                  observerResult <- notifyObserver observe (ConsumerSessionConnected generation)
                  case observerResult of
                    Left failure -> pure (ConsumeFailed failure)
                    Right () ->
                      awaitBatchDrained
                        topic
                        observe
                        session
                        nextTransport {batchConnected = True, batchPermitOutstanding = False}
                        terminalResult
                BridgeError ConnectionScope _receipt False message -> do
                  observerResult <- notifyObserver observe (ConsumerSessionDisconnected message)
                  case observerResult of
                    Left failure -> pure (ConsumeFailed failure)
                    Right () ->
                      awaitBatchDrained
                        topic
                        observe
                        session
                        nextTransport {batchConnected = False, batchPermitOutstanding = False}
                        terminalResult
                BridgeError scope _receipt _fatal message ->
                  pure
                    ( ConsumeFailed
                        ( ConsumerProtocolFailure
                            ("batch bridge failed while draining in " <> renderBridgeScope scope <> ": " <> message)
                        )
                    )
                Drained -> do
                  observerResult <- notifyObserver observe ConsumerSessionDrained
                  case observerResult of
                    Left failure -> pure (ConsumeFailed failure)
                    Right () -> pure terminalResult
                Delivery receipt _payload _redeliveryCount ->
                  settleRacedDelivery nextTransport receipt
                Settled _receipt _kind ->
                  pure
                    ( ConsumeFailed
                        (ConsumerProtocolFailure "batch bridge repeated settlement while draining")
                    )
 where
  settleRacedDelivery nextTransport receipt =
    let command = Settle receipt (Nack "drain-requested")
     in case applyParentCommand (batchBridgeState nextTransport) command of
          Left stateError -> pure (ConsumeFailed (settlementStateFailure stateError))
          Right requestedState -> do
            writeResult <- writePipedStdin session (encodeParentCommand command)
            case writeResult of
              Left PipedStdinClosed ->
                pure
                  ( ConsumeFailed
                      ( ConsumerSettlementFailure
                          "bridge stdin closed before raced drain settlement"
                          (SETransient "bridge stdin is closed")
                      )
                  )
              Left (PipedWriteFailed detail) ->
                pure
                  ( ConsumeFailed
                      ( ConsumerSettlementFailure
                          "bridge pipe write failed before raced drain settlement"
                          (SETransient detail)
                      )
                  )
              Right () -> do
                settled <-
                  awaitBatchSettlements
                    topic
                    observe
                    session
                    nextTransport
                      { batchBridgeState = requestedState
                      , batchPermitOutstanding = False
                      }
                    True
                    [(receipt, NackKind)]
                case settled of
                  Left failure -> pure (ConsumeFailed failure)
                  Right settledTransport ->
                    awaitBatchDrained topic observe session settledTransport terminalResult

awaitBatchDelivery
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> Maybe Integer
  -> BatchTransportState event
  -> IO (AwaitBatchDelivery event)
awaitBatchDelivery topic observe session maybeDeadline transport = do
  permitted <- ensureBatchPermit session transport
  case permitted of
    Left failure -> pure (BatchDeliveryFailed failure)
    Right permittedTransport -> do
      timedFrame <- readBridgeFrameUntil session maybeDeadline
      case timedFrame of
        TimedBridgeDeadline -> pure (BatchDeliveryDeadline permittedTransport)
        TimedBridgeResult (Left failure) -> pure (BatchDeliveryFailed failure)
        TimedBridgeResult (Right Nothing) -> pure BatchDeliveryExited
        TimedBridgeResult (Right (Just frame)) ->
          case applyChildFrame (batchBridgeState permittedTransport) frame of
            Left stateError -> pure (BatchDeliveryFailed (settlementStateFailure stateError))
            Right nextBridgeState ->
              let nextTransport = permittedTransport {batchBridgeState = nextBridgeState}
               in case frame of
                    Connected generation -> do
                      observerResult <- notifyObserver observe (ConsumerSessionConnected generation)
                      case observerResult of
                        Left failure -> pure (BatchDeliveryFailed failure)
                        Right () ->
                          awaitBatchDelivery
                            topic
                            observe
                            session
                            maybeDeadline
                            nextTransport
                              { batchConnected = True
                              , batchPermitOutstanding = False
                              }
                    BridgeError ConnectionScope _receipt False message -> do
                      observerResult <- notifyObserver observe (ConsumerSessionDisconnected message)
                      case observerResult of
                        Left failure -> pure (BatchDeliveryFailed failure)
                        Right () ->
                          awaitBatchDelivery
                            topic
                            observe
                            session
                            maybeDeadline
                            nextTransport
                              { batchConnected = False
                              , batchPermitOutstanding = False
                              }
                    BridgeError scope _receipt _fatal message ->
                      pure
                        ( BatchDeliveryFailed
                            ( ConsumerProtocolFailure
                                ("batch bridge error in " <> renderBridgeScope scope <> ": " <> message)
                            )
                        )
                    Delivery receipt payload redeliveryCount ->
                      let deferred =
                            case decodeDelivery topic payload of
                              Left decodeFailure -> DeferredDecodeFailure receipt decodeFailure
                              Right event ->
                                DeferredDecoded
                                  PulsarInternal.Delivery
                                    { deliveryEventInternal = event
                                    , deliveryReceiptInternal = receipt
                                    , deliveryRedeliveryCountInternal = redeliveryCount
                                    }
                       in pure
                            ( BatchDeliveryArrived
                                nextTransport {batchPermitOutstanding = False}
                                deferred
                            )
                    Settled _receipt _kind ->
                      pure
                        ( BatchDeliveryFailed
                            (ConsumerProtocolFailure "batch bridge emitted an unrequested settlement")
                        )
                    Drained ->
                      pure
                        ( BatchDeliveryFailed
                            (ConsumerProtocolFailure "batch bridge drained before the parent requested drain")
                        )

ensureBatchPermit
  :: PipedSession
  -> BatchTransportState event
  -> IO (Either ConsumerFailure (BatchTransportState event))
ensureBatchPermit session transport
  | not (batchConnected transport) = pure (Right transport)
  | batchPermitOutstanding transport = pure (Right transport)
  | otherwise =
      case applyParentCommand (batchBridgeState transport) (Permit 1) of
        Left stateError -> pure (Left (settlementStateFailure stateError))
        Right permittedState -> do
          writeResult <- writePipedStdin session (encodeParentCommand (Permit 1))
          pure $
            case writeResult of
              Left PipedStdinClosed ->
                Left (ConsumerPermitFailure (SETransient "batch bridge stdin is closed"))
              Left (PipedWriteFailed detail) ->
                Left (ConsumerPermitFailure (SETransient detail))
              Right () ->
                Right
                  transport
                    { batchBridgeState = permittedState
                    , batchPermitOutstanding = True
                    }

readBridgeFrameUntil
  :: PipedSession
  -> Maybe Integer
  -> IO TimedBridgeFrame
readBridgeFrameUntil session maybeDeadline =
  case maybeDeadline of
    Nothing -> TimedBridgeResult <$> readBridgeFrame session
    Just deadline -> do
      now <- getMonotonicTimeNSec
      let remainingNanoseconds = deadline - toInteger now
      if remainingNanoseconds <= 0
        then pure TimedBridgeDeadline
        else do
          maybeFrame <-
            timeout
              (boundedMicroseconds remainingNanoseconds)
              (readBridgeFrame session)
          pure (maybe TimedBridgeDeadline TimedBridgeResult maybeFrame)

boundedMicroseconds :: Integer -> Int
boundedMicroseconds nanoseconds =
  fromInteger
    ( min
        (toInteger (maxBound :: Int))
        ((nanoseconds + 999) `div` 1000)
    )

pipedProcessExceptionFailure :: SomeException -> ConsumerFailure
pipedProcessExceptionFailure exception =
  case fromException exception of
    Just actionException ->
      ConsumerPipedActionFailure
        (pipedActionExceptionDetail actionException)
        (pipedActionExceptionOutcome actionException)
    Nothing ->
      ConsumerProtocolFailure
        ("failed to start or supervise Pulsar bridge: " <> exceptionText exception)

finalizeConsume
  :: ConsumeActionResult result
  -> ProcessOutcome
  -> ConsumeProcessResult result
finalizeConsume actionResult outcome =
  case (actionResult, outcome) of
    (ConsumeCompleted result, ProcessSucceeded _transcript) ->
      ConsumeProcessFinished (Right result)
    (ConsumeCompleted _result, ProcessFailed failure) ->
      ConsumeProcessFinished (Left (ConsumerTransportFailure failure))
    (ConsumeCancelled asyncException, ProcessSucceeded _transcript) ->
      ConsumeProcessCancelled asyncException
    (ConsumeCancelled _asyncException, ProcessFailed failure) ->
      ConsumeProcessFinished (Left (ConsumerTransportFailure failure))
    (ConsumeFailed failure, ProcessSucceeded _transcript) ->
      ConsumeProcessFinished (Left failure)
    (ConsumeFailed failure, ProcessFailed processFailure) ->
      ConsumeProcessFinished
        ( Left
            ( ConsumerTransportContextFailure
                failure
                processFailure
            )
        )
    (ConsumeExitedBeforeDrain, ProcessFailed failure) ->
      ConsumeProcessFinished (Left (ConsumerTransportFailure failure))
    (ConsumeExitedBeforeDrain, ProcessSucceeded transcript) ->
      ConsumeProcessFinished (Left (ConsumerTransportExited transcript))

consumeFrames
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> (Delivery event -> IO (ConsumerDecision result))
  -> PipedSession
  -> BridgeState
  -> IO (ConsumeActionResult result)
consumeFrames topic observe handler session state = do
  frameResult <- readBridgeFrame session
  case frameResult of
    Left failure -> pure (ConsumeFailed failure)
    Right Nothing -> pure ConsumeExitedBeforeDrain
    Right (Just frame) ->
      case applyChildFrame state frame of
        Left stateError -> pure (protocolStateFailure stateError)
        Right nextState ->
          case frame of
            Connected generation -> do
              observerResult <- notifyObserver observe (ConsumerSessionConnected generation)
              case observerResult of
                Left failure -> pure (ConsumeFailed failure)
                Right () -> consumeFrames topic observe handler session nextState
            BridgeError scope _receipt fatal message ->
              handleBridgeError
                topic
                observe
                handler
                session
                nextState
                scope
                fatal
                message
            Delivery receipt payload redeliveryCount ->
              handleDelivery
                topic
                observe
                handler
                session
                nextState
                receipt
                payload
                redeliveryCount
            Settled _receipt _kind ->
              pure
                ( ConsumeFailed
                    (ConsumerProtocolFailure "bridge emitted settlement without a pending command")
                )
            Drained ->
              pure
                ( ConsumeFailed
                    (ConsumerProtocolFailure "bridge drained before the parent requested drain")
                )

handleDelivery
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> (Delivery event -> IO (ConsumerDecision result))
  -> PipedSession
  -> BridgeState
  -> DeliveryReceipt
  -> ByteString
  -> Int
  -> IO (ConsumeActionResult result)
handleDelivery topic observe handler session state receipt payload redeliveryCount =
  case decodeDelivery topic payload of
    Left decodeFailure ->
      settleFailureThenDrain
        observe
        session
        state
        receipt
        (Nack (renderNackReason (DecodeRejected (Text.pack (show decodeFailure)))))
        (ConsumerDecodeFailure decodeFailure)
    Right event -> do
      handlerResult <-
        tryAny
          ( handler
              PulsarInternal.Delivery
                { deliveryEventInternal = event
                , deliveryReceiptInternal = receipt
                , deliveryRedeliveryCountInternal = redeliveryCount
                }
          )
      case handlerResult of
        Left exception
          | Just asyncException <- fromException exception ->
              -- A daemon SIGTERM/ThreadKilled is a typed drain request for the
              -- in-flight receipt, not permission to abandon it.  Settle the
              -- exact receipt with a negative acknowledgement, await the child
              -- confirmation and drained frame. The cancellation stays in the
              -- action result until the child exit status and scoped cleanup
              -- have both been observed.
              settleTerminal
                observe
                session
                state
                receipt
                (Nack (renderNackReason DrainRequested))
                (ConsumeCancelled asyncException)
          | otherwise ->
              let message = "delivery handler threw: " <> exceptionText exception
               in settleFailureThenDrain
                    observe
                    session
                    state
                    receipt
                    (Nack (renderNackReason (HandlerRejected message)))
                    (ConsumerHandlerFailure message)
        Right decision ->
          case decision of
            ContinueInternal disposition -> do
              settlementResult <-
                settleReceipt observe session state receipt (dispositionSettlement disposition)
              case settlementResult of
                Left failure -> pure (ConsumeFailed failure)
                Right settledState ->
                  consumeFrames topic observe handler session settledState
            DoneInternal disposition result -> do
              settleTerminal
                observe
                session
                state
                receipt
                (dispositionSettlement disposition)
                (ConsumeCompleted result)

settleFailureThenDrain
  :: (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BridgeState
  -> DeliveryReceipt
  -> Settlement
  -> ConsumerFailure
  -> IO (ConsumeActionResult result)
settleFailureThenDrain observe session state receipt settlement failure = do
  settleTerminal
    observe
    session
    state
    receipt
    settlement
    (ConsumeFailed failure)

settleTerminal
  :: (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BridgeState
  -> DeliveryReceipt
  -> Settlement
  -> ConsumeActionResult result
  -> IO (ConsumeActionResult result)
settleTerminal observe session state receipt settlement terminalResult =
  case applyParentCommand state settlementCommand of
    Left stateError -> pure (ConsumeFailed (settlementStateFailure stateError))
    Right settlementState ->
      case applyParentCommand settlementState Drain of
        Left stateError -> pure (protocolStateFailure stateError)
        Right drainingState -> do
          observerResult <- notifyObserver observe ConsumerSessionDraining
          case observerResult of
            Left failure -> pure (ConsumeFailed failure)
            Right () -> do
              writeResult <-
                writePipedStdin
                  session
                  (encodeParentCommand settlementCommand <> encodeParentCommand Drain)
              case writeResult of
                Left PipedStdinClosed ->
                  pure
                    ( ConsumeFailed
                        ( ConsumerSettlementFailure
                            "bridge stdin closed before terminal settlement"
                            (SETransient "bridge stdin is closed")
                        )
                    )
                Left (PipedWriteFailed detail) ->
                  pure
                    ( ConsumeFailed
                        ( ConsumerSettlementFailure
                            "bridge pipe write failed before terminal settlement"
                            (SETransient detail)
                        )
                    )
                Right () -> do
                  settlementResult <-
                    awaitSettlement observe session drainingState receipt expectedKind
                  case settlementResult of
                    Left failure -> pure (ConsumeFailed failure)
                    Right settledState ->
                      awaitDrained observe session settledState terminalResult
 where
  settlementCommand = Settle receipt settlement
  expectedKind =
    case settlement of
      Ack -> AckKind
      Nack _reason -> NackKind

settleReceipt
  :: (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BridgeState
  -> DeliveryReceipt
  -> Settlement
  -> IO (Either ConsumerFailure BridgeState)
settleReceipt observe session state receipt settlement =
  case applyParentCommand state command of
    Left stateError -> pure (Left (settlementStateFailure stateError))
    Right requestedState -> do
      writeResult <- writePipedStdin session (encodeParentCommand command)
      case writeResult of
        Left PipedStdinClosed ->
          pure
            ( Left
                ( ConsumerSettlementFailure
                    "bridge stdin closed before settlement"
                    (SETransient "bridge stdin is closed")
                )
            )
        Left (PipedWriteFailed detail) ->
          pure
            ( Left
                ( ConsumerSettlementFailure
                    "bridge pipe write failed before settlement"
                    (SETransient detail)
                )
            )
        Right () -> awaitSettlement observe session requestedState receipt expectedKind
 where
  command = Settle receipt settlement
  expectedKind =
    case settlement of
      Ack -> AckKind
      Nack _reason -> NackKind

awaitSettlement
  :: (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BridgeState
  -> DeliveryReceipt
  -> SettlementKind
  -> IO (Either ConsumerFailure BridgeState)
awaitSettlement observe session state expectedReceipt expectedKind = do
  frameResult <- readBridgeFrame session
  case frameResult of
    Left failure -> pure (Left failure)
    Right Nothing ->
      pure
        ( Left
            ( ConsumerSettlementFailure
                "bridge exited before settlement confirmation"
                (SETransient "unexpected end of bridge stdout")
            )
        )
    Right (Just frame) ->
      case applyChildFrame state frame of
        Left stateError -> pure (Left (settlementStateFailure stateError))
        Right nextState ->
          case frame of
            Connected generation -> do
              observerResult <- notifyObserver observe (ConsumerSessionConnected generation)
              case observerResult of
                Left failure -> pure (Left failure)
                Right () -> awaitSettlement observe session nextState expectedReceipt expectedKind
            BridgeError ConnectionScope _receipt False message -> do
              observerResult <- notifyObserver observe (ConsumerSessionDisconnected message)
              case observerResult of
                Left failure -> pure (Left failure)
                Right () -> awaitSettlement observe session nextState expectedReceipt expectedKind
            BridgeError scope _receipt _fatal message ->
              pure (Left (bridgeSettlementFailure scope message))
            Settled actualReceipt actualKind
              | actualReceipt == expectedReceipt && actualKind == expectedKind ->
                  pure (Right nextState)
              | otherwise ->
                  pure
                    ( Left
                        ( ConsumerSettlementFailure
                            "bridge confirmed a different settlement"
                            (SETransient "receipt or settlement kind did not match")
                        )
                    )
            Delivery _receipt _payload _redeliveryCount ->
              pure
                ( Left
                    ( ConsumerSettlementFailure
                        "bridge delivered a second message before settlement"
                        (SETransient "more than one delivery was in flight")
                    )
                )
            Drained ->
              pure
                ( Left
                    ( ConsumerSettlementFailure
                        "bridge drained before settlement confirmation"
                        (SETransient "settlement was not confirmed")
                    )
                )

awaitDrained
  :: (ConsumerSessionEvent -> IO ())
  -> PipedSession
  -> BridgeState
  -> ConsumeActionResult result
  -> IO (ConsumeActionResult result)
awaitDrained observe session state terminalResult = do
  frameResult <- readBridgeFrame session
  case frameResult of
    Left failure -> pure (ConsumeFailed failure)
    Right Nothing -> pure ConsumeExitedBeforeDrain
    Right (Just frame) ->
      case applyChildFrame state frame of
        Left stateError -> pure (protocolStateFailure stateError)
        Right nextState ->
          case frame of
            Connected generation -> do
              observerResult <- notifyObserver observe (ConsumerSessionConnected generation)
              case observerResult of
                Left failure -> pure (ConsumeFailed failure)
                Right () -> awaitDrained observe session nextState terminalResult
            BridgeError ConnectionScope _receipt False message -> do
              observerResult <- notifyObserver observe (ConsumerSessionDisconnected message)
              case observerResult of
                Left failure -> pure (ConsumeFailed failure)
                Right () -> awaitDrained observe session nextState terminalResult
            BridgeError scope _receipt _fatal message ->
              pure
                ( ConsumeFailed
                    ( ConsumerProtocolFailure
                        ("bridge failed while draining in " <> renderBridgeScope scope <> ": " <> message)
                    )
                )
            Drained -> do
              observerResult <- notifyObserver observe ConsumerSessionDrained
              case observerResult of
                Left failure -> pure (ConsumeFailed failure)
                Right () -> pure terminalResult
            Delivery _receipt _payload _redeliveryCount ->
              pure
                ( ConsumeFailed
                    (ConsumerProtocolFailure "bridge delivered a message while draining")
                )
            Settled _receipt _kind ->
              pure
                ( ConsumeFailed
                    (ConsumerProtocolFailure "bridge repeated settlement while draining")
                )

handleBridgeError
  :: Topic event
  -> (ConsumerSessionEvent -> IO ())
  -> (Delivery event -> IO (ConsumerDecision result))
  -> PipedSession
  -> BridgeState
  -> BridgeErrorScope
  -> Bool
  -> Text
  -> IO (ConsumeActionResult result)
handleBridgeError topic observe handler session state scope fatal message =
  case (scope, fatal) of
    (ConnectionScope, False) -> do
      observerResult <- notifyObserver observe (ConsumerSessionDisconnected message)
      case observerResult of
        Left failure -> pure (ConsumeFailed failure)
        Right () -> consumeFrames topic observe handler session state
    _ ->
      pure
        ( ConsumeFailed
            ( ConsumerProtocolFailure
                ("bridge error in " <> renderBridgeScope scope <> ": " <> message)
            )
        )

readBridgeFrame :: PipedSession -> IO (Either ConsumerFailure (Maybe ChildFrame))
readBridgeFrame session = do
  maybeLine <- readPipedStdoutLine session
  pure $
    case maybeLine of
      Nothing -> Right Nothing
      Just line ->
        case decodeChildFrame line of
          Left codecError ->
            Left
              ( ConsumerProtocolFailure
                  ("invalid bridge NDJSON: " <> Text.pack (show codecError))
              )
          Right frame -> Right (Just frame)

decodeDelivery :: Topic event -> ByteString -> Either TopicDecodeError event
decodeDelivery topic payload = do
  payloadText <-
    case Text.Encoding.decodeUtf8' payload of
      Left unicodeError -> Left (utf8TopicDecodeError topic unicodeError)
      Right decoded -> Right decoded
  decodeTopicPayload topic payloadText

utf8TopicDecodeError :: Topic event -> UnicodeException -> TopicDecodeError
utf8TopicDecodeError topic unicodeError =
  TopicDecodeError
    { topicDecodeErrorTopic = topicName topic
    , topicDecodeErrorDetail = "payload is not UTF-8: " <> Text.pack (show unicodeError)
    }

dispositionSettlement :: Disposition -> Settlement
dispositionSettlement AckInternal = Ack
dispositionSettlement (NackInternal reason) = Nack (renderNackReason reason)

renderNackReason :: NackReason -> Text
renderNackReason (DecodeRejected message) = "decode-rejected: " <> message
renderNackReason (HandlerRejected message) = "handler-rejected: " <> message
renderNackReason (RetryRequested message) = "retry-requested: " <> message
renderNackReason DrainRequested = "drain-requested"

notifyObserver
  :: (ConsumerSessionEvent -> IO ())
  -> ConsumerSessionEvent
  -> IO (Either ConsumerFailure ())
notifyObserver observe event = do
  result <- trySync (observe event)
  pure $
    case result of
      Left exception ->
        Left
          ( ConsumerHandlerFailure
              ("consumer session observer threw: " <> exceptionText exception)
          )
      Right () -> Right ()

cleanupSubscription
  :: PulsarWebSocketSettings
  -> Subscription event
  -> IO (Either ConsumerFailure ())
cleanupSubscription settings subscription =
  case subscriptionCleanupSubprocess settings subscription of
    Nothing -> pure (Right ())
    Just command -> do
      -- Owned cursor deletion is a bounded release action. Once begun it must
      -- not be interrupted by a racing cancellation and falsely reported as
      -- clean; curl's max-time keeps the uninterruptible region finite.
      outcomeResult <-
        tryProcessOutcome
          (uninterruptibleMask_ (runStreaming defaultSubprocessEnv command))
      pure $
        case outcomeResult of
          Left serviceError -> Left (ConsumerCleanupFailure serviceError)
          Right outcome@(ProcessFailed _failure) ->
            Left
              ( ConsumerCleanupFailure
                  (SETransient ("owned Pulsar subscription cleanup failed:\n" <> renderProcessOutcome outcome))
              )
          Right outcome@(ProcessSucceeded transcript)
            | cleanupHttpStatusIsSuccess (Text.strip (processTranscriptStdout transcript)) -> Right ()
            | otherwise ->
                Left
                  ( ConsumerCleanupFailure
                      ( SETransient
                          ( "owned Pulsar subscription cleanup returned an unexpected HTTP status:\n"
                              <> renderProcessOutcome outcome
                          )
                      )
                  )

cleanupHttpStatusIsSuccess :: Text -> Bool
cleanupHttpStatusIsSuccess status =
  status `elem` ["200", "204", "404"]

createHttpStatusIsSuccess :: Text -> Bool
createHttpStatusIsSuccess status =
  status `elem` ["200", "204", "409"]

tryProcessOutcome :: IO ProcessOutcome -> IO (Either ServiceError ProcessOutcome)
tryProcessOutcome action = do
  result <- trySync action
  pure $
    case result of
      Left exception -> Left (SETransient (exceptionText exception))
      Right outcome -> Right outcome

trySync :: IO value -> IO (Either SomeException value)
trySync action = do
  result <- try action
  case result of
    Left exception
      | Just asyncException <- fromException exception -> throwIO (asyncException :: SomeAsyncException)
      | otherwise -> pure (Left exception)
    Right value -> pure (Right value)

tryAny :: IO value -> IO (Either SomeException value)
tryAny = try

exceptionText :: SomeException -> Text
exceptionText = Text.pack . displayException

protocolStateFailure :: (Show stateError) => stateError -> ConsumeActionResult result
protocolStateFailure =
  ConsumeFailed . ConsumerProtocolFailure . ("bridge state violation: " <>) . Text.pack . show

settlementStateFailure :: (Show stateError) => stateError -> ConsumerFailure
settlementStateFailure stateError =
  ConsumerSettlementFailure
    "bridge rejected settlement state"
    (SETransient (Text.pack (show stateError)))

bridgeSettlementFailure :: BridgeErrorScope -> Text -> ConsumerFailure
bridgeSettlementFailure scope message =
  ConsumerSettlementFailure
    ("bridge settlement error in " <> renderBridgeScope scope)
    (SETransient message)

renderBridgeScope :: BridgeErrorScope -> Text
renderBridgeScope ConnectionScope = "connection"
renderBridgeScope DeliveryScope = "delivery"
renderBridgeScope SettlementScope = "settlement"
renderBridgeScope ProtocolScope = "protocol"
renderBridgeScope DrainScope = "drain"

producerUrl :: PulsarWebSocketSettings -> Topic event -> Text
producerUrl settings topic =
  stripTrailingSlash (pulsarWebSocketEndpoint settings)
    <> "/v2/producer/"
    <> topicPath (topicName topic)

consumerUrl :: PulsarWebSocketSettings -> Subscription event -> Text
consumerUrl settings subscription =
  stripTrailingSlash (pulsarWebSocketEndpoint settings)
    <> "/v2/consumer/"
    <> topicPath (topicName (subscriptionTopicInternal subscription))
    <> "/"
    <> pathSegment (subscriptionNameInternal subscription)
    <> "?subscriptionType=Failover&receiverQueueSize=1"
    <> "&pullMode=true"
    <> "&subscriptionInitialPosition="
    <> initialPosition (subscriptionStartInternal subscription)
    <> "&negativeAckRedeliveryDelay=1000"

subscriptionAdminResourceUrl :: PulsarWebSocketSettings -> Subscription event -> Text
subscriptionAdminResourceUrl settings subscription =
  stripTrailingSlash (pulsarAdminEndpoint settings)
    <> "/"
    <> topicPath (topicName (subscriptionTopicInternal subscription))
    <> "/subscription/"
    <> pathSegment (subscriptionNameInternal subscription)

-- MessageId.latest. Pulsar serializes @MessageIdImpl(Long.MAX_VALUE,
-- Long.MAX_VALUE, -1)@ for @createSubscription(..., MessageId.latest)@.
-- @MessageIdImpl(-1, -1, -1)@ is @MessageId.earliest@, which plants the cursor
-- at the start of the topic and replays every message already published to it —
-- the exact inversion of the guarantee this cursor exists to prove.
latestMessageIdJson :: Text
latestMessageIdJson =
  "{\"ledgerId\":9223372036854775807,\"entryId\":9223372036854775807,\"partitionIndex\":-1}"

initialPosition :: SubscriptionStart -> Text
initialPosition FromEarliest = "Earliest"
initialPosition FromLatest = "Latest"

topicPath :: Text -> Text
topicPath topic =
  case Text.stripPrefix "persistent://" topic of
    Just rest -> "persistent/" <> encodePath rest
    Nothing
      | "/" `Text.isInfixOf` topic -> encodePath topic
      | otherwise -> "persistent/public/default/" <> pathSegment topic

encodePath :: Text -> Text
encodePath = Text.intercalate "/" . fmap pathSegment . Text.splitOn "/"

pathSegment :: Text -> Text
pathSegment = Text.concatMap encodeCharacter

encodeCharacter :: Char -> Text
encodeCharacter character
  | isPathSafe character = Text.singleton character
  | otherwise = percentEncodeUtf8 character

isPathSafe :: Char -> Bool
isPathSafe character = character `elem` safeCharacters

safeCharacters :: [Char]
safeCharacters =
  ['a' .. 'z']
    <> ['A' .. 'Z']
    <> ['0' .. '9']
    <> "-._~"

percentEncodeUtf8 :: Char -> Text
percentEncodeUtf8 =
  Text.concatMap (Text.pack . bytePercentHex)
    . Text.Encoding.decodeLatin1
    . Text.Encoding.encodeUtf8
    . Text.singleton

bytePercentHex :: Char -> String
bytePercentHex character =
  let byte = fromEnum character
   in [ '%'
      , intToHexUpper (byte `div` 16)
      , intToHexUpper (byte `mod` 16)
      ]

intToHexUpper :: Int -> Char
intToHexUpper digit
  | digit < 10 = toEnum (fromEnum '0' + digit)
  | otherwise = toEnum (fromEnum 'A' + digit - 10)

stripTrailingSlash :: Text -> Text
stripTrailingSlash value
  | "/" `Text.isSuffixOf` value = stripTrailingSlash (Text.dropEnd 1 value)
  | otherwise = value

websocketEndpointFromServiceUrl :: Text -> Text
websocketEndpointFromServiceUrl =
  appendWebsocketPath . toWebsocketScheme . stripTrailingSlash

adminEndpointFromServiceUrl :: Text -> Text
adminEndpointFromServiceUrl =
  appendAdminPath . removeWebsocketPath . toHttpScheme . stripTrailingSlash

toWebsocketScheme :: Text -> Text
toWebsocketScheme endpoint
  | Just rest <- Text.stripPrefix "pulsar://" endpoint = "ws://" <> rest
  | Just rest <- Text.stripPrefix "http://" endpoint = "ws://" <> rest
  | Just rest <- Text.stripPrefix "https://" endpoint = "wss://" <> rest
  | otherwise = endpoint

toHttpScheme :: Text -> Text
toHttpScheme endpoint
  | Just rest <- Text.stripPrefix "pulsar://" endpoint = "http://" <> rest
  | Just rest <- Text.stripPrefix "ws://" endpoint = "http://" <> rest
  | Just rest <- Text.stripPrefix "wss://" endpoint = "https://" <> rest
  | otherwise = endpoint

appendWebsocketPath :: Text -> Text
appendWebsocketPath endpoint
  | "/ws" `Text.isSuffixOf` endpoint = endpoint
  | "/pulsar" `Text.isSuffixOf` endpoint = endpoint <> "/ws"
  | otherwise = endpoint <> "/ws"

removeWebsocketPath :: Text -> Text
removeWebsocketPath endpoint
  | "/ws" `Text.isSuffixOf` endpoint = Text.dropEnd 3 endpoint
  | otherwise = endpoint

appendAdminPath :: Text -> Text
appendAdminPath endpoint
  | "/admin/v2" `Text.isSuffixOf` endpoint = endpoint
  | otherwise = endpoint <> "/admin/v2"

-- | One-shot typed publisher. Payload bytes arrive over stdin, avoiding shell
-- argument interpolation and preserving the topic encoder's exact UTF-8.
pulsarProducerScript :: Text
pulsarProducerScript =
  Text.unlines
    [ "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url] = process.argv.slice(1);"
    , "const chunks = [];"
    , "process.stdin.on('data', (chunk) => chunks.push(Buffer.from(chunk)));"
    , "process.stdin.on('end', () => {"
    , "  const payload = Buffer.concat(chunks);"
    , "  const ws = new WebSocketCtor(url);"
    , "  let acknowledged = false;"
    , "  const timer = setTimeout(() => { console.error('publish timeout'); process.exit(2); }, 10000);"
    , "  ws.addEventListener('open', () => {"
    , "    ws.send(JSON.stringify({ payload: payload.toString('base64'), properties: {}, context: 'jitml' }));"
    , "  });"
    , "  ws.addEventListener('message', (event) => {"
    , "    const response = JSON.parse(String(event.data));"
    , "    if (response.result && response.result !== 'ok') { console.error(String(event.data)); process.exit(1); }"
    , "    acknowledged = true;"
    , "    clearTimeout(timer);"
    , "    process.stdout.write(String(response.messageId || response.context || 'ok'));"
    , "    ws.close();"
    , "    process.exit(0);"
    , "  });"
    , "  ws.addEventListener('error', (event) => { console.error(event.message || 'publish websocket error'); });"
    , "  ws.addEventListener('close', (event) => {"
    , "    if (!acknowledged) { clearTimeout(timer); console.error(`publish closed: ${event.code} ${event.reason || ''}`); process.exit(1); }"
    , "  });"
    , "});"
    ]

-- | Multi-receipt pull bridge used only by 'pulsarConsumeBatchesUntil'.  The
-- parent explicitly permits one delivery at a time, so it can stop admitting
-- requests at the batch deadline without exposing broker message ids.  A
-- permit that races with a deadline is either carried into the next batch by
-- the parent or negative-acknowledged by the child after drain begins.
pulsarBatchConsumerBridgeScript :: Text
pulsarBatchConsumerBridgeScript =
  Text.unlines
    [ "const crypto = require('crypto');"
    , "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url] = process.argv.slice(1);"
    , "const version = 1;"
    , "const session = crypto.randomUUID();"
    , "const receiptToMessageId = new Map();"
    , "const pendingSettlements = new Map();"
    , "const settlementSockets = new Map();"
    , "let socket = null;"
    , "let generation = 0;"
    , "let deliverySequence = 0;"
    , "let reconnectTimer = null;"
    , "let stdinBuffer = '';"
    , "let permitOutstanding = false;"
    , "let draining = false;"
    , "let autonomousDrain = false;"
    , "let completed = false;"
    , "const emit = (frame) => process.stdout.write(JSON.stringify({ version, ...frame }) + '\\n');"
    , "const sameReceipt = (left, right) => left && right && left.session === right.session && left.generation === right.generation && left.deliveryId === right.deliveryId;"
    , "function firstReceipt() { const first = receiptToMessageId.values().next(); return first.done ? null : first.value.receipt; }"
    , "function emitError(scope, receipt, fatal, message) {"
    , "  emit({ type: 'bridge-error', scope, receipt: receipt || null, fatal, message: String(message) });"
    , "  if (fatal) {"
    , "    completed = true;"
    , "    if (reconnectTimer !== null) { clearTimeout(reconnectTimer); reconnectTimer = null; }"
    , "    const failingSocket = socket;"
    , "    socket = null;"
    , "    if (failingSocket && failingSocket.readyState < 2) failingSocket.close();"
    , "    process.stdout.write('', () => process.exit(1));"
    , "  }"
    , "}"
    , "function scheduleReconnect() {"
    , "  if (completed || reconnectTimer !== null) return;"
    , "  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 1000);"
    , "}"
    , "function permitOne() {"
    , "  if (completed || draining || permitOutstanding) return;"
    , "  if (!socket || socket.readyState !== 1) return;"
    , "  socket.send(JSON.stringify({ type: 'permit', permitMessages: 1 }));"
    , "  permitOutstanding = true;"
    , "}"
    , "function finishDrainIfIdle() {"
    , "  if (!draining || receiptToMessageId.size !== 0 || pendingSettlements.size !== 0 || completed) return;"
    , "  completed = true;"
    , "  permitOutstanding = false;"
    , "  if (reconnectTimer !== null) { clearTimeout(reconnectTimer); reconnectTimer = null; }"
    , "  const closingSocket = socket;"
    , "  socket = null;"
    , "  if (closingSocket && closingSocket.readyState < 2) closingSocket.close();"
    , "  emit({ type: 'drained' });"
    , "  process.stdout.write('', () => process.exit(0));"
    , "}"
    , "function flushSettlement(command) {"
    , "  if (!command || !socket || socket.readyState !== 1 || completed) return;"
    , "  const receipt = command.receipt;"
    , "  const entry = receiptToMessageId.get(receipt.deliveryId);"
    , "  if (!entry || !sameReceipt(entry.receipt, receipt)) { emitError('settlement', receipt, true, 'unknown or stale receipt token'); return; }"
    , "  if (settlementSockets.get(receipt.deliveryId) === socket) return;"
    , "  const sendingSocket = socket;"
    , "  try {"
    , "    if (command.settlement.type === 'ack') sendingSocket.send(JSON.stringify({ messageId: entry.messageId }));"
    , "    else if (command.settlement.type === 'nack') sendingSocket.send(JSON.stringify({ type: 'negativeAcknowledge', messageId: entry.messageId }));"
    , "    else { emitError('settlement', receipt, true, 'unknown settlement kind'); return; }"
    , "  } catch (error) {"
    , "    console.error(`settlement send failed: ${error.message || error}`);"
    , "    try { sendingSocket.close(); } catch (_closeError) {}"
    , "    return;"
    , "  }"
    , "  settlementSockets.set(receipt.deliveryId, sendingSocket);"
    , "  confirmSettlementWhenFlushed(command, entry, sendingSocket);"
    , "}"
    , "function confirmSettlementWhenFlushed(command, entry, sendingSocket) {"
    , "  const receipt = command.receipt;"
    , "  if (completed || pendingSettlements.get(receipt.deliveryId) !== command) return;"
    , "  if (socket !== sendingSocket || sendingSocket.readyState !== 1) {"
    , "    if (settlementSockets.get(receipt.deliveryId) === sendingSocket) settlementSockets.delete(receipt.deliveryId);"
    , "    return;"
    , "  }"
    , "  if (sendingSocket.bufferedAmount !== 0) { setImmediate(() => confirmSettlementWhenFlushed(command, entry, sendingSocket)); return; }"
    , "  receiptToMessageId.delete(receipt.deliveryId);"
    , "  pendingSettlements.delete(receipt.deliveryId);"
    , "  settlementSockets.delete(receipt.deliveryId);"
    , "  if (!command.internalDrainRace) emit({ type: 'settled', receipt, settlement: command.settlement.type });"
    , "  if (draining) finishDrainIfIdle();"
    , "}"
    , "function flushPendingSettlements() { for (const command of pendingSettlements.values()) flushSettlement(command); }"
    , "function handleCommand(command) {"
    , "  if (!command || command.version !== version || typeof command.type !== 'string') { emitError('protocol', null, true, 'invalid command envelope'); return; }"
    , "  if (command.type === 'permit') {"
    , "    if (command.permitMessages !== 1) { emitError('protocol', null, true, 'batch permits must request exactly one message'); return; }"
    , "    if (draining) { emitError('drain', null, true, 'permit requested after drain'); return; }"
    , "    if (permitOutstanding) { emitError('protocol', null, true, 'permit already outstanding'); return; }"
    , "    permitOne();"
    , "    return;"
    , "  }"
    , "  if (command.type === 'settle') {"
    , "    const entry = command.receipt && receiptToMessageId.get(command.receipt.deliveryId);"
    , "    if (!entry || !sameReceipt(entry.receipt, command.receipt)) { emitError('settlement', command.receipt || null, true, 'unknown receipt token'); return; }"
    , "    if (pendingSettlements.has(command.receipt.deliveryId)) { emitError('settlement', command.receipt, true, 'settlement already pending'); return; }"
    , "    pendingSettlements.set(command.receipt.deliveryId, command);"
    , "    flushSettlement(command);"
    , "    return;"
    , "  }"
    , "  if (command.type === 'drain') {"
    , "    draining = true;"
    , "    setImmediate(finishDrainIfIdle);"
    , "    return;"
    , "  }"
    , "  emitError('protocol', null, true, `unknown command type: ${command.type}`);"
    , "}"
    , "process.stdin.setEncoding('utf8');"
    , "process.stdin.on('data', (chunk) => {"
    , "  stdinBuffer += chunk;"
    , "  const lines = stdinBuffer.split('\\n');"
    , "  stdinBuffer = lines.pop() || '';"
    , "  for (const line of lines) {"
    , "    if (line.trim().length === 0) continue;"
    , "    try { handleCommand(JSON.parse(line)); } catch (error) { emitError('protocol', null, true, error.message || error); }"
    , "  }"
    , "});"
    , "function drainAfterParentExit() {"
    , "  autonomousDrain = true;"
    , "  draining = true;"
    , "  for (const entry of receiptToMessageId.values()) {"
    , "    if (!pendingSettlements.has(entry.receipt.deliveryId)) pendingSettlements.set(entry.receipt.deliveryId, { version, type: 'settle', receipt: entry.receipt, settlement: { type: 'nack', reason: 'drain-requested' } });"
    , "  }"
    , "  flushPendingSettlements();"
    , "  if (receiptToMessageId.size !== 0 && (!socket || socket.readyState !== 1)) scheduleReconnect();"
    , "  setImmediate(finishDrainIfIdle);"
    , "}"
    , "process.stdin.on('end', drainAfterParentExit);"
    , "process.on('SIGTERM', drainAfterParentExit);"
    , "function connect() {"
    , "  if (completed) return;"
    , "  const connectionGeneration = ++generation;"
    , "  const nextSocket = new WebSocketCtor(url);"
    , "  socket = nextSocket;"
    , "  nextSocket.addEventListener('open', () => {"
    , "    if (socket !== nextSocket || completed) return;"
    , "    emit({ type: 'connected', generation: connectionGeneration });"
    , "    flushPendingSettlements();"
    , "    if (draining) finishDrainIfIdle();"
    , "  });"
    , "  nextSocket.addEventListener('message', (event) => {"
    , "    if (socket !== nextSocket || completed) return;"
    , "    if (!permitOutstanding) { emitError('delivery', firstReceipt(), true, 'delivery arrived without a permit'); return; }"
    , "    permitOutstanding = false;"
    , "    let message;"
    , "    try { message = JSON.parse(String(event.data)); } catch (error) { emitError('delivery', null, true, error.message || error); return; }"
    , "    if (!message.messageId || typeof message.payload !== 'string') { emitError('delivery', null, true, 'broker delivery missing messageId or payload'); return; }"
    , "    const deliveryId = `receipt-${++deliverySequence}-${crypto.randomUUID()}`;"
    , "    const receipt = { session, generation: connectionGeneration, deliveryId };"
    , "    receiptToMessageId.set(deliveryId, { receipt, messageId: message.messageId });"
    , "    if (draining && autonomousDrain) {"
    , "      const command = { version, type: 'settle', receipt, settlement: { type: 'nack', reason: 'drain-requested' }, internalDrainRace: true };"
    , "      pendingSettlements.set(deliveryId, command);"
    , "      flushSettlement(command);"
    , "      return;"
    , "    }"
    , "    const redeliveryCount = Number.isInteger(message.redeliveryCount) && message.redeliveryCount >= 0 ? message.redeliveryCount : 0;"
    , "    emit({ type: 'delivery', receipt, payloadBase64: message.payload, redeliveryCount });"
    , "  });"
    , "  nextSocket.addEventListener('error', (event) => { console.error(`consumer websocket error: ${event.message || ''}`); });"
    , "  nextSocket.addEventListener('close', (event) => {"
    , "    if (socket !== nextSocket || completed) return;"
    , "    socket = null;"
    , "    permitOutstanding = false;"
    , "    for (const [deliveryId, sendingSocket] of settlementSockets.entries()) if (sendingSocket === nextSocket) settlementSockets.delete(deliveryId);"
    , "    emitError('connection', firstReceipt(), false, `closed ${event.code} ${event.reason || ''}`);"
    , "    if (draining && receiptToMessageId.size === 0) finishDrainIfIdle(); else scheduleReconnect();"
    , "  });"
    , "}"
    , "connect();"
    ]

-- | Persistent receipt-token bridge. Broker message ids live only in the
-- private @receiptToMessageId@ map and are never emitted on stdout.
pulsarConsumerBridgeScript :: Text
pulsarConsumerBridgeScript =
  Text.unlines
    [ "const crypto = require('crypto');"
    , "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url] = process.argv.slice(1);"
    , "const version = 1;"
    , "const session = crypto.randomUUID();"
    , "const receiptToMessageId = new Map();"
    , "let socket = null;"
    , "let generation = 0;"
    , "let deliverySequence = 0;"
    , "let reconnectTimer = null;"
    , "let stdinBuffer = '';"
    , "let inFlight = null;"
    , "let pendingSettlement = null;"
    , "let settlementSocket = null;"
    , "let permitOutstanding = false;"
    , "let draining = false;"
    , "let completed = false;"
    , "const emit = (frame) => process.stdout.write(JSON.stringify({ version, ...frame }) + '\\n');"
    , "const sameReceipt = (left, right) => left && right && left.session === right.session && left.generation === right.generation && left.deliveryId === right.deliveryId;"
    , "function emitError(scope, receipt, fatal, message) {"
    , "  emit({ type: 'bridge-error', scope, receipt: receipt || null, fatal, message: String(message) });"
    , "  if (fatal) {"
    , "    completed = true;"
    , "    if (reconnectTimer !== null) { clearTimeout(reconnectTimer); reconnectTimer = null; }"
    , "    const failingSocket = socket;"
    , "    socket = null;"
    , "    if (failingSocket && failingSocket.readyState < 2) failingSocket.close();"
    , "    process.stdout.write('', () => process.exit(1));"
    , "  }"
    , "}"
    , "function scheduleReconnect() {"
    , "  if (completed || reconnectTimer !== null) return;"
    , "  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 1000);"
    , "}"
    , "function permitOne() {"
    , "  if (completed || draining || inFlight || pendingSettlement || permitOutstanding) return;"
    , "  if (!socket || socket.readyState !== 1) return;"
    , "  socket.send(JSON.stringify({ type: 'permit', permitMessages: 1 }));"
    , "  permitOutstanding = true;"
    , "}"
    , "function finishDrainIfIdle() {"
    , "  if (!draining || inFlight || pendingSettlement || completed) return;"
    , "  completed = true;"
    , "  if (reconnectTimer !== null) { clearTimeout(reconnectTimer); reconnectTimer = null; }"
    , "  const closingSocket = socket;"
    , "  socket = null;"
    , "  if (closingSocket && closingSocket.readyState < 2) closingSocket.close();"
    , "  emit({ type: 'drained' });"
    , "  process.stdout.write('', () => process.exit(0));"
    , "}"
    , "function flushPendingSettlement() {"
    , "  if (!pendingSettlement || !socket || socket.readyState !== 1 || completed) return;"
    , "  const command = pendingSettlement;"
    , "  const receipt = command.receipt;"
    , "  const entry = receiptToMessageId.get(receipt.deliveryId);"
    , "  if (!entry || !sameReceipt(entry.receipt, receipt) || !sameReceipt(inFlight, receipt)) {"
    , "    emitError('settlement', receipt, true, 'unknown or stale receipt token');"
    , "    return;"
    , "  }"
    , "  if (settlementSocket === socket) return;"
    , "  const sendingSocket = socket;"
    , "  try {"
    , "    if (command.settlement.type === 'ack') {"
    , "      sendingSocket.send(JSON.stringify({ messageId: entry.messageId }));"
    , "    } else if (command.settlement.type === 'nack') {"
    , "      sendingSocket.send(JSON.stringify({ type: 'negativeAcknowledge', messageId: entry.messageId }));"
    , "    } else {"
    , "      emitError('settlement', receipt, true, 'unknown settlement kind');"
    , "      return;"
    , "    }"
    , "  } catch (error) {"
    , "    console.error(`settlement send failed: ${error.message || error}`);"
    , "    try { sendingSocket.close(); } catch (_closeError) {}"
    , "    return;"
    , "  }"
    , "  settlementSocket = sendingSocket;"
    , "  confirmSettlementWhenFlushed(command, entry, sendingSocket);"
    , "}"
    , "function confirmSettlementWhenFlushed(command, entry, sendingSocket) {"
    , "  if (completed || pendingSettlement !== command) return;"
    , "  if (socket !== sendingSocket || sendingSocket.readyState !== 1) {"
    , "    if (settlementSocket === sendingSocket) settlementSocket = null;"
    , "    return;"
    , "  }"
    , "  if (sendingSocket.bufferedAmount !== 0) { setImmediate(() => confirmSettlementWhenFlushed(command, entry, sendingSocket)); return; }"
    , "  const receipt = command.receipt;"
    , "  const settlement = command.settlement.type;"
    , "  receiptToMessageId.delete(receipt.deliveryId);"
    , "  inFlight = null;"
    , "  pendingSettlement = null;"
    , "  settlementSocket = null;"
    , "  emit({ type: 'settled', receipt, settlement });"
    , "  if (draining) finishDrainIfIdle(); else setImmediate(permitOne);"
    , "}"
    , "function handleCommand(command) {"
    , "  if (!command || command.version !== version || typeof command.type !== 'string') {"
    , "    emitError('protocol', null, true, 'invalid command envelope');"
    , "    return;"
    , "  }"
    , "  if (command.type === 'settle') {"
    , "    if (pendingSettlement !== null) { emitError('settlement', command.receipt, true, 'settlement already pending'); return; }"
    , "    const entry = command.receipt && receiptToMessageId.get(command.receipt.deliveryId);"
    , "    if (!entry || !sameReceipt(entry.receipt, command.receipt) || !sameReceipt(inFlight, command.receipt)) {"
    , "      emitError('settlement', command.receipt || null, true, 'unknown receipt token');"
    , "      return;"
    , "    }"
    , "    pendingSettlement = command;"
    , "    flushPendingSettlement();"
    , "    return;"
    , "  }"
    , "  if (command.type === 'drain') {"
    , "    draining = true;"
    , "    finishDrainIfIdle();"
    , "    return;"
    , "  }"
    , "  emitError('protocol', null, true, `unknown command type: ${command.type}`);"
    , "}"
    , "process.stdin.setEncoding('utf8');"
    , "process.stdin.on('data', (chunk) => {"
    , "  stdinBuffer += chunk;"
    , "  const lines = stdinBuffer.split('\\n');"
    , "  stdinBuffer = lines.pop() || '';"
    , "  for (const line of lines) {"
    , "    if (line.trim().length === 0) continue;"
    , "    try { handleCommand(JSON.parse(line)); } catch (error) { emitError('protocol', null, true, error.message || error); }"
    , "  }"
    , "});"
    , "function drainAfterParentExit() {"
    , "  draining = true;"
    , "  if (inFlight && !pendingSettlement) {"
    , "    pendingSettlement = { version, type: 'settle', receipt: inFlight, settlement: { type: 'nack', reason: 'drain-requested' } };"
    , "  }"
    , "  if (pendingSettlement) {"
    , "    flushPendingSettlement();"
    , "    if (!socket || socket.readyState !== 1) scheduleReconnect();"
    , "    return;"
    , "  }"
    , "  finishDrainIfIdle();"
    , "}"
    , "process.stdin.on('end', drainAfterParentExit);"
    , "process.on('SIGTERM', drainAfterParentExit);"
    , "function connect() {"
    , "  if (completed) return;"
    , "  const connectionGeneration = ++generation;"
    , "  const nextSocket = new WebSocketCtor(url);"
    , "  socket = nextSocket;"
    , "  nextSocket.addEventListener('open', () => {"
    , "    if (socket !== nextSocket || completed) return;"
    , "    emit({ type: 'connected', generation: connectionGeneration });"
    , "    if (pendingSettlement !== null) flushPendingSettlement();"
    , "    else if (draining) finishDrainIfIdle();"
    , "    else permitOne();"
    , "  });"
    , "  nextSocket.addEventListener('message', (event) => {"
    , "    if (socket !== nextSocket || completed) return;"
    , "    if (!permitOutstanding) { emitError('delivery', inFlight, true, 'delivery arrived without a permit'); return; }"
    , "    permitOutstanding = false;"
    , "    if (inFlight || pendingSettlement) { emitError('delivery', inFlight, true, 'more than one delivery in flight'); return; }"
    , "    let message;"
    , "    try { message = JSON.parse(String(event.data)); } catch (error) { emitError('delivery', null, true, error.message || error); return; }"
    , "    if (!message.messageId || typeof message.payload !== 'string') { emitError('delivery', null, true, 'broker delivery missing messageId or payload'); return; }"
    , "    const deliveryId = `receipt-${++deliverySequence}-${crypto.randomUUID()}`;"
    , "    const receipt = { session, generation: connectionGeneration, deliveryId };"
    , "    receiptToMessageId.set(deliveryId, { receipt, messageId: message.messageId });"
    , "    inFlight = receipt;"
    , "    const redeliveryCount = Number.isInteger(message.redeliveryCount) && message.redeliveryCount >= 0 ? message.redeliveryCount : 0;"
    , "    emit({ type: 'delivery', receipt, payloadBase64: message.payload, redeliveryCount });"
    , "  });"
    , "  nextSocket.addEventListener('error', (event) => { console.error(`consumer websocket error: ${event.message || ''}`); });"
    , "  nextSocket.addEventListener('close', (event) => {"
    , "    if (socket !== nextSocket || completed) return;"
    , "    socket = null;"
    , "    if (settlementSocket === nextSocket) settlementSocket = null;"
    , "    permitOutstanding = false;"
    , "    emitError('connection', inFlight, false, `closed ${event.code} ${event.reason || ''}`);"
    , "    if (draining && !inFlight && !pendingSettlement) finishDrainIfIdle(); else scheduleReconnect();"
    , "  });"
    , "}"
    , "connect();"
    ]

{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Data.ByteString.Char8 qualified as ByteString
import Data.Foldable (traverse_)
import Data.List (isInfixOf)
import Network.Socket
  ( AddrInfo (..)
  , Socket
  , SocketType (Stream)
  , close
  , connect
  , defaultHints
  , getAddrInfo
  , socket
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Strict (StateT, evalStateT, get)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.AppError.AppError (AppError (..))
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities
  ( HasHarbor
  , HasKubectl
  , HasMinIO
  , HasPulsar (..)
  , SubscriptionId (..)
  , TopicName (..)
  )
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonSubscription (..)
  , EventDomain (..)
  , HandlerRouter (..)
  , consumerOutcomeError
  , daemonSubscriptionsForBootConfig
  , dedupCacheCapacity
  , domainFor
  , emptyHandlerRouter
  , eventIdFromPayload
  , processAtLeastOnce
  , runConsumerLoop
  , subscribeDaemonTopics
  )
import JitML.Service.Endpoints (MetricsSnapshot (..), endpointStatus, healthz, metrics, readyz)
import JitML.Service.Http (withHttpRoutesOnce)
import JitML.Service.Lifecycle (LifecyclePhase (..), lifecyclePlan)
import JitML.Service.Retry (RetryPolicy (..), ServiceError (..), retryServiceAction)
import JitML.Service.Runtime
  ( DaemonRuntime (daemonReady)
  , daemonHttpRoutes
  , defaultDaemonRuntime
  , runtimeAfterSignal
  )
import JitML.Service.Runtime qualified as Runtime
import JitML.Service.Signal
  ( DaemonControlSnapshot (..)
  , DaemonSignal (..)
  , DaemonSignalAction (..)
  , applyDaemonSignal
  , daemonSignalAction
  , newDaemonControl
  , renderDaemonSignalAction
  )
import JitML.Substrate (Substrate (..))

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-daemon-lifecycle"
      [ testCase "lifecycle order reaches ready before serve" $
          lifecyclePlan @?= [Load, Prereq, Acquire, Ready, Serve, Drain, Exit]
      , testCase "endpoint status codes follow readiness" $ do
          endpointStatus healthz @?= 200
          endpointStatus (readyz False) @?= 503
          endpointStatus (readyz True) @?= 200
          endpointStatus (metrics (MetricsSnapshot 0 1 0)) @?= 200
      , testCase "daemon signals map to reload and graceful drain" $ do
          daemonSignalAction DaemonSighup @?= ReloadLiveConfig
          daemonSignalAction DaemonSigterm @?= BeginGracefulDrain
          renderDaemonSignalAction BeginGracefulDrain @?= "begin-graceful-drain"
          let drainingRuntime = runtimeAfterSignal defaultDaemonRuntime DaemonSigterm
          endpointStatus (readyz True) @?= 200
          endpointStatus (readyz (daemonReady drainingRuntime)) @?= 503
      , testCase "daemon control records reload generation and drain readiness" $ do
          control <- newDaemonControl True
          reloaded <- applyDaemonSignal control DaemonSighup
          reloaded @?= DaemonControlSnapshot True False 1
          drained <- applyDaemonSignal control DaemonSigint
          drained @?= DaemonControlSnapshot False True 1
      , testCase "retry policy retries transient errors" $ do
          result <-
            retryServiceAction (LinearN 2 0) (\() -> pure (Left (SETimeout "timeout"))) ()
              :: IO (Either AppError ())
          result @?= Left (PulsarFailed "timeout: timeout")
      , testCase "message hash dedup collapses repeated messages" $ do
          let first = eventIdFromPayload (ByteString.pack "payload")
              second = eventIdFromPayload (ByteString.pack "payload")
          first @?= second
          assertBool "one side effect" (length (processAtLeastOnce [first, second]) == 1)
      , testCase "domainFor accepts fully-qualified Pulsar topics (Sprint 5.5)" $ do
          domainFor "persistent://public/default/training.command.linux-cpu" @?= Just TrainingDomain
          domainFor "persistent://public/default/tune.command.linux-cuda" @?= Just TuneDomain
          domainFor "persistent://public/default/rl.command.apple-silicon" @?= Just RlDomain
          domainFor "persistent://public/default/inference.request.linux-cpu" @?= Just InferenceDomain
      , testCase "daemon subscriptions follow BootConfig residency (Sprint 5.5)" $ do
          let clusterSubscriptions =
                daemonSubscriptionsForBootConfig
                  (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
              hostSubscriptions =
                daemonSubscriptionsForBootConfig
                  (BootConfig.defaultBootConfig AppleSilicon BootConfig.Host)
          fmap (unTopicName . daemonSubscriptionTopic) clusterSubscriptions
            @?= [ "persistent://public/default/training.command.linux-cpu"
                , "persistent://public/default/tune.command.linux-cpu"
                , "persistent://public/default/rl.command.linux-cpu"
                , "persistent://public/default/inference.request.linux-cpu"
                ]
          fmap daemonSubscriptionName clusterSubscriptions
            @?= replicate 4 "jitml-service"
          fmap (unTopicName . daemonSubscriptionTopic) hostSubscriptions
            @?= ["persistent://public/default/inference.command.apple-silicon"]
          fmap daemonSubscriptionName hostSubscriptions @?= ["jitml-host"]
      , testCase "one-shot daemon HTTP server exposes healthz" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (daemonHttpRoutes defaultDaemonRuntime) $ \port -> do
            response <- httpGet port "/healthz"
            assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
            assertBool "health body" ("\r\n\r\nok\n" `isInfixOf` response)
      , testCase
          "daemon runtime summary includes client acquisition and subscription settings (Sprints 5.4/5.5)"
          $ do
            let summary = Runtime.renderDaemonRuntimeSummary defaultDaemonRuntime
            assertBool "client acquisition section" ("client_acquisition:" `Text.isInfixOf` summary)
            assertBool
              "default MinIO endpoint"
              ("minio_endpoint: http://minio.platform.svc.cluster.local:9000" `Text.isInfixOf` summary)
            assertBool
              "default Pulsar WebSocket endpoint"
              ( "pulsar_websocket_endpoint: ws://pulsar-broker.platform.svc.cluster.local:8080/ws"
                  `Text.isInfixOf` summary
              )
            assertBool "subscription section" ("pulsar_subscriptions:" `Text.isInfixOf` summary)
            assertBool
              "default training subscription"
              ( "- persistent://public/default/training.command.linux-cpu as jitml-service"
                  `Text.isInfixOf` summary
              )
            assertBool
              "default inference subscription"
              ( "- persistent://public/default/inference.request.linux-cpu as jitml-service"
                  `Text.isInfixOf` summary
              )
            assertBool "subscription status section" ("pulsar_subscription_status:" `Text.isInfixOf` summary)
            assertBool
              "pending training subscription"
              ( "- persistent://public/default/training.command.linux-cpu as jitml-service: pending"
                  `Text.isInfixOf` summary
              )
      , testCase "daemon service client interpreter exposes all capability classes (Sprint 5.4)" $ do
          let action :: ServiceClients.DaemonServiceClient ()
              action = requiresDaemonCapabilities
              settings =
                ServiceClients.daemonClientSettingsForBootConfig
                  (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
          ServiceClients.runDaemonServiceClient settings action
      , testCase "daemon acquisition records Pulsar subscription success (Sprint 5.5)" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          acquiredRuntime <-
            evalStateT
              (Runtime.acquireDaemonSubscriptions defaultDaemonRuntime)
              (SyntheticBrokerState pullRef ackRef subscribeRef)
          daemonReady acquiredRuntime @?= True
          fmap Runtime.daemonSubscriptionStatusState (Runtime.daemonSubscriptionStatuses acquiredRuntime)
            @?= [ Runtime.DaemonSubscriptionAcquired
                    (SubscriptionId "persistent://public/default/training.command.linux-cpu\njitml-service")
                , Runtime.DaemonSubscriptionAcquired
                    (SubscriptionId "persistent://public/default/tune.command.linux-cpu\njitml-service")
                , Runtime.DaemonSubscriptionAcquired
                    (SubscriptionId "persistent://public/default/rl.command.linux-cpu\njitml-service")
                , Runtime.DaemonSubscriptionAcquired
                    (SubscriptionId "persistent://public/default/inference.request.linux-cpu\njitml-service")
                ]
          subscribeLog <- readIORef subscribeRef
          length subscribeLog @?= 4
          let summary = Runtime.renderDaemonRuntimeSummary acquiredRuntime
          assertBool
            "acquired training subscription"
            ( "- persistent://public/default/training.command.linux-cpu as jitml-service: acquired persistent://public/default/training.command.linux-cpu jitml-service"
                `Text.isInfixOf` summary
            )
      , testCase "daemon consumer batch drains acquired subscriptions through router (Sprint 5.5)" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          acquiredRuntime <-
            evalStateT
              (Runtime.acquireDaemonSubscriptions defaultDaemonRuntime)
              (SyntheticBrokerState pullRef ackRef subscribeRef)
          modifyIORef'
            pullRef
            ( const
                [ ("training.command.linux-cpu", "payload-a")
                , ("training.command.linux-cpu", "payload-a")
                , ("rl.command.linux-cpu", "payload-b")
                , ("unknown.command.linux-cpu", "payload-c")
                ]
            )
          dispatchRef <- newIORef ([] :: [(EventDomain, Text)])
          (_, outcomes) <-
            evalStateT
              ( Runtime.daemonConsumerBatch
                  acquiredRuntime
                  1
                  ( \domain _eventId payload ->
                      liftIO (modifyIORef' dispatchRef ((domain, payload) :))
                        >> pure (Right ())
                  )
              )
              (SyntheticBrokerState pullRef ackRef subscribeRef)
          length outcomes @?= 4
          dispatchedCount outcomes @?= 2
          dedupCount outcomes @?= 1
          skippedCount outcomes @?= 1
          ackedPayloads <- readIORef ackRef
          length ackedPayloads @?= 4
          dispatched <- readIORef dispatchRef
          length dispatched @?= 2
      , testCase "consumerLoopExit short-circuits on first PulsarFailed (Sprint 5.5)" $ do
          -- The lifecycle exit helper walks the outcome list and surfaces
          -- the first AppError. A clean batch returns Nothing.
          let cleanBatch =
                [ ConsumerDispatched TrainingDomain (eventIdFromPayload "a")
                , ConsumerDeduplicated TuneDomain (eventIdFromPayload "a")
                ]
              poisonedBatch =
                [ ConsumerDispatched TrainingDomain (eventIdFromPayload "a")
                , ConsumerError (SETimeout "ack budget exhausted")
                , ConsumerDispatched RlDomain (eventIdFromPayload "b")
                ]
          Runtime.consumerLoopExit cleanBatch @?= Nothing
          Runtime.consumerLoopExit poisonedBatch
            @?= Just (PulsarFailed "timeout: ack budget exhausted")
      , testCase "Consumer ack failure surfaces AppError PulsarFailed (Sprint 5.5)" $ do
          -- A ConsumerError carrying SETimeout/SETransient/SEConflict maps
          -- to AppError PulsarFailed per the typed exit contract; a clean
          -- dispatch/dedup outcome returns Nothing.
          let timeoutOutcome = ConsumerError (SETimeout "ack timeout")
              transientOutcome = ConsumerError (SETransient "broker hiccup")
              cleanOutcome = ConsumerDispatched TrainingDomain (eventIdFromPayload "abc")
              dedupOutcome = ConsumerDeduplicated TuneDomain (eventIdFromPayload "abc")
          consumerOutcomeError timeoutOutcome
            @?= Just (PulsarFailed "timeout: ack timeout")
          consumerOutcomeError transientOutcome
            @?= Just (PulsarFailed "transient: broker hiccup")
          consumerOutcomeError cleanOutcome @?= Nothing
          consumerOutcomeError dedupOutcome @?= Nothing
      , testCase "Consumer loop dispatches, dedups, and acks against a synthetic broker" $ do
          -- Synthetic HasPulsar instance backed by an IORef pull queue +
          -- an IORef ack log. The Consumer loop reads N events, dedups the
          -- repeated EventID, and acks each delivery (including dedup hits)
          -- per the at-least-once contract.
          pullRef <-
            newIORef
              [ ("training.command.linux-cpu", "payload-a")
              , ("training.command.linux-cpu", "payload-a") -- redelivery
              , ("rl.command.linux-cpu", "payload-b")
              , ("inference.request.linux-cpu", "payload-c")
              ]
          ackRef <- newIORef ([] :: [Text])
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          dispatchRef <- newIORef ([] :: [(EventDomain, Text)])
          let router0 = emptyHandlerRouter 16
          (_, outcomes) <-
            evalStateT
              ( runConsumerLoop
                  (SubscriptionId "test-sub")
                  router0
                  4
                  ( \domain _eventId payload ->
                      liftIO (modifyIORef' dispatchRef ((domain, payload) :))
                        >> pure (Right ())
                  )
              )
              (SyntheticBrokerState pullRef ackRef subscribeRef)
          length outcomes @?= 4
          dispatchedCount outcomes @?= 3
          dedupCount outcomes @?= 1
          ackedPayloads <- readIORef ackRef
          length ackedPayloads @?= 4 -- every delivery (incl. dedup) acked
          dispatched <- readIORef dispatchRef
          length dispatched @?= 3
      , testCase "daemon handler router uses LiveConfig dedup cache size (Sprint 5.5)" $ do
          let router = Runtime.daemonHandlerRouter defaultDaemonRuntime
          dedupCacheCapacity (trainingCache router) @?= 4096
          dedupCacheCapacity (tuneCache router) @?= 4096
          dedupCacheCapacity (rlCache router) @?= 4096
          dedupCacheCapacity (inferenceCache router) @?= 4096
      , testCase "subscribeDaemonTopics calls the typed HasPulsar boundary (Sprint 5.5)" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          let subscriptions =
                take 2 $
                  daemonSubscriptionsForBootConfig
                    (BootConfig.defaultBootConfig LinuxCUDA BootConfig.Cluster)
          results <-
            evalStateT
              (subscribeDaemonTopics subscriptions)
              (SyntheticBrokerState pullRef ackRef subscribeRef)
          length results @?= 2
          traverse_
            ( either
                (const (assertBool "subscription failed" False))
                (const (pure ()))
                . snd
            )
            results
          subscribeLog <- readIORef subscribeRef
          subscribeLog
            @?= [ ("persistent://public/default/training.command.linux-cuda", "jitml-service")
                , ("persistent://public/default/tune.command.linux-cuda", "jitml-service")
                ]
      ]

-- | A synthetic `HasPulsar` instance that pulls envelopes off an IORef-backed
-- queue and records acks in another IORef. Used only by the Consumer loop
-- dedup-and-ack test above; the production daemon uses a real Pulsar client.
data SyntheticBrokerState = SyntheticBrokerState
  { syntheticPullQueue :: IORef [(Text, Text)]
  , syntheticAckLog :: IORef [Text]
  , syntheticSubscribeLog :: IORef [(Text, Text)]
  }

requiresDaemonCapabilities
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m) => m ()
requiresDaemonCapabilities =
  pure ()

instance HasPulsar (StateT SyntheticBrokerState IO) where
  pulsarPublish _ _ = pure (Right "synthetic-message-id")
  pulsarAcknowledge _ payload = do
    state <- get
    liftIO (modifyIORef' (syntheticAckLog state) (payload :))
    pure (Right ())
  pulsarSubscribe (TopicName topic) subscriptionName = do
    state <- get
    liftIO (modifyIORef' (syntheticSubscribeLog state) (++ [(topic, subscriptionName)]))
    pure (Right (SubscriptionId (topic <> "\n" <> subscriptionName)))
  pulsarSeek _ _ = pure (Right ())
  pulsarConsume _ = do
    state <- get
    pending <- liftIO (readIORef (syntheticPullQueue state))
    case pending of
      [] -> pure (Left (SETransient "synthetic queue exhausted"))
      (envelope : rest) -> do
        liftIO (modifyIORef' (syntheticPullQueue state) (const rest))
        pure (Right envelope)

dispatchedCount :: [ConsumerOutcome] -> Int
dispatchedCount = length . filter isDispatched
 where
  isDispatched (ConsumerDispatched _ _) = True
  isDispatched _ = False

dedupCount :: [ConsumerOutcome] -> Int
dedupCount = length . filter isDedup
 where
  isDedup (ConsumerDeduplicated _ _) = True
  isDedup _ = False

skippedCount :: [ConsumerOutcome] -> Int
skippedCount = length . filter isSkipped
 where
  isSkipped (ConsumerSkippedUnroutable _) = True
  isSkipped _ = False

httpGet :: Int -> String -> IO String
httpGet port path =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> ioError (userError "no address for daemon test client")
      addr : _ ->
        bracket (openSocket addr) close $ \client -> do
          sendAll client (ByteString.pack ("GET " <> path <> " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"))
          ByteString.unpack <$> recv client 4096

openSocket :: AddrInfo -> IO Socket
openSocket addr = do
  client <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect client (addrAddress addr)
  pure client

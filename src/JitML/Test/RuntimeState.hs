{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.RuntimeState
  ( runtimeStateTests
  )
where

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Service.InferenceBatch
  ( BatchPolicy
  , batchMaximumLatencyMicros
  , batchMaximumSize
  , mkBatchPolicy
  )
import JitML.Service.Lifecycle (LifecyclePhase (Serve))
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Logger (emitDaemonLog, newDaemonLogger)
import JitML.Service.Retry
  ( RetryPolicy (..)
  , ServiceError (SETransient)
  , retryServiceActionWith
  )
import JitML.Service.RuntimeState
  ( DaemonState
  , daemonReadyEvidence
  , daemonStateDetail
  , daemonStateDraining
  , daemonStateLabel
  , daemonStateReady
  , initialDaemonState
  , initialDaemonStateWithTopicFamily
  , readyConsumerConnections
  , recordClientProbesSucceeded
  , recordConsumerConnected
  , recordConsumerDisconnected
  , recordMetalAcquired
  , recordTopicFamilyReconciled
  )
import JitML.Service.Signal
  ( DaemonControl
  , DaemonControlSnapshot (..)
  , DaemonSignal (..)
  , applyDaemonLiveConfig
  , applyDaemonSignal
  , newDaemonControl
  , newDaemonControlWithLiveConfig
  , readDaemonControl
  , snapshotDraining
  , snapshotLiveConfig
  , snapshotReady
  , snapshotReloadGeneration
  )

runtimeStateTests :: TestTree
runtimeStateTests =
  testGroup
    "RuntimeState"
    [ testCase "startup cannot be ready before persistent connections and probes" $ do
        daemonStateLabel linuxStarting @?= "starting"
        daemonStateDetail linuxStarting @?= "awaiting consumer-connections"
        daemonStateReady linuxStarting @?= False
    , topicFamilyEvidenceTests
    , coordinatorReadinessTests
    , testCase "empty evidence sets cannot manufacture readiness" $ do
        let noConsumers = initialDaemonState False [] probes
            noProbes = initialDaemonState False topics []
        daemonStateLabel noConsumers @?= "degraded"
        daemonStateReady noConsumers @?= False
        daemonStateLabel noProbes @?= "degraded"
        daemonStateReady noProbes @?= False
    , testCase "client probes cannot manufacture readiness before connections" $ do
        let wrongStage = recordClientProbesSucceeded probes linuxStarting
        daemonStateLabel wrongStage @?= "degraded"
        daemonStateReady wrongStage @?= False
    , testCase "Metal, connection, and probe evidence promote exactly to Ready" $ do
        let metalStarting = initialDaemonState True topics probes
            metalReady = recordMetalAcquired "fixed bridge + runtime" metalStarting
            connected = connectAll metalReady
            ready = recordClientProbesSucceeded probes connected
        daemonStateReady metalStarting @?= False
        daemonStateReady metalReady @?= False
        daemonStateReady connected @?= False
        daemonStateReady ready @?= True
        (length . readyConsumerConnections <$> daemonReadyEvidence ready) @?= Just 2
    , testCase "disconnect degrades and a higher-generation reconnect restores evidence" $ do
        let ready = recordClientProbesSucceeded probes (connectAll linuxStarting)
            disconnected = recordConsumerDisconnected "topic-a" "socket closed" ready
            reconnected = recordConsumerConnected "topic-a" 2 disconnected
        daemonStateLabel disconnected @?= "degraded"
        daemonStateReady disconnected @?= False
        daemonStateReady reconnected @?= True
    , testCase "signal control stores one closed state and an orthogonal reload generation" $ do
        let ready = recordClientProbesSucceeded probes (connectAll linuxStarting)
        control <- newDaemonControl ready
        requested <- applyDaemonSignal control DaemonSighup
        snapshotReady requested @?= True
        snapshotDraining requested @?= False
        snapshotReloadGeneration requested @?= 0
        _ <- applyDaemonLiveConfig control LiveConfig.defaultLiveConfig
        unchanged <- readDaemonControl control
        snapshotReloadGeneration unchanged @?= 0
        _ <-
          applyDaemonLiveConfig
            control
            (LiveConfig.defaultLiveConfig {LiveConfig.liveDedupCacheSize = 8})
        reloaded <- readDaemonControl control
        snapshotReloadGeneration reloaded @?= 1
        draining <- applyDaemonSignal control DaemonSigterm
        snapshotReady draining @?= False
        snapshotDraining draining @?= True
        daemonStateDraining (snapshotDaemonState draining) @?= True
    , operationalLiveReloadTests
    , retryDeadlineTests
    ]

operationalLiveReloadTests :: TestTree
operationalLiveReloadTests =
  testCase "every accepted LiveConfig field changes its operational snapshot on reload" $ do
    let initialConfig =
          LiveConfig.defaultLiveConfig
            { LiveConfig.liveLogLevel = LiveConfig.Info
            , LiveConfig.liveRetryPolicy = Once
            , LiveConfig.liveInferenceBatchSize = 1
            , LiveConfig.liveInferenceMaxLatencyMillis = 2
            , LiveConfig.liveDedupCacheSize = 3
            , LiveConfig.liveDedupCacheTtlSeconds = 4
            , LiveConfig.liveDrainDeadlineSeconds = 5
            }
        reloadedConfig =
          LiveConfig.defaultLiveConfig
            { LiveConfig.liveLogLevel = LiveConfig.Debug
            , LiveConfig.liveRetryPolicy = LinearN 3 7
            , LiveConfig.liveInferenceBatchSize = 8
            , LiveConfig.liveInferenceMaxLatencyMillis = 9
            , LiveConfig.liveDedupCacheSize = 10
            , LiveConfig.liveDedupCacheTtlSeconds = 11
            , LiveConfig.liveDrainDeadlineSeconds = 12
            }
    control <- newDaemonControlWithLiveConfig linuxStarting initialConfig
    logger <- newDaemonLogger
    let readLiveConfig = snapshotLiveConfig <$> readDaemonControl control

    defaultControl <- newDaemonControlWithLiveConfig linuxStarting LiveConfig.defaultLiveConfig
    readConfiguredBatchPolicy defaultControl >>= assertBatchPolicy 64 5_000_000

    emitDaemonLog logger readLiveConfig LiveConfig.Debug Serve "filtered before reload"
      >>= (@?= False)
    runConfiguredRetry control >>= (@?= 1)
    readConfiguredBatchPolicy control >>= assertBatchPolicy 1 2_000

    _ <- applyDaemonLiveConfig control reloadedConfig
    reloaded <- readDaemonControl control
    snapshotReloadGeneration reloaded @?= 1
    snapshotLiveConfig reloaded @?= reloadedConfig

    emitDaemonLog logger readLiveConfig LiveConfig.Debug Serve "visible after reload"
      >>= (@?= True)
    runConfiguredRetry control >>= (@?= 3)
    readConfiguredBatchPolicy control >>= assertBatchPolicy 8 9_000
    LiveConfig.liveDedupCacheSize (snapshotLiveConfig reloaded) @?= 10
    LiveConfig.liveDedupCacheTtlSeconds (snapshotLiveConfig reloaded) @?= 11
    LiveConfig.liveDrainDeadlineMicros (snapshotLiveConfig reloaded) @?= 12_000_000

retryDeadlineTests :: TestTree
retryDeadlineTests =
  testCase "RetryUntil never starts an action at or after its deadline" $ do
    clockRef <- newIORef 0
    attemptsRef <- newIORef (0 :: Int)
    let clock = readIORef clockRef
        sleep delayMillis = modifyIORef' clockRef (+ delayMillis)
        action () = do
          modifyIORef' attemptsRef (+ 1)
          pure (Left (SETransient "retry") :: Either ServiceError ())
    result <- retryServiceActionWith clock sleep (RetryUntil 10) action ()
    result @?= Left (SETransient "retry")
    readIORef attemptsRef >>= (@?= 1)
    readIORef clockRef >>= (@?= 10)

runConfiguredRetry :: DaemonControl -> IO Int
runConfiguredRetry control = do
  snapshot <- readDaemonControl control
  attemptsRef <- newIORef (0 :: Int)
  let action () = do
        modifyIORef' attemptsRef (+ 1)
        pure (Left (SETransient "retry") :: Either ServiceError ())
  _ <-
    retryServiceActionWith
      (pure 0)
      (const (pure ()))
      (LiveConfig.liveRetryPolicy (snapshotLiveConfig snapshot))
      action
      ()
  readIORef attemptsRef

readConfiguredBatchPolicy :: DaemonControl -> IO BatchPolicy
readConfiguredBatchPolicy control = do
  config <- snapshotLiveConfig <$> readDaemonControl control
  case mkBatchPolicy
    (fromIntegral (LiveConfig.liveInferenceBatchSize config))
    (fromIntegral (LiveConfig.liveInferenceMaxLatencyMillis config) * 1_000) of
    Left err -> assertFailure ("validated LiveConfig produced an invalid batch policy: " <> show err)
    Right policy -> pure policy

assertBatchPolicy :: Integer -> Integer -> BatchPolicy -> IO ()
assertBatchPolicy expectedSize expectedLatency policy = do
  batchMaximumSize policy @?= fromInteger expectedSize
  batchMaximumLatencyMicros policy @?= fromInteger expectedLatency

topicFamilyEvidenceTests :: TestTree
topicFamilyEvidenceTests =
  testGroup
    "Coordinator topic-family evidence"
    [ testCase "nominal observations refine in topology order with exact dispositions" $ do
        let observations =
              [ (topicNameAt 0, PulsarBootstrap.TopicCreated)
              , (topicNameAt 1, PulsarBootstrap.TopicAlreadyExists)
              , (topicNameAt 2, PulsarBootstrap.TopicCreated)
              ]
        case PulsarBootstrap.refineTopicFamilyEvidence topicFixture (reverse observations) of
          Left err -> assertFailure ("expected exact topic-family evidence, got " <> show err)
          Right evidence -> do
            PulsarBootstrap.topicFamilyEvidenceTopics evidence @?= topicFixtureNames
            PulsarBootstrap.topicFamilyEvidenceDispositions evidence @?= observations
    , testCase "duplicate expected topic is rejected before observation checks" $
        PulsarBootstrap.refineTopicFamilyEvidence
          [topicAt 0, topicAt 0]
          [(topicNameAt 0, PulsarBootstrap.TopicCreated)]
          @?= Left (PulsarBootstrap.DuplicateExpectedTopic (topicNameAt 0))
    , testCase "duplicate observed topic is rejected" $
        PulsarBootstrap.refineTopicFamilyEvidence
          topicFixture
          [ (topicNameAt 0, PulsarBootstrap.TopicCreated)
          , (topicNameAt 0, PulsarBootstrap.TopicAlreadyExists)
          , (topicNameAt 1, PulsarBootstrap.TopicCreated)
          , (topicNameAt 2, PulsarBootstrap.TopicCreated)
          ]
          @?= Left (PulsarBootstrap.DuplicateObservedTopic (topicNameAt 0))
    , testCase "missing observed topics are reported exactly" $
        PulsarBootstrap.refineTopicFamilyEvidence
          topicFixture
          [(topicNameAt 0, PulsarBootstrap.TopicCreated)]
          @?= Left
            ( PulsarBootstrap.MissingObservedTopics
                [topicNameAt 1, topicNameAt 2]
            )
    , testCase "unexpected observed topics are reported exactly" $
        PulsarBootstrap.refineTopicFamilyEvidence
          [topicAt 0]
          [ (topicNameAt 0, PulsarBootstrap.TopicCreated)
          , ("persistent://public/default/unexpected", PulsarBootstrap.TopicCreated)
          ]
          @?= Left
            ( PulsarBootstrap.UnexpectedObservedTopics
                ["persistent://public/default/unexpected"]
            )
    , testCase "reconcile invokes every topic once and preserves dispositions" $ do
        callsRef <- newIORef []
        result <-
          PulsarBootstrap.reconcileTopicFamilyWith topicFixture $ \topic -> do
            let name = PulsarBootstrap.topicName topic
                disposition =
                  if name == topicNameAt 1
                    then PulsarBootstrap.TopicAlreadyExists
                    else PulsarBootstrap.TopicCreated
            modifyIORef' callsRef (<> [name])
            pure (Right disposition :: Either Text PulsarBootstrap.TopicCreateDisposition)
        calls <- readIORef callsRef
        calls @?= topicFixtureNames
        case result of
          Left err -> assertFailure ("expected successful topic reconciliation, got " <> show err)
          Right evidence ->
            PulsarBootstrap.topicFamilyEvidenceDispositions evidence
              @?= [ (topicNameAt 0, PulsarBootstrap.TopicCreated)
                  , (topicNameAt 1, PulsarBootstrap.TopicAlreadyExists)
                  , (topicNameAt 2, PulsarBootstrap.TopicCreated)
                  ]
    , testCase "reconcile stops at the first typed creation failure" $ do
        callsRef <- newIORef []
        result <-
          PulsarBootstrap.reconcileTopicFamilyWith topicFixture $ \topic -> do
            let name = PulsarBootstrap.topicName topic
            modifyIORef' callsRef (<> [name])
            pure $
              if name == topicNameAt 1
                then Left ("synthetic create failure" :: Text)
                else Right PulsarBootstrap.TopicCreated
        result
          @?= Left
            ( PulsarBootstrap.TopicCreateFailed
                (topicNameAt 1)
                "synthetic create failure"
            )
        readIORef callsRef >>= (@?= take 2 topicFixtureNames)
    ]

coordinatorReadinessTests :: TestTree
coordinatorReadinessTests =
  testGroup
    "Coordinator readiness"
    [ testCase "exact topics, all subscriptions, and all probes are jointly required" $ do
        daemonStateLabel coordinatorStarting @?= "starting"
        daemonStateDetail coordinatorStarting @?= "awaiting topic-family"
        daemonStateReady coordinatorStarting @?= False

        let reconciled =
              recordTopicFamilyReconciled
                (reverse topicFixtureNames)
                coordinatorStarting
            oneConsumer = recordConsumerConnected "coordinator-consumer-a" 1 reconciled
            connected = recordConsumerConnected "coordinator-consumer-b" 1 oneConsumer
            ready = recordClientProbesSucceeded probes connected
        daemonStateDetail reconciled @?= "awaiting consumer-connections"
        daemonStateReady reconciled @?= False
        daemonStateReady oneConsumer @?= False
        daemonStateDetail connected @?= "awaiting client-probes"
        daemonStateReady connected @?= False
        daemonStateReady ready @?= True
        daemonStateDetail ready @?= "reconciled-topics=3 connected-consumers=2 client-probes=3"
    , testCase "a subscription cannot connect before exact topic evidence" $ do
        let premature =
              recordConsumerConnected
                "coordinator-consumer-a"
                1
                coordinatorStarting
        daemonStateLabel premature @?= "degraded"
        daemonStateReady premature @?= False
        daemonStateDetail premature
          @?= "runtime invariant failed: consumer connected before topic reconciliation: coordinator-consumer-a"
    , testCase "incomplete, duplicate, or unexpected topic evidence cannot unlock readiness" $ do
        let missing =
              recordTopicFamilyReconciled
                (take 2 topicFixtureNames)
                coordinatorStarting
            duplicate =
              recordTopicFamilyReconciled
                [topicNameAt 0, topicNameAt 0, topicNameAt 2]
                coordinatorStarting
            unexpected =
              recordTopicFamilyReconciled
                (take 2 topicFixtureNames <> ["persistent://public/default/unexpected"])
                coordinatorStarting
        daemonStateLabel missing @?= "degraded"
        daemonStateReady missing @?= False
        daemonStateDetail missing
          @?= "runtime invariant failed: topic reconcile evidence does not match the expected topic family"
        daemonStateLabel duplicate @?= "degraded"
        daemonStateReady duplicate @?= False
        daemonStateDetail duplicate
          @?= "runtime invariant failed: topic reconcile evidence contains duplicate topics"
        daemonStateLabel unexpected @?= "degraded"
        daemonStateReady unexpected @?= False
        daemonStateDetail unexpected
          @?= "runtime invariant failed: topic reconcile evidence does not match the expected topic family"
    ]

linuxStarting :: DaemonState
linuxStarting = initialDaemonState False topics probes

coordinatorStarting :: DaemonState
coordinatorStarting =
  initialDaemonStateWithTopicFamily
    False
    topicFixtureNames
    ["coordinator-consumer-a", "coordinator-consumer-b"]
    probes

topicFixture :: [PulsarBootstrap.AnyTopic]
topicFixture = take 3 PulsarBootstrap.pulsarTopics

topicFixtureNames :: [Text]
topicFixtureNames = fmap PulsarBootstrap.topicName topicFixture

topicAt :: Int -> PulsarBootstrap.AnyTopic
topicAt index =
  case drop index topicFixture of
    topic : _ -> topic
    [] -> error "Coordinator topology contains fewer than three topics"

topicNameAt :: Int -> Text
topicNameAt = PulsarBootstrap.topicName . topicAt

topics :: [Text]
topics = ["topic-a", "topic-b"]

probes :: [Text]
probes = ["minio", "harbor", "kubectl"]

connectAll :: DaemonState -> DaemonState
connectAll =
  recordConsumerConnected "topic-b" 1
    . recordConsumerConnected "topic-a" 1

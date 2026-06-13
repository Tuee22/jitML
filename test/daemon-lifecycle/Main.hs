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
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text

import Data.ProtoLens qualified as ProtoLens
import Data.ProtoLens.Field qualified as Field
import Lens.Family2 qualified as Lens
import Proto.Jitml.Inference qualified as ProtoInference
import Proto.Jitml.Inference_Fields ()

import JitML.AppError.AppError (AppError (..))
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Service.AppleInferenceRpc qualified as AppleRpc
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , SubscriptionId (..)
  , TopicName (..)
  )
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonSubscription (..)
  , EventDomain (..)
  , EventId (..)
  , HandlerRouter (..)
  , consumerOutcomeError
  , consumerStep
  , daemonSubscriptionsForBootConfig
  , dedupCacheCapacity
  , dedupCacheKnown
  , dedupCacheTtlSeconds
  , domainFor
  , emptyHandlerRouter
  , emptyHandlerRouterWithTtl
  , eventIdFromPayload
  , processAtLeastOnce
  , routeByKindAt
  , runConsumerLoop
  , subscribeDaemonTopics
  )
import JitML.Service.Endpoints (MetricsSnapshot (..), endpointStatus, healthz, metrics, readyz)
import JitML.Service.Http (withHttpRoutesOnce)
import JitML.Service.Lifecycle (LifecyclePhase (..), lifecyclePlan)
import JitML.Service.Retry (RetryPolicy (..), ServiceError (..), retryServiceAction)
import JitML.Service.Runtime
  ( DaemonRuntime (daemonAppleMetalAcquireStatus, daemonReady)
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
import JitML.Service.Workload
  ( WorkloadEffect (..)
  , WorkloadEffectResult (..)
  , WorkloadKind (..)
  , WorkloadPlacement (..)
  , dispatchDomainPayloadForResidency
  , hostWorkloadCommandTopic
  , parseWorkloadEffectPayload
  , planWorkloadPlacement
  , renderRlJob
  , renderTrainingJob
  , renderTuneJob
  , renderWorkloadEffectPayload
  , runWorkloadEffects
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
      , testCase "inference request and result protobuf envelopes round-trip" $ do
          let request =
                Inference.InferenceRequest
                  { Inference.irCallId = "call-proto"
                  , Inference.irExperimentHash = "exp-proto"
                  , Inference.irReplyTopic = "inference.result.linux-cpu"
                  , Inference.irInput = [1.0, 2.5, -3.25]
                  }
              result =
                Inference.InferenceResult
                  { Inference.iresCallId = "call-proto"
                  , Inference.iresExperimentHash = "exp-proto"
                  , Inference.iresOutput = [0.25, 0.75]
                  }
          Inference.decodeInferenceRequestProto (Inference.encodeInferenceRequestProto request)
            @?= Right request
          Inference.decodeInferenceResultProto (Inference.encodeInferenceResultProto result)
            @?= Right result
      , testCase "local proto3 bytes decode through the proto-lens generated InferenceRequest" $ do
          let request =
                Inference.InferenceRequest
                  { Inference.irCallId = "call-cross"
                  , Inference.irExperimentHash = "exp-cross"
                  , Inference.irReplyTopic = "inference.result.linux-cpu"
                  , Inference.irInput = [0.5, -1.25, 2.5]
                  }
              localBytes = Inference.encodeInferenceRequestProto request
          case ProtoLens.decodeMessage localBytes of
            Left err ->
              assertBool ("expected proto-lens decode of local bytes, got: " <> err) False
            Right (decoded :: ProtoInference.InferenceRequest) -> do
              Lens.view (Field.field @"callId") decoded @?= Inference.irCallId request
              Lens.view (Field.field @"experimentHash") decoded
                @?= Inference.irExperimentHash request
              Lens.view (Field.field @"replyTopic") decoded
                @?= Inference.irReplyTopic request
              Lens.view (Field.field @"input") decoded
                @?= Inference.irInput request
              let reencoded = ProtoLens.encodeMessage decoded
              Inference.decodeInferenceRequestProto reencoded @?= Right request
      , testCase "Apple host inference RPC envelopes render and parse (Sprint 7.5)" $ do
          let command =
                Inference.AppleInferenceCommand
                  { Inference.appleCommandCallId = "call-apple"
                  , Inference.appleCommandKind = Inference.AppleCommandInference
                  , Inference.appleCommandModelId = "jitml-build"
                  , Inference.appleCommandStartingSnapshot = "manifest-sha"
                  , Inference.appleCommandReplyTopic = Inference.appleInferenceEventTopic
                  , Inference.appleCommandInputs = "minio://jitml-checkpoints/input-a"
                  }
              event =
                Inference.AppleInferenceEvent
                  { Inference.appleEventCallId = "call-apple"
                  , Inference.appleEventKind = Inference.AppleEventCompleted
                  , Inference.appleEventOutputRefs =
                      ["minio://jitml-checkpoints/output-a"]
                  , Inference.appleEventErrorCode = Nothing
                  , Inference.appleEventMessage = Nothing
                  }
              staleEvent =
                Inference.AppleInferenceEvent
                  { Inference.appleEventCallId = "call-apple"
                  , Inference.appleEventKind = Inference.AppleEventError
                  , Inference.appleEventOutputRefs = []
                  , Inference.appleEventErrorCode = Just "stale-starting-snapshot"
                  , Inference.appleEventMessage = Just "latest pointer advanced"
                  }
          Inference.appleInferenceCommandTopic @?= "inference.command.apple-silicon"
          Inference.appleInferenceEventTopic @?= "inference.event.apple-silicon"
          Inference.parseAppleInferenceCommand (Inference.renderAppleInferenceCommand command)
            @?= Just command
          Inference.parseAppleInferenceEvent (Inference.renderAppleInferenceEvent event)
            @?= Just event
          Inference.parseAppleInferenceEvent (Inference.renderAppleInferenceEvent staleEvent)
            @?= Just staleEvent
      , testCase "Apple host inference RPC plan publishes and correlates events (Sprint 7.5)" $ do
          clientLogRef <- newIORef []
          let request =
                Inference.InferenceRequest
                  { Inference.irCallId = "call-apple-rpc"
                  , Inference.irExperimentHash = "manifest-sha"
                  , Inference.irReplyTopic = "inference.result.apple-silicon"
                  , Inference.irInput = [1.0, -2.5]
                  }
              plan = AppleRpc.appleInferenceRpcPlan "snapshot-sha" request
              command = AppleRpc.appleRpcCommand plan
              completedEvent =
                Inference.AppleInferenceEvent
                  { Inference.appleEventCallId = "call-apple-rpc"
                  , Inference.appleEventKind = Inference.AppleEventCompleted
                  , Inference.appleEventOutputRefs =
                      ["minio://jitml-checkpoints/apple-output"]
                  , Inference.appleEventErrorCode = Nothing
                  , Inference.appleEventMessage = Nothing
                  }
              mismatchedEvent =
                completedEvent {Inference.appleEventCallId = "different-call"}
              errorEvent =
                Inference.AppleInferenceEvent
                  { Inference.appleEventCallId = "call-apple-rpc"
                  , Inference.appleEventKind = Inference.AppleEventError
                  , Inference.appleEventOutputRefs = []
                  , Inference.appleEventErrorCode = Just "stale-starting-snapshot"
                  , Inference.appleEventMessage = Just "latest pointer advanced"
                  }
              renderedPlan = AppleRpc.renderAppleInferenceRpcPlan plan
          AppleRpc.appleRpcCommandTopic plan
            @?= TopicName Inference.appleInferenceCommandTopic
          AppleRpc.appleRpcEventTopic plan
            @?= TopicName Inference.appleInferenceEventTopic
          AppleRpc.appleRpcClientReplyTopic plan
            @?= TopicName "inference.result.apple-silicon"
          Inference.appleCommandCallId command @?= "call-apple-rpc"
          Inference.appleCommandModelId command @?= "manifest-sha"
          Inference.appleCommandStartingSnapshot command @?= "snapshot-sha"
          Inference.appleCommandReplyTopic command @?= Inference.appleInferenceEventTopic
          Inference.appleCommandInputs command @?= "1.0,-2.5"
          Inference.parseAppleInferenceCommand (AppleRpc.appleRpcCommandPayload plan)
            @?= Just command
          assertBool
            "rendered plan names Apple command topic"
            (Inference.appleInferenceCommandTopic `Text.isInfixOf` renderedPlan)
          published <-
            evalStateT
              (AppleRpc.publishAppleInferenceRpcCommand plan)
              (SyntheticClientState clientLogRef)
          published @?= Right "synthetic-message-id"
          clientLog <- readIORef clientLogRef
          clientLog @?= ["pulsar:publish:inference.command.apple-silicon"]
          AppleRpc.correlateAppleInferenceEvent command completedEvent
            @?= Right ["minio://jitml-checkpoints/apple-output"]
          AppleRpc.correlateAppleInferenceEvent command mismatchedEvent
            @?= Left "apple inference event call-id mismatch: expected call-apple-rpc, got different-call"
          AppleRpc.correlateAppleInferenceEvent command errorEvent
            @?= Left "apple inference event error stale-starting-snapshot: latest pointer advanced"
      , testCase
          "Apple host<->cluster RPC round-trip: command -> host handle -> event -> correlate (Sprint 14.4)"
          $ do
            -- Sprint 14.4 — the full RPC dispatch logic, exercised deterministically
            -- through the synthetic broker: the cluster builds an
            -- AppleInferenceCommand, the host handler runs inference (stub) and
            -- emits the AppleInferenceEvent reply, and the cluster correlates it
            -- back to the staged output refs. The host also publishes the reply on
            -- inference.event.apple-silicon through HasPulsar.
            eventLogRef <- newIORef []
            let request =
                  Inference.InferenceRequest
                    { Inference.irCallId = "call-14-4"
                    , Inference.irExperimentHash = "exp-14-4"
                    , Inference.irReplyTopic = "inference.result.apple-silicon"
                    , Inference.irInput = [0.5, 1.5]
                    }
                plan = AppleRpc.appleInferenceRpcPlan "exp-14-4" request
                command = AppleRpc.appleRpcCommand plan
                stubRun cmd =
                  pure (Right ["minio://jitml-checkpoints/out/" <> Inference.appleCommandCallId cmd])
                failRun _cmd = pure (Left "metal launch failed")
            completed <- AppleRpc.handleAppleInferenceCommand stubRun command
            Inference.appleEventCallId completed @?= "call-14-4"
            Inference.appleEventKind completed @?= Inference.AppleEventCompleted
            AppleRpc.correlateAppleInferenceEvent command completed
              @?= Right ["minio://jitml-checkpoints/out/call-14-4"]
            failed <- AppleRpc.handleAppleInferenceCommand failRun command
            Inference.appleEventKind failed @?= Inference.AppleEventError
            AppleRpc.correlateAppleInferenceEvent command failed
              @?= Left "apple inference event error inference-failed: metal launch failed"
            publishedEvent <-
              evalStateT
                (AppleRpc.publishAppleInferenceEvent completed)
                (SyntheticClientState eventLogRef)
            publishedEvent @?= Right "synthetic-message-id"
            eventLog <- readIORef eventLogRef
            eventLog @?= ["pulsar:publish:inference.event.apple-silicon"]
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
            @?= [ "persistent://public/default/inference.command.apple-silicon"
                , "persistent://public/default/training.host-command.apple-silicon"
                , "persistent://public/default/tune.host-command.apple-silicon"
                , "persistent://public/default/rl.host-command.apple-silicon"
                ]
          fmap daemonSubscriptionName hostSubscriptions @?= replicate 4 "jitml-host"
          -- Sprint 14.4 — the Apple in-cluster (ForwardToHost) daemon also
          -- subscribes to inference.event.apple-silicon to receive host replies.
          let appleClusterSubscriptions =
                daemonSubscriptionsForBootConfig
                  (BootConfig.defaultBootConfig AppleSilicon BootConfig.Cluster)
          fmap (unTopicName . daemonSubscriptionTopic) appleClusterSubscriptions
            @?= [ "persistent://public/default/training.command.apple-silicon"
                , "persistent://public/default/tune.command.apple-silicon"
                , "persistent://public/default/rl.command.apple-silicon"
                , "persistent://public/default/inference.request.apple-silicon"
                , "persistent://public/default/inference.event.apple-silicon"
                ]
      , testCase "workload placement routes Apple Metal starts to host command topics (Sprint 5.11)" $ do
          planWorkloadPlacement BootConfig.Cluster WorkloadRl AppleSilicon
            @?= WorkloadHostCommand (hostWorkloadCommandTopic WorkloadRl AppleSilicon)
          planWorkloadPlacement BootConfig.Cluster WorkloadTraining LinuxCPU
            @?= WorkloadClusterJob
          publishRef <- newIORef []
          let appleRl =
                Rl.RlStart
                  Rl.StartRLRun
                    { Rl.srlExperimentHash = "apple-rl"
                    , Rl.srlAlgorithm = "PPO"
                    , Rl.srlEnvironment = "cartpole"
                    , Rl.srlSubstrate = AppleSilicon
                    , Rl.srlSeed = 42
                    , Rl.srlMaxSteps = 200
                    , Rl.srlEvalEpisodes = 2
                    }
              linuxRl =
                Rl.RlStart
                  Rl.StartRLRun
                    { Rl.srlExperimentHash = "linux-rl"
                    , Rl.srlAlgorithm = "PPO"
                    , Rl.srlEnvironment = "cartpole"
                    , Rl.srlSubstrate = LinuxCPU
                    , Rl.srlSeed = 42
                    , Rl.srlMaxSteps = 200
                    , Rl.srlEvalEpisodes = 2
                    }
          _ <-
            evalStateT
              (dispatchDomainPayloadForResidency BootConfig.Cluster RlDomain (Rl.renderRlCommand appleRl))
              (SyntheticClientState publishRef)
          appleLog <- readIORef publishRef
          appleLog
            @?= ["pulsar:publish:persistent://public/default/rl.host-command.apple-silicon"]
          linuxRef <- newIORef []
          _ <-
            evalStateT
              (dispatchDomainPayloadForResidency BootConfig.Cluster RlDomain (Rl.renderRlCommand linuxRl))
              (SyntheticClientState linuxRef)
          linuxLog <- readIORef linuxRef
          linuxLog @?= ["kubectl:apply:job/jitml-rl-linux-rl"]
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
            assertBool "Apple Metal acquire section" ("apple_metal_acquire:" `Text.isInfixOf` summary)
            assertBool "default Apple Metal acquire not required" ("  not_required" `Text.isInfixOf` summary)
            assertBool "client probe section" ("client_probe_status:" `Text.isInfixOf` summary)
            assertBool
              "pending MinIO client probe"
              ("- minio:list jitml-checkpoints: pending" `Text.isInfixOf` summary)
      , testCase "Apple Metal acquire status renders success and failure (Sprint 5.10)" $ do
          let appleRuntime =
                Runtime.daemonRuntimeForBootConfig
                  (BootConfig.defaultBootConfig AppleSilicon BootConfig.Host)
              successRuntime =
                appleRuntime
                  { daemonAppleMetalAcquireStatus =
                      Runtime.AppleMetalAcquireSucceeded
                        "apple.metal-runtime=yes apple.metal-bridge=yes"
                  }
              failureRuntime =
                appleRuntime
                  { daemonAppleMetalAcquireStatus =
                      Runtime.AppleMetalAcquireFailed
                        "apple.metal-runtime=yes apple.metal-bridge=no"
                  , daemonReady = False
                  }
              successSummary = Runtime.renderDaemonRuntimeSummary successRuntime
              failureSummary = Runtime.renderDaemonRuntimeSummary failureRuntime
          daemonAppleMetalAcquireStatus appleRuntime @?= Runtime.AppleMetalAcquirePending
          assertBool
            "successful Apple acquire status"
            ("ok apple.metal-runtime=yes apple.metal-bridge=yes" `Text.isInfixOf` successSummary)
          assertBool
            "failed Apple acquire status"
            ("failed apple.metal-runtime=yes apple.metal-bridge=no" `Text.isInfixOf` failureSummary)
          endpointStatus (readyz (daemonReady failureRuntime)) @?= 503
      , testCase "daemon service client interpreter exposes all capability classes (Sprint 5.4)" $ do
          let action :: ServiceClients.DaemonServiceClient ()
              action = requiresDaemonCapabilities
              settings =
                ServiceClients.daemonClientSettingsForBootConfig
                  (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
          ServiceClients.runDaemonServiceClient settings action
      , testCase "daemon client probe invokes non-Pulsar capability clients (Sprint 5.4)" $ do
          clientLogRef <- newIORef []
          probedRuntime <-
            evalStateT
              (Runtime.probeDaemonServiceClients defaultDaemonRuntime)
              (SyntheticClientState clientLogRef)
          daemonReady probedRuntime @?= True
          fmap Runtime.daemonClientProbeStatusState (Runtime.daemonClientProbeStatuses probedRuntime)
            @?= [ Runtime.DaemonClientProbeSucceeded "listed 0 objects"
                , Runtime.DaemonClientProbeSucceeded "listed 0 images"
                , Runtime.DaemonClientProbeSucceeded "received 1 lines"
                ]
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "minio:list:jitml-checkpoints:daemon-health/"
                , "harbor:list:library"
                , "kubectl:get:pods"
                ]
          let summary = Runtime.renderDaemonRuntimeSummary probedRuntime
          assertBool
            "successful kubectl probe in summary"
            ("- kubectl:get pods: ok received 1 lines" `Text.isInfixOf` summary)
      , testCase "daemon workload effects invoke non-Pulsar clients (Sprint 5.4)" $ do
          clientLogRef <- newIORef []
          let checkpointBlob =
                ObjectRef
                  (BucketName "jitml-checkpoints")
                  (ObjectKey "experiments/demo/blobs/blob-a")
              latestPointer =
                ObjectRef
                  (BucketName "jitml-checkpoints")
                  (ObjectKey "experiments/demo/pointers/latest")
              effects =
                [ WriteCheckpointBlob checkpointBlob (ByteString.pack "checkpoint-bytes")
                , UpdateCheckpointPointer latestPointer Nothing "manifest-a"
                , PromoteWorkloadImage
                    (ImageRef "library/jitml:build")
                    (ImageRef "library/jitml:ready")
                , RunInference
                    Inference.InferenceRequest
                      { Inference.irCallId = "call-1"
                      , Inference.irExperimentHash = "inference-exp"
                      , Inference.irReplyTopic = "inference.result.linux-cpu"
                      , Inference.irInput = [1.0, 2.0]
                      }
                , ApplyWorkloadResource (KubeResource "job/jitml-train") "kind: Job\n"
                , ReadWorkloadResourceStatus (KubeResource "job/jitml-train")
                , DeleteWorkloadResource (KubeResource "job/jitml-train")
                ]
          results <-
            evalStateT
              (runWorkloadEffects effects)
              (SyntheticClientState clientLogRef)
          results
            @?= [ Right (CheckpointBlobWritten (ETag "synthetic-etag"))
                , Right (CheckpointPointerUpdated (ETag "synthetic-etag"))
                , Right (WorkloadImagePromoted (ImageRef "library/jitml:ready"))
                , Left (SETransient "inference: weighted inference runner required")
                , Right WorkloadResourceApplied
                , Right (WorkloadResourceStatus "items: []")
                , Right WorkloadResourceDeleted
                ]
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "minio:put-blob-bytes-if-absent"
                , "minio:cas-pointer"
                , "harbor:promote"
                , "minio:read-object"
                , "minio:read-bytes"
                , "kubectl:apply:job/jitml-train"
                , "kubectl:status:job/jitml-train"
                , "kubectl:delete:job/jitml-train"
                ]
      , testCase "daemon workload dispatcher routes parsed payloads before ack (Sprint 5.4)" $ do
          clientLogRef <- newIORef []
          let checkpointBlob =
                ObjectRef
                  (BucketName "jitml-checkpoints")
                  (ObjectKey "experiments/demo/blobs/blob-a")
              imageEffect =
                PromoteWorkloadImage
                  (ImageRef "library/jitml:build")
                  (ImageRef "library/jitml:ready")
              inferenceEffect =
                RunInference
                  Inference.InferenceRequest
                    { Inference.irCallId = "call-2"
                    , Inference.irExperimentHash = "inference-exp"
                    , Inference.irReplyTopic = "inference.result.linux-cpu"
                    , Inference.irInput = [3.0]
                    }
              effects =
                [ WriteCheckpointBlob checkpointBlob (ByteString.pack "checkpoint-bytes")
                , imageEffect
                , inferenceEffect
                , ApplyWorkloadResource (KubeResource "job/jitml-train") "kind: Job\n"
                ]
              renderedPayloads = fmap renderWorkloadEffectPayload effects
          fmap parseWorkloadEffectPayload renderedPayloads @?= fmap Just effects
          dispatchResults <-
            evalStateT
              ( traverse
                  (Runtime.daemonWorkloadDispatcher TrainingDomain (eventIdFromPayload "workload"))
                  renderedPayloads
              )
              (SyntheticClientState clientLogRef)
          dispatchResults
            @?= [ Right ()
                , Right ()
                , Left (SETransient "inference: weighted inference runner required")
                , Right ()
                ]
          ignored <-
            evalStateT
              ( Runtime.daemonWorkloadDispatcher
                  TrainingDomain
                  (eventIdFromPayload "not-workload")
                  "kind: UnknownTrainingCommand\n"
              )
              (SyntheticClientState clientLogRef)
          ignored @?= Right ()
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "minio:put-blob-bytes-if-absent"
                , "harbor:promote"
                , "minio:read-object"
                , "minio:read-bytes"
                , "kubectl:apply:job/jitml-train"
                ]
      , testCase "daemon workload dispatcher can inject Linux CPU engine inference (Sprint 7.3)" $ do
          clientLogRef <- newIORef []
          let inferenceRequest =
                Inference.renderInferenceRequest
                  Inference.InferenceRequest
                    { Inference.irCallId = "call-engine"
                    , Inference.irExperimentHash = "inference-exp"
                    , Inference.irReplyTopic = "inference.result.linux-cpu"
                    , Inference.irInput = [4.0, 5.0]
                    }
              injectedRunner manifest input = do
                recordClientCall ("engine:linux-cpu:" <> Checkpoint.manifestId manifest)
                pure (Right (fmap (+ 10.0) input))
          result <-
            evalStateT
              ( Runtime.daemonWorkloadDispatcherWithInference
                  injectedRunner
                  InferenceDomain
                  (eventIdFromPayload "inference-request")
                  inferenceRequest
              )
              (SyntheticClientState clientLogRef)
          result @?= Right ()
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "minio:read-object"
                , "minio:read-bytes"
                , "engine:linux-cpu:inference-exp"
                , "pulsar:publish:inference.result.linux-cpu"
                ]
      , testCase "daemon workload dispatcher maps command envelopes to workload effects (Sprint 5.4)" $ do
          clientLogRef <- newIORef []
          let trainingStart =
                Training.renderTrainingCommand $
                  Training.TrainingStart $
                    Training.StartTraining
                      "exp-123"
                      "experiments/mnist.dhall"
                      LinuxCPU
                      11
                      2
                      32
              trainingStop =
                Training.renderTrainingCommand $
                  Training.TrainingStop $
                    Training.StopTraining "exp-123" True
              rlStart =
                Rl.renderRlCommand $
                  Rl.RlStart $
                    Rl.StartRLRun
                      "rl-exp"
                      "ppo"
                      "cartpole"
                      LinuxCPU
                      7
                      128
                      4
              tuneStart =
                Tune.renderTuneCommand $
                  Tune.TuneStart $
                    Tune.StartSweep
                      "tune-exp"
                      "experiments/mnist-tune.dhall"
                      LinuxCPU
                      99
                      3
                      100
                      "TPE"
                      "ASHA"
                      "Median"
              inferenceRequest =
                Inference.renderInferenceRequest
                  Inference.InferenceRequest
                    { Inference.irCallId = "call-3"
                    , Inference.irExperimentHash = "inference-exp"
                    , Inference.irReplyTopic = "inference.result.linux-cpu"
                    , Inference.irInput = [4.0, 5.0]
                    }
          results <-
            evalStateT
              ( sequence
                  [ Runtime.daemonWorkloadDispatcher
                      TrainingDomain
                      (eventIdFromPayload "training-start")
                      trainingStart
                  , Runtime.daemonWorkloadDispatcher
                      TrainingDomain
                      (eventIdFromPayload "training-stop")
                      trainingStop
                  , Runtime.daemonWorkloadDispatcher
                      RlDomain
                      (eventIdFromPayload "rl-start")
                      rlStart
                  , Runtime.daemonWorkloadDispatcher
                      TuneDomain
                      (eventIdFromPayload "tune-start")
                      tuneStart
                  , Runtime.daemonWorkloadDispatcher
                      InferenceDomain
                      (eventIdFromPayload "inference-request")
                      inferenceRequest
                  ]
              )
              (SyntheticClientState clientLogRef)
          results
            @?= [ Right ()
                , Right ()
                , Right ()
                , Right ()
                , Left (SETransient "inference: weighted inference runner required")
                ]
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "kubectl:apply:job/jitml-train-exp-123"
                , "kubectl:delete:job/jitml-train-exp-123"
                , "kubectl:apply:job/jitml-rl-rl-exp"
                , "kubectl:apply:job/jitml-tune-tune-exp"
                , "minio:read-object"
                , "minio:read-bytes"
                ]
      , testCase "daemon-rendered linux-cuda workload Jobs request NVIDIA RuntimeClass" $ do
          let trainingCuda =
                renderTrainingJob
                  (Training.StartTraining "cuda-train" "experiments/mnist.dhall" LinuxCUDA 11 2 32)
              rlCuda =
                renderRlJob
                  (Rl.StartRLRun "cuda-rl" "ppo" "cartpole" LinuxCUDA 7 128 4)
              tuneCuda =
                renderTuneJob
                  (Tune.StartSweep "cuda-tune" "experiments/mnist-tune.dhall" LinuxCUDA 99 3 100 "TPE" "ASHA" "Median")
              trainingCpu =
                renderTrainingJob
                  (Training.StartTraining "cpu-train" "experiments/mnist.dhall" LinuxCPU 11 2 32)
              assertCudaJob label manifest = do
                assertBool
                  (label <> " requests NVIDIA RuntimeClass")
                  ("runtimeClassName: nvidia" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " asks the NVIDIA runtime for visible devices")
                  ("NVIDIA_VISIBLE_DEVICES" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " restricts NVIDIA driver capabilities")
                  ("NVIDIA_DRIVER_CAPABILITIES" `Text.isInfixOf` manifest)
          assertCudaJob "training" trainingCuda
          assertCudaJob "rl" rlCuda
          assertCudaJob "tune" tuneCuda
          assertBool
            "linux-cpu workload Jobs do not request the NVIDIA RuntimeClass"
            (not ("runtimeClassName: nvidia" `Text.isInfixOf` trainingCpu))
      , testCase "daemon acquisition records Pulsar subscription success (Sprint 5.5)" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          seekRef <- newIORef ([] :: [(Text, Text)])
          acquiredRuntime <-
            evalStateT
              (Runtime.acquireDaemonSubscriptions defaultDaemonRuntime)
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
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
          seekRef <- newIORef ([] :: [(Text, Text)])
          acquiredRuntime <-
            evalStateT
              (Runtime.acquireDaemonSubscriptions defaultDaemonRuntime)
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
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
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
          length outcomes @?= 4
          dispatchedCount outcomes @?= 2
          dedupCount outcomes @?= 1
          skippedCount outcomes @?= 1
          ackedPayloads <- readIORef ackRef
          length ackedPayloads @?= 4
          dispatched <- readIORef dispatchRef
          length dispatched @?= 2
      , testCase "daemon consumer batch with zero budget exits without consuming" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          seekRef <- newIORef ([] :: [(Text, Text)])
          acquiredRuntime <-
            evalStateT
              (Runtime.acquireDaemonSubscriptions defaultDaemonRuntime)
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
          modifyIORef'
            pullRef
            (const [("training.command.linux-cpu", "payload-a")])
          (_, outcomes) <-
            evalStateT
              ( Runtime.daemonConsumerBatch
                  acquiredRuntime
                  0
                  (\_domain _eventId _payload -> pure (Right ()))
              )
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
          outcomes @?= []
          pendingPayloads <- readIORef pullRef
          pendingPayloads @?= [("training.command.linux-cpu", "payload-a")]
          ackedPayloads <- readIORef ackRef
          ackedPayloads @?= []
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
      , testCase "Consumer dispatch failure does not poison dedup cache and seeks cursor (Sprint 5.5)" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          seekRef <- newIORef ([] :: [(Text, Text)])
          let subscription = SubscriptionId "test-sub"
              topic = TopicName "training.command.linux-cpu"
              payload = "payload-fail"
              eventId = eventIdFromPayload (ByteString.pack "payload-fail")
              brokerState = SyntheticBrokerState pullRef ackRef subscribeRef seekRef
          (routerAfterFailure, firstOutcome) <-
            evalStateT
              ( consumerStep
                  subscription
                  (emptyHandlerRouter 16)
                  topic
                  payload
                  (\_domain _eventId _payload -> pure (Left (SETransient "handler failed")))
              )
              brokerState
          firstOutcome @?= ConsumerError (SETransient "handler failed")
          dedupCacheKnown eventId (trainingCache routerAfterFailure) @?= False
          seekLog <- readIORef seekRef
          seekLog @?= [("test-sub", unEventId eventId)]
          ackedAfterFailure <- readIORef ackRef
          ackedAfterFailure @?= []
          (routerAfterSuccess, secondOutcome) <-
            evalStateT
              ( consumerStep
                  subscription
                  routerAfterFailure
                  topic
                  payload
                  (\_domain _eventId _payload -> pure (Right ()))
              )
              brokerState
          secondOutcome @?= ConsumerDispatched TrainingDomain eventId
          dedupCacheKnown eventId (trainingCache routerAfterSuccess) @?= True
          ackedAfterSuccess <- readIORef ackRef
          ackedAfterSuccess @?= ["payload-fail"]
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
          seekRef <- newIORef ([] :: [(Text, Text)])
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
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
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
          dedupCacheTtlSeconds (trainingCache router) @?= 3600
          dedupCacheCapacity (tuneCache router) @?= 4096
          dedupCacheTtlSeconds (tuneCache router) @?= 3600
          dedupCacheCapacity (rlCache router) @?= 4096
          dedupCacheTtlSeconds (rlCache router) @?= 3600
          dedupCacheCapacity (inferenceCache router) @?= 4096
          dedupCacheTtlSeconds (inferenceCache router) @?= 3600
      , testCase "dedup cache expires entries at LiveConfig TTL boundary (Sprint 5.5)" $ do
          let eventId = eventIdFromPayload "payload-a"
              router0 = emptyHandlerRouterWithTtl 16 5
              (router1, firstSeen) = routeByKindAt 100 router0 TrainingDomain eventId
              (router2, redeliveryBeforeTtl) = routeByKindAt 104 router1 TrainingDomain eventId
              (_router3, redeliveryAtTtl) = routeByKindAt 105 router2 TrainingDomain eventId
          firstSeen @?= True
          redeliveryBeforeTtl @?= False
          redeliveryAtTtl @?= True
      , testCase "subscribeDaemonTopics calls the typed HasPulsar boundary (Sprint 5.5)" $ do
          pullRef <- newIORef []
          ackRef <- newIORef []
          subscribeRef <- newIORef ([] :: [(Text, Text)])
          seekRef <- newIORef ([] :: [(Text, Text)])
          let subscriptions =
                take 2 $
                  daemonSubscriptionsForBootConfig
                    (BootConfig.defaultBootConfig LinuxCUDA BootConfig.Cluster)
          results <-
            evalStateT
              (subscribeDaemonTopics subscriptions)
              (SyntheticBrokerState pullRef ackRef subscribeRef seekRef)
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
  , syntheticSeekLog :: IORef [(Text, Text)]
  }

newtype SyntheticClientState = SyntheticClientState
  { syntheticClientLog :: IORef [Text]
  }

requiresDaemonCapabilities
  :: (HasHarbor m, HasKubectl m, HasMinIO m, HasPulsar m) => m ()
requiresDaemonCapabilities =
  pure ()

recordClientCall :: Text -> StateT SyntheticClientState IO ()
recordClientCall entry = do
  state <- get
  liftIO (modifyIORef' (syntheticClientLog state) (++ [entry]))

instance HasMinIO (StateT SyntheticClientState IO) where
  minioPutIfAbsent ref _payload = do
    recordClientCall "minio:put-if-absent"
    pure (Right ref)
  minioReadObject _ref = do
    recordClientCall "minio:read-object"
    pure (Right (Checkpoint.manifestContentSha syntheticInferenceManifest))
  minioReadBytes _ref = do
    recordClientCall "minio:read-bytes"
    pure (Right (LazyByteString.toStrict (Checkpoint.encodeManifestCbor syntheticInferenceManifest)))
  putBlobIfAbsent _ref _payload = do
    recordClientCall "minio:put-blob-if-absent"
    pure (Right (ETag "synthetic-etag"))
  putBlobBytesIfAbsent _ref _payload = do
    recordClientCall "minio:put-blob-bytes-if-absent"
    pure (Right (ETag "synthetic-etag"))
  casPointer _ref _expected _payload = do
    recordClientCall "minio:cas-pointer"
    pure (Right (ETag "synthetic-etag"))
  listObjects (BucketName bucket) prefix = do
    recordClientCall ("minio:list:" <> bucket <> ":" <> prefix)
    pure (Right [])
  deleteObject _ref = do
    recordClientCall "minio:delete-object"
    pure (Right ())

instance HasHarbor (StateT SyntheticClientState IO) where
  harborImageExists _image = do
    recordClientCall "harbor:exists"
    pure (Right False)
  harborPromoteImage _source target = do
    recordClientCall "harbor:promote"
    pure (Right target)
  harborPushImage _image = do
    recordClientCall "harbor:push"
    pure (Right (ETag "synthetic-digest"))
  harborPullImage _image = do
    recordClientCall "harbor:pull"
    pure (Right (ETag "synthetic-digest"))
  harborListImages project = do
    recordClientCall ("harbor:list:" <> project)
    pure (Right [])

instance HasKubectl (StateT SyntheticClientState IO) where
  kubectlApply (KubeResource resource) _yaml = do
    recordClientCall ("kubectl:apply:" <> resource)
    pure (Right ())
  kubectlStatus (KubeResource resource) = do
    recordClientCall ("kubectl:status:" <> resource)
    pure (Right "items: []")
  kubectlGet (KubeResource resource) = do
    recordClientCall ("kubectl:get:" <> resource)
    pure (Right "items: []")
  kubectlDelete (KubeResource resource) = do
    recordClientCall ("kubectl:delete:" <> resource)
    pure (Right ())

instance HasPulsar (StateT SyntheticClientState IO) where
  pulsarPublish (TopicName topic) _payload = do
    recordClientCall ("pulsar:publish:" <> topic)
    pure (Right "synthetic-message-id")
  pulsarAcknowledge _topic _payload = do
    recordClientCall "pulsar:ack"
    pure (Right ())
  pulsarSubscribe (TopicName topic) subscriptionName = do
    recordClientCall ("pulsar:subscribe:" <> topic <> ":" <> subscriptionName)
    pure (Right (SubscriptionId (topic <> "\n" <> subscriptionName)))
  pulsarSeek (SubscriptionId subscription) eventId = do
    recordClientCall ("pulsar:seek:" <> subscription <> ":" <> eventId)
    pure (Right ())
  pulsarConsume _subscription =
    pure (Left (SETransient "synthetic client has no pull queue"))

syntheticInferenceManifest :: Checkpoint.CheckpointManifest
syntheticInferenceManifest =
  Checkpoint.emptyManifest
    "inference-exp"
    "latest"
    [Checkpoint.TensorBlob "dense.weight" [2] "blob-a"]

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
  pulsarSeek (SubscriptionId subscription) eventId = do
    state <- get
    liftIO (modifyIORef' (syntheticSeekLog state) (++ [(subscription, eventId)]))
    pure (Right ())
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

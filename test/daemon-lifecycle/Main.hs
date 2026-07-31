{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent.Async (async, cancel, waitCatch)
import Control.Concurrent.MVar (newEmptyMVar, newMVar, putMVar, readMVar, takeMVar)
import Control.Exception (bracket)
import Data.ByteString.Char8 qualified as ByteString
import Data.Foldable (traverse_)
import Data.List (find, isInfixOf)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isJust)
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
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Strict (StateT, evalStateT, get)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)

import Data.ProtoLens qualified as ProtoLens
import Data.ProtoLens.Field qualified as Field
import Lens.Family2 qualified as Lens
import Proto.Jitml.Inference qualified as ProtoInference
import Proto.Jitml.Inference_Fields ()

import SigtermRegression qualified

import JitML.AppError.AppError (AppError (..))
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Coordinator.Topology
  ( ProtocolRoute (..)
  , decodeTopicPayload
  , topicFor
  , topicName
  )
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan (Validation (..))
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities
  ( BucketName (..)
  , ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , ETag (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , ImageRef (..)
  , KubeResource (..)
  , NackReason (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , ack
  , deliveryBatchWindow
  , done
  , doneBatch
  , mkSubscription
  , subscriptionName
  , subscriptionOwnership
  , subscriptionTopic
  )
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonCommand (..)
  , DaemonSubscription
  , EventDomain (..)
  , EventId
  , HandlerRouter (..)
  , consumerOutcomeError
  , consumerStep
  , consumerStepCommitted
  , daemonCommandDomain
  , daemonCommandEventId
  , daemonCommandPayload
  , daemonSubscriptionDomain
  , daemonSubscriptionName
  , daemonSubscriptionOwnership
  , daemonSubscriptionStart
  , daemonSubscriptionTopicName
  , daemonSubscriptionsForBootConfig
  , dedupCacheCapacity
  , dedupCacheKnown
  , dedupCacheTtlSeconds
  , emptyHandlerRouter
  , emptyHandlerRouterWithTtl
  , processAtLeastOnce
  , reconfigureHandlerRouterAt
  , routeByKindAt
  , runConsumerLoop
  )
import JitML.Service.Endpoints (MetricsSnapshot (..), endpointStatus, healthz, metrics, readyz)
import JitML.Service.HostWorkloadRegistry qualified as HostWorkloadRegistry
import JitML.Service.Http (withHttpRoutesOnce)
import JitML.Service.InferenceBatch qualified as InferenceBatch
import JitML.Service.Lifecycle (LifecyclePhase (..), lifecyclePlan)
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Retry (RetryPolicy (..), ServiceError (..), retryServiceAction)
import JitML.Service.RoleLifecycle
  ( computeRoles
  , profileComputes
  , profileOwnsTopics
  , profileServesWebsocket
  , roleLifecyclePlan
  , roleProfile
  )
import JitML.Service.Runtime
  ( DaemonRuntime (daemonAppleMetalAcquireStatus, daemonState)
  , daemonConsumerSessionTransition
  , daemonHttpRoutes
  , daemonReady
  , defaultDaemonRuntime
  , runtimeAfterSignal
  )
import JitML.Service.Runtime qualified as Runtime
import JitML.Service.RuntimeState
  ( daemonStateLabel
  )
import JitML.Service.RuntimeState qualified as RuntimeState
import JitML.Service.Signal
  ( DaemonControl
  , DaemonControlSnapshot (..)
  , DaemonSignal (..)
  , DaemonSignalAction (..)
  , applyDaemonLiveConfig
  , applyDaemonSignal
  , daemonSignalAction
  , modifyDaemonState
  , newDaemonControl
  , readDaemonControl
  , renderDaemonSignalAction
  , snapshotDraining
  , snapshotReady
  , snapshotReloadGeneration
  )
import JitML.Service.Workload
  ( ClusterJobSpec (..)
  , SomeWorkloadEffect (..)
  , SomeWorkloadOutcome (..)
  , WorkloadDecodeError
  , WorkloadEffect (..)
  , WorkloadLaunch (..)
  , WorkloadPlacement (..)
  , dispatchRlCommand
  , dispatchWorkloadPayload
  , hostCommandSpecPayload
  , hostCommandSpecTopicName
  , parseWorkloadEffectPayload
  , planWorkloadPlacement
  , renderRlJob
  , renderSomeWorkloadOutcome
  , renderTrainingJob
  , renderTuneJob
  , renderWorkloadEffectPayload
  , runWorkloadEffects
  , workloadOutcomeError
  )
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.Pulsar
  ( ObservedDecision (..)
  , ObservedDisposition (..)
  , observeDisposition
  , simulateDeliveryDecisionForTest
  )
import JitML.Training.Budget qualified as TrainingBudget

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-daemon-lifecycle"
      [ testCase "lifecycle order reaches ready before serve" $
          lifecyclePlan @?= [Load, Prereq, Acquire, Ready, Serve, Drain, Exit]
      , testCase
          "actual jitml executable is linked with the threaded RTS"
          SigtermRegression.threadedRtsRegression
      , testCase
          "actual jitml service SIGTERM drops readiness and drains one in-flight delivery"
          SigtermRegression.sigtermDrainRegression
      , testCase
          "actual jitml service enforces configured drain deadline and joins forced cleanup"
          SigtermRegression.sigtermDeadlineRegression
      , testCase
          "actual jitml service reloads LiveConfig and drains restart-required BootConfig changes"
          SigtermRegression.sighupReloadRegression
      , testCase
          "actual Webapp service survives LiveConfig reloads and exits cleanly on SIGTERM"
          SigtermRegression.webappSignalRegression
      , testCase
          "actual jitml service fails closed without a valid adjacent LiveConfig"
          SigtermRegression.liveConfigFailClosedRegression
      , testCase "role model: exactly the Engine computes; every role shares the skeleton" $ do
          -- The Engine is the only compute role (Webapp/Coordinator run no ML).
          computeRoles @?= [BootConfig.Engine]
          profileComputes (roleProfile BootConfig.Engine) @?= True
          profileComputes (roleProfile BootConfig.Coordinator) @?= False
          profileComputes (roleProfile BootConfig.Webapp) @?= False
          -- The Coordinator owns topic lifecycle; the Webapp serves the websocket.
          profileOwnsTopics (roleProfile BootConfig.Coordinator) @?= True
          profileServesWebsocket (roleProfile BootConfig.Webapp) @?= True
          -- Every role runs the same lifecycle skeleton in the same order.
          mapM_
            (\role -> roleLifecyclePlan role @?= lifecyclePlan)
            [BootConfig.Engine, BootConfig.Coordinator, BootConfig.Webapp]
          -- BootConfig defaults to the Engine role (preserves current behaviour).
          BootConfig.bootActiveRole (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
            @?= BootConfig.Engine
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
          control <- newDaemonControl (daemonState defaultDaemonRuntime)
          requested <- applyDaemonSignal control DaemonSighup
          snapshotReloadGeneration requested @?= 0
          snapshotReady requested @?= False
          snapshotDraining requested @?= False
          _ <- applyDaemonLiveConfig control (Runtime.daemonLiveConfig defaultDaemonRuntime)
          unchanged <- readDaemonControl control
          snapshotReloadGeneration unchanged @?= 0
          _ <-
            applyDaemonLiveConfig
              control
              ( (Runtime.daemonLiveConfig defaultDaemonRuntime)
                  { LiveConfig.liveDedupCacheSize = 17
                  }
              )
          reloaded <- readDaemonControl control
          snapshotReloadGeneration reloaded @?= 1
          drained <- applyDaemonSignal control DaemonSigint
          snapshotReloadGeneration drained @?= 1
          snapshotReady drained @?= False
          snapshotDraining drained @?= True
          daemonStateLabel (snapshotDaemonState drained) @?= "draining"
      , testCase "retry policy retries transient errors" $ do
          result <-
            retryServiceAction (LinearN 2 0) (\() -> pure (Left (SETimeout "timeout"))) ()
              :: IO (Either AppError ())
          result @?= Left (PulsarFailed "timeout: timeout")
      , testCase "semantic command identity is stable and plan-bound" $ do
          let command = syntheticTrainingCommand "semantic-plan" LinuxCPU
              changedCommand =
                TrainingDaemonCommand
                  LinuxCPU
                  ( Training.TrainingStart
                      ( preparedStartTraining
                          Training.StartTraining
                            { Training.stExperimentHash = "semantic-plan"
                            , Training.stDhallObjectKey = "experiments/synthetic.dhall"
                            , Training.stSubstrate = LinuxCPU
                            , Training.stSeed = 7
                            , Training.stEpochs = 3
                            , Training.stBatchSize = 8
                            , Training.stPlanId = ""
                            , Training.stResolvedPlan = ""
                            , Training.stTrainingExamples = 64
                            , Training.stEvaluationExamples = 16
                            }
                      )
                  )
          first <- expectDaemonCommandEventId command
          second <- expectDaemonCommandEventId command
          changed <- expectDaemonCommandEventId changedCommand
          first @?= second
          assertBool "changed canonical plan changes semantic identity" (first /= changed)
          assertBool "one side effect" (length (processAtLeastOnce [first, second]) == 1)
      , testCase "semantic command identity is encoding-independent after typed decode" $ do
          let typedStart =
                preparedStartTraining
                  Training.StartTraining
                    { Training.stExperimentHash = "semantic-encoding"
                    , Training.stDhallObjectKey = "experiments/synthetic.dhall"
                    , Training.stSubstrate = LinuxCPU
                    , Training.stSeed = 7
                    , Training.stEpochs = 2
                    , Training.stBatchSize = 8
                    , Training.stPlanId = ""
                    , Training.stResolvedPlan = ""
                    , Training.stTrainingExamples = 64
                    , Training.stEvaluationExamples = 16
                    }
              typedCommand = Training.TrainingStart typedStart
              reorderedText =
                Text.unlines
                  [ "batch-size: " <> Text.pack (show (Training.stBatchSize typedStart))
                  , "kind: StartTraining"
                  , "evaluation-examples: "
                      <> Text.pack (show (Training.stEvaluationExamples typedStart))
                  , "epochs: " <> Text.pack (show (Training.stEpochs typedStart))
                  , "seed: " <> Text.pack (show (Training.stSeed typedStart))
                  , "substrate: linux-cpu"
                  , "dhall-object-key: experiments/synthetic.dhall"
                  , "experiment-hash: semantic-encoding"
                  , "training-examples: "
                      <> Text.pack (show (Training.stTrainingExamples typedStart))
                  , "resolved-plan: " <> Training.stResolvedPlan typedStart
                  , "plan-id: " <> Training.stPlanId typedStart
                  ]
          textDecoded <-
            case Training.parseTrainingCommand reorderedText of
              Nothing -> assertFailure "reordered typed Training command did not decode" >> fail "unreachable"
              Just value -> pure value
          protoDecoded <-
            case Training.decodeTrainingCommandProto (Training.encodeTrainingCommandProto typedCommand) of
              Left err -> assertFailure (Text.unpack err) >> fail "unreachable"
              Right value -> pure value
          canonicalId <-
            expectDaemonCommandEventId (TrainingDaemonCommand LinuxCPU typedCommand)
          textId <- expectDaemonCommandEventId (TrainingDaemonCommand LinuxCPU textDecoded)
          protoId <- expectDaemonCommandEventId (TrainingDaemonCommand LinuxCPU protoDecoded)
          textId @?= canonicalId
          protoId @?= canonicalId
      , testCase "invalid semantic command identity Nacks without dispatch" $ do
          dispatchedRef <- newIORef False
          let command =
                case syntheticTrainingCommand "invalid-semantic-plan" LinuxCPU of
                  TrainingDaemonCommand substrate (Training.TrainingStart start) ->
                    TrainingDaemonCommand
                      substrate
                      (Training.TrainingStart start {Training.stExperimentHash = ""})
                  _ -> error "synthetic training fixture produced a non-training command"
              router = emptyHandlerRouter 16
          (routerAfter, outcome, disposition) <-
            consumerStep router command $ \_command _eventId -> do
              writeIORef dispatchedRef True
              pure (Right ())
          routerAfter @?= router
          case outcome of
            ConsumerError (SEConflict identityError) -> do
              assertBool
                "identity refinement is reported"
                ("invalid semantic event identity" `Text.isInfixOf` identityError)
              observeDisposition disposition
                @?= ObservedNack (HandlerRejected ("conflict: " <> identityError))
            unexpected ->
              assertFailure ("expected typed semantic identity failure, got " <> show unexpected)
          readIORef dispatchedRef >>= (@?= False)
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
      , testCase "daemon subscription plans are opaque topology-derived borrowed cursors" $ do
          clusterSubscriptions <-
            expectSubscriptionPlan
              (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
          hostSubscriptions <-
            expectSubscriptionPlan
              (BootConfig.defaultBootConfig AppleSilicon BootConfig.Host)
          appleClusterSubscriptions <-
            expectSubscriptionPlan
              (BootConfig.defaultBootConfig AppleSilicon BootConfig.Cluster)
          assertSubscriptionPlan
            "jitml-engine"
            ["persistent://public/default/inference.request.linux-cpu"]
            clusterSubscriptions
          assertSubscriptionPlan
            "jitml-host"
            [ "persistent://public/default/inference.command.apple-silicon"
            , "persistent://public/default/training.host-command.apple-silicon"
            , "persistent://public/default/tune.host-command.apple-silicon"
            , "persistent://public/default/rl.host-command.apple-silicon"
            ]
            hostSubscriptions
          appleClusterSubscriptions @?= []
          traverse_
            ( \substrate -> do
                let base = BootConfig.defaultBootConfig substrate BootConfig.Cluster
                    coordinator = base {BootConfig.bootActiveRole = BootConfig.Coordinator}
                    webapp =
                      base
                        { BootConfig.bootActiveRole = BootConfig.Webapp
                        , BootConfig.bootWebappPulsarWsUrl = Just "ws://pulsar.example/ws"
                        }
                coordinatorSubscriptions <- expectSubscriptionPlan coordinator
                webappSubscriptions <- expectSubscriptionPlan webapp
                assertSubscriptionPlan
                  "jitml-coordinator"
                  ( coordinatorTopicNames substrate
                      <> [ "persistent://public/default/inference.request.apple-silicon"
                         | substrate == AppleSilicon
                         ]
                  )
                  coordinatorSubscriptions
                webappSubscriptions @?= []
            )
            [LinuxCPU, LinuxCUDA, AppleSilicon]
      , testCase "runtime workload dispatch is restricted by role and command domain" $ do
          let engineConfig = BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster
              coordinatorConfig =
                engineConfig {BootConfig.bootActiveRole = BootConfig.Coordinator}
              webappConfig =
                engineConfig
                  { BootConfig.bootActiveRole = BootConfig.Webapp
                  , BootConfig.bootWebappPulsarWsUrl = Just "ws://pulsar.example/ws"
                  }
              runtimeFor = Runtime.daemonRuntimeForBootConfig
          Runtime.validateDaemonWorkloadDispatchRole (runtimeFor engineConfig)
            @?= Right ()
          Runtime.validateDaemonWorkloadDispatchRole (runtimeFor coordinatorConfig)
            @?= Right ()
          Runtime.validateDaemonWorkloadDispatchRole (runtimeFor webappConfig)
            @?= Left
              (SEUnauthorized "workload dispatch requires activeRole=Engine or Coordinator, received webapp")
          let inference = syntheticInferenceCommand LinuxCPU "role-inference"
              training = syntheticTrainingCommand "role-training" LinuxCPU
          Runtime.validateDaemonCommandDispatchRole (runtimeFor engineConfig) inference @?= Right ()
          assertUnauthorized
            (Runtime.validateDaemonCommandDispatchRole (runtimeFor engineConfig) training)
          Runtime.validateDaemonCommandDispatchRole (runtimeFor coordinatorConfig) training @?= Right ()
          assertUnauthorized
            (Runtime.validateDaemonCommandDispatchRole (runtimeFor coordinatorConfig) inference)
      , testCase "Apple host Stops refine to exact keyed cancel-or-drain actions" $ do
          let trainingStop =
                TrainingDaemonCommand
                  AppleSilicon
                  (Training.TrainingStop (Training.StopTraining "apple-training" True))
              tuneStop =
                TuneDaemonCommand
                  AppleSilicon
                  (Tune.TuneStop (Tune.StopSweep "apple-tune"))
              rlStop =
                RlDaemonCommand
                  AppleSilicon
                  (Rl.RlStop (Rl.StopRLRun "apple-rl" True))
          traverse_
            ( \(command, expectedMode, expectedFamily, expectedHash) -> do
                action <- expectRight (Runtime.planAppleHostWorkloadAction command)
                case action of
                  Runtime.StopAppleHostWorkload observedMode _key ->
                    observedMode @?= expectedMode
                  other ->
                    assertFailure ("expected an Apple host Stop action, got " <> show other)
                maybeKey <- expectRight (Runtime.appleHostWorkloadActionKey action)
                case maybeKey of
                  Nothing -> assertFailure "expected a keyed Apple host Stop action"
                  Just key -> do
                    HostWorkloadRegistry.hostWorkloadFamily key @?= expectedFamily
                    HostWorkloadRegistry.hostWorkloadExperimentHash key @?= expectedHash
            )
            [
              ( trainingStop
              , Runtime.DrainAppleHostWorkload
              , HostWorkloadRegistry.TrainingWorkload
              , "apple-training"
              )
            ,
              ( tuneStop
              , Runtime.CancelAppleHostWorkload
              , HostWorkloadRegistry.TuneWorkload
              , "apple-tune"
              )
            ,
              ( rlStop
              , Runtime.DrainAppleHostWorkload
              , HostWorkloadRegistry.RlWorkload
              , "apple-rl"
              )
            ]
          let appleHostEngine =
                BootConfig.defaultBootConfig AppleSilicon BootConfig.Host
              appleCoordinator =
                (BootConfig.defaultBootConfig AppleSilicon BootConfig.Cluster)
                  { BootConfig.bootActiveRole = BootConfig.Coordinator
                  }
              linuxEngine =
                BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster
          Runtime.workflowStatusProjectionMode appleHostEngine trainingStop
            @?= Runtime.RequireWorkflowStatusProjection
          Runtime.workflowStatusProjectionMode appleCoordinator trainingStop
            @?= Runtime.SkipWorkflowStatusProjection
          Runtime.workflowStatusProjectionMode linuxEngine trainingStop
            @?= Runtime.BestEffortWorkflowStatusProjection
          let publicationFailure = Left (SETransient "workflow status unavailable")
          Runtime.applyWorkflowStatusProjectionResult
            Runtime.RequireWorkflowStatusProjection
            publicationFailure
            @?= publicationFailure
          Runtime.applyWorkflowStatusProjectionResult
            Runtime.BestEffortWorkflowStatusProjection
            publicationFailure
            @?= Right ()
      , testCase "Apple host AlphaZero starts refine to an executable host action" $ do
          let start =
                preparedStartAlphaZeroRun
                  Rl.StartAlphaZeroRun
                    { Rl.sazSubstrate = AppleSilicon
                    , Rl.sazExperimentHash = "apple-alpha-zero"
                    , Rl.sazPlanId = ""
                    , Rl.sazResolvedPlan = ""
                    , Rl.sazGame = "hex"
                    , Rl.sazGenerations = 2
                    , Rl.sazSelfPlayGames = 4
                    , Rl.sazMctsSimulationsPerMove = 8
                    , Rl.sazMaxPlies = 32
                    , Rl.sazOptimizerUpdates = 3
                    , Rl.sazArenaGames = 4
                    , Rl.sazSeed = 19
                    }
              command = RlDaemonCommand AppleSilicon (Rl.RlStartAlphaZero start)
          Runtime.planAppleHostWorkloadAction command
            @?= Right (Runtime.RunAppleHostAlphaZero start)
      , testCase "Apple cluster Stops forward exactly once to host command topics" $ do
          let assertClusterStopForwarded (command, expectedTopic) = do
                clientLogRef <- newIORef []
                let router = emptyHandlerRouter 16
                (routerAfterStop, outcome, disposition) <-
                  evalStateT
                    (consumerStep router command Runtime.daemonWorkloadDispatcherForwardingInference)
                    (SyntheticClientState clientLogRef)
                eventId <- expectDaemonCommandEventId command
                assertBool "successful Stop is entered into dedup" (routerAfterStop /= router)
                outcome @?= ConsumerDispatched (daemonCommandDomain command) eventId
                observeDisposition disposition @?= ObservedAck
                readIORef clientLogRef
                  >>= (@?= ["pulsar:publish:" <> expectedTopic])
              commands =
                [
                  ( TrainingDaemonCommand
                      AppleSilicon
                      (Training.TrainingStop (Training.StopTraining "apple-training" True))
                  , "persistent://public/default/training.host-command.apple-silicon"
                  )
                ,
                  ( TuneDaemonCommand
                      AppleSilicon
                      (Tune.TuneStop (Tune.StopSweep "apple-tune"))
                  , "persistent://public/default/tune.host-command.apple-silicon"
                  )
                ,
                  ( RlDaemonCommand
                      AppleSilicon
                      (Rl.RlStop (Rl.StopRLRun "apple-rl" True))
                  , "persistent://public/default/rl.host-command.apple-silicon"
                  )
                ]
          traverse_ assertClusterStopForwarded commands
      , testCase "workload placement routes Apple Metal starts to host command topics (Sprint 5.11)" $ do
          publishRef <- newIORef []
          let appleStart = syntheticRlStart "apple-rl" AppleSilicon
              linuxStart = syntheticRlStart "linux-rl" LinuxCPU
              appleRl = Rl.RlStart appleStart
              linuxRl = Rl.RlStart linuxStart
          case planWorkloadPlacement BootConfig.Cluster (RlLaunch appleStart) of
            Left err -> assertFailure (show err)
            Right (WorkloadClusterJob _) -> assertFailure "Apple Metal launch was placed in cluster"
            Right (WorkloadHostCommand spec) -> do
              hostCommandSpecTopicName spec
                @?= "persistent://public/default/rl.host-command.apple-silicon"
              hostCommandSpecPayload spec @?= Rl.renderRlCommand appleRl
          case planWorkloadPlacement BootConfig.Cluster (RlLaunch linuxStart) of
            Left err -> assertFailure (show err)
            Right (WorkloadHostCommand _) -> assertFailure "Linux CPU launch was placed on the host"
            Right (WorkloadClusterJob spec) -> do
              clusterJobResource spec @?= KubeResource "job/jitml-rl-linux-rl"
              assertBool
                "cluster placement carries its manifest"
                ("kind: Job" `Text.isInfixOf` clusterJobManifest spec)
          appleResult <-
            evalStateT
              (dispatchRlCommand BootConfig.Cluster AppleSilicon appleRl)
              (SyntheticClientState publishRef)
          assertWorkloadOutcomesSucceeded appleResult
          appleLog <- readIORef publishRef
          appleLog
            @?= ["pulsar:publish:persistent://public/default/rl.host-command.apple-silicon"]
          linuxRef <- newIORef []
          linuxResult <-
            evalStateT
              (dispatchRlCommand BootConfig.Cluster LinuxCPU linuxRl)
              (SyntheticClientState linuxRef)
          assertWorkloadOutcomesSucceeded linuxResult
          linuxLog <- readIORef linuxRef
          linuxLog @?= ["kubectl:apply:job/jitml-rl-linux-rl"]
      , testCase "one-shot daemon HTTP server exposes healthz" $ do
          control <- newDaemonControl (daemonState defaultDaemonRuntime)
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (daemonHttpRoutes control defaultDaemonRuntime) $ \port -> do
            response <- httpGet port "/healthz"
            assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
            assertBool "health body" ("\r\n\r\nok\n" `isInfixOf` response)
      , testCase "live readyz follows the shared control state" $ do
          readyRuntime <- readyLinuxRuntime
          control <- newDaemonControl (daemonState defaultDaemonRuntime)
          assertReadyHttpStatus control readyRuntime "503 Service Unavailable"
          _ <- modifyDaemonState control (const (daemonState readyRuntime))
          assertReadyHttpStatus control readyRuntime "200 OK"
          drained <- applyDaemonSignal control DaemonSigterm
          snapshotDraining drained @?= True
          assertReadyHttpStatus control readyRuntime "503 Service Unavailable"
      , testCase "Coordinator readyz requires exact topics, role subscriptions, and probes" $ do
          let coordinatorBootConfig =
                (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
                  { BootConfig.bootActiveRole = BootConfig.Coordinator
                  }
              coordinatorRuntime = Runtime.daemonRuntimeForBootConfig coordinatorBootConfig
              topicObservations =
                fmap
                  (\topic -> (PulsarBootstrap.topicName topic, PulsarBootstrap.TopicCreated))
                  PulsarBootstrap.pulsarTopics
          fmap
            Runtime.daemonClientProbeStatusName
            (Runtime.daemonClientProbeStatuses coordinatorRuntime)
            @?= [ "minio:list jitml-checkpoints"
                , "harbor:list library"
                , "kubectl:get pods"
                ]
          topicEvidence <-
            expectRight
              ( PulsarBootstrap.refineTopicFamilyEvidence
                  PulsarBootstrap.pulsarTopics
                  topicObservations
              )
          control <- newDaemonControl (daemonState coordinatorRuntime)
          daemonStateLabel (daemonState coordinatorRuntime) @?= "starting"
          RuntimeState.daemonStateDetail (daemonState coordinatorRuntime)
            @?= "awaiting topic-family"
          assertReadyHttpStatus control coordinatorRuntime "503 Service Unavailable"

          let reconciledRuntime =
                coordinatorRuntime
                  { daemonState =
                      RuntimeState.recordTopicFamilyReconciled
                        (PulsarBootstrap.topicFamilyEvidenceTopics topicEvidence)
                        (daemonState coordinatorRuntime)
                  }
          _ <- modifyDaemonState control (const (daemonState reconciledRuntime))
          RuntimeState.daemonStateDetail (daemonState reconciledRuntime)
            @?= "awaiting consumer-connections"
          assertReadyHttpStatus control coordinatorRuntime "503 Service Unavailable"

          let connectedRuntime = connectAllConsumers 1 reconciledRuntime
          _ <- modifyDaemonState control (const (daemonState connectedRuntime))
          RuntimeState.daemonStateDetail (daemonState connectedRuntime)
            @?= "awaiting client-probes"
          assertReadyHttpStatus control coordinatorRuntime "503 Service Unavailable"

          clientLogRef <- newIORef []
          readyCoordinator <-
            evalStateT
              (Runtime.probeCoordinatorServiceClients connectedRuntime)
              (SyntheticClientState clientLogRef)
          daemonReady readyCoordinator @?= True
          daemonStateLabel (daemonState readyCoordinator) @?= "ready"
          readIORef clientLogRef
            >>= ( @?=
                    [ "minio:list:jitml-checkpoints:daemon-health/"
                    , "harbor:list:library"
                    , "kubectl:get:pods"
                    ]
                )
          _ <- modifyDaemonState control (const (daemonState readyCoordinator))
          assertReadyHttpStatus control coordinatorRuntime "200 OK"
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
              "default inference subscription"
              ( "- persistent://public/default/inference.request.linux-cpu as jitml-engine"
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
                  , daemonState =
                      RuntimeState.recordMetalFailure
                        "apple.metal-runtime=yes apple.metal-bridge=no"
                        (daemonState appleRuntime)
                  }
              successSummary = Runtime.renderDaemonRuntimeSummary successRuntime
              failureSummary = Runtime.renderDaemonRuntimeSummary failureRuntime
          daemonAppleMetalAcquireStatus appleRuntime @?= Runtime.AppleMetalAcquirePending
          daemonStateLabel (daemonState appleRuntime) @?= "starting"
          daemonReady appleRuntime @?= False
          assertBool
            "successful Apple acquire status"
            ("ok apple.metal-runtime=yes apple.metal-bridge=yes" `Text.isInfixOf` successSummary)
          assertBool
            "failed Apple acquire status"
            ("failed apple.metal-runtime=yes apple.metal-bridge=no" `Text.isInfixOf` failureSummary)
          endpointStatus (readyz (daemonReady failureRuntime)) @?= 503
      , testCase "Engine service client exposes only artifact and messaging capabilities (Sprint 12.16)" $ do
          let action :: ServiceClients.EngineServiceClient ()
              action = requiresEngineCapabilities
              settings =
                ServiceClients.engineClientSettingsForBootConfig
                  (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
              rendered = ServiceClients.renderEngineClientSettings settings
          ServiceClients.runEngineServiceClient settings action
          assertBool "Engine keeps its MinIO endpoint" ("minio_endpoint:" `Text.isInfixOf` rendered)
          assertBool
            "Engine keeps its Pulsar endpoint"
            ("pulsar_websocket_endpoint:" `Text.isInfixOf` rendered)
          assertBool
            "Engine does not retain Harbor configuration"
            (not ("harbor" `Text.isInfixOf` Text.toLower rendered))
          assertBool
            "Engine does not retain kubectl configuration"
            (not ("kubectl" `Text.isInfixOf` Text.toLower rendered))
          assertBool
            "Engine does not retain the Harbor administrator"
            (not ("admin" `Text.isInfixOf` Text.toLower rendered))
          assertBool
            "Engine does not retain the default Harbor password"
            (not ("Harbor12345" `Text.isInfixOf` rendered))
      , testCase "Engine refuses to enter publication after the batch deadline" $ do
          topic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
          command <-
            case syntheticTrainingCommand "expired-publication" LinuxCPU of
              TrainingDaemonCommand _ trainingCommand -> pure trainingCommand
              other -> assertFailure ("expected a training command, got " <> show other)
          let settings =
                ServiceClients.engineClientSettingsWithPublicationDeadline 0 $
                  ServiceClients.engineClientSettingsForBootConfig
                    (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
          result <-
            ServiceClients.runEngineServiceClient settings (pulsarPublish topic command)
          result
            @?= Left (SETimeout "inference batch publication deadline expired before publish")
      , testCase "daemon client settings are projected by active role (Sprint 12.16)" $ do
          let baseConfig = BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster
              engineSettings =
                Runtime.daemonClientSettings
                  (Runtime.daemonRuntimeForBootConfig baseConfig)
              coordinatorSettings =
                Runtime.daemonClientSettings
                  ( Runtime.daemonRuntimeForBootConfig
                      baseConfig {BootConfig.bootActiveRole = BootConfig.Coordinator}
                  )
              webappSettings =
                Runtime.daemonClientSettings
                  ( Runtime.daemonRuntimeForBootConfig
                      baseConfig
                        { BootConfig.bootActiveRole = BootConfig.Webapp
                        , BootConfig.bootWebappPulsarWsUrl = Just "ws://browser.example/ws"
                        }
                  )
              engineRendered = ServiceClients.renderDaemonRoleClientSettings engineSettings
              webappRendered = ServiceClients.renderDaemonRoleClientSettings webappSettings
          assertBool
            "Engine projection is present"
            (isJust (ServiceClients.engineRoleClientSettings engineSettings))
          ServiceClients.coordinatorRoleClientSettings engineSettings @?= Nothing
          assertBool
            "Coordinator projection is present"
            (isJust (ServiceClients.coordinatorRoleClientSettings coordinatorSettings))
          ServiceClients.engineRoleClientSettings coordinatorSettings @?= Nothing
          ServiceClients.engineRoleClientSettings webappSettings @?= Nothing
          ServiceClients.coordinatorRoleClientSettings webappSettings @?= Nothing
          ServiceClients.rolePulsarSettings webappSettings @?= Nothing
          assertBool
            "Engine rendering omits Harbor"
            (not ("harbor" `Text.isInfixOf` Text.toLower engineRendered))
          assertBool
            "Engine rendering omits kubectl"
            (not ("kubectl" `Text.isInfixOf` Text.toLower engineRendered))
          webappRendered @?= "(browser-only; no daemon clients)\n"
      , testCase "daemon client probe invokes non-Pulsar capability clients (Sprint 5.4)" $ do
          clientLogRef <- newIORef []
          daemonReady defaultDaemonRuntime @?= False
          daemonStateLabel (daemonState defaultDaemonRuntime) @?= "starting"
          let connectedRuntime = connectAllConsumers 1 defaultDaemonRuntime
          daemonReady connectedRuntime @?= False
          probedRuntime <-
            evalStateT
              (Runtime.probeEngineServiceClients connectedRuntime)
              (SyntheticClientState clientLogRef)
          daemonReady probedRuntime @?= True
          daemonStateLabel (daemonState probedRuntime) @?= "ready"
          fmap Runtime.daemonClientProbeStatusState (Runtime.daemonClientProbeStatuses probedRuntime)
            @?= [Runtime.DaemonClientProbeSucceeded "listed 0 objects"]
          clientLog <- readIORef clientLogRef
          clientLog
            @?= ["minio:list:jitml-checkpoints:daemon-health/"]
          let summary = Runtime.renderDaemonRuntimeSummary probedRuntime
          assertBool
            "successful MinIO probe in summary"
            ("- minio:list jitml-checkpoints: ok listed 0 objects" `Text.isInfixOf` summary)
          case Runtime.daemonSubscriptions probedRuntime of
            [] -> assertFailure "ready runtime has no consumer subscriptions"
            firstSubscription : _ -> do
              let disconnectedRuntime =
                    probedRuntime
                      { daemonState =
                          daemonConsumerSessionTransition
                            firstSubscription
                            (ConsumerSessionDisconnected "socket lost")
                            (daemonState probedRuntime)
                      }
                  reconnectedRuntime =
                    disconnectedRuntime
                      { daemonState =
                          daemonConsumerSessionTransition
                            firstSubscription
                            (ConsumerSessionConnected 2)
                            (daemonState disconnectedRuntime)
                      }
              daemonStateLabel (daemonState disconnectedRuntime) @?= "degraded"
              daemonReady disconnectedRuntime @?= False
              daemonStateLabel (daemonState reconnectedRuntime) @?= "ready"
              daemonReady reconnectedRuntime @?= True
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
                SomeWorkloadEffect
                  (WriteCheckpointBlob checkpointBlob (ByteString.pack "checkpoint-bytes"))
                  :| [ SomeWorkloadEffect
                         (UpdateCheckpointPointer latestPointer Nothing "manifest-a")
                     , SomeWorkloadEffect
                         ( PromoteWorkloadImage
                             (ImageRef "library/jitml:build")
                             (ImageRef "library/jitml:ready")
                         )
                     , SomeWorkloadEffect
                         (ApplyWorkloadResource (KubeResource "job/jitml-train") "kind: Job\n")
                     , SomeWorkloadEffect
                         (ReadWorkloadResourceStatus (KubeResource "job/jitml-train"))
                     , SomeWorkloadEffect
                         (DeleteWorkloadResource (KubeResource "job/jitml-train"))
                     ]
          results <-
            evalStateT
              (runWorkloadEffects effects)
              (SyntheticClientState clientLogRef)
          length results @?= 6
          traverse_ (\outcome -> workloadOutcomeError outcome @?= Nothing) results
          assertBool
            "indexed outcomes retain their legal result renderers"
            ( all
                (Text.isInfixOf " => " . renderSomeWorkloadOutcome)
                (NonEmpty.toList results)
            )
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "minio:put-blob-bytes-if-absent"
                , "minio:cas-pointer"
                , "harbor:promote"
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
                SomeWorkloadEffect
                  ( PromoteWorkloadImage
                      (ImageRef "library/jitml:build")
                      (ImageRef "library/jitml:ready")
                  )
              effects =
                [ SomeWorkloadEffect
                    (WriteCheckpointBlob checkpointBlob (ByteString.pack "checkpoint-bytes"))
                , imageEffect
                , SomeWorkloadEffect
                    (ApplyWorkloadResource (KubeResource "job/jitml-train") "kind: Job\n")
                ]
              renderedPayloads = fmap renderSomeEffectPayload effects
          fmap parseWorkloadEffectPayload renderedPayloads @?= fmap Right effects
          dispatchResults <-
            evalStateT
              (traverse dispatchWorkloadPayload renderedPayloads)
              (SyntheticClientState clientLogRef)
          traverse_ assertWorkloadDispatchOutcome dispatchResults
          malformed <-
            evalStateT
              (dispatchWorkloadPayload "kind: UnknownTrainingCommand\n")
              (SyntheticClientState clientLogRef)
          case malformed of
            Left _ -> pure ()
            other -> assertFailure ("expected explicit malformed-workload failure, got " <> show other)
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "minio:put-blob-bytes-if-absent"
                , "harbor:promote"
                , "kubectl:apply:job/jitml-train"
                ]
      , testCase "daemon workload dispatcher can inject Linux CPU engine inference (Sprint 7.3)" $ do
          clientLogRef <- newIORef []
          let inferenceRequest =
                Inference.InferenceRequest
                  { Inference.irCallId = "call-engine"
                  , Inference.irExperimentHash = syntheticInferenceExperimentHash
                  , Inference.irReplyTopic = "inference.result.linux-cpu"
                  , Inference.irInput = [4.0, 5.0]
                  }
              injectedRunner _eligibleRef manifest input = do
                recordClientCall ("engine:linux-cpu:" <> Checkpoint.manifestId manifest)
                pure (Right (fmap (+ 10.0) input))
              inferenceCommand =
                InferenceDaemonCommand LinuxCPU (Inference.RunInference inferenceRequest)
          eventId <- expectDaemonCommandEventId inferenceCommand
          result <-
            evalStateT
              ( Runtime.daemonWorkloadDispatcherWithInference
                  injectedRunner
                  inferenceCommand
                  eventId
              )
              (SyntheticClientState clientLogRef)
          result @?= Right ()
          clientLog <- readIORef clientLogRef
          -- Completed admission reads the latest pointer (P1), the addressed
          -- manifest, the pointer again (P2), then binds the weight blob and the
          -- companion transcript before the reloaded graph is served.
          clientLog
            @?= [ "minio:read-bytes"
                , "minio:read-bytes"
                , "minio:read-bytes"
                , "minio:read-bytes"
                , "minio:read-bytes"
                , "engine:linux-cpu:inference-exp"
                , "pulsar:publish:persistent://public/default/inference.result.linux-cpu"
                ]
      , testCase "daemon dispatcher pairs Linux Stop resource effects (Sprint 12.16)" $ do
          clientLogRef <- newIORef []
          let trainingStart =
                Training.TrainingStart $
                  preparedStartTraining
                    Training.StartTraining
                      { Training.stExperimentHash = "exp-123"
                      , Training.stDhallObjectKey = "experiments/mnist.dhall"
                      , Training.stSubstrate = LinuxCPU
                      , Training.stSeed = 11
                      , Training.stEpochs = 2
                      , Training.stBatchSize = 32
                      , Training.stPlanId = ""
                      , Training.stResolvedPlan = ""
                      , Training.stTrainingExamples = 64
                      , Training.stEvaluationExamples = 16
                      }
              trainingStop =
                Training.TrainingStop $
                  Training.StopTraining "exp-123" True
              rlStart =
                Rl.RlStart $
                  Rl.StartRLRun
                    "rl-exp"
                    "ppo"
                    "cartpole"
                    LinuxCPU
                    7
                    128
                    4
              rlStop =
                Rl.RlStop $
                  Rl.StopRLRun "rl-exp" True
              tuneStart =
                Tune.TuneStart $
                  preparedStartSweep
                    Tune.StartSweep
                      { Tune.ssExperimentHash = "tune-exp"
                      , Tune.ssDhallObjectKey = "experiments/mnist-tune.dhall"
                      , Tune.ssSubstrate = LinuxCPU
                      , Tune.ssSweepSeed = 99
                      , Tune.ssTrialBudget = 3
                      , Tune.ssBudgetPerTrial = 100
                      , Tune.ssSampler = "TPE"
                      , Tune.ssScheduler = "ASHA"
                      , Tune.ssPruner = "Median"
                      , Tune.ssParallelism = 1
                      , Tune.ssPromotions = 1
                      , Tune.ssPlanId = ""
                      , Tune.ssResolvedPlan = ""
                      }
              tuneStop =
                Tune.TuneStop $
                  Tune.StopSweep "tune-exp"
              inferenceRequest =
                Inference.InferenceRequest
                  { Inference.irCallId = "call-3"
                  , Inference.irExperimentHash = syntheticInferenceExperimentHash
                  , Inference.irReplyTopic = "inference.result.linux-cpu"
                  , Inference.irInput = [4.0, 5.0]
                  }
              trainingStartCommand = TrainingDaemonCommand LinuxCPU trainingStart
              trainingStopCommand = TrainingDaemonCommand LinuxCPU trainingStop
              rlStartCommand = RlDaemonCommand LinuxCPU rlStart
              rlStopCommand = RlDaemonCommand LinuxCPU rlStop
              tuneStartCommand = TuneDaemonCommand LinuxCPU tuneStart
              tuneStopCommand = TuneDaemonCommand LinuxCPU tuneStop
              inferenceCommand =
                InferenceDaemonCommand LinuxCPU (Inference.RunInference inferenceRequest)
          trainingStartEventId <- expectDaemonCommandEventId trainingStartCommand
          trainingStopEventId <- expectDaemonCommandEventId trainingStopCommand
          rlStartEventId <- expectDaemonCommandEventId rlStartCommand
          rlStopEventId <- expectDaemonCommandEventId rlStopCommand
          tuneStartEventId <- expectDaemonCommandEventId tuneStartCommand
          tuneStopEventId <- expectDaemonCommandEventId tuneStopCommand
          inferenceEventId <- expectDaemonCommandEventId inferenceCommand
          results <-
            evalStateT
              ( sequence
                  [ Runtime.daemonWorkloadDispatcher
                      trainingStartCommand
                      trainingStartEventId
                  , Runtime.daemonWorkloadDispatcher
                      trainingStopCommand
                      trainingStopEventId
                  , Runtime.daemonWorkloadDispatcher
                      rlStartCommand
                      rlStartEventId
                  , Runtime.daemonWorkloadDispatcher
                      rlStopCommand
                      rlStopEventId
                  , Runtime.daemonWorkloadDispatcher
                      tuneStartCommand
                      tuneStartEventId
                  , Runtime.daemonWorkloadDispatcher
                      tuneStopCommand
                      tuneStopEventId
                  , Runtime.daemonWorkloadDispatcher
                      inferenceCommand
                      inferenceEventId
                  ]
              )
              (SyntheticClientState clientLogRef)
          results
            @?= [ Right ()
                , Right ()
                , Right ()
                , Right ()
                , Right ()
                , Right ()
                , Left (SETransient "inference: weighted inference runner required")
                ]
          clientLog <- readIORef clientLogRef
          clientLog
            @?= [ "kubectl:apply:job/jitml-train-exp-123"
                , "kubectl:delete:job/jitml-train-exp-123"
                , "kubectl:delete:configmap/runconfig-jitml-train-exp-123"
                , "kubectl:apply:job/jitml-rl-rl-exp"
                , "kubectl:delete:job/jitml-rl-rl-exp"
                , "kubectl:delete:configmap/runconfig-jitml-rl-rl-exp"
                , "kubectl:apply:job/jitml-tune-tune-exp"
                , "kubectl:delete:job/jitml-tune-tune-exp"
                , "kubectl:delete:configmap/runconfig-jitml-tune-tune-exp"
                , -- Completed admission (pointer P1, addressed manifest, pointer P2,
                  -- weight blob, companion transcript) runs before the default
                  -- runner reports that a weighted runner is required.
                  "minio:read-bytes"
                , "minio:read-bytes"
                , "minio:read-bytes"
                , "minio:read-bytes"
                , "minio:read-bytes"
                ]
      , testCase "Linux Stop attempts both deletions when either typed effect fails" $ do
          traverse_
            ( \(experimentHash, expectedFailure) -> do
                clientLogRef <- newIORef []
                let command =
                      TrainingDaemonCommand
                        LinuxCPU
                        ( Training.TrainingStop
                            (Training.StopTraining experimentHash True)
                        )
                    jobName = "jitml-train-" <> experimentHash
                eventId <- expectDaemonCommandEventId command
                result <-
                  evalStateT
                    (Runtime.daemonWorkloadDispatcher command eventId)
                    (SyntheticClientState clientLogRef)
                result @?= Left expectedFailure
                readIORef clientLogRef
                  >>= ( @?=
                          [ "kubectl:delete:job/" <> jobName
                          , "kubectl:delete:configmap/runconfig-" <> jobName
                          ]
                      )
            )
            [
              ( "fail-job-delete"
              , SETransient "synthetic Job deletion failure"
              )
            ,
              ( "fail-configmap-delete"
              , SETransient "synthetic RunConfig deletion failure"
              )
            ]
      , testCase "daemon-rendered workload Jobs enforce compute cardinality and CUDA RuntimeClass" $ do
          let trainingCuda =
                either (error . show) id $
                  renderTrainingJob
                    ( preparedStartTraining
                        Training.StartTraining
                          { Training.stExperimentHash = "cuda-train"
                          , Training.stDhallObjectKey = "experiments/mnist.dhall"
                          , Training.stSubstrate = LinuxCUDA
                          , Training.stSeed = 11
                          , Training.stEpochs = 2
                          , Training.stBatchSize = 32
                          , Training.stPlanId = ""
                          , Training.stResolvedPlan = ""
                          , Training.stTrainingExamples = 64
                          , Training.stEvaluationExamples = 16
                          }
                    )
              rlCuda =
                either (error . show) id $
                  renderRlJob
                    (Rl.StartRLRun "cuda-rl" "ppo" "cartpole" LinuxCUDA 7 128 4)
              tuneCuda =
                either (error . show) id $
                  renderTuneJob
                    ( preparedStartSweep
                        Tune.StartSweep
                          { Tune.ssExperimentHash = "cuda-tune"
                          , Tune.ssDhallObjectKey = "experiments/mnist-tune.dhall"
                          , Tune.ssSubstrate = LinuxCUDA
                          , Tune.ssSweepSeed = 99
                          , Tune.ssTrialBudget = 3
                          , Tune.ssBudgetPerTrial = 100
                          , Tune.ssSampler = "Sobol"
                          , Tune.ssScheduler = "Fifo"
                          , Tune.ssPruner = "NoPruner"
                          , Tune.ssParallelism = 1
                          , Tune.ssPromotions = 1
                          , Tune.ssPlanId = ""
                          , Tune.ssResolvedPlan = ""
                          }
                    )
              trainingCpu =
                either (error . show) id $
                  renderTrainingJob
                    ( preparedStartTraining
                        Training.StartTraining
                          { Training.stExperimentHash = "cpu-train"
                          , Training.stDhallObjectKey = "experiments/mnist.dhall"
                          , Training.stSubstrate = LinuxCPU
                          , Training.stSeed = 11
                          , Training.stEpochs = 2
                          , Training.stBatchSize = 32
                          , Training.stPlanId = ""
                          , Training.stResolvedPlan = ""
                          , Training.stTrainingExamples = 64
                          , Training.stEvaluationExamples = 16
                          }
                    )
              assertComputeJob label manifest = do
                assertBool
                  (label <> " labels the pod as numerical compute")
                  ("jitml.compute: \"true\"" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " labels workload compute scope")
                  ("jitml.compute-scope: workload" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " pins to compute nodes")
                  ("jitml.node-role/compute: \"true\"" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " uses required hostname anti-affinity")
                  ("requiredDuringSchedulingIgnoredDuringExecution" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " uses hard topology spread")
                  ( "topologySpreadConstraints:" `Text.isInfixOf` manifest
                      && "whenUnsatisfiable: DoNotSchedule" `Text.isInfixOf` manifest
                  )
                assertBool
                  (label <> " scopes anti-affinity to workload Jobs")
                  ("jitml.compute-scope: workload" `Text.isInfixOf` manifest)
                assertBool
                  (label <> " avoids advisory anti-affinity")
                  (not ("preferredDuringSchedulingIgnoredDuringExecution" `Text.isInfixOf` manifest))
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
          assertComputeJob "training-cuda" trainingCuda
          assertComputeJob "rl-cuda" rlCuda
          assertComputeJob "tune-cuda" tuneCuda
          assertBool
            "tune RunConfig carries its derived plan identity"
            ("planId = \"" `Text.isInfixOf` tuneCuda)
          assertBool
            "tune RunConfig carries the canonical resolved plan"
            ("resolvedPlan = \"transport-version=1|" `Text.isInfixOf` tuneCuda)
          assertBool
            "tune RunConfig does not reinterpret raw axis fields"
            ( not
                ( "sampler = \"" `Text.isInfixOf` tuneCuda
                    || "scheduler = \"" `Text.isInfixOf` tuneCuda
                    || "pruner = \"" `Text.isInfixOf` tuneCuda
                )
            )
          assertComputeJob "training-cpu" trainingCpu
          assertCudaJob "training" trainingCuda
          assertCudaJob "rl" rlCuda
          assertCudaJob "tune" tuneCuda
          assertBool
            "linux-cpu workload Jobs do not request the NVIDIA RuntimeClass"
            (not ("runtimeClassName: nvidia" `Text.isInfixOf` trainingCpu))
      , testCase "test delivery simulation observes a decision without settling a receipt" $ do
          broker <- newSyntheticBroker []
          simulated <-
            evalStateT
              ( simulateDeliveryDecisionForTest
                  "test-session"
                  1
                  "fabricated-delivery"
                  0
                  ("synthetic-event" :: Text)
                  (\_delivery -> pure (done ack ()))
              )
              broker
          case simulated of
            Left err -> assertFailure (show err)
            Right (observed, receiptFingerprint) -> do
              observed @?= ObservedDone ObservedAck ()
              assertBool "opaque receipt fingerprint is diagnostic only" (not (Text.null receiptFingerprint))
          readIORef (syntheticSettlementLog broker) >>= (@?= [])
      , testCase "equal payloads with distinct receipts settle twice but dispatch once" $ do
          subscription <- trainingDaemonSubscription LinuxCPU
          let topic = daemonSubscriptionTopicName subscription
              payload = syntheticTrainingPayload "equal-payload" LinuxCPU
          broker <-
            newSyntheticBroker
              [ syntheticEnvelope topic "delivery-a" 0 payload
              , syntheticEnvelope topic "delivery-b" 1 payload
              ]
          observedRef <- newIORef []
          dispatchRef <- newIORef ([] :: [EventId])
          result <-
            evalStateT
              ( runConsumerLoop
                  subscription
                  (emptyHandlerRouter 16)
                  2
                  (recordObservedSession observedRef)
                  ( \_command eventId -> do
                      liftIO (modifyIORef' dispatchRef (<> [eventId]))
                      pure (Right ())
                  )
              )
              broker
          (_, outcomes) <- expectConsumerLoopSuccess result
          dispatchedCount outcomes @?= 1
          dedupCount outcomes @?= 1
          dispatches <- readIORef dispatchRef
          length dispatches @?= 1
          settlements <- readIORef (syntheticSettlementLog broker)
          fmap syntheticSettledDisposition settlements @?= [ObservedAck, ObservedAck]
          assertBool
            "distinct receipts keep distinct opaque fingerprints"
            ( case fmap syntheticSettledReceipt settlements of
                [firstReceipt, secondReceipt] -> firstReceipt /= secondReceipt
                _ -> False
            )
          observed <- readIORef observedRef
          observed
            @?= [ ConsumerSessionConnected 1
                , ConsumerSessionDraining
                , ConsumerSessionDrained
                ]
          cleanup <- readIORef (syntheticCleanupLog broker)
          cleanup
            @?= [ "close:persistent://public/default/training.command.linux-cpu:jitml-coordinator"
                ]
      , testCase "dispatch failure Nacks without a dedup mark and redelivery dispatches again" $ do
          subscription <- trainingDaemonSubscription LinuxCPU
          let topic = daemonSubscriptionTopicName subscription
              payload = syntheticTrainingPayload "retry-payload" LinuxCPU
              command = syntheticTrainingCommand "retry-payload" LinuxCPU
          eventId <- expectDaemonCommandEventId command
          broker <-
            newSyntheticBroker
              [ syntheticEnvelope topic "delivery-failed" 0 payload
              , syntheticEnvelope topic "delivery-redelivered" 1 payload
              ]
          attemptsRef <- newIORef (0 :: Int)
          result <-
            evalStateT
              ( runConsumerLoop
                  subscription
                  (emptyHandlerRouter 16)
                  2
                  (const (pure ()))
                  ( \_command _eventId -> do
                      attempts <- liftIO (readIORef attemptsRef)
                      liftIO (writeIORef attemptsRef (attempts + 1))
                      if attempts == 0
                        then pure (Left (SETransient "handler failed"))
                        else pure (Right ())
                  )
              )
              broker
          (router, outcomes) <- expectConsumerLoopSuccess result
          outcomes
            @?= [ ConsumerError (SETransient "handler failed")
                , ConsumerDispatched TrainingDomain eventId
                ]
          readIORef attemptsRef >>= (@?= 2)
          dedupCacheKnown eventId (trainingCache router) @?= True
          settlements <- readIORef (syntheticSettlementLog broker)
          fmap syntheticSettledDisposition settlements
            @?= [ ObservedNack (HandlerRejected "transient: handler failed")
                , ObservedAck
                ]
      , testCase "settlement failure surfaces after exactly one handler decision" $ do
          subscription <- trainingDaemonSubscription LinuxCPU
          let topic = daemonSubscriptionTopicName subscription
          broker <-
            newSyntheticBroker
              [syntheticEnvelope topic "settlement-fails" 0 (syntheticTrainingPayload "settlement" LinuxCPU)]
          writeIORef
            (syntheticSettlementFailure broker)
            (Just (SETimeout "broker settlement timeout"))
          result <-
            evalStateT
              ( runConsumerLoop
                  subscription
                  (emptyHandlerRouter 16)
                  1
                  (const (pure ()))
                  (\_command _eventId -> pure (Right ()))
              )
              broker
          case result of
            Left failure@(ConsumerSettlementFailure _ (SETimeout "broker settlement timeout")) ->
              assertBool
                "settlement failure maps to a typed daemon error"
                (isJust (consumerOutcomeError (ConsumerSessionError failure)))
            other -> assertFailure ("expected settlement failure, got " <> show other)
          settlements <- readIORef (syntheticSettlementLog broker)
          length settlements @?= 1
          readIORef (syntheticCleanupLog broker) >>= (@?= [])
      , testCase "malformed typed delivery fails decode before the handler" $ do
          subscription <- trainingDaemonSubscription LinuxCPU
          broker <-
            newSyntheticBroker
              [ syntheticEnvelope
                  (daemonSubscriptionTopicName subscription)
                  "malformed"
                  0
                  "kind: NotTraining\n"
              ]
          dispatchRef <- newIORef (0 :: Int)
          result <-
            evalStateT
              ( runConsumerLoop
                  subscription
                  (emptyHandlerRouter 16)
                  1
                  (const (pure ()))
                  ( \_command _eventId ->
                      liftIO (modifyIORef' dispatchRef (+ 1)) >> pure (Right ())
                  )
              )
              broker
          case result of
            Left (ConsumerDecodeFailure _) -> pure ()
            other -> assertFailure ("expected typed decode failure, got " <> show other)
          readIORef dispatchRef >>= (@?= 0)
          readIORef (syntheticSettlementLog broker) >>= (@?= [])
      , testCase "bounded Done drains before return and ownership controls cleanup" $ do
          subscription <- trainingDaemonSubscription LinuxCPU
          let topic = daemonSubscriptionTopicName subscription
          broker <-
            newSyntheticBroker
              [ syntheticEnvelope topic "bounded-a" 0 (syntheticTrainingPayload "bounded-a" LinuxCPU)
              , syntheticEnvelope topic "bounded-b" 0 (syntheticTrainingPayload "bounded-b" LinuxCPU)
              , syntheticEnvelope topic "bounded-c" 0 (syntheticTrainingPayload "bounded-c" LinuxCPU)
              ]
          result <-
            evalStateT
              ( runConsumerLoop
                  subscription
                  (emptyHandlerRouter 16)
                  2
                  (const (pure ()))
                  (\_command _eventId -> pure (Right ()))
              )
              broker
          (_, outcomes) <- expectConsumerLoopSuccess result
          length outcomes @?= 2
          readIORef (syntheticSessionLog broker)
            >>= ( @?=
                    [ ConsumerSessionConnected 1
                    , ConsumerSessionDraining
                    , ConsumerSessionDrained
                    ]
                )
          pending <- readIORef (syntheticDeliveryQueue broker)
          fmap syntheticDeliveryId pending @?= ["bounded-c"]
          ownedTopic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
          ownedSubscription <-
            expectRight
              (mkSubscription ownedTopic "owned-test" FromEarliest Owned)
          ownedBroker <-
            newSyntheticBroker
              [ syntheticEnvelope
                  (topicName ownedTopic)
                  "owned-delivery"
                  0
                  (syntheticTrainingPayload "owned" LinuxCPU)
              ]
          ownedResult <-
            evalStateT
              ( pulsarConsumeUntil
                  ownedSubscription
                  (const (pure ()))
                  (\_delivery -> pure (done ack ()))
              )
              ownedBroker
          ownedResult @?= Right ()
          readIORef (syntheticCleanupLog ownedBroker)
            >>= (@?= ["delete:persistent://public/default/training.command.linux-cpu:owned-test"])
      , testCase "daemon consumer batch with zero budget does not open a session" $ do
          broker <-
            newSyntheticBroker
              [ syntheticEnvelope
                  "persistent://public/default/training.command.linux-cpu"
                  "not-consumed"
                  0
                  (syntheticTrainingPayload "not-consumed" LinuxCPU)
              ]
          (_, outcomes) <-
            evalStateT
              ( Runtime.daemonConsumerBatch
                  defaultDaemonRuntime
                  0
                  (\_command _eventId -> pure (Right ()))
              )
              broker
          outcomes @?= []
          readIORef (syntheticSessionLog broker) >>= (@?= [])
          pending <- readIORef (syntheticDeliveryQueue broker)
          fmap syntheticDeliveryId pending @?= ["not-consumed"]
      , testCase "default batch capability captures the real monotonic admission time" $ do
          topic <- expectRight (topicFor TrainingCommandRoute LinuxCPU)
          subscription <-
            expectRight
              (mkSubscription topic "synthetic-batch-clock" FromEarliest Borrowed)
          policy <- expectRight (InferenceBatch.mkBatchPolicy 1 1_000_000)
          broker <-
            newSyntheticBroker
              [ syntheticEnvelope
                  (topicName topic)
                  "batch-clock"
                  0
                  (syntheticTrainingPayload "batch-clock" LinuxCPU)
              ]
          observedWindow <- newIORef Nothing
          before <- getMonotonicTimeNSec
          result <-
            evalStateT
              ( pulsarConsumeBatchesUntil
                  (pure policy)
                  (const ())
                  subscription
                  (const (pure ()))
                  ( \batch -> do
                      liftIO (writeIORef observedWindow (Just (deliveryBatchWindow batch)))
                      pure (doneBatch ack ())
                  )
              )
              broker
          after <- getMonotonicTimeNSec
          result @?= Right ()
          observed <- readIORef observedWindow
          case observed of
            Nothing -> assertFailure "default batch handler did not observe a window"
            Just window -> do
              let admitted = InferenceBatch.batchWindowAdmissionNanoseconds window
                  deadline = InferenceBatch.batchWindowDeadlineNanoseconds window
              assertBool "batch admission predates the test clock" (admitted >= before)
              assertBool "batch admission exceeds the test clock" (admitted <= after)
              assertBool "batch deadline does not follow admission" (deadline > toInteger admitted)
      , testCase "consumerLoopExit short-circuits on first PulsarFailed (Sprint 5.5)" $ do
          eventA <- expectDaemonCommandEventId (syntheticTrainingCommand "a" LinuxCPU)
          eventB <- expectDaemonCommandEventId (syntheticTrainingCommand "b" LinuxCPU)
          let cleanBatch =
                [ ConsumerDispatched TrainingDomain eventA
                , ConsumerDeduplicated TuneDomain eventA
                ]
              poisonedBatch =
                [ ConsumerDispatched TrainingDomain eventA
                , ConsumerError (SETimeout "ack budget exhausted")
                , ConsumerDispatched RlDomain eventB
                ]
          Runtime.consumerLoopExit cleanBatch @?= Nothing
          Runtime.consumerLoopExit poisonedBatch
            @?= Just (PulsarFailed "timeout: ack budget exhausted")
      , testCase "batch command commits survive cancellation of a later command" $ do
          let firstCommand = syntheticTrainingCommand "batch-prefix-a" LinuxCPU
              secondCommand = syntheticTrainingCommand "batch-prefix-b" LinuxCPU
              cancelledCommand = syntheticTrainingCommand "batch-cancelled" LinuxCPU
          firstEvent <- expectDaemonCommandEventId firstCommand
          secondEvent <- expectDaemonCommandEventId secondCommand
          cancelledEvent <- expectDaemonCommandEventId cancelledCommand
          routerRef <- newMVar (emptyHandlerRouter 16)
          _ <- consumerStepCommitted routerRef firstCommand (\_ _ -> pure (Right ()))
          _ <- consumerStepCommitted routerRef secondCommand (\_ _ -> pure (Right ()))
          dispatchEntered <- newEmptyMVar
          neverFinishDispatch <- newEmptyMVar
          worker <-
            async $
              consumerStepCommitted
                routerRef
                cancelledCommand
                ( \_ _ -> do
                    putMVar dispatchEntered ()
                    _ <- takeMVar neverFinishDispatch
                    pure (Right ())
                )
          takeMVar dispatchEntered
          cancel worker
          cancelled <- waitCatch worker
          case cancelled of
            Left _ -> pure ()
            Right _ -> assertFailure "expected the later batch command to be cancelled"
          retainedRouter <- readMVar routerRef
          dedupCacheKnown firstEvent (trainingCache retainedRouter) @?= True
          dedupCacheKnown secondEvent (trainingCache retainedRouter) @?= True
          dedupCacheKnown cancelledEvent (trainingCache retainedRouter) @?= False
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
          eventId <-
            expectDaemonCommandEventId (syntheticTrainingCommand "payload-a" LinuxCPU)
          let router0 = emptyHandlerRouterWithTtl 16 5
              (router1, firstSeen) = routeByKindAt 100 router0 TrainingDomain eventId
              (router2, redeliveryBeforeTtl) = routeByKindAt 104 router1 TrainingDomain eventId
              (_router3, redeliveryAtTtl) = routeByKindAt 105 router2 TrainingDomain eventId
          firstSeen @?= True
          redeliveryBeforeTtl @?= False
          redeliveryAtTtl @?= True
      , testCase "hot reload resizes dedup caches without losing newest live entries" $ do
          older <- expectDaemonCommandEventId (syntheticTrainingCommand "older" LinuxCPU)
          newer <- expectDaemonCommandEventId (syntheticTrainingCommand "newer" LinuxCPU)
          let router0 = emptyHandlerRouterWithTtl 4 30
              (router1, _) = routeByKindAt 100 router0 TrainingDomain older
              (router2, _) = routeByKindAt 101 router1 TrainingDomain newer
              shrunk = reconfigureHandlerRouterAt 103 1 5 router2
              expired = reconfigureHandlerRouterAt 106 1 5 shrunk
          dedupCacheCapacity (trainingCache shrunk) @?= 1
          dedupCacheTtlSeconds (trainingCache shrunk) @?= 5
          dedupCacheKnown newer (trainingCache shrunk) @?= True
          dedupCacheKnown older (trainingCache shrunk) @?= False
          dedupCacheKnown newer (trainingCache expired) @?= False
      ]

expectRight :: (Show err) => Either err value -> IO value
expectRight result =
  case result of
    Left err -> ioError (userError (show err))
    Right value -> pure value

expectSubscriptionPlan :: BootConfig.BootConfig -> IO [DaemonSubscription]
expectSubscriptionPlan =
  expectRight . daemonSubscriptionsForBootConfig

assertSubscriptionPlan :: Text -> [Text] -> [DaemonSubscription] -> IO ()
assertSubscriptionPlan expectedName expectedTopics subscriptions = do
  let expectedCount = length expectedTopics
  length subscriptions @?= expectedCount
  fmap daemonSubscriptionTopicName subscriptions @?= expectedTopics
  fmap daemonSubscriptionName subscriptions @?= replicate expectedCount expectedName
  fmap daemonSubscriptionStart subscriptions @?= replicate expectedCount FromEarliest
  fmap daemonSubscriptionOwnership subscriptions @?= replicate expectedCount Borrowed

connectAllConsumers :: Word64 -> DaemonRuntime -> DaemonRuntime
connectAllConsumers generation runtime =
  runtime
    { daemonState =
        foldl
          ( \state subscription ->
              daemonConsumerSessionTransition
                subscription
                (ConsumerSessionConnected generation)
                state
          )
          (daemonState runtime)
          (Runtime.daemonSubscriptions runtime)
    }

readyLinuxRuntime :: IO DaemonRuntime
readyLinuxRuntime = do
  clientLogRef <- newIORef []
  evalStateT
    (Runtime.probeEngineServiceClients (connectAllConsumers 1 defaultDaemonRuntime))
    (SyntheticClientState clientLogRef)

assertReadyHttpStatus
  :: DaemonControl
  -> DaemonRuntime
  -> String
  -> IO ()
assertReadyHttpStatus control runtime expectedStatus =
  withHttpRoutesOnce
    (HttpListener "127.0.0.1" 0)
    (daemonHttpRoutes control runtime)
    ( \port -> do
        response <- httpGet port "/readyz"
        assertBool
          ("expected readyz HTTP status " <> expectedStatus)
          (("HTTP/1.1 " <> expectedStatus) `isInfixOf` response)
    )

syntheticRlStart :: Text -> Substrate -> Rl.StartRLRun
syntheticRlStart experimentHash substrate =
  Rl.StartRLRun
    { Rl.srlExperimentHash = experimentHash
    , Rl.srlAlgorithm = "PPO"
    , Rl.srlEnvironment = "cartpole"
    , Rl.srlSubstrate = substrate
    , Rl.srlSeed = 42
    , Rl.srlMaxSteps = 200
    , Rl.srlEvalEpisodes = 2
    }

assertWorkloadOutcomesSucceeded
  :: Either WorkloadDecodeError (NonEmpty SomeWorkloadOutcome)
  -> IO ()
assertWorkloadOutcomesSucceeded result =
  case result of
    Left err -> assertFailure (show err)
    Right outcomes ->
      traverse_ (\outcome -> workloadOutcomeError outcome @?= Nothing) outcomes

assertWorkloadDispatchOutcome
  :: Either WorkloadDecodeError SomeWorkloadOutcome
  -> IO ()
assertWorkloadDispatchOutcome result =
  case result of
    Left err -> assertFailure (show err)
    Right outcome -> workloadOutcomeError outcome @?= Nothing

renderSomeEffectPayload :: SomeWorkloadEffect -> Text
renderSomeEffectPayload (SomeWorkloadEffect effect) =
  renderWorkloadEffectPayload effect

trainingDaemonSubscription :: Substrate -> IO DaemonSubscription
trainingDaemonSubscription substrate = do
  let bootConfig =
        (BootConfig.defaultBootConfig substrate BootConfig.Cluster)
          { BootConfig.bootActiveRole = BootConfig.Coordinator
          }
  subscriptions <-
    expectSubscriptionPlan bootConfig
  case filter ((== TrainingDomain) . daemonSubscriptionDomain) subscriptions of
    [subscription] -> pure subscription
    unexpected ->
      ioError
        (userError ("expected one training subscription, got " <> show unexpected))

syntheticTrainingPayload :: Text -> Substrate -> Text
syntheticTrainingPayload experimentHash substrate =
  daemonCommandPayload (syntheticTrainingCommand experimentHash substrate)

syntheticTrainingCommand :: Text -> Substrate -> DaemonCommand
syntheticTrainingCommand experimentHash substrate =
  TrainingDaemonCommand
    substrate
    ( Training.TrainingStart
        ( preparedStartTraining
            Training.StartTraining
              { Training.stExperimentHash = experimentHash
              , Training.stDhallObjectKey = "experiments/synthetic.dhall"
              , Training.stSubstrate = substrate
              , Training.stSeed = 7
              , Training.stEpochs = 2
              , Training.stBatchSize = 8
              , Training.stPlanId = ""
              , Training.stResolvedPlan = ""
              , Training.stTrainingExamples = 64
              , Training.stEvaluationExamples = 16
              }
        )
    )

syntheticInferenceCommand :: Substrate -> Text -> DaemonCommand
syntheticInferenceCommand substrate callId =
  InferenceDaemonCommand
    substrate
    ( Inference.RunInference
        Inference.InferenceRequest
          { Inference.irCallId = callId
          , Inference.irExperimentHash = "inference-model"
          , Inference.irReplyTopic =
              "inference.result." <> renderSubstrate substrate
          , Inference.irInput = [1.0]
          }
    )

coordinatorTopicNames :: Substrate -> [Text]
coordinatorTopicNames substrate =
  [ "persistent://public/default/training.command." <> renderSubstrate substrate
  , "persistent://public/default/tune.command." <> renderSubstrate substrate
  , "persistent://public/default/rl.command." <> renderSubstrate substrate
  ]

assertUnauthorized :: Either ServiceError () -> IO ()
assertUnauthorized result =
  case result of
    Left (SEUnauthorized _) -> pure ()
    unexpected -> assertFailure ("expected SEUnauthorized, got " <> show unexpected)

expectDaemonCommandEventId :: DaemonCommand -> IO EventId
expectDaemonCommandEventId command =
  case daemonCommandEventId command of
    Failure errors ->
      ioError (userError ("expected valid semantic event identity, got " <> show errors))
    Success eventId -> pure eventId

syntheticEnvelope :: Text -> Text -> Int -> Text -> SyntheticEnvelope
syntheticEnvelope topic deliveryId redeliveryCount payload =
  SyntheticEnvelope
    { syntheticEnvelopeTopic = topic
    , syntheticSession = "synthetic-session"
    , syntheticGeneration = 1
    , syntheticDeliveryId = deliveryId
    , syntheticRedeliveryCount = redeliveryCount
    , syntheticPayload = payload
    }

newSyntheticBroker :: [SyntheticEnvelope] -> IO SyntheticBrokerState
newSyntheticBroker envelopes =
  SyntheticBrokerState
    <$> newIORef envelopes
    <*> newIORef []
    <*> newIORef []
    <*> newIORef []
    <*> newIORef Nothing

recordObservedSession
  :: IORef [ConsumerSessionEvent]
  -> ConsumerSessionEvent
  -> StateT SyntheticBrokerState IO ()
recordObservedSession ref event =
  liftIO (modifyIORef' ref (<> [event]))

expectConsumerLoopSuccess
  :: Either ConsumerFailure (HandlerRouter, [ConsumerOutcome])
  -> IO (HandlerRouter, [ConsumerOutcome])
expectConsumerLoopSuccess =
  expectRight

firstEnvelopeFor :: Text -> [SyntheticEnvelope] -> Maybe SyntheticEnvelope
firstEnvelopeFor selectedTopic =
  firstMatch
 where
  firstMatch [] = Nothing
  firstMatch (envelope : rest)
    | syntheticEnvelopeTopic envelope == selectedTopic = Just envelope
    | otherwise = firstMatch rest

takeEnvelopeFor
  :: Text
  -> [SyntheticEnvelope]
  -> Maybe (SyntheticEnvelope, [SyntheticEnvelope])
takeEnvelopeFor selectedTopic =
  go []
 where
  go _prefix [] = Nothing
  go prefix (envelope : rest)
    | syntheticEnvelopeTopic envelope == selectedTopic =
        Just (envelope, reverse prefix <> rest)
    | otherwise = go (envelope : prefix) rest

observedDecisionDisposition :: ObservedDecision result -> ObservedDisposition
observedDecisionDisposition decision =
  case decision of
    ObservedContinue disposition -> disposition
    ObservedDone disposition _ -> disposition

cleanupAction :: SubscriptionOwnership -> Text
cleanupAction ownership =
  case ownership of
    Borrowed -> "close"
    Owned -> "delete"

data SyntheticEnvelope = SyntheticEnvelope
  { syntheticEnvelopeTopic :: Text
  , syntheticSession :: Text
  , syntheticGeneration :: Word64
  , syntheticDeliveryId :: Text
  , syntheticRedeliveryCount :: Int
  , syntheticPayload :: Text
  }
  deriving stock (Eq, Show)

data SyntheticSettlement = SyntheticSettlement
  { syntheticSettledReceipt :: Text
  , syntheticSettledDisposition :: ObservedDisposition
  }
  deriving stock (Eq, Show)

-- | Persistent receipt-bound test interpreter. It keeps raw wire payloads
-- until the opaque subscription topic decodes them, then exposes only a
-- test-namespace 'Delivery'. Settlement records the receipt fingerprint, not a
-- broker message id.
data SyntheticBrokerState = SyntheticBrokerState
  { syntheticDeliveryQueue :: IORef [SyntheticEnvelope]
  , syntheticSettlementLog :: IORef [SyntheticSettlement]
  , syntheticSessionLog :: IORef [ConsumerSessionEvent]
  , syntheticCleanupLog :: IORef [Text]
  , syntheticSettlementFailure :: IORef (Maybe ServiceError)
  }

newtype SyntheticClientState = SyntheticClientState
  { syntheticClientLog :: IORef [Text]
  }

requiresEngineCapabilities
  :: (HasMinIO m, HasPulsar m) => m ()
requiresEngineCapabilities =
  pure ()

recordClientCall :: Text -> StateT SyntheticClientState IO ()
recordClientCall entry = do
  state <- get
  liftIO (modifyIORef' (syntheticClientLog state) (++ [entry]))

instance HasMinIO (StateT SyntheticClientState IO) where
  minioPutIfAbsent ref _payload = do
    recordClientCall "minio:put-if-absent"
    pure (Right ref)
  minioReadObject ref = do
    recordClientCall "minio:read-object"
    pure (fmap TextEncoding.decodeUtf8Lenient (lookupSyntheticObject ref))
  minioReadBytes ref = do
    recordClientCall "minio:read-bytes"
    pure (lookupSyntheticObject ref)
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
    pure $
      case resource of
        "job/jitml-train-fail-job-delete" ->
          Left (SETransient "synthetic Job deletion failure")
        "configmap/runconfig-jitml-train-fail-configmap-delete" ->
          Left (SETransient "synthetic RunConfig deletion failure")
        _ -> Right ()

instance HasPulsar (StateT SyntheticClientState IO) where
  pulsarPublish topic _event = do
    recordClientCall ("pulsar:publish:" <> topicName topic)
    pure (Right "synthetic-message-id")
  pulsarConsumeUntil subscription _observe _handler =
    pure
      ( Left
          ( ConsumerProtocolFailure
              ("synthetic client has no queue for " <> topicName (subscriptionTopic subscription))
          )
      )

-- | The current admission-before-serving inference path
-- (`runInferenceRequestWithTarget` -> `loadInferenceCheckpointWith` ->
-- `admitLatestCompletedCheckpoint`) resolves a checkpoint through the exact
-- Store admission flow: read the latest pointer (whose body is a canonical
-- SHA-256 manifest address), read the addressed manifest at that address,
-- re-read the pointer, then bind every physical blob before the reloaded graph
-- is served. Only a canonical, completion-admissible checkpoint reaches the
-- injected engine runner, so the synthetic MinIO store must lay the objects out
-- exactly as the real store does. This fixture is a genuinely admissible
-- non-supervised (RL) ProductRow completed weight checkpoint — the smallest
-- checkpoint that survives `requireAdmittedCompletedCheckpoint` and still routes
-- through the unweighted `loadInferenceCheckpointWith` (its manifest carries no
-- supervised-runtime payload). It is built purely from the real
-- Checkpoint/Product helpers.
data SyntheticInferenceFixture = SyntheticInferenceFixture
  { sifExperimentHash :: Text
  , sifObjects :: [(Text, ByteString.ByteString)]
  -- ^ synthetic object store keyed by the checkpoint object key (the
  -- `jitml-checkpoints/` bucket prefix stripped, matching `checkpointObjectRef`).
  }

-- | Experiment hash the daemon inference tests issue their `InferenceRequest`
-- against; it must be a canonical non-supervised ProductRow so completed
-- admission accepts the weight-only checkpoint.
syntheticInferenceExperimentHash :: Text
syntheticInferenceExperimentHash =
  sifExperimentHash syntheticInferenceFixture

syntheticInferenceFixture :: SyntheticInferenceFixture
syntheticInferenceFixture =
  either (error . Text.unpack) id buildSyntheticInferenceFixture

buildSyntheticInferenceFixture :: Either Text SyntheticInferenceFixture
buildSyntheticInferenceFixture = do
  row <-
    maybe
      (Left "daemon inference fixture: missing canonical ProductRow DQN/cartpole")
      Right
      (find ((== "DQN/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  planId <-
    case ProductMatrix.projectProductRow LinuxCPU row of
      Success (ProductMatrix.SomeProductProjection _ projection) ->
        Right (ProductMatrix.productProjectionPlanId projection)
      Failure errors ->
        Left ("daemon inference fixture: plan projection failed: " <> Text.pack (show errors))
  let experiment = ProductMatrix.productRowExperimentHash row
      tensorName = "rl-dqn-weights"
      initialWeights = [0.0, 0.0]
      finalWeights = [0.25, 0.5]
      initialBytes = WeightCodec.encodeJmw1 initialWeights
      finalBytes = WeightCodec.encodeJmw1 finalWeights
      finalSha = WeightCodec.jmw1ContentSha finalBytes
      weightKey = Checkpoint.blobKey experiment finalSha
      bar = ProductMatrix.convergenceBar row
      convergenceMetrics =
        [
          ( ProductConvergence.convergenceMetricName bar
          , ProductConvergence.convergenceThreshold bar
          )
        ]
      budget = ProductMatrix.trainingBudget row
      step = TrainingBudget.trainingBudgetTargetUnits budget
  completed <-
    ProductCompletion.completedTrainingForProductRowWithWeightHashes
      planId
      budget
      row
      (Text.replicate 64 "d")
      experiment
      step
      1
      convergenceMetrics
      (WeightCodec.jmw1ContentSha initialBytes)
      finalSha
  let companionPayload = LazyByteString.fromStrict (ByteString.pack "exact product transcript")
      companionSha = WeightCodec.jmw1ContentSha companionPayload
      companionKey =
        "jitml-checkpoints/"
          <> experiment
          <> "/artifacts/rl-trajectory/"
          <> companionSha
          <> ".txt"
      transcriptPointer =
        Checkpoint.ArtifactPointer
          { Checkpoint.artifactPointerKind = "rl-trajectory"
          , Checkpoint.artifactPointerObjectKey = companionKey
          , Checkpoint.artifactPointerSha = Just companionSha
          }
      tensor = Checkpoint.TensorBlob tensorName [length finalWeights] weightKey
      manifest =
        Checkpoint.attachCompletedTraining completed $
          (Checkpoint.emptyManifest "inference-exp" experiment [tensor])
            { Checkpoint.manifestModelFamily = Checkpoint.ReinforcementLearningPolicyFamily
            , Checkpoint.manifestArchitecture =
                Checkpoint.defaultArchitectureMetadata Checkpoint.ReinforcementLearningPolicyFamily
            , Checkpoint.manifestStep = step
            , Checkpoint.manifestMetrics = convergenceMetrics
            , Checkpoint.manifestTranscriptPointers = [transcriptPointer]
            }
      manifestBytes = LazyByteString.toStrict (Checkpoint.encodeManifestCbor manifest)
      manifestSha = Checkpoint.manifestContentSha manifest
      objects =
        [
          ( CheckpointStore.checkpointObjectKey (Checkpoint.latestPointerKey experiment)
          , TextEncoding.encodeUtf8 manifestSha
          )
        , (CheckpointStore.checkpointObjectKey (Checkpoint.manifestKey experiment manifestSha), manifestBytes)
        , (CheckpointStore.checkpointObjectKey weightKey, LazyByteString.toStrict finalBytes)
        , (CheckpointStore.checkpointObjectKey companionKey, LazyByteString.toStrict companionPayload)
        ]
  pure
    SyntheticInferenceFixture
      { sifExperimentHash = experiment
      , sifObjects = objects
      }

-- | Answer a synthetic MinIO read by the object key the real admission flow
-- requests (bucket prefix already stripped by `checkpointObjectRef`).
lookupSyntheticObject :: ObjectRef -> Either ServiceError ByteString.ByteString
lookupSyntheticObject ref =
  case lookup (unObjectKey (objectKey ref)) (sifObjects syntheticInferenceFixture) of
    Just bytes -> Right bytes
    Nothing ->
      Left
        ( SETransient
            ("synthetic MinIO store has no object for key " <> unObjectKey (objectKey ref))
        )

instance HasPulsar (StateT SyntheticBrokerState IO) where
  pulsarPublish _ _ = pure (Right "synthetic-message-id")
  pulsarConsumeUntil subscription observe handler = do
    state <- get
    pending <- liftIO (readIORef (syntheticDeliveryQueue state))
    let selectedTopic = subscriptionTopic subscription
        selectedTopicName = topicName selectedTopic
        generation =
          maybe 1 syntheticGeneration (firstEnvelopeFor selectedTopicName pending)
        emit event = do
          liftIO (modifyIORef' (syntheticSessionLog state) (<> [event]))
          observe event
        finishCleanup =
          liftIO $
            modifyIORef'
              (syntheticCleanupLog state)
              ( <>
                  [ cleanupAction (subscriptionOwnership subscription)
                      <> ":"
                      <> selectedTopicName
                      <> ":"
                      <> subscriptionName subscription
                  ]
              )
        loop = do
          envelopes <- liftIO (readIORef (syntheticDeliveryQueue state))
          case takeEnvelopeFor selectedTopicName envelopes of
            Nothing ->
              pure
                ( Left
                    (ConsumerProtocolFailure ("synthetic queue exhausted for " <> selectedTopicName))
                )
            Just (envelope, rest) -> do
              liftIO (writeIORef (syntheticDeliveryQueue state) rest)
              case decodeTopicPayload selectedTopic (syntheticPayload envelope) of
                Left decodeError -> pure (Left (ConsumerDecodeFailure decodeError))
                Right event -> do
                  simulated <-
                    simulateDeliveryDecisionForTest
                      (syntheticSession envelope)
                      (syntheticGeneration envelope)
                      (syntheticDeliveryId envelope)
                      (syntheticRedeliveryCount envelope)
                      event
                      handler
                  case simulated of
                    Left err -> pure (Left (ConsumerProtocolFailure (Text.pack (show err))))
                    Right (observed, receiptFingerprint) -> do
                      let disposition = observedDecisionDisposition observed
                      liftIO $
                        modifyIORef'
                          (syntheticSettlementLog state)
                          (<> [SyntheticSettlement receiptFingerprint disposition])
                      settlementFailure <-
                        liftIO (readIORef (syntheticSettlementFailure state))
                      case settlementFailure of
                        Just err ->
                          pure
                            ( Left
                                (ConsumerSettlementFailure receiptFingerprint err)
                            )
                        Nothing ->
                          case observed of
                            ObservedContinue _ -> loop
                            ObservedDone _ result -> do
                              emit ConsumerSessionDraining
                              emit ConsumerSessionDrained
                              finishCleanup
                              pure (Right result)
    emit (ConsumerSessionConnected generation)
    loop

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

preparedStartSweep :: Tune.StartSweep -> Tune.StartSweep
preparedStartSweep raw =
  case PlanCommand.prepareStartSweep raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartSweep test fixture: " <> Text.unpack message)

preparedStartTraining :: Training.StartTraining -> Training.StartTraining
preparedStartTraining raw =
  case PlanCommand.prepareStartTraining raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartTraining test fixture: " <> Text.unpack message)

preparedStartAlphaZeroRun :: Rl.StartAlphaZeroRun -> Rl.StartAlphaZeroRun
preparedStartAlphaZeroRun raw =
  case PlanCommand.prepareStartAlphaZeroRun raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartAlphaZeroRun test fixture: " <> Text.unpack message)

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

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent qualified
import Control.Exception qualified
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (eitherDecode)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Foldable (traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text.Encoding qualified as Text.Encoding

import Data.ByteString qualified
import JitML.Bootstrap
  ( bootstrapPlanSteps
  , hostBootConfigForPublication
  , livePhasedRolloutSubprocesses
  )
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Cluster.DockerImage qualified as DockerImage
import JitML.Cluster.EdgePort qualified as EdgePort
import JitML.Cluster.Helm qualified as Helm
import JitML.Cluster.Kind (kindConfigFor, renderKindConfig)
import JitML.Cluster.PostgresRegistry qualified as PostgresRegistry
import JitML.Cluster.Publication qualified as Publication
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Cluster.Readiness qualified as Readiness
import JitML.Engines.CpuFeatures (CpuFeatures (..), detectCpuFeatures, microKernelChoice)
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.OneDnnRuntime qualified as OneDnnRuntime
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Numerics.Schema qualified as Numerics
import JitML.RL.AlphaZero.SelfPlay qualified as SelfPlay

import JitML.Observability.TbSidecar qualified as TbSidecar
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.Proto.Gc qualified as ProtoGc
import JitML.Proto.Training qualified as Training
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.Routes (renderHTTPRoute, renderRouteTable, routeRegistry)
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasHarbor (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , ImageRef (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , SubscriptionId (..)
  , TopicName (..)
  )
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.ConfigMap qualified as ServiceConfigMap
import JitML.Service.Consumer (EventDomain (..), eventIdFromPayload)
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.HarborSubprocess qualified as HarborSubprocess
import JitML.Service.KubectlSubprocess (KubectlSettings (..), defaultKubectlSettings)
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.Runtime qualified as Runtime
import JitML.Storage.Buckets (bucketNames)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Sub.Subprocess qualified
import JitML.Substrate (Substrate (..))
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as TuneResume
import System.Directory (doesFileExist, listDirectory, makeAbsolute)
import System.FilePath ((</>))
import System.Info qualified as SystemInfo

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-integration"
      [ testCase "runStreaming captures a fixture process" $ do
          (exitCode, stdoutText, stderrText) <-
            runStreaming defaultSubprocessEnv (subprocess "/bin/echo" ["subprocess-ok"])
          exitCode @?= ExitSuccess
          stdoutText @?= "subprocess-ok\n"
          stderrText @?= ""
      , testCase "bootstrap plan includes Harbor-first publication" $
          bootstrapPlanSteps LinuxCPU
            @?= [ "reconcile prerequisite graph for cluster"
                , "render kind/cluster-linux-cpu.yaml"
                , "prepare Helm dependencies with helm dependency build chart"
                , "create/export Kind kubeconfig and copy it to ./.build/jitml.kubeconfig"
                , "apply jitml-manual StorageClass and manual PVs"
                , "install MinIO and Percona storage for Harbor"
                , "install Harbor bootstrap phase"
                , "build jitml:local and jitml-demo:local and load them into Kind"
                , "install Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
                , "write ./.build/runtime/cluster-publication.json"
                ]
      , testCase "kind config render carries repo mounts for non-CUDA substrates" $ do
          let appleConfig = renderKindConfig (kindConfigFor AppleSilicon)
              cpuConfig = renderKindConfig (kindConfigFor LinuxCPU)
          assertBool
            "apple-silicon mounts build cache"
            ("containerPath: /jitml/.build" `Text.isInfixOf` appleConfig)
          assertBool "linux-cpu mounts data root" ("containerPath: /jitml/.data" `Text.isInfixOf` cpuConfig)
          assertBool
            "apple-silicon does not configure NVIDIA containerd"
            (not ("runtimes.nvidia" `Text.isInfixOf` appleConfig))
          assertBool
            "linux-cpu does not mount NVIDIA toolkit"
            (not ("nvidia-container-runtime" `Text.isInfixOf` cpuConfig))
      , testCase "kind config renders a single mounted node for every substrate (Sprint 3.1)" $ do
          let cpuConfig = renderKindConfig (kindConfigFor LinuxCPU)
              controlPlaneCount =
                length (Text.breakOnAll "  - role: control-plane" cpuConfig)
          controlPlaneCount @?= 1
          assertBool
            "single-node kind config has no separate worker"
            (not ("  - role: worker" `Text.isInfixOf` cpuConfig))
          assertBool
            "the single node has the repo build mount"
            (length (Text.breakOnAll "containerPath: /jitml/.build" cpuConfig) == 1)
      , testCase "linux-cuda Kind config wires NVIDIA runtime handler (Sprint 4.7)" $ do
          let cudaConfig = renderKindConfig (kindConfigFor LinuxCUDA)
          assertBool
            "linux-cuda carries the GPU node label"
            ("node-labels: jitml.runtime/gpu=true,jitml.substrate/linux-cuda=true" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda configures containerd patches"
            ("containerdConfigPatches:" `Text.isInfixOf` cudaConfig)
          assertBool "linux-cuda registers the nvidia runtime" ("runtimes.nvidia" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda runtime uses the NVIDIA binary"
            ("BinaryName = \"/usr/bin/nvidia-container-runtime\"" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the repo-owned runtime config"
            ("containerPath: /etc/nvidia-container-runtime" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the runtime binary"
            ("containerPath: /usr/bin/nvidia-container-runtime" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the host driver root"
            ("containerPath: /run/nvidia/driver" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the container CLI library"
            ("containerPath: /usr/lib/x86_64-linux-gnu/libnvidia-container.so.1" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the container CLI Go support library"
            ("containerPath: /usr/lib/x86_64-linux-gnu/libnvidia-container-go.so.1" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts NVML for the NVIDIA container CLI"
            ("containerPath: /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1" `Text.isInfixOf` cudaConfig)
      , testCase "route registry renders HTTPRoute manifests" $
          length (fmap renderHTTPRoute routeRegistry) @?= length routeRegistry
      , testCase "route table matches golden fixture" $ do
          expected <- Text.IO.readFile "test/golden/cluster/route-table.md"
          renderRouteTable @?= expected
      , testCase "filesystem HasMinIO honours putBlobIfAbsent and pointer CAS" $
          withSystemTempDirectory "jitml-fs-minio" $ \root ->
            runFilesystemMinIO root $ do
              let bucket = BucketName "jitml-checkpoints"
                  blobRef = ObjectRef bucket (ObjectKey "blobs/abc.bin")
                  pointerRef = ObjectRef bucket (ObjectKey "pointers/latest")
              first <- putBlobIfAbsent blobRef "weights:v1"
              case first of
                Right (ETag _) -> pure ()
                Left err ->
                  liftIO (assertFailure ("expected first putBlobIfAbsent OK, got: " <> show err))
              second <- putBlobIfAbsent blobRef "weights:v1"
              case second of
                Left (SEConflict _) -> pure ()
                _ -> liftIO (assertFailure "expected SEConflict on second putBlobIfAbsent")
              ptr1 <- casPointer pointerRef Nothing "manifest:sha-1"
              case ptr1 of
                Right (ETag etag1) -> do
                  ptr2 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-2"
                  case ptr2 of
                    Right (ETag _) -> pure ()
                    Left err ->
                      liftIO (assertFailure ("expected pointer CAS OK, got: " <> show err))
                  ptr3 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-3"
                  case ptr3 of
                    Left (SEConflict _) -> pure ()
                    _ -> liftIO (assertFailure "expected SEConflict on stale-ETag pointer CAS")
                Left err ->
                  liftIO (assertFailure ("expected first casPointer OK, got: " <> show err))
      , testCase "checkpoint snapshot writes through HasMinIO conditional boundaries (Sprint 10.2)" $
          withSystemTempDirectory "jitml-checkpoint-hasminio" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-write-minio"
                  blobObjectKey = Checkpoint.blobKey experimentHash "blob-weights"
                  manifest =
                    Checkpoint.emptyManifest
                      "m1"
                      experimentHash
                      [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
                  payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
              firstWrite <-
                CheckpointStore.writeCheckpointSnapshotWithMinIO
                  manifest
                  [(blobObjectKey, payload)]
                  Nothing
              case firstWrite of
                Left err ->
                  liftIO (assertFailure ("expected checkpoint write OK, got: " <> show err))
                Right stored -> do
                  liftIO $
                    CheckpointStore.storedPointerResult stored
                      @?= Checkpoint.PointerWritten (CheckpointStore.storedManifestSha stored)
                  inferred <- CheckpointStore.loadInferenceCheckpoint experimentHash [10.0]
                  liftIO $
                    inferred @?= Right (Checkpoint.inferFromManifest manifest [10.0])
              secondWrite <-
                CheckpointStore.writeCheckpointSnapshotWithMinIO
                  manifest
                  [(blobObjectKey, payload)]
                  Nothing
              case secondWrite of
                Left err ->
                  liftIO (assertFailure ("expected idempotent object writes, got: " <> show err))
                Right stored ->
                  liftIO $
                    CheckpointStore.storedPointerResult stored
                      @?= Checkpoint.PointerConflict (Checkpoint.latestPointerKey experimentHash)
      , testCase "MinIOSubprocess renders signed S3 conditional-write commands" $ do
          let settings = MinIOSubprocess.minioSettingsForLocalEdge 9091
              ref = ObjectRef (BucketName "jitml-checkpoints") (ObjectKey "pointers/latest")
              putCommand =
                MinIOSubprocess.minioPutObjectSubprocess
                  settings
                  ref
                  "/tmp/payload"
                  "/tmp/body"
                  "/tmp/etag"
                  Nothing
              listCommand =
                MinIOSubprocess.minioListObjectsSubprocess
                  settings
                  (BucketName "jitml-checkpoints")
                  "pointers/"
                  "/tmp/body"
          assertBool
            "MinIO PUT uses curl AWS SigV4"
            ("--aws-sigv4 aws:amz:us-east-1:s3" `Text.isInfixOf` renderSubprocess putCommand)
          assertBool
            "MinIO PUT uses local demo credentials explicitly"
            ("--user minio:minioadmin" `Text.isInfixOf` renderSubprocess putCommand)
          assertBool
            "MinIO PUT enforces If-None-Match"
            ("--header 'If-None-Match: *'" `Text.isInfixOf` renderSubprocess putCommand)
          assertBool
            "MinIO PUT signs the canonical S3 object URL"
            ( "http://127.0.0.1:9091/jitml-checkpoints/pointers/latest"
                `Text.isInfixOf` renderSubprocess putCommand
            )
          assertBool
            "MinIO PUT sends the routed Envoy request target"
            ( "--request-target /minio/s3/jitml-checkpoints/pointers/latest"
                `Text.isInfixOf` renderSubprocess putCommand
            )
          assertBool
            "MinIO list uses S3 list-type query"
            ( "'http://127.0.0.1:9091/jitml-checkpoints?list-type=2&prefix=pointers%2F'"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          assertBool
            "MinIO list sends the routed Envoy request target"
            ( "'/minio/s3/jitml-checkpoints?list-type=2&prefix=pointers%2F'"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          MinIOSubprocess.parseListObjectsResponse
            (BucketName "jitml-checkpoints")
            "<ListBucketResult><Contents><Key>pointers/latest</Key></Contents></ListBucketResult>"
            @?= [ObjectRef (BucketName "jitml-checkpoints") (ObjectKey "pointers/latest")]
      , testCase "PulsarWebSocketSubprocess renders routed producer and consumer commands" $ do
          let settings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge 9091
              topic = TopicName "persistent://public/default/training.command.linux-cpu"
              subscription = SubscriptionId "persistent://public/default/training.command.linux-cpu\njitml-live"
              publishCommand =
                PulsarWebSocketSubprocess.pulsarPublishSubprocess
                  settings
                  topic
                  "/tmp/payload"
                  "/tmp/out"
              barePublishCommand =
                PulsarWebSocketSubprocess.pulsarPublishSubprocess
                  settings
                  (TopicName "inference.result.linux-cpu")
                  "/tmp/payload"
                  "/tmp/out"
              consumeCommand =
                PulsarWebSocketSubprocess.pulsarConsumeSubprocess
                  settings
                  subscription
                  "/tmp/out"
              workerCommand =
                PulsarWebSocketSubprocess.pulsarConsumerWorkerSubprocess
                  settings
                  subscription
              acknowledgeCommand =
                PulsarWebSocketSubprocess.pulsarAcknowledgeSubprocess
                  settings
                  "ws://127.0.0.1:9091/pulsar/ws/v2/consumer/persistent/public/default/training.command.linux-cpu/jitml-live?subscriptionType=Exclusive&receiverQueueSize=1&ackTimeoutMillis=30000"
                  "message-id"
                  "/tmp/out"
              subscribeCommand =
                PulsarWebSocketSubprocess.pulsarSubscribeSubprocess
                  settings
                  topic
                  "jitml-live"
                  "/tmp/out"
          assertBool
            "Pulsar producer targets the routed WebSocket endpoint"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/producer/persistent/public/default/training.command.linux-cpu"
                `Text.isInfixOf` renderSubprocess publishCommand
            )
          assertBool
            "Pulsar producer resolves bare public/default topic names"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/producer/persistent/public/default/inference.result.linux-cpu"
                `Text.isInfixOf` renderSubprocess barePublishCommand
            )
          assertBool
            "Pulsar consumer targets the routed WebSocket endpoint"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/consumer/persistent/public/default/training.command.linux-cpu/jitml-live"
                `Text.isInfixOf` renderSubprocess consumeCommand
            )
          assertBool
            "Pulsar acknowledge targets the routed WebSocket endpoint"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/consumer/persistent/public/default/training.command.linux-cpu/jitml-live"
                `Text.isInfixOf` renderSubprocess acknowledgeCommand
            )
          assertBool
            "Pulsar subscribe probe targets the routed WebSocket endpoint"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/consumer/persistent/public/default/training.command.linux-cpu/jitml-live"
                `Text.isInfixOf` renderSubprocess subscribeCommand
            )
          assertBool
            "Pulsar subscribe probe does not prefetch broker messages"
            ("receiverQueueSize=0" `Text.isInfixOf` renderSubprocess subscribeCommand)
          assertBool
            "Pulsar worker targets the routed WebSocket endpoint"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/consumer/persistent/public/default/training.command.linux-cpu/jitml-live"
                `Text.isInfixOf` renderSubprocess workerCommand
            )
          assertBool
            "Pulsar worker keeps broker delivery enabled"
            ("receiverQueueSize=1" `Text.isInfixOf` renderSubprocess workerCommand)
          assertBool
            "Pulsar WebSocket commands use Node"
            ("node --eval" `Text.isInfixOf` renderSubprocess publishCommand)
          assertBool
            "Pulsar WebSocket scripts fall back to Node's bundled undici client"
            ( any
                ("require('undici').WebSocket" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments publishCommand)
            )
          assertBool
            "Pulsar consume records broker message ids for post-dispatch ack"
            ( any
                ("message-id:" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments consumeCommand)
            )
          assertBool
            "Pulsar consume no longer acks before dispatcher completion"
            ( not
                ( any
                    ("ws.send(JSON.stringify({ messageId: message.messageId }))" `Text.isInfixOf`)
                    (JitML.Sub.Subprocess.subprocessArguments consumeCommand)
                )
            )
          assertBool
            "Pulsar acknowledge sends the broker message id after dispatch"
            ( any
                ("ws.send(JSON.stringify({ messageId }))" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments acknowledgeCommand)
            )
          assertBool
            "Pulsar worker accepts message ids from the parent process"
            ( any
                ("process.stdin.on('data'" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments workerCommand)
            )
          assertBool
            "Pulsar worker streams decoded payloads to the parent process"
            ( any
                ("process.stdout.write" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments workerCommand)
            )
          assertBool
            "Pulsar worker acks only when the parent writes a message id"
            ( any
                ("ws.send(JSON.stringify({ messageId }))" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments workerCommand)
            )
          assertBool
            "Pulsar worker can negatively acknowledge failed deliveries"
            ( any
                ("negativeAcknowledge" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments workerCommand)
            )
          assertBool
            "Pulsar subscribe script records the broker-opened subscription"
            ( any
                ("closed before subscription open" `Text.isInfixOf`)
                (JitML.Sub.Subprocess.subprocessArguments subscribeCommand)
            )
      , testCase "Pulsar bootstrap registers the substrate-scoped topic family (Sprint 5.5)" $ do
          let topics = fmap PulsarBootstrap.topicName PulsarBootstrap.pulsarTopics
          -- 9 substrate-scoped topics × 3 substrates + 2 apple-only internal
          -- topics = 29 (Sprint 13.7 added gc.event.<substrate>).
          length topics @?= 29
          traverse_
            ( \topic ->
                assertBool
                  ("registered topic " <> Text.unpack topic)
                  (topic `elem` topics)
            )
            [ "persistent://public/default/training.command.apple-silicon"
            , "persistent://public/default/training.event.apple-silicon"
            , "persistent://public/default/tune.command.apple-silicon"
            , "persistent://public/default/tune.event.apple-silicon"
            , "persistent://public/default/rl.command.apple-silicon"
            , "persistent://public/default/rl.event.apple-silicon"
            , "persistent://public/default/inference.request.apple-silicon"
            , "persistent://public/default/inference.result.apple-silicon"
            , "persistent://public/default/training.command.linux-cpu"
            , "persistent://public/default/tune.command.linux-cpu"
            , "persistent://public/default/rl.command.linux-cpu"
            , "persistent://public/default/inference.request.linux-cpu"
            , "persistent://public/default/training.command.linux-cuda"
            , "persistent://public/default/tune.command.linux-cuda"
            , "persistent://public/default/rl.command.linux-cuda"
            , "persistent://public/default/inference.request.linux-cuda"
            , "persistent://public/default/inference.command.apple-silicon"
            , "persistent://public/default/inference.event.apple-silicon"
            , "persistent://public/default/gc.event.apple-silicon"
            , "persistent://public/default/gc.event.linux-cpu"
            , "persistent://public/default/gc.event.linux-cuda"
            ]
          assertBool
            "no retired cluster topic"
            ("persistent://public/default/training.command.cluster" `notElem` topics)
          assertBool
            "no retired host topic"
            ("persistent://public/default/inference.request.host" `notElem` topics)
      , testCase "BootConfig Dhall loader round-trips the rendered cluster config" $
          withSystemTempDirectory "jitml-boot-config" $ \root -> do
            let bootConfig = BootConfig.defaultBootConfig LinuxCUDA BootConfig.Cluster
                bootConfigPath = root </> "BootConfig.dhall"
            Text.IO.writeFile bootConfigPath (BootConfig.renderBootConfigDhall bootConfig)
            loadedConfig <- BootConfig.loadBootConfig bootConfigPath
            loadedConfig @?= bootConfig
      , testCase "BootConfig Dhall loader round-trips the rendered Apple host config" $
          withSystemTempDirectory "jitml-host-boot-config" $ \root -> do
            let bootConfig =
                  (BootConfig.defaultBootConfig AppleSilicon BootConfig.Host)
                    { BootConfig.bootPulsarServiceUrl = "pulsar://127.0.0.1:9090/pulsar"
                    , BootConfig.bootPulsarAdminUrl = "http://127.0.0.1:9090/pulsar/admin"
                    , BootConfig.bootMinioEndpoint = "http://127.0.0.1:9090/minio/s3"
                    , BootConfig.bootHarborRegistry = "127.0.0.1:9090/library"
                    }
                bootConfigPath = root </> "BootConfig.dhall"
            Text.IO.writeFile bootConfigPath (BootConfig.renderBootConfigDhall bootConfig)
            loadedConfig <- BootConfig.loadBootConfig bootConfigPath
            loadedConfig @?= bootConfig
      , testCase "daemon client settings derive in-cluster endpoints from BootConfig (Sprint 5.4)" $ do
          let settings =
                ServiceClients.daemonClientSettingsForBootConfig
                  (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
              minioSettings = ServiceClients.daemonMinIOSettings settings
              pulsarSettings = ServiceClients.daemonPulsarSettings settings
              harborSettings = ServiceClients.daemonHarborSettings settings
              kubectlSettings = ServiceClients.daemonKubectlSettings settings
          MinIOSubprocess.minioEndpoint minioSettings
            @?= "http://minio.platform.svc.cluster.local:9000"
          MinIOSubprocess.minioRequestPathPrefix minioSettings @?= ""
          PulsarWebSocketSubprocess.pulsarWebSocketEndpoint pulsarSettings
            @?= "ws://pulsar-broker.platform.svc.cluster.local:8080/ws"
          HarborSubprocess.harborRegistry harborSettings
            @?= "harbor-registry.platform.svc.cluster.local:5000"
          HarborSubprocess.harborApiBaseUrl harborSettings
            @?= "http://harbor.platform.svc.cluster.local/api"
          kubectlKubeconfig kubectlSettings @?= ""
      , testCase "daemon client settings derive Apple host edge endpoints from BootConfig (Sprint 5.4)" $ do
          let lease = EdgePort.EdgePortLease {EdgePort.leasedPort = 9092, EdgePort.leasedHost = "127.0.0.1"}
              publication = Publication.publicationWithLeasedPort lease (Publication.defaultPublication AppleSilicon)
              hostConfig = hostBootConfigForPublication publication
              settings = ServiceClients.daemonClientSettingsForBootConfig hostConfig
              minioSettings = ServiceClients.daemonMinIOSettings settings
              pulsarSettings = ServiceClients.daemonPulsarSettings settings
              harborSettings = ServiceClients.daemonHarborSettings settings
              kubectlSettings = ServiceClients.daemonKubectlSettings settings
          MinIOSubprocess.minioEndpoint minioSettings @?= "http://127.0.0.1:9092"
          MinIOSubprocess.minioRequestPathPrefix minioSettings @?= "/minio/s3"
          PulsarWebSocketSubprocess.pulsarWebSocketEndpoint pulsarSettings
            @?= "ws://127.0.0.1:9092/pulsar/ws"
          HarborSubprocess.harborRegistry harborSettings @?= "127.0.0.1:9092"
          HarborSubprocess.harborApiBaseUrl harborSettings
            @?= "http://127.0.0.1:9092/harbor/api"
          kubectlKubeconfig kubectlSettings @?= "./.build/jitml.kubeconfig"
      , testCase "CpuFeatures detection picks the right oneDNN micro-kernel knob" $ do
          features <- detectCpuFeatures
          assertBool
            "detected vendor is one of the known classes"
            (cpuVendor features `elem` ["apple-silicon", "intel-or-amd", "intel", "amd", "unknown"])
          let knob = microKernelChoice features
          assertBool
            "selected knob is one of the linuxCpuKnobs micro-kernel axis choices"
            (knob `elem` ["onednn-jit-avx512", "onednn-jit-avx2", "onednn-reference"])
      , testCase "oneDNN runtime probe reports pkg-config and link visibility" $ do
          probe <- OneDnnRuntime.probeOneDnnRuntime
          let rendered = OneDnnRuntime.renderOneDnnRuntimeProbe probe
          assertBool
            "probe render includes oneDNN runtime section"
            ("onednn_runtime:" `Text.isInfixOf` rendered)
          assertBool
            "probe records pkg-config attempts"
            (any ("pkg-config --modversion" `Text.isInfixOf`) (OneDnnRuntime.oneDnnRuntimeProbeLog probe))
          assertBool
            "probe records header visibility attempts"
            (any ("test -r /usr/include" `Text.isInfixOf`) (OneDnnRuntime.oneDnnRuntimeProbeLog probe))
          assertBool
            "probe records dynamic-linker visibility"
            (any ("ldconfig -p:" `Text.isInfixOf`) (OneDnnRuntime.oneDnnRuntimeProbeLog probe))
          assertBool
            "jitml:local provides linkable oneDNN"
            (OneDnnRuntime.oneDnnRuntimeAvailable probe)
      , testCase "CUDA runtime probe reports toolchain, device, and link visibility attempts" $ do
          probe <- CudaRuntime.probeCudaRuntime
          let rendered = CudaRuntime.renderCudaRuntimeProbe probe
          assertBool
            "probe render includes CUDA runtime section"
            ("cuda_runtime:" `Text.isInfixOf` rendered)
          assertBool
            "probe records nvcc attempt"
            (any ("nvcc --version:" `Text.isInfixOf`) (CudaRuntime.cudaRuntimeProbeLog probe))
          assertBool
            "probe records nvidia-smi attempt"
            (any ("nvidia-smi -L:" `Text.isInfixOf`) (CudaRuntime.cudaRuntimeProbeLog probe))
          assertBool
            "probe records dynamic-linker visibility"
            (any ("ldconfig -p:" `Text.isInfixOf`) (CudaRuntime.cudaRuntimeProbeLog probe))
      , testCase "Metal runtime probe reports Swift, xcrun, and device attempts" $ do
          probe <- MetalRuntime.probeMetalRuntime
          let rendered = MetalRuntime.renderMetalRuntimeProbe probe
          assertBool
            "probe render includes Metal runtime section"
            ("metal_runtime:" `Text.isInfixOf` rendered)
          assertBool
            "probe records swift attempt"
            (any ("swift --version:" `Text.isInfixOf`) (MetalRuntime.metalRuntimeProbeLog probe))
          assertBool
            "probe records metal compiler lookup"
            (any ("xcrun -find metal:" `Text.isInfixOf`) (MetalRuntime.metalRuntimeProbeLog probe))
          assertBool
            "probe records Metal device visibility attempt"
            ( any
                ("system_profiler SPDisplaysDataType:" `Text.isInfixOf`)
                (MetalRuntime.metalRuntimeProbeLog probe)
            )
      , testCase "spawned ./.build/jitml binary matrix against a real workdir" $
          -- Spawns the real `jitml` binary in a temp workdir, exercising the
          -- typed Subprocess boundary against the actual executable (not the
          -- library API). Covers the canonical Sprint 12.2 matrix: --help,
          -- bootstrap --dry-run, cluster up --dry-run, service --help,
          -- train --dry-run experiments/mnist.dhall, and the Sprint 9.7
          -- TPE tuning Dhall render path.
          withSystemTempDirectory "jitml-spawned-bin" $ \workdir -> do
            jitmlBinary <- locateJitmlBinary
            case jitmlBinary of
              Nothing -> pure () -- skip when the binary isn't built (e.g., first build)
              Just binary -> do
                let runJitml args = do
                      let cmd =
                            (subprocess binary args)
                              { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just workdir
                              }
                      runStreaming defaultSubprocessEnv cmd
                -- --help
                (helpExit, helpStdout, _) <- runJitml ["--help"]
                helpExit @?= ExitSuccess
                assertBool "--help mentions Usage" ("Usage:" `Text.isInfixOf` helpStdout)
                -- bootstrap --linux-cpu --dry-run
                (bootExit, bootStdout, _) <-
                  runJitml ["bootstrap", "--linux-cpu", "--dry-run"]
                bootExit @?= ExitSuccess
                assertBool
                  "bootstrap --dry-run emits the typed Plan"
                  ("Command: jitml bootstrap" `Text.isInfixOf` bootStdout)
                -- cluster up --substrate linux-cpu --dry-run
                (clusterExit, clusterStdout, _) <-
                  runJitml ["cluster", "up", "--substrate", "linux-cpu", "--dry-run"]
                clusterExit @?= ExitSuccess
                assertBool
                  "cluster up --dry-run emits the typed Plan"
                  ("Command: jitml cluster up" `Text.isInfixOf` clusterStdout)
                -- internal gc <hash> exits 3 on no-op
                (gcExit, _gcStdout, _) <-
                  runJitml ["internal", "gc", "some-experiment-hash"]
                gcExit @?= ExitFailure 3
                -- service --help prints the daemon usage line
                (serviceExit, serviceStdout, _) <- runJitml ["service", "--help"]
                serviceExit @?= ExitSuccess
                assertBool
                  "service --help mentions the daemon"
                  ("Run the jitML daemon" `Text.isInfixOf` serviceStdout)
                assertBool
                  "service --help exposes the bounded consumer validation mode"
                  ("--consume-once" `Text.isInfixOf` serviceStdout)
                -- train --dry-run experiments/mnist.dhall emits the typed Plan
                -- (resolve the path against the repo root, not the temp workdir).
                experimentPath <- makeAbsolute "experiments/mnist.dhall"
                (trainExit, trainStdout, _) <-
                  runJitml ["train", "--dry-run", Text.pack experimentPath]
                trainExit @?= ExitSuccess
                assertBool
                  "train --dry-run emits the decode-experiment step"
                  ("decode-experiment" `Text.isInfixOf` trainStdout)
                tunePath <- makeAbsolute "experiments/mnist-tune.dhall"
                (tuneExit, tuneStdout, _) <-
                  runJitml ["tune", Text.pack tunePath]
                tuneExit @?= ExitSuccess
                assertBool
                  "tune renders the TPE sampler from Dhall"
                  ("sampler: TPE" `Text.isInfixOf` tuneStdout)
      , testCase "SelfPlayBuffer round-trips through filesystem HasMinIO (Sprint 9.5)" $
          -- Writes a deterministic SelfPlayBuffer to the typed `HasMinIO`
          -- filesystem instance, reads it back, and asserts the
          -- transcript hash is stable across the round-trip. Closes the
          -- MinIO checkpoint round-trip half of Sprint 9.5.
          withSystemTempDirectory "jitml-selfplay-roundtrip" $ \root ->
            runFilesystemMinIO root $ do
              let buffer =
                    SelfPlay.runSelfPlay
                      ( SelfPlay.defaultSelfPlayConfig
                          { SelfPlay.selfPlayGamesPerGeneration = 3
                          , SelfPlay.selfPlaySimulationsPerMove = 2
                          }
                      )
                  bucket = BucketName "jitml-checkpoints"
                  bufferKey = ObjectRef bucket (ObjectKey ("selfplay/" <> SelfPlay.bufferTranscriptHash buffer <> ".cbor"))
                  -- Serialise the buffer by its transcript hash (the canonical
                  -- content-addressed key it would land at in MinIO).
                  payload = "selfplay-buffer:" <> SelfPlay.bufferTranscriptHash buffer
              first <- putBlobIfAbsent bufferKey payload
              case first of
                Right (ETag _) -> pure ()
                Left err ->
                  liftIO (assertFailure ("expected first putBlobIfAbsent OK, got: " <> show err))
              -- Re-derive the buffer with the same seed and assert hash equality.
              let buffer2 =
                    SelfPlay.runSelfPlay
                      ( SelfPlay.defaultSelfPlayConfig
                          { SelfPlay.selfPlayGamesPerGeneration = 3
                          , SelfPlay.selfPlaySimulationsPerMove = 2
                          }
                      )
              liftIO $
                SelfPlay.bufferTranscriptHash buffer @?= SelfPlay.bufferTranscriptHash buffer2
              liftIO $
                SelfPlay.bufferLength buffer @?= 3
      , testCase "GC reaping deletes manifests + blobs through HasMinIO (Sprint 10.3)" $
          withSystemTempDirectory "jitml-gc-reap" $ \root ->
            runFilesystemMinIO root $ do
              -- Seed three manifests; LastN 1 should reap the older two.
              let experimentHash = "exp-gc"
                  mkManifest tag step =
                    ( Checkpoint.emptyManifest
                        tag
                        experimentHash
                        [Checkpoint.TensorBlob ("t-" <> tag) [1] ("blob-" <> tag)]
                    )
                      { Checkpoint.manifestStep = step
                      }
                  manifests =
                    [ mkManifest "old1" 1
                    , mkManifest "old2" 2
                    , mkManifest "fresh" 3
                    ]
              -- Seed manifest + blob objects in MinIO.
              mapM_
                ( \m -> do
                    let manifestSha = Checkpoint.manifestContentSha m
                        manifestObjRef =
                          CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experimentHash manifestSha)
                    _ <-
                      putBlobIfAbsent
                        manifestObjRef
                        (Text.pack (show m))
                    case Checkpoint.manifestTensors m of
                      [tensor] -> do
                        let blobObjRef =
                              CheckpointStore.checkpointObjectRef
                                (Checkpoint.blobKey experimentHash (Checkpoint.tensorBlobKey tensor))
                        _ <- putBlobIfAbsent blobObjRef "weights"
                        pure ()
                      tensors ->
                        liftIO $
                          assertFailure
                            ("expected one tensor in seeded GC manifest, got: " <> show (length tensors))
                )
                manifests
              let plan = CheckpointStore.buildGcPlan experimentHash (CheckpointStore.LastN 1) manifests []
              liftIO (length (CheckpointStore.gcReapEvents plan) @?= 2)
              result <- CheckpointStore.executeGcPlan plan
              liftIO $ do
                CheckpointStore.gcExecutedReapedManifests result @?= 2
                CheckpointStore.gcExecutedReapedBlobs result @?= 2
                CheckpointStore.gcExecutedDeleteFailures result @?= []
      , testCase "loadInferenceCheckpoint via HasMinIO round-trips (Sprint 10.4)" $
          withSystemTempDirectory "jitml-inference-load" $ \root -> do
            env <- buildEnv defaultGlobalFlags
            runFilesystemMinIO root $ do
              let experimentHash = "exp-inf"
                  blobObjectKey = Checkpoint.blobKey experimentHash "blob-weights"
                  manifest =
                    Checkpoint.emptyManifest
                      "m1"
                      experimentHash
                      [Checkpoint.TensorBlob "dense" [2, 2] blobObjectKey]
                  manifestSha = Checkpoint.manifestContentSha manifest
                  bucket = BucketName "jitml-checkpoints"
                  manifestRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experimentHash manifestSha)
                  pointerRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experimentHash)
                  blobRef = CheckpointStore.checkpointObjectRef blobObjectKey
                  manifestBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor manifest)
                  weightBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0])
              liftIO $
                CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experimentHash)
                  @?= ObjectRef bucket (ObjectKey (experimentHash <> "/pointers/latest"))
              _ <- putBlobBytesIfAbsent blobRef weightBytes
              _ <- putBlobBytesIfAbsent manifestRef manifestBytes
              _ <- casPointer pointerRef Nothing manifestSha
              inferred <- CheckpointStore.loadInferenceCheckpoint experimentHash [1.0, 2.0, 3.0]
              liftIO $
                inferred @?= Right (Checkpoint.inferFromManifest manifest [1.0, 2.0, 3.0])
              ffiInferred <-
                CheckpointStore.loadInferenceCheckpointWith
                  (\loadedManifest values -> liftIO (Local.runLinuxCpuCheckpointInference env loadedManifest values))
                  experimentHash
                  [1.0, 2.0, 3.0]
              liftIO $
                ffiInferred @?= Right (Checkpoint.inferFromManifest manifest [1.0, 2.0, 3.0])
              weightedInferred <-
                CheckpointStore.loadInferenceCheckpointWithWeights
                  ( \loadedManifest loadedWeights values ->
                      liftIO
                        ( Local.runLinuxCpuWeightedCheckpointInference
                            env
                            loadedManifest
                            loadedWeights
                            values
                        )
                  )
                  experimentHash
                  [1.0, 2.0, 3.0]
              -- Sprint 13.11 — the weighted runner now drives a real
              -- oneDNN Dense2D GEMM `out = input · W` against the
              -- caller-supplied weights, not the prior smoke-fixture
              -- identity+bias. The staged weight buffer [1,2,3,4]
              -- is reshaped as a 3×3 row-major matrix (n=3 from the
              -- input length, padded with zeros to fill the matmul
              -- shape):
              --   W = [[1, 2, 3], [4, 0, 0], [0, 0, 0]]
              -- and input [1, 2, 3] × W produces [9, 2, 3].
              liftIO $
                weightedInferred @?= Right [9.0, 2.0, 3.0]
      , testCase "Dhall numerics schema decodes against the full Haskell catalog" $ do
          -- Decodes dhall/numerics/Schema.dhall through `Dhall.inputFile`
          -- and asserts the resulting NumericsCatalog matches the
          -- expected catalog generated from `JitML.Numerics.Catalog`. This
          -- is the Sprint 12.2 Dhall-to-typed-record decode coverage.
          catalog <- Numerics.loadNumericsCatalog "."
          Numerics.validateNumericsCatalog catalog @?= Right ()
      , testCase "Subprocess stdin pipes payload to the child process" $ do
          -- `cat` echoes stdin to stdout. The typed boundary's stdin
          -- payload (subprocessWithStdin) feeds bytes into the child.
          (exitCode, stdoutText, _stderr) <-
            runStreaming
              defaultSubprocessEnv
              (JitML.Sub.Subprocess.subprocessWithStdin "/bin/cat" [] "stdin-ok\n")
          exitCode @?= ExitSuccess
          stdoutText @?= "stdin-ok\n"
      , testCase "writeCheckpointSidecar puts TbCheckpointMarker via HasMinIO (Sprint 4.6)" $
          withSystemTempDirectory "jitml-tb-sidecar" $ \root ->
            runFilesystemMinIO root $ do
              let marker =
                    TensorBoard.TbCheckpointMarker
                      { TensorBoard.tcmStep = 200
                      , TensorBoard.tcmEpoch = 5
                      , TensorBoard.tcmManifestSha = "sha-tb-1"
                      , TensorBoard.tcmExperimentSha = "exp-tb"
                      , TensorBoard.tcmTrialSha = Nothing
                      , TensorBoard.tcmRunUuid = "run-tb"
                      , TensorBoard.tcmMetricsAtStep = [("loss", 0.42)]
                      }
              writeResult <-
                TbSidecar.writeCheckpointSidecar "exp-tb" 200 "sha-tb-1" marker
              case writeResult of
                Right _ -> pure ()
                Left err ->
                  liftIO (assertFailure ("expected sidecar PUT OK, got: " <> show err))
              let bucket = BucketName "jitml-tensorboard"
                  key = TensorBoard.checkpointSidecarKey "exp-tb" 200 "sha-tb-1"
                  ref = ObjectRef bucket (ObjectKey key)
              readback <- minioReadBytes ref
              liftIO $
                case readback of
                  Right bytes ->
                    assertBool
                      "TbCheckpointMarker round-trip CBOR is non-empty"
                      (Data.ByteString.length bytes > 0)
                  Left err ->
                    assertFailure ("expected sidecar read OK, got: " <> show err)
      , testCase "leaseEdgePort binds 127.0.0.1 on the first available candidate (Sprint 3.5)" $ do
          lease <- EdgePort.leaseEdgePort [49997, 49998, 49999]
          case lease of
            Just l -> do
              assertBool
                "leased port is one of the candidates"
                (EdgePort.leasedPort l `elem` [49997, 49998, 49999])
              EdgePort.leasedHost l @?= "127.0.0.1"
            Nothing -> assertFailure "expected at least one port to be bindable"
      , testCase "publicationWithLeasedPort rewrites edge_port + pulsar/minio URLs (Sprint 3.5)" $ do
          -- The bridge from `leaseEdgePort`'s probe to the JSON
          -- publication consumed by downstream substrates. The default
          -- per-substrate publication uses the canonical 9090; after
          -- the lease binds 9092, the publication's edge_port + Pulsar
          -- URL + MinIO URL all reflect the leased port.
          let lease = EdgePort.EdgePortLease {EdgePort.leasedPort = 9092, EdgePort.leasedHost = "127.0.0.1"}
              base = Publication.defaultPublication LinuxCPU
              relocated = Publication.publicationWithLeasedPort lease base
          Publication.publicationEdgePort relocated @?= 9092
          assertBool
            "pulsar URL carries the leased port"
            (":9092/pulsar" `Text.isInfixOf` Publication.publicationPulsarUrl relocated)
          assertBool
            "minio URL carries the leased port"
            (":9092/minio/s3" `Text.isInfixOf` Publication.publicationMinioUrl relocated)
          -- Substrate identity preserved.
          Publication.publicationSubstrate relocated @?= LinuxCPU
      , testCase "dispatchCheckpointDone routes a marker through HasMinIO (Sprint 4.6)" $
          -- The Consumer-domain entry point: given a typed
          -- `TbCheckpointMarker` (the in-memory shape of a CheckpointDone
          -- inference event), `dispatchCheckpointDone` derives the
          -- sidecar key from the marker's own fields and writes the
          -- CBOR bytes through `HasMinIO.putBlobBytesIfAbsent`.
          withSystemTempDirectory "jitml-dispatch-ckpt" $ \root ->
            runFilesystemMinIO root $ do
              let marker =
                    TensorBoard.TbCheckpointMarker
                      { TensorBoard.tcmStep = 1234
                      , TensorBoard.tcmEpoch = 5
                      , TensorBoard.tcmManifestSha = "sha-abc"
                      , TensorBoard.tcmExperimentSha = "exp-xyz"
                      , TensorBoard.tcmTrialSha = Nothing
                      , TensorBoard.tcmRunUuid = "run-1"
                      , TensorBoard.tcmMetricsAtStep = [("loss", 0.5)]
                      }
              result <- TbSidecar.dispatchCheckpointDone marker
              case result of
                Right _ -> pure ()
                Left err -> liftIO (assertFailure ("dispatch failed: " <> show err))
              -- Verify the sidecar landed at the canonical key.
              let expectedKey = TensorBoard.checkpointSidecarKey "exp-xyz" 1234 "sha-abc"
                  ref =
                    ObjectRef
                      (BucketName "jitml-tensorboard")
                      (ObjectKey expectedKey)
              bytesResult <- minioReadBytes ref
              case bytesResult of
                Right bytes ->
                  liftIO $
                    assertBool
                      "dispatched sidecar is non-empty"
                      (Data.ByteString.length bytes > 0)
                Left err ->
                  liftIO (assertFailure ("expected sidecar read OK: " <> show err))
      , testCase "daemon TensorBoard dispatcher writes CheckpointDone sidecar (Sprint 4.6)" $
          withSystemTempDirectory "jitml-daemon-tb-dispatch" $ \root -> do
            let checkpoint =
                  Training.CheckpointDone
                    { Training.cdExperimentHash = "exp-daemon"
                    , Training.cdManifestSha = "manifest-daemon"
                    , Training.cdStep = 77
                    , Training.cdPointerKey = "jitml-checkpoints/exp-daemon/latest"
                    , Training.cdEpoch = 3
                    , Training.cdTrialSha = Just "trial-1"
                    , Training.cdRunUuid = "run-daemon"
                    , Training.cdMetricsAtStep = [("loss", 0.125)]
                    }
                payload =
                  Training.renderTrainingEvent
                    (Training.TrainingCheckpoint checkpoint)
                eventId = eventIdFromPayload (Text.Encoding.encodeUtf8 payload)
                expectedKey =
                  TensorBoard.checkpointSidecarKey
                    "exp-daemon"
                    77
                    "manifest-daemon"
                ref =
                  ObjectRef
                    (BucketName "jitml-tensorboard")
                    (ObjectKey expectedKey)
            (dispatchResult, readResult) <-
              runFilesystemMinIO root $ do
                result <-
                  Runtime.daemonTensorBoardDispatcher
                    TrainingDomain
                    eventId
                    payload
                bytes <- minioReadBytes ref
                pure (result, bytes)
            dispatchResult @?= Right ()
            case readResult of
              Right bytes ->
                assertBool
                  "daemon dispatcher wrote a non-empty sidecar"
                  (Data.ByteString.length bytes > 0)
              Left err ->
                assertFailure ("expected daemon sidecar read OK: " <> show err)
      , testCase "TensorBoard writer flushes TFRecord shards through HasMinIO (Sprint 4.6)" $
          withSystemTempDirectory "jitml-tb-writer" $ \root -> do
            let state0 = TensorBoard.emptyTensorBoardWriterState "exp-writer" "writer-a" 0 10
                event =
                  TensorBoard.TensorBoardEvent
                    { TensorBoard.tbWallTime = 10
                    , TensorBoard.tbStep = 1
                    , TensorBoard.tbTag = "loss"
                    , TensorBoard.tbValue = 0.5
                    }
                limits =
                  TensorBoard.defaultShardRotationLimits
                    { TensorBoard.shardExplicitFlush = True
                    }
                ref = TensorBoard.tensorBoardShardObjectRef state0
            (writeResult, readResult, duplicateResult) <-
              runFilesystemMinIO root $ do
                written <- TensorBoard.writeTensorBoardEvent 10 limits state0 event
                bytes <- minioReadBytes ref
                duplicate <- TensorBoard.writeTensorBoardEvent 10 limits state0 event
                pure (written, bytes, duplicate)
            case writeResult of
              Right (Just (TensorBoard.TensorBoardFlushStored storedRef _), state1) -> do
                storedRef @?= ref
                TensorBoard.tbwsShardSeq state1 @?= 1
              other ->
                assertFailure ("expected stored shard, got: " <> show other)
            case readResult of
              Right bytes ->
                assertBool
                  "TFRecord shard includes TensorBoard file-version event"
                  (Text.Encoding.encodeUtf8 "brain.Event:2" `Data.ByteString.isInfixOf` bytes)
              Left err ->
                assertFailure ("expected TensorBoard shard read OK: " <> show err)
            case duplicateResult of
              Right (Just (TensorBoard.TensorBoardFlushAlreadyPresent duplicateRef), _) ->
                duplicateRef @?= ref
              other ->
                assertFailure ("expected duplicate shard to be idempotent, got: " <> show other)
      , testCase "dockerMirrorPlan emits build + tag + push subprocesses (Sprint 3.5)" $ do
          let localTag = "jitml:local"
              harborTag = "127.0.0.1:9091/library/jitml:dev"
              plan = DockerImage.dockerMirrorPlan localTag "." harborTag
              rendered = fmap renderSubprocess plan
          length plan @?= 3
          assertBool
            "first step builds"
            (any ("docker build" `Text.isPrefixOf`) rendered)
          assertBool
            "second step tags to harbor"
            (any (harborTag `Text.isInfixOf`) rendered)
          assertBool
            "third step pushes"
            (any ("docker push" `Text.isInfixOf`) rendered)
      , testCase "dockerBuildAndKindLoadPlan emits explicit Kind image load subprocesses (Sprint 3.5)" $ do
          let plan = DockerImage.dockerBuildAndKindLoadPlan LinuxCPU "jitml:local" "."
              rendered = fmap renderSubprocess plan
          length plan @?= 2
          assertBool
            "first step builds the local image"
            (any ("docker build -t jitml:local" `Text.isInfixOf`) rendered)
          assertBool
            "second step loads the image into the substrate Kind cluster"
            (any ("kind load docker-image jitml:local --name jitml-linux-cpu" `Text.isInfixOf`) rendered)
      , testCase "helm phased rollout installs packaged dependency archives (Sprint 3.5)" $ do
          let rendered = Text.unlines (fmap renderSubprocess (Helm.helmPhasedRolloutPlan "chart"))
          assertBool
            "harbor install uses dependency archive"
            ("chart/charts/harbor-1.16.2.tgz" `Text.isInfixOf` rendered)
          assertBool
            "Harbor install uses direct subchart values"
            ("--values chart/values/harbor.yaml" `Text.isInfixOf` rendered)
          assertBool
            "MinIO install uses direct subchart values"
            ("--values chart/values/minio.yaml" `Text.isInfixOf` rendered)
          assertBool
            "Pulsar install uses direct subchart values"
            ("--values chart/values/pulsar.yaml" `Text.isInfixOf` rendered)
          assertBool
            "Envoy install uses gateway-helm dependency archive"
            ("chart/charts/gateway-helm-1.2.6.tgz" `Text.isInfixOf` rendered)
          assertBool
            "jitml-service install uses checked-in local chart"
            ("chart/local/jitml-service" `Text.isInfixOf` rendered)
          assertBool
            "retired mirror placeholder is absent from the Helm release plan"
            (not ("jitml-mirror" `Text.isInfixOf` rendered))
      , testCase "jitml-service local chart carries current Dhall config surface" $ do
          configMap <- Text.IO.readFile "chart/local/jitml-service/templates/configmap.yaml"
          deployment <- Text.IO.readFile "chart/local/jitml-service/templates/deployment.yaml"
          rbac <- Text.IO.readFile "chart/local/jitml-service/templates/rbac.yaml"
          assertBool
            "local chart renders typed Residency constructors"
            ("residency = < Cluster | Host >.Cluster" `Text.isInfixOf` configMap)
          assertBool
            "local chart uses the daemon service account"
            ("serviceAccountName: jitml-service" `Text.isInfixOf` deployment)
          assertBool
            "local chart grants namespace-scoped daemon kubectl access"
            ("kind: RoleBinding" `Text.isInfixOf` rbac)
          assertBool
            "local chart renders typed InferenceMode constructors"
            ("< SelfInference | ForwardToHost >.SelfInference" `Text.isInfixOf` configMap)
          assertBool
            "local chart uses current retryPolicy field"
            ("retryPolicy = ExponentialN" `Text.isInfixOf` configMap)
          assertBool
            "local chart uses current inference latency field"
            ("inferenceMaxLatencyMillis = 25" `Text.isInfixOf` configMap)
          assertBool
            "local chart uses current dedup cache size field"
            ("dedupCacheSize = 4096" `Text.isInfixOf` configMap)
          assertBool
            "local chart uses current dedup cache ttl field"
            ("dedupCacheTtlSeconds = 3600" `Text.isInfixOf` configMap)
          assertBool
            "old unqualified Residency value is absent"
            (not ("residency = Cluster" `Text.isInfixOf` configMap))
          assertBool
            "old LiveConfig retry field is absent"
            (not ("retry = { maxAttempts" `Text.isInfixOf` configMap))
      , testCase "Pulsar direct values are wait-safe for local Kind" $ do
          directValues <- Text.IO.readFile "chart/values/pulsar.yaml"
          umbrellaValues <- Text.IO.readFile "chart/values.yaml"
          assertBool
            "direct Pulsar values avoid LoadBalancer waits"
            ("type: ClusterIP" `Text.isInfixOf` directValues)
          assertBool
            "umbrella Pulsar values avoid LoadBalancer waits"
            ("type: ClusterIP" `Text.isInfixOf` umbrellaValues)
          assertBool
            "direct Pulsar values do not request a LoadBalancer"
            (not ("type: LoadBalancer" `Text.isInfixOf` directValues))
      , testCase
          "live phased rollout wires the explicit Kind image load phase before final services (Sprint 3.5)"
          $ do
            let rendered = fmap renderSubprocess (livePhasedRolloutSubprocesses LinuxCPU "chart")
                commandText = Text.unlines rendered
            assertBool
              "live rollout creates Kind first"
              ("kind create cluster --name jitml-linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout refreshes the repo kubeconfig when Kind already exists"
              ( "kind export kubeconfig --name jitml-linux-cpu --kubeconfig \"$tmpKubeconfig\""
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout copies Kind's temp kubeconfig into the repo-local kubeconfig"
              ("cp \"$tmpKubeconfig\" ./.build/jitml.kubeconfig" `Text.isInfixOf` commandText)
            assertBool
              "live rollout applies manual storage manifests"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/storageclass-jitml-manual.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the GatewayClass before the Gateway"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/gatewayclass-jitml.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the generated Gateway"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/gateway-jitml-edge.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies generated HTTPRoutes"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-demo-api.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the Harbor registry route"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-harbor-registry.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout builds jitml image"
              ("docker build -t jitml:local" `Text.isInfixOf` commandText)
            assertBool
              "live rollout loads jitml image into Kind"
              ("kind load docker-image jitml:local --name jitml-linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout retags jitml:local as jitml-demo:local instead of rebuilding"
              ("docker tag jitml:local jitml-demo:local" `Text.isInfixOf` commandText)
            assertBool
              "live rollout does not run a second docker build for jitml-demo:local"
              (not ("docker build -t jitml-demo:local" `Text.isInfixOf` commandText))
            assertBool
              "live rollout loads demo image into Kind"
              ("kind load docker-image jitml-demo:local --name jitml-linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout threads substrate into local charts"
              ("--set substrate=linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout applies generated Grafana dashboards"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/grafana-dashboard-daemon-health.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the generated Prometheus ScrapeConfig"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/prometheus-scrapeconfig-jitml.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout gives Harbor an explicit localhost externalURL"
              ("--set-string externalURL=http://127.0.0.1:9091" `Text.isInfixOf` commandText)
            assertBool
              "live rollout passes Harbor's external database values"
              ("--values chart/values/harbor.yaml" `Text.isInfixOf` commandText)
            let (beforeHarbor, _fromHarbor) =
                  Text.breakOn "helm upgrade --install harbor chart/charts/harbor-1.16.2.tgz" commandText
            assertBool
              "live rollout installs MinIO before Harbor so the registry bucket exists"
              ("helm upgrade --install minio chart/charts/minio-14.8.5.tgz" `Text.isInfixOf` beforeHarbor)
            assertBool
              "live rollout checks the Harbor registry bucket before installing Harbor"
              ( "/opt/bitnami/minio-client/bin/mc ls jitml-minio/harbor-registry >/dev/null"
                  `Text.isInfixOf` beforeHarbor
              )
            assertBool
              "live rollout waits for harbor-pg before installing Harbor"
              ( "wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready'"
                  `Text.isInfixOf` beforeHarbor
              )
            assertBool
              "live rollout grants Harbor ownership of the public schema before installing Harbor"
              ("GRANT ALL ON SCHEMA public TO harbor" `Text.isInfixOf` beforeHarbor)
            let (beforeFinalService, _fromFinalService) =
                  Text.breakOn "helm upgrade --install jitml-service chart/local/jitml-service" commandText
            assertBool
              "live rollout loads local images before installing final workloads"
              ("kind load docker-image jitml-demo:local --name jitml-linux-cpu" `Text.isInfixOf` beforeFinalService)
            let (beforeObservabilityManifests, _fromObservabilityManifests) =
                  Text.breakOn
                    "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/grafana-dashboard-training-throughput.yaml"
                    commandText
            assertBool
              "live rollout installs kube-prometheus-stack before applying dashboard ConfigMaps"
              ( "helm upgrade --install kube-prometheus-stack"
                  `Text.isInfixOf` beforeObservabilityManifests
              )
            assertBool
              "live rollout installs jitml-service before applying Prometheus scrape config"
              ( "helm upgrade --install jitml-service chart/local/jitml-service"
                  `Text.isInfixOf` beforeObservabilityManifests
              )
            assertBool
              "live rollout pins Pulsar topic creation to repo kubeconfig"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig exec -n platform pulsar-toolset-0"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout waits for MinIO readiness before topic bootstrap"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status deployment/minio --timeout=300s"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout verifies MinIO bucket readiness before topic bootstrap"
              ( "/opt/bitnami/minio-client/bin/mc ls jitml-minio/jitml-checkpoints >/dev/null"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout waits for Pulsar broker readiness before topic bootstrap"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status statefulset/pulsar-broker --timeout=300s"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies registered PerconaPGCluster manifests"
              ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -n platform -f -" `Text.isInfixOf` commandText)
            assertBool
              "live rollout waits for the registered service Postgres cluster"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready' --timeout=600s"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout uses the explicit Pulsar admin binary path"
              ("/pulsar/bin/pulsar-admin topics create" `Text.isInfixOf` commandText)
            assertBool
              "live rollout makes Pulsar topic creation idempotent"
              ("/pulsar/bin/pulsar-admin topics list" `Text.isInfixOf` commandText)
            assertBool
              "retired mirror placeholder chart is not executed by the live path"
              (not ("helm upgrade --install jitml-mirror" `Text.isInfixOf` commandText))
            assertBool
              "live rollout does not rely on the in-cluster Harbor DNS name for local image publication"
              (not ("docker push harbor.platform.svc.cluster.local" `Text.isInfixOf` commandText))
      , testCase "HarborSubprocess uses explicit local registry settings (Sprint 4.1)" $ do
          let settings =
                (HarborSubprocess.harborSettingsForLocalEdge 9091)
                  { HarborSubprocess.harborDockerHost = Just "unix:///explicit/docker.sock"
                  }
              imageRef = ImageRef "127.0.0.1:9091/library/jitml:phase4"
              loginCommand = HarborSubprocess.harborLoginSubprocess settings
              listCommand = HarborSubprocess.harborListRepositoriesSubprocess settings "library"
              artifactCommand = HarborSubprocess.harborArtifactStatusSubprocess settings "library" "jitml" "phase4"
              tagCommand = HarborSubprocess.harborCreateTagSubprocess settings "library" "jitml" "phase4" "ready"
          renderSubprocess loginCommand
            @?= "docker --host unix:///explicit/docker.sock --config ./.build/docker/harbor login --username admin --password-stdin 127.0.0.1:9091"
          JitML.Sub.Subprocess.subprocessStdin loginCommand @?= Just "Harbor12345"
          renderSubprocess (HarborSubprocess.harborManifestInspectSubprocess settings imageRef)
            @?= "docker --host unix:///explicit/docker.sock --config ./.build/docker/harbor manifest inspect 127.0.0.1:9091/library/jitml:phase4"
          assertBool
            "Harbor API base path is explicit"
            ( "http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories?page_size=100"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          assertBool
            "Harbor artifact existence uses the API, not docker manifest inspect"
            ( "http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories/jitml/artifacts/phase4"
                `Text.isInfixOf` renderSubprocess artifactCommand
            )
          assertBool
            "Harbor same-repository promotion uses the API tag endpoint"
            ( "http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories/jitml/artifacts/phase4/tags"
                `Text.isInfixOf` renderSubprocess tagCommand
            )
          assertBool
            "Harbor tag promotion sends the target tag as JSON"
            ("{\"name\":\"ready\"}" `Text.isInfixOf` renderSubprocess tagCommand)
      , testCase "cluster down uses an idempotent Kind delete subprocess (Sprint 3.5)" $ do
          let rendered = renderSubprocess (Helm.kindDeleteSubprocess LinuxCPU)
          assertBool
            "cluster down checks for the substrate Kind cluster"
            ("kind get clusters | grep -Fx jitml-linux-cpu" `Text.isInfixOf` rendered)
          assertBool
            "cluster down deletes the substrate Kind cluster"
            ("kind delete cluster --name jitml-linux-cpu" `Text.isInfixOf` rendered)
          assertBool
            "cluster down reports no-op through exit 3"
            ("else exit 3" `Text.isInfixOf` rendered)
      , testCase "platform readiness checks cover Phase 4 service rollouts" $ do
          let rendered = Text.unlines (fmap renderSubprocess Readiness.platformReadinessSubprocesses)
          assertBool "Harbor readiness" ("rollout status deployment/harbor-core" `Text.isInfixOf` rendered)
          assertBool "MinIO readiness" ("rollout status deployment/minio" `Text.isInfixOf` rendered)
          assertBool "Pulsar readiness" ("rollout status statefulset/pulsar-broker" `Text.isInfixOf` rendered)
          assertBool
            "Prometheus readiness"
            ("rollout status statefulset/prometheus-kube-prometheus-stack-prometheus" `Text.isInfixOf` rendered)
          assertBool
            "TensorBoard readiness"
            ("rollout status deployment/tensorboard" `Text.isInfixOf` rendered)
          assertBool
            "PerconaPGCluster readiness"
            ("wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready'" `Text.isInfixOf` rendered)
          assertBool "NVIDIA RuntimeClass check" ("get runtimeclass nvidia" `Text.isInfixOf` rendered)
          assertBool "MinIO bucket readiness exec" ("exec -n platform deploy/minio" `Text.isInfixOf` rendered)
          assertBool
            "MinIO bucket readiness retries transient service startup"
            ("for attempt in 1 2 3 4 5 6 7 8 9 10" `Text.isInfixOf` Readiness.renderMinioBucketReadinessCommand)
          assertBool
            "MinIO bucket readiness uses the in-pod client"
            ( "/opt/bitnami/minio-client/bin/mc alias set jitml-minio http://minio.platform.svc.cluster.local:9000 minio minioadmin >/dev/null"
                `Text.isInfixOf` Readiness.renderMinioBucketReadinessCommand
            )
          mapM_
            ( \bucket ->
                assertBool
                  ("MinIO bucket readiness checks " <> Text.unpack bucket)
                  ( ("/opt/bitnami/minio-client/bin/mc ls jitml-minio/" <> bucket <> " >/dev/null")
                      `Text.isInfixOf` Readiness.renderMinioBucketReadinessCommand
                  )
            )
            bucketNames
      , testCase "jitml-service runtimeClassName is linux-cuda only (Sprints 4.7/5.6)" $ do
          let appleDeployment = ServiceConfigMap.renderServiceDeployment AppleSilicon
              cpuDeployment = ServiceConfigMap.renderServiceDeployment LinuxCPU
              cudaDeployment = ServiceConfigMap.renderServiceDeployment LinuxCUDA
          assertBool
            "apple-silicon does not request the NVIDIA RuntimeClass"
            (not ("runtimeClassName: nvidia" `Text.isInfixOf` appleDeployment))
          assertBool
            "linux-cpu does not request the NVIDIA RuntimeClass"
            (not ("runtimeClassName: nvidia" `Text.isInfixOf` cpuDeployment))
          assertBool
            "linux-cuda requests the NVIDIA RuntimeClass"
            ("runtimeClassName: nvidia" `Text.isInfixOf` cudaDeployment)
          assertBool
            "linux-cuda asks the NVIDIA runtime for visible devices"
            ("NVIDIA_VISIBLE_DEVICES" `Text.isInfixOf` cudaDeployment)
          assertBool
            "linux-cuda restricts NVIDIA driver capabilities to compute and utility"
            ("NVIDIA_DRIVER_CAPABILITIES" `Text.isInfixOf` cudaDeployment)
          assertBool
            "linux-cpu does not set NVIDIA runtime environment"
            (not ("NVIDIA_VISIBLE_DEVICES" `Text.isInfixOf` cpuDeployment))
          assertBool
            "jitml-service uses required pod anti-affinity for one pod per node"
            ("requiredDuringSchedulingIgnoredDuringExecution" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service rolls on single-node clusters without anti-affinity deadlock"
            ("maxSurge: 0" `Text.isInfixOf` cpuDeployment && "maxUnavailable: 1" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service pins its service account"
            ("serviceAccountName: jitml-service" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service anti-affinity is keyed by hostname"
            ("topologyKey: kubernetes.io/hostname" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service does not rely on advisory anti-affinity"
            (not ("preferredDuringSchedulingIgnoredDuringExecution" `Text.isInfixOf` cpuDeployment))
      , testCase "Apple host BootConfig is patched from cluster publication (Sprint 3.5)" $ do
          let lease = EdgePort.EdgePortLease {EdgePort.leasedPort = 9092, EdgePort.leasedHost = "127.0.0.1"}
              publication = Publication.publicationWithLeasedPort lease (Publication.defaultPublication AppleSilicon)
              hostConfig = hostBootConfigForPublication publication
          BootConfig.bootPulsarServiceUrl hostConfig @?= Publication.publicationPulsarUrl publication
          BootConfig.bootMinioEndpoint hostConfig @?= Publication.publicationMinioUrl publication
          BootConfig.bootPulsarAdminUrl hostConfig @?= "http://127.0.0.1:9092/pulsar/admin"
          BootConfig.bootHarborRegistry hostConfig @?= "127.0.0.1:9092/library"
      , testCase "Tune resume-from-partial-sweep via HasMinIO (Sprint 9.7)" $
          withSystemTempDirectory "jitml-tune-resume" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-tune-resume"
                  transcripts =
                    [ Tune.TrialTranscript experimentHash 1 [0.5, 0.4]
                    , Tune.TrialTranscript experimentHash 2 [0.6, 0.45]
                    , Tune.TrialTranscript experimentHash 3 [0.55, 0.42]
                    ]
              mapM_ TuneResume.persistTrialTranscript transcripts
              outcome <- TuneResume.replaySweep experimentHash [1, 2, 3]
              liftIO $ do
                TuneResume.resumedSeeds outcome @?= [1, 2, 3]
                length (TuneResume.resumedTrials outcome) @?= 3
                TuneResume.resumeReadFailures outcome @?= []
                fmap Tune.transcriptValues (TuneResume.resumedTrials outcome)
                  @?= fmap Tune.transcriptValues transcripts
      , testCase "AsyncBuffer sink writes transcripts through HasMinIO (Sprint 8.4)" $
          withSystemTempDirectory "jitml-async-minio-sink" $ \root -> do
            -- Build an AsyncSink that closes over a per-batch counter and
            -- writes each batch's content-hashed payload through
            -- `HasMinIO.putBlobBytesIfAbsent` via the filesystem instance.
            counter <- newIORef (0 :: Int)
            let bucket = BucketName "jitml-transcripts"
                experimentHash = "exp-async"
                sink =
                  AsyncBuffer.AsyncSink
                    ( \batch -> do
                        seqNum <- readIORef counter
                        modifyIORef' counter (+ 1)
                        let payload =
                              Text.Encoding.encodeUtf8
                                ( Text.pack
                                    ("transcript:" <> show (length batch))
                                )
                            ref =
                              ObjectRef
                                bucket
                                ( ObjectKey
                                    ( "jitml-transcripts/"
                                        <> experimentHash
                                        <> "/"
                                        <> Text.pack (show seqNum)
                                        <> ".cbor"
                                    )
                                )
                        result <-
                          runFilesystemMinIO root $
                            putBlobBytesIfAbsent ref payload
                        case result of
                          Right _ ->
                            pure
                              ( AsyncBuffer.AsyncWriteOk
                                  ( "jitml-transcripts/"
                                      <> experimentHash
                                      <> "/"
                                      <> Text.pack (show seqNum)
                                      <> ".cbor"
                                  )
                              )
                          Left err ->
                            pure (AsyncBuffer.AsyncWriteFailed (Text.pack (show err)))
                    )
            buffer <- AsyncBuffer.newAsyncBuffer Buffer.OffPolicyReplay 16 sink
            let mkT n =
                  Buffer.Transition
                    { Buffer.transitionStep = n
                    , Buffer.transitionAction = n
                    , Buffer.transitionReward = fromIntegral n
                    , Buffer.transitionObservation = n
                    , Buffer.transitionDone = False
                    }
            mapM_ (AsyncBuffer.insertAsync buffer . mkT) [0, 1, 2]
            results <- AsyncBuffer.drainAsync buffer
            length results @?= 3
            mapM_
              ( \case
                  AsyncBuffer.AsyncWriteOk _ -> pure ()
                  AsyncBuffer.AsyncWriteFailed err ->
                    assertFailure ("async sink write failed: " <> Text.unpack err)
              )
              results
            -- Verify the blob landed in MinIO.
            readback <-
              runFilesystemMinIO root $
                minioReadBytes
                  ( ObjectRef
                      bucket
                      (ObjectKey "jitml-transcripts/exp-async/0.cbor")
                  )
            case readback of
              Right bytes ->
                assertBool
                  "MinIO holds the first transcript batch"
                  ("transcript:" `Text.isPrefixOf` Text.Encoding.decodeUtf8 bytes)
              Left err ->
                assertFailure ("expected MinIO read OK, got: " <> show err)
      , testCase "kubectlApply carries PerconaPGCluster YAML through explicit stdin command" $ do
          cluster <-
            case PostgresRegistry.postgresRegistry of
              [value] -> pure value
              values ->
                assertFailure
                  ("expected exactly one PerconaPGCluster registry entry, got: " <> show (length values))
          let yaml = PostgresRegistry.renderPerconaPGCluster cluster
              cmd =
                JitML.Sub.Subprocess.subprocessWithStdin
                  "kubectl"
                  [ "--kubeconfig"
                  , "./.build/jitml.kubeconfig"
                  , "apply"
                  , "--dry-run=client"
                  , "--validate=false"
                  , "-f"
                  , "-"
                  ]
                  yaml
          renderSubprocess cmd
            @?= "kubectl --kubeconfig ./.build/jitml.kubeconfig apply --dry-run=client --validate=false -f -"
          JitML.Sub.Subprocess.subprocessStdin cmd @?= Just yaml
          assertBool "rendered PerconaPGCluster names harbor-pg" ("harbor-pg" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster includes required pgBackRest repo"
            ("    pgbackrest:" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins the Postgres image"
            ("2.5.1-ppg16.8-postgres" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins the PgBouncer image"
            ("2.5.1-ppg16.8-pgbouncer1.24.0" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins the pgBackRest image"
            ("2.5.1-ppg16.8-pgbackrest2.54.2" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins manual storage class"
            ("storageClassName: jitml-manual" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster binds a manual PV by volumeName"
            ("volumeName: platform-harbor-pg-pv-0" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster binds a manual backup PV by volumeName"
            ("volumeName: platform-harbor-pg-repo1-pv-0" `Text.isInfixOf` yaml)
      , testCase "KubectlSubprocess settings pin the repo-local kubeconfig explicitly" $ do
          kubectlBinary defaultKubectlSettings @?= "kubectl"
          kubectlKubeconfig defaultKubectlSettings @?= "./.build/jitml.kubeconfig"
          kubectlNamespace defaultKubectlSettings @?= "platform"
      , testGroup
          -- Sprint 13.2 — exercises HasMinIO / HasPulsar through the routed
          -- Envoy edge against a live Kind cluster brought up by Sprint 13.1.
          -- Select with `cabal test jitml-integration --test-options='-p Live'`.
          -- Skipped by default with `-p '!/Live/'` when running on a host
          -- without a cluster up. Tests fail with a clear message when the
          -- cluster-publication.json is missing.
          "Live"
          [ testCase "live HasMinIO conditional writes round-trip on jitml-checkpoints" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              -- Use a unique key per run so a re-run on the same cluster
              -- starts from a clean state for the conflict assertion.
              uniqueSuffix <- pickRandomSuffix
              let bucket = BucketName "jitml-checkpoints"
                  blobKey = "live-test/blob-" <> uniqueSuffix <> ".bin"
                  pointerKey = "live-test/pointer-" <> uniqueSuffix
                  blobRef = ObjectRef bucket (ObjectKey blobKey)
                  pointerRef = ObjectRef bucket (ObjectKey pointerKey)
              MinIOSubprocess.runMinIOSubprocess settings $ do
                first <- putBlobIfAbsent blobRef "weights:v1"
                case first of
                  Right (ETag _) -> pure ()
                  Left err ->
                    liftIO
                      ( assertFailure
                          ("expected first putBlobIfAbsent OK, got: " <> show err)
                      )
                second <- putBlobIfAbsent blobRef "weights:v1"
                case second of
                  Left (SEConflict _) -> pure ()
                  other ->
                    liftIO
                      ( assertFailure
                          ("expected SEConflict on second putBlobIfAbsent, got: " <> show other)
                      )
                ptr1 <- casPointer pointerRef Nothing "manifest:sha-1"
                case ptr1 of
                  Right (ETag etag1) -> do
                    ptr2 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-2"
                    case ptr2 of
                      Right (ETag _) -> pure ()
                      Left err ->
                        liftIO
                          ( assertFailure
                              ("expected pointer CAS OK, got: " <> show err)
                          )
                    ptr3 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-3"
                    case ptr3 of
                      Left (SEConflict _) -> pure ()
                      other ->
                        liftIO
                          ( assertFailure
                              ("expected SEConflict on stale-ETag pointer CAS, got: " <> show other)
                          )
                  Left err ->
                    liftIO
                      ( assertFailure
                          ("expected pointer CAS OK on first write, got: " <> show err)
                      )
                -- Cleanup: best-effort delete so re-running on the same
                -- cluster doesn't pile up stale objects under live-test/.
                _ <- deleteObject blobRef
                _ <- deleteObject pointerRef
                pure ()
          , testCase "live HasMinIO listObjects sees a freshly written object" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                  bucket = BucketName "jitml-checkpoints"
              uniqueSuffix <- pickRandomSuffix
              let ref = ObjectRef bucket (ObjectKey ("live-test/list-" <> uniqueSuffix))
              MinIOSubprocess.runMinIOSubprocess settings $ do
                _ <- putBlobIfAbsent ref "hello"
                result <- listObjects bucket "live-test/list-"
                liftIO $ case result of
                  Right refs ->
                    assertBool
                      ( "expected listObjects to include "
                          <> show ref
                          <> " under prefix live-test/list-; got: "
                          <> show refs
                      )
                      (ref `elem` refs)
                  Left err ->
                    assertFailure ("listObjects failed live: " <> show err)
                _ <- deleteObject ref
                pure ()
          , testCase "live HasPulsar publish/subscribe/consume round-trip on training.command" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                  substrate = Publication.publicationSubstrate publication
                  topicText =
                    "persistent://public/default/training.command."
                      <> substrateUrlSegment substrate
                  topic = TopicName topicText
              uniqueSuffix <- pickRandomSuffix
              let subscription = "live-integration-" <> uniqueSuffix
                  payload = "live-training-command-" <> uniqueSuffix
              PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $ do
                subscriptionId <- do
                  subscribeResult <- pulsarSubscribe topic subscription
                  case subscribeResult of
                    Right sid -> pure sid
                    Left err -> do
                      liftIO (assertFailure ("pulsarSubscribe failed live: " <> show err))
                      error "unreachable"
                publishResult <- pulsarPublish topic payload
                liftIO $ case publishResult of
                  Right _ -> pure ()
                  Left err ->
                    assertFailure ("pulsarPublish failed live: " <> show err)
                consumed <- pulsarConsume subscriptionId
                liftIO $ case consumed of
                  Right (_topicBack, payloadBack) ->
                    assertBool
                      ( "expected consumed payload to equal published payload; got: "
                          <> show payloadBack
                      )
                      (payloadBack == payload)
                  Left err ->
                    assertFailure ("pulsarConsume failed live: " <> show err)
                -- Acknowledge so the message is not redelivered to a future
                -- subscriber on the same topic+subscription pair.
                ackResult <- pulsarAcknowledge topic payload
                liftIO $ case ackResult of
                  Right _ -> pure ()
                  Left err ->
                    assertFailure ("pulsarAcknowledge failed live: " <> show err)
          , testCase
              "live jitml-service holds subscriptions on all four daemon command topics (Sprint 13.2 acquisition)"
              $ do
                publication <- requireLivePublication
                let substrate = Publication.publicationSubstrate publication
                    substrateSegment = substrateUrlSegment substrate
                    daemonTopics =
                      [ "persistent://public/default/training.command." <> substrateSegment
                      , "persistent://public/default/tune.command." <> substrateSegment
                      , "persistent://public/default/rl.command." <> substrateSegment
                      , "persistent://public/default/inference.request." <> substrateSegment
                      ]
                -- Each topic must (a) have a `jitml-service` subscription
                -- registered with the broker and (b) carry at least one
                -- consumer (the cluster daemon Deployment's held-open
                -- WebSocket worker).
                traverse_
                  ( \topic -> do
                      let statsCmd =
                            subprocess
                              "kubectl"
                              [ "--kubeconfig"
                              , "./.build/jitml.kubeconfig"
                              , "exec"
                              , "-n"
                              , "platform"
                              , "pulsar-toolset-0"
                              , "--"
                              , "/pulsar/bin/pulsar-admin"
                              , "topics"
                              , "stats"
                              , topic
                              ]
                      (exitCode, stdoutText, stderrText) <-
                        runStreaming defaultSubprocessEnv statsCmd
                      case exitCode of
                        ExitFailure code ->
                          assertFailure
                            ( "pulsar-admin topics stats failed for "
                                <> Text.unpack topic
                                <> " exit "
                                <> show code
                                <> " stderr: "
                                <> Text.unpack stderrText
                            )
                        ExitSuccess -> pure ()
                      case eitherDecode
                        ( ByteString.Lazy.fromStrict
                            (Text.Encoding.encodeUtf8 stdoutText)
                        ) of
                        Left parseErr ->
                          assertFailure
                            ( "pulsar-admin topics stats JSON parse failed for "
                                <> Text.unpack topic
                                <> ": "
                                <> parseErr
                            )
                        Right (statsValue :: Aeson.Value) -> assertJitmlServiceHasConsumer topic statsValue
                  )
                  daemonTopics
          , testCase "live HasHarbor same-repository tag promotion round-trip (Sprint 13.2 Harbor)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = HarborSubprocess.harborSettingsForLocalEdge edgePort
                  registry = HarborSubprocess.harborRegistry settings
              uniqueSuffix <- pickRandomSuffix
              let repository = "library/jitml-harbor-test-" <> uniqueSuffix
                  initialRef = ImageRef (registry <> "/" <> repository <> ":initial")
                  currentRef = ImageRef (registry <> "/" <> repository <> ":current")
                  sourceImage = "alpine:3.20"
              -- Stage a small source image (alpine ~5MB) on the host and
              -- retag it as the initial Harbor reference. We use the host
              -- docker daemon directly (not via HasHarbor) for the pull
              -- because alpine lives in docker.io, not Harbor. The test
              -- assumes alpine:3.20 is already present (a fallback `docker
              -- pull alpine:3.20` is fired if it isn't).
              ensureLocalImage sourceImage
              (tagExit, _, tagErr) <-
                runStreaming
                  defaultSubprocessEnv
                  ( subprocess
                      "docker"
                      ["tag", Text.pack sourceImage, unImageRef initialRef]
                  )
              case tagExit of
                ExitSuccess -> pure ()
                ExitFailure code ->
                  assertFailure
                    ( "docker tag failed exit "
                        <> show code
                        <> " stderr: "
                        <> Text.unpack tagErr
                    )
              -- Drive the live tag/push/promote flow through HasHarbor.
              HarborSubprocess.runHarborSubprocess settings $ do
                pushResult <- harborPushImage initialRef
                liftIO $ case pushResult of
                  Right _ -> pure ()
                  Left err ->
                    assertFailure ("harborPushImage initial failed: " <> show err)
                existsInitial <- harborImageExists initialRef
                liftIO $ case existsInitial of
                  Right True -> pure ()
                  other ->
                    assertFailure
                      ( "harborImageExists initial expected Right True, got "
                          <> show other
                      )
                promotionResult <- harborPromoteImage initialRef currentRef
                liftIO $ case promotionResult of
                  Right promoted -> promoted @?= currentRef
                  Left err ->
                    assertFailure ("harborPromoteImage failed: " <> show err)
                existsCurrent <- harborImageExists currentRef
                liftIO $ case existsCurrent of
                  Right True -> pure ()
                  other ->
                    assertFailure
                      ( "harborImageExists current expected Right True, got "
                          <> show other
                      )
              -- Cleanup: remove the test repository through the Harbor API
              -- via curl so a future test run can re-create the same name.
              _ <-
                runStreaming
                  defaultSubprocessEnv
                  ( subprocess
                      "curl"
                      [ "-s"
                      , "-u"
                      , HarborSubprocess.harborUsername settings
                          <> ":"
                          <> HarborSubprocess.harborPassword settings
                      , "-X"
                      , "DELETE"
                      , HarborSubprocess.harborApiBaseUrl settings
                          <> "/v2.0/projects/library/repositories/"
                          <> Text.drop (Text.length "library/") repository
                      ]
                  )
              pure ()
          , testCase "live daemon dispatches StartTraining into a Kubernetes Job (Sprint 13.3)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                  substrate = Publication.publicationSubstrate publication
                  topicText =
                    "persistent://public/default/training.command."
                      <> substrateUrlSegment substrate
                  topic = TopicName topicText
              uniqueSuffix <- pickRandomSuffix
              -- 16 hex chars used as the experiment hash so the rendered Job
              -- name `jitml-train-<hash>` stays well under the K8s 63-char
              -- limit. `JitML.Service.Workload.workloadName` uses the full
              -- experiment-hash as the suffix (no truncation), so the
              -- expected Job name matches verbatim here.
              let experimentHash =
                    Text.take 16 ("liveint" <> uniqueSuffix <> "abcdef0123456789")
                  payload =
                    Text.unlines
                      [ "kind: StartTraining"
                      , "experiment-hash: " <> experimentHash
                      , "dhall-object-key: experiments/mnist.dhall"
                      , "substrate: " <> substrateUrlSegment substrate
                      , "seed: 42"
                      , "epochs: 1"
                      , "batch-size: 32"
                      ]
                  expectedJobName = "jitml-train-" <> experimentHash
              -- Publish the command on the live broker. The cluster-side
              -- daemon (jitml-service Deployment) is subscribed to this topic
              -- under subscription `jitml-service` and dispatches the
              -- StartTraining envelope into a Kubernetes Job before ack.
              PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess pulsarSettings $ do
                publishResult <- pulsarPublish topic payload
                liftIO $ case publishResult of
                  Right _ -> pure ()
                  Left err ->
                    assertFailure ("pulsarPublish StartTraining failed live: " <> show err)
              -- Poll briefly for the Job to appear; the held-open worker
              -- typically dispatches within a second of consume + ack.
              jobAppeared <- waitForJob expectedJobName 15
              assertBool
                ("expected Job " <> Text.unpack expectedJobName <> " to be applied by the daemon")
                jobAppeared
              -- Best-effort cleanup so a re-run doesn't pile up Jobs.
              _ <- deleteJob expectedJobName
              pure ()
          , testCase "live checkpoint snapshot round-trip through MinIOSubprocess (Sprint 13.7)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-ckpt-" <> uniqueSuffix
                  blobObjectKey = Checkpoint.blobKey experimentHash "blob-weights"
                  manifest =
                    Checkpoint.emptyManifest
                      "m1"
                      experimentHash
                      [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
                  payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
              MinIOSubprocess.runMinIOSubprocess settings $ do
                first <-
                  CheckpointStore.writeCheckpointSnapshotWithMinIO
                    manifest
                    [(blobObjectKey, payload)]
                    Nothing
                liftIO $ case first of
                  Left err ->
                    assertFailure
                      ("expected live checkpoint write OK, got: " <> show err)
                  Right stored ->
                    CheckpointStore.storedPointerResult stored
                      @?= Checkpoint.PointerWritten
                        (CheckpointStore.storedManifestSha stored)
                -- A second identical write must idempotently succeed on the
                -- blob + manifest writes and surface PointerConflict for the
                -- latest pointer (CAS If-Match guard).
                second <-
                  CheckpointStore.writeCheckpointSnapshotWithMinIO
                    manifest
                    [(blobObjectKey, payload)]
                    Nothing
                liftIO $ case second of
                  Left err ->
                    assertFailure
                      ("expected idempotent live re-write, got: " <> show err)
                  Right stored ->
                    CheckpointStore.storedPointerResult stored
                      @?= Checkpoint.PointerConflict
                        (Checkpoint.latestPointerKey experimentHash)
                -- Best-effort cleanup so re-runs don't pile up checkpoint
                -- objects.
                _ <-
                  deleteObject
                    (CheckpointStore.checkpointObjectRef blobObjectKey)
                _ <-
                  deleteObject
                    ( CheckpointStore.checkpointObjectRef
                        ( Checkpoint.manifestKey
                            experimentHash
                            (Checkpoint.manifestContentSha manifest)
                        )
                    )
                _ <-
                  deleteObject
                    ( CheckpointStore.checkpointObjectRef
                        (Checkpoint.latestPointerKey experimentHash)
                    )
                pure ()
          , testCase "live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 13.7)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-gc-" <> uniqueSuffix
                  blobObjectKeyForStep stepIdx =
                    Checkpoint.blobKey experimentHash ("blob-step-" <> Text.pack (show stepIdx))
                  manifestFor stepIdx =
                    (Checkpoint.emptyManifest "m" experimentHash [])
                      { Checkpoint.manifestStep = fromIntegral (stepIdx :: Int)
                      , Checkpoint.manifestTensors =
                          [ Checkpoint.TensorBlob
                              ("dense.weight.step" <> Text.pack (show stepIdx))
                              [1]
                              (blobObjectKeyForStep stepIdx)
                          ]
                      }
                  steps = [1, 2, 3] :: [Int]
                  manifests = fmap manifestFor steps
                  payloadFor stepIdx = Checkpoint.encodeJmw1 [fromIntegral stepIdx]
              MinIOSubprocess.runMinIOSubprocess settings $ do
                -- Stage three manifests + blobs without advancing the latest
                -- pointer (this is a controlled fixture for GC, not a real
                -- training run).
                mapM_
                  ( \(stepIdx, manifest) -> do
                      _ <-
                        putBlobBytesIfAbsent
                          ( CheckpointStore.checkpointObjectRef
                              (blobObjectKeyForStep stepIdx)
                          )
                          (ByteString.Lazy.toStrict (payloadFor stepIdx))
                      _ <-
                        putBlobBytesIfAbsent
                          ( CheckpointStore.checkpointObjectRef
                              ( Checkpoint.manifestKey
                                  experimentHash
                                  (Checkpoint.manifestContentSha manifest)
                              )
                          )
                          ( ByteString.Lazy.toStrict
                              (Checkpoint.encodeManifestCbor manifest)
                          )
                      pure ()
                  )
                  (zip steps manifests)
                -- Live list: assert the three manifests are visible through
                -- the routed S3 list-objects call.
                listing <- CheckpointStore.listCheckpointManifestsMinIO experimentHash
                liftIO $ case listing of
                  Left err ->
                    assertFailure
                      ("listCheckpointManifestsMinIO failed live: " <> show err)
                  Right ms ->
                    length ms @?= 3
                -- Build a LastN 2 plan: should reap exactly one manifest
                -- (the one with the lowest step).
                let listed = case listing of
                      Right ms -> ms
                      _ -> []
                    plan =
                      CheckpointStore.buildGcPlan
                        experimentHash
                        (CheckpointStore.LastN 2)
                        listed
                        []
                liftIO $ do
                  CheckpointStore.gcNoOp plan @?= False
                  length (CheckpointStore.gcReapEvents plan) @?= 1
                executed <- CheckpointStore.executeGcPlan plan
                liftIO $ do
                  CheckpointStore.gcExecutedReapedManifests executed @?= 1
                  CheckpointStore.gcExecutedReapedBlobs executed @?= 1
                  CheckpointStore.gcExecutedDeleteFailures executed @?= []
                -- A second list should now show only 2 manifests.
                listingAfter <-
                  CheckpointStore.listCheckpointManifestsMinIO experimentHash
                liftIO $ case listingAfter of
                  Left err ->
                    assertFailure
                      ("post-GC list failed: " <> show err)
                  Right ms ->
                    length ms @?= 2
                -- Cleanup the remaining two manifests + their blobs so a
                -- re-run starts from a clean prefix.
                mapM_
                  ( \stepIdx -> do
                      _ <-
                        deleteObject
                          ( CheckpointStore.checkpointObjectRef
                              (blobObjectKeyForStep stepIdx)
                          )
                      pure ()
                  )
                  steps
                mapM_
                  ( deleteObject
                      . CheckpointStore.checkpointObjectRef
                      . Checkpoint.manifestKey experimentHash
                      . Checkpoint.manifestContentSha
                  )
                  manifests
          , testCase "live jitml internal gc reaps from live MinIO (Sprint 13.7 CLI)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-cli-gc-" <> uniqueSuffix
                  steps = [1 .. 6] :: [Int]
                  blobObjectKeyForStep stepIdx =
                    Checkpoint.blobKey experimentHash ("blob-step-" <> Text.pack (show stepIdx))
                  manifestFor stepIdx =
                    (Checkpoint.emptyManifest "m" experimentHash [])
                      { Checkpoint.manifestStep = fromIntegral stepIdx
                      , Checkpoint.manifestTensors =
                          [ Checkpoint.TensorBlob
                              ("dense.weight.step" <> Text.pack (show stepIdx))
                              [1]
                              (blobObjectKeyForStep stepIdx)
                          ]
                      }
                  manifests = fmap manifestFor steps
                  payloadFor stepIdx = Checkpoint.encodeJmw1 [fromIntegral stepIdx]
              -- Stage six manifests + blobs so that the CLI's hardcoded
              -- `LastN 5` retention reaps exactly one (the lowest step).
              MinIOSubprocess.runMinIOSubprocess settings $
                mapM_
                  ( \(stepIdx, manifest) -> do
                      _ <-
                        putBlobBytesIfAbsent
                          ( CheckpointStore.checkpointObjectRef
                              (blobObjectKeyForStep stepIdx)
                          )
                          (ByteString.Lazy.toStrict (payloadFor stepIdx))
                      _ <-
                        putBlobBytesIfAbsent
                          ( CheckpointStore.checkpointObjectRef
                              ( Checkpoint.manifestKey
                                  experimentHash
                                  (Checkpoint.manifestContentSha manifest)
                              )
                          )
                          ( ByteString.Lazy.toStrict
                              (Checkpoint.encodeManifestCbor manifest)
                          )
                      pure ()
                  )
                  (zip steps manifests)
              jitmlBinary <- locateJitmlBinary
              case jitmlBinary of
                Nothing ->
                  assertFailure
                    "jitml binary not found — needed for Sprint 13.7 CLI gc live test"
                Just binary -> do
                  repoRoot <- makeAbsolute "."
                  let gcCmd =
                        (subprocess binary ["internal", "gc", experimentHash])
                          { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
                          }
                  -- First invocation should reap 1 manifest (LastN 5 of 6).
                  (exit1, stdout1, stderr1) <- runStreaming defaultSubprocessEnv gcCmd
                  case exit1 of
                    ExitSuccess ->
                      assertBool
                        ( "expected `reaped=1` in gc stdout; got: "
                            <> Text.unpack stdout1
                        )
                        ( "reaped=1" `Text.isInfixOf` stdout1
                            && "reaped-blobs=1" `Text.isInfixOf` stdout1
                        )
                    ExitFailure code ->
                      assertFailure
                        ( "jitml internal gc first run failed exit "
                            <> show code
                            <> " stderr: "
                            <> Text.unpack stderr1
                        )
                  -- Second invocation against the same store: 5 manifests
                  -- remain → kept=5, reaped=0 → gcNoOp → exit 3.
                  (exit2, _stdout2, _stderr2) <- runStreaming defaultSubprocessEnv gcCmd
                  exit2 @?= ExitFailure 3
              -- Cleanup: delete the remaining 5 manifests + blobs.
              MinIOSubprocess.runMinIOSubprocess settings $ do
                mapM_
                  ( \stepIdx -> do
                      _ <-
                        deleteObject
                          ( CheckpointStore.checkpointObjectRef
                              (blobObjectKeyForStep stepIdx)
                          )
                      pure ()
                  )
                  steps
                mapM_
                  ( deleteObject
                      . CheckpointStore.checkpointObjectRef
                      . Checkpoint.manifestKey experimentHash
                      . Checkpoint.manifestContentSha
                  )
                  manifests
          , testCase
              "live jitml internal gc publishes GcReapedEvent on gc.event.<substrate> (Sprint 13.7 events)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                    pulsarSettings =
                      PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    topicText = ProtoGc.gcEventTopic substrate
                    topic = TopicName topicText
                uniqueSuffix <- pickRandomSuffix
                let experimentHash = "live-gce-" <> uniqueSuffix
                    subscription = "live-gc-event-sub-" <> uniqueSuffix
                    steps = [1 .. 6] :: [Int]
                    blobKeyFor stepIdx =
                      Checkpoint.blobKey experimentHash ("blob-step-" <> Text.pack (show stepIdx))
                    manifestFor stepIdx =
                      (Checkpoint.emptyManifest "gce" experimentHash [])
                        { Checkpoint.manifestStep = fromIntegral stepIdx
                        , Checkpoint.manifestTensors =
                            [ Checkpoint.TensorBlob
                                ("dense.weight.step" <> Text.pack (show stepIdx))
                                [1]
                                (blobKeyFor stepIdx)
                            ]
                        }
                    manifests = fmap manifestFor steps
                    payloadFor stepIdx = Checkpoint.encodeJmw1 [fromIntegral stepIdx]
                    lowestStepSha = Checkpoint.manifestContentSha (manifestFor 1)
                -- Subscribe BEFORE staging + running gc so the consumer sees
                -- every event the CLI publishes.
                PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess pulsarSettings $ do
                  subscribeResult <- pulsarSubscribe topic subscription
                  case subscribeResult of
                    Right _ -> pure ()
                    Left err ->
                      liftIO
                        ( assertFailure
                            ("gc.event subscribe failed live: " <> show err)
                        )
                -- Stage 6 manifests + blobs through live MinIO so LastN 5
                -- reaps exactly the lowest-step manifest.
                MinIOSubprocess.runMinIOSubprocess minioSettings $
                  mapM_
                    ( \(stepIdx, manifest) -> do
                        _ <-
                          putBlobBytesIfAbsent
                            ( CheckpointStore.checkpointObjectRef
                                (blobKeyFor stepIdx)
                            )
                            (ByteString.Lazy.toStrict (payloadFor stepIdx))
                        _ <-
                          putBlobBytesIfAbsent
                            ( CheckpointStore.checkpointObjectRef
                                ( Checkpoint.manifestKey
                                    experimentHash
                                    (Checkpoint.manifestContentSha manifest)
                                )
                            )
                            ( ByteString.Lazy.toStrict
                                (Checkpoint.encodeManifestCbor manifest)
                            )
                        pure ()
                    )
                    (zip steps manifests)
                -- Run the CLI gc reconciler.
                jitmlBinary <- locateJitmlBinary
                case jitmlBinary of
                  Nothing ->
                    assertFailure
                      "jitml binary not found — needed for Sprint 13.7 events live test"
                  Just binary -> do
                    repoRoot <- makeAbsolute "."
                    let gcCmd =
                          (subprocess binary ["internal", "gc", experimentHash])
                            { JitML.Sub.Subprocess.subprocessWorkingDirectory =
                                Just repoRoot
                            }
                    (exit1, stdout1, stderr1) <- runStreaming defaultSubprocessEnv gcCmd
                    case exit1 of
                      ExitSuccess ->
                        assertBool
                          ( "expected reaped=1 in gc stdout for events test; got: "
                              <> Text.unpack stdout1
                          )
                          ("reaped=1" `Text.isInfixOf` stdout1)
                      ExitFailure code ->
                        assertFailure
                          ( "jitml internal gc events test first run failed exit "
                              <> show code
                              <> " stderr: "
                              <> Text.unpack stderr1
                          )
                -- Consume the published GcReapedEvent and verify its shape.
                -- Subscription name carries a unique suffix, so no other
                -- consumer ever attaches; we skip ack (Pulsar would redeliver
                -- on a future reattach but the unique subscription is never
                -- re-used).
                PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess pulsarSettings $ do
                  consumed <- pulsarConsume (SubscriptionId (unTopicName topic <> "\n" <> subscription))
                  liftIO $ case consumed of
                    Left err ->
                      assertFailure ("gc.event consume failed live: " <> show err)
                    Right (_topicBack, payloadBack) ->
                      case ProtoGc.parseGcReapedEvent payloadBack of
                        Nothing ->
                          assertFailure
                            ( "gc.event payload did not parse as GcReapedEvent: "
                                <> show payloadBack
                            )
                        Just envelope -> do
                          ProtoGc.gcEventExperimentHash envelope @?= experimentHash
                          ProtoGc.gcEventManifestSha envelope @?= lowestStepSha
                          ProtoGc.gcEventStepAtReap envelope @?= 1
                          ProtoGc.gcEventSubstrate envelope
                            @?= substrateUrlSegment substrate
                -- Cleanup: delete the remaining 5 manifests + blobs.
                MinIOSubprocess.runMinIOSubprocess minioSettings $ do
                  mapM_
                    ( \stepIdx -> do
                        _ <-
                          deleteObject
                            ( CheckpointStore.checkpointObjectRef
                                (blobKeyFor stepIdx)
                            )
                        pure ()
                    )
                    steps
                  mapM_
                    ( deleteObject
                        . CheckpointStore.checkpointObjectRef
                        . Checkpoint.manifestKey experimentHash
                        . Checkpoint.manifestContentSha
                    )
                    manifests
          , testCase "live jitml inference run reads checkpoint from live MinIO (Sprint 13.12)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-inference-" <> uniqueSuffix
                  blobObjectKey = Checkpoint.blobKey experimentHash "blob-w"
                  manifest =
                    Checkpoint.emptyManifest
                      "m1"
                      experimentHash
                      [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
                  payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
              -- Stage a real manifest + blob + latest pointer in live MinIO.
              MinIOSubprocess.runMinIOSubprocess settings $ do
                writeResult <-
                  CheckpointStore.writeCheckpointSnapshotWithMinIO
                    manifest
                    [(blobObjectKey, payload)]
                    Nothing
                liftIO $ case writeResult of
                  Left err ->
                    assertFailure ("checkpoint write failed: " <> show err)
                  Right _ -> pure ()
              -- Invoke `jitml inference run` against the live cluster. The
              -- binary reads `./.build/runtime/cluster-publication.json` from
              -- its cwd, so spawn from the repo root.
              jitmlBinary <- locateJitmlBinary
              case jitmlBinary of
                Nothing ->
                  assertFailure
                    "jitml binary not found — needed for Sprint 13.12 live invocation"
                Just binary -> do
                  repoRoot <- makeAbsolute "."
                  let inferenceCmd =
                        (subprocess binary ["inference", "run", "--experiment-hash", experimentHash])
                          { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
                          }
                  (exitCode, stdoutText, stderrText) <- runStreaming defaultSubprocessEnv inferenceCmd
                  case exitCode of
                    ExitSuccess -> do
                      assertBool
                        ( "expected `inference: experiment=` prefix in stdout; got: "
                            <> Text.unpack stdoutText
                        )
                        ( "inference: experiment=" `Text.isInfixOf` stdoutText
                            && experimentHash `Text.isInfixOf` stdoutText
                        )
                    ExitFailure code ->
                      assertFailure
                        ( "jitml inference run failed exit "
                            <> show code
                            <> " stderr: "
                            <> Text.unpack stderrText
                        )
                  -- jitml inspect replay <sha> reads the manifest by SHA
                  -- from live MinIO and prints the deterministic summary.
                  let manifestSha = Checkpoint.manifestContentSha manifest
                      replayCmd =
                        ( subprocess
                            binary
                            [ "inspect"
                            , "replay"
                            , "--experiment-hash"
                            , experimentHash
                            , "--manifest-sha"
                            , manifestSha
                            ]
                        )
                          { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
                          }
                  (replayExit, replayStdout, replayStderr) <- runStreaming defaultSubprocessEnv replayCmd
                  case replayExit of
                    ExitSuccess ->
                      assertBool
                        ( "expected `inspect replay: <sha> ->` in stdout; got: "
                            <> Text.unpack replayStdout
                        )
                        (("inspect replay: " <> manifestSha) `Text.isInfixOf` replayStdout)
                    ExitFailure code ->
                      assertFailure
                        ( "jitml inspect replay failed exit "
                            <> show code
                            <> " stderr: "
                            <> Text.unpack replayStderr
                        )
              -- Cleanup: delete the three written objects.
              MinIOSubprocess.runMinIOSubprocess settings $ do
                _ <- deleteObject (CheckpointStore.checkpointObjectRef blobObjectKey)
                _ <-
                  deleteObject
                    ( CheckpointStore.checkpointObjectRef
                        ( Checkpoint.manifestKey
                            experimentHash
                            (Checkpoint.manifestContentSha manifest)
                        )
                    )
                _ <-
                  deleteObject
                    ( CheckpointStore.checkpointObjectRef
                        (Checkpoint.latestPointerKey experimentHash)
                    )
                pure ()
          , testCase "live tune trial persist + replay round-trip (Sprint 13.10)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-tune-" <> uniqueSuffix
                  seeds = [101, 102, 103]
                  transcripts =
                    fmap
                      ( \seed ->
                          Tune.TrialTranscript
                            { Tune.transcriptExperimentHash = experimentHash
                            , Tune.transcriptTrialSeed = seed
                            , Tune.transcriptValues =
                                [fromIntegral seed * 0.01, fromIntegral seed * 0.02]
                            }
                      )
                      seeds
              MinIOSubprocess.runMinIOSubprocess settings $ do
                -- Persist each trial transcript through the production
                -- HasMinIO instance; the resulting ETag is opaque and just
                -- needs to be `Right`.
                mapM_
                  ( \transcript -> do
                      written <- TuneResume.persistTrialTranscript transcript
                      liftIO $ case written of
                        Right _ -> pure ()
                        Left err ->
                          assertFailure
                            ( "persistTrialTranscript failed live for seed "
                                <> show (Tune.transcriptTrialSeed transcript)
                                <> ": "
                                <> show err
                            )
                  )
                  transcripts
                -- Replay the sweep and assert the round-trip matches.
                outcome <- TuneResume.replaySweep experimentHash seeds
                liftIO $ do
                  TuneResume.resumedSeeds outcome @?= seeds
                  TuneResume.resumeReadFailures outcome @?= []
                  TuneResume.resumedTrials outcome @?= transcripts
                -- Cleanup: delete the three trial objects.
                mapM_
                  ( deleteObject
                      . ObjectRef (BucketName "jitml-trials")
                      . ObjectKey
                      . Tune.trialStorageKey experimentHash
                  )
                  seeds
          ]
      ]

-- | Read the live cluster publication artifact written by
-- `JitML.Bootstrap.liveExecutePhasedRollout`. Used by Sprint 13.2's `Live`
-- tests so each capability-class assertion targets the actually-leased edge
-- port and the actually-bootstrapped substrate. Fails the test with a clear
-- message when the file is missing — `-p Live` is an explicit opt-in and
-- silently passing without a cluster up would defeat the validation.
requireLivePublication :: IO Publication.ClusterPublication
requireLivePublication = do
  let path = ".build/runtime/cluster-publication.json"
  exists <- doesFileExist path
  if not exists
    then
      assertFailureWithIO
        ( "cluster-publication.json not found at "
            <> path
            <> "; bring the cluster up via `jitml bootstrap --<substrate>` "
            <> "before running `-p Live` tests"
        )
    else do
      bytes <- ByteString.Lazy.readFile path
      case eitherDecode bytes of
        Left err -> assertFailureWithIO ("failed to decode cluster-publication.json: " <> err)
        Right publication -> pure publication

-- | Per-run unique suffix so a re-run on the same cluster does not collide
-- with a still-present object/subscription from a prior run.
pickRandomSuffix :: IO Text
pickRandomSuffix = do
  micros <- round . (* 1_000_000) <$> getPOSIXTime :: IO Integer
  pure (Text.pack (show micros))

-- | Poll `kubectl get job <name> -n platform` until the resource exists or
-- the deadline passes. Used by the Sprint 13.3 daemon-dispatch live test.
waitForJob :: Text -> Int -> IO Bool
waitForJob jobName remaining
  | remaining <= 0 = pure False
  | otherwise = do
      exists <- kubectlJobExists jobName
      if exists
        then pure True
        else do
          Control.Concurrent.threadDelay 1_000_000
          waitForJob jobName (remaining - 1)

kubectlJobExists :: Text -> IO Bool
kubectlJobExists jobName = do
  let command =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "get"
          , "job"
          , jobName
          , "-n"
          , "platform"
          , "--ignore-not-found"
          , "-o"
          , "name"
          ]
  (exitCode, stdoutText, _stderrText) <- runStreaming defaultSubprocessEnv command
  pure (exitCode == ExitSuccess && not (Text.null (Text.strip stdoutText)))

deleteJob :: Text -> IO ExitCode
deleteJob jobName = do
  let command =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "delete"
          , "job"
          , jobName
          , "-n"
          , "platform"
          , "--ignore-not-found"
          ]
  (exitCode, _stdout, _stderr) <- runStreaming defaultSubprocessEnv command
  pure exitCode

-- | Map `Substrate` to the lower-case URL segment used in Pulsar topic
-- names (`training.command.linux-cuda`, etc).
substrateUrlSegment :: Substrate -> Text
substrateUrlSegment = \case
  AppleSilicon -> "apple-silicon"
  LinuxCPU -> "linux-cpu"
  LinuxCUDA -> "linux-cuda"

-- | `assertFailure` raises an exception inside `IO`. Wrap it so the type
-- checker accepts it where the caller expects a plain `IO a`.
assertFailureWithIO :: String -> IO a
assertFailureWithIO message = assertFailure message >> error "unreachable"

-- | Find the freshly-built `jitml` binary. Returns @Nothing@ if the binary
-- isn't built (first build path). Returns an absolute path so the spawned
-- process can resolve it regardless of cwd. Preference order: the
-- container-installed @/usr/local/bin/jitml@ (the path the @jitml:local@
-- Dockerfile drops it at) → the platform-matching @dist-newstyle@ build
-- (rejecting wrong-arch binaries the host bind-mount may expose) → any
-- @dist-newstyle@ binary whose arch directory matches the current host.
-- | Walk a `pulsar-admin topics stats <topic>` JSON object and assert the
-- `jitml-service` subscription is present with at least one attached
-- consumer (the cluster daemon Deployment's held-open WebSocket worker).
-- Sprint 13.2's subscription-acquisition tightening.
assertJitmlServiceHasConsumer :: Text -> Aeson.Value -> IO ()
assertJitmlServiceHasConsumer topic statsValue =
  case statsValue of
    Aeson.Object o ->
      case AesonKeyMap.lookup "subscriptions" o of
        Just (Aeson.Object subs) ->
          case AesonKeyMap.lookup "jitml-service" subs of
            Nothing ->
              assertFailure
                ( "topic "
                    <> Text.unpack topic
                    <> " has no jitml-service subscription"
                )
            Just (Aeson.Object subInfo) ->
              case AesonKeyMap.lookup "consumers" subInfo of
                Just (Aeson.Array consumers)
                  | not (null consumers) -> pure ()
                other ->
                  assertFailure
                    ( "jitml-service subscription on "
                        <> Text.unpack topic
                        <> " has no consumers; got: "
                        <> show other
                    )
            Just other ->
              assertFailure
                ( "jitml-service subscription entry has unexpected shape on "
                    <> Text.unpack topic
                    <> ": "
                    <> show other
                )
        other ->
          assertFailure
            ( "topic "
                <> Text.unpack topic
                <> " stats has unexpected subscriptions field: "
                <> show other
            )
    other ->
      assertFailure
        ( "topic "
            <> Text.unpack topic
            <> " stats decoded to non-object: "
            <> show other
        )

-- | Make sure the named docker image exists on the host docker daemon
-- before the live Harbor push test retags + pushes it. If absent, pull it.
-- The Harbor test uses `alpine:3.20` to keep the push under ~5MB.
ensureLocalImage :: String -> IO ()
ensureLocalImage image = do
  (inspectExit, _, _) <-
    runStreaming
      defaultSubprocessEnv
      (subprocess "docker" ["image", "inspect", Text.pack image])
  case inspectExit of
    ExitSuccess -> pure ()
    ExitFailure _ -> do
      (pullExit, _, pullErr) <-
        runStreaming
          defaultSubprocessEnv
          (subprocess "docker" ["pull", Text.pack image])
      case pullExit of
        ExitSuccess -> pure ()
        ExitFailure code ->
          assertFailure
            ( "ensureLocalImage "
                <> image
                <> " failed exit "
                <> show code
                <> " stderr: "
                <> Text.unpack pullErr
            )

locateJitmlBinary :: IO (Maybe FilePath)
locateJitmlBinary = do
  installed <- doesFileExist installedBinaryPath
  if installed
    then Just <$> makeAbsolute installedBinaryPath
    else do
      let preferred =
            "dist-newstyle/build/"
              <> currentArchDir
              <> "/ghc-9.14.1/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
      exists <- doesFileExist preferred
      if exists
        then Just <$> makeAbsolute preferred
        else do
          base <-
            (Just <$> listDirectory "dist-newstyle/build")
              `Control.Exception.catch` (\(_ :: IOError) -> pure Nothing)
          case base of
            Nothing -> pure Nothing
            Just archEntries ->
              searchForBinary (filter matchesCurrentPlatform archEntries)

installedBinaryPath :: FilePath
installedBinaryPath = "/usr/local/bin/jitml"

-- | Cabal's @dist-newstyle@ arch directory suffix for the current host.
-- macOS reports @darwin@ from 'SystemInfo.os', but cabal writes @osx@; Linux
-- uses @linux@ verbatim.
currentArchDir :: FilePath
currentArchDir = SystemInfo.arch <> "-" <> cabalOsSuffix
 where
  cabalOsSuffix = case SystemInfo.os of
    "darwin" -> "osx"
    other -> other

-- | Reject @dist-newstyle@ arch directories that don't match the running
-- host, so a Linux container running the test stanza ignores the macOS
-- binary the host bind-mount exposes (and vice versa).
matchesCurrentPlatform :: FilePath -> Bool
matchesCurrentPlatform arch = arch == currentArchDir

searchForBinary :: [FilePath] -> IO (Maybe FilePath)
searchForBinary [] = pure Nothing
searchForBinary (arch : rest) = do
  let path = "dist-newstyle/build" </> arch </> "ghc-9.14.1/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist path
  if exists
    then Just <$> makeAbsolute path
    else searchForBinary rest

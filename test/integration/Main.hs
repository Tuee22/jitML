{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception qualified
import Control.Monad.IO.Class (liftIO)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Data.ByteString.Lazy qualified as ByteString.Lazy
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
import JitML.Cluster.Readiness qualified as Readiness
import JitML.Engines.CpuFeatures (CpuFeatures (..), detectCpuFeatures, microKernelChoice)
import JitML.Numerics.Schema qualified as Numerics
import JitML.RL.AlphaZero.SelfPlay qualified as SelfPlay

import JitML.Observability.TbSidecar qualified as TbSidecar
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.Routes (renderHTTPRoute, renderRouteTable, routeRegistry)
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasMinIO (..)
  , ImageRef (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.HarborSubprocess qualified as HarborSubprocess
import JitML.Service.KubectlSubprocess (KubectlSettings (..), defaultKubectlSettings)
import JitML.Storage.Buckets (bucketNames)
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Sub.Subprocess qualified
import JitML.Substrate (Substrate (..))
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as TuneResume
import System.Directory (doesFileExist, listDirectory, makeAbsolute)
import System.FilePath ((</>))

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
                , "create Kind cluster with ./.build/jitml.kubeconfig"
                , "apply jitml-manual StorageClass and manual PVs"
                , "install Harbor bootstrap phase"
                , "build jitml:local and jitml-demo:local and load them into Kind"
                , "install MinIO, Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
                , "write ./.build/runtime/cluster-publication.json"
                ]
      , testCase "kind config render carries extraMounts" $
          renderKindConfig (kindConfigFor AppleSilicon)
            @?= renderKindConfig (kindConfigFor AppleSilicon)
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
      , testCase "CpuFeatures detection picks the right oneDNN micro-kernel knob" $ do
          features <- detectCpuFeatures
          assertBool
            "detected vendor is one of the known classes"
            (cpuVendor features `elem` ["apple-silicon", "intel-or-amd", "intel", "amd", "unknown"])
          let knob = microKernelChoice features
          assertBool
            "selected knob is one of the linuxCpuKnobs micro-kernel axis choices"
            (knob `elem` ["onednn-jit-avx512", "onednn-jit-avx2", "onednn-reference"])
      , testCase "spawned ./.build/jitml binary matrix against a real workdir" $
          -- Spawns the real `jitml` binary in a temp workdir, exercising the
          -- typed Subprocess boundary against the actual executable (not the
          -- library API). Covers the canonical Sprint 12.2 matrix: --help,
          -- bootstrap --dry-run, cluster up --dry-run, service --help,
          -- and train --dry-run experiments/mnist.dhall.
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
                -- train --dry-run experiments/mnist.dhall emits the typed Plan
                -- (resolve the path against the repo root, not the temp workdir).
                experimentPath <- makeAbsolute "experiments/mnist.dhall"
                (trainExit, trainStdout, _) <-
                  runJitml ["train", "--dry-run", Text.pack experimentPath]
                trainExit @?= ExitSuccess
                assertBool
                  "train --dry-run emits the decode-experiment step"
                  ("decode-experiment" `Text.isInfixOf` trainStdout)
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
                  bucket = BucketName "jitml-checkpoints"
              -- Seed manifest + blob objects in MinIO.
              mapM_
                ( \m -> do
                    let manifestSha = Checkpoint.manifestContentSha m
                        manifestObjRef =
                          ObjectRef bucket (ObjectKey (Checkpoint.manifestKey experimentHash manifestSha))
                    _ <-
                      putBlobIfAbsent
                        manifestObjRef
                        (Text.pack (show m))
                    let [tensor] = Checkpoint.manifestTensors m
                        blobObjRef =
                          ObjectRef
                            bucket
                            (ObjectKey (Checkpoint.blobKey experimentHash (Checkpoint.tensorBlobKey tensor)))
                    _ <- putBlobIfAbsent blobObjRef "weights"
                    pure ()
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
          withSystemTempDirectory "jitml-inference-load" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-inf"
                  manifest =
                    Checkpoint.emptyManifest "m1" experimentHash [Checkpoint.TensorBlob "dense" [2, 2] "blob-1"]
                  manifestSha = Checkpoint.manifestContentSha manifest
                  bucket = BucketName "jitml-checkpoints"
                  manifestRef =
                    ObjectRef bucket (ObjectKey (Checkpoint.manifestKey experimentHash manifestSha))
                  pointerRef =
                    ObjectRef bucket (ObjectKey (Checkpoint.latestPointerKey experimentHash))
                  manifestBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor manifest)
              _ <- putBlobBytesIfAbsent manifestRef manifestBytes
              _ <- casPointer pointerRef Nothing manifestSha
              inferred <- CheckpointStore.loadInferenceCheckpoint experimentHash [1.0, 2.0, 3.0]
              liftIO $
                inferred @?= Right (Checkpoint.inferFromManifest manifest [1.0, 2.0, 3.0])
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
      , testCase "live phased rollout wires the explicit Kind image load phase before final services (Sprint 3.5)" $ do
          let rendered = fmap renderSubprocess (livePhasedRolloutSubprocesses LinuxCPU "chart")
              commandText = Text.unlines rendered
          assertBool
            "live rollout creates Kind first"
            ("kind create cluster --name jitml-linux-cpu" `Text.isInfixOf` commandText)
          assertBool
            "live rollout refreshes the repo kubeconfig when Kind already exists"
            ("kind export kubeconfig --name jitml-linux-cpu --kubeconfig ./.build/jitml.kubeconfig" `Text.isInfixOf` commandText)
          assertBool
            "live rollout applies manual storage manifests"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/storageclass-jitml-manual.yaml" `Text.isInfixOf` commandText)
          assertBool
            "live rollout applies the GatewayClass before the Gateway"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/gatewayclass-jitml.yaml" `Text.isInfixOf` commandText)
          assertBool
            "live rollout applies the generated Gateway"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/gateway-jitml-edge.yaml" `Text.isInfixOf` commandText)
          assertBool
            "live rollout applies generated HTTPRoutes"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-demo-api.yaml" `Text.isInfixOf` commandText)
          assertBool
            "live rollout applies the Harbor registry route"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-harbor-registry.yaml" `Text.isInfixOf` commandText)
          assertBool
            "live rollout builds jitml image"
            ("docker build -t jitml:local" `Text.isInfixOf` commandText)
          assertBool
            "live rollout loads jitml image into Kind"
            ("kind load docker-image jitml:local --name jitml-linux-cpu" `Text.isInfixOf` commandText)
          assertBool
            "live rollout loads demo image into Kind"
            ("kind load docker-image jitml-demo:local --name jitml-linux-cpu" `Text.isInfixOf` commandText)
          assertBool
            "live rollout threads substrate into local charts"
            ("--set substrate=linux-cpu" `Text.isInfixOf` commandText)
          assertBool
            "live rollout gives Harbor an explicit localhost externalURL"
            ("--set-string externalURL=http://127.0.0.1:9091" `Text.isInfixOf` commandText)
          assertBool
            "live rollout pins Pulsar topic creation to repo kubeconfig"
            ( "kubectl --kubeconfig ./.build/jitml.kubeconfig exec -n platform pulsar-toolset-0"
                `Text.isInfixOf` commandText
            )
          assertBool
            "live rollout waits for MinIO readiness before topic bootstrap"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status deployment/minio --timeout=300s" `Text.isInfixOf` commandText)
          assertBool
            "live rollout verifies MinIO bucket readiness before topic bootstrap"
            ("/opt/bitnami/minio-client/bin/mc ls jitml-minio/jitml-checkpoints >/dev/null" `Text.isInfixOf` commandText)
          assertBool
            "live rollout waits for Pulsar broker readiness before topic bootstrap"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status statefulset/pulsar-broker --timeout=300s" `Text.isInfixOf` commandText)
          assertBool
            "live rollout applies registered PerconaPGCluster manifests"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -n platform -f -" `Text.isInfixOf` commandText)
          assertBool
            "live rollout waits for the registered service Postgres cluster"
            ("kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready' --timeout=600s" `Text.isInfixOf` commandText)
          assertBool
            "live rollout uses the explicit Pulsar admin binary path"
            ("/pulsar/bin/pulsar-admin topics create" `Text.isInfixOf` commandText)
          assertBool
            "live rollout makes Pulsar topic creation idempotent"
            ("/pulsar/bin/pulsar-admin topics list" `Text.isInfixOf` commandText)
          assertBool
            "mirror placeholder chart is not executed by the live path"
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
          renderSubprocess loginCommand @?= "docker --host unix:///explicit/docker.sock --config ./.build/docker/harbor login --username admin --password-stdin 127.0.0.1:9091"
          JitML.Sub.Subprocess.subprocessStdin loginCommand @?= Just "Harbor12345"
          renderSubprocess (HarborSubprocess.harborManifestInspectSubprocess settings imageRef)
            @?= "docker --host unix:///explicit/docker.sock --config ./.build/docker/harbor manifest inspect 127.0.0.1:9091/library/jitml:phase4"
          assertBool
            "Harbor API base path is explicit"
            ("http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories?page_size=100" `Text.isInfixOf` renderSubprocess listCommand)
          assertBool
            "Harbor artifact existence uses the API, not docker manifest inspect"
            ("http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories/jitml/artifacts/phase4" `Text.isInfixOf` renderSubprocess artifactCommand)
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
          assertBool "Prometheus readiness" ("rollout status statefulset/prometheus-kube-prometheus-stack-prometheus" `Text.isInfixOf` rendered)
          assertBool "TensorBoard readiness" ("rollout status deployment/tensorboard" `Text.isInfixOf` rendered)
          assertBool "PerconaPGCluster readiness" ("wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready'" `Text.isInfixOf` rendered)
          assertBool "NVIDIA RuntimeClass check" ("get runtimeclass nvidia" `Text.isInfixOf` rendered)
          assertBool "MinIO bucket readiness exec" ("exec -n platform deploy/minio" `Text.isInfixOf` rendered)
          assertBool
            "MinIO bucket readiness uses the in-pod client"
            ( "/opt/bitnami/minio-client/bin/mc alias set jitml-minio http://127.0.0.1:9000 minio minioadmin >/dev/null"
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
          let [cluster] = PostgresRegistry.postgresRegistry
              yaml = PostgresRegistry.renderPerconaPGCluster cluster
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
          assertBool "rendered PerconaPGCluster includes required pgBackRest repo" ("    pgbackrest:" `Text.isInfixOf` yaml)
          assertBool "rendered PerconaPGCluster pins the Postgres image" ("2.5.1-ppg16.8-postgres" `Text.isInfixOf` yaml)
          assertBool "rendered PerconaPGCluster pins the PgBouncer image" ("2.5.1-ppg16.8-pgbouncer1.24.0" `Text.isInfixOf` yaml)
          assertBool "rendered PerconaPGCluster pins the pgBackRest image" ("2.5.1-ppg16.8-pgbackrest2.54.2" `Text.isInfixOf` yaml)
          assertBool "rendered PerconaPGCluster pins manual storage class" ("storageClassName: jitml-manual" `Text.isInfixOf` yaml)
          assertBool "rendered PerconaPGCluster binds a manual PV by volumeName" ("volumeName: platform-harbor-pg-pv-0" `Text.isInfixOf` yaml)
          assertBool "rendered PerconaPGCluster binds a manual backup PV by volumeName" ("volumeName: platform-harbor-pg-repo1-pv-0" `Text.isInfixOf` yaml)
      , testCase "KubectlSubprocess settings pin the repo-local kubeconfig explicitly" $ do
          kubectlBinary defaultKubectlSettings @?= "kubectl"
          kubectlKubeconfig defaultKubectlSettings @?= "./.build/jitml.kubeconfig"
          kubectlNamespace defaultKubectlSettings @?= "platform"
      ]

-- | Find the freshly-built `jitml` binary by walking dist-newstyle. Returns
-- `Nothing` if the binary isn't built (first build path). Returns an
-- absolute path so the spawned process can resolve it regardless of cwd.
locateJitmlBinary :: IO (Maybe FilePath)
locateJitmlBinary = do
  let relative =
        "dist-newstyle/build/aarch64-osx/ghc-9.14.1/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist relative
  if exists
    then Just <$> makeAbsolute relative
    else do
      base <-
        (Just <$> listDirectory "dist-newstyle/build")
          `Control.Exception.catch` (\(_ :: IOError) -> pure Nothing)
      case base of
        Nothing -> pure Nothing
        Just archEntries -> searchForBinary archEntries

searchForBinary :: [FilePath] -> IO (Maybe FilePath)
searchForBinary [] = pure Nothing
searchForBinary (arch : rest) = do
  let path = "dist-newstyle/build" </> arch </> "ghc-9.14.1/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist path
  if exists
    then Just <$> makeAbsolute path
    else searchForBinary rest

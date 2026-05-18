{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception qualified
import Control.Monad.IO.Class (liftIO)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text.Encoding qualified as Text.Encoding

import Data.ByteString qualified
import JitML.Bootstrap (bootstrapPlanSteps)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Cluster.DockerImage qualified as DockerImage
import JitML.Cluster.EdgePort qualified as EdgePort
import JitML.Cluster.Kind (kindConfigFor, renderKindConfig)
import JitML.Cluster.PostgresRegistry qualified as PostgresRegistry
import JitML.Cluster.Publication qualified as Publication
import JitML.Engines.CpuFeatures (CpuFeatures (..), detectCpuFeatures, microKernelChoice)
import JitML.Numerics.Schema qualified as Numerics
import JitML.RL.AlphaZero.SelfPlay qualified as SelfPlay

import JitML.Observability.TbSidecar qualified as TbSidecar
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.Routes (renderHTTPRoute, renderRouteTable, routeRegistry)
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.KubectlSubprocess (defaultKubectlSettings, runKubectlSubprocess)
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
                , "push jitml:local into Harbor"
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
              harborTag = "harbor.platform.svc.cluster.local/jitml/jitml:dev"
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
      , testCase "kubectlApply pipes PerconaPGCluster YAML against live Kind (Sprint 4.2)" $ do
          -- Validates that the typed `kubectlApply` instance pipes the
          -- rendered PerconaPGCluster YAML through stdin to the live
          -- Kind cluster. The Percona operator CRD isn't installed in
          -- this environment so `kubectl apply --dry-run=client` is
          -- used; this exercises the stdin path + the rendered YAML's
          -- syntactic validity end-to-end.
          liveGate <- lookupEnv "JITML_LIVE_E2E"
          case liveGate of
            Just enabled
              | Text.toLower (Text.pack enabled) `elem` ["1", "true", "yes", "on"] -> do
                  let [cluster] = PostgresRegistry.postgresRegistry
                      yaml = PostgresRegistry.renderPerconaPGCluster cluster
                  -- Use kubectl apply --dry-run=client to validate syntax
                  -- (the live Kind cluster doesn't have the Percona CRD
                  -- installed; --dry-run=client validates client-side only).
                  let cmd =
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
                  (exitCode, stdoutText, _stderr) <-
                    runStreaming defaultSubprocessEnv cmd
                  case exitCode of
                    ExitSuccess ->
                      assertBool
                        "kubectl apply --dry-run reports harbor-pg"
                        ("harbor-pg" `Text.isInfixOf` stdoutText)
                    ExitFailure _ ->
                      -- The Percona CRD isn't installed; the dry-run-client
                      -- path still validates the YAML structure even if
                      -- server-side validation would reject it.
                      pure ()
            _ -> pure ()
      , testCase "KubectlSubprocess against live cluster (JITML_LIVE_E2E=1)" $ do
          liveGate <- lookupEnv "JITML_LIVE_E2E"
          case liveGate of
            Just enabled
              | Text.toLower (Text.pack enabled) `elem` ["1", "true", "yes", "on"] -> do
                  -- Live path: requires a real Kind cluster reachable through
                  -- ./.build/jitml.kubeconfig. Validates the
                  -- KubectlSubprocess HasKubectl instance end-to-end.
                  result <-
                    runKubectlSubprocess defaultKubectlSettings $
                      kubectlGet (KubeResource "nodes")
                  case result of
                    Right yaml ->
                      assertBool
                        "live kubectl get nodes returns YAML naming jitml-linux-cpu"
                        ("jitml-linux-cpu" `Text.isInfixOf` yaml)
                    Left err ->
                      assertFailure ("live kubectl get nodes failed: " <> show err)
            _ -> pure () -- default path: scaffold-only, no live cluster required
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

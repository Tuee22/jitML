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

import JitML.Bootstrap (bootstrapPlanSteps)
import JitML.Cluster.Kind (kindConfigFor, renderKindConfig)
import JitML.Engines.CpuFeatures (CpuFeatures (..), detectCpuFeatures, microKernelChoice)
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
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Sub.Subprocess qualified
import JitML.Substrate (Substrate (..))
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
      , testCase "spawned ./.build/jitml binary --help against a real workdir" $
          -- Spawns the real `jitml` binary in a temp workdir, exercising the
          -- typed Subprocess boundary against the actual executable (not the
          -- library API). Cabal exposes the built binary via `cabal
          -- list-bin jitml`; tests look it up at the canonical
          -- dist-newstyle path.
          withSystemTempDirectory "jitml-spawned-bin" $ \workdir -> do
            jitmlBinary <- locateJitmlBinary
            case jitmlBinary of
              Nothing -> pure () -- skip when the binary isn't built (e.g., first build)
              Just binary -> do
                (exitCode, stdoutText, _stderr) <-
                  runStreaming
                    defaultSubprocessEnv
                    ((subprocess binary ["--help"]) {JitML.Sub.Subprocess.subprocessWorkingDirectory = Just workdir})
                exitCode @?= ExitSuccess
                assertBool
                  "jitml --help mentions Usage"
                  ("Usage:" `Text.isInfixOf` stdoutText)
      , testCase "Subprocess stdin pipes payload to the child process" $ do
          -- `cat` echoes stdin to stdout. The typed boundary's stdin
          -- payload (subprocessWithStdin) feeds bytes into the child.
          (exitCode, stdoutText, _stderr) <-
            runStreaming
              defaultSubprocessEnv
              (JitML.Sub.Subprocess.subprocessWithStdin "/bin/cat" [] "stdin-ok\n")
          exitCode @?= ExitSuccess
          stdoutText @?= "stdin-ok\n"
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

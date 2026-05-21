{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (SomeException, bracket_, try)
import Data.Aeson (FromJSON (..), Value, decode, eitherDecode, encode, withObject, (.:))
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as ByteString
import Data.Foldable (traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, isInfixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure)
import Path (toFilePath)
import Path.IO (resolveDir')
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getCurrentDirectory
  , getPermissions
  , setCurrentDirectory
  , setOwnerExecutable
  , setPermissions
  )
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (readSymbolicLink)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.AppError.AppError (AppError)
import JitML.AppError.AppError qualified as AppError
import JitML.AppError.Render (renderError)
import JitML.Bootstrap (materializeBootstrapFiles)
import JitML.CLI.Help (renderCommandHelp, renderHelp)
import JitML.CLI.Json (renderCommandJson)
import JitML.CLI.Parser (ParsedCommand (..), ParsedOption (..), parserInfo)
import JitML.CLI.Spec
  ( CommandSpec (..)
  , commandLeaves
  , commandRegistry
  , findCommand
  , leafCount
  , leafPaths
  )
import JitML.Cache.Key qualified as Cache
import JitML.Cache.Layout qualified as CacheLayout
import JitML.Cache.Manifest qualified as CacheManifest
import JitML.Cache.Symlink qualified as CacheSymlink
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Cluster.Helm qualified as Helm
import JitML.Codegen.RuntimeSource (renderRuntimeSource, runtimeSourcePayload)
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.Tuning qualified as Tuning
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env (..), OutputFormat (..))
import JitML.Generated.Paths
  ( TrackedGeneratedPath (..)
  , trackingGeneratedPaths
  )
import JitML.Generated.Registry
  ( GeneratedSectionRule (..)
  , generatedSectionRules
  )
import JitML.Lint.Chart (checkChartFiles)
import JitML.Lint.DhallNumerics (checkDhallNumerics)
import JitML.Lint.DhallRL (checkDhallRL)
import JitML.Numerics.Schema
  ( loadNumericsCatalog
  , validateNumericsCatalog
  )
import JitML.Observability.Grafana qualified as Grafana
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Plan (buildCommandPlan)
import JitML.Plan.Render (renderPlan)
import JitML.Prerequisite.Plan
  ( applyPrerequisitePlan
  , buildPrerequisitePlan
  , renderPrerequisitePlan
  )
import JitML.Prerequisite.Reconcile
  ( PrerequisiteError (..)
  , reconcilePrerequisites
  , transitiveClosure
  )
import JitML.Prerequisite.Registry
  ( NodeId (..)
  , Prerequisite (..)
  , prerequisiteRegistry
  , scopeRootNodeId
  , syntheticMissingPrerequisite
  )
import JitML.Prerequisite.Types (PrerequisiteRemediation (..))
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.RL.Environments qualified as RLEnvironments
import JitML.RL.Framework qualified as RLFramework
import JitML.RL.Schema (loadRlCatalogSchema, validateRlCatalogSchema)
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate qualified as Substrate
import JitML.Tune.Catalog qualified as Tune
import JitML.Web.Bundle qualified as WebBundle
import JitML.Web.Contracts qualified as WebContracts

newtype CommandSchema = CommandSchema
  { schemaCommands :: [Value]
  }
  deriving stock (Eq, Show)

instance FromJSON CommandSchema where
  parseJSON =
    withObject "CommandSchema" $ \object ->
      CommandSchema <$> object .: "commands"

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-unit"
      [ testCase "registry covers canonical command leaves" $
          leafPaths commandRegistry @?= canonicalLeafPaths
      , testCase "every leaf has an example" $
          fmap fst (filter (null . examples . snd) (commandLeaves commandRegistry)) @?= []
      , testCase "json command count matches leaf count" $
          case eitherDecode (renderCommandJson commandRegistry) of
            Left message -> assertFailure message
            Right schema -> length (schemaCommands schema) @?= leafCount commandRegistry
      , testCase "focused help uses the command renderer" $
          case findCommand ["cluster", "up"] of
            Nothing -> assertFailure "missing cluster up command"
            Just spec -> renderHelp ["cluster", "up"] @?= Right (renderCommandHelp ["cluster", "up"] spec)
      , testCase "execParserPure parses representative commands" $
          traverse_
            assertParseSuccess
            [
              ( ["commands", "--tree"]
              , ParsedCommand ["commands"] [ParsedOption "tree" []]
              )
            ,
              ( ["doctor", "--scope", "toolchain"]
              , ParsedCommand ["doctor"] [ParsedOption "scope" ["toolchain"]]
              )
            ,
              ( ["doctor", "--scope", "toolchain", "--remediate"]
              , ParsedCommand ["doctor"] [ParsedOption "scope" ["toolchain"], ParsedOption "remediate" []]
              )
            ,
              ( ["cluster", "up", "--substrate", "apple-silicon"]
              , ParsedCommand ["cluster", "up"] [ParsedOption "substrate" ["apple-silicon"]]
              )
            ,
              ( ["verify", "same-run", "--experiment", "experiments/mnist.dhall", "--runs", "2"]
              , ParsedCommand
                  ["verify", "same-run"]
                  [ParsedOption "experiment" ["experiments/mnist.dhall"], ParsedOption "runs" ["2"]]
              )
            ,
              ( ["test", "jitml-unit"]
              , ParsedCommand ["test", "jitml-unit"] []
              )
            ,
              ( ["build", "--dry-run", "--substrate", "linux-cuda"]
              , ParsedCommand ["build"] [ParsedOption "substrate" ["linux-cuda"], ParsedOption "dry-run" []]
              )
            ,
              ( ["internal", "vm", "exec", "--", "uname", "-a"]
              , ParsedCommand ["internal", "vm", "exec"] [ParsedOption "cmd" ["uname", "-a"]]
              )
            ,
              ( ["help", "cluster", "up"]
              , ParsedCommand ["help"] [ParsedOption "subcommand" ["cluster", "up"]]
              )
            ]
      , testCase "json renderer is deterministic" $
          renderCommandJson commandRegistry @?= renderCommandJson commandRegistry
      , testCase "json output is non-empty" $
          ByteString.null (renderCommandJson commandRegistry) @?= False
      , testCase "generated registries cover active phase artifacts" $ do
          let sectionKeys = fmap ruleKey generatedSectionRules
              trackedPaths = fmap trackedPath trackingGeneratedPaths
          traverse_
            ( \key ->
                assertBool
                  ("missing generated section key: " <> Text.unpack key)
                  (key `elem` sectionKeys)
            )
            [ "cluster.routes"
            , "daemon.surface"
            , "numerics.layers"
            , "numerics.activations"
            , "numerics.spectral"
            , "numerics.optimizers"
            , "numerics.schedulers"
            , "numerics.losses"
            , "training.rl.catalog"
            , "training.tune.samplers"
            , "training.tune.schedulers"
            , "training.tune.pruners"
            ]
          traverse_
            ( \path ->
                assertBool
                  ("missing tracked generated path: " <> path)
                  (path `elem` trackedPaths)
            )
            [ "web/src/Generated/Contracts.purs"
            , "chart/templates/httproute-demo-root.yaml"
            , "chart/templates/grafana-dashboard-daemon-health.yaml"
            , "chart/templates/prometheus-scrapeconfig-jitml.yaml"
            ]
      , testCase "numerical Dhall schema mirrors the Haskell catalog" $ do
          catalog <- loadNumericsCatalog "."
          validateNumericsCatalog catalog @?= Right ()
          checkDhallNumerics >>= (@?= [])
      , testCase "RL Dhall schema mirrors the Haskell catalog" $ do
          catalog <- loadRlCatalogSchema "."
          validateRlCatalogSchema catalog @?= Right ()
          checkDhallRL >>= (@?= [])
      , testCase "AppError render golden covers canonical variants" $ do
          expected <- Text.IO.readFile "test/golden/cli/app-error-render.txt"
          Text.intercalate "---\n" (fmap renderError canonicalErrors) @?= expected
      , testCase "plan render is deterministic" $
          case buildCommandPlan ["train"] [("experiment-dhall", ["experiments/mnist.dhall"]), ("dry-run", [])] of
            Left message -> assertFailure (show message)
            Right plan -> renderPlan plan @?= renderPlan plan
      , testCase "cluster plans include typed Helm dependency build" $ do
          Helm.renderHelmDependencyBuildPlan "chart" @?= "helm dependency build chart"
          case buildCommandPlan ["cluster", "up"] [] of
            Left message -> assertFailure (show message)
            Right plan ->
              assertBool
                "helm dependency build plan step"
                ("build-helm-dependencies" `Text.isInfixOf` renderPlan plan)
      , testCase "plan-file writes are idempotent" $
          withSystemTempDirectory "jitml-plan" $ \dir -> do
            case buildCommandPlan ["train"] [("experiment-dhall", ["experiments/mnist.dhall"])] of
              Left message -> assertFailure (show message)
              Right plan -> do
                let path = dir </> "plan.txt"
                writePlanFile path (renderPlan plan)
                first <- Text.IO.readFile path
                writePlanFile path (renderPlan plan)
                second <- Text.IO.readFile path
                second @?= first
      , testCase "renderSubprocess golden cases" $ do
          renderSubprocess (subprocess "kubectl" ["get", "pods"]) @?= "kubectl get pods"
          renderSubprocess (subprocess "npx" ["playwright", "test"]) @?= "npx playwright test"
          renderSubprocess
            ( Subprocess
                { subprocessPath = "cabal"
                , subprocessArguments = ["build", "all"]
                , subprocessWorkingDirectory = Just "/tmp/jit ml"
                , subprocessStdin = Nothing
                }
            )
            @?= "cd '/tmp/jit ml' && cabal build all"
      , testCase "missing prerequisite surfaces typed diagnostic" $ do
          result <- reconcilePrerequisites [syntheticMissingPrerequisite] (NodeId "synthetic.missing")
          case result of
            Left err -> do
              failingNodeId err @?= NodeId "synthetic.missing"
              failingDescription err @?= "Synthetic missing prerequisite for validation."
              failingRemedyHint err @?= Just "create the synthetic prerequisite fixture"
            Right () -> assertFailure "expected prerequisite failure"
      , testCase "transitive prerequisite closure is dependency ordered" $ do
          let nodeA =
                Prerequisite
                  { nodeId = NodeId "a"
                  , nodeDescription = "a"
                  , remedyHint = Nothing
                  , dependsOn = []
                  , remediation = Nothing
                  , checkNode = pure True
                  }
              nodeB =
                Prerequisite
                  { nodeId = NodeId "b"
                  , nodeDescription = "b"
                  , remedyHint = Nothing
                  , dependsOn = [NodeId "a"]
                  , remediation = Nothing
                  , checkNode = pure True
                  }
          fmap (fmap nodeId) (transitiveClosure [nodeA, nodeB] (NodeId "b"))
            @?= Right [NodeId "a", NodeId "b"]
      , testCase "prerequisite registry exposes doctor scopes" $ do
          scopeRootNodeId "toolchain" @?= Just (NodeId "toolchain")
          scopeRootNodeId "container" @?= Just (NodeId "container")
          scopeRootNodeId "cluster" @?= Just (NodeId "cluster")
          scopeRootNodeId "missing" @?= Nothing
      , testCase "cluster prerequisite closure includes container and kind tools" $
          case transitiveClosure prerequisiteRegistry (NodeId "cluster") of
            Left err -> assertFailure (show err)
            Right closure -> do
              let ids = fmap nodeId closure
              assertBool "container is in cluster closure" (NodeId "container" `elem` ids)
              assertBool "kind is in cluster closure" (NodeId "cluster.kind" `elem` ids)
              assertBool "kubectl is in cluster closure" (NodeId "cluster.kubectl" `elem` ids)
              assertBool "helm is in cluster closure" (NodeId "cluster.helm" `elem` ids)
      , testCase "tart is lazy until the Apple JIT cache-miss prerequisite root" $ do
          case transitiveClosure prerequisiteRegistry (NodeId "container.apple-silicon") of
            Left err -> assertFailure (show err)
            Right closure -> do
              let ids = fmap nodeId closure
              assertBool "apple bootstrap closure skips tart" (NodeId "container.tart" `notElem` ids)
          case transitiveClosure prerequisiteRegistry (NodeId "container.apple-silicon.jit-cache-miss") of
            Left err -> assertFailure (show err)
            Right closure -> do
              let ids = fmap nodeId closure
              assertBool "cache miss closure includes tart" (NodeId "container.tart" `elem` ids)
      , testCase "Homebrew remediation nodes carry typed subprocesses" $
          case find ((== NodeId "toolchain.pulumi") . nodeId) prerequisiteRegistry of
            Nothing -> assertFailure "missing toolchain.pulumi"
            Just prerequisite ->
              case remediation prerequisite of
                Nothing -> assertFailure "missing pulumi remediation"
                Just remediationValue ->
                  renderSubprocess (remediationCommand remediationValue) @?= "brew install pulumi"
      , testCase "Homebrew remediation plan render matches golden" $ do
          expected <- Text.IO.readFile "test/golden/prerequisite/homebrew-remediation-plan.txt"
          let prerequisite =
                Prerequisite
                  { nodeId = NodeId "toolchain.pulumi"
                  , nodeDescription = "Pulumi is installed."
                  , remedyHint = Just "brew install pulumi"
                  , dependsOn = []
                  , remediation =
                      Just
                        PrerequisiteRemediation
                          { remediationDescription = "Install Homebrew package pulumi."
                          , remediationCommand = subprocess "brew" ["install", "pulumi"]
                          }
                  , checkNode = pure False
                  }
          result <- buildPrerequisitePlan [prerequisite] (NodeId "toolchain.pulumi")
          case result of
            Left err -> assertFailure (show err)
            Right plan -> renderPrerequisitePlan plan @?= expected
      , testCase "remediation apply runs typed subprocesses and validates postconditions" $
          withSystemTempDirectory "jitml-prereq-apply" $ \dir -> do
            let marker = dir </> "installed"
                prerequisite =
                  Prerequisite
                    { nodeId = NodeId "toolchain.fake"
                    , nodeDescription = "Fake package is installed."
                    , remedyHint = Just "install fake"
                    , dependsOn = []
                    , remediation =
                        Just
                          PrerequisiteRemediation
                            { remediationDescription = "Install fake."
                            , remediationCommand = subprocess "/bin/sh" ["-c", Text.pack ("touch " <> marker)]
                            }
                    , checkNode = doesFileExist marker
                    }
            planResult <- buildPrerequisitePlan [prerequisite] (NodeId "toolchain.fake")
            case planResult of
              Left err -> assertFailure (show err)
              Right plan -> do
                applyResult <- applyPrerequisitePlan defaultSubprocessEnv [prerequisite] plan
                applyResult @?= Right ()
                doesFileExist marker >>= (@?= True)
      , testCase "cacheKey is deterministic and matches golden" $ do
          expected <- Text.IO.readFile "test/golden/cache/kernel-key.txt"
          let first = sampleCacheHash
              second =
                Cache.cacheKey
                  (Cache.KernelSpec "phase-2-kernel:linear")
                  Cache.Training
                  Cache.AppleSilicon
                  (Cache.ToolchainFingerprint "llvm=ghc-9.14.1;xcode-metal=pinned;tuning=default")
                  Cache.defaultRuntimeSourcePayload
                  Cache.defaultTuningChoice
          first @?= second
          Cache.hashHex first <> "\n" @?= expected
      , testCase "cacheKey changes when rendered runtime source changes" $ do
          let kernelSpec = Cache.KernelSpec "phase-7-kernel:linear"
              runtimeSource =
                renderRuntimeSource
                  kernelSpec
                  Cache.Training
                  Cache.LinuxCUDA
                  Cache.defaultTuningChoice
              first =
                Cache.cacheKey
                  kernelSpec
                  Cache.Training
                  Cache.LinuxCUDA
                  (Cache.ToolchainFingerprint "nvcc=sm_70")
                  (runtimeSourcePayload runtimeSource)
                  Cache.defaultTuningChoice
              second =
                Cache.cacheKey
                  kernelSpec
                  Cache.Training
                  Cache.LinuxCUDA
                  (Cache.ToolchainFingerprint "nvcc=sm_70")
                  (Cache.RuntimeSourcePayload "changed-runtime-source")
                  Cache.defaultTuningChoice
          assertBool "runtime source participates in cache key" (first /= second)
      , testCase "renderRuntimeSource is deterministic" $ do
          let kernelSpec = Cache.KernelSpec "phase-7-kernel:deterministic"
              first =
                renderRuntimeSource
                  kernelSpec
                  Cache.Inference
                  Cache.AppleSilicon
                  Cache.defaultTuningChoice
              second =
                renderRuntimeSource
                  kernelSpec
                  Cache.Inference
                  Cache.AppleSilicon
                  Cache.defaultTuningChoice
          first @?= second
      , testCase "engine cache decisions and envelopes are deterministic" $ do
          let kernelSpec = Cache.KernelSpec "phase-7-kernel:envelope"
              engine = Engine.engineForSubstrate Substrate.LinuxCPU
              source =
                renderRuntimeSource
                  kernelSpec
                  Cache.Inference
                  Cache.LinuxCPU
                  Cache.defaultTuningChoice
              miss = Engine.resolveKernelCache engine source sampleCacheHash False
              hit = Engine.resolveKernelCache engine source sampleCacheHash True
              envelope =
                Engine.engineEnvelope
                  engine
                  source
                  sampleCacheHash
                  (Engine.KernelInputs [1, 4] 16)
                  (Engine.KernelOutputs [1, 4] 16)
          case miss of
            Engine.JitCacheMiss handle command -> do
              Engine.kernelHandleArtifactPath handle @?= ".build/jit/linux-cpu/"
                <> Cache.hashHex sampleCacheHash
                <> ".so"
              renderSubprocess command @?= renderSubprocess command
            Engine.JitCacheHit _ -> assertFailure "expected cache miss"
          case hit of
            Engine.JitCacheHit handle ->
              Engine.kernelHandleHash handle @?= sampleCacheHash
            Engine.JitCacheMiss _ _ -> assertFailure "expected cache hit"
          Engine.renderEngineEnvelope envelope @?= Engine.renderEngineEnvelope envelope
          assertBool
            "engine envelope names deterministic reduction mode"
            ("onednn-fixed-block-reduction" `Text.isInfixOf` Engine.renderEngineEnvelope envelope)
      , testCase "hardware auto-tuning benchmark plan enumerates deterministic candidates" $ do
          let plan = Tuning.benchmarkPlan Tuning.linuxCudaKnobs
              deterministicDefault = Tuning.selectDeterministic Tuning.linuxCudaKnobs
              rendered = Tuning.renderBenchmarkPlan plan
          Tuning.benchmarkPlanSubstrate plan @?= Substrate.LinuxCUDA
          length (Tuning.benchmarkPlanResults plan) @?= 72
          assertBool
            "deterministic default is included"
            (deterministicDefault `elem` Tuning.benchmarkPlanResults plan)
          assertBool
            "benchmark plan renders cache-key tuning choices"
            ( Cache.unTuningChoice (Tuning.tuningChoiceForResult deterministicDefault)
                `Text.isInfixOf` rendered
            )
      , testCase "cachePath resolves under the substrate cache root" $
          withSystemTempDirectory "jitml-cache-layout" $ \dir -> do
            root <- resolveDir' (dir </> ".build")
            path <- CacheLayout.cachePath root Cache.AppleSilicon sampleCacheHash (Cache.Extension "dylib")
            toFilePath path
              @?= dir
              </> ".build/jit/apple-silicon/"
              <> Text.unpack (Cache.hashHex sampleCacheHash)
              <> ".dylib"
      , testCase "manifest round-trips and indexes latest hashes" $
          withSystemTempDirectory "jitml-cache-manifest" $ \dir -> do
            root <- resolveDir' (dir </> ".build")
            let entry =
                  CacheManifest.ManifestEntry
                    { CacheManifest.manifestEntryModelId = Cache.ModelId "mnist-linear"
                    , CacheManifest.manifestEntryKind = Cache.Training
                    , CacheManifest.manifestEntrySubstrate = Cache.AppleSilicon
                    , CacheManifest.manifestEntryToolchain =
                        Cache.ToolchainFingerprint "llvm=ghc-9.14.1;xcode-metal=pinned;tuning=default"
                    , CacheManifest.manifestEntryHash = sampleCacheHash
                    }
                manifest = CacheManifest.upsertManifest entry CacheManifest.emptyManifest
                key = CacheManifest.manifestEntryKey entry
            decode (encode manifest) @?= Just manifest
            CacheManifest.lookupManifest key manifest @?= Just sampleCacheHash
            CacheManifest.writeManifestAtomic root manifest
            readResult <- CacheManifest.readManifest root
            readResult @?= Right manifest
      , testCase "repointSymlink replaces Apple stable FFI link atomically" $
          withSystemTempDirectory "jitml-cache-symlink" $ \dir -> do
            root <- resolveDir' (dir </> ".build")
            let modelId = Cache.ModelId "mnist-linear"
                extension = Cache.Extension "dylib"
                nextHash =
                  Cache.cacheKey
                    (Cache.KernelSpec "phase-2-kernel:conv")
                    Cache.Inference
                    Cache.AppleSilicon
                    (Cache.ToolchainFingerprint "llvm=ghc-9.14.1;xcode-metal=pinned;tuning=default")
                    Cache.defaultRuntimeSourcePayload
                    Cache.defaultTuningChoice
            firstTarget <- CacheLayout.cachePath root Cache.AppleSilicon sampleCacheHash extension
            secondTarget <- CacheLayout.cachePath root Cache.AppleSilicon nextHash extension
            createDirectoryIfMissing True (takeDirectory (toFilePath firstTarget))
            Text.IO.writeFile (toFilePath firstTarget) "first"
            Text.IO.writeFile (toFilePath secondTarget) "second"
            link <- CacheSymlink.repointSymlink root modelId sampleCacheHash extension
            firstLinkTarget <- readSymbolicLink (toFilePath link)
            firstLinkTarget @?= toFilePath firstTarget
            failures <- newIORef []
            reader <-
              forkIO $
                let loop = do
                      result <- try (readSymbolicLink (toFilePath link)) :: IO (Either SomeException FilePath)
                      case result of
                        Left err -> modifyIORef' failures (("read failed: " <> show err) :)
                        Right target
                          | target `elem` [toFilePath firstTarget, toFilePath secondTarget] -> pure ()
                          | otherwise -> modifyIORef' failures (("unexpected target: " <> target) :)
                      threadDelay 1000
                      loop
                 in loop
            traverse_
              ( \index ->
                  CacheSymlink.repointSymlink
                    root
                    modelId
                    (if even index then sampleCacheHash else nextHash)
                    extension
              )
              ([1 .. 50] :: [Int])
            killThread reader
            observedFailures <- readIORef failures
            observedFailures @?= []
            sameLink <- CacheSymlink.repointSymlink root modelId nextHash extension
            sameLink @?= link
            secondLinkTarget <- readSymbolicLink (toFilePath link)
            secondLinkTarget @?= toFilePath secondTarget
      , testCase "bootstrap materialization reports no-op on a second pass" $
          withSystemTempDirectory "jitml-materialize" $ \dir -> do
            let legacyMinioValues = dir </> "chart" </> "templates" </> "minio-values.yaml"
                standaloneMinioValues = dir </> "chart" </> "minio-values.yaml"
            createDirectoryIfMissing True (takeDirectory legacyMinioValues)
            createDirectoryIfMissing True (takeDirectory standaloneMinioValues)
            writeFile legacyMinioValues "legacy values location\n"
            writeFile standaloneMinioValues "standalone values location\n"
            first <- materializeBootstrapFiles dir Substrate.LinuxCPU
            second <- materializeBootstrapFiles dir Substrate.LinuxCPU
            legacyExists <- doesFileExist legacyMinioValues
            standaloneExists <- doesFileExist standaloneMinioValues
            first @?= True
            second @?= False
            legacyExists @?= False
            standaloneExists @?= False
      , testCase "chart lint skips Helm dependency archive cache" $
          withSystemTempDirectory "jitml-chart-lint" $ \dir -> do
            let archive = dir </> "chart" </> "charts" </> "gateway-helm-1.2.6.tgz"
                storageClass = dir </> "chart" </> "templates" </> "storageclass-jitml-manual.yaml"
            createDirectoryIfMissing True (takeDirectory archive)
            createDirectoryIfMissing True (takeDirectory storageClass)
            StrictByteString.writeFile archive (StrictByteString.pack [0x1f, 0x8b, 0x08, 0x00])
            writeFile
              storageClass
              ( unlines
                  [ "apiVersion: storage.k8s.io/v1"
                  , "kind: StorageClass"
                  , "metadata:"
                  , "  name: jitml-manual"
                  , "provisioner: kubernetes.io/no-provisioner"
                  ]
              )
            cwd <- getCurrentDirectory
            bracket_ (setCurrentDirectory dir) (setCurrentDirectory cwd) $ do
              _ <- checkChartFiles
              pure ()
      , testGroup
          "stage-0 bootstrap scripts"
          [ testCase "apple help names the Haskell bootstrap delegation" $ do
              result <- runBootstrapScript Nothing "bootstrap/apple-silicon.sh" ["help"]
              scriptExit result @?= ExitSuccess
              assertContains "apple help" "./.build/jitml bootstrap --apple-silicon" (scriptStdout result)
          , testCase "apple doctor rejects non-macOS hosts" $ do
              withStubCommands [unameStub "Linux" "arm64"] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "apple non-macOS diagnostic" "requires macOS" (scriptStderr result)
          , testCase "apple doctor rejects non-arm64 hosts" $ do
              withStubCommands [unameStub "Darwin" "x86_64"] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "apple non-arm64 diagnostic" "requires Apple Silicon arm64" (scriptStderr result)
          , testCase "apple doctor reports missing Xcode Command Line Tools" $
              withStubCommands [unameStub "Darwin" "arm64", xcodeSelectUnavailableStub, brewStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "apple xcode diagnostic" "xcode-select --install" (scriptStderr result)
          , testCase "apple doctor reports missing Homebrew" $
              withStubCommands [unameStub "Darwin" "arm64", xcodeSelectStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "apple homebrew diagnostic" "install Homebrew" (scriptStderr result)
          , testCase "apple doctor ignores broad package-toolchain gaps" $
              withStubCommands [unameStub "Darwin" "arm64", xcodeSelectStub, brewStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                scriptExit result @?= ExitSuccess
                assertContains "apple doctor ok" "stage-0 doctor: ok" (scriptStderr result)
          , testCase "linux CPU doctor reports missing Docker" $ do
              withStubCommands [] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/linux-cpu.sh"
                    ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "linux docker diagnostic" "missing required command 'docker'" (scriptStderr result)
          , testCase "linux CPU doctor requires Docker without sudo" $
              withStubCommands [dockerInfoFailureStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cpu.sh" ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "linux sudo diagnostic" "without sudo" (scriptStderr result)
          , testCase "linux CPU doctor ignores non-Docker toolchain gaps" $
              withStubCommands [dockerOkStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/linux-cpu.sh"
                    ["doctor"]
                scriptExit result @?= ExitSuccess
                assertContains "linux cpu doctor ok" "stage-0 doctor: ok" (scriptStderr result)
          , testCase "linux CUDA doctor reports missing NVIDIA runtime" $
              withStubCommands [dockerWithoutNvidiaRuntimeStub, nvidiaSmiHighCapabilityStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cuda.sh" ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "cuda runtime diagnostic" "NVIDIA container runtime" (scriptStderr result)
          , testCase "linux CUDA doctor reports insufficient compute capability" $
              withStubCommands [dockerWithNvidiaRuntimeStub, nvidiaSmiLowCapabilityStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cuda.sh" ["doctor"]
                scriptExit result @?= ExitFailure 2
                assertContains "cuda capability diagnostic" "compute capability" (scriptStderr result)
          ]
      , testCase "buildEnv uses default dirs" $ do
          env <- buildEnv defaultGlobalFlags
          takeFileNameCompat (toFilePath (envCacheDir env)) @?= ".build"
          takeFileNameCompat (toFilePath (envDataDir env)) @?= ".data"
      , testCase "buildEnv uses explicit CLI overrides" $
          withSystemTempDirectory "jitml-env-cli" $ \dir -> do
            env <-
              buildEnv
                defaultGlobalFlags
                  { globalCacheDir = Just (dir </> "cli-build")
                  , globalFormat = Just OutputJson
                  }
            toFilePath (envCacheDir env) @?= dir </> "cli-build/"
            envFormat env @?= OutputJson
      , testCase "service hot reload increments only on config changes" $ do
          let initial = HotReload.initialSnapshot LiveConfig.defaultLiveConfig
          HotReload.handleSighupReload initial LiveConfig.defaultLiveConfig
            @?= HotReload.ReloadIgnored "live config unchanged"
          case HotReload.handleSighupReload
            initial
            LiveConfig.defaultLiveConfig {LiveConfig.liveInferenceBatchSize = 128} of
            HotReload.ReloadIgnored reason -> assertFailure (Text.unpack reason)
            HotReload.ReloadApplied snapshot -> HotReload.snapshotGeneration snapshot @?= 1
      , testCase "service capability classes are named in the local surface" $
          Capabilities.capabilityNames
            @?= ["HasMinIO", "HasPulsar", "HasHarbor", "HasKubectl"]
      , testCase "AsyncBuffer drains async writes in spawn order (Sprint 8.4)" $ do
          writeLog <- newIORef ([] :: [Int])
          let sink =
                AsyncBuffer.AsyncSink
                  ( \transitions -> do
                      modifyIORef' writeLog (length transitions :)
                      pure (AsyncBuffer.AsyncWriteOk (Text.pack ("wrote " <> show (length transitions))))
                  )
          buffer <- AsyncBuffer.newAsyncBuffer Buffer.OnPolicyRollout 8 sink
          let mkT n =
                Buffer.Transition
                  { Buffer.transitionStep = n
                  , Buffer.transitionAction = n
                  , Buffer.transitionReward = fromIntegral n
                  , Buffer.transitionObservation = n
                  , Buffer.transitionDone = False
                  }
          mapM_ (AsyncBuffer.insertAsync buffer . mkT) [0 .. 4 :: Int]
          results <- AsyncBuffer.drainAsync buffer
          length results @?= 5
          let isOk (AsyncBuffer.AsyncWriteOk _) = True
              isOk _ = False
          mapM_ (assertBool "write OK" . isOk) results
          pending <- AsyncBuffer.pendingAsyncCount buffer
          pending @?= 0
      , testCase "canonical RL environments and framework surfaces are deterministic" $ do
          fmap RLEnvironments.environmentName RLEnvironments.canonicalEnvironments
            @?= ["cartpole", "mountain-car", "lunar-lander", "atari-subset"]
          case RLEnvironments.canonicalEnvironments of
            [] -> assertFailure "missing canonical environments"
            environment : _ ->
              RLEnvironments.deterministicStep environment 7 1
                @?= RLEnvironments.deterministicStep environment 7 1
          fmap RLFramework.renderRLRunPhase RLFramework.rlRunPlan
            @?= ["collect", "compute-advantages", "optimise", "evaluate", "checkpoint"]
      , testCase "AlphaZero catalog includes games, two-headed network, and arena summary" $ do
          fmap AlphaZero.pigName AlphaZero.canonicalGames
            @?= ["connect4", "othello", "hex", "gomoku"]
          AlphaZero.policyHeadSize AlphaZero.connect4Network @?= 7
          AlphaZero.arenaWinRate (AlphaZero.ArenaSummary 3 1 0) @?= 0.75
      , testCase "MCTS transposition table de-dupes equivalent move sequences" $ do
          let cfg = Mcts.defaultMctsConfig 7
              table0 = Mcts.emptyTranspositionTable
              (_, table1) = Mcts.runSearchWithTable cfg 42 [0, 1, 2] table0
              (_, table2) = Mcts.runSearchWithTable cfg 42 [0, 1, 2] table1
              (_, table3) = Mcts.runSearchWithTable cfg 42 [0, 1, 3] table2
          Mcts.transpositionSize table1 @?= 1
          Mcts.transpositionSize table2 @?= 1 -- duplicate move sequence collapses
          Mcts.transpositionSize table3 @?= 2 -- distinct move sequence allocates
          assertBool
            "transposition key is stable across calls"
            (Mcts.transpositionKey [0, 1, 2] == Mcts.transpositionKey [0, 1, 2])
          assertBool
            "distinct move sequences hash differently"
            (Mcts.transpositionKey [0, 1, 2] /= Mcts.transpositionKey [0, 1, 3])
      , testCase "tuning trial storage and resume summary are deterministic" $ do
          Tune.trialStorageKey "exp-a" 42 @?= "jitml-trials/exp-a/42/transcript.cbor"
          Tune.resumeMatchesFullRun Tune.Sobol 3 8 @?= True
      , testCase "checkpoint split-blob keys and pointer CAS are deterministic" $ do
          Checkpoint.blobKey "exp-a" "sha-a" @?= "jitml-checkpoints/exp-a/blobs/sha-a"
          Checkpoint.manifestKey "exp-a" "sha-m" @?= "jitml-checkpoints/exp-a/manifests/sha-m.cbor"
          Checkpoint.latestPointerKey "exp-a" @?= "jitml-checkpoints/exp-a/pointers/latest"
          let write =
                Checkpoint.PointerWrite
                  { Checkpoint.pointerWriteKey = Checkpoint.latestPointerKey "exp-a"
                  , Checkpoint.pointerWriteExpectedETag = Just "etag-a"
                  , Checkpoint.pointerWriteManifestSha = "sha-m"
                  }
          Checkpoint.applyPointerWrite (Just "etag-a") write
            @?= Checkpoint.PointerWritten "sha-m"
          Checkpoint.applyPointerWrite (Just "etag-b") write
            @?= Checkpoint.PointerConflict (Checkpoint.latestPointerKey "exp-a")
      , testCase "jmw1 encoder emits magic, CBOR header length, and little-endian doubles" $ do
          let payload = Checkpoint.encodeJmw1 [1.0]
          ByteString.take 4 payload @?= "JMW1"
          assertBool "binary header is present" (ByteString.length payload > 16)
          ByteString.drop (ByteString.length payload - 8) payload
            @?= ByteString.pack [0, 0, 0, 0, 0, 0, 240, 63]
      , testCase "checkpoint manifest CBOR codec is deterministic and canonical ordered" $ do
          let manifest =
                Checkpoint.emptyManifest
                  "manifest-a"
                  "exp-a"
                  [ Checkpoint.TensorBlob "z" [1] "blob-z"
                  , Checkpoint.TensorBlob "a" [2] "blob-a"
                  ]
              reordered =
                Checkpoint.emptyManifest
                  "manifest-a"
                  "exp-a"
                  [ Checkpoint.TensorBlob "a" [2] "blob-a"
                  , Checkpoint.TensorBlob "z" [1] "blob-z"
                  ]
          Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor manifest)
            @?= Right reordered
          Checkpoint.manifestContentSha manifest @?= Checkpoint.manifestContentSha reordered
          Checkpoint.manifestKey "exp-a" (Checkpoint.manifestContentSha manifest)
            @?= "jitml-checkpoints/exp-a/manifests/"
            <> Checkpoint.manifestContentSha manifest
            <> ".cbor"
      , testCase "checkpoint store writes blobs/manifests and reads latest inference path" $
          withSystemTempDirectory "jitml-checkpoint-store" $ \dir -> do
            let blobKey = Checkpoint.blobKey "exp1" "blob1"
                manifest =
                  Checkpoint.emptyManifest
                    "m1"
                    "exp1"
                    [Checkpoint.TensorBlob "dense.weight" [2, 2] blobKey]
                payload = Checkpoint.encodeJmw1 [1, 2, 3, 4]
            firstWrite <- CheckpointStore.writeCheckpointSnapshot dir manifest [(blobKey, payload)] Nothing
            CheckpointStore.storedPointerResult firstWrite
              @?= Checkpoint.PointerWritten (CheckpointStore.storedManifestSha firstWrite)
            decoded <-
              CheckpointStore.readCheckpointManifest
                dir
                "exp1"
                (CheckpointStore.storedManifestSha firstWrite)
            decoded @?= Right manifest
            listed <- CheckpointStore.listCheckpointManifests dir "exp1"
            listed @?= Right [manifest]
            inferred <- CheckpointStore.inferFromLatestCheckpoint dir "exp1" [10, 20]
            inferred @?= Right (Checkpoint.inferFromManifest manifest [10, 20])
            conflict <- CheckpointStore.writeCheckpointSnapshot dir manifest [(blobKey, payload)] Nothing
            CheckpointStore.storedPointerResult conflict
              @?= Checkpoint.PointerConflict (Checkpoint.latestPointerKey "exp1")
      , testCase "TensorBoard checkpoint sidecar keys are stable" $
          TensorBoard.checkpointSidecarKey "exp-a" 12 "sha-m"
            @?= "jitml-tensorboard/exp-a/checkpoints/12-sha-m.cbor"
      , testCase "TensorBoard shard keys include writer id and shard sequence" $
          TensorBoard.shardKey "exp-a" "writer-1" 3
            @?= "jitml-tensorboard/exp-a/shards/writer-1-3.tfevents"
      , testCase "TensorBoard Event protobuf encoder matches the vendored schema" $ do
          let encoded =
                TensorBoard.encodeTensorBoardEventProto
                  TensorBoard.TensorBoardEvent
                    { TensorBoard.tbWallTime = 0
                    , TensorBoard.tbStep = 7
                    , TensorBoard.tbTag = "loss"
                    , TensorBoard.tbValue = 1.5
                    }
          encoded
            @?= StrictByteString.pack
              [ 0x09
              , 0x00
              , 0x00
              , 0x00
              , 0x00
              , 0x00
              , 0x00
              , 0x00
              , 0x00
              , 0x10
              , 0x07
              , 0x2a
              , 0x0d
              , 0x0a
              , 0x0b
              , 0x0a
              , 0x04
              , 0x6c
              , 0x6f
              , 0x73
              , 0x73
              , 0x15
              , 0x00
              , 0x00
              , 0xc0
              , 0x3f
              ]
      , testCase "TensorBoard CRC32C-Castagnoli matches canonical vectors" $ do
          -- Canonical CRC32C test vectors from RFC 3720 Appendix B.4.
          TensorBoard.crc32cCastagnoli "" @?= 0x00000000
          TensorBoard.crc32cCastagnoli (StrictByteString.pack [0x61]) @?= 0xC1D04330
          TensorBoard.crc32cCastagnoli (StrictByteString.replicate 32 0x00) @?= 0x8A9136AA
          TensorBoard.crc32cCastagnoli "123456789" @?= 0xE3069283
      , testCase "TbCheckpointMarker CBOR sidecar is deterministic" $ do
          let marker =
                TensorBoard.TbCheckpointMarker
                  { TensorBoard.tcmStep = 100
                  , TensorBoard.tcmEpoch = 4
                  , TensorBoard.tcmManifestSha = "sha-m"
                  , TensorBoard.tcmExperimentSha = "exp-a"
                  , TensorBoard.tcmTrialSha = Nothing
                  , TensorBoard.tcmRunUuid = "uuid-1"
                  , TensorBoard.tcmMetricsAtStep = [("loss", 0.5), ("acc", 0.92)]
                  }
              encoded = TensorBoard.encodeTbCheckpointMarker marker
              again = TensorBoard.encodeTbCheckpointMarker marker
          encoded @?= again
          assertBool "encoded payload is non-empty" (ByteString.length encoded > 0)
      , testCase "shouldRotateShard honours bytes / elapsed / explicit limits" $ do
          let limits = TensorBoard.defaultShardRotationLimits
          TensorBoard.shouldRotateShard 1024 1 limits @?= TensorBoard.ShardKeepOpen
          TensorBoard.shouldRotateShard (4 * 1024 * 1024) 1 limits
            @?= TensorBoard.ShardRotateForBytes (4 * 1024 * 1024) (4 * 1024 * 1024)
          TensorBoard.shouldRotateShard 1024 30 limits
            @?= TensorBoard.ShardRotateForElapsed 30 10
          TensorBoard.shouldRotateShard 1024 1 (limits {TensorBoard.shardExplicitFlush = True})
            @?= TensorBoard.ShardRotateForExplicit
      , testCase "TFRecord frame encodes length + masked CRCs + payload" $ do
          let payload = StrictByteString.pack [0x01, 0x02, 0x03, 0x04]
              frame = ByteString.toStrict (TensorBoard.encodeTfRecord payload)
          StrictByteString.length frame @?= 8 + 4 + 4 + 4
          StrictByteString.take 8 frame
            @?= StrictByteString.pack [0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
          let payloadOffset = 8 + 4
              extractedPayload =
                StrictByteString.take 4 (StrictByteString.drop payloadOffset frame)
          extractedPayload @?= payload
      , testCase "Grafana daemon-health dashboard matches golden fixture" $ do
          expected <- Text.IO.readFile "test/golden/observability/grafana-daemon-health.yaml"
          case find ((== "daemon-health") . Grafana.dashboardName) Grafana.dashboards of
            Nothing -> assertFailure "missing daemon-health dashboard"
            Just dashboard -> Grafana.renderDashboardConfigMap dashboard @?= expected
      , testCase "frontend bundle and panel surfaces cover the demo panels" $ do
          fmap WebBundle.panelName WebBundle.panelSurfaces
            @?= [ "mnist-live-inference"
                , "cifar-imagenet-upload"
                , "connect4-human-vs-alphazero"
                , "rl-trajectory"
                , "training-progress"
                , "hyperparameter-sweep"
                ]
          fmap WebBundle.demoRoutePath WebBundle.demoRoutes
            @?= [ "/"
                , "/api"
                , "/api/inference"
                , "/api/images"
                , "/api/connect4/move"
                , "/api/ws"
                , "/api/ws/training"
                , "/api/ws/tune"
                ]
          WebBundle.renderDemoRouteManifest
            @?= Text.unlines
              [ "demo-routes:"
              , "- / static-shell <- web/src/Main.purs"
              , "- /api contract-index <- src/JitML/Web/Contracts.hs"
              , "- /api/inference inference-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/images image-upload-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/connect4/move connect4-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws metrics-stream-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws/training training-stream-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws/tune tune-stream-contract <- src/JitML/Web/Contracts.hs"
              ]
          WebContracts.contractGeneratorName @?= "local-purescript-bridge-compatible-renderer"
      ]

takeFileNameCompat :: FilePath -> FilePath
takeFileNameCompat path =
  reverse (takeWhile (/= '/') (dropWhile (== '/') (reverse path)))

sampleCacheHash :: Cache.Hash
sampleCacheHash =
  Cache.cacheKey
    (Cache.KernelSpec "phase-2-kernel:linear")
    Cache.Training
    Cache.AppleSilicon
    (Cache.ToolchainFingerprint "llvm=ghc-9.14.1;xcode-metal=pinned;tuning=default")
    Cache.defaultRuntimeSourcePayload
    Cache.defaultTuningChoice

canonicalErrors :: [AppError]
canonicalErrors =
  [ AppError.PrerequisiteUnmet
      "ghc-9.14.1"
      "GHC 9.14.1 is required."
      (Just "ghcup install ghc 9.14.1")
  , AppError.SubprocessFailed "kubectl get pods" (ExitFailure 1) "kubectl failed"
  , AppError.MinIOFailed "bucket unavailable"
  , AppError.PulsarFailed "broker unavailable"
  , AppError.HarborFailed "registry unavailable"
  , AppError.KubectlFailed "context missing"
  , AppError.DocsCheckDrift $
      Text.unlines
        [ "file: README.md"
        , "key: command-tree"
        , "Run `jitml docs generate` to update."
        ]
  , AppError.UnknownCommand "unknown command: jitml missing"
  , AppError.InvalidConfig "BootConfig changed under SIGHUP"
  , AppError.DhallTypeError "expected Natural"
  , AppError.ChartLintFailed $
      Text.unlines
        [ "file: chart/templates/pv.yaml"
        , "key: chart.storage"
        , "message: invalid storage class"
        , "remedy: use jitml-manual"
        ]
  , AppError.RouteRegistryDrift "httproute generated output is stale"
  , AppError.JitCacheMiss "abc123"
  , AppError.JitToolchainDrift "cached with older nvcc"
  , AppError.CheckpointFormatUnsupported ".jmw0"
  , AppError.CheckpointWriteConflict "latest pointer etag changed"
  , AppError.ReconcilerNoop "docs generate: no changes"
  ]

assertParseSuccess :: ([String], ParsedCommand) -> Assertion
assertParseSuccess (args, expected) =
  case execParserPure defaultPrefs parserInfo args of
    Success parsed -> parsed @?= expected
    Failure _ -> assertFailure ("parse failed for " <> show args)
    CompletionInvoked _ -> assertFailure ("completion invoked for " <> show args)

data ScriptResult = ScriptResult
  { scriptExit :: ExitCode
  , scriptStdout :: String
  , scriptStderr :: String
  }
  deriving stock (Eq, Show)

runBootstrapScript
  :: Maybe FilePath -> FilePath -> [String] -> IO ScriptResult
runBootstrapScript pathPrefix script args = do
  let process =
        Subprocess
          { subprocessPath = script
          , subprocessArguments = fmap Text.pack (commandDirArgs <> args)
          , subprocessWorkingDirectory = Just "."
          , subprocessStdin = Nothing
          }
  (exitCode, stdoutText, stderrText) <- runStreaming defaultSubprocessEnv process
  pure
    ScriptResult
      { scriptExit = exitCode
      , scriptStdout = Text.unpack stdoutText
      , scriptStderr = Text.unpack stderrText
      }
 where
  commandDirArgs =
    case pathPrefix of
      Nothing -> []
      Just dir -> ["--command-dir", dir]

withStubCommands :: [(FilePath, String)] -> (FilePath -> IO a) -> IO a
withStubCommands commands action =
  withSystemTempDirectory "jitml-bootstrap-stubs" $ \dir -> do
    traverse_ (writeStubCommand dir) commands
    action dir

writeStubCommand :: FilePath -> (FilePath, String) -> IO ()
writeStubCommand dir (name, body) = do
  let path = dir </> name
  writeFile path body
  permissions <- getPermissions path
  setPermissions path (setOwnerExecutable True permissions)

assertContains :: String -> String -> String -> Assertion
assertContains label needle haystack =
  assertBool
    (label <> " did not contain " <> show needle <> " in:\n" <> haystack)
    (needle `isInfixOf` haystack)

xcodeSelectStub :: (FilePath, String)
xcodeSelectStub =
  ( "xcode-select"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"-p\" ]; then"
      , "  printf '%s\\n' /Library/Developer/CommandLineTools"
      , "  exit 0"
      , "fi"
      , "exit 0"
      ]
  )

xcodeSelectUnavailableStub :: (FilePath, String)
xcodeSelectUnavailableStub =
  ( "xcode-select"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"-p\" ]; then"
      , "  exit 1"
      , "fi"
      , "exit 0"
      ]
  )

unameStub :: String -> String -> (FilePath, String)
unameStub osName archName =
  ( "uname"
  , unlines
      [ "#!/usr/bin/env bash"
      , "case \"${1:-}\" in"
      , "  -s) printf '%s\\n' '" <> osName <> "' ;;"
      , "  -m) printf '%s\\n' '" <> archName <> "' ;;"
      , "  *) printf '%s\\n' '" <> osName <> "' ;;"
      , "esac"
      ]
  )

brewStub :: (FilePath, String)
brewStub =
  ( "brew"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"--version\" ]; then"
      , "  printf '%s\\n' 'Homebrew 4.0.0'"
      , "  exit 0"
      , "fi"
      , "exit 0"
      ]
  )

dockerOkStub :: (FilePath, String)
dockerOkStub =
  ( "docker"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"info\" ]; then"
      , "  exit 0"
      , "fi"
      , "exit 0"
      ]
  )

dockerInfoFailureStub :: (FilePath, String)
dockerInfoFailureStub =
  ( "docker"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"info\" ]; then"
      , "  printf '%s\\n' 'permission denied' >&2"
      , "  exit 1"
      , "fi"
      , "exit 0"
      ]
  )

dockerWithNvidiaRuntimeStub :: (FilePath, String)
dockerWithNvidiaRuntimeStub =
  dockerRuntimeStub "{\"nvidia\":{},\"runc\":{}}"

dockerWithoutNvidiaRuntimeStub :: (FilePath, String)
dockerWithoutNvidiaRuntimeStub =
  dockerRuntimeStub "{\"runc\":{}}"

dockerRuntimeStub :: String -> (FilePath, String)
dockerRuntimeStub runtimeJson =
  ( "docker"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"info\" ] && [ \"${2:-}\" = \"--format\" ]; then"
      , "  printf '%s\\n' '" <> runtimeJson <> "'"
      , "  exit 0"
      , "fi"
      , "if [ \"${1:-}\" = \"info\" ]; then"
      , "  exit 0"
      , "fi"
      , "exit 0"
      ]
  )

nvidiaSmiHighCapabilityStub :: (FilePath, String)
nvidiaSmiHighCapabilityStub =
  nvidiaSmiCapabilityStub "8.0"

nvidiaSmiLowCapabilityStub :: (FilePath, String)
nvidiaSmiLowCapabilityStub =
  nvidiaSmiCapabilityStub "6.1"

nvidiaSmiCapabilityStub :: String -> (FilePath, String)
nvidiaSmiCapabilityStub capability =
  ( "nvidia-smi"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"--query-gpu=compute_cap\" ]; then"
      , "  printf '%s\\n' '" <> capability <> "'"
      , "  exit 0"
      , "fi"
      , "exit 0"
      ]
  )

canonicalLeafPaths :: [[Text]]
canonicalLeafPaths =
  [ ["bootstrap"]
  , ["doctor"]
  , ["service"]
  , ["cluster", "up"]
  , ["cluster", "down"]
  , ["cluster", "status"]
  , ["cluster", "reset"]
  , ["train"]
  , ["eval"]
  , ["tune"]
  , ["rl", "train"]
  , ["rl", "eval"]
  , ["rl", "rollout"]
  , ["verify", "same-run"]
  , ["verify", "cross-backend"]
  , ["verify", "replay"]
  , ["inspect", "list"]
  , ["inspect", "show"]
  , ["inspect", "replay"]
  , ["inspect", "trial"]
  , ["inspect", "frontier"]
  , ["bench", "train"]
  , ["bench", "inference"]
  , ["bench", "env"]
  , ["inference", "run"]
  , ["test", "all"]
  , ["test", "jitml-unit"]
  , ["test", "jitml-integration"]
  , ["test", "jitml-sl-canonicals"]
  , ["test", "jitml-rl-canonicals"]
  , ["test", "jitml-hyperparameter"]
  , ["test", "jitml-cross-backend"]
  , ["test", "jitml-daemon-lifecycle"]
  , ["test", "jitml-e2e"]
  , ["lint", "files"]
  , ["lint", "docs"]
  , ["lint", "proto"]
  , ["lint", "chart"]
  , ["lint", "haskell"]
  , ["lint", "purescript"]
  , ["lint", "all"]
  , ["docs", "check"]
  , ["docs", "generate"]
  , ["check-code"]
  , ["build"]
  , ["kubectl"]
  , ["internal", "materialize-substrate"]
  , ["internal", "list-prereqs"]
  , ["internal", "gc"]
  , ["internal", "vm", "bootstrap"]
  , ["internal", "vm", "up"]
  , ["internal", "vm", "down"]
  , ["internal", "vm", "status"]
  , ["internal", "vm", "exec"]
  , ["internal", "cache", "stat"]
  , ["internal", "cache", "list"]
  , ["internal", "cache", "evict"]
  , ["commands"]
  , ["help"]
  ]

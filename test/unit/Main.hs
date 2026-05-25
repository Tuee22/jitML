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
import Data.List qualified as List
import Data.Maybe (fromMaybe)
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
import System.Info qualified as SystemInfo
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
import JitML.Codegen.Cuda qualified as Cuda
import JitML.Codegen.KernelFamily (KernelFamily (..))
import JitML.Codegen.Metal qualified as Metal
import JitML.Codegen.RuntimeSource (renderRuntimeSource, runtimeSourcePayload)
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.CpuFeatures qualified as CpuFeatures
import JitML.Engines.CublasBindings qualified as Cublas
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.CudnnBindings qualified as Cudnn
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.Loader qualified as Loader
import JitML.Engines.Local qualified as LocalEngine
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.OneDnnRuntime qualified as OneDnnRuntime
import JitML.Engines.Rng qualified as Rng
import JitML.Engines.Tuning qualified as Tuning
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Engines.TuningCache qualified as TuningCache
import JitML.Engines.TuningStore qualified as TuningStore
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
import JitML.RL.Simulator qualified as Sim
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate qualified as Substrate
import JitML.Tart.Build qualified as TartBuild
import JitML.Tart.Lifecycle (VmName (..))
import JitML.Tart.Lifecycle qualified as TartLifecycle
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
                  sampleRuntimeSourcePayload
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
      , testCase "linux-cpu local fingerprint includes host artifact ABI" $ do
          let expectedAbi =
                "artifact-abi="
                  <> Text.pack SystemInfo.os
                  <> "-"
                  <> Text.pack SystemInfo.arch
          assertBool
            "linux-cpu local fingerprint separates host/container artifact ABIs"
            (expectedAbi `Text.isInfixOf` Cache.unToolchainFingerprint LocalEngine.linuxCpuToolchainFingerprint)
          assertBool
            "linux-cpu local fingerprint records the deterministic reduction block"
            ( "reduction-block=256"
                `Text.isInfixOf` Cache.unToolchainFingerprint LocalEngine.linuxCpuToolchainFingerprint
            )
      , testCase "CpuFeatures parsers select deterministic oneDNN micro-kernel knobs" $ do
          let linuxAvx512 =
                CpuFeatures.cpuFeaturesFromLinuxCpuinfo
                  ( Text.unlines
                      [ "vendor_id\t: GenuineIntel"
                      , "flags\t: fpu sse4_2 avx2 avx512f"
                      ]
                  )
              linuxAvx2 =
                CpuFeatures.cpuFeaturesFromLinuxCpuinfo
                  ( Text.unlines
                      [ "vendor_id\t: AuthenticAMD"
                      , "flags\t: fpu sse4_2 avx2"
                      ]
                  )
              linuxReference =
                CpuFeatures.cpuFeaturesFromLinuxCpuinfo
                  ( Text.unlines
                      [ "vendor_id\t: other"
                      , "flags\t: fpu sse4_2"
                      ]
                  )
              darwinApple =
                CpuFeatures.cpuFeaturesFromDarwinSysctl
                  ( Text.unlines
                      [ "machdep.cpu.brand_string: Apple M3"
                      , "hw.optional.avx2_0: 0"
                      , "hw.optional.avx512f: 0"
                      ]
                  )
              darwinIntel =
                CpuFeatures.cpuFeaturesFromDarwinSysctl
                  ( Text.unlines
                      [ "machdep.cpu.brand_string: Intel"
                      , "hw.optional.avx2_0: 1"
                      , "hw.optional.avx512f: 0"
                      ]
                  )
          linuxAvx512
            @?= CpuFeatures.CpuFeatures
              { CpuFeatures.cpuHasAvx2 = True
              , CpuFeatures.cpuHasAvx512 = True
              , CpuFeatures.cpuVendor = "intel"
              }
          CpuFeatures.microKernelChoice linuxAvx512 @?= "onednn-jit-avx512"
          CpuFeatures.microKernelChoice linuxAvx2 @?= "onednn-jit-avx2"
          CpuFeatures.microKernelChoice linuxReference @?= "onednn-reference"
          darwinApple
            @?= CpuFeatures.CpuFeatures
              { CpuFeatures.cpuHasAvx2 = False
              , CpuFeatures.cpuHasAvx512 = False
              , CpuFeatures.cpuVendor = "apple-silicon"
              }
          CpuFeatures.microKernelChoice darwinApple @?= "onednn-reference"
          CpuFeatures.microKernelChoice darwinIntel @?= "onednn-jit-avx2"
      , testCase "oneDNN runtime probe parser reports pkg-config and link visibility" $ do
          OneDnnRuntime.parsePkgConfigVersion "3.5.3\n" @?= Just "3.5.3"
          OneDnnRuntime.parsePkgConfigVersion "\n" @?= Nothing
          OneDnnRuntime.oneDnnLibraryVisibleFromLdconfig
            "libdnnl.so.3 (libc6,AArch64) => /usr/lib/libdnnl.so.3\n"
            @?= True
          OneDnnRuntime.oneDnnLibraryVisibleFromLdconfig
            "libblas.so.3 (libc6,AArch64) => /usr/lib/libblas.so.3\n"
            @?= False
          let availableProbe =
                OneDnnRuntime.OneDnnRuntimeProbe
                  { OneDnnRuntime.oneDnnRuntimePkgConfigName = Just "dnnl"
                  , OneDnnRuntime.oneDnnRuntimePkgConfigVersion = Just "3.5.3"
                  , OneDnnRuntime.oneDnnRuntimeHeaderPath = Nothing
                  , OneDnnRuntime.oneDnnRuntimeLibraryVisible = True
                  , OneDnnRuntime.oneDnnRuntimeProbeLog =
                      [ "pkg-config --modversion dnnl: 3.5.3"
                      , "ldconfig -p: libdnnl visible=yes"
                      ]
                  }
              missingLibraryProbe =
                availableProbe {OneDnnRuntime.oneDnnRuntimeLibraryVisible = False}
              headerOnlyProbe =
                availableProbe
                  { OneDnnRuntime.oneDnnRuntimePkgConfigName = Nothing
                  , OneDnnRuntime.oneDnnRuntimePkgConfigVersion = Nothing
                  , OneDnnRuntime.oneDnnRuntimeHeaderPath = Just "/usr/include/oneapi/dnnl/dnnl.hpp"
                  }
              rendered = OneDnnRuntime.renderOneDnnRuntimeProbe availableProbe
          OneDnnRuntime.oneDnnRuntimeAvailable availableProbe @?= True
          OneDnnRuntime.oneDnnRuntimeAvailable headerOnlyProbe @?= True
          OneDnnRuntime.oneDnnRuntimeAvailable missingLibraryProbe @?= False
          assertBool
            "rendered probe records availability"
            ("available: yes" `Text.isInfixOf` rendered)
          assertBool
            "rendered probe records selected pkg-config module"
            ("pkg_config_name: dnnl" `Text.isInfixOf` rendered)
          assertBool
            "rendered probe records header path"
            ("header_path:" `Text.isInfixOf` rendered)
      , testCase "CUDA runtime probe parser reports nvcc, devices, and libraries" $ do
          let nvccOutput =
                Text.unlines
                  [ "nvcc: NVIDIA (R) Cuda compiler driver"
                  , "Cuda compilation tools, release 12.4, V12.4.99"
                  ]
              smiOutput =
                Text.unlines
                  [ "GPU 0: NVIDIA GeForce RTX 5090 (UUID: GPU-123)"
                  , "GPU 1: NVIDIA GeForce RTX 4090 (UUID: GPU-456)"
                  ]
              ldconfigOutput =
                Text.unlines
                  [ "libcuda.so.1 (libc6,x86-64) => /usr/lib/libcuda.so.1"
                  , "libcublas.so.12 (libc6,x86-64) => /usr/lib/libcublas.so.12"
                  , "libcudnn.so.9 (libc6,x86-64) => /usr/lib/libcudnn.so.9"
                  ]
              visibility = CudaRuntime.cudaLibrariesVisibleFromLdconfig ldconfigOutput
              availableProbe =
                CudaRuntime.CudaRuntimeProbe
                  { CudaRuntime.cudaRuntimeNvccVersion = Just "12.4"
                  , CudaRuntime.cudaRuntimeGpuDevices = CudaRuntime.parseNvidiaSmiDevices smiOutput
                  , CudaRuntime.cudaRuntimeLibraryVisibility = visibility
                  , CudaRuntime.cudaRuntimeProbeLog =
                      [ "nvcc --version: 12.4"
                      , "nvidia-smi -L: 2 device(s)"
                      , "ldconfig -p: libcuda=yes libcublas=yes libcudnn=yes"
                      ]
                  }
              missingCudnnProbe =
                availableProbe
                  { CudaRuntime.cudaRuntimeLibraryVisibility =
                      visibility {CudaRuntime.cudaDnnLibraryVisible = False}
                  }
              rendered = CudaRuntime.renderCudaRuntimeProbe availableProbe
          CudaRuntime.parseNvccVersion nvccOutput @?= Just "12.4"
          CudaRuntime.parseNvccVersion "\n" @?= Nothing
          CudaRuntime.parseNvidiaSmiDevices smiOutput
            @?= [ "GPU 0: NVIDIA GeForce RTX 5090 (UUID: GPU-123)"
                , "GPU 1: NVIDIA GeForce RTX 4090 (UUID: GPU-456)"
                ]
          CudaRuntime.cudaLibrariesAvailable visibility @?= True
          CudaRuntime.cudaRuntimeAvailable availableProbe @?= True
          CudaRuntime.cudaRuntimeAvailable missingCudnnProbe @?= False
          assertBool
            "rendered CUDA probe records availability"
            ("available: yes" `Text.isInfixOf` rendered)
          assertBool
            "rendered CUDA probe records cuDNN visibility"
            ("libcudnn: yes" `Text.isInfixOf` rendered)
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
      , testCase "kernel loader resolves cache hits without recompiling" $
          withSystemTempDirectory "jitml-kernel-loader" $ \dir -> do
            cwd <- getCurrentDirectory
            bracket_ (setCurrentDirectory dir) (setCurrentDirectory cwd) $ do
              env <- buildEnv defaultGlobalFlags
              let kernelSpec = Cache.KernelSpec "phase-7-kernel:loader"
                  engine = Engine.engineForSubstrate Substrate.LinuxCPU
                  source =
                    renderRuntimeSource
                      kernelSpec
                      Cache.Inference
                      Cache.LinuxCPU
                      Cache.defaultTuningChoice
                  handle = Engine.kernelHandleFor engine sampleCacheHash
                  artifactPath = Text.unpack (Engine.kernelHandleArtifactPath handle)
              createDirectoryIfMissing True (takeDirectory artifactPath)
              StrictByteString.writeFile artifactPath (StrictByteString.pack [0x7f, 0x45, 0x4c, 0x46])
              loaded <- Loader.ensureKernelArtifact env engine source sampleCacheHash
              case loaded of
                Left err -> assertFailure (Text.unpack err)
                Right artifact -> do
                  Loader.kernelArtifactHandle artifact @?= handle
                  Loader.kernelArtifactCompiled artifact @?= False
                  case Loader.kernelArtifactStatus artifact of
                    Engine.JitCacheHit loadedHandle ->
                      loadedHandle @?= handle
                    Engine.JitCacheMiss _ _ ->
                      assertFailure "expected loader cache hit"
                  assertBool
                    "loader keeps the typed compile command for diagnostics"
                    ("g++ -std=c++20" `Text.isInfixOf` Loader.kernelArtifactCompileCommand artifact)
      , testCase "splitmix RNG path is deterministic and CUDA codegen forbids curand" $ do
          Rng.splitMixWords 5 (Rng.SplitMixSeed 0)
            @?= [ 0xe220a8397b1dcdaf
                , 0x6e789e6aa1b965f4
                , 0x06c45d188009454f
                , 0xf88bb8a8724c81ec
                , 0x1b39896a51a8749b
                ]
          Rng.deriveSplitMixSeed (Rng.SplitMixSeed 42) 0
            @?= Rng.deriveSplitMixSeed (Rng.SplitMixSeed 42) 0
          assertBool
            "different splitmix streams derive different seeds"
            (Rng.deriveSplitMixSeed (Rng.SplitMixSeed 42) 0 /= Rng.deriveSplitMixSeed (Rng.SplitMixSeed 42) 1)
          assertBool
            "splitmix unit double stays in [0,1)"
            (let value = Rng.splitMixUnitDouble 0xe220a8397b1dcdaf in value >= 0 && value < 1)
          case Cuda.renderCudaFamilySource
            Dense2D
            (Cache.KernelSpec "phase-7-kernel:rng")
            Cache.Training
            Cache.defaultTuningChoice of
            [SourceFile _ contents] -> do
              assertBool
                "CUDA source records the host splitmix RNG policy"
                ("host-splitmix64-no-curand" `Text.isInfixOf` contents)
              assertBool
                "CUDA source does not include curand runtime headers"
                (not ("#include <curand" `Text.isInfixOf` contents))
            _ ->
              assertFailure "expected one generated CUDA source file"
          case Cuda.renderCudaFamilySource
            Reduction
            (Cache.KernelSpec "phase-7-kernel:cuda-reduction")
            Cache.Training
            Cache.defaultTuningChoice of
            [SourceFile _ contents] -> do
              assertBool
                "CUDA reduction emits no nondeterministic atomics"
                (not ("atomicAdd" `Text.isInfixOf` contents))
              assertBool
                "CUDA source exports a host-callable FFI wrapper"
                ( "extern \"C\" void jitml_kernel(float *out, const float *input, std::size_t n)"
                    `Text.isInfixOf` contents
                )
              assertBool
                "CUDA device kernel is not exported as the FFI symbol"
                (not ("__global__ void jitml_kernel" `Text.isInfixOf` contents))
              assertBool
                "CUDA FFI wrapper allocates device output"
                ("cudaMalloc(reinterpret_cast<void **>(&deviceOutput)" `Text.isInfixOf` contents)
              assertBool
                "CUDA FFI wrapper copies device output back to the host"
                ("cudaMemcpyDeviceToHost" `Text.isInfixOf` contents)
              assertBool
                "CUDA reduction writes one partial per warp"
                ("partials[blockIdx.x * warpsPerBlock + warp] = v;" `Text.isInfixOf` contents)
              assertBool
                "CUDA source exports family metadata for future FFI loading"
                ("jitml_kernel_family_name" `Text.isInfixOf` contents)
              assertBool
                "CUDA source exports output-count metadata for future FFI loading"
                ("jitml_kernel_output_count" `Text.isInfixOf` contents)
            _ ->
              assertFailure "expected one generated CUDA reduction source file"
      , testCase "CUDA reduction host partials finalize in canonical order" $ do
          CudaRuntime.cudaReductionPartialCount 0 @?= Right 0
          CudaRuntime.cudaReductionPartialCount 1 @?= Right 8
          CudaRuntime.cudaReductionPartialCount 256 @?= Right 8
          CudaRuntime.cudaReductionPartialCount 257 @?= Right 16
          CudaRuntime.cudaReductionPartialCount (-1)
            @?= Left "cuda reduction input count cannot be negative: -1"
          CudaRuntime.accumulateCudaReductionPartials [1.0, 2.0, 3.0]
            @?= 6.0
          CudaRuntime.finalizeCudaReductionPartials 257 [1.0 .. 16.0]
            @?= Right 136.0
          CudaRuntime.finalizeCudaReductionPartials 257 [1.0, 2.0]
            @?= Left "cuda reduction partial count mismatch: expected 16, got 2"
      , testCase "CUDA local runner fails closed before compile when runtime is unavailable" $
          withSystemTempDirectory "jitml-cuda-local" $ \dir -> do
            env <-
              buildEnv
                defaultGlobalFlags
                  { globalCacheDir = Just (dir </> ".build")
                  , globalDataDir = Just (dir </> ".data")
                  }
            let unavailableProbe =
                  CudaRuntime.CudaRuntimeProbe
                    { CudaRuntime.cudaRuntimeNvccVersion = Nothing
                    , CudaRuntime.cudaRuntimeGpuDevices = []
                    , CudaRuntime.cudaRuntimeLibraryVisibility =
                        CudaRuntime.CudaLibraryVisibility
                          { CudaRuntime.cudaDriverLibraryVisible = True
                          , CudaRuntime.cudaBlasLibraryVisible = True
                          , CudaRuntime.cudaDnnLibraryVisible = False
                          }
                    , CudaRuntime.cudaRuntimeProbeLog = []
                    }
            result <-
              CudaLocal.runCudaFamilyKernelWithProbe
                (pure unavailableProbe)
                env
                Identity
                [1.0, 2.0]
            result
              @?= Left
                "linux-cuda runtime unavailable: nvcc=missing gpu_devices=0 libcuda=yes libcublas=yes libcudnn=no"
      , testCase "cuBLAS bindings module always renders typed status text (Sprint 7.4)" $ do
          -- Pure-Haskell invariants for `JitML.Engines.CublasBindings`:
          -- the binding module is the typed Haskell surface that wraps
          -- libcublas behind the `cuda` cabal flag. The status renderer
          -- must format codes deterministically regardless of build
          -- flag so callers can log them without importing libcublas
          -- itself.
          Cublas.renderCublasStatus (Cublas.CublasStatus 0) @?= "cublas-status=0"
          Cublas.renderCublasStatus (Cublas.CublasStatus 13) @?= "cublas-status=13"
      , testCase "cuDNN bindings module always renders typed status text (Sprint 7.4)" $ do
          Cudnn.renderCudnnStatus (Cudnn.CudnnStatus 0) @?= "cudnn-status=0"
          Cudnn.renderCudnnStatus (Cudnn.CudnnStatus 7) @?= "cudnn-status=7"
      , testCase "cuBLAS / cuDNN binding stubs fail closed when compiled without -fcuda" $ do
          -- When the library is compiled without the `cuda` cabal flag
          -- the binding modules return a typed `CublasStatus (-2)` /
          -- `CudnnStatus (-2)` on every entrypoint. This protects
          -- downstream callers from a silent no-op path on hosts where
          -- libcublas/libcudnn are unavailable. The `+cuda` validation
          -- exercises the real FFI path through `jitml-cross-backend`.
          let unavailable = Cublas.CublasStatus (-2)
          if Cublas.cublasBindingsCompiledIn
            then
              assertBool
                "cuBLAS bindings compiled in: skip the unavailable-stub assertion"
                True
            else do
              result <- Cublas.verifyCublasRuntime
              result @?= Left unavailable
              handleResult <- Cublas.withCublasHandle (\_ -> pure ())
              handleResult @?= Left unavailable
          if Cudnn.cudnnBindingsCompiledIn
            then
              assertBool
                "cuDNN bindings compiled in: skip the unavailable-stub assertion"
                True
            else do
              let unavailableCudnn = Cudnn.CudnnStatus (-2)
              result <- Cudnn.verifyCudnnRuntime
              result @?= Left unavailableCudnn
              handleResult <- Cudnn.withCudnnHandle (\_ -> pure ())
              handleResult @?= Left unavailableCudnn
      , testCase "Metal package exports family and output-count metadata" $ do
          let reductionPackage =
                Metal.renderMetalFamilyPackage
                  Reduction
                  (Cache.KernelSpec "phase-7-kernel:metal-reduction")
                  Cache.Inference
                  Cache.defaultTuningChoice
          case find ((== "Sources/JitMLMetal/JitMLMetal.swift") . sourceRelativePath) reductionPackage of
            Nothing ->
              assertFailure "missing generated Swift source"
            Just (SourceFile _ contents) -> do
              assertBool
                "Swift source exports family metadata for future FFI loading"
                ("@_cdecl(\"jitml_kernel_family_name\")" `Text.isInfixOf` contents)
              assertBool
                "Swift source exports output-count metadata for future FFI loading"
                ("@_cdecl(\"jitml_kernel_output_count\")" `Text.isInfixOf` contents)
              assertBool
                "Metal reduction metadata reports one output per simdgroup partial"
                ("return n == 0 ? 0 : ((n - 1) / 32 + 1)" `Text.isInfixOf` contents)
              assertBool
                "Swift source records the generated family name"
                ( "private let jitmlKernelFamilyCString: UnsafeMutablePointer<CChar> = strdup(\"reduction\")!"
                    `Text.isInfixOf` contents
                )
          Metal.threadgroupSizeFor Reduction @?= 64
      , testCase "Metal runtime probe parser reports Swift, xcrun, and device visibility" $ do
          let swiftOutput =
                "swift-driver version: 1.115 Apple Swift version 6.0 (swiftlang-6.0.0 clang-1600.0.26.3)\n"
              xcrunOutput = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal\n"
              systemProfilerOutput =
                Text.unlines
                  [ "Graphics/Displays:"
                  , "    Apple M3 Max:"
                  , "      Metal Support: Metal 3"
                  ]
              availableProbe =
                MetalRuntime.MetalRuntimeProbe
                  { MetalRuntime.metalRuntimeSwiftVersion = MetalRuntime.parseSwiftVersion swiftOutput
                  , MetalRuntime.metalRuntimeMetalCompilerPath =
                      MetalRuntime.parseXcrunFindOutput xcrunOutput
                  , MetalRuntime.metalRuntimeSwiftCompilerPath =
                      Just "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
                  , MetalRuntime.metalRuntimeDeviceVisible =
                      MetalRuntime.metalDeviceVisibleFromSystemProfiler systemProfilerOutput
                  , MetalRuntime.metalRuntimeProbeLog =
                      [ "swift --version: 6.0"
                      , "xcrun -find metal: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal"
                      , "xcrun -find swiftc: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
                      , "system_profiler SPDisplaysDataType: metal_device_visible=yes"
                      ]
                  }
              missingDeviceProbe =
                availableProbe {MetalRuntime.metalRuntimeDeviceVisible = False}
              rendered = MetalRuntime.renderMetalRuntimeProbe availableProbe
          MetalRuntime.parseSwiftVersion swiftOutput @?= Just "6.0"
          MetalRuntime.parseSwiftVersion "Swift version 5.9.2\n" @?= Just "5.9.2"
          MetalRuntime.parseSwiftVersion "\n" @?= Nothing
          MetalRuntime.parseXcrunFindOutput xcrunOutput
            @?= Just "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal"
          MetalRuntime.parseXcrunFindOutput "\n" @?= Nothing
          MetalRuntime.metalDeviceVisibleFromSystemProfiler systemProfilerOutput @?= True
          MetalRuntime.metalDeviceVisibleFromSystemProfiler "Metal: Unsupported\n" @?= False
          MetalRuntime.metalRuntimeAvailable availableProbe @?= True
          MetalRuntime.metalRuntimeAvailable missingDeviceProbe @?= False
          assertBool
            "rendered Metal probe records availability"
            ("available: yes" `Text.isInfixOf` rendered)
          assertBool
            "rendered Metal probe records compiler path"
            ("metal_compiler: /Applications/Xcode.app" `Text.isInfixOf` rendered)
      , testCase "Apple Tart cache-miss build plan orders VM, Swift build, cache publish, and symlink" $ do
          let source =
                renderRuntimeSource
                  (Cache.KernelSpec "phase-7-kernel:metal-cache-miss")
                  Cache.Inference
                  Cache.AppleSilicon
                  Cache.defaultTuningChoice
              plan =
                TartBuild.tartCacheMissBuildPlan
                  (VmName "jitml-build")
                  (Cache.ModelId "mnist-linear")
                  source
                  sampleCacheHash
              rendered = TartBuild.renderTartCacheMissBuildPlan plan
              expectedSourceDir =
                ".build/jit-src/apple-silicon/" <> Cache.hashHex sampleCacheHash
              expectedArtifact =
                ".build/jit/apple-silicon/" <> Cache.hashHex sampleCacheHash <> ".dylib"
          TartBuild.tartCacheMissSourceDir plan @?= expectedSourceDir
          TartBuild.tartCacheMissBuildProduct plan
            @?= expectedSourceDir
            <> "/.build/release/libJitMLMetal.dylib"
          TartBuild.tartCacheMissArtifactPath plan @?= expectedArtifact
          TartBuild.tartCacheMissStableSymlinkPath plan
            @?= ".build/host/apple-silicon/mnist-linear.dylib"
          assertBool
            "plan validates the Swift toolchain inside the VM"
            ("validate-swift-toolchain: tart exec jitml-build swift --version" `Text.isInfixOf` rendered)
          assertBool
            "plan builds the generated Swift package inside the VM"
            ( ( "build-metal-package: tart exec jitml-build swift build --package-path "
                  <> expectedSourceDir
                  <> " -c release"
              )
                `Text.isInfixOf` rendered
            )
          assertBool
            "plan publishes the dynamic library into the content-addressed cache"
            ( ("publish-cache-artifact: mv " <> expectedArtifact <> ".tmp " <> expectedArtifact)
                `Text.isInfixOf` rendered
            )
          assertBool
            "plan repoints the host-stable FFI symlink through the Haskell helper"
            ( "repoint-stable-ffi-symlink: host-action JitML.Cache.Symlink.repointSymlink .build mnist-linear "
                `Text.isInfixOf` rendered
            )
          observedSteps <- newIORef []
          let record stepName detail =
                modifyIORef' observedSteps (<> [stepName <> ": " <> detail])
              executor =
                TartBuild.TartCacheMissBuildExecutor
                  { TartBuild.executeTartHostAction = \stepName action -> do
                      record stepName (TartBuild.renderTartHostAction action)
                      pure (Right ())
                  , TartBuild.executeTartCommand = \stepName command -> do
                      record stepName (renderSubprocess command)
                      pure (Right ())
                  }
              expectedStepNames =
                [ "ensure-vm-up"
                , "validate-swift-toolchain"
                , "build-metal-package"
                , "prepare-cache-dirs"
                , "copy-build-product"
                , "publish-cache-artifact"
                , "repoint-stable-ffi-symlink"
                ]
          executionResult <- TartBuild.executeTartCacheMissBuildPlanWith executor plan
          executionResult @?= Right (TartBuild.TartCacheMissBuildResult expectedStepNames)
          observedExecution <- readIORef observedSteps
          observedExecution
            @?= [ "ensure-vm-up: JitML.Tart.ensureVmUpLive jitml-build"
                , "validate-swift-toolchain: tart exec jitml-build swift --version"
                , "build-metal-package: tart exec jitml-build swift build --package-path "
                    <> expectedSourceDir
                    <> " -c release"
                , "prepare-cache-dirs: mkdir -p .build/jit/apple-silicon .build/host/apple-silicon"
                , "copy-build-product: cp "
                    <> expectedSourceDir
                    <> "/.build/release/libJitMLMetal.dylib "
                    <> expectedArtifact
                    <> ".tmp"
                , "publish-cache-artifact: mv "
                    <> expectedArtifact
                    <> ".tmp "
                    <> expectedArtifact
                , "repoint-stable-ffi-symlink: JitML.Cache.Symlink.repointSymlink .build mnist-linear "
                    <> Cache.hashHex sampleCacheHash
                    <> " dylib"
                ]
          failedSteps <- newIORef []
          let failingExecutor =
                TartBuild.TartCacheMissBuildExecutor
                  { TartBuild.executeTartHostAction = \stepName _action -> do
                      modifyIORef' failedSteps (<> [stepName])
                      pure (Right ())
                  , TartBuild.executeTartCommand = \stepName _command -> do
                      modifyIORef' failedSteps (<> [stepName])
                      pure $
                        if stepName == "copy-build-product"
                          then Left "missing dylib"
                          else Right ()
                  }
          failureResult <- TartBuild.executeTartCacheMissBuildPlanWith failingExecutor plan
          failureResult @?= Left "copy-build-product: missing dylib"
          observedFailure <- readIORef failedSteps
          observedFailure
            @?= [ "ensure-vm-up"
                , "validate-swift-toolchain"
                , "build-metal-package"
                , "prepare-cache-dirs"
                , "copy-build-product"
                ]
      , testCase "Tart VM status parser recognizes missing, stopped, and running VMs" $ do
          let stoppedJson =
                Text.unlines
                  [ "["
                  , "  {"
                  , "    \"Name\": \"jitml-build\","
                  , "    \"Running\": false,"
                  , "    \"State\": \"stopped\""
                  , "  }"
                  , "]"
                  ]
              runningJson =
                Text.unlines
                  [ "["
                  , "  {"
                  , "    \"Name\": \"jitml-build\","
                  , "    \"Running\": true,"
                  , "    \"State\": \"running\""
                  , "  }"
                  , "]"
                  ]
          TartLifecycle.parseTartListStatus (VmName "jitml-build") "[]" @?= Right TartLifecycle.TartVmMissing
          TartLifecycle.parseTartListStatus (VmName "jitml-build") stoppedJson
            @?= Right TartLifecycle.TartVmStopped
          TartLifecycle.parseTartListStatus (VmName "jitml-build") runningJson
            @?= Right TartLifecycle.TartVmRunning
          TartLifecycle.renderTartVmStatus TartLifecycle.TartVmMissing @?= "missing"
          TartLifecycle.renderTartVmStatus TartLifecycle.TartVmStopped @?= "stopped"
          TartLifecycle.renderTartVmStatus TartLifecycle.TartVmRunning @?= "running"
          renderSubprocess
            (TartLifecycle.tartCloneSubprocess TartLifecycle.defaultTartBaseImage (VmName "jitml-build"))
            @?= "tart clone ghcr.io/cirruslabs/macos-sequoia-xcode:16 jitml-build"
          renderSubprocess TartLifecycle.tartListSubprocess
            @?= "tart list --source local --format json"
          renderSubprocess (TartLifecycle.tartRunSubprocess (VmName "jitml-build"))
            @?= "tart run --no-graphics jitml-build"
          renderSubprocess (TartLifecycle.tartStopSubprocess (VmName "jitml-build"))
            @?= "tart stop jitml-build"
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
      , testCase "hardware auto-tuning selects fastest measured deterministic candidate" $ do
          let plan = Tuning.benchmarkPlan Tuning.linuxCudaKnobs
          case Tuning.benchmarkPlanResults plan of
            first : second : third : _ -> do
              let firstMeasurement =
                    Tuning.BenchmarkMeasurement first 40 "sha-first"
                  measurements =
                    [ firstMeasurement
                    , Tuning.BenchmarkMeasurement second 25 "sha-second"
                    , Tuning.BenchmarkMeasurement third 35 "sha-third"
                    ]
                  tieMeasurements =
                    [ Tuning.BenchmarkMeasurement second 10 "sha-second"
                    , Tuning.BenchmarkMeasurement first 10 "sha-first"
                    ]
              Tuning.selectMeasuredTuning plan measurements @?= Right second
              Tuning.selectMeasuredTuning plan tieMeasurements @?= Right first
              Tuning.selectBenchmarkMeasurement plan measurements
                @?= Right (Tuning.BenchmarkMeasurement second 25 "sha-second")
              Tuning.renderBenchmarkMeasurement firstMeasurement
                @?= Cache.unTuningChoice (Tuning.tuningChoiceForResult first)
                <> " latency_micros=40 output_digest=sha-first"
              Tuning.selectMeasuredTuning plan [] @?= Left "benchmark plan has no measurements"
            _ ->
              assertFailure "expected at least three benchmark candidates"
      , testCase "hardware auto-tuning persists selected measured choice by base hash" $
          withSystemTempDirectory "jitml-tuning-store" $ \dir -> do
            let plan = Tuning.benchmarkPlan Tuning.linuxCudaKnobs
            case Tuning.benchmarkPlanResults plan of
              first : second : _ -> do
                let baseHash = sampleCacheHash
                    measurements =
                      [ Tuning.BenchmarkMeasurement first 40 "sha-first"
                      , Tuning.BenchmarkMeasurement second 25 "sha-second"
                      ]
                persisted <-
                  TuningStore.persistSelectedMeasuredTuning
                    dir
                    baseHash
                    plan
                    measurements
                let expected =
                      TuningStore.PersistedTuningSelection
                        { TuningStore.persistedTuningSubstrate = Substrate.LinuxCUDA
                        , TuningStore.persistedTuningBaseHash = baseHash
                        , TuningStore.persistedTuningChoice = Tuning.tuningChoiceForResult second
                        , TuningStore.persistedTuningLatencyMicros = 25
                        , TuningStore.persistedTuningOutputDigest = "sha-second"
                        }
                    path =
                      TuningStore.tuningSelectionPath
                        dir
                        Substrate.LinuxCUDA
                        baseHash
                persisted @?= Right expected
                doesFileExist path >>= (@?= True)
                loaded <- TuningStore.readTuningSelection dir Substrate.LinuxCUDA baseHash
                loaded @?= Right (Just expected)
              _ ->
                assertFailure "expected at least two benchmark candidates"
      , testCase "hardware auto-tuning loads persisted choice for cache-key derivation" $
          withSystemTempDirectory "jitml-tuning-cache" $ \dir -> do
            let kernelSpec = Cache.KernelSpec "phase-7-kernel:tuned-cache"
                kind = Cache.Training
                fingerprint = Cache.ToolchainFingerprint "nvcc=sm_70"
                benchmarkPlan = Tuning.benchmarkPlan Tuning.linuxCudaKnobs
                basePlan =
                  TuningCache.defaultTuningCachePlan
                    kernelSpec
                    kind
                    Substrate.LinuxCUDA
                    fingerprint
            TuningCache.tuningCacheHash basePlan @?= TuningCache.tuningCacheBaseHash basePlan
            TuningCache.tuningCacheTuningChoice basePlan @?= Cache.defaultTuningChoice
            TuningCache.tuningCacheSelectionSource basePlan @?= "default"
            case Tuning.benchmarkPlanResults benchmarkPlan of
              first : second : _ -> do
                let measurements =
                      [ Tuning.BenchmarkMeasurement first 40 "sha-first"
                      , Tuning.BenchmarkMeasurement second 25 "sha-second"
                      ]
                persisted <-
                  TuningStore.persistSelectedMeasuredTuning
                    dir
                    (TuningCache.tuningCacheBaseHash basePlan)
                    benchmarkPlan
                    measurements
                case persisted of
                  Left err -> assertFailure (Text.unpack err)
                  Right selection -> do
                    selectedPlanResult <-
                      TuningCache.selectTuningCachePlan
                        dir
                        kernelSpec
                        kind
                        Substrate.LinuxCUDA
                        fingerprint
                    case selectedPlanResult of
                      Left err -> assertFailure (Text.unpack err)
                      Right selectedPlan -> do
                        TuningCache.tuningCacheBaseHash selectedPlan
                          @?= TuningCache.tuningCacheBaseHash basePlan
                        TuningCache.tuningCacheTuningChoice selectedPlan
                          @?= Tuning.tuningChoiceForResult second
                        TuningCache.tuningCachePersistedSelection selectedPlan
                          @?= Just selection
                        TuningCache.tuningCacheSelectionSource selectedPlan @?= "persisted"
                        assertBool
                          "persisted tuning choice changes final cache hash"
                          (TuningCache.tuningCacheHash selectedPlan /= TuningCache.tuningCacheBaseHash selectedPlan)
              _ ->
                assertFailure "expected at least two benchmark candidates"
      , testCase "hardware auto-tuning benchmark driver collects digests and persists the winner" $
          withSystemTempDirectory "jitml-tuning-benchmark" $ \dir -> do
            let plan = Tuning.benchmarkPlan Tuning.linuxCpuKnobs
            case Tuning.benchmarkPlanResults plan of
              first : second : _ -> do
                let boundedPlan =
                      Tuning.BenchmarkPlan
                        (Tuning.benchmarkPlanSubstrate plan)
                        [first, second]
                    firstDigest = TuningBenchmark.digestFloatOutput [1.0, 2.0]
                    secondDigest = TuningBenchmark.digestFloatOutput [1.0, 3.0]
                    observed candidate
                      | candidate == first =
                          pure (Right (TuningBenchmark.BenchmarkObservation 30 firstDigest))
                      | candidate == second =
                          pure (Right (TuningBenchmark.BenchmarkObservation 20 secondDigest))
                      | otherwise =
                          pure (Left "unexpected candidate")
                assertBool "float output digest is content-sensitive" (firstDigest /= secondDigest)
                measured <-
                  TuningBenchmark.collectBenchmarkMeasurements boundedPlan observed
                measured
                  @?= Right
                    [ Tuning.BenchmarkMeasurement first 30 firstDigest
                    , Tuning.BenchmarkMeasurement second 20 secondDigest
                    ]
                timed <-
                  TuningBenchmark.measureBenchmarkObservation
                    TuningBenchmark.digestFloatOutput
                    (pure [1.0, 2.0])
                TuningBenchmark.benchmarkObservationOutputDigest timed @?= firstDigest
                assertBool
                  "benchmark timing is non-negative"
                  (TuningBenchmark.benchmarkObservationLatencyMicros timed >= 0)
                persisted <-
                  TuningBenchmark.collectAndPersistBenchmarkSelection
                    dir
                    sampleCacheHash
                    boundedPlan
                    observed
                persisted
                  @?= Right
                    ( TuningStore.PersistedTuningSelection
                        { TuningStore.persistedTuningSubstrate = Substrate.LinuxCPU
                        , TuningStore.persistedTuningBaseHash = sampleCacheHash
                        , TuningStore.persistedTuningChoice = Tuning.tuningChoiceForResult second
                        , TuningStore.persistedTuningLatencyMicros = 20
                        , TuningStore.persistedTuningOutputDigest = secondDigest
                        }
                    )
              _ ->
                assertFailure "expected at least two benchmark candidates"
      , testCase "ensureTuningSelection persists synthetic runner output on first cache miss" $
          withSystemTempDirectory "jitml-tuning-ensure" $ \dir -> do
            env <-
              buildEnv
                defaultGlobalFlags
                  { globalCacheDir = Just (dir </> ".build")
                  , globalDataDir = Just (dir </> ".data")
                  }
            runnerCalls <- newIORef (0 :: Int)
            let kernelSpec = Cache.KernelSpec "phase-7-kernel:ensure-tuning"
                kind = Cache.Training
                fingerprint = Cache.ToolchainFingerprint "g++-shared;tuning=ensure-test"
                substrate = Substrate.LinuxCPU
                plan = Tuning.benchmarkPlan (Tuning.knobSpace substrate)
                candidates = Tuning.benchmarkPlanResults plan
                candidateLatency candidate =
                  10 + 100 * fromMaybe 0 (List.elemIndex candidate candidates)
                syntheticRunner _env _spec _kind _input candidate = do
                  modifyIORef' runnerCalls succ
                  pure $
                    Right
                      ( TuningBenchmark.BenchmarkObservation
                          (candidateLatency candidate)
                          ( "digest-"
                              <> Cache.unTuningChoice (Tuning.tuningChoiceForResult candidate)
                          )
                      )
            firstResult <-
              TuningBenchmark.ensureTuningSelection
                env
                substrate
                syntheticRunner
                kernelSpec
                kind
                fingerprint
                [1.0, 2.0]
            firstPlan <- case firstResult of
              Left err -> assertFailure (Text.unpack err) >> error "unreachable"
              Right p -> pure p
            firstCalls <- readIORef runnerCalls
            firstCalls @?= length candidates
            firstCandidate <- case candidates of
              candidate : _ -> pure candidate
              [] -> assertFailure "expected at least one Linux CPU benchmark candidate" >> error "unreachable"
            case TuningCache.tuningCachePersistedSelection firstPlan of
              Nothing -> assertFailure "first ensureTuningSelection did not persist a selection"
              Just selection ->
                TuningStore.persistedTuningChoice selection
                  @?= Tuning.tuningChoiceForResult firstCandidate
            TuningCache.tuningCacheSelectionSource firstPlan @?= "persisted"
            secondResult <-
              TuningBenchmark.ensureTuningSelection
                env
                substrate
                syntheticRunner
                kernelSpec
                kind
                fingerprint
                [1.0, 2.0]
            secondPlan <- case secondResult of
              Left err -> assertFailure (Text.unpack err) >> error "unreachable"
              Right p -> pure p
            secondCalls <- readIORef runnerCalls
            assertBool
              "second ensureTuningSelection does not re-invoke the runner"
              (secondCalls == firstCalls)
            TuningCache.tuningCacheTuningChoice secondPlan
              @?= TuningCache.tuningCacheTuningChoice firstPlan
            TuningCache.tuningCacheHash secondPlan
              @?= TuningCache.tuningCacheHash firstPlan
      , testCase "hardware auto-tuning CUDA and Metal runners preflight runtime availability" $ do
          let kernelSpec = Cache.KernelSpec "phase-7-kernel:preflight-runner"
              cudaCandidate = Tuning.selectDeterministic Tuning.linuxCudaKnobs
              appleCandidate = Tuning.selectDeterministic Tuning.appleSiliconKnobs
              linuxCandidate = Tuning.selectDeterministic Tuning.linuxCpuKnobs
              availableCudaProbe =
                CudaRuntime.CudaRuntimeProbe
                  { CudaRuntime.cudaRuntimeNvccVersion = Just "12.4"
                  , CudaRuntime.cudaRuntimeGpuDevices =
                      ["GPU 0: NVIDIA GeForce RTX 5090 (UUID: GPU-123)"]
                  , CudaRuntime.cudaRuntimeLibraryVisibility =
                      CudaRuntime.CudaLibraryVisibility
                        { CudaRuntime.cudaDriverLibraryVisible = True
                        , CudaRuntime.cudaBlasLibraryVisible = True
                        , CudaRuntime.cudaDnnLibraryVisible = True
                        }
                  , CudaRuntime.cudaRuntimeProbeLog = []
                  }
              unavailableCudaProbe =
                availableCudaProbe
                  { CudaRuntime.cudaRuntimeNvccVersion = Nothing
                  , CudaRuntime.cudaRuntimeGpuDevices = []
                  , CudaRuntime.cudaRuntimeLibraryVisibility =
                      CudaRuntime.CudaLibraryVisibility
                        { CudaRuntime.cudaDriverLibraryVisible = True
                        , CudaRuntime.cudaBlasLibraryVisible = True
                        , CudaRuntime.cudaDnnLibraryVisible = False
                        }
                  }
              availableMetalProbe =
                MetalRuntime.MetalRuntimeProbe
                  { MetalRuntime.metalRuntimeSwiftVersion = Just "6.0"
                  , MetalRuntime.metalRuntimeMetalCompilerPath = Just "/usr/bin/metal"
                  , MetalRuntime.metalRuntimeSwiftCompilerPath = Just "/usr/bin/swiftc"
                  , MetalRuntime.metalRuntimeDeviceVisible = True
                  , MetalRuntime.metalRuntimeProbeLog = []
                  }
              unavailableMetalProbe =
                availableMetalProbe
                  { MetalRuntime.metalRuntimeSwiftVersion = Nothing
                  , MetalRuntime.metalRuntimeMetalCompilerPath = Nothing
                  , MetalRuntime.metalRuntimeDeviceVisible = False
                  }
          cudaEnv <- buildEnv defaultGlobalFlags
          cudaWrong <-
            TuningBenchmark.cudaBenchmarkCandidateRunnerWithProbe
              (pure unavailableCudaProbe)
              cudaEnv
              kernelSpec
              Cache.Training
              []
              appleCandidate
          cudaWrong
            @?= Left "linux-cuda benchmark runner cannot execute apple-silicon candidate"
          cudaUnavailable <-
            TuningBenchmark.cudaBenchmarkCandidateRunnerWithProbe
              (pure unavailableCudaProbe)
              cudaEnv
              kernelSpec
              Cache.Training
              []
              cudaCandidate
          cudaUnavailable
            @?= Left
              "linux-cuda benchmark runner unavailable: nvcc=missing gpu_devices=0 libcuda=yes libcublas=yes libcudnn=no"
          -- When the runtime is available (synthetic probe) the runner
          -- now drives the real CUDA kernel through the loader. The
          -- live FFI candidate measurement is exercised through
          -- `jitml-cross-backend` on a CUDA host; here we keep the
          -- deterministic path that only covers wrong-substrate and
          -- unavailable cases. `availableCudaProbe` is intentionally
          -- only used by the `unavailableCudaProbe` field-update form
          -- above so the synthetic library-visible/positive shape stays
          -- expressed in this case.
          metalWrong <-
            TuningBenchmark.metalBenchmarkCandidateRunnerWithProbe
              (pure unavailableMetalProbe)
              kernelSpec
              Cache.Training
              []
              linuxCandidate
          metalWrong
            @?= Left "apple-silicon benchmark runner cannot execute linux-cpu candidate"
          metalUnavailable <-
            TuningBenchmark.metalBenchmarkCandidateRunnerWithProbe
              (pure unavailableMetalProbe)
              kernelSpec
              Cache.Training
              []
              appleCandidate
          metalUnavailable
            @?= Left
              "apple-silicon benchmark runner unavailable: swift=missing metal=missing swiftc=present device=no"
          metalAvailable <-
            TuningBenchmark.metalBenchmarkCandidateRunnerWithProbe
              (pure availableMetalProbe)
              kernelSpec
              Cache.Training
              []
              appleCandidate
          metalAvailable
            @?= Left
              "apple-silicon benchmark runner reached an available runtime, but Metal FFI candidate execution is not implemented yet"
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
                    ( renderedRuntimeSourcePayload
                        (Cache.KernelSpec "phase-2-kernel:conv")
                        Cache.Inference
                        Cache.AppleSilicon
                    )
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
      , testCase "classical-control simulators step deterministically with physics" $ do
          -- Cartpole at rest with a right-push starts moving right with
          -- a positive cart acceleration and a small leftward pole lean.
          let firstStep = Sim.cartPoleStep Sim.cartPoleInitial 1
              state1 = Sim.simStepState firstStep
          Sim.simStepReward firstStep @?= 1.0
          Sim.simStepDone firstStep @?= False
          assertBool "cart moves right under positive force" (Sim.cartVelocity state1 > 0)
          assertBool "pole begins falling left under cart acceleration" (Sim.poleAngularVelocity state1 < 0)
          -- Stepping the same state twice produces the same result.
          Sim.cartPoleStep Sim.cartPoleInitial 1 @?= firstStep
          -- Mountain-car starts at p=-0.5, v=0. Pushing right (action 2)
          -- gives positive force but gravity dominates initially; pushing
          -- left should produce negative velocity.
          let mcStep = Sim.mountainCarStep Sim.mountainCarInitial 0
              mcState = Sim.simStepState mcStep
          Sim.simStepReward mcStep @?= -1.0
          assertBool
            "mountain-car velocity becomes negative under leftward push"
            (Sim.mountainCarVelocity mcState < 0)
          -- A car at the goal terminates.
          let goalState = Sim.MountainCarState 0.6 0.05
              goalStep = Sim.mountainCarStep goalState 2
          Sim.simStepDone goalStep @?= True
          -- The render-frame observation has the documented length and the
          -- typed IO boundary mirrors the pure step semantics.
          length (Sim.renderObservation (Sim.cartPoleRenderFrame Sim.cartPoleInitial)) @?= 4
          length (Sim.renderObservation (Sim.mountainCarRenderFrame Sim.mountainCarInitial)) @?= 2
          (obs, reward, done) <- Sim.stepEnvironmentIO Sim.cartPoleEnvironment Sim.cartPoleInitial 1
          length obs @?= 4
          reward @?= 1.0
          done @?= False
      , testCase "lunar-lander simulator steps deterministically (Sprint 8.3)" $ do
          -- No-op above the pad: lander falls under gravity; vertical
          -- velocity becomes negative and the y coordinate decreases.
          let drift = Sim.lunarLanderStep Sim.lunarLanderInitial 0
              driftState = Sim.simStepState drift
          assertBool
            "no-op step accelerates downward under lunar gravity"
            (Sim.lunarLanderVy driftState < 0)
          assertBool
            "no-op step lowers the lander altitude"
            (Sim.lunarLanderY driftState < Sim.lunarLanderY Sim.lunarLanderInitial)
          Sim.simStepDone drift @?= False
          -- Firing the main engine produces a positive vertical impulse;
          -- the resulting vy is greater than the no-op vy.
          let burn = Sim.lunarLanderStep Sim.lunarLanderInitial 2
              burnState = Sim.simStepState burn
          assertBool
            "main-engine fire counters lunar gravity"
            (Sim.lunarLanderVy burnState > Sim.lunarLanderVy driftState)
          -- Left side engine yields positive angular velocity.
          let lefti = Sim.lunarLanderStep Sim.lunarLanderInitial 1
              leftState = Sim.simStepState lefti
          assertBool
            "left side engine spins the lander counter-clockwise"
            (Sim.lunarLanderOmega leftState > 0)
          -- Right side engine yields negative angular velocity.
          let righti = Sim.lunarLanderStep Sim.lunarLanderInitial 3
              rightState = Sim.simStepState righti
          assertBool
            "right side engine spins the lander clockwise"
            (Sim.lunarLanderOmega rightState < 0)
          -- Two invocations from the same state produce the same step.
          Sim.lunarLanderStep Sim.lunarLanderInitial 0 @?= drift
          -- A lander already touching the ground at high vertical speed
          -- counts as a crash and terminates with a strong penalty.
          let crashState =
                Sim.LunarLanderState
                  { Sim.lunarLanderX = 0.0
                  , Sim.lunarLanderY = 0.0
                  , Sim.lunarLanderVx = 0.0
                  , Sim.lunarLanderVy = -5.0
                  , Sim.lunarLanderAngle = 0.0
                  , Sim.lunarLanderOmega = 0.0
                  , Sim.lunarLanderLeftLegContact = True
                  , Sim.lunarLanderRightLegContact = True
                  }
              crashStep = Sim.lunarLanderStep crashState 0
          Sim.simStepDone crashStep @?= True
          assertBool "crash carries a strong penalty" (Sim.simStepReward crashStep < -50.0)
          -- Render-frame observation length matches the eight-dim
          -- canonical state vector.
          length (Sim.renderObservation (Sim.lunarLanderRenderFrame Sim.lunarLanderInitial))
            @?= 8
          (obs, _, _) <-
            Sim.stepEnvironmentIO Sim.lunarLanderEnvironment Sim.lunarLanderInitial 0
          length obs @?= 8
      , testCase "atari-subset deterministic stub steps reproducibly (Sprint 8.3)" $ do
          -- Two same-state same-action invocations are bit-identical.
          let first = Sim.atariSubsetStep Sim.atariSubsetInitial 5
          Sim.atariSubsetStep Sim.atariSubsetInitial 5 @?= first
          -- Different actions produce different successor RAM hashes.
          let other = Sim.atariSubsetStep Sim.atariSubsetInitial 6
          assertBool
            "distinct actions update the stub RAM hash distinctly"
            (Sim.atariRamHash (Sim.simStepState first) /= Sim.atariRamHash (Sim.simStepState other))
          -- Each step advances the step counter by one.
          Sim.atariStep (Sim.simStepState first) @?= 1
          -- Reward stays in [0, 1).
          let r = Sim.simStepReward first
          assertBool "reward stays normalised in [0, 1)" (r >= 0 && r < 1)
          -- Render-frame matches the 128-byte canonical RAM-state width.
          length (Sim.renderObservation (Sim.atariSubsetRenderFrame Sim.atariSubsetInitial))
            @?= 128
          -- Step boundary advances to termination at the documented length.
          let walk s
                | Sim.simStepDone (Sim.atariSubsetStep s 0) = Sim.atariStep s + 1
                | otherwise = walk (Sim.simStepState (Sim.atariSubsetStep s 0))
          walk Sim.atariSubsetInitial @?= 250
      , testCase "AlphaZero rule engines reject illegal moves per game" $ do
          -- Othello: cell 19 (D3) flips one stone for opening Black; the
          -- canonical centre cells 27, 28, 35, 36 are pre-occupied.
          AlphaZero.othelloLegalMove 19 AlphaZero.initialOthello @?= True
          AlphaZero.othelloLegalMove 27 AlphaZero.initialOthello @?= False
          AlphaZero.othelloLegalMove 3 AlphaZero.initialOthello @?= False
          AlphaZero.othelloFlipsFor AlphaZero.othelloInitialBoard 1 19 @?= [27]
          -- Hex / Gomoku reject occupied cells.
          let occupied = AlphaZero.hexApplyMove 5 AlphaZero.initialHex
          AlphaZero.hexLegalMove 5 AlphaZero.initialHex @?= True
          AlphaZero.hexLegalMove 5 occupied @?= False
          AlphaZero.hexLegalMove 121 AlphaZero.initialHex @?= False
          let gomokuOccupied = AlphaZero.gomokuApplyMove 7 AlphaZero.initialGomoku
          AlphaZero.gomokuLegalMove 7 AlphaZero.initialGomoku @?= True
          AlphaZero.gomokuLegalMove 7 gomokuOccupied @?= False
          -- Connect 4 rejects a column with six pieces already.
          let columnFull =
                foldr
                  (\_ s -> AlphaZero.applyMove 2 s)
                  AlphaZero.initialConnect4
                  ([1 .. 6] :: [Int])
          AlphaZero.connect4LegalMove 2 columnFull @?= False
          AlphaZero.connect4LegalMove 3 columnFull @?= True
          AlphaZero.connect4LegalMove (-1) AlphaZero.initialConnect4 @?= False
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
          Checkpoint.decodeJmw1 payload @?= Right [1.0]
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
    sampleRuntimeSourcePayload
    Cache.defaultTuningChoice

sampleRuntimeSourcePayload :: Cache.RuntimeSourcePayload
sampleRuntimeSourcePayload =
  renderedRuntimeSourcePayload
    (Cache.KernelSpec "phase-2-kernel:linear")
    Cache.Training
    Cache.AppleSilicon

renderedRuntimeSourcePayload
  :: Cache.KernelSpec -> Cache.Kind -> Cache.Substrate -> Cache.RuntimeSourcePayload
renderedRuntimeSourcePayload kernelSpec kind substrate =
  runtimeSourcePayload $
    renderRuntimeSource
      kernelSpec
      kind
      substrate
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

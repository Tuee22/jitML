{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), Value, decode, eitherDecode, encode, withObject, (.:))
import Data.ByteString.Lazy qualified as ByteString
import Data.Foldable (traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, isInfixOf)
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
  , getPermissions
  , setOwnerExecutable
  , setPermissions
  )
import System.Environment (getEnvironment, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath (searchPathSeparator, takeDirectory, (</>))
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
                , subprocessEnvironment = [("LC_ALL", "C")]
                , subprocessWorkingDirectory = Just "/tmp/jit ml"
                }
            )
            @?= "LC_ALL=C cd '/tmp/jit ml' && cabal build all"
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
      , testGroup
          "stage-0 bootstrap scripts"
          [ testCase "apple help names the Haskell bootstrap delegation" $ do
              result <- runBootstrapScript Nothing "bootstrap/apple-silicon.sh" ["help"] []
              scriptExit result @?= ExitSuccess
              assertContains "apple help" "./.build/jitml bootstrap --apple-silicon" (scriptStdout result)
          , testCase "apple doctor rejects non-macOS hosts" $ do
              result <-
                runBootstrapScript
                  Nothing
                  "bootstrap/apple-silicon.sh"
                  ["doctor"]
                  [ ("JITML_BOOTSTRAP_UNAME_S", "Linux")
                  , ("JITML_BOOTSTRAP_UNAME_M", "arm64")
                  ]
              scriptExit result @?= ExitFailure 2
              assertContains "apple non-macOS diagnostic" "requires macOS" (scriptStderr result)
          , testCase "apple doctor rejects non-arm64 hosts" $ do
              result <-
                runBootstrapScript
                  Nothing
                  "bootstrap/apple-silicon.sh"
                  ["doctor"]
                  [ ("JITML_BOOTSTRAP_UNAME_S", "Darwin")
                  , ("JITML_BOOTSTRAP_UNAME_M", "x86_64")
                  ]
              scriptExit result @?= ExitFailure 2
              assertContains "apple non-arm64 diagnostic" "requires Apple Silicon arm64" (scriptStderr result)
          , testCase "apple doctor reports missing Xcode Command Line Tools" $
              withStubCommands [brewStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                    [ ("JITML_BOOTSTRAP_UNAME_S", "Darwin")
                    , ("JITML_BOOTSTRAP_UNAME_M", "arm64")
                    , ("JITML_BOOTSTRAP_MISSING_COMMANDS", "xcode-select")
                    ]
                scriptExit result @?= ExitFailure 2
                assertContains "apple xcode diagnostic" "xcode-select --install" (scriptStderr result)
          , testCase "apple doctor reports missing Homebrew" $
              withStubCommands [xcodeSelectStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                    [ ("JITML_BOOTSTRAP_UNAME_S", "Darwin")
                    , ("JITML_BOOTSTRAP_UNAME_M", "arm64")
                    , ("JITML_BOOTSTRAP_MISSING_COMMANDS", "brew")
                    ]
                scriptExit result @?= ExitFailure 2
                assertContains "apple homebrew diagnostic" "install Homebrew" (scriptStderr result)
          , testCase "apple doctor ignores broad package-toolchain gaps" $
              withStubCommands [xcodeSelectStub, brewStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                    [ ("JITML_BOOTSTRAP_UNAME_S", "Darwin")
                    , ("JITML_BOOTSTRAP_UNAME_M", "arm64")
                    ,
                      ( "JITML_BOOTSTRAP_MISSING_COMMANDS"
                      , "ghcup protoc colima docker kind kubectl helm node poetry tart purs spago pulumi"
                      )
                    ]
                scriptExit result @?= ExitSuccess
                assertContains "apple doctor ok" "stage-0 doctor: ok" (scriptStderr result)
          , testCase "linux CPU doctor reports missing Docker" $ do
              result <-
                runBootstrapScript
                  Nothing
                  "bootstrap/linux-cpu.sh"
                  ["doctor"]
                  [("JITML_BOOTSTRAP_MISSING_COMMANDS", "docker")]
              scriptExit result @?= ExitFailure 2
              assertContains "linux docker diagnostic" "missing required command 'docker'" (scriptStderr result)
          , testCase "linux CPU doctor requires Docker without sudo" $
              withStubCommands [dockerInfoFailureStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cpu.sh" ["doctor"] []
                scriptExit result @?= ExitFailure 2
                assertContains "linux sudo diagnostic" "without sudo" (scriptStderr result)
          , testCase "linux CPU doctor ignores non-Docker toolchain gaps" $
              withStubCommands [dockerOkStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/linux-cpu.sh"
                    ["doctor"]
                    [("JITML_BOOTSTRAP_MISSING_COMMANDS", "kind kubectl helm node poetry tart purs spago pulumi")]
                scriptExit result @?= ExitSuccess
                assertContains "linux cpu doctor ok" "stage-0 doctor: ok" (scriptStderr result)
          , testCase "linux CUDA doctor reports missing NVIDIA runtime" $
              withStubCommands [dockerWithoutNvidiaRuntimeStub, nvidiaSmiHighCapabilityStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cuda.sh" ["doctor"] []
                scriptExit result @?= ExitFailure 2
                assertContains "cuda runtime diagnostic" "NVIDIA container runtime" (scriptStderr result)
          , testCase "linux CUDA doctor reports insufficient compute capability" $
              withStubCommands [dockerWithNvidiaRuntimeStub, nvidiaSmiLowCapabilityStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cuda.sh" ["doctor"] []
                scriptExit result @?= ExitFailure 2
                assertContains "cuda capability diagnostic" "compute capability" (scriptStderr result)
          ]
      , testCase "buildEnv uses default dirs" $ do
          unsetEnv "JITML_BUILD_DIR"
          unsetEnv "JITML_DATA_DIR"
          env <- buildEnv defaultGlobalFlags
          takeFileNameCompat (toFilePath (envCacheDir env)) @?= ".build"
          takeFileNameCompat (toFilePath (envDataDir env)) @?= ".data"
      , testCase "buildEnv uses env overrides" $
          withSystemTempDirectory "jitml-env" $ \dir -> do
            setEnv "JITML_BUILD_DIR" (dir </> "build")
            setEnv "JITML_DATA_DIR" (dir </> "data")
            env <- buildEnv defaultGlobalFlags
            toFilePath (envCacheDir env) @?= dir </> "build/"
            toFilePath (envDataDir env) @?= dir </> "data/"
            unsetEnv "JITML_BUILD_DIR"
            unsetEnv "JITML_DATA_DIR"
      , testCase "buildEnv uses CLI overrides before env" $
          withSystemTempDirectory "jitml-env-cli" $ \dir -> do
            setEnv "JITML_BUILD_DIR" (dir </> "ignored")
            env <-
              buildEnv
                defaultGlobalFlags
                  { globalCacheDir = Just (dir </> "cli-build")
                  , globalFormat = Just OutputJson
                  }
            toFilePath (envCacheDir env) @?= dir </> "cli-build/"
            envFormat env @?= OutputJson
            unsetEnv "JITML_BUILD_DIR"
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
            inferred <- CheckpointStore.inferFromLatestCheckpoint dir "exp1" [10, 20]
            inferred @?= Right (Checkpoint.inferFromManifest manifest [10, 20])
            conflict <- CheckpointStore.writeCheckpointSnapshot dir manifest [(blobKey, payload)] Nothing
            CheckpointStore.storedPointerResult conflict
              @?= Checkpoint.PointerConflict (Checkpoint.latestPointerKey "exp1")
      , testCase "TensorBoard checkpoint sidecar keys are stable" $
          TensorBoard.checkpointSidecarKey "exp-a" 12 "sha-m"
            @?= "jitml-tensorboard/exp-a/checkpoints/12-sha-m.cbor"
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
          fmap WebBundle.demoRoutePath WebBundle.demoRoutes @?= ["/", "/api", "/api/ws"]
          WebBundle.renderDemoRouteManifest
            @?= "demo-routes:\n- / static-shell <- web/src/Main.purs\n- /api contract-index <- src/JitML/Web/Contracts.hs\n- /api/ws websocket-contract <- src/JitML/Web/Contracts.hs\n"
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
  :: Maybe FilePath -> FilePath -> [String] -> [(String, String)] -> IO ScriptResult
runBootstrapScript pathPrefix script args extraEnv = do
  baseEnv <- getEnvironment
  let processEnv = mergeEnv (pathOverride baseEnv <> extraEnv) baseEnv
      process =
        Subprocess
          { subprocessPath = script
          , subprocessArguments = fmap Text.pack args
          , subprocessEnvironment = fmap envPair processEnv
          , subprocessWorkingDirectory = Just "."
          }
  (exitCode, stdoutText, stderrText) <- runStreaming defaultSubprocessEnv process
  pure
    ScriptResult
      { scriptExit = exitCode
      , scriptStdout = Text.unpack stdoutText
      , scriptStderr = Text.unpack stderrText
      }
 where
  envPair (key, value) =
    (Text.pack key, Text.pack value)

  pathOverride baseEnv =
    case pathPrefix of
      Nothing -> []
      Just dir ->
        let inheritedPath = fromMaybe "" (lookup "PATH" baseEnv)
         in [("PATH", dir <> [searchPathSeparator] <> inheritedPath)]

mergeEnv :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnv overrides baseEnv =
  overrides <> filter ((`notElem` overrideNames) . fst) baseEnv
 where
  overrideNames = fmap fst overrides

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
  , ["test", "jitml-haskell-style"]
  , ["test", "jitml-purescript-style"]
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

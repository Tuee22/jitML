{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket_)
import Control.Monad qualified
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
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Data.Vector.Unboxed qualified
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
import JitML.Experiment.Overrides qualified as Overrides
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
import JitML.Numerics.Mlp qualified as Mlp
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
import JitML.Proto.Gc qualified as ProtoGc
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms qualified as RLAlgorithms
import JitML.RL.Algorithms.A2cLoss qualified as A2cLoss
import JitML.RL.Algorithms.ArsLoss qualified as ArsLoss
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.CrossQLoss qualified as CrossQLoss
import JitML.RL.Algorithms.DdpgLoss qualified as DdpgLoss
import JitML.RL.Algorithms.DqnLoss qualified as DqnLoss
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.MaskablePpoLoss qualified as MaskablePpoLoss
import JitML.RL.Algorithms.PpoLoss qualified as PpoLoss
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnLoss qualified as QrDqnLoss
import JitML.RL.Algorithms.QrDqnTrainer qualified as QrDqnTrainer
import JitML.RL.Algorithms.RecurrentPpoLoss qualified as RecurrentPpoLoss
import JitML.RL.Algorithms.SacLoss qualified as SacLoss
import JitML.RL.Algorithms.Td3Loss qualified as Td3Loss
import JitML.RL.Algorithms.TqcLoss qualified as TqcLoss
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.RL.ConvergenceThresholds qualified as ConvergenceThresholds
import JitML.RL.Environments qualified as RLEnvironments
import JitML.RL.Framework qualified as RLFramework
import JitML.RL.Schema (loadRlCatalogSchema, validateRlCatalogSchema)
import JitML.RL.Simulator qualified as Sim
import JitML.Routes qualified as Routes
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.WebSocket qualified as WS
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate qualified as Substrate
import JitML.Test.Report (substrateTestInvocations)
import JitML.Tune.Catalog qualified as Tune
import JitML.Web.AdminPortals qualified as WebAdminPortals
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
            , -- Sprint 1.13 — the --test-options passthrough forwards an opaque
              -- argument string (e.g. a tasty -p substrate lane) to cabal test.

              ( ["test", "jitml-backends", "--test-options", "-p linux-cuda"]
              , ParsedCommand
                  ["test", "jitml-backends"]
                  [ParsedOption "test-options" ["-p linux-cuda"]]
              )
            , -- Explicit substrate selectors on `test` (mirror `bootstrap`):
              -- the orchestrator restricts partitioned stanzas to that lane.

              ( ["test", "all", "--linux-cuda"]
              , ParsedCommand ["test", "all"] [ParsedOption "linux-cuda" []]
              )
            ,
              ( ["test", "jitml-backends", "--linux-cpu"]
              , ParsedCommand ["test", "jitml-backends"] [ParsedOption "linux-cpu" []]
              )
            ,
              ( ["test", "all", "--live"]
              , ParsedCommand ["test", "all"] [ParsedOption "live" []]
              )
            ,
              ( ["build", "--dry-run", "--substrate", "linux-cuda"]
              , ParsedCommand ["build"] [ParsedOption "substrate" ["linux-cuda"], ParsedOption "dry-run" []]
              )
            , -- Sprint 1.12 — train --substrate / --seed Dhall overrides.

              ( ["train", "experiments/mnist.dhall", "--substrate", "linux-cpu", "--seed", "42"]
              , ParsedCommand
                  ["train"]
                  [ ParsedOption "experiment-dhall" ["experiments/mnist.dhall"]
                  , ParsedOption "substrate" ["linux-cpu"]
                  , ParsedOption "seed" ["42"]
                  ]
              )
            , -- Sprint 1.12 — rl train --substrate / --seed Dhall overrides.

              ( ["rl", "train", "experiments/cartpole.dhall", "--substrate", "apple-silicon", "--seed", "1729"]
              , ParsedCommand
                  ["rl", "train"]
                  [ ParsedOption "rl-experiment-dhall" ["experiments/cartpole.dhall"]
                  , ParsedOption "substrate" ["apple-silicon"]
                  , ParsedOption "seed" ["1729"]
                  ]
              )
            ,
              ( ["rl", "alphazero", "self-play", "--substrate", "linux-cpu", "--seed", "31"]
              , ParsedCommand
                  ["rl", "alphazero", "self-play"]
                  [ ParsedOption "substrate" ["linux-cpu"]
                  , ParsedOption "seed" ["31"]
                  ]
              )
            , -- Sprint 1.12 — tune --sampler / --scheduler / --pruner / --trials / --parallelism overrides.

              (
                [ "tune"
                , "experiments/mnist-tune.dhall"
                , "--sampler"
                , "Sobol"
                , "--scheduler"
                , "ASHA"
                , "--pruner"
                , "MedianPruner"
                , "--trials"
                , "64"
                , "--parallelism"
                , "8"
                ]
              , ParsedCommand
                  ["tune"]
                  [ ParsedOption "tune-dhall" ["experiments/mnist-tune.dhall"]
                  , ParsedOption "sampler" ["Sobol"]
                  , ParsedOption "scheduler" ["ASHA"]
                  , ParsedOption "pruner" ["MedianPruner"]
                  , ParsedOption "trials" ["64"]
                  , ParsedOption "parallelism" ["8"]
                  ]
              )
            ,
              ( ["help", "cluster", "up"]
              , ParsedCommand ["help"] [ParsedOption "subcommand" ["cluster", "up"]]
              )
            ]
      , testCase "substrateTestInvocations builds the right cabal lanes" $ do
          -- No substrate: one legacy invocation over all targets, with the
          -- opaque --test-options forwarded verbatim.
          substrateTestInvocations Nothing ["jitml-unit", "jitml-backends"] Nothing
            @?= [["test", "jitml-unit", "jitml-backends"]]
          substrateTestInvocations Nothing ["jitml-backends"] (Just "-p Live")
            @?= [["test", "jitml-backends", "--test-options", "-p Live"]]
          -- linux-cpu: pure-logic stanza runs in full; the partitioned stanza
          -- is restricted to the linux-cpu lane. No -fcuda.
          substrateTestInvocations (Just Substrate.LinuxCPU) ["jitml-unit", "jitml-backends"] Nothing
            @?= [ ["test", "jitml-unit"]
                , ["test", "jitml-backends", "--test-options", "-p linux-cpu"]
                ]
          -- linux-cuda: -fcuda on every invocation (one consistent build) and
          -- the backends lane selected with -p linux-cuda.
          substrateTestInvocations (Just Substrate.LinuxCUDA) ["jitml-unit", "jitml-backends"] Nothing
            @?= [ ["test", "-fcuda", "jitml-unit"]
                , ["test", "-fcuda", "jitml-backends", "--test-options", "-p linux-cuda"]
                ]
          -- A single partitioned stanza omits the (empty) pure-logic invocation.
          substrateTestInvocations (Just Substrate.LinuxCUDA) ["jitml-backends"] Nothing
            @?= [["test", "-fcuda", "jitml-backends", "--test-options", "-p linux-cuda"]]
          -- A pure-logic-only run omits the (empty) partitioned invocation.
          substrateTestInvocations (Just Substrate.LinuxCPU) ["jitml-unit", "jitml-e2e"] Nothing
            @?= [["test", "jitml-unit", "jitml-e2e"]]
          -- User --test-options still apply to non-partitioned stanzas under a
          -- substrate flag; otherwise focused live filters such as WorkflowMatrix
          -- accidentally expand to the whole integration suite.
          substrateTestInvocations
            (Just Substrate.AppleSilicon)
            ["jitml-integration"]
            (Just "-p WorkflowMatrix")
            @?= [["test", "jitml-integration", "--test-options", "-p WorkflowMatrix"]]
          -- User --test-options are appended after the synthesized lane selector.
          substrateTestInvocations (Just Substrate.LinuxCUDA) ["jitml-backends"] (Just "--num-threads=1")
            @?= [["test", "-fcuda", "jitml-backends", "--test-options", "-p linux-cuda --num-threads=1"]]
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
            , "web/src/Generated/AdminPortals.purs"
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
          expected <- Text.IO.readFile "test/snapshots/cli/app-error-render.txt"
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
      , testCase "Sprint 1.12 — substrate parser accepts canonical identifiers only" $ do
          Substrate.parseSubstrate "apple-silicon" @?= Just Substrate.AppleSilicon
          Substrate.parseSubstrate "linux-cpu" @?= Just Substrate.LinuxCPU
          Substrate.parseSubstrate "linux-cuda" @?= Just Substrate.LinuxCUDA
          -- Bare aliases must not parse — README.md:880 used `cpu,cuda`,
          -- which is the contradiction Sprint 1.12 closes.
          Substrate.parseSubstrate "cpu" @?= Nothing
          Substrate.parseSubstrate "cuda" @?= Nothing
          Substrate.parseSubstrate "apple" @?= Nothing
          Substrate.parseSubstrate "linux" @?= Nothing
          Substrate.parseSubstrate "" @?= Nothing
      , testCase "Sprint 1.12 — train CLI overrides parse" $ do
          let parsed =
                Overrides.parseExperimentOverrides
                  [ ParsedOption "substrate" ["linux-cpu"]
                  , ParsedOption "seed" ["42"]
                  ]
          parsed
            @?= Right
              Overrides.ExperimentOverrides
                { Overrides.eoSubstrate = Just Substrate.LinuxCPU
                , Overrides.eoSeed = Just 42
                }
      , testCase "Sprint 1.12 — train CLI overrides default to empty" $ do
          let parsed = Overrides.parseExperimentOverrides []
          parsed @?= Right Overrides.emptyExperimentOverrides
          Overrides.hasExperimentOverrides Overrides.emptyExperimentOverrides @?= False
      , testCase "Sprint 1.12 — invalid --substrate value surfaces a typed error" $ do
          let parsed = Overrides.parseExperimentOverrides [ParsedOption "substrate" ["cpu"]]
          parsed @?= Left (Overrides.InvalidSubstrate "cpu")
      , testCase "Sprint 1.12 — invalid --seed value surfaces a typed error" $ do
          let parsed = Overrides.parseExperimentOverrides [ParsedOption "seed" ["not-a-number"]]
          parsed @?= Left (Overrides.InvalidSeed "not-a-number")
      , testCase "Sprint 1.12 — tune CLI overrides parse for every catalog axis" $ do
          let parsed =
                Overrides.parseTuningOverrides
                  [ ParsedOption "sampler" ["TPE"]
                  , ParsedOption "scheduler" ["ASHA"]
                  , ParsedOption "pruner" ["MedianPruner"]
                  , ParsedOption "trials" ["128"]
                  , ParsedOption "parallelism" ["8"]
                  ]
          parsed
            @?= Right
              Overrides.TuningOverrides
                { Overrides.toSampler = Just Tune.TPE
                , Overrides.toScheduler = Just Tune.ASHA
                , Overrides.toPruner = Just Tune.MedianPruner
                , Overrides.toTrials = Just 128
                , Overrides.toParallelism = Just 8
                }
      , testCase "Sprint 1.12 — invalid --sampler surfaces a typed error" $ do
          let parsed = Overrides.parseTuningOverrides [ParsedOption "sampler" ["Bogus"]]
          parsed @?= Left (Overrides.InvalidSampler "Bogus")
      , testCase "Sprint 1.12 — invalid --trials surfaces a typed error" $ do
          let parsed = Overrides.parseTuningOverrides [ParsedOption "trials" ["-3"]]
          parsed @?= Left (Overrides.InvalidTrials "-3")
      , testCase "Sprint 1.12 — overrides substitute on named axis only (pillar 2)" $ do
          let ovr =
                Overrides.TuningOverrides
                  { Overrides.toSampler = Just Tune.PBT
                  , Overrides.toScheduler = Nothing
                  , Overrides.toPruner = Nothing
                  , Overrides.toTrials = Nothing
                  , Overrides.toParallelism = Nothing
                  }
          -- Sampler override substitutes; other axes preserve the base.
          Overrides.overrideSampler ovr Tune.Grid @?= Tune.PBT
          Overrides.overrideScheduler ovr Tune.Fifo @?= Tune.Fifo
          Overrides.overridePruner ovr Tune.NoPruner @?= Tune.NoPruner
          Overrides.overrideTrials ovr 64 @?= 64
          Overrides.overrideParallelism ovr 4 @?= 4
      , testCase "Sprint 1.12 — empty overrides preserve every Dhall value" $ do
          let empty = Overrides.emptyTuningOverrides
          Overrides.overrideSampler empty Tune.Grid @?= Tune.Grid
          Overrides.overrideScheduler empty Tune.Hyperband @?= Tune.Hyperband
          Overrides.overridePruner empty Tune.PercentilePruner @?= Tune.PercentilePruner
          Overrides.overrideTrials empty 256 @?= 256
          Overrides.overrideParallelism empty 16 @?= 16
          Overrides.overrideSubstrate Overrides.emptyExperimentOverrides Substrate.AppleSilicon
            @?= Substrate.AppleSilicon
          Overrides.overrideSeed Overrides.emptyExperimentOverrides 1729 @?= 1729
      , testCase "Sprint 1.12 — render override summary lists only present axes" $ do
          Overrides.renderExperimentOverrides Overrides.emptyExperimentOverrides @?= "(none)"
          Overrides.renderTuningOverrides Overrides.emptyTuningOverrides @?= "(none)"
          let ovr =
                Overrides.ExperimentOverrides
                  { Overrides.eoSubstrate = Just Substrate.LinuxCPU
                  , Overrides.eoSeed = Just 42
                  }
          Overrides.renderExperimentOverrides ovr @?= "substrate=linux-cpu, seed=42"
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
      , testCase "Apple JIT cache-miss prerequisite root requires fixed Metal bridge nodes" $ do
          -- Sprint 2.12 — the core Apple cache-miss path uses the host OS Metal
          -- runtime plus the fixed bridge, not Tart, SwiftPM, or a VM lifecycle.
          let registryIds = fmap nodeId prerequisiteRegistry
          assertBool
            "apple.metal-runtime is in the registry"
            (NodeId "apple.metal-runtime" `elem` registryIds)
          assertBool
            "apple.metal-bridge is in the registry"
            (NodeId "apple.metal-bridge" `elem` registryIds)
          assertBool
            "optional apple.swiftc is registered but not a core dependency"
            (NodeId "apple.swiftc" `elem` registryIds)
          assertBool
            "container.tart is not in the registry"
            (NodeId "container.tart" `notElem` registryIds)
          case transitiveClosure prerequisiteRegistry (NodeId "container.apple-silicon.jit-cache-miss") of
            Left err -> assertFailure (show err)
            Right closure -> do
              let closureIds = fmap nodeId closure
              assertBool
                "cache miss closure references Metal runtime"
                (NodeId "apple.metal-runtime" `elem` closureIds)
              assertBool
                "cache miss closure references fixed bridge"
                (NodeId "apple.metal-bridge" `elem` closureIds)
              assertBool
                "cache miss closure excludes Tart"
                (NodeId "container.tart" `notElem` closureIds)
              assertBool
                "cache miss closure excludes optional Swift compiler"
                (NodeId "apple.swiftc" `notElem` closureIds)
      , testCase "Homebrew remediation nodes carry typed subprocesses" $
          case find ((== NodeId "toolchain.spago") . nodeId) prerequisiteRegistry of
            Nothing -> assertFailure "missing toolchain.spago"
            Just prerequisite ->
              case remediation prerequisite of
                Nothing -> assertFailure "missing spago remediation"
                Just remediationValue ->
                  renderSubprocess (remediationCommand remediationValue) @?= "brew install spago"
      , testCase "Homebrew remediation plan render matches golden" $ do
          expected <- Text.IO.readFile "test/snapshots/prerequisite/homebrew-remediation-plan.txt"
          let prerequisite =
                Prerequisite
                  { nodeId = NodeId "toolchain.spago"
                  , nodeDescription = "Spago is installed."
                  , remedyHint = Just "brew install spago"
                  , dependsOn = []
                  , remediation =
                      Just
                        PrerequisiteRemediation
                          { remediationDescription = "Install Homebrew package spago."
                          , remediationCommand = subprocess "brew" ["install", "spago"]
                          }
                  , checkNode = pure False
                  }
          result <- buildPrerequisitePlan [prerequisite] (NodeId "toolchain.spago")
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
          expected <- Text.IO.readFile "test/snapshots/cache/kernel-key.txt"
          let first = sampleCacheHash
              second =
                Cache.cacheKey
                  (Cache.KernelSpec "phase-2-kernel:linear")
                  Cache.Training
                  Cache.AppleSilicon
                  (Cache.ToolchainFingerprint "llvm=ghc-9.12.4;xcode-metal=pinned;tuning=default")
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
      , testCase "Apple kernel loader fills source metadata cache without host build tools" $
          withSystemTempDirectory "jitml-apple-metadata-loader" $ \dir -> do
            cwd <- getCurrentDirectory
            bracket_ (setCurrentDirectory dir) (setCurrentDirectory cwd) $ do
              env <- buildEnv defaultGlobalFlags
              let kernelSpec = Cache.KernelSpec "phase-7-kernel:apple-metadata"
                  source =
                    renderRuntimeSource
                      kernelSpec
                      Cache.Inference
                      Cache.AppleSilicon
                      Cache.defaultTuningChoice
                  engine = Engine.engineForSubstrate Substrate.AppleSilicon
                  handle = Engine.kernelHandleFor engine sampleCacheHash
                  artifactPath = Text.unpack (Engine.kernelHandleArtifactPath handle)
              first <- Loader.ensureKernelArtifact env engine source sampleCacheHash
              case first of
                Left err -> assertFailure (Text.unpack err)
                Right artifact -> do
                  Loader.kernelArtifactHandle artifact @?= handle
                  Loader.kernelArtifactCompiled artifact @?= True
                  Engine.engineArtifactExtension (Engine.kernelHandleEngine handle) @?= "metal.json"
                  contents <- Text.IO.readFile artifactPath
                  assertBool
                    "metadata artifact records bridge ABI"
                    ("\"bridge_abi\": \"jitml-metal-bridge-v1\"" `Text.isInfixOf` contents)
                  assertBool
                    "metadata artifact embeds MSL"
                    ("kernel void jitml_kernel" `Text.isInfixOf` contents)
                  assertBool
                    "Apple metadata diagnostic excludes Tart"
                    (not ("tart" `Text.isInfixOf` Text.toLower (Loader.kernelArtifactCompileCommand artifact)))
                  assertBool
                    "Apple metadata diagnostic excludes SwiftPM"
                    (not ("swift build" `Text.isInfixOf` Text.toLower (Loader.kernelArtifactCompileCommand artifact)))
              second <- Loader.ensureKernelArtifact env engine source sampleCacheHash
              case second of
                Left err -> assertFailure (Text.unpack err)
                Right artifact ->
                  Loader.kernelArtifactCompiled artifact @?= False
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
      , testCase
          "cuDNN deterministic-algorithm pin is emitted and consistent with the Tuning allowlist (Sprint 13.8)"
          $ do
            let renderedSource family =
                  Text.concat
                    [ contents
                    | SourceFile _ contents <-
                        Cuda.renderCudaFamilySource
                          family
                          (Cache.KernelSpec "phase-13-kernel:cudnn-pin")
                          Cache.Training
                          Cache.defaultTuningChoice
                    ]
                convPin = "CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM"
                pinField algo = "jitml_cudnn_algorithm = \"" <> algo <> "\""
            -- The conv forward pin in Codegen.Cuda must agree with the
            -- independently-defined deterministic forward-algorithm allowlist in
            -- Engines.Tuning (a cross-module consistency check, not a tautology).
            assertBool
              "conv forward pin is a deterministic algorithm in the Tuning allowlist"
              (convPin `elem` Tuning.cuDnnDeterministicAlgorithms)
            Control.Monad.forM_ [Conv2DKernel, Conv3DKernel] $ \family ->
              assertBool
                ("generated CUDA source for " <> show family <> " pins the deterministic conv algorithm")
                (pinField convPin `Text.isInfixOf` renderedSource family)
            Control.Monad.forM_ [BatchNormKernel, LayerNormKernel] $ \family ->
              assertBool
                ("generated CUDA source for " <> show family <> " pins the persistent batch-norm algorithm")
                (pinField "CUDNN_BATCHNORM_SPATIAL_PERSISTENT" `Text.isInfixOf` renderedSource family)
            -- Non-cuDNN families (the MLP/reduction kernels) must not claim a cuDNN
            -- algorithm, so the deterministic pin stays scoped to the conv/norm path.
            assertBool
              "non-cuDNN family records no cuDNN algorithm"
              (pinField "none" `Text.isInfixOf` renderedSource Reduction)
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
          -- exercises the real FFI path through `jitml-backends`.
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
      , testCase "Metal source metadata records family, launch, and source payload" $ do
          let reductionMetadata =
                Metal.renderMetalFamilyMetadata
                  Reduction
                  (Cache.KernelSpec "phase-7-kernel:metal-reduction")
                  Cache.Inference
                  Cache.defaultTuningChoice
          case find ((== "kernel.metal.json") . sourceRelativePath) reductionMetadata of
            Nothing ->
              assertFailure "missing Metal source metadata"
            Just (SourceFile _ contents) -> do
              assertBool
                "metadata records the fixed bridge ABI"
                ("\"bridge_abi\": \"jitml-metal-bridge-v1\"" `Text.isInfixOf` contents)
              assertBool
                "metadata records family"
                ("\"family\": \"reduction\"" `Text.isInfixOf` contents)
              assertBool
                "metadata records output-count policy"
                ("\"kind\": \"ceil-input-over-32\"" `Text.isInfixOf` contents)
              assertBool
                "metadata embeds canonical MSL source"
                ("kernel void jitml_kernel" `Text.isInfixOf` contents)
              Metal.metalOutputCountFor Reduction 0 @?= 0
              Metal.metalOutputCountFor Reduction 33 @?= 2
          Metal.threadgroupSizeFor Reduction @?= 64
      , testCase "Metal runtime probe is device-only for core execution" $ do
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
                  { MetalRuntime.metalRuntimeSwiftVersion = Nothing
                  , MetalRuntime.metalRuntimeMetalCompilerPath = Nothing
                  , MetalRuntime.metalRuntimeSwiftCompilerPath = Nothing
                  , MetalRuntime.metalRuntimeDeviceVisible =
                      MetalRuntime.metalDeviceVisibleFromSystemProfiler systemProfilerOutput
                  , MetalRuntime.metalRuntimeProbeLog =
                      ["system_profiler SPDisplaysDataType: metal_device_visible=yes"]
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
          -- Sprint 2.12 — Swift/Xcode discovery is optional and not part of the
          -- core Apple Metal runtime gate.
          MetalRuntime.metalRuntimeAvailable
            availableProbe
              { MetalRuntime.metalRuntimeMetalCompilerPath = Nothing
              , MetalRuntime.metalRuntimeSwiftCompilerPath = Nothing
              , MetalRuntime.metalRuntimeSwiftVersion = Nothing
              }
            @?= True
          assertBool
            "rendered Metal probe records availability"
            ("available: yes" `Text.isInfixOf` rendered)
          assertBool
            "rendered Metal probe records compiler probes as not run"
            ("metal_compiler: not_probed" `Text.isInfixOf` rendered)
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
          -- `jitml-backends` on a CUDA host; here we keep the
          -- deterministic path that only covers wrong-substrate and
          -- unavailable cases. `availableCudaProbe` is intentionally
          -- only used by the `unavailableCudaProbe` field-update form
          -- above so the synthetic library-visible/positive shape stays
          -- expressed in this case.
          -- Sprint 14.3 — the Metal benchmark runner now drives the real
          -- Metal candidate through `MetalLocal.runMetalKernel` (metadata cache
          -- -> fixed bridge -> runtime makeLibrary -> launch). The live
          -- measurement is exercised through `jitml-backends` on a Metal-capable
          -- Apple host; here we keep the deterministic wrong-substrate and
          -- device-not-visible branches. `availableMetalProbe` is retained for
          -- the `unavailableMetalProbe` field-update form above.
          metalWrong <-
            TuningBenchmark.metalBenchmarkCandidateRunnerWithProbe
              (pure unavailableMetalProbe)
              cudaEnv
              kernelSpec
              Cache.Training
              []
              linuxCandidate
          metalWrong
            @?= Left "apple-silicon benchmark runner cannot execute linux-cpu candidate"
          metalUnavailable <-
            TuningBenchmark.metalBenchmarkCandidateRunnerWithProbe
              (pure unavailableMetalProbe)
              cudaEnv
              kernelSpec
              Cache.Training
              []
              appleCandidate
          metalUnavailable
            @?= Left
              "apple-silicon benchmark runner unavailable: device=no"
      , testCase "cachePath resolves under the substrate cache root" $
          withSystemTempDirectory "jitml-cache-layout" $ \dir -> do
            root <- resolveDir' (dir </> ".build")
            path <- CacheLayout.cachePath root Cache.LinuxCPU sampleCacheHash (Cache.Extension "so")
            toFilePath path
              @?= dir
              </> ".build/jit/linux-cpu/"
              <> Text.unpack (Cache.hashHex sampleCacheHash)
              <> ".so"
      , testCase "Apple Metal metadata path uses the source-metadata extension" $
          withSystemTempDirectory "jitml-cache-layout-metal" $ \dir -> do
            root <- resolveDir' (dir </> ".build")
            path <- CacheLayout.appleMetalMetadataPath root sampleCacheHash
            toFilePath path
              @?= dir
              </> ".build/jit/apple-silicon/"
              <> Text.unpack (Cache.hashHex sampleCacheHash)
              <> ".metal.json"
      , testCase "manifest round-trips and indexes latest hashes" $
          withSystemTempDirectory "jitml-cache-manifest" $ \dir -> do
            root <- resolveDir' (dir </> ".build")
            let entry =
                  CacheManifest.ManifestEntry
                    { CacheManifest.manifestEntryModelId = Cache.ModelId "mnist-linear"
                    , CacheManifest.manifestEntryKind = Cache.Training
                    , CacheManifest.manifestEntrySubstrate = Cache.AppleSilicon
                    , CacheManifest.manifestEntryToolchain =
                        Cache.ToolchainFingerprint "llvm=ghc-9.12.4;xcode-metal=pinned;tuning=default"
                    , CacheManifest.manifestEntryHash = sampleCacheHash
                    }
                manifest = CacheManifest.upsertManifest entry CacheManifest.emptyManifest
                key = CacheManifest.manifestEntryKey entry
            decode (encode manifest) @?= Just manifest
            CacheManifest.lookupManifest key manifest @?= Just sampleCacheHash
            CacheManifest.writeManifestAtomic root manifest
            readResult <- CacheManifest.readManifest root
            readResult @?= Right manifest
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
              renderedLiveConfig = LiveConfig.renderLiveConfigDhall LiveConfig.defaultLiveConfig
          assertBool
            "LiveConfig omits build VM fields"
            (not ("buildVm" `Text.isInfixOf` renderedLiveConfig))
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
            @?= ["cartpole", "mountain-car", "lunar-lander", "key-door-grid", "atari-subset"]
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
      , testCase
          "key-door-grid exposes deterministic maps, masks, renders, and goal termination (Sprint 8.9)"
          $ do
            Sim.keyDoorGridInitial 3 @?= Sim.keyDoorGridInitial 3
            assertBool
              "different seeds move key or wall layout"
              (Sim.keyDoorGridInitial 3 /= Sim.keyDoorGridInitial 4)
            let start = Sim.keyDoorGridInitial 0
            Sim.keyDoorGridLegalActionMask start
              @?= [False, True, False, True, False, False]
            length (Sim.keyDoorGridObservation start) @?= 127
            Sim.keyDoorGridRenderFrame start @?= Sim.keyDoorGridRenderFrame start
            assertBool
              "render frame is generated from Haskell state"
              ("key-door-grid" `Text.isInfixOf` Sim.renderCaption (Sim.keyDoorGridRenderFrame start))
            let east1 = Sim.keyDoorGridStep start (fromEnum Sim.KeyDoorGridEast)
                east2 = Sim.keyDoorGridStep (Sim.simStepState east1) (fromEnum Sim.KeyDoorGridEast)
                onKey = Sim.simStepState east2
            Sim.keyDoorGridAgent onKey @?= Sim.keyDoorGridKey onKey
            Sim.keyDoorGridLegalActionMask onKey
              @?= [False, True, True, True, True, False]
            let picked = Sim.keyDoorGridStep onKey (fromEnum Sim.KeyDoorGridPickUpKey)
                carried = Sim.simStepState picked
            Sim.keyDoorGridHasKey carried @?= True
            assertBool "key pickup gives positive reward" (Sim.simStepReward picked > 0)
            let routeToDoor =
                  foldl
                    (\state action -> Sim.simStepState (Sim.keyDoorGridStep state (fromEnum action)))
                    carried
                    [ Sim.KeyDoorGridEast
                    , Sim.KeyDoorGridEast
                    , Sim.KeyDoorGridSouth
                    , Sim.KeyDoorGridSouth
                    ]
            Sim.keyDoorGridAgent routeToDoor @?= Sim.KeyDoorGridPosition 2 4
            assertBool
              "open-door action is legal next to the locked door after key pickup"
              (Sim.keyDoorGridLegalActionMask routeToDoor !! fromEnum Sim.KeyDoorGridOpenDoor)
            let opened = Sim.keyDoorGridStep routeToDoor (fromEnum Sim.KeyDoorGridOpenDoor)
                openedState = Sim.simStepState opened
            Sim.keyDoorGridDoorOpen openedState @?= True
            let throughDoor = Sim.keyDoorGridStep openedState (fromEnum Sim.KeyDoorGridSouth)
                goal = Sim.keyDoorGridStep (Sim.simStepState throughDoor) (fromEnum Sim.KeyDoorGridSouth)
            Sim.keyDoorGridAgent (Sim.simStepState goal) @?= Sim.keyDoorGridGoal (Sim.simStepState goal)
            Sim.simStepDone goal @?= True
            assertBool "goal reward is positive" (Sim.simStepReward goal > 0)
      , testCase "atari-subset requires an explicit uncommitted ROM path (Sprint 8.8)" $ do
          result <- ALE.resolveAtariRomPath (Just "/jitml/nonexistent-atari-rom.bin")
          case result of
            Left err ->
              assertBool
                "missing-ROM policy names JITML_ATARI_ROM"
                ("JITML_ATARI_ROM" `Text.isInfixOf` err)
            Right path ->
              assertBool
                ("unexpected ambient Atari ROM path during unit test: " <> path)
                False
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
      , testCase "MCTS position oracle plumbing routes through the real tree search (Sprint 9.10)" $ do
          -- Confirm that supplying a custom position oracle (`[Int] -> NodeEval`)
          -- actually changes the search output. The neutral default expands the
          -- root with uniform priors; a biased oracle yields asymmetric priors,
          -- proving the oracle threads through the real descend/expand search.
          let cfg = Mcts.defaultMctsConfig 4
              defaultTree = Mcts.runSearch cfg 17
              biasedTree =
                Mcts.runSearchWithPrior (\_ -> Mcts.NodeEval [1.0, 2.0, 3.0, 4.0] 0.0 False) cfg 17
              defaultPriors = map Mcts.edgePrior (Mcts.nodeChildren defaultTree)
              biasedPriors = map Mcts.edgePrior (Mcts.nodeChildren biasedTree)
          assertBool
            "default oracle produces uniform priors"
            (all (\p -> abs (p - 0.25) < 0.001) defaultPriors)
          assertBool
            "biased oracle does not produce uniform priors"
            (any (\p -> abs (p - 0.25) > 0.001) biasedPriors)
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
      , testCase "checkpoint manifest carries architecture-aware model-family metadata" $ do
          let weightA = Checkpoint.TensorBlob "a.weight" [2, 2] "blob-a"
              weightZ = Checkpoint.TensorBlob "z.weight" [3] "blob-z"
              inputSpec = Checkpoint.TensorSpec "board" [6, 7, 2] "F64"
              policySpec = Checkpoint.TensorSpec "policy" [7] "F64"
              valueSpec = Checkpoint.TensorSpec "value" [1] "F64"
              manifest =
                ( Checkpoint.emptyManifest
                    "manifest-rich"
                    "exp-rich"
                    [weightZ, weightA]
                )
                  { Checkpoint.manifestModelFamily = Checkpoint.AlphaZeroPolicyValueFamily
                  , Checkpoint.manifestArchitecture =
                      Checkpoint.ArchitectureMetadata
                        { Checkpoint.architectureName = "connect4-policy-value"
                        , Checkpoint.architectureModelFamily =
                            Checkpoint.AlphaZeroPolicyValueFamily
                        , Checkpoint.architectureInputs = [inputSpec]
                        , Checkpoint.architectureOutputs = [valueSpec, policySpec]
                        }
                  , Checkpoint.manifestPreprocessing =
                      [ Checkpoint.PreprocessingMetadata
                          { Checkpoint.preprocessingName = "connect4-board"
                          , Checkpoint.preprocessingSteps = ["legal-mask", "perspective"]
                          , Checkpoint.preprocessingInputs = [inputSpec]
                          }
                      ]
                  , Checkpoint.manifestOutputDecoders =
                      [ Checkpoint.OutputDecoder
                          { Checkpoint.outputDecoderName = "z-policy"
                          , Checkpoint.outputDecoderKind = Checkpoint.PolicyDistributionOutput
                          , Checkpoint.outputDecoderLabels = ["0", "1", "2", "3", "4", "5", "6"]
                          , Checkpoint.outputDecoderUnits = Nothing
                          , Checkpoint.outputDecoderArtifactKind = Nothing
                          }
                      , Checkpoint.OutputDecoder
                          { Checkpoint.outputDecoderName = "a-mcts-visits"
                          , Checkpoint.outputDecoderKind = Checkpoint.MctsVisitDistributionOutput
                          , Checkpoint.outputDecoderLabels = ["0", "1", "2", "3", "4", "5", "6"]
                          , Checkpoint.outputDecoderUnits = Nothing
                          , Checkpoint.outputDecoderArtifactKind = Nothing
                          }
                      , Checkpoint.OutputDecoder
                          { Checkpoint.outputDecoderName = "value"
                          , Checkpoint.outputDecoderKind = Checkpoint.ValueEstimateOutput
                          , Checkpoint.outputDecoderLabels = []
                          , Checkpoint.outputDecoderUnits = Nothing
                          , Checkpoint.outputDecoderArtifactKind = Nothing
                          }
                      ]
                  , Checkpoint.manifestWeightLayout =
                      Checkpoint.NamedTensorWeightLayout
                        [ Checkpoint.tensorSpecFromBlob weightZ
                        , Checkpoint.tensorSpecFromBlob weightA
                        ]
                  , Checkpoint.manifestReplayPointers =
                      [Checkpoint.ArtifactPointer "self-play" "jitml-checkpoints/exp-rich/replay/a" (Just "sha-r")]
                  , Checkpoint.manifestTranscriptPointers =
                      [Checkpoint.ArtifactPointer "training" "jitml-checkpoints/exp-rich/transcript/a" Nothing]
                  , Checkpoint.manifestSubstrateArtifacts =
                      [ Checkpoint.SubstrateArtifact
                          "linux-cuda"
                          "jit-kernel"
                          "cache-key-a"
                          (Just "jitml-checkpoints/exp-rich/artifacts/kernel")
                      ]
                  }
          case Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor manifest) of
            Left err -> assertFailure ("manifest decode failed: " <> Text.unpack err)
            Right decoded -> do
              Checkpoint.manifestModelFamily decoded
                @?= Checkpoint.AlphaZeroPolicyValueFamily
              fmap Checkpoint.tensorName (Checkpoint.manifestTensors decoded)
                @?= ["a.weight", "z.weight"]
              case Checkpoint.manifestWeightLayout decoded of
                Checkpoint.NamedTensorWeightLayout specs ->
                  fmap Checkpoint.tensorSpecName specs @?= ["a.weight", "z.weight"]
                other ->
                  assertFailure ("expected named tensor layout, got: " <> show other)
              fmap Checkpoint.outputDecoderKind (Checkpoint.manifestOutputDecoders decoded)
                @?= [ Checkpoint.MctsVisitDistributionOutput
                    , Checkpoint.ValueEstimateOutput
                    , Checkpoint.PolicyDistributionOutput
                    ]
              Checkpoint.manifestReplayPointers decoded
                @?= [Checkpoint.ArtifactPointer "self-play" "jitml-checkpoints/exp-rich/replay/a" (Just "sha-r")]
              Checkpoint.manifestTranscriptPointers decoded
                @?= [Checkpoint.ArtifactPointer "training" "jitml-checkpoints/exp-rich/transcript/a" Nothing]
      , testCase "checkpoint metadata covers every no-caveat trainable family" $ do
          let tensor = Checkpoint.TensorBlob "weights" [1] "blob"
              families =
                [ (Checkpoint.SupervisedModelFamily, Checkpoint.ClassificationOutput)
                , (Checkpoint.ReinforcementLearningPolicyFamily, Checkpoint.PolicyDistributionOutput)
                , (Checkpoint.AlphaZeroPolicyValueFamily, Checkpoint.ValueEstimateOutput)
                , (Checkpoint.HyperparameterTuningFamily, Checkpoint.RegressionOutput)
                ]
          traverse_
            ( \(family, decoderKind) -> do
                let manifest =
                      (Checkpoint.emptyManifest "m" "exp" [tensor])
                        { Checkpoint.manifestModelFamily = family
                        , Checkpoint.manifestArchitecture =
                            (Checkpoint.defaultArchitectureMetadata family)
                              { Checkpoint.architectureName = "family-test"
                              }
                        , Checkpoint.manifestOutputDecoders =
                            [ Checkpoint.OutputDecoder
                                { Checkpoint.outputDecoderName = "decoder"
                                , Checkpoint.outputDecoderKind = decoderKind
                                , Checkpoint.outputDecoderLabels = []
                                , Checkpoint.outputDecoderUnits = Nothing
                                , Checkpoint.outputDecoderArtifactKind = Nothing
                                }
                            ]
                        }
                case Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor manifest) of
                  Left err -> assertFailure ("manifest decode failed: " <> Text.unpack err)
                  Right decoded -> do
                    Checkpoint.manifestModelFamily decoded @?= family
                    fmap Checkpoint.outputDecoderKind (Checkpoint.manifestOutputDecoders decoded)
                      @?= [decoderKind]
            )
            families
      , testCase "checkpoint store writes blobs/manifests and reads latest pointer" $
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
            latest <- CheckpointStore.readCheckpointPointer dir (Checkpoint.latestPointerKey "exp1")
            latest @?= Just (CheckpointStore.storedManifestSha firstWrite)
            blob <- CheckpointStore.readObject dir blobKey
            blob @?= Right payload
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
          expected <- Text.IO.readFile "test/snapshots/observability/grafana-daemon-health.yaml"
          case find ((== "daemon-health") . Grafana.dashboardName) Grafana.dashboards of
            Nothing -> assertFailure "missing daemon-health dashboard"
            Just dashboard -> Grafana.renderDashboardConfigMap dashboard @?= expected
      , testCase "frontend bundle and panel surfaces cover the demo panels" $ do
          fmap WebBundle.panelName WebBundle.panelSurfaces
            @?= [ "mnist-live-inference"
                , "generic-inference-lab"
                , "checkpoint-compare-lab"
                , "cifar-imagenet-upload"
                , "connect4-human-vs-alphazero"
                , "rl-trajectory"
                , "training-progress"
                , "hyperparameter-sweep"
                ]
          fmap WebBundle.demoRoutePath WebBundle.demoRoutes
            @?= [ "/"
                , "/api"
                , "/api/runs/{runId}/command"
                , "/api/inference"
                , "/api/inference/generic"
                , "/api/images"
                , "/api/checkpoints/compare"
                , "/api/connect4/move"
                , "/api/ws"
                , "/api/ws/training"
                , "/api/ws/rl"
                , "/api/ws/tune"
                ]
          WebBundle.renderDemoRouteManifest
            @?= Text.unlines
              [ "demo-routes:"
              , "- / static-shell <- web/src/Main.purs"
              , "- /api contract-index <- src/JitML/Web/Contracts.hs"
              , "- /api/runs/{runId}/command workflow-command-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/inference inference-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/inference/generic generic-inference-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/images image-upload-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/checkpoints/compare checkpoint-compare-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/connect4/move connect4-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws metrics-stream-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws/training training-stream-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws/rl rl-stream-contract <- src/JitML/Web/Contracts.hs"
              , "- /api/ws/tune tune-stream-contract <- src/JitML/Web/Contracts.hs"
              ]
          WebContracts.contractGeneratorName @?= "local-purescript-bridge-compatible-renderer"
          fmap (Routes.routeName . fst) Routes.adminPortalRoutes
            @?= [ "grafana"
                , "prometheus"
                , "tensorboard"
                , "harbor-portal"
                , "minio-console"
                , "pulsar-admin"
                ]
          assertBool
            "admin portal renderer emits the generated module"
            ("module Generated.AdminPortals where" `Text.isInfixOf` WebAdminPortals.renderPureScriptAdminPortals)
      , -- Sprint 13.6 — convergence threshold table sanity.
        testGroup
          "RL convergence threshold table (Sprint 13.6)"
          [ testCase "PPO cartpole threshold is reachable by SB3-zoo baselines" $ do
              case ConvergenceThresholds.cohortThreshold "PPO" "cartpole" of
                Nothing ->
                  assertBool
                    "PPO/cartpole threshold must exist"
                    False
                Just threshold -> do
                  ConvergenceThresholds.literatureTarget threshold @?= 475.0
                  ConvergenceThresholds.slack threshold @?= 25.0
                  assertBool
                    "median 480 passes literature target - slack"
                    (ConvergenceThresholds.passesConvergence threshold 480.0)
                  assertBool
                    "median 449 (just below 475 - 25) fails the assertion"
                    (not (ConvergenceThresholds.passesConvergence threshold 449.0))
          , testCase "every catalog algorithm except HER/AlphaZero has at least one cohort" $ do
              let catalogNames =
                    fmap RLAlgorithms.algorithmName RLAlgorithms.algorithmCatalog
                  covered =
                    fmap (fst . fst) ConvergenceThresholds.cohortThresholds
                  required = filter (`notElem` ["HER", "AlphaZero"]) catalogNames
                  missing = [name | name <- required, name `notElem` covered]
              missing @?= []
          , testCase "every threshold row uses a positive slack and an env from the canonical catalog" $ do
              let envNames =
                    fmap RLEnvironments.environmentName RLEnvironments.canonicalEnvironments
                  rows = ConvergenceThresholds.cohortThresholds
                  badSlack =
                    [ (algo, env)
                    | ((algo, env), threshold) <- rows
                    , ConvergenceThresholds.slack threshold <= 0
                    ]
                  unknownEnv =
                    [ (algo, env)
                    | ((algo, env), _) <- rows
                    , env `notElem` envNames
                    ]
              badSlack @?= []
              unknownEnv @?= []
          , testCase "mountain-car thresholds keep the literature target negative" $
              mapM_
                ( \((algo, env), threshold) ->
                    Control.Monad.when (env == "mountain-car") $
                      assertBool
                        ("mountain-car target for " <> Text.unpack algo <> " must be negative")
                        (ConvergenceThresholds.literatureTarget threshold < 0)
                )
                ConvergenceThresholds.cohortThresholds
          ]
      , -- Sprint 12.10 — backend-agnostic invariants relocated out of
        -- jitml-backends (which is now a per-substrate live lane). These
        -- assert pure, substrate-independent properties, so they belong in the
        -- substrate-agnostic unit stanza that runs in every lane.
        testGroup
          "Backend-agnostic engine + manifest invariants (Sprint 12.10)"
          [ testCase "each substrate has deterministic engine flags" $
              mapM_
                ( assertBool "flags present"
                    . not
                    . null
                    . Engine.deterministicFlags
                    . Engine.engineForSubstrate
                )
                Substrate.allSubstrates
          , testCase "checkpoint weight-only tensor selection is backend independent" $ do
              let manifest =
                    Checkpoint.emptyManifest "m1" "exp" [Checkpoint.TensorBlob "dense" [2, 2] "blob"]
                  expected = [Checkpoint.TensorBlob "dense" [2, 2] "blob"]
              mapM_
                (\_substrate -> Checkpoint.weightOnlyTensors manifest @?= expected)
                [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
          ]
      , -- Sprint 13.7 — gc_reaped envelope round-trips through the
        -- proto3-compatible wire format and the deterministic text
        -- render/parse pair.
        testGroup
          "GC reaped event envelope (Sprint 13.7)"
          [ testCase "gcEventTopic emits a substrate-scoped persistent path" $ do
              ProtoGc.gcEventTopic Substrate.LinuxCUDA
                @?= "persistent://public/default/gc.event.linux-cuda"
              ProtoGc.gcEventTopic Substrate.LinuxCPU
                @?= "persistent://public/default/gc.event.linux-cpu"
              ProtoGc.gcEventTopic Substrate.AppleSilicon
                @?= "persistent://public/default/gc.event.apple-silicon"
          , testCase "GcReapedEvent round-trips through proto3-compatible bytes" $ do
              let envelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-13.7"
                      , ProtoGc.gcEventManifestSha = "sha256:reaped"
                      , ProtoGc.gcEventReapedBlobShas = ["blob-a", "blob-b"]
                      , ProtoGc.gcEventStepAtReap = 42
                      , ProtoGc.gcEventSubstrate = "linux-cuda"
                      , ProtoGc.gcEventTimestampNs = 1_700_000_000_000_000_000
                      }
              ProtoGc.decodeGcReapedEventProto (ProtoGc.encodeGcReapedEventProto envelope)
                @?= Right envelope
          , testCase "GcReapedEvent round-trips through render/parse" $ do
              let envelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-text"
                      , ProtoGc.gcEventManifestSha = "sha256:text"
                      , ProtoGc.gcEventReapedBlobShas = ["blob-x"]
                      , ProtoGc.gcEventStepAtReap = 7
                      , ProtoGc.gcEventSubstrate = "linux-cpu"
                      , ProtoGc.gcEventTimestampNs = 1
                      }
              ProtoGc.parseGcReapedEvent (ProtoGc.renderGcReapedEvent envelope)
                @?= Just envelope
          , testCase "GcReapedEvent with no reaped blobs round-trips" $ do
              let envelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-no-blobs"
                      , ProtoGc.gcEventManifestSha = "sha256:lonely"
                      , ProtoGc.gcEventReapedBlobShas = []
                      , ProtoGc.gcEventStepAtReap = 0
                      , ProtoGc.gcEventSubstrate = "apple-silicon"
                      , ProtoGc.gcEventTimestampNs = 0
                      }
              ProtoGc.decodeGcReapedEventProto (ProtoGc.encodeGcReapedEventProto envelope)
                @?= Right envelope
              ProtoGc.parseGcReapedEvent (ProtoGc.renderGcReapedEvent envelope)
                @?= Just envelope
          ]
      , -- Sprint 13.13 — minimal RFC 6455 WebSocket primitives.
        testGroup
          "WebSocket frame and handshake primitives (Sprint 13.13)"
          [ testCase "Sec-WebSocket-Accept matches the RFC 6455 example" $
              -- RFC 6455 §1.3 worked example: key "dGhlIHNhbXBsZSBub25jZQ=="
              -- must produce accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=".
              WS.webSocketAcceptKey "dGhlIHNhbXBsZSBub25jZQ=="
                @?= "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
          , testCase "detectWebSocketUpgrade derives the accept key from a real request" $
              case WS.detectWebSocketUpgrade
                ( "GET /api/ws HTTP/1.1\r\n"
                    <> "Host: 127.0.0.1\r\n"
                    <> "Upgrade: websocket\r\n"
                    <> "Connection: Upgrade\r\n"
                    <> "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                    <> "Sec-WebSocket-Version: 13\r\n\r\n"
                ) of
                WS.UpgradeAccepted accept ->
                  accept @?= "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
                WS.NoUpgrade ->
                  assertFailure "expected WebSocket upgrade detection"
          , testCase "detectWebSocketUpgrade ignores plain HTTP requests" $
              WS.detectWebSocketUpgrade
                "GET /api HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
                @?= WS.NoUpgrade
          , testCase "encodeTextFrame writes a 1-frame text payload (≤125 bytes)" $
              -- "hello" (5 bytes) → 0x81 0x05 'h' 'e' 'l' 'l' 'o'.
              WS.encodeTextFrame "hello"
                @?= StrictByteString.pack
                  [0x81, 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F]
          , testCase "encodeTextFrame uses the 16-bit extended length form for 126..65535 byte payloads" $
              let payload = Text.replicate 200 "x"
                  encoded = WS.encodeTextFrame payload
               in do
                    StrictByteString.index encoded 0 @?= 0x81
                    StrictByteString.index encoded 1 @?= 126
                    -- bytes 2..3 carry big-endian 200 = 0x00C8.
                    StrictByteString.index encoded 2 @?= 0x00
                    StrictByteString.index encoded 3 @?= 0xC8
          , testCase "encodeCloseFrame writes opcode 0x8 with no payload" $
              WS.encodeCloseFrame @?= StrictByteString.pack [0x88, 0x00]
          , testCase "renderUpgradeAccept emits the canonical 101 Switching Protocols response" $
              WS.renderUpgradeAccept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
                @?= "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
          ]
      , -- Sprint 13.8 — PPO real-loss math (clipped surrogate, value
        -- loss, GAE, KL early stop). Catalog-level loss validation now
        -- feeds trained-network inputs from real simulator rollouts.
        testGroup
          "PPO loss math (Sprint 13.8)"
          [ testCase "clippedSurrogateLoss returns 0 on empty batch" $
              PpoLoss.clippedSurrogateLoss 0.2 [] [] [] @?= 0.0
          , testCase "clippedSurrogateLoss with identical policies and zero advantage is 0" $
              PpoLoss.clippedSurrogateLoss
                0.2
                [0.0, 0.0, 0.0]
                [0.0, 0.0, 0.0]
                [0.0, 0.0, 0.0]
                @?= 0.0
          , testCase "clippedSurrogateLoss returns negated unclipped objective when ratio stays in band" $
              let
                -- ratio = exp(0) = 1.0, advantage = 1.0, term = 1.0
                result =
                  PpoLoss.clippedSurrogateLoss
                    0.2
                    [0.0, 0.0]
                    [0.0, 0.0]
                    [1.0, 1.0]
               in
                result @?= negate 1.0
          , testCase "clippedSurrogateLoss clips ratio above 1 + eps when advantage positive" $
              let
                -- new=log(2), old=0, ratio=2.0 > 1+eps=1.2; clipped to 1.2.
                -- min(2*1, 1.2*1) = 1.2 → loss = -1.2.
                result =
                  PpoLoss.clippedSurrogateLoss 0.2 [0.0] [log 2.0] [1.0]
               in
                abs (result - (-1.2)) < 1.0e-9 @?= True
          , testCase "valueFunctionLoss is mean squared error" $
              -- ((1-0)^2 + (2-0)^2 + (0-3)^2) / 3 = (1+4+9)/3 = 14/3
              let result = PpoLoss.valueFunctionLoss [1.0, 2.0, 0.0] [0.0, 0.0, 3.0]
               in abs (result - 14.0 / 3.0) < 1.0e-9 @?= True
          , testCase "gaeAdvantages on a single-step trajectory equals the TD residual" $
              -- delta = r + gamma*nv - v = 1 + 0.99*0 - 0 = 1
              -- A = delta + 0 = 1
              PpoLoss.gaeAdvantages 0.99 0.95 [1.0] [0.0] [0.0]
                @?= [1.0]
          , testCase "gaeAdvantages accumulates backwards with gamma*lambda decay" $
              -- deltas = [d0=1+0.99*0-0=1, d1=1+0.99*0-0=1]
              -- A1 = d1 + 0 = 1
              -- A0 = d0 + gamma*lambda*A1 = 1 + 0.99*0.95*1 = 1.9405
              case PpoLoss.gaeAdvantages 0.99 0.95 [1.0, 1.0] [0.0, 0.0] [0.0, 0.0] of
                [a0, a1] ->
                  (abs (a0 - 1.9405) < 1.0e-9, abs (a1 - 1.0) < 1.0e-9) @?= (True, True)
                other -> assertFailure ("expected 2 advantages, got: " <> show other)
          , testCase "normaliseAdvantages produces zero-mean unit-stdev output" $
              let xs = [1.0, 2.0, 3.0, 4.0, 5.0]
                  normalised = PpoLoss.normaliseAdvantages xs
                  meanZ = sum normalised / fromIntegral (length normalised)
                  sqDev z = (z - meanZ) * (z - meanZ)
                  varZ = sum (fmap sqDev normalised) / fromIntegral (length normalised)
               in (abs meanZ < 1.0e-6, abs (varZ - 1.0) < 1.0e-6) @?= (True, True)
          , testCase "approxKlDivergence is zero when policies coincide" $
              PpoLoss.approxKlDivergence [0.0, 0.0] [0.0, 0.0] @?= 0.0
          , testCase "approxKlDivergence is positive when new policy is less confident" $
              -- new = -1 (less confident), old = 0; KL ≈ mean(old - new) = 1.0
              PpoLoss.approxKlDivergence [0.0, 0.0] [-1.0, -1.0] @?= 1.0
          , testCase "ppoTotalLoss combines surrogate + value + entropy with the configured coefficients" $
              -- surrogate = -1.0 (from identical-policy + adv=1 case)
              -- value loss = 1.0 (predicted=0, target=1)
              -- entropy = 1.0
              -- total = -1.0 + 0.5*1.0 - 0.01*1.0 = -1 + 0.5 - 0.01 = -0.51
              let result =
                    PpoLoss.ppoTotalLoss 0.2 0.5 0.01 [0.0] [0.0] [1.0] [0.0] [1.0] 1.0
               in abs (result - (-0.51)) < 1.0e-9 @?= True
          , testCase "ppoTotalLoss is run-to-run deterministic on identical inputs" $
              let first = PpoLoss.ppoTotalLoss 0.2 0.5 0.01 [0.0, 0.1] [0.0, 0.1] [1.0, 0.5] [0.0, 0.0] [1.0, 1.0] 0.5
                  second = PpoLoss.ppoTotalLoss 0.2 0.5 0.01 [0.0, 0.1] [0.0, 0.1] [1.0, 0.5] [0.0, 0.0] [1.0, 1.0] 0.5
               in first @?= second
          ]
      , -- Sprint 13.8 — A2C real loss math.
        testGroup
          "A2C loss math (Sprint 13.8)"
          [ testCase "a2cPolicyGradientLoss returns 0 on empty batch" $
              A2cLoss.a2cPolicyGradientLoss [] [] @?= 0.0
          , testCase "a2cPolicyGradientLoss is mean(-log_prob * advantage)" $
              -- log_probs = [-1, -2], advantages = [1.0, 2.0]
              -- term = [-1, -4], mean = -5/2 = -2.5
              -- loss = -mean = 2.5
              A2cLoss.a2cPolicyGradientLoss [-1.0, -2.0] [1.0, 2.0] @?= 2.5
          , testCase "a2cTotalLoss combines policy gradient + value + entropy" $
              -- pg = 2.5 (from above)
              -- vf = ((0-1)^2 + (0-1)^2) / 2 = 1.0
              -- entropy = 1.0
              -- total = 2.5 + 0.5*1.0 - 0.01*1.0 = 2.99
              let result = A2cLoss.a2cTotalLoss 0.5 0.01 [-1.0, -2.0] [1.0, 2.0] [0.0, 0.0] [1.0, 1.0] 1.0
               in abs (result - 2.99) < 1.0e-9 @?= True
          , testCase "a2cTotalLoss is run-to-run deterministic" $
              let first = A2cLoss.a2cTotalLoss 0.5 0.01 [-1.0, -0.5] [1.0, 0.5] [0.0, 0.5] [1.0, 1.0] 0.5
                  second = A2cLoss.a2cTotalLoss 0.5 0.01 [-1.0, -0.5] [1.0, 0.5] [0.0, 0.5] [1.0, 1.0] 0.5
               in first @?= second
          ]
      , -- Sprint 13.8 — DQN real loss math.
        testGroup
          "DQN loss math (Sprint 13.8)"
          [ testCase "dqnBellmanTarget passes through reward on terminal step" $
              DqnLoss.dqnBellmanTarget 0.99 1.0 True 5.0 @?= 1.0
          , testCase "dqnBellmanTarget adds discounted maxQ on non-terminal step" $
              -- r + gamma * maxNext = 1.0 + 0.99 * 5.0 = 5.95
              DqnLoss.dqnBellmanTarget 0.99 1.0 False 5.0 @?= 5.95
          , testCase "dqnDoubleBellmanTarget uses the online-selected action's target value" $
              -- Same shape as Bellman; the caller has already selected the action.
              DqnLoss.dqnDoubleBellmanTarget 0.99 1.0 False 3.0 @?= 1.0 + 0.99 * 3.0
          , testCase "dqnTdResidual is (Q - target)" $
              DqnLoss.dqnTdResidual 2.0 0.5 @?= 1.5
          , testCase "dqnTdLoss is mean squared TD error" $
              -- residuals = [2-0, 0-2] = [2, -2], mse = (4+4)/2 = 4.0
              DqnLoss.dqnTdLoss [2.0, 0.0] [0.0, 2.0] @?= 4.0
          , testCase "dqnHuberLoss uses L2 within kappa and L1 beyond" $
              -- residual = 0.5 (within kappa=1.0): 0.5 * 0.5^2 = 0.125
              -- residual = 2.0 (beyond kappa): 1.0 * (2.0 - 0.5*1.0) = 1.5
              -- mean = (0.125 + 1.5) / 2 = 0.8125
              let result = DqnLoss.dqnHuberLoss 1.0 [0.5, 2.0] [0.0, 0.0]
               in abs (result - 0.8125) < 1.0e-9 @?= True
          , testCase "dqnHuberLoss is run-to-run deterministic" $
              let first = DqnLoss.dqnHuberLoss 1.0 [0.5, 2.0, -1.0] [0.0, 0.0, 0.0]
                  second = DqnLoss.dqnHuberLoss 1.0 [0.5, 2.0, -1.0] [0.0, 0.0, 0.0]
               in first @?= second
          ]
      , -- Sprint 13.8 — DDPG real loss math.
        testGroup
          "DDPG loss math (Sprint 13.8)"
          [ testCase "ddpgCriticTarget applies the deterministic-policy Bellman target" $
              -- rewards = [1, 1], terminals = [False, True], targetQ = [5, 5]
              -- → [1 + 0.99*5, 1] = [5.95, 1.0]
              DdpgLoss.ddpgCriticTarget 0.99 [1.0, 1.0] [False, True] [5.0, 5.0]
                @?= [5.95, 1.0]
          , testCase "ddpgActorLoss is -mean(Q(s, mu(s)))" $
              -- mean([2, 4]) = 3, loss = -3
              DdpgLoss.ddpgActorLoss [2.0, 4.0] @?= (-3.0)
          , testCase "ddpgActorLoss returns 0 on empty batch" $
              DdpgLoss.ddpgActorLoss [] @?= 0.0
          ]
      , -- Sprint 13.8 — TD3 real loss math.
        testGroup
          "TD3 loss math (Sprint 13.8)"
          [ testCase "td3ClippedDoubleTarget picks the minimum of Q1_target and Q2_target" $
              -- Q1 = [3, 5], Q2 = [4, 2], min = [3, 2]
              -- → [1 + 0.99*3, 1 + 0.99*2] = [3.97, 2.98]
              case Td3Loss.td3ClippedDoubleTarget 0.99 [1.0, 1.0] [False, False] [3.0, 5.0] [4.0, 2.0] of
                [a0, a1] -> (abs (a0 - 3.97) < 1.0e-9, abs (a1 - 2.98) < 1.0e-9) @?= (True, True)
                other -> assertFailure ("expected 2 outputs, got: " <> show other)
          , testCase "td3SmoothTargetActions clips both noise and action to ranges" $
              -- noiseClip = 0.5, actionRange = [-1.0, 1.0]
              -- actions = [0.0, 0.9], noise = [0.7, 0.3]
              -- clipped noise = [0.5, 0.3]
              -- smoothed = clip(0.0 + 0.5, ...) = 0.5; clip(0.9 + 0.3, ...) = 1.0
              Td3Loss.td3SmoothTargetActions 0.5 (-1.0) 1.0 [0.0, 0.9] [0.7, 0.3]
                @?= [0.5, 1.0]
          ]
      , -- Sprint 13.8 — SAC real loss math.
        testGroup
          "SAC loss math (Sprint 13.8)"
          [ testCase "sacCriticTarget subtracts alpha * log_pi from min(Q1, Q2)" $
              -- alpha = 0.2, rewards = [1], terminals = [False],
              -- Q1 = [3], Q2 = [4], min = [3], log_pi = [0.5]
              -- soft = 3 - 0.2*0.5 = 2.9
              -- target = 1 + 0.99 * 2.9 = 3.871
              case SacLoss.sacCriticTarget 0.99 0.2 [1.0] [False] [3.0] [4.0] [0.5] of
                [target] -> abs (target - 3.871) < 1.0e-9 @?= True
                other -> assertFailure ("expected 1 target, got: " <> show other)
          , testCase "sacActorLoss is mean(alpha * log_pi - Q_min)" $
              -- alpha = 0.2, log_pi = [0.5, 1.0], Q_min = [3, 4]
              -- terms = [0.2*0.5 - 3, 0.2*1.0 - 4] = [-2.9, -3.8]
              -- mean = -3.35
              let result = SacLoss.sacActorLoss 0.2 [0.5, 1.0] [3.0, 4.0]
               in abs (result - (-3.35)) < 1.0e-9 @?= True
          , testCase "sacTemperatureLoss drives alpha toward the target entropy" $
              -- alpha = 0.5, target_entropy = -2.0, log_pi = [1.0]
              -- term = -0.5 * (1.0 + (-2.0)) = -0.5 * -1.0 = 0.5
              let result = SacLoss.sacTemperatureLoss 0.5 (-2.0) [1.0]
               in abs (result - 0.5) < 1.0e-9 @?= True
          ]
      , -- Sprint 13.8 — QR-DQN real loss math.
        testGroup
          "QR-DQN loss math (Sprint 13.8)"
          [ testCase "quantileMidpoints emits (i + 0.5) / N for the canonical 4-atom case" $
              QrDqnLoss.quantileMidpoints 4 @?= [0.125, 0.375, 0.625, 0.875]
          , testCase "quantileMidpoints returns [] on non-positive N" $
              QrDqnLoss.quantileMidpoints 0 @?= []
          , testCase "quantileHuberLoss is asymmetric across the residual sign" $ do
              -- residual = 1.0 (positive), tau = 0.5, kappa = 1.0:
              -- asymmetric = |0.5 - 0| = 0.5; Huber = 0.5 * 1 * 1 = 0.5
              -- total = 0.25
              let result = QrDqnLoss.quantileHuberLoss 1.0 0.5 1.0
              abs (result - 0.25) < 1.0e-9 @?= True
              -- residual = -1.0, tau = 0.5: asymmetric = |0.5 - 1| = 0.5; Huber = 0.5
              -- total = 0.25 (symmetric here at tau=0.5).
              let result2 = QrDqnLoss.quantileHuberLoss 1.0 0.5 (-1.0)
              abs (result2 - 0.25) < 1.0e-9 @?= True
          , testCase "qrDqnLoss is run-to-run deterministic" $
              let predicted = [[0.1, 0.2, 0.3, 0.4]]
                  targets = [[0.15, 0.25, 0.35, 0.45]]
                  first = QrDqnLoss.qrDqnLoss 1.0 predicted targets
                  second = QrDqnLoss.qrDqnLoss 1.0 predicted targets
               in first @?= second
          ]
      , -- Sprint 13.8 — ARS update math.
        testGroup
          "ARS update math (Sprint 13.8)"
          [ testCase "arsTopDirections keeps the top-b perturbations by max(R+, R-)" $
              -- max returns = [10, 5, 8]; top-2 = [10, 8] → triples at index 0, 2
              ArsLoss.arsTopDirections
                2
                [ (10.0, 3.0, [1.0, 0.0])
                , (5.0, 5.0, [0.0, 1.0])
                , (8.0, 8.0, [1.0, 1.0])
                ]
                @?= [ (10.0, 3.0, [1.0, 0.0])
                    , (8.0, 8.0, [1.0, 1.0])
                    ]
          , testCase "arsUpdateDirection sums (R+ - R-) * delta across kept directions" $
              -- triples: (10, 3, [1, 0]) → (10-3)*[1, 0] = [7, 0]
              --          (8, 8, [1, 1]) → (8-8)*[1, 1] = [0, 0]
              -- total = [7, 0]
              ArsLoss.arsUpdateDirection
                [ (10.0, 3.0, [1.0, 0.0])
                , (8.0, 8.0, [1.0, 1.0])
                ]
                @?= [7.0, 0.0]
          , testCase "arsUpdateDirection returns empty on no triples" $
              ArsLoss.arsUpdateDirection [] @?= []
          ]
      , -- Sprint 13.8 — TRPO real loss math.
        testGroup
          "TRPO loss math (Sprint 13.8)"
          [ testCase "trpoSurrogate is -mean(ratio * advantage)" $
              -- ratio = exp(0) = 1, adv = 1, term = 1, mean = 1, loss = -1
              TrpoLoss.trpoSurrogate [0.0] [0.0] [1.0] @?= (-1.0)
          , testCase "trpoKlConstraintSatisfied accepts step within delta" $ do
              -- KL = mean(old - new) = mean(0 - 0) = 0 ≤ 0.01
              TrpoLoss.trpoKlConstraintSatisfied 0.01 [0.0] [0.0] @?= True
              -- KL = mean(0 - (-1)) = 1 > 0.01
              TrpoLoss.trpoKlConstraintSatisfied 0.01 [0.0] [-1.0] @?= False
          ]
      , -- Sprint 13.8 — MaskablePPO action masking.
        testGroup
          "MaskablePPO masking (Sprint 13.8)"
          [ testCase "applyActionMask zeros illegal actions and renormalises" $
              -- mask = [T, F, T], probs = [0.4, 0.4, 0.2]
              -- masked = [0.4, 0, 0.2], sum = 0.6
              -- normalised = [0.4/0.6, 0, 0.2/0.6]
              let result = MaskablePpoLoss.applyActionMask [True, False, True] [0.4, 0.4, 0.2]
                  expected = [0.4 / 0.6, 0.0, 0.2 / 0.6]
                  closeEnough = all (\(a, b) -> abs (a - b) < 1.0e-9) (zip result expected)
               in closeEnough @?= True
          , testCase "applyActionMask returns probs unchanged on length mismatch" $
              MaskablePpoLoss.applyActionMask [True, True] [0.5, 0.3, 0.2]
                @?= [0.5, 0.3, 0.2]
          ]
      , -- Sprint 13.8 — RecurrentPPO BPTT windowing.
        testGroup
          "RecurrentPPO BPTT windowing (Sprint 13.8)"
          [ testCase "bpttWindows splits a trajectory into windows" $
              RecurrentPpoLoss.bpttWindows 3 ([1, 2, 3, 4, 5, 6, 7] :: [Int])
                @?= [[1, 2, 3], [4, 5, 6], [7]]
          , testCase "bpttWindows treats non-positive window as a single bucket" $
              RecurrentPpoLoss.bpttWindows 0 ([1, 2, 3] :: [Int]) @?= [[1, 2, 3]]
          , testCase "bpttWindows returns [] on empty trajectory" $
              RecurrentPpoLoss.bpttWindows 4 ([] :: [Int]) @?= []
          ]
      , -- Sprint 13.8 — CrossQ batch normalisation.
        testGroup
          "CrossQ loss math (Sprint 13.8)"
          [ testCase "crossQNormalise centres and scales the input" $
              -- mean = 2.0, var = 1.0, eps = 0
              -- q = 3 → (3 - 2)/sqrt(1) = 1.0
              -- q = 2 → 0.0
              -- q = 1 → -1.0
              CrossQLoss.crossQNormalise 2.0 1.0 0 [3.0, 2.0, 1.0]
                @?= [1.0, 0.0, -1.0]
          , testCase "crossQTarget subtracts alpha * log_pi from normalised Q" $
              -- gamma = 0.99, alpha = 0.2, reward = 1, terminal = False,
              -- qNorm = [3], log_pi = [0.5]
              -- soft = 3 - 0.2*0.5 = 2.9
              -- target = 1 + 0.99 * 2.9 = 3.871
              case CrossQLoss.crossQTarget 0.99 0.2 [1.0] [False] [3.0] [0.5] of
                [target] -> abs (target - 3.871) < 1.0e-9 @?= True
                other -> assertFailure ("expected 1 target, got: " <> show other)
          ]
      , -- Sprint 13.8 — TQC truncated quantile pooling.
        testGroup
          "TQC loss math (Sprint 13.8)"
          [ testCase "poolAndTruncate drops the top atoms after pooling all critics" $
              -- 3 critics × 2 atoms = 6 atoms total: [5,3, 4,2, 6,1]
              -- sorted = [1, 2, 3, 4, 5, 6]
              -- drop top 1 per critic × 3 critics = drop 3 → [1, 2, 3]
              TqcLoss.poolAndTruncate 1 [[5.0, 3.0], [4.0, 2.0], [6.0, 1.0]]
                @?= [1.0, 2.0, 3.0]
          , testCase "tqcTarget collapses to a point mass on terminal step" $
              TqcLoss.tqcTarget 0.99 1 1.0 True [[1.0, 2.0]] 0.1 @?= [1.0]
          , testCase "tqcTarget shifts the truncated atoms by the reward" $
              -- gamma = 1.0 for an easy check, drop none, softTerm = 0
              -- critics = [[1, 2]], truncated = [1, 2]
              -- shifted = [r + 1*(1-0), r + 1*(2-0)] = [r+1, r+2]
              TqcLoss.tqcTarget 1.0 0 5.0 False [[1.0, 2.0]] 0.0 @?= [6.0, 7.0]
          ]
      , -- Sprint 13.8 — HER goal relabeling.
        testGroup
          "HER relabeling (Sprint 13.8)"
          [ testCase "sparseGoalReward returns 0 within epsilon, -1 beyond" $ do
              -- distance = abs(x - g); epsilon = 0.5
              let distance x g = abs (x - g)
              HerLoss.sparseGoalReward distance 0.5 0.3 0.0 @?= 0.0
              HerLoss.sparseGoalReward distance 0.5 1.0 0.0 @?= (-1.0)
          , testCase "herRelabel substitutes the new goal and recomputes the reward" $
              -- (s, a, s', terminal) = (0.0, 1, 0.4, False), newGoal = 0.5
              -- distance = |0.4 - 0.5| = 0.1, within eps=0.5 → reward = 0
              let distance x g = abs (x - g)
                  result =
                    HerLoss.herRelabel
                      distance
                      0.5
                      (0.5 :: Double)
                      (0.0 :: Double, 1, 0.4, False)
               in (HerLoss.relRelabeledGoal result, HerLoss.relRelabeledReward result)
                    @?= (0.5, 0.0)
          ]
      , testGroup
          "Differentiable MLP (Sprint 13.8 + 13.9)"
          [ testCase "mlpForward output dim matches shape outputs" $ do
              let shape = Mlp.MlpShape 4 8 3
                  params = Mlp.mlpInit shape 7
                  fwd = Mlp.mlpForward params (Data.Vector.Unboxed.fromList [0.1, 0.2, 0.3, 0.4])
              Data.Vector.Unboxed.length (Mlp.forwardOutput fwd) @?= 3
          , testCase "mlpForward is run-to-run deterministic on same seed" $ do
              let shape = Mlp.MlpShape 4 8 3
                  paramsA = Mlp.mlpInit shape 99
                  paramsB = Mlp.mlpInit shape 99
                  inp = Data.Vector.Unboxed.fromList [1.0, -0.5, 0.25, 0.0]
                  fa = Mlp.forwardOutput (Mlp.mlpForward paramsA inp)
                  fb = Mlp.forwardOutput (Mlp.mlpForward paramsB inp)
              fa @?= fb
          , testCase "Adam step reduces a quadratic loss after enough updates" $ do
              -- Minimal sanity: train a 1-hidden-unit MLP to drive output → 1.0
              -- given a fixed input. The Adam update direction must be correct.
              let shape = Mlp.MlpShape 1 4 1
                  initialParams = Mlp.mlpInit shape 13
                  adamConfig =
                    Mlp.defaultAdamConfig {Mlp.adamLearningRate = 0.05}
                  initialAdam = Mlp.adamInit shape
                  target = Data.Vector.Unboxed.fromList [1.0]
                  inp = Data.Vector.Unboxed.fromList [0.5]
                  stepOnce (p, a) _ =
                    let fwd = Mlp.mlpForward p inp
                        out = Mlp.forwardOutput fwd
                        dLdy = Data.Vector.Unboxed.zipWith (-) out target
                        grad = Mlp.mlpBackward p fwd dLdy
                     in Mlp.adamStep adamConfig a p grad
                  (trainedParams, _) = foldl stepOnce (initialParams, initialAdam) [1 :: Int .. 200]
                  initialOut =
                    Data.Vector.Unboxed.head
                      (Mlp.forwardOutput (Mlp.mlpForward initialParams inp))
                  finalOut =
                    Data.Vector.Unboxed.head
                      (Mlp.forwardOutput (Mlp.mlpForward trainedParams inp))
              assertBool
                ( "Adam should move output toward target; initial="
                    <> show initialOut
                    <> " final="
                    <> show finalOut
                )
                (abs (finalOut - 1.0) < abs (initialOut - 1.0))
          , testCase "policyValueForward produces normalised policy" $ do
              let shape = Mlp.MlpShape 4 8 3
                  params = Mlp.mlpInit shape 5
                  inp = Data.Vector.Unboxed.fromList [0.0, 0.0, 0.0, 0.0]
                  pv = Mlp.policyValueForward params 2 inp
                  total = Data.Vector.Unboxed.sum (Mlp.pvPolicy pv)
              Data.Vector.Unboxed.length (Mlp.pvPolicy pv) @?= 2
              assertBool ("policy should sum to 1; got " <> show total) (abs (total - 1.0) < 1.0e-9)
              assertBool "value head is tanh-bounded" (abs (Mlp.pvValue pv) <= 1.0)
          , testCase "sampleCategorical maps uniform to expected bucket" $ do
              let probs = Data.Vector.Unboxed.fromList [0.25, 0.25, 0.5 :: Double]
              Mlp.sampleCategorical probs 0.1 @?= 0
              Mlp.sampleCategorical probs 0.3 @?= 1
              Mlp.sampleCategorical probs 0.6 @?= 2
              Mlp.sampleCategorical probs 0.99 @?= 2
          ]
      , testGroup
          "PPO trainer end-to-end (Sprint 13.8)"
          [ testCase "trainPpoOnCartpole produces stats for each iteration" $ do
              let smallConfig =
                    PpoTrainer.defaultPpoTrainConfig
                      { PpoTrainer.ppoSeed = 7
                      , PpoTrainer.ppoRolloutSteps = 64
                      , PpoTrainer.ppoNumIterations = 3
                      , PpoTrainer.ppoEpochsPerUpdate = 2
                      }
              result <- PpoTrainer.trainPpoOnCartpole smallConfig
              length (PpoTrainer.resultIterations result) @?= 3
          , testCase "PPO training is run-to-run deterministic on the same seed" $ do
              let smallConfig =
                    PpoTrainer.defaultPpoTrainConfig
                      { PpoTrainer.ppoSeed = 17
                      , PpoTrainer.ppoRolloutSteps = 64
                      , PpoTrainer.ppoNumIterations = 2
                      , PpoTrainer.ppoEpochsPerUpdate = 1
                      }
              resultA <- PpoTrainer.trainPpoOnCartpole smallConfig
              resultB <- PpoTrainer.trainPpoOnCartpole smallConfig
              fmap PpoTrainer.iterMeanReward (PpoTrainer.resultIterations resultA)
                @?= fmap PpoTrainer.iterMeanReward (PpoTrainer.resultIterations resultB)
          ]
      , testGroup
          "DQN trainer (Sprint 13.8 off-policy seam)"
          [ testCase "DQN training runs end-to-end and emits stats" $ do
              let smallConfig =
                    DqnTrainer.defaultDqnTrainConfig
                      { DqnTrainer.dqnSeed = 11
                      , DqnTrainer.dqnNumSteps = 2000
                      , DqnTrainer.dqnTrainStart = 200
                      , DqnTrainer.dqnTargetUpdateInterval = 200
                      , DqnTrainer.dqnStatInterval = 500
                      , DqnTrainer.dqnReplayCapacity = 500
                      }
              result <- DqnTrainer.trainDqnOnCartpole smallConfig
              assertBool
                "DQN trainer emitted at least one stat"
                (not (null (DqnTrainer.dqnResultStats result)))
          , testCase "DQN training is run-to-run deterministic on the same seed" $ do
              let smallConfig =
                    DqnTrainer.defaultDqnTrainConfig
                      { DqnTrainer.dqnSeed = 23
                      , DqnTrainer.dqnNumSteps = 1000
                      , DqnTrainer.dqnTrainStart = 100
                      , DqnTrainer.dqnTargetUpdateInterval = 100
                      , DqnTrainer.dqnStatInterval = 500
                      , DqnTrainer.dqnReplayCapacity = 200
                      }
              resultA <- DqnTrainer.trainDqnOnCartpole smallConfig
              resultB <- DqnTrainer.trainDqnOnCartpole smallConfig
              fmap DqnTrainer.dqnIterMeanReward (DqnTrainer.dqnResultStats resultA)
                @?= fmap DqnTrainer.dqnIterMeanReward (DqnTrainer.dqnResultStats resultB)
          , testCase "Double-DQN variant trains end-to-end and stays deterministic" $ do
              let doubleConfig =
                    DqnTrainer.defaultDqnTrainConfig
                      { DqnTrainer.dqnSeed = 31
                      , DqnTrainer.dqnNumSteps = 1500
                      , DqnTrainer.dqnTrainStart = 200
                      , DqnTrainer.dqnTargetUpdateInterval = 150
                      , DqnTrainer.dqnStatInterval = 500
                      , DqnTrainer.dqnReplayCapacity = 400
                      , DqnTrainer.dqnUseDouble = True
                      }
              resultA <- DqnTrainer.trainDqnOnCartpole doubleConfig
              resultB <- DqnTrainer.trainDqnOnCartpole doubleConfig
              assertBool
                "Double-DQN emitted at least one stat"
                (not (null (DqnTrainer.dqnResultStats resultA)))
              fmap DqnTrainer.dqnIterMeanReward (DqnTrainer.dqnResultStats resultA)
                @?= fmap DqnTrainer.dqnIterMeanReward (DqnTrainer.dqnResultStats resultB)
          ]
      , testGroup
          "Continuous actor-critic trainer (Sprint 13.8 DDPG/TD3/SAC/CrossQ/TQC)"
          [ testCase (show variant <> " trains end-to-end and is run-to-run deterministic") $ do
              resultA <- ContinuousTrainer.trainContinuousOnPendulum (smallContConfig variant)
              resultB <- ContinuousTrainer.trainContinuousOnPendulum (smallContConfig variant)
              assertBool
                (show variant <> " emitted at least one stat")
                (not (null (ContinuousTrainer.contResultStats resultA)))
              assertBool
                (show variant <> " produced finite episode rewards")
                ( not
                    ( any
                        (isNaN . ContinuousTrainer.contIterMeanReward)
                        (ContinuousTrainer.contResultStats resultA)
                    )
                )
              fmap ContinuousTrainer.contIterMeanReward (ContinuousTrainer.contResultStats resultA)
                @?= fmap ContinuousTrainer.contIterMeanReward (ContinuousTrainer.contResultStats resultB)
          | variant <-
              [ ContinuousTrainer.VariantDDPG
              , ContinuousTrainer.VariantTD3
              , ContinuousTrainer.VariantSAC
              , ContinuousTrainer.VariantCrossQ
              , ContinuousTrainer.VariantTQC
              ]
          ]
      , testGroup
          "QR-DQN trainer (Sprint 13.8 distributional off-policy)"
          [ testCase "QR-DQN trains end-to-end and emits stats" $ do
              let cfg =
                    QrDqnTrainer.defaultQrDqnTrainConfig
                      { QrDqnTrainer.qrSeed = 13
                      , QrDqnTrainer.qrNumQuantiles = 5
                      , QrDqnTrainer.qrHiddenUnits = 16
                      , QrDqnTrainer.qrNumSteps = 1500
                      , QrDqnTrainer.qrTrainStart = 100
                      , QrDqnTrainer.qrTargetUpdateInterval = 150
                      , QrDqnTrainer.qrStatInterval = 500
                      , QrDqnTrainer.qrReplayCapacity = 400
                      }
              result <- QrDqnTrainer.trainQrDqnOnCartpole cfg
              assertBool
                "QR-DQN emitted at least one stat"
                (not (null (QrDqnTrainer.qrResultStats result)))
          , testCase "QR-DQN is run-to-run deterministic on the same seed" $ do
              let cfg =
                    QrDqnTrainer.defaultQrDqnTrainConfig
                      { QrDqnTrainer.qrSeed = 27
                      , QrDqnTrainer.qrNumQuantiles = 4
                      , QrDqnTrainer.qrHiddenUnits = 16
                      , QrDqnTrainer.qrNumSteps = 1000
                      , QrDqnTrainer.qrTrainStart = 100
                      , QrDqnTrainer.qrStatInterval = 500
                      , QrDqnTrainer.qrReplayCapacity = 300
                      }
              resultA <- QrDqnTrainer.trainQrDqnOnCartpole cfg
              resultB <- QrDqnTrainer.trainQrDqnOnCartpole cfg
              fmap QrDqnTrainer.qrIterMeanReward (QrDqnTrainer.qrResultStats resultA)
                @?= fmap QrDqnTrainer.qrIterMeanReward (QrDqnTrainer.qrResultStats resultB)
          ]
      , testGroup
          "ARS trainer (Sprint 13.8 gradient-free)"
          [ testCase "ARS trains end-to-end and is run-to-run deterministic" $ do
              let cfg =
                    ArsTrainer.defaultArsTrainConfig
                      { ArsTrainer.arsSeed = 5
                      , ArsTrainer.arsIterations = 20
                      , ArsTrainer.arsNumDirections = 8
                      , ArsTrainer.arsTopB = 4
                      , ArsTrainer.arsMaxEpisodeSteps = 200
                      }
              resultA <- ArsTrainer.trainArsOnCartpole cfg
              resultB <- ArsTrainer.trainArsOnCartpole cfg
              assertBool
                "ARS emitted at least one stat"
                (not (null (ArsTrainer.arsResultStats resultA)))
              fmap ArsTrainer.arsIterBestReturn (ArsTrainer.arsResultStats resultA)
                @?= fmap ArsTrainer.arsIterBestReturn (ArsTrainer.arsResultStats resultB)
          , testCase "ARS improves the mean episode return over the run" $ do
              let cfg =
                    ArsTrainer.defaultArsTrainConfig
                      { ArsTrainer.arsSeed = 9
                      , ArsTrainer.arsIterations = 40
                      , ArsTrainer.arsNumDirections = 16
                      , ArsTrainer.arsTopB = 8
                      , ArsTrainer.arsMaxEpisodeSteps = 500
                      }
              result <- ArsTrainer.trainArsOnCartpole cfg
              let means = fmap ArsTrainer.arsIterMeanReturn (ArsTrainer.arsResultStats result)
              case (means, reverse means) of
                (firstMean : _, lastMean : _) ->
                  assertBool
                    ("ARS mean return should improve; first=" <> show firstMean <> " last=" <> show lastMean)
                    (lastMean > firstMean)
                _ -> assertBool "ARS produced no stats" False
          ]
      , testGroup
          "HER trainer (Sprint 13.8 goal-conditioned)"
          [ testCase "HER trains end-to-end and is run-to-run deterministic" $ do
              let cfg =
                    HerTrainer.defaultHerTrainConfig
                      { HerTrainer.herSeed = 3
                      , HerTrainer.herNumBits = 5
                      , HerTrainer.herHiddenUnits = 32
                      , HerTrainer.herEpisodes = 120
                      , HerTrainer.herStatInterval = 40
                      , HerTrainer.herReplayCapacity = 2000
                      }
              resultA <- HerTrainer.trainHerOnBitFlip cfg
              resultB <- HerTrainer.trainHerOnBitFlip cfg
              assertBool
                "HER emitted at least one stat"
                (not (null (HerTrainer.herResultStats resultA)))
              fmap HerTrainer.herIterSuccessRate (HerTrainer.herResultStats resultA)
                @?= fmap HerTrainer.herIterSuccessRate (HerTrainer.herResultStats resultB)
          , testCase "hindsight relabeling beats no-hindsight on bit-flip success rate" $ do
              let base =
                    HerTrainer.defaultHerTrainConfig
                      { HerTrainer.herSeed = 8
                      , HerTrainer.herNumBits = 5
                      , HerTrainer.herHiddenUnits = 32
                      , HerTrainer.herEpisodes = 300
                      , HerTrainer.herStatInterval = 50
                      , HerTrainer.herReplayCapacity = 4000
                      }
              withHer <- HerTrainer.trainHerOnBitFlip base {HerTrainer.herUseHindsight = True}
              withoutHer <- HerTrainer.trainHerOnBitFlip base {HerTrainer.herUseHindsight = False}
              let finalRate r =
                    case reverse (HerTrainer.herResultStats r) of
                      (s : _) -> HerTrainer.herIterSuccessRate s
                      [] -> 0.0
                  herRate = finalRate withHer
                  noHerRate = finalRate withoutHer
              assertBool
                ("hindsight should help; HER=" <> show herRate <> " noHER=" <> show noHerRate)
                (herRate >= noHerRate)
          ]
      ]

-- | Small continuous-trainer config for fast unit-test runs.
smallContConfig
  :: ContinuousTrainer.ContinuousVariant -> ContinuousTrainer.ContinuousTrainConfig
smallContConfig variant =
  (ContinuousTrainer.defaultContinuousTrainConfig variant)
    { ContinuousTrainer.ctSeed = 19
    , ContinuousTrainer.ctHidden = 16
    , ContinuousTrainer.ctNumSteps = 400
    , ContinuousTrainer.ctReplayCapacity = 400
    , ContinuousTrainer.ctBatchSize = 16
    , ContinuousTrainer.ctStartSteps = 50
    , ContinuousTrainer.ctTrainStart = 50
    , ContinuousTrainer.ctMaxEpisodeSteps = 40
    , ContinuousTrainer.ctStatInterval = 100
    }

takeFileNameCompat :: FilePath -> FilePath
takeFileNameCompat path =
  reverse (takeWhile (/= '/') (dropWhile (== '/') (reverse path)))

sampleCacheHash :: Cache.Hash
sampleCacheHash =
  Cache.cacheKey
    (Cache.KernelSpec "phase-2-kernel:linear")
    Cache.Training
    Cache.AppleSilicon
    (Cache.ToolchainFingerprint "llvm=ghc-9.12.4;xcode-metal=pinned;tuning=default")
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
      "ghc-9.12.4"
      "GHC 9.12.4 is required."
      (Just "ghcup install ghc 9.12.4")
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
  , AppError.InferenceCheckpointMissing "abc123"
  , AppError.InferenceManifestShaMismatch "abc123" "deadbeef"
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
  , ["rl", "alphazero", "self-play"]
  , ["verify", "same-run"]
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
  , ["test", "jitml-backends"]
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
  , ["internal", "install-metal-bridge"]
  , ["internal", "upload-dataset"]
  , ["internal", "gc"]
  , ["internal", "cache", "stat"]
  , ["internal", "cache", "list"]
  , ["internal", "cache", "evict"]
  , ["commands"]
  , ["help"]
  ]

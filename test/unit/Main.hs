{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Exception (IOException, bracket_, finally, try)
import Control.Exception qualified as Exception
import Control.Monad qualified
import Control.Monad.Catch (ExitCase (..))
import Data.Aeson (FromJSON (..), Value, decode, eitherDecode, encode, withObject, (.:))
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as ByteString
import Data.Char (isDigit)
import Data.Foldable (traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, isInfixOf, nub)
import Data.List qualified as List
import Data.Maybe (fromMaybe, isNothing, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure)
import Path (toFilePath)
import Path.IO (resolveDir')
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesFileExist
  , getCurrentDirectory
  , getPermissions
  , removeFile
  , setCurrentDirectory
  , setOwnerExecutable
  , setPermissions
  )
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Info qualified as SystemInfo
import System.Timeout (timeout)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.QuickCheck qualified as QuickCheck

import DurableStateTopology (durableStateTopologyTests)
import ReconcileStamp qualified
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Data.Vector.Unboxed qualified
import JitML.App
  ( alphaZeroArtifactStep
  , inferenceReplyAppError
  , matchingInferenceResult
  , parseUserIntOptionAtLeast
  , rlTrainerEnvironmentCompatibilityError
  , serviceRoleInvocationError
  )
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
import JitML.Coordinator.Topology qualified as Topology
import JitML.Docs.Check qualified as DocsCheck
import JitML.Engines.CpuFeatures qualified as CpuFeatures
import JitML.Engines.CublasBindings qualified as Cublas
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.CudnnBindings qualified as Cudnn
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.Loader qualified as Loader
import JitML.Engines.Local qualified as LocalEngine
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.MlpCheckpoint qualified as MlpCheckpoint
import JitML.Engines.OneDnnRuntime qualified as OneDnnRuntime
import JitML.Engines.Rng qualified as Rng
import JitML.Engines.Tuning qualified as Tuning
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Engines.TuningCache qualified as TuningCache
import JitML.Engines.TuningStore qualified as TuningStore
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env (..), OutputFormat (..))
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Generated.Paths
  ( TrackedGeneratedPath (..)
  , trackingGeneratedPaths
  )
import JitML.Generated.Registry
  ( GeneratedSectionRule (..)
  , generatedSectionRules
  )
import JitML.Inference.AdversarialMove qualified as AdversarialMove
import JitML.Inference.Decode qualified as Decode
import JitML.Lint.Chart (checkChartFiles)
import JitML.Lint.DhallNumerics (checkDhallNumerics)
import JitML.Lint.DhallRL (checkDhallRL)
import JitML.Lint.ProductTruth qualified as ProductTruth
import JitML.Lint.Stack.Types (LintFinding (..))
import JitML.Numerics.Autodiff qualified as Autodiff
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Numerics.Schema
  ( loadNumericsCatalog
  , validateNumericsCatalog
  )
import JitML.Observability.Grafana qualified as Grafana
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Plan (PlanId, buildCommandPlan, refinePlanIdText)
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
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.ExternalBars qualified as ProductExternalBars
import JitML.Product.Matrix (ModelState (..), ProductRow (..))
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.PhaseStatus
  ( ProductPhaseStatus (..)
  , ProductSprintStatus (..)
  , SprintStatus (..)
  )
import JitML.Product.PhaseStatus qualified as PhaseStatus
import JitML.Product.Pipeline qualified as ProductPipeline
import JitML.Proto.Gc qualified as ProtoGc
import JitML.Proto.Inference qualified as ProtoInference
import JitML.Proto.Wire qualified as ProtoWire
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms qualified as RLAlgorithms
import JitML.RL.Algorithms.A2cLoss qualified as A2cLoss
import JitML.RL.Algorithms.ArsLoss qualified as ArsLoss
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.Common qualified as AlgorithmCommon
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
import JitML.RL.Algorithms.Registry qualified as AlgorithmRegistry
import JitML.RL.Algorithms.SacLoss qualified as SacLoss
import JitML.RL.Algorithms.Td3Loss qualified as Td3Loss
import JitML.RL.Algorithms.TqcLoss qualified as TqcLoss
import JitML.RL.Algorithms.Trpo qualified as Trpo
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.RL.ConvergenceThresholds qualified as ConvergenceThresholds
import JitML.RL.Environments qualified as RLEnvironments
import JitML.RL.Framework qualified as RLFramework
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Schema (loadRlCatalogSchema, validateRlCatalogSchema)
import JitML.RL.Simulator qualified as Sim
import JitML.Routes qualified as Routes
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.CatalogSchema (catalogFileSchemas)
import JitML.Service.DhallSchema
  ( bootConfigSchema
  , canonicalDhallType
  , configSchemas
  , liveConfigSchema
  , runSchemaDhall
  )
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.InferenceReplyScope (runInferenceReplyScope, runInferenceReplyScopeObserved)
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Retry qualified as ServiceRetry
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.WebSocket qualified as WS
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessAttemptFailure (..)
  , ProcessDuration (..)
  , ProcessFailure
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , mkProcessFailure
  , observedProcessFailureCommand
  , observedProcessFailureExitCode
  , processFailureCommand
  , processFailureDuration
  , processFailureExitCode
  , processFailureStderr
  , processFailureStdout
  , processFailureWorkingDirectory
  , processOutcome
  , renderProcessOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream
  ( defaultSubprocessEnv
  , observeProcessAction
  , runStreaming
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate qualified as Substrate
import JitML.Test.HostWorkloadRegistry qualified as HostWorkloadRegistry
import JitML.Test.InferenceBatch qualified as InferenceBatch
import JitML.Test.LiveE2EScope qualified as LiveE2EScope
import JitML.Test.LivePlan
  ( LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  )
import JitML.Test.PipedProcess qualified as PipedProcess
import JitML.Test.PulsarBridge qualified as PulsarBridge
import JitML.Test.PulsarTransport qualified as PulsarTransport
import JitML.Test.Report qualified as Report
import JitML.Test.RunContract qualified as RunContractTest
import JitML.Test.RunPlan qualified as RunPlanTest
import JitML.Test.RuntimeState qualified as RuntimeStateTest
import JitML.Test.ScenarioJournal qualified as ScenarioJournal
import JitML.Test.WorkflowMatrix qualified as WorkflowMatrix
import JitML.Test.Workload qualified as WorkloadTest
import JitML.Test.WorkloadContract qualified as WorkloadContractTest
import JitML.Test.WorkloadPlan qualified as WorkloadPlanTest
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune
import JitML.Web.AdminPortals qualified as WebAdminPortals
import JitML.Web.Bundle qualified as WebBundle
import JitML.Web.Contracts qualified as WebContracts
import JitML.Work.Envelope qualified as Work
import ProtocolCodec qualified

newtype CommandSchema = CommandSchema
  { schemaCommands :: [Value]
  }
  deriving stock (Eq, Show)

completedTestManifest :: Word64 -> Checkpoint.CheckpointManifest
completedTestManifest step =
  let metrics = [("validation_accuracy", 0.95)]
      evidence =
        either
          (error . Text.unpack)
          id
          ( ProductEvidence.mkTrainingEvidence
              "unit-initial-weights"
              ("unit-final-weights-" <> Text.pack (show step))
              (max 1 step)
              "unit-dataset-sha"
          )
      observations =
        either
          (error . Text.unpack)
          id
          (convergenceObservationsFixture metrics)
      completed =
        either
          (error . Text.unpack)
          id
          ( TrainingBudget.completedTraining
              unitFixturePlanId
              (unitBudget TrainingBudget.SupervisedEpochBudget (max 1 step))
              step
              evidence
              observations
              TrainingBudget.TensorBoardRunMetadata
                { TrainingBudget.tbrRunId = "unit-test"
                , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/unit-test"
                , TrainingBudget.tbrScalarTags = fmap fst metrics
                }
          )
      manifest =
        (Checkpoint.emptyManifest "m" "exp1" [])
          { Checkpoint.manifestStep = step
          , Checkpoint.manifestMetrics = metrics
          }
   in Checkpoint.attachCompletedTraining completed manifest

unitFixturePlanId :: PlanId
unitFixturePlanId =
  either (error . Text.unpack) id (refinePlanIdText (Text.replicate 64 "e"))

unitBudget
  :: TrainingBudget.BudgetKind -> Word64 -> TrainingBudget.TrainingBudget
unitBudget kind target =
  either
    (error . Text.unpack)
    id
    (TrainingBudget.mkTrainingBudget kind target Nothing)

completedTrainingFixture :: Word64 -> TrainingBudget.CompletedTraining
completedTrainingFixture step =
  case Checkpoint.manifestCompletedTraining (completedTestManifest step) of
    Nothing -> error "completedTestManifest did not attach completed training"
    Just completed -> completed

convergenceObservationsFixture
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsFixture =
  ProductExternalBars.convergenceObservationsForMetrics

canonicalRlUnits :: Text -> Text -> Either Text Word64
canonicalRlUnits = ProductBudget.canonicalProductRlTargetUnits

assertCanonicalRlBudget
  :: ProductMatrix.ProductRow state
  -> Text
  -> Text
  -> Assertion
assertCanonicalRlBudget row algorithm environment =
  case canonicalRlUnits algorithm environment of
    Left err -> assertFailure (Text.unpack err)
    Right expected ->
      TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row)
        @?= expected

assertCanonicalRlScheduleIsExact
  :: ProductMatrix.ProductRow state
  -> Text
  -> Text
  -> Assertion
assertCanonicalRlScheduleIsExact row algorithm environment =
  case ProductBudget.canonicalProductRlSchedule algorithm environment of
    Left err -> assertFailure (Text.unpack err)
    Right canonical ->
      ProductBudget.planExactRlTrainingSchedule
        (ProductBudget.trainerKindForAlgorithm algorithm)
        environment
        ProductBudget.productRlDefaultEvaluationEpisodes
        ProductBudget.productRlDefaultMaxEpisodeSteps
        Nothing
        (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row))
        @?= Right canonical

readPlanSprintStatuses :: ProductPhaseStatus -> IO [(Text, SprintStatus)]
readPlanSprintStatuses phase = do
  content <- Text.IO.readFile (phaseDocument phase)
  case parsePlanSprintStatuses (Text.pack (phaseDocument phase)) content of
    Left err -> assertFailure (Text.unpack err)
    Right statuses -> pure statuses

parsePlanSprintStatuses :: Text -> Text -> Either Text [(Text, SprintStatus)]
parsePlanSprintStatuses path =
  go Nothing [] . Text.lines
 where
  go _ statuses [] = Right (reverse statuses)
  go _ statuses (line : rest)
    | Just sprintId' <- parseSprintHeader line =
        go (Just sprintId') statuses rest
  go (Just sprintId') statuses (line : rest)
    | Just rawStatus <- Text.stripPrefix "**Status**:" (Text.strip line) =
        case PhaseStatus.parseSprintStatus rawStatus of
          Just status -> go Nothing ((sprintId', status) : statuses) rest
          Nothing ->
            Left $
              path
                <> ": unknown sprint status "
                <> Text.strip rawStatus
                <> " for "
                <> sprintId'
  go activeSprint statuses (_ : rest) =
    go activeSprint statuses rest

parseSprintHeader :: Text -> Maybe Text
parseSprintHeader line =
  case Text.stripPrefix "## Sprint " (Text.strip line) of
    Nothing -> Nothing
    Just rest ->
      let sprintId' = Text.takeWhile isSprintIdChar rest
       in if Text.null sprintId' then Nothing else Just sprintId'
 where
  isSprintIdChar char =
    char == '.' || isDigit char

registrySprintStatuses :: ProductPhaseStatus -> [(Text, SprintStatus)]
registrySprintStatuses phase =
  [ (sprintId sprint', sprintStatus sprint')
  | sprint' <- phaseSprints phase
  ]

markProductPhaseDone :: ProductPhaseStatus -> ProductPhaseStatus
markProductPhaseDone phase =
  phase {phaseSprints = fmap markSprintDone (phaseSprints phase)}

markSprintDone :: ProductSprintStatus -> ProductSprintStatus
markSprintDone sprint' =
  sprint' {sprintStatus = Done}

demoteFirstProductSprint :: [ProductPhaseStatus] -> [ProductPhaseStatus]
demoteFirstProductSprint [] = []
demoteFirstProductSprint (phase : rest) =
  phase {phaseSprints = demoteFirstSprint (phaseSprints phase)} : rest

demoteFirstSprint :: [ProductSprintStatus] -> [ProductSprintStatus]
demoteFirstSprint [] = []
demoteFirstSprint (sprint' : rest) =
  sprint' {sprintStatus = Active} : rest

instance FromJSON CommandSchema where
  parseJSON =
    withObject "CommandSchema" $ \object ->
      CommandSchema <$> object .: "commands"

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-unit"
      [ durableStateTopologyTests
      , ReconcileStamp.reconcileStampTests
      , HostWorkloadRegistry.hostWorkloadRegistryTests
      , InferenceBatch.inferenceBatchTests
      , PipedProcess.pipedProcessTests
      , ProtocolCodec.protocolCodecTests
      , PulsarBridge.pulsarBridgeTests
      , PulsarTransport.pulsarTransportTests
      , RunContractTest.runContractTests
      , RunPlanTest.runPlanTests
      , WorkloadContractTest.workloadContractTests
      , WorkloadPlanTest.workloadPlanTests
      , RuntimeStateTest.runtimeStateTests
      , WorkloadTest.workloadTests
      , testCase "registry covers canonical command leaves" $
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
              ( ["test", "jitml-e2e", "--live", "--linux-cpu"]
              , ParsedCommand ["test", "jitml-e2e"] [ParsedOption "linux-cpu" [], ParsedOption "live" []]
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

              (
                [ "rl"
                , "train"
                , "experiments/cartpole.dhall"
                , "--substrate"
                , "apple-silicon"
                , "--seed"
                , "1729"
                , "--algorithm"
                , "QR-DQN"
                ]
              , ParsedCommand
                  ["rl", "train"]
                  [ ParsedOption "rl-experiment-dhall" ["experiments/cartpole.dhall"]
                  , ParsedOption "substrate" ["apple-silicon"]
                  , ParsedOption "seed" ["1729"]
                  , ParsedOption "algorithm" ["QR-DQN"]
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
      , testCase "user-facing numeric CLI options return InvalidConfig on malformed values" $ do
          let malformed option fallback minimumValue =
                parseUserIntOptionAtLeast
                  option
                  fallback
                  minimumValue
                  [ParsedOption option ["not-an-int"]]
                  @?= Left
                    ( AppError.InvalidConfig
                        ( "invalid --"
                            <> option
                            <> " value: \"not-an-int\"; expected an integer >= "
                            <> Text.pack (show minimumValue)
                        )
                    )
          traverse_
            (\(option, fallback, minimumValue) -> malformed option fallback minimumValue)
            [ ("consume-once", 0, 0)
            , ("seed", 42, 0)
            , ("games", 2, 1)
            , ("sims", 4, 1)
            , ("max-plies", 6, 1)
            , ("updates", 1, 1)
            , ("arena-games", 4, 1)
            ]
      , testCase "user-facing numeric CLI options enforce minimum values" $ do
          parseUserIntOptionAtLeast "consume-once" 0 0 [ParsedOption "consume-once" ["0"]]
            @?= Right 0
          parseUserIntOptionAtLeast "games" 2 1 [ParsedOption "games" ["0"]]
            @?= Left
              ( AppError.InvalidConfig
                  "invalid --games value: \"0\"; expected an integer >= 1"
              )
      , testCase "substrateTestInvocations builds the right cabal lanes" $ do
          -- No substrate: one exact invocation per target, with the opaque
          -- --test-options forwarded verbatim.
          Report.substrateTestInvocations Nothing ["jitml-unit", "jitml-backends"] Nothing
            @?= [["test", "jitml-unit"], ["test", "jitml-backends"]]
          Report.substrateTestInvocations Nothing ["jitml-backends"] (Just "-p Live")
            @?= [["test", "jitml-backends", "--test-options", "-p Live"]]
          -- linux-cpu: non-backend stanza runs in full; the partitioned stanza
          -- is restricted to the linux-cpu lane. No -fcuda.
          Report.substrateTestInvocations (Just Substrate.LinuxCPU) ["jitml-unit", "jitml-backends"] Nothing
            @?= [ ["test", "jitml-unit"]
                , ["test", "jitml-backends", "--test-options", "-p linux-cpu"]
                ]
          -- linux-cuda: -fcuda on every invocation (one consistent build) and
          -- the backends lane selected with -p linux-cuda.
          Report.substrateTestInvocations (Just Substrate.LinuxCUDA) ["jitml-unit", "jitml-backends"] Nothing
            @?= [ ["test", "-fcuda", "jitml-unit"]
                , ["test", "-fcuda", "jitml-backends", "--test-options", "-p linux-cuda"]
                ]
          -- Invocation order remains identical to target order so each
          -- transcript is journaled against the stanza that produced it.
          Report.substrateTestInvocations (Just Substrate.LinuxCPU) ["jitml-backends", "jitml-unit"] Nothing
            @?= [ ["test", "jitml-backends", "--test-options", "-p linux-cpu"]
                , ["test", "jitml-unit"]
                ]
          -- A single partitioned stanza omits the (empty) non-backend invocation.
          Report.substrateTestInvocations (Just Substrate.LinuxCUDA) ["jitml-backends"] Nothing
            @?= [["test", "-fcuda", "jitml-backends", "--test-options", "-p linux-cuda"]]
          -- A non-backend-only substrate run serializes stanzas, avoiding
          -- Cabal-native parallelism over a shared live cluster/device.
          Report.substrateTestInvocations (Just Substrate.LinuxCPU) ["jitml-unit", "jitml-e2e"] Nothing
            @?= [ ["test", "jitml-unit"]
                , ["test", "jitml-e2e"]
                ]
          -- User --test-options still apply to non-partitioned stanzas under a
          -- substrate flag; otherwise focused live filters such as WorkflowMatrix
          -- accidentally expand to the whole integration suite.
          Report.substrateTestInvocations
            (Just Substrate.AppleSilicon)
            ["jitml-integration"]
            (Just "-p WorkflowMatrix")
            @?= [["test", "jitml-integration", "--test-options", "-p WorkflowMatrix"]]
          -- User --test-options are appended after the synthesized lane selector.
          Report.substrateTestInvocations
            (Just Substrate.LinuxCUDA)
            ["jitml-backends"]
            (Just "--num-threads=1")
            @?= [["test", "-fcuda", "jitml-backends", "--test-options", "-p linux-cuda --num-threads=1"]]
      , testCase "invocation journals derive honest suite status and duration" $ do
          case mkProcessFailure (ExitFailure 7) fixtureProcessTranscript of
            Nothing -> assertFailure "failed to construct non-zero process failure"
            Just failure -> do
              let successTranscript =
                    fixtureProcessTranscript
                      { processTranscriptCommand = "cabal test jitml-unit"
                      , processTranscriptStdout = "unit passed\n"
                      , processTranscriptStderr = ""
                      , processTranscriptDuration = ProcessDuration 100_000_000
                      }
                  journal =
                    Report.appendInvocation
                      ( Report.appendInvocation
                          ( Report.appendInvocation
                              Report.emptyInvocationJournal
                              (Report.passedInvocation "jitml-unit" successTranscript)
                          )
                          (Report.failedInvocation "jitml-integration" failure)
                      )
                      ( Report.notRunInvocation
                          "jitml-e2e"
                          "cabal test jitml-e2e"
                          "jitml-integration"
                          failure
                      )
                  result = Report.deriveSuiteResult journal
                  entries = Report.invocationJournalEntries journal
                  rendered =
                    Report.renderReportCardWithKnobs
                      Report.defaultReportCardKnobs
                      Report.ReportCard
                        { Report.reportInvocationJournal = journal
                        , Report.reportScenarioJournals = []
                        , Report.reportMeasurements = Report.emptyReportMeasurements
                        }
              Report.suitePassed result @?= 1
              Report.suiteFailed result @?= 1
              Report.suiteNotRun result @?= 1
              Report.suiteStatus result @?= Report.SuiteFailed
              Report.suiteDuration result @?= ProcessDuration 225_000_000
              Report.firstInvocationFailure journal @?= Just failure
              case fmap Report.invocationResult entries of
                [Report.Passed observed, Report.Failed observedFailure, Report.NotRun blocker] -> do
                  observed @?= successTranscript
                  observedFailure @?= ObservedProcessExitFailure failure
                  Report.blockedByStanza blocker @?= "jitml-integration"
                  Report.blockedByFailure blocker @?= observedFailure
                observed -> assertFailure ("unexpected invocation journal: " <> show observed)
              assertBool
                "failed stanza is not rendered PASS"
                ("jitml-integration: FAIL" `Text.isInfixOf` rendered)
              assertBool
                "fail-fast stanza is NotRun"
                ("jitml-e2e: NOT-RUN (blocked by jitml-integration)" `Text.isInfixOf` rendered)
              assertBool
                "suite duration is evidence-derived"
                ("duration_nanoseconds: 225000000" `Text.isInfixOf` rendered)
              assertBool "failed stdout is retained" ("pod-a Running" `Text.isInfixOf` rendered)
              assertBool "failed stderr is retained" ("kubectl failed" `Text.isInfixOf` rendered)
      , testCase "runner exceptions remain Failed without fabricated exit evidence" $ do
          let failure = ObservedProcessAttemptFailure fixtureProcessAttemptFailure
              journal =
                Report.appendInvocation
                  ( Report.appendInvocation
                      Report.emptyInvocationJournal
                      (Report.failedObservedInvocation "jitml-e2e-playwright" failure)
                  )
                  ( Report.notRunObservedInvocation
                      "jitml-e2e"
                      "cabal test jitml-e2e"
                      "jitml-e2e-playwright"
                      failure
                  )
              suite = Report.deriveSuiteResult journal
              rendered =
                Report.renderReportCard
                  Report.ReportCard
                    { Report.reportInvocationJournal = journal
                    , Report.reportScenarioJournals = []
                    , Report.reportMeasurements = Report.emptyReportMeasurements
                    }
          Report.suitePassed suite @?= 0
          Report.suiteFailed suite @?= 1
          Report.suiteNotRun suite @?= 1
          Report.suiteDuration suite @?= ProcessDuration 25_000_000
          Report.firstInvocationFailure journal @?= Nothing
          Report.firstObservedInvocationFailure journal @?= Just failure
          assertBool
            "no exit status is invented"
            ( "exit: unavailable" `Text.isInfixOf` rendered
                && not ("exit: 1" `Text.isInfixOf` rendered)
            )
          assertBool
            "unavailable streams and exception detail are retained"
            ( "stdout: (unavailable; capture did not complete)" `Text.isInfixOf` rendered
                && "docker: executable not found" `Text.isInfixOf` rendered
            )
      , testCase "observed process attempts rethrow asynchronous exceptions unchanged" $ do
          observed <-
            Exception.try
              ( observeProcessAction
                  (subprocess "scope-fixture" ["async"])
                  (Exception.throwIO Exception.ThreadKilled)
              )
          (observed :: Either Exception.AsyncException ObservedProcessOutcome)
            @?= Left Exception.ThreadKilled
      , testCase "live e2e scope preserves the primary failure and cleans up after diagnostics" $ do
          executionOrder <- newIORef ([] :: [Text])
          postBodyRan <- newIORef False
          let acquire = scopeStep "acquire" "bootstrap"
              playwright = plannedScopeTest "playwright-live" "playwright"
              cabal = plannedScopeTest "jitml-e2e" "cabal-e2e"
              diagnostics = scopeStep "diagnostics" "diagnostics"
              release = scopeStep "release" "release"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire = [acquire]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = [release]
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "playwright-live" -> failedScopeOutcome 7 20 step
                          "diagnostics" -> failedScopeOutcome 8 30 step
                          "release" -> failedScopeOutcome 9 40 step
                          _ -> successfulScopeOutcome 10 step
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
          result <-
            LiveE2EScope.runLiveE2EScope
              backend
              plan
              [playwright, cabal]
              (modifyIORef' postBodyRan (const True) >> pure (Right ()))
          readIORef executionOrder
            >>= (@?= ["acquire", "playwright-live", "diagnostics", "release"])
          readIORef postBodyRan >>= (@?= False)
          case LiveE2EScope.liveE2EPrimaryFailure result of
            Nothing -> assertFailure "Playwright failure was not retained as primary"
            Just primary -> do
              LiveE2EScope.liveE2EFailurePhase primary @?= LiveE2EScope.LiveE2ETest
              LiveE2EScope.liveE2EFailureStep primary @?= "playwright-live"
              observedProcessFailureExitCode (LiveE2EScope.liveE2EFailureProcess primary)
                @?= Just (ExitFailure 7)
          fmap LiveE2EScope.liveE2EFailurePhase (LiveE2EScope.liveE2ESecondaryFailures result)
            @?= [LiveE2EScope.LiveE2EDiagnostics, LiveE2EScope.LiveE2ERelease]
          case fmap Report.invocationResult . Report.invocationJournalEntries $
            LiveE2EScope.liveE2EInvocationJournal result of
            [Report.Failed observedFailure, Report.NotRun blocker] -> do
              observedProcessFailureExitCode observedFailure @?= Just (ExitFailure 7)
              observedProcessFailureCommand observedFailure @?= "scope-fixture playwright"
              Report.blockedByStanza blocker @?= "live-e2e-test/playwright-live"
              Report.blockedByFailure blocker @?= observedFailure
            observed -> assertFailure ("unexpected failed live journal: " <> show observed)
          Report.suiteDuration
            (Report.deriveSuiteResult (LiveE2EScope.liveE2EInvocationJournal result))
            @?= ProcessDuration 20
          fmap
            ScenarioJournal.scenarioRecordPhase
            ( ScenarioJournal.scenarioJournalRecords
                (LiveE2EScope.liveE2EScenarioJournal result)
            )
            @?= [ ScenarioJournal.ScenarioAcquire
                , ScenarioJournal.ScenarioBody
                , ScenarioJournal.ScenarioDiagnostics
                , ScenarioJournal.ScenarioRelease
                ]
      , testCase "live e2e runner exceptions are Failed and diagnostics cannot prevent release" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "acquire" "bootstrap"
              playwright = plannedScopeTest "playwright-live" "playwright"
              cabal = plannedScopeTest "jitml-e2e" "cabal-e2e"
              diagnostics = scopeStep "diagnostics" "diagnostics"
              release = scopeStep "release" "release"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire = [acquire]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = [release]
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      case livePlanStepName step of
                        "playwright-live" ->
                          Exception.throwIO (userError "playwright launch exploded")
                        "diagnostics" ->
                          Exception.throwIO (userError "diagnostics launch exploded")
                        _ -> pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
          result <-
            LiveE2EScope.runLiveE2EScope
              backend
              plan
              [playwright, cabal]
              (pure (Right ()))
          readIORef executionOrder
            >>= (@?= ["acquire", "playwright-live", "diagnostics", "release"])
          primary <-
            case LiveE2EScope.liveE2EPrimaryFailure result of
              Nothing -> assertFailure "runner exception was not retained as primary"
              Just failure -> pure failure
          case LiveE2EScope.liveE2EFailureProcess primary of
            ObservedProcessExitFailure _ ->
              assertFailure "runner exception was rewritten as a process exit"
            ObservedProcessAttemptFailure failure -> do
              processAttemptFailureCommand failure @?= "scope-fixture playwright"
              processAttemptFailureStdout failure @?= Nothing
              processAttemptFailureStderr failure @?= Nothing
              assertBool
                "runner exception detail is retained"
                ("playwright launch exploded" `Text.isInfixOf` processAttemptFailureException failure)
          case LiveE2EScope.liveE2ESecondaryFailures result of
            [diagnosticFailure] -> do
              LiveE2EScope.liveE2EFailurePhase diagnosticFailure
                @?= LiveE2EScope.LiveE2EDiagnostics
              case LiveE2EScope.liveE2EFailureProcess diagnosticFailure of
                ObservedProcessExitFailure _ ->
                  assertFailure "diagnostic exception was rewritten as a process exit"
                ObservedProcessAttemptFailure failure ->
                  assertBool
                    "diagnostic exception detail is retained"
                    ( "diagnostics launch exploded"
                        `Text.isInfixOf` processAttemptFailureException failure
                    )
            observed -> assertFailure ("unexpected diagnostic failures: " <> show observed)
          let invocationJournal = LiveE2EScope.liveE2EInvocationJournal result
              suite = Report.deriveSuiteResult invocationJournal
              rendered =
                Report.renderReportCard
                  Report.ReportCard
                    { Report.reportInvocationJournal = invocationJournal
                    , Report.reportScenarioJournals =
                        [LiveE2EScope.liveE2EScenarioJournal result]
                    , Report.reportMeasurements = Report.emptyReportMeasurements
                    }
          Report.suitePassed suite @?= 0
          Report.suiteFailed suite @?= 1
          Report.suiteNotRun suite @?= 1
          case fmap Report.invocationResult (Report.invocationJournalEntries invocationJournal) of
            [Report.Failed failure, Report.NotRun blocker] -> do
              Report.blockedByStanza blocker @?= "live-e2e-test/playwright-live"
              Report.blockedByFailure blocker @?= failure
              Report.firstObservedInvocationFailure invocationJournal @?= Just failure
            observed -> assertFailure ("unexpected exception journal: " <> show observed)
          assertBool
            "report renders the missing exit status explicitly"
            ("exit: unavailable" `Text.isInfixOf` rendered)
          assertBool
            "report retains both synchronous runner exceptions"
            ( "playwright launch exploded" `Text.isInfixOf` rendered
                && "diagnostics launch exploded" `Text.isInfixOf` rendered
            )
      , testCase "live e2e asynchronous cancellation retains identity after diagnostics and release" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "acquire" "bootstrap"
              playwright = plannedScopeTest "playwright-live" "playwright"
              diagnostics = scopeStep "diagnostics" "diagnostics"
              release = scopeStep "release" "release"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire = [acquire]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = [release]
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      if livePlanStepName step == "playwright-live"
                        then Exception.throwIO Exception.ThreadKilled
                        else pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
          cancelled <-
            Exception.try
              ( LiveE2EScope.runLiveE2EScope
                  backend
                  plan
                  [playwright]
                  (pure (Right ()))
              )
          readIORef executionOrder
            >>= (@?= ["acquire", "playwright-live", "diagnostics", "release"])
          case cancelled of
            Left exception -> exception @?= Exception.ThreadKilled
            Right _ ->
              assertFailure "asynchronous cancellation was converted into a scope result"
      , testCase "live e2e late exceptional exit requires diagnostics after a clean body" $ do
          LiveE2EScope.liveE2EDiagnosticsRequired
            (const False)
            (ExitCaseException (Exception.toException Exception.ThreadKilled))
            @?= True
          LiveE2EScope.liveE2EDiagnosticsRequired
            id
            (ExitCaseSuccess False)
            @?= False
          LiveE2EScope.liveE2EDiagnosticsRequired
            id
            ExitCaseAbort
            @?= True
      , testCase "live e2e acquire failure blocks tests but still releases partial ownership" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "bootstrap" "bootstrap"
              diagnostics = scopeStep "diagnostics" "diagnostics"
              release = scopeStep "release" "release"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire = [acquire]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = [release]
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "bootstrap" -> failedScopeOutcome 6 11 step
                          "release" -> failedScopeOutcome 3 13 step
                          _ -> successfulScopeOutcome 12 step
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure =
                      (== ExitFailure 3) . processFailureExitCode
                  }
          result <-
            LiveE2EScope.runLiveE2EScope
              backend
              plan
              [plannedScopeTest "playwright-live" "playwright", plannedScopeTest "jitml-e2e" "cabal-e2e"]
              (pure (Right ()))
          readIORef executionOrder >>= (@?= ["bootstrap", "diagnostics", "release"])
          fmap LiveE2EScope.liveE2EFailurePhase (LiveE2EScope.liveE2EPrimaryFailure result)
            @?= Just LiveE2EScope.LiveE2EAcquire
          LiveE2EScope.liveE2ESecondaryFailures result @?= []
          case fmap Report.invocationResult . Report.invocationJournalEntries $
            LiveE2EScope.liveE2EInvocationJournal result of
            [Report.NotRun firstBlocker, Report.NotRun secondBlocker] -> do
              Report.blockedByStanza firstBlocker @?= "live-e2e-acquire/bootstrap"
              Report.blockedByFailure firstBlocker @?= Report.blockedByFailure secondBlocker
            observed -> assertFailure ("unexpected blocked live journal: " <> show observed)
          fmap
            ScenarioJournal.scenarioRecordDisposition
            ( ScenarioJournal.scenarioJournalRecords
                (LiveE2EScope.liveE2EScenarioJournal result)
            )
            @?= [ ScenarioJournal.ScenarioStepFailed
                , ScenarioJournal.ScenarioStepSucceeded
                , ScenarioJournal.ScenarioStepAcceptedNoop
                ]
      , testCase "live e2e measurement failure remains primary over diagnostics and release" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "acquire" "bootstrap"
              diagnostics = scopeStep "diagnostics" "diagnostics"
              release = scopeStep "release" "release"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire = [acquire]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = [release]
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "diagnostics" -> failedScopeOutcome 8 30 step
                          "release" -> failedScopeOutcome 9 40 step
                          _ -> successfulScopeOutcome 20 step
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
          result <-
            LiveE2EScope.runLiveE2EScope
              backend
              plan
              [plannedScopeTest "playwright-live" "playwright"]
              ( do
                  modifyIORef' executionOrder (<> ["measurements"])
                  pure (Left "measurement exploded" :: Either Text ())
              )
          readIORef executionOrder
            >>= (@?= ["acquire", "playwright-live", "measurements", "diagnostics", "release"])
          LiveE2EScope.liveE2EPrimaryFailure result @?= Nothing
          LiveE2EScope.liveE2EPostBodyFailure result @?= Just "measurement exploded"
          LiveE2EScope.liveE2EScopeFailure result
            @?= Just (LiveE2EScope.LiveE2EPostBodyIssue "measurement exploded")
          fmap LiveE2EScope.liveE2EFailurePhase (LiveE2EScope.liveE2ESecondaryFailures result)
            @?= [LiveE2EScope.LiveE2EDiagnostics, LiveE2EScope.LiveE2ERelease]
          let invocationJournal = LiveE2EScope.liveE2EInvocationJournal result
              suite = Report.deriveSuiteResult invocationJournal
              issues =
                ScenarioJournal.scenarioJournalIssues
                  (LiveE2EScope.liveE2EScenarioJournal result)
          Report.suitePassed suite @?= 1
          Report.suiteFailed suite @?= 0
          Report.suiteNotRun suite @?= 0
          Report.suiteDuration suite @?= ProcessDuration 20
          fmap ScenarioJournal.scenarioIssueStep issues @?= ["live-report-measurements"]
          fmap ScenarioJournal.scenarioIssueDetail issues @?= ["measurement exploded"]
      , testCase "live e2e release-only failure is retained after a successful body" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "acquire" "bootstrap"
              diagnostics = scopeStep "diagnostics" "diagnostics"
              release = scopeStep "release" "release"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire = [acquire]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = [release]
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "release" -> failedScopeOutcome 9 40 step
                          _ -> successfulScopeOutcome 20 step
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
          result <-
            LiveE2EScope.runLiveE2EScope
              backend
              plan
              [plannedScopeTest "playwright-live" "playwright"]
              (pure (Right ()))
          readIORef executionOrder
            >>= (@?= ["acquire", "playwright-live", "release"])
          LiveE2EScope.liveE2EPrimaryFailure result @?= Nothing
          LiveE2EScope.liveE2EPostBodyFailure result @?= Nothing
          case LiveE2EScope.liveE2ESecondaryFailures result of
            [releaseFailure] -> do
              LiveE2EScope.liveE2EFailurePhase releaseFailure
                @?= LiveE2EScope.LiveE2ERelease
              observedProcessFailureExitCode (LiveE2EScope.liveE2EFailureProcess releaseFailure)
                @?= Just (ExitFailure 9)
              LiveE2EScope.liveE2EScopeFailure result
                @?= Just (LiveE2EScope.LiveE2EProcessFailure releaseFailure)
            observed -> assertFailure ("unexpected release failures: " <> show observed)
          let suite =
                Report.deriveSuiteResult (LiveE2EScope.liveE2EInvocationJournal result)
          Report.suitePassed suite @?= 1
          Report.suiteFailed suite @?= 0
          Report.suiteNotRun suite @?= 0
          Report.suiteDuration suite @?= ProcessDuration 20
          fmap
            ScenarioJournal.scenarioRecordDisposition
            ( ScenarioJournal.scenarioJournalRecords
                (LiveE2EScope.liveE2EScenarioJournal result)
            )
            @?= [ ScenarioJournal.ScenarioStepSucceeded
                , ScenarioJournal.ScenarioStepSucceeded
                , ScenarioJournal.ScenarioStepFailed
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
            , "web/src/Generated/AdminPortals.purs"
            , "chart/templates/httproute-demo-root.yaml"
            , "chart/templates/grafana-dashboard-daemon-health.yaml"
            , "chart/templates/prometheus-scrapeconfig-jitml.yaml"
            ]
      , testCase "docs metadata check accepts complete governed headers" $ do
          DocsCheck.checkDocumentMetadataText
            "docs.md"
            ( Text.unlines
                [ "# Docs"
                , ""
                , "**Status**: Authoritative source"
                , "**Supersedes**: N/A"
                , "**Referenced by**: README.md"
                , "**Generated sections**: none"
                , ""
                , "> **Purpose**: Test document."
                ]
            )
            @?= []
      , testCase "docs metadata check rejects missing required headers" $ do
          let drifts =
                DocsCheck.checkDocumentMetadataText
                  "docs.md"
                  ( Text.unlines
                      [ "# Docs"
                      , ""
                      , "**Status**: Authoritative source"
                      , "**Generated sections**: none"
                      ]
                  )
          fmap DocsCheck.driftKey drifts
            @?= ["metadata.supersedes", "metadata.referenced-by", "metadata.purpose"]
      , testCase "docs metadata check reconciles generated-section markers" $ do
          let good =
                DocsCheck.checkDocumentMetadataText
                  "documents/engineering/cluster_topology.md"
                  ( Text.unlines
                      [ "# Cluster"
                      , ""
                      , "**Status**: Authoritative source"
                      , "**Supersedes**: N/A"
                      , "**Referenced by**: README.md"
                      , "**Generated sections**: cluster.routes"
                      , ""
                      , "> **Purpose**: Test document."
                      , ""
                      , "<!-- jitml:cluster.routes:start -->"
                      , "generated"
                      , "<!-- jitml:cluster.routes:end -->"
                      ]
                  )
              stale =
                DocsCheck.checkDocumentMetadataText
                  "documents/engineering/cluster_topology.md"
                  ( Text.unlines
                      [ "# Cluster"
                      , ""
                      , "**Status**: Authoritative source"
                      , "**Supersedes**: N/A"
                      , "**Referenced by**: README.md"
                      , "**Generated sections**: none"
                      , ""
                      , "> **Purpose**: Test document."
                      , ""
                      , "<!-- jitml:cluster.routes:start -->"
                      , "generated"
                      , "<!-- jitml:cluster.routes:end -->"
                      ]
                  )
          good @?= []
          fmap DocsCheck.driftKey stale
            @?= [ "metadata.generated-sections.cluster.routes"
                , "metadata.generated-sections.cluster.routes"
                ]
      , testCase "docs closure-claim check rejects premature current product closure claims" $ do
          let claimDoc = "The no-caveat product complete status is current."
              activeDrifts =
                DocsCheck.checkDocumentClosureClaimsText
                  False
                  "docs.md"
                  claimDoc
              allDone =
                PhaseStatus.productPhasesDone
                  (fmap markProductPhaseDone PhaseStatus.allProductPhaseStatuses)
          fmap DocsCheck.driftKey activeDrifts
            @?= ["closure-claim.no-caveat-product-complete"]
          DocsCheck.checkDocumentClosureClaimsText allDone "docs.md" claimDoc @?= []
      , testCase "docs closure-claim check exempts historical and prohibition blocks" $ do
          let historical =
                Text.unlines
                  [ "Historical 2026-06-30 evidence:"
                  , "The no-caveat product complete record is retained as history."
                  ]
              prohibition =
                "No future closure may claim \"all phases done\" until evidence is current."
          DocsCheck.checkDocumentClosureClaimsText False "docs.md" historical @?= []
          DocsCheck.checkDocumentClosureClaimsText False "docs.md" prohibition @?= []
      , testCase "numerical Dhall schema mirrors the Haskell catalog" $ do
          catalog <- loadNumericsCatalog "."
          validateNumericsCatalog catalog @?= Right ()
          checkDhallNumerics >>= (@?= [])
      , testCase "RL Dhall schema mirrors the Haskell catalog" $ do
          catalog <- loadRlCatalogSchema "."
          validateRlCatalogSchema catalog @?= Right ()
          checkDhallRL >>= (@?= [])
      , testCase "reflected BootConfig Dhall schema equals the checked-in file" $ do
          fileText <- Text.IO.readFile "dhall/service/BootConfig.dhall"
          canonicalDhallType fileText @?= Right bootConfigSchema
      , testCase "BootConfig refinement accepts only documented role/runtime combinations" $ do
          let linuxCpu = BootConfig.defaultBootConfig Substrate.LinuxCPU BootConfig.Cluster
              linuxCuda = BootConfig.defaultBootConfig Substrate.LinuxCUDA BootConfig.Cluster
              appleCluster = BootConfig.defaultBootConfig Substrate.AppleSilicon BootConfig.Cluster
              appleHost = BootConfig.defaultBootConfig Substrate.AppleSilicon BootConfig.Host
              coordinator = linuxCpu {BootConfig.bootActiveRole = BootConfig.Coordinator}
              webapp =
                linuxCpu
                  { BootConfig.bootActiveRole = BootConfig.Webapp
                  , BootConfig.bootWebappPulsarWsUrl = Just "ws://pulsar.example/ws"
                  }
          traverse_
            (\config -> BootConfig.validateBootConfig config @?= Right config)
            [linuxCpu, linuxCuda, appleCluster, appleHost, coordinator, webapp]
          BootConfig.validateBootConfig
            ( linuxCpu
                { BootConfig.bootResidency = BootConfig.Host
                , BootConfig.bootHttpListener = Nothing
                }
            )
            @?= Left
              ( BootConfig.UnsupportedBootRuntime
                  Substrate.LinuxCPU
                  BootConfig.Host
                  BootConfig.SelfInference
              )
          BootConfig.validateBootConfig
            (linuxCpu {BootConfig.bootInferenceMode = BootConfig.ForwardToHost})
            @?= Left
              ( BootConfig.UnsupportedBootRuntime
                  Substrate.LinuxCPU
                  BootConfig.Cluster
                  BootConfig.ForwardToHost
              )
          BootConfig.validateBootConfig
            (appleCluster {BootConfig.bootInferenceMode = BootConfig.SelfInference})
            @?= Left
              ( BootConfig.UnsupportedBootRuntime
                  Substrate.AppleSilicon
                  BootConfig.Cluster
                  BootConfig.SelfInference
              )
          BootConfig.validateBootConfig
            (appleHost {BootConfig.bootInferenceMode = BootConfig.ForwardToHost})
            @?= Left
              ( BootConfig.UnsupportedBootRuntime
                  Substrate.AppleSilicon
                  BootConfig.Host
                  BootConfig.ForwardToHost
              )
          BootConfig.validateBootConfig
            (appleHost {BootConfig.bootActiveRole = BootConfig.Coordinator})
            @?= Left (BootConfig.HostResidencyRequiresEngine BootConfig.Coordinator)
          BootConfig.validateBootConfig
            (linuxCpu {BootConfig.bootHttpListener = Nothing})
            @?= Left (BootConfig.ClusterResidencyRequiresHttpListener BootConfig.Engine)
          BootConfig.validateBootConfig
            (appleHost {BootConfig.bootHttpListener = Just (BootConfig.HttpListener "127.0.0.1" 8080)})
            @?= Left BootConfig.HostResidencyForbidsHttpListener
          BootConfig.validateBootConfig
            (linuxCpu {BootConfig.bootHttpListener = Just (BootConfig.HttpListener "  " 8080)})
            @?= Left BootConfig.EmptyHttpListenerHost
          BootConfig.validateBootConfig
            (linuxCpu {BootConfig.bootHttpListener = Just (BootConfig.HttpListener "127.0.0.1" 0)})
            @?= Left (BootConfig.HttpListenerPortOutOfRange 0)
          BootConfig.validateBootConfig
            (linuxCpu {BootConfig.bootActiveRole = BootConfig.Webapp})
            @?= Left BootConfig.WebappRequiresPulsarWebSocketUrl
          BootConfig.validateBootConfig
            ( webapp
                { BootConfig.bootWebappPulsarWsUrl = Just " "
                }
            )
            @?= Left BootConfig.WebappRequiresPulsarWebSocketUrl
          BootConfig.validateBootConfig
            (linuxCpu {BootConfig.bootWebappPulsarWsUrl = Just "ws://pulsar.example/ws"})
            @?= Left (BootConfig.NonWebappForbidsPulsarWebSocketUrl BootConfig.Engine)
      , testCase "BootConfig loader rejects a Dhall-valid but illegal runtime combination" $
          withSystemTempDirectory "jitml-invalid-boot-config" $ \root -> do
            let invalid =
                  (BootConfig.defaultBootConfig Substrate.LinuxCPU BootConfig.Cluster)
                    { BootConfig.bootInferenceMode = BootConfig.ForwardToHost
                    }
                path = root </> "BootConfig.dhall"
            Text.IO.writeFile path (BootConfig.renderBootConfigDhall invalid)
            result <- try (BootConfig.loadBootConfig path) :: IO (Either IOException BootConfig.BootConfig)
            case result of
              Left err ->
                assertBool
                  "loader reports the illegal topology"
                  ("unsupported BootConfig runtime topology" `isInfixOf` show err)
              Right loaded ->
                assertFailure ("illegal BootConfig unexpectedly loaded: " <> show loaded)
      , testCase "BootConfig loader rejects a Natural listener port before Int conversion" $
          withSystemTempDirectory "jitml-overflow-boot-config" $ \root -> do
            let hugePort = "18446744073709559696"
                valid =
                  BootConfig.renderBootConfigDhall
                    (BootConfig.defaultBootConfig Substrate.LinuxCPU BootConfig.Cluster)
                overflow = Text.replace "port = 8080" ("port = " <> hugePort) valid
                path = root </> "BootConfig.dhall"
            Text.IO.writeFile path overflow
            result <- try (BootConfig.loadBootConfig path) :: IO (Either IOException BootConfig.BootConfig)
            case result of
              Left err ->
                assertBool
                  "loader preserves and reports the unconverted Natural"
                  ( ("HTTP listener port must be between 1 and 65535, received " <> Text.unpack hugePort)
                      `isInfixOf` show err
                  )
              Right loaded ->
                assertFailure ("overflowing BootConfig unexpectedly loaded: " <> show loaded)
      , testCase "service role selection accepts Coordinator serve and rejects non-Engine consume-once" $ do
          serviceRoleInvocationError BootConfig.Engine True @?= Nothing
          serviceRoleInvocationError BootConfig.Webapp False @?= Nothing
          serviceRoleInvocationError BootConfig.Webapp True
            @?= Just "service --consume-once is available only when activeRole=Engine"
          serviceRoleInvocationError BootConfig.Coordinator False @?= Nothing
          serviceRoleInvocationError BootConfig.Coordinator True
            @?= Just "service --consume-once is available only when activeRole=Engine"
      , testCase "inference reply correlation binds call id and experiment hash" $ do
          let exactReply =
                ProtoInference.renderInferenceResult
                  ProtoInference.InferenceResult
                    { ProtoInference.iresCallId = "call-1"
                    , ProtoInference.iresExperimentHash = "experiment-1"
                    , ProtoInference.iresOutput = [0.25, 0.75]
                    }
              wrongExperimentReply =
                ProtoInference.renderInferenceResult
                  ProtoInference.InferenceResult
                    { ProtoInference.iresCallId = "call-1"
                    , ProtoInference.iresExperimentHash = "experiment-2"
                    , ProtoInference.iresOutput = [1.0]
                    }
          matchingInferenceResult "call-1" "experiment-1" exactReply
            @?= Just [0.25, 0.75]
          matchingInferenceResult "call-1" "experiment-1" wrongExperimentReply
            @?= Nothing
          matchingInferenceResult "call-2" "experiment-1" exactReply
            @?= Nothing
      , testCase "live inference reply transport failures are not checkpoint-missing errors" $ do
          inferenceReplyAppError "experiment-1" "consumer startup timed out"
            @?= AppError.PulsarFailed
              "inference request/reply failed for experiment-1: consumer startup timed out"
      , testCase "inference reply scope joins Owned cleanup and retains its failure beside the primary" $ do
          workerStarted <- newEmptyMVar
          neverReply <- newEmptyMVar
          cleanupFinished <- newIORef False
          let cleanupFailure =
                Capabilities.ConsumerCleanupFailure
                  (ServiceRetry.SETransient "forced owned subscription DELETE failure")
              consumerAction :: IO (Either Capabilities.ConsumerFailure ())
              consumerAction =
                Exception.catch
                  ( do
                      putMVar workerStarted ()
                      _ <- takeMVar neverReply
                      pure (Right ())
                  )
                  handleCancellation
              handleCancellation :: Exception.SomeAsyncException -> IO (Either Capabilities.ConsumerFailure ())
              handleCancellation _cancelled = do
                threadDelay 100000
                writeIORef cleanupFinished True
                pure (Left cleanupFailure)
              primaryAction :: IO (Either Text ())
              primaryAction = do
                takeMVar workerStarted
                pure (Left "inference result: no matching reply")
          result <-
            withinUnitDeadline
              "inference reply scope did not join failing Owned cleanup"
              (runInferenceReplyScope consumerAction primaryAction)
          cleanupWasJoined <- readIORef cleanupFinished
          cleanupWasJoined @?= True
          case result of
            Left detail -> do
              assertBool
                "primary reply failure was lost"
                ("inference result: no matching reply" `Text.isInfixOf` detail)
              assertBool
                "owned cleanup failure was lost"
                ("forced owned subscription DELETE failure" `Text.isInfixOf` detail)
            Right () -> assertFailure "cleanup failure incorrectly returned reply success"
      , testCase "inference reply scope treats joined clean cancellation as a clean release" $ do
          workerStarted <- newEmptyMVar
          neverReply <- newEmptyMVar
          let consumerAction :: IO (Either Capabilities.ConsumerFailure ())
              consumerAction = do
                putMVar workerStarted ()
                _ <- takeMVar neverReply
                pure (Right ())
              primaryAction :: IO (Either Text ())
              primaryAction = do
                takeMVar workerStarted
                pure (Left "inference result: no matching reply")
          withinUnitDeadline
            "inference reply scope did not join clean cancellation"
            (runInferenceReplyScope consumerAction primaryAction)
            >>= (@?= Left "inference result: no matching reply")
      , testCase "inference reply scope does not duplicate a natural consumer failure as cleanup" $ do
          failureReady <- newEmptyMVar
          allowConsumerReturn <- newEmptyMVar
          let consumerFailure = Capabilities.ConsumerHandlerFailure "natural reply handler failure"
              primaryFailure = "inference reply consumer failed: " <> Text.pack (show consumerFailure)
              consumerAction :: IO (Either Capabilities.ConsumerFailure ())
              consumerAction = do
                putMVar failureReady ()
                takeMVar allowConsumerReturn
                pure (Left consumerFailure)
              primaryAction :: IO (Either Text ())
              primaryAction = do
                takeMVar failureReady
                putMVar allowConsumerReturn ()
                threadDelay 100000
                pure (Left primaryFailure)
          withinUnitDeadline
            "natural inference consumer failure scope did not terminate"
            (runInferenceReplyScope consumerAction primaryAction)
            >>= (@?= Left primaryFailure)
      , testCase "inference reply scope observes cleanup failure and rethrows exceptional primary identity" $ do
          workerStarted <- newEmptyMVar
          neverReply <- newEmptyMVar
          observedReleaseIssues <- newIORef []
          let cleanupFailure =
                Capabilities.ConsumerCleanupFailure
                  (ServiceRetry.SETransient "forced exceptional-exit DELETE failure")
              consumerAction :: IO (Either Capabilities.ConsumerFailure ())
              consumerAction =
                Exception.catch
                  ( do
                      putMVar workerStarted ()
                      _ <- takeMVar neverReply
                      pure (Right ())
                  )
                  handleCancellation
              handleCancellation :: Exception.SomeAsyncException -> IO (Either Capabilities.ConsumerFailure ())
              handleCancellation _cancelled = pure (Left cleanupFailure)
              primaryAction :: IO (Either Text ())
              primaryAction = do
                takeMVar workerStarted
                Exception.throwIO Exception.ThreadKilled
              observe issue = do
                modifyIORef' observedReleaseIssues (<> [issue])
                Exception.throwIO (userError "forced cleanup observer failure")
              scopedAttempt =
                Exception.try
                  (runInferenceReplyScopeObserved observe consumerAction primaryAction)
                  :: IO (Either Exception.SomeException (Either Text ()))
          result <-
            withinUnitDeadline
              "exceptional inference reply scope did not finish its joined cleanup"
              scopedAttempt
          case result of
            Left exception ->
              (Exception.fromException exception :: Maybe Exception.AsyncException)
                @?= Just Exception.ThreadKilled
            Right value -> assertFailure ("exceptional primary returned normally: " <> show value)
          observed <- readIORef observedReleaseIssues
          case observed of
            [issue] ->
              assertBool
                "exceptional release lost its Owned cleanup failure"
                ("forced exceptional-exit DELETE failure" `Text.isInfixOf` issue)
            issues -> assertFailure ("unexpected exceptional release observations: " <> show issues)
      , testCase "reflected LiveConfig Dhall schema equals the checked-in file" $ do
          fileText <- Text.IO.readFile "dhall/service/LiveConfig.dhall"
          canonicalDhallType fileText @?= Right liveConfigSchema
      , testCase "rendered LiveConfig is standalone Dhall and round-trips through the loader" $
          withSystemTempDirectory "jitml-live-config-roundtrip" $ \root -> do
            let path = root </> "LiveConfig.dhall"
            Text.IO.writeFile path (LiveConfig.renderLiveConfigDhall LiveConfig.defaultLiveConfig)
            loaded <- LiveConfig.loadLiveConfig path
            loaded @?= LiveConfig.defaultLiveConfig
      , testCase "LiveConfig loader rejects a huge Natural before Int conversion" $
          withSystemTempDirectory "jitml-overflow-live-config" $ \root -> do
            let hugeDeadline = "18446744073709559696"
                valid = LiveConfig.renderLiveConfigDhall LiveConfig.defaultLiveConfig
                overflow =
                  Text.replace
                    "drainDeadlineSeconds = 30"
                    ("drainDeadlineSeconds = " <> hugeDeadline)
                    valid
                path = root </> "LiveConfig.dhall"
            Text.IO.writeFile path overflow
            result <-
              try (LiveConfig.loadLiveConfig path)
                :: IO (Either IOException LiveConfig.LiveConfig)
            case result of
              Left err -> do
                assertBool
                  "loader reports the bounded drain deadline"
                  ("LiveConfig drainDeadlineSeconds must be at most" `isInfixOf` show err)
                assertBool
                  "loader preserves and reports the unconverted Natural"
                  (("received " <> Text.unpack hugeDeadline) `isInfixOf` show err)
              Right loaded ->
                assertFailure ("overflowing LiveConfig unexpectedly loaded: " <> show loaded)
      , testCase "LiveConfig loader rejects a zero drain deadline" $
          withSystemTempDirectory "jitml-zero-drain-live-config" $ \root -> do
            let valid = LiveConfig.renderLiveConfigDhall LiveConfig.defaultLiveConfig
                zeroDeadline =
                  Text.replace
                    "drainDeadlineSeconds = 30"
                    "drainDeadlineSeconds = 0"
                    valid
                path = root </> "LiveConfig.dhall"
            Text.IO.writeFile path zeroDeadline
            result <-
              try (LiveConfig.loadLiveConfig path)
                :: IO (Either IOException LiveConfig.LiveConfig)
            case result of
              Left err ->
                assertBool
                  "loader reports the positive drain deadline requirement"
                  ( "LiveConfig drainDeadlineSeconds must be greater than zero"
                      `isInfixOf` show err
                  )
              Right loaded ->
                assertFailure ("zero-deadline LiveConfig unexpectedly loaded: " <> show loaded)
      , testCase "reflected RunConfig let-record equals dhall/run/Schema.dhall" $ do
          fileText <- Text.IO.readFile "dhall/run/Schema.dhall"
          canonicalDhallType fileText @?= canonicalDhallType runSchemaDhall
      , testCase "Sprint 5.17 — malformed mounted RunConfig reports decode failure" $
          withSystemTempDirectory "jitml-runconfig-malformed" $ \dir -> do
            let path = dir </> "RunConfig.dhall"
            missing <- RunConfig.tryLoadTrainingRunConfig path
            missing @?= RunConfig.RunConfigMissing
            Text.IO.writeFile path "not a valid RunConfig"
            training <- RunConfig.tryLoadTrainingRunConfig path
            tune <- RunConfig.tryLoadTuneRunConfig path
            rl <- RunConfig.tryLoadRlRunConfig path
            assertDecodeFailure "training" training
            assertDecodeFailure "tune" tune
            assertDecodeFailure "rl" rl
      , testCase "Sprint 21.3 — inference selector Dhall fails closed for illegal states" $
          withSystemTempDirectory "jitml-inference-selector" $ \dir -> do
            let path = dir </> "InferenceSelector.dhall"
                load body = do
                  Text.IO.writeFile path body
                  RunConfig.tryLoadInferenceSelectorConfig path
                validSelector provenanceKind convergencePassed updateCount finalHash =
                  Text.unlines
                    [ "{ experimentHash = \"exp-selector\""
                    , ", manifestSha = \"manifest-selector\""
                    , ", completedTraining ="
                    , "    { experimentHash = \"exp-selector\""
                    , "    , manifestSha = \"manifest-selector\""
                    , "    , provenanceKind = \"" <> provenanceKind <> "\""
                    , "    , evidence ="
                    , "        { initialWeightHash = \"initial-selector\""
                    , "        , finalWeightHash = \"" <> finalHash <> "\""
                    , "        , updateCount = " <> Text.pack (show updateCount)
                    , "        , datasetShaAtRead = \"dataset-selector\""
                    , "        }"
                    , "    , convergencePassed = " <> if convergencePassed then "True" else "False"
                    , "    }"
                    , "}"
                    ]
                assertRejected label expected body = do
                  result <- load body
                  case result of
                    RunConfig.RunConfigDecodeFailed err ->
                      assertBool
                        (Text.unpack label)
                        (Text.null expected || expected `Text.isInfixOf` err)
                    other ->
                      assertFailure
                        ( "expected inference selector rejection for "
                            <> Text.unpack label
                            <> ", got "
                            <> show other
                        )
            loaded <-
              load (validSelector "completed-training" True (1 :: Int) "final-selector")
            case loaded of
              RunConfig.RunConfigLoaded selector -> do
                RunConfig.iscExperimentHash selector @?= "exp-selector"
                RunConfig.iscManifestSha selector @?= "manifest-selector"
              other -> assertFailure ("expected valid selector to load, got " <> show other)
            assertRejected
              "declared selector"
              ""
              "{ experimentHash = \"declared-only\" }"
            assertRejected
              "partial selector"
              ""
              ( Text.unlines
                  [ "{ experimentHash = \"exp-selector\""
                  , ", manifestSha = \"manifest-selector\""
                  , "}"
                  ]
              )
            assertRejected
              "synthetic selector"
              "completed-training provenance"
              (validSelector "synthetic" True (1 :: Int) "final-selector")
            assertRejected
              "seeded selector"
              "completed-training provenance"
              (validSelector "seeded-demo" True (1 :: Int) "final-selector")
            assertRejected
              "failed selector"
              "failed convergence"
              (validSelector "completed-training" False (1 :: Int) "final-selector")
            assertRejected
              "zero-update selector"
              "positive updateCount"
              (validSelector "completed-training" True (0 :: Int) "final-selector")
            assertRejected
              "unchanged-weight selector"
              "changed weights"
              (validSelector "completed-training" True (1 :: Int) "initial-selector")
      , testCase "every reflected config schema is well-formed Dhall and reflexive" $
          -- Each reflected schema must itself parse + canonicalise back to itself,
          -- proving the emitted type is valid Dhall (anti-drift for RunConfig too).
          [ name
          | (name, schemaText) <- configSchemas
          , canonicalDhallType schemaText /= Right schemaText
          ]
            @?= []
      , testCase "every numerics/RL catalog Dhall leaf equals the emitted catalog" $ do
          -- Reflected catalog emission (the reverse of the decode-and-compare
          -- mirror above): each checked-in import-free catalog leaf must equal the
          -- Dhall emitted from the Haskell catalog, canonicalised on both sides.
          mismatches <-
            Control.Monad.foldM
              ( \acc (path, emitted) -> do
                  fileText <- Text.IO.readFile path
                  pure $
                    if canonicalDhallType fileText == canonicalDhallType emitted
                      then acc
                      else Text.pack path : acc
              )
              []
              catalogFileSchemas
          mismatches @?= []
      , testCase "Coordinator topic algebra derives the substrate-scoped family" $ do
          let names = fmap Topology.anyTopicName Topology.coordinatorTopics
          -- 10 substrate-scoped (workflow,phase) pairs × 3 substrates (30) +
          -- 4 apple-only internal/host-command legs = 34.
          length names @?= 34
          mapM_
            ( \t ->
                assertBool
                  ("derived topic " <> Text.unpack t)
                  (t `elem` names)
            )
            [ "persistent://public/default/training.command.linux-cpu"
            , "persistent://public/default/gc.event.linux-cuda"
            , "persistent://public/default/workflow.status.linux-cpu"
            , "persistent://public/default/inference.command.apple-silicon"
            , "persistent://public/default/rl.host-command.apple-silicon"
            ]
      , testCase "Coordinator routing graph validates and rejects one-sided links" $ do
          Topology.validateTopology Topology.jitmlTopology @?= Right ()
          assertBool
            "a command-only routing entry is rejected as one-sided"
            ( Topology.validateTopology
                [Topology.RouteEntry Topology.Train Topology.Command Substrate.allSubstrates]
                /= Right ()
            )
      , testCase "Work* readiness gate: ArtifactRef mintable only from a trained derivation" $ do
          let trained = completedTestManifest 5
              untrained = Checkpoint.emptyManifest "m" "exp1" []
              stepOnly = (Checkpoint.emptyManifest "m" "exp1" []) {Checkpoint.manifestStep = 5}
          fmap Work.artifactRefStep (Work.mintArtifactRef trained) @?= Just 5
          Work.mintArtifactRef untrained @?= Nothing
          Work.mintArtifactRef stepOnly @?= Nothing
          assertBool
            "readiness sentinel ends in .ready"
            (".ready" `Text.isSuffixOf` Work.readinessSentinelKey "exp1")
      , testCase "Work* command parse rejects malformed / unready commands with typed rejections" $ do
          let ready = Work.mintArtifactRef (completedTestManifest 1)
              parseInfer art =
                Work.parseWorkCommand
                  Topology.Infer
                  Substrate.LinuxCPU
                  "call-1"
                  "exp1"
                  art
                  "1,2,3"
                  "inference.result.linux-cpu"
          -- inference requires a ready derived artifact
          Work.parseWorkCommand Topology.Infer Substrate.LinuxCPU "c" "exp1" Nothing "1" "reply"
            @?= Left (Work.ArtifactNotReady Topology.Infer)
          -- with a minted artifact it parses
          case parseInfer ready of
            Right cmd -> Work.wcCallId cmd @?= Work.CallId "call-1"
            Left rej -> assertFailure ("expected Right, got " <> show rej)
          -- training consumes no artifact; missing callId / replyTopic are typed rejections
          Work.parseWorkCommand Topology.Train Substrate.LinuxCPU "" "exp1" Nothing "p" "reply"
            @?= Left Work.MissingCallId
          Work.parseWorkCommand Topology.Train Substrate.LinuxCPU "c" "exp1" Nothing "p" ""
            @?= Left Work.MissingReplyTopic
          assertBool
            "training parses with no artifact"
            ( either
                (const False)
                (const True)
                (Work.parseWorkCommand Topology.Train Substrate.LinuxCPU "c" "exp1" Nothing "p" "reply")
            )
      , testCase "Engine output decoding lifts a raw vector into a typed DecodedInference" $ do
          let clsDecoder =
                Checkpoint.OutputDecoder "mnist" Checkpoint.ClassificationOutput ["0", "1", "2"] Nothing Nothing
              genDecoder =
                Checkpoint.OutputDecoder "g" Checkpoint.GenericOutput [] Nothing Nothing
          case Decode.decodeInference clsDecoder [1.0, 3.0, 2.0] of
            Decode.DecodedClassification top _confidence probabilities labels -> do
              top @?= 1
              length probabilities @?= 3
              labels @?= ["0", "1", "2"]
            other -> assertFailure ("expected DecodedClassification, got " <> show other)
          Decode.decodeInference genDecoder [1.0, 2.0] @?= Decode.DecodedGeneric [1.0, 2.0]
      , testCase "Engine composite commands round-trip + the MCTS move is legal" $ do
          let compareCommand =
                ProtoInference.CheckpointCompareCommand "c1" "base" "cand" "inference.result.linux-cpu" [1.0, 2.0]
          ProtoInference.parseCheckpointCompareCommand
            (ProtoInference.renderCheckpointCompareCommand compareCommand)
            @?= Just compareCommand
          let moveCommand =
                ProtoInference.AdversarialMoveCommand
                  "m1"
                  "connect4"
                  "connect4-alphazero"
                  "inference.result.linux-cpu"
                  [3]
                  1
                  8
                  []
          ProtoInference.parseAdversarialMoveCommand (ProtoInference.renderAdversarialMoveCommand moveCommand)
            @?= Just moveCommand
          -- the Engine's MCTS picks a legal connect-4 column from a uniform output
          let outcome = AdversarialMove.computeAdversarialMove "connect4" [3] 1 8 (replicate 8 0.1)
          assertBool
            "chosen column is legal"
            (AdversarialMove.amoChosenColumn outcome `elem` AdversarialMove.amoLegalMoves outcome)
          -- the Engine renders typed `decoded-*` wire lines for the panels
          let rendered =
                Decode.renderDecodedInference (Decode.DecodedClassification 1 0.5 [0.2, 0.5, 0.3] ["a", "b", "c"])
          assertBool "decoded-kind line" ("decoded-kind: classification" `elem` rendered)
          assertBool "decoded-top-class line" ("decoded-top-class: 1" `elem` rendered)
      , testCase "Work* callId semantic dedup is a pure first-seen fold" $ do
          let mk c = case Work.parseWorkCommand Topology.Train Substrate.LinuxCPU c "exp1" Nothing "p" "reply" of
                Right cmd -> cmd
                Left _ -> error "unexpected rejection in dedup test"
              log' = [mk "a", mk "b", mk "a", mk "c", mk "b"]
          fmap (Work.unCallId . Work.wcCallId) (Work.dedupByCallId log') @?= ["a", "b", "c"]
      , testCase "AppError render golden covers canonical variants" $ do
          expected <- Text.IO.readFile "test/snapshots/cli/app-error-render.txt"
          case mkProcessFailure (ExitFailure 1) fixtureProcessTranscript of
            Nothing -> assertFailure "ExitFailure 1 did not construct ProcessFailure"
            Just failure ->
              Text.intercalate "---\n" (fmap renderError (canonicalErrors failure)) @?= expected
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
                , Overrides.eoAlgorithm = Nothing
                }
      , testCase "Sprint 22.2 — RL algorithm CLI override parses" $ do
          let parsed = Overrides.parseExperimentOverrides [ParsedOption "algorithm" ["QR-DQN"]]
          parsed
            @?= Right
              Overrides.ExperimentOverrides
                { Overrides.eoSubstrate = Nothing
                , Overrides.eoSeed = Nothing
                , Overrides.eoAlgorithm = Just "QR-DQN"
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
      , testCase "Sprint 22.2 — invalid --algorithm value surfaces a typed error" $ do
          let parsed = Overrides.parseExperimentOverrides [ParsedOption "algorithm" ["Bogus"]]
          parsed @?= Left (Overrides.InvalidAlgorithm "Bogus")
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
      , testCase "Sprint 9.16 — tuning overrides apply before artifact planning" $ do
          loaded <- Tune.loadTuningExperiment "experiments/mnist-tune.dhall"
          experiment <- case loaded of
            Left err -> assertFailure ("expected tuning fixture to decode: " <> Text.unpack err)
            Right value -> pure value
          let ovr =
                Overrides.TuningOverrides
                  { Overrides.toSampler = Just Tune.Sobol
                  , Overrides.toScheduler = Just Tune.Fifo
                  , Overrides.toPruner = Just Tune.NoPruner
                  , Overrides.toTrials = Just 2
                  , Overrides.toParallelism = Just 1
                  }
              resolved = Overrides.applyOverrides ovr experiment
          case Tune.tuningExperimentConfig resolved of
            Nothing -> assertFailure "expected resolved tuning config"
            Just config -> do
              Tune.tuningSamplerKind (Tune.tuningConfigSampler config) @?= Tune.Sobol
              Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config) @?= Tune.Fifo
              Tune.tuningPrunerKind (Tune.tuningConfigPruner config) @?= Tune.NoPruner
              Tune.tuningConfigTrials config @?= 2
              Tune.tuningConfigParallelism config @?= 1
          let implicitParallelism =
                Overrides.applyOverrides
                  Overrides.emptyTuningOverrides {Overrides.toTrials = Just 2}
                  experiment
          case Tune.tuningExperimentConfig implicitParallelism of
            Nothing -> assertFailure "expected trial-only override to retain tuning config"
            Just config -> do
              Tune.tuningConfigTrials config @?= 2
              Tune.tuningConfigParallelism config @?= 2
          let explicitInvalidParallelism =
                Overrides.applyOverrides
                  Overrides.emptyTuningOverrides
                    { Overrides.toTrials = Just 2
                    , Overrides.toParallelism = Just 8
                    }
                  experiment
          case Tune.tuningExperimentConfig explicitInvalidParallelism of
            Nothing -> assertFailure "expected explicit parallelism override to retain tuning config"
            Just config -> do
              Tune.tuningConfigTrials config @?= 2
              Tune.tuningConfigParallelism config @?= 8
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
          Overrides.overrideAlgorithm Overrides.emptyExperimentOverrides "PPO" @?= "PPO"
      , testCase "Sprint 1.12 — render override summary lists only present axes" $ do
          Overrides.renderExperimentOverrides Overrides.emptyExperimentOverrides @?= "(none)"
          Overrides.renderTuningOverrides Overrides.emptyTuningOverrides @?= "(none)"
          let ovr =
                Overrides.ExperimentOverrides
                  { Overrides.eoSubstrate = Just Substrate.LinuxCPU
                  , Overrides.eoSeed = Just 42
                  , Overrides.eoAlgorithm = Just "DQN"
                  }
          Overrides.renderExperimentOverrides ovr @?= "substrate=linux-cpu, seed=42, algorithm=DQN"
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
      , testCase "structured subprocess success preserves its complete transcript" $ do
          outcome <-
            runStreaming
              defaultSubprocessEnv
              (subprocess "/bin/sh" ["-c", "printf success-out; printf success-err >&2"])
          case outcome of
            ProcessSucceeded transcript -> do
              assertOutcomeField
                "success command"
                "/bin/sh -c 'printf success-out; printf success-err >&2'"
                (processTranscriptCommand transcript)
                outcome
              assertOutcomeField "success stdout" "success-out" (processTranscriptStdout transcript) outcome
              assertOutcomeField "success stderr" "success-err" (processTranscriptStderr transcript) outcome
              assertOutcomeField
                "success working directory"
                Nothing
                (processTranscriptWorkingDirectory transcript)
                outcome
              assertOutcomePredicate
                "elapsed duration is measured"
                (processDurationNanoseconds (processTranscriptDuration transcript) > 0)
                outcome
            ProcessFailed failure ->
              assertFailure
                ( "successful fixture returned failure:\n"
                    <> Text.unpack (renderProcessOutcome (ProcessFailed failure))
                )
      , testCase "structured subprocess failure preserves both streams and metadata" $ do
          let command =
                (subprocess "/bin/sh" ["-c", "printf failure-out; printf failure-err >&2; exit 7"])
                  { subprocessWorkingDirectory = Just "."
                  }
          outcome <- runStreaming defaultSubprocessEnv command
          case outcome of
            ProcessSucceeded transcript ->
              assertFailure
                ( "failing fixture returned success:\n"
                    <> Text.unpack (renderProcessOutcome (ProcessSucceeded transcript))
                )
            ProcessFailed failure -> do
              assertOutcomeField
                "failure command"
                "cd . && /bin/sh -c 'printf failure-out; printf failure-err >&2; exit 7'"
                (processFailureCommand failure)
                outcome
              assertOutcomeField "failure exit" (ExitFailure 7) (processFailureExitCode failure) outcome
              assertOutcomeField "failure stdout" "failure-out" (processFailureStdout failure) outcome
              assertOutcomeField "failure stderr" "failure-err" (processFailureStderr failure) outcome
              assertOutcomeField
                "failure working directory"
                (Just ".")
                (processFailureWorkingDirectory failure)
                outcome
              assertOutcomePredicate
                "elapsed duration is measured"
                (processDurationNanoseconds (processFailureDuration failure) > 0)
                outcome
      , testCase "ProcessFailure smart construction rejects ExitSuccess" $
          mkProcessFailure ExitSuccess fixtureProcessTranscript @?= Nothing
      , testCase "ProcessFailure smart construction rejects ExitFailure 0" $ do
          mkProcessFailure (ExitFailure 0) fixtureProcessTranscript @?= Nothing
          processOutcome (ExitFailure 0) fixtureProcessTranscript
            @?= ProcessSucceeded fixtureProcessTranscript
      , QuickCheck.testProperty "ProcessFailure smart construction retains every non-zero exit" $
          \(QuickCheck.NonZero code) ->
            fmap processFailureExitCode (mkProcessFailure (ExitFailure code) fixtureProcessTranscript)
              QuickCheck.=== Just (ExitFailure code)
      , QuickCheck.testProperty "process outcome success and failure constructors are exclusive" $
          \(QuickCheck.NonNegative code) ->
            let selectedExit
                  | code == 0 = ExitSuccess
                  | otherwise = ExitFailure code
             in case processOutcome selectedExit fixtureProcessTranscript of
                  ProcessSucceeded _ -> selectedExit QuickCheck.=== ExitSuccess
                  ProcessFailed failure ->
                    QuickCheck.conjoin
                      [ selectedExit QuickCheck.=/= ExitSuccess
                      , processFailureExitCode failure QuickCheck.=== selectedExit
                      ]
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
                Left err -> assertFailure (Text.unpack (Loader.renderKernelArtifactError err))
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
                Left err -> assertFailure (Text.unpack (Loader.renderKernelArtifactError err))
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
                Left err -> assertFailure (Text.unpack (Loader.renderKernelArtifactError err))
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
                "cuBLAS bindings compiled in; unavailable-stub assertion is not applicable"
                True
            else do
              result <- Cublas.verifyCublasRuntime
              result @?= Left unavailable
              handleResult <- Cublas.withCublasHandle (\_ -> pure ())
              handleResult @?= Left unavailable
          if Cudnn.cudnnBindingsCompiledIn
            then
              assertBool
                "cuDNN bindings compiled in; unavailable-stub assertion is not applicable"
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
            publicationExists <- doesFileExist (dir </> ".build" </> "runtime" </> "cluster-publication.json")
            first @?= True
            second @?= False
            legacyExists @?= False
            standaloneExists @?= False
            publicationExists @?= False
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
              assertScriptExit "apple help" ExitSuccess result
              assertScriptContains
                "apple help"
                ScriptStdout
                "./.build/jitml bootstrap --apple-silicon"
                result
          , testCase "apple doctor rejects non-macOS hosts" $ do
              withStubCommands [unameStub "Linux" "arm64"] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                assertScriptExit "apple non-macOS" (ExitFailure 2) result
                assertScriptContains "apple non-macOS diagnostic" ScriptStderr "requires macOS" result
          , testCase "apple doctor rejects non-arm64 hosts" $ do
              withStubCommands [unameStub "Darwin" "x86_64"] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                assertScriptExit "apple non-arm64" (ExitFailure 2) result
                assertScriptContains
                  "apple non-arm64 diagnostic"
                  ScriptStderr
                  "requires Apple Silicon arm64"
                  result
          , testCase "apple doctor reports missing Xcode Command Line Tools" $
              withStubCommands [unameStub "Darwin" "arm64", xcodeSelectUnavailableStub, brewStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                assertScriptExit "apple missing Xcode" (ExitFailure 2) result
                assertScriptContains "apple xcode diagnostic" ScriptStderr "xcode-select --install" result
          , testCase "apple doctor reports missing Homebrew" $
              withStubCommands [unameStub "Darwin" "arm64", xcodeSelectStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                assertScriptExit "apple missing Homebrew" (ExitFailure 2) result
                assertScriptContains "apple homebrew diagnostic" ScriptStderr "install Homebrew" result
          , testCase "apple doctor ignores broad package-toolchain gaps" $
              withStubCommands [unameStub "Darwin" "arm64", xcodeSelectStub, brewStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/apple-silicon.sh"
                    ["doctor"]
                assertScriptExit "apple doctor" ExitSuccess result
                assertScriptContains "apple doctor ok" ScriptStderr "stage-0 doctor: ok" result
          , testCase "apple build prepends compatible Homebrew LLVM for GHC" $
              withSystemTempDirectory "jitml-llvm-prefix" $ \llvmPrefix -> do
                let llvmBin = llvmPrefix </> "bin"
                createDirectoryIfMissing True llvmBin
                writeStubCommand llvmBin (llvmToolStub "opt" "19")
                writeStubCommand llvmBin (llvmToolStub "llc" "19")
                withPreservedFile ".build/jitml"
                  $ withStubCommands
                    [ unameStub "Darwin" "arm64"
                    , xcodeSelectStub
                    , brewPrefixStub llvmPrefix
                    , cabalBuildStub
                    , codesignStub
                    ]
                  $ \stubDir -> do
                    result <-
                      runBootstrapScript
                        (Just stubDir)
                        "bootstrap/apple-silicon.sh"
                        ["build"]
                    assertScriptExit "apple build" ExitSuccess result
                    assertScriptContains "apple build llvm path" ScriptStderr "using llvm@19" result
          , testCase "linux CPU doctor reports missing Docker" $ do
              withStubCommands [] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/linux-cpu.sh"
                    ["doctor"]
                assertScriptExit "linux missing Docker" (ExitFailure 2) result
                assertScriptContains
                  "linux docker diagnostic"
                  ScriptStderr
                  "missing required command 'docker'"
                  result
          , testCase "linux CPU doctor requires Docker without sudo" $
              withStubCommands [dockerInfoFailureStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cpu.sh" ["doctor"]
                assertScriptExit "linux Docker without sudo" (ExitFailure 2) result
                assertScriptContains "linux sudo diagnostic" ScriptStderr "without sudo" result
          , testCase "linux CPU doctor ignores non-Docker toolchain gaps" $
              withStubCommands [dockerOkStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/linux-cpu.sh"
                    ["doctor"]
                assertScriptExit "linux CPU doctor" ExitSuccess result
                assertScriptContains "linux cpu doctor ok" ScriptStderr "stage-0 doctor: ok" result
          , testCase "linux CPU up handles absent optional compose env" $
              withStubCommands [dockerOkStub] $ \stubDir -> do
                result <-
                  runBootstrapScript
                    (Just stubDir)
                    "bootstrap/linux-cpu.sh"
                    ["up"]
                assertScriptExit "linux CPU up" ExitSuccess result
                assertScriptContains "linux cpu up doctor ok" ScriptStderr "stage-0 doctor: ok" result
          , testCase "linux CUDA doctor reports missing NVIDIA runtime" $
              withStubCommands [dockerWithoutNvidiaRuntimeStub, nvidiaSmiHighCapabilityStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cuda.sh" ["doctor"]
                assertScriptExit "CUDA runtime doctor" (ExitFailure 2) result
                assertScriptContains
                  "cuda runtime diagnostic"
                  ScriptStderr
                  "NVIDIA container runtime"
                  result
          , testCase "linux CUDA doctor reports insufficient compute capability" $
              withStubCommands [dockerWithNvidiaRuntimeStub, nvidiaSmiLowCapabilityStub] $ \stubDir -> do
                result <- runBootstrapScript (Just stubDir) "bootstrap/linux-cuda.sh" ["doctor"]
                assertScriptExit "CUDA capability doctor" (ExitFailure 2) result
                assertScriptContains
                  "cuda capability diagnostic"
                  ScriptStderr
                  "compute capability"
                  result
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
            LiveConfig.defaultLiveConfig {LiveConfig.liveDedupCacheSize = 128} of
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
            @?= [ "cartpole"
                , "mountain-car"
                , "acrobot"
                , "pendulum"
                , "lunar-lander"
                , "key-door-grid"
                , "gridworld-deterministic"
                ]
          fmap RLFramework.renderRLRunPhase RLFramework.rlRunPlan
            @?= ["collect", "compute-advantages", "optimise", "evaluate", "checkpoint"]
      , testCase "RL trainer dispatch rejects unsupported environment fallbacks (Sprint 25.1)" $ do
          rlTrainerEnvironmentCompatibilityError "ppo" "cartpole" @?= Nothing
          rlTrainerEnvironmentCompatibilityError "ppo" "mountain-car" @?= Nothing
          rlTrainerEnvironmentCompatibilityError "sac" "pendulum" @?= Nothing
          rlTrainerEnvironmentCompatibilityError "sac" "lunar-lander" @?= Nothing
          rlTrainerEnvironmentCompatibilityError "dqn" "lunar-lander"
            @?= Just
              "RL trainer dqn does not support environment lunar-lander; supported environments: cartpole, mountain-car, key-door-grid"
          rlTrainerEnvironmentCompatibilityError "sac" "key-door-grid"
            @?= Just
              "RL trainer sac does not support environment key-door-grid; supported environments: pendulum, lunar-lander"
          rlTrainerEnvironmentCompatibilityError "unknown" "mountain-car" @?= Nothing
      , testCase "AlphaZero catalog includes games, two-headed network, and arena summary" $ do
          fmap AlphaZero.pigName AlphaZero.canonicalGames
            @?= ["connect4", "othello", "hex", "gomoku"]
          AlphaZero.policyHeadSize AlphaZero.connect4Network @?= 7
          AlphaZero.arenaWinRate (AlphaZero.ArenaSummary 3 1 0) @?= 0.75
      , testCase "AlphaZero artifact step counts completed generations rather than samples" $ do
          let completedGenerations = 64
              generatedSamples = 2370
          assertBool
            "regression fixture distinguishes generation and sample units"
            (completedGenerations /= fromIntegral generatedSamples)
          alphaZeroArtifactStep completedGenerations generatedSamples
            @?= completedGenerations
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
          -- Acrobot starts hanging down. A positive torque changes angular
          -- velocity, while a state with the tip above the target line
          -- terminates.
          let acrobotStep = Sim.acrobotStep Sim.acrobotInitial 2
              acrobotState = Sim.simStepState acrobotStep
          Sim.simStepReward acrobotStep @?= -1.0
          assertBool
            "acrobot torque changes angular velocity"
            (abs (Sim.acrobotDTheta2 acrobotState) > 0)
          Sim.acrobotStep Sim.acrobotInitial 2 @?= acrobotStep
          let acrobotTerminal =
                Sim.acrobotStep
                  (Sim.AcrobotState pi 0.0 0.0 0.0)
                  1
          Sim.simStepDone acrobotTerminal @?= True
          length (Sim.renderObservation (Sim.acrobotRenderFrame Sim.acrobotInitial)) @?= 6
          -- The render-frame observation has the documented length and the
          -- typed IO boundary mirrors the pure step semantics.
          length (Sim.renderObservation (Sim.cartPoleRenderFrame Sim.cartPoleInitial)) @?= 4
          length (Sim.renderObservation (Sim.mountainCarRenderFrame Sim.mountainCarInitial)) @?= 2
          (obs, reward, done) <- Sim.stepEnvironmentIO Sim.cartPoleEnvironment Sim.cartPoleInitial 1
          length obs @?= 4
          reward @?= 1.0
          done @?= False
      , testCase "pendulum continuous-control simulator uses bounded torque dynamics (Sprint 25.1)" $ do
          let left = Sim.pendulumStep Sim.pendulumInitial (-2.0)
              right = Sim.pendulumStep Sim.pendulumInitial 2.0
              overBound = Sim.pendulumStep Sim.pendulumInitial 100.0
          assertBool
            "pendulum left/right torques produce different angular velocities"
            ( Sim.pendThetaDot (Sim.cStepState left)
                /= Sim.pendThetaDot (Sim.cStepState right)
            )
          overBound @?= right
          Sim.cStepDone right @?= False
          length (Sim.pendulumObservation Sim.pendulumInitial) @?= 3
          length (Sim.renderObservation (Sim.pendulumRenderFrame Sim.pendulumInitial)) @?= 3
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
                  , Sim.lunarLanderPrevShaping = Nothing
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
      , testCase
          "gridworld-deterministic exposes tabular transitions, walls, and goal termination (Sprint 25.1)"
          $ do
            let start = Sim.gridWorldInitial
                east = Sim.gridWorldStep start (fromEnum Sim.GridWorldEast)
                south = Sim.gridWorldStep (Sim.simStepState east) (fromEnum Sim.GridWorldSouth)
                blocked = Sim.gridWorldStep (Sim.simStepState south) (fromEnum Sim.GridWorldSouth)
            length (Sim.gridWorldObservation start) @?= 16
            Sim.gridWorldStep start (fromEnum Sim.GridWorldEast) @?= east
            assertBool "gridworld normal move has step cost" (Sim.simStepReward east < 0)
            assertBool
              "gridworld wall collision has stronger penalty"
              (Sim.simStepReward blocked < Sim.simStepReward east)
            let routeToGoal =
                  foldl
                    ( \state action ->
                        Sim.simStepState (Sim.gridWorldStep state (fromEnum action))
                    )
                    start
                    [ Sim.GridWorldEast
                    , Sim.GridWorldEast
                    , Sim.GridWorldEast
                    , Sim.GridWorldSouth
                    , Sim.GridWorldSouth
                    ]
                goal = Sim.gridWorldStep routeToGoal (fromEnum Sim.GridWorldSouth)
            Sim.simStepDone goal @?= True
            assertBool "gridworld goal gives terminal reward" (Sim.simStepReward goal > 0)
            assertBool
              "gridworld render frame is generated from Haskell state"
              ("G" `Text.isInfixOf` Sim.renderCaption (Sim.gridWorldRenderFrame start))
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
          -- Illegal policy indices are rejected exactly; they are not aliased
          -- onto the next legal Othello cell.
          AlphaZero.applyMove 27 AlphaZero.initialOthello @?= AlphaZero.initialOthello
      , testCase "Othello forced passes preserve replay and the real player to move" $ do
          let passPosition =
                List.foldl'
                  (flip AlphaZero.applyMove)
                  AlphaZero.initialOthello
                  [ 19
                  , 18
                  , 17
                  , 20
                  , 21
                  , 34
                  , 45
                  , 14
                  , 33
                  , 42
                  , 29
                  , 32
                  , 7
                  , 37
                  , 43
                  , 52
                  , 51
                  , 44
                  , 59
                  , 26
                  , 50
                  , 49
                  , 56
                  , 41
                  , 24
                  , 61
                  , 30
                  , 25
                  , 60
                  , 16
                  , 48
                  , 38
                  , 62
                  , 10
                  , 31
                  , 22
                  , 8
                  , 23
                  , 2
                  , 3
                  , 11
                  , 4
                  , 5
                  , 53
                  , 40
                  , 47
                  , 12
                  , 57
                  , 54
                  , 58
                  , 39
                  , 46
                  , 15
                  , 55
                  , 63
                  , 6
                  , 9
                  , 13
                  ]
              playable = AlphaZero.normaliseForcedPass passPosition
          AlphaZero.gameOutcome passPosition @?= AlphaZero.GameInProgress
          AlphaZero.legalMoves passPosition @?= []
          AlphaZero.gameCurrentPlayer playable @?= -1
          take 1 (reverse (AlphaZero.gameMoves playable)) @?= [-1]
          AlphaZero.legalMoves playable @?= [0, 1]
          AlphaZero.gameMoves (AlphaZero.applyMove 0 passPosition)
            @?= AlphaZero.gameMoves passPosition
            <> [-1, 0]
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
                Mcts.runSearchWithPrior (\_ -> Mcts.NodeEval [1.0, 2.0, 3.0, 4.0] 0.0 False Nothing) cfg 17
              defaultPriors = map Mcts.edgePrior (Mcts.nodeChildren defaultTree)
              biasedPriors = map Mcts.edgePrior (Mcts.nodeChildren biasedTree)
          assertBool
            "default oracle produces uniform priors"
            (all (\p -> abs (p - 0.25) < 0.001) defaultPriors)
          assertBool
            "biased oracle does not produce uniform priors"
            (any (\p -> abs (p - 0.25) > 0.001) biasedPriors)
      , testCase "Othello MCTS expands only legal policy actions" $ do
          let net = PVN.initPolicyValueNet 65 64 16 101
              cfg = (Mcts.defaultMctsConfig 64) {Mcts.mctsSimulations = 8}
              tree =
                Mcts.runSearchWithPrior
                  (PVN.networkPriorOracle net AlphaZero.initialOthello)
                  cfg
                  17
              expandedActions = map Mcts.edgeAction (Mcts.nodeChildren tree)
              visitTarget = PVN.mctsVisitDistribution net 8 AlphaZero.initialOthello 17
              positiveTargetActions =
                [ action
                | action <- [0 .. 63]
                , visitTarget Data.Vector.Unboxed.! action > 0.0
                ]
          expandedActions @?= AlphaZero.legalMoves AlphaZero.initialOthello
          positiveTargetActions @?= AlphaZero.legalMoves AlphaZero.initialOthello
      , testCase "MCTS preserves value sign when an Othello pass keeps the same player" $ do
          let cfg =
                (Mcts.defaultMctsConfig 1)
                  { Mcts.mctsSimulations = 2
                  , Mcts.mctsRootDirichletWeight = 0.0
                  }
              oracle [] = Mcts.NodeEval [1.0] 0.0 False (Just 1)
              oracle _ = Mcts.NodeEval [] 1.0 True (Just 1)
              tree = Mcts.runSearchWithPrior oracle cfg 17
          case Mcts.nodeChildren tree of
            [edge] -> Mcts.edgeTotalValue edge @?= 1.0
            edges ->
              assertFailure
                ("expected one forced-pass search edge, got " <> show (length edges))
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
          Checkpoint.decodeJmw1 (Checkpoint.encodeJmw1 [0 / 0])
            @?= Left ".jmw1 tensor values must be finite"
      , testCase "checkpoint manifest decoder rejects corrupt CBOR" $ do
          assertBool
            "corrupt manifest bytes cannot refine into a checkpoint"
            (case Checkpoint.decodeManifestCbor "not-cbor" of Left _ -> True; Right _ -> False)
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
      , testCase "completed checkpoint CBOR re-encodes to its addressed content hash" $ do
          let manifest = completedTestManifest 5
              addressedSha = Checkpoint.manifestContentSha manifest
              payload = Checkpoint.encodeManifestCbor manifest
          case Checkpoint.decodeManifestCbor payload of
            Left err -> assertFailure ("completed manifest failed to decode: " <> Text.unpack err)
            Right decoded -> do
              Checkpoint.manifestContentSha decoded @?= addressedSha
              Checkpoint.encodeManifestCbor decoded @?= payload
      , testCase "inference eligibility requires manifest weight-delta evidence" $ do
          let completedManifest = completedTestManifest 1
              stripped =
                completedManifest
                  { Checkpoint.manifestInitialWeightHash = Nothing
                  , Checkpoint.manifestFinalWeightHash = Nothing
                  , Checkpoint.manifestUpdateCount = Nothing
                  , Checkpoint.manifestDatasetShaAtRead = Nothing
                  }
          Checkpoint.requireInferenceEligibleCheckpoint "sha" stripped
            @?= Left Checkpoint.CompletedTrainingEvidenceMissing
      , testCase "inference manifest CBOR decode fails closed before raw inference use" $ do
          let completedManifest = completedTestManifest 1
              manifestSha = Checkpoint.manifestContentSha completedManifest
              stripped =
                completedManifest
                  { Checkpoint.manifestInitialWeightHash = Nothing
                  , Checkpoint.manifestFinalWeightHash = Nothing
                  , Checkpoint.manifestUpdateCount = Nothing
                  , Checkpoint.manifestDatasetShaAtRead = Nothing
                  }
          case Checkpoint.decodeInferenceEligibleManifestCbor
            manifestSha
            (Checkpoint.encodeManifestCbor completedManifest) of
            Left err -> assertFailure ("expected inference-eligible decode, got " <> Text.unpack err)
            Right eligible ->
              Checkpoint.eligibleCheckpointManifestSha eligible @?= manifestSha
          Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor stripped)
            @?= Right stripped
          Checkpoint.decodeInferenceEligibleManifestCbor
            "stripped-sha"
            (Checkpoint.encodeManifestCbor stripped)
            @?= Left "completed-training manifest is missing weight-delta evidence"
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
                        , Checkpoint.architectureLayerGraph = Nothing
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
      , testCase "checkpoint manifest round-trips LayerGraph topology and parameter tensors (Sprint 23.3)" $ do
          graph <- either (assertFailure . Text.unpack) pure (vitShapedLayerGraph 31)
          let tensors = layerGraphCheckpointTensors graph
              loaded = loadedLayerGraphWeights graph
              manifest =
                (Checkpoint.emptyManifest "m-layergraph" "exp-layergraph" tensors)
                  { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
                  , Checkpoint.manifestArchitecture =
                      (Checkpoint.defaultArchitectureMetadata Checkpoint.SupervisedModelFamily)
                        { Checkpoint.architectureName = "vit-shaped-layergraph"
                        , Checkpoint.architectureInputs = [Checkpoint.TensorSpec "input" [4] "F64"]
                        , Checkpoint.architectureOutputs = [Checkpoint.TensorSpec "logits" [3] "F64"]
                        , Checkpoint.architectureLayerGraph =
                            Just (Checkpoint.layerGraphMetadataFromGraph graph)
                        }
                  , Checkpoint.manifestWeightLayout =
                      Checkpoint.NamedTensorWeightLayout (fmap Checkpoint.tensorSpecFromBlob tensors)
                  }
          case Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor manifest) of
            Left err -> assertFailure ("manifest decode failed: " <> Text.unpack err)
            Right decoded -> do
              Checkpoint.architectureLayerGraph (Checkpoint.manifestArchitecture decoded)
                @?= Just (Checkpoint.layerGraphMetadataFromGraph graph)
              CheckpointStore.layerGraphFromCheckpoint decoded loaded
                @?= Right (Just graph)
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
            firstWriteResult <-
              CheckpointStore.writeCheckpointSnapshot dir manifest [(blobKey, payload)] Nothing
            case firstWriteResult of
              Left err -> assertFailure ("expected checkpoint write, got: " <> Text.unpack err)
              Right firstWrite -> do
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
                latest @?= Right (Just (CheckpointStore.storedManifestSha firstWrite))
                blob <- CheckpointStore.readObject dir blobKey
                blob @?= Right payload
                conflictResult <- CheckpointStore.writeCheckpointSnapshot dir manifest [(blobKey, payload)] Nothing
                case conflictResult of
                  Left err -> assertFailure ("expected checkpoint conflict result, got: " <> Text.unpack err)
                  Right conflict ->
                    CheckpointStore.storedPointerResult conflict
                      @?= Checkpoint.PointerConflict (Checkpoint.latestPointerKey "exp1")
      , testCase "checkpoint store rejects unsafe local object keys as typed failures (Sprint 10.11)" $
          withSystemTempDirectory "jitml-checkpoint-safe-path" $ \dir -> do
            CheckpointStore.objectPathForKey dir "jitml-checkpoints/exp1/manifests/sha.cbor"
              @?= Right (dir </> "jitml-checkpoints/exp1/manifests/sha.cbor")
            traverse_
              ( \objectKey ->
                  CheckpointStore.objectPathForKey dir objectKey
                    @?= Left ("unsafe object key: " <> objectKey)
              )
              [ ""
              , "/absolute"
              , "../escape"
              , "exp1/../escape"
              , "jitml-checkpoints/exp1/../../escape"
              ]
            writeFailure <- CheckpointStore.writeObjectIfAbsent dir "../escape" "payload"
            writeFailure @?= Left "unsafe object key: ../escape"
            readFailure <- CheckpointStore.readObject dir "../escape"
            readFailure @?= Left "unsafe object key: ../escape"
            pointerFailure <- CheckpointStore.readCheckpointPointer dir "../pointer"
            pointerFailure @?= Left "unsafe object key: ../pointer"
            listedFailure <- CheckpointStore.listCheckpointManifests dir "../escape"
            listedFailure
              @?= Left "unsafe object key: jitml-checkpoints/../escape/manifests"
            validWrite <-
              CheckpointStore.writeObjectIfAbsent
                dir
                "jitml-checkpoints/exp1/artifacts/a.txt"
                "payload"
            validWrite
              @?= Right (CheckpointStore.ObjectCreated "jitml-checkpoints/exp1/artifacts/a.txt")
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
                , "/api/ws/inference"
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
              , "- /api/ws/inference inference-stream-contract <- src/JitML/Web/Contracts.hs"
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
      , testGroup
          "MLP checkpoint inference plan (Sprint 14.3)"
          [ testCase "detects named W1/b1/W2/b2 tensors, fits input, and trims semantic output width" $ do
              let shape =
                    Mlp.MlpShape
                      { Mlp.mlpInputs = 3
                      , Mlp.mlpHidden = 2
                      , Mlp.mlpOutputs = 4
                      }
                  flatWeights =
                    [ 0.1
                    , 0.2
                    , 0.3
                    , -0.1
                    , 0.4
                    , 0.5
                    , 0.01
                    , -0.02
                    , 0.2
                    , -0.1
                    , 0.3
                    , 0.4
                    , -0.3
                    , 0.2
                    , -0.5
                    , 0.1
                    , 0.03
                    , 0.04
                    , 0.05
                    , 0.06
                    ]
                  specs =
                    [ Checkpoint.TensorSpec "W2" [4, 2] "F64"
                    , Checkpoint.TensorSpec "b2" [4] "F64"
                    , Checkpoint.TensorSpec "W1" [2, 3] "F64"
                    , Checkpoint.TensorSpec "b1" [2] "F64"
                    ]
                  manifest =
                    ( Checkpoint.emptyManifest
                        "mlp-demo"
                        "exp"
                        [Checkpoint.TensorBlob "weights" [length flatWeights] "blob"]
                    )
                      { Checkpoint.manifestWeightLayout = Checkpoint.NamedTensorWeightLayout specs
                      , Checkpoint.manifestArchitecture =
                          Checkpoint.ArchitectureMetadata
                            { Checkpoint.architectureName = "demo-mlp"
                            , Checkpoint.architectureModelFamily = Checkpoint.SupervisedModelFamily
                            , Checkpoint.architectureInputs = [Checkpoint.TensorSpec "input" [3] "F64"]
                            , Checkpoint.architectureOutputs = [Checkpoint.TensorSpec "logits" [2] "F64"]
                            , Checkpoint.architectureLayerGraph = Nothing
                            }
                      }
                  loaded =
                    [ CheckpointStore.LoadedWeightTensor
                        (Checkpoint.TensorBlob "weights" [length flatWeights] "blob")
                        flatWeights
                    ]
              case Mlp.mlpParamsFromFlat shape flatWeights of
                Left err -> assertFailure err
                Right params -> do
                  result <-
                    MlpCheckpoint.runMlpCheckpointForwardWith
                      (\p input -> pure (Right (Mlp.mlpForward p input)))
                      manifest
                      loaded
                      [1.0, 2.0]
                  let expected =
                        take 2 $
                          Data.Vector.Unboxed.toList $
                            Mlp.forwardOutput $
                              Mlp.mlpForward params (MlpCheckpoint.fitMlpInput 3 [1.0, 2.0])
                  result @?= Just (Right expected)
          , testCase "leaves legacy non-MLP checkpoint manifests on the Dense2D fallback path" $ do
              let manifest = Checkpoint.emptyManifest "dense" "exp" [Checkpoint.TensorBlob "dense.weight" [2, 2] "blob"]
              MlpCheckpoint.mlpCheckpointPlan manifest @?= Right Nothing
          ]
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
          , testCase "ProductRow RL budgets are the shared trainer schedule's exact observed units" $ do
              mapM_
                ( \row ->
                    case ProductMatrix.rowClass row of
                      ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
                        assertCanonicalRlBudget row algorithm environment
                      ProductMatrix.RlGoalConditioned environment ->
                        assertCanonicalRlBudget row "HER" environment
                      _ -> pure ()
                )
                ProductMatrix.allProductRows
          , testCase "canonical RL schedules retain convergence floors and indivisible trainer units" $ do
              canonicalRlUnits "PPO" "cartpole" @?= Right 1_228_800
              canonicalRlUnits "PPO" "lunar-lander" @?= Right 2_400_000
              canonicalRlUnits "RecurrentPPO" "key-door-grid" @?= Right 307_200
              canonicalRlUnits "DQN" "cartpole" @?= Right 50_000
              canonicalRlUnits "DQN" "mountain-car" @?= Right 120_000
              canonicalRlUnits "QR-DQN" "key-door-grid" @?= Right 120_000
              canonicalRlUnits "SAC" "pendulum" @?= Right 4_000
              canonicalRlUnits "ARS" "cartpole" @?= Right 800_000
              canonicalRlUnits "HER" "goal-reaching" @?= Right 2_004
          , testCase "every canonical RL budget is an idempotent exact producer target" $ do
              mapM_
                ( \row ->
                    case ProductMatrix.rowClass row of
                      ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
                        assertCanonicalRlScheduleIsExact row algorithm environment
                      ProductMatrix.RlGoalConditioned environment ->
                        assertCanonicalRlScheduleIsExact row "HER" environment
                      _ -> pure ()
                )
                ProductMatrix.allProductRows
          , testCase "unrepresentable RL budget and vector overrides fail before training" $ do
              case ProductBudget.planExactRlTrainingSchedule
                "her"
                "goal-reaching"
                ProductBudget.productRlDefaultEvaluationEpisodes
                ProductBudget.productRlDefaultMaxEpisodeSteps
                Nothing
                2_000 of
                Left err ->
                  assertBool
                    "HER granularity failure names exact execution"
                    ("cannot be executed exactly" `Text.isInfixOf` err)
                Right schedule ->
                  assertFailure ("unexpected exact HER schedule: " <> show schedule)
              case ProductBudget.planExactRlTrainingSchedule
                "ppo"
                "cartpole"
                ProductBudget.productRlDefaultEvaluationEpisodes
                ProductBudget.productRlDefaultMaxEpisodeSteps
                (Just 7)
                1_228_800 of
                Left err ->
                  assertBool
                    "vector-width override failure reports the scheduled count"
                    ("schedules 1229312" `Text.isInfixOf` err)
                Right schedule ->
                  assertFailure ("unexpected exact vector schedule: " <> show schedule)
          , testCase "HER and every AlphaZero game have fixed-budget convergence metrics" $ do
              let her = ConvergenceThresholds.herGoalMetric
                  games =
                    fmap ConvergenceThresholds.azgGame ConvergenceThresholds.alphaZeroGameConvergenceRows
              assertBool
                "HER success metric passes"
                (TrainingBudget.convergencePassed (ConvergenceThresholds.hgmSuccessRate her))
              assertBool
                "HER achieved-goal distance metric passes"
                (TrainingBudget.convergencePassed (ConvergenceThresholds.hgmAchievedGoalDistance her))
              case find ((== "HER/goal-reaching") . ProductMatrix.rowId) ProductMatrix.allProductRows of
                Nothing -> assertFailure "missing HER/goal-reaching ProductRow"
                Just row -> do
                  observations <-
                    either
                      (assertFailure . Text.unpack)
                      pure
                      ( convergenceObservationsFixture
                          [ ("goal_success_rate", 1.0)
                          , ("achieved_goal_distance", 0.0)
                          ]
                      )
                  ProductExternalBars.assertConvergenceObservationsAgainstBar
                    (ProductMatrix.convergenceBar row)
                    observations
                    @?= []
              games @?= ["connect4", "othello", "hex", "gomoku"]
          , testCase "all-model workflow matrix enumerates SL/RL/HER/AlphaZero trained-artifact cells" $ do
              let cells = WorkflowMatrix.allModelCells
                  names = fmap WorkflowMatrix.modelCellName cells
              length (filter ((== WorkflowMatrix.SupervisedModelCell) . WorkflowMatrix.modelCellKind) cells)
                @?= 11
              assertBool "HER model cell is present" ("HER/goal-reaching" `elem` names)
              assertBool "Connect 4 AlphaZero model cell is present" ("connect4" `elem` names)
              assertBool "tuning product cell is present" ("hyperparameter-tuning" `elem` names)
              assertBool
                "model cells are unique"
                (length names == length (nub names))
              assertBool
                "every model cell requires a trained artifact"
                (all WorkflowMatrix.modelCellRequiresTrainedArtifact cells)
          , testCase "ProductRow registry satisfies the Sprint 19.1 matrix floor" $
              ProductMatrix.validateProductMatrix ProductMatrix.allProductRows @?= []
          , testCase "ProductRow filter selects exact known ids for both internal commands" $ do
              let selected =
                    fmap
                      (List.sort . fmap ProductMatrix.rowId)
                      (ProductMatrix.selectProductRows (Just " DQN/cartpole, PPO/cartpole "))
              selected @?= Right ["DQN/cartpole", "PPO/cartpole"]
              fmap (fmap ProductMatrix.rowId) (ProductMatrix.selectProductRows Nothing)
                @?= Right ProductMatrix.productRowIds
          , testCase "ProductRow filter rejects every unknown id instead of accepting a valid subset" $
              ProductMatrix.selectProductRows
                (Just "PPO/cartpole,PPO.cartpole,DQN.cartpole")
                @?= Left
                  "JITML_PRODUCT_ROW_FILTER is invalid: unknown product row ids: PPO.cartpole, DQN.cartpole"
          , testCase "ProductRow filter rejects duplicate ids before internal work starts" $
              ProductMatrix.selectProductRows
                (Just "PPO/cartpole,DQN/cartpole,PPO/cartpole")
                @?= Left
                  "JITML_PRODUCT_ROW_FILTER is invalid: duplicate product row ids: PPO/cartpole"
          , testCase "supervised ProductRows declare the publisher's exact fixed epoch budgets" $ do
              let supervisedBudgets =
                    [ (ProductMatrix.rowId row, TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row))
                    | row <- ProductMatrix.allProductRows
                    , ProductMatrix.family row == ProductMatrix.Supervised
                    ]
              supervisedBudgets
                @?= [ ("mnist-shallow-mlp", 10)
                    , ("mnist-deep-mlp", 10)
                    , ("mnist-lenet", 10)
                    , ("fashion-mnist-mlp", 10)
                    , ("fashion-mnist-resnet", 10)
                    , ("cifar10-resnet20", 5)
                    , ("cifar10-resnet56", 5)
                    , ("cifar100-wide-resnet", 10)
                    , ("cifar10-vit", 5)
                    , ("tiny-imagenet-resnet50", 5)
                    , ("california-housing-mlp", 10)
                    ]
          , testCase "ProductRow artifact experiment hashes are stable and object-key safe" $ do
              let hashes = fmap ProductMatrix.productRowExperimentHash ProductMatrix.allProductRows
              assertBool
                "product-row hashes are unique"
                (length hashes == length (nub hashes))
              assertBool
                "product-row hashes use the product-row namespace"
                (all ("product-row-" `Text.isPrefixOf`) hashes)
              assertBool
                "product-row hashes avoid slash-separated object prefixes"
                (not (any (Text.isInfixOf "/") hashes))
          , testCase "CheckpointList frames carry ProductRow selector state and row ids" $ do
              case ProductMatrix.allProductRows of
                [] -> assertFailure "ProductRow registry is unexpectedly empty"
                row : _ -> do
                  let rowId' = ProductMatrix.rowId row
                      experimentHash = ProductMatrix.productRowExperimentHash row
                      selectorStates = ["eligible", "training-required", "unsupported", "error"]
                      summaries =
                        Workload.checkpointSummariesForRow
                          rowId'
                          experimentHash
                          [completedTestManifest 1]
                      selector state =
                        Text.intercalate
                          "\t"
                          [ rowId' <> "-" <> state
                          , experimentHash <> "-" <> state
                          , ProductMatrix.renderRowFamily (ProductMatrix.family row)
                          , state
                          , if state == "eligible" then "1" else "0"
                          , ProductMatrix.demoPanel row
                          ]
                      frame =
                        Workload.renderCheckpointListResultWithSelectors
                          "call-product"
                          (fmap selector selectorStates)
                          summaries
                  assertBool
                    "checkpoint summary carries the product row id"
                    ( any
                        (("checkpoint-summary: " <> rowId' <> "\t" <> experimentHash) `Text.isPrefixOf`)
                        (Text.lines frame)
                    )
                  traverse_
                    ( \state ->
                        assertBool
                          ("row selector carries " <> Text.unpack state <> " state")
                          (("\t" <> state <> "\t") `Text.isInfixOf` frame)
                    )
                    selectorStates
                  assertBool
                    "global selector is ready when at least one row is eligible"
                    ("selector-state: ready" `Text.isInfixOf` frame)
          , testCase "README matrix rows match the ProductRow registry in both directions" $ do
              readme <- Text.IO.readFile "README.md"
              case readmeProductParityFailures readme of
                Left err -> assertFailure (Text.unpack err)
                Right failures -> failures @?= []
          , testCase "Generated PureScript model matrix constants match ProductRow registry rows" $ do
              generated <- Text.IO.readFile "web/src/Generated/Contracts.purs"
              generatedModelMatrixPairs generated @?= registryModelMatrixPairs
          , testCase "ProductRow browser artifacts never use seeded demo weights" $ do
              generated <- Text.IO.readFile "web/src/Generated/Contracts.purs"
              let productHashes = fmap ProductMatrix.productRowExperimentHash ProductMatrix.allProductRows
                  generatedHashes =
                    [ experimentHash
                    | (_, _, experimentHash, _, _) <- generatedModelMatrixPairs generated
                    ]
              assertBool
                "product-row hashes all use the product-row namespace"
                (all ("product-row-" `Text.isPrefixOf`) productHashes)
              assertBool
                "generated hashes all use the product-row namespace"
                (all ("product-row-" `Text.isPrefixOf`) generatedHashes)
              filter ("demo-weights" `Text.isInfixOf`) productHashes @?= []
              filter ("demo-weights" `Text.isInfixOf`) generatedHashes @?= []
          , testCase "ProductRow experiment configs resolve or reflect for every row" $ do
              loaded <-
                traverse
                  ( \row -> do
                      result <- ProductExperiment.loadProductExperimentForRow row
                      pure (ProductMatrix.rowId row, result)
                  )
                  ProductMatrix.allProductRows
              let failures =
                    [ rowId' <> ": " <> err
                    | (rowId', Left err) <- loaded
                    ]
              failures @?= []
          , testCase "RL algorithm override preserves the resolved experiment record" $ do
              loaded <- ProductExperiment.loadRlExperimentByPath "experiments/cartpole.dhall"
              experiment <- case loaded of
                Left err -> assertFailure (Text.unpack err)
                Right value -> pure value
              let override =
                    Overrides.ExperimentOverrides
                      { Overrides.eoSubstrate = Nothing
                      , Overrides.eoSeed = Nothing
                      , Overrides.eoAlgorithm = Just "A2C"
                      }
              ProductExperiment.rlExperimentEnvironment experiment @?= "cartpole"
              ProductExperiment.rlExperimentAlgorithm experiment @?= "PPO"
              Overrides.overrideAlgorithm override (ProductExperiment.rlExperimentAlgorithm experiment)
                @?= "A2C"
              ProductExperiment.rlExperimentEnvironment experiment @?= "cartpole"
          , testCase "RL algorithm registry maps product algorithms to distinct update contracts (Sprint 25.2)" $ do
              AlgorithmRegistry.validateAlgorithmModuleRegistry AlgorithmRegistry.algorithmModuleRegistry @?= []
              let productAlgorithms =
                    List.sort . nub $
                      concatMap productRowRlAlgorithms ProductMatrix.allProductRows
                  expectedAlgorithms =
                    List.sort
                      [ "PPO"
                      , "A2C"
                      , "TRPO"
                      , "MaskablePPO"
                      , "RecurrentPPO"
                      , "DQN"
                      , "QR-DQN"
                      , "DDPG"
                      , "TD3"
                      , "SAC"
                      , "CrossQ"
                      , "TQC"
                      , "ARS"
                      , "HER"
                      ]
                  resolved =
                    [ ( algorithm
                      , AlgorithmCommon.updateIdentity contract
                      , AlgorithmCommon.trainerEntryPoint contract
                      )
                    | algorithm <- productAlgorithms
                    , Just contract <- [AlgorithmRegistry.updateContractFor algorithm]
                    ]
                  missing =
                    [ algorithm
                    | algorithm <- productAlgorithms
                    , isNothing (AlgorithmRegistry.updateContractFor algorithm)
                    ]
                  updateIdentities = [identity | (_, identity, _) <- resolved]
              productAlgorithms @?= expectedAlgorithms
              missing @?= []
              assertBool
                "each product RL algorithm resolves to a distinct update identity"
                (length updateIdentities == length (nub updateIdentities))
              resolved
                @?= List.sort
                  [
                    ( "A2C"
                    , "on-policy.a2c.unclipped-advantage-actor-critic"
                    , "JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpole/VariantA2C"
                    )
                  ,
                    ( "ARS"
                    , "black-box.ars.finite-difference-linear-policy"
                    , "JitML.RL.Algorithms.ArsTrainer.trainArsOnCartpole"
                    )
                  ,
                    ( "CrossQ"
                    , "off-policy.crossq.batch-renorm-no-target-network"
                    , "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantCrossQ"
                    )
                  ,
                    ( "DDPG"
                    , "off-policy.ddpg.deterministic-actor-critic"
                    , "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantDDPG"
                    )
                  ,
                    ( "DQN"
                    , "off-policy.dqn.scalar-bellman-target-network"
                    , "JitML.RL.Algorithms.DqnTrainer.trainDqnOnCartpole"
                    )
                  ,
                    ( "HER"
                    , "goal-conditioned.her.future-relabeling-off-policy-wrapper"
                    , "JitML.RL.Algorithms.HerTrainer.trainHerOnBitFlip"
                    )
                  ,
                    ( "MaskablePPO"
                    , "on-policy.maskable-ppo.masked-categorical-clipped-surrogate"
                    , "JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpole/VariantMaskablePPO"
                    )
                  , ("PPO", "on-policy.ppo.clipped-surrogate", "JitML.RL.Algorithms.PpoTrainer.trainPpoOnCartpole")
                  ,
                    ( "QR-DQN"
                    , "off-policy.qr-dqn.quantile-huber-distributional"
                    , "JitML.RL.Algorithms.QrDqnTrainer.trainQrDqnOnCartpole"
                    )
                  ,
                    ( "RecurrentPPO"
                    , "on-policy.recurrent-ppo.sequence-bptt-clipped-surrogate"
                    , "JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpole/VariantRecurrentPPO"
                    )
                  ,
                    ( "SAC"
                    , "off-policy.sac.entropy-regularized-twin-critic"
                    , "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantSAC"
                    )
                  ,
                    ( "TD3"
                    , "off-policy.td3.clipped-double-q-delayed-policy"
                    , "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantTD3"
                    )
                  ,
                    ( "TQC"
                    , "off-policy.tqc.truncated-quantile-critics"
                    , "JitML.RL.Algorithms.ContinuousTrainer.trainContinuousOnPendulum/VariantTQC"
                    )
                  ,
                    ( "TRPO"
                    , "on-policy.trpo.kl-trust-region"
                    , "JitML.RL.Algorithms.PpoTrainer.trainOnPolicyOnCartpole/VariantTRPO"
                    )
                  ]
          , testCase
              "documented optional/research rows are typed non-product and absent from ProductRow registry"
              $ do
                let nonProductIds = fmap ProductMatrix.nonProductRowId ProductMatrix.nonProductRows
                    productIds = ProductMatrix.productRowIds
                assertBool
                  "Tic-Tac-Toe minimax anchor is typed non-product"
                  ("tic-tac-toe" `elem` nonProductIds)
                assertBool
                  "optional Atari/ALE support is typed non-product"
                  ("atari-subset" `elem` nonProductIds)
                let overlapping =
                      [ nonProductId
                      | nonProductId <- nonProductIds
                      , nonProductId `elem` productIds
                      ]
                overlapping @?= []
          , testCase
              "ProductRow registry rejects duplicates, undocumented rows, missing rows, and missing test ids"
              $ do
                let rows = ProductMatrix.allProductRows
                case rows of
                  [] -> assertFailure "ProductRow registry is unexpectedly empty"
                  firstRow : rest -> do
                    let withoutMnist =
                          filter ((/= "mnist-shallow-mlp") . ProductMatrix.rowId) rows
                        duplicateRows = firstRow : rows
                        undocumentedRows =
                          firstRow
                            { rowId = "undocumented-supervised-row"
                            }
                            : rows
                        missingTestIdRows =
                          firstRow
                            { integrationTest = ""
                            }
                            : rest
                    assertBool
                      "duplicate row id is rejected"
                      ( any
                          ("duplicate row id: " `Text.isPrefixOf`)
                          (ProductMatrix.validateProductMatrix duplicateRows)
                      )
                    assertBool
                      "documented-but-unregistered supervised row is rejected"
                      ( "missing matrix-floor supervised row: mnist-shallow-mlp"
                          `elem` ProductMatrix.validateProductMatrix withoutMnist
                      )
                    assertBool
                      "undocumented supervised row is rejected"
                      ( "undocumented matrix supervised row: undocumented-supervised-row"
                          `elem` ProductMatrix.validateProductMatrix undocumentedRows
                      )
                    assertBool
                      "missing integration test id is rejected"
                      ( any
                          (" is missing integrationTest" `Text.isSuffixOf`)
                          (ProductMatrix.validateProductMatrix missingTestIdRows)
                      )
          , testCase "Training evidence rejects fabricated weight state" $ do
              ProductEvidence.mkTrainingEvidence "same" "same" 1 "dataset-sha"
                @?= Left "training evidence requires weight movement"
              ProductEvidence.mkTrainingEvidence "initial" "final" 0 "dataset-sha"
                @?= Left "training evidence requires a positive update count"
          , testCase "CompletedTraining rejects failed bar-evaluated convergence" $ do
              let evidence =
                    either
                      (error . Text.unpack)
                      id
                      (ProductEvidence.mkTrainingEvidence "initial" "final" 1 "dataset-sha")
                  failedObservation =
                    either
                      (error . Text.unpack)
                      id
                      ( ProductConvergence.evaluateConvergence
                          (ProductConvergence.mkConvergenceBar "accuracy" TrainingBudget.MetricMaximise 0.90 0.0)
                          (ProductConvergence.MeasuredMetrics [("accuracy", 0.50)])
                      )
                  result =
                    TrainingBudget.completedTraining
                      unitFixturePlanId
                      (unitBudget TrainingBudget.SupervisedEpochBudget 1)
                      1
                      evidence
                      [failedObservation]
                      TrainingBudget.TensorBoardRunMetadata
                        { TrainingBudget.tbrRunId = "unit-test"
                        , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/unit-test"
                        , TrainingBudget.tbrScalarTags = ["accuracy"]
                        }
              assertBool
                "failed convergence observation is rejected"
                ( case result of
                    Left err -> "convergence metric failed: accuracy" `Text.isInfixOf` err
                    Right _ -> False
                )
          , testCase
              "ModelRef type-state pipeline reaches inference eligibility only through completed training"
              $ do
                let completed = completedTrainingFixture 1
                    declaredExperiment = ProductPipeline.declareExperiment "exp1"
                    declaredModel = ProductPipeline.declareModel declaredExperiment
                    startedModel = ProductPipeline.startTraining declaredModel
                    acceptCompleted
                      :: ProductPipeline.ModelRef 'TrainingCompleted
                      -> Text
                    acceptCompleted = ProductPipeline.modelRefExperimentHash
                    acceptEligible :: ProductPipeline.InferenceEligibleRef -> Text
                    acceptEligible = ProductPipeline.modelRefExperimentHash
                    completedCheckpoint =
                      either
                        (error . show)
                        id
                        ( Checkpoint.requireInferenceEligibleCheckpoint
                            "manifest-sha"
                            (completedTestManifest 1)
                        )
                trainedModel <- ProductPipeline.train startedModel completed
                acceptCompleted trainedModel @?= "exp1"
                case ProductPipeline.markInferenceEligible completedCheckpoint trainedModel of
                  Left err -> assertFailure (Text.unpack err)
                  Right eligibleModel -> do
                    acceptEligible eligibleModel @?= "exp1"
                    ProductPipeline.modelRefManifestSha eligibleModel @?= Just "manifest-sha"
                    ProductPipeline.modelRefCompletedTraining eligibleModel @?= Just completed
          , testCase "ModelRef inference eligibility rejects a mismatched completed-training witness" $ do
              let completed = completedTrainingFixture 1
                  declaredModel =
                    ProductPipeline.declareModel
                      (ProductPipeline.declareExperiment "exp1")
                  startedModel = ProductPipeline.startTraining declaredModel
                  trainedModel = ProductPipeline.completeTraining startedModel completed
                  mismatchedCheckpoint =
                    either
                      (error . show)
                      id
                      ( Checkpoint.requireInferenceEligibleCheckpoint
                          "manifest-sha"
                          (completedTestManifest 2)
                      )
              ProductPipeline.markInferenceEligible mismatchedCheckpoint trainedModel
                @?= Left "completed-training witness does not match model reference"
          , testCase "InferenceEligibleCheckpoint mints an inference-only ModelRef" $ do
              let acceptEligible :: ProductPipeline.InferenceEligibleRef -> Text
                  acceptEligible = ProductPipeline.modelRefExperimentHash
                  completed = completedTrainingFixture 1
              case Checkpoint.requireInferenceEligibleCheckpoint "manifest-sha" (completedTestManifest 1) of
                Left err -> assertFailure (show err)
                Right eligibleCheckpoint -> do
                  let eligibleModel =
                        ProductPipeline.inferenceEligibleModelRef eligibleCheckpoint
                  acceptEligible eligibleModel @?= "exp1"
                  ProductPipeline.modelRefManifestSha eligibleModel @?= Just "manifest-sha"
                  ProductPipeline.modelRefCompletedTraining eligibleModel @?= Just completed
          , testCase "Every ProductRow has a concrete numeric convergence bar" $ do
              let offenders =
                    [ ProductMatrix.rowId row
                    | row <- ProductMatrix.allProductRows
                    , let bar = ProductMatrix.convergenceBar row
                    , Text.null (ProductConvergence.convergenceMetricName bar)
                        || isNaN (ProductConvergence.convergenceThreshold bar)
                        || isInfinite (ProductConvergence.convergenceThreshold bar)
                    ]
              offenders @?= []
          , testCase "ProductTruth scanner rejects Sprint 20 fossil source mentions" $ do
              let findings =
                    ProductTruth.scanProductTruthSourceText
                      "src/JitML/RL/Reintroduced.hs"
                      "module JitML.RL.Reintroduced where\nx = deterministicStep\n"
              assertBool
                "deterministicStep source mention is rejected"
                ( any
                    ((== "product-truth.scaffold.deterministicStep") . findingKey)
                    findings
                )
          , testCase "ProductTruth scanner rejects seeded demo artifact literals" $ do
              let findings =
                    ProductTruth.scanProductTruthSourceText
                      "src/JitML/Product/ReintroducedSeed.hs"
                      "module JitML.Product.ReintroducedSeed where\nx = \"mnist-demo-weights\"\n"
              assertBool
                "seeded demo artifact literal is rejected"
                ( any
                    ((== "product-truth.scaffold.seeded-demo-weights") . findingKey)
                    findings
                )
          , testCase "ProductTruth reachability rejects product-reachable scaffold imports" $ do
              let modules =
                    [ ProductTruth.SourceModule
                        "JitML.App"
                        "src/JitML/App.hs"
                        ["JitML.Product.Reintroduced"]
                    , ProductTruth.SourceModule
                        "JitML.Product.Reintroduced"
                        "src/JitML/Product/Reintroduced.hs"
                        ["JitML.RL.Loop"]
                    ]
                  findings = ProductTruth.scanProductTruthImports modules
              assertBool
                "reachable JitML.RL.Loop import is rejected"
                ( any
                    ((== "product-truth.reachable-import") . findingKey)
                    findings
                )
          , testCase "ProductTruth reachability permits the real VecEnv module" $ do
              let modules =
                    [ ProductTruth.SourceModule
                        "JitML.App"
                        "src/JitML/App.hs"
                        ["JitML.RL.Algorithms.PpoTrainer"]
                    , ProductTruth.SourceModule
                        "JitML.RL.Algorithms.PpoTrainer"
                        "src/JitML/RL/Algorithms/PpoTrainer.hs"
                        ["JitML.RL.VecEnv"]
                    , ProductTruth.SourceModule
                        "JitML.RL.VecEnv"
                        "src/JitML/RL/VecEnv.hs"
                        []
                    ]
                  findings = ProductTruth.scanProductTruthImports modules
              findings @?= []
          , testCase "ProductRow implementations do not name non-product scaffolding" $ do
              let offenders =
                    [ (ProductMatrix.rowId row, ProductMatrix.implementation row, scaffold)
                    | row <- ProductMatrix.allProductRows
                    , scaffold <- ProductTruth.nonProductScaffolding
                    , Text.toLower scaffold
                        `Text.isInfixOf` Text.toLower (ProductMatrix.implementation row)
                    ]
              offenders @?= []
          ]
      , testGroup
          "Product phase status registry (Sprint 19.2)"
          [ testCase "enumerates product phases 19 through 34" $ do
              PhaseStatus.productPhaseNumbers @?= [19 .. 34]
              PhaseStatus.validateProductPhaseStatuses PhaseStatus.allProductPhaseStatuses @?= []
          , testCase "reports incomplete while any product sprint is open" $ do
              PhaseStatus.allProductPhasesDone @?= False
              assertBool
                "an all-Done registry satisfies the predicate"
                ( PhaseStatus.productPhasesDone
                    (fmap markProductPhaseDone PhaseStatus.allProductPhaseStatuses)
                )
              assertBool
                "a registry with any non-Done sprint remains incomplete"
                ( not
                    ( PhaseStatus.productPhasesDone
                        (demoteFirstProductSprint PhaseStatus.allProductPhaseStatuses)
                    )
                )
          , testCase "matches the sprint Status headers in phase documents" $ do
              actual <- concat <$> traverse readPlanSprintStatuses PhaseStatus.allProductPhaseStatuses
              let expected = concatMap registrySprintStatuses PhaseStatus.allProductPhaseStatuses
              actual @?= expected
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
          [ testCase "GC event route emits a substrate-scoped persistent path" $ do
              fmap Topology.topicName (Topology.topicFor Topology.GcEventRoute Substrate.LinuxCUDA)
                @?= Right "persistent://public/default/gc.event.linux-cuda"
              fmap Topology.topicName (Topology.topicFor Topology.GcEventRoute Substrate.LinuxCPU)
                @?= Right "persistent://public/default/gc.event.linux-cpu"
              fmap Topology.topicName (Topology.topicFor Topology.GcEventRoute Substrate.AppleSilicon)
                @?= Right "persistent://public/default/gc.event.apple-silicon"
          , testCase "GcReapedEvent round-trips through proto3-compatible bytes" $ do
              let envelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-13.7"
                      , ProtoGc.gcEventManifestSha = "sha256:reaped"
                      , ProtoGc.gcEventReapedBlobShas = ["blob-a", "blob-b"]
                      , ProtoGc.gcEventStepAtReap = 42
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCUDA
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
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                      , ProtoGc.gcEventTimestampNs = 1
                      }
              ProtoGc.parseGcReapedEvent (ProtoGc.renderGcReapedEvent envelope)
                @?= Right envelope
          , testCase "GcReapedEvent with no reaped blobs round-trips" $ do
              let envelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-no-blobs"
                      , ProtoGc.gcEventManifestSha = "sha256:lonely"
                      , ProtoGc.gcEventReapedBlobShas = []
                      , ProtoGc.gcEventStepAtReap = 0
                      , ProtoGc.gcEventSubstrate = Substrate.AppleSilicon
                      , ProtoGc.gcEventTimestampNs = 0
                      }
              ProtoGc.decodeGcReapedEventProto (ProtoGc.encodeGcReapedEventProto envelope)
                @?= Right envelope
              ProtoGc.parseGcReapedEvent (ProtoGc.renderGcReapedEvent envelope)
                @?= Right envelope
          , testCase "GcReapedEvent text decoder rejects structural and scalar defects" $ do
              let envelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-strict"
                      , ProtoGc.gcEventManifestSha = "sha256:strict"
                      , ProtoGc.gcEventReapedBlobShas = ["blob-a", "blob-b"]
                      , ProtoGc.gcEventStepAtReap = 9
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                      , ProtoGc.gcEventTimestampNs = 10
                      }
                  validPayload = ProtoGc.renderGcReapedEvent envelope
                  withoutManifest =
                    Text.unlines
                      ( filter
                          (not . Text.isPrefixOf "manifest-sha:")
                          (Text.lines validPayload)
                      )
                  rejectedPayloads =
                    [ ("unknown field", validPayload <> "unexpected: value\n")
                    , ("duplicate field", validPayload <> "manifest-sha: sha256:duplicate\n")
                    , ("malformed line", Text.replace "step-at-reap: 9" "step-at-reap 9" validPayload)
                    , ("missing field", withoutManifest)
                    , ("empty field", Text.replace "experiment-hash: exp-strict" "experiment-hash: " validPayload)
                    , ("malformed number", Text.replace "step-at-reap: 9" "step-at-reap: nine" validPayload)
                    , ("noncanonical substrate", Text.replace "substrate: linux-cpu" "substrate: cpu" validPayload)
                    , ("empty blob member", Text.replace "blob-a,blob-b" "blob-a,,blob-b" validPayload)
                    ]
              traverse_
                ( \(label, rejectedPayload) ->
                    case ProtoGc.parseGcReapedEvent rejectedPayload of
                      Left _ -> pure ()
                      Right decoded ->
                        assertFailure
                          (label <> " unexpectedly decoded as " <> show decoded)
                )
                rejectedPayloads
          , testCase
              "GcReapedEvent protobuf decoder rejects unknown, duplicate, malformed, missing, and empty fields"
              $ do
                let envelope =
                      ProtoGc.GcReapedEvent
                        { ProtoGc.gcEventExperimentHash = "exp-proto-strict"
                        , ProtoGc.gcEventManifestSha = "sha256:proto-strict"
                        , ProtoGc.gcEventReapedBlobShas = ["blob-a"]
                        , ProtoGc.gcEventStepAtReap = 11
                        , ProtoGc.gcEventSubstrate = Substrate.LinuxCUDA
                        , ProtoGc.gcEventTimestampNs = 12
                        }
                    validBytes = ProtoGc.encodeGcReapedEventProto envelope
                    requiredFields substrateField =
                      [ ProtoWire.stringField 1 "exp-proto-strict"
                      , ProtoWire.stringField 2 "sha256:proto-strict"
                      , ProtoWire.stringField 3 "blob-a"
                      , ProtoWire.uint64Field 4 11
                      , ProtoWire.stringField 5 substrateField
                      , ProtoWire.uint64Field 6 12
                      ]
                    rejectedBytes =
                      [ validBytes <> ProtoWire.encodeMessage [ProtoWire.stringField 7 "unknown"]
                      , validBytes <> ProtoWire.encodeMessage [ProtoWire.stringField 1 "duplicate"]
                      , ProtoWire.encodeMessage
                          ( ProtoWire.stringField 4 "eleven"
                              : filter ((/= 4) . ProtoWire.protoFieldNumber) (requiredFields "linux-cuda")
                          )
                      , ProtoWire.encodeMessage
                          (filter ((/= 2) . ProtoWire.protoFieldNumber) (requiredFields "linux-cuda"))
                      , ProtoWire.encodeMessage
                          ( ProtoWire.stringField 1 ""
                              : filter ((/= 1) . ProtoWire.protoFieldNumber) (requiredFields "linux-cuda")
                          )
                      , ProtoWire.encodeMessage (requiredFields "cuda")
                      ]
                traverse_
                  ( \rejectedPayload ->
                      case ProtoGc.decodeGcReapedEventProto rejectedPayload of
                        Left _ -> pure ()
                        Right decoded ->
                          assertFailure
                            ("invalid protobuf unexpectedly decoded as " <> show decoded)
                  )
                  rejectedBytes
          , testCase "GcEventRoute rejects an envelope from another substrate lane" $ do
              let linuxEnvelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventExperimentHash = "exp-route"
                      , ProtoGc.gcEventManifestSha = "sha256:route"
                      , ProtoGc.gcEventReapedBlobShas = []
                      , ProtoGc.gcEventStepAtReap = 1
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                      , ProtoGc.gcEventTimestampNs = 2
                      }
                  cudaEnvelope =
                    linuxEnvelope
                      { ProtoGc.gcEventSubstrate = Substrate.LinuxCUDA
                      }
              case Topology.topicFor Topology.GcEventRoute Substrate.LinuxCPU of
                Left err -> assertFailure ("failed to resolve GC event route: " <> show err)
                Right topic -> do
                  Topology.decodeTopicPayload topic (ProtoGc.renderGcReapedEvent linuxEnvelope)
                    @?= Right linuxEnvelope
                  case Topology.decodeTopicPayload topic (ProtoGc.renderGcReapedEvent cudaEnvelope) of
                    Left _ -> pure ()
                    Right decoded ->
                      assertFailure
                        ("cross-lane GC event unexpectedly decoded as " <> show decoded)
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
          , testCase "categorical KL uses every action probability" $ do
              let actual =
                    TrpoLoss.categoricalKlDivergence
                      [[0.5, 0.5]]
                      [[0.75, 0.25]]
                  expected = 0.14384103622589042
              assertBool ("unexpected exact KL: " <> show actual) (abs (actual - expected) < 1.0e-15)
          , testCase "categorical KL handles legal-action masks and ignores zero old mass" $ do
              let maskedKl =
                    TrpoLoss.categoricalKlDivergence
                      [[0.0, 0.2, 0.8]]
                      [[0.0, 1.0 / 3.0, 2.0 / 3.0]]
                  expected = 0.04369212068196553
                  oldWithTwoIllegal = [[0.2, 0.0, 0.0, 0.8]]
                  illegalMassA = [[0.3, 0.1, 0.0, 0.6]]
                  illegalMassB = [[0.3, 0.0, 0.1, 0.6]]
              assertBool ("unexpected masked exact KL: " <> show maskedKl) (abs (maskedKl - expected) < 1.0e-15)
              TrpoLoss.categoricalKlDivergence oldWithTwoIllegal illegalMassA
                @?= TrpoLoss.categoricalKlDivergence oldWithTwoIllegal illegalMassB
          , testCase "TRPO KL and surrogate validation fail closed" $ do
              let nan = 0.0 / 0.0
                  infinity = 1.0 / 0.0
                  rejectedConstraints =
                    [ TrpoLoss.trpoKlConstraintSatisfied 0.01 [] []
                    , TrpoLoss.trpoKlConstraintSatisfied 0.01 [[0.5, 0.5]] []
                    , TrpoLoss.trpoKlConstraintSatisfied 0.01 [[0.5, 0.5]] [[1.0]]
                    , TrpoLoss.trpoKlConstraintSatisfied 0.01 [[0.5, 0.5]] [[1.0, 0.0]]
                    , TrpoLoss.trpoKlConstraintSatisfied 0.01 [[0.5, 0.5]] [[nan, 0.5]]
                    , TrpoLoss.trpoKlConstraintSatisfied infinity [[0.5, 0.5]] [[0.5, 0.5]]
                    , TrpoLoss.trpoKlConstraintSatisfied 0.01 [[0.0, 0.0]] [[0.0, 0.0]]
                    ]
                  rejectedSurrogates =
                    [ TrpoLoss.trpoSurrogate [] [] []
                    , TrpoLoss.trpoSurrogate [0.0] [] [1.0]
                    , TrpoLoss.trpoSurrogate [0.0] [nan] [1.0]
                    , TrpoLoss.trpoSurrogate [0.0] [infinity] [1.0]
                    ]
              assertBool "malformed/non-finite KL input was accepted" (not (or rejectedConstraints))
              assertBool "malformed/non-finite surrogate did not fail closed" (all isInfinite rejectedSurrogates)
          , testCase "trpoKlConstraintSatisfied applies the exact categorical threshold" $ do
              TrpoLoss.trpoKlConstraintSatisfied 0.15 [[0.5, 0.5]] [[0.75, 0.25]] @?= True
              TrpoLoss.trpoKlConstraintSatisfied 0.10 [[0.5, 0.5]] [[0.75, 0.25]] @?= False
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
          , testCase "MLP is expressible as a two-layer LayerGraph (Sprint 23.1)" $ do
              let shape = Mlp.MlpShape 4 8 3
                  params = Mlp.mlpInit shape 7
                  input = Data.Vector.Unboxed.fromList [0.1, 0.2, 0.3, 0.4]
                  expected = Mlp.forwardOutput (Mlp.mlpForward params input)
              graph <- either assertFailure pure (Mlp.mlpLayerGraph params)
              tape <- either (assertFailure . Text.unpack) pure (LayerGraph.runLayerGraph graph input)
              LayerGraph.layerTapeOutput tape @?= expected
          , testCase "LayerGraph finite-difference gradients cover every layer kind (Sprint 23.1)" $
              Control.Monad.forM_ (zip [1 :: Int ..] LayerGraph.allLayerKinds) $ \(seed, kind) -> do
                graph <- either (assertFailure . Text.unpack) pure (unitLayerGraph kind seed)
                let input = Data.Vector.Unboxed.fromList [0.2, -0.3, 0.4]
                    target = Data.Vector.Unboxed.fromList [0.1, -0.2, 0.3]
                err <-
                  either
                    (assertFailure . Text.unpack)
                    pure
                    (Autodiff.maxFiniteDifferenceError 1.0e-5 graph input target)
                assertBool
                  (Text.unpack (LayerGraph.layerKindName kind) <> " finite-difference error too large: " <> show err)
                  (err < 1.0e-4)
          , testCase "LayerGraph gradients are deterministic for a ResNet-shaped graph (Sprint 23.1)" $ do
              graph <- either (assertFailure . Text.unpack) pure (resNetShapedLayerGraph 17)
              let input = Data.Vector.Unboxed.fromList [0.2, -0.3, 0.4]
                  target = Data.Vector.Unboxed.fromList [0.0, 0.1, -0.1]
                  gradA =
                    fmap snd (LayerGraph.layerGraphSquaredErrorGradient graph input target)
                  gradB =
                    fmap snd (LayerGraph.layerGraphSquaredErrorGradient graph input target)
              gradA @?= gradB
          , testCase "LayerGraph supports a ViT-shaped patch plus attention graph (Sprint 23.1)" $ do
              graph <- either (assertFailure . Text.unpack) pure (vitShapedLayerGraph 23)
              let input = Data.Vector.Unboxed.fromList [0.1, 0.0, -0.2, 0.3]
                  target = Data.Vector.Unboxed.fromList [0.0, 0.2, -0.1]
              (tape, gradient) <-
                either
                  (assertFailure . Text.unpack)
                  pure
                  (LayerGraph.layerGraphSquaredErrorGradient graph input target)
              Data.Vector.Unboxed.length (LayerGraph.layerTapeOutput tape) @?= 3
              length (LayerGraph.layerGraphLayerGradients gradient) @?= 3
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
          , testCase "TRPO defaults match the catalog trust-region target" $ do
              PpoTrainer.ppoKlTarget PpoTrainer.defaultPpoTrainConfig @?= 0.01
              PpoTrainer.ppoTrpoCriticUpdates PpoTrainer.defaultPpoTrainConfig @?= 10
              PpoTrainer.ppoTrpoCriticLearningRate PpoTrainer.defaultPpoTrainConfig @?= 1.0e-3
              fmap
                AlgorithmCommon.hyperValue
                ( find
                    ((== "max-kl") . AlgorithmCommon.hyperName)
                    Trpo.trpoHyperparameters
                )
                @?= Just "0.01"
              fmap
                AlgorithmCommon.hyperValue
                ( find
                    ((== "cg-damping") . AlgorithmCommon.hyperName)
                    Trpo.trpoHyperparameters
                )
                @?= Just "0.1"
              fmap
                AlgorithmCommon.hyperValue
                ( find
                    ((== "critic-updates") . AlgorithmCommon.hyperName)
                    Trpo.trpoHyperparameters
                )
                @?= Just "10"
              fmap
                AlgorithmCommon.hyperValue
                ( find
                    ((== "value-learning-rate") . AlgorithmCommon.hyperName)
                    Trpo.trpoHyperparameters
                )
                @?= Just "0.001"
          , testCase "pure TRPO ignores PPO epochs and performs configured critic passes" $ do
              let config =
                    PpoTrainer.defaultPpoTrainConfig
                      { PpoTrainer.ppoHiddenUnits = 4
                      , PpoTrainer.ppoActionCount = 2
                      , PpoTrainer.ppoObsSize = 4
                      , PpoTrainer.ppoVariant = PpoTrainer.VariantTRPO
                      }
                  params = PpoTrainer.initialPpoParams config
                  adam = Mlp.adamInit (Mlp.MlpShape 4 4 3)
                  observationRows =
                    [ ([0.0, 0.0, 0.0, 0.0], 0, 1.0)
                    , ([0.2, -0.1, 0.3, -0.2], 1, -0.5)
                    , ([-0.4, 0.1, -0.2, 0.5], 0, 0.75)
                    , ([0.6, -0.3, 0.2, -0.1], 1, -1.25)
                    ]
                  batch = fmap (mkTrpoStep config params) observationRows
                  oneEpoch = config {PpoTrainer.ppoEpochsPerUpdate = 1}
                  manyEpochs = config {PpoTrainer.ppoEpochsPerUpdate = 17}
                  resultOne@(paramsOne, adamOne) = PpoTrainer.ppoUpdate oneEpoch params adam batch
                  resultMany = PpoTrainer.ppoUpdate manyEpochs params adam batch
              resultMany @?= resultOne
              Mlp.adamStep_ adamOne
                @?= PpoTrainer.ppoTrpoCriticUpdates config
              assertBool "TRPO update was vacuous" (paramsOne /= params)
          , testCase "TRPO critic passes recompute finite gradients and reduce value MSE" $ do
              let config =
                    smallTrpoConfig
                      { PpoTrainer.ppoMiniBatchSize = 2
                      , PpoTrainer.ppoTrpoCriticUpdates = 10
                      , PpoTrainer.ppoTrpoCriticLearningRate = 0.01
                      }
                  params = PpoTrainer.initialPpoParams config
                  adam = Mlp.adamInit (Mlp.paramShape params)
                  rows =
                    [ ([0.0, 0.0, 0.0, 0.0], 0, 0.8)
                    , ([0.2, -0.1, 0.3, -0.2], 1, -0.6)
                    , ([-0.4, 0.1, -0.2, 0.5], 0, 0.4)
                    , ([0.6, -0.3, 0.2, -0.1], 1, -0.2)
                    ]
                  batch =
                    [ let (step, _, _) = mkTrpoStep config params (observation, action, 0.0)
                       in (step, 0.0, target)
                    | (observation, action, target) <- rows
                    ]
                  initialMse = trpoValueMse config params batch
                  result@(updated, updatedAdam) = PpoTrainer.ppoUpdate config params adam batch
                  repeated = PpoTrainer.ppoUpdate config params adam batch
                  finalMse = trpoValueMse config updated batch
              repeated @?= result
              Mlp.adamStep_ updatedAdam @?= 20
              assertBool "TRPO critic produced non-finite value MSE" (not (isNaN finalMse || isInfinite finalMse))
              assertBool
                ("TRPO critic did not reduce value MSE: " <> show initialMse <> " -> " <> show finalMse)
                (finalMse < initialMse)
          , testCase "TRPO rejects invalid critic fitting configuration and Adam variance" $ do
              let params = PpoTrainer.initialPpoParams smallTrpoConfig
                  adam = Mlp.adamInit (Mlp.paramShape params)
                  sample@(step, advantage, target) =
                    mkTrpoStep smallTrpoConfig params ([0.2, -0.1, 0.3, -0.4], 0, 1.0)
                  batch = [sample]
                  invalidConfigs =
                    [ smallTrpoConfig {PpoTrainer.ppoTrpoCriticUpdates = 0}
                    , smallTrpoConfig {PpoTrainer.ppoMiniBatchSize = 0}
                    , smallTrpoConfig {PpoTrainer.ppoTrpoCriticLearningRate = 0.0}
                    ]
                  negativeVariance =
                    adam
                      { Mlp.adamV = constantGradientLike params (-0.1)
                      }
                  staleBatch =
                    [
                      ( step
                          { PpoTrainer.rsPolicy = Data.Vector.Unboxed.fromList [0.9, 0.1]
                          , PpoTrainer.rsLogProb = log 0.9
                          }
                      , advantage
                      , target
                      )
                    ]
              map
                (\config -> PpoTrainer.ppoUpdate config params adam batch)
                invalidConfigs
                @?= replicate (length invalidConfigs) (params, adam)
              PpoTrainer.trpoCriticStep
                smallTrpoConfig
                params
                negativeVariance
                (constantGradientLike params 0.25)
                @?= (params, negativeVariance)
              PpoTrainer.ppoUpdate smallTrpoConfig params adam staleBatch
                @?= (params, adam)
          , testCase "device TRPO ignores PPO epochs" $ do
              let runWithEpochs epochs = do
                    gradientCalls <- newIORef (0 :: Int)
                    let referenceBatchGradient = mlpdBatchGradient pureReferenceMlpDevice
                        countingDevice =
                          pureReferenceMlpDevice
                            { mlpdBatchGradient = \params batch -> do
                                modifyIORef' gradientCalls (+ 1)
                                referenceBatchGradient params batch
                            }
                        smallConfig =
                          PpoTrainer.defaultPpoTrainConfig
                            { PpoTrainer.ppoSeed = 29
                            , PpoTrainer.ppoHiddenUnits = 4
                            , PpoTrainer.ppoVectorEnvCount = 1
                            , PpoTrainer.ppoRolloutSteps = 4
                            , PpoTrainer.ppoNumIterations = 1
                            , PpoTrainer.ppoEpochsPerUpdate = epochs
                            , PpoTrainer.ppoMiniBatchSize = 4
                            , PpoTrainer.ppoMaxEpisodeSteps = 10
                            , PpoTrainer.ppoVariant = PpoTrainer.VariantTRPO
                            }
                    result <-
                      PpoTrainer.trainOnPolicyOnDeviceWithEnvironment
                        countingDevice
                        (Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment)
                        PpoTrainer.VariantTRPO
                        smallConfig
                    calls <- readIORef gradientCalls
                    pure (calls, fmap PpoTrainer.resultFinalParams result)
              oneEpoch <- runWithEpochs 1
              manyEpochs <- runWithEpochs 17
              oneEpoch @?= manyEpochs
          , testCase "device TRPO recomputes every critic minibatch and matches the pure reference" $ do
              let config =
                    smallTrpoConfig
                      { PpoTrainer.ppoMiniBatchSize = 2
                      , PpoTrainer.ppoTrpoCriticUpdates = 3
                      , PpoTrainer.ppoTrpoCriticLearningRate = 0.01
                      }
                  params = PpoTrainer.initialPpoParams config
                  adam = Mlp.adamInit (Mlp.paramShape params)
                  rows =
                    [ ([0.0, 0.0, 0.0, 0.0], 0, 10.0)
                    , ([0.2, -0.1, 0.3, -0.2], 1, -10.0)
                    , ([-0.4, 0.1, -0.2, 0.5], 0, 8.0)
                    , ([0.6, -0.3, 0.2, -0.1], 1, -8.0)
                    ]
                  batch =
                    [ let (step, _, _) = mkTrpoStep config params (observation, action, 0.0)
                       in (step, 0.0, target)
                    | (observation, action, target) <- rows
                    ]
                  actionCount = PpoTrainer.ppoActionCount config
                  expectedCriticCalls =
                    PpoTrainer.ppoTrpoCriticUpdates config
                      * ( (length batch + PpoTrainer.ppoMiniBatchSize config - 1)
                            `div` PpoTrainer.ppoMiniBatchSize config
                        )
                  referenceGradient = mlpdBatchGradient pureReferenceMlpDevice
              kindsRef <- newIORef ([] :: [Text])
              criticParamsRef <- newIORef ([] :: [Mlp.MlpParams])
              let recordingDevice =
                    pureReferenceMlpDevice
                      { mlpdBatchGradient = \current pairs -> do
                          let kind = trpoGradientCallKind actionCount pairs
                          modifyIORef' kindsRef (<> [kind])
                          Control.Monad.when (kind == "critic") $
                            modifyIORef' criticParamsRef (<> [current])
                          referenceGradient current pairs
                      }
                  expected = PpoTrainer.ppoUpdate config params adam batch
              actual <-
                PpoTrainer.ppoUpdateDevice recordingDevice config params adam batch
              actual @?= Right expected
              case actual of
                Left err -> assertFailure (Text.unpack err)
                Right (_, actualAdam) -> Mlp.adamStep_ actualAdam @?= expectedCriticCalls
              kinds <- readIORef kindsRef
              criticSnapshots <- readIORef criticParamsRef
              length (filter (== "actor-or-fisher") kinds) @?= 1
              length (filter (== "critic") kinds) @?= expectedCriticCalls
              assertBool
                "unexpected mixed or malformed TRPO gradient call"
                (all (`elem` ["actor-or-fisher", "critic"]) kinds)
              assertBool
                "critic callback did not receive freshly updated parameters"
                ( and
                    ( zipWith
                        (\before after -> maxParameterDifference before after > 0.0)
                        criticSnapshots
                        ( case criticSnapshots of
                            [] -> []
                            _ : remainingSnapshots -> remainingSnapshots
                        )
                    )
                )
          , testCase "device TRPO propagates an injected mid-critic failure" $ do
              let config =
                    smallTrpoConfig
                      { PpoTrainer.ppoMiniBatchSize = 2
                      , PpoTrainer.ppoTrpoCriticUpdates = 3
                      , PpoTrainer.ppoTrpoCriticLearningRate = 0.01
                      }
                  params = PpoTrainer.initialPpoParams config
                  adam = Mlp.adamInit (Mlp.paramShape params)
                  rows =
                    [ ([0.0, 0.0, 0.0, 0.0], 0, 1.0, 10.0)
                    , ([0.2, -0.1, 0.3, -0.2], 1, -0.5, -10.0)
                    , ([-0.4, 0.1, -0.2, 0.5], 0, 0.75, 8.0)
                    , ([0.6, -0.3, 0.2, -0.1], 1, -1.25, -8.0)
                    ]
                  batch =
                    [ let (step, _, _) = mkTrpoStep config params (observation, action, advantage)
                       in (step, advantage, target)
                    | (observation, action, advantage, target) <- rows
                    ]
                  actionCount = PpoTrainer.ppoActionCount config
                  referenceGradient = mlpdBatchGradient pureReferenceMlpDevice
              kindsRef <- newIORef ([] :: [Text])
              criticCallsRef <- newIORef (0 :: Int)
              let failingDevice =
                    pureReferenceMlpDevice
                      { mlpdBatchGradient = \current pairs -> do
                          let kind = trpoGradientCallKind actionCount pairs
                          modifyIORef' kindsRef (<> [kind])
                          if kind == "critic"
                            then do
                              modifyIORef' criticCallsRef (+ 1)
                              call <- readIORef criticCallsRef
                              if call == 3
                                then pure (Left "injected TRPO mid-critic failure")
                                else referenceGradient current pairs
                            else referenceGradient current pairs
                      }
              assertLeftContains
                "injected TRPO mid-critic failure"
                (PpoTrainer.ppoUpdateDevice failingDevice config params adam batch)
              criticCalls <- readIORef criticCallsRef
              kinds <- readIORef kindsRef
              criticCalls @?= 3
              assertBool
                "test did not exercise actor Fisher calls"
                (length (filter (== "actor-or-fisher") kinds) > 1)
              assertBool
                "unexpected mixed or malformed TRPO gradient call"
                (all (`elem` ["actor-or-fisher", "critic"]) kinds)
          , testCase "TRPO critic preserves every actor parameter despite stale Adam moments" $ do
              let config =
                    PpoTrainer.defaultPpoTrainConfig
                      { PpoTrainer.ppoHiddenUnits = 4
                      , PpoTrainer.ppoActionCount = 2
                      , PpoTrainer.ppoObsSize = 4
                      , PpoTrainer.ppoLearningRate = 0.01
                      , PpoTrainer.ppoVariant = PpoTrainer.VariantTRPO
                      }
                  params = PpoTrainer.initialPpoParams config
                  fullGradient = constantGradientLike params 0.25
                  staleAdam =
                    Mlp.AdamState
                      { Mlp.adamStep_ = 7
                      , Mlp.adamM = constantGradientLike params 0.4
                      , Mlp.adamV = constantGradientLike params 0.3
                      }
                  (updated, updatedAdam) =
                    PpoTrainer.trpoCriticStep config params staleAdam fullGradient
                  hiddenCount = 4
                  policyWeightCount = 2 * hiddenCount
                  observation = Data.Vector.Unboxed.fromList [0.2, -0.1, 0.3, -0.4]
                  oldPolicy =
                    Mlp.pvPolicy
                      (Mlp.policyValueForwardWith Mlp.LinearValueHead params 2 observation)
                  newPolicy =
                    Mlp.pvPolicy
                      (Mlp.policyValueForwardWith Mlp.LinearValueHead updated 2 observation)
                  actorMomentsZero moment =
                    Data.Vector.Unboxed.all (== 0.0) (Mlp.gradW1 moment)
                      && Data.Vector.Unboxed.all (== 0.0) (Mlp.gradB1 moment)
                      && Data.Vector.Unboxed.all (== 0.0) (Data.Vector.Unboxed.take policyWeightCount (Mlp.gradW2 moment))
                      && Data.Vector.Unboxed.all (== 0.0) (Data.Vector.Unboxed.take 2 (Mlp.gradB2 moment))
              Mlp.paramW1 updated @?= Mlp.paramW1 params
              Mlp.paramB1 updated @?= Mlp.paramB1 params
              Data.Vector.Unboxed.take policyWeightCount (Mlp.paramW2 updated)
                @?= Data.Vector.Unboxed.take policyWeightCount (Mlp.paramW2 params)
              Data.Vector.Unboxed.take 2 (Mlp.paramB2 updated)
                @?= Data.Vector.Unboxed.take 2 (Mlp.paramB2 params)
              newPolicy @?= oldPolicy
              assertBool
                "critic did not update its value-only row/bias"
                ( Data.Vector.Unboxed.drop policyWeightCount (Mlp.paramW2 updated)
                    /= Data.Vector.Unboxed.drop policyWeightCount (Mlp.paramW2 params)
                    || Data.Vector.Unboxed.drop 2 (Mlp.paramB2 updated)
                      /= Data.Vector.Unboxed.drop 2 (Mlp.paramB2 params)
                )
              assertBool "critic left actor first moments populated" (actorMomentsZero (Mlp.adamM updatedAdam))
              assertBool "critic left actor second moments populated" (actorMomentsZero (Mlp.adamV updatedAdam))
          , testCase "TRPO line search accepts only a strict finite-KL improvement and otherwise rolls back" $ do
              let config = smallTrpoConfig
                  params = PpoTrainer.initialPpoParams config
                  adam = Mlp.adamInit (Mlp.paramShape params)
                  batch = [mkTrpoStep config params ([0.2, -0.1, 0.3, -0.4], 0, 1.0)]
                  direction = policyBiasGradient config batch params
                  (accepted, _) =
                    PpoTrainer.trpoLineSearchUpdate config batch params adam direction
                  zeroAdvantage = [(step, 0.0, target) | (step, _, target) <- batch]
                  (strictRollback, _) =
                    PpoTrainer.trpoLineSearchUpdate config zeroAdvantage params adam direction
                  staleBatch =
                    [ ( step
                          { PpoTrainer.rsPolicy = Data.Vector.Unboxed.fromList [0.9, 0.1]
                          , PpoTrainer.rsLogProb = log 0.9
                          }
                      , advantage
                      , target
                      )
                    | (step, advantage, target) <- batch
                    ]
                  (staleRollback, _) =
                    PpoTrainer.trpoLineSearchUpdate config staleBatch params adam direction
                  oldPolicies = trpoPolicies batch
                  acceptedPolicies = trpoPoliciesAt config accepted batch
                  oldLogProbs = [PpoTrainer.rsLogProb step | (step, _, _) <- batch]
                  acceptedLogProbs = selectedLogProbs config accepted batch
                  advantages = [advantage | (_, advantage, _) <- batch]
                  exactKl =
                    TrpoLoss.categoricalKlDivergence oldPolicies acceptedPolicies
                  oldLoss = TrpoLoss.trpoSurrogate oldLogProbs oldLogProbs advantages
                  acceptedLoss = TrpoLoss.trpoSurrogate oldLogProbs acceptedLogProbs advantages
              assertBool "valid TRPO direction was not accepted" (accepted /= params)
              assertBool "accepted TRPO KL was non-finite" (not (isNaN exactKl || isInfinite exactKl))
              assertBool "accepted TRPO KL exceeded its target" (exactKl <= PpoTrainer.ppoKlTarget config)
              assertBool "accepted TRPO surrogate was not a strict improvement" (acceptedLoss < oldLoss)
              strictRollback @?= params
              staleRollback @?= params
          , testCase "TRPO Fisher is advantage-independent, PSD, and matches finite-difference KL curvature" $ do
              let config = smallTrpoConfig {PpoTrainer.ppoTrpoCgDamping = 0.0}
                  params = PpoTrainer.initialPpoParams config
                  rows =
                    [ ([0.0, 0.0, 0.0, 0.0], 0, 1.0)
                    , ([0.2, -0.1, 0.3, -0.2], 1, -0.5)
                    , ([-0.4, 0.1, -0.2, 0.5], 0, 0.75)
                    ]
                  batch = fmap (mkTrpoStep config params) rows
                  differentAdvantages =
                    [(step, advantage * 100.0 - 17.0, target) | (step, advantage, target) <- batch]
                  direction = deterministicGradientLike params
                  productA =
                    PpoTrainer.trpoFisherVectorProduct config batch params direction
                  productB =
                    PpoTrainer.trpoFisherVectorProduct config differentAdvantages params direction
                  curvature = gradientDotForTest direction productA
                  epsilon = 1.0e-4
                  plusParams = addGradientToParams epsilon direction params
                  minusParams = addGradientToParams (-epsilon) direction params
                  oldPolicies = trpoPolicies batch
                  plusKl =
                    TrpoLoss.categoricalKlDivergence oldPolicies (trpoPoliciesAt config plusParams batch)
                  minusKl =
                    TrpoLoss.categoricalKlDivergence oldPolicies (trpoPoliciesAt config minusParams batch)
                  finiteDifferenceCurvature = (plusKl + minusKl) / (epsilon * epsilon)
              productB @?= productA
              assertBool "TRPO Fisher product contains a non-finite value" (gradientAllFinite productA)
              assertBool ("TRPO Fisher curvature was negative: " <> show curvature) (curvature >= -1.0e-12)
              assertBool
                ( "TRPO Fisher/finite-difference curvature mismatch: analytic="
                    <> show curvature
                    <> " finite-difference="
                    <> show finiteDifferenceCurvature
                )
                (abs (curvature - finiteDifferenceCurvature) < 1.0e-5)
          , testCase "device TRPO CG truncates late curvature loss but rejects an invalid first direction" $ do
              let params = PpoTrainer.initialPpoParams smallTrpoConfig
                  rhs = deterministicGradientLike params
              fisherCalls <- newIORef (0 :: Int)
              let finitePrecisionFisher direction = do
                    modifyIORef' fisherCalls (+ 1)
                    call <- readIORef fisherCalls
                    pure . Right $
                      if call == 2
                        then mapGradientForTest negate direction
                        else positiveDiagonalGradientForTest direction
              truncated <-
                PpoTrainer.conjugateGradientSolveDevice
                  10
                  finitePrecisionFisher
                  rhs
              solution <- either (assertFailure . Text.unpack) pure truncated
              calls <- readIORef fisherCalls
              calls @?= 2
              assertBool "truncated CG solution was non-finite" (gradientAllFinite solution)
              assertBool
                "truncated CG discarded its finite first iterate"
                (gradientDotForTest solution solution > 0.0)
              assertLeftContains
                "curvature is not positive"
                ( PpoTrainer.conjugateGradientSolveDevice
                    10
                    (pure . Right . mapGradientForTest negate)
                    rhs
                )
          , testCase "device TRPO line search makes a non-vacuous safe move and fails closed" $ do
              let config = smallTrpoConfig
                  params = PpoTrainer.initialPpoParams config
                  adam = Mlp.adamInit (Mlp.paramShape params)
                  batch = [mkTrpoStep config params ([0.2, -0.1, 0.3, -0.4], 0, 1.0)]
                  direction = policyBiasGradient config batch params
                  (pureAccepted, _) =
                    PpoTrainer.trpoLineSearchUpdate config batch params adam direction
              actual <-
                PpoTrainer.trpoLineSearchUpdateDevice
                  pureReferenceMlpDevice
                  config
                  batch
                  params
                  direction
              deviceAccepted <- either (assertFailure . Text.unpack) pure actual
              assertBool "pure TRPO reference did not move" (pureAccepted /= params)
              assertBool "device TRPO did not move" (deviceAccepted /= params)
              assertBool
                "pure/device TRPO line-search results diverged"
                (maxParameterDifference pureAccepted deviceAccepted < 1.0e-5)
              assertLeftContains
                "TRPO device line-search forward failed"
                ( PpoTrainer.trpoLineSearchUpdateDevice
                    (failingForwardBatchDevice "TRPO device line-search forward failed")
                    config
                    batch
                    params
                    direction
                )
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
          , testCase "DQN device trainer returns Left on forward failure" $
              assertLeftContains
                "dqn device forward kernel failed mid-run"
                ( DqnTrainer.trainDqnOnDevice
                    (failingForwardBatchDevice "dqn forward unavailable")
                    fastDqnDeviceConfig
                )
          , testCase "DQN device trainer returns Left on batch-gradient failure" $
              assertLeftContains
                "dqn device batch-gradient kernel failed mid-run"
                ( DqnTrainer.trainDqnOnDevice
                    (failingBatchGradientDevice "dqn gradient unavailable")
                    fastDqnDeviceConfig
                )
          ]
      , testGroup
          "Continuous actor-critic trainer (Sprint 13.8 DDPG/TD3/SAC/CrossQ/TQC)"
          ( [ testCase (show variant <> " trains end-to-end and is run-to-run deterministic") $ do
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
              <> [ testCase "continuous device trainer returns Left on input-gradient failure" $
                     assertLeftContains
                       "continuous device input-gradient kernel"
                       ( ContinuousTrainer.trainContinuousOnDevice
                           (failingInputGradientDevice "continuous input-gradient unavailable")
                           fastContinuousDeviceConfig
                       )
                 ]
          )
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
          , testCase "QR-DQN device trainer returns Left on forward failure" $
              assertLeftContains
                "qr-dqn device forward kernel failed mid-run"
                ( QrDqnTrainer.trainQrDqnOnDevice
                    (failingForwardBatchDevice "qr forward unavailable")
                    fastQrDqnDeviceConfig
                )
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
          , testCase "HER device trainer returns Left on batch-gradient failure" $
              assertLeftContains
                "her device batch-gradient kernel failed mid-run"
                ( HerTrainer.trainHerOnDevice
                    (failingBatchGradientDevice "her gradient unavailable")
                    fastHerDeviceConfig
                )
          ]
      ]

readmeProductParityFailures :: Text -> Either Text [Text]
readmeProductParityFailures readme = do
  documentedRows <- readmeProductRowIds readme
  documentedEnvironments <- readmeRlEnvironmentIds readme
  let registryRows = ProductMatrix.productRowIds
      registryEnvironments = registryRlEnvironmentIds
  pure $
    matrixSetFailures "README matrix row" documentedRows registryRows
      <> matrixSetFailures "README RL environment" documentedEnvironments registryEnvironments

readmeProductRowIds :: Text -> Either Text [Text]
readmeProductRowIds readme = do
  supervisedIds <-
    traverse
      readmeSupervisedRowId
      (markdownRowsBetween "# Canonical supervised learning problems" "## Dataset sources" readme)
  rlIds <- readmeRlProductRowIds readme
  alphaZeroIds <- readmeAlphaZeroProductRowIds readme
  pure $ supervisedIds <> rlIds <> alphaZeroIds <> ["hyperparameter-tuning"]

readmeRlEnvironmentIds :: Text -> Either Text [Text]
readmeRlEnvironmentIds readme =
  traverse
    readmeRlEnvironmentId
    (markdownRowsBetween "# Canonical reinforcement learning environments" "---" readme)

readmeRlProductRowIds :: Text -> Either Text [Text]
readmeRlProductRowIds readme =
  concat
    <$> traverse
      readmeRlTargetRowIds
      ( markdownRowsBetween
          "# Convergence and determinism checks for RL"
          "# AlphaZero-style self-play and persistent MCTS state"
          readme
      )

readmeAlphaZeroProductRowIds :: Text -> Either Text [Text]
readmeAlphaZeroProductRowIds readme = do
  gameIds <-
    traverse
      readmeAlphaZeroGameId
      (markdownRowsBetween "### Canonical adversarial games" "---" readme)
  pure [gameId | gameId <- gameIds, gameId `notElem` nonProductIds]
 where
  nonProductIds = fmap ProductMatrix.nonProductRowId ProductMatrix.nonProductRows

readmeSupervisedRowId :: [Text] -> Either Text Text
readmeSupervisedRowId cells =
  case cells of
    dataset : model : _ ->
      case (dataset, model) of
        ("MNIST", modelText)
          | "shallow MLP" `Text.isInfixOf` modelText ->
              Right "mnist-shallow-mlp"
        ("MNIST", modelText)
          | "deep MLP" `Text.isInfixOf` modelText ->
              Right "mnist-deep-mlp"
        ("MNIST", modelText)
          | "deep CNN" `Text.isInfixOf` modelText ->
              Right "mnist-lenet"
        ("Fashion-MNIST", modelText)
          | "shallow MLP" `Text.isInfixOf` modelText ->
              Right "fashion-mnist-mlp"
        ("Fashion-MNIST", modelText)
          | "small ResNet" `Text.isInfixOf` modelText ->
              Right "fashion-mnist-resnet"
        ("CIFAR-10", modelText)
          | "ResNet-20" `Text.isInfixOf` modelText ->
              Right "cifar10-resnet20"
        ("CIFAR-10", modelText)
          | "ResNet-56" `Text.isInfixOf` modelText ->
              Right "cifar10-resnet56"
        ("CIFAR-100", modelText)
          | "Wide ResNet-28-10" `Text.isInfixOf` modelText ->
              Right "cifar100-wide-resnet"
        ("CIFAR-10", modelText)
          | "small ViT" `Text.isInfixOf` modelText ->
              Right "cifar10-vit"
        ("Tiny ImageNet (200-class, 64x64)", modelText)
          | "ResNet-50" `Text.isInfixOf` modelText ->
              Right "tiny-imagenet-resnet50"
        ("Tiny ImageNet (200-class, 64×64)", modelText)
          | "ResNet-50" `Text.isInfixOf` modelText ->
              Right "tiny-imagenet-resnet50"
        ("California Housing (UCI tabular regression)", modelText)
          | "small MLP" `Text.isInfixOf` modelText ->
              Right "california-housing-mlp"
        _ ->
          Left ("unmapped README supervised row: " <> dataset <> " / " <> model)
    _ -> Left ("malformed README supervised row: " <> Text.intercalate " | " cells)

readmeRlEnvironmentId :: [Text] -> Either Text Text
readmeRlEnvironmentId cells =
  case cells of
    env : _ ->
      case env of
        "CartPole-v1" -> Right "cartpole"
        "MountainCar-v0" -> Right "mountain-car"
        "Acrobot-v1" -> Right "acrobot"
        "Pendulum-v1" -> Right "pendulum"
        "LunarLander-v2 (discrete)" -> Right "lunar-lander"
        "KeyDoorGrid-v0" -> Right "key-door-grid"
        "GridWorld-Deterministic-v0" -> Right "gridworld-deterministic"
        _ -> Left ("unmapped README RL environment row: " <> env)
    _ -> Left ("malformed README RL environment row: " <> Text.intercalate " | " cells)

readmeRlTargetRowIds :: [Text] -> Either Text [Text]
readmeRlTargetRowIds cells =
  case cells of
    familyCell : surface : _ ->
      case familyCell of
        "HER" -> Right ["HER/goal-reaching"]
        "AlphaZero" -> Right []
        "Environment-floor parity rows" ->
          traverse readmeExplicitRlPair (commaListBefore " median" surface)
        _ -> do
          algorithms <- traverse readmeRlAlgorithm (slashList familyCell)
          environments <- traverse readmeRlTargetEnvironment (commaListBefore " median" surface)
          pure [algorithm <> "/" <> environment | algorithm <- algorithms, environment <- environments]
    _ -> Left ("malformed README RL target row: " <> Text.intercalate " | " cells)

readmeExplicitRlPair :: Text -> Either Text Text
readmeExplicitRlPair pair =
  case Text.splitOn "/" pair of
    [algorithm, environment] -> do
      algorithmId <- readmeRlAlgorithm algorithm
      environmentId <- readmeRlTargetEnvironment environment
      pure (algorithmId <> "/" <> environmentId)
    _ -> Left ("malformed explicit RL pair: " <> pair)

readmeRlAlgorithm :: Text -> Either Text Text
readmeRlAlgorithm raw
  | raw `elem` ProductMatrix.floorRlAlgorithms ProductMatrix.matrixFloor =
      Right raw
  | otherwise =
      Left ("README names RL algorithm outside matrix floor: " <> raw)

readmeRlTargetEnvironment :: Text -> Either Text Text
readmeRlTargetEnvironment raw
  | raw `elem` ProductMatrix.floorRlEnvironments ProductMatrix.matrixFloor =
      Right raw
  | otherwise =
      Left ("README names RL environment outside matrix floor: " <> raw)

readmeAlphaZeroGameId :: [Text] -> Either Text Text
readmeAlphaZeroGameId cells =
  case cells of
    game : _ ->
      case game of
        "Tic-Tac-Toe" -> Right "tic-tac-toe"
        "Connect 4" -> Right "connect4"
        "Othello (Reversi)" -> Right "othello"
        "Gomoku-9x9" -> Right "gomoku"
        "Gomoku" -> Right "gomoku"
        "Hex-7x7" -> Right "hex"
        "Hex" -> Right "hex"
        _ -> Left ("unmapped README AlphaZero game row: " <> game)
    _ -> Left ("malformed README AlphaZero game row: " <> Text.intercalate " | " cells)

registryRlEnvironmentIds :: [Text]
registryRlEnvironmentIds =
  List.sort . nub $
    [ environment
    | row <- ProductMatrix.allProductRows
    , environment <- productRowRlEnvironments row
    ]

productRowRlEnvironments :: ProductRow state -> [Text]
productRowRlEnvironments row =
  case ProductMatrix.rowClass row of
    ProductMatrix.RlAlgorithmEnvironment _ environment -> [environment]
    ProductMatrix.RlGoalConditioned _ -> []
    _ -> []

productRowRlAlgorithms :: ProductRow state -> [Text]
productRowRlAlgorithms row =
  case ProductMatrix.rowClass row of
    ProductMatrix.RlAlgorithmEnvironment algorithm _ -> [algorithm]
    ProductMatrix.RlGoalConditioned _ -> ["HER"]
    _ -> []

registryModelMatrixPairs :: [(Text, Text, Text, Text, Text)]
registryModelMatrixPairs =
  [ ( generatedModelKind row
    , ProductMatrix.rowId row
    , ProductMatrix.productRowExperimentHash row
    , ProductMatrix.e2eTest row
    , ProductMatrix.demoPanel row
    )
  | row <- ProductMatrix.allProductRows
  ]

generatedModelKind :: ProductMatrix.ProductRow state -> Text
generatedModelKind row =
  case ProductMatrix.family row of
    ProductMatrix.Supervised -> "supervised"
    ProductMatrix.ReinforcementLearning ->
      case ProductMatrix.rowClass row of
        ProductMatrix.RlGoalConditioned _ -> "her"
        _ -> "rl"
    ProductMatrix.AlphaZero -> "alphazero"
    ProductMatrix.Tuning -> "tuning"

generatedModelMatrixPairs :: Text -> [(Text, Text, Text, Text, Text)]
generatedModelMatrixPairs generated =
  mapMaybe generatedModelMatrixPair (Text.lines generated)

generatedModelMatrixPair :: Text -> Maybe (Text, Text, Text, Text, Text)
generatedModelMatrixPair line = do
  kind <- quotedField "kind" line
  name <- quotedField "name" line
  experimentHash <- quotedField "experimentHash" line
  e2eTest <- quotedField "e2eTest" line
  demoPanel <- quotedField "demoPanel" line
  pure (kind, name, experimentHash, e2eTest, demoPanel)

quotedField :: Text -> Text -> Maybe Text
quotedField field line =
  let marker = field <> ": \""
      (_, markerAndRest) = Text.breakOn marker line
   in if Text.null markerAndRest
        then Nothing
        else
          let afterMarker = Text.drop (Text.length marker) markerAndRest
              (value, suffix) = Text.breakOn "\"" afterMarker
           in if Text.null suffix then Nothing else Just value

matrixSetFailures :: Text -> [Text] -> [Text] -> [Text]
matrixSetFailures label documented registry =
  missing <> unexpected <> duplicateDocs <> duplicateRegistry
 where
  documentedSorted = List.sort documented
  registrySorted = List.sort registry
  missing =
    [ label <> " documented but missing from registry: " <> rowId'
    | rowId' <- documentedSorted
    , rowId' `notElem` registry
    ]
  unexpected =
    [ label <> " registry row missing from docs: " <> rowId'
    | rowId' <- registrySorted
    , rowId' `notElem` documented
    ]
  duplicateDocs =
    [ label <> " documented more than once: " <> rowId'
    | rowId' <- duplicatesText documented
    ]
  duplicateRegistry =
    [ label <> " registry row duplicated: " <> rowId'
    | rowId' <- duplicatesText registry
    ]

markdownRowsBetween :: Text -> Text -> Text -> [[Text]]
markdownRowsBetween start end document =
  [ cells
  | line <- sectionLines start end document
  , let stripped = Text.strip line
  , "|" `Text.isPrefixOf` stripped
  , "|" `Text.isSuffixOf` stripped
  , let cells = markdownTableCells stripped
  , not (null cells)
  , not (markdownHeaderOrSeparator cells)
  ]

sectionLines :: Text -> Text -> Text -> [Text]
sectionLines start end document =
  case dropWhile ((/= start) . Text.strip) (Text.lines document) of
    [] -> []
    _ : rest -> takeWhile ((/= end) . Text.strip) rest

markdownTableCells :: Text -> [Text]
markdownTableCells line =
  case Text.splitOn "|" line of
    _ : cellsWithTail ->
      case reverse cellsWithTail of
        _ : cells -> fmap Text.strip (reverse cells)
        [] -> []
    [] -> []

markdownHeaderOrSeparator :: [Text] -> Bool
markdownHeaderOrSeparator cells =
  case cells of
    first : _
      | first
          `elem` [ "Dataset"
                 , "Env"
                 , "algorithm family"
                 , "Algorithm"
                 , "Game"
                 ] ->
          True
    _ -> all markdownSeparatorCell cells

markdownSeparatorCell :: Text -> Bool
markdownSeparatorCell cell =
  not (Text.null cell)
    && Text.all (\ch -> ch == '-' || ch == ':' || ch == ' ') cell

slashList :: Text -> [Text]
slashList = fmap Text.strip . Text.splitOn "/"

commaListBefore :: Text -> Text -> [Text]
commaListBefore marker =
  fmap Text.strip
    . Text.splitOn ","
    . fst
    . Text.breakOn marker

duplicatesText :: [Text] -> [Text]
duplicatesText values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]

unitLayerGraph :: LayerGraph.LayerKind -> Int -> Either Text LayerGraph.LayerGraph
unitLayerGraph kind seed = do
  node <-
    case kind of
      LayerGraph.PoolLayer _ ->
        LayerGraph.mkIdentityLayer
          "unit-pool"
          kind
          3
          LayerGraph.TrainingMode
      LayerGraph.DropoutLayer _ ->
        LayerGraph.mkIdentityLayer
          "unit-dropout"
          kind
          3
          LayerGraph.TrainingMode
      _ ->
        LayerGraph.mkAffineLayer
          "unit-layer"
          kind
          3
          3
          (activationForUnitKind kind)
          LayerGraph.TrainingMode
          (LayerGraph.deterministicParameters seed 3 3)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "unit-" <> LayerGraph.layerKindName kind
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphNodes = [node]
      }

activationForUnitKind :: LayerGraph.LayerKind -> LayerGraph.LayerActivation
activationForUnitKind kind =
  case kind of
    LayerGraph.NormLayer _ -> LayerGraph.LinearActivation
    LayerGraph.PoolLayer _ -> LayerGraph.LinearActivation
    LayerGraph.DropoutLayer _ -> LayerGraph.LinearActivation
    LayerGraph.DenseLayer -> LayerGraph.TanhActivation
    _ -> LayerGraph.TanhActivation

resNetShapedLayerGraph :: Int -> Either Text LayerGraph.LayerGraph
resNetShapedLayerGraph seed = do
  stem <-
    LayerGraph.mkAffineLayer
      "resnet-stem"
      LayerGraph.DenseLayer
      3
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters seed 3 3)
  block <-
    LayerGraph.mkAffineLayer
      "resnet-basic-block"
      (LayerGraph.BasicBlockLayer 0.1)
      3
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 1) 3 3)
  headNode <-
    LayerGraph.mkAffineLayer
      "resnet-head"
      LayerGraph.DenseLayer
      3
      3
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 2) 3 3)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "unit-resnet"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphNodes = [stem, block, headNode]
      }

vitShapedLayerGraph :: Int -> Either Text LayerGraph.LayerGraph
vitShapedLayerGraph seed = do
  patch <-
    LayerGraph.mkAffineLayer
      "vit-patch"
      LayerGraph.PatchEmbedLayer
      4
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters seed 4 3)
  attention <-
    LayerGraph.mkAffineLayer
      "vit-attention"
      (LayerGraph.MultiHeadAttentionLayer 1)
      3
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 1) 3 3)
  headNode <-
    LayerGraph.mkAffineLayer
      "vit-head"
      LayerGraph.DenseLayer
      3
      3
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 2) 3 3)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "unit-vit"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphNodes = [patch, attention, headNode]
      }

layerGraphCheckpointTensors :: LayerGraph.LayerGraph -> [Checkpoint.TensorBlob]
layerGraphCheckpointTensors =
  concatMap nodeTensors . LayerGraph.layerGraphNodes
 where
  nodeTensors node =
    case LayerGraph.layerParameters node of
      Nothing -> []
      Just _ ->
        let inputWidth = layerShapeWidth (LayerGraph.layerInputShape node)
            outputWidth = layerShapeWidth (LayerGraph.layerOutputShape node)
            weightName = LayerGraph.layerNodeName node <> ".weights"
            biasName = LayerGraph.layerNodeName node <> ".bias"
         in [ Checkpoint.TensorBlob
                weightName
                [outputWidth, inputWidth]
                ("jitml-checkpoints/exp-layergraph/blobs/" <> weightName)
            , Checkpoint.TensorBlob
                biasName
                [outputWidth]
                ("jitml-checkpoints/exp-layergraph/blobs/" <> biasName)
            ]

loadedLayerGraphWeights :: LayerGraph.LayerGraph -> [CheckpointStore.LoadedWeightTensor]
loadedLayerGraphWeights graph =
  concatMap loadedNode (LayerGraph.layerGraphNodes graph)
 where
  tensorByName =
    [(Checkpoint.tensorName tensor, tensor) | tensor <- layerGraphCheckpointTensors graph]
  loadedNode node =
    case LayerGraph.layerParameters node of
      Nothing -> []
      Just params ->
        [ CheckpointStore.LoadedWeightTensor
            (lookupTensor (LayerGraph.layerNodeName node <> ".weights"))
            (Data.Vector.Unboxed.toList (LayerGraph.layerWeights params))
        , CheckpointStore.LoadedWeightTensor
            (lookupTensor (LayerGraph.layerNodeName node <> ".bias"))
            (Data.Vector.Unboxed.toList (LayerGraph.layerBias params))
        ]
  lookupTensor name =
    case lookup name tensorByName of
      Just tensor -> tensor
      Nothing -> error ("missing layer graph test tensor " <> Text.unpack name)

layerShapeWidth :: LayerGraph.TensorShape -> Int
layerShapeWidth shape =
  case LayerGraph.tensorShapeWidth shape of
    Right width -> width
    Left err -> error (Text.unpack err)

assertLeftContains :: Text -> IO (Either Text a) -> Assertion
assertLeftContains expected action = do
  result <- action
  case result of
    Left err ->
      assertBool
        ("expected error to contain " <> Text.unpack expected <> ", got " <> Text.unpack err)
        (expected `Text.isInfixOf` err)
    Right _ -> assertFailure ("expected Left containing " <> Text.unpack expected)

assertDecodeFailure :: String -> RunConfig.RunConfigLoadResult a -> Assertion
assertDecodeFailure label result =
  case result of
    RunConfig.RunConfigDecodeFailed message ->
      assertBool (label <> " decode failure message should be non-empty") (not (Text.null message))
    other -> assertFailure (label <> " expected RunConfigDecodeFailed, got " <> showLoadResult other)
 where
  showLoadResult RunConfig.RunConfigMissing = "RunConfigMissing"
  showLoadResult (RunConfig.RunConfigLoaded _) = "RunConfigLoaded"
  showLoadResult (RunConfig.RunConfigDecodeFailed message) =
    "RunConfigDecodeFailed " <> Text.unpack message

failingForwardBatchDevice :: Text -> MlpDevice
failingForwardBatchDevice message =
  pureReferenceMlpDevice
    { mlpdForwardBatch = \_ _ -> pure (Left message)
    }

failingBatchGradientDevice :: Text -> MlpDevice
failingBatchGradientDevice message =
  pureReferenceMlpDevice
    { mlpdBatchGradient = \_ _ -> pure (Left message)
    }

failingInputGradientDevice :: Text -> MlpDevice
failingInputGradientDevice message =
  pureReferenceMlpDevice
    { mlpdInputGradientBatch = \_ _ -> pure (Left message)
    }

trpoGradientCallKind
  :: Int
  -> [(Data.Vector.Unboxed.Vector Double, Data.Vector.Unboxed.Vector Double)]
  -> Text
trpoGradientCallKind actionCount pairs
  | null pairs = "malformed"
  | any ((/= actionCount + 1) . Data.Vector.Unboxed.length . snd) pairs = "malformed"
  | all ((== 0.0) . (Data.Vector.Unboxed.! actionCount) . snd) pairs =
      "actor-or-fisher"
  | all
      ( Data.Vector.Unboxed.all (== 0.0)
          . Data.Vector.Unboxed.take actionCount
          . snd
      )
      pairs =
      "critic"
  | otherwise = "mixed"

mkTrpoStep
  :: PpoTrainer.PpoTrainConfig
  -> Mlp.MlpParams
  -> ([Double], Int, Double)
  -> (PpoTrainer.RolloutStep, Double, Double)
mkTrpoStep config params (observationValues, action, advantage) =
  let observation = Data.Vector.Unboxed.fromList observationValues
      output =
        Mlp.policyValueForwardWith
          Mlp.LinearValueHead
          params
          (PpoTrainer.ppoActionCount config)
          observation
      probability = Mlp.pvPolicy output Data.Vector.Unboxed.! action
   in ( PpoTrainer.RolloutStep
          { PpoTrainer.rsObs = observation
          , PpoTrainer.rsAction = action
          , PpoTrainer.rsLogProb = log probability
          , PpoTrainer.rsValue = Mlp.pvValue output
          , PpoTrainer.rsReward = 0.0
          , PpoTrainer.rsDone = False
          , PpoTrainer.rsPolicy = Mlp.pvPolicy output
          , PpoTrainer.rsActionMask = Nothing
          , PpoTrainer.rsRecurrentState = Data.Vector.Unboxed.empty
          }
      , advantage
      , 0.0
      )

gradientVector :: Int -> Double -> Data.Vector.Unboxed.Vector Double
gradientVector size scale =
  Data.Vector.Unboxed.generate
    size
    (\index -> scale * fromIntegral ((index `mod` 7) - 3))

smallTrpoConfig :: PpoTrainer.PpoTrainConfig
smallTrpoConfig =
  PpoTrainer.defaultPpoTrainConfig
    { PpoTrainer.ppoSeed = 31
    , PpoTrainer.ppoHiddenUnits = 4
    , PpoTrainer.ppoActionCount = 2
    , PpoTrainer.ppoObsSize = 4
    , PpoTrainer.ppoVariant = PpoTrainer.VariantTRPO
    }

constantGradientLike :: Mlp.MlpParams -> Double -> Mlp.MlpGradient
constantGradientLike params value =
  Mlp.MlpGradient
    { Mlp.gradW1 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramW1 params)) value
    , Mlp.gradB1 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramB1 params)) value
    , Mlp.gradW2 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramW2 params)) value
    , Mlp.gradB2 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramB2 params)) value
    }

deterministicGradientLike :: Mlp.MlpParams -> Mlp.MlpGradient
deterministicGradientLike params =
  Mlp.MlpGradient
    { Mlp.gradW1 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramW1 params)) 0.01
    , Mlp.gradB1 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramB1 params)) 0.02
    , Mlp.gradW2 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramW2 params)) 0.015
    , Mlp.gradB2 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramB2 params)) 0.025
    }

mapGradientForTest :: (Double -> Double) -> Mlp.MlpGradient -> Mlp.MlpGradient
mapGradientForTest f gradient =
  Mlp.MlpGradient
    { Mlp.gradW1 = Data.Vector.Unboxed.map f (Mlp.gradW1 gradient)
    , Mlp.gradB1 = Data.Vector.Unboxed.map f (Mlp.gradB1 gradient)
    , Mlp.gradW2 = Data.Vector.Unboxed.map f (Mlp.gradW2 gradient)
    , Mlp.gradB2 = Data.Vector.Unboxed.map f (Mlp.gradB2 gradient)
    }

positiveDiagonalGradientForTest :: Mlp.MlpGradient -> Mlp.MlpGradient
positiveDiagonalGradientForTest gradient =
  Mlp.MlpGradient
    { Mlp.gradW1 = diagonal 0 (Mlp.gradW1 gradient)
    , Mlp.gradB1 = diagonal 1 (Mlp.gradB1 gradient)
    , Mlp.gradW2 = diagonal 2 (Mlp.gradW2 gradient)
    , Mlp.gradB2 = diagonal 3 (Mlp.gradB2 gradient)
    }
 where
  diagonal offset =
    Data.Vector.Unboxed.imap
      (\index value -> (1.0 + 0.25 * fromIntegral ((index + offset) `mod` 5)) * value)

policyBiasGradient
  :: PpoTrainer.PpoTrainConfig
  -> [(PpoTrainer.RolloutStep, Double, Double)]
  -> Mlp.MlpParams
  -> Mlp.MlpGradient
policyBiasGradient config batch params =
  case batch of
    [] -> constantGradientLike params 0.0
    ((step, advantage, _) : _) ->
      let actionCount = PpoTrainer.ppoActionCount config
          action = PpoTrainer.rsAction step
          policy = PpoTrainer.rsPolicy step
          policyBias =
            Data.Vector.Unboxed.generate
              actionCount
              ( \index ->
                  let indicator = if index == action then 1.0 else 0.0
                   in negate (advantage * (indicator - policy Data.Vector.Unboxed.! index))
              )
       in (constantGradientLike params 0.0)
            { Mlp.gradB2 = policyBias Data.Vector.Unboxed.++ Data.Vector.Unboxed.singleton 0.0
            }

trpoPolicies :: [(PpoTrainer.RolloutStep, Double, Double)] -> [[Double]]
trpoPolicies = fmap (Data.Vector.Unboxed.toList . PpoTrainer.rsPolicy . firstStep)
 where
  firstStep (step, _, _) = step

trpoValueMse
  :: PpoTrainer.PpoTrainConfig
  -> Mlp.MlpParams
  -> [(PpoTrainer.RolloutStep, Double, Double)]
  -> Double
trpoValueMse config params batch =
  sum squaredErrors / fromIntegral (max 1 (length squaredErrors))
 where
  squaredErrors =
    [ let predicted =
            Mlp.pvValue
              ( Mlp.policyValueForwardWith
                  Mlp.LinearValueHead
                  params
                  (PpoTrainer.ppoActionCount config)
                  (PpoTrainer.rsObs step)
              )
       in (predicted - target) ^ (2 :: Int)
    | (step, _, target) <- batch
    ]

trpoPoliciesAt
  :: PpoTrainer.PpoTrainConfig
  -> Mlp.MlpParams
  -> [(PpoTrainer.RolloutStep, Double, Double)]
  -> [[Double]]
trpoPoliciesAt config params =
  fmap
    ( \(step, _, _) ->
        Data.Vector.Unboxed.toList
          ( Mlp.pvPolicy
              ( Mlp.policyValueForwardWith
                  Mlp.LinearValueHead
                  params
                  (PpoTrainer.ppoActionCount config)
                  (PpoTrainer.rsObs step)
              )
          )
    )

selectedLogProbs
  :: PpoTrainer.PpoTrainConfig
  -> Mlp.MlpParams
  -> [(PpoTrainer.RolloutStep, Double, Double)]
  -> [Double]
selectedLogProbs config params =
  fmap
    ( \(step, _, _) ->
        let policy =
              Mlp.pvPolicy
                ( Mlp.policyValueForwardWith
                    Mlp.LinearValueHead
                    params
                    (PpoTrainer.ppoActionCount config)
                    (PpoTrainer.rsObs step)
                )
         in log (policy Data.Vector.Unboxed.! PpoTrainer.rsAction step)
    )

gradientDotForTest :: Mlp.MlpGradient -> Mlp.MlpGradient -> Double
gradientDotForTest left right =
  Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradW1 left) (Mlp.gradW1 right))
    + Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradB1 left) (Mlp.gradB1 right))
    + Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradW2 left) (Mlp.gradW2 right))
    + Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradB2 left) (Mlp.gradB2 right))

gradientAllFinite :: Mlp.MlpGradient -> Bool
gradientAllFinite gradient =
  all
    (Data.Vector.Unboxed.all (\value -> not (isNaN value || isInfinite value)))
    [ Mlp.gradW1 gradient
    , Mlp.gradB1 gradient
    , Mlp.gradW2 gradient
    , Mlp.gradB2 gradient
    ]

addGradientToParams :: Double -> Mlp.MlpGradient -> Mlp.MlpParams -> Mlp.MlpParams
addGradientToParams scale gradient params =
  params
    { Mlp.paramW1 = addScaled (Mlp.paramW1 params) (Mlp.gradW1 gradient)
    , Mlp.paramB1 = addScaled (Mlp.paramB1 params) (Mlp.gradB1 gradient)
    , Mlp.paramW2 = addScaled (Mlp.paramW2 params) (Mlp.gradW2 gradient)
    , Mlp.paramB2 = addScaled (Mlp.paramB2 params) (Mlp.gradB2 gradient)
    }
 where
  addScaled =
    Data.Vector.Unboxed.zipWith (\value change -> value + scale * change)

maxParameterDifference :: Mlp.MlpParams -> Mlp.MlpParams -> Double
maxParameterDifference left right =
  maximum
    ( 0.0
        : concatMap
          Data.Vector.Unboxed.toList
          [ Data.Vector.Unboxed.zipWith (\a b -> abs (a - b)) (Mlp.paramW1 left) (Mlp.paramW1 right)
          , Data.Vector.Unboxed.zipWith (\a b -> abs (a - b)) (Mlp.paramB1 left) (Mlp.paramB1 right)
          , Data.Vector.Unboxed.zipWith (\a b -> abs (a - b)) (Mlp.paramW2 left) (Mlp.paramW2 right)
          , Data.Vector.Unboxed.zipWith (\a b -> abs (a - b)) (Mlp.paramB2 left) (Mlp.paramB2 right)
          ]
    )

fastDqnDeviceConfig :: DqnTrainer.DqnTrainConfig
fastDqnDeviceConfig =
  DqnTrainer.defaultDqnTrainConfig
    { DqnTrainer.dqnSeed = 101
    , DqnTrainer.dqnHiddenUnits = 8
    , DqnTrainer.dqnNumSteps = 2
    , DqnTrainer.dqnReplayCapacity = 8
    , DqnTrainer.dqnBatchSize = 1
    , DqnTrainer.dqnTrainStart = 1
    , DqnTrainer.dqnUpdateFrequency = 1
    , DqnTrainer.dqnTargetUpdateInterval = 2
    , DqnTrainer.dqnMaxEpisodeSteps = 10
    , DqnTrainer.dqnStatInterval = 1
    }

fastQrDqnDeviceConfig :: QrDqnTrainer.QrDqnTrainConfig
fastQrDqnDeviceConfig =
  QrDqnTrainer.defaultQrDqnTrainConfig
    { QrDqnTrainer.qrSeed = 102
    , QrDqnTrainer.qrHiddenUnits = 8
    , QrDqnTrainer.qrNumQuantiles = 3
    , QrDqnTrainer.qrNumSteps = 2
    , QrDqnTrainer.qrReplayCapacity = 8
    , QrDqnTrainer.qrBatchSize = 1
    , QrDqnTrainer.qrTrainStart = 1
    , QrDqnTrainer.qrUpdateFrequency = 1
    , QrDqnTrainer.qrTargetUpdateInterval = 2
    , QrDqnTrainer.qrMaxEpisodeSteps = 10
    , QrDqnTrainer.qrStatInterval = 1
    }

fastHerDeviceConfig :: HerTrainer.HerTrainConfig
fastHerDeviceConfig =
  HerTrainer.defaultHerTrainConfig
    { HerTrainer.herSeed = 103
    , HerTrainer.herNumBits = 3
    , HerTrainer.herHiddenUnits = 8
    , HerTrainer.herEpisodes = 5
    , HerTrainer.herReplayCapacity = 16
    , HerTrainer.herBatchSize = 1
    , HerTrainer.herTargetUpdateInterval = 2
    , HerTrainer.herStatInterval = 1
    }

fastContinuousDeviceConfig :: ContinuousTrainer.ContinuousTrainConfig
fastContinuousDeviceConfig =
  (ContinuousTrainer.defaultContinuousTrainConfig ContinuousTrainer.VariantDDPG)
    { ContinuousTrainer.ctSeed = 104
    , ContinuousTrainer.ctHidden = 8
    , ContinuousTrainer.ctNumSteps = 2
    , ContinuousTrainer.ctReplayCapacity = 8
    , ContinuousTrainer.ctBatchSize = 1
    , ContinuousTrainer.ctStartSteps = 0
    , ContinuousTrainer.ctTrainStart = 1
    , ContinuousTrainer.ctPolicyDelay = 1
    , ContinuousTrainer.ctMaxEpisodeSteps = 10
    , ContinuousTrainer.ctStatInterval = 1
    }

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

assertOutcomeField :: (Eq a, Show a) => String -> a -> a -> ProcessOutcome -> Assertion
assertOutcomeField label expected actual outcome
  | actual == expected = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected "
            <> show expected
            <> ", got "
            <> show actual
            <> " in:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

assertOutcomePredicate :: String -> Bool -> ProcessOutcome -> Assertion
assertOutcomePredicate _ True _ = pure ()
assertOutcomePredicate label False outcome =
  assertFailure (label <> ":\n" <> Text.unpack (renderProcessOutcome outcome))

canonicalErrors :: ProcessFailure -> [AppError]
canonicalErrors fixtureProcessFailure =
  [ AppError.PrerequisiteUnmet
      "ghc-9.12.4"
      "GHC 9.12.4 is required."
      (Just "ghcup install ghc 9.12.4")
  , AppError.SubprocessFailed fixtureProcessFailure
  , AppError.SubprocessAttemptFailed fixtureProcessAttemptFailure
  , AppError.MinIOFailed "bucket unavailable"
  , AppError.PulsarFailed "broker unavailable"
  , AppError.HarborFailed "registry unavailable"
  , AppError.KubectlFailed "context missing"
  , AppError.DocsCheckDrift $
      Text.unlines
        [ "file: README.md"
        , "key: command-tree"
        , "reason: generated section drift"
        , "remedy: run `jitml docs generate` to update"
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
  , AppError.TrainingPrerequisiteUnmet "dataset staging is incomplete"
  , AppError.ReconcilerNoop "docs generate: no changes"
  ]

fixtureProcessTranscript :: ProcessTranscript
fixtureProcessTranscript =
  ProcessTranscript
    { processTranscriptCommand = "kubectl get pods"
    , processTranscriptStdout = "pod-a Running\n"
    , processTranscriptStderr = "kubectl failed"
    , processTranscriptWorkingDirectory = Just "/work/jitML"
    , processTranscriptDuration = ProcessDuration 125_000_000
    }

fixtureProcessAttemptFailure :: ProcessAttemptFailure
fixtureProcessAttemptFailure =
  ProcessAttemptFailure
    { processAttemptFailureCommand = "docker run playwright"
    , processAttemptFailureStdout = Nothing
    , processAttemptFailureStderr = Nothing
    , processAttemptFailureWorkingDirectory = Just "/work/jitML"
    , processAttemptFailureDuration = ProcessDuration 25_000_000
    , processAttemptFailureException = "docker: executable not found"
    }

scopeStep :: Text -> Text -> LivePlanStep
scopeStep name commandLabel =
  LivePlanStep
    { livePlanStepName = name
    , livePlanStepCommand = subprocess "scope-fixture" [commandLabel]
    }

plannedScopeTest :: Text -> Text -> LiveE2EScope.PlannedTestInvocation
plannedScopeTest stanza commandLabel =
  LiveE2EScope.PlannedTestInvocation
    { LiveE2EScope.plannedTestStanza = stanza
    , LiveE2EScope.plannedTestCommand = subprocess "scope-fixture" [commandLabel]
    }

successfulScopeOutcome :: Word64 -> LivePlanStep -> ProcessOutcome
successfulScopeOutcome duration step =
  processOutcome ExitSuccess (scopeTranscript duration step)

failedScopeOutcome :: Int -> Word64 -> LivePlanStep -> ProcessOutcome
failedScopeOutcome exitCode duration step =
  processOutcome
    (ExitFailure exitCode)
    ( (scopeTranscript duration step)
        { processTranscriptStderr = livePlanStepName step <> " failed\n"
        }
    )

scopeTranscript :: Word64 -> LivePlanStep -> ProcessTranscript
scopeTranscript duration step =
  ProcessTranscript
    { processTranscriptCommand = renderSubprocess (livePlanStepCommand step)
    , processTranscriptStdout = livePlanStepName step <> " stdout\n"
    , processTranscriptStderr = ""
    , processTranscriptWorkingDirectory = Just "/work/jitML"
    , processTranscriptDuration = ProcessDuration duration
    }

assertParseSuccess :: ([String], ParsedCommand) -> Assertion
assertParseSuccess (args, expected) =
  case execParserPure defaultPrefs parserInfo args of
    Success parsed -> parsed @?= expected
    Failure _ -> assertFailure ("parse failed for " <> show args)
    CompletionInvoked _ -> assertFailure ("completion invoked for " <> show args)

newtype ScriptResult = ScriptResult
  { scriptOutcome :: ProcessOutcome
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
  ScriptResult <$> runStreaming defaultSubprocessEnv process
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

withPreservedFile :: FilePath -> IO a -> IO a
withPreservedFile path action =
  withSystemTempDirectory "jitml-preserved-file" $ \dir -> do
    let backup = dir </> "backup"
    existed <- doesFileExist path
    Control.Monad.when existed (copyFile path backup)
    action `finally` do
      generated <- doesFileExist path
      Control.Monad.when generated (removeFile path)
      Control.Monad.when existed (copyFile backup path)

assertContains :: String -> String -> String -> Assertion
assertContains label needle haystack =
  assertBool
    (label <> " did not contain " <> show needle <> " in:\n" <> haystack)
    (needle `isInfixOf` haystack)

data ScriptStream
  = ScriptStdout
  | ScriptStderr

assertScriptExit :: String -> ExitCode -> ScriptResult -> Assertion
assertScriptExit label expected (ScriptResult outcome) =
  assertOutcomeField label expected (scriptOutcomeExitCode outcome) outcome

assertScriptContains :: String -> ScriptStream -> String -> ScriptResult -> Assertion
assertScriptContains label stream needle (ScriptResult outcome)
  | needle `isInfixOf` scriptStreamText stream outcome = pure ()
  | otherwise =
      assertFailure
        ( label
            <> " did not contain "
            <> show needle
            <> " in:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

scriptOutcomeExitCode :: ProcessOutcome -> ExitCode
scriptOutcomeExitCode (ProcessSucceeded _) = ExitSuccess
scriptOutcomeExitCode (ProcessFailed failure) = processFailureExitCode failure

scriptStreamText :: ScriptStream -> ProcessOutcome -> String
scriptStreamText ScriptStdout (ProcessSucceeded transcript) = Text.unpack (processTranscriptStdout transcript)
scriptStreamText ScriptStdout (ProcessFailed failure) = Text.unpack (processFailureStdout failure)
scriptStreamText ScriptStderr (ProcessSucceeded transcript) = Text.unpack (processTranscriptStderr transcript)
scriptStreamText ScriptStderr (ProcessFailed failure) = Text.unpack (processFailureStderr failure)

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

brewPrefixStub :: FilePath -> (FilePath, String)
brewPrefixStub prefix =
  ( "brew"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"--version\" ]; then"
      , "  printf '%s\\n' 'Homebrew 4.0.0'"
      , "  exit 0"
      , "fi"
      , "if [ \"${1:-}\" = \"--prefix\" ] && [ \"${2:-}\" = \"llvm@19\" ]; then"
      , "  printf '%s\\n' '" <> prefix <> "'"
      , "  exit 0"
      , "fi"
      , "exit 1"
      ]
  )

llvmToolStub :: FilePath -> String -> (FilePath, String)
llvmToolStub name major =
  ( name
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"--version\" ]; then"
      , "  printf '%s\\n' 'LLVM version " <> major <> ".1.0'"
      , "  exit 0"
      , "fi"
      , "exit 0"
      ]
  )

cabalBuildStub :: (FilePath, String)
cabalBuildStub =
  ( "cabal"
  , unlines
      [ "#!/usr/bin/env bash"
      , "if [ \"${1:-}\" = \"build\" ]; then"
      , "  mkdir -p .build/stub"
      , "  printf '%s\\n' '#!/usr/bin/env bash' 'exit 0' > .build/stub/jitml"
      , "  chmod +x .build/stub/jitml"
      , "  exit 0"
      , "fi"
      , "if [ \"${1:-}\" = \"list-bin\" ]; then"
      , "  printf '%s\\n' \"$PWD/.build/stub/jitml\""
      , "  exit 0"
      , "fi"
      , "exit 1"
      ]
  )

codesignStub :: (FilePath, String)
codesignStub =
  ( "codesign"
  , unlines
      [ "#!/usr/bin/env bash"
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

withinUnitDeadline :: String -> IO value -> IO value
withinUnitDeadline label action = do
  completed <- timeout 5_000_000 action
  case completed of
    Just value -> pure value
    Nothing -> assertFailure label >> error "unreachable"

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
  , ["test", "jitml-negative-controls"]
  , ["test", "jitml-model-convergence"]
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
  , ["project", "init"]
  , ["internal", "materialize-substrate"]
  , ["internal", "list-prereqs"]
  , ["internal", "install-metal-bridge"]
  , ["internal", "upload-dataset"]
  , ["internal", "seed-demo-checkpoints"]
  , ["internal", "train-and-publish-product-rows"]
  , ["internal", "benchmark-product-row-wall-clock"]
  , ["internal", "dhall-schema"]
  , ["internal", "third-party-images"]
  , ["internal", "gc"]
  , ["internal", "cache", "stat"]
  , ["internal", "cache", "list"]
  , ["internal", "cache", "evict"]
  , ["commands"]
  , ["help"]
  ]

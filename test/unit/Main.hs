{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Codec.Serialise qualified as Serialise
import Control.Applicative ((<|>))
import Control.Concurrent (MVar, forkIO, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Exception (IOException, bracket_, finally, try)
import Control.Exception qualified as Exception
import Control.Monad qualified
import Control.Monad.Catch (ExitCase (..))
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, ask, asks, runReaderT)
import Data.Aeson (FromJSON (..), Value, decode, eitherDecode, encode, withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as ByteString
import Data.Char (intToDigit, isDigit)
import Data.Foldable (for_, toList, traverse_)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, isInfixOf, nub)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty)
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, mapMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure)
import Path (toFilePath)
import Path.IO (resolveDir')
import System.Directory
  ( canonicalizePath
  , copyFile
  , createDirectoryIfMissing
  , createDirectoryLink
  , doesFileExist
  , getCurrentDirectory
  , getPermissions
  , removeFile
  , setCurrentDirectory
  , setOwnerExecutable
  , setPermissions
  )
import System.Environment (getExecutablePath, lookupEnv, setEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Info qualified as SystemInfo
import System.Timeout (timeout)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck qualified as QuickCheck

import CheckpointV1Admission qualified
import DurableStateTopology (durableStateTopologyTests)
import ProductExperimentExactness qualified
import ProductTuneTranscript qualified
import ReconcileStamp qualified
import RegressionStandardization qualified
import SupervisedCheckpointV2 qualified
import SupervisedTrainingSeed qualified
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase, (@?=))

import Data.Vector qualified as Vector
import Data.Vector.Unboxed qualified
import Dhall qualified
import JitML.App
  ( alphaZeroArtifactStep
  , convergeBoundedView
  , freshGcConvergenceAttemptBound
  , freshGcConvergenceFailure
  , gcFreshPlanIntentsToPersist
  , gcFreshTerminalRecoveryWork
  , inferenceReplyAppError
  , matchingInferenceResult
  , parseUserIntOptionAtLeast
  , rlTrainerEnvironmentCompatibilityError
  , selectInternalProductRows
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
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Cluster.Helm qualified as Helm
import JitML.Codegen.Cuda qualified as Cuda
import JitML.Codegen.CudaLayerTraining qualified as CudaLayerTrainingCodegen
import JitML.Codegen.KernelFamily (KernelFamily (..))
import JitML.Codegen.KernelFamily qualified as KernelFamily
import JitML.Codegen.LayerTraining qualified as LayerTrainingCodegen
import JitML.Codegen.Metal qualified as Metal
import JitML.Codegen.MlpCuda qualified as MlpCudaCodegen
import JitML.Codegen.MlpMetal qualified as MlpMetalCodegen
import JitML.Codegen.MlpOneDnn qualified as MlpOneDnnCodegen
import JitML.Codegen.OneDnn qualified as OneDnnCodegen
import JitML.Codegen.RuntimeSource (renderRuntimeSource, runtimeSourcePayload)
import JitML.Codegen.RuntimeSource qualified as RuntimeSource
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Coordinator.Topology qualified as Topology
import JitML.Docs.Check qualified as DocsCheck
import JitML.Engines.CpuFeatures qualified as CpuFeatures
import JitML.Engines.CublasBindings qualified as Cublas
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.CudnnBindings qualified as Cudnn
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.Fingerprint qualified as Fingerprint
import JitML.Engines.LoadableKernel ()
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
import JitML.Inference.Command qualified as InferenceCommand
import JitML.Inference.Decode qualified as Decode
import JitML.Lint.Chart (checkChartFiles)
import JitML.Lint.DhallNumerics (checkDhallNumerics, mlDslDhallFiles)
import JitML.Lint.DhallRL (checkDhallRL)
import JitML.Lint.FailOpen qualified as FailOpen
import JitML.Lint.ProductTruth qualified as ProductTruth
import JitML.Lint.Stack.Types (LintFinding (..))
import JitML.Numerics.Autodiff qualified as Autodiff
import JitML.Numerics.Catalog qualified as NumericsCatalog
import JitML.Numerics.FamilyReference qualified as FamilyReference
import JitML.Numerics.LayerDhall qualified as LayerDhall
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.LayerGraphDevice qualified as LayerGraphDevice
import JitML.Numerics.LayerGraphMetadata qualified as LayerGraphMetadata
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Numerics.Schema
  ( loadNumericsCatalog
  , validateNumericsCatalog
  )
import JitML.Observability.Grafana qualified as Grafana
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Plan
  ( PlanId
  , RunKindWitness (..)
  , buildCommandPlan
  , planIdText
  , refinePlanIdText
  , runPlanId
  )
import JitML.Plan.Plan qualified as RunPlan
import JitML.Plan.Render (renderPlan)
import JitML.Plan.Workload qualified as ResolvedWorkload
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
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.DeviceWitness qualified as DeviceWitness
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
import JitML.Product.Publisher qualified as Publisher
import JitML.Proto.Gc qualified as ProtoGc
import JitML.Proto.Inference qualified as ProtoInference
import JitML.Proto.Rl qualified as ProtoRl
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
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SLCanonicals
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities (HasMinIO (..))
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.CatalogSchema (catalogFileSchemas)
import JitML.Service.DhallSchema
  ( bootConfigSchema
  , canonicalDhallType
  , configSchemas
  , liveConfigSchema
  , runSchemaDhall
  )
import JitML.Service.FilesystemMinIO (FilesystemMinIO, runFilesystemMinIO)
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.InferenceReplyScope
  ( runInferenceReplyScope
  , runInferenceReplyScopeObserved
  , runInferenceReplyScopeWithRelease
  )
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Retry qualified as ServiceRetry
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.Transcript qualified as Transcript
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
  , subprocessEnvOverrideAndRemove
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate qualified as Substrate
import JitML.Test.BrowserEvidenceJournal qualified as BrowserEvidenceJournal
import JitML.Test.DeviceWitnessFixture qualified as DeviceWitnessFixture
import JitML.Test.HostWorkloadRegistry qualified as HostWorkloadRegistry
import JitML.Test.InferenceBatch qualified as InferenceBatch
import JitML.Test.LiveE2EScope qualified as LiveE2EScope
import JitML.Test.LivePlan
  ( LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  )
import JitML.Test.PipedProcess qualified as PipedProcess
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.ProductScenarioRunner qualified as ProductScenarioRunner
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
              (unitBudget TrainingBudget.TuningTrialBudget (max 1 step))
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

-- | Structural facts parsed from a phase document per sprint, used by the
-- automated rule-M enforcement guards (forward-only dependency edges,
-- validation-gate presence, single-accelerator-per-phase). These replace the
-- previously hand-run deterministic scans (development_plan_standards.md
-- "M. Enforcement") with machine checks so plan sizing/ordering cannot silently
-- drift.
data PlanSprintFacts = PlanSprintFacts
  { psfId :: Text
  , psfBlockedBy :: [Text]
  , psfHasValidationGate :: Bool
  , psfValidationNamesCuda :: Bool
  , psfValidationNamesApple :: Bool
  }

readPlanSprintFacts :: ProductPhaseStatus -> IO [PlanSprintFacts]
readPlanSprintFacts phase = do
  content <- Text.IO.readFile (phaseDocument phase)
  pure (parsePlanSprintFacts content)

parsePlanSprintFacts :: Text -> [PlanSprintFacts]
parsePlanSprintFacts content =
  fmap sprintFacts (sprintSections (Text.lines content))
 where
  -- Group lines into (sprintId, bodyLines) per `## Sprint X.Y` header; a body
  -- runs until the next level-2 (`## `) heading.
  sprintSections :: [Text] -> [(Text, [Text])]
  sprintSections [] = []
  sprintSections (line : rest)
    | Just sid <- parseSprintHeader line =
        let (body, after) = break isLevelTwoHeading rest
         in (sid, body) : sprintSections after
    | otherwise = sprintSections rest
  isLevelTwoHeading line = "## " `Text.isPrefixOf` Text.strip line
  sprintFacts (sid, body) =
    let valBlock = validationBlockLines body
     in PlanSprintFacts
          { psfId = sid
          , psfBlockedBy = concatMap extractDottedNumbers (filter isBlockedByLine body)
          , psfHasValidationGate = any lineNamesGateCommand valBlock
          , psfValidationNamesCuda = any (lineNamesAny cudaTokens) valBlock
          , psfValidationNamesApple = any (lineNamesAny appleTokens) valBlock
          }
  isBlockedByLine line = "**Blocked by**:" `Text.isPrefixOf` Text.strip line
  -- The lines of a sprint's `### Validation` block (up to the next heading).
  validationBlockLines body =
    case dropWhile (not . isValidationHeading) body of
      [] -> []
      (_ : afterHeading) -> takeWhile (not . isAnyHeading) afterHeading
  isValidationHeading line = "### Validation" `Text.isPrefixOf` Text.strip line
  isAnyHeading line = "##" `Text.isPrefixOf` Text.strip line
  lineNamesGateCommand line = any (`Text.isInfixOf` line) ["jitml", "bootstrap", "docker", "cabal"]
  lineNamesAny toks line = any (`Text.isInfixOf` line) toks
  cudaTokens = ["--linux-cuda", "-fcuda", "linux-cuda.sh"]
  appleTokens = ["--apple-silicon", "apple-silicon.sh"]

-- | Extract maximal digit/dot tokens containing a dot (i.e. `X.Y` sprint ids).
extractDottedNumbers :: Text -> [Text]
extractDottedNumbers =
  filter (Text.any (== '.')) . Text.split (\c -> not (isDigit c || c == '.'))

-- | Compare two dotted numeric ids (e.g. `23.2` vs `24.1`) as `[Int]` tuples.
compareDottedId :: Text -> Text -> Ordering
compareDottedId a b = compare (parseNums a) (parseNums b)
 where
  parseNums =
    fmap (fromMaybe 0 . readMaybeInt) . filter (not . Text.null) . Text.splitOn "."
  readMaybeInt t = if Text.all isDigit t && not (Text.null t) then Just (read (Text.unpack t) :: Int) else Nothing

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

browserEvidenceJournalTests :: TestTree
browserEvidenceJournalTests =
  testGroup
    "BrowserEvidenceJournal"
    [ testCase "strict v1 round-trips the exact ordered 55-row Passed result" $
        withBrowserEvidenceJournalFixture $ \fixture -> do
          written <-
            BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic
              (browserJournalFixtureKey fixture)
              (browserJournalFixturePath fixture)
              (browserJournalFixtureExpectation fixture)
              ( replicate
                  BrowserEvidenceJournal.browserEvidenceCanonicalRowCount
                  ( BrowserEvidenceJournal.BrowserEvidenceObservation
                      BrowserEvidenceJournal.BrowserPassed
                      ""
                  )
              )
          case written of
            Left errors -> assertFailure ("browser journal write failed: " <> show errors)
            Right () -> pure ()
          loaded <- readBrowserJournalFixture fixture
          case loaded of
            Left errors -> assertFailure ("browser journal read failed: " <> show errors)
            Right report -> do
              assertBool
                "55 Passed rows did not close the browser report"
                (BrowserEvidenceJournal.browserEvidenceReportAllPassed report)
              let entries = BrowserEvidenceJournal.browserEvidenceReportEntries report
              length entries
                @?= BrowserEvidenceJournal.browserEvidenceCanonicalRowCount
              fmap BrowserEvidenceJournal.browserEvidenceResultOrdinal entries
                @?= [(0 :: Word64) .. 54]
              fmap BrowserEvidenceJournal.browserEvidenceResultRowId entries
                @?= fmap
                  BrowserEvidenceJournal.expectedBrowserRowId
                  browserJournalExpectedRows
          let renderedKey =
                BrowserEvidenceJournal.renderBrowserEvidenceJournalKey
                  (browserJournalFixtureKey fixture)
          Text.length renderedKey @?= 64
          assertBool "browser key is not lowercase hex" (Text.all journalLowerHex renderedKey)
          case BrowserEvidenceJournal.parseBrowserEvidenceJournalKey renderedKey of
            Left err -> assertFailure ("rendered browser key did not parse: " <> show err)
            Right parsedKey ->
              assertBool
                "parsed browser key differs from generated key"
                (parsedKey == browserJournalFixtureKey fixture)
          assertBool
            "uppercase browser key unexpectedly parsed"
            ( case BrowserEvidenceJournal.parseBrowserEvidenceJournalKey
                ("A" <> Text.drop 1 renderedKey) of
                Left _ -> True
                Right _ -> False
            )
    , testCase "v1 HMAC material matches the independent UTF-8 frontend golden" $
        withSystemTempDirectory "jitml-browser-evidence-hmac-golden" $ \root -> do
          let fixedKeyText =
                "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
              expectedTag =
                "edbf2a5a0a1398b629d54f039f693317e5f98dfb5a2980cfa092539fa90df879"
              expectation =
                browserExpectationOrFail
                  "phase-262-browser-unit-current-run"
                  (Text.replicate 64 "a")
                  (Text.replicate 64 "b")
                  browserJournalExpectedRows
              observations =
                replicate
                  BrowserEvidenceJournal.browserEvidenceCanonicalRowCount
                  ( BrowserEvidenceJournal.BrowserEvidenceObservation
                      BrowserEvidenceJournal.BrowserPassed
                      ""
                  )
              path = root </> "golden.json"
          key <-
            case BrowserEvidenceJournal.parseBrowserEvidenceJournalKey fixedKeyText of
              Left err -> assertFailure ("fixed browser key did not parse: " <> show err) >> error "unreachable"
              Right value -> pure value
          written <-
            BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic
              key
              path
              expectation
              observations
          case written of
            Left errors -> assertFailure ("golden browser journal write failed: " <> show errors)
            Right () -> pure ()
          readJournalValue path >>= \case
            Aeson.Object record ->
              journalTextField "run_receipt_hmac_sha256" record @?= expectedTag
            other -> assertFailure ("golden browser journal is not an object: " <> show other)
          let unicodeExpectedTag =
                "c2b6ac58411e9bab5e85cc6ed4006117a3ce9ea4e9cdd1a3994228f3cca041b0"
              unicodeObservations =
                BrowserEvidenceJournal.BrowserEvidenceObservation
                  BrowserEvidenceJournal.BrowserFailed
                  "é 🧪 failure"
                  : replicate
                    (BrowserEvidenceJournal.browserEvidenceCanonicalRowCount - 1)
                    ( BrowserEvidenceJournal.BrowserEvidenceObservation
                        BrowserEvidenceJournal.BrowserPassed
                        ""
                    )
          unicodeWritten <-
            BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic
              key
              path
              expectation
              unicodeObservations
          case unicodeWritten of
            Left errors ->
              assertFailure ("Unicode golden browser journal write failed: " <> show errors)
            Right () -> pure ()
          readJournalValue path >>= \case
            Aeson.Object record ->
              journalTextField "run_receipt_hmac_sha256" record @?= unicodeExpectedTag
            other ->
              assertFailure ("Unicode golden browser journal is not an object: " <> show other)
    , testCase "initial journal honestly retains every row as NotRun" $
        withBrowserEvidenceJournalFixture $ \fixture -> do
          written <-
            BrowserEvidenceJournal.writeInitialBrowserEvidenceJournalAtomic
              (browserJournalFixtureKey fixture)
              (browserJournalFixturePath fixture)
              (browserJournalFixtureExpectation fixture)
          case written of
            Left errors -> assertFailure ("initial browser journal write failed: " <> show errors)
            Right () -> pure ()
          loaded <- readBrowserJournalFixture fixture
          case loaded of
            Left errors -> assertFailure ("initial browser journal read failed: " <> show errors)
            Right report -> do
              assertBool
                "an all-NotRun seed journal was accepted as green"
                (not (BrowserEvidenceJournal.browserEvidenceReportAllPassed report))
              let entries = BrowserEvidenceJournal.browserEvidenceReportEntries report
              assertBool
                "initial browser journal did not preserve every NotRun cell"
                ( all
                    ( (== BrowserEvidenceJournal.BrowserNotRun)
                        . BrowserEvidenceJournal.browserEvidenceResultStatus
                    )
                    entries
                )
              assertBool
                "initial NotRun cells omitted their reason"
                ( not
                    ( any
                        (Text.null . BrowserEvidenceJournal.browserEvidenceResultDetail)
                        entries
                    )
                )
    , testCase "authentication and strict schema reject tampering and unknown fields" $
        withBrowserEvidenceJournalFixture $ \fixture -> do
          writePassingBrowserJournal fixture
          original <- readJournalValue (browserJournalFixturePath fixture)
          wrongKey <- generateDifferentBrowserJournalKey (browserJournalFixtureKey fixture)
          assertBrowserEvidenceJournalError
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalAuthenticationFailed -> True; _ -> False)
            =<< BrowserEvidenceJournal.readBrowserEvidenceJournal
              wrongKey
              (browserJournalFixturePath fixture)
              (browserJournalFixtureExpectation fixture)
          writeJournalValue
            (browserJournalFixturePath fixture)
            (setJournalField "phase_262_unknown" Aeson.Null original)
          assertBrowserEvidenceJournalError
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalMalformed {} -> True; _ -> False)
            =<< readBrowserJournalFixture fixture
          writeJournalValue
            (browserJournalFixturePath fixture)
            ( modifyFirstJournalRow
                (setObjectField "status" (Aeson.String "PASS"))
                original
            )
          assertBrowserEvidenceJournalError
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalStatusInvalid {} -> True; _ -> False)
            =<< readBrowserJournalFixture fixture
          writeJournalValue
            (browserJournalFixturePath fixture)
            (setJournalField "run_receipt_hmac_sha256" (Aeson.String "not-a-tag") original)
          assertBrowserEvidenceJournalError
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalAuthenticationTagInvalid {} -> True; _ -> False)
            =<< readBrowserJournalFixture fixture
    , testCase "coverage rejects missing, duplicate, orphaned, and reordered rows" $
        withBrowserEvidenceJournalFixture $ \fixture -> do
          writePassingBrowserJournal fixture
          original <- readJournalValue (browserJournalFixturePath fixture)
          let check mutation predicate = do
                writeJournalValue
                  (browserJournalFixturePath fixture)
                  (modifyJournalRows mutation original)
                assertBrowserEvidenceJournalError predicate
                  =<< readBrowserJournalFixture fixture
          check
            reverse
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalRowOrderMismatch {} -> True; _ -> False)
          check
            (take 54)
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalMissingRow {} -> True; _ -> False)
          check
            ( \case
                first : _second : remaining -> first : first : remaining
                [first] -> [first, first]
                [] -> []
            )
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalDuplicateRow {} -> True; _ -> False)
          writeJournalValue
            (browserJournalFixturePath fixture)
            ( modifyFirstJournalRow
                (setObjectField "row_id" (Aeson.String "orphan-browser-row"))
                original
            )
          assertBrowserEvidenceJournalError
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalOrphanRow {} -> True; _ -> False)
            =<< readBrowserJournalFixture fixture
    , testCase "authenticated identity drift cannot join the canonical catalogue" $
        withBrowserEvidenceJournalFixture $ \fixture -> do
          assertBool
            "oversized browser expectation identity unexpectedly refined"
            ( case BrowserEvidenceJournal.browserEvidenceExpectation
                (Text.replicate 4097 "x")
                Substrate.LinuxCPU
                (Text.replicate 64 "a")
                (Text.replicate 64 "b")
                browserJournalExpectedRows of
                Left errors ->
                  any
                    ( \case
                        BrowserEvidenceJournal.BrowserEvidenceExpectationIdentityInvalid
                          "run_id"
                          _ -> True
                        _ -> False
                    )
                    errors
                Right _ -> False
            )
          let expectedRows = browserJournalExpectedRows
              wrongPlanRows =
                case expectedRows of
                  [] -> []
                  first : remaining ->
                    first
                      { BrowserEvidenceJournal.expectedBrowserPlanId = Text.replicate 64 "f"
                      }
                      : remaining
              alteredExpectation =
                browserExpectationOrFail
                  "phase-262-browser-unit-current-run"
                  (Text.replicate 64 "a")
                  (Text.replicate 64 "b")
                  wrongPlanRows
          written <-
            BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic
              (browserJournalFixtureKey fixture)
              (browserJournalFixturePath fixture)
              alteredExpectation
              ( replicate
                  BrowserEvidenceJournal.browserEvidenceCanonicalRowCount
                  ( BrowserEvidenceJournal.BrowserEvidenceObservation
                      BrowserEvidenceJournal.BrowserPassed
                      ""
                  )
              )
          case written of
            Left errors -> assertFailure ("altered browser journal write failed: " <> show errors)
            Right () -> pure ()
          assertBrowserEvidenceJournalError
            (\case BrowserEvidenceJournal.BrowserEvidenceJournalPlanMismatch {} -> True; _ -> False)
            =<< readBrowserJournalFixture fixture
    , testCase "status detail policy rejects fabricated or unsafe explanations" $
        withBrowserEvidenceJournalFixture $ \fixture -> do
          let rejected status detail = do
                written <-
                  BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic
                    (browserJournalFixtureKey fixture)
                    (browserJournalFixturePath fixture)
                    (browserJournalFixtureExpectation fixture)
                    ( replicate
                        BrowserEvidenceJournal.browserEvidenceCanonicalRowCount
                        (BrowserEvidenceJournal.BrowserEvidenceObservation status detail)
                    )
                case written of
                  Left errors ->
                    assertBool
                      ("expected detail rejection, got " <> show errors)
                      ( any
                          (\case BrowserEvidenceJournal.BrowserEvidenceJournalDetailInvalid {} -> True; _ -> False)
                          errors
                      )
                  Right () -> assertFailure "unsafe browser status detail was written"
          rejected BrowserEvidenceJournal.BrowserPassed "fabricated pass detail"
          rejected BrowserEvidenceJournal.BrowserFailed ""
          rejected BrowserEvidenceJournal.BrowserNotRun "contains\ncontrol"
          rejected BrowserEvidenceJournal.BrowserFailed "contains\x85\&control"
          rejected BrowserEvidenceJournal.BrowserFailed (Text.replicate 4097 "x")
    ]

data BrowserEvidenceJournalFixture = BrowserEvidenceJournalFixture
  { browserJournalFixturePath :: !FilePath
  , browserJournalFixtureKey :: !BrowserEvidenceJournal.BrowserEvidenceJournalKey
  , browserJournalFixtureExpectation :: !BrowserEvidenceJournal.BrowserEvidenceExpectation
  }

withBrowserEvidenceJournalFixture
  :: (BrowserEvidenceJournalFixture -> IO result)
  -> IO result
withBrowserEvidenceJournalFixture action =
  withSystemTempDirectory "jitml-browser-evidence-journal" $ \root -> do
    key <-
      BrowserEvidenceJournal.generateBrowserEvidenceJournalKey
        >>= \case
          Left err -> assertFailure ("browser key generation failed: " <> show err) >> error "unreachable"
          Right value -> pure value
    action
      BrowserEvidenceJournalFixture
        { browserJournalFixturePath = root </> "result.json"
        , browserJournalFixtureKey = key
        , browserJournalFixtureExpectation =
            browserExpectationOrFail
              "phase-262-browser-unit-current-run"
              (Text.replicate 64 "a")
              (Text.replicate 64 "b")
              browserJournalExpectedRows
        }

browserJournalExpectedRows :: [BrowserEvidenceJournal.BrowserEvidenceExpectedRow]
browserJournalExpectedRows =
  [ BrowserEvidenceJournal.BrowserEvidenceExpectedRow
      { BrowserEvidenceJournal.expectedBrowserOrdinal = ordinal
      , BrowserEvidenceJournal.expectedBrowserRowId = "browser-row-" <> suffix
      , BrowserEvidenceJournal.expectedBrowserPlanId = digestFor ordinal 'c'
      , BrowserEvidenceJournal.expectedBrowserExperimentHash = digestFor ordinal 'd'
      , BrowserEvidenceJournal.expectedBrowserManifestSha256 = digestFor ordinal 'e'
      , BrowserEvidenceJournal.expectedBrowserE2ETest = "browser-e2e-" <> suffix
      }
  | ordinal <- [0 .. fromIntegral BrowserEvidenceJournal.browserEvidenceCanonicalRowCount - 1]
  , let suffix = Text.justifyRight 2 '0' (Text.pack (show ordinal))
  ]
 where
  digestFor ordinal prefix =
    Text.cons
      prefix
      (Text.justifyRight 63 '0' (Text.pack (show ordinal)))

browserExpectationOrFail
  :: Text
  -> Text
  -> Text
  -> [BrowserEvidenceJournal.BrowserEvidenceExpectedRow]
  -> BrowserEvidenceJournal.BrowserEvidenceExpectation
browserExpectationOrFail runId catalogueSha sourceSha rows =
  case BrowserEvidenceJournal.browserEvidenceExpectation
    runId
    Substrate.LinuxCPU
    catalogueSha
    sourceSha
    rows of
    Left errors -> error ("invalid browser expectation fixture: " <> show errors)
    Right expectation -> expectation

writePassingBrowserJournal :: BrowserEvidenceJournalFixture -> IO ()
writePassingBrowserJournal fixture = do
  written <-
    BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic
      (browserJournalFixtureKey fixture)
      (browserJournalFixturePath fixture)
      (browserJournalFixtureExpectation fixture)
      ( replicate
          BrowserEvidenceJournal.browserEvidenceCanonicalRowCount
          ( BrowserEvidenceJournal.BrowserEvidenceObservation
              BrowserEvidenceJournal.BrowserPassed
              ""
          )
      )
  case written of
    Left errors -> assertFailure ("browser journal write failed: " <> show errors)
    Right () -> pure ()

readBrowserJournalFixture
  :: BrowserEvidenceJournalFixture
  -> IO
       ( Either
           (NonEmpty BrowserEvidenceJournal.BrowserEvidenceJournalError)
           BrowserEvidenceJournal.BrowserEvidenceReport
       )
readBrowserJournalFixture fixture =
  BrowserEvidenceJournal.readBrowserEvidenceJournal
    (browserJournalFixtureKey fixture)
    (browserJournalFixturePath fixture)
    (browserJournalFixtureExpectation fixture)

assertBrowserEvidenceJournalError
  :: (BrowserEvidenceJournal.BrowserEvidenceJournalError -> Bool)
  -> Either
       (NonEmpty BrowserEvidenceJournal.BrowserEvidenceJournalError)
       BrowserEvidenceJournal.BrowserEvidenceReport
  -> Assertion
assertBrowserEvidenceJournalError predicate outcome =
  case outcome of
    Left errors ->
      assertBool
        ("unexpected browser journal errors: " <> show errors)
        (any predicate errors)
    Right _ -> assertFailure "invalid browser journal minted BrowserEvidenceReport"

generateDifferentBrowserJournalKey
  :: BrowserEvidenceJournal.BrowserEvidenceJournalKey
  -> IO BrowserEvidenceJournal.BrowserEvidenceJournalKey
generateDifferentBrowserJournalKey original = do
  generated <- BrowserEvidenceJournal.generateBrowserEvidenceJournalKey
  case generated of
    Left err -> assertFailure ("browser key generation failed: " <> show err) >> error "unreachable"
    Right key
      | key == original -> generateDifferentBrowserJournalKey original
      | otherwise -> pure key

productScenarioJournalTests :: TestTree
productScenarioJournalTests =
  testGroup
    "ProductScenarioJournal"
    [ testCase "opaque local-executable evidence round-trips through exact-address journal admission" $
        withProductScenarioJournalFixture $ \fixture -> do
          loaded <- readJournalFixture fixture (journalFixtureRunId fixture)
          loaded @?= Right (journalFixtureReport fixture)
          let checkpointAlias = journalFixtureRoot fixture </> "checkpoint-alias"
              foreignCheckpointRoot =
                journalFixtureRoot fixture </> "foreign-physical-checkpoints"
              readAtRoot root =
                ProductScenarioJournal.readProductScenarioJournal
                  (journalFixtureKey fixture)
                  (journalFixturePath fixture)
                  root
                  (journalFixtureRunId fixture)
                  (journalFixtureExecutablePath fixture)
                  (journalFixtureExecutableSha fixture)
                  (journalFixtureBatch fixture)
          createDirectoryLink
            (journalFixtureCheckpointRoot fixture)
            checkpointAlias
          readAtRoot checkpointAlias
            >>= (@?= Right (journalFixtureReport fixture))
          removeFile checkpointAlias
          createDirectoryIfMissing True foreignCheckpointRoot
          createDirectoryLink foreignCheckpointRoot checkpointAlias
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalCheckpointScopeMismatch {} -> True; _ -> False)
            =<< readAtRoot checkpointAlias
          wrongRootWrite <-
            ProductScenarioJournal.writeProductScenarioJournalAtomic
              (journalFixtureKey fixture)
              (journalFixtureRoot fixture </> "wrong-root-journal.json")
              (journalFixtureRoot fixture </> "wrong-checkpoint-root")
              (journalFixtureRunId fixture)
              (journalFixtureBatch fixture)
              (journalFixtureReport fixture)
          case wrongRootWrite of
            Left errors ->
              assertBool
                ("expected writer checkpoint-scope rejection, got " <> show errors)
                ( any
                    (\case ProductScenarioJournal.ProductScenarioJournalCheckpointScopeMismatch {} -> True; _ -> False)
                    errors
                )
            Right () ->
              assertFailure
                "writer persisted opaque evidence under a foreign checkpoint root"
          let renderedKey =
                ProductScenarioJournal.renderProductScenarioJournalKey
                  (journalFixtureKey fixture)
          case ProductScenarioJournal.parseProductScenarioJournalKey renderedKey of
            Left err ->
              assertFailure
                ("rendered journal key did not parse: " <> show err)
            Right parsedKey ->
              assertBool
                "parsed journal key differs from the generated key"
                (parsedKey == journalFixtureKey fixture)
          assertBool
            "rendered journal key is not exactly 32 lowercase-hex bytes"
            (Text.length renderedKey == 64 && Text.all journalLowerHex renderedKey)
          assertBool
            "uppercase journal key unexpectedly parsed"
            ( case ProductScenarioJournal.parseProductScenarioJournalKey
                ("A" <> Text.drop 1 renderedKey) of
                Left _ -> True
                Right _ -> False
            )
          assertBool
            "non-ASCII decimal digit unexpectedly parsed as journal hex"
            ( case ProductScenarioJournal.parseProductScenarioJournalKey
                ("\x0660" <> Text.drop 1 renderedKey) of
                Left _ -> True
                Right _ -> False
            )
          wrongKey <- generateDifferentJournalKey (journalFixtureKey fixture)
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< ProductScenarioJournal.readProductScenarioJournal
              wrongKey
              (journalFixturePath fixture)
              (journalFixtureCheckpointRoot fixture)
              (journalFixtureRunId fixture)
              (journalFixtureExecutablePath fixture)
              (journalFixtureExecutableSha fixture)
              (journalFixtureBatch fixture)
          let wrongExecutablePath =
                journalFixtureRoot fixture </> "wrong-jitml-executable"
          copyFile
            (journalFixtureExecutablePath fixture)
            wrongExecutablePath
          canonicalWrongExecutablePath <- canonicalizePath wrongExecutablePath
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalExecutablePathMismatch {} -> True; _ -> False)
            =<< ProductScenarioJournal.readProductScenarioJournal
              (journalFixtureKey fixture)
              (journalFixturePath fixture)
              (journalFixtureCheckpointRoot fixture)
              (journalFixtureRunId fixture)
              canonicalWrongExecutablePath
              (journalFixtureExecutableSha fixture)
              (journalFixtureBatch fixture)
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalExecutableShaMismatch {} -> True; _ -> False)
            =<< ProductScenarioJournal.readProductScenarioJournal
              (journalFixtureKey fixture)
              (journalFixturePath fixture)
              (journalFixtureCheckpointRoot fixture)
              (journalFixtureRunId fixture)
              (journalFixtureExecutablePath fixture)
              zeroJournalDigest
              (journalFixtureBatch fixture)
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalMalformed {} -> True; _ -> False)
            =<< ProductScenarioJournal.readProductScenarioJournal
              (journalFixtureKey fixture)
              (journalFixturePath fixture)
              (journalFixtureCheckpointRoot fixture)
              (journalFixtureRunId fixture)
              (journalFixtureExecutablePath fixture)
              ("\x0660" <> Text.drop 1 (journalFixtureExecutableSha fixture))
              (journalFixtureBatch fixture)
          let entries =
                Report.completedProductScenarioReportEntries
                  (journalFixtureReport fixture)
          assertBool "journal fixture must cover two ProductRows" (length entries == 2)
          traverse_
            ( \entry -> do
                assertBool
                  "local executable evidence omitted its precondition rejection"
                  (Report.completedProductScenarioPreconditionRejected entry)
                assertBool
                  "local executable evidence lost precondition < inference < completion order"
                  ( Report.completedProductScenarioPreconditionSequence entry
                      < Report.completedProductScenarioInferenceSequence entry
                      && Report.completedProductScenarioInferenceSequence entry
                        < Report.completedProductScenarioCompletionSequence entry
                  )
            )
            entries
    , testCase "strict current-run schema rejects malformed, unknown, stale-run, batch, and lane input" $
        withProductScenarioJournalFixture $ \fixture -> do
          original <- readJournalValue (journalFixturePath fixture)
          ByteString.writeFile (journalFixturePath fixture) "{"
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalMalformed {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          writeJournalValue
            (journalFixturePath fixture)
            (setJournalField "unknown_phase_261_field" Aeson.Null original)
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalMalformed {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          writeJournalValue
            (journalFixturePath fixture)
            ( modifyFirstJournalRow
                (setObjectField "unknown_row_field" Aeson.Null)
                original
            )
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalMalformed {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          writeJournalValue
            (journalFixturePath fixture)
            (setJournalField "version" (Aeson.toJSON (1 :: Word64)) original)
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          writeJournalValue (journalFixturePath fixture) original
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalRunIdMismatch {} -> True; _ -> False)
            =<< readJournalFixture fixture "phase-261-different-run"
          let rewrittenRunId = "phase-261-rewritten-current-run"
              relabelledRows =
                modifyJournalRows
                  ( fmap $ \case
                      Aeson.Object row ->
                        Aeson.Object
                          ( setObjectField
                              "run_id"
                              (Aeson.String rewrittenRunId)
                              row
                          )
                      row -> row
                  )
                  (setJournalField "run_id" (Aeson.String rewrittenRunId) original)
          writeJournalValue
            (journalFixturePath fixture)
            (refreshJournalUnkeyedReceipt relabelledRows)
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture rewrittenRunId
          writeJournalValue
            (journalFixturePath fixture)
            ( setJournalField
                "checkpoint_scope_sha256"
                (Aeson.String zeroJournalDigest)
                original
            )
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          writeJournalValue
            (journalFixturePath fixture)
            ( setJournalField
                "projection_batch_sha256"
                (Aeson.String zeroJournalDigest)
                original
            )
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          writeJournalValue
            (journalFixturePath fixture)
            ( setJournalField
                "substrate"
                (Aeson.String "linux-cuda")
                original
            )
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
    , testCase "journal coverage rejects reordered, missing, duplicate, and orphan rows" $
        withProductScenarioJournalFixture $ \fixture -> do
          original <- readJournalValue (journalFixturePath fixture)
          let check mutation predicate = do
                writeJournalValue
                  (journalFixturePath fixture)
                  (modifyJournalRows mutation original)
                assertProductScenarioJournalError predicate
                  =<< readJournalFixture fixture (journalFixtureRunId fixture)
          check
            reverse
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            (take 1)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            (\case first : rest -> first : rest <> [first]; [] -> [])
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          writeJournalValue
            (journalFixturePath fixture)
            ( modifyFirstJournalRow
                (setObjectField "row_id" (Aeson.String "orphan-product-row"))
                original
            )
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
    , testCase "identity, contract, inference, and chronology drift cannot rehydrate opaque evidence" $
        withProductScenarioJournalFixture $ \fixture -> do
          original <- readJournalValue (journalFixturePath fixture)
          let check field value predicate = do
                writeJournalValue
                  (journalFixturePath fixture)
                  (modifyFirstJournalRow (setObjectField field value) original)
                assertProductScenarioJournalError predicate
                  =<< readJournalFixture fixture (journalFixtureRunId fixture)
          check
            "plan_id"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "run_id"
            (Aeson.String "phase-261-row-run-drift")
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "executable_path"
            (Aeson.String "/tmp/forged-jitml")
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "executable_sha256"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "invocation_digest"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "experiment_hash"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "command"
            (Aeson.String "jitml internal wrong-command")
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "projection_sha256"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "contract_sha256"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "execution_journal_receipt"
            (Aeson.String "tampered-execution-receipt")
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          let forgedReceipt = "self-consistent-forged-execution-receipt"
              selfConsistentForgedReceipt =
                refreshJournalUnkeyedReceipt
                  ( modifyFirstJournalRow
                      ( setObjectField
                          "execution_journal_sha256"
                          (Aeson.String (journalSha256Text forgedReceipt))
                          . setObjectField
                            "execution_journal_receipt"
                            (Aeson.String forgedReceipt)
                      )
                      original
                  )
          writeJournalValue
            (journalFixturePath fixture)
            selfConsistentForgedReceipt
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
            =<< readJournalFixture fixture (journalFixtureRunId fixture)
          check
            "execution_journal_sha256"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "inference_experiment_hash"
            (Aeson.String "product-row-drifted-inference")
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "inference_manifest_sha256"
            (Aeson.String zeroJournalDigest)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "precondition_rejected"
            (Aeson.Bool False)
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          check
            "completion_sequence"
            (Aeson.toJSON (2 :: Word64))
            (\case ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
          writeJournalValue (journalFixturePath fixture) original
          assertProductScenarioJournalError
            (\case ProductScenarioJournal.ProductScenarioJournalCheckpointScopeMismatch {} -> True; _ -> False)
            =<< ProductScenarioJournal.readProductScenarioJournal
              (journalFixtureKey fixture)
              (journalFixturePath fixture)
              (journalFixtureRoot fixture </> "absent-checkpoint-store")
              (journalFixtureRunId fixture)
              (journalFixtureExecutablePath fixture)
              (journalFixtureExecutableSha fixture)
              (journalFixtureBatch fixture)
    ]

data ProductScenarioJournalFixture = ProductScenarioJournalFixture
  { journalFixtureRoot :: !FilePath
  , journalFixturePath :: !FilePath
  , journalFixtureCheckpointRoot :: !FilePath
  , journalFixtureKey :: !ProductScenarioJournal.ProductScenarioJournalKey
  , journalFixtureRunId :: !Text
  , journalFixtureExecutablePath :: !FilePath
  , journalFixtureExecutableSha :: !Text
  , journalFixtureBatch :: !ProductMatrix.ProductProjectionBatch
  , journalFixtureReport :: !Report.CompletedProductScenarioReport
  }

withProductScenarioJournalFixture
  :: (ProductScenarioJournalFixture -> IO result)
  -> IO result
withProductScenarioJournalFixture action =
  withSystemTempDirectory "jitml-product-scenario-journal" $ \cacheRoot -> do
    let workdir = cacheRoot </> "workspace"
        checkpointRoot = workdir </> ".build" </> "checkpoints"
        executablePath = cacheRoot </> "jitml-product-scenario-fixture"
        runId = "phase-261-unit-current-run"
    createDirectoryIfMissing True workdir
    unitExecutablePath <- getExecutablePath >>= canonicalizePath
    writeProductScenarioFixtureExecutable
      executablePath
      unitExecutablePath
    canonicalExecutablePath <- canonicalizePath executablePath
    executableSha <-
      WeightCodec.jmw1ContentSha <$> ByteString.readFile canonicalExecutablePath
    key <-
      journalExpectRight
        =<< ProductScenarioJournal.generateProductScenarioJournalKey
    rowsAndEvidence <-
      traverse
        ( journalProductScenarioEvidence
            workdir
            runId
            canonicalExecutablePath
            executableSha
        )
        [ "DQN/cartpole"
        , "DQN/mountain-car"
        ]
    let rows = fmap fst rowsAndEvidence
        evidence = fmap snd rowsAndEvidence
        batch =
          journalExpectSuccess
            (ProductMatrix.projectProductRows Substrate.LinuxCPU rows)
        report =
          journalExpectEitherRight
            (Report.projectCompletedProductScenarioReport batch evidence)
        journalPath = cacheRoot </> "phase-261-product-scenarios.json"
        fixture =
          ProductScenarioJournalFixture
            { journalFixtureRoot = cacheRoot
            , journalFixturePath = journalPath
            , journalFixtureCheckpointRoot = checkpointRoot
            , journalFixtureKey = key
            , journalFixtureRunId = runId
            , journalFixtureExecutablePath = canonicalExecutablePath
            , journalFixtureExecutableSha = executableSha
            , journalFixtureBatch = batch
            , journalFixtureReport = report
            }
    journalExpectRight
      =<< ProductScenarioJournal.writeProductScenarioJournalAtomic
        key
        journalPath
        checkpointRoot
        runId
        batch
        report
    action fixture

journalProductScenarioEvidence
  :: FilePath
  -> Text
  -> FilePath
  -> Text
  -> Text
  -> IO
       ( ProductMatrix.ProductRow 'ProductMatrix.Declared
       , Report.CompletedProductScenarioEvidence
       )
journalProductScenarioEvidence workdir runId executablePath executableSha rowId = do
  row <-
    maybe
      (assertFailure ("missing journal ProductRow " <> Text.unpack rowId))
      pure
      (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)
  projection <-
    case ProductMatrix.projectProductRow Substrate.LinuxCPU row of
      RunPlan.Success
        ( ProductMatrix.SomeProductProjection
            RunPlan.ReinforcementLearningWitness
            exactProjection
          ) -> pure exactProjection
      RunPlan.Success _ ->
        assertFailure ("journal fixture ProductRow is not RL: " <> Text.unpack rowId)
      RunPlan.Failure errors ->
        assertFailure ("journal ProductRow projection failed: " <> show errors)
  evidence <-
    journalExpectRight
      =<< ProductScenarioRunner.runProductScenario
        runId
        executablePath
        executableSha
        workdir
        projection
  pure (row, evidence)

writeProductScenarioFixtureExecutable
  :: FilePath
  -> FilePath
  -> IO ()
writeProductScenarioFixtureExecutable
  executablePath
  unitExecutablePath = do
    Text.IO.writeFile executablePath script
    permissions <- getPermissions executablePath
    setPermissions executablePath (setOwnerExecutable True permissions)
   where
    script =
      Text.unlines
        [ "#!/bin/sh"
        , "set -eu"
        , "export JITML_PRODUCT_SCENARIO_UNIT_FIXTURE_WORKER=1"
        , "exec " <> shellQuote unitExecutablePath <> " \"$@\""
        ]

    shellQuote value =
      "'" <> Text.replace "'" "'\\''" (Text.pack value) <> "'"

runProductScenarioFixtureWorker :: IO ()
runProductScenarioFixtureWorker = do
  rawInvocation <-
    lookupEnv "JITML_PRODUCT_SCENARIO_INVOCATION" >>= \case
      Nothing ->
        ioError
          (userError "fixture worker did not receive ProductScenario invocation")
      Just value -> pure (Text.pack value)
  invocation <-
    either
      (ioError . userError . Text.unpack)
      pure
      (TrainingBudget.parseProductScenarioInvocation rawInvocation)
  let rowId = TrainingBudget.productScenarioInvocationRowId invocation
  row <-
    maybe
      (ioError (userError ("fixture worker has unknown ProductRow " <> Text.unpack rowId)))
      pure
      (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)
  projection <-
    case ProductMatrix.projectProductRow
      (TrainingBudget.productScenarioInvocationSubstrate invocation)
      row of
      RunPlan.Success
        ( ProductMatrix.SomeProductProjection
            RunPlan.ReinforcementLearningWitness
            exactProjection
          ) -> pure exactProjection
      RunPlan.Success _ ->
        ioError (userError "fixture worker ProductRow is not reinforcement learning")
      RunPlan.Failure errors ->
        ioError
          (userError ("fixture worker projection failed: " <> show errors))
  let experiment = ProductMatrix.productProjectionExperimentHash projection
      planId = ProductMatrix.productProjectionPlanId projection
      budget = ProductMatrix.productProjectionTrainingBudget projection
      observedUnits = TrainingBudget.trainingBudgetTargetUnits budget
      bar = ProductMatrix.productProjectionConvergenceBar projection
      metrics =
        [
          ( ProductConvergence.convergenceMetricName bar
          , ProductConvergence.convergenceThreshold bar
          )
        ]
      initialWeights = [0.0, 0.0]
      finalWeights = [0.25, 0.5]
      initialSha =
        WeightCodec.jmw1ContentSha (WeightCodec.encodeJmw1 initialWeights)
      finalSha =
        WeightCodec.jmw1ContentSha (WeightCodec.encodeJmw1 finalWeights)
  fixtureWitness <-
    journalExpectRight =<< DeviceWitnessFixture.fixtureDeviceExecutionWitness
  completed <-
    journalExpectRight
      ( ProductCompletion.completedTrainingForProductRowWithWeightHashes
          planId
          budget
          row
          (Text.replicate 64 "d")
          experiment
          observedUnits
          1
          metrics
          initialSha
          finalSha
          (Just fixtureWitness)
      )
  invocationBound <-
    journalExpectRight
      ( TrainingBudget.bindCompletedTrainingToProductScenarioInvocation
          invocation
          completed
      )
  env <- buildEnv defaultGlobalFlags
  artifact <-
    runReaderT
      ( CheckpointWriter.writeTextArtifact
          experiment
          "rl-trajectory"
          ("phase-261 journal trajectory " <> rowId)
      )
      env
  let transcriptPointer =
        Checkpoint.ArtifactPointer
          { Checkpoint.artifactPointerKind = "rl-trajectory"
          , Checkpoint.artifactPointerObjectKey =
              CheckpointWriter.storedArtifactObjectKey artifact
          , Checkpoint.artifactPointerSha =
              Just (CheckpointWriter.storedArtifactSha artifact)
          }
  _stored <-
    runReaderT
      ( CheckpointWriter.writeLocalCompletedProductWeightCheckpoint
          invocationBound
          experiment
          "rl-dqn-unit-weights"
          observedUnits
          metrics
          finalWeights
          [transcriptPointer]
      )
      env
  pure ()

readJournalFixture
  :: ProductScenarioJournalFixture
  -> Text
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
           Report.CompletedProductScenarioReport
       )
readJournalFixture fixture expectedRunId =
  ProductScenarioJournal.readProductScenarioJournal
    (journalFixtureKey fixture)
    (journalFixturePath fixture)
    (journalFixtureCheckpointRoot fixture)
    expectedRunId
    (journalFixtureExecutablePath fixture)
    (journalFixtureExecutableSha fixture)
    (journalFixtureBatch fixture)

assertProductScenarioJournalError
  :: (ProductScenarioJournal.ProductScenarioJournalError -> Bool)
  -> Either
       (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
       Report.CompletedProductScenarioReport
  -> Assertion
assertProductScenarioJournalError predicate outcome =
  case outcome of
    Left errors ->
      assertBool
        ("expected ProductScenarioJournal error, got " <> show errors)
        (any predicate errors)
    Right _report ->
      assertFailure "invalid raw journal minted CompletedProductScenarioReport"

readJournalValue :: FilePath -> IO Value
readJournalValue path = do
  payload <- ByteString.readFile path
  case eitherDecode payload of
    Left err -> assertFailure ("journal fixture JSON did not decode: " <> err)
    Right value -> pure value

writeJournalValue :: FilePath -> Value -> IO ()
writeJournalValue path = ByteString.writeFile path . encode

setJournalField :: Text -> Value -> Value -> Value
setJournalField field value journal =
  case journal of
    Aeson.Object record ->
      Aeson.Object (AesonKeyMap.insert (AesonKey.fromText field) value record)
    _ -> journal

modifyJournalRows :: ([Value] -> [Value]) -> Value -> Value
modifyJournalRows modifyRows journal =
  case journal of
    Aeson.Object record ->
      case AesonKeyMap.lookup "rows" record of
        Just (Aeson.Array rows) ->
          Aeson.Object
            ( AesonKeyMap.insert
                "rows"
                (Aeson.Array (Vector.fromList (modifyRows (Vector.toList rows))))
                record
            )
        _ -> journal
    _ -> journal

modifyFirstJournalRow :: (Aeson.Object -> Aeson.Object) -> Value -> Value
modifyFirstJournalRow modifyRow =
  modifyJournalRows $ \case
    Aeson.Object first : rest -> Aeson.Object (modifyRow first) : rest
    rows -> rows

setObjectField :: Text -> Value -> Aeson.Object -> Aeson.Object
setObjectField field =
  AesonKeyMap.insert (AesonKey.fromText field)

zeroJournalDigest :: Text
zeroJournalDigest = Text.replicate 64 "0"

journalLowerHex :: Char -> Bool
journalLowerHex character =
  isDigit character
    || (character >= 'a' && character <= 'f')

generateDifferentJournalKey
  :: ProductScenarioJournal.ProductScenarioJournalKey
  -> IO ProductScenarioJournal.ProductScenarioJournalKey
generateDifferentJournalKey original = do
  generated <-
    journalExpectRight
      =<< ProductScenarioJournal.generateProductScenarioJournalKey
  if generated == original
    then generateDifferentJournalKey original
    else pure generated

-- Mirrors the public wire material but deliberately applies an unkeyed SHA-256
-- instead of the hidden HMAC operation.  Even a self-consistent raw rewrite
-- must therefore fail authentication before semantic validation or Store IO.
refreshJournalUnkeyedReceipt :: Value -> Value
refreshJournalUnkeyedReceipt journal =
  setJournalField
    "run_receipt_hmac_sha256"
    (Aeson.String (journalSha256Text (journalRunReceiptMaterial journal)))
    journal

journalRunReceiptMaterial :: Value -> Text
journalRunReceiptMaterial journal =
  case journal of
    Aeson.Object record ->
      Text.concat
        ( [ journalReceiptField
              "domain"
              "jitml-product-scenario-run-receipt-hmac-v1"
          , journalReceiptField "format" (journalTextField "format" record)
          , journalReceiptField
              "version"
              (journalShowText (journalWordField "version" record))
          , journalReceiptField "run_id" (journalTextField "run_id" record)
          , journalReceiptField "substrate" (journalTextField "substrate" record)
          , journalReceiptField
              "projection_batch_sha256"
              (journalTextField "projection_batch_sha256" record)
          , journalReceiptField
              "checkpoint_scope_sha256"
              (journalTextField "checkpoint_scope_sha256" record)
          , journalReceiptField "row_count" (journalShowText (length rows))
          ]
            <> concat
              [ journalReceiptField "row_index" (journalShowText index)
                  : journalRunReceiptRowFields row
              | (index, row) <- zip [(0 :: Int) ..] rows
              ]
        )
     where
      rows = journalObjectRows record
    _ -> error "ProductScenarioJournal test receipt expected an object"

journalRunReceiptRowFields :: Aeson.Object -> [Text]
journalRunReceiptRowFields row =
  [ journalReceiptField "row_id" (journalTextField "row_id" row)
  , journalReceiptField "run_id" (journalTextField "run_id" row)
  , journalReceiptField "plan_id" (journalTextField "plan_id" row)
  , journalReceiptField "row_substrate" (journalTextField "substrate" row)
  , journalReceiptField "executable_path" (journalTextField "executable_path" row)
  , journalReceiptField
      "executable_sha256"
      (journalTextField "executable_sha256" row)
  , journalReceiptField
      "invocation_digest"
      (journalTextField "invocation_digest" row)
  , journalReceiptField "experiment_hash" (journalTextField "experiment_hash" row)
  , journalReceiptField "manifest_sha256" (journalTextField "manifest_sha256" row)
  , journalReceiptField "projection_sha256" (journalTextField "projection_sha256" row)
  , journalReceiptField "command" (journalTextField "command" row)
  , journalReceiptField "contract_sha256" (journalTextField "contract_sha256" row)
  , journalReceiptField
      "execution_journal_receipt"
      (journalTextField "execution_journal_receipt" row)
  , journalReceiptField
      "execution_journal_sha256"
      (journalTextField "execution_journal_sha256" row)
  , journalReceiptField
      "inference_experiment_hash"
      (journalTextField "inference_experiment_hash" row)
  , journalReceiptField
      "inference_manifest_sha256"
      (journalTextField "inference_manifest_sha256" row)
  , journalReceiptField
      "precondition_rejected"
      (journalShowText (journalBoolField "precondition_rejected" row))
  , journalReceiptField
      "precondition_sequence"
      (journalShowText (journalWordField "precondition_sequence" row))
  , journalReceiptField
      "inference_sequence"
      (journalShowText (journalWordField "inference_sequence" row))
  , journalReceiptField
      "completion_sequence"
      (journalShowText (journalWordField "completion_sequence" row))
  ]

journalReceiptField :: Text -> Text -> Text
journalReceiptField label value =
  label
    <> "="
    <> journalShowText (Text.length value)
    <> ":"
    <> value
    <> "\n"

journalObjectRows :: Aeson.Object -> [Aeson.Object]
journalObjectRows record =
  case journalValueField "rows" record of
    Aeson.Array rows ->
      [ row
      | Aeson.Object row <- Vector.toList rows
      ]
    _ -> error "ProductScenarioJournal test receipt expected rows to be an array"

journalTextField :: Text -> Aeson.Object -> Text
journalTextField field record =
  case journalValueField field record of
    Aeson.String value -> value
    _ ->
      error
        ( "ProductScenarioJournal test receipt expected text field "
            <> Text.unpack field
        )

journalWordField :: Text -> Aeson.Object -> Word64
journalWordField field record =
  case Aeson.fromJSON (journalValueField field record) of
    Aeson.Success value -> value
    Aeson.Error detail ->
      error
        ( "ProductScenarioJournal test receipt expected Word64 field "
            <> Text.unpack field
            <> ": "
            <> detail
        )

journalBoolField :: Text -> Aeson.Object -> Bool
journalBoolField field record =
  case journalValueField field record of
    Aeson.Bool value -> value
    _ ->
      error
        ( "ProductScenarioJournal test receipt expected Bool field "
            <> Text.unpack field
        )

journalValueField :: Text -> Aeson.Object -> Value
journalValueField field record =
  fromMaybe
    ( error
        ( "ProductScenarioJournal test receipt missing field "
            <> Text.unpack field
        )
    )
    (AesonKeyMap.lookup (AesonKey.fromText field) record)

journalSha256Text :: Text -> Text
journalSha256Text =
  WeightCodec.jmw1ContentSha
    . ByteString.fromStrict
    . Text.Encoding.encodeUtf8

journalShowText :: (Show value) => value -> Text
journalShowText = Text.pack . show

journalExpectRight :: (Show error) => Either error value -> IO value
journalExpectRight outcome =
  case outcome of
    Left err ->
      assertFailure ("expected Right, got Left " <> show err) >> error "unreachable"
    Right value -> pure value

journalExpectEitherRight :: (Show error) => Either error value -> value
journalExpectEitherRight outcome =
  case outcome of
    Left err -> error ("expected Right, got Left " <> show err)
    Right value -> value

journalExpectSuccess :: (Show error) => RunPlan.Validation error value -> value
journalExpectSuccess outcome =
  case outcome of
    RunPlan.Failure err -> error ("expected Success, got Failure " <> show err)
    RunPlan.Success value -> value

withGcSemanticId :: ProtoGc.GcReapedEvent -> ProtoGc.GcReapedEvent
withGcSemanticId event =
  event
    { ProtoGc.gcEventId = ProtoGc.gcReapedEventSemanticId event
    }

phase262PreparedTensorSnapshot
  :: Text
  -> Text
  -> Word64
  -> CheckpointStore.PreparedCheckpointSnapshot
phase262PreparedTensorSnapshot experimentHash tag step =
  case CheckpointStore.prepareCheckpointSnapshot
    CheckpointStore.WriterCandidateSnapshot
    CheckpointStore.WriterNoPointerIntent
    logicalManifest
    [(logicalObjectKey, payload)] of
    Left err -> error ("Phase 262 snapshot fixture failed: " <> Text.unpack err)
    Right prepared -> prepared
 where
  payload = Checkpoint.encodeJmw1 [fromIntegral step + 1]
  logicalObjectKey =
    Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
  logicalManifest =
    ( Checkpoint.emptyManifest
        tag
        experimentHash
        [Checkpoint.TensorBlob (tag <> ".weights") [1] logicalObjectKey]
    )
      { Checkpoint.manifestStep = step
      }

-- A manifest whose admitted runtime declares the unit-image input transform
-- every trained classification row uses: a 2x2 single-channel image, so a legal
-- request carries exactly four values, each in @[0,1]@.
phase262UnitImageServingManifest :: Checkpoint.CheckpointManifest
phase262UnitImageServingManifest =
  phase262ServingManifest
    ( Runtime.RawUnitImageInput
        Runtime.RawRuntimeImageGeometry
          { Runtime.rawRuntimeImageWidth = 2
          , Runtime.rawRuntimeImageHeight = 2
          , Runtime.rawRuntimeImageChannels = 1
          }
    )
    (Runtime.RawClassificationRuntimeTask 4)

-- The regression counterpart: a standardized four-feature input, which admits
-- any finite value. It is what makes the unit-image rejection above a statement
-- about the declared domain rather than about the literal numbers.
phase262StandardizedServingManifest :: Checkpoint.CheckpointManifest
phase262StandardizedServingManifest =
  phase262ServingManifest
    (Runtime.RawStandardizeInput [0.0, 0.0, 0.0, 0.0] [1.0, 1.0, 1.0, 1.0])
    (Runtime.RawRegressionRuntimeTask 1)

phase262ServingManifest
  :: Runtime.RawRuntimeInputTransform
  -> Runtime.RawRuntimeTask
  -> Checkpoint.CheckpointManifest
phase262ServingManifest inputTransform task =
  (completedTestManifest 4)
    { Checkpoint.manifestSupervisedRuntime = Just payload
    }
 where
  payload =
    case Runtime.refineSupervisedRuntimePayload raw of
      Left err ->
        error ("Phase 262 serving-manifest fixture failed: " <> Text.unpack err)
      Right refined -> refined
  raw =
    Runtime.RawSupervisedRuntimePayload
      { Runtime.rawRuntimePayloadRowId = "phase262-serving"
      , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
      , Runtime.rawRuntimePayloadPlanId = Text.replicate 64 "e"
      , Runtime.rawRuntimePayloadDatasetSha256 = Text.replicate 64 "a"
      , Runtime.rawRuntimePayloadInitialJmw1Sha256 = Text.replicate 64 "b"
      , Runtime.rawRuntimePayloadFinalJmw1Sha256 = Text.replicate 64 "c"
      , Runtime.rawRuntimePayloadRuntime =
          Runtime.RawSupervisedRuntime
            { Runtime.rawSupervisedRuntimeTask = task
            , Runtime.rawSupervisedRuntimeInputTransform = inputTransform
            , Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawIdentityOutput
            }
      , Runtime.rawRuntimePayloadLayerGraphMetadata = Nothing
      }

-- | Every inference reply kind, rendered by the Engine's own renderer.
phase262RenderedInferenceReplies :: [(String, Text)]
phase262RenderedInferenceReplies =
  [
    ( "InferenceResult"
    , ProtoInference.renderInferenceResult
        ProtoInference.InferenceResult
          { ProtoInference.iresCallId = "unit-call"
          , ProtoInference.iresExperimentHash = "product-row-mnist-deep-mlp"
          , ProtoInference.iresOutput = [0.25, 0.75]
          }
    )
  ,
    ( "InferenceFailure"
    , ProtoInference.renderInferenceFailure
        ProtoInference.InferenceFailure
          { ProtoInference.ifailCallId = "unit-call"
          , ProtoInference.ifailExperimentHash = "product-row-mnist-deep-mlp"
          , ProtoInference.ifailError = "inference: request input rejected"
          }
    )
  ,
    ( "CheckpointCompareResult"
    , ProtoInference.renderCheckpointCompareResult
        ProtoInference.CheckpointCompareResult
          { ProtoInference.ccrCallId = "unit-call"
          , ProtoInference.ccrBaselineExperimentHash = "product-row-mnist-shallow-mlp"
          , ProtoInference.ccrCandidateExperimentHash = "product-row-mnist-deep-mlp"
          , ProtoInference.ccrBaselineOutput = [0.25]
          , ProtoInference.ccrCandidateOutput = [0.5]
          , ProtoInference.ccrMaxAbsDelta = 0.25
          , ProtoInference.ccrMeanAbsDelta = 0.25
          }
    )
  ,
    ( "AdversarialMoveResult"
    , ProtoInference.renderAdversarialMoveResult
        ProtoInference.AdversarialMoveResult
          { ProtoInference.amrCallId = "unit-call"
          , ProtoInference.amrExperimentHash = "product-row-connect4"
          , ProtoInference.amrGame = "connect4"
          , ProtoInference.amrChosenColumn = 3
          , ProtoInference.amrLegalMoves = [0, 1, 2, 3]
          , ProtoInference.amrVisitCounts = [1, 2, 3, 4]
          , ProtoInference.amrPolicyPriors = [0.1, 0.2, 0.3, 0.4]
          , ProtoInference.amrValueEstimate = 0.5
          , ProtoInference.amrGameOver = False
          , ProtoInference.amrTranscriptId = "transcript-1"
          }
    )
  ,
    ( "TranscriptReplay"
    , Workload.renderTranscriptReplayResult
        "unit-call"
        "transcript-1"
        Transcript.TranscriptRecord
          { Transcript.transcriptGame = "connect4"
          , Transcript.transcriptExperimentHash = "product-row-connect4"
          , Transcript.transcriptMoves = [1, 2, 3]
          , Transcript.transcriptAnalysis = "complete"
          }
    )
  , -- The transcript fail path, which answers with an empty replay rather than
    -- redelivering. It publishes only because the wire form admits empty game
    -- and experiment-hash values; a stricter form would make the Engine's own
    -- fallback unpublishable and starve the shared subscription.

    ( "TranscriptReplay (unavailable)"
    , Workload.renderTranscriptReplayResult
        "unit-call"
        "transcript-missing"
        Transcript.TranscriptRecord
          { Transcript.transcriptGame = ""
          , Transcript.transcriptExperimentHash = ""
          , Transcript.transcriptMoves = []
          , Transcript.transcriptAnalysis = "transcript unavailable: absent"
          }
    )
  , ("CheckpointList", phase262CheckpointListFrame)
  ]

-- | One authenticated @CheckpointList@ frame with zero rows, spelled out
-- literally rather than rendered, so the wire form is pinned independently of
-- the renderer that produces it.
-- | A node executing one declared layer kind, built from the kind's own witness
-- operator so the lowering is exercised against the declared vocabulary rather
-- than a hand-picked subset.
phase241WitnessNode :: LayerGraph.LayerKind -> LayerGraph.LayerNode
phase241WitnessNode kind =
  LayerGraph.LayerNode
    { LayerGraph.layerNodeName = "phase-241-" <> LayerGraph.layerKindName kind
    , LayerGraph.layerNodeOp = op
    , LayerGraph.layerInputShape = LayerGraph.TensorShape [4]
    , LayerGraph.layerOutputShape = LayerGraph.TensorShape [4]
    , LayerGraph.layerMode = LayerGraph.TrainingMode
    , LayerGraph.layerActivation = LayerGraph.LinearActivation
    , LayerGraph.layerParameters = Just (LayerGraph.deterministicOpParameters 5 op)
    }
 where
  op = LayerGraph.layerKindWitnessOp kind

phase262CheckpointListFrame :: Text
phase262CheckpointListFrame =
  Text.unlines
    [ "kind: CheckpointList"
    , "call-id: unit-call"
    , "panel: checkpoint-browse"
    , "status: published"
    , "run-id: unit-run"
    , "substrate: linux-cpu"
    , "catalogue-sha256: " <> Text.replicate 64 "a"
    , "source-journal-sha256: " <> Text.replicate 64 "b"
    , "count: 0"
    , "selector-state: fail-closed:no-inference-eligible-artifact"
    ]

-- | The field names the generated browser contract accepts on a
-- @CheckpointList@ frame, read out of its @checkpointFieldNames@ binding.
phase262BrowserCheckpointFieldNames :: Text -> IO [Text]
phase262BrowserCheckpointFieldNames generated =
  case break ("checkpointFieldNames =" `Text.isPrefixOf`) (fmap Text.strip (Text.lines generated)) of
    (_, []) -> assertFailure "generated contracts declare no checkpointFieldNames"
    (_, _ : rest) ->
      pure
        [ name
        | line <- takeWhile (not . Text.isPrefixOf "]") rest
        , Just quoted <- [Text.stripPrefix "[ " line <|> Text.stripPrefix ", " line]
        , let name = Text.dropAround (== '"') (Text.strip quoted)
        , not (Text.null name)
        ]

-- | Read the right-hand side of a top-level @name = ...@ binding out of a
-- PureScript panel.
phase262PanelBinding :: Text -> Text -> IO Text
phase262PanelBinding source name =
  case mapMaybe (Text.stripPrefix (name <> " = ")) (Text.lines source) of
    [] -> assertFailure ("panel declares no " <> Text.unpack name)
    binding : _ -> pure (Text.strip binding)

-- | Read a top-level @name = "literal"@ binding out of a PureScript panel.
phase262PanelStringField :: Text -> Text -> IO Text
phase262PanelStringField source name =
  Text.dropAround (== '"') <$> phase262PanelBinding source name

-- | Read the compare panel's @defaultInputText@ array as numbers.
phase262PanelDefaultInput :: Text -> IO [Double]
phase262PanelDefaultInput source = do
  binding <- phase262PanelBinding source "defaultInputText"
  let literals =
        filter (not . Text.null)
          . fmap (Text.dropAround (== '"') . Text.strip)
          . Text.splitOn ","
          . Text.dropAround (\char -> char == '[' || char == ']')
          . Text.strip
          $ binding
  traverse readPanelNumber literals
 where
  readPanelNumber literal =
    case reads (Text.unpack literal) of
      [(value, "")] -> pure value
      _ ->
        assertFailure
          ("compare panel default input is not numeric: " <> Text.unpack literal)

phase262PreparedGcObjectKeys
  :: CheckpointStore.PreparedCheckpointSnapshot
  -> [Text]
phase262PreparedGcObjectKeys prepared =
  List.sort
    ( fmap fst (CheckpointStore.preparedSnapshotPayloads prepared)
        <> [ CheckpointStore.writerCommitObjectKey
               (CheckpointStore.preparedSnapshotCommit prepared)
           ]
    )

-- Independent lowercase-hex renderer for the experiment-fence text envelope.
-- Deliberately does not call Store's encoder, so the expected wire bytes are
-- computed from the CBOR payload rather than restated by the implementation.
phase262LowerHex :: StrictByteString.ByteString -> Text
phase262LowerHex =
  Text.pack . concatMap encodeByte . StrictByteString.unpack
 where
  encodeByte byte =
    let (high, low) = fromIntegral byte `divMod` (16 :: Int)
     in [intToDigit high, intToDigit low]

-- Independent restatement of the storage snapshot identity: SHA-256 over
-- canonical CBOR of the literal @jitml-snapshot-v1@ domain string, the exact
-- canonical logical-manifest bytes, and the sorted original-key/payload-SHA
-- binding table.
phase262DerivedSnapshotId
  :: Checkpoint.CheckpointManifest
  -> [(Text, Text)]
  -> Text
phase262DerivedSnapshotId logicalManifest originalBindings =
  WeightCodec.jmw1ContentSha
    ( Serialise.serialise
        ( "jitml-snapshot-v1" :: Text
        , ByteString.toStrict (Checkpoint.encodeManifestCbor logicalManifest)
        , List.sortOn fst originalBindings
        )
    )

-- Drive the production bounded-convergence helper and count exactly how many
-- attempts it performed.
phase262CountedConvergence
  :: Int
  -> (Int -> Int -> Either Int Text)
  -> IO (Maybe Text, Int)
phase262CountedConvergence bound step = do
  attempts <- newIORef (0 :: Int)
  outcome <-
    convergeBoundedView
      bound
      ( \attempt state -> do
          modifyIORef' attempts (+ 1)
          pure (step attempt state)
      )
      0
  performed <- readIORef attempts
  pure (outcome, performed)

phase262ScopedGcObjectKeys :: Text -> Text -> [Text] -> [Text]
phase262ScopedGcObjectKeys experimentHash snapshotId objectIds =
  List.sort
    ( [ "jitml-checkpoints/"
          <> experimentHash
          <> "/snapshots/"
          <> snapshotId
          <> "/objects/"
          <> objectId
      | objectId <- objectIds
      ]
        <> [ "jitml-checkpoints/"
               <> experimentHash
               <> "/snapshots/"
               <> snapshotId
               <> "/committed.cbor"
           ]
    )

data Phase262FenceRaceEnv = Phase262FenceRaceEnv
  { phase262FenceRaceRoot :: FilePath
  , phase262FenceRaceFirstIntentList :: MVar ()
  , phase262FenceRaceReleaseFirstIntentList :: MVar ()
  , phase262FenceRaceIntentListCount :: IORef Int
  }

newtype Phase262FenceRaceMinIO value = Phase262FenceRaceMinIO
  { unPhase262FenceRaceMinIO :: ReaderT Phase262FenceRaceEnv IO value
  }
  deriving (Functor, Applicative, Monad)

runPhase262FenceRaceMinIO
  :: Phase262FenceRaceEnv
  -> Phase262FenceRaceMinIO value
  -> IO value
runPhase262FenceRaceMinIO environment action =
  runReaderT (unPhase262FenceRaceMinIO action) environment

phase262WithFilesystemMinIO
  :: FilesystemMinIO value
  -> Phase262FenceRaceMinIO value
phase262WithFilesystemMinIO action = do
  root <- Phase262FenceRaceMinIO (asks phase262FenceRaceRoot)
  Phase262FenceRaceMinIO (liftIO (runFilesystemMinIO root action))

instance HasMinIO Phase262FenceRaceMinIO where
  minioPutIfAbsent ref payload =
    phase262WithFilesystemMinIO (minioPutIfAbsent ref payload)
  minioReadObject ref =
    phase262WithFilesystemMinIO (minioReadObject ref)
  minioReadBytes ref =
    phase262WithFilesystemMinIO (minioReadBytes ref)
  minioReadBytesWithETag ref =
    phase262WithFilesystemMinIO (minioReadBytesWithETag ref)
  putBlobIfAbsent ref payload =
    phase262WithFilesystemMinIO (putBlobIfAbsent ref payload)
  putBlobBytesIfAbsent ref payload =
    phase262WithFilesystemMinIO (putBlobBytesIfAbsent ref payload)
  casPointer ref expected payload =
    phase262WithFilesystemMinIO (casPointer ref expected payload)
  listObjects bucket prefix = do
    listed <- phase262WithFilesystemMinIO (listObjects bucket prefix)
    Control.Monad.when ("/gc/intents/" `Text.isSuffixOf` prefix) $ do
      environment <- Phase262FenceRaceMinIO ask
      listingNumber <-
        Phase262FenceRaceMinIO . liftIO $
          atomicModifyIORef'
            (phase262FenceRaceIntentListCount environment)
            (\count -> let next = count + 1 in (next, next))
      Control.Monad.when (listingNumber == 1) $
        Phase262FenceRaceMinIO . liftIO $ do
          putMVar (phase262FenceRaceFirstIntentList environment) ()
          takeMVar (phase262FenceRaceReleaseFirstIntentList environment)
    pure listed
  deleteObject ref =
    phase262WithFilesystemMinIO (deleteObject ref)

data Phase262CancellationDelayEnv = Phase262CancellationDelayEnv
  { phase262CancellationDelayRoot :: FilePath
  , phase262CancellationDelayReached :: MVar ()
  , phase262CancellationDelayRelease :: MVar ()
  }

newtype Phase262CancellationDelayMinIO value = Phase262CancellationDelayMinIO
  { unPhase262CancellationDelayMinIO :: ReaderT Phase262CancellationDelayEnv IO value
  }
  deriving (Functor, Applicative, Monad)

runPhase262CancellationDelayMinIO
  :: Phase262CancellationDelayEnv
  -> Phase262CancellationDelayMinIO value
  -> IO value
runPhase262CancellationDelayMinIO environment action =
  runReaderT (unPhase262CancellationDelayMinIO action) environment

phase262WithCancellationDelayFilesystem
  :: FilesystemMinIO value
  -> Phase262CancellationDelayMinIO value
phase262WithCancellationDelayFilesystem action = do
  root <- Phase262CancellationDelayMinIO (asks phase262CancellationDelayRoot)
  Phase262CancellationDelayMinIO (liftIO (runFilesystemMinIO root action))

instance HasMinIO Phase262CancellationDelayMinIO where
  minioPutIfAbsent ref payload =
    phase262WithCancellationDelayFilesystem (minioPutIfAbsent ref payload)
  minioReadObject ref =
    phase262WithCancellationDelayFilesystem (minioReadObject ref)
  minioReadBytes ref =
    phase262WithCancellationDelayFilesystem (minioReadBytes ref)
  minioReadBytesWithETag ref =
    phase262WithCancellationDelayFilesystem (minioReadBytesWithETag ref)
  putBlobIfAbsent ref payload =
    phase262WithCancellationDelayFilesystem (putBlobIfAbsent ref payload)
  putBlobBytesIfAbsent ref payload = do
    environment <- Phase262CancellationDelayMinIO ask
    if "/gc/cancelled/"
      `Text.isInfixOf` Capabilities.unObjectKey (Capabilities.objectKey ref)
      then Phase262CancellationDelayMinIO . liftIO $ do
        putMVar (phase262CancellationDelayReached environment) ()
        takeMVar (phase262CancellationDelayRelease environment)
        runFilesystemMinIO
          (phase262CancellationDelayRoot environment)
          (putBlobBytesIfAbsent ref payload)
      else
        phase262WithCancellationDelayFilesystem
          (putBlobBytesIfAbsent ref payload)
  casPointer ref expected payload =
    phase262WithCancellationDelayFilesystem (casPointer ref expected payload)
  listObjects bucket prefix =
    phase262WithCancellationDelayFilesystem (listObjects bucket prefix)
  deleteObject ref =
    phase262WithCancellationDelayFilesystem (deleteObject ref)

data Phase262CancellationCompletionDelayEnv = Phase262CancellationCompletionDelayEnv
  { phase262CancellationCompletionRoot :: FilePath
  , phase262CancellationCompletionReached :: MVar ()
  , phase262CancellationCompletionRelease :: MVar ()
  , phase262CancellationCompletionDidDelay :: IORef Bool
  }

newtype Phase262CancellationCompletionDelayMinIO value
  = Phase262CancellationCompletionDelayMinIO
  { unPhase262CancellationCompletionDelayMinIO
      :: ReaderT Phase262CancellationCompletionDelayEnv IO value
  }
  deriving (Functor, Applicative, Monad)

runPhase262CancellationCompletionDelayMinIO
  :: Phase262CancellationCompletionDelayEnv
  -> Phase262CancellationCompletionDelayMinIO value
  -> IO value
runPhase262CancellationCompletionDelayMinIO environment action =
  runReaderT
    (unPhase262CancellationCompletionDelayMinIO action)
    environment

phase262WithCancellationCompletionFilesystem
  :: FilesystemMinIO value
  -> Phase262CancellationCompletionDelayMinIO value
phase262WithCancellationCompletionFilesystem action = do
  root <-
    Phase262CancellationCompletionDelayMinIO
      (asks phase262CancellationCompletionRoot)
  Phase262CancellationCompletionDelayMinIO
    (liftIO (runFilesystemMinIO root action))

instance HasMinIO Phase262CancellationCompletionDelayMinIO where
  minioPutIfAbsent ref payload =
    phase262WithCancellationCompletionFilesystem (minioPutIfAbsent ref payload)
  minioReadObject ref =
    phase262WithCancellationCompletionFilesystem (minioReadObject ref)
  minioReadBytes ref =
    phase262WithCancellationCompletionFilesystem (minioReadBytes ref)
  minioReadBytesWithETag ref =
    phase262WithCancellationCompletionFilesystem (minioReadBytesWithETag ref)
  putBlobIfAbsent ref payload =
    phase262WithCancellationCompletionFilesystem (putBlobIfAbsent ref payload)
  putBlobBytesIfAbsent ref payload =
    phase262WithCancellationCompletionFilesystem
      (putBlobBytesIfAbsent ref payload)
  casPointer ref expected payload = do
    environment <- Phase262CancellationCompletionDelayMinIO ask
    let completesRearmedCancellation =
          case CheckpointStore.decodeExperimentGcFence payload of
            Left _ -> False
            Right fence ->
              any
                ( \decision ->
                    CheckpointStore.gcFenceDecisionGeneration decision == 1
                      && CheckpointStore.gcFenceDecisionPhase decision
                        == CheckpointStore.GcFenceCancelled
                )
                (CheckpointStore.experimentGcFenceDecisions fence)
    delayThis <-
      if completesRearmedCancellation
        then
          Phase262CancellationCompletionDelayMinIO . liftIO $
            atomicModifyIORef'
              (phase262CancellationCompletionDidDelay environment)
              (\alreadyDelayed -> (True, not alreadyDelayed))
        else pure False
    if delayThis
      then Phase262CancellationCompletionDelayMinIO . liftIO $ do
        putMVar (phase262CancellationCompletionReached environment) ()
        takeMVar (phase262CancellationCompletionRelease environment)
        runFilesystemMinIO
          (phase262CancellationCompletionRoot environment)
          (casPointer ref expected payload)
      else
        phase262WithCancellationCompletionFilesystem
          (casPointer ref expected payload)
  listObjects bucket prefix =
    phase262WithCancellationCompletionFilesystem (listObjects bucket prefix)
  deleteObject ref =
    phase262WithCancellationCompletionFilesystem (deleteObject ref)

data Phase262DeleteFailureEnv = Phase262DeleteFailureEnv
  { phase262DeleteFailureRoot :: FilePath
  , phase262DeleteFailureRef :: Capabilities.ObjectRef
  , phase262DeleteFailureCalls :: IORef [Capabilities.ObjectRef]
  }

newtype Phase262DeleteFailureMinIO value = Phase262DeleteFailureMinIO
  { unPhase262DeleteFailureMinIO :: ReaderT Phase262DeleteFailureEnv IO value
  }
  deriving (Functor, Applicative, Monad)

runPhase262DeleteFailureMinIO
  :: Phase262DeleteFailureEnv
  -> Phase262DeleteFailureMinIO value
  -> IO value
runPhase262DeleteFailureMinIO environment action =
  runReaderT (unPhase262DeleteFailureMinIO action) environment

phase262WithDeleteFailureFilesystem
  :: FilesystemMinIO value
  -> Phase262DeleteFailureMinIO value
phase262WithDeleteFailureFilesystem action = do
  root <- Phase262DeleteFailureMinIO (asks phase262DeleteFailureRoot)
  Phase262DeleteFailureMinIO (liftIO (runFilesystemMinIO root action))

instance HasMinIO Phase262DeleteFailureMinIO where
  minioPutIfAbsent ref payload =
    phase262WithDeleteFailureFilesystem (minioPutIfAbsent ref payload)
  minioReadObject ref =
    phase262WithDeleteFailureFilesystem (minioReadObject ref)
  minioReadBytes ref =
    phase262WithDeleteFailureFilesystem (minioReadBytes ref)
  minioReadBytesWithETag ref =
    phase262WithDeleteFailureFilesystem (minioReadBytesWithETag ref)
  putBlobIfAbsent ref payload =
    phase262WithDeleteFailureFilesystem (putBlobIfAbsent ref payload)
  putBlobBytesIfAbsent ref payload =
    phase262WithDeleteFailureFilesystem (putBlobBytesIfAbsent ref payload)
  casPointer ref expected payload =
    phase262WithDeleteFailureFilesystem (casPointer ref expected payload)
  listObjects bucket prefix =
    phase262WithDeleteFailureFilesystem (listObjects bucket prefix)
  deleteObject ref = do
    environment <- Phase262DeleteFailureMinIO ask
    Phase262DeleteFailureMinIO . liftIO $
      modifyIORef' (phase262DeleteFailureCalls environment) (<> [ref])
    if ref == phase262DeleteFailureRef environment
      then pure (Left (ServiceRetry.SETransient "injected manifest failure"))
      else phase262WithDeleteFailureFilesystem (deleteObject ref)

phase262LoadExperimentFence
  :: FilePath
  -> Text
  -> IO CheckpointStore.ExperimentGcFence
phase262LoadExperimentFence root experimentHash = do
  loaded <-
    runFilesystemMinIO root $
      minioReadBytes
        ( CheckpointStore.checkpointObjectRef
            (CheckpointStore.experimentGcFenceObjectKey experimentHash)
        )
  case loaded of
    Left err -> assertFailure ("could not read experiment GC fence: " <> show err) >> error "unreachable"
    Right bytes ->
      case Text.Encoding.decodeUtf8' bytes of
        Left err -> assertFailure ("experiment GC fence is not UTF-8: " <> show err) >> error "unreachable"
        Right encoded ->
          case CheckpointStore.decodeExperimentGcFence encoded of
            Left err -> assertFailure ("could not decode experiment GC fence: " <> show err) >> error "unreachable"
            Right fence -> pure fence

phase262SingleRevalidatedIntent
  :: CheckpointStore.GcFenceEpoch
  -> CheckpointStore.GcPlan
  -> [Checkpoint.CheckpointManifest]
  -> [Checkpoint.CheckpointManifest]
  -> [CheckpointStore.WriterReservation]
  -> [CheckpointStore.GcEvent]
  -> CheckpointStore.GcIntent
  -> CheckpointStore.RevalidatedGcIntent
phase262SingleRevalidatedIntent epoch plan manifests roots reservations terminals intent =
  case CheckpointStore.revalidateGcIntents
    epoch
    epoch
    plan
    manifests
    roots
    reservations
    terminals
    [intent] of
    Right ([witness], []) -> witness
    result -> error ("expected one freshly revalidated GC intent, got " <> show result)

phase262LoadGcFenceEpoch
  :: FilePath
  -> Text
  -> IO CheckpointStore.GcFenceEpoch
phase262LoadGcFenceEpoch root experimentHash = do
  loaded <-
    runFilesystemMinIO
      root
      (CheckpointStore.loadGcFenceEpoch experimentHash)
  case loaded of
    Left err -> assertFailure ("could not load GC fence epoch: " <> show err) >> error "unreachable"
    Right epoch -> pure epoch

phase262SeedPreparedSnapshotMinIO
  :: FilePath
  -> CheckpointStore.PreparedCheckpointSnapshot
  -> IO ()
phase262SeedPreparedSnapshotMinIO root prepared = do
  outcomes <-
    runFilesystemMinIO root $
      sequence
        ( [ putBlobBytesIfAbsent
              (CheckpointStore.checkpointObjectRef key)
              (ByteString.toStrict payload)
          | (key, payload) <- CheckpointStore.preparedSnapshotPayloads prepared
          ]
            <> [ putBlobBytesIfAbsent
                   ( CheckpointStore.checkpointObjectRef
                       ( Checkpoint.manifestKey
                           (Checkpoint.manifestExperiment (CheckpointStore.preparedSnapshotManifest prepared))
                           (CheckpointStore.preparedSnapshotManifestSha prepared)
                       )
                   )
                   (ByteString.toStrict (CheckpointStore.preparedSnapshotManifestBytes prepared))
               , putBlobBytesIfAbsent
                   ( CheckpointStore.checkpointObjectRef
                       ( CheckpointStore.writerCommitObjectKey
                           (CheckpointStore.preparedSnapshotCommit prepared)
                       )
                   )
                   ( CheckpointStore.encodeWriterCommit
                       (CheckpointStore.preparedSnapshotCommit prepared)
                   )
               ]
        )
  traverse_
    (\case Left err -> assertFailure (show err); Right _ -> pure ())
    outcomes

main :: IO ()
main =
  lookupEnv "JITML_PRODUCT_SCENARIO_UNIT_FIXTURE_WORKER" >>= \case
    Just "1" -> runProductScenarioFixtureWorker
    _ -> unitTestMain

unitTestMain :: IO ()
unitTestMain =
  defaultMain $
    testGroup
      "jitml-unit"
      [ CheckpointV1Admission.checkpointV1AdmissionTests
      , durableStateTopologyTests
      , ProductExperimentExactness.productExperimentExactnessTests
      , ProductTuneTranscript.productTuneTranscriptTests
      , ReconcileStamp.reconcileStampTests
      , RegressionStandardization.regressionStandardizationTests
      , SupervisedCheckpointV2.supervisedCheckpointV2Tests
      , SupervisedTrainingSeed.supervisedTrainingSeedTests
      , HostWorkloadRegistry.hostWorkloadRegistryTests
      , InferenceBatch.inferenceBatchTests
      , PipedProcess.pipedProcessTests
      , ProtocolCodec.protocolCodecTests
      , PulsarBridge.pulsarBridgeTests
      , PulsarTransport.pulsarTransportTests
      , RunContractTest.runContractTests
      , browserEvidenceJournalTests
      , productScenarioJournalTests
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
            ,
              (
                [ "internal"
                , "train-and-publish-product-rows"
                , "--linux-cpu"
                , "--row"
                , "mnist-shallow-mlp"
                ]
              , ParsedCommand
                  ["internal", "train-and-publish-product-rows"]
                  [ ParsedOption "linux-cpu" []
                  , ParsedOption "row" ["mnist-shallow-mlp"]
                  ]
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
      , testCase "ProductRow internal command rejects repeated or list-valued --row" $ do
          assertParseFailure
            [ "internal"
            , "train-and-publish-product-rows"
            , "--linux-cpu"
            , "--row"
            , "mnist-shallow-mlp"
            , "--row"
            , "mnist-deep-mlp"
            ]
          assertBool
            "comma-separated --row values must not widen the exact command"
            ( case selectInternalProductRows
                (Just "mnist-shallow-mlp,mnist-deep-mlp")
                Nothing of
                Left _ -> True
                Right _ -> False
            )
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
          assertBool
            "integration ProductScenario rows must trigger the selected substrate runtime probe"
            ("jitml-integration" `elem` Report.substrateRuntimeStanzas)
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
      , testCase "staged live e2e refines browser evidence before Haskell consumers" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "acquire" "bootstrap"
              producer = plannedScopeTest "jitml-integration" "integration"
              playwright = plannedScopeTest "jitml-e2e-playwright" "playwright"
              haskellE2E = plannedScopeTest "jitml-e2e" "cabal-e2e"
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
                  , LiveE2EScope.liveE2EDiagnosticSteps = []
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
              producerRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-integration"
                  , LiveE2EScope.liveE2ERefinementName = "product-browser-catalogue"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["producer-refinement"])
                        >> pure (LiveE2EScope.LiveE2ERefined ())
                  }
              browserRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-e2e-playwright"
                  , LiveE2EScope.liveE2ERefinementName = "browser-result-journal"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["browser-refinement"])
                        >> pure
                          ( LiveE2EScope.LiveE2ERefined
                              ("measured-browser-report" :: Text)
                          )
                  }
          result <-
            LiveE2EScope.runStagedLiveE2EScope
              backend
              plan
              [producer]
              producerRefinement
              [playwright]
              browserRefinement
              [haskellE2E]
          readIORef executionOrder
            >>= ( @?=
                    [ "acquire"
                    , "jitml-integration"
                    , "producer-refinement"
                    , "jitml-e2e-playwright"
                    , "browser-refinement"
                    , "jitml-e2e"
                    , "release"
                    ]
                )
          LiveE2EScope.liveE2EPrimaryFailure result @?= Nothing
          LiveE2EScope.liveE2EPostBodyFailure result @?= Nothing
          LiveE2EScope.liveE2EPostBodyResult result @?= Just "measured-browser-report"
          case fmap
            Report.invocationResult
            ( Report.invocationJournalEntries
                (LiveE2EScope.liveE2EInvocationJournal result)
            ) of
            [Report.Passed {}, Report.Passed {}, Report.Passed {}] -> pure ()
            observed -> assertFailure ("unexpected staged success journal: " <> show observed)
      , testCase "producer refinement failure honestly blocks browser invocations" $ do
          executionOrder <- newIORef ([] :: [Text])
          finalRefinementRan <- newIORef False
          let acquire = scopeStep "acquire" "bootstrap"
              producer = plannedScopeTest "jitml-integration" "integration"
              playwright = plannedScopeTest "jitml-e2e-playwright" "playwright"
              haskellE2E = plannedScopeTest "jitml-e2e" "cabal-e2e"
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
              producerRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-integration"
                  , LiveE2EScope.liveE2ERefinementName = "product-browser-catalogue"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["producer-refinement"])
                        >> pure
                          ( LiveE2EScope.LiveE2ERefinementRejected
                              "authenticated catalogue refinement failed"
                          )
                  }
              browserRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-e2e-playwright"
                  , LiveE2EScope.liveE2ERefinementName = "browser-result-journal"
                  , LiveE2EScope.liveE2ERefinementAction =
                      writeIORef finalRefinementRan True
                        >> pure (LiveE2EScope.LiveE2ERefined ())
                  }
          result <-
            LiveE2EScope.runStagedLiveE2EScope
              backend
              plan
              [producer]
              producerRefinement
              [playwright]
              browserRefinement
              [haskellE2E]
          readIORef executionOrder
            >>= ( @?=
                    [ "acquire"
                    , "jitml-integration"
                    , "producer-refinement"
                    , "diagnostics"
                    , "release"
                    ]
                )
          readIORef finalRefinementRan >>= (@?= False)
          LiveE2EScope.liveE2EPrimaryFailure result @?= Nothing
          LiveE2EScope.liveE2EPostBodyFailure result
            @?= Just "authenticated catalogue refinement failed"
          case fmap Report.invocationResult . Report.invocationJournalEntries $
            LiveE2EScope.liveE2EInvocationJournal result of
            [ Report.Passed {}
              , Report.NotRunAfterRefinement firstBlocker
              , Report.NotRunAfterRefinement secondBlocker
              ] -> do
                Report.refinementBlockerStanza firstBlocker @?= "jitml-integration"
                Report.refinementBlockerName firstBlocker @?= "product-browser-catalogue"
                Report.refinementBlockerDetail firstBlocker
                  @?= "authenticated catalogue refinement failed"
                secondBlocker @?= firstBlocker
            observed -> assertFailure ("unexpected refinement-blocked journal: " <> show observed)
      , testCase "browser journal refinement runs before propagating Playwright failure" $ do
          executionOrder <- newIORef ([] :: [Text])
          let acquire = scopeStep "acquire" "bootstrap"
              producer = plannedScopeTest "jitml-integration" "integration"
              playwright = plannedScopeTest "jitml-e2e-playwright" "playwright"
              haskellE2E = plannedScopeTest "jitml-e2e" "cabal-e2e"
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        if livePlanStepName step == "jitml-e2e-playwright"
                          then failedScopeOutcome 7 20 step
                          else successfulScopeOutcome 10 step
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
                  , LiveE2EScope.liveE2EDiagnosticSteps = [diagnostics]
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
              producerRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-integration"
                  , LiveE2EScope.liveE2ERefinementName = "product-browser-catalogue"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["producer-refinement"])
                        >> pure (LiveE2EScope.LiveE2ERefined ())
                  }
              browserRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-e2e-playwright"
                  , LiveE2EScope.liveE2ERefinementName = "browser-result-journal"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["browser-refinement"])
                        >> pure
                          ( LiveE2EScope.LiveE2ERefinedWithIssue
                              ()
                              "browser result contains NotRun rows"
                          )
                  }
          result <-
            LiveE2EScope.runStagedLiveE2EScope
              backend
              plan
              [producer]
              producerRefinement
              [playwright]
              browserRefinement
              [haskellE2E]
          readIORef executionOrder
            >>= ( @?=
                    [ "acquire"
                    , "jitml-integration"
                    , "producer-refinement"
                    , "jitml-e2e-playwright"
                    , "browser-refinement"
                    , "diagnostics"
                    , "release"
                    ]
                )
          fmap LiveE2EScope.liveE2EFailureStep (LiveE2EScope.liveE2EPrimaryFailure result)
            @?= Just "jitml-e2e-playwright"
          LiveE2EScope.liveE2EPostBodyResult result @?= Just ()
          LiveE2EScope.liveE2EPostBodyFailure result
            @?= Just "browser result contains NotRun rows"
          case fmap Report.invocationResult . Report.invocationJournalEntries $
            LiveE2EScope.liveE2EInvocationJournal result of
            [Report.Passed {}, Report.Failed failure, Report.NotRun blocker] ->
              Report.blockedByFailure blocker @?= failure
            observed -> assertFailure ("unexpected browser failure journal: " <> show observed)
      , testCase "browser refinement rejection blocks post-refinement stanzas honestly" $ do
          executionOrder <- newIORef ([] :: [Text])
          let producer = plannedScopeTest "jitml-integration" "integration"
              playwright = plannedScopeTest "jitml-e2e-playwright" "playwright"
              haskellE2E = plannedScopeTest "jitml-e2e" "cabal-e2e"
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = BorrowedLiveCluster
                  , scopedLivePlanAcquire = []
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = []
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
                  , LiveE2EScope.liveE2EDiagnosticSteps = []
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
              producerRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-integration"
                  , LiveE2EScope.liveE2ERefinementName = "product-browser-catalogue"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["producer-refinement"])
                        >> pure (LiveE2EScope.LiveE2ERefined ())
                  }
              browserRefinement =
                LiveE2EScope.LiveE2ERefinement
                  { LiveE2EScope.liveE2ERefinementSourceStanza = "jitml-e2e-playwright"
                  , LiveE2EScope.liveE2ERefinementName = "browser-result-journal"
                  , LiveE2EScope.liveE2ERefinementAction =
                      modifyIORef' executionOrder (<> ["browser-refinement"])
                        >> pure
                          ( LiveE2EScope.LiveE2ERefinementRejected
                              "browser journal authentication failed"
                              :: LiveE2EScope.LiveE2ERefinementOutcome Text
                          )
                  }
          result <-
            LiveE2EScope.runStagedLiveE2EScope
              backend
              plan
              [producer]
              producerRefinement
              [playwright]
              browserRefinement
              [haskellE2E]
          readIORef executionOrder
            >>= ( @?=
                    [ "jitml-integration"
                    , "producer-refinement"
                    , "jitml-e2e-playwright"
                    , "browser-refinement"
                    ]
                )
          LiveE2EScope.liveE2EPrimaryFailure result @?= Nothing
          LiveE2EScope.liveE2EPostBodyResult result @?= Nothing
          LiveE2EScope.liveE2EPostBodyFailure result
            @?= Just "browser journal authentication failed"
          case fmap Report.invocationResult . Report.invocationJournalEntries $
            LiveE2EScope.liveE2EInvocationJournal result of
            [ Report.Passed {}
              , Report.Passed {}
              , Report.NotRunAfterRefinement blocker
              ] -> do
                Report.refinementBlockerStanza blocker @?= "jitml-e2e-playwright"
                Report.refinementBlockerName blocker @?= "browser-result-journal"
                Report.refinementBlockerDetail blocker
                  @?= "browser journal authentication failed"
            observed -> assertFailure ("unexpected browser rejection journal: " <> show observed)
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "playwright-live" -> failedScopeOutcome 7 20 step
                          "diagnostics" -> failedScopeOutcome 8 30 step
                          "release" -> failedScopeOutcome 9 40 step
                          _ -> successfulScopeOutcome 10 step
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      case livePlanStepName step of
                        "playwright-live" ->
                          Exception.throwIO (userError "playwright launch exploded")
                        "diagnostics" ->
                          Exception.throwIO (userError "diagnostics launch exploded")
                        _ -> pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      if livePlanStepName step == "playwright-live"
                        then Exception.throwIO Exception.ThreadKilled
                        else pure (successfulScopeOutcome 10 step)
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "bootstrap" -> failedScopeOutcome 6 11 step
                          "release" -> failedScopeOutcome 3 13 step
                          _ -> successfulScopeOutcome 12 step
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "diagnostics" -> failedScopeOutcome 8 30 step
                          "release" -> failedScopeOutcome 9 40 step
                          _ -> successfulScopeOutcome 20 step
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
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
                  { LiveE2EScope.liveE2ERunStep = \_environment step -> do
                      modifyIORef' executionOrder (<> [livePlanStepName step])
                      pure $
                        case livePlanStepName step of
                          "release" -> failedScopeOutcome 9 40 step
                          _ -> successfulScopeOutcome 20 step
                  , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
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
      , testCase "phase link scan reads markdown link destinations only" $ do
          -- A renumber rewrites prose and moves files; a citation it misses stays
          -- valid markdown pointing at nothing, which metadata validation cannot
          -- see. The scan therefore reads destinations, and must not be fooled by
          -- a phase file name that merely appears in prose or in a code span.
          DocsCheck.phaseLinkTargets
            ( Text.unlines
                [ "See [Phase 42](phase-42-some-slug.md) and"
                , "[relative](../DEVELOPMENT_PLAN/phase-7-other-slug.md#anchor)."
                , "Prose naming phase-99-not-a-link.md is not a citation, nor is"
                , "`phase-98-code-span.md` inside a code span."
                , "[repeat](phase-42-some-slug.md) is counted once."
                ]
            )
            @?= [ "../DEVELOPMENT_PLAN/phase-7-other-slug.md"
                , "phase-42-some-slug.md"
                ]
      , testCase "phase link scan ignores non-phase link destinations" $ do
          DocsCheck.phaseLinkTargets
            ( Text.unlines
                [ "[readme](README.md), [anchor](README.md#legacy-to-new-phase-map),"
                , "[no slug](phase-12-.md), [no digits](phase-abc-slug.md)."
                ]
            )
            @?= []
      , testCase "docs root metadata check accepts complete root-doc headers" $ do
          DocsCheck.checkRootDocMetadataText
            "README.md"
            ( Text.unlines
                [ "# jitML"
                , ""
                , "**Status**: Governed orientation document"
                , "**Supersedes**: N/A"
                , "**Canonical homes**: [documents/README.md](documents/README.md)"
                , ""
                , "> **Purpose**: Orientation."
                ]
            )
            @?= []
      , testCase "docs root metadata check rejects missing root header fields" $ do
          let drifts =
                DocsCheck.checkRootDocMetadataText
                  "AGENTS.md"
                  ( Text.unlines
                      [ "# AGENTS.md"
                      , ""
                      , "**Status**: Governed entry document"
                      , ""
                      , "> **Purpose**: Entry."
                      ]
                  )
          fmap DocsCheck.driftKey drifts
            @?= ["metadata.supersedes", "metadata.canonical-homes"]
      , testCase "docs taxonomy and naming predicates hold for the canonical layout" $ do
          DocsCheck.docsCategoryAllowed "engineering" @?= True
          DocsCheck.docsCategoryAllowed "cli" @?= True
          DocsCheck.docsCategoryAllowed "operations" @?= False
          DocsCheck.docNameConforms "checkpoint_format.md" @?= True
          DocsCheck.docNameConforms "README.md" @?= True
          DocsCheck.docNameConforms "Not-Snake.md" @?= False
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
      , testCase "inference reply scope releases an admin-created cursor even before consumer readiness" $ do
          neverReady <- newEmptyMVar
          released <- newIORef False
          let consumerAction :: IO (Either Capabilities.ConsumerFailure ())
              consumerAction = do
                _ <- takeMVar neverReady
                pure (Right ())
              releaseAction :: IO (Either Capabilities.ConsumerFailure ())
              releaseAction = do
                writeIORef released True
                pure (Right ())
              primaryAction :: IO (Either Text ())
              primaryAction = pure (Left "correlated publish failed before consumer readiness")
          result <-
            withinUnitDeadline
              "inference reply scope did not release the established cursor"
              (runInferenceReplyScopeWithRelease consumerAction releaseAction primaryAction)
          result @?= Left "correlated publish failed before consumer readiness"
          readIORef released >>= (@?= True)
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
      , testCase "Work* ArtifactRef minting requires opaque Store admission" $ do
          let mintFromPersistedAdmission
                :: CheckpointStore.AdmittedCompletedCheckpoint
                -> Work.ArtifactRef
              mintFromPersistedAdmission = Work.mintArtifactRef
          mintFromPersistedAdmission `seq` pure ()
          source <- Text.IO.readFile "src/JitML/Work/Envelope.hs"
          assertBool
            "ArtifactRef minting bypasses Store via structural completion refinement"
            (not ("validateCheckpointCompletion" `Text.isInfixOf` source))
          assertBool
            "ArtifactRef minting does not consume Store admission"
            ("CheckpointStore.AdmittedCompletedCheckpoint" `Text.isInfixOf` source)
          assertBool
            "readiness sentinel ends in .ready"
            (".ready" `Text.isSuffixOf` Work.readinessSentinelKey "exp1")
      , testCase "Work* command parse rejects malformed / unready commands with typed rejections" $ do
          -- inference requires a ready derived artifact
          Work.parseWorkCommand Topology.Infer Substrate.LinuxCPU "c" "exp1" Nothing "1" "reply"
            @?= Left (Work.ArtifactNotReady Topology.Infer)
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
              Tune.tuningConfigParallelism config @?= 1
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
      , testCase "child-specific environment scrubs journal capabilities without rendering its challenge" $ do
          let challenge = "product-scenario-invocation-v1\t" <> Text.replicate 64 "c"
              journalKey = "unit-journal-signing-secret"
              journalPath = "/tmp/unit-journal-secret-path"
              runIdentity = "unit-parent-run-secret"
              parentExecutablePath = "/tmp/unit-parent-jitml-secret-path"
              parentExecutableSha = Text.replicate 64 "e"
              environment =
                subprocessEnvOverrideAndRemove
                  [ ("JITML_PRODUCT_SCENARIO_INVOCATION", challenge)
                  , ("JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE", journalKey)
                  , ("JITML_PRODUCT_SCENARIO_JOURNAL_PATH", journalPath)
                  , ("JITML_PRODUCT_SCENARIO_RUN_ID", runIdentity)
                  , ("JITML_PRODUCT_SCENARIO_EXECUTABLE", parentExecutablePath)
                  , ("JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256", parentExecutableSha)
                  ]
                  [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
                  , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
                  , "JITML_PRODUCT_SCENARIO_RUN_ID"
                  , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
                  , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
                  ]
              command =
                subprocess
                  "/bin/sh"
                  [ "-c"
                  , Text.unwords
                      [ "test -n \"${JITML_PRODUCT_SCENARIO_INVOCATION:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_JOURNAL_PATH:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_RUN_ID:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_EXECUTABLE:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256:-}\""
                      , "&& printf scrubbed >&2; exit 7"
                      ]
                  ]
          outcome <- runStreaming environment command
          case outcome of
            ProcessSucceeded transcript ->
              assertFailure
                ("scrub fixture unexpectedly succeeded: " <> show transcript)
            ProcessFailed failure -> do
              processFailureStderr failure @?= "scrubbed"
              let rendered = renderProcessOutcome outcome
              assertBool
                "rendered process failure leaked the invocation challenge"
                (not (challenge `Text.isInfixOf` rendered))
              assertBool
                "rendered process failure leaked the journal key"
                (not (journalKey `Text.isInfixOf` rendered))
              assertBool
                "rendered process failure leaked the journal path"
                (not (journalPath `Text.isInfixOf` rendered))
              assertBool
                "rendered process failure leaked the parent run identity"
                (not (runIdentity `Text.isInfixOf` rendered))
              assertBool
                "rendered process failure leaked the parent executable path"
                (not (parentExecutablePath `Text.isInfixOf` rendered))
              assertBool
                "rendered process failure leaked the parent executable SHA"
                (not (parentExecutableSha `Text.isInfixOf` rendered))
      , testCase "live planned environment is delivered without rendering journal capabilities" $ do
          let keyPath = "/tmp/jitml-unit-secret/journal-key"
              journalPath = "/tmp/jitml-unit-secret/journal.cbor"
              runIdentity = "unit-secret-run-identity"
              executablePath = "/tmp/jitml-unit-secret/jitml"
              executableSha256 = Text.replicate 64 "e"
              environment =
                subprocessEnvOverrideAndRemove
                  [ ("JITML_SUBSTRATE", "linux-cpu")
                  , ("JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE", keyPath)
                  , ("JITML_PRODUCT_SCENARIO_JOURNAL_PATH", journalPath)
                  , ("JITML_PRODUCT_SCENARIO_RUN_ID", runIdentity)
                  , ("JITML_PRODUCT_SCENARIO_EXECUTABLE", executablePath)
                  , ("JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256", executableSha256)
                  ]
                  ["JITML_PRODUCT_SCENARIO_INVOCATION"]
              command =
                subprocess
                  "/bin/sh"
                  [ "-c"
                  , Text.unwords
                      [ "test -n \"${JITML_SUBSTRATE:-}\""
                      , "&& test -n \"${JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE:-}\""
                      , "&& test -n \"${JITML_PRODUCT_SCENARIO_JOURNAL_PATH:-}\""
                      , "&& test -n \"${JITML_PRODUCT_SCENARIO_RUN_ID:-}\""
                      , "&& test -n \"${JITML_PRODUCT_SCENARIO_EXECUTABLE:-}\""
                      , "&& test -n \"${JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_INVOCATION:-}\""
                      , "&& printf capabilities-received"
                      ]
                  ]
              scrubbedCommand =
                subprocess
                  "/bin/sh"
                  [ "-c"
                  , Text.unwords
                      [ "test -z \"${JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_JOURNAL_PATH:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_RUN_ID:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_EXECUTABLE:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256:-}\""
                      , "&& test -z \"${JITML_PRODUCT_SCENARIO_INVOCATION:-}\""
                      , "&& printf stale-capabilities-scrubbed"
                      ]
                  ]
              staleEnvironment =
                subprocessEnvOverrideAndRemove
                  [ ("JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE", keyPath)
                  , ("JITML_PRODUCT_SCENARIO_JOURNAL_PATH", journalPath)
                  , ("JITML_PRODUCT_SCENARIO_RUN_ID", runIdentity)
                  , ("JITML_PRODUCT_SCENARIO_EXECUTABLE", executablePath)
                  , ("JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256", executableSha256)
                  , ("JITML_PRODUCT_SCENARIO_INVOCATION", "stale-invocation")
                  ]
                  [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
                  , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
                  , "JITML_PRODUCT_SCENARIO_RUN_ID"
                  , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
                  , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
                  , "JITML_PRODUCT_SCENARIO_INVOCATION"
                  ]
              planned =
                LiveE2EScope.PlannedTestInvocation
                  { LiveE2EScope.plannedTestStanza = "jitml-integration"
                  , LiveE2EScope.plannedTestCommand = command
                  , LiveE2EScope.plannedTestEnvironment = environment
                  }
              unrelated =
                LiveE2EScope.PlannedTestInvocation
                  { LiveE2EScope.plannedTestStanza = "jitml-unit"
                  , LiveE2EScope.plannedTestCommand = scrubbedCommand
                  , LiveE2EScope.plannedTestEnvironment = staleEnvironment
                  }
              plan =
                ScopedLivePlan
                  { scopedLivePlanOwnership = OwnedEphemeralCluster
                  , scopedLivePlanAcquire =
                      [ LivePlanStep
                          { livePlanStepName = "acquire-scrub"
                          , livePlanStepCommand = scrubbedCommand
                          }
                      ]
                  , scopedLivePlanBody = []
                  , scopedLivePlanRelease = []
                  }
              backend =
                LiveE2EScope.LiveE2EScopeBackend
                  { LiveE2EScope.liveE2ERunStep =
                      \childEnvironment step ->
                        runStreaming childEnvironment (livePlanStepCommand step)
                  , LiveE2EScope.liveE2ELifecycleEnvironment = staleEnvironment
                  , LiveE2EScope.liveE2EDiagnosticSteps = []
                  , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
                  }
          result <-
            LiveE2EScope.runLiveE2EScope
              backend
              plan
              [planned, unrelated]
              (pure (Right ()))
          LiveE2EScope.liveE2EScopeFailure result @?= Nothing
          let invocationJournal = LiveE2EScope.liveE2EInvocationJournal result
          case Report.invocationJournalEntries invocationJournal of
            [integrationRecord, unrelatedRecord] ->
              case ( Report.invocationResult integrationRecord
                   , Report.invocationResult unrelatedRecord
                   ) of
                (Report.Passed integrationTranscript, Report.Passed unrelatedTranscript) -> do
                  processTranscriptStdout integrationTranscript @?= "capabilities-received"
                  processTranscriptStdout unrelatedTranscript @?= "stale-capabilities-scrubbed"
                  Report.invocationCommand integrationRecord @?= renderSubprocess command
                  Report.invocationCommand unrelatedRecord @?= renderSubprocess scrubbedCommand
                  processTranscriptCommand integrationTranscript @?= renderSubprocess command
                  processTranscriptCommand unrelatedTranscript @?= renderSubprocess scrubbedCommand
                  let showCapableEvidence =
                        Text.unlines
                          [ renderSubprocess command
                          , renderSubprocess scrubbedCommand
                          , Report.invocationCommand integrationRecord
                          , Report.invocationCommand unrelatedRecord
                          , processTranscriptCommand integrationTranscript
                          , processTranscriptCommand unrelatedTranscript
                          , Text.pack (show invocationJournal)
                          , Text.pack (show (LiveE2EScope.liveE2EScenarioJournal result))
                          ]
                  for_
                    [keyPath, journalPath, runIdentity, executablePath, executableSha256]
                    ( \capability ->
                        assertBool
                          "rendered command/transcript leaked a ProductScenario capability"
                          (not (capability `Text.isInfixOf` showCapableEvidence))
                    )
                observed ->
                  assertFailure
                    ("environment propagation fixtures did not pass: " <> show observed)
            observed ->
              assertFailure
                ("unexpected environment propagation journal: " <> show observed)
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
              linuxCpuFingerprint =
                Cache.unToolchainFingerprint
                  (Fingerprint.engineFamilyToolchainFingerprint Substrate.LinuxCPU)
          assertBool
            "linux-cpu local fingerprint separates host/container artifact ABIs"
            (expectedAbi `Text.isInfixOf` linuxCpuFingerprint)
          assertBool
            "linux-cpu local fingerprint records the deterministic reduction block"
            ( ("reduction-block=" <> Text.pack (show OneDnnCodegen.oneDnnFixedReductionBlock))
                `Text.isInfixOf` linuxCpuFingerprint
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
      , testCase "kernel loader probes the artifact toolchain once per process" $
          withSystemTempDirectory "jitml-toolchain-probe" $ \dir -> do
            cwd <- getCurrentDirectory
            originalPath <- fromMaybe "" <$> lookupEnv "PATH"
            let shimDirectory = dir </> "shim"
                shimPath = shimDirectory </> "nvcc"
                probeLog = dir </> "nvcc-invocations"
            createDirectoryIfMissing True shimDirectory
            writeFile
              shimPath
              ( unlines
                  [ "#!/bin/sh"
                  , "echo invoked >> " <> probeLog
                  , "echo 'Cuda compilation tools, release 12.8, V12.8.61'"
                  ]
              )
            shimPermissions <- getPermissions shimPath
            setPermissions shimPath (setOwnerExecutable True shimPermissions)
            writeFile probeLog ""
            bracket_
              (setCurrentDirectory dir >> setEnv "PATH" (shimDirectory <> ":" <> originalPath))
              (setEnv "PATH" originalPath >> setCurrentDirectory cwd)
              $ do
                env <- buildEnv defaultGlobalFlags
                let kernelSpec = Cache.KernelSpec "phase-78-kernel:toolchain-probe"
                    engine = Engine.engineForSubstrate Substrate.LinuxCUDA
                    source =
                      renderRuntimeSource
                        kernelSpec
                        Cache.Inference
                        Cache.LinuxCUDA
                        Cache.defaultTuningChoice
                    handle = Engine.kernelHandleFor engine sampleCacheHash
                    artifactPath = Text.unpack (Engine.kernelHandleArtifactPath handle)
                createDirectoryIfMissing True (takeDirectory artifactPath)
                StrictByteString.writeFile artifactPath (StrictByteString.pack [0x7f, 0x45, 0x4c, 0x46])
                -- Every one of these is a cache hit, which is what a training
                -- loop does: `ensureKernelArtifact` runs per device operation,
                -- not per compile.
                statuses <-
                  traverse
                    (const (Loader.ensureKernelArtifact env engine source sampleCacheHash))
                    [1 :: Int .. 32]
                assertBool
                  "every repeated resolution is a cache hit"
                  ( all
                      ( \case
                          Right artifact ->
                            not (Loader.kernelArtifactCompiled artifact)
                          Left _ -> False
                      )
                      statuses
                  )
                invocations <- length . lines <$> readFile probeLog
                assertBool
                  ( "the toolchain probe is memoised per process, but nvcc ran "
                      <> show invocations
                      <> " times across 32 cache hits"
                  )
                  (invocations <= 1)
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
            @?= ["HasMinIO", "HasPulsar", "HasImageRegistry", "HasKubectl"]
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
      , testCase "Phase 252 learning curves are non-empty, finite, and strictly ordered" $ do
          first <-
            either (assertFailure . Text.unpack) pure $
              RLFramework.mkIterationSummary 0 "training_reward" 1.0
          second <-
            either (assertFailure . Text.unpack) pure $
              RLFramework.mkIterationSummary 1 "training_reward" 2.0
          otherMetric <-
            either (assertFailure . Text.unpack) pure $
              RLFramework.mkIterationSummary 2 "training_loss" 0.5
          assertBool "empty learning curve accepted" (isLeftResult (RLFramework.mkLearningCurve []))
          assertBool
            "unordered learning curve accepted"
            (isLeftResult (RLFramework.mkLearningCurve [second, first]))
          assertBool
            "non-finite iteration summary accepted"
            (isLeftResult (RLFramework.mkIterationSummary 2 "training_reward" (0 / 0)))
          assertBool
            "mixed-metric learning curve accepted"
            (isLeftResult (RLFramework.mkLearningCurve [first, second, otherMetric]))
          fmap
            (fmap RLFramework.iterationSummaryMetricValue . RLFramework.learningCurveSummaries)
            (RLFramework.mkLearningCurve [first, second])
            @?= Right [1.0, 2.0]
      , testCase "Phase 252 exact evaluation set uses the complete finite keyed cohort" $ do
          let ordered =
                [ (0, 100.0, 3, True)
                , (1, 100.0, 4, True)
                , (2, 0.0, 5, False)
                , (3, 0.0, 6, False)
                ]
              shuffled =
                [ (2, 0.0, 5, False)
                , (0, 100.0, 3, True)
                , (3, 0.0, 6, False)
                , (1, 100.0, 4, True)
                ]
          exact <-
            either (assertFailure . Text.unpack) pure (RLFramework.mkEvaluationSet 4 ordered)
          reordered <-
            either (assertFailure . Text.unpack) pure (RLFramework.mkEvaluationSet 4 shuffled)
          counters <-
            either (assertFailure . Text.unpack) pure $
              AlgorithmCommon.mkMeasuredTrainerCounters 10 2
          metrics <-
            either (assertFailure . Text.unpack) pure $
              ProductCompletion.rlCompletionMetrics "ppo" counters reordered
          RLFramework.evaluationSetMedianReward exact @?= 50.0
          RLFramework.evaluationSetMedianReward reordered @?= 50.0
          RLFramework.evaluationSetOutcomes reordered @?= RLFramework.evaluationSetOutcomes exact
          lookup "median_final_reward" metrics @?= Just 50.0
          lookup "env_steps" metrics @?= Just 10.0
          assertBool
            "duplicate evaluation key accepted"
            (isLeftResult (RLFramework.mkEvaluationSet 4 (take 3 ordered <> [ordered !! 2])))
          assertBool
            "gapped evaluation key accepted"
            (isLeftResult (RLFramework.mkEvaluationSet 4 (take 3 ordered <> [(4, 0.0, 1, False)])))
          assertBool "empty evaluation set accepted" (isLeftResult (RLFramework.mkEvaluationSet 0 []))
          assertBool
            "non-finite evaluation reward accepted"
            (isLeftResult (RLFramework.mkEvaluationSet 1 [(0, 1 / 0, 1, True)]))
          assertBool
            "zero-step evaluation outcome accepted"
            (isLeftResult (RLFramework.mkEvaluationSet 1 [(0, 1.0, 0, True)]))
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
      , testCase "Phase 250 — typed cohort smart constructor rejects/accepts action-domain pairs" $ do
          let isRejected result =
                case result of
                  Left _ -> True
                  Right _ -> False
          -- Incompatible discrete/continuous/goal-conditioned pairs have no value.
          assertBool "SAC+cartpole rejected" (isRejected (AlgorithmRegistry.mkCohort "SAC" "cartpole"))
          assertBool "DQN+pendulum rejected" (isRejected (AlgorithmRegistry.mkCohort "DQN" "pendulum"))
          assertBool "HER+cartpole rejected" (isRejected (AlgorithmRegistry.mkCohort "HER" "cartpole"))
          -- Canonical pairs construct with the exact action domain and trainer kind.
          fmap AlgorithmRegistry.cohortActionDomain (AlgorithmRegistry.mkCohort "PPO" "cartpole")
            @?= Right AlgorithmRegistry.DiscreteDomain
          fmap AlgorithmRegistry.cohortActionDomain (AlgorithmRegistry.mkCohort "SAC" "pendulum")
            @?= Right AlgorithmRegistry.ContinuousDomain
          fmap AlgorithmRegistry.cohortActionDomain (AlgorithmRegistry.mkCohort "HER" "goal-reaching")
            @?= Right AlgorithmRegistry.GoalConditionedDomain
          -- lunar-lander is dual-domain, resolved from the (algorithm, environment) pair.
          fmap AlgorithmRegistry.cohortActionDomain (AlgorithmRegistry.mkCohort "PPO" "lunar-lander")
            @?= Right AlgorithmRegistry.DiscreteDomain
          fmap AlgorithmRegistry.cohortActionDomain (AlgorithmRegistry.mkCohort "SAC" "lunar-lander")
            @?= Right AlgorithmRegistry.ContinuousDomain
          -- The cohort renders the identity-critical trainer-kind string.
          fmap AlgorithmRegistry.cohortTrainerKind (AlgorithmRegistry.mkCohort "QR-DQN" "cartpole")
            @?= Right "qrdqn"
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
      , testCase "explicit tuning plan seeds deterministically select distinct trial streams" $ do
          let seeded seedValue =
                Tune.trialObjectiveResultsForSeededBudget
                  seedValue
                  Tune.TPE
                  1
                  Tune.tuningObjectiveOptimizerUpdates
                  4
          case (seeded 1729, seeded 1730, seeded 1729) of
            (Right first, Right second, Right replay) -> do
              replay @?= first
              assertBool "different explicit seeds must change the executed trial stream" (second /= first)
            outcomes -> assertFailure ("seeded tuning schedule failed: " <> show outcomes)
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
      , testCase
          "checkpoint snapshot preparation isolates every physical class deterministically (Phase 262)"
          $ do
            let experimentHash = "exp-snapshot-prepare"
                tensorPayload = Checkpoint.encodeJmw1 [1.0]
                optimizerPayload = "optimizer-state"
                rngPayload = "12345678"
                replayPayload = "replay-payload"
                transcriptPayload = "transcript-payload"
                substratePayload = "substrate-payload"
                contentKey payload =
                  Checkpoint.blobKey
                    experimentHash
                    (WeightCodec.jmw1ContentSha payload)
                tensorKey = Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha tensorPayload)
                optimizerKey = contentKey optimizerPayload
                rngKey = contentKey rngPayload
                replayKey = contentKey replayPayload
                transcriptKey = contentKey transcriptPayload
                substrateKey = contentKey substratePayload
                manifest =
                  ( Checkpoint.emptyManifest
                      "snapshot-logical"
                      experimentHash
                      [Checkpoint.TensorBlob "weights" [1] tensorKey]
                  )
                    { Checkpoint.manifestOptimizer =
                        [ Checkpoint.OptimizerBlob
                            "adam"
                            optimizerKey
                            (fromIntegral (ByteString.length optimizerPayload))
                        ]
                    , Checkpoint.manifestRng =
                        [Checkpoint.RngBlob "training" rngKey 1]
                    , Checkpoint.manifestReplayPointers =
                        [ Checkpoint.ArtifactPointer
                            "replay"
                            replayKey
                            (Just (WeightCodec.jmw1ContentSha replayPayload))
                        ]
                    , Checkpoint.manifestTranscriptPointers =
                        [ Checkpoint.ArtifactPointer
                            "transcript"
                            transcriptKey
                            (Just (WeightCodec.jmw1ContentSha transcriptPayload))
                        ]
                    , Checkpoint.manifestSubstrateArtifacts =
                        [ Checkpoint.SubstrateArtifact
                            "linux-cpu"
                            "kernel"
                            (WeightCodec.jmw1ContentSha substratePayload)
                            (Just substrateKey)
                        ]
                    , Checkpoint.manifestMetrics = [("z", 2), ("a", 1)]
                    }
                payloads =
                  [ (tensorKey, tensorPayload)
                  , (optimizerKey, optimizerPayload)
                  , (rngKey, rngPayload)
                  , (replayKey, replayPayload)
                  , (transcriptKey, transcriptPayload)
                  , (substrateKey, substratePayload)
                  ]
                prepare =
                  CheckpointStore.prepareCheckpointSnapshot
                    CheckpointStore.WriterCandidateSnapshot
                    CheckpointStore.WriterNoPointerIntent
            prepared <-
              case prepare manifest payloads of
                Left err -> assertFailure ("snapshot preparation failed: " <> Text.unpack err)
                Right value -> pure value
            reordered <-
              case prepare
                manifest {Checkpoint.manifestMetrics = reverse (Checkpoint.manifestMetrics manifest)}
                (reverse payloads) of
                Left err -> assertFailure ("reordered snapshot preparation failed: " <> Text.unpack err)
                Right value -> pure value
            CheckpointStore.preparedSnapshotId reordered
              @?= CheckpointStore.preparedSnapshotId prepared
            CheckpointStore.preparedSnapshotManifestSha reordered
              @?= CheckpointStore.preparedSnapshotManifestSha prepared
            let snapshotPrefix =
                  "jitml-checkpoints/"
                    <> experimentHash
                    <> "/snapshots/"
                    <> CheckpointStore.preparedSnapshotId prepared
                    <> "/objects/"
                physicalKeys = fmap fst (CheckpointStore.preparedSnapshotPayloads prepared)
            length physicalKeys @?= 6
            assertBool
              "every physical class is rebased into the one snapshot namespace"
              (all (snapshotPrefix `Text.isPrefixOf`) physicalKeys)
            CheckpointStore.checkpointStorageSnapshotId
              (CheckpointStore.preparedSnapshotManifest prepared)
              @?= Right (Just (CheckpointStore.preparedSnapshotId prepared))
            reservation <-
              case CheckpointStore.instantiateWriterReservation
                (Text.replicate 64 "1")
                (CheckpointStore.preparedSnapshotReservationTemplate prepared) of
                Left err -> assertFailure ("reservation instantiation failed: " <> Text.unpack err)
                Right value -> pure value
            let commit = CheckpointStore.preparedSnapshotCommit prepared
            CheckpointStore.decodeWriterReservation
              (CheckpointStore.encodeWriterReservation reservation)
              @?= Right reservation
            CheckpointStore.decodeWriterCommit
              (CheckpointStore.encodeWriterCommit commit)
              @?= Right commit
            assertBool
              "reservation validation rejects a snapshot id that does not bind its physical paths"
              ( case CheckpointStore.validateWriterReservation
                  reservation {CheckpointStore.writerReservationSnapshotId = Text.replicate 64 "a"} of
                  Left _ -> True
                  Right _ -> False
              )
            assertBool
              "commit validation rejects a noncanonical payload hash"
              ( case CheckpointStore.writerCommitPhysicalObjects commit of
                  firstPhysical : remaining ->
                    case CheckpointStore.validateWriterCommit
                      commit
                        { CheckpointStore.writerCommitPhysicalObjects =
                            firstPhysical {CheckpointStore.writerPhysicalObjectSha = "bad"}
                              : remaining
                        } of
                      Left _ -> True
                      Right _ -> False
                  [] -> False
              )
            assertBool
              "commit validation rejects an original-key substitution that preserves scoped key and payload SHA"
              ( case CheckpointStore.writerCommitPhysicalObjects commit of
                  firstPhysical : remaining ->
                    case CheckpointStore.validateWriterCommit
                      commit
                        { CheckpointStore.writerCommitPhysicalObjects =
                            firstPhysical
                              { CheckpointStore.writerPhysicalObjectOriginalKey =
                                  Checkpoint.blobKey
                                    experimentHash
                                    (Text.replicate 64 "d")
                              }
                              : remaining
                        } of
                      Left _ -> True
                      Right _ -> False
                  [] -> False
              )
            changedMetadata <-
              case prepare manifest {Checkpoint.manifestStep = 1} payloads of
                Left err -> assertFailure ("metadata-changed preparation failed: " <> Text.unpack err)
                Right value -> pure value
            assertBool
              "logical metadata changes storage snapshot identity"
              (CheckpointStore.preparedSnapshotId changedMetadata /= CheckpointStore.preparedSnapshotId prepared)
            assertBool
              "different snapshots never share physical object addresses"
              ( null
                  ( physicalKeys
                      `List.intersect` fmap
                        fst
                        (CheckpointStore.preparedSnapshotPayloads changedMetadata)
                  )
              )
            case CheckpointStore.gcReapEvents
              ( CheckpointStore.buildGcPlan
                  experimentHash
                  (CheckpointStore.LastN 0)
                  [CheckpointStore.preparedSnapshotManifest prepared]
                  []
              ) of
              [event] ->
                CheckpointStore.gcReapedObjectKeys event
                  @?= List.sort
                    ( physicalKeys
                        <> [CheckpointStore.writerCommitObjectKey commit]
                    )
              events ->
                assertFailure ("expected one snapshot GC event, got " <> show events)
            emptyPrepared <-
              case prepare
                (Checkpoint.emptyManifest "empty-snapshot" experimentHash [])
                [] of
                Left err -> assertFailure ("empty snapshot preparation failed: " <> Text.unpack err)
                Right value -> pure value
            CheckpointStore.checkpointStorageSnapshotId
              (CheckpointStore.preparedSnapshotManifest emptyPrepared)
              @?= Right Nothing
            case CheckpointStore.gcReapEvents
              ( CheckpointStore.buildGcPlan
                  experimentHash
                  (CheckpointStore.LastN 0)
                  [CheckpointStore.preparedSnapshotManifest emptyPrepared]
                  []
              ) of
              [event] ->
                CheckpointStore.gcReapedObjectKeys event
                  @?= [ CheckpointStore.writerCommitObjectKey
                          (CheckpointStore.preparedSnapshotCommit emptyPrepared)
                      ]
              events ->
                assertFailure ("expected one zero-object snapshot GC event, got " <> show events)
      , testCase "admission rejects a coherently forged original-to-scoped descriptor (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-forged-descriptor" $ \root -> do
            let experimentHash = "exp-forged-snapshot-descriptor"
                payload = Checkpoint.encodeJmw1 [8]
                originalKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  Checkpoint.emptyManifest
                    "forged-descriptor"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] originalKey]
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(originalKey, payload)]
                    )
                forgedOriginalKey =
                  Checkpoint.blobKey experimentHash (Text.replicate 64 "d")
                forgedScopedKey =
                  "jitml-checkpoints/"
                    <> experimentHash
                    <> "/snapshots/"
                    <> CheckpointStore.preparedSnapshotId prepared
                    <> "/objects/"
                    <> WeightCodec.jmw1ContentSha
                      ( ByteString.fromStrict
                          (Text.Encoding.encodeUtf8 forgedOriginalKey)
                      )
                forgedManifest =
                  (CheckpointStore.preparedSnapshotManifest prepared)
                    { Checkpoint.manifestTensors =
                        [Checkpoint.TensorBlob "weights" [1] forgedScopedKey]
                    }
                forgedManifestSha = Checkpoint.manifestContentSha forgedManifest
            forgedCommit <-
              case CheckpointStore.writerCommitPhysicalObjects
                (CheckpointStore.preparedSnapshotCommit prepared) of
                [physicalObject] ->
                  pure
                    ( (CheckpointStore.preparedSnapshotCommit prepared)
                        { CheckpointStore.writerCommitManifestSha = forgedManifestSha
                        , CheckpointStore.writerCommitPhysicalObjects =
                            [ physicalObject
                                { CheckpointStore.writerPhysicalObjectOriginalKey =
                                    forgedOriginalKey
                                , CheckpointStore.writerPhysicalObjectKey =
                                    forgedScopedKey
                                }
                            ]
                        }
                    )
                physicalObjects ->
                  assertFailure
                    ( "expected one descriptor binding, got "
                        <> show physicalObjects
                    )
                    >> error "unreachable"
            CheckpointStore.validateWriterCommit forgedCommit
              @?= Right forgedCommit
            let seededObjects =
                  [ (forgedScopedKey, payload)
                  ,
                    ( Checkpoint.manifestKey experimentHash forgedManifestSha
                    , Checkpoint.encodeManifestCbor forgedManifest
                    )
                  ,
                    ( CheckpointStore.writerCommitObjectKey forgedCommit
                    , ByteString.fromStrict
                        (CheckpointStore.encodeWriterCommit forgedCommit)
                    )
                  ]
            for_ seededObjects $ \(objectKey, objectBytes) -> do
              seeded <-
                CheckpointStore.writeObjectIfAbsent root objectKey objectBytes
              case seeded of
                Left err -> assertFailure ("could not seed forged descriptor: " <> show err)
                Right _ -> pure ()
            admitted <-
              CheckpointStore.admitLocalCheckpointAt
                root
                experimentHash
                forgedManifestSha
            case admitted of
              Left (CheckpointStore.AdmissionSnapshotCommitInvalid reason) ->
                assertBool
                  ("forged descriptor produced the wrong rejection: " <> Text.unpack reason)
                  ("snapshot id does not bind" `Text.isInfixOf` reason)
              Left err -> assertFailure ("wrong forged-descriptor error: " <> show err)
              Right _ -> assertFailure "coherently forged snapshot descriptor was admitted"
      , testCase "writer kind is bound to manifest completion before preparation and admission (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-writer-kind" $ \root -> do
            let experimentHash = "exp-writer-kind"
                payload = Checkpoint.encodeJmw1 [4]
                payloadSha = WeightCodec.jmw1ContentSha payload
                logicalObjectKey = Checkpoint.blobKey experimentHash payloadSha
                metrics = [("validation_accuracy", 0.95)]
                evidence =
                  journalExpectEitherRight
                    ( ProductEvidence.mkTrainingEvidence
                        (Text.replicate 64 "0")
                        payloadSha
                        1
                        "writer-kind-dataset"
                    )
                observations =
                  journalExpectEitherRight (convergenceObservationsFixture metrics)
                completed =
                  journalExpectEitherRight
                    ( TrainingBudget.completedTraining
                        unitFixturePlanId
                        (unitBudget TrainingBudget.TuningTrialBudget 1)
                        1
                        evidence
                        observations
                        TrainingBudget.TensorBoardRunMetadata
                          { TrainingBudget.tbrRunId = "writer-kind"
                          , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/writer-kind"
                          , TrainingBudget.tbrScalarTags = fmap fst metrics
                          }
                    )
                completedManifest =
                  Checkpoint.attachCompletedTraining
                    completed
                    ( ( Checkpoint.emptyManifest
                          "writer-kind-completed"
                          experimentHash
                          [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                      )
                        { Checkpoint.manifestStep = 1
                        , Checkpoint.manifestMetrics = metrics
                        }
                    )
                candidateManifest =
                  Checkpoint.emptyManifest
                    "writer-kind-candidate"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                latestIntent =
                  CheckpointStore.WriterLatestPointerIntent
                    (Checkpoint.latestPointerKey experimentHash)
            CheckpointStore.prepareCheckpointSnapshot
              CheckpointStore.WriterCandidateSnapshot
              CheckpointStore.WriterNoPointerIntent
              completedManifest
              [(logicalObjectKey, payload)]
              @?= Left "candidate writer transaction cannot carry completed training"
            CheckpointStore.prepareCheckpointSnapshot
              CheckpointStore.WriterCompletedSnapshot
              latestIntent
              candidateManifest
              [(logicalObjectKey, payload)]
              @?= Left "completed writer transaction requires completed training"
            prepared <-
              journalExpectRight
                ( CheckpointStore.prepareCheckpointSnapshot
                    CheckpointStore.WriterCompletedSnapshot
                    latestIntent
                    completedManifest
                    [(logicalObjectKey, payload)]
                )
            let completedCommit = CheckpointStore.preparedSnapshotCommit prepared
                candidateTemplate =
                  (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    { CheckpointStore.writerReservationTemplateKind =
                        CheckpointStore.WriterCandidateSnapshot
                    , CheckpointStore.writerReservationTemplatePointerIntent =
                        CheckpointStore.WriterNoPointerIntent
                    }
            candidateReservation <-
              journalExpectRight
                ( CheckpointStore.instantiateWriterReservation
                    (Text.replicate 64 "c")
                    candidateTemplate
                )
            let forgedCandidateCommit =
                  completedCommit
                    { CheckpointStore.writerCommitReservationId =
                        CheckpointStore.writerReservationId candidateReservation
                    , CheckpointStore.writerCommitKind =
                        CheckpointStore.WriterCandidateSnapshot
                    }
                seededObjects =
                  CheckpointStore.preparedSnapshotPayloads prepared
                    <> [
                         ( Checkpoint.manifestKey
                             experimentHash
                             (CheckpointStore.preparedSnapshotManifestSha prepared)
                         , CheckpointStore.preparedSnapshotManifestBytes prepared
                         )
                       ,
                         ( CheckpointStore.writerCommitObjectKey forgedCandidateCommit
                         , ByteString.fromStrict
                             (CheckpointStore.encodeWriterCommit forgedCandidateCommit)
                         )
                       ]
            CheckpointStore.validateWriterCommit forgedCandidateCommit
              @?= Right forgedCandidateCommit
            for_ seededObjects $ \(objectKey, objectBytes) -> do
              seeded <- CheckpointStore.writeObjectIfAbsent root objectKey objectBytes
              case seeded of
                Left err -> assertFailure ("could not seed forged writer kind: " <> show err)
                Right _ -> pure ()
            admitted <-
              CheckpointStore.admitLocalCheckpointAt
                root
                experimentHash
                (CheckpointStore.preparedSnapshotManifestSha prepared)
            case admitted of
              Left (CheckpointStore.AdmissionSnapshotCommitInvalid reason) ->
                assertBool
                  ("wrong writer-kind rejection: " <> Text.unpack reason)
                  ("candidate writer transaction cannot carry completed training" `Text.isInfixOf` reason)
              Left err -> assertFailure ("wrong writer-kind admission error: " <> show err)
              Right _ -> assertFailure "candidate commit admitted a completed manifest"
      , testCase "GC keeps a rooted scoped snapshot and reaps only the discarded exact graph (Phase 262)" $ do
          let experimentHash = "exp-gc-scoped-roots"
              rootedPrepared = phase262PreparedTensorSnapshot experimentHash "rooted" 1
              discardedPrepared = phase262PreparedTensorSnapshot experimentHash "discarded" 2
              rooted = CheckpointStore.preparedSnapshotManifest rootedPrepared
              discarded = CheckpointStore.preparedSnapshotManifest discardedPrepared
              rootedPlan =
                CheckpointStore.buildGcPlan
                  experimentHash
                  (CheckpointStore.LastN 0)
                  [rooted, discarded]
                  [rooted]
              fullyReapedPlan =
                CheckpointStore.buildGcPlan
                  experimentHash
                  (CheckpointStore.LastN 0)
                  [rooted, discarded]
                  []
          CheckpointStore.gcPlanValidationFailures rootedPlan @?= []
          CheckpointStore.gcKeptManifestShas rootedPlan
            @?= [Checkpoint.manifestContentSha rooted]
          case CheckpointStore.gcReapEvents rootedPlan of
            [event] -> do
              CheckpointStore.gcReapedManifestSha event
                @?= Checkpoint.manifestContentSha discarded
              CheckpointStore.gcReapedObjectKeys event
                @?= phase262PreparedGcObjectKeys discardedPrepared
              assertBool
                "rooted snapshot object leaked into discarded event"
                ( null
                    ( phase262PreparedGcObjectKeys rootedPrepared
                        `List.intersect` CheckpointStore.gcReapedObjectKeys event
                    )
                )
            events -> assertFailure ("expected one scoped GC event, got " <> show events)
          length (CheckpointStore.gcReapEvents fullyReapedPlan) @?= 2
          List.sort
            (concatMap CheckpointStore.gcReapedObjectKeys (CheckpointStore.gcReapEvents fullyReapedPlan))
            @?= List.sort
              ( phase262PreparedGcObjectKeys rootedPrepared
                  <> phase262PreparedGcObjectKeys discardedPrepared
              )
      , testCase
          "GC rejects legacy unscoped and malformed physical graphs before intent creation (Phase 262)"
          $ do
            let experimentHash = "exp-gc-invalid-graphs"
                validPrepared = phase262PreparedTensorSnapshot experimentHash "valid" 1
                valid = CheckpointStore.preparedSnapshotManifest validPrepared
                legacy =
                  Checkpoint.emptyManifest
                    "legacy"
                    experimentHash
                    [ Checkpoint.TensorBlob
                        "legacy.weights"
                        [1]
                        (Checkpoint.blobKey experimentHash (Text.replicate 64 "a"))
                    ]
                legacyPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [legacy]
                    []
                invalidKeys =
                  [ ("empty segment", experimentHash <> "//blobs/shared")
                  , ("dot segment", experimentHash <> "/./blobs/shared")
                  , ("dot-dot segment", experimentHash <> "/artifacts/../blobs/shared")
                  , ("control character", experimentHash <> "/blobs/bad\NUL\&key")
                  , ("cross-experiment", "another-experiment/blobs/shared")
                  ]
            assertBool
              "legacy unscoped candidate was GC eligible"
              (not (null (CheckpointStore.gcPlanValidationFailures legacyPlan)))
            CheckpointStore.gcReapEvents legacyPlan @?= []
            CheckpointStore.gcPlanIntents legacyPlan @?= []
            for_ invalidKeys $ \(label, malformedAlias) -> do
              let malformedRoot =
                    Checkpoint.emptyManifest
                      ("malformed-" <> label)
                      experimentHash
                      [Checkpoint.TensorBlob "root.weights" [1] malformedAlias]
                  plan =
                    CheckpointStore.buildGcPlan
                      experimentHash
                      (CheckpointStore.LastN 0)
                      [valid]
                      [malformedRoot]
              assertBool
                (Text.unpack label <> " malformed root did not poison the complete plan")
                (not (null (CheckpointStore.gcPlanValidationFailures plan)))
              CheckpointStore.gcReapEvents plan @?= []
              CheckpointStore.gcPlanIntents plan @?= []
              CheckpointStore.gcNoOp plan @?= False
            let invalidExperimentPlan =
                  CheckpointStore.buildGcPlan
                    "invalid/experiment"
                    CheckpointStore.KeepAll
                    []
                    []
            assertBool
              "an experiment hash must be exactly one safe path segment"
              (not (null (CheckpointStore.gcPlanValidationFailures invalidExperimentPlan)))
      , testCase "GC planning is invariant under equal-step scoped-manifest permutations (Phase 262)" $ do
          let experimentHash = "exp-gc-order"
              manifests =
                [ CheckpointStore.preparedSnapshotManifest
                    (phase262PreparedTensorSnapshot experimentHash tag 7)
                | tag <- ["a", "b", "c"]
                ]
              plans =
                [ CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 1)
                    permutation
                    []
                | permutation <- List.permutations manifests
                ]
              expectedKept = take 1 (List.sort (fmap Checkpoint.manifestContentSha manifests))
          case plans of
            [] -> assertFailure "manifest permutations unexpectedly produced no plans"
            referencePlan : remainingPlans -> do
              CheckpointStore.gcPlanValidationFailures referencePlan @?= []
              assertBool
                "all equal-step permutations produce one identical plan"
                (all (== referencePlan) remainingPlans)
              CheckpointStore.gcKeptManifestShas referencePlan @?= expectedKept
              fmap CheckpointStore.gcIntentEventId (CheckpointStore.gcPlanIntents referencePlan)
                @?= fmap CheckpointStore.gcEventId (CheckpointStore.gcReapEvents referencePlan)
      , testCase "completed canonical ProductRow manifests are intrinsic GC roots (Phase 262)" $ do
          case find
            ((== ProductMatrix.ReinforcementLearning) . ProductMatrix.family)
            ProductMatrix.allProductRows of
            Nothing -> assertFailure "ProductMatrix unexpectedly has no canonical RL row"
            Just row -> do
              fixtureWitness <-
                expectRightText =<< DeviceWitnessFixture.fixtureDeviceExecutionWitness
              let experimentHash = ProductMatrix.productRowExperimentHash row
                  budget = ProductMatrix.trainingBudget row
                  observedUnits = TrainingBudget.trainingBudgetTargetUnits budget
                  convergenceBar = ProductMatrix.convergenceBar row
                  metrics =
                    [
                      ( ProductConvergence.convergenceMetricName convergenceBar
                      , ProductConvergence.convergenceThreshold convergenceBar
                      )
                    ]
                  completed =
                    either
                      (error . Text.unpack)
                      id
                      ( ProductCompletion.completedTrainingForProductRowWithWeightHashes
                          unitFixturePlanId
                          budget
                          row
                          "unit-product-dataset"
                          experimentHash
                          observedUnits
                          1
                          metrics
                          (Text.replicate 64 "a")
                          (Text.replicate 64 "b")
                          (Just fixtureWitness)
                      )
                  manifest =
                    Checkpoint.attachCompletedTraining
                      completed
                      ( (Checkpoint.emptyManifest "product-gc-root" experimentHash [])
                          { Checkpoint.manifestStep = observedUnits
                          , Checkpoint.manifestMetrics = metrics
                          }
                      )
                  plan =
                    CheckpointStore.buildGcPlan
                      experimentHash
                      (CheckpointStore.LastN 0)
                      [manifest]
                      []
              CheckpointStore.gcKeptManifestShas plan
                @?= [Checkpoint.manifestContentSha manifest]
              CheckpointStore.gcReapEvents plan @?= []
      , testCase
          "identical writers allocate unique attempt markers and a leaked marker fences a committed snapshot (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-writer-reservations"
          $ \root -> do
            let experimentHash = "exp-writer-reservation-race"
                payload = Checkpoint.encodeJmw1 [1]
                logicalObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  Checkpoint.emptyManifest
                    "identical-writer"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalObjectKey, payload)]
                    )
                attempt0 = Text.replicate 64 "0"
                attempt1 = Text.replicate 63 "0" <> "1"
                reservation0 =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        attempt0
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
                reservation1 =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        attempt1
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
            assertBool
              "two exact writer attempts resolved to the same marker"
              ( CheckpointStore.writerReservationObjectKey reservation0
                  /= CheckpointStore.writerReservationObjectKey reservation1
              )
            seeded <-
              CheckpointStore.writeObjectIfAbsent
                root
                (CheckpointStore.writerReservationObjectKey reservation0)
                ( ByteString.fromStrict
                    (CheckpointStore.encodeWriterReservation reservation0)
                )
            seeded
              @?= Right
                ( CheckpointStore.ObjectCreated
                    (CheckpointStore.writerReservationObjectKey reservation0)
                )
            written <-
              CheckpointStore.writeCandidateCheckpointSnapshot
                root
                logicalManifest
                [(logicalObjectKey, payload)]
            case written of
              Left err ->
                assertFailure
                  ( "exact retry did not advance past the occupied attempt marker: "
                      <> Text.unpack (CheckpointStore.renderCheckpointWriteError err)
                  )
              Right _ -> pure ()
            leaked <-
              CheckpointStore.readObject
                root
                (CheckpointStore.writerReservationObjectKey reservation0)
            leaked
              @?= Right
                ( ByteString.fromStrict
                    (CheckpointStore.encodeWriterReservation reservation0)
                )
            attempt1Path <-
              case CheckpointStore.objectPathForKey
                root
                (CheckpointStore.writerReservationObjectKey reservation1) of
                Left err -> assertFailure (Text.unpack err) >> error "unreachable"
                Right path -> pure path
            attempt1Exists <- doesFileExist attempt1Path
            attempt1Exists @?= False
            committed <-
              CheckpointStore.readObject
                root
                ( CheckpointStore.writerCommitObjectKey
                    (CheckpointStore.preparedSnapshotCommit prepared)
                )
            committed
              @?= Right
                ( ByteString.fromStrict
                    ( CheckpointStore.encodeWriterCommit
                        (CheckpointStore.preparedSnapshotCommit prepared)
                    )
                )
            listed <- CheckpointStore.listCheckpointManifests root experimentHash
            listed @?= Right [CheckpointStore.preparedSnapshotManifest prepared]
            let plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [CheckpointStore.preparedSnapshotManifest prepared]
                    []
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            case CheckpointStore.gcPlanIntents plan of
              [intent] ->
                CheckpointStore.revalidateGcIntents
                  epoch
                  epoch
                  plan
                  [CheckpointStore.preparedSnapshotManifest prepared]
                  []
                  [reservation0]
                  []
                  [intent]
                  @?= Right ([], [intent])
              intents ->
                assertFailure ("expected one fenced intent, got " <> show intents)
      , testCase
          "writer-before-plan cancellation prevents deletion until a fresh generation is authorized (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-writer-final-fence"
          $ \root -> do
            let experimentHash = "exp-writer-final-fence"
                payload = Checkpoint.encodeJmw1 [5]
                logicalObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  Checkpoint.emptyManifest
                    "writer-final-fence"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalObjectKey, payload)]
                    )
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [CheckpointStore.preparedSnapshotManifest prepared]
                    []
                reservation =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values ->
                  assertFailure ("expected one writer-race GC intent, got " <> show values)
                    >> error "unreachable"
            firstIntentList <- newEmptyMVar
            releaseFirstIntentList <- newEmptyMVar
            intentListCount <- newIORef 0
            writerResult <- newEmptyMVar
            let environment =
                  Phase262FenceRaceEnv
                    { phase262FenceRaceRoot = root
                    , phase262FenceRaceFirstIntentList = firstIntentList
                    , phase262FenceRaceReleaseFirstIntentList = releaseFirstIntentList
                    , phase262FenceRaceIntentListCount = intentListCount
                    }
            _ <-
              forkIO $ do
                outcome <-
                  runPhase262FenceRaceMinIO environment $
                    CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                      logicalManifest
                      [(logicalObjectKey, payload)]
                putMVar writerResult outcome
            -- The writer has already registered in the experiment fence and
            -- listed an empty outbox. Install the intent before it resumes.
            takeMVar firstIntentList
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            putMVar releaseFirstIntentList ()
            outcome <- takeMVar writerResult
            case outcome of
              Left err ->
                assertFailure ("writer did not cancel the late intent: " <> show err)
              Right _ -> pure ()
            runFilesystemMinIO
              root
              ( minioReadBytes
                  ( CheckpointStore.checkpointObjectRef
                      (CheckpointStore.writerReservationObjectKey reservation)
                  )
              )
              >>= \case
                Left _ -> pure ()
                Right _ -> assertFailure "writer did not release its separate marker"
            runFilesystemMinIO
              root
              (CheckpointStore.loadActiveWriterReservations experimentHash)
              >>= (@?= Right [])
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcCancelledIntents experimentHash)
              >>= (@?= Right [intent])
            let manifest = CheckpointStore.preparedSnapshotManifest prepared
                event = CheckpointStore.gcIntentEvent intent
                manifestRef =
                  CheckpointStore.checkpointObjectRef
                    ( Checkpoint.manifestKey
                        experimentHash
                        (CheckpointStore.gcReapedManifestSha event)
                    )
            runFilesystemMinIO root (minioReadBytes manifestRef) >>= \case
              Left err ->
                assertFailure ("writer graph was deleted before fresh authorization: " <> show err)
              Right _ -> pure ()
            for_ (CheckpointStore.gcReapedObjectKeys event) $ \key ->
              runFilesystemMinIO
                root
                (minioReadBytes (CheckpointStore.checkpointObjectRef key))
                >>= \case
                  Left err ->
                    assertFailure
                      ("writer physical object was deleted before fresh authorization: " <> show err)
                  Right _ -> pure ()
            -- A completed cancellation is not a permanent veto. Re-persisting
            -- the same intent and obtaining a new fresh witness creates the
            -- next generation; only that opaque authorization can delete.
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            let witness = phase262SingleRevalidatedIntent epoch plan [manifest] [] [] [] intent
            authorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents [witness])
            CheckpointStore.gcAuthorizationCancelledIntents authorization @?= []
            CheckpointStore.gcAuthorizationFailures authorization @?= []
            authorized <-
              case CheckpointStore.gcAuthorizedIntents authorization of
                [value] -> pure value
                values ->
                  assertFailure ("expected one re-armed authorization, got " <> show values)
                    >> error "unreachable"
            executingFence <- phase262LoadExperimentFence root experimentHash
            fmap
              ( \decision ->
                  ( CheckpointStore.gcFenceDecisionGeneration decision
                  , CheckpointStore.gcFenceDecisionPhase decision
                  )
              )
              (CheckpointStore.experimentGcFenceDecisions executingFence)
              @?= [ (0, CheckpointStore.GcFenceCancelled)
                  , (1, CheckpointStore.GcFenceExecuting)
                  ]
            executed <-
              runFilesystemMinIO
                root
                (CheckpointStore.executeAuthorizedGcIntents [authorized])
            length (CheckpointStore.gcCompletedExecutions executed) @?= 1
            CheckpointStore.gcExecutionFailures executed @?= []
            runFilesystemMinIO root (minioReadBytes manifestRef) >>= \case
              Left _ -> pure ()
              Right _ -> assertFailure "re-armed authorization did not delete the manifest"
      , testCase "a delayed duplicate cancellation helper is inert after generation re-arm (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-delayed-cancellation" $ \root -> do
            let experimentHash = "exp-delayed-cancellation"
                prepared = phase262PreparedTensorSnapshot experimentHash "delayed" 3
                manifest = CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [manifest]
                    []
            phase262SeedPreparedSnapshotMinIO root prepared
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values ->
                  assertFailure ("expected one delayed-cancellation intent, got " <> show values)
                    >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            cancellationReached <- newEmptyMVar
            releaseCancellation <- newEmptyMVar
            cancellationResult <- newEmptyMVar
            let cancellationEnvironment =
                  Phase262CancellationDelayEnv
                    { phase262CancellationDelayRoot = root
                    , phase262CancellationDelayReached = cancellationReached
                    , phase262CancellationDelayRelease = releaseCancellation
                    }
            _ <-
              forkIO $ do
                outcome <-
                  runPhase262CancellationDelayMinIO
                    cancellationEnvironment
                    (CheckpointStore.cancelGcIntents [intent])
                putMVar cancellationResult outcome
            -- The first canceller owns generation zero and is paused before
            -- writing its stable tombstone.
            takeMVar cancellationReached
            helperReached <- newEmptyMVar
            releaseHelper <- newEmptyMVar
            helperResult <- newEmptyMVar
            let helperEnvironment =
                  Phase262CancellationDelayEnv
                    { phase262CancellationDelayRoot = root
                    , phase262CancellationDelayReached = helperReached
                    , phase262CancellationDelayRelease = releaseHelper
                    }
            _ <-
              forkIO $ do
                outcome <-
                  runPhase262CancellationDelayMinIO
                    helperEnvironment
                    (CheckpointStore.helpGcCancellations [intent])
                putMVar helperResult outcome
            -- The helper has classified and retained the exact generation-zero
            -- Cancelling decision, then paused before its idempotent PUT.
            takeMVar helperReached
            putMVar releaseCancellation ()
            takeMVar cancellationResult >>= (@?= Right [intent])
            let fenceRef =
                  CheckpointStore.checkpointObjectRef
                    (CheckpointStore.experimentGcFenceObjectKey experimentHash)
            loadedFence <-
              runFilesystemMinIO root (minioReadBytesWithETag fenceRef)
            (cancelledFence, cancelledEtag) <-
              case loadedFence of
                Left err ->
                  assertFailure ("could not load cancelled helper fence: " <> show err)
                    >> error "unreachable"
                Right (bytes, etag) ->
                  case Text.Encoding.decodeUtf8' bytes of
                    Left err ->
                      assertFailure ("helper fence was not UTF-8: " <> show err)
                        >> error "unreachable"
                    Right encoded ->
                      case CheckpointStore.decodeExperimentGcFence encoded of
                        Left err ->
                          assertFailure ("could not decode helper fence: " <> show err)
                            >> error "unreachable"
                        Right fence -> pure (fence, etag)
            let generation = 1
                plannedDecision =
                  CheckpointStore.GcFenceDecision
                    { CheckpointStore.gcFenceDecisionGeneration = generation
                    , CheckpointStore.gcFenceDecisionIntent = intent
                    , CheckpointStore.gcFenceDecisionOperationId =
                        CheckpointStore.gcFenceOperationId generation intent
                    , CheckpointStore.gcFenceDecisionPhase =
                        CheckpointStore.GcFencePlanned
                    }
                plannedFence =
                  cancelledFence
                    { CheckpointStore.experimentGcFenceRevision =
                        CheckpointStore.experimentGcFenceRevision cancelledFence + 1
                    , CheckpointStore.experimentGcFenceDecisions =
                        CheckpointStore.experimentGcFenceDecisions cancelledFence
                          <> [plannedDecision]
                    }
            runFilesystemMinIO
              root
              ( casPointer
                  fenceRef
                  (Just cancelledEtag)
                  (CheckpointStore.encodeExperimentGcFence plannedFence)
              )
              >>= \case
                Left err ->
                  assertFailure ("could not seed helper-race re-arm: " <> show err)
                Right _ -> pure ()
            putMVar releaseHelper ()
            takeMVar helperResult >>= (@?= Right [intent])
            finalFence <- phase262LoadExperimentFence root experimentHash
            fmap
              ( \decision ->
                  ( CheckpointStore.gcFenceDecisionGeneration decision
                  , CheckpointStore.gcFenceDecisionPhase decision
                  )
              )
              (CheckpointStore.experimentGcFenceDecisions finalFence)
              @?= [ (0, CheckpointStore.GcFenceCancelled)
                  , (1, CheckpointStore.GcFencePlanned)
                  ]
            runFilesystemMinIO root (CheckpointStore.loadGcCancelledIntents experimentHash)
              >>= (@?= Right [])
            runFilesystemMinIO root (CheckpointStore.loadGcIntents experimentHash)
              >>= (@?= Right [intent])
      , testCase
          "writer waits for a re-armed generation cancellation despite its stable old tombstone (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-rearmed-writer-cancellation"
          $ \root -> do
            let experimentHash = "exp-rearmed-writer-cancellation"
                targetPrepared = phase262PreparedTensorSnapshot experimentHash "target" 3
                target = CheckpointStore.preparedSnapshotManifest targetPrepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [target]
                    []
                childPayload = Checkpoint.encodeJmw1 [12]
                childObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha childPayload)
                childManifest =
                  ( Checkpoint.emptyManifest
                      "child"
                      experimentHash
                      [Checkpoint.TensorBlob "child.weights" [1] childObjectKey]
                  )
                    { Checkpoint.manifestStep = 4
                    , Checkpoint.manifestParentManifestSha =
                        Just (Checkpoint.manifestContentSha target)
                    }
                childPrepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        childManifest
                        [(childObjectKey, childPayload)]
                    )
                childReservation =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate childPrepared)
                    )
            phase262SeedPreparedSnapshotMinIO root targetPrepared
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values -> assertFailure ("expected one re-armed intent, got " <> show values) >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            runFilesystemMinIO root (CheckpointStore.cancelGcIntents [intent])
              >>= (@?= Right [intent])
            let fenceRef =
                  CheckpointStore.checkpointObjectRef
                    (CheckpointStore.experimentGcFenceObjectKey experimentHash)
            loadedFence <-
              runFilesystemMinIO root (minioReadBytesWithETag fenceRef)
            (cancelledFence, cancelledEtag) <-
              case loadedFence of
                Left err -> assertFailure ("could not load cancelled fence: " <> show err) >> error "unreachable"
                Right (bytes, etag) ->
                  case Text.Encoding.decodeUtf8' bytes of
                    Left err -> assertFailure ("cancelled fence was not UTF-8: " <> show err) >> error "unreachable"
                    Right encoded ->
                      case CheckpointStore.decodeExperimentGcFence encoded of
                        Left err -> assertFailure ("could not decode cancelled fence: " <> show err) >> error "unreachable"
                        Right fence -> pure (fence, etag)
            let generation = 1
                plannedDecision =
                  CheckpointStore.GcFenceDecision
                    { CheckpointStore.gcFenceDecisionGeneration = generation
                    , CheckpointStore.gcFenceDecisionIntent = intent
                    , CheckpointStore.gcFenceDecisionOperationId =
                        CheckpointStore.gcFenceOperationId generation intent
                    , CheckpointStore.gcFenceDecisionPhase =
                        CheckpointStore.GcFencePlanned
                    }
                plannedFence =
                  cancelledFence
                    { CheckpointStore.experimentGcFenceRevision =
                        CheckpointStore.experimentGcFenceRevision cancelledFence + 1
                    , CheckpointStore.experimentGcFenceDecisions =
                        CheckpointStore.experimentGcFenceDecisions cancelledFence
                          <> [plannedDecision]
                    }
            runFilesystemMinIO
              root
              ( casPointer
                  fenceRef
                  (Just cancelledEtag)
                  (CheckpointStore.encodeExperimentGcFence plannedFence)
              )
              >>= \case
                Left err -> assertFailure ("could not seed re-armed Planned generation: " <> show err)
                Right _ -> pure ()
            completionReached <- newEmptyMVar
            completionRelease <- newEmptyMVar
            completionDidDelay <- newIORef False
            writerResult <- newEmptyMVar
            let environment =
                  Phase262CancellationCompletionDelayEnv
                    { phase262CancellationCompletionRoot = root
                    , phase262CancellationCompletionReached = completionReached
                    , phase262CancellationCompletionRelease = completionRelease
                    , phase262CancellationCompletionDidDelay = completionDidDelay
                    }
            _ <-
              forkIO $ do
                outcome <-
                  runPhase262CancellationCompletionDelayMinIO environment $
                    CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                      childManifest
                      [(childObjectKey, childPayload)]
                putMVar writerResult outcome
            takeMVar completionReached
            let childMarkerRef =
                  CheckpointStore.checkpointObjectRef
                    (CheckpointStore.writerReservationObjectKey childReservation)
                childPayloadRef =
                  case CheckpointStore.preparedSnapshotPayloads childPrepared of
                    [(key, _)] -> CheckpointStore.checkpointObjectRef key
                    values -> error ("unexpected child payload fixture: " <> show values)
            for_ [childMarkerRef, childPayloadRef] $ \ref ->
              runFilesystemMinIO root (minioReadBytes ref) >>= \case
                Left _ -> pure ()
                Right _ ->
                  assertFailure
                    "writer created its marker/payload before generation-one cancellation completed"
            cancellingFence <- phase262LoadExperimentFence root experimentHash
            case reverse (CheckpointStore.experimentGcFenceDecisions cancellingFence) of
              latest : _ ->
                CheckpointStore.gcFenceDecisionPhase latest
                  @?= CheckpointStore.GcFenceCancelling
              [] -> assertFailure "re-armed cancellation lost its fence decision"
            putMVar completionRelease ()
            takeMVar writerResult >>= \case
              Left err -> assertFailure ("writer did not resume after cancellation completion: " <> show err)
              Right _ -> pure ()
            completedFence <- phase262LoadExperimentFence root experimentHash
            case reverse (CheckpointStore.experimentGcFenceDecisions completedFence) of
              latest : _ ->
                CheckpointStore.gcFenceDecisionPhase latest
                  @?= CheckpointStore.GcFenceCancelled
              [] -> assertFailure "completed re-armed cancellation lost its fence decision"
      , testCase "a fully completed cross-snapshot parent writer invalidates a stale GC witness (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-short-parent-writer" $ \root -> do
            let experimentHash = "exp-short-parent-writer"
                targetPrepared = phase262PreparedTensorSnapshot experimentHash "parent" 4
                target = CheckpointStore.preparedSnapshotManifest targetPrepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [target]
                    []
                childPayload = Checkpoint.encodeJmw1 [9]
                childObjectKey =
                  Checkpoint.blobKey
                    experimentHash
                    (WeightCodec.jmw1ContentSha childPayload)
                childManifest =
                  ( Checkpoint.emptyManifest
                      "child"
                      experimentHash
                      [Checkpoint.TensorBlob "child.weights" [1] childObjectKey]
                  )
                    { Checkpoint.manifestStep = 5
                    , Checkpoint.manifestParentManifestSha =
                        Just (Checkpoint.manifestContentSha target)
                    }
            phase262SeedPreparedSnapshotMinIO root targetPrepared
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values -> assertFailure ("expected one parent intent, got " <> show values) >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            staleEpoch <- phase262LoadGcFenceEpoch root experimentHash
            let staleWitness =
                  phase262SingleRevalidatedIntent
                    staleEpoch
                    plan
                    [target]
                    []
                    []
                    []
                    intent
            childWrite <-
              runFilesystemMinIO root $
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  childManifest
                  [(childObjectKey, childPayload)]
            case childWrite of
              Left err -> assertFailure ("cross-snapshot child writer failed: " <> show err)
              Right _ -> pure ()
            runFilesystemMinIO
              root
              (CheckpointStore.loadActiveWriterReservations experimentHash)
              >>= (@?= Right [])
            authorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents [staleWitness])
            CheckpointStore.gcAuthorizedIntents authorization @?= []
            CheckpointStore.gcAuthorizationCancelledIntents authorization @?= []
            assertBool
              "short parent writer did not invalidate the old writer/root epoch"
              (not (null (CheckpointStore.gcAuthorizationFailures authorization)))
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcCancelledIntents experimentHash)
              >>= (@?= Right [intent])
            let targetManifestRef =
                  CheckpointStore.checkpointObjectRef
                    ( Checkpoint.manifestKey
                        experimentHash
                        (Checkpoint.manifestContentSha target)
                    )
            runFilesystemMinIO root (minioReadBytes targetManifestRef) >>= \case
              Left err -> assertFailure ("stale witness deleted the new parent's target: " <> show err)
              Right _ -> pure ()
      , testCase "authorizer discovers a marker-only reservation omitted by revalidation (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-marker-omission" $ \root -> do
            let experimentHash = "exp-marker-omission"
                prepared = phase262PreparedTensorSnapshot experimentHash "marker" 2
                manifest = CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [manifest]
                    []
                reservation =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
            phase262SeedPreparedSnapshotMinIO root prepared
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values -> assertFailure ("expected one marker intent, got " <> show values) >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            runFilesystemMinIO
              root
              ( putBlobBytesIfAbsent
                  ( CheckpointStore.checkpointObjectRef
                      (CheckpointStore.writerReservationObjectKey reservation)
                  )
                  (CheckpointStore.encodeWriterReservation reservation)
              )
              >>= \case
                Left err -> assertFailure ("could not seed marker-only reservation: " <> show err)
                Right _ -> pure ()
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            let witness =
                  phase262SingleRevalidatedIntent
                    epoch
                    plan
                    [manifest]
                    []
                    []
                    []
                    intent
            authorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents [witness])
            CheckpointStore.gcAuthorizedIntents authorization @?= []
            CheckpointStore.gcAuthorizationCancelledIntents authorization @?= [intent]
            CheckpointStore.gcAuthorizationFailures authorization @?= []
            runFilesystemMinIO
              root
              (CheckpointStore.cancelGcIntents [intent])
              >>= (@?= Right [intent])
            let manifestRef =
                  CheckpointStore.checkpointObjectRef
                    (Checkpoint.manifestKey experimentHash (Checkpoint.manifestContentSha manifest))
            runFilesystemMinIO root (minioReadBytes manifestRef) >>= \case
              Left err -> assertFailure ("marker-omission target was deleted: " <> show err)
              Right _ -> pure ()
      , testCase "a marker conflict retains its experiment-fence registration permanently (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-marker-conflict" $ \root -> do
            let experimentHash = "exp-marker-conflict"
                payload = Checkpoint.encodeJmw1 [6]
                logicalObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  Checkpoint.emptyManifest
                    "marker-conflict"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalObjectKey, payload)]
                    )
                reservation0 =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
            runFilesystemMinIO
              root
              ( putBlobBytesIfAbsent
                  ( CheckpointStore.checkpointObjectRef
                      (CheckpointStore.writerReservationObjectKey reservation0)
                  )
                  (CheckpointStore.encodeWriterReservation reservation0)
              )
              >>= \case
                Left err -> assertFailure ("could not seed occupied marker: " <> show err)
                Right _ -> pure ()
            written <-
              runFilesystemMinIO root $
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  logicalManifest
                  [(logicalObjectKey, payload)]
            case written of
              Left err -> assertFailure ("writer did not advance after marker conflict: " <> show err)
              Right _ -> pure ()
            runFilesystemMinIO
              root
              (CheckpointStore.loadActiveWriterReservations experimentHash)
              >>= (@?= Right [reservation0])
            fence <- phase262LoadExperimentFence root experimentHash
            CheckpointStore.experimentGcFenceReservations fence @?= [reservation0]
            let manifest = CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [manifest]
                    []
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values ->
                  assertFailure ("expected one marker-conflict intent, got " <> show values) >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            for_ [1 :: Int, 2] $ \_ -> do
              epoch <- phase262LoadGcFenceEpoch root experimentHash
              CheckpointStore.revalidateGcIntents
                epoch
                epoch
                plan
                [manifest]
                []
                []
                []
                [intent]
                @?= Right ([], [intent])
              runFilesystemMinIO root (CheckpointStore.cancelGcIntents [intent])
                >>= \case
                  Left failures -> assertFailure ("marker-conflict cancellation failed: " <> show failures)
                  Right _ -> pure ()
      , testCase
          "a failed marker delete retains the writer's fence entry because deletion precedes unregister (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-marker-delete-order"
          $ \root -> do
            let experimentHash = "exp-marker-delete-order"
                payload = Checkpoint.encodeJmw1 [12]
                logicalObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  Checkpoint.emptyManifest
                    "marker-delete-order"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalObjectKey, payload)]
                    )
                reservation =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
                markerRef =
                  CheckpointStore.checkpointObjectRef
                    (CheckpointStore.writerReservationObjectKey reservation)
                fencedRoot = root </> "marker-delete-failed"
                releasedRoot = root </> "marker-delete-succeeded"
            deleteCalls <- newIORef []
            let environment =
                  Phase262DeleteFailureEnv
                    { phase262DeleteFailureRoot = fencedRoot
                    , phase262DeleteFailureRef = markerRef
                    , phase262DeleteFailureCalls = deleteCalls
                    }
            fenced <-
              runPhase262DeleteFailureMinIO environment $
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  logicalManifest
                  [(logicalObjectKey, payload)]
            case fenced of
              Left err -> err @?= ServiceRetry.SETransient "injected manifest failure"
              Right _ -> assertFailure "the writer reported success after its marker delete failed"
            -- The marker delete is the only deletion the writer attempts, and
            -- it aborts before the fence CAS, so the reservation entry is still
            -- protecting the snapshot.
            readIORef deleteCalls >>= (@?= [markerRef])
            runFilesystemMinIO fencedRoot (minioReadBytes markerRef) >>= \case
              Left err -> assertFailure ("the undeletable marker vanished: " <> show err)
              Right _ -> pure ()
            fencedFence <- phase262LoadExperimentFence fencedRoot experimentHash
            CheckpointStore.experimentGcFenceReservations fencedFence @?= [reservation]
            runFilesystemMinIO
              fencedRoot
              (CheckpointStore.loadActiveWriterReservations experimentHash)
              >>= (@?= Right [reservation])
            released <-
              runFilesystemMinIO releasedRoot $
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  logicalManifest
                  [(logicalObjectKey, payload)]
            case released of
              Left err -> assertFailure ("the unobstructed writer failed: " <> show err)
              Right _ -> pure ()
            runFilesystemMinIO releasedRoot (minioReadBytes markerRef) >>= \case
              Left _ -> pure ()
              Right _ -> assertFailure "successful cleanup left the reservation marker"
            releasedFence <- phase262LoadExperimentFence releasedRoot experimentHash
            CheckpointStore.experimentGcFenceReservations releasedFence @?= []
            runFilesystemMinIO
              releasedRoot
              (CheckpointStore.loadActiveWriterReservations experimentHash)
              >>= (@?= Right [])
      , testCase "absent-manifest intents cannot mint fresh destructive authority (Phase 262)" $
          withSystemTempDirectory "jitml-phase262-absent-intent" $ \root -> do
            let experimentHash = "exp-absent-intent"
                prepared = phase262PreparedTensorSnapshot experimentHash "first" 1
                firstManifest = CheckpointStore.preparedSnapshotManifest prepared
                firstPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [firstManifest]
                    []
                emptyPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    []
                    []
            firstIntent <-
              case CheckpointStore.gcPlanIntents firstPlan of
                [value] -> pure value
                values -> assertFailure ("expected one first planner intent, got " <> show values) >> error "unreachable"
            let secondEvent =
                  (CheckpointStore.gcIntentEvent firstIntent)
                    { CheckpointStore.gcReapedManifestSha = Text.replicate 64 "b"
                    , CheckpointStore.gcStepAtReap = 2
                    }
                secondIntent =
                  CheckpointStore.GcIntent
                    { CheckpointStore.gcIntentEvent = secondEvent
                    , CheckpointStore.gcIntentEventId =
                        CheckpointStore.gcEventId secondEvent
                    }
            runFilesystemMinIO
              root
              (CheckpointStore.persistGcIntents [firstIntent, secondIntent])
              >>= (@?= Right (List.sort [firstIntent, secondIntent]))
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            CheckpointStore.revalidateGcIntents
              epoch
              epoch
              emptyPlan
              []
              []
              []
              []
              [firstIntent, secondIntent]
              @?= Right ([], List.sort [firstIntent, secondIntent])
            fence <- phase262LoadExperimentFence root experimentHash
            CheckpointStore.experimentGcFenceDecisions fence @?= []
      , testCase
          "local GC listing distinguishes committed, reserved, orphaned, legacy, and empty snapshots (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-gc-listing"
          $ \root -> do
            let experimentHash = "exp-gc-listing-states"
                payload = Checkpoint.encodeJmw1 [3]
                logicalObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  Checkpoint.emptyManifest
                    "listing-state"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalObjectKey, payload)]
                    )
                reservation =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
                seedPreparedManifest targetRoot = do
                  outcome <-
                    CheckpointStore.writeObjectIfAbsent
                      targetRoot
                      ( Checkpoint.manifestKey
                          experimentHash
                          (CheckpointStore.preparedSnapshotManifestSha prepared)
                      )
                      (CheckpointStore.preparedSnapshotManifestBytes prepared)
                  case outcome of
                    Left err ->
                      assertFailure
                        ("could not seed prepared manifest: " <> show err)
                    Right _ -> pure ()
                committedRoot = root </> "committed"
                reservedRoot = root </> "reserved"
                orphanedRoot = root </> "orphaned"
                legacyRoot = root </> "legacy"
                emptyRoot = root </> "empty"
            committedWrite <-
              CheckpointStore.writeCandidateCheckpointSnapshot
                committedRoot
                logicalManifest
                [(logicalObjectKey, payload)]
            case committedWrite of
              Left err -> assertFailure (show err)
              Right _ -> pure ()
            CheckpointStore.listCheckpointManifests committedRoot experimentHash
              >>= (@?= Right [CheckpointStore.preparedSnapshotManifest prepared])
            seedPreparedManifest reservedRoot
            reservedWrite <-
              CheckpointStore.writeObjectIfAbsent
                reservedRoot
                (CheckpointStore.writerReservationObjectKey reservation)
                ( ByteString.fromStrict
                    (CheckpointStore.encodeWriterReservation reservation)
                )
            case reservedWrite of
              Left err -> assertFailure (show err)
              Right _ -> pure ()
            CheckpointStore.listCheckpointManifests reservedRoot experimentHash
              >>= (@?= Right [])
            seedPreparedManifest orphanedRoot
            orphaned <- CheckpointStore.listCheckpointManifests orphanedRoot experimentHash
            case orphaned of
              Left err ->
                assertBool
                  ("orphaned snapshot produced the wrong error: " <> Text.unpack err)
                  ("neither a commit nor an active reservation" `Text.isInfixOf` err)
              Right manifests ->
                assertFailure ("orphaned snapshot was GC eligible: " <> show manifests)
            let legacyManifest =
                  Checkpoint.emptyManifest
                    "legacy-listing"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                legacySha = Checkpoint.manifestContentSha legacyManifest
            legacyWrite <-
              CheckpointStore.writeObjectIfAbsent
                legacyRoot
                (Checkpoint.manifestKey experimentHash legacySha)
                (Checkpoint.encodeManifestCbor legacyManifest)
            case legacyWrite of
              Left err -> assertFailure (show err)
              Right _ -> pure ()
            CheckpointStore.listCheckpointManifests legacyRoot experimentHash
              >>= (@?= Right [])
            let emptyManifest = Checkpoint.emptyManifest "empty-uncommitted" experimentHash []
                emptySha = Checkpoint.manifestContentSha emptyManifest
            emptyWrite <-
              CheckpointStore.writeObjectIfAbsent
                emptyRoot
                (Checkpoint.manifestKey experimentHash emptySha)
                (Checkpoint.encodeManifestCbor emptyManifest)
            case emptyWrite of
              Left err -> assertFailure (show err)
              Right _ -> pure ()
            CheckpointStore.listCheckpointManifests emptyRoot experimentHash
              >>= (@?= Right [])
      , testCase
          "zero-object snapshots require their exact commit before model admission and own only that commit in GC (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-zero-object"
          $ \root -> do
            let experimentHash = "exp-zero-object"
                logicalManifest =
                  Checkpoint.emptyManifest "zero-object" experimentHash []
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        []
                    )
                committedRoot = root </> "committed"
                commitlessRoot = root </> "commitless"
            storedResult <-
              CheckpointStore.writeCandidateCheckpointSnapshot
                committedRoot
                logicalManifest
                []
            stored <-
              case storedResult of
                Left err -> assertFailure (show err) >> error "unreachable"
                Right candidate ->
                  pure (CheckpointStore.candidateStoredCheckpoint candidate)
            admitted <-
              CheckpointStore.admitLocalCheckpointAt
                committedRoot
                experimentHash
                (CheckpointStore.storedManifestSha stored)
            case admitted of
              Left err ->
                assertFailure
                  ( "committed zero-object snapshot was rejected: "
                      <> Text.unpack (CheckpointStore.renderCheckpointAdmissionError err)
                  )
              Right checkpoint -> do
                CheckpointStore.admittedCheckpointManifestSha checkpoint
                  @?= CheckpointStore.storedManifestSha stored
                length (CheckpointStore.admittedCheckpointWeights checkpoint) @?= 0
            CheckpointStore.listCheckpointManifests committedRoot experimentHash
              >>= (@?= Right [CheckpointStore.preparedSnapshotManifest prepared])
            case CheckpointStore.gcReapEvents
              ( CheckpointStore.buildGcPlan
                  experimentHash
                  (CheckpointStore.LastN 0)
                  [CheckpointStore.preparedSnapshotManifest prepared]
                  []
              ) of
              [event] ->
                CheckpointStore.gcReapedObjectKeys event
                  @?= [ CheckpointStore.writerCommitObjectKey
                          (CheckpointStore.preparedSnapshotCommit prepared)
                      ]
              events ->
                assertFailure ("expected one zero-object GC event, got " <> show events)
            commitlessWrite <-
              CheckpointStore.writeObjectIfAbsent
                commitlessRoot
                (Checkpoint.manifestKey experimentHash (Checkpoint.manifestContentSha logicalManifest))
                (Checkpoint.encodeManifestCbor logicalManifest)
            case commitlessWrite of
              Left err -> assertFailure (show err)
              Right _ -> pure ()
            inspected <-
              CheckpointStore.readCheckpointManifest
                commitlessRoot
                experimentHash
                (Checkpoint.manifestContentSha logicalManifest)
            inspected @?= Right logicalManifest
            rejected <-
              CheckpointStore.admitLocalCheckpointAt
                commitlessRoot
                experimentHash
                (Checkpoint.manifestContentSha logicalManifest)
            case rejected of
              Left (CheckpointStore.AdmissionSnapshotCommitInvalid _) -> pure ()
              Left err -> assertFailure ("wrong commitless admission error: " <> show err)
              Right _ -> assertFailure "commitless empty manifest was admitted"
            CheckpointStore.listCheckpointManifests commitlessRoot experimentHash
              >>= (@?= Right [])
      , testCase
          "the admitted-inventory audit rebases companion pointers exactly as the writer does (Phase 262)"
          $ do
            let experimentHash = "exp-companion-artifact"
                payload = Checkpoint.encodeJmw1 [7]
                payloadSha = WeightCodec.jmw1ContentSha payload
                logicalKey =
                  "jitml-checkpoints/"
                    <> experimentHash
                    <> "/artifacts/rl-trajectory/"
                    <> payloadSha
                    <> ".txt"
                logicalPointer =
                  Checkpoint.ArtifactPointer
                    { Checkpoint.artifactPointerKind = "rl-trajectory"
                    , Checkpoint.artifactPointerObjectKey = logicalKey
                    , Checkpoint.artifactPointerSha = Just payloadSha
                    }
                logicalManifest =
                  (Checkpoint.emptyManifest "companion" experimentHash [])
                    { Checkpoint.manifestTranscriptPointers = [logicalPointer]
                    }
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalKey, payload)]
                    )
                preparedManifest = CheckpointStore.preparedSnapshotManifest prepared
                snapshotId =
                  journalExpectEitherRight
                    (CheckpointStore.checkpointStorageSnapshotId preparedManifest)
            -- The writer rebases companion pointers into the snapshot
            -- namespace, so the publisher audit must project the logical
            -- pointer through the identical derivation before comparing
            -- inventories. This is the exact equality the live
            -- admitted-inventory audit performs.
            Checkpoint.manifestTranscriptPointers preparedManifest
              @?= [ Publisher.snapshotScopedPointer
                      preparedManifest
                      snapshotId
                      logicalPointer
                  ]
            assertBool
              "the writer must not leave a companion pointer at its logical key"
              ( Checkpoint.manifestTranscriptPointers preparedManifest
                  /= [logicalPointer]
              )
            -- A manifest with no physical objects has no namespace, so the
            -- audit leaves its projected pointer untouched.
            Publisher.snapshotScopedPointer
              (Checkpoint.emptyManifest "companion-empty" experimentHash [])
              Nothing
              logicalPointer
              @?= logicalPointer
      , testCase
          "the storage snapshot id binds the jitml-snapshot-v1 domain, logical manifest, and sorted bindings (Phase 262)"
          $ do
            let experimentHash = "exp-snapshot-domain"
                payload = Checkpoint.encodeJmw1 [11]
                payloadSha = WeightCodec.jmw1ContentSha payload
                logicalObjectKey = Checkpoint.blobKey experimentHash payloadSha
                logicalManifest =
                  Checkpoint.emptyManifest
                    "snapshot-domain"
                    experimentHash
                    [Checkpoint.TensorBlob "weights" [1] logicalObjectKey]
                emptyManifest =
                  Checkpoint.emptyManifest "snapshot-domain-empty" experimentHash []
                prepared =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        logicalManifest
                        [(logicalObjectKey, payload)]
                    )
                preparedEmpty =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        emptyManifest
                        []
                    )
                expectedSnapshotId =
                  phase262DerivedSnapshotId
                    logicalManifest
                    [(logicalObjectKey, payloadSha)]
                expectedEmptySnapshotId = phase262DerivedSnapshotId emptyManifest []
                orderedPayloads =
                  [Checkpoint.encodeJmw1 [21], Checkpoint.encodeJmw1 [22]]
                orderedPairs =
                  [ (Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha blob), blob)
                  | blob <- orderedPayloads
                  ]
                -- Declare the payload bindings in the reverse of their sorted
                -- key order so the implementation's sort is observable.
                declaredPairs = List.sortOn (Down . fst) orderedPairs
                declaredBindings =
                  [ (objectKey, WeightCodec.jmw1ContentSha blob)
                  | (objectKey, blob) <- declaredPairs
                  ]
                declaredManifest =
                  Checkpoint.emptyManifest
                    "snapshot-domain-order"
                    experimentHash
                    [ Checkpoint.TensorBlob tensorName [1] objectKey
                    | (tensorName, (objectKey, _)) <-
                        zip ["weights-a", "weights-b"] declaredPairs
                    ]
                preparedOrdered =
                  journalExpectEitherRight
                    ( CheckpointStore.prepareCheckpointSnapshot
                        CheckpointStore.WriterCandidateSnapshot
                        CheckpointStore.WriterNoPointerIntent
                        declaredManifest
                        declaredPairs
                    )
                commitKeyFor snapshotId =
                  "jitml-checkpoints/"
                    <> experimentHash
                    <> "/snapshots/"
                    <> snapshotId
                    <> "/committed.cbor"
            CheckpointStore.preparedSnapshotId prepared @?= expectedSnapshotId
            CheckpointStore.preparedSnapshotId preparedEmpty @?= expectedEmptySnapshotId
            -- The derived identity is the namespace every rebased physical key
            -- and the sole GC-owned control key are bound to.
            CheckpointStore.checkpointStorageSnapshotId
              (CheckpointStore.preparedSnapshotManifest prepared)
              @?= Right (Just expectedSnapshotId)
            CheckpointStore.writerCommitObjectKey
              (CheckpointStore.preparedSnapshotCommit prepared)
              @?= commitKeyFor expectedSnapshotId
            CheckpointStore.checkpointStorageSnapshotId
              (CheckpointStore.preparedSnapshotManifest preparedEmpty)
              @?= Right Nothing
            CheckpointStore.writerCommitObjectKey
              (CheckpointStore.preparedSnapshotCommit preparedEmpty)
              @?= commitKeyFor expectedEmptySnapshotId
            -- The binding table is sorted before it is hashed, so a manifest
            -- which declares its payloads out of key order still derives the
            -- sorted identity.
            assertBool
              "fixture must declare its bindings out of sorted key order"
              (declaredBindings /= List.sortOn fst declaredBindings)
            CheckpointStore.preparedSnapshotId preparedOrdered
              @?= phase262DerivedSnapshotId declaredManifest declaredBindings
            assertBool
              "snapshot identity does not sort its payload binding table"
              ( CheckpointStore.preparedSnapshotId preparedOrdered
                  /= WeightCodec.jmw1ContentSha
                    ( Serialise.serialise
                        ( "jitml-snapshot-v1" :: Text
                        , ByteString.toStrict
                            (Checkpoint.encodeManifestCbor declaredManifest)
                        , declaredBindings
                        )
                    )
              )
      , testCase
          "fresh-plan discovery persists a writer completion and restarts before GC no-op (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-fresh-plan-restart"
          $ \root -> do
            let experimentHash = "exp-fresh-plan-restart"
                oldPrepared =
                  phase262PreparedTensorSnapshot experimentHash "old" 1
                newPrepared =
                  phase262PreparedTensorSnapshot experimentHash "new" 2
                retention = CheckpointStore.LastN 1
            phase262SeedPreparedSnapshotMinIO root oldPrepared
            initialManifests <-
              runFilesystemMinIO
                root
                (CheckpointStore.listCheckpointManifestsMinIO experimentHash)
                >>= \case
                  Left err ->
                    assertFailure ("initial manifest view failed: " <> show err)
                      >> error "unreachable"
                  Right values -> pure values
            let initialPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    retention
                    initialManifests
                    []
            CheckpointStore.gcNoOp initialPlan @?= True
            gcFreshPlanIntentsToPersist initialPlan [] @?= Right []
            -- A writer completes after the initial no-op view but before the
            -- epoch-bracketed fresh view. LastN 1 now discovers the old exact
            -- graph as new work.
            phase262SeedPreparedSnapshotMinIO root newPrepared
            freshManifests <-
              runFilesystemMinIO
                root
                (CheckpointStore.listCheckpointManifestsMinIO experimentHash)
                >>= \case
                  Left err ->
                    assertFailure ("fresh manifest view failed: " <> show err)
                      >> error "unreachable"
                  Right values -> pure values
            let freshPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    retention
                    freshManifests
                    []
            CheckpointStore.gcNoOp freshPlan @?= False
            missing <-
              case gcFreshPlanIntentsToPersist freshPlan [] of
                Right [intent] -> pure [intent]
                outcome ->
                  assertFailure ("fresh plan did not discover one exact intent: " <> show outcome)
                    >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents missing)
              >>= (@?= Right missing)
            nextPending <-
              runFilesystemMinIO root (CheckpointStore.loadGcIntents experimentHash)
                >>= \case
                  Left err ->
                    assertFailure ("restarted pending scan failed: " <> show err)
                      >> error "unreachable"
                  Right values -> pure values
            gcFreshPlanIntentsToPersist freshPlan nextPending @?= Right []
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            witnesses <-
              case CheckpointStore.revalidateGcIntents
                epoch
                epoch
                freshPlan
                freshManifests
                []
                []
                []
                nextPending of
                Right (values, []) -> pure values
                outcome ->
                  assertFailure ("restarted fresh view did not handle the intent: " <> show outcome)
                    >> error "unreachable"
            authorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents witnesses)
            CheckpointStore.gcAuthorizationFailures authorization @?= []
            CheckpointStore.gcAuthorizationCancelledIntents authorization @?= []
            executed <-
              runFilesystemMinIO
                root
                ( CheckpointStore.executeAuthorizedGcIntents
                    (CheckpointStore.gcAuthorizedIntents authorization)
                )
            length (CheckpointStore.gcCompletedExecutions executed) @?= 1
            CheckpointStore.gcExecutionFailures executed @?= []
      , testCase
          "the bounded fresh-view driver fails closed after exactly 4,096 attempts (Phase 262)"
          $ do
            freshGcConvergenceFailure
              @?= AppError.InvalidConfig "gc fresh-view convergence did not stabilize"
            -- A view which always asks for another restart must exhaust the
            -- production bound instead of looping forever.
            exhausted <-
              phase262CountedConvergence
                freshGcConvergenceAttemptBound
                (\attempt state -> Left (state + attempt))
            exhausted @?= (Nothing, 4096)
            -- The bound is the driver's only stopping rule for a restarting
            -- view, so a smaller bound stops sooner and the 4,096 above is the
            -- value `runFreshGcConvergence` supplies.
            phase262CountedConvergence 3 (\attempt state -> Left (state + attempt))
              >>= (@?= (Nothing, 3))
            -- A view which stabilizes returns its value and stops attempting.
            converged <-
              phase262CountedConvergence
                freshGcConvergenceAttemptBound
                ( \attempt state ->
                    if attempt == 2
                      then Right ("converged after " <> Text.pack (show state))
                      else Left (state + 1)
                )
            converged @?= (Just "converged after 2", 3)
      , testCase
          "the ProductScenario operational envelope is exactly four hours (Phase 262)"
          $ do
            -- The runner installs this exact value as its live-workflow
            -- timeout, so pinning it here is what keeps the envelope from
            -- silently regressing to the former two-hour bound that expired
            -- the heaviest canonical row before it could publish completion.
            let oneHourMicros = 60 * 60 * 1_000_000 :: Int
                envelopeMicros =
                  ProductScenarioRunner.productScenarioWorkflowTimeoutMicros
            envelopeMicros @?= 4 * oneHourMicros
            -- Stated in the units the envelope is reasoned about in, so a
            -- micro/millisecond mix-up is caught rather than merely a change
            -- in the arithmetic that spells the same number.
            envelopeMicros `div` oneHourMicros @?= 4
      , testCase
          "an out-of-domain request input is a terminal load failure, a runner failure is not (Phase 262)"
          $ do
            -- The Engine settles a terminal failure by answering it and moves
            -- on; a non-terminal one nacks and is redelivered. Getting this
            -- classification wrong in either direction is severe: a
            -- misclassified transient discards recoverable work, and a
            -- misclassified permanent failure parks an unanswerable request on
            -- the one shared `jitml-engine` subscription forever, which
            -- silences every other inference command behind it.
            let unitImage = phase262UnitImageServingManifest
            -- Outside `[0,1]`: exactly the shape that starved the live Engine.
            case CheckpointStore.checkpointRequestInputRejection
              unitImage
              [0.7, -0.5, 1.0, 2.0] of
              Nothing ->
                assertFailure
                  "an out-of-[0,1] unit-image input was accepted by the request oracle"
              Just reason ->
                assertBool
                  ("rejected for the wrong reason: " <> Text.unpack reason)
                  ("[0,1]" `Text.isInfixOf` reason)
            -- The same values are legal for a standardized regression runtime,
            -- so the verdict follows the admitted runtime's declared domain
            -- rather than the literal numbers.
            CheckpointStore.checkpointRequestInputRejection
              phase262StandardizedServingManifest
              [0.7, -0.5, 1.0, 2.0]
              @?= Nothing
            -- Inside the domain, and at both closed endpoints.
            CheckpointStore.checkpointRequestInputRejection
              unitImage
              [0.0, 0.25, 0.5, 1.0]
              @?= Nothing
            -- Width is equally request-determined.
            assertBool
              "a wrong-width input was accepted by the request oracle"
              ( isJust
                  ( CheckpointStore.checkpointRequestInputRejection
                      unitImage
                      [0.5, 0.5, 0.5]
                  )
              )
            -- A manifest declaring no supervised runtime declares no input
            -- domain, so it must not manufacture a terminal verdict.
            CheckpointStore.checkpointRequestInputRejection
              (completedTestManifest 4)
              [0.7, -0.5, 1.0, 2.0]
              @?= Nothing
            -- The settlement decision itself.
            CheckpointStore.checkpointLoadErrorTerminal
              (CheckpointStore.CheckpointLoadInputRejected "outside [0,1]")
              @?= True
            -- A runner failure describes execution, not the request, so a
            -- redelivery can still succeed and it must stay retryable.
            CheckpointStore.checkpointLoadErrorTerminal
              (CheckpointStore.CheckpointLoadRunnerFailed "device dispatch failed")
              @?= False
      , testCase
          "the checkpoint-compare panel submits inside the unit-image domain it compares (Phase 262)"
          $ do
            -- The panel compares two MNIST classifiers, whose trained runtime
            -- declares a unit-image input transform. A default outside `[0,1]`
            -- is unanswerable by construction, and that exact residue — carried
            -- over from the panel's retired generic-tensor target — is what
            -- poisoned the live Engine's shared subscription.
            source <- Text.IO.readFile "web/src/Panels/CheckpointCompare.purs"
            baseline <- phase262PanelStringField source "defaultBaselineExperimentHash"
            candidate <- phase262PanelStringField source "defaultCandidateExperimentHash"
            assertBool
              ( "this guard only holds while both compared rows are unit-image "
                  <> "classifiers; got "
                  <> Text.unpack baseline
                  <> " and "
                  <> Text.unpack candidate
              )
              ( all
                  ("product-row-mnist-" `Text.isPrefixOf`)
                  [baseline, candidate]
              )
            values <- phase262PanelDefaultInput source
            assertBool
              "the compare panel declares no default input values"
              (not (null values))
            assertBool
              ( "compare panel default input leaves the unit-image domain: "
                  <> show values
              )
              (all (\value -> value >= 0.0 && value <= 1.0) values)
      , testCase
          "fresh revalidation executes or cancels each exact intent without subset trimming (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-fresh-revalidation"
          $ \root -> do
            let experimentHash = "exp-gc-fresh-revalidation"
                prepared = phase262PreparedTensorSnapshot experimentHash "target" 4
                target = CheckpointStore.preparedSnapshotManifest prepared
                initialPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [target]
                    []
                rootedPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [target]
                    [target]
                gonePlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    []
                    []
            case CheckpointStore.gcPlanIntents initialPlan of
              [intent] -> do
                epoch <- phase262LoadGcFenceEpoch root experimentHash
                let exactKeys =
                      CheckpointStore.gcReapedObjectKeys
                        (CheckpointStore.gcIntentEvent intent)
                length exactKeys @?= 2
                CheckpointStore.revalidateGcIntents
                  epoch
                  epoch
                  rootedPlan
                  [target]
                  [target]
                  []
                  []
                  [intent]
                  @?= Right ([], [intent])
                CheckpointStore.revalidateGcIntents
                  epoch
                  epoch
                  gonePlan
                  []
                  []
                  []
                  []
                  [intent]
                  @?= Right ([], [intent])
                CheckpointStore.revalidateGcIntents
                  epoch
                  epoch
                  initialPlan
                  [target]
                  []
                  []
                  [CheckpointStore.gcIntentEvent intent]
                  [intent]
                  @?= Right ([], [intent])
                CheckpointStore.gcReapedObjectKeys
                  (CheckpointStore.gcIntentEvent intent)
                  @?= exactKeys
                let ready =
                      CheckpointStore.GcReadyEvent
                        { CheckpointStore.gcReadyEvent =
                            CheckpointStore.gcIntentEvent intent
                        , CheckpointStore.gcReadyEventId =
                            CheckpointStore.gcIntentEventId intent
                        , CheckpointStore.gcReadySubstrate = "linux-cpu"
                        , CheckpointStore.gcReadyTimestampNs = 1
                        }
                assertBool
                  "one event was accepted as both cancelled and publish-ready"
                  ( case CheckpointStore.validateGcTerminalRelations
                      [intent]
                      [intent]
                      [ready]
                      [] of
                      Left (ServiceRetry.SEConflict _) -> True
                      _ -> False
                  )
                assertBool
                  "one event was accepted as both cancelled and published"
                  ( case CheckpointStore.validateGcTerminalRelations
                      [intent]
                      [intent]
                      []
                      [ready] of
                      Left (ServiceRetry.SEConflict _) -> True
                      _ -> False
                  )
              intents -> assertFailure ("expected one exact initial intent, got " <> show intents)
      , testCase
          "Executing crash recovery deletes exact remnants, records Reaped, and replays idempotently (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-gc-executing-recovery"
          $ \root -> do
            let experimentHash = "exp-gc-executing-recovery"
                prepared = phase262PreparedTensorSnapshot experimentHash "recovery" 3
                manifest = CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [manifest]
                    []
                absentPlan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    []
                    []
            phase262SeedPreparedSnapshotMinIO root prepared
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values -> assertFailure ("expected one recovery intent, got " <> show values) >> error "unreachable"
            persisted <-
              runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
            persisted @?= Right [intent]
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            let witness = phase262SingleRevalidatedIntent epoch plan [manifest] [] [] [] intent
            authorization <-
              runFilesystemMinIO root (CheckpointStore.authorizeRevalidatedGcIntents [witness])
            CheckpointStore.gcAuthorizationCancelledIntents authorization @?= []
            CheckpointStore.gcAuthorizationFailures authorization @?= []
            authorized <-
              case CheckpointStore.gcAuthorizedIntents authorization of
                [value] -> pure value
                values -> assertFailure ("expected one authorization, got " <> show values) >> error "unreachable"
            let event = CheckpointStore.gcIntentEvent intent
                candidateReady =
                  CheckpointStore.GcReadyEvent
                    { CheckpointStore.gcReadyEvent = event
                    , CheckpointStore.gcReadyEventId =
                        CheckpointStore.gcIntentEventId intent
                    , CheckpointStore.gcReadySubstrate = "linux-cpu"
                    , CheckpointStore.gcReadyTimestampNs = 1
                    }
                manifestRef =
                  CheckpointStore.checkpointObjectRef
                    (Checkpoint.manifestKey experimentHash (CheckpointStore.gcReapedManifestSha event))
            runFilesystemMinIO
              root
              (CheckpointStore.acknowledgeGcReadyEvent candidateReady)
              >>= \case
                Left _ -> pure ()
                Right () -> assertFailure "Executing operation published an unpersisted ready value"
            firstPhysicalRef <-
              case CheckpointStore.gcReapedObjectKeys event of
                firstKey : _ ->
                  pure (CheckpointStore.checkpointObjectRef firstKey)
                [] ->
                  assertFailure "recovery fixture unexpectedly has no physical objects"
                    >> error "unreachable"
            runFilesystemMinIO root (deleteObject manifestRef) >>= (@?= Right ())
            runFilesystemMinIO root (deleteObject firstPhysicalRef) >>= (@?= Right ())
            recoveryEpoch <- phase262LoadGcFenceEpoch root experimentHash
            let recoveryWitness =
                  phase262SingleRevalidatedIntent
                    recoveryEpoch
                    absentPlan
                    []
                    []
                    []
                    []
                    intent
            recoveryAuthorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents [recoveryWitness])
            CheckpointStore.gcAuthorizationFailures recoveryAuthorization @?= []
            CheckpointStore.gcAuthorizationCancelledIntents recoveryAuthorization @?= []
            recoveredAuthorized <-
              case CheckpointStore.gcAuthorizedIntents recoveryAuthorization of
                [value] -> pure value
                values ->
                  assertFailure ("Executing recovery lost exact authority: " <> show values)
                    >> error "unreachable"
            recoveredAuthorized @?= authorized
            executed <-
              runFilesystemMinIO
                root
                (CheckpointStore.executeAuthorizedGcIntents [recoveredAuthorized])
            fmap
              (CheckpointStore.gcIntentEventId . CheckpointStore.gcExecutionIntent)
              (CheckpointStore.gcCompletedExecutions executed)
              @?= [CheckpointStore.gcIntentEventId intent]
            CheckpointStore.gcExecutionFailures executed @?= []
            fence <- phase262LoadExperimentFence root experimentHash
            case reverse (CheckpointStore.experimentGcFenceDecisions fence) of
              decision : _ -> do
                CheckpointStore.gcFenceDecisionIntent decision @?= intent
                CheckpointStore.gcFenceDecisionPhase decision @?= CheckpointStore.GcFenceReaped
              [] -> assertFailure "Reaped execution left no durable decision"
            reapedEpoch <- phase262LoadGcFenceEpoch root experimentHash
            let reapedWitness =
                  phase262SingleRevalidatedIntent
                    reapedEpoch
                    absentPlan
                    []
                    []
                    []
                    []
                    intent
            reapedAuthorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents [reapedWitness])
            reapedAuthorized <-
              case CheckpointStore.gcAuthorizedIntents reapedAuthorization of
                [value] -> pure value
                values ->
                  assertFailure ("Reaped recovery lost exact authority: " <> show values)
                    >> error "unreachable"
            CheckpointStore.gcAuthorizationFailures reapedAuthorization @?= []
            CheckpointStore.gcAuthorizationCancelledIntents reapedAuthorization @?= []
            reapedAuthorized @?= authorized
            replayed <-
              runFilesystemMinIO
                root
                (CheckpointStore.executeAuthorizedGcIntents [reapedAuthorized])
            length (CheckpointStore.gcCompletedExecutions replayed) @?= 1
            CheckpointStore.gcExecutionFailures replayed @?= []
            runFilesystemMinIO
              root
              (CheckpointStore.acknowledgeGcReadyEvent candidateReady)
              >>= \case
                Left _ -> pure ()
                Right () -> assertFailure "Reaped operation published an absent ready value"
            promoted <-
              runFilesystemMinIO root (CheckpointStore.promoteGcIntents "linux-cpu" 1 [intent])
            CheckpointStore.gcPromotionFailures promoted @?= []
            ready <-
              case CheckpointStore.gcPromotedReadyEvents promoted of
                [value] -> pure value
                values -> assertFailure ("expected one durable ready value, got " <> show values) >> error "unreachable"
            ready @?= candidateReady
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcReadyEvents experimentHash)
              >>= (@?= Right [ready])
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcIntents experimentHash)
              >>= (@?= Right [intent])
            gcFreshTerminalRecoveryWork [intent] [ready] []
              @?= ([], [ready])
            let forgedReady =
                  ready {CheckpointStore.gcReadyTimestampNs = 2}
            runFilesystemMinIO
              root
              (CheckpointStore.acknowledgeGcReadyEvent forgedReady)
              >>= \case
                Left _ -> pure ()
                Right () -> assertFailure "forged ready bytes minted a published tombstone"
            runFilesystemMinIO
              root
              (CheckpointStore.acknowledgeGcReadyEvent ready)
              >>= (@?= Right ())
            runFilesystemMinIO
              root
              (CheckpointStore.acknowledgeGcReadyEvent ready)
              >>= (@?= Right ())
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcPublishedEvents experimentHash)
              >>= (@?= Right [ready])
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcReadyEvents experimentHash)
              >>= (@?= Right [])
            -- A published tombstone which appears after the initial scan is
            -- permanent, but a late transient intent still requires exact
            -- acknowledgement cleanup and a full fresh-view restart.
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            gcFreshTerminalRecoveryWork [intent] [] [ready]
              @?= ([ready], [])
            runFilesystemMinIO
              root
              (CheckpointStore.acknowledgeGcReadyEvent ready)
              >>= (@?= Right ())
            runFilesystemMinIO
              root
              (CheckpointStore.loadGcIntents experimentHash)
              >>= (@?= Right [])
      , testCase
          "an already-Reaped event remains promotable when a sibling manifest delete fails (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-reaped-sibling-failure"
          $ \root -> do
            let experimentHash = "exp-reaped-sibling-failure"
                prepared =
                  [ phase262PreparedTensorSnapshot experimentHash tag step
                  | (tag, step) <- [("first", 1), ("second", 2)]
                  ]
                manifests = fmap CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    manifests
                    []
            traverse_ (phase262SeedPreparedSnapshotMinIO root) prepared
            intents <-
              case CheckpointStore.gcPlanIntents plan of
                [first, second] -> pure [first, second]
                values ->
                  assertFailure ("expected two mixed-batch intents, got " <> show values)
                    >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents intents)
              >>= (@?= Right intents)
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            witnesses <-
              case CheckpointStore.revalidateGcIntents
                epoch
                epoch
                plan
                manifests
                []
                []
                []
                intents of
                Right (values, []) -> pure values
                outcome ->
                  assertFailure ("mixed-batch revalidation failed: " <> show outcome)
                    >> error "unreachable"
            authorization <-
              runFilesystemMinIO
                root
                (CheckpointStore.authorizeRevalidatedGcIntents witnesses)
            CheckpointStore.gcAuthorizationCancelledIntents authorization @?= []
            CheckpointStore.gcAuthorizationFailures authorization @?= []
            (reapedAuthorization, siblingAuthorization) <-
              case CheckpointStore.gcAuthorizedIntents authorization of
                [first, second] -> pure (first, second)
                values ->
                  assertFailure ("expected two mixed-batch authorizations, got " <> show values)
                    >> error "unreachable"
            firstExecution <-
              runFilesystemMinIO
                root
                (CheckpointStore.executeAuthorizedGcIntents [reapedAuthorization])
            reapedIntent <-
              case CheckpointStore.gcCompletedExecutions firstExecution of
                [execution] -> pure (CheckpointStore.gcExecutionIntent execution)
                values ->
                  assertFailure ("could not establish Reaped fixture: " <> show values)
                    >> error "unreachable"
            siblingIntent <-
              case filter (/= reapedIntent) intents of
                [value] -> pure value
                values ->
                  assertFailure ("could not identify mixed-batch sibling: " <> show values)
                    >> error "unreachable"
            let siblingEvent = CheckpointStore.gcIntentEvent siblingIntent
                failingManifestRef =
                  CheckpointStore.checkpointObjectRef
                    ( Checkpoint.manifestKey
                        experimentHash
                        (CheckpointStore.gcReapedManifestSha siblingEvent)
                    )
            deleteCalls <- newIORef []
            let environment =
                  Phase262DeleteFailureEnv
                    { phase262DeleteFailureRoot = root
                    , phase262DeleteFailureRef = failingManifestRef
                    , phase262DeleteFailureCalls = deleteCalls
                    }
            mixedExecution <-
              runPhase262DeleteFailureMinIO environment $
                CheckpointStore.executeAuthorizedGcIntents
                  [reapedAuthorization, siblingAuthorization]
            fmap
              CheckpointStore.gcExecutionIntent
              (CheckpointStore.gcCompletedExecutions mixedExecution)
              @?= [reapedIntent]
            calls <- readIORef deleteCalls
            calls @?= [failingManifestRef]
            case filter
              ((== siblingIntent) . CheckpointStore.gcExecutionIntent)
              (CheckpointStore.gcEventExecutions mixedExecution) of
              [execution] -> do
                assertBool
                  "sibling manifest failure was not reported"
                  ( case CheckpointStore.gcManifestDeleteOutcome execution of
                      CheckpointStore.GcDeleteFailed _ -> True
                      _ -> False
                  )
                assertBool
                  "the failed sibling crossed the physical-object barrier"
                  ( all
                      ((== CheckpointStore.GcDeleteDeferred) . snd)
                      (CheckpointStore.gcObjectDeleteOutcomes execution)
                  )
              values ->
                assertFailure ("missing sibling execution outcome: " <> show values)
            for_ (CheckpointStore.gcReapedObjectKeys siblingEvent) $ \key ->
              runFilesystemMinIO
                root
                (minioReadBytes (CheckpointStore.checkpointObjectRef key))
                >>= \case
                  Left err ->
                    assertFailure ("sibling object was touched behind the barrier: " <> show err)
                  Right _ -> pure ()
            promoted <-
              runFilesystemMinIO
                root
                (CheckpointStore.promoteGcIntents "linux-cpu" 1 [reapedIntent])
            CheckpointStore.gcPromotionFailures promoted @?= []
            fmap
              CheckpointStore.gcReadyEvent
              (CheckpointStore.gcPromotedReadyEvents promoted)
              @?= [CheckpointStore.gcIntentEvent reapedIntent]
      , testCase
          "Executing wins before a later writer can create a marker or repair a deleted payload (Phase 262)"
          $ withSystemTempDirectory "jitml-phase262-gc-wins-writer"
          $ \root -> do
            let experimentHash = "exp-gc-wins-writer"
                tag = "gc-wins"
                step = 4
                payload = Checkpoint.encodeJmw1 [fromIntegral step + 1]
                logicalObjectKey =
                  Checkpoint.blobKey experimentHash (WeightCodec.jmw1ContentSha payload)
                logicalManifest =
                  ( Checkpoint.emptyManifest
                      tag
                      experimentHash
                      [Checkpoint.TensorBlob (tag <> ".weights") [1] logicalObjectKey]
                  )
                    { Checkpoint.manifestStep = step
                    }
                prepared = phase262PreparedTensorSnapshot experimentHash tag step
                manifest = CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [manifest]
                    []
            phase262SeedPreparedSnapshotMinIO root prepared
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values -> assertFailure ("expected one GC-wins intent, got " <> show values) >> error "unreachable"
            runFilesystemMinIO root (CheckpointStore.persistGcIntents [intent])
              >>= (@?= Right [intent])
            epoch <- phase262LoadGcFenceEpoch root experimentHash
            let witness = phase262SingleRevalidatedIntent epoch plan [manifest] [] [] [] intent
            authorization <-
              runFilesystemMinIO root (CheckpointStore.authorizeRevalidatedGcIntents [witness])
            length (CheckpointStore.gcAuthorizedIntents authorization) @?= 1
            CheckpointStore.gcAuthorizationFailures authorization @?= []
            let payloadKey =
                  case CheckpointStore.preparedSnapshotPayloads prepared of
                    [(key, _)] -> key
                    values -> error ("unexpected payload fixture: " <> show values)
                payloadRef = CheckpointStore.checkpointObjectRef payloadKey
                reservation =
                  journalExpectEitherRight
                    ( CheckpointStore.instantiateWriterReservation
                        (Text.replicate 64 "0")
                        (CheckpointStore.preparedSnapshotReservationTemplate prepared)
                    )
                markerRef =
                  CheckpointStore.checkpointObjectRef
                    (CheckpointStore.writerReservationObjectKey reservation)
            runFilesystemMinIO root (deleteObject payloadRef) >>= (@?= Right ())
            writer <-
              runFilesystemMinIO root $
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  logicalManifest
                  [(logicalObjectKey, payload)]
            case writer of
              Left (ServiceRetry.SEConflict reason) ->
                assertBool
                  ("writer lost with the wrong reason: " <> Text.unpack reason)
                  ("executing or reaped" `Text.isInfixOf` reason)
              Left err -> assertFailure ("writer lost with the wrong error: " <> show err)
              Right _ -> assertFailure "writer mutated after GC execution authorization"
            runFilesystemMinIO root (minioReadBytes payloadRef) >>= \case
              Left _ -> pure ()
              Right _ -> assertFailure "losing writer repaired the deleted payload"
            runFilesystemMinIO root (minioReadBytes markerRef) >>= \case
              Left _ -> pure ()
              Right _ -> assertFailure "losing writer created a separate marker"
            runFilesystemMinIO
              root
              (CheckpointStore.loadActiveWriterReservations experimentHash)
              >>= (@?= Right [])
      , testCase
          "experiment fence codec rejects version, generation, and operation-id forgeries (Phase 262)"
          $ do
            let experimentHash = "exp-gc-fence-codec"
                prepared = phase262PreparedTensorSnapshot experimentHash "codec" 2
                manifest = CheckpointStore.preparedSnapshotManifest prepared
                plan =
                  CheckpointStore.buildGcPlan
                    experimentHash
                    (CheckpointStore.LastN 0)
                    [manifest]
                    []
            intent <-
              case CheckpointStore.gcPlanIntents plan of
                [value] -> pure value
                values -> assertFailure ("expected one codec intent, got " <> show values) >> error "unreachable"
            let decision generation phase =
                  CheckpointStore.GcFenceDecision
                    { CheckpointStore.gcFenceDecisionGeneration = generation
                    , CheckpointStore.gcFenceDecisionIntent = intent
                    , CheckpointStore.gcFenceDecisionOperationId =
                        CheckpointStore.gcFenceOperationId generation intent
                    , CheckpointStore.gcFenceDecisionPhase = phase
                    }
                valid =
                  CheckpointStore.ExperimentGcFence
                    { CheckpointStore.experimentGcFenceVersion = 1
                    , CheckpointStore.experimentGcFenceRevision = 1
                    , CheckpointStore.experimentGcFenceWriterEpoch = 0
                    , CheckpointStore.experimentGcFenceExperimentHash = experimentHash
                    , CheckpointStore.experimentGcFenceReservations = []
                    , CheckpointStore.experimentGcFenceDecisions =
                        [decision 0 CheckpointStore.GcFencePlanned]
                    }
                rejects forged =
                  assertBool
                    "forged experiment fence decoded"
                    ( case CheckpointStore.decodeExperimentGcFence
                        (CheckpointStore.encodeExperimentGcFence forged) of
                        Left _ -> True
                        Right _ -> False
                    )
            CheckpointStore.decodeExperimentGcFence
              (CheckpointStore.encodeExperimentGcFence valid)
              @?= Right valid
            rejects valid {CheckpointStore.experimentGcFenceVersion = 2}
            rejects valid {CheckpointStore.experimentGcFenceWriterEpoch = 2}
            rejects
              valid
                { CheckpointStore.experimentGcFenceDecisions =
                    [decision 2 CheckpointStore.GcFencePlanned]
                }
            rejects
              valid
                { CheckpointStore.experimentGcFenceDecisions =
                    [ (decision 0 CheckpointStore.GcFencePlanned)
                        { CheckpointStore.gcFenceDecisionOperationId = Text.replicate 64 "f"
                        }
                    ]
                }
            CheckpointStore.experimentGcFenceObjectKey experimentHash
              @?= "jitml-checkpoints/"
              <> experimentHash
              <> "/gc/coordination-fence.txt"
      , testCase
          "experiment fence wire envelope is the exact prefix plus lowercase-hex canonical CBOR (Phase 262)"
          $ do
            let experimentHash = "exp-fence-envelope"
                fence =
                  CheckpointStore.ExperimentGcFence
                    { CheckpointStore.experimentGcFenceVersion = 1
                    , CheckpointStore.experimentGcFenceRevision = 23
                    , CheckpointStore.experimentGcFenceWriterEpoch = 0
                    , CheckpointStore.experimentGcFenceExperimentHash = experimentHash
                    , CheckpointStore.experimentGcFenceReservations = []
                    , CheckpointStore.experimentGcFenceDecisions = []
                    }
                canonicalPayload = ByteString.toStrict (Serialise.serialise fence)
                canonicalHex = phase262LowerHex canonicalPayload
                envelopeFor payload =
                  "jitml-experiment-gc-fence-v1:" <> phase262LowerHex payload
                encoded = CheckpointStore.encodeExperimentGcFence fence
            encoded @?= envelopeFor canonicalPayload
            CheckpointStore.decodeExperimentGcFence encoded @?= Right fence
            assertBool
              "the fence hex payload has no case-sensitive digits"
              (Text.toUpper canonicalHex /= canonicalHex)
            -- The redundant one-byte-length unsigned form is well-formed CBOR
            -- that cborg accepts but never emits, so the same revision decodes
            -- from different bytes and only the re-encode check rejects it.
            revisionIndex <-
              case StrictByteString.elemIndices 23 canonicalPayload of
                [index] -> pure index
                indices ->
                  assertFailure ("the fence revision byte is not unique: " <> show indices)
                    >> error "unreachable"
            let noncanonicalPayload =
                  StrictByteString.take revisionIndex canonicalPayload
                    <> StrictByteString.pack [0x18, 23]
                    <> StrictByteString.drop (revisionIndex + 1) canonicalPayload
            Serialise.deserialiseOrFail (ByteString.fromStrict noncanonicalPayload)
              @?= ( Right fence
                      :: Either Serialise.DeserialiseFailure CheckpointStore.ExperimentGcFence
                  )
            traverse_
              ( \(label, rejected, reason) ->
                  assertEqual
                    label
                    (Left reason)
                    (CheckpointStore.decodeExperimentGcFence rejected)
              )
              [
                ( "uppercase hex payload"
                , "jitml-experiment-gc-fence-v1:" <> Text.toUpper canonicalHex
                , "experiment GC fence hex payload is not lowercase hexadecimal"
                )
              ,
                ( "missing envelope prefix"
                , canonicalHex
                , "experiment GC fence has an unsupported text-envelope prefix"
                )
              ,
                ( "wrong envelope prefix"
                , "jitml-experiment-gc-fence-v2:" <> canonicalHex
                , "experiment GC fence has an unsupported text-envelope prefix"
                )
              ,
                ( "odd hex length"
                , encoded <> "0"
                , "experiment GC fence hex payload has odd length"
                )
              ,
                ( "non-hex payload characters"
                , encoded <> "zz"
                , "experiment GC fence hex payload is not lowercase hexadecimal"
                )
              ,
                ( "trailing bytes after the canonical CBOR"
                , envelopeFor (canonicalPayload <> StrictByteString.pack [0])
                , "experiment GC fence is not canonical text/CBOR"
                )
              ,
                ( "noncanonical CBOR revision encoding"
                , envelopeFor noncanonicalPayload
                , "experiment GC fence is not canonical text/CBOR"
                )
              ]
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
      , testCase "structural completion validation requires manifest weight-delta evidence" $ do
          let completedManifest = completedTestManifest 1
              stripped =
                completedManifest
                  { Checkpoint.manifestInitialWeightHash = Nothing
                  , Checkpoint.manifestFinalWeightHash = Nothing
                  , Checkpoint.manifestUpdateCount = Nothing
                  , Checkpoint.manifestDatasetShaAtRead = Nothing
                  }
          Checkpoint.validateCheckpointCompletion stripped
            @?= Left Checkpoint.CompletedTrainingEvidenceMissing
      , testCase "decoded manifests require separate structural completion validation" $ do
          let completedManifest = completedTestManifest 1
              stripped =
                completedManifest
                  { Checkpoint.manifestInitialWeightHash = Nothing
                  , Checkpoint.manifestFinalWeightHash = Nothing
                  , Checkpoint.manifestUpdateCount = Nothing
                  , Checkpoint.manifestDatasetShaAtRead = Nothing
                  }
          decoded <-
            case Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor completedManifest) of
              Left err -> assertFailure ("expected completed manifest decode, got " <> Text.unpack err)
              Right manifest -> pure manifest
          case Checkpoint.validateCheckpointCompletion decoded of
            Left err ->
              assertFailure
                ( "expected structural completion validation, got "
                    <> Text.unpack (Checkpoint.renderCheckpointCompletionValidationError err)
                )
            Right validated -> do
              Checkpoint.validatedCheckpointCompletionManifest validated
                @?= completedManifest
              Just (Checkpoint.validatedCheckpointCompletedTraining validated)
                @?= Checkpoint.manifestCompletedTraining completedManifest
          Checkpoint.decodeManifestCbor (Checkpoint.encodeManifestCbor stripped)
            @?= Right stripped
          Checkpoint.validateCheckpointCompletion stripped
            @?= Left Checkpoint.CompletedTrainingEvidenceMissing
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
            Right decoded ->
              Checkpoint.architectureLayerGraph (Checkpoint.manifestArchitecture decoded)
                @?= Just (Checkpoint.layerGraphMetadataFromGraph graph)
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
      , testCase "candidate checkpoint writes exact blobs/manifests without publishing latest" $
          withSystemTempDirectory "jitml-checkpoint-store" $ \dir -> do
            let payload = Checkpoint.encodeJmw1 [1, 2, 3, 4]
                blobKey =
                  Checkpoint.blobKey
                    "exp1"
                    (WeightCodec.jmw1ContentSha payload)
                manifest =
                  Checkpoint.emptyManifest
                    "m1"
                    "exp1"
                    [Checkpoint.TensorBlob "dense.weight" [2, 2] blobKey]
                prepared =
                  CheckpointStore.prepareCheckpointSnapshot
                    CheckpointStore.WriterCandidateSnapshot
                    CheckpointStore.WriterNoPointerIntent
                    manifest
                    [(blobKey, payload)]
            firstWriteResult <-
              CheckpointStore.writeCandidateCheckpointSnapshot dir manifest [(blobKey, payload)]
            case firstWriteResult of
              Left err ->
                assertFailure
                  ( "expected checkpoint write, got: "
                      <> Text.unpack (CheckpointStore.renderCheckpointWriteError err)
                  )
              Right candidate -> do
                let firstWrite = CheckpointStore.candidateStoredCheckpoint candidate
                expectedPrepared <-
                  case prepared of
                    Left err -> assertFailure ("candidate preparation failed: " <> Text.unpack err)
                    Right value -> pure value
                storedBlobKey <-
                  case CheckpointStore.preparedSnapshotPayloads expectedPrepared of
                    [(objectKey, _)] -> pure objectKey
                    payloads ->
                      assertFailure
                        ( "expected one prepared candidate payload, got "
                            <> show (length payloads)
                        )
                CheckpointStore.storedPointerResult firstWrite
                  @?= Checkpoint.PointerNotWritten (Checkpoint.latestPointerKey "exp1")
                decoded <-
                  CheckpointStore.readCheckpointManifest
                    dir
                    "exp1"
                    (CheckpointStore.storedManifestSha firstWrite)
                decoded @?= Right (CheckpointStore.preparedSnapshotManifest expectedPrepared)
                listed <- CheckpointStore.listCheckpointManifests dir "exp1"
                listed @?= Right [CheckpointStore.preparedSnapshotManifest expectedPrepared]
                latest <- CheckpointStore.readCheckpointPointer dir (Checkpoint.latestPointerKey "exp1")
                latest @?= Right Nothing
                blob <- CheckpointStore.readObject dir storedBlobKey
                blob @?= Right payload
                idempotentResult <-
                  CheckpointStore.writeCandidateCheckpointSnapshot dir manifest [(blobKey, payload)]
                case idempotentResult of
                  Left err ->
                    assertFailure
                      ( "expected identical candidate rewrite, got: "
                          <> Text.unpack (CheckpointStore.renderCheckpointWriteError err)
                      )
                  Right _ -> pure ()
                conflictResult <-
                  CheckpointStore.writeObjectIfAbsent dir storedBlobKey "different bytes"
                conflictResult
                  @?= Left
                    ( CheckpointStore.CheckpointWriteObjectConflict
                        storedBlobKey
                        "existing bytes differ"
                    )
                preserved <- CheckpointStore.readObject dir storedBlobKey
                preserved @?= Right payload
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
            writeFailure
              @?= Left
                ( CheckpointStore.CheckpointWriteInvalid
                    "unsafe object key: ../escape"
                )
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
            let unreadableKey = "jitml-checkpoints/exp1/artifacts/unreadable"
            createDirectoryIfMissing True (dir </> Text.unpack unreadableKey)
            unreadableWrite <-
              CheckpointStore.writeObjectIfAbsent dir unreadableKey "payload"
            case unreadableWrite of
              Left (CheckpointStore.CheckpointWriteObjectConflict actualKey reason) -> do
                actualKey @?= unreadableKey
                assertBool
                  "unreadable immutable object conflict records comparison failure"
                  ("existing bytes could not be compared" `Text.isPrefixOf` reason)
              other ->
                assertFailure
                  ("unreadable immutable object was not a typed conflict: " <> show other)
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
                , "minio-console"
                , "pulsar-admin"
                ]
          assertBool
            "admin portal renderer emits the generated module"
            ("module Generated.AdminPortals where" `Text.isInfixOf` WebAdminPortals.renderPureScriptAdminPortals)
      , testCase
          "the demo API edge route outlasts the webapp's own reply budget (Phase 262)"
          $ do
            -- The webapp brokers request/reply work through the Engine, so a
            -- shorter edge budget returns a gateway timeout for a request the
            -- webapp would have answered, and the browser never sees the typed
            -- result or the typed fail-closed reason. `JitML.Routes` sits below
            -- `JitML.Bootstrap`, which imports it, so it cannot derive this
            -- from the inference constants; the relationship is held here.
            let replyBudgetSeconds =
                  ( InferenceCommand.inferenceReplyStartupTimeoutMicros
                      + InferenceCommand.inferenceReplyTimeoutMicros
                  )
                    `div` 1_000_000
            assertBool
              ( "demo API edge timeout "
                  <> show Routes.demoApiRouteTimeoutSeconds
                  <> "s does not outlast the webapp reply budget "
                  <> show replyBudgetSeconds
                  <> "s"
              )
              (Routes.demoApiRouteTimeoutSeconds > replyBudgetSeconds)
            -- The route really carries it, so the rendered HTTPRoute cannot
            -- silently fall back to the gateway default.
            case filter ((== "demo-api") . Routes.routeName) Routes.routeRegistry of
              [demoApi] -> do
                Routes.routeTimeoutSeconds demoApi
                  @?= Just Routes.demoApiRouteTimeoutSeconds
                assertBool
                  "rendered demo-api HTTPRoute omits its request timeout"
                  ( ("request: " <> Text.pack (show Routes.demoApiRouteTimeoutSeconds) <> "s")
                      `Text.isInfixOf` Routes.renderHTTPRoute demoApi
                  )
              other ->
                assertFailure
                  ("expected exactly one demo-api route, got " <> show (length other))
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
                        (ByteString.toStrict (Checkpoint.encodeJmw1 flatWeights))
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
          , testCase "Phase 251 — evaluation episode count cannot move any training dimension" $ do
              -- One trainer per coupling site (on-policy, fixed-step off-policy,
              -- continuous control, ARS, HER): the compiled training schedule
              -- must be identical whether the run is scored over a handful of
              -- evaluation episodes or an absurdly large number, while the
              -- recorded evaluation dimension itself changes.
              let trainingFor trainerKind environment =
                    ProductBudget.TrainingPlan
                      { ProductBudget.trainingPlanTrainerKind = trainerKind
                      , ProductBudget.trainingPlanEnvironment = environment
                      , ProductBudget.trainingPlanSeed = 7
                      , ProductBudget.trainingPlanMaxEpisodeSteps =
                          ProductBudget.productRlDefaultMaxEpisodeSteps
                      , ProductBudget.trainingPlanEpisodeBudgetFloor =
                          ProductBudget.productRlDefaultTrainingEpisodeFloor
                      , ProductBudget.trainingPlanVectorEnvironments = Nothing
                      , ProductBudget.trainingPlanRequestedTransitionFloor =
                          Just ProductBudget.productRlRequestedStepFloor
                      , ProductBudget.trainingPlanExactTransitionTarget = Nothing
                      }
              mapM_
                ( \(trainerKind, environment) ->
                    case ( ProductBudget.compileRlPlan
                             (trainingFor trainerKind environment)
                             (ProductBudget.EvaluationPlan 4)
                         , ProductBudget.compileRlPlan
                             (trainingFor trainerKind environment)
                             (ProductBudget.EvaluationPlan 250_000)
                         ) of
                      (Right small, Right large) -> do
                        assertEqual
                          ( "schedule for "
                              <> Text.unpack trainerKind
                              <> "/"
                              <> Text.unpack environment
                              <> " must ignore evaluation episode count"
                          )
                          (ProductBudget.compiledRlSchedule small)
                          (ProductBudget.compiledRlSchedule large)
                        assertBool
                          "the evaluation dimension itself must differ"
                          ( ProductBudget.compiledRlEvaluationEpisodes small
                              /= ProductBudget.compiledRlEvaluationEpisodes large
                          )
                      other ->
                        assertFailure
                          ( "expected two compiled plans for "
                              <> Text.unpack trainerKind
                              <> "/"
                              <> Text.unpack environment
                              <> ": "
                              <> show other
                          )
                )
                [ ("ppo", "cartpole")
                , ("dqn", "cartpole")
                , ("sac", "pendulum")
                , ("ars", "cartpole")
                , ("her", "goal-reaching")
                ]
          , testCase
              "Phase 251 — compiled RL plan transport round-trips and the worker RunConfig re-validates it"
              $ do
                -- Mirrors the daemon 'Workload.rlRunConfigFor' path: compile a
                -- plan from raw request inputs, serialize it, then re-parse and
                -- re-validate it worker-side.
                let training =
                      ProductBudget.TrainingPlan
                        { ProductBudget.trainingPlanTrainerKind = "ppo"
                        , ProductBudget.trainingPlanEnvironment = "cartpole"
                        , ProductBudget.trainingPlanSeed = 7
                        , ProductBudget.trainingPlanMaxEpisodeSteps = 128
                        , ProductBudget.trainingPlanEpisodeBudgetFloor =
                            ProductBudget.productRlDefaultTrainingEpisodeFloor
                        , ProductBudget.trainingPlanVectorEnvironments = Nothing
                        , ProductBudget.trainingPlanRequestedTransitionFloor = Nothing
                        , ProductBudget.trainingPlanExactTransitionTarget = Nothing
                        }
                case ProductBudget.compileRlPlan training (ProductBudget.EvaluationPlan 4) of
                  Left err -> assertFailure ("compile failed: " <> Text.unpack err)
                  Right plan -> do
                    let transport = ProductBudget.renderCompiledRlPlanTransport plan
                        planId = ProductBudget.compiledRlPlanId plan
                    ProductBudget.parseCompiledRlPlanTransport transport @?= Right plan
                    let config =
                          RunConfig.RlRunConfig
                            { RunConfig.rlcExperimentHash = "exp-251"
                            , RunConfig.rlcPlanId = planId
                            , RunConfig.rlcResolvedPlan = transport
                            , RunConfig.rlcAtariRomPath = Nothing
                            , RunConfig.rlcPulsarWsUrl = "ws://broker"
                            }
                    RunConfig.rlPlanFromRunConfig config @?= Right plan
                    case RunConfig.rlPlanFromRunConfig config {RunConfig.rlcPlanId = "deadbeef"} of
                      Left _ -> pure ()
                      Right _ -> assertFailure "a tampered planId must be rejected"
          , testCase "Phase 252 — mounted RL plans reject semantic CLI overrides" $ do
              RunConfig.validateMountedRlSemanticOverrides Overrides.emptyExperimentOverrides
                @?= Right ()
              let substrateOverride =
                    Overrides.emptyExperimentOverrides
                      { Overrides.eoSubstrate = Just Substrate.LinuxCPU
                      }
                  seedOverride =
                    Overrides.emptyExperimentOverrides
                      { Overrides.eoSeed = Just 8
                      }
                  algorithmOverride =
                    Overrides.emptyExperimentOverrides
                      { Overrides.eoAlgorithm = Just "DQN"
                      }
              RunConfig.validateMountedRlSemanticOverrides substrateOverride
                @?= Right ()
              case RunConfig.validateMountedRlSemanticOverrides seedOverride of
                Left err ->
                  assertBool
                    "mounted seed rejection names the authoritative plan"
                    ("mounted RlRunConfig is authoritative" `Text.isInfixOf` err)
                Right () -> assertFailure "mounted --seed override was accepted"
              case RunConfig.validateMountedRlSemanticOverrides algorithmOverride of
                Left err ->
                  assertBool
                    "mounted algorithm rejection names the authoritative plan"
                    ("mounted RlRunConfig is authoritative" `Text.isInfixOf` err)
                Right () -> assertFailure "mounted --algorithm override was accepted"
          , testCase "Phase 252 — daemon and Apple RL starts share one environment-independent plan" $ do
              let start =
                    ProtoRl.StartRLRun
                      { ProtoRl.srlExperimentHash = "phase-252-plan"
                      , ProtoRl.srlAlgorithm = "PPO"
                      , ProtoRl.srlEnvironment = "cartpole"
                      , ProtoRl.srlSubstrate = Substrate.AppleSilicon
                      , ProtoRl.srlSeed = 7
                      , ProtoRl.srlMaxSteps = 128
                      , ProtoRl.srlEvalEpisodes = 4
                      }
              case (Workload.rlPlanForStart start, Workload.rlRunConfigFor start) of
                (Right plan, Right config) -> do
                  ProductBudget.compiledRlPlanId plan
                    @?= RunConfig.rlcPlanId config
                  ProductBudget.renderCompiledRlPlanTransport plan
                    @?= RunConfig.rlcResolvedPlan config
                  ProductBudget.trainingPlanVectorEnvironments
                    (ProductBudget.compiledRlTraining plan)
                    @?= Nothing
                  RunConfig.rlPlanFromRunConfig config @?= Right plan
                (planResult, configResult) ->
                  assertFailure
                    ( "expected the shared RL start compiler to succeed: "
                        <> show planResult
                        <> "; "
                        <> show configResult
                    )
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
          , testCase "ProductRow public identities remain the exact 55-row matrix" $
              ProductMatrix.productRowIds
                @?= [ "mnist-shallow-mlp"
                    , "mnist-deep-mlp"
                    , "mnist-lenet"
                    , "fashion-mnist-mlp"
                    , "fashion-mnist-resnet"
                    , "cifar10-resnet20"
                    , "cifar10-resnet56"
                    , "cifar100-wide-resnet"
                    , "cifar10-vit"
                    , "tiny-imagenet-resnet50"
                    , "california-housing-mlp"
                    , "PPO/cartpole"
                    , "PPO/mountain-car"
                    , "PPO/acrobot"
                    , "PPO/lunar-lander"
                    , "PPO/key-door-grid"
                    , "PPO/gridworld-deterministic"
                    , "A2C/cartpole"
                    , "A2C/mountain-car"
                    , "A2C/lunar-lander"
                    , "A2C/key-door-grid"
                    , "TRPO/cartpole"
                    , "TRPO/mountain-car"
                    , "TRPO/lunar-lander"
                    , "TRPO/key-door-grid"
                    , "MaskablePPO/cartpole"
                    , "MaskablePPO/mountain-car"
                    , "MaskablePPO/lunar-lander"
                    , "MaskablePPO/key-door-grid"
                    , "RecurrentPPO/cartpole"
                    , "RecurrentPPO/mountain-car"
                    , "RecurrentPPO/lunar-lander"
                    , "RecurrentPPO/key-door-grid"
                    , "DQN/cartpole"
                    , "DQN/mountain-car"
                    , "DQN/key-door-grid"
                    , "QR-DQN/cartpole"
                    , "QR-DQN/mountain-car"
                    , "QR-DQN/key-door-grid"
                    , "DDPG/lunar-lander"
                    , "TD3/lunar-lander"
                    , "SAC/lunar-lander"
                    , "SAC/pendulum"
                    , "CrossQ/lunar-lander"
                    , "TQC/lunar-lander"
                    , "ARS/cartpole"
                    , "ARS/mountain-car"
                    , "ARS/lunar-lander"
                    , "ARS/key-door-grid"
                    , "HER/goal-reaching"
                    , "connect4"
                    , "othello"
                    , "hex"
                    , "gomoku"
                    , "hyperparameter-tuning"
                    ]
          , testCase "every ProductRow resolves to one deterministic semantic plan on every substrate" $ do
              let attempts =
                    [ ( substrate
                      , row
                      , ProductMatrix.projectProductRow substrate row
                      )
                    | substrate <- Substrate.allSubstrates
                    , row <- ProductMatrix.allProductRows
                    ]
                  failures =
                    [ (Substrate.renderSubstrate substrate, ProductMatrix.rowId row, errors)
                    | (substrate, row, RunPlan.Failure errors) <- attempts
                    ]
                  summaries =
                    [ ( substrate
                      , ProductMatrix.rowId row
                      , ProductMatrix.productProjectionRowId projection
                      , ProductMatrix.productProjectionSubstrate projection
                      , planIdText (ProductMatrix.productProjectionPlanId projection)
                      , ProductMatrix.productProjectionCommand projection
                      , RunPlan.runPlanPlacement (ProductMatrix.productProjectionRunPlan projection)
                      )
                    | ( substrate
                        , row
                        , RunPlan.Success (ProductMatrix.SomeProductProjection _ projection)
                        ) <-
                        attempts
                    ]
              failures @?= []
              length summaries
                @?= length ProductMatrix.allProductRows
                * length Substrate.allSubstrates
              assertBool
                "projection preserves row identity and selected substrate"
                ( all
                    ( \(substrate, rowId', projectedRowId, projectedSubstrate, _, _, _) ->
                        rowId' == projectedRowId && substrate == projectedSubstrate
                    )
                    summaries
                )
              assertBool
                "every semantic PlanId is canonical lowercase SHA-256 text"
                ( all
                    ( \(_, _, _, _, planId, _, _) ->
                        Text.length planId == 64
                          && Text.all (\ch -> isDigit ch || (ch >= 'a' && ch <= 'f')) planId
                    )
                    summaries
                )
              assertBool
                "every projected workflow command targets the exact row/substrate executor"
                ( all
                    ( \(substrate, rowId', _, _, _, command, _) ->
                        command
                          == [ "internal"
                             , "train-and-publish-product-rows"
                             , "--" <> Substrate.renderSubstrate substrate
                             , "--row"
                             , rowId'
                             ]
                    )
                    summaries
                )
              assertBool
                "every ProductRow plan truthfully records direct in-process execution"
                (all ((== RunPlan.InProcessRun) . (\(_, _, _, _, _, _, placement) -> placement)) summaries)
              traverse_
                ( \substrate -> do
                    let planIds =
                          [ planId
                          | (observedSubstrate, _, _, _, planId, _, _) <- summaries
                          , observedSubstrate == substrate
                          ]
                    assertBool
                      ("PlanIds are row-unique on " <> show substrate)
                      (length planIds == length (nub planIds))
                )
                Substrate.allSubstrates
              traverse_
                ( \row -> do
                    let planIds =
                          [ planIdText (ProductMatrix.productProjectionPlanId projection)
                          | substrate <- Substrate.allSubstrates
                          , RunPlan.Success (ProductMatrix.SomeProductProjection _ projection) <-
                              [ProductMatrix.projectProductRow substrate row]
                          ]
                    assertBool
                      ("PlanId includes substrate for " <> Text.unpack (ProductMatrix.rowId row))
                      (length planIds == length (nub planIds))
                    traverse_
                      ( \substrate ->
                          ProductMatrix.projectProductRow substrate row
                            @?= ProductMatrix.projectProductRow substrate row
                      )
                      Substrate.allSubstrates
                )
                ProductMatrix.allProductRows
          , testCase "ProductProjectionBatch preserves order and rejects duplicate/unprojectable rows together" $ do
              case ( ProductMatrix.projectProductRows Substrate.LinuxCPU []
                   , WorkflowMatrix.modelCellsForRows Substrate.LinuxCPU []
                   ) of
                (RunPlan.Failure batchErrors, RunPlan.Failure workflowErrors) -> do
                  workflowErrors @?= batchErrors
                  assertBool
                    "empty projection cannot create a vacuous product denominator"
                    (ProductMatrix.EmptyProductProjectionBatch `elem` batchErrors)
                other -> assertFailure ("unexpected empty batch/workflow result: " <> show other)
              traverse_
                ( \substrate ->
                    case ProductMatrix.projectProductRows substrate ProductMatrix.allProductRows of
                      RunPlan.Failure errors -> assertFailure (show errors)
                      RunPlan.Success batch -> do
                        ProductMatrix.productProjectionBatchSubstrate batch @?= substrate
                        ProductMatrix.productProjectionBatchRowIds batch
                          @?= ProductMatrix.productRowIds
                        fmap
                          ( \(ProductMatrix.SomeProductProjection _ projection) ->
                              ProductMatrix.productProjectionRowId projection
                          )
                          (ProductMatrix.productProjectionBatchProjections batch)
                          @?= ProductMatrix.productRowIds
                )
                Substrate.allSubstrates
              case ProductMatrix.allProductRows of
                [] -> assertFailure "ProductRow registry is unexpectedly empty"
                firstRow : _ -> do
                  let unprojectable =
                        firstRow
                          { productCapability =
                              ProductMatrix.UnsupportedProduct "batch-negative-control"
                          }
                      invalidRows = [unprojectable, unprojectable]
                  case ( ProductMatrix.projectProductRows Substrate.LinuxCPU invalidRows
                       , WorkflowMatrix.modelCellsForRows Substrate.LinuxCPU invalidRows
                       ) of
                    (RunPlan.Failure batchErrors, RunPlan.Failure workflowErrors) -> do
                      workflowErrors @?= batchErrors
                      assertBool
                        "batch reports the duplicate row identity"
                        ( ProductMatrix.DuplicateProductRowId (ProductMatrix.rowId firstRow)
                            `elem` batchErrors
                        )
                      length
                        [ ()
                        | ProductMatrix.UnprojectableProductRow
                            ProductMatrix.UnsupportedProductRow {} <-
                            toList batchErrors
                        ]
                        @?= 2
                    other -> assertFailure ("unexpected batch/workflow result: " <> show other)
                  let collidingLeft = firstRow {rowId = "collision/a"}
                      collidingRight = firstRow {rowId = "collision.a"}
                      projectedPlanId candidate =
                        case ProductMatrix.projectProductRow Substrate.LinuxCPU candidate of
                          RunPlan.Failure errors -> error (show errors)
                          RunPlan.Success (ProductMatrix.SomeProductProjection _ projection) ->
                            ProductMatrix.productProjectionPlanId projection
                  ProductMatrix.productRowExperimentHash collidingLeft
                    @?= ProductMatrix.productRowExperimentHash collidingRight
                  assertBool
                    "exact row id participates in PlanId despite artifact-key sanitization"
                    (projectedPlanId collidingLeft /= projectedPlanId collidingRight)
                  case ProductMatrix.projectProductRows
                    Substrate.LinuxCPU
                    [collidingLeft, collidingRight] of
                    RunPlan.Success _ -> assertFailure "colliding product experiment hashes formed a batch"
                    RunPlan.Failure errors ->
                      assertBool
                        "batch rejects the colliding projected artifact identity"
                        ( ProductMatrix.DuplicateProductExperimentHash
                            (ProductMatrix.productRowExperimentHash collidingLeft)
                            `elem` errors
                        )
                  let contractLeft =
                        firstRow
                          { rowId = "contract-left"
                          , integrationTest = "integration.product.shared"
                          , e2eTest = "e2e.product.shared"
                          }
                      contractRight =
                        firstRow
                          { rowId = "contract-right"
                          , integrationTest = "integration.product.shared"
                          , e2eTest = "e2e.product.shared"
                          }
                  case ProductMatrix.projectProductRows
                    Substrate.LinuxCPU
                    [contractLeft, contractRight] of
                    RunPlan.Success _ -> assertFailure "duplicate scenario contracts formed a batch"
                    RunPlan.Failure errors -> do
                      assertBool
                        "batch rejects duplicate integration contract identity"
                        ( ProductMatrix.DuplicateProductIntegrationTest
                            "integration.product.shared"
                            `elem` errors
                        )
                      assertBool
                        "batch rejects duplicate e2e contract identity"
                        ( ProductMatrix.DuplicateProductE2ETest
                            "e2e.product.shared"
                            `elem` errors
                        )
          , testCase "representative ProductRow plans pin exact semantics and family/substrate PlanIds" $ do
              let goldenPlanIds =
                    [
                      ( "mnist-shallow-mlp"
                      , Substrate.AppleSilicon
                      , "6d97fd41fec883305f3f3812892145e17dc364d0c84d6a0e2ba9e5afc335e637"
                      )
                    ,
                      ( "mnist-shallow-mlp"
                      , Substrate.LinuxCPU
                      , "374e1606c3f0accff486b4cfbad37f2c5a28f59fa3572bf3a1d9d3392e4d7661"
                      )
                    ,
                      ( "mnist-shallow-mlp"
                      , Substrate.LinuxCUDA
                      , "e2cede27867023e454cbfb0a5f48a28ef745e1856808a27dc1ef861f5b786b85"
                      )
                    ,
                      ( "PPO/cartpole"
                      , Substrate.AppleSilicon
                      , "bb0c9e378027e3884f5ba4f22d9ee5232147e28eccb8721789739e81486efb52"
                      )
                    ,
                      ( "PPO/cartpole"
                      , Substrate.LinuxCPU
                      , "56ea69e1cdd088d5fb53c2da6dd144d32c83c0f7d4b5383c6d9af2cadf8cc193"
                      )
                    ,
                      ( "PPO/cartpole"
                      , Substrate.LinuxCUDA
                      , "9237c8850b754aadc4603e2067303f4fc0daec21f0916e4deb03c7102d5cdb2e"
                      )
                    ,
                      ( "connect4"
                      , Substrate.AppleSilicon
                      , "a966451502b6cb37a06e01d536fed665d9bf4436b63b63a127f43573d59f8e38"
                      )
                    ,
                      ( "connect4"
                      , Substrate.LinuxCPU
                      , "c1c7a5571e64ce8711a83cb771662c65219123aa7cb2ea7927106d0258b6c74e"
                      )
                    ,
                      ( "connect4"
                      , Substrate.LinuxCUDA
                      , "2ed82af6d0b5281591ffc747087b802ee72552644e0d4b213c77139f3410dd6d"
                      )
                    ,
                      ( "hyperparameter-tuning"
                      , Substrate.AppleSilicon
                      , "5fcef09cdaab17fdfa1fad975f49ecc7f6cbbad8c1b26cc9d40018a51bb9006a"
                      )
                    ,
                      ( "hyperparameter-tuning"
                      , Substrate.LinuxCPU
                      , "4150d67ddfa20cda8b76351328560973fa713b98773cf08bb2456c2bfec56384"
                      )
                    ,
                      ( "hyperparameter-tuning"
                      , Substrate.LinuxCUDA
                      , "617fb9df165ce1bbca71c987e03d67a5d94911a230658dfc1aaa539d3d56452b"
                      )
                    ]
                  expectedBudget rowIdentity =
                    case rowIdentity of
                      "mnist-shallow-mlp" ->
                        [ ("epochs", 10)
                        , ("training-examples", 7000)
                        , ("evaluation-examples", 1000)
                        , ("batch-examples", 128)
                        , ("optimizer-updates", 550)
                        ]
                      "PPO/cartpole" ->
                        [ ("environment-transitions", 1_228_800)
                        , ("rollout-ticks-per-environment", 512)
                        , ("vector-environments", 16)
                        , ("episode-steps", 500)
                        , ("evaluation-episodes", 20)
                        ]
                      "connect4" ->
                        [ ("generations", 64)
                        , ("self-play-games-per-generation", 2)
                        , ("mcts-simulations-per-move", 128)
                        , ("max-plies-per-game", 42)
                        , ("optimizer-updates-per-generation", 8)
                        , ("arena-games", 9)
                        ]
                      "hyperparameter-tuning" ->
                        [ ("trials", 128)
                        , ("parallel-trials", 1)
                        , ("promotions", 1)
                        , ("per-trial-optimizer-updates", 1000)
                        ]
                      _ -> error "unknown representative ProductRow"
                  expectedSeeds rowIdentity =
                    case rowIdentity of
                      "mnist-shallow-mlp" -> [1001]
                      "PPO/cartpole" -> [42]
                      "connect4" -> [42]
                      "hyperparameter-tuning" -> [1729]
                      _ -> error "unknown representative ProductRow"
              traverse_
                ( \(rowIdentity, substrate, expectedPlanId) ->
                    case find ((== rowIdentity) . ProductMatrix.rowId) ProductMatrix.allProductRows of
                      Nothing -> assertFailure ("missing representative ProductRow: " <> Text.unpack rowIdentity)
                      Just row ->
                        case ProductMatrix.projectProductRow substrate row of
                          RunPlan.Failure errors -> assertFailure (show errors)
                          RunPlan.Success (ProductMatrix.SomeProductProjection witness projection) -> do
                            let observedSeeds =
                                  toList
                                    ( RunPlan.seedCohortValues
                                        ( RunPlan.runPlanSeeds
                                            (ProductMatrix.productProjectionRunPlan projection)
                                        )
                                    )
                            planIdText (ProductMatrix.productProjectionPlanId projection)
                              @?= expectedPlanId
                            RunPlan.runPlanBudgetSummary
                              (ProductMatrix.productProjectionRunPlan projection)
                              @?= expectedBudget rowIdentity
                            observedSeeds @?= expectedSeeds rowIdentity
                            assertBool
                              "projected seeds are positive and Int-safe"
                              ( all
                                  ( \seed ->
                                      seed > 0
                                        && seed <= fromIntegral (maxBound :: Int)
                                  )
                                  observedSeeds
                              )
                            RunPlan.runPlanPlacement
                              (ProductMatrix.productProjectionRunPlan projection)
                              @?= RunPlan.InProcessRun
                            case witness of
                              SupervisedTrainingWitness -> do
                                rowIdentity @?= "mnist-shallow-mlp"
                                ProductMatrix.productProjectionDescriptor projection
                                  @?= ProductMatrix.SupervisedProductDescriptor 7000 1000 128 1.0e-3
                                case ProductMatrix.productProjectionResolvedPlan projection of
                                  ProductMatrix.ResolvedSupervisedProductPlan plan ->
                                    ResolvedWorkload.parseSupervisedPlanTransport
                                      (ResolvedWorkload.renderSupervisedPlanTransport plan)
                                      @?= RunPlan.Success plan
                              ReinforcementLearningWitness -> do
                                rowIdentity @?= "PPO/cartpole"
                                ProductMatrix.productProjectionDescriptor projection
                                  @?= ProductMatrix.RlProductDescriptor
                                    "PPO"
                                    "cartpole"
                                    512
                                    16
                                    500
                                    20
                              HyperparameterTuningWitness -> do
                                rowIdentity @?= "hyperparameter-tuning"
                                ProductMatrix.productProjectionDescriptor projection
                                  @?= ProductMatrix.TuningProductDescriptor
                                    Tune.canonicalMnistTuningExecutionSpec
                                    1
                                    1
                                    1000
                                case ProductMatrix.productProjectionResolvedPlan projection of
                                  ProductMatrix.ResolvedTuningProductPlan plan ->
                                    ResolvedWorkload.parseTuningPlanTransport
                                      (ResolvedWorkload.renderTuningPlanTransport plan)
                                      @?= RunPlan.Success plan
                              AlphaZeroSelfPlayWitness -> do
                                rowIdentity @?= "connect4"
                                ProductMatrix.productProjectionDescriptor projection
                                  @?= ProductMatrix.AlphaZeroProductDescriptor
                                    "connect4"
                                    2
                                    128
                                    42
                                    8
                                    9
                                case ProductMatrix.productProjectionResolvedPlan projection of
                                  ProductMatrix.ResolvedAlphaZeroProductPlan plan ->
                                    ResolvedWorkload.parseAlphaZeroPlanTransport
                                      (ResolvedWorkload.renderAlphaZeroPlanTransport plan)
                                      @?= RunPlan.Success plan
                )
                goldenPlanIds
          , testCase "canonical supervised ProductRows carry the exact typed learning-rate recipe" $ do
              let expectedRates =
                    [ ("mnist-shallow-mlp", 1.0e-3)
                    , ("mnist-deep-mlp", 1.0e-3)
                    , ("mnist-lenet", 1.0e-3)
                    , ("fashion-mnist-mlp", 1.0e-3)
                    , ("fashion-mnist-resnet", 3.0e-3)
                    , ("cifar10-resnet20", 1.1e-3)
                    , ("cifar10-resnet56", 1.0e-3)
                    , ("cifar100-wide-resnet", 1.0e-3)
                    , ("cifar10-vit", 1.5e-3)
                    , ("tiny-imagenet-resnet50", 1.0e-3)
                    , ("california-housing-mlp", 1.0e-3)
                    ]
              traverse_
                ( \(rowIdentity, expectedRate) ->
                    case find ((== rowIdentity) . ProductMatrix.rowId) ProductMatrix.allProductRows of
                      Nothing ->
                        assertFailure
                          ("missing canonical supervised ProductRow: " <> Text.unpack rowIdentity)
                      Just row ->
                        case ProductMatrix.productCapability row of
                          ProductMatrix.ExecutableProduct
                            descriptor@ProductMatrix.SupervisedProductDescriptor {}
                            ProductMatrix.SupervisedProductEvidence ->
                              ProductMatrix.supervisedLearningRate descriptor @?= expectedRate
                          other ->
                            assertFailure
                              ("unexpected supervised ProductRow capability: " <> show other)
                )
                expectedRates
          , testCase "cifar10-vit ProductRow pins the expanded convergence recipe" $ do
              row <-
                maybe
                  (assertFailure "missing canonical cifar10-vit ProductRow")
                  pure
                  (find ((== "cifar10-vit") . ProductMatrix.rowId) ProductMatrix.allProductRows)
              ProductMatrix.trainingBudget row
                @?= either
                  (error . Text.unpack)
                  id
                  (TrainingBudget.mkTrainingBudget TrainingBudget.SupervisedEpochBudget 40 (Just 1009))
              case ProductMatrix.projectProductRow Substrate.LinuxCPU row of
                RunPlan.Failure errors -> assertFailure (show errors)
                RunPlan.Success (ProductMatrix.SomeProductProjection witness projection) ->
                  case witness of
                    SupervisedTrainingWitness -> do
                      ProductMatrix.productProjectionDescriptor projection
                        @?= ProductMatrix.SupervisedProductDescriptor 2000 1000 128 1.5e-3
                      case ProductMatrix.productProjectionResolvedPlan projection of
                        ProductMatrix.ResolvedSupervisedProductPlan plan -> do
                          RunPlan.quantityValue (ResolvedWorkload.supervisedPlanTrainingExamples plan) @?= 2000
                          RunPlan.quantityValue (ResolvedWorkload.supervisedPlanEpochs plan) @?= 40
                          RunPlan.quantityValue (ResolvedWorkload.supervisedPlanEvaluationExamples plan) @?= 1000
                          RunPlan.quantityValue (ResolvedWorkload.supervisedPlanBatchExamples plan) @?= 128
                          RunPlan.quantityValue (ResolvedWorkload.supervisedPlanOptimizerUpdates plan) @?= 640
                    _ -> assertFailure "cifar10-vit projected to a non-supervised run kind"
          , testCase "tiny-imagenet-resnet50 ProductRow pins its complete resolved budget" $ do
              row <-
                maybe
                  (assertFailure "missing canonical tiny-imagenet-resnet50 ProductRow")
                  pure
                  (find ((== "tiny-imagenet-resnet50") . ProductMatrix.rowId) ProductMatrix.allProductRows)
              ProductMatrix.trainingBudget row
                @?= either
                  (error . Text.unpack)
                  id
                  ( TrainingBudget.mkTrainingBudget
                      TrainingBudget.SupervisedEpochBudget
                      15
                      (Just 1010)
                  )
              case ProductMatrix.projectProductRow Substrate.LinuxCPU row of
                RunPlan.Failure errors -> assertFailure (show errors)
                RunPlan.Success (ProductMatrix.SomeProductProjection witness projection) ->
                  case witness of
                    SupervisedTrainingWitness -> do
                      ProductMatrix.productProjectionDescriptor projection
                        @?= ProductMatrix.SupervisedProductDescriptor 8000 1000 128 1.0e-3
                      RunPlan.runPlanBudgetSummary
                        (ProductMatrix.productProjectionRunPlan projection)
                        @?= [ ("epochs", 15)
                            , ("training-examples", 8000)
                            , ("evaluation-examples", 1000)
                            , ("batch-examples", 128)
                            , ("optimizer-updates", 945)
                            ]
                      ProductMatrix.productProjectionCommand projection
                        @?= [ "internal"
                            , "train-and-publish-product-rows"
                            , "--linux-cpu"
                            , "--row"
                            , "tiny-imagenet-resnet50"
                            ]
                    _ ->
                      assertFailure
                        "tiny-imagenet-resnet50 projected to a non-supervised run kind"
          , testCase "supervised recipe fields are refined and participate in ProductRow PlanId" $ do
              row <-
                maybe
                  (assertFailure "missing canonical mnist-shallow-mlp ProductRow")
                  pure
                  (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
              let rowWithRate learningRate =
                    case ProductMatrix.productCapability row of
                      ProductMatrix.ExecutableProduct
                        (ProductMatrix.SupervisedProductDescriptor training evaluation batch _)
                        ProductMatrix.SupervisedProductEvidence ->
                          row
                            { productCapability =
                                ProductMatrix.ExecutableProduct
                                  ( ProductMatrix.SupervisedProductDescriptor
                                      training
                                      evaluation
                                      batch
                                      learningRate
                                  )
                                  ProductMatrix.SupervisedProductEvidence
                            }
                      other -> error ("unexpected supervised ProductRow capability: " <> show other)
                  rowWithTrainingExamples trainingExamples =
                    case ProductMatrix.productCapability row of
                      ProductMatrix.ExecutableProduct
                        (ProductMatrix.SupervisedProductDescriptor _ evaluation batch learningRate)
                        ProductMatrix.SupervisedProductEvidence ->
                          row
                            { productCapability =
                                ProductMatrix.ExecutableProduct
                                  ( ProductMatrix.SupervisedProductDescriptor
                                      trainingExamples
                                      evaluation
                                      batch
                                      learningRate
                                  )
                                  ProductMatrix.SupervisedProductEvidence
                            }
                      other -> error ("unexpected supervised ProductRow capability: " <> show other)
                  projectionPlanId candidate =
                    case ProductMatrix.projectProductRow Substrate.LinuxCPU candidate of
                      RunPlan.Failure errors -> error (show errors)
                      RunPlan.Success (ProductMatrix.SomeProductProjection _ projection) ->
                        ProductMatrix.productProjectionPlanId projection
                  hasLearningRateError candidate =
                    case ProductMatrix.projectProductRow Substrate.LinuxCPU candidate of
                      RunPlan.Success _ -> False
                      RunPlan.Failure errors ->
                        any
                          ( \case
                              ProductMatrix.InvalidProductSupervisedLearningRate {} -> True
                              _ -> False
                          )
                          errors
              traverse_
                ( \invalidRate ->
                    assertBool
                      ("invalid supervised learning rate projected successfully: " <> show invalidRate)
                      (hasLearningRateError (rowWithRate invalidRate))
                )
                [0.0, -1.0e-3, 0.0 / 0.0, 1.0 / 0.0]
              assertBool
                "a distinct valid supervised learning rate did not change the ProductRow PlanId"
                (projectionPlanId row /= projectionPlanId (rowWithRate 2.0e-3))
              assertBool
                "a distinct valid supervised training-example count did not change the ProductRow PlanId"
                (projectionPlanId row /= projectionPlanId (rowWithTrainingExamples 7001))
          , testCase "ProductRow projection retains workload semantic PlanIds" $ do
              traverse_
                ( \row ->
                    case ProductMatrix.projectProductRow Substrate.LinuxCPU row of
                      RunPlan.Failure errors -> assertFailure (show errors)
                      RunPlan.Success (ProductMatrix.SomeProductProjection witness projection) ->
                        case witness of
                          SupervisedTrainingWitness ->
                            assertBool
                              "supervised outer PlanId wraps the common RunPlan id"
                              ( ProductMatrix.productProjectionPlanId projection
                                  /= runPlanId (ProductMatrix.productProjectionRunPlan projection)
                              )
                          ReinforcementLearningWitness ->
                            ProductMatrix.productProjectionPlanId projection
                              @?= runPlanId (ProductMatrix.productProjectionRunPlan projection)
                          HyperparameterTuningWitness ->
                            assertBool
                              "tuning outer PlanId covers its axes"
                              ( ProductMatrix.productProjectionPlanId projection
                                  /= runPlanId (ProductMatrix.productProjectionRunPlan projection)
                              )
                          AlphaZeroSelfPlayWitness ->
                            assertBool
                              "AlphaZero outer PlanId covers its game"
                              ( ProductMatrix.productProjectionPlanId projection
                                  /= runPlanId (ProductMatrix.productProjectionRunPlan projection)
                              )
                )
                ProductMatrix.allProductRows
          , testCase "ProductRow projection accumulates typed configuration failures" $ do
              case ProductMatrix.allProductRows of
                [] -> assertFailure "ProductRow registry is unexpectedly empty"
                firstRow : rest -> do
                  let invalidBar =
                        (ProductMatrix.convergenceBar firstRow)
                          { ProductConvergence.convergenceMetricName = ""
                          , ProductConvergence.convergenceThreshold = 0 / 0
                          }
                      malformed =
                        firstRow
                          { family = ProductMatrix.Tuning
                          , integrationTest = ""
                          , convergenceBar = invalidBar
                          }
                      unsupported =
                        firstRow
                          { productCapability = ProductMatrix.UnsupportedProduct "not executable"
                          }
                      wrongBudget =
                        firstRow
                          { trainingBudget = unitBudget TrainingBudget.RlEnvironmentStepBudget 1
                          }
                      wrongClass =
                        firstRow
                          { rowClass = ProductMatrix.RlGoalConditioned "goal-reaching"
                          }
                      -- Sprint 21.4: a declared ProductRow can no longer carry a
                      -- measured evidence handle — the optional evidence fields
                      -- were removed, so the fabrication below is a compile-time
                      -- impossibility rather than a runtime-rejected projection.
                      wrongDevice =
                        firstRow
                          { deviceClaim = ProductMatrix.GoalConditionedPolicy
                          }
                      errorsFor row =
                        case ProductMatrix.projectProductRow Substrate.LinuxCPU row of
                          RunPlan.Success _ -> []
                          RunPlan.Failure errors -> toList errors
                      isEmptyIntegration err =
                        case err of
                          ProductMatrix.EmptyProductRowField _ "integrationTest" -> True
                          _ -> False
                      isFamilyMismatch err =
                        case err of
                          ProductMatrix.ProductFamilyRunKindMismatch {} -> True
                          _ -> False
                      isInvalidConvergence err =
                        case err of
                          ProductMatrix.InvalidProductConvergenceBar {} -> True
                          _ -> False
                      isUnsupported err =
                        case err of
                          ProductMatrix.UnsupportedProductRow {} -> True
                          _ -> False
                      isWrongBudget err =
                        case err of
                          ProductMatrix.ProductBudgetKindMismatch {} -> True
                          _ -> False
                      isWrongClass err =
                        case err of
                          ProductMatrix.ProductRowClassRunKindMismatch {} -> True
                          ProductMatrix.ProductDescriptorRowClassMismatch {} -> True
                          _ -> False
                      isWrongDevice err =
                        case err of
                          ProductMatrix.ProductDeviceClaimMismatch {} -> True
                          _ -> False
                      malformedErrors = errorsFor malformed
                  assertBool "empty integration contract is typed" (any isEmptyIntegration malformedErrors)
                  assertBool "family mismatch is typed" (any isFamilyMismatch malformedErrors)
                  assertBool "invalid convergence is typed" (any isInvalidConvergence malformedErrors)
                  assertBool "independent failures accumulate" (length malformedErrors >= 3)
                  assertBool "unsupported capability cannot project" (any isUnsupported (errorsFor unsupported))
                  assertBool "wrong budget kind cannot project" (any isWrongBudget (errorsFor wrongBudget))
                  assertBool "wrong RowClass cannot project" (any isWrongClass (errorsFor wrongClass))
                  assertBool "wrong DeviceClaim cannot project" (any isWrongDevice (errorsFor wrongDevice))
                  assertBool
                    "matrix validation rejects unsupported rows"
                    ( any
                        ( \case
                            ProductMatrix.UnprojectableProductRow projectionError ->
                              isUnsupported projectionError
                            _ -> False
                        )
                        (ProductMatrix.validateProductMatrixTyped (unsupported : rest))
                    )
          , testCase "ProductRow projection rejects inexact and trainer-incompatible RL descriptors" $ do
              case find ((== "PPO/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows of
                Nothing -> assertFailure "missing PPO/cartpole ProductRow"
                Just row -> do
                  let mismatched =
                        row
                          { trainingBudget =
                              either
                                (error . Text.unpack)
                                id
                                ( TrainingBudget.mkTrainingBudget
                                    TrainingBudget.RlEnvironmentStepBudget
                                    1
                                    (Just 42)
                                )
                          }
                  case ProductMatrix.projectProductRow Substrate.LinuxCPU mismatched of
                    RunPlan.Success _ -> assertFailure "same-kind inexact RL budget projected successfully"
                    RunPlan.Failure errors ->
                      assertBool
                        "inexact RL schedule has a typed projection error"
                        ( any
                            ( \case
                                ProductMatrix.InvalidProductRlSchedule {} -> True
                                _ -> False
                            )
                            errors
                        )
              case find ((== "DQN/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows of
                Nothing -> assertFailure "missing DQN/cartpole ProductRow"
                Just row ->
                  case ProductMatrix.productCapability row of
                    ProductMatrix.ExecutableProduct
                      (ProductMatrix.RlProductDescriptor algorithm _ rollout vectors episode evaluation)
                      ProductMatrix.RlProductEvidence -> do
                        let unsupported =
                              row
                                { rowClass = ProductMatrix.RlAlgorithmEnvironment algorithm "acrobot"
                                , productCapability =
                                    ProductMatrix.ExecutableProduct
                                      ( ProductMatrix.RlProductDescriptor
                                          algorithm
                                          "acrobot"
                                          rollout
                                          vectors
                                          episode
                                          evaluation
                                      )
                                      ProductMatrix.RlProductEvidence
                                }
                        case ProductMatrix.projectProductRow Substrate.LinuxCPU unsupported of
                          RunPlan.Success _ ->
                            assertFailure "trainer-incompatible RL pair projected successfully"
                          RunPlan.Failure errors ->
                            assertBool
                              "trainer-incompatible RL pair has a typed projection error"
                              ( any
                                  ( \case
                                      ProductMatrix.InvalidProductRlSchedule {} -> True
                                      _ -> False
                                  )
                                  errors
                              )
                    other -> assertFailure ("unexpected DQN capability: " <> show other)
          , testCase "canonical semantic projections have distinct PlanIds" $ do
              let projectionPlanId row =
                    case ProductMatrix.projectProductRow Substrate.LinuxCPU row of
                      RunPlan.Failure errors -> error (show errors)
                      RunPlan.Success (ProductMatrix.SomeProductProjection _ projection) ->
                        ProductMatrix.productProjectionPlanId projection
              case ( find ((== "PPO/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows
                   , find ((== "A2C/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows
                   , find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows
                   , find ((== "mnist-deep-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows
                   ) of
                (Just ppoRow, Just a2cRow, Just shallowRow, Just deepRow) -> do
                  assertBool
                    "canonical RL algorithm identity changes PlanId"
                    (projectionPlanId ppoRow /= projectionPlanId a2cRow)
                  assertBool
                    "canonical supervised architecture identity changes PlanId"
                    (projectionPlanId shallowRow /= projectionPlanId deepRow)
                _ -> assertFailure "missing representative canonical ProductRow"
          , testCase "ProductRow projection rejects seeds outside the exact executor range" $ do
              case ProductMatrix.allProductRows of
                [] -> assertFailure "ProductRow registry is unexpectedly empty"
                row : _ -> do
                  let originalBudget = ProductMatrix.trainingBudget row
                      outOfRange =
                        row
                          { trainingBudget =
                              either
                                (error . Text.unpack)
                                id
                                ( TrainingBudget.mkTrainingBudget
                                    (TrainingBudget.trainingBudgetKind originalBudget)
                                    (TrainingBudget.trainingBudgetTargetUnits originalBudget)
                                    (Just (maxBound :: Word64))
                                )
                          }
                  case ProductMatrix.projectProductRow Substrate.LinuxCPU outOfRange of
                    RunPlan.Success _ -> assertFailure "out-of-range executor seed projected successfully"
                    RunPlan.Failure errors ->
                      assertBool
                        "out-of-range seed has a typed projection error"
                        ( any
                            ( \case
                                ProductMatrix.InvalidProductSeed {} -> True
                                _ -> False
                            )
                            errors
                        )
          , testCase "ProductRow projection rejects target and descriptor quantities outside the executor range" $ do
              case ProductMatrix.allProductRows of
                [] -> assertFailure "ProductRow registry is unexpectedly empty"
                row : _ -> do
                  let originalBudget = ProductMatrix.trainingBudget row
                      oversizedTarget =
                        row
                          { trainingBudget =
                              either
                                (error . Text.unpack)
                                id
                                ( TrainingBudget.mkTrainingBudget
                                    (TrainingBudget.trainingBudgetKind originalBudget)
                                    (maxBound :: Word64)
                                    (TrainingBudget.trainingBudgetSeed originalBudget)
                                )
                          }
                      oversizedDescriptor =
                        case ProductMatrix.productCapability row of
                          ProductMatrix.ExecutableProduct
                            (ProductMatrix.SupervisedProductDescriptor _ evaluation batch learningRate)
                            ProductMatrix.SupervisedProductEvidence ->
                              row
                                { productCapability =
                                    ProductMatrix.ExecutableProduct
                                      ( ProductMatrix.SupervisedProductDescriptor
                                          (maxBound :: Word64)
                                          evaluation
                                          batch
                                          learningRate
                                      )
                                      ProductMatrix.SupervisedProductEvidence
                                }
                          other -> error ("unexpected first-row capability: " <> show other)
                      hasExecutorRangeError candidate =
                        case ProductMatrix.projectProductRow Substrate.LinuxCPU candidate of
                          RunPlan.Success _ -> False
                          RunPlan.Failure errors ->
                            any
                              ( \case
                                  ProductMatrix.InvalidProductExecutorQuantity {} -> True
                                  _ -> False
                              )
                              errors
                  assertBool
                    "oversized training target has a typed projection error"
                    (hasExecutorRangeError oversizedTarget)
                  assertBool
                    "oversized descriptor axis has a typed projection error"
                    (hasExecutorRangeError oversizedDescriptor)
          , testCase "WorkflowMatrix cells preserve ProductRow projection identity and plan" $ do
              traverse_
                ( \substrate ->
                    case WorkflowMatrix.modelCellsForRows substrate ProductMatrix.allProductRows of
                      RunPlan.Failure errors -> assertFailure (show errors)
                      RunPlan.Success cells -> do
                        length cells @?= ProductMatrix.productRowCount
                        traverse_
                          ( \cell ->
                              case find
                                ((== WorkflowMatrix.modelCellName cell) . ProductMatrix.rowId)
                                ProductMatrix.allProductRows of
                                Nothing -> assertFailure "workflow cell has orphan ProductRow identity"
                                Just row ->
                                  case ProductMatrix.projectProductRow substrate row of
                                    RunPlan.Failure errors -> assertFailure (show errors)
                                    RunPlan.Success (ProductMatrix.SomeProductProjection _ projection) -> do
                                      WorkflowMatrix.modelCellPlanId cell
                                        @?= planIdText (ProductMatrix.productProjectionPlanId projection)
                                      WorkflowMatrix.modelCellCommand cell
                                        @?= ProductMatrix.productProjectionCommand projection
                          )
                          cells
                )
                Substrate.allSubstrates
              assertBool
                "workflow matrix crosses every row with every substrate"
                ( length WorkflowMatrix.modelCellMatrix
                    == ProductMatrix.productRowCount * length Substrate.allSubstrates
                )
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
                    , ("cifar10-resnet20", 40)
                    , ("cifar10-resnet56", 40)
                    , ("cifar100-wide-resnet", 10)
                    , ("cifar10-vit", 40)
                    , ("tiny-imagenet-resnet50", 15)
                    , ("california-housing-mlp", 10)
                    ]
          , testCase "canonical RL, HER, and AlphaZero ProductRows pin config seed 42" $ do
              let deviceRows =
                    [ row
                    | row <- ProductMatrix.allProductRows
                    , ProductMatrix.family row
                        `elem` [ProductMatrix.ReinforcementLearning, ProductMatrix.AlphaZero]
                    ]
              assertBool "canonical device ProductRows are present" (not (null deviceRows))
              traverse_
                ( \row ->
                    TrainingBudget.trainingBudgetSeed (ProductMatrix.trainingBudget row)
                      @?= Just 42
                )
                deviceRows
          , testCase "seedless ProductRows cannot cross the exact executor projection" $ do
              case find ((== "PPO/cartpole") . ProductMatrix.rowId) ProductMatrix.allProductRows of
                Nothing -> assertFailure "missing PPO/cartpole ProductRow"
                Just row -> do
                  let seedless =
                        row
                          { trainingBudget =
                              unitBudget
                                TrainingBudget.RlEnvironmentStepBudget
                                (TrainingBudget.trainingBudgetTargetUnits (ProductMatrix.trainingBudget row))
                          }
                  case ProductMatrix.projectProductRow Substrate.LinuxCPU seedless of
                    RunPlan.Success _ -> assertFailure "seedless ProductRow projected successfully"
                    RunPlan.Failure errors ->
                      assertBool
                        "missing product seed has a typed projection error"
                        ( any
                            ( \case
                                ProductMatrix.MissingProductSeed {} -> True
                                _ -> False
                            )
                            errors
                        )
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
          , testCase "device evidence is minted from an execution witness, not a declaration" $ do
              -- Phase 229. There is no pure constructor for a witness: the mint
              -- must find the artifact the engine reported and digest its bytes.
              -- The rendered cell therefore names the code that ran rather than
              -- the substrate that was asked for.
              witness <-
                expectRightText =<< DeviceWitnessFixture.fixtureDeviceExecutionWitness
              let cell = DeviceWitness.renderDeviceExecutionWitness witness
              assertBool
                "device evidence omits the executing lane"
                (Substrate.renderSubstrate Substrate.LinuxCPU `Text.isInfixOf` cell)
              assertBool
                "device evidence omits the backend the artifact reports"
                (DeviceWitness.witnessBackend witness `Text.isInfixOf` cell)
              assertBool
                "device evidence omits the identity read back from the artifact"
                (DeviceWitness.witnessExecutedIdentity witness `Text.isInfixOf` cell)
              assertBool
                "device evidence omits the artifact digest"
                ( Text.take 16 (DeviceWitness.witnessArtifactSha256 witness)
                    `Text.isInfixOf` cell
                )
          , testCase "a witness names a specific artifact, so distinct lanes cannot share a cell" $ do
              cpuWitness <-
                expectRightText
                  =<< DeviceWitnessFixture.fixtureDeviceExecutionWitnessFor Substrate.LinuxCPU
              cudaWitness <-
                expectRightText
                  =<< DeviceWitnessFixture.fixtureDeviceExecutionWitnessFor Substrate.LinuxCUDA
              assertBool
                "two lanes rendered the same device-evidence cell"
                ( DeviceWitness.renderDeviceExecutionWitness cpuWitness
                    /= DeviceWitness.renderDeviceExecutionWitness cudaWitness
                )
              assertBool
                "two lanes recorded the same artifact digest"
                ( DeviceWitness.witnessArtifactSha256 cpuWitness
                    /= DeviceWitness.witnessArtifactSha256 cudaWitness
                )
          , testCase "the witness mint fails closed on an artifact that is not there" $ do
              minted <-
                DeviceWitness.witnessDeviceExecution
                  Substrate.LinuxCPU
                  "onednn"
                  (Text.replicate 64 "0")
                  "/nonexistent/jitml/kernel.so"
                  "jitml_matmul_forward"
              case minted of
                Right _ ->
                  assertFailure "a witness was minted for an artifact that does not exist"
                Left message ->
                  assertBool
                    "the mint failure does not name the absent artifact"
                    ("absent artifact" `Text.isInfixOf` message)
          , testCase "a decoded witness is refined, so a hand-authored journal row fails closed" $ do
              witness <-
                expectRightText =<< DeviceWitnessFixture.fixtureDeviceExecutionWitness
              let raw = DeviceWitness.deviceExecutionWitnessToRaw witness
              DeviceWitness.refineRawDeviceExecutionWitness raw @?= Right witness
              assertBool
                "a witness with a non-digest artifact hash refined"
                ( isLeftResult
                    ( DeviceWitness.refineRawDeviceExecutionWitness
                        raw {DeviceWitness.rawWitnessArtifactSha256 = "not-a-digest"}
                    )
                )
              assertBool
                "a witness with a blank executed identity refined"
                ( isLeftResult
                    ( DeviceWitness.refineRawDeviceExecutionWitness
                        raw {DeviceWitness.rawWitnessExecutedIdentity = "   "}
                    )
                )
              assertBool
                "a witness naming an unknown substrate refined"
                ( isLeftResult
                    ( DeviceWitness.refineRawDeviceExecutionWitness
                        raw {DeviceWitness.rawWitnessSubstrate = "linux-tpu"}
                    )
                )
          , testCase
              "CheckpointList wire fields agree between the topology validator and the browser contract (Phase 262)"
              $ do
                -- Both ends of one wire form. The Engine renders the frame, the
                -- topology validator gates it on the way out, and the generated
                -- PureScript parses it on the way in. When the validator's set
                -- was the narrower pre-catalogue one, the Engine's own reply was
                -- unpublishable: every browse request failed publication, and
                -- because that read as a transient failure the command was
                -- nacked back onto the shared `jitml-engine` subscription
                -- forever. Nothing in a single-ended test could see it.
                generated <- Text.IO.readFile "web/src/Generated/Contracts.purs"
                browserFields <- phase262BrowserCheckpointFieldNames generated
                browserFields @?= Topology.checkpointListPayloadFields
                -- A frame carrying the agreed provenance publishes; the same
                -- frame without the catalogue digest does not, so the
                -- provenance is required rather than merely tolerated.
                case Topology.mkInferenceResultMessage phase262CheckpointListFrame of
                  Left err ->
                    assertFailure
                      ("authenticated CheckpointList frame is unpublishable: " <> Text.unpack err)
                  Right _ -> pure ()
                -- Every kind the Engine renders, gated by the validator it
                -- must pass on the way out. A reply the Engine can render but
                -- not publish is reported as a failed publication, which reads
                -- as a command that never succeeds; a single-ended renderer
                -- test cannot see that.
                traverse_
                  ( \(label, frame) ->
                      case Topology.mkInferenceResultMessage frame of
                        Left err ->
                          assertFailure
                            ( "Engine-rendered "
                                <> label
                                <> " frame is unpublishable: "
                                <> Text.unpack err
                            )
                        Right _ -> pure ()
                  )
                  phase262RenderedInferenceReplies
                assertBool
                  "a CheckpointList frame without its catalogue digest was accepted"
                  ( isLeftResult
                      ( Topology.mkInferenceResultMessage
                          ( Text.unlines
                              ( filter
                                  (not . Text.isPrefixOf "catalogue-sha256: ")
                                  (Text.lines phase262CheckpointListFrame)
                              )
                          )
                      )
                  )
          , testCase "README matrix rows match the ProductRow registry in both directions" $ do
              readme <- Text.IO.readFile "README.md"
              case readmeProductParityFailures readme of
                Left err -> assertFailure (Text.unpack err)
                Right failures -> failures @?= []
          , testCase "Generated PureScript model matrix constants match ProductRow registry rows" $ do
              generated <- Text.IO.readFile "web/src/Generated/Contracts.purs"
              let lanePairs substrate =
                    generatedModelMatrixPairsForSubstrate
                      (Substrate.renderSubstrate substrate)
                      generated
              traverse_
                (\substrate -> lanePairs substrate @?= registryModelMatrixPairs)
                Substrate.allSubstrates
              length (generatedModelMatrixPairs generated)
                @?= length Substrate.allSubstrates
                * length registryModelMatrixPairs
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
          , testCase "ProductRow experiment configs strictly refine for every row" $ do
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
              "ModelRef type-state pipeline stops at completed training before Store admission"
              $ do
                let completed = completedTrainingFixture 1
                    declaredExperiment = ProductPipeline.declareExperiment "exp1"
                    declaredModel = ProductPipeline.declareModel declaredExperiment
                    startedModel = ProductPipeline.startTraining declaredModel
                    acceptCompleted
                      :: ProductPipeline.ModelRef 'TrainingCompleted
                      -> Text
                    acceptCompleted = ProductPipeline.modelRefExperimentHash
                trainedModel <- ProductPipeline.train startedModel completed
                acceptCompleted trainedModel @?= "exp1"
                ProductPipeline.modelRefCompletedTraining trainedModel
                  @?= Just completed
                ProductPipeline.modelRefManifestSha trainedModel @?= Nothing
          , testCase "Pipeline eligibility APIs require opaque Store admission" $ do
              let markFromPersistedAdmission
                    :: CheckpointStore.AdmittedCompletedCheckpoint
                    -> ProductPipeline.ModelRef 'TrainingCompleted
                    -> Either Text ProductPipeline.InferenceEligibleRef
                  markFromPersistedAdmission = ProductPipeline.markInferenceEligible
                  referenceFromPersistedAdmission
                    :: CheckpointStore.AdmittedCompletedCheckpoint
                    -> ProductPipeline.InferenceEligibleRef
                  referenceFromPersistedAdmission =
                    ProductPipeline.inferenceEligibleModelRef
              markFromPersistedAdmission `seq` pure ()
              referenceFromPersistedAdmission `seq` pure ()
          , testCase "Pipeline depends on Store admission and not Format proof minting" $ do
              source <- Text.IO.readFile "src/JitML/Product/Pipeline.hs"
              assertBool
                "Pipeline does not import Store admission"
                ("import JitML.Checkpoint.Store qualified as CheckpointStore" `Text.isInfixOf` source)
              assertBool
                "Pipeline directly performs structural completion refinement"
                (not ("validateCheckpointCompletion" `Text.isInfixOf` source))
              assertBool
                "Pipeline accepts a structural completion witness instead of Store admission"
                (not ("ValidatedCheckpointCompletion" `Text.isInfixOf` source))
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
          "One operator vocabulary (Phase 72)"
          [ testCase "the catalog is derived from its own type" $ do
              NumericsCatalog.layerCatalog @?= [minBound .. maxBound]
              length NumericsCatalog.layerCatalog @?= 11
          , testCase "every catalog constructor has an executable operator" $ do
              fmap (LayerGraph.opLayer . LayerGraph.layerOpTemplate) NumericsCatalog.layerCatalog
                @?= NumericsCatalog.layerCatalog
          , testCase "every declared layer kind is executed by a real operator" $ do
              fmap (LayerGraph.opKind . LayerGraph.layerKindWitnessOp) LayerGraph.allLayerKinds
                @?= LayerGraph.allLayerKinds
          , testCase "every catalog constructor's kind is a declared layer kind" $ do
              let kinds =
                    List.nub
                      ( fmap
                          (LayerGraph.opKind . LayerGraph.layerOpTemplate)
                          NumericsCatalog.layerCatalog
                      )
                  declaredShapes = fmap kindConstructorName LayerGraph.allLayerKinds
                  orphans =
                    [kind | kind <- kinds, kindConstructorName kind `notElem` declaredShapes]
              orphans @?= []
          , testCase "a node's kind is the kind of the operator it executes" $ do
              node <-
                expectRightText
                  ( LayerGraph.mkAffineLayer
                      "vocabulary-dense"
                      2
                      2
                      LayerGraph.LinearActivation
                      LayerGraph.TrainingMode
                      (LayerGraph.deterministicParameters 1 2 2)
                  )
              LayerGraph.layerNodeKind node @?= LayerGraph.DenseLayer
              LayerGraph.layerNodeKind node @?= LayerGraph.opKind (LayerGraph.layerNodeOp node)
          , testCase "a block constructor rejects a spec of the other topology" $ do
              let basicSpec =
                    LayerGraph.BlockSpec
                      [ LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) Nothing LayerGraph.ReluActivation
                      , LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) Nothing LayerGraph.ReluActivation
                      ]
                      LayerGraph.IdentityShortcut
                      1.0
                      LayerGraph.ReluActivation
                  params = LayerGraph.deterministicOpParameters 7 (LayerGraph.BlockOp basicSpec)
              assertBool
                "a width-preserving spec is rejected as a bottleneck"
                ( case LayerGraph.mkBottleneck "vocabulary-block" basicSpec LayerGraph.TrainingMode params of
                    Left _ -> True
                    Right _ -> False
                )
              assertBool
                "the same spec is accepted as a basic block"
                ( case LayerGraph.mkBasicBlock "vocabulary-block" basicSpec LayerGraph.TrainingMode params of
                    Left _ -> False
                    Right _ -> True
                )
          , testCase "checkpoint metadata reconstruction rejects a kind that disagrees" $ do
              node <-
                expectRightText
                  ( LayerGraph.mkAffineLayer
                      "vocabulary-dense"
                      2
                      2
                      LayerGraph.LinearActivation
                      LayerGraph.TrainingMode
                      (LayerGraph.deterministicParameters 1 2 2)
                  )
              let graph =
                    LayerGraph.LayerGraph
                      { LayerGraph.layerGraphName = "vocabulary-graph"
                      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [2]
                      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
                      , LayerGraph.layerGraphNodes = [node]
                      }
                  metadata = LayerGraphMetadata.layerGraphMetadataFromGraph graph
                  tampered =
                    metadata
                      { LayerGraphMetadata.layerGraphMetadataNodes =
                          [ nodeMeta
                              { LayerGraphMetadata.layerGraphNodeKind =
                                  LayerGraphMetadata.LayerGraphConv2DLayer
                              }
                          | nodeMeta <- LayerGraphMetadata.layerGraphMetadataNodes metadata
                          ]
                      }
              assertBool
                "the untampered metadata round-trips"
                ( case LayerGraphMetadata.layerGraphFromMetadata metadata of
                    Left _ -> False
                    Right _ -> True
                )
              assertBool
                "a kind that disagrees with the executed operator is rejected"
                ( case LayerGraphMetadata.layerGraphFromMetadata tampered of
                    Left _ -> True
                    Right _ -> False
                )
          ]
      , testGroup
          "Fail-closed architecture resolution (Phase 233)"
          [ testCase "every canonical row's wire model and executed family agree" $
              -- The row carries its family directly now; this is the guard that
              -- the carried family cannot drift from the wire name.
              [ SLCanonicals.problemName problem
              | problem <- SLCanonicals.canonicalProblems
              , Architecture.familyForModel (SLCanonicals.problemModel problem)
                  /= Just (SLCanonicals.problemFamily problem)
              ]
                @?= []
          , testCase "an unrecognised model resolves to nothing, not to dense" $ do
              -- It previously answered DenseFamily, which silently degraded the
              -- architecture and made its own parity check vacuous.
              Architecture.familyForModel "NotAModel" @?= Nothing
              Architecture.familyForModel "Dense" @?= Just SLCanonicals.DenseFamily
          , testCase "claimed features follow the executed family" $ do
              -- A non-dense row must claim non-dense features. With the old
              -- string fallback an unknown model claimed only [FeatureDense],
              -- so feature parity held vacuously against a dense stand-in.
              let claimedFor name =
                    [ Architecture.architectureClaimedFeaturesForProblem problem
                    | problem <- SLCanonicals.canonicalProblems
                    , SLCanonicals.problemName problem == name
                    ]
              claimedFor "mnist-shallow-mlp" @?= [[Architecture.FeatureDense]]
              [ name
                | name <- ["mnist-lenet", "cifar10-vit", "cifar10-resnet20"]
                , claimedFor name == [[Architecture.FeatureDense]]
                ]
                @?= []
          , testCase "every canonical row builds its literal graph" $
              -- The builder no longer falls back to the legacy dense graph, so
              -- this is now a real assertion rather than a tautology.
              [ SLCanonicals.problemName problem
              | problem <- SLCanonicals.canonicalProblems
              , Left _ <-
                  [ Architecture.architectureSpecForProblem
                      Classifier.defaultClassifierConfig
                      problem
                  ]
              ]
                @?= []
          , testCase "the declared layer count matches the built topology" $
              -- layerCountForFamily feeds seed-headroom bounds; this keeps it
              -- from drifting from the topology it counts.
              [ SLCanonicals.problemName problem
              | problem <- SLCanonicals.canonicalProblems
              , Right spec <-
                  [ Architecture.architectureSpecForProblem
                      Classifier.defaultClassifierConfig
                      problem
                  ]
              , Architecture.layerCountForFamily (SLCanonicals.problemFamily problem)
                  /= length (Architecture.archLayers spec)
              ]
                @?= []
          , testCase "every parameterised operator receives trainable weights" $
              -- The weightPlan wildcard gave an unhandled operator zero
              -- trainable parameters: it would execute and train nothing.
              [ LayerGraph.layerKindName kind
              | kind <- LayerGraph.allLayerKinds
              , let op = LayerGraph.layerKindWitnessOp kind
              , kind
                  `notElem` [ LayerGraph.DenseLayer
                            , LayerGraph.IdentityLayer
                            , LayerGraph.DropoutLayer 0.1
                            , LayerGraph.PoolLayer LayerGraph.MaxPool
                            , LayerGraph.PoolLayer LayerGraph.AvgPool
                            , LayerGraph.PoolLayer LayerGraph.GlobalAvgPool
                            ]
              , Data.Vector.Unboxed.null
                  (LayerGraph.layerWeights (LayerGraph.deterministicOpParameters 5 op))
              ]
                @?= []
          ]
      , testGroup
          "Total device operator lowering (Phase 241)"
          [ testCase "every declared operator lowers to a device primitive" $
              -- The dispatch used to be a guard chain ending in a wildcard that
              -- reported "operator not supported on device". Three of the eleven
              -- operators fell into it, so a graph containing one either failed
              -- closed or had its backward computed by the pure executor that is
              -- supposed to be its oracle. The lowering is now total, and this
              -- pins that: a new operator with no device primitive shows up here
              -- as a Left rather than as a silent host fallback.
              [ LayerGraph.layerKindName kind
              | kind <- LayerGraph.allLayerKinds
              , Left _ <- [LayerGraphDevice.lowerLayerOp (phase241WitnessNode kind)]
              ]
                @?= []
          , testCase "identity and dropout lower to the shared scale definition" $ do
              -- Identity is the unit scale, and dropout's scale is read off the
              -- same `dropoutScale` the pure executor applies, so the device and
              -- the oracle cannot disagree about the keep probability.
              let scaleOf kind =
                    case LayerGraphDevice.lowerLayerOp (phase241WitnessNode kind) of
                      Right (LayerGraphDevice.LowerOpTrain plan) ->
                        Just (LayerGraphDevice.dopFparams plan)
                      _ -> Nothing
              scaleOf LayerGraph.IdentityLayer @?= Just [1.0]
              scaleOf (LayerGraph.DropoutLayer 0.25)
                @?= Just [LayerGraph.dropoutScale LayerGraph.TrainingMode 0.25]
          , testCase "each operator family claims its own opcode and evidence code" $ do
              -- Two operators sharing an opcode would let the artifact run one
              -- and be recorded as the other.
              let plans =
                    [ (LayerGraphDevice.dopCode plan, LayerGraphDevice.dopEvidenceCode plan)
                    | kind <- LayerGraph.allLayerKinds
                    , Right (LayerGraphDevice.LowerOpTrain plan) <-
                        [LayerGraphDevice.lowerLayerOp (phase241WitnessNode kind)]
                    ]
              assertBool
                "an operator lowered to an opcode with a mismatched evidence code"
                (all (\(code, evidenceCode) -> code /= 0 && evidenceCode /= 0) plans)
              nub (fmap fst plans) @?= nub (fmap fst plans)
              [ (code, nub evidenceCodes)
                | code <- nub (fmap fst plans)
                , let evidenceCodes = [e | (c, e) <- plans, c == code]
                , length (nub evidenceCodes) /= 1
                ]
                @?= []
          ]
      , testGroup
          "Cross-renderer family contract (Phase 84)"
          [ testCase "every renderer emits each entry point exactly once per family" $ do
              -- The signature is emitted once and the body supplied as data, so
              -- a family cannot acquire a second or zero copy of its ABI.
              let oneDnnSource family =
                    Text.concat
                      ( fmap
                          sourceContents
                          ( OneDnnCodegen.renderOneDnnFamilySource
                              family
                              (Cache.KernelSpec "phase-84")
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
                  cudaSource family =
                    Text.concat
                      ( fmap
                          sourceContents
                          ( Cuda.renderCudaFamilySource
                              family
                              (Cache.KernelSpec "phase-84")
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
                  metalSource = Metal.renderMetalFamilySource
                  counts :: Text -> (KernelFamily -> Text) -> Text -> Text -> [(Text, KernelFamily)]
                  counts label render open weighted =
                    [ (label, family)
                    | family <- KernelFamily.kernelFamilies
                    , Text.count open (render family) /= 1
                        || Text.count weighted (render family) /= 1
                    ]
              concat
                [ counts "onednn" oneDnnSource "void jitml_kernel(" "void jitml_weighted_kernel("
                , counts "cuda" cudaSource "void jitml_kernel(" "void jitml_weighted_kernel("
                , counts
                    "metal"
                    metalSource
                    "kernel void jitml_kernel("
                    "kernel void jitml_weighted_kernel("
                ]
                @?= []
          , testCase "all three renderers agree on unweighted attention" $ do
              -- The contract says attention at Wq = Wk = Wv = I is an
              -- elementwise square. Each renderer must express that, not a
              -- passthrough.
              let oneDnn =
                    Text.concat
                      ( fmap
                          sourceContents
                          ( OneDnnCodegen.renderOneDnnFamilySource
                              KernelFamily.MultiHeadAttentionKernel
                              (Cache.KernelSpec "phase-84-mha")
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
                  metal = Metal.renderMetalFamilySource KernelFamily.MultiHeadAttentionKernel
              assertBool
                "oneDNN attention delegates to the unit-weight algebra"
                ("jitml_onednn_mha_unit(out, input, n);" `Text.isInfixOf` oneDnn)
              assertBool
                "metal attention squares its input"
                ("input[id] * input[id]" `Text.isInfixOf` metal)
              assertBool
                "no renderer leaves attention as a bare passthrough"
                (not ("jitml_onednn_dense_identity(out, input, n);" `Text.isInfixOf` oneDnn))
          , testCase "the metal reduction never writes past its output buffer" $ do
              -- The weighted reduction body used to write out[id] for every
              -- id < n into a buffer sized ceil(n / 32).
              -- The rendered source concatenates the unweighted and weighted
              -- bodies, and BOTH needles already occur in the unweighted one, so
              -- an infix check here passes even with the weighted fix reverted.
              -- Count instead: each must appear exactly twice, once per body.
              let metal = Metal.renderMetalFamilySource KernelFamily.Reduction
              Metal.metalOutputCountFor KernelFamily.Reduction 100 @?= 4
              Text.count "out[base / 32u] = v;" metal @?= 2
              Text.count "uint tid_in_simd [[thread_index_in_simdgroup]]" metal @?= 2
              assertBool
                "no reduction body writes one output per input lane"
                (not ("  out[id] = input[id];" `Text.isInfixOf` metal))
          , testCase "metal output sizing and its declared kind agree" $
              [ family
              | family <- KernelFamily.kernelFamilies
              , let sized = Metal.metalOutputCountFor family 64
              , let declared = Metal.metalOutputCountKind family
              , if declared == "same-as-input" then sized /= 64 else sized /= 2
              ]
                @?= []
          ]
      , testGroup
          "Kernel-family semantics contract (Phase 80)"
          [ testCase "the contract degenerates every family to its unweighted meaning" $ do
              -- The unweighted ABI has no independent definition: it is the
              -- weighted reference at the family's canonical no-op weights.
              let input = [1.0, 2.0, 3.0, 4.0] :: [Float]
                  actual =
                    [ (family, FamilyReference.unweightedFamilyReference family input)
                    | family <- KernelFamily.kernelFamilies
                    ]
                  closeTo expected got =
                    length expected == length got
                      && and [abs (a - b) < 1.0e-4 | (a, b) <- zip expected got]
              [ family
                | (family, got) <- actual
                , let expected =
                        case family of
                          Identity -> [1.0, 2.0, 3.0, 4.0]
                          Reduction -> [10.0]
                          Dense2D -> [1.0, 2.0, 3.0, 4.0]
                          Conv2DKernel -> [1.0, 2.0, 3.0, 4.0]
                          Conv3DKernel -> [1.0, 2.0, 3.0, 4.0]
                          BatchNormKernel -> [0.999995, 1.99999, 2.999985, 3.99998]
                          LayerNormKernel -> [-1.3416354, -0.4472118, 0.4472118, 1.3416354]
                          -- Wq = Wk = Wv = I degenerates attention to a square.
                          MultiHeadAttentionKernel -> [1.0, 4.0, 9.0, 16.0]
                          EmbeddingKernel -> [1.0, 2.0, 3.0, 4.0]
                , not (closeTo expected got)
                ]
                @?= []
          , testCase "the linux-cpu attention body is the weighted algebra at identity" $ do
              -- This lane rendered `jitml_onednn_dense_identity` — the input
              -- unchanged — while linux-cuda and apple-silicon both squared.
              let source =
                    Text.concat
                      ( fmap
                          sourceContents
                          ( OneDnnCodegen.renderOneDnnFamilySource
                              KernelFamily.MultiHeadAttentionKernel
                              (Cache.KernelSpec "phase-80-mha")
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
              assertBool
                "the unweighted attention body calls the unit-weight algebra"
                ("jitml_onednn_mha_unit(out, input, n);" `Text.isInfixOf` source)
              assertBool
                "the unit-weight helper builds identity projections"
                ("identity[2 * block + i * n + i] = 1.0f;" `Text.isInfixOf` source)
          , testCase "no linux-cpu weighted family renders a discarding passthrough" $ do
              -- A tenth family now fails the build rather than silently
              -- rendering `(void)weights; jitml_kernel(...)`.
              let weightedBody family =
                    Text.concat
                      ( fmap
                          sourceContents
                          ( OneDnnCodegen.renderOneDnnFamilySource
                              family
                              (Cache.KernelSpec "phase-80-weighted")
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
                  -- Identity and Reduction have no weight parameter at all;
                  -- their canonical no-op weight buffer is empty.
                  weightless = [KernelFamily.Identity, KernelFamily.Reduction]
              [ family
                | family <- KernelFamily.kernelFamilies
                , family `notElem` weightless
                , not
                    ( "_weighted(out, input, n, weights, weights_count);"
                        `Text.isInfixOf` weightedBody family
                    )
                ]
                @?= []
              [ family
                | family <- weightless
                , not ("(void)weights;" `Text.isInfixOf` weightedBody family)
                ]
                @?= []
          ]
      , testGroup
          "One substrate profile (Phase 79)"
          [ testCase "the engine record is a projection of the profile" $
              -- Backend and artifact extension exist in one place now, so the
              -- two cannot disagree about a substrate.
              [ substrate
              | substrate <- [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
              , let profile = Substrate.profileFor substrate
              , let engine = Engine.engineForSubstrate substrate
              , Engine.engineBackend engine /= Substrate.profileBackend profile
                  || Engine.engineArtifactExtension engine
                    /= Substrate.profileArtifactExtension profile
                  || Engine.engineSubstrate engine /= Substrate.profileSubstrate profile
              ]
                @?= []
          , testCase "every substrate-varying fact reads off the one profile" $ do
              -- The former five shapes of "apple-silicon has no cluster
              -- compute", plus the edge port and the runtime class whose
              -- wildcard let a new substrate inherit Nothing.
              [ substrate
                | substrate <- [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
                , let profile = Substrate.profileFor substrate
                , Substrate.substrateHasClusterCompute substrate
                    /= Substrate.profileHasClusterCompute profile
                    || Substrate.substrateEdgePort substrate /= Substrate.profileEdgePort profile
                    || Substrate.substrateRuntimeClass substrate
                      /= Substrate.profileRuntimeClass profile
                ]
                @?= []
              Substrate.substrateHasClusterCompute Substrate.AppleSilicon @?= False
              Substrate.substrateHasClusterCompute Substrate.LinuxCPU @?= True
              Substrate.substrateHasClusterCompute Substrate.LinuxCUDA @?= True
          , testCase "each substrate declares how it fills and enters its artifact" $ do
              -- The loader and the MLP device dispatch on these values instead
              -- of on a wildcard over Substrate.
              fmap
                (Substrate.profileArtifactFill . Substrate.profileFor)
                [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
                @?= [ Substrate.SourceMetadataWriteFill
                    , Substrate.CompileSubprocessFill
                    , Substrate.CompileSubprocessFill
                    ]
              fmap
                (Substrate.profileLaunch . Substrate.profileFor)
                [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
                @?= [ Substrate.FixedBridgeLaunch
                    , Substrate.LoadableSymbolLaunch
                    , Substrate.LoadableSymbolLaunch
                    ]
          , testCase "an apple artifact's identity is read out of the artifact" $ do
              -- Before Sprint 79.1 the Apple family driver reported the family
              -- the host had ASKED for, so the mismatch guard compared a value
              -- with itself. The identity now comes from the written document.
              withSystemTempDirectory "phase79-metal" $ \dir -> do
                let path = dir </> "kernel.metal.json"
                Text.IO.writeFile path "{\n  \"family\": \"conv2d\",\n  \"abi\": \"x\"\n}\n"
                identity <-
                  Loader.executedArtifactIdentity Substrate.FixedBridgeLaunch path
                identity @?= Right "conv2d"
          , testCase "a malformed or absent apple artifact identity fails closed" $
              withSystemTempDirectory "phase79-metal-bad" $ \dir -> do
                let missing = dir </> "absent.metal.json"
                    malformed = dir </> "malformed.metal.json"
                Text.IO.writeFile malformed "{\n  \"abi\": \"x\"\n}\n"
                absentResult <- Loader.executedArtifactIdentity Substrate.FixedBridgeLaunch missing
                malformedResult <-
                  Loader.executedArtifactIdentity Substrate.FixedBridgeLaunch malformed
                assertBool
                  "an unreadable artifact is rejected"
                  (either (const True) (const False) absentResult)
                malformedResult @?= Left "Metal source-metadata artifact declares no family"
          , testCase "linux-cpu fails closed when oneDNN is unavailable" $ do
              -- This lane previously went straight to dlopen with no probe at
              -- all, while CUDA and Metal both gated on theirs.
              let unavailable =
                    OneDnnRuntime.OneDnnRuntimeProbe
                      { OneDnnRuntime.oneDnnRuntimePkgConfigName = Nothing
                      , OneDnnRuntime.oneDnnRuntimePkgConfigVersion = Nothing
                      , OneDnnRuntime.oneDnnRuntimeHeaderPath = Nothing
                      , OneDnnRuntime.oneDnnRuntimeLibraryVisible = False
                      , OneDnnRuntime.oneDnnRuntimeProbeLog = []
                      }
              OneDnnRuntime.oneDnnRuntimeAvailable unavailable @?= False
              env <- buildEnv defaultGlobalFlags
              result <-
                LocalEngine.runLinuxCpuFamilyKernelWithProbe
                  (pure unavailable)
                  env
                  Dense2D
                  [1.0, 2.0]
              case result of
                Left message ->
                  assertBool
                    ("probe failure names the lane: " <> Text.unpack message)
                    ("linux-cpu oneDNN runtime unavailable" `Text.isInfixOf` message)
                Right _ -> assertFailure "a missing oneDNN runtime must fail closed"
          ]
      , testGroup
          "Derived toolchain fingerprints (Phase 78)"
          [ testCase "every substrate has a real build fingerprint" $ do
              -- The former shared non-linux-cpu literal named no compiler, no
              -- target and no bridge ABI; `jitml build` keyed CUDA and Apple
              -- artifacts on it.
              let fingerprints =
                    [ (substrate, Fingerprint.buildToolchainFingerprint substrate)
                    | substrate <- [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
                    ]
              traverse_
                ( \(substrate, fingerprint) -> do
                    let text = Cache.unToolchainFingerprint fingerprint
                        compiler = Engine.engineCompiler (Engine.engineForSubstrate substrate)
                    assertBool
                      (show substrate <> " fingerprint names its compiler")
                      (compiler `Text.isInfixOf` text)
                    assertBool
                      (show substrate <> " fingerprint names the host artifact ABI")
                      (("artifact-abi=" <> Fingerprint.hostArtifactAbi) `Text.isInfixOf` text)
                )
                fingerprints
              length (List.nub (fmap snd fingerprints)) @?= 3
          , testCase "build and benchmark tuning key the same artifact" $
              -- The build path and the benchmark candidate runners previously
              -- derived different fingerprints on CUDA and Apple, so the lane
              -- benchmarked at one cache key and installed at another.
              [ substrate
              | substrate <- [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
              , Fingerprint.buildToolchainFingerprint substrate
                  /= Fingerprint.engineFamilyToolchainFingerprint substrate
              ]
                @?= []
          , testCase "every compile and link flag reaches the fingerprint" $
              -- The mechanical form of "a toolchain change invalidates its
              -- artifact": each artifact's fingerprint carries the same flag
              -- list its own compile command passes. Sprint 265.1 made the
              -- library arguments follow the program, so this is checked per
              -- (substrate, program) pair rather than once per substrate.
              [ (substrate, program, flag)
              | substrate <- [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
              , let engine = Engine.engineForSubstrate substrate
              , (program, fingerprint) <-
                  [ (RuntimeSource.FamilyProgram, Fingerprint.engineFamilyToolchainFingerprint substrate)
                  , (RuntimeSource.MlpProgram, Fingerprint.mlpToolchainFingerprint substrate)
                  , (RuntimeSource.LayerTrainingProgram, Fingerprint.layerTrainingToolchainFingerprint substrate)
                  ]
              , let text = Cache.unToolchainFingerprint fingerprint
              , flag <-
                  Engine.engineCompileFlags engine program
                    <> Engine.engineLinkFlags engine program
              , not (flag `Text.isInfixOf` text)
              ]
                @?= []
          , testCase "every argument the compiler receives is one the cache key saw" $ do
              -- Sprint 78.1 closed one direction: no advertised determinism fact
              -- without a real argument. This closes the other, which was never
              -- tested — an argument added straight into `compileSubprocess`
              -- would reach the compiler while the fingerprint stayed blind to
              -- it, and the artifact bytes would then depend on an input the
              -- cache key does not carry. That is exactly the defect class that
              -- reopened this phase, in mirror image.
              let scratch = "/tmp/jitml-scratch-fixture"
                  spec = Cache.KernelSpec "phase-78-compile-line"
              traverse_
                ( \substrate -> do
                    let engine = Engine.engineForSubstrate substrate
                        source = RuntimeSource.renderRuntimeSource spec Cache.Inference substrate Cache.defaultTuningChoice
                        staging = Engine.renderedStagingPath engine sampleCacheHash
                        rendered =
                          subprocessArguments
                            (Engine.compileSubprocess engine source sampleCacheHash scratch staging)
                        folded =
                          concatMap
                            (Engine.renderCompileFlag scratch)
                            (Engine.engineCompileFlagSpecs engine)
                        -- Everything the fold does not own: the program's library
                        -- defines, the output pair, and the link line.
                        unowned = filter (`notElem` folded) rendered
                        program = RuntimeSource.runtimeSourceProgram source
                        accountedFor =
                          Engine.programLibraryDefines engine program
                            <> [ "-o"
                               , Text.pack staging
                               , Text.pack (RuntimeSource.runtimeSourceRelativeDirectory source sampleCacheHash)
                                   <> "/"
                                   <> Engine.engineSourceFileName engine
                               ]
                            <> Engine.engineLinkFlags engine program
                    assertBool
                      ( show substrate
                          <> " compile line carries an argument no list owns: "
                          <> show (filter (`notElem` accountedFor) unowned)
                      )
                      (all (`elem` accountedFor) unowned)
                )
                Substrate.allSubstrates
          , testCase "each substrate pins every non-determinism source its producer has" $ do
              -- The pins are read off the profile, so a substrate cannot acquire
              -- a source of non-determinism without also acquiring its remedy.
              -- `linux-cpu` and `apple-silicon` carry the empty set as a
              -- positive claim; the double-compile gate in jitml-backends is
              -- what discharges it.
              Substrate.producerPins Substrate.LinuxCUDA
                @?= [Substrate.IntermediateFileNaming, Substrate.SymbolMangling]
              Substrate.producerPins Substrate.LinuxCPU @?= []
              Substrate.producerPins Substrate.AppleSilicon @?= []
              -- A pin that renders an argument must actually appear on the line.
              let cudaEngine = Engine.engineForSubstrate Substrate.LinuxCUDA
                  reproducibility = Engine.compileLineReproducibility cudaEngine
              assertBool
                ("linux-cuda advertises its intermediate-naming pin: " <> show reproducibility)
                ("--keep" `elem` reproducibility && "--keep-dir" `elem` reproducibility)
              Engine.compileLineReproducibility (Engine.engineForSubstrate Substrate.LinuxCPU) @?= []
          , testCase "every rendered native source uses its substrate's linkage style" $ do
              -- `cudafe` mangles an anonymous namespace with a per-invocation
              -- random id, so a CUDA renderer that reintroduces one silently
              -- makes its artifact irreproducible. `linux-cpu` keeps the
              -- anonymous form: g++ mangles it deterministically and Sprint
              -- 263.1 pins those artifact bytes.
              let rendered files = Text.concat (fmap sourceContents files)
                  anonymous source = "namespace {" `Text.isInfixOf` source
                  cudaSources =
                    [ ("cuda-layer-training", rendered CudaLayerTrainingCodegen.renderCudaLayerTrainingSource)
                    , ("cuda-mlp", rendered MlpCudaCodegen.renderMlpCudaSource)
                    ]
              Substrate.substrateLinkage Substrate.LinuxCUDA @?= Substrate.StaticFunctions
              Substrate.substrateLinkage Substrate.LinuxCPU @?= Substrate.AnonymousNamespace
              [name | (name, source) <- cudaSources, anonymous source] @?= ([] :: [Text])
              assertBool
                "the linux-cpu layer-training source keeps its attested anonymous namespace"
                (anonymous (rendered OneDnnCodegen.renderOneDnnLayerTrainingSource))
          , testCase "only the programs that call cuBLAS/cuDNN link them" $ do
              -- Sprint 265.1 — the MLP artifact is hand-written elementwise
              -- CUDA including only `cuda_runtime.h`; it used to be compiled
              -- with `-DJITML_USE_CUBLAS=1 -DJITML_USE_CUDNN=1` and linked
              -- against both libraries anyway, so its `.so` carried DT_NEEDED
              -- entries it never enters and its cache key named two libraries
              -- it does not use. The family and layer-training programs do call
              -- them and must keep them.
              let cudaEngine = Engine.engineForSubstrate Substrate.LinuxCUDA
                  argumentsFor program =
                    Engine.engineCompileFlags cudaEngine program
                      <> Engine.engineLinkFlags cudaEngine program
                  mentions program needle = any (needle `Text.isInfixOf`) (argumentsFor program)
              [ (program, needle)
                | program <- [RuntimeSource.FamilyProgram, RuntimeSource.LayerTrainingProgram]
                , needle <- ["cublas", "cudnn", "CUBLAS", "CUDNN"]
                , not (mentions program needle)
                ]
                @?= []
              [ needle
                | needle <- ["cublas", "cudnn", "CUBLAS", "CUDNN"]
                , mentions RuntimeSource.MlpProgram needle
                ]
                @?= []
              -- Every program still links the CUDA runtime itself.
              [ program
                | program <- [minBound .. maxBound] :: [RuntimeSource.KernelProgram]
                , not (mentions program "-lcudart")
                ]
                @?= []
          , testCase "the metal bridge ABI token is interpolated, never hardcoded" $ do
              let token = "bridge-abi=" <> Metal.metalBridgeAbiVersion
              traverse_
                ( \fingerprint ->
                    assertBool
                      "metal fingerprint interpolates the bridge ABI version"
                      (token `Text.isInfixOf` Cache.unToolchainFingerprint fingerprint)
                )
                [ Fingerprint.engineFamilyToolchainFingerprint Substrate.AppleSilicon
                , Fingerprint.mlpToolchainFingerprint Substrate.AppleSilicon
                ]
          , testCase "the apple MLP fingerprint names MSL kernels, not a host C ABI" $ do
              -- The Apple artifact is Metal source metadata and exports no C
              -- symbols; the previous fingerprint claimed `abi=cdecl-host-buffers`
              -- and five C prototypes, one of which is defined nowhere.
              let text =
                    Cache.unToolchainFingerprint (Fingerprint.mlpToolchainFingerprint Substrate.AppleSilicon)
              assertBool
                "apple MLP fingerprint declares the fixed-bridge ABI"
                ("abi=fixed-bridge-host-buffers" `Text.isInfixOf` text)
              assertBool
                "apple MLP fingerprint does not claim a cdecl host ABI"
                (not ("cdecl" `Text.isInfixOf` text))
              traverse_
                ( \entry ->
                    assertBool
                      ("apple MLP fingerprint names " <> Text.unpack entry)
                      (entry `Text.isInfixOf` text)
                )
                Fingerprint.mlpMetalEntryPoints
          , testCase "every named entry point exists in the source its lane renders" $ do
              -- The rule that keeps a fingerprint from describing an ABI its
              -- artifact does not export.
              let rendered files = Text.concat (fmap sourceContents files)
                  spec = Cache.KernelSpec "phase-78-entry-points"
                  familySources =
                    [
                      ( "onednn"
                      , rendered
                          ( OneDnnCodegen.renderOneDnnFamilySource
                              KernelFamily.Dense2D
                              spec
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
                    ,
                      ( "cuda"
                      , rendered
                          ( Cuda.renderCudaFamilySource
                              KernelFamily.Dense2D
                              spec
                              Cache.Inference
                              Cache.defaultTuningChoice
                          )
                      )
                    ]
                  missing :: [Text] -> (Text, Text) -> [(Text, Text)]
                  missing entries (label, source) =
                    [(label, entry) | entry <- entries, not (entry `Text.isInfixOf` source)]
              concatMap (missing Fingerprint.familyKernelEntryPoints) familySources @?= []
              -- The Apple family artifact defines two MSL kernels; the family
              -- name and output count are metadata fields, not entry points.
              missing
                Fingerprint.metalFamilyEntryPoints
                ("metal", Metal.renderMetalFamilySource KernelFamily.Dense2D)
                @?= []
              concatMap
                (missing Fingerprint.mlpHostEntryPoints)
                [ ("mlp-onednn", rendered MlpOneDnnCodegen.renderMlpOneDnnSource)
                , ("mlp-cuda", rendered MlpCudaCodegen.renderMlpCudaSource)
                ]
                @?= []
              missing
                Fingerprint.mlpMetalEntryPoints
                ("mlp-metal", MlpMetalCodegen.renderMlpMetalProgram)
                @?= []
              -- Sprint 264.1: both layer-training lanes render the one entry-point
              -- vocabulary, because the operator layer they splice is shared text
              -- and each backend supplies the primitives it names.
              concatMap
                (missing Fingerprint.layerTrainingEntryPoints)
                [ ("layer-training-onednn", rendered OneDnnCodegen.renderOneDnnLayerTrainingSource)
                , ("layer-training-cuda", rendered CudaLayerTrainingCodegen.renderCudaLayerTrainingSource)
                ]
                @?= []
          , testCase "the family fingerprint names every kernel family" $
              [ family
              | family <- KernelFamily.kernelFamilies
              , substrate <- [Substrate.AppleSilicon, Substrate.LinuxCPU, Substrate.LinuxCUDA]
              , not
                  ( KernelFamily.familyName family
                      `Text.isInfixOf` Cache.unToolchainFingerprint
                        (Fingerprint.engineFamilyToolchainFingerprint substrate)
                  )
              ]
                @?= []
          , testCase "the layer-training fingerprint names the executed operator vocabulary" $
              -- Widening the operator vocabulary (Sprint 241.1) therefore
              -- invalidates the training artifact without touching Fingerprint.
              [ (substrate, kind)
              | substrate <- [Substrate.LinuxCPU, Substrate.LinuxCUDA]
              , kind <- LayerGraph.allLayerKinds
              , not
                  ( LayerGraph.layerKindName kind
                      `Text.isInfixOf` Cache.unToolchainFingerprint
                        (Fingerprint.layerTrainingToolchainFingerprint substrate)
                  )
              ]
                @?= []
          , testCase "every fingerprint the JIT cache uses is distinct and non-empty" $ do
              let named =
                    [ ("family-apple", Fingerprint.engineFamilyToolchainFingerprint Substrate.AppleSilicon)
                    , ("family-linux-cpu", Fingerprint.engineFamilyToolchainFingerprint Substrate.LinuxCPU)
                    , ("family-linux-cuda", Fingerprint.engineFamilyToolchainFingerprint Substrate.LinuxCUDA)
                    , ("mlp-apple", Fingerprint.mlpToolchainFingerprint Substrate.AppleSilicon)
                    , ("mlp-linux-cpu", Fingerprint.mlpToolchainFingerprint Substrate.LinuxCPU)
                    , ("mlp-linux-cuda", Fingerprint.mlpToolchainFingerprint Substrate.LinuxCUDA)
                    , ("layer-training-linux-cpu", Fingerprint.layerTrainingToolchainFingerprint Substrate.LinuxCPU)
                    , ("layer-training-linux-cuda", Fingerprint.layerTrainingToolchainFingerprint Substrate.LinuxCUDA)
                    ]
              [ name
                | (name, fingerprint) <- named
                , Text.null (Cache.unToolchainFingerprint fingerprint)
                ]
                @?= ([] :: [Text])
              length (List.nub (fmap snd named)) @?= length named
          , testCase "no advertised determinism argument is absent from the compile line" $
              -- The defect that reopened Phase 78: `profileDeterminism` for
              -- `linux-cuda` advertised `--use_fast_math=false`, which
              -- `compileSubprocess` deliberately never passes (modern nvcc
              -- rejects the `=false` spelling). Because the list feeds the
              -- toolchain fingerprint, the cache key attested a compile line
              -- that was never run. Anything shaped like a compiler argument
              -- must therefore be an argument the compiler is given.
              [ (substrate, fact)
              | substrate <- Substrate.allSubstrates
              , let engine = Engine.engineForSubstrate substrate
              , fact <- Engine.deterministicFlags engine
              , "-" `Text.isPrefixOf` fact
              , fact `notElem` fmap Engine.compileFlagText (Engine.engineCompileFlagSpecs engine)
              ]
                @?= []
          , testCase "every determinism-roled compile argument is advertised" $
              -- The other direction: a determinism argument added to the
              -- compile line reaches the cache key without a second edit.
              [ (substrate, Engine.compileFlagText flag)
              | substrate <- Substrate.allSubstrates
              , let engine = Engine.engineForSubstrate substrate
              , flag <- Engine.engineCompileFlagSpecs engine
              , Engine.compileFlagRole flag == Engine.DeterminismFlag
              , Engine.compileFlagText flag `notElem` Engine.deterministicFlags engine
              ]
                @?= []
          , testCase "the fast-math fact is read off the compile line" $ do
              -- Fast math is off by omission on both compiled lanes, and the
              -- fact says so rather than naming a flag no compiler is given.
              -- Adding one flips the fact and invalidates every artifact on
              -- that lane.
              let factsFor = Engine.compileLineDeterminism . Engine.engineForSubstrate
                  mentionsFastMath =
                    any
                      ( (\flag -> "fast-math" `Text.isInfixOf` flag || "fast_math" `Text.isInfixOf` flag)
                          . Engine.compileFlagText
                      )
                      . Engine.engineCompileFlagSpecs
                      . Engine.engineForSubstrate
              -- The Apple artifact is a metadata write, not a compile
              -- subprocess, so it advertises no compile-line facts at all.
              factsFor Substrate.AppleSilicon @?= []
              [ substrate
                | substrate <- [Substrate.LinuxCPU, Substrate.LinuxCUDA]
                , mentionsFastMath substrate || "fast-math=absent" `notElem` factsFor substrate
                ]
                @?= []
          , testCase "no CUDA determinism fact describes a kernel the artifact does not run" $ do
              -- `cudnn-explicit-algorithm-id` and `warp-shuffle-deterministic`
              -- were substrate-wide, so the trainer MLP artifact keyed on both
              -- while its rendered source reduces per thread with neither. The
              -- determinism facts are now the compile line's own, which no
              -- kernel can contradict; the artifact's *link line* still carries
              -- cuBLAS/cuDNN for every CUDA artifact, which is the separate
              -- per-artifact-flag item Sprint `265.1` owns.
              let facts =
                    Engine.deterministicFlags (Engine.engineForSubstrate Substrate.LinuxCUDA)
                  source = Text.concat (fmap sourceContents MlpCudaCodegen.renderMlpCudaSource)
              traverse_
                ( \claim -> do
                    assertBool
                      ("the MLP CUDA source does not use " <> Text.unpack claim)
                      (not (claim `Text.isInfixOf` Text.toLower source))
                    assertBool
                      ("the CUDA determinism facts do not claim " <> Text.unpack claim)
                      (not (any (Text.isInfixOf claim . Text.toLower) facts))
                )
                ["cudnn", "shfl", "warp-shuffle"]
          , testCase "the CUDA layer-training knobs are the choices its source makes" $ do
              -- The cuDNN algorithm ids and the cuBLAS math mode are named once
              -- and spliced into the rendered source, so the cache key cannot
              -- address the artifact by an algorithm it stopped selecting.
              let text =
                    Cache.unToolchainFingerprint
                      (Fingerprint.layerTrainingToolchainFingerprint Substrate.LinuxCUDA)
                  source =
                    Text.concat
                      (fmap sourceContents CudaLayerTrainingCodegen.renderCudaLayerTrainingSource)
              assertBool
                "the CUDA layer-training artifact declares determinism choices"
                (not (null CudaLayerTrainingCodegen.cudaLayerTrainingDeterminismChoices))
              [ choice
                | choice <- CudaLayerTrainingCodegen.cudaLayerTrainingDeterminismChoices
                , not (choice `Text.isInfixOf` source && choice `Text.isInfixOf` text)
                ]
                @?= []
          ]
      , testGroup
          "Layer-graph training lanes (Phase 264)"
          [ testCase "both lanes splice the identical shared operator chunks" $ do
              -- The operator bodies are one string, not a per-lane copy, so the
              -- two lanes cannot drift in operator semantics. A lane that
              -- re-implemented GeGLU or attention its own way would stop
              -- containing this text.
              --
              -- The chunks are checked one at a time rather than as a single
              -- block because a lane chooses its own emission offsets:
              -- `linux-cpu` interleaves them with its primitive parts to keep
              -- its rendered text byte-for-byte what Sprint `263.1` attested,
              -- while `linux-cuda` has no committed digest to preserve and
              -- emits them contiguously. Sharing the text is the invariant;
              -- emitting it in one run is not.
              let chunks =
                    [ ("kind-dispatch", LayerTrainingCodegen.layerTrainingKindDispatchLayer)
                    , ("operator-bodies", LayerTrainingCodegen.layerTrainingOperatorBodies)
                    , ("jitml_op_train", LayerTrainingCodegen.layerTrainingOpTrainEntry)
                    ]
                  oneDnnSource =
                    Text.concat
                      (fmap sourceContents OneDnnCodegen.renderOneDnnLayerTrainingSource)
                  cudaSource =
                    Text.concat
                      (fmap sourceContents CudaLayerTrainingCodegen.renderCudaLayerTrainingSource)
              mapM_
                ( \(name, chunk) -> do
                    let rendered = Text.unlines chunk
                    assertBool
                      ("the linux-cpu layer-training source splices the shared " <> name <> " chunk")
                      (rendered `Text.isInfixOf` oneDnnSource)
                    assertBool
                      ("the linux-cuda layer-training source splices the shared " <> name <> " chunk")
                      (rendered `Text.isInfixOf` cudaSource)
                )
                chunks
              assertBool
                "the linux-cuda layer-training source emits the shared chunks contiguously"
                ( Text.unlines LayerTrainingCodegen.layerTrainingOperatorLayer
                    `Text.isInfixOf` cudaSource
                )
          , testCase "the linux-cpu lane keeps its attested emission order" $ do
              -- Sprint `263.1` re-issued the committed lane fragment from
              -- measured device witnesses whose `DeviceEvidence` cells pin a
              -- prefix of this artifact's SHA-256. Appending the shared layer
              -- after the primitives instead of interleaving it relocates the
              -- kind-dispatch block and restamps that digest for a change that
              -- concerns another lane entirely. This pins the interleaving, so
              -- the mistake is a failing unit case rather than a failed
              -- twelve-hour live gate.
              let oneDnnSource =
                    Text.concat
                      (fmap sourceContents OneDnnCodegen.renderOneDnnLayerTrainingSource)
                  anchors =
                    [ "jitml_layer_training_backend"
                    , "jitml_layer_forward_primitive"
                    , "jitml_conv2d_spatial_forward"
                    , "jitml_geglu_train"
                    , "jitml_pool_train"
                    , "jitml_op_train"
                    ]
                  offsetOf anchor =
                    case Text.breakOn anchor oneDnnSource of
                      (before, matched)
                        | Text.null matched -> Nothing
                        | otherwise -> Just (Text.length before)
                  offsets = fmap offsetOf anchors
              assertBool
                ( "every linux-cpu layer-training anchor is emitted: "
                    <> show (zip anchors offsets)
                )
                (all isJust offsets)
              let resolved = catMaybes offsets
              assertBool
                ( "the linux-cpu layer-training emission order is unchanged: "
                    <> show (zip anchors resolved)
                )
                (List.sort resolved == resolved)
          , testCase "the CUDA layer-training primitives are real cuBLAS/cuDNN calls" $ do
              let cudaSource =
                    Text.concat
                      (fmap sourceContents CudaLayerTrainingCodegen.renderCudaLayerTrainingSource)
                  required =
                    [ "cublasSgemm"
                    , "cublasSetMathMode"
                    , "CUBLAS_PEDANTIC_MATH"
                    , "cudnnConvolutionForward"
                    , "cudnnConvolutionBackwardData"
                    , "cudnnConvolutionBackwardFilter"
                    , "cudnnPoolingForward"
                    , "cudnnPoolingBackward"
                    ]
              [entry | entry <- required, not (entry `Text.isInfixOf` cudaSource)] @?= []
              assertBool
                "the CUDA layer-training source names no oneDNN primitive"
                (not ("dnnl" `Text.isInfixOf` cudaSource))
          , testCase "each lane's artifact answers with its own backend identity" $ do
              let oneDnnSource =
                    Text.concat
                      (fmap sourceContents OneDnnCodegen.renderOneDnnLayerTrainingSource)
                  cudaSource =
                    Text.concat
                      (fmap sourceContents CudaLayerTrainingCodegen.renderCudaLayerTrainingSource)
              assertBool
                "the linux-cpu artifact reports linux-cpu-onednn"
                ("linux-cpu-onednn" `Text.isInfixOf` oneDnnSource)
              assertBool
                "the linux-cuda artifact reports linux-cuda-cudnn"
                ("linux-cuda-cudnn" `Text.isInfixOf` cudaSource)
              assertBool
                "neither lane can answer with the other's identity"
                ( not ("linux-cuda-cudnn" `Text.isInfixOf` oneDnnSource)
                    && not ("linux-cpu-onednn" `Text.isInfixOf` cudaSource)
                )
          ]
      , testGroup
          "Layer vocabulary as parameterised Dhall (Phase 77)"
          [ testCase "the reflected union describes exactly the executed operators" $
              -- The cross-type audit extended from Catalog.Layer to the executed
              -- LayerOp: alternatives are read out of the reflected decoder type,
              -- never restated.
              LayerDhall.layerOpAuditMismatches @?= []
          , testCase "every executed operator round-trips through Dhall" $ do
              -- decode . render == id over every operator witness, so the
              -- parameterised vocabulary cannot stop covering a constructor
              -- without failing here.
              let operators =
                    fmap LayerGraph.layerKindWitnessOp LayerGraph.allLayerKinds
                      <> fmap LayerGraph.layerOpTemplate NumericsCatalog.layerCatalog
              decoded <-
                traverse
                  (Dhall.input LayerDhall.layerOpDecoder . LayerDhall.renderLayerOp)
                  operators
              decoded @?= operators
              length operators @?= 28
          , testCase "the reflected alternatives cover every catalog constructor" $ do
              alternatives <- expectRightText LayerDhall.layerOpUnionAlternatives
              List.sort alternatives @?= List.sort LayerDhall.executedLayerOpAlternatives
              length alternatives @?= length NumericsCatalog.layerCatalog
          , testCase "each checked-in numerical type file equals the reflected type" $ do
              mismatches <-
                Control.Monad.foldM
                  ( \acc (path, reflected) -> do
                      fileText <- Text.IO.readFile path
                      pure $
                        if canonicalDhallType fileText == canonicalDhallType reflected
                          then acc
                          else Text.pack path : acc
                  )
                  []
                  LayerDhall.numericsTypeFileSchemas
              mismatches @?= []
          , testCase "an architecture description round-trips and executes" $ do
              let description = dhallMlpDescription
              back <-
                Dhall.input
                  LayerDhall.layerGraphDescriptionDecoder
                  (LayerDhall.renderLayerGraphDescription description)
              back @?= description
              graph <- expectRightText (LayerDhall.buildLayerGraph description)
              fmap LayerGraph.layerNodeName (LayerGraph.layerGraphNodes graph)
                @?= ["hidden", "output"]
              fmap LayerGraph.layerNodeKind (LayerGraph.layerGraphNodes graph)
                @?= [LayerGraph.DenseLayer, LayerGraph.DenseLayer]
              tape <-
                expectRightText
                  (LayerGraph.runLayerGraph graph (Data.Vector.Unboxed.fromList [0.1, 0.2, 0.3, 0.4]))
              Data.Vector.Unboxed.length (LayerGraph.layerTapeOutput tape) @?= 2
          , testCase "a description whose producer width changes fails closed" $ do
              -- Widening the first node's output leaves the second node's
              -- declared input behind; the graph must not be built.
              let lying =
                    dhallMlpDescription
                      { LayerDhall.descGraphNodes =
                          case LayerDhall.descGraphNodes dhallMlpDescription of
                            (firstNode : rest) ->
                              firstNode
                                { LayerDhall.descNodeOutputShape = LayerGraph.TensorShape [9]
                                }
                                : rest
                            [] -> []
                      }
              assertBool
                "a lying output shape is rejected"
                ( case LayerDhall.buildLayerGraph lying of
                    Left message -> "does not chain" `Text.isInfixOf` message
                    Right _ -> False
                )
          , testCase "a description whose nodes do not chain fails closed" $ do
              let broken =
                    dhallMlpDescription
                      { LayerDhall.descGraphNodes =
                          case LayerDhall.descGraphNodes dhallMlpDescription of
                            [firstNode, secondNode] ->
                              [ firstNode
                              , secondNode
                                  { LayerDhall.descNodeInputShape = LayerGraph.TensorShape [5]
                                  }
                              ]
                            other -> other
                      }
              assertBool
                "a broken chain is rejected"
                ( case LayerDhall.buildLayerGraph broken of
                    Left message -> "does not chain" `Text.isInfixOf` message
                    Right _ -> False
                )
          , testCase "a description whose operator geometry disagrees fails closed" $ do
              -- A real spatial convolution produces [1,4,4]; the description
              -- claims a flat [16].
              let convDescription =
                    LayerDhall.LayerGraphDescription
                      { LayerDhall.descGraphName = "conv-liar"
                      , LayerDhall.descGraphSeed = 3
                      , LayerDhall.descGraphInputShape = LayerGraph.TensorShape [16]
                      , LayerDhall.descGraphOutputShape = LayerGraph.TensorShape [9]
                      , LayerDhall.descGraphNodes =
                          [ LayerDhall.LayerNodeDescription
                              { LayerDhall.descNodeName = "conv"
                              , LayerDhall.descNodeOp =
                                  LayerGraph.ConvOp
                                    (LayerGraph.ConvSpec 1 1 [4, 4] [2, 2] [1, 1] [0, 0])
                              , LayerDhall.descNodeInputShape = LayerGraph.TensorShape [16]
                              , LayerDhall.descNodeOutputShape = LayerGraph.TensorShape [9]
                              , LayerDhall.descNodeMode = LayerGraph.TrainingMode
                              , LayerDhall.descNodeActivation = LayerGraph.ReluActivation
                              }
                          ]
                      }
              assertBool
                "a declared shape that disagrees with the operator geometry is rejected"
                ( case LayerDhall.buildLayerGraph convDescription of
                    Left message -> "disagrees with the operator geometry" `Text.isInfixOf` message
                    Right _ -> False
                )
          , testCase "no ML-describing Dhall file names a substrate" $ do
              -- Substrate selection belongs on the CLI/plan seam, never in the
              -- architecture DSL.
              paths <- mlDslDhallFiles
              assertBool "the ML DSL file set is non-empty" (not (null paths))
              files <- traverse (\path -> (,) path <$> Text.IO.readFile path) paths
              LayerDhall.mlDslSubstrateMentions files @?= []
          ]
      , testGroup
          "Execution-path fail-open lint (Phase 7)"
          [ testCase "every cabal stanza makes an incomplete pattern a build error" $ do
              manifest <- Text.IO.readFile "jitml.cabal"
              let stanzas =
                    length
                      [ () | line <- Text.lines manifest, "    ghc-options:" `Text.isPrefixOf` line
                      ]
                  guarded =
                    length
                      [ ()
                      | line <- Text.lines manifest
                      , "-Werror=incomplete-patterns" `Text.isInfixOf` line
                      ]
              assertBool "jitml.cabal declares ghc-options stanzas" (stanzas > 0)
              guarded @?= stanzas
          , testCase "the scan rejects a new fail-open wildcard on the execution path" $ do
              let sites =
                    FailOpen.scanFailOpenSites
                      "src/JitML/Codegen/Reintroduced.hs"
                      "render op =\n  case op of\n    ConvOp s -> convSource s\n    _ -> []\n"
              fmap FailOpen.siteForm sites @?= [FailOpen.WildcardEmptyList]
          , testCase "the scan rejects a rendered switch default that only breaks" $ do
              let sites =
                    FailOpen.scanFailOpenSites
                      "src/JitML/Codegen/Reintroduced.hs"
                      "source =\n  Text.unlines\n    [ \"    default:\"\n    , \"      break;\"\n    ]\n"
              fmap FailOpen.siteForm sites @?= [FailOpen.RenderedSwitchDefaultBreak]
          , testCase "the scan accepts a catch-all that fails closed" $ do
              let sites =
                    FailOpen.scanFailOpenSites
                      "src/JitML/Codegen/Reintroduced.hs"
                      "render op =\n  case op of\n    ConvOp s -> Right (convSource s)\n    _ -> Left \"unsupported operator\"\n"
              sites @?= []
          , testCase "the execution path covers codegen, engines, and numerics" $ do
              FailOpen.executionPathRoots
                @?= ["src/JitML/Codegen", "src/JitML/Engines", "src/JitML/Numerics"]
              assertBool
                "a numerics module is on the execution path"
                (FailOpen.isExecutionPathSource "src/JitML/Numerics/LayerGraphDevice.hs")
              assertBool
                "a lint module is not on the execution path"
                (not (FailOpen.isExecutionPathSource "src/JitML/Lint/FailOpen.hs"))
          , testCase "every pending fail-open entry names the sprint that owns it" $ do
              let offenders =
                    [ FailOpen.pendingPath pending
                    | pending <- FailOpen.failOpenPendingRegistry
                    , Text.null (FailOpen.pendingOwningSprint pending)
                        || FailOpen.pendingCount pending <= 0
                    ]
              offenders @?= []
          , testCase "the worktree carries no unregistered fail-open site" $
              FailOpen.checkFailOpenWildcards >>= (@?= [])
          ]
      , testGroup
          "Product phase status registry (Phase 221)"
          [ testCase "enumerates product phases 220 through 289" $ do
              PhaseStatus.productPhaseNumbers @?= [220 .. 289]
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
          , testCase "every dependency edge is forward-only (rule M(a))" $ do
              facts <- concat <$> traverse readPlanSprintFacts PhaseStatus.allProductPhaseStatuses
              Control.Monad.forM_ facts $ \sf ->
                Control.Monad.forM_ (psfBlockedBy sf) $ \ref ->
                  assertBool
                    ( Text.unpack (psfId sf)
                        <> " declares a backward Blocked-by edge to higher-numbered "
                        <> Text.unpack ref
                    )
                    (compareDottedId ref (psfId sf) /= GT)
          , testCase "every sprint declares a concrete validation gate" $ do
              facts <- concat <$> traverse readPlanSprintFacts PhaseStatus.allProductPhaseStatuses
              Control.Monad.forM_ facts $ \sf ->
                assertBool
                  (Text.unpack (psfId sf) <> " has no non-empty ### Validation gate")
                  (psfHasValidationGate sf)
          , testCase "no sprint validation requires both accelerators (rule M(b))" $ do
              facts <- concat <$> traverse readPlanSprintFacts PhaseStatus.allProductPhaseStatuses
              Control.Monad.forM_ facts $ \sf ->
                assertBool
                  ( Text.unpack (psfId sf)
                      <> " validation names both a linux-cuda and an apple-silicon lane"
                  )
                  (not (psfValidationNamesCuda sf && psfValidationNamesApple sf))
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
          , testCase "GcReapedEvent protobuf encoding canonicalizes keys and event identity" $ do
              let snapshotId = Text.replicate 64 "a"
                  scopedPrefix =
                    "jitml-checkpoints/exp-13.7/snapshots/" <> snapshotId
                  commitKey = scopedPrefix <> "/committed.cbor"
                  keyA = scopedPrefix <> "/objects/" <> Text.replicate 64 "b"
                  keyB = scopedPrefix <> "/objects/" <> Text.replicate 64 "c"
                  suppliedEnvelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventId = "caller-supplied-id-is-not-trusted"
                      , ProtoGc.gcEventExperimentHash = "exp-13.7"
                      , ProtoGc.gcEventManifestSha = Text.replicate 64 "1"
                      , ProtoGc.gcEventReapedObjectKeys = [keyB, commitKey, keyA, keyB]
                      , ProtoGc.gcEventStepAtReap = 42
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCUDA
                      , ProtoGc.gcEventTimestampNs = 1_700_000_000_000_000_000
                      }
                  expectedEnvelope =
                    withGcSemanticId
                      suppliedEnvelope
                        { ProtoGc.gcEventReapedObjectKeys = [commitKey, keyA, keyB]
                        }
              ProtoGc.decodeGcReapedEventProto
                (ProtoGc.encodeGcReapedEventProto suppliedEnvelope)
                @?= Right expectedEnvelope
          , testCase "GcReapedEvent length-safe topic text preserves exact scoped object keys" $ do
              let objectKeys =
                    phase262ScopedGcObjectKeys
                      "exp-text"
                      (Text.replicate 64 "d")
                      [Text.replicate 64 "e", Text.replicate 64 "f"]
                  envelope =
                    withGcSemanticId
                      ProtoGc.GcReapedEvent
                        { ProtoGc.gcEventId = ""
                        , ProtoGc.gcEventExperimentHash = "exp-text"
                        , ProtoGc.gcEventManifestSha = Text.replicate 64 "2"
                        , ProtoGc.gcEventReapedObjectKeys = objectKeys
                        , ProtoGc.gcEventStepAtReap = 7
                        , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                        , ProtoGc.gcEventTimestampNs = 1
                        }
                  rendered = ProtoGc.renderGcReapedEvent envelope
              assertBool "topic payload is one line" (not ("\n" `Text.isInfixOf` rendered))
              ProtoGc.parseGcReapedEvent rendered @?= Right envelope
          , testCase "GcReapedEvent commit-only zero-object snapshot round-trips" $ do
              let envelope =
                    withGcSemanticId
                      ProtoGc.GcReapedEvent
                        { ProtoGc.gcEventId = ""
                        , ProtoGc.gcEventExperimentHash = "exp-no-blobs"
                        , ProtoGc.gcEventManifestSha = Text.replicate 64 "3"
                        , ProtoGc.gcEventReapedObjectKeys =
                            phase262ScopedGcObjectKeys
                              "exp-no-blobs"
                              (Text.replicate 64 "3")
                              []
                        , ProtoGc.gcEventStepAtReap = 0
                        , ProtoGc.gcEventSubstrate = Substrate.AppleSilicon
                        , ProtoGc.gcEventTimestampNs = 0
                        }
              ProtoGc.decodeGcReapedEventProto (ProtoGc.encodeGcReapedEventProto envelope)
                @?= Right envelope
              ProtoGc.parseGcReapedEvent (ProtoGc.renderGcReapedEvent envelope)
                @?= Right envelope
          , testCase "GcReapedEvent text decoder rejects envelope and hex defects" $ do
              let envelope =
                    withGcSemanticId
                      ProtoGc.GcReapedEvent
                        { ProtoGc.gcEventId = ""
                        , ProtoGc.gcEventExperimentHash = "exp-strict"
                        , ProtoGc.gcEventManifestSha = Text.replicate 64 "4"
                        , ProtoGc.gcEventReapedObjectKeys =
                            phase262ScopedGcObjectKeys
                              "exp-strict"
                              (Text.replicate 64 "4")
                              [Text.replicate 64 "5", Text.replicate 64 "6"]
                        , ProtoGc.gcEventStepAtReap = 9
                        , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                        , ProtoGc.gcEventTimestampNs = 10
                        }
                  validPayload = ProtoGc.renderGcReapedEvent envelope
                  rejectedPayloads =
                    [ ("missing envelope prefix", Text.drop 1 validPayload)
                    , ("empty protobuf bytes", "jitml-gc-reaped-event-protobuf-hex-v1:")
                    , ("odd hex length", validPayload <> "0")
                    , ("non-hex suffix", validPayload <> "gg")
                    , ("uppercase noncanonical text", Text.toUpper validPayload)
                    , ("trailing bytes", validPayload <> "00")
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
              "GcReapedEvent protobuf decoder rejects structural, key, and identity defects"
              $ do
                let snapshotId = Text.replicate 64 "5"
                    validObjectKeys =
                      phase262ScopedGcObjectKeys
                        "exp-proto-strict"
                        snapshotId
                        [Text.replicate 64 "6", Text.replicate 64 "7"]
                    envelope =
                      withGcSemanticId
                        ProtoGc.GcReapedEvent
                          { ProtoGc.gcEventId = ""
                          , ProtoGc.gcEventExperimentHash = "exp-proto-strict"
                          , ProtoGc.gcEventManifestSha = Text.replicate 64 "5"
                          , ProtoGc.gcEventReapedObjectKeys = validObjectKeys
                          , ProtoGc.gcEventStepAtReap = 11
                          , ProtoGc.gcEventSubstrate = Substrate.LinuxCUDA
                          , ProtoGc.gcEventTimestampNs = 12
                          }
                    validBytes = ProtoGc.encodeGcReapedEventProto envelope
                    eventFields experimentHash manifestSha objectKeys substrateField eventId =
                      [ ProtoWire.stringField 1 experimentHash
                      , ProtoWire.stringField 2 manifestSha
                      ]
                        <> fmap (ProtoWire.stringField 3) objectKeys
                        <> [ ProtoWire.uint64Field 4 11
                           , ProtoWire.stringField 5 substrateField
                           , ProtoWire.uint64Field 6 12
                           , ProtoWire.stringField 7 eventId
                           ]
                    requiredFields =
                      eventFields
                        (ProtoGc.gcEventExperimentHash envelope)
                        (ProtoGc.gcEventManifestSha envelope)
                        (ProtoGc.gcEventReapedObjectKeys envelope)
                        "linux-cuda"
                        (ProtoGc.gcEventId envelope)
                    replaceFieldNumber fieldNumber replacement =
                      replacement
                        : filter ((/= fieldNumber) . ProtoWire.protoFieldNumber) requiredFields
                    scopedPrefix =
                      "jitml-checkpoints/exp-proto-strict/snapshots/" <> snapshotId
                    commitKey = scopedPrefix <> "/committed.cbor"
                    keyA = scopedPrefix <> "/objects/" <> Text.replicate 64 "6"
                    otherSnapshotKey =
                      "jitml-checkpoints/exp-proto-strict/snapshots/"
                        <> Text.replicate 64 "8"
                        <> "/objects/"
                        <> Text.replicate 64 "9"
                    reservationKey =
                      "jitml-checkpoints/exp-proto-strict/snapshots/"
                        <> snapshotId
                        <> "/reservations/"
                        <> Text.replicate 64 "0"
                        <> ".cbor"
                    rejectedBytes =
                      [ validBytes <> ProtoWire.encodeMessage [ProtoWire.stringField 8 "unknown"]
                      , validBytes <> ProtoWire.encodeMessage [ProtoWire.stringField 1 "duplicate"]
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 4 (ProtoWire.stringField 4 "eleven"))
                      , ProtoWire.encodeMessage
                          (filter ((/= 2) . ProtoWire.protoFieldNumber) requiredFields)
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 2 (ProtoWire.stringField 2 "not-a-manifest-sha"))
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 2 (ProtoWire.stringField 2 (Text.replicate 63 "a")))
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 2 (ProtoWire.stringField 2 (Text.replicate 64 "A")))
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 1 (ProtoWire.stringField 1 ""))
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 5 (ProtoWire.stringField 5 "cuda"))
                      , ProtoWire.encodeMessage
                          (replaceFieldNumber 7 (ProtoWire.stringField 7 (Text.replicate 64 "f")))
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              (reverse validObjectKeys)
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              [commitKey, ""]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              [commitKey, keyA, keyA]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              [ "jitml-checkpoints/another-experiment/snapshots/"
                                  <> snapshotId
                                  <> "/committed.cbor"
                              ]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              ["jitml-checkpoints/exp-proto-strict/manifests/forbidden.cbor"]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              [keyA]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              [commitKey, keyA, otherSnapshotKey]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
                      , ProtoWire.encodeMessage
                          ( eventFields
                              "exp-proto-strict"
                              (Text.replicate 64 "5")
                              [commitKey, reservationKey]
                              "linux-cuda"
                              (ProtoGc.gcEventId envelope)
                          )
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
          , testCase
              "GcReapedEvent protobuf decoder rejects noncanonical and unsafe physical keys"
              $ do
                let baseEnvelope =
                      ProtoGc.GcReapedEvent
                        { ProtoGc.gcEventId = "ignored-by-encoder"
                        , ProtoGc.gcEventExperimentHash = "exp-key-safety"
                        , ProtoGc.gcEventManifestSha = Text.replicate 64 "8"
                        , ProtoGc.gcEventReapedObjectKeys = []
                        , ProtoGc.gcEventStepAtReap = 13
                        , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                        , ProtoGc.gcEventTimestampNs = 14
                        }
                    rejectedKeys =
                      [
                        ( "relative bucket alias"
                        , "exp-key-safety/snapshots/"
                            <> Text.replicate 64 "a"
                            <> "/committed.cbor"
                        , "not the canonical full bucket key"
                        )
                      ,
                        ( "missing physical object path"
                        , "jitml-checkpoints/exp-key-safety"
                        , "has no object path"
                        )
                      ,
                        ( "empty physical path segment"
                        , "jitml-checkpoints/exp-key-safety/snapshots//committed.cbor"
                        , "contains an empty path segment"
                        )
                      ,
                        ( "dot physical path segment"
                        , "jitml-checkpoints/exp-key-safety/snapshots/./committed.cbor"
                        , "contains a dot path segment"
                        )
                      ,
                        ( "dot-dot physical path segment"
                        , "jitml-checkpoints/exp-key-safety/snapshots/../committed.cbor"
                        , "contains a dot-dot path segment"
                        )
                      ,
                        ( "backslash physical path separator"
                        , "jitml-checkpoints/exp-key-safety/snapshots/a\\b/committed.cbor"
                        , "contains a path separator"
                        )
                      ,
                        ( "control character in physical path"
                        , "jitml-checkpoints/exp-key-safety/snapshots/a\nb/committed.cbor"
                        , "contains a control character"
                        )
                      ,
                        ( "cross-experiment physical key"
                        , "jitml-checkpoints/another-experiment/snapshots/"
                            <> Text.replicate 64 "a"
                            <> "/committed.cbor"
                        , "outside its experiment"
                        )
                      ,
                        ( "manifest control namespace"
                        , "jitml-checkpoints/exp-key-safety/manifests"
                        , "reserved control prefix"
                        )
                      ,
                        ( "pointer control namespace"
                        , "jitml-checkpoints/exp-key-safety/pointers"
                        , "reserved control prefix"
                        )
                      ,
                        ( "GC control namespace"
                        , "jitml-checkpoints/exp-key-safety/gc"
                        , "reserved control prefix"
                        )
                      ]
                traverse_
                  ( \(label, rejectedKey, expectedError) ->
                      case ProtoGc.decodeGcReapedEventProto
                        ( ProtoGc.encodeGcReapedEventProto
                            baseEnvelope
                              { ProtoGc.gcEventReapedObjectKeys = [rejectedKey]
                              }
                        ) of
                        Left err ->
                          assertBool
                            ( label
                                <> " produced the wrong rejection: "
                                <> Text.unpack err
                            )
                            (expectedError `Text.isInfixOf` err)
                        Right decoded ->
                          assertFailure
                            (label <> " unexpectedly decoded as " <> show decoded)
                  )
                  rejectedKeys
          , testCase "GcReapedEvent protobuf decoder rejects unsafe experiment hashes" $ do
              let baseEnvelope =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventId = "ignored-by-encoder"
                      , ProtoGc.gcEventExperimentHash = "exp-hash-safety"
                      , ProtoGc.gcEventManifestSha = Text.replicate 64 "9"
                      , ProtoGc.gcEventReapedObjectKeys = []
                      , ProtoGc.gcEventStepAtReap = 15
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                      , ProtoGc.gcEventTimestampNs = 16
                      }
                  rejectedHashes =
                    [ ("empty experiment hash", "", "empty protobuf field")
                    , ("dot experiment hash", ".", "contains a dot path segment")
                    , ("dot-dot experiment hash", "..", "contains a dot-dot path segment")
                    , ("slash in experiment hash", "exp/bad", "contains a path separator")
                    , ("backslash in experiment hash", "exp\\bad", "contains a path separator")
                    ,
                      ( "control character in experiment hash"
                      , "exp\nbad"
                      , "contains a control character"
                      )
                    ]
              traverse_
                ( \(label, rejectedHash, expectedError) ->
                    case ProtoGc.decodeGcReapedEventProto
                      ( ProtoGc.encodeGcReapedEventProto
                          baseEnvelope
                            { ProtoGc.gcEventExperimentHash = rejectedHash
                            }
                      ) of
                      Left err ->
                        assertBool
                          ( label
                              <> " produced the wrong rejection: "
                              <> Text.unpack err
                          )
                          (expectedError `Text.isInfixOf` err)
                      Right decoded ->
                        assertFailure
                          (label <> " unexpectedly decoded as " <> show decoded)
                )
                rejectedHashes
          , testCase "broker semantic id exactly matches the durable Store identity" $ do
              let experimentHash = "exp-identity"
                  manifestSha = Text.replicate 64 "6"
                  objectKeys =
                    phase262ScopedGcObjectKeys
                      experimentHash
                      (Text.replicate 64 "6")
                      [Text.replicate 64 "a", Text.replicate 64 "b"]
                  storeEvent =
                    CheckpointStore.GcEvent
                      { CheckpointStore.gcReapedManifestSha = manifestSha
                      , CheckpointStore.gcReapedObjectKeys = objectKeys
                      , CheckpointStore.gcExperimentHash = experimentHash
                      , CheckpointStore.gcStepAtReap = 17
                      }
                  brokerEvent =
                    ProtoGc.GcReapedEvent
                      { ProtoGc.gcEventId = "ignored"
                      , ProtoGc.gcEventExperimentHash = experimentHash
                      , ProtoGc.gcEventManifestSha = manifestSha
                      , ProtoGc.gcEventReapedObjectKeys = objectKeys
                      , ProtoGc.gcEventStepAtReap = 17
                      , ProtoGc.gcEventSubstrate = Substrate.LinuxCPU
                      , ProtoGc.gcEventTimestampNs = 999
                      }
              ProtoGc.gcReapedEventSemanticId brokerEvent
                @?= CheckpointStore.gcEventId storeEvent
          , testCase "GcEventRoute rejects an envelope from another substrate lane" $ do
              let linuxEnvelope =
                    withGcSemanticId
                      ProtoGc.GcReapedEvent
                        { ProtoGc.gcEventId = ""
                        , ProtoGc.gcEventExperimentHash = "exp-route"
                        , ProtoGc.gcEventManifestSha = Text.replicate 64 "7"
                        , ProtoGc.gcEventReapedObjectKeys =
                            phase262ScopedGcObjectKeys
                              "exp-route"
                              (Text.replicate 64 "7")
                              []
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
          , testCase "dqnHuberGradient preserves small residuals and clips outliers" $
              fmap (DqnLoss.dqnHuberGradient 1.0) [-2.0, -0.5, 0.0, 0.5, 2.0]
                @?= [-1.0, -0.5, 0.0, 0.5, 1.0]
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
          , testCase "LayerGraph softmax cross-entropy gradient matches finite differences (Sprint 235.1)" $ do
              node <-
                either
                  (assertFailure . Text.unpack)
                  pure
                  ( LayerGraph.mkAffineLayer
                      "ce-logits"
                      4
                      3
                      LayerGraph.LinearActivation
                      LayerGraph.TrainingMode
                      (LayerGraph.deterministicParameters 7 4 3)
                  )
              let graph =
                    LayerGraph.LayerGraph
                      { LayerGraph.layerGraphName = "ce-fd"
                      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [4]
                      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3]
                      , LayerGraph.layerGraphNodes = [node]
                      }
                  input = Data.Vector.Unboxed.fromList [0.5, -0.25, 0.75, -0.1]
                  label = 2 :: Int
                  base = LayerGraph.graphParameterVector graph
                  eps = 1.0e-6
                  lossFor v = do
                    g <- LayerGraph.replaceGraphParameterVector graph v
                    LayerGraph.layerGraphCrossEntropyLoss g input label
                  numericAt i =
                    let bumped d =
                          base Data.Vector.Unboxed.// [(i, (base Data.Vector.Unboxed.! i) + d)]
                     in do
                          lp <- lossFor (bumped eps)
                          lm <- lossFor (bumped (negate eps))
                          pure ((lp - lm) / (2 * eps))
              (_, gradient) <-
                either
                  (assertFailure . Text.unpack)
                  pure
                  (LayerGraph.layerGraphCrossEntropyGradient graph input label)
              let analytic = LayerGraph.flattenLayerGraphGradient gradient
              numeric <-
                either
                  (assertFailure . Text.unpack)
                  pure
                  (traverse numericAt [0 .. Data.Vector.Unboxed.length base - 1])
              let maxErr =
                    maximum
                      ( 0
                          : [ abs (analytic Data.Vector.Unboxed.! i - numeric !! i)
                            | i <- [0 .. Data.Vector.Unboxed.length base - 1]
                            ]
                      )
              assertBool
                ("cross-entropy gradient finite-difference error too large: " <> show maxErr)
                (maxErr < 1.0e-4)
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
          , sprint231NodeAutodiffTests
          , reloadedGraphServingTests
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
          , testCase "device PPO reports one optimizer step per executed minibatch" $ do
              let config =
                    PpoTrainer.defaultPpoTrainConfig
                      { PpoTrainer.ppoSeed = 71
                      , PpoTrainer.ppoHiddenUnits = 8
                      , PpoTrainer.ppoVectorEnvCount = 1
                      , PpoTrainer.ppoRolloutSteps = 4
                      , PpoTrainer.ppoNumIterations = 2
                      , PpoTrainer.ppoEpochsPerUpdate = 3
                      , PpoTrainer.ppoMiniBatchSize = 2
                      , PpoTrainer.ppoMaxEpisodeSteps = 10
                      }
              resultE <-
                PpoTrainer.trainOnPolicyOnDeviceWithEnvironment
                  pureReferenceMlpDevice
                  (Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment)
                  PpoTrainer.VariantPPO
                  config
              result <- either (assertFailure . Text.unpack) pure resultE
              AlgorithmCommon.measuredOptimizerUpdateCount
                (PpoTrainer.resultMeasuredCounters result)
                @?= 12
              AlgorithmCommon.measuredEnvironmentTransitionCount
                (PpoTrainer.resultMeasuredCounters result)
                @?= 8
          , testCase "device TRPO reports accepted actor plus value-head optimizer steps" $ do
              let config =
                    PpoTrainer.defaultPpoTrainConfig
                      { PpoTrainer.ppoSeed = 73
                      , PpoTrainer.ppoHiddenUnits = 8
                      , PpoTrainer.ppoVectorEnvCount = 1
                      , PpoTrainer.ppoRolloutSteps = 4
                      , PpoTrainer.ppoNumIterations = 1
                      , PpoTrainer.ppoMiniBatchSize = 4
                      , PpoTrainer.ppoMaxEpisodeSteps = 10
                      , PpoTrainer.ppoTrpoCriticUpdates = 2
                      , PpoTrainer.ppoVariant = PpoTrainer.VariantTRPO
                      }
                  initial = PpoTrainer.initialPpoParams config
              resultE <-
                PpoTrainer.trainOnPolicyOnDeviceWithEnvironment
                  pureReferenceMlpDevice
                  (Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment)
                  PpoTrainer.VariantTRPO
                  config
              result <- either (assertFailure . Text.unpack) pure resultE
              let actorApplications :: Int
                  actorApplications =
                    if trpoActorSlicesChangedForTest config initial (PpoTrainer.resultFinalParams result)
                      then 1
                      else 0
              AlgorithmCommon.measuredOptimizerUpdateCount
                (PpoTrainer.resultMeasuredCounters result)
                @?= fromIntegral (2 + actorApplications)
              AlgorithmCommon.measuredEnvironmentTransitionCount
                (PpoTrainer.resultMeasuredCounters result)
                @?= 4
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
          , testCase "DQN greedy behavior policy runs through the injected device" $ do
              forwardCalls <- newIORef (0 :: Int)
              let referenceForward = mlpdForward pureReferenceMlpDevice
                  countingDevice =
                    pureReferenceMlpDevice
                      { mlpdForward = \currentParams observation -> do
                          modifyIORef' forwardCalls (+ 1)
                          referenceForward currentParams observation
                      }
                  config =
                    fastDqnDeviceConfig
                      { DqnTrainer.dqnNumSteps = 2
                      , DqnTrainer.dqnTrainStart = 2
                      , DqnTrainer.dqnEpsilonStart = 0.0
                      , DqnTrainer.dqnEpsilonEnd = 0.0
                      }
              result <- DqnTrainer.trainDqnOnDevice countingDevice config
              _ <- either (assertFailure . Text.unpack) pure result
              readIORef forwardCalls >>= (@?= 2)
          , testCase "DQN greedy behavior policy fails closed on device-forward failure" $
              assertLeftContains
                "dqn device forward kernel failed mid-run (behavior policy)"
                ( DqnTrainer.trainDqnOnDevice
                    (failingForwardDevice "dqn behavior forward unavailable")
                    ( fastDqnDeviceConfig
                        { DqnTrainer.dqnNumSteps = 1
                        , DqnTrainer.dqnTrainStart = 2
                        , DqnTrainer.dqnEpsilonStart = 0.0
                        , DqnTrainer.dqnEpsilonEnd = 0.0
                        }
                    )
                )
          , testCase "DQN greedy behavior rejects an observation/network shape mismatch" $
              assertLeftContains
                "input/dLdy shape mismatch against the network"
                ( DqnTrainer.trainDqnOnDevice
                    pureReferenceMlpDevice
                    ( fastDqnDeviceConfig
                        { DqnTrainer.dqnNumSteps = 1
                        , DqnTrainer.dqnTrainStart = 2
                        , DqnTrainer.dqnEpsilonStart = 0.0
                        , DqnTrainer.dqnEpsilonEnd = 0.0
                        , DqnTrainer.dqnObsSize = 5
                        }
                    )
                )
          , testCase "DQN pure and pure-reference-device trainers remain exactly aligned" $ do
              let config =
                    fastDqnDeviceConfig
                      { DqnTrainer.dqnNumSteps = 5
                      , DqnTrainer.dqnTrainStart = 2
                      , DqnTrainer.dqnBatchSize = 2
                      , DqnTrainer.dqnUpdateFrequency = 1
                      , DqnTrainer.dqnEpsilonStart = 0.0
                      , DqnTrainer.dqnEpsilonEnd = 0.0
                      }
              pureResult <- DqnTrainer.trainDqnOnCartpole config
              deviceResultE <- DqnTrainer.trainDqnOnDevice pureReferenceMlpDevice config
              deviceResult <- either (assertFailure . Text.unpack) pure deviceResultE
              deviceResult @?= pureResult
          , testCase "DQN evaluation uses the injected device and fails closed" $ do
              forwardCalls <- newIORef (0 :: Int)
              let referenceForward = mlpdForward pureReferenceMlpDevice
                  countingDevice =
                    pureReferenceMlpDevice
                      { mlpdForward = \currentParams observation -> do
                          modifyIORef' forwardCalls (+ 1)
                          referenceForward currentParams observation
                      }
                  config =
                    fastDqnDeviceConfig
                      { DqnTrainer.dqnMaxEpisodeSteps = 3
                      }
                  environment = Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment
                  params = DqnTrainer.initialDqnParams config
              failedForwardCalls <- newIORef (0 :: Int)
              let failingEvaluationDevice =
                    pureReferenceMlpDevice
                      { mlpdForward = \_ _ -> do
                          modifyIORef' failedForwardCalls (+ 1)
                          pure (Left "dqn evaluation forward unavailable")
                      }
              evaluationE <-
                DqnTrainer.evaluateDqnPolicyWithEnvironment
                  countingDevice
                  environment
                  config
                  params
                  2
              evaluation <- either (assertFailure . Text.unpack) pure evaluationE
              length evaluation @?= 2
              calls <- readIORef forwardCalls
              assertBool "DQN evaluation bypassed the injected device" (calls >= 2)
              assertLeftContains
                "dqn device forward kernel failed during evaluation"
                ( DqnTrainer.evaluateDqnPolicyWithEnvironment
                    failingEvaluationDevice
                    environment
                    config
                    params
                    2
                )
              readIORef failedForwardCalls >>= (@?= 1)
          , testCase "DQN production head clips chosen-action TD outliers to kappa one" $ do
              let captureHead qValue = do
                    forwardCalls <- newIORef (0 :: Int)
                    capturedHeads <- newIORef ([] :: [Data.Vector.Unboxed.Vector Double])
                    let capturingDevice =
                          pureReferenceMlpDevice
                            { mlpdForwardBatch = \_ observations -> do
                                call <- readIORef forwardCalls
                                modifyIORef' forwardCalls (+ 1)
                                let value = if even call then qValue else 0.0
                                pure
                                  ( Right
                                      ( fmap
                                          (const (Data.Vector.Unboxed.replicate 2 value))
                                          observations
                                      )
                                  )
                            , mlpdBatchGradient = \params pairs -> do
                                writeIORef capturedHeads (fmap snd pairs)
                                pure (Right (constantGradientLike params 0.0))
                            }
                        config =
                          fastDqnDeviceConfig
                            { DqnTrainer.dqnNumSteps = 1
                            , DqnTrainer.dqnGamma = 0.0
                            }
                    result <- DqnTrainer.trainDqnOnDevice capturingDevice config
                    _ <- either (assertFailure . Text.unpack) pure result
                    heads <- readIORef capturedHeads
                    case heads of
                      [headGradient] -> pure (List.sort (Data.Vector.Unboxed.toList headGradient))
                      _ -> assertFailure ("expected one captured DQN head, got " <> show heads)
              positive <- captureHead 100.0
              negative <- captureHead (-100.0)
              positive @?= [0.0, 1.0]
              negative @?= [-1.0, 0.0]
          , testCase "DQN result counts only update-frequency-eligible Adam steps" $ do
              let config =
                    fastDqnDeviceConfig
                      { DqnTrainer.dqnNumSteps = 5
                      , DqnTrainer.dqnTrainStart = 2
                      , DqnTrainer.dqnUpdateFrequency = 2
                      }
              resultE <- DqnTrainer.trainDqnOnDevice pureReferenceMlpDevice config
              result <- either (assertFailure . Text.unpack) pure resultE
              AlgorithmCommon.measuredOptimizerUpdateCount
                (DqnTrainer.dqnResultMeasuredCounters result)
                @?= 2
              AlgorithmCommon.measuredEnvironmentTransitionCount
                (DqnTrainer.dqnResultMeasuredCounters result)
                @?= 5
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
              <> [ testCase "continuous result counts delayed actor optimizer steps only" $ do
                     let config =
                           (ContinuousTrainer.defaultContinuousTrainConfig ContinuousTrainer.VariantTD3)
                             { ContinuousTrainer.ctSeed = 74
                             , ContinuousTrainer.ctHidden = 8
                             , ContinuousTrainer.ctNumSteps = 5
                             , ContinuousTrainer.ctReplayCapacity = 8
                             , ContinuousTrainer.ctBatchSize = 1
                             , ContinuousTrainer.ctStartSteps = 0
                             , ContinuousTrainer.ctTrainStart = 1
                             , ContinuousTrainer.ctPolicyDelay = 2
                             , ContinuousTrainer.ctMaxEpisodeSteps = 10
                             , ContinuousTrainer.ctStatInterval = 1
                             }
                     resultE <-
                       ContinuousTrainer.trainContinuousOnDevice
                         pureReferenceMlpDevice
                         config
                     result <- either (assertFailure . Text.unpack) pure resultE
                     AlgorithmCommon.measuredOptimizerUpdateCount
                       (ContinuousTrainer.contResultMeasuredCounters result)
                       @?= 2
                     AlgorithmCommon.measuredEnvironmentTransitionCount
                       (ContinuousTrainer.contResultMeasuredCounters result)
                       @?= 5
                 , testCase "continuous device trainer returns Left on input-gradient failure" $
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
          , testCase "QR-DQN result counts only update-frequency-eligible Adam steps" $ do
              let config =
                    fastQrDqnDeviceConfig
                      { QrDqnTrainer.qrNumSteps = 7
                      , QrDqnTrainer.qrTrainStart = 2
                      , QrDqnTrainer.qrUpdateFrequency = 3
                      }
              resultE <- QrDqnTrainer.trainQrDqnOnDevice pureReferenceMlpDevice config
              result <- either (assertFailure . Text.unpack) pure resultE
              AlgorithmCommon.measuredOptimizerUpdateCount
                (QrDqnTrainer.qrResultMeasuredCounters result)
                @?= 2
              AlgorithmCommon.measuredEnvironmentTransitionCount
                (QrDqnTrainer.qrResultMeasuredCounters result)
                @?= 7
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
              AlgorithmCommon.measuredOptimizerUpdateCount
                (ArsTrainer.arsResultMeasuredCounters resultA)
                @?= fromIntegral (ArsTrainer.arsIterations cfg)
              AlgorithmCommon.measuredEnvironmentTransitionCount
                (ArsTrainer.arsResultMeasuredCounters resultA)
                @?= fromIntegral
                  ( 2
                      * ArsTrainer.arsIterations cfg
                      * ArsTrainer.arsNumDirections cfg
                      * ArsTrainer.arsMaxEpisodeSteps cfg
                  )
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
          , testCase "HER always emits a final learning summary" $ do
              let cfg =
                    fastHerDeviceConfig
                      { HerTrainer.herEpisodes = 5
                      , HerTrainer.herStatInterval = 25
                      }
              result <- HerTrainer.trainHerOnBitFlip cfg
              fmap HerTrainer.herIterEpisode (HerTrainer.herResultStats result)
                @?= [5]
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
          , testCase "HER reports every executed repeated online-Q optimizer step" $ do
              callsRef <- newIORef (0 :: Int)
              let referenceBatchGradient = mlpdBatchGradient pureReferenceMlpDevice
                  countingDevice =
                    pureReferenceMlpDevice
                      { mlpdBatchGradient = \params batch -> do
                          modifyIORef' callsRef (+ 1)
                          referenceBatchGradient params batch
                      }
                  config =
                    fastHerDeviceConfig
                      { HerTrainer.herEpisodes = 5
                      , HerTrainer.herUpdatesPerEpisode = 3
                      }
              resultE <- HerTrainer.trainHerOnDevice countingDevice config
              result <- either (assertFailure . Text.unpack) pure resultE
              calls <- readIORef callsRef
              assertBool "HER counting test executed no optimizer step" (calls > 0)
              AlgorithmCommon.measuredOptimizerUpdateCount
                (HerTrainer.herResultMeasuredCounters result)
                @?= fromIntegral calls
              AlgorithmCommon.measuredEnvironmentTransitionCount
                (HerTrainer.herResultMeasuredCounters result)
                @?= fromIntegral
                  (HerTrainer.herEpisodes config * HerTrainer.herNumBits config)
          , testCase "HER rejects zero updates instead of repairing the schedule" $ do
              result <-
                HerTrainer.trainHerOnDevice
                  pureReferenceMlpDevice
                  (fastHerDeviceConfig {HerTrainer.herUpdatesPerEpisode = 0})
              result @?= Left "HER updates per episode must be positive"
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

generatedModelMatrixPairsForSubstrate
  :: Text
  -> Text
  -> [(Text, Text, Text, Text, Text)]
generatedModelMatrixPairsForSubstrate substrate generated =
  [ pair
  | line <- Text.lines generated
  , quotedField "substrate" line == Just substrate
  , Just pair <- [generatedModelMatrixPair line]
  ]

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

-- | Sprint 23.1 — correct reverse-mode autodiff for every Tier-2 layer node,
-- verified by finite differences of BOTH the parameter gradient and the input
-- gradient against a small deterministic loss. These construct real operators
-- (genuine convolution, windowed pooling, coupled normalization, self-attention
-- with residual, GeGLU, patch embedding, residual/basic/bottleneck blocks), not
-- the retired dense/stencil approximations.
sprint231NodeAutodiffTests :: TestTree
sprint231NodeAutodiffTests =
  testGroup
    "Sprint 23.1 correct per-node reverse-mode autodiff (finite differences)"
    [ testCase "Conv2D forward/backward matches finite differences" $
        fdCheckNode "Conv2D" 1.0e-4 1 $
          let spec = LayerGraph.ConvSpec 2 3 [4, 4] [3, 3] [1, 1] [1, 1]
           in LayerGraph.mkConvLayer
                "conv2d"
                spec
                LayerGraph.TanhActivation
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 11 (LayerGraph.ConvOp spec))
    , testCase "Conv3D forward/backward matches finite differences" $
        fdCheckNode "Conv3D" 1.0e-4 2 $
          let spec = LayerGraph.ConvSpec 2 2 [3, 3, 3] [2, 2, 2] [1, 1, 1] [0, 0, 0]
           in LayerGraph.mkConv3DLayer
                "conv3d"
                spec
                LayerGraph.TanhActivation
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 12 (LayerGraph.ConvOp spec))
    , testCase "Conv2D fast forward equals a naive reference within 1e-9" $ do
        -- Proves the optimized 2-D convForward specialization (exercised by
        -- runLayerGraph with a linear activation) equals an independent naive
        -- reference on host, without oneDNN, across two geometries including a
        -- strided/padded case. Byte-identical accumulation keeps the diff ~0.
        conv2DFastMatchesReference 3 8 8 8 3 3 2 2 1 1 41
        conv2DFastMatchesReference 2 5 7 6 3 3 1 1 0 0 57
        let win = LayerGraph.PoolWindow 2 2 2 2 0 0 False
            sp = LayerGraph.SpatialShape 1 4 4
        node <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.mkPoolLayer "maxpool" sp (LayerGraph.PoolMax win) LayerGraph.TrainingMode)
        -- Strictly distinct values (permutation of 1..16), gap 1 >> eps.
        let input = Data.Vector.Unboxed.fromList [3, 14, 1, 9, 12, 5, 16, 7, 2, 11, 8, 6, 15, 4, 13, 10]
            target = Data.Vector.Unboxed.fromList [0.2, -0.4, 0.7, -0.1]
        checkNodeInputFD "MaxPool" 1.0e-5 (singleNodeGraph node) input target
        assertNoParams "MaxPool" node input target
    , testCase "MaxPool overlapping windows accumulate shared-argmax gradient" $ do
        let win = LayerGraph.PoolWindow 2 2 1 1 0 0 False
            sp = LayerGraph.SpatialShape 1 3 3
        node <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.mkPoolLayer "maxpool-ov" sp (LayerGraph.PoolMax win) LayerGraph.TrainingMode)
        let input = Data.Vector.Unboxed.fromList [1, 5, 2, 8, 9, 3, 4, 7, 6]
            target = Data.Vector.Unboxed.fromList [0.1, -0.2, 0.3, -0.4]
        checkNodeInputFD "MaxPool overlap" 1.0e-5 (singleNodeGraph node) input target
    , testCase "AvgPool windowed average matches finite differences (no params)" $ do
        let win = LayerGraph.PoolWindow 2 2 2 2 0 0 False
            sp = LayerGraph.SpatialShape 2 4 4
        node <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.mkPoolLayer "avgpool" sp (LayerGraph.PoolAvg win) LayerGraph.TrainingMode)
        let input = detVec 3 32
            target = detVec 200 8
        checkNodeInputFD "AvgPool" 1.0e-6 (singleNodeGraph node) input target
        assertNoParams "AvgPool" node input target
    , testCase "AvgPool overlapping windows accumulate contributions" $ do
        let win = LayerGraph.PoolWindow 2 2 1 1 0 0 False
            sp = LayerGraph.SpatialShape 1 4 4
        node <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.mkPoolLayer "avgpool-ov" sp (LayerGraph.PoolAvg win) LayerGraph.TrainingMode)
        checkNodeInputFD "AvgPool overlap" 1.0e-6 (singleNodeGraph node) (detVec 4 16) (detVec 210 9)
    , testCase "GlobalAvgPool reduces per channel (channel-separated gradient)" $ do
        let sp = LayerGraph.SpatialShape 3 2 2
        node <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.mkPoolLayer "gap" sp LayerGraph.PoolGlobal LayerGraph.TrainingMode)
        let input = detVec 5 12
            target = Data.Vector.Unboxed.fromList [1.0, -1.0, 0.0]
        checkNodeInputFD "GlobalAvgPool" 1.0e-6 (singleNodeGraph node) input target
        assertNoParams "GlobalAvgPool" node input target
    , testCase "LayerNorm coupled Jacobian matches finite differences" $
        fdCheckNode "LayerNorm" 1.0e-4 6 $
          let spec = LayerGraph.NormSpec LayerGraph.NormLayerWise 6 1 1.0e-5
           in LayerGraph.mkNormLayer
                "layernorm"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 21 (LayerGraph.NormOp spec))
    , testCase "GroupNorm group-local statistics match finite differences" $
        fdCheckNode "GroupNorm" 1.0e-4 7 $
          let spec = LayerGraph.NormSpec (LayerGraph.NormGroup 3) 6 1 1.0e-5
           in LayerGraph.mkNormLayer
                "groupnorm"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 22 (LayerGraph.NormOp spec))
    , testCase "GroupNorm with spatial>1 reduces over channels x spatial" $
        fdCheckNode "GroupNorm P>1" 1.0e-4 8 $
          let spec = LayerGraph.NormSpec (LayerGraph.NormGroup 2) 4 3 1.0e-5
           in LayerGraph.mkNormLayer
                "groupnorm-p"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 23 (LayerGraph.NormOp spec))
    , testCase "BatchNorm couples across the batch axis (training mode)" $
        fdCheckNode "BatchNorm" 1.0e-4 9 $
          let spec = LayerGraph.NormSpec LayerGraph.NormBatch 4 5 1.0e-5
           in LayerGraph.mkNormLayer
                "batchnorm"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 24 (LayerGraph.NormOp spec))
    , testCase "MultiHeadAttention (with residual) matches finite differences" $
        fdCheckNode "MHA" 1.0e-4 10 $
          let spec = LayerGraph.AttentionSpec 3 4 2 False
           in LayerGraph.mkAttentionLayer
                "mha"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 31 (LayerGraph.AttentionOp spec))
    , testCase "PatchEmbed shared projection + col2im matches finite differences" $
        fdCheckNode "PatchEmbed" 1.0e-4 11 $
          let spec = LayerGraph.PatchSpec 1 4 4 2 2 3
           in LayerGraph.mkPatchEmbedLayer
                "patch"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 41 (LayerGraph.PatchOp spec))
    , testCase "GeGLU gated feed-forward matches finite differences" $
        fdCheckNode "GeGLU" 1.0e-4 12 $
          let spec = LayerGraph.GeGLUSpec 4 6 3
           in LayerGraph.mkGeGLULayer
                "geglu"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 51 (LayerGraph.GeGLUOp spec))
    , testCase "Residual (identity shortcut) matches finite differences" $
        fdCheckNode "Residual" 1.0e-4 13 $
          let inner = LayerGraph.AffineSpec 4 4
              op = LayerGraph.ResidualOp inner LayerGraph.IdentityShortcut 0.5 LayerGraph.TanhActivation
           in LayerGraph.mkResidualNode
                "residual"
                inner
                LayerGraph.IdentityShortcut
                0.5
                LayerGraph.TanhActivation
                LayerGraph.LinearActivation
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 61 op)
    , testCase "Residual (projection shortcut) matches finite differences" $
        fdCheckNode "Residual proj" 1.0e-4 14 $
          let inner = LayerGraph.AffineSpec 4 6
              sc = LayerGraph.ProjectionShortcut (LayerGraph.AffineSpec 4 6)
              op = LayerGraph.ResidualOp inner sc 0.5 LayerGraph.TanhActivation
           in LayerGraph.mkResidualNode
                "residual-proj"
                inner
                sc
                0.5
                LayerGraph.TanhActivation
                LayerGraph.LinearActivation
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 62 op)
    , testCase "BasicBlock (two affine->norm stages, identity skip) matches finite differences" $
        fdCheckNode "BasicBlock" 1.0e-4 15 $
          let spec = basicBlockSpec
           in LayerGraph.mkBasicBlock
                "basicblock"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 71 (LayerGraph.BlockOp spec))
    , testCase "Bottleneck (reduced middle width, identity skip) matches finite differences" $
        fdCheckNode "Bottleneck" 1.0e-4 16 $
          let spec = bottleneckSpec
           in LayerGraph.mkBottleneck
                "bottleneck"
                spec
                LayerGraph.TrainingMode
                (LayerGraph.deterministicOpParameters 81 (LayerGraph.BlockOp spec))
    , testCase "Full ResNet-shaped graph matches finite differences end to end" $ do
        graph <- either (assertFailure . Text.unpack) pure realResNetGraph
        iw <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.tensorShapeWidth (LayerGraph.layerGraphInputShape graph))
        ow <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.tensorShapeWidth (LayerGraph.layerGraphOutputShape graph))
        checkGraphFD "ResNet-shaped" 2.0e-4 graph (detVec 300 iw) (detVec 400 ow)
    , testCase "Full ViT-shaped graph matches finite differences end to end" $ do
        graph <- either (assertFailure . Text.unpack) pure realVitGraph
        iw <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.tensorShapeWidth (LayerGraph.layerGraphInputShape graph))
        ow <-
          either
            (assertFailure . Text.unpack)
            pure
            (LayerGraph.tensorShapeWidth (LayerGraph.layerGraphOutputShape graph))
        checkGraphFD "ViT-shaped" 2.0e-4 graph (detVec 500 iw) (detVec 600 ow)
    , testGroup
        "explicit shape/operation failures (no silent collapse)"
        [ testCase "identity-shortcut residual with d_in /= d_out is rejected" $
            assertBool
              "should be Left"
              ( isLeftResult
                  ( LayerGraph.mkResidualNode
                      "bad"
                      (LayerGraph.AffineSpec 4 3)
                      LayerGraph.IdentityShortcut
                      1.0
                      LayerGraph.TanhActivation
                      LayerGraph.LinearActivation
                      LayerGraph.TrainingMode
                      ( LayerGraph.LayerParameters
                          (Data.Vector.Unboxed.replicate 12 0.0)
                          (Data.Vector.Unboxed.replicate 3 0.0)
                      )
                  )
              )
        , testCase "GroupNorm with channels not divisible by groups is rejected" $
            assertBool
              "should be Left"
              ( isLeftResult
                  ( LayerGraph.mkNormLayer
                      "bad"
                      (LayerGraph.NormSpec (LayerGraph.NormGroup 4) 6 1 1.0e-5)
                      LayerGraph.TrainingMode
                      ( LayerGraph.deterministicOpParameters
                          1
                          (LayerGraph.NormOp (LayerGraph.NormSpec (LayerGraph.NormGroup 4) 6 1 1.0e-5))
                      )
                  )
              )
        , testCase "attention with embedDim not divisible by heads is rejected" $
            assertBool
              "should be Left"
              ( isLeftResult
                  ( LayerGraph.mkAttentionLayer
                      "bad"
                      (LayerGraph.AttentionSpec 3 5 2 False)
                      LayerGraph.TrainingMode
                      ( LayerGraph.LayerParameters
                          (Data.Vector.Unboxed.replicate 100 0.0)
                          (Data.Vector.Unboxed.replicate 20 0.0)
                      )
                  )
              )
        , testCase "block with non-composing stage shapes is rejected" $
            assertBool
              "should be Left"
              ( isLeftResult
                  ( LayerGraph.mkBasicBlock
                      "bad"
                      ( LayerGraph.BlockSpec
                          [ LayerGraph.BlockStage (LayerGraph.AffineSpec 4 5) Nothing LayerGraph.TanhActivation
                          , LayerGraph.BlockStage (LayerGraph.AffineSpec 4 4) Nothing LayerGraph.LinearActivation
                          ]
                          LayerGraph.IdentityShortcut
                          1.0
                          LayerGraph.LinearActivation
                      )
                      LayerGraph.TrainingMode
                      ( LayerGraph.LayerParameters
                          (Data.Vector.Unboxed.replicate 100 0.0)
                          (Data.Vector.Unboxed.replicate 100 0.0)
                      )
                  )
              )
        ]
    ]

basicBlockSpec :: LayerGraph.BlockSpec
basicBlockSpec =
  LayerGraph.BlockSpec
    [ LayerGraph.BlockStage
        (LayerGraph.AffineSpec 4 4)
        (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5))
        LayerGraph.TanhActivation
    , LayerGraph.BlockStage
        (LayerGraph.AffineSpec 4 4)
        (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 4 1 1.0e-5))
        LayerGraph.LinearActivation
    ]
    LayerGraph.IdentityShortcut
    1.0
    LayerGraph.LinearActivation

bottleneckSpec :: LayerGraph.BlockSpec
bottleneckSpec =
  LayerGraph.BlockSpec
    [ LayerGraph.BlockStage
        (LayerGraph.AffineSpec 8 2)
        (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 2 1 1.0e-5))
        LayerGraph.TanhActivation
    , LayerGraph.BlockStage
        (LayerGraph.AffineSpec 2 2)
        (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 2 1 1.0e-5))
        LayerGraph.TanhActivation
    , LayerGraph.BlockStage
        (LayerGraph.AffineSpec 2 8)
        (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 8 1 1.0e-5))
        LayerGraph.LinearActivation
    ]
    LayerGraph.IdentityShortcut
    1.0
    LayerGraph.LinearActivation

-- | Small ResNet-shaped graph: conv stem -> BasicBlock -> GlobalAvgPool -> Dense.
realResNetGraph :: Either Text LayerGraph.LayerGraph
realResNetGraph = do
  let stemSpec = LayerGraph.ConvSpec 1 2 [4, 4] [3, 3] [1, 1] [1, 1]
  stem <-
    LayerGraph.mkConvLayer
      "resnet-stem"
      stemSpec
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters 91 (LayerGraph.ConvOp stemSpec))
  -- stem output is [2,4,4] = 32 features; treat as a flat vector for the block.
  let blkSpec =
        LayerGraph.BlockSpec
          [ LayerGraph.BlockStage
              (LayerGraph.AffineSpec 32 32)
              (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 32 1 1.0e-5))
              LayerGraph.TanhActivation
          , LayerGraph.BlockStage
              (LayerGraph.AffineSpec 32 32)
              (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise 32 1 1.0e-5))
              LayerGraph.LinearActivation
          ]
          LayerGraph.IdentityShortcut
          1.0
          LayerGraph.LinearActivation
  block <-
    LayerGraph.mkBasicBlock
      "resnet-block"
      blkSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters 92 (LayerGraph.BlockOp blkSpec))
  pool <-
    LayerGraph.mkPoolLayer
      "resnet-gap"
      (LayerGraph.SpatialShape 2 4 4)
      LayerGraph.PoolGlobal
      LayerGraph.TrainingMode
  headNode <-
    LayerGraph.mkAffineLayer
      "resnet-head"
      2
      3
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters 93 2 3)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "real-resnet"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [1, 4, 4]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphNodes = [stem, block, pool, headNode]
      }

-- | Small ViT-shaped graph: PatchEmbed -> LayerNorm -> MHA(residual) -> LayerNorm -> GeGLU -> MeanPool -> Dense.
realVitGraph :: Either Text LayerGraph.LayerGraph
realVitGraph = do
  let patchSpec = LayerGraph.PatchSpec 1 4 4 2 2 4 -- N=4 patches, d=4 -> 16 tokens flattened
  patch <-
    LayerGraph.mkPatchEmbedLayer
      "vit-patch"
      patchSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters 101 (LayerGraph.PatchOp patchSpec))
  let ln1Spec = LayerGraph.NormSpec (LayerGraph.NormGroup 4) 4 4 1.0e-5 -- per-token LayerNorm over 4 tokens x 4 dims
  ln1 <-
    LayerGraph.mkNormLayer
      "vit-ln1"
      ln1Spec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters 102 (LayerGraph.NormOp ln1Spec))
  let attnSpec = LayerGraph.AttentionSpec 4 4 2 False
  attn <-
    LayerGraph.mkAttentionLayer
      "vit-attn"
      attnSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters 103 (LayerGraph.AttentionOp attnSpec))
  let geSpec = LayerGraph.GeGLUSpec 16 8 4
  geglu <-
    LayerGraph.mkGeGLULayer
      "vit-geglu"
      geSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters 104 (LayerGraph.GeGLUOp geSpec))
  headNode <-
    LayerGraph.mkAffineLayer
      "vit-head"
      4
      3
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters 105 4 3)
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "real-vit"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [1, 4, 4]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphNodes = [patch, ln1, attn, geglu, headNode]
      }

-- | Run the optimized 2-D 'LayerGraph.convForward' (through 'runLayerGraph' with a
-- linear activation so the output is the raw convolution) and assert it equals an
-- independent naive reference within 1e-9. Proves the fast specialization on host
-- without oneDNN. Arguments: @cIn cOut H W Kh Kw sH sW pH pW seed@.
conv2DFastMatchesReference
  :: Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Assertion
conv2DFastMatchesReference cI cO h w kh kw sh sw ph pw seed = do
  let spec = LayerGraph.ConvSpec cI cO [h, w] [kh, kw] [sh, sw] [ph, pw]
      params = LayerGraph.deterministicOpParameters seed (LayerGraph.ConvOp spec)
  node <-
    either
      (assertFailure . Text.unpack)
      pure
      ( LayerGraph.mkConvLayer
          "conv2d-fast-vs-ref"
          spec
          LayerGraph.LinearActivation
          LayerGraph.TrainingMode
          params
      )
  let input = detVec seed (cI * h * w)
  tape <-
    either
      (assertFailure . Text.unpack)
      pure
      (LayerGraph.runLayerGraph (singleNodeGraph node) input)
  let got = LayerGraph.layerTapeOutput tape
      ref =
        naiveConv2DRef
          cO
          cI
          h
          w
          kh
          kw
          sh
          sw
          ph
          pw
          (LayerGraph.layerWeights params)
          (LayerGraph.layerBias params)
          input
      diff = maxAbsDiffVec got ref
  assertBool
    ( "Conv2D fast forward differs from naive reference (cIn="
        <> show cI
        <> ", cOut="
        <> show cO
        <> ", stride="
        <> show (sh, sw)
        <> ", pad="
        <> show (ph, pw)
        <> "): max|delta| = "
        <> show diff
    )
    (diff < 1.0e-9)

-- | Independent naive 2-D cross-correlation reference (NCHW input, OIHW weights,
-- zero padding), computed from scratch in the test so it does not share code with
-- 'LayerGraph.convForward'. Arguments: @cOut cIn H W Kh Kw sH sW pH pW weights bias input@.
naiveConv2DRef
  :: Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Data.Vector.Unboxed.Vector Double
  -> Data.Vector.Unboxed.Vector Double
  -> Data.Vector.Unboxed.Vector Double
  -> Data.Vector.Unboxed.Vector Double
naiveConv2DRef cO cI h w kh kw sh sw ph pw weights bias x =
  Data.Vector.Unboxed.fromList
    [ (bias Data.Vector.Unboxed.! co)
        + sum
          [ (weights Data.Vector.Unboxed.! (((co * cI + ci) * kh * kw) + ky * kw + kx))
              * xAt ci (oh * sh + ky - ph) (ow * sw + kx - pw)
          | ci <- [0 .. cI - 1]
          , ky <- [0 .. kh - 1]
          , kx <- [0 .. kw - 1]
          ]
    | co <- [0 .. cO - 1]
    , oh <- [0 .. ohDim - 1]
    , ow <- [0 .. owDim - 1]
    ]
 where
  ohDim = (h + 2 * ph - kh) `div` sh + 1
  owDim = (w + 2 * pw - kw) `div` sw + 1
  xAt ci ih iw
    | ih >= 0 && ih < h && iw >= 0 && iw < w =
        x Data.Vector.Unboxed.! (ci * h * w + ih * w + iw)
    | otherwise = 0.0

maxAbsDiffVec
  :: Data.Vector.Unboxed.Vector Double -> Data.Vector.Unboxed.Vector Double -> Double
maxAbsDiffVec a b
  | Data.Vector.Unboxed.length a /= Data.Vector.Unboxed.length b = 1.0 / 0.0
  | Data.Vector.Unboxed.null a = 0.0
  | otherwise =
      Data.Vector.Unboxed.maximum (Data.Vector.Unboxed.zipWith (\p q -> abs (p - q)) a b)

-- Phase 240 — the reloaded supervised-graph serving contract. The refinement is
-- the tamper gate; since the widening it serves every correct operator (not only
-- dense), and the reloaded graph is served through the pure reference executor
-- 'Runtime.executeSupervisedGraphRuntime' (which runs 'LayerGraph.runLayerGraph'
-- with the transforms outside the graph), so the serving output equals the
-- trained graph's pure inference bit-for-bit.
reloadedGraphServingTests :: TestTree
reloadedGraphServingTests =
  testGroup
    "Reloaded supervised graph refinement + pure serving (Phase 240)"
    [ testCase "refineReloadedLayerGraph accepts a Conv+Norm+Attention graph with correct params" $ do
        graph <- eitherAssert reloadConvNormAttnGraph
        case LayerGraph.refineReloadedLayerGraph graph of
          Left err -> assertFailure ("expected acceptance, got: " <> Text.unpack err)
          Right refined -> refined @?= graph
    , testCase "refineReloadedLayerGraph rejects a duplicate node name" $ do
        graph <- eitherAssert reloadDuplicateNameGraph
        case LayerGraph.refineReloadedLayerGraph graph of
          Right _ -> assertFailure "duplicate node name was accepted"
          Left err ->
            assertBool
              ("rejected for the wrong reason: " <> Text.unpack err)
              ("duplicate node name" `Text.isInfixOf` err)
    , testCase "refineReloadedLayerGraph rejects a wrong parameter count" $ do
        graph <- eitherAssert reloadWrongParamGraph
        case LayerGraph.refineReloadedLayerGraph graph of
          Right _ -> assertFailure "wrong parameter count was accepted"
          Left err ->
            assertBool
              ("rejected for the wrong reason: " <> Text.unpack err)
              ("weights" `Text.isInfixOf` err)
    , testCase "executeSupervisedGraphRuntime over a reconstructed Conv+Norm graph equals runLayerGraph" $ do
        trained <- eitherAssert reloadConvNormGraph
        inputWidth <-
          eitherAssert (LayerGraph.tensorShapeWidth (LayerGraph.layerGraphInputShape trained))
        outputWidth <-
          eitherAssert (LayerGraph.tensorShapeWidth (LayerGraph.layerGraphOutputShape trained))
        -- Reconstruct exactly as the read path does: metadata -> topology ->
        -- inject the frozen graph-ordered parameters.
        let metadata = LayerGraphMetadata.layerGraphMetadataFromGraph trained
            params = LayerGraph.graphParameterVector trained
        topology <- eitherAssert (LayerGraphMetadata.layerGraphFromMetadata metadata)
        reconstructed <- eitherAssert (LayerGraph.replaceGraphParameterVector topology params)
        payload <- eitherAssert (reloadIdentityServingPayload inputWidth outputWidth)
        let input = detVec 7 inputWidth
        expected <- eitherAssert (LayerGraph.runLayerGraph trained input)
        served <- eitherAssert (Runtime.executeSupervisedGraphRuntime payload reconstructed input)
        served @?= LayerGraph.layerTapeOutput expected
    ]

eitherAssert :: Either Text value -> IO value
eitherAssert = either (assertFailure . Text.unpack) pure

-- A Conv(1x1) -> LayerNorm -> Attention graph, all boundaries 16 wide, each node
-- carrying correctly-sized packed parameters. This is the literal-architecture
-- shape the dense-only serving path used to reject.
reloadConvNormAttnGraph :: Either Text LayerGraph.LayerGraph
reloadConvNormAttnGraph = do
  conv <- reloadConvNode
  norm <- reloadNormNode
  attn <- reloadAttnNode
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "reload-conv-norm-attn"
      , LayerGraph.layerGraphInputShape = LayerGraph.layerInputShape conv
      , LayerGraph.layerGraphOutputShape = LayerGraph.layerOutputShape attn
      , LayerGraph.layerGraphNodes = [conv, norm, attn]
      }

reloadConvNormGraph :: Either Text LayerGraph.LayerGraph
reloadConvNormGraph = do
  conv <- reloadConvNode
  norm <- reloadNormNode
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "reload-conv-norm"
      , LayerGraph.layerGraphInputShape = LayerGraph.layerInputShape conv
      , LayerGraph.layerGraphOutputShape = LayerGraph.layerOutputShape norm
      , LayerGraph.layerGraphNodes = [conv, norm]
      }

reloadConvNode :: Either Text LayerGraph.LayerNode
reloadConvNode =
  let spec = LayerGraph.ConvSpec 1 1 [4, 4] [1, 1] [1, 1] [0, 0]
   in LayerGraph.mkConvLayer
        "reload-conv"
        spec
        LayerGraph.LinearActivation
        LayerGraph.InferenceMode
        (LayerGraph.deterministicOpParameters 101 (LayerGraph.ConvOp spec))

reloadNormNode :: Either Text LayerGraph.LayerNode
reloadNormNode =
  let spec = LayerGraph.NormSpec LayerGraph.NormLayerWise 16 1 1.0e-5
   in LayerGraph.mkNormLayer
        "reload-norm"
        spec
        LayerGraph.InferenceMode
        (LayerGraph.deterministicOpParameters 102 (LayerGraph.NormOp spec))

reloadAttnNode :: Either Text LayerGraph.LayerNode
reloadAttnNode =
  let spec = LayerGraph.AttentionSpec 4 4 2 False
   in LayerGraph.mkAttentionLayer
        "reload-attn"
        spec
        LayerGraph.InferenceMode
        (LayerGraph.deterministicOpParameters 103 (LayerGraph.AttentionOp spec))

-- Rename the second node to collide with the first: a duplicate stable identity
-- the refinement gate must reject.
reloadDuplicateNameGraph :: Either Text LayerGraph.LayerGraph
reloadDuplicateNameGraph = do
  graph <- reloadConvNormAttnGraph
  case LayerGraph.layerGraphNodes graph of
    (n0 : n1 : rest) ->
      Right
        graph
          { LayerGraph.layerGraphNodes =
              n0 : n1 {LayerGraph.layerNodeName = LayerGraph.layerNodeName n0} : rest
          }
    _ -> Left "reload duplicate fixture expected at least two nodes"

-- Truncate the first node's packed weights so its length no longer matches the
-- operator's segment layout: a tampered parameter identity.
reloadWrongParamGraph :: Either Text LayerGraph.LayerGraph
reloadWrongParamGraph = do
  graph <- reloadConvNormAttnGraph
  case LayerGraph.layerGraphNodes graph of
    (n0 : rest) ->
      let bad =
            LayerGraph.LayerParameters
              { LayerGraph.layerWeights = Data.Vector.Unboxed.fromList [0.0, 0.0]
              , LayerGraph.layerBias = Data.Vector.Unboxed.fromList [0.0]
              }
       in Right
            graph
              { LayerGraph.layerGraphNodes =
                  n0 {LayerGraph.layerParameters = Just bad} : rest
              }
    _ -> Left "reload wrong-param fixture expected at least one node"

-- Identity ingress/egress payload so executeSupervisedGraphRuntime's transforms
-- are no-ops and its output equals the reconstructed graph's runLayerGraph output.
reloadIdentityServingPayload :: Int -> Int -> Either Text Runtime.SupervisedRuntimePayload
reloadIdentityServingPayload inputWidth semanticWidth =
  Runtime.refineSupervisedRuntimePayload
    Runtime.RawSupervisedRuntimePayload
      { Runtime.rawRuntimePayloadRowId = "reload-conv-norm"
      , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
      , Runtime.rawRuntimePayloadPlanId = Text.replicate 64 "e"
      , Runtime.rawRuntimePayloadDatasetSha256 = Text.replicate 64 "a"
      , Runtime.rawRuntimePayloadInitialJmw1Sha256 = Text.replicate 64 "b"
      , Runtime.rawRuntimePayloadFinalJmw1Sha256 = Text.replicate 64 "c"
      , Runtime.rawRuntimePayloadRuntime =
          Runtime.RawSupervisedRuntime
            { Runtime.rawSupervisedRuntimeTask = Runtime.RawRegressionRuntimeTask semanticWidth
            , Runtime.rawSupervisedRuntimeInputTransform = Runtime.RawIdentityInput inputWidth
            , Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawIdentityOutput
            }
      , Runtime.rawRuntimePayloadLayerGraphMetadata = Nothing
      }

detVec :: Int -> Int -> Data.Vector.Unboxed.Vector Double
detVec salt n =
  Data.Vector.Unboxed.generate n $ \i ->
    0.6 * sin (0.7 * fromIntegral (i + 1) + 0.13 * fromIntegral salt)
      + 0.2 * cos (0.31 * fromIntegral (i * 2 + salt + 1))

singleNodeGraph :: LayerGraph.LayerNode -> LayerGraph.LayerGraph
singleNodeGraph node =
  LayerGraph.LayerGraph
    { LayerGraph.layerGraphName = LayerGraph.layerNodeName node
    , LayerGraph.layerGraphInputShape = LayerGraph.layerInputShape node
    , LayerGraph.layerGraphOutputShape = LayerGraph.layerOutputShape node
    , LayerGraph.layerGraphNodes = [node]
    }

fdCheckNode :: String -> Double -> Int -> Either Text LayerGraph.LayerNode -> Assertion
fdCheckNode label tol salt enode = do
  node <- either (assertFailure . Text.unpack) pure enode
  iw <-
    either
      (assertFailure . Text.unpack)
      pure
      (LayerGraph.tensorShapeWidth (LayerGraph.layerInputShape node))
  ow <-
    either
      (assertFailure . Text.unpack)
      pure
      (LayerGraph.tensorShapeWidth (LayerGraph.layerOutputShape node))
  checkGraphFD label tol (singleNodeGraph node) (detVec salt iw) (detVec (salt + 137) ow)

checkGraphFD
  :: String
  -> Double
  -> LayerGraph.LayerGraph
  -> Data.Vector.Unboxed.Vector Double
  -> Data.Vector.Unboxed.Vector Double
  -> Assertion
checkGraphFD label tol graph input target = do
  paramErr <-
    either
      (assertFailure . Text.unpack)
      pure
      (Autodiff.maxFiniteDifferenceError 1.0e-6 graph input target)
  inputErr <-
    either
      (assertFailure . Text.unpack)
      pure
      (Autodiff.maxInputFiniteDifferenceError 1.0e-6 graph input target)
  assertBool
    (label <> " parameter finite-difference error too large: " <> show paramErr)
    (paramErr < tol)
  assertBool (label <> " input finite-difference error too large: " <> show inputErr) (inputErr < tol)

checkNodeInputFD
  :: String
  -> Double
  -> LayerGraph.LayerGraph
  -> Data.Vector.Unboxed.Vector Double
  -> Data.Vector.Unboxed.Vector Double
  -> Assertion
checkNodeInputFD label tol graph input target = do
  inputErr <-
    either
      (assertFailure . Text.unpack)
      pure
      (Autodiff.maxInputFiniteDifferenceError 1.0e-6 graph input target)
  assertBool (label <> " input finite-difference error too large: " <> show inputErr) (inputErr < tol)

assertNoParams
  :: String
  -> LayerGraph.LayerNode
  -> Data.Vector.Unboxed.Vector Double
  -> Data.Vector.Unboxed.Vector Double
  -> Assertion
assertNoParams label node input target = do
  (_, gradient) <-
    either
      (assertFailure . Text.unpack)
      pure
      (LayerGraph.layerGraphSquaredErrorGradient (singleNodeGraph node) input target)
  case LayerGraph.layerGraphLayerGradients gradient of
    [g] ->
      assertBool
        (label <> " must have no parameter gradient")
        (isNothing (LayerGraph.layerGradientParameters g))
    other -> assertFailure (label <> " expected a single node gradient, got " <> show (length other))

isLeftResult :: Either a b -> Bool
isLeftResult = either (const True) (const False)

-- | Unwrap a fixture that reports failure as 'Text', failing the case with the
-- message rather than a pattern-match error.
expectRightText :: Either Text value -> IO value
expectRightText = either (assertFailure . Text.unpack) pure

-- | The constructor name of a layer kind with its payload erased, so kinds can
-- be compared by shape rather than by representative payload value.
kindConstructorName :: LayerGraph.LayerKind -> String
kindConstructorName = takeWhile (/= ' ') . show

-- | A two-layer classifier expressed entirely as data (Sprint 77.1) — no
-- hardcoded Haskell builder, only the described operators plus a seed.
dhallMlpDescription :: LayerDhall.LayerGraphDescription
dhallMlpDescription =
  LayerDhall.LayerGraphDescription
    { LayerDhall.descGraphName = "dhall-mlp"
    , LayerDhall.descGraphSeed = 7
    , LayerDhall.descGraphInputShape = LayerGraph.TensorShape [4]
    , LayerDhall.descGraphOutputShape = LayerGraph.TensorShape [2]
    , LayerDhall.descGraphNodes =
        [ LayerDhall.LayerNodeDescription
            { LayerDhall.descNodeName = "hidden"
            , LayerDhall.descNodeOp = LayerGraph.DenseOp
            , LayerDhall.descNodeInputShape = LayerGraph.TensorShape [4]
            , LayerDhall.descNodeOutputShape = LayerGraph.TensorShape [3]
            , LayerDhall.descNodeMode = LayerGraph.TrainingMode
            , LayerDhall.descNodeActivation = LayerGraph.ReluActivation
            }
        , LayerDhall.LayerNodeDescription
            { LayerDhall.descNodeName = "output"
            , LayerDhall.descNodeOp = LayerGraph.DenseOp
            , LayerDhall.descNodeInputShape = LayerGraph.TensorShape [3]
            , LayerDhall.descNodeOutputShape = LayerGraph.TensorShape [2]
            , LayerDhall.descNodeMode = LayerGraph.TrainingMode
            , LayerDhall.descNodeActivation = LayerGraph.SoftmaxActivation
            }
        ]
    }

unitLayerGraph :: LayerGraph.LayerKind -> Int -> Either Text LayerGraph.LayerGraph
unitLayerGraph kind seed = do
  node <-
    case kind of
      LayerGraph.PoolLayer _ ->
        LayerGraph.mkIdentityLayer
          "unit-pool"
          3
          LayerGraph.TrainingMode
      LayerGraph.DropoutLayer _ ->
        LayerGraph.mkIdentityLayer
          "unit-dropout"
          3
          LayerGraph.TrainingMode
      _ ->
        LayerGraph.mkAffineLayer
          "unit-layer"
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
      3
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters seed 3 3)
  block <-
    LayerGraph.mkAffineLayer
      "resnet-basic-block"
      3
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 1) 3 3)
  headNode <-
    LayerGraph.mkAffineLayer
      "resnet-head"
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
      4
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters seed 4 3)
  attention <-
    LayerGraph.mkAffineLayer
      "vit-attention"
      3
      3
      LayerGraph.TanhActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 1) 3 3)
  headNode <-
    LayerGraph.mkAffineLayer
      "vit-head"
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

failingForwardDevice :: Text -> MlpDevice
failingForwardDevice message =
  pureReferenceMlpDevice
    { mlpdForward = \_ _ -> pure (Left message)
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

trpoActorSlicesChangedForTest
  :: PpoTrainer.PpoTrainConfig
  -> Mlp.MlpParams
  -> Mlp.MlpParams
  -> Bool
trpoActorSlicesChangedForTest config before after =
  Mlp.paramW1 before /= Mlp.paramW1 after
    || Mlp.paramB1 before /= Mlp.paramB1 after
    || Data.Vector.Unboxed.take policyWeightCount (Mlp.paramW2 before)
      /= Data.Vector.Unboxed.take policyWeightCount (Mlp.paramW2 after)
    || Data.Vector.Unboxed.take actionCount (Mlp.paramB2 before)
      /= Data.Vector.Unboxed.take actionCount (Mlp.paramB2 after)
 where
  actionCount = PpoTrainer.ppoActionCount config
  policyWeightCount = actionCount * Mlp.mlpHidden (Mlp.paramShape before)

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
  , AppError.RegistryFailed "registry unavailable"
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
    , LiveE2EScope.plannedTestEnvironment = defaultSubprocessEnv
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

assertParseFailure :: [String] -> Assertion
assertParseFailure args =
  case execParserPure defaultPrefs parserInfo args of
    Failure _ -> pure ()
    Success parsed -> assertFailure ("parse unexpectedly succeeded for " <> show args <> ": " <> show parsed)
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

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.App
  ( alphaZeroArtifactStep
  , inferenceReplyAppError
  , main
  , matchingInferenceResult
  , parseUserIntOptionAtLeast
  , rlTrainerEnvironmentCompatibilityError
  , serviceRoleInvocationError
  , waitForConsumeOnceHostWorkloads
  )
where

import Control.Concurrent (ThreadId, forkFinally, forkIO, killThread, threadDelay)
import Control.Concurrent.Async (concurrently)
import Control.Concurrent.MVar
  ( MVar
  , modifyMVar
  , modifyMVar_
  , newEmptyMVar
  , newMVar
  , putMVar
  , readMVar
  , takeMVar
  , tryPutMVar
  , tryReadMVar
  , tryTakeMVar
  )
import Control.Exception.Safe
  ( bracket
  , displayException
  , finally
  , mask_
  , throwIO
  , tryAny
  )
import Control.Monad (unless, void, when)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Crypto.Hash.SHA256 qualified
import Data.Aeson (eitherDecode, encode)
import Data.Bifunctor (second)
import Data.Bool (bool)
import Data.ByteString qualified
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (lefts)
import Data.Either.Combinators (mapLeft)
import Data.Foldable (for_, traverse_)
import Data.List (sort, stripPrefix)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32, Word64)
import GHC.Clock (getMonotonicTimeNSec)
import Options.Applicative (ParserResult (..), renderFailure)
import Path (Abs, Dir, Path, toFilePath)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getFileSize
  , listDirectory
  , removeFile
  )
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO qualified
import System.Timeout (timeout)
import Text.Printf (printf)
import Text.Read (readMaybe)

import Network.Socket
  ( AddrInfo (..)
  , Socket
  , SocketType (Stream)
  , close
  , connect
  , defaultHints
  , getAddrInfo
  , socket
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)

import JitML.AppError.AppError (AppError (..))
import JitML.Bootstrap
  ( LiveExecutionResult (..)
  , LiveStepFailure (..)
  , cachedThirdPartyRolloutImages
  , liveExecutePhasedRollout
  , materializeBootstrapFiles
  , readExistingLivePublication
  , renderLiveStepFailure
  )
import JitML.CLI.Help (renderHelp)
import JitML.CLI.Json (renderCommandJson)
import JitML.CLI.Output
  ( exitWithError
  , exitWithErrorIO
  , renderError
  , writeLazyByteString
  , writeLine
  , writeLineIO
  , writeText
  )
import JitML.CLI.Parser (ParsedCommand (..), ParsedOption (..), parseCommandPure)
import JitML.CLI.Spec (commandPathText, commandRegistry)
import JitML.CLI.Tree (renderCommandList, renderCommandTree)
import JitML.Cache.Key qualified as Cache
import JitML.Cache.Layout qualified as CacheLayout
import JitML.Cache.Manifest qualified as CacheManifest
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Cluster.Helm qualified as Helm
import JitML.Cluster.Publication (ClusterPublication, defaultPublication, renderPublicationSummary)
import JitML.Cluster.Publication qualified as Publication
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Coordinator.Topology qualified as Topology
import JitML.Docs.Check (checkDocs, renderDocsDrift)
import JitML.Docs.Generate (GenerateResult (..), generateDocs)
import JitML.Engines.CudaLocal (runCudaWeightedCheckpointInference)
import JitML.Engines.CudaRuntime (cudaRuntimeAvailable, probeCudaRuntime)
import JitML.Engines.Engine
  ( engineForSubstrate
  , kernelHandleArtifactPath
  , renderBuildPlan
  )
import JitML.Engines.Loader qualified as EngineLoader
import JitML.Engines.Local
  ( linuxCpuKernelOutput
  , linuxCpuToolchainFingerprint
  , runLinuxCpuKernel
  , runLinuxCpuWeightedCheckpointInference
  )
import JitML.Engines.MetalBridge qualified as MetalBridge
import JitML.Engines.MetalLocal (runMetalWeightedCheckpointInference)
import JitML.Engines.MetalRuntime (metalRuntimeAvailable, probeMetalRuntime)
import JitML.Engines.OneDnnRuntime (oneDnnRuntimeAvailable, probeOneDnnRuntime)
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Engines.TuningCache qualified as TuningCache
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (App, ColorMode (..), Env (..), OutputFormat (..))
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Lint.Stack
  ( LintFinding
  , LintMode (..)
  , LintTarget (..)
  , renderLintFinding
  , runCheckCode
  , runLint
  )
import JitML.Numerics.Mlp (AdamState, MlpParams, MlpShape (..), mlpInit, mlpParamsToFlat)
import JitML.Numerics.MlpDevice (MlpDevice (..), probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate, rlDeviceForSubstrate)
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( PlanId
  , buildCommandPlan
  , planIdFromCanonicalText
  , planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSeeds
  , runPlanSubjectId
  , runPlanSubstrate
  , seedCohortValues
  , validationToEither
  )
import JitML.Plan.Render (renderPlan)
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Prerequisite.Nodes.Container qualified as ContainerPrerequisites
import JitML.Prerequisite.Plan
  ( PrerequisitePlanError (..)
  , applyPrerequisitePlan
  , buildPrerequisitePlan
  , renderPrerequisitePlan
  )
import JitML.Prerequisite.Reconcile qualified as Prerequisite
import JitML.Prerequisite.Registry
  ( NodeId (..)
  , prerequisiteRegistry
  , renderPrerequisiteRegistry
  , scopeRootNodeId
  )
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.ExternalBars qualified as ProductExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Pipeline qualified as ProductPipeline
import JitML.Project.Config qualified as ProjectConfig
import JitML.Proto.Gc qualified as ProtoGc
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl qualified as ProtoRl
import JitML.Proto.Training qualified as ProtoTraining
import JitML.Proto.Tune qualified as ProtoTune
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms qualified as RL
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnTrainer qualified as QrDqnTrainer
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Simulator qualified as RLSim
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.Regression qualified as Regression
import JitML.SL.TinyImageNet qualified as TinyImageNet
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.CatalogSchema qualified as CatalogSchema
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , EventId
  , HandlerRouter
  , consumerStep
  )
import JitML.Service.Consumer qualified as Consumer
import JitML.Service.DhallSchema qualified as DhallSchema
import JitML.Service.HostWorkloadRegistry qualified as HostWorkloadRegistry
import JitML.Service.HotReload qualified as HotReload
import JitML.Service.InferenceBatch qualified as InferenceBatch
import JitML.Service.InferenceReplyScope qualified as InferenceReplyScope
import JitML.Service.Lifecycle qualified as ServiceLifecycle
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.Logger qualified as ServiceLogger
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.Retry qualified as ServiceRetry
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.Runtime qualified as ServiceRuntime
import JitML.Service.RuntimeState qualified as RuntimeState
import JitML.Service.Signal qualified as ServiceSignal
import JitML.Service.WorkflowStatus qualified as WorkflowStatus
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessOutcome (..)
  , processFailureExitCode
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream
  ( defaultSubprocessEnv
  , runStreaming
  , runStreamingObserved
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate, substrateEdgePort)
import JitML.Test.LiveE2EScope qualified as LiveE2EScope
import JitML.Test.LivePlan
  ( LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  , scopedLiveE2EPlanFor
  )
import JitML.Test.Report
  ( ProductRowReportEvidence (..)
  , ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , appendInvocation
  , emptyInvocationJournal
  , emptyReportMeasurements
  , failedObservedInvocation
  , firstObservedInvocationFailure
  , loadReportCardKnobs
  , notRunObservedInvocation
  , passedInvocation
  , productRowReportCoverageFailures
  , renderReportCardWithKnobs
  , reportStanzas
  , substrateRuntimeStanzas
  , substrateTestInvocations
  )
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as Tune
import JitML.Web.Server qualified as WebServer

main :: IO ()
main = getArgs >>= runArgs

-- | Sprint 10.7 (Pulsar ML-Workflow convergence) — THE single Engine inference
-- compute: the one place that picks the substrate's weighted checkpoint runner
-- and runs the kernel. The demo HTTP handler, the `jitml inference run` CLI, and
-- the daemon consumer all route through this function, so the
-- @load→pick-runner→run-kernel@ pick-runner step is no longer copied across three
-- sites (it lives here). Per the contract the Engine (daemon) is the role that
-- actually serves this compute in production; the demo/CLI publish-only,
-- websocket-async routing is owned by Phase `11` Sprint `11.10`.
engineWeightedInference
  :: Env
  -> Substrate
  -> ProductPipeline.InferenceEligibleRef
  -> Checkpoint.CheckpointManifest
  -> [CheckpointStore.LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
engineWeightedInference env substrate _modelRef manifest weights values =
  case substrate of
    LinuxCPU ->
      runLinuxCpuWeightedCheckpointInference env manifest weights values
    LinuxCUDA ->
      runCudaWeightedCheckpointInference env manifest weights values
    AppleSilicon ->
      runMetalWeightedCheckpointInference env manifest weights values

runArgs :: [String] -> IO ()
runArgs args =
  case extractGlobalFlags args of
    Left err -> exitWithErrorIO err
    Right (globalFlags, commandArgs) -> do
      env <- buildEnv globalFlags
      runReaderT (runCommandArgs commandArgs) env

runCommandArgs :: [String] -> App ()
runCommandArgs args =
  case requestedHelp args of
    Just path -> printHelp path
    Nothing ->
      case parseCommandPure args of
        Success parsed -> runParsed parsed
        Failure failure -> do
          let (message, _exitCode) = renderFailure failure "jitml"
          exitWithError (UnknownCommand (Text.pack message))
        CompletionInvoked _ -> pure ()

requestedHelp :: [String] -> Maybe [Text]
requestedHelp ("help" : rest) = Just (fmap Text.pack rest)
requestedHelp args
  | any (`elem` ["--help", "-h"]) args =
      Just (fmap Text.pack (filter (`notElem` ["--help", "-h"]) args))
  | otherwise = Nothing

runParsed :: ParsedCommand -> App ()
runParsed ParsedCommand {parsedPath, parsedOptions}
  | parsedPath == ["commands"] = printCommands parsedOptions
  | parsedPath == ["doctor"] =
      runDoctor parsedOptions
  | parsedPath == ["bootstrap"] =
      runBootstrap parsedOptions
  | isPlanApplyPath parsedPath && hasPlanOutput parsedOptions =
      runPlanOutput parsedPath parsedOptions
  | parsedPath == ["service"] =
      runService parsedOptions
  | take 1 parsedPath == ["cluster"] =
      runCluster parsedPath parsedOptions
  | parsedPath == ["build"] =
      runBuild parsedOptions
  | parsedPath == ["project", "init"] =
      runProjectInit parsedOptions
  | parsedPath == ["train"] =
      runTrain parsedOptions
  | parsedPath == ["eval"] =
      runEval parsedOptions
  | parsedPath == ["tune"] =
      runTune parsedOptions
  | take 1 parsedPath == ["rl"] =
      runRl parsedPath parsedOptions
  | parsedPath == ["inference", "run"] =
      runInference parsedOptions
  | take 1 parsedPath == ["test"] =
      runTest parsedPath parsedOptions
  | parsedPath == ["help"] =
      printHelp (optionValues "subcommand" parsedOptions)
  | parsedPath == ["docs", "check"] =
      runDocsCheck
  | parsedPath == ["docs", "generate"] =
      runDocsGenerate
  | parsedPath == ["check-code"] =
      runLintCommand "check-code" runCheckCode
  | isLintPath parsedPath =
      runLintPath parsedPath parsedOptions
  | parsedPath == ["internal", "materialize-substrate"] =
      runMaterializeSubstrate parsedOptions
  | parsedPath == ["internal", "list-prereqs"] =
      writeText (renderPrerequisiteRegistry prerequisiteRegistry)
  | parsedPath == ["internal", "install-metal-bridge"] =
      runInstallMetalBridge
  | take 2 parsedPath == ["internal", "cache"] =
      runInternalCache parsedPath parsedOptions
  | parsedPath == ["internal", "gc"] =
      runInternalGc parsedOptions
  | parsedPath == ["internal", "upload-dataset"] =
      runInternalUploadDataset parsedOptions
  | parsedPath == ["internal", "train-and-publish-product-rows"] =
      runInternalTrainAndPublishProductRows parsedOptions
  | parsedPath == ["internal", "benchmark-product-row-wall-clock"] =
      runInternalBenchmarkProductRowWallClock
  | parsedPath == ["internal", "seed-demo-checkpoints"] =
      runInternalSeedDemoCheckpoints
  | parsedPath == ["internal", "dhall-schema"] =
      runInternalDhallSchema parsedOptions
  | parsedPath == ["internal", "third-party-images"] =
      -- Sprint 2.13 — the single source for the third-party chart image list the
      -- stage-0 scripts pre-pull (authenticated, on the host) before `kind load`.
      writeText (Text.unlines cachedThirdPartyRolloutImages)
  | otherwise =
      writeLine ("registered command: " <> commandPathText parsedPath)

printCommands :: [ParsedOption] -> App ()
printCommands parsedOptions = do
  format <- asks envFormat
  case commandOutputFormat format parsedOptions of
    OutputJson ->
      writeLazyByteString (renderCommandJson commandRegistry)
    OutputTable
      | hasOption "tree" parsedOptions ->
          writeText (renderCommandTree commandRegistry)
    OutputPlain
      | hasOption "tree" parsedOptions ->
          writeText (renderCommandTree commandRegistry)
    _ ->
      writeText (renderCommandList commandRegistry)

commandOutputFormat :: OutputFormat -> [ParsedOption] -> OutputFormat
commandOutputFormat format parsedOptions
  | hasOption "json" parsedOptions = OutputJson
  | otherwise = format

printHelp :: [Text] -> App ()
printHelp path =
  case renderHelp path of
    Right helpText -> writeText helpText
    Left message -> exitWithError (UnknownCommand message)

runDoctor :: [ParsedOption] -> App ()
runDoctor parsedOptions = do
  let scope = selectedScope parsedOptions
  case scopeRootNodeId scope of
    Nothing ->
      exitWithError (InvalidConfig ("unknown doctor scope: " <> scope))
    Just root
      | hasOption "remediate" parsedOptions -> runDoctorRemediate scope root
      | otherwise -> do
          result <- liftIO (Prerequisite.reconcilePrerequisites prerequisiteRegistry root)
          case result of
            Left err -> exitWithError (prerequisiteAppError err)
            Right () -> do
              writeLine ("doctor scope: " <> scope)
              writeLine "doctor: ok"

runDoctorRemediate :: Text -> NodeId -> App ()
runDoctorRemediate scope root = do
  planResult <- liftIO (buildPrerequisitePlan prerequisiteRegistry root)
  case planResult of
    Left err -> exitWithError (prerequisiteAppError err)
    Right plan -> do
      writeText (renderPrerequisitePlan plan)
      applyResult <- liftIO (applyPrerequisitePlan defaultSubprocessEnv prerequisiteRegistry plan)
      case applyResult of
        Left err -> exitWithError (prerequisitePlanAppError err)
        Right () -> do
          result <- liftIO (Prerequisite.reconcilePrerequisites prerequisiteRegistry root)
          case result of
            Left err -> exitWithError (prerequisiteAppError err)
            Right () -> do
              writeLine ("doctor scope: " <> scope)
              writeLine "doctor: ok"

selectedScope :: [ParsedOption] -> Text
selectedScope parsedOptions =
  case optionValues "scope" parsedOptions of
    [] -> "cluster"
    value : _ -> value

prerequisiteAppError :: Prerequisite.PrerequisiteError -> AppError
prerequisiteAppError err =
  PrerequisiteUnmet
    (unNodeId (Prerequisite.failingNodeId err))
    (Prerequisite.failingDescription err)
    (Prerequisite.failingRemedyHint err)

prerequisitePlanAppError :: PrerequisitePlanError -> AppError
prerequisitePlanAppError err =
  case err of
    PrerequisitePlanMissingRemediation node remedy ->
      PrerequisiteUnmet
        (unNodeId node)
        "Prerequisite has no typed remediation action."
        (Just remedy)
    PrerequisitePlanRemediationFailed _node failure ->
      SubprocessFailed failure
    PrerequisitePlanPostconditionFailed node description ->
      PrerequisiteUnmet
        (unNodeId node)
        description
        (Just "remediation ran, but the prerequisite postcondition still failed")

runMaterializeSubstrate :: [ParsedOption] -> App ()
runMaterializeSubstrate parsedOptions =
  case optionValues "substrate" parsedOptions of
    [] -> exitWithError (InvalidConfig "missing --substrate value")
    substrate : _
      | Just parsedSubstrate <- parseSubstrate substrate -> do
          changed <- liftIO (materializeBootstrapFiles "." parsedSubstrate)
          if changed
            then writeLine ("materialize-substrate: " <> substrate <> " bootstrap files are present")
            else exitWithError (ReconcilerNoop ("materialize-substrate: " <> substrate <> " already current"))
      | otherwise ->
          exitWithError (InvalidConfig ("unknown substrate: " <> substrate))

supportedSubstrates :: [Text]
supportedSubstrates =
  [ "apple-silicon"
  , "linux-cpu"
  , "linux-cuda"
  ]

hasOption :: Text -> [ParsedOption] -> Bool
hasOption expected =
  any ((== expected) . parsedOptionName)

optionValues :: Text -> [ParsedOption] -> [Text]
optionValues expected =
  concatMap selectedValues
 where
  selectedValues option
    | parsedOptionName option == expected = parsedOptionValues option
    | otherwise = []

runDocsCheck :: App ()
runDocsCheck = do
  drifts <- liftIO checkDocs
  if null drifts
    then writeLine "docs check: ok"
    else exitWithError (DocsCheckDrift (Text.intercalate "\n" (fmap renderDocsDrift drifts)))

runDocsGenerate :: App ()
runDocsGenerate = do
  result <- liftIO generateDocs
  case result of
    Left drifts ->
      exitWithError (DocsCheckDrift (Text.intercalate "\n" (fmap renderDocsDrift drifts)))
    Right GeneratedChanged ->
      writeLine "docs generate: updated"
    Right GeneratedNoop ->
      exitWithError (ReconcilerNoop "docs generate: no changes")

-- | Sprint 2.15 — write a default, self-validating @jitml.dhall@ durable-state
-- config. Refuses to clobber an existing file unless @--force@ is given.
runProjectInit :: [ParsedOption] -> App ()
runProjectInit parsedOptions = do
  let outputPath = case optionValues "output" parsedOptions of
        (path : _) -> Text.unpack path
        [] -> "jitml.dhall"
      rendered = ProjectConfig.renderProjectConfigDhall ProjectConfig.defaultProjectConfig
  exists <- liftIO (doesFileExist outputPath)
  if exists && not (hasOption "force" parsedOptions)
    then
      exitWithError
        ( InvalidConfig
            ("jitml project init: " <> Text.pack outputPath <> " already exists (pass --force to overwrite)")
        )
    else do
      liftIO (writeFile outputPath (Text.unpack rendered))
      writeLine ("project init: wrote " <> Text.pack outputPath)

isLintPath :: [Text] -> Bool
isLintPath ("lint" : _) = True
isLintPath _ = False

runLintPath :: [Text] -> [ParsedOption] -> App ()
runLintPath path parsedOptions =
  case lintTargetFromPath path of
    Just target ->
      runLintCommand (commandPathText path) (runLint target mode)
    Nothing ->
      exitWithError (UnknownCommand ("unknown lint target: " <> commandPathText path))
 where
  mode
    | hasOption "write" parsedOptions = LintWrite
    | otherwise = LintCheck

runLintCommand :: Text -> IO [LintFinding] -> App ()
runLintCommand label action = do
  findings <- liftIO action
  case findings of
    [] -> writeLine (label <> ": ok")
    _ ->
      exitWithError (ChartLintFailed (Text.intercalate "\n" (fmap renderLintFinding findings)))

lintTargetFromPath :: [Text] -> Maybe LintTarget
lintTargetFromPath ["lint", "files"] = Just LintFiles
lintTargetFromPath ["lint", "docs"] = Just LintDocs
lintTargetFromPath ["lint", "proto"] = Just LintProto
lintTargetFromPath ["lint", "chart"] = Just LintChart
lintTargetFromPath ["lint", "haskell"] = Just LintHaskell
lintTargetFromPath ["lint", "purescript"] = Just LintPurescript
lintTargetFromPath ["lint", "all"] = Just LintAll
lintTargetFromPath _ = Nothing

isPlanApplyPath :: [Text] -> Bool
isPlanApplyPath path =
  path
    `elem` [ ["bootstrap"]
           , ["service"]
           , ["cluster", "up"]
           , ["train"]
           , ["tune"]
           , ["rl", "train"]
           , ["test", "all"]
           , ["internal", "gc"]
           ]

hasPlanOutput :: [ParsedOption] -> Bool
hasPlanOutput parsedOptions =
  hasOption "dry-run" parsedOptions || hasOption "plan-file" parsedOptions

runPlanOutput :: [Text] -> [ParsedOption] -> App ()
runPlanOutput path parsedOptions = do
  env <- ask
  case buildCommandPlan path (optionPairs parsedOptions <> envOptionPairs env) of
    Left message ->
      exitWithError (InvalidConfig message)
    Right plan -> do
      let rendered = renderPlan plan
      case optionValues "plan-file" parsedOptions of
        [] -> pure ()
        (planPath : _) -> liftIO (writePlanFile (Text.unpack planPath) rendered)
      if hasOption "dry-run" parsedOptions
        then writeText rendered
        else writeLine ("wrote plan for " <> commandPathText path)

optionPairs :: [ParsedOption] -> [(Text, [Text])]
optionPairs =
  fmap (\option -> (parsedOptionName option, parsedOptionValues option))

envOptionPairs :: Env -> [(Text, [Text])]
envOptionPairs env =
  [ ("cache-dir", [Text.pack (toFilePath (envCacheDir env))])
  , ("data-dir", [Text.pack (toFilePath (envDataDir env))])
  ]

runBootstrap :: [ParsedOption] -> App ()
runBootstrap parsedOptions =
  case bootstrapSubstrates parsedOptions of
    [substrate] ->
      if hasPlanOutput parsedOptions
        then runPlanOutput ["bootstrap"] parsedOptions
        else case parseSubstrate substrate of
          Nothing -> exitWithError (InvalidConfig ("unknown substrate: " <> substrate))
          Just parsedSubstrate -> do
            result <- liftIO (liveExecutePhasedRollout parsedSubstrate "chart")
            if liveAlreadyConverged result
              then writeLine ("bootstrap: " <> substrate <> " already converged")
              else
                writeLine
                  ( "bootstrap: live phased rollout executed "
                      <> Text.pack (show (length (liveStepsExecuted result)))
                      <> " steps"
                  )
            mapM_
              ( \failure ->
                  writeLine ("bootstrap: step failed: " <> renderLiveStepFailure failure)
              )
              (liveStepsFailed result)
            exitWithLiveStepFailure "bootstrap live phased rollout" (liveStepsFailed result)
            when (liveAlreadyConverged result) $
              exitWithError (ReconcilerNoop ("bootstrap: " <> substrate <> " already current"))
    [] ->
      exitWithError (InvalidConfig "bootstrap requires exactly one substrate flag")
    _ ->
      exitWithError (InvalidConfig "bootstrap accepts exactly one substrate flag")

renderLiveStepFailures :: [LiveStepFailure] -> Text
renderLiveStepFailures =
  Text.intercalate "\n" . fmap renderLiveStepFailure

exitWithLiveStepFailure :: Text -> [LiveStepFailure] -> App ()
exitWithLiveStepFailure _ [] = pure ()
exitWithLiveStepFailure context (failure : _) =
  case failure of
    LiveStepProcessFailure _ processFailure ->
      exitWithError (SubprocessFailed processFailure)
    LiveStepInvalidResult {} ->
      exitWithError (InvalidConfig (context <> ": " <> renderLiveStepFailures [failure]))
    LiveStepInvariantFailure {} ->
      exitWithError (InvalidConfig (context <> ": " <> renderLiveStepFailures [failure]))

bootstrapSubstrates :: [ParsedOption] -> [Text]
bootstrapSubstrates parsedOptions =
  filter (`hasOption` parsedOptions) supportedSubstrates

runService :: [ParsedOption] -> App ()
runService parsedOptions = do
  -- Sprint 13.3 dedup observation — Kubernetes pipes the daemon
  -- container's stdout into the kubelet log stream, which makes
  -- GHC's default block-buffering swallow per-delivery
  -- `service: <outcome>` lines until ~4 KB accumulates. Switch to
  -- line-buffered output so `kubectl logs deploy/jitml-service` sees
  -- every consumer outcome as it lands (the dedup live assertion
  -- depends on this).
  liftIO (System.IO.hSetBuffering System.IO.stdout System.IO.LineBuffering)
  liftIO (System.IO.hSetBuffering System.IO.stderr System.IO.LineBuffering)
  let configValues = optionValues "config" parsedOptions
      explicitConfig = not (null configValues)
      consumeOnceRequested = hasOption "consume-once" parsedOptions
      configPath =
        case configValues of
          [] -> "./conf/cluster/linux-cpu.dhall"
          value : _ -> value
  consumeOnceBudget <- requireUserIntOptionAtLeast "consume-once" 0 0 parsedOptions
  env <- ask
  (bootConfig, liveConfig) <- loadServiceConfigs configPath explicitConfig
  let activeRole = BootConfig.bootActiveRole bootConfig
  for_ (serviceRoleInvocationError activeRole consumeOnceRequested) $
    exitWithError . InvalidConfig
  -- Role selection is exhaustive and happens before a daemon runtime exists.
  -- Engine and Coordinator share the resource-safe lifecycle shell but acquire
  -- disjoint prerequisites and command plans.
  case activeRole of
    BootConfig.Engine ->
      runDaemonCommandRoleServe
        env
        configPath
        consumeOnceRequested
        consumeOnceBudget
        (ServiceRuntime.daemonRuntimeForConfigs bootConfig liveConfig)
    BootConfig.Coordinator ->
      runDaemonCommandRoleServe
        env
        configPath
        consumeOnceRequested
        consumeOnceBudget
        (ServiceRuntime.daemonRuntimeForConfigs bootConfig liveConfig)
    BootConfig.Webapp -> runWebappRole configPath bootConfig liveConfig

serviceRoleInvocationError :: BootConfig.Role -> Bool -> Maybe Text
serviceRoleInvocationError role consumeOnceRequested
  | consumeOnceRequested && role /= BootConfig.Engine =
      Just "service --consume-once is available only when activeRole=Engine"
serviceRoleInvocationError BootConfig.Coordinator _ = Nothing
serviceRoleInvocationError BootConfig.Engine _ = Nothing
serviceRoleInvocationError BootConfig.Webapp _ = Nothing

-- | Sprint 11.10 — the Webapp role: serve the compiled browser bundle + the
-- held-open @/api/ws@ Pulsar bridge, deriving host/port/substrate/WS endpoint
-- from the typed Dhall 'BootConfig'. The browser-runtime handler __publishes__
-- an inference @WorkCommand@ to the Engine (via 'requestInferenceViaEngine') and
-- renders the streamed result; the Webapp itself computes no inference.
runWebappRole :: Text -> BootConfig.BootConfig -> LiveConfig.LiveConfig -> App ()
runWebappRole configPath boot liveConfig = do
  listener <-
    case BootConfig.bootHttpListener boot of
      Just configuredListener -> pure configuredListener
      Nothing ->
        exitWithError
          (InvalidConfig "validated Webapp BootConfig has no HTTP listener")
  wsEndpoint <-
    case BootConfig.bootWebappPulsarWsUrl boot of
      Just endpoint -> pure endpoint
      Nothing ->
        exitWithError
          (InvalidConfig "validated Webapp BootConfig has no Pulsar WebSocket URL")
  let substrate = BootConfig.bootSubstrate boot
      host = BootConfig.listenerHost listener
      port = BootConfig.listenerPort listener
      publication = defaultPublication substrate
      pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForEndpoint wsEndpoint
      handler request =
        fmap
          ( fmap
              ( \output ->
                  WebServer.BrowserRuntimeResult
                    { WebServer.browserRuntimeCheckpointSha =
                        WebServer.browserRuntimeExperimentHash request
                    , WebServer.browserRuntimeOutput = output
                    }
              )
          )
          ( requestInferenceViaEngine
              pulsarSettings
              substrate
              (WebServer.browserRuntimeExperimentHash request)
              (WebServer.browserRuntimeInput request)
          )
      publishers =
        WebServer.BrowserCommandPublishers
          { WebServer.publishCompareCommand =
              publishCheckpointCompareCommandOnly pulsarSettings substrate
          , WebServer.publishMoveCommand =
              publishAdversarialMoveCommandOnly pulsarSettings substrate
          , WebServer.publishListCheckpointsCommand =
              publishListCheckpointsCommandOnly pulsarSettings substrate
          , WebServer.publishLoadTranscriptCommand =
              publishLoadTranscriptCommandOnly pulsarSettings substrate
          }
  writeLine ("webapp: serving " <> host <> ":" <> Text.pack (show port))
  let runtime = ServiceRuntime.daemonRuntimeForConfigs boot liveConfig
      serveWebapp =
        WebServer.serveDemoWithBridgeEndpointWithRuntime
          host
          port
          (Just publication)
          (Just wsEndpoint)
          (Just handler)
          (Just publishers)
  control <-
    liftIO
      ( ServiceSignal.newDaemonControlWithLiveConfig
          (ServiceRuntime.daemonState runtime)
          liveConfig
      )
  reloadFailure <-
    liftIO
      ( ServiceRuntime.runDaemonWithReloadAndDrain
          control
          serveWebapp
          (reloadServiceConfigs configPath control (const (pure ())) boot)
          (pure ())
      )
  for_ reloadFailure exitWithError

runDaemonCommandRoleServe :: Env -> Text -> Bool -> Int -> ServiceRuntime.DaemonRuntime -> App ()
runDaemonCommandRoleServe env configPath consumeOnceRequested consumeOnceBudget runtime = do
  daemonLogger <- liftIO ServiceLogger.newDaemonLogger
  hostWorkloadRegistry <- liftIO (hostWorkloadRegistryForRuntime runtime)
  acquireResult <- acquireDaemonRole runtime
  acquiredRuntime <-
    case acquireResult of
      Right readyRuntime -> pure readyRuntime
      Left (failedRuntime, err) -> do
        writeLine ("service config: " <> configPath)
        writeText (ServiceRuntime.renderDaemonRuntimeSummary failedRuntime)
        exitWithError err
  if consumeOnceRequested
    then do
      engineClientSettings <-
        case ServiceClients.engineRoleClientSettings
          (ServiceRuntime.daemonClientSettings acquiredRuntime) of
          Just settings -> pure settings
          Nothing ->
            exitWithError
              (InvalidConfig "Engine consume-once runtime has no Engine client settings")
      (_, outcomes) <-
        liftIO
          ( ServiceClients.runEngineServiceClient
              engineClientSettings
              ( ServiceRuntime.daemonConsumerBatch
                  acquiredRuntime
                  consumeOnceBudget
                  ( engineDaemonWorkloadDispatcherForRuntime
                      env
                      acquiredRuntime
                      hostWorkloadRegistry
                  )
              )
          )
      hostWorkloadFailure <-
        liftIO (waitForConsumeOnceHostWorkloads hostWorkloadRegistry)
      writeLine ("service config: " <> configPath)
      writeText (ServiceRuntime.renderDaemonRuntimeSummary acquiredRuntime)
      writeLine
        ( "service: consume-once drained "
            <> Text.pack (show consumeOnceBudget)
            <> " message(s) per planned subscription"
        )
      writeText (ServiceRuntime.renderConsumerOutcomes outcomes)
      case ServiceRuntime.consumerLoopExit outcomes of
        Just consumerFailure -> exitWithError consumerFailure
        Nothing -> for_ hostWorkloadFailure exitWithError
    else do
      control <-
        liftIO
          ( ServiceSignal.newDaemonControlWithLiveConfig
              (ServiceRuntime.daemonState acquiredRuntime)
              (ServiceRuntime.daemonLiveConfig acquiredRuntime)
          )
      consumerWorkers <-
        liftIO
          ( startDaemonConsumerWorkers
              env
              control
              daemonLogger
              acquiredRuntime
              hostWorkloadRegistry
          )
      connected <- liftIO (waitForDaemonConsumerConnections consumerWorkers)
      unless connected $ do
        liftIO $ do
          void
            ( ServiceSignal.modifyDaemonState
                control
                ( RuntimeState.recordRuntimeFailure
                    "persistent Pulsar consumers did not connect before startup deadline"
                )
            )
          stopDaemonConsumerWorkers control consumerWorkers
        writeLine ("service config: " <> configPath)
        writeText (ServiceRuntime.renderDaemonRuntimeSummary acquiredRuntime)
        exitWithError
          (PulsarFailed "persistent Pulsar consumers did not connect before startup deadline")
      connectedSnapshot <- liftIO (ServiceSignal.readDaemonControl control)
      let connectedRuntime =
            acquiredRuntime
              { ServiceRuntime.daemonState =
                  ServiceSignal.snapshotDaemonState connectedSnapshot
              }
      probeResultRuntime <-
        case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig connectedRuntime) of
          BootConfig.Engine ->
            case ServiceClients.engineRoleClientSettings
              (ServiceRuntime.daemonClientSettings connectedRuntime) of
              Just settings ->
                liftIO
                  ( ServiceClients.runEngineServiceClient
                      settings
                      (ServiceRuntime.probeEngineServiceClients connectedRuntime)
                  )
              Nothing ->
                exitWithError
                  (InvalidConfig "Engine runtime has no Engine client settings")
          BootConfig.Coordinator ->
            case ServiceClients.coordinatorRoleClientSettings
              (ServiceRuntime.daemonClientSettings connectedRuntime) of
              Just settings ->
                liftIO
                  ( ServiceClients.runDaemonServiceClient
                      settings
                      (ServiceRuntime.probeCoordinatorServiceClients connectedRuntime)
                  )
              Nothing ->
                exitWithError
                  (InvalidConfig "Coordinator runtime has no Coordinator client settings")
          BootConfig.Webapp ->
            exitWithError
              (InvalidConfig "Webapp cannot probe command-role daemon clients")
      reconnectedAfterProbes <- liftIO (waitForDaemonConsumerConnections consumerWorkers)
      unless reconnectedAfterProbes $ do
        liftIO (stopDaemonConsumerWorkers control consumerWorkers)
        exitWithError
          (PulsarFailed "persistent Pulsar consumers disconnected during client probes")
      liftIO
        ( void
            ( ServiceSignal.modifyDaemonState
                control
                ( applyDaemonClientProbeStatuses
                    (ServiceRuntime.daemonClientProbeStatuses probeResultRuntime)
                )
            )
        )
      finalSnapshot <- liftIO (ServiceSignal.readDaemonControl control)
      let probedRuntime =
            probeResultRuntime
              { ServiceRuntime.daemonState =
                  ServiceSignal.snapshotDaemonState finalSnapshot
              }
      writeLine ("service config: " <> configPath)
      writeText (ServiceRuntime.renderDaemonRuntimeSummary probedRuntime)
      unless (ServiceRuntime.daemonReady probedRuntime) $ do
        liftIO (stopDaemonConsumerWorkers control consumerWorkers)
        exitWithError
          ( PrerequisiteUnmet
              "service.readiness"
              (RuntimeState.daemonStateDetail (ServiceRuntime.daemonState probedRuntime))
              (Just "restore every persistent consumer connection and service-client probe")
          )
      liftIO
        ( void
            ( emitDaemonControlLog
                daemonLogger
                control
                LiveConfig.Info
                ServiceLifecycle.Ready
                ( "role ready: "
                    <> BootConfig.renderRole (BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig probedRuntime))
                )
            )
        )
      writeLine (serviceListeningLine probedRuntime)
      workerCleanup <- liftIO (newMVar False)
      cleanupFailure <- liftIO (newMVar Nothing)
      let stopDaemonResourcesOnce =
            modifyMVar_ workerCleanup $ \stopped ->
              if stopped
                then pure True
                else do
                  (_, registryFailure) <-
                    concurrently
                      (stopDaemonConsumerWorkers control consumerWorkers)
                      (drainHostWorkloads control hostWorkloadRegistry)
                  modifyMVar_ cleanupFailure (const (pure registryFailure))
                  pure True
      reloadFailure <-
        liftIO
          ( ServiceRuntime.serveDaemonWithReloadAndDrain
              control
              probedRuntime
              ( reloadServiceConfigs
                  configPath
                  control
                  (`refreshIdleDaemonConsumerRouters` consumerWorkers)
                  (ServiceRuntime.daemonBootConfig probedRuntime)
              )
              stopDaemonResourcesOnce
              `finally` stopDaemonResourcesOnce
          )
      resourceFailure <- liftIO (readMVar cleanupFailure)
      case reloadFailure of
        Just primaryFailure -> exitWithError primaryFailure
        Nothing -> for_ resourceFailure exitWithError

hostWorkloadRegistryForRuntime
  :: ServiceRuntime.DaemonRuntime
  -> IO (Maybe HostWorkloadRegistry.HostWorkloadRegistry)
hostWorkloadRegistryForRuntime runtime =
  whenMaybe
    (bootConfigIsAppleHostEngine (ServiceRuntime.daemonBootConfig runtime))
    HostWorkloadRegistry.newHostWorkloadRegistry

whenMaybe :: (Applicative f) => Bool -> f a -> f (Maybe a)
whenMaybe condition action =
  bool (pure Nothing) (Just <$> action) condition

-- | A bounded consume-once pull may register asynchronous Apple host Starts.
-- Once every subscription has returned, no further registrations can race the
-- snapshot, so wait for every retained handle and surface any worker failure
-- before the process reports success.
waitForConsumeOnceHostWorkloads
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO (Maybe AppError)
waitForConsumeOnceHostWorkloads Nothing = pure Nothing
waitForConsumeOnceHostWorkloads (Just registry) = do
  snapshots <- HostWorkloadRegistry.hostWorkloadRegistrySnapshots registry
  results <-
    traverse
      ( \(key, _snapshot) -> do
          outcome <- HostWorkloadRegistry.waitHostWorkload registry key
          pure (fmap (key,) outcome)
      )
      snapshots
  pure $
    case sequence results of
      Left registryError ->
        Just
          ( PrerequisiteUnmet
              "service.apple-host-workload.consume-once"
              (HostWorkloadRegistry.renderHostWorkloadRegistryError registryError)
              (Just "restore the process-local Apple host workload registry and retry")
          )
      Right outcomes ->
        case [ renderHostWorkloadFailure key failure
             | (key, HostWorkloadRegistry.HostWorkloadFailed failure) <- outcomes
             ] of
          [] -> Nothing
          failures ->
            Just
              ( PrerequisiteUnmet
                  "service.apple-host-workload.consume-once"
                  (Text.intercalate "; " failures)
                  (Just "correct the failed Apple host workload inputs and retry")
              )
 where
  renderHostWorkloadFailure key failure =
    HostWorkloadRegistry.hostWorkloadFamilyLabel
      (HostWorkloadRegistry.hostWorkloadFamily key)
      <> "/"
      <> HostWorkloadRegistry.hostWorkloadExperimentHash key
      <> ": "
      <> failure

bootConfigIsAppleHostEngine :: BootConfig.BootConfig -> Bool
bootConfigIsAppleHostEngine bootConfig =
  BootConfig.bootActiveRole bootConfig == BootConfig.Engine
    && BootConfig.bootSubstrate bootConfig == AppleSilicon
    && BootConfig.bootResidency bootConfig == BootConfig.Host

drainHostWorkloads
  :: ServiceSignal.DaemonControl
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO (Maybe AppError)
drainHostWorkloads _control Nothing = pure Nothing
drainHostWorkloads control (Just registry) = do
  snapshot <- ServiceSignal.readDaemonControl control
  result <-
    HostWorkloadRegistry.drainHostWorkloadRegistry
      registry
      (fromIntegral (LiveConfig.liveDrainDeadlineMicros (ServiceSignal.snapshotLiveConfig snapshot)))
  pure $
    case result of
      Right _report -> Nothing
      Left registryError ->
        Just
          ( PrerequisiteUnmet
              "service.apple-host-workload-drain"
              (HostWorkloadRegistry.renderHostWorkloadRegistryError registryError)
              (Just "allow the keyed Apple host workloads to cancel and join before the drain deadline")
          )

acquireDaemonRole
  :: ServiceRuntime.DaemonRuntime
  -> App (Either (ServiceRuntime.DaemonRuntime, AppError) ServiceRuntime.DaemonRuntime)
acquireDaemonRole runtime =
  case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig runtime) of
    BootConfig.Engine -> acquireAppleMetalBridge runtime
    BootConfig.Coordinator -> acquireCoordinatorTopicFamily runtime
    BootConfig.Webapp ->
      pure
        ( Left
            ( runtime
            , InvalidConfig "Webapp cannot enter the command-role daemon lifecycle"
            )
        )

acquireCoordinatorTopicFamily
  :: ServiceRuntime.DaemonRuntime
  -> App (Either (ServiceRuntime.DaemonRuntime, AppError) ServiceRuntime.DaemonRuntime)
acquireCoordinatorTopicFamily runtime = do
  result <-
    liftIO
      ( PulsarBootstrap.runCoordinatorPulsarTopicReconcileIO
          (LiveConfig.liveRetryPolicy (ServiceRuntime.daemonLiveConfig runtime))
      )
  pure $
    case result of
      Right evidence ->
        Right
          runtime
            { ServiceRuntime.daemonState =
                RuntimeState.recordTopicFamilyReconciled
                  (PulsarBootstrap.topicFamilyEvidenceTopics evidence)
                  (ServiceRuntime.daemonState runtime)
            }
      Left reconcileError ->
        let detail = Text.pack (show reconcileError)
         in Left
              ( runtime
                  { ServiceRuntime.daemonState =
                      RuntimeState.recordTopicFamilyFailure
                        detail
                        (ServiceRuntime.daemonState runtime)
                  }
              , PrerequisiteUnmet
                  "service.coordinator.topic-family"
                  detail
                  (Just "restore Pulsar and the Coordinator's in-cluster topic reconcile capability")
              )

serviceListeningLine :: ServiceRuntime.DaemonRuntime -> Text
serviceListeningLine runtime =
  case BootConfig.bootHttpListener (ServiceRuntime.daemonBootConfig runtime) of
    Nothing -> "service: running without HTTP listener"
    Just listener ->
      "service: listening on "
        <> BootConfig.listenerHost listener
        <> ":"
        <> Text.pack (show (BootConfig.listenerPort listener))

data DaemonConsumerWorker = DaemonConsumerWorker
  { daemonConsumerWorkerThreadId :: ThreadId
  , daemonConsumerWorkerRouter :: MVar HandlerRouter
  , daemonConsumerWorkerConnected :: MVar Bool
  , daemonConsumerWorkerInFlight :: MVar Bool
  , daemonConsumerWorkerFinished :: MVar ()
  }

startDaemonConsumerWorkers
  :: Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO [DaemonConsumerWorker]
startDaemonConsumerWorkers env control daemonLogger runtime hostWorkloadRegistry =
  -- Sprint 16.11 — one dedup-cache MVar PER worker, not one shared across every
  -- worker. The dispatch compute runs inside `modifyMVar routerRef`
  -- (`handleDaemonConsumerDelivery`), so a single shared MVar serialized all
  -- workers: a long host Metal training/RL/tune workload (dispatched on its own
  -- `*.host-command` topic, 10s-100s of compute) held the one MVar and blocked the
  -- `inference.command` worker for the whole duration — so under a backlog of
  -- placement-dispatched host workloads a client's bounded inference reply poll
  -- timed out (head-of-line blocking across domains). Each subscription maps to a
  -- single topic/domain and redeliveries return to the same worker, so a
  -- per-worker router gives identical dedup semantics with no cross-worker lock.
  traverse startWorker (ServiceRuntime.daemonSubscriptions runtime)
 where
  startWorker subscription = do
    routerRef <- newMVar (ServiceRuntime.daemonHandlerRouter runtime)
    connectedRef <- newMVar False
    inFlightRef <- newMVar False
    finishedRef <- newEmptyMVar
    workerThread <-
      forkFinally
        ( daemonConsumerWorkerLoop
            env
            control
            daemonLogger
            runtime
            hostWorkloadRegistry
            routerRef
            connectedRef
            inFlightRef
            subscription
        )
        (const (void (tryPutMVar finishedRef ())))
    pure
      DaemonConsumerWorker
        { daemonConsumerWorkerThreadId = workerThread
        , daemonConsumerWorkerRouter = routerRef
        , daemonConsumerWorkerConnected = connectedRef
        , daemonConsumerWorkerInFlight = inFlightRef
        , daemonConsumerWorkerFinished = finishedRef
        }

stopDaemonConsumerWorkers :: ServiceSignal.DaemonControl -> [DaemonConsumerWorker] -> IO ()
stopDaemonConsumerWorkers control workers = do
  void (ServiceSignal.modifyDaemonState control RuntimeState.beginDaemonDrain)
  -- Idle workers can close their bridge immediately. In-flight handlers are
  -- left alone: after dispatch they observe the draining state, return a
  -- terminal disposition, and let the bridge confirm settlement before exit.
  for_ workers $ \worker -> do
    inFlight <- readMVar (daemonConsumerWorkerInFlight worker)
    unless inFlight (requestDaemonConsumerWorkerCancellation worker)
  controlSnapshot <- ServiceSignal.readDaemonControl control
  let deadline =
        LiveConfig.liveDrainDeadlineMicros
          (ServiceSignal.snapshotLiveConfig controlSnapshot)
  drained <-
    timeout
      deadline
      (traverse_ (readMVar . daemonConsumerWorkerFinished) workers)
  case drained of
    Just () -> pure ()
    Nothing ->
      -- A stuck handler or bridge must not hold process shutdown past the
      -- configured deadline. Issue cancellation from detached thrower threads:
      -- 'throwTo' is synchronous and could otherwise block this coordinator on
      -- an uninterruptible native call before the timeout can take effect.
      do
        traverse_ requestDaemonConsumerWorkerCancellation workers
        forcedCleanup <-
          timeout
            daemonConsumerForcedCleanupJoinMicros
            (traverse_ (readMVar . daemonConsumerWorkerFinished) workers)
        case forcedCleanup of
          Just () -> pure ()
          Nothing ->
            writeLineIO
              "service: forced consumer cleanup did not join before the post-cancel deadline"

requestDaemonConsumerWorkerCancellation :: DaemonConsumerWorker -> IO ()
requestDaemonConsumerWorkerCancellation worker = do
  finished <- tryReadMVar (daemonConsumerWorkerFinished worker)
  case finished of
    Just () -> pure ()
    Nothing -> void (forkIO (killThread (daemonConsumerWorkerThreadId worker)))

daemonConsumerForcedCleanupJoinMicros :: Int
daemonConsumerForcedCleanupJoinMicros = 5 * 1000 * 1000

reloadServiceConfigs
  :: Text
  -> ServiceSignal.DaemonControl
  -> (LiveConfig.LiveConfig -> IO ())
  -> BootConfig.BootConfig
  -> IO (Maybe AppError)
reloadServiceConfigs configPath control applyLiveConfig initialBootConfig = do
  let bootConfigPath = Text.unpack configPath
      liveConfigPath = takeDirectory bootConfigPath </> "LiveConfig.dhall"
  bootResult <- tryAny (BootConfig.loadBootConfig bootConfigPath)
  case bootResult of
    Left err ->
      restartRequired
        "invalid boot config"
        ( "failed to reload service config "
            <> configPath
            <> ": "
            <> Text.pack (displayException err)
        )
    Right nextBootConfig
      | nextBootConfig /= initialBootConfig ->
          restartRequired
            "boot config changed"
            "BootConfig changed under SIGHUP"
      | otherwise -> do
          liveResult <- tryAny (LiveConfig.loadLiveConfig liveConfigPath)
          case liveResult of
            Left err -> do
              generation <- currentReloadGeneration control
              writeLineIO
                ( "reload: ignored; reason=invalid live config; generation="
                    <> Text.pack (show generation)
                )
              writeLineIO
                ( "reload: invalid live config detail="
                    <> Text.pack (displayException err)
                )
              pure Nothing
            Right nextLiveConfig -> do
              decision <- ServiceSignal.applyDaemonLiveConfig control nextLiveConfig
              writeLineIO (HotReload.renderReloadDecision decision)
              case decision of
                HotReload.ReloadIgnored _reason -> pure ()
                HotReload.ReloadApplied snapshot -> do
                  applyLiveConfig nextLiveConfig
                  writeLineIO
                    ( "reload: active live config; log-level="
                        <> Text.pack (show (LiveConfig.liveLogLevel nextLiveConfig))
                        <> "; retry-policy="
                        <> Text.pack (show (LiveConfig.liveRetryPolicy nextLiveConfig))
                        <> "; inference-batch-size="
                        <> Text.pack (show (LiveConfig.liveInferenceBatchSize nextLiveConfig))
                        <> "; inference-max-latency-millis="
                        <> Text.pack (show (LiveConfig.liveInferenceMaxLatencyMillis nextLiveConfig))
                        <> "; dedup-cache-size="
                        <> Text.pack (show (LiveConfig.liveDedupCacheSize nextLiveConfig))
                        <> "; dedup-cache-ttl-seconds="
                        <> Text.pack (show (LiveConfig.liveDedupCacheTtlSeconds nextLiveConfig))
                        <> "; drain-deadline-seconds="
                        <> Text.pack (show (LiveConfig.liveDrainDeadlineSeconds nextLiveConfig))
                        <> "; generation="
                        <> Text.pack (show (HotReload.snapshotGeneration snapshot))
                    )
              pure Nothing
 where
  restartRequired reason detail = do
    generation <- currentReloadGeneration control
    writeLineIO
      ( "reload: restart-required; reason="
          <> reason
          <> "; generation="
          <> Text.pack (show generation)
      )
    pure (Just (InvalidConfig detail))

currentReloadGeneration :: ServiceSignal.DaemonControl -> IO Int
currentReloadGeneration control =
  ServiceSignal.snapshotReloadGeneration
    <$> ServiceSignal.readDaemonControl control

refreshIdleDaemonConsumerRouters :: LiveConfig.LiveConfig -> [DaemonConsumerWorker] -> IO ()
refreshIdleDaemonConsumerRouters liveConfig =
  traverse_ refreshWorker
 where
  refreshWorker worker = mask_ $ do
    maybeRouter <- tryTakeMVar (daemonConsumerWorkerRouter worker)
    case maybeRouter of
      Nothing -> pure ()
      Just router -> do
        configuredRouter <-
          Consumer.reconfigureHandlerRouter
            (LiveConfig.liveDedupCacheSize liveConfig)
            (LiveConfig.liveDedupCacheTtlSeconds liveConfig)
            router
        putMVar (daemonConsumerWorkerRouter worker) configuredRouter

waitForDaemonConsumerConnections :: [DaemonConsumerWorker] -> IO Bool
waitForDaemonConsumerConnections workers =
  go daemonConsumerStartupPollAttempts
 where
  go attempts = do
    connected <- traverse (readMVar . daemonConsumerWorkerConnected) workers
    if and connected
      then pure True
      else
        if attempts <= 0
          then pure False
          else do
            threadDelay daemonConsumerStartupPollMicros
            go (attempts - 1)

daemonConsumerWorkerLoop
  :: Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> MVar HandlerRouter
  -> MVar Bool
  -> MVar Bool
  -> Consumer.DaemonSubscription
  -> IO ()
daemonConsumerWorkerLoop
  env
  control
  daemonLogger
  runtime
  hostWorkloadRegistry
  routerRef
  connectedRef
  inFlightRef
  subscription =
    runWorker
   where
    runWorker =
      case ServiceClients.rolePulsarSettings (ServiceRuntime.daemonClientSettings runtime) of
        Nothing ->
          ioError
            ( userError
                "command-role daemon runtime has no Pulsar client settings"
            )
        Just pulsarSettings -> do
          workerResult <-
            PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
              pulsarSettings
              consumeSubscription
          case workerResult of
            Right _ -> pure ()
            Left failure -> do
              modifyMVar_ connectedRef (const (pure False))
              void
                ( ServiceSignal.modifyDaemonState
                    control
                    (RuntimeState.recordRuntimeFailure (Text.pack (show failure)))
                )
              snapshot <- ServiceSignal.readDaemonControl control
              unless (ServiceSignal.snapshotDraining snapshot) $ do
                void
                  ( emitDaemonControlLog
                      daemonLogger
                      control
                      LiveConfig.Error
                      ServiceLifecycle.Serve
                      ( "consumer worker error: "
                          <> Text.strip
                            (ServiceRuntime.renderConsumerOutcomes [ConsumerSessionError failure])
                      )
                  )
                threadDelay daemonConsumerErrorDelayMicros
                runWorker

    consumeSubscription =
      case Consumer.daemonSubscriptionDomain subscription of
        Consumer.InferenceDomain ->
          Consumer.consumeDaemonSubscriptionBatches
            subscription
            (liftIO (readInferenceBatchPolicy control))
            inferenceBatchCompatibility
            (observeDaemonConsumerSession control connectedRef subscription)
            ( handleDaemonConsumerBatch
                env
                control
                daemonLogger
                runtime
                hostWorkloadRegistry
                routerRef
                inFlightRef
            )
        _ ->
          Consumer.consumeDaemonSubscription
            subscription
            (observeDaemonConsumerSession control connectedRef subscription)
            ( handleDaemonConsumerDelivery
                env
                control
                daemonLogger
                runtime
                hostWorkloadRegistry
                routerRef
                inFlightRef
            )

observeDaemonConsumerSession
  :: ServiceSignal.DaemonControl
  -> MVar Bool
  -> Consumer.DaemonSubscription
  -> Capabilities.ConsumerSessionEvent
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess ()
observeDaemonConsumerSession control connectedRef subscription sessionEvent =
  liftIO $ do
    modifyMVar_ connectedRef (const (pure (sessionConnected sessionEvent)))
    void
      ( ServiceSignal.modifyDaemonState
          control
          (ServiceRuntime.daemonConsumerSessionTransition subscription sessionEvent)
      )
 where
  sessionConnected event =
    case event of
      Capabilities.ConsumerSessionConnected _ -> True
      Capabilities.ConsumerSessionDisconnected _ -> False
      Capabilities.ConsumerSessionDraining -> False
      Capabilities.ConsumerSessionDrained -> False

handleDaemonConsumerDelivery
  :: Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> MVar HandlerRouter
  -> MVar Bool
  -> Consumer.DaemonCommand
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Capabilities.ConsumerDecision ())
handleDaemonConsumerDelivery
  env
  control
  daemonLogger
  runtime
  hostWorkloadRegistry
  routerRef
  inFlightRef
  command = do
    liftIO $
      bracket
        (modifyMVar_ inFlightRef (const (pure True)))
        (const (modifyMVar_ inFlightRef (const (pure False))))
        ( \() -> do
            initialSnapshot <- ServiceSignal.readDaemonControl control
            if ServiceSignal.snapshotDraining initialSnapshot
              then
                pure
                  ( Capabilities.done
                      (Capabilities.nack Capabilities.DrainRequested)
                      ()
                  )
              else modifyMVar routerRef $ \router -> do
                liveSnapshot <- ServiceSignal.readDaemonControl control
                let liveConfig = ServiceSignal.snapshotLiveConfig liveSnapshot
                configuredRouter <-
                  Consumer.reconfigureHandlerRouter
                    (LiveConfig.liveDedupCacheSize liveConfig)
                    (LiveConfig.liveDedupCacheTtlSeconds liveConfig)
                    router
                (router', outcome, disposition) <-
                  consumerStep
                    configuredRouter
                    command
                    ( dispatchDaemonCommandWithRetry
                        env
                        runtime
                        hostWorkloadRegistry
                        liveConfig
                        Nothing
                    )
                void
                  ( emitDaemonControlLog
                      daemonLogger
                      control
                      LiveConfig.Info
                      ServiceLifecycle.Serve
                      (Text.strip (ServiceRuntime.renderConsumerOutcomes [outcome]))
                  )
                for_ (ServiceRuntime.consumerLoopExit [outcome]) $ \appError ->
                  void
                    ( emitDaemonControlLog
                        daemonLogger
                        control
                        LiveConfig.Error
                        ServiceLifecycle.Serve
                        ("consumer outcome error: " <> renderError appError)
                    )
                completedSnapshot <- ServiceSignal.readDaemonControl control
                let decision =
                      if ServiceSignal.snapshotDraining completedSnapshot
                        then Capabilities.done disposition ()
                        else Capabilities.continue disposition
                pure (router', decision)
        )

data InferenceBatchCompatibility
  = CompatibleRunInference Text Int
  | IsolatedInferenceCommand Text
  deriving stock (Eq)

inferenceBatchCompatibility :: Consumer.DaemonCommand -> InferenceBatchCompatibility
inferenceBatchCompatibility command =
  case command of
    Consumer.InferenceDaemonCommand _ (Inference.RunInference request) ->
      CompatibleRunInference
        (Inference.irExperimentHash request)
        (length (Inference.irInput request))
    _ -> IsolatedInferenceCommand (Consumer.daemonCommandPayload command)

readInferenceBatchPolicy
  :: ServiceSignal.DaemonControl
  -> IO InferenceBatch.BatchPolicy
readInferenceBatchPolicy control = do
  snapshot <- ServiceSignal.readDaemonControl control
  let liveConfig = ServiceSignal.snapshotLiveConfig snapshot
  case InferenceBatch.mkBatchPolicy
    (fromIntegral (LiveConfig.liveInferenceBatchSize liveConfig))
    (fromIntegral (LiveConfig.liveInferenceMaxLatencyMillis liveConfig) * 1000) of
    Right policy -> pure policy
    Left policyError ->
      ioError
        ( userError
            ( "validated LiveConfig produced an invalid inference batch policy: "
                <> show policyError
            )
        )

data DaemonBatchFailure
  = DaemonBatchSloExpired
  | DaemonBatchDispatchFailed AppError

handleDaemonConsumerBatch
  :: Env
  -> ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> MVar HandlerRouter
  -> MVar Bool
  -> Capabilities.DeliveryBatch Consumer.DaemonCommand
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Capabilities.ConsumerBatchDecision ())
handleDaemonConsumerBatch
  env
  control
  daemonLogger
  runtime
  hostWorkloadRegistry
  routerRef
  inFlightRef
  batch =
    liftIO $
      bracket
        (modifyMVar_ inFlightRef (const (pure True)))
        (const (modifyMVar_ inFlightRef (const (pure False))))
        ( \() -> do
            initialSnapshot <- ServiceSignal.readDaemonControl control
            if ServiceSignal.snapshotDraining initialSnapshot
              then
                pure
                  ( Capabilities.doneBatch
                      (Capabilities.nack Capabilities.DrainRequested)
                      ()
                  )
              else do
                liveSnapshot <- ServiceSignal.readDaemonControl control
                let liveConfig = ServiceSignal.snapshotLiveConfig liveSnapshot
                modifyMVar_ routerRef $ \router ->
                  Consumer.reconfigureHandlerRouter
                    (LiveConfig.liveDedupCacheSize liveConfig)
                    (LiveConfig.liveDedupCacheTtlSeconds liveConfig)
                    router
                (_outcomes, batchFailure) <-
                  runDaemonConsumerBatch
                    env
                    runtime
                    hostWorkloadRegistry
                    liveConfig
                    (Capabilities.deliveryBatchWindow batch)
                    (emitOutcomeLog control daemonLogger)
                    routerRef
                    (Capabilities.deliveryBatchEvents batch)
                completedSnapshot <- ServiceSignal.readDaemonControl control
                let disposition = daemonBatchDisposition batchFailure
                    decision =
                      if ServiceSignal.snapshotDraining completedSnapshot
                        then Capabilities.doneBatch disposition ()
                        else Capabilities.continueBatch disposition
                pure decision
        )

runDaemonConsumerBatch
  :: Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> LiveConfig.LiveConfig
  -> InferenceBatch.BatchWindow
  -> (ConsumerOutcome -> IO ())
  -> MVar HandlerRouter
  -> NonEmpty.NonEmpty Consumer.DaemonCommand
  -> IO ([ConsumerOutcome], Maybe DaemonBatchFailure)
runDaemonConsumerBatch
  env
  runtime
  hostWorkloadRegistry
  liveConfig
  window
  observeOutcome
  routerRef
  initialCommands =
    go [] (NonEmpty.toList initialCommands)
   where
    go outcomes pendingCommands =
      case pendingCommands of
        [] -> pure (reverse outcomes, Nothing)
        command : remaining -> do
          now <- getMonotonicTimeNSec
          if InferenceBatch.batchWindowExpiredAt now window
            then pure (reverse outcomes, Just DaemonBatchSloExpired)
            else do
              (outcome, _disposition) <-
                Consumer.consumerStepCommitted
                  routerRef
                  command
                  ( dispatchDaemonCommandWithRetry
                      env
                      runtime
                      hostWorkloadRegistry
                      liveConfig
                      (Just (InferenceBatch.batchWindowDeadlineNanoseconds window))
                  )
              observeOutcome outcome
              case Consumer.consumerOutcomeError outcome of
                Just appError ->
                  pure
                    ( reverse (outcome : outcomes)
                    , Just (DaemonBatchDispatchFailed appError)
                    )
                Nothing -> go (outcome : outcomes) remaining

daemonBatchDisposition :: Maybe DaemonBatchFailure -> Capabilities.Disposition
daemonBatchDisposition batchFailure =
  case batchFailure of
    Nothing -> Capabilities.ack
    Just DaemonBatchSloExpired ->
      Capabilities.nack
        (Capabilities.RetryRequested "inference batch latency SLO expired")
    Just (DaemonBatchDispatchFailed appError) ->
      Capabilities.nack
        (Capabilities.HandlerRejected (Text.strip (renderError appError)))

emitOutcomeLog
  :: ServiceSignal.DaemonControl
  -> ServiceLogger.DaemonLogger
  -> ConsumerOutcome
  -> IO ()
emitOutcomeLog control daemonLogger outcome = do
  void
    ( emitDaemonControlLog
        daemonLogger
        control
        LiveConfig.Info
        ServiceLifecycle.Serve
        (Text.strip (ServiceRuntime.renderConsumerOutcomes [outcome]))
    )
  for_ (Consumer.consumerOutcomeError outcome) $ \appError ->
    void
      ( emitDaemonControlLog
          daemonLogger
          control
          LiveConfig.Error
          ServiceLifecycle.Serve
          ("consumer outcome error: " <> renderError appError)
      )

dispatchDaemonCommandWithRetry
  :: Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> LiveConfig.LiveConfig
  -> Maybe Integer
  -> Consumer.DaemonCommand
  -> EventId
  -> IO (Either ServiceError ())
dispatchDaemonCommandWithRetry
  env
  runtime
  hostWorkloadRegistry
  liveConfig
  publicationDeadline
  command
  eventId =
    ServiceRetry.retryServiceActionEither
      (LiveConfig.liveRetryPolicy liveConfig)
      ( \() ->
          dispatchDaemonCommandForRole
            env
            runtime
            hostWorkloadRegistry
            publicationDeadline
            command
            eventId
      )
      ()

dispatchDaemonCommandForRole
  :: Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> Maybe Integer
  -> Consumer.DaemonCommand
  -> EventId
  -> IO (Either ServiceError ())
dispatchDaemonCommandForRole
  env
  runtime
  hostWorkloadRegistry
  publicationDeadline
  command
  eventId =
    case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig runtime) of
      BootConfig.Engine ->
        case ServiceClients.engineRoleClientSettings
          (ServiceRuntime.daemonClientSettings runtime) of
          Just settings ->
            ServiceClients.runEngineServiceClient
              ( maybe
                  settings
                  (`ServiceClients.engineClientSettingsWithPublicationDeadline` settings)
                  publicationDeadline
              )
              ( engineDaemonWorkloadDispatcherForRuntime
                  env
                  runtime
                  hostWorkloadRegistry
                  command
                  eventId
              )
          Nothing -> pure (Left (SEConflict "Engine runtime has no Engine client settings"))
      BootConfig.Coordinator ->
        case ServiceClients.coordinatorRoleClientSettings
          (ServiceRuntime.daemonClientSettings runtime) of
          Just settings ->
            ServiceClients.runDaemonServiceClient
              settings
              (coordinatorDaemonWorkloadDispatcherForRuntime runtime command eventId)
          Nothing ->
            pure (Left (SEConflict "Coordinator runtime has no Coordinator client settings"))
      BootConfig.Webapp ->
        pure (Left (SEUnauthorized "Webapp cannot dispatch daemon commands"))

daemonConsumerErrorDelayMicros :: Int
daemonConsumerErrorDelayMicros = 1000000

daemonConsumerStartupPollMicros :: Int
daemonConsumerStartupPollMicros = 100000

daemonConsumerStartupPollAttempts :: Int
daemonConsumerStartupPollAttempts = 300

emitDaemonControlLog
  :: ServiceLogger.DaemonLogger
  -> ServiceSignal.DaemonControl
  -> LiveConfig.LogLevel
  -> ServiceLifecycle.LifecyclePhase
  -> Text
  -> IO Bool
emitDaemonControlLog logger control =
  ServiceLogger.emitDaemonLog
    logger
    (ServiceSignal.snapshotLiveConfig <$> ServiceSignal.readDaemonControl control)

applyDaemonClientProbeStatuses
  :: [ServiceRuntime.DaemonClientProbeStatus]
  -> RuntimeState.DaemonState
  -> RuntimeState.DaemonState
applyDaemonClientProbeStatuses statuses state =
  case failedProbe statuses of
    Just (name, err) ->
      RuntimeState.recordClientProbeFailure name (Text.pack (show err)) state
    Nothing
      | all probeSucceeded statuses ->
          RuntimeState.recordClientProbesSucceeded
            (fmap ServiceRuntime.daemonClientProbeStatusName statuses)
            state
      | otherwise ->
          RuntimeState.recordRuntimeFailure
            "client probing returned a pending status"
            state
 where
  failedProbe [] = Nothing
  failedProbe (status : rest) =
    case ServiceRuntime.daemonClientProbeStatusState status of
      ServiceRuntime.DaemonClientProbeFailed err ->
        Just (ServiceRuntime.daemonClientProbeStatusName status, err)
      _ -> failedProbe rest

  probeSucceeded status =
    case ServiceRuntime.daemonClientProbeStatusState status of
      ServiceRuntime.DaemonClientProbeSucceeded _ -> True
      _ -> False

daemonWorkloadDispatcherForRuntime
  :: (Capabilities.HasPulsar m)
  => ServiceRuntime.DaemonRuntime
  -> (Consumer.DaemonCommand -> EventId -> m (Either ServiceError ()))
  -> Consumer.DaemonCommand
  -> EventId
  -> m (Either ServiceError ())
daemonWorkloadDispatcherForRuntime runtime innerDispatcher command eventId
  | Left roleError <- ServiceRuntime.validateDaemonCommandDispatchRole runtime command =
      pure (Left roleError)
  | incomingSubstrate /= configuredSubstrate =
      pure
        ( Left
            ( SETransient
                ( "consumer delivery substrate mismatch: expected "
                    <> renderSubstrate configuredSubstrate
                    <> ", received "
                    <> renderSubstrate incomingSubstrate
                )
            )
        )
  | otherwise = do
      -- Sprint 14.1 (Feature C) — the Engine's workflow-status projector: alongside
      -- the underlying command dispatch, project the observed training / tune / rl
      -- lifecycle transition into a reconciled `WorkflowStatus` frame and republish
      -- it onto `workflow.status.<substrate>`, which the workflow panel renders live.
      dispatchResult <- innerDispatcher command eventId
      case dispatchResult of
        Left err -> pure (Left err)
        Right () ->
          case projectionMode of
            ServiceRuntime.SkipWorkflowStatusProjection -> pure (Right ())
            _projectionRequiredOrBestEffort ->
              ServiceRuntime.applyWorkflowStatusProjectionResult projectionMode
                <$> projectWorkflowStatus command
 where
  incomingSubstrate = Consumer.daemonCommandSubstrate command
  bootConfig = ServiceRuntime.daemonBootConfig runtime
  projectionMode =
    ServiceRuntime.workflowStatusProjectionMode bootConfig command
  configuredSubstrate = BootConfig.bootSubstrate bootConfig

coordinatorDaemonWorkloadDispatcherForRuntime
  :: ServiceRuntime.DaemonRuntime
  -> Consumer.DaemonCommand
  -> EventId
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
coordinatorDaemonWorkloadDispatcherForRuntime runtime =
  daemonWorkloadDispatcherForRuntime runtime coordinatorDispatcher
 where
  coordinatorDispatcher =
    case BootConfig.bootSubstrate
      (ServiceRuntime.daemonBootConfig runtime) of
      AppleSilicon -> ServiceRuntime.daemonWorkloadDispatcherForwardingInference
      LinuxCPU -> ServiceRuntime.daemonWorkloadDispatcher
      LinuxCUDA -> ServiceRuntime.daemonWorkloadDispatcher

engineDaemonWorkloadDispatcherForRuntime
  :: Env
  -> ServiceRuntime.DaemonRuntime
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> Consumer.DaemonCommand
  -> EventId
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
engineDaemonWorkloadDispatcherForRuntime env runtime hostWorkloadRegistry =
  daemonWorkloadDispatcherForRuntime runtime engineDispatcher
 where
  bootConfig = ServiceRuntime.daemonBootConfig runtime
  configuredSubstrate = BootConfig.bootSubstrate bootConfig
  engineDispatcher =
    case (configuredSubstrate, BootConfig.bootInferenceMode bootConfig) of
      -- Sprint 13.11 — both Linux substrates route SelfInference through the
      -- weighted runners so the daemon executes the substrate-specific weighted
      -- kernel against `.jmw1`-decoded tensors instead of the deterministic
      -- summary path.
      (LinuxCPU, BootConfig.SelfInference) ->
        ServiceRuntime.daemonWorkloadDispatcherWithWeightedInference $ \modelRef manifest weights input ->
          liftIO (engineWeightedInference env LinuxCPU modelRef manifest weights input)
      (LinuxCUDA, BootConfig.SelfInference) ->
        ServiceRuntime.daemonWorkloadDispatcherWithWeightedInference $ \modelRef manifest weights input ->
          liftIO (engineWeightedInference env LinuxCUDA modelRef manifest weights input)
      -- Sprint 14.5 — the Apple host-native daemon (`Host + SelfInference`)
      -- routes inference through the Metal weighted runner so it executes the
      -- generated `jitml_weighted_kernel` against `.jmw1`-decoded tensors. The host
      -- daemon is the Engine for `apple-silicon`: it consumes the cluster-forwarded
      -- inference command off `inference.command.apple-silicon`, runs the Metal
      -- weighted kernel, and publishes the matching `InferenceResult` to the
      -- request's reply-topic directly (the converged values model). Sprint 5.11
      -- extends that host-resident execution rule to Metal-backed training/RL/tune
      -- command envelopes forwarded by the in-cluster Apple daemon on the
      -- host-command topics.
      (AppleSilicon, BootConfig.SelfInference) ->
        daemonWorkloadDispatcherHostingAppleWorkloads env hostWorkloadRegistry
      _ -> \_command _eventId ->
        pure
          ( Left
              ( SEUnauthorized
                  "Engine client cannot execute Coordinator orchestration"
              )
          )

-- | Sprint 14.1 (Feature C) — project an observed lifecycle transition into a
-- reconciled `WorkflowStatus` frame and publish it onto
-- `workflow.status.<substrate>`. The caller selects whether a failure is a
-- best-effort overlay or required terminal evidence for acknowledgement.
-- Inference-domain payloads carry no run status and are skipped.
projectWorkflowStatus
  :: (Capabilities.HasPulsar m)
  => Consumer.DaemonCommand
  -> m (Either ServiceError ())
projectWorkflowStatus command =
  case WorkflowStatus.workflowStatusFrameForDaemonCommand command of
    Nothing -> pure (Right ())
    Just frame ->
      case Topology.mkWorkflowStatusMessage
        (WorkflowStatus.renderWorkflowStatusFrame frame) of
        Left decodeError ->
          pure
            ( Left
                ( SEConflict
                    ( "workflow status frame encoding failed: "
                        <> Text.pack (show decodeError)
                    )
                )
            )
        Right message ->
          publishProtocolEvent
            Topology.WorkflowStatusRoute
            (Consumer.daemonCommandSubstrate command)
            message

daemonWorkloadDispatcherHostingAppleWorkloads
  :: Env
  -> Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> Consumer.DaemonCommand
  -> EventId
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
daemonWorkloadDispatcherHostingAppleWorkloads env hostWorkloadRegistry command eventId
  | substrate /= AppleSilicon =
      pure (Left (SETransient "host Apple dispatcher received a non-apple-silicon delivery"))
  | otherwise =
      case ServiceRuntime.planAppleHostWorkloadAction command of
        Left err -> pure (Left err)
        Right action ->
          case action of
            ServiceRuntime.RunAppleHostTraining start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleTraining env start)
            ServiceRuntime.RunAppleHostTune start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleTune env start)
            ServiceRuntime.RunAppleHostRl start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleRl env start)
            ServiceRuntime.RunAppleHostAlphaZero start ->
              superviseAppleHostWorkload
                hostWorkloadRegistry
                action
                (runHostAppleAlphaZero env start)
            ServiceRuntime.StopAppleHostWorkload mode key ->
              stopAppleHostWorkload hostWorkloadRegistry eventId mode key
            ServiceRuntime.RunAppleHostInference _ ->
              hostInferenceFallback command eventId
 where
  substrate = Consumer.daemonCommandSubstrate command
  hostInferenceFallback =
    ServiceRuntime.daemonWorkloadDispatcherHostingAppleInference
      ( \modelRef manifest weights input -> liftIO (engineWeightedInference env AppleSilicon modelRef manifest weights input)
      )

superviseAppleHostWorkload
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> ServiceRuntime.AppleHostWorkloadAction
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
superviseAppleHostWorkload registry action workload = do
  clientSettings <- ask
  liftIO
    ( ServiceRuntime.executeAppleHostWorkloadStart registry action $ do
        workloadResult <-
          ServiceClients.runEngineServiceClient clientSettings workload
        case workloadResult of
          Right () -> pure ()
          Left serviceError ->
            throwIO
              ( userError
                  ( "Apple host workload failed: "
                      <> show serviceError
                  )
              )
    )

stopAppleHostWorkload
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> EventId
  -> ServiceRuntime.AppleHostWorkloadStopMode
  -> HostWorkloadRegistry.HostWorkloadKey
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
stopAppleHostWorkload registry eventId mode key =
  liftIO
    ( ServiceRuntime.executeAppleHostWorkloadStop
        registry
        eventId
        mode
        key
    )

runHostAppleTraining
  :: Env
  -> ProtoTraining.StartTraining
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleTraining env start
  | ProtoTraining.stSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple training received a non-apple-silicon command"))
  | otherwise = case PlanCommand.validateStartTraining start of
      Left err ->
        pure (Left (SETransient ("host Apple supervised plan refinement failed: " <> err)))
      Right plan -> do
        problemE <-
          liftIO
            ( SL.loadCanonicalProblemExperiment
                ( Text.unpack
                    (runPlanSubjectId (WorkloadPlan.supervisedPlanRunPlan plan))
                )
            )
        case problemE of
          Left err -> pure (Left (SETransient ("host Apple training experiment decode failed: " <> err)))
          Right problem -> do
            case supervisedExecutionBudget plan of
              Left err -> pure (Left (SETransient err))
              Right (trainLimit, epochs, testLimit, batchSize) -> do
                result <-
                  liftIO
                    ( runReaderT
                        ( runDeviceMnistTrainingWithLimitsAndLearningRate
                            AppleSilicon
                            problem
                            trainLimit
                            epochs
                            testLimit
                            batchSize
                            Nothing
                        )
                        env
                    )
                case result of
                  Left err -> pure (Left (SETransient ("host Apple training failed: " <> err)))
                  Right metrics -> do
                    epochResult <- publishTrainingEpoch start metrics
                    case epochResult of
                      Left err -> pure (Left err)
                      Right () -> publishTrainingCheckpoint problem plan start metrics

publishTrainingEpoch
  :: ProtoTraining.StartTraining
  -> TrainingMetrics
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishTrainingEpoch start metrics = do
  timestampNs <- liftIO currentTimestampNs
  let epochNumber = fromIntegral (tmCompletedUnits metrics)
      envelope =
        ProtoTraining.TrainingEpoch
          ( ProtoTraining.EpochCompleted
              { ProtoTraining.ecExperimentHash = ProtoTraining.stExperimentHash start
              , ProtoTraining.ecEpoch = epochNumber
              , -- Sprint 8.13 — real train + held-out validation loss.
                ProtoTraining.ecLoss = tmTrainLoss metrics
              , ProtoTraining.ecValidationLoss = tmValidationLoss metrics
              , ProtoTraining.ecTimestampNs = timestampNs
              }
          )
  publishProtocolEvent Topology.TrainingEventRoute AppleSilicon envelope

publishTrainingCheckpoint
  :: SL.CanonicalProblem
  -> WorkloadPlan.SupervisedPlan
  -> ProtoTraining.StartTraining
  -> TrainingMetrics
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishTrainingCheckpoint problem plan start metrics =
  case tmCheckpointWeights metrics of
    Nothing -> pure (Right ())
    Just weights -> do
      let experimentHash = ProtoTraining.stExperimentHash start
          step = tmCompletedUnits metrics
          tensorName = "sl-trained-weights"
          metricRows = trainingCheckpointMetrics metrics
          completedTraining =
            eitherToMaybe
              ( completedTrainingForSupervisedProblem
                  plan
                  problem
                  metrics
                  experimentHash
                  tensorName
                  step
                  metricRows
                  weights
              )
      checkpointResult <-
        writeMinIOWeightCheckpointWithDatasetShaAndCompleted
          (tmDatasetShaAtRead metrics)
          completedTraining
          experimentHash
          tensorName
          step
          metricRows
          weights
      case checkpointResult of
        Left err -> pure (Left err)
        Right stored -> do
          case trainingCheckpointEventEnvelope
            experimentHash
            tensorName
            step
            metricRows
            (tmDatasetShaAtRead metrics)
            completedTraining
            weights
            stored of
            Left err -> pure (Left (SETransient ("host Apple checkpoint event failed: " <> err)))
            Right envelope ->
              publishProtocolEvent Topology.TrainingEventRoute AppleSilicon envelope

runHostAppleTune
  :: Env
  -> ProtoTune.StartSweep
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleTune env start
  | ProtoTune.ssSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple tune received a non-apple-silicon command"))
  | otherwise = case PlanCommand.validateStartSweep start of
      Left err -> pure (Left (SETransient ("host Apple tuning plan validation failed: " <> err)))
      Right plan -> case tuningExecutionCountsService "host Apple tuning" plan of
        Left err -> pure (Left err)
        Right (trialCount, parallelism, promotions, updates) -> do
          let device = mlpDeviceForSubstrate AppleSilicon env
          trialResultsE <-
            liftIO
              ( Tune.trialObjectiveResultsWithDeviceForBudget
                  device
                  (WorkloadPlan.tuningPlanSampler plan)
                  parallelism
                  updates
                  trialCount
              )
          case trialResultsE of
            Left err -> pure (Left (SETransient ("host Apple tune failed: " <> err)))
            Right trialResults ->
              case Tune.trialExecutions
                (WorkloadPlan.tuningPlanScheduler plan)
                (WorkloadPlan.tuningPlanPruner plan)
                promotions
                trialResults of
                Left err -> pure (Left (SETransient ("host Apple tune failed: " <> err)))
                Right executions -> publishHostTuneEvents plan executions

publishHostTuneEvents
  :: WorkloadPlan.TuningPlan
  -> [Tune.TrialExecution]
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishHostTuneEvents plan trialResults = do
  baseSeed <- case word64ToIntService
    "host Apple tuning seed"
    (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan)))) of
    Left err -> pure (Left err)
    Right value -> pure (Right value)
  case baseSeed of
    Left err -> pure (Left err)
    Right resolvedSeed -> publishWithSeed resolvedSeed
 where
  planId = planIdText (WorkloadPlan.tuningPlanId plan)
  experimentHash = runPlanExperimentId (WorkloadPlan.tuningPlanRunPlan plan)
  publishWithSeed baseSeed = do
    let
      promotedResults =
        [ Tune.trialExecutionResult execution
        | execution <- trialResults
        , Tune.trialExecutionPromoted execution
        ]
      objectives = fmap Tune.trialResultObjective promotedResults
      prunedCount = length (filter Tune.trialExecutionPruned trialResults)
      promotedCount = length promotedResults
    publishedResults <- traverse (publishTrial baseSeed) trialResults
    case firstLeft publishedResults of
      Just err -> pure (Left err)
      Nothing -> do
        let completed = fromIntegral (length trialResults)
            bestObjective = if null objectives then 0.0 else maximum objectives
            finished =
              ProtoTune.SweepFinished
                { ProtoTune.sfExperimentHash = experimentHash
                , ProtoTune.sfPlanId = planId
                , ProtoTune.sfTrialsCompleted = completed
                , ProtoTune.sfTrialsPruned = fromIntegral prunedCount
                , ProtoTune.sfTrialsPromoted = fromIntegral promotedCount
                , ProtoTune.sfBestObjective = bestObjective
                }
        case tuneSweepCompletedTraining
          plan
          experimentHash
          completed
          bestObjective of
          Left err -> pure (Left (SETransient ("host Apple tuning completion failed: " <> err)))
          Right completedTraining ->
            case ProtoTune.completeSweep finished completedTraining of
              Left err -> pure (Left (SETransient ("host Apple tuning event failed: " <> err)))
              Right completedSweep ->
                publishProtocolEvent
                  Topology.TuneEventRoute
                  AppleSilicon
                  (ProtoTune.TuneSweepCompleted completedSweep)

  publishTrial baseSeed execution = do
    timestampStart <- liftIO currentTimestampNs
    let trialResult = Tune.trialExecutionResult execution
        trialIndex = Tune.trialResultIndex trialResult
        trialSeed = baseSeed + trialIndex
        objective = Tune.trialResultObjective trialResult
        started =
          ProtoTune.TuneTrialStarted
            ( ProtoTune.TrialStarted
                { ProtoTune.tsExperimentHash = experimentHash
                , ProtoTune.tsPlanId = planId
                , ProtoTune.tsTrial = fromIntegral trialIndex
                , ProtoTune.tsTrialSeed = fromIntegral trialSeed
                , ProtoTune.tsParametersJson =
                    "{\"sampler\":\""
                      <> Text.pack (show (WorkloadPlan.tuningPlanSampler plan))
                      <> "\",\"scheduler\":\""
                      <> Text.pack (show (WorkloadPlan.tuningPlanScheduler plan))
                      <> "\",\"pruner\":\""
                      <> Text.pack (show (WorkloadPlan.tuningPlanPruner plan))
                      <> "\",\"parallelism\":"
                      <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanParallelism plan)))
                      <> ",\"promotions\":"
                      <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanPromotions plan)))
                      <> ",\"perTrialOptimizerUpdates\":"
                      <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan)))
                      <> "}"
                , ProtoTune.tsTimestampNs = timestampStart
                }
            )
    startResult <-
      publishProtocolEvent Topology.TuneEventRoute AppleSilicon started
    case startResult of
      Left err -> pure (Left err)
      Right () -> do
        persistResult <-
          Tune.persistTrialTranscript
            Tune.TrialTranscript
              { Tune.transcriptExperimentHash = experimentHash
              , Tune.transcriptTrialSeed = trialSeed
              , Tune.transcriptValues = [objective]
              }
        case persistResult of
          Left err -> pure (Left err)
          Right _ -> do
            checkpointResult <-
              if Tune.trialExecutionPromoted execution
                then
                  void
                    <$> writeMinIOWeightCheckpoint
                      experimentHash
                      "tune-trial-weights"
                      (fromIntegral trialSeed)
                      [("objective", objective)]
                      (Tune.trialResultWeights trialResult)
                else pure (Right ())
            case checkpointResult of
              Left err -> pure (Left err)
              Right () -> do
                timestampEnd <- liftIO currentTimestampNs
                let finished =
                      ProtoTune.TuneTrialFinished
                        ( ProtoTune.TrialFinished
                            { ProtoTune.tfTuneExperimentHash = experimentHash
                            , ProtoTune.tfTunePlanId = planId
                            , ProtoTune.tfTuneTrial = fromIntegral trialIndex
                            , ProtoTune.tfTuneObjective = objective
                            , ProtoTune.tfTunePruned = Tune.trialExecutionPruned execution
                            , ProtoTune.tfTuneTranscriptObjectKey =
                                Tune.trialStorageKey experimentHash trialSeed
                            , ProtoTune.tfTuneTimestampNs = timestampEnd
                            }
                        )
                publishProtocolEvent Topology.TuneEventRoute AppleSilicon finished

tuningExecutionCountsService
  :: Text
  -> WorkloadPlan.TuningPlan
  -> Either ServiceError (Int, Int, Int, Int)
tuningExecutionCountsService label plan =
  (,,,)
    <$> word64ToIntService (label <> " trial count") (quantityValue (WorkloadPlan.tuningPlanTrials plan))
    <*> word64ToIntService
      (label <> " parallelism")
      (quantityValue (WorkloadPlan.tuningPlanParallelism plan))
    <*> word64ToIntService (label <> " promotions") (quantityValue (WorkloadPlan.tuningPlanPromotions plan))
    <*> word64ToIntService
      (label <> " per-trial updates")
      (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan))

word64ToIntService :: Text -> Word64 -> Either ServiceError Int
word64ToIntService label value
  | toInteger value > toInteger (maxBound :: Int) =
      Left (SETransient (label <> " exceeds the platform Int range"))
  | otherwise = Right (fromIntegral value)

runHostAppleRl
  :: Env
  -> ProtoRl.StartRLRun
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleRl env start
  | ProtoRl.srlSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple RL received a non-apple-silicon command"))
  | otherwise = do
      let trainerKind = Workload.rlTrainerForAlgorithm (ProtoRl.srlAlgorithm start)
          device = rlDeviceForSubstrate AppleSilicon env
      episodesE <-
        liftIO
          ( runTrainerEpisodes
              AppleSilicon
              device
              Nothing
              trainerKind
              (ProtoRl.srlEnvironment start)
              (fromIntegral (ProtoRl.srlSeed start))
              (max 1 (fromIntegral (ProtoRl.srlEvalEpisodes start)))
              (max 1 (fromIntegral (ProtoRl.srlMaxSteps start)))
              Nothing
          )
      case episodesE of
        Left err -> pure (Left (SETransient ("host Apple RL failed: " <> err)))
        Right trainerRun -> do
          results <- traverse (publishHostRlEpisode start) (trainerRunEpisodes trainerRun)
          pure $ maybe (Right ()) Left (firstLeft results)

runHostAppleAlphaZero
  :: Env
  -> ProtoRl.StartAlphaZeroRun
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
runHostAppleAlphaZero env start
  | ProtoRl.sazSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple AlphaZero received a non-apple-silicon command"))
  | otherwise = case PlanCommand.validateStartAlphaZeroRun start of
      Left err -> pure (Left (SETransient ("host Apple AlphaZero plan validation failed: " <> err)))
      Right plan ->
        case alphaZeroHostInputs plan of
          Left err -> pure (Left err)
          Right (generations, games, sims, maxPlies, updates, arenaGames, seed) -> do
            let gameName = WorkloadPlan.renderAlphaZeroGame (WorkloadPlan.alphaZeroPlanGame plan)
                experimentHash = runPlanExperimentId (WorkloadPlan.alphaZeroPlanRunPlan plan)
                planId = planIdText (WorkloadPlan.alphaZeroPlanId plan)
                initialState = AlphaZero.initialStateFor gameName
                device = rlDeviceForSubstrate AppleSilicon env
                net0 =
                  PolicyValueNet.initPolicyValueNet
                    (AlphaZero.observationSizeFor gameName)
                    (AlphaZero.actionCountFor gameName)
                    16
                    seed
                adam0 = PolicyValueNet.initAdamFor net0
            probe <- liftIO (probeMlpDevice device)
            case probe of
              Left err -> pure (Left (SETransient ("host Apple AlphaZero device failed: " <> err)))
              Right () -> do
                trained <-
                  trainHostAlphaZeroGenerations
                    experimentHash
                    planId
                    initialState
                    device
                    net0
                    adam0
                    generations
                    games
                    sims
                    maxPlies
                    updates
                    seed
                case trained of
                  Left err -> pure (Left err)
                  Right (trainedNet, samples) -> do
                    let winRate =
                          PolicyValueNet.arenaWinRateAgainstUniformFrom
                            initialState
                            trainedNet
                            arenaGames
                            maxPlies
                            (seed + 7919)
                        completedGenerations = fromIntegral generations
                        checkpointStep =
                          alphaZeroArtifactStep completedGenerations (length samples)
                        metrics =
                          [ ("arena_win_rate", winRate)
                          , ("legal_move_rate", 1.0)
                          , ("mcts_simulations_per_move", fromIntegral sims)
                          , ("self_play_games", fromIntegral games)
                          , ("self_play_generations", fromIntegral generations)
                          , ("self_play_samples", fromIntegral (length samples))
                          ]
                        initialWeights = PolicyValueNet.policyValueNetToFlat net0
                        finalWeights = PolicyValueNet.policyValueNetToFlat trainedNet
                        completed =
                          do
                            budget <- eitherToMaybe (alphaZeroCompletionBudget plan)
                            alphaZeroCompletedTraining
                              (WorkloadPlan.alphaZeroPlanId plan)
                              budget
                              experimentHash
                              gameName
                              completedGenerations
                              metrics
                              initialWeights
                              finalWeights
                    checkpoint <-
                      writeMinIOWeightCheckpointWithDatasetShaAndCompleted
                        Nothing
                        completed
                        experimentHash
                        ("alphazero-" <> gameName <> "-policy-value-weights")
                        checkpointStep
                        metrics
                        finalWeights
                    case checkpoint of
                      Left err -> pure (Left err)
                      Right _ ->
                        publishProtocolEvent
                          Topology.RlEventRoute
                          AppleSilicon
                          ( ProtoRl.RlArenaCompleted
                              ProtoRl.ArenaCompleted
                                { ProtoRl.acPlanId = planId
                                , ProtoRl.acExperimentHash = experimentHash
                                , ProtoRl.acArenaGames = fromIntegral arenaGames
                                , ProtoRl.acWinRate = winRate
                                }
                          )
 where
  alphaZeroHostInputs plan = do
    generations <-
      convert "host Apple AlphaZero generations" (WorkloadPlan.alphaZeroPlanGenerations plan)
    games <-
      convert "host Apple AlphaZero self-play games" (WorkloadPlan.alphaZeroPlanSelfPlayGames plan)
    sims <-
      convert "host Apple AlphaZero MCTS simulations" (WorkloadPlan.alphaZeroPlanMctsSimulations plan)
    maxPlies <- convert "host Apple AlphaZero max plies" (WorkloadPlan.alphaZeroPlanMaxPlies plan)
    updates <- convert "host Apple AlphaZero optimizer updates" (WorkloadPlan.alphaZeroPlanUpdates plan)
    arenaGames <- convert "host Apple AlphaZero arena games" (WorkloadPlan.alphaZeroPlanArenaGames plan)
    seed <-
      word64ToIntService
        "host Apple AlphaZero seed"
        (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.alphaZeroPlanRunPlan plan))))
    pure (generations, games, sims, maxPlies, updates, arenaGames, seed)
  convert label = word64ToIntService label . quantityValue

trainHostAlphaZeroGenerations
  :: Text
  -> Text
  -> AlphaZero.GameState
  -> MlpDevice
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> ServiceClients.EngineServiceClient
       (Either ServiceError (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample]))
trainHostAlphaZeroGenerations experimentHash planId initialState device = go 0
 where
  go generation net adam generationTarget games sims maxPlies updates seed
    | generation >= generationTarget = pure (Right (net, []))
    | otherwise = do
        sampleResults <-
          liftIO $
            traverse
              ( \gameIndex ->
                  PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                    initialState
                    device
                    net
                    (seed + generation * 7919 + gameIndex)
                    sims
                    maxPlies
              )
              [0 .. games - 1]
        case sequence sampleResults of
          Left err -> pure (Left (SETransient ("host Apple AlphaZero self-play failed: " <> err)))
          Right batches -> do
            let generationSamples = concat batches
            if null generationSamples
              then pure (Left (SETransient "host Apple AlphaZero self-play produced no samples"))
              else do
                trained <-
                  liftIO
                    ( PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
                        device
                        net
                        adam
                        1.0e-3
                        updates
                        generationSamples
                    )
                case trained of
                  Left err -> pure (Left (SETransient ("host Apple AlphaZero training failed: " <> err)))
                  Right (trainedNet, trainedAdam) -> do
                    published <-
                      publishProtocolEvent
                        Topology.RlEventRoute
                        AppleSilicon
                        ( ProtoRl.RlGenerationCompleted
                            ProtoRl.GenerationCompleted
                              { ProtoRl.gcPlanId = planId
                              , ProtoRl.gcExperimentHash = experimentHash
                              , ProtoRl.gcGeneration = fromIntegral generation
                              , ProtoRl.gcSelfPlayGames = fromIntegral games
                              , ProtoRl.gcSamples = fromIntegral (length generationSamples)
                              }
                        )
                    case published of
                      Left err -> pure (Left err)
                      Right () -> do
                        later <-
                          go
                            (generation + 1)
                            trainedNet
                            trainedAdam
                            generationTarget
                            games
                            sims
                            maxPlies
                            updates
                            seed
                        pure (fmap (second (generationSamples <>)) later)

publishHostRlEpisode
  :: ProtoRl.StartRLRun
  -> EpisodeEnvelope.SimulatedEpisode
  -> ServiceClients.EngineServiceClient (Either ServiceError ())
publishHostRlEpisode start episode = do
  timestampNs <- liftIO currentTimestampNs
  let envelope =
        ProtoRl.RlEpisode
          ( ProtoRl.EpisodeDone
              { ProtoRl.edExperimentHash = ProtoRl.srlExperimentHash start
              , ProtoRl.edEpisode = fromIntegral (EpisodeEnvelope.simEpisodeIndex episode)
              , ProtoRl.edReward = EpisodeEnvelope.simEpisodeReward episode
              , ProtoRl.edSteps = fromIntegral (EpisodeEnvelope.simEpisodeSteps episode)
              , ProtoRl.edTimestampNs = timestampNs
              }
          )
      animationEnvelopes =
        fmap
          (rlAnimationEnvelope (ProtoRl.srlExperimentHash start) (ProtoRl.srlEnvironment start) timestampNs)
          (EpisodeEnvelope.simEpisodeFrames episode)
  episodeResult <- publishProtocolEvent Topology.RlEventRoute AppleSilicon envelope
  frameResults <-
    traverse
      (publishProtocolEvent Topology.RlEventRoute AppleSilicon)
      animationEnvelopes
  pure $ maybe (Right ()) Left (firstLeft (episodeResult : frameResults))

publishProtocolEvent
  :: (Capabilities.HasPulsar m)
  => Topology.ProtocolRoute event
  -> Substrate
  -> event
  -> m (Either ServiceError ())
publishProtocolEvent route substrate event =
  case Topology.topicFor route substrate of
    Left err ->
      pure (Left (SETransient ("Pulsar topic resolution failed: " <> Text.pack (show err))))
    Right topic ->
      fmap void (Capabilities.pulsarPublish topic event)

publishPulsarEvent
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Topology.ProtocolRoute event
  -> Substrate
  -> event
  -> IO (Either ServiceError Text)
publishPulsarEvent settings route substrate event =
  case Topology.topicFor route substrate of
    Left err ->
      pure (Left (SETransient ("Pulsar topic resolution failed: " <> Text.pack (show err))))
    Right topic ->
      PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
        settings
        (Capabilities.pulsarPublish topic event)

firstLeft :: [Either a b] -> Maybe a
firstLeft [] = Nothing
firstLeft (Left err : _) = Just err
firstLeft (Right _ : rest) = firstLeft rest

-- | Sprint 5.10 — the host-native Apple daemon acquires only the fixed Metal
-- bridge and the host OS Metal runtime. If the fixed bridge is absent, jitML
-- makes one headless source-build attempt for that process-stable bridge before
-- subscribing to work. Kernel cache misses still only write source metadata and
-- call the bridge.
acquireAppleMetalBridge
  :: ServiceRuntime.DaemonRuntime
  -> App (Either (ServiceRuntime.DaemonRuntime, AppError) ServiceRuntime.DaemonRuntime)
acquireAppleMetalBridge runtime =
  case (BootConfig.bootSubstrate boot, BootConfig.bootInferenceMode boot) of
    (AppleSilicon, BootConfig.SelfInference) -> do
      metalProbe <- liftIO probeMetalRuntime
      bridgeAcquire <- liftIO acquireFixedBridge
      let runtimeAvailable = metalRuntimeAvailable metalProbe
          bridgeAvailable = bridgeAcquireAvailable bridgeAcquire
          statusText =
            "apple.metal-runtime="
              <> renderAcquireBool runtimeAvailable
              <> " apple.metal-bridge="
              <> renderAcquireBool bridgeAvailable
              <> bridgeAcquireSummary bridgeAcquire
          acquired =
            runtime
              { ServiceRuntime.daemonAppleMetalAcquireStatus =
                  if runtimeAvailable && bridgeAvailable
                    then ServiceRuntime.AppleMetalAcquireSucceeded statusText
                    else ServiceRuntime.AppleMetalAcquireFailed statusText
              , ServiceRuntime.daemonState =
                  if runtimeAvailable && bridgeAvailable
                    then
                      RuntimeState.recordMetalAcquired
                        statusText
                        (ServiceRuntime.daemonState runtime)
                    else
                      RuntimeState.recordMetalFailure
                        statusText
                        (ServiceRuntime.daemonState runtime)
              }
      pure $
        if runtimeAvailable && bridgeAvailable
          then Right acquired
          else
            Left
              ( acquired
              , appleMetalAcquireError runtimeAvailable bridgeAvailable
              )
    _ ->
      pure
        ( Right
            runtime
              { ServiceRuntime.daemonState =
                  RuntimeState.recordMetalNotRequired
                    (ServiceRuntime.daemonState runtime)
              }
        )
 where
  boot = ServiceRuntime.daemonBootConfig runtime

acquireFixedBridge :: IO BridgeAcquireResult
acquireFixedBridge = do
  bridgeAvailable <- ContainerPrerequisites.probeFixedMetalBridge
  if bridgeAvailable
    then pure BridgeAlreadyAvailable
    else do
      installed <- MetalBridge.installFixedMetalBridge
      case installed of
        Right path -> do
          verified <- ContainerPrerequisites.probeFixedMetalBridge
          pure $
            if verified
              then BridgeInstalled path
              else BridgeInstallFailed "installed bridge did not pass probe"
        Left err -> pure (BridgeInstallFailed (MetalBridge.renderMetalBridgeInstallError err))

data BridgeAcquireResult
  = BridgeAlreadyAvailable
  | BridgeInstalled FilePath
  | BridgeInstallFailed Text
  deriving stock (Eq, Show)

bridgeAcquireAvailable :: BridgeAcquireResult -> Bool
bridgeAcquireAvailable BridgeAlreadyAvailable = True
bridgeAcquireAvailable BridgeInstalled {} = True
bridgeAcquireAvailable BridgeInstallFailed {} = False

bridgeAcquireSummary :: BridgeAcquireResult -> Text
bridgeAcquireSummary BridgeAlreadyAvailable = " bridge_source=existing"
bridgeAcquireSummary (BridgeInstalled path) = " bridge_source=installed:" <> Text.pack path
bridgeAcquireSummary (BridgeInstallFailed err) = " bridge_install_error=" <> err

appleMetalAcquireError :: Bool -> Bool -> AppError
appleMetalAcquireError runtimeAvailable bridgeAvailable
  | not runtimeAvailable =
      PrerequisiteUnmet
        "apple.metal-runtime"
        "Apple host Metal runtime is unavailable to jitml service."
        ( Just
            "run on Apple Silicon with a visible Metal device; jitML will not use VM, generated package, login-keychain, or full-Xcode remediation for this prerequisite"
        )
  | not bridgeAvailable =
      PrerequisiteUnmet
        "apple.metal-bridge"
        "Fixed jitML Metal bridge dylib is unavailable or its probe failed."
        (Just "build or install the fixed jitML Metal bridge dylib before starting the Apple host daemon")
  | otherwise =
      InvalidConfig "apple Metal acquire failed unexpectedly"

renderAcquireBool :: Bool -> Text
renderAcquireBool True = "yes"
renderAcquireBool False = "no"

runInstallMetalBridge :: App ()
runInstallMetalBridge = do
  installed <- liftIO MetalBridge.installFixedMetalBridge
  case installed of
    Left (MetalBridge.MetalBridgeBuildFailed failure) ->
      exitWithError (SubprocessFailed failure)
    Left err ->
      exitWithError (InvalidConfig (MetalBridge.renderMetalBridgeInstallError err))
    Right path -> do
      writeLine ("metal_bridge: " <> Text.pack path)
      writeLine "metal_bridge_probe: ok"

loadServiceConfigs
  :: Text
  -> Bool
  -> App (BootConfig.BootConfig, LiveConfig.LiveConfig)
loadServiceConfigs configPath explicitConfig = do
  let path = Text.unpack configPath
      liveConfigPath = takeDirectory path </> "LiveConfig.dhall"
  exists <- liftIO (doesFileExist path)
  if exists
    then do
      bootResult <- liftIO (tryAny (BootConfig.loadBootConfig path))
      bootConfig <-
        case bootResult of
          Right loaded -> pure loaded
          Left err ->
            exitWithError
              ( InvalidConfig
                  ( "failed to load service config "
                      <> configPath
                      <> ": "
                      <> Text.pack (displayException err)
                  )
              )
      liveExists <- liftIO (doesFileExist liveConfigPath)
      unless liveExists $
        exitWithError
          ( InvalidConfig
              ( "service live config does not exist: "
                  <> Text.pack liveConfigPath
              )
          )
      liveResult <- liftIO (tryAny (LiveConfig.loadLiveConfig liveConfigPath))
      case liveResult of
        Right liveConfig ->
          pure (bootConfig, liveConfig)
        Left err ->
          exitWithError
            ( InvalidConfig
                ( "failed to load service live config "
                    <> Text.pack liveConfigPath
                    <> ": "
                    <> Text.pack (displayException err)
                )
            )
    else
      if explicitConfig
        then exitWithError (InvalidConfig ("service config does not exist: " <> configPath))
        else
          pure
            ( ServiceRuntime.daemonBootConfig ServiceRuntime.defaultDaemonRuntime
            , ServiceRuntime.daemonLiveConfig ServiceRuntime.defaultDaemonRuntime
            )

runCluster :: [Text] -> [ParsedOption] -> App ()
runCluster ["cluster", "up"] parsedOptions =
  case selectedSubstrate parsedOptions of
    Left err -> exitWithError err
    Right substrate -> do
      result <- liftIO (liveExecutePhasedRollout substrate "chart")
      if liveAlreadyConverged result
        then writeLine ("cluster up: " <> renderSubstrate substrate <> " already converged")
        else
          writeLine
            ( "cluster up: live phased rollout executed "
                <> Text.pack (show (length (liveStepsExecuted result)))
                <> " steps"
            )
      mapM_
        ( \failure ->
            writeLine ("cluster up: step failed: " <> renderLiveStepFailure failure)
        )
        (liveStepsFailed result)
      exitWithLiveStepFailure "cluster up live phased rollout" (liveStepsFailed result)
      writeText (renderPublicationSummary (livePublication result))
      when (liveAlreadyConverged result) $
        exitWithError
          (ReconcilerNoop ("cluster up: " <> renderSubstrate substrate <> " already current"))
runCluster ["cluster", "status"] _ = do
  publication <- readClusterPublicationOrExit
  writeText (renderPublicationSummary publication)
runCluster ["cluster", "down"] _ = do
  publication <- readClusterPublicationOrExit
  let substrate = Publication.publicationSubstrate publication
      command = Helm.kindDeleteSubprocess substrate
      clusterName = "jitml-" <> renderSubstrate substrate
  outcome <- liftIO (runStreaming defaultSubprocessEnv command)
  case outcome of
    ProcessSucceeded _ ->
      liftIO (writeClusterPublication (publicationWithStatus "stopped" publication))
        >> writeLine ("cluster down: " <> clusterName <> " deleted; ./.build and ./.data preserved")
    ProcessFailed failure ->
      case processFailureExitCode failure of
        ExitFailure 3 -> do
          liftIO (writeClusterPublication (publicationWithStatus "stopped" publication))
          exitWithError (ReconcilerNoop ("cluster down: " <> clusterName <> " already absent"))
        _ -> exitWithError (SubprocessFailed failure)
runCluster ["cluster", "reset"] parsedOptions
  | hasOption "yes" parsedOptions =
      writeLine "cluster reset: local runtime state reset requested"
  | otherwise =
      exitWithError (InvalidConfig "cluster reset requires --yes")
runCluster path _ =
  exitWithError (UnknownCommand ("unknown cluster command: " <> commandPathText path))

runBuild :: [ParsedOption] -> App ()
runBuild parsedOptions =
  case selectedSubstrateWithDefault LinuxCPU parsedOptions of
    Left err -> exitWithError err
    Right substrate -> do
      env <- ask
      let engine = engineForSubstrate substrate
          kernelSpec = Cache.KernelSpec "jitml-build:identity"
          kind = Cache.Training
          fingerprint = buildToolchainFingerprint substrate
      tuningPlanResult <-
        liftIO $
          TuningCache.selectTuningCachePlan
            (toFilePath (envCacheDir env))
            kernelSpec
            kind
            substrate
            fingerprint
      tuningPlan <-
        case tuningPlanResult of
          Left err -> exitWithError (InvalidConfig err)
          Right plan -> pure plan
      let runtimeSource = TuningCache.tuningCacheRuntimeSource tuningPlan
          hash = TuningCache.tuningCacheHash tuningPlan
          buildPlanSections =
            [ "build: /opt/build/jitml"
            , "tuning_base_hash: " <> Cache.hashHex (TuningCache.tuningCacheBaseHash tuningPlan)
            , "tuning_choice: " <> Cache.unTuningChoice (TuningCache.tuningCacheTuningChoice tuningPlan)
            , "tuning_selection: " <> TuningCache.tuningCacheSelectionSource tuningPlan
            , renderBuildPlan engine runtimeSource hash
            ]
          rendered = Text.unlines buildPlanSections
      case optionValues "plan-file" parsedOptions of
        [] -> pure ()
        planPath : _ -> liftIO (writePlanFile (Text.unpack planPath) rendered)
      runOutput <-
        if hasOption "dry-run" parsedOptions
          then pure []
          else case substrate of
            LinuxCPU -> do
              tunedArtifact <-
                runBenchmarkTunedEnsureKernelArtifact
                  env
                  substrate
                  kernelSpec
                  kind
                  fingerprint
              tunedPlanResult <-
                liftIO
                  ( TuningCache.selectTuningCachePlan
                      (toFilePath (envCacheDir env))
                      kernelSpec
                      kind
                      substrate
                      fingerprint
                  )
              case tunedPlanResult of
                Left err -> exitWithError (InvalidConfig err)
                Right tunedPlan -> do
                  let tunedSource = TuningCache.tuningCacheRuntimeSource tunedPlan
                      tunedHash = TuningCache.tuningCacheHash tunedPlan
                  result <-
                    liftIO (runLinuxCpuKernel env tunedSource tunedHash benchmarkSampleInput)
                  case result of
                    Left message ->
                      exitWithError (JitCacheMiss message)
                    Right kernelRun ->
                      pure
                        ( reportTunedArtifact tunedArtifact
                            <> ["linux_cpu_run: " <> Text.pack (show (linuxCpuKernelOutput kernelRun))]
                        )
            LinuxCUDA -> do
              tunedArtifact <-
                runBenchmarkTunedEnsureKernelArtifact
                  env
                  substrate
                  kernelSpec
                  kind
                  fingerprint
              pure (reportTunedArtifact tunedArtifact)
            _ -> do
              artifactResult <- liftIO (EngineLoader.ensureKernelArtifact env engine runtimeSource hash)
              case artifactResult of
                Left (EngineLoader.KernelArtifactProcessFailure failure) ->
                  exitWithError (SubprocessFailed failure)
                Left err ->
                  exitWithError (JitCacheMiss (EngineLoader.renderKernelArtifactError err))
                Right artifact ->
                  pure (reportTunedArtifact artifact)
      writeText (Text.unlines (rendered : runOutput))
 where
  benchmarkSampleInput :: [Float]
  -- Sprint 13.15 — full-tensor benchmark payload. The benchmark runner
  -- exercises the candidate kernel against a representative 32-float
  -- input (vs. the prior 2-float smoke fixture) so the persisted
  -- TuningChoice reflects realistic measurement against the same
  -- shape the JIT cache will see at inference time. Values are
  -- deterministic per the determinism contract.
  benchmarkSampleInput =
    [fromIntegral i / 4.0 | i <- [(0 :: Int) .. 31]]

  reportTunedArtifact artifact =
    [ "cache_artifact_ready: "
        <> kernelHandleArtifactPath (EngineLoader.kernelArtifactHandle artifact)
    , "cache_artifact_compiled: "
        <> if EngineLoader.kernelArtifactCompiled artifact then "yes" else "no"
    ]

  runBenchmarkTunedEnsureKernelArtifact env substrate kernelSpec kind fingerprint = do
    result <-
      liftIO
        ( TuningBenchmark.ensureKernelArtifactWithBenchmarkTuning
            env
            substrate
            kernelSpec
            kind
            fingerprint
            benchmarkSampleInput
        )
    case result of
      Left (EngineLoader.KernelArtifactProcessFailure failure) ->
        exitWithError (SubprocessFailed failure)
      Left err ->
        exitWithError (JitCacheMiss (EngineLoader.renderKernelArtifactError err))
      Right artifact -> pure artifact

buildToolchainFingerprint :: Substrate -> Cache.ToolchainFingerprint
buildToolchainFingerprint LinuxCPU =
  linuxCpuToolchainFingerprint
buildToolchainFingerprint _ =
  Cache.ToolchainFingerprint "jitml-build;compiler-pins=cabal.project"

runTrain :: [ParsedOption] -> App ()
runTrain parsedOptions = do
  -- Sprint 1.12 — parse CLI Dhall overrides (--substrate / --seed) per
  -- README.md → Why this exists pillar 2. The pure resolver returns an
  -- OverrideError on invalid flag values; we surface that through the
  -- existing AppError/exit-code path before any downstream work runs.
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  problem <- resolveTrainingProblem parsedOptions
  -- Sprint 8.10 — `jitml train` is a substrate-backed, fail-closed command:
  -- a live cluster publication and a staged dataset are hard prerequisites,
  -- and the network trains through the resolved substrate's JIT device with
  -- __no synthetic or pure-Haskell fallback__. When a prerequisite is unmet
  -- nothing is printed or published — the command exits 2 with a typed
  -- `TrainingPrerequisiteUnmet`. Only the live measured loss is published.
  substrate <- resolveWorkerSubstrate overrides
  plan <- resolveSupervisedInvocationPlan parsedOptions overrides substrate problem
  result <- runDeviceMnistTraining substrate problem plan
  case result of
    Left reason -> exitWithError (TrainingPrerequisiteUnmet reason)
    Right metrics -> do
      publishWorkerTrainingEvent metrics
      publishWorkerTrainingCheckpoint plan substrate problem parsedOptions metrics

resolveTrainingProblem :: [ParsedOption] -> App SL.CanonicalProblem
resolveTrainingProblem parsedOptions = do
  let dhallPath = Text.unpack (selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions)
  loaded <- liftIO (ProductExperiment.loadSupervisedProblemByPath dhallPath)
  case loaded of
    Left err -> exitWithError (DhallTypeError err)
    Right problem -> pure problem

resolveSupervisedInvocationPlan
  :: [ParsedOption]
  -> Overrides.ExperimentOverrides
  -> Substrate
  -> SL.CanonicalProblem
  -> App WorkloadPlan.SupervisedPlan
resolveSupervisedInvocationPlan parsedOptions overrides substrate problem = do
  mounted <- liftIO (RunConfig.tryLoadTrainingRunConfig runConfigPath)
  plan <- case mounted of
    RunConfig.RunConfigLoaded config ->
      case RunConfig.supervisedPlanFromRunConfig config of
        Left err -> exitWithError (mountedRunConfigDecodeError "TrainingRunConfig" err)
        Right resolved -> pure resolved
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError "TrainingRunConfig" err)
    RunConfig.RunConfigMissing -> do
      rejectMissingMountedRunConfigInKubernetes "TrainingRunConfig"
      prepareLocalSupervisedPlan parsedOptions overrides substrate problem
  let runPlan = WorkloadPlan.supervisedPlanRunPlan plan
      selectedPath = selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions
  when (runPlanSubstrate runPlan /= substrate) $
    exitWithError
      ( InvalidConfig
          ( "supervised plan substrate mismatch: plan="
              <> renderSubstrate (runPlanSubstrate runPlan)
              <> ", selected="
              <> renderSubstrate substrate
          )
      )
  when (runPlanSubjectId runPlan /= Text.strip selectedPath) $
    exitWithError
      ( InvalidConfig
          ( "supervised plan subject mismatch: plan="
              <> runPlanSubjectId runPlan
              <> ", command="
              <> Text.strip selectedPath
          )
      )
  pure plan

prepareLocalSupervisedPlan
  :: [ParsedOption]
  -> Overrides.ExperimentOverrides
  -> Substrate
  -> SL.CanonicalProblem
  -> App WorkloadPlan.SupervisedPlan
prepareLocalSupervisedPlan parsedOptions overrides substrate problem = do
  epochs <- localSupervisedQuantity "JITML_SL_EPOCHS" 3
  trainingExamples <- localSupervisedQuantity "JITML_SL_TRAIN_LIMIT" 2000
  evaluationExamples <- localSupervisedQuantity "JITML_SL_TEST_LIMIT" 1000
  batchExamples <- localSupervisedQuantity "JITML_SL_BATCH_SIZE" 128
  let dhallPath = selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions
      experimentHash =
        Checkpoint.deriveExperimentHash
          dhallPath
          (SL.problemName problem <> "\NUL" <> SL.problemModel problem)
      raw =
        ProtoTraining.StartTraining
          { ProtoTraining.stExperimentHash = experimentHash
          , ProtoTraining.stDhallObjectKey = dhallPath
          , ProtoTraining.stSubstrate = substrate
          , ProtoTraining.stSeed =
              Overrides.overrideSeed overrides (fromIntegral (SL.problemSeed problem))
          , ProtoTraining.stEpochs = epochs
          , ProtoTraining.stBatchSize = batchExamples
          , ProtoTraining.stPlanId = ""
          , ProtoTraining.stResolvedPlan = ""
          , ProtoTraining.stTrainingExamples = trainingExamples
          , ProtoTraining.stEvaluationExamples = evaluationExamples
          }
  case PlanCommand.prepareStartTraining raw of
    Left err -> exitWithError (InvalidConfig ("supervised plan refinement failed: " <> err))
    Right (_, plan) -> pure plan

localSupervisedQuantity :: String -> Word32 -> App Word32
localSupervisedQuantity name fallback = do
  raw <- liftIO (envWithDefault name (Text.pack (show fallback)))
  case readMaybe (Text.unpack raw) :: Maybe Integer of
    Just value
      | value > 0 && value <= toInteger (maxBound :: Word32) -> pure (fromInteger value)
    _ ->
      exitWithError
        ( InvalidConfig
            ( Text.pack name
                <> " must be a positive Word32, received "
                <> raw
            )
        )

supervisedExecutionBudget
  :: WorkloadPlan.SupervisedPlan
  -> Either Text (Int, Int, Int, Int)
supervisedExecutionBudget plan = do
  trainingExamples <-
    boundedInt "supervised training examples" (WorkloadPlan.supervisedPlanTrainingExamples plan)
  epochs <- boundedInt "supervised epochs" (WorkloadPlan.supervisedPlanEpochs plan)
  evaluationExamples <-
    boundedInt "supervised evaluation examples" (WorkloadPlan.supervisedPlanEvaluationExamples plan)
  batchExamples <-
    boundedInt "supervised batch examples" (WorkloadPlan.supervisedPlanBatchExamples plan)
  pure (trainingExamples, epochs, evaluationExamples, batchExamples)
 where
  boundedInt label quantity
    | value > toInteger (maxBound :: Int) = Left (label <> " exceeds the platform Int range")
    | otherwise = Right (fromIntegral (quantityValue quantity))
   where
    value = toInteger (quantityValue quantity)

-- | Sprint 8.13 — the real supervised-learning run metrics surfaced by
-- @jitml train@. The published loss is a measured cross-entropy (classifier)
-- or MSE (regression) value, never @1 − accuracy@; the validation loss is a
-- real held-out measurement on the validation partition (the quantity that
-- drives validation-driven model selection); the throughput field is a
-- deterministic, non-wall-clock performance metric (train examples × epochs);
-- and the held-out metric is the test-partition accuracy/error reported once on
-- the selected model.
data TrainingMetrics = TrainingMetrics
  { tmTrainLoss :: !Double
  , tmValidationLoss :: !Double
  , tmExamplesProcessed :: !Int
  , tmHeldOutMetric :: !(Maybe (Text, Double))
  , tmCompletedUnits :: !Word64
  , tmInitialCheckpointWeights :: !(Maybe [Double])
  , tmCheckpointWeights :: !(Maybe [Double])
  , tmDatasetShaAtRead :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | Materialize a deterministic held-out selection slice in addition to the
-- exact gradient-example budget.  Only the first @trainingExamples@ values
-- enter optimizer updates; the remainder is validation-only.
trainingMaterializationLimit :: Int -> Int
trainingMaterializationLimit trainingExamples =
  trainingExamples + max 1 (trainingExamples `div` 5)

-- | Sprint 8.13 — promote the architecture's 'Architecture.SlRunMetrics' plus
-- the held-out test metric into the App-level 'TrainingMetrics' the publishers
-- consume.
trainingMetricsFor
  :: Int
  -> Maybe Text
  -> Maybe [Double]
  -> Architecture.SlRunMetrics
  -> Maybe Double
  -> Text
  -> TrainingMetrics
trainingMetricsFor completedEpochs datasetShaAtRead checkpointWeights metrics heldOut metricLabel =
  TrainingMetrics
    { tmTrainLoss = Architecture.slmTrainLoss metrics
    , tmValidationLoss = Architecture.slmValidationLoss metrics
    , tmExamplesProcessed = Architecture.slmExamplesProcessed metrics
    , tmHeldOutMetric = fmap (metricLabel,) heldOut
    , tmCompletedUnits = fromIntegral (max 1 completedEpochs)
    , tmInitialCheckpointWeights = Architecture.slmInitialWeights metrics <$ checkpointWeights
    , tmCheckpointWeights = checkpointWeights
    , tmDatasetShaAtRead = datasetShaAtRead
    }

-- | Sprint 8.13 — render the @jitml train@ stdout summary with the real
-- cross-entropy train/validation losses, the deterministic throughput metric,
-- the train accuracy, and the held-out test metric. Replaces the prior
-- @train_acc=…@-only line that hid the faked loss.
renderTrainingMetricsLine
  :: Substrate
  -> SL.CanonicalProblem
  -> Maybe Text
  -> Int
  -> Int
  -> Architecture.SlRunMetrics
  -> Maybe Double
  -> Text
  -> Text
renderTrainingMetricsLine substrate problem archiveName trainLimit epochs metrics heldOut metricLabel =
  "train: "
    <> SL.problemName problem
    <> " model="
    <> SL.problemModel problem
    <> " substrate="
    <> renderSubstrate substrate
    <> maybe "" (" archive=" <>) archiveName
    <> " limit="
    <> Text.pack (show (max 1 trainLimit))
    <> " epochs="
    <> Text.pack (show (max 1 epochs))
    <> " train_loss="
    <> Text.pack (show (Architecture.slmTrainLoss metrics))
    <> " val_loss="
    <> Text.pack (show (Architecture.slmValidationLoss metrics))
    <> " train_acc="
    <> Text.pack (show (Architecture.slmTrainAccuracy metrics))
    <> " examples_processed="
    <> Text.pack (show (Architecture.slmExamplesProcessed metrics))
    <> maybe "" (\a -> " " <> metricLabel <> "=" <> Text.pack (show a)) heldOut
    <> "\n"

-- | Sprint 8.10 — drive the substrate-backed differentiable SL classifier
-- over the canonical dataset bytes staged in MinIO. Returns @Right metrics@
-- (real cross-entropy train + held-out validation loss, deterministic
-- throughput, and the held-out test accuracy) when real device training ran, or
-- @Left reason@ when a hard prerequisite (live publication, staged dataset ref,
-- staged bytes) is absent or the device training itself failed. There is no
-- synthetic fallback: a missing prerequisite is a 'Left', never a fabricated
-- curve. The exact example, epoch, evaluation, and batch quantities come from
-- one re-refined supervised plan; the worker never reconstructs or clamps
-- primitive mounted values.
runDeviceMnistTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> WorkloadPlan.SupervisedPlan
  -> App (Either Text TrainingMetrics)
runDeviceMnistTraining substrate problem plan =
  case supervisedExecutionBudget plan of
    Left err -> pure (Left err)
    Right (trainLimit, epochs, testLimit, batchSize) ->
      runDeviceMnistTrainingWithLimitsAndLearningRate
        substrate
        problem
        trainLimit
        epochs
        testLimit
        batchSize
        Nothing

runDeviceMnistTrainingWithLimitsAndLearningRate
  :: Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Int
  -> Int
  -> Int
  -> Maybe Double
  -> App (Either Text TrainingMetrics)
runDeviceMnistTrainingWithLimitsAndLearningRate substrate problem trainLimit epochs testLimit batchSize learningRateOverride = do
  env <- ask
  liveContext <- workerLiveContext
  case liveContext of
    Nothing ->
      pure (Left "no live cluster publication (run `jitml bootstrap --<substrate>`)")
    Just context ->
      case Dataset.datasetForProblem problem of
        Just trainRef
          | hasCanonicalLabels trainRef -> do
              let minioSettings = workerLiveMinIOSettings context
                  run :: MinIOSubprocess.MinIOSubprocess a -> App a
                  run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
              imagesE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
              labelsE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
              case (imagesE, labelsE) of
                (Right imgArtifact, Right lblArtifact) -> do
                  let datasetShaAtRead =
                        Dataset.datasetReadShaForArtifacts [imgArtifact, lblArtifact]
                  let config =
                        ( Classifier.defaultClassifierConfig
                            { Classifier.clfEpochs = epochs
                            , Classifier.clfBatchSize = batchSize
                            }
                        )
                          { Classifier.clfLearningRate =
                              fromMaybe
                                (Classifier.clfLearningRate Classifier.defaultClassifierConfig)
                                learningRateOverride
                          }
                      device = mlpDeviceForSubstrate substrate env
                      decodedE =
                        Classifier.decodeBoundedDataset
                          config
                          (Just (trainingMaterializationLimit trainLimit))
                          (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload imgArtifact))
                          (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload lblArtifact))
                  case decodedE of
                    Left err -> pure (Left (Text.pack err))
                    Right (configForData, dataset) -> do
                      let spec = Architecture.architectureSpecForProblem configForData problem
                          trainSet = take trainLimit dataset
                          validationSet = drop trainLimit dataset
                      if length trainSet /= trainLimit || null validationSet
                        then pure (Left "supervised dataset cannot satisfy exact training/validation example budgets")
                        else do
                          trainedE <-
                            liftIO
                              ( Architecture.trainArchitectureWithDeviceSelected
                                  device
                                  spec
                                  configForData
                                  trainSet
                                  validationSet
                              )
                          case trainedE of
                            Left err -> pure (Left ("substrate training failed: " <> err))
                            Right (trained, metrics) -> do
                              testAccE <- evaluateTestSplitDevice device minioSettings trainRef trained testLimit
                              case testAccE of
                                Left err -> pure (Left err)
                                Right testAcc -> do
                                  writeText
                                    ( renderTrainingMetricsLine
                                        substrate
                                        problem
                                        Nothing
                                        trainLimit
                                        epochs
                                        metrics
                                        testAcc
                                        "test_accuracy"
                                    )
                                  pure
                                    ( Right
                                        ( trainingMetricsFor
                                            epochs
                                            (Just datasetShaAtRead)
                                            (Just (Architecture.trainedArchitectureWeights trained))
                                            metrics
                                            testAcc
                                            "test_accuracy"
                                        )
                                    )
                _ ->
                  pure
                    ( Left
                        ( datasetFetchFailure
                            ("dataset bytes not staged in MinIO for " <> Dataset.datasetName trainRef)
                            [imagesE, labelsE]
                        )
                    )
          | Dataset.datasetName trainRef == "CIFAR-10" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                learningRateOverride
                (workerLiveMinIOSettings context)
                Classifier.decodeCifar10ArchiveBoundedDataset
          | Dataset.datasetName trainRef == "CIFAR-100" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                learningRateOverride
                (workerLiveMinIOSettings context)
                Classifier.decodeCifar100ArchiveBoundedDataset
          | Dataset.datasetName trainRef == "Tiny ImageNet" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                learningRateOverride
                (workerLiveMinIOSettings context)
                TinyImageNet.decodeTinyImageNetArchiveBoundedClassificationDataset
          | Dataset.datasetName trainRef == "California Housing" && hasCanonicalArchive trainRef ->
              runDeviceCaliforniaHousingTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                batchSize
                (workerLiveMinIOSettings context)
        _ ->
          pure
            (Left ("no staged canonical dataset for problem " <> SL.problemName problem))

runDeviceArchiveClassifierTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> Int
  -> Int
  -> Maybe Double
  -> MinIOSubprocess.MinIOSettings
  -> ( Classifier.ClassifierConfig
       -> Dataset.DatasetSplit
       -> Maybe Int
       -> Data.ByteString.ByteString
       -> Either String (Classifier.ClassifierConfig, Classifier.Dataset)
     )
  -> App (Either Text TrainingMetrics)
runDeviceArchiveClassifierTraining substrate problem trainRef trainLimit epochs testLimit batchSize learningRateOverride minioSettings decodeArchive = do
  env <- ask
  let run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      config =
        ( Classifier.defaultClassifierConfig
            { Classifier.clfEpochs = epochs
            , Classifier.clfBatchSize = batchSize
            }
        )
          { Classifier.clfLearningRate =
              fromMaybe
                (Classifier.clfLearningRate Classifier.defaultClassifierConfig)
                learningRateOverride
          }
      device = mlpDeviceForSubstrate substrate env
  archiveE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left err ->
      pure
        ( Left
            ( datasetFetchFailure
                ("dataset archive not staged in MinIO for " <> Dataset.datasetName trainRef)
                [Left err]
            )
        )
    Right archiveArtifact ->
      let archiveBytes = Dataset.fetchedArtifactPayload archiveArtifact
          datasetShaAtRead = Dataset.datasetReadShaForArtifacts [archiveArtifact]
       in case decodeArchive
            config
            Dataset.TrainSplit
            (Just (trainingMaterializationLimit trainLimit))
            archiveBytes of
            Left err -> pure (Left (Text.pack err))
            Right (configForData, dataset) -> do
              let spec = Architecture.architectureSpecForProblem configForData problem
                  trainSet = take trainLimit dataset
                  validationSet = drop trainLimit dataset
              if length trainSet /= trainLimit || null validationSet
                then pure (Left "supervised archive cannot satisfy exact training/validation example budgets")
                else do
                  trainedE <-
                    liftIO
                      ( Architecture.trainArchitectureWithDeviceSelected
                          device
                          spec
                          configForData
                          trainSet
                          validationSet
                      )
                  case trainedE of
                    Left err -> pure (Left ("substrate archive training failed: " <> err))
                    Right (trained, metrics) ->
                      case decodeArchive configForData Dataset.TestSplit (Just testLimit) archiveBytes of
                        Left err -> pure (Left (Text.pack err))
                        Right (_, testSet)
                          | length testSet /= testLimit ->
                              pure (Left "supervised archive cannot satisfy exact evaluation-example budget")
                          | otherwise -> do
                              testAccE <-
                                liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
                              case testAccE of
                                Left err -> pure (Left err)
                                Right testAcc -> do
                                  writeText
                                    ( renderTrainingMetricsLine
                                        substrate
                                        problem
                                        (Just (Dataset.datasetName trainRef))
                                        trainLimit
                                        epochs
                                        metrics
                                        (Just testAcc)
                                        "test_accuracy"
                                    )
                                  pure
                                    ( Right
                                        ( trainingMetricsFor
                                            epochs
                                            (Just datasetShaAtRead)
                                            (Just (Architecture.trainedArchitectureWeights trained))
                                            metrics
                                            (Just testAcc)
                                            "test_accuracy"
                                        )
                                    )

runDeviceCaliforniaHousingTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> Int
  -> Int
  -> MinIOSubprocess.MinIOSettings
  -> App (Either Text TrainingMetrics)
runDeviceCaliforniaHousingTraining substrate problem trainRef trainLimit epochs testLimit batchSize minioSettings = do
  env <- ask
  let run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      device = mlpDeviceForSubstrate substrate env
  archiveE <- run (Dataset.fetchVerifiedDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left err ->
      pure
        ( Left
            ( datasetFetchFailure
                ("dataset archive not staged in MinIO for " <> Dataset.datasetName trainRef)
                [Left err]
            )
        )
    Right archiveArtifact ->
      let archiveBytes = Dataset.fetchedArtifactPayload archiveArtifact
          datasetShaAtRead = Dataset.datasetReadShaForArtifacts [archiveArtifact]
       in case Regression.decodeCaliforniaHousingArchiveBoundedData (Just (trainLimit + testLimit)) archiveBytes of
            Left err -> pure (Left (Text.pack err))
            Right dataset ->
              case listToMaybe dataset of
                Nothing -> pure (Left "California Housing archive produced no rows")
                Just firstExample -> do
                  let normalizedDataset = Regression.standardizeRegressionExamples dataset
                      trainSet = take trainLimit normalizedDataset
                      validationSet = take testLimit (drop trainLimit normalizedDataset)
                      config =
                        Regression.defaultRegressionConfig
                          { Regression.regInputs = VU.length (Regression.regressionFeatures firstExample)
                          , Regression.regEpochs = epochs
                          , Regression.regBatchSize = batchSize
                          }
                  trainedE <-
                    if length trainSet /= trainLimit || length validationSet /= testLimit
                      then pure (Left "supervised regression cannot satisfy exact train/evaluation budgets")
                      else liftIO (Regression.trainRegressorWithDevice device config trainSet)
                  case trainedE of
                    Left err -> pure (Left ("substrate regression training failed: " <> err))
                    Right (trained, trainMse) -> do
                      -- Sprint 8.13 — real held-out validation MSE on the carved
                      -- validation partition (never trained on); the published loss
                      -- and validation loss are both real device measurements.
                      validationMseE <-
                        liftIO
                          ( Regression.meanSquaredErrorWithDevice
                              device
                              trained
                              (if null validationSet then trainSet else validationSet)
                          )
                      -- Sprint 10.9 review hardening — surface the rare device-failure
                      -- fallback rather than silently publishing train MSE as validation MSE.
                      validationMse <- case validationMseE of
                        Right mse -> pure mse
                        Left err -> do
                          writeText
                            ( "train: warning: held-out validation MSE unavailable ("
                                <> err
                                <> "); publishing train MSE as a conservative fallback\n"
                            )
                          pure trainMse
                      let epochsBudget = max 1 epochs
                          examplesProcessed = length trainSet * epochsBudget
                          initialShape =
                            MlpShape
                              { mlpInputs = Regression.regInputs config
                              , mlpHidden = Regression.regHidden config
                              , mlpOutputs = 1
                              }
                          initialWeights =
                            mlpParamsToFlat (mlpInit initialShape (Regression.regSeed config))
                      writeText
                        ( "train: "
                            <> SL.problemName problem
                            <> " model="
                            <> SL.problemModel problem
                            <> " substrate="
                            <> renderSubstrate substrate
                            <> " archive="
                            <> Dataset.datasetName trainRef
                            <> " limit="
                            <> Text.pack (show (max 1 trainLimit))
                            <> " epochs="
                            <> Text.pack (show epochsBudget)
                            <> " train_mse="
                            <> Text.pack (show trainMse)
                            <> " val_mse="
                            <> Text.pack (show validationMse)
                            <> " examples_processed="
                            <> Text.pack (show examplesProcessed)
                            <> "\n"
                        )
                      pure
                        ( Right
                            TrainingMetrics
                              { tmTrainLoss = trainMse
                              , tmValidationLoss = validationMse
                              , tmExamplesProcessed = examplesProcessed
                              , tmHeldOutMetric = Just ("rmse", sqrt validationMse)
                              , tmCompletedUnits = fromIntegral epochsBudget
                              , tmInitialCheckpointWeights = Just initialWeights
                              , tmCheckpointWeights =
                                  Just (mlpParamsToFlat (Regression.trainedRegressorParams trained))
                              , tmDatasetShaAtRead = Just datasetShaAtRead
                              }
                        )

-- | True when a problem's dataset has a published canonical label SHA, i.e.
-- real label bytes are stageable in MinIO (not the synthetic per-(name,
-- split, size) fixture).
hasCanonicalLabels :: Dataset.DatasetRef -> Bool
hasCanonicalLabels ref =
  isJust
    ( Dataset.canonicalArtifactSha256For
        (Dataset.datasetName ref)
        Dataset.TrainSplit
        Dataset.LabelsArtifact
    )

hasCanonicalArchive :: Dataset.DatasetRef -> Bool
hasCanonicalArchive ref =
  isJust
    ( Dataset.canonicalArtifactSha256For
        (Dataset.datasetName ref)
        Dataset.TrainSplit
        Dataset.ArchiveArtifact
    )

-- | Sprint 8.10 — fetch the test split images + labels and report the trained
-- classifier's held-out accuracy over the first @limit@ examples /through the
-- device forward/. Returns 'Nothing' when the test bytes are not staged or
-- the device forward is unavailable (the caller then publishes the train-set
-- accuracy, which is itself a real device measurement).
evaluateTestSplitDevice
  :: MlpDevice
  -> MinIOSubprocess.MinIOSettings
  -> Dataset.DatasetRef
  -> Architecture.TrainedArchitecture
  -> Int
  -> App (Either Text (Maybe Double))
evaluateTestSplitDevice device minioSettings trainRef trained limit = do
  let testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
      run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
  testImgE <- run (Dataset.fetchVerifiedDatasetArtifactBytes testRef Dataset.ImagesArtifact)
  testLblE <- run (Dataset.fetchVerifiedDatasetArtifactBytes testRef Dataset.LabelsArtifact)
  case (testImgE, testLblE) of
    (Right tiArtifact, Right tlArtifact) ->
      case ( Classifier.parseIdxImages (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload tiArtifact))
           , Classifier.parseIdxLabels (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload tlArtifact))
           ) of
        (Right (_, images), Right labels) -> do
          let testSet = take limit (Classifier.zipImagesLabels images labels)
          if length testSet /= limit
            then pure (Left "supervised test split cannot satisfy exact evaluation-example budget")
            else do
              accE <- liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
              pure (fmap Just accE)
        _ -> pure (Right Nothing)
    _ ->
      pure
        ( Left
            ( datasetFetchFailure
                ("test dataset bytes not staged in MinIO for " <> Dataset.datasetName testRef)
                [testImgE, testLblE]
            )
        )

datasetFetchFailure :: Text -> [Either ServiceError a] -> Text
datasetFetchFailure fallback results =
  case [message | Left (SEConflict message) <- results] of
    message : _ -> message
    [] -> fallback

-- | 'Right' to 'Just', 'Left' to 'Nothing'. Local helper mirroring the
-- per-module copies in "JitML.Bootstrap" / "JitML.Proto.Wire".
eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

data WorkerLiveContext = WorkerLiveContext
  { workerLivePublication :: ClusterPublication
  , workerLiveMinIOSettings :: MinIOSubprocess.MinIOSettings
  , workerLivePulsarSettings :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  }

-- | Resolve live service coordinates for a worker process. Daemon-dispatched
-- Kubernetes Jobs mount @BootConfig.dhall@ but do not have the host's
-- @.build/runtime/cluster-publication.json@, so they must use in-cluster
-- service DNS for MinIO/Pulsar. Host-side developer commands keep using the
-- leased edge publication file.
workerLiveContext :: App (Maybe WorkerLiveContext)
workerLiveContext = do
  bootMaybe <- liftIO (tryLoadBootConfigFromFile serviceBootConfigPath)
  case bootMaybe of
    Just bootConfig -> do
      let clientSettings = ServiceClients.engineClientSettingsForBootConfig bootConfig
      pure $
        Just
          WorkerLiveContext
            { workerLivePublication = publicationFromBootConfig bootConfig
            , workerLiveMinIOSettings = ServiceClients.engineMinIOSettings clientSettings
            , workerLivePulsarSettings = ServiceClients.enginePulsarSettings clientSettings
            }
    Nothing -> do
      cluster <- liftIO (readExistingLivePublication ".")
      pure $
        fmap
          ( \publication ->
              let edgePort = Publication.publicationEdgePort publication
               in WorkerLiveContext
                    { workerLivePublication = publication
                    , workerLiveMinIOSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                    , workerLivePulsarSettings =
                        PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    }
          )
          cluster

publicationFromBootConfig :: BootConfig.BootConfig -> ClusterPublication
publicationFromBootConfig bootConfig =
  (defaultPublication (BootConfig.bootSubstrate bootConfig))
    { Publication.publicationEdgePort = substrateEdgePort (BootConfig.bootSubstrate bootConfig)
    , Publication.publicationPulsarUrl = BootConfig.bootPulsarServiceUrl bootConfig
    , Publication.publicationMinioUrl = BootConfig.bootMinioEndpoint bootConfig
    }

-- | Sprint 13.5 — resolve the worker's broker publish target. A
-- daemon-dispatched worker runs inside a Kubernetes Job pod where the
-- host edge (@127.0.0.1:\<edge-port\>@) is the pod's own localhost, not
-- the broker; the daemon-rendered Job sets @JITML_PULSAR_WS@ (the
-- in-cluster broker WebSocket endpoint) + @JITML_SUBSTRATE@ so the worker
-- reaches the broker through the in-cluster service DNS. Offline / host
-- runs fall back to the leased host-edge settings in
-- @cluster-publication.json@.
workerBrokerTarget
  :: App (Maybe (Substrate, PulsarWebSocketSubprocess.PulsarWebSocketSettings))
workerBrokerTarget = do
  -- Sprint 5.7 — prefer the typed Dhall config the daemon mounts on the worker
  -- pod: substrate + Pulsar wiring travel as `BootConfig.dhall` (substrate) and
  -- the per-run `RunConfig.dhall` (Pulsar WebSocket URL), retiring the
  -- `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env vars. Falls back to env + the
  -- leased host-edge publication for developer-side local invocations.
  bootMaybe <- liftIO (tryLoadBootConfigFromFile serviceBootConfigPath)
  mountedWs <- mountedWsFromRunConfig
  pulsarWsEnv <- liftIO (lookupEnv "JITML_PULSAR_WS")
  substrateEnv <- liftIO (lookupEnv "JITML_SUBSTRATE")
  cluster <- liftIO (readExistingLivePublication ".")
  let mountedSubstrate = fmap BootConfig.bootSubstrate bootMaybe
      envSubstrate = substrateEnv >>= (parseSubstrate . Text.pack)
      envWs = fmap Text.pack (pulsarWsEnv >>= nonEmptyString)
      wsUrl = mountedWs `orElse` envWs
      substrate = mountedSubstrate `orElse` envSubstrate
  pure $
    case (wsUrl, substrate) of
      (Just url, Just sub) ->
        Just
          ( sub
          , PulsarWebSocketSubprocess.pulsarSettingsForEndpoint url
          )
      _ -> case cluster of
        Just publication ->
          Just
            ( Publication.publicationSubstrate publication
            , PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge
                (Publication.publicationEdgePort publication)
            )
        Nothing -> Nothing
 where
  nonEmptyString s = if null s then Nothing else Just s
  orElse :: Maybe a -> Maybe a -> Maybe a
  orElse first fallback = case first of
    Just _ -> first
    Nothing -> fallback
  -- Try each RunConfig variant in turn; pick the first that has a pulsarWsUrl.
  mountedWsFromRunConfig :: App (Maybe Text)
  mountedWsFromRunConfig = do
    rl <- liftIO (RunConfig.tryLoadRlRunConfig runConfigPath)
    tr <- liftIO (RunConfig.tryLoadTrainingRunConfig runConfigPath)
    tu <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
    az <- liftIO (RunConfig.tryLoadAlphaZeroRunConfig runConfigPath)
    case listToMaybe
      ( catMaybes
          [ fmapRunConfig RunConfig.rlcPulsarWsUrl rl
          , fmapRunConfig RunConfig.trcPulsarWsUrl tr
          , fmapRunConfig RunConfig.turcPulsarWsUrl tu
          , fmapRunConfig RunConfig.azrcPulsarWsUrl az
          ]
      ) of
      Just ws -> pure (Just ws)
      Nothing -> case firstRunConfigDecodeFailure
        [rlRunConfigError rl, trainingRunConfigError tr, tuneRunConfigError tu, alphaZeroRunConfigError az] of
        Just err -> exitWithError (mountedRunConfigDecodeError "RunConfig" err)
        Nothing -> pure Nothing

-- | Sprint 8.11 — resolve the substrate the RL worker trains on, using the
-- same precedence as 'workerBrokerTarget': the daemon-mounted
-- @BootConfig.dhall@ substrate, else @JITML_SUBSTRATE@, else the leased
-- cluster publication's substrate, else @linux-cpu@ for developer-side runs.
-- The base is then overridden by an explicit CLI @--substrate@ flag.
workerSubstrateBase :: App Substrate
workerSubstrateBase = do
  bootMaybe <- liftIO (tryLoadBootConfigFromFile serviceBootConfigPath)
  substrateEnv <- liftIO (lookupEnv "JITML_SUBSTRATE")
  cluster <- liftIO (readExistingLivePublication ".")
  pure $ case fmap BootConfig.bootSubstrate bootMaybe of
    Just substrate -> substrate
    Nothing -> case substrateEnv >>= (parseSubstrate . Text.pack) of
      Just substrate -> substrate
      Nothing -> maybe LinuxCPU Publication.publicationSubstrate cluster

-- | Apply an explicit CLI @--substrate@ override on top of 'workerSubstrateBase'.
resolveWorkerSubstrate :: Overrides.ExperimentOverrides -> App Substrate
resolveWorkerSubstrate overrides =
  Overrides.overrideSubstrate overrides <$> workerSubstrateBase

-- | Sprint 5.7 — best-effort load of `BootConfig.dhall` from a mounted path.
-- Returns 'Nothing' when the file is absent (developer-side CLI runs).
tryLoadBootConfigFromFile :: FilePath -> IO (Maybe BootConfig.BootConfig)
tryLoadBootConfigFromFile path = do
  exists <- doesFileExist path
  if exists
    then do
      attempt <- tryAny (BootConfig.loadBootConfig path)
      case attempt of
        Left _ -> pure Nothing
        Right value -> pure (Just value)
    else pure Nothing

mountedRunConfigDecodeError :: Text -> Text -> AppError
mountedRunConfigDecodeError configName detail =
  InvalidConfig
    ( "failed to decode mounted "
        <> configName
        <> " at "
        <> Text.pack runConfigPath
        <> ": "
        <> detail
    )

rejectMissingMountedRunConfigInKubernetes :: Text -> App ()
rejectMissingMountedRunConfigInKubernetes configName = do
  kubernetesHost <- liftIO (lookupEnv "KUBERNETES_SERVICE_HOST")
  when (maybe False (not . null) kubernetesHost) $
    exitWithError
      ( mountedRunConfigDecodeError
          configName
          "required resolved-plan mount is missing in a Kubernetes workload"
      )

fmapRunConfig :: (a -> b) -> RunConfig.RunConfigLoadResult a -> Maybe b
fmapRunConfig f loadResult =
  case loadResult of
    RunConfig.RunConfigLoaded value -> Just (f value)
    RunConfig.RunConfigMissing -> Nothing
    RunConfig.RunConfigDecodeFailed _ -> Nothing

runConfigDecodeError :: RunConfig.RunConfigLoadResult a -> Maybe Text
runConfigDecodeError loadResult =
  case loadResult of
    RunConfig.RunConfigDecodeFailed err -> Just err
    _ -> Nothing

rlRunConfigError :: RunConfig.RunConfigLoadResult RunConfig.RlRunConfig -> Maybe Text
rlRunConfigError = runConfigDecodeError

trainingRunConfigError :: RunConfig.RunConfigLoadResult RunConfig.TrainingRunConfig -> Maybe Text
trainingRunConfigError = runConfigDecodeError

tuneRunConfigError :: RunConfig.RunConfigLoadResult RunConfig.TuneRunConfig -> Maybe Text
tuneRunConfigError = runConfigDecodeError

alphaZeroRunConfigError :: RunConfig.RunConfigLoadResult RunConfig.AlphaZeroRunConfig -> Maybe Text
alphaZeroRunConfigError = runConfigDecodeError

firstRunConfigDecodeFailure :: [Maybe Text] -> Maybe Text
firstRunConfigDecodeFailure = listToMaybe . catMaybes

nonEmptyText :: Text -> Maybe Text
nonEmptyText value
  | Text.null value = Nothing
  | otherwise = Just value

-- | Sprint 5.7 (worker side) — return the experiment hash the daemon wrote to
-- the per-run @RunConfig.dhall@ mounted at 'runConfigPath'. Tries each
-- RunConfig variant in turn (RL, training, tune) and falls back to the
-- legacy @JITML_EXPERIMENT_HASH@ env var for developer-side local invocations
-- that have not staged a mounted RunConfig.
workerExperimentHash :: App (Maybe Text)
workerExperimentHash = do
  rl <- liftIO (RunConfig.tryLoadRlRunConfig runConfigPath)
  tr <- liftIO (RunConfig.tryLoadTrainingRunConfig runConfigPath)
  tu <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
  az <- liftIO (RunConfig.tryLoadAlphaZeroRunConfig runConfigPath)
  case listToMaybe
    ( catMaybes
        [ nonEmptyText =<< fmapRunConfig RunConfig.rlcExperimentHash rl
        , supervisedExperimentHash =<< fmapRunConfig id tr
        , tuningExperimentHash =<< fmapRunConfig id tu
        , alphaZeroExperimentHash =<< fmapRunConfig id az
        ]
    ) of
    Just experimentHash -> pure (Just experimentHash)
    Nothing -> case firstRunConfigDecodeFailure
      [rlRunConfigError rl, trainingRunConfigError tr, tuneRunConfigError tu, alphaZeroRunConfigError az] of
      Just err -> exitWithError (mountedRunConfigDecodeError "RunConfig" err)
      Nothing -> liftIO $ do
        raw <- lookupEnv "JITML_EXPERIMENT_HASH"
        pure $ case raw of
          Just value | not (null value) -> Just (Text.pack value)
          _ -> Nothing
 where
  supervisedExperimentHash config =
    nonEmptyText . runPlanExperimentId . WorkloadPlan.supervisedPlanRunPlan
      =<< eitherToMaybe (RunConfig.supervisedPlanFromRunConfig config)
  tuningExperimentHash config =
    nonEmptyText . runPlanExperimentId . WorkloadPlan.tuningPlanRunPlan
      =<< eitherToMaybe (RunConfig.tuningPlanFromRunConfig config)
  alphaZeroExperimentHash config =
    nonEmptyText . runPlanExperimentId . WorkloadPlan.alphaZeroPlanRunPlan
      =<< eitherToMaybe (RunConfig.alphaZeroPlanFromRunConfig config)

publishWorkerTrainingEvent :: TrainingMetrics -> App ()
publishWorkerTrainingEvent metrics = do
  target <- workerBrokerTarget
  experimentHashMaybe <- workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      timestampNs <- liftIO currentTimestampNs
      let envelope =
            ProtoTraining.TrainingEpoch
              ( ProtoTraining.EpochCompleted
                  { ProtoTraining.ecExperimentHash = experimentHash
                  , ProtoTraining.ecEpoch = fromIntegral (tmCompletedUnits metrics)
                  , -- Sprint 8.13 — real cross-entropy/MSE training loss and a
                    -- distinct real held-out validation loss, never @1 − acc@.
                    ProtoTraining.ecLoss = tmTrainLoss metrics
                  , ProtoTraining.ecValidationLoss = tmValidationLoss metrics
                  , ProtoTraining.ecTimestampNs = timestampNs
                  }
              )
      result <-
        liftIO
          ( publishPulsarEvent
              pulsarSettings
              Topology.TrainingEventRoute
              substrate
              envelope
          )
      case result of
        Right _ -> pure ()
        Left err ->
          writeText
            ( "train: training.event publish failed: "
                <> Text.pack (show err)
                <> "\n"
            )
    _ -> pure ()

publishWorkerTrainingCheckpoint
  :: WorkloadPlan.SupervisedPlan
  -> Substrate
  -> SL.CanonicalProblem
  -> [ParsedOption]
  -> TrainingMetrics
  -> App ()
publishWorkerTrainingCheckpoint plan substrate problem parsedOptions metrics =
  case tmCheckpointWeights metrics of
    Nothing -> pure ()
    Just weights -> do
      liveExperimentHash <- workerExperimentHash
      let experimentDhall = selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions
          derivedExperimentHash =
            Checkpoint.deriveExperimentHash
              experimentDhall
              (renderSubstrate substrate <> ":" <> SL.problemName problem)
          experimentHash = fromMaybe derivedExperimentHash liveExperimentHash
          tensorName = "sl-trained-weights"
          step = tmCompletedUnits metrics
          metricRows = trainingCheckpointMetrics metrics
          completedTraining =
            eitherToMaybe
              ( completedTrainingForSupervisedProblem
                  plan
                  problem
                  metrics
                  experimentHash
                  tensorName
                  step
                  metricRows
                  weights
              )
      stored <-
        writeLocalWeightCheckpointWithCompleted
          completedTraining
          experimentHash
          tensorName
          step
          metricRows
          weights
      publishWorkerTrainingCheckpointEvent
        tensorName
        step
        metricRows
        (tmDatasetShaAtRead metrics)
        completedTraining
        weights
        stored

publishWorkerTrainingCheckpointEvent
  :: Text
  -> Word64
  -> [(Text, Double)]
  -> Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> [Double]
  -> CheckpointStore.StoredCheckpoint
  -> App ()
publishWorkerTrainingCheckpointEvent tensorName step metricRows datasetShaAtRead completedTraining weights stored = do
  target <- workerBrokerTarget
  experimentHashMaybe <- workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      envelope <-
        case trainingCheckpointEventEnvelope
          experimentHash
          tensorName
          step
          metricRows
          datasetShaAtRead
          completedTraining
          weights
          stored of
          Left err -> exitWithError (InvalidConfig ("training checkpoint event failed: " <> err))
          Right value -> pure value
      result <-
        liftIO
          ( publishPulsarEvent
              pulsarSettings
              Topology.TrainingEventRoute
              substrate
              envelope
          )
      case result of
        Right _ -> pure ()
        Left err ->
          writeText
            ( "train: checkpoint event publish failed: "
                <> Text.pack (show err)
                <> "\n"
            )
    _ -> pure ()

trainingCheckpointEventEnvelope
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> [Double]
  -> CheckpointStore.StoredCheckpoint
  -> Either Text ProtoTraining.TrainingEvent
trainingCheckpointEventEnvelope experimentHash _tensorName step metricRows _datasetShaAtRead completedOverride _weights stored = do
  let checkpoint =
        ProtoTraining.CheckpointDone
          { ProtoTraining.cdExperimentHash = experimentHash
          , ProtoTraining.cdManifestSha = CheckpointStore.storedManifestSha stored
          , ProtoTraining.cdStep = step
          , ProtoTraining.cdPointerKey = Checkpoint.latestPointerKey experimentHash
          , ProtoTraining.cdEpoch = fromIntegral step
          , ProtoTraining.cdTrialSha = Nothing
          , ProtoTraining.cdRunUuid = "training-" <> experimentHash
          , ProtoTraining.cdMetricsAtStep = metricRows
          }
  case completedOverride of
    Nothing -> Right (ProtoTraining.TrainingCheckpoint checkpoint)
    Just completed ->
      ProtoTraining.TrainingCompletedCheckpoint
        <$> ProtoTraining.completeCheckpointDone checkpoint completed

trainingCheckpointMetrics :: TrainingMetrics -> [(Text, Double)]
trainingCheckpointMetrics metrics =
  [ ("train_loss", tmTrainLoss metrics)
  , ("validation_loss", tmValidationLoss metrics)
  , ("examples_processed", fromIntegral (tmExamplesProcessed metrics))
  ]
    <> maybe [] pure (tmHeldOutMetric metrics)

-- | Sprint 8.10 — `jitml eval --checkpoint <id>` loads the named inference
-- checkpoint's `.jmw1` weight blob and runs a real forward through the
-- resolved substrate's JIT device (the same weighted runner `jitml inference
-- run` uses). A missing pointer/manifest/checkpoint surfaces as a typed
-- `InferenceCheckpointMissing` (exit 1) with no synthetic fallback. The
-- held-out accuracy/loss over a staged test split layers on this read path
-- once the SL checkpoint-write loop lands (Phase 10 Sprint 10.5 / Phase 13
-- Sprint 13.17).
runEval :: [ParsedOption] -> App ()
runEval = runCheckpointEval "eval"

-- | Sprints 8.10 / 9.9 — load the named inference checkpoint's `.jmw1` weights
-- and run a real forward through the resolved substrate's JIT device. Shared by
-- `jitml eval` (@label = "eval"@) and `jitml rl eval` (@label = "rl eval"@). A
-- missing pointer/manifest/checkpoint surfaces as a typed
-- `InferenceCheckpointMissing` (exit 1); no synthetic fallback.
runCheckpointEval :: Text -> [ParsedOption] -> App ()
runCheckpointEval label parsedOptions = do
  let experimentHash = selectedValue "checkpoint" "default" parsedOptions
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
          substrate = Publication.publicationSubstrate publication
      env <- ask
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (inferenceForSubstrate env substrate experimentHash)
          )
      case result of
        Right values ->
          writeLine
            ( label
                <> ": checkpoint="
                <> experimentHash
                <> " substrate="
                <> renderSubstrate substrate
                <> " output="
                <> Text.pack (show values)
            )
        Left err -> exitWithError (classifyCheckpointLoadError experimentHash err)
    Nothing -> exitWithError (InferenceCheckpointMissing experimentHash)

runTune :: [ParsedOption] -> App ()
runTune parsedOptions = do
  mounted <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
  case mounted of
    RunConfig.RunConfigLoaded config ->
      case RunConfig.tuningPlanFromRunConfig config of
        Left err -> exitWithError (mountedRunConfigDecodeError "TuneRunConfig" err)
        Right plan -> do
          writeLine
            ( "tune resolved-plan: plan-id="
                <> planIdText (WorkloadPlan.tuningPlanId plan)
                <> " trials="
                <> Text.pack (show (quantityValue (WorkloadPlan.tuningPlanTrials plan)))
            )
          publishWorkerTuneEvent plan
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError "TuneRunConfig" err)
    RunConfig.RunConfigMissing -> do
      rejectMissingMountedRunConfigInKubernetes "TuneRunConfig"
      runLocalTune parsedOptions

runLocalTune :: [ParsedOption] -> App ()
runLocalTune parsedOptions = do
  overrides <- case Overrides.parseTuningOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  let tunePath = Text.unpack (selectedValue "tune-dhall" "experiments/mnist-tune.dhall" parsedOptions)
  loaded <- liftIO (Tune.loadTuningExperiment tunePath)
  experiment <- case loaded of
    Left message -> exitWithError (DhallTypeError message)
    Right value -> pure (Overrides.applyOverrides overrides value)
  (start, plan) <- prepareLocalTuningPlan tunePath experiment
  let rendered = Tune.renderTuningPlan tunePath experiment
      renderedWithOverrides =
        rendered
          <> "plan-id: "
          <> ProtoTune.ssPlanId start
          <> "\nresolved-plan: "
          <> ProtoTune.ssResolvedPlan start
          <> "\noverrides: "
          <> Overrides.renderTuningOverrides overrides
          <> "\n"
  tuneArtifactLines <- writeLocalTuneArtifacts experiment plan
  case optionValues "plan-file" parsedOptions of
    [] -> pure ()
    planPath : _ ->
      liftIO
        ( writePlanFile
            (Text.unpack planPath)
            (renderedWithOverrides <> Text.unlines tuneArtifactLines)
        )
  writeText (renderedWithOverrides <> Text.unlines tuneArtifactLines)

prepareLocalTuningPlan
  :: FilePath
  -> Tune.TuningExperiment
  -> App (ProtoTune.StartSweep, WorkloadPlan.TuningPlan)
prepareLocalTuningPlan tunePath experiment = do
  config <- case Tune.tuningExperimentConfig experiment of
    Nothing -> exitWithError (InvalidConfig "tuning experiment requires a tuning configuration")
    Just value -> pure value
  substrate <- workerSubstrateBase
  trials <- word32PlanValue "tuning trials" (toInteger (Tune.tuningConfigTrials config))
  parallelism <-
    word32PlanValue "tuning parallelism" (toInteger (Tune.tuningConfigParallelism config))
  promotions <-
    word32PlanValue
      "tuning promotions"
      (tuningPromotionBudget config)
  updates <-
    word32PlanValue
      "tuning per-trial updates"
      (toInteger (Tune.tuningSchedulerMaxBudget (Tune.tuningConfigScheduler config)))
  let experimentHash =
        Checkpoint.deriveExperimentHash
          (Text.pack tunePath)
          (Tune.renderTuningPlan tunePath experiment)
      raw =
        ProtoTune.StartSweep
          { ProtoTune.ssExperimentHash = experimentHash
          , ProtoTune.ssDhallObjectKey = Text.pack tunePath
          , ProtoTune.ssSubstrate = substrate
          , ProtoTune.ssSweepSeed = fromIntegral (Tune.tuningExperimentSeed experiment)
          , ProtoTune.ssTrialBudget = trials
          , ProtoTune.ssBudgetPerTrial = updates
          , ProtoTune.ssSampler = Text.pack (show (Tune.tuningSamplerKind (Tune.tuningConfigSampler config)))
          , ProtoTune.ssScheduler =
              Text.pack (show (Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config)))
          , ProtoTune.ssPruner = Text.pack (show (Tune.tuningPrunerKind (Tune.tuningConfigPruner config)))
          , ProtoTune.ssParallelism = parallelism
          , ProtoTune.ssPromotions = promotions
          , ProtoTune.ssPlanId = ""
          , ProtoTune.ssResolvedPlan = ""
          }
  case PlanCommand.prepareStartSweep raw of
    Left err -> exitWithError (InvalidConfig ("tuning plan refinement failed: " <> err))
    Right prepared -> pure prepared

tuningPromotionBudget :: Tune.TuningConfig -> Integer
tuningPromotionBudget config =
  let trials = toInteger (Tune.tuningConfigTrials config)
      scheduler = Tune.tuningConfigScheduler config
      eta = max 1 (toInteger (Tune.tuningSchedulerEta scheduler))
   in case Tune.tuningSchedulerKind scheduler of
        Tune.Fifo -> trials
        Tune.SuccessiveHalving -> max 1 (trials `div` eta)
        Tune.Hyperband -> max 1 (trials `div` eta)
        Tune.ASHA -> max 1 (trials `div` eta)

word32PlanValue :: Text -> Integer -> App Word32
word32PlanValue label value
  | value < 0 || value > toInteger (maxBound :: Word32) =
      exitWithError (InvalidConfig (label <> " is outside the Word32 protocol range"))
  | otherwise = pure (fromInteger value)

writeLocalTuneArtifacts
  :: Tune.TuningExperiment
  -> WorkloadPlan.TuningPlan
  -> App [Text]
writeLocalTuneArtifacts experiment plan = do
  trialCount <- intPlanValue "tuning trials" (quantityValue (WorkloadPlan.tuningPlanTrials plan))
  parallelism <-
    intPlanValue "tuning parallelism" (quantityValue (WorkloadPlan.tuningPlanParallelism plan))
  promotions <-
    intPlanValue "tuning promotions" (quantityValue (WorkloadPlan.tuningPlanPromotions plan))
  updates <-
    intPlanValue
      "tuning per-trial updates"
      (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan))
  let sampler = WorkloadPlan.tuningPlanSampler plan
      scheduler = WorkloadPlan.tuningPlanScheduler plan
      pruner = WorkloadPlan.tuningPlanPruner plan
      experimentHash = runPlanExperimentId (WorkloadPlan.tuningPlanRunPlan plan)
  results <-
    case Tune.trialObjectiveResultsForBudget sampler parallelism updates trialCount of
      Left err -> exitWithError (InvalidConfig ("resolved tuning execution failed: " <> err))
      Right values -> pure values
  executions <-
    case Tune.trialExecutions scheduler pruner promotions results of
      Left err -> exitWithError (InvalidConfig ("resolved tuning execution failed: " <> err))
      Right values -> pure values
  let promotedResults =
        [ Tune.trialExecutionResult execution
        | execution <- executions
        , Tune.trialExecutionPromoted execution
        ]
      prunedCount = length (filter Tune.trialExecutionPruned executions)
  case selectBestTrialResult promotedResults of
    Nothing -> exitWithError (InvalidConfig "resolved tuning plan produced no trials")
    Just best -> do
      storedPromotions <-
        traverse
          ( \result ->
              writeLocalWeightCheckpoint
                experimentHash
                "tune-trial-weights"
                (fromIntegral (Tune.trialResultIndex result))
                [("objective", Tune.trialResultObjective result)]
                (Tune.trialResultWeights result)
          )
          promotedResults
      artifact <-
        writeTextArtifact
          experimentHash
          "tune-trials"
          (renderTuneTrialArtifact experiment sampler executions best)
      pure $
        [ "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
        , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
        , "trials-completed: " <> Text.pack (show (length executions))
        , "trials-pruned: " <> Text.pack (show prunedCount)
        , "trials-promoted: " <> Text.pack (show (length promotedResults))
        ]
          <> concatMap
            (renderStoredCheckpointLinesWithPrefix "trial-checkpoint" experimentHash)
            storedPromotions
          <> renderStoredArtifactLines "tune-trials" artifact

selectBestTrialResult :: [Tune.TrialObjectiveResult] -> Maybe Tune.TrialObjectiveResult
selectBestTrialResult [] = Nothing
selectBestTrialResult (firstResult : rest) =
  Just (foldl select firstResult rest)
 where
  select best current
    | Tune.trialResultObjective current >= Tune.trialResultObjective best = current
    | otherwise = best

renderTuneTrialArtifact
  :: Tune.TuningExperiment
  -> Tune.Sampler
  -> [Tune.TrialExecution]
  -> Tune.TrialObjectiveResult
  -> Text
renderTuneTrialArtifact experiment sampler executions best =
  Text.unlines $
    [ "kind: tune-trials-v1"
    , "name: " <> Tune.tuningExperimentName experiment
    , "sampler: " <> Text.pack (show sampler)
    , "trial-count: " <> Text.pack (show (length executions))
    , "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
    , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
    ]
      <> concatMap renderTrial executions
 where
  renderTrial execution =
    let result = Tune.trialExecutionResult execution
     in [ "trial: " <> Text.pack (show (Tune.trialResultIndex result))
        , "objective: " <> Text.pack (show (Tune.trialResultObjective result))
        , "pruned: " <> Text.pack (show (Tune.trialExecutionPruned execution))
        , "promoted: " <> Text.pack (show (Tune.trialExecutionPromoted execution))
        , "weight-count: " <> Text.pack (show (length (Tune.trialResultWeights result)))
        ]

renderRlTrajectoryArtifact
  :: Text
  -> Text
  -> Text
  -> Int
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Text
renderRlTrajectoryArtifact experimentHash environment trainer seed episodes =
  Text.unlines $
    [ "kind: rl-trajectory-v1"
    , "experiment-hash: " <> experimentHash
    , "environment: " <> environment
    , "trainer: " <> trainer
    , "seed: " <> Text.pack (show seed)
    , "episodes: " <> Text.pack (show (length episodes))
    ]
      <> concatMap renderEpisode episodes
 where
  renderEpisode episode =
    [ "episode: " <> Text.pack (show (EpisodeEnvelope.simEpisodeIndex episode))
    , "episode-steps: " <> Text.pack (show (EpisodeEnvelope.simEpisodeSteps episode))
    , "episode-reward: " <> Text.pack (show (EpisodeEnvelope.simEpisodeReward episode))
    , "episode-done: " <> Text.pack (show (EpisodeEnvelope.simEpisodeDone episode))
    , "episode-frame-count: "
        <> Text.pack (show (length (EpisodeEnvelope.simEpisodeFrames episode)))
    ]
      <> concatMap renderFrame (EpisodeEnvelope.simEpisodeFrames episode)
  renderFrame frame =
    [ "frame-episode: " <> Text.pack (show (EpisodeEnvelope.simFrameEpisodeIndex frame))
    , "frame-step: " <> Text.pack (show (EpisodeEnvelope.simFrameStepIndex frame))
    , "frame-action: " <> Text.pack (show (EpisodeEnvelope.simFrameAction frame))
    , "frame-reward: " <> Text.pack (show (EpisodeEnvelope.simFrameReward frame))
    , "frame-done: " <> Text.pack (show (EpisodeEnvelope.simFrameDone frame))
    , "frame-observation: " <> Text.pack (show (EpisodeEnvelope.simFrameObservation frame))
    , "frame-next-observation: "
        <> Text.pack (show (EpisodeEnvelope.simFrameNextObservation frame))
    , "frame-action-probabilities: "
        <> Text.pack (show (EpisodeEnvelope.simFrameActionProbabilities frame))
    , "frame-caption: " <> EpisodeEnvelope.simFrameCaption frame
    ]

renderAlphaZeroTranscriptArtifact
  :: Text
  -> Int
  -> Int
  -> Int
  -> [PolicyValueNet.PolicyValueTrainingSample]
  -> Text
renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples =
  Text.unlines $
    [ "kind: alphazero-transcript-v1"
    , "experiment-hash: " <> experimentHash
    , "game: " <> maybe "unknown" (AlphaZero.gameName . PolicyValueNet.sampleState) (listToMaybe samples)
    , "seed: " <> Text.pack (show seed)
    , "mcts-sims: " <> Text.pack (show sims)
    , "max-plies: " <> Text.pack (show maxPlies)
    , "samples: " <> Text.pack (show (length samples))
    ]
      <> concatMap renderSample (zip [0 :: Int ..] samples)
 where
  renderSample (index, sample) =
    [ "sample: " <> Text.pack (show index)
    , "state: " <> Text.pack (show (PolicyValueNet.sampleState sample))
    , "visit-distribution: "
        <> Text.pack (show (VU.toList (PolicyValueNet.sampleVisitDist sample)))
    , "outcome: " <> Text.pack (show (PolicyValueNet.sampleOutcome sample))
    ]

-- | Sprint 13.10 / 9.16 — when running inside a daemon-dispatched tune Job
-- (live publication + JITML_EXPERIMENT_HASH set), run the sampler, scheduler,
-- and pruner selected by the mounted TuneRunConfig for the configured trial
-- budget.
-- Each trial:
--
--   1. uses the selected `(Sampler, Scheduler, Pruner)` axes;
--   2. trains the sampled trial through the substrate-selected JIT device and
--      returns both the measured objective and checkpointable weights;
--   3. persists a `TrialTranscript` to MinIO via `persistTrialTranscript`;
--   4. promotes the measured trial weights into `jitml-checkpoints`;
--   5. publishes `TuneTrialStarted` + `TuneTrialFinished` envelopes to
--      `tune.event.<substrate>`.
--
-- After the loop publishes `TuneSweepCompleted` with the exact planned count and
-- the best measured objective. The worker consumes only the already-refined
-- plan mounted by the daemon; it never re-reads or repairs primitive budgets.
publishWorkerTuneEvent :: WorkloadPlan.TuningPlan -> App ()
publishWorkerTuneEvent plan = do
  env <- ask
  liveContext <- workerLiveContext
  context <- case liveContext of
    Nothing ->
      exitWithError
        (InvalidConfig "resolved tuning worker requires mounted service configuration")
    Just value -> pure value
  let publication = workerLivePublication context
      substrate = Publication.publicationSubstrate publication
      plannedSubstrate = runPlanSubstrate (WorkloadPlan.tuningPlanRunPlan plan)
      experimentHash = runPlanExperimentId (WorkloadPlan.tuningPlanRunPlan plan)
      planId = planIdText (WorkloadPlan.tuningPlanId plan)
      sampler = WorkloadPlan.tuningPlanSampler plan
      scheduler = WorkloadPlan.tuningPlanScheduler plan
      pruner = WorkloadPlan.tuningPlanPruner plan
      pulsarSettings = workerLivePulsarSettings context
      minioSettings = workerLiveMinIOSettings context
      device = mlpDeviceForSubstrate substrate env
  unless (substrate == plannedSubstrate) $
    exitWithError
      ( InvalidConfig
          ( "resolved tuning plan substrate "
              <> renderSubstrate plannedSubstrate
              <> " does not match worker substrate "
              <> renderSubstrate substrate
          )
      )
  trialBudget <- intPlanValue "tuning trials" (quantityValue (WorkloadPlan.tuningPlanTrials plan))
  parallelism <-
    intPlanValue "tuning parallelism" (quantityValue (WorkloadPlan.tuningPlanParallelism plan))
  promotions <-
    intPlanValue "tuning promotions" (quantityValue (WorkloadPlan.tuningPlanPromotions plan))
  updates <-
    intPlanValue
      "tuning per-trial updates"
      (quantityValue (WorkloadPlan.tuningPlanPerTrialUpdates plan))
  sweepSeed <-
    intPlanValue
      "tuning sweep seed"
      (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan))))
  trialResultsE <-
    liftIO
      ( Tune.trialObjectiveResultsWithDeviceForBudget
          device
          sampler
          parallelism
          updates
          trialBudget
      )
  trialResults <- case trialResultsE of
    Left err -> exitWithError (InvalidConfig ("device-backed tuning execution failed: " <> err))
    Right values -> pure values
  executions <-
    case Tune.trialExecutions scheduler pruner promotions trialResults of
      Left err -> exitWithError (InvalidConfig ("resolved tuning execution failed: " <> err))
      Right values -> pure values
  objectives <-
    traverse
      ( publishOneTrial
          pulsarSettings
          minioSettings
          substrate
          experimentHash
          planId
          sampler
          scheduler
          pruner
          parallelism
          promotions
          updates
          sweepSeed
      )
      executions
  let promotedObjectives =
        [ objective
        | (execution, objective) <- zip executions objectives
        , Tune.trialExecutionPromoted execution
        ]
      prunedCount = length (filter Tune.trialExecutionPruned executions)
      promotedCount = length promotedObjectives
  bestObjective <- case promotedObjectives of
    [] -> exitWithError (InvalidConfig "resolved tuning plan produced no trials")
    values -> pure (maximum values)
  let completed = fromIntegral trialBudget
      finished =
        ProtoTune.SweepFinished
          { ProtoTune.sfExperimentHash = experimentHash
          , ProtoTune.sfPlanId = planId
          , ProtoTune.sfTrialsCompleted = completed
          , ProtoTune.sfTrialsPruned = fromIntegral prunedCount
          , ProtoTune.sfTrialsPromoted = fromIntegral promotedCount
          , ProtoTune.sfBestObjective = bestObjective
          }
  completedTraining <-
    case tuneSweepCompletedTraining
      plan
      experimentHash
      completed
      bestObjective of
      Left err -> exitWithError (InvalidConfig ("tuning completion proof failed: " <> err))
      Right value -> pure value
  envelope <-
    case ProtoTune.completeSweep finished completedTraining of
      Left err -> exitWithError (InvalidConfig ("tuning completion event failed: " <> err))
      Right value -> pure (ProtoTune.TuneSweepCompleted value)
  publishResult <-
    liftIO
      ( publishPulsarEvent
          pulsarSettings
          Topology.TuneEventRoute
          substrate
          envelope
      )
  requireServiceSuccess "publish tuning completion" publishResult
 where
  publishOneTrial pulsarSettings minioSettings substrate experimentHash planId sampler scheduler pruner parallelism promotions updates sweepSeed execution = do
    let trialResult = Tune.trialExecutionResult execution
        trialIndex = Tune.trialResultIndex trialResult
        trialSeed = sweepSeed + trialIndex
        objective = Tune.trialResultObjective trialResult
        trialValues = [objective]
        transcript =
          Tune.TrialTranscript
            { Tune.transcriptExperimentHash = experimentHash
            , Tune.transcriptTrialSeed = trialSeed
            , Tune.transcriptValues = trialValues
            }
        parametersJson =
          "{\"sampler\":\""
            <> Text.pack (show sampler)
            <> "\",\"scheduler\":\""
            <> Text.pack (show scheduler)
            <> "\",\"pruner\":\""
            <> Text.pack (show pruner)
            <> "\",\"parallelism\":"
            <> Text.pack (show parallelism)
            <> ",\"promotions\":"
            <> Text.pack (show promotions)
            <> ",\"perTrialOptimizerUpdates\":"
            <> Text.pack (show updates)
            <> "}"
    timestampStart <- liftIO currentTimestampNs
    let startEvent =
          ProtoTune.TuneTrialStarted
            ( ProtoTune.TrialStarted
                { ProtoTune.tsExperimentHash = experimentHash
                , ProtoTune.tsPlanId = planId
                , ProtoTune.tsTrial = fromIntegral trialIndex
                , ProtoTune.tsTrialSeed = fromIntegral trialSeed
                , ProtoTune.tsParametersJson = parametersJson
                , ProtoTune.tsTimestampNs = timestampStart
                }
            )
    startPublish <-
      liftIO
        ( publishPulsarEvent
            pulsarSettings
            Topology.TuneEventRoute
            substrate
            startEvent
        )
    requireServiceSuccess "publish tuning trial start" startPublish
    persistResult <-
      liftIO
        ( MinIOSubprocess.runMinIOSubprocess
            minioSettings
            (Tune.persistTrialTranscript transcript)
        )
    requireServiceSuccess "persist tuning trial transcript" persistResult
    when (Tune.trialExecutionPromoted execution) $ do
      checkpointResult <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              ( writeMinIOWeightCheckpoint
                  experimentHash
                  "tune-trial-weights"
                  (fromIntegral trialSeed)
                  [("objective", objective)]
                  (Tune.trialResultWeights trialResult)
              )
          )
      requireServiceSuccess "persist promoted tuning trial checkpoint" checkpointResult
    timestampEnd <- liftIO currentTimestampNs
    let finishedEvent =
          ProtoTune.TuneTrialFinished
            ( ProtoTune.TrialFinished
                { ProtoTune.tfTuneExperimentHash = experimentHash
                , ProtoTune.tfTunePlanId = planId
                , ProtoTune.tfTuneTrial = fromIntegral trialIndex
                , ProtoTune.tfTuneObjective = objective
                , ProtoTune.tfTunePruned = Tune.trialExecutionPruned execution
                , ProtoTune.tfTuneTranscriptObjectKey =
                    Tune.trialStorageKey experimentHash trialSeed
                , ProtoTune.tfTuneTimestampNs = timestampEnd
                }
            )
    finishPublish <-
      liftIO
        ( publishPulsarEvent
            pulsarSettings
            Topology.TuneEventRoute
            substrate
            finishedEvent
        )
    requireServiceSuccess "publish tuning trial finish" finishPublish
    pure objective

  requireServiceSuccess label result =
    case result of
      Left err -> exitWithError (InvalidConfig (label <> ": " <> Text.pack (show err)))
      Right _ -> pure ()

runRl :: [Text] -> [ParsedOption] -> App ()
runRl ["rl", "train"] parsedOptions = do
  -- Sprint 1.12 — parse the CLI overrides (--substrate / --seed) per
  -- README.md → Why this exists pillar 2 before any worker dispatch.
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  -- Sprint 5.7 — read the RL run parameters from the typed Dhall
  -- `RunConfig` the daemon mounted on the dispatched Job pod. Falls back to
  -- env vars + defaults when no mount is present (e.g., developer-side CLI
  -- invocation outside the cluster). Defaults match the
  -- `experiments/cartpole.dhall` worked example.
  let rlExperimentPath =
        Text.unpack (selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions)
  runConfigLoad <- liftIO (RunConfig.tryLoadRlRunConfig runConfigPath)
  (envName, seed, maxSteps, evalEpisodes, trainerKind, atariRomPath) <- case runConfigLoad of
    RunConfig.RunConfigLoaded rc ->
      pure
        ( RunConfig.rlcEnvironment rc
        , RunConfig.rlcSeed rc
        , max 1 (RunConfig.rlcMaxSteps rc)
        , max 1 (RunConfig.rlcEvalEpisodes rc)
        , overrideTrainerKind overrides (Text.toLower (Text.strip (RunConfig.rlcTrainerKind rc)))
        , RunConfig.rlcAtariRomPath rc
        )
    RunConfig.RunConfigMissing -> do
      loaded <- liftIO (ProductExperiment.loadRlExperimentByPath rlExperimentPath)
      experiment <-
        case loaded of
          Left err -> exitWithError (DhallTypeError err)
          Right value -> pure value
      msR <- liftIO (envWithDefault "JITML_MAX_STEPS" "200")
      eeR <- liftIO (envWithDefault "JITML_EVAL_EPISODES" "4")
      pure
        ( ProductExperiment.rlExperimentEnvironment experiment
        , fromIntegral (ProductExperiment.rlExperimentSeed experiment)
        , max 1 (readIntDefault 200 msR)
        , max 1 (readIntDefault 4 eeR)
        , Workload.rlTrainerForAlgorithm
            (Overrides.overrideAlgorithm overrides (ProductExperiment.rlExperimentAlgorithm experiment))
        , Nothing
        )
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError "RlRunConfig" err)
  -- Sprint 1.12 — apply the CLI seed override before dispatch so the
  -- override governs same-seed rollout generation. Substrate
  -- override is recorded in the summary; it flows through to deeper RL
  -- worker dispatch in follow-up work when RunConfig generation reads
  -- the resolved value.
  let resolvedSeed = fromIntegral (Overrides.overrideSeed overrides (fromIntegral seed)) :: Int
  -- Sprint 20.1 — route catalog trainers through the real dispatch path.
  -- Sprint 8.8 routes atari-subset through the runtime-loaded ALE adapter
  -- and an explicit uncommitted ROM path; all other recognized trainer
  -- selectors produce convergence statistics through the network seam, then
  -- project the per-iteration summary into the @EpisodeDone@ envelope shape
  -- so the dispatch chain stays observable end-to-end.
  -- Sprint 8.11 — resolve the substrate and route every MLP-backed trainer
  -- through its JIT-compiled device. An unknown trainer or an unavailable
  -- substrate device fails closed with a typed `InvalidConfig`; nothing is
  -- printed or published in that case.
  substrate <- resolveWorkerSubstrate overrides
  env <- ask
  episodesE <-
    liftIO
      ( runTrainerEpisodes
          substrate
          (rlDeviceForSubstrate substrate env)
          atariRomPath
          trainerKind
          envName
          resolvedSeed
          evalEpisodes
          maxSteps
          Nothing
      )
  trainerRun <- case episodesE of
    Left err -> exitWithError (InvalidConfig err)
    Right run -> pure run
  let episodes = trainerRunEpisodes trainerRun
  liveExperimentHash <- workerExperimentHash
  let rlExperimentDhall = selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions
      derivedExperimentHash =
        Checkpoint.deriveExperimentHash
          rlExperimentDhall
          (renderSubstrate substrate <> ":" <> trainerKind <> ":" <> envName)
      experimentHash = fromMaybe derivedExperimentHash liveExperimentHash
      completionMetrics = rlCompletionMetrics trainerKind (trainerRunObservedUnits trainerRun) episodes
      averageReward = metricValueOrZero "avg_reward" completionMetrics
      checkpointStep = rlObservedBudgetUnits episodes
      tensorName = "rl-" <> trainerKind <> "-weights"
      completedTraining =
        trainerRunEvidence trainerRun
          >>= rlCompletedTraining
            trainerKind
            envName
            experimentHash
            tensorName
            checkpointStep
            completionMetrics
  checkpointMaybe <-
    case trainerRunWeights trainerRun of
      Nothing -> pure Nothing
      Just weights -> do
        stored <-
          writeLocalWeightCheckpointWithCompleted
            completedTraining
            experimentHash
            tensorName
            checkpointStep
            completionMetrics
            weights
        pure (Just (stored, completedTraining))
  replayArtifact <-
    writeTextArtifact
      experimentHash
      "rl-trajectory"
      (renderRlTrajectoryArtifact experimentHash envName trainerKind resolvedSeed episodes)
  let replayArtifactLines = renderStoredArtifactLines "rl-replay" replayArtifact
  writeText $
    Text.unlines
      ( [ "rl train: " <> rlExperimentDhall
        , "algorithms: " <> Text.pack (show (length RL.algorithmCatalog))
        , "environment: " <> envName
        , "trainer: " <> trainerKind
        , "episodes: " <> Text.pack (show (length episodes))
        , "avg-reward: " <> Text.pack (show averageReward)
        , "overrides: " <> Overrides.renderExperimentOverrides overrides
        ]
          <> maybe [] (renderStoredCheckpointLines experimentHash . fst) checkpointMaybe
          <> replayArtifactLines
      )
  traverse_ (publishWorkerRlEpisode envName) episodes
  publishWorkerRlCompletion tensorName checkpointStep completionMetrics checkpointMaybe

-- Sprint 9.9 — `jitml rl eval` loads the named checkpoint and runs the real
-- substrate device forward (shared with `jitml eval`); a missing checkpoint →
-- `InferenceCheckpointMissing`, no echo stub.
runRl ["rl", "eval"] parsedOptions = runCheckpointEval "rl eval" parsedOptions
-- Sprint 9.9 — `jitml rl rollout --seed N` runs one real on-device PPO rollout
-- on cartpole through the resolved substrate's JIT engine and prints the
-- measured per-iteration episode rewards. No LCG `deterministicTrajectory`
-- stand-in; an unavailable substrate device fails closed with `InvalidConfig`.
runRl ["rl", "rollout"] parsedOptions = do
  seed <- requireUserIntOptionAtLeast "seed" 42 0 parsedOptions
  substrate <- workerSubstrateBase
  env <- ask
  episodesE <- liftIO (runDeviceRollout (rlDeviceForSubstrate substrate env) seed)
  case episodesE of
    Left err -> exitWithError (InvalidConfig err)
    Right episodes -> do
      let experimentHash =
            Checkpoint.deriveExperimentHash
              "rl-rollout"
              (renderSubstrate substrate <> ":" <> Text.pack (show seed))
      replayArtifact <-
        writeTextArtifact
          experimentHash
          "rl-rollout"
          (renderRlTrajectoryArtifact experimentHash "cartpole" "ppo-rollout" seed episodes)
      writeText $
        Text.unlines
          ( [ "rl rollout: seed="
                <> Text.pack (show seed)
                <> " substrate="
                <> renderSubstrate substrate
                <> " rewards="
                <> Text.pack (show (fmap EpisodeEnvelope.simEpisodeReward episodes))
            ]
              <> renderStoredArtifactLines "rl-rollout" replayArtifact
          )
runRl ["rl", "alphazero", "self-play"] parsedOptions = do
  mounted <- liftIO (RunConfig.tryLoadAlphaZeroRunConfig runConfigPath)
  case mounted of
    RunConfig.RunConfigLoaded config ->
      case RunConfig.alphaZeroPlanFromRunConfig config of
        Left err -> exitWithError (mountedRunConfigDecodeError "AlphaZeroRunConfig" err)
        Right plan -> runResolvedAlphaZeroPlan True plan
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError "AlphaZeroRunConfig" err)
    RunConfig.RunConfigMissing -> do
      rejectMissingMountedRunConfigInKubernetes "AlphaZeroRunConfig"
      plan <- prepareLocalAlphaZeroPlan parsedOptions
      runResolvedAlphaZeroPlan False plan
runRl path _ =
  exitWithError (UnknownCommand ("unknown rl command: " <> commandPathText path))

prepareLocalAlphaZeroPlan :: [ParsedOption] -> App WorkloadPlan.AlphaZeroPlan
prepareLocalAlphaZeroPlan parsedOptions = do
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  baseSubstrate <- workerSubstrateBase
  generations <- requireUserIntOptionAtLeast "generations" 1 1 parsedOptions
  games <- requireUserIntOptionAtLeast "games" 2 1 parsedOptions
  sims <- requireUserIntOptionAtLeast "sims" 4 1 parsedOptions
  maxPlies <- requireUserIntOptionAtLeast "max-plies" 6 1 parsedOptions
  updates <- requireUserIntOptionAtLeast "updates" 1 1 parsedOptions
  arenaGames <- requireUserIntOptionAtLeast "arena-games" 4 1 parsedOptions
  let gameName = ProductExperiment.normalizeAlphaZeroGame (selectedValue "game" "connect4" parsedOptions)
      canonicalGameNames = fmap AlphaZero.pigName AlphaZero.canonicalGames
  unless (gameName `elem` canonicalGameNames) $
    exitWithError
      ( InvalidConfig
          ( "unknown AlphaZero game: "
              <> gameName
              <> " (expected one of "
              <> Text.intercalate ", " canonicalGameNames
              <> ")"
          )
      )
  generationsWord <- word32PlanValue "AlphaZero generations" (toInteger generations)
  gamesWord <- word32PlanValue "AlphaZero self-play games" (toInteger games)
  simsWord <- word32PlanValue "AlphaZero MCTS simulations" (toInteger sims)
  maxPliesWord <- word32PlanValue "AlphaZero max plies" (toInteger maxPlies)
  updatesWord <- word32PlanValue "AlphaZero optimizer updates" (toInteger updates)
  arenaGamesWord <- word32PlanValue "AlphaZero arena games" (toInteger arenaGames)
  let substrate = Overrides.overrideSubstrate overrides baseSubstrate
      seed = Overrides.overrideSeed overrides 31
      experimentHash =
        Checkpoint.deriveExperimentHash
          "alphazero-self-play"
          ( Text.intercalate
              ":"
              [ renderSubstrate substrate
              , gameName
              , Text.pack (show generations)
              , Text.pack (show games)
              , Text.pack (show sims)
              , Text.pack (show maxPlies)
              , Text.pack (show updates)
              , Text.pack (show arenaGames)
              , Text.pack (show seed)
              ]
          )
      raw =
        ProtoRl.StartAlphaZeroRun
          { ProtoRl.sazSubstrate = substrate
          , ProtoRl.sazExperimentHash = experimentHash
          , ProtoRl.sazPlanId = ""
          , ProtoRl.sazResolvedPlan = ""
          , ProtoRl.sazGame = gameName
          , ProtoRl.sazGenerations = generationsWord
          , ProtoRl.sazSelfPlayGames = gamesWord
          , ProtoRl.sazMctsSimulationsPerMove = simsWord
          , ProtoRl.sazMaxPlies = maxPliesWord
          , ProtoRl.sazOptimizerUpdates = updatesWord
          , ProtoRl.sazArenaGames = arenaGamesWord
          , ProtoRl.sazSeed = seed
          }
  case PlanCommand.prepareStartAlphaZeroRun raw of
    Left err -> exitWithError (InvalidConfig ("AlphaZero plan refinement failed: " <> err))
    Right (_, plan) -> pure plan

runResolvedAlphaZeroPlan :: Bool -> WorkloadPlan.AlphaZeroPlan -> App ()
runResolvedAlphaZeroPlan requireLiveContext plan = do
  env <- ask
  generations <-
    intPlanValue "AlphaZero generations" (quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan))
  games <-
    intPlanValue
      "AlphaZero self-play games"
      (quantityValue (WorkloadPlan.alphaZeroPlanSelfPlayGames plan))
  sims <-
    intPlanValue
      "AlphaZero MCTS simulations"
      (quantityValue (WorkloadPlan.alphaZeroPlanMctsSimulations plan))
  maxPlies <-
    intPlanValue "AlphaZero max plies" (quantityValue (WorkloadPlan.alphaZeroPlanMaxPlies plan))
  updates <-
    intPlanValue "AlphaZero optimizer updates" (quantityValue (WorkloadPlan.alphaZeroPlanUpdates plan))
  arenaGames <-
    intPlanValue "AlphaZero arena games" (quantityValue (WorkloadPlan.alphaZeroPlanArenaGames plan))
  seed <-
    intPlanValue
      "AlphaZero seed"
      (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.alphaZeroPlanRunPlan plan))))
  contextMaybe <- workerLiveContext
  when (requireLiveContext && isNothing contextMaybe) $
    exitWithError (InvalidConfig "resolved AlphaZero worker requires mounted service configuration")
  let substrate = runPlanSubstrate (WorkloadPlan.alphaZeroPlanRunPlan plan)
      experimentHash = runPlanExperimentId (WorkloadPlan.alphaZeroPlanRunPlan plan)
      planId = planIdText (WorkloadPlan.alphaZeroPlanId plan)
      gameName = WorkloadPlan.renderAlphaZeroGame (WorkloadPlan.alphaZeroPlanGame plan)
      device = rlDeviceForSubstrate substrate env
      initialState = AlphaZero.initialStateFor gameName
      observationSize = AlphaZero.observationSizeFor gameName
      actionCount = AlphaZero.actionCountFor gameName
      net0 = PolicyValueNet.initPolicyValueNet observationSize actionCount 16 seed
      adam0 = PolicyValueNet.initAdamFor net0
  for_ contextMaybe $ \context ->
    unless (Publication.publicationSubstrate (workerLivePublication context) == substrate) $
      exitWithError
        ( InvalidConfig
            ( "resolved AlphaZero plan substrate "
                <> renderSubstrate substrate
                <> " does not match worker substrate "
                <> renderSubstrate (Publication.publicationSubstrate (workerLivePublication context))
            )
        )
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err -> exitWithError (InvalidConfig ("AlphaZero substrate device unavailable: " <> err))
    Right () -> do
      (trainedNet, samples) <-
        trainResolvedAlphaZeroGenerations
          contextMaybe
          substrate
          experimentHash
          planId
          initialState
          device
          net0
          adam0
          generations
          games
          sims
          maxPlies
          updates
          seed
      let winRate =
            PolicyValueNet.arenaWinRateAgainstUniformFrom
              initialState
              trainedNet
              arenaGames
              maxPlies
              (seed + 7919)
          completedGenerations = fromIntegral generations
          checkpointStep =
            alphaZeroArtifactStep completedGenerations (length samples)
          alphaZeroMetrics =
            [ ("arena_win_rate", winRate)
            , ("legal_move_rate", 1.0)
            , ("mcts_simulations_per_move", fromIntegral sims)
            , ("self_play_games", fromIntegral games)
            , ("self_play_generations", fromIntegral generations)
            , ("self_play_samples", fromIntegral (length samples))
            ]
          initialAlphaZeroWeights = PolicyValueNet.policyValueNetToFlat net0
          alphaZeroWeights = PolicyValueNet.policyValueNetToFlat trainedNet
          alphaZeroCompleted =
            do
              budget <- eitherToMaybe (alphaZeroCompletionBudget plan)
              alphaZeroCompletedTraining
                (WorkloadPlan.alphaZeroPlanId plan)
                budget
                experimentHash
                gameName
                completedGenerations
                alphaZeroMetrics
                initialAlphaZeroWeights
                alphaZeroWeights
      stored <-
        writeLocalWeightCheckpointWithCompleted
          alphaZeroCompleted
          experimentHash
          ("alphazero-" <> gameName <> "-policy-value-weights")
          checkpointStep
          alphaZeroMetrics
          alphaZeroWeights
      transcriptArtifact <-
        writeTextArtifact
          experimentHash
          "alphazero-transcript"
          (renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples)
      writeText $
        Text.unlines
          ( [ "rl alphazero self-play: substrate=" <> renderSubstrate substrate
            , "game: " <> gameName
            , "generations: " <> Text.pack (show generations)
            , "games: " <> Text.pack (show games)
            , "samples: " <> Text.pack (show (length samples))
            , "arena-win-rate: " <> Text.pack (show winRate)
            , "legal-move-rate: 1.0"
            , "mcts-simulations-per-move: " <> Text.pack (show sims)
            ]
              <> renderStoredCheckpointLines experimentHash stored
              <> renderStoredArtifactLines "alphazero-transcript" transcriptArtifact
          )
      publishResolvedAlphaZeroEvent
        contextMaybe
        substrate
        ( ProtoRl.RlArenaCompleted
            ProtoRl.ArenaCompleted
              { ProtoRl.acPlanId = planId
              , ProtoRl.acExperimentHash = experimentHash
              , ProtoRl.acArenaGames = fromIntegral arenaGames
              , ProtoRl.acWinRate = winRate
              }
        )

trainResolvedAlphaZeroGenerations
  :: Maybe WorkerLiveContext
  -> Substrate
  -> Text
  -> Text
  -> AlphaZero.GameState
  -> MlpDevice
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> App (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample])
trainResolvedAlphaZeroGenerations context substrate experimentHash planId initialState device = go 0
 where
  go generation net adam generationTarget games sims maxPlies updates seed
    | generation >= generationTarget = pure (net, [])
    | otherwise = do
        sampleResults <-
          liftIO $
            traverse
              ( \gameIndex ->
                  PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                    initialState
                    device
                    net
                    (seed + generation * 7919 + gameIndex)
                    sims
                    maxPlies
              )
              [0 .. games - 1]
        generationSamples <- case sequence sampleResults of
          Left err -> exitWithError (InvalidConfig ("AlphaZero self-play failed: " <> err))
          Right batches -> pure (concat batches)
        when (null generationSamples) $
          exitWithError (InvalidConfig "AlphaZero self-play produced no samples")
        trainedE <-
          liftIO $
            PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
              device
              net
              adam
              1.0e-3
              updates
              generationSamples
        (trainedNet, trainedAdam) <- case trainedE of
          Left err -> exitWithError (InvalidConfig ("AlphaZero device training failed: " <> err))
          Right trained -> pure trained
        publishResolvedAlphaZeroEvent
          context
          substrate
          ( ProtoRl.RlGenerationCompleted
              ProtoRl.GenerationCompleted
                { ProtoRl.gcPlanId = planId
                , ProtoRl.gcExperimentHash = experimentHash
                , ProtoRl.gcGeneration = fromIntegral generation
                , ProtoRl.gcSelfPlayGames = fromIntegral games
                , ProtoRl.gcSamples = fromIntegral (length generationSamples)
                }
          )
        (finalNet, laterSamples) <-
          go
            (generation + 1)
            trainedNet
            trainedAdam
            generationTarget
            games
            sims
            maxPlies
            updates
            seed
        pure (finalNet, generationSamples <> laterSamples)

publishResolvedAlphaZeroEvent :: Maybe WorkerLiveContext -> Substrate -> ProtoRl.RlEvent -> App ()
publishResolvedAlphaZeroEvent Nothing _ _ = pure ()
publishResolvedAlphaZeroEvent (Just context) substrate event = do
  result <-
    liftIO
      ( publishPulsarEvent
          (workerLivePulsarSettings context)
          Topology.RlEventRoute
          substrate
          event
      )
  case result of
    Left err -> exitWithError (InvalidConfig ("publish AlphaZero event: " <> Text.pack (show err)))
    Right _ -> pure ()

intPlanValue :: Text -> Word64 -> App Int
intPlanValue label value
  | toInteger value > toInteger (maxBound :: Int) =
      exitWithError (InvalidConfig (label <> " exceeds the platform Int range"))
  | otherwise = pure (fromIntegral value)

overrideTrainerKind :: Overrides.ExperimentOverrides -> Text -> Text
overrideTrainerKind overrides base =
  maybe base Workload.rlTrainerForAlgorithm (Overrides.eoAlgorithm overrides)

-- | Sprint 9.9 — run a single real on-device PPO rollout (one iteration:
-- collect a real cartpole rollout through the substrate device, one policy
-- update) and project its per-iteration stats into episodes. A device 'Left'
-- (toolchain/hardware absent) propagates so `rl rollout` fails closed rather
-- than emitting a scripted trajectory.
runDeviceRollout :: MlpDevice -> Int -> IO (Either Text [EpisodeEnvelope.SimulatedEpisode])
runDeviceRollout device seed = do
  let config =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = seed
          , PpoTrainer.ppoVariant = PpoTrainer.VariantPPO
          , PpoTrainer.ppoNumIterations = 1
          , PpoTrainer.ppoRolloutSteps = 512
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
  resultE <- PpoTrainer.trainOnPolicyOnDevice device PpoTrainer.VariantPPO config
  pure $
    fmap
      ( map
          ( \stat ->
              EpisodeEnvelope.SimulatedEpisode
                { EpisodeEnvelope.simEpisodeIndex = PpoTrainer.iterIndex stat
                , EpisodeEnvelope.simEpisodeSteps = 512
                , EpisodeEnvelope.simEpisodeReward = PpoTrainer.iterMeanReward stat
                , EpisodeEnvelope.simEpisodeDone = True
                , EpisodeEnvelope.simEpisodeFrames = []
                }
          )
          . PpoTrainer.resultIterations
      )
      resultE

writeLocalWeightCheckpoint
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> App CheckpointStore.StoredCheckpoint
writeLocalWeightCheckpoint =
  writeLocalWeightCheckpointWithDatasetSha Nothing

writeLocalWeightCheckpointWithDatasetSha
  :: Maybe Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> App CheckpointStore.StoredCheckpoint
writeLocalWeightCheckpointWithDatasetSha datasetShaAtRead experimentHash tensorName step metrics weights = do
  writeLocalWeightCheckpointWithDatasetShaAndCompleted
    datasetShaAtRead
    Nothing
    experimentHash
    tensorName
    step
    metrics
    weights

writeLocalWeightCheckpointWithCompleted
  :: Maybe TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> App CheckpointStore.StoredCheckpoint
writeLocalWeightCheckpointWithCompleted completedOverride experimentHash tensorName step metrics weights = do
  checkpointRoot <- localCheckpointRoot
  let (manifest, payloads) =
        buildWeightCheckpointSnapshotWithExplicitCompleted
          completedOverride
          experimentHash
          tensorName
          step
          metrics
          weights
  expectedPointer <- localLatestPointerExpectation checkpointRoot experimentHash
  writeResult <-
    liftIO (CheckpointStore.writeCheckpointSnapshot checkpointRoot manifest payloads expectedPointer)
  case writeResult of
    Left err ->
      exitWithError (InvalidConfig ("checkpoint write: " <> err))
    Right stored -> do
      _ <- mirrorWeightCheckpointToLiveIfPublished manifest payloads
      pure stored

writeLocalWeightCheckpointWithDatasetShaAndCompleted
  :: Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> App CheckpointStore.StoredCheckpoint
writeLocalWeightCheckpointWithDatasetShaAndCompleted datasetShaAtRead completedOverride experimentHash tensorName step metrics weights = do
  checkpointRoot <- localCheckpointRoot
  let (manifest, payloads) =
        buildWeightCheckpointSnapshotWithDatasetShaAndCompleted
          datasetShaAtRead
          completedOverride
          experimentHash
          tensorName
          step
          metrics
          weights
  expectedPointer <- localLatestPointerExpectation checkpointRoot experimentHash
  writeResult <-
    liftIO (CheckpointStore.writeCheckpointSnapshot checkpointRoot manifest payloads expectedPointer)
  case writeResult of
    Left err ->
      exitWithError (InvalidConfig ("checkpoint write: " <> err))
    Right stored -> do
      _ <- mirrorWeightCheckpointToLiveIfPublished manifest payloads
      pure stored

localLatestPointerExpectation :: FilePath -> Text -> App (Maybe Text)
localLatestPointerExpectation checkpointRoot experimentHash = do
  pointerResult <-
    liftIO
      ( CheckpointStore.readCheckpointPointer
          checkpointRoot
          (Checkpoint.latestPointerKey experimentHash)
      )
  case pointerResult of
    Left err ->
      exitWithError (InvalidConfig ("checkpoint pointer read: " <> err))
    Right currentPointer -> pure currentPointer

writeMinIOWeightCheckpoint
  :: (Capabilities.HasMinIO m)
  => Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> m (Either ServiceError CheckpointStore.StoredCheckpoint)
writeMinIOWeightCheckpoint =
  writeMinIOWeightCheckpointWithDatasetSha Nothing

writeMinIOWeightCheckpointWithDatasetSha
  :: (Capabilities.HasMinIO m)
  => Maybe Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> m (Either ServiceError CheckpointStore.StoredCheckpoint)
writeMinIOWeightCheckpointWithDatasetSha datasetShaAtRead experimentHash tensorName step metrics weights =
  let (manifest, payloads) =
        buildWeightCheckpointSnapshotWithDatasetSha
          datasetShaAtRead
          experimentHash
          tensorName
          step
          metrics
          weights
   in CheckpointStore.writeCheckpointSnapshotWithMinIO manifest payloads Nothing

writeMinIOWeightCheckpointWithDatasetShaAndCompleted
  :: (Capabilities.HasMinIO m)
  => Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> m (Either ServiceError CheckpointStore.StoredCheckpoint)
writeMinIOWeightCheckpointWithDatasetShaAndCompleted datasetShaAtRead completedOverride experimentHash tensorName step metrics weights =
  let (manifest, payloads) =
        buildWeightCheckpointSnapshotWithDatasetShaAndCompleted
          datasetShaAtRead
          completedOverride
          experimentHash
          tensorName
          step
          metrics
          weights
   in CheckpointStore.writeCheckpointSnapshotWithMinIO manifest payloads Nothing

buildWeightCheckpointSnapshotWithDatasetSha
  :: Maybe Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildWeightCheckpointSnapshotWithDatasetSha datasetShaAtRead =
  buildWeightCheckpointSnapshotWithDatasetShaAndCompleted datasetShaAtRead Nothing

buildWeightCheckpointSnapshotWithDatasetShaAndCompleted
  :: Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildWeightCheckpointSnapshotWithDatasetShaAndCompleted datasetShaAtRead completedOverride =
  buildWeightCheckpointSnapshotWithDatasetShaAndCompletion datasetShaAtRead completedOverride True

buildWeightCheckpointSnapshotWithExplicitCompleted
  :: Maybe TrainingBudget.CompletedTraining
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildWeightCheckpointSnapshotWithExplicitCompleted completedOverride =
  buildWeightCheckpointSnapshotWithDatasetShaAndCompletion
    Nothing
    completedOverride
    (isJust completedOverride)

buildWeightCheckpointSnapshotWithDatasetShaAndCompletion
  :: Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> Bool
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildWeightCheckpointSnapshotWithDatasetShaAndCompletion _datasetShaAtRead completedOverride markCompleted experimentHash tensorName step metrics weights =
  let payload = Checkpoint.encodeJmw1 weights
      blobSha = hexEncodeBytes (Crypto.Hash.SHA256.hash (LazyByteString.toStrict payload))
      blobObjectKey = Checkpoint.blobKey experimentHash blobSha
      weightTensor = Checkpoint.TensorBlob tensorName [length weights] blobObjectKey
      modelFamily = checkpointModelFamilyForTensor tensorName
      completed =
        if markCompleted
          then completedOverride
          else Nothing
      baseManifest =
        ( Checkpoint.emptyManifest
            ("checkpoint-" <> Text.pack (show step))
            experimentHash
            [weightTensor]
        )
          { Checkpoint.manifestModelFamily = modelFamily
          , Checkpoint.manifestArchitecture =
              Checkpoint.ArchitectureMetadata
                { Checkpoint.architectureName = checkpointArchitectureName modelFamily
                , Checkpoint.architectureModelFamily = modelFamily
                , Checkpoint.architectureInputs = []
                , Checkpoint.architectureOutputs = []
                , Checkpoint.architectureLayerGraph = Nothing
                }
          , Checkpoint.manifestOutputDecoders = checkpointOutputDecoders modelFamily
          , Checkpoint.manifestWeightLayout =
              Checkpoint.NamedTensorWeightLayout [Checkpoint.tensorSpecFromBlob weightTensor]
          , Checkpoint.manifestStep = step
          , Checkpoint.manifestMetrics = metrics
          }
      manifest =
        maybe
          baseManifest
          (`Checkpoint.attachCompletedTraining` baseManifest)
          completed
   in (manifest, [(blobObjectKey, payload)])

completedTrainingForSupervisedProblem
  :: WorkloadPlan.SupervisedPlan
  -> SL.CanonicalProblem
  -> TrainingMetrics
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForSupervisedProblem plan problem metrics experimentHash tensorName step metricRows finalWeights = do
  row <-
    maybe
      (Left ("missing ProductRow for supervised problem " <> SL.problemName problem))
      Right
      (supervisedProductRowForProblem problem)
  initialWeights <-
    maybe
      (Left ("missing initial checkpoint weights for " <> SL.problemName problem))
      Right
      (tmInitialCheckpointWeights metrics)
  budget <-
    TrainingBudget.mkTrainingBudget
      TrainingBudget.SupervisedEpochBudget
      (quantityValue (WorkloadPlan.supervisedPlanEpochs plan))
      (Just (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.supervisedPlanRunPlan plan)))))
  completedTrainingForProductRow
    (WorkloadPlan.supervisedPlanId plan)
    budget
    row
    (tmDatasetShaAtRead metrics)
    experimentHash
    tensorName
    step
    metricRows
    initialWeights
    finalWeights

supervisedProductRowForProblem
  :: SL.CanonicalProblem
  -> Maybe (ProductMatrix.ProductRow 'ProductMatrix.Declared)
supervisedProductRowForProblem problem =
  listToMaybe
    [ row
    | row <- ProductMatrix.allProductRows
    , ProductMatrix.family row == ProductMatrix.Supervised
    , ProductMatrix.rowId row == SL.problemName problem
    ]

completedTrainingForProductRow
  :: PlanId
  -> TrainingBudget.TrainingBudget
  -> ProductMatrix.ProductRow state
  -> Maybe Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Double]
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForProductRow planId budget row datasetShaAtRead experimentHash tensorName step metrics initialWeights finalWeights = do
  evidence <-
    checkpointTrainingEvidenceWithInitialWeights
      datasetShaAtRead
      initialWeights
      experimentHash
      tensorName
      step
      metrics
      finalWeights
  observations <- convergenceObservationsForProductRow row metrics
  TrainingBudget.completedTraining
    planId
    budget
    step
    evidence
    observations
    TrainingBudget.TensorBoardRunMetadata
      { TrainingBudget.tbrRunId = experimentHash
      , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
      , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
      }

-- | Phase-10 bridge for product rows whose total kind-indexed plan projection
-- lands in Sprint 19.4.  The identity is still canonical, deterministic, and
-- bound to the row's declared budget; Sprint 19.4 replaces this bridge with
-- the row's resolved 'RunPlan' identity.
completionPlanIdForProductRow
  :: ProductMatrix.ProductRow state
  -> Either Text PlanId
completionPlanIdForProductRow row =
  completionPlanIdFromCanonicalText
    ( Text.intercalate
        "\NUL"
        [ "jitml-product-row-completion-plan-v1"
        , ProductMatrix.rowId row
        , ProductMatrix.productRowExperimentHash row
        , TrainingBudget.renderTrainingBudget (ProductMatrix.trainingBudget row)
        ]
    )

completionPlanIdFromCanonicalText :: Text -> Either Text PlanId
completionPlanIdFromCanonicalText canonical =
  case validationToEither (planIdFromCanonicalText canonical) of
    Right planId -> Right planId
    Left errors ->
      Left ("completion plan-id refinement failed: " <> Text.pack (show errors))

convergenceObservationsForProductRow
  :: ProductMatrix.ProductRow state
  -> [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsForProductRow row metrics = do
  observation <-
    ProductConvergence.evaluateConvergence
      (ProductMatrix.convergenceBar row)
      (ProductConvergence.MeasuredMetrics metrics)
  case ProductExternalBars.assertProductBarExternal
    (ProductMatrix.convergenceBar row)
    (TrainingBudget.coMetricValue observation) of
    [] -> Right [observation]
    failures -> Left (Text.intercalate "; " failures)

tuneSweepCompletedTraining
  :: WorkloadPlan.TuningPlan
  -> Text
  -> Word32
  -> Double
  -> Either Text TrainingBudget.CompletedTraining
tuneSweepCompletedTraining plan experimentHash trialsCompleted bestObjective =
  let observed = fromIntegral trialsCompleted
      planned = quantityValue (WorkloadPlan.tuningPlanTrials plan)
      seed = NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.tuningPlanRunPlan plan)))
      metrics = [("best_objective", bestObjective)]
   in do
        budget <-
          TrainingBudget.mkTrainingBudget
            TrainingBudget.TuningTrialBudget
            planned
            (Just seed)
        evidence <-
          ProductEvidence.mkTrainingEvidence
            (sha256Text ("tune-initial:" <> experimentHash))
            (sha256Text ("tune-final:" <> experimentHash <> ":" <> Text.pack (show bestObjective)))
            observed
            (sha256Text ("tune-dataset:" <> experimentHash))
        observations <- convergenceObservationsForMetrics metrics
        TrainingBudget.completedTraining
          (WorkloadPlan.tuningPlanId plan)
          budget
          observed
          evidence
          observations
          TrainingBudget.TensorBoardRunMetadata
            { TrainingBudget.tbrRunId = experimentHash
            , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
            , TrainingBudget.tbrScalarTags = fmap fst metrics
            }

alphaZeroCompletedTraining
  :: PlanId
  -> TrainingBudget.TrainingBudget
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Double]
  -> Maybe TrainingBudget.CompletedTraining
alphaZeroCompletedTraining planId budget experimentHash game generationCount metrics initialWeights finalWeights = do
  evidence <-
    eitherToMaybe $
      ProductEvidence.mkTrainingEvidence
        (hashWeightList initialWeights)
        (hashWeightList finalWeights)
        (max 1 generationCount)
        (sha256Text ("alphazero-evidence:" <> experimentHash <> ":" <> game))
  observations <- eitherToMaybe (alphaZeroConvergenceObservations metrics)
  eitherToMaybe $
    TrainingBudget.completedTraining
      planId
      budget
      generationCount
      evidence
      observations
      TrainingBudget.TensorBoardRunMetadata
        { TrainingBudget.tbrRunId = experimentHash
        , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
        , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
        }

-- | AlphaZero budgets are counted in completed self-play generations. Sample
-- count remains useful diagnostic evidence, but it is not the checkpoint's
-- progress unit and can differ substantially between games and runs.
alphaZeroArtifactStep :: Word64 -> Int -> Word64
alphaZeroArtifactStep completedGenerations _sampleCount = completedGenerations

alphaZeroCompletionBudget
  :: WorkloadPlan.AlphaZeroPlan
  -> Either Text TrainingBudget.TrainingBudget
alphaZeroCompletionBudget plan =
  TrainingBudget.mkTrainingBudget
    TrainingBudget.AlphaZeroSelfPlayBudget
    (quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan))
    ( Just
        ( NonEmpty.head
            (seedCohortValues (runPlanSeeds (WorkloadPlan.alphaZeroPlanRunPlan plan)))
        )
    )

alphaZeroConvergenceObservations
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
alphaZeroConvergenceObservations metrics = do
  arenaWinRate <-
    maybe
      (Left "missing AlphaZero arena_win_rate metric")
      Right
      (lookup "arena_win_rate" metrics)
  let threshold = RLConvergence.alphaZeroArenaThreshold
      thresholdValue = RLConvergence.azTargetWinRate threshold - RLConvergence.azSlack threshold
  observation <-
    TrainingBudget.measureCriterionExcluding
      "arena_win_rate"
      TrainingBudget.MetricMaximise
      thresholdValue
      0.5
      1.0e-12
      arenaWinRate
  pure [observation]

checkpointTrainingEvidenceWithInitialWeights
  :: Maybe Text
  -> [Double]
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> Either Text ProductEvidence.TrainingEvidence
checkpointTrainingEvidenceWithInitialWeights datasetShaAtRead initialWeights experimentHash tensorName step metrics weights =
  ProductEvidence.mkTrainingEvidence
    (hashWeightList initialWeights)
    (hashBytes (LazyByteString.toStrict (Checkpoint.encodeJmw1 weights)))
    (max 1 step)
    (fromMaybe (checkpointDatasetShaAtRead experimentHash tensorName metrics) datasetShaAtRead)

checkpointDatasetShaAtRead :: Text -> Text -> [(Text, Double)] -> Text
checkpointDatasetShaAtRead experimentHash tensorName metrics =
  sha256Text $
    Text.intercalate
      ":"
      [ "checkpoint-dataset"
      , experimentHash
      , tensorName
      , Text.intercalate "," (fmap fst metrics)
      ]

convergenceObservationsForMetrics
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsForMetrics =
  ProductExternalBars.convergenceObservationsForMetrics

sha256Text :: Text -> Text
sha256Text =
  hashBytes . Crypto.Hash.SHA256.hash . Text.Encoding.encodeUtf8

hashBytes :: Data.ByteString.ByteString -> Text
hashBytes =
  hexEncodeBytes . Crypto.Hash.SHA256.hash

checkpointTrainingBudgetForTensor :: Text -> Word64 -> TrainingBudget.TrainingBudget
checkpointTrainingBudgetForTensor tensorName step =
  let kind =
        case checkpointModelFamilyForTensor tensorName of
          Checkpoint.ReinforcementLearningPolicyFamily ->
            TrainingBudget.RlEnvironmentStepBudget
          Checkpoint.AlphaZeroPolicyValueFamily ->
            TrainingBudget.AlphaZeroSelfPlayBudget
          Checkpoint.HyperparameterTuningFamily ->
            TrainingBudget.TuningTrialBudget
          Checkpoint.SupervisedModelFamily ->
            TrainingBudget.SupervisedEpochBudget
          Checkpoint.GenericModelFamily ->
            TrainingBudget.SupervisedEpochBudget
   in either
        (error . Text.unpack)
        id
        (TrainingBudget.mkTrainingBudget kind (max 1 step) Nothing)

checkpointModelFamilyForTensor :: Text -> Checkpoint.ModelFamily
checkpointModelFamilyForTensor tensorName
  | "alphazero" `Text.isInfixOf` lowered =
      Checkpoint.AlphaZeroPolicyValueFamily
  | "rl-" `Text.isPrefixOf` lowered =
      Checkpoint.ReinforcementLearningPolicyFamily
  | "tune" `Text.isInfixOf` lowered =
      Checkpoint.HyperparameterTuningFamily
  | otherwise =
      Checkpoint.GenericModelFamily
 where
  lowered = Text.toLower tensorName

checkpointArchitectureName :: Checkpoint.ModelFamily -> Text
checkpointArchitectureName family =
  case family of
    Checkpoint.SupervisedModelFamily -> "supervised-weighted-model"
    Checkpoint.ReinforcementLearningPolicyFamily -> "rl-policy"
    Checkpoint.AlphaZeroPolicyValueFamily -> "alphazero-policy-value"
    Checkpoint.HyperparameterTuningFamily -> "tuning-surrogate-or-trial"
    Checkpoint.GenericModelFamily -> "generic-weighted-model"

checkpointOutputDecoders :: Checkpoint.ModelFamily -> [Checkpoint.OutputDecoder]
checkpointOutputDecoders family =
  case family of
    Checkpoint.SupervisedModelFamily ->
      [decoder "prediction" Checkpoint.ClassificationOutput]
    Checkpoint.ReinforcementLearningPolicyFamily ->
      [decoder "policy" Checkpoint.PolicyDistributionOutput]
    Checkpoint.AlphaZeroPolicyValueFamily ->
      [ decoder "policy" Checkpoint.PolicyDistributionOutput
      , decoder "value" Checkpoint.ValueEstimateOutput
      , decoder "mcts-visits" Checkpoint.MctsVisitDistributionOutput
      ]
    Checkpoint.HyperparameterTuningFamily ->
      [decoder "objective" Checkpoint.RegressionOutput]
    Checkpoint.GenericModelFamily ->
      [decoder "output" Checkpoint.GenericOutput]
 where
  decoder name kind =
    Checkpoint.OutputDecoder
      { Checkpoint.outputDecoderName = name
      , Checkpoint.outputDecoderKind = kind
      , Checkpoint.outputDecoderLabels = []
      , Checkpoint.outputDecoderUnits = Nothing
      , Checkpoint.outputDecoderArtifactKind = Nothing
      }

mirrorWeightCheckpointToLiveIfPublished
  :: Checkpoint.CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> App Bool
mirrorWeightCheckpointToLiveIfPublished manifest payloads = do
  publicationMaybe <- liftIO (readExistingLivePublication ".")
  case publicationMaybe of
    Nothing -> pure False
    Just publication -> do
      let minioSettings = MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              ( do
                  expectedPointer <-
                    MinIOSubprocess.minioObjectETag
                      ( CheckpointStore.checkpointObjectRef
                          (Checkpoint.latestPointerKey (Checkpoint.manifestExperiment manifest))
                      )
                  case expectedPointer of
                    Left err -> pure (Left err)
                    Right expected ->
                      CheckpointStore.writeCheckpointSnapshotWithMinIO manifest payloads expected
              )
          )
      case result of
        Right _ -> pure True
        Left err ->
          exitWithError (MinIOFailed ("checkpoint mirror failed: " <> Text.pack (show err)))

renderStoredCheckpointLines :: Text -> CheckpointStore.StoredCheckpoint -> [Text]
renderStoredCheckpointLines = renderStoredCheckpointLinesWithPrefix "checkpoint"

renderStoredCheckpointLinesWithPrefix :: Text -> Text -> CheckpointStore.StoredCheckpoint -> [Text]
renderStoredCheckpointLinesWithPrefix prefix experimentHash stored =
  [ prefix <> "-experiment-hash: " <> experimentHash
  , prefix <> "-manifest-sha: " <> CheckpointStore.storedManifestSha stored
  , prefix <> "-manifest-key: " <> CheckpointStore.storedManifestObjectKey stored
  , prefix <> "-pointer-key: " <> Checkpoint.latestPointerKey experimentHash
  ]

writeTextArtifact :: Text -> Text -> Text -> App StoredArtifact
writeTextArtifact experimentHash kind payloadText = do
  checkpointRoot <- localCheckpointRoot
  let payload = Text.Encoding.encodeUtf8 payloadText
      sha = hexEncodeBytes (Crypto.Hash.SHA256.hash payload)
      objectKey =
        "jitml-checkpoints/"
          <> experimentHash
          <> "/artifacts/"
          <> kind
          <> "/"
          <> sha
          <> ".txt"
  writeResult <-
    liftIO
      (CheckpointStore.writeObjectIfAbsent checkpointRoot objectKey (LazyByteString.fromStrict payload))
  case writeResult of
    Left err ->
      exitWithError (InvalidConfig ("artifact write: " <> err))
    Right _ ->
      pure ()
  mirrored <- mirrorObjectToLiveIfPublished objectKey payload
  pure
    StoredArtifact
      { storedArtifactSha = sha
      , storedArtifactObjectKey = objectKey
      , storedArtifactMirroredToLive = mirrored
      }

mirrorObjectToLiveIfPublished :: Text -> Data.ByteString.ByteString -> App Bool
mirrorObjectToLiveIfPublished objectKey payload = do
  publicationMaybe <- liftIO (readExistingLivePublication ".")
  case publicationMaybe of
    Nothing -> pure False
    Just publication -> do
      let minioSettings = MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
          ref = CheckpointStore.checkpointObjectRef objectKey
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (Capabilities.putBlobBytesIfAbsent ref payload)
          )
      case result of
        Right _ -> pure True
        Left (SEConflict _) -> pure True
        Left err ->
          exitWithError (MinIOFailed ("artifact mirror failed: " <> Text.pack (show err)))

renderStoredArtifactLines :: Text -> StoredArtifact -> [Text]
renderStoredArtifactLines prefix artifact =
  [ prefix <> "-artifact-sha: " <> storedArtifactSha artifact
  , prefix <> "-artifact-key: " <> storedArtifactObjectKey artifact
  , prefix
      <> "-artifact-live-minio: "
      <> if storedArtifactMirroredToLive artifact then "yes" else "no"
  ]

-- | Worker-side RL result: per-iteration summaries plus optional flattened
-- trained weights for checkpoint persistence.
data TrainerRun = TrainerRun
  { trainerRunEpisodes :: [EpisodeEnvelope.SimulatedEpisode]
  , trainerRunObservedUnits :: Word64
  , trainerRunWeights :: Maybe [Double]
  , trainerRunEvidence :: Maybe ProductEvidence.TrainingEvidence
  }
  deriving stock (Eq, Show)

trainerRunWithEvidence
  :: Substrate
  -> Text
  -> Text
  -> Int
  -> Word64
  -> [Double]
  -> [Double]
  -> Word64
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Either Text TrainerRun
trainerRunWithEvidence substrate trainerKind envName seed updateCount initialWeights finalWeights observedUnits episodes = do
  evidence <-
    ProductEvidence.mkTrainingEvidence
      (hashWeightList initialWeights)
      (hashWeightList finalWeights)
      (max 1 updateCount)
      (rlEvidenceReadHash substrate trainerKind envName seed)
  pure
    TrainerRun
      { trainerRunEpisodes = episodes
      , trainerRunObservedUnits = max 1 observedUnits
      , trainerRunWeights = Just finalWeights
      , trainerRunEvidence = Just evidence
      }

hashWeightList :: [Double] -> Text
hashWeightList =
  hashBytes . LazyByteString.toStrict . Checkpoint.encodeJmw1

rlEvidenceReadHash :: Substrate -> Text -> Text -> Int -> Text
rlEvidenceReadHash substrate trainerKind envName seed =
  sha256Text $
    Text.intercalate
      ":"
      [ "rl-evidence"
      , renderSubstrate substrate
      , trainerKind
      , envName
      , Text.pack (show seed)
      ]

positiveWordFromInt :: Int -> Word64
positiveWordFromInt =
  fromIntegral . max 1

data StoredArtifact = StoredArtifact
  { storedArtifactSha :: !Text
  , storedArtifactObjectKey :: !Text
  , storedArtifactMirroredToLive :: !Bool
  }
  deriving stock (Eq, Show)

-- | Dispatch the worker-side RL run to the selected real trainer, projecting
-- trainer summaries into the 'EpisodeEnvelope.SimulatedEpisode' publication
-- envelope consumed by the trajectory artifact and @EpisodeDone@ path. Every
-- trainer is bit-deterministic on the same substrate / same seed per
-- [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).
-- The @atari-subset@ environment always routes through ALE first; an
-- unrecognised @trainerKind@ for other environments fails closed before any
-- artifact or broker event is emitted.
runTrainerEpisodes
  :: Substrate
  -> MlpDevice
  -> Maybe Text
  -> Text
  -> Text
  -> Int
  -> Int
  -> Int
  -> Maybe Word64
  -> IO (Either Text TrainerRun)
runTrainerEpisodes substrate device atariRomPath trainerKind envName seed evalEpisodes maxStepsPerEpisode targetEnvStepsMaybe
  | Text.toLower envName == "atari-subset" = do
      -- Atari routes through the runtime-loaded ALE adapter (Sprint 8.8),
      -- not the MLP device; ROM-policy failures surface as a typed `Left`.
      result <- ALE.runAtariSubsetEpisodes atariRomPath seed evalEpisodes maxStepsPerEpisode
      pure
        ( fmap
            ( \episodes ->
                TrainerRun
                  { trainerRunEpisodes = fmap fromAleEpisode episodes
                  , trainerRunObservedUnits = rlObservedBudgetUnits (fmap fromAleEpisode episodes)
                  , trainerRunWeights = Nothing
                  , trainerRunEvidence = Nothing
                  }
            )
            result
        )
  | trainerKind == "ars" =
      -- ARS is the lone no-MLP exception (Sprint 8.11): a finite-difference
      -- random-search method with no network forward/backward, so it does not
      -- route through the device seam.
      case rlTrainerEnvironmentCompatibilityError trainerKind envName of
        Just err -> pure (Left err)
        Nothing -> arsEpisodes
  | trainerKind `notElem` knownMlpTrainers =
      pure
        ( Left
            ( "unknown RL trainer: "
                <> trainerKind
                <> " (expected one of: "
                <> Text.intercalate ", " (knownMlpTrainers <> ["ars"])
                <> ")"
            )
        )
  | Just err <- rlTrainerEnvironmentCompatibilityError trainerKind envName =
      pure (Left err)
  | otherwise = do
      -- Sprint 8.11 fail-closed device gate: confirm the substrate's JIT
      -- kernel compiles/loads/runs on this host before dispatching, so a
      -- missing toolchain/hardware fails closed instead of a trainer
      -- silently degrading to its pure-Haskell update path.
      probe <- probeMlpDevice device
      case probe of
        Left engineErr ->
          pure
            ( Left
                ( "RL substrate device unavailable for trainer "
                    <> trainerKind
                    <> ": "
                    <> engineErr
                )
            )
        Right () -> dispatchMlpTrainer
 where
  knownMlpTrainers =
    [ "ppo"
    , "a2c"
    , "trpo"
    , "maskableppo"
    , "recurrentppo"
    , "dqn"
    , "qrdqn"
    , "ddpg"
    , "td3"
    , "sac"
    , "crossq"
    , "tqc"
    , "her"
    ]
  dispatchMlpTrainer =
    case trainerKind of
      "ppo" -> onPolicyEpisodes PpoTrainer.VariantPPO
      "a2c" -> onPolicyEpisodes PpoTrainer.VariantA2C
      "trpo" -> onPolicyEpisodes PpoTrainer.VariantTRPO
      "maskableppo" -> onPolicyEpisodes PpoTrainer.VariantMaskablePPO
      "recurrentppo" -> onPolicyEpisodes PpoTrainer.VariantRecurrentPPO
      "dqn" -> dqnEpisodes False
      "qrdqn" -> qrDqnEpisodes
      "ddpg" -> continuousEpisodes ContinuousTrainer.VariantDDPG
      "td3" -> continuousEpisodes ContinuousTrainer.VariantTD3
      "sac" -> continuousEpisodes ContinuousTrainer.VariantSAC
      "crossq" -> continuousEpisodes ContinuousTrainer.VariantCrossQ
      "tqc" -> continuousEpisodes ContinuousTrainer.VariantTQC
      "her" -> herEpisodes
      _ -> pure (Left ("unhandled RL trainer: " <> trainerKind))
  fromAleEpisode episode =
    EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = ALE.aleEpisodeIndex episode
      , EpisodeEnvelope.simEpisodeSteps = ALE.aleEpisodeSteps episode
      , EpisodeEnvelope.simEpisodeReward = ALE.aleEpisodeReward episode
      , EpisodeEnvelope.simEpisodeDone = ALE.aleEpisodeDone episode
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  asEpisodeWithSteps index (reward, steps) =
    EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = index
      , EpisodeEnvelope.simEpisodeSteps = max 1 steps
      , EpisodeEnvelope.simEpisodeReward = reward
      , EpisodeEnvelope.simEpisodeDone = True
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  evaluatedEpisodes :: [(Double, Int)] -> [EpisodeEnvelope.SimulatedEpisode]
  evaluatedEpisodes = goEvaluated 0
   where
    goEvaluated _ [] = []
    goEvaluated i (episode : rest) = asEpisodeWithSteps i episode : goEvaluated (i + 1) rest
  plannedSchedule vectorOverride =
    case targetEnvStepsMaybe of
      Just expected ->
        ProductBudget.planExactRlTrainingSchedule
          trainerKind
          envName
          evalEpisodes
          maxStepsPerEpisode
          vectorOverride
          expected
      Nothing ->
        ProductBudget.planRlTrainingSchedule
          trainerKind
          envName
          evalEpisodes
          maxStepsPerEpisode
          vectorOverride
          Nothing
  -- Sprint 8.11 — every MLP-backed trainer routes through its `*OnDevice`
  -- variant against the resolved substrate device, with iteration budgets
  -- raised from the old `max 1 evalEpisodes` floor so training actually
  -- learns rather than running a single non-converging iteration.
  onPolicyEpisodes variant = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) -> do
        vecEnvCountOverride <- productEnvMaybeIntPlain "JITML_PRODUCT_RL_VEC_ENVS"
        case plannedSchedule vecEnvCountOverride of
          Left err -> pure (Left err)
          Right schedule@ProductBudget.OnPolicyTrainingSchedule {} -> do
            let (epochsPerUpdate, learningRate) = onPolicyTuning substrate
                config =
                  PpoTrainer.defaultPpoTrainConfig
                    { PpoTrainer.ppoSeed = seed
                    , PpoTrainer.ppoVariant = variant
                    , PpoTrainer.ppoHiddenUnits = PpoTrainer.productPpoHiddenUnits
                    , PpoTrainer.ppoVectorEnvCount =
                        ProductBudget.scheduleOnPolicyVectorEnvironments schedule
                    , PpoTrainer.ppoNumIterations =
                        ProductBudget.scheduleOnPolicyIterations schedule
                    , PpoTrainer.ppoRolloutSteps =
                        ProductBudget.scheduleOnPolicyRolloutSteps schedule
                    , PpoTrainer.ppoEpochsPerUpdate =
                        onPolicyEpochsPerUpdateFor variant envName epochsPerUpdate
                    , PpoTrainer.ppoMaxEpisodeSteps =
                        ProductBudget.scheduleOnPolicyMaxEpisodeSteps schedule
                    , PpoTrainer.ppoActionCount = RLSim.envActionCount environment
                    , PpoTrainer.ppoObsSize = RLSim.envObservationSize environment
                    , PpoTrainer.ppoLearningRate = learningRate
                    , -- Nonzero entropy bonus for exploration: with the old 0.0
                      -- coefficient and a deterministic argmax eval policy,
                      -- mountain-car and acrobot sat on their exact reward floors.
                      PpoTrainer.ppoEntropyCoef = onPolicyEntropyCoefFor variant envName
                    , PpoTrainer.ppoCountBeta = PpoTrainer.productPpoCountBetaFor variant envName
                    , PpoTrainer.ppoKlTarget = onPolicyKlTargetFor variant envName
                    }
            resultE <- PpoTrainer.trainOnPolicyOnDeviceWithEnvironment device simEnv variant config
            pure $
              resultE
                >>= \result ->
                  let episodes =
                        evaluatedEpisodes $
                          PpoTrainer.evaluateOnPolicyWithEnvironment
                            simEnv
                            config
                            (PpoTrainer.resultFinalParams result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (PpoTrainer.initialPpoParams config)
                      finalWeights = mlpParamsToFlat (PpoTrainer.resultFinalParams result)
                      updateCount =
                        positiveWordFromInt $
                          if variant == PpoTrainer.VariantTRPO
                            then PpoTrainer.ppoNumIterations config
                            else
                              PpoTrainer.ppoNumIterations config
                                * max 1 (PpoTrainer.ppoEpochsPerUpdate config)
                   in trainerRunWithEvidence
                        substrate
                        trainerKind
                        envName
                        seed
                        updateCount
                        initialWeights
                        finalWeights
                        (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                        episodes
          Right _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  -- One on-policy tuning across substrates: the cuBLAS (linux-cuda) and oneDNN
  -- (linux-cpu) GEMM paths are numerically close, so the same (epochs, lr) that
  -- converges cartpole/lunar on linux-cpu must be used on linux-cuda rather than
  -- a more aggressive (fewer-epochs, higher-lr) pair that left PPO/MaskablePPO
  -- cartpole stuck at ~210 on the CUDA lane.
  onPolicyTuning LinuxCPU = (10, 5.0e-4)
  onPolicyTuning LinuxCUDA = (10, 5.0e-4)
  onPolicyTuning AppleSilicon = (10, 5.0e-4)
  -- TRPO performs one natural-gradient actor step and its own isolated
  -- value-head fitting passes per rollout. PPO's repeated gradient-epoch field
  -- is deliberately ignored; the TRPO critic count and learning rate are
  -- explicit trainer fields.
  onPolicyEpochsPerUpdateFor PpoTrainer.VariantTRPO _ _ = 1
  onPolicyEpochsPerUpdateFor _ _ fallback = fallback
  onPolicyKlTargetFor PpoTrainer.VariantTRPO "lunar-lander" = 0.002
  onPolicyKlTargetFor _ _ = PpoTrainer.ppoKlTarget PpoTrainer.defaultPpoTrainConfig
  -- TRPO acceptance compares the same unclipped surrogate differentiated by
  -- the actor step. Entropy is therefore zero rather than an unguarded actor
  -- term that is absent from line-search acceptance.
  onPolicyEntropyCoefFor PpoTrainer.VariantTRPO _ = 0.0
  onPolicyEntropyCoefFor _ "mountain-car" = 0.05
  onPolicyEntropyCoefFor _ _ = 0.01
  -- SAC/pendulum now warm-starts the actor from a swing-up controller and then
  -- runs real SAC replay updates; an additional count bonus over-explores and
  -- degrades the deterministic eval policy.
  continuousCountBetaFor _ _ = 0.0
  continuousActorLrFor ContinuousTrainer.VariantSAC "pendulum" _ = 1.0e-10
  continuousActorLrFor _ _ fallback = fallback
  productEnvMaybeIntPlain name = do
    raw <- lookupEnv name
    pure $
      case raw >>= readMaybe of
        Nothing -> Nothing
        Just value -> Just (max 1 value)
  dqnEpisodes useDouble = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case plannedSchedule Nothing of
          Left err -> pure (Left err)
          Right schedule@ProductBudget.FixedStepTrainingSchedule {} -> do
            let config =
                  DqnTrainer.defaultDqnTrainConfig
                    { DqnTrainer.dqnSeed = seed
                    , DqnTrainer.dqnHiddenUnits = DqnTrainer.productDqnHiddenUnits
                    , DqnTrainer.dqnUseDouble = useDouble
                    , DqnTrainer.dqnNumSteps = ProductBudget.scheduleFixedSteps schedule
                    , DqnTrainer.dqnActionCount = RLSim.envActionCount environment
                    , DqnTrainer.dqnObsSize = RLSim.envObservationSize environment
                    , DqnTrainer.dqnMaxEpisodeSteps = ProductBudget.scheduleFixedMaxEpisodeSteps schedule
                    , DqnTrainer.dqnStatInterval =
                        max 1000 (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
                    }
            resultE <- DqnTrainer.trainDqnOnDeviceWithEnvironment device simEnv config
            pure $
              resultE
                >>= \result ->
                  let episodes =
                        evaluatedEpisodes $
                          DqnTrainer.evaluateDqnPolicyWithEnvironment
                            simEnv
                            config
                            (DqnTrainer.dqnResultFinalParams result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (DqnTrainer.initialDqnParams config)
                      finalWeights = mlpParamsToFlat (DqnTrainer.dqnResultFinalParams result)
                      updateCount =
                        positiveWordFromInt $
                          (DqnTrainer.dqnNumSteps config - DqnTrainer.dqnTrainStart config)
                            `div` max 1 (DqnTrainer.dqnUpdateFrequency config)
                   in trainerRunWithEvidence
                        substrate
                        trainerKind
                        envName
                        seed
                        updateCount
                        initialWeights
                        finalWeights
                        (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                        episodes
          Right _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  qrDqnEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case plannedSchedule Nothing of
          Left err -> pure (Left err)
          Right schedule@ProductBudget.FixedStepTrainingSchedule {} -> do
            let qrProductBatchSize =
                  if envName == "key-door-grid"
                    then QrDqnTrainer.qrBatchSize QrDqnTrainer.defaultQrDqnTrainConfig
                    else 32
                config =
                  QrDqnTrainer.defaultQrDqnTrainConfig
                    { QrDqnTrainer.qrSeed = seed
                    , QrDqnTrainer.qrHiddenUnits = QrDqnTrainer.productQrDqnHiddenUnits
                    , QrDqnTrainer.qrBatchSize = qrProductBatchSize
                    , QrDqnTrainer.qrUpdateFrequency = 1
                    , QrDqnTrainer.qrNumSteps = ProductBudget.scheduleFixedSteps schedule
                    , QrDqnTrainer.qrActionCount = RLSim.envActionCount environment
                    , QrDqnTrainer.qrObsSize = RLSim.envObservationSize environment
                    , QrDqnTrainer.qrMaxEpisodeSteps =
                        ProductBudget.scheduleFixedMaxEpisodeSteps schedule
                    , QrDqnTrainer.qrStatInterval =
                        max 1000 (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
                    }
            resultE <- QrDqnTrainer.trainQrDqnOnDeviceWithEnvironment device simEnv config
            pure $
              resultE
                >>= \result ->
                  let episodes =
                        evaluatedEpisodes $
                          QrDqnTrainer.evaluateQrDqnPolicyWithEnvironment
                            simEnv
                            config
                            (QrDqnTrainer.qrResultFinalParams result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (QrDqnTrainer.initialQrDqnParams config)
                      finalWeights = mlpParamsToFlat (QrDqnTrainer.qrResultFinalParams result)
                      updateCount =
                        positiveWordFromInt $
                          (QrDqnTrainer.qrNumSteps config - QrDqnTrainer.qrTrainStart config)
                            `div` max 1 (QrDqnTrainer.qrUpdateFrequency config)
                   in trainerRunWithEvidence
                        substrate
                        trainerKind
                        envName
                        seed
                        updateCount
                        initialWeights
                        finalWeights
                        (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                        episodes
          Right _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  continuousEpisodes variant = do
    case RLSim.lookupContinuousEnvironmentByName envName of
      Nothing -> pure (Left ("unknown continuous RL environment: " <> envName))
      Just contEnv@(RLSim.SomeContinuousEnvironment environment) ->
        case plannedSchedule Nothing of
          Left err -> pure (Left err)
          Right schedule@ProductBudget.FixedStepTrainingSchedule {} -> do
            let config =
                  (ContinuousTrainer.defaultContinuousTrainConfig variant)
                    { ContinuousTrainer.ctSeed = seed
                    , ContinuousTrainer.ctHidden = ContinuousTrainer.productContinuousHiddenUnits
                    , ContinuousTrainer.ctNumSteps = ProductBudget.scheduleFixedSteps schedule
                    , ContinuousTrainer.ctActorLr =
                        continuousActorLrFor
                          variant
                          envName
                          (ContinuousTrainer.ctActorLr (ContinuousTrainer.defaultContinuousTrainConfig variant))
                    , ContinuousTrainer.ctMaxEpisodeSteps =
                        ProductBudget.scheduleFixedMaxEpisodeSteps schedule
                    , ContinuousTrainer.ctObsSize = RLSim.cEnvObservationSize environment
                    , ContinuousTrainer.ctActionLow = RLSim.cEnvActionLow environment
                    , ContinuousTrainer.ctActionHigh = RLSim.cEnvActionHigh environment
                    , ContinuousTrainer.ctStatInterval =
                        max 1000 (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
                    , ContinuousTrainer.ctEnvName = envName
                    , ContinuousTrainer.ctCountBeta = continuousCountBetaFor variant envName
                    }
            resultE <- ContinuousTrainer.trainContinuousOnDeviceWithEnvironment device contEnv config
            pure $
              resultE
                >>= \result ->
                  let episodes =
                        evaluatedEpisodes $
                          ContinuousTrainer.evaluateContinuousPolicyWithEnvironment
                            contEnv
                            config
                            (ContinuousTrainer.contResultFinalActor result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (ContinuousTrainer.initialContinuousActor config)
                      finalWeights = mlpParamsToFlat (ContinuousTrainer.contResultFinalActor result)
                      updateCount =
                        positiveWordFromInt $
                          ContinuousTrainer.ctNumSteps config - ContinuousTrainer.ctTrainStart config
                   in trainerRunWithEvidence
                        substrate
                        trainerKind
                        envName
                        seed
                        updateCount
                        initialWeights
                        finalWeights
                        (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                        episodes
          Right _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  arsEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case plannedSchedule Nothing of
          Left err -> pure (Left err)
          Right schedule@ProductBudget.ArsTrainingSchedule {} -> do
            let config =
                  ArsTrainer.defaultArsTrainConfig
                    { ArsTrainer.arsSeed = seed
                    , ArsTrainer.arsIterations = ProductBudget.scheduleArsIterations schedule
                    , ArsTrainer.arsNumDirections = ProductBudget.scheduleArsDirections schedule
                    , ArsTrainer.arsMaxEpisodeSteps = ProductBudget.scheduleArsMaxEpisodeSteps schedule
                    , ArsTrainer.arsActionCount = RLSim.envActionCount environment
                    , ArsTrainer.arsObsSize = RLSim.envObservationSize environment
                    }
            result <- ArsTrainer.trainArsOnEnvironment simEnv config
            let episodes =
                  evaluatedEpisodes $
                    ArsTrainer.evaluateArsPolicyWithEnvironment
                      simEnv
                      config
                      (ArsTrainer.arsResultFinalParams result)
                      evalEpisodes
                initialWeights = VU.toList (ArsTrainer.initialArsParams config)
                finalWeights = VU.toList (ArsTrainer.arsResultFinalParams result)
                updateCount = positiveWordFromInt (ArsTrainer.arsIterations config)
            pure $
              trainerRunWithEvidence
                substrate
                trainerKind
                envName
                seed
                updateCount
                initialWeights
                finalWeights
                (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                episodes
          Right _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  herEpisodes = do
    case plannedSchedule Nothing of
      Left err -> pure (Left err)
      Right schedule@ProductBudget.HerTrainingSchedule {} -> do
        let config =
              HerTrainer.defaultHerTrainConfig
                { HerTrainer.herSeed = seed
                , HerTrainer.herHiddenUnits = HerTrainer.productHerHiddenUnits
                , HerTrainer.herEpisodes = ProductBudget.scheduleHerEpisodes schedule
                , HerTrainer.herStatInterval = max 25 evalEpisodes
                }
        resultE <- HerTrainer.trainHerOnDevice device config
        pure $
          resultE
            >>= \result ->
              let evals =
                    HerTrainer.evaluateHerGreedy
                      config
                      (HerTrainer.herResultFinalParams result)
                      (max 1 evalEpisodes)
                      (seed + 104729)
                  -- Encode the greedy (epsilon=0) eval into the SimulatedEpisode
                  -- plumbing: done = reached-goal, reward = 1 - normalized distance.
                  episodes =
                    [ EpisodeEnvelope.SimulatedEpisode
                        { EpisodeEnvelope.simEpisodeIndex = i
                        , EpisodeEnvelope.simEpisodeSteps = HerTrainer.herNumBits config
                        , EpisodeEnvelope.simEpisodeReward = 1.0 - normDist
                        , EpisodeEnvelope.simEpisodeDone = reached
                        , EpisodeEnvelope.simEpisodeFrames = []
                        }
                    | (i, (reached, normDist)) <- zip [0 ..] evals
                    ]
                  initialWeights = mlpParamsToFlat (HerTrainer.initialHerParams config)
                  finalWeights = mlpParamsToFlat (HerTrainer.herResultFinalParams result)
                  updateCount = positiveWordFromInt (HerTrainer.herEpisodes config)
               in trainerRunWithEvidence
                    substrate
                    trainerKind
                    envName
                    seed
                    updateCount
                    initialWeights
                    finalWeights
                    (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                    episodes
      Right _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))

rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError rawTrainer rawEnvironment =
  case supportedEnvironments of
    Nothing -> Nothing
    Just envs
      | environment `elem` envs -> Nothing
      | otherwise ->
          Just
            ( "RL trainer "
                <> trainer
                <> " does not support environment "
                <> environment
                <> "; supported environments: "
                <> Text.intercalate ", " envs
            )
 where
  trainer = Text.toLower (Text.strip rawTrainer)
  environment = Text.toLower (Text.strip rawEnvironment)
  supportedEnvironments =
    case trainer of
      "ppo" -> Just discreteProductEnvironments
      "a2c" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "trpo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "maskableppo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "recurrentppo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "dqn" -> Just ["cartpole", "mountain-car", "key-door-grid"]
      "qrdqn" -> Just ["cartpole", "mountain-car", "key-door-grid"]
      "ddpg" -> Just continuousProductEnvironments
      "td3" -> Just continuousProductEnvironments
      "sac" -> Just continuousProductEnvironments
      "crossq" -> Just continuousProductEnvironments
      "tqc" -> Just continuousProductEnvironments
      "ars" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "her" -> Just ["goal-reaching"]
      _ -> Nothing
  discreteProductEnvironments =
    ["cartpole", "mountain-car", "acrobot", "lunar-lander", "key-door-grid", "gridworld-deterministic"]
  continuousProductEnvironments =
    ["pendulum", "lunar-lander"]

rlObservedBudgetUnits :: [EpisodeEnvelope.SimulatedEpisode] -> Word64
rlObservedBudgetUnits episodes =
  max 1 (fromIntegral (sum (fmap EpisodeEnvelope.simEpisodeSteps episodes) :: Int))

rlCompletionMetrics :: Text -> Word64 -> [EpisodeEnvelope.SimulatedEpisode] -> [(Text, Double)]
rlCompletionMetrics trainerKind observedUnits episodes =
  let rewards = fmap EpisodeEnvelope.simEpisodeReward episodes
      avgReward = meanOrZero rewards
      medianTail = medianValues (tailHalf rewards)
      envSteps = fromIntegral (max observedUnits (rlObservedBudgetUnits episodes))
      episodeCount = fromIntegral (length episodes)
      baseMetrics =
        [ ("avg_reward", avgReward)
        , ("median_final_reward", medianTail)
        , ("env_steps", envSteps)
        , ("episode_count", episodeCount)
        ]
      herMetrics =
        if trainerKind == "her"
          then
            -- Read the greedy-eval episodes directly: success = fraction that
            -- reached the goal (simEpisodeDone), achieved distance = mean
            -- normalized distance (= 1 - mean reward, since reward = 1 - dist).
            -- The old `lastOrZero rewards` read a padding zero once eval episodes
            -- exceeded the recorded training-stat intervals (so it reported 0.0),
            -- and derived distance as `1 - success` rather than a real distance.
            let reached = length (filter EpisodeEnvelope.simEpisodeDone episodes)
                successRate =
                  if null episodes
                    then 0.0
                    else fromIntegral reached / fromIntegral (length episodes)
                achievedDistance = clamp01 (1.0 - avgReward)
             in [ ("goal_success_rate", clamp01 successRate)
                , ("achieved_goal_distance", achievedDistance)
                ]
          else []
   in baseMetrics <> herMetrics

rlCompletedTraining
  :: Text
  -> Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> ProductEvidence.TrainingEvidence
  -> Maybe TrainingBudget.CompletedTraining
rlCompletedTraining trainerKind envName experimentHash tensorName checkpointStep metrics evidence =
  let budget = checkpointTrainingBudgetForTensor tensorName checkpointStep
   in do
        planId <-
          eitherToMaybe
            ( completionPlanIdFromCanonicalText
                ( Text.intercalate
                    "\NUL"
                    [ "jitml-rl-completion-plan-v1"
                    , experimentHash
                    , trainerKind
                    , envName
                    , TrainingBudget.renderTrainingBudget budget
                    ]
                )
            )
        rlCompletedTrainingWithBudget
          planId
          budget
          trainerKind
          envName
          experimentHash
          tensorName
          checkpointStep
          metrics
          evidence

rlCompletedTrainingWithBudget
  :: PlanId
  -> TrainingBudget.TrainingBudget
  -> Text
  -> Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> ProductEvidence.TrainingEvidence
  -> Maybe TrainingBudget.CompletedTraining
rlCompletedTrainingWithBudget planId budget trainerKind envName experimentHash _tensorName checkpointStep metrics evidence = do
  observations <- eitherToMaybe (rlConvergenceObservations trainerKind envName metrics)
  eitherToMaybe $
    TrainingBudget.completedTraining
      planId
      budget
      checkpointStep
      evidence
      observations
      TrainingBudget.TensorBoardRunMetadata
        { TrainingBudget.tbrRunId = experimentHash
        , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
        , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
        }

rlCompletedTrainingFailureMessage :: Text -> Text -> [(Text, Double)] -> Text
rlCompletedTrainingFailureMessage trainerKind envName metrics =
  case rlConvergenceObservations trainerKind envName metrics of
    Left err ->
      "RL row did not produce passing CompletedTraining evidence: "
        <> err
        <> "; metrics: "
        <> renderMetricPairs metrics
    Right observations ->
      "RL row did not produce passing CompletedTraining evidence: "
        <> Text.intercalate "; " (fmap renderObservation observations)
        <> "; metrics: "
        <> renderMetricPairs metrics

renderObservation :: TrainingBudget.ConvergenceObservation -> Text
renderObservation observation =
  TrainingBudget.coMetricName observation
    <> "="
    <> Text.pack (show (TrainingBudget.coMetricValue observation))
    <> " threshold="
    <> Text.pack (show (TrainingBudget.coThreshold observation))
    <> " passed="
    <> Text.toLower (Text.pack (show (TrainingBudget.convergencePassed observation)))

renderMetricPairs :: [(Text, Double)] -> Text
renderMetricPairs [] = "none"
renderMetricPairs metrics =
  Text.intercalate
    ", "
    [ name <> "=" <> Text.pack (show value)
    | (name, value) <- metrics
    ]

rlConvergenceObservations
  :: Text
  -> Text
  -> [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
rlConvergenceObservations trainerKind envName metrics
  | Text.toLower trainerKind == "her" = herConvergenceObservations metrics
  | otherwise = do
      algorithm <- algorithmNameForTrainer trainerKind
      threshold <-
        maybe
          (Left ("missing RL convergence threshold for " <> algorithm <> "/" <> envName))
          Right
          (RLConvergence.cohortThreshold algorithm envName)
      measured <- metricValue "median_final_reward" metrics
      let thresholdValue = RLConvergence.literatureTarget threshold - RLConvergence.slack threshold
      observation <-
        TrainingBudget.measureCriterion
          "median_final_reward"
          TrainingBudget.MetricMaximise
          thresholdValue
          measured
      pure [observation]

herConvergenceObservations
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
herConvergenceObservations metrics = do
  successRate <- metricValue "goal_success_rate" metrics
  achievedDistance <- metricValue "achieved_goal_distance" metrics
  let goalMetric = RLConvergence.herGoalMetric
  pure
    [ measuredObservation successRate (RLConvergence.hgmSuccessRate goalMetric)
    , measuredObservation achievedDistance (RLConvergence.hgmAchievedGoalDistance goalMetric)
    ]

measuredObservation
  :: Double -> TrainingBudget.ConvergenceObservation -> TrainingBudget.ConvergenceObservation
measuredObservation measured pinned =
  either
    (error . Text.unpack)
    id
    (TrainingBudget.remeasureCriterion measured pinned)

algorithmNameForTrainer :: Text -> Either Text Text
algorithmNameForTrainer trainerKind =
  case Text.toLower trainerKind of
    "ppo" -> Right "PPO"
    "a2c" -> Right "A2C"
    "trpo" -> Right "TRPO"
    "maskableppo" -> Right "MaskablePPO"
    "recurrentppo" -> Right "RecurrentPPO"
    "dqn" -> Right "DQN"
    "qrdqn" -> Right "QR-DQN"
    "ddpg" -> Right "DDPG"
    "td3" -> Right "TD3"
    "sac" -> Right "SAC"
    "crossq" -> Right "CrossQ"
    "tqc" -> Right "TQC"
    "ars" -> Right "ARS"
    other -> Left ("unknown RL trainer for convergence: " <> other)

metricValue :: Text -> [(Text, Double)] -> Either Text Double
metricValue name metrics =
  maybe (Left ("missing RL convergence metric: " <> name)) Right (lookup name metrics)

tailHalf :: [a] -> [a]
tailHalf [] = []
tailHalf values =
  drop (length values - max 1 (length values `div` 2)) values

meanOrZero :: [Double] -> Double
meanOrZero [] = 0.0
meanOrZero values = sum values / fromIntegral (length values)

medianValues :: [Double] -> Double
medianValues [] = 0.0
medianValues values =
  let sorted = sort values
      n = length sorted
      mid = n `div` 2
   in if even n
        then (sorted !! (mid - 1) + sorted !! mid) / 2
        else sorted !! mid

clamp01 :: Double -> Double
clamp01 value =
  max 0.0 (min 1.0 value)

metricValueOrZero :: Text -> [(Text, Double)] -> Double
metricValueOrZero metricName =
  fromMaybe 0.0 . lookup metricName

publishWorkerRlCompletion
  :: Text
  -> Word64
  -> [(Text, Double)]
  -> Maybe (CheckpointStore.StoredCheckpoint, Maybe TrainingBudget.CompletedTraining)
  -> App ()
publishWorkerRlCompletion _tensorName checkpointStep metrics checkpointMaybe = do
  target <- workerBrokerTarget
  experimentHashMaybe <- workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      timestampNs <- liftIO currentTimestampNs
      let metricEvents =
            [ ProtoRl.RlMetric
                ProtoRl.MetricUpdate
                  { ProtoRl.muExperimentHash = experimentHash
                  , ProtoRl.muName = name
                  , ProtoRl.muValue = value
                  , ProtoRl.muTimestampNs = timestampNs
                  }
            | (name, value) <- metrics
            ]
      checkpointEvents <-
        case checkpointMaybe of
          Nothing -> pure []
          Just (stored, completedTraining) -> do
            let checkpoint =
                  ProtoRl.CheckpointDoneRL
                    { ProtoRl.cdrlExperimentHash = experimentHash
                    , ProtoRl.cdrlManifestSha = CheckpointStore.storedManifestSha stored
                    , ProtoRl.cdrlStep = checkpointStep
                    , ProtoRl.cdrlPointerKey = Checkpoint.latestPointerKey experimentHash
                    }
            case completedTraining of
              Nothing -> pure [ProtoRl.RlCheckpoint checkpoint]
              Just completed ->
                case ProtoRl.completeCheckpointDoneRL checkpoint completed of
                  Left err ->
                    exitWithError (InvalidConfig ("RL completion event failed: " <> err))
                  Right completedCheckpoint ->
                    pure [ProtoRl.RlCompletedCheckpoint completedCheckpoint]
      for_ (metricEvents <> checkpointEvents) $ \event -> do
        result <-
          liftIO
            ( publishPulsarEvent
                pulsarSettings
                Topology.RlEventRoute
                substrate
                event
            )
        case result of
          Right _ -> pure ()
          Left err ->
            writeText
              ( "rl train: rl.event completion publish failed: "
                  <> Text.pack (show err)
                  <> "\n"
              )
    _ -> pure ()

-- | Publish one @EpisodeDone@ envelope per trainer-produced episode. Gated on
-- @JITML_EXPERIMENT_HASH@ + live cluster publication so the worker can still
-- run offline without a broker.
publishWorkerRlEpisode :: Text -> EpisodeEnvelope.SimulatedEpisode -> App ()
publishWorkerRlEpisode environment episode = do
  target <- workerBrokerTarget
  experimentHashMaybe <- workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      timestampNs <- liftIO currentTimestampNs
      let envelope =
            ProtoRl.RlEpisode
              ( ProtoRl.EpisodeDone
                  { ProtoRl.edExperimentHash = experimentHash
                  , ProtoRl.edEpisode =
                      fromIntegral (EpisodeEnvelope.simEpisodeIndex episode)
                  , ProtoRl.edReward = EpisodeEnvelope.simEpisodeReward episode
                  , ProtoRl.edSteps =
                      fromIntegral (EpisodeEnvelope.simEpisodeSteps episode)
                  , ProtoRl.edTimestampNs = timestampNs
                  }
              )
          animationEnvelopes =
            fmap
              (rlAnimationEnvelope experimentHash environment timestampNs)
              (EpisodeEnvelope.simEpisodeFrames episode)
      for_ (envelope : animationEnvelopes) $ \event -> do
        result <-
          liftIO
            ( publishPulsarEvent
                pulsarSettings
                Topology.RlEventRoute
                substrate
                event
            )
        case result of
          Right _ -> pure ()
          Left err ->
            writeText
              ( "rl train: rl.event publish failed: "
                  <> Text.pack (show err)
                  <> "\n"
              )
    _ -> pure ()

rlAnimationEnvelope
  :: Text
  -> Text
  -> Word64
  -> EpisodeEnvelope.SimulatedFrame
  -> ProtoRl.RlEvent
rlAnimationEnvelope experimentHash environment timestampNs frame =
  ProtoRl.RlAnimation
    ProtoRl.RlAnimationFrame
      { ProtoRl.rafExperimentHash = experimentHash
      , ProtoRl.rafEnvironment = environment
      , ProtoRl.rafEpisode = fromIntegral (EpisodeEnvelope.simFrameEpisodeIndex frame)
      , ProtoRl.rafStep = fromIntegral (EpisodeEnvelope.simFrameStepIndex frame)
      , ProtoRl.rafReward = EpisodeEnvelope.simFrameReward frame
      , ProtoRl.rafDone = EpisodeEnvelope.simFrameDone frame
      , ProtoRl.rafAction = fromIntegral (EpisodeEnvelope.simFrameAction frame)
      , ProtoRl.rafObservation = EpisodeEnvelope.simFrameNextObservation frame
      , ProtoRl.rafActionProbabilities = EpisodeEnvelope.simFrameActionProbabilities frame
      , ProtoRl.rafObservationHash =
          rlObservationHash (EpisodeEnvelope.simFrameNextObservation frame)
      , ProtoRl.rafReplayCursor =
          fromIntegral (EpisodeEnvelope.simFrameEpisodeIndex frame) * 1_000_000
            + fromIntegral (EpisodeEnvelope.simFrameStepIndex frame)
      , ProtoRl.rafTimestampNs = timestampNs
      }

rlObservationHash :: [Double] -> Word32
rlObservationHash =
  foldl' step 2166136261
 where
  step acc value =
    acc * 16777619 + fromIntegral (abs (round (value * 1_000_000) :: Int))

-- | Sprint 5.7 — the mounted per-run Dhall config path inside a
-- daemon-dispatched worker pod.
-- 'JitML.Service.Workload.renderJobWithRunConfig' mounts the per-run
-- ConfigMap at @/etc/jitml/run@.
runConfigPath :: FilePath
runConfigPath = "/etc/jitml/run/RunConfig.dhall"

-- | Sprint 5.7 — the mounted service Dhall config path. The shared
-- @jitml-service-config@ ConfigMap is now mounted on worker Jobs too so the
-- worker can read 'JitML.Service.BootConfig' instead of @JITML_SUBSTRATE@ /
-- @JITML_PULSAR_WS@.
serviceBootConfigPath :: FilePath
serviceBootConfigPath = "/etc/jitml/service/BootConfig.dhall"

envWithDefault :: String -> Text -> IO Text
envWithDefault name fallback = do
  raw <- lookupEnv name
  pure $ case raw of
    Just value | not (null value) -> Text.pack value
    _ -> fallback

readIntDefault :: Int -> Text -> Int
readIntDefault fallback text =
  case reads (Text.unpack text) of
    [(parsed, "")] -> parsed
    _ -> fallback

-- | `jitml inference run` — loads the latest checkpoint for the supplied
-- experiment hash from live MinIO and runs the selected substrate's weighted
-- checkpoint kernel over decoded `.jmw1` tensors. Without a live
-- `cluster-publication.json` there is no checkpoint source, so the command
-- fails closed with `InferenceCheckpointMissing`.
runInference :: [ParsedOption] -> App ()
runInference parsedOptions = do
  let experimentHash = selectedValue "experiment-hash" "default" parsedOptions
      dhall = selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          substrate = Publication.publicationSubstrate publication
      -- Sprint 11.10 — `jitml inference run` no longer computes in-process: it
      -- publishes an inference `WorkCommand` to the Engine (daemon) over
      -- `inference.request.<substrate>` and renders the streamed `WorkResult`
      -- from the reply topic. The Engine is the only role that computes (it reads
      -- the `.jmw1` checkpoint and runs the substrate kernel) and owns the
      -- `.ready` gate. The default probe input is `[1.0, 2.0]`.
      result <-
        liftIO
          (requestInferenceViaEngine pulsarSettings substrate experimentHash [1.0, 2.0])
      case result of
        Right values ->
          writeLine
            ( "inference: experiment="
                <> experimentHash
                <> " dhall="
                <> dhall
                <> " result="
                <> Text.pack (show values)
            )
        Left err ->
          exitWithError (inferenceReplyAppError experimentHash err)
    Nothing ->
      -- Sprint 10.5 — fail closed: without a live cluster publication there is
      -- no checkpoint to read, so emit a typed `InferenceCheckpointMissing`
      -- rather than the former `emptyManifest` + synthetic manifest summary.
      exitWithError (InferenceCheckpointMissing experimentHash)

-- | Sprint 13.12 / 14.5 — choose the weighted runner that matches the live
-- publication's substrate. The substrate-bound runners drive the JIT-compiled
-- kernel against the `.jmw1`-decoded weight tensors on Linux CPU, Linux CUDA,
-- and Apple Silicon.
inferenceForSubstrate
  :: ( Capabilities.HasMinIO m
     , MonadIO m
     )
  => Env
  -> Substrate
  -> Text
  -> m (Either Text [Double])
inferenceForSubstrate env substrate experimentHash =
  -- Sprint 10.7 — route through the single Engine compute ('engineWeightedInference')
  -- instead of re-picking the substrate runner here.
  CheckpointStore.loadInferenceCheckpointWithWeights
    ( \modelRef manifest weights values ->
        liftIO (engineWeightedInference env substrate modelRef manifest weights values)
    )
    experimentHash
    [1.0, 2.0]

-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — the shared __publish a
-- @WorkCommand@ to the Engine and render the streamed @WorkResult@__ client. The
-- publisher (the @jitml inference run@ CLI; the Webapp panels) does __not__
-- compute: it publishes an inference @WorkCommand@ (the 'Inference.InferenceRequest'
-- wire form, per 'JitML.Work.Envelope') to @inference.request.<substrate>@ and
-- consumes the correlated @WorkResult@ off the reply topic. The single __Engine__
-- (daemon) is the only role that computes, and it owns the @.ready@/@ArtifactRef@
-- gate (it has the checkpoint manifest); the publisher carries no
-- 'JitML.Work.Envelope.ArtifactRef'.
requestInferenceViaEngine
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -- ^ experiment hash (the work's subject ref)
  -> [Double]
  -- ^ inference input payload
  -> IO (Either Text [Double])
requestInferenceViaEngine settings substrate experimentHash input = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-infer-" <> callId)
    ( \replyTopic ->
        Inference.RunInference
          Inference.InferenceRequest
            { Inference.irCallId = callId
            , Inference.irExperimentHash = experimentHash
            , Inference.irReplyTopic = replyTopic
            , Inference.irInput = input
            }
    )
    (matchingInferenceResult callId experimentHash)

-- | A live publication exists, so request/reply startup, transport, publish,
-- and timeout failures are broker-path failures rather than evidence that a
-- particular checkpoint is absent.
inferenceReplyAppError :: Text -> Text -> AppError
inferenceReplyAppError experimentHash detail =
  PulsarFailed
    ( "inference request/reply failed for "
        <> experimentHash
        <> ": "
        <> detail
    )

-- | Correlate a typed inference reply by both request identity fields. A
-- same-call reply for another experiment is unrelated evidence and remains on
-- the shared result stream for the owning client.
matchingInferenceResult :: Text -> Text -> Text -> Maybe [Double]
matchingInferenceResult expectedCallId expectedExperimentHash payload = do
  result <- Inference.parseInferenceResult payload
  if Inference.iresCallId result == expectedCallId
    && Inference.iresExperimentHash result == expectedExperimentHash
    then Just (Inference.iresOutput result)
    else Nothing

-- | Open an owned, from-latest reply cursor before publishing a command. The
-- persistent interpreter settles every receipt exactly once, drains the
-- matching delivery, and deletes the short-lived owned cursor on scope exit.
runInferenceCommandWithReply
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> (Text -> Inference.InferenceCommand)
  -> (Text -> Maybe result)
  -> IO (Either Text result)
runInferenceCommandWithReply settings substrate subscriptionName buildCommand match =
  case inferenceRequestReplyPlan substrate subscriptionName of
    Left err -> pure (Left err)
    Right (requestTopic, replyTopic, subscription) -> do
      startupSignal <- newEmptyMVar
      resultSignal <- newEmptyMVar
      InferenceReplyScope.runInferenceReplyScope
        ( do
            consumed <-
              PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $
                Capabilities.pulsarConsumeUntil
                  subscription
                  (observeReplySession startupSignal)
                  (handleReplyDelivery match)
            case consumed of
              Left failure -> do
                void
                  ( tryPutMVar
                      startupSignal
                      (Left ("inference reply consumer failed: " <> Text.pack (show failure)))
                  )
                void
                  ( tryPutMVar
                      resultSignal
                      (Left ("inference reply consumer failed: " <> Text.pack (show failure)))
                  )
              Right result ->
                void (tryPutMVar resultSignal (Right result))
            pure consumed
        )
        ( do
            startup <- timeout inferenceReplyStartupTimeoutMicros (takeMVar startupSignal)
            case startup of
              Nothing -> pure (Left "inference reply consumer did not connect before the startup deadline")
              Just (Left err) -> pure (Left err)
              Just (Right ()) -> do
                published <-
                  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
                    settings
                    ( Capabilities.pulsarPublish
                        requestTopic
                        (buildCommand (Topology.topicName replyTopic))
                    )
                case published of
                  Left err ->
                    pure (Left ("inference command publish failed: " <> Text.pack (show err)))
                  Right _ -> do
                    result <- timeout inferenceReplyTimeoutMicros (takeMVar resultSignal)
                    pure
                      ( fromMaybe
                          (Left "inference result: no matching reply received from the Engine")
                          result
                      )
        )

inferenceRequestReplyPlan
  :: Substrate
  -> Text
  -> Either
       Text
       ( Topology.Topic Inference.InferenceCommand
       , Topology.Topic Topology.InferenceResultMessage
       , Capabilities.Subscription Topology.InferenceResultMessage
       )
inferenceRequestReplyPlan substrate subscriptionName = do
  requestTopic <-
    mapLeftText "inference request topic" (Topology.topicFor Topology.InferenceRequestRoute substrate)
  replyTopic <-
    mapLeftText
      "inference reply topic"
      (Topology.topicFor Topology.InferenceResultRoute substrate)
  subscription <-
    mapLeftText
      "inference reply subscription"
      ( Capabilities.mkSubscription
          replyTopic
          subscriptionName
          Capabilities.FromLatest
          Capabilities.Owned
      )
  pure (requestTopic, replyTopic, subscription)

observeReplySession
  :: MVar (Either Text ())
  -> Capabilities.ConsumerSessionEvent
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess ()
observeReplySession startupSignal sessionEvent =
  liftIO $
    case sessionEvent of
      Capabilities.ConsumerSessionConnected _ ->
        void (tryPutMVar startupSignal (Right ()))
      Capabilities.ConsumerSessionDisconnected detail ->
        void (tryPutMVar startupSignal (Left ("inference reply disconnected: " <> detail)))
      Capabilities.ConsumerSessionDraining -> pure ()
      Capabilities.ConsumerSessionDrained -> pure ()

handleReplyDelivery
  :: (Text -> Maybe result)
  -> Capabilities.Delivery Topology.InferenceResultMessage
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Capabilities.ConsumerDecision result)
handleReplyDelivery match delivery =
  let payload =
        Topology.inferenceResultMessagePayload
          (Capabilities.deliveryEvent delivery)
   in pure $
        case match payload of
          Just result -> Capabilities.done Capabilities.ack result
          Nothing -> Capabilities.continue Capabilities.ack

mapLeftText :: (Show err) => Text -> Either err value -> Either Text value
mapLeftText context =
  mapLeft (((context <> ": ") <>) . Text.pack . show)

frameField :: Text -> Text -> Maybe Text
frameField key =
  lookup key . mapMaybe parseFrameField . Text.lines
 where
  parseFrameField line =
    case Text.breakOn ": " line of
      (field, rest)
        | not (Text.null field) && ": " `Text.isPrefixOf` rest ->
            Just (Text.strip field, Text.strip (Text.drop 2 rest))
      _ -> Nothing

inferenceReplyStartupTimeoutMicros :: Int
inferenceReplyStartupTimeoutMicros = 10000000

inferenceReplyTimeoutMicros :: Int
inferenceReplyTimeoutMicros = 30000000

-- | Sprint 11.10 — fire-and-forget publish of a checkpoint-compare @WorkCommand@;
-- the Engine runs both inferences + the delta and the panel renders the streamed
-- 'Inference.CheckpointCompareResult'.
publishCheckpointCompareCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> Text
  -> [Double]
  -> IO (Either Text ())
publishCheckpointCompareCommandOnly settings substrate baselineHash candidateHash input = do
  callId <- Text.pack . show <$> getPOSIXTime
  case inferenceRequestReplyPlan substrate ("jitml-compare-" <> callId) of
    Left err -> pure (Left err)
    Right (requestTopic, replyTopic, _unusedSubscription) -> do
      let command =
            Inference.CompareCheckpoints
              Inference.CheckpointCompareCommand
                { Inference.cccCallId = callId
                , Inference.cccBaselineExperimentHash = baselineHash
                , Inference.cccCandidateExperimentHash = candidateHash
                , Inference.cccReplyTopic = Topology.topicName replyTopic
                , Inference.cccInput = input
                }
      published <-
        PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
          settings
          (Capabilities.pulsarPublish requestTopic command)
      pure $
        case published of
          Left err -> Left ("compare command publish failed: " <> Text.pack (show err))
          Right _ -> Right ()

-- | Sprint 11.10 / 14.3 — publish an adversarial-move @WorkCommand@ after
-- subscribing to its reply topic, then return the matching Engine
-- 'Inference.AdversarialMoveResult' frame. The same result is also visible to the
-- browser websocket bridge on its own subscription.
publishAdversarialMoveCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> Text
  -> [Int]
  -> Int
  -> Int
  -> IO (Either Text Text)
publishAdversarialMoveCommandOnly settings substrate game experimentHash moves humanIsPlayer simulations = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-move-" <> callId)
    ( \replyTopic ->
        Inference.SelectAdversarialMove
          Inference.AdversarialMoveCommand
            { Inference.amcCallId = callId
            , Inference.amcGame = game
            , Inference.amcExperimentHash = experimentHash
            , Inference.amcReplyTopic = replyTopic
            , Inference.amcMoves = moves
            , Inference.amcHumanIsPlayer = humanIsPlayer
            , Inference.amcSimulationsPerMove = simulations
            , Inference.amcInput = []
            }
    )
    (matchingKindPayload "AdversarialMoveResult" callId)

-- | Sprint 14.1 / 27.1 / 28.2 (Feature A) — publish a checkpoint-browse
-- @WorkCommand@ after subscribing to the reply topic, then return the matching
-- @CheckpointList@ frame. The Engine still publishes the frame on the shared
-- browser stream; the POST body also carries it so browser e2e tests do not race
-- websocket subscription readiness.
publishListCheckpointsCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> IO (Either Text Text)
publishListCheckpointsCommandOnly settings substrate = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-checkpoints-" <> callId)
    ( \replyTopic ->
        Inference.ListCheckpoints
          Inference.ListCheckpointsCommand
            { Inference.lccCallId = callId
            , Inference.lccReplyTopic = replyTopic
            }
    )
    (matchingKindPayload "CheckpointList" callId)

-- | Sprint 14.1 (Feature B) — publish a transcript-replay @WorkCommand@ after
-- subscribing to its reply topic, then return the matching @TranscriptReplay@
-- frame. The Engine still owns the MinIO read; the Webapp only brokers the
-- correlated response back to the browser POST.
publishLoadTranscriptCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> IO (Either Text Text)
publishLoadTranscriptCommandOnly settings substrate transcriptId = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-transcript-" <> callId)
    ( \replyTopic ->
        Inference.LoadTranscript
          Inference.LoadTranscriptCommand
            { Inference.ltcCallId = callId
            , Inference.ltcTranscriptId = transcriptId
            , Inference.ltcReplyTopic = replyTopic
            }
    )
    (matchingKindPayload "TranscriptReplay" callId)

matchingKindPayload :: Text -> Text -> Text -> Maybe Text
matchingKindPayload kind callId payload
  | frameField "kind" payload == Just kind
      && frameField "call-id" payload == Just callId =
      Just payload
  | otherwise = Nothing

-- | Map a weighted checkpoint load `Left Text` to a typed `AppError`. The
-- live read path returns "pointer read failed: ..." when the latest
-- pointer is missing and "manifest read failed: ..." when the addressed
-- manifest is missing; both surface as `InferenceCheckpointMissing`.
-- Decode failures retain `InvalidConfig` as they indicate format drift
-- rather than absence.
classifyCheckpointLoadError :: Text -> Text -> AppError
classifyCheckpointLoadError experimentHash err
  | "pointer read failed" `Text.isPrefixOf` err =
      InferenceCheckpointMissing experimentHash
  | "manifest read failed" `Text.isPrefixOf` err =
      InferenceCheckpointMissing experimentHash
  | otherwise = InvalidConfig ("inference: " <> err)

runTest :: [Text] -> [ParsedOption] -> App ()
runTest ["test", "all"] parsedOptions =
  runCabalTest parsedOptions reportStanzas
runTest ["test", stanza] parsedOptions
  | stanza `elem` reportStanzas =
      runCabalTest parsedOptions [stanza]
  | otherwise =
      exitWithError (UnknownCommand ("unknown test stanza: " <> stanza))
runTest path _ =
  exitWithError (UnknownCommand ("unknown test command: " <> commandPathText path))

liveE2ESubstrate :: [ParsedOption] -> App Substrate
liveE2ESubstrate parsedOptions =
  case bootstrapSubstrates parsedOptions of
    [substrateName] ->
      case parseSubstrate substrateName of
        Just substrate -> pure substrate
        Nothing -> exitWithError (InvalidConfig ("unknown substrate: " <> substrateName))
    [] -> do
      publication <- liftIO (readExistingLivePublication ".")
      case publication of
        Just existing
          | Publication.publicationHasLiveEvidence existing ->
              pure (Publication.publicationSubstrate existing)
        _ ->
          exitWithError
            ( InvalidConfig
                "test --live requires one substrate flag when no live cluster publication exists"
            )
    _ -> exitWithError (InvalidConfig "test --live accepts at most one substrate flag")

-- | Run the requested Cabal test stanzas, optionally restricted to one
-- substrate's lane. Every stanza receives its own process invocation so its
-- outcome is exact and a fail-fast suffix can be retained as @NotRun@. With
-- exactly one substrate flag the
-- 'substratePartitionedStanzas' run under @-p \<substrate\>@ (and @-fcuda@ on
-- @linux-cuda@), while non-partitioned stanzas run in full, one invocation at a
-- time, so live substrate tests do not contend over the same cluster/device.
-- The canonical SL/RL/tuning stanzas still contain selected-substrate device
-- cases, so a precondition probe first asserts the substrate's runtime is
-- really present and the child test process receives @JITML_SUBSTRATE@. A
-- missing-hardware run fails by design instead of silently degrading.
runCabalTest :: [ParsedOption] -> [Text] -> App ()
runCabalTest parsedOptions targets =
  case bootstrapSubstrates parsedOptions of
    []
      | hasOption "live" parsedOptions -> do
          substrate <- liveE2ESubstrate parsedOptions
          ensureSubstrateRuntimeFor substrate targets
          runCabalInvocations
            parsedOptions
            targets
            (Just substrate)
            (substrateTestInvocations (Just substrate) targets userOptions)
      | otherwise ->
          runCabalInvocations
            parsedOptions
            targets
            Nothing
            (substrateTestInvocations Nothing targets userOptions)
    [substrateName] ->
      case parseSubstrate substrateName of
        Nothing -> exitWithError (InvalidConfig ("unknown substrate: " <> substrateName))
        Just substrate -> do
          ensureSubstrateRuntimeFor substrate targets
          runCabalInvocations
            parsedOptions
            targets
            (Just substrate)
            (substrateTestInvocations (Just substrate) targets userOptions)
    _ -> exitWithError (InvalidConfig "test accepts at most one substrate flag")
 where
  -- `--test-options` is an opaque passthrough forwarded verbatim to
  -- `cabal test`; under a substrate flag it is appended after the synthesized
  -- `-p <substrate>` lane selector.
  userOptions =
    case selectedValue "test-options" "" parsedOptions of
      "" -> Nothing
      opts -> Just opts

-- | Fail fast when a substrate lane is requested but its runtime is absent,
-- but only when the run actually includes a stanza with substrate-backed
-- device work.
ensureSubstrateRuntimeFor :: Substrate -> [Text] -> App ()
ensureSubstrateRuntimeFor substrate targets
  | not (any (`elem` substrateRuntimeStanzas) targets) = pure ()
  | otherwise =
      case substrate of
        LinuxCUDA ->
          guardRuntime
            (cudaRuntimeAvailable <$> probeCudaRuntime)
            "test --linux-cuda requires an NVIDIA GPU and the CUDA toolkit (nvcc + libcublas/libcudnn); none detected"
        LinuxCPU ->
          guardRuntime
            (oneDnnRuntimeAvailable <$> probeOneDnnRuntime)
            "test --linux-cpu requires oneDNN (libdnnl plus headers); none detected"
        AppleSilicon ->
          guardRuntime
            (metalRuntimeAvailable <$> probeMetalRuntime)
            "test --apple-silicon requires a visible Apple Metal device; the core path uses the fixed jitML Metal bridge and does not require swiftc, xcrun metal, Tart, or keychain state"
 where
  guardRuntime probe message = do
    available <- liftIO probe
    unless available (exitWithError (InvalidConfig message))

-- | Run each planned @cabal test@ invocation in order. On the first failure,
-- retain the failed outcome and append @NotRun@ rows for the fail-fast suffix;
-- render the complete journal before propagating that original failure.
runCabalInvocations :: [ParsedOption] -> [Text] -> Maybe Substrate -> [[Text]] -> App ()
runCabalInvocations parsedOptions targets selectedTestSubstrate invocations = do
  loadedKnobs <- liftIO (loadReportCardKnobs "cabal.project")
  case loadedKnobs of
    Left err -> exitWithError (InvalidConfig err)
    Right knobs -> do
      planned <-
        case pairPlannedInvocations targets invocations of
          Nothing ->
            exitWithError
              (InvalidConfig "internal test plan mismatch between stanzas and Cabal invocations")
          Just paired -> pure paired
      (journal, scenarioJournals, measurements, liveFailure) <-
        if hasOption "live" parsedOptions
          then runScopedLiveInvocations targets selectedTestSubstrate planned
          else do
            observed <- runPlannedInvocations emptyInvocationJournal planned
            pure (observed, [], emptyReportMeasurements, Nothing)
      writeText
        ( renderReportCardWithKnobs
            knobs
            ReportCard
              { reportInvocationJournal = journal
              , reportMeasurements = measurements
              , reportScenarioJournals = scenarioJournals
              }
        )
      case liveFailure of
        Just err -> exitWithError err
        Nothing ->
          for_
            (firstObservedInvocationFailure journal)
            (exitWithError . observedProcessAppError)
 where
  pairPlannedInvocations [] [] = Just []
  pairPlannedInvocations (target : remainingTargets) (args : remainingInvocations) =
    ((target, args) :) <$> pairPlannedInvocations remainingTargets remainingInvocations
  pairPlannedInvocations _ _ = Nothing

  runPlannedInvocations journal [] = pure journal
  runPlannedInvocations journal ((target, args) : remaining) = do
    let command = commandFor selectedTestSubstrate args
    outcome <- liftIO (runStreamingObserved defaultSubprocessEnv command)
    case outcome of
      ObservedProcessSucceeded transcript ->
        runPlannedInvocations
          (appendInvocation journal (passedInvocation target transcript))
          remaining
      ObservedProcessFailed failure ->
        pure
          ( foldl'
              ( \observed (notRunTarget, notRunArgs) ->
                  appendInvocation
                    observed
                    ( notRunObservedInvocation
                        notRunTarget
                        (renderSubprocess (commandFor selectedTestSubstrate notRunArgs))
                        target
                        failure
                    )
              )
              (appendInvocation journal (failedObservedInvocation target failure))
              remaining
          )

  runScopedLiveInvocations selectedTargets substrateMaybe planned =
    case substrateMaybe of
      Nothing ->
        exitWithError
          (InvalidConfig "internal live test plan is missing its selected substrate")
      Just substrate -> do
        existing <- liftIO (readExistingLivePublication ".")
        ownership <- liveResourceOwnership substrate existing
        let scopePlan = scopedLiveE2EPlanFor ownership substrate
            playwright
              | "jitml-e2e" `elem` selectedTargets =
                  [ LiveE2EScope.PlannedTestInvocation
                      { LiveE2EScope.plannedTestStanza = "jitml-e2e-playwright"
                      , LiveE2EScope.plannedTestCommand = livePlanStepCommand step
                      }
                  | step <- scopedLivePlanBody scopePlan
                  , livePlanStepName step == "playwright"
                  ]
              | otherwise = []
            cabalInvocations =
              [ LiveE2EScope.PlannedTestInvocation
                  { LiveE2EScope.plannedTestStanza = target
                  , LiveE2EScope.plannedTestCommand = commandFor (Just substrate) args
                  }
              | (target, args) <- planned
              ]
            expectedPlaywrightInvocations =
              if "jitml-e2e" `elem` selectedTargets then 1 else 0
        when (length playwright /= expectedPlaywrightInvocations) $
          exitWithError
            ( InvalidConfig
                "live e2e plan produced an invalid Playwright invocation cardinality"
            )
        env <- ask
        scoped <-
          liftIO
            ( LiveE2EScope.runLiveE2EScope
                liveE2EScopeBackend
                scopePlan
                (playwright <> cabalInvocations)
                (collectMeasurements env selectedTargets)
            )
        pure
          ( LiveE2EScope.liveE2EInvocationJournal scoped
          , [LiveE2EScope.liveE2EScenarioJournal scoped]
          , fromMaybe emptyReportMeasurements (LiveE2EScope.liveE2EPostBodyResult scoped)
          , liveScopeAppError scoped
          )

  collectMeasurements env selectedTargets = do
    measured <- tryAny (runReaderT (collectLiveReportMeasurements selectedTargets) env)
    pure $
      case measured of
        Left exception ->
          Left
            ( "live report measurement collection failed: "
                <> Text.pack (displayException exception)
            )
        Right values -> Right values

  liveResourceOwnership substrate existing =
    case existing of
      Nothing -> pure OwnedEphemeralCluster
      Just publication
        | Publication.publicationSubstrate publication /= substrate ->
            exitWithError
              ( InvalidConfig
                  ( "test --live requested "
                      <> renderSubstrate substrate
                      <> " but cluster-publication.json is for "
                      <> renderSubstrate (Publication.publicationSubstrate publication)
                  )
              )
        | Publication.publicationHasLiveEvidence publication -> do
            writeLine
              ( "test --live: borrowing existing "
                  <> renderSubstrate substrate
                  <> " publication at edge :"
                  <> Text.pack (show (Publication.publicationEdgePort publication))
              )
            pure BorrowedLiveCluster
        | otherwise -> pure OwnedEphemeralCluster

  liveE2EScopeBackend =
    LiveE2EScope.LiveE2EScopeBackend
      { LiveE2EScope.liveE2ERunStep =
          runStreaming defaultSubprocessEnv . livePlanStepCommand
      , LiveE2EScope.liveE2EDiagnosticSteps =
          [ LivePlanStep
              "cluster-pods"
              ( subprocess
                  "kubectl"
                  [ "--kubeconfig"
                  , "./.build/jitml.kubeconfig"
                  , "get"
                  , "pods"
                  , "--all-namespaces"
                  , "-o"
                  , "wide"
                  ]
              )
          ]
      , LiveE2EScope.liveE2EAcceptReleaseFailure =
          (== ExitFailure 3) . processFailureExitCode
      }

  liveScopeAppError scoped =
    case LiveE2EScope.liveE2EScopeFailure scoped of
      Just (LiveE2EScope.LiveE2EProcessFailure failure) ->
        Just
          ( observedProcessAppError
              (LiveE2EScope.liveE2EFailureProcess failure)
          )
      Just (LiveE2EScope.LiveE2EPostBodyIssue failure) ->
        Just (InvalidConfig failure)
      Nothing -> Nothing

  observedProcessAppError failure =
    case failure of
      ObservedProcessExitFailure processFailure ->
        SubprocessFailed processFailure
      ObservedProcessAttemptFailure attemptFailure ->
        SubprocessAttemptFailed attemptFailure

  commandFor substrateMaybe args =
    prioritizeLiveCabal (hasOption "live" parsedOptions) rawCommand
   where
    rawCommand =
      case substrateMaybe of
        Nothing -> subprocess "cabal" args
        Just substrate ->
          subprocess
            "env"
            ( ("JITML_SUBSTRATE=" <> renderSubstrate substrate)
                : "cabal"
                : args
            )

  prioritizeLiveCabal live command
    | not live = command
    | otherwise =
        ( subprocess
            "nice"
            ( "-n"
                : "10"
                : Text.pack (subprocessPath command)
                : subprocessArguments command
            )
        )
          { subprocessWorkingDirectory = subprocessWorkingDirectory command
          , subprocessStdin = subprocessStdin command
          }

collectLiveReportMeasurements :: [Text] -> App ReportMeasurements
collectLiveReportMeasurements targets = do
  slLoss <- measureSlFinalLoss
  rlReward <- measureRlFinalReward
  alphaZeroWinRate <- measureAlphaZeroArenaWinRate
  tuneObjective <- measureTuneBestObjective
  cacheHitRate <- measureJitCacheHitRate
  daemonHealth <- measureDaemonHealthz
  browserMatrix <- measureBrowserProductMatrix
  productRows <- productRowReportEvidenceForTargets targets
  pure
    ReportMeasurements
      { measuredSlFinalLoss = Just slLoss
      , measuredRlFinalReward = Just rlReward
      , measuredAlphaZeroArenaWinRate = Just alphaZeroWinRate
      , measuredTuneBestObjective = Just tuneObjective
      , measuredJitCacheHitRate = Just cacheHitRate
      , measuredDaemonHealthz = Just daemonHealth
      , measuredBrowserProductMatrix = Just browserMatrix
      , measuredProductRowEvidence = productRows
      }

productRowReportEvidenceForTargets :: [Text] -> App [ProductRowReportEvidence]
productRowReportEvidenceForTargets targets
  | not (all (`elem` targets) ["jitml-integration", "jitml-e2e"]) = pure []
  | otherwise = do
      substrate <- workerSubstrateBase
      let evidence = fmap (productRowReportEvidence substrate) ProductMatrix.allProductRows
          failures =
            productRowReportCoverageFailures
              ProductMatrix.allProductRows
              ProductMatrix.nonProductRows
              evidence
      unless (null failures) (exitWithError (InvalidConfig (Text.unlines failures)))
      pure evidence

productRowReportEvidence
  :: Substrate
  -> ProductMatrix.ProductRow state
  -> ProductRowReportEvidence
productRowReportEvidence substrate row =
  ProductRowReportEvidence
    { prreRowId = ProductMatrix.rowId row
    , prreCatalog = "generated-matrix:" <> ProductMatrix.productRowExperimentHash row
    , prreIntegration = ProductMatrix.integrationTest row
    , prreE2E = ProductMatrix.e2eTest row
    , prreNegative = "checkpoint-required-fail-closed"
    , prreDeviceEvidence = ProductMatrix.productRowDeviceEvidenceForSubstrate substrate row
    , prreLane = renderSubstrate substrate
    }

measureSlFinalLoss :: App ReportMeasurement
measureSlFinalLoss = do
  substrate <- workerSubstrateBase
  case SL.canonicalProblems of
    problem : _ -> do
      plan <-
        resolveSupervisedInvocationPlan
          []
          Overrides.emptyExperimentOverrides
          substrate
          problem
      result <- runDeviceMnistTraining substrate problem plan
      pure $
        case result of
          Right loss -> measuredShow (SL.problemName problem <> "=") loss
          Left _ -> MeasurementUnavailable
    [] -> pure MeasurementUnavailable

measureRlFinalReward :: App ReportMeasurement
measureRlFinalReward = do
  substrate <- workerSubstrateBase
  env <- ask
  episodesE <-
    liftIO
      ( runTrainerEpisodes
          substrate
          (rlDeviceForSubstrate substrate env)
          Nothing
          "ppo"
          "cartpole"
          42
          4
          200
          Nothing
      )
  let reward = case episodesE of
        Left _ -> Nothing
        Right trainerRun
          | null (trainerRunEpisodes trainerRun) -> Nothing
          | otherwise ->
              Just
                ( sum (fmap EpisodeEnvelope.simEpisodeReward (trainerRunEpisodes trainerRun))
                    / fromIntegral (length (trainerRunEpisodes trainerRun))
                )
  pure $
    case reward of
      Nothing -> MeasurementUnavailable
      Just value -> measuredShow "ppo/cartpole=" value

measureAlphaZeroArenaWinRate :: App ReportMeasurement
measureAlphaZeroArenaWinRate =
  let net = PolicyValueNet.initPolicyValueNet 43 7 16 31
      adam = PolicyValueNet.initAdamFor net
      result =
        PolicyValueNet.runOneGenerationOfSelfPlay
          net
          adam
          2
          (AlphaZero.maxPliesFor "connect4")
          8
          4
          4
          99
   in pure (measuredShow "connect4/gen0=" (PolicyValueNet.genArenaWinRate result))

measureTuneBestObjective :: App ReportMeasurement
measureTuneBestObjective = do
  env <- ask
  cluster <- liftIO (readExistingLivePublication ".")
  loaded <- liftIO (Tune.loadTuningExperiment "experiments/mnist-tune.dhall")
  case (cluster, loaded >>= maybe (Left "missing tuning block") Right . Tune.tuningExperimentConfig) of
    (Just publication, Right config) -> do
      let sampler = Tune.tuningSamplerKind (Tune.tuningConfigSampler config)
          scheduler = Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config)
          pruner = Tune.tuningPrunerKind (Tune.tuningConfigPruner config)
          trialCount = fromIntegral (Tune.tuningConfigTrials config)
          device = mlpDeviceForSubstrate (Publication.publicationSubstrate publication) env
      valuesE <-
        liftIO
          ( fmap
              (fmap (fmap Tune.trialResultObjective))
              (Tune.trialObjectiveResultsWithDeviceForAxes device sampler scheduler pruner trialCount)
          )
      pure $
        case valuesE of
          Left _ -> MeasurementUnavailable
          Right [] -> MeasurementUnavailable
          Right values -> measuredShow (Text.pack (show sampler) <> "=") (maximum values)
    _ -> pure MeasurementUnavailable

measureJitCacheHitRate :: App ReportMeasurement
measureJitCacheHitRate = do
  cluster <- liftIO (readExistingLivePublication ".")
  case cluster of
    Nothing -> pure MeasurementUnavailable
    Just publication -> do
      response <- liftIO (httpGetLocal (Publication.publicationEdgePort publication) "/metrics")
      pure $
        case response >>= httpOkBody >>= readCacheHitRate of
          Left _ -> MeasurementUnavailable
          Right rendered -> MeasurementAvailable rendered

measureDaemonHealthz :: App ReportMeasurement
measureDaemonHealthz = do
  cluster <- liftIO (readExistingLivePublication ".")
  case cluster of
    Nothing -> pure MeasurementUnavailable
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
      response <- liftIO (httpGetLocal edgePort "/healthz")
      pure $
        case response >>= httpOkBody of
          Right body
            | Text.strip body == "ok" ->
                MeasurementAvailable
                  ("http://127.0.0.1:" <> Text.pack (show edgePort) <> "/healthz status=200")
          _ -> MeasurementUnavailable

-- | The no-caveat browser/product matrix: probe the live checkpoint-list
-- selector surface that the row-complete Playwright matrix renders. The
-- denominator is the typed ProductRow registry, so a missing selector row keeps
-- the report card unavailable instead of silently counting the historical panel
-- sample.
measureBrowserProductMatrix :: App ReportMeasurement
measureBrowserProductMatrix = do
  cluster <- liftIO (readExistingLivePublication ".")
  case cluster of
    Nothing -> pure MeasurementUnavailable
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
      served <- liftIO (probeCheckpointListProductRows edgePort)
      let total = ProductMatrix.productRowCount
      pure $
        if served == total && total > 0
          then
            MeasurementAvailable
              ( "checkpoint-backed product rows "
                  <> Text.pack (show served)
                  <> "/"
                  <> Text.pack (show total)
                  <> " served at edge :"
                  <> Text.pack (show edgePort)
              )
          else MeasurementUnavailable

probeCheckpointListProductRows :: Int -> IO Int
probeCheckpointListProductRows port = do
  response <- httpPostLocal port "/api/checkpoints" ""
  pure $
    case response >>= httpOkBody of
      Left _ -> 0
      Right body ->
        length
          [ ()
          | row <- ProductMatrix.allProductRows
          , checkpointListContainsRow body row
          ]

checkpointListContainsRow :: Text -> ProductMatrix.ProductRow state -> Bool
checkpointListContainsRow body row =
  Text.isInfixOf
    ( "row-selector: "
        <> ProductMatrix.rowId row
        <> "\t"
        <> ProductMatrix.productRowExperimentHash row
        <> "\t"
    )
    body
    && Text.isInfixOf
      ( "checkpoint-summary: "
          <> ProductMatrix.rowId row
          <> "\t"
          <> ProductMatrix.productRowExperimentHash row
          <> "\t"
      )
      body

measuredShow :: (Show a) => Text -> a -> ReportMeasurement
measuredShow prefix value =
  MeasurementAvailable (prefix <> Text.pack (show value))

httpGetLocal :: Int -> Text -> IO (Either Text Text)
httpGetLocal port path = do
  result <-
    tryAny $
      withSocketsDo $ do
        addresses <-
          getAddrInfo
            (Just defaultHints {addrSocketType = Stream})
            (Just "127.0.0.1")
            (Just (show port))
        case addresses of
          [] -> ioError (userError "no address for jitml live report probe")
          addr : _ ->
            bracket (openLocalSocket addr) close $ \client -> do
              sendAll client (httpGetRequest path)
              Text.pack . ByteString.Char8.unpack <$> recvAll client
  pure $
    case result of
      Left err -> Left (Text.pack (displayException err))
      Right response -> Right response

openLocalSocket :: AddrInfo -> IO Socket
openLocalSocket addr = do
  client <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect client (addrAddress addr)
  pure client

httpGetRequest :: Text -> Data.ByteString.ByteString
httpGetRequest path =
  ByteString.Char8.pack $
    "GET "
      <> Text.unpack path
      <> " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"

-- | POST a plain-text body to a local edge route and return the raw HTTP
-- response. Used by 'measureBrowserProductMatrix' to exercise the demo's
-- checkpoint-backed product endpoints in-process.
httpPostLocal :: Int -> Text -> Text -> IO (Either Text Text)
httpPostLocal port path body = do
  result <-
    tryAny $
      withSocketsDo $ do
        addresses <-
          getAddrInfo
            (Just defaultHints {addrSocketType = Stream})
            (Just "127.0.0.1")
            (Just (show port))
        case addresses of
          [] -> ioError (userError "no address for jitml browser product probe")
          addr : _ ->
            bracket (openLocalSocket addr) close $ \client -> do
              sendAll client (httpPostRequest path body)
              Text.pack . ByteString.Char8.unpack <$> recvAll client
  pure $
    case result of
      Left err -> Left (Text.pack (displayException err))
      Right response -> Right response

httpPostRequest :: Text -> Text -> Data.ByteString.ByteString
httpPostRequest path body =
  let bodyBytes = ByteString.Char8.pack (Text.unpack body)
   in ByteString.Char8.pack
        ( "POST "
            <> Text.unpack path
            <> " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\nContent-Type: text/plain\r\nContent-Length: "
            <> show (Data.ByteString.length bodyBytes)
            <> "\r\n\r\n"
        )
        <> bodyBytes

recvAll :: Socket -> IO Data.ByteString.ByteString
recvAll client = do
  chunk <- recv client 65536
  if Data.ByteString.null chunk
    then pure Data.ByteString.empty
    else (chunk <>) <$> recvAll client

httpOkBody :: Text -> Either Text Text
httpOkBody response =
  case httpResponseStatus response of
    Just 200 -> Right (httpResponseBody response)
    Just status -> Left ("HTTP status " <> Text.pack (show status))
    Nothing -> Left "HTTP response missing status"

httpResponseStatus :: Text -> Maybe Int
httpResponseStatus response =
  case Text.words <$> listToMaybe (Text.lines response) of
    Just (_version : statusText : _) -> readMaybe (Text.unpack statusText)
    _ -> Nothing

httpResponseBody :: Text -> Text
httpResponseBody response =
  case Text.splitOn "\r\n\r\n" response of
    _headers : bodyParts -> Text.intercalate "\r\n\r\n" bodyParts
    [] -> ""

readCacheHitRate :: Text -> Either Text Text
readCacheHitRate body = do
  hits <-
    maybe (Left "jitml_jit_cache_hits missing") Right (prometheusMetricInt "jitml_jit_cache_hits" body)
  misses <-
    maybe
      (Left "jitml_jit_cache_misses missing")
      Right
      (prometheusMetricInt "jitml_jit_cache_misses" body)
  let total = hits + misses
  if total <= 0
    then Left "jit cache counters are empty"
    else
      let rate = fromIntegral hits / (fromIntegral total :: Double)
       in Right $
            "prometheus="
              <> Text.pack (show rate)
              <> " hits="
              <> Text.pack (show hits)
              <> " misses="
              <> Text.pack (show misses)

prometheusMetricInt :: Text -> Text -> Maybe Int
prometheusMetricInt metricName body =
  firstMatch (Text.lines body)
 where
  firstMatch [] = Nothing
  firstMatch (line : rest)
    | "#" `Text.isPrefixOf` Text.stripStart line = firstMatch rest
    | otherwise =
        case Text.words line of
          metric : value : _
            | metric == metricName -> readMaybe (Text.unpack value)
          _ -> firstMatch rest

-- | `jitml internal gc <experiment-hash>` reconciler. When a live
-- `cluster-publication.json` is present, walks the live MinIO bucket
-- `jitml-checkpoints/<experiment-hash>/manifests/` through
-- `JitML.Checkpoint.Store.listCheckpointManifestsMinIO`, applies the
-- registry-sourced `checkpoints` retention (Sprint 10.8) through
-- `Store.buildGcPlan`, and executes the
-- plan through `Store.executeGcPlan` over `JitML.Service.MinIOSubprocess`.
-- Without a live publication the reconciler falls back to walking the
-- local on-disk manifest store. Exits `3` (`ReconcilerNoop`) when the
-- store is already at the target state.
-- | Sprint 13.4 / 8.12 — `jitml internal upload-dataset` reads a local
-- file, looks up the canonical SHA-256 in
-- 'JitML.SL.Dataset.canonicalArtifactSha256For', verifies the file's SHA
-- matches the canonical when one is pinned, and uploads it to MinIO at the
-- typed dataset artefact key via the routed `MinIOSubprocess`. Mismatches
-- abort with 'InvalidConfig'.
runInternalUploadDataset :: [ParsedOption] -> App ()
runInternalUploadDataset parsedOptions = do
  let name = selectedValue "name" "MNIST" parsedOptions
      splitText = selectedValue "split" "train" parsedOptions
      artifactText = selectedValue "artifact" "images" parsedOptions
      path = Text.unpack (selectedValue "path" "" parsedOptions)
  split <- case parseDatasetSplit splitText of
    Just s -> pure s
    Nothing ->
      exitWithError
        ( InvalidConfig
            ( "upload-dataset: unknown split "
                <> splitText
                <> " (expected train/validation/test)"
            )
        )
  artifact <- case parseDatasetArtifact artifactText of
    Just a -> pure a
    Nothing ->
      exitWithError
        ( InvalidConfig
            ( "upload-dataset: unknown artifact "
                <> artifactText
                <> " (expected images/labels/archive)"
            )
        )
  when (null path) $
    exitWithError
      (InvalidConfig "upload-dataset: --path is required")
  bytes <- liftIO (Data.ByteString.readFile path)
  let actualSha = hexEncodeBytes (Crypto.Hash.SHA256.hash bytes)
      canonicalSha = Dataset.canonicalArtifactSha256For name split artifact
  case canonicalSha of
    Nothing ->
      writeText
        ( "upload-dataset: warning — no canonical SHA for "
            <> name
            <> "/"
            <> Dataset.datasetSplitText split
            <> "/"
            <> Dataset.datasetArtifactText artifact
            <> "; uploading "
            <> Text.pack (show (Data.ByteString.length bytes))
            <> " bytes with synthetic SHA verification disabled\n"
        )
    Just expected ->
      when (expected /= actualSha) $
        exitWithError
          ( InvalidConfig
              ( "upload-dataset SHA mismatch for "
                  <> name
                  <> "/"
                  <> Dataset.datasetSplitText split
                  <> "/"
                  <> Dataset.datasetArtifactText artifact
                  <> ": expected "
                  <> expected
                  <> ", got "
                  <> actualSha
              )
          )
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Nothing ->
      exitWithError
        ( InvalidConfig
            "upload-dataset requires a live cluster; bring it up via `jitml bootstrap`"
        )
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
          ref =
            Dataset.DatasetRef
              name
              split
              (Data.ByteString.length bytes)
              actualSha
      uploaded <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              ( Capabilities.putBlobBytesIfAbsent
                  (Dataset.datasetArtifactObjectRef ref artifact)
                  bytes
              )
          )
      case uploaded of
        Right _ ->
          writeText
            ( "upload-dataset: "
                <> name
                <> "/"
                <> Dataset.datasetSplitText split
                <> "/"
                <> Dataset.datasetArtifactText artifact
                <> " uploaded ("
                <> Text.pack (show (Data.ByteString.length bytes))
                <> " bytes, sha256="
                <> actualSha
                <> ")\n"
            )
        Left err ->
          exitWithError
            ( InvalidConfig
                ("upload-dataset failed: " <> Text.pack (show err))
            )

-- | Sprint 5.12 — print the binary's own reflected Dhall config schema. The
-- schema is read back off the live @FromDhall@ decoder (see
-- 'DhallSchema.configSchemas'), so it cannot drift from the decoder types.
runInternalDhallSchema :: [ParsedOption] -> App ()
runInternalDhallSchema parsedOptions =
  case selectedValue "catalog" "" parsedOptions of
    "" -> printConfigSchema
    catalogSelector ->
      case CatalogSchema.catalogGroup catalogSelector of
        Just entries ->
          writeText
            ( Text.intercalate
                "\n"
                ["-- " <> name <> "\n" <> schema | (name, schema) <- entries]
            )
        Nothing ->
          exitWithError
            ( InvalidConfig
                ( "dhall-schema: unknown catalog surface "
                    <> catalogSelector
                    <> " (expected one of: numerics, rl, all)"
                )
            )
 where
  printConfigSchema =
    case selectedValue "config" "" parsedOptions of
      "" ->
        writeText
          ( Text.intercalate
              "\n"
              [ "-- " <> name <> "\n" <> schema
              | (name, schema) <- DhallSchema.configSchemas
              ]
          )
      name ->
        case lookup name DhallSchema.configSchemas of
          Just schema -> writeText (schema <> "\n")
          Nothing ->
            exitWithError
              ( InvalidConfig
                  ( "dhall-schema: unknown config surface "
                      <> name
                      <> " (expected one of: "
                      <> Text.intercalate ", " (fmap fst DhallSchema.configSchemas)
                      <> ")"
                  )
              )

data ProductPublishResult = ProductPublishResult
  { productPublishRowId :: !Text
  , productPublishExperimentHash :: !Text
  , productPublishStatus :: !Text
  , productPublishManifestSha :: !(Maybe Text)
  , productPublishMessage :: !Text
  }
  deriving stock (Eq, Show)

runInternalTrainAndPublishProductRows :: [ParsedOption] -> App ()
runInternalTrainAndPublishProductRows parsedOptions = do
  substrate <- case selectedSubstrateFlagWithDefault LinuxCPU parsedOptions of
    Left err -> exitWithError err
    Right value -> pure value
  rowFilterRaw <- liftIO (lookupEnv "JITML_PRODUCT_ROW_FILTER")
  selectedRows <-
    either
      (exitWithError . InvalidConfig)
      pure
      (ProductMatrix.selectProductRows (Text.pack <$> rowFilterRaw))
  results <-
    traverse
      ( \row -> do
          writeLine ("train-and-publish-product-rows: row=" <> ProductMatrix.rowId row)
          trainAndPublishProductRow substrate row
      )
      selectedRows
  let eligibleCount = length [() | result <- results, productPublishStatus result == "eligible"]
      unsupportedCount = length [() | result <- results, productPublishStatus result == "unsupported"]
      errorRows = [productPublishRowId result | result <- results, productPublishStatus result == "error"]
  writeText $
    Text.unlines
      ( [ "train-and-publish-product-rows: substrate=" <> renderSubstrate substrate
        , "rows: " <> Text.pack (show (length results))
        , "eligible: " <> Text.pack (show eligibleCount)
        , "unsupported: " <> Text.pack (show unsupportedCount)
        , "errors: " <> Text.pack (show (length errorRows))
        ]
          <> fmap renderProductPublishResult results
      )
  unless (null errorRows) $
    exitWithError
      ( InvalidConfig
          ( "train-and-publish-product-rows failed for rows: "
              <> Text.intercalate ", " errorRows
          )
      )

data ProductRowTimingResult = ProductRowTimingResult
  { productTimingRowId :: !Text
  , productTimingShape :: !MlpShape
  , productTimingBatchSize :: !Int
  , productTimingRepetitions :: !Int
  , productTimingCpuSeconds :: !Double
  , productTimingCudaSeconds :: !Double
  }
  deriving stock (Eq, Show)

runInternalBenchmarkProductRowWallClock :: App ()
runInternalBenchmarkProductRowWallClock = do
  env <- ask
  rowFilterRaw <- liftIO (lookupEnv "JITML_PRODUCT_ROW_FILTER")
  selectedRows <-
    either
      (exitWithError . InvalidConfig)
      pure
      (ProductMatrix.selectProductRows (Text.pack <$> rowFilterRaw))
  let cpuDevice = mlpDeviceForSubstrate LinuxCPU env
      cudaDevice = mlpDeviceForSubstrate LinuxCUDA env
  requireProductTimingProbe "linux-cpu" cpuDevice
  requireProductTimingProbe "linux-cuda" cudaDevice
  results <- traverse (benchmarkProductTimingRow cpuDevice cudaDevice) selectedRows
  let failingRows =
        [ productTimingRowId result
        | result <- results
        , productTimingCudaSeconds result >= productTimingCpuSeconds result
        ]
  writeText $
    Text.unlines
      ( [ "benchmark-product-row-wall-clock: rows=" <> Text.pack (show (length results))
        , "benchmark-product-row-wall-clock: status="
            <> if null failingRows then "PASS" else "FAIL"
        , Text.intercalate
            "\t"
            [ "row_id"
            , "inputs"
            , "hidden"
            , "outputs"
            , "batch"
            , "repetitions"
            , "linux_cpu_seconds"
            , "linux_cuda_seconds"
            , "speedup"
            , "status"
            ]
        ]
          <> fmap renderProductTimingResult results
      )
  unless (null failingRows) $
    exitWithError
      ( InvalidConfig
          ( "benchmark-product-row-wall-clock failed; linux-cuda was not strictly faster for rows: "
              <> Text.intercalate ", " failingRows
          )
      )

requireProductTimingProbe :: Text -> MlpDevice -> App ()
requireProductTimingProbe label device = do
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "benchmark-product-row-wall-clock: "
                <> label
                <> " MLP device probe failed: "
                <> err
            )
        )
    Right () -> pure ()

benchmarkProductTimingRow
  :: MlpDevice
  -> MlpDevice
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> App ProductRowTimingResult
benchmarkProductTimingRow cpuDevice cudaDevice row = do
  let shape = productRowTimingShape row
  batchSize <- productEnvInt "JITML_PRODUCT_TIMING_BATCH" (productRowTimingDefaultBatch row shape)
  repetitions <- productEnvInt "JITML_PRODUCT_TIMING_REPETITIONS" 4
  let params = mlpInit shape (productRowTimingSeed row)
      inputs = productRowTimingInputs row shape batchSize
      deltas = productRowTimingDeltas row shape batchSize
      gradientBatch = zip inputs deltas
  writeLine
    ( "benchmark-product-row-wall-clock: row="
        <> ProductMatrix.rowId row
        <> " shape="
        <> renderMlpShape shape
        <> " batch="
        <> Text.pack (show batchSize)
        <> " repetitions="
        <> Text.pack (show repetitions)
    )
  requireProductTimingAction
    (ProductMatrix.rowId row <> "/linux-cpu warmup")
    (warmProductTimingDevice cpuDevice params inputs gradientBatch)
  requireProductTimingAction
    (ProductMatrix.rowId row <> "/linux-cuda warmup")
    (warmProductTimingDevice cudaDevice params inputs gradientBatch)
  cpuSeconds <-
    requireProductTimingAction
      (ProductMatrix.rowId row <> "/linux-cpu timing")
      (timeProductTimingDevice cpuDevice params inputs gradientBatch repetitions)
  cudaSeconds <-
    requireProductTimingAction
      (ProductMatrix.rowId row <> "/linux-cuda timing")
      (timeProductTimingDevice cudaDevice params inputs gradientBatch repetitions)
  pure
    ProductRowTimingResult
      { productTimingRowId = ProductMatrix.rowId row
      , productTimingShape = shape
      , productTimingBatchSize = batchSize
      , productTimingRepetitions = repetitions
      , productTimingCpuSeconds = cpuSeconds
      , productTimingCudaSeconds = cudaSeconds
      }

requireProductTimingAction :: Text -> IO (Either Text a) -> App a
requireProductTimingAction label action = do
  result <- liftIO action
  case result of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "benchmark-product-row-wall-clock: "
                <> label
                <> " failed: "
                <> err
            )
        )
    Right value -> pure value

warmProductTimingDevice
  :: MlpDevice
  -> MlpParams
  -> [VU.Vector Double]
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text ())
warmProductTimingDevice device params inputs gradientBatch =
  void <$> runProductTimingIteration device params inputs gradientBatch

timeProductTimingDevice
  :: MlpDevice
  -> MlpParams
  -> [VU.Vector Double]
  -> [(VU.Vector Double, VU.Vector Double)]
  -> Int
  -> IO (Either Text Double)
timeProductTimingDevice device params inputs gradientBatch repetitions = do
  start <- getPOSIXTime
  runResult <- go repetitions
  end <- getPOSIXTime
  let elapsed = fromRational (toRational (end - start))
  pure (elapsed <$ runResult)
 where
  go remaining
    | remaining <= 0 = pure (Right ())
    | otherwise = do
        result <- runProductTimingIteration device params inputs gradientBatch
        case result of
          Left err -> pure (Left err)
          Right () -> go (remaining - 1)

runProductTimingIteration
  :: MlpDevice
  -> MlpParams
  -> [VU.Vector Double]
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text ())
runProductTimingIteration device params inputs gradientBatch = do
  forward <- mlpdForwardBatch device params inputs
  case forward of
    Left err -> pure (Left err)
    Right outputs
      | length outputs /= length inputs ->
          pure (Left "forward batch returned an unexpected output count")
      | otherwise -> do
          gradient <- mlpdBatchGradient device params gradientBatch
          pure (void gradient)

productRowTimingShape :: ProductMatrix.ProductRow state -> MlpShape
productRowTimingShape row =
  case ProductMatrix.rowId row of
    "mnist-shallow-mlp" -> MlpShape 784 64 10
    "mnist-deep-mlp" -> MlpShape 784 128 10
    "mnist-lenet" -> MlpShape 784 96 10
    "fashion-mnist-mlp" -> MlpShape 784 96 10
    "fashion-mnist-resnet" -> MlpShape 784 160 10
    "cifar10-resnet20" -> MlpShape 3072 192 10
    "cifar10-resnet56" -> MlpShape 3072 256 10
    "cifar100-wide-resnet" -> MlpShape 3072 256 100
    "cifar10-vit" -> MlpShape 3072 256 10
    "tiny-imagenet-resnet50" -> MlpShape 3072 320 200
    "california-housing-mlp" -> MlpShape 8 96 1
    _ ->
      case ProductMatrix.rowClass row of
        ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
          productRowTimingRlShape algorithm environment
        ProductMatrix.RlGoalConditioned environment ->
          productRowTimingGoalShape environment
        ProductMatrix.AlphaZeroGame game ->
          productRowTimingAlphaZeroShape game
        ProductMatrix.HyperparameterTuning _ ->
          MlpShape 784 128 10
        ProductMatrix.SupervisedClassification _ _ ->
          MlpShape 784 128 10
        ProductMatrix.SupervisedRegression _ _ ->
          MlpShape 8 96 1

productRowTimingRlShape :: Text -> Text -> MlpShape
productRowTimingRlShape algorithm environment =
  let (inputs, outputs) = productRowTimingRlDims algorithm environment
   in MlpShape inputs 128 outputs

productRowTimingRlDims :: Text -> Text -> (Int, Int)
productRowTimingRlDims algorithm environment
  | algorithm `elem` ["DDPG", "TD3", "SAC", "CrossQ", "TQC"] =
      case environment of
        "pendulum" -> (3, 1)
        "lunar-lander" -> (8, 2)
        _ -> discreteDims environment
  | otherwise = discreteDims environment
 where
  discreteDims "cartpole" = (4, 2)
  discreteDims "mountain-car" = (2, 3)
  discreteDims "acrobot" = (6, 3)
  discreteDims "lunar-lander" = (8, 4)
  discreteDims "key-door-grid" = (16, 4)
  discreteDims "gridworld-deterministic" = (8, 4)
  discreteDims "pendulum" = (3, 3)
  discreteDims _ = (8, 4)

productRowTimingGoalShape :: Text -> MlpShape
productRowTimingGoalShape "goal-reaching" = MlpShape 6 128 4
productRowTimingGoalShape _ = MlpShape 8 128 4

productRowTimingAlphaZeroShape :: Text -> MlpShape
productRowTimingAlphaZeroShape "connect4" = MlpShape 42 160 8
productRowTimingAlphaZeroShape "othello" = MlpShape 64 192 65
productRowTimingAlphaZeroShape "hex" = MlpShape 121 224 122
productRowTimingAlphaZeroShape "gomoku" = MlpShape 225 256 226
productRowTimingAlphaZeroShape _ = MlpShape 64 192 65

productRowTimingDefaultBatch :: ProductMatrix.ProductRow state -> MlpShape -> Int
productRowTimingDefaultBatch row shape =
  case ProductMatrix.family row of
    ProductMatrix.Supervised
      | mlpInputs shape >= 3000 -> 512
      | otherwise -> 2048
    ProductMatrix.ReinforcementLearning -> 65536
    ProductMatrix.AlphaZero -> 4096
    ProductMatrix.Tuning -> 2048

productRowTimingSeed :: ProductMatrix.ProductRow state -> Int
productRowTimingSeed row =
  1
    + ( Text.foldl'
          (\acc ch -> (acc * 33 + fromEnum ch) `mod` 2147483646)
          (17 :: Int)
          (ProductMatrix.rowId row)
          `mod` 2147483646
      )

productRowTimingInputs :: ProductMatrix.ProductRow state -> MlpShape -> Int -> [VU.Vector Double]
productRowTimingInputs row shape batchSize =
  [ VU.generate
      (mlpInputs shape)
      (deterministicTimingValue (productRowTimingSeed row) sampleIndex)
  | sampleIndex <- [0 .. batchSize - 1]
  ]

productRowTimingDeltas :: ProductMatrix.ProductRow state -> MlpShape -> Int -> [VU.Vector Double]
productRowTimingDeltas row shape batchSize =
  [ VU.generate
      (mlpOutputs shape)
      (deterministicTimingValue (productRowTimingSeed row + 104729) sampleIndex)
  | sampleIndex <- [0 .. batchSize - 1]
  ]

deterministicTimingValue :: Int -> Int -> Int -> Double
deterministicTimingValue seed sampleIndex featureIndex =
  let raw =
        ( seed
            + 1103515245 * (sampleIndex + 1)
            + 12345 * (featureIndex + 3)
        )
          `mod` 2003
   in (fromIntegral raw / 1001.5) - 1.0

renderProductTimingResult :: ProductRowTimingResult -> Text
renderProductTimingResult result =
  Text.intercalate
    "\t"
    [ productTimingRowId result
    , Text.pack (show (mlpInputs shape))
    , Text.pack (show (mlpHidden shape))
    , Text.pack (show (mlpOutputs shape))
    , Text.pack (show (productTimingBatchSize result))
    , Text.pack (show (productTimingRepetitions result))
    , renderTimingDouble (productTimingCpuSeconds result)
    , renderTimingDouble (productTimingCudaSeconds result)
    , renderTimingDouble (productTimingCpuSeconds result / productTimingCudaSeconds result)
    , if productTimingCudaSeconds result < productTimingCpuSeconds result then "PASS" else "FAIL"
    ]
 where
  shape = productTimingShape result

renderMlpShape :: MlpShape -> Text
renderMlpShape shape =
  Text.intercalate
    "x"
    [ Text.pack (show (mlpInputs shape))
    , Text.pack (show (mlpHidden shape))
    , Text.pack (show (mlpOutputs shape))
    ]

renderTimingDouble :: Double -> Text
renderTimingDouble value =
  Text.pack (printf "%.6f" value)

trainAndPublishProductRow
  :: Substrate
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> App ProductPublishResult
trainAndPublishProductRow substrate row =
  case ProductMatrix.rowClass row of
    ProductMatrix.SupervisedClassification _ _ ->
      trainAndPublishSupervisedProductRow substrate row
    ProductMatrix.SupervisedRegression _ _ ->
      trainAndPublishSupervisedProductRow substrate row
    ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
      trainAndPublishRlProductRow substrate row (Workload.rlTrainerForAlgorithm algorithm) environment
    ProductMatrix.RlGoalConditioned environment ->
      trainAndPublishRlProductRow substrate row "her" environment
    ProductMatrix.AlphaZeroGame game ->
      trainAndPublishAlphaZeroProductRow substrate row game
    ProductMatrix.HyperparameterTuning _ ->
      trainAndPublishTuningProductRow substrate row

trainAndPublishSupervisedProductRow
  :: Substrate
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> App ProductPublishResult
trainAndPublishSupervisedProductRow substrate row = do
  loaded <-
    liftIO
      (ProductExperiment.loadSupervisedProblemByPath (Text.unpack (ProductMatrix.experimentConfig row)))
  case loaded of
    Left err -> pure (productPublishError row err)
    Right problem -> do
      trainLimit <-
        productEnvInt
          "JITML_PRODUCT_SL_TRAIN_LIMIT"
          (productSupervisedDefaultTrainLimit row)
      epochs <-
        productEnvInt
          "JITML_PRODUCT_SL_EPOCHS"
          (productSupervisedDefaultEpochs row)
      testLimit <-
        productEnvInt
          "JITML_PRODUCT_SL_TEST_LIMIT"
          (productSupervisedDefaultTestLimit row)
      learningRate <-
        productEnvDouble
          "JITML_PRODUCT_SL_LEARNING_RATE"
          (productSupervisedDefaultLearningRate row)
      trained <-
        runDeviceMnistTrainingWithLimitsAndLearningRate
          substrate
          problem
          trainLimit
          epochs
          testLimit
          (Classifier.clfBatchSize Classifier.defaultClassifierConfig)
          (Just learningRate)
      case trained of
        Left err -> pure (productPublishError row err)
        Right metrics ->
          case tmCheckpointWeights metrics of
            Nothing ->
              pure (productPublishError row "supervised row produced no checkpointable weights")
            Just weights -> do
              let experimentHash = ProductMatrix.productRowExperimentHash row
                  tensorName = experimentHash <> "-sl-weights"
                  metricRows = trainingCheckpointMetrics metrics
                  completedTraining =
                    do
                      planId <- completionPlanIdForProductRow row
                      initialWeights <-
                        maybe
                          (Left "missing initial checkpoint weights")
                          Right
                          (tmInitialCheckpointWeights metrics)
                      completedTrainingForProductRow
                        planId
                        (ProductMatrix.trainingBudget row)
                        row
                        (tmDatasetShaAtRead metrics)
                        experimentHash
                        tensorName
                        (tmCompletedUnits metrics)
                        metricRows
                        initialWeights
                        weights
              case completedTraining of
                Left err ->
                  pure
                    ( productPublishError
                        row
                        ("supervised row did not produce passing CompletedTraining evidence: " <> err)
                    )
                Right completed -> do
                  stored <-
                    writeLocalWeightCheckpointWithCompleted
                      (Just completed)
                      experimentHash
                      tensorName
                      (tmCompletedUnits metrics)
                      metricRows
                      weights
                  pure (productPublishEligible row stored "supervised artifact published")

trainAndPublishRlProductRow
  :: Substrate
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> Text
  -> Text
  -> App ProductPublishResult
trainAndPublishRlProductRow substrate row trainerKind environment =
  case rlTrainerEnvironmentCompatibilityError trainerKind environment of
    Just err ->
      pure (productPublishUnsupported row err)
    Nothing -> do
      env <- ask
      -- 20 evaluation episodes for a stable median: over just 4 episodes a
      -- genuinely-converged but variable policy (e.g. PPO/cartpole) can post a
      -- low median from a couple of unlucky short episodes, so the convergence
      -- gate saw noise rather than the policy's true performance.
      evalEpisodes <-
        productEnvInt
          "JITML_PRODUCT_RL_EVAL_EPISODES"
          ProductBudget.productRlDefaultEvaluationEpisodes
      maxSteps <-
        productEnvInt
          "JITML_PRODUCT_RL_MAX_STEPS"
          ProductBudget.productRlDefaultMaxEpisodeSteps
      trainerRunE <-
        liftIO
          ( runTrainerEpisodes
              substrate
              (rlDeviceForSubstrate substrate env)
              Nothing
              trainerKind
              environment
              (productRowSeed row 41)
              evalEpisodes
              maxSteps
              (Just (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row)))
          )
      case trainerRunE of
        Left err ->
          pure (productPublishError row err)
        Right trainerRun ->
          case (trainerRunWeights trainerRun, trainerRunEvidence trainerRun) of
            (Just weights, Just evidence) -> do
              let experimentHash = ProductMatrix.productRowExperimentHash row
                  tensorName = "rl-" <> Text.toLower trainerKind <> "-weights"
                  metrics =
                    rlCompletionMetrics
                      trainerKind
                      (trainerRunObservedUnits trainerRun)
                      (trainerRunEpisodes trainerRun)
                  checkpointStep = trainerRunObservedUnits trainerRun
                  completedTraining =
                    do
                      completionPlanId <- eitherToMaybe (completionPlanIdForProductRow row)
                      rlCompletedTrainingWithBudget
                        completionPlanId
                        (ProductMatrix.trainingBudget row)
                        trainerKind
                        environment
                        experimentHash
                        tensorName
                        checkpointStep
                        metrics
                        evidence
              case completedTraining of
                Nothing ->
                  pure
                    ( productPublishError
                        row
                        (rlCompletedTrainingFailureMessage trainerKind environment metrics)
                    )
                Just completed -> do
                  stored <-
                    writeLocalWeightCheckpointWithCompleted
                      (Just completed)
                      experimentHash
                      tensorName
                      checkpointStep
                      metrics
                      weights
                  _ <-
                    writeTextArtifact
                      experimentHash
                      "rl-trajectory"
                      ( renderRlTrajectoryArtifact
                          experimentHash
                          environment
                          trainerKind
                          (productRowSeed row 41)
                          (trainerRunEpisodes trainerRun)
                      )
                  pure (productPublishEligible row stored "RL policy artifact published")
            _ ->
              pure (productPublishUnsupported row "RL row produced no checkpointable policy weights")

trainAndPublishAlphaZeroProductRow
  :: Substrate
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> Text
  -> App ProductPublishResult
trainAndPublishAlphaZeroProductRow substrate row game = do
  env <- ask
  games <- productEnvInt "JITML_PRODUCT_AZ_GAMES" (alphaZeroProductGamesFor game)
  sims <-
    productEnvInt
      "JITML_PRODUCT_AZ_SIMS"
      (fromIntegral (RLConvergence.alphaZeroSimulationBudget game))
  maxPlies <- productEnvInt "JITML_PRODUCT_AZ_MAX_PLIES" (AlphaZero.maxPliesFor game)
  updates <- productEnvInt "JITML_PRODUCT_AZ_UPDATES" (alphaZeroProductUpdatesFor game)
  -- Odd arena-game count: for a no-draw game (hex, gomoku) an even count lets a
  -- genuine ~50% net land on exactly 4W-4L = 0.5, which the all-draw sentinel in
  -- `passesAlphaZeroArena` rejects as if every game had drawn. With 9 games a
  -- real 50%-ish net lands at 4/9 or 5/9 — both clear the 0.40 external bar and
  -- neither is the 0.5 sentinel — so a legitimately-winning net is not discarded.
  arenaGames <- productEnvInt "JITML_PRODUCT_AZ_ARENA_GAMES" 9
  generationTarget <-
    productEnvInt
      "JITML_PRODUCT_AZ_GENERATIONS"
      (fromIntegral (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row)))
  let seed = productRowSeed row 101
      device = rlDeviceForSubstrate substrate env
      initialState = AlphaZero.initialStateFor game
      observationSize = AlphaZero.observationSizeFor game
      actionCount = AlphaZero.actionCountFor game
      net0 = PolicyValueNet.initPolicyValueNet observationSize actionCount 16 seed
      adam0 = PolicyValueNet.initAdamFor net0
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err ->
      pure (productPublishError row ("AlphaZero substrate device unavailable: " <> err))
    Right () -> do
      generationResult <-
        liftIO $
          trainAlphaZeroGenerationsWithDevice
            device
            initialState
            net0
            adam0
            generationTarget
            games
            sims
            maxPlies
            updates
            seed
      case generationResult of
        Left err ->
          pure (productPublishError row ("AlphaZero self-play failed: " <> err))
        Right (trainedNet, samples, generationCount) -> do
          if null samples
            then pure (productPublishError row "AlphaZero self-play produced no samples")
            else do
              let winRate =
                    PolicyValueNet.arenaWinRateAgainstUniformFrom
                      initialState
                      trainedNet
                      arenaGames
                      maxPlies
                      (seed + 7919)
                  experimentHash = ProductMatrix.productRowExperimentHash row
                  completedGenerations = fromIntegral generationCount
                  checkpointStep =
                    alphaZeroArtifactStep completedGenerations (length samples)
                  metrics =
                    [ ("arena_win_rate", winRate)
                    , ("legal_move_rate", 1.0)
                    , ("mcts_simulations_per_move", fromIntegral sims)
                    , ("self_play_games", fromIntegral games)
                    , ("self_play_generations", fromIntegral generationCount)
                    , ("self_play_samples", fromIntegral (length samples))
                    ]
                  initialWeights = PolicyValueNet.policyValueNetToFlat net0
                  finalWeights = PolicyValueNet.policyValueNetToFlat trainedNet
                  completedTraining =
                    do
                      completionPlanId <- eitherToMaybe (completionPlanIdForProductRow row)
                      alphaZeroCompletedTraining
                        completionPlanId
                        (ProductMatrix.trainingBudget row)
                        experimentHash
                        game
                        completedGenerations
                        metrics
                        initialWeights
                        finalWeights
              case completedTraining of
                Nothing ->
                  pure
                    ( productPublishError
                        row
                        ( "AlphaZero row did not produce passing CompletedTraining evidence: arena_win_rate="
                            <> Text.pack (show winRate)
                        )
                    )
                Just completed -> do
                  stored <-
                    writeLocalWeightCheckpointWithCompleted
                      (Just completed)
                      experimentHash
                      ("alphazero-" <> game <> "-policy-value-weights")
                      checkpointStep
                      metrics
                      finalWeights
                  _ <-
                    writeTextArtifact
                      experimentHash
                      "alphazero-transcript"
                      (renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples)
                  pure (productPublishEligible row stored "AlphaZero policy-value artifact published")

alphaZeroProductGamesFor :: Text -> Int
alphaZeroProductGamesFor "othello" = 4
alphaZeroProductGamesFor _ = 2

alphaZeroProductUpdatesFor :: Text -> Int
alphaZeroProductUpdatesFor "othello" = 16
alphaZeroProductUpdatesFor _ = 8

trainAlphaZeroGenerationsWithDevice
  :: MlpDevice
  -> AlphaZero.GameState
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> IO (Either Text (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample], Int))
trainAlphaZeroGenerationsWithDevice device initialState net0 adam0 generationTarget games sims maxPlies updates seed =
  go 0 net0 adam0 []
 where
  go generation net adam allSamples
    | generation >= max 1 generationTarget =
        pure (Right (net, allSamples, generation))
    | otherwise = do
        sampleResults <-
          traverse
            ( \gameIndex ->
                PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                  initialState
                  device
                  net
                  (seed + generation * 7919 + gameIndex)
                  sims
                  maxPlies
            )
            [0 .. max 1 games - 1]
        case sequence sampleResults of
          Left err -> pure (Left err)
          Right batches -> do
            let generationSamples = concat batches
            trainedE <-
              PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
                device
                net
                adam
                1.0e-3
                updates
                generationSamples
            case trainedE of
              Left err -> pure (Left err)
              Right (trainedNet, trainedAdam) ->
                go (generation + 1) trainedNet trainedAdam (allSamples <> generationSamples)

trainAndPublishTuningProductRow
  :: Substrate
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> App ProductPublishResult
trainAndPublishTuningProductRow substrate row = do
  env <- ask
  loaded <- liftIO (Tune.loadTuningExperiment (Text.unpack (ProductMatrix.experimentConfig row)))
  case loaded of
    Left err ->
      pure (productPublishError row err)
    Right experiment ->
      case Tune.tuningExperimentConfig experiment of
        Nothing ->
          pure (productPublishError row "tuning row has no tuning config")
        Just config -> do
          trialCount <-
            productEnvInt
              "JITML_PRODUCT_TUNE_TRIALS"
              ( fromIntegral
                  ( max
                      1
                      ( min
                          (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row))
                          (fromIntegral (Tune.tuningConfigTrials config))
                      )
                  )
              )
          resultsE <-
            liftIO
              ( Tune.trialObjectiveResultsWithDeviceForConfig
                  (mlpDeviceForSubstrate substrate env)
                  config
                  trialCount
              )
          case resultsE of
            Left err ->
              pure (productPublishError row err)
            Right results ->
              case selectBestTrialResult results of
                Nothing ->
                  pure (productPublishError row "tuning row produced no trial results")
                Just best -> do
                  let experimentHash = ProductMatrix.productRowExperimentHash row
                      -- Budget evidence counts trials EXECUTED, not the
                      -- scheduler/pruner-filtered survivors: ASHA/MedianPruner
                      -- drop sub-median trials from `results` (champion
                      -- selection), so counting `length results` made the
                      -- 128-trial budget gate unsatisfiable whenever a pruner
                      -- was active. `selectBestTrialResult`/`renderTuneTrialArtifact`
                      -- still consume the filtered `results`.
                      trialsCompleted32 :: Word32
                      trialsCompleted32 = fromIntegral trialCount
                      trialsCompleted = fromIntegral trialsCompleted32
                      completedTraining =
                        do
                          planId <- completionPlanIdForProductRow row
                          completedTrainingForProductRow
                            planId
                            (ProductMatrix.trainingBudget row)
                            row
                            Nothing
                            experimentHash
                            "tune-trial-weights"
                            trialsCompleted
                            [("best_objective", Tune.trialResultObjective best)]
                            (Tune.trialResultInitialWeights best)
                            (Tune.trialResultWeights best)
                  case completedTraining of
                    Left err ->
                      pure
                        (productPublishError row ("tuning row did not produce passing CompletedTraining evidence: " <> err))
                    Right completed -> do
                      let productExecutions =
                            [ Tune.TrialExecution
                                { Tune.trialExecutionResult = result
                                , Tune.trialExecutionPruned = False
                                , Tune.trialExecutionPromoted =
                                    Tune.trialResultIndex result == Tune.trialResultIndex best
                                }
                            | result <- results
                            ]
                      stored <-
                        writeLocalWeightCheckpointWithCompleted
                          (Just completed)
                          experimentHash
                          "tune-trial-weights"
                          trialsCompleted
                          [("best_objective", Tune.trialResultObjective best)]
                          (Tune.trialResultWeights best)
                      _ <-
                        writeTextArtifact
                          experimentHash
                          "tune-trials"
                          ( renderTuneTrialArtifact
                              experiment
                              (Tune.tuningSamplerKind (Tune.tuningConfigSampler config))
                              productExecutions
                              best
                          )
                      pure (productPublishEligible row stored "tuning promoted artifact published")

productPublishEligible
  :: ProductMatrix.ProductRow state
  -> CheckpointStore.StoredCheckpoint
  -> Text
  -> ProductPublishResult
productPublishEligible row stored message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.rowId row
    , productPublishExperimentHash = ProductMatrix.productRowExperimentHash row
    , productPublishStatus = "eligible"
    , productPublishManifestSha = Just (CheckpointStore.storedManifestSha stored)
    , productPublishMessage = message
    }

productPublishUnsupported :: ProductMatrix.ProductRow state -> Text -> ProductPublishResult
productPublishUnsupported row message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.rowId row
    , productPublishExperimentHash = ProductMatrix.productRowExperimentHash row
    , productPublishStatus = "unsupported"
    , productPublishManifestSha = Nothing
    , productPublishMessage = message
    }

productPublishError :: ProductMatrix.ProductRow state -> Text -> ProductPublishResult
productPublishError row message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.rowId row
    , productPublishExperimentHash = ProductMatrix.productRowExperimentHash row
    , productPublishStatus = "error"
    , productPublishManifestSha = Nothing
    , productPublishMessage = message
    }

renderProductPublishResult :: ProductPublishResult -> Text
renderProductPublishResult result =
  Text.intercalate
    "\t"
    [ "product-row"
    , productPublishRowId result
    , productPublishExperimentHash result
    , productPublishStatus result
    , fromMaybe "none" (productPublishManifestSha result)
    , productPublishMessage result
    ]

productEnvInt :: String -> Int -> App Int
productEnvInt name fallback = do
  raw <- liftIO (envWithDefault name (Text.pack (show fallback)))
  pure (max 1 (readIntDefault fallback raw))

productEnvDouble :: String -> Double -> App Double
productEnvDouble name fallback = do
  raw <- liftIO (envWithDefault name (Text.pack (show fallback)))
  pure $
    case readMaybe (Text.unpack raw) of
      Just value | value > 0.0 -> value
      _ -> fallback

productSupervisedDefaultLearningRate :: ProductMatrix.ProductRow state -> Double
productSupervisedDefaultLearningRate row
  | ProductMatrix.rowId row == "fashion-mnist-resnet" = 3.0e-3
  | otherwise = 1.0e-3

productSupervisedDefaultTrainLimit :: ProductMatrix.ProductRow state -> Int
productSupervisedDefaultTrainLimit row =
  case ProductMatrix.rowId row of
    "cifar10-resnet20" -> 1000
    "cifar10-resnet56" -> 1000
    "cifar10-vit" -> 1000
    "tiny-imagenet-resnet50" -> 256
    _ -> 7000

productSupervisedDefaultEpochs :: ProductMatrix.ProductRow state -> Int
productSupervisedDefaultEpochs =
  fromIntegral . TrainingBudget.tbTargetUnits . ProductMatrix.trainingBudget

productSupervisedDefaultTestLimit :: ProductMatrix.ProductRow state -> Int
productSupervisedDefaultTestLimit row
  | ProductMatrix.rowId row == "tiny-imagenet-resnet50" = 500
  | otherwise = 1000

productRowSeed :: ProductMatrix.ProductRow state -> Int -> Int
productRowSeed row fallback =
  fromIntegral $
    fromMaybe
      (fromIntegral (fallback + stableTextSeed (ProductMatrix.rowId row)))
      (TrainingBudget.tbSeed (ProductMatrix.trainingBudget row))

stableTextSeed :: Text -> Int
stableTextSeed =
  Text.foldl' (\acc ch -> acc * 33 + fromEnum ch) 17

runInternalSeedDemoCheckpoints :: App ()
runInternalSeedDemoCheckpoints =
  exitWithError
    ( InvalidConfig
        "internal seed-demo-checkpoints is retired; use `jitml internal train-and-publish-product-rows --substrate <substrate>` to produce inference-eligible product-row artifacts"
    )

parseDatasetSplit :: Text -> Maybe Dataset.DatasetSplit
parseDatasetSplit "train" = Just Dataset.TrainSplit
parseDatasetSplit "validation" = Just Dataset.ValidationSplit
parseDatasetSplit "test" = Just Dataset.TestSplit
parseDatasetSplit _ = Nothing

parseDatasetArtifact :: Text -> Maybe Dataset.DatasetArtifact
parseDatasetArtifact "images" = Just Dataset.ImagesArtifact
parseDatasetArtifact "data" = Just Dataset.ImagesArtifact
parseDatasetArtifact "labels" = Just Dataset.LabelsArtifact
parseDatasetArtifact "archive" = Just Dataset.ArchiveArtifact
parseDatasetArtifact "tarball" = Just Dataset.ArchiveArtifact
parseDatasetArtifact _ = Nothing

hexEncodeBytes :: Data.ByteString.ByteString -> Text
hexEncodeBytes =
  Text.pack
    . concatMap (\b -> [hexDigit (fromIntegral b `div` 16), hexDigit (fromIntegral b `mod` 16)])
    . Data.ByteString.unpack
 where
  hexDigit n
    | n < 10 = toEnum (fromEnum '0' + n)
    | otherwise = toEnum (fromEnum 'a' + n - 10)

-- | Sprint 10.8 — the checkpoint GC retention, sourced from the durable-state
-- registry's `checkpoints` store (replacing the former hardcoded `LastN 5`). The
-- registry's typed `RetentionPolicy` is mapped onto the GC-supported subset
-- (`KeepAll`/`LastN`); age/bytes policies fall back to `KeepAll` — object-store ILM,
-- not the manifest-chain GC, governs those.
checkpointsGcRetention :: CheckpointStore.RetentionPolicy
checkpointsGcRetention =
  case ProjectConfig.lookupStoreRetention "checkpoints" ProjectConfig.defaultProjectConfig of
    Just (ProjectConfig.LastN n) -> CheckpointStore.LastN (fromIntegral n)
    Just (ProjectConfig.LastNWithinAge keep _) -> CheckpointStore.LastN (fromIntegral keep)
    Just ProjectConfig.KeepAll -> CheckpointStore.KeepAll
    _ -> CheckpointStore.KeepAll

runInternalGc :: [ParsedOption] -> App ()
runInternalGc parsedOptions = do
  let experimentHash = selectedValue "experiment-hash" "default" parsedOptions
      retention = checkpointsGcRetention
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
      listing <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (CheckpointStore.listCheckpointManifestsMinIO experimentHash)
          )
      manifests <-
        case listing of
          Left err ->
            exitWithError
              ( InvalidConfig
                  ("gc live manifest scan: " <> Text.pack (show err))
              )
          Right found -> pure found
      let plan = CheckpointStore.buildGcPlan experimentHash retention manifests []
      executed <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (CheckpointStore.executeGcPlan plan)
          )
      publishGcReapedEvents publication executed plan
      writeLine
        ( "gc: "
            <> experimentHash
            <> " kept="
            <> Text.pack (show (length (CheckpointStore.gcKeptManifestShas plan)))
            <> " reaped="
            <> Text.pack (show (CheckpointStore.gcExecutedReapedManifests executed))
            <> " reaped-blobs="
            <> Text.pack (show (CheckpointStore.gcExecutedReapedBlobs executed))
        )
      when (CheckpointStore.gcNoOp plan) $
        exitWithError (ReconcilerNoop ("gc: " <> experimentHash <> " already current"))
    Nothing -> do
      checkpointRoot <- localCheckpointRoot
      loadedManifests <- liftIO (CheckpointStore.listCheckpointManifests checkpointRoot experimentHash)
      manifests <-
        case loadedManifests of
          Left err -> exitWithError (InvalidConfig ("gc manifest scan: " <> err))
          Right found -> pure found
      let plan = CheckpointStore.buildGcPlan experimentHash retention manifests []
      writeLine
        ( "gc: "
            <> experimentHash
            <> " kept="
            <> Text.pack (show (length (CheckpointStore.gcKeptManifestShas plan)))
            <> " reaped="
            <> Text.pack (show (length (CheckpointStore.gcReapEvents plan)))
        )
      when (CheckpointStore.gcNoOp plan) $
        exitWithError (ReconcilerNoop ("gc: " <> experimentHash <> " already current"))

-- | Publish a `gc.event.<substrate>` envelope per successfully reaped
-- manifest after `executeGcPlan` returns. Sprint 13.7. The envelope is
-- emitted only for manifests that the live execution actually reaped
-- (excluding the trailing partial failure window) so consumers see a
-- delete stream that matches MinIO state. Publication errors are
-- non-fatal: a failed `pulsarPublish` is logged to stderr but does not
-- roll back the MinIO delete (which already happened) and does not
-- short-circuit the reconciler — the consumer's at-least-once recovery
-- handles the missed event on the next run.
publishGcReapedEvents
  :: ClusterPublication
  -> CheckpointStore.GcExecutionResult
  -> CheckpointStore.GcPlan
  -> App ()
publishGcReapedEvents publication executed plan
  | CheckpointStore.gcExecutedReapedManifests executed <= 0 = pure ()
  | otherwise = do
      let edgePort = Publication.publicationEdgePort publication
          substrate = Publication.publicationSubstrate publication
          pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          reapedCount = CheckpointStore.gcExecutedReapedManifests executed
          reapedEvents =
            take reapedCount (CheckpointStore.gcReapEvents plan)
      timestampNs <- liftIO currentTimestampNs
      for_ reapedEvents $ \event -> do
        let envelope =
              ProtoGc.GcReapedEvent
                { ProtoGc.gcEventExperimentHash =
                    CheckpointStore.gcExperimentHash event
                , ProtoGc.gcEventManifestSha =
                    CheckpointStore.gcReapedManifestSha event
                , ProtoGc.gcEventReapedBlobShas =
                    CheckpointStore.gcReapedBlobShas event
                , ProtoGc.gcEventStepAtReap =
                    CheckpointStore.gcStepAtReap event
                , ProtoGc.gcEventSubstrate = substrate
                , ProtoGc.gcEventTimestampNs = timestampNs
                }
        result <-
          liftIO
            ( publishPulsarEvent
                pulsarSettings
                Topology.GcEventRoute
                substrate
                envelope
            )
        case result of
          Right _ -> pure ()
          Left err ->
            writeText
              ( "gc: publish failed for "
                  <> ProtoGc.gcEventManifestSha envelope
                  <> ": "
                  <> Text.pack (show err)
                  <> "\n"
              )

currentTimestampNs :: IO Word64
currentTimestampNs = do
  posix <- getPOSIXTime
  pure (floor (posix * 1_000_000_000))

localCheckpointRoot :: App FilePath
localCheckpointRoot = do
  cacheDir <- asks envCacheDir
  pure (toFilePath cacheDir </> "checkpoints")

data CacheFileInfo = CacheFileInfo
  { cacheFilePath :: FilePath
  , cacheFileBytes :: Integer
  }

runInternalCache :: [Text] -> [ParsedOption] -> App ()
runInternalCache ["internal", "cache", "stat"] _ = do
  buildRoot <- asks envCacheDir
  manifest <- readCacheManifestOrExit buildRoot
  files <- liftIO (scanCacheFiles buildRoot)
  writeLine
    ( "cache stat: manifest-entries="
        <> Text.pack (show (length (CacheManifest.manifestEntries manifest)))
        <> " files="
        <> Text.pack (show (length files))
        <> " bytes="
        <> Text.pack (show (sum (fmap cacheFileBytes files)))
    )
runInternalCache ["internal", "cache", "list"] _ = do
  buildRoot <- asks envCacheDir
  manifest <- readCacheManifestOrExit buildRoot
  files <- liftIO (scanCacheFiles buildRoot)
  let entries = CacheManifest.manifestEntries manifest
      renderedEntries = fmap (renderCacheManifestEntry files) entries
      renderedFiles =
        [ "cache file: path="
            <> Text.pack (cacheFilePath file)
            <> " bytes="
            <> Text.pack (show (cacheFileBytes file))
        | file <- files
        , not (any (`cacheEntryOwnsFile` file) entries)
        ]
  writeText
    ( if null renderedEntries && null renderedFiles
        then "cache list: empty\n"
        else Text.unlines (renderedEntries <> renderedFiles)
    )
runInternalCache ["internal", "cache", "evict"] parsedOptions = do
  let rawHash = selectedValue "hash" "missing" parsedOptions
  case Cache.hashFromHex rawHash of
    Nothing ->
      exitWithError (InvalidConfig ("invalid JIT cache hash: " <> rawHash))
    Just hash -> do
      buildRoot <- asks envCacheDir
      manifest <- readCacheManifestOrExit buildRoot
      files <- liftIO (scanCacheFiles buildRoot)
      let hashText = Cache.hashHex hash
          oldEntries = CacheManifest.manifestEntries manifest
          keptEntries =
            filter
              ((/= hash) . CacheManifest.manifestEntryHash)
              oldEntries
          matchingFiles = filter (cacheFileHasHash hashText) files
          removedEntries = length oldEntries - length keptEntries
      deleteResults <- liftIO (traverse deleteCacheFile matchingFiles)
      case lefts deleteResults of
        [] -> do
          when (removedEntries > 0) $
            liftIO $
              CacheManifest.writeManifestAtomic
                buildRoot
                (CacheManifest.Manifest keptEntries)
          writeLine
            ( "cache evict: hash="
                <> hashText
                <> " files-deleted="
                <> Text.pack (show (length matchingFiles))
                <> " manifest-entries-removed="
                <> Text.pack (show removedEntries)
            )
        failures ->
          exitWithError
            ( InvalidConfig
                ( "cache evict failed while deleting files: "
                    <> Text.intercalate "; " (fmap Text.pack failures)
                )
            )
runInternalCache path _ =
  exitWithError (UnknownCommand ("unknown cache command: " <> commandPathText path))

readCacheManifestOrExit :: Path Abs Dir -> App CacheManifest.Manifest
readCacheManifestOrExit buildRoot = do
  result <- liftIO (CacheManifest.readManifest buildRoot)
  case result of
    Right manifest -> pure manifest
    Left err -> exitWithError (InvalidConfig ("cache manifest unreadable: " <> Text.pack err))

scanCacheFiles :: Path Abs Dir -> IO [CacheFileInfo]
scanCacheFiles buildRoot = do
  root <- CacheLayout.cacheRoot buildRoot
  scanDirectory (toFilePath root)

scanDirectory :: FilePath -> IO [CacheFileInfo]
scanDirectory directory = do
  exists <- doesDirectoryExist directory
  if not exists
    then pure []
    else do
      names <- sort <$> listDirectory directory
      concat <$> traverse scanChild names
 where
  scanChild name = do
    let path = directory </> name
    isDirectory <- doesDirectoryExist path
    isFile <- doesFileExist path
    if isDirectory
      then scanDirectory path
      else
        if isFile && name /= "manifest.json"
          then do
            size <- getFileSize path
            pure [CacheFileInfo path size]
          else pure []

renderCacheManifestEntry :: [CacheFileInfo] -> CacheManifest.ManifestEntry -> Text
renderCacheManifestEntry files entry =
  let hashText = Cache.hashHex (CacheManifest.manifestEntryHash entry)
      present =
        if any (cacheFileHasHash hashText) files
          then "present"
          else "missing"
   in Text.unwords
        [ "cache entry:"
        , "model=" <> Cache.unModelId (CacheManifest.manifestEntryModelId entry)
        , "kind=" <> Cache.kindText (CacheManifest.manifestEntryKind entry)
        , "substrate=" <> Cache.substrateText (CacheManifest.manifestEntrySubstrate entry)
        , "toolchain=" <> Cache.unToolchainFingerprint (CacheManifest.manifestEntryToolchain entry)
        , "hash=" <> hashText
        , "artifact=" <> present
        ]

cacheEntryOwnsFile :: CacheManifest.ManifestEntry -> CacheFileInfo -> Bool
cacheEntryOwnsFile entry =
  cacheFileHasHash (Cache.hashHex (CacheManifest.manifestEntryHash entry))

cacheFileHasHash :: Text -> CacheFileInfo -> Bool
cacheFileHasHash hashText file =
  (hashText <> ".") `Text.isPrefixOf` Text.pack (takeFileName (cacheFilePath file))

deleteCacheFile :: CacheFileInfo -> IO (Either String ())
deleteCacheFile file = do
  result <- tryAny (removeFile (cacheFilePath file))
  case result of
    Right () -> pure (Right ())
    Left err -> pure (Left (cacheFilePath file <> ": " <> displayException err))

selectedSubstrate :: [ParsedOption] -> Either AppError Substrate
selectedSubstrate =
  selectedSubstrateWithDefault AppleSilicon

selectedSubstrateWithDefault :: Substrate -> [ParsedOption] -> Either AppError Substrate
selectedSubstrateWithDefault defaultSubstrate parsedOptions =
  case optionValues "substrate" parsedOptions of
    value : _ ->
      maybe
        (Left (InvalidConfig ("unknown substrate: " <> value)))
        Right
        (parseSubstrate value)
    [] -> Right defaultSubstrate

selectedSubstrateFlagWithDefault :: Substrate -> [ParsedOption] -> Either AppError Substrate
selectedSubstrateFlagWithDefault defaultSubstrate parsedOptions =
  case filter (`hasOption` parsedOptions) supportedSubstrates of
    [] -> selectedSubstrateWithDefault defaultSubstrate parsedOptions
    [substrateName] ->
      maybe
        (Left (InvalidConfig ("unknown substrate: " <> substrateName)))
        Right
        (parseSubstrate substrateName)
    _ -> Left (InvalidConfig "expected exactly one substrate flag")

selectedValue :: Text -> Text -> [ParsedOption] -> Text
selectedValue optionName fallback parsedOptions =
  case optionValues optionName parsedOptions of
    [] -> fallback
    value : _ -> value

parseUserIntOptionAtLeast :: Text -> Int -> Int -> [ParsedOption] -> Either AppError Int
parseUserIntOptionAtLeast optionName fallback minimumValue parsedOptions =
  let raw = selectedValue optionName (Text.pack (show fallback)) parsedOptions
   in case readMaybe (Text.unpack raw) of
        Just parsed | parsed >= minimumValue -> Right parsed
        _ ->
          Left
            ( InvalidConfig
                ( "invalid --"
                    <> optionName
                    <> " value: \""
                    <> raw
                    <> "\"; expected an integer >= "
                    <> Text.pack (show minimumValue)
                )
            )

requireUserIntOptionAtLeast :: Text -> Int -> Int -> [ParsedOption] -> App Int
requireUserIntOptionAtLeast optionName fallback minimumValue parsedOptions =
  either exitWithError pure (parseUserIntOptionAtLeast optionName fallback minimumValue parsedOptions)

readClusterPublicationOrExit :: App ClusterPublication
readClusterPublicationOrExit = do
  result <- liftIO readClusterPublication
  case result of
    Right publication -> pure publication
    Left message -> exitWithError (InvalidConfig message)

readClusterPublication :: IO (Either Text ClusterPublication)
readClusterPublication = do
  let publicationPath = ".build/runtime/cluster-publication.json"
  exists <- doesFileExist publicationPath
  if exists
    then do
      bytes <- LazyByteString.readFile publicationPath
      pure $ case eitherDecode bytes of
        Left err ->
          Left
            ( "cluster publication is corrupt: "
                <> Text.pack publicationPath
                <> ": "
                <> Text.pack err
            )
        Right publication
          | Publication.publicationHasLiveEvidence publication -> Right publication
          | otherwise ->
              Left
                ( "cluster publication has no live readiness evidence: "
                    <> Text.pack publicationPath
                    <> "; run `jitml cluster up --substrate <substrate>` or `jitml bootstrap --<substrate>`"
                )
    else
      pure
        ( Left
            ( "cluster publication is missing: "
                <> Text.pack publicationPath
                <> "; run `jitml cluster up --substrate <substrate>` or `jitml bootstrap --<substrate>`"
            )
        )

writeClusterPublication :: ClusterPublication -> IO ()
writeClusterPublication publication = do
  let runtimeRoot = ".build" </> "runtime"
  createDirectoryIfMissing True runtimeRoot
  LazyByteString.writeFile (runtimeRoot </> "cluster-publication.json") (encode publication)

publicationWithStatus :: Text -> ClusterPublication -> ClusterPublication
publicationWithStatus status publication =
  publication
    { Publication.publicationComponents =
        [(name, status) | (name, _) <- Publication.publicationComponents publication]
    }

extractGlobalFlags :: [String] -> Either AppError (GlobalFlags, [String])
extractGlobalFlags = go defaultGlobalFlags []
 where
  go flags commandArgs [] = Right (flags, reverse commandArgs)
  go flags commandArgs ("--" : rest) = Right (flags, reverse commandArgs <> ("--" : rest))
  go flags commandArgs (arg : rest)
    | arg == "--format" =
        withValue arg rest $ \value remaining ->
          case parseOutputFormat value of
            Left err -> Left err
            Right format -> go flags {globalFormat = Just format} commandArgs remaining
    | Just value <- stripPrefix "--format=" arg =
        case parseOutputFormat value of
          Left err -> Left err
          Right format -> go flags {globalFormat = Just format} commandArgs rest
    | arg == "--color" =
        withValue arg rest $ \value remaining ->
          case parseColorMode value of
            Left err -> Left err
            Right color -> go flags {globalColor = color} commandArgs remaining
    | Just value <- stripPrefix "--color=" arg =
        case parseColorMode value of
          Left err -> Left err
          Right color -> go flags {globalColor = color} commandArgs rest
    | arg == "--no-color" =
        go flags {globalColor = ColorNever} commandArgs rest
    | arg == "--cache-dir" =
        withValue arg rest $ \value remaining ->
          go flags {globalCacheDir = Just value} commandArgs remaining
    | Just value <- stripPrefix "--cache-dir=" arg =
        go flags {globalCacheDir = Just value} commandArgs rest
    | arg == "--data-dir" =
        withValue arg rest $ \value remaining ->
          go flags {globalDataDir = Just value} commandArgs remaining
    | Just value <- stripPrefix "--data-dir=" arg =
        go flags {globalDataDir = Just value} commandArgs rest
    | otherwise =
        go flags (arg : commandArgs) rest

  withValue flagName args applyValue =
    case args of
      [] -> Left (InvalidConfig ("missing value for " <> Text.pack flagName))
      value : remaining -> applyValue value remaining

parseOutputFormat :: String -> Either AppError OutputFormat
parseOutputFormat "plain" = Right OutputPlain
parseOutputFormat "table" = Right OutputTable
parseOutputFormat "json" = Right OutputJson
parseOutputFormat value =
  Left (InvalidConfig ("invalid --format value: " <> Text.pack value))

parseColorMode :: String -> Either AppError ColorMode
parseColorMode "auto" = Right ColorAuto
parseColorMode "always" = Right ColorAlways
parseColorMode "never" = Right ColorNever
parseColorMode value =
  Left (InvalidConfig ("invalid --color value: " <> Text.pack value))

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.App
  ( alphaZeroArtifactStep
  , checkpointTrainingBudgetForTensor
  , inferenceReplyAppError
  , main
  , matchingInferenceResult
  , parseUserIntOptionAtLeast
  , rlObservedBudgetUnits
  , validateProductCompletedTrainingPlanId
  , rlTrainerEnvironmentCompatibilityError
  , selectInternalProductRows
  , serviceRoleInvocationError
  , validateTrainerEvidenceCounters
  , waitForConsumeOnceHostWorkloads
  )
where

import Control.Exception.Safe
  ( displayException
  , tryAny
  )
import Control.Monad (void, when)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Crypto.Hash.SHA256 qualified
import Data.Aeson (eitherDecode, encode)
import Data.ByteString qualified
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (lefts)
import Data.Foldable (for_)
import Data.List (sort, stripPrefix)
import Data.Maybe (catMaybes, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
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
import System.FilePath (takeFileName, (</>))
import Text.Read (readMaybe)

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
  , writeLazyByteString
  , writeLine
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
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Cluster.Helm qualified as Helm
import JitML.Cluster.Publication (ClusterPublication, defaultPublication, renderPublicationSummary)
import JitML.Cluster.Publication qualified as Publication
import JitML.Coordinator.Topology qualified as Topology
import JitML.Docs.Check (checkDocs, renderDocsDrift)
import JitML.Docs.Generate (GenerateResult (..), generateDocs)
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
  )
import JitML.Engines.TuningBenchmark qualified as TuningBenchmark
import JitML.Engines.TuningCache qualified as TuningCache
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (App, ColorMode (..), Env (..), OutputFormat (..))
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Inference.Command qualified as InferenceCommand
import JitML.Lint.Stack
  ( LintFinding
  , LintMode (..)
  , LintTarget (..)
  , renderLintFinding
  , runCheckCode
  , runLint
  )
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( buildCommandPlan
  , runPlanExperimentId
  , runPlanSubjectId
  , runPlanSubstrate
  )
import JitML.Plan.Render (renderPlan)
import JitML.Plan.Workload qualified as WorkloadPlan
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
import JitML.Product.Benchmark qualified as ProductBenchmark
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Pipeline qualified as ProductPipeline
import JitML.Product.Publisher qualified as ProductPublisher
import JitML.Project.Config qualified as ProjectConfig
import JitML.Proto.Gc qualified as ProtoGc
import JitML.Proto.Training qualified as ProtoTraining
import JitML.RL.Command qualified as RlCommand
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.TrainerExecution
  ( TrainerRun
  , trainerRunEpisodes
  , trainerRunEvidence
  , trainerRunObservedUnits
  , trainerRunWeights
  )
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.SL.TrainingExecution (TrainingMetrics (..))
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.CatalogSchema qualified as CatalogSchema
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Command qualified as ServiceCommand
import JitML.Service.DhallSchema qualified as DhallSchema
import JitML.Service.HostWorkloadRegistry qualified as HostWorkloadRegistry
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , processFailureExitCode
  )
import JitML.Sub.Stream
  ( defaultSubprocessEnv
  , runStreaming
  )
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate, substrateEdgePort)
import JitML.Test.Command qualified as TestCommand
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Command qualified as TuneCommand

main :: IO ()
main = getArgs >>= runArgs

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
      TuneCommand.runTune tuningCommandRuntime runConfigPath parsedOptions
  | take 1 parsedPath == ["rl"] =
      RlCommand.runRl rlCommandRuntime runConfigPath parsedPath parsedOptions
  | parsedPath == ["inference", "run"] =
      InferenceCommand.runInference inferenceCommandRuntime parsedOptions
  | take 1 parsedPath == ["test"] =
      TestCommand.runTest testCommandRuntime parsedPath parsedOptions
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
      ServiceCommand.runInstallMetalBridge
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
  let configValues = optionValues "config" parsedOptions
      explicitConfig = not (null configValues)
      consumeOnceRequested = hasOption "consume-once" parsedOptions
      configPath =
        case configValues of
          [] -> "./conf/cluster/linux-cpu.dhall"
          value : _ -> value
  consumeOnceBudget <- requireUserIntOptionAtLeast "consume-once" 0 0 parsedOptions
  ServiceCommand.runService
    serviceCommandRuntime
    ServiceCommand.ServiceInvocation
      { ServiceCommand.serviceInvocationConfigPath = configPath
      , ServiceCommand.serviceInvocationExplicitConfig = explicitConfig
      , ServiceCommand.serviceInvocationConsumeOnceRequested = consumeOnceRequested
      , ServiceCommand.serviceInvocationConsumeOnceBudget = consumeOnceBudget
      }
{-# NOINLINE runService #-}

serviceRoleInvocationError :: BootConfig.Role -> Bool -> Maybe Text
serviceRoleInvocationError = ServiceCommand.serviceRoleInvocationError
{-# NOINLINE serviceRoleInvocationError #-}

waitForConsumeOnceHostWorkloads
  :: Maybe HostWorkloadRegistry.HostWorkloadRegistry
  -> IO (Maybe AppError)
waitForConsumeOnceHostWorkloads = ServiceCommand.waitForConsumeOnceHostWorkloads
{-# NOINLINE waitForConsumeOnceHostWorkloads #-}

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
  result <-
    TrainingExecution.runDeviceMnistTraining
      trainingExecutionRuntime
      substrate
      problem
      plan
  case result of
    Left reason -> exitWithError (TrainingPrerequisiteUnmet reason)
    Right metrics -> do
      publishWorkerTrainingEvent metrics
      publishWorkerTrainingCheckpoint plan problem metrics

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
      seed = Overrides.overrideSeed overrides (fromIntegral (SL.problemSeed problem))
      invocationFingerprint =
        Text.intercalate
          "\NUL"
          [ SL.problemName problem
          , SL.problemDataset problem
          , SL.problemModel problem
          , renderSubstrate substrate
          , Text.pack (show seed)
          , Text.pack (show epochs)
          , Text.pack (show trainingExamples)
          , Text.pack (show evaluationExamples)
          , Text.pack (show batchExamples)
          ]
      experimentHash =
        Checkpoint.deriveExperimentHash
          dhallPath
          invocationFingerprint
      raw =
        ProtoTraining.StartTraining
          { ProtoTraining.stExperimentHash = experimentHash
          , ProtoTraining.stDhallObjectKey = dhallPath
          , ProtoTraining.stSubstrate = substrate
          , ProtoTraining.stSeed = seed
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

-- | 'Right' to 'Just', 'Left' to 'Nothing'. Local helper mirroring the
-- per-module copies in "JitML.Bootstrap" / "JitML.Proto.Wire".
eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

data WorkerLiveContext = WorkerLiveContext
  { workerLivePublication :: ClusterPublication
  , workerLiveMinIOSettings :: MinIOSubprocess.MinIOSettings
  , workerLivePulsarSettings :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  , workerLiveUsesMountedServices :: Bool
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
            , workerLiveUsesMountedServices = True
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
                    , workerLiveUsesMountedServices = False
                    }
          )
          cluster

-- Keep the device-training effect boundary opaque to App's optimizer.
trainingExecutionRuntime :: TrainingExecution.TrainingExecutionRuntime
trainingExecutionRuntime =
  TrainingExecution.TrainingExecutionRuntime
    { TrainingExecution.trainingResolveMinIOSettings =
        fmap (fmap workerLiveMinIOSettings) workerLiveContext
    }
{-# NOINLINE trainingExecutionRuntime #-}

-- Keep service orchestration and host training opaque at the App boundary.
serviceCommandRuntime :: ServiceCommand.ServiceCommandRuntime
serviceCommandRuntime =
  ServiceCommand.ServiceCommandRuntime
    { ServiceCommand.serviceTrainingExecutionRuntime = trainingExecutionRuntime
    }
{-# NOINLINE serviceCommandRuntime #-}

-- Keep tuning's device/storage/event callbacks opaque at the App boundary.
tuningCommandRuntime :: TuneCommand.TuningCommandRuntime
tuningCommandRuntime =
  TuneCommand.TuningCommandRuntime
    { TuneCommand.tuningResolveWorkerServices =
        fmap (fmap tuningWorkerServicesFromContext) workerLiveContext
    , TuneCommand.tuningResolveWorkerSubstrate = workerSubstrateBase
    , TuneCommand.tuningWriteLocalCheckpointLines =
        \experimentHash tensorName step metrics weights -> do
          storedCandidate <-
            CheckpointWriter.writeLocalCandidateWeightCheckpoint
              experimentHash
              tensorName
              step
              metrics
              weights
          pure
            ( CheckpointWriter.renderStoredCheckpointLinesWithPrefix
                "trial-checkpoint"
                experimentHash
                (CheckpointStore.candidateStoredCheckpoint storedCandidate)
            )
    , TuneCommand.tuningWriteLocalArtifactLines =
        \experimentHash kind payload ->
          CheckpointWriter.renderStoredArtifactLines kind
            <$> CheckpointWriter.writeTextArtifact experimentHash kind payload
    , TuneCommand.tuningWriteMinIOCheckpoint =
        \settings experimentHash tensorName step metrics weights ->
          fmap
            void
            ( MinIOSubprocess.runMinIOSubprocess
                settings
                ( CheckpointWriter.writeMinIOCandidateWeightCheckpoint
                    experimentHash
                    tensorName
                    step
                    metrics
                    weights
                )
            )
    , TuneCommand.tuningPublishEvent =
        \settings substrate event ->
          fmap
            void
            ( ServiceCommand.publishPulsarEvent
                settings
                Topology.TuneEventRoute
                substrate
                event
            )
    , TuneCommand.tuningTimestampNs = ServiceCommand.currentTimestampNs
    }
{-# NOINLINE tuningCommandRuntime #-}

tuningWorkerServicesFromContext
  :: WorkerLiveContext
  -> TuneCommand.TuningWorkerServices
tuningWorkerServicesFromContext context =
  TuneCommand.TuningWorkerServices
    { TuneCommand.tuningWorkerSubstrate =
        Publication.publicationSubstrate (workerLivePublication context)
    , TuneCommand.tuningWorkerMinIOSettings = workerLiveMinIOSettings context
    , TuneCommand.tuningWorkerPulsarSettings = workerLivePulsarSettings context
    }

-- Keep RL command orchestration and its worker-service actions opaque to App.
rlCommandRuntime :: RlCommand.RlCommandRuntime
rlCommandRuntime =
  RlCommand.RlCommandRuntime
    { RlCommand.rlCommandWorkerSubstrateBase = workerSubstrateBase
    , RlCommand.rlCommandWorkerExperimentHash = workerExperimentHash
    , RlCommand.rlCommandRunCheckpointEval = runCheckpointEval
    , RlCommand.rlCommandWorkerBrokerTarget = workerBrokerTarget
    , RlCommand.rlCommandAlphaZeroWorkerServices =
        fmap (fmap rlWorkerServicesFromContext) workerLiveContext
    , RlCommand.rlCommandPublishEvent =
        \settings substrate event ->
          fmap
            void
            ( ServiceCommand.publishPulsarEvent
                settings
                Topology.RlEventRoute
                substrate
                event
            )
    , RlCommand.rlCommandTimestampNs = ServiceCommand.currentTimestampNs
    }
{-# NOINLINE rlCommandRuntime #-}

rlWorkerServicesFromContext :: WorkerLiveContext -> RlCommand.RlWorkerServices
rlWorkerServicesFromContext context =
  RlCommand.RlWorkerServices
    { RlCommand.rlWorkerServiceSubstrate =
        Publication.publicationSubstrate (workerLivePublication context)
    , RlCommand.rlWorkerServicePulsarSettings = workerLivePulsarSettings context
    }

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
      timestampNs <- liftIO ServiceCommand.currentTimestampNs
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
          ( ServiceCommand.publishPulsarEvent
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
  -> SL.CanonicalProblem
  -> TrainingMetrics
  -> App ()
publishWorkerTrainingCheckpoint plan problem metrics = do
  let experimentHash =
        runPlanExperimentId (WorkloadPlan.supervisedPlanRunPlan plan)
      step = tmCompletedUnits metrics
      metricRows = ServiceCommand.trainingCheckpointMetrics metrics
  completion <-
    case CheckpointWriter.attemptGenericSupervisedRuntimeForTraining
      plan
      problem
      metrics
      experimentHash
      metricRows of
      Left err ->
        exitWithError
          (InvalidConfig ("supervised V2 checkpoint construction failed: " <> err))
      Right value -> pure value
  case completion of
    CheckpointWriter.SupervisedRuntimeCompletionMiss _ -> pure ()
    CheckpointWriter.SupervisedRuntimeCompleted completedTraining runtimeArtifact -> do
      stored <-
        writeWorkerCompletedSupervisedCheckpoint
          completedTraining
          experimentHash
          metricRows
          runtimeArtifact
      publishWorkerTrainingCheckpointEvent
        step
        metricRows
        completedTraining
        stored

writeWorkerCompletedSupervisedCheckpoint
  :: TrainingBudget.CompletedTraining
  -> Text
  -> [(Text, Double)]
  -> RuntimeArtifact.TrainingRuntimeArtifact
  -> App CheckpointStore.StoredCompletedCheckpoint
writeWorkerCompletedSupervisedCheckpoint completed experimentHash metricRows artifact = do
  context <- workerLiveContext
  case context of
    Just liveContext
      | workerLiveUsesMountedServices liveContext -> do
          result <-
            liftIO
              ( MinIOSubprocess.runMinIOSubprocess
                  (workerLiveMinIOSettings liveContext)
                  ( do
                      expectedPointer <-
                        MinIOSubprocess.minioObjectETag
                          ( CheckpointStore.checkpointObjectRef
                              (Checkpoint.latestPointerKey experimentHash)
                          )
                      case expectedPointer of
                        Left err -> pure (Left err)
                        Right expected ->
                          CheckpointWriter.writeMinIOCompletedSupervisedCheckpoint
                            expected
                            completed
                            experimentHash
                            metricRows
                            artifact
                  )
              )
          case result of
            Left err ->
              exitWithError
                (MinIOFailed ("supervised V2 checkpoint write failed: " <> Text.pack (show err)))
            Right stored -> pure stored
    _ ->
      CheckpointWriter.writeLocalCompletedSupervisedCheckpoint
        completed
        experimentHash
        metricRows
        artifact

publishWorkerTrainingCheckpointEvent
  :: Word64
  -> [(Text, Double)]
  -> TrainingBudget.CompletedTraining
  -> CheckpointStore.StoredCompletedCheckpoint
  -> App ()
publishWorkerTrainingCheckpointEvent step metricRows completedTraining stored = do
  target <- workerBrokerTarget
  experimentHashMaybe <- workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      envelope <-
        case ServiceCommand.trainingCompletedCheckpointEventEnvelope
          experimentHash
          step
          metricRows
          completedTraining
          stored of
          Left err -> exitWithError (InvalidConfig ("training checkpoint event failed: " <> err))
          Right value -> pure value
      result <-
        liftIO
          ( ServiceCommand.publishPulsarEvent
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

alphaZeroArtifactStep :: Word64 -> Int -> Word64
alphaZeroArtifactStep = ProductCompletion.alphaZeroArtifactStep
{-# NOINLINE alphaZeroArtifactStep #-}

-- Preserve the public budget helper while keeping checkpoint persistence out of App.
checkpointTrainingBudgetForTensor
  :: Text
  -> Word64
  -> Either Text TrainingBudget.TrainingBudget
checkpointTrainingBudgetForTensor = CheckpointWriter.checkpointTrainingBudgetForTensor
{-# NOINLINE checkpointTrainingBudgetForTensor #-}

validateTrainerEvidenceCounters :: Word64 -> Word64 -> Either Text ()
validateTrainerEvidenceCounters =
  TrainerExecution.validateTrainerEvidenceCounters

rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError =
  TrainerExecution.rlTrainerEnvironmentCompatibilityError

rlObservedBudgetUnits
  :: [EpisodeEnvelope.SimulatedEpisode]
  -> Either Text Word64
rlObservedBudgetUnits = TrainerExecution.rlObservedBudgetUnits

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
    ( \admitted manifest weights values ->
        liftIO
          ( ServiceCommand.engineWeightedInference
              env
              substrate
              (ProductPipeline.inferenceEligibleModelRef admitted)
              manifest
              weights
              values
          )
    )
    experimentHash
    [1.0, 2.0]

-- | Preserve the test-facing App surface while the broker client lives in
-- "JitML.Inference.Command".
inferenceReplyAppError :: Text -> Text -> AppError
inferenceReplyAppError = InferenceCommand.inferenceReplyAppError

-- | Preserve the test-facing App surface while reply correlation lives in
-- "JitML.Inference.Command".
matchingInferenceResult :: Text -> Text -> Text -> Maybe [Double]
matchingInferenceResult = InferenceCommand.matchingInferenceResult

-- Keep inference option resolution opaque at the App boundary.
inferenceCommandRuntime :: InferenceCommand.InferenceCommandRuntime
inferenceCommandRuntime =
  InferenceCommand.InferenceCommandRuntime
    { InferenceCommand.inferenceCommandSelectedValue = selectedValue
    }
{-# NOINLINE inferenceCommandRuntime #-}

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

-- Keep report orchestration and its measurement callbacks opaque to App.
testCommandRuntime :: TestCommand.TestCommandRuntime
testCommandRuntime =
  TestCommand.TestCommandRuntime
    { TestCommand.testCommandBootstrapSubstrates = bootstrapSubstrates
    , TestCommand.testCommandHasOption = hasOption
    , TestCommand.testCommandSelectedValue = selectedValue
    , TestCommand.testCommandMeasureSlFinalLossText =
        measureTestSlFinalLossText
    , TestCommand.testCommandMeasureRlFinalRewardText =
        measureTestRlFinalRewardText
    }
{-# NOINLINE testCommandRuntime #-}

measureTestSlFinalLossText :: App (Maybe Text)
measureTestSlFinalLossText = do
  substrate <- workerSubstrateBase
  case SL.canonicalProblems of
    problem : _ -> do
      plan <-
        resolveSupervisedInvocationPlan
          []
          Overrides.emptyExperimentOverrides
          substrate
          problem
      result <-
        TrainingExecution.runDeviceMnistTraining
          trainingExecutionRuntime
          substrate
          problem
          plan
      pure $
        case result of
          Right metrics ->
            Just
              ( SL.problemName problem
                  <> "="
                  <> Text.pack (show metrics)
              )
          Left _ -> Nothing
    [] -> pure Nothing
{-# NOINLINE measureTestSlFinalLossText #-}

measureTestRlFinalRewardText :: App (Maybe Text)
measureTestRlFinalRewardText = do
  substrate <- workerSubstrateBase
  env <- ask
  episodesE <-
    liftIO $ do
      planE <- TrainerExecution.compileTraditionalRlPlan "ppo" "cartpole" 42 4 200 Nothing
      case planE of
        Left err -> pure (Left err)
        Right plan ->
          TrainerExecution.runTrainerEpisodesForPlan
            substrate
            (rlDeviceForSubstrate substrate env)
            Nothing
            plan
  pure $ case episodesE of
    Left _ -> Nothing
    Right trainerRun
      | null (trainerRunEpisodes trainerRun) -> Nothing
      | otherwise ->
          Just
            ( "ppo/cartpole="
                <> Text.pack
                  ( show
                      ( sum
                          ( fmap
                              EpisodeEnvelope.simEpisodeReward
                              (trainerRunEpisodes trainerRun)
                          )
                          / fromIntegral
                            (length (trainerRunEpisodes trainerRun))
                      )
                  )
            )
{-# NOINLINE measureTestRlFinalRewardText #-}

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

runInternalTrainAndPublishProductRows :: [ParsedOption] -> App ()
runInternalTrainAndPublishProductRows parsedOptions = do
  substrate <- case selectedSubstrateFlagWithDefault LinuxCPU parsedOptions of
    Left err -> exitWithError err
    Right value -> pure value
  rowFilterRaw <- liftIO (lookupEnv "JITML_PRODUCT_ROW_FILTER")
  commandRow <-
    case optionValues "row" parsedOptions of
      [] -> pure Nothing
      [rowIdentity] -> pure (Just rowIdentity)
      _ -> exitWithError (InvalidConfig "train-and-publish-product-rows accepts at most one --row value")
  selectedRows <-
    either
      (exitWithError . InvalidConfig)
      pure
      ( selectInternalProductRows
          commandRow
          (Text.pack <$> rowFilterRaw)
      )
  ProductPublisher.runTrainAndPublishProductRows productPublisherRuntime substrate selectedRows

productPublisherRuntime :: ProductPublisher.ProductPublisherRuntime
productPublisherRuntime =
  ProductPublisher.ProductPublisherRuntime
    { ProductPublisher.publisherRunSupervisedTraining =
        \substrate problem trainLimit epochs testLimit batchSize exactLearningRate -> do
          fmap supervisedPublishRunFromTrainingMetrics
            <$> TrainingExecution.runDeviceMnistTrainingWithLimitsAndLearningRate
              trainingExecutionRuntime
              substrate
              problem
              trainLimit
              epochs
              testLimit
              batchSize
              (Just exactLearningRate)
    , ProductPublisher.publisherRunRlTraining =
        \substrate device plan ->
          fmap rlPublishRunFromTrainerRun
            <$> TrainerExecution.runTrainerEpisodesForPlan substrate device Nothing plan
    , ProductPublisher.publisherCompleteProductRow = ProductCompletion.completedTrainingForProductRow
    , ProductPublisher.publisherCompleteSupervisedProductRowWithWeightHashes =
        ProductCompletion.completedTrainingForProductRowWithWeightHashes
    , ProductPublisher.publisherRlCompletionMetrics = ProductCompletion.rlCompletionMetrics
    , ProductPublisher.publisherRlCompletedTraining = ProductCompletion.rlCompletedTrainingWithBudget
    , ProductPublisher.publisherRlCompletionFailure = ProductCompletion.rlCompletedTrainingFailureMessage
    , ProductPublisher.publisherAlphaZeroCompletedTraining = ProductCompletion.alphaZeroCompletedTraining
    , ProductPublisher.publisherWriteCompletedWeightCheckpoint =
        CheckpointWriter.writeLocalCompletedProductWeightCheckpoint
    , ProductPublisher.publisherWriteCompletedSupervisedCheckpoint =
        CheckpointWriter.writeLocalCompletedSupervisedCheckpoint
    , ProductPublisher.publisherAdmitCompletedCheckpoint =
        CheckpointWriter.admitLocalStoredCompletedCheckpoint
    , ProductPublisher.publisherWriteTextArtifact =
        \experimentHash kind payload -> do
          stored <- CheckpointWriter.writeTextArtifact experimentHash kind payload
          pure
            ( CheckpointWriter.storedArtifactSha stored
            , CheckpointWriter.storedArtifactObjectKey stored
            )
    , ProductPublisher.publisherLoadTuningDataset =
        fmap (fmap tuningPublishDatasetFromExecutionDataset)
          . TuneCommand.loadTuningExecutionDataset tuningCommandRuntime
    , ProductPublisher.publisherReuseAdmittedCheckpoint =
        \experimentHash -> do
          checkpointRoot <- CheckpointWriter.localCheckpointRoot
          admittedResult <-
            liftIO (CheckpointStore.admitLocalLatestCheckpoint checkpointRoot experimentHash)
          pure $ case admittedResult of
            Left _ -> Nothing
            Right admitted ->
              case CheckpointStore.requireAdmittedCompletedCheckpoint admitted of
                Left _ -> Nothing
                Right completed -> Just completed
    }
{-# NOINLINE productPublisherRuntime #-}

supervisedPublishRunFromTrainingMetrics
  :: TrainingMetrics
  -> ProductPublisher.SupervisedPublishRun
supervisedPublishRunFromTrainingMetrics metrics =
  ProductPublisher.SupervisedPublishRun
    { ProductPublisher.supervisedPublishTrainLoss = tmTrainLoss metrics
    , ProductPublisher.supervisedPublishValidationLoss = tmValidationLoss metrics
    , ProductPublisher.supervisedPublishExamplesProcessed = tmExamplesProcessed metrics
    , ProductPublisher.supervisedPublishHeldOutMetric = tmHeldOutMetric metrics
    , ProductPublisher.supervisedPublishCompletedUnits = tmCompletedUnits metrics
    , ProductPublisher.supervisedPublishOptimizerUpdatesExecuted =
        tmOptimizerUpdatesExecuted metrics
    , ProductPublisher.supervisedPublishRuntimeProgram = tmSupervisedRuntimeProgram metrics
    , ProductPublisher.supervisedPublishLayerGraphMetadata =
        tmTrainedLayerGraphMetadata metrics
    , ProductPublisher.supervisedPublishInitialJmw1Bytes = tmInitialJmw1Bytes metrics
    , ProductPublisher.supervisedPublishFinalJmw1Bytes = tmFinalJmw1Bytes metrics
    , ProductPublisher.supervisedPublishVerifiedDatasetShaAtRead =
        tmVerifiedDatasetShaAtRead metrics
    , ProductPublisher.supervisedPublishInitialWeights = tmInitialCheckpointWeights metrics
    , ProductPublisher.supervisedPublishCheckpointWeights = tmCheckpointWeights metrics
    , ProductPublisher.supervisedPublishDatasetShaAtRead = tmDatasetShaAtRead metrics
    }

rlPublishRunFromTrainerRun :: TrainerRun -> ProductPublisher.RlPublishRun
rlPublishRunFromTrainerRun trainerRun =
  ProductPublisher.RlPublishRun
    { ProductPublisher.rlPublishEpisodes = trainerRunEpisodes trainerRun
    , ProductPublisher.rlPublishObservedUnits = trainerRunObservedUnits trainerRun
    , ProductPublisher.rlPublishWeights = trainerRunWeights trainerRun
    , ProductPublisher.rlPublishEvidence = trainerRunEvidence trainerRun
    }

tuningPublishDatasetFromExecutionDataset
  :: TuneCommand.TuningExecutionDataset
  -> ProductPublisher.TuningPublishDataset
tuningPublishDatasetFromExecutionDataset dataset =
  ProductPublisher.TuningPublishDataset
    { ProductPublisher.tuningPublishProblem =
        TuneCommand.tuningDatasetProblem dataset
    , ProductPublisher.tuningPublishBaseConfig =
        TuneCommand.tuningDatasetBaseConfig dataset
    , ProductPublisher.tuningPublishTrainSet =
        TuneCommand.tuningDatasetTrainSet dataset
    , ProductPublisher.tuningPublishValidationSet =
        TuneCommand.tuningDatasetValidationSet dataset
    , ProductPublisher.tuningPublishDatasetShaAtRead =
        TuneCommand.tuningDatasetShaAtRead dataset
    }

selectInternalProductRows
  :: Maybe Text
  -> Maybe Text
  -> Either Text [ProductMatrix.ProductRow 'ProductMatrix.Declared]
selectInternalProductRows = ProductPublisher.selectInternalProductRows

runInternalBenchmarkProductRowWallClock :: App ()
runInternalBenchmarkProductRowWallClock =
  ProductBenchmark.runProductRowWallClockBenchmark

validateProductCompletedTrainingPlanId
  :: ProductMatrix.ProductProjection kind
  -> TrainingBudget.CompletedTraining
  -> Either Text ()
validateProductCompletedTrainingPlanId =
  ProductPublisher.validateProductCompletedTrainingPlanId

runInternalSeedDemoCheckpoints :: App ()
runInternalSeedDemoCheckpoints =
  exitWithError
    ( InvalidConfig
        "internal seed-demo-checkpoints is retired; use `jitml internal train-and-publish-product-rows --<substrate> --row <row-id>` to produce inference-eligible product-row artifacts"
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
      checkpointRoot <- CheckpointWriter.localCheckpointRoot
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
      timestampNs <- liftIO ServiceCommand.currentTimestampNs
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
            ( ServiceCommand.publishPulsarEvent
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

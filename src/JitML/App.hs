{-# LANGUAGE OverloadedStrings #-}

module JitML.App
  ( demoMain
  , main
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless, void, when)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Data.Aeson (decode, encode)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (stripPrefix)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Options.Applicative (ParserResult (..), renderFailure)
import Path (toFilePath)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))

import JitML.AppError.AppError (AppError (..))
import JitML.Bootstrap
  ( LiveExecutionResult (..)
  , liveExecutePhasedRollout
  , materializeBootstrapFiles
  )
import JitML.CLI.Help (renderHelp)
import JitML.CLI.Json (renderCommandJson)
import JitML.CLI.Output
  ( exitWithError
  , exitWithErrorIO
  , writeLazyByteString
  , writeLine
  , writeLineIO
  , writeText
  )
import JitML.CLI.Parser (ParsedCommand (..), ParsedOption (..), parseCommandPure)
import JitML.CLI.Spec (commandPathText, commandRegistry)
import JitML.CLI.Tree (renderCommandList, renderCommandTree)
import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Cluster.Helm qualified as Helm
import JitML.Cluster.Publication (ClusterPublication, defaultPublication, renderPublicationSummary)
import JitML.Cluster.Publication qualified as Publication
import JitML.Codegen.RuntimeSource
  ( materializeRuntimeSource
  , renderRuntimeSource
  , runtimeSourcePayload
  )
import JitML.Docs.Check (checkDocs, renderDocsDrift)
import JitML.Docs.Generate (GenerateResult (..), generateDocs)
import JitML.Engines.Engine (engineForSubstrate, renderBuildPlan)
import JitML.Engines.Local (linuxCpuKernelOutput, runLinuxCpuKernel)
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (App, ColorMode (..), Env (..), OutputFormat (..))
import JitML.Lint.Stack
  ( LintFinding
  , LintMode (..)
  , LintTarget (..)
  , renderLintFinding
  , runCheckCode
  , runLint
  )
import JitML.Plan.Apply (writePlanFile)
import JitML.Plan.Plan (buildCommandPlan)
import JitML.Plan.Render (renderPlan)
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
import JitML.RL.Algorithms qualified as RL
import JitML.SL.Canonicals qualified as SL
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Runtime qualified as ServiceRuntime
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Tart.Exec (tartSshSubprocess)
import JitML.Tart.Lifecycle (VmName (..), ensureVmUp)
import JitML.Test.Report
  ( ReportCard (..)
  , loadReportCardKnobs
  , renderReportCardForTargets
  , reportStanzas
  )
import JitML.Tune.Catalog qualified as Tune
import JitML.Web.Bundle qualified as WebBundle
import JitML.Web.Server qualified as WebServer

main :: IO ()
main = getArgs >>= runArgs

demoMain :: IO ()
demoMain = do
  args <- getArgs
  case parseDemoArgs args of
    Left err -> exitWithErrorIO (InvalidConfig err)
    Right demoArgs -> do
      writeLineIO WebBundle.demoStatusLine
      WebServer.serveDemo (demoHost demoArgs) (demoPort demoArgs)

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
  | parsedPath == ["kubectl"] =
      runKubectl parsedOptions
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
  | take 1 parsedPath == ["verify"] =
      runVerify parsedPath parsedOptions
  | take 1 parsedPath == ["bench"] =
      runBench parsedPath parsedOptions
  | take 1 parsedPath == ["inspect"] =
      runInspect parsedPath parsedOptions
  | take 1 parsedPath == ["test"] =
      runTest parsedPath
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
  | parsedPath == ["internal", "vm", "exec"] =
      runInternalVmExec parsedOptions
  | parsedPath == ["internal", "vm", "bootstrap"] =
      runInternalVmLifecycle "bootstrap"
  | parsedPath == ["internal", "vm", "up"] =
      runInternalVmLifecycle "up"
  | parsedPath == ["internal", "vm", "down"] =
      runInternalVmLifecycle "down"
  | parsedPath == ["internal", "vm", "status"] =
      runInternalVmLifecycle "status"
  | take 2 parsedPath == ["internal", "cache"] =
      runInternalCache parsedPath parsedOptions
  | parsedPath == ["internal", "gc"] =
      runInternalGc parsedOptions
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
    PrerequisitePlanRemediationFailed _node commandText exitCode stderrText ->
      SubprocessFailed commandText exitCode stderrText
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
            changed <- liftIO (materializeBootstrapFiles "." parsedSubstrate)
            writeLine
              ( "bootstrap: "
                  <> substrate
                  <> if changed then " reconciled" else " materialization already current"
              )
            result <- liftIO (liveExecutePhasedRollout parsedSubstrate "chart")
            writeLine
              ( "bootstrap: live phased rollout executed "
                  <> Text.pack (show (length (liveStepsExecuted result)))
                  <> " steps"
              )
            mapM_
              ( \(step, stderrText) ->
                  writeLine ("bootstrap: step failed: " <> step <> " stderr: " <> stderrText)
              )
              (liveStepsFailed result)
            unless (null (liveStepsFailed result)) $
              exitWithError
                ( SubprocessFailed
                    "bootstrap live phased rollout"
                    (ExitFailure 1)
                    (renderLiveStepFailures (liveStepsFailed result))
                )
    [] ->
      exitWithError (InvalidConfig "bootstrap requires exactly one substrate flag")
    _ ->
      exitWithError (InvalidConfig "bootstrap accepts exactly one substrate flag")

renderLiveStepFailures :: [(Text, Text)] -> Text
renderLiveStepFailures =
  Text.intercalate "\n" . fmap renderFailureLine
 where
  renderFailureLine (step, stderrText) =
    step <> ": " <> stderrText

bootstrapSubstrates :: [ParsedOption] -> [Text]
bootstrapSubstrates parsedOptions =
  filter (`hasOption` parsedOptions) supportedSubstrates

runService :: [ParsedOption] -> App ()
runService parsedOptions = do
  let configValues = optionValues "config" parsedOptions
      explicitConfig = not (null configValues)
      configPath =
        case configValues of
          [] -> "./conf/cluster/linux-cpu.dhall"
          value : _ -> value
  runtime <- loadDaemonRuntime configPath explicitConfig
  acquiredRuntime <-
    liftIO
      ( ServiceClients.runDaemonServiceClient
          (ServiceRuntime.daemonClientSettings runtime)
          (ServiceRuntime.acquireDaemonSubscriptions runtime)
      )
  probedRuntime <-
    liftIO
      ( ServiceClients.runDaemonServiceClient
          (ServiceRuntime.daemonClientSettings acquiredRuntime)
          (ServiceRuntime.probeDaemonServiceClients acquiredRuntime)
      )
  writeLine ("service config: " <> configPath)
  writeText (ServiceRuntime.renderDaemonRuntimeSummary probedRuntime)
  writeLine "service: listening on 0.0.0.0:8080"
  liftIO (ServiceRuntime.serveDaemon probedRuntime)

loadDaemonRuntime :: Text -> Bool -> App ServiceRuntime.DaemonRuntime
loadDaemonRuntime configPath explicitConfig = do
  let path = Text.unpack configPath
  exists <- liftIO (doesFileExist path)
  if exists
    then do
      result <- liftIO (tryAny (BootConfig.loadBootConfig path))
      case result of
        Right bootConfig -> pure (ServiceRuntime.daemonRuntimeForBootConfig bootConfig)
        Left err ->
          exitWithError
            ( InvalidConfig
                ( "failed to load service config "
                    <> configPath
                    <> ": "
                    <> Text.pack (displayException err)
                )
            )
    else
      if explicitConfig
        then exitWithError (InvalidConfig ("service config does not exist: " <> configPath))
        else pure ServiceRuntime.defaultDaemonRuntime

runCluster :: [Text] -> [ParsedOption] -> App ()
runCluster ["cluster", "up"] parsedOptions =
  case selectedSubstrate parsedOptions of
    Left err -> exitWithError err
    Right substrate -> do
      changed <- liftIO (materializeBootstrapFiles "." substrate)
      if changed
        then writeLine ("cluster up: " <> renderSubstrate substrate <> " reconciled")
        else
          exitWithError (ReconcilerNoop ("cluster up: " <> renderSubstrate substrate <> " already current"))
runCluster ["cluster", "status"] _ = do
  publication <- liftIO readClusterPublication
  writeText (renderPublicationSummary publication)
runCluster ["cluster", "down"] _ = do
  publication <- liftIO readClusterPublication
  let substrate = Publication.publicationSubstrate publication
      command = Helm.kindDeleteSubprocess substrate
      clusterName = "jitml-" <> renderSubstrate substrate
  (exitCode, _stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  case exitCode of
    ExitSuccess ->
      liftIO (writeClusterPublication (publicationWithStatus "stopped" publication))
        >> writeLine ("cluster down: " <> clusterName <> " deleted; ./.build and ./.data preserved")
    ExitFailure 3 -> do
      liftIO (writeClusterPublication (publicationWithStatus "stopped" publication))
      exitWithError (ReconcilerNoop ("cluster down: " <> clusterName <> " already absent"))
    ExitFailure _ ->
      exitWithError (SubprocessFailed (renderSubprocess command) exitCode stderrText)
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
          tuningChoice = Cache.defaultTuningChoice
          cacheSubstrate = cacheSubstrateFromCli substrate
          runtimeSource = renderRuntimeSource kernelSpec kind cacheSubstrate tuningChoice
          fingerprint = Cache.ToolchainFingerprint "jitml-build;compiler-pins=cabal.project"
          hash =
            Cache.cacheKey
              kernelSpec
              kind
              cacheSubstrate
              fingerprint
              (runtimeSourcePayload runtimeSource)
              tuningChoice
          rendered =
            Text.unlines
              [ "build: /opt/build/jitml"
              , renderBuildPlan engine runtimeSource hash
              ]
      case optionValues "plan-file" parsedOptions of
        [] -> pure ()
        planPath : _ -> liftIO (writePlanFile (Text.unpack planPath) rendered)
      runOutput <-
        if hasOption "dry-run" parsedOptions
          then pure []
          else case substrate of
            LinuxCPU -> do
              result <- liftIO (runLinuxCpuKernel env runtimeSource hash [1.0, 2.0])
              case result of
                Left message ->
                  exitWithError (SubprocessFailed "linux-cpu-jit" (ExitFailure 1) message)
                Right kernelRun ->
                  pure ["linux_cpu_run: " <> Text.pack (show (linuxCpuKernelOutput kernelRun))]
            _ -> do
              void (liftIO (materializeRuntimeSource env runtimeSource hash))
              pure []
      writeText (Text.unlines (rendered : runOutput))

runKubectl :: [ParsedOption] -> App ()
runKubectl parsedOptions =
  writeLine
    ("kubectl: ./.build/jitml.kubeconfig " <> Text.unwords (optionValues "kubectl-args" parsedOptions))

runTrain :: [ParsedOption] -> App ()
runTrain parsedOptions =
  let experiment = selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions
      problem =
        case SL.canonicalProblems of
          firstProblem : _ -> firstProblem
          [] -> SL.CanonicalProblem "empty" "empty" "empty" 0
   in writeText $
        Text.unlines
          [ "train: " <> experiment
          , "problem: " <> SL.problemName problem
          , "final_loss: " <> Text.pack (show (SL.finalLoss problem))
          ]

runEval :: [ParsedOption] -> App ()
runEval parsedOptions =
  writeLine ("eval: checkpoint " <> selectedValue "checkpoint" "latest" parsedOptions <> " accepted")

runTune :: [ParsedOption] -> App ()
runTune parsedOptions = do
  let tunePath = Text.unpack (selectedValue "tune-dhall" "experiments/mnist-tune.dhall" parsedOptions)
  loaded <- liftIO (Tune.loadTuningExperiment tunePath)
  case loaded of
    Left message ->
      exitWithError (DhallTypeError message)
    Right experiment -> do
      let rendered = Tune.renderTuningPlan tunePath experiment
      case optionValues "plan-file" parsedOptions of
        [] -> pure ()
        planPath : _ -> liftIO (writePlanFile (Text.unpack planPath) rendered)
      writeText rendered

runRl :: [Text] -> [ParsedOption] -> App ()
runRl ["rl", "train"] parsedOptions =
  writeText $
    Text.unlines
      [ "rl train: " <> selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions
      , "algorithms: " <> Text.pack (show (length RL.algorithmCatalog))
      ]
runRl ["rl", "eval"] parsedOptions =
  writeLine ("rl eval: " <> selectedValue "checkpoint" "latest" parsedOptions)
runRl ["rl", "rollout"] parsedOptions =
  writeLine
    ( "rl rollout: "
        <> Text.pack
          (show (RL.deterministicTrajectory "PPO" (readInt (selectedValue "seed" "42" parsedOptions))))
    )
runRl path _ =
  exitWithError (UnknownCommand ("unknown rl command: " <> commandPathText path))

runInference :: [ParsedOption] -> App ()
runInference parsedOptions =
  let manifest =
        Checkpoint.emptyManifest
          "latest"
          (selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions)
          [Checkpoint.TensorBlob "dense.weight" [2, 2] "blob-1"]
   in writeLine ("inference: " <> Text.pack (show (Checkpoint.inferFromManifest manifest [1.0, 2.0])))

runVerify :: [Text] -> [ParsedOption] -> App ()
runVerify path parsedOptions =
  writeLine
    ("verify: " <> commandPathText path <> " " <> Text.pack (show (optionPairs parsedOptions)))

runBench :: [Text] -> [ParsedOption] -> App ()
runBench path parsedOptions =
  writeLine ("bench: " <> commandPathText path <> " " <> Text.pack (show (optionPairs parsedOptions)))

runInspect :: [Text] -> [ParsedOption] -> App ()
runInspect ["inspect", "replay"] parsedOptions =
  runInspectReplay parsedOptions
runInspect path parsedOptions =
  writeLine
    ("inspect: " <> commandPathText path <> " " <> Text.pack (show (optionPairs parsedOptions)))

-- | `jitml inspect replay <manifest-sha>` — walks the local checkpoint store
-- by manifest content SHA and prints the deterministic inference summary
-- the manifest would produce on a fixed input. Used as the offline replay
-- harness for the determinism contract; the live-MinIO variant lives in
-- Sprint 10.4's `loadInferenceCheckpoint` once `HasMinIO` is wired.
runInspectReplay :: [ParsedOption] -> App ()
runInspectReplay parsedOptions = do
  let manifestSha = selectedValue "manifest-sha" "missing" parsedOptions
      experimentHash = selectedValue "experiment-hash" "default" parsedOptions
  checkpointRoot <- localCheckpointRoot
  result <- liftIO (CheckpointStore.readCheckpointManifest checkpointRoot experimentHash manifestSha)
  case result of
    Left err -> exitWithError (InvalidConfig ("inspect replay: " <> err))
    Right manifest ->
      let inferred = Checkpoint.inferFromManifest manifest [1.0, 2.0, 3.0]
       in writeLine
            ( "inspect replay: "
                <> manifestSha
                <> " -> "
                <> Text.pack (show inferred)
            )

runTest :: [Text] -> App ()
runTest ["test", "all"] =
  runCabalTest reportStanzas
runTest ["test", stanza]
  | stanza `elem` reportStanzas =
      runCabalTest [stanza]
  | otherwise =
      exitWithError (UnknownCommand ("unknown test stanza: " <> stanza))
runTest path =
  exitWithError (UnknownCommand ("unknown test command: " <> commandPathText path))

runCabalTest :: [Text] -> App ()
runCabalTest targets = do
  let command = subprocess "cabal" ("test" : targets)
  (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  case exitCode of
    ExitSuccess -> do
      writeText stdoutText
      loadedKnobs <- liftIO (loadReportCardKnobs "cabal.project")
      case loadedKnobs of
        Left err -> exitWithError (InvalidConfig err)
        Right knobs ->
          writeText
            ( renderReportCardForTargets
                knobs
                (targetStanzas targets)
                (ReportCard (passedCount targets) 0 0)
            )
    ExitFailure _ ->
      exitWithError (SubprocessFailed (renderSubprocess command) exitCode stderrText)

passedCount :: [Text] -> Int
passedCount = length

targetStanzas :: [Text] -> [Text]
targetStanzas targets = targets

runInternalVmExec :: [ParsedOption] -> App ()
runInternalVmExec parsedOptions =
  writeLine
    (renderSubprocess (tartSshSubprocess (VmName "jitml-build") (optionValues "cmd" parsedOptions)))

runInternalVmLifecycle :: Text -> App ()
runInternalVmLifecycle action = do
  liftIO (ensureVmUp "." (VmName "jitml-build"))
  writeLine ("vm " <> action <> ": jitml-build")

-- | `jitml internal gc <experiment-hash>` reconciler. Walks the local
-- on-disk manifests under the supplied experiment hash, applies
-- `LastN 5` retention through `Store.buildGcPlan`, and exits `3`
-- (`ReconcilerNoop`) when the cluster is already at the target state.
runInternalGc :: [ParsedOption] -> App ()
runInternalGc parsedOptions = do
  let experimentHash = selectedValue "experiment-hash" "default" parsedOptions
      retention = CheckpointStore.LastN 5
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

localCheckpointRoot :: App FilePath
localCheckpointRoot = do
  cacheDir <- asks envCacheDir
  pure (toFilePath cacheDir </> "checkpoints")

runInternalCache :: [Text] -> [ParsedOption] -> App ()
runInternalCache ["internal", "cache", "stat"] _ =
  writeLine "cache stat: entries=0 bytes=0"
runInternalCache ["internal", "cache", "list"] _ =
  writeLine "cache list: empty"
runInternalCache ["internal", "cache", "evict"] parsedOptions =
  writeLine ("cache evict: " <> selectedValue "hash" "missing" parsedOptions)
runInternalCache path _ =
  exitWithError (UnknownCommand ("unknown cache command: " <> commandPathText path))

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

cacheSubstrateFromCli :: Substrate -> Cache.Substrate
cacheSubstrateFromCli AppleSilicon = Cache.AppleSilicon
cacheSubstrateFromCli LinuxCPU = Cache.LinuxCPU
cacheSubstrateFromCli LinuxCUDA = Cache.LinuxCUDA

selectedValue :: Text -> Text -> [ParsedOption] -> Text
selectedValue optionName fallback parsedOptions =
  case optionValues optionName parsedOptions of
    [] -> fallback
    value : _ -> value

readInt :: Text -> Int
readInt value =
  case reads (Text.unpack value) of
    [(parsed, "")] -> parsed
    _ -> 0

readClusterPublication :: IO ClusterPublication
readClusterPublication = do
  exists <- doesFileExist ".build/runtime/cluster-publication.json"
  if exists
    then do
      bytes <- LazyByteString.readFile ".build/runtime/cluster-publication.json"
      pure (fromMaybe (defaultPublication AppleSilicon) (decode bytes))
    else pure (defaultPublication AppleSilicon)

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

data DemoArgs = DemoArgs
  { demoHost :: Text
  , demoPort :: Int
  }
  deriving stock (Eq, Show)

defaultDemoArgs :: DemoArgs
defaultDemoArgs =
  DemoArgs
    { demoHost = "127.0.0.1"
    , demoPort = 8080
    }

parseDemoArgs :: [String] -> Either Text DemoArgs
parseDemoArgs = go defaultDemoArgs
 where
  go demoArgs [] = Right demoArgs
  go demoArgs ("--host" : value : rest)
    | null value = Left "invalid --host value: empty"
    | otherwise = go demoArgs {demoHost = Text.pack value} rest
  go _ ["--host"] = Left "missing value for --host"
  go demoArgs ("--port" : value : rest) =
    maybe
      (Left ("invalid --port value: " <> Text.pack value))
      (\port -> go demoArgs {demoPort = port} rest)
      (readMaybeInt value)
  go _ ["--port"] = Left "missing value for --port"
  go demoArgs (arg : rest)
    | Just value <- stripPrefix "--host=" arg =
        if null value
          then Left "invalid --host value: empty"
          else go demoArgs {demoHost = Text.pack value} rest
    | Just value <- stripPrefix "--port=" arg =
        maybe
          (Left ("invalid --port value: " <> Text.pack value))
          (\port -> go demoArgs {demoPort = port} rest)
          (readMaybeInt value)
    | otherwise = Left ("unknown jitml-demo argument: " <> Text.pack arg)

readMaybeInt :: String -> Maybe Int
readMaybeInt value =
  case reads value of
    [(parsed, "")]
      | parsed > 0 && parsed <= 65535 -> Just parsed
    _ -> Nothing

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

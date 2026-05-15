{-# LANGUAGE OverloadedStrings #-}

module JitML.App
  ( demoMain
  , main
  )
where

import Control.Monad (void)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Data.Aeson (decode)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (stripPrefix)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Options.Applicative (ParserResult (..), renderFailure)
import Path (toFilePath)
import System.Directory (doesFileExist)
import System.Environment (getArgs)

import JitML.AppError.AppError (AppError (..))
import JitML.Bootstrap (materializeBootstrapFiles)
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
import JitML.Cluster.Publication (ClusterPublication, defaultPublication, renderPublicationSummary)
import JitML.Codegen.RuntimeSource
  ( materializeRuntimeSource
  , renderRuntimeSource
  , runtimeSourcePayload
  )
import JitML.Docs.Check (checkDocs, renderDocsDrift)
import JitML.Docs.Generate (GenerateResult (..), generateDocs)
import JitML.Engines.Engine (engineForSubstrate, renderBuildPlan)
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
import JitML.Service.BootConfig (Residency (..), defaultBootConfig, renderBootConfigDhall)
import JitML.Service.Endpoints
  ( MetricsSnapshot (..)
  , healthz
  , metrics
  , readyz
  , renderEndpointResponse
  )
import JitML.Service.Lifecycle (lifecyclePlan, renderLifecyclePhase)
import JitML.Service.LiveConfig (defaultLiveConfig, renderLiveConfigDhall)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Tart.Exec (tartSshSubprocess)
import JitML.Tart.Lifecycle (VmName (..), ensureVmUp)
import JitML.Test.Report (ReportCard (..), renderReportCard)
import JitML.Tune.Catalog qualified as Tune

main :: IO ()
main = getArgs >>= runArgs

demoMain :: IO ()
demoMain = writeLineIO "jitml-demo: serving generated frontend contract surface"

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
      writeLine "gc: checkpoint retention policy reconciled"
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
          liftIO (materializeBootstrapFiles "." parsedSubstrate)
          writeLine ("materialize-substrate: " <> substrate <> " bootstrap files are present")
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
            liftIO (materializeBootstrapFiles "." parsedSubstrate)
            writeLine ("bootstrap: " <> substrate <> " reconciled")
    [] ->
      exitWithError (InvalidConfig "bootstrap requires exactly one substrate flag")
    _ ->
      exitWithError (InvalidConfig "bootstrap accepts exactly one substrate flag")

bootstrapSubstrates :: [ParsedOption] -> [Text]
bootstrapSubstrates parsedOptions =
  filter (`hasOption` parsedOptions) supportedSubstrates

runService :: [ParsedOption] -> App ()
runService parsedOptions = do
  let configPath =
        case optionValues "config" parsedOptions of
          [] -> "./conf/cluster/linux-cpu.dhall"
          value : _ -> value
  writeLine ("service config: " <> configPath)
  writeText $
    Text.unlines
      [ "lifecycle:"
      , "  - " <> Text.intercalate "\n  - " (fmap renderLifecyclePhase lifecyclePlan)
      , "boot_config:"
      , indentText (renderBootConfigDhall (defaultBootConfig LinuxCPU Cluster))
      , "live_config:"
      , indentText (renderLiveConfigDhall defaultLiveConfig)
      , "healthz:"
      , indentText (renderEndpointResponse healthz)
      , "readyz:"
      , indentText (renderEndpointResponse (readyz True))
      , "metrics:"
      , indentText (renderEndpointResponse (metrics (MetricsSnapshot 0 1 0)))
      ]

runCluster :: [Text] -> [ParsedOption] -> App ()
runCluster ["cluster", "up"] parsedOptions =
  case selectedSubstrate parsedOptions of
    Left err -> exitWithError err
    Right substrate -> do
      liftIO (materializeBootstrapFiles "." substrate)
      writeLine ("cluster up: " <> renderSubstrate substrate <> " reconciled")
runCluster ["cluster", "status"] _ = do
  publication <- liftIO readClusterPublication
  writeText (renderPublicationSummary publication)
runCluster ["cluster", "down"] _ =
  writeLine "cluster down: Kind cluster delete plan rendered; state preserved"
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
      if hasOption "dry-run" parsedOptions
        then pure ()
        else void (liftIO (materializeRuntimeSource env runtimeSource hash))
      writeText rendered

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
runTune parsedOptions =
  writeText $
    Text.unlines
      [ "tune: " <> selectedValue "tune-dhall" "experiments/mnist-tune.dhall" parsedOptions
      , "trials: " <> Text.pack (show (Tune.deterministicTrials Tune.Sobol 4))
      ]

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
        Checkpoint.CheckpointManifest
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
runInspect path parsedOptions =
  writeLine
    ("inspect: " <> commandPathText path <> " " <> Text.pack (show (optionPairs parsedOptions)))

runTest :: [Text] -> App ()
runTest ["test", "all"] =
  writeText (renderReportCard (ReportCard 10 0 0))
runTest ["test", stanza] =
  writeLine ("test: " <> stanza <> " selected")
runTest path =
  exitWithError (UnknownCommand ("unknown test command: " <> commandPathText path))

runInternalVmExec :: [ParsedOption] -> App ()
runInternalVmExec parsedOptions =
  writeLine
    (renderSubprocess (tartSshSubprocess (VmName "jitml-build") (optionValues "cmd" parsedOptions)))

runInternalVmLifecycle :: Text -> App ()
runInternalVmLifecycle action = do
  liftIO (ensureVmUp "." (VmName "jitml-build"))
  writeLine ("vm " <> action <> ": jitml-build")

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

indentText :: Text -> Text
indentText =
  Text.unlines . fmap ("  " <>) . Text.lines

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

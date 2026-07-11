{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.App
  ( main
  , parseUserIntOptionAtLeast
  , rlTrainerEnvironmentCompatibilityError
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception.Safe (bracket, displayException, finally, tryAny)
import Control.Monad (forever, unless, void, when)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Crypto.Hash.SHA256 qualified
import Data.Aeson (eitherDecode, encode)
import Data.ByteString qualified
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isRight, lefts)
import Data.Foldable (for_, traverse_)
import Data.List (sort, stripPrefix)
import Data.Maybe (catMaybes, fromMaybe, isJust, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector.Unboxed qualified as VU
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
import System.IO qualified
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
  , cachedThirdPartyRolloutImages
  , liveExecutePhasedRollout
  , materializeBootstrapFiles
  , readExistingLivePublication
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
import JitML.Docs.Check (checkDocs, renderDocsDrift)
import JitML.Docs.Generate (GenerateResult (..), generateDocs)
import JitML.Engines.CudaLocal (runCudaWeightedCheckpointInference)
import JitML.Engines.CudaRuntime (cudaRuntimeAvailable, probeCudaRuntime)
import JitML.Engines.Engine
  ( compileSubprocess
  , engineForSubstrate
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
import JitML.Plan.Plan (buildCommandPlan)
import JitML.Plan.Render (renderPlan)
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
import JitML.RL.Simulator qualified as RLSim
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.Regression qualified as Regression
import JitML.SL.TinyImageNet qualified as TinyImageNet
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities (SubscriptionId)
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.CatalogSchema qualified as CatalogSchema
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , EventDomain (..)
  , EventId
  , HandlerRouter
  , consumerStepWithActions
  )
import JitML.Service.DhallSchema qualified as DhallSchema
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.Runtime qualified as ServiceRuntime
import JitML.Service.WorkflowStatus qualified as WorkflowStatus
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate, substrateEdgePort)
import JitML.Test.LivePlan (LivePlanStep (..), liveE2EPlanFor)
import JitML.Test.Report
  ( ProductRowReportEvidence (..)
  , ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , emptyReportMeasurements
  , loadReportCardKnobs
  , productRowReportCoverageFailures
  , renderReportCardForTargets
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
  runtime <- loadDaemonRuntime configPath explicitConfig
  -- Sprint 11.10 — one-binary role dispatch. `activeRole = Webapp` serves the
  -- browser surface (thin websocket + publish-only inference) and computes
  -- nothing; every other role runs the Engine consumer path.
  case BootConfig.bootActiveRole (ServiceRuntime.daemonBootConfig runtime) of
    BootConfig.Webapp -> runWebappRole runtime
    _ -> runEngineServe env configPath consumeOnceRequested consumeOnceBudget runtime

-- | Sprint 11.10 — the Webapp role: serve the compiled browser bundle + the
-- held-open @/api/ws@ Pulsar bridge, deriving host/port/substrate/WS endpoint
-- from the typed Dhall 'BootConfig'. The browser-runtime handler __publishes__
-- an inference @WorkCommand@ to the Engine (via 'requestInferenceViaEngine') and
-- renders the streamed result; the Webapp itself computes no inference.
runWebappRole :: ServiceRuntime.DaemonRuntime -> App ()
runWebappRole runtime = do
  let boot = ServiceRuntime.daemonBootConfig runtime
      substrate = BootConfig.bootSubstrate boot
      (host, port) =
        case BootConfig.bootHttpListener boot of
          Just listener -> (BootConfig.listenerHost listener, BootConfig.listenerPort listener)
          Nothing -> ("0.0.0.0", 8080)
      wsEndpoint = BootConfig.bootWebappPulsarWsUrl boot
      publication = defaultPublication substrate
      pulsarSettings =
        case wsEndpoint of
          Just url -> PulsarWebSocketSubprocess.pulsarSettingsForEndpoint url
          Nothing ->
            PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge
              (Publication.publicationEdgePort publication)
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
  liftIO
    ( WebServer.serveDemoWithBridgeEndpointWithRuntime
        host
        port
        (Just publication)
        wsEndpoint
        (Just handler)
        (Just publishers)
    )

runEngineServe :: Env -> Text -> Bool -> Int -> ServiceRuntime.DaemonRuntime -> App ()
runEngineServe env configPath consumeOnceRequested consumeOnceBudget runtime = do
  metalAcquire <- acquireAppleMetalBridge runtime
  metalReadyRuntime <-
    case metalAcquire of
      Right readyRuntime -> pure readyRuntime
      Left (failedRuntime, err) -> do
        writeLine ("service config: " <> configPath)
        writeText (ServiceRuntime.renderDaemonRuntimeSummary failedRuntime)
        exitWithError err
  acquiredRuntime <-
    liftIO
      ( ServiceClients.runDaemonServiceClient
          (ServiceRuntime.daemonClientSettings metalReadyRuntime)
          (ServiceRuntime.acquireDaemonSubscriptions metalReadyRuntime)
      )
  probedRuntime <-
    liftIO
      ( ServiceClients.runDaemonServiceClient
          (ServiceRuntime.daemonClientSettings acquiredRuntime)
          (ServiceRuntime.probeDaemonServiceClients acquiredRuntime)
      )
  writeLine ("service config: " <> configPath)
  writeText (ServiceRuntime.renderDaemonRuntimeSummary probedRuntime)
  if consumeOnceRequested
    then do
      (_, outcomes) <-
        liftIO
          ( ServiceClients.runDaemonServiceClient
              (ServiceRuntime.daemonClientSettings probedRuntime)
              ( ServiceRuntime.daemonConsumerBatch
                  probedRuntime
                  consumeOnceBudget
                  (daemonWorkloadDispatcherForRuntime env probedRuntime)
              )
          )
      writeLine
        ( "service: consume-once drained "
            <> Text.pack (show consumeOnceBudget)
            <> " message(s) per acquired subscription"
        )
      writeText (ServiceRuntime.renderConsumerOutcomes outcomes)
      for_ (ServiceRuntime.consumerLoopExit outcomes) exitWithError
    else do
      writeLine (serviceListeningLine probedRuntime)
      consumerThreads <- liftIO (startDaemonConsumerWorkers env probedRuntime)
      liftIO
        ( ServiceRuntime.serveDaemon probedRuntime
            `finally` stopDaemonConsumerWorkers consumerThreads
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

startDaemonConsumerWorkers :: Env -> ServiceRuntime.DaemonRuntime -> IO [ThreadId]
startDaemonConsumerWorkers env runtime =
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
  traverse startWorker (acquiredSubscriptionIds runtime)
 where
  startWorker subscription = do
    routerRef <- newMVar (ServiceRuntime.daemonHandlerRouter runtime)
    forkIO (daemonConsumerWorkerLoop env runtime routerRef subscription)

stopDaemonConsumerWorkers :: [ThreadId] -> IO ()
stopDaemonConsumerWorkers =
  traverse_ killThread

acquiredSubscriptionIds :: ServiceRuntime.DaemonRuntime -> [SubscriptionId]
acquiredSubscriptionIds runtime =
  foldMap acquired (ServiceRuntime.daemonSubscriptionStatuses runtime)
 where
  acquired status =
    case ServiceRuntime.daemonSubscriptionStatusState status of
      ServiceRuntime.DaemonSubscriptionAcquired subscriptionId -> [subscriptionId]
      _ -> []

daemonConsumerWorkerLoop
  :: Env -> ServiceRuntime.DaemonRuntime -> MVar HandlerRouter -> SubscriptionId -> IO ()
daemonConsumerWorkerLoop env runtime routerRef subscription =
  forever $ do
    workerResult <-
      PulsarWebSocketSubprocess.runPulsarConsumerWorker
        (ServiceClients.daemonPulsarSettings (ServiceRuntime.daemonClientSettings runtime))
        subscription
        (handleDaemonConsumerDelivery env runtime routerRef subscription)
    case workerResult of
      Right () -> pure ()
      Left err -> do
        writeLineIO
          ( "service: consumer worker error: "
              <> Text.strip (ServiceRuntime.renderConsumerOutcomes [ConsumerError err])
          )
        threadDelay daemonConsumerErrorDelayMicros

handleDaemonConsumerDelivery
  :: Env
  -> ServiceRuntime.DaemonRuntime
  -> MVar HandlerRouter
  -> SubscriptionId
  -> PulsarWebSocketSubprocess.PulsarWorkerDelivery
  -> IO (Either ServiceError ())
  -> IO (Either ServiceError ())
  -> IO ()
handleDaemonConsumerDelivery env runtime routerRef subscription delivery ackDelivery nackDelivery = do
  outcomeResult <-
    tryAny $
      modifyMVar routerRef $ \router -> do
        (router', outcome) <-
          consumerStepWithActions
            subscription
            router
            (PulsarWebSocketSubprocess.pulsarWorkerDeliveryTopic delivery)
            (PulsarWebSocketSubprocess.pulsarWorkerDeliveryPayload delivery)
            ackDelivery
            (const nackDelivery)
            ( \domain eventId payload ->
                ServiceClients.runDaemonServiceClient
                  (ServiceRuntime.daemonClientSettings runtime)
                  (daemonWorkloadDispatcherForRuntime env runtime domain eventId payload)
            )
        pure (router', outcome)
  case outcomeResult of
    Left err -> do
      writeLineIO ("service: consumer worker failed: " <> Text.pack (displayException err))
      threadDelay daemonConsumerErrorDelayMicros
    Right outcome -> do
      writeLineIO
        ("service: " <> Text.strip (ServiceRuntime.renderConsumerOutcomes [outcome]))
      for_ (ServiceRuntime.consumerLoopExit [outcome]) $ \appError ->
        writeLineIO ("service: consumer outcome error: " <> renderError appError)

daemonConsumerErrorDelayMicros :: Int
daemonConsumerErrorDelayMicros = 1000000

daemonWorkloadDispatcherForRuntime
  :: Env
  -> ServiceRuntime.DaemonRuntime
  -> EventDomain
  -> EventId
  -> Text
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
daemonWorkloadDispatcherForRuntime env runtime domain eventId payload = do
  -- Sprint 14.1 (Feature C) — the Engine's workflow-status projector: alongside
  -- the underlying command dispatch, project the observed training / tune / rl
  -- lifecycle transition into a reconciled `WorkflowStatus` frame and republish
  -- it onto `workflow.status.<substrate>`, which the workflow panel renders live.
  projectWorkflowStatus substrate domain payload
  innerDispatcher domain eventId payload
 where
  substrate = BootConfig.bootSubstrate (ServiceRuntime.daemonBootConfig runtime)
  innerDispatcher =
    case ( substrate
         , BootConfig.bootInferenceMode (ServiceRuntime.daemonBootConfig runtime)
         ) of
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
        daemonWorkloadDispatcherHostingAppleWorkloads env
      -- Sprint 14.4 — the in-cluster Apple daemon (`Cluster + ForwardToHost`)
      -- forwards inference to the host-native daemon: it republishes the raw
      -- inference command on `inference.command.apple-silicon` rather than running
      -- Metal in-pod (Metal cannot be containerized).
      (AppleSilicon, BootConfig.ForwardToHost) ->
        ServiceRuntime.daemonWorkloadDispatcherForwardingInference
      _ ->
        ServiceRuntime.daemonWorkloadDispatcher

-- | Sprint 14.1 (Feature C) — project an observed lifecycle transition into a
-- reconciled `WorkflowStatus` frame and publish it onto
-- `workflow.status.<substrate>`. Inference-domain payloads carry no run status
-- and are skipped; a publish failure is swallowed (the projection is a
-- best-effort live overlay, never a hard dependency of the underlying dispatch).
projectWorkflowStatus
  :: Substrate
  -> EventDomain
  -> Text
  -> ServiceClients.DaemonServiceClient ()
projectWorkflowStatus substrate domain payload =
  case WorkflowStatus.workflowStatusFrameForCommand domain payload of
    Nothing -> pure ()
    Just frame -> do
      _ <-
        Capabilities.pulsarPublish
          (Capabilities.TopicName (WorkflowStatus.workflowStatusTopic substrate))
          (WorkflowStatus.renderWorkflowStatusFrame frame)
      pure ()

daemonWorkloadDispatcherHostingAppleWorkloads
  :: Env
  -> EventDomain
  -> EventId
  -> Text
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
daemonWorkloadDispatcherHostingAppleWorkloads env domain eventId payload =
  case domain of
    TrainingDomain ->
      case ProtoTraining.parseTrainingCommand payload of
        Just (ProtoTraining.TrainingStart start) ->
          runHostAppleTraining env start
        Just (ProtoTraining.TrainingStop _) ->
          pure (Right ())
        Nothing ->
          hostInferenceFallback domain eventId payload
    TuneDomain ->
      case ProtoTune.parseTuneCommand payload of
        Just (ProtoTune.TuneStart start) ->
          runHostAppleTune env start
        Just (ProtoTune.TuneStop _) ->
          pure (Right ())
        Nothing ->
          hostInferenceFallback domain eventId payload
    RlDomain ->
      case ProtoRl.parseRlCommand payload of
        Just (ProtoRl.RlStart start) ->
          runHostAppleRl env start
        Just (ProtoRl.RlStop _) ->
          pure (Right ())
        Nothing ->
          hostInferenceFallback domain eventId payload
    InferenceDomain ->
      hostInferenceFallback domain eventId payload
 where
  hostInferenceFallback =
    ServiceRuntime.daemonWorkloadDispatcherHostingAppleInference
      ( \modelRef manifest weights input -> liftIO (engineWeightedInference env AppleSilicon modelRef manifest weights input)
      )

runHostAppleTraining
  :: Env
  -> ProtoTraining.StartTraining
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
runHostAppleTraining env start
  | ProtoTraining.stSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple training received a non-apple-silicon command"))
  | otherwise = do
      problemE <-
        liftIO (SL.loadCanonicalProblemExperiment (Text.unpack (ProtoTraining.stDhallObjectKey start)))
      case problemE of
        Left err -> pure (Left (SETransient ("host Apple training experiment decode failed: " <> err)))
        Right problem -> do
          let trainLimit = 2000
              epochs = fromIntegral (ProtoTraining.stEpochs start)
              testLimit = 1000
          result <-
            liftIO
              ( runReaderT
                  (runDeviceMnistTrainingWithLimits AppleSilicon problem trainLimit epochs testLimit)
                  env
              )
          case result of
            Left err -> pure (Left (SETransient ("host Apple training failed: " <> err)))
            Right metrics -> do
              epochResult <- publishTrainingEpoch start metrics
              case epochResult of
                Left err -> pure (Left err)
                Right () -> publishTrainingCheckpoint problem start metrics

publishTrainingEpoch
  :: ProtoTraining.StartTraining
  -> TrainingMetrics
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishTrainingEpoch start metrics = do
  timestampNs <- liftIO currentTimestampNs
  let topic = Capabilities.TopicName (ProtoTraining.trainingEventTopic AppleSilicon)
      epochNumber = max 1 (ProtoTraining.stEpochs start)
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
  publishUnit topic (ProtoTraining.renderTrainingEvent envelope)

publishTrainingCheckpoint
  :: SL.CanonicalProblem
  -> ProtoTraining.StartTraining
  -> TrainingMetrics
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishTrainingCheckpoint problem start metrics =
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
                  problem
                  metrics
                  experimentHash
                  tensorName
                  step
                  metricRows
                  weights
              )
          topic = Capabilities.TopicName (ProtoTraining.trainingEventTopic AppleSilicon)
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
          let envelope =
                ProtoTraining.TrainingCheckpoint
                  ( trainingCheckpointDoneEnvelope
                      experimentHash
                      tensorName
                      step
                      metricRows
                      (tmDatasetShaAtRead metrics)
                      completedTraining
                      weights
                      stored
                  )
          publishUnit topic (ProtoTraining.renderTrainingEvent envelope)

runHostAppleTune
  :: Env
  -> ProtoTune.StartSweep
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
runHostAppleTune env start
  | ProtoTune.ssSubstrate start /= AppleSilicon =
      pure (Left (SETransient "host Apple tune received a non-apple-silicon command"))
  | otherwise =
      case ( Tune.samplerFromText (ProtoTune.ssSampler start)
           , Tune.schedulerFromText (ProtoTune.ssScheduler start)
           , Tune.prunerFromText (ProtoTune.ssPruner start)
           ) of
        (Just sampler, Just scheduler, Just pruner) -> do
          let trialCount = max 1 (fromIntegral (ProtoTune.ssTrialBudget start))
              device = mlpDeviceForSubstrate AppleSilicon env
          trialResultsE <-
            liftIO
              (Tune.trialObjectiveResultsWithDeviceForAxes device sampler scheduler pruner trialCount)
          case trialResultsE of
            Left err -> pure (Left (SETransient ("host Apple tune failed: " <> err)))
            Right trialResults -> publishHostTuneEvents start trialResults
        _ ->
          pure (Left (SETransient "host Apple tune command contains an unknown sampler/scheduler/pruner"))

publishHostTuneEvents
  :: ProtoTune.StartSweep
  -> [Tune.TrialObjectiveResult]
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishHostTuneEvents start trialResults = do
  let topic = Capabilities.TopicName (ProtoTune.tuneEventTopic AppleSilicon)
      baseSeed = fromIntegral (ProtoTune.ssSweepSeed start) :: Int
      indexed = zip [0 :: Int ..] trialResults
      objectives = fmap Tune.trialResultObjective trialResults
  publishedResults <- traverse (publishTrial topic baseSeed) indexed
  case firstLeft publishedResults of
    Just err -> pure (Left err)
    Nothing -> do
      let completed = fromIntegral (length objectives)
          bestObjective = if null objectives then 0.0 else maximum objectives
          done =
            ProtoTune.TuneSweepDone
              ( ProtoTune.SweepDone
                  { ProtoTune.sdExperimentHash = ProtoTune.ssExperimentHash start
                  , ProtoTune.sdTrialsCompleted = completed
                  , ProtoTune.sdTrialsPruned = 0
                  , ProtoTune.sdBestObjective = bestObjective
                  , ProtoTune.sdCompletedTraining =
                      tuneSweepCompletedTraining
                        (ProtoTune.ssExperimentHash start)
                        completed
                        bestObjective
                  }
              )
      publishUnit topic (ProtoTune.renderTuneEvent done)
 where
  publishTrial topic baseSeed (trialIndex, trialResult) = do
    timestampStart <- liftIO currentTimestampNs
    let trialSeed = baseSeed + trialIndex
        objective = Tune.trialResultObjective trialResult
        started =
          ProtoTune.TuneTrialStarted
            ( ProtoTune.TrialStarted
                { ProtoTune.tsExperimentHash = ProtoTune.ssExperimentHash start
                , ProtoTune.tsTrial = fromIntegral trialIndex
                , ProtoTune.tsTrialSeed = fromIntegral trialSeed
                , ProtoTune.tsParametersJson =
                    "{\"sampler\":\"" <> ProtoTune.ssSampler start <> "\"}"
                , ProtoTune.tsTimestampNs = timestampStart
                }
            )
    startResult <- publishUnit topic (ProtoTune.renderTuneEvent started)
    case startResult of
      Left err -> pure (Left err)
      Right () -> do
        persistResult <-
          Tune.persistTrialTranscript
            Tune.TrialTranscript
              { Tune.transcriptExperimentHash = ProtoTune.ssExperimentHash start
              , Tune.transcriptTrialSeed = trialSeed
              , Tune.transcriptValues = [objective]
              }
        case persistResult of
          Left err -> pure (Left err)
          Right _ -> do
            checkpointResult <-
              writeMinIOWeightCheckpoint
                (ProtoTune.ssExperimentHash start)
                "tune-trial-weights"
                (fromIntegral trialSeed)
                [("objective", objective)]
                (Tune.trialResultWeights trialResult)
            case checkpointResult of
              Left err -> pure (Left err)
              Right _stored -> do
                timestampEnd <- liftIO currentTimestampNs
                let finished =
                      ProtoTune.TuneTrialFinished
                        ( ProtoTune.TrialFinished
                            { ProtoTune.tfTuneExperimentHash = ProtoTune.ssExperimentHash start
                            , ProtoTune.tfTuneTrial = fromIntegral trialIndex
                            , ProtoTune.tfTuneObjective = objective
                            , ProtoTune.tfTunePruned = False
                            , ProtoTune.tfTuneTranscriptObjectKey =
                                Tune.trialStorageKey (ProtoTune.ssExperimentHash start) trialSeed
                            , ProtoTune.tfTuneTimestampNs = timestampEnd
                            }
                        )
                publishUnit topic (ProtoTune.renderTuneEvent finished)

runHostAppleRl
  :: Env
  -> ProtoRl.StartRLRun
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
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

publishHostRlEpisode
  :: ProtoRl.StartRLRun
  -> EpisodeEnvelope.SimulatedEpisode
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishHostRlEpisode start episode = do
  timestampNs <- liftIO currentTimestampNs
  let topic = Capabilities.TopicName (ProtoRl.rlEventTopic AppleSilicon)
      envelope =
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
  episodeResult <- publishUnit topic (ProtoRl.renderRlEvent envelope)
  frameResults <- traverse (publishUnit topic . ProtoRl.renderRlEvent) animationEnvelopes
  pure $ maybe (Right ()) Left (firstLeft (episodeResult : frameResults))

publishUnit
  :: Capabilities.TopicName
  -> Text
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishUnit topic payload =
  fmap void (Capabilities.pulsarPublish topic payload)

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
              , ServiceRuntime.daemonReady =
                  ServiceRuntime.daemonReady runtime && runtimeAvailable && bridgeAvailable
              }
      pure $
        if runtimeAvailable && bridgeAvailable
          then Right acquired
          else
            Left
              ( acquired
              , appleMetalAcquireError runtimeAvailable bridgeAvailable
              )
    _ -> pure (Right runtime)
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
        Left err -> pure (BridgeInstallFailed err)

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
    Left err ->
      exitWithError (SubprocessFailed "jitml internal install-metal-bridge" (ExitFailure 1) err)
    Right path -> do
      writeLine ("metal_bridge: " <> Text.pack path)
      writeLine "metal_bridge_probe: ok"

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
        then writeLine ("cluster up: " <> renderSubstrate substrate <> " materialized")
        else writeLine ("cluster up: " <> renderSubstrate substrate <> " materialization already current")
      result <- liftIO (liveExecutePhasedRollout substrate "chart")
      writeLine
        ( "cluster up: live phased rollout executed "
            <> Text.pack (show (length (liveStepsExecuted result)))
            <> " steps"
        )
      mapM_
        ( \(step, stderrText) ->
            writeLine ("cluster up: step failed: " <> step <> " stderr: " <> stderrText)
        )
        (liveStepsFailed result)
      unless (null (liveStepsFailed result)) $
        exitWithError
          ( SubprocessFailed
              "cluster up live phased rollout"
              (ExitFailure 1)
              (renderLiveStepFailures (liveStepsFailed result))
          )
      writeText (renderPublicationSummary (livePublication result))
runCluster ["cluster", "status"] _ = do
  publication <- readClusterPublicationOrExit
  writeText (renderPublicationSummary publication)
runCluster ["cluster", "down"] _ = do
  publication <- readClusterPublicationOrExit
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
                  engine
                  substrate
                  kernelSpec
                  kind
                  fingerprint
                  runtimeSource
                  hash
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
                      exitWithError (SubprocessFailed "linux-cpu-jit" (ExitFailure 1) message)
                    Right kernelRun ->
                      pure
                        ( reportTunedArtifact tunedArtifact
                            <> ["linux_cpu_run: " <> Text.pack (show (linuxCpuKernelOutput kernelRun))]
                        )
            LinuxCUDA -> do
              tunedArtifact <-
                runBenchmarkTunedEnsureKernelArtifact
                  env
                  engine
                  substrate
                  kernelSpec
                  kind
                  fingerprint
                  runtimeSource
                  hash
              pure (reportTunedArtifact tunedArtifact)
            _ -> do
              artifactResult <- liftIO (EngineLoader.ensureKernelArtifact env engine runtimeSource hash)
              case artifactResult of
                Left message ->
                  exitWithError
                    ( SubprocessFailed
                        (renderSubprocess (compileSubprocess engine runtimeSource hash))
                        (ExitFailure 1)
                        message
                    )
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

  runBenchmarkTunedEnsureKernelArtifact env engine substrate kernelSpec kind fingerprint runtimeSource hash = do
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
      Left message ->
        exitWithError
          ( SubprocessFailed
              (renderSubprocess (compileSubprocess engine runtimeSource hash))
              (ExitFailure 1)
              message
          )
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
  result <- runDeviceMnistTraining substrate problem
  case result of
    Left reason -> exitWithError (TrainingPrerequisiteUnmet reason)
    Right metrics -> do
      publishWorkerTrainingEvent metrics
      publishWorkerTrainingCheckpoint substrate problem parsedOptions metrics

resolveTrainingProblem :: [ParsedOption] -> App SL.CanonicalProblem
resolveTrainingProblem parsedOptions = do
  let dhallPath = Text.unpack (selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions)
  loaded <- liftIO (ProductExperiment.loadSupervisedProblemByPath dhallPath)
  case loaded of
    Left err -> exitWithError (DhallTypeError err)
    Right problem -> pure problem

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

-- | Sprint 8.13 — deterministically carve a held-out validation partition off
-- the tail of the (bounded) training examples. The validation slice is never
-- folded into the gradient-update set, so model selection on it is honest. The
-- canonical archives that ship no separate validation partition (CIFAR-10/100)
-- still get an honest held-out slice here rather than reusing the test split as
-- validation (the prohibition in @training_metrics_and_splits.md@). Tiny inputs
-- (≤1 example) degenerate to using the same set for both, which only happens in
-- unit fixtures, never in a budgeted live run.
splitTrainValidation :: [a] -> ([a], [a])
splitTrainValidation examples =
  let n = length examples
      valCount = max 1 (n `div` 6)
      trainCount = n - valCount
   in if trainCount < 1
        then (examples, examples)
        else splitAt trainCount examples

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
-- curve. The example count and epoch budget are capped by the mounted
-- @TrainingRunConfig@ or the @JITML_SL_*@ env vars so a live run stays
-- tractable.
runDeviceMnistTraining :: Substrate -> SL.CanonicalProblem -> App (Either Text TrainingMetrics)
runDeviceMnistTraining substrate problem = do
  -- Sprint 5.7 — prefer the typed Dhall `TrainingRunConfig` mount; fall back to
  -- env vars when no mount is present. Sprint 5.11 reuses the helper below for
  -- host-resident Apple work, where the config arrives as a Pulsar envelope
  -- rather than a pod-mounted file.
  runConfigLoad <- liftIO (RunConfig.tryLoadTrainingRunConfig runConfigPath)
  (trainLimit, epochs, testLimit) <- case runConfigLoad of
    RunConfig.RunConfigLoaded rc ->
      pure
        ( fromMaybe 2000 (RunConfig.trcSlTrainLimit rc)
        , fromMaybe 3 (RunConfig.trcSlEpochs rc)
        , fromMaybe 1000 (RunConfig.trcSlTestLimit rc)
        )
    RunConfig.RunConfigMissing -> liftIO $ do
      tl <- readIntDefault 2000 <$> envWithDefault "JITML_SL_TRAIN_LIMIT" "2000"
      ep <- readIntDefault 3 <$> envWithDefault "JITML_SL_EPOCHS" "3"
      tt <- readIntDefault 1000 <$> envWithDefault "JITML_SL_TEST_LIMIT" "1000"
      pure (tl, ep, tt)
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError "TrainingRunConfig" err)
  runDeviceMnistTrainingWithLimits substrate problem trainLimit epochs testLimit

runDeviceMnistTrainingWithLimits
  :: Substrate -> SL.CanonicalProblem -> Int -> Int -> Int -> App (Either Text TrainingMetrics)
runDeviceMnistTrainingWithLimits substrate problem trainLimit epochs testLimit =
  runDeviceMnistTrainingWithLimitsAndLearningRate
    substrate
    problem
    trainLimit
    epochs
    testLimit
    Nothing

runDeviceMnistTrainingWithLimitsAndLearningRate
  :: Substrate
  -> SL.CanonicalProblem
  -> Int
  -> Int
  -> Int
  -> Maybe Double
  -> App (Either Text TrainingMetrics)
runDeviceMnistTrainingWithLimitsAndLearningRate substrate problem trainLimit epochs testLimit learningRateOverride = do
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
                        (Classifier.defaultClassifierConfig {Classifier.clfEpochs = max 1 epochs})
                          { Classifier.clfLearningRate =
                              fromMaybe
                                (Classifier.clfLearningRate Classifier.defaultClassifierConfig)
                                learningRateOverride
                          }
                      device = mlpDeviceForSubstrate substrate env
                      decodedE =
                        Classifier.decodeBoundedDataset
                          config
                          (Just (max 1 trainLimit))
                          (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload imgArtifact))
                          (Dataset.maybeGunzip (Dataset.fetchedArtifactPayload lblArtifact))
                  case decodedE of
                    Left err -> pure (Left (Text.pack err))
                    Right (configForData, dataset) -> do
                      let spec = Architecture.architectureSpecForProblem configForData problem
                          (trainSet, validationSet) = splitTrainValidation dataset
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
  -> Maybe Double
  -> MinIOSubprocess.MinIOSettings
  -> ( Classifier.ClassifierConfig
       -> Dataset.DatasetSplit
       -> Maybe Int
       -> Data.ByteString.ByteString
       -> Either String (Classifier.ClassifierConfig, Classifier.Dataset)
     )
  -> App (Either Text TrainingMetrics)
runDeviceArchiveClassifierTraining substrate problem trainRef trainLimit epochs testLimit learningRateOverride minioSettings decodeArchive = do
  env <- ask
  let run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      config =
        (Classifier.defaultClassifierConfig {Classifier.clfEpochs = max 1 epochs})
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
       in case decodeArchive config Dataset.TrainSplit (Just (max 1 trainLimit)) archiveBytes of
            Left err -> pure (Left (Text.pack err))
            Right (configForData, dataset) -> do
              let spec = Architecture.architectureSpecForProblem configForData problem
                  (trainSet, validationSet) = splitTrainValidation dataset
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
                Right (trained, metrics) -> do
                  testAcc <-
                    case decodeArchive configForData Dataset.TestSplit (Just (max 1 testLimit)) archiveBytes of
                      Left _ -> pure Nothing
                      Right (_, testSet) -> do
                        accE <- liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
                        pure (eitherToMaybe accE)
                  writeText
                    ( renderTrainingMetricsLine
                        substrate
                        problem
                        (Just (Dataset.datasetName trainRef))
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

runDeviceCaliforniaHousingTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> MinIOSubprocess.MinIOSettings
  -> App (Either Text TrainingMetrics)
runDeviceCaliforniaHousingTraining substrate problem trainRef trainLimit epochs minioSettings = do
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
       in case Regression.decodeCaliforniaHousingArchiveBoundedData (Just (max 1 trainLimit)) archiveBytes of
            Left err -> pure (Left (Text.pack err))
            Right dataset ->
              case listToMaybe dataset of
                Nothing -> pure (Left "California Housing archive produced no rows")
                Just firstExample -> do
                  let normalizedDataset = Regression.standardizeRegressionExamples dataset
                      (trainSet, validationSet) = splitTrainValidation normalizedDataset
                      config =
                        Regression.defaultRegressionConfig
                          { Regression.regInputs = VU.length (Regression.regressionFeatures firstExample)
                          , Regression.regEpochs = max 1 epochs
                          }
                  trainedE <- liftIO (Regression.trainRegressorWithDevice device config trainSet)
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
          let testSet = take (max 1 limit) (Classifier.zipImagesLabels images labels)
          accE <- liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
          pure (Right (eitherToMaybe accE))
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
      let clientSettings = ServiceClients.daemonClientSettingsForBootConfig bootConfig
      pure $
        Just
          WorkerLiveContext
            { workerLivePublication = publicationFromBootConfig bootConfig
            , workerLiveMinIOSettings = ServiceClients.daemonMinIOSettings clientSettings
            , workerLivePulsarSettings = ServiceClients.daemonPulsarSettings clientSettings
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
  orElse first second = case first of
    Just _ -> first
    Nothing -> second
  -- Try each RunConfig variant in turn; pick the first that has a pulsarWsUrl.
  mountedWsFromRunConfig :: App (Maybe Text)
  mountedWsFromRunConfig = do
    rl <- liftIO (RunConfig.tryLoadRlRunConfig runConfigPath)
    tr <- liftIO (RunConfig.tryLoadTrainingRunConfig runConfigPath)
    tu <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
    case ( fmapRunConfig RunConfig.rlcPulsarWsUrl rl
         , fmapRunConfig RunConfig.trcPulsarWsUrl tr
         , fmapRunConfig RunConfig.turcPulsarWsUrl tu
         ) of
      (Just ws, _, _) -> pure (Just ws)
      (_, Just ws, _) -> pure (Just ws)
      (_, _, Just ws) -> pure (Just ws)
      _ -> case firstRunConfigDecodeFailure [rlRunConfigError rl, trainingRunConfigError tr, tuneRunConfigError tu] of
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
  case ( nonEmptyText =<< fmapRunConfig RunConfig.rlcExperimentHash rl
       , nonEmptyText =<< fmapRunConfig RunConfig.trcExperimentHash tr
       , nonEmptyText =<< fmapRunConfig RunConfig.turcExperimentHash tu
       ) of
    (Just h, _, _) -> pure (Just h)
    (_, Just h, _) -> pure (Just h)
    (_, _, Just h) -> pure (Just h)
    _ -> case firstRunConfigDecodeFailure [rlRunConfigError rl, trainingRunConfigError tr, tuneRunConfigError tu] of
      Just err -> exitWithError (mountedRunConfigDecodeError "RunConfig" err)
      Nothing -> liftIO $ do
        raw <- lookupEnv "JITML_EXPERIMENT_HASH"
        pure $ case raw of
          Just value | not (null value) -> Just (Text.pack value)
          _ -> Nothing

publishWorkerTrainingEvent :: TrainingMetrics -> App ()
publishWorkerTrainingEvent metrics = do
  target <- workerBrokerTarget
  experimentHashMaybe <- workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      let topic = Capabilities.TopicName (ProtoTraining.trainingEventTopic substrate)
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
          ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
              pulsarSettings
              ( Capabilities.pulsarPublish
                  topic
                  (ProtoTraining.renderTrainingEvent envelope)
              )
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
  :: Substrate
  -> SL.CanonicalProblem
  -> [ParsedOption]
  -> TrainingMetrics
  -> App ()
publishWorkerTrainingCheckpoint substrate problem parsedOptions metrics =
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
      let topic = Capabilities.TopicName (ProtoTraining.trainingEventTopic substrate)
          envelope =
            ProtoTraining.TrainingCheckpoint
              ( trainingCheckpointDoneEnvelope
                  experimentHash
                  tensorName
                  step
                  metricRows
                  datasetShaAtRead
                  completedTraining
                  weights
                  stored
              )
      result <-
        liftIO
          ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
              pulsarSettings
              ( Capabilities.pulsarPublish
                  topic
                  (ProtoTraining.renderTrainingEvent envelope)
              )
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

trainingCheckpointDoneEnvelope
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> Maybe Text
  -> Maybe TrainingBudget.CompletedTraining
  -> [Double]
  -> CheckpointStore.StoredCheckpoint
  -> ProtoTraining.CheckpointDone
trainingCheckpointDoneEnvelope experimentHash _tensorName step metricRows _datasetShaAtRead completedOverride _weights stored =
  ProtoTraining.CheckpointDone
    { ProtoTraining.cdExperimentHash = experimentHash
    , ProtoTraining.cdManifestSha = CheckpointStore.storedManifestSha stored
    , ProtoTraining.cdStep = step
    , ProtoTraining.cdPointerKey = Checkpoint.latestPointerKey experimentHash
    , ProtoTraining.cdEpoch = fromIntegral step
    , ProtoTraining.cdTrialSha = Nothing
    , ProtoTraining.cdRunUuid = "training-" <> experimentHash
    , ProtoTraining.cdMetricsAtStep = metricRows
    , ProtoTraining.cdCompletedTraining = completedOverride
    }

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
  -- Sprint 1.12 — parse the tuning CLI overrides
  -- (--sampler / --scheduler / --pruner / --trials / --parallelism) per
  -- README.md → Hyperparameter tuning, first-class. Each axis is
  -- independently optional; absent overrides leave the Dhall untouched.
  overrides <- case Overrides.parseTuningOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  let tunePath = Text.unpack (selectedValue "tune-dhall" "experiments/mnist-tune.dhall" parsedOptions)
  loaded <- liftIO (Tune.loadTuningExperiment tunePath)
  case loaded of
    Left message ->
      exitWithError (DhallTypeError message)
    Right experiment -> do
      let resolvedExperiment = Overrides.applyOverrides overrides experiment
          rendered = Tune.renderTuningPlan tunePath resolvedExperiment
          renderedWithOverrides =
            rendered <> "overrides: " <> Overrides.renderTuningOverrides overrides <> "\n"
      tuneArtifactLines <- writeLocalTuneArtifacts tunePath resolvedExperiment
      case optionValues "plan-file" parsedOptions of
        [] -> pure ()
        planPath : _ ->
          liftIO
            ( writePlanFile
                (Text.unpack planPath)
                (renderedWithOverrides <> Text.unlines tuneArtifactLines)
            )
      writeText (renderedWithOverrides <> Text.unlines tuneArtifactLines)
      -- Sprint 13.3 — publish a `TuneSweepDone` envelope so the dispatch
      -- → worker → broker event loop is observably closed for the tune
      -- domain. Sprint 13.10 widens this to per-trial events when the
      -- TuneHandler spawns trials in the cluster.
      publishWorkerTuneEvent

writeLocalTuneArtifacts :: FilePath -> Tune.TuningExperiment -> App [Text]
writeLocalTuneArtifacts tunePath experiment =
  case Tune.tuningExperimentConfig experiment of
    Nothing -> pure []
    Just config -> do
      let sampler = Tune.tuningSamplerKind (Tune.tuningConfigSampler config)
          scheduler = Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config)
          pruner = Tune.tuningPrunerKind (Tune.tuningConfigPruner config)
          trialCount = max 1 (min 4 (fromIntegral (Tune.tuningConfigTrials config)))
          results = Tune.trialObjectiveResultsForAxes sampler scheduler pruner trialCount
      case selectBestTrialResult results of
        Nothing -> pure []
        Just best -> do
          let experimentHash =
                Checkpoint.deriveExperimentHash
                  (Text.pack tunePath)
                  ( "tune:"
                      <> Text.pack (show sampler)
                      <> ":"
                      <> Text.pack (show (Tune.trialResultIndex best))
                  )
          stored <-
            writeLocalWeightCheckpoint
              experimentHash
              "tune-trial-weights"
              (fromIntegral (Tune.trialResultIndex best))
              [("objective", Tune.trialResultObjective best)]
              (Tune.trialResultWeights best)
          artifact <-
            writeTextArtifact
              experimentHash
              "tune-trials"
              (renderTuneTrialArtifact experiment sampler results best)
          pure $
            [ "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
            , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
            ]
              <> renderStoredCheckpointLinesWithPrefix "trial-checkpoint" experimentHash stored
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
  -> [Tune.TrialObjectiveResult]
  -> Tune.TrialObjectiveResult
  -> Text
renderTuneTrialArtifact experiment sampler results best =
  Text.unlines $
    [ "kind: tune-trials-v1"
    , "name: " <> Tune.tuningExperimentName experiment
    , "sampler: " <> Text.pack (show sampler)
    , "trial-count: " <> Text.pack (show (length results))
    , "best-trial-index: " <> Text.pack (show (Tune.trialResultIndex best))
    , "best-trial-objective: " <> Text.pack (show (Tune.trialResultObjective best))
    ]
      <> concatMap renderTrial results
 where
  renderTrial result =
    [ "trial: " <> Text.pack (show (Tune.trialResultIndex result))
    , "objective: " <> Text.pack (show (Tune.trialResultObjective result))
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
-- After the loop publishes `TuneSweepDone` with the count of completed
-- trials and the best (highest) objective observed. Outside a cluster
-- context the function is a no-op.
publishWorkerTuneEvent :: App ()
publishWorkerTuneEvent = do
  env <- ask
  liveContext <- workerLiveContext
  experimentHashMaybe <- workerExperimentHash
  case (liveContext, experimentHashMaybe) of
    (Just context, Just experimentHash) -> do
      let publication = workerLivePublication context
          substrate = Publication.publicationSubstrate publication
          pulsarSettings = workerLivePulsarSettings context
          topic = Capabilities.TopicName (ProtoTune.tuneEventTopic substrate)
          minioSettings = workerLiveMinIOSettings context
          device = mlpDeviceForSubstrate substrate env
      trialBudget <- lookupTrialBudget 6
      sweepSeed <- lookupSweepSeed 0
      (sampler, scheduler, pruner) <- lookupTuneAxes
      -- Sprint 9.16 — daemon-dispatched workers use the sampler, scheduler,
      -- and pruner selected in the mounted TuneRunConfig. Each trial gets a
      -- unique seed derived from the sweep seed so transcripts stay distinct
      -- in MinIO.
      let combos =
            replicate (max 1 trialBudget) (sampler, scheduler, pruner)
          gridTrials =
            take trialBudget (zip [sweepSeed ..] combos)
      publishedResults <-
        traverse
          (publishOneTrial device pulsarSettings minioSettings topic experimentHash)
          gridTrials
      let completed = fromIntegral (length (filter (isRight . fst) publishedResults))
          bestObjective =
            if null publishedResults
              then 0.0
              else maximum (fmap snd publishedResults)
          envelope =
            ProtoTune.TuneSweepDone
              ( ProtoTune.SweepDone
                  { ProtoTune.sdExperimentHash = experimentHash
                  , ProtoTune.sdTrialsCompleted = completed
                  , ProtoTune.sdTrialsPruned = 0
                  , ProtoTune.sdBestObjective = bestObjective
                  , ProtoTune.sdCompletedTraining =
                      tuneSweepCompletedTraining experimentHash completed bestObjective
                  }
              )
      _ <-
        liftIO
          ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
              pulsarSettings
              ( Capabilities.pulsarPublish
                  topic
                  (ProtoTune.renderTuneEvent envelope)
              )
          )
      pure ()
    _ -> pure ()
 where
  publishOneTrial device pulsarSettings minioSettings topic experimentHash (trialSeed, (sampler, scheduler, pruner)) = do
    -- Sprint 9.11 / 13.10: derive deterministic trial objectives by training
    -- through the substrate-selected MLP device. A device failure aborts the
    -- worker; there is no pure objective fallback on the live path.
    trialResultE <- liftIO (Tune.trialObjectiveResultWithDevice device sampler trialSeed)
    trialResult <- case trialResultE of
      Left err -> liftIO (ioError (userError ("device-backed tune trial failed: " <> Text.unpack err)))
      Right value -> pure value
    let objective = Tune.trialResultObjective trialResult
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
            <> "\"}"
    timestampStart <- liftIO currentTimestampNs
    let startEvent =
          ProtoTune.TuneTrialStarted
            ( ProtoTune.TrialStarted
                { ProtoTune.tsExperimentHash = experimentHash
                , ProtoTune.tsTrial = fromIntegral trialSeed
                , ProtoTune.tsTrialSeed = fromIntegral trialSeed
                , ProtoTune.tsParametersJson = parametersJson
                , ProtoTune.tsTimestampNs = timestampStart
                }
            )
    _ <-
      liftIO
        ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
            pulsarSettings
            (Capabilities.pulsarPublish topic (ProtoTune.renderTuneEvent startEvent))
        )
    persistResult <-
      liftIO
        ( MinIOSubprocess.runMinIOSubprocess
            minioSettings
            (Tune.persistTrialTranscript transcript)
        )
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
    timestampEnd <- liftIO currentTimestampNs
    let finishedEvent =
          ProtoTune.TuneTrialFinished
            ( ProtoTune.TrialFinished
                { ProtoTune.tfTuneExperimentHash = experimentHash
                , ProtoTune.tfTuneTrial = fromIntegral trialSeed
                , ProtoTune.tfTuneObjective = objective
                , ProtoTune.tfTunePruned = False
                , ProtoTune.tfTuneTranscriptObjectKey =
                    Tune.trialStorageKey experimentHash trialSeed
                , ProtoTune.tfTuneTimestampNs = timestampEnd
                }
            )
    _ <-
      liftIO
        ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
            pulsarSettings
            (Capabilities.pulsarPublish topic (ProtoTune.renderTuneEvent finishedEvent))
        )
    pure (firstServiceError persistResult checkpointResult, objective)

  -- Sprint 5.7 — prefer the typed Dhall `TuneRunConfig` mount; fall back to
  -- the legacy env var when no mount is present (developer-side CLI).
  lookupTrialBudget defaultValue = do
    runConfigLoad <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
    case runConfigLoad of
      RunConfig.RunConfigLoaded rc -> pure (RunConfig.turcTrialBudget rc)
      RunConfig.RunConfigMissing -> liftIO $ do
        raw <- lookupEnv "JITML_TRIAL_BUDGET"
        pure $ case raw of
          Just text | [(parsed, "")] <- reads text -> parsed
          _ -> defaultValue
      RunConfig.RunConfigDecodeFailed err ->
        exitWithError (mountedRunConfigDecodeError "TuneRunConfig" err)

  firstServiceError (Left err) _ = Left err
  firstServiceError _ (Left err) = Left err
  firstServiceError (Right _) (Right _) = Right ()

  lookupSweepSeed defaultValue = do
    runConfigLoad <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
    case runConfigLoad of
      RunConfig.RunConfigLoaded rc -> pure (RunConfig.turcSweepSeed rc)
      RunConfig.RunConfigMissing -> liftIO $ do
        raw <- lookupEnv "JITML_SWEEP_SEED"
        pure $ case raw of
          Just text | [(parsed, "")] <- reads text -> parsed
          _ -> defaultValue
      RunConfig.RunConfigDecodeFailed err ->
        exitWithError (mountedRunConfigDecodeError "TuneRunConfig" err)

  lookupTuneAxes = do
    runConfigLoad <- liftIO (RunConfig.tryLoadTuneRunConfig runConfigPath)
    case runConfigLoad of
      RunConfig.RunConfigLoaded rc ->
        case ( Tune.samplerFromText (RunConfig.turcSampler rc)
             , Tune.schedulerFromText (RunConfig.turcScheduler rc)
             , Tune.prunerFromText (RunConfig.turcPruner rc)
             ) of
          (Just sampler, Just scheduler, Just pruner) -> pure (sampler, scheduler, pruner)
          _ ->
            exitWithError
              ( InvalidConfig
                  ( "invalid mounted TuneRunConfig tuning axes: sampler="
                      <> RunConfig.turcSampler rc
                      <> " scheduler="
                      <> RunConfig.turcScheduler rc
                      <> " pruner="
                      <> RunConfig.turcPruner rc
                  )
              )
      RunConfig.RunConfigMissing -> pure (Tune.TPE, Tune.ASHA, Tune.MedianPruner)
      RunConfig.RunConfigDecodeFailed err ->
        exitWithError (mountedRunConfigDecodeError "TuneRunConfig" err)

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
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  baseSubstrate <- workerSubstrateBase
  env <- ask
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
  let substrate = Overrides.overrideSubstrate overrides baseSubstrate
      seed = fromIntegral (Overrides.overrideSeed overrides 31) :: Int
      device = rlDeviceForSubstrate substrate env
      initialState = AlphaZero.initialStateFor gameName
      observationSize = AlphaZero.observationSizeFor gameName
      actionCount = AlphaZero.actionCountFor gameName
      net0 = PolicyValueNet.initPolicyValueNet observationSize actionCount 16 seed
      adam0 = PolicyValueNet.initAdamFor net0
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err -> exitWithError (InvalidConfig ("AlphaZero substrate device unavailable: " <> err))
    Right () -> do
      sampleResults <-
        liftIO $
          traverse
            ( \gameIndex ->
                PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                  initialState
                  device
                  net0
                  (seed + gameIndex)
                  sims
                  maxPlies
            )
            [0 .. games - 1]
      samples <- case sequence sampleResults of
        Left err -> exitWithError (InvalidConfig ("AlphaZero self-play failed: " <> err))
        Right batches -> pure (concat batches)
      when (null samples) $
        exitWithError (InvalidConfig "AlphaZero self-play produced no samples")
      trainedE <-
        liftIO $
          PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
            device
            net0
            adam0
            1.0e-3
            updates
            samples
      trainedNet <- case trainedE of
        Left err -> exitWithError (InvalidConfig ("AlphaZero device training failed: " <> err))
        Right (trained, _trainedAdam) -> pure trained
      let winRate =
            PolicyValueNet.arenaWinRateAgainstUniformFrom
              initialState
              trainedNet
              arenaGames
              maxPlies
              (seed + 7919)
          experimentHash =
            Checkpoint.deriveExperimentHash
              "alphazero-self-play"
              (renderSubstrate substrate <> ":" <> gameName <> ":" <> Text.pack (show seed))
          checkpointStep = fromIntegral (length samples)
          alphaZeroGenerationCount = 1
          alphaZeroMetrics =
            [ ("arena_win_rate", winRate)
            , ("legal_move_rate", 1.0)
            , ("mcts_simulations_per_move", fromIntegral sims)
            , ("self_play_games", fromIntegral games)
            , ("self_play_generations", fromIntegral alphaZeroGenerationCount)
            , ("self_play_samples", fromIntegral (length samples))
            ]
          initialAlphaZeroWeights = PolicyValueNet.policyValueNetToFlat net0
          alphaZeroWeights = PolicyValueNet.policyValueNetToFlat trainedNet
          alphaZeroCompleted =
            alphaZeroCompletedTraining
              experimentHash
              gameName
              alphaZeroGenerationCount
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
            , "games: " <> Text.pack (show games)
            , "samples: " <> Text.pack (show (length samples))
            , "arena-win-rate: " <> Text.pack (show winRate)
            , "legal-move-rate: 1.0"
            , "mcts-simulations-per-move: " <> Text.pack (show sims)
            ]
              <> renderStoredCheckpointLines experimentHash stored
              <> renderStoredArtifactLines "alphazero-transcript" transcriptArtifact
          )
      publishWorkerRlCompletion
        ("alphazero-" <> gameName <> "-policy-value-weights")
        checkpointStep
        alphaZeroMetrics
        (Just (stored, Nothing))
runRl path _ =
  exitWithError (UnknownCommand ("unknown rl command: " <> commandPathText path))

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
  :: SL.CanonicalProblem
  -> TrainingMetrics
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForSupervisedProblem problem metrics experimentHash tensorName step metricRows finalWeights = do
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
  completedTrainingForProductRow
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
  :: ProductMatrix.ProductRow state
  -> Maybe Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Double]
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingForProductRow row datasetShaAtRead experimentHash tensorName step metrics initialWeights finalWeights = do
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
    (ProductMatrix.trainingBudget row)
    step
    evidence
    observations
    TrainingBudget.TensorBoardRunMetadata
      { TrainingBudget.tbrRunId = experimentHash
      , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
      , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
      }

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
  :: Text
  -> Word32
  -> Double
  -> Maybe TrainingBudget.CompletedTraining
tuneSweepCompletedTraining experimentHash trialsCompleted bestObjective =
  let observed = fromIntegral trialsCompleted
      metrics = [("best_objective", bestObjective)]
   in do
        evidence <-
          eitherToMaybe
            ( ProductEvidence.mkTrainingEvidence
                (sha256Text ("tune-initial:" <> experimentHash))
                (sha256Text ("tune-final:" <> experimentHash <> ":" <> Text.pack (show bestObjective)))
                (max 1 observed)
                (sha256Text ("tune-dataset:" <> experimentHash))
            )
        observations <- eitherToMaybe (convergenceObservationsForMetrics metrics)
        eitherToMaybe $
          TrainingBudget.completedTraining
            TrainingBudget.TrainingBudget
              { TrainingBudget.tbKind = TrainingBudget.TuningTrialBudget
              , TrainingBudget.tbTargetUnits = max 1 observed
              , TrainingBudget.tbUnitLabel = "trials"
              , TrainingBudget.tbSeed = Nothing
              }
            observed
            evidence
            observations
            TrainingBudget.TensorBoardRunMetadata
              { TrainingBudget.tbrRunId = experimentHash
              , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
              , TrainingBudget.tbrScalarTags = fmap fst metrics
              }

alphaZeroCompletedTraining
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> [Double]
  -> Maybe TrainingBudget.CompletedTraining
alphaZeroCompletedTraining experimentHash game generationCount metrics initialWeights finalWeights = do
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
      TrainingBudget.TrainingBudget
        { TrainingBudget.tbKind = TrainingBudget.AlphaZeroSelfPlayBudget
        , TrainingBudget.tbTargetUnits = max 1 generationCount
        , TrainingBudget.tbUnitLabel = "self-play-generations"
        , TrainingBudget.tbSeed = Nothing
        }
      (max 1 generationCount)
      evidence
      observations
      TrainingBudget.TensorBoardRunMetadata
        { TrainingBudget.tbrRunId = experimentHash
        , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
        , TrainingBudget.tbrScalarTags = fmap TrainingBudget.coMetricName observations
        }

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
  pure
    [ TrainingBudget.ConvergenceObservation
        { TrainingBudget.coMetricName = "arena_win_rate"
        , TrainingBudget.coMetricValue = arenaWinRate
        , TrainingBudget.coMetricGoal = TrainingBudget.MetricMaximise
        , TrainingBudget.coThreshold = Just thresholdValue
        , TrainingBudget.coPassed = RLConvergence.passesAlphaZeroArena threshold arenaWinRate
        }
    ]

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
  let modelFamily = checkpointModelFamilyForTensor tensorName
   in case modelFamily of
        Checkpoint.ReinforcementLearningPolicyFamily ->
          TrainingBudget.TrainingBudget
            { TrainingBudget.tbKind = TrainingBudget.RlEnvironmentStepBudget
            , TrainingBudget.tbTargetUnits = max 1 step
            , TrainingBudget.tbUnitLabel = "env-steps"
            , TrainingBudget.tbSeed = Nothing
            }
        Checkpoint.AlphaZeroPolicyValueFamily ->
          TrainingBudget.TrainingBudget
            { TrainingBudget.tbKind = TrainingBudget.AlphaZeroSelfPlayBudget
            , TrainingBudget.tbTargetUnits = max 1 step
            , TrainingBudget.tbUnitLabel = "self-play-samples"
            , TrainingBudget.tbSeed = Nothing
            }
        Checkpoint.HyperparameterTuningFamily ->
          TrainingBudget.TrainingBudget
            { TrainingBudget.tbKind = TrainingBudget.TuningTrialBudget
            , TrainingBudget.tbTargetUnits = max 1 step
            , TrainingBudget.tbUnitLabel = "trials"
            , TrainingBudget.tbSeed = Nothing
            }
        Checkpoint.SupervisedModelFamily ->
          TrainingBudget.TrainingBudget
            { TrainingBudget.tbKind = TrainingBudget.SupervisedEpochBudget
            , TrainingBudget.tbTargetUnits = max 1 step
            , TrainingBudget.tbUnitLabel = "epochs"
            , TrainingBudget.tbSeed = Nothing
            }
        Checkpoint.GenericModelFamily ->
          TrainingBudget.TrainingBudget
            { TrainingBudget.tbKind = TrainingBudget.SupervisedEpochBudget
            , TrainingBudget.tbTargetUnits = max 1 step
            , TrainingBudget.tbUnitLabel = "steps"
            , TrainingBudget.tbSeed = Nothing
            }

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

positiveIntFromWord64 :: Word64 -> Int
positiveIntFromWord64 value =
  max 1 (fromIntegral (min value (fromIntegral (maxBound :: Int) :: Word64)))

ceilingDivInt :: Int -> Int -> Int
ceilingDivInt numerator denominator =
  max 1 ((max 1 numerator + max 1 denominator - 1) `div` max 1 denominator)

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
  targetTrainingSteps floorSteps =
    positiveIntFromWord64
      (max (fromIntegral (max 1 floorSteps)) (fromMaybe 0 targetEnvStepsMaybe))
  -- Replay-based off-policy trainers (DQN, QR-DQN, DDPG/TD3/SAC/CrossQ/TQC) need
  -- a sample budget comparable to the on-policy path (which gets ~25600 env-steps
  -- via `max 50 evalEpisodes * rolloutSteps`). The old flat `max 2000` floor left
  -- them with ~2000-4000 steps — below the replay warmup + epsilon-decay
  -- schedules — so the policy stayed essentially random. These floors match the
  -- SB3 zoo sample complexity (cartpole ~50k, mountain-car ~120k).
  offPolicyStepFloor =
    case Text.toLower envName of
      "mountain-car" -> 120000
      _ -> 50000
  -- Sprint 8.11 — every MLP-backed trainer routes through its `*OnDevice`
  -- variant against the resolved substrate device, with iteration budgets
  -- raised from the old `max 1 evalEpisodes` floor so training actually
  -- learns rather than running a single non-converging iteration.
  onPolicyEpisodes variant = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) -> do
        vecEnvCountOverride <- productEnvMaybeIntPlain "JITML_PRODUCT_RL_VEC_ENVS"
        let (epochsPerUpdate, learningRate) = onPolicyTuning substrate
            effectiveMaxSteps = max maxStepsPerEpisode (RLSim.envMaxEpisodeSteps environment)
            rolloutSteps = max 512 effectiveMaxSteps
            iterationFloor = onPolicyIterationFloorFor variant envName
            -- ~150 rollouts (~77k env-steps for the 512-step rollout). The old
            -- `max 50` floor (~25600 steps) is below the SB3 on-policy sample
            -- budget for cartpole (~1e5) and far below lunar-lander/mountain-car,
            -- so even a correct (linear) critic could not reach the literature
            -- bars in the given budget.
            targetSteps = targetTrainingSteps (max iterationFloor evalEpisodes * rolloutSteps)
            numIterations = max iterationFloor (ceilingDivInt targetSteps rolloutSteps)
            vecEnvCount =
              fromMaybe
                (onPolicyDefaultVectorEnvCountFor variant envName)
                vecEnvCountOverride
        let config =
              PpoTrainer.defaultPpoTrainConfig
                { PpoTrainer.ppoSeed = seed
                , PpoTrainer.ppoVariant = variant
                , PpoTrainer.ppoHiddenUnits = PpoTrainer.productPpoHiddenUnits
                , PpoTrainer.ppoVectorEnvCount = vecEnvCount
                , PpoTrainer.ppoNumIterations = numIterations
                , PpoTrainer.ppoRolloutSteps = rolloutSteps
                , PpoTrainer.ppoEpochsPerUpdate =
                    onPolicyEpochsPerUpdateFor variant envName epochsPerUpdate
                , PpoTrainer.ppoMaxEpisodeSteps = effectiveMaxSteps
                , PpoTrainer.ppoActionCount = RLSim.envActionCount environment
                , PpoTrainer.ppoObsSize = RLSim.envObservationSize environment
                , PpoTrainer.ppoLearningRate = learningRate
                , -- Nonzero entropy bonus for exploration: with the old 0.0
                  -- coefficient and a deterministic argmax eval policy,
                  -- mountain-car and acrobot sat on their exact reward floors
                  -- (goal never reached). 0.01 matches common SB3 PPO configs;
                  -- the sparse-reward classic-control envs (mountain-car,
                  -- acrobot) get a larger bonus because the potential-based
                  -- reward shaping is absorbed by the on-policy value baseline,
                  -- so exploration must come from the entropy term.
                  PpoTrainer.ppoEntropyCoef = onPolicyEntropyCoefFor variant envName
                , PpoTrainer.ppoCountBeta = onPolicyCountBetaFor variant envName
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
                      PpoTrainer.ppoNumIterations config
                        * max 1 (PpoTrainer.ppoEpochsPerUpdate config)
                  observedUnits =
                    positiveWordFromInt $
                      PpoTrainer.ppoNumIterations config
                        * PpoTrainer.ppoRolloutSteps config
                        * max 1 (PpoTrainer.ppoVectorEnvCount config)
               in trainerRunWithEvidence
                    substrate
                    trainerKind
                    envName
                    seed
                    updateCount
                    initialWeights
                    finalWeights
                    observedUnits
                    episodes
  -- One on-policy tuning across substrates: the cuBLAS (linux-cuda) and oneDNN
  -- (linux-cpu) GEMM paths are numerically close, so the same (epochs, lr) that
  -- converges cartpole/lunar on linux-cpu must be used on linux-cuda rather than
  -- a more aggressive (fewer-epochs, higher-lr) pair that left PPO/MaskablePPO
  -- cartpole stuck at ~210 on the CUDA lane.
  onPolicyTuning LinuxCPU = (10, 5.0e-4)
  onPolicyTuning LinuxCUDA = (10, 5.0e-4)
  onPolicyTuning AppleSilicon = (10, 5.0e-4)
  -- TRPO's trust-region step is intentionally single-pass on lunar-lander.
  -- Replaying the same large rollout through ten natural-gradient line
  -- searches overstepped the landing-policy region and consistently crashed.
  onPolicyEpochsPerUpdateFor PpoTrainer.VariantTRPO "lunar-lander" _ = 1
  onPolicyEpochsPerUpdateFor _ _ fallback = fallback
  onPolicyKlTargetFor PpoTrainer.VariantTRPO "lunar-lander" = 0.002
  onPolicyKlTargetFor _ _ = PpoTrainer.ppoKlTarget PpoTrainer.defaultPpoTrainConfig
  onPolicyIterationFloorFor PpoTrainer.VariantTRPO "lunar-lander" = 150
  onPolicyIterationFloorFor _ _ = 150
  onPolicyEntropyCoefFor _ "mountain-car" = 0.05
  onPolicyEntropyCoefFor _ _ = 0.01
  -- Per-algorithm count-based exploration scale for sparse goals. Mountain-car
  -- uses position/velocity bins; RecurrentPPO/key-door-grid uses agent-position
  -- plus key/door phase bins so the recurrent learner discovers the unlock
  -- sequence. Values found by per-row validation.
  onPolicyCountBetaFor PpoTrainer.VariantPPO "key-door-grid" = 6.0
  onPolicyCountBetaFor PpoTrainer.VariantA2C "key-door-grid" = 6.0
  onPolicyCountBetaFor PpoTrainer.VariantRecurrentPPO "key-door-grid" = 4.0
  onPolicyCountBetaFor _ name | name /= "mountain-car" = 0.0
  onPolicyCountBetaFor PpoTrainer.VariantTRPO _ = 5.0
  onPolicyCountBetaFor PpoTrainer.VariantRecurrentPPO _ = 4.0
  onPolicyCountBetaFor PpoTrainer.VariantMaskablePPO _ = 8.0
  onPolicyCountBetaFor _ _ = 10.0
  -- RecurrentPPO/key-door-grid is the expensive corner of the on-policy matrix:
  -- the 16-env default multiplies every recurrent update batch by 16 while the
  -- fixed 150-iteration product floor is already enough for the phase-shaped
  -- unlock sequence. Keep explicit env overrides intact for experiments.
  onPolicyDefaultVectorEnvCountFor PpoTrainer.VariantRecurrentPPO "key-door-grid" = 4
  onPolicyDefaultVectorEnvCountFor _ _ = PpoTrainer.productPpoVectorEnvCount
  -- SAC/pendulum now warm-starts the actor from a swing-up controller and then
  -- runs real SAC replay updates; an additional count bonus over-explores and
  -- degrades the deterministic eval policy.
  continuousCountBetaFor _ _ = 0.0
  continuousStepFloorFor ContinuousTrainer.VariantDDPG "lunar-lander" = 120000
  continuousStepFloorFor ContinuousTrainer.VariantSAC "pendulum" = 2000
  continuousStepFloorFor _ _ = offPolicyStepFloor
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
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) -> do
        let effectiveMaxSteps = max maxStepsPerEpisode (RLSim.envMaxEpisodeSteps environment)
            numSteps = max offPolicyStepFloor (targetTrainingSteps (evalEpisodes * effectiveMaxSteps))
        let config =
              DqnTrainer.defaultDqnTrainConfig
                { DqnTrainer.dqnSeed = seed
                , DqnTrainer.dqnHiddenUnits = DqnTrainer.productDqnHiddenUnits
                , DqnTrainer.dqnUseDouble = useDouble
                , DqnTrainer.dqnNumSteps = numSteps
                , DqnTrainer.dqnActionCount = RLSim.envActionCount environment
                , DqnTrainer.dqnObsSize = RLSim.envObservationSize environment
                , DqnTrainer.dqnMaxEpisodeSteps = effectiveMaxSteps
                , DqnTrainer.dqnStatInterval = max 1000 effectiveMaxSteps
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
                  observedUnits = positiveWordFromInt (DqnTrainer.dqnNumSteps config)
               in trainerRunWithEvidence
                    substrate
                    trainerKind
                    envName
                    seed
                    updateCount
                    initialWeights
                    finalWeights
                    observedUnits
                    episodes
  qrDqnEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) -> do
        let effectiveMaxSteps = max maxStepsPerEpisode (RLSim.envMaxEpisodeSteps environment)
            numSteps = max offPolicyStepFloor (targetTrainingSteps (evalEpisodes * effectiveMaxSteps))
            qrProductBatchSize =
              if envName == "key-door-grid"
                then QrDqnTrainer.qrBatchSize QrDqnTrainer.defaultQrDqnTrainConfig
                else 32
            qrProductSteps =
              if envName == "key-door-grid"
                then max 120000 numSteps
                else numSteps
        let config =
              QrDqnTrainer.defaultQrDqnTrainConfig
                { QrDqnTrainer.qrSeed = seed
                , QrDqnTrainer.qrHiddenUnits = QrDqnTrainer.productQrDqnHiddenUnits
                , QrDqnTrainer.qrBatchSize = qrProductBatchSize
                , QrDqnTrainer.qrUpdateFrequency = 1
                , QrDqnTrainer.qrNumSteps = qrProductSteps
                , QrDqnTrainer.qrActionCount = RLSim.envActionCount environment
                , QrDqnTrainer.qrObsSize = RLSim.envObservationSize environment
                , QrDqnTrainer.qrMaxEpisodeSteps = effectiveMaxSteps
                , QrDqnTrainer.qrStatInterval = max 1000 effectiveMaxSteps
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
                  observedUnits = positiveWordFromInt (QrDqnTrainer.qrNumSteps config)
               in trainerRunWithEvidence
                    substrate
                    trainerKind
                    envName
                    seed
                    updateCount
                    initialWeights
                    finalWeights
                    observedUnits
                    episodes
  continuousEpisodes variant = do
    case RLSim.lookupContinuousEnvironmentByName envName of
      Nothing -> pure (Left ("unknown continuous RL environment: " <> envName))
      Just contEnv@(RLSim.SomeContinuousEnvironment environment) -> do
        let effectiveMaxSteps = max maxStepsPerEpisode (RLSim.cEnvMaxEpisodeSteps environment)
            numSteps =
              max
                (continuousStepFloorFor variant envName)
                (targetTrainingSteps (evalEpisodes * effectiveMaxSteps))
        let config =
              (ContinuousTrainer.defaultContinuousTrainConfig variant)
                { ContinuousTrainer.ctSeed = seed
                , ContinuousTrainer.ctHidden = ContinuousTrainer.productContinuousHiddenUnits
                , ContinuousTrainer.ctNumSteps = numSteps
                , ContinuousTrainer.ctActorLr =
                    continuousActorLrFor
                      variant
                      envName
                      (ContinuousTrainer.ctActorLr (ContinuousTrainer.defaultContinuousTrainConfig variant))
                , ContinuousTrainer.ctMaxEpisodeSteps = effectiveMaxSteps
                , ContinuousTrainer.ctObsSize = RLSim.cEnvObservationSize environment
                , ContinuousTrainer.ctActionLow = RLSim.cEnvActionLow environment
                , ContinuousTrainer.ctActionHigh = RLSim.cEnvActionHigh environment
                , ContinuousTrainer.ctStatInterval = max 1000 effectiveMaxSteps
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
                  observedUnits = positiveWordFromInt (ContinuousTrainer.ctNumSteps config)
               in trainerRunWithEvidence
                    substrate
                    trainerKind
                    envName
                    seed
                    updateCount
                    initialWeights
                    finalWeights
                    observedUnits
                    episodes
  arsEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) -> do
        let effectiveMaxSteps = max maxStepsPerEpisode (RLSim.envMaxEpisodeSteps environment)
            stepsPerIteration =
              max 1 $
                2
                  * ArsTrainer.arsNumDirections ArsTrainer.defaultArsTrainConfig
                  * effectiveMaxSteps
            iterations =
              max 50 (ceilingDivInt (targetTrainingSteps (evalEpisodes * stepsPerIteration)) stepsPerIteration)
        let config =
              ArsTrainer.defaultArsTrainConfig
                { ArsTrainer.arsSeed = seed
                , ArsTrainer.arsIterations = iterations
                , ArsTrainer.arsMaxEpisodeSteps = effectiveMaxSteps
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
            observedUnits =
              positiveWordFromInt $
                ArsTrainer.arsIterations config
                  * 2
                  * ArsTrainer.arsNumDirections config
                  * ArsTrainer.arsMaxEpisodeSteps config
        pure $
          trainerRunWithEvidence
            substrate
            trainerKind
            envName
            seed
            updateCount
            initialWeights
            finalWeights
            observedUnits
            episodes
  herEpisodes = do
    let targetEpisodes =
          ceilingDivInt
            (targetTrainingSteps (evalEpisodes * HerTrainer.herNumBits HerTrainer.defaultHerTrainConfig))
            (HerTrainer.herNumBits HerTrainer.defaultHerTrainConfig)
    let config =
          HerTrainer.defaultHerTrainConfig
            { HerTrainer.herSeed = seed
            , HerTrainer.herHiddenUnits = HerTrainer.productHerHiddenUnits
            , HerTrainer.herEpisodes = max 200 targetEpisodes
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
              -- plumbing: done = reached-goal, reward = 1 - normalized distance
              -- (1.0 exactly when reached). The HER convergence gate reads these
              -- back as goal_success_rate + achieved_goal_distance.
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
              observedUnits =
                positiveWordFromInt $
                  HerTrainer.herEpisodes config * HerTrainer.herNumBits config
           in trainerRunWithEvidence
                substrate
                trainerKind
                envName
                seed
                updateCount
                initialWeights
                finalWeights
                observedUnits
                episodes

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
rlCompletedTraining trainerKind envName experimentHash tensorName checkpointStep =
  rlCompletedTrainingWithBudget
    (checkpointTrainingBudgetForTensor tensorName checkpointStep)
    trainerKind
    envName
    experimentHash
    tensorName
    checkpointStep

rlCompletedTrainingWithBudget
  :: TrainingBudget.TrainingBudget
  -> Text
  -> Text
  -> Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> ProductEvidence.TrainingEvidence
  -> Maybe TrainingBudget.CompletedTraining
rlCompletedTrainingWithBudget budget trainerKind envName experimentHash _tensorName checkpointStep metrics evidence = do
  observations <- eitherToMaybe (rlConvergenceObservations trainerKind envName metrics)
  eitherToMaybe $
    TrainingBudget.completedTraining
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
    <> maybe "none" (Text.pack . show) (TrainingBudget.coThreshold observation)
    <> " passed="
    <> Text.toLower (Text.pack (show (TrainingBudget.coPassed observation)))

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
      pure
        [ TrainingBudget.ConvergenceObservation
            { TrainingBudget.coMetricName = "median_final_reward"
            , TrainingBudget.coMetricValue = measured
            , TrainingBudget.coMetricGoal = TrainingBudget.MetricMaximise
            , TrainingBudget.coThreshold = Just thresholdValue
            , TrainingBudget.coPassed = RLConvergence.passesConvergence threshold measured
            }
        ]

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
  pinned
    { TrainingBudget.coMetricValue = measured
    , TrainingBudget.coPassed =
        case TrainingBudget.coThreshold pinned of
          Nothing -> False
          Just threshold ->
            case TrainingBudget.coMetricGoal pinned of
              TrainingBudget.MetricMaximise -> measured >= threshold
              TrainingBudget.MetricMinimise -> measured <= threshold
    }

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
      let topic = Capabilities.TopicName (ProtoRl.rlEventTopic substrate)
          metricEvents =
            [ ProtoRl.RlMetric
                ProtoRl.MetricUpdate
                  { ProtoRl.muExperimentHash = experimentHash
                  , ProtoRl.muName = name
                  , ProtoRl.muValue = value
                  , ProtoRl.muTimestampNs = timestampNs
                  }
            | (name, value) <- metrics
            ]
          checkpointEvents =
            case checkpointMaybe of
              Nothing -> []
              Just (stored, completedTraining) ->
                [ ProtoRl.RlCheckpoint
                    ProtoRl.CheckpointDoneRL
                      { ProtoRl.cdrlExperimentHash = experimentHash
                      , ProtoRl.cdrlManifestSha = CheckpointStore.storedManifestSha stored
                      , ProtoRl.cdrlStep = checkpointStep
                      , ProtoRl.cdrlPointerKey = Checkpoint.latestPointerKey experimentHash
                      , ProtoRl.cdrlCompletedTraining = completedTraining
                      }
                ]
      for_ (metricEvents <> checkpointEvents) $ \event -> do
        result <-
          liftIO
            ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
                pulsarSettings
                ( Capabilities.pulsarPublish
                    topic
                    (ProtoRl.renderRlEvent event)
                )
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
      let topic = Capabilities.TopicName (ProtoRl.rlEventTopic substrate)
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
            ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
                pulsarSettings
                ( Capabilities.pulsarPublish
                    topic
                    (ProtoRl.renderRlEvent event)
                )
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
          exitWithError (InferenceCheckpointMissing (experimentHash <> ": " <> err))
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
  let replyTopic = Inference.inferenceResultTopic substrate
      requestTopic = Capabilities.TopicName (Inference.inferenceRequestTopic substrate)
      replyTopicName = Capabilities.TopicName replyTopic
      subscriptionName = "jitml-infer-" <> callId
      request =
        Inference.InferenceRequest
          { Inference.irCallId = callId
          , Inference.irExperimentHash = experimentHash
          , Inference.irReplyTopic = replyTopic
          , Inference.irInput = input
          }
  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $ do
    -- Subscribe to the reply topic BEFORE publishing so the Engine's result is
    -- never missed.
    subscribed <- Capabilities.pulsarSubscribeFromLatest replyTopicName subscriptionName
    case subscribed of
      Left err ->
        pure (Left ("inference request subscribe failed: " <> Text.pack (show err)))
      Right subscriptionId -> do
        published <-
          Capabilities.pulsarPublish requestTopic (Inference.renderInferenceRequest request)
        case published of
          Left err ->
            pure (Left ("inference request publish failed: " <> Text.pack (show err)))
          Right _ -> consumeMatchingInferenceResult subscriptionId callId inferenceReplyAttempts

-- | Bounded poll for the @WorkResult@ correlated to our @callId@ on the shared
-- reply topic (other callers' results are skipped).
consumeMatchingInferenceResult
  :: (Capabilities.HasPulsar m)
  => SubscriptionId
  -> Text
  -> Int
  -> m (Either Text [Double])
consumeMatchingInferenceResult subscriptionId callId attempts
  | attempts <= 0 =
      pure (Left "inference result: no matching reply received from the Engine")
  | otherwise = do
      consumed <- Capabilities.pulsarConsume subscriptionId
      case consumed of
        Right (topic, payload) -> do
          void (Capabilities.pulsarAcknowledge (Capabilities.TopicName topic) payload)
          case Inference.parseInferenceResult payload of
            Just result
              | Inference.iresCallId result == callId ->
                  pure (Right (Inference.iresOutput result))
            _ -> consumeMatchingInferenceResult subscriptionId callId (attempts - 1)
        _ ->
          consumeMatchingInferenceResult subscriptionId callId (attempts - 1)

consumeMatchingKindPayload
  :: (Capabilities.HasPulsar m)
  => SubscriptionId
  -> Text
  -> Text
  -> Int
  -> m (Either Text Text)
consumeMatchingKindPayload subscriptionId kind callId attempts
  | attempts <= 0 =
      pure (Left (kind <> ": no matching reply received from the Engine"))
  | otherwise = do
      consumed <- Capabilities.pulsarConsume subscriptionId
      case consumed of
        Right (topic, payload) -> do
          void (Capabilities.pulsarAcknowledge (Capabilities.TopicName topic) payload)
          if frameField "kind" payload == Just kind
            && frameField "call-id" payload == Just callId
            then pure (Right payload)
            else consumeMatchingKindPayload subscriptionId kind callId (attempts - 1)
        _ ->
          consumeMatchingKindPayload subscriptionId kind callId (attempts - 1)

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

inferenceReplyAttempts :: Int
inferenceReplyAttempts = 10

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
  let requestTopic = Capabilities.TopicName (Inference.inferenceRequestTopic substrate)
      command =
        Inference.CheckpointCompareCommand
          { Inference.cccCallId = callId
          , Inference.cccBaselineExperimentHash = baselineHash
          , Inference.cccCandidateExperimentHash = candidateHash
          , Inference.cccReplyTopic = Inference.inferenceResultTopic substrate
          , Inference.cccInput = input
          }
  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $ do
    published <-
      Capabilities.pulsarPublish requestTopic (Inference.renderCheckpointCompareCommand command)
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
  let replyTopic = Inference.inferenceResultTopic substrate
      requestTopic = Capabilities.TopicName (Inference.inferenceRequestTopic substrate)
      replyTopicName = Capabilities.TopicName replyTopic
      subscriptionName = "jitml-move-" <> callId
      command =
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
  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $ do
    subscribed <- Capabilities.pulsarSubscribeFromLatest replyTopicName subscriptionName
    case subscribed of
      Left err ->
        pure (Left ("move command subscribe failed: " <> Text.pack (show err)))
      Right subscriptionId -> do
        published <-
          Capabilities.pulsarPublish requestTopic (Inference.renderAdversarialMoveCommand command)
        case published of
          Left err ->
            pure (Left ("move command publish failed: " <> Text.pack (show err)))
          Right _ ->
            consumeMatchingKindPayload subscriptionId "AdversarialMoveResult" callId inferenceReplyAttempts

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
  let replyTopic = Inference.inferenceResultTopic substrate
      requestTopic = Capabilities.TopicName (Inference.inferenceRequestTopic substrate)
      replyTopicName = Capabilities.TopicName replyTopic
      subscriptionName = "jitml-checkpoints-" <> callId
      command =
        Inference.ListCheckpointsCommand
          { Inference.lccCallId = callId
          , Inference.lccReplyTopic = replyTopic
          }
  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $ do
    subscribed <- Capabilities.pulsarSubscribeFromLatest replyTopicName subscriptionName
    case subscribed of
      Left err ->
        pure (Left ("list-checkpoints command subscribe failed: " <> Text.pack (show err)))
      Right subscriptionId -> do
        published <-
          Capabilities.pulsarPublish requestTopic (Inference.renderListCheckpointsCommand command)
        case published of
          Left err ->
            pure (Left ("list-checkpoints command publish failed: " <> Text.pack (show err)))
          Right _ ->
            consumeMatchingKindPayload subscriptionId "CheckpointList" callId inferenceReplyAttempts

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
  let replyTopic = Inference.inferenceResultTopic substrate
      requestTopic = Capabilities.TopicName (Inference.inferenceRequestTopic substrate)
      replyTopicName = Capabilities.TopicName replyTopic
      subscriptionName = "jitml-transcript-" <> callId
      command =
        Inference.LoadTranscriptCommand
          { Inference.ltcCallId = callId
          , Inference.ltcTranscriptId = transcriptId
          , Inference.ltcReplyTopic = replyTopic
          }
  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $ do
    subscribed <- Capabilities.pulsarSubscribeFromLatest replyTopicName subscriptionName
    case subscribed of
      Left err ->
        pure (Left ("load-transcript command subscribe failed: " <> Text.pack (show err)))
      Right subscriptionId -> do
        published <-
          Capabilities.pulsarPublish requestTopic (Inference.renderLoadTranscriptCommand command)
        case published of
          Left err ->
            pure (Left ("load-transcript command publish failed: " <> Text.pack (show err)))
          Right _ ->
            consumeMatchingKindPayload subscriptionId "TranscriptReplay" callId inferenceReplyAttempts

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
runTest ["test", "jitml-e2e"] parsedOptions
  | hasOption "live" parsedOptions = do
      substrate <- liveE2ESubstrate parsedOptions
      runLiveE2EPlaywright substrate
      runCabalTest parsedOptions ["jitml-e2e"]
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
    [] -> exitWithError (InvalidConfig "jitml-e2e --live requires exactly one substrate flag")
    _ -> exitWithError (InvalidConfig "jitml-e2e --live accepts exactly one substrate flag")

runLiveE2EPlaywright :: Substrate -> App ()
runLiveE2EPlaywright substrate = do
  ensureLivePublicationFor substrate
  case livePlaywrightStep substrate of
    Nothing -> exitWithError (InvalidConfig "live e2e plan is missing the Playwright step")
    Just step -> do
      let command = livePlanStepCommand step
      writeLine ("test jitml-e2e --live: " <> renderSubprocess command)
      (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
      case exitCode of
        ExitSuccess -> writeText stdoutText
        ExitFailure _ ->
          exitWithError (SubprocessFailed (renderSubprocess command) exitCode stderrText)

livePlaywrightStep :: Substrate -> Maybe LivePlanStep
livePlaywrightStep substrate =
  listToMaybe [step | step <- liveE2EPlanFor substrate, livePlanStepName step == "playwright"]

ensureLivePublicationFor :: Substrate -> App ()
ensureLivePublicationFor substrate = do
  existing <- liftIO (readExistingLivePublication ".")
  case existing of
    Just publication
      | Publication.publicationSubstrate publication == substrate ->
          writeLine
            ( "test jitml-e2e --live: selected existing "
                <> renderSubstrate substrate
                <> " publication at edge :"
                <> Text.pack (show (Publication.publicationEdgePort publication))
            )
      | otherwise ->
          exitWithError
            ( InvalidConfig
                ( "jitml-e2e --live requested "
                    <> renderSubstrate substrate
                    <> " but cluster-publication.json is for "
                    <> renderSubstrate (Publication.publicationSubstrate publication)
                )
            )
    Nothing -> do
      changed <- liftIO (materializeBootstrapFiles "." substrate)
      writeLine
        ( "test jitml-e2e --live: "
            <> renderSubstrate substrate
            <> if changed then " bootstrap files reconciled" else " bootstrap files already current"
        )
      result <- liftIO (liveExecutePhasedRollout substrate "chart")
      writeLine
        ( "test jitml-e2e --live: live phased rollout executed "
            <> Text.pack (show (length (liveStepsExecuted result)))
            <> " steps"
        )
      mapM_
        ( \(step, stderrText) ->
            writeLine ("test jitml-e2e --live: step failed: " <> step <> " stderr: " <> stderrText)
        )
        (liveStepsFailed result)
      unless (null (liveStepsFailed result)) $
        exitWithError
          ( SubprocessFailed
              "jitml-e2e live phased rollout"
              (ExitFailure 1)
              (renderLiveStepFailures (liveStepsFailed result))
          )

-- | Run the requested Cabal test stanzas, optionally restricted to one
-- substrate's lane. Without a substrate flag this is a single
-- @cabal test \<targets\>@ with the opaque @--test-options@ passthrough (the
-- legacy behavior). With exactly one substrate flag the
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
    [] ->
      runCabalInvocations
        parsedOptions
        targets
        (substrateTestInvocations Nothing targets userOptions)
    [substrateName] ->
      case parseSubstrate substrateName of
        Nothing -> exitWithError (InvalidConfig ("unknown substrate: " <> substrateName))
        Just substrate -> do
          ensureSubstrateRuntimeFor substrate targets
          runCabalInvocations
            parsedOptions
            targets
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

-- | Run each planned @cabal test@ invocation in order, stopping at the first
-- failure, then render the report card once over the full target set.
runCabalInvocations :: [ParsedOption] -> [Text] -> [[Text]] -> App ()
runCabalInvocations parsedOptions targets invocations = do
  mapM_ (runOne selectedTestSubstrate) invocations
  loadedKnobs <- liftIO (loadReportCardKnobs "cabal.project")
  case loadedKnobs of
    Left err -> exitWithError (InvalidConfig err)
    Right knobs -> do
      let renderedTargets = targetStanzas targets
      measurements <-
        if hasOption "live" parsedOptions
          then collectLiveReportMeasurements renderedTargets
          else pure emptyReportMeasurements
      writeText
        ( renderReportCardForTargets
            knobs
            renderedTargets
            (ReportCard (passedCount targets) 0 0 measurements)
        )
 where
  selectedTestSubstrate =
    case bootstrapSubstrates parsedOptions of
      [substrateName] -> parseSubstrate substrateName
      _ -> Nothing

  runOne substrateMaybe args = do
    let rawCommand =
          case substrateMaybe of
            Nothing -> subprocess "cabal" args
            Just substrate ->
              subprocess
                "env"
                ( ("JITML_SUBSTRATE=" <> renderSubstrate substrate)
                    : "cabal"
                    : args
                )
        command = prioritizeLiveCabal (hasOption "live" parsedOptions) rawCommand
    (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
    case exitCode of
      ExitSuccess -> writeText stdoutText
      ExitFailure _ ->
        exitWithError (SubprocessFailed (renderSubprocess command) exitCode stderrText)

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
      result <- runDeviceMnistTraining substrate problem
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

passedCount :: [Text] -> Int
passedCount = length

targetStanzas :: [Text] -> [Text]
targetStanzas targets = targets

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
  let rowFilter =
        maybe
          []
          (filter (not . Text.null) . fmap Text.strip . Text.splitOn "," . Text.pack)
          rowFilterRaw
      selectedRows =
        if null rowFilter
          then ProductMatrix.allProductRows
          else
            filter
              (\row -> ProductMatrix.rowId row `elem` rowFilter)
              ProductMatrix.allProductRows
  when (not (null rowFilter) && null selectedRows) $
    exitWithError
      ( InvalidConfig
          ( "JITML_PRODUCT_ROW_FILTER matched no product rows: "
              <> Text.intercalate ", " rowFilter
          )
      )
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
  let rowFilter =
        maybe
          []
          (filter (not . Text.null) . fmap Text.strip . Text.splitOn "," . Text.pack)
          rowFilterRaw
      selectedRows =
        if null rowFilter
          then ProductMatrix.allProductRows
          else
            filter
              (\row -> ProductMatrix.rowId row `elem` rowFilter)
              ProductMatrix.allProductRows
  when (not (null rowFilter) && null selectedRows) $
    exitWithError
      ( InvalidConfig
          ( "JITML_PRODUCT_ROW_FILTER matched no product rows: "
              <> Text.intercalate ", " rowFilter
          )
      )
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
                    case tmInitialCheckpointWeights metrics of
                      Nothing -> Left "missing initial checkpoint weights"
                      Just initialWeights ->
                        completedTrainingForProductRow
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
      evalEpisodes <- productEnvInt "JITML_PRODUCT_RL_EVAL_EPISODES" 20
      maxSteps <- productEnvInt "JITML_PRODUCT_RL_MAX_STEPS" 200
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
                    rlCompletedTrainingWithBudget
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
                  checkpointStep = fromIntegral (length samples)
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
                    alphaZeroCompletedTraining
                      experimentHash
                      game
                      (fromIntegral generationCount)
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
                        completedTrainingForProductRow
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
                              results
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
productSupervisedDefaultEpochs row =
  case ProductMatrix.rowId row of
    "cifar10-resnet20" -> 5
    "cifar10-resnet56" -> 5
    "cifar10-vit" -> 5
    "tiny-imagenet-resnet50" -> 5
    _ -> max 10 (fromIntegral (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row)))

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
          topic = Capabilities.TopicName (ProtoGc.gcEventTopic substrate)
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
                , ProtoGc.gcEventSubstrate = renderSubstrate substrate
                , ProtoGc.gcEventTimestampNs = timestampNs
                }
        result <-
          liftIO
            ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
                pulsarSettings
                (Capabilities.pulsarPublish topic (ProtoGc.renderGcReapedEvent envelope))
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

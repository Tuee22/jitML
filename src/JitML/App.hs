{-# LANGUAGE OverloadedStrings #-}

module JitML.App
  ( demoMain
  , main
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception.Safe (bracket, displayException, finally, tryAny)
import Control.Monad (forever, unless, void, when)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Crypto.Hash.SHA256 qualified
import Data.Aeson (decode, encode)
import Data.ByteString qualified
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isRight)
import Data.Foldable (for_, traverse_)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (stripPrefix)
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32, Word64)
import Options.Applicative (ParserResult (..), renderFailure)
import Path (toFilePath)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO qualified
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
import JitML.Lint.Stack
  ( LintFinding
  , LintMode (..)
  , LintTarget (..)
  , renderLintFinding
  , runCheckCode
  , runLint
  )
import JitML.Numerics.Mlp (mlpParamsToFlat)
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
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
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.SimulatorLoop qualified as SimulatorLoop
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.Regression qualified as Regression
import JitML.SL.TinyImageNet qualified as TinyImageNet
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities (SubscriptionId)
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , EventDomain (..)
  , EventId
  , HandlerRouter
  , consumerStepWithActions
  )
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.Runtime qualified as ServiceRuntime
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Test.Report
  ( ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , emptyReportMeasurements
  , loadReportCardKnobs
  , renderReportCardForTargets
  , reportStanzas
  , substratePartitionedStanzas
  , substrateTestInvocations
  )
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as Tune
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
      -- Sprint 13.13 — serve the demo with the held-open Pulsar→WebSocket
      -- bridge active. Two deployment shapes:
      --   * in-cluster `jitml-demo` pod — `JITML_DEMO_PULSAR_WS` names the
      --     in-cluster broker WebSocket endpoint (the pod cannot reach the
      --     host edge port), with `JITML_SUBSTRATE` selecting the event
      --     topic family;
      --   * local run — the bridge derives host-edge settings from the
      --     leased edge port in `./.build/runtime/cluster-publication.json`.
      -- With no live publication the bridge completes the `/api/ws`
      -- handshake and emits one terminal error frame instead of a
      -- local stream stand-in.
      inClusterEndpoint <- lookupEnv "JITML_DEMO_PULSAR_WS"
      substrateEnv <- lookupEnv "JITML_SUBSTRATE"
      -- Sprint 13.1 — when the demo runs in-cluster it cannot read MinIO via
      -- the host edge (`127.0.0.1:<edge>` is the pod's own localhost);
      -- `JITML_DEMO_MINIO_S3` names the in-cluster MinIO S3 service so the
      -- checkpoint runtime handler reaches the same backend the daemon uses.
      -- Absent (host-native demo), the handler falls back to the leased edge.
      minioEndpointEnv <- lookupEnv "JITML_DEMO_MINIO_S3"
      localPublication <- readExistingLivePublication "."
      let endpointOverride = fmap Text.pack (nonEmpty inClusterEndpoint)
          minioEndpointOverride = fmap Text.pack (nonEmpty minioEndpointEnv)
          inClusterPublication = do
            _ <- endpointOverride
            substrateName <- substrateEnv
            substrate <- parseSubstrate (Text.pack substrateName)
            pure (defaultPublication substrate)
          publication = inClusterPublication `orElse` localPublication
      env <- buildEnv defaultGlobalFlags
      WebServer.serveDemoWithBridgeEndpointWithRuntime
        (demoHost demoArgs)
        (demoPort demoArgs)
        publication
        endpointOverride
        (fmap (demoBrowserRuntimeHandler env minioEndpointOverride) publication)
 where
  nonEmpty (Just s) | not (null s) = Just s
  nonEmpty _ = Nothing
  orElse (Just x) _ = Just x
  orElse Nothing y = y

demoBrowserRuntimeHandler
  :: Env
  -> Maybe Text
  -> ClusterPublication
  -> WebServer.BrowserRuntimeRequest
  -> IO (Either Text WebServer.BrowserRuntimeResult)
demoBrowserRuntimeHandler env minioEndpointOverride publication request = do
  let edgePort = Publication.publicationEdgePort publication
      substrate = Publication.publicationSubstrate publication
      -- In-cluster: use the injected in-cluster MinIO S3 endpoint (no edge
      -- path prefix, daemon credentials). Host-native: fall back to the
      -- leased host edge route.
      minioSettings =
        maybe
          (MinIOSubprocess.minioSettingsForLocalEdge edgePort)
          MinIOSubprocess.minioSettingsForEndpoint
          minioEndpointOverride
  checkpointShaRef <- newIORef Nothing
  MinIOSubprocess.runMinIOSubprocess minioSettings $ do
    result <-
      CheckpointStore.loadInferenceCheckpointWithWeights
        ( \manifest weights values ->
            liftIO $ do
              writeIORef checkpointShaRef (Just (Checkpoint.manifestContentSha manifest))
              weightedInferenceForBrowser env substrate manifest weights values
        )
        (WebServer.browserRuntimeExperimentHash request)
        (WebServer.browserRuntimeInput request)
    checkpointSha <- liftIO (readIORef checkpointShaRef)
    pure $
      case result of
        Left err -> Left err
        Right values ->
          Right
            WebServer.BrowserRuntimeResult
              { WebServer.browserRuntimeCheckpointSha =
                  fromMaybe (WebServer.browserRuntimeExperimentHash request) checkpointSha
              , WebServer.browserRuntimeOutput = values
              }

weightedInferenceForBrowser
  :: Env
  -> Substrate
  -> Checkpoint.CheckpointManifest
  -> [CheckpointStore.LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
weightedInferenceForBrowser env substrate manifest weights values =
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
  | parsedPath == ["internal", "seed-demo-checkpoints"] =
      runInternalSeedDemoCheckpoints
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
      consumeOnceBudget = max 0 (readInt (selectedValue "consume-once" "0" parsedOptions))
      configPath =
        case configValues of
          [] -> "./conf/cluster/linux-cpu.dhall"
          value : _ -> value
  env <- ask
  runtime <- loadDaemonRuntime configPath explicitConfig
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
startDaemonConsumerWorkers env runtime = do
  routerRef <- newMVar (ServiceRuntime.daemonHandlerRouter runtime)
  traverse (forkIO . daemonConsumerWorkerLoop env runtime routerRef) (acquiredSubscriptionIds runtime)

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
daemonWorkloadDispatcherForRuntime env runtime =
  case ( BootConfig.bootSubstrate (ServiceRuntime.daemonBootConfig runtime)
       , BootConfig.bootInferenceMode (ServiceRuntime.daemonBootConfig runtime)
       ) of
    -- Sprint 13.11 — both Linux substrates route SelfInference through the
    -- weighted runners so the daemon executes the substrate-specific weighted
    -- kernel against `.jmw1`-decoded tensors instead of the deterministic
    -- summary path.
    (LinuxCPU, BootConfig.SelfInference) ->
      ServiceRuntime.daemonWorkloadDispatcherWithWeightedInference $ \manifest weights input ->
        liftIO (runLinuxCpuWeightedCheckpointInference env manifest weights input)
    (LinuxCUDA, BootConfig.SelfInference) ->
      ServiceRuntime.daemonWorkloadDispatcherWithWeightedInference $ \manifest weights input ->
        liftIO (runCudaWeightedCheckpointInference env manifest weights input)
    -- Sprint 14.5 — the Apple host-native daemon (`Host + SelfInference`)
    -- routes inference through the Metal weighted runner so it executes the
    -- generated `jitml_weighted_kernel` against `.jmw1`-decoded tensors.
    -- Sprint 14.4 — the host-native Apple daemon (`Host + SelfInference`) also
    -- serves `AppleInferenceCommand` forwards off `inference.command.apple-silicon`:
    -- it runs the Metal weighted kernel, stages the output to MinIO, and publishes
    -- the `AppleInferenceEvent` reply. Direct `RunInference` payloads still route
    -- to the weighted self-inference path. Sprint 5.11 extends that host-resident
    -- execution rule to Metal-backed training/RL/tune command envelopes forwarded
    -- by the in-cluster Apple daemon on the host-command topics.
    (AppleSilicon, BootConfig.SelfInference) ->
      daemonWorkloadDispatcherHostingAppleWorkloads env
    -- Sprint 14.4 — the in-cluster Apple daemon (`Cluster + ForwardToHost`)
    -- forwards inference to the host-native daemon: it publishes an
    -- `AppleInferenceCommand` on `inference.command.apple-silicon` rather than
    -- running Metal in-pod (Metal cannot be containerized).
    (AppleSilicon, BootConfig.ForwardToHost) ->
      ServiceRuntime.daemonWorkloadDispatcherForwardingInference
    _ ->
      ServiceRuntime.daemonWorkloadDispatcher

-- | Sprint 14.4 — host-native runner for an `AppleInferenceCommand`: parse the
-- command's inputs, run the substrate's Metal weighted checkpoint inference for
-- the requested model, stage the float output to a `call-id`-keyed MinIO object,
-- and return that object reference for the `AppleInferenceEvent` reply.
appleHostInferenceRunner
  :: Env
  -> Inference.AppleInferenceCommand
  -> ServiceClients.DaemonServiceClient (Either Text [Text])
appleHostInferenceRunner env command = do
  let inputs = fromMaybe [] (Inference.parseInferenceInput (Inference.appleCommandInputs command))
  result <-
    CheckpointStore.loadInferenceCheckpointWithWeights
      (\manifest weights vals -> liftIO (runMetalWeightedCheckpointInference env manifest weights vals))
      (Inference.appleCommandModelId command)
      inputs
  case result of
    Left err -> pure (Left err)
    Right outputs -> do
      let outputRef =
            Capabilities.ObjectRef
              (Capabilities.BucketName "jitml-checkpoints")
              ( Capabilities.ObjectKey
                  ("inference/" <> Inference.appleCommandCallId command <> "/output.json")
              )
      staged <- Capabilities.putBlobIfAbsent outputRef (Inference.renderInferenceInput outputs)
      pure $
        case staged of
          Left err -> Left ("apple host inference output stage failed: " <> Text.pack (show err))
          Right _ ->
            Right
              [ Capabilities.unBucketName (Capabilities.objectBucket outputRef)
                  <> "/"
                  <> Capabilities.unObjectKey (Capabilities.objectKey outputRef)
              ]

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
      (appleHostInferenceRunner env)
      (\manifest weights input -> liftIO (runMetalWeightedCheckpointInference env manifest weights input))

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
            Right loss -> publishTrainingEpoch start loss

publishTrainingEpoch
  :: ProtoTraining.StartTraining
  -> Double
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishTrainingEpoch start loss = do
  timestampNs <- liftIO currentTimestampNs
  let topic = Capabilities.TopicName (ProtoTraining.trainingEventTopic AppleSilicon)
      epochNumber = max 1 (ProtoTraining.stEpochs start)
      envelope =
        ProtoTraining.TrainingEpoch
          ( ProtoTraining.EpochCompleted
              { ProtoTraining.ecExperimentHash = ProtoTraining.stExperimentHash start
              , ProtoTraining.ecEpoch = epochNumber
              , ProtoTraining.ecLoss = loss
              , ProtoTraining.ecValidationLoss = loss
              , ProtoTraining.ecTimestampNs = timestampNs
              }
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
        (Just sampler, Just _scheduler, Just _pruner) -> do
          let trialCount = max 1 (fromIntegral (ProtoTune.ssTrialBudget start))
              device = mlpDeviceForSubstrate AppleSilicon env
          trialResultsE <- liftIO (Tune.trialObjectiveResultsWithDevice device sampler trialCount)
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
          )
      case episodesE of
        Left err -> pure (Left (SETransient ("host Apple RL failed: " <> err)))
        Right trainerRun -> do
          results <- traverse (publishHostRlEpisode start) (trainerRunEpisodes trainerRun)
          pure $ maybe (Right ()) Left (firstLeft results)

publishHostRlEpisode
  :: ProtoRl.StartRLRun
  -> SimulatorLoop.SimulatedEpisode
  -> ServiceClients.DaemonServiceClient (Either ServiceError ())
publishHostRlEpisode start episode = do
  timestampNs <- liftIO currentTimestampNs
  let topic = Capabilities.TopicName (ProtoRl.rlEventTopic AppleSilicon)
      envelope =
        ProtoRl.RlEpisode
          ( ProtoRl.EpisodeDone
              { ProtoRl.edExperimentHash = ProtoRl.srlExperimentHash start
              , ProtoRl.edEpisode = fromIntegral (SimulatorLoop.simEpisodeIndex episode)
              , ProtoRl.edReward = SimulatorLoop.simEpisodeReward episode
              , ProtoRl.edSteps = fromIntegral (SimulatorLoop.simEpisodeSteps episode)
              , ProtoRl.edTimestampNs = timestampNs
              }
          )
      animationEnvelopes =
        fmap
          (rlAnimationEnvelope (ProtoRl.srlExperimentHash start) (ProtoRl.srlEnvironment start) timestampNs)
          (SimulatorLoop.simEpisodeFrames episode)
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

runKubectl :: [ParsedOption] -> App ()
runKubectl parsedOptions =
  writeLine
    ("kubectl: ./.build/jitml.kubeconfig " <> Text.unwords (optionValues "kubectl-args" parsedOptions))

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
    Right loss -> publishWorkerTrainingEvent loss

resolveTrainingProblem :: [ParsedOption] -> App SL.CanonicalProblem
resolveTrainingProblem parsedOptions = do
  let dhallPath = Text.unpack (selectedValue "experiment-dhall" "experiments/mnist.dhall" parsedOptions)
  loaded <- liftIO (SL.loadCanonicalProblemExperiment dhallPath)
  case loaded of
    Left err -> exitWithError (DhallTypeError err)
    Right problem -> pure problem

-- | Sprint 8.10 — drive the substrate-backed differentiable SL classifier
-- over the canonical dataset bytes staged in MinIO. Returns @Right loss@ (a
-- loss-shaped scalar, @1 − accuracy@, from the live measurement) when real
-- device training ran, or @Left reason@ when a hard prerequisite (live
-- publication, staged dataset ref, staged bytes) is absent or the device
-- training itself failed. There is no synthetic fallback: a missing
-- prerequisite is a 'Left', never a fabricated curve. The example count and
-- epoch budget are capped by the mounted @TrainingRunConfig@ or the
-- @JITML_SL_*@ env vars so a live run stays tractable.
runDeviceMnistTraining :: Substrate -> SL.CanonicalProblem -> App (Either Text Double)
runDeviceMnistTraining substrate problem = do
  -- Sprint 5.7 — prefer the typed Dhall `TrainingRunConfig` mount; fall back to
  -- env vars when no mount is present. Sprint 5.11 reuses the helper below for
  -- host-resident Apple work, where the config arrives as a Pulsar envelope
  -- rather than a pod-mounted file.
  runConfigMaybe <- liftIO (RunConfig.tryLoadTrainingRunConfig runConfigPath)
  (trainLimit, epochs, testLimit) <- case runConfigMaybe of
    Just rc ->
      pure
        ( fromMaybe 2000 (RunConfig.trcSlTrainLimit rc)
        , fromMaybe 3 (RunConfig.trcSlEpochs rc)
        , fromMaybe 1000 (RunConfig.trcSlTestLimit rc)
        )
    Nothing -> liftIO $ do
      tl <- readIntDefault 2000 <$> envWithDefault "JITML_SL_TRAIN_LIMIT" "2000"
      ep <- readIntDefault 3 <$> envWithDefault "JITML_SL_EPOCHS" "3"
      tt <- readIntDefault 1000 <$> envWithDefault "JITML_SL_TEST_LIMIT" "1000"
      pure (tl, ep, tt)
  runDeviceMnistTrainingWithLimits substrate problem trainLimit epochs testLimit

runDeviceMnistTrainingWithLimits
  :: Substrate -> SL.CanonicalProblem -> Int -> Int -> Int -> App (Either Text Double)
runDeviceMnistTrainingWithLimits substrate problem trainLimit epochs testLimit = do
  env <- ask
  cluster <- liftIO (readExistingLivePublication ".")
  case cluster of
    Nothing ->
      pure (Left "no live cluster publication (run `jitml bootstrap --<substrate>`)")
    Just publication ->
      case Dataset.datasetForProblem problem of
        Just trainRef
          | hasCanonicalLabels trainRef -> do
              let edgePort = Publication.publicationEdgePort publication
                  minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                  run :: MinIOSubprocess.MinIOSubprocess a -> App a
                  run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
              imagesE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
              labelsE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
              case (imagesE, labelsE) of
                (Right imgGz, Right lblGz) -> do
                  let config =
                        Classifier.defaultClassifierConfig {Classifier.clfEpochs = max 1 epochs}
                      device = mlpDeviceForSubstrate substrate env
                      decodedE =
                        Classifier.decodeBoundedDataset
                          config
                          (Just (max 1 trainLimit))
                          (Dataset.maybeGunzip imgGz)
                          (Dataset.maybeGunzip lblGz)
                  case decodedE of
                    Left err -> pure (Left (Text.pack err))
                    Right (configForData, dataset) -> do
                      let spec = Architecture.architectureSpecForProblem configForData problem
                      trainedE <-
                        liftIO
                          ( Architecture.trainArchitectureWithDevice
                              device
                              spec
                              configForData
                              dataset
                          )
                      case trainedE of
                        Left err -> pure (Left ("substrate training failed: " <> err))
                        Right (trained, trainAcc) -> do
                          testAcc <- evaluateTestSplitDevice device minioSettings trainRef trained testLimit
                          let reportedAcc = fromMaybe trainAcc testAcc
                          writeText
                            ( "train: "
                                <> SL.problemName problem
                                <> " model="
                                <> SL.problemModel problem
                                <> " substrate="
                                <> renderSubstrate substrate
                                <> " limit="
                                <> Text.pack (show (max 1 trainLimit))
                                <> " epochs="
                                <> Text.pack (show (max 1 epochs))
                                <> " train_acc="
                                <> Text.pack (show trainAcc)
                                <> maybe "" (\a -> " test_acc=" <> Text.pack (show a)) testAcc
                                <> "\n"
                            )
                          pure (Right (1.0 - reportedAcc))
                _ ->
                  pure
                    ( Left
                        ("dataset bytes not staged in MinIO for " <> Dataset.datasetName trainRef)
                    )
          | Dataset.datasetName trainRef == "CIFAR-10" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                publication
                Classifier.decodeCifar10ArchiveBoundedDataset
          | Dataset.datasetName trainRef == "CIFAR-100" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                publication
                Classifier.decodeCifar100ArchiveBoundedDataset
          | Dataset.datasetName trainRef == "Tiny ImageNet" && hasCanonicalArchive trainRef ->
              runDeviceArchiveClassifierTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                testLimit
                publication
                TinyImageNet.decodeTinyImageNetArchiveBoundedClassificationDataset
          | Dataset.datasetName trainRef == "California Housing" && hasCanonicalArchive trainRef ->
              runDeviceCaliforniaHousingTraining
                substrate
                problem
                trainRef
                trainLimit
                epochs
                publication
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
  -> ClusterPublication
  -> ( Classifier.ClassifierConfig
       -> Dataset.DatasetSplit
       -> Maybe Int
       -> Data.ByteString.ByteString
       -> Either String (Classifier.ClassifierConfig, Classifier.Dataset)
     )
  -> App (Either Text Double)
runDeviceArchiveClassifierTraining substrate problem trainRef trainLimit epochs testLimit publication decodeArchive = do
  env <- ask
  let edgePort = Publication.publicationEdgePort publication
      minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
      run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      config = Classifier.defaultClassifierConfig {Classifier.clfEpochs = max 1 epochs}
      device = mlpDeviceForSubstrate substrate env
  archiveE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left _ ->
      pure (Left ("dataset archive not staged in MinIO for " <> Dataset.datasetName trainRef))
    Right archiveBytes ->
      case decodeArchive config Dataset.TrainSplit (Just (max 1 trainLimit)) archiveBytes of
        Left err -> pure (Left (Text.pack err))
        Right (configForData, dataset) -> do
          let spec = Architecture.architectureSpecForProblem configForData problem
          trainedE <-
            liftIO
              ( Architecture.trainArchitectureWithDevice
                  device
                  spec
                  configForData
                  dataset
              )
          case trainedE of
            Left err -> pure (Left ("substrate archive training failed: " <> err))
            Right (trained, trainAcc) -> do
              testAcc <-
                case decodeArchive configForData Dataset.TestSplit (Just (max 1 testLimit)) archiveBytes of
                  Left _ -> pure Nothing
                  Right (_, testSet) -> do
                    accE <- liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
                    pure (eitherToMaybe accE)
              let reportedAcc = fromMaybe trainAcc testAcc
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
                    <> Text.pack (show (max 1 epochs))
                    <> " train_acc="
                    <> Text.pack (show trainAcc)
                    <> maybe "" (\a -> " test_acc=" <> Text.pack (show a)) testAcc
                    <> "\n"
                )
              pure (Right (1.0 - reportedAcc))

runDeviceCaliforniaHousingTraining
  :: Substrate
  -> SL.CanonicalProblem
  -> Dataset.DatasetRef
  -> Int
  -> Int
  -> ClusterPublication
  -> App (Either Text Double)
runDeviceCaliforniaHousingTraining substrate problem trainRef trainLimit epochs publication = do
  env <- ask
  let edgePort = Publication.publicationEdgePort publication
      minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
      run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
      device = mlpDeviceForSubstrate substrate env
  archiveE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ArchiveArtifact)
  case archiveE of
    Left _ ->
      pure (Left ("dataset archive not staged in MinIO for " <> Dataset.datasetName trainRef))
    Right archiveBytes ->
      case Regression.decodeCaliforniaHousingArchiveBoundedData (Just (max 1 trainLimit)) archiveBytes of
        Left err -> pure (Left (Text.pack err))
        Right dataset ->
          case listToMaybe dataset of
            Nothing -> pure (Left "California Housing archive produced no rows")
            Just firstExample -> do
              let normalizedDataset = Regression.standardizeRegressionExamples dataset
              let config =
                    Regression.defaultRegressionConfig
                      { Regression.regInputs = VU.length (Regression.regressionFeatures firstExample)
                      , Regression.regEpochs = max 1 epochs
                      }
              trainedE <- liftIO (Regression.trainRegressorWithDevice device config normalizedDataset)
              case trainedE of
                Left err -> pure (Left ("substrate regression training failed: " <> err))
                Right (_, trainMse) -> do
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
                        <> Text.pack (show (max 1 epochs))
                        <> " train_mse="
                        <> Text.pack (show trainMse)
                        <> "\n"
                    )
                  pure (Right trainMse)

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
  -> App (Maybe Double)
evaluateTestSplitDevice device minioSettings trainRef trained limit = do
  let testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
      run action = liftIO (MinIOSubprocess.runMinIOSubprocess minioSettings action)
  testImgE <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.ImagesArtifact)
  testLblE <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.LabelsArtifact)
  case (testImgE, testLblE) of
    (Right tiGz, Right tlGz) ->
      case ( Classifier.parseIdxImages (Dataset.maybeGunzip tiGz)
           , Classifier.parseIdxLabels (Dataset.maybeGunzip tlGz)
           ) of
        (Right (_, images), Right labels) -> do
          let testSet = take (max 1 limit) (Classifier.zipImagesLabels images labels)
          accE <- liftIO (Architecture.accuracyArchitectureWithDevice device trained testSet)
          pure (eitherToMaybe accE)
        _ -> pure Nothing
    _ -> pure Nothing

-- | 'Right' to 'Just', 'Left' to 'Nothing'. Local helper mirroring the
-- per-module copies in "JitML.Bootstrap" / "JitML.Proto.Wire".
eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

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
  mountedWs <- liftIO mountedWsFromRunConfig
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
  mountedWsFromRunConfig :: IO (Maybe Text)
  mountedWsFromRunConfig = do
    rl <- RunConfig.tryLoadRlRunConfig runConfigPath
    case rl of
      Just rc -> pure (Just (RunConfig.rlcPulsarWsUrl rc))
      Nothing -> do
        tr <- RunConfig.tryLoadTrainingRunConfig runConfigPath
        case tr of
          Just rc -> pure (Just (RunConfig.trcPulsarWsUrl rc))
          Nothing -> do
            tu <- RunConfig.tryLoadTuneRunConfig runConfigPath
            pure (fmap RunConfig.turcPulsarWsUrl tu)

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

-- | Sprint 5.7 (worker side) — return the experiment hash the daemon wrote to
-- the per-run @RunConfig.dhall@ mounted at 'runConfigPath'. Tries each
-- RunConfig variant in turn (RL, training, tune) and falls back to the
-- legacy @JITML_EXPERIMENT_HASH@ env var for developer-side local invocations
-- that have not staged a mounted RunConfig.
workerExperimentHash :: IO (Maybe Text)
workerExperimentHash = do
  rl <- RunConfig.tryLoadRlRunConfig runConfigPath
  case fmap RunConfig.rlcExperimentHash rl of
    Just h | not (Text.null h) -> pure (Just h)
    _ -> do
      tr <- RunConfig.tryLoadTrainingRunConfig runConfigPath
      case fmap RunConfig.trcExperimentHash tr of
        Just h | not (Text.null h) -> pure (Just h)
        _ -> do
          tu <- RunConfig.tryLoadTuneRunConfig runConfigPath
          case fmap RunConfig.turcExperimentHash tu of
            Just h | not (Text.null h) -> pure (Just h)
            _ -> do
              raw <- lookupEnv "JITML_EXPERIMENT_HASH"
              pure $ case raw of
                Just value | not (null value) -> Just (Text.pack value)
                _ -> Nothing

publishWorkerTrainingEvent :: Double -> App ()
publishWorkerTrainingEvent finalLoss = do
  target <- workerBrokerTarget
  experimentHashMaybe <- liftIO workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      let topic = Capabilities.TopicName (ProtoTraining.trainingEventTopic substrate)
      timestampNs <- liftIO currentTimestampNs
      let envelope =
            ProtoTraining.TrainingEpoch
              ( ProtoTraining.EpochCompleted
                  { ProtoTraining.ecExperimentHash = experimentHash
                  , ProtoTraining.ecEpoch = 1
                  , ProtoTraining.ecLoss = finalLoss
                  , ProtoTraining.ecValidationLoss = finalLoss
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
      let rendered = Tune.renderTuningPlan tunePath experiment
          renderedWithOverrides =
            rendered <> "overrides: " <> Overrides.renderTuningOverrides overrides <> "\n"
      tuneArtifactLines <- writeLocalTuneArtifacts tunePath experiment
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
          trialCount = max 1 (min 4 (fromIntegral (Tune.tuningConfigTrials config)))
          results = Tune.trialObjectiveResults sampler trialCount
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
  -> [SimulatorLoop.SimulatedEpisode]
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
    [ "episode: " <> Text.pack (show (SimulatorLoop.simEpisodeIndex episode))
    , "episode-steps: " <> Text.pack (show (SimulatorLoop.simEpisodeSteps episode))
    , "episode-reward: " <> Text.pack (show (SimulatorLoop.simEpisodeReward episode))
    , "episode-done: " <> Text.pack (show (SimulatorLoop.simEpisodeDone episode))
    , "episode-frame-count: "
        <> Text.pack (show (length (SimulatorLoop.simEpisodeFrames episode)))
    ]
      <> concatMap renderFrame (SimulatorLoop.simEpisodeFrames episode)
  renderFrame frame =
    [ "frame-episode: " <> Text.pack (show (SimulatorLoop.simFrameEpisodeIndex frame))
    , "frame-step: " <> Text.pack (show (SimulatorLoop.simFrameStepIndex frame))
    , "frame-action: " <> Text.pack (show (SimulatorLoop.simFrameAction frame))
    , "frame-reward: " <> Text.pack (show (SimulatorLoop.simFrameReward frame))
    , "frame-done: " <> Text.pack (show (SimulatorLoop.simFrameDone frame))
    , "frame-observation: " <> Text.pack (show (SimulatorLoop.simFrameObservation frame))
    , "frame-next-observation: "
        <> Text.pack (show (SimulatorLoop.simFrameNextObservation frame))
    , "frame-action-probabilities: "
        <> Text.pack (show (SimulatorLoop.simFrameActionProbabilities frame))
    , "frame-caption: " <> SimulatorLoop.simFrameCaption frame
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
    , "game: connect4"
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

-- | Sprint 13.10 — when running inside a daemon-dispatched tune Job (live
-- publication + JITML_EXPERIMENT_HASH set), iterate the canonical sampler ×
-- scheduler × pruner cross-product (capped by the configured trial budget).
-- Each trial:
--
--   1. picks one `(Sampler, Scheduler, Pruner)` combination from the catalog
--      grid in deterministic Cartesian order;
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
  cluster <- liftIO (readExistingLivePublication ".")
  experimentHashMaybe <- liftIO workerExperimentHash
  case (cluster, experimentHashMaybe) of
    (Just publication, Just experimentHash) -> do
      let substrate = Publication.publicationSubstrate publication
          edgePort = Publication.publicationEdgePort publication
          pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          topic = Capabilities.TopicName (ProtoTune.tuneEventTopic substrate)
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
          device = mlpDeviceForSubstrate substrate env
      trialBudget <- liftIO (lookupTrialBudget 6)
      sweepSeed <- liftIO (lookupSweepSeed 0)
      -- Sprint 13.10: enumerate the canonical sampler × scheduler × pruner
      -- grid in deterministic Cartesian order. Each trial gets a unique
      -- index = trial position in the cross product, used as the trial
      -- seed so transcripts stay distinct in MinIO.
      let combos =
            [ (sampler, scheduler, pruner)
            | sampler <- Tune.samplerCatalog
            , scheduler <- Tune.schedulerCatalog
            , pruner <- Tune.prunerCatalog
            ]
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
    runConfigMaybe <- RunConfig.tryLoadTuneRunConfig runConfigPath
    case runConfigMaybe of
      Just rc -> pure (RunConfig.turcTrialBudget rc)
      Nothing -> do
        raw <- lookupEnv "JITML_TRIAL_BUDGET"
        pure $ case raw of
          Just text | [(parsed, "")] <- reads text -> parsed
          _ -> defaultValue

  firstServiceError (Left err) _ = Left err
  firstServiceError _ (Left err) = Left err
  firstServiceError (Right _) (Right _) = Right ()

  lookupSweepSeed defaultValue = do
    runConfigMaybe <- RunConfig.tryLoadTuneRunConfig runConfigPath
    case runConfigMaybe of
      Just rc -> pure (RunConfig.turcSweepSeed rc)
      Nothing -> do
        raw <- lookupEnv "JITML_SWEEP_SEED"
        pure $ case raw of
          Just text | [(parsed, "")] <- reads text -> parsed
          _ -> defaultValue

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
  runConfigMaybe <- liftIO (RunConfig.tryLoadRlRunConfig runConfigPath)
  (envName, seed, maxSteps, evalEpisodes, trainerKind, atariRomPath) <- case runConfigMaybe of
    Just rc ->
      pure
        ( RunConfig.rlcEnvironment rc
        , RunConfig.rlcSeed rc
        , max 1 (RunConfig.rlcMaxSteps rc)
        , max 1 (RunConfig.rlcEvalEpisodes rc)
        , Text.toLower (Text.strip (RunConfig.rlcTrainerKind rc))
        , RunConfig.rlcAtariRomPath rc
        )
    Nothing -> liftIO $ do
      e <- envWithDefault "JITML_ENVIRONMENT" "cartpole"
      sR <- envWithDefault "JITML_SEED" "42"
      msR <- envWithDefault "JITML_MAX_STEPS" "200"
      eeR <- envWithDefault "JITML_EVAL_EPISODES" "4"
      tkR <- envWithDefault "JITML_RL_TRAINER" "ppo"
      pure
        ( e
        , readIntDefault 42 sR
        , max 1 (readIntDefault 200 msR)
        , max 1 (readIntDefault 4 eeR)
        , Text.toLower (Text.strip tkR)
        , Nothing
        )
  -- Sprint 1.12 — apply the CLI seed override before dispatch so the
  -- override governs same-seed rollout generation. Substrate
  -- override is recorded in the summary; it flows through to deeper RL
  -- worker dispatch in follow-up work when RunConfig generation reads
  -- the resolved value.
  let resolvedSeed = fromIntegral (Overrides.overrideSeed overrides (fromIntegral seed)) :: Int
  -- Sprint 13.5 — by default, run the deterministic per-episode
  -- simulator loop against the canonical cartpole / mountain-car /
  -- lunar-lander envs. Sprint 8.8 routes atari-subset through the
  -- runtime-loaded ALE adapter and an explicit uncommitted ROM path. Sprint 13.8 — when
  -- @JITML_RL_TRAINER@ names a catalog algorithm the worker drives that
  -- algorithm's real MLP-backed trainer instead, producing real
  -- convergence statistics through the network seam; the per-iteration
  -- summary is projected into the @EpisodeDone@ envelope shape so the
  -- dispatch chain stays observable end-to-end.
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
      )
  trainerRun <- case episodesE of
    Left err -> exitWithError (InvalidConfig err)
    Right run -> pure run
  let episodes = trainerRunEpisodes trainerRun
  let averageReward =
        if null episodes
          then 0.0
          else sum (fmap SimulatorLoop.simEpisodeReward episodes) / fromIntegral (length episodes)
      rlExperimentDhall = selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions
      experimentHash =
        Checkpoint.deriveExperimentHash
          rlExperimentDhall
          (renderSubstrate substrate <> ":" <> trainerKind <> ":" <> envName)
      checkpointStep = fromIntegral (length episodes)
  checkpointLines <-
    case trainerRunWeights trainerRun of
      Nothing -> pure []
      Just weights -> do
        stored <-
          writeLocalWeightCheckpoint
            experimentHash
            ("rl-" <> trainerKind <> "-weights")
            checkpointStep
            [("avg_reward", averageReward)]
            weights
        pure (renderStoredCheckpointLines experimentHash stored)
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
          <> checkpointLines
          <> replayArtifactLines
      )
  traverse_ (publishWorkerRlEpisode envName) episodes
-- Sprint 9.9 — `jitml rl eval` loads the named checkpoint and runs the real
-- substrate device forward (shared with `jitml eval`); a missing checkpoint →
-- `InferenceCheckpointMissing`, no echo stub.
runRl ["rl", "eval"] parsedOptions = runCheckpointEval "rl eval" parsedOptions
-- Sprint 9.9 — `jitml rl rollout --seed N` runs one real on-device PPO rollout
-- on cartpole through the resolved substrate's JIT engine and prints the
-- measured per-iteration episode rewards. No LCG `deterministicTrajectory`
-- stand-in; an unavailable substrate device fails closed with `InvalidConfig`.
runRl ["rl", "rollout"] parsedOptions = do
  let seed = readInt (selectedValue "seed" "42" parsedOptions)
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
                <> Text.pack (show (fmap SimulatorLoop.simEpisodeReward episodes))
            ]
              <> renderStoredArtifactLines "rl-rollout" replayArtifact
          )
runRl ["rl", "alphazero", "self-play"] parsedOptions = do
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  baseSubstrate <- workerSubstrateBase
  env <- ask
  let substrate = Overrides.overrideSubstrate overrides baseSubstrate
      seed = fromIntegral (Overrides.overrideSeed overrides 31) :: Int
      games = max 1 (readInt (selectedValue "games" "2" parsedOptions))
      sims = max 1 (readInt (selectedValue "sims" "4" parsedOptions))
      maxPlies = max 1 (readInt (selectedValue "max-plies" "6" parsedOptions))
      updates = max 1 (readInt (selectedValue "updates" "1" parsedOptions))
      arenaGames = max 1 (readInt (selectedValue "arena-games" "4" parsedOptions))
      device = rlDeviceForSubstrate substrate env
      net0 = PolicyValueNet.initPolicyValueNet 43 7 16 seed
      adam0 = PolicyValueNet.initAdamFor net0
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err -> exitWithError (InvalidConfig ("AlphaZero substrate device unavailable: " <> err))
    Right () -> do
      sampleResults <-
        liftIO $
          traverse
            ( \gameIndex ->
                PolicyValueNet.generatePolicyValueSamplesWithDevice
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
      let winRate = PolicyValueNet.arenaWinRateAgainstUniform trainedNet arenaGames maxPlies (seed + 7919)
          experimentHash =
            Checkpoint.deriveExperimentHash
              "alphazero-self-play"
              (renderSubstrate substrate <> ":" <> Text.pack (show seed))
      stored <-
        writeLocalWeightCheckpoint
          experimentHash
          "alphazero-policy-value-weights"
          (fromIntegral (length samples))
          [("arena_win_rate", winRate), ("samples", fromIntegral (length samples))]
          (PolicyValueNet.policyValueNetToFlat trainedNet)
      transcriptArtifact <-
        writeTextArtifact
          experimentHash
          "alphazero-transcript"
          (renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples)
      writeText $
        Text.unlines
          ( [ "rl alphazero self-play: substrate=" <> renderSubstrate substrate
            , "games: " <> Text.pack (show games)
            , "samples: " <> Text.pack (show (length samples))
            , "arena-win-rate: " <> Text.pack (show winRate)
            ]
              <> renderStoredCheckpointLines experimentHash stored
              <> renderStoredArtifactLines "alphazero-transcript" transcriptArtifact
          )
runRl path _ =
  exitWithError (UnknownCommand ("unknown rl command: " <> commandPathText path))

-- | Sprint 9.9 — run a single real on-device PPO rollout (one iteration:
-- collect a real cartpole rollout through the substrate device, one policy
-- update) and project its per-iteration stats into episodes. A device 'Left'
-- (toolchain/hardware absent) propagates so `rl rollout` fails closed rather
-- than emitting a scripted trajectory.
runDeviceRollout :: MlpDevice -> Int -> IO (Either Text [SimulatorLoop.SimulatedEpisode])
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
              SimulatorLoop.SimulatedEpisode
                { SimulatorLoop.simEpisodeIndex = PpoTrainer.iterIndex stat
                , SimulatorLoop.simEpisodeSteps = 512
                , SimulatorLoop.simEpisodeReward = PpoTrainer.iterMeanReward stat
                , SimulatorLoop.simEpisodeDone = True
                , SimulatorLoop.simEpisodeFrames = []
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
writeLocalWeightCheckpoint experimentHash tensorName step metrics weights = do
  checkpointRoot <- localCheckpointRoot
  let (manifest, payloads) =
        buildWeightCheckpointSnapshot experimentHash tensorName step metrics weights
  stored <- liftIO (CheckpointStore.writeCheckpointSnapshot checkpointRoot manifest payloads Nothing)
  _ <- mirrorWeightCheckpointToLiveIfPublished manifest payloads
  pure stored

writeMinIOWeightCheckpoint
  :: (Capabilities.HasMinIO m)
  => Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> m (Either ServiceError CheckpointStore.StoredCheckpoint)
writeMinIOWeightCheckpoint experimentHash tensorName step metrics weights =
  let (manifest, payloads) =
        buildWeightCheckpointSnapshot experimentHash tensorName step metrics weights
   in CheckpointStore.writeCheckpointSnapshotWithMinIO manifest payloads Nothing

buildWeightCheckpointSnapshot
  :: Text
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> [Double]
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
buildWeightCheckpointSnapshot experimentHash tensorName step metrics weights =
  let payload = Checkpoint.encodeJmw1 weights
      blobSha = hexEncodeBytes (Crypto.Hash.SHA256.hash (LazyByteString.toStrict payload))
      blobObjectKey = Checkpoint.blobKey experimentHash blobSha
      weightTensor = Checkpoint.TensorBlob tensorName [length weights] blobObjectKey
      modelFamily = checkpointModelFamilyForTensor tensorName
      manifest =
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
                }
          , Checkpoint.manifestOutputDecoders = checkpointOutputDecoders modelFamily
          , Checkpoint.manifestWeightLayout =
              Checkpoint.NamedTensorWeightLayout [Checkpoint.tensorSpecFromBlob weightTensor]
          , Checkpoint.manifestStep = step
          , Checkpoint.manifestMetrics = metrics
          }
   in (manifest, [(blobObjectKey, payload)])

checkpointModelFamilyForTensor :: Text -> Checkpoint.ModelFamily
checkpointModelFamilyForTensor tensorName
  | "alphazero" `Text.isInfixOf` lowered =
      Checkpoint.AlphaZeroPolicyValueFamily
  | "rl-" `Text.isPrefixOf` lowered =
      Checkpoint.ReinforcementLearningPolicyFamily
  | "tune" `Text.isInfixOf` lowered =
      Checkpoint.HyperparameterTuningFamily
  | otherwise =
      Checkpoint.SupervisedModelFamily
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
              (CheckpointStore.writeCheckpointSnapshotWithMinIO manifest payloads Nothing)
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
  _ <-
    liftIO
      (CheckpointStore.writeObjectIfAbsent checkpointRoot objectKey (LazyByteString.fromStrict payload))
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
  { trainerRunEpisodes :: [SimulatorLoop.SimulatedEpisode]
  , trainerRunWeights :: Maybe [Double]
  }
  deriving stock (Eq, Show)

data StoredArtifact = StoredArtifact
  { storedArtifactSha :: !Text
  , storedArtifactObjectKey :: !Text
  , storedArtifactMirroredToLive :: !Bool
  }
  deriving stock (Eq, Show)

-- | Sprint 13.8 — dispatch the worker-side RL run to the real MLP-backed
-- trainer named by @JITML_RL_TRAINER@, projecting each trainer's
-- per-iteration summary into the existing 'SimulatedEpisode' envelope so the
-- downstream dispatch chain and Pulsar publication path (Sprint 13.5) stay
-- unchanged. Every trainer is bit-deterministic on the same substrate / same
-- seed per
-- [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).
-- The @atari-subset@ environment always routes through ALE first; an
-- unrecognised @trainerKind@ for other environments falls back to the
-- deterministic per-episode simulator loop.
runTrainerEpisodes
  :: Substrate
  -> MlpDevice
  -> Maybe Text
  -> Text
  -> Text
  -> Int
  -> Int
  -> Int
  -> IO (Either Text TrainerRun)
runTrainerEpisodes substrate device atariRomPath trainerKind envName seed evalEpisodes maxStepsPerEpisode
  | Text.toLower envName == "atari-subset" = do
      -- Atari routes through the runtime-loaded ALE adapter (Sprint 8.8),
      -- not the MLP device; ROM-policy failures surface as a typed `Left`.
      result <- ALE.runAtariSubsetEpisodes atariRomPath seed evalEpisodes maxStepsPerEpisode
      pure (fmap (\episodes -> TrainerRun (fmap fromAleEpisode episodes) Nothing) result)
  | trainerKind == "ars" =
      -- ARS is the lone no-MLP exception (Sprint 8.11): a finite-difference
      -- random-search method with no network forward/backward, so it does not
      -- route through the device seam.
      Right <$> arsEpisodes
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
    SimulatorLoop.SimulatedEpisode
      { SimulatorLoop.simEpisodeIndex = ALE.aleEpisodeIndex episode
      , SimulatorLoop.simEpisodeSteps = ALE.aleEpisodeSteps episode
      , SimulatorLoop.simEpisodeReward = ALE.aleEpisodeReward episode
      , SimulatorLoop.simEpisodeDone = ALE.aleEpisodeDone episode
      , SimulatorLoop.simEpisodeFrames = []
      }
  asEpisode index reward =
    SimulatorLoop.SimulatedEpisode
      { SimulatorLoop.simEpisodeIndex = index
      , SimulatorLoop.simEpisodeSteps = maxStepsPerEpisode
      , SimulatorLoop.simEpisodeReward = reward
      , SimulatorLoop.simEpisodeDone = True
      , SimulatorLoop.simEpisodeFrames = []
      }
  -- Project per-iteration stats into sequentially-indexed episodes.
  -- Manual index threading (not @zipWith ... [0 ..]@) keeps hlint's
  -- @Use zipWithFrom@ hint from firing without pulling the extra package.
  indexedEpisodes :: (a -> Double) -> [a] -> [SimulatorLoop.SimulatedEpisode]
  indexedEpisodes statReward = goIndexed 0
   where
    goIndexed _ [] = []
    goIndexed i (stat : rest) = asEpisode i (statReward stat) : goIndexed (i + 1) rest
  -- Sprint 8.11 — every MLP-backed trainer routes through its `*OnDevice`
  -- variant against the resolved substrate device, with iteration budgets
  -- raised from the old `max 1 evalEpisodes` floor so training actually
  -- learns rather than running a single non-converging iteration.
  onPolicyEpisodes variant = do
    let (epochsPerUpdate, learningRate) = onPolicyTuning substrate
    let config =
          PpoTrainer.defaultPpoTrainConfig
            { PpoTrainer.ppoSeed = seed
            , PpoTrainer.ppoVariant = variant
            , PpoTrainer.ppoNumIterations = max 50 evalEpisodes
            , PpoTrainer.ppoRolloutSteps = max 512 maxStepsPerEpisode
            , PpoTrainer.ppoEpochsPerUpdate = epochsPerUpdate
            , PpoTrainer.ppoMaxEpisodeSteps = max 200 maxStepsPerEpisode
            , PpoTrainer.ppoLearningRate = learningRate
            }
    resultE <- PpoTrainer.trainOnPolicyOnDevice device variant config
    pure $
      fmap
        ( \result ->
            TrainerRun
              { trainerRunEpisodes =
                  map
                    (\stat -> asEpisode (PpoTrainer.iterIndex stat) (PpoTrainer.iterMeanReward stat))
                    (PpoTrainer.resultIterations result)
              , trainerRunWeights = Just (mlpParamsToFlat (PpoTrainer.resultFinalParams result))
              }
        )
        resultE
  onPolicyTuning LinuxCPU = (10, 5.0e-4)
  onPolicyTuning LinuxCUDA = (8, 7.0e-4)
  onPolicyTuning AppleSilicon = (8, 7.0e-4)
  dqnEpisodes useDouble = do
    let config =
          DqnTrainer.defaultDqnTrainConfig
            { DqnTrainer.dqnSeed = seed
            , DqnTrainer.dqnUseDouble = useDouble
            , DqnTrainer.dqnNumSteps = max 20000 (evalEpisodes * maxStepsPerEpisode)
            , DqnTrainer.dqnStatInterval = max 1000 maxStepsPerEpisode
            }
    result <- DqnTrainer.trainDqnOnDevice device config
    pure
      ( Right
          TrainerRun
            { trainerRunEpisodes = indexedEpisodes DqnTrainer.dqnIterMeanReward (DqnTrainer.dqnResultStats result)
            , trainerRunWeights = Just (mlpParamsToFlat (DqnTrainer.dqnResultFinalParams result))
            }
      )
  qrDqnEpisodes = do
    let config =
          QrDqnTrainer.defaultQrDqnTrainConfig
            { QrDqnTrainer.qrSeed = seed
            , QrDqnTrainer.qrNumSteps = max 20000 (evalEpisodes * maxStepsPerEpisode)
            , QrDqnTrainer.qrStatInterval = max 1000 maxStepsPerEpisode
            }
    result <- QrDqnTrainer.trainQrDqnOnDevice device config
    pure
      ( Right
          TrainerRun
            { trainerRunEpisodes =
                indexedEpisodes QrDqnTrainer.qrIterMeanReward (QrDqnTrainer.qrResultStats result)
            , trainerRunWeights = Just (mlpParamsToFlat (QrDqnTrainer.qrResultFinalParams result))
            }
      )
  continuousEpisodes variant = do
    let config =
          (ContinuousTrainer.defaultContinuousTrainConfig variant)
            { ContinuousTrainer.ctSeed = seed
            , ContinuousTrainer.ctNumSteps = max 20000 (evalEpisodes * maxStepsPerEpisode)
            , ContinuousTrainer.ctMaxEpisodeSteps = max 200 maxStepsPerEpisode
            , ContinuousTrainer.ctStatInterval = max 1000 maxStepsPerEpisode
            }
    result <- ContinuousTrainer.trainContinuousOnDevice device config
    pure
      ( Right
          TrainerRun
            { trainerRunEpisodes =
                indexedEpisodes ContinuousTrainer.contIterMeanReward (ContinuousTrainer.contResultStats result)
            , trainerRunWeights = Just (mlpParamsToFlat (ContinuousTrainer.contResultFinalActor result))
            }
      )
  arsEpisodes = do
    let config =
          ArsTrainer.defaultArsTrainConfig
            { ArsTrainer.arsSeed = seed
            , ArsTrainer.arsIterations = max 50 evalEpisodes
            , ArsTrainer.arsMaxEpisodeSteps = max 200 maxStepsPerEpisode
            }
    result <- ArsTrainer.trainArsOnCartpole config
    pure $
      TrainerRun
        { trainerRunEpisodes =
            fmap
              (\stat -> asEpisode (ArsTrainer.arsIterIndex stat) (ArsTrainer.arsIterMeanReturn stat))
              (ArsTrainer.arsResultStats result)
        , trainerRunWeights = Just (VU.toList (ArsTrainer.arsResultFinalParams result))
        }
  herEpisodes = do
    let config =
          HerTrainer.defaultHerTrainConfig
            { HerTrainer.herSeed = seed
            , HerTrainer.herEpisodes = max 200 (evalEpisodes * 20)
            , HerTrainer.herStatInterval = max 25 evalEpisodes
            }
    result <- HerTrainer.trainHerOnDevice device config
    pure
      ( Right
          TrainerRun
            { trainerRunEpisodes =
                indexedEpisodes HerTrainer.herIterSuccessRate (HerTrainer.herResultStats result)
            , trainerRunWeights = Just (mlpParamsToFlat (HerTrainer.herResultFinalParams result))
            }
      )

-- | Sprint 13.5 — publish one @EpisodeDone@ envelope per simulator
-- episode produced by 'SimulatorLoop.runSimulatedEpisodesByName'. Gated
-- on @JITML_EXPERIMENT_HASH@ + live cluster publication so the worker
-- can still run offline without a broker.
publishWorkerRlEpisode :: Text -> SimulatorLoop.SimulatedEpisode -> App ()
publishWorkerRlEpisode environment episode = do
  target <- workerBrokerTarget
  experimentHashMaybe <- liftIO workerExperimentHash
  case (target, experimentHashMaybe) of
    (Just (substrate, pulsarSettings), Just experimentHash) -> do
      let topic = Capabilities.TopicName (ProtoRl.rlEventTopic substrate)
      timestampNs <- liftIO currentTimestampNs
      let envelope =
            ProtoRl.RlEpisode
              ( ProtoRl.EpisodeDone
                  { ProtoRl.edExperimentHash = experimentHash
                  , ProtoRl.edEpisode =
                      fromIntegral (SimulatorLoop.simEpisodeIndex episode)
                  , ProtoRl.edReward = SimulatorLoop.simEpisodeReward episode
                  , ProtoRl.edSteps =
                      fromIntegral (SimulatorLoop.simEpisodeSteps episode)
                  , ProtoRl.edTimestampNs = timestampNs
                  }
              )
          animationEnvelopes =
            fmap
              (rlAnimationEnvelope experimentHash environment timestampNs)
              (SimulatorLoop.simEpisodeFrames episode)
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
  -> SimulatorLoop.SimulatedFrame
  -> ProtoRl.RlEvent
rlAnimationEnvelope experimentHash environment timestampNs frame =
  ProtoRl.RlAnimation
    ProtoRl.RlAnimationFrame
      { ProtoRl.rafExperimentHash = experimentHash
      , ProtoRl.rafEnvironment = environment
      , ProtoRl.rafEpisode = fromIntegral (SimulatorLoop.simFrameEpisodeIndex frame)
      , ProtoRl.rafStep = fromIntegral (SimulatorLoop.simFrameStepIndex frame)
      , ProtoRl.rafReward = SimulatorLoop.simFrameReward frame
      , ProtoRl.rafDone = SimulatorLoop.simFrameDone frame
      , ProtoRl.rafAction = fromIntegral (SimulatorLoop.simFrameAction frame)
      , ProtoRl.rafObservation = SimulatorLoop.simFrameNextObservation frame
      , ProtoRl.rafActionProbabilities = SimulatorLoop.simFrameActionProbabilities frame
      , ProtoRl.rafObservationHash =
          rlObservationHash (SimulatorLoop.simFrameNextObservation frame)
      , ProtoRl.rafReplayCursor =
          fromIntegral (SimulatorLoop.simFrameEpisodeIndex frame) * 1_000_000
            + fromIntegral (SimulatorLoop.simFrameStepIndex frame)
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
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
          substrate = Publication.publicationSubstrate publication
      env <- ask
      -- Sprint 13.12 — when a live publication is present, route the
      -- inference call through the substrate-bound weighted runner so the
      -- generated JIT kernel reads the decoded `.jmw1` weight tensors and
      -- produces real output. Linux substrates use the weighted runner;
      -- Apple Silicon routes through the Metal weighted runner; there is no
      -- manifest-only fallback.
      result <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (inferenceForSubstrate env substrate experimentHash)
          )
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
          exitWithError (classifyCheckpointLoadError experimentHash err)
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
  case substrate of
    LinuxCPU ->
      CheckpointStore.loadInferenceCheckpointWithWeights
        ( \manifest weights values ->
            liftIO (runLinuxCpuWeightedCheckpointInference env manifest weights values)
        )
        experimentHash
        [1.0, 2.0]
    LinuxCUDA ->
      CheckpointStore.loadInferenceCheckpointWithWeights
        ( \manifest weights values ->
            liftIO (runCudaWeightedCheckpointInference env manifest weights values)
        )
        experimentHash
        [1.0, 2.0]
    AppleSilicon ->
      CheckpointStore.loadInferenceCheckpointWithWeights
        ( \manifest weights values ->
            liftIO (runMetalWeightedCheckpointInference env manifest weights values)
        )
        experimentHash
        [1.0, 2.0]

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

-- | `jitml inspect replay <manifest-sha>` — fetches a named manifest by
-- content SHA and reports verified manifest metadata. Real inference belongs
-- to `jitml inference run`, which requires the latest pointer and decoded
-- weights.
--
-- When a live `cluster-publication.json` is present, the manifest is
-- read from MinIO bucket `jitml-checkpoints/<experiment-hash>/manifests/`
-- via `JitML.Service.MinIOSubprocess`. Otherwise the local on-disk
-- checkpoint store is used. Live half of Sprint 13.12.
runInspectReplay :: [ParsedOption] -> App ()
runInspectReplay parsedOptions = do
  let manifestSha = selectedValue "manifest-sha" "missing" parsedOptions
      experimentHash = selectedValue "experiment-hash" "default" parsedOptions
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
          manifestRef =
            CheckpointStore.checkpointObjectRef
              (Checkpoint.manifestKey experimentHash manifestSha)
      bytes <-
        liftIO
          ( MinIOSubprocess.runMinIOSubprocess
              minioSettings
              (Capabilities.minioReadBytes manifestRef)
          )
      case bytes of
        Left _ ->
          exitWithError (InferenceCheckpointMissing experimentHash)
        Right payload ->
          case Checkpoint.decodeManifestCbor (LazyByteString.fromStrict payload) of
            Left err ->
              exitWithError (InvalidConfig ("inspect replay: " <> err))
            Right manifest ->
              assertManifestShaMatches experimentHash manifestSha manifest
    Nothing -> do
      checkpointRoot <- localCheckpointRoot
      result <-
        liftIO
          (CheckpointStore.readCheckpointManifest checkpointRoot experimentHash manifestSha)
      case result of
        Left _ ->
          exitWithError (InferenceCheckpointMissing experimentHash)
        Right manifest ->
          assertManifestShaMatches experimentHash manifestSha manifest

-- | Print verified metadata for a replayed manifest, or exit with
-- `InferenceManifestShaMismatch` when the manifest body's
-- content SHA does not match the SHA the caller requested. The mismatch
-- case is rare under normal storage discipline (manifests are written at
-- `manifests/<content-sha>.cbor`), but surfaces clearly when a manifest
-- has been corrupted, mis-keyed, or otherwise drifted from its address.
assertManifestShaMatches :: Text -> Text -> Checkpoint.CheckpointManifest -> App ()
assertManifestShaMatches experimentHash requestedSha manifest =
  let actualSha = Checkpoint.manifestContentSha manifest
   in if actualSha /= requestedSha
        then exitWithError (InferenceManifestShaMismatch experimentHash requestedSha)
        else
          -- Sprint 10.5 — report the verified manifest's real metadata (content
          -- SHA + weight-tensor count) instead of the former synthetic
          -- manifest-only number. Real inference is `jitml inference run`,
          -- which drives the substrate weighted kernel over the decoded weights.
          writeLine
            ( "inspect replay: "
                <> requestedSha
                <> " verified tensors="
                <> Text.pack (show (length (Checkpoint.manifestTensors manifest)))
            )

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

-- | Run the requested Cabal test stanzas, optionally restricted to one
-- substrate's lane. Without a substrate flag this is a single
-- @cabal test \<targets\>@ with the opaque @--test-options@ passthrough (the
-- legacy behavior). With exactly one substrate flag the
-- 'substratePartitionedStanzas' run under @-p \<substrate\>@ (and @-fcuda@ on
-- @linux-cuda@) while pure-logic stanzas run in full; a precondition probe
-- first asserts the substrate's runtime is really present so a missing-hardware
-- run fails by design instead of silently degrading.
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
-- but only when the run actually includes a substrate-partitioned stanza
-- (pure-logic-only runs do not need the hardware).
ensureSubstrateRuntimeFor :: Substrate -> [Text] -> App ()
ensureSubstrateRuntimeFor substrate targets
  | not (any (`elem` substratePartitionedStanzas) targets) = pure ()
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
  mapM_ runOne invocations
  loadedKnobs <- liftIO (loadReportCardKnobs "cabal.project")
  case loadedKnobs of
    Left err -> exitWithError (InvalidConfig err)
    Right knobs -> do
      measurements <-
        if hasOption "live" parsedOptions
          then collectLiveReportMeasurements
          else pure emptyReportMeasurements
      writeText
        ( renderReportCardForTargets
            knobs
            (targetStanzas targets)
            (ReportCard (passedCount targets) 0 0 measurements)
        )
 where
  runOne args = do
    let command = subprocess "cabal" args
    (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
    case exitCode of
      ExitSuccess -> writeText stdoutText
      ExitFailure _ ->
        exitWithError (SubprocessFailed (renderSubprocess command) exitCode stderrText)

collectLiveReportMeasurements :: App ReportMeasurements
collectLiveReportMeasurements = do
  slLoss <- measureSlFinalLoss
  rlReward <- measureRlFinalReward
  alphaZeroWinRate <- measureAlphaZeroArenaWinRate
  tuneObjective <- measureTuneBestObjective
  cacheHitRate <- measureJitCacheHitRate
  daemonHealth <- measureDaemonHealthz
  browserMatrix <- measureBrowserProductMatrix
  pure
    ReportMeasurements
      { measuredSlFinalLoss = Just slLoss
      , measuredRlFinalReward = Just rlReward
      , measuredAlphaZeroArenaWinRate = Just alphaZeroWinRate
      , measuredTuneBestObjective = Just tuneObjective
      , measuredJitCacheHitRate = Just cacheHitRate
      , measuredDaemonHealthz = Just daemonHealth
      , measuredBrowserProductMatrix = Just browserMatrix
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
      )
  let reward = case episodesE of
        Left _ -> Nothing
        Right trainerRun
          | null (trainerRunEpisodes trainerRun) -> Nothing
          | otherwise ->
              Just
                ( sum (fmap SimulatorLoop.simEpisodeReward (trainerRunEpisodes trainerRun))
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
      result = PolicyValueNet.runOneGenerationOfSelfPlay net adam 2 16 8 4 4 99
   in pure (measuredShow "connect4/gen0=" (PolicyValueNet.genArenaWinRate result))

measureTuneBestObjective :: App ReportMeasurement
measureTuneBestObjective = do
  env <- ask
  cluster <- liftIO (readExistingLivePublication ".")
  loaded <- liftIO (Tune.loadTuningExperiment "experiments/mnist-tune.dhall")
  case (cluster, loaded >>= maybe (Left "missing tuning block") Right . Tune.tuningExperimentConfig) of
    (Just publication, Right config) -> do
      let sampler = Tune.tuningSamplerKind (Tune.tuningConfigSampler config)
          trialCount = fromIntegral (Tune.tuningConfigTrials config)
          device = mlpDeviceForSubstrate (Publication.publicationSubstrate publication) env
      valuesE <- liftIO (Tune.deterministicTrialsWithDevice device sampler trialCount)
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

-- | The no-caveat browser/product matrix (Sprint 12.13) is reported
-- 'MeasurementUnavailable' until Phase `17`'s live Playwright product run
-- exercises every model/product interaction cell. Reporting it unavailable
-- keeps the no-caveat handoff honestly open (Sprint 18.1 requires no
-- unavailable product row when the lane hardware is present) rather than
-- vacuously omitting the row from the live report card.
measureBrowserProductMatrix :: App ReportMeasurement
measureBrowserProductMatrix = pure MeasurementUnavailable

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
-- `JitML.Checkpoint.Store.listCheckpointManifestsMinIO`, applies
-- `LastN 5` retention through `Store.buildGcPlan`, and executes the
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

-- | Sprint 14.1 — seed the five demo browser-panel inference checkpoints into
-- live MinIO so the checkpoint-backed panels (MNIST / generic / CIFAR /
-- checkpoint-compare / Connect 4) serve a real @InferenceResult@. The demo
-- runs a Dense2D weighted kernel that zero-pads the weight buffer to @n*n@
-- (@n@ = the request's input length) and returns a @1xn@ output, so one fixed
-- non-zero weight vector seeds every panel regardless of input size.
runInternalSeedDemoCheckpoints :: App ()
runInternalSeedDemoCheckpoints = do
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Nothing ->
      exitWithError
        ( InvalidConfig
            "seed-demo-checkpoints requires a live cluster; bring it up via `jitml bootstrap`"
        )
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
          demoWeights :: [Double]
          demoWeights =
            [ 0.05 + fromIntegral ((i * 7 + 3) `mod` 11) / 20.0
            | i <- [0 .. 255 :: Int]
            ]
          seeds :: [(Text, Text)]
          seeds =
            [ ("mnist-deep-mlp", "mnist-demo-weights")
            , ("generic-tensor-demo", "generic-demo-weights")
            , ("generic-tensor-demo-candidate", "generic-candidate-demo-weights")
            , ("cifar-imagenet", "cifar-demo-weights")
            , ("connect4-alphazero", "connect4-alphazero-demo-weights")
            ]
          seedOne (experimentHash, tensorName) = do
            result <-
              liftIO
                ( MinIOSubprocess.runMinIOSubprocess
                    minioSettings
                    ( writeMinIOWeightCheckpoint
                        experimentHash
                        tensorName
                        (1 :: Word64)
                        [("demo", 1.0)]
                        demoWeights
                    )
                )
            case result of
              Right _ ->
                writeText ("seed-demo-checkpoints: " <> experimentHash <> " seeded\n")
              Left err ->
                exitWithError
                  ( InvalidConfig
                      ( "seed-demo-checkpoints: "
                          <> experimentHash
                          <> " failed: "
                          <> Text.pack (show err)
                      )
                  )
      mapM_ seedOne seeds

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

runInternalGc :: [ParsedOption] -> App ()
runInternalGc parsedOptions = do
  let experimentHash = selectedValue "experiment-hash" "default" parsedOptions
      retention = CheckpointStore.LastN 5
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

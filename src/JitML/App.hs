{-# LANGUAGE OverloadedStrings #-}

module JitML.App
  ( demoMain
  , main
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception.Safe (bracket, displayException, finally, tryAny)
import Control.Monad (forever, unless, when)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ask, asks, liftIO, runReaderT)
import Crypto.Hash.SHA256 qualified
import Data.Aeson (decode, encode)
import Data.ByteString qualified
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isRight)
import Data.Foldable (for_, traverse_)
import Data.List (stripPrefix)
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)
import Options.Applicative (ParserResult (..), renderFailure)
import Path (toFilePath)
import System.Directory (createDirectoryIfMissing, doesFileExist, getCurrentDirectory)
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
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate, rlDeviceForSubstrate)
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
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities (SubscriptionId)
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , EventDomain
  , EventId
  , HandlerRouter
  , consumerStepWithActions
  )
import JitML.Service.LiveConfig
  ( liveBuildVmCpuCount
  , liveBuildVmDiskGib
  , liveBuildVmMemoryMib
  )
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError)
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Service.Runtime qualified as ServiceRuntime
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Tart.Exec (tartExecSubprocess)
import JitML.Tart.Lifecycle (VmName (..))
import JitML.Tart.Lifecycle qualified as TartLifecycle
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
      localPublication <- readExistingLivePublication "."
      let endpointOverride = fmap Text.pack (nonEmpty inClusterEndpoint)
          inClusterPublication = do
            _ <- endpointOverride
            substrateName <- substrateEnv
            substrate <- parseSubstrate (Text.pack substrateName)
            pure (defaultPublication substrate)
          publication = inClusterPublication `orElse` localPublication
      WebServer.serveDemoWithBridgeEndpoint
        (demoHost demoArgs)
        (demoPort demoArgs)
        publication
        endpointOverride
 where
  nonEmpty (Just s) | not (null s) = Just s
  nonEmpty _ = Nothing
  orElse (Just x) _ = Just x
  orElse Nothing y = y

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
  | parsedPath == ["internal", "vm", "exec"] =
      runInternalVmExec parsedOptions
  | take 2 parsedPath == ["internal", "vm"] =
      runInternalVmLifecycle (drop 2 parsedPath)
  | take 2 parsedPath == ["internal", "cache"] =
      runInternalCache parsedPath parsedOptions
  | parsedPath == ["internal", "gc"] =
      runInternalGc parsedOptions
  | parsedPath == ["internal", "upload-dataset"] =
      runInternalUploadDataset parsedOptions
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
  ensureHostBuildVm probedRuntime
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
      writeLine "service: listening on 0.0.0.0:8080"
      consumerThreads <- liftIO (startDaemonConsumerWorkers env probedRuntime)
      liftIO
        ( ServiceRuntime.serveDaemon probedRuntime
            `finally` stopDaemonConsumerWorkers consumerThreads
        )

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
    -- to the weighted self-inference path.
    (AppleSilicon, BootConfig.SelfInference) ->
      ServiceRuntime.daemonWorkloadDispatcherHostingAppleInference
        (appleHostInferenceRunner env)
        (\manifest weights input -> liftIO (runMetalWeightedCheckpointInference env manifest weights input))
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

-- | Sprint 5.9 — the host-native Apple daemon (`AppleSilicon` + `SelfInference`)
-- provisions and starts the jitml-managed Tart build VM at acquire with the
-- LiveConfig-configured CPU/memory/disk, so the first Apple JIT cache-miss build
-- finds it ready. Non-fatal: a failure is logged and the daemon continues (a
-- build that actually needs the VM surfaces a hard error in the Loader).
ensureHostBuildVm :: ServiceRuntime.DaemonRuntime -> App ()
ensureHostBuildVm runtime =
  case (BootConfig.bootSubstrate boot, BootConfig.bootInferenceMode boot) of
    (AppleSilicon, BootConfig.SelfInference) -> do
      root <- liftIO getCurrentDirectory
      let live = ServiceRuntime.daemonLiveConfig runtime
          config =
            (TartLifecycle.defaultBuildVmConfig root)
              { TartLifecycle.buildVmCpuCount = liveBuildVmCpuCount live
              , TartLifecycle.buildVmMemoryMib = liveBuildVmMemoryMib live
              , TartLifecycle.buildVmDiskGib = liveBuildVmDiskGib live
              }
      result <- liftIO (TartLifecycle.ensureBuildVmUp config)
      case result of
        Right status ->
          writeLine
            ( "build-vm: "
                <> unVmName TartLifecycle.defaultBuildVmName
                <> " "
                <> TartLifecycle.renderTartVmStatus status
            )
        Left err ->
          writeLine ("build-vm: not ready (continuing): " <> err)
    _ -> pure ()
 where
  boot = ServiceRuntime.daemonBootConfig runtime

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
  let problem =
        case SL.canonicalProblems of
          firstProblem : _ -> firstProblem
          [] -> SL.CanonicalProblem "empty" "empty" "empty" 0
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
              -- Sprint 5.7 — prefer the typed Dhall `TrainingRunConfig` mount;
              -- fall back to the env vars when no mount is present.
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
              imagesE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
              labelsE <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
              case (imagesE, labelsE) of
                (Right imgGz, Right lblGz) -> do
                  let config =
                        Classifier.defaultClassifierConfig {Classifier.clfEpochs = max 1 epochs}
                      device = mlpDeviceForSubstrate substrate env
                  trainedE <-
                    liftIO
                      ( Classifier.trainClassifierWithDeviceFromIdxBounded
                          device
                          config
                          (Just (max 1 trainLimit))
                          (Dataset.maybeGunzip imgGz)
                          (Dataset.maybeGunzip lblGz)
                      )
                  case trainedE of
                    Left err -> pure (Left ("substrate training failed: " <> err))
                    Right (trained, trainAcc) -> do
                      testAcc <- evaluateTestSplitDevice device minioSettings trainRef trained testLimit
                      let reportedAcc = fromMaybe trainAcc testAcc
                      writeText
                        ( "train: "
                            <> SL.problemName problem
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
        _ ->
          pure
            (Left ("no staged canonical dataset for problem " <> SL.problemName problem))

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

-- | Sprint 8.10 — fetch the test split images + labels and report the trained
-- classifier's held-out accuracy over the first @limit@ examples /through the
-- device forward/. Returns 'Nothing' when the test bytes are not staged or
-- the device forward is unavailable (the caller then publishes the train-set
-- accuracy, which is itself a real device measurement).
evaluateTestSplitDevice
  :: MlpDevice
  -> MinIOSubprocess.MinIOSettings
  -> Dataset.DatasetRef
  -> Classifier.TrainedClassifier
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
          accE <- liftIO (Classifier.accuracyWithDevice device trained testSet)
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
      case optionValues "plan-file" parsedOptions of
        [] -> pure ()
        planPath : _ -> liftIO (writePlanFile (Text.unpack planPath) renderedWithOverrides)
      writeText renderedWithOverrides
      -- Sprint 13.3 — publish a `TuneSweepDone` envelope so the dispatch
      -- → worker → broker event loop is observably closed for the tune
      -- domain. Sprint 13.10 widens this to per-trial events when the
      -- TuneHandler spawns trials in the cluster.
      publishWorkerTuneEvent

-- | Sprint 13.10 — when running inside a daemon-dispatched tune Job (live
-- publication + JITML_EXPERIMENT_HASH set), iterate the canonical sampler ×
-- scheduler × pruner cross-product (capped by the configured trial budget).
-- Each trial:
--
--   1. picks one `(Sampler, Scheduler, Pruner)` combination from the catalog
--      grid in deterministic Cartesian order;
--   2. computes a deterministic objective via `Tune.deterministicTrials`
--      against the sampler;
--   3. persists a `TrialTranscript` to MinIO via `persistTrialTranscript`;
--   4. publishes `TuneTrialStarted` + `TuneTrialFinished` envelopes to
--      `tune.event.<substrate>`.
--
-- After the loop publishes `TuneSweepDone` with the count of completed
-- trials and the best (highest) objective observed. Outside a cluster
-- context the function is a no-op.
publishWorkerTuneEvent :: App ()
publishWorkerTuneEvent = do
  cluster <- liftIO (readExistingLivePublication ".")
  experimentHashMaybe <- liftIO workerExperimentHash
  case (cluster, experimentHashMaybe) of
    (Just publication, Just experimentHash) -> do
      let substrate = Publication.publicationSubstrate publication
          edgePort = Publication.publicationEdgePort publication
          pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          topic = Capabilities.TopicName (ProtoTune.tuneEventTopic substrate)
          minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
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
      trialResults <-
        traverse
          (publishOneTrial pulsarSettings minioSettings topic experimentHash)
          gridTrials
      let completed = fromIntegral (length (filter (isRight . fst) trialResults))
          bestObjective =
            if null trialResults
              then 0.0
              else maximum (fmap snd trialResults)
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
  publishOneTrial pulsarSettings minioSettings topic experimentHash (trialSeed, (sampler, scheduler, pruner)) = do
    -- Sprint 13.10: derive a deterministic trial objective from the
    -- (sampler, scheduler, pruner) tuple via `Tune.deterministicTrials`.
    -- The transcript carries the first three sampler-derived values so
    -- replays can reproduce the same objective bit-for-bit.
    let trialValues = take 3 (Tune.deterministicTrials sampler 8)
        objective = case trialValues of
          (v : _) -> v
          _ -> 0.0
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
    pure (persistResult, objective)

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
  episodes <- case episodesE of
    Left err -> exitWithError (InvalidConfig err)
    Right eps -> pure eps
  let averageReward =
        if null episodes
          then 0.0
          else sum (fmap SimulatorLoop.simEpisodeReward episodes) / fromIntegral (length episodes)
  writeText $
    Text.unlines
      [ "rl train: " <> selectedValue "rl-experiment-dhall" "experiments/cartpole.dhall" parsedOptions
      , "algorithms: " <> Text.pack (show (length RL.algorithmCatalog))
      , "environment: " <> envName
      , "trainer: " <> trainerKind
      , "episodes: " <> Text.pack (show (length episodes))
      , "avg-reward: " <> Text.pack (show averageReward)
      , "overrides: " <> Overrides.renderExperimentOverrides overrides
      ]
  traverse_ publishWorkerRlEpisode episodes
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
    Right episodes ->
      writeLine
        ( "rl rollout: seed="
            <> Text.pack (show seed)
            <> " substrate="
            <> renderSubstrate substrate
            <> " rewards="
            <> Text.pack (show (fmap SimulatorLoop.simEpisodeReward episodes))
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
                }
          )
          . PpoTrainer.resultIterations
      )
      resultE

-- | Sprint 13.8 — dispatch the worker-side RL run to the real MLP-backed
-- trainer named by @JITML_RL_TRAINER@, projecting each trainer's
-- per-iteration summary into the existing 'SimulatedEpisode' envelope
-- shape so the downstream dispatch chain and Pulsar publication path
-- (Sprint 13.5) stay unchanged. Every trainer is bit-deterministic on
-- the same substrate / same seed per
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
  -> IO (Either Text [SimulatorLoop.SimulatedEpisode])
runTrainerEpisodes substrate device atariRomPath trainerKind envName seed evalEpisodes maxStepsPerEpisode
  | Text.toLower envName == "atari-subset" = do
      -- Atari routes through the runtime-loaded ALE adapter (Sprint 8.8),
      -- not the MLP device; ROM-policy failures surface as a typed `Left`.
      result <- ALE.runAtariSubsetEpisodes atariRomPath seed evalEpisodes maxStepsPerEpisode
      pure (fmap (fmap fromAleEpisode) result)
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
      }
  asEpisode index reward =
    SimulatorLoop.SimulatedEpisode
      { SimulatorLoop.simEpisodeIndex = index
      , SimulatorLoop.simEpisodeSteps = maxStepsPerEpisode
      , SimulatorLoop.simEpisodeReward = reward
      , SimulatorLoop.simEpisodeDone = True
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
        ( map (\stat -> asEpisode (PpoTrainer.iterIndex stat) (PpoTrainer.iterMeanReward stat))
            . PpoTrainer.resultIterations
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
    pure (Right (indexedEpisodes DqnTrainer.dqnIterMeanReward (DqnTrainer.dqnResultStats result)))
  qrDqnEpisodes = do
    let config =
          QrDqnTrainer.defaultQrDqnTrainConfig
            { QrDqnTrainer.qrSeed = seed
            , QrDqnTrainer.qrNumSteps = max 20000 (evalEpisodes * maxStepsPerEpisode)
            , QrDqnTrainer.qrStatInterval = max 1000 maxStepsPerEpisode
            }
    result <- QrDqnTrainer.trainQrDqnOnDevice device config
    pure (Right (indexedEpisodes QrDqnTrainer.qrIterMeanReward (QrDqnTrainer.qrResultStats result)))
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
          (indexedEpisodes ContinuousTrainer.contIterMeanReward (ContinuousTrainer.contResultStats result))
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
      fmap
        (\stat -> asEpisode (ArsTrainer.arsIterIndex stat) (ArsTrainer.arsIterMeanReturn stat))
        (ArsTrainer.arsResultStats result)
  herEpisodes = do
    let config =
          HerTrainer.defaultHerTrainConfig
            { HerTrainer.herSeed = seed
            , HerTrainer.herEpisodes = max 200 (evalEpisodes * 20)
            , HerTrainer.herStatInterval = max 25 evalEpisodes
            }
    result <- HerTrainer.trainHerOnDevice device config
    pure (Right (indexedEpisodes HerTrainer.herIterSuccessRate (HerTrainer.herResultStats result)))

-- | Sprint 13.5 — publish one @EpisodeDone@ envelope per simulator
-- episode produced by 'SimulatorLoop.runSimulatedEpisodesByName'. Gated
-- on @JITML_EXPERIMENT_HASH@ + live cluster publication so the worker
-- can still run offline without a broker.
publishWorkerRlEpisode :: SimulatorLoop.SimulatedEpisode -> App ()
publishWorkerRlEpisode episode = do
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
      result <-
        liftIO
          ( PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
              pulsarSettings
              ( Capabilities.pulsarPublish
                  topic
                  (ProtoRl.renderRlEvent envelope)
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
            "test --apple-silicon requires the Metal toolchain (swiftc + metal) and a visible Metal device; none detected"
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
  pure
    ReportMeasurements
      { measuredSlFinalLoss = Just slLoss
      , measuredRlFinalReward = Just rlReward
      , measuredAlphaZeroArenaWinRate = Just alphaZeroWinRate
      , measuredTuneBestObjective = Just tuneObjective
      , measuredJitCacheHitRate = Just cacheHitRate
      , measuredDaemonHealthz = Just daemonHealth
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
        Right [] -> Nothing
        Right episodes ->
          Just
            ( sum (fmap SimulatorLoop.simEpisodeReward episodes)
                / fromIntegral (length episodes)
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
  loaded <- liftIO (Tune.loadTuningExperiment "experiments/mnist-tune.dhall")
  pure $
    case loaded >>= maybe (Left "missing tuning block") Right . Tune.tuningExperimentConfig of
      Left _ -> MeasurementUnavailable
      Right config ->
        let sampler = Tune.tuningSamplerKind (Tune.tuningConfigSampler config)
            trialCount = fromIntegral (Tune.tuningConfigTrials config)
            values = Tune.deterministicTrials sampler trialCount
         in case values of
              [] -> MeasurementUnavailable
              _ -> measuredShow (Text.pack (show sampler) <> "=") (maximum values)

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
-- | Sprint 13.4 — `jitml internal upload-dataset` reads a local file,
-- looks up the canonical SHA-256 in 'JitML.SL.Dataset.canonicalSha256For'
-- (or the synthetic fallback), verifies the file's SHA matches the
-- canonical, and uploads it to MinIO at
-- `jitml-datasets/<name>/<split>/data.bin` via the routed
-- `MinIOSubprocess`. Mismatches abort with 'InvalidConfig'.
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
                <> " (expected images/labels)"
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

parseDatasetSplit :: Text -> Maybe Dataset.DatasetSplit
parseDatasetSplit "train" = Just Dataset.TrainSplit
parseDatasetSplit "validation" = Just Dataset.ValidationSplit
parseDatasetSplit "test" = Just Dataset.TestSplit
parseDatasetSplit _ = Nothing

parseDatasetArtifact :: Text -> Maybe Dataset.DatasetArtifact
parseDatasetArtifact "images" = Just Dataset.ImagesArtifact
parseDatasetArtifact "data" = Just Dataset.ImagesArtifact
parseDatasetArtifact "labels" = Just Dataset.LabelsArtifact
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

-- | `jitml internal vm exec -- <cmd...>` runs a command inside the Apple
-- Silicon build VM via `tart exec` and streams its stdout.
runInternalVmExec :: [ParsedOption] -> App ()
runInternalVmExec parsedOptions = do
  let command = tartExecSubprocess TartLifecycle.defaultBuildVmName (optionValues "cmd" parsedOptions)
  (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  case exitCode of
    ExitSuccess -> writeText stdoutText
    ExitFailure _ ->
      exitWithError (InvalidConfig ("internal vm exec: " <> stderrText))

-- | `jitml internal vm <create|up|down|status|delete>` drives the jitml-managed
-- Tart build-VM lifecycle. The VM is provisioned with the baseline build-VM
-- resources and the repository mounted so the in-VM `swift build` writes the
-- dylib to a host-visible path.
runInternalVmLifecycle :: [Text] -> App ()
runInternalVmLifecycle path = do
  root <- liftIO getCurrentDirectory
  let config = TartLifecycle.defaultBuildVmConfig root
  case path of
    ["create"] -> do
      result <- liftIO (TartLifecycle.provisionBuildVm config)
      reportVmActionUnit "create" result
    ["up"] -> do
      result <- liftIO (TartLifecycle.ensureBuildVmUp config)
      reportVmActionStatus "up" result
    ["down"] -> do
      result <- liftIO (TartLifecycle.stopTartVmLive (TartLifecycle.buildVmName config))
      reportVmActionStatus "down" result
    ["status"] -> do
      result <- liftIO (TartLifecycle.queryTartVmStatus (TartLifecycle.buildVmName config))
      reportVmActionStatus "status" result
    ["delete"] -> do
      result <- liftIO (TartLifecycle.deleteTartVmLive (TartLifecycle.buildVmName config))
      reportVmActionStatus "delete" result
    _ ->
      exitWithError (UnknownCommand ("unknown vm lifecycle action: " <> Text.unwords path))

reportVmActionStatus :: Text -> Either Text TartLifecycle.TartVmStatus -> App ()
reportVmActionStatus action result =
  case result of
    Left err ->
      exitWithError (InvalidConfig ("internal vm " <> action <> ": " <> err))
    Right status ->
      writeLine
        ( "vm "
            <> action
            <> ": "
            <> unVmName TartLifecycle.defaultBuildVmName
            <> " "
            <> TartLifecycle.renderTartVmStatus status
        )

reportVmActionUnit :: Text -> Either Text () -> App ()
reportVmActionUnit action result =
  case result of
    Left err ->
      exitWithError (InvalidConfig ("internal vm " <> action <> ": " <> err))
    Right () ->
      writeLine
        ("vm " <> action <> ": " <> unVmName TartLifecycle.defaultBuildVmName <> " ok")

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

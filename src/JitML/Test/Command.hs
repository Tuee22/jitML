{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Command
  ( TestCommandRuntime (..)
  , runTest
  )
where

import Control.Exception.Safe (bracket, displayException, tryAny)
import Control.Monad (unless, when)
import Control.Monad.Reader (ask, liftIO, runReaderT)
import Data.ByteString qualified
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Foldable (for_)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))
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
import JitML.Bootstrap (readExistingLivePublication)
import JitML.CLI.Output (exitWithError, writeLine, writeText)
import JitML.CLI.Parser (ParsedOption)
import JitML.CLI.Spec (commandPathText)
import JitML.Cluster.Publication qualified as Publication
import JitML.Engines.CudaRuntime (cudaRuntimeAvailable, probeCudaRuntime)
import JitML.Engines.MetalRuntime (metalRuntimeAvailable, probeMetalRuntime)
import JitML.Engines.OneDnnRuntime
  ( oneDnnRuntimeAvailable
  , probeOneDnnRuntime
  )
import JitML.Env.Env (App)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , processFailureExitCode
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream
  ( defaultSubprocessEnv
  , runStreaming
  , runStreamingObserved
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Test.LiveE2EScope qualified as LiveE2EScope
import JitML.Test.LivePlan
  ( LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  , scopedLiveE2EPlanFor
  )
import JitML.Test.Report
  ( ReportCard (..)
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
  , renderReportCardWithKnobs
  , reportStanzas
  , substrateRuntimeStanzas
  , substrateTestInvocations
  )
import JitML.Tune.Catalog qualified as Tune

-- | App-owned option resolution and worker measurements consumed by the test
-- command. Keeping these effects explicit lets the command/report orchestration
-- compile independently without importing "JitML.App".
data TestCommandRuntime = TestCommandRuntime
  { testCommandBootstrapSubstrates :: [ParsedOption] -> [Text]
  , testCommandHasOption :: Text -> [ParsedOption] -> Bool
  , testCommandSelectedValue :: Text -> Text -> [ParsedOption] -> Text
  , testCommandMeasureSlFinalLossText :: App (Maybe Text)
  , testCommandMeasureRlFinalRewardText :: App (Maybe Text)
  }

runTest :: TestCommandRuntime -> [Text] -> [ParsedOption] -> App ()
runTest runtime ["test", "all"] parsedOptions =
  runCabalTest runtime parsedOptions reportStanzas
runTest runtime ["test", stanza] parsedOptions
  | stanza `elem` reportStanzas =
      runCabalTest runtime parsedOptions [stanza]
  | otherwise =
      exitWithError (UnknownCommand ("unknown test stanza: " <> stanza))
runTest _runtime path _ =
  exitWithError (UnknownCommand ("unknown test command: " <> commandPathText path))
{-# NOINLINE runTest #-}

liveE2ESubstrate :: TestCommandRuntime -> [ParsedOption] -> App Substrate
liveE2ESubstrate runtime parsedOptions =
  case testCommandBootstrapSubstrates runtime parsedOptions of
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
runCabalTest :: TestCommandRuntime -> [ParsedOption] -> [Text] -> App ()
runCabalTest runtime parsedOptions targets =
  case testCommandBootstrapSubstrates runtime parsedOptions of
    []
      | testCommandHasOption runtime "live" parsedOptions -> do
          substrate <- liveE2ESubstrate runtime parsedOptions
          ensureSubstrateRuntimeFor substrate targets
          runCabalInvocations
            runtime
            parsedOptions
            targets
            (Just substrate)
            (substrateTestInvocations (Just substrate) targets userOptions)
      | otherwise ->
          runCabalInvocations
            runtime
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
            runtime
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
    case testCommandSelectedValue runtime "test-options" "" parsedOptions of
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
runCabalInvocations
  :: TestCommandRuntime
  -> [ParsedOption]
  -> [Text]
  -> Maybe Substrate
  -> [[Text]]
  -> App ()
runCabalInvocations runtime parsedOptions targets selectedTestSubstrate invocations = do
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
        if testCommandHasOption runtime "live" parsedOptions
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
    measured <-
      tryAny
        (runReaderT (collectLiveReportMeasurements runtime selectedTargets) env)
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
    prioritizeLiveCabal
      (testCommandHasOption runtime "live" parsedOptions)
      rawCommand
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
{-# NOINLINE runCabalInvocations #-}

collectLiveReportMeasurements
  :: TestCommandRuntime
  -> [Text]
  -> App ReportMeasurements
collectLiveReportMeasurements runtime targets = do
  when
    (all (`elem` targets) ["jitml-integration", "jitml-e2e"])
    ( exitWithError
        ( InvalidConfig
            "live product evidence was requested, but no opaque validated completed-scenario journal is available; Phase 28.4 must supply the cross-process journal reader"
        )
    )
  slLoss <- measureSlFinalLoss runtime
  rlReward <- measureRlFinalReward runtime
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
      , -- Sprint 19.4 deliberately leaves this empty until the report receives
        -- opaque completed-scenario values.  Suite target names and registry
        -- declarations are not execution evidence; Sprint 28.4 supplies the
        -- journal artifact reader that can populate this field across processes.
        measuredProductRowEvidence = Nothing
      }
{-# NOINLINE collectLiveReportMeasurements #-}

measureSlFinalLoss :: TestCommandRuntime -> App ReportMeasurement
measureSlFinalLoss runtime =
  maybe MeasurementUnavailable MeasurementAvailable
    <$> testCommandMeasureSlFinalLossText runtime

measureRlFinalReward :: TestCommandRuntime -> App ReportMeasurement
measureRlFinalReward runtime =
  maybe MeasurementUnavailable MeasurementAvailable
    <$> testCommandMeasureRlFinalRewardText runtime

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

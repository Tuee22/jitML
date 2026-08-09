{-# LANGUAGE OverloadedStrings #-}

module SigtermRegression
  ( threadedRtsRegression
  , sigtermDrainRegression
  , sigtermDeadlineRegression
  , sighupReloadRegression
  , webappSignalRegression
  , liveConfigFailClosedRegression
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (wait, withAsync)
import Control.Exception (SomeException, bracket, onException, try)
import Control.Monad (unless)
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString
import Data.List (isInfixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import Network.Socket
  ( AddrInfo (..)
  , SockAddr (SockAddrInet)
  , SocketType (Stream)
  , bind
  , close
  , connect
  , defaultHints
  , getAddrInfo
  , getSocketName
  , socket
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)
import System.Directory
  ( doesFileExist
  , findExecutable
  , getPermissions
  , makeAbsolute
  , setOwnerExecutable
  , setPermissions
  )
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, (@?=))

import JitML.Plan.Command qualified as PlanCommand
import JitML.Proto.Training qualified as Training
import JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , Residency (Cluster)
  , Role (Coordinator, Webapp)
  , defaultBootConfig
  , renderBootConfigDhall
  )
import JitML.Service.LiveConfig
  ( LiveConfig (..)
  , defaultLiveConfig
  , renderLiveConfigDhall
  )
import JitML.Sub.Outcome (ProcessOutcome (..), renderProcessOutcome)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (LinuxCPU))

data LifecycleFixture = LifecycleFixture
  { fixtureDirectory :: FilePath
  , fixtureConfigPath :: FilePath
  , fixtureLiveConfigPath :: FilePath
  , fixtureWrapperPath :: FilePath
  , fixtureBridgeLogPath :: FilePath
  , fixtureServiceStdoutPath :: FilePath
  , fixtureServiceStderrPath :: FilePath
  , fixtureAllowDeliveryPath :: FilePath
  , fixtureHandlerStartedPath :: FilePath
  , fixtureHandlerReleasePath :: FilePath
  , fixturePidPath :: FilePath
  , fixtureTrainingBridgePidPath :: FilePath
  , fixtureHandlerPidPath :: FilePath
  , fixturePort :: Int
  }

data DrainScenario
  = GracefulWithinDeadline
  | ForcedAtDeadline
  deriving stock (Eq)

threadedRtsRegression :: Assertion
threadedRtsRegression = do
  jitmlBinary <- requireJitmlBinary
  outcome <-
    runStreaming
      defaultSubprocessEnv
      (subprocess jitmlBinary ["+RTS", "-N1", "-RTS", "commands", "--tree"])
  assertProcessSucceeded "threaded RTS capability probe" outcome

sigtermDrainRegression :: Assertion
sigtermDrainRegression =
  withSystemTempDirectory "jitml-sigterm-drain" $ \directory -> do
    jitmlBinary <- requireJitmlBinary
    port <- reserveTcpPort
    let fixture = lifecycleFixture directory port
    writeLifecycleFixture jitmlBinary fixture GracefulWithinDeadline
    maybeRun <-
      timeout lifecycleTimeoutMicroseconds
        $ withAsync
          (runStreaming defaultSubprocessEnv (subprocess (fixtureWrapperPath fixture) []))
        $ \serviceWorker -> do
          childPid <- readChildPid (fixturePidPath fixture)
          let emergencyStop = do
                Text.IO.writeFile (fixtureHandlerReleasePath fixture) ""
                _ <- signalChild "-KILL" childPid
                pure ()
          (signalledAt, processOutcome) <-
            ( do
                waitForHttpStatus port "200 OK"
                Text.IO.writeFile (fixtureAllowDeliveryPath fixture) ""
                waitForFile "training handler to enter its in-flight dispatch" (fixtureHandlerStartedPath fixture)
                signalledAt <- getMonotonicTimeNSec
                signalOutcome <- signalChild "-TERM" childPid
                assertProcessSucceeded "SIGTERM delivery" signalOutcome
                waitForHttpStatus port "503 Service Unavailable"
                Text.IO.writeFile (fixtureHandlerReleasePath fixture) ""
                processOutcome <- wait serviceWorker
                pure (signalledAt, processOutcome)
            )
              `onException` emergencyStop
          pure (signalledAt, processOutcome)
    case maybeRun of
      Nothing -> lifecycleFailure fixture "actual jitml service did not drain before the test timeout"
      Just (signalledAt, processOutcome) -> do
        finishedAt <- getMonotonicTimeNSec
        case processOutcome of
          ProcessSucceeded _transcript -> pure ()
          ProcessFailed _failure ->
            lifecycleFailure
              fixture
              ("actual jitml service failed:\n" <> Text.unpack (renderProcessOutcome processOutcome))
        assertBool
          "SIGTERM drain exceeded the configured 30-second deadline"
          (finishedAt - signalledAt < drainDeadlineNanoseconds)
        assertLifecycleEvidence fixture

sigtermDeadlineRegression :: Assertion
sigtermDeadlineRegression =
  withSystemTempDirectory "jitml-sigterm-deadline" $ \directory -> do
    jitmlBinary <- requireJitmlBinary
    port <- reserveTcpPort
    let fixture = lifecycleFixture directory port
    writeLifecycleFixture jitmlBinary fixture ForcedAtDeadline
    maybeRun <-
      timeout lifecycleTimeoutMicroseconds
        $ withAsync
          (runStreaming defaultSubprocessEnv (subprocess (fixtureWrapperPath fixture) []))
        $ \serviceWorker -> do
          childPid <- readChildPid (fixturePidPath fixture)
          let emergencyStop = do
                Text.IO.writeFile (fixtureHandlerReleasePath fixture) ""
                _ <- signalChild "-KILL" childPid
                pure ()
          (signalledAt, bridgePid, handlerPid, processOutcome) <-
            ( do
                waitForHttpStatus port "200 OK"
                Text.IO.writeFile (fixtureAllowDeliveryPath fixture) ""
                waitForFile "training handler to enter its in-flight dispatch" (fixtureHandlerStartedPath fixture)
                bridgePid <- readPlainPid "training bridge pid" (fixtureTrainingBridgePidPath fixture)
                handlerPid <- readPlainPid "stuck handler pid" (fixtureHandlerPidPath fixture)
                signalledAt <- getMonotonicTimeNSec
                signalOutcome <- signalChild "-TERM" childPid
                assertProcessSucceeded "SIGTERM delivery" signalOutcome
                waitForHttpStatus port "503 Service Unavailable"
                processOutcome <- wait serviceWorker
                pure (signalledAt, bridgePid, handlerPid, processOutcome)
            )
              `onException` emergencyStop
          pure (signalledAt, childPid, bridgePid, handlerPid, processOutcome)
    case maybeRun of
      Nothing ->
        lifecycleFailure fixture "actual jitml service did not force cleanup after its configured deadline"
      Just (signalledAt, childPid, bridgePid, handlerPid, processOutcome) -> do
        finishedAt <- getMonotonicTimeNSec
        case processOutcome of
          ProcessSucceeded _transcript -> pure ()
          ProcessFailed _failure ->
            lifecycleFailure
              fixture
              ( "actual jitml service failed during forced drain:\n"
                  <> Text.unpack (renderProcessOutcome processOutcome)
              )
        let elapsed = finishedAt - signalledAt
        assertBool
          "forced cancellation happened before the configured one-second grace deadline"
          (elapsed >= minimumDeadlineNanoseconds)
        assertBool
          "forced cleanup did not join within the bounded post-cancel window"
          (elapsed < forcedDrainUpperBoundNanoseconds)
        assertDeadlineLifecycleEvidence fixture
        assertProcessExited "jitml service" childPid
        assertProcessExited "training bridge" bridgePid
        assertProcessExited "stuck kubectl handler" handlerPid

sighupReloadRegression :: Assertion
sighupReloadRegression =
  withSystemTempDirectory "jitml-sighup-reload" $ \directory -> do
    jitmlBinary <- requireJitmlBinary
    port <- reserveTcpPort
    let fixture = lifecycleFixture directory port
        changedLiveConfig =
          defaultLiveConfig
            { liveDedupCacheSize = reloadDedupCacheSize
            , liveDedupCacheTtlSeconds = reloadDedupCacheTtlSeconds
            , liveDrainDeadlineSeconds = reloadDrainDeadlineSeconds
            }
        changedBootConfig =
          (lifecycleBootConfig fixture)
            { bootHarborRegistry = "restart-required.invalid/library"
            }
    -- The bridge fixture expects the final restart-required drain to force a
    -- stuck delivery. Start from the default deadline, then prove the SIGHUP
    -- update to one second governs that final drain.
    writeLifecycleFixture jitmlBinary fixture ForcedAtDeadline
    writeLiveConfigFixture fixture defaultLiveConfig
    maybeRun <-
      timeout lifecycleTimeoutMicroseconds
        $ withAsync
          (runStreaming defaultSubprocessEnv (subprocess (fixtureWrapperPath fixture) []))
        $ \serviceWorker -> do
          childPid <- readChildPid (fixturePidPath fixture)
          let emergencyStop = do
                Text.IO.writeFile (fixtureHandlerReleasePath fixture) ""
                _ <- signalChild "-KILL" childPid
                pure ()
          (restartRequestedAt, bridgePid, handlerPid, processOutcome) <-
            ( do
                waitForHttpStatus port "200 OK"

                unchangedSignal <- signalChild "-HUP" childPid
                assertProcessSucceeded "unchanged LiveConfig SIGHUP delivery" unchangedSignal
                waitForServiceLog
                  fixture
                  "unchanged LiveConfig reload decision"
                  unchangedReloadEvidence
                waitForHttpStatus port "200 OK"
                assertAppliedReloadCount fixture 0

                writeLiveConfigFixture fixture changedLiveConfig
                changedSignal <- signalChild "-HUP" childPid
                assertProcessSucceeded "changed LiveConfig SIGHUP delivery" changedSignal
                waitForServiceLog fixture "applied LiveConfig reload" appliedReloadEvidence
                waitForServiceLog fixture "active reloaded LiveConfig values" activeReloadConfigEvidence
                waitForHttpStatus port "200 OK"
                assertAppliedReloadCount fixture 1

                writeMalformedLiveConfigFixture fixture
                malformedSignal <- signalChild "-HUP" childPid
                assertProcessSucceeded "malformed LiveConfig SIGHUP delivery" malformedSignal
                waitForServiceLog
                  fixture
                  "malformed LiveConfig last-good decision"
                  malformedReloadEvidence
                waitForHttpStatus port "200 OK"
                assertAppliedReloadCount fixture 1

                -- Restore the last-good LiveConfig on disk so the following
                -- SIGHUP isolates the immutable BootConfig change.
                writeLiveConfigFixture fixture changedLiveConfig
                Text.IO.writeFile (fixtureAllowDeliveryPath fixture) ""
                waitForFile
                  "training handler to enter its restart-required in-flight dispatch"
                  (fixtureHandlerStartedPath fixture)
                bridgePid <- readPlainPid "training bridge pid" (fixtureTrainingBridgePidPath fixture)
                handlerPid <- readPlainPid "stuck handler pid" (fixtureHandlerPidPath fixture)
                Text.IO.writeFile
                  (fixtureConfigPath fixture)
                  (renderBootConfigDhall changedBootConfig)
                threadDelay fixtureWriteSettleMicroseconds
                restartRequestedAt <- getMonotonicTimeNSec
                restartSignal <- signalChild "-HUP" childPid
                assertProcessSucceeded "changed BootConfig SIGHUP delivery" restartSignal
                waitForServiceLog
                  fixture
                  "BootConfig restart-required reload decision"
                  restartRequiredEvidence
                waitForHttpStatus port "503 Service Unavailable"
                processOutcome <- wait serviceWorker
                pure (restartRequestedAt, bridgePid, handlerPid, processOutcome)
            )
              `onException` emergencyStop
          pure (restartRequestedAt, childPid, bridgePid, handlerPid, processOutcome)
    case maybeRun of
      Nothing -> lifecycleFailure fixture "actual jitml service did not finish its SIGHUP regression"
      Just (restartRequestedAt, childPid, bridgePid, handlerPid, processOutcome) -> do
        finishedAt <- getMonotonicTimeNSec
        case processOutcome of
          ProcessSucceeded _transcript ->
            lifecycleFailure fixture "restart-required BootConfig change exited successfully"
          ProcessFailed _failure -> pure ()
        let elapsed = finishedAt - restartRequestedAt
        assertBool
          "restart-required drain ignored the hot-reloaded one-second deadline"
          (elapsed >= minimumDeadlineNanoseconds)
        assertBool
          "restart-required forced cleanup did not join within the bounded window"
          (elapsed < forcedDrainUpperBoundNanoseconds)
        assertSighupReloadEvidence fixture
        assertReloadDeadlineLifecycleEvidence fixture
        assertProcessExited "jitml service" childPid
        assertProcessExited "training bridge" bridgePid
        assertProcessExited "stuck kubectl handler" handlerPid

webappSignalRegression :: Assertion
webappSignalRegression =
  withSystemTempDirectory "jitml-webapp-signals" $ \directory -> do
    jitmlBinary <- requireJitmlBinary
    port <- reserveTcpPort
    let fixture = lifecycleFixture directory port
        initialLiveConfig =
          defaultLiveConfig
            { liveDedupCacheSize = 31
            , liveDedupCacheTtlSeconds = 37
            , liveDrainDeadlineSeconds = 2
            }
        changedLiveConfig =
          initialLiveConfig
            { liveDedupCacheSize = reloadDedupCacheSize
            , liveDedupCacheTtlSeconds = reloadDedupCacheTtlSeconds
            , liveDrainDeadlineSeconds = reloadDrainDeadlineSeconds
            }
    writeWebappLifecycleFixture jitmlBinary fixture initialLiveConfig
    maybeRun <-
      timeout lifecycleTimeoutMicroseconds
        $ withAsync
          (runStreaming defaultSubprocessEnv (subprocess (fixtureWrapperPath fixture) []))
        $ \serviceWorker -> do
          childPid <- readChildPid (fixturePidPath fixture)
          let emergencyStop = do
                _ <- signalChild "-KILL" childPid
                pure ()
          processOutcome <-
            ( do
                waitForHttpStatusAt port "/" "200 OK"
                waitForServiceLog
                  fixture
                  "Webapp serving announcement"
                  ("webapp: serving 127.0.0.1:" <> Text.pack (show port))

                unchangedSignal <- signalChild "-HUP" childPid
                assertProcessSucceeded "Webapp unchanged LiveConfig SIGHUP delivery" unchangedSignal
                waitForServiceLog
                  fixture
                  "Webapp unchanged LiveConfig reload decision"
                  unchangedReloadEvidence
                waitForHttpStatusAt port "/" "200 OK"
                assertAppliedReloadCount fixture 0
                assertProcessRunning "Webapp after unchanged reload" childPid

                writeLiveConfigFixture fixture changedLiveConfig
                changedSignal <- signalChild "-HUP" childPid
                assertProcessSucceeded "Webapp changed LiveConfig SIGHUP delivery" changedSignal
                waitForServiceLog fixture "Webapp applied LiveConfig reload" appliedReloadEvidence
                waitForServiceLog
                  fixture
                  "Webapp active reloaded LiveConfig values"
                  activeReloadConfigEvidence
                waitForHttpStatusAt port "/" "200 OK"
                assertAppliedReloadCount fixture 1
                assertProcessRunning "Webapp after changed reload" childPid

                termSignal <- signalChild "-TERM" childPid
                assertProcessSucceeded "Webapp SIGTERM delivery" termSignal
                wait serviceWorker
            )
              `onException` emergencyStop
          pure (childPid, processOutcome)
    case maybeRun of
      Nothing -> lifecycleFailure fixture "actual Webapp service did not finish its signal regression"
      Just (childPid, processOutcome) -> do
        case processOutcome of
          ProcessSucceeded _transcript -> pure ()
          ProcessFailed _failure ->
            lifecycleFailure
              fixture
              ( "actual Webapp service failed during signal handling:\n"
                  <> Text.unpack (renderProcessOutcome processOutcome)
              )
        assertWebappReloadEvidence fixture
        assertProcessExited "Webapp service" childPid

liveConfigFailClosedRegression :: Assertion
liveConfigFailClosedRegression =
  withSystemTempDirectory "jitml-live-config-fail-closed" $ \directory -> do
    jitmlBinary <- requireJitmlBinary
    let bootConfigPath = directory </> "BootConfig.dhall"
        liveConfigPath = directory </> "LiveConfig.dhall"
        bootConfig = defaultBootConfig LinuxCPU Cluster
        runService =
          runStreaming
            defaultSubprocessEnv
            (subprocess jitmlBinary ["service", "--config", Text.pack bootConfigPath])
        runBounded label = do
          maybeOutcome <- timeout conditionTimeoutMicroseconds runService
          case maybeOutcome of
            Nothing -> ioError (userError (label <> " did not fail before service startup"))
            Just outcome -> pure outcome
    Text.IO.writeFile bootConfigPath (renderBootConfigDhall bootConfig)
    missingOutcome <- runBounded "missing adjacent LiveConfig.dhall"
    assertProcessFailedContaining
      "missing adjacent LiveConfig.dhall"
      "service live config does not exist"
      missingOutcome
    Text.IO.writeFile liveConfigPath "{ malformed ="
    malformedOutcome <- runBounded "malformed adjacent LiveConfig.dhall"
    assertProcessFailedContaining
      "malformed adjacent LiveConfig.dhall"
      "failed to load service live config"
      malformedOutcome

lifecycleFixture :: FilePath -> Int -> LifecycleFixture
lifecycleFixture directory port =
  LifecycleFixture
    { fixtureDirectory = directory
    , fixtureConfigPath = directory </> "BootConfig.dhall"
    , fixtureLiveConfigPath = directory </> "LiveConfig.dhall"
    , fixtureWrapperPath = directory </> "run-jitml-service"
    , fixtureBridgeLogPath = directory </> "bridge.log"
    , fixtureServiceStdoutPath = directory </> "service.stdout"
    , fixtureServiceStderrPath = directory </> "service.stderr"
    , fixtureAllowDeliveryPath = directory </> "allow-delivery"
    , fixtureHandlerStartedPath = directory </> "handler-started"
    , fixtureHandlerReleasePath = directory </> "handler-release"
    , fixturePidPath = directory </> "service.pid"
    , fixtureTrainingBridgePidPath = directory </> "training-bridge.pid"
    , fixtureHandlerPidPath = directory </> "handler.pid"
    , fixturePort = port
    }

writeLifecycleFixture :: FilePath -> LifecycleFixture -> DrainScenario -> IO ()
writeLifecycleFixture jitmlBinary fixture scenario = do
  let bootConfig = lifecycleBootConfig fixture
      liveConfig =
        defaultLiveConfig
          { liveDrainDeadlineSeconds =
              case scenario of
                GracefulWithinDeadline -> liveDrainDeadlineSeconds defaultLiveConfig
                ForcedAtDeadline -> 1
          }
      trainingPayload =
        Training.renderTrainingCommand
          ( Training.TrainingStart
              ( preparedStartTraining
                  Training.StartTraining
                    { Training.stExperimentHash = "sigterm-in-flight"
                    , Training.stDhallObjectKey = "experiments/synthetic.dhall"
                    , Training.stSubstrate = LinuxCPU
                    , Training.stSeed = 17
                    , Training.stEpochs = 2
                    , Training.stBatchSize = 8
                    , Training.stPlanId = ""
                    , Training.stResolvedPlan = ""
                    , Training.stTrainingExamples = 64
                    , Training.stEvaluationExamples = 16
                    }
              )
          )
  Text.IO.writeFile (fixtureConfigPath fixture) (renderBootConfigDhall bootConfig)
  Text.IO.writeFile (fixtureLiveConfigPath fixture) (renderLiveConfigDhall liveConfig)
  writeExecutable
    (fixtureDirectory fixture </> "node")
    (fakeNodeScript fixture scenario trainingPayload)
  writeExecutable (fixtureDirectory fixture </> "curl") fakeCurlScript
  writeExecutable (fixtureDirectory fixture </> "kubectl") (fakeKubectlScript fixture)
  writeExecutable (fixtureWrapperPath fixture) (serviceWrapperScript jitmlBinary fixture)
  -- Overlay-backed test workspaces can retain a short write lease after close.
  threadDelay 50000

preparedStartTraining :: Training.StartTraining -> Training.StartTraining
preparedStartTraining raw =
  case PlanCommand.prepareStartTraining raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartTraining test fixture: " <> Text.unpack message)

lifecycleBootConfig :: LifecycleFixture -> BootConfig
lifecycleBootConfig fixture =
  (defaultBootConfig LinuxCPU Cluster)
    { bootActiveRole = Coordinator
    , bootPulsarServiceUrl = "pulsar://lifecycle.invalid:6650"
    , bootPulsarAdminUrl = "http://lifecycle.invalid:8080"
    , bootMinioEndpoint = "http://lifecycle.invalid:9000"
    , bootHarborRegistry = "lifecycle.invalid/library"
    , bootHttpListener =
        Just
          HttpListener
            { listenerHost = "127.0.0.1"
            , listenerPort = fixturePort fixture
            }
    }

webappBootConfig :: LifecycleFixture -> BootConfig
webappBootConfig fixture =
  (defaultBootConfig LinuxCPU Cluster)
    { bootActiveRole = Webapp
    , bootPulsarServiceUrl = "pulsar://webapp.invalid:6650"
    , bootPulsarAdminUrl = "http://webapp.invalid:8080"
    , bootMinioEndpoint = "http://webapp.invalid:9000"
    , bootHarborRegistry = "webapp.invalid/library"
    , bootHttpListener =
        Just
          HttpListener
            { listenerHost = "127.0.0.1"
            , listenerPort = fixturePort fixture
            }
    , bootWebappPulsarWsUrl = Just "ws://webapp.invalid:8080"
    }

writeWebappLifecycleFixture :: FilePath -> LifecycleFixture -> LiveConfig -> IO ()
writeWebappLifecycleFixture jitmlBinary fixture liveConfig = do
  Text.IO.writeFile
    (fixtureConfigPath fixture)
    (renderBootConfigDhall (webappBootConfig fixture))
  Text.IO.writeFile (fixtureLiveConfigPath fixture) (renderLiveConfigDhall liveConfig)
  writeExecutable (fixtureWrapperPath fixture) (serviceWrapperScript jitmlBinary fixture)
  threadDelay fixtureWriteSettleMicroseconds

writeLiveConfigFixture :: LifecycleFixture -> LiveConfig -> IO ()
writeLiveConfigFixture fixture liveConfig = do
  Text.IO.writeFile (fixtureLiveConfigPath fixture) (renderLiveConfigDhall liveConfig)
  threadDelay fixtureWriteSettleMicroseconds

writeMalformedLiveConfigFixture :: LifecycleFixture -> IO ()
writeMalformedLiveConfigFixture fixture = do
  Text.IO.writeFile (fixtureLiveConfigPath fixture) "{ malformed ="
  threadDelay fixtureWriteSettleMicroseconds

serviceWrapperScript :: FilePath -> LifecycleFixture -> Text
serviceWrapperScript jitmlBinary fixture =
  Text.unlines
    [ "#!/bin/sh"
    , "set -u"
    , "PATH=" <> shellQuote (fixtureDirectory fixture) <> ":$PATH"
    , "export PATH"
    , shellQuote jitmlBinary
        <> " service --config "
        <> shellQuote (fixtureConfigPath fixture)
        <> " >"
        <> shellQuote (fixtureServiceStdoutPath fixture)
        <> " 2>"
        <> shellQuote (fixtureServiceStderrPath fixture)
        <> " &"
    , "child=$!"
    , "cleanup() {"
    , "  kill -KILL \"$child\" 2>/dev/null || true"
    , "  wait \"$child\" 2>/dev/null || true"
    , "}"
    , "trap cleanup EXIT HUP INT TERM"
    , "printf 'pid:%s\\n' \"$child\" > " <> shellQuote (fixturePidPath fixture)
    , "wait \"$child\""
    , "status=$?"
    , "trap - EXIT HUP INT TERM"
    , "exit \"$status\""
    ]

fakeNodeScript :: LifecycleFixture -> DrainScenario -> Text -> Text
fakeNodeScript fixture scenario payload =
  Text.unlines
    [ "#!/bin/sh"
    , "set -eu"
    , "endpoint=''"
    , "for argument in \"$@\"; do endpoint=$argument; done"
    , "case \"$endpoint\" in"
    , "  *training.command.linux-cpu*) topic=training ;;"
    , "  *tune.command.linux-cpu*) topic=tune ;;"
    , "  *rl.command.linux-cpu*) topic=rl ;;"
    , "  *inference.request.linux-cpu*) topic=inference ;;"
    , "  *) echo 'unknown lifecycle topic' >&2; exit 40 ;;"
    , "esac"
    , "cleanup() { printf '%s\\n' \"cleanup:$topic\" >> "
        <> shellQuote (fixtureBridgeLogPath fixture)
        <> "; }"
    , "trap cleanup EXIT"
    , emitJson "{\"version\":1,\"type\":\"connected\",\"generation\":1}"
    , "printf '%s\\n' \"connected:$topic\" >> " <> shellQuote (fixtureBridgeLogPath fixture)
    , "if [ \"$topic\" = training ]; then"
    , "  printf '%s\\n' \"$$\" > " <> shellQuote (fixtureTrainingBridgePidPath fixture)
    , "  while [ ! -f " <> shellQuote (fixtureAllowDeliveryPath fixture) <> " ]; do sleep 0.01; done"
    , "  " <> emitJson (deliveryFrame payload)
    , "  printf '%s\\n' 'delivery:training' >> " <> shellQuote (fixtureBridgeLogPath fixture)
    , "  IFS= read -r settlement"
    , "  case \"$settlement\" in *'\"type\":\"settle\"'*) ;; *) exit 41 ;; esac"
    , expectedSettlementCommand scenario
    , "  IFS= read -r drain"
    , "  case \"$drain\" in *'\"type\":\"drain\"'*) ;; *) exit 43 ;; esac"
    , "  printf '%s\\n' "
        <> shellQuoteText (settlementLogLine scenario)
        <> " >> "
        <> shellQuote (fixtureBridgeLogPath fixture)
    , "  " <> emitJson (settledFrame scenario)
    , "  " <> emitJson "{\"version\":1,\"type\":\"drained\"}"
    , "else"
    , "  while IFS= read -r command; do"
    , "    printf '%s\\n' \"unexpected:$topic:$command\" >> " <> shellQuote (fixtureBridgeLogPath fixture)
    , "  done"
    , "fi"
    ]

expectedSettlementCommand :: DrainScenario -> Text
expectedSettlementCommand scenario =
  case scenario of
    GracefulWithinDeadline ->
      "  case \"$settlement\" in *'\"type\":\"ack\"'*) ;; *) exit 42 ;; esac"
    ForcedAtDeadline ->
      Text.unlines
        [ "  case \"$settlement\" in *'\"type\":\"nack\"'*) ;; *) exit 42 ;; esac"
        , "  case \"$settlement\" in *'\"reason\":\"drain-requested\"'*) ;; *) exit 44 ;; esac"
        ]

settlementLogLine :: DrainScenario -> Text
settlementLogLine scenario =
  case scenario of
    GracefulWithinDeadline -> "settlement:training:ack"
    ForcedAtDeadline -> "settlement:training:nack:drain-requested"

fakeCurlScript :: Text
fakeCurlScript =
  Text.unlines
    [ "#!/bin/sh"
    , "set -eu"
    , "output=''"
    , "url=''"
    , "while [ \"$#\" -gt 0 ]; do"
    , "  case \"$1\" in"
    , "    --output) shift; output=$1 ;;"
    , "    http://*|https://*) url=$1 ;;"
    , "  esac"
    , "  shift"
    , "done"
    , "case \"$url\" in"
    , "  *'/repositories?page_size='*) printf '%s' '[]' ;;"
    , "  *)"
    , "    if [ -n \"$output\" ]; then printf '%s' "
        <> "'<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
        <> "<Name>jitml-checkpoints</Name>"
        <> "<Prefix>daemon-health/</Prefix><KeyCount>0</KeyCount>"
        <> "<MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>"
        <> "</ListBucketResult>' > \"$output\"; fi"
    , "    printf '%s' '200'"
    , "    ;;"
    , "esac"
    ]

fakeKubectlScript :: LifecycleFixture -> Text
fakeKubectlScript fixture =
  Text.unlines
    [ "#!/bin/sh"
    , "set -eu"
    , "case \" $* \" in"
    , "  *' apply '*)"
    , "    cat >/dev/null"
    , "    printf '%s\\n' \"$$\" > " <> shellQuote (fixtureHandlerPidPath fixture)
    , "    cancel_handler() { printf '%s\\n' 'handler:cancel' >> "
        <> shellQuote (fixtureBridgeLogPath fixture)
        <> "; exit 143; }"
    , "    trap cancel_handler TERM INT"
    , "    printf '%s\\n' 'handler:start' >> " <> shellQuote (fixtureBridgeLogPath fixture)
    , "    touch " <> shellQuote (fixtureHandlerStartedPath fixture)
    , "    while [ ! -f " <> shellQuote (fixtureHandlerReleasePath fixture) <> " ]; do sleep 0.01; done"
    , "    printf '%s\\n' 'handler:finish' >> " <> shellQuote (fixtureBridgeLogPath fixture)
    , "    printf '%s\\n' 'job.batch/sigterm-in-flight configured'"
    , "    ;;"
    , "  *) printf '%s\\n' 'items: []' ;;"
    , "esac"
    ]

deliveryFrame :: Text -> Text
deliveryFrame payload =
  "{\"version\":1,\"type\":\"delivery\",\"receipt\":"
    <> receiptJson
    <> ",\"payloadBase64\":\""
    <> Text.Encoding.decodeUtf8 (Base64.encode (Text.Encoding.encodeUtf8 payload))
    <> "\",\"redeliveryCount\":0}"

settledFrame :: DrainScenario -> Text
settledFrame scenario =
  "{\"version\":1,\"type\":\"settled\",\"receipt\":"
    <> receiptJson
    <> ",\"settlement\":\""
    <> settlementKindText scenario
    <> "\"}"

settlementKindText :: DrainScenario -> Text
settlementKindText scenario =
  case scenario of
    GracefulWithinDeadline -> "ack"
    ForcedAtDeadline -> "nack"

receiptJson :: Text
receiptJson =
  "{\"session\":\"sigterm-session\",\"generation\":1,\"deliveryId\":\"delivery-1\"}"

emitJson :: Text -> Text
emitJson json =
  "printf '%s\\n' " <> shellQuoteText json

writeExecutable :: FilePath -> Text -> IO ()
writeExecutable path contents = do
  Text.IO.writeFile path contents
  permissions <- getPermissions path
  setPermissions path (setOwnerExecutable True permissions)

requireJitmlBinary :: IO FilePath
requireJitmlBinary = do
  maybeBinary <- findExecutable "jitml"
  case maybeBinary of
    Nothing -> ioError (userError "Cabal did not expose the jitml build tool to daemon-lifecycle tests")
    Just binary -> makeAbsolute binary

readChildPid :: FilePath -> IO Text
readChildPid path = do
  waitForFile "service wrapper child pid" path
  line <- Text.IO.readFile path
  case Text.stripPrefix "pid:" (Text.strip line) of
    Just pid
      | not (Text.null pid) && Text.all (`elem` ['0' .. '9']) pid -> pure pid
    _ -> ioError (userError "service wrapper did not report its child pid")

readPlainPid :: String -> FilePath -> IO Text
readPlainPid label path = do
  waitForFile label path
  pid <- Text.strip <$> Text.IO.readFile path
  if not (Text.null pid) && Text.all (`elem` ['0' .. '9']) pid
    then pure pid
    else ioError (userError (label <> " was not a process id"))

signalChild :: Text -> Text -> IO ProcessOutcome
signalChild signal childPid =
  runStreaming defaultSubprocessEnv (subprocess "/bin/kill" [signal, childPid])

assertProcessSucceeded :: String -> ProcessOutcome -> Assertion
assertProcessSucceeded _label (ProcessSucceeded _transcript) = pure ()
assertProcessSucceeded label outcome =
  assertFailure (label <> " failed:\n" <> Text.unpack (renderProcessOutcome outcome))

assertProcessFailedContaining :: String -> Text -> ProcessOutcome -> Assertion
assertProcessFailedContaining label expected outcome =
  case outcome of
    ProcessSucceeded _transcript ->
      assertFailure (label <> " unexpectedly started the service")
    ProcessFailed _failure ->
      assertBool
        (label <> " did not report the typed configuration error:\n" <> Text.unpack rendered)
        (expected `Text.isInfixOf` rendered)
 where
  rendered = renderProcessOutcome outcome

assertProcessExited :: String -> Text -> Assertion
assertProcessExited label processId = do
  outcome <- signalChild "-0" processId
  case outcome of
    ProcessFailed _failure -> pure ()
    ProcessSucceeded _transcript ->
      assertFailure
        (label <> " remained alive after service shutdown (pid " <> Text.unpack processId <> ")")

assertProcessRunning :: String -> Text -> Assertion
assertProcessRunning label processId = do
  outcome <- signalChild "-0" processId
  case outcome of
    ProcessSucceeded _transcript -> pure ()
    ProcessFailed _failure ->
      assertFailure (label <> " was not alive (pid " <> Text.unpack processId <> ")")

waitForHttpStatus :: Int -> String -> IO ()
waitForHttpStatus port =
  waitForHttpStatusAt port "/readyz"

waitForHttpStatusAt :: Int -> String -> String -> IO ()
waitForHttpStatusAt port path expectedStatus =
  waitForCondition ("HTTP status " <> expectedStatus) $ do
    response <- try (httpGet port path) :: IO (Either SomeException String)
    pure (either (const False) (isInfixOf ("HTTP/1.1 " <> expectedStatus)) response)

waitForFile :: String -> FilePath -> IO ()
waitForFile label path =
  waitForCondition label (doesFileExist path)

waitForServiceLog :: LifecycleFixture -> String -> Text -> IO ()
waitForServiceLog fixture label expected =
  waitForCondition label $ do
    serviceStdout <- readIfPresent (fixtureServiceStdoutPath fixture)
    pure (expected `Text.isInfixOf` serviceStdout)

assertAppliedReloadCount :: LifecycleFixture -> Int -> Assertion
assertAppliedReloadCount fixture expectedCount = do
  serviceStdout <- readIfPresent (fixtureServiceStdoutPath fixture)
  countOccurrences "reload: applied; generation=" serviceStdout @?= expectedCount

waitForCondition :: String -> IO Bool -> IO ()
waitForCondition label condition = do
  result <- timeout conditionTimeoutMicroseconds loop
  unless (result == Just ()) (ioError (userError ("timed out waiting for " <> label)))
 where
  loop = do
    satisfied <- condition
    if satisfied
      then pure ()
      else threadDelay conditionPollMicroseconds >> loop

httpGet :: Int -> String -> IO String
httpGet port path =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> ioError (userError "no address for lifecycle HTTP client")
      addr : _ ->
        bracket
          (socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr))
          close
          ( \client -> do
              connect client (addrAddress addr)
              sendAll client (ByteString.pack ("GET " <> path <> " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"))
              ByteString.unpack <$> recv client 4096
          )

reserveTcpPort :: IO Int
reserveTcpPort =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just "0")
    case addresses of
      [] -> ioError (userError "no address for lifecycle port reservation")
      addr : _ ->
        bracket
          (socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr))
          close
          ( \reservation -> do
              bind reservation (addrAddress addr)
              socketAddress <- getSocketName reservation
              case socketAddress of
                SockAddrInet port _host -> pure (fromIntegral port)
                _ -> ioError (userError "lifecycle test requires an IPv4 listener")
          )

assertLifecycleEvidence :: LifecycleFixture -> Assertion
assertLifecycleEvidence fixture = do
  bridgeLog <- Text.lines <$> Text.IO.readFile (fixtureBridgeLogPath fixture)
  serviceStderr <- Text.IO.readFile (fixtureServiceStderrPath fixture)
  countLine "one training delivery" "delivery:training" bridgeLog @?= 1
  countLine "one handler entry" "handler:start" bridgeLog @?= 1
  countLine "one handler completion" "handler:finish" bridgeLog @?= 1
  countLine "one receipt settlement" "settlement:training:ack" bridgeLog @?= 1
  countPrefix "three Coordinator consumer connections" "connected:" bridgeLog @?= 3
  countPrefix "three Coordinator bridge cleanups" "cleanup:" bridgeLog @?= 3
  countOccurrences "\"msg\":\"dispatched training " serviceStderr @?= 1
  assertBool
    ("in-flight completion/settlement order was lost: " <> show bridgeLog)
    ( orderedSubsequence
        [ "handler:start"
        , "handler:finish"
        , "settlement:training:ack"
        , "cleanup:training"
        ]
        bridgeLog
    )

assertDeadlineLifecycleEvidence :: LifecycleFixture -> Assertion
assertDeadlineLifecycleEvidence fixture = do
  bridgeLog <- Text.lines <$> Text.IO.readFile (fixtureBridgeLogPath fixture)
  countLine "one training delivery" "delivery:training" bridgeLog @?= 1
  countLine "one handler entry" "handler:start" bridgeLog @?= 1
  countLine "one forced handler cancellation" "handler:cancel" bridgeLog @?= 1
  countLine "no normal handler completion" "handler:finish" bridgeLog @?= 0
  countLine
    "one drain-requested receipt settlement"
    "settlement:training:nack:drain-requested"
    bridgeLog
    @?= 1
  countPrefix "three Coordinator consumer connections" "connected:" bridgeLog @?= 3
  countPrefix "three Coordinator bridge cleanups" "cleanup:" bridgeLog @?= 3
  assertBool
    ("forced cancellation/settlement/cleanup order was lost: " <> show bridgeLog)
    ( orderedSubsequence
        [ "handler:start"
        , "handler:cancel"
        , "settlement:training:nack:drain-requested"
        , "cleanup:training"
        ]
        bridgeLog
    )

assertReloadDeadlineLifecycleEvidence :: LifecycleFixture -> Assertion
assertReloadDeadlineLifecycleEvidence fixture = do
  bridgeLog <- Text.lines <$> Text.IO.readFile (fixtureBridgeLogPath fixture)
  let connectionCount = countPrefix "consumer connections" "connected:" bridgeLog
      cleanupCount = countPrefix "bridge cleanups" "cleanup:" bridgeLog
  countLine "one training delivery" "delivery:training" bridgeLog @?= 1
  countLine "one handler entry" "handler:start" bridgeLog @?= 1
  countLine "one forced handler cancellation" "handler:cancel" bridgeLog @?= 1
  countLine "no normal handler completion" "handler:finish" bridgeLog @?= 0
  countLine
    "one drain-requested receipt settlement"
    "settlement:training:nack:drain-requested"
    bridgeLog
    @?= 1
  assertBool
    "fewer than three Coordinator consumer connections were established"
    (connectionCount >= 3)
  cleanupCount @?= connectionCount
  assertBool
    ("reload drain cancellation/settlement/cleanup order was lost: " <> show bridgeLog)
    ( orderedSubsequence
        [ "handler:start"
        , "handler:cancel"
        , "settlement:training:nack:drain-requested"
        , "cleanup:training"
        ]
        bridgeLog
    )

assertSighupReloadEvidence :: LifecycleFixture -> Assertion
assertSighupReloadEvidence fixture = do
  serviceStdout <- Text.IO.readFile (fixtureServiceStdoutPath fixture)
  let serviceLines = Text.lines serviceStdout
  countOccurrences unchangedReloadEvidence serviceStdout @?= 1
  countOccurrences appliedReloadEvidence serviceStdout @?= 1
  countOccurrences activeReloadConfigEvidence serviceStdout @?= 1
  countOccurrences malformedReloadEvidence serviceStdout @?= 1
  countOccurrences restartRequiredEvidence serviceStdout @?= 1
  countOccurrences "reload: applied; generation=" serviceStdout @?= 1
  countOccurrences "generation=2" serviceStdout @?= 0
  assertBool
    ("SIGHUP reload decision order was lost: " <> show serviceLines)
    ( orderedTextSubstrings
        [ unchangedReloadEvidence
        , appliedReloadEvidence
        , activeReloadConfigEvidence
        , malformedReloadEvidence
        , restartRequiredEvidence
        ]
        serviceLines
    )

assertWebappReloadEvidence :: LifecycleFixture -> Assertion
assertWebappReloadEvidence fixture = do
  serviceStdout <- Text.IO.readFile (fixtureServiceStdoutPath fixture)
  let serviceLines = Text.lines serviceStdout
  countOccurrences unchangedReloadEvidence serviceStdout @?= 1
  countOccurrences appliedReloadEvidence serviceStdout @?= 1
  countOccurrences activeReloadConfigEvidence serviceStdout @?= 1
  countOccurrences "reload: applied; generation=" serviceStdout @?= 1
  countOccurrences "generation=2" serviceStdout @?= 0
  assertBool
    ("Webapp SIGHUP reload decision order was lost: " <> show serviceLines)
    ( orderedTextSubstrings
        [ unchangedReloadEvidence
        , appliedReloadEvidence
        , activeReloadConfigEvidence
        ]
        serviceLines
    )

countLine :: String -> Text -> [Text] -> Int
countLine _label wanted = length . filter (== wanted)

countPrefix :: String -> Text -> [Text] -> Int
countPrefix _label prefix = length . filter (Text.isPrefixOf prefix)

countOccurrences :: Text -> Text -> Int
countOccurrences needle = length . Text.breakOnAll needle

orderedSubsequence :: (Eq value) => [value] -> [value] -> Bool
orderedSubsequence [] _actual = True
orderedSubsequence _expected [] = False
orderedSubsequence expected@(next : rest) (actual : remaining)
  | next == actual = orderedSubsequence rest remaining
  | otherwise = orderedSubsequence expected remaining

orderedTextSubstrings :: [Text] -> [Text] -> Bool
orderedTextSubstrings [] _actual = True
orderedTextSubstrings _expected [] = False
orderedTextSubstrings expected@(next : rest) (actual : remaining)
  | next `Text.isInfixOf` actual = orderedTextSubstrings rest remaining
  | otherwise = orderedTextSubstrings expected remaining

lifecycleFailure :: LifecycleFixture -> String -> IO value
lifecycleFailure fixture message = do
  stdoutText <- readIfPresent (fixtureServiceStdoutPath fixture)
  stderrText <- readIfPresent (fixtureServiceStderrPath fixture)
  bridgeText <- readIfPresent (fixtureBridgeLogPath fixture)
  ioError
    ( userError
        ( message
            <> "\nservice stdout:\n"
            <> Text.unpack stdoutText
            <> "\nservice stderr:\n"
            <> Text.unpack stderrText
            <> "\nbridge log:\n"
            <> Text.unpack bridgeText
        )
    )

readIfPresent :: FilePath -> IO Text
readIfPresent path = do
  exists <- doesFileExist path
  if exists then Text.IO.readFile path else pure "(missing)"

shellQuote :: FilePath -> Text
shellQuote = shellQuoteText . Text.pack

shellQuoteText :: Text -> Text
shellQuoteText value =
  "'" <> Text.replace "'" "'\"'\"'" value <> "'"

lifecycleTimeoutMicroseconds :: Int
lifecycleTimeoutMicroseconds = 20 * 1000 * 1000

conditionTimeoutMicroseconds :: Int
conditionTimeoutMicroseconds = 8 * 1000 * 1000

conditionPollMicroseconds :: Int
conditionPollMicroseconds = 10 * 1000

fixtureWriteSettleMicroseconds :: Int
fixtureWriteSettleMicroseconds = 50 * 1000

reloadDedupCacheSize :: Int
reloadDedupCacheSize = 17

reloadDedupCacheTtlSeconds :: Int
reloadDedupCacheTtlSeconds = 23

reloadDrainDeadlineSeconds :: Int
reloadDrainDeadlineSeconds = 1

unchangedReloadEvidence :: Text
unchangedReloadEvidence =
  "reload: ignored; reason=live config unchanged"

appliedReloadEvidence :: Text
appliedReloadEvidence =
  "reload: applied; generation=1"

activeReloadConfigEvidence :: Text
activeReloadConfigEvidence =
  Text.intercalate
    ""
    [ "reload: active live config; log-level=Info"
    , "; retry-policy=ExponentialN 5 50 2000"
    , "; inference-batch-size=64"
    , "; inference-max-latency-millis=5000"
    , "; dedup-cache-size=17"
    , "; dedup-cache-ttl-seconds=23"
    , "; drain-deadline-seconds=1"
    ]

malformedReloadEvidence :: Text
malformedReloadEvidence =
  "reload: ignored; reason=invalid live config; generation=1"

restartRequiredEvidence :: Text
restartRequiredEvidence =
  "reload: restart-required; reason=boot config changed; generation=1"

drainDeadlineNanoseconds :: Word64
drainDeadlineNanoseconds = 30 * 1000 * 1000 * 1000

minimumDeadlineNanoseconds :: Word64
minimumDeadlineNanoseconds = 750 * 1000 * 1000

forcedDrainUpperBoundNanoseconds :: Word64
forcedDrainUpperBoundNanoseconds = 8 * 1000 * 1000 * 1000

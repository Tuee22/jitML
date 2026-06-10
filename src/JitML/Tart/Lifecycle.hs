{-# LANGUAGE OverloadedStrings #-}

-- | Tart build-VM lifecycle (reinstated 2026-06-10, Phase 2 Sprint 2.11).
--
-- All Apple Silicon Swift/Metal builds run inside a @jitml@-managed Tart VM. This
-- module owns that VM's lifecycle: clone (create) it from a base image, assign its
-- CPU/memory/disk limits, start it headless with the repository mounted so the
-- in-VM @swift build@ writes the produced dylib to a host-visible path, stop it,
-- and delete it. Execution stays host-native: the dylib is copied out of the VM
-- (it lands on the shared mount) and the host @dlopen@s it. See
-- @documents/engineering/jit_codegen_architecture.md@ → Apple Silicon Tart-VM
-- Build JIT.
module JitML.Tart.Lifecycle
  ( BuildVmConfig (..)
  , TartVmStatus (..)
  , VmName (..)
  , defaultBuildVmConfig
  , defaultBuildVmName
  , defaultTartBaseImage
  , ensureBuildVmUp
  , guestMountTag
  , guestSourcePath
  , parseTartListStatus
  , provisionBuildVm
  , queryTartVmStatus
  , renderTartVmStatus
  , stopTartVmLive
  , deleteTartVmLive
  , tartCloneSubprocess
  , tartDeleteSubprocess
  , tartListSubprocess
  , tartRunSubprocess
  , tartSetSubprocess
  , tartStopSubprocess
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception.Safe (displayException, tryAny)
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:), (.:?))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Exit (ExitCode (..))
import System.FilePath ((</>))

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming, startDetached)
import JitML.Sub.Subprocess (Subprocess, subprocess)

newtype VmName = VmName
  { unVmName :: Text
  }
  deriving stock (Eq, Show)

data TartVmStatus
  = TartVmMissing
  | TartVmStopped
  | TartVmRunning
  deriving stock (Eq, Show)

-- | The @jitml@-managed build VM and the resources it is assigned. The resource
-- limits are surfaced through the host Dhall @LiveConfig@ (Phase 5 Sprint 5.9);
-- 'defaultBuildVmConfig' carries the baseline the daemon uses when none is set.
data BuildVmConfig = BuildVmConfig
  { buildVmName :: VmName
  , buildVmBaseImage :: Text
  , buildVmCpuCount :: Int
  , buildVmMemoryMib :: Int
  , buildVmDiskGib :: Int
  , -- | Absolute host path mounted into the VM (the repository root) so the
    -- in-VM @swift build@ writes the dylib to a host-visible location.
    buildVmHostMountRoot :: FilePath
  }
  deriving stock (Eq, Show)

defaultBuildVmName :: VmName
defaultBuildVmName = VmName "jitml-build"

defaultTartBaseImage :: Text
defaultTartBaseImage =
  "ghcr.io/cirruslabs/macos-sequoia-xcode:latest"

-- | The shared-mount tag passed to @tart run --dir@. The guest exposes the
-- mounted host root at @\/Volumes\/My Shared Files\/<tag>@.
guestMountTag :: Text
guestMountTag = "jitml"

defaultBuildVmConfig :: FilePath -> BuildVmConfig
defaultBuildVmConfig hostMountRoot =
  BuildVmConfig
    { buildVmName = defaultBuildVmName
    , buildVmBaseImage = defaultTartBaseImage
    , buildVmCpuCount = 4
    , buildVmMemoryMib = 8192
    , buildVmDiskGib = 50
    , buildVmHostMountRoot = hostMountRoot
    }

-- | Map a repository-relative directory (e.g. the generated source dir
-- @.build/jit-src/apple-silicon/<hash>@) to its path inside the VM under the
-- shared mount, so the in-VM @swift build@ can address it with @--package-path@.
guestSourcePath :: FilePath -> FilePath
guestSourcePath relativeDir =
  ("/Volumes/My Shared Files" </> Text.unpack guestMountTag) </> relativeDir

data TartListEntry = TartListEntry
  { tartListEntryName :: Text
  , tartListEntryRunning :: Bool
  , tartListEntryState :: Maybe Text
  }
  deriving stock (Eq, Show)

instance FromJSON TartListEntry where
  parseJSON =
    withObject "TartListEntry" $ \object ->
      TartListEntry
        <$> object .: "Name"
        <*> object .: "Running"
        <*> object .:? "State"

-- | Ensure the build VM exists with its configured resources and is running with
-- the repository mounted; provision (clone + set limits) it on first use.
ensureBuildVmUp :: BuildVmConfig -> IO (Either Text TartVmStatus)
ensureBuildVmUp config = do
  status <- queryTartVmStatus (buildVmName config)
  case status of
    Left err -> pure (Left err)
    Right TartVmRunning -> pure (Right TartVmRunning)
    Right TartVmMissing -> do
      provisioned <- provisionBuildVm config
      case provisioned of
        Left err -> pure (Left err)
        Right () -> startAndWait config
    Right TartVmStopped -> startAndWait config

startAndWait :: BuildVmConfig -> IO (Either Text TartVmStatus)
startAndWait config = do
  started <- startTartVmDetached config
  case started of
    Left err -> pure (Left err)
    Right () -> do
      ready <- waitForTartExec (buildVmName config) 60
      pure $
        case ready of
          Left err -> Left err
          Right () -> Right TartVmRunning

-- | Clone the base image into the named VM (when missing) and assign its
-- CPU/memory/disk limits. Idempotent: a present VM is left in place.
provisionBuildVm :: BuildVmConfig -> IO (Either Text ())
provisionBuildVm config = do
  status <- queryTartVmStatus (buildVmName config)
  case status of
    Left err -> pure (Left err)
    Right TartVmMissing -> do
      cloned <- runTartCommand (tartCloneSubprocess (buildVmBaseImage config) (buildVmName config))
      case cloned of
        Left err -> pure (Left err)
        Right () ->
          runTartCommand
            ( tartSetSubprocess
                (buildVmName config)
                (buildVmCpuCount config)
                (buildVmMemoryMib config)
                (buildVmDiskGib config)
            )
    Right _existing -> pure (Right ())

stopTartVmLive :: VmName -> IO (Either Text TartVmStatus)
stopTartVmLive vmName = do
  status <- queryTartVmStatus vmName
  case status of
    Left err -> pure (Left err)
    Right TartVmMissing -> pure (Right TartVmMissing)
    Right TartVmStopped -> pure (Right TartVmStopped)
    Right TartVmRunning -> do
      stopped <- runTartCommand (tartStopSubprocess vmName)
      case stopped of
        Left err -> pure (Left err)
        Right () -> queryTartVmStatus vmName

-- | Stop (if running) and delete the VM. Idempotent on a missing VM.
deleteTartVmLive :: VmName -> IO (Either Text TartVmStatus)
deleteTartVmLive vmName = do
  _stopped <- stopTartVmLive vmName
  status <- queryTartVmStatus vmName
  case status of
    Left err -> pure (Left err)
    Right TartVmMissing -> pure (Right TartVmMissing)
    Right _present -> do
      deleted <- runTartCommand (tartDeleteSubprocess vmName)
      case deleted of
        Left err -> pure (Left err)
        Right () -> queryTartVmStatus vmName

queryTartVmStatus :: VmName -> IO (Either Text TartVmStatus)
queryTartVmStatus vmName = do
  executed <- tryRunStreaming tartListSubprocess
  pure $
    case executed of
      Left err -> Left err
      Right (exitCode, stdoutText, stderrText) ->
        case exitCode of
          ExitSuccess ->
            parseTartListStatus vmName stdoutText
          ExitFailure _ ->
            Left
              ( "failed to inspect Tart VMs with "
                  <> renderSubprocess tartListSubprocess
                  <> ": "
                  <> stderrText
              )

runTartCommand :: Subprocess -> IO (Either Text ())
runTartCommand command = do
  executed <- tryRunStreaming command
  pure $
    case executed of
      Left err -> Left err
      Right (exitCode, stdoutText, stderrText) ->
        case exitCode of
          ExitSuccess -> Right ()
          ExitFailure _ ->
            Left
              ( "failed to run "
                  <> renderSubprocess command
                  <> renderCommandFailureDetail stdoutText stderrText
              )

renderCommandFailureDetail :: Text -> Text -> Text
renderCommandFailureDetail stdoutText stderrText =
  case Text.strip (if Text.null stderrText then stdoutText else stderrText) of
    "" -> ""
    detail -> ": " <> detail

startTartVmDetached :: BuildVmConfig -> IO (Either Text ())
startTartVmDetached config = do
  let command = tartRunSubprocess (buildVmHostMountRoot config) (buildVmName config)
  result <- tryAny (startDetached defaultSubprocessEnv command)
  pure $
    case result of
      Left err ->
        Left
          ( "failed to start Tart VM with "
              <> renderSubprocess command
              <> ": "
              <> Text.pack (displayException err)
          )
      Right () -> Right ()

tryRunStreaming :: Subprocess -> IO (Either Text (ExitCode, Text, Text))
tryRunStreaming command = do
  result <- tryAny (runStreaming defaultSubprocessEnv command)
  pure $
    case result of
      Left err ->
        Left
          ( "failed to run "
              <> renderSubprocess command
              <> ": "
              <> Text.pack (displayException err)
          )
      Right executed -> Right executed

waitForTartExec :: VmName -> Int -> IO (Either Text ())
waitForTartExec vmName attemptsRemaining
  | attemptsRemaining <= 0 =
      pure (Left ("Tart VM " <> unVmName vmName <> " did not become exec-ready"))
  | otherwise = do
      let probe = subprocess "tart" ["exec", unVmName vmName, "true"]
      executed <- tryRunStreaming probe
      case executed of
        Left err -> pure (Left err)
        Right (exitCode, _stdoutText, stderrText) ->
          case exitCode of
            ExitSuccess -> pure (Right ())
            ExitFailure _ -> do
              threadDelay 1000000
              if attemptsRemaining == 1
                then
                  pure
                    ( Left
                        ( "Tart VM "
                            <> unVmName vmName
                            <> " failed exec readiness probe "
                            <> renderSubprocess probe
                            <> ": "
                            <> stderrText
                        )
                    )
                else waitForTartExec vmName (attemptsRemaining - 1)

parseTartListStatus :: VmName -> Text -> Either Text TartVmStatus
parseTartListStatus (VmName vmName) jsonText = do
  entries <-
    case eitherDecode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 jsonText)) of
      Left err -> Left ("failed to parse `tart list --format json`: " <> Text.pack err)
      Right decoded -> Right decoded
  pure $
    case filter ((== vmName) . tartListEntryName) entries of
      [] -> TartVmMissing
      entry : _
        | tartListEntryRunning entry -> TartVmRunning
        | otherwise ->
            case tartListEntryState entry of
              Just "running" -> TartVmRunning
              _ -> TartVmStopped

renderTartVmStatus :: TartVmStatus -> Text
renderTartVmStatus TartVmMissing = "missing"
renderTartVmStatus TartVmStopped = "stopped"
renderTartVmStatus TartVmRunning = "running"

tartCloneSubprocess :: Text -> VmName -> Subprocess
tartCloneSubprocess baseImage vmName =
  subprocess "tart" ["clone", baseImage, unVmName vmName]

tartSetSubprocess :: VmName -> Int -> Int -> Int -> Subprocess
tartSetSubprocess vmName cpuCount memoryMib diskGib =
  subprocess
    "tart"
    [ "set"
    , unVmName vmName
    , "--cpu"
    , Text.pack (show cpuCount)
    , "--memory"
    , Text.pack (show memoryMib)
    , "--disk-size"
    , Text.pack (show diskGib)
    ]

tartListSubprocess :: Subprocess
tartListSubprocess =
  subprocess "tart" ["list", "--source", "local", "--format", "json"]

tartRunSubprocess :: FilePath -> VmName -> Subprocess
tartRunSubprocess hostMountRoot vmName =
  subprocess
    "tart"
    [ "run"
    , "--no-graphics"
    , "--dir"
    , guestMountTag <> ":" <> Text.pack hostMountRoot
    , unVmName vmName
    ]

tartStopSubprocess :: VmName -> Subprocess
tartStopSubprocess vmName =
  subprocess "tart" ["stop", unVmName vmName]

tartDeleteSubprocess :: VmName -> Subprocess
tartDeleteSubprocess vmName =
  subprocess "tart" ["delete", unVmName vmName]

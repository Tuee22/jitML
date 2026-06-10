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
  , diskGrowthTarget
  , ensureBuildVmUp
  , guestMountTag
  , guestSourcePath
  , parseTartListStatus
  , parseTartListDiskGib
  , provisionBuildVm
  , queryTartVmStatus
  , queryTartVmDiskGib
  , renderTartVmStatus
  , stopTartVmLive
  , deleteTartVmLive
  , tartCloneSubprocess
  , tartDeleteSubprocess
  , tartListSubprocess
  , tartRunSubprocess
  , tartSetDiskSubprocess
  , tartSetResourcesSubprocess
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
  , buildVmHostMountRoot :: FilePath
  -- ^ Absolute host path mounted into the VM (the repository root) so the
  -- in-VM @swift build@ writes the dylib to a host-visible location.
  }
  deriving stock (Eq, Show)

defaultBuildVmName :: VmName
defaultBuildVmName = VmName "jitml-build"

-- | Base image cloned into the build VM. Pinned to the Xcode-16 (macOS Sequoia)
-- tag rather than @:latest@ so the in-VM Swift/Metal toolchain is reproducible
-- across provisions — the within-substrate determinism contract depends on a
-- stable toolchain — and so a fresh provision reuses an already-pulled local
-- image instead of re-downloading a moving @:latest@.
defaultTartBaseImage :: Text
defaultTartBaseImage =
  "ghcr.io/cirruslabs/macos-sequoia-xcode:16"

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
  , tartListEntryDiskGib :: Maybe Int
  }
  deriving stock (Eq, Show)

instance FromJSON TartListEntry where
  parseJSON =
    withObject "TartListEntry" $ \object ->
      TartListEntry
        <$> object .: "Name"
        <*> object .: "Running"
        <*> object .:? "State"
        <*> object .:? "Disk"

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
      -- A warm restart becomes exec-ready in ~20s, but a cold first boot of a
      -- freshly cloned macOS image can take longer; allow generous headroom so a
      -- slow-but-valid boot is not mistaken for a failed one.
      ready <- waitForTartExec (buildVmName config) 180
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
        Right () -> do
          setResources <-
            runTartCommand
              ( tartSetResourcesSubprocess
                  (buildVmName config)
                  (buildVmCpuCount config)
                  (buildVmMemoryMib config)
              )
          case setResources of
            Left err -> pure (Left err)
            Right () -> growBuildVmDisk config
    Right _existing -> pure (Right ())

-- | Grow the cloned VM's disk to the configured size when (and only when) the
-- configured size exceeds the image's current disk. @tart set --disk-size@ can
-- only grow a disk, never shrink it, and cirruslabs base images already ship a
-- large disk, so a fixed @--disk-size@ smaller than the base would fail
-- provisioning outright. A grow-only resize keeps provisioning self-sufficient.
growBuildVmDisk :: BuildVmConfig -> IO (Either Text ())
growBuildVmDisk config = do
  currentDisk <- queryTartVmDiskGib (buildVmName config)
  case currentDisk of
    Left err -> pure (Left err)
    Right current ->
      case diskGrowthTarget (buildVmDiskGib config) current of
        Nothing -> pure (Right ())
        Just target -> runTartCommand (tartSetDiskSubprocess (buildVmName config) target)

-- | The disk size (GiB) to grow a freshly cloned VM to, or 'Nothing' when no
-- grow is required. Resize only when the configured size is strictly larger than
-- the image's current disk; an unknown current size is treated as "no grow"
-- because the base image's disk is already ample.
diskGrowthTarget :: Int -> Maybe Int -> Maybe Int
diskGrowthTarget configuredGib currentGib =
  case currentGib of
    Just current | configuredGib > current -> Just configuredGib
    _ -> Nothing

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

-- | The named VM's current disk size in GiB, or 'Nothing' when the field is
-- absent. A missing VM also yields 'Nothing'.
queryTartVmDiskGib :: VmName -> IO (Either Text (Maybe Int))
queryTartVmDiskGib vmName = do
  executed <- tryRunStreaming tartListSubprocess
  pure $
    case executed of
      Left err -> Left err
      Right (exitCode, stdoutText, stderrText) ->
        case exitCode of
          ExitSuccess ->
            parseTartListDiskGib vmName stdoutText
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

parseTartListDiskGib :: VmName -> Text -> Either Text (Maybe Int)
parseTartListDiskGib (VmName vmName) jsonText = do
  entries <-
    case eitherDecode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 jsonText)) of
      Left err -> Left ("failed to parse `tart list --format json`: " <> Text.pack err)
      Right decoded -> Right decoded
  pure $
    case filter ((== vmName) . tartListEntryName) entries of
      [] -> Nothing
      entry : _ -> tartListEntryDiskGib entry

renderTartVmStatus :: TartVmStatus -> Text
renderTartVmStatus TartVmMissing = "missing"
renderTartVmStatus TartVmStopped = "stopped"
renderTartVmStatus TartVmRunning = "running"

tartCloneSubprocess :: Text -> VmName -> Subprocess
tartCloneSubprocess baseImage vmName =
  subprocess "tart" ["clone", baseImage, unVmName vmName]

tartSetResourcesSubprocess :: VmName -> Int -> Int -> Subprocess
tartSetResourcesSubprocess vmName cpuCount memoryMib =
  subprocess
    "tart"
    [ "set"
    , unVmName vmName
    , "--cpu"
    , Text.pack (show cpuCount)
    , "--memory"
    , Text.pack (show memoryMib)
    ]

tartSetDiskSubprocess :: VmName -> Int -> Subprocess
tartSetDiskSubprocess vmName diskGib =
  subprocess
    "tart"
    [ "set"
    , unVmName vmName
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

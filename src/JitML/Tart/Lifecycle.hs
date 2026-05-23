{-# LANGUAGE OverloadedStrings #-}

module JitML.Tart.Lifecycle
  ( TartVmStatus (..)
  , VmName (..)
  , bootstrapTartVmLive
  , defaultTartBaseImage
  , ensureVmUp
  , ensureVmUpLive
  , parseTartListStatus
  , queryTartVmStatus
  , renderTartVmStatus
  , stopTartVmLive
  , tartCloneSubprocess
  , tartListSubprocess
  , tartRunSubprocess
  , tartStopSubprocess
  , vmStatePath
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception.Safe (displayException, tryAny)
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:), (.:?))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing)
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

defaultTartBaseImage :: Text
defaultTartBaseImage =
  "ghcr.io/cirruslabs/macos-sequoia-xcode:16"

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

ensureVmUp :: FilePath -> VmName -> IO ()
ensureVmUp root vmName = do
  createDirectoryIfMissing True (root </> ".build" </> "runtime")
  Text.IO.writeFile (vmStatePath root vmName) "up\n"

ensureVmUpLive :: VmName -> IO (Either Text TartVmStatus)
ensureVmUpLive vmName = do
  status <- queryTartVmStatus vmName
  case status of
    Left err -> pure (Left err)
    Right TartVmRunning -> pure (Right TartVmRunning)
    Right TartVmMissing ->
      pure $
        Left
          ( "Tart VM "
              <> unVmName vmName
              <> " is missing; run `jitml internal vm bootstrap` or clone "
              <> defaultTartBaseImage
              <> " before the first Apple JIT cache miss"
          )
    Right TartVmStopped -> do
      started <- startTartVmDetached vmName
      case started of
        Left err -> pure (Left err)
        Right () -> do
          ready <- waitForTartExec vmName 30
          pure $
            case ready of
              Left err -> Left err
              Right () -> Right TartVmRunning

bootstrapTartVmLive :: Text -> VmName -> IO (Either Text TartVmStatus)
bootstrapTartVmLive baseImage vmName = do
  status <- queryTartVmStatus vmName
  case status of
    Left err -> pure (Left err)
    Right TartVmMissing -> do
      cloned <- runTartCommand (tartCloneSubprocess baseImage vmName)
      case cloned of
        Left err -> pure (Left err)
        Right () -> do
          verified <- queryTartVmStatus vmName
          pure $
            case verified of
              Right TartVmMissing ->
                Left
                  ( "Tart clone completed but "
                      <> unVmName vmName
                      <> " was not listed by "
                      <> renderSubprocess tartListSubprocess
                  )
              other -> other
    Right existing -> pure (Right existing)

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

startTartVmDetached :: VmName -> IO (Either Text ())
startTartVmDetached vmName = do
  let command = tartRunSubprocess vmName
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

tartListSubprocess :: Subprocess
tartListSubprocess =
  subprocess "tart" ["list", "--source", "local", "--format", "json"]

tartRunSubprocess :: VmName -> Subprocess
tartRunSubprocess vmName =
  subprocess "tart" ["run", "--no-graphics", unVmName vmName]

tartStopSubprocess :: VmName -> Subprocess
tartStopSubprocess vmName =
  subprocess "tart" ["stop", unVmName vmName]

vmStatePath :: FilePath -> VmName -> FilePath
vmStatePath root vmName =
  root </> ".build" </> "runtime" </> Text.unpack (unVmName vmName) <> ".state"

{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.OneDnnRuntime
  ( OneDnnRuntimeProbe (..)
  , oneDnnLibraryVisibleFromLdconfig
  , oneDnnRuntimeAvailable
  , parsePkgConfigVersion
  , probeOneDnnRuntime
  , renderOneDnnRuntimeProbe
  )
where

import Control.Exception qualified as Exception
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data OneDnnRuntimeProbe = OneDnnRuntimeProbe
  { oneDnnRuntimePkgConfigName :: Maybe Text
  , oneDnnRuntimePkgConfigVersion :: Maybe Text
  , oneDnnRuntimeHeaderPath :: Maybe Text
  , oneDnnRuntimeLibraryVisible :: Bool
  , oneDnnRuntimeProbeLog :: [Text]
  }
  deriving stock (Eq, Show)

oneDnnRuntimeAvailable :: OneDnnRuntimeProbe -> Bool
oneDnnRuntimeAvailable probe =
  (isJust (oneDnnRuntimePkgConfigName probe) || isJust (oneDnnRuntimeHeaderPath probe))
    && oneDnnRuntimeLibraryVisible probe

probeOneDnnRuntime :: IO OneDnnRuntimeProbe
probeOneDnnRuntime = do
  pkgConfigResults <- traverse probePkgConfig ["dnnl", "onednn"]
  headerResults <- traverse probeHeader ["/usr/include/oneapi/dnnl/dnnl.hpp", "/usr/include/dnnl.hpp"]
  ldconfigResult <- probeLdconfig
  let selected = firstPkgConfigHit pkgConfigResults
      selectedHeader = firstHeaderHit headerResults
      libraryVisible =
        case ldconfigResult of
          Right output -> oneDnnLibraryVisibleFromLdconfig output
          Left _ -> False
      pkgConfigLog =
        fmap renderPkgConfigProbeResult pkgConfigResults
      headerLog =
        fmap renderHeaderProbeResult headerResults
      libraryLog =
        case ldconfigResult of
          Right output ->
            [ "ldconfig -p: libdnnl visible=" <> renderBool (oneDnnLibraryVisibleFromLdconfig output)
            ]
          Left err ->
            ["ldconfig -p: " <> err]
  pure
    OneDnnRuntimeProbe
      { oneDnnRuntimePkgConfigName = fmap fst selected
      , oneDnnRuntimePkgConfigVersion = fmap snd selected
      , oneDnnRuntimeHeaderPath = selectedHeader
      , oneDnnRuntimeLibraryVisible = libraryVisible
      , oneDnnRuntimeProbeLog = pkgConfigLog <> headerLog <> libraryLog
      }

parsePkgConfigVersion :: Text -> Maybe Text
parsePkgConfigVersion output =
  case Text.strip output of
    "" -> Nothing
    version -> Just version

oneDnnLibraryVisibleFromLdconfig :: Text -> Bool
oneDnnLibraryVisibleFromLdconfig output =
  any lineMentionsOneDnnLibrary (Text.lines output)
 where
  lineMentionsOneDnnLibrary line =
    "libdnnl" `Text.isInfixOf` line || "libonednn" `Text.isInfixOf` line

renderOneDnnRuntimeProbe :: OneDnnRuntimeProbe -> Text
renderOneDnnRuntimeProbe probe =
  Text.unlines $
    [ "onednn_runtime:"
    , "  available: " <> renderBool (oneDnnRuntimeAvailable probe)
    , "  pkg_config_name: " <> fromMaybe "none" (oneDnnRuntimePkgConfigName probe)
    , "  pkg_config_version: " <> fromMaybe "none" (oneDnnRuntimePkgConfigVersion probe)
    , "  header_path: " <> fromMaybe "none" (oneDnnRuntimeHeaderPath probe)
    , "  library_visible: " <> renderBool (oneDnnRuntimeLibraryVisible probe)
    , "  probes:"
    ]
      <> fmap ("    - " <>) (oneDnnRuntimeProbeLog probe)

probePkgConfig :: Text -> IO (Text, Maybe Text, Text)
probePkgConfig packageName = do
  result <- runSubprocessSafely command
  pure $
    case result of
      Right (ExitSuccess, stdoutText, _stderrText) ->
        case parsePkgConfigVersion stdoutText of
          Just version ->
            (packageName, Just version, renderSubprocess command <> ": " <> version)
          Nothing ->
            (packageName, Nothing, renderSubprocess command <> ": empty version")
      Right (ExitFailure code, _stdoutText, stderrText) ->
        ( packageName
        , Nothing
        , renderSubprocess command
            <> ": exit "
            <> Text.pack (show code)
            <> renderStderr stderrText
        )
      Left err ->
        (packageName, Nothing, renderSubprocess command <> ": " <> err)
 where
  command = subprocess "pkg-config" ["--modversion", packageName]

probeHeader :: Text -> IO (Text, Bool, Text)
probeHeader headerPath = do
  result <- runSubprocessSafely command
  pure $
    case result of
      Right (ExitSuccess, _stdoutText, _stderrText) ->
        (headerPath, True, renderSubprocess command <> ": readable")
      Right (ExitFailure code, _stdoutText, stderrText) ->
        ( headerPath
        , False
        , renderSubprocess command
            <> ": exit "
            <> Text.pack (show code)
            <> renderStderr stderrText
        )
      Left err ->
        (headerPath, False, renderSubprocess command <> ": " <> err)
 where
  command = subprocess "test" ["-r", headerPath]

probeLdconfig :: IO (Either Text Text)
probeLdconfig = do
  result <- runSubprocessSafely command
  pure $
    case result of
      Right (ExitSuccess, stdoutText, _stderrText) -> Right stdoutText
      Right (ExitFailure code, _stdoutText, stderrText) ->
        Left ("exit " <> Text.pack (show code) <> renderStderr stderrText)
      Left err -> Left err
 where
  command = subprocess "ldconfig" ["-p"]

runSubprocessSafely :: Subprocess -> IO (Either Text (ExitCode, Text, Text))
runSubprocessSafely command =
  (Right <$> runStreaming defaultSubprocessEnv command)
    `Exception.catch` \(err :: Exception.SomeException) ->
      pure (Left (Text.pack (Exception.displayException err)))

firstPkgConfigHit :: [(Text, Maybe Text, Text)] -> Maybe (Text, Text)
firstPkgConfigHit [] = Nothing
firstPkgConfigHit ((packageName, Just version, _message) : _rest) = Just (packageName, version)
firstPkgConfigHit (_miss : rest) = firstPkgConfigHit rest

firstHeaderHit :: [(Text, Bool, Text)] -> Maybe Text
firstHeaderHit [] = Nothing
firstHeaderHit ((headerPath, True, _message) : _rest) = Just headerPath
firstHeaderHit (_miss : rest) = firstHeaderHit rest

renderPkgConfigProbeResult :: (Text, Maybe Text, Text) -> Text
renderPkgConfigProbeResult (_packageName, _version, message) =
  message

renderHeaderProbeResult :: (Text, Bool, Text) -> Text
renderHeaderProbeResult (_headerPath, _visible, message) =
  message

renderStderr :: Text -> Text
renderStderr stderrText =
  case Text.strip stderrText of
    "" -> ""
    stripped -> ": " <> stripped

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.MetalRuntime
  ( MetalRuntimeProbe (..)
  , metalDeviceVisibleFromSystemProfiler
  , metalRuntimeAvailable
  , parseSwiftVersion
  , parseXcrunFindOutput
  , probeMetalRuntime
  , renderMetalRuntimeProbe
  )
where

import Control.Applicative ((<|>))
import Control.Exception qualified as Exception
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data MetalRuntimeProbe = MetalRuntimeProbe
  { metalRuntimeSwiftVersion :: Maybe Text
  , metalRuntimeMetalCompilerPath :: Maybe Text
  , metalRuntimeSwiftCompilerPath :: Maybe Text
  , metalRuntimeDeviceVisible :: Bool
  , metalRuntimeProbeLog :: [Text]
  }
  deriving stock (Eq, Show)

-- | Sprint 2.12 — core Apple Metal execution is gated by the host OS Metal
-- runtime only. Swift/Xcode compiler discovery is an optional non-core
-- capability exposed as separate prerequisites, so this probe does not invoke
-- swift, xcrun, the offline metal compiler, Tart, or keychain commands.
metalRuntimeAvailable :: MetalRuntimeProbe -> Bool
metalRuntimeAvailable = metalRuntimeDeviceVisible

probeMetalRuntime :: IO MetalRuntimeProbe
probeMetalRuntime = do
  systemProfilerResult <- probeSystemProfiler
  let deviceVisible =
        case systemProfilerResult of
          Right output -> metalDeviceVisibleFromSystemProfiler output
          Left _ -> False
  pure
    MetalRuntimeProbe
      { metalRuntimeSwiftVersion = Nothing
      , metalRuntimeMetalCompilerPath = Nothing
      , metalRuntimeSwiftCompilerPath = Nothing
      , metalRuntimeDeviceVisible = deviceVisible
      , metalRuntimeProbeLog =
          [renderSystemProfilerProbeResult systemProfilerResult]
      }

parseSwiftVersion :: Text -> Maybe Text
parseSwiftVersion output =
  firstJust (parseLine <$> Text.lines output)
 where
  parseLine line =
    parseAfterMarker "Apple Swift version " line
      <|> parseAfterMarker "Swift version " line
  parseAfterMarker marker line =
    let (_before, afterMarker) = Text.breakOn marker line
     in if Text.null afterMarker
          then Nothing
          else
            let version =
                  Text.takeWhile
                    (\char -> char /= ',' && char /= ')' && not (isSpace char))
                    (Text.drop (Text.length marker) afterMarker)
             in if Text.null version then Nothing else Just version

parseXcrunFindOutput :: Text -> Maybe Text
parseXcrunFindOutput output =
  case filter (not . Text.null) (Text.strip <$> Text.lines output) of
    path : _rest -> Just path
    [] -> Nothing

metalDeviceVisibleFromSystemProfiler :: Text -> Bool
metalDeviceVisibleFromSystemProfiler output =
  any (lineReportsMetal . Text.strip) (Text.lines output)
 where
  lineReportsMetal line =
    "Metal" `Text.isInfixOf` line
      && not ("Unsupported" `Text.isInfixOf` line)
      && ( "Supported" `Text.isInfixOf` line
             || "Metal " `Text.isInfixOf` line
             || "Metal:" `Text.isPrefixOf` line
         )

renderMetalRuntimeProbe :: MetalRuntimeProbe -> Text
renderMetalRuntimeProbe probe =
  Text.unlines $
    [ "metal_runtime:"
    , "  available: " <> renderBool (metalRuntimeAvailable probe)
    , "  swift_version: " <> renderOptionalProbeValue (metalRuntimeSwiftVersion probe)
    , "  metal_compiler: " <> renderOptionalProbeValue (metalRuntimeMetalCompilerPath probe)
    , "  swift_compiler: " <> renderOptionalProbeValue (metalRuntimeSwiftCompilerPath probe)
    , "  device_visible: " <> renderBool (metalRuntimeDeviceVisible probe)
    , "  probes:"
    ]
      <> fmap ("    - " <>) (metalRuntimeProbeLog probe)

probeSystemProfiler :: IO (Either Text Text)
probeSystemProfiler = do
  result <- runSubprocessSafely command
  pure $
    case result of
      Right (ExitSuccess, stdoutText, _stderrText) -> Right stdoutText
      Right (ExitFailure code, _stdoutText, stderrText) ->
        Left ("exit " <> Text.pack (show code) <> renderStderr stderrText)
      Left err -> Left err
 where
  command = subprocess "system_profiler" ["SPDisplaysDataType"]

runSubprocessSafely :: Subprocess -> IO (Either Text (ExitCode, Text, Text))
runSubprocessSafely command =
  (Right <$> runStreaming defaultSubprocessEnv command)
    `Exception.catch` \(err :: Exception.SomeException) ->
      pure (Left (Text.pack (Exception.displayException err)))

renderSystemProfilerProbeResult :: Either Text Text -> Text
renderSystemProfilerProbeResult (Right output) =
  renderSubprocess (subprocess "system_profiler" ["SPDisplaysDataType"])
    <> ": metal_device_visible="
    <> renderBool (metalDeviceVisibleFromSystemProfiler output)
renderSystemProfilerProbeResult (Left err) =
  renderSubprocess (subprocess "system_profiler" ["SPDisplaysDataType"]) <> ": " <> err

renderStderr :: Text -> Text
renderStderr stderrText =
  case Text.strip stderrText of
    "" -> ""
    stripped -> ": " <> stripped

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

renderOptionalProbeValue :: Maybe Text -> Text
renderOptionalProbeValue = fromMaybe "not_probed"

firstJust :: [Maybe a] -> Maybe a
firstJust [] = Nothing
firstJust (Just value : _rest) = Just value
firstJust (Nothing : rest) = firstJust rest

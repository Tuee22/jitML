{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.MetalRuntime
  ( MetalRuntimeProbe (..)
  , metalDeviceVisibleFromSystemProfiler
  , metalRuntimeAvailable
  , parseSwiftVersion
  , parseXcrunFindOutput
  , probeMetalRuntime
  , probeMetalRuntimeCached
  , renderMetalRuntimeProbe
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception qualified as Exception
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.IO.Unsafe (unsafePerformIO)

import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , renderProcessFailure
  )
import JitML.Sub.Render (renderBool, renderSubprocess)
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

-- | Reuse a successful device-visibility probe within one process.  LayerGraph
-- training opens its compiled backend once per batch, but GPU visibility cannot
-- change underneath a running producer in any supported lifecycle.  Caching the
-- successful result avoids spawning @system_profiler@ for every batch while
-- keeping 'probeMetalRuntime' fresh for explicit doctor/status diagnostics.
-- Failed probes are deliberately not cached, so a transient subprocess failure
-- cannot poison the remainder of the process.
probeMetalRuntimeCached :: IO MetalRuntimeProbe
probeMetalRuntimeCached =
  modifyMVar successfulMetalRuntimeProbe $ \cached ->
    case cached of
      Just probe -> pure (cached, probe)
      Nothing -> do
        probe <- probeMetalRuntime
        pure
          ( if metalRuntimeDeviceVisible probe then Just probe else Nothing
          , probe
          )

{-# NOINLINE successfulMetalRuntimeProbe #-}
successfulMetalRuntimeProbe :: MVar (Maybe MetalRuntimeProbe)
successfulMetalRuntimeProbe = unsafePerformIO (newMVar Nothing)

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
      Right (ProcessSucceeded transcript) -> Right (processTranscriptStdout transcript)
      Right (ProcessFailed failure) -> Left (renderProcessFailure failure)
      Left err -> Left err
 where
  command = subprocess "system_profiler" ["SPDisplaysDataType"]

runSubprocessSafely :: Subprocess -> IO (Either Text ProcessOutcome)
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

renderOptionalProbeValue :: Maybe Text -> Text
renderOptionalProbeValue = fromMaybe "not_probed"

firstJust :: [Maybe a] -> Maybe a
firstJust [] = Nothing
firstJust (Just value : _rest) = Just value
firstJust (Nothing : rest) = firstJust rest

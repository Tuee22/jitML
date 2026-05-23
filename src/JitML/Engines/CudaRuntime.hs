{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.CudaRuntime
  ( accumulateCudaReductionPartials
  , CudaLibraryVisibility (..)
  , CudaRuntimeProbe (..)
  , cudaLibrariesAvailable
  , cudaLibrariesVisibleFromLdconfig
  , cudaReductionBlockSize
  , cudaReductionPartialCount
  , cudaReductionWarpsPerBlock
  , cudaRuntimeAvailable
  , cudaWarpSize
  , finalizeCudaReductionPartials
  , parseNvccVersion
  , parseNvidiaSmiDevices
  , probeCudaRuntime
  , renderCudaRuntimeProbe
  )
where

import Control.Exception qualified as Exception
import Data.Char (isSpace)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data CudaLibraryVisibility = CudaLibraryVisibility
  { cudaDriverLibraryVisible :: Bool
  , cudaBlasLibraryVisible :: Bool
  , cudaDnnLibraryVisible :: Bool
  }
  deriving stock (Eq, Show)

data CudaRuntimeProbe = CudaRuntimeProbe
  { cudaRuntimeNvccVersion :: Maybe Text
  , cudaRuntimeGpuDevices :: [Text]
  , cudaRuntimeLibraryVisibility :: CudaLibraryVisibility
  , cudaRuntimeProbeLog :: [Text]
  }
  deriving stock (Eq, Show)

cudaRuntimeAvailable :: CudaRuntimeProbe -> Bool
cudaRuntimeAvailable probe =
  isJust (cudaRuntimeNvccVersion probe)
    && not (null (cudaRuntimeGpuDevices probe))
    && cudaLibrariesAvailable (cudaRuntimeLibraryVisibility probe)

cudaLibrariesAvailable :: CudaLibraryVisibility -> Bool
cudaLibrariesAvailable visibility =
  cudaDriverLibraryVisible visibility
    && cudaBlasLibraryVisible visibility
    && cudaDnnLibraryVisible visibility

probeCudaRuntime :: IO CudaRuntimeProbe
probeCudaRuntime = do
  nvccResult <- probeNvcc
  nvidiaSmiResult <- probeNvidiaSmi
  ldconfigResult <- probeLdconfig
  let libraryVisibility =
        case ldconfigResult of
          Right output -> cudaLibrariesVisibleFromLdconfig output
          Left _ -> emptyCudaLibraryVisibility
      devices =
        case nvidiaSmiResult of
          Right output -> parseNvidiaSmiDevices output
          Left _ -> []
      nvccVersion =
        case nvccResult of
          Right output -> parseNvccVersion output
          Left _ -> Nothing
  pure
    CudaRuntimeProbe
      { cudaRuntimeNvccVersion = nvccVersion
      , cudaRuntimeGpuDevices = devices
      , cudaRuntimeLibraryVisibility = libraryVisibility
      , cudaRuntimeProbeLog =
          [renderNvccProbeResult nvccResult]
            <> [renderNvidiaSmiProbeResult nvidiaSmiResult]
            <> [renderLdconfigProbeResult ldconfigResult]
      }

parseNvccVersion :: Text -> Maybe Text
parseNvccVersion output =
  firstJust (parseReleaseLine <$> Text.lines output)
 where
  parseReleaseLine line =
    let marker = "release "
        (_before, afterMarker) = Text.breakOn marker line
     in if Text.null afterMarker
          then Nothing
          else
            let version =
                  Text.takeWhile
                    (\char -> char /= ',' && not (isSpace char))
                    (Text.drop (Text.length marker) afterMarker)
             in if Text.null version then Nothing else Just version

parseNvidiaSmiDevices :: Text -> [Text]
parseNvidiaSmiDevices output =
  filter ("GPU " `Text.isPrefixOf`) (Text.strip <$> Text.lines output)

cudaLibrariesVisibleFromLdconfig :: Text -> CudaLibraryVisibility
cudaLibrariesVisibleFromLdconfig output =
  CudaLibraryVisibility
    { cudaDriverLibraryVisible = any (mentions "libcuda.so") lines'
    , cudaBlasLibraryVisible = any (mentions "libcublas.so") lines'
    , cudaDnnLibraryVisible = any (mentions "libcudnn.so") lines'
    }
 where
  lines' = Text.lines output
  mentions needle line = needle `Text.isInfixOf` line

renderCudaRuntimeProbe :: CudaRuntimeProbe -> Text
renderCudaRuntimeProbe probe =
  Text.unlines $
    [ "cuda_runtime:"
    , "  available: " <> renderBool (cudaRuntimeAvailable probe)
    , "  nvcc_version: " <> fromMaybe "none" (cudaRuntimeNvccVersion probe)
    , "  gpu_devices:"
    ]
      <> renderDevices (cudaRuntimeGpuDevices probe)
      <> [ "  libraries:"
         , "    libcuda: "
             <> renderBool (cudaDriverLibraryVisible (cudaRuntimeLibraryVisibility probe))
         , "    libcublas: "
             <> renderBool (cudaBlasLibraryVisible (cudaRuntimeLibraryVisibility probe))
         , "    libcudnn: "
             <> renderBool (cudaDnnLibraryVisible (cudaRuntimeLibraryVisibility probe))
         , "  probes:"
         ]
      <> fmap ("    - " <>) (cudaRuntimeProbeLog probe)

cudaReductionBlockSize :: Int
cudaReductionBlockSize = 256

cudaWarpSize :: Int
cudaWarpSize = 32

cudaReductionWarpsPerBlock :: Int
cudaReductionWarpsPerBlock =
  cudaReductionBlockSize `div` cudaWarpSize

cudaReductionPartialCount :: Int -> Either Text Int
cudaReductionPartialCount inputCount
  | inputCount < 0 =
      Left ("cuda reduction input count cannot be negative: " <> Text.pack (show inputCount))
  | inputCount == 0 =
      Right 0
  | otherwise =
      Right (ceilDiv inputCount cudaReductionBlockSize * cudaReductionWarpsPerBlock)

accumulateCudaReductionPartials :: [Float] -> Float
accumulateCudaReductionPartials =
  foldl' (+) 0

finalizeCudaReductionPartials :: Int -> [Float] -> Either Text Float
finalizeCudaReductionPartials inputCount partials = do
  expected <- cudaReductionPartialCount inputCount
  let actual = length partials
  if actual == expected
    then Right (accumulateCudaReductionPartials partials)
    else
      Left
        ( "cuda reduction partial count mismatch: expected "
            <> Text.pack (show expected)
            <> ", got "
            <> Text.pack (show actual)
        )

ceilDiv :: Int -> Int -> Int
ceilDiv value divisor =
  let (quotient, remainder) = value `divMod` divisor
   in if remainder == 0 then quotient else quotient + 1

probeNvcc :: IO (Either Text Text)
probeNvcc = do
  result <- runSubprocessSafely command
  pure $
    case result of
      Right (ExitSuccess, stdoutText, _stderrText) -> Right stdoutText
      Right (ExitFailure code, _stdoutText, stderrText) ->
        Left ("exit " <> Text.pack (show code) <> renderStderr stderrText)
      Left err -> Left err
 where
  command = subprocess "nvcc" ["--version"]

probeNvidiaSmi :: IO (Either Text Text)
probeNvidiaSmi = do
  result <- runSubprocessSafely command
  pure $
    case result of
      Right (ExitSuccess, stdoutText, _stderrText) -> Right stdoutText
      Right (ExitFailure code, _stdoutText, stderrText) ->
        Left ("exit " <> Text.pack (show code) <> renderStderr stderrText)
      Left err -> Left err
 where
  command = subprocess "nvidia-smi" ["-L"]

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

renderNvccProbeResult :: Either Text Text -> Text
renderNvccProbeResult (Right output) =
  case parseNvccVersion output of
    Just version -> renderSubprocess (subprocess "nvcc" ["--version"]) <> ": " <> version
    Nothing -> renderSubprocess (subprocess "nvcc" ["--version"]) <> ": empty version"
renderNvccProbeResult (Left err) =
  renderSubprocess (subprocess "nvcc" ["--version"]) <> ": " <> err

renderNvidiaSmiProbeResult :: Either Text Text -> Text
renderNvidiaSmiProbeResult (Right output) =
  renderSubprocess (subprocess "nvidia-smi" ["-L"])
    <> ": "
    <> Text.pack (show (length (parseNvidiaSmiDevices output)))
    <> " device(s)"
renderNvidiaSmiProbeResult (Left err) =
  renderSubprocess (subprocess "nvidia-smi" ["-L"]) <> ": " <> err

renderLdconfigProbeResult :: Either Text Text -> Text
renderLdconfigProbeResult (Right output) =
  let visibility = cudaLibrariesVisibleFromLdconfig output
   in renderSubprocess (subprocess "ldconfig" ["-p"])
        <> ": libcuda="
        <> renderBool (cudaDriverLibraryVisible visibility)
        <> " libcublas="
        <> renderBool (cudaBlasLibraryVisible visibility)
        <> " libcudnn="
        <> renderBool (cudaDnnLibraryVisible visibility)
renderLdconfigProbeResult (Left err) =
  renderSubprocess (subprocess "ldconfig" ["-p"]) <> ": " <> err

renderDevices :: [Text] -> [Text]
renderDevices [] = ["    - none"]
renderDevices devices = fmap ("    - " <>) devices

renderStderr :: Text -> Text
renderStderr stderrText =
  case Text.strip stderrText of
    "" -> ""
    stripped -> ": " <> stripped

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

emptyCudaLibraryVisibility :: CudaLibraryVisibility
emptyCudaLibraryVisibility =
  CudaLibraryVisibility
    { cudaDriverLibraryVisible = False
    , cudaBlasLibraryVisible = False
    , cudaDnnLibraryVisible = False
    }

firstJust :: [Maybe a] -> Maybe a
firstJust [] = Nothing
firstJust (Just value : _rest) = Just value
firstJust (Nothing : rest) = firstJust rest

{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.TuningBenchmark
  ( BenchmarkObservation (..)
  , collectAndPersistBenchmarkSelection
  , collectBenchmarkMeasurements
  , cudaBenchmarkCandidateRunner
  , cudaBenchmarkCandidateRunnerWithProbe
  , digestDoubleOutput
  , digestFloatOutput
  , linuxCpuBenchmarkCandidateRunner
  , measureBenchmarkObservation
  , metalBenchmarkCandidateRunner
  , metalBenchmarkCandidateRunnerWithProbe
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (Bits, shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64, Word8)
import GHC.Clock (getMonotonicTimeNSec)
import GHC.Float (castDoubleToWord64, castFloatToWord32)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource (renderRuntimeSource, runtimeSourcePayload)
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.Tuning
  ( BenchmarkMeasurement (..)
  , BenchmarkPlan (..)
  , TuningResult
  , tuningChoiceForResult
  , tuningSubstrate
  )
import JitML.Engines.TuningStore
  ( PersistedTuningSelection
  , persistSelectedMeasuredTuning
  )
import JitML.Env.Env (Env)
import JitML.Substrate (Substrate (..), renderSubstrate)

data BenchmarkObservation = BenchmarkObservation
  { benchmarkObservationLatencyMicros :: Int
  , benchmarkObservationOutputDigest :: Text
  }
  deriving stock (Eq, Show)

collectBenchmarkMeasurements
  :: BenchmarkPlan
  -> (TuningResult -> IO (Either Text BenchmarkObservation))
  -> IO (Either Text [BenchmarkMeasurement])
collectBenchmarkMeasurements plan runCandidate =
  collect (benchmarkPlanResults plan)
 where
  collect [] =
    pure (Right [])
  collect (candidate : rest) = do
    observed <- runCandidate candidate
    case observed of
      Left err ->
        pure $
          Left
            ( "benchmark candidate failed: "
                <> Cache.unTuningChoice (tuningChoiceForResult candidate)
                <> ": "
                <> err
            )
      Right observation -> do
        restMeasurements <- collect rest
        pure $
          ( BenchmarkMeasurement
              candidate
              (benchmarkObservationLatencyMicros observation)
              (benchmarkObservationOutputDigest observation)
              :
          )
            <$> restMeasurements

cudaBenchmarkCandidateRunner
  :: Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
cudaBenchmarkCandidateRunner =
  cudaBenchmarkCandidateRunnerWithProbe CudaRuntime.probeCudaRuntime

cudaBenchmarkCandidateRunnerWithProbe
  :: IO CudaRuntime.CudaRuntimeProbe
  -> Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
cudaBenchmarkCandidateRunnerWithProbe probeRuntime env kernelSpec kind input candidate
  | tuningSubstrate candidate /= LinuxCUDA =
      pure $
        Left
          ( "linux-cuda benchmark runner cannot execute "
              <> renderSubstrate (tuningSubstrate candidate)
              <> " candidate"
          )
  | otherwise = do
      probe <- probeRuntime
      if not (CudaRuntime.cudaRuntimeAvailable probe)
        then
          pure $
            Left
              ( "linux-cuda benchmark runner unavailable: "
                  <> renderCudaBenchmarkProbeSummary probe
              )
        else do
          start <- getMonotonicTimeNSec
          kernelResult <- CudaLocal.runCudaKernel env source hash input
          end <- getMonotonicTimeNSec
          pure $
            case kernelResult of
              Left err -> Left err
              Right kernelRun ->
                Right
                  BenchmarkObservation
                    { benchmarkObservationLatencyMicros = elapsedMicros start end
                    , benchmarkObservationOutputDigest =
                        digestFloatOutput (CudaLocal.cudaKernelOutput kernelRun)
                    }
 where
  tuningChoice = tuningChoiceForResult candidate
  source =
    renderRuntimeSource
      kernelSpec
      kind
      Cache.LinuxCUDA
      tuningChoice
  hash =
    Cache.cacheKey
      kernelSpec
      kind
      Cache.LinuxCUDA
      CudaLocal.cudaToolchainFingerprint
      (runtimeSourcePayload source)
      tuningChoice

metalBenchmarkCandidateRunner
  :: Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
metalBenchmarkCandidateRunner =
  metalBenchmarkCandidateRunnerWithProbe MetalRuntime.probeMetalRuntime

metalBenchmarkCandidateRunnerWithProbe
  :: IO MetalRuntime.MetalRuntimeProbe
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
metalBenchmarkCandidateRunnerWithProbe probeRuntime _kernelSpec _kind _input candidate
  | tuningSubstrate candidate /= AppleSilicon =
      pure $
        Left
          ( "apple-silicon benchmark runner cannot execute "
              <> renderSubstrate (tuningSubstrate candidate)
              <> " candidate"
          )
  | otherwise = do
      probe <- probeRuntime
      pure $
        if MetalRuntime.metalRuntimeAvailable probe
          then
            Left
              "apple-silicon benchmark runner reached an available runtime, but Metal FFI candidate execution is not implemented yet"
          else
            Left
              ( "apple-silicon benchmark runner unavailable: "
                  <> renderMetalBenchmarkProbeSummary probe
              )

collectAndPersistBenchmarkSelection
  :: FilePath
  -> Cache.Hash
  -> BenchmarkPlan
  -> (TuningResult -> IO (Either Text BenchmarkObservation))
  -> IO (Either Text PersistedTuningSelection)
collectAndPersistBenchmarkSelection buildRoot baseHash plan runCandidate = do
  measurementsResult <- collectBenchmarkMeasurements plan runCandidate
  case measurementsResult of
    Left err -> pure (Left err)
    Right measurements -> persistSelectedMeasuredTuning buildRoot baseHash plan measurements

linuxCpuBenchmarkCandidateRunner
  :: Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
linuxCpuBenchmarkCandidateRunner env kernelSpec kind input candidate
  | tuningSubstrate candidate /= LinuxCPU =
      pure $
        Left
          ( "linux-cpu benchmark runner cannot execute "
              <> renderSubstrate (tuningSubstrate candidate)
              <> " candidate"
          )
  | otherwise = do
      start <- getMonotonicTimeNSec
      kernelResult <- Local.runLinuxCpuKernel env source hash input
      end <- getMonotonicTimeNSec
      pure $
        case kernelResult of
          Left err -> Left err
          Right kernelRun ->
            Right
              BenchmarkObservation
                { benchmarkObservationLatencyMicros = elapsedMicros start end
                , benchmarkObservationOutputDigest =
                    digestFloatOutput (Local.linuxCpuKernelOutput kernelRun)
                }
 where
  tuningChoice = tuningChoiceForResult candidate
  source =
    renderRuntimeSource
      kernelSpec
      kind
      Cache.LinuxCPU
      tuningChoice
  hash =
    Cache.cacheKey
      kernelSpec
      kind
      Cache.LinuxCPU
      Local.linuxCpuToolchainFingerprint
      (runtimeSourcePayload source)
      tuningChoice

measureBenchmarkObservation :: (output -> Text) -> IO output -> IO BenchmarkObservation
measureBenchmarkObservation digestOutput action = do
  start <- getMonotonicTimeNSec
  output <- action
  end <- getMonotonicTimeNSec
  pure
    BenchmarkObservation
      { benchmarkObservationLatencyMicros = elapsedMicros start end
      , benchmarkObservationOutputDigest = digestOutput output
      }

digestFloatOutput :: [Float] -> Text
digestFloatOutput =
  sha256Hex . ByteString.concat . fmap (word32Le . castFloatToWord32)

digestDoubleOutput :: [Double] -> Text
digestDoubleOutput =
  sha256Hex . ByteString.concat . fmap (word64Le . castDoubleToWord64)

elapsedMicros :: Word64 -> Word64 -> Int
elapsedMicros start end =
  fromIntegral ((max end start - start) `div` 1000)

sha256Hex :: ByteString -> Text
sha256Hex =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash

byteHex :: Word8 -> String
byteHex byte =
  [ hexDigits !! fromIntegral (byte `div` 16)
  , hexDigits !! fromIntegral (byte `mod` 16)
  ]

hexDigits :: String
hexDigits = "0123456789abcdef"

word32Le :: Word32 -> ByteString
word32Le word =
  ByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    ]

word64Le :: Word64 -> ByteString
word64Le word =
  ByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    , byteAt 32 word
    , byteAt 40 word
    , byteAt 48 word
    , byteAt 56 word
    ]

byteAt :: (Bits word, Integral word) => Int -> word -> Word8
byteAt offset word =
  fromIntegral (word `shiftR` offset)

renderCudaBenchmarkProbeSummary :: CudaRuntime.CudaRuntimeProbe -> Text
renderCudaBenchmarkProbeSummary probe =
  "nvcc="
    <> renderMaybePresence (CudaRuntime.cudaRuntimeNvccVersion probe)
    <> " gpu_devices="
    <> Text.pack (show (length (CudaRuntime.cudaRuntimeGpuDevices probe)))
    <> " libcuda="
    <> renderBool
      ( CudaRuntime.cudaDriverLibraryVisible
          (CudaRuntime.cudaRuntimeLibraryVisibility probe)
      )
    <> " libcublas="
    <> renderBool
      ( CudaRuntime.cudaBlasLibraryVisible
          (CudaRuntime.cudaRuntimeLibraryVisibility probe)
      )
    <> " libcudnn="
    <> renderBool
      ( CudaRuntime.cudaDnnLibraryVisible
          (CudaRuntime.cudaRuntimeLibraryVisibility probe)
      )

renderMetalBenchmarkProbeSummary :: MetalRuntime.MetalRuntimeProbe -> Text
renderMetalBenchmarkProbeSummary probe =
  "swift="
    <> renderMaybePresence (MetalRuntime.metalRuntimeSwiftVersion probe)
    <> " metal="
    <> renderMaybePresence (MetalRuntime.metalRuntimeMetalCompilerPath probe)
    <> " swiftc="
    <> renderMaybePresence (MetalRuntime.metalRuntimeSwiftCompilerPath probe)
    <> " device="
    <> renderBool (MetalRuntime.metalRuntimeDeviceVisible probe)

renderMaybePresence :: Maybe a -> Text
renderMaybePresence Nothing = "missing"
renderMaybePresence (Just _value) = "present"

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

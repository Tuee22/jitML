{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.TuningBenchmark
  ( BenchmarkObservation (..)
  , BenchmarkCandidateRunner
  , candidateRunnerForSubstrate
  , collectAndPersistBenchmarkSelection
  , collectBenchmarkMeasurements
  , cudaBenchmarkCandidateRunner
  , cudaBenchmarkCandidateRunnerWithProbe
  , digestDoubleOutput
  , digestFloatOutput
  , ensureKernelArtifactWithBenchmarkTuning
  , ensureKernelArtifactWithBenchmarkTuningWithRunner
  , ensureKernelArtifactWithWeightedBenchmarkTuning
  , ensureTuningSelection
  , linuxCpuBenchmarkCandidateRunner
  , linuxCpuWeightedBenchmarkCandidateRunner
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

import Path (toFilePath)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource (renderRuntimeSource, runtimeSourcePayload)
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.Engine (engineForSubstrate)
import JitML.Engines.Loader (KernelArtifact, ensureKernelArtifact)
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalLocal qualified as MetalLocal
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.Tuning
  ( BenchmarkMeasurement (..)
  , BenchmarkPlan (..)
  , TuningResult
  , benchmarkPlan
  , knobSpace
  , tuningChoiceForResult
  , tuningSubstrate
  )
import JitML.Engines.TuningCache
  ( TuningCachePlan (..)
  , selectTuningCachePlan
  )
import JitML.Engines.TuningStore
  ( PersistedTuningSelection
  , persistSelectedMeasuredTuning
  )
import JitML.Env.Env (Env (..))
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

-- | Sprint 14.3 — live Metal benchmark candidate runner. Mirror of
-- `cudaBenchmarkCandidateRunner`: render the tuned Metal package for the
-- candidate, drive the Tart build + FFI launch through
-- `MetalLocal.runMetalKernel`, time the round-trip, and digest the float
-- output. Gated on host Metal device visibility (the build itself runs in
-- the `jitml-build` VM; the host only needs a visible device to execute the
-- produced dylib).
metalBenchmarkCandidateRunner
  :: Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
metalBenchmarkCandidateRunner =
  metalBenchmarkCandidateRunnerWithProbe MetalRuntime.probeMetalRuntime

metalBenchmarkCandidateRunnerWithProbe
  :: IO MetalRuntime.MetalRuntimeProbe
  -> Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
metalBenchmarkCandidateRunnerWithProbe probeRuntime env kernelSpec kind input candidate
  | tuningSubstrate candidate /= AppleSilicon =
      pure $
        Left
          ( "apple-silicon benchmark runner cannot execute "
              <> renderSubstrate (tuningSubstrate candidate)
              <> " candidate"
          )
  | otherwise = do
      probe <- probeRuntime
      if not (MetalRuntime.metalRuntimeDeviceVisible probe)
        then
          pure $
            Left
              ( "apple-silicon benchmark runner unavailable: "
                  <> renderMetalBenchmarkProbeSummary probe
              )
        else do
          start <- getMonotonicTimeNSec
          kernelResult <- MetalLocal.runMetalKernel env source hash input
          end <- getMonotonicTimeNSec
          pure $
            case kernelResult of
              Left err -> Left err
              Right kernelRun ->
                Right
                  BenchmarkObservation
                    { benchmarkObservationLatencyMicros = elapsedMicros start end
                    , benchmarkObservationOutputDigest =
                        digestFloatOutput (MetalLocal.metalKernelOutput kernelRun)
                    }
 where
  tuningChoice = tuningChoiceForResult candidate
  source =
    renderRuntimeSource
      kernelSpec
      kind
      Cache.AppleSilicon
      tuningChoice
  hash =
    Cache.cacheKey
      kernelSpec
      kind
      Cache.AppleSilicon
      MetalLocal.metalToolchainFingerprint
      (runtimeSourcePayload source)
      tuningChoice

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

type BenchmarkCandidateRunner =
  Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)

candidateRunnerForSubstrate :: Substrate -> BenchmarkCandidateRunner
candidateRunnerForSubstrate LinuxCPU = linuxCpuBenchmarkCandidateRunner
candidateRunnerForSubstrate LinuxCUDA = cudaBenchmarkCandidateRunner
candidateRunnerForSubstrate AppleSilicon = metalBenchmarkCandidateRunner

-- | Ensure the JIT cache artifact for @substrate@ exists, invoking the typed
-- benchmark candidate runner on the first cache miss so the persisted tuning
-- selection is set before the artifact is materialised.
--
-- This is the @collectAndPersistBenchmarkSelection@ → @TuningStore@ wiring
-- prescribed by Phase 7 Sprint 7.6: when no persisted selection exists for the
-- @(substrate, base-hash)@ pair, the substrate-specific candidate runner is
-- invoked across the deterministic benchmark plan, the lowest-latency
-- candidate is persisted, and the runtime source for the selected
-- 'TuningResult' is compiled into the cache. When a persisted selection
-- already exists, the tuned runtime source is used directly.
ensureKernelArtifactWithBenchmarkTuning
  :: Env
  -> Substrate
  -> Cache.KernelSpec
  -> Cache.Kind
  -> Cache.ToolchainFingerprint
  -> [Float]
  -> IO (Either Text KernelArtifact)
ensureKernelArtifactWithBenchmarkTuning env substrate =
  ensureKernelArtifactWithBenchmarkTuningWithRunner
    env
    substrate
    (candidateRunnerForSubstrate substrate)

ensureKernelArtifactWithBenchmarkTuningWithRunner
  :: Env
  -> Substrate
  -> BenchmarkCandidateRunner
  -> Cache.KernelSpec
  -> Cache.Kind
  -> Cache.ToolchainFingerprint
  -> [Float]
  -> IO (Either Text KernelArtifact)
ensureKernelArtifactWithBenchmarkTuningWithRunner env substrate runner kernelSpec kind fingerprint input = do
  tuned <- ensureTuningSelection env substrate runner kernelSpec kind fingerprint input
  case tuned of
    Left err -> pure (Left err)
    Right plan ->
      ensureKernelArtifact
        env
        (engineForSubstrate substrate)
        (tuningCacheRuntimeSource plan)
        (tuningCacheHash plan)

-- | Sprint 13.15 — weighted variant of `ensureKernelArtifactWithBenchmarkTuning`.
-- The first cache miss for a Linux CPU kernel drives the
-- `linuxCpuWeightedBenchmarkCandidateRunner` against the supplied input +
-- weights tensors (measuring the real weighted Dense2D body, not the
-- unweighted single-input fixture). The persisted `TuningChoice` therefore
-- reflects measurement against the same workload shape the JIT cache will see
-- at inference time. Only Linux CPU is wired here — Linux CUDA's weighted
-- benchmark candidate runner closes alongside the GPU passthrough validation
-- in Phase 15.
ensureKernelArtifactWithWeightedBenchmarkTuning
  :: Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> Cache.ToolchainFingerprint
  -> [Float]
  -> [Float]
  -> IO (Either Text KernelArtifact)
ensureKernelArtifactWithWeightedBenchmarkTuning env kernelSpec kind fingerprint input weights = do
  let runner runnerEnv runnerSpec runnerKind runnerInput =
        linuxCpuWeightedBenchmarkCandidateRunner
          runnerEnv
          runnerSpec
          runnerKind
          runnerInput
          weights
  ensureKernelArtifactWithBenchmarkTuningWithRunner
    env
    LinuxCPU
    runner
    kernelSpec
    kind
    fingerprint
    input

-- | The persistence half of the benchmark-tuning wiring: load the persisted
-- selection if one exists, otherwise run the supplied candidate runner across
-- the deterministic benchmark plan and persist the lowest-latency selection
-- before re-resolving the tuning plan.
ensureTuningSelection
  :: Env
  -> Substrate
  -> BenchmarkCandidateRunner
  -> Cache.KernelSpec
  -> Cache.Kind
  -> Cache.ToolchainFingerprint
  -> [Float]
  -> IO (Either Text TuningCachePlan)
ensureTuningSelection env substrate runner kernelSpec kind fingerprint input = do
  initialPlan <- selectTuningCachePlan buildRoot kernelSpec kind substrate fingerprint
  case initialPlan of
    Left err -> pure (Left err)
    Right plan
      | Just _ <- tuningCachePersistedSelection plan ->
          pure (Right plan)
      | otherwise -> do
          let candidatePlan = benchmarkPlan (knobSpace substrate)
          selectionResult <-
            collectAndPersistBenchmarkSelection
              buildRoot
              (tuningCacheBaseHash plan)
              candidatePlan
              (runner env kernelSpec kind input)
          case selectionResult of
            Left err -> pure (Left err)
            Right _persisted ->
              selectTuningCachePlan buildRoot kernelSpec kind substrate fingerprint
 where
  buildRoot = toFilePath (envCacheDir env)

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

-- | Sprint 13.15 — weighted variant of the Linux CPU benchmark candidate
-- runner. Drives `runLinuxCpuWeightedKernel` against the supplied input +
-- weights tensors so the first-cache-miss benchmark path measures the real
-- weighted Dense2D body (Sprint 13.11 ABI) instead of the single-tensor
-- unweighted body. The persisted `TuningChoice` therefore reflects measured
-- selection against the actual workload shape that production inference
-- will execute, not the smoke fixture.
linuxCpuWeightedBenchmarkCandidateRunner
  :: Env
  -> Cache.KernelSpec
  -> Cache.Kind
  -> [Float]
  -- ^ input tensor (flat row-major)
  -> [Float]
  -- ^ weight tensor (flat row-major)
  -> TuningResult
  -> IO (Either Text BenchmarkObservation)
linuxCpuWeightedBenchmarkCandidateRunner env kernelSpec kind input weights candidate
  | tuningSubstrate candidate /= LinuxCPU =
      pure $
        Left
          ( "linux-cpu weighted benchmark runner cannot execute "
              <> renderSubstrate (tuningSubstrate candidate)
              <> " candidate"
          )
  | otherwise = do
      start <- getMonotonicTimeNSec
      kernelResult <- Local.runLinuxCpuWeightedKernel env source hash input weights
      end <- getMonotonicTimeNSec
      pure $
        case kernelResult of
          Left err -> Left err
          Right kernelRun ->
            Right
              BenchmarkObservation
                { benchmarkObservationLatencyMicros = elapsedMicros start end
                , benchmarkObservationOutputDigest =
                    digestFloatOutput (Local.linuxCpuWeightedKernelOutput kernelRun)
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

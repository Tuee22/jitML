{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Local
  ( LinuxCpuKernelRun (..)
  , LinuxCpuWeightedKernelRun (..)
  , linuxCpuFamilyHash
  , linuxCpuFamilyRuntimeSource
  , linuxCpuIdentityHash
  , linuxCpuIdentityRuntimeSource
  , flattenLoadedWeights
  , runLinuxCpuCheckpointInference
  , runLinuxCpuFamilyKernel
  , runLinuxCpuFamilyKernelWithProbe
  , runLinuxCpuIdentityKernel
  , runLinuxCpuKernel
  , runLinuxCpuWeightedCheckpointInference
  , runLinuxCpuWeightedFamilyKernel
  , runLinuxCpuWeightedFamilyKernelWithProbe
  , runLinuxCpuWeightedKernel
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format
  ( ArchitectureMetadata (..)
  , CheckpointManifest (..)
  , validateSupervisedRuntimePlanForSubstrate
  )
import JitML.Checkpoint.Store
  ( LoadedWeightTensor (..)
  , runSupervisedGraphCheckpointInference
  )
import JitML.Codegen.KernelFamily (KernelFamily (..), kernelFamilyKernelSpec)
import JitML.Codegen.OneDnn (renderOneDnnFamilySource)
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , renderRuntimeSource
  , runtimeSourcePayload
  )
import JitML.Engines.Engine
  ( KernelHandle (..)
  , engineForSubstrate
  )
import JitML.Engines.Fingerprint qualified as Fingerprint
import JitML.Engines.LoadableKernel (loadAndRun, loadAndRunWeighted)
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactCompileCommand
  , kernelArtifactCompiled
  , kernelArtifactHandle
  , renderKernelArtifactError
  )
import JitML.Engines.MlpCheckpoint (runMlpCheckpointForwardWith)
import JitML.Engines.OneDnnRuntime qualified as OneDnnRuntime
import JitML.Env.Env (Env)
import JitML.Numerics.MlpOneDnn (mlpForwardOneDnn)
import JitML.Sub.Render (renderBool)
import JitML.Substrate (Substrate (..))

data LinuxCpuKernelRun = LinuxCpuKernelRun
  { linuxCpuKernelHandle :: KernelHandle
  , linuxCpuKernelInput :: [Float]
  , linuxCpuKernelOutput :: [Float]
  , linuxCpuKernelReportedFamily :: Text
  , linuxCpuKernelCompileCommand :: Text
  , linuxCpuKernelCompiled :: Bool
  }
  deriving stock (Eq, Show)

-- | Outcome of a weighted-kernel run. The `linuxCpuWeightedKernelWeights`
-- field records the flattened row-major weight buffer that was passed
-- to the FFI; tests + audits can compare against the source manifest.
data LinuxCpuWeightedKernelRun = LinuxCpuWeightedKernelRun
  { linuxCpuWeightedKernelHandle :: KernelHandle
  , linuxCpuWeightedKernelInput :: [Float]
  , linuxCpuWeightedKernelOutput :: [Float]
  , linuxCpuWeightedKernelWeights :: [Float]
  , linuxCpuWeightedKernelReportedFamily :: Text
  , linuxCpuWeightedKernelCompileCommand :: Text
  , linuxCpuWeightedKernelCompiled :: Bool
  }
  deriving stock (Eq, Show)

linuxCpuIdentityRuntimeSource :: RuntimeSource
linuxCpuIdentityRuntimeSource =
  renderRuntimeSource linuxCpuIdentityKernel Cache.Inference Cache.LinuxCPU Cache.defaultTuningChoice

linuxCpuIdentityHash :: Cache.Hash
linuxCpuIdentityHash =
  Cache.cacheKey
    linuxCpuIdentityKernel
    Cache.Inference
    Cache.LinuxCPU
    (Fingerprint.engineFamilyToolchainFingerprint LinuxCPU)
    (runtimeSourcePayload linuxCpuIdentityRuntimeSource)
    Cache.defaultTuningChoice

runLinuxCpuIdentityKernel :: Env -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuIdentityKernel env =
  runLinuxCpuKernel env linuxCpuIdentityRuntimeSource linuxCpuIdentityHash

linuxCpuFamilyRuntimeSource :: KernelFamily -> RuntimeSource
linuxCpuFamilyRuntimeSource family =
  GeneratedOneDnnSource
    { runtimeSourceKernel = kernelFamilyKernelSpec family
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles =
        renderOneDnnFamilySource
          family
          (kernelFamilyKernelSpec family)
          Cache.Inference
          Cache.defaultTuningChoice
    }

linuxCpuFamilyHash :: KernelFamily -> Cache.Hash
linuxCpuFamilyHash family =
  Cache.cacheKey
    (kernelFamilyKernelSpec family)
    Cache.Inference
    Cache.LinuxCPU
    (Fingerprint.engineFamilyToolchainFingerprint LinuxCPU)
    (runtimeSourcePayload (linuxCpuFamilyRuntimeSource family))
    Cache.defaultTuningChoice

runLinuxCpuFamilyKernel :: Env -> KernelFamily -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuFamilyKernel =
  runLinuxCpuFamilyKernelWithProbe OneDnnRuntime.probeOneDnnRuntime

-- | Probe-gated family entry, mirroring the CUDA and Metal drivers. Sprint
-- `79.1` added it: this lane was the only one that went straight to @dlopen@
-- with no availability probe at all, even though `probeOneDnnRuntime` already
-- existed. A missing oneDNN now fails closed with a summary instead of
-- surfacing as a dynamic-linker exception.
runLinuxCpuFamilyKernelWithProbe
  :: IO OneDnnRuntime.OneDnnRuntimeProbe
  -> Env
  -> KernelFamily
  -> [Float]
  -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuFamilyKernelWithProbe probeRuntime env family input = do
  probe <- probeRuntime
  if OneDnnRuntime.oneDnnRuntimeAvailable probe
    then runLinuxCpuKernel env (linuxCpuFamilyRuntimeSource family) (linuxCpuFamilyHash family) input
    else pure (Left ("linux-cpu oneDNN runtime unavailable: " <> renderOneDnnUnavailableSummary probe))

renderOneDnnUnavailableSummary :: OneDnnRuntime.OneDnnRuntimeProbe -> Text
renderOneDnnUnavailableSummary probe =
  Text.intercalate
    " "
    [ "pkg_config=" <> fromMaybe "missing" (OneDnnRuntime.oneDnnRuntimePkgConfigName probe)
    , "header=" <> fromMaybe "missing" (OneDnnRuntime.oneDnnRuntimeHeaderPath probe)
    , "libdnnl=" <> renderBool (OneDnnRuntime.oneDnnRuntimeLibraryVisible probe)
    ]

runLinuxCpuCheckpointInference :: Env -> CheckpointManifest -> [Double] -> IO (Either Text [Double])
runLinuxCpuCheckpointInference env manifest input =
  case manifestSupervisedRuntime manifest of
    Just _ ->
      pure (Left "V2 supervised inference requires exact persisted weights")
    Nothing -> do
      kernelResult <- runLinuxCpuIdentityKernel env (fmap realToFrac input)
      pure $
        case kernelResult of
          Left err -> Left err
          Right kernelRun ->
            -- Sprint 10.5 — return the faithful kernel output; the former
            -- `+ nTensors/100` synthetic offset (a fabricated inference value) is
            -- removed. The real weighted read path is
            -- 'runLinuxCpuWeightedCheckpointInference'.
            Right (fmap realToFrac (linuxCpuKernelOutput kernelRun))

-- | Sprint 13.11 — drive the live `jitml_weighted_kernel` ABI for a
-- checkpoint-supplied weight tensor list. Routes through Dense2D's real
-- GEMM body for now (the first family with a per-family weighted body);
-- other families pass through the identity body inside the kernel until
-- their per-family weighted paths land. The flattened weights buffer is
-- derived from `LoadedWeightTensor` via `flattenLoadedWeights`.
runLinuxCpuWeightedCheckpointInference
  :: Env
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runLinuxCpuWeightedCheckpointInference env manifest weights input = do
  case traverse (validateSupervisedRuntimePlanForSubstrate LinuxCPU) (manifestSupervisedRuntime manifest) of
    Left err -> pure (Left ("V2 linux-cpu PlanId incompatibility: " <> err))
    Right _
      -- Phase 240: a supervised-graph checkpoint reloads its single trained
      -- LayerGraph envelope, refines it (a tampered or structurally malformed
      -- graph fails closed), and serves it through the PURE reference executor
      -- (runLayerGraph, with the input/output transforms applied OUTSIDE the
      -- graph) — substrate-independent and bit-identical to the linux-cuda and
      -- apple-silicon serving paths. There is no SupervisedRuntime executor and
      -- no fallback graph on the supervised path. Weight-only manifests (no
      -- supervised runtime and no layer graph) take the MLP/kernel fallback.
      | Just _ <- architectureLayerGraph (manifestArchitecture manifest) ->
          runSupervisedGraphCheckpointInference manifest weights input
      | otherwise -> mlpFallback
 where
  mlpFallback = do
    mlpResult <- runMlpCheckpointForwardWith (mlpForwardOneDnn env) manifest weights input
    case mlpResult of
      Just result -> pure result
      Nothing -> do
        let flatWeights = flattenLoadedWeights weights
        kernelResult <-
          runLinuxCpuWeightedFamilyKernel
            env
            Dense2D
            (fmap realToFrac input)
            flatWeights
        pure $
          case kernelResult of
            Left err -> Left err
            Right kernelRun ->
              Right (fmap realToFrac (linuxCpuWeightedKernelOutput kernelRun))

-- | Flatten a list of `LoadedWeightTensor` into a row-major Float
-- buffer suitable for the `jitml_weighted_kernel` ABI. Tensors are
-- concatenated in manifest order; per-tensor shape information is
-- intentionally lost at this layer because the kernel reshapes
-- whatever buffer it receives based on the family. Per-family
-- reshaping discipline lives in the generated oneDNN code.
flattenLoadedWeights :: [LoadedWeightTensor] -> [Float]
flattenLoadedWeights =
  fmap realToFrac . concatMap loadedWeightValues

runLinuxCpuKernel
  :: Env -> RuntimeSource -> Cache.Hash -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuKernel env source hash input = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("linux-cpu compile failed: " <> renderKernelArtifactError err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      (reportedFamily, output) <- loadAndRun artifactPath input
      pure
        ( Right
            LinuxCpuKernelRun
              { linuxCpuKernelHandle = handle
              , linuxCpuKernelInput = input
              , linuxCpuKernelOutput = output
              , linuxCpuKernelReportedFamily = reportedFamily
              , linuxCpuKernelCompileCommand = kernelArtifactCompileCommand artifact
              , linuxCpuKernelCompiled = kernelArtifactCompiled artifact
              }
        )
 where
  engine = engineForSubstrate LinuxCPU

-- | Sprint 13.11 — load the family's compiled `.so` and call into the
-- weighted ABI symbol `jitml_weighted_kernel` with the caller's input +
-- flat row-major weights buffer. The family runtime source is the same
-- as the unweighted family path (Sprint 7.6's `KernelFamily`-aware
-- codegen), only the symbol resolved at load time differs.
runLinuxCpuWeightedFamilyKernel
  :: Env
  -> KernelFamily
  -> [Float]
  -> [Float]
  -> IO (Either Text LinuxCpuWeightedKernelRun)
runLinuxCpuWeightedFamilyKernel =
  runLinuxCpuWeightedFamilyKernelWithProbe OneDnnRuntime.probeOneDnnRuntime

runLinuxCpuWeightedFamilyKernelWithProbe
  :: IO OneDnnRuntime.OneDnnRuntimeProbe
  -> Env
  -> KernelFamily
  -> [Float]
  -> [Float]
  -> IO (Either Text LinuxCpuWeightedKernelRun)
runLinuxCpuWeightedFamilyKernelWithProbe probeRuntime env family input weights = do
  probe <- probeRuntime
  if OneDnnRuntime.oneDnnRuntimeAvailable probe
    then
      runLinuxCpuWeightedKernel
        env
        (linuxCpuFamilyRuntimeSource family)
        (linuxCpuFamilyHash family)
        input
        weights
    else pure (Left ("linux-cpu oneDNN runtime unavailable: " <> renderOneDnnUnavailableSummary probe))

-- | Generic weighted-kernel driver: ensure the artifact, look up the
-- three core symbols + the new `jitml_weighted_kernel` symbol, marshal
-- the input and weights buffers across the FFI, and copy the output
-- back. Returns the compile metadata + reported family alongside the
-- output so callers can attribute results in tests / audits.
runLinuxCpuWeightedKernel
  :: Env
  -> RuntimeSource
  -> Cache.Hash
  -> [Float]
  -> [Float]
  -> IO (Either Text LinuxCpuWeightedKernelRun)
runLinuxCpuWeightedKernel env source hash input weights = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("linux-cpu weighted compile failed: " <> renderKernelArtifactError err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      (reportedFamily, output) <- loadAndRunWeighted artifactPath input weights
      pure
        ( Right
            LinuxCpuWeightedKernelRun
              { linuxCpuWeightedKernelHandle = handle
              , linuxCpuWeightedKernelInput = input
              , linuxCpuWeightedKernelOutput = output
              , linuxCpuWeightedKernelWeights = weights
              , linuxCpuWeightedKernelReportedFamily = reportedFamily
              , linuxCpuWeightedKernelCompileCommand = kernelArtifactCompileCommand artifact
              , linuxCpuWeightedKernelCompiled = kernelArtifactCompiled artifact
              }
        )
 where
  engine = engineForSubstrate LinuxCPU

linuxCpuIdentityKernel :: Cache.KernelSpec
linuxCpuIdentityKernel =
  Cache.KernelSpec "jitml-linux-cpu:identity"

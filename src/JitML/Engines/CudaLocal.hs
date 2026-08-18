{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.CudaLocal
  ( CudaKernelRun (..)
  , CudaWeightedKernelRun (..)
  , cudaFamilyHash
  , cudaFamilyRuntimeSource
  , runCudaCheckpointInference
  , runCudaFamilyKernel
  , runCudaFamilyKernelWithProbe
  , runCudaKernel
  , runCudaWeightedCheckpointInference
  , runCudaWeightedFamilyKernel
  , runCudaWeightedFamilyKernelWithProbe
  , runCudaWeightedKernel
  )
where

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
import JitML.Codegen.Cuda (renderCudaFamilySource)
import JitML.Codegen.KernelFamily (KernelFamily (..), kernelFamilyKernelSpec)
import JitML.Codegen.RuntimeSource (KernelProgram (..), RuntimeSource (..), runtimeSourcePayload)
import JitML.Engines.CudaRuntime qualified as CudaRuntime
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
import JitML.Env.Env (Env)
import JitML.Numerics.MlpCuda (mlpForwardCuda)
import JitML.Sub.Render (renderBool)
import JitML.Substrate (Substrate (..))

data CudaKernelRun = CudaKernelRun
  { cudaKernelHandle :: KernelHandle
  , cudaKernelInput :: [Float]
  , cudaKernelOutput :: [Float]
  , cudaKernelReportedFamily :: Text
  , cudaKernelCompileCommand :: Text
  , cudaKernelCompiled :: Bool
  }
  deriving stock (Eq, Show)

-- | Outcome of a CUDA weighted-kernel run. Same shape as
-- `CudaKernelRun` plus the flattened weight buffer that was uploaded
-- to the device.
data CudaWeightedKernelRun = CudaWeightedKernelRun
  { cudaWeightedKernelHandle :: KernelHandle
  , cudaWeightedKernelInput :: [Float]
  , cudaWeightedKernelOutput :: [Float]
  , cudaWeightedKernelWeights :: [Float]
  , cudaWeightedKernelReportedFamily :: Text
  , cudaWeightedKernelCompileCommand :: Text
  , cudaWeightedKernelCompiled :: Bool
  }
  deriving stock (Eq, Show)

cudaFamilyRuntimeSource :: KernelFamily -> RuntimeSource
cudaFamilyRuntimeSource family =
  GeneratedCudaSource
    { runtimeSourceKernel = kernelFamilyKernelSpec family
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceProgramKind = FamilyProgram
    , runtimeSourceFiles =
        renderCudaFamilySource
          family
          (kernelFamilyKernelSpec family)
          Cache.Inference
          Cache.defaultTuningChoice
    }

cudaFamilyHash :: KernelFamily -> Cache.Hash
cudaFamilyHash family =
  Cache.cacheKey
    (kernelFamilyKernelSpec family)
    Cache.Inference
    Cache.LinuxCUDA
    (Fingerprint.engineFamilyToolchainFingerprint LinuxCUDA)
    (runtimeSourcePayload (cudaFamilyRuntimeSource family))
    Cache.defaultTuningChoice

runCudaFamilyKernel :: Env -> KernelFamily -> [Float] -> IO (Either Text CudaKernelRun)
runCudaFamilyKernel =
  runCudaFamilyKernelWithProbe CudaRuntime.probeCudaRuntime

runCudaFamilyKernelWithProbe
  :: IO CudaRuntime.CudaRuntimeProbe
  -> Env
  -> KernelFamily
  -> [Float]
  -> IO (Either Text CudaKernelRun)
runCudaFamilyKernelWithProbe probeRuntime env family input = do
  probe <- probeRuntime
  if CudaRuntime.cudaRuntimeAvailable probe
    then runCudaKernel env (cudaFamilyRuntimeSource family) (cudaFamilyHash family) input
    else pure (Left ("linux-cuda runtime unavailable: " <> renderCudaUnavailableSummary probe))

runCudaCheckpointInference :: Env -> CheckpointManifest -> [Double] -> IO (Either Text [Double])
runCudaCheckpointInference env manifest input =
  case manifestSupervisedRuntime manifest of
    Just _ ->
      pure (Left "V2 supervised inference requires exact persisted weights")
    Nothing -> do
      kernelResult <- runCudaFamilyKernel env Identity (fmap realToFrac input)
      pure $
        case kernelResult of
          Left err -> Left err
          Right kernelRun ->
            -- Sprint 10.5 — faithful kernel output; the synthetic `+ nTensors/100`
            -- offset is removed (real weighted read: 'runCudaWeightedCheckpointInference').
            Right (fmap realToFrac (cudaKernelOutput kernelRun))

-- | Sprint 13.11 — CUDA weighted checkpoint inference. Mirror of the
-- Linux CPU path. Routes through `runCudaWeightedFamilyKernel` against
-- Dense2D and replaces the prior bias-based smoke fixture.
runCudaWeightedCheckpointInference
  :: Env
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runCudaWeightedCheckpointInference env manifest weights input = do
  case traverse (validateSupervisedRuntimePlanForSubstrate LinuxCUDA) (manifestSupervisedRuntime manifest) of
    Left err -> pure (Left ("V2 linux-cuda PlanId incompatibility: " <> err))
    Right _
      -- Phase 239: a supervised-graph checkpoint serves the trained dense
      -- LayerGraph directly (reconstruct + inject + runLayerGraph). Weight-only
      -- manifests (no supervised runtime and no layer graph) take the MLP/kernel
      -- fallback; the V2 token-runtime serving path has been retired.
      | Just _ <- architectureLayerGraph (manifestArchitecture manifest) ->
          runSupervisedGraphCheckpointInference manifest weights input
      | otherwise -> mlpFallback
 where
  mlpFallback = do
    mlpResult <- runMlpCheckpointForwardWith (mlpForwardCuda env) manifest weights input
    case mlpResult of
      Just result -> pure result
      Nothing -> do
        let flatWeights = fmap realToFrac (concatMap loadedWeightValues weights)
        kernelResult <-
          runCudaWeightedFamilyKernel env Dense2D (fmap realToFrac input) flatWeights
        pure $
          case kernelResult of
            Left err -> Left err
            Right kernelRun ->
              Right (fmap realToFrac (cudaWeightedKernelOutput kernelRun))

runCudaWeightedFamilyKernel
  :: Env
  -> KernelFamily
  -> [Float]
  -> [Float]
  -> IO (Either Text CudaWeightedKernelRun)
runCudaWeightedFamilyKernel =
  runCudaWeightedFamilyKernelWithProbe CudaRuntime.probeCudaRuntime

runCudaWeightedFamilyKernelWithProbe
  :: IO CudaRuntime.CudaRuntimeProbe
  -> Env
  -> KernelFamily
  -> [Float]
  -> [Float]
  -> IO (Either Text CudaWeightedKernelRun)
runCudaWeightedFamilyKernelWithProbe probeRuntime env family input weights = do
  probe <- probeRuntime
  if CudaRuntime.cudaRuntimeAvailable probe
    then
      runCudaWeightedKernel
        env
        (cudaFamilyRuntimeSource family)
        (cudaFamilyHash family)
        input
        weights
    else
      pure
        ( Left
            ( "linux-cuda runtime unavailable: "
                <> renderCudaUnavailableSummary probe
            )
        )

-- | Sprint 13.11 — load the family `.so`, resolve the new
-- `jitml_weighted_kernel` symbol, marshal the input + weights buffers
-- across the FFI (the device-side helper allocates GPU memory and
-- launches the family-specific weighted kernel), and return the host
-- output alongside `CudaWeightedKernelRun` metadata.
runCudaWeightedKernel
  :: Env
  -> RuntimeSource
  -> Cache.Hash
  -> [Float]
  -> [Float]
  -> IO (Either Text CudaWeightedKernelRun)
runCudaWeightedKernel env source hash input weights = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("linux-cuda weighted compile failed: " <> renderKernelArtifactError err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      (reportedFamily, output) <- loadAndRunWeighted artifactPath input weights
      pure
        ( Right
            CudaWeightedKernelRun
              { cudaWeightedKernelHandle = handle
              , cudaWeightedKernelInput = input
              , cudaWeightedKernelOutput = output
              , cudaWeightedKernelWeights = weights
              , cudaWeightedKernelReportedFamily = reportedFamily
              , cudaWeightedKernelCompileCommand = kernelArtifactCompileCommand artifact
              , cudaWeightedKernelCompiled = kernelArtifactCompiled artifact
              }
        )
 where
  engine = engineForSubstrate LinuxCUDA

runCudaKernel
  :: Env -> RuntimeSource -> Cache.Hash -> [Float] -> IO (Either Text CudaKernelRun)
runCudaKernel env source hash input = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("linux-cuda compile failed: " <> renderKernelArtifactError err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      (reportedFamily, output) <- loadAndRun artifactPath input
      pure
        ( Right
            CudaKernelRun
              { cudaKernelHandle = handle
              , cudaKernelInput = input
              , cudaKernelOutput = output
              , cudaKernelReportedFamily = reportedFamily
              , cudaKernelCompileCommand = kernelArtifactCompileCommand artifact
              , cudaKernelCompiled = kernelArtifactCompiled artifact
              }
        )
 where
  engine = engineForSubstrate LinuxCUDA

renderCudaUnavailableSummary :: CudaRuntime.CudaRuntimeProbe -> Text
renderCudaUnavailableSummary probe =
  Text.intercalate
    " "
    [ "nvcc=" <> maybe "missing" (const "present") (CudaRuntime.cudaRuntimeNvccVersion probe)
    , "gpu_devices=" <> Text.pack (show (length (CudaRuntime.cudaRuntimeGpuDevices probe)))
    , "libcuda="
        <> renderBool
          ( CudaRuntime.cudaDriverLibraryVisible
              (CudaRuntime.cudaRuntimeLibraryVisibility probe)
          )
    , "libcublas="
        <> renderBool
          ( CudaRuntime.cudaBlasLibraryVisible
              (CudaRuntime.cudaRuntimeLibraryVisibility probe)
          )
    , "libcudnn="
        <> renderBool
          ( CudaRuntime.cudaDnnLibraryVisible
              (CudaRuntime.cudaRuntimeLibraryVisibility probe)
          )
    ]

{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.CudaLocal
  ( CudaKernelRun (..)
  , CudaWeightedKernelRun (..)
  , cudaFamilyHash
  , cudaFamilyRuntimeSource
  , cudaToolchainFingerprint
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
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CFloat (..), CSize (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (CheckpointManifest)
import JitML.Checkpoint.Store (LoadedWeightTensor (..))
import JitML.Codegen.Cuda (renderCudaFamilySource)
import JitML.Codegen.KernelFamily (KernelFamily (..), kernelFamilyKernelSpec)
import JitML.Codegen.RuntimeSource (RuntimeSource (..), runtimeSourcePayload)
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.Engine
  ( KernelHandle (..)
  , engineForSubstrate
  )
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactCompileCommand
  , kernelArtifactCompiled
  , kernelArtifactHandle
  , withKernelSymbol
  )
import JitML.Engines.MlpCheckpoint (runMlpCheckpointForwardWith)
import JitML.Env.Env (Env)
import JitML.Numerics.MlpCuda (mlpForwardCuda)
import JitML.Substrate (Substrate (..))

type KernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> IO ()

-- Sprint 13.11 — CUDA weighted ABI mirrors the Linux CPU shape: output,
-- input, input_count, weights, weights_count.
type WeightedKernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> Ptr CFloat -> CSize -> IO ()

type KernelFamilyFunction =
  IO CString

type KernelOutputCountFunction =
  CSize -> IO CSize

foreign import ccall "dynamic" mkKernelFunction :: FunPtr KernelFunction -> KernelFunction

foreign import ccall "dynamic"
  mkWeightedKernelFunction :: FunPtr WeightedKernelFunction -> WeightedKernelFunction

foreign import ccall "dynamic"
  mkKernelFamilyFunction :: FunPtr KernelFamilyFunction -> KernelFamilyFunction

foreign import ccall "dynamic"
  mkKernelOutputCountFunction :: FunPtr KernelOutputCountFunction -> KernelOutputCountFunction

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
    cudaToolchainFingerprint
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
runCudaCheckpointInference env _manifest input = do
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
      pure (Left ("linux-cuda weighted compile failed: " <> err))
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
      pure (Left ("linux-cuda compile failed: " <> err))
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

loadAndRun :: FilePath -> [Float] -> IO (Text, [Float])
loadAndRun artifactPath input =
  withKernelSymbol artifactPath "jitml_kernel_family_name" $ \familySymbol ->
    withKernelSymbol artifactPath "jitml_kernel_output_count" $ \outputCountSymbol ->
      withKernelSymbol artifactPath "jitml_kernel" $ \kernelSymbol -> do
        reportedFamily <- Text.pack <$> (mkKernelFamilyFunction familySymbol >>= peekCString)
        let kernel = mkKernelFunction kernelSymbol
            outputCount = mkKernelOutputCountFunction outputCountSymbol
            cInput = fmap CFloat input
            inputCount = length input
        outputLength <- fromIntegral <$> outputCount (fromIntegral inputCount)
        output <-
          withArray cInput $ \inputPtr ->
            allocaArray outputLength $ \outputPtr -> do
              kernel outputPtr inputPtr (fromIntegral inputCount)
              fmap (\(CFloat value) -> value) <$> peekArray outputLength outputPtr
        pure (reportedFamily, output)

-- | Sprint 13.11 — weighted variant of `loadAndRun`. Resolves the same
-- three metadata symbols, plus `jitml_weighted_kernel`, and threads the
-- input + weights buffers across the FFI to the device-side helper.
loadAndRunWeighted :: FilePath -> [Float] -> [Float] -> IO (Text, [Float])
loadAndRunWeighted artifactPath input weights =
  withKernelSymbol artifactPath "jitml_kernel_family_name" $ \familySymbol ->
    withKernelSymbol artifactPath "jitml_kernel_output_count" $ \outputCountSymbol ->
      withKernelSymbol artifactPath "jitml_weighted_kernel" $ \kernelSymbol -> do
        reportedFamily <- Text.pack <$> (mkKernelFamilyFunction familySymbol >>= peekCString)
        let kernel = mkWeightedKernelFunction kernelSymbol
            outputCount = mkKernelOutputCountFunction outputCountSymbol
            cInput = fmap CFloat input
            cWeights = fmap CFloat weights
            inputCount = length input
            weightsCount = length weights
        outputLength <- fromIntegral <$> outputCount (fromIntegral inputCount)
        output <-
          withArray cInput $ \inputPtr ->
            withArray cWeights $ \weightsPtr ->
              allocaArray outputLength $ \outputPtr -> do
                kernel
                  outputPtr
                  inputPtr
                  (fromIntegral inputCount)
                  weightsPtr
                  (fromIntegral weightsCount)
                fmap (\(CFloat value) -> value) <$> peekArray outputLength outputPtr
        pure (reportedFamily, output)

cudaToolchainFingerprint :: Cache.ToolchainFingerprint
cudaToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "nvcc-shared"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "sm=70"
        , "--use_fast_math=false"
        , "tf32=disabled"
        , "abi=extern-c-host-wrapper"
        , "link=-lcudart,-lcublas,-lcudnn"
        , "cublas=v2-deterministic-gemm"
        , "cudnn=algo-implicit-precomp-gemm"
        , "jitml_kernel(float*,const float*,size_t)"
        , "jitml_kernel_family_name(void)"
        , "jitml_kernel_output_count(size_t)"
        , -- Sprint 13.11: weighted CUDA ABI. Dense2D / Conv2D / Conv3D /
          -- BatchNorm / LayerNorm / MHA / Embedding now drive real device
          -- kernels (full set landed 2026-05-27). The "all-families" tag
          -- bumps cache invalidation so the JIT cache picks up the real
          -- weighted device kernels instead of the prior unweighted
          -- fall-through.
          "jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)"
        , "weighted-bodies=all-families"
        ]
    )

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

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

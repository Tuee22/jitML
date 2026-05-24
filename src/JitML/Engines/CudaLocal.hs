{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.CudaLocal
  ( CudaKernelRun (..)
  , cudaFamilyHash
  , cudaFamilyRuntimeSource
  , cudaToolchainFingerprint
  , runCudaCheckpointInference
  , runCudaFamilyKernel
  , runCudaFamilyKernelWithProbe
  , runCudaKernel
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
import JitML.Checkpoint.Format (CheckpointManifest, weightOnlyTensors)
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
import JitML.Env.Env (Env)
import JitML.Substrate (Substrate (..))

type KernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> IO ()

type KernelFamilyFunction =
  IO CString

type KernelOutputCountFunction =
  CSize -> IO CSize

foreign import ccall "dynamic" mkKernelFunction :: FunPtr KernelFunction -> KernelFunction

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
runCudaCheckpointInference env manifest input = do
  kernelResult <- runCudaFamilyKernel env Identity (fmap realToFrac input)
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        let bias = fromIntegral (length (weightOnlyTensors manifest)) / 100.0
         in Right (fmap ((+ bias) . realToFrac) (cudaKernelOutput kernelRun))

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
        , "jitml_kernel(float*,const float*,size_t)"
        , "jitml_kernel_family_name(void)"
        , "jitml_kernel_output_count(size_t)"
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

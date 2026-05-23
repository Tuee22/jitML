{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Local
  ( LinuxCpuKernelRun (..)
  , linuxCpuFamilyHash
  , linuxCpuFamilyRuntimeSource
  , linuxCpuIdentityHash
  , linuxCpuIdentityRuntimeSource
  , linuxCpuToolchainFingerprint
  , runLinuxCpuCheckpointInference
  , runLinuxCpuFamilyKernel
  , runLinuxCpuWeightedCheckpointInference
  , runLinuxCpuKernel
  , runLinuxCpuIdentityKernel
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
import JitML.Checkpoint.Store (LoadedWeightTensor (..))
import JitML.Codegen.KernelFamily (KernelFamily, kernelFamilyKernelSpec)
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

data LinuxCpuKernelRun = LinuxCpuKernelRun
  { linuxCpuKernelHandle :: KernelHandle
  , linuxCpuKernelInput :: [Float]
  , linuxCpuKernelOutput :: [Float]
  , linuxCpuKernelReportedFamily :: Text
  , linuxCpuKernelCompileCommand :: Text
  , linuxCpuKernelCompiled :: Bool
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
    linuxCpuToolchainFingerprint
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
    linuxCpuToolchainFingerprint
    (runtimeSourcePayload (linuxCpuFamilyRuntimeSource family))
    Cache.defaultTuningChoice

runLinuxCpuFamilyKernel :: Env -> KernelFamily -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuFamilyKernel env family =
  runLinuxCpuKernel env (linuxCpuFamilyRuntimeSource family) (linuxCpuFamilyHash family)

runLinuxCpuCheckpointInference :: Env -> CheckpointManifest -> [Double] -> IO (Either Text [Double])
runLinuxCpuCheckpointInference env manifest input = do
  kernelResult <- runLinuxCpuIdentityKernel env (fmap realToFrac input)
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        let bias = fromIntegral (length (weightOnlyTensors manifest)) / 100.0
         in Right (fmap ((+ bias) . realToFrac) (linuxCpuKernelOutput kernelRun))

runLinuxCpuWeightedCheckpointInference
  :: Env
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runLinuxCpuWeightedCheckpointInference env _manifest weights input = do
  kernelResult <- runLinuxCpuIdentityKernel env (fmap realToFrac input)
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        Right (fmap ((+ weightBias weights) . realToFrac) (linuxCpuKernelOutput kernelRun))

weightBias :: [LoadedWeightTensor] -> Double
weightBias loadedWeights =
  let values = concatMap loadedWeightValues loadedWeights
   in case values of
        [] -> 0
        _ -> sum values / fromIntegral (length values) / 100.0

runLinuxCpuKernel
  :: Env -> RuntimeSource -> Cache.Hash -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuKernel env source hash input = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("linux-cpu compile failed: " <> err))
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

linuxCpuIdentityKernel :: Cache.KernelSpec
linuxCpuIdentityKernel =
  Cache.KernelSpec "jitml-linux-cpu:identity"

linuxCpuToolchainFingerprint :: Cache.ToolchainFingerprint
linuxCpuToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "g++-shared"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "reduction-block=256"
        , "abi=extern-c"
        , "jitml_kernel(float*,const float*,size_t)"
        , "jitml_kernel_family_name(void)"
        , "jitml_kernel_output_count(size_t)"
        ]
    )

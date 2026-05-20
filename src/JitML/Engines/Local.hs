{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Local
  ( LinuxCpuKernelRun (..)
  , linuxCpuIdentityHash
  , linuxCpuIdentityRuntimeSource
  , runLinuxCpuCheckpointInference
  , runLinuxCpuKernel
  , runLinuxCpuIdentityKernel
  )
where

import Control.Exception (bracket)
import Control.Monad (void)
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.Types (CFloat (..), CSize (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Posix.DynamicLinker (RTLDFlags (RTLD_NOW), dlclose, dlopen, dlsym)

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (CheckpointManifest, weightOnlyTensors)
import JitML.Codegen.RuntimeSource
  ( RuntimeSource
  , materializeRuntimeSource
  , renderRuntimeSource
  , runtimeSourcePayload
  )
import JitML.Engines.Engine
  ( KernelHandle (..)
  , compileSubprocess
  , engineForSubstrate
  , kernelHandleFor
  )
import JitML.Env.Env (Env)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Substrate (Substrate (..))

type KernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> IO ()

foreign import ccall "dynamic" mkKernelFunction :: FunPtr KernelFunction -> KernelFunction

data LinuxCpuKernelRun = LinuxCpuKernelRun
  { linuxCpuKernelHandle :: KernelHandle
  , linuxCpuKernelInput :: [Float]
  , linuxCpuKernelOutput :: [Float]
  , linuxCpuKernelCompileCommand :: Text
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
    linuxCpuFingerprint
    (runtimeSourcePayload linuxCpuIdentityRuntimeSource)
    Cache.defaultTuningChoice

runLinuxCpuIdentityKernel :: Env -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuIdentityKernel env =
  runLinuxCpuKernel env linuxCpuIdentityRuntimeSource linuxCpuIdentityHash

runLinuxCpuCheckpointInference :: Env -> CheckpointManifest -> [Double] -> IO (Either Text [Double])
runLinuxCpuCheckpointInference env manifest input = do
  kernelResult <- runLinuxCpuIdentityKernel env (fmap realToFrac input)
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        let bias = fromIntegral (length (weightOnlyTensors manifest)) / 100.0
         in Right (fmap ((+ bias) . realToFrac) (linuxCpuKernelOutput kernelRun))

runLinuxCpuKernel
  :: Env -> RuntimeSource -> Cache.Hash -> [Float] -> IO (Either Text LinuxCpuKernelRun)
runLinuxCpuKernel env source hash input = do
  void (materializeRuntimeSource env source hash)
  createDirectoryIfMissing True (takeDirectory artifactPath)
  (exitCode, _stdoutText, stderrText) <- runStreaming defaultSubprocessEnv compileCommand
  case exitCode of
    ExitFailure _ ->
      pure (Left ("linux-cpu compile failed: " <> stderrText))
    ExitSuccess -> do
      output <- loadAndRun artifactPath input
      pure
        ( Right
            LinuxCpuKernelRun
              { linuxCpuKernelHandle = handle
              , linuxCpuKernelInput = input
              , linuxCpuKernelOutput = output
              , linuxCpuKernelCompileCommand = renderSubprocess compileCommand
              }
        )
 where
  engine = engineForSubstrate LinuxCPU
  handle = kernelHandleFor engine hash
  artifactPath = Text.unpack (kernelHandleArtifactPath handle)
  compileCommand = compileSubprocess engine source hash

loadAndRun :: FilePath -> [Float] -> IO [Float]
loadAndRun artifactPath input =
  bracket (dlopen artifactPath [RTLD_NOW]) dlclose $ \dynamicLibrary -> do
    symbol <- dlsym dynamicLibrary "jitml_kernel"
    let kernel = mkKernelFunction symbol
        cInput = fmap CFloat input
        count = length input
    withArray cInput $ \inputPtr ->
      allocaArray count $ \outputPtr -> do
        kernel outputPtr inputPtr (fromIntegral count)
        fmap (\(CFloat value) -> value) <$> peekArray count outputPtr

linuxCpuIdentityKernel :: Cache.KernelSpec
linuxCpuIdentityKernel =
  Cache.KernelSpec "jitml-linux-cpu:identity"

linuxCpuFingerprint :: Cache.ToolchainFingerprint
linuxCpuFingerprint =
  Cache.ToolchainFingerprint "g++-shared;abi=extern-c;jitml_kernel(float*,const float*,size_t)"

{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Local
  ( LinuxCpuKernelRun (..)
  , LinuxCpuWeightedKernelRun (..)
  , linuxCpuFamilyHash
  , linuxCpuFamilyRuntimeSource
  , linuxCpuIdentityHash
  , linuxCpuIdentityRuntimeSource
  , linuxCpuToolchainFingerprint
  , flattenLoadedWeights
  , runLinuxCpuCheckpointInference
  , runLinuxCpuFamilyKernel
  , runLinuxCpuIdentityKernel
  , runLinuxCpuKernel
  , runLinuxCpuWeightedCheckpointInference
  , runLinuxCpuWeightedFamilyKernel
  , runLinuxCpuWeightedKernel
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
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactCompileCommand
  , kernelArtifactCompiled
  , kernelArtifactHandle
  , withKernelSymbol
  )
import JitML.Engines.MlpCheckpoint (runMlpCheckpointForwardWith)
import JitML.Env.Env (Env)
import JitML.Numerics.MlpOneDnn (mlpForwardOneDnn)
import JitML.Substrate (Substrate (..))

type KernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> IO ()

-- Sprint 13.11 — weighted ABI: caller supplies a flat row-major weights
-- buffer alongside the input. Output, input, input_count, weights,
-- weights_count.
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
runLinuxCpuCheckpointInference env _manifest input = do
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
runLinuxCpuWeightedFamilyKernel env family =
  runLinuxCpuWeightedKernel
    env
    (linuxCpuFamilyRuntimeSource family)
    (linuxCpuFamilyHash family)

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
      pure (Left ("linux-cpu weighted compile failed: " <> err))
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
-- input + weights buffers across the FFI.
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
        , -- Sprint 13.11: weighted kernel ABI accepting a flat row-major
          -- weights buffer alongside the input. Dense2D / Conv2D / Conv3D /
          -- BatchNorm / LayerNorm / MHA / Embedding now drive real oneDNN
          -- primitive paths (full set landed 2026-05-27). The fingerprint
          -- entry below invalidates pre-13.11 cache entries; the
          -- "all-families" tag bumps invalidation again when the per-
          -- family bodies land so the cache picks up the real weighted
          -- primitives instead of the prior unweighted fall-through.
          "jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)"
        , "weighted-bodies=all-families"
        ]
    )

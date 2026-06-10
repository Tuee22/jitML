{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Apple Silicon local Metal engine (Sprint 14.2 / 14.5).
--
-- Mirrors "JitML.Engines.CudaLocal": the first cache miss drives the Swift glue
-- build on the host with the CommandLineTools @swift build@ (no Tart VM, no full
-- Xcode), the produced @libJitMLMetal.dylib@ is published into the
-- content-addressed Apple cache, and this module @dlopen@s that dylib, resolves
-- the host-callable @jitml_kernel@ / @jitml_weighted_kernel@ C ABI emitted by
-- "JitML.Codegen.Metal", and launches the kernel against the host's Metal GPU
-- through the generated launcher (which JIT-compiles the embedded MSL at runtime
-- via @MTLDevice.makeLibrary(source:)@).
module JitML.Engines.MetalLocal
  ( MetalKernelRun (..)
  , MetalWeightedKernelRun (..)
  , metalFamilyHash
  , metalFamilyRuntimeSource
  , metalToolchainFingerprint
  , runMetalCheckpointInference
  , runMetalFamilyKernel
  , runMetalFamilyKernelWithProbe
  , runMetalKernel
  , runMetalWeightedCheckpointInference
  , runMetalWeightedFamilyKernel
  , runMetalWeightedFamilyKernelWithProbe
  , runMetalWeightedKernel
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
import JitML.Codegen.KernelFamily (KernelFamily (..), kernelFamilyKernelSpec)
import JitML.Codegen.Metal (renderMetalFamilyPackage)
import JitML.Codegen.RuntimeSource (RuntimeSource (..), runtimeSourcePayload)
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
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Env.Env (Env)
import JitML.Substrate (Substrate (..))

type KernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> IO ()

-- | Weighted ABI mirrors the CUDA / Linux CPU shape: output, input,
-- input_count, weights, weights_count.
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

data MetalKernelRun = MetalKernelRun
  { metalKernelHandle :: KernelHandle
  , metalKernelInput :: [Float]
  , metalKernelOutput :: [Float]
  , metalKernelReportedFamily :: Text
  , metalKernelCompileCommand :: Text
  , metalKernelCompiled :: Bool
  }
  deriving stock (Eq, Show)

-- | Outcome of a Metal weighted-kernel run. Same shape as 'MetalKernelRun'
-- plus the flattened weight buffer uploaded to the GPU.
data MetalWeightedKernelRun = MetalWeightedKernelRun
  { metalWeightedKernelHandle :: KernelHandle
  , metalWeightedKernelInput :: [Float]
  , metalWeightedKernelOutput :: [Float]
  , metalWeightedKernelWeights :: [Float]
  , metalWeightedKernelReportedFamily :: Text
  , metalWeightedKernelCompileCommand :: Text
  , metalWeightedKernelCompiled :: Bool
  }
  deriving stock (Eq, Show)

metalFamilyRuntimeSource :: KernelFamily -> RuntimeSource
metalFamilyRuntimeSource family =
  GeneratedMetalPackage
    { runtimeSourceKernel = kernelFamilyKernelSpec family
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles =
        renderMetalFamilyPackage
          family
          (kernelFamilyKernelSpec family)
          Cache.Inference
          Cache.defaultTuningChoice
    }

metalFamilyHash :: KernelFamily -> Cache.Hash
metalFamilyHash family =
  Cache.cacheKey
    (kernelFamilyKernelSpec family)
    Cache.Inference
    Cache.AppleSilicon
    metalToolchainFingerprint
    (runtimeSourcePayload (metalFamilyRuntimeSource family))
    Cache.defaultTuningChoice

runMetalFamilyKernel :: Env -> KernelFamily -> [Float] -> IO (Either Text MetalKernelRun)
runMetalFamilyKernel =
  runMetalFamilyKernelWithProbe MetalRuntime.probeMetalRuntime

runMetalFamilyKernelWithProbe
  :: IO MetalRuntime.MetalRuntimeProbe
  -> Env
  -> KernelFamily
  -> [Float]
  -> IO (Either Text MetalKernelRun)
runMetalFamilyKernelWithProbe probeRuntime env family input = do
  probe <- probeRuntime
  if MetalRuntime.metalRuntimeDeviceVisible probe
    then runMetalKernel env (metalFamilyRuntimeSource family) (metalFamilyHash family) input
    else pure (Left ("apple-silicon Metal device not visible: " <> renderMetalUnavailableSummary probe))

runMetalCheckpointInference :: Env -> CheckpointManifest -> [Double] -> IO (Either Text [Double])
runMetalCheckpointInference env manifest input = do
  kernelResult <- runMetalFamilyKernel env Identity (fmap realToFrac input)
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        let bias = fromIntegral (length (weightOnlyTensors manifest)) / 100.0
         in Right (fmap ((+ bias) . realToFrac) (metalKernelOutput kernelRun))

-- | Weighted checkpoint inference. Mirror of the CUDA path: routes through
-- the weighted Dense2D Metal kernel and returns the GPU output.
runMetalWeightedCheckpointInference
  :: Env
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runMetalWeightedCheckpointInference env _manifest weights input = do
  let flatWeights = fmap realToFrac (concatMap loadedWeightValues weights)
  kernelResult <-
    runMetalWeightedFamilyKernel env Dense2D (fmap realToFrac input) flatWeights
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        Right (fmap realToFrac (metalWeightedKernelOutput kernelRun))

runMetalWeightedFamilyKernel
  :: Env
  -> KernelFamily
  -> [Float]
  -> [Float]
  -> IO (Either Text MetalWeightedKernelRun)
runMetalWeightedFamilyKernel =
  runMetalWeightedFamilyKernelWithProbe MetalRuntime.probeMetalRuntime

runMetalWeightedFamilyKernelWithProbe
  :: IO MetalRuntime.MetalRuntimeProbe
  -> Env
  -> KernelFamily
  -> [Float]
  -> [Float]
  -> IO (Either Text MetalWeightedKernelRun)
runMetalWeightedFamilyKernelWithProbe probeRuntime env family input weights = do
  probe <- probeRuntime
  if MetalRuntime.metalRuntimeDeviceVisible probe
    then
      runMetalWeightedKernel
        env
        (metalFamilyRuntimeSource family)
        (metalFamilyHash family)
        input
        weights
    else
      pure
        ( Left
            ( "apple-silicon Metal device not visible: "
                <> renderMetalUnavailableSummary probe
            )
        )

-- | Load the family dylib, resolve the @jitml_weighted_kernel@ symbol, marshal
-- input + weights across the FFI to the generated Metal launcher, and return
-- the host output alongside 'MetalWeightedKernelRun' metadata.
runMetalWeightedKernel
  :: Env
  -> RuntimeSource
  -> Cache.Hash
  -> [Float]
  -> [Float]
  -> IO (Either Text MetalWeightedKernelRun)
runMetalWeightedKernel env source hash input weights = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("apple-silicon weighted build failed: " <> err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      (reportedFamily, output) <- loadAndRunWeighted artifactPath input weights
      pure
        ( Right
            MetalWeightedKernelRun
              { metalWeightedKernelHandle = handle
              , metalWeightedKernelInput = input
              , metalWeightedKernelOutput = output
              , metalWeightedKernelWeights = weights
              , metalWeightedKernelReportedFamily = reportedFamily
              , metalWeightedKernelCompileCommand = kernelArtifactCompileCommand artifact
              , metalWeightedKernelCompiled = kernelArtifactCompiled artifact
              }
        )
 where
  engine = engineForSubstrate AppleSilicon

runMetalKernel
  :: Env -> RuntimeSource -> Cache.Hash -> [Float] -> IO (Either Text MetalKernelRun)
runMetalKernel env source hash input = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("apple-silicon build failed: " <> err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      (reportedFamily, output) <- loadAndRun artifactPath input
      pure
        ( Right
            MetalKernelRun
              { metalKernelHandle = handle
              , metalKernelInput = input
              , metalKernelOutput = output
              , metalKernelReportedFamily = reportedFamily
              , metalKernelCompileCommand = kernelArtifactCompileCommand artifact
              , metalKernelCompiled = kernelArtifactCompiled artifact
              }
        )
 where
  engine = engineForSubstrate AppleSilicon

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

metalToolchainFingerprint :: Cache.ToolchainFingerprint
metalToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "swiftpm-metal-dynamic"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "metal-build-vm-runtime-makelibrary"
        , "single-stream-launch-order"
        , "simd-aligned-threadgroups"
        , "abi=extern-c-cdecl-launcher"
        , "jitml_kernel(float*,const float*,size_t)"
        , "jitml_kernel_family_name(void)"
        , "jitml_kernel_output_count(size_t)"
        , "jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)"
        , -- Sprint 14.5 — per-family weighted Metal bodies (Dense2D / Conv2D /
          -- Conv3D / BatchNorm / LayerNorm / MHA / Embedding) mirror the CUDA
          -- `weightedFamilyImpl` math. The "all-families" tag invalidates any
          -- pre-2026-05-30 Dense2D-baseline cache entries.
          "weighted-bodies=all-families"
        ]
    )

renderMetalUnavailableSummary :: MetalRuntime.MetalRuntimeProbe -> Text
renderMetalUnavailableSummary probe =
  Text.intercalate
    " "
    [ "swift=" <> maybe "missing" (const "present") (MetalRuntime.metalRuntimeSwiftVersion probe)
    , "device_visible=" <> renderBool (MetalRuntime.metalRuntimeDeviceVisible probe)
    ]

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

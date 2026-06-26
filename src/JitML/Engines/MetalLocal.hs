{-# LANGUAGE OverloadedStrings #-}

-- | Apple Silicon local Metal engine (Sprint 14.2 / 14.5).
--
-- Mirrors "JitML.Engines.CudaLocal" at the Haskell cache boundary, but the
-- Apple artifact is source metadata rather than a generated dylib. A cache miss
-- writes @<hash>.metal.json@; the fixed host Metal bridge loads once per
-- process, compiles the MSL through @MTLDevice.makeLibrary(source:options:)@,
-- caches pipelines internally, and dispatches on the host GPU.
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
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Checkpoint.Format (CheckpointManifest)
import JitML.Checkpoint.Store (LoadedWeightTensor (..))
import JitML.Codegen.KernelFamily (KernelFamily (..), kernelFamilyKernelSpec)
import JitML.Codegen.Metal
  ( metalBridgeAbiVersion
  , metalOutputCountFor
  , renderMetalFamilyMetadata
  , renderMetalFamilySource
  , threadgroupSizeFor
  )
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
  )
import JitML.Engines.MetalBridge qualified as MetalBridge
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.MlpCheckpoint (runMlpCheckpointForwardWith)
import JitML.Env.Env (Env)
import JitML.Numerics.MlpMetal (mlpForwardMetal)
import JitML.Substrate (Substrate (..))

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
  GeneratedMetalSourceMetadata
    { runtimeSourceKernel = kernelFamilyKernelSpec family
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceKernelFamily = Just family
    , runtimeSourceFiles =
        renderMetalFamilyMetadata
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
runMetalCheckpointInference env _manifest input = do
  kernelResult <- runMetalFamilyKernel env Identity (fmap realToFrac input)
  pure $
    case kernelResult of
      Left err -> Left err
      Right kernelRun ->
        -- Sprint 10.5 — faithful kernel output; the synthetic `+ nTensors/100`
        -- offset is removed (real weighted read: 'runMetalWeightedCheckpointInference').
        Right (fmap realToFrac (metalKernelOutput kernelRun))

-- | Weighted checkpoint inference. Mirror of the CUDA path: routes through
-- the weighted Dense2D Metal kernel and returns the GPU output.
runMetalWeightedCheckpointInference
  :: Env
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runMetalWeightedCheckpointInference env manifest weights input = do
  mlpResult <- runMlpCheckpointForwardWith (mlpForwardMetal env) manifest weights input
  case mlpResult of
    Just result -> pure result
    Nothing -> do
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

-- | Fill/read the source-metadata cache, then launch the weighted kernel through
-- the fixed host Metal bridge.
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
      pure (Left ("apple-silicon weighted metadata cache failed: " <> err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
      case runtimeSourceMetalFamily source of
        Nothing ->
          pure (Left "apple-silicon weighted metadata cache is not a Metal kernel-family source")
        Just family -> do
          outputResult <-
            MetalBridge.runMetalSource
              (renderMetalFamilySource family)
              "jitml_weighted_kernel"
              (threadgroupSizeFor family)
              input
              (Just weights)
              (metalOutputCountFor family (length input))
          pure $
            case outputResult of
              Left err -> Left ("apple-silicon weighted bridge dispatch failed: " <> err)
              Right output ->
                Right
                  MetalWeightedKernelRun
                    { metalWeightedKernelHandle = handle
                    , metalWeightedKernelInput = input
                    , metalWeightedKernelOutput = output
                    , metalWeightedKernelWeights = weights
                    , metalWeightedKernelReportedFamily = familyNameText family
                    , metalWeightedKernelCompileCommand = kernelArtifactCompileCommand artifact
                    , metalWeightedKernelCompiled = kernelArtifactCompiled artifact
                    }
 where
  engine = engineForSubstrate AppleSilicon

runMetalKernel
  :: Env -> RuntimeSource -> Cache.Hash -> [Float] -> IO (Either Text MetalKernelRun)
runMetalKernel env source hash input = do
  artifactResult <- ensureKernelArtifact env engine source hash
  case artifactResult of
    Left err ->
      pure (Left ("apple-silicon metadata cache failed: " <> err))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
      case runtimeSourceMetalFamily source of
        Nothing ->
          pure (Left "apple-silicon metadata cache is not a Metal kernel-family source")
        Just family -> do
          outputResult <-
            MetalBridge.runMetalSource
              (renderMetalFamilySource family)
              "jitml_kernel"
              (threadgroupSizeFor family)
              input
              Nothing
              (metalOutputCountFor family (length input))
          pure $
            case outputResult of
              Left err -> Left ("apple-silicon bridge dispatch failed: " <> err)
              Right output ->
                Right
                  MetalKernelRun
                    { metalKernelHandle = handle
                    , metalKernelInput = input
                    , metalKernelOutput = output
                    , metalKernelReportedFamily = familyNameText family
                    , metalKernelCompileCommand = kernelArtifactCompileCommand artifact
                    , metalKernelCompiled = kernelArtifactCompiled artifact
                    }
 where
  engine = engineForSubstrate AppleSilicon

runtimeSourceMetalFamily :: RuntimeSource -> Maybe KernelFamily
runtimeSourceMetalFamily GeneratedMetalSourceMetadata {runtimeSourceKernelFamily = Just family} = Just family
runtimeSourceMetalFamily _ = Nothing

familyNameText :: KernelFamily -> Text
familyNameText Identity = "identity"
familyNameText Reduction = "reduction"
familyNameText Dense2D = "dense"
familyNameText Conv2DKernel = "conv2d"
familyNameText Conv3DKernel = "conv3d"
familyNameText BatchNormKernel = "batchnorm"
familyNameText LayerNormKernel = "layernorm"
familyNameText MultiHeadAttentionKernel = "mha"
familyNameText EmbeddingKernel = "embedding"

metalToolchainFingerprint :: Cache.ToolchainFingerprint
metalToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "fixed-metal-bridge"
        , "bridge-abi=" <> metalBridgeAbiVersion
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "artifact=metal-source-metadata"
        , "metal-runtime-makelibrary"
        , "single-stream-launch-order"
        , "simd-aligned-threadgroups"
        , "abi=fixed-bridge-host-buffers"
        , "jitml_kernel(float*,const float*,size_t)"
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
    [ "device_visible=" <> renderBool (MetalRuntime.metalRuntimeDeviceVisible probe)
    ]

renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

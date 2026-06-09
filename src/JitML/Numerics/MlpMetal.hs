{-# LANGUAGE OverloadedStrings #-}

-- | The Apple-Silicon (Metal lane) backend for the JIT-compiled MLP
-- forward/backward kernels emitted by "JitML.Codegen.MlpMetal".
--
-- Like "JitML.Numerics.MlpCuda" / "JitML.Numerics.MlpOneDnn", this module only
-- supplies the backend 'MlpBackendSpec' and re-exports the five operations
-- under @*Metal@ names; the host-side marshalling lives once in
-- "JitML.Numerics.MlpDevice".
--
-- ⚠ The generated Metal program is UNVERIFIED on non-Mac hosts — it must be
-- exercised on the @-p apple-silicon@ lane (host-native on a Mac) before it is
-- trusted. The Haskell here is a thin spec wrapper and compiles everywhere.
module JitML.Numerics.MlpMetal
  ( mlpMetalHash
  , mlpMetalRuntimeSource
  , mlpMetalToolchainFingerprint
  , metalMlpSpec
  , metalMlpDevice
  , mlpForwardMetal
  , mlpForwardBatchMetal
  , mlpBackwardMetal
  , mlpBatchGradientMetal
  , mlpInputGradientBatchMetal
  , policyValueForwardMetal
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.MlpMetal (mlpMetalKernelSpec, renderMlpMetalSource)
import JitML.Codegen.RuntimeSource (RuntimeSource (..), runtimeSourcePayload)
import JitML.Engines.Engine (engineForSubstrate)
import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( MlpForward
  , MlpGradient
  , MlpParams
  , PolicyValueOutput
  , policyValueFromForward
  )
import JitML.Numerics.MlpDevice
  ( MlpBackendSpec (..)
  , MlpDevice
  , mlpBackwardWith
  , mlpBatchGradientWith
  , mlpDeviceFromSpec
  , mlpForwardBatchWith
  , mlpForwardWith
  , mlpInputGradientBatchWith
  )
import JitML.Substrate (Substrate (..))

mlpMetalRuntimeSource :: RuntimeSource
mlpMetalRuntimeSource =
  GeneratedMetalPackage
    { runtimeSourceKernel = mlpMetalKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderMlpMetalSource
    }

-- | Toolchain fingerprint for the MLP Metal kernel. Records the Swift/MSL
-- runtime-compile intent + the @\@_cdecl@ ABI; combined with the AppleSilicon
-- substrate this keeps the artifact in its own JIT-cache slot.
mlpMetalToolchainFingerprint :: Cache.ToolchainFingerprint
mlpMetalToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "swift-build-dynamic-lib"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "msl-makeLibrary-runtime"
        , "mathMode=safe(fast-math-off)"
        , "single-stream-launch-order"
        , "abi=cdecl-host-buffers"
        , "reductions=sequential-fixed-order"
        , "jitml_mlp_forward(float*,float*,float*,const float*,const float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_mlp_backward(float*,float*,float*,float*,const float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_mlp_batch_gradient(float*,float*,float*,float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_mlp_forward_batch(float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_mlp_input_gradient_batch(float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        ]
    )

mlpMetalHash :: Cache.Hash
mlpMetalHash =
  Cache.cacheKey
    mlpMetalKernelSpec
    Cache.Inference
    Cache.AppleSilicon
    mlpMetalToolchainFingerprint
    (runtimeSourcePayload mlpMetalRuntimeSource)
    Cache.defaultTuningChoice

-- | The Metal backend's compile/load coordinates for the shared MLP runner.
metalMlpSpec :: MlpBackendSpec
metalMlpSpec =
  MlpBackendSpec
    { mbsTag = "mlp-metal"
    , mbsEngine = engineForSubstrate AppleSilicon
    , mbsRuntimeSource = mlpMetalRuntimeSource
    , mbsHash = mlpMetalHash
    }

-- | The Metal MLP operations bundled for injection into the RL trainers.
metalMlpDevice :: Env -> MlpDevice
metalMlpDevice = mlpDeviceFromSpec metalMlpSpec

mlpForwardMetal :: Env -> MlpParams -> VU.Vector Double -> IO (Either Text MlpForward)
mlpForwardMetal = mlpForwardWith metalMlpSpec

mlpBackwardMetal
  :: Env -> MlpParams -> MlpForward -> VU.Vector Double -> IO (Either Text MlpGradient)
mlpBackwardMetal = mlpBackwardWith metalMlpSpec

mlpForwardBatchMetal
  :: Env -> MlpParams -> [VU.Vector Double] -> IO (Either Text [VU.Vector Double])
mlpForwardBatchMetal = mlpForwardBatchWith metalMlpSpec

mlpBatchGradientMetal
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text MlpGradient)
mlpBatchGradientMetal = mlpBatchGradientWith metalMlpSpec

mlpInputGradientBatchMetal
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text [VU.Vector Double])
mlpInputGradientBatchMetal = mlpInputGradientBatchWith metalMlpSpec

-- | Device-backed policy/value forward pass on the Metal lane.
policyValueForwardMetal
  :: Env -> MlpParams -> Int -> VU.Vector Double -> IO (Either Text PolicyValueOutput)
policyValueForwardMetal env params actionCount input =
  fmap (policyValueFromForward actionCount) <$> mlpForwardMetal env params input

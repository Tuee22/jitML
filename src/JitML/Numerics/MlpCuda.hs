{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.8 / 13.9 — the CUDA backend for the JIT-compiled MLP
-- forward/backward kernels emitted by "JitML.Codegen.MlpCuda".
--
-- The host-side compile/load/marshal path is shared across every backend and
-- lives in "JitML.Numerics.MlpDevice"; this module only supplies the CUDA
-- 'MlpBackendSpec' (engine, generated runtime source, cache hash) and
-- re-exports the five operations under their conventional @*Cuda@ names so
-- existing callers (the RL trainers, AlphaZero 'PolicyValueNet', the
-- @jitml-backends@ tests) are unchanged. The artifact is compiled once and
-- cached in the content-addressed JIT cache; subsequent runs hit the cache.
module JitML.Numerics.MlpCuda
  ( mlpCudaHash
  , mlpCudaRuntimeSource
  , mlpCudaToolchainFingerprint
  , cudaMlpSpec
  , cudaMlpDevice
  , mlpForwardCuda
  , mlpForwardBatchCuda
  , mlpBackwardCuda
  , mlpBatchGradientCuda
  , mlpInputGradientBatchCuda
  , policyValueForwardCuda
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.MlpCuda (mlpCudaKernelSpec, renderMlpCudaSource)
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

mlpCudaRuntimeSource :: RuntimeSource
mlpCudaRuntimeSource =
  GeneratedCudaSource
    { runtimeSourceKernel = mlpCudaKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderMlpCudaSource
    }

-- | Toolchain fingerprint for the MLP CUDA kernel. Distinct symbol names keep
-- this artifact in its own JIT-cache slot, separate from the
-- per-'JitML.Codegen.KernelFamily.KernelFamily' kernels.
mlpCudaToolchainFingerprint :: Cache.ToolchainFingerprint
mlpCudaToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "nvcc-shared"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "sm=70"
        , "--use_fast_math=false"
        , "tf32=disabled"
        , "abi=extern-c-host-wrapper"
        , "reductions=per-thread-sequential"
        , "jitml_mlp_forward(float*,float*,float*,const float*,const float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_mlp_backward(float*,float*,float*,float*,const float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_mlp_batch_gradient(float*,float*,float*,float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_mlp_forward_batch(float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_mlp_input_gradient_batch(float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        ]
    )

mlpCudaHash :: Cache.Hash
mlpCudaHash =
  Cache.cacheKey
    mlpCudaKernelSpec
    Cache.Inference
    Cache.LinuxCUDA
    mlpCudaToolchainFingerprint
    (runtimeSourcePayload mlpCudaRuntimeSource)
    Cache.defaultTuningChoice

-- | The CUDA backend's compile/load coordinates for the shared MLP runner.
cudaMlpSpec :: MlpBackendSpec
cudaMlpSpec =
  MlpBackendSpec
    { mbsTag = "mlp-cuda"
    , mbsEngine = engineForSubstrate LinuxCUDA
    , mbsRuntimeSource = mlpCudaRuntimeSource
    , mbsHash = mlpCudaHash
    }

-- | The CUDA MLP operations bundled for injection into the RL trainers.
cudaMlpDevice :: Env -> MlpDevice
cudaMlpDevice = mlpDeviceFromSpec cudaMlpSpec

mlpForwardCuda :: Env -> MlpParams -> VU.Vector Double -> IO (Either Text MlpForward)
mlpForwardCuda = mlpForwardWith cudaMlpSpec

mlpBackwardCuda
  :: Env -> MlpParams -> MlpForward -> VU.Vector Double -> IO (Either Text MlpGradient)
mlpBackwardCuda = mlpBackwardWith cudaMlpSpec

mlpForwardBatchCuda
  :: Env -> MlpParams -> [VU.Vector Double] -> IO (Either Text [VU.Vector Double])
mlpForwardBatchCuda = mlpForwardBatchWith cudaMlpSpec

mlpBatchGradientCuda
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text MlpGradient)
mlpBatchGradientCuda = mlpBatchGradientWith cudaMlpSpec

mlpInputGradientBatchCuda
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text [VU.Vector Double])
mlpInputGradientBatchCuda = mlpInputGradientBatchWith cudaMlpSpec

-- | Device-backed policy/value forward pass: runs the MLP forward on the GPU
-- and assembles the same 'PolicyValueOutput' (softmax policy head + tanh value
-- head) the pure 'JitML.Numerics.Mlp.policyValueForward' produces.
policyValueForwardCuda
  :: Env -> MlpParams -> Int -> VU.Vector Double -> IO (Either Text PolicyValueOutput)
policyValueForwardCuda env params actionCount input =
  fmap (policyValueFromForward actionCount) <$> mlpForwardCuda env params input

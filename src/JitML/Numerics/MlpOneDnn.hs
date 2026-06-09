{-# LANGUAGE OverloadedStrings #-}

-- | The Linux-CPU (oneDNN lane) backend for the JIT-compiled MLP
-- forward/backward kernels emitted by "JitML.Codegen.MlpOneDnn".
--
-- Like "JitML.Numerics.MlpCuda", this module only supplies the backend
-- 'MlpBackendSpec' and re-exports the five operations under @*OneDnn@ names;
-- the host-side marshalling lives once in "JitML.Numerics.MlpDevice". The
-- generated kernel runs on the CPU, so each result matches the pure
-- 'JitML.Numerics.Mlp' network within single precision and is bit-deterministic
-- run-to-run on the same host.
module JitML.Numerics.MlpOneDnn
  ( mlpOneDnnHash
  , mlpOneDnnRuntimeSource
  , mlpOneDnnToolchainFingerprint
  , oneDnnMlpSpec
  , oneDnnMlpDevice
  , mlpForwardOneDnn
  , mlpForwardBatchOneDnn
  , mlpBackwardOneDnn
  , mlpBatchGradientOneDnn
  , mlpInputGradientBatchOneDnn
  , policyValueForwardOneDnn
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.MlpOneDnn (mlpOneDnnKernelSpec, renderMlpOneDnnSource)
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

mlpOneDnnRuntimeSource :: RuntimeSource
mlpOneDnnRuntimeSource =
  GeneratedOneDnnSource
    { runtimeSourceKernel = mlpOneDnnKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderMlpOneDnnSource
    }

-- | Toolchain fingerprint for the MLP oneDNN kernel. Records the g++ compile
-- intent + the @extern "C"@ ABI; combined with the LinuxCPU substrate this
-- keeps the artifact in its own JIT-cache slot.
mlpOneDnnToolchainFingerprint :: Cache.ToolchainFingerprint
mlpOneDnnToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "g++-shared-c++20-O2-fPIC"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "-DJITML_DETERMINISTIC_REDUCTIONS=1"
        , "abi=extern-c-host-direct"
        , "reductions=sequential-fixed-order"
        , "jitml_mlp_forward(float*,float*,float*,const float*,const float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_mlp_backward(float*,float*,float*,float*,const float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_mlp_batch_gradient(float*,float*,float*,float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_mlp_forward_batch(float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_mlp_input_gradient_batch(float*,const float*,const float*,const float*,const float*,const float*,int,int,int,int)"
        ]
    )

mlpOneDnnHash :: Cache.Hash
mlpOneDnnHash =
  Cache.cacheKey
    mlpOneDnnKernelSpec
    Cache.Inference
    Cache.LinuxCPU
    mlpOneDnnToolchainFingerprint
    (runtimeSourcePayload mlpOneDnnRuntimeSource)
    Cache.defaultTuningChoice

-- | The oneDNN backend's compile/load coordinates for the shared MLP runner.
oneDnnMlpSpec :: MlpBackendSpec
oneDnnMlpSpec =
  MlpBackendSpec
    { mbsTag = "mlp-onednn"
    , mbsEngine = engineForSubstrate LinuxCPU
    , mbsRuntimeSource = mlpOneDnnRuntimeSource
    , mbsHash = mlpOneDnnHash
    }

-- | The oneDNN MLP operations bundled for injection into the RL trainers.
oneDnnMlpDevice :: Env -> MlpDevice
oneDnnMlpDevice = mlpDeviceFromSpec oneDnnMlpSpec

mlpForwardOneDnn :: Env -> MlpParams -> VU.Vector Double -> IO (Either Text MlpForward)
mlpForwardOneDnn = mlpForwardWith oneDnnMlpSpec

mlpBackwardOneDnn
  :: Env -> MlpParams -> MlpForward -> VU.Vector Double -> IO (Either Text MlpGradient)
mlpBackwardOneDnn = mlpBackwardWith oneDnnMlpSpec

mlpForwardBatchOneDnn
  :: Env -> MlpParams -> [VU.Vector Double] -> IO (Either Text [VU.Vector Double])
mlpForwardBatchOneDnn = mlpForwardBatchWith oneDnnMlpSpec

mlpBatchGradientOneDnn
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text MlpGradient)
mlpBatchGradientOneDnn = mlpBatchGradientWith oneDnnMlpSpec

mlpInputGradientBatchOneDnn
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text [VU.Vector Double])
mlpInputGradientBatchOneDnn = mlpInputGradientBatchWith oneDnnMlpSpec

-- | Device-backed policy/value forward pass on the oneDNN lane.
policyValueForwardOneDnn
  :: Env -> MlpParams -> Int -> VU.Vector Double -> IO (Either Text PolicyValueOutput)
policyValueForwardOneDnn env params actionCount input =
  fmap (policyValueFromForward actionCount) <$> mlpForwardOneDnn env params input

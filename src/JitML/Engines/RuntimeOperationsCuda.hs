{-# LANGUAGE OverloadedStrings #-}

-- | Linux-CUDA binding for the versioned supervised-runtime structural ABI.
-- Generated CUDA source is compiled into the content-addressed kernel cache;
-- every callback is then loaded and capability-checked by
-- 'RuntimeOperationsDevice.runtimeOperationsBackendExecutor'.
module JitML.Engines.RuntimeOperationsCuda
  ( cudaRuntimeOperationsSpec
  , runtimeOperationsCudaHash
  , runtimeOperationsCudaRuntimeSource
  , runtimeOperationsCudaToolchainFingerprint
  )
where

import Data.Text qualified as Text
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeOperationsCuda
  ( renderRuntimeOperationsCudaSource
  , runtimeOperationsCudaKernelSpec
  )
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , runtimeSourcePayload
  )
import JitML.Engines.Engine (engineForSubstrate)
import JitML.Engines.RuntimeOperationsDevice qualified as RuntimeOperationsDevice
import JitML.Substrate (Substrate (..))

runtimeOperationsCudaRuntimeSource :: RuntimeSource
runtimeOperationsCudaRuntimeSource =
  GeneratedCudaSource
    { runtimeSourceKernel = runtimeOperationsCudaKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderRuntimeOperationsCudaSource
    }

runtimeOperationsCudaToolchainFingerprint :: Cache.ToolchainFingerprint
runtimeOperationsCudaToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "nvcc-shared-sm70"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "abi=jitml-runtime-operations-v1-double"
        , "capabilities=0xff"
        , "device-arithmetic=fp64"
        , "single-thread-fixed-order-reductions"
        , "softmax=max-shifted-sequential"
        , "--use_fast_math=false"
        , "--fmad=false"
        , "transport=extern-c-host-wrapper"
        , "jitml_runtime_operations_abi_version(void)"
        , "jitml_runtime_operations_capabilities(void)"
        , "jitml_runtime_input_transform"
        , "jitml_runtime_output_transform"
        , "jitml_runtime_residual_add"
        , "jitml_runtime_layer_norm"
        , "jitml_runtime_token_mix_pack"
        , "jitml_runtime_token_mix_merge"
        , "jitml_runtime_patch_extract"
        , "jitml_runtime_attention"
        , "jitml_runtime_mean_pool"
        ]
    )

runtimeOperationsCudaHash :: Cache.Hash
runtimeOperationsCudaHash =
  Cache.cacheKey
    runtimeOperationsCudaKernelSpec
    Cache.Inference
    Cache.LinuxCUDA
    runtimeOperationsCudaToolchainFingerprint
    (runtimeSourcePayload runtimeOperationsCudaRuntimeSource)
    Cache.defaultTuningChoice

cudaRuntimeOperationsSpec :: RuntimeOperationsDevice.RuntimeOperationsBackendSpec
cudaRuntimeOperationsSpec =
  RuntimeOperationsDevice.RuntimeOperationsBackendSpec
    { RuntimeOperationsDevice.runtimeOperationsBackendLabel = "linux-cuda"
    , RuntimeOperationsDevice.runtimeOperationsBackendEngine =
        engineForSubstrate LinuxCUDA
    , RuntimeOperationsDevice.runtimeOperationsBackendSource =
        runtimeOperationsCudaRuntimeSource
    , RuntimeOperationsDevice.runtimeOperationsBackendHash =
        runtimeOperationsCudaHash
    , RuntimeOperationsDevice.runtimeOperationsBackendExpectedAbi =
        RuntimeOperationsDevice.runtimeOperationsAbiVersion
    , RuntimeOperationsDevice.runtimeOperationsBackendRequiredCapabilities =
        RuntimeOperationsDevice.runtimeOperationsAllCapabilities
    }

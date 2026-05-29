{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.8 / 13.9 — the host-side runner that compiles, loads, and
-- launches the nvcc-emitted MLP forward/backward kernels from
-- "JitML.Codegen.MlpCuda" behind the same 'JitML.Numerics.Mlp'
-- interface the pure-Haskell network exposes. This is the device-backed
-- half of the "CUDA-emitted forward/backward kernels" item that Sprints
-- 13.8 and 13.9 still own as Remaining Work.
--
-- The artifact is compiled once and cached in the content-addressed JIT
-- cache (same @ensureKernelArtifact@ path as the per-family kernels);
-- subsequent runs hit the cache. Each call marshals the flat row-major
-- parameter buffers across the FFI to the @extern \"C\"@ host wrappers,
-- which own device allocation and host↔device copies.
module JitML.Numerics.MlpCuda
  ( mlpCudaHash
  , mlpCudaRuntimeSource
  , mlpCudaToolchainFingerprint
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
import Foreign.C.Types (CFloat (..), CInt (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.MlpCuda (mlpCudaKernelSpec, renderMlpCudaSource)
import JitML.Codegen.RuntimeSource (RuntimeSource (..), runtimeSourcePayload)
import JitML.Engines.Engine (KernelHandle (..), engineForSubstrate)
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactHandle
  , withKernelSymbol
  )
import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( MlpForward (..)
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , PolicyValueOutput
  , mlpZeroGradient
  , policyValueFromForward
  )
import JitML.Substrate (Substrate (..))

-- Forward ABI: (hidden_pre, hidden_act, output) out;
--              (input, w1, b1, w2, b2) in; (inputs, hidden, outputs).
type MlpForwardFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

-- Backward ABI: (g_w1, g_b1, g_w2, g_b2) out;
--               (d_l_dy, input, hidden_act, w2) in; (inputs, hidden, outputs).
type MlpBackwardFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

-- Batched fused ABI: (g_w1, g_b1, g_w2, g_b2) out; (input[B×in], d_l_dy[B×out],
--                     w1, b1, w2) in; (inputs, hidden, outputs, batch). The
-- gradient is summed over the batch in a single device round-trip.
type MlpBatchGradientFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

foreign import ccall "dynamic" mkMlpForwardFun :: FunPtr MlpForwardFun -> MlpForwardFun

foreign import ccall "dynamic" mkMlpBackwardFun :: FunPtr MlpBackwardFun -> MlpBackwardFun

-- Batched forward ABI: output[B×out] out; (input[B×in], w1, b1, w2, b2) in;
--                       (inputs, hidden, outputs, batch).
type MlpForwardBatchFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

foreign import ccall "dynamic"
  mkMlpBatchGradientFun :: FunPtr MlpBatchGradientFun -> MlpBatchGradientFun

-- Batched input-gradient ABI: dx[B×in] out; (input[B×in], d_l_dy[B×out],
--                              w1, b1, w2) in; (inputs, hidden, outputs, batch).
type MlpInputGradientBatchFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

foreign import ccall "dynamic"
  mkMlpForwardBatchFun :: FunPtr MlpForwardBatchFun -> MlpForwardBatchFun

foreign import ccall "dynamic"
  mkMlpInputGradientBatchFun :: FunPtr MlpInputGradientBatchFun -> MlpInputGradientBatchFun

mlpCudaRuntimeSource :: RuntimeSource
mlpCudaRuntimeSource =
  GeneratedCudaSource
    { runtimeSourceKernel = mlpCudaKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderMlpCudaSource
    }

-- | Toolchain fingerprint for the MLP CUDA kernel. Distinct symbol names
-- keep this artifact in its own JIT-cache slot, separate from the
-- per-'KernelFamily' kernels.
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

-- | Run the MLP forward pass through the generated CUDA kernel. Returns
-- the same 'MlpForward' cache the pure 'JitML.Numerics.Mlp.mlpForward'
-- produces (so the value head / softmax wrappers consume it unchanged),
-- with the arithmetic executed on the device.
mlpForwardCuda :: Env -> MlpParams -> VU.Vector Double -> IO (Either Text MlpForward)
mlpForwardCuda env params input = do
  artifactResult <- ensureKernelArtifact env engine mlpCudaRuntimeSource mlpCudaHash
  case artifactResult of
    Left err -> pure (Left ("mlp-cuda compile failed: " <> err))
    Right artifact -> do
      let path = Text.unpack (kernelHandleArtifactPath (kernelArtifactHandle artifact))
      withKernelSymbol path "jitml_mlp_forward" $ \symbol -> do
        let forwardFun = mkMlpForwardFun symbol
        withArray (toC (VU.toList input)) $ \pInput ->
          withArray (toC (VU.toList (paramW1 params))) $ \pW1 ->
            withArray (toC (VU.toList (paramB1 params))) $ \pB1 ->
              withArray (toC (VU.toList (paramW2 params))) $ \pW2 ->
                withArray (toC (VU.toList (paramB2 params))) $ \pB2 ->
                  allocaArray hidden $ \pHiddenPre ->
                    allocaArray hidden $ \pHiddenAct ->
                      allocaArray outputs $ \pOutput -> do
                        forwardFun
                          pHiddenPre
                          pHiddenAct
                          pOutput
                          pInput
                          pW1
                          pB1
                          pW2
                          pB2
                          (fromIntegral inputs)
                          (fromIntegral hidden)
                          (fromIntegral outputs)
                        hiddenPre <- peekFloats hidden pHiddenPre
                        hiddenAct <- peekFloats hidden pHiddenAct
                        output <- peekFloats outputs pOutput
                        pure
                          ( Right
                              MlpForward
                                { forwardInput = input
                                , forwardHiddenPre = VU.fromList hiddenPre
                                , forwardHiddenAct = VU.fromList hiddenAct
                                , forwardOutput = VU.fromList output
                                }
                          )
 where
  engine = engineForSubstrate LinuxCUDA
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape

-- | Run the MLP backward pass through the generated CUDA kernel. Returns
-- the same 'MlpGradient' the pure 'JitML.Numerics.Mlp.mlpBackward'
-- produces, with the arithmetic executed on the device.
mlpBackwardCuda
  :: Env -> MlpParams -> MlpForward -> VU.Vector Double -> IO (Either Text MlpGradient)
mlpBackwardCuda env params fwd dLdy = do
  artifactResult <- ensureKernelArtifact env engine mlpCudaRuntimeSource mlpCudaHash
  case artifactResult of
    Left err -> pure (Left ("mlp-cuda compile failed: " <> err))
    Right artifact -> do
      let path = Text.unpack (kernelHandleArtifactPath (kernelArtifactHandle artifact))
      withKernelSymbol path "jitml_mlp_backward" $ \symbol -> do
        let backwardFun = mkMlpBackwardFun symbol
        withArray (toC (VU.toList dLdy)) $ \pDy ->
          withArray (toC (VU.toList (forwardInput fwd))) $ \pInput ->
            withArray (toC (VU.toList (forwardHiddenAct fwd))) $ \pHiddenAct ->
              withArray (toC (VU.toList (paramW2 params))) $ \pW2 ->
                allocaArray w1n $ \pGW1 ->
                  allocaArray hidden $ \pGB1 ->
                    allocaArray w2n $ \pGW2 ->
                      allocaArray outputs $ \pGB2 -> do
                        backwardFun
                          pGW1
                          pGB1
                          pGW2
                          pGB2
                          pDy
                          pInput
                          pHiddenAct
                          pW2
                          (fromIntegral inputs)
                          (fromIntegral hidden)
                          (fromIntegral outputs)
                        gW1 <- peekFloats w1n pGW1
                        gB1 <- peekFloats hidden pGB1
                        gW2 <- peekFloats w2n pGW2
                        gB2 <- peekFloats outputs pGB2
                        pure
                          ( Right
                              MlpGradient
                                { gradW1 = VU.fromList gW1
                                , gradB1 = VU.fromList gB1
                                , gradW2 = VU.fromList gW2
                                , gradB2 = VU.fromList gB2
                                }
                          )
 where
  engine = engineForSubstrate LinuxCUDA
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape
  w1n = hidden * inputs
  w2n = outputs * hidden

-- | Sprint 13.8 — batched device forward: runs the network forward over a
-- whole minibatch in a single device round-trip and returns the per-sample
-- output vectors. The complement to 'mlpBatchGradientCuda' — a CUDA trainer
-- obtains the minibatch's policy/value outputs here (to form the loss
-- gradient), then calls 'mlpBatchGradientCuda' for the summed gradient.
-- Each output matches the pure 'mlpForward' output within single precision.
mlpForwardBatchCuda
  :: Env -> MlpParams -> [VU.Vector Double] -> IO (Either Text [VU.Vector Double])
mlpForwardBatchCuda env params inputs
  | null inputs = pure (Right [])
  | any (\i -> VU.length i /= inputCount) inputs =
      pure (Left "mlpForwardBatchCuda: input shape mismatch against the network")
  | otherwise = do
      artifactResult <- ensureKernelArtifact env engine mlpCudaRuntimeSource mlpCudaHash
      case artifactResult of
        Left err -> pure (Left ("mlp-cuda compile failed: " <> err))
        Right artifact -> do
          let path = Text.unpack (kernelHandleArtifactPath (kernelArtifactHandle artifact))
          withKernelSymbol path "jitml_mlp_forward_batch" $ \symbol -> do
            let forwardFun = mkMlpForwardBatchFun symbol
                inputFlat = toC (concatMap VU.toList inputs)
                batchN = length inputs
            withArray inputFlat $ \pInput ->
              withArray (toC (VU.toList (paramW1 params))) $ \pW1 ->
                withArray (toC (VU.toList (paramB1 params))) $ \pB1 ->
                  withArray (toC (VU.toList (paramW2 params))) $ \pW2 ->
                    withArray (toC (VU.toList (paramB2 params))) $ \pB2 ->
                      allocaArray (batchN * outputs) $ \pOutput -> do
                        forwardFun
                          pOutput
                          pInput
                          pW1
                          pB1
                          pW2
                          pB2
                          (fromIntegral inputCount)
                          (fromIntegral hidden)
                          (fromIntegral outputs)
                          (fromIntegral batchN)
                        flat <- peekFloats (batchN * outputs) pOutput
                        pure (Right (chunksOf outputs (VU.fromList flat)))
 where
  engine = engineForSubstrate LinuxCUDA
  shape = paramShape params
  inputCount = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape
  chunksOf n vec
    | VU.length vec < n = []
    | otherwise = VU.take n vec : chunksOf n (VU.drop n vec)

-- | Sprint 13.8 — batched device gradient: given a minibatch of
-- @(input, dL/dy)@ pairs, compute the parameter gradient /summed over the
-- batch/ in a single device round-trip (one host↔device transfer for the
-- whole batch, rather than per-sample marshalling). This is the
-- amortised-copy primitive the RL trainers' minibatch hot path adopts; the
-- result equals @sum (map (mlpBackward params fwd) batch)@ within
-- single-precision tolerance and is bit-deterministic on the same device.
mlpBatchGradientCuda
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -- ^ minibatch of (input, dL/dy); each input has @mlpInputs@ entries,
  --   each dL/dy has @mlpOutputs@ entries
  -> IO (Either Text MlpGradient)
mlpBatchGradientCuda env params batch
  | null batch = pure (Right (mlpZeroGradient shape))
  | any (\(i, dy) -> VU.length i /= inputs || VU.length dy /= outputs) batch =
      pure (Left "mlpBatchGradientCuda: input/dLdy shape mismatch against the network")
  | otherwise = do
      artifactResult <- ensureKernelArtifact env engine mlpCudaRuntimeSource mlpCudaHash
      case artifactResult of
        Left err -> pure (Left ("mlp-cuda compile failed: " <> err))
        Right artifact -> do
          let path = Text.unpack (kernelHandleArtifactPath (kernelArtifactHandle artifact))
          withKernelSymbol path "jitml_mlp_batch_gradient" $ \symbol -> do
            let gradientFun = mkMlpBatchGradientFun symbol
                inputFlat = toC (concatMap (VU.toList . fst) batch)
                dyFlat = toC (concatMap (VU.toList . snd) batch)
                batchN = length batch
            withArray inputFlat $ \pInput ->
              withArray dyFlat $ \pDy ->
                withArray (toC (VU.toList (paramW1 params))) $ \pW1 ->
                  withArray (toC (VU.toList (paramB1 params))) $ \pB1 ->
                    withArray (toC (VU.toList (paramW2 params))) $ \pW2 ->
                      allocaArray w1n $ \pGW1 ->
                        allocaArray hidden $ \pGB1 ->
                          allocaArray w2n $ \pGW2 ->
                            allocaArray outputs $ \pGB2 -> do
                              gradientFun
                                pGW1
                                pGB1
                                pGW2
                                pGB2
                                pInput
                                pDy
                                pW1
                                pB1
                                pW2
                                (fromIntegral inputs)
                                (fromIntegral hidden)
                                (fromIntegral outputs)
                                (fromIntegral batchN)
                              gW1 <- peekFloats w1n pGW1
                              gB1 <- peekFloats hidden pGB1
                              gW2 <- peekFloats w2n pGW2
                              gB2 <- peekFloats outputs pGB2
                              pure
                                ( Right
                                    MlpGradient
                                      { gradW1 = VU.fromList gW1
                                      , gradB1 = VU.fromList gB1
                                      , gradW2 = VU.fromList gW2
                                      , gradB2 = VU.fromList gB2
                                      }
                                )
 where
  engine = engineForSubstrate LinuxCUDA
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape
  w1n = hidden * inputs
  w2n = outputs * hidden

-- | Sprint 13.8 — batched device input-gradient: given a minibatch of
-- @(input, dL/dy)@ pairs, compute @dL/dx@ for each sample (per-sample, not
-- summed) in a single device round-trip. This is the deterministic-policy
-- gradient primitive the continuous actor-critics need: the actor update's
-- @dQ/da@ is the action-slice of the critic's input gradient. Each result
-- matches the pure 'JitML.Numerics.Mlp.mlpInputGradient' within single
-- precision and is bit-deterministic on the same device.
mlpInputGradientBatchCuda
  :: Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -- ^ minibatch of (input, dL/dy)
  -> IO (Either Text [VU.Vector Double])
mlpInputGradientBatchCuda env params batch
  | null batch = pure (Right [])
  | any (\(i, dy) -> VU.length i /= inputs || VU.length dy /= outputs) batch =
      pure (Left "mlpInputGradientBatchCuda: input/dLdy shape mismatch against the network")
  | otherwise = do
      artifactResult <- ensureKernelArtifact env engine mlpCudaRuntimeSource mlpCudaHash
      case artifactResult of
        Left err -> pure (Left ("mlp-cuda compile failed: " <> err))
        Right artifact -> do
          let path = Text.unpack (kernelHandleArtifactPath (kernelArtifactHandle artifact))
          withKernelSymbol path "jitml_mlp_input_gradient_batch" $ \symbol -> do
            let gradFun = mkMlpInputGradientBatchFun symbol
                inputFlat = toC (concatMap (VU.toList . fst) batch)
                dyFlat = toC (concatMap (VU.toList . snd) batch)
                batchN = length batch
            withArray inputFlat $ \pInput ->
              withArray dyFlat $ \pDy ->
                withArray (toC (VU.toList (paramW1 params))) $ \pW1 ->
                  withArray (toC (VU.toList (paramB1 params))) $ \pB1 ->
                    withArray (toC (VU.toList (paramW2 params))) $ \pW2 ->
                      allocaArray (batchN * inputs) $ \pDx -> do
                        gradFun
                          pDx
                          pInput
                          pDy
                          pW1
                          pB1
                          pW2
                          (fromIntegral inputs)
                          (fromIntegral hidden)
                          (fromIntegral outputs)
                          (fromIntegral batchN)
                        flat <- peekFloats (batchN * inputs) pDx
                        pure (Right (chunksOf inputs (VU.fromList flat)))
 where
  engine = engineForSubstrate LinuxCUDA
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape
  chunksOf n vec
    | VU.length vec < n = []
    | otherwise = VU.take n vec : chunksOf n (VU.drop n vec)

-- | Device-backed policy/value forward pass: runs the MLP forward on the
-- GPU and assembles the same 'PolicyValueOutput' (softmax policy head +
-- tanh value head) the pure 'JitML.Numerics.Mlp.policyValueForward'
-- produces. The AlphaZero training step ("JitML.RL.AlphaZero.PolicyValueNet")
-- consumes this so the network forward runs on the device.
policyValueForwardCuda
  :: Env -> MlpParams -> Int -> VU.Vector Double -> IO (Either Text PolicyValueOutput)
policyValueForwardCuda env params actionCount input =
  fmap (policyValueFromForward actionCount) <$> mlpForwardCuda env params input

toC :: [Double] -> [CFloat]
toC = fmap (CFloat . realToFrac)

peekFloats :: Int -> Ptr CFloat -> IO [Double]
peekFloats n ptr = fmap (\(CFloat v) -> realToFrac v) <$> peekArray n ptr

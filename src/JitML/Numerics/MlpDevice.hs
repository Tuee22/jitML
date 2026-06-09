{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Shared host-side runner for the JIT-compiled MLP forward/backward kernels.
--
-- Every backend (CUDA, oneDNN, Metal) emits the /same/ @extern "C"@ ABI — the
-- @jitml_mlp_forward@ / @jitml_mlp_backward@ / @jitml_mlp_forward_batch@ /
-- @jitml_mlp_batch_gradient@ / @jitml_mlp_input_gradient_batch@ symbols, each
-- taking flat row-major @float@ buffers. The host-side compile → load → marshal
-- path is therefore identical across backends; only the engine, generated
-- runtime source, and content-addressed cache hash differ. This module owns
-- that single path, parameterized by an 'MlpBackendSpec'. The per-backend
-- modules ("JitML.Numerics.MlpCuda" / "JitML.Numerics.MlpOneDnn" /
-- "JitML.Numerics.MlpMetal") supply their spec and re-export the five functions
-- under their conventional names, so existing callers are unaffected.
--
-- The five operations are also bundled into an 'MlpDevice' record so a caller
-- (the RL trainers) can be parameterized by an injected backend rather than
-- hard-coding one — the seam the device-parity trainers route through.
module JitML.Numerics.MlpDevice
  ( MlpBackendSpec (..)
  , MlpDevice (..)
  , mlpDeviceFromSpec
  , mlpForwardWith
  , mlpBackwardWith
  , mlpForwardBatchWith
  , mlpBatchGradientWith
  , mlpInputGradientBatchWith
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Foreign.C.Types (CFloat (..), CInt (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource (RuntimeSource)
import JitML.Engines.Engine (Engine, KernelHandle (..))
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
  , mlpZeroGradient
  )

-- | A backend's compile/load coordinates. The MLP ABI is identical across
-- backends; only these values differ (plus a human-readable error tag).
data MlpBackendSpec = MlpBackendSpec
  { mbsTag :: Text
  -- ^ error-message prefix, e.g. @"mlp-onednn"@
  , mbsEngine :: Engine
  -- ^ engine that compiles/loads the artifact
  , mbsRuntimeSource :: RuntimeSource
  -- ^ the generated kernel source for this backend
  , mbsHash :: Cache.Hash
  -- ^ content-addressed JIT-cache key for the artifact
  }

-- | The five MLP device operations bundled behind one record, each already
-- closed over its 'Env' and 'MlpBackendSpec'. Injected into the RL trainers so
-- one trainer body serves every backend ('mlpDeviceFromSpec').
data MlpDevice = MlpDevice
  { mlpdForward :: MlpParams -> VU.Vector Double -> IO (Either Text MlpForward)
  , mlpdBackward
      :: MlpParams -> MlpForward -> VU.Vector Double -> IO (Either Text MlpGradient)
  , mlpdForwardBatch
      :: MlpParams -> [VU.Vector Double] -> IO (Either Text [VU.Vector Double])
  , mlpdBatchGradient
      :: MlpParams
      -> [(VU.Vector Double, VU.Vector Double)]
      -> IO (Either Text MlpGradient)
  , mlpdInputGradientBatch
      :: MlpParams
      -> [(VU.Vector Double, VU.Vector Double)]
      -> IO (Either Text [VU.Vector Double])
  }

-- | Bundle a backend spec + environment into an 'MlpDevice'.
mlpDeviceFromSpec :: MlpBackendSpec -> Env -> MlpDevice
mlpDeviceFromSpec spec env =
  MlpDevice
    { mlpdForward = mlpForwardWith spec env
    , mlpdBackward = mlpBackwardWith spec env
    , mlpdForwardBatch = mlpForwardBatchWith spec env
    , mlpdBatchGradient = mlpBatchGradientWith spec env
    , mlpdInputGradientBatch = mlpInputGradientBatchWith spec env
    }

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

-- Batched fused gradient ABI: (g_w1, g_b1, g_w2, g_b2) out;
--   (input[B×in], d_l_dy[B×out], w1, b1, w2) in; (inputs, hidden, outputs, batch).
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

foreign import ccall "dynamic" mkMlpForwardFun :: FunPtr MlpForwardFun -> MlpForwardFun

foreign import ccall "dynamic" mkMlpBackwardFun :: FunPtr MlpBackwardFun -> MlpBackwardFun

foreign import ccall "dynamic"
  mkMlpBatchGradientFun :: FunPtr MlpBatchGradientFun -> MlpBatchGradientFun

foreign import ccall "dynamic"
  mkMlpForwardBatchFun :: FunPtr MlpForwardBatchFun -> MlpForwardBatchFun

foreign import ccall "dynamic"
  mkMlpInputGradientBatchFun :: FunPtr MlpInputGradientBatchFun -> MlpInputGradientBatchFun

-- | Run the MLP forward pass through @spec@'s generated kernel. Returns the
-- same 'MlpForward' cache the pure 'JitML.Numerics.Mlp.mlpForward' produces,
-- with the arithmetic executed by the backend.
mlpForwardWith
  :: MlpBackendSpec -> Env -> MlpParams -> VU.Vector Double -> IO (Either Text MlpForward)
mlpForwardWith spec env params input = do
  artifactResult <- ensureKernelArtifact env (mbsEngine spec) (mbsRuntimeSource spec) (mbsHash spec)
  case artifactResult of
    Left err -> pure (Left (mbsTag spec <> " compile failed: " <> err))
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
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape

-- | Run the MLP backward pass through @spec@'s generated kernel. Returns the
-- same 'MlpGradient' the pure 'JitML.Numerics.Mlp.mlpBackward' produces.
mlpBackwardWith
  :: MlpBackendSpec
  -> Env
  -> MlpParams
  -> MlpForward
  -> VU.Vector Double
  -> IO (Either Text MlpGradient)
mlpBackwardWith spec env params fwd dLdy = do
  artifactResult <- ensureKernelArtifact env (mbsEngine spec) (mbsRuntimeSource spec) (mbsHash spec)
  case artifactResult of
    Left err -> pure (Left (mbsTag spec <> " compile failed: " <> err))
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
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape
  w1n = hidden * inputs
  w2n = outputs * hidden

-- | Batched device forward: runs the network forward over a whole minibatch in
-- one round-trip and returns the per-sample output vectors.
mlpForwardBatchWith
  :: MlpBackendSpec
  -> Env
  -> MlpParams
  -> [VU.Vector Double]
  -> IO (Either Text [VU.Vector Double])
mlpForwardBatchWith spec env params inputs
  | null inputs = pure (Right [])
  | any (\i -> VU.length i /= inputCount) inputs =
      pure (Left (mbsTag spec <> ": input shape mismatch against the network"))
  | otherwise = do
      artifactResult <- ensureKernelArtifact env (mbsEngine spec) (mbsRuntimeSource spec) (mbsHash spec)
      case artifactResult of
        Left err -> pure (Left (mbsTag spec <> " compile failed: " <> err))
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
  shape = paramShape params
  inputCount = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape

-- | Batched device gradient: given a minibatch of @(input, dL/dy)@ pairs,
-- compute the parameter gradient /summed over the batch/ in one round-trip.
mlpBatchGradientWith
  :: MlpBackendSpec
  -> Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text MlpGradient)
mlpBatchGradientWith spec env params batch
  | null batch = pure (Right (mlpZeroGradient shape))
  | any (\(i, dy) -> VU.length i /= inputs || VU.length dy /= outputs) batch =
      pure (Left (mbsTag spec <> ": input/dLdy shape mismatch against the network"))
  | otherwise = do
      artifactResult <- ensureKernelArtifact env (mbsEngine spec) (mbsRuntimeSource spec) (mbsHash spec)
      case artifactResult of
        Left err -> pure (Left (mbsTag spec <> " compile failed: " <> err))
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
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape
  w1n = hidden * inputs
  w2n = outputs * hidden

-- | Batched device input-gradient: per-sample @dL/dx@ for the minibatch.
mlpInputGradientBatchWith
  :: MlpBackendSpec
  -> Env
  -> MlpParams
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text [VU.Vector Double])
mlpInputGradientBatchWith spec env params batch
  | null batch = pure (Right [])
  | any (\(i, dy) -> VU.length i /= inputs || VU.length dy /= outputs) batch =
      pure (Left (mbsTag spec <> ": input/dLdy shape mismatch against the network"))
  | otherwise = do
      artifactResult <- ensureKernelArtifact env (mbsEngine spec) (mbsRuntimeSource spec) (mbsHash spec)
      case artifactResult of
        Left err -> pure (Left (mbsTag spec <> " compile failed: " <> err))
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
  shape = paramShape params
  inputs = mlpInputs shape
  hidden = mlpHidden shape
  outputs = mlpOutputs shape

toC :: [Double] -> [CFloat]
toC = fmap (CFloat . realToFrac)

peekFloats :: Int -> Ptr CFloat -> IO [Double]
peekFloats n ptr = fmap (\(CFloat v) -> realToFrac v) <$> peekArray n ptr

chunksOf :: Int -> VU.Vector Double -> [VU.Vector Double]
chunksOf n vec
  | n <= 0 = []
  | VU.length vec < n = []
  | otherwise = VU.take n vec : chunksOf n (VU.drop n vec)

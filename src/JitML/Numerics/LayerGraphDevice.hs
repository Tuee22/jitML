{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Linux-CPU oneDNN training runner for the typed layer graph.
--
-- The pure "JitML.Numerics.LayerGraph" tape owns graph semantics (activation,
-- residual passthrough, parameterless pool/dropout resizing). This module
-- delegates each parameterized node's update-critical affine work to generated
-- oneDNN kernels: forward pre-activation, backward-data, and backward-weights.
-- Conv2D and Conv3D nodes use oneDNN convolution forward_training/backward
-- primitives over a 1x1 channel projection, which is algebraically equivalent
-- to the current graph IR's flat affine semantics.
module JitML.Numerics.LayerGraphDevice
  ( LayerGraphDeviceEvidence (..)
  , LayerGraphDeviceForwardRun (..)
  , LayerGraphDeviceRun (..)
  , layerGraphDeviceExecutionWitness
  , layerGraphDeviceHash
  , layerGraphDeviceRuntimeSource
  , layerTrainingBackendFor
  , runLayerGraphForwardDevice
  , layerGraphSquaredErrorGradientDevice
  , layerGraphCrossEntropyGradientDevice
  , layerGraphSquaredErrorGradientBatchDevice
  , layerGraphCrossEntropyGradientBatchDevice
  , trainLayerGraphClassifierDevice
  , trainLayerGraphClassifierEpochDevice
  , classifierBatchGradientDevice
  , withCompiledLayerGraphDevice
  , runDeviceSpatialConv
  , runDeviceOp
  , runDeviceBlock

    -- * The total operator lowering (Sprint 241.1)
  , DeviceOpPlan (..)
  , LoweredOp (..)
  , lowerLayerOp
  )
where

import Control.Monad (foldM, unless)
import Data.List (transpose)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CFloat (..), CInt (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.CudaLayerTraining (renderCudaLayerTrainingSource)
import JitML.Codegen.OneDnn (renderOneDnnLayerTrainingSource)
import JitML.Codegen.RuntimeSource (KernelProgram (..), RuntimeSource (..), runtimeSourcePayload)
import JitML.Engines.Engine
  ( KernelHandle (..)
  , engineForSubstrate
  )
import JitML.Engines.Fingerprint qualified as Fingerprint
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactCompiled
  , kernelArtifactHandle
  , renderKernelArtifactError
  , withKernelSymbol
  )
import JitML.Env.Env (Env)
import JitML.Numerics.LayerGraph
  ( LayerActivation (..)
  , LayerForward (..)
  , LayerGradient (..)
  , LayerGraph
  , LayerGraphGradient (..)
  , LayerGraphTape
  , LayerKind (..)
  , LayerMode (..)
  , LayerNode (..)
  , LayerParameterGradient (..)
  , LayerParameters (..)
  , PoolKind (..)
  , layerNodeKind
  )
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Product.DeviceWitness qualified as DeviceWitness

type LayerForwardFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

type LayerBackwardDataFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

type LayerBackwardWeightsFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

-- Phase 241 — real spatial Conv2D training kernels. Geometry is passed
-- explicitly (Cin, Cout, H, W, Kh, Kw, sH, sW, pH, pW, batch) so oneDNN runs a
-- true K×K spatial convolution rather than the dense-equivalent 1×1 stand-in.
type ConvForwardFun =
  Ptr CFloat -- out
  -> Ptr CFloat -- input
  -> Ptr CFloat -- weights
  -> Ptr CFloat -- bias
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

type ConvBackwardDataFun =
  Ptr CFloat -- dx
  -> Ptr CFloat -- d_pre
  -> Ptr CFloat -- weights
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

type ConvBackwardWeightsFun =
  Ptr CFloat -- g_weights
  -> Ptr CFloat -- g_bias
  -> Ptr CFloat -- d_pre
  -> Ptr CFloat -- input
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

-- Phase 241 — 3-D spatial convolution. The 2-D triple with one more spatial
-- axis: @cin, cout, d, h, w, kd, kh, kw, sd, sh, sw, pd, ph, pw, batch@.
type Conv3DForwardFun =
  Ptr CFloat -- out
  -> Ptr CFloat -- input
  -> Ptr CFloat -- weights
  -> Ptr CFloat -- bias
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

type Conv3DBackwardDataFun =
  Ptr CFloat -- dx
  -> Ptr CFloat -- d_pre
  -> Ptr CFloat -- weights
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

type Conv3DBackwardWeightsFun =
  Ptr CFloat -- g_weights
  -> Ptr CFloat -- g_bias
  -> Ptr CFloat -- d_pre
  -> Ptr CFloat -- input
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> IO ()

-- Phase 241 — unified correct-operator device training entry. Geometry travels
-- in the @geom@ int array + @fparams@ float array; @opcode@ selects the operator
-- (10 GeGLU, 11 Norm, 12 Patch, 13 Attention, 14 Residual, 15 Pool, 16 Scale).
-- Writes @(out, dX, dW, dB)@ with dW/dB in the operator's packed segment order,
-- and returns the executed-opcode status: @0@ when the artifact ran the
-- requested operator, non-zero when it recognised no such opcode. Reading that
-- status is what stops an unrecognised operator from being reported as a
-- successful run over untouched buffers.
type OpTrainFun =
  CInt -- opcode
  -> Ptr CInt -- geom
  -> CInt -- geom_len
  -> Ptr CFloat -- fparams
  -> CInt -- fparams_len
  -> Ptr CFloat -- out
  -> Ptr CFloat -- dx
  -> Ptr CFloat -- dw
  -> Ptr CFloat -- db
  -> Ptr CFloat -- x
  -> Ptr CFloat -- weights
  -> Ptr CFloat -- bias
  -> Ptr CFloat -- dy
  -> CInt -- xlen
  -> CInt -- outlen
  -> CInt -- wlen
  -> CInt -- blen
  -> IO CInt

type BackendNameFun = IO CString

type PrimitiveNameFun = CInt -> IO CString

foreign import ccall "dynamic"
  mkLayerForwardFun :: FunPtr LayerForwardFun -> LayerForwardFun

foreign import ccall "dynamic"
  mkLayerBackwardDataFun :: FunPtr LayerBackwardDataFun -> LayerBackwardDataFun

foreign import ccall "dynamic"
  mkLayerBackwardWeightsFun :: FunPtr LayerBackwardWeightsFun -> LayerBackwardWeightsFun

foreign import ccall "dynamic"
  mkConvForwardFun :: FunPtr ConvForwardFun -> ConvForwardFun

foreign import ccall "dynamic"
  mkConvBackwardDataFun :: FunPtr ConvBackwardDataFun -> ConvBackwardDataFun

foreign import ccall "dynamic"
  mkConvBackwardWeightsFun :: FunPtr ConvBackwardWeightsFun -> ConvBackwardWeightsFun

foreign import ccall "dynamic"
  mkConv3DForwardFun :: FunPtr Conv3DForwardFun -> Conv3DForwardFun

foreign import ccall "dynamic"
  mkConv3DBackwardDataFun :: FunPtr Conv3DBackwardDataFun -> Conv3DBackwardDataFun

foreign import ccall "dynamic"
  mkConv3DBackwardWeightsFun :: FunPtr Conv3DBackwardWeightsFun -> Conv3DBackwardWeightsFun

foreign import ccall "dynamic"
  mkOpTrainFun :: FunPtr OpTrainFun -> OpTrainFun

foreign import ccall "dynamic"
  mkBackendNameFun :: FunPtr BackendNameFun -> BackendNameFun

foreign import ccall "dynamic"
  mkPrimitiveNameFun :: FunPtr PrimitiveNameFun -> PrimitiveNameFun

data LayerGraphDeviceEvidence = LayerGraphDeviceEvidence
  { layerEvidenceName :: !Text
  , layerEvidenceKind :: !Text
  , layerEvidenceBackend :: !Text
  , layerEvidenceForwardPrimitive :: !Text
  , layerEvidenceBackwardDataPrimitive :: !Text
  , layerEvidenceBackwardWeightsPrimitive :: !Text
  , layerEvidenceArtifactPath :: !Text
  , layerEvidenceArtifactCompiled :: !Bool
  }
  deriving stock (Eq, Show)

data LayerGraphDeviceRun = LayerGraphDeviceRun
  { layerGraphDeviceTape :: !LayerGraphTape
  , layerGraphDeviceGradient :: !LayerGraphGradient
  , layerGraphDeviceEvidence :: ![LayerGraphDeviceEvidence]
  }
  deriving stock (Eq, Show)

data LayerGraphDeviceForwardRun = LayerGraphDeviceForwardRun
  { layerGraphDeviceForwardTape :: !LayerGraphTape
  , layerGraphDeviceForwardEvidence :: ![LayerGraphDeviceEvidence]
  }
  deriving stock (Eq, Show)

data LayerGraphDeviceFunctions = LayerGraphDeviceFunctions
  { lgForward :: LayerForwardFun
  , lgBackwardData :: LayerBackwardDataFun
  , lgBackwardWeights :: LayerBackwardWeightsFun
  , lgConvForward :: ConvForwardFun
  , lgConvBackwardData :: ConvBackwardDataFun
  , lgConvBackwardWeights :: ConvBackwardWeightsFun
  , lgConv3DForward :: Conv3DForwardFun
  , lgConv3DBackwardData :: Conv3DBackwardDataFun
  , lgConv3DBackwardWeights :: Conv3DBackwardWeightsFun
  , lgOpTrain :: OpTrainFun
  , lgForwardPrimitive :: PrimitiveNameFun
  , lgBackwardDataPrimitive :: PrimitiveNameFun
  , lgBackwardWeightsPrimitive :: PrimitiveNameFun
  }

-- | The lanes that have a layer-graph training kernel.
--
-- Sprint `264.1`. This is deliberately narrower than 'Cache.Substrate': a
-- substrate with no rendered training kernel has no value here, so every
-- function behind this type is total and no lane can silently reach a kernel
-- another lane rendered. 'layerTrainingBackendFor' is the one boundary where a
-- substrate becomes a backend, and it fails closed.
data LayerTrainingBackend
  = OneDnnLayerTraining
  | CudaLayerTraining
  deriving stock (Eq, Show)

-- | Resolve the lane's layer-graph training backend, or fail closed naming the
-- sprint that owns the missing kernel.
--
-- @apple-silicon@ has no layer-graph training kernel: the Metal renderer emits
-- source metadata for the /family/ kernels only. Serving that lane's training
-- through the @linux-cpu@ oneDNN artifact would attribute a run to hardware that
-- did not execute it, and falling back to the pure executor is what the
-- hardware-native determinism contract forbids, so this is an error rather than
-- a default.
layerTrainingBackendFor :: Cache.Substrate -> Either Text LayerTrainingBackend
layerTrainingBackendFor substrate =
  case substrate of
    Cache.LinuxCPU -> Right OneDnnLayerTraining
    Cache.LinuxCUDA -> Right CudaLayerTraining
    Cache.AppleSilicon ->
      Left
        ( "layer-graph device training has no apple-silicon kernel: the Metal "
            <> "layer-training renderer is Sprint 270.1's"
        )

-- | The substrate a backend /is/, read off the backend that executes rather
-- than off the substrate that was requested.
layerTrainingBackendSubstrate :: LayerTrainingBackend -> Cache.Substrate
layerTrainingBackendSubstrate OneDnnLayerTraining = Cache.LinuxCPU
layerTrainingBackendSubstrate CudaLayerTraining = Cache.LinuxCUDA

layerGraphDeviceKernelSpec :: LayerTrainingBackend -> Cache.KernelSpec
layerGraphDeviceKernelSpec OneDnnLayerTraining =
  Cache.KernelSpec "layer-graph-training-onednn-affine-conv"
layerGraphDeviceKernelSpec CudaLayerTraining =
  Cache.KernelSpec "layer-graph-training-cuda-affine-conv"

layerGraphDeviceRuntimeSource :: LayerTrainingBackend -> RuntimeSource
layerGraphDeviceRuntimeSource backend =
  case backend of
    OneDnnLayerTraining ->
      GeneratedOneDnnSource
        { runtimeSourceKernel = layerGraphDeviceKernelSpec backend
        , runtimeSourceKind = Cache.Training
        , runtimeSourceTuning = Cache.defaultTuningChoice
        , runtimeSourceProgramKind = LayerTrainingProgram
        , runtimeSourceFiles = renderOneDnnLayerTrainingSource
        }
    CudaLayerTraining ->
      GeneratedCudaSource
        { runtimeSourceKernel = layerGraphDeviceKernelSpec backend
        , runtimeSourceKind = Cache.Training
        , runtimeSourceTuning = Cache.defaultTuningChoice
        , runtimeSourceProgramKind = LayerTrainingProgram
        , runtimeSourceFiles = renderCudaLayerTrainingSource
        }

layerGraphDeviceHash :: LayerTrainingBackend -> Cache.Hash
layerGraphDeviceHash backend =
  Cache.cacheKey
    (layerGraphDeviceKernelSpec backend)
    Cache.Training
    (layerTrainingBackendSubstrate backend)
    (Fingerprint.layerTrainingToolchainFingerprint (layerTrainingBackendSubstrate backend))
    (runtimeSourcePayload (layerGraphDeviceRuntimeSource backend))
    Cache.defaultTuningChoice

runLayerGraphForwardDevice
  :: Cache.Substrate
  -> Env
  -> LayerGraph
  -> Vector Double
  -> IO (Either Text LayerGraphDeviceForwardRun)
runLayerGraphForwardDevice substrate env graph input =
  withCompiledLayerGraphDevice substrate env $ \functions backendName artifactPath artifactCompiled ->
    deviceForwardGraph functions backendName artifactPath artifactCompiled graph input

layerGraphSquaredErrorGradientDevice
  :: Cache.Substrate
  -> Env
  -> LayerGraph
  -> Vector Double
  -> Vector Double
  -> IO (Either Text LayerGraphDeviceRun)
layerGraphSquaredErrorGradientDevice substrate env graph input target =
  case LayerGraph.layerGraphSquaredErrorGradient graph input target of
    Left err -> pure (Left err)
    Right (tape, pureGradient) -> do
      let seed = VU.zipWith (-) (LayerGraph.layerTapeOutput tape) target
      withCompiledLayerGraphDevice substrate env $ \functions backendName artifactPath artifactCompiled -> do
        deviceResult <-
          deviceGradient
            functions
            backendName
            artifactPath
            artifactCompiled
            seed
            tape
            pureGradient
        pure $
          fmap
            ( \(gradient, evidence) ->
                LayerGraphDeviceRun
                  { layerGraphDeviceTape = tape
                  , layerGraphDeviceGradient = gradient
                  , layerGraphDeviceEvidence = evidence
                  }
            )
            deviceResult

-- | Classification counterpart of 'layerGraphSquaredErrorGradientDevice': runs
-- the update-critical layer-graph training kernels on the oneDNN device for a
-- single labelled example, seeding the backward pass with the softmax
-- cross-entropy output gradient via 'LayerGraph.layerGraphCrossEntropyGradient'.
layerGraphCrossEntropyGradientDevice
  :: Cache.Substrate
  -> Env
  -> LayerGraph
  -> Vector Double
  -> Int
  -> IO (Either Text LayerGraphDeviceRun)
layerGraphCrossEntropyGradientDevice substrate env graph input label =
  case LayerGraph.layerGraphCrossEntropyGradient graph input label of
    Left err -> pure (Left err)
    Right (tape, pureGradient) -> do
      let logits = LayerGraph.layerTapeOutput tape
          seed = VU.imap (\i p -> p - if i == label then 1.0 else 0.0) (softmax logits)
      withCompiledLayerGraphDevice substrate env $ \functions backendName artifactPath artifactCompiled -> do
        deviceResult <-
          deviceGradient
            functions
            backendName
            artifactPath
            artifactCompiled
            seed
            tape
            pureGradient
        pure $
          fmap
            ( \(gradient, evidence) ->
                LayerGraphDeviceRun
                  { layerGraphDeviceTape = tape
                  , layerGraphDeviceGradient = gradient
                  , layerGraphDeviceEvidence = evidence
                  }
            )
            deviceResult

-- | Batched squared-error gradient: runs the pure oracle once per example, then
-- one batched oneDNN device call per layer over the whole batch (oneDNN
-- @backward_weights@ sums the parameter gradient over the batch).  The returned
-- gradient is the batch-summed gradient, matching the per-example summed oracle
-- within float32 tolerance; only one device round-trip per layer is taken.
layerGraphSquaredErrorGradientBatchDevice
  :: Cache.Substrate
  -> Env
  -> LayerGraph
  -> [(Vector Double, Vector Double)]
  -> IO (Either Text LayerGraphDeviceRun)
layerGraphSquaredErrorGradientBatchDevice substrate env graph batch
  | null batch = pure (Left "layerGraphSquaredErrorGradientBatchDevice: empty batch")
  | otherwise =
      case traverse (uncurry (LayerGraph.layerGraphSquaredErrorGradient graph)) batch of
        Left err -> pure (Left err)
        Right [] -> pure (Left "layerGraphSquaredErrorGradientBatchDevice: empty batch")
        Right pairs@(pair0 : _) -> do
          let seeds =
                zipWith
                  (\(tape, _) (_, target) -> VU.zipWith (-) (LayerGraph.layerTapeOutput tape) target)
                  pairs
                  batch
          withCompiledLayerGraphDevice substrate env $ \functions backendName artifactPath artifactCompiled -> do
            deviceResult <-
              deviceGradientBatch functions backendName artifactPath artifactCompiled seeds pairs
            pure (fmap (batchRun (fst pair0)) deviceResult)

-- | Batched classification counterpart of
-- 'layerGraphSquaredErrorGradientBatchDevice'.
layerGraphCrossEntropyGradientBatchDevice
  :: Cache.Substrate
  -> Env
  -> Int
  -> LayerGraph
  -> [(Vector Double, Int)]
  -> IO (Either Text LayerGraphDeviceRun)
layerGraphCrossEntropyGradientBatchDevice substrate env classes graph batch
  | null batch = pure (Left "layerGraphCrossEntropyGradientBatchDevice: empty batch")
  | otherwise =
      case traverse (uncurry (LayerGraph.layerGraphClassifierCrossEntropyGradient graph classes)) batch of
        Left err -> pure (Left err)
        Right [] -> pure (Left "layerGraphCrossEntropyGradientBatchDevice: empty batch")
        Right pairs@(pair0 : _) -> do
          let seeds =
                zipWith
                  (\(tape, _) (_, label) -> classifierSeed classes (LayerGraph.layerTapeOutput tape) label)
                  pairs
                  batch
          withCompiledLayerGraphDevice substrate env $ \functions backendName artifactPath artifactCompiled -> do
            deviceResult <-
              deviceGradientBatch functions backendName artifactPath artifactCompiled seeds pairs
            pure (fmap (batchRun (fst pair0)) deviceResult)

-- | Batch-summed flat classification cross-entropy parameter gradient over the
-- semantic-prefix @classes@ logits, through the oneDNN device (one batched device
-- call per layer; @backward_weights@ sums over the batch). The device counterpart
-- of 'LayerGraph.pureClassifierBatchGradient', used by the Adam/SGD graph
-- optimizer steppers.
classifierBatchGradientDevice
  :: Cache.Substrate
  -> Env
  -> Int
  -> LayerGraph
  -> [(Vector Double, Int)]
  -> IO (Either Text (Vector Double))
classifierBatchGradientDevice substrate env classes graph batch = do
  runResult <- layerGraphCrossEntropyGradientBatchDevice substrate env classes graph batch
  pure (fmap (LayerGraph.flattenLayerGraphGradient . layerGraphDeviceGradient) runResult)

batchRun
  :: LayerGraphTape
  -> (LayerGraphGradient, [LayerGraphDeviceEvidence])
  -> LayerGraphDeviceRun
batchRun tape (gradient, evidence) =
  LayerGraphDeviceRun
    { layerGraphDeviceTape = tape
    , layerGraphDeviceGradient = gradient
    , layerGraphDeviceEvidence = evidence
    }

-- | Full-batch Adam training of a classification 'LayerGraph' through the
-- oneDNN device cross-entropy gradient.  Each epoch accumulates the per-example
-- softmax cross-entropy gradient over the dataset, averages it, and takes one
-- Adam step on the graph's flat parameter vector via
-- 'LayerGraph.replaceGraphParameterVector'.  This is the IR-native supervised
-- classification training loop that makes the typed 'LayerGraph' the single
-- owner of training (Sprint 235.1).
trainLayerGraphClassifierDevice
  :: Cache.Substrate
  -> Env
  -> Int
  -- ^ semantic class count (softmax/CE gradient is taken over the first @classes@
  -- logits; the graph output is @classes + 1@ raw logits)
  -> Int
  -- ^ epochs
  -> Int
  -- ^ mini-batch size (examples are consumed in deterministic order)
  -> Double
  -- ^ learning rate
  -> LayerGraph
  -> [(Vector Double, Int)]
  -- ^ @(features, class label)@ examples
  -> IO (Either Text LayerGraph)
trainLayerGraphClassifierDevice substrate env classes epochs batchSize learningRate graph0 dataset
  | epochs <= 0 = pure (Left "trainLayerGraphClassifierDevice: epochs must be positive")
  | batchSize <= 0 = pure (Left "trainLayerGraphClassifierDevice: batch size must be positive")
  | classes <= 0 = pure (Left "trainLayerGraphClassifierDevice: class count must be positive")
  | null dataset = pure (Left "trainLayerGraphClassifierDevice: empty dataset")
  | otherwise = runEpochs 1 (LayerGraph.initGraphClassifierAdam graph0)
 where
  runEpochs epoch st
    | epoch > epochs = pure (Right (LayerGraph.gcaGraph st))
    | otherwise = do
        stepped <-
          trainLayerGraphClassifierEpochDevice substrate env classes batchSize learningRate st dataset
        case stepped of
          Left err -> pure (Left err)
          Right st' -> runEpochs (epoch + 1) st'

-- | Run one oneDNN device training epoch (all mini-batches, Adam moments
-- threaded through 'LayerGraph.GraphClassifierAdam') over a classification
-- dataset. This is the device counterpart of
-- 'LayerGraph.trainLayerGraphClassifierEpochPure' and shares the same pure Adam
-- step ('LayerGraph.graphAdamBatchStep'), so the device and pure trajectories are
-- identical up to the @float32@ device gradient. Exposing a per-epoch stepper (vs
-- an all-epochs loop) lets validation-driven model selection thread Adam moments
-- across epochs while snapshotting the best graph.
trainLayerGraphClassifierEpochDevice
  :: Cache.Substrate
  -> Env
  -> Int
  -> Int
  -> Double
  -> LayerGraph.GraphClassifierAdam
  -> [(Vector Double, Int)]
  -> IO (Either Text LayerGraph.GraphClassifierAdam)
trainLayerGraphClassifierEpochDevice substrate env classes batchSize learningRate st0 dataset =
  foldBatches (LayerGraph.classifierBatches batchSize dataset) st0
 where
  foldBatches [] st = pure (Right st)
  foldBatches (batch : rest) st = do
    -- One batched device call per layer over the whole mini-batch; the oneDNN
    -- @backward_weights@ reduction sums the parameter gradient over the batch, so
    -- the returned flat gradient is already the batch sum.
    runResult <-
      layerGraphCrossEntropyGradientBatchDevice substrate env classes (LayerGraph.gcaGraph st) batch
    case runResult
      >>= ( \run ->
              LayerGraph.graphAdamBatchStep
                learningRate
                st
                (LayerGraph.flattenLayerGraphGradient (layerGraphDeviceGradient run))
                (length batch)
          ) of
      Left err -> pure (Left err)
      Right st' -> foldBatches rest st'

withCompiledLayerGraphDevice
  :: Cache.Substrate
  -> Env
  -> (LayerGraphDeviceFunctions -> Text -> Text -> Bool -> IO (Either Text a))
  -> IO (Either Text a)
withCompiledLayerGraphDevice substrate env useFunctions =
  case layerTrainingBackendFor substrate of
    Left err -> pure (Left err)
    Right backend -> withCompiledLayerGraphBackend backend env useFunctions

withCompiledLayerGraphBackend
  :: LayerTrainingBackend
  -> Env
  -> (LayerGraphDeviceFunctions -> Text -> Text -> Bool -> IO (Either Text a))
  -> IO (Either Text a)
withCompiledLayerGraphBackend backend env useFunctions = do
  artifactResult <-
    ensureKernelArtifact
      env
      (engineForSubstrate (layerTrainingBackendSubstrate backend))
      (layerGraphDeviceRuntimeSource backend)
      (layerGraphDeviceHash backend)
  case artifactResult of
    Left err ->
      pure
        ( Left
            ( "layergraph device compile failed on "
                <> Cache.substrateText (layerTrainingBackendSubstrate backend)
                <> ": "
                <> renderKernelArtifactError err
            )
        )
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = kernelHandleArtifactPath handle
          path = Text.unpack artifactPath
      withKernelSymbol path "jitml_layer_training_backend" $ \backendSymbol ->
        withKernelSymbol path "jitml_layer_forward_primitive" $ \forwardNameSymbol ->
          withKernelSymbol path "jitml_layer_backward_data_primitive" $ \dataNameSymbol ->
            withKernelSymbol path "jitml_layer_backward_weights_primitive" $ \weightsNameSymbol ->
              withKernelSymbol path "jitml_layer_forward" $ \forwardSymbol ->
                withKernelSymbol path "jitml_layer_backward_data" $ \dataSymbol ->
                  withKernelSymbol path "jitml_layer_backward_weights" $ \weightsSymbol ->
                    withKernelSymbol path "jitml_conv2d_spatial_forward" $ \convFwdSymbol ->
                      withKernelSymbol path "jitml_conv2d_spatial_backward_data" $ \convDataSymbol ->
                        withKernelSymbol path "jitml_conv2d_spatial_backward_weights" $ \convWeightsSymbol ->
                          withKernelSymbol path "jitml_conv3d_spatial_forward" $ \conv3FwdSymbol ->
                            withKernelSymbol path "jitml_conv3d_spatial_backward_data" $ \conv3DataSymbol ->
                              withKernelSymbol path "jitml_conv3d_spatial_backward_weights" $ \conv3WeightsSymbol ->
                                withKernelSymbol path "jitml_op_train" $ \opTrainSymbol -> do
                                  backendName <- cStringText =<< mkBackendNameFun backendSymbol
                                  let functions =
                                        LayerGraphDeviceFunctions
                                          { lgForward = mkLayerForwardFun forwardSymbol
                                          , lgBackwardData = mkLayerBackwardDataFun dataSymbol
                                          , lgBackwardWeights = mkLayerBackwardWeightsFun weightsSymbol
                                          , lgConvForward = mkConvForwardFun convFwdSymbol
                                          , lgConvBackwardData = mkConvBackwardDataFun convDataSymbol
                                          , lgConvBackwardWeights = mkConvBackwardWeightsFun convWeightsSymbol
                                          , lgConv3DForward = mkConv3DForwardFun conv3FwdSymbol
                                          , lgConv3DBackwardData = mkConv3DBackwardDataFun conv3DataSymbol
                                          , lgConv3DBackwardWeights =
                                              mkConv3DBackwardWeightsFun conv3WeightsSymbol
                                          , lgOpTrain = mkOpTrainFun opTrainSymbol
                                          , lgForwardPrimitive = mkPrimitiveNameFun forwardNameSymbol
                                          , lgBackwardDataPrimitive = mkPrimitiveNameFun dataNameSymbol
                                          , lgBackwardWeightsPrimitive =
                                              mkPrimitiveNameFun weightsNameSymbol
                                          }
                                  useFunctions
                                    functions
                                    backendName
                                    artifactPath
                                    (kernelArtifactCompiled artifact)

-- | Mint the execution witness for the layer-graph training kernel.
--
-- This is deliberately not derivable from a substrate label: it loads the
-- artifact the training loop just used, asks that artifact which backend it is
-- (@jitml_layer_training_backend@) and which primitive it lowers a dense layer
-- to (@jitml_layer_forward_primitive@), and digests the compiled bytes. A host
-- with no oneDNN toolchain, or a run that never compiled the kernel, cannot
-- produce the value at all.
--
-- Callers record it only after their training loop has returned successfully,
-- so the witness attests an execution rather than an intent.
layerGraphDeviceExecutionWitness
  :: Cache.Substrate -> Env -> IO (Either Text DeviceWitness.DeviceExecutionWitness)
layerGraphDeviceExecutionWitness substrate env =
  case layerTrainingBackendFor substrate of
    Left err -> pure (Left err)
    Right backend ->
      withCompiledLayerGraphBackend backend env $ \functions backendName artifactPath _compiled -> do
        executedPrimitive <- primitiveNameText (lgForwardPrimitive functions) 0
        DeviceWitness.witnessDeviceExecution
          (layerTrainingBackendSubstrate backend)
          backendName
          (Cache.hashHex (layerGraphDeviceHash backend))
          (Text.unpack artifactPath)
          executedPrimitive

deviceForwardGraph
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> LayerGraph
  -> Vector Double
  -> IO (Either Text LayerGraphDeviceForwardRun)
deviceForwardGraph functions backendName artifactPath artifactCompiled graph input =
  case LayerGraph.tensorShapeWidth (LayerGraph.layerGraphInputShape graph) of
    Left err -> pure (Left err)
    Right inputWidth
      | VU.length input /= inputWidth ->
          pure
            ( Left
                ( LayerGraph.layerGraphName graph
                    <> " expected input width "
                    <> Text.pack (show inputWidth)
                    <> ", got "
                    <> Text.pack (show (VU.length input))
                )
            )
      | otherwise -> do
          folded <-
            foldM
              ( \state node ->
                  case state of
                    Left err -> pure (Left err)
                    Right (current, layers, evidence) -> do
                      nodeResult <-
                        deviceForwardNode
                          functions
                          backendName
                          artifactPath
                          artifactCompiled
                          node
                          current
                      pure $
                        case nodeResult of
                          Left err -> Left err
                          Right (forward, maybeEvidence) ->
                            Right
                              ( layerForwardOutput forward
                              , forward : layers
                              , maybe evidence (: evidence) maybeEvidence
                              )
              )
              (Right (input, [], []))
              (LayerGraph.layerGraphNodes graph)
          pure $ do
            (output, layers, evidence) <- folded
            outputWidth <- LayerGraph.tensorShapeWidth (LayerGraph.layerGraphOutputShape graph)
            unless (VU.length output == outputWidth) $
              Left
                ( LayerGraph.layerGraphName graph
                    <> " produced output width "
                    <> Text.pack (show (VU.length output))
                    <> ", expected "
                    <> Text.pack (show outputWidth)
                )
            let tape =
                  LayerGraph.LayerGraphTape
                    { LayerGraph.layerTapeInput = input
                    , LayerGraph.layerTapeOutput = output
                    , LayerGraph.layerTapeLayers = reverse layers
                    }
            Right
              LayerGraphDeviceForwardRun
                { layerGraphDeviceForwardTape = tape
                , layerGraphDeviceForwardEvidence = reverse evidence
                }

deviceForwardNode
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> LayerNode
  -> Vector Double
  -> IO (Either Text (LayerForward, Maybe LayerGraphDeviceEvidence))
deviceForwardNode functions backendName artifactPath artifactCompiled node input =
  case ( LayerGraph.tensorShapeWidth (layerInputShape node)
       , LayerGraph.tensorShapeWidth (layerOutputShape node)
       ) of
    (Left err, _) -> pure (Left err)
    (_, Left err) -> pure (Left err)
    (Right inputWidth, Right outputWidth)
      | VU.length input /= inputWidth ->
          pure
            ( Left
                ( layerNodeName node
                    <> " expected input width "
                    <> Text.pack (show inputWidth)
                    <> ", got "
                    <> Text.pack (show (VU.length input))
                )
            )
      | otherwise ->
          case layerParameters node of
            Just params -> do
              let transformedInput =
                    input
              preResult <-
                runDeviceForwardOnly
                  functions
                  (layerKindCode (layerNodeKind node))
                  params
                  transformedInput
                  inputWidth
                  outputWidth
              case preResult of
                Left err -> pure (Left err)
                Right preActivation -> do
                  evidence <-
                    mkEvidence
                      functions
                      backendName
                      artifactPath
                      artifactCompiled
                      node
                      (layerKindCode (layerNodeKind node))
                  let activated = applyActivation (layerActivation node) preActivation
                      output =
                        case residualScale (layerNodeKind node) of
                          Just scale
                            | VU.length input == VU.length activated ->
                                VU.zipWith (+) input (VU.map (* scale) activated)
                          _ -> activated
                  pure (Right (forward preActivation output, Just evidence))
            Nothing -> do
              let output = parameterlessForward node input outputWidth
              pure (Right (forward output output, Nothing))
 where
  forward preActivation output =
    LayerForward
      { layerForwardNode = node
      , layerForwardInput = input
      , layerForwardPreActivation = preActivation
      , layerForwardOutput = output
      }

deviceGradient
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> Vector Double
  -- ^ loss seed: gradient of the loss w.r.t. the graph output
  -> LayerGraphTape
  -> LayerGraphGradient
  -> IO (Either Text (LayerGraphGradient, [LayerGraphDeviceEvidence]))
deviceGradient functions backendName artifactPath artifactCompiled seed tape pureGradient = do
  let forwards = LayerGraph.layerTapeLayers tape
      gradients = layerGraphLayerGradients pureGradient
      upstreams = perNodeUpstreams seed gradients
  if length forwards /= length gradients
    then pure (Left "layergraph-onednn: tape/gradient layer count mismatch")
    else do
      results <-
        traverse
          ( \(up, fwd, gr) ->
              deviceLayerGradient functions backendName artifactPath artifactCompiled up fwd gr
          )
          (zip3 upstreams forwards gradients)
      pure $ do
        pairs <- sequence results
        let deviceGradients = fmap fst pairs
            evidence = [entry | (_grad, Just entry) <- pairs]
        pure
          ( pureGradient
              { layerGraphInputGradient =
                  case deviceGradients of
                    [] -> layerGraphInputGradient pureGradient
                    firstGradient : _ -> layerGradientInput firstGradient
              , layerGraphLayerGradients = deviceGradients
              }
          , evidence
          )

deviceLayerGradient
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> Vector Double
  -- ^ upstream: gradient of the loss w.r.t. this node's output
  -> LayerForward
  -> LayerGradient
  -> IO (Either Text (LayerGradient, Maybe LayerGraphDeviceEvidence))
deviceLayerGradient functions backendName artifactPath artifactCompiled upstream forward pureGradient =
  case lowerLayerOp node of
    Left err -> pure (Left err)
    Right lowered ->
      case (lowered, layerParameters node, layerGradientParameters pureGradient) of
        -- Parameterless operators (pooling, dropout, identity) still execute:
        -- they lower to an opcode and their input gradient comes back from the
        -- device rather than from the pure executor.
        (LowerOpTrain plan, Nothing, Nothing) -> parameterFreeSingle plan
        (LowerDenseAffine, Just params, Just paramGradient) -> denseSingle params paramGradient
        (LowerSpatialConv spec, Just params, Just _) -> convSingle spec params
        (LowerBlockComposition, Just _, Just _) -> blockSingle
        (LowerOpTrain plan, Just _, Just _) -> genericSingle plan
        _ ->
          pure
            ( Left
                ( "layergraph-onednn: parameter/gradient mismatch for "
                    <> layerGradientName pureGradient
                )
            )
 where
  node = layerForwardNode forward
  input = layerForwardInput forward
  -- A parameterless node keeps its 'Nothing' parameter gradient; what changes
  -- is that its input gradient is the device's, not the host oracle's.
  parameterFreeSingle plan = do
    result <- runDeviceOpPlan functions plan input upstream VU.empty VU.empty
    case result of
      Left err -> pure (Left err)
      Right (_out, dInput, _dW, _dB) -> do
        evidence <-
          mkEvidence functions backendName artifactPath artifactCompiled node (dopEvidenceCode plan)
        pure (Right (pureGradient {layerGradientInput = dInput}, Just evidence))
  finish evidenceCode dInput dW dB = do
    evidence <- mkEvidence functions backendName artifactPath artifactCompiled node evidenceCode
    pure
      ( Right
          ( pureGradient
              { layerGradientInput = dInput
              , layerGradientParameters =
                  Just (LayerParameterGradient {layerGradWeights = dW, layerGradBias = dB})
              }
          , Just evidence
          )
      )
  -- Existing dense flat path (unchanged): seeds the device backward with the
  -- pure oracle's pre-activation gradient (== bias gradient for a dense op) and
  -- dispatches on the coarse layer-kind tag, preserving Tier-1 fixture evidence.
  denseSingle params paramGradient = do
    let dPre = layerGradBias paramGradient
        inputs = VU.length input
        outputs = VU.length dPre
        kindCode = layerKindCode (layerNodeKind node)
    result <- runDeviceLayer functions kindCode params input dPre inputs outputs 1
    case result of
      Left err -> pure (Left err)
      Right (preActivation, transformedInputGradient, weightGradient, biasGradient)
        | VU.length preActivation /= VU.length (layerForwardPreActivation forward) ->
            pure
              ( Left
                  ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
              )
        | otherwise ->
            finish
              kindCode
              ( if isResidualKind (layerNodeKind node)
                  then layerGradientInput pureGradient
                  else transformedInputGradient
              )
              weightGradient
              biasGradient
  -- Real spatial convolution: differentiate the node activation on the host to
  -- recover the pre-activation gradient, then run the oneDNN spatial conv
  -- forward/backward-data/backward-weights. The evidence code comes from the
  -- geometry that ran rather than a literal, so a three-dimensional convolution
  -- cannot be recorded as the two-dimensional primitive.
  convSingle spec params = do
    let dPre = activationBackwardLocal (layerActivation node) (layerForwardOutput forward) upstream
    result <- runDeviceSpatialConv functions spec params input dPre
    case result of
      Left err -> pure (Left err)
      Right (_out, dx, dw, db) -> finish (spatialConvEvidenceCode spec) dx dw db
  -- GeGLU / Norm / Attention / Patch / Residual: one unified device kernel per
  -- operator driven by the true upstream output gradient; dW/dB come back in the
  -- operator's packed segment order.
  genericSingle plan = do
    result <- runDeviceOp functions node input upstream
    case result of
      Left err -> pure (Left err)
      Right (out, dx, dw, db)
        | VU.length out /= VU.length (layerForwardPreActivation forward) ->
            pure
              ( Left
                  ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
              )
        | otherwise -> finish (dopEvidenceCode plan) dx dw db
  -- BasicBlock / Bottleneck: composed on-device from the dense-affine and norm
  -- sub-kernels ('runDeviceBlock'); dW/dB come back in the block's packed
  -- 'opWeightSegments'/'opBiasSegments' order.
  blockSingle = do
    result <- runDeviceBlock functions node input upstream
    case result of
      Left err -> pure (Left err)
      Right (out, dx, dw, db)
        | VU.length out /= VU.length (layerForwardPreActivation forward) ->
            pure
              ( Left
                  ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
              )
        | otherwise -> finish blockEvidenceCode dx dw db

-- | Batched analogue of 'deviceGradient': transposes N per-example tapes/pure
-- gradients into per-layer bundles and takes one batched device call per layer.
-- The returned layer-graph gradient is the batch sum (matching the per-example
-- summed oracle); one evidence entry is recorded per parameterized layer.
deviceGradientBatch
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> [Vector Double]
  -- ^ per-example loss seeds (aligned with @pairs@)
  -> [(LayerGraphTape, LayerGraphGradient)]
  -> IO (Either Text (LayerGraphGradient, [LayerGraphDeviceEvidence]))
deviceGradientBatch _ _ _ _ _ [] = pure (Left "layergraph-onednn: empty batch")
deviceGradientBatch functions backendName artifactPath artifactCompiled seeds pairs@(pair0 : _)
  | any ((/= layerCount) . length) forwardsN
      || any ((/= layerCount) . length) gradsN =
      pure (Left "layergraph-onednn: tape/gradient layer count mismatch")
  | otherwise = do
      results <-
        traverse
          ( \(ups, fwds, grs) ->
              deviceLayerGradientBatch functions backendName artifactPath artifactCompiled ups fwds grs
          )
          (zip3 (transpose upstreamsN) (transpose forwardsN) (transpose gradsN))
      pure $ do
        summedLayers <- sequence results
        let deviceLayers = fmap fst summedLayers
            evidence = [entry | (_grad, Just entry) <- summedLayers]
        pure
          ( template
              { layerGraphInputGradient =
                  case deviceLayers of
                    [] -> layerGraphInputGradient template
                    firstLayer : _ -> layerGradientInput firstLayer
              , layerGraphLayerGradients = deviceLayers
              }
          , evidence
          )
 where
  forwardsN = fmap (LayerGraph.layerTapeLayers . fst) pairs
  gradsN = fmap (layerGraphLayerGradients . snd) pairs
  upstreamsN = zipWith perNodeUpstreams seeds gradsN
  layerCount = length (LayerGraph.layerTapeLayers (fst pair0))
  template = snd pair0

-- | Batched analogue of 'deviceLayerGradient' for one layer over N examples.
-- The dense flat path takes one batched oneDNN call (@backward_weights@ sums the
-- parameter gradient over the batch). The correct-operator paths (spatial conv,
-- GeGLU/Norm/Attention/Patch/Residual) fold the single-example device kernel over
-- the batch, summing parameter and input gradients in ascending example order.
deviceLayerGradientBatch
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> [Vector Double]
  -- ^ per-example upstream output gradients (aligned with @forwards@)
  -> [LayerForward]
  -> [LayerGradient]
  -> IO (Either Text (LayerGradient, Maybe LayerGraphDeviceEvidence))
deviceLayerGradientBatch _ _ _ _ _ [] _ =
  pure (Left "layergraph-onednn: empty layer batch")
deviceLayerGradientBatch _ _ _ _ _ _ [] =
  pure (Left "layergraph-onednn: empty layer batch")
deviceLayerGradientBatch functions backendName artifactPath artifactCompiled upstreams forwards@(forward0 : _) grads@(template : _) =
  case lowerLayerOp node of
    Left err -> pure (Left err)
    Right lowered ->
      case (lowered, layerParameters node, layerGradientParameters template) of
        (LowerOpTrain plan, Nothing, Nothing) -> parameterFreeBatch plan
        (LowerDenseAffine, Just params, Just paramGradient) -> denseBatch params paramGradient
        (LowerSpatialConv spec, Just params, Just _) ->
          foldExamples (spatialConvEvidenceCode spec) $ \fwd up ->
            let dPre =
                  activationBackwardLocal (layerActivation node) (layerForwardOutput fwd) up
             in fmap (fmap dropForward) (runDeviceSpatialConv functions spec params (layerForwardInput fwd) dPre)
        (LowerBlockComposition, Just _, Just _) ->
          foldExamples blockEvidenceCode $ \fwd up ->
            fmap (fmap dropForward) (runDeviceBlock functions (layerForwardNode fwd) (layerForwardInput fwd) up)
        (LowerOpTrain plan, Just _, Just _) ->
          foldExamples (dopEvidenceCode plan) $ \fwd up ->
            fmap (fmap dropForward) (runDeviceOp functions node (layerForwardInput fwd) up)
        _ ->
          pure
            ( Left
                ("layergraph-onednn: parameter/gradient mismatch for " <> layerGradientName template)
            )
 where
  node = layerForwardNode forward0
  batchN = length forwards
  summedPureInput = sumVecs (fmap layerGradientInput grads)
  dropForward (_out, dx, dw, db) = (dx, dw, db)
  -- Parameterless operators fold the same single-example device kernel over the
  -- batch and sum the input gradients; the parameter gradient stays absent.
  parameterFreeBatch plan = do
    folded <-
      foldDeviceExamples
        ( \fwd up ->
            fmap
              (fmap dropForward)
              (runDeviceOpPlan functions plan (layerForwardInput fwd) up VU.empty VU.empty)
        )
        forwards
        upstreams
    case folded of
      Left err -> pure (Left err)
      Right (dxSum, _dwSum, _dbSum) -> do
        evidence <-
          mkEvidence functions backendName artifactPath artifactCompiled node (dopEvidenceCode plan)
        pure (Right (template {layerGradientInput = dxSum}, Just evidence))
  -- Existing dense flat path: one concatenated batched device round-trip.
  denseBatch params paramGradient = do
    let inputs = VU.length (layerForwardInput forward0)
        outputs = VU.length (layerGradBias paramGradient)
        kindCode = layerKindCode (layerNodeKind node)
        inputFlat = VU.concat (fmap layerForwardInput forwards)
        dPreFlat = VU.concat [layerGradBias pg | Just pg <- fmap layerGradientParameters grads]
    result <- runDeviceLayer functions kindCode params inputFlat dPreFlat inputs outputs batchN
    case result of
      Left err -> pure (Left err)
      Right (preActivation, transformedInputGradient, weightGradient, biasGradient)
        | VU.length preActivation /= batchN * VU.length (layerForwardPreActivation forward0) ->
            pure
              ( Left
                  ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
              )
        | otherwise -> do
            evidence <- mkEvidence functions backendName artifactPath artifactCompiled node kindCode
            let deviceInputGradient =
                  if isResidualKind (layerNodeKind node)
                    then summedPureInput
                    else sumRows batchN inputs transformedInputGradient
            pure
              ( Right
                  ( template
                      { layerGradientInput = deviceInputGradient
                      , layerGradientParameters =
                          Just (LayerParameterGradient weightGradient biasGradient)
                      }
                  , Just evidence
                  )
              )
  -- Correct-operator path: fold the single-example device kernel over the batch.
  foldExamples evCode runOne = do
    folded <- foldDeviceExamples runOne forwards upstreams
    case folded of
      Left err -> pure (Left err)
      Right (dxSum, dwSum, dbSum) -> do
        evidence <- mkEvidence functions backendName artifactPath artifactCompiled node evCode
        pure
          ( Right
              ( template
                  { layerGradientInput = dxSum
                  , layerGradientParameters = Just (LayerParameterGradient dwSum dbSum)
                  }
              , Just evidence
              )
          )

-- | Fold a single-example device operator kernel over a batch, summing the
-- @(dInput, dWeights, dBias)@ triples in ascending example order.
foldDeviceExamples
  :: (LayerForward -> Vector Double -> IO (Either Text (Vector Double, Vector Double, Vector Double)))
  -> [LayerForward]
  -> [Vector Double]
  -> IO (Either Text (Vector Double, Vector Double, Vector Double))
foldDeviceExamples runOne forwards upstreams = go (zip forwards upstreams) Nothing
 where
  go [] Nothing = pure (Left "layergraph-onednn: empty layer batch")
  go [] (Just acc) = pure (Right acc)
  go ((fwd, up) : rest) macc = do
    result <- runOne fwd up
    case result of
      Left err -> pure (Left err)
      Right (dx, dw, db) ->
        let acc' =
              case macc of
                Nothing -> (dx, dw, db)
                Just (dxS, dwS, dbS) ->
                  (VU.zipWith (+) dxS dx, VU.zipWith (+) dwS dw, VU.zipWith (+) dbS db)
         in go rest (Just acc')

-- | Fixed-order component-wise sum of equal-length vectors (empty when no input).
sumVecs :: [Vector Double] -> Vector Double
sumVecs [] = VU.empty
sumVecs (v : vs) = foldl' (VU.zipWith (+)) v vs

-- | Sum the @n@ consecutive @width@-length rows of a flat @n*width@ vector.
sumRows :: Int -> Int -> Vector Double -> Vector Double
sumRows n width flat =
  sumVecs [VU.slice (row * width) width flat | row <- [0 .. n - 1]]

runDeviceLayer
  :: LayerGraphDeviceFunctions
  -> CInt
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> Int
  -> Int
  -> Int
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceLayer functions kindCode params input dPre inputs outputs batchN
  | VU.length (layerWeights params) /= inputs * outputs =
      pure (Left "layergraph-onednn: weight length does not match input/output width")
  | VU.length (layerBias params) /= outputs =
      pure (Left "layergraph-onednn: bias length does not match output width")
  | VU.length dPre /= batchN * outputs =
      pure (Left "layergraph-onednn: dPre length does not match batch/output width")
  | VU.length input /= batchN * inputs =
      pure (Left "layergraph-onednn: input length does not match batch/input width")
  | otherwise =
      withArray (toC (VU.toList input)) $ \inputPtr ->
        withArray (toC (VU.toList (layerWeights params))) $ \weightsPtr ->
          withArray (toC (VU.toList (layerBias params))) $ \biasPtr ->
            withArray (toC (VU.toList dPre)) $ \dPrePtr ->
              allocaArray (batchN * outputs) $ \prePtr ->
                allocaArray (batchN * inputs) $ \inputGradPtr ->
                  allocaArray (inputs * outputs) $ \weightGradPtr ->
                    allocaArray outputs $ \biasGradPtr -> do
                      lgForward
                        functions
                        prePtr
                        inputPtr
                        weightsPtr
                        biasPtr
                        (fromIntegral inputs)
                        (fromIntegral outputs)
                        kindCode
                        (fromIntegral batchN)
                      lgBackwardData
                        functions
                        inputGradPtr
                        dPrePtr
                        weightsPtr
                        (fromIntegral inputs)
                        (fromIntegral outputs)
                        kindCode
                        (fromIntegral batchN)
                      lgBackwardWeights
                        functions
                        weightGradPtr
                        biasGradPtr
                        dPrePtr
                        inputPtr
                        (fromIntegral inputs)
                        (fromIntegral outputs)
                        kindCode
                        (fromIntegral batchN)
                      preActivation <- VU.fromList <$> peekFloats (batchN * outputs) prePtr
                      inputGradient <- VU.fromList <$> peekFloats (batchN * inputs) inputGradPtr
                      weightGradient <- VU.fromList <$> peekFloats (inputs * outputs) weightGradPtr
                      biasGradient <- VU.fromList <$> peekFloats outputs biasGradPtr
                      pure (Right (preActivation, inputGradient, weightGradient, biasGradient))

runDeviceForwardOnly
  :: LayerGraphDeviceFunctions
  -> CInt
  -> LayerParameters
  -> Vector Double
  -> Int
  -> Int
  -> IO (Either Text (Vector Double))
runDeviceForwardOnly functions kindCode params input inputs outputs
  | VU.length (layerWeights params) /= inputs * outputs =
      pure (Left "layergraph-onednn: weight length does not match input/output width")
  | VU.length (layerBias params) /= outputs =
      pure (Left "layergraph-onednn: bias length does not match output width")
  | otherwise =
      withArray (toC (VU.toList input)) $ \inputPtr ->
        withArray (toC (VU.toList (layerWeights params))) $ \weightsPtr ->
          withArray (toC (VU.toList (layerBias params))) $ \biasPtr ->
            allocaArray outputs $ \prePtr -> do
              lgForward
                functions
                prePtr
                inputPtr
                weightsPtr
                biasPtr
                (fromIntegral inputs)
                (fromIntegral outputs)
                kindCode
                1
              Right . VU.fromList <$> peekFloats outputs prePtr

-- | Phase 241 — run a real spatial 2-D convolution's forward + backward through
-- the oneDNN device kernels, returning @(output, dInput, dWeights, dBias)@.
-- @dPre@ is the gradient w.r.t. the convolution output (length
-- @Cout*Hout*Wout@). This is the device counterpart of the pure
-- 'LayerGraph.convForward' / 'LayerGraph.convBackward' oracle it is validated
-- against (single example; NCHW/OIHW/cross-correlation/zero-padding).
runDeviceSpatialConv
  :: LayerGraphDeviceFunctions
  -> LayerGraph.ConvSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceSpatialConv functions spec params input dPre =
  case ( LayerGraph.convInputDims spec
       , LayerGraph.convKernelDims spec
       , LayerGraph.convStride spec
       , LayerGraph.convPadding spec
       ) of
    ([h, w], [kh, kw], [sh, sw], [ph, pw])
      | cin <= 0 || cout <= 0 || h <= 0 || w <= 0 ->
          pure (Left "runDeviceSpatialConv: non-positive conv geometry")
      | VU.length input /= inLen ->
          pure (Left "runDeviceSpatialConv: input length does not match Cin*H*W")
      | VU.length dPre /= outLen ->
          pure (Left "runDeviceSpatialConv: dPre length does not match Cout*Hout*Wout")
      | VU.length (layerWeights params) /= wLen ->
          pure (Left "runDeviceSpatialConv: weight length does not match Cout*Cin*Kh*Kw")
      | VU.length (layerBias params) /= cout ->
          pure (Left "runDeviceSpatialConv: bias length does not match Cout")
      | otherwise ->
          withArray (toC (VU.toList input)) $ \inputPtr ->
            withArray (toC (VU.toList (layerWeights params))) $ \weightsPtr ->
              withArray (toC (VU.toList (layerBias params))) $ \biasPtr ->
                withArray (toC (VU.toList dPre)) $ \dPrePtr ->
                  allocaArray outLen $ \outPtr ->
                    allocaArray inLen $ \dxPtr ->
                      allocaArray wLen $ \dwPtr ->
                        allocaArray cout $ \dbPtr -> do
                          let ci = fromIntegral cin
                              co = fromIntegral cout
                              args =
                                ( ci
                                , co
                                , fromIntegral h
                                , fromIntegral w
                                , fromIntegral kh
                                , fromIntegral kw
                                , fromIntegral sh
                                , fromIntegral sw
                                , fromIntegral ph
                                , fromIntegral pw
                                , 1 :: CInt
                                )
                          applyConvForward (lgConvForward functions) outPtr inputPtr weightsPtr biasPtr args
                          applyConvBackwardData (lgConvBackwardData functions) dxPtr dPrePtr weightsPtr args
                          applyConvBackwardWeights (lgConvBackwardWeights functions) dwPtr dbPtr dPrePtr inputPtr args
                          out <- VU.fromList <$> peekFloats outLen outPtr
                          dx <- VU.fromList <$> peekFloats inLen dxPtr
                          dw <- VU.fromList <$> peekFloats wLen dwPtr
                          db <- VU.fromList <$> peekFloats cout dbPtr
                          pure (Right (out, dx, dw, db))
     where
      cin = LayerGraph.convIn spec
      cout = LayerGraph.convOut spec
      oh = (h + 2 * ph - kh) `div` sh + 1
      ow = (w + 2 * pw - kw) `div` sw + 1
      inLen = cin * h * w
      outLen = cout * oh * ow
      wLen = cout * cin * kh * kw
    -- Sprint `241.1` — a real three-dimensional convolution is one more spatial
    -- axis of the same primitive, not an unsupported operator. The 2-D arm above
    -- is kept separate rather than generalised because oneDNN's memory format
    -- tags (nchw/oihw versus ncdhw/oidhw) and primitive descriptors are
    -- arity-specific.
    ([d, h, w], [kd, kh, kw], [sd, sh, sw], [pdp, ph, pw])
      | cin <= 0 || cout <= 0 || d <= 0 || h <= 0 || w <= 0 ->
          pure (Left "runDeviceSpatialConv: non-positive conv geometry")
      | VU.length input /= inLen ->
          pure (Left "runDeviceSpatialConv: input length does not match Cin*D*H*W")
      | VU.length dPre /= outLen ->
          pure (Left "runDeviceSpatialConv: dPre length does not match Cout*Dout*Hout*Wout")
      | VU.length (layerWeights params) /= wLen ->
          pure (Left "runDeviceSpatialConv: weight length does not match Cout*Cin*Kd*Kh*Kw")
      | VU.length (layerBias params) /= cout ->
          pure (Left "runDeviceSpatialConv: bias length does not match Cout")
      | otherwise ->
          withArray (toC (VU.toList input)) $ \inputPtr ->
            withArray (toC (VU.toList (layerWeights params))) $ \weightsPtr ->
              withArray (toC (VU.toList (layerBias params))) $ \biasPtr ->
                withArray (toC (VU.toList dPre)) $ \dPrePtr ->
                  allocaArray outLen $ \outPtr ->
                    allocaArray inLen $ \dxPtr ->
                      allocaArray wLen $ \dwPtr ->
                        allocaArray cout $ \dbPtr -> do
                          let ci = fromIntegral cin
                              co = fromIntegral cout
                          lgConv3DForward
                            functions
                            outPtr
                            inputPtr
                            weightsPtr
                            biasPtr
                            ci
                            co
                            (fromIntegral d)
                            (fromIntegral h)
                            (fromIntegral w)
                            (fromIntegral kd)
                            (fromIntegral kh)
                            (fromIntegral kw)
                            (fromIntegral sd)
                            (fromIntegral sh)
                            (fromIntegral sw)
                            (fromIntegral pdp)
                            (fromIntegral ph)
                            (fromIntegral pw)
                            1
                          lgConv3DBackwardData
                            functions
                            dxPtr
                            dPrePtr
                            weightsPtr
                            ci
                            co
                            (fromIntegral d)
                            (fromIntegral h)
                            (fromIntegral w)
                            (fromIntegral kd)
                            (fromIntegral kh)
                            (fromIntegral kw)
                            (fromIntegral sd)
                            (fromIntegral sh)
                            (fromIntegral sw)
                            (fromIntegral pdp)
                            (fromIntegral ph)
                            (fromIntegral pw)
                            1
                          lgConv3DBackwardWeights
                            functions
                            dwPtr
                            dbPtr
                            dPrePtr
                            inputPtr
                            ci
                            co
                            (fromIntegral d)
                            (fromIntegral h)
                            (fromIntegral w)
                            (fromIntegral kd)
                            (fromIntegral kh)
                            (fromIntegral kw)
                            (fromIntegral sd)
                            (fromIntegral sh)
                            (fromIntegral sw)
                            (fromIntegral pdp)
                            (fromIntegral ph)
                            (fromIntegral pw)
                            1
                          out <- VU.fromList <$> peekFloats outLen outPtr
                          dx <- VU.fromList <$> peekFloats inLen dxPtr
                          dw <- VU.fromList <$> peekFloats wLen dwPtr
                          db <- VU.fromList <$> peekFloats cout dbPtr
                          pure (Right (out, dx, dw, db))
     where
      cin = LayerGraph.convIn spec
      cout = LayerGraph.convOut spec
      od = (d + 2 * pdp - kd) `div` sd + 1
      oh = (h + 2 * ph - kh) `div` sh + 1
      ow = (w + 2 * pw - kw) `div` sw + 1
      inLen = cin * d * h * w
      outLen = cout * od * oh * ow
      wLen = cout * cin * kd * kh * kw
    _ ->
      pure
        ( Left
            "runDeviceSpatialConv: conv geometry is neither 2-D nor 3-D on every axis"
        )

type ConvArgs = (CInt, CInt, CInt, CInt, CInt, CInt, CInt, CInt, CInt, CInt, CInt)

applyConvForward
  :: ConvForwardFun -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> ConvArgs -> IO ()
applyConvForward f o i wgt b (ci, co, h, w, kh, kw, sh, sw, ph, pw, n) =
  f o i wgt b ci co h w kh kw sh sw ph pw n

applyConvBackwardData
  :: ConvBackwardDataFun -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> ConvArgs -> IO ()
applyConvBackwardData f dx dpre wgt (ci, co, h, w, kh, kw, sh, sw, ph, pw, n) =
  f dx dpre wgt ci co h w kh kw sh sw ph pw n

applyConvBackwardWeights
  :: ConvBackwardWeightsFun -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> ConvArgs -> IO ()
applyConvBackwardWeights f gw gb dpre i (ci, co, h, w, kh, kw, sh, sw, ph, pw, n) =
  f gw gb dpre i ci co h w kh kw sh sw ph pw n

-- ---------------------------------------------------------------------------
-- Phase 241 — correct-operator device dispatch helpers
-- ---------------------------------------------------------------------------

-- | Per-node upstream output gradients recovered from the pure per-layer
-- gradients plus the loss seed: the upstream of node @i@ is the input gradient
-- of node @i+1@, and the last node's upstream is the loss seed.
perNodeUpstreams :: Vector Double -> [LayerGradient] -> [Vector Double]
perNodeUpstreams seed grads =
  case grads of
    [] -> []
    (_ : rest) -> fmap layerGradientInput rest ++ [seed]

-- | The closed device primitive set every 'LayerGraph.LayerOp' lowers to.
--
-- Sprint `241.1`. Before this the dispatch was a chain of guards ending in a
-- wildcard that reported \"operator not supported on device\": three of the
-- eleven declared operators had no lowering at all, and the graph they appeared
-- in either failed closed (3-D convolution) or ran its backward on the host
-- executor that is supposed to be the /oracle/ (pooling, dropout, identity).
-- A lowering that is total over 'LayerGraph.LayerOp' cannot do either: adding a
-- twelfth operator makes 'lowerLayerOp' a compile error under
-- @-Werror=incomplete-patterns@ rather than a silent host fallback.
data LoweredOp
  = -- | Flat affine layer through @jitml_layer_forward@ / @_backward_*@.
    LowerDenseAffine
  | -- | Real spatial convolution through the @jitml_conv{2,3}d_spatial_*@
    -- triple, selected by the arity of the verified geometry.
    LowerSpatialConv !LayerGraph.ConvSpec
  | -- | Composed block, executed as its device sub-kernels.
    LowerBlockComposition
  | -- | One @jitml_op_train@ opcode with its packed geometry.
    LowerOpTrain !DeviceOpPlan
  deriving stock (Eq, Show)

-- | Lower one node's operator to the device primitive that executes it.
--
-- Total over 'LayerGraph.LayerOp' by construction — there is no wildcard arm.
-- 'LayerGraph.IdentityOp' and 'LayerGraph.DropoutOp' lower to the same scale
-- kernel (identity is the unit scale), so \"no parameters\" does not mean \"not
-- executed\": the substrate still runs the operator and the pure executor stays
-- the oracle it is compared against.
lowerLayerOp :: LayerNode -> Either Text LoweredOp
lowerLayerOp node =
  case LayerGraph.layerNodeOp node of
    LayerGraph.DenseOp -> Right LowerDenseAffine
    LayerGraph.ConvOp spec -> Right (LowerSpatialConv spec)
    LayerGraph.BlockOp _ -> Right LowerBlockComposition
    LayerGraph.IdentityOp -> LowerOpTrain . scaleOpPlan 1.0 <$> inputWidth
    LayerGraph.DropoutOp rate ->
      LowerOpTrain . scaleOpPlan (LayerGraph.dropoutScale (layerMode node) rate) <$> inputWidth
    LayerGraph.PoolOp shape poolSpec -> LowerOpTrain <$> poolOpPlan shape poolSpec
    LayerGraph.NormOp spec -> LowerOpTrain . normOpPlan spec <$> inputWidth
    LayerGraph.GeGLUOp spec -> Right (LowerOpTrain (gegluOpPlan spec))
    LayerGraph.AttentionOp spec -> Right (LowerOpTrain (attentionOpPlan spec))
    LayerGraph.PatchOp spec -> Right (LowerOpTrain (patchOpPlan spec))
    LayerGraph.ResidualOp inner shortcut scale innerAct ->
      LowerOpTrain <$> residualOpPlan inner shortcut scale innerAct (layerActivation node)
 where
  -- An unreadable declared width is a lowering failure, not a zero-width
  -- kernel launch: a zero here would dispatch an operator over no elements and
  -- report it as a successful device execution.
  inputWidth = LayerGraph.tensorShapeWidth (LayerGraph.layerInputShape node)

-- | The operator has 2-D spatial geometry (as opposed to 3-D). Both arities
-- have a real device kernel; this only selects which one.
is2DConv :: LayerGraph.ConvSpec -> Bool
is2DConv spec = length (LayerGraph.convInputDims spec) == 2

-- | Evidence kind code for a spatial convolution — the same @JITML_LAYER_CONV*@
-- codes the generated primitive-name reporter answers for, so the recorded
-- primitive names the arity that actually ran.
spatialConvEvidenceCode :: LayerGraph.ConvSpec -> CInt
spatialConvEvidenceCode spec = if is2DConv spec then 1 else 2

-- | Evidence kind code for a composed block: it is built from the residual and
-- dense sub-kernels, and reports as the residual family.
blockEvidenceCode :: CInt
blockEvidenceCode = 7

-- | Host mirror of 'LayerGraph.activationBackward' (used to differentiate the
-- convolution node activation before the spatial-conv device backward).
activationBackwardLocal :: LayerActivation -> Vector Double -> Vector Double -> Vector Double
activationBackwardLocal LinearActivation _ up = up
activationBackwardLocal TanhActivation activated up =
  VU.zipWith (\a u -> (1.0 - a * a) * u) activated up
activationBackwardLocal ReluActivation activated up =
  VU.zipWith (\a u -> if a > 0.0 then u else 0.0) activated up
activationBackwardLocal SoftmaxActivation activated up =
  let d = VU.sum (VU.zipWith (*) activated up)
   in VU.zipWith (\a u -> a * (u - d)) activated up

-- | Integer activation code shared with the generated 'jitml_op_train' kernel
-- (0 linear, 1 tanh, 2 relu). Softmax activation is not supported inside a
-- device residual composition.
activationCode :: LayerActivation -> Either Text Int
activationCode LinearActivation = Right 0
activationCode TanhActivation = Right 1
activationCode ReluActivation = Right 2
activationCode SoftmaxActivation =
  Left "layergraph-onednn: softmax activation unsupported in device residual"

-- | One 'jitml_op_train' invocation: the opcode, its packed integer geometry
-- and float parameters, the output width it writes, and the evidence code the
-- artifact's primitive-name reporter answers for.
data DeviceOpPlan = DeviceOpPlan
  { dopCode :: !CInt
  , dopGeom :: ![Int]
  , dopFparams :: ![Double]
  , dopOutLen :: !Int
  , dopEvidenceCode :: !CInt
  }
  deriving stock (Eq, Show)

normOpPlan :: LayerGraph.NormSpec -> Int -> DeviceOpPlan
normOpPlan spec inputLen =
  DeviceOpPlan
    { dopCode = 11
    , dopGeom = [flavorCode, LayerGraph.nChannels spec, LayerGraph.nSpatial spec, groups]
    , dopFparams = [LayerGraph.nEps spec]
    , dopOutLen = inputLen
    , dopEvidenceCode = 3
    }
 where
  (flavorCode, groups) =
    case LayerGraph.nFlavor spec of
      LayerGraph.NormBatch -> (0, 1)
      LayerGraph.NormLayerWise -> (1, 1)
      LayerGraph.NormGroup g -> (2, g)

gegluOpPlan :: LayerGraph.GeGLUSpec -> DeviceOpPlan
gegluOpPlan spec =
  DeviceOpPlan
    { dopCode = 10
    , dopGeom = [LayerGraph.ggIn spec, LayerGraph.ggFf spec, LayerGraph.ggOut spec]
    , dopFparams = []
    , dopOutLen = LayerGraph.ggOut spec
    , dopEvidenceCode = 4
    }

attentionOpPlan :: LayerGraph.AttentionSpec -> DeviceOpPlan
attentionOpPlan spec =
  DeviceOpPlan
    { dopCode = 13
    , dopGeom =
        [ LayerGraph.attnSeqLen spec
        , LayerGraph.attnEmbedDim spec
        , LayerGraph.attnNumHeads spec
        , if LayerGraph.attnCausal spec then 1 else 0
        ]
    , dopFparams = []
    , dopOutLen = LayerGraph.attnSeqLen spec * LayerGraph.attnEmbedDim spec
    , dopEvidenceCode = 5
    }

patchOpPlan :: LayerGraph.PatchSpec -> DeviceOpPlan
patchOpPlan spec =
  DeviceOpPlan
    { dopCode = 12
    , dopGeom =
        [ LayerGraph.peC spec
        , LayerGraph.peH spec
        , LayerGraph.peW spec
        , LayerGraph.peP spec
        , LayerGraph.peStride spec
        , LayerGraph.peD spec
        ]
    , dopFparams = []
    , dopOutLen = nY * nX * LayerGraph.peD spec
    , dopEvidenceCode = 6
    }
 where
  nY = (LayerGraph.peH spec - LayerGraph.peP spec) `div` LayerGraph.peStride spec + 1
  nX = (LayerGraph.peW spec - LayerGraph.peP spec) `div` LayerGraph.peStride spec + 1

residualOpPlan
  :: LayerGraph.AffineSpec
  -> LayerGraph.Shortcut
  -> Double
  -> LayerActivation
  -> LayerActivation
  -> Either Text DeviceOpPlan
residualOpPlan inner shortcut scale innerAct nodeAct = do
  innerCode <- activationCode innerAct
  finalCode <- activationCode nodeAct
  let hasProj =
        case shortcut of
          LayerGraph.ProjectionShortcut _ -> 1
          LayerGraph.IdentityShortcut -> 0
  Right
    DeviceOpPlan
      { dopCode = 14
      , dopGeom = [LayerGraph.asIn inner, LayerGraph.asOut inner, hasProj, innerCode, finalCode]
      , dopFparams = [scale]
      , dopOutLen = LayerGraph.asOut inner
      , dopEvidenceCode = 7
      }

-- | Pooling has no trainable parameters, but it is not free: the backward pass
-- routes each output gradient back to the input cells the forward pass read.
-- The device runs both halves through the oneDNN pooling primitive whose
-- algorithm is the pure 'LayerGraph.PoolSpec' — max, average-excluding-padding,
-- or average-including-padding — and global average pooling is the
-- exclude-padding case over the full spatial extent.
poolOpPlan :: LayerGraph.SpatialShape -> LayerGraph.PoolSpec -> Either Text DeviceOpPlan
poolOpPlan shape poolSpec =
  case poolSpec of
    LayerGraph.PoolMax win -> Right (windowed 0 win)
    LayerGraph.PoolAvg win
      | LayerGraph.pwCountPad win -> Right (windowed 2 win)
      | otherwise -> Right (windowed 1 win)
    LayerGraph.PoolGlobal ->
      Right
        DeviceOpPlan
          { dopCode = 15
          , dopGeom = [1, channels, height, width, height, width, 1, 1, 0, 0]
          , dopFparams = []
          , dopOutLen = channels
          , dopEvidenceCode = 8
          }
 where
  channels = LayerGraph.spC shape
  height = LayerGraph.spH shape
  width = LayerGraph.spW shape
  windowed algo win =
    DeviceOpPlan
      { dopCode = 15
      , dopGeom =
          [ algo
          , channels
          , height
          , width
          , LayerGraph.pwKh win
          , LayerGraph.pwKw win
          , LayerGraph.pwSh win
          , LayerGraph.pwSw win
          , LayerGraph.pwPh win
          , LayerGraph.pwPw win
          ]
      , dopFparams = []
      , dopOutLen =
          channels
            * LayerGraph.convOutDim height (LayerGraph.pwKh win) (LayerGraph.pwSh win) (LayerGraph.pwPh win)
            * LayerGraph.convOutDim width (LayerGraph.pwKw win) (LayerGraph.pwSw win) (LayerGraph.pwPw win)
      , dopEvidenceCode = 8
      }

-- | @out = scale * x@, @dx = scale * dy@ — the whole of the identity operator
-- (unit scale) and of dropout's deterministic keep-probability scaling.
scaleOpPlan :: Double -> Int -> DeviceOpPlan
scaleOpPlan scale width =
  DeviceOpPlan
    { dopCode = 16
    , dopGeom = []
    , dopFparams = [scale]
    , dopOutLen = width
    , dopEvidenceCode = 9
    }

-- | Run a correct operator's forward + backward on the oneDNN device via the
-- unified 'jitml_op_train' kernel, returning @(out, dInput, dWeights, dBias)@
-- with dWeights/dBias in the operator's packed segment order. This is the device
-- counterpart of the pure per-op oracle (@gegluBackward@ / @normBackward@ /
-- @attentionBackward@ / @patchBackward@ / @residualBackward@) it is validated
-- against within float32 tolerance. @upstream@ is the gradient w.r.t. the node
-- output (single example).
runDeviceOp
  :: LayerGraphDeviceFunctions
  -> LayerNode
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceOp functions node input upstream =
  case lowerLayerOp node of
    Left err -> pure (Left err)
    Right (LowerOpTrain plan) ->
      case (,) <$> weights <*> bias of
        Left err -> pure (Left err)
        Right (weightValues, biasValues) ->
          runDeviceOpPlan functions plan input upstream weightValues biasValues
    Right _ ->
      pure
        ( Left
            ( "runDeviceOp: "
                <> LayerGraph.layerKindName (layerNodeKind node)
                <> " does not lower to a jitml_op_train opcode"
            )
        )
 where
  wLen = sum (LayerGraph.opWeightSegments (LayerGraph.layerNodeOp node))
  bLen = sum (LayerGraph.opBiasSegments (LayerGraph.layerNodeOp node))
  -- A parameterless operator (pooling, dropout, identity) legitimately has no
  -- LayerParameters; it still executes, with empty weight and bias segments.
  parameterVectors =
    case layerParameters node of
      Nothing -> (VU.empty, VU.empty)
      Just params -> (layerWeights params, layerBias params)
  weights
    | VU.length (fst parameterVectors) == wLen = Right (fst parameterVectors)
    | otherwise = Left "runDeviceOp: weight length does not match operator segment layout"
  bias
    | VU.length (snd parameterVectors) == bLen = Right (snd parameterVectors)
    | otherwise = Left "runDeviceOp: bias length does not match operator segment layout"

-- | Marshal one 'DeviceOpPlan' across the FFI and read back
-- @(out, dInput, dWeights, dBias)@.
--
-- The kernel's return value is the executed-opcode status, and a non-zero
-- status becomes a typed error naming the opcode rather than four buffers the
-- artifact never wrote.
runDeviceOpPlan
  :: LayerGraphDeviceFunctions
  -> DeviceOpPlan
  -> Vector Double
  -> Vector Double
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceOpPlan functions plan input upstream weightValues biasValues
  | VU.length upstream /= outLen =
      pure (Left "runDeviceOp: upstream length does not match operator output width")
  | otherwise =
      withArray (fmap fromIntegral (dopGeom plan) :: [CInt]) $ \geomPtr ->
        withArray (toC (dopFparams plan)) $ \fPtr ->
          withArray (toC (VU.toList input)) $ \xPtr ->
            withArray (toC (VU.toList weightValues)) $ \wPtr ->
              withArray (toC (VU.toList biasValues)) $ \bPtr ->
                withArray (toC (VU.toList upstream)) $ \dyPtr ->
                  allocaArray (max 1 outLen) $ \outPtr ->
                    allocaArray (max 1 inLen) $ \dxPtr ->
                      allocaArray (max 1 wLen) $ \dwPtr ->
                        allocaArray (max 1 bLen) $ \dbPtr -> do
                          status <-
                            lgOpTrain
                              functions
                              (dopCode plan)
                              geomPtr
                              (fromIntegral (length (dopGeom plan)))
                              fPtr
                              (fromIntegral (length (dopFparams plan)))
                              outPtr
                              dxPtr
                              dwPtr
                              dbPtr
                              xPtr
                              wPtr
                              bPtr
                              dyPtr
                              (fromIntegral inLen)
                              (fromIntegral outLen)
                              (fromIntegral wLen)
                              (fromIntegral bLen)
                          if status /= 0
                            then
                              pure
                                ( Left
                                    ( "layergraph-onednn: compiled artifact executed no operator for"
                                        <> " jitml_op_train opcode "
                                        <> Text.pack (show (dopCode plan))
                                    )
                                )
                            else do
                              out <- VU.fromList <$> peekFloats outLen outPtr
                              dx <- VU.fromList <$> peekFloats inLen dxPtr
                              dw <- VU.fromList <$> peekFloats wLen dwPtr
                              dbv <- VU.fromList <$> peekFloats bLen dbPtr
                              pure (Right (out, dx, dw, dbv))
 where
  inLen = VU.length input
  outLen = dopOutLen plan
  wLen = VU.length weightValues
  bLen = VU.length biasValues

-- | Phase 241/242 — @BasicBlock@ / @Bottleneck@ device backward composed from the
-- existing device sub-kernels: the dense-affine forward/backward
-- ('runDeviceForwardOnly' / 'runDeviceLayer', kind code 0) and the norm
-- 'jitml_op_train' opcode-11 kernel (via 'runDeviceOp' on a synthetic norm node).
-- Returns @(out, dInput, dWeights, dBias)@ with dWeights/dBias in the block's
-- packed 'LayerGraph.opWeightSegments' / 'opBiasSegments' order, matching the pure
-- 'LayerGraph.blockBackward' oracle within float32 tolerance. Every matmul and
-- normalization runs on the device; only the elementwise glue (activation
-- derivative, residual scale, and the skip/branch add) runs on the host — the same
-- split the spatial-conv node already uses. There is no single-plan
-- 'jitml_op_train' opcode for a block: it is a composition, so 'deviceOpPlan'
-- deliberately stays "unsupported" for @BlockOp@ and this path is taken instead.
runDeviceBlock
  :: LayerGraphDeviceFunctions
  -> LayerNode
  -> Vector Double
  -- ^ block input @x@
  -> Vector Double
  -- ^ upstream: gradient of the loss w.r.t. the block output @y@
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceBlock functions node input upstream =
  case (LayerGraph.layerNodeOp node, layerParameters node) of
    (LayerGraph.BlockOp spec, Just params) ->
      case blockDeviceParts spec params of
        Left err -> pure (Left err)
        Right (stageParts, shortcutPart) ->
          runBlockDevice
            functions
            (layerActivation node)
            (LayerGraph.blScale spec)
            stageParts
            shortcutPart
            input
            upstream
    (LayerGraph.BlockOp _, Nothing) ->
      pure (Left (layerNodeName node <> ": block requires parameters"))
    _ -> pure (Left "runDeviceBlock: node operator is not a BlockOp")

-- | One block stage's device-ready parameter split: the dense-affine weights/bias
-- and dimensions, an optional (norm spec, gamma/beta) pair, and the stage
-- activation.
data DeviceStagePart = DeviceStagePart
  { dspAffine :: !LayerParameters
  , dspAffIn :: !Int
  , dspAffOut :: !Int
  , dspNorm :: !(Maybe (LayerGraph.NormSpec, LayerParameters))
  , dspAct :: !LayerActivation
  }

-- | Per-stage forward tape kept for the backward pass: the stage input @x_i@, the
-- affine pre-activation @z_i@ (norm input), and the activated stage output.
data DeviceStageTape = DeviceStageTape
  { dstInput :: !(Vector Double)
  , dstAffineOut :: !(Vector Double)
  , dstOutput :: !(Vector Double)
  }

-- | 'Nothing' is an identity shortcut; @'Just' (inWidth, outWidth, projection)@ is
-- a projection shortcut with its own dense affine parameters.
type DeviceShortcut = Maybe (Int, Int, LayerParameters)

-- | Split a block node's packed weights/bias into per-stage device parts plus the
-- shortcut part, in the exact 'LayerGraph.opWeightSegments' /
-- 'LayerGraph.opBiasSegments' (@BlockOp spec@) order.
blockDeviceParts
  :: LayerGraph.BlockSpec
  -> LayerParameters
  -> Either Text ([DeviceStagePart], DeviceShortcut)
blockDeviceParts spec params = do
  let stages = LayerGraph.blStages spec
      shortcut = LayerGraph.blShortcut spec
      wLens = concatMap stageWeightLens stages <> shortcutWeightLens shortcut
      bLens = concatMap stageBiasLens stages <> shortcutBiasLens shortcut
      wSegs = splitDeviceSegs wLens (layerWeights params)
      bSegs = splitDeviceSegs bLens (layerBias params)
  (parts, wRest, bRest) <- consumeStages stages wSegs bSegs
  shortcutPart <- buildDeviceShortcut shortcut wRest bRest
  pure (parts, shortcutPart)
 where
  stageWeightLens st =
    (LayerGraph.asOut (LayerGraph.bsAffine st) * LayerGraph.asIn (LayerGraph.bsAffine st))
      : maybe [] (\n -> [LayerGraph.nChannels n]) (LayerGraph.bsNorm st)
  stageBiasLens st =
    LayerGraph.asOut (LayerGraph.bsAffine st)
      : maybe [] (\n -> [LayerGraph.nChannels n]) (LayerGraph.bsNorm st)
  shortcutWeightLens sc =
    case sc of
      LayerGraph.IdentityShortcut -> []
      LayerGraph.ProjectionShortcut a -> [LayerGraph.asOut a * LayerGraph.asIn a]
  shortcutBiasLens sc =
    case sc of
      LayerGraph.IdentityShortcut -> []
      LayerGraph.ProjectionShortcut a -> [LayerGraph.asOut a]
  consumeStages [] wSegs bSegs = Right ([], wSegs, bSegs)
  consumeStages (st : sts) wSegs bSegs =
    case (wSegs, bSegs) of
      (wAff : wRest0, bAff : bRest0) -> do
        let affParams = LayerParameters wAff bAff
            aff = LayerGraph.bsAffine st
        (normInfo, wRest1, bRest1) <-
          case LayerGraph.bsNorm st of
            Nothing -> Right (Nothing, wRest0, bRest0)
            Just nspec ->
              case (wRest0, bRest0) of
                (wGamma : wR, bBeta : bR) ->
                  Right (Just (nspec, LayerParameters wGamma bBeta), wR, bR)
                _ -> Left "runDeviceBlock: missing block-stage norm parameters"
        (rest, wFinal, bFinal) <- consumeStages sts wRest1 bRest1
        Right
          ( DeviceStagePart
              affParams
              (LayerGraph.asIn aff)
              (LayerGraph.asOut aff)
              normInfo
              (LayerGraph.bsAct st)
              : rest
          , wFinal
          , bFinal
          )
      _ -> Left "runDeviceBlock: missing block-stage affine parameters"
  buildDeviceShortcut LayerGraph.IdentityShortcut _ _ = Right Nothing
  buildDeviceShortcut (LayerGraph.ProjectionShortcut a) wSegs bSegs =
    case (wSegs, bSegs) of
      (w : _, b : _) -> Right (Just (LayerGraph.asIn a, LayerGraph.asOut a, LayerParameters w b))
      _ -> Left "runDeviceBlock: missing projection-shortcut parameters"

splitDeviceSegs :: [Int] -> Vector Double -> [Vector Double]
splitDeviceSegs lens v = go 0 lens
 where
  go _ [] = []
  go off (n : rest) = VU.slice off n v : go (off + n) rest

-- | Forward through the block on device, then backward in reverse, matching the
-- pure 'LayerGraph.blockForward' / 'blockBackward' composition exactly.
runBlockDevice
  :: LayerGraphDeviceFunctions
  -> LayerActivation
  -> Double
  -> [DeviceStagePart]
  -> DeviceShortcut
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runBlockDevice functions finalAct scale stageParts shortcutPart input upstream =
  bindE (forwardStages stageParts input) $ \(tapes, u) ->
    bindE (shortcutForward shortcutPart input) $ \sx ->
      if VU.length sx /= VU.length u
        then pure (Left "runDeviceBlock: shortcut/branch width mismatch")
        else do
          let ypre = VU.zipWith (\p q -> p + scale * q) sx u
              y = applyActivation finalAct ypre
              d = activationBackwardLocal finalAct y upstream
              du = VU.map (* scale) d
          bindE (backwardStages stageParts tapes du) $ \(dxBranch, stageWGrads, stageBGrads) ->
            bindE (shortcutBackward shortcutPart input d) $ \(dxShort, shortWGrads, shortBGrads) ->
              let dInput = VU.zipWith (+) dxBranch dxShort
                  dWeights = VU.concat (stageWGrads <> shortWGrads)
                  dBias = VU.concat (stageBGrads <> shortBGrads)
               in pure (Right (y, dInput, dWeights, dBias))
 where
  forwardStages parts x0 = go parts x0 []
   where
    go [] x acc = pure (Right (reverse acc, x))
    go (p : ps) x acc =
      bindE (deviceAffineForward functions (dspAffine p) x (dspAffIn p) (dspAffOut p)) $ \z ->
        case dspNorm p of
          Nothing ->
            let out = applyActivation (dspAct p) z
             in go ps out (DeviceStageTape x z out : acc)
          Just (nspec, nparams) ->
            bindE (deviceNormForward functions nspec nparams z) $ \zn ->
              let out = applyActivation (dspAct p) zn
               in go ps out (DeviceStageTape x z out : acc)
  -- Reverse-thread the incoming gradient (last stage first); prepend each stage's
  -- gradients so the accumulators end in forward (packed-segment) order.
  backwardStages parts tapes du = goRev (reverse (zip parts tapes)) du [] []
   where
    goRev [] dIn wAcc bAcc = pure (Right (dIn, wAcc, bAcc))
    goRev ((p, tape) : rest) dIn wAcc bAcc =
      bindE (stageBackward p tape dIn) $ \(dPrev, wGrad, bGrad) ->
        goRev rest dPrev (wGrad : wAcc) (bGrad : bAcc)
  stageBackward p tape dIn =
    let dActPre = activationBackwardLocal (dspAct p) (dstOutput tape) dIn
     in case dspNorm p of
          Nothing ->
            bindE
              (deviceAffineBackward functions (dspAffine p) (dstInput tape) dActPre (dspAffIn p) (dspAffOut p))
              (\(dx, dW, dB) -> pure (Right (dx, dW, dB)))
          Just (nspec, nparams) ->
            bindE (deviceNormBackward functions nspec nparams (dstAffineOut tape) dActPre) $ \(dz, dGamma, dBeta) ->
              bindE
                (deviceAffineBackward functions (dspAffine p) (dstInput tape) dz (dspAffIn p) (dspAffOut p))
                (\(dx, dW, dB) -> pure (Right (dx, VU.concat [dW, dGamma], VU.concat [dB, dBeta])))
  shortcutForward Nothing x = pure (Right x)
  shortcutForward (Just (sIn, sOut, projParams)) x =
    deviceAffineForward functions projParams x sIn sOut
  shortcutBackward Nothing _ d = pure (Right (d, [], []))
  shortcutBackward (Just (sIn, sOut, projParams)) x d =
    bindE
      (deviceAffineBackward functions projParams x d sIn sOut)
      (\(dx, dW, dB) -> pure (Right (dx, [dW], [dB])))

-- | Short-circuiting bind for the @IO (Either Text a)@ device-call pipeline.
bindE :: IO (Either Text a) -> (a -> IO (Either Text b)) -> IO (Either Text b)
bindE m f = m >>= either (pure . Left) f

-- | Device linear affine forward @z = W x + b@ (kind code 0).
deviceAffineForward
  :: LayerGraphDeviceFunctions
  -> LayerParameters
  -> Vector Double
  -> Int
  -> Int
  -> IO (Either Text (Vector Double))
deviceAffineForward functions =
  runDeviceForwardOnly functions 0

-- | Device linear affine backward given the pre-activation gradient @dPre@:
-- @(dInput = Wᵀ dPre, dW = dPre ⊗ x, dB = dPre)@ (single example).
deviceAffineBackward
  :: LayerGraphDeviceFunctions
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> Int
  -> Int
  -> IO (Either Text (Vector Double, Vector Double, Vector Double))
deviceAffineBackward functions params x dPre inW outW = do
  result <- runDeviceLayer functions 0 params x dPre inW outW 1
  pure (fmap (\(_pre, dx, dW, dB) -> (dx, dW, dB)) result)

-- | Device norm forward (@out = norm(z)@) via the opcode-11 kernel with a zero
-- upstream; the backward outputs are ignored on the forward pass.
deviceNormForward
  :: LayerGraphDeviceFunctions
  -> LayerGraph.NormSpec
  -> LayerParameters
  -> Vector Double
  -> IO (Either Text (Vector Double))
deviceNormForward functions nspec nparams z =
  case LayerGraph.mkNormLayer "block-stage-norm" nspec TrainingMode nparams of
    Left err -> pure (Left err)
    Right normNode -> do
      result <- runDeviceOp functions normNode z (VU.replicate (VU.length z) 0.0)
      pure (fmap (\(out, _, _, _) -> out) result)

-- | Device norm backward via the opcode-11 kernel: @(dInput, dGamma, dBeta)@.
deviceNormBackward
  :: LayerGraphDeviceFunctions
  -> LayerGraph.NormSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double, Vector Double, Vector Double))
deviceNormBackward functions nspec nparams z dy =
  case LayerGraph.mkNormLayer "block-stage-norm" nspec TrainingMode nparams of
    Left err -> pure (Left err)
    Right normNode -> do
      result <- runDeviceOp functions normNode z dy
      pure (fmap (\(_out, dz, dGamma, dBeta) -> (dz, dGamma, dBeta)) result)

mkEvidence
  :: LayerGraphDeviceFunctions
  -> Text
  -> Text
  -> Bool
  -> LayerNode
  -> CInt
  -> IO LayerGraphDeviceEvidence
mkEvidence functions backendName artifactPath artifactCompiled node kindCode = do
  forwardPrimitive <- primitiveNameText (lgForwardPrimitive functions) kindCode
  backwardDataPrimitive <- primitiveNameText (lgBackwardDataPrimitive functions) kindCode
  backwardWeightsPrimitive <- primitiveNameText (lgBackwardWeightsPrimitive functions) kindCode
  pure
    LayerGraphDeviceEvidence
      { layerEvidenceName = layerNodeName node
      , layerEvidenceKind = LayerGraph.layerKindName (layerNodeKind node)
      , layerEvidenceBackend = backendName
      , layerEvidenceForwardPrimitive = forwardPrimitive
      , layerEvidenceBackwardDataPrimitive = backwardDataPrimitive
      , layerEvidenceBackwardWeightsPrimitive = backwardWeightsPrimitive
      , layerEvidenceArtifactPath = artifactPath
      , layerEvidenceArtifactCompiled = artifactCompiled
      }

primitiveNameText :: PrimitiveNameFun -> CInt -> IO Text
primitiveNameText nameFun kindCode =
  cStringText =<< nameFun kindCode

cStringText :: CString -> IO Text
cStringText =
  fmap Text.pack . peekCString

peekFloats :: Int -> Ptr CFloat -> IO [Double]
peekFloats n ptr =
  fmap (\(CFloat value) -> realToFrac value) <$> peekArray n ptr

toC :: [Double] -> [CFloat]
toC =
  fmap (CFloat . realToFrac)

layerKindCode :: LayerKind -> CInt
layerKindCode Conv2DLayer = 1
layerKindCode Conv3DLayer = 2
layerKindCode _ = 0

isResidualKind :: LayerKind -> Bool
isResidualKind (ResidualLayer _) = True
isResidualKind (BasicBlockLayer _) = True
isResidualKind (BottleneckBlockLayer _) = True
isResidualKind _ = False

applyActivation :: LayerActivation -> Vector Double -> Vector Double
applyActivation LinearActivation = id
applyActivation TanhActivation = VU.map tanh
applyActivation ReluActivation = VU.map (max 0.0)
applyActivation SoftmaxActivation = softmax

parameterlessForward :: LayerNode -> Vector Double -> Int -> Vector Double
parameterlessForward node input outputWidth =
  case layerNodeKind node of
    DropoutLayer rate ->
      let scale =
            case layerMode node of
              TrainingMode -> 1.0 - clampDouble 0.0 0.95 rate
              InferenceMode -> 1.0
       in VU.map (* scale) input
    PoolLayer GlobalAvgPool ->
      VU.replicate outputWidth (meanVector input)
    PoolLayer AvgPool ->
      resizeByAveraging input outputWidth
    PoolLayer MaxPool ->
      VU.replicate outputWidth (if VU.null input then 0.0 else VU.maximum input)
    _ -> resizeIdentity input outputWidth

residualScale :: LayerKind -> Maybe Double
residualScale (ResidualLayer scale) = Just scale
residualScale (BasicBlockLayer scale) = Just scale
residualScale (BottleneckBlockLayer scale) = Just scale
residualScale _ = Nothing

softmax :: Vector Double -> Vector Double
softmax values
  | VU.null values = VU.empty
  | otherwise =
      let m = VU.maximum values
          exps = VU.map (exp . subtract m) values
          total = VU.sum exps
       in if total == 0.0
            then VU.replicate (VU.length values) (1.0 / fromIntegral (VU.length values))
            else VU.map (/ total) exps

-- | Semantic-prefix softmax cross-entropy loss seed, mirroring
-- 'LayerGraph.layerGraphClassifierCrossEntropyGradient': softmax over the first
-- @classes@ logits minus the one-hot label, with the trailing slack logit(s)
-- receiving a zero upstream gradient.
classifierSeed :: Int -> Vector Double -> Int -> Vector Double
classifierSeed classes logits label =
  let probs = softmax (VU.take classes logits)
      dPrefix = VU.imap (\i p -> p - if i == label then 1.0 else 0.0) probs
      width = VU.length logits
   in dPrefix VU.++ VU.replicate (width - classes) 0.0

resizeIdentity :: Vector Double -> Int -> Vector Double
resizeIdentity input outputWidth
  | outputWidth <= 0 = VU.empty
  | VU.length input == outputWidth = input
  | VU.null input = VU.replicate outputWidth 0.0
  | otherwise = VU.generate outputWidth (\idx -> input VU.! (idx `mod` VU.length input))

resizeByAveraging :: Vector Double -> Int -> Vector Double
resizeByAveraging input outputWidth
  | outputWidth <= 0 = VU.empty
  | VU.null input = VU.replicate outputWidth 0.0
  | VU.length input == outputWidth = input
  | otherwise =
      VU.generate outputWidth $ \idx ->
        let bucket = [input VU.! j | j <- [idx, idx + outputWidth .. VU.length input - 1]]
         in sum bucket / fromIntegral (max 1 (length bucket))

meanVector :: Vector Double -> Double
meanVector values
  | VU.null values = 0.0
  | otherwise = VU.sum values / fromIntegral (VU.length values)

clampDouble :: Double -> Double -> Double -> Double
clampDouble lo hi = min hi . max lo

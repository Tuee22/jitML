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
module JitML.Numerics.LayerGraphOneDnn
  ( LayerGraphOneDnnEvidence (..)
  , LayerGraphOneDnnForwardRun (..)
  , LayerGraphOneDnnRun (..)
  , layerGraphOneDnnHash
  , layerGraphOneDnnRuntimeSource
  , layerGraphOneDnnToolchainFingerprint
  , runLayerGraphForwardOneDnn
  , layerGraphSquaredErrorGradientOneDnn
  , layerGraphCrossEntropyGradientOneDnn
  , layerGraphSquaredErrorGradientBatchOneDnn
  , layerGraphCrossEntropyGradientBatchOneDnn
  , trainLayerGraphClassifierOneDnn
  , trainLayerGraphClassifierEpochOneDnn
  , classifierBatchGradientOneDnn
  , withCompiledLayerGraphOneDnn
  , runDeviceSpatialConv
  , runDeviceOp
  , runDeviceBlock
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
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.OneDnn (renderOneDnnLayerTrainingSource)
import JitML.Codegen.RuntimeSource (RuntimeSource (..), runtimeSourcePayload)
import JitML.Engines.Engine
  ( KernelHandle (..)
  , engineForSubstrate
  )
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
  )
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Substrate (Substrate (..))

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

-- Phase 241 — unified correct-operator device training entry. Geometry travels
-- in the @geom@ int array + @fparams@ float array; @opcode@ selects the operator
-- (10 GeGLU, 11 Norm, 12 Patch, 13 Attention, 14 Residual). Returns
-- @(out, dX, dW, dB)@ with dW/dB in the operator's packed segment order.
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
  -> IO ()

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
  mkOpTrainFun :: FunPtr OpTrainFun -> OpTrainFun

foreign import ccall "dynamic"
  mkBackendNameFun :: FunPtr BackendNameFun -> BackendNameFun

foreign import ccall "dynamic"
  mkPrimitiveNameFun :: FunPtr PrimitiveNameFun -> PrimitiveNameFun

data LayerGraphOneDnnEvidence = LayerGraphOneDnnEvidence
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

data LayerGraphOneDnnRun = LayerGraphOneDnnRun
  { layerGraphOneDnnTape :: !LayerGraphTape
  , layerGraphOneDnnGradient :: !LayerGraphGradient
  , layerGraphOneDnnEvidence :: ![LayerGraphOneDnnEvidence]
  }
  deriving stock (Eq, Show)

data LayerGraphOneDnnForwardRun = LayerGraphOneDnnForwardRun
  { layerGraphOneDnnForwardTape :: !LayerGraphTape
  , layerGraphOneDnnForwardEvidence :: ![LayerGraphOneDnnEvidence]
  }
  deriving stock (Eq, Show)

data LayerGraphOneDnnFunctions = LayerGraphOneDnnFunctions
  { lgForward :: LayerForwardFun
  , lgBackwardData :: LayerBackwardDataFun
  , lgBackwardWeights :: LayerBackwardWeightsFun
  , lgConvForward :: ConvForwardFun
  , lgConvBackwardData :: ConvBackwardDataFun
  , lgConvBackwardWeights :: ConvBackwardWeightsFun
  , lgOpTrain :: OpTrainFun
  , lgForwardPrimitive :: PrimitiveNameFun
  , lgBackwardDataPrimitive :: PrimitiveNameFun
  , lgBackwardWeightsPrimitive :: PrimitiveNameFun
  }

layerGraphOneDnnKernelSpec :: Cache.KernelSpec
layerGraphOneDnnKernelSpec =
  Cache.KernelSpec "layer-graph-training-onednn-affine-conv"

layerGraphOneDnnRuntimeSource :: RuntimeSource
layerGraphOneDnnRuntimeSource =
  GeneratedOneDnnSource
    { runtimeSourceKernel = layerGraphOneDnnKernelSpec
    , runtimeSourceKind = Cache.Training
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderOneDnnLayerTrainingSource
    }

layerGraphOneDnnToolchainFingerprint :: Cache.ToolchainFingerprint
layerGraphOneDnnToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "g++-shared-c++20-O2-fPIC"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "-DJITML_DETERMINISTIC_REDUCTIONS=1"
        , "abi=extern-c-layer-graph-training"
        , "jitml_layer_forward(float*,const float*,const float*,const float*,int,int,int,int)"
        , "jitml_layer_backward_data(float*,const float*,const float*,int,int,int,int)"
        , "jitml_layer_backward_weights(float*,float*,const float*,const float*,int,int,int,int)"
        , "jitml_conv2d_spatial_forward(...,int×11)"
        , "jitml_conv2d_spatial_backward_data(...,int×11)"
        , "jitml_conv2d_spatial_backward_weights(...,int×11)"
        , "jitml_op_train(int,const int*,int,const float*,int,float*×4,const float*×4,int×4)"
        , "correct-ops=geglu(10)+norm(11)+patch(12)+attention(13)+residual(14)"
        , "primitives=matmul+convolution-forward-training+convolution-backward-data+convolution-backward-weights+spatial-conv2d+geglu-matmul-gelu+normalization+attention-matmul-softmax+patch-matmul+residual-matmul"
        ]
    )

layerGraphOneDnnHash :: Cache.Hash
layerGraphOneDnnHash =
  Cache.cacheKey
    layerGraphOneDnnKernelSpec
    Cache.Training
    Cache.LinuxCPU
    layerGraphOneDnnToolchainFingerprint
    (runtimeSourcePayload layerGraphOneDnnRuntimeSource)
    Cache.defaultTuningChoice

runLayerGraphForwardOneDnn
  :: Env -> LayerGraph -> Vector Double -> IO (Either Text LayerGraphOneDnnForwardRun)
runLayerGraphForwardOneDnn env graph input =
  withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled ->
    deviceForwardGraph functions backendName artifactPath artifactCompiled graph input

layerGraphSquaredErrorGradientOneDnn
  :: Env -> LayerGraph -> Vector Double -> Vector Double -> IO (Either Text LayerGraphOneDnnRun)
layerGraphSquaredErrorGradientOneDnn env graph input target =
  case LayerGraph.layerGraphSquaredErrorGradient graph input target of
    Left err -> pure (Left err)
    Right (tape, pureGradient) -> do
      let seed = VU.zipWith (-) (LayerGraph.layerTapeOutput tape) target
      withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
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
                LayerGraphOneDnnRun
                  { layerGraphOneDnnTape = tape
                  , layerGraphOneDnnGradient = gradient
                  , layerGraphOneDnnEvidence = evidence
                  }
            )
            deviceResult

-- | Classification counterpart of 'layerGraphSquaredErrorGradientOneDnn': runs
-- the update-critical layer-graph training kernels on the oneDNN device for a
-- single labelled example, seeding the backward pass with the softmax
-- cross-entropy output gradient via 'LayerGraph.layerGraphCrossEntropyGradient'.
layerGraphCrossEntropyGradientOneDnn
  :: Env -> LayerGraph -> Vector Double -> Int -> IO (Either Text LayerGraphOneDnnRun)
layerGraphCrossEntropyGradientOneDnn env graph input label =
  case LayerGraph.layerGraphCrossEntropyGradient graph input label of
    Left err -> pure (Left err)
    Right (tape, pureGradient) -> do
      let logits = LayerGraph.layerTapeOutput tape
          seed = VU.imap (\i p -> p - if i == label then 1.0 else 0.0) (softmax logits)
      withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
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
                LayerGraphOneDnnRun
                  { layerGraphOneDnnTape = tape
                  , layerGraphOneDnnGradient = gradient
                  , layerGraphOneDnnEvidence = evidence
                  }
            )
            deviceResult

-- | Batched squared-error gradient: runs the pure oracle once per example, then
-- one batched oneDNN device call per layer over the whole batch (oneDNN
-- @backward_weights@ sums the parameter gradient over the batch).  The returned
-- gradient is the batch-summed gradient, matching the per-example summed oracle
-- within float32 tolerance; only one device round-trip per layer is taken.
layerGraphSquaredErrorGradientBatchOneDnn
  :: Env -> LayerGraph -> [(Vector Double, Vector Double)] -> IO (Either Text LayerGraphOneDnnRun)
layerGraphSquaredErrorGradientBatchOneDnn env graph batch
  | null batch = pure (Left "layerGraphSquaredErrorGradientBatchOneDnn: empty batch")
  | otherwise =
      case traverse (uncurry (LayerGraph.layerGraphSquaredErrorGradient graph)) batch of
        Left err -> pure (Left err)
        Right [] -> pure (Left "layerGraphSquaredErrorGradientBatchOneDnn: empty batch")
        Right pairs@(pair0 : _) -> do
          let seeds =
                zipWith
                  (\(tape, _) (_, target) -> VU.zipWith (-) (LayerGraph.layerTapeOutput tape) target)
                  pairs
                  batch
          withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
            deviceResult <-
              deviceGradientBatch functions backendName artifactPath artifactCompiled seeds pairs
            pure (fmap (batchRun (fst pair0)) deviceResult)

-- | Batched classification counterpart of
-- 'layerGraphSquaredErrorGradientBatchOneDnn'.
layerGraphCrossEntropyGradientBatchOneDnn
  :: Env -> Int -> LayerGraph -> [(Vector Double, Int)] -> IO (Either Text LayerGraphOneDnnRun)
layerGraphCrossEntropyGradientBatchOneDnn env classes graph batch
  | null batch = pure (Left "layerGraphCrossEntropyGradientBatchOneDnn: empty batch")
  | otherwise =
      case traverse (uncurry (LayerGraph.layerGraphClassifierCrossEntropyGradient graph classes)) batch of
        Left err -> pure (Left err)
        Right [] -> pure (Left "layerGraphCrossEntropyGradientBatchOneDnn: empty batch")
        Right pairs@(pair0 : _) -> do
          let seeds =
                zipWith
                  (\(tape, _) (_, label) -> classifierSeed classes (LayerGraph.layerTapeOutput tape) label)
                  pairs
                  batch
          withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
            deviceResult <-
              deviceGradientBatch functions backendName artifactPath artifactCompiled seeds pairs
            pure (fmap (batchRun (fst pair0)) deviceResult)

-- | Batch-summed flat classification cross-entropy parameter gradient over the
-- semantic-prefix @classes@ logits, through the oneDNN device (one batched device
-- call per layer; @backward_weights@ sums over the batch). The device counterpart
-- of 'LayerGraph.pureClassifierBatchGradient', used by the Adam/SGD graph
-- optimizer steppers.
classifierBatchGradientOneDnn
  :: Env -> Int -> LayerGraph -> [(Vector Double, Int)] -> IO (Either Text (Vector Double))
classifierBatchGradientOneDnn env classes graph batch = do
  runResult <- layerGraphCrossEntropyGradientBatchOneDnn env classes graph batch
  pure (fmap (LayerGraph.flattenLayerGraphGradient . layerGraphOneDnnGradient) runResult)

batchRun
  :: LayerGraphTape
  -> (LayerGraphGradient, [LayerGraphOneDnnEvidence])
  -> LayerGraphOneDnnRun
batchRun tape (gradient, evidence) =
  LayerGraphOneDnnRun
    { layerGraphOneDnnTape = tape
    , layerGraphOneDnnGradient = gradient
    , layerGraphOneDnnEvidence = evidence
    }

-- | Full-batch Adam training of a classification 'LayerGraph' through the
-- oneDNN device cross-entropy gradient.  Each epoch accumulates the per-example
-- softmax cross-entropy gradient over the dataset, averages it, and takes one
-- Adam step on the graph's flat parameter vector via
-- 'LayerGraph.replaceGraphParameterVector'.  This is the IR-native supervised
-- classification training loop that makes the typed 'LayerGraph' the single
-- owner of training (Sprint 235.1).
trainLayerGraphClassifierOneDnn
  :: Env
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
trainLayerGraphClassifierOneDnn env classes epochs batchSize learningRate graph0 dataset
  | epochs <= 0 = pure (Left "trainLayerGraphClassifierOneDnn: epochs must be positive")
  | batchSize <= 0 = pure (Left "trainLayerGraphClassifierOneDnn: batch size must be positive")
  | classes <= 0 = pure (Left "trainLayerGraphClassifierOneDnn: class count must be positive")
  | null dataset = pure (Left "trainLayerGraphClassifierOneDnn: empty dataset")
  | otherwise = runEpochs 1 (LayerGraph.initGraphClassifierAdam graph0)
 where
  runEpochs epoch st
    | epoch > epochs = pure (Right (LayerGraph.gcaGraph st))
    | otherwise = do
        stepped <-
          trainLayerGraphClassifierEpochOneDnn env classes batchSize learningRate st dataset
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
trainLayerGraphClassifierEpochOneDnn
  :: Env
  -> Int
  -> Int
  -> Double
  -> LayerGraph.GraphClassifierAdam
  -> [(Vector Double, Int)]
  -> IO (Either Text LayerGraph.GraphClassifierAdam)
trainLayerGraphClassifierEpochOneDnn env classes batchSize learningRate st0 dataset =
  foldBatches (LayerGraph.classifierBatches batchSize dataset) st0
 where
  foldBatches [] st = pure (Right st)
  foldBatches (batch : rest) st = do
    -- One batched device call per layer over the whole mini-batch; the oneDNN
    -- @backward_weights@ reduction sums the parameter gradient over the batch, so
    -- the returned flat gradient is already the batch sum.
    runResult <- layerGraphCrossEntropyGradientBatchOneDnn env classes (LayerGraph.gcaGraph st) batch
    case runResult
      >>= ( \run ->
              LayerGraph.graphAdamBatchStep
                learningRate
                st
                (LayerGraph.flattenLayerGraphGradient (layerGraphOneDnnGradient run))
                (length batch)
          ) of
      Left err -> pure (Left err)
      Right st' -> foldBatches rest st'

withCompiledLayerGraphOneDnn
  :: Env
  -> (LayerGraphOneDnnFunctions -> Text -> Text -> Bool -> IO (Either Text a))
  -> IO (Either Text a)
withCompiledLayerGraphOneDnn env useFunctions = do
  artifactResult <-
    ensureKernelArtifact
      env
      (engineForSubstrate LinuxCPU)
      layerGraphOneDnnRuntimeSource
      layerGraphOneDnnHash
  case artifactResult of
    Left err ->
      pure (Left ("layergraph-onednn compile failed: " <> renderKernelArtifactError err))
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
                          withKernelSymbol path "jitml_op_train" $ \opTrainSymbol -> do
                            backendName <- cStringText =<< mkBackendNameFun backendSymbol
                            let functions =
                                  LayerGraphOneDnnFunctions
                                    { lgForward = mkLayerForwardFun forwardSymbol
                                    , lgBackwardData = mkLayerBackwardDataFun dataSymbol
                                    , lgBackwardWeights = mkLayerBackwardWeightsFun weightsSymbol
                                    , lgConvForward = mkConvForwardFun convFwdSymbol
                                    , lgConvBackwardData = mkConvBackwardDataFun convDataSymbol
                                    , lgConvBackwardWeights = mkConvBackwardWeightsFun convWeightsSymbol
                                    , lgOpTrain = mkOpTrainFun opTrainSymbol
                                    , lgForwardPrimitive = mkPrimitiveNameFun forwardNameSymbol
                                    , lgBackwardDataPrimitive = mkPrimitiveNameFun dataNameSymbol
                                    , lgBackwardWeightsPrimitive = mkPrimitiveNameFun weightsNameSymbol
                                    }
                            useFunctions functions backendName artifactPath (kernelArtifactCompiled artifact)

deviceForwardGraph
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> LayerGraph
  -> Vector Double
  -> IO (Either Text LayerGraphOneDnnForwardRun)
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
              LayerGraphOneDnnForwardRun
                { layerGraphOneDnnForwardTape = tape
                , layerGraphOneDnnForwardEvidence = reverse evidence
                }

deviceForwardNode
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> LayerNode
  -> Vector Double
  -> IO (Either Text (LayerForward, Maybe LayerGraphOneDnnEvidence))
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
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> Vector Double
  -- ^ loss seed: gradient of the loss w.r.t. the graph output
  -> LayerGraphTape
  -> LayerGraphGradient
  -> IO (Either Text (LayerGraphGradient, [LayerGraphOneDnnEvidence]))
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
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> Vector Double
  -- ^ upstream: gradient of the loss w.r.t. this node's output
  -> LayerForward
  -> LayerGradient
  -> IO (Either Text (LayerGradient, Maybe LayerGraphOneDnnEvidence))
deviceLayerGradient functions backendName artifactPath artifactCompiled upstream forward pureGradient =
  case (layerParameters node, layerGradientParameters pureGradient) of
    (Nothing, Nothing) -> pure (Right (pureGradient, Nothing))
    (Just params, Just paramGradient) ->
      case LayerGraph.layerNodeOp node of
        LayerGraph.DenseOp -> denseSingle params paramGradient
        LayerGraph.ConvOp spec
          | is2DConv spec -> convSingle spec params
        LayerGraph.BlockOp _ -> blockSingle
        op
          | isGenericDeviceOp op -> genericSingle
        _ ->
          pure
            ( Left
                ( "layergraph-onednn: operator not supported on device: "
                    <> LayerGraph.layerKindName (layerNodeKind node)
                )
            )
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
  -- forward/backward-data/backward-weights.
  convSingle spec params = do
    let dPre = activationBackwardLocal (layerActivation node) (layerForwardOutput forward) upstream
    result <- runDeviceSpatialConv functions spec params input dPre
    case result of
      Left err -> pure (Left err)
      Right (_out, dx, dw, db) -> finish 1 dx dw db
  -- GeGLU / Norm / Attention / Patch / Residual: one unified device kernel per
  -- operator driven by the true upstream output gradient; dW/dB come back in the
  -- operator's packed segment order.
  genericSingle = do
    result <- runDeviceOp functions node input upstream
    case result of
      Left err -> pure (Left err)
      Right (out, dx, dw, db)
        | VU.length out /= VU.length (layerForwardPreActivation forward) ->
            pure
              ( Left
                  ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
              )
        | otherwise -> finish (deviceOpEvidenceCode (LayerGraph.layerNodeOp node)) dx dw db
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
        | otherwise -> finish (deviceOpEvidenceCode (LayerGraph.layerNodeOp node)) dx dw db

-- | Batched analogue of 'deviceGradient': transposes N per-example tapes/pure
-- gradients into per-layer bundles and takes one batched device call per layer.
-- The returned layer-graph gradient is the batch sum (matching the per-example
-- summed oracle); one evidence entry is recorded per parameterized layer.
deviceGradientBatch
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> [Vector Double]
  -- ^ per-example loss seeds (aligned with @pairs@)
  -> [(LayerGraphTape, LayerGraphGradient)]
  -> IO (Either Text (LayerGraphGradient, [LayerGraphOneDnnEvidence]))
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
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> [Vector Double]
  -- ^ per-example upstream output gradients (aligned with @forwards@)
  -> [LayerForward]
  -> [LayerGradient]
  -> IO (Either Text (LayerGradient, Maybe LayerGraphOneDnnEvidence))
deviceLayerGradientBatch _ _ _ _ _ [] _ =
  pure (Left "layergraph-onednn: empty layer batch")
deviceLayerGradientBatch _ _ _ _ _ _ [] =
  pure (Left "layergraph-onednn: empty layer batch")
deviceLayerGradientBatch functions backendName artifactPath artifactCompiled upstreams forwards@(forward0 : _) grads@(template : _) =
  case (layerParameters node, layerGradientParameters template) of
    (Nothing, Nothing) ->
      pure (Right (template {layerGradientInput = summedPureInput}, Nothing))
    (Just params, Just paramGradient) ->
      case LayerGraph.layerNodeOp node of
        LayerGraph.DenseOp -> denseBatch params paramGradient
        LayerGraph.ConvOp spec
          | is2DConv spec ->
              foldExamples 1 $ \fwd up ->
                let dPre =
                      activationBackwardLocal (layerActivation node) (layerForwardOutput fwd) up
                 in fmap (fmap dropForward) (runDeviceSpatialConv functions spec params (layerForwardInput fwd) dPre)
        LayerGraph.BlockOp _ ->
          foldExamples (deviceOpEvidenceCode (LayerGraph.layerNodeOp node)) $ \fwd up ->
            fmap (fmap dropForward) (runDeviceBlock functions (layerForwardNode fwd) (layerForwardInput fwd) up)
        op
          | isGenericDeviceOp op ->
              foldExamples (deviceOpEvidenceCode op) $ \fwd up ->
                fmap (fmap dropForward) (runDeviceOp functions node (layerForwardInput fwd) up)
        _ ->
          pure
            ( Left
                ( "layergraph-onednn: operator not supported on device (batched): "
                    <> LayerGraph.layerKindName (layerNodeKind node)
                )
            )
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
    _ -> pure (Left "runDeviceSpatialConv: expected 2-D conv geometry")

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

-- | The operator has a real 2-D spatial convolution device kernel.
is2DConv :: LayerGraph.ConvSpec -> Bool
is2DConv spec = length (LayerGraph.convInputDims spec) == 2

-- | The operator is driven by the unified 'jitml_op_train' device kernel.
isGenericDeviceOp :: LayerGraph.LayerOp -> Bool
isGenericDeviceOp op =
  case op of
    LayerGraph.NormOp _ -> True
    LayerGraph.GeGLUOp _ -> True
    LayerGraph.AttentionOp _ -> True
    LayerGraph.PatchOp _ -> True
    LayerGraph.ResidualOp {} -> True
    _ -> False

-- | Descriptive evidence kind code for a correct-operator device kernel (maps to
-- the generated primitive-name reporter). Conv uses the conv2d code (1).
deviceOpEvidenceCode :: LayerGraph.LayerOp -> CInt
deviceOpEvidenceCode op =
  case op of
    LayerGraph.ConvOp _ -> 1
    LayerGraph.NormOp _ -> 3
    LayerGraph.GeGLUOp _ -> 4
    LayerGraph.AttentionOp _ -> 5
    LayerGraph.PatchOp _ -> 6
    LayerGraph.ResidualOp {} -> 7
    LayerGraph.BlockOp _ -> 7
    _ -> 0

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

data DeviceOpPlan = DeviceOpPlan
  { dopCode :: !CInt
  , dopGeom :: ![Int]
  , dopFparams :: ![Double]
  , dopOutLen :: !Int
  }

-- | Build the 'jitml_op_train' invocation plan (opcode, integer geometry, float
-- params, output length) for a correct operator from its verified spec plus the
-- node activation (used as the residual final activation).
deviceOpPlan :: LayerGraph.LayerOp -> LayerActivation -> Int -> Either Text DeviceOpPlan
deviceOpPlan op nodeAct inputLen =
  case op of
    LayerGraph.NormOp spec ->
      let (flavorCode, groups) =
            case LayerGraph.nFlavor spec of
              LayerGraph.NormBatch -> (0, 1)
              LayerGraph.NormLayerWise -> (1, 1)
              LayerGraph.NormGroup g -> (2, g)
       in Right
            DeviceOpPlan
              { dopCode = 11
              , dopGeom =
                  [flavorCode, LayerGraph.nChannels spec, LayerGraph.nSpatial spec, groups]
              , dopFparams = [LayerGraph.nEps spec]
              , dopOutLen = inputLen
              }
    LayerGraph.GeGLUOp spec ->
      Right
        DeviceOpPlan
          { dopCode = 10
          , dopGeom = [LayerGraph.ggIn spec, LayerGraph.ggFf spec, LayerGraph.ggOut spec]
          , dopFparams = []
          , dopOutLen = LayerGraph.ggOut spec
          }
    LayerGraph.AttentionOp spec ->
      Right
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
          }
    LayerGraph.PatchOp spec ->
      let nY = (LayerGraph.peH spec - LayerGraph.peP spec) `div` LayerGraph.peStride spec + 1
          nX = (LayerGraph.peW spec - LayerGraph.peP spec) `div` LayerGraph.peStride spec + 1
       in Right
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
              }
    LayerGraph.ResidualOp inner shortcut scale innerAct -> do
      innerCode <- activationCode innerAct
      finalCode <- activationCode nodeAct
      let hasProj =
            case shortcut of
              LayerGraph.ProjectionShortcut _ -> 1
              LayerGraph.IdentityShortcut -> 0
      Right
        DeviceOpPlan
          { dopCode = 14
          , dopGeom =
              [LayerGraph.asIn inner, LayerGraph.asOut inner, hasProj, innerCode, finalCode]
          , dopFparams = [scale]
          , dopOutLen = LayerGraph.asOut inner
          }
    _ -> Left "layergraph-onednn: deviceOpPlan: unsupported operator"

-- | Run a correct operator's forward + backward on the oneDNN device via the
-- unified 'jitml_op_train' kernel, returning @(out, dInput, dWeights, dBias)@
-- with dWeights/dBias in the operator's packed segment order. This is the device
-- counterpart of the pure per-op oracle (@gegluBackward@ / @normBackward@ /
-- @attentionBackward@ / @patchBackward@ / @residualBackward@) it is validated
-- against within float32 tolerance. @upstream@ is the gradient w.r.t. the node
-- output (single example).
runDeviceOp
  :: LayerGraphOneDnnFunctions
  -> LayerNode
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceOp functions node input upstream =
  case layerParameters node of
    Nothing -> pure (Left ("runDeviceOp: " <> layerNodeName node <> " has no parameters"))
    Just params ->
      case deviceOpPlan (LayerGraph.layerNodeOp node) (layerActivation node) inLen of
        Left err -> pure (Left err)
        Right plan
          | VU.length upstream /= dopOutLen plan ->
              pure (Left "runDeviceOp: upstream length does not match operator output width")
          | VU.length (layerWeights params) /= wLen ->
              pure (Left "runDeviceOp: weight length does not match operator segment layout")
          | VU.length (layerBias params) /= bLen ->
              pure (Left "runDeviceOp: bias length does not match operator segment layout")
          | otherwise ->
              let outLen = dopOutLen plan
               in withArray (fmap fromIntegral (dopGeom plan) :: [CInt]) $ \geomPtr ->
                    withArray (toC (dopFparams plan)) $ \fPtr ->
                      withArray (toC (VU.toList input)) $ \xPtr ->
                        withArray (toC (VU.toList (layerWeights params))) $ \wPtr ->
                          withArray (toC (VU.toList (layerBias params))) $ \bPtr ->
                            withArray (toC (VU.toList upstream)) $ \dyPtr ->
                              allocaArray outLen $ \outPtr ->
                                allocaArray inLen $ \dxPtr ->
                                  allocaArray (max 1 wLen) $ \dwPtr ->
                                    allocaArray (max 1 bLen) $ \dbPtr -> do
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
                                      out <- VU.fromList <$> peekFloats outLen outPtr
                                      dx <- VU.fromList <$> peekFloats inLen dxPtr
                                      dw <- VU.fromList <$> peekFloats wLen dwPtr
                                      dbv <- VU.fromList <$> peekFloats bLen dbPtr
                                      pure (Right (out, dx, dw, dbv))
 where
  inLen = VU.length input
  wLen = sum (LayerGraph.opWeightSegments (LayerGraph.layerNodeOp node))
  bLen = sum (LayerGraph.opBiasSegments (LayerGraph.layerNodeOp node))

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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
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
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> LayerNode
  -> CInt
  -> IO LayerGraphOneDnnEvidence
mkEvidence functions backendName artifactPath artifactCompiled node kindCode = do
  forwardPrimitive <- primitiveNameText (lgForwardPrimitive functions) kindCode
  backwardDataPrimitive <- primitiveNameText (lgBackwardDataPrimitive functions) kindCode
  backwardWeightsPrimitive <- primitiveNameText (lgBackwardWeightsPrimitive functions) kindCode
  pure
    LayerGraphOneDnnEvidence
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

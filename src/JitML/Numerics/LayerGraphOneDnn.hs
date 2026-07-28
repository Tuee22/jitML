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
        , "primitives=matmul+convolution-forward-training+convolution-backward-data+convolution-backward-weights+spatial-conv2d"
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
      withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
        deviceResult <-
          deviceGradient
            functions
            backendName
            artifactPath
            artifactCompiled
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
    Right (tape, pureGradient) ->
      withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
        deviceResult <-
          deviceGradient
            functions
            backendName
            artifactPath
            artifactCompiled
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
        Right pairs@(pair0 : _) ->
          withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
            deviceResult <-
              deviceGradientBatch functions backendName artifactPath artifactCompiled pairs
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
        Right pairs@(pair0 : _) ->
          withCompiledLayerGraphOneDnn env $ \functions backendName artifactPath artifactCompiled -> do
            deviceResult <-
              deviceGradientBatch functions backendName artifactPath artifactCompiled pairs
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
                        withKernelSymbol path "jitml_conv2d_spatial_backward_weights" $ \convWeightsSymbol -> do
                          backendName <- cStringText =<< mkBackendNameFun backendSymbol
                          let functions =
                                LayerGraphOneDnnFunctions
                                  { lgForward = mkLayerForwardFun forwardSymbol
                                  , lgBackwardData = mkLayerBackwardDataFun dataSymbol
                                  , lgBackwardWeights = mkLayerBackwardWeightsFun weightsSymbol
                                  , lgConvForward = mkConvForwardFun convFwdSymbol
                                  , lgConvBackwardData = mkConvBackwardDataFun convDataSymbol
                                  , lgConvBackwardWeights = mkConvBackwardWeightsFun convWeightsSymbol
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
  -> LayerGraphTape
  -> LayerGraphGradient
  -> IO (Either Text (LayerGraphGradient, [LayerGraphOneDnnEvidence]))
deviceGradient functions backendName artifactPath artifactCompiled tape pureGradient = do
  let forwards = LayerGraph.layerTapeLayers tape
      gradients = layerGraphLayerGradients pureGradient
  if length forwards /= length gradients
    then pure (Left "layergraph-onednn: tape/gradient layer count mismatch")
    else do
      results <-
        traverse
          (uncurry (deviceLayerGradient functions backendName artifactPath artifactCompiled))
          (zip forwards gradients)
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
  -> LayerForward
  -> LayerGradient
  -> IO (Either Text (LayerGradient, Maybe LayerGraphOneDnnEvidence))
deviceLayerGradient functions backendName artifactPath artifactCompiled forward pureGradient =
  case (layerParameters node, layerGradientParameters pureGradient) of
    (Nothing, Nothing) -> pure (Right (pureGradient, Nothing))
    (Just params, Just paramGradient) -> do
      let input = layerForwardInput forward
          transformedInput =
            input
          dPre = layerGradBias paramGradient
          inputs = VU.length transformedInput
          outputs = VU.length dPre
          kindCode = layerKindCode (layerNodeKind node)
      result <-
        runDeviceLayer functions kindCode params transformedInput dPre inputs outputs 1
      case result of
        Left err -> pure (Left err)
        Right (preActivation, transformedInputGradient, weightGradient, biasGradient)
          | VU.length preActivation /= VU.length (layerForwardPreActivation forward) ->
              pure
                ( Left
                    ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
                )
          | otherwise -> do
              evidence <-
                mkEvidence
                  functions
                  backendName
                  artifactPath
                  artifactCompiled
                  node
                  kindCode
              let deviceInputGradient =
                    if isResidualKind (layerNodeKind node)
                      then layerGradientInput pureGradient
                      else transformedInputGradient
                  deviceParamGradient =
                    LayerParameterGradient
                      { layerGradWeights = weightGradient
                      , layerGradBias = biasGradient
                      }
              pure
                ( Right
                    ( pureGradient
                        { layerGradientInput = deviceInputGradient
                        , layerGradientParameters = Just deviceParamGradient
                        }
                    , Just evidence
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

-- | Batched analogue of 'deviceGradient': transposes N per-example tapes/pure
-- gradients into per-layer bundles and takes one batched device call per layer.
-- The returned layer-graph gradient is the batch sum (matching the per-example
-- summed oracle); one evidence entry is recorded per parameterized layer.
deviceGradientBatch
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> [(LayerGraphTape, LayerGraphGradient)]
  -> IO (Either Text (LayerGraphGradient, [LayerGraphOneDnnEvidence]))
deviceGradientBatch _ _ _ _ [] = pure (Left "layergraph-onednn: empty batch")
deviceGradientBatch functions backendName artifactPath artifactCompiled pairs@(pair0 : _)
  | any ((/= layerCount) . length) forwardsN
      || any ((/= layerCount) . length) gradsN =
      pure (Left "layergraph-onednn: tape/gradient layer count mismatch")
  | otherwise = do
      results <-
        traverse
          (uncurry (deviceLayerGradientBatch functions backendName artifactPath artifactCompiled))
          (zip (transpose forwardsN) (transpose gradsN))
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
  layerCount = length (LayerGraph.layerTapeLayers (fst pair0))
  template = snd pair0

-- | Batched analogue of 'deviceLayerGradient' for one layer over N examples.
-- Parameter gradients (weights/bias) are summed over the batch inside oneDNN;
-- input gradients are summed on the host in ascending example order.
deviceLayerGradientBatch
  :: LayerGraphOneDnnFunctions
  -> Text
  -> Text
  -> Bool
  -> [LayerForward]
  -> [LayerGradient]
  -> IO (Either Text (LayerGradient, Maybe LayerGraphOneDnnEvidence))
deviceLayerGradientBatch _ _ _ _ [] _ =
  pure (Left "layergraph-onednn: empty layer batch")
deviceLayerGradientBatch _ _ _ _ _ [] =
  pure (Left "layergraph-onednn: empty layer batch")
deviceLayerGradientBatch functions backendName artifactPath artifactCompiled forwards@(forward0 : _) grads@(template : _) =
  case (layerParameters node, layerGradientParameters template) of
    (Nothing, Nothing) ->
      pure (Right (template {layerGradientInput = summedPureInput}, Nothing))
    (Just params, Just paramGradient) -> do
      let inputs = VU.length (layerForwardInput forward0)
          outputs = VU.length (layerGradBias paramGradient)
          kindCode = layerKindCode (layerNodeKind node)
          inputFlat = VU.concat (fmap layerForwardInput forwards)
          dPreFlat = VU.concat [layerGradBias pg | Just pg <- fmap layerGradientParameters grads]
      result <-
        runDeviceLayer functions kindCode params inputFlat dPreFlat inputs outputs batchN
      case result of
        Left err -> pure (Left err)
        Right (preActivation, transformedInputGradient, weightGradient, biasGradient)
          | VU.length preActivation
              /= batchN * VU.length (layerForwardPreActivation forward0) ->
              pure
                ( Left
                    ("layergraph-onednn: forward output length mismatch for " <> layerNodeName node)
                )
          | otherwise -> do
              evidence <-
                mkEvidence functions backendName artifactPath artifactCompiled node kindCode
              let deviceInputGradient =
                    if isResidualKind (layerNodeKind node)
                      then summedPureInput
                      else sumRows batchN inputs transformedInputGradient
                  deviceParamGradient =
                    LayerParameterGradient
                      { layerGradWeights = weightGradient
                      , layerGradBias = biasGradient
                      }
              pure
                ( Right
                    ( template
                        { layerGradientInput = deviceInputGradient
                        , layerGradientParameters = Just deviceParamGradient
                        }
                    , Just evidence
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

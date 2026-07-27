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
  , trainLayerGraphClassifierOneDnn
  )
where

import Control.Monad (foldM, unless)
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
  -> IO ()

type LayerBackwardDataFun =
  Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
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
        , "jitml_layer_forward(float*,const float*,const float*,const float*,int,int,int)"
        , "jitml_layer_backward_data(float*,const float*,const float*,int,int,int)"
        , "jitml_layer_backward_weights(float*,float*,const float*,const float*,int,int,int)"
        , "primitives=matmul+convolution-forward-training+convolution-backward-data+convolution-backward-weights"
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
  -- ^ epochs
  -> Int
  -- ^ mini-batch size (examples are consumed in deterministic order)
  -> Double
  -- ^ learning rate
  -> LayerGraph
  -> [(Vector Double, Int)]
  -- ^ @(features, class label)@ examples
  -> IO (Either Text LayerGraph)
trainLayerGraphClassifierOneDnn env epochs batchSize learningRate graph0 dataset
  | epochs <= 0 = pure (Left "trainLayerGraphClassifierOneDnn: epochs must be positive")
  | batchSize <= 0 = pure (Left "trainLayerGraphClassifierOneDnn: batch size must be positive")
  | null dataset = pure (Left "trainLayerGraphClassifierOneDnn: empty dataset")
  | otherwise = runEpochs 1 graph0 zeroMoments zeroMoments 1
 where
  paramCount = VU.length (LayerGraph.graphParameterVector graph0)
  zeroMoments = VU.replicate paramCount 0
  beta1 = 0.9
  beta2 = 0.999
  epsilon = 1.0e-8
  batches = chunksOfList batchSize dataset
  -- Adam moments @m@/@v@ and the step counter @t@ thread across every
  -- mini-batch of every epoch (one Adam step per batch).
  runEpochs epoch graph m v t
    | epoch > epochs = pure (Right graph)
    | otherwise = do
        result <- runBatches batches graph m v t
        case result of
          Left err -> pure (Left err)
          Right (graph', m', v', t') -> runEpochs (epoch + 1) graph' m' v' t'
  runBatches [] graph m v t = pure (Right (graph, m, v, t))
  runBatches (batch : rest) graph m v t = do
    gradientResult <- accumulateGradient graph batch
    case gradientResult of
      Left err -> pure (Left err)
      Right summed ->
        let grad = VU.map (/ fromIntegral (length batch)) summed
            tD = fromIntegral t :: Double
            bc1 = 1 - beta1 ** tD
            bc2 = 1 - beta2 ** tD
            m' = VU.zipWith (\mi gi -> beta1 * mi + (1 - beta1) * gi) m grad
            v' = VU.zipWith (\vi gi -> beta2 * vi + (1 - beta2) * gi * gi) v grad
            params = LayerGraph.graphParameterVector graph
            params' =
              VU.zipWith3
                (\p mi vi -> p - learningRate * (mi / bc1) / (sqrt (vi / bc2) + epsilon))
                params
                m'
                v'
         in case LayerGraph.replaceGraphParameterVector graph params' of
              Left err -> pure (Left err)
              Right graph' -> runBatches rest graph' m' v' (t + 1)
  accumulateGradient graph = foldM step (Right VU.empty)
   where
    step (Left err) _ = pure (Left err)
    step (Right summed) (features, label) = do
      runResult <- layerGraphCrossEntropyGradientOneDnn env graph features label
      pure $ case runResult of
        Left err -> Left err
        Right run ->
          let g = LayerGraph.flattenLayerGraphGradient (layerGraphOneDnnGradient run)
           in Right (if VU.null summed then g else VU.zipWith (+) summed g)

chunksOfList :: Int -> [a] -> [[a]]
chunksOfList n xs
  | n <= 0 = [xs]
  | otherwise = case splitAt n xs of
      ([], _) -> []
      (chunk, rest) -> chunk : chunksOfList n rest

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
                  withKernelSymbol path "jitml_layer_backward_weights" $ \weightsSymbol -> do
                    backendName <- cStringText =<< mkBackendNameFun backendSymbol
                    let functions =
                          LayerGraphOneDnnFunctions
                            { lgForward = mkLayerForwardFun forwardSymbol
                            , lgBackwardData = mkLayerBackwardDataFun dataSymbol
                            , lgBackwardWeights = mkLayerBackwardWeightsFun weightsSymbol
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
        runDeviceLayer functions kindCode params transformedInput dPre inputs outputs
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

runDeviceLayer
  :: LayerGraphOneDnnFunctions
  -> CInt
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> Int
  -> Int
  -> IO (Either Text (Vector Double, Vector Double, Vector Double, Vector Double))
runDeviceLayer functions kindCode params input dPre inputs outputs
  | VU.length (layerWeights params) /= inputs * outputs =
      pure (Left "layergraph-onednn: weight length does not match input/output width")
  | VU.length (layerBias params) /= outputs =
      pure (Left "layergraph-onednn: bias length does not match output width")
  | VU.length dPre /= outputs =
      pure (Left "layergraph-onednn: dPre length does not match output width")
  | otherwise =
      withArray (toC (VU.toList input)) $ \inputPtr ->
        withArray (toC (VU.toList (layerWeights params))) $ \weightsPtr ->
          withArray (toC (VU.toList (layerBias params))) $ \biasPtr ->
            withArray (toC (VU.toList dPre)) $ \dPrePtr ->
              allocaArray outputs $ \prePtr ->
                allocaArray inputs $ \inputGradPtr ->
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
                      lgBackwardData
                        functions
                        inputGradPtr
                        dPrePtr
                        weightsPtr
                        (fromIntegral inputs)
                        (fromIntegral outputs)
                        kindCode
                      lgBackwardWeights
                        functions
                        weightGradPtr
                        biasGradPtr
                        dPrePtr
                        inputPtr
                        (fromIntegral inputs)
                        (fromIntegral outputs)
                        kindCode
                      preActivation <- VU.fromList <$> peekFloats outputs prePtr
                      inputGradient <- VU.fromList <$> peekFloats inputs inputGradPtr
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
              Right . VU.fromList <$> peekFloats outputs prePtr

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

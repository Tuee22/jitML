{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 23.1 — typed layer graph plus a pure reverse-mode autodiff oracle.
--
-- This module is intentionally backend-independent. Phase 23.2 wires the same
-- node catalog to oneDNN training kernels; this sprint gives every layer kind a
-- typed graph representation, deterministic parameter tensors, a pure forward
-- pass, and a reverse-mode backward pass that can be checked by finite
-- differences.
module JitML.Numerics.LayerGraph
  ( TensorShape (..)
  , tensorShapeWidth
  , LayerMode (..)
  , LayerActivation (..)
  , PoolKind (..)
  , NormKind (..)
  , LayerKind (..)
  , layerKindName
  , allLayerKinds
  , LayerParameters (..)
  , LayerNode (..)
  , LayerGraph (..)
  , LayerForward (..)
  , LayerGraphTape (..)
  , LayerParameterGradient (..)
  , LayerGradient (..)
  , LayerGraphGradient (..)
  , deterministicParameters
  , mkAffineLayer
  , mkIdentityLayer
  , runLayerGraph
  , backwardLayerGraph
  , layerGraphSquaredErrorGradient
  , layerGraphLoss
  , graphParameterVector
  , replaceGraphParameterVector
  , maxFiniteDifferenceError
  )
where

import Control.Monad (foldM, unless, when)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

newtype TensorShape = TensorShape {unTensorShape :: [Int]}
  deriving stock (Eq, Show)

tensorShapeWidth :: TensorShape -> Either Text Int
tensorShapeWidth (TensorShape dims)
  | null dims = Left "TensorShape must have at least one dimension"
  | any (<= 0) dims = Left ("TensorShape dimensions must be positive: " <> Text.pack (show dims))
  | otherwise = Right (product dims)

data LayerMode
  = TrainingMode
  | InferenceMode
  deriving stock (Eq, Show)

data LayerActivation
  = LinearActivation
  | TanhActivation
  | ReluActivation
  | SoftmaxActivation
  deriving stock (Eq, Show)

data PoolKind
  = MaxPool
  | AvgPool
  | GlobalAvgPool
  deriving stock (Eq, Show)

data NormKind
  = BatchNorm
  | LayerNorm
  | GroupNorm Int
  deriving stock (Eq, Show)

data LayerKind
  = DenseLayer
  | Conv2DLayer
  | Conv3DLayer
  | PoolLayer PoolKind
  | NormLayer NormKind
  | DropoutLayer Double
  | ResidualLayer Double
  | BasicBlockLayer Double
  | BottleneckBlockLayer Double
  | MultiHeadAttentionLayer Int
  | GeGLULayer
  | PatchEmbedLayer
  deriving stock (Eq, Show)

layerKindName :: LayerKind -> Text
layerKindName DenseLayer = "Dense"
layerKindName Conv2DLayer = "Conv2D"
layerKindName Conv3DLayer = "Conv3D"
layerKindName (PoolLayer MaxPool) = "MaxPool"
layerKindName (PoolLayer AvgPool) = "AvgPool"
layerKindName (PoolLayer GlobalAvgPool) = "GlobalAvgPool"
layerKindName (NormLayer BatchNorm) = "BatchNorm"
layerKindName (NormLayer LayerNorm) = "LayerNorm"
layerKindName (NormLayer (GroupNorm groups)) = "GroupNorm(" <> Text.pack (show groups) <> ")"
layerKindName (DropoutLayer rate) = "Dropout(" <> Text.pack (show rate) <> ")"
layerKindName (ResidualLayer _) = "Residual"
layerKindName (BasicBlockLayer _) = "BasicBlock"
layerKindName (BottleneckBlockLayer _) = "BottleneckBlock"
layerKindName (MultiHeadAttentionLayer heads) = "MultiHeadAttention(" <> Text.pack (show heads) <> ")"
layerKindName GeGLULayer = "GeGLU"
layerKindName PatchEmbedLayer = "PatchEmbed"

allLayerKinds :: [LayerKind]
allLayerKinds =
  [ DenseLayer
  , Conv2DLayer
  , Conv3DLayer
  , PoolLayer MaxPool
  , PoolLayer AvgPool
  , PoolLayer GlobalAvgPool
  , NormLayer BatchNorm
  , NormLayer LayerNorm
  , NormLayer (GroupNorm 2)
  , DropoutLayer 0.1
  , ResidualLayer 0.1
  , BasicBlockLayer 0.1
  , BottleneckBlockLayer 0.1
  , MultiHeadAttentionLayer 2
  , GeGLULayer
  , PatchEmbedLayer
  ]

data LayerParameters = LayerParameters
  { layerWeights :: !(Vector Double)
  , layerBias :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data LayerNode = LayerNode
  { layerNodeName :: !Text
  , layerNodeKind :: !LayerKind
  , layerInputShape :: !TensorShape
  , layerOutputShape :: !TensorShape
  , layerMode :: !LayerMode
  , layerActivation :: !LayerActivation
  , layerParameters :: !(Maybe LayerParameters)
  }
  deriving stock (Eq, Show)

data LayerGraph = LayerGraph
  { layerGraphName :: !Text
  , layerGraphInputShape :: !TensorShape
  , layerGraphOutputShape :: !TensorShape
  , layerGraphNodes :: ![LayerNode]
  }
  deriving stock (Eq, Show)

data LayerForward = LayerForward
  { layerForwardNode :: !LayerNode
  , layerForwardInput :: !(Vector Double)
  , layerForwardPreActivation :: !(Vector Double)
  , layerForwardOutput :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data LayerGraphTape = LayerGraphTape
  { layerTapeInput :: !(Vector Double)
  , layerTapeOutput :: !(Vector Double)
  , layerTapeLayers :: ![LayerForward]
  }
  deriving stock (Eq, Show)

data LayerParameterGradient = LayerParameterGradient
  { layerGradWeights :: !(Vector Double)
  , layerGradBias :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data LayerGradient = LayerGradient
  { layerGradientName :: !Text
  , layerGradientInput :: !(Vector Double)
  , layerGradientParameters :: !(Maybe LayerParameterGradient)
  }
  deriving stock (Eq, Show)

data LayerGraphGradient = LayerGraphGradient
  { layerGraphInputGradient :: !(Vector Double)
  , layerGraphLayerGradients :: ![LayerGradient]
  }
  deriving stock (Eq, Show)

deterministicParameters :: Int -> Int -> Int -> LayerParameters
deterministicParameters seed inputWidth outputWidth =
  let limit = sqrt (6.0 / fromIntegral (max 1 (inputWidth + outputWidth)))
      (weights, _gen) = drawUniform (inputWidth * outputWidth) limit (Random.mkStdGen seed)
   in LayerParameters
        { layerWeights = weights
        , layerBias = VU.replicate outputWidth 0.0
        }

mkAffineLayer
  :: Text
  -> LayerKind
  -> Int
  -> Int
  -> LayerActivation
  -> LayerMode
  -> LayerParameters
  -> Either Text LayerNode
mkAffineLayer name kind inputWidth outputWidth activation mode params = do
  validatePositive "inputWidth" inputWidth
  validatePositive "outputWidth" outputWidth
  let expectedWeights = inputWidth * outputWidth
  when (VU.length (layerWeights params) /= expectedWeights) $
    Left
      ( name
          <> " expected "
          <> Text.pack (show expectedWeights)
          <> " weights, got "
          <> Text.pack (show (VU.length (layerWeights params)))
      )
  when (VU.length (layerBias params) /= outputWidth) $
    Left
      ( name
          <> " expected "
          <> Text.pack (show outputWidth)
          <> " bias values, got "
          <> Text.pack (show (VU.length (layerBias params)))
      )
  pure
    LayerNode
      { layerNodeName = name
      , layerNodeKind = kind
      , layerInputShape = TensorShape [inputWidth]
      , layerOutputShape = TensorShape [outputWidth]
      , layerMode = mode
      , layerActivation = activation
      , layerParameters = Just params
      }

mkIdentityLayer :: Text -> LayerKind -> Int -> LayerMode -> Either Text LayerNode
mkIdentityLayer name kind width mode = do
  validatePositive "width" width
  pure
    LayerNode
      { layerNodeName = name
      , layerNodeKind = kind
      , layerInputShape = TensorShape [width]
      , layerOutputShape = TensorShape [width]
      , layerMode = mode
      , layerActivation = LinearActivation
      , layerParameters = Nothing
      }

runLayerGraph :: LayerGraph -> Vector Double -> Either Text LayerGraphTape
runLayerGraph graph input = do
  inputWidth <- tensorShapeWidth (layerGraphInputShape graph)
  expectedOutputWidth <- tensorShapeWidth (layerGraphOutputShape graph)
  unless (VU.length input == inputWidth) $
    Left
      ( layerGraphName graph
          <> " expected input width "
          <> Text.pack (show inputWidth)
          <> ", got "
          <> Text.pack (show (VU.length input))
      )
  (output, forwards) <-
    foldM
      ( \(current, layers) node -> do
          forward <- runLayerNode node current
          pure (layerForwardOutput forward, forward : layers)
      )
      (input, [])
      (layerGraphNodes graph)
  unless (VU.length output == expectedOutputWidth) $
    Left
      ( layerGraphName graph
          <> " produced output width "
          <> Text.pack (show (VU.length output))
          <> ", expected "
          <> Text.pack (show expectedOutputWidth)
      )
  pure
    LayerGraphTape
      { layerTapeInput = input
      , layerTapeOutput = output
      , layerTapeLayers = reverse forwards
      }

backwardLayerGraph
  :: LayerGraph -> LayerGraphTape -> Vector Double -> Either Text LayerGraphGradient
backwardLayerGraph graph tape upstream = do
  outputWidth <- tensorShapeWidth (layerGraphOutputShape graph)
  unless (VU.length upstream == outputWidth) $
    Left
      ( layerGraphName graph
          <> " expected output gradient width "
          <> Text.pack (show outputWidth)
          <> ", got "
          <> Text.pack (show (VU.length upstream))
      )
  (inputGradient, gradients) <-
    foldM
      ( \(current, grads) forward -> do
          (next, grad) <- backwardLayerNode forward current
          pure (next, grad : grads)
      )
      (upstream, [])
      (reverse (layerTapeLayers tape))
  pure
    LayerGraphGradient
      { layerGraphInputGradient = inputGradient
      , layerGraphLayerGradients = gradients
      }

layerGraphSquaredErrorGradient
  :: LayerGraph -> Vector Double -> Vector Double -> Either Text (LayerGraphTape, LayerGraphGradient)
layerGraphSquaredErrorGradient graph input target = do
  tape <- runLayerGraph graph input
  unless (VU.length target == VU.length (layerTapeOutput tape)) $
    Left "layerGraphSquaredErrorGradient: target width differs from graph output"
  let upstream = VU.zipWith (-) (layerTapeOutput tape) target
  gradient <- backwardLayerGraph graph tape upstream
  pure (tape, gradient)

layerGraphLoss :: LayerGraph -> Vector Double -> Vector Double -> Either Text Double
layerGraphLoss graph input target = do
  tape <- runLayerGraph graph input
  unless (VU.length target == VU.length (layerTapeOutput tape)) $
    Left "layerGraphLoss: target width differs from graph output"
  pure (0.5 * VU.sum (VU.map (\x -> x * x) (VU.zipWith (-) (layerTapeOutput tape) target)))

graphParameterVector :: LayerGraph -> Vector Double
graphParameterVector =
  VU.concat . fmap nodeParams . layerGraphNodes
 where
  nodeParams node =
    case layerParameters node of
      Nothing -> VU.empty
      Just params -> VU.concat [layerWeights params, layerBias params]

replaceGraphParameterVector :: LayerGraph -> Vector Double -> Either Text LayerGraph
replaceGraphParameterVector graph flat = do
  (nodes, consumed) <- mapAccumEither replaceNode 0 (layerGraphNodes graph)
  when (consumed /= VU.length flat) $
    Left
      ( "replaceGraphParameterVector consumed "
          <> Text.pack (show consumed)
          <> " values, got "
          <> Text.pack (show (VU.length flat))
      )
  pure graph {layerGraphNodes = nodes}
 where
  replaceNode offset node =
    case layerParameters node of
      Nothing -> Right (node, offset)
      Just params ->
        let wLen = VU.length (layerWeights params)
            bLen = VU.length (layerBias params)
            total = wLen + bLen
         in if offset + total > VU.length flat
              then Left ("not enough flat parameters for " <> layerNodeName node)
              else
                let slice = VU.slice offset total flat
                    weights = VU.take wLen slice
                    bias = VU.drop wLen slice
                 in Right
                      ( node
                          { layerParameters =
                              Just
                                LayerParameters
                                  { layerWeights = weights
                                  , layerBias = bias
                                  }
                          }
                      , offset + total
                      )

maxFiniteDifferenceError
  :: Double -> LayerGraph -> Vector Double -> Vector Double -> Either Text Double
maxFiniteDifferenceError epsilon graph input target = do
  unless (epsilon > 0) $
    Left "maxFiniteDifferenceError: epsilon must be positive"
  (_tape, gradient) <- layerGraphSquaredErrorGradient graph input target
  let analytic = flattenLayerGraphGradient gradient
      baseParams = graphParameterVector graph
  unless (VU.length analytic == VU.length baseParams) $
    Left "maxFiniteDifferenceError: analytic gradient length differs from parameter vector"
  errors <-
    traverse
      (finiteDifferenceAt epsilon graph input target baseParams analytic)
      [0 .. VU.length baseParams - 1]
  pure (maximum (0.0 : errors))

runLayerNode :: LayerNode -> Vector Double -> Either Text LayerForward
runLayerNode node input = do
  inputWidth <- tensorShapeWidth (layerInputShape node)
  outputWidth <- tensorShapeWidth (layerOutputShape node)
  unless (VU.length input == inputWidth) $
    Left
      ( layerNodeName node
          <> " expected input width "
          <> Text.pack (show inputWidth)
          <> ", got "
          <> Text.pack (show (VU.length input))
      )
  (preActivation, output) <-
    case layerParameters node of
      Just params -> do
        let transformedInput = parameterizedInputForward (layerNodeKind node) input
        pre <- affinePreActivation params transformedInput outputWidth
        let activated = applyActivation (layerActivation node) pre
            out =
              case residualScale (layerNodeKind node) of
                Just scale
                  | VU.length input == VU.length activated ->
                      VU.zipWith (+) input (VU.map (* scale) activated)
                _ -> activated
        pure (pre, out)
      Nothing ->
        let out = parameterlessForward node input outputWidth
         in pure (out, out)
  pure
    LayerForward
      { layerForwardNode = node
      , layerForwardInput = input
      , layerForwardPreActivation = preActivation
      , layerForwardOutput = output
      }

backwardLayerNode :: LayerForward -> Vector Double -> Either Text (Vector Double, LayerGradient)
backwardLayerNode forward upstream =
  case layerParameters node of
    Just params -> do
      outputWidth <- tensorShapeWidth (layerOutputShape node)
      unless (VU.length upstream == outputWidth) $
        Left (layerNodeName node <> " upstream gradient width mismatch")
      let activated =
            applyActivation
              (layerActivation node)
              (layerForwardPreActivation forward)
          scale = residualScale (layerNodeKind node)
          residualUpstream =
            case scale of
              Just residual
                | VU.length upstream == VU.length (layerForwardInput forward) ->
                    VU.map (* residual) upstream
              _ -> upstream
          dPre = activationBackward (layerActivation node) activated residualUpstream
          transformedInput =
            parameterizedInputForward (layerNodeKind node) (layerForwardInput forward)
          paramGrad =
            LayerParameterGradient
              { layerGradWeights = outerProduct dPre transformedInput
              , layerGradBias = dPre
              }
          transformedInputGrad =
            matVecTransposed
              (layerWeights params)
              (VU.length dPre)
              (VU.length transformedInput)
              dPre
          inputGradFromLayer =
            parameterizedInputBackward
              (layerNodeKind node)
              (layerForwardInput forward)
              transformedInputGrad
          inputGrad =
            case scale of
              Just _
                | VU.length upstream == VU.length inputGradFromLayer ->
                    VU.zipWith (+) upstream inputGradFromLayer
              _ -> inputGradFromLayer
      pure
        ( inputGrad
        , LayerGradient
            { layerGradientName = layerNodeName node
            , layerGradientInput = inputGrad
            , layerGradientParameters = Just paramGrad
            }
        )
    Nothing -> do
      inputWidth <- tensorShapeWidth (layerInputShape node)
      let inputGrad = parameterlessBackward node inputWidth upstream
      pure
        ( inputGrad
        , LayerGradient
            { layerGradientName = layerNodeName node
            , layerGradientInput = inputGrad
            , layerGradientParameters = Nothing
            }
        )
 where
  node = layerForwardNode forward

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
    NormLayer normKind ->
      resizeIdentity (normalizeVector normKind input) outputWidth
    _ -> resizeIdentity input outputWidth

parameterlessBackward :: LayerNode -> Int -> Vector Double -> Vector Double
parameterlessBackward node inputWidth upstream =
  case layerNodeKind node of
    DropoutLayer rate ->
      let scale =
            case layerMode node of
              TrainingMode -> 1.0 - clampDouble 0.0 0.95 rate
              InferenceMode -> 1.0
       in VU.map (* scale) (resizeIdentity upstream inputWidth)
    PoolLayer GlobalAvgPool ->
      VU.replicate inputWidth (VU.sum upstream / fromIntegral (max 1 inputWidth))
    PoolLayer AvgPool ->
      distributeAverage upstream inputWidth
    PoolLayer MaxPool ->
      distributeAverage upstream inputWidth
    NormLayer _ ->
      distributeAverage upstream inputWidth
    _ -> resizeIdentity upstream inputWidth

parameterizedInputForward :: LayerKind -> Vector Double -> Vector Double
parameterizedInputForward kind input =
  case kind of
    Conv2DLayer -> stencilTransform [(0, 0.50), (-1, 0.25), (1, 0.25)] input
    Conv3DLayer -> stencilTransform [(0, 0.40), (-1, 0.20), (1, 0.20), (-2, 0.10), (2, 0.10)] input
    PatchEmbedLayer -> patchMaskTransform input
    MultiHeadAttentionLayer heads -> attentionContextTransform heads input
    GeGLULayer -> VU.map gegluInput input
    BasicBlockLayer scale ->
      VU.zipWith (+) input (VU.map (* scale) (stencilTransform [(0, 0.50), (-1, 0.25), (1, 0.25)] input))
    BottleneckBlockLayer scale ->
      VU.zipWith
        (+)
        input
        (VU.map (* scale) (stencilTransform [(0, 0.40), (-1, 0.20), (1, 0.20), (-2, 0.10), (2, 0.10)] input))
    _ -> input

parameterizedInputBackward :: LayerKind -> Vector Double -> Vector Double -> Vector Double
parameterizedInputBackward kind input upstream =
  case kind of
    Conv2DLayer -> stencilBackward [(0, 0.50), (-1, 0.25), (1, 0.25)] (VU.length input) upstream
    Conv3DLayer ->
      stencilBackward [(0, 0.40), (-1, 0.20), (1, 0.20), (-2, 0.10), (2, 0.10)] (VU.length input) upstream
    PatchEmbedLayer -> patchMaskBackward input upstream
    MultiHeadAttentionLayer heads -> attentionContextBackward heads input upstream
    GeGLULayer -> VU.zipWith (*) (VU.map gegluInputDerivative input) upstream
    BasicBlockLayer scale ->
      VU.zipWith
        (+)
        upstream
        (VU.map (* scale) (stencilBackward [(0, 0.50), (-1, 0.25), (1, 0.25)] (VU.length input) upstream))
    BottleneckBlockLayer scale ->
      VU.zipWith
        (+)
        upstream
        ( VU.map
            (* scale)
            (stencilBackward [(0, 0.40), (-1, 0.20), (1, 0.20), (-2, 0.10), (2, 0.10)] (VU.length input) upstream)
        )
    _ -> upstream

stencilTransform :: [(Int, Double)] -> Vector Double -> Vector Double
stencilTransform taps input =
  let n = VU.length input
   in VU.generate n $ \idx ->
        sum
          [ weight * (input VU.! clampIndex n (idx + offset))
          | (offset, weight) <- taps
          ]

stencilBackward :: [(Int, Double)] -> Int -> Vector Double -> Vector Double
stencilBackward taps inputWidth upstream =
  VU.generate inputWidth $ \inputIdx ->
    sum
      [ weight * (upstream VU.! outputIdx)
      | outputIdx <- [0 .. VU.length upstream - 1]
      , (offset, weight) <- taps
      , clampIndex inputWidth (outputIdx + offset) == inputIdx
      ]

clampIndex :: Int -> Int -> Int
clampIndex n idx
  | n <= 1 = 0
  | idx < 0 = 0
  | idx >= n = n - 1
  | otherwise = idx

patchMaskTransform :: Vector Double -> Vector Double
patchMaskTransform =
  VU.imap (\idx value -> value * patchMask idx)

patchMaskBackward :: Vector Double -> Vector Double -> Vector Double
patchMaskBackward input upstream =
  VU.imap (\idx _ -> (upstream VU.! idx) * patchMask idx) input

patchMask :: Int -> Double
patchMask idx =
  0.75 + 0.05 * fromIntegral (idx `mod` 5)

attentionContextTransform :: Int -> Vector Double -> Vector Double
attentionContextTransform heads input =
  let n = max 1 (VU.length input)
      mean = VU.sum input / fromIntegral n
      contextWeight = 1.0 / fromIntegral (max 1 heads + 1)
   in VU.map (\value -> (1.0 - contextWeight) * value + contextWeight * mean) input

attentionContextBackward :: Int -> Vector Double -> Vector Double -> Vector Double
attentionContextBackward heads input upstream =
  let n = max 1 (VU.length input)
      contextWeight = 1.0 / fromIntegral (max 1 heads + 1)
      shared = contextWeight * VU.sum upstream / fromIntegral n
   in VU.map (\value -> (1.0 - contextWeight) * value + shared) upstream

gegluInput :: Double -> Double
gegluInput value =
  value * sigmoid value

gegluInputDerivative :: Double -> Double
gegluInputDerivative value =
  let s = sigmoid value
   in s + value * s * (1.0 - s)

sigmoid :: Double -> Double
sigmoid value =
  1.0 / (1.0 + exp (negate value))

normalizeVector :: NormKind -> Vector Double -> Vector Double
normalizeVector normKind input =
  case normKind of
    GroupNorm groups -> normalizeGroups (max 1 groups) input
    BatchNorm -> normalizeOne input
    LayerNorm -> normalizeOne input

normalizeGroups :: Int -> Vector Double -> Vector Double
normalizeGroups groups input =
  let n = VU.length input
      groupSize = max 1 ((n + groups - 1) `div` groups)
   in VU.concat
        [ normalizeOne (VU.slice start (min groupSize (n - start)) input)
        | start <- [0, groupSize .. n - 1]
        ]

normalizeOne :: Vector Double -> Vector Double
normalizeOne values
  | VU.null values = VU.empty
  | otherwise =
      let mean = meanVector values
          centered = VU.map (subtract mean) values
          variance = VU.sum (VU.map (\x -> x * x) centered) / fromIntegral (VU.length values)
          invStd = 1.0 / sqrt (variance + 1.0e-6)
       in VU.map (* invStd) centered

affinePreActivation :: LayerParameters -> Vector Double -> Int -> Either Text (Vector Double)
affinePreActivation params input outputWidth = do
  let inputWidth = VU.length input
      expected = inputWidth * outputWidth
  unless (VU.length (layerWeights params) == expected) $
    Left "affinePreActivation: weight length does not match input/output width"
  unless (VU.length (layerBias params) == outputWidth) $
    Left "affinePreActivation: bias length does not match output width"
  pure (VU.zipWith (+) (matVec (layerWeights params) outputWidth inputWidth input) (layerBias params))

applyActivation :: LayerActivation -> Vector Double -> Vector Double
applyActivation LinearActivation = id
applyActivation TanhActivation = VU.map tanh
applyActivation ReluActivation = VU.map (max 0.0)
applyActivation SoftmaxActivation = softmax

activationBackward :: LayerActivation -> Vector Double -> Vector Double -> Vector Double
activationBackward LinearActivation _ upstream = upstream
activationBackward TanhActivation activated upstream =
  VU.zipWith (\a u -> (1.0 - a * a) * u) activated upstream
activationBackward ReluActivation activated upstream =
  VU.zipWith (\a u -> if a > 0.0 then u else 0.0) activated upstream
activationBackward SoftmaxActivation activated upstream =
  let dot = VU.sum (VU.zipWith (*) activated upstream)
   in VU.zipWith (\a u -> a * (u - dot)) activated upstream

residualScale :: LayerKind -> Maybe Double
residualScale (ResidualLayer scale) = Just scale
residualScale (BasicBlockLayer scale) = Just scale
residualScale (BottleneckBlockLayer scale) = Just scale
residualScale _ = Nothing

flattenLayerGraphGradient :: LayerGraphGradient -> Vector Double
flattenLayerGraphGradient =
  VU.concat . fmap layerParams . layerGraphLayerGradients
 where
  layerParams gradient =
    case layerGradientParameters gradient of
      Nothing -> VU.empty
      Just params -> VU.concat [layerGradWeights params, layerGradBias params]

finiteDifferenceAt
  :: Double
  -> LayerGraph
  -> Vector Double
  -> Vector Double
  -> Vector Double
  -> Vector Double
  -> Int
  -> Either Text Double
finiteDifferenceAt epsilon graph input target baseParams analytic idx = do
  let plusParams = baseParams VU.// [(idx, baseParams VU.! idx + epsilon)]
      minusParams = baseParams VU.// [(idx, baseParams VU.! idx - epsilon)]
  plusGraph <- replaceGraphParameterVector graph plusParams
  minusGraph <- replaceGraphParameterVector graph minusParams
  plusLoss <- layerGraphLoss plusGraph input target
  minusLoss <- layerGraphLoss minusGraph input target
  let numeric = (plusLoss - minusLoss) / (2.0 * epsilon)
  pure (abs (numeric - (analytic VU.! idx)))

matVec :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVec weights rows cols input =
  VU.generate rows $ \r ->
    VU.sum
      ( VU.generate cols $ \c ->
          (weights VU.! (r * cols + c)) * (input VU.! c)
      )

matVecTransposed :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVecTransposed weights rows cols upstream =
  VU.generate cols $ \c ->
    VU.sum
      ( VU.generate rows $ \r ->
          (weights VU.! (r * cols + c)) * (upstream VU.! r)
      )

outerProduct :: Vector Double -> Vector Double -> Vector Double
outerProduct left right =
  VU.generate (VU.length left * VU.length right) $ \idx ->
    let (row, col) = idx `quotRem` VU.length right
     in (left VU.! row) * (right VU.! col)

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

drawUniform :: Int -> Double -> Random.StdGen -> (Vector Double, Random.StdGen)
drawUniform n limit gen0 =
  let (values, genN) = go n gen0 []
   in (VU.fromList (reverse values), genN)
 where
  go 0 g acc = (acc, g)
  go k g acc =
    let (u, g') = Random.uniformR (-limit, limit) g
     in go (k - 1) g' (u : acc)

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

distributeAverage :: Vector Double -> Int -> Vector Double
distributeAverage upstream inputWidth
  | inputWidth <= 0 = VU.empty
  | VU.null upstream = VU.replicate inputWidth 0.0
  | otherwise =
      VU.generate inputWidth $ \idx ->
        let bucket = idx `mod` VU.length upstream
            bucketSize =
              length [bucket, bucket + VU.length upstream .. inputWidth - 1]
         in (upstream VU.! bucket) / fromIntegral (max 1 bucketSize)

meanVector :: Vector Double -> Double
meanVector values
  | VU.null values = 0.0
  | otherwise = VU.sum values / fromIntegral (VU.length values)

validatePositive :: Text -> Int -> Either Text ()
validatePositive label value
  | value > 0 = Right ()
  | otherwise = Left (label <> " must be positive, got " <> Text.pack (show value))

clampDouble :: Double -> Double -> Double -> Double
clampDouble lo hi = min hi . max lo

mapAccumEither :: (acc -> x -> Either e (y, acc)) -> acc -> [x] -> Either e ([y], acc)
mapAccumEither f =
  go []
 where
  go ys acc [] = Right (reverse ys, acc)
  go ys acc (x : xs) = do
    (y, acc') <- f acc x
    go (y : ys) acc' xs

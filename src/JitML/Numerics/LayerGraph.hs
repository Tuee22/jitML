{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 23.1 — typed layer graph plus a pure reverse-mode autodiff engine.
--
-- This module is intentionally backend-independent. Phase 23.2 wires the same
-- node catalog to oneDNN training kernels; this sprint gives every layer kind a
-- typed graph representation, deterministic parameter tensors, a correct
-- forward pass, and a correct reverse-mode backward pass verified by finite
-- differences on both parameter and input gradients.
--
-- Two node tiers share one 'LayerNode' type:
--
--   * Tier-1 coarse operators ('DenseOp', 'IdentityOp', 'DropoutOp') built by
--     'mkAffineLayer' / 'mkIdentityLayer' / 'mkDropoutLayer'. These carry the
--     @W1,b1,W2,b2@-compatible flat 'LayerParameters' and are what the served
--     supervised graph and the MLP special case execute.
--   * Tier-2 verified nodes ('ConvOp', 'PoolOp', 'NormOp', 'AttentionOp',
--     'GeGLUOp', 'PatchOp', 'ResidualOp', 'BasicBlockOp', 'BottleneckOp') built
--     by the correctness-checked smart constructors ('mkConvLayer', ...). These
--     carry their real geometry in a 'LayerOp' spec and multi-tensor parameters
--     packed into the same flat @layerWeights@ / @layerBias@ vectors, so the
--     generic parameter/gradient flatten machinery is unchanged.
--
-- Every node's backward pass recomputes its forward internals from the stored
-- node input and parameters and applies the exact vector–Jacobian product, so
-- the forward tape needs no per-node state and gradients are deterministic for
-- a fixed seed and substrate.
module JitML.Numerics.LayerGraph
  ( TensorShape (..)
  , tensorShapeWidth
  , tensorShapeRank
  , LayerMode (..)
  , LayerActivation (..)
  , PoolKind (..)
  , NormKind (..)
  , LayerKind (..)
  , layerKindName
  , allLayerKinds

    -- * Operator geometry (Tier-2 specs)
  , ConvSpec (..)
  , SpatialShape (..)
  , PoolWindow (..)
  , PoolSpec (..)
  , NormFlavor (..)
  , NormSpec (..)
  , AttentionSpec (..)
  , GeGLUSpec (..)
  , AffineSpec (..)
  , Shortcut (..)
  , BlockStage (..)
  , BlockSpec (..)
  , PatchSpec (..)
  , LayerOp (..)
  , convOutDim

    -- * Parameters, nodes, graph
  , LayerParameters (..)
  , LayerNode (..)
  , LayerGraph (..)
  , LayerForward (..)
  , LayerGraphTape (..)
  , LayerParameterGradient (..)
  , LayerGradient (..)
  , LayerGraphGradient (..)

    -- * Deterministic initialisers
  , deterministicParameters
  , deterministicOpParameters
  , opWeightSegments
  , opBiasSegments

    -- * Smart constructors
  , mkAffineLayer
  , mkIdentityLayer
  , mkDropoutLayer
  , mkConvLayer
  , mkConv3DLayer
  , mkPoolLayer
  , mkNormLayer
  , mkAttentionLayer
  , mkGeGLULayer
  , mkPatchEmbedLayer
  , mkResidualNode
  , mkBasicBlock
  , mkBottleneck

    -- * Forward / backward
  , runLayerGraph
  , backwardLayerGraph
  , layerGraphSquaredErrorGradient
  , layerGraphLoss
  , graphParameterVector
  , replaceGraphParameterVector

    -- * Finite-difference oracles
  , maxFiniteDifferenceError
  , maxInputFiniteDifferenceError
  )
where

import Control.Monad (foldM, unless, when)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

-- ---------------------------------------------------------------------------
-- Shapes
-- ---------------------------------------------------------------------------

newtype TensorShape = TensorShape {unTensorShape :: [Int]}
  deriving stock (Eq, Show)

tensorShapeWidth :: TensorShape -> Either Text Int
tensorShapeWidth (TensorShape dims)
  | null dims = Left "TensorShape must have at least one dimension"
  | any (<= 0) dims = Left ("TensorShape dimensions must be positive: " <> Text.pack (show dims))
  | otherwise = Right (product dims)

tensorShapeRank :: TensorShape -> Int
tensorShapeRank = length . unTensorShape

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

-- | Serialization / identity tag for pooling and normalization families. Kept
-- stable across the Tier-2 enrichment so checkpoint metadata and oneDNN kind
-- tables continue to switch on it unchanged.
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

-- | Stable node identity tag. The real per-node geometry lives in 'LayerOp';
-- this enum remains the checkpoint-metadata / oneDNN switch key.
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

-- ---------------------------------------------------------------------------
-- Operator geometry (Tier-2 specs). Specs carry dimensions only; the parameter
-- tensor data lives in the node's packed 'LayerParameters'.
-- ---------------------------------------------------------------------------

-- | Dimension-general convolution spec, shared by 2D and 3D via the list
-- fields (2 or 3 spatial entries).
data ConvSpec = ConvSpec
  { convIn :: !Int
  , convOut :: !Int
  , convInputDims :: ![Int]
  , convKernelDims :: ![Int]
  , convStride :: ![Int]
  , convPadding :: ![Int]
  }
  deriving stock (Eq, Show)

data SpatialShape = SpatialShape
  { spC :: !Int
  , spH :: !Int
  , spW :: !Int
  }
  deriving stock (Eq, Show)

data PoolWindow = PoolWindow
  { pwKh :: !Int
  , pwKw :: !Int
  , pwSh :: !Int
  , pwSw :: !Int
  , pwPh :: !Int
  , pwPw :: !Int
  , pwCountPad :: !Bool
  }
  deriving stock (Eq, Show)

data PoolSpec
  = PoolMax !PoolWindow
  | PoolAvg !PoolWindow
  | PoolGlobal
  deriving stock (Eq, Show)

data NormFlavor
  = NormBatch
  | NormLayerWise
  | NormGroup !Int
  deriving stock (Eq, Show)

-- | Normalization spec. @nChannels@ is the per-channel affine width (gamma/beta
-- length); @nSpatial@ is the spatial extent per channel (1 for the dense case).
-- For 'NormBatch' the input is a flattened @batch x nChannels@ block; for
-- 'NormLayerWise' the input is one instance of @nChannels*nSpatial@ features;
-- for 'NormGroup' the input is channel-major @nChannels x nSpatial@.
data NormSpec = NormSpec
  { nFlavor :: !NormFlavor
  , nChannels :: !Int
  , nSpatial :: !Int
  , nEps :: !Double
  }
  deriving stock (Eq, Show)

data AttentionSpec = AttentionSpec
  { attnSeqLen :: !Int
  , attnEmbedDim :: !Int
  , attnNumHeads :: !Int
  , attnCausal :: !Bool
  }
  deriving stock (Eq, Show)

data GeGLUSpec = GeGLUSpec
  { ggIn :: !Int
  , ggFf :: !Int
  , ggOut :: !Int
  }
  deriving stock (Eq, Show)

-- | An affine map @W : [asOut, asIn]@ (row-major) plus bias @b : [asOut]@. Data
-- lives in the packed node parameters; this carries only the dimensions.
data AffineSpec = AffineSpec
  { asIn :: !Int
  , asOut :: !Int
  }
  deriving stock (Eq, Show)

data Shortcut
  = IdentityShortcut
  | ProjectionShortcut !AffineSpec
  deriving stock (Eq, Show)

-- | One block stage: an affine map, an optional normalization, and an
-- activation applied to the (optionally normalized) pre-activation.
data BlockStage = BlockStage
  { bsAffine :: !AffineSpec
  , bsNorm :: !(Maybe NormSpec)
  , bsAct :: !LayerActivation
  }
  deriving stock (Eq, Show)

data BlockSpec = BlockSpec
  { blStages :: ![BlockStage]
  , blShortcut :: !Shortcut
  , blScale :: !Double
  , blFinalAct :: !LayerActivation
  }
  deriving stock (Eq, Show)

-- | Non-overlapping (or overlapping) patch embedding spec. No learned
-- positional embedding in this tier; the projection + col2im are the verified
-- core.
data PatchSpec = PatchSpec
  { peC :: !Int
  , peH :: !Int
  , peW :: !Int
  , peP :: !Int
  , peStride :: !Int
  , peD :: !Int
  }
  deriving stock (Eq, Show)

-- | The verified operator geometry carried by every node. Tier-1 coarse nodes
-- use 'DenseOp' / 'IdentityOp' / 'DropoutOp'.
data LayerOp
  = DenseOp
  | IdentityOp
  | DropoutOp !Double
  | ConvOp !ConvSpec
  | PoolOp !SpatialShape !PoolSpec
  | NormOp !NormSpec
  | AttentionOp !AttentionSpec
  | GeGLUOp !GeGLUSpec
  | PatchOp !PatchSpec
  | ResidualOp !AffineSpec !Shortcut !Double !LayerActivation
  | BlockOp !BlockSpec
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Parameters, nodes, graph
-- ---------------------------------------------------------------------------

-- | Packed parameters. @layerWeights@ is the ordered concatenation of every
-- weight-like tensor (kernel, projection, gamma, ...); @layerBias@ is the
-- ordered concatenation of every bias-like tensor (bias, beta, ...). The
-- segment lengths are recovered from the node's 'LayerOp' via
-- 'opWeightSegments' / 'opBiasSegments', so the generic flatten machinery is
-- operator-agnostic.
data LayerParameters = LayerParameters
  { layerWeights :: !(Vector Double)
  , layerBias :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data LayerNode = LayerNode
  { layerNodeName :: !Text
  , layerNodeKind :: !LayerKind
  , layerNodeOp :: !LayerOp
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

-- ---------------------------------------------------------------------------
-- Parameter segment layout
-- ---------------------------------------------------------------------------

-- | Weight-tensor segment lengths (in canonical order) for an operator.
opWeightSegments :: LayerOp -> [Int]
opWeightSegments op =
  case op of
    DenseOp -> [] -- filled at construction: dense uses [in*out]
    IdentityOp -> []
    DropoutOp _ -> []
    ConvOp s -> [convOut s * convIn s * product (convKernelDims s)]
    PoolOp _ _ -> []
    NormOp s -> [nChannels s]
    AttentionOp s -> let d = attnEmbedDim s in replicate 4 (d * d)
    GeGLUOp s -> [ggFf s * ggIn s, ggFf s * ggIn s, ggOut s * ggFf s]
    PatchOp s -> [peD s * (peC s * peP s * peP s)]
    ResidualOp inner sc _ _ ->
      (asOut inner * asIn inner) : shortcutWeightSegs sc
    BlockOp b ->
      concatMap stageWeightSegs (blStages b) <> shortcutWeightSegs (blShortcut b)
 where
  stageWeightSegs st =
    (asOut (bsAffine st) * asIn (bsAffine st))
      : maybe [] (\n -> [nChannels n]) (bsNorm st)
  shortcutWeightSegs sc =
    case sc of
      IdentityShortcut -> []
      ProjectionShortcut a -> [asOut a * asIn a]

-- | Bias-tensor segment lengths (in canonical order) for an operator.
opBiasSegments :: LayerOp -> [Int]
opBiasSegments op =
  case op of
    DenseOp -> []
    IdentityOp -> []
    DropoutOp _ -> []
    ConvOp s -> [convOut s]
    PoolOp _ _ -> []
    NormOp s -> [nChannels s]
    AttentionOp s -> replicate 4 (attnEmbedDim s)
    GeGLUOp s -> [ggFf s, ggFf s, ggOut s]
    PatchOp s -> [peD s]
    ResidualOp inner sc _ _ -> asOut inner : shortcutBiasSegs sc
    BlockOp b ->
      concatMap stageBiasSegs (blStages b) <> shortcutBiasSegs (blShortcut b)
 where
  stageBiasSegs st =
    asOut (bsAffine st) : maybe [] (\n -> [nChannels n]) (bsNorm st)
  shortcutBiasSegs sc =
    case sc of
      IdentityShortcut -> []
      ProjectionShortcut a -> [asOut a]

-- | Split a flat vector into segments of the given lengths.
splitSegments :: [Int] -> Vector Double -> [Vector Double]
splitSegments = go 0
 where
  go _ [] _ = []
  go off (len : rest) v = VU.slice off len v : go (off + len) rest v

-- | Total destructuring of a known-length segment list (the segment count is
-- fixed by the operator spec, so the fallback is unreachable). Used instead of
-- a partial @let [a,b,c] = ...@ so the module compiles under @-Werror@.
split3 :: [a] -> (a, a, a)
split3 (a : b : c : _) = (a, b, c)
split3 _ = error "split3: expected at least 3 segments"

split4 :: [a] -> (a, a, a, a)
split4 (a : b : c : d : _) = (a, b, c, d)
split4 _ = error "split4: expected at least 4 segments"

-- ---------------------------------------------------------------------------
-- Deterministic initialisers
-- ---------------------------------------------------------------------------

-- | Dense affine parameters: @W : [outputWidth, inputWidth]@ Glorot-uniform,
-- zero bias. Retained signature for the Tier-1 / MLP path.
deterministicParameters :: Int -> Int -> Int -> LayerParameters
deterministicParameters seed inputWidth outputWidth =
  let limit = glorotLimit inputWidth outputWidth
      (weights, _gen) = drawUniform (inputWidth * outputWidth) limit (Random.mkStdGen seed)
   in LayerParameters
        { layerWeights = weights
        , layerBias = VU.replicate outputWidth 0.0
        }

glorotLimit :: Int -> Int -> Double
glorotLimit fanIn fanOut = sqrt (6.0 / fromIntegral (max 1 (fanIn + fanOut)))

-- | Deterministic parameters for any Tier-2 operator: each weight segment is
-- Glorot-uniform with a per-segment fan-in/out, biases and betas are zero,
-- gammas are ones. The packed layout matches 'opWeightSegments' /
-- 'opBiasSegments'.
deterministicOpParameters :: Int -> LayerOp -> LayerParameters
deterministicOpParameters seed op =
  LayerParameters
    { layerWeights = VU.concat weightTensors
    , layerBias = VU.concat biasTensors
    }
 where
  gen0 = Random.mkStdGen seed
  weightTensors = snd (List.mapAccumL drawWeight gen0 (weightPlan op))
  biasTensors = fmap biasTensor (biasPlan op)
  drawWeight g (len, fanIn, fanOut, isGamma)
    | isGamma = (g, VU.replicate len 1.0)
    | otherwise =
        let (v, g') = drawUniform len (glorotLimit fanIn fanOut) g
         in (g', v)
  biasTensor len = VU.replicate len 0.0

-- | (segment length, fanIn, fanOut, isGamma) per weight tensor.
weightPlan :: LayerOp -> [(Int, Int, Int, Bool)]
weightPlan op =
  case op of
    ConvOp s ->
      let fanK = convIn s * product (convKernelDims s)
       in [(convOut s * fanK, fanK, convOut s * product (convKernelDims s), False)]
    NormOp s -> [(nChannels s, 0, 0, True)]
    AttentionOp s ->
      let d = attnEmbedDim s in replicate 4 (d * d, d, d, False)
    GeGLUOp s ->
      [ (ggFf s * ggIn s, ggIn s, ggFf s, False)
      , (ggFf s * ggIn s, ggIn s, ggFf s, False)
      , (ggOut s * ggFf s, ggFf s, ggOut s, False)
      ]
    PatchOp s ->
      let cpp = peC s * peP s * peP s in [(peD s * cpp, cpp, peD s, False)]
    ResidualOp inner sc _ _ ->
      (asOut inner * asIn inner, asIn inner, asOut inner, False) : shortcutWeightPlan sc
    BlockOp b ->
      concatMap stageWeightPlan (blStages b) <> shortcutWeightPlan (blShortcut b)
    _ -> []
 where
  stageWeightPlan st =
    let a = bsAffine st
     in (asOut a * asIn a, asIn a, asOut a, False)
          : maybe [] (\n -> [(nChannels n, 0, 0, True)]) (bsNorm st)
  shortcutWeightPlan sc =
    case sc of
      IdentityShortcut -> []
      ProjectionShortcut a -> [(asOut a * asIn a, asIn a, asOut a, False)]

biasPlan :: LayerOp -> [Int]
biasPlan = opBiasSegments

-- ---------------------------------------------------------------------------
-- Smart constructors
-- ---------------------------------------------------------------------------

validatePositive :: Text -> Int -> Either Text ()
validatePositive label value
  | value > 0 = Right ()
  | otherwise = Left (label <> " must be positive, got " <> Text.pack (show value))

nodeWith
  :: Text
  -> LayerKind
  -> LayerOp
  -> TensorShape
  -> TensorShape
  -> LayerMode
  -> LayerActivation
  -> Maybe LayerParameters
  -> LayerNode
nodeWith name kind op inShape outShape mode act params =
  LayerNode
    { layerNodeName = name
    , layerNodeKind = kind
    , layerNodeOp = op
    , layerInputShape = inShape
    , layerOutputShape = outShape
    , layerMode = mode
    , layerActivation = act
    , layerParameters = params
    }

-- | Validate that packed parameters match an operator's segment layout.
checkParams :: Text -> LayerOp -> LayerParameters -> Either Text ()
checkParams name op params = do
  let wExpected = sum (opWeightSegments op)
      bExpected = sum (opBiasSegments op)
  when (VU.length (layerWeights params) /= wExpected) $
    Left
      ( name
          <> " expected "
          <> tshow wExpected
          <> " weights, got "
          <> tshow (VU.length (layerWeights params))
      )
  when (VU.length (layerBias params) /= bExpected) $
    Left
      ( name
          <> " expected "
          <> tshow bExpected
          <> " bias values, got "
          <> tshow (VU.length (layerBias params))
      )

-- | Tier-1 dense affine node. The @kind@ tag is stored for serialization
-- identity; the executed operator is always a plain affine ('DenseOp').
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
          <> tshow expectedWeights
          <> " weights, got "
          <> tshow (VU.length (layerWeights params))
      )
  when (VU.length (layerBias params) /= outputWidth) $
    Left
      ( name
          <> " expected "
          <> tshow outputWidth
          <> " bias values, got "
          <> tshow (VU.length (layerBias params))
      )
  pure
    ( nodeWith
        name
        kind
        DenseOp
        (TensorShape [inputWidth])
        (TensorShape [outputWidth])
        mode
        activation
        (Just params)
    )

-- | Tier-1 parameterless identity passthrough.
mkIdentityLayer :: Text -> LayerKind -> Int -> LayerMode -> Either Text LayerNode
mkIdentityLayer name kind width mode = do
  validatePositive "width" width
  pure
    ( nodeWith
        name
        kind
        IdentityOp
        (TensorShape [width])
        (TensorShape [width])
        mode
        LinearActivation
        Nothing
    )

-- | Tier-1 dropout: scales by @1 - rate@ in training, identity in inference.
mkDropoutLayer :: Text -> Double -> Int -> LayerMode -> Either Text LayerNode
mkDropoutLayer name rate width mode = do
  validatePositive "width" width
  pure
    ( nodeWith
        name
        (DropoutLayer rate)
        (DropoutOp rate)
        (TensorShape [width])
        (TensorShape [width])
        mode
        LinearActivation
        Nothing
    )

convOutDim :: Int -> Int -> Int -> Int -> Int
convOutDim n k st pd = (n + 2 * pd - k) `div` st + 1

-- | 2-D convolution node. Input laid out row-major @[C_in, H, W]@; kernel
-- @[C_out, C_in, Kh, Kw]@; bias @[C_out]@; output @[C_out, H_out, W_out]@.
mkConvLayer
  :: Text -> ConvSpec -> LayerActivation -> LayerMode -> LayerParameters -> Either Text LayerNode
mkConvLayer name = mkConvGeneric name Conv2DLayer 2

-- | 3-D convolution node. Input @[C_in, D, H, W]@; kernel @[C_out, C_in, Kd, Kh, Kw]@.
mkConv3DLayer
  :: Text -> ConvSpec -> LayerActivation -> LayerMode -> LayerParameters -> Either Text LayerNode
mkConv3DLayer name = mkConvGeneric name Conv3DLayer 3

mkConvGeneric
  :: Text
  -> LayerKind
  -> Int
  -> ConvSpec
  -> LayerActivation
  -> LayerMode
  -> LayerParameters
  -> Either Text LayerNode
mkConvGeneric name kind nd spec activation mode params = do
  unless (length (convInputDims spec) == nd) $
    Left (name <> ": convInputDims must have " <> tshow nd <> " entries")
  unless (length (convKernelDims spec) == nd) $
    Left (name <> ": convKernelDims must have " <> tshow nd <> " entries")
  unless (length (convStride spec) == nd) $
    Left (name <> ": convStride must have " <> tshow nd <> " entries")
  unless (length (convPadding spec) == nd) $
    Left (name <> ": convPadding must have " <> tshow nd <> " entries")
  validatePositive "convIn" (convIn spec)
  validatePositive "convOut" (convOut spec)
  let op = ConvOp spec
      outDims =
        zipWith4' convOutDim (convInputDims spec) (convKernelDims spec) (convStride spec) (convPadding spec)
  unless (all (> 0) outDims) $
    Left (name <> ": convolution output dimensions must be positive: " <> tshow outDims)
  checkParams name op params
  pure
    ( nodeWith
        name
        kind
        op
        (TensorShape (convIn spec : convInputDims spec))
        (TensorShape (convOut spec : outDims))
        mode
        activation
        (Just params)
    )

-- | Pooling node (Max / Avg / GlobalAvg). Parameterless.
mkPoolLayer :: Text -> SpatialShape -> PoolSpec -> LayerMode -> Either Text LayerNode
mkPoolLayer name sp poolSpec mode = do
  validatePositive "channels" (spC sp)
  validatePositive "height" (spH sp)
  validatePositive "width" (spW sp)
  (kind, outShape) <-
    case poolSpec of
      PoolGlobal -> Right (PoolLayer GlobalAvgPool, TensorShape [spC sp])
      PoolMax win -> poolShape MaxPool win
      PoolAvg win -> poolShape AvgPool win
  pure
    ( nodeWith
        name
        kind
        (PoolOp sp poolSpec)
        (TensorShape [spC sp, spH sp, spW sp])
        outShape
        mode
        LinearActivation
        Nothing
    )
 where
  poolShape pk win =
    let hO = convOutDim (spH sp) (pwKh win) (pwSh win) (pwPh win)
        wO = convOutDim (spW sp) (pwKw win) (pwSw win) (pwPw win)
     in if hO > 0 && wO > 0
          then Right (PoolLayer pk, TensorShape [spC sp, hO, wO])
          else Left (name <> ": pooling output must be positive")

-- | Normalization node (Batch / Layer / Group). gamma/beta per channel.
mkNormLayer :: Text -> NormSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkNormLayer name spec mode params = do
  validatePositive "nChannels" (nChannels spec)
  validatePositive "nSpatial" (nSpatial spec)
  case nFlavor spec of
    NormGroup g -> do
      validatePositive "groups" g
      when (nChannels spec `mod` g /= 0) $
        Left (name <> ": channels " <> tshow (nChannels spec) <> " not divisible by groups " <> tshow g)
    _ -> Right ()
  let kind = normKindOf spec
      op = NormOp spec
      -- For 'NormBatch', @nSpatial@ is the batch size, so the flat width is
      -- @batch * channels@ (sample-major); for Layer/Group it is the spatial
      -- extent per channel.
      width = nChannels spec * nSpatial spec
  checkParams name op params
  pure
    ( nodeWith
        name
        kind
        op
        (TensorShape [width])
        (TensorShape [width])
        mode
        LinearActivation
        (Just params)
    )

normKindOf :: NormSpec -> LayerKind
normKindOf spec =
  case nFlavor spec of
    NormBatch -> NormLayer BatchNorm
    NormLayerWise -> NormLayer LayerNorm
    NormGroup g -> NormLayer (GroupNorm g)

-- | Multi-head self-attention node with residual add. Input/output width
-- @seqLen * embedDim@.
mkAttentionLayer :: Text -> AttentionSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkAttentionLayer name spec mode params = do
  validatePositive "attnSeqLen" (attnSeqLen spec)
  validatePositive "attnEmbedDim" (attnEmbedDim spec)
  validatePositive "attnNumHeads" (attnNumHeads spec)
  when (attnEmbedDim spec `mod` attnNumHeads spec /= 0) $
    Left
      ( name
          <> ": embedDim "
          <> tshow (attnEmbedDim spec)
          <> " not divisible by heads "
          <> tshow (attnNumHeads spec)
      )
  let op = AttentionOp spec
      width = attnSeqLen spec * attnEmbedDim spec
  checkParams name op params
  pure
    ( nodeWith
        name
        (MultiHeadAttentionLayer (attnNumHeads spec))
        op
        (TensorShape [width])
        (TensorShape [width])
        mode
        LinearActivation
        (Just params)
    )

-- | GeGLU feed-forward node @y = W2 (a ⊙ GELU(g)) + b2@.
mkGeGLULayer :: Text -> GeGLUSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkGeGLULayer name spec mode params = do
  validatePositive "ggIn" (ggIn spec)
  validatePositive "ggFf" (ggFf spec)
  validatePositive "ggOut" (ggOut spec)
  let op = GeGLUOp spec
  checkParams name op params
  pure
    ( nodeWith
        name
        GeGLULayer
        op
        (TensorShape [ggIn spec])
        (TensorShape [ggOut spec])
        mode
        LinearActivation
        (Just params)
    )

-- | Patch-embedding node: non-overlapping (or overlapping) patchify + shared
-- projection. Input @[C, H, W]@ pixel-row-major; output @[N, d]@ flattened.
mkPatchEmbedLayer :: Text -> PatchSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkPatchEmbedLayer name spec mode params = do
  validatePositive "peC" (peC spec)
  validatePositive "peH" (peH spec)
  validatePositive "peW" (peW spec)
  validatePositive "peP" (peP spec)
  validatePositive "peStride" (peStride spec)
  validatePositive "peD" (peD spec)
  let positions = patchPositions spec
      n = length positions
  when (n <= 0) $ Left (name <> ": patch grid is empty")
  let op = PatchOp spec
  checkParams name op params
  pure
    ( nodeWith
        name
        PatchEmbedLayer
        op
        (TensorShape [peC spec, peH spec, peW spec])
        (TensorShape [n, peD spec])
        mode
        LinearActivation
        (Just params)
    )

-- | Residual node @y = φ_out(shortcut(x) + s·φ(Wx+b))@.
mkResidualNode
  :: Text
  -> AffineSpec
  -> Shortcut
  -> Double
  -> LayerActivation
  -> LayerActivation
  -> LayerMode
  -> LayerParameters
  -> Either Text LayerNode
mkResidualNode name inner shortcut scale innerAct finalAct mode params = do
  validatePositive "asIn" (asIn inner)
  validatePositive "asOut" (asOut inner)
  dOut <- residualOutWidth name inner shortcut
  let op = ResidualOp inner shortcut scale innerAct
  checkParams name op params
  pure
    ( nodeWith
        name
        (ResidualLayer scale)
        op
        (TensorShape [asIn inner])
        (TensorShape [dOut])
        mode
        finalAct
        (Just params)
    )

residualOutWidth :: Text -> AffineSpec -> Shortcut -> Either Text Int
residualOutWidth name inner shortcut =
  case shortcut of
    IdentityShortcut ->
      if asIn inner == asOut inner
        then Right (asOut inner)
        else
          Left
            ( name
                <> ": identity shortcut requires d_in==d_out (got "
                <> tshow (asIn inner)
                <> ", "
                <> tshow (asOut inner)
                <> "); attach a projection shortcut"
            )
    ProjectionShortcut proj ->
      if asOut proj == asOut inner && asIn proj == asIn inner
        then Right (asOut inner)
        else
          Left
            ( name
                <> ": projection shortcut shape must match inner (in "
                <> tshow (asIn inner)
                <> ", out "
                <> tshow (asOut inner)
                <> ")"
            )

-- | Basic residual block (two affine→norm stages with a skip).
mkBasicBlock :: Text -> BlockSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkBasicBlock = mkBlockNode BasicBlockLayer

-- | Bottleneck residual block (three affine→norm stages with a reduced middle).
mkBottleneck :: Text -> BlockSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkBottleneck = mkBlockNode BottleneckBlockLayer

mkBlockNode
  :: (Double -> LayerKind) -> Text -> BlockSpec -> LayerMode -> LayerParameters -> Either Text LayerNode
mkBlockNode mkKind name spec mode params = do
  when (null (blStages spec)) $ Left (name <> ": block must have at least one stage")
  dIn <- case blStages spec of
    (st : _) -> Right (asIn (bsAffine st))
    [] -> Left (name <> ": empty block")
  dOut <- blockOutWidth name spec
  validateStageComposition name (blStages spec)
  let op = BlockOp spec
  checkParams name op params
  pure
    ( nodeWith
        name
        (mkKind (blScale spec))
        op
        (TensorShape [dIn])
        (TensorShape [dOut])
        mode
        (blFinalAct spec)
        (Just params)
    )

blockOutWidth :: Text -> BlockSpec -> Either Text Int
blockOutWidth name spec = do
  (firstStage, lastStage) <- case (blStages spec, reverse (blStages spec)) of
    (f : _, l : _) -> Right (f, l)
    _ -> Left (name <> ": block must have at least one stage")
  let dIn = asIn (bsAffine firstStage)
      dOut = asOut (bsAffine lastStage)
  case blShortcut spec of
    IdentityShortcut ->
      if dIn == dOut
        then Right dOut
        else
          Left
            (name <> ": identity shortcut requires d_in==d_out (got " <> tshow dIn <> ", " <> tshow dOut <> ")")
    ProjectionShortcut proj ->
      if asOut proj == dOut && asIn proj == dIn
        then Right dOut
        else
          Left
            ( name
                <> ": projection shortcut shape must match block (in "
                <> tshow dIn
                <> ", out "
                <> tshow dOut
                <> ")"
            )

validateStageComposition :: Text -> [BlockStage] -> Either Text ()
validateStageComposition name = go
 where
  go (a : rest@(b : _)) = checkPair a b >> go rest
  go _ = Right ()
  checkPair a b =
    when (asOut (bsAffine a) /= asIn (bsAffine b)) $
      Left
        ( name
            <> ": stage output "
            <> tshow (asOut (bsAffine a))
            <> " does not compose with next stage input "
            <> tshow (asIn (bsAffine b))
        )

-- ---------------------------------------------------------------------------
-- Forward / backward — graph fold
-- ---------------------------------------------------------------------------

runLayerGraph :: LayerGraph -> Vector Double -> Either Text LayerGraphTape
runLayerGraph graph input = do
  inputWidth <- tensorShapeWidth (layerGraphInputShape graph)
  expectedOutputWidth <- tensorShapeWidth (layerGraphOutputShape graph)
  unless (VU.length input == inputWidth) $
    Left
      ( layerGraphName graph
          <> " expected input width "
          <> tshow inputWidth
          <> ", got "
          <> tshow (VU.length input)
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
          <> tshow (VU.length output)
          <> ", expected "
          <> tshow expectedOutputWidth
      )
  pure
    ( LayerGraphTape
        { layerTapeInput = input
        , layerTapeOutput = output
        , layerTapeLayers = reverse forwards
        }
    )

backwardLayerGraph
  :: LayerGraph -> LayerGraphTape -> Vector Double -> Either Text LayerGraphGradient
backwardLayerGraph graph tape upstream = do
  outputWidth <- tensorShapeWidth (layerGraphOutputShape graph)
  unless (VU.length upstream == outputWidth) $
    Left
      ( layerGraphName graph
          <> " expected output gradient width "
          <> tshow outputWidth
          <> ", got "
          <> tshow (VU.length upstream)
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
    (LayerGraphGradient {layerGraphInputGradient = inputGradient, layerGraphLayerGradients = gradients})

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

-- ---------------------------------------------------------------------------
-- Parameter flatten machinery (operator-agnostic)
-- ---------------------------------------------------------------------------

graphParameterVector :: LayerGraph -> Vector Double
graphParameterVector = VU.concat . fmap nodeParams . layerGraphNodes
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
          <> tshow consumed
          <> " values, got "
          <> tshow (VU.length flat)
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
                      ( node {layerParameters = Just LayerParameters {layerWeights = weights, layerBias = bias}}
                      , offset + total
                      )

flattenLayerGraphGradient :: LayerGraphGradient -> Vector Double
flattenLayerGraphGradient = VU.concat . fmap layerParams . layerGraphLayerGradients
 where
  layerParams gradient =
    case layerGradientParameters gradient of
      Nothing -> VU.empty
      Just params -> VU.concat [layerGradWeights params, layerGradBias params]

-- ---------------------------------------------------------------------------
-- Per-node forward
-- ---------------------------------------------------------------------------

runLayerNode :: LayerNode -> Vector Double -> Either Text LayerForward
runLayerNode node input = do
  inputWidth <- tensorShapeWidth (layerInputShape node)
  unless (VU.length input == inputWidth) $
    Left
      ( layerNodeName node
          <> " expected input width "
          <> tshow inputWidth
          <> ", got "
          <> tshow (VU.length input)
      )
  (preActivation, output) <- forwardOp node input
  pure
    ( LayerForward
        { layerForwardNode = node
        , layerForwardInput = input
        , layerForwardPreActivation = preActivation
        , layerForwardOutput = output
        }
    )

-- | Returns (pre-activation, output). Most ops apply the node activation
-- elementwise to a pre-activation; blocks/residual/attention build the output
-- internally and report it as both.
forwardOp :: LayerNode -> Vector Double -> Either Text (Vector Double, Vector Double)
forwardOp node input =
  case layerNodeOp node of
    IdentityOp -> Right (input, input)
    DropoutOp rate ->
      let out = VU.map (* dropoutScale (layerMode node) rate) input in Right (out, out)
    DenseOp -> do
      params <- requireParams node
      pre <- affinePreActivation params input =<< tensorShapeWidth (layerOutputShape node)
      Right (pre, applyActivation (layerActivation node) pre)
    ConvOp spec -> do
      params <- requireParams node
      let pre = convForward spec params input
      Right (pre, applyActivation (layerActivation node) pre)
    PoolOp sp poolSpec -> Right (poolForward sp poolSpec input, poolForward sp poolSpec input)
    NormOp spec -> do
      params <- requireParams node
      let (y, _, _) = normForward spec params input
      Right (y, y)
    AttentionOp spec -> do
      params <- requireParams node
      let y = attentionForward spec params input
      Right (y, y)
    GeGLUOp spec -> do
      params <- requireParams node
      let (y, _) = gegluForward spec params input
      Right (y, y)
    PatchOp spec -> do
      params <- requireParams node
      let y = patchForward spec params input
      Right (y, y)
    ResidualOp inner shortcut scale innerAct -> do
      params <- requireParams node
      (y, _) <- residualForward inner shortcut scale innerAct (layerActivation node) params input
      Right (y, y)
    BlockOp spec -> do
      params <- requireParams node
      (y, _) <- blockForward spec params input
      Right (y, y)

requireParams :: LayerNode -> Either Text LayerParameters
requireParams node =
  case layerParameters node of
    Just p -> Right p
    Nothing -> Left (layerNodeName node <> " requires parameters")

dropoutScale :: LayerMode -> Double -> Double
dropoutScale mode rate =
  case mode of
    TrainingMode -> 1.0 - clampDouble 0.0 0.95 rate
    InferenceMode -> 1.0

-- ---------------------------------------------------------------------------
-- Per-node backward
-- ---------------------------------------------------------------------------

backwardLayerNode :: LayerForward -> Vector Double -> Either Text (Vector Double, LayerGradient)
backwardLayerNode forward upstream = do
  outputWidth <- tensorShapeWidth (layerOutputShape node)
  unless (VU.length upstream == outputWidth) $
    Left (layerNodeName node <> " upstream gradient width mismatch")
  (inputGrad, paramGrad) <- backwardOp node (layerForwardInput forward) upstream
  pure
    ( inputGrad
    , LayerGradient
        { layerGradientName = layerNodeName node
        , layerGradientInput = inputGrad
        , layerGradientParameters = paramGrad
        }
    )
 where
  node = layerForwardNode forward

-- | Returns (input gradient, optional parameter gradient).
backwardOp
  :: LayerNode
  -> Vector Double
  -> Vector Double
  -> Either Text (Vector Double, Maybe LayerParameterGradient)
backwardOp node input upstream =
  case layerNodeOp node of
    IdentityOp -> Right (upstream, Nothing)
    DropoutOp rate -> Right (VU.map (* dropoutScale (layerMode node) rate) upstream, Nothing)
    DenseOp -> do
      params <- requireParams node
      outputWidth <- tensorShapeWidth (layerOutputShape node)
      pre <- affinePreActivation params input outputWidth
      let dPre = activationBackward (layerActivation node) (applyActivation (layerActivation node) pre) upstream
          dW = outerProduct dPre input
          dX = matVecTransposed (layerWeights params) (VU.length dPre) (VU.length input) dPre
      Right (dX, Just (LayerParameterGradient dW dPre))
    ConvOp spec -> do
      params <- requireParams node
      let pre = convForward spec params input
          dPre = activationBackward (layerActivation node) (applyActivation (layerActivation node) pre) upstream
          (dX, pg) = convBackward spec params input dPre
      Right (dX, Just pg)
    PoolOp sp poolSpec -> Right (poolBackward sp poolSpec input upstream, Nothing)
    NormOp spec -> do
      params <- requireParams node
      let (dX, pg) = normBackward spec params input upstream
      Right (dX, Just pg)
    AttentionOp spec -> do
      params <- requireParams node
      let (dX, pg) = attentionBackward spec params input upstream
      Right (dX, Just pg)
    GeGLUOp spec -> do
      params <- requireParams node
      let (dX, pg) = gegluBackward spec params input upstream
      Right (dX, Just pg)
    PatchOp spec -> do
      params <- requireParams node
      let (dX, pg) = patchBackward spec params input upstream
      Right (dX, Just pg)
    ResidualOp inner shortcut scale innerAct -> do
      params <- requireParams node
      (dX, pg) <-
        residualBackward inner shortcut scale innerAct (layerActivation node) params input upstream
      Right (dX, Just pg)
    BlockOp spec -> do
      params <- requireParams node
      (dX, pg) <- blockBackward spec params input upstream
      Right (dX, Just pg)

-- ---------------------------------------------------------------------------
-- Affine primitives
-- ---------------------------------------------------------------------------

affinePreActivation :: LayerParameters -> Vector Double -> Int -> Either Text (Vector Double)
affinePreActivation params input outputWidth = do
  let inputWidth = VU.length input
      expected = inputWidth * outputWidth
  unless (VU.length (layerWeights params) == expected) $
    Left "affinePreActivation: weight length does not match input/output width"
  unless (VU.length (layerBias params) == outputWidth) $
    Left "affinePreActivation: bias length does not match output width"
  pure (VU.zipWith (+) (matVec (layerWeights params) outputWidth inputWidth input) (layerBias params))

-- | Pure affine: y = W x + b, W row-major [out,in].
affFwd :: Vector Double -> Vector Double -> AffineSpec -> Vector Double -> Vector Double
affFwd w b spec x = VU.zipWith (+) (matVec w (asOut spec) (asIn spec) x) b

-- | Returns (dInput, dW, dB) for y = W x + b.
affBwd
  :: Vector Double
  -> AffineSpec
  -> Vector Double
  -> Vector Double
  -> (Vector Double, Vector Double, Vector Double)
affBwd w spec x dz =
  ( matVecTransposed w (asOut spec) (asIn spec) dz
  , outerProduct dz x
  , dz
  )

-- ---------------------------------------------------------------------------
-- Convolution (2D/3D via one N-D path)
-- ---------------------------------------------------------------------------

convForward :: ConvSpec -> LayerParameters -> Vector Double -> Vector Double
convForward spec params x =
  VU.generate (cO * outVol) $ \o ->
    let (co, r) = o `quotRem` outVol
        outCoord = unflatten outDims r
     in (layerBias params VU.! co)
          + sum
            [ layerWeights params VU.! kIdx co ci kc
                * xAt ci (zipWith3' (\oc kk (st, pd) -> oc * st + kk - pd) outCoord kc (zip strides paddings))
            | ci <- [0 .. cI - 1]
            , kc <- kernelCoords
            ]
 where
  cO = convOut spec
  cI = convIn spec
  inDims = convInputDims spec
  kDims = convKernelDims spec
  strides = convStride spec
  paddings = convPadding spec
  outDims = zipWith4' convOutDim inDims kDims strides paddings
  outVol = product outDims
  kVol = product kDims
  kernelCoords = enumerateCoords kDims
  inVol = product inDims
  xAt ci coord
    | inBounds inDims coord = x VU.! (ci * inVol + flatten inDims coord)
    | otherwise = 0.0
  kIdx co ci kc = ((co * cI + ci) * kVol) + flatten kDims kc

convBackward
  :: ConvSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> (Vector Double, LayerParameterGradient)
convBackward spec params x dY = (dX, LayerParameterGradient dW db)
 where
  cO = convOut spec
  cI = convIn spec
  inDims = convInputDims spec
  kDims = convKernelDims spec
  strides = convStride spec
  paddings = convPadding spec
  outDims = zipWith4' convOutDim inDims kDims strides paddings
  outVol = product outDims
  kVol = product kDims
  inVol = product inDims
  kernelCoords = enumerateCoords kDims
  outCoords = enumerateCoords outDims
  yIdx co r = co * outVol + r
  inCoordFor outCoord kc = zipWith3' (\oc kk (st, pd) -> oc * st + kk - pd) outCoord kc (zip strides paddings)
  xAt ci coord
    | inBounds inDims coord = x VU.! (ci * inVol + flatten inDims coord)
    | otherwise = 0.0
  dW =
    VU.generate (cO * cI * kVol) $ \ix ->
      let (r2, kFlat) = ix `quotRem` kVol
          (co, ci) = r2 `quotRem` cI
          kc = unflatten kDims kFlat
       in sum
            [ dY VU.! yIdx co (flatten outDims outCoord) * xAt ci (inCoordFor outCoord kc)
            | outCoord <- outCoords
            ]
  db =
    VU.generate cO $ \co ->
      sum [dY VU.! yIdx co r | r <- [0 .. outVol - 1]]
  dX =
    VU.accum
      (+)
      (VU.replicate (cI * inVol) 0.0)
      [ ( ci * inVol + flatten inDims inCoord
        , layerWeights params VU.! (((co * cI + ci) * kVol) + flatten kDims kc)
            * dY VU.! yIdx co (flatten outDims outCoord)
        )
      | co <- [0 .. cO - 1]
      , ci <- [0 .. cI - 1]
      , outCoord <- outCoords
      , kc <- kernelCoords
      , let inCoord = inCoordFor outCoord kc
      , inBounds inDims inCoord
      ]

-- ---------------------------------------------------------------------------
-- Pooling
-- ---------------------------------------------------------------------------

poolForward :: SpatialShape -> PoolSpec -> Vector Double -> Vector Double
poolForward sp poolSpec x =
  case poolSpec of
    PoolGlobal -> globalAvgPoolForward sp x
    PoolMax win -> fst (maxPoolForward sp win x)
    PoolAvg win -> avgPoolForward sp win x

poolBackward :: SpatialShape -> PoolSpec -> Vector Double -> Vector Double -> Vector Double
poolBackward sp poolSpec x upstream =
  case poolSpec of
    PoolGlobal -> globalAvgPoolBackward sp upstream
    PoolMax win -> maxPoolBackward (spC sp * spH sp * spW sp) (snd (maxPoolForward sp win x)) upstream
    PoolAvg win -> avgPoolBackward sp win (spC sp * spH sp * spW sp) upstream

poolFlatIdx :: SpatialShape -> Int -> Int -> Int -> Int
poolFlatIdx sp c h w = (c * spH sp + h) * spW sp + w

poolOutHW :: SpatialShape -> PoolWindow -> (Int, Int)
poolOutHW sp win =
  ( convOutDim (spH sp) (pwKh win) (pwSh win) (pwPh win)
  , convOutDim (spW sp) (pwKw win) (pwSw win) (pwPw win)
  )

windowMembers :: SpatialShape -> PoolWindow -> Int -> Int -> [(Int, Int)]
windowMembers sp win i j =
  [ (r, s)
  | a <- [0 .. pwKh win - 1]
  , let r = i * pwSh win - pwPh win + a
  , r >= 0
  , r < spH sp
  , b <- [0 .. pwKw win - 1]
  , let s = j * pwSw win - pwPw win + b
  , s >= 0
  , s < spW sp
  ]

poolCells :: SpatialShape -> Int -> Int -> [(Int, Int, Int)]
poolCells sp hO wO = [(c, i, j) | c <- [0 .. spC sp - 1], i <- [0 .. hO - 1], j <- [0 .. wO - 1]]

maxPoolForward :: SpatialShape -> PoolWindow -> Vector Double -> (Vector Double, Vector Int)
maxPoolForward sp win x =
  let (hO, wO) = poolOutHW sp win
      pick (c, i, j) =
        let ks = [poolFlatIdx sp c r s | (r, s) <- windowMembers sp win i j]
         in case ks of
              [] -> (0, 0.0)
              (k0 : rest) ->
                List.foldl'
                  (\(bk, bv) k -> let v = x VU.! k in if v > bv then (k, v) else (bk, bv))
                  (k0, x VU.! k0)
                  rest
      ps = map pick (poolCells sp hO wO)
   in (VU.fromList (map snd ps), VU.fromList (map fst ps))

maxPoolBackward :: Int -> Vector Int -> Vector Double -> Vector Double
maxPoolBackward inLen argmax dY = VU.accumulate (+) (VU.replicate inLen 0.0) (VU.zip argmax dY)

avgDivisor :: PoolWindow -> [(Int, Int)] -> Double
avgDivisor win members =
  if pwCountPad win then fromIntegral (pwKh win * pwKw win) else fromIntegral (length members)

avgPoolForward :: SpatialShape -> PoolWindow -> Vector Double -> Vector Double
avgPoolForward sp win x =
  let (hO, wO) = poolOutHW sp win
   in VU.fromList
        [ let ms = windowMembers sp win i j
           in sum [x VU.! poolFlatIdx sp c r s | (r, s) <- ms] / avgDivisor win ms
        | (c, i, j) <- poolCells sp hO wO
        ]

avgPoolBackward :: SpatialShape -> PoolWindow -> Int -> Vector Double -> Vector Double
avgPoolBackward sp win inLen dY =
  let (hO, wO) = poolOutHW sp win
      contribs =
        [ (poolFlatIdx sp c r s, (dY VU.! o) / avgDivisor win ms)
        | (o, (c, i, j)) <- zip [0 ..] (poolCells sp hO wO)
        , let ms = windowMembers sp win i j
        , (r, s) <- ms
        ]
   in VU.accum (+) (VU.replicate inLen 0.0) contribs

globalAvgPoolForward :: SpatialShape -> Vector Double -> Vector Double
globalAvgPoolForward sp x =
  let area = spH sp * spW sp
   in VU.generate (spC sp) $ \c ->
        sum [x VU.! poolFlatIdx sp c h w | h <- [0 .. spH sp - 1], w <- [0 .. spW sp - 1]]
          / fromIntegral area

globalAvgPoolBackward :: SpatialShape -> Vector Double -> Vector Double
globalAvgPoolBackward sp dY =
  let area = spH sp * spW sp
   in VU.generate (spC sp * area) $ \k -> (dY VU.! (k `div` area)) / fromIntegral area

-- ---------------------------------------------------------------------------
-- Normalization
-- ---------------------------------------------------------------------------

-- | Group index sets for a normalization spec applied to a flat vector.
normGroupIndices :: NormSpec -> Int -> [[Int]]
normGroupIndices spec len =
  case nFlavor spec of
    NormLayerWise -> [[0 .. len - 1]]
    NormGroup g ->
      let gsz = nChannels spec `div` g
          spatial = nSpatial spec
       in [[i | i <- [0 .. len - 1], ((i `div` spatial) `div` gsz) == k] | k <- [0 .. g - 1]]
    NormBatch ->
      -- input is batch x channels (sample-major); each feature reduces over the batch
      let c = nChannels spec
       in [[i | i <- [0 .. len - 1], (i `mod` c) == k] | k <- [0 .. c - 1]]

-- | Per-element channel index (for gamma/beta lookup).
normChannelOf :: NormSpec -> Int -> Int
normChannelOf spec i =
  case nFlavor spec of
    NormBatch -> i `mod` nChannels spec
    _ -> i `div` nSpatial spec

normForward
  :: NormSpec -> LayerParameters -> Vector Double -> (Vector Double, Vector Double, [(Double, Double)])
normForward spec params x =
  let gamma = layerWeights params
      beta = layerBias params
      groups = normGroupIndices spec (VU.length x)
      stats =
        [ let m = fromIntegral (length idxs)
              mu = sum [x VU.! i | i <- idxs] / m
              var = sum [let { d = (x VU.! i) - mu } in d * d | i <- idxs] / m
           in (mu, 1.0 / sqrt (var + nEps spec))
        | idxs <- groups
        ]
      groupOf = groupLookup groups (VU.length x)
      xhat =
        VU.generate (VU.length x) $ \i ->
          let (mu, r) = stats !! (groupOf VU.! i)
           in ((x VU.! i) - mu) * r
      y =
        VU.generate (VU.length x) $ \i ->
          gamma VU.! normChannelOf spec i * (xhat VU.! i) + beta VU.! normChannelOf spec i
   in (y, xhat, stats)

normBackward
  :: NormSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> (Vector Double, LayerParameterGradient)
normBackward spec params x dy =
  let gamma = layerWeights params
      (_, xhat, stats) = normForward spec params x
      groups = normGroupIndices spec (VU.length x)
      groupOf = groupLookup groups (VU.length x)
      ghat = VU.generate (VU.length x) $ \i -> (dy VU.! i) * gamma VU.! normChannelOf spec i
      groupMeans =
        [ let m = fromIntegral (length idxs)
              meanG = sum [ghat VU.! i | i <- idxs] / m
              meanGX = sum [ghat VU.! i * xhat VU.! i | i <- idxs] / m
           in (meanG, meanGX)
        | idxs <- groups
        ]
      dx =
        VU.generate (VU.length x) $ \i ->
          let k = groupOf VU.! i
              (_, r) = stats !! k
              (meanG, meanGX) = groupMeans !! k
           in r * (ghat VU.! i - meanG - xhat VU.! i * meanGX)
      dGamma =
        VU.generate (nChannels spec) $ \c ->
          sum [dy VU.! i * xhat VU.! i | i <- [0 .. VU.length x - 1], normChannelOf spec i == c]
      dBeta =
        VU.generate (nChannels spec) $ \c ->
          sum [dy VU.! i | i <- [0 .. VU.length x - 1], normChannelOf spec i == c]
   in (dx, LayerParameterGradient dGamma dBeta)

groupLookup :: [[Int]] -> Int -> Vector Int
groupLookup groups len =
  VU.accum (\_ v -> v) (VU.replicate len 0) [(i, k) | (k, idxs) <- zip [0 ..] groups, i <- idxs]

-- ---------------------------------------------------------------------------
-- Multi-head attention (with residual)
-- ---------------------------------------------------------------------------

attentionForward :: AttentionSpec -> LayerParameters -> Vector Double -> Vector Double
attentionForward spec params x = fst (attentionRun spec params x)

-- | Shared forward that also returns the per-head softmax and projections used
-- by the backward pass.
attentionRun :: AttentionSpec -> LayerParameters -> Vector Double -> (Vector Double, AttnCache)
attentionRun spec params x =
  let d = attnEmbedDim spec
      s = attnSeqLen spec
      h = attnNumHeads spec
      dh = d `div` h
      sc = 1.0 / sqrt (fromIntegral dh)
      (wQ, wK, wV, wO) = split4 (splitSegments (replicate 4 (d * d)) (layerWeights params))
      (bQ, bK, bV, bO) = split4 (splitSegments (replicate 4 d) (layerBias params))
      toks = chunksOf d x
      proj w b t = VU.zipWith (+) (matVec w d d t) b
      qs = map (proj wQ bQ) toks
      ks = map (proj wK bK) toks
      vs = map (proj wV bV) toks
      headSlice hd = VU.slice (hd * dh) dh
      perHead hd =
        let qh = map (headSlice hd) qs
            kh = map (headSlice hd) ks
            vh = map (headSlice hd) vs
            rowP i =
              softmax
                ( VU.fromList
                    [ if attnCausal spec && t > i then (-1.0) / 0.0 else sc * dot (qh !! i) (kh !! t)
                    | t <- [0 .. s - 1]
                    ]
                )
            ps = [rowP i | i <- [0 .. s - 1]]
            ctx i = foldl1 addV [scaleV (ps !! i VU.! t) (vh !! t) | t <- [0 .. s - 1]]
         in ([ctx i | i <- [0 .. s - 1]], ps, qh, kh, vh)
      heads = map perHead [0 .. h - 1]
      contexts = [ctx | (ctx, _, _, _, _) <- heads]
      cs = [VU.concat [contexts !! hd !! i | hd <- [0 .. h - 1]] | i <- [0 .. s - 1]]
      os = map (proj wO bO) cs
      ys = zipWith addV toks os
   in ( VU.concat ys
      , AttnCache {acToks = toks, acQs = qs, acKs = ks, acVs = vs, acHeads = heads, acCs = cs}
      )

data AttnCache = AttnCache
  { acToks :: ![Vector Double]
  , acQs :: ![Vector Double]
  , acKs :: ![Vector Double]
  , acVs :: ![Vector Double]
  , acHeads :: ![([Vector Double], [Vector Double], [Vector Double], [Vector Double], [Vector Double])]
  , acCs :: ![Vector Double]
  }

attentionBackward
  :: AttentionSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> (Vector Double, LayerParameterGradient)
attentionBackward spec params x upstream =
  let d = attnEmbedDim spec
      s = attnSeqLen spec
      h = attnNumHeads spec
      dh = d `div` h
      sc = 1.0 / sqrt (fromIntegral dh)
      (wQ, wK, wV, wO) = split4 (splitSegments (replicate 4 (d * d)) (layerWeights params))
      cache = snd (attentionRun spec params x)
      dOs = chunksOf d upstream -- residual: dO = dY, dX seed = dY
      dWO = foldl1 addV (zipWith outerProduct dOs (acCs cache))
      dBO = foldl1 addV dOs
      dCs = map (matVecTransposed wO d d) dOs
      headSlice hd = VU.slice (hd * dh) dh
      accHead hd =
        let (_, ps, qh, kh, vh) = acHeads cache !! hd
            dch = map (headSlice hd) dCs
            dP i = VU.fromList [dot (dch !! i) (vh !! t) | t <- [0 .. s - 1]]
            dV t = foldl1 addV [scaleV (ps !! i VU.! t) (dch !! i) | i <- [0 .. s - 1]]
            dA i =
              let p = ps !! i
                  g = dP i
                  m = dot p g
               in VU.imap (\t pt -> pt * ((g VU.! t) - m)) p
            dQ i = foldl1 addV [scaleV (sc * (dA i VU.! t)) (kh !! t) | t <- [0 .. s - 1]]
            dK t = foldl1 addV [scaleV (sc * (dA i VU.! t)) (qh !! i) | i <- [0 .. s - 1]]
         in ([dQ i | i <- [0 .. s - 1]], [dK t | t <- [0 .. s - 1]], [dV t | t <- [0 .. s - 1]])
      perHead = map accHead [0 .. h - 1]
      catAt sel i = VU.concat [let (a, b, c) = perHead !! hd in sel (a, b, c) !! i | hd <- [0 .. h - 1]]
      dQs = [catAt (\(a, _, _) -> a) i | i <- [0 .. s - 1]]
      dKs = [catAt (\(_, b, _) -> b) i | i <- [0 .. s - 1]]
      dVs = [catAt (\(_, _, c) -> c) i | i <- [0 .. s - 1]]
      dWfrom ds = foldl1 addV (zipWith outerProduct ds (acToks cache))
      dBfrom = foldl1 addV
      dxs =
        [ foldl1
            addV
            [ dOs !! i
            , matVecTransposed wQ d d (dQs !! i)
            , matVecTransposed wK d d (dKs !! i)
            , matVecTransposed wV d d (dVs !! i)
            ]
        | i <- [0 .. s - 1]
        ]
      weights = VU.concat [dWfrom dQs, dWfrom dKs, dWfrom dVs, dWO]
      biases = VU.concat [dBfrom dQs, dBfrom dKs, dBfrom dVs, dBO]
   in (VU.concat dxs, LayerParameterGradient weights biases)

-- ---------------------------------------------------------------------------
-- GeGLU
-- ---------------------------------------------------------------------------

gelu :: Double -> Double
gelu u = 0.5 * u * (1.0 + erf (u / sqrt 2.0))

geluPdf :: Double -> Double
geluPdf u = exp (negate (u * u) / 2.0) / sqrt (2.0 * pi)

geluDeriv :: Double -> Double
geluDeriv u = 0.5 * (1.0 + erf (u / sqrt 2.0)) + u * geluPdf u

gegluForward
  :: GeGLUSpec
  -> LayerParameters
  -> Vector Double
  -> (Vector Double, (Vector Double, Vector Double, Vector Double, Vector Double))
gegluForward spec params x =
  let (wa, wb, w2) =
        split3
          ( splitSegments
              [ggFf spec * ggIn spec, ggFf spec * ggIn spec, ggOut spec * ggFf spec]
              (layerWeights params)
          )
      (ba, bb, b2) = split3 (splitSegments [ggFf spec, ggFf spec, ggOut spec] (layerBias params))
      a = VU.zipWith (+) (matVec wa (ggFf spec) (ggIn spec) x) ba
      g = VU.zipWith (+) (matVec wb (ggFf spec) (ggIn spec) x) bb
      gg = VU.map gelu g
      hHidden = VU.zipWith (*) a gg
      y = VU.zipWith (+) (matVec w2 (ggOut spec) (ggFf spec) hHidden) b2
   in (y, (a, g, gg, hHidden))

gegluBackward
  :: GeGLUSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> (Vector Double, LayerParameterGradient)
gegluBackward spec params x dy =
  let (wa, wb, w2) =
        split3
          ( splitSegments
              [ggFf spec * ggIn spec, ggFf spec * ggIn spec, ggOut spec * ggFf spec]
              (layerWeights params)
          )
      (_, (a, g, gg, hHidden)) = gegluForward spec params x
      dW2 = outerProduct dy hHidden
      dB2 = dy
      dh = matVecTransposed w2 (ggOut spec) (ggFf spec) dy
      da = VU.zipWith (*) dh gg
      dg = VU.zipWith3 (\d ai gi -> d * ai * geluDeriv gi) dh a g
      dWa = outerProduct da x
      dBa = da
      dWb = outerProduct dg x
      dBb = dg
      dx =
        VU.zipWith
          (+)
          (matVecTransposed wa (ggFf spec) (ggIn spec) da)
          (matVecTransposed wb (ggFf spec) (ggIn spec) dg)
   in (dx, LayerParameterGradient (VU.concat [dWa, dWb, dW2]) (VU.concat [dBa, dBb, dB2]))

-- ---------------------------------------------------------------------------
-- Patch embedding
-- ---------------------------------------------------------------------------

-- | Flat pixel indices per patch (pixel-row-major layout: idx = ((y*W)+x)*C + c).
patchPositions :: PatchSpec -> [[Int]]
patchPositions spec =
  [ [ ((y + dy) * peW spec + (x + dx)) * peC spec + c
    | dy <- [0 .. peP spec - 1]
    , dx <- [0 .. peP spec - 1]
    , c <- [0 .. peC spec - 1]
    ]
  | y <- [0, peStride spec .. peH spec - peP spec]
  , x <- [0, peStride spec .. peW spec - peP spec]
  ]

patchForward :: PatchSpec -> LayerParameters -> Vector Double -> Vector Double
patchForward spec params x =
  let cpp = peC spec * peP spec * peP spec
      w = layerWeights params
      b = layerBias params
      positions = patchPositions spec
      patches = [VU.fromList [x VU.! i | i <- idx] | idx <- positions]
      es = [VU.zipWith (+) (matVec w (peD spec) cpp p) b | p <- patches]
   in VU.concat es

patchBackward
  :: PatchSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> (Vector Double, LayerParameterGradient)
patchBackward spec params x dE =
  let cpp = peC spec * peP spec * peP spec
      w = layerWeights params
      positions = patchPositions spec
      patches = [VU.fromList [x VU.! i | i <- idx] | idx <- positions]
      dEs = chunksOf (peD spec) dE
      dW = foldl1 addV (zipWith outerProduct dEs patches)
      dB = foldl1 addV dEs
      dps = map (matVecTransposed w (peD spec) cpp) dEs
      inN = peC spec * peH spec * peW spec
      dX =
        VU.accum
          (+)
          (VU.replicate inN 0.0)
          [(i, dp VU.! off) | (idx, dp) <- zip positions dps, (off, i) <- zip [0 ..] idx]
   in (dX, LayerParameterGradient dW dB)

-- ---------------------------------------------------------------------------
-- Residual node
-- ---------------------------------------------------------------------------

residualForward
  :: AffineSpec
  -> Shortcut
  -> Double
  -> LayerActivation
  -> LayerActivation
  -> LayerParameters
  -> Vector Double
  -> Either Text (Vector Double, Vector Double)
residualForward inner shortcut scale innerAct finalAct params x = do
  let op = ResidualOp inner shortcut scale innerAct
      ws = splitSegments (opWeightSegments op) (layerWeights params)
      bs = splitSegments (opBiasSegments op) (layerBias params)
  (wInner, bInner, mProj) <- residualSegments shortcut ws bs
  let z = affFwd wInner bInner inner x
      a = applyActivation innerAct z
      sx = case mProj of
        Nothing -> x
        Just (proj, wp, bp) -> affFwd wp bp proj x
      ypre = VU.zipWith (\p q -> p + scale * q) sx a
      y = applyActivation finalAct ypre
  pure (y, ypre)

-- | Total binding of a residual node's inner affine params and optional
-- projection-shortcut params from its packed segments.
residualSegments
  :: Shortcut
  -> [Vector Double]
  -> [Vector Double]
  -> Either Text (Vector Double, Vector Double, Maybe (AffineSpec, Vector Double, Vector Double))
residualSegments shortcut ws bs =
  case (shortcut, ws, bs) of
    (IdentityShortcut, wi : _, bi : _) -> Right (wi, bi, Nothing)
    (ProjectionShortcut proj, wi : wp : _, bi : bp : _) -> Right (wi, bi, Just (proj, wp, bp))
    _ -> Left "residual: parameter segments do not match shortcut"

residualBackward
  :: AffineSpec
  -> Shortcut
  -> Double
  -> LayerActivation
  -> LayerActivation
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> Either Text (Vector Double, LayerParameterGradient)
residualBackward inner shortcut scale innerAct finalAct params x upstream = do
  let op = ResidualOp inner shortcut scale innerAct
      ws = splitSegments (opWeightSegments op) (layerWeights params)
      bs = splitSegments (opBiasSegments op) (layerBias params)
  (wInner, bInner, mProj) <- residualSegments shortcut ws bs
  let z = affFwd wInner bInner inner x
      a = applyActivation innerAct z
      sx = case mProj of
        Nothing -> x
        Just (proj, wp, bp) -> affFwd wp bp proj x
      ypre = VU.zipWith (\p q -> p + scale * q) sx a
      d = activationBackward finalAct (applyActivation finalAct ypre) upstream
      dPre = VU.map (* scale) (activationBackward innerAct a d)
      (dxF, dWf, dBf) = affBwd wInner inner x dPre
  pure $ case mProj of
    Nothing -> (VU.zipWith (+) dxF d, LayerParameterGradient dWf dBf)
    Just (proj, wp, _bp) ->
      let (dxS, dWs, dBs) = affBwd wp proj x d
       in (VU.zipWith (+) dxF dxS, LayerParameterGradient (VU.concat [dWf, dWs]) (VU.concat [dBf, dBs]))

-- ---------------------------------------------------------------------------
-- Blocks (BasicBlock / Bottleneck): ordered affine→norm stages + skip
-- ---------------------------------------------------------------------------

-- | Stage tape: the stage input, the affine pre-activation (norm input), and
-- the activation input (norm output, or the affine pre-activation when the
-- stage has no norm). The backward pass recomputes norm statistics from the
-- norm input, so xhat/stats are not stored.
data StageTape = StageTape
  { stInput :: !(Vector Double)
  , stNormIn :: !(Vector Double)
  , stActIn :: !(Vector Double)
  }

blockForward
  :: BlockSpec
  -> LayerParameters
  -> Vector Double
  -> Either Text (Vector Double, ([StageTape], Vector Double))
blockForward spec params x = do
  let ws = splitSegments (opWeightSegments (BlockOp spec)) (layerWeights params)
      bs = splitSegments (opBiasSegments (BlockOp spec)) (layerBias params)
      (stageWs, shortcutWs) = splitAt (stageWeightCount (blStages spec)) ws
      (stageBs, shortcutBs) = splitAt (stageBiasCount (blStages spec)) bs
      stagePieces = assignStageParams (blStages spec) stageWs stageBs
  (u, tapes) <- foldStages (blStages spec) stagePieces x
  sx <- shortcutFwd (blShortcut spec) shortcutWs shortcutBs x
  when (VU.length sx /= VU.length u) $ Left "block: shortcut/branch width mismatch"
  let ypre = VU.zipWith (\p q -> p + blScale spec * q) sx u
      y = applyActivation (blFinalAct spec) ypre
  pure (y, (tapes, ypre))

foldStages
  :: [BlockStage]
  -> [([Vector Double], [Vector Double])]
  -> Vector Double
  -> Either Text (Vector Double, [StageTape])
foldStages stages pieces x0 = go stages pieces x0 []
 where
  go [] _ h acc = Right (h, reverse acc)
  go (st : sts) (pc : pcs) h acc =
    let (out, tape) = stageForward st pc h
     in go sts pcs out (tape : acc)
  go _ [] _ _ = Left "block: parameter/stage count mismatch"

stageForward
  :: BlockStage -> ([Vector Double], [Vector Double]) -> Vector Double -> (Vector Double, StageTape)
stageForward (BlockStage affine mNorm act) (wSegs, bSegs) x =
  case (mNorm, wSegs, bSegs) of
    (Nothing, wAff : _, bAff : _) ->
      let z = affFwd wAff bAff affine x
       in (applyActivation act z, StageTape x z z)
    (Just normSpec, wAff : wGamma : _, bAff : bBeta : _) ->
      let z = affFwd wAff bAff affine x
          normParams = LayerParameters wGamma bBeta
          (zn, _xhat, _stats) = normForward normSpec normParams z
       in (applyActivation act zn, StageTape x z zn)
    _ -> error "stageForward: block stage/segment mismatch"

stageBackward
  :: BlockStage
  -> ([Vector Double], [Vector Double])
  -> StageTape
  -> Vector Double
  -> (Vector Double, [Vector Double], [Vector Double])
stageBackward (BlockStage affine mNorm act) (wSegs, bSegs) tape dOut =
  let actIn = stActIn tape
      dActPre = activationBackward act (applyActivation act actIn) dOut
   in case (mNorm, wSegs, bSegs) of
        (Nothing, wAff : _, _) ->
          let (dx, dW, dB) = affBwd wAff affine (stInput tape) dActPre
           in (dx, [dW], [dB])
        (Just normSpec, wAff : wGamma : _, _ : bBeta : _) ->
          let normParams = LayerParameters wGamma bBeta
              (dz, pg) = normBackward normSpec normParams (stNormIn tape) dActPre
              (dx, dW, dB) = affBwd wAff affine (stInput tape) dz
           in (dx, [dW, layerGradWeights pg], [dB, layerGradBias pg])
        _ -> error "stageBackward: block stage/segment mismatch"

blockBackward
  :: BlockSpec
  -> LayerParameters
  -> Vector Double
  -> Vector Double
  -> Either Text (Vector Double, LayerParameterGradient)
blockBackward spec params x upstream = do
  let ws = splitSegments (opWeightSegments (BlockOp spec)) (layerWeights params)
      bs = splitSegments (opBiasSegments (BlockOp spec)) (layerBias params)
      (stageWs, shortcutWs) = splitAt (stageWeightCount (blStages spec)) ws
      (stageBs, _shortcutBs) = splitAt (stageBiasCount (blStages spec)) bs
      stagePieces = assignStageParams (blStages spec) stageWs stageBs
  (_, (tapes, ypre)) <- blockForward spec params x
  let d = activationBackward (blFinalAct spec) (applyActivation (blFinalAct spec) ypre) upstream
      du = VU.map (* blScale spec) d
      (dxBranch, stageGrads) = backwardStages (blStages spec) stagePieces tapes du
  sx <- shortcutBwdInput (blShortcut spec) shortcutWs x d
  let (dxShort, shortcutGrads) = sx
      stageWeightGrad = VU.concat (concatMap fst stageGrads)
      stageBiasGrad = VU.concat (concatMap snd stageGrads)
      (shortWeightGrad, shortBiasGrad) = shortcutGrads
  pure
    ( VU.zipWith (+) dxBranch dxShort
    , LayerParameterGradient
        (VU.concat [stageWeightGrad, shortWeightGrad])
        (VU.concat [stageBiasGrad, shortBiasGrad])
    )

-- | Reverse-thread the stage list: feed the incoming grad to the LAST stage
-- first. Returns (input gradient of the whole stage stack, per-stage
-- (weightGrads, biasGrads) in FORWARD order).
backwardStages
  :: [BlockStage]
  -> [([Vector Double], [Vector Double])]
  -> [StageTape]
  -> Vector Double
  -> (Vector Double, [([Vector Double], [Vector Double])])
backwardStages stages pieces tapes du =
  let triples = zip3 stages pieces tapes
      step (st, pc, tape) (dIn, acc) =
        let (dPrev, dW, dB) = stageBackward st pc tape dIn
         in (dPrev, (dW, dB) : acc)
      (dx, grads) = foldr step (du, []) triples
   in (dx, grads)

shortcutFwd
  :: Shortcut -> [Vector Double] -> [Vector Double] -> Vector Double -> Either Text (Vector Double)
shortcutFwd shortcut ws bs x =
  case shortcut of
    IdentityShortcut -> Right x
    ProjectionShortcut proj ->
      case (ws, bs) of
        (w : _, b : _) -> Right (affFwd w b proj x)
        _ -> Left "block: projection shortcut missing parameters"

shortcutBwdInput
  :: Shortcut
  -> [Vector Double]
  -> Vector Double
  -> Vector Double
  -> Either Text (Vector Double, (Vector Double, Vector Double))
shortcutBwdInput shortcut ws x d =
  case shortcut of
    IdentityShortcut -> Right (d, (VU.empty, VU.empty))
    ProjectionShortcut proj ->
      case ws of
        (w : _) ->
          let (dx, dW, dB) = affBwd w proj x d
           in Right (dx, (dW, dB))
        _ -> Left "block: projection shortcut missing parameters"

stageWeightCount :: [BlockStage] -> Int
stageWeightCount = sum . map (\st -> 1 + maybe 0 (const 1) (bsNorm st))

stageBiasCount :: [BlockStage] -> Int
stageBiasCount = stageWeightCount

assignStageParams
  :: [BlockStage] -> [Vector Double] -> [Vector Double] -> [([Vector Double], [Vector Double])]
assignStageParams = go
 where
  go [] _ _ = []
  go (st : sts) wRest bRest =
    let n = 1 + maybe 0 (const 1) (bsNorm st)
        (wHere, wNext) = splitAt n wRest
        (bHere, bNext) = splitAt n bRest
     in (wHere, bHere) : go sts wNext bNext

-- ---------------------------------------------------------------------------
-- Activations
-- ---------------------------------------------------------------------------

applyActivation :: LayerActivation -> Vector Double -> Vector Double
applyActivation LinearActivation = id
applyActivation TanhActivation = VU.map tanh
applyActivation ReluActivation = VU.map (max 0.0)
applyActivation SoftmaxActivation = softmax

activationBackward :: LayerActivation -> Vector Double -> Vector Double -> Vector Double
activationBackward LinearActivation _ upstream = upstream
activationBackward TanhActivation activated upstream = VU.zipWith (\a u -> (1.0 - a * a) * u) activated upstream
activationBackward ReluActivation activated upstream = VU.zipWith (\a u -> if a > 0.0 then u else 0.0) activated upstream
activationBackward SoftmaxActivation activated upstream =
  let d = VU.sum (VU.zipWith (*) activated upstream)
   in VU.zipWith (\a u -> a * (u - d)) activated upstream

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

-- | Abramowitz–Stegun 7.1.26 rational approximation to erf (|error| < 1.5e-7),
-- adequate at the finite-difference tolerance floor for GELU.
erf :: Double -> Double
erf x =
  let t = 1.0 / (1.0 + 0.3275911 * abs x)
      y =
        1.0
          - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
            * t
            * exp (negate (x * x))
   in if x >= 0 then y else negate y

-- ---------------------------------------------------------------------------
-- Finite-difference oracles
-- ---------------------------------------------------------------------------

-- | Max absolute error between the analytic parameter gradient and central
-- finite differences of the loss over every parameter.
maxFiniteDifferenceError
  :: Double -> LayerGraph -> Vector Double -> Vector Double -> Either Text Double
maxFiniteDifferenceError epsilon graph input target = do
  unless (epsilon > 0) $ Left "maxFiniteDifferenceError: epsilon must be positive"
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

-- | Max absolute error between the analytic input gradient and central finite
-- differences of the loss over every input coordinate.
maxInputFiniteDifferenceError
  :: Double -> LayerGraph -> Vector Double -> Vector Double -> Either Text Double
maxInputFiniteDifferenceError epsilon graph input target = do
  unless (epsilon > 0) $ Left "maxInputFiniteDifferenceError: epsilon must be positive"
  (_tape, gradient) <- layerGraphSquaredErrorGradient graph input target
  let analytic = layerGraphInputGradient gradient
  unless (VU.length analytic == VU.length input) $
    Left "maxInputFiniteDifferenceError: analytic input gradient length differs from input"
  errors <-
    traverse
      ( \idx -> do
          let plusInput = input VU.// [(idx, input VU.! idx + epsilon)]
              minusInput = input VU.// [(idx, input VU.! idx - epsilon)]
          plusLoss <- layerGraphLoss graph plusInput target
          minusLoss <- layerGraphLoss graph minusInput target
          let numeric = (plusLoss - minusLoss) / (2.0 * epsilon)
          pure (abs (numeric - (analytic VU.! idx)))
      )
      [0 .. VU.length input - 1]
  pure (maximum (0.0 : errors))

-- ---------------------------------------------------------------------------
-- Small numeric helpers
-- ---------------------------------------------------------------------------

matVec :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVec weights rows cols input =
  VU.generate rows $ \r ->
    VU.sum (VU.generate cols $ \c -> (weights VU.! (r * cols + c)) * (input VU.! c))

matVecTransposed :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVecTransposed weights rows cols upstream =
  VU.generate cols $ \c ->
    VU.sum (VU.generate rows $ \r -> (weights VU.! (r * cols + c)) * (upstream VU.! r))

outerProduct :: Vector Double -> Vector Double -> Vector Double
outerProduct left right =
  VU.generate (VU.length left * VU.length right) $ \idx ->
    let (row, col) = idx `quotRem` VU.length right
     in (left VU.! row) * (right VU.! col)

addV :: Vector Double -> Vector Double -> Vector Double
addV = VU.zipWith (+)

scaleV :: Double -> Vector Double -> Vector Double
scaleV s = VU.map (* s)

dot :: Vector Double -> Vector Double -> Double
dot a b = VU.sum (VU.zipWith (*) a b)

chunksOf :: Int -> Vector Double -> [Vector Double]
chunksOf n v
  | n <= 0 = []
  | VU.null v = []
  | otherwise = VU.take n v : chunksOf n (VU.drop n v)

drawUniform :: Int -> Double -> Random.StdGen -> (Vector Double, Random.StdGen)
drawUniform n limit gen0 =
  let (values, genN) = go n gen0 []
   in (VU.fromList (reverse values), genN)
 where
  go 0 g acc = (acc, g)
  go k g acc =
    let (u, g') = Random.uniformR (-limit, limit) g
     in go (k - 1) g' (u : acc)

clampDouble :: Double -> Double -> Double -> Double
clampDouble lo hi = min hi . max lo

tshow :: (Show a) => a -> Text
tshow = Text.pack . show

mapAccumEither :: (acc -> x -> Either e (y, acc)) -> acc -> [x] -> Either e ([y], acc)
mapAccumEither f = go []
 where
  go ys acc [] = Right (reverse ys, acc)
  go ys acc (x : xs) = do
    (y, acc') <- f acc x
    go (y : ys) acc' xs

-- N-D coordinate helpers (row-major)

flatten :: [Int] -> [Int] -> Int
flatten dims coord = foldl (\acc (d, c) -> acc * d + c) 0 (zip dims coord)

unflatten :: [Int] -> Int -> [Int]
unflatten dims flat = reverse (go (reverse dims) flat)
 where
  go [] _ = []
  go (d : ds) v = let (q, r) = v `quotRem` d in r : go ds q

inBounds :: [Int] -> [Int] -> Bool
inBounds dims coord = and (zipWith (\d c -> c >= 0 && c < d) dims coord)

enumerateCoords :: [Int] -> [[Int]]
enumerateCoords [] = [[]]
enumerateCoords (d : ds) = [i : rest | i <- [0 .. d - 1], rest <- enumerateCoords ds]

zipWith3' :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]
zipWith3' = zipWith3

zipWith4' :: (a -> b -> c -> d -> e) -> [a] -> [b] -> [c] -> [d] -> [e]
zipWith4' f (a : as) (b : bs) (c : cs) (d : ds) = f a b c d : zipWith4' f as bs cs ds
zipWith4' _ _ _ _ _ = []

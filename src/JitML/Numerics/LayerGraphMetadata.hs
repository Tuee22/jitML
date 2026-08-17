{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Serialisable, checkpoint-facing description of a trained
-- 'LayerGraph.LayerGraph' plus the pure converters that round-trip a dense
-- graph through that description.
--
-- This module owns the @LayerGraph*Metadata@ DTO block and the
-- graph<->metadata converters so both "JitML.Checkpoint.Format" (which projects
-- a trained graph into a checkpoint manifest) and "JitML.SL.RuntimeArtifact"
-- (whose supervised runtime payload now carries the trained graph metadata) can
-- depend on it without a module import cycle.  Its only jitML dependency is the
-- low-level typed IR in "JitML.Numerics.LayerGraph".
module JitML.Numerics.LayerGraphMetadata
  ( LayerGraphActivationMetadata (..)
  , LayerGraphKindMetadata (..)
  , LayerGraphMetadata (..)
  , LayerGraphModeMetadata (..)
  , LayerGraphNodeMetadata (..)
  , layerGraphFromMetadata
  , layerGraphMetadataFromGraph
  , layerGraphMetadataParameterCount
  )
where

import Codec.Serialise (Serialise)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import GHC.Generics (Generic)

import JitML.Numerics.LayerGraph qualified as LayerGraph

data LayerGraphModeMetadata
  = LayerGraphTrainingMode
  | LayerGraphInferenceMode
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data LayerGraphActivationMetadata
  = LayerGraphLinearActivation
  | LayerGraphTanhActivation
  | LayerGraphReluActivation
  | LayerGraphSoftmaxActivation
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data LayerGraphKindMetadata
  = LayerGraphDenseLayer
  | LayerGraphConv2DLayer
  | LayerGraphConv3DLayer
  | LayerGraphMaxPoolLayer
  | LayerGraphAvgPoolLayer
  | LayerGraphGlobalAvgPoolLayer
  | LayerGraphBatchNormLayer
  | LayerGraphLayerNormLayer
  | LayerGraphGroupNormLayer Int
  | LayerGraphDropoutLayer Double
  | LayerGraphResidualLayer Double
  | LayerGraphBasicBlockLayer Double
  | LayerGraphBottleneckBlockLayer Double
  | LayerGraphMultiHeadAttentionLayer Int
  | LayerGraphGeGLULayer
  | LayerGraphPatchEmbedLayer
  | LayerGraphIdentityLayer
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data LayerGraphNodeMetadata = LayerGraphNodeMetadata
  { layerGraphNodeName :: Text
  , layerGraphNodeKind :: LayerGraphKindMetadata
  , layerGraphNodeInputShape :: [Int]
  , layerGraphNodeOutputShape :: [Int]
  , layerGraphNodeMode :: LayerGraphModeMetadata
  , layerGraphNodeActivation :: LayerGraphActivationMetadata
  , layerGraphNodeWeightTensor :: Maybe Text
  , layerGraphNodeBiasTensor :: Maybe Text
  , layerGraphNodeOp :: LayerGraph.LayerOp
  -- ^ Phases 242–244 — the node's verified operator geometry. Correct-operator
  --   nodes (Conv/Norm/Pool/Block/Attention/GeGLU/Patch/Dropout) carry a real
  --   'LayerGraph.LayerOp' rather than a decorative kind over a dense affine, so
  --   the checkpoint parameter count and reconstruction are faithful to the
  --   trained graph (not a dense-lowered @in*out@ approximation).
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data LayerGraphMetadata = LayerGraphMetadata
  { layerGraphMetadataName :: Text
  , layerGraphMetadataInputShape :: [Int]
  , layerGraphMetadataOutputShape :: [Int]
  , layerGraphMetadataNodes :: [LayerGraphNodeMetadata]
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

-- | Project a trained graph into checkpoint metadata. Sprint `72.1`:
-- @layerGraphNodeKind@ is written from 'LayerGraph.opKind', so the wire field
-- is a checksum on the one operator vocabulary rather than a second
-- vocabulary; 'layerGraphFromMetadata' rejects a persisted kind that disagrees
-- with the persisted operator.
layerGraphMetadataFromGraph :: LayerGraph.LayerGraph -> LayerGraphMetadata
layerGraphMetadataFromGraph graph =
  LayerGraphMetadata
    { layerGraphMetadataName = LayerGraph.layerGraphName graph
    , layerGraphMetadataInputShape = LayerGraph.unTensorShape (LayerGraph.layerGraphInputShape graph)
    , layerGraphMetadataOutputShape = LayerGraph.unTensorShape (LayerGraph.layerGraphOutputShape graph)
    , layerGraphMetadataNodes = fmap nodeMetadata (LayerGraph.layerGraphNodes graph)
    }
 where
  nodeMetadata node =
    LayerGraphNodeMetadata
      { layerGraphNodeName = LayerGraph.layerNodeName node
      , layerGraphNodeKind = layerKindMetadata (LayerGraph.layerNodeKind node)
      , layerGraphNodeInputShape = LayerGraph.unTensorShape (LayerGraph.layerInputShape node)
      , layerGraphNodeOutputShape = LayerGraph.unTensorShape (LayerGraph.layerOutputShape node)
      , layerGraphNodeMode = layerModeMetadata (LayerGraph.layerMode node)
      , layerGraphNodeActivation = layerActivationMetadata (LayerGraph.layerActivation node)
      , layerGraphNodeWeightTensor =
          fmap (const (LayerGraph.layerNodeName node <> ".weights")) (LayerGraph.layerParameters node)
      , layerGraphNodeBiasTensor =
          fmap (const (LayerGraph.layerNodeName node <> ".bias")) (LayerGraph.layerParameters node)
      , layerGraphNodeOp = LayerGraph.layerNodeOp node
      }

layerModeMetadata :: LayerGraph.LayerMode -> LayerGraphModeMetadata
layerModeMetadata LayerGraph.TrainingMode = LayerGraphTrainingMode
layerModeMetadata LayerGraph.InferenceMode = LayerGraphInferenceMode

layerActivationMetadata :: LayerGraph.LayerActivation -> LayerGraphActivationMetadata
layerActivationMetadata LayerGraph.LinearActivation = LayerGraphLinearActivation
layerActivationMetadata LayerGraph.TanhActivation = LayerGraphTanhActivation
layerActivationMetadata LayerGraph.ReluActivation = LayerGraphReluActivation
layerActivationMetadata LayerGraph.SoftmaxActivation = LayerGraphSoftmaxActivation

layerKindMetadata :: LayerGraph.LayerKind -> LayerGraphKindMetadata
layerKindMetadata LayerGraph.DenseLayer = LayerGraphDenseLayer
layerKindMetadata LayerGraph.Conv2DLayer = LayerGraphConv2DLayer
layerKindMetadata LayerGraph.Conv3DLayer = LayerGraphConv3DLayer
layerKindMetadata (LayerGraph.PoolLayer LayerGraph.MaxPool) = LayerGraphMaxPoolLayer
layerKindMetadata (LayerGraph.PoolLayer LayerGraph.AvgPool) = LayerGraphAvgPoolLayer
layerKindMetadata (LayerGraph.PoolLayer LayerGraph.GlobalAvgPool) = LayerGraphGlobalAvgPoolLayer
layerKindMetadata (LayerGraph.NormLayer LayerGraph.BatchNorm) = LayerGraphBatchNormLayer
layerKindMetadata (LayerGraph.NormLayer LayerGraph.LayerNorm) = LayerGraphLayerNormLayer
layerKindMetadata (LayerGraph.NormLayer (LayerGraph.GroupNorm groups)) = LayerGraphGroupNormLayer groups
layerKindMetadata (LayerGraph.DropoutLayer rate) = LayerGraphDropoutLayer rate
layerKindMetadata (LayerGraph.ResidualLayer scale) = LayerGraphResidualLayer scale
layerKindMetadata (LayerGraph.BasicBlockLayer scale) = LayerGraphBasicBlockLayer scale
layerKindMetadata (LayerGraph.BottleneckBlockLayer scale) = LayerGraphBottleneckBlockLayer scale
layerKindMetadata (LayerGraph.MultiHeadAttentionLayer heads) = LayerGraphMultiHeadAttentionLayer heads
layerKindMetadata LayerGraph.GeGLULayer = LayerGraphGeGLULayer
layerKindMetadata LayerGraph.PatchEmbedLayer = LayerGraphPatchEmbedLayer
layerKindMetadata LayerGraph.IdentityLayer = LayerGraphIdentityLayer

-- ---------------------------------------------------------------------------
-- Phase 239 — reverse converters: reconstruct a served dense 'LayerGraph' from
-- the checkpoint's 'LayerGraphMetadata'.  The trained supervised graph is an
-- all-'DenseOp' / 'IdentityOp' chain (every parameterised node is built by
-- 'LayerGraph.mkAffineLayer', every parameterless node by
-- 'LayerGraph.mkIdentityLayer').  The metadata carries the exact per-node
-- structure (name, kind, single-dimension in/out shapes, mode, activation, and
-- whether the node owns weight/bias tensors), so from-metadata rebuilds each
-- node with zeroed placeholder parameters of the right size; the real trained
-- weights are injected afterwards via
-- 'LayerGraph.replaceGraphParameterVector'.  Round-trip is exact for dense
-- graphs: reconstructing then re-injecting the original parameter vector
-- reproduces the source graph.
metadataLayerMode :: LayerGraphModeMetadata -> LayerGraph.LayerMode
metadataLayerMode LayerGraphTrainingMode = LayerGraph.TrainingMode
metadataLayerMode LayerGraphInferenceMode = LayerGraph.InferenceMode

metadataLayerActivation :: LayerGraphActivationMetadata -> LayerGraph.LayerActivation
metadataLayerActivation LayerGraphLinearActivation = LayerGraph.LinearActivation
metadataLayerActivation LayerGraphTanhActivation = LayerGraph.TanhActivation
metadataLayerActivation LayerGraphReluActivation = LayerGraph.ReluActivation
metadataLayerActivation LayerGraphSoftmaxActivation = LayerGraph.SoftmaxActivation

metadataLayerKind :: LayerGraphKindMetadata -> LayerGraph.LayerKind
metadataLayerKind LayerGraphDenseLayer = LayerGraph.DenseLayer
metadataLayerKind LayerGraphConv2DLayer = LayerGraph.Conv2DLayer
metadataLayerKind LayerGraphConv3DLayer = LayerGraph.Conv3DLayer
metadataLayerKind LayerGraphMaxPoolLayer = LayerGraph.PoolLayer LayerGraph.MaxPool
metadataLayerKind LayerGraphAvgPoolLayer = LayerGraph.PoolLayer LayerGraph.AvgPool
metadataLayerKind LayerGraphGlobalAvgPoolLayer = LayerGraph.PoolLayer LayerGraph.GlobalAvgPool
metadataLayerKind LayerGraphBatchNormLayer = LayerGraph.NormLayer LayerGraph.BatchNorm
metadataLayerKind LayerGraphLayerNormLayer = LayerGraph.NormLayer LayerGraph.LayerNorm
metadataLayerKind (LayerGraphGroupNormLayer groups) = LayerGraph.NormLayer (LayerGraph.GroupNorm groups)
metadataLayerKind (LayerGraphDropoutLayer rate) = LayerGraph.DropoutLayer rate
metadataLayerKind (LayerGraphResidualLayer scale) = LayerGraph.ResidualLayer scale
metadataLayerKind (LayerGraphBasicBlockLayer scale) = LayerGraph.BasicBlockLayer scale
metadataLayerKind (LayerGraphBottleneckBlockLayer scale) = LayerGraph.BottleneckBlockLayer scale
metadataLayerKind (LayerGraphMultiHeadAttentionLayer heads) = LayerGraph.MultiHeadAttentionLayer heads
metadataLayerKind LayerGraphGeGLULayer = LayerGraph.GeGLULayer
metadataLayerKind LayerGraphPatchEmbedLayer = LayerGraph.PatchEmbedLayer
metadataLayerKind LayerGraphIdentityLayer = LayerGraph.IdentityLayer

-- | The trained graph's total parameter count derived from each node's real
-- operator geometry: a dense affine contributes @inputWidth * outputWidth@
-- weights plus @outputWidth@ biases, while every correct operator contributes the
-- sum of its packed 'LayerGraph.opWeightSegments' and 'LayerGraph.opBiasSegments'
-- (conv kernels, gamma/beta, projection tensors, block stages, ...). This equals
-- @VU.length ('LayerGraph.graphParameterVector' graph)@ exactly, so it is the
-- graph-ordered @supervised.weights@ length and the admission/serving anchor.
layerGraphMetadataParameterCount :: LayerGraphMetadata -> Int
layerGraphMetadataParameterCount =
  sum . fmap nodeParameterCount . layerGraphMetadataNodes
 where
  nodeParameterCount node =
    let (wLen, bLen) =
          nodeParameterLengths
            (layerGraphNodeOp node)
            (product (layerGraphNodeInputShape node))
            (product (layerGraphNodeOutputShape node))
     in wLen + bLen

-- | Real packed @(weightLength, biasLength)@ for a node's operator. Dense affines
-- carry @in*out@ weights + @out@ biases; every other correct operator uses its
-- packed segment layout; parameterless operators contribute nothing.
nodeParameterLengths :: LayerGraph.LayerOp -> Int -> Int -> (Int, Int)
nodeParameterLengths op inputWidth outputWidth =
  case op of
    LayerGraph.DenseOp -> (inputWidth * outputWidth, outputWidth)
    _ -> (sum (LayerGraph.opWeightSegments op), sum (LayerGraph.opBiasSegments op))

-- | Reconstruct the served trained 'LayerGraph' (structure only; parameters are
-- zeroed placeholders) from checkpoint metadata. Each node is rebuilt from its
-- stored real 'LayerGraph.LayerOp', with zeroed weight/bias tensors sized by the
-- operator's packed segment layout (a dense affine gets @in*out@ + @out@), so the
-- reconstructed per-node parameter split matches the trained graph exactly and
-- 'LayerGraph.replaceGraphParameterVector' consumes the persisted
-- @supervised.weights@ vector without a shape mismatch. Callers inject the real
-- trained parameter vector afterwards.
layerGraphFromMetadata :: LayerGraphMetadata -> Either Text LayerGraph.LayerGraph
layerGraphFromMetadata meta = do
  nodes <- traverse nodeFromMetadata (layerGraphMetadataNodes meta)
  Right
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = layerGraphMetadataName meta
      , LayerGraph.layerGraphInputShape =
          LayerGraph.TensorShape (layerGraphMetadataInputShape meta)
      , LayerGraph.layerGraphOutputShape =
          LayerGraph.TensorShape (layerGraphMetadataOutputShape meta)
      , LayerGraph.layerGraphNodes = nodes
      }
 where
  nodeFromMetadata node =
    let op = layerGraphNodeOp node
        inputWidth = product (layerGraphNodeInputShape node)
        outputWidth = product (layerGraphNodeOutputShape node)
        (wLen, bLen) = nodeParameterLengths op inputWidth outputWidth
        parameters
          | wLen == 0 && bLen == 0 = Nothing
          | otherwise =
              Just
                LayerGraph.LayerParameters
                  { LayerGraph.layerWeights = VU.replicate wLen 0.0
                  , LayerGraph.layerBias = VU.replicate bLen 0.0
                  }
        storedKind = metadataLayerKind (layerGraphNodeKind node)
        derivedKind = LayerGraph.opKind op
     in if storedKind /= derivedKind
          then
            Left
              ( layerGraphNodeName node
                  <> ": checkpoint kind "
                  <> LayerGraph.layerKindName storedKind
                  <> " disagrees with the executed operator's kind "
                  <> LayerGraph.layerKindName derivedKind
              )
          else
            Right
              LayerGraph.LayerNode
                { LayerGraph.layerNodeName = layerGraphNodeName node
                , LayerGraph.layerNodeOp = op
                , LayerGraph.layerInputShape = LayerGraph.TensorShape (layerGraphNodeInputShape node)
                , LayerGraph.layerOutputShape = LayerGraph.TensorShape (layerGraphNodeOutputShape node)
                , LayerGraph.layerMode = metadataLayerMode (layerGraphNodeMode node)
                , LayerGraph.layerActivation = metadataLayerActivation (layerGraphNodeActivation node)
                , LayerGraph.layerParameters = parameters
                }

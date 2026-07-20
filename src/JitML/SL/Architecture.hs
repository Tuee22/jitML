{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

-- | Substrate-backed supervised-learning architecture runtime.
--
-- The older classifier path in "JitML.SL.Classifier" trains one
-- single-hidden-layer MLP. This module composes the same real
-- @jitml_mlp_*@ device ABI into the canonical SL model families: deep dense
-- stacks, residual stacks, patch-convolution stems, and a compact
-- patch-attention encoder. Every trainable layer calls the injected
-- 'MlpDevice' for batched forward, parameter-gradient, and input-gradient
-- work; a device failure is returned as 'Left' and never falls back to the
-- pure-Haskell reference path.
module JitML.SL.Architecture
  ( ArchitectureFamily (..)
  , ArchitectureFeature (..)
  , ArchitectureOptimizer (..)
  , ArchitectureSpec (..)
  , ExactArchitectureTraining
  , TrainedArchitecture (..)
  , SlRunMetrics (..)
  , architectureSpecForProblem
  , architectureSeedHeadroomForProblem
  , allCanonicalArchitectureSpecs
  , architectureClaimedFeatures
  , architectureClaimedFeaturesForProblem
  , architectureImplementedFeatures
  , canonicalEpochPermutation
  , advanceExactArchitectureTraining
  , exactArchitectureInitialWeights
  , exactArchitectureTrainedWeights
  , exactArchitectureUpdatesExecuted
  , initialiseExactArchitectureTraining
  , measureExactArchitectureValidation
  , renderArchitectureFeature
  , trainArchitectureWithDevice
  , trainArchitectureWithDeviceForExactUpdates
  , trainArchitectureWithDeviceSelected
  , trainCanonicalArchitectureWithDeviceSelected
  , accuracyArchitectureWithDevice
  , crossEntropyArchitectureWithDevice
  , predictArchitectureWithDevice
  , bindTrainedArchitectureInputTransform
  , canonicalClassificationRuntimeContract
  , projectTrainedArchitectureRuntime
  , trainedArchitectureWeights
  , validateArchitectureFeatureParity
  )
where

import Control.Monad (foldM)
import Data.Bifunctor (second)
import Data.Either (fromRight)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as VB
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)

import JitML.Engines.Rng qualified as Rng
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpGradient (..)
  , MlpParams (..)
  , MlpShape (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , mlpParamsToFlat
  , softmax
  )
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.SL.Canonicals
  ( CanonicalProblem (..)
  , canonicalProblems
  )
import JitML.SL.Classifier
  ( ClassifierConfig (..)
  , Dataset
  , LabeledExample (..)
  , defaultClassifierConfig
  )
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact

data ArchitectureFamily
  = DenseFamily
  | DeepDenseFamily
  | Conv2DLeNetFamily
  | ResidualFamily Int
  | WideResidualFamily Int
  | VisionTransformerFamily
  deriving stock (Eq, Show)

data ArchitectureFeature
  = FeatureDense
  | FeatureBatchNorm
  | FeatureDropout
  | FeatureConv2D
  | FeaturePooling
  | FeatureGroupNorm
  | FeatureResidual
  | FeatureBasicBlock
  | FeatureBottleneckBlock
  | FeatureAttention
  | FeaturePatchEmbedding
  | FeatureLayerNorm
  | FeatureGeGLU
  deriving stock (Eq, Ord, Show)

-- | Optimizers supported by the exact tuning executor.  Their update rules
-- are host-owned while every forward/backward gradient remains device-backed.
data ArchitectureOptimizer
  = ArchitectureAdam
  | ArchitectureAdamW
  | ArchitectureSGD
  deriving stock (Eq, Read, Show)

data OptimizerConfig
  = AdamOptimizer !AdamConfig
  | AdamWOptimizer !AdamConfig !Double
  | SgdOptimizer !Double

optimizerConfigFor :: ArchitectureOptimizer -> Double -> OptimizerConfig
optimizerConfigFor optimizer learningRate =
  case optimizer of
    ArchitectureAdam -> AdamOptimizer adamConfig
    -- Canonical decoupled weight decay used by the named AdamW choice.
    ArchitectureAdamW -> AdamWOptimizer adamConfig 1.0e-2
    ArchitectureSGD -> SgdOptimizer learningRate
 where
  adamConfig = defaultAdamConfig {adamLearningRate = learningRate}

-- | Opaque resumable optimizer state used by tuning rung execution.  The
-- absolute update counter owns batch/dropout indexing, so advancing by deltas
-- never replays an earlier optimizer step.
data ExactArchitectureTraining = ExactArchitectureTraining
  { exactTrainingSpec :: !ArchitectureSpec
  , exactTrainingConfig :: !ClassifierConfig
  , exactTrainingOptimizer :: !OptimizerConfig
  , exactTrainingDropout :: !Double
  , exactTrainingTrainSet :: !Dataset
  , exactTrainingValidationSet :: !Dataset
  , exactTrainingStates :: ![LayerState]
  , exactTrainingUpdates :: !Int
  , exactTrainingExamplesProcessed :: !Int
  , exactTrainingInitialWeights :: ![Double]
  }

data ArchitectureSpec = ArchitectureSpec
  { archProblem :: !CanonicalProblem
  , archFamily :: !ArchitectureFamily
  , archLayers :: ![LayerSpec]
  , archLayerGraph :: !LayerGraph.LayerGraph
  }
  deriving stock (Eq, Show)

data TrainedArchitecture = TrainedArchitecture
  { trainedArchSpec :: !ArchitectureSpec
  , trainedArchLayers :: ![LayerState]
  , trainedArchConfig :: !ClassifierConfig
  , trainedArchInputTransform :: !RuntimeArtifact.RawRuntimeInputTransform
  }
  deriving stock (Eq, Show)

-- | Sprint 8.13 — real supervised-learning run metrics. The published loss is
-- a measured mean softmax cross-entropy, never @1 − accuracy@; the validation
-- loss is a real held-out measurement on the validation partition; and the
-- throughput field is a deterministic, non-wall-clock performance metric (the
-- count of training examples the device pushed through forward+backward across
-- every epoch), so it stays inside the determinism contract that excludes
-- wall-clock timing.
data SlRunMetrics = SlRunMetrics
  { slmTrainLoss :: !Double
  -- ^ Real mean softmax cross-entropy on the train partition of the
  --   validation-selected model.
  , slmValidationLoss :: !Double
  -- ^ Real mean softmax cross-entropy on the held-out validation partition of
  --   the selected model — the quantity that drove model selection.
  , slmTrainAccuracy :: !Double
  -- ^ Train-partition accuracy of the selected model.
  , slmExamplesProcessed :: !Int
  -- ^ Deterministic throughput metric: train examples × epochs.
  , slmOptimizerUpdatesExecuted :: !Word64
  -- ^ Trainer-owned count incremented only after a mini-batch optimizer update
  --   returns successfully. Publishers consume this observation directly;
  --   they must not reconstruct it from epochs and batch geometry.
  , slmInitialWeights :: ![Double]
  -- ^ Flat parameter vector from the real initialized layers before the first
  --   optimizer step. Checkpoint witnesses use this to prove movement from the
  --   actual random initialization rather than an all-zero placeholder.
  }
  deriving stock (Eq, Show)

data LayerSpec
  = DenseSpec
      { layerName :: !Text
      , layerInputs :: !Int
      , layerHidden :: !Int
      , layerOutputs :: !Int
      }
  | ResidualSpec
      { layerName :: !Text
      , layerWidth :: !Int
      , layerHidden :: !Int
      , layerResidualScale :: !Double
      }
  | LayerNormSpec
      { layerName :: !Text
      }
  | TokenMixingSpec
      { layerName :: !Text
      , tokenMixingTokens :: !Int
      , tokenMixingHidden :: !Int
      }
  | PatchSpec
      { layerName :: !Text
      , patchGeometry :: !ImageGeometry
      , patchSize :: !Int
      , patchStride :: !Int
      , patchHidden :: !Int
      , patchOutputs :: !Int
      }
  | AttentionSpec
      { layerName :: !Text
      , attentionWidth :: !Int
      , attentionHidden :: !Int
      }
  | MeanPoolSpec
      { layerName :: !Text
      }
  deriving stock (Eq, Show)

data LayerState
  = DenseState !Text !MlpParams !AdamState
  | ResidualState !Text !Double !MlpParams !AdamState
  | LayerNormState !Text
  | TokenMixingState !Text !Int !MlpParams !AdamState
  | PatchState !Text !PatchRuntime !MlpParams !AdamState
  | AttentionState !Text !MlpParams !AdamState
  | MeanPoolState !Text
  deriving stock (Eq, Show)

data ImageGeometry = ImageGeometry
  { geomWidth :: !Int
  , geomHeight :: !Int
  , geomChannels :: !Int
  }
  deriving stock (Eq, Show)

data PatchRuntime = PatchRuntime
  { patchRuntimeGeometry :: !ImageGeometry
  , patchRuntimePositions :: ![[Int]]
  , patchRuntimeInputCount :: !Int
  }
  deriving stock (Eq, Show)

data BatchRep
  = FlatBatch ![Vector Double]
  | TokenBatch ![[Vector Double]]
  deriving stock (Eq, Show)

data LayerTape
  = DenseTape ![Vector Double]
  | ResidualTape ![Vector Double]
  | LayerNormTape ![[LayerNormToken]]
  | TokenMixingTape !Int ![[Vector Double]]
  | PatchTape ![[Vector Double]]
  | AttentionTape ![[AttentionToken]]
  | MeanPoolTape ![Int]
  deriving stock (Eq, Show)

data LayerNormToken = LayerNormToken
  { layerNormInvStd :: !Double
  , layerNormOutput :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data AttentionToken = AttentionToken
  { tokenInput :: !(Vector Double)
  , tokenQ :: !(Vector Double)
  , tokenK :: !(Vector Double)
  , tokenV :: !(Vector Double)
  , tokenWeights :: !(Vector Double)
  , tokenOutput :: !(Vector Double)
  }
  deriving stock (Eq, Show)

data GraphLayerPlan
  = GraphAffine !Text !LayerGraph.LayerKind !Int !LayerGraph.LayerActivation
  | GraphIdentity !Text !LayerGraph.LayerKind

-- | Architecture row for every canonical SL problem. The specs are sized from
-- the concrete training config, so the same row works for small tests and for
-- real IDX image widths.
architectureSpecForProblem :: ClassifierConfig -> CanonicalProblem -> ArchitectureSpec
architectureSpecForProblem config problem =
  let family = familyForModel (problemModel problem)
      layers = layersForFamily family
   in ArchitectureSpec
        { archProblem = problem
        , archFamily = family
        , archLayers = layers
        , archLayerGraph =
            architectureLayerGraphForFamily
              family
              (problemName problem)
              inputs
              outputs
              (clfSeed config)
              latent
              wideLatent
        }
 where
  inputs = clfInputs config
  outputs = clfClasses config + 1
  baseHidden = max 4 (clfHidden config)
  latent = clamp 4 256 baseHidden
  wideLatent = clamp 8 256 baseHidden
  geometry = geometryForInput inputs
  denseFinal name inWidth = DenseSpec name inWidth baseHidden outputs
  projection name = DenseSpec name inputs baseHidden
  tokenCapacity =
    max 1 (length (patchPositions geometry (residualPatchSide geometry) (residualPatchSide geometry)))
  vitTokenCapacity =
    max 1 (length (patchPositions geometry (vitPatchSide geometry) (vitPatchSide geometry)))
  mixerLayerNorm = LayerNormSpec
  tokenMixer name tokens hidden =
    TokenMixingSpec name tokens (max 4 hidden)
  -- Residual scale raised from a near-identity 0.1/0.2: at 0.1 the block output
  -- @x + 0.1*f(x)@ is dominated by the skip path, so the residual MLPs barely
  -- contribute and the deep stacks learned little more than the patch stem +
  -- classifier. 0.5 lets each block meaningfully transform its input while the
  -- skip connection still stabilises the depth.
  residualBlock idx width hidden =
    ResidualSpec ("residual-" <> Text.pack (show idx)) width hidden 0.5
  bottleneckResidualBlock idx width hidden =
    ResidualSpec ("bottleneck-" <> Text.pack (show idx)) width (max 4 (hidden `div` 2)) 0.4
  patchStem name outWidth hidden =
    PatchSpec
      name
      geometry
      (patchSide geometry)
      (patchSide geometry)
      hidden
      outWidth
  residualPatchStem name outWidth hidden =
    PatchSpec
      name
      geometry
      (residualPatchSide geometry)
      (residualPatchSide geometry)
      hidden
      outWidth
  vitPatchStem name outWidth hidden =
    PatchSpec
      name
      geometry
      (vitPatchSide geometry)
      (vitPatchSide geometry)
      hidden
      outWidth
  layersForFamily DenseFamily =
    [denseFinal "dense-classifier" inputs]
  layersForFamily DeepDenseFamily =
    [ projection "deep-dense-1" latent
    , DenseSpec "deep-dense-2" latent baseHidden latent
    , denseFinal "deep-dense-classifier" latent
    ]
  layersForFamily Conv2DLeNetFamily =
    [ patchStem "conv2d-patch-stem" latent baseHidden
    , MeanPoolSpec "conv2d-global-mean-pool"
    , denseFinal "lenet-classifier" latent
    ]
  -- The per-token residual blocks refine each patch independently, so without a
  -- cross-patch mixing step the stack is a "bag of patches" that discards spatial
  -- structure and caps well below the convergence bars. The trained path now uses
  -- a compact MLP-Mixer block: LayerNorm over each token, a device-backed MLP over
  -- the token axis, another LayerNorm, then self-attention before the global pool.
  layersForFamily (ResidualFamily depth)
    | depth == 50 =
        [residualPatchStem "resnet50-conv-stem" latent baseHidden]
          <> fmap (\i -> bottleneckResidualBlock i latent baseHidden) [1 .. 16 :: Int]
          <> [ mixerLayerNorm "resnet50-pre-mixer-layernorm"
             , tokenMixer "resnet50-token-mixing-mlp" tokenCapacity baseHidden
             , mixerLayerNorm "resnet50-post-mixer-layernorm"
             ]
          <> [AttentionSpec "resnet50-token-mixing" latent baseHidden]
          <> [MeanPoolSpec "resnet50-global-mean-pool", denseFinal "resnet50-classifier" latent]
  layersForFamily (ResidualFamily depth) =
    [residualPatchStem "residual-conv-stem" latent baseHidden]
      <> fmap (\i -> residualBlock i latent baseHidden) [1 .. depth]
      <> [ mixerLayerNorm "residual-pre-mixer-layernorm"
         , tokenMixer "residual-token-mixing-mlp" tokenCapacity baseHidden
         , mixerLayerNorm "residual-post-mixer-layernorm"
         ]
      <> [AttentionSpec "residual-token-mixing" latent baseHidden]
      <> [MeanPoolSpec "residual-global-mean-pool", denseFinal "residual-classifier" latent]
  layersForFamily (WideResidualFamily depth) =
    [residualPatchStem "wide-residual-conv-stem" wideLatent (baseHidden * 2)]
      <> fmap (\i -> residualBlock i wideLatent (baseHidden * 2)) [1 .. depth]
      <> [ mixerLayerNorm "wide-residual-pre-mixer-layernorm"
         , tokenMixer "wide-residual-token-mixing-mlp" tokenCapacity (baseHidden * 2)
         , mixerLayerNorm "wide-residual-post-mixer-layernorm"
         ]
      <> [AttentionSpec "wide-residual-token-mixing" wideLatent (baseHidden * 2)]
      <> [MeanPoolSpec "wide-residual-global-mean-pool", denseFinal "wide-residual-classifier" wideLatent]
  layersForFamily VisionTransformerFamily =
    [ vitPatchStem "vit-patch-embedding" latent baseHidden
    , LayerNormSpec "vit-pre-mixer-layernorm"
    , tokenMixer "vit-token-mixing-mlp" vitTokenCapacity baseHidden
    , LayerNormSpec "vit-post-mixer-layernorm"
    , AttentionSpec "vit-self-attention" latent baseHidden
    , MeanPoolSpec "vit-token-mean-pool"
    , denseFinal "vit-classifier" latent
    ]

-- | Largest positive seed offset reached while constructing the exact
-- architecture for a canonical problem.  The layer runtime seeds the final
-- (parameterised) layer at @seed + (layerCount - 1) * 1009@, while the typed
-- graph seeds each parameterised node at its zero-based graph-plan index.
-- Keeping the formula beside the topology constructors lets plan refinement
-- prove every downstream 'Int' addition is in range before execution begins.
architectureSeedHeadroomForProblem :: CanonicalProblem -> Integer
architectureSeedHeadroomForProblem problem =
  max layerInitialisationOffset graphInitialisationOffset
 where
  family = familyForModel (problemModel problem)
  exactSpec = architectureSpecForProblem defaultClassifierConfig problem
  layerInitialisationOffset =
    max 0 (toInteger (length (archLayers exactSpec)) - 1) * 1009
  graphInitialisationOffset =
    maximum
      ( 0
          : [ toInteger index
            | (index, GraphAffine {}) <-
                zip [0 :: Int ..] (graphPlansForFamily family 1 1 1)
            ]
      )

architectureLayerGraphForFamily
  :: ArchitectureFamily
  -> Text
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> LayerGraph.LayerGraph
architectureLayerGraphForFamily family name inputWidth outputWidth seed latent wideLatent =
  LayerGraph.LayerGraph
    { LayerGraph.layerGraphName = name
    , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [inputWidth]
    , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [outputWidth]
    , LayerGraph.layerGraphNodes =
        graphNodes seed inputWidth (graphPlansForFamily family outputWidth latent wideLatent)
    }

graphPlansForFamily :: ArchitectureFamily -> Int -> Int -> Int -> [GraphLayerPlan]
graphPlansForFamily family outputWidth latent wideLatent =
  case family of
    DenseFamily ->
      [GraphAffine "dense-classifier" LayerGraph.DenseLayer outputWidth LayerGraph.LinearActivation]
    DeepDenseFamily ->
      [ GraphAffine "deep-dense-1" LayerGraph.DenseLayer latent LayerGraph.ReluActivation
      , GraphIdentity "deep-dense-1-batchnorm" (LayerGraph.NormLayer LayerGraph.BatchNorm)
      , GraphIdentity "deep-dense-1-dropout" (LayerGraph.DropoutLayer 0.1)
      , GraphAffine "deep-dense-2" LayerGraph.DenseLayer latent LayerGraph.ReluActivation
      , GraphIdentity "deep-dense-2-batchnorm" (LayerGraph.NormLayer LayerGraph.BatchNorm)
      , GraphIdentity "deep-dense-2-dropout" (LayerGraph.DropoutLayer 0.1)
      , GraphAffine "deep-dense-classifier" LayerGraph.DenseLayer outputWidth LayerGraph.LinearActivation
      ]
    Conv2DLeNetFamily ->
      [ GraphAffine "lenet-conv1" LayerGraph.Conv2DLayer latent LayerGraph.ReluActivation
      , GraphIdentity "lenet-pool1" (LayerGraph.PoolLayer LayerGraph.MaxPool)
      , GraphAffine "lenet-conv2" LayerGraph.Conv2DLayer latent LayerGraph.ReluActivation
      , GraphIdentity "lenet-global-avg-pool" (LayerGraph.PoolLayer LayerGraph.GlobalAvgPool)
      , GraphAffine "lenet-classifier" LayerGraph.DenseLayer outputWidth LayerGraph.LinearActivation
      ]
    ResidualFamily depth
      | depth == 50 ->
          residualStem "resnet50" latent
            <> concatMap (bottleneckBlock "resnet50" latent) [1 .. 16 :: Int]
            <> mixerGraphBlock "resnet50" latent
            <> residualHead "resnet50" outputWidth
      | otherwise ->
          residualStem "resnet" latent
            <> concatMap (basicBlock "resnet" latent) [1 .. depth]
            <> mixerGraphBlock "resnet" latent
            <> residualHead "resnet" outputWidth
    WideResidualFamily depth ->
      [ GraphAffine "wide-resnet-conv-stem" LayerGraph.Conv2DLayer wideLatent LayerGraph.ReluActivation
      , GraphIdentity "wide-resnet-groupnorm-stem" (LayerGraph.NormLayer (LayerGraph.GroupNorm 4))
      ]
        <> concatMap (wideBasicBlock wideLatent) [1 .. depth]
        <> mixerGraphBlock "wide-resnet" wideLatent
        <> [ GraphIdentity "wide-resnet-global-avg-pool" (LayerGraph.PoolLayer LayerGraph.GlobalAvgPool)
           , GraphAffine "wide-resnet-classifier" LayerGraph.DenseLayer outputWidth LayerGraph.LinearActivation
           ]
    VisionTransformerFamily ->
      [ GraphAffine "vit-patch-embedding" LayerGraph.PatchEmbedLayer latent LayerGraph.ReluActivation
      , GraphIdentity "vit-layernorm-1" (LayerGraph.NormLayer LayerGraph.LayerNorm)
      , GraphAffine "vit-token-mixing-mlp" LayerGraph.GeGLULayer latent LayerGraph.TanhActivation
      , GraphIdentity "vit-layernorm-mixer" (LayerGraph.NormLayer LayerGraph.LayerNorm)
      , GraphAffine
          "vit-self-attention"
          (LayerGraph.MultiHeadAttentionLayer 2)
          latent
          LayerGraph.TanhActivation
      , GraphIdentity "vit-layernorm-2" (LayerGraph.NormLayer LayerGraph.LayerNorm)
      , GraphAffine "vit-geglu-mlp" LayerGraph.GeGLULayer latent LayerGraph.TanhActivation
      , GraphIdentity "vit-token-mean-pool" (LayerGraph.PoolLayer LayerGraph.GlobalAvgPool)
      , GraphAffine "vit-classifier" LayerGraph.DenseLayer outputWidth LayerGraph.LinearActivation
      ]

mixerGraphBlock :: Text -> Int -> [GraphLayerPlan]
mixerGraphBlock prefix width =
  [ GraphIdentity (prefix <> "-pre-mixer-layernorm") (LayerGraph.NormLayer LayerGraph.LayerNorm)
  , GraphAffine (prefix <> "-token-mixing-mlp") LayerGraph.GeGLULayer width LayerGraph.TanhActivation
  , GraphIdentity (prefix <> "-post-mixer-layernorm") (LayerGraph.NormLayer LayerGraph.LayerNorm)
  , GraphAffine
      (prefix <> "-token-attention")
      (LayerGraph.MultiHeadAttentionLayer 2)
      width
      LayerGraph.TanhActivation
  ]

residualStem :: Text -> Int -> [GraphLayerPlan]
residualStem prefix width =
  [ GraphAffine (prefix <> "-conv-stem") LayerGraph.Conv2DLayer width LayerGraph.ReluActivation
  , GraphIdentity (prefix <> "-stem-batchnorm") (LayerGraph.NormLayer LayerGraph.BatchNorm)
  ]

residualHead :: Text -> Int -> [GraphLayerPlan]
residualHead prefix outputWidth =
  [ GraphIdentity (prefix <> "-global-avg-pool") (LayerGraph.PoolLayer LayerGraph.GlobalAvgPool)
  , GraphAffine (prefix <> "-classifier") LayerGraph.DenseLayer outputWidth LayerGraph.LinearActivation
  ]

basicBlock :: Text -> Int -> Int -> [GraphLayerPlan]
basicBlock prefix width idx =
  [ GraphAffine
      (prefix <> "-basic-block-" <> Text.pack (show idx))
      (LayerGraph.BasicBlockLayer 0.1)
      width
      LayerGraph.ReluActivation
  , GraphIdentity
      (prefix <> "-basic-block-" <> Text.pack (show idx) <> "-batchnorm")
      (LayerGraph.NormLayer LayerGraph.BatchNorm)
  ]

bottleneckBlock :: Text -> Int -> Int -> [GraphLayerPlan]
bottleneckBlock prefix width idx =
  [ GraphAffine
      (prefix <> "-bottleneck-block-" <> Text.pack (show idx))
      (LayerGraph.BottleneckBlockLayer 0.1)
      width
      LayerGraph.ReluActivation
  , GraphIdentity
      (prefix <> "-bottleneck-block-" <> Text.pack (show idx) <> "-batchnorm")
      (LayerGraph.NormLayer LayerGraph.BatchNorm)
  ]

wideBasicBlock :: Int -> Int -> [GraphLayerPlan]
wideBasicBlock width idx =
  [ GraphAffine
      ("wide-resnet-basic-block-" <> Text.pack (show idx))
      (LayerGraph.BasicBlockLayer 0.1)
      width
      LayerGraph.ReluActivation
  , GraphIdentity
      ("wide-resnet-basic-block-" <> Text.pack (show idx) <> "-groupnorm")
      (LayerGraph.NormLayer (LayerGraph.GroupNorm 4))
  ]

graphNodes :: Int -> Int -> [GraphLayerPlan] -> [LayerGraph.LayerNode]
graphNodes seed inputWidth plans =
  snd (List.mapAccumL step (inputWidth, 0 :: Int) plans)
 where
  step (currentWidth, idx) plan =
    case plan of
      GraphAffine name kind outputWidth activation ->
        let node =
              fromRight (fallbackIdentity name currentWidth) $
                LayerGraph.mkAffineLayer
                  name
                  kind
                  currentWidth
                  outputWidth
                  activation
                  LayerGraph.TrainingMode
                  (LayerGraph.deterministicParameters (seed + idx) currentWidth outputWidth)
         in ((outputWidth, idx + 1), node)
      GraphIdentity name kind ->
        let node =
              fromRight (fallbackIdentity name currentWidth) $
                LayerGraph.mkIdentityLayer
                  name
                  kind
                  currentWidth
                  LayerGraph.TrainingMode
         in ((currentWidth, idx + 1), node)
  fallbackIdentity name' width =
    LayerGraph.LayerNode
      { LayerGraph.layerNodeName = name'
      , LayerGraph.layerNodeKind = LayerGraph.DenseLayer
      , LayerGraph.layerInputShape = LayerGraph.TensorShape [max 1 width]
      , LayerGraph.layerOutputShape = LayerGraph.TensorShape [max 1 width]
      , LayerGraph.layerMode = LayerGraph.TrainingMode
      , LayerGraph.layerActivation = LayerGraph.LinearActivation
      , LayerGraph.layerParameters = Nothing
      }

allCanonicalArchitectureSpecs :: ClassifierConfig -> [ArchitectureSpec]
allCanonicalArchitectureSpecs config =
  fmap (architectureSpecForProblem config) canonicalProblems

familyForModel :: Text -> ArchitectureFamily
familyForModel "Dense" = DenseFamily
familyForModel "DeepDense" = DeepDenseFamily
familyForModel "Conv2D" = Conv2DLeNetFamily
familyForModel "ResidualBlock" = ResidualFamily 2
familyForModel "ResidualBlock20" = ResidualFamily 20
familyForModel "ResidualBlock56" = ResidualFamily 56
familyForModel "WideResidualBlock" = WideResidualFamily 12
familyForModel "VisionTransformer" = VisionTransformerFamily
familyForModel "ResidualBlock50" = ResidualFamily 50
familyForModel _ = DenseFamily

architectureClaimedFeatures :: ArchitectureSpec -> [ArchitectureFeature]
architectureClaimedFeatures =
  architectureClaimedFeaturesForProblem . archProblem

architectureClaimedFeaturesForProblem :: CanonicalProblem -> [ArchitectureFeature]
architectureClaimedFeaturesForProblem problem =
  case problemModel problem of
    "Dense" ->
      [FeatureDense]
    "DeepDense" ->
      [FeatureDense, FeatureBatchNorm, FeatureDropout]
    "Conv2D" ->
      [FeatureDense, FeatureConv2D, FeaturePooling]
    "ResidualBlock" ->
      mixerResNetFeatures FeatureBasicBlock
    "ResidualBlock20" ->
      mixerResNetFeatures FeatureBasicBlock
    "ResidualBlock56" ->
      mixerResNetFeatures FeatureBasicBlock
    "WideResidualBlock" ->
      [ FeatureDense
      , FeatureConv2D
      , FeatureGroupNorm
      , FeatureLayerNorm
      , FeatureResidual
      , FeatureBasicBlock
      , FeatureAttention
      , FeatureGeGLU
      ]
    "VisionTransformer" ->
      [FeatureDense, FeaturePatchEmbedding, FeatureLayerNorm, FeatureAttention, FeatureGeGLU]
    "ResidualBlock50" ->
      mixerResNetFeatures FeatureBottleneckBlock
    _ ->
      [FeatureDense]
 where
  mixerResNetFeatures blockFeature =
    [ FeatureDense
    , FeatureConv2D
    , FeatureBatchNorm
    , FeatureLayerNorm
    , FeatureResidual
    , blockFeature
    , FeatureAttention
    , FeatureGeGLU
    ]

architectureImplementedFeatures :: ArchitectureSpec -> [ArchitectureFeature]
architectureImplementedFeatures spec =
  List.nub
    ( concatMap
        (featuresForKind . LayerGraph.layerNodeKind)
        (LayerGraph.layerGraphNodes (archLayerGraph spec))
    )

validateArchitectureFeatureParity :: ArchitectureSpec -> [ArchitectureFeature] -> [Text]
validateArchitectureFeatureParity spec claimed =
  [ problemName (archProblem spec)
      <> " claims "
      <> renderArchitectureFeature feature
      <> " but archLayerGraph does not implement it"
  | feature <- claimed
  , feature `notElem` implemented
  ]
 where
  implemented = architectureImplementedFeatures spec

renderArchitectureFeature :: ArchitectureFeature -> Text
renderArchitectureFeature feature =
  case feature of
    FeatureDense -> "Dense"
    FeatureBatchNorm -> "BatchNorm"
    FeatureDropout -> "Dropout"
    FeatureConv2D -> "Conv2D"
    FeaturePooling -> "pooling"
    FeatureGroupNorm -> "GroupNorm"
    FeatureResidual -> "residual"
    FeatureBasicBlock -> "BasicBlock"
    FeatureBottleneckBlock -> "BottleneckBlock"
    FeatureAttention -> "attention"
    FeaturePatchEmbedding -> "patch-embedding"
    FeatureLayerNorm -> "LayerNorm"
    FeatureGeGLU -> "GeGLU"

featuresForKind :: LayerGraph.LayerKind -> [ArchitectureFeature]
featuresForKind kind =
  case kind of
    LayerGraph.DenseLayer -> [FeatureDense]
    LayerGraph.Conv2DLayer -> [FeatureConv2D]
    LayerGraph.Conv3DLayer -> []
    LayerGraph.PoolLayer _ -> [FeaturePooling]
    LayerGraph.NormLayer LayerGraph.BatchNorm -> [FeatureBatchNorm]
    LayerGraph.NormLayer LayerGraph.LayerNorm -> [FeatureLayerNorm]
    LayerGraph.NormLayer (LayerGraph.GroupNorm _) -> [FeatureGroupNorm]
    LayerGraph.DropoutLayer _ -> [FeatureDropout]
    LayerGraph.ResidualLayer _ -> [FeatureResidual]
    LayerGraph.BasicBlockLayer _ -> [FeatureResidual, FeatureBasicBlock]
    LayerGraph.BottleneckBlockLayer _ -> [FeatureResidual, FeatureBottleneckBlock]
    LayerGraph.MultiHeadAttentionLayer _ -> [FeatureAttention]
    LayerGraph.GeGLULayer -> [FeatureGeGLU]
    LayerGraph.PatchEmbedLayer -> [FeaturePatchEmbedding]

-- | Train a canonical architecture through the substrate device. The loss is
-- mean softmax cross entropy; Adam updates are host-owned but every layer's
-- forward, backward, and input-gradient pass goes through 'MlpDevice'.
trainArchitectureWithDevice
  :: MlpDevice
  -> ArchitectureSpec
  -> ClassifierConfig
  -> Dataset
  -> IO (Either Text (TrainedArchitecture, Double))
trainArchitectureWithDevice device spec config dataset
  | null dataset = pure (Left "trainArchitectureWithDevice: empty dataset")
  | clfEpochs config <= 0 = pure (Left "trainArchitectureWithDevice: epoch count must be positive")
  | clfBatchSize config <= 0 = pure (Left "trainArchitectureWithDevice: batch size must be positive")
  | otherwise = do
      let adamConfig =
            defaultAdamConfig {adamLearningRate = clfLearningRate config}
          optimizerConfig = AdamOptimizer adamConfig
          inputs = FlatBatch (fmap exampleFeatures dataset)
          labels = fmap exampleLabel dataset
      statesE <- initialiseLayers (clfSeed config) (archLayers spec)
      case statesE of
        Left err -> pure (Left err)
        Right states0 -> do
          trainedE <-
            foldM
              ( \acc _epoch -> case acc of
                  Left err -> pure (Left err)
                  Right (states, updatesExecuted) -> do
                    epochE <-
                      trainEpoch
                        (clfBatchSize config)
                        device
                        optimizerConfig
                        (clfClasses config)
                        labels
                        states
                        inputs
                    pure $
                      do
                        (states', epochUpdates) <- epochE
                        totalUpdates <-
                          checkedOptimizerUpdateSum updatesExecuted epochUpdates
                        Right (states', totalUpdates)
              )
              (Right (states0, 0))
              [1 .. clfEpochs config]
          case trainedE of
            Left err -> pure (Left err)
            Right (states, _updatesExecuted) -> do
              let trained =
                    TrainedArchitecture
                      { trainedArchSpec = spec
                      , trainedArchLayers = states
                      , trainedArchConfig = config
                      , trainedArchInputTransform =
                          defaultTrainedArchitectureInputTransform config
                      }
              accE <- accuracyArchitectureWithDevice device trained dataset
              pure (fmap (trained,) accE)

accuracyArchitectureWithDevice
  :: MlpDevice -> TrainedArchitecture -> Dataset -> IO (Either Text Double)
accuracyArchitectureWithDevice _ _ [] = pure (Left "accuracyArchitectureWithDevice: empty evaluation dataset")
accuracyArchitectureWithDevice device trained dataset = do
  outE <- forwardOnly device (trainedArchLayers trained) (FlatBatch (fmap exampleFeatures dataset))
  pure $ do
    outs <- outE
    case outs of
      FlatBatch vectors ->
        let classes = clfClasses (trainedArchConfig trained)
            predicted = fmap (VU.maxIndex . VU.take classes) vectors
            correct =
              length
                (filter id (zipWith (==) predicted (fmap exampleLabel dataset)))
         in Right (fromIntegral correct / fromIntegral (length dataset))
      TokenBatch _ -> Left "accuracyArchitectureWithDevice: final representation is token-shaped"

-- | Sprint 8.13 — real mean softmax cross-entropy of a trained architecture
-- over a dataset, computed through the device forward. This is the SL loss the
-- runtime publishes; it replaces the @1 − accuracy@ stand-in. Empty evaluation
-- data fails closed instead of manufacturing a zero loss.
crossEntropyArchitectureWithDevice
  :: MlpDevice -> TrainedArchitecture -> Dataset -> IO (Either Text Double)
crossEntropyArchitectureWithDevice _ _ [] = pure (Left "crossEntropyArchitectureWithDevice: empty evaluation dataset")
crossEntropyArchitectureWithDevice device trained dataset = do
  outE <- forwardOnly device (trainedArchLayers trained) (FlatBatch (fmap exampleFeatures dataset))
  pure $ do
    outs <- outE
    case outs of
      FlatBatch vectors ->
        let classes = clfClasses (trainedArchConfig trained)
            losses = zipWith (crossEntropyOne classes) vectors (fmap exampleLabel dataset)
         in Right (sum losses / fromIntegral (length dataset))
      TokenBatch _ -> Left "crossEntropyArchitectureWithDevice: final representation is token-shaped"

-- | Run one input through the exact trained layer-state path. The inference
-- boundary is deliberately strict: callers must provide the configured input
-- width, the trained state/spec counts must agree, and the device path must
-- return exactly one non-empty finite flat vector. No input padding, output
-- trimming, alternate graph, or fallback evaluator is permitted here.
predictArchitectureWithDevice
  :: MlpDevice
  -> TrainedArchitecture
  -> Vector Double
  -> IO (Either Text (Vector Double))
predictArchitectureWithDevice device trained input
  | null states =
      pure (Left "predictArchitectureWithDevice: trained architecture has no layer states")
  | length states /= length specs =
      pure
        ( Left
            ( "predictArchitectureWithDevice: layer state/spec count mismatch (states="
                <> showText (length states)
                <> ", specs="
                <> showText (length specs)
                <> ")"
            )
        )
  | expectedWidth <= 0 =
      pure (Left "predictArchitectureWithDevice: configured input width must be positive")
  | VU.length input /= expectedWidth =
      pure
        ( Left
            ( "predictArchitectureWithDevice: input width mismatch (expected="
                <> showText expectedWidth
                <> ", actual="
                <> showText (VU.length input)
                <> ")"
            )
        )
  | not (VU.all isFiniteDouble input) =
      pure (Left "predictArchitectureWithDevice: input contains a non-finite value")
  | otherwise = do
      outE <- forwardOnly device states (FlatBatch [input])
      pure $ do
        output <- case outE of
          Left err -> Left err
          Right (TokenBatch _) ->
            Left "predictArchitectureWithDevice: final representation is token-shaped"
          Right (FlatBatch []) ->
            Left "predictArchitectureWithDevice: device path returned no outputs"
          Right (FlatBatch [flatOutput]) -> Right flatOutput
          Right (FlatBatch flatOutputs) ->
            Left
              ( "predictArchitectureWithDevice: device path returned multiple outputs (count="
                  <> showText (length flatOutputs)
                  <> ")"
              )
        if VU.null output
          then Left "predictArchitectureWithDevice: device path returned an empty flat output"
          else
            if VU.all isFiniteDouble output
              then Right output
              else Left "predictArchitectureWithDevice: device path returned a non-finite flat output"
 where
  states = trainedArchLayers trained
  specs = archLayers (trainedArchSpec trained)
  expectedWidth = clfInputs (trainedArchConfig trained)

-- | Bind the exact fitted feature transform that must run before the trained
-- classification graph.  Canonical image tensors default to their unit-image
-- contract, while callers that fitted train-partition statistics may replace
-- it with a finite, positive-scale standardisation program of the same flat
-- width.  Identity transforms and alternate image geometries are rejected so
-- a record update cannot silently weaken the canonical preprocessing contract.
bindTrainedArchitectureInputTransform
  :: RuntimeArtifact.RawRuntimeInputTransform
  -> TrainedArchitecture
  -> Either Text TrainedArchitecture
bindTrainedArchitectureInputTransform inputTransform trained = do
  validateTrainedArchitectureInputTransform
    (trainedArchConfig trained)
    inputTransform
  Right trained {trainedArchInputTransform = inputTransform}

validateTrainedArchitectureInputTransform
  :: ClassifierConfig
  -> RuntimeArtifact.RawRuntimeInputTransform
  -> Either Text ()
validateTrainedArchitectureInputTransform config inputTransform = do
  refined <- RuntimeArtifact.refineRuntimeInputTransform inputTransform
  let expectedWidth = clfInputs config
      actualWidth = RuntimeArtifact.runtimeInputWidth refined
      expectedGeometry =
        rawImageGeometry (geometryForInput expectedWidth)
  if expectedWidth > 0
    then Right ()
    else Left "trained classification runtime input width must be positive"
  if actualWidth == expectedWidth
    then Right ()
    else
      Left
        ( "trained classification runtime input transform width mismatch (expected="
            <> showText expectedWidth
            <> ", actual="
            <> showText actualWidth
            <> ")"
        )
  case inputTransform of
    RuntimeArtifact.RawUnitImageInput actualGeometry
      | actualGeometry == expectedGeometry -> Right ()
      | otherwise ->
          Left
            ( "trained classification runtime unit-image geometry mismatch (expected="
                <> showText expectedGeometry
                <> ", actual="
                <> showText actualGeometry
                <> ")"
            )
    RuntimeArtifact.RawStandardizeInput _ _ -> Right ()
    RuntimeArtifact.RawIdentityInput _ ->
      Left
        "trained classification runtime input transform must be unit-image or standardized"

defaultTrainedArchitectureInputTransform
  :: ClassifierConfig -> RuntimeArtifact.RawRuntimeInputTransform
defaultTrainedArchitectureInputTransform config =
  RuntimeArtifact.RawUnitImageInput
    (rawImageGeometry (geometryForInput (clfInputs config)))

-- | Derive the exact persistence contract for a canonical classification
-- architecture directly from the same 'LayerSpec' values that training uses.
-- No trained state, weights, or initialization seed participates in this
-- topology projection: a generic supervised plan may select a different exact
-- seed without changing the persisted executable shape.  Checkpoint
-- refinement can therefore reject a runtime whose family, transforms, layer
-- order, names, or production dimensions differ from the authoritative row.
-- ProductRow seed identity remains enforced at the Product projection and
-- publisher boundaries. California Housing deliberately remains outside this
-- helper because its standardisation and inverse-target transform are fitted
-- from the raw training partition.
canonicalClassificationRuntimeContract
  :: ClassifierConfig
  -> CanonicalProblem
  -> Either Text RuntimeArtifact.RawSupervisedRuntime
canonicalClassificationRuntimeContract config problem = do
  if problem `elem` canonicalProblems
    then Right ()
    else
      Left
        ( "runtime contract problem is not an exact canonical supervised row: "
            <> problemName problem
        )
  if problemDataset problem == "California Housing"
    then
      Left
        "California Housing uses the distinct fitted tabular-regression runtime contract"
    else Right ()
  if clfInputs config > 0 && clfClasses config > 0
    then Right ()
    else Left "runtime contract input and semantic class widths must be positive"
  let spec = architectureSpecForProblem config problem
      rawRuntime =
        RuntimeArtifact.RawSupervisedRuntime
          { RuntimeArtifact.rawSupervisedRuntimeFamily =
              rawRuntimeFamily (archFamily spec)
          , RuntimeArtifact.rawSupervisedRuntimeTask =
              RuntimeArtifact.RawClassificationRuntimeTask (clfClasses config)
          , RuntimeArtifact.rawSupervisedRuntimeInputTransform =
              defaultTrainedArchitectureInputTransform config
          , RuntimeArtifact.rawSupervisedRuntimeOutputTransform =
              RuntimeArtifact.RawSemanticPrefixOutput (clfClasses config)
          , RuntimeArtifact.rawSupervisedRuntimeLayers =
              fmap runtimeLayerContract (archLayers spec)
          }
  refined <- RuntimeArtifact.refineSupervisedRuntime rawRuntime
  if RuntimeArtifact.supervisedRuntimeToRaw refined == rawRuntime
    then Right rawRuntime
    else Left "canonical classification runtime contract did not survive exact refinement"

runtimeLayerContract :: LayerSpec -> RuntimeArtifact.RawRuntimeLayer
runtimeLayerContract spec =
  case spec of
    DenseSpec name inputs hidden outputs ->
      RuntimeArtifact.RawDenseLayer
        name
        (RuntimeArtifact.RawRuntimeMlpShape inputs hidden outputs)
    ResidualSpec name width hidden scale ->
      RuntimeArtifact.RawResidualLayer
        name
        scale
        (RuntimeArtifact.RawRuntimeMlpShape width hidden width)
    LayerNormSpec name ->
      RuntimeArtifact.RawLayerNormLayer name
    TokenMixingSpec name tokens hidden ->
      RuntimeArtifact.RawTokenMixLayer name tokens hidden
    PatchSpec name geometry size stride hidden outputs ->
      RuntimeArtifact.RawPatchLayer
        name
        (rawImageGeometry geometry)
        size
        stride
        hidden
        outputs
    AttentionSpec name width hidden ->
      RuntimeArtifact.RawAttentionLayer name width hidden
    MeanPoolSpec name ->
      RuntimeArtifact.RawMeanPoolLayer name

-- | Project the exact trained classification program into the persistence DTO
-- consumed by the V2 supervised runtime.  The projection walks the executable
-- 'LayerSpec'/'LayerState' pairs in their original order.  It does not consult
-- the decorative 'archLayerGraph' and does not reconstruct a topology from the
-- row name.  Every state kind, name, shape, and operation attribute must still
-- agree with the spec that was actually trained; a forged or drifted pair fails
-- before any runtime value is returned.
projectTrainedArchitectureRuntime
  :: TrainedArchitecture
  -> Either Text RuntimeArtifact.RawSupervisedRuntime
projectTrainedArchitectureRuntime trained = do
  let spec = trainedArchSpec trained
      config = trainedArchConfig trained
      problem = archProblem spec
  if problem `elem` canonicalProblems
    then Right ()
    else
      Left
        ( "trained runtime problem is not an exact canonical supervised row: "
            <> problemName problem
        )
  if problemDataset problem == "California Housing"
    then
      Left
        "California Housing uses the distinct tabular-regression runtime projection"
    else Right ()
  expectedFamily <- exactArchitectureFamilyForModel (problemModel problem)
  if archFamily spec == expectedFamily
    then Right ()
    else
      Left
        ( "trained runtime family differs from its canonical model mapping (model="
            <> problemModel problem
            <> ", expected="
            <> showText expectedFamily
            <> ", actual="
            <> showText (archFamily spec)
            <> ")"
        )
  if clfInputs config > 0 && clfClasses config > 0
    then Right ()
    else Left "trained runtime input and semantic class widths must be positive"
  validateTrainedArchitectureInputTransform
    config
    (trainedArchInputTransform trained)
  pairs <-
    zipExact
      "trained runtime layer spec/state count"
      (archLayers spec)
      (trainedArchLayers trained)
  layers <- traverse (uncurry projectRuntimeLayer) pairs
  contract <- canonicalClassificationRuntimeContract config problem
  let contractWithInputTransform =
        contract
          { RuntimeArtifact.rawSupervisedRuntimeInputTransform =
              trainedArchInputTransform trained
          }
      rawRuntime =
        contractWithInputTransform
          { RuntimeArtifact.rawSupervisedRuntimeLayers = layers
          }
  if rawRuntime == contractWithInputTransform
    then Right ()
    else
      Left
        "trained runtime topology differs from the canonical LayerSpec runtime contract"
  refined <- RuntimeArtifact.refineSupervisedRuntime rawRuntime
  if RuntimeArtifact.supervisedRuntimeToRaw refined == rawRuntime
    then Right rawRuntime
    else Left "trained runtime projection did not survive exact refinement"

exactArchitectureFamilyForModel :: Text -> Either Text ArchitectureFamily
exactArchitectureFamilyForModel model =
  case model of
    "Dense" -> Right DenseFamily
    "DeepDense" -> Right DeepDenseFamily
    "Conv2D" -> Right Conv2DLeNetFamily
    "ResidualBlock" -> Right (ResidualFamily 2)
    "ResidualBlock20" -> Right (ResidualFamily 20)
    "ResidualBlock56" -> Right (ResidualFamily 56)
    "WideResidualBlock" -> Right (WideResidualFamily 12)
    "VisionTransformer" -> Right VisionTransformerFamily
    "ResidualBlock50" -> Right (ResidualFamily 50)
    _ -> Left ("unsupported exact supervised architecture model: " <> model)

rawRuntimeFamily :: ArchitectureFamily -> RuntimeArtifact.RawRuntimeFamily
rawRuntimeFamily family =
  case family of
    DenseFamily -> RuntimeArtifact.RawDenseRuntimeFamily
    DeepDenseFamily -> RuntimeArtifact.RawDeepDenseRuntimeFamily
    Conv2DLeNetFamily -> RuntimeArtifact.RawConv2DLeNetRuntimeFamily
    ResidualFamily depth -> RuntimeArtifact.RawResidualRuntimeFamily depth
    WideResidualFamily depth -> RuntimeArtifact.RawWideResidualRuntimeFamily depth
    VisionTransformerFamily -> RuntimeArtifact.RawVisionTransformerRuntimeFamily

projectRuntimeLayer
  :: LayerSpec
  -> LayerState
  -> Either Text RuntimeArtifact.RawRuntimeLayer
projectRuntimeLayer spec state =
  case (spec, state) of
    (DenseSpec expectedName inputs hidden outputs, DenseState actualName params _) -> do
      requireRuntimeLayerName expectedName actualName
      validateRuntimeMlpParams
        expectedName
        (MlpShape inputs hidden outputs)
        params
      Right (RuntimeArtifact.RawDenseLayer actualName (rawMlpShape params))
    ( ResidualSpec expectedName width hidden expectedScale
      , ResidualState actualName actualScale params _
      ) -> do
        requireRuntimeLayerName expectedName actualName
        requireRuntimeAttribute expectedName "residual scale" expectedScale actualScale
        validateRuntimeMlpParams
          expectedName
          (MlpShape width hidden width)
          params
        Right
          ( RuntimeArtifact.RawResidualLayer
              actualName
              actualScale
              (rawMlpShape params)
          )
    (LayerNormSpec expectedName, LayerNormState actualName) -> do
      requireRuntimeLayerName expectedName actualName
      Right (RuntimeArtifact.RawLayerNormLayer actualName)
    ( TokenMixingSpec expectedName expectedTokens hidden
      , TokenMixingState actualName actualTokens params _
      ) -> do
        requireRuntimeLayerName expectedName actualName
        requireRuntimeAttribute
          expectedName
          "token-mix token count"
          expectedTokens
          actualTokens
        validateRuntimeMlpParams
          expectedName
          (MlpShape expectedTokens hidden expectedTokens)
          params
        let actualShape = paramShape params
        Right
          ( RuntimeArtifact.RawTokenMixLayer
              actualName
              actualTokens
              (mlpHidden actualShape)
          )
    ( PatchSpec expectedName expectedGeometry size stride hidden outputs
      , PatchState actualName runtime params _
      ) -> do
        requireRuntimeLayerName expectedName actualName
        requireRuntimeAttribute
          expectedName
          "patch geometry"
          expectedGeometry
          (patchRuntimeGeometry runtime)
        let expectedPositions = patchPositions expectedGeometry size stride
            expectedInputCount =
              geomWidth expectedGeometry
                * geomHeight expectedGeometry
                * geomChannels expectedGeometry
            expectedPatchInputs =
              size * size * geomChannels expectedGeometry + 2
        requireRuntimeAttribute
          expectedName
          "patch positions"
          expectedPositions
          (patchRuntimePositions runtime)
        requireRuntimeAttribute
          expectedName
          "patch input element count"
          expectedInputCount
          (patchRuntimeInputCount runtime)
        validateRuntimeMlpParams
          expectedName
          (MlpShape expectedPatchInputs hidden outputs)
          params
        let actualShape = paramShape params
        Right
          ( RuntimeArtifact.RawPatchLayer
              actualName
              (rawImageGeometry (patchRuntimeGeometry runtime))
              size
              stride
              (mlpHidden actualShape)
              (mlpOutputs actualShape)
          )
    (AttentionSpec expectedName width hidden, AttentionState actualName params _) -> do
      requireRuntimeLayerName expectedName actualName
      validateRuntimeMlpParams
        expectedName
        (MlpShape width hidden (width * 3))
        params
      let actualShape = paramShape params
      Right
        ( RuntimeArtifact.RawAttentionLayer
            actualName
            (mlpInputs actualShape)
            (mlpHidden actualShape)
        )
    (MeanPoolSpec expectedName, MeanPoolState actualName) -> do
      requireRuntimeLayerName expectedName actualName
      Right (RuntimeArtifact.RawMeanPoolLayer actualName)
    _ ->
      Left
        ( "trained runtime layer kind drift (spec="
            <> runtimeSpecKind spec
            <> ", state="
            <> runtimeStateKind state
            <> ")"
        )

requireRuntimeLayerName :: Text -> Text -> Either Text ()
requireRuntimeLayerName expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( "trained runtime layer name drift (expected="
            <> expected
            <> ", actual="
            <> actual
            <> ")"
        )

requireRuntimeAttribute
  :: (Eq value, Show value)
  => Text
  -> Text
  -> value
  -> value
  -> Either Text ()
requireRuntimeAttribute name attribute expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( name
            <> ": trained runtime "
            <> attribute
            <> " drift (expected="
            <> showText expected
            <> ", actual="
            <> showText actual
            <> ")"
        )

validateRuntimeMlpParams :: Text -> MlpShape -> MlpParams -> Either Text ()
validateRuntimeMlpParams name expected params = do
  requireRuntimeAttribute name "MLP shape" expected actual
  requireParameterLength
    "W1"
    (toInteger (mlpHidden actual) * toInteger (mlpInputs actual))
    (paramW1 params)
  requireParameterLength "b1" (toInteger (mlpHidden actual)) (paramB1 params)
  requireParameterLength
    "W2"
    (toInteger (mlpOutputs actual) * toInteger (mlpHidden actual))
    (paramW2 params)
  requireParameterLength "b2" (toInteger (mlpOutputs actual)) (paramB2 params)
 where
  actual = paramShape params
  requireParameterLength label expectedLength vector
    | toInteger (VU.length vector) /= expectedLength =
        Left
          ( name
              <> ": trained runtime parameter "
              <> label
              <> " length drift (expected="
              <> showText expectedLength
              <> ", actual="
              <> showText (VU.length vector)
              <> ")"
          )
    | not (VU.all isFiniteDouble vector) =
        Left (name <> ": trained runtime parameter " <> label <> " contains a non-finite value")
    | otherwise = Right ()

rawMlpShape :: MlpParams -> RuntimeArtifact.RawRuntimeMlpShape
rawMlpShape params =
  let shape = paramShape params
   in RuntimeArtifact.RawRuntimeMlpShape
        { RuntimeArtifact.rawRuntimeMlpInputs = mlpInputs shape
        , RuntimeArtifact.rawRuntimeMlpHidden = mlpHidden shape
        , RuntimeArtifact.rawRuntimeMlpOutputs = mlpOutputs shape
        }

rawImageGeometry :: ImageGeometry -> RuntimeArtifact.RawRuntimeImageGeometry
rawImageGeometry geometry =
  RuntimeArtifact.RawRuntimeImageGeometry
    { RuntimeArtifact.rawRuntimeImageWidth = geomWidth geometry
    , RuntimeArtifact.rawRuntimeImageHeight = geomHeight geometry
    , RuntimeArtifact.rawRuntimeImageChannels = geomChannels geometry
    }

runtimeSpecKind :: LayerSpec -> Text
runtimeSpecKind spec =
  case spec of
    DenseSpec {} -> "Dense"
    ResidualSpec {} -> "Residual"
    LayerNormSpec {} -> "LayerNorm"
    TokenMixingSpec {} -> "TokenMix"
    PatchSpec {} -> "Patch"
    AttentionSpec {} -> "Attention"
    MeanPoolSpec {} -> "MeanPool"

runtimeStateKind :: LayerState -> Text
runtimeStateKind state =
  case state of
    DenseState {} -> "Dense"
    ResidualState {} -> "Residual"
    LayerNormState {} -> "LayerNorm"
    TokenMixingState {} -> "TokenMix"
    PatchState {} -> "Patch"
    AttentionState {} -> "Attention"
    MeanPoolState {} -> "MeanPool"

-- | Softmax cross-entropy of one example: @-log p[label]@ over the first
-- @numClasses@ logits.
crossEntropyOne :: Int -> Vector Double -> Int -> Double
crossEntropyOne numClasses outputVec label =
  let probs = softmax (VU.take numClasses outputVec)
      p = if label >= 0 && label < VU.length probs then probs VU.! label else 0.0
   in negate (log (max 1.0e-12 p))

-- | Sprint 8.13 — train a canonical architecture with validation-driven model
-- selection. Trains epoch by epoch, measures the held-out validation
-- cross-entropy after each epoch, and returns the snapshot with the lowest
-- validation loss (early-stop / model selection on the validation partition,
-- never on test). The returned 'SlRunMetrics' carries the selected model's real
-- train and validation cross-entropy plus the deterministic throughput metric.
-- The validation partition must be a non-empty held-out slice that the caller
-- never folds into @trainSet@.
trainArchitectureWithDeviceSelected
  :: MlpDevice
  -> ArchitectureSpec
  -> ClassifierConfig
  -> Dataset
  -- ^ train partition (gradient updates only)
  -> Dataset
  -- ^ validation partition (selection only; never trained on)
  -> IO (Either Text (TrainedArchitecture, SlRunMetrics))
trainArchitectureWithDeviceSelected =
  trainArchitectureWithDeviceSelectedWithEpochOrder
    (\_epoch dataset -> dataset)

-- | Canonical ProductRow training uses one deterministic, seed-derived
-- permutation of the complete training partition per epoch.  Validation and
-- test partitions retain their original order and never enter this function.
-- The permutation changes neither the number nor the sizes of mini-batches,
-- so the trainer-owned successful optimizer-update count remains the exact
-- observation of the authoritative plan budget.
trainCanonicalArchitectureWithDeviceSelected
  :: MlpDevice
  -> ArchitectureSpec
  -> ClassifierConfig
  -> Dataset
  -- ^ train partition (permuted once per epoch for gradient updates)
  -> Dataset
  -- ^ validation partition (selection only; never trained on or permuted)
  -> IO (Either Text (TrainedArchitecture, SlRunMetrics))
trainCanonicalArchitectureWithDeviceSelected device spec config =
  trainArchitectureWithDeviceSelectedWithEpochOrder
    (canonicalEpochPermutation (clfSeed config))
    device
    spec
    config

-- | Produce the stable canonical epoch order from the experiment seed and
-- one-based epoch index.  SplitMix supplies one fixed-width key per example;
-- sorting by @(key, originalIndex)@ makes collisions deterministic while
-- retaining every whole labeled example exactly once.
canonicalEpochPermutation :: Int -> Int -> Dataset -> Dataset
canonicalEpochPermutation seed epoch dataset =
  selectExample
    <$> List.sortOn
      (\(word, originalIndex, _example) -> (word, originalIndex))
      (zip3 permutationKeys [0 :: Int ..] dataset)
 where
  permutationKeys =
    Rng.splitMixWords
      (length dataset)
      ( Rng.deriveSplitMixSeed
          (Rng.SplitMixSeed (fromIntegral seed))
          (fromIntegral epoch)
      )
  selectExample (_, _, example) = example

trainArchitectureWithDeviceSelectedWithEpochOrder
  :: (Int -> Dataset -> Dataset)
  -> MlpDevice
  -> ArchitectureSpec
  -> ClassifierConfig
  -> Dataset
  -> Dataset
  -> IO (Either Text (TrainedArchitecture, SlRunMetrics))
trainArchitectureWithDeviceSelectedWithEpochOrder epochOrder device spec config trainSet validationSet
  | null trainSet = pure (Left "trainArchitectureWithDeviceSelected: empty training dataset")
  | null validationSet = pure (Left "trainArchitectureWithDeviceSelected: empty validation dataset")
  | clfEpochs config <= 0 =
      pure (Left "trainArchitectureWithDeviceSelected: epoch count must be positive")
  | clfBatchSize config <= 0 =
      pure (Left "trainArchitectureWithDeviceSelected: batch size must be positive")
  | otherwise = do
      let adamConfig = defaultAdamConfig {adamLearningRate = clfLearningRate config}
          optimizerConfig = AdamOptimizer adamConfig
          epochs = clfEpochs config
          selectionSet = validationSet
          mkTrained states =
            TrainedArchitecture
              { trainedArchSpec = spec
              , trainedArchLayers = states
              , trainedArchConfig = config
              , trainedArchInputTransform =
                  defaultTrainedArchitectureInputTransform config
              }
      statesE <- initialiseLayers (clfSeed config) (archLayers spec)
      case statesE of
        Left err -> pure (Left err)
        Right states0 -> do
          let initialWeights = architectureLayerWeights states0
          folded <-
            foldM
              ( \acc epoch -> case acc of
                  Left err -> pure (Left err)
                  Right (states, best, updatesExecuted) -> do
                    let epochTrainSet = epochOrder epoch trainSet
                    stepE <-
                      trainEpoch
                        (clfBatchSize config)
                        device
                        optimizerConfig
                        (clfClasses config)
                        (fmap exampleLabel epochTrainSet)
                        states
                        (FlatBatch (fmap exampleFeatures epochTrainSet))
                    case stepE of
                      Left err -> pure (Left err)
                      Right (states', epochUpdates) -> do
                        valE <- crossEntropyArchitectureWithDevice device (mkTrained states') selectionSet
                        case valE of
                          Left err -> pure (Left err)
                          Right valLoss ->
                            let best' = case best of
                                  Just (_, bestVal) | bestVal <= valLoss -> best
                                  _ -> Just (states', valLoss)
                             in pure $ do
                                  totalUpdates <-
                                    checkedOptimizerUpdateSum updatesExecuted epochUpdates
                                  Right (states', best', totalUpdates)
              )
              (Right (states0, Nothing, 0))
              [1 .. epochs]
          case folded of
            Left err -> pure (Left err)
            Right (_, Nothing, _) ->
              pure (Left "trainArchitectureWithDeviceSelected: no epoch produced a validation measurement")
            Right (_, Just (bestStates, bestValLoss), updatesExecuted) -> do
              let trained = mkTrained bestStates
              trainLossE <- crossEntropyArchitectureWithDevice device trained trainSet
              trainAccE <- accuracyArchitectureWithDevice device trained trainSet
              pure $ do
                trainLoss <- trainLossE
                trainAcc <- trainAccE
                Right
                  ( trained
                  , SlRunMetrics
                      { slmTrainLoss = trainLoss
                      , slmValidationLoss = bestValLoss
                      , slmTrainAccuracy = trainAcc
                      , slmExamplesProcessed = length trainSet * epochs
                      , slmOptimizerUpdatesExecuted = updatesExecuted
                      , slmInitialWeights = initialWeights
                      }
                  )

-- | Train for exactly the requested number of mini-batch optimizer updates.
-- This is the tuning runtime: a scheduler budget is an update budget, not an
-- epoch count.  Batches cycle deterministically when the budget exceeds one
-- dataset pass.  The configured dropout is deterministic inverted input
-- dropout applied only to gradient batches; validation and objective
-- measurements always use the untouched held-out examples.
trainArchitectureWithDeviceForExactUpdates
  :: MlpDevice
  -> ArchitectureSpec
  -> ClassifierConfig
  -> ArchitectureOptimizer
  -> Double
  -> Int
  -> Dataset
  -> Dataset
  -> IO (Either Text (TrainedArchitecture, SlRunMetrics))
trainArchitectureWithDeviceForExactUpdates device spec config optimizer dropout updates trainSet validationSet = do
  initialE <-
    initialiseExactArchitectureTraining
      spec
      config
      optimizer
      dropout
      trainSet
      validationSet
  case initialE of
    Left err -> pure (Left err)
    Right initial -> do
      advancedE <- advanceExactArchitectureTraining device updates initial
      case advancedE of
        Left err -> pure (Left err)
        Right advanced -> exactArchitectureMetrics device advanced

initialiseExactArchitectureTraining
  :: ArchitectureSpec
  -> ClassifierConfig
  -> ArchitectureOptimizer
  -> Double
  -> Dataset
  -> Dataset
  -> IO (Either Text ExactArchitectureTraining)
initialiseExactArchitectureTraining spec config optimizer dropout trainSet validationSet
  | null trainSet = pure (Left "initialiseExactArchitectureTraining: empty training dataset")
  | null validationSet = pure (Left "initialiseExactArchitectureTraining: empty validation dataset")
  | clfBatchSize config <= 0 =
      pure (Left "initialiseExactArchitectureTraining: batch size must be positive")
  | isNaN dropout || isInfinite dropout || dropout < 0.0 || dropout >= 1.0 =
      pure (Left "initialiseExactArchitectureTraining: dropout must be finite and in [0, 1)")
  | otherwise = do
      statesE <- initialiseLayers (clfSeed config) (archLayers spec)
      pure $
        fmap
          ( \states ->
              ExactArchitectureTraining
                { exactTrainingSpec = spec
                , exactTrainingConfig = config
                , exactTrainingOptimizer = optimizerConfigFor optimizer (clfLearningRate config)
                , exactTrainingDropout = dropout
                , exactTrainingTrainSet = trainSet
                , exactTrainingValidationSet = validationSet
                , exactTrainingStates = states
                , exactTrainingUpdates = 0
                , exactTrainingExamplesProcessed = 0
                , exactTrainingInitialWeights = architectureLayerWeights states
                }
          )
          statesE

advanceExactArchitectureTraining
  :: MlpDevice
  -> Int
  -> ExactArchitectureTraining
  -> IO (Either Text ExactArchitectureTraining)
advanceExactArchitectureTraining device additionalUpdates training
  | additionalUpdates < 0 =
      pure (Left "advanceExactArchitectureTraining: update delta must be non-negative")
  | otherwise =
      foldM advanceOne (Right training) [1 .. additionalUpdates]
 where
  advanceOne acc _offset =
    case acc of
      Left err -> pure (Left err)
      Right current
        | exactTrainingUpdates current == maxBound ->
            pure
              ( Left
                  "advanceExactArchitectureTraining: optimizer-update count exceeds the Int range"
              )
        | otherwise -> do
            let config = exactTrainingConfig current
                absoluteUpdate = exactTrainingUpdates current + 1
                batches =
                  miniBatches
                    (clfBatchSize config)
                    (fmap exampleFeatures (exactTrainingTrainSet current))
                    (fmap exampleLabel (exactTrainingTrainSet current))
                (batchInputs, batchLabels) =
                  batches !! ((absoluteUpdate - 1) `mod` length batches)
                droppedInputs =
                  applyDeterministicInputDropout
                    (clfSeed config)
                    absoluteUpdate
                    (exactTrainingDropout current)
                    batchInputs
            case checkedExactExamplesProcessed
              (exactTrainingExamplesProcessed current)
              (length batchLabels) of
              Left err -> pure (Left err)
              Right examplesProcessed -> do
                statesE <-
                  trainBatch
                    device
                    (exactTrainingOptimizer current)
                    (clfClasses config)
                    batchLabels
                    (exactTrainingStates current)
                    (FlatBatch droppedInputs)
                pure $
                  fmap
                    ( \states ->
                        current
                          { exactTrainingStates = states
                          , exactTrainingUpdates = absoluteUpdate
                          , exactTrainingExamplesProcessed = examplesProcessed
                          }
                    )
                    statesE

measureExactArchitectureValidation
  :: MlpDevice
  -> ExactArchitectureTraining
  -> IO (Either Text (Double, Double))
measureExactArchitectureValidation device training = do
  let trained = exactTrainingTrainedArchitecture training
      validationSet = exactTrainingValidationSet training
  validationLossE <- crossEntropyArchitectureWithDevice device trained validationSet
  validationAccuracyE <- accuracyArchitectureWithDevice device trained validationSet
  pure ((,) <$> validationLossE <*> validationAccuracyE)

exactArchitectureMetrics
  :: MlpDevice
  -> ExactArchitectureTraining
  -> IO (Either Text (TrainedArchitecture, SlRunMetrics))
exactArchitectureMetrics device training = do
  let trained = exactTrainingTrainedArchitecture training
  trainLossE <- crossEntropyArchitectureWithDevice device trained (exactTrainingTrainSet training)
  validationE <- measureExactArchitectureValidation device training
  trainAccuracyE <- accuracyArchitectureWithDevice device trained (exactTrainingTrainSet training)
  pure $ do
    trainLoss <- trainLossE
    (validationLoss, _validationAccuracy) <- validationE
    trainAccuracy <- trainAccuracyE
    updatesExecuted <- checkedExactOptimizerUpdates (exactTrainingUpdates training)
    Right
      ( trained
      , SlRunMetrics
          { slmTrainLoss = trainLoss
          , slmValidationLoss = validationLoss
          , slmTrainAccuracy = trainAccuracy
          , slmExamplesProcessed = exactTrainingExamplesProcessed training
          , slmOptimizerUpdatesExecuted = updatesExecuted
          , slmInitialWeights = exactTrainingInitialWeights training
          }
      )

exactTrainingTrainedArchitecture :: ExactArchitectureTraining -> TrainedArchitecture
exactTrainingTrainedArchitecture training =
  TrainedArchitecture
    { trainedArchSpec = exactTrainingSpec training
    , trainedArchLayers = exactTrainingStates training
    , trainedArchConfig = exactTrainingConfig training
    , trainedArchInputTransform =
        defaultTrainedArchitectureInputTransform (exactTrainingConfig training)
    }

exactArchitectureUpdatesExecuted :: ExactArchitectureTraining -> Int
exactArchitectureUpdatesExecuted = exactTrainingUpdates

exactArchitectureInitialWeights :: ExactArchitectureTraining -> [Double]
exactArchitectureInitialWeights = exactTrainingInitialWeights

exactArchitectureTrainedWeights :: ExactArchitectureTraining -> [Double]
exactArchitectureTrainedWeights = architectureLayerWeights . exactTrainingStates

applyDeterministicInputDropout
  :: Int -> Int -> Double -> [Vector Double] -> [Vector Double]
applyDeterministicInputDropout _ _ 0.0 = id
applyDeterministicInputDropout seed updateIndex rate =
  snd . List.mapAccumL dropIndexedExample (0 :: Int)
 where
  inverseKeep = 1.0 / (1.0 - rate)
  dropIndexedExample exampleIndex value =
    (exampleIndex + 1, dropExample exampleIndex value)
  dropExample exampleIndex =
    VU.imap $ \featureIndex value ->
      if dropoutUnit seed updateIndex exampleIndex featureIndex < rate
        then 0.0
        else value * inverseKeep

dropoutUnit :: Int -> Int -> Int -> Int -> Double
dropoutUnit seed updateIndex exampleIndex featureIndex =
  fromIntegral hashed / 1000003.0
 where
  hashed :: Integer
  hashed =
    abs
      ( toInteger seed * 1103515245
          + toInteger updateIndex * 2654435761
          + toInteger exampleIndex * 2246822519
          + toInteger featureIndex * 3266489917
      )
      `mod` 1000003

-- | Flatten a trained architecture's per-layer 'MlpParams' into one weight
-- vector, in layer order, so a trained architecture can be promoted into a
-- checkpoint (the shape the tuning sweep's @trialResultWeights@ round-trips
-- through the @.jmw1@ codec). Parameterless layers (mean-pool) contribute
-- nothing.
trainedArchitectureWeights :: TrainedArchitecture -> [Double]
trainedArchitectureWeights =
  architectureLayerWeights . trainedArchLayers

architectureLayerWeights :: [LayerState] -> [Double]
architectureLayerWeights =
  concatMap layerWeights
 where
  layerWeights (DenseState _ params _) = mlpParamsToFlat params
  layerWeights (ResidualState _ _ params _) = mlpParamsToFlat params
  layerWeights (LayerNormState _) = []
  layerWeights (TokenMixingState _ _ params _) = mlpParamsToFlat params
  layerWeights (PatchState _ _ params _) = mlpParamsToFlat params
  layerWeights (AttentionState _ params _) = mlpParamsToFlat params
  layerWeights (MeanPoolState _) = []

trainEpoch
  :: Int
  -> MlpDevice
  -> OptimizerConfig
  -> Int
  -> [Int]
  -> [LayerState]
  -> BatchRep
  -> IO (Either Text ([LayerState], Word64))
trainEpoch batchSize device optimizerConfig numClasses labels states (FlatBatch inputs) =
  if batchSize <= 0
    then pure (Left "trainArchitectureWithDevice: batch size must be positive")
    else
      foldM
        ( \acc (batchInputs, batchLabels) -> case acc of
            Left err -> pure (Left err)
            Right (current, updatesExecuted) ->
              case checkedOptimizerUpdateSum updatesExecuted 1 of
                Left err -> pure (Left err)
                Right nextUpdatesExecuted -> do
                  updatedE <-
                    trainBatch device optimizerConfig numClasses batchLabels current (FlatBatch batchInputs)
                  pure $
                    fmap
                      (,nextUpdatesExecuted)
                      updatedE
        )
        (Right (states, 0))
        (miniBatches batchSize inputs labels)
trainEpoch _ _ _ _ _ _ (TokenBatch _) =
  pure (Left "trainArchitectureWithDevice: top-level epoch expected flat inputs")

checkedOptimizerUpdateSum :: Word64 -> Word64 -> Either Text Word64
checkedOptimizerUpdateSum current additional
  | additional > maxBound - current =
      Left "trainArchitectureWithDevice: optimizer-update count exceeds the Word64 range"
  | otherwise = Right (current + additional)

checkedExactOptimizerUpdates :: Int -> Either Text Word64
checkedExactOptimizerUpdates updatesExecuted
  | updatesExecuted < 0 =
      Left "exact architecture optimizer-update count must be non-negative"
  | otherwise = Right (fromIntegral updatesExecuted)

checkedExactExamplesProcessed :: Int -> Int -> Either Text Int
checkedExactExamplesProcessed current additional
  | current < 0 || additional < 0 =
      Left "exact architecture examples-processed count must be non-negative"
  | additional > maxBound - current =
      Left "exact architecture examples-processed count exceeds the Int range"
  | otherwise = Right (current + additional)

trainBatch
  :: MlpDevice
  -> OptimizerConfig
  -> Int
  -> [Int]
  -> [LayerState]
  -> BatchRep
  -> IO (Either Text [LayerState])
trainBatch device optimizerConfig numClasses labels states inputs = do
  fwdE <- forwardWithTapes device states inputs
  case fwdE of
    Left err -> pure (Left err)
    Right (FlatBatch outputs, tapes) -> do
      let outputGrads = zipWith (classifierOutputGradient numClasses) outputs labels
      backE <- backwardAll device optimizerConfig states tapes (FlatBatch outputGrads) (length labels)
      pure (fmap fst backE)
    Right (TokenBatch _, _) ->
      pure (Left "trainArchitectureWithDevice: final layer produced token representation")

miniBatches :: Int -> [Vector Double] -> [Int] -> [([Vector Double], [Int])]
miniBatches size inputs labels =
  case splitAt size (zip inputs labels) of
    ([], _) -> []
    (chunk, rest) ->
      let (chunkInputs, chunkLabels) = unzip chunk
          (restInputs, restLabels) = unzip rest
       in (chunkInputs, chunkLabels) : miniBatches size restInputs restLabels

initialiseLayers :: Int -> [LayerSpec] -> IO (Either Text [LayerState])
initialiseLayers seed specs =
  pure (traverse (uncurry initialiseLayer) (zip [0 :: Int ..] specs))
 where
  initialiseLayer idx spec =
    let layerSeed = seed + idx * 1009
     in case spec of
          DenseSpec name inputs hidden outputs ->
            let shape = MlpShape inputs hidden outputs
                params = mlpInit shape layerSeed
             in Right (DenseState name params (adamInit shape))
          ResidualSpec name width hidden scale ->
            let shape = MlpShape width hidden width
                params = mlpInit shape layerSeed
             in Right (ResidualState name scale params (adamInit shape))
          LayerNormSpec name -> Right (LayerNormState name)
          TokenMixingSpec name tokens hidden
            | tokens <= 0 ->
                Left (name <> ": token-mixing token count must be positive")
            | otherwise ->
                let shape = MlpShape tokens hidden tokens
                    params = mlpInit shape layerSeed
                 in Right (TokenMixingState name tokens params (adamInit shape))
          PatchSpec name geometry pSize pStride hidden outputs
            | pSize <= 0 || pStride <= 0 ->
                Left (name <> ": patch size and stride must be positive")
            | otherwise ->
                let positions = patchPositions geometry pSize pStride
                    patchInputs = pSize * pSize * geomChannels geometry + 2
                    shape = MlpShape patchInputs hidden outputs
                    params = mlpInit shape layerSeed
                    runtime =
                      PatchRuntime
                        { patchRuntimeGeometry = geometry
                        , patchRuntimePositions = positions
                        , patchRuntimeInputCount =
                            geomWidth geometry * geomHeight geometry * geomChannels geometry
                        }
                 in if null positions
                      then Left (name <> ": image geometry produced no patches")
                      else Right (PatchState name runtime params (adamInit shape))
          AttentionSpec name width hidden ->
            let shape = MlpShape width hidden (width * 3)
                params = mlpInit shape layerSeed
             in Right (AttentionState name params (adamInit shape))
          MeanPoolSpec name -> Right (MeanPoolState name)

forwardOnly :: MlpDevice -> [LayerState] -> BatchRep -> IO (Either Text BatchRep)
forwardOnly device states input =
  foldM step (Right input) states
 where
  step acc state = case acc of
    Left err -> pure (Left err)
    Right rep -> do
      next <- forwardLayer device state rep
      pure (fmap fst next)

forwardWithTapes
  :: MlpDevice -> [LayerState] -> BatchRep -> IO (Either Text (BatchRep, [LayerTape]))
forwardWithTapes device states input = do
  result <- foldM step (Right (input, [])) states
  pure (fmap (second reverse) result)
 where
  step acc state = case acc of
    Left err -> pure (Left err)
    Right (rep, tapes) -> do
      next <- forwardLayer device state rep
      pure (fmap (\(rep', tape) -> (rep', tape : tapes)) next)

forwardLayer :: MlpDevice -> LayerState -> BatchRep -> IO (Either Text (BatchRep, LayerTape))
forwardLayer device state rep =
  case (state, rep) of
    (DenseState _ params _, FlatBatch xs) -> do
      outsE <- mlpdForwardBatch device params xs
      pure (fmap (\outs -> (FlatBatch outs, DenseTape xs)) outsE)
    (ResidualState _ scale params _, FlatBatch xs) -> do
      outsE <- mlpdForwardBatch device params xs
      pure $
        fmap
          ( \outs ->
              let scaled = fmap (VU.map (* scale)) outs
               in (FlatBatch (zipWith addVec xs scaled), ResidualTape xs)
          )
          outsE
    (ResidualState _ scale params _, TokenBatch samples) -> do
      let flatTokens = concat samples
      outsE <- mlpdForwardBatch device params flatTokens
      pure $
        fmap
          ( \flatOuts ->
              let scaled = fmap (VU.map (* scale)) flatOuts
                  residualTokens = zipWith addVec flatTokens scaled
               in ( TokenBatch (unflattenBy (fmap length samples) residualTokens)
                  , ResidualTape flatTokens
                  )
          )
          outsE
    (LayerNormState _, TokenBatch samples) ->
      let normalized = fmap (fmap layerNormForward) samples
       in pure
            ( Right
                ( TokenBatch (fmap (fmap layerNormOutput) normalized)
                , LayerNormTape normalized
                )
            )
    (TokenMixingState name expectedTokens params _, TokenBatch samples) ->
      case tokenMixingInputsExact name expectedTokens params samples of
        Left err -> pure (Left err)
        Right (width, channelInputs) -> do
          outsE <- mlpdForwardBatch device params (concat channelInputs)
          pure $ do
            flatOuts <- outsE
            mixedChannels <-
              unflattenByExact
                (name <> ": token-mixing forward device outputs")
                (fmap length channelInputs)
                flatOuts
            mixedTokens <-
              tokenMixingOutputsExact name expectedTokens width mixedChannels
            Right
              ( TokenBatch mixedTokens
              , TokenMixingTape width channelInputs
              )
    (PatchState _ runtime params _, FlatBatch xs) -> do
      let patchesBySample = fmap (extractPatches runtime) xs
          flatPatches = concat patchesBySample
      outsE <- mlpdForwardBatch device params flatPatches
      pure $
        fmap
          ( \flatOuts ->
              ( TokenBatch (unflattenBy (fmap length patchesBySample) flatOuts)
              , PatchTape patchesBySample
              )
          )
          outsE
    (AttentionState name params _, TokenBatch samples) ->
      case validateAttentionInputs name params samples of
        Left err -> pure (Left err)
        Right () -> do
          let flatTokens = concat samples
          qkvE <- mlpdForwardBatch device params flatTokens
          pure $ do
            flatQkv <- qkvE
            grouped <-
              unflattenByExact
                (name <> ": attention forward device outputs")
                (fmap length samples)
                flatQkv
            samplePairs <-
              zipExact
                (name <> ": attention forward sample count")
                samples
                grouped
            attended <- traverse (uncurry (attentionForward name)) samplePairs
            Right
              ( TokenBatch (fmap (fmap attentionOutput) attended)
              , AttentionTape attended
              )
    (MeanPoolState name, TokenBatch samples) ->
      pure $ do
        _ <- validateTokenBatch (name <> ": mean-pool inputs") Nothing samples
        pooled <- traverse (meanVectorExact name) samples
        Right (FlatBatch pooled, MeanPoolTape (fmap length samples))
    (DenseState name _ _, TokenBatch _) ->
      pure (Left (name <> ": dense layer expected flat inputs"))
    (LayerNormState name, FlatBatch _) ->
      pure (Left (name <> ": layernorm expected token inputs"))
    (TokenMixingState name _ _ _, FlatBatch _) ->
      pure (Left (name <> ": token-mixing expected token inputs"))
    (PatchState name _ _ _, TokenBatch _) ->
      pure (Left (name <> ": patch layer expected flat inputs"))
    (AttentionState name _ _, FlatBatch _) ->
      pure (Left (name <> ": attention layer expected token inputs"))
    (MeanPoolState name, FlatBatch _) ->
      pure (Left (name <> ": mean-pool layer expected token inputs"))

backwardAll
  :: MlpDevice
  -> OptimizerConfig
  -> [LayerState]
  -> [LayerTape]
  -> BatchRep
  -> Int
  -> IO (Either Text ([LayerState], BatchRep))
backwardAll device optimizerConfig states tapes upstream batchN = do
  let reversed = zip (reverse states) (reverse tapes)
      lastIndex = length reversed - 1
      step acc (idx, (state, tape)) = case acc of
        Left err -> pure (Left err)
        Right (statesRev, grad) -> do
          let needInputGradient = idx < lastIndex
          back <- backwardLayer device optimizerConfig needInputGradient state tape grad batchN
          pure (fmap (\(state', grad') -> (state' : statesRev, grad')) back)
  result <-
    foldM
      step
      (Right ([], upstream))
      (zip [0 :: Int ..] reversed)
  pure $ fmap (\(statesRev, grad) -> (statesRev, grad)) result

backwardLayer
  :: MlpDevice
  -> OptimizerConfig
  -> Bool
  -> LayerState
  -> LayerTape
  -> BatchRep
  -> Int
  -> IO (Either Text (LayerState, BatchRep))
backwardLayer device optimizerConfig needInputGradient state tape upstream batchN =
  case (state, tape, upstream) of
    (DenseState name params adam, DenseTape xs, FlatBatch dys) -> do
      result <- deviceGradientStep device optimizerConfig needInputGradient params adam xs dys batchN
      pure (fmap (\(params', adam', dxs) -> (DenseState name params' adam', FlatBatch dxs)) result)
    (ResidualState name scale params adam, ResidualTape xs, FlatBatch dys) -> do
      let residualDys = fmap (VU.map (* scale)) dys
      result <-
        deviceGradientStep device optimizerConfig needInputGradient params adam xs residualDys batchN
      pure $
        fmap
          ( \(params', adam', dxs) ->
              ( ResidualState name scale params' adam'
              , FlatBatch (zipWith addVec dys dxs)
              )
          )
          result
    (ResidualState name scale params adam, ResidualTape xs, TokenBatch dysBySample) -> do
      let flatDys = concat dysBySample
          residualDys = fmap (VU.map (* scale)) flatDys
      result <-
        deviceGradientStep device optimizerConfig needInputGradient params adam xs residualDys batchN
      pure $
        fmap
          ( \(params', adam', dxs) ->
              let flatCombined = zipWith addVec flatDys dxs
               in ( ResidualState name scale params' adam'
                  , TokenBatch (unflattenBy (fmap length dysBySample) flatCombined)
                  )
          )
          result
    (LayerNormState name, LayerNormTape normalized, TokenBatch dysBySample) ->
      pure
        ( Right
            ( LayerNormState name
            , TokenBatch (zipWith (zipWith layerNormBackward) normalized dysBySample)
            )
        )
    ( TokenMixingState name expectedTokens params adam
      , TokenMixingTape width channelInputs
      , TokenBatch dysBySample
      ) ->
        case tokenMixingGradientsExact
          name
          expectedTokens
          width
          channelInputs
          dysBySample of
          Left err -> pure (Left err)
          Right channelDys -> do
            result <-
              deviceGradientStep
                device
                optimizerConfig
                True
                params
                adam
                (concat channelInputs)
                (concat channelDys)
                batchN
            pure $ do
              (params', adam', channelDxsFlat) <- result
              channelDxs <-
                unflattenByExact
                  (name <> ": token-mixing backward device input gradients")
                  (fmap length channelInputs)
                  channelDxsFlat
              mixerTokenDxs <-
                tokenMixingOutputsExact name expectedTokens width channelDxs
              Right
                ( TokenMixingState name expectedTokens params' adam'
                , TokenBatch mixerTokenDxs
                )
    (PatchState name runtime params adam, PatchTape patchesBySample, TokenBatch tokenDys) -> do
      let flatPatches = concat patchesBySample
          flatDys = concat tokenDys
      result <-
        deviceGradientStep device optimizerConfig needInputGradient params adam flatPatches flatDys batchN
      pure $
        fmap
          ( \(params', adam', patchDxs) ->
              let dxs =
                    scatterPatchGradients
                      runtime
                      (fmap length patchesBySample)
                      patchDxs
               in (PatchState name runtime params' adam', FlatBatch dxs)
          )
          result
    (AttentionState name params adam, AttentionTape attended, TokenBatch dysBySample) -> do
      case zipExact (name <> ": attention backward sample count") attended dysBySample of
        Left err -> pure (Left err)
        Right samplePairs ->
          case traverse (uncurry (attentionBackward name)) samplePairs of
            Left err -> pure (Left err)
            Right back -> do
              let tokenInputs = concatMap (fmap tokenInput) attended
                  qkvDys = concatMap fst back
                  zeroDirectTokenDxs = fmap snd back
              result <-
                deviceGradientStep device optimizerConfig True params adam tokenInputs qkvDys batchN
              pure $ do
                (params', adam', tokenDxsFromQkv) <- result
                qkvGrouped <-
                  unflattenByExact
                    (name <> ": attention backward QKV input gradients")
                    (fmap length attended)
                    tokenDxsFromQkv
                combined <-
                  addTokenBatchesExact
                    (name <> ": attention backward input-gradient components")
                    zeroDirectTokenDxs
                    qkvGrouped
                Right (AttentionState name params' adam', TokenBatch combined)
    (MeanPoolState name, MeanPoolTape counts, FlatBatch dys) ->
      pure $ do
        if null counts
          then Left (name <> ": mean-pool backward has no recorded samples")
          else Right ()
        countGradientPairs <-
          zipExact (name <> ": mean-pool backward sample count") counts dys
        expanded <- traverse (uncurry (expandMeanPoolGradient name)) countGradientPairs
        Right (MeanPoolState name, TokenBatch expanded)
    _ -> pure (Left "backwardLayer: layer/tape/upstream shape mismatch")

deviceGradientStep
  :: MlpDevice
  -> OptimizerConfig
  -> Bool
  -> MlpParams
  -> AdamState
  -> [Vector Double]
  -> [Vector Double]
  -> Int
  -> IO (Either Text (MlpParams, AdamState, [Vector Double]))
deviceGradientStep device optimizerConfig needInputGradient params adam xs dys batchN
  | length xs /= length dys =
      pure (Left "deviceGradientStep: input/gradient batch size mismatch")
  -- @batchN@ is the outer example count used to average the loss gradient.
  -- Patch, token, and channel layers legitimately expand each example into
  -- multiple device rows, so it need not equal @length xs@.
  | batchN <= 0 = pure (Left "deviceGradientStep: batch size must be positive")
  | otherwise = do
      dxE <-
        if needInputGradient
          then mlpdInputGradientBatch device params (zip xs dys)
          else pure (Right [])
      gradE <- mlpdBatchGradient device params (zip xs dys)
      pure $ do
        dxs <- dxE
        grad <- gradE
        let meanGrad = scaleMlpGradient (1.0 / fromIntegral batchN) grad
            (params', adam') = applyOptimizer optimizerConfig adam params meanGrad
        Right (params', adam', dxs)

applyOptimizer
  :: OptimizerConfig -> AdamState -> MlpParams -> MlpGradient -> (MlpParams, AdamState)
applyOptimizer optimizer adam params gradient =
  case optimizer of
    AdamOptimizer config -> adamStep config adam params gradient
    AdamWOptimizer config weightDecay ->
      let (adamParams, adam') = adamStep config adam params gradient
          decay = max 0.0 (1.0 - adamLearningRate config * weightDecay)
       in ( decayMlpWeights decay adamParams
          , adam'
          )
    SgdOptimizer learningRate ->
      ( applySgd learningRate params gradient
      , adam
      )

decayMlpWeights :: Double -> MlpParams -> MlpParams
decayMlpWeights factor params =
  params
    { paramW1 = VU.map (* factor) (paramW1 params)
    , paramW2 = VU.map (* factor) (paramW2 params)
    }

applySgd :: Double -> MlpParams -> MlpGradient -> MlpParams
applySgd learningRate params gradient =
  params
    { paramW1 = descend (paramW1 params) (gradW1 gradient)
    , paramB1 = descend (paramB1 params) (gradB1 gradient)
    , paramW2 = descend (paramW2 params) (gradW2 gradient)
    , paramB2 = descend (paramB2 params) (gradB2 gradient)
    }
 where
  descend = VU.zipWith (\value grad -> value - learningRate * grad)

classifierOutputGradient :: Int -> Vector Double -> Int -> Vector Double
classifierOutputGradient numClasses outputVec label =
  let logits = VU.take numClasses outputVec
      probs = softmax logits
      dLogits =
        VU.imap
          (\i p -> p - if i == label then 1.0 else 0.0)
          probs
      tailCount = max 0 (VU.length outputVec - numClasses)
   in dLogits VU.++ VU.replicate tailCount 0.0

scaleMlpGradient :: Double -> MlpGradient -> MlpGradient
scaleMlpGradient s grad =
  MlpGradient
    { gradW1 = VU.map (* s) (gradW1 grad)
    , gradB1 = VU.map (* s) (gradB1 grad)
    , gradW2 = VU.map (* s) (gradW2 grad)
    , gradB2 = VU.map (* s) (gradB2 grad)
    }

validateAttentionInputs :: Text -> MlpParams -> [[Vector Double]] -> Either Text ()
validateAttentionInputs name params samples = do
  width <- validateTokenBatch (name <> ": attention inputs") Nothing samples
  let shape = paramShape params
  if mlpInputs shape /= width
    then
      Left
        ( name
            <> ": attention parameter input width mismatch (tokens="
            <> showText width
            <> ", parameters="
            <> showText (mlpInputs shape)
            <> ")"
        )
    else Right ()
  if mlpOutputs shape /= width * 3
    then
      Left
        ( name
            <> ": attention parameter output width mismatch (expected="
            <> showText (width * 3)
            <> ", actual="
            <> showText (mlpOutputs shape)
            <> ")"
        )
    else Right ()

attentionForward
  :: Text
  -> [Vector Double]
  -> [Vector Double]
  -> Either Text [AttentionToken]
attentionForward name inputs qkvs = do
  width <- validateTokenBatch (name <> ": attention sample inputs") Nothing [inputs]
  inputQkvPairs <-
    zipExact (name <> ": attention sample input/QKV count") inputs qkvs
  triples <-
    traverse
      (\(_, qkv) -> splitQkvExact name width qkv)
      inputQkvPairs
  let qs = fmap first3 triples
      ks = fmap second3 triples
      vs = fmap third3 triples
      scale = 1.0 / sqrt (fromIntegral width)
      weightsByToken =
        [ softmax (VU.fromList [dot q k * scale | k <- ks])
        | q <- qs
        ]
      outputs =
        [ weightedSum weights vs
        | weights <- weightsByToken
        ]
  buildAttentionTokens name inputs qs ks vs weightsByToken outputs
 where
  first3 (a, _, _) = a
  second3 (_, b, _) = b
  third3 (_, _, c) = c

buildAttentionTokens
  :: Text
  -> [Vector Double]
  -> [Vector Double]
  -> [Vector Double]
  -> [Vector Double]
  -> [Vector Double]
  -> [Vector Double]
  -> Either Text [AttentionToken]
buildAttentionTokens _ [] [] [] [] [] [] = Right []
buildAttentionTokens name (input : inputs) (q : qs) (k : ks) (v : vs) (weights : weightsByToken) (output : outputs) = do
  rest <- buildAttentionTokens name inputs qs ks vs weightsByToken outputs
  Right
    ( AttentionToken
        { tokenInput = input
        , tokenQ = q
        , tokenK = k
        , tokenV = v
        , tokenWeights = weights
        , tokenOutput = output
        }
        : rest
    )
buildAttentionTokens name _ _ _ _ _ _ =
  Left (name <> ": attention internal component-count mismatch")

attentionOutput :: AttentionToken -> Vector Double
attentionOutput = tokenOutput

attentionBackward
  :: Text
  -> [AttentionToken]
  -> [Vector Double]
  -> Either Text ([Vector Double], [Vector Double])
attentionBackward name tokens dzs = do
  tokenGradientPairs <-
    zipExact (name <> ": attention backward token/gradient count") tokens dzs
  case tokens of
    [] -> Left (name <> ": attention backward received an empty token sample")
    firstToken : _ -> do
      let width = VU.length (tokenInput firstToken)
          n = length tokens
      if width <= 0
        then Left (name <> ": attention backward token width must be positive")
        else Right ()
      mapM_
        (uncurry (validateAttentionBackwardToken name n width))
        (zip [0 :: Int ..] tokenGradientPairs)
      let qs = VB.fromList (fmap tokenQ tokens)
          ks = VB.fromList (fmap tokenK tokens)
          vs = VB.fromList (fmap tokenV tokens)
          weightsByToken = VB.fromList (fmap tokenWeights tokens)
          dzsVector = VB.fromList dzs
          scale = 1.0 / sqrt (fromIntegral width)
          dV =
            VB.generate n $ \j ->
              VU.generate width $ \d ->
                sum
                  [ (weightsByToken VB.! i VU.! j) * (dzsVector VB.! i VU.! d)
                  | i <- [0 .. n - 1]
                  ]
          dScores =
            VB.generate n $ \i ->
              let weights = weightsByToken VB.! i
                  dA =
                    VU.generate n $ \j ->
                      dot (dzsVector VB.! i) (vs VB.! j)
                  weightedMean = VU.sum (VU.zipWith (*) weights dA)
               in VU.imap (\j w -> w * ((dA VU.! j) - weightedMean)) weights
          dQ =
            VB.generate n $ \i ->
              VU.generate width $ \d ->
                sum
                  [ (dScores VB.! i VU.! j) * (ks VB.! j VU.! d) * scale
                  | j <- [0 .. n - 1]
                  ]
          dK =
            VB.generate n $ \j ->
              VU.generate width $ \d ->
                sum
                  [ (dScores VB.! i VU.! j) * (qs VB.! i VU.! d) * scale
                  | i <- [0 .. n - 1]
                  ]
          dQkv =
            VB.toList $ VB.generate n $ \index ->
              concat3 (dQ VB.! index) (dK VB.! index) (dV VB.! index)
          directInputDxs = replicate n (VU.replicate width 0.0)
      -- The current compact attention executable has no outer residual branch.
      -- Its input gradient therefore comes exclusively from the QKV projection;
      -- the explicit zero term keeps the strict component-count validation in
      -- the caller without pulling Sprint 23.1's residual correction forward.
      Right (dQkv, directInputDxs)

validateAttentionBackwardToken
  :: Text
  -> Int
  -> Int
  -> Int
  -> (AttentionToken, Vector Double)
  -> Either Text ()
validateAttentionBackwardToken name tokenCount width index (token, dz) = do
  requireVectorWidth name "input" index width (tokenInput token)
  requireVectorWidth name "query" index width (tokenQ token)
  requireVectorWidth name "key" index width (tokenK token)
  requireVectorWidth name "value" index width (tokenV token)
  requireVectorWidth name "output" index width (tokenOutput token)
  requireVectorWidth name "upstream gradient" index width dz
  requireVectorWidth name "attention weights" index tokenCount (tokenWeights token)

splitQkvExact
  :: Text
  -> Int
  -> Vector Double
  -> Either Text (Vector Double, Vector Double, Vector Double)
splitQkvExact name width vector
  | VU.length vector /= width * 3 =
      Left
        ( name
            <> ": attention QKV width mismatch (expected="
            <> showText (width * 3)
            <> ", actual="
            <> showText (VU.length vector)
            <> ")"
        )
  | otherwise =
      Right
        ( VU.slice 0 width vector
        , VU.slice width width vector
        , VU.slice (2 * width) width vector
        )

concat3 :: Vector Double -> Vector Double -> Vector Double -> Vector Double
concat3 a b c = a VU.++ b VU.++ c

layerNormEpsilon :: Double
layerNormEpsilon = 1.0e-5

layerNormForward :: Vector Double -> LayerNormToken
layerNormForward input =
  let width = max 1 (VU.length input)
      mean = VU.sum input / fromIntegral width
      centered = VU.map (subtract mean) input
      variance = VU.sum (VU.map (\x -> x * x) centered) / fromIntegral width
      invStd = 1.0 / sqrt (variance + layerNormEpsilon)
      output = VU.map (* invStd) centered
   in LayerNormToken
        { layerNormInvStd = invStd
        , layerNormOutput = output
        }

layerNormBackward :: LayerNormToken -> Vector Double -> Vector Double
layerNormBackward token dy =
  let output = layerNormOutput token
      width = max 1 (VU.length output)
      meanDy = VU.sum dy / fromIntegral width
      meanDyY = VU.sum (VU.zipWith (*) dy output) / fromIntegral width
      invStd = layerNormInvStd token
   in VU.zipWith
        (\dyI yI -> invStd * (dyI - meanDy - yI * meanDyY))
        dy
        output

tokenMixingInputsExact
  :: Text
  -> Int
  -> MlpParams
  -> [[Vector Double]]
  -> Either Text (Int, [[Vector Double]])
tokenMixingInputsExact name expectedTokens params samples = do
  width <-
    validateTokenBatch
      (name <> ": token-mixing inputs")
      (Just expectedTokens)
      samples
  let shape = paramShape params
  if mlpInputs shape /= expectedTokens || mlpOutputs shape /= expectedTokens
    then
      Left
        ( name
            <> ": token-mixing parameter shape mismatch (expected="
            <> showText expectedTokens
            <> "->"
            <> showText expectedTokens
            <> ", actual="
            <> showText (mlpInputs shape)
            <> "->"
            <> showText (mlpOutputs shape)
            <> ")"
        )
    else Right ()
  let sampleChannels sample =
        [ VU.fromList [token VU.! channel | token <- sample]
        | channel <- [0 .. width - 1]
        ]
  Right (width, fmap sampleChannels samples)

tokenMixingOutputsExact
  :: Text
  -> Int
  -> Int
  -> [[Vector Double]]
  -> Either Text [[Vector Double]]
tokenMixingOutputsExact name expectedTokens width channelSamples
  | null channelSamples =
      Left (name <> ": token-mixing channel batch is empty")
  | width <= 0 =
      Left (name <> ": token-mixing channel width must be positive")
  | otherwise = do
      mapM_
        validateChannelSample
        (zip [0 :: Int ..] channelSamples)
      Right (fmap transposeChannels channelSamples)
 where
  validateChannelSample (sampleIndex, channels)
    | length channels /= width =
        Left
          ( name
              <> ": token-mixing channel count mismatch at sample "
              <> showText sampleIndex
              <> " (expected="
              <> showText width
              <> ", actual="
              <> showText (length channels)
              <> ")"
          )
    | otherwise =
        mapM_
          ( \(channelIndex, channel) ->
              requireVectorWidth
                name
                "token-mixing channel"
                (sampleIndex * width + channelIndex)
                expectedTokens
                channel
          )
          (zip [0 :: Int ..] channels)
  transposeChannels channels =
    [ VU.fromList [channel VU.! tokenIndex | channel <- channels]
    | tokenIndex <- [0 .. expectedTokens - 1]
    ]

tokenMixingGradientsExact
  :: Text
  -> Int
  -> Int
  -> [[Vector Double]]
  -> [[Vector Double]]
  -> Either Text [[Vector Double]]
tokenMixingGradientsExact name expectedTokens width channelInputs dysBySample = do
  upstreamWidth <-
    validateTokenBatch
      (name <> ": token-mixing backward upstream")
      (Just expectedTokens)
      dysBySample
  if upstreamWidth /= width
    then
      Left
        ( name
            <> ": token-mixing backward width mismatch (tape="
            <> showText width
            <> ", upstream="
            <> showText upstreamWidth
            <> ")"
        )
    else Right ()
  _ <- tokenMixingOutputsExact name expectedTokens width channelInputs
  _ <-
    zipExact
      (name <> ": token-mixing backward sample count")
      channelInputs
      dysBySample
  Right
    ( fmap
        ( \tokens ->
            [ VU.fromList [token VU.! channel | token <- tokens]
            | channel <- [0 .. width - 1]
            ]
        )
        dysBySample
    )

patchPositions :: ImageGeometry -> Int -> Int -> [[Int]]
patchPositions geometry size stride =
  [ [ pixelIndex geometry (x + dx) (y + dy) c
    | dy <- [0 .. size - 1]
    , dx <- [0 .. size - 1]
    , c <- [0 .. geomChannels geometry - 1]
    ]
  | y <- takeWhile (<= geomHeight geometry - size) [0, stride ..]
  , x <- takeWhile (<= geomWidth geometry - size) [0, stride ..]
  ]

extractPatches :: PatchRuntime -> Vector Double -> [Vector Double]
extractPatches runtime input =
  [ VU.fromList
      ( [ if idx < VU.length input then input VU.! idx else 0.0
        | idx <- indices
        ]
          <> patchPositionFeatures runtime indices
      )
  | indices <- patchRuntimePositions runtime
  ]

patchPositionFeatures :: PatchRuntime -> [Int] -> [Double]
patchPositionFeatures runtime indices =
  case indices of
    [] -> [0.0, 0.0]
    firstIdx : _ ->
      let geometry = patchRuntimeGeometry runtime
          pixel = firstIdx `div` max 1 (geomChannels geometry)
          x = pixel `mod` max 1 (geomWidth geometry)
          y = pixel `div` max 1 (geomWidth geometry)
          norm coordinate extent =
            if extent <= 1
              then 0.0
              else (fromIntegral coordinate / fromIntegral (extent - 1)) * 2.0 - 1.0
       in [norm x (geomWidth geometry), norm y (geomHeight geometry)]

scatterPatchGradients :: PatchRuntime -> [Int] -> [Vector Double] -> [Vector Double]
scatterPatchGradients runtime counts patchDxs =
  fmap scatterOne (unflattenBy counts patchDxs)
 where
  inputCount = patchRuntimeInputCount runtime
  positions = patchRuntimePositions runtime
  scatterOne dxs =
    VU.accum (+) (VU.replicate inputCount 0.0) $
      concat
        [ [ (idx, dx VU.! offset)
          | (offset, idx) <- zip [0 ..] indices
          , idx < inputCount
          , offset < VU.length dx
          ]
        | (indices, dx) <- zip positions dxs
        ]

pixelIndex :: ImageGeometry -> Int -> Int -> Int -> Int
pixelIndex geometry x y c =
  ((y * geomWidth geometry) + x) * geomChannels geometry + c

geometryForInput :: Int -> ImageGeometry
geometryForInput inputs
  | inputs == 784 = ImageGeometry 28 28 1
  | inputs == 3072 = ImageGeometry 32 32 3
  | inputs == 12288 = ImageGeometry 64 64 3
  | side * side == inputs = ImageGeometry side side 1
  | otherwise = ImageGeometry inputs 1 1
 where
  side = floor (sqrt (fromIntegral inputs :: Double))

patchSide :: ImageGeometry -> Int
patchSide geometry
  | geomHeight geometry <= 1 = 1
  | geomWidth geometry <= 2 = geomWidth geometry
  | geomWidth geometry <= 8 = 2
  | geomWidth geometry <= 32 = 4
  | otherwise = 8

residualPatchSide :: ImageGeometry -> Int
residualPatchSide geometry
  | geomHeight geometry <= 1 = 1
  | geomWidth geometry <= 2 = geomWidth geometry
  | geomWidth geometry <= 8 = 2
  | geomWidth geometry <= 28 = 7
  | geomWidth geometry <= 32 = 8
  | otherwise = 16

vitPatchSide :: ImageGeometry -> Int
vitPatchSide geometry
  -- Four 16x16 tokens leave the bounded CIFAR product row with almost no
  -- spatial sequence to mix, while the diagnostic 8x8/16-token correction
  -- remained below the frozen held-out bar.  The standard 4x4 CIFAR patch
  -- yields 64 tokens and reduces the data-limited patch projection from 770 to
  -- 50 inputs while keeping the exact five-epoch / forty-update product budget
  -- unchanged.  The later literal-architecture phase still owns replacing
  -- this executable Mixer approximation with the single typed ViT graph.
  | geomWidth geometry >= 32 = 4
  | otherwise = patchSide geometry

meanVectorExact :: Text -> [Vector Double] -> Either Text (Vector Double)
meanVectorExact name vectors = do
  width <- validateTokenBatch (name <> ": mean-pool sample") Nothing [vectors]
  let summed = List.foldl' addVec (VU.replicate width 0.0) vectors
  Right (VU.map (/ fromIntegral (length vectors)) summed)

expandMeanPoolGradient
  :: Text
  -> Int
  -> Vector Double
  -> Either Text [Vector Double]
expandMeanPoolGradient name tokenCount dy
  | tokenCount <= 0 =
      Left (name <> ": mean-pool backward token count must be positive")
  | VU.null dy =
      Left (name <> ": mean-pool backward gradient width must be positive")
  | otherwise =
      Right (replicate tokenCount (VU.map (/ fromIntegral tokenCount) dy))

validateTokenBatch
  :: Text
  -> Maybe Int
  -> [[Vector Double]]
  -> Either Text Int
validateTokenBatch label expectedTokenCount samples =
  case samples of
    [] -> Left (label <> ": batch is empty")
    [] : _ -> Left (label <> ": sample 0 has no tokens")
    (firstToken : _) : _ -> do
      let width = VU.length firstToken
      if width <= 0
        then Left (label <> ": token width must be positive")
        else Right ()
      mapM_ (validateSample width) (zip [0 :: Int ..] samples)
      Right width
 where
  validateSample width (sampleIndex, tokens)
    | null tokens =
        Left
          ( label
              <> ": sample "
              <> showText sampleIndex
              <> " has no tokens"
          )
    | Just expected <- expectedTokenCount
    , length tokens /= expected =
        Left
          ( label
              <> ": token count mismatch at sample "
              <> showText sampleIndex
              <> " (expected="
              <> showText expected
              <> ", actual="
              <> showText (length tokens)
              <> ")"
          )
    | otherwise =
        mapM_
          ( \(tokenIndex, token) ->
              requireVectorWidth
                label
                ("token in sample " <> showText sampleIndex)
                tokenIndex
                width
                token
          )
          (zip [0 :: Int ..] tokens)

requireVectorWidth
  :: Text
  -> Text
  -> Int
  -> Int
  -> Vector Double
  -> Either Text ()
requireVectorWidth label role index expected vector
  | VU.length vector == expected = Right ()
  | otherwise =
      Left
        ( label
            <> ": "
            <> role
            <> " width mismatch at index "
            <> showText index
            <> " (expected="
            <> showText expected
            <> ", actual="
            <> showText (VU.length vector)
            <> ")"
        )

zipExact :: Text -> [a] -> [b] -> Either Text [(a, b)]
zipExact label left right
  | leftCount /= rightCount =
      Left
        ( label
            <> " mismatch (left="
            <> showText leftCount
            <> ", right="
            <> showText rightCount
            <> ")"
        )
  | otherwise = Right (zip left right)
 where
  leftCount = length left
  rightCount = length right

addVecExact
  :: Text
  -> Vector Double
  -> Vector Double
  -> Either Text (Vector Double)
addVecExact label left right
  | VU.length left /= VU.length right =
      Left
        ( label
            <> " vector width mismatch (left="
            <> showText (VU.length left)
            <> ", right="
            <> showText (VU.length right)
            <> ")"
        )
  | otherwise = Right (VU.zipWith (+) left right)

addTokenBatchesExact
  :: Text
  -> [[Vector Double]]
  -> [[Vector Double]]
  -> Either Text [[Vector Double]]
addTokenBatchesExact label left right = do
  samplePairs <- zipExact (label <> " sample count") left right
  traverse addSample (zip [0 :: Int ..] samplePairs)
 where
  addSample (sampleIndex, (leftTokens, rightTokens)) = do
    tokenPairs <-
      zipExact
        (label <> " token count at sample " <> showText sampleIndex)
        leftTokens
        rightTokens
    traverse
      ( \(tokenIndex, (leftToken, rightToken)) ->
          addVecExact
            ( label
                <> " at sample "
                <> showText sampleIndex
                <> ", token "
                <> showText tokenIndex
            )
            leftToken
            rightToken
      )
      (zip [0 :: Int ..] tokenPairs)

addVec :: Vector Double -> Vector Double -> Vector Double
addVec = VU.zipWith (+)

dot :: Vector Double -> Vector Double -> Double
dot a b = VU.sum (VU.zipWith (*) a b)

weightedSum :: Vector Double -> [Vector Double] -> Vector Double
weightedSum weights vectors =
  case vectors of
    [] -> VU.empty
    first : _ ->
      let vectorsVector = VB.fromList vectors
       in VU.generate (VU.length first) $ \d ->
            sum
              [ (weights VU.! i) * (vectorsVector VB.! i VU.! d)
              | i <- [0 .. VB.length vectorsVector - 1]
              ]

unflattenBy :: [Int] -> [a] -> [[a]]
unflattenBy counts values =
  case counts of
    [] -> []
    n : ns ->
      let (chunk, rest) = splitAt n values
       in chunk : unflattenBy ns rest

unflattenByExact :: Text -> [Int] -> [a] -> Either Text [[a]]
unflattenByExact label counts values
  | any (< 0) counts = Left (label <> ": negative group size")
  | expected /= actual =
      Left
        ( label
            <> " count mismatch (expected="
            <> showText expected
            <> ", actual="
            <> showText actual
            <> ")"
        )
  | otherwise = Right (unflattenBy counts values)
 where
  expected = sum counts
  actual = length values

clamp :: Int -> Int -> Int -> Int
clamp lo hi value = max lo (min hi value)

isFiniteDouble :: Double -> Bool
isFiniteDouble value = not (isNaN value || isInfinite value)

showText :: (Show a) => a -> Text
showText = Text.pack . show

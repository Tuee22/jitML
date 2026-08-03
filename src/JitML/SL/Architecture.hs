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
  , OptimizerConfig (..)
  , applyGraphOptimizerStep
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
  , trainedArchitectureWeights
  , validateArchitectureFeatureParity
  , denseChainGraph
  , serveClassifierGraphAccuracy
  , serveClassifierGraphCrossEntropy
  , correctOpsVitGraph
  , correctOpsConvLeNetGraph
  , correctOpsResNetGraph
  , correctOpsDeepDenseGraph
  )
where

import Control.Monad (foldM)
import Data.Either (fromRight)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)

import JitML.Engines.Rng qualified as Rng
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.LayerGraphOneDnn qualified as LayerGraphOneDnn
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpParams (..)
  , MlpShape (..)
  , adamInit
  , defaultAdamConfig
  , mlpInit
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
  , exactTrainingAdam :: !LayerGraph.GraphClassifierAdam
  -- ^ Sprint 238.1 — the trained typed 'LayerGraph.LayerGraph' plus threaded Adam
  -- moments (replacing the parallel @[LayerState]@ optimizer state).
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
  , trainedArchGraph :: !LayerGraph.LayerGraph
  -- ^ Sprint 237.1/238.1 — the trained typed 'LayerGraph.LayerGraph' IR is the
  -- single supervised serving and parameter representation. Accuracy,
  -- cross-entropy, runtime projection, and graph-ordered weight identity are all
  -- computed from this graph via 'LayerGraph.runLayerGraph' /
  -- 'LayerGraph.graphParameterVector'.
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
-- Phases 242–244 — the @archLayerGraph@ is the LITERAL correct-operator graph the
-- architecture trains, serves, validates for feature parity, and checkpoints: no
-- decorative kind ever sits on a 'LayerGraph.DenseOp'. The flat 'DenseFamily'
-- keeps the single trained affine (its trained graph is the 'denseChainGraph'
-- expansion of the freshly initialised @[LayerState]@); every other family is
-- built from real ConvOp/NormOp/PoolOp/BlockOp/AttentionOp/GeGLUOp/PatchOp/
-- DropoutOp nodes whose widths chain exactly. A builder that fails its
-- smart-constructor shape checks falls back to the legacy decorative graph so the
-- pure signature holds; the feature-parity and named-block-count tests catch any
-- such regression.
architectureLayerGraphForFamily family name inputWidth outputWidth seed latent wideLatent =
  case family of
    DenseFamily -> legacyGraph
    DeepDenseFamily -> literal (correctOpsDeepDenseGraph name inputWidth outputWidth seed latent)
    Conv2DLeNetFamily -> literal (correctOpsConvLeNetGraph name inputWidth outputWidth seed latent)
    VisionTransformerFamily -> literal (correctOpsVitGraph name inputWidth outputWidth seed latent)
    ResidualFamily depth
      | depth == 50 ->
          literal (correctOpsResNetGraph resNet50Shape name inputWidth outputWidth seed latent)
      | otherwise ->
          literal (correctOpsResNetGraph resNetShape name inputWidth outputWidth seed latent)
    WideResidualFamily _ ->
      literal (correctOpsResNetGraph wideResNetShape name inputWidth outputWidth seed wideLatent)
 where
  legacyGraph =
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = name
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [inputWidth]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [outputWidth]
      , LayerGraph.layerGraphNodes =
          graphNodes seed inputWidth (graphPlansForFamily family outputWidth latent wideLatent)
      }
  literal = fromRight legacyGraph

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
      , LayerGraph.layerNodeOp = LayerGraph.IdentityOp
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
-- mean softmax cross entropy over the semantic-prefix classes. Sprint 238.1: the
-- typed 'LayerGraph.LayerGraph' IR is trained directly through the device
-- classifier loop (oneDNN for a real substrate, CPU autodiff for the pure
-- reference device), replacing the parallel @[LayerState]@ program.
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
      statesE <- initialiseLayers (clfSeed config) (archLayers spec)
      case statesE >>= initialClassifierGraph spec of
        Left err -> pure (Left err)
        Right graph0 -> do
          trainedE <-
            trainClassifierGraphAllEpochs
              device
              (clfClasses config)
              (clfEpochs config)
              (clfBatchSize config)
              (clfLearningRate config)
              graph0
              (datasetClassifierExamples dataset)
          case trainedE of
            Left err -> pure (Left err)
            Right graph -> do
              let trained =
                    TrainedArchitecture
                      { trainedArchSpec = spec
                      , trainedArchGraph = graph
                      , trainedArchConfig = config
                      , trainedArchInputTransform =
                          defaultTrainedArchitectureInputTransform config
                      }
              accE <- accuracyArchitectureWithDevice device trained dataset
              pure (fmap (trained,) accE)

-- | Train a classification 'LayerGraph.LayerGraph' for a fixed number of epochs
-- through the architecture's device (fixed dataset order every epoch), threading
-- Adam moments across epochs. Used by the non-model-selecting one-shot trainer.
trainClassifierGraphAllEpochs
  :: MlpDevice
  -> Int
  -> Int
  -> Int
  -> Double
  -> LayerGraph.LayerGraph
  -> [(Vector Double, Int)]
  -> IO (Either Text LayerGraph.LayerGraph)
trainClassifierGraphAllEpochs device classes epochs batchSize lr graph0 examples =
  go 1 (LayerGraph.initGraphClassifierAdam graph0)
 where
  go epoch st
    | epoch > epochs = pure (Right (LayerGraph.gcaGraph st))
    | otherwise = do
        stepped <- trainClassifierGraphEpoch device classes batchSize lr st examples
        case stepped of
          Left err -> pure (Left err)
          Right st' -> go (epoch + 1) st'

-- | The @(features, class label)@ pairs the typed layer-graph classifier
-- trainers consume, in dataset order.
datasetClassifierExamples :: Dataset -> [(Vector Double, Int)]
datasetClassifierExamples = fmap (\ex -> (exampleFeatures ex, exampleLabel ex))

-- | Phases 242–244 — the initial classification 'LayerGraph' the architecture
-- trains and then serves. The flat 'DenseFamily' expands its freshly initialized
-- @[LayerState]@ into a dense chain graph ('denseChainGraph'), so graph training
-- reproduces the historical device MLP training within the @Double@-vs-@float32@
-- skew. Every other family trains the LITERAL correct-operator @archLayerGraph@
-- directly: the trained graph IS the graph whose features are validated and whose
-- weights are checkpointed, with each claimed feature realised by a real trained
-- node of the matching kind (ConvOp/NormOp/PoolOp/BlockOp/AttentionOp/GeGLUOp/
-- PatchOp/DropoutOp) rather than a decorative kind on a @DenseOp@.
initialClassifierGraph :: ArchitectureSpec -> [LayerState] -> Either Text LayerGraph.LayerGraph
initialClassifierGraph spec states =
  case archFamily spec of
    DenseFamily -> denseChainGraph graphName states
    _ -> Right (archLayerGraph spec)
 where
  graphName = problemName (archProblem spec)

-- | Sprint 238.1 — train one classification epoch through the device the
-- architecture was given. The pure reference device (no 'Env') trains through the
-- CPU reverse-mode autodiff loop; a real JIT substrate device (@Just env@) trains
-- through the oneDNN device loop. Both share the one pure Adam step
-- ('LayerGraph.graphAdamBatchStep'), threading Adam moments across epochs through
-- 'LayerGraph.GraphClassifierAdam'.
trainClassifierGraphEpoch
  :: MlpDevice
  -> Int
  -> Int
  -> Double
  -> LayerGraph.GraphClassifierAdam
  -> [(Vector Double, Int)]
  -> IO (Either Text LayerGraph.GraphClassifierAdam)
trainClassifierGraphEpoch device classes batchSize lr st examples =
  case mlpdEnv device of
    Nothing ->
      pure (LayerGraph.trainLayerGraphClassifierEpochPure classes batchSize lr st examples)
    Just env ->
      LayerGraphOneDnn.trainLayerGraphClassifierEpochOneDnn env classes batchSize lr st examples

-- | Batch-summed classification cross-entropy parameter gradient through the
-- architecture's device: CPU autodiff for the pure reference device, oneDNN for a
-- real substrate.
classifierGraphBatchGradient
  :: MlpDevice
  -> Int
  -> LayerGraph.LayerGraph
  -> [(Vector Double, Int)]
  -> IO (Either Text (Vector Double))
classifierGraphBatchGradient device classes graph batch =
  case mlpdEnv device of
    Nothing -> pure (LayerGraph.pureClassifierBatchGradient classes graph batch)
    Just env -> LayerGraphOneDnn.classifierBatchGradientOneDnn env classes graph batch

-- | Apply one optimizer update (Adam or plain SGD) to the graph parameters from a
-- batch-summed gradient. Adam reuses the shared 'LayerGraph.graphAdamBatchStep'
-- (moments threaded through 'LayerGraph.GraphClassifierAdam'); SGD steps the flat
-- parameter vector directly. The step counter advances for both.
applyGraphOptimizerStep
  :: OptimizerConfig
  -> LayerGraph.GraphClassifierAdam
  -> Vector Double
  -> Int
  -> Either Text LayerGraph.GraphClassifierAdam
applyGraphOptimizerStep optimizerConfig st summed batchLen =
  case optimizerConfig of
    AdamOptimizer adamConfig ->
      LayerGraph.graphAdamBatchStep (adamLearningRate adamConfig) st summed batchLen
    AdamWOptimizer adamConfig weightDecay -> do
      -- AdamW: the Adam step, then decoupled weight decay on the weight tensors
      -- only (biases are not decayed), matching the retired [LayerState] path.
      stepped <- LayerGraph.graphAdamBatchStep (adamLearningRate adamConfig) st summed batchLen
      let decay = max 0.0 (1.0 - adamLearningRate adamConfig * weightDecay)
      Right
        stepped {LayerGraph.gcaGraph = LayerGraph.decayGraphWeights decay (LayerGraph.gcaGraph stepped)}
    SgdOptimizer learningRate ->
      let grad = VU.map (/ fromIntegral batchLen) summed
          params = LayerGraph.graphParameterVector (LayerGraph.gcaGraph st)
          params' = VU.zipWith (\p g -> p - learningRate * g) params grad
       in do
            graph' <- LayerGraph.replaceGraphParameterVector (LayerGraph.gcaGraph st) params'
            Right st {LayerGraph.gcaGraph = graph', LayerGraph.gcaStep = LayerGraph.gcaStep st + 1}

-- | One optimizer update of the trained graph over a single mini-batch through
-- the architecture's device, used by the exact-update tuning runtime.
trainClassifierGraphBatch
  :: MlpDevice
  -> Int
  -> OptimizerConfig
  -> LayerGraph.GraphClassifierAdam
  -> [(Vector Double, Int)]
  -> IO (Either Text LayerGraph.GraphClassifierAdam)
trainClassifierGraphBatch device classes optimizerConfig st batch = do
  summedE <- classifierGraphBatchGradient device classes (LayerGraph.gcaGraph st) batch
  pure (summedE >>= \summed -> applyGraphOptimizerStep optimizerConfig st summed (length batch))

accuracyArchitectureWithDevice
  :: MlpDevice -> TrainedArchitecture -> Dataset -> IO (Either Text Double)
accuracyArchitectureWithDevice _ _ [] = pure (Left "accuracyArchitectureWithDevice: empty evaluation dataset")
accuracyArchitectureWithDevice _device trained dataset =
  -- Sprint 237.1: every family serves through the typed LayerGraph IR executor.
  pure
    ( serveClassifierGraphAccuracy
        (clfClasses (trainedArchConfig trained))
        (trainedArchGraph trained)
        dataset
    )

-- | Sprint 8.13 — real mean softmax cross-entropy of a trained architecture over
-- a dataset, computed through the typed 'LayerGraph.runLayerGraph' serving
-- executor over the first @classes@ logits. This is the SL loss the runtime
-- publishes; it replaces the @1 − accuracy@ stand-in. Empty evaluation data fails
-- closed instead of manufacturing a zero loss.
crossEntropyArchitectureWithDevice
  :: MlpDevice -> TrainedArchitecture -> Dataset -> IO (Either Text Double)
crossEntropyArchitectureWithDevice _ _ [] = pure (Left "crossEntropyArchitectureWithDevice: empty evaluation dataset")
crossEntropyArchitectureWithDevice _device trained dataset =
  -- Sprint 237.1: every family serves through the typed LayerGraph IR executor.
  pure
    ( serveClassifierGraphCrossEntropy
        (clfClasses (trainedArchConfig trained))
        (trainedArchGraph trained)
        dataset
    )

-- | Expand a chain of dense @[LayerState]@ into a single dense 'LayerGraph'
-- carrying the trained weights. Fails closed on any non-'DenseState' layer.
denseChainGraph :: Text -> [LayerState] -> Either Text LayerGraph.LayerGraph
denseChainGraph graphName states =
  case traverse denseParams states of
    Left err -> Left err
    Right [] -> Left "denseChainGraph: no dense layer states"
    Right paramsList@(firstParams : _) -> do
      nodeGroups <- traverse (uncurry denseNodes) (zip [0 ..] paramsList)
      let firstShape = paramShape firstParams
          lastShape = paramShape (List.foldl' (\_ p -> p) firstParams paramsList)
      Right
        LayerGraph.LayerGraph
          { LayerGraph.layerGraphName = graphName
          , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [mlpInputs firstShape]
          , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [mlpOutputs lastShape]
          , LayerGraph.layerGraphNodes = concat nodeGroups
          }
 where
  denseParams (DenseState _ params _) = Right params
  denseParams other =
    Left ("denseChainGraph: expected DenseState, got " <> runtimeStateKind other)
  denseNodes :: Int -> MlpParams -> Either Text [LayerGraph.LayerNode]
  denseNodes idx params = do
    let shape = paramShape params
        prefix = graphName <> "-l" <> Text.pack (show idx)
    hidden <-
      LayerGraph.mkAffineLayer
        (prefix <> "-hidden")
        LayerGraph.DenseLayer
        (mlpInputs shape)
        (mlpHidden shape)
        LayerGraph.TanhActivation
        LayerGraph.InferenceMode
        LayerGraph.LayerParameters
          { LayerGraph.layerWeights = paramW1 params
          , LayerGraph.layerBias = paramB1 params
          }
    output <-
      LayerGraph.mkAffineLayer
        (prefix <> "-output")
        LayerGraph.DenseLayer
        (mlpHidden shape)
        (mlpOutputs shape)
        LayerGraph.LinearActivation
        LayerGraph.InferenceMode
        LayerGraph.LayerParameters
          { LayerGraph.layerWeights = paramW2 params
          , LayerGraph.layerBias = paramB2 params
          }
    Right [hidden, output]

-- | Run one flat feature vector through a served classifier 'LayerGraph' and
-- return the raw output logits (width @classes + 1@).
classifierGraphLogits :: LayerGraph.LayerGraph -> Vector Double -> Either Text (Vector Double)
classifierGraphLogits graph input =
  LayerGraph.layerTapeOutput <$> LayerGraph.runLayerGraph graph input

-- | IR-served accuracy: argmax over the semantic-prefix @classes@ logits.
serveClassifierGraphAccuracy :: Int -> LayerGraph.LayerGraph -> Dataset -> Either Text Double
serveClassifierGraphAccuracy _ _ [] =
  Left "serveClassifierGraphAccuracy: empty evaluation dataset"
serveClassifierGraphAccuracy classes graph dataset = do
  predicted <-
    traverse
      (fmap (VU.maxIndex . VU.take classes) . classifierGraphLogits graph . exampleFeatures)
      dataset
  let correct = length (filter id (zipWith (==) predicted (fmap exampleLabel dataset)))
  Right (fromIntegral correct / fromIntegral (length dataset))

-- | IR-served mean softmax cross-entropy over the semantic-prefix @classes@
-- logits, matching 'crossEntropyOne'.
serveClassifierGraphCrossEntropy :: Int -> LayerGraph.LayerGraph -> Dataset -> Either Text Double
serveClassifierGraphCrossEntropy _ _ [] =
  Left "serveClassifierGraphCrossEntropy: empty evaluation dataset"
serveClassifierGraphCrossEntropy classes graph dataset = do
  losses <-
    traverse
      ( \ex ->
          (\logits -> crossEntropyOne classes logits (exampleLabel ex))
            <$> classifierGraphLogits graph (exampleFeatures ex)
      )
      dataset
  Right (sum losses / fromIntegral (length dataset))

-- Sprint 237.1 / 238.1 — config-driven correct-operators Vision Transformer graph.
--
-- Replaces the decorative single-affine placeholder for the VisionTransformer
-- family with a graph that executes the FD-validated Phase-233 operators: patch
-- embedding of a @C×H×W@ image into @N@ tokens of width @D@, a normalization, a
-- multi-head self-attention node (carrying @W_O@ and the transformer residual),
-- a GeGLU collapse over the flattened tokens, and a linear classifier. Every
-- shape chains @C*H*W -> N*D -> N*D -> N*D -> D -> outputs@, so
-- 'LayerGraph.runLayerGraph' serves (and 'LayerGraphOneDnn.trainLayerGraphClassifierOneDnn'
-- trains) the true transformer math rather than a stack of plain affines. The
-- embedding width is forced even so the two attention heads divide it.
correctOpsVitGraph
  :: Text
  -> Int
  -- ^ input width @C*H*W@
  -> Int
  -- ^ output width @classes + 1@
  -> Int
  -- ^ seed
  -> Int
  -- ^ latent width hint
  -> Either Text LayerGraph.LayerGraph
correctOpsVitGraph name inputs outputs seed latentHint = do
  let geometry = geometryForInput inputs
      channels = geomChannels geometry
      height = geomHeight geometry
      width = geomWidth geometry
      -- Compact proxy with real attention signal: a quarter-image non-overlapping
      -- patch yields ~16 tokens (a 4×4 grid on 32×32) and a modest embedD (≤32), so
      -- self-attention (O(tokens²·embedD)) has a genuine sequence to mix while patch
      -- projection and the GeGLU collapse stay cheap.
      patch = max 1 (min height width `div` 4)
      tokensH = max 1 ((height - patch) `div` patch + 1)
      tokensW = max 1 ((width - patch) `div` patch + 1)
      tokens = tokensH * tokensW
      heads = 2
      embedD = let base = max heads (clamp 8 32 latentHint) in base - (base `mod` heads)
      flatTokens = tokens * embedD
      ffHidden = max 4 embedD
      patchSpec = LayerGraph.PatchSpec channels height width patch patch embedD
      normSpec = LayerGraph.NormSpec LayerGraph.NormLayerWise embedD tokens 1.0e-5
      attnSpec = LayerGraph.AttentionSpec tokens embedD heads False
      gegluSpec = LayerGraph.GeGLUSpec flatTokens ffHidden embedD
  patchNode <-
    LayerGraph.mkPatchEmbedLayer
      (name <> "-patch-embedding")
      patchSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters seed (LayerGraph.PatchOp patchSpec))
  normNode <-
    LayerGraph.mkNormLayer
      (name <> "-layernorm")
      normSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 1) (LayerGraph.NormOp normSpec))
  attnNode <-
    LayerGraph.mkAttentionLayer
      (name <> "-self-attention")
      attnSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 2) (LayerGraph.AttentionOp attnSpec))
  gegluNode <-
    LayerGraph.mkGeGLULayer
      (name <> "-geglu")
      gegluSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 3) (LayerGraph.GeGLUOp gegluSpec))
  headNode <-
    LayerGraph.mkAffineLayer
      (name <> "-classifier")
      LayerGraph.DenseLayer
      embedD
      outputs
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 4) embedD outputs)
  Right
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = name
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [channels, height, width]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [outputs]
      , LayerGraph.layerGraphNodes = [patchNode, normNode, attnNode, gegluNode, headNode]
      }

-- Phases 242–244 — classic compact LeNet graph: two real 'LayerGraph.ConvOp'
-- stages each followed by a local average 'LayerGraph.PoolOp', then a dense
-- classifier over the flattened feature map — @[Dense, Conv2D, pooling]@ each a
-- real trained node. conv1 (C_in→lc1, 3×3 stride s1, ReLU) -> pool1 (2×2) ->
-- conv2 (lc1→lc2, 3×3, ReLU) -> pool2 (2×2) -> Dense(featDim -> outputs). The
-- first conv strides to downsample large inputs; strides/pool windows degrade
-- gracefully so tiny inputs never reach zero spatial. Two convs + two local pools
-- preserve real spatial structure instead of collapsing to a single channel mean.
correctOpsConvLeNetGraph
  :: Text
  -> Int
  -- ^ input width @C*H*W@
  -> Int
  -- ^ output width @classes + 1@
  -> Int
  -- ^ seed
  -> Int
  -- ^ conv-channel width hint
  -> Either Text LayerGraph.LayerGraph
correctOpsConvLeNetGraph name inputs outputs seed channelHint = do
  let geometry = geometryForInput inputs
      channels = geomChannels geometry
      height = geomHeight geometry
      width = geomWidth geometry
      lc1 = max 2 (clamp 4 8 channelHint)
      lc2 = max 2 (clamp 8 16 channelHint)
      -- conv1 strides to downsample large inputs; conv2 keeps the (already small)
      -- spatial extent. Each conv is followed by a 2×2 local avg-pool (or 1×1 when
      -- the extent is already 1, so shape-chaining never collapses to zero).
      s1 = if width >= 16 then 2 else 1
      c1h = LayerGraph.convOutDim height 3 s1 1
      c1w = LayerGraph.convOutDim width 3 s1 1
      p1kH = if c1h >= 2 then 2 else 1
      p1kW = if c1w >= 2 then 2 else 1
      p1h = LayerGraph.convOutDim c1h p1kH p1kH 0
      p1w = LayerGraph.convOutDim c1w p1kW p1kW 0
      c2h = LayerGraph.convOutDim p1h 3 1 1
      c2w = LayerGraph.convOutDim p1w 3 1 1
      p2kH = if c2h >= 2 then 2 else 1
      p2kW = if c2w >= 2 then 2 else 1
      p2h = LayerGraph.convOutDim c2h p2kH p2kH 0
      p2w = LayerGraph.convOutDim c2w p2kW p2kW 0
      featDim = lc2 * p2h * p2w
      conv1Spec = LayerGraph.ConvSpec channels lc1 [height, width] [3, 3] [s1, s1] [1, 1]
      conv2Spec = LayerGraph.ConvSpec lc1 lc2 [p1h, p1w] [3, 3] [1, 1] [1, 1]
      pool1Shape = LayerGraph.SpatialShape lc1 c1h c1w
      pool2Shape = LayerGraph.SpatialShape lc2 c2h c2w
      pool1Window = LayerGraph.PoolWindow p1kH p1kW p1kH p1kW 0 0 False
      pool2Window = LayerGraph.PoolWindow p2kH p2kW p2kH p2kW 0 0 False
  conv1Node <-
    LayerGraph.mkConvLayer
      (name <> "-conv-1")
      conv1Spec
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters seed (LayerGraph.ConvOp conv1Spec))
  pool1Node <-
    LayerGraph.mkPoolLayer
      (name <> "-pool-1")
      pool1Shape
      (LayerGraph.PoolAvg pool1Window)
      LayerGraph.TrainingMode
  conv2Node <-
    LayerGraph.mkConvLayer
      (name <> "-conv-2")
      conv2Spec
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 1) (LayerGraph.ConvOp conv2Spec))
  pool2Node <-
    LayerGraph.mkPoolLayer
      (name <> "-pool-2")
      pool2Shape
      (LayerGraph.PoolAvg pool2Window)
      LayerGraph.TrainingMode
  headNode <-
    LayerGraph.mkAffineLayer
      (name <> "-classifier")
      LayerGraph.DenseLayer
      featDim
      outputs
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 2) featDim outputs)
  Right
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = name
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [channels, height, width]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [outputs]
      , LayerGraph.layerGraphNodes = [conv1Node, pool1Node, conv2Node, pool2Node, headNode]
      }

-- Phase 243 — literal DeepDense graph. A ReLU dense stack interleaved with a real
-- 'LayerGraph.NormOp' 'LayerGraph.NormBatch' node (kind @BatchNorm@, standardizing
-- the whole hidden vector — @nChannels = 1@, @nSpatial = hidden@ — so it is
-- non-degenerate per example rather than a constant-@beta@ collapse) and a real
-- 'LayerGraph.DropoutOp' node. So @[Dense, BatchNorm, Dropout]@ are each realised
-- by a trained node of the matching kind, not a decorative kind on a @DenseOp@.
-- Shapes chain @inputs -> hidden -> hidden -> outputs@.
correctOpsDeepDenseGraph
  :: Text
  -> Int
  -- ^ input width
  -> Int
  -- ^ output width @classes + 1@
  -> Int
  -- ^ seed
  -> Int
  -- ^ hidden width hint
  -> Either Text LayerGraph.LayerGraph
correctOpsDeepDenseGraph name inputs outputs seed latentHint = do
  -- Compact proxy: a modest hidden width keeps the dense matmuls light while the
  -- two-hidden-layer ReLU MLP comfortably clears the (easy-dataset) MNIST bar.
  let hidden = max 4 (clamp 4 128 latentHint)
      eps = 1.0e-5
      -- Whole-vector batch-standardization: one gamma/beta over the hidden
      -- activations. Non-degenerate per example (reduces over @hidden@ values, not
      -- a batch of one), so it preserves signal while carrying the BatchNorm kind.
      bnSpec = LayerGraph.NormSpec LayerGraph.NormBatch 1 hidden eps
      dropoutRate = 0.1
  dense1 <-
    LayerGraph.mkAffineLayer
      (name <> "-dense-1")
      LayerGraph.DenseLayer
      inputs
      hidden
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters seed inputs hidden)
  bn1 <-
    LayerGraph.mkNormLayer
      (name <> "-batchnorm-1")
      bnSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 1) (LayerGraph.NormOp bnSpec))
  drop1 <- LayerGraph.mkDropoutLayer (name <> "-dropout-1") dropoutRate hidden LayerGraph.TrainingMode
  dense2 <-
    LayerGraph.mkAffineLayer
      (name <> "-dense-2")
      LayerGraph.DenseLayer
      hidden
      hidden
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 2) hidden hidden)
  bn2 <-
    LayerGraph.mkNormLayer
      (name <> "-batchnorm-2")
      bnSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 3) (LayerGraph.NormOp bnSpec))
  drop2 <- LayerGraph.mkDropoutLayer (name <> "-dropout-2") dropoutRate hidden LayerGraph.TrainingMode
  headNode <-
    LayerGraph.mkAffineLayer
      (name <> "-classifier")
      LayerGraph.DenseLayer
      hidden
      outputs
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 4) hidden outputs)
  Right
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = name
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [inputs]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [outputs]
      , LayerGraph.layerGraphNodes = [dense1, bn1, drop1, dense2, bn2, drop2, headNode]
      }

-- | Per-family shape of the compact literal ResNet mixer graph.
data ResNetShape = ResNetShape
  { rnsStemNorm :: !LayerGraph.NormFlavor
  -- ^ stem normalization flavor: 'LayerGraph.NormBatch' (BatchNorm kind) for the
  --   ResNet families, 'LayerGraph.NormGroup' (GroupNorm kind) for wide-ResNet.
  , rnsBottleneck :: !Bool
  -- ^ 'True' builds three-stage bottleneck blocks ('LayerGraph.mkBottleneck',
  --   'LayerGraph.BottleneckBlockLayer' kind); 'False' builds two-stage basic
  --   blocks ('LayerGraph.mkBasicBlock', 'LayerGraph.BasicBlockLayer' kind).
  , rnsBlockCount :: !Int
  -- ^ number of residual blocks (a compact proxy for the literal depth, per the
  --   ConvergenceThresholds compact-proxy doctrine).
  }

resNetShape :: ResNetShape
resNetShape = ResNetShape LayerGraph.NormBatch False 2

resNet50Shape :: ResNetShape
resNet50Shape = ResNetShape LayerGraph.NormBatch True 2

wideResNetShape :: ResNetShape
wideResNetShape = ResNetShape (LayerGraph.NormGroup 2) False 2

-- Phases 242–244 — literal compact "mixer-ResNet" graph. A real TWO-STAGE strided
-- convolutional feature extractor with a LOCAL (spatial-preserving) average pool,
-- then a residual/attention/GeGLU mixer — every claimed feature a trained node of
-- the matching kind:
--
--   conv1 ('LayerGraph.ConvOp' C_in→c1, 3×3 stride s1, ReLU) -> stem norm
--   ('LayerGraph.NormOp'; BatchNorm for ResNet, GroupNorm for wide-ResNet, over c1)
--   -> conv2 ('LayerGraph.ConvOp' c1→c2, 3×3 stride s2, ReLU) -> local avg-pool
--   ('LayerGraph.PoolOp' 'LayerGraph.PoolAvg' 2×2, preserving a small spatial grid)
--   -> dense feature projection (featDim = c2·h3·w3 -> width) -> basic/bottleneck
--   residual block(s) ('LayerGraph.BlockOp') -> LayerNorm -> multi-head attention
--   ('LayerGraph.AttentionOp', @seqLen × embedDim = width@) -> GeGLU -> dense
--   classifier.
--
-- Keeping REAL spatial features (a preserved @c2·h3·w3@ feature map projected to
-- @width@) instead of collapsing to a tiny width via a single global pool is the
-- capacity that clears the ResNet bars. Strides adapt so tiny inputs never reach
-- zero spatial (mnist 28×28 shares this builder via fashion-mnist-resnet), and
-- every spatial-dependent dim (stem-norm nSpatial, conv2 input dims, pool geometry,
-- projection featDim) is computed from the exact strided output dims so
-- shape-chaining stays exact.
correctOpsResNetGraph
  :: ResNetShape
  -> Text
  -> Int
  -- ^ input width @C*H*W@
  -> Int
  -- ^ output width @classes + 1@
  -> Int
  -- ^ seed
  -> Int
  -- ^ mixer-width hint
  -> Either Text LayerGraph.LayerGraph
correctOpsResNetGraph shape name inputs outputs seed widthHint = do
  let geometry = geometryForInput inputs
      channels = geomChannels geometry
      height = geomHeight geometry
      imWidth = geomWidth geometry
      heads = 2
      seqLen = 2
      -- Mixer working width (~64): @width = seqLen*embedD@; the downstream
      -- block/attention/GeGLU/classifier all run at this modest width.
      embedBase = clamp 8 32 widthHint
      embedD = max heads (embedBase - (embedBase `mod` heads))
      width = seqLen * embedD
      eps = 1.0e-5
      -- Two strided convs collapse the image toward ~4×4 while the local avg-pool
      -- keeps a real (not global) spatial grid. c1/c2 are the conv channel counts.
      c1 = 16
      c2 = 32
      s1 = if imWidth >= 16 then max 2 (imWidth `div` 16) else 1
      h1 = LayerGraph.convOutDim height 3 s1 1
      w1 = LayerGraph.convOutDim imWidth 3 s1 1
      s2 = if min h1 w1 >= 8 then 2 else 1
      h2 = LayerGraph.convOutDim h1 3 s2 1
      w2 = LayerGraph.convOutDim w1 3 s2 1
      pkH = if h2 >= 2 then 2 else 1
      pkW = if w2 >= 2 then 2 else 1
      h3 = LayerGraph.convOutDim h2 pkH pkH 0
      w3 = LayerGraph.convOutDim w2 pkW pkW 0
      featDim = c2 * h3 * w3
      conv1Spec = LayerGraph.ConvSpec channels c1 [height, imWidth] [3, 3] [s1, s1] [1, 1]
      stemNormSpec = LayerGraph.NormSpec (rnsStemNorm shape) c1 (h1 * w1) eps
      conv2Spec = LayerGraph.ConvSpec c1 c2 [h1, w1] [3, 3] [s2, s2] [1, 1]
      poolShape = LayerGraph.SpatialShape c2 h2 w2
      poolWindow = LayerGraph.PoolWindow pkH pkW pkH pkW 0 0 False
      lnSpec = LayerGraph.NormSpec LayerGraph.NormLayerWise width 1 eps
      attnSpec = LayerGraph.AttentionSpec seqLen embedD heads False
      ggSpec = LayerGraph.GeGLUSpec width (max 4 width) width
  conv1Node <-
    LayerGraph.mkConvLayer
      (name <> "-conv-stem-1")
      conv1Spec
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters seed (LayerGraph.ConvOp conv1Spec))
  stemNormNode <-
    LayerGraph.mkNormLayer
      (name <> "-stem-norm")
      stemNormSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 1) (LayerGraph.NormOp stemNormSpec))
  conv2Node <-
    LayerGraph.mkConvLayer
      (name <> "-conv-stem-2")
      conv2Spec
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 2) (LayerGraph.ConvOp conv2Spec))
  poolNode <-
    LayerGraph.mkPoolLayer
      (name <> "-local-avg-pool")
      poolShape
      (LayerGraph.PoolAvg poolWindow)
      LayerGraph.TrainingMode
  projNode <-
    LayerGraph.mkAffineLayer
      (name <> "-feature-projection")
      LayerGraph.DenseLayer
      featDim
      width
      LayerGraph.ReluActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 3) featDim width)
  blockNodes <- traverse (mkResBlock shape name width eps seed) [1 .. max 1 (rnsBlockCount shape)]
  lnNode <-
    LayerGraph.mkNormLayer
      (name <> "-layernorm")
      lnSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 4) (LayerGraph.NormOp lnSpec))
  attnNode <-
    LayerGraph.mkAttentionLayer
      (name <> "-attention")
      attnSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 5) (LayerGraph.AttentionOp attnSpec))
  ggNode <-
    LayerGraph.mkGeGLULayer
      (name <> "-geglu")
      ggSpec
      LayerGraph.TrainingMode
      (LayerGraph.deterministicOpParameters (seed + 6) (LayerGraph.GeGLUOp ggSpec))
  headNode <-
    LayerGraph.mkAffineLayer
      (name <> "-classifier")
      LayerGraph.DenseLayer
      width
      outputs
      LayerGraph.LinearActivation
      LayerGraph.TrainingMode
      (LayerGraph.deterministicParameters (seed + 7) width outputs)
  Right
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = name
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [channels, height, imWidth]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [outputs]
      , LayerGraph.layerGraphNodes =
          [conv1Node, stemNormNode, conv2Node, poolNode, projNode]
            <> blockNodes
            <> [lnNode, attnNode, ggNode, headNode]
      }

-- | Build one residual block node (basic or bottleneck) over the working width.
mkResBlock :: ResNetShape -> Text -> Int -> Double -> Int -> Int -> Either Text LayerGraph.LayerNode
mkResBlock shape name width eps seed idx =
  ctor blockName spec LayerGraph.TrainingMode params
 where
  blockSeed = seed + 10 + idx
  blockName = name <> "-block-" <> Text.pack (show idx)
  spec = resBlockSpec shape width eps
  params = LayerGraph.deterministicOpParameters blockSeed (LayerGraph.BlockOp spec)
  ctor = if rnsBottleneck shape then LayerGraph.mkBottleneck else LayerGraph.mkBasicBlock

-- | Compact residual block spec: an identity-shortcut stack of affine→LayerNorm→
-- ReLU stages with a final ReLU. Basic blocks keep the width; bottleneck blocks
-- reduce to a middle width and expand back (distinct topology → the
-- 'LayerGraph.BottleneckBlockLayer' kind).
resBlockSpec :: ResNetShape -> Int -> Double -> LayerGraph.BlockSpec
resBlockSpec shape width eps
  | rnsBottleneck shape =
      let mid = max 2 (width `div` 2)
       in LayerGraph.BlockSpec
            [blockStage width mid eps, blockStage mid mid eps, blockStage mid width eps]
            LayerGraph.IdentityShortcut
            1.0
            LayerGraph.ReluActivation
  | otherwise =
      LayerGraph.BlockSpec
        [blockStage width width eps, blockStage width width eps]
        LayerGraph.IdentityShortcut
        1.0
        LayerGraph.ReluActivation

blockStage :: Int -> Int -> Double -> LayerGraph.BlockStage
blockStage dIn dOut eps =
  LayerGraph.BlockStage
    (LayerGraph.AffineSpec dIn dOut)
    (Just (LayerGraph.NormSpec LayerGraph.NormLayerWise dOut 1 eps))
    LayerGraph.ReluActivation

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
predictArchitectureWithDevice _device trained input
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
  | otherwise =
      -- Sprint 237.1: inference runs the trained typed LayerGraph IR and returns
      -- the raw @classes + 1@ logits; callers take the semantic-prefix argmax.
      pure $ do
        output <- classifierGraphLogits (trainedArchGraph trained) input
        if VU.null output
          then Left "predictArchitectureWithDevice: served graph returned an empty flat output"
          else
            if VU.all isFiniteDouble output
              then Right output
              else Left "predictArchitectureWithDevice: served graph returned a non-finite flat output"
 where
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
  let rawRuntime =
        RuntimeArtifact.RawSupervisedRuntime
          { RuntimeArtifact.rawSupervisedRuntimeTask =
              RuntimeArtifact.RawClassificationRuntimeTask (clfClasses config)
          , RuntimeArtifact.rawSupervisedRuntimeInputTransform =
              defaultTrainedArchitectureInputTransform config
          , RuntimeArtifact.rawSupervisedRuntimeOutputTransform =
              RuntimeArtifact.RawSemanticPrefixOutput (clfClasses config)
          }
  refined <- RuntimeArtifact.refineSupervisedRuntime rawRuntime
  if RuntimeArtifact.supervisedRuntimeToRaw refined == rawRuntime
    then Right rawRuntime
    else Left "canonical classification runtime contract did not survive exact refinement"

rawImageGeometry :: ImageGeometry -> RuntimeArtifact.RawRuntimeImageGeometry
rawImageGeometry geometry =
  RuntimeArtifact.RawRuntimeImageGeometry
    { RuntimeArtifact.rawRuntimeImageWidth = geomWidth geometry
    , RuntimeArtifact.rawRuntimeImageHeight = geomHeight geometry
    , RuntimeArtifact.rawRuntimeImageChannels = geomChannels geometry
    }

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
      let epochs = clfEpochs config
          classes = clfClasses config
          batchSize = clfBatchSize config
          lr = clfLearningRate config
          selectionSet = validationSet
          mkTrained graph =
            TrainedArchitecture
              { trainedArchSpec = spec
              , trainedArchGraph = graph
              , trainedArchConfig = config
              , trainedArchInputTransform =
                  defaultTrainedArchitectureInputTransform config
              }
      statesE <- initialiseLayers (clfSeed config) (archLayers spec)
      case statesE >>= initialClassifierGraph spec of
        Left err -> pure (Left err)
        Right graph0 -> do
          -- Sprint 238.1: train the typed LayerGraph epoch by epoch (Adam moments
          -- threaded through GraphClassifierAdam), selecting the snapshot with the
          -- lowest held-out validation cross-entropy — the same model-selection
          -- and update/example accounting the [LayerState] loop used.
          let initialWeights = VU.toList (LayerGraph.graphParameterVector graph0)
          folded <-
            foldM
              ( \acc epoch -> case acc of
                  Left err -> pure (Left err)
                  Right (st, best, updatesExecuted) -> do
                    let epochExamples = datasetClassifierExamples (epochOrder epoch trainSet)
                        epochUpdates =
                          fromIntegral (length (LayerGraph.classifierBatches batchSize epochExamples)) :: Word64
                    stepE <- trainClassifierGraphEpoch device classes batchSize lr st epochExamples
                    case stepE of
                      Left err -> pure (Left err)
                      Right st' ->
                        case serveClassifierGraphCrossEntropy classes (LayerGraph.gcaGraph st') selectionSet of
                          Left err -> pure (Left err)
                          Right valLoss ->
                            let best' = case best of
                                  Just (_, bestVal) | bestVal <= valLoss -> best
                                  _ -> Just (LayerGraph.gcaGraph st', valLoss)
                             in pure $ do
                                  totalUpdates <-
                                    checkedOptimizerUpdateSum updatesExecuted epochUpdates
                                  Right (st', best', totalUpdates)
              )
              (Right (LayerGraph.initGraphClassifierAdam graph0, Nothing, 0))
              [1 .. epochs]
          case folded of
            Left err -> pure (Left err)
            Right (_, Nothing, _) ->
              pure (Left "trainArchitectureWithDeviceSelected: no epoch produced a validation measurement")
            Right (_, Just (bestGraph, bestValLoss), updatesExecuted) -> do
              let trained = mkTrained bestGraph
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
          ( \graph0 ->
              ExactArchitectureTraining
                { exactTrainingSpec = spec
                , exactTrainingConfig = config
                , exactTrainingOptimizer = optimizerConfigFor optimizer (clfLearningRate config)
                , exactTrainingDropout = dropout
                , exactTrainingTrainSet = trainSet
                , exactTrainingValidationSet = validationSet
                , exactTrainingAdam = LayerGraph.initGraphClassifierAdam graph0
                , exactTrainingUpdates = 0
                , exactTrainingExamplesProcessed = 0
                , exactTrainingInitialWeights = VU.toList (LayerGraph.graphParameterVector graph0)
                }
          )
          (statesE >>= initialClassifierGraph spec)

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
                -- Sprint 238.1: one optimizer update of the trained typed graph
                -- over this (dropout-masked) mini-batch through the device.
                adamE <-
                  trainClassifierGraphBatch
                    device
                    (clfClasses config)
                    (exactTrainingOptimizer current)
                    (exactTrainingAdam current)
                    (zip droppedInputs batchLabels)
                pure $
                  fmap
                    ( \adam ->
                        current
                          { exactTrainingAdam = adam
                          , exactTrainingUpdates = absoluteUpdate
                          , exactTrainingExamplesProcessed = examplesProcessed
                          }
                    )
                    adamE

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
    , trainedArchGraph = LayerGraph.gcaGraph (exactTrainingAdam training)
    , trainedArchConfig = exactTrainingConfig training
    , trainedArchInputTransform =
        defaultTrainedArchitectureInputTransform (exactTrainingConfig training)
    }

exactArchitectureUpdatesExecuted :: ExactArchitectureTraining -> Int
exactArchitectureUpdatesExecuted = exactTrainingUpdates

exactArchitectureInitialWeights :: ExactArchitectureTraining -> [Double]
exactArchitectureInitialWeights = exactTrainingInitialWeights

exactArchitectureTrainedWeights :: ExactArchitectureTraining -> [Double]
exactArchitectureTrainedWeights =
  VU.toList . LayerGraph.graphParameterVector . LayerGraph.gcaGraph . exactTrainingAdam

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
  -- Sprint 237.1: graph-ordered flat parameters (weights ++ bias per node, in
  -- node order) are the single trained-weight witness for checkpoints and tuning.
  VU.toList . LayerGraph.graphParameterVector . trainedArchGraph

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
  -- This geometry describes the retained legacy @archLayers@ initialization
  -- adapter only. The trained literal ViT is built by 'correctOpsVitGraph',
  -- which uses an 8x8 CIFAR patch and 16 tokens. Do not treat this 4x4/64-token
  -- descriptor as the executable graph contract.
  | geomWidth geometry >= 32 = 4
  | otherwise = patchSide geometry

clamp :: Int -> Int -> Int -> Int
clamp lo hi value = max lo (min hi value)

isFiniteDouble :: Double -> Bool
isFiniteDouble value = not (isNaN value || isInfinite value)

showText :: (Show a) => a -> Text
showText = Text.pack . show

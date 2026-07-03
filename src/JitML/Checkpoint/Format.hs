{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Format
  ( AdvancePredicate (..)
  , ArtifactPointer (..)
  , ArchitectureMetadata (..)
  , CheckpointManifest (..)
  , CheckpointPartKind (..)
  , EligibilityError (..)
  , InferenceEligibleCheckpoint
  , LayerGraphActivationMetadata (..)
  , LayerGraphKindMetadata (..)
  , LayerGraphMetadata (..)
  , LayerGraphModeMetadata (..)
  , LayerGraphNodeMetadata (..)
  , MetricDirection (..)
  , ModelFamily (..)
  , OptimizerBlob (..)
  , OutputDecoder (..)
  , OutputDecoderKind (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , PreprocessingMetadata (..)
  , RngBlob (..)
  , SubstrateArtifact (..)
  , TensorBlob (..)
  , TensorSpec (..)
  , WeightLayout (..)
  , advanceBestMaximised
  , advanceBestMinimised
  , advanceLatest
  , applyAdvancePredicate
  , applyPointerWrite
  , attachCompletedTraining
  , bestPointerKey
  , blobKey
  , decodeJmw1
  , decodeInferenceEligibleManifestCbor
  , decodeManifestCbor
  , defaultArchitectureMetadata
  , deriveExperimentHash
  , emptyManifest
  , encodeJmw1
  , encodeManifestCbor
  , latestPointerKey
  , layerGraphMetadataFromGraph
  , manifestContentSha
  , manifestKey
  , manifestPointer
  , manifestTrainingEvidence
  , renderEligibilityError
  , requireInferenceEligibleCheckpoint
  , eligibleCheckpointCompletedTraining
  , eligibleCheckpointManifest
  , eligibleCheckpointManifestSha
  , tensorSpecFromBlob
  , trialPointerKey
  , validateSupervisedManifestShapeLayout
  , weightOnlyTensors
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (Bits, shiftL, shiftR, (.&.))
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.List (group, sort, sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word32, Word64, Word8)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import GHC.Generics (Generic)

import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Product.Evidence
  ( TrainingEvidence
  , mkTrainingEvidence
  )
import JitML.Training.Budget
  ( CompletedTraining
  , coMetricName
  , completedTrainingDatasetShaAtRead
  , completedTrainingEvidence
  , completedTrainingFinalWeightHash
  , completedTrainingInitialWeightHash
  , completedTrainingMetrics
  , completedTrainingObservedUnits
  , completedTrainingTensorBoard
  , completedTrainingUpdateCount
  , convergencePassed
  , tbrScalarTags
  )

data CheckpointPartKind
  = WeightPart
  | OptimizerPart
  | RngPart
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data TensorBlob = TensorBlob
  { tensorName :: Text
  , tensorShape :: [Int]
  , tensorBlobKey :: Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data OptimizerBlob = OptimizerBlob
  { optimizerKind :: Text
  , optimizerBlobKey :: Text
  , optimizerStateSize :: Int
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data RngBlob = RngBlob
  { rngStreamId :: Text
  , rngBlobKey :: Text
  , rngWordCount :: Int
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data ModelFamily
  = GenericModelFamily
  | SupervisedModelFamily
  | ReinforcementLearningPolicyFamily
  | AlphaZeroPolicyValueFamily
  | HyperparameterTuningFamily
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data TensorSpec = TensorSpec
  { tensorSpecName :: Text
  , tensorSpecShape :: [Int]
  , tensorSpecDtype :: Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

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

data ArchitectureMetadata = ArchitectureMetadata
  { architectureName :: Text
  , architectureModelFamily :: ModelFamily
  , architectureInputs :: [TensorSpec]
  , architectureOutputs :: [TensorSpec]
  , architectureLayerGraph :: Maybe LayerGraphMetadata
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data PreprocessingMetadata = PreprocessingMetadata
  { preprocessingName :: Text
  , preprocessingSteps :: [Text]
  , preprocessingInputs :: [TensorSpec]
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data OutputDecoderKind
  = ClassificationOutput
  | RegressionOutput
  | PolicyDistributionOutput
  | ValueEstimateOutput
  | MctsVisitDistributionOutput
  | ReplayArtifactOutput
  | GenericOutput
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data OutputDecoder = OutputDecoder
  { outputDecoderName :: Text
  , outputDecoderKind :: OutputDecoderKind
  , outputDecoderLabels :: [Text]
  , outputDecoderUnits :: Maybe Text
  , outputDecoderArtifactKind :: Maybe Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data WeightLayout
  = FlatWeightLayout [TensorSpec]
  | NamedTensorWeightLayout [TensorSpec]
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data ArtifactPointer = ArtifactPointer
  { artifactPointerKind :: Text
  , artifactPointerObjectKey :: Text
  , artifactPointerSha :: Maybe Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data SubstrateArtifact = SubstrateArtifact
  { substrateArtifactSubstrate :: Text
  , substrateArtifactKind :: Text
  , substrateArtifactCacheKey :: Text
  , substrateArtifactObjectKey :: Maybe Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data CheckpointManifest = CheckpointManifest
  { manifestId :: Text
  , manifestExperiment :: Text
  , manifestModelFamily :: ModelFamily
  , manifestArchitecture :: ArchitectureMetadata
  , manifestPreprocessing :: [PreprocessingMetadata]
  , manifestOutputDecoders :: [OutputDecoder]
  , manifestWeightLayout :: WeightLayout
  , manifestReplayPointers :: [ArtifactPointer]
  , manifestTranscriptPointers :: [ArtifactPointer]
  , manifestSubstrateArtifacts :: [SubstrateArtifact]
  , manifestTensors :: [TensorBlob]
  , manifestOptimizer :: [OptimizerBlob]
  , manifestRng :: [RngBlob]
  , manifestStep :: Word64
  , manifestMetrics :: [(Text, Double)]
  , manifestCompletedTraining :: Maybe CompletedTraining
  , manifestInitialWeightHash :: Maybe Text
  , manifestFinalWeightHash :: Maybe Text
  , manifestUpdateCount :: Maybe Word64
  , manifestDatasetShaAtRead :: Maybe Text
  , manifestParentManifestSha :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data InferenceEligibleCheckpoint = InferenceEligibleCheckpoint
  { eligibleCheckpointManifest :: CheckpointManifest
  , eligibleCheckpointManifestSha :: Text
  , eligibleCheckpointCompletedTraining :: CompletedTraining
  }
  deriving stock (Eq, Show)

data EligibilityError
  = MissingCompletedTraining
  | CompletedTrainingHasNoMetrics
  | CompletedTrainingHasFailedMetrics [Text]
  | CompletedTrainingOutrunsManifest Word64 Word64
  | CompletedTrainingEvidenceMissing
  | CompletedTrainingEvidenceInvalid Text
  | CompletedTrainingEvidenceMismatch
  | SupervisedManifestShapeLayoutInvalid [Text]
  | TensorBoardMetadataMissing
  deriving stock (Eq, Show)

data PointerWrite = PointerWrite
  { pointerWriteKey :: Text
  , pointerWriteExpectedETag :: Maybe Text
  , pointerWriteManifestSha :: Text
  }
  deriving stock (Eq, Show)

data PointerWriteResult
  = PointerWritten Text
  | PointerConflict Text
  deriving stock (Eq, Show)

data Jmw1Header = Jmw1Header
  { jmw1Dtype :: Text
  , jmw1TensorCount :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data MetricDirection
  = Maximise
  | Minimise
  deriving stock (Eq, Show)

-- | Typed advance predicates for the pointer-CAS step. The trainer picks the
-- predicate from the experiment Dhall's `metrics[i].direction` field per
-- README → Concurrency model.
data AdvancePredicate
  = AdvanceLatest
  | -- | metric name
    AdvanceBestMaximised Text
  | -- | metric name
    AdvanceBestMinimised Text
  deriving stock (Eq, Show)

advanceLatest :: AdvancePredicate
advanceLatest = AdvanceLatest

advanceBestMaximised :: Text -> AdvancePredicate
advanceBestMaximised = AdvanceBestMaximised

advanceBestMinimised :: Text -> AdvancePredicate
advanceBestMinimised = AdvanceBestMinimised

-- | Evaluate the advance predicate against the current and proposed manifests.
-- True means the pointer should advance to the proposed manifest.
applyAdvancePredicate
  :: AdvancePredicate
  -> Maybe CheckpointManifest
  -- ^ current pointer target
  -> CheckpointManifest
  -- ^ proposed
  -> Bool
applyAdvancePredicate _ Nothing _ = True
applyAdvancePredicate predicate (Just current) proposed =
  case predicate of
    AdvanceLatest ->
      manifestStep proposed > manifestStep current
    AdvanceBestMaximised metric ->
      lookupMetric metric proposed > lookupMetric metric current
    AdvanceBestMinimised metric ->
      lookupMetric metric proposed < lookupMetric metric current

lookupMetric :: Text -> CheckpointManifest -> Maybe Double
lookupMetric metric manifest =
  lookup metric (manifestMetrics manifest)

-- | Convenience builder. Use record syntax on the result to fill richer
-- manifests with optimizer / RNG / metric details.
emptyManifest :: Text -> Text -> [TensorBlob] -> CheckpointManifest
emptyManifest mid experiment tensors =
  CheckpointManifest
    { manifestId = mid
    , manifestExperiment = experiment
    , manifestModelFamily = GenericModelFamily
    , manifestArchitecture = defaultArchitectureMetadata GenericModelFamily
    , manifestPreprocessing = []
    , manifestOutputDecoders = []
    , manifestWeightLayout = NamedTensorWeightLayout (fmap tensorSpecFromBlob tensors)
    , manifestReplayPointers = []
    , manifestTranscriptPointers = []
    , manifestSubstrateArtifacts = []
    , manifestTensors = tensors
    , manifestOptimizer = []
    , manifestRng = []
    , manifestStep = 0
    , manifestMetrics = []
    , manifestCompletedTraining = Nothing
    , manifestInitialWeightHash = Nothing
    , manifestFinalWeightHash = Nothing
    , manifestUpdateCount = Nothing
    , manifestDatasetShaAtRead = Nothing
    , manifestParentManifestSha = Nothing
    }

attachCompletedTraining :: CompletedTraining -> CheckpointManifest -> CheckpointManifest
attachCompletedTraining completed manifest =
  manifest
    { manifestCompletedTraining = Just completed
    , manifestInitialWeightHash = Just (completedTrainingInitialWeightHash completed)
    , manifestFinalWeightHash = Just (completedTrainingFinalWeightHash completed)
    , manifestUpdateCount = Just (completedTrainingUpdateCount completed)
    , manifestDatasetShaAtRead = Just (completedTrainingDatasetShaAtRead completed)
    }

manifestTrainingEvidence :: CheckpointManifest -> Either EligibilityError TrainingEvidence
manifestTrainingEvidence manifest =
  case ( manifestInitialWeightHash manifest
       , manifestFinalWeightHash manifest
       , manifestUpdateCount manifest
       , manifestDatasetShaAtRead manifest
       ) of
    (Just initialHash, Just finalHash, Just updateCount, Just datasetSha) ->
      case mkTrainingEvidence initialHash finalHash updateCount datasetSha of
        Right evidence -> Right evidence
        Left err -> Left (CompletedTrainingEvidenceInvalid err)
    _ -> Left CompletedTrainingEvidenceMissing

requireInferenceEligibleCheckpoint
  :: Text
  -- ^ manifest content sha already validated by the caller
  -> CheckpointManifest
  -> Either EligibilityError InferenceEligibleCheckpoint
requireInferenceEligibleCheckpoint manifestSha manifest =
  case manifestCompletedTraining manifest of
    Nothing -> Left MissingCompletedTraining
    Just completed
      | completedTrainingObservedUnits completed > manifestStep manifest ->
          Left
            ( CompletedTrainingOutrunsManifest
                (completedTrainingObservedUnits completed)
                (manifestStep manifest)
            )
      | null (completedTrainingMetrics completed) ->
          Left CompletedTrainingHasNoMetrics
      | null (tbrScalarTags (completedTrainingTensorBoard completed)) ->
          Left TensorBoardMetadataMissing
      | otherwise ->
          case manifestTrainingEvidence manifest of
            Left err -> Left err
            Right evidence
              | evidence /= completedTrainingEvidence completed ->
                  Left CompletedTrainingEvidenceMismatch
              | otherwise ->
                  let supervisedShapeLayoutErrors =
                        validateSupervisedManifestShapeLayout manifest
                   in case filter (not . convergencePassed) (completedTrainingMetrics completed) of
                        []
                          | not (null supervisedShapeLayoutErrors) ->
                              Left (SupervisedManifestShapeLayoutInvalid supervisedShapeLayoutErrors)
                          | otherwise ->
                              Right
                                InferenceEligibleCheckpoint
                                  { eligibleCheckpointManifest = manifest
                                  , eligibleCheckpointManifestSha = manifestSha
                                  , eligibleCheckpointCompletedTraining = completed
                                  }
                        failed ->
                          Left (CompletedTrainingHasFailedMetrics (fmap coMetricName failed))

validateSupervisedManifestShapeLayout :: CheckpointManifest -> [Text]
validateSupervisedManifestShapeLayout manifest
  | manifestModelFamily manifest /= SupervisedModelFamily = []
  | otherwise =
      concat
        [ architectureFamilyErrors
        , architectureShapeErrors
        , tensorBlobErrors
        , weightLayoutErrors
        , layerGraphErrors
        ]
 where
  architecture = manifestArchitecture manifest
  tensors = manifestTensors manifest
  tensorSpecs = fmap tensorSpecFromBlob tensors
  layoutSpecs =
    case manifestWeightLayout manifest of
      NamedTensorWeightLayout specs -> Just specs
      FlatWeightLayout _ -> Nothing

  architectureFamilyErrors =
    [ "supervised manifest architecture family is "
        <> Text.pack (show (architectureModelFamily architecture))
        <> ", expected SupervisedModelFamily"
    | architectureModelFamily architecture /= SupervisedModelFamily
    ]

  architectureShapeErrors =
    concat
      [ singletonShapeErrors "architecture input" (architectureInputs architecture)
      , singletonShapeErrors "architecture output" (architectureOutputs architecture)
      , concatMap (tensorSpecShapeErrors "architecture input") (architectureInputs architecture)
      , concatMap (tensorSpecShapeErrors "architecture output") (architectureOutputs architecture)
      ]

  tensorBlobErrors =
    ["supervised manifest has no weight tensors" | null tensors]
      <> concatMap tensorBlobShapeErrors tensors
      <> duplicateNameErrors "weight tensor" (fmap tensorName tensors)

  weightLayoutErrors =
    case manifestWeightLayout manifest of
      FlatWeightLayout _ ->
        ["supervised manifest requires NamedTensorWeightLayout"]
      NamedTensorWeightLayout specs ->
        ["supervised manifest has empty NamedTensorWeightLayout" | null specs]
          <> concatMap (tensorSpecShapeErrors "weight layout") specs
          <> duplicateNameErrors "weight layout tensor" (fmap tensorSpecName specs)
          <> [ "supervised manifest weight layout does not match manifest tensors"
             | sortTensorSpecs specs /= sortTensorSpecs tensorSpecs
             ]

  layerGraphErrors =
    case architectureLayerGraph architecture of
      Nothing ->
        ["supervised manifest missing layer graph metadata"]
      Just graph ->
        graphShapeErrors graph
          <> graphNodeErrors graph
          <> graphTensorErrors graph

  graphShapeErrors graph =
    concat
      [ shapeErrors "layer graph input" (layerGraphMetadataInputShape graph)
      , shapeErrors "layer graph output" (layerGraphMetadataOutputShape graph)
      , [ "supervised layer graph input shape does not match architecture input"
        | Just inputShape <- [singleTensorSpecShape (architectureInputs architecture)]
        , layerGraphMetadataInputShape graph /= inputShape
        ]
      , [ "supervised layer graph output shape does not match architecture output"
        | Just outputShape <- [singleTensorSpecShape (architectureOutputs architecture)]
        , layerGraphMetadataOutputShape graph /= outputShape
        ]
      ]

  graphNodeErrors graph =
    ["supervised layer graph has no nodes" | null (layerGraphMetadataNodes graph)]
      <> concatMap layerNodeShapeErrors (layerGraphMetadataNodes graph)
      <> duplicateNameErrors "layer graph node" (fmap layerGraphNodeName (layerGraphMetadataNodes graph))

  graphTensorErrors graph =
    let expectedSpecs = concatMap expectedLayerGraphTensorSpecs (layerGraphMetadataNodes graph)
        expectedNames = fmap tensorSpecName expectedSpecs
        layoutMismatch =
          case layoutSpecs of
            Nothing -> []
            Just specs ->
              [ "supervised layer graph tensors do not match named weight layout"
              | sortTensorSpecs expectedSpecs /= sortTensorSpecs specs
              ]
     in ["supervised layer graph declares no parameter tensors" | null expectedSpecs]
          <> concatMap layerNodeTensorPairErrors (layerGraphMetadataNodes graph)
          <> duplicateNameErrors "layer graph tensor" expectedNames
          <> [ "supervised layer graph tensors do not match manifest tensors"
             | sortTensorSpecs expectedSpecs /= sortTensorSpecs tensorSpecs
             ]
          <> layoutMismatch

  expectedLayerGraphTensorSpecs node =
    case (layerGraphNodeWeightTensor node, layerGraphNodeBiasTensor node) of
      (Just weightName, Just biasName) ->
        let inputWidth = product (layerGraphNodeInputShape node)
            outputWidth = product (layerGraphNodeOutputShape node)
         in [ TensorSpec weightName [outputWidth, inputWidth] "F64"
            , TensorSpec biasName [outputWidth] "F64"
            ]
      _ -> []

  layerNodeTensorPairErrors node =
    case (layerGraphNodeWeightTensor node, layerGraphNodeBiasTensor node) of
      (Nothing, Nothing) -> []
      (Just _, Just _) -> []
      _ ->
        [ "layer graph node "
            <> layerGraphNodeName node
            <> " must declare both weight and bias tensors or neither"
        ]

  layerNodeShapeErrors node =
    shapeErrors
      ("layer graph node " <> layerGraphNodeName node <> " input")
      (layerGraphNodeInputShape node)
      <> shapeErrors
        ("layer graph node " <> layerGraphNodeName node <> " output")
        (layerGraphNodeOutputShape node)

  tensorSpecShapeErrors label spec =
    shapeErrors (label <> " " <> tensorSpecName spec) (tensorSpecShape spec)

  tensorBlobShapeErrors tensor =
    shapeErrors ("weight tensor " <> tensorName tensor) (tensorShape tensor)

  singletonShapeErrors label specs =
    [ "supervised manifest must declare exactly one " <> label <> " TensorSpec"
    | length specs /= 1
    ]

  singleTensorSpecShape [spec] = Just (tensorSpecShape spec)
  singleTensorSpecShape _ = Nothing

  shapeErrors label shape =
    [ label
        <> " shape must be non-empty and positive, got "
        <> Text.pack (show shape)
    | null shape || any (<= 0) shape
    ]

  duplicateNameErrors label names =
    [ "supervised manifest has duplicate " <> label <> " name " <> name
    | name : _ : _ <- group (sort names)
    ]

  sortTensorSpecs = sortOn tensorSpecName

renderEligibilityError :: EligibilityError -> Text
renderEligibilityError err =
  case err of
    MissingCompletedTraining ->
      "manifest has no completed-training witness"
    CompletedTrainingHasNoMetrics ->
      "completed-training witness has no convergence metrics"
    CompletedTrainingHasFailedMetrics metrics ->
      "completed-training witness has failed convergence metrics: "
        <> Text.intercalate "," metrics
    CompletedTrainingOutrunsManifest observed manifestStepValue ->
      "completed-training witness observes "
        <> Text.pack (show observed)
        <> " units but manifest step is "
        <> Text.pack (show manifestStepValue)
    CompletedTrainingEvidenceMissing ->
      "completed-training manifest is missing weight-delta evidence"
    CompletedTrainingEvidenceInvalid detail ->
      "completed-training manifest has invalid weight-delta evidence: " <> detail
    CompletedTrainingEvidenceMismatch ->
      "completed-training manifest evidence does not match its witness"
    SupervisedManifestShapeLayoutInvalid errors ->
      "supervised manifest has invalid shape/layout metadata: "
        <> Text.intercalate "; " errors
    TensorBoardMetadataMissing ->
      "completed-training witness has no TensorBoard scalar metadata"

defaultArchitectureMetadata :: ModelFamily -> ArchitectureMetadata
defaultArchitectureMetadata family =
  ArchitectureMetadata
    { architectureName = "unspecified"
    , architectureModelFamily = family
    , architectureInputs = []
    , architectureOutputs = []
    , architectureLayerGraph = Nothing
    }

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

tensorSpecFromBlob :: TensorBlob -> TensorSpec
tensorSpecFromBlob tensor =
  TensorSpec
    { tensorSpecName = tensorName tensor
    , tensorSpecShape = tensorShape tensor
    , tensorSpecDtype = "F64"
    }

-- | The experiment hash: `sha256(resolved-dhall || substrate-fingerprint)`.
deriveExperimentHash :: Text -> Text -> Text
deriveExperimentHash resolvedDhall substrateFingerprint =
  hexBytes $
    SHA256.hash $
      Text.Encoding.encodeUtf8 (resolvedDhall <> "||" <> substrateFingerprint)

encodeJmw1 :: [Double] -> LazyByteString.ByteString
encodeJmw1 values =
  LazyByteString.fromStrict $
    StrictByteString.concat
      [ Text.Encoding.encodeUtf8 "JMW1"
      , word32Le (fromIntegral (LazyByteString.length header))
      , LazyByteString.toStrict header
      , StrictByteString.concat (fmap doubleLe values)
      ]
 where
  header =
    serialise
      Jmw1Header
        { jmw1Dtype = "F64"
        , jmw1TensorCount = length values
        }

decodeJmw1 :: LazyByteString.ByteString -> Either Text [Double]
decodeJmw1 payload = do
  let strict = LazyByteString.toStrict payload
      (magic, afterMagic) = StrictByteString.splitAt 4 strict
      (headerLengthBytes, afterHeaderLength) = StrictByteString.splitAt 4 afterMagic
  if magic /= Text.Encoding.encodeUtf8 "JMW1"
    then Left "unsupported .jmw1 magic"
    else do
      headerLength <- maybeToEither "truncated .jmw1 header length" (word32FromLe headerLengthBytes)
      let requestedHeaderLength = fromIntegral headerLength
          (headerBytes, tensorBytes) =
            StrictByteString.splitAt requestedHeaderLength afterHeaderLength
      if StrictByteString.length headerBytes /= requestedHeaderLength
        then Left "truncated .jmw1 header"
        else do
          header <- decodeJmw1Header (LazyByteString.fromStrict headerBytes)
          if jmw1Dtype header /= "F64"
            then Left ("unsupported .jmw1 dtype: " <> jmw1Dtype header)
            else decodeJmw1Doubles (jmw1TensorCount header) tensorBytes

decodeJmw1Header :: LazyByteString.ByteString -> Either Text Jmw1Header
decodeJmw1Header bytes =
  case deserialiseOrFail bytes of
    Left failure -> Left ("invalid .jmw1 header: " <> Text.pack (show failure))
    Right header -> Right header

decodeJmw1Doubles :: Int -> StrictByteString.ByteString -> Either Text [Double]
decodeJmw1Doubles count bytes
  | count < 0 = Left "invalid .jmw1 tensor count"
  | StrictByteString.length bytes /= count * 8 =
      Left "unexpected .jmw1 tensor payload length"
  | otherwise =
      traverse decodeDoubleAt [0 .. count - 1]
 where
  decodeDoubleAt index =
    castWord64ToDouble
      <$> maybeToEither
        "truncated .jmw1 double payload"
        (word64FromLe (StrictByteString.take 8 (StrictByteString.drop (index * 8) bytes)))

encodeManifestCbor :: CheckpointManifest -> LazyByteString.ByteString
encodeManifestCbor =
  serialise . canonicalManifest

decodeManifestCbor :: LazyByteString.ByteString -> Either Text CheckpointManifest
decodeManifestCbor payload =
  case deserialiseOrFail payload of
    Left failure -> Left (Text.pack (show failure))
    Right manifest -> Right manifest

decodeInferenceEligibleManifestCbor
  :: Text
  -- ^ manifest content sha already validated by the caller
  -> LazyByteString.ByteString
  -> Either Text InferenceEligibleCheckpoint
decodeInferenceEligibleManifestCbor manifestSha payload = do
  manifest <- decodeManifestCbor payload
  case requireInferenceEligibleCheckpoint manifestSha manifest of
    Left err -> Left (renderEligibilityError err)
    Right eligible -> Right eligible

manifestContentSha :: CheckpointManifest -> Text
manifestContentSha =
  hexBytes . SHA256.hashlazy . encodeManifestCbor

blobKey :: Text -> Text -> Text
blobKey experimentHash blobSha =
  "jitml-checkpoints/" <> experimentHash <> "/blobs/" <> blobSha

manifestKey :: Text -> Text -> Text
manifestKey experimentHash manifestSha =
  "jitml-checkpoints/" <> experimentHash <> "/manifests/" <> manifestSha <> ".cbor"

latestPointerKey :: Text -> Text
latestPointerKey experimentHash =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/latest"

bestPointerKey :: Text -> Text -> Text
bestPointerKey experimentHash metricName =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/best/" <> metricName

trialPointerKey :: Text -> Text -> Text
trialPointerKey experimentHash trialId =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/trial/" <> trialId

manifestPointer :: CheckpointManifest -> Text
manifestPointer manifest =
  "jitml-checkpoints/"
    <> manifestExperiment manifest
    <> "/"
    <> manifestId manifest
    <> ".manifest.cbor"

-- | The inference path loads only weight-only blobs and skips optimizer/RNG
-- parts.
weightOnlyTensors :: CheckpointManifest -> [TensorBlob]
weightOnlyTensors = manifestTensors

applyPointerWrite :: Maybe Text -> PointerWrite -> PointerWriteResult
applyPointerWrite currentETag write
  | currentETag == pointerWriteExpectedETag write =
      PointerWritten (pointerWriteManifestSha write)
  | otherwise =
      PointerConflict (pointerWriteKey write)

canonicalManifest :: CheckpointManifest -> CheckpointManifest
canonicalManifest manifest =
  manifest
    { manifestTensors = sortOn tensorName (manifestTensors manifest)
    , manifestOptimizer = sortOn optimizerKind (manifestOptimizer manifest)
    , manifestRng = sortOn rngStreamId (manifestRng manifest)
    , manifestMetrics = sortOn fst (manifestMetrics manifest)
    , manifestArchitecture = canonicalArchitecture (manifestArchitecture manifest)
    , manifestPreprocessing =
        sortOn preprocessingName (fmap canonicalPreprocessing (manifestPreprocessing manifest))
    , manifestOutputDecoders = sortOn outputDecoderName (manifestOutputDecoders manifest)
    , manifestWeightLayout = canonicalWeightLayout (manifestWeightLayout manifest)
    , manifestReplayPointers = sortOn artifactPointerSortKey (manifestReplayPointers manifest)
    , manifestTranscriptPointers = sortOn artifactPointerSortKey (manifestTranscriptPointers manifest)
    , manifestSubstrateArtifacts =
        sortOn substrateArtifactSortKey (manifestSubstrateArtifacts manifest)
    }

canonicalArchitecture :: ArchitectureMetadata -> ArchitectureMetadata
canonicalArchitecture architecture =
  architecture
    { architectureInputs = sortOn tensorSpecName (architectureInputs architecture)
    , architectureOutputs = sortOn tensorSpecName (architectureOutputs architecture)
    }

canonicalPreprocessing :: PreprocessingMetadata -> PreprocessingMetadata
canonicalPreprocessing preprocessing =
  preprocessing
    { preprocessingInputs = sortOn tensorSpecName (preprocessingInputs preprocessing)
    }

canonicalWeightLayout :: WeightLayout -> WeightLayout
canonicalWeightLayout layout =
  case layout of
    FlatWeightLayout tensors ->
      FlatWeightLayout (sortOn tensorSpecName tensors)
    NamedTensorWeightLayout tensors ->
      NamedTensorWeightLayout (sortOn tensorSpecName tensors)

artifactPointerSortKey :: ArtifactPointer -> (Text, Text, Maybe Text)
artifactPointerSortKey pointer =
  (artifactPointerKind pointer, artifactPointerObjectKey pointer, artifactPointerSha pointer)

substrateArtifactSortKey :: SubstrateArtifact -> (Text, Text, Text, Maybe Text)
substrateArtifactSortKey artifact =
  ( substrateArtifactSubstrate artifact
  , substrateArtifactKind artifact
  , substrateArtifactCacheKey artifact
  , substrateArtifactObjectKey artifact
  )

hexBytes :: StrictByteString.ByteString -> Text
hexBytes =
  Text.pack . concatMap hexWord8 . StrictByteString.unpack

doubleLe :: Double -> StrictByteString.ByteString
doubleLe =
  word64Le . castDoubleToWord64

word32Le :: Word32 -> StrictByteString.ByteString
word32Le word =
  StrictByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    ]

word64Le :: Word64 -> StrictByteString.ByteString
word64Le word =
  StrictByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    , byteAt 32 word
    , byteAt 40 word
    , byteAt 48 word
    , byteAt 56 word
    ]

byteAt :: (Integral a, Bits a) => Int -> a -> Word8
byteAt offset word =
  fromIntegral ((word `shiftR` offset) .&. 0xff)

word32FromLe :: StrictByteString.ByteString -> Maybe Word32
word32FromLe bytes =
  case StrictByteString.unpack bytes of
    [b0, b1, b2, b3] ->
      Just
        ( fromIntegral b0
            + (fromIntegral b1 `shiftL` 8)
            + (fromIntegral b2 `shiftL` 16)
            + (fromIntegral b3 `shiftL` 24)
        )
    _ -> Nothing

word64FromLe :: StrictByteString.ByteString -> Maybe Word64
word64FromLe bytes =
  case StrictByteString.unpack bytes of
    [b0, b1, b2, b3, b4, b5, b6, b7] ->
      Just
        ( fromIntegral b0
            + (fromIntegral b1 `shiftL` 8)
            + (fromIntegral b2 `shiftL` 16)
            + (fromIntegral b3 `shiftL` 24)
            + (fromIntegral b4 `shiftL` 32)
            + (fromIntegral b5 `shiftL` 40)
            + (fromIntegral b6 `shiftL` 48)
            + (fromIntegral b7 `shiftL` 56)
        )
    _ -> Nothing

maybeToEither :: Text -> Maybe a -> Either Text a
maybeToEither message =
  maybe (Left message) Right

hexWord8 :: Word8 -> String
hexWord8 byte =
  [ intToDigit (fromIntegral byte `div` 16)
  , intToDigit (fromIntegral byte `mod` 16)
  ]

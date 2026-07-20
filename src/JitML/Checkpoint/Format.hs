{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Format
  ( AdvancePredicate (..)
  , AddressedCheckpointManifest
  , ArtifactPointer (..)
  , ArchitectureMetadata (..)
  , CheckpointManifest (..)
  , CheckpointPartKind (..)
  , CheckpointCompletionValidationError (..)
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
  , RawCheckpointEnvelope (..)
  , RawCheckpointBodyV2 (..)
  , RawCheckpointEnvelopeV2 (..)
  , RawCheckpointManifest (..)
  , RngBlob (..)
  , SubstrateArtifact (..)
  , SupervisedRuntimeManifestMetadata (..)
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
  , checkpointManifestToRaw
  , checkpointWireVersion
  , checkpointWireVersionV2
  , canonicalSupervisedRuntimeManifestMetadata
  , decodeJmw1
  , decodeAddressedManifestCbor
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
  , renderCheckpointCompletionValidationError
  , refineCheckpointManifest
  , validateCheckpointCompletion
  , ValidatedCheckpointCompletion
  , validatedCheckpointCompletedTraining
  , validatedCheckpointCompletionManifest
  , addressedManifest
  , addressedManifestBodyBytes
  , addressedManifestBodySha
  , addressedManifestBytes
  , addressedManifestSha
  , addressedManifestWireVersion
  , tensorSpecFromBlob
  , trialPointerKey
  , validateSupervisedManifestShapeLayout
  , validateSupervisedRuntimePlanForSubstrate
  , weightOnlyTensors
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.Foldable (traverse_)
import Data.List (find, group, sort, sortOn)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import GHC.Generics (Generic)

import JitML.Checkpoint.WeightCodec (decodeJmw1, encodeJmw1)
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Plan.Plan
  ( PlanId
  , RunKind (..)
  , RunKindWitness (..)
  , Validation (..)
  , planIdFromCanonicalText
  , planIdText
  , quantityValue
  , refinePlanIdText
  , runPlanExperimentId
  , runPlanSeeds
  , runPlanSubstrate
  , seedCohortValues
  , validationToEither
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Evidence
  ( TrainingEvidence
  , evidenceDatasetShaAtRead
  , evidenceFinalWeightHash
  , evidenceInitialWeightHash
  , evidenceUpdateCount
  , mkTrainingEvidence
  )
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as Canonicals
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.Regression qualified as Regression
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Substrate qualified as Substrate
import JitML.Training.Budget
  ( BudgetKind (..)
  , CompletedTraining
  , ConvergenceObservation
  , MetricGoal (..)
  , RawCompletedTraining
  , TensorBoardRunMetadata
  , TrainingBudget
  , coMetricName
  , coMetricValue
  , completedTraining
  , completedTrainingBudget
  , completedTrainingDatasetShaAtRead
  , completedTrainingEvidence
  , completedTrainingFinalWeightHash
  , completedTrainingInitialWeightHash
  , completedTrainingMetrics
  , completedTrainingObservedUnits
  , completedTrainingPlanId
  , completedTrainingTensorBoard
  , completedTrainingToRaw
  , completedTrainingUpdateCount
  , convergencePassed
  , measureCriterion
  , measureCriterionExcluding
  , mkTrainingBudget
  , refineCompletedTraining
  , tbrLogPrefix
  , tbrRunId
  , tbrScalarTags
  , trainingBudgetKind
  , trainingBudgetSeed
  , trainingBudgetTargetUnits
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

-- | The manifest-visible projection of one exact supervised runtime.  Writer
-- and decoder both consume this value, so architecture dimensions,
-- preprocessing and output decoding cannot drift into parallel conventions.
data SupervisedRuntimeManifestMetadata = SupervisedRuntimeManifestMetadata
  { supervisedRuntimeArchitectureMetadata :: ArchitectureMetadata
  , supervisedRuntimePreprocessingMetadata :: [PreprocessingMetadata]
  , supervisedRuntimeOutputDecoderMetadata :: [OutputDecoder]
  }
  deriving stock (Eq, Show)

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
  , manifestPlanId :: Maybe PlanId
  , manifestCompletedTraining :: Maybe CompletedTraining
  , manifestInitialWeightHash :: Maybe Text
  , manifestFinalWeightHash :: Maybe Text
  , manifestUpdateCount :: Maybe Word64
  , manifestDatasetShaAtRead :: Maybe Text
  , manifestParentManifestSha :: Maybe Text
  , manifestSupervisedRuntime :: Maybe RuntimeArtifact.SupervisedRuntimePayload
  }
  deriving stock (Eq, Generic, Show)

-- | Versioned, forgeable checkpoint payload.  It contains only a raw
-- completion DTO; refinement is mandatory before a completed manifest can
-- reach an inference consumer.
data RawCheckpointManifest = RawCheckpointManifest
  { rawManifestId :: Text
  , rawManifestExperiment :: Text
  , rawManifestModelFamily :: ModelFamily
  , rawManifestArchitecture :: ArchitectureMetadata
  , rawManifestPreprocessing :: [PreprocessingMetadata]
  , rawManifestOutputDecoders :: [OutputDecoder]
  , rawManifestWeightLayout :: WeightLayout
  , rawManifestReplayPointers :: [ArtifactPointer]
  , rawManifestTranscriptPointers :: [ArtifactPointer]
  , rawManifestSubstrateArtifacts :: [SubstrateArtifact]
  , rawManifestTensors :: [TensorBlob]
  , rawManifestOptimizer :: [OptimizerBlob]
  , rawManifestRng :: [RngBlob]
  , rawManifestStep :: Word64
  , rawManifestMetrics :: [(Text, Double)]
  , rawManifestPlanId :: Maybe Text
  , rawManifestCompletedTraining :: Maybe RawCompletedTraining
  , rawManifestInitialWeightHash :: Maybe Text
  , rawManifestFinalWeightHash :: Maybe Text
  , rawManifestUpdateCount :: Maybe Word64
  , rawManifestDatasetShaAtRead :: Maybe Text
  , rawManifestParentManifestSha :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawCheckpointEnvelope = RawCheckpointEnvelope
  { rawCheckpointVersion :: Word64
  , rawCheckpointPayload :: RawCheckpointManifest
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | V2 has a canonical embedded body whose exact bytes have their own
-- identity.  The V1 manifest DTO is deliberately embedded unchanged so the
-- frozen V1 encoder remains byte-for-byte stable.
data RawCheckpointBodyV2 = RawCheckpointBodyV2
  { rawCheckpointV2Manifest :: RawCheckpointManifest
  , rawCheckpointV2SupervisedRuntime :: RuntimeArtifact.RawSupervisedRuntimePayload
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Exact V2 outer envelope.  The digest is the raw 32-byte SHA-256 of
-- 'rawCheckpointV2BodyBytes'; the address is separately derived from the exact
-- serialized bytes of this whole value.
data RawCheckpointEnvelopeV2 = RawCheckpointEnvelopeV2
  { rawCheckpointV2Version :: Word64
  , rawCheckpointV2BodySha256 :: StrictByteString.ByteString
  , rawCheckpointV2BodyBytes :: StrictByteString.ByteString
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | A decoded checkpoint paired with the exact fetched bytes and their
-- identity.  The constructor is hidden so callers cannot relabel a decoded and
-- re-encoded value as the object that was actually fetched.
data AddressedCheckpointManifest = AddressedCheckpointManifest
  { addressedManifest :: CheckpointManifest
  , addressedManifestWireVersion :: Word64
  , addressedManifestBytes :: LazyByteString.ByteString
  , addressedManifestSha :: Text
  , addressedManifestBodyBytes :: Maybe StrictByteString.ByteString
  , addressedManifestBodySha :: Maybe Text
  }
  deriving stock (Eq, Show)

-- Retained decoder-only DTOs for manifests written before Sprint 10.12.  They
-- mirror the former generic record layout exactly, but are never exposed as
-- proof-bearing values.  The stored verdict is checked against the recomputed
-- typed criterion and then discarded; because the legacy wire carried no
-- canonical PlanId, a legacy manifest always remains a resumable candidate and
-- cannot satisfy the current structural completion refinement.
data LegacyTrainingBudget = LegacyTrainingBudget
  { legacyBudgetKind :: BudgetKind
  , legacyBudgetTargetUnits :: Word64
  , legacyBudgetUnitLabel :: Text
  , legacyBudgetSeed :: Maybe Word64
  }
  deriving stock (Generic)
  deriving anyclass (Serialise)

data LegacyConvergenceObservation = LegacyConvergenceObservation
  { legacyMetricName :: Text
  , legacyMetricValue :: Double
  , legacyMetricGoal :: MetricGoal
  , legacyMetricThreshold :: Maybe Double
  , legacyMetricPassed :: Bool
  }
  deriving stock (Generic)
  deriving anyclass (Serialise)

data LegacyCompletedTraining = LegacyCompletedTraining
  { legacyCompletedBudget :: LegacyTrainingBudget
  , legacyCompletedObservedUnits :: Word64
  , legacyCompletedEvidence :: TrainingEvidence
  , legacyCompletedMetrics :: [LegacyConvergenceObservation]
  , legacyCompletedTensorBoard :: TensorBoardRunMetadata
  }
  deriving stock (Generic)
  deriving anyclass (Serialise)

data LegacyCheckpointManifest = LegacyCheckpointManifest
  { legacyManifestId :: Text
  , legacyManifestExperiment :: Text
  , legacyManifestModelFamily :: ModelFamily
  , legacyManifestArchitecture :: ArchitectureMetadata
  , legacyManifestPreprocessing :: [PreprocessingMetadata]
  , legacyManifestOutputDecoders :: [OutputDecoder]
  , legacyManifestWeightLayout :: WeightLayout
  , legacyManifestReplayPointers :: [ArtifactPointer]
  , legacyManifestTranscriptPointers :: [ArtifactPointer]
  , legacyManifestSubstrateArtifacts :: [SubstrateArtifact]
  , legacyManifestTensors :: [TensorBlob]
  , legacyManifestOptimizer :: [OptimizerBlob]
  , legacyManifestRng :: [RngBlob]
  , legacyManifestStep :: Word64
  , legacyManifestMetrics :: [(Text, Double)]
  , legacyManifestCompletedTraining :: Maybe LegacyCompletedTraining
  , legacyManifestInitialWeightHash :: Maybe Text
  , legacyManifestFinalWeightHash :: Maybe Text
  , legacyManifestUpdateCount :: Maybe Word64
  , legacyManifestDatasetShaAtRead :: Maybe Text
  , legacyManifestParentManifestSha :: Maybe Text
  }
  deriving stock (Generic)
  deriving anyclass (Serialise)

-- | Pure structural completion refinement.  Its constructor is hidden;
-- candidate and partial manifests remain inspectable but cannot inhabit this
-- type.  This value makes no claim that the manifest or any referenced payload
-- was persisted, addressed, or observed through a stable pointer.  Store owns
-- those independent admission guarantees.
data ValidatedCheckpointCompletion = ValidatedCheckpointCompletion
  { validatedCheckpointCompletionManifest :: CheckpointManifest
  , validatedCheckpointCompletedTraining :: CompletedTraining
  }
  deriving stock (Eq, Show)

data CheckpointCompletionValidationError
  = MissingCompletedTraining
  | SupervisedRuntimeArtifactMissing
  | CompletedTrainingHasNoMetrics
  | CompletedTrainingHasFailedMetrics [Text]
  | CompletedTrainingExternalBarMismatch [Text]
  | CompletedTrainingOutrunsManifest Word64 Word64
  | CompletedTrainingEvidenceMissing
  | CompletedTrainingEvidenceInvalid Text
  | CompletedTrainingEvidenceMismatch
  | CompletedTrainingPlanIdMissing
  | CompletedTrainingPlanIdMismatch Text Text
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
  | PointerNotWritten Text
  deriving stock (Eq, Show)

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
    , manifestPlanId = Nothing
    , manifestCompletedTraining = Nothing
    , manifestInitialWeightHash = Nothing
    , manifestFinalWeightHash = Nothing
    , manifestUpdateCount = Nothing
    , manifestDatasetShaAtRead = Nothing
    , manifestParentManifestSha = Nothing
    , manifestSupervisedRuntime = Nothing
    }

attachCompletedTraining :: CompletedTraining -> CheckpointManifest -> CheckpointManifest
attachCompletedTraining completed manifest =
  manifest
    { manifestPlanId = Just (completedTrainingPlanId completed)
    , manifestCompletedTraining = Just completed
    , manifestInitialWeightHash = Just (completedTrainingInitialWeightHash completed)
    , manifestFinalWeightHash = Just (completedTrainingFinalWeightHash completed)
    , manifestUpdateCount = Just (completedTrainingUpdateCount completed)
    , manifestDatasetShaAtRead = Just (completedTrainingDatasetShaAtRead completed)
    }

manifestTrainingEvidence
  :: CheckpointManifest
  -> Either CheckpointCompletionValidationError TrainingEvidence
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

validateCheckpointCompletion
  :: CheckpointManifest
  -> Either CheckpointCompletionValidationError ValidatedCheckpointCompletion
validateCheckpointCompletion manifest =
  if isInspectionOnlySupervisedV1 manifest
    then Left SupervisedRuntimeArtifactMissing
    else case manifestCompletedTraining manifest of
      Nothing -> Left MissingCompletedTraining
      Just completed
        | Nothing <- manifestPlanId manifest ->
            Left CompletedTrainingPlanIdMissing
        | Just manifestPlan <- manifestPlanId manifest
        , manifestPlan /= completedTrainingPlanId completed ->
            Left
              ( CompletedTrainingPlanIdMismatch
                  (planIdText (completedTrainingPlanId completed))
                  (planIdText manifestPlan)
              )
        | completedTrainingObservedUnits completed /= manifestStep manifest ->
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
                        externalBarErrors =
                          case manifestSupervisedRuntime manifest of
                            Just payload ->
                              case find
                                ( (== RuntimeArtifact.payloadRowId payload)
                                    . ProductMatrix.rowId
                                )
                                ProductMatrix.allProductRows of
                                Just row ->
                                  ExternalBars.assertConvergenceObservationsAgainstBar
                                    (ProductMatrix.convergenceBar row)
                                    (completedTrainingMetrics completed)
                                Nothing ->
                                  ["supervised V2 runtime has no canonical convergence row"]
                            Nothing ->
                              case ProductMatrix.productRowForExperimentHash
                                (manifestExperiment manifest) of
                                Just row ->
                                  ExternalBars.assertConvergenceObservationsAgainstBar
                                    (ProductMatrix.convergenceBar row)
                                    (completedTrainingMetrics completed)
                                Nothing ->
                                  ExternalBars.assertConvergenceObservationsExternal
                                    (completedTrainingMetrics completed)
                     in case filter (not . convergencePassed) (completedTrainingMetrics completed) of
                          []
                            | not (null externalBarErrors) ->
                                Left (CompletedTrainingExternalBarMismatch externalBarErrors)
                            | not (null supervisedShapeLayoutErrors) ->
                                Left (SupervisedManifestShapeLayoutInvalid supervisedShapeLayoutErrors)
                            | otherwise ->
                                Right
                                  ValidatedCheckpointCompletion
                                    { validatedCheckpointCompletionManifest = manifest
                                    , validatedCheckpointCompletedTraining = completed
                                    }
                          failed ->
                            Left (CompletedTrainingHasFailedMetrics (fmap coMetricName failed))

isInspectionOnlySupervisedV1 :: CheckpointManifest -> Bool
isInspectionOnlySupervisedV1 manifest =
  isNothing (manifestSupervisedRuntime manifest)
    && ( manifestModelFamily manifest == SupervisedModelFamily
           || architectureModelFamily (manifestArchitecture manifest)
             == SupervisedModelFamily
           || maybe
             False
             ( (== SupervisedEpochBudget)
                 . trainingBudgetKind
                 . completedTrainingBudget
             )
             (manifestCompletedTraining manifest)
           || case ProductMatrix.productRowForExperimentHash (manifestExperiment manifest) of
             Just row -> ProductMatrix.family row == ProductMatrix.Supervised
             Nothing -> False
       )

validateSupervisedManifestShapeLayout :: CheckpointManifest -> [Text]
validateSupervisedManifestShapeLayout manifest
  | Just runtimePayload <- manifestSupervisedRuntime manifest =
      validateSupervisedV2Bindings manifest runtimePayload
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

-- | Validate an exact runtime against the canonical problem row carried by
-- its closed execution origin and derive the only
-- architecture/preprocessing/decoder metadata accepted by V2.  Product
-- origins re-project the authoritative ProductRow; generic origins bind the
-- row together with a canonical exact-plan transport in the addressed body.
-- The classification topology comes from the same LayerSpecs used by
-- training; the California transforms retain their fitted values but are
-- checked against the row's fixed production widths and regressor topology.
canonicalSupervisedRuntimeManifestMetadata
  :: RuntimeArtifact.SupervisedRuntimePayload
  -> Either Text SupervisedRuntimeManifestMetadata
canonicalSupervisedRuntimeManifestMetadata payload = do
  problem <- authoritativeSupervisedRuntimeProblem payload
  validateAuthoritativeRuntime problem (RuntimeArtifact.payloadRuntime payload)
  let runtime = RuntimeArtifact.payloadRuntime payload
      inputSpec =
        TensorSpec
          { tensorSpecName = "input"
          , tensorSpecShape = [RuntimeArtifact.supervisedRuntimeInputWidth runtime]
          , tensorSpecDtype = "F64"
          }
      outputSpec =
        TensorSpec
          { tensorSpecName = "raw-output"
          , tensorSpecShape = [RuntimeArtifact.supervisedRuntimeRawOutputWidth runtime]
          , tensorSpecDtype = "F64"
          }
      task = RuntimeArtifact.supervisedRuntimeTask runtime
      semanticWidth = RuntimeArtifact.runtimeTaskSemanticWidth task
      isClassification = RuntimeArtifact.runtimeTaskIsClassification task
      rawInput =
        RuntimeArtifact.runtimeInputTransformToRaw
          (RuntimeArtifact.supervisedRuntimeInputTransform runtime)
      rawOutput =
        RuntimeArtifact.runtimeOutputTransformToRaw
          (RuntimeArtifact.supervisedRuntimeOutputTransform runtime)
      decoder =
        OutputDecoder
          { outputDecoderName = "prediction"
          , outputDecoderKind =
              if isClassification then ClassificationOutput else RegressionOutput
          , outputDecoderLabels =
              if isClassification
                then fmap (("class-" <>) . Text.pack . show) [0 .. semanticWidth - 1]
                else []
          , outputDecoderUnits =
              if isClassification then Nothing else Just "median-house-value"
          , outputDecoderArtifactKind =
              Just
                ( "supervised-runtime-v2/"
                    <> renderRuntimeOutputTransform rawOutput
                )
          }
  Right
    SupervisedRuntimeManifestMetadata
      { supervisedRuntimeArchitectureMetadata =
          ArchitectureMetadata
            { architectureName =
                "supervised-runtime-v2/" <> RuntimeArtifact.payloadRowId payload
            , architectureModelFamily = SupervisedModelFamily
            , architectureInputs = [inputSpec]
            , architectureOutputs = [outputSpec]
            , architectureLayerGraph = Nothing
            }
      , supervisedRuntimePreprocessingMetadata =
          [ PreprocessingMetadata
              { preprocessingName = "supervised-runtime-v2-input"
              , preprocessingSteps = renderRuntimeInputTransform rawInput
              , preprocessingInputs = [inputSpec]
              }
          ]
      , supervisedRuntimeOutputDecoderMetadata = [decoder]
      }

authoritativeSupervisedRuntimeProblem
  :: RuntimeArtifact.SupervisedRuntimePayload
  -> Either Text Canonicals.CanonicalProblem
authoritativeSupervisedRuntimeProblem payload = do
  row <- authoritativeSupervisedRuntimeRow payload
  requireRuntimeContract
    "ProductRow family"
    ProductMatrix.Supervised
    (ProductMatrix.family row)
  _ <- resolveSupervisedRuntimePlanBinding row payload
  problem <-
    maybe
      ( Left
          ( "runtime ProductRow has no authoritative canonical problem: "
              <> ProductMatrix.rowId row
          )
      )
      Right
      ( find
          ((== ProductMatrix.rowId row) . Canonicals.problemName)
          Canonicals.canonicalProblems
      )
  validateCanonicalProblemRow row problem
  Right problem

-- | Require the payload's closed origin to bind the selected substrate.
-- Product origins derive it from the unique authoritative projection; generic
-- origins derive it from the exact re-parsed plan transport.  Engines call
-- this before probing hardware or loading weights.
validateSupervisedRuntimePlanForSubstrate
  :: Substrate.Substrate
  -> RuntimeArtifact.SupervisedRuntimePayload
  -> Either Text ()
validateSupervisedRuntimePlanForSubstrate substrate payload = do
  row <- authoritativeSupervisedRuntimeRow payload
  binding <- resolveSupervisedRuntimePlanBinding row payload
  let boundPlan = supervisedRuntimeBindingPlan binding
  requireRuntimeContract
    "runtime selected substrate"
    substrate
    ( runPlanSubstrate
        (WorkloadPlan.supervisedPlanRunPlan boundPlan)
    )

authoritativeSupervisedRuntimeRow
  :: RuntimeArtifact.SupervisedRuntimePayload
  -> Either Text (ProductMatrix.ProductRow 'ProductMatrix.Declared)
authoritativeSupervisedRuntimeRow payload =
  maybe
    ( Left
        ( "runtime does not identify an authoritative ProductRow: "
            <> RuntimeArtifact.payloadRowId payload
        )
    )
    Right
    ( find
        ((== RuntimeArtifact.payloadRowId payload) . ProductMatrix.rowId)
        ProductMatrix.allProductRows
    )

data SupervisedRuntimePlanBinding
  = GenericSupervisedExecutionBinding !Text !WorkloadPlan.SupervisedPlan
  | ProductRowSupervisedRuntimePlanBinding
      !(ProductMatrix.ProductProjection 'SupervisedTraining)

supervisedRuntimeBindingPlan
  :: SupervisedRuntimePlanBinding -> WorkloadPlan.SupervisedPlan
supervisedRuntimeBindingPlan binding =
  case binding of
    GenericSupervisedExecutionBinding _ plan -> plan
    ProductRowSupervisedRuntimePlanBinding projection ->
      case ProductMatrix.productProjectionResolvedPlan projection of
        ProductMatrix.ResolvedSupervisedProductPlan plan -> plan

supervisedRuntimeBindingBudget
  :: SupervisedRuntimePlanBinding -> Either Text TrainingBudget
supervisedRuntimeBindingBudget binding =
  case binding of
    ProductRowSupervisedRuntimePlanBinding projection ->
      Right (ProductMatrix.productProjectionTrainingBudget projection)
    GenericSupervisedExecutionBinding _ plan ->
      mkTrainingBudget
        SupervisedEpochBudget
        (quantityValue (WorkloadPlan.supervisedPlanEpochs plan))
        ( Just
            ( NonEmpty.head
                ( seedCohortValues
                    (runPlanSeeds (WorkloadPlan.supervisedPlanRunPlan plan))
                )
            )
        )

resolveSupervisedRuntimePlanBinding
  :: ProductMatrix.ProductRow state
  -> RuntimeArtifact.SupervisedRuntimePayload
  -> Either Text SupervisedRuntimePlanBinding
resolveSupervisedRuntimePlanBinding row payload =
  case RuntimeArtifact.supervisedRuntimeOriginToRaw
    (RuntimeArtifact.payloadOrigin payload) of
    RuntimeArtifact.RawProductRowProjectionOrigin ->
      ProductRowSupervisedRuntimePlanBinding
        <$> authoritativeSupervisedProjection row payload
    RuntimeArtifact.RawGenericSupervisedExecutionOrigin originRowId transport -> do
      requireRuntimeContract
        "generic supervised execution origin row id"
        (ProductMatrix.rowId row)
        originRowId
      requireRuntimeContract
        "generic supervised execution payload row id"
        (RuntimeArtifact.payloadRowId payload)
        originRowId
      plan <-
        case validationToEither
          (WorkloadPlan.parseSupervisedPlanTransport transport) of
          Left errors ->
            Left
              ( "generic supervised runtime plan transport is invalid: "
                  <> Text.pack (show errors)
              )
          Right value -> Right value
      requireRuntimeContract
        "generic supervised runtime canonical plan transport"
        (WorkloadPlan.renderSupervisedPlanTransport plan)
        transport
      requireRuntimeContract
        "generic supervised runtime PlanId"
        (WorkloadPlan.supervisedPlanId plan)
        (RuntimeArtifact.payloadPlanId payload)
      case ProductMatrix.productRowForExperimentHash
        (runPlanExperimentId (WorkloadPlan.supervisedPlanRunPlan plan)) of
        Nothing -> Right ()
        Just productRow ->
          Left
            ( "generic supervised runtime plan occupies authoritative ProductRow experiment identity "
                <> ProductMatrix.rowId productRow
            )
      Right (GenericSupervisedExecutionBinding originRowId plan)

-- | Re-project the authoritative row for every supported substrate, then let
-- the payload PlanId select exactly one opaque supervised projection.  The
-- returned value carries the resolved workload plan as well as the ProductRow
-- budget, so downstream completion checks cannot reconstruct either contract
-- from independently supplied manifest fields.
authoritativeSupervisedProjection
  :: ProductMatrix.ProductRow state
  -> RuntimeArtifact.SupervisedRuntimePayload
  -> Either
       Text
       (ProductMatrix.ProductProjection 'SupervisedTraining)
authoritativeSupervisedProjection row payload = do
  case RuntimeArtifact.supervisedRuntimeOriginToRaw
    (RuntimeArtifact.payloadOrigin payload) of
    RuntimeArtifact.RawProductRowProjectionOrigin -> Right ()
    RuntimeArtifact.RawGenericSupervisedExecutionOrigin {} ->
      Left "generic supervised runtime origin cannot be admitted as a ProductRow projection"
  projections <-
    traverse
      (`authoritativeSupervisedProjectionForSubstrate` row)
      Substrate.allSubstrates
  let matches =
        [ projection
        | projection <- projections
        , ProductMatrix.productProjectionPlanId projection
            == RuntimeArtifact.payloadPlanId payload
        ]
  case matches of
    [projection] -> Right projection
    [] ->
      Left
        ( "runtime PlanId does not equal any authoritative ProductRow substrate projection: "
            <> RuntimeArtifact.payloadPlanIdText payload
        )
    _ ->
      Left
        "runtime PlanId ambiguously matches multiple authoritative substrate projections"

authoritativeSupervisedProjectionForSubstrate
  :: Substrate.Substrate
  -> ProductMatrix.ProductRow state
  -> Either
       Text
       (ProductMatrix.ProductProjection 'SupervisedTraining)
authoritativeSupervisedProjectionForSubstrate substrate row =
  case validationToEither (ProductMatrix.projectProductRow substrate row) of
    Left errors ->
      Left
        ( "authoritative ProductRow projection failed for "
            <> Substrate.renderSubstrate substrate
            <> ": "
            <> Text.pack (show errors)
        )
    Right
      ( ProductMatrix.SomeProductProjection
          SupervisedTrainingWitness
          projection
        ) -> Right projection
    Right _ ->
      Left
        ( "authoritative ProductRow projection is not supervised for "
            <> Substrate.renderSubstrate substrate
        )

validateCanonicalProblemRow
  :: ProductMatrix.ProductRow state
  -> Canonicals.CanonicalProblem
  -> Either Text ()
validateCanonicalProblemRow row problem =
  case ProductMatrix.rowClass row of
    ProductMatrix.SupervisedClassification dataset model -> do
      requireRuntimeContract "ProductRow dataset" dataset (Canonicals.problemDataset problem)
      requireRuntimeContract "ProductRow model" model (Canonicals.problemModel problem)
      if Canonicals.problemDataset problem == "California Housing"
        then Left "California Housing ProductRow must be regression"
        else Right ()
    ProductMatrix.SupervisedRegression dataset model -> do
      requireRuntimeContract "ProductRow dataset" dataset (Canonicals.problemDataset problem)
      requireRuntimeContract "ProductRow model" model (Canonicals.problemModel problem)
      if Canonicals.problemDataset problem == "California Housing"
        then Right ()
        else Left "only the authoritative California Housing row is regression"
    _ -> Left "runtime ProductRow is not supervised"

validateAuthoritativeRuntime
  :: Canonicals.CanonicalProblem
  -> RuntimeArtifact.SupervisedRuntime
  -> Either Text ()
validateAuthoritativeRuntime problem runtime
  | Canonicals.problemDataset problem == "California Housing" =
      validateCaliforniaRuntime runtime
  | otherwise = do
      (inputWidth, semanticWidth) <- classificationProductionDimensions problem
      let config =
            Classifier.defaultClassifierConfig
              { Classifier.clfSeed = Canonicals.problemSeed problem
              , Classifier.clfInputs = inputWidth
              , Classifier.clfClasses = semanticWidth
              }
      expected <- Architecture.canonicalClassificationRuntimeContract config problem
      requireRuntimeContract
        "classification production input width"
        inputWidth
        (RuntimeArtifact.supervisedRuntimeInputWidth runtime)
      requireRuntimeContract
        "classification production raw-output width"
        (semanticWidth + 1)
        (RuntimeArtifact.supervisedRuntimeRawOutputWidth runtime)
      validateClassificationRuntimeContract
        problem
        expected
        (RuntimeArtifact.supervisedRuntimeToRaw runtime)

classificationProductionDimensions
  :: Canonicals.CanonicalProblem
  -> Either Text (Int, Int)
classificationProductionDimensions problem =
  case Canonicals.problemDataset problem of
    "MNIST" -> Right (784, 10)
    "Fashion-MNIST" -> Right (784, 10)
    "CIFAR-10" -> Right (3072, 10)
    "CIFAR-100" -> Right (3072, 100)
    "Tiny ImageNet" -> Right (12288, 200)
    dataset ->
      Left
        ( "no authoritative classification dimensions for dataset "
            <> dataset
        )

validateClassificationRuntimeContract
  :: Canonicals.CanonicalProblem
  -> RuntimeArtifact.RawSupervisedRuntime
  -> RuntimeArtifact.RawSupervisedRuntime
  -> Either Text ()
validateClassificationRuntimeContract problem expected actual = do
  requireRuntimeContract
    "classification runtime family"
    (RuntimeArtifact.rawSupervisedRuntimeFamily expected)
    (RuntimeArtifact.rawSupervisedRuntimeFamily actual)
  requireRuntimeContract
    "classification runtime task"
    (RuntimeArtifact.rawSupervisedRuntimeTask expected)
    (RuntimeArtifact.rawSupervisedRuntimeTask actual)
  validateClassificationInputTransform
    problem
    (RuntimeArtifact.rawSupervisedRuntimeInputTransform expected)
    (RuntimeArtifact.rawSupervisedRuntimeInputTransform actual)
  requireRuntimeContract
    "classification output transform"
    (RuntimeArtifact.rawSupervisedRuntimeOutputTransform expected)
    (RuntimeArtifact.rawSupervisedRuntimeOutputTransform actual)
  requireRuntimeContract
    "classification runtime topology"
    (RuntimeArtifact.rawSupervisedRuntimeLayers expected)
    (RuntimeArtifact.rawSupervisedRuntimeLayers actual)

-- | The current CIFAR-10 ViT is the sole classification row whose exact
-- training program fits an ingress transform.  Its three population RGB
-- statistics are fitted from the authoritative training partition and then
-- repeated in pixel-major channel order across the 32x32 image.  Admission can
-- validate that complete structural contract without pretending to refit from
-- checkpoint metadata; every other classification row retains exact equality
-- with its canonical unit-image transform.
validateClassificationInputTransform
  :: Canonicals.CanonicalProblem
  -> RuntimeArtifact.RawRuntimeInputTransform
  -> RuntimeArtifact.RawRuntimeInputTransform
  -> Either Text ()
validateClassificationInputTransform problem expected actual
  | Canonicals.problemName problem == "cifar10-vit" =
      case actual of
        RuntimeArtifact.RawStandardizeInput means scales -> do
          requireRuntimeContract
            "cifar10-vit standardization mean width"
            cifar10InputWidth
            (length means)
          requireRuntimeContract
            "cifar10-vit standardization scale width"
            cifar10InputWidth
            (length scales)
          if all (\meanValue -> isFinite meanValue && meanValue >= 0.0 && meanValue <= 1.0) means
            then Right ()
            else Left "cifar10-vit standardization means must be finite decoded-unit values"
          if all (\scale -> isFinite scale && scale > 0.0 && scale <= 0.5) scales
            then Right ()
            else
              Left
                "cifar10-vit standardization scales must be finite positive decoded-unit population scales"
          if repeatsRgb means
            then Right ()
            else Left "cifar10-vit standardization means must repeat one RGB triplet per pixel"
          if repeatsRgb scales
            then Right ()
            else Left "cifar10-vit standardization scales must repeat one RGB triplet per pixel"
        _ ->
          Left
            "cifar10-vit classification input transform must be fitted RGB standardization"
  | otherwise =
      requireRuntimeContract
        "classification input transform"
        expected
        actual
 where
  cifar10InputWidth = 32 * 32 * 3
  repeatsRgb values =
    case take 3 values of
      [red, green, blue] ->
        values == concat (replicate (cifar10InputWidth `div` 3) [red, green, blue])
      _ -> False
  isFinite value = not (isNaN value || isInfinite value)

validateCaliforniaRuntime :: RuntimeArtifact.SupervisedRuntime -> Either Text ()
validateCaliforniaRuntime runtime = do
  let raw = RuntimeArtifact.supervisedRuntimeToRaw runtime
      inputWidth = Regression.regInputs Regression.defaultRegressionConfig
      hiddenWidth = Regression.regHidden Regression.defaultRegressionConfig
      semanticWidth = 1
  requireRuntimeContract
    "California runtime family"
    RuntimeArtifact.RawTabularRegressionRuntimeFamily
    (RuntimeArtifact.rawSupervisedRuntimeFamily raw)
  requireRuntimeContract
    "California runtime task"
    (RuntimeArtifact.RawRegressionRuntimeTask semanticWidth)
    (RuntimeArtifact.rawSupervisedRuntimeTask raw)
  requireRuntimeContract
    "California production input width"
    inputWidth
    (RuntimeArtifact.supervisedRuntimeInputWidth runtime)
  requireRuntimeContract
    "California production raw-output width"
    semanticWidth
    (RuntimeArtifact.supervisedRuntimeRawOutputWidth runtime)
  case RuntimeArtifact.rawSupervisedRuntimeInputTransform raw of
    RuntimeArtifact.RawStandardizeInput means scales -> do
      requireRuntimeContract "California standardization mean width" inputWidth (length means)
      requireRuntimeContract "California standardization scale width" inputWidth (length scales)
    _ -> Left "California runtime requires fitted standardization input"
  case RuntimeArtifact.rawSupervisedRuntimeOutputTransform raw of
    RuntimeArtifact.RawDestandardizeOutput means scales -> do
      requireRuntimeContract "California target mean width" semanticWidth (length means)
      requireRuntimeContract "California target scale width" semanticWidth (length scales)
    _ -> Left "California runtime requires fitted target destandardization"
  requireRuntimeContract
    "California runtime topology"
    [ RuntimeArtifact.RawDenseLayer
        "regressor"
        (RuntimeArtifact.RawRuntimeMlpShape inputWidth hiddenWidth semanticWidth)
    ]
    (RuntimeArtifact.rawSupervisedRuntimeLayers raw)

requireRuntimeContract :: (Eq value, Show value) => Text -> value -> value -> Either Text ()
requireRuntimeContract label expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( label
            <> " differs from the authoritative ProductRow contract: expected "
            <> Text.pack (show expected)
            <> ", got "
            <> Text.pack (show actual)
        )

renderRuntimeInputTransform
  :: RuntimeArtifact.RawRuntimeInputTransform -> [Text]
renderRuntimeInputTransform raw =
  case raw of
    RuntimeArtifact.RawIdentityInput width ->
      ["identity", "width=" <> Text.pack (show width)]
    RuntimeArtifact.RawUnitImageInput geometry ->
      [ "unit-image-[0,1]"
      , "geometry=" <> Text.pack (show geometry)
      ]
    RuntimeArtifact.RawStandardizeInput means scales ->
      [ "standardize"
      , "means=" <> Text.pack (show means)
      , "scales=" <> Text.pack (show scales)
      ]

renderRuntimeOutputTransform
  :: RuntimeArtifact.RawRuntimeOutputTransform -> Text
renderRuntimeOutputTransform raw =
  case raw of
    RuntimeArtifact.RawIdentityOutput -> "identity"
    RuntimeArtifact.RawSemanticPrefixOutput width ->
      "semantic-prefix/" <> Text.pack (show width)
    RuntimeArtifact.RawDestandardizeOutput means scales ->
      "destandardize/means="
        <> Text.pack (show means)
        <> "/scales="
        <> Text.pack (show scales)

-- | Cross-bind the independently refined runtime program, closed execution
-- origin, completion witness, manifest fields, physical tensor and
-- graph-ordered virtual layout.  The object store still has to verify the
-- referenced JMW1 bytes; this function makes it impossible for a valid V2 body
-- to describe a different row, run or flat-vector interpretation.
validateSupervisedV2Bindings
  :: CheckpointManifest
  -> RuntimeArtifact.SupervisedRuntimePayload
  -> [Text]
validateSupervisedV2Bindings manifest payload =
  concat
    [ modelFamilyErrors
    , productRowErrors
    , runtimeMetadataErrors
    , planErrors
    , datasetErrors
    , weightHashErrors
    , completionErrors
    , tensorErrors
    , flatLayoutErrors
    ]
 where
  runtime = RuntimeArtifact.payloadRuntime payload
  runtimePlan = RuntimeArtifact.payloadPlanId payload
  runtimeDatasetSha = RuntimeArtifact.payloadDatasetSha256 payload
  runtimeInitialSha = RuntimeArtifact.payloadInitialJmw1Sha256 payload
  runtimeFinalSha = RuntimeArtifact.payloadFinalJmw1Sha256 payload
  parameterCount = RuntimeArtifact.supervisedRuntimeParameterCount runtime
  expectedTensorKey = blobKey (manifestExperiment manifest) runtimeFinalSha
  expectedLayout =
    fmap
      ( \slice ->
          TensorSpec
            { tensorSpecName = RuntimeArtifact.runtimeVirtualSliceQualifiedName slice
            , tensorSpecShape = RuntimeArtifact.runtimeVirtualSliceShape slice
            , tensorSpecDtype = "F64"
            }
      )
      (RuntimeArtifact.supervisedRuntimeVirtualSlices runtime)

  modelFamilyErrors =
    [ "V2 supervised runtime requires SupervisedModelFamily"
    | manifestModelFamily manifest /= SupervisedModelFamily
    ]
      <> [ "V2 supervised architecture metadata requires SupervisedModelFamily"
         | architectureModelFamily (manifestArchitecture manifest) /= SupervisedModelFamily
         ]

  productRowErrors =
    case find
      ((== RuntimeArtifact.payloadRowId payload) . ProductMatrix.rowId)
      ProductMatrix.allProductRows of
      Nothing ->
        [ "V2 supervised runtime does not identify an authoritative ProductRow: "
            <> RuntimeArtifact.payloadRowId payload
        ]
      Just row ->
        [ "V2 runtime ProductRow is not supervised: " <> ProductMatrix.rowId row
        | ProductMatrix.family row /= ProductMatrix.Supervised
        ]
          <> case resolveSupervisedRuntimePlanBinding row payload of
            Left err -> ["V2 supervised runtime origin is invalid: " <> err]
            Right binding ->
              let boundExperiment =
                    runPlanExperimentId
                      ( WorkloadPlan.supervisedPlanRunPlan
                          (supervisedRuntimeBindingPlan binding)
                      )
                  commonErrors =
                    [ "V2 manifest experiment does not equal the bound supervised plan experiment"
                    | manifestExperiment manifest /= boundExperiment
                    ]
               in commonErrors
                    <> case binding of
                      GenericSupervisedExecutionBinding _ _ ->
                        [ "generic supervised V2 manifest cannot occupy an authoritative ProductRow experiment hash"
                        | isJust
                            ( ProductMatrix.productRowForExperimentHash
                                (manifestExperiment manifest)
                            )
                        ]
                      ProductRowSupervisedRuntimePlanBinding _ ->
                        [ "V2 manifest experiment does not equal the authoritative supervised ProductRow experiment hash"
                        | manifestExperiment manifest
                            /= ProductMatrix.productRowExperimentHash row
                        ]
                          <> case ProductMatrix.productRowForExperimentHash
                            (manifestExperiment manifest) of
                            Nothing ->
                              ["V2 manifest experiment does not identify an authoritative ProductRow"]
                            Just experimentRow ->
                              [ "V2 runtime row identity does not match the ProductRow named by manifest experiment: expected "
                                  <> ProductMatrix.rowId experimentRow
                                  <> ", got "
                                  <> RuntimeArtifact.payloadRowId payload
                              | ProductMatrix.rowId experimentRow
                                  /= RuntimeArtifact.payloadRowId payload
                              ]

  runtimeMetadataErrors =
    case canonicalSupervisedRuntimeManifestMetadata payload of
      Left err ->
        ["V2 supervised runtime violates its canonical runtime/plan contract: " <> err]
      Right metadata ->
        [ "V2 manifest architecture metadata does not equal the exact runtime projection"
        | manifestArchitecture manifest
            /= supervisedRuntimeArchitectureMetadata metadata
        ]
          <> [ "V2 manifest preprocessing metadata does not equal the exact runtime projection"
             | manifestPreprocessing manifest
                 /= supervisedRuntimePreprocessingMetadata metadata
             ]
          <> [ "V2 manifest output-decoder metadata does not equal the exact runtime projection"
             | manifestOutputDecoders manifest
                 /= supervisedRuntimeOutputDecoderMetadata metadata
             ]

  planErrors =
    case manifestPlanId manifest of
      Nothing -> ["V2 supervised manifest is missing its PlanId"]
      Just manifestPlan ->
        [ "V2 runtime PlanId does not match manifest PlanId: expected "
            <> planIdText manifestPlan
            <> ", got "
            <> RuntimeArtifact.payloadPlanIdText payload
        | manifestPlan /= runtimePlan
        ]

  datasetErrors =
    case authoritativeSupervisedRuntimeProblem payload
      >>= Dataset.canonicalDatasetReadShaForProblem of
      Left err ->
        ["V2 supervised runtime canonical dataset contract is invalid: " <> err]
      Right expectedDatasetSha ->
        [ "V2 runtime payload dataset SHA-256 does not equal the canonical training/evaluation read SHA-256"
        | runtimeDatasetSha /= expectedDatasetSha
        ]
          <> case manifestDatasetShaAtRead manifest of
            Nothing -> ["V2 supervised manifest is missing its dataset-at-read SHA-256"]
            Just manifestDatasetSha ->
              [ "V2 runtime dataset SHA-256 does not match manifest dataset-at-read SHA-256"
              | manifestDatasetSha /= runtimeDatasetSha
              ]
                <> [ "V2 manifest dataset-at-read SHA-256 does not equal the canonical training/evaluation read SHA-256"
                   | manifestDatasetSha /= expectedDatasetSha
                   ]
          <> case manifestCompletedTraining manifest of
            Nothing -> []
            Just completed ->
              [ "V2 completed-training dataset SHA-256 does not equal the canonical training/evaluation read SHA-256"
              | completedTrainingDatasetShaAtRead completed /= expectedDatasetSha
              ]

  weightHashErrors =
    maybeTextBindingErrors
      "initial-weight SHA-256"
      runtimeInitialSha
      (manifestInitialWeightHash manifest)
      <> maybeTextBindingErrors
        "final-weight SHA-256"
        runtimeFinalSha
        (manifestFinalWeightHash manifest)

  completionErrors =
    case manifestCompletedTraining manifest of
      Nothing -> ["V2 supervised manifest is missing completed training"]
      Just completed ->
        concat
          [ [ "V2 runtime PlanId does not match completed training PlanId"
            | completedTrainingPlanId completed /= runtimePlan
            ]
          , [ "V2 runtime dataset SHA-256 does not match completed training dataset SHA-256"
            | completedTrainingDatasetShaAtRead completed /= runtimeDatasetSha
            ]
          , [ "V2 runtime initial-weight SHA-256 does not match completed training"
            | completedTrainingInitialWeightHash completed /= runtimeInitialSha
            ]
          , [ "V2 runtime final-weight SHA-256 does not match completed training"
            | completedTrainingFinalWeightHash completed /= runtimeFinalSha
            ]
          , [ "V2 completed training observed budget does not match manifest step"
            | completedTrainingObservedUnits completed /= manifestStep manifest
            ]
          , case manifestUpdateCount manifest of
              Nothing -> ["V2 supervised manifest is missing its update count"]
              Just updateCount ->
                [ "V2 completed training update count does not match manifest update count"
                | completedTrainingUpdateCount completed /= updateCount
                ]
          , completionMetricBindingErrors completed
          , tensorBoardBindingErrors completed
          , authoritativeCompletionContractErrors completed
          ]

  completionMetricBindingErrors completed =
    duplicateManifestMetricErrors
      <> concatMap requireObservationMetric observations
   where
    observations = completedTrainingMetrics completed
    manifestRows = manifestMetrics manifest
    duplicateManifestMetricErrors =
      [ "V2 supervised manifest has duplicate metric name " <> name
      | name : _ : _ <- group (sort (fmap fst manifestRows))
      ]
    requireObservationMetric observation =
      case [ value
           | (name, value) <- manifestRows
           , name == coMetricName observation
           ] of
        [] ->
          [ "V2 supervised manifest is missing completed-training metric "
              <> coMetricName observation
          ]
        [value]
          | value == coMetricValue observation -> []
          | otherwise ->
              [ "V2 supervised manifest metric differs from completed training: "
                  <> coMetricName observation
              ]
        _ ->
          [ "V2 supervised manifest metric is not unique: "
              <> coMetricName observation
          ]

  tensorBoardBindingErrors completed =
    let tensorBoard = completedTrainingTensorBoard completed
        expectedPrefix = "jitml-tensorboard/" <> manifestExperiment manifest
        expectedTags = fmap coMetricName (completedTrainingMetrics completed)
     in concat
          [ [ "V2 completed-training TensorBoard run id does not match manifest experiment"
            | tbrRunId tensorBoard /= manifestExperiment manifest
            ]
          , [ "V2 completed-training TensorBoard log prefix does not match manifest experiment"
            | tbrLogPrefix tensorBoard /= expectedPrefix
            ]
          , [ "V2 completed-training TensorBoard scalar tags do not exactly match convergence metrics"
            | tbrScalarTags tensorBoard /= expectedTags
            ]
          ]

  authoritativeCompletionContractErrors completed =
    case do
      row <- authoritativeSupervisedRuntimeRow payload
      binding <- resolveSupervisedRuntimePlanBinding row payload
      budget <- supervisedRuntimeBindingBudget binding
      Right (binding, budget) of
      Left err ->
        [ "V2 supervised completion cannot derive its exact plan binding: "
            <> err
        ]
      Right (binding, boundBudget) ->
        let supervisedPlan = supervisedRuntimeBindingPlan binding
            completedBudget = completedTrainingBudget completed
            boundEpochs =
              quantityValue
                (WorkloadPlan.supervisedPlanEpochs supervisedPlan)
            boundOptimizerUpdates =
              quantityValue
                (WorkloadPlan.supervisedPlanOptimizerUpdates supervisedPlan)
            budgetOwner =
              case binding of
                ProductRowSupervisedRuntimePlanBinding _ ->
                  "authoritative ProductRow training budget"
                GenericSupervisedExecutionBinding _ _ ->
                  "exact generic SupervisedPlan training budget"
         in concat
              [ [ "V2 completed training budget kind does not match the " <> budgetOwner
                | trainingBudgetKind completedBudget
                    /= trainingBudgetKind boundBudget
                ]
              , [ "V2 completed training budget target does not match the " <> budgetOwner
                | trainingBudgetTargetUnits completedBudget
                    /= trainingBudgetTargetUnits boundBudget
                ]
              , [ "V2 completed training budget seed does not match the " <> budgetOwner
                | trainingBudgetSeed completedBudget
                    /= trainingBudgetSeed boundBudget
                ]
              , [ "V2 completed training observed epoch units do not match the authoritative SupervisedPlan epoch count"
                | completedTrainingObservedUnits completed /= boundEpochs
                ]
              , [ "V2 manifest step does not match the authoritative SupervisedPlan epoch count"
                | manifestStep manifest /= boundEpochs
                ]
              , [ "V2 completed-training evidence update count does not match the authoritative SupervisedPlan optimizer-update count"
                | evidenceUpdateCount (completedTrainingEvidence completed)
                    /= boundOptimizerUpdates
                ]
              , case manifestUpdateCount manifest of
                  Nothing -> []
                  Just updateCount ->
                    [ "V2 manifest update count does not match the authoritative SupervisedPlan optimizer-update count"
                    | updateCount /= boundOptimizerUpdates
                    ]
              ]

  tensorErrors =
    case manifestTensors manifest of
      [tensor] ->
        [ "V2 supervised physical tensor must be named supervised.weights"
        | tensorName tensor /= "supervised.weights"
        ]
          <> [ "V2 supervised physical tensor shape mismatch: expected "
                 <> Text.pack (show [parameterCount])
                 <> ", got "
                 <> Text.pack (show (tensorShape tensor))
             | tensorShape tensor /= [parameterCount]
             ]
          <> [ "V2 supervised physical tensor key mismatch: expected "
                 <> expectedTensorKey
                 <> ", got "
                 <> tensorBlobKey tensor
             | tensorBlobKey tensor /= expectedTensorKey
             ]
      tensors ->
        [ "V2 supervised manifest must name exactly one physical tensor; got "
            <> Text.pack (show (length tensors))
        ]

  flatLayoutErrors =
    case manifestWeightLayout manifest of
      NamedTensorWeightLayout _ ->
        ["V2 supervised manifest requires graph-ordered FlatWeightLayout"]
      FlatWeightLayout specs ->
        ["V2 supervised FlatWeightLayout must not be empty" | null specs]
          <> [ "V2 supervised FlatWeightLayout does not equal the graph-ordered virtual slices"
             | specs /= expectedLayout
             ]

maybeTextBindingErrors :: Text -> Text -> Maybe Text -> [Text]
maybeTextBindingErrors label expected observed =
  case observed of
    Nothing -> ["V2 supervised manifest is missing its " <> label]
    Just value ->
      [ "V2 runtime " <> label <> " does not match manifest " <> label
      | value /= expected
      ]

renderCheckpointCompletionValidationError
  :: CheckpointCompletionValidationError
  -> Text
renderCheckpointCompletionValidationError err =
  case err of
    MissingCompletedTraining ->
      "manifest has no completed-training witness"
    SupervisedRuntimeArtifactMissing ->
      "supervised V1 manifest has no exact V2 runtime artifact and is inspection-only"
    CompletedTrainingHasNoMetrics ->
      "completed-training witness has no convergence metrics"
    CompletedTrainingHasFailedMetrics metrics ->
      "completed-training witness has failed convergence metrics: "
        <> Text.intercalate "," metrics
    CompletedTrainingExternalBarMismatch errors ->
      "completed-training witness does not match external convergence bars: "
        <> Text.intercalate "; " errors
    CompletedTrainingOutrunsManifest observed manifestStepValue ->
      "completed-training witness observes "
        <> Text.pack (show observed)
        <> " units but completed manifest step is "
        <> Text.pack (show manifestStepValue)
    CompletedTrainingEvidenceMissing ->
      "completed-training manifest is missing weight-delta evidence"
    CompletedTrainingEvidenceInvalid detail ->
      "completed-training manifest has invalid weight-delta evidence: " <> detail
    CompletedTrainingEvidenceMismatch ->
      "completed-training manifest evidence does not match its witness"
    CompletedTrainingPlanIdMissing ->
      "completed-training manifest is missing its plan-id"
    CompletedTrainingPlanIdMismatch completedId manifestIdValue ->
      "completed-training plan-id "
        <> completedId
        <> " does not match manifest plan-id "
        <> manifestIdValue
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

checkpointWireVersion :: Word64
checkpointWireVersion = 1

-- | The byte-preserving supervised-runtime envelope.  V1 remains the default
-- for every manifest which does not carry a refined runtime payload.
checkpointWireVersionV2 :: Word64
checkpointWireVersionV2 = 2

checkpointManifestToRaw :: CheckpointManifest -> RawCheckpointManifest
checkpointManifestToRaw manifest =
  RawCheckpointManifest
    { rawManifestId = manifestId manifest
    , rawManifestExperiment = manifestExperiment manifest
    , rawManifestModelFamily = manifestModelFamily manifest
    , rawManifestArchitecture = manifestArchitecture manifest
    , rawManifestPreprocessing = manifestPreprocessing manifest
    , rawManifestOutputDecoders = manifestOutputDecoders manifest
    , rawManifestWeightLayout = manifestWeightLayout manifest
    , rawManifestReplayPointers = manifestReplayPointers manifest
    , rawManifestTranscriptPointers = manifestTranscriptPointers manifest
    , rawManifestSubstrateArtifacts = manifestSubstrateArtifacts manifest
    , rawManifestTensors = manifestTensors manifest
    , rawManifestOptimizer = manifestOptimizer manifest
    , rawManifestRng = manifestRng manifest
    , rawManifestStep = manifestStep manifest
    , rawManifestMetrics = manifestMetrics manifest
    , rawManifestPlanId = planIdText <$> manifestPlanId manifest
    , rawManifestCompletedTraining =
        completedTrainingToRaw <$> manifestCompletedTraining manifest
    , rawManifestInitialWeightHash = manifestInitialWeightHash manifest
    , rawManifestFinalWeightHash = manifestFinalWeightHash manifest
    , rawManifestUpdateCount = manifestUpdateCount manifest
    , rawManifestDatasetShaAtRead = manifestDatasetShaAtRead manifest
    , rawManifestParentManifestSha = manifestParentManifestSha manifest
    }

refineCheckpointManifest :: RawCheckpointManifest -> Either Text CheckpointManifest
refineCheckpointManifest raw = do
  validateFiniteManifest raw
  planId <- traverse refinePlanIdText (rawManifestPlanId raw)
  completed <- traverse refineCompletedTraining (rawManifestCompletedTraining raw)
  pure
    CheckpointManifest
      { manifestId = rawManifestId raw
      , manifestExperiment = rawManifestExperiment raw
      , manifestModelFamily = rawManifestModelFamily raw
      , manifestArchitecture = rawManifestArchitecture raw
      , manifestPreprocessing = rawManifestPreprocessing raw
      , manifestOutputDecoders = rawManifestOutputDecoders raw
      , manifestWeightLayout = rawManifestWeightLayout raw
      , manifestReplayPointers = rawManifestReplayPointers raw
      , manifestTranscriptPointers = rawManifestTranscriptPointers raw
      , manifestSubstrateArtifacts = rawManifestSubstrateArtifacts raw
      , manifestTensors = rawManifestTensors raw
      , manifestOptimizer = rawManifestOptimizer raw
      , manifestRng = rawManifestRng raw
      , manifestStep = rawManifestStep raw
      , manifestMetrics = rawManifestMetrics raw
      , manifestPlanId = planId
      , manifestCompletedTraining = completed
      , manifestInitialWeightHash = rawManifestInitialWeightHash raw
      , manifestFinalWeightHash = rawManifestFinalWeightHash raw
      , manifestUpdateCount = rawManifestUpdateCount raw
      , manifestDatasetShaAtRead = rawManifestDatasetShaAtRead raw
      , manifestParentManifestSha = rawManifestParentManifestSha raw
      , manifestSupervisedRuntime = Nothing
      }

encodeManifestCbor :: CheckpointManifest -> LazyByteString.ByteString
encodeManifestCbor manifest =
  case manifestSupervisedRuntime manifest of
    Nothing ->
      -- Do not change this branch without updating the frozen V1 golden.  In
      -- particular, V1 continues to sort Flat layouts by tensor name.
      serialise
        RawCheckpointEnvelope
          { rawCheckpointVersion = checkpointWireVersion
          , rawCheckpointPayload = checkpointManifestToRaw (canonicalManifest manifest)
          }
    Just runtimePayload ->
      let canonical = canonicalManifestV2 manifest
          body =
            RawCheckpointBodyV2
              { rawCheckpointV2Manifest = checkpointManifestToRaw canonical
              , rawCheckpointV2SupervisedRuntime =
                  RuntimeArtifact.supervisedRuntimePayloadToRaw runtimePayload
              }
          bodyBytes = LazyByteString.toStrict (serialise body)
       in serialise
            RawCheckpointEnvelopeV2
              { rawCheckpointV2Version = checkpointWireVersionV2
              , rawCheckpointV2BodySha256 = SHA256.hash bodyBytes
              , rawCheckpointV2BodyBytes = bodyBytes
              }

decodeManifestCbor :: LazyByteString.ByteString -> Either Text CheckpointManifest
decodeManifestCbor payload =
  addressedManifest <$> decodeAddressedManifestCbor payload

-- | Structurally dispatch and retain the exact fetched representation.  A
-- successful structural decode selects a wire form permanently: semantic or
-- canonical validation failures never fall through to an older decoder.
decodeAddressedManifestCbor
  :: LazyByteString.ByteString -> Either Text AddressedCheckpointManifest
decodeAddressedManifestCbor payload =
  case decodeRawCheckpointEnvelopeV2 payload of
    Right envelope -> decodeAddressedV2 payload envelope
    Left v2StructuralFailure ->
      case decodeRawCheckpointEnvelope payload of
        Right envelope -> decodeAddressedV1 payload envelope
        Left v1StructuralFailure ->
          case decodeLegacyCheckpointManifest payload of
            Right legacy -> decodeAddressedLegacy payload legacy
            Left legacyStructuralFailure ->
              Left
                ( "invalid checkpoint DTO: V2 decode: "
                    <> v2StructuralFailure
                    <> "; V1 decode: "
                    <> v1StructuralFailure
                    <> "; legacy decode: "
                    <> legacyStructuralFailure
                )

decodeAddressedV2
  :: LazyByteString.ByteString
  -> RawCheckpointEnvelopeV2
  -> Either Text AddressedCheckpointManifest
decodeAddressedV2 outerBytes envelope = do
  if rawCheckpointV2Version envelope == checkpointWireVersionV2
    then Right ()
    else
      Left
        ( "unsupported V2 checkpoint version: "
            <> Text.pack (show (rawCheckpointV2Version envelope))
        )
  if serialise envelope == outerBytes
    then Right ()
    else Left "V2 checkpoint outer envelope is not in canonical CBOR form"
  let bodyBytes = rawCheckpointV2BodyBytes envelope
      expectedBodyDigest = rawCheckpointV2BodySha256 envelope
      actualBodyDigest = SHA256.hash bodyBytes
  if StrictByteString.length expectedBodyDigest == 32
    then Right ()
    else Left "V2 checkpoint body SHA-256 must contain exactly 32 raw bytes"
  if expectedBodyDigest == actualBodyDigest
    then Right ()
    else
      Left
        ( "V2 checkpoint body SHA-256 mismatch: expected "
            <> hexBytes expectedBodyDigest
            <> ", got "
            <> hexBytes actualBodyDigest
        )
  body <- decodeRawCheckpointBodyV2 bodyBytes
  if LazyByteString.toStrict (serialise body) == bodyBytes
    then Right ()
    else Left "V2 checkpoint embedded body is not in canonical CBOR form"
  baseManifest <- refineCheckpointManifest (rawCheckpointV2Manifest body)
  runtimePayload <-
    mapLeftText
      "invalid V2 supervised runtime payload: "
      ( RuntimeArtifact.refineSupervisedRuntimePayload
          (rawCheckpointV2SupervisedRuntime body)
      )
  let manifest = baseManifest {manifestSupervisedRuntime = Just runtimePayload}
      canonical = canonicalManifestV2 manifest
      canonicalRawManifest = checkpointManifestToRaw canonical
      canonicalRawRuntime =
        RuntimeArtifact.supervisedRuntimePayloadToRaw runtimePayload
  if rawCheckpointV2Manifest body == canonicalRawManifest
    then Right ()
    else Left "V2 checkpoint base manifest is not in canonical value order"
  if rawCheckpointV2SupervisedRuntime body == canonicalRawRuntime
    then Right ()
    else Left "V2 checkpoint supervised runtime DTO is not canonical"
  case validateSupervisedV2Bindings manifest runtimePayload of
    [] -> Right ()
    errors ->
      Left
        ( "invalid V2 supervised checkpoint binding: "
            <> Text.intercalate "; " errors
        )
  Right
    AddressedCheckpointManifest
      { addressedManifest = manifest
      , addressedManifestWireVersion = checkpointWireVersionV2
      , addressedManifestBytes = outerBytes
      , addressedManifestSha = hexBytes (SHA256.hashlazy outerBytes)
      , addressedManifestBodyBytes = Just bodyBytes
      , addressedManifestBodySha = Just (hexBytes actualBodyDigest)
      }

decodeAddressedV1
  :: LazyByteString.ByteString
  -> RawCheckpointEnvelope
  -> Either Text AddressedCheckpointManifest
decodeAddressedV1 outerBytes envelope = do
  if rawCheckpointVersion envelope == checkpointWireVersion
    then Right ()
    else
      Left
        ( "unsupported checkpoint version: "
            <> Text.pack (show (rawCheckpointVersion envelope))
        )
  manifest <- refineCheckpointManifest (rawCheckpointPayload envelope)
  Right
    AddressedCheckpointManifest
      { addressedManifest = manifest
      , addressedManifestWireVersion = checkpointWireVersion
      , addressedManifestBytes = outerBytes
      , addressedManifestSha = hexBytes (SHA256.hashlazy outerBytes)
      , addressedManifestBodyBytes = Nothing
      , addressedManifestBodySha = Nothing
      }

decodeAddressedLegacy
  :: LazyByteString.ByteString
  -> LegacyCheckpointManifest
  -> Either Text AddressedCheckpointManifest
decodeAddressedLegacy outerBytes legacy = do
  manifest <- refineLegacyCheckpointManifest legacy
  Right
    AddressedCheckpointManifest
      { addressedManifest = manifest
      , addressedManifestWireVersion = 0
      , addressedManifestBytes = outerBytes
      , addressedManifestSha = hexBytes (SHA256.hashlazy outerBytes)
      , addressedManifestBodyBytes = Nothing
      , addressedManifestBodySha = Nothing
      }

decodeRawCheckpointEnvelopeV2
  :: LazyByteString.ByteString -> Either Text RawCheckpointEnvelopeV2
decodeRawCheckpointEnvelopeV2 payload =
  case deserialiseOrFail payload of
    Left failure -> Left (Text.pack (show failure))
    Right envelope -> Right envelope

decodeRawCheckpointBodyV2
  :: StrictByteString.ByteString -> Either Text RawCheckpointBodyV2
decodeRawCheckpointBodyV2 payload =
  case deserialiseOrFail (LazyByteString.fromStrict payload) of
    Left failure -> Left ("invalid V2 checkpoint body: " <> Text.pack (show failure))
    Right body -> Right body

decodeRawCheckpointEnvelope
  :: LazyByteString.ByteString -> Either Text RawCheckpointEnvelope
decodeRawCheckpointEnvelope payload =
  case deserialiseOrFail payload of
    Left failure -> Left (Text.pack (show failure))
    Right envelope -> Right envelope

decodeLegacyCheckpointManifest
  :: LazyByteString.ByteString -> Either Text LegacyCheckpointManifest
decodeLegacyCheckpointManifest payload =
  case deserialiseOrFail payload of
    Left failure -> Left (Text.pack (show failure))
    Right manifest -> Right manifest

refineLegacyCheckpointManifest
  :: LegacyCheckpointManifest -> Either Text CheckpointManifest
refineLegacyCheckpointManifest legacy = do
  candidate <- refineCheckpointManifest (legacyManifestToRawCandidate legacy)
  traverse_ refineLegacyCompletedTraining (legacyManifestCompletedTraining legacy)
  pure candidate

legacyManifestToRawCandidate :: LegacyCheckpointManifest -> RawCheckpointManifest
legacyManifestToRawCandidate legacy =
  RawCheckpointManifest
    { rawManifestId = legacyManifestId legacy
    , rawManifestExperiment = legacyManifestExperiment legacy
    , rawManifestModelFamily = legacyManifestModelFamily legacy
    , rawManifestArchitecture = legacyManifestArchitecture legacy
    , rawManifestPreprocessing = legacyManifestPreprocessing legacy
    , rawManifestOutputDecoders = legacyManifestOutputDecoders legacy
    , rawManifestWeightLayout = legacyManifestWeightLayout legacy
    , rawManifestReplayPointers = legacyManifestReplayPointers legacy
    , rawManifestTranscriptPointers = legacyManifestTranscriptPointers legacy
    , rawManifestSubstrateArtifacts = legacyManifestSubstrateArtifacts legacy
    , rawManifestTensors = legacyManifestTensors legacy
    , rawManifestOptimizer = legacyManifestOptimizer legacy
    , rawManifestRng = legacyManifestRng legacy
    , rawManifestStep = legacyManifestStep legacy
    , rawManifestMetrics = legacyManifestMetrics legacy
    , rawManifestPlanId = Nothing
    , rawManifestCompletedTraining = Nothing
    , rawManifestInitialWeightHash = legacyManifestInitialWeightHash legacy
    , rawManifestFinalWeightHash = legacyManifestFinalWeightHash legacy
    , rawManifestUpdateCount = legacyManifestUpdateCount legacy
    , rawManifestDatasetShaAtRead = legacyManifestDatasetShaAtRead legacy
    , rawManifestParentManifestSha = legacyManifestParentManifestSha legacy
    }

refineLegacyCompletedTraining
  :: LegacyCompletedTraining -> Either Text CompletedTraining
refineLegacyCompletedTraining legacy = do
  budget <- refineLegacyBudget (legacyCompletedBudget legacy)
  planId <- legacyCompletionPlanId legacy
  observations <- traverse refineLegacyObservation (legacyCompletedMetrics legacy)
  completedTraining
    planId
    budget
    (legacyCompletedObservedUnits legacy)
    (legacyCompletedEvidence legacy)
    observations
    (legacyCompletedTensorBoard legacy)

legacyCompletionPlanId :: LegacyCompletedTraining -> Either Text PlanId
legacyCompletionPlanId legacy =
  case planIdFromCanonicalText canonical of
    Success planId -> Right planId
    Failure errors -> Left ("invalid legacy completion plan identity: " <> Text.pack (show errors))
 where
  budget = legacyCompletedBudget legacy
  evidence = legacyCompletedEvidence legacy
  canonical =
    Text.intercalate
      "\NUL"
      [ "legacy-checkpoint-completion-v1"
      , Text.pack (show (legacyBudgetKind budget))
      , Text.pack (show (legacyBudgetTargetUnits budget))
      , legacyBudgetUnitLabel budget
      , maybe "seedless" (Text.pack . show) (legacyBudgetSeed budget)
      , evidenceInitialWeightHash evidence
      , evidenceFinalWeightHash evidence
      , Text.pack (show (evidenceUpdateCount evidence))
      , evidenceDatasetShaAtRead evidence
      ]

refineLegacyBudget :: LegacyTrainingBudget -> Either Text TrainingBudget
refineLegacyBudget legacy = do
  if legacyBudgetUnitLabel legacy `elem` legacyUnitAliases (legacyBudgetKind legacy)
    then pure ()
    else
      Left
        ( "legacy training budget unit mismatch for "
            <> renderLegacyBudgetKind (legacyBudgetKind legacy)
            <> ": "
            <> legacyBudgetUnitLabel legacy
        )
  mkTrainingBudget
    (legacyBudgetKind legacy)
    (legacyBudgetTargetUnits legacy)
    (legacyBudgetSeed legacy)

legacyUnitAliases :: BudgetKind -> [Text]
legacyUnitAliases kind =
  case kind of
    SupervisedEpochBudget -> ["epochs", "epoch", "fixed-epochs", "steps", "units"]
    RlEnvironmentStepBudget -> ["environment-steps", "env-steps", "goal-conditioned-env-steps", "units"]
    AlphaZeroSelfPlayBudget -> ["self-play-generations", "self-play-samples", "units"]
    TuningTrialBudget -> ["trials", "units"]

renderLegacyBudgetKind :: BudgetKind -> Text
renderLegacyBudgetKind = Text.pack . show

refineLegacyObservation
  :: LegacyConvergenceObservation -> Either Text ConvergenceObservation
refineLegacyObservation legacy = do
  threshold <-
    maybe
      (Left ("legacy convergence metric is missing a criterion: " <> legacyMetricName legacy))
      Right
      (legacyMetricThreshold legacy)
  observation <-
    if legacyMetricName legacy == "arena_win_rate"
      then
        measureCriterionExcluding
          (legacyMetricName legacy)
          (legacyMetricGoal legacy)
          threshold
          0.5
          1.0e-12
          (legacyMetricValue legacy)
      else
        measureCriterion
          (legacyMetricName legacy)
          (legacyMetricGoal legacy)
          threshold
          (legacyMetricValue legacy)
  if convergencePassed observation == legacyMetricPassed legacy
    then Right observation
    else
      Left
        ( "legacy stored convergence verdict contradicts criterion for "
            <> legacyMetricName legacy
        )

validateFiniteManifest :: RawCheckpointManifest -> Either Text ()
validateFiniteManifest raw = do
  traverse_ finiteMetric (rawManifestMetrics raw)
  traverse_ finiteLayerKind (layerKinds (rawManifestArchitecture raw))
 where
  finiteMetric (name, value)
    | isNaN value || isInfinite value =
        Left ("checkpoint metric " <> name <> " must be finite")
    | otherwise = Right ()

  finiteLayerKind kind =
    case kind of
      LayerGraphDropoutLayer value -> finiteMetadata "dropout" value
      LayerGraphResidualLayer value -> finiteMetadata "residual" value
      LayerGraphBasicBlockLayer value -> finiteMetadata "basic-block" value
      LayerGraphBottleneckBlockLayer value -> finiteMetadata "bottleneck-block" value
      _ -> Right ()

  finiteMetadata label value
    | isNaN value || isInfinite value =
        Left ("checkpoint " <> label <> " metadata must be finite")
    | otherwise = Right ()

  layerKinds architecture =
    maybe [] (fmap layerGraphNodeKind . layerGraphMetadataNodes) (architectureLayerGraph architecture)

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

-- | V2 shares every deterministic V1 ordering rule except the Flat virtual
-- layout.  Those specs are an execution-meaningful graph traversal, not a map,
-- so sorting them would sever slice-to-parameter identity.
canonicalManifestV2 :: CheckpointManifest -> CheckpointManifest
canonicalManifestV2 manifest =
  let canonical = canonicalManifest manifest
   in canonical
        { manifestWeightLayout =
            case manifestWeightLayout manifest of
              FlatWeightLayout specs -> FlatWeightLayout specs
              NamedTensorWeightLayout _ -> manifestWeightLayout canonical
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

mapLeftText :: Text -> Either Text a -> Either Text a
mapLeftText prefix result =
  case result of
    Left err -> Left (prefix <> err)
    Right value -> Right value

hexWord8 :: Word8 -> String
hexWord8 byte =
  [ intToDigit (fromIntegral byte `div` 16)
  , intToDigit (fromIntegral byte `mod` 16)
  ]

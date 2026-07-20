{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Exact, persistence-safe supervised inference runtimes.
--
-- Raw values are deliberately forgeable serialisation DTOs.  The refined
-- constructors are hidden: callers can obtain them only by checking the full
-- family/task/transform/graph contract and, for a loaded value, the exact JMW1
-- bytes.  The module is independent of checkpoint manifests, the ProductRow
-- registry, and the training architecture implementation so those layers can
-- project into one stable V2 runtime boundary without a dependency cycle.
module JitML.SL.RuntimeArtifact
  ( -- * Forgeable wire DTOs
    RawRuntimeFamily (..)
  , RawRuntimeTask (..)
  , RawRuntimeMlpShape (..)
  , RawRuntimeImageGeometry (..)
  , RawRuntimeInputTransform (..)
  , RawRuntimeOutputTransform (..)
  , RawRuntimeLayer (..)
  , RawSupervisedRuntime (..)
  , RawSupervisedRuntimeOrigin (..)
  , RawSupervisedRuntimePayload (..)
  , RawTrainingRuntimeArtifact (..)

    -- * Hidden refined runtime values
  , RuntimeFamily
  , RuntimeTask
  , RuntimeMlpShape
  , RuntimeImageGeometry
  , RuntimeInputTransform
  , RuntimeOutputTransform
  , RuntimeRepresentation
  , RuntimeLayerKind (..)
  , RuntimeLayer
  , SupervisedRuntime
  , SupervisedRuntimeOrigin
  , SupervisedRuntimePayload
  , RuntimeVirtualSlice
  , TrainingRuntimeArtifact
  , LoadedRuntime
  , RuntimeMlpExecutor
  , RuntimeInputTransformExecutor
  , RuntimeOutputTransformExecutor
  , RuntimeResidualAddExecutor
  , RuntimeLayerNormExecutor
  , RuntimeTokenMixExecutor
  , RuntimePatchExtractExecutor
  , RuntimeAttentionExecutor
  , RuntimeMeanPoolExecutor
  , RuntimeBackendExecutor (..)

    -- * Refinement and construction
  , refineRuntimeFamily
  , refineRuntimeTask
  , refineRuntimeMlpShape
  , refineRuntimeImageGeometry
  , refineRuntimeInputTransform
  , refineRuntimeOutputTransform
  , refineSupervisedRuntime
  , refineSupervisedRuntimePayload
  , refineTrainingRuntimeArtifact
  , mkTrainingRuntimeArtifact
  , loadSupervisedRuntime
  , loadTrainingRuntimeArtifact

    -- * Raw projections
  , runtimeFamilyToRaw
  , runtimeTaskToRaw
  , runtimeMlpShapeToRaw
  , runtimeImageGeometryToRaw
  , runtimeInputTransformToRaw
  , runtimeOutputTransformToRaw
  , runtimeLayerToRaw
  , supervisedRuntimeToRaw
  , supervisedRuntimeOriginToRaw
  , supervisedRuntimePayloadToRaw
  , trainingRuntimeArtifactToRaw

    -- * Refined accessors
  , runtimeTaskSemanticWidth
  , runtimeTaskIsClassification
  , runtimeMlpInputs
  , runtimeMlpHidden
  , runtimeMlpOutputs
  , runtimeMlpParameterCount
  , runtimeImageWidth
  , runtimeImageHeight
  , runtimeImageChannels
  , runtimeImageElementCount
  , runtimeInputWidth
  , runtimeRepresentationShape
  , runtimeLayerName
  , runtimeLayerKind
  , runtimeLayerInputRepresentation
  , runtimeLayerOutputRepresentation
  , runtimeLayerMlpShape
  , supervisedRuntimeFamily
  , supervisedRuntimeTask
  , supervisedRuntimeInputTransform
  , supervisedRuntimeOutputTransform
  , supervisedRuntimeLayers
  , supervisedRuntimeInputWidth
  , supervisedRuntimeRawOutputWidth
  , supervisedRuntimeParameterCount
  , supervisedRuntimeVirtualSlices
  , runtimeVirtualSliceLayerName
  , runtimeVirtualSliceParameterName
  , runtimeVirtualSliceQualifiedName
  , runtimeVirtualSliceOffset
  , runtimeVirtualSliceLength
  , runtimeVirtualSliceShape
  , payloadRowId
  , payloadOrigin
  , payloadPlanId
  , payloadPlanIdText
  , payloadDatasetSha256
  , payloadInitialJmw1Sha256
  , payloadFinalJmw1Sha256
  , payloadRuntime
  , trainingArtifactPayload
  , trainingArtifactInitialJmw1Bytes
  , trainingArtifactFinalJmw1Bytes
  , loadedRuntimePayload
  , loadedRuntimeFinalJmw1Bytes
  , loadedRuntimeWeights
  , loadedRuntimeLayerParameters

    -- * Strict inference
  , executeLoadedRuntime
  )
where

import Codec.Serialise (Serialise)
import Control.Monad (foldM, join)
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isDigit)
import Data.Foldable (traverse_)
import Data.List qualified as List
import Data.Maybe (isJust, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import GHC.Generics (Generic)

import JitML.Checkpoint.WeightCodec
  ( decodeJmw1
  , encodeJmw1
  , jmw1ContentSha
  )
import JitML.Numerics.Mlp
  ( MlpParams
  , MlpShape (..)
  , mlpParamsFromFlat
  )
import JitML.Plan.Plan
  ( PlanId
  , planIdText
  , refinePlanIdText
  )

-- Raw DTOs -------------------------------------------------------------------

data RawRuntimeFamily
  = RawDenseRuntimeFamily
  | RawDeepDenseRuntimeFamily
  | RawConv2DLeNetRuntimeFamily
  | RawResidualRuntimeFamily Int
  | RawWideResidualRuntimeFamily Int
  | RawVisionTransformerRuntimeFamily
  | RawTabularRegressionRuntimeFamily
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawRuntimeTask
  = RawClassificationRuntimeTask Int
  | RawRegressionRuntimeTask Int
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawRuntimeMlpShape = RawRuntimeMlpShape
  { rawRuntimeMlpInputs :: Int
  , rawRuntimeMlpHidden :: Int
  , rawRuntimeMlpOutputs :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawRuntimeImageGeometry = RawRuntimeImageGeometry
  { rawRuntimeImageWidth :: Int
  , rawRuntimeImageHeight :: Int
  , rawRuntimeImageChannels :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | @RawUnitImageInput@ consumes the already-normalised finite image tensor
-- used by training.  Every element must be in @[0,1]@ and is retained exactly;
-- the runtime never guesses that an out-of-range tensor was a byte image.
-- @RawStandardizeInput@ is the task-neutral fitted feature transform used by
-- either classification or regression when its means and positive scales were
-- measured from the training partition.
data RawRuntimeInputTransform
  = RawIdentityInput Int
  | RawUnitImageInput RawRuntimeImageGeometry
  | RawStandardizeInput [Double] [Double]
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawRuntimeOutputTransform
  = RawIdentityOutput
  | RawSemanticPrefixOutput Int
  | RawDestandardizeOutput [Double] [Double]
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Parameterised layers name only their MLP shape or the attributes from
-- which that shape is derived.  No weight offset is persisted.  Refinement
-- derives every @W1,b1,W2,b2@ virtual slice cumulatively in graph order.
--
-- V2 freezes the pre-Sprint-23.1 operation algebra: 'RawTokenMixLayer'
-- replaces its input with the transposed channel-MLP result, and
-- 'RawAttentionLayer' returns attended values without an outer skip.  Only
-- 'RawResidualLayer' denotes an explicit residual addition.  Sprint 23.1 must
-- introduce a distinguishable operation/version if it later adds those skips;
-- existing V2 bytes cannot be reinterpreted.
data RawRuntimeLayer
  = RawDenseLayer Text RawRuntimeMlpShape
  | RawResidualLayer Text Double RawRuntimeMlpShape
  | RawLayerNormLayer Text
  | RawTokenMixLayer Text Int Int
  | RawPatchLayer Text RawRuntimeImageGeometry Int Int Int Int
  | RawAttentionLayer Text Int Int
  | RawMeanPoolLayer Text
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawSupervisedRuntime = RawSupervisedRuntime
  { rawSupervisedRuntimeFamily :: RawRuntimeFamily
  , rawSupervisedRuntimeTask :: RawRuntimeTask
  , rawSupervisedRuntimeInputTransform :: RawRuntimeInputTransform
  , rawSupervisedRuntimeOutputTransform :: RawRuntimeOutputTransform
  , rawSupervisedRuntimeLayers :: [RawRuntimeLayer]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Closed provenance for the plan bound into a supervised V2 runtime.
--
-- Product publication carries the exact registry projection implicitly: the
-- row plus PlanId must re-project to exactly one supported substrate.  A
-- public/daemon @jitml train@ command is intentionally broader than the
-- ProductRow matrix, so it persists a composite execution origin: the exact
-- canonical problem row plus the complete canonical 'SupervisedPlan'
-- transport that produced its PlanId.  The addressed V2 body binds that pair;
-- checkpoint refinement re-parses it and keeps generic completion distinct
-- from ProductRow evidence.
data RawSupervisedRuntimeOrigin
  = RawProductRowProjectionOrigin
  | RawGenericSupervisedExecutionOrigin
      { rawGenericOriginRowId :: Text
      , rawGenericOriginPlanTransport :: Text
      }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawSupervisedRuntimePayload = RawSupervisedRuntimePayload
  { rawRuntimePayloadRowId :: Text
  , rawRuntimePayloadOrigin :: RawSupervisedRuntimeOrigin
  , rawRuntimePayloadPlanId :: Text
  , rawRuntimePayloadDatasetSha256 :: Text
  , rawRuntimePayloadInitialJmw1Sha256 :: Text
  , rawRuntimePayloadFinalJmw1Sha256 :: Text
  , rawRuntimePayloadRuntime :: RawSupervisedRuntime
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Exact bytes returned by training.  Strict bytes avoid any lazy chunking
-- identity leaking into the wire DTO; accessors expose lazy bytes at the object
-- store boundary.
data RawTrainingRuntimeArtifact = RawTrainingRuntimeArtifact
  { rawTrainingArtifactPayload :: RawSupervisedRuntimePayload
  , rawTrainingArtifactInitialJmw1Bytes :: StrictByteString.ByteString
  , rawTrainingArtifactFinalJmw1Bytes :: StrictByteString.ByteString
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- Refined values --------------------------------------------------------------

data RuntimeFamily
  = DenseRuntimeFamily
  | DeepDenseRuntimeFamily
  | Conv2DLeNetRuntimeFamily
  | ResidualRuntimeFamily Int
  | WideResidualRuntimeFamily Int
  | VisionTransformerRuntimeFamily
  | TabularRegressionRuntimeFamily
  deriving stock (Eq, Show)

data RuntimeTask
  = ClassificationRuntimeTask Int
  | RegressionRuntimeTask Int
  deriving stock (Eq, Show)

data RuntimeMlpShape = RuntimeMlpShape !Int !Int !Int
  deriving stock (Eq, Show)

data RuntimeImageGeometry = RuntimeImageGeometry !Int !Int !Int
  deriving stock (Eq, Show)

data RuntimeInputTransform
  = IdentityInput !Int
  | UnitImageInput !RuntimeImageGeometry
  | StandardizeInput !(Vector Double) !(Vector Double)
  deriving stock (Eq, Show)

data RuntimeOutputTransform
  = IdentityOutput
  | SemanticPrefixOutput !Int
  | DestandardizeOutput !(Vector Double) !(Vector Double)
  deriving stock (Eq, Show)

data RuntimeRepresentation
  = FlatRuntimeRepresentation !Int
  | TokenRuntimeRepresentation !Int !Int
  deriving stock (Eq, Show)

data RuntimeLayerKind
  = DenseRuntimeLayerKind
  | ResidualRuntimeLayerKind
  | LayerNormRuntimeLayerKind
  | TokenMixRuntimeLayerKind
  | PatchRuntimeLayerKind
  | AttentionRuntimeLayerKind
  | MeanPoolRuntimeLayerKind
  deriving stock (Eq, Ord, Show)

data RuntimeLayerOperation
  = DenseOperation !RuntimeMlpShape
  | ResidualOperation !Double !RuntimeMlpShape
  | LayerNormOperation
  | TokenMixOperation !Int !Int !RuntimeMlpShape
  | PatchOperation
      !RuntimeImageGeometry
      !Int
      !Int
      !RuntimeMlpShape
      ![[Int]]
  | AttentionOperation !Int !Int !RuntimeMlpShape
  | MeanPoolOperation
  deriving stock (Eq, Show)

data RuntimeLayer = RuntimeLayer
  { refinedLayerName :: !Text
  , refinedLayerOperation :: !RuntimeLayerOperation
  , refinedLayerInput :: !RuntimeRepresentation
  , refinedLayerOutput :: !RuntimeRepresentation
  }
  deriving stock (Eq, Show)

data SupervisedRuntime = SupervisedRuntime
  { refinedRuntimeFamily :: !RuntimeFamily
  , refinedRuntimeTask :: !RuntimeTask
  , refinedRuntimeInputTransform :: !RuntimeInputTransform
  , refinedRuntimeOutputTransform :: !RuntimeOutputTransform
  , refinedRuntimeLayers :: ![RuntimeLayer]
  , refinedRuntimeInputWidth :: !Int
  , refinedRuntimeRawOutputWidth :: !Int
  , refinedRuntimeParameterCount :: !Int
  }
  deriving stock (Eq, Show)

data SupervisedRuntimeOrigin
  = ProductRowProjectionOrigin
  | GenericSupervisedExecutionOrigin !Text !Text
  deriving stock (Eq, Show)

newtype RuntimeSha256 = RuntimeSha256 Text
  deriving stock (Eq, Ord, Show)

data SupervisedRuntimePayload = SupervisedRuntimePayload
  { refinedPayloadRowId :: !Text
  , refinedPayloadOrigin :: !SupervisedRuntimeOrigin
  , refinedPayloadPlanId :: !PlanId
  , refinedPayloadDatasetSha256 :: !RuntimeSha256
  , refinedPayloadInitialJmw1Sha256 :: !RuntimeSha256
  , refinedPayloadFinalJmw1Sha256 :: !RuntimeSha256
  , refinedPayloadRuntime :: !SupervisedRuntime
  }
  deriving stock (Eq, Show)

data RuntimeVirtualSlice = RuntimeVirtualSlice
  { refinedSliceLayerName :: !Text
  , refinedSliceParameterName :: !Text
  , refinedSliceOffset :: !Int
  , refinedSliceLength :: !Int
  , refinedSliceShape :: ![Int]
  }
  deriving stock (Eq, Show)

data TrainingRuntimeArtifact = TrainingRuntimeArtifact
  { refinedTrainingPayload :: !SupervisedRuntimePayload
  , refinedTrainingInitialBytes :: !StrictByteString.ByteString
  , refinedTrainingFinalBytes :: !StrictByteString.ByteString
  }
  deriving stock (Eq, Show)

data LoadedRuntime = LoadedRuntime
  { refinedLoadedPayload :: !SupervisedRuntimePayload
  , refinedLoadedFinalBytes :: !StrictByteString.ByteString
  , refinedLoadedWeights :: ![Double]
  , refinedLoadedLayerParameters :: ![Maybe MlpParams]
  }
  deriving stock (Eq, Show)

type RuntimeMlpExecutor =
  MlpParams -> Vector Double -> IO (Either Text (Vector Double))

type RuntimeInputTransformExecutor =
  RuntimeInputTransform -> Vector Double -> IO (Either Text (Vector Double))

type RuntimeOutputTransformExecutor =
  RuntimeTask
  -> RuntimeOutputTransform
  -> Vector Double
  -> IO (Either Text (Vector Double))

type RuntimeResidualAddExecutor =
  Double
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double))

type RuntimeLayerNormExecutor =
  Vector Double -> IO (Either Text (Vector Double))

type RuntimeTokenMixExecutor =
  RuntimeBackendExecutor
  -> RuntimeLayer
  -> Int
  -> Int
  -> RuntimeMlpShape
  -> MlpParams
  -> [Vector Double]
  -> IO (Either Text [Vector Double])

type RuntimePatchExtractExecutor =
  RuntimeImageGeometry
  -> [[Int]]
  -> Vector Double
  -> IO (Either Text [Vector Double])

type RuntimeAttentionExecutor =
  RuntimeBackendExecutor
  -> RuntimeLayer
  -> Int
  -> RuntimeMlpShape
  -> MlpParams
  -> [Vector Double]
  -> IO (Either Text [Vector Double])

type RuntimeMeanPoolExecutor =
  [Vector Double] -> IO (Either Text (Vector Double))

-- | Complete selected-substrate execution contract for a persisted V2 graph.
-- Every operation has a mandatory callback.  A backend which cannot support
-- an operation returns a typed 'Left'; the dispatcher never substitutes an
-- implementation or another backend after the runtime has been recognized.
data RuntimeBackendExecutor = RuntimeBackendExecutor
  { runtimeBackendLabel :: !Text
  , runtimeBackendInputTransformExecutor :: RuntimeInputTransformExecutor
  , runtimeBackendOutputTransformExecutor :: RuntimeOutputTransformExecutor
  , runtimeBackendMlpExecutor :: RuntimeMlpExecutor
  , runtimeBackendResidualAddExecutor :: RuntimeResidualAddExecutor
  , runtimeBackendLayerNormExecutor :: RuntimeLayerNormExecutor
  , runtimeBackendTokenMixExecutor :: RuntimeTokenMixExecutor
  , runtimeBackendPatchExtractExecutor :: RuntimePatchExtractExecutor
  , runtimeBackendAttentionExecutor :: RuntimeAttentionExecutor
  , runtimeBackendMeanPoolExecutor :: RuntimeMeanPoolExecutor
  }

-- Leaf refinement -------------------------------------------------------------

refineRuntimeFamily :: RawRuntimeFamily -> Either Text RuntimeFamily
refineRuntimeFamily raw =
  case raw of
    RawDenseRuntimeFamily -> Right DenseRuntimeFamily
    RawDeepDenseRuntimeFamily -> Right DeepDenseRuntimeFamily
    RawConv2DLeNetRuntimeFamily -> Right Conv2DLeNetRuntimeFamily
    RawResidualRuntimeFamily depth ->
      ResidualRuntimeFamily <$> requirePositive "residual depth" depth
    RawWideResidualRuntimeFamily depth ->
      WideResidualRuntimeFamily <$> requirePositive "wide-residual depth" depth
    RawVisionTransformerRuntimeFamily -> Right VisionTransformerRuntimeFamily
    RawTabularRegressionRuntimeFamily -> Right TabularRegressionRuntimeFamily

refineRuntimeTask :: RawRuntimeTask -> Either Text RuntimeTask
refineRuntimeTask raw =
  case raw of
    RawClassificationRuntimeTask width ->
      ClassificationRuntimeTask
        <$> requirePositive "classification semantic width" width
    RawRegressionRuntimeTask width ->
      RegressionRuntimeTask
        <$> requirePositive "regression semantic width" width

refineRuntimeMlpShape :: RawRuntimeMlpShape -> Either Text RuntimeMlpShape
refineRuntimeMlpShape raw = do
  inputs <- requirePositive "MLP input width" (rawRuntimeMlpInputs raw)
  hidden <- requirePositive "MLP hidden width" (rawRuntimeMlpHidden raw)
  outputs <- requirePositive "MLP output width" (rawRuntimeMlpOutputs raw)
  _ <-
    checkedIntSum
      "MLP parameter count"
      [ toInteger inputs * toInteger hidden
      , toInteger hidden
      , toInteger outputs * toInteger hidden
      , toInteger outputs
      ]
  Right (RuntimeMlpShape inputs hidden outputs)

refineRuntimeImageGeometry
  :: RawRuntimeImageGeometry -> Either Text RuntimeImageGeometry
refineRuntimeImageGeometry raw = do
  width <- requirePositive "image width" (rawRuntimeImageWidth raw)
  height <- requirePositive "image height" (rawRuntimeImageHeight raw)
  channels <- requirePositive "image channel count" (rawRuntimeImageChannels raw)
  _ <- checkedIntProduct "image element count" [width, height, channels]
  Right (RuntimeImageGeometry width height channels)

refineRuntimeInputTransform
  :: RawRuntimeInputTransform -> Either Text RuntimeInputTransform
refineRuntimeInputTransform raw =
  case raw of
    RawIdentityInput width ->
      IdentityInput <$> requirePositive "identity input width" width
    RawUnitImageInput geometry ->
      UnitImageInput <$> refineRuntimeImageGeometry geometry
    RawStandardizeInput means scales -> do
      if null means
        then Left "standardize input width must be positive"
        else Right ()
      if length means /= length scales
        then Left "standardize input mean/scale widths must match"
        else Right ()
      traverse_ (requireFinite "standardize input mean") means
      traverse_ (requireFinitePositive "standardize input scale") scales
      Right (StandardizeInput (VU.fromList means) (VU.fromList scales))

refineRuntimeOutputTransform
  :: RawRuntimeOutputTransform -> Either Text RuntimeOutputTransform
refineRuntimeOutputTransform raw =
  case raw of
    RawIdentityOutput -> Right IdentityOutput
    RawSemanticPrefixOutput width ->
      SemanticPrefixOutput
        <$> requirePositive "semantic output prefix width" width
    RawDestandardizeOutput means scales -> do
      if null means
        then Left "destandardize output width must be positive"
        else Right ()
      if length means /= length scales
        then Left "destandardize output mean/scale widths must match"
        else Right ()
      traverse_ (requireFinite "destandardize output mean") means
      traverse_ (requireFinitePositive "destandardize output scale") scales
      Right (DestandardizeOutput (VU.fromList means) (VU.fromList scales))

-- Runtime refinement ----------------------------------------------------------

refineSupervisedRuntime
  :: RawSupervisedRuntime -> Either Text SupervisedRuntime
refineSupervisedRuntime raw = do
  family <- refineRuntimeFamily (rawSupervisedRuntimeFamily raw)
  task <- refineRuntimeTask (rawSupervisedRuntimeTask raw)
  inputTransform <-
    refineRuntimeInputTransform (rawSupervisedRuntimeInputTransform raw)
  outputTransform <-
    refineRuntimeOutputTransform (rawSupervisedRuntimeOutputTransform raw)
  let inputWidth = runtimeInputWidth inputTransform
      rawLayers = rawSupervisedRuntimeLayers raw
  if null rawLayers
    then Left "supervised runtime graph must contain at least one layer"
    else Right ()
  (_, finalRepresentation, reverseLayers) <-
    foldM
      refineNextLayer
      (Set.empty, FlatRuntimeRepresentation inputWidth, [])
      rawLayers
  layers <- Right (reverse reverseLayers)
  rawOutputWidth <-
    case finalRepresentation of
      FlatRuntimeRepresentation width -> Right width
      TokenRuntimeRepresentation _ _ ->
        Left "supervised runtime graph must end in a flat representation"
  validateTaskAndTransforms task inputTransform outputTransform rawOutputWidth
  validateFamilyGraph family task inputTransform layers
  parameterCount <-
    checkedIntSum
      "supervised runtime parameter count"
      ( fmap
          (maybe 0 (toInteger . runtimeMlpParameterCount) . runtimeLayerMlpShape)
          layers
      )
  Right
    SupervisedRuntime
      { refinedRuntimeFamily = family
      , refinedRuntimeTask = task
      , refinedRuntimeInputTransform = inputTransform
      , refinedRuntimeOutputTransform = outputTransform
      , refinedRuntimeLayers = layers
      , refinedRuntimeInputWidth = inputWidth
      , refinedRuntimeRawOutputWidth = rawOutputWidth
      , refinedRuntimeParameterCount = parameterCount
      }

refineNextLayer
  :: (Set Text, RuntimeRepresentation, [RuntimeLayer])
  -> RawRuntimeLayer
  -> Either Text (Set Text, RuntimeRepresentation, [RuntimeLayer])
refineNextLayer (seenNames, inputRepresentation, layers) raw = do
  name <- refineLayerName (rawLayerName raw)
  if Set.member name seenNames
    then Left ("duplicate runtime layer name: " <> name)
    else Right ()
  layer <- refineLayer name inputRepresentation raw
  Right
    ( Set.insert name seenNames
    , refinedLayerOutput layer
    , layer : layers
    )

refineLayer
  :: Text
  -> RuntimeRepresentation
  -> RawRuntimeLayer
  -> Either Text RuntimeLayer
refineLayer name inputRepresentation raw =
  case raw of
    RawDenseLayer _ rawShape -> do
      inputWidth <- requireFlatInput name inputRepresentation
      shape <- refineRuntimeMlpShape rawShape
      if runtimeMlpInputs shape /= inputWidth
        then layerShapeMismatch name "dense input" inputWidth (runtimeMlpInputs shape)
        else Right ()
      let output = FlatRuntimeRepresentation (runtimeMlpOutputs shape)
      Right (RuntimeLayer name (DenseOperation shape) inputRepresentation output)
    RawResidualLayer _ scale rawShape -> do
      requireFinitePositive (name <> " residual scale") scale
      shape <- refineRuntimeMlpShape rawShape
      let width = representationFeatureWidth inputRepresentation
      if runtimeMlpInputs shape /= width
        then layerShapeMismatch name "residual input" width (runtimeMlpInputs shape)
        else Right ()
      if runtimeMlpOutputs shape /= width
        then layerShapeMismatch name "residual output" width (runtimeMlpOutputs shape)
        else Right ()
      Right
        ( RuntimeLayer
            name
            (ResidualOperation scale shape)
            inputRepresentation
            inputRepresentation
        )
    RawLayerNormLayer _ -> do
      _ <- requireTokenInput name inputRepresentation
      Right
        ( RuntimeLayer
            name
            LayerNormOperation
            inputRepresentation
            inputRepresentation
        )
    RawTokenMixLayer _ rawTokens rawHidden -> do
      (tokens, width) <- requireTokenInput name inputRepresentation
      expectedTokens <- requirePositive (name <> " token-mix token count") rawTokens
      hidden <- requirePositive (name <> " token-mix hidden width") rawHidden
      if tokens /= expectedTokens
        then layerShapeMismatch name "token-mix token count" tokens expectedTokens
        else Right ()
      shape <-
        refineRuntimeMlpShape
          RawRuntimeMlpShape
            { rawRuntimeMlpInputs = tokens
            , rawRuntimeMlpHidden = hidden
            , rawRuntimeMlpOutputs = tokens
            }
      Right
        ( RuntimeLayer
            name
            (TokenMixOperation tokens width shape)
            inputRepresentation
            inputRepresentation
        )
    RawPatchLayer _ rawGeometry rawSize rawStride rawHidden rawOutputs -> do
      inputWidth <- requireFlatInput name inputRepresentation
      geometry <- refineRuntimeImageGeometry rawGeometry
      if runtimeImageElementCount geometry /= inputWidth
        then
          layerShapeMismatch
            name
            "patch image element count"
            inputWidth
            (runtimeImageElementCount geometry)
        else Right ()
      size <- requirePositive (name <> " patch size") rawSize
      stride <- requirePositive (name <> " patch stride") rawStride
      hidden <- requirePositive (name <> " patch hidden width") rawHidden
      outputs <- requirePositive (name <> " patch output width") rawOutputs
      if size > runtimeImageWidth geometry || size > runtimeImageHeight geometry
        then Left (name <> ": patch size exceeds image geometry")
        else Right ()
      let positions = patchPositions geometry size stride
      if null positions
        then Left (name <> ": image geometry produced no patches")
        else Right ()
      patchInputs <-
        checkedIntSum
          (name <> " patch input width")
          [ toInteger size * toInteger size * toInteger (runtimeImageChannels geometry)
          , 2
          ]
      shape <-
        refineRuntimeMlpShape
          RawRuntimeMlpShape
            { rawRuntimeMlpInputs = patchInputs
            , rawRuntimeMlpHidden = hidden
            , rawRuntimeMlpOutputs = outputs
            }
      let output = TokenRuntimeRepresentation (length positions) outputs
      Right
        ( RuntimeLayer
            name
            (PatchOperation geometry size stride shape positions)
            inputRepresentation
            output
        )
    RawAttentionLayer _ rawWidth rawHidden -> do
      (tokens, inputWidth) <- requireTokenInput name inputRepresentation
      width <- requirePositive (name <> " attention width") rawWidth
      hidden <- requirePositive (name <> " attention hidden width") rawHidden
      if width /= inputWidth
        then layerShapeMismatch name "attention width" inputWidth width
        else Right ()
      qkvWidth <-
        checkedIntProduct (name <> " attention QKV width") [3, width]
      shape <-
        refineRuntimeMlpShape
          RawRuntimeMlpShape
            { rawRuntimeMlpInputs = width
            , rawRuntimeMlpHidden = hidden
            , rawRuntimeMlpOutputs = qkvWidth
            }
      let representation = TokenRuntimeRepresentation tokens width
      Right
        ( RuntimeLayer
            name
            (AttentionOperation width hidden shape)
            representation
            representation
        )
    RawMeanPoolLayer _ -> do
      (_, width) <- requireTokenInput name inputRepresentation
      Right
        ( RuntimeLayer
            name
            MeanPoolOperation
            inputRepresentation
            (FlatRuntimeRepresentation width)
        )

validateTaskAndTransforms
  :: RuntimeTask
  -> RuntimeInputTransform
  -> RuntimeOutputTransform
  -> Int
  -> Either Text ()
validateTaskAndTransforms task inputTransform outputTransform rawOutputWidth = do
  case (task, inputTransform) of
    (RegressionRuntimeTask _, UnitImageInput _) ->
      Left "regression runtime cannot use a unit-image transform"
    _ -> Right ()
  let semanticWidth = runtimeTaskSemanticWidth task
  case (task, outputTransform) of
    (ClassificationRuntimeTask _, DestandardizeOutput _ _) ->
      Left "classification runtime cannot destandardize regression targets"
    (RegressionRuntimeTask _, SemanticPrefixOutput _) ->
      Left "regression runtime cannot use a classification semantic prefix"
    (_, IdentityOutput)
      | rawOutputWidth == semanticWidth -> Right ()
      | otherwise ->
          outputWidthMismatch "identity" semanticWidth rawOutputWidth
    (ClassificationRuntimeTask _, SemanticPrefixOutput width)
      | width /= semanticWidth ->
          outputWidthMismatch "semantic-prefix task" semanticWidth width
      | rawOutputWidth < width ->
          Left "semantic output prefix exceeds the graph output width"
      | otherwise -> Right ()
    (RegressionRuntimeTask _, DestandardizeOutput means scales)
      | VU.length means /= semanticWidth ->
          outputWidthMismatch "destandardize mean" semanticWidth (VU.length means)
      | VU.length scales /= semanticWidth ->
          outputWidthMismatch "destandardize scale" semanticWidth (VU.length scales)
      | rawOutputWidth /= semanticWidth ->
          outputWidthMismatch "destandardize graph" semanticWidth rawOutputWidth
      | otherwise -> Right ()

validateFamilyGraph
  :: RuntimeFamily
  -> RuntimeTask
  -> RuntimeInputTransform
  -> [RuntimeLayer]
  -> Either Text ()
validateFamilyGraph family task inputTransform layers = do
  case (family, task) of
    (DenseRuntimeFamily, ClassificationRuntimeTask _) ->
      requireLayerKinds "dense" [DenseRuntimeLayerKind] kinds
    (DenseRuntimeFamily, RegressionRuntimeTask _) ->
      Left "regression task requires the tabular-regression runtime family"
    (DeepDenseRuntimeFamily, ClassificationRuntimeTask _)
      | length kinds >= 2 && all (== DenseRuntimeLayerKind) kinds -> Right ()
      | otherwise -> Left "deep-dense runtime requires at least two dense layers"
    (DeepDenseRuntimeFamily, RegressionRuntimeTask _) ->
      Left "regression task requires the tabular-regression runtime family"
    (Conv2DLeNetRuntimeFamily, ClassificationRuntimeTask _) ->
      requireLayerKinds
        "conv2d-lenet"
        [PatchRuntimeLayerKind, MeanPoolRuntimeLayerKind, DenseRuntimeLayerKind]
        kinds
    (Conv2DLeNetRuntimeFamily, RegressionRuntimeTask _) ->
      Left "regression task requires the tabular-regression runtime family"
    (ResidualRuntimeFamily _, ClassificationRuntimeTask _) ->
      requireResidualGraph "residual" kinds
    (WideResidualRuntimeFamily _, ClassificationRuntimeTask _) ->
      requireResidualGraph "wide-residual" kinds
    (ResidualRuntimeFamily _, RegressionRuntimeTask _) ->
      Left "regression task requires the tabular-regression runtime family"
    (WideResidualRuntimeFamily _, RegressionRuntimeTask _) ->
      Left "regression task requires the tabular-regression runtime family"
    (VisionTransformerRuntimeFamily, ClassificationRuntimeTask _) ->
      if hasKind PatchRuntimeLayerKind
        && hasKind TokenMixRuntimeLayerKind
        && hasKind AttentionRuntimeLayerKind
        && hasKind MeanPoolRuntimeLayerKind
        && lastKind == Just DenseRuntimeLayerKind
        then Right ()
        else
          Left
            "vision-transformer runtime requires patch, token-mix, attention, mean-pool, and final dense layers"
    (VisionTransformerRuntimeFamily, RegressionRuntimeTask _) ->
      Left "regression task requires the tabular-regression runtime family"
    (TabularRegressionRuntimeFamily, RegressionRuntimeTask _) ->
      requireLayerKinds "tabular-regression" [DenseRuntimeLayerKind] kinds
    (TabularRegressionRuntimeFamily, ClassificationRuntimeTask _) ->
      Left "classification task cannot use the tabular-regression runtime family"
  case inputTransform of
    UnitImageInput geometry ->
      traverse_ (validatePatchGeometry geometry) layers
    _ -> Right ()
 where
  kinds = fmap runtimeLayerKind layers
  hasKind kind = kind `elem` kinds
  lastKind = case reverse kinds of kind : _ -> Just kind; [] -> Nothing
  requireResidualGraph label graphKinds =
    case graphKinds of
      firstKind : _
        | firstKind == PatchRuntimeLayerKind
            && ResidualRuntimeLayerKind `elem` graphKinds
            && MeanPoolRuntimeLayerKind `elem` graphKinds
            && lastKind == Just DenseRuntimeLayerKind ->
            Right ()
      _ ->
        Left
          ( label
              <> " runtime requires an initial patch, residual block, mean-pool, and final dense layer"
          )

validatePatchGeometry
  :: RuntimeImageGeometry -> RuntimeLayer -> Either Text ()
validatePatchGeometry expected layer =
  case refinedLayerOperation layer of
    PatchOperation actual _ _ _ _
      | actual == expected -> Right ()
      | otherwise ->
          Left
            ( runtimeLayerName layer
                <> ": patch geometry differs from the unit-image input geometry"
            )
    _ -> Right ()

requireLayerKinds :: Text -> [RuntimeLayerKind] -> [RuntimeLayerKind] -> Either Text ()
requireLayerKinds label expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( label
            <> " runtime layer sequence mismatch: expected "
            <> showText expected
            <> ", got "
            <> showText actual
        )

-- Payload and exact bytes -----------------------------------------------------

refineSupervisedRuntimePayload
  :: RawSupervisedRuntimePayload -> Either Text SupervisedRuntimePayload
refineSupervisedRuntimePayload raw = do
  rowId <- requireCanonicalText "runtime row id" (rawRuntimePayloadRowId raw)
  origin <- refineSupervisedRuntimeOrigin (rawRuntimePayloadOrigin raw)
  plan <- refinePlanIdText (rawRuntimePayloadPlanId raw)
  datasetSha <-
    refineRuntimeSha "runtime dataset SHA-256" (rawRuntimePayloadDatasetSha256 raw)
  initialSha <-
    refineRuntimeSha
      "runtime initial JMW1 SHA-256"
      (rawRuntimePayloadInitialJmw1Sha256 raw)
  finalSha <-
    refineRuntimeSha
      "runtime final JMW1 SHA-256"
      (rawRuntimePayloadFinalJmw1Sha256 raw)
  if initialSha == finalSha
    then Left "runtime initial and final JMW1 SHA-256 values must be distinct"
    else Right ()
  runtime <- refineSupervisedRuntime (rawRuntimePayloadRuntime raw)
  Right
    SupervisedRuntimePayload
      { refinedPayloadRowId = rowId
      , refinedPayloadOrigin = origin
      , refinedPayloadPlanId = plan
      , refinedPayloadDatasetSha256 = datasetSha
      , refinedPayloadInitialJmw1Sha256 = initialSha
      , refinedPayloadFinalJmw1Sha256 = finalSha
      , refinedPayloadRuntime = runtime
      }

refineSupervisedRuntimeOrigin
  :: RawSupervisedRuntimeOrigin -> Either Text SupervisedRuntimeOrigin
refineSupervisedRuntimeOrigin raw =
  case raw of
    RawProductRowProjectionOrigin -> Right ProductRowProjectionOrigin
    RawGenericSupervisedExecutionOrigin rowId transport ->
      GenericSupervisedExecutionOrigin
        <$> requireCanonicalText "generic supervised runtime origin row id" rowId
        <*> requireCanonicalText "generic supervised runtime plan transport" transport

refineTrainingRuntimeArtifact
  :: RawTrainingRuntimeArtifact -> Either Text TrainingRuntimeArtifact
refineTrainingRuntimeArtifact raw = do
  payload <- refineSupervisedRuntimePayload (rawTrainingArtifactPayload raw)
  mkTrainingRuntimeArtifact
    payload
    (LazyByteString.fromStrict (rawTrainingArtifactInitialJmw1Bytes raw))
    (LazyByteString.fromStrict (rawTrainingArtifactFinalJmw1Bytes raw))

mkTrainingRuntimeArtifact
  :: SupervisedRuntimePayload
  -> LazyByteString.ByteString
  -> LazyByteString.ByteString
  -> Either Text TrainingRuntimeArtifact
mkTrainingRuntimeArtifact payload initialBytes finalBytes = do
  _ <-
    validateExactJmw1
      "initial"
      (runtimeShaText (refinedPayloadInitialJmw1Sha256 payload))
      (supervisedRuntimeParameterCount (payloadRuntime payload))
      initialBytes
  _ <-
    validateExactJmw1
      "final"
      (runtimeShaText (refinedPayloadFinalJmw1Sha256 payload))
      (supervisedRuntimeParameterCount (payloadRuntime payload))
      finalBytes
  Right
    TrainingRuntimeArtifact
      { refinedTrainingPayload = payload
      , refinedTrainingInitialBytes = LazyByteString.toStrict initialBytes
      , refinedTrainingFinalBytes = LazyByteString.toStrict finalBytes
      }

loadSupervisedRuntime
  :: SupervisedRuntimePayload
  -> LazyByteString.ByteString
  -> Either Text LoadedRuntime
loadSupervisedRuntime payload finalBytes = do
  values <-
    validateExactJmw1
      "final"
      (runtimeShaText (refinedPayloadFinalJmw1Sha256 payload))
      (supervisedRuntimeParameterCount (payloadRuntime payload))
      finalBytes
  parameters <-
    buildLayerParameters (supervisedRuntimeLayers (payloadRuntime payload)) values
  Right
    LoadedRuntime
      { refinedLoadedPayload = payload
      , refinedLoadedFinalBytes = LazyByteString.toStrict finalBytes
      , refinedLoadedWeights = values
      , refinedLoadedLayerParameters = parameters
      }

loadTrainingRuntimeArtifact
  :: TrainingRuntimeArtifact -> Either Text LoadedRuntime
loadTrainingRuntimeArtifact artifact =
  loadSupervisedRuntime
    (trainingArtifactPayload artifact)
    (trainingArtifactFinalJmw1Bytes artifact)

validateExactJmw1
  :: Text
  -> Text
  -> Int
  -> LazyByteString.ByteString
  -> Either Text [Double]
validateExactJmw1 label expectedSha expectedCount bytes = do
  let actualSha = jmw1ContentSha bytes
  if actualSha /= expectedSha
    then
      Left
        ( label
            <> " JMW1 SHA-256 mismatch: expected "
            <> expectedSha
            <> ", got "
            <> actualSha
        )
    else Right ()
  values <-
    mapLeft
      (\err -> label <> " JMW1 decode failed: " <> err)
      (decodeJmw1 bytes)
  if length values /= expectedCount
    then
      Left
        ( label
            <> " JMW1 value count mismatch: expected "
            <> showText expectedCount
            <> ", got "
            <> showText (length values)
        )
    else Right ()
  if encodeJmw1 values /= bytes
    then Left (label <> " JMW1 bytes are not the canonical frozen encoding")
    else Right values

buildLayerParameters
  :: [RuntimeLayer] -> [Double] -> Either Text [Maybe MlpParams]
buildLayerParameters layers values = do
  (remaining, reverseParameters) <-
    foldM consume (values, []) layers
  if null remaining
    then Right (reverse reverseParameters)
    else Left "runtime weight vector has unconsumed trailing parameters"
 where
  consume (remaining, parameters) layer =
    case runtimeLayerMlpShape layer of
      Nothing -> Right (remaining, Nothing : parameters)
      Just shape -> do
        let count = runtimeMlpParameterCount shape
            (layerValues, rest) = splitAt count remaining
        if length layerValues /= count
          then
            Left
              ( runtimeLayerName layer
                  <> ": truncated exact MLP parameter slice"
              )
          else do
            params <-
              mapLeft
                (\err -> runtimeLayerName layer <> ": " <> Text.pack err)
                (mlpParamsFromFlat (toMlpShape shape) layerValues)
            Right (rest, Just params : parameters)

-- Virtual layout --------------------------------------------------------------

supervisedRuntimeVirtualSlices :: SupervisedRuntime -> [RuntimeVirtualSlice]
supervisedRuntimeVirtualSlices runtime =
  join (snd (List.mapAccumL deriveLayerSlices 0 (supervisedRuntimeLayers runtime)))

deriveLayerSlices :: Int -> RuntimeLayer -> (Int, [RuntimeVirtualSlice])
deriveLayerSlices offset layer =
  case runtimeLayerMlpShape layer of
    Nothing -> (offset, [])
    Just shape ->
      let specs =
            [ ("W1", [runtimeMlpHidden shape, runtimeMlpInputs shape])
            , ("b1", [runtimeMlpHidden shape])
            , ("W2", [runtimeMlpOutputs shape, runtimeMlpHidden shape])
            , ("b2", [runtimeMlpOutputs shape])
            ]
          (nextOffset, slices) = List.mapAccumL (deriveOne layer) offset specs
       in (nextOffset, slices)

deriveOne
  :: RuntimeLayer
  -> Int
  -> (Text, [Int])
  -> (Int, RuntimeVirtualSlice)
deriveOne layer offset (parameterName, shape) =
  let count = product shape
   in ( offset + count
      , RuntimeVirtualSlice
          { refinedSliceLayerName = runtimeLayerName layer
          , refinedSliceParameterName = parameterName
          , refinedSliceOffset = offset
          , refinedSliceLength = count
          , refinedSliceShape = shape
          }
      )

-- Raw projections -------------------------------------------------------------

runtimeFamilyToRaw :: RuntimeFamily -> RawRuntimeFamily
runtimeFamilyToRaw family =
  case family of
    DenseRuntimeFamily -> RawDenseRuntimeFamily
    DeepDenseRuntimeFamily -> RawDeepDenseRuntimeFamily
    Conv2DLeNetRuntimeFamily -> RawConv2DLeNetRuntimeFamily
    ResidualRuntimeFamily depth -> RawResidualRuntimeFamily depth
    WideResidualRuntimeFamily depth -> RawWideResidualRuntimeFamily depth
    VisionTransformerRuntimeFamily -> RawVisionTransformerRuntimeFamily
    TabularRegressionRuntimeFamily -> RawTabularRegressionRuntimeFamily

runtimeTaskToRaw :: RuntimeTask -> RawRuntimeTask
runtimeTaskToRaw task =
  case task of
    ClassificationRuntimeTask width -> RawClassificationRuntimeTask width
    RegressionRuntimeTask width -> RawRegressionRuntimeTask width

runtimeMlpShapeToRaw :: RuntimeMlpShape -> RawRuntimeMlpShape
runtimeMlpShapeToRaw shape =
  RawRuntimeMlpShape
    { rawRuntimeMlpInputs = runtimeMlpInputs shape
    , rawRuntimeMlpHidden = runtimeMlpHidden shape
    , rawRuntimeMlpOutputs = runtimeMlpOutputs shape
    }

runtimeImageGeometryToRaw
  :: RuntimeImageGeometry -> RawRuntimeImageGeometry
runtimeImageGeometryToRaw geometry =
  RawRuntimeImageGeometry
    { rawRuntimeImageWidth = runtimeImageWidth geometry
    , rawRuntimeImageHeight = runtimeImageHeight geometry
    , rawRuntimeImageChannels = runtimeImageChannels geometry
    }

runtimeInputTransformToRaw
  :: RuntimeInputTransform -> RawRuntimeInputTransform
runtimeInputTransformToRaw transform =
  case transform of
    IdentityInput width -> RawIdentityInput width
    UnitImageInput geometry -> RawUnitImageInput (runtimeImageGeometryToRaw geometry)
    StandardizeInput means scales ->
      RawStandardizeInput (VU.toList means) (VU.toList scales)

runtimeOutputTransformToRaw
  :: RuntimeOutputTransform -> RawRuntimeOutputTransform
runtimeOutputTransformToRaw transform =
  case transform of
    IdentityOutput -> RawIdentityOutput
    SemanticPrefixOutput width -> RawSemanticPrefixOutput width
    DestandardizeOutput means scales ->
      RawDestandardizeOutput (VU.toList means) (VU.toList scales)

runtimeLayerToRaw :: RuntimeLayer -> RawRuntimeLayer
runtimeLayerToRaw layer =
  case refinedLayerOperation layer of
    DenseOperation shape ->
      RawDenseLayer (runtimeLayerName layer) (runtimeMlpShapeToRaw shape)
    ResidualOperation scale shape ->
      RawResidualLayer (runtimeLayerName layer) scale (runtimeMlpShapeToRaw shape)
    LayerNormOperation -> RawLayerNormLayer (runtimeLayerName layer)
    TokenMixOperation tokens _ shape ->
      RawTokenMixLayer
        (runtimeLayerName layer)
        tokens
        (runtimeMlpHidden shape)
    PatchOperation geometry size stride shape _ ->
      RawPatchLayer
        (runtimeLayerName layer)
        (runtimeImageGeometryToRaw geometry)
        size
        stride
        (runtimeMlpHidden shape)
        (runtimeMlpOutputs shape)
    AttentionOperation width hidden _ ->
      RawAttentionLayer (runtimeLayerName layer) width hidden
    MeanPoolOperation -> RawMeanPoolLayer (runtimeLayerName layer)

supervisedRuntimeToRaw :: SupervisedRuntime -> RawSupervisedRuntime
supervisedRuntimeToRaw runtime =
  RawSupervisedRuntime
    { rawSupervisedRuntimeFamily = runtimeFamilyToRaw (supervisedRuntimeFamily runtime)
    , rawSupervisedRuntimeTask = runtimeTaskToRaw (supervisedRuntimeTask runtime)
    , rawSupervisedRuntimeInputTransform =
        runtimeInputTransformToRaw (supervisedRuntimeInputTransform runtime)
    , rawSupervisedRuntimeOutputTransform =
        runtimeOutputTransformToRaw (supervisedRuntimeOutputTransform runtime)
    , rawSupervisedRuntimeLayers = fmap runtimeLayerToRaw (supervisedRuntimeLayers runtime)
    }

supervisedRuntimeOriginToRaw
  :: SupervisedRuntimeOrigin -> RawSupervisedRuntimeOrigin
supervisedRuntimeOriginToRaw origin =
  case origin of
    ProductRowProjectionOrigin -> RawProductRowProjectionOrigin
    GenericSupervisedExecutionOrigin rowId transport ->
      RawGenericSupervisedExecutionOrigin rowId transport

supervisedRuntimePayloadToRaw
  :: SupervisedRuntimePayload -> RawSupervisedRuntimePayload
supervisedRuntimePayloadToRaw payload =
  RawSupervisedRuntimePayload
    { rawRuntimePayloadRowId = payloadRowId payload
    , rawRuntimePayloadOrigin =
        supervisedRuntimeOriginToRaw (payloadOrigin payload)
    , rawRuntimePayloadPlanId = payloadPlanIdText payload
    , rawRuntimePayloadDatasetSha256 = payloadDatasetSha256 payload
    , rawRuntimePayloadInitialJmw1Sha256 = payloadInitialJmw1Sha256 payload
    , rawRuntimePayloadFinalJmw1Sha256 = payloadFinalJmw1Sha256 payload
    , rawRuntimePayloadRuntime = supervisedRuntimeToRaw (payloadRuntime payload)
    }

trainingRuntimeArtifactToRaw
  :: TrainingRuntimeArtifact -> RawTrainingRuntimeArtifact
trainingRuntimeArtifactToRaw artifact =
  RawTrainingRuntimeArtifact
    { rawTrainingArtifactPayload =
        supervisedRuntimePayloadToRaw (trainingArtifactPayload artifact)
    , rawTrainingArtifactInitialJmw1Bytes = refinedTrainingInitialBytes artifact
    , rawTrainingArtifactFinalJmw1Bytes = refinedTrainingFinalBytes artifact
    }

-- Accessors -------------------------------------------------------------------

runtimeTaskSemanticWidth :: RuntimeTask -> Int
runtimeTaskSemanticWidth task =
  case task of
    ClassificationRuntimeTask width -> width
    RegressionRuntimeTask width -> width

runtimeTaskIsClassification :: RuntimeTask -> Bool
runtimeTaskIsClassification task =
  case task of
    ClassificationRuntimeTask _ -> True
    RegressionRuntimeTask _ -> False

runtimeMlpInputs :: RuntimeMlpShape -> Int
runtimeMlpInputs (RuntimeMlpShape inputs _ _) = inputs

runtimeMlpHidden :: RuntimeMlpShape -> Int
runtimeMlpHidden (RuntimeMlpShape _ hidden _) = hidden

runtimeMlpOutputs :: RuntimeMlpShape -> Int
runtimeMlpOutputs (RuntimeMlpShape _ _ outputs) = outputs

runtimeMlpParameterCount :: RuntimeMlpShape -> Int
runtimeMlpParameterCount shape =
  runtimeMlpHidden shape * runtimeMlpInputs shape
    + runtimeMlpHidden shape
    + runtimeMlpOutputs shape * runtimeMlpHidden shape
    + runtimeMlpOutputs shape

runtimeImageWidth :: RuntimeImageGeometry -> Int
runtimeImageWidth (RuntimeImageGeometry width _ _) = width

runtimeImageHeight :: RuntimeImageGeometry -> Int
runtimeImageHeight (RuntimeImageGeometry _ height _) = height

runtimeImageChannels :: RuntimeImageGeometry -> Int
runtimeImageChannels (RuntimeImageGeometry _ _ channels) = channels

runtimeImageElementCount :: RuntimeImageGeometry -> Int
runtimeImageElementCount geometry =
  runtimeImageWidth geometry
    * runtimeImageHeight geometry
    * runtimeImageChannels geometry

runtimeInputWidth :: RuntimeInputTransform -> Int
runtimeInputWidth transform =
  case transform of
    IdentityInput width -> width
    UnitImageInput geometry -> runtimeImageElementCount geometry
    StandardizeInput means _ -> VU.length means

runtimeRepresentationShape :: RuntimeRepresentation -> [Int]
runtimeRepresentationShape representation =
  case representation of
    FlatRuntimeRepresentation width -> [width]
    TokenRuntimeRepresentation tokens width -> [tokens, width]

runtimeLayerName :: RuntimeLayer -> Text
runtimeLayerName = refinedLayerName

runtimeLayerKind :: RuntimeLayer -> RuntimeLayerKind
runtimeLayerKind layer =
  case refinedLayerOperation layer of
    DenseOperation _ -> DenseRuntimeLayerKind
    ResidualOperation _ _ -> ResidualRuntimeLayerKind
    LayerNormOperation -> LayerNormRuntimeLayerKind
    TokenMixOperation {} -> TokenMixRuntimeLayerKind
    PatchOperation {} -> PatchRuntimeLayerKind
    AttentionOperation {} -> AttentionRuntimeLayerKind
    MeanPoolOperation -> MeanPoolRuntimeLayerKind

runtimeLayerInputRepresentation :: RuntimeLayer -> RuntimeRepresentation
runtimeLayerInputRepresentation = refinedLayerInput

runtimeLayerOutputRepresentation :: RuntimeLayer -> RuntimeRepresentation
runtimeLayerOutputRepresentation = refinedLayerOutput

runtimeLayerMlpShape :: RuntimeLayer -> Maybe RuntimeMlpShape
runtimeLayerMlpShape layer =
  case refinedLayerOperation layer of
    DenseOperation shape -> Just shape
    ResidualOperation _ shape -> Just shape
    LayerNormOperation -> Nothing
    TokenMixOperation _ _ shape -> Just shape
    PatchOperation _ _ _ shape _ -> Just shape
    AttentionOperation _ _ shape -> Just shape
    MeanPoolOperation -> Nothing

supervisedRuntimeFamily :: SupervisedRuntime -> RuntimeFamily
supervisedRuntimeFamily = refinedRuntimeFamily

supervisedRuntimeTask :: SupervisedRuntime -> RuntimeTask
supervisedRuntimeTask = refinedRuntimeTask

supervisedRuntimeInputTransform :: SupervisedRuntime -> RuntimeInputTransform
supervisedRuntimeInputTransform = refinedRuntimeInputTransform

supervisedRuntimeOutputTransform :: SupervisedRuntime -> RuntimeOutputTransform
supervisedRuntimeOutputTransform = refinedRuntimeOutputTransform

supervisedRuntimeLayers :: SupervisedRuntime -> [RuntimeLayer]
supervisedRuntimeLayers = refinedRuntimeLayers

supervisedRuntimeInputWidth :: SupervisedRuntime -> Int
supervisedRuntimeInputWidth = refinedRuntimeInputWidth

supervisedRuntimeRawOutputWidth :: SupervisedRuntime -> Int
supervisedRuntimeRawOutputWidth = refinedRuntimeRawOutputWidth

supervisedRuntimeParameterCount :: SupervisedRuntime -> Int
supervisedRuntimeParameterCount = refinedRuntimeParameterCount

runtimeVirtualSliceLayerName :: RuntimeVirtualSlice -> Text
runtimeVirtualSliceLayerName = refinedSliceLayerName

runtimeVirtualSliceParameterName :: RuntimeVirtualSlice -> Text
runtimeVirtualSliceParameterName = refinedSliceParameterName

runtimeVirtualSliceQualifiedName :: RuntimeVirtualSlice -> Text
runtimeVirtualSliceQualifiedName slice =
  runtimeVirtualSliceLayerName slice <> "." <> runtimeVirtualSliceParameterName slice

runtimeVirtualSliceOffset :: RuntimeVirtualSlice -> Int
runtimeVirtualSliceOffset = refinedSliceOffset

runtimeVirtualSliceLength :: RuntimeVirtualSlice -> Int
runtimeVirtualSliceLength = refinedSliceLength

runtimeVirtualSliceShape :: RuntimeVirtualSlice -> [Int]
runtimeVirtualSliceShape = refinedSliceShape

payloadRowId :: SupervisedRuntimePayload -> Text
payloadRowId = refinedPayloadRowId

payloadOrigin :: SupervisedRuntimePayload -> SupervisedRuntimeOrigin
payloadOrigin = refinedPayloadOrigin

payloadPlanId :: SupervisedRuntimePayload -> PlanId
payloadPlanId = refinedPayloadPlanId

payloadPlanIdText :: SupervisedRuntimePayload -> Text
payloadPlanIdText = planIdText . payloadPlanId

payloadDatasetSha256 :: SupervisedRuntimePayload -> Text
payloadDatasetSha256 = runtimeShaText . refinedPayloadDatasetSha256

payloadInitialJmw1Sha256 :: SupervisedRuntimePayload -> Text
payloadInitialJmw1Sha256 = runtimeShaText . refinedPayloadInitialJmw1Sha256

payloadFinalJmw1Sha256 :: SupervisedRuntimePayload -> Text
payloadFinalJmw1Sha256 = runtimeShaText . refinedPayloadFinalJmw1Sha256

payloadRuntime :: SupervisedRuntimePayload -> SupervisedRuntime
payloadRuntime = refinedPayloadRuntime

trainingArtifactPayload :: TrainingRuntimeArtifact -> SupervisedRuntimePayload
trainingArtifactPayload = refinedTrainingPayload

trainingArtifactInitialJmw1Bytes
  :: TrainingRuntimeArtifact -> LazyByteString.ByteString
trainingArtifactInitialJmw1Bytes =
  LazyByteString.fromStrict . refinedTrainingInitialBytes

trainingArtifactFinalJmw1Bytes
  :: TrainingRuntimeArtifact -> LazyByteString.ByteString
trainingArtifactFinalJmw1Bytes =
  LazyByteString.fromStrict . refinedTrainingFinalBytes

loadedRuntimePayload :: LoadedRuntime -> SupervisedRuntimePayload
loadedRuntimePayload = refinedLoadedPayload

loadedRuntimeFinalJmw1Bytes :: LoadedRuntime -> LazyByteString.ByteString
loadedRuntimeFinalJmw1Bytes = LazyByteString.fromStrict . refinedLoadedFinalBytes

loadedRuntimeWeights :: LoadedRuntime -> [Double]
loadedRuntimeWeights = refinedLoadedWeights

loadedRuntimeLayerParameters :: LoadedRuntime -> [(Text, MlpParams)]
loadedRuntimeLayerParameters loaded =
  [ (runtimeLayerName layer, params)
  | (layer, Just params) <-
      zip
        (supervisedRuntimeLayers (payloadRuntime (loadedRuntimePayload loaded)))
        (refinedLoadedLayerParameters loaded)
  ]

-- Strict inference ------------------------------------------------------------

data RuntimeValue
  = FlatRuntimeValue !(Vector Double)
  | TokenRuntimeValue ![Vector Double]

executeLoadedRuntime
  :: RuntimeBackendExecutor
  -> LoadedRuntime
  -> Vector Double
  -> IO (Either Text (Vector Double))
executeLoadedRuntime backend loaded rawInput =
  case requireCanonicalText "runtime backend label" (runtimeBackendLabel backend) of
    Left err -> pure (Left err)
    Right _ -> do
      transformed <-
        invokeRuntimeBackend backend "input-transform" $
          runtimeBackendInputTransformExecutor
            backend
            (supervisedRuntimeInputTransform runtime)
            rawInput
      case transformed of
        Left err -> pure (Left err)
        Right input -> executeGraph input
 where
  runtime = payloadRuntime (loadedRuntimePayload loaded)

  executeGraph input = do
    executed <-
      foldM
        executeOne
        (Right (FlatRuntimeValue input))
        ( zip3
            [0 :: Int ..]
            (supervisedRuntimeLayers runtime)
            (refinedLoadedLayerParameters loaded)
        )
    case executed of
      Left err -> pure (Left err)
      Right finalValue ->
        case finalValue of
          TokenRuntimeValue _ ->
            pure (Left "loaded supervised runtime ended in a token representation")
          FlatRuntimeValue output ->
            invokeRuntimeBackend backend "output-transform" $
              runtimeBackendOutputTransformExecutor
                backend
                (supervisedRuntimeTask runtime)
                (supervisedRuntimeOutputTransform runtime)
                output

  executeOne acc (_, layer, parameters) =
    case acc of
      Left err -> pure (Left err)
      Right value -> do
        case validateRuntimeValue (runtimeLayerInputRepresentation layer) value of
          Left err -> pure (Left (runtimeLayerName layer <> ": " <> err))
          Right () -> do
            result <- executeLayer backend layer parameters value
            pure $ do
              next <- result
              mapLeft
                (\err -> runtimeLayerName layer <> ": " <> err)
                (validateRuntimeValue (runtimeLayerOutputRepresentation layer) next)
              Right next

executeLayer
  :: RuntimeBackendExecutor
  -> RuntimeLayer
  -> Maybe MlpParams
  -> RuntimeValue
  -> IO (Either Text RuntimeValue)
executeLayer backend layer parameters value =
  case (refinedLayerOperation layer, parameters, value) of
    (DenseOperation shape, Just params, FlatRuntimeValue input) ->
      fmap FlatRuntimeValue <$> runMlpExact backend layer shape params input
    (ResidualOperation scale shape, Just params, FlatRuntimeValue input) -> do
      residual <- runMlpExact backend layer shape params input
      case residual of
        Left err -> pure (Left err)
        Right output ->
          fmap (fmap FlatRuntimeValue) (runResidualAdd backend scale input output)
    (ResidualOperation scale shape, Just params, TokenRuntimeValue tokens) -> do
      residuals <- traverse (runMlpExact backend layer shape params) tokens
      case sequence residuals of
        Left err -> pure (Left err)
        Right outputs -> do
          added <-
            traverse
              (uncurry (runResidualAdd backend scale))
              (zip tokens outputs)
          pure (TokenRuntimeValue <$> sequence added)
    (LayerNormOperation, Nothing, TokenRuntimeValue tokens) -> do
      normalised <-
        traverse
          ( invokeRuntimeBackend backend "layer-norm"
              . runtimeBackendLayerNormExecutor backend
          )
          tokens
      pure (TokenRuntimeValue <$> sequence normalised)
    (TokenMixOperation tokenCount width shape, Just params, TokenRuntimeValue tokens) ->
      fmap (fmap TokenRuntimeValue) $
        invokeRuntimeBackend backend "token-mix" $
          runtimeBackendTokenMixExecutor
            backend
            backend
            layer
            tokenCount
            width
            shape
            params
            tokens
    (PatchOperation geometry _ _ shape positions, Just params, FlatRuntimeValue input) -> do
      extracted <-
        invokeRuntimeBackend backend "patch-extract" $
          runtimeBackendPatchExtractExecutor backend geometry positions input
      case extracted of
        Left err -> pure (Left err)
        Right patches -> do
          outputs <- traverse (runMlpExact backend layer shape params) patches
          pure (TokenRuntimeValue <$> sequence outputs)
    (AttentionOperation width _ shape, Just params, TokenRuntimeValue tokens) ->
      fmap (fmap TokenRuntimeValue) $
        invokeRuntimeBackend backend "attention" $
          runtimeBackendAttentionExecutor
            backend
            backend
            layer
            width
            shape
            params
            tokens
    (MeanPoolOperation, Nothing, TokenRuntimeValue tokens) ->
      fmap (fmap FlatRuntimeValue) $
        invokeRuntimeBackend backend "mean-pool" $
          runtimeBackendMeanPoolExecutor backend tokens
    (_, Nothing, _)
      | isJust (runtimeLayerMlpShape layer) ->
          pure (Left "parameterised runtime layer has no exact parameter slice")
    (_, Just _, _)
      | isNothing (runtimeLayerMlpShape layer) ->
          pure (Left "parameter-free runtime layer unexpectedly has parameters")
    _ -> pure (Left "runtime layer representation transition mismatch")

runMlpExact
  :: RuntimeBackendExecutor
  -> RuntimeLayer
  -> RuntimeMlpShape
  -> MlpParams
  -> Vector Double
  -> IO (Either Text (Vector Double))
runMlpExact backend layer shape params input =
  case validateVectorWidth "MLP input" (runtimeMlpInputs shape) input of
    Left err -> pure (Left err)
    Right () -> do
      result <-
        invokeRuntimeBackend backend "mlp" $
          runtimeBackendMlpExecutor backend params input
      pure $ do
        output <- result
        mapLeft
          (\err -> runtimeLayerName layer <> " callback: " <> err)
          (validateVectorWidth "MLP output" (runtimeMlpOutputs shape) output)
        Right output

runResidualAdd
  :: RuntimeBackendExecutor
  -> Double
  -> Vector Double
  -> Vector Double
  -> IO (Either Text (Vector Double))
runResidualAdd backend scale input residual =
  invokeRuntimeBackend backend "residual-add" $
    runtimeBackendResidualAddExecutor backend scale input residual

invokeRuntimeBackend
  :: RuntimeBackendExecutor
  -> Text
  -> IO (Either Text value)
  -> IO (Either Text value)
invokeRuntimeBackend backend operation =
  fmap
    ( mapLeft
        ( \err ->
            "runtime backend "
              <> runtimeBackendLabel backend
              <> " "
              <> operation
              <> " failed: "
              <> err
        )
    )

validateRuntimeValue
  :: RuntimeRepresentation -> RuntimeValue -> Either Text ()
validateRuntimeValue representation value =
  case (representation, value) of
    (FlatRuntimeRepresentation width, FlatRuntimeValue vector) ->
      validateVectorWidth "flat representation" width vector
    (TokenRuntimeRepresentation tokenCount width, TokenRuntimeValue tokens) ->
      validateTokens tokenCount width tokens
    (FlatRuntimeRepresentation _, TokenRuntimeValue _) ->
      Left "expected a flat representation, got tokens"
    (TokenRuntimeRepresentation _ _, FlatRuntimeValue _) ->
      Left "expected a token representation, got flat values"

validateTokens :: Int -> Int -> [Vector Double] -> Either Text ()
validateTokens expectedCount expectedWidth tokens = do
  if length tokens /= expectedCount
    then
      Left
        ( "token count mismatch: expected "
            <> showText expectedCount
            <> ", got "
            <> showText (length tokens)
        )
    else Right ()
  traverse_ (validateVectorWidth "token width" expectedWidth) tokens

validateVectorWidth :: Text -> Int -> Vector Double -> Either Text ()
validateVectorWidth label expected vector = do
  if VU.length vector /= expected
    then
      Left
        ( label
            <> " mismatch: expected "
            <> showText expected
            <> ", got "
            <> showText (VU.length vector)
        )
    else Right ()
  traverse_ (requireFinite label) (VU.toList vector)

patchPositions :: RuntimeImageGeometry -> Int -> Int -> [[Int]]
patchPositions geometry size stride =
  [ [ pixelIndex geometry (x + dx) (y + dy) channel
    | dy <- [0 .. size - 1]
    , dx <- [0 .. size - 1]
    , channel <- [0 .. runtimeImageChannels geometry - 1]
    ]
  | y <- takeWhile (<= runtimeImageHeight geometry - size) [0, stride ..]
  , x <- takeWhile (<= runtimeImageWidth geometry - size) [0, stride ..]
  ]

pixelIndex :: RuntimeImageGeometry -> Int -> Int -> Int -> Int
pixelIndex geometry x y channel =
  ((y * runtimeImageWidth geometry) + x) * runtimeImageChannels geometry
    + channel

-- Validation helpers ----------------------------------------------------------

rawLayerName :: RawRuntimeLayer -> Text
rawLayerName raw =
  case raw of
    RawDenseLayer name _ -> name
    RawResidualLayer name _ _ -> name
    RawLayerNormLayer name -> name
    RawTokenMixLayer name _ _ -> name
    RawPatchLayer name _ _ _ _ _ -> name
    RawAttentionLayer name _ _ -> name
    RawMeanPoolLayer name -> name

refineLayerName :: Text -> Either Text Text
refineLayerName = requireCanonicalText "runtime layer name"

requireCanonicalText :: Text -> Text -> Either Text Text
requireCanonicalText label value
  | Text.null value = Left (label <> " must not be empty")
  | Text.strip value /= value =
      Left (label <> " must not contain leading or trailing whitespace")
  | otherwise = Right value

refineRuntimeSha :: Text -> Text -> Either Text RuntimeSha256
refineRuntimeSha label value
  | Text.length value == 64 && Text.all isLowerHex value =
      Right (RuntimeSha256 value)
  | otherwise =
      Left (label <> " must be exactly 64 lowercase hexadecimal characters")
 where
  isLowerHex char = isDigit char || (char >= 'a' && char <= 'f')

runtimeShaText :: RuntimeSha256 -> Text
runtimeShaText (RuntimeSha256 value) = value

requirePositive :: Text -> Int -> Either Text Int
requirePositive label value
  | value > 0 = Right value
  | otherwise = Left (label <> " must be positive")

requireFinite :: Text -> Double -> Either Text ()
requireFinite label value
  | isNaN value || isInfinite value = Left (label <> " must be finite")
  | otherwise = Right ()

requireFinitePositive :: Text -> Double -> Either Text ()
requireFinitePositive label value = do
  requireFinite label value
  if value > 0.0
    then Right ()
    else Left (label <> " must be positive")

checkedIntProduct :: Text -> [Int] -> Either Text Int
checkedIntProduct label values =
  checkedIntValue label (product (fmap toInteger values))

checkedIntSum :: Text -> [Integer] -> Either Text Int
checkedIntSum label = checkedIntValue label . sum

checkedIntValue :: Text -> Integer -> Either Text Int
checkedIntValue label value
  | value <= 0 = Left (label <> " must be positive")
  | value > toInteger (maxBound :: Int) = Left (label <> " exceeds Int range")
  | otherwise = Right (fromInteger value)

requireFlatInput :: Text -> RuntimeRepresentation -> Either Text Int
requireFlatInput name representation =
  case representation of
    FlatRuntimeRepresentation width -> Right width
    TokenRuntimeRepresentation _ _ ->
      Left (name <> ": layer requires a flat input representation")

requireTokenInput
  :: Text -> RuntimeRepresentation -> Either Text (Int, Int)
requireTokenInput name representation =
  case representation of
    TokenRuntimeRepresentation tokens width -> Right (tokens, width)
    FlatRuntimeRepresentation _ ->
      Left (name <> ": layer requires a token input representation")

representationFeatureWidth :: RuntimeRepresentation -> Int
representationFeatureWidth representation =
  case representation of
    FlatRuntimeRepresentation width -> width
    TokenRuntimeRepresentation _ width -> width

layerShapeMismatch
  :: Text -> Text -> Int -> Int -> Either Text ()
layerShapeMismatch name label expected actual =
  Left
    ( name
        <> ": "
        <> label
        <> " mismatch: expected "
        <> showText expected
        <> ", got "
        <> showText actual
    )

outputWidthMismatch :: Text -> Int -> Int -> Either Text ()
outputWidthMismatch label expected actual =
  Left
    ( label
        <> " output width mismatch: expected "
        <> showText expected
        <> ", got "
        <> showText actual
    )

toMlpShape :: RuntimeMlpShape -> MlpShape
toMlpShape shape =
  MlpShape
    { mlpInputs = runtimeMlpInputs shape
    , mlpHidden = runtimeMlpHidden shape
    , mlpOutputs = runtimeMlpOutputs shape
    }

mapLeft :: (left -> other) -> Either left value -> Either other value
mapLeft transform result =
  case result of
    Left err -> Left (transform err)
    Right value -> Right value

showText :: (Show value) => value -> Text
showText = Text.pack . show

{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Exact, persistence-safe supervised inference runtimes.
--
-- Phase 239: the trained typed 'LayerGraph.LayerGraph' is the single supervised
-- served representation.  This module no longer persists or executes a V2
-- structural layer-operation program; it retains only the pieces required to
-- serve and admit a supervised-graph checkpoint: the task, the input/output
-- transforms that ride OUTSIDE the graph, and the trained graph metadata.  The
-- served forward pass reconstructs and runs the graph
-- ('executeSupervisedGraphRuntime'); the transforms are applied as exact pure
-- functions before and after that graph run.
--
-- Raw values are deliberately forgeable serialisation DTOs.  The refined
-- constructors are hidden: callers can obtain them only by checking the full
-- task/transform contract and, for a loaded value, the exact JMW1 bytes against
-- the graph parameter count.
module JitML.SL.RuntimeArtifact
  ( -- * Forgeable wire DTOs
    RawRuntimeTask (..)
  , RawRuntimeImageGeometry (..)
  , RawRuntimeInputTransform (..)
  , RawRuntimeOutputTransform (..)
  , RawSupervisedRuntime (..)
  , RawSupervisedRuntimeOrigin (..)
  , RawSupervisedRuntimePayload (..)
  , RawTrainingRuntimeArtifact (..)

    -- * Hidden refined runtime values
  , RuntimeTask
  , RuntimeImageGeometry
  , RuntimeInputTransform
  , RuntimeOutputTransform
  , SupervisedRuntime
  , SupervisedRuntimeOrigin
  , SupervisedRuntimePayload
  , TrainingRuntimeArtifact

    -- * Refinement and construction
  , refineRuntimeTask
  , refineRuntimeImageGeometry
  , refineRuntimeInputTransform
  , refineRuntimeOutputTransform
  , refineSupervisedRuntime
  , refineSupervisedRuntimePayload
  , refineTrainingRuntimeArtifact
  , mkTrainingRuntimeArtifact

    -- * Raw projections
  , runtimeTaskToRaw
  , runtimeImageGeometryToRaw
  , runtimeInputTransformToRaw
  , runtimeOutputTransformToRaw
  , supervisedRuntimeToRaw
  , supervisedRuntimeOriginToRaw
  , supervisedRuntimePayloadToRaw
  , trainingRuntimeArtifactToRaw

    -- * Refined accessors
  , runtimeTaskSemanticWidth
  , runtimeTaskIsClassification
  , runtimeImageWidth
  , runtimeImageHeight
  , runtimeImageChannels
  , runtimeImageElementCount
  , runtimeInputWidth
  , supervisedRuntimeTask
  , supervisedRuntimeInputTransform
  , supervisedRuntimeOutputTransform
  , supervisedRuntimeInputWidth
  , payloadRowId
  , payloadOrigin
  , payloadPlanId
  , payloadPlanIdText
  , payloadDatasetSha256
  , payloadInitialJmw1Sha256
  , payloadFinalJmw1Sha256
  , payloadRuntime
  , payloadLayerGraphMetadata
  , supervisedPayloadParameterCount
  , trainingArtifactPayload
  , trainingArtifactInitialJmw1Bytes
  , trainingArtifactFinalJmw1Bytes

    -- * Exact serving through the trained graph
  , applyRuntimeInputTransform
  , applyRuntimeOutputTransform
  , executeSupervisedGraphRuntime
  )
where

import Codec.Serialise (Serialise)
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isDigit)
import Data.Foldable (traverse_)
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
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.LayerGraphMetadata
  ( LayerGraphMetadata
  , layerGraphMetadataParameterCount
  )
import JitML.Plan.Plan
  ( PlanId
  , planIdText
  , refinePlanIdText
  )

-- Raw DTOs -------------------------------------------------------------------

data RawRuntimeTask
  = RawClassificationRuntimeTask Int
  | RawRegressionRuntimeTask Int
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

-- | Phase 239 — the supervised runtime carries only the task and the exact
-- input/output transforms applied outside the trained graph.  The topology and
-- parameters live in the trained 'LayerGraph.LayerGraph' description
-- ('rawRuntimePayloadLayerGraphMetadata'); there is no persisted structural
-- layer-operation program.
data RawSupervisedRuntime = RawSupervisedRuntime
  { rawSupervisedRuntimeTask :: RawRuntimeTask
  , rawSupervisedRuntimeInputTransform :: RawRuntimeInputTransform
  , rawSupervisedRuntimeOutputTransform :: RawRuntimeOutputTransform
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Closed provenance for the plan bound into a supervised runtime.
--
-- Product publication carries the exact registry projection implicitly: the
-- row plus PlanId must re-project to exactly one supported substrate.  A
-- public/daemon @jitml train@ command is intentionally broader than the
-- ProductRow matrix, so it persists a composite execution origin: the exact
-- canonical problem row plus the complete canonical 'SupervisedPlan'
-- transport that produced its PlanId.
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
  , rawRuntimePayloadLayerGraphMetadata :: Maybe LayerGraphMetadata
  -- ^ Phase 237/239: the trained typed 'LayerGraph.LayerGraph' projected into
  -- its serialisable checkpoint description.  Every supervised checkpoint now
  -- carries this graph; the served checkpoint reconstructs and runs it directly
  -- and admission anchors the weight blob length to its parameter count.
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

data RuntimeTask
  = ClassificationRuntimeTask Int
  | RegressionRuntimeTask Int
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

data SupervisedRuntime = SupervisedRuntime
  { refinedRuntimeTask :: !RuntimeTask
  , refinedRuntimeInputTransform :: !RuntimeInputTransform
  , refinedRuntimeOutputTransform :: !RuntimeOutputTransform
  , refinedRuntimeInputWidth :: !Int
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
  , refinedPayloadLayerGraphMetadata :: !(Maybe LayerGraphMetadata)
  }
  deriving stock (Eq, Show)

data TrainingRuntimeArtifact = TrainingRuntimeArtifact
  { refinedTrainingPayload :: !SupervisedRuntimePayload
  , refinedTrainingInitialBytes :: !StrictByteString.ByteString
  , refinedTrainingFinalBytes :: !StrictByteString.ByteString
  }
  deriving stock (Eq, Show)

-- Leaf refinement -------------------------------------------------------------

refineRuntimeTask :: RawRuntimeTask -> Either Text RuntimeTask
refineRuntimeTask raw =
  case raw of
    RawClassificationRuntimeTask width ->
      ClassificationRuntimeTask
        <$> requirePositive "classification semantic width" width
    RawRegressionRuntimeTask width ->
      RegressionRuntimeTask
        <$> requirePositive "regression semantic width" width

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
  task <- refineRuntimeTask (rawSupervisedRuntimeTask raw)
  inputTransform <-
    refineRuntimeInputTransform (rawSupervisedRuntimeInputTransform raw)
  outputTransform <-
    refineRuntimeOutputTransform (rawSupervisedRuntimeOutputTransform raw)
  validateTaskAndTransforms task inputTransform outputTransform
  Right
    SupervisedRuntime
      { refinedRuntimeTask = task
      , refinedRuntimeInputTransform = inputTransform
      , refinedRuntimeOutputTransform = outputTransform
      , refinedRuntimeInputWidth = runtimeInputWidth inputTransform
      }

-- | Cross-check that the task and its transforms are mutually consistent.  The
-- graph itself owns the topology and output width, so this validates only the
-- transform algebra: transform kind vs task kind, and the semantic width of the
-- semantic-prefix / destandardize transforms.
validateTaskAndTransforms
  :: RuntimeTask
  -> RuntimeInputTransform
  -> RuntimeOutputTransform
  -> Either Text ()
validateTaskAndTransforms task inputTransform outputTransform = do
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
    (_, IdentityOutput) -> Right ()
    (ClassificationRuntimeTask _, SemanticPrefixOutput width)
      | width /= semanticWidth ->
          outputWidthMismatch "semantic-prefix task" semanticWidth width
      | otherwise -> Right ()
    (RegressionRuntimeTask _, DestandardizeOutput means scales)
      | VU.length means /= semanticWidth ->
          outputWidthMismatch "destandardize mean" semanticWidth (VU.length means)
      | VU.length scales /= semanticWidth ->
          outputWidthMismatch "destandardize scale" semanticWidth (VU.length scales)
      | otherwise -> Right ()

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
      , refinedPayloadLayerGraphMetadata =
          rawRuntimePayloadLayerGraphMetadata raw
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

-- | The graph-ordered parameter count a supervised payload's exact JMW1 blobs
-- must have.  Every supervised checkpoint carries its trained graph metadata,
-- so a payload without it is rejected before any bytes are trusted.
supervisedPayloadParameterCount
  :: SupervisedRuntimePayload -> Either Text Int
supervisedPayloadParameterCount payload =
  case refinedPayloadLayerGraphMetadata payload of
    Just graphMeta -> Right (layerGraphMetadataParameterCount graphMeta)
    Nothing ->
      Left "supervised runtime payload is missing its trained layer graph metadata"

mkTrainingRuntimeArtifact
  :: SupervisedRuntimePayload
  -> LazyByteString.ByteString
  -> LazyByteString.ByteString
  -> Either Text TrainingRuntimeArtifact
mkTrainingRuntimeArtifact payload initialBytes finalBytes = do
  expectedCount <- supervisedPayloadParameterCount payload
  _ <-
    validateExactJmw1
      "initial"
      (runtimeShaText (refinedPayloadInitialJmw1Sha256 payload))
      expectedCount
      initialBytes
  _ <-
    validateExactJmw1
      "final"
      (runtimeShaText (refinedPayloadFinalJmw1Sha256 payload))
      expectedCount
      finalBytes
  Right
    TrainingRuntimeArtifact
      { refinedTrainingPayload = payload
      , refinedTrainingInitialBytes = LazyByteString.toStrict initialBytes
      , refinedTrainingFinalBytes = LazyByteString.toStrict finalBytes
      }

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

-- Raw projections -------------------------------------------------------------

runtimeTaskToRaw :: RuntimeTask -> RawRuntimeTask
runtimeTaskToRaw task =
  case task of
    ClassificationRuntimeTask width -> RawClassificationRuntimeTask width
    RegressionRuntimeTask width -> RawRegressionRuntimeTask width

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

supervisedRuntimeToRaw :: SupervisedRuntime -> RawSupervisedRuntime
supervisedRuntimeToRaw runtime =
  RawSupervisedRuntime
    { rawSupervisedRuntimeTask = runtimeTaskToRaw (supervisedRuntimeTask runtime)
    , rawSupervisedRuntimeInputTransform =
        runtimeInputTransformToRaw (supervisedRuntimeInputTransform runtime)
    , rawSupervisedRuntimeOutputTransform =
        runtimeOutputTransformToRaw (supervisedRuntimeOutputTransform runtime)
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
    , rawRuntimePayloadLayerGraphMetadata = payloadLayerGraphMetadata payload
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

supervisedRuntimeTask :: SupervisedRuntime -> RuntimeTask
supervisedRuntimeTask = refinedRuntimeTask

supervisedRuntimeInputTransform :: SupervisedRuntime -> RuntimeInputTransform
supervisedRuntimeInputTransform = refinedRuntimeInputTransform

supervisedRuntimeOutputTransform :: SupervisedRuntime -> RuntimeOutputTransform
supervisedRuntimeOutputTransform = refinedRuntimeOutputTransform

supervisedRuntimeInputWidth :: SupervisedRuntime -> Int
supervisedRuntimeInputWidth = refinedRuntimeInputWidth

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

payloadLayerGraphMetadata :: SupervisedRuntimePayload -> Maybe LayerGraphMetadata
payloadLayerGraphMetadata = refinedPayloadLayerGraphMetadata

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

-- Exact serving through the trained graph --------------------------------------

-- | Apply the exact input transform outside the graph.  Pure and deterministic:
-- the served forward pass runs entirely through 'LayerGraph.runLayerGraph', so
-- the pre-transform stays a plain function on the input vector.
applyRuntimeInputTransform
  :: RuntimeInputTransform -> Vector Double -> Either Text (Vector Double)
applyRuntimeInputTransform transform input = do
  validateVectorWidth "runtime input" (runtimeInputWidth transform) input
  case transform of
    IdentityInput _ -> Right input
    UnitImageInput _ ->
      VU.mapM
        ( \value ->
            if value < 0.0 || value > 1.0
              then Left "unit-image input values must be in [0,1]"
              else Right value
        )
        input
    StandardizeInput means scales ->
      VU.generateM
        (VU.length input)
        ( \index -> do
            let value = input VU.! index
                meanValue = means VU.! index
                scale = scales VU.! index
                standardized = (value - meanValue) / scale
            requireFinite "standardized runtime input" standardized
            Right standardized
        )

-- | Apply the exact output transform outside the graph (semantic-prefix slice
-- for classification, inverse standardisation for regression).
applyRuntimeOutputTransform
  :: RuntimeTask
  -> RuntimeOutputTransform
  -> Vector Double
  -> Either Text (Vector Double)
applyRuntimeOutputTransform task transform output = do
  traverse_ (requireFinite "runtime raw output") (VU.toList output)
  let semanticWidth = runtimeTaskSemanticWidth task
  case transform of
    IdentityOutput -> do
      validateVectorWidth "runtime semantic output" semanticWidth output
      Right output
    SemanticPrefixOutput width ->
      if width /= semanticWidth || VU.length output < width
        then Left "semantic-prefix output width mismatch"
        else Right (VU.slice 0 width output)
    DestandardizeOutput means scales -> do
      validateVectorWidth "destandardize raw output" semanticWidth output
      VU.generateM semanticWidth $ \index -> do
        let value = output VU.! index * scales VU.! index + means VU.! index
        requireFinite "destandardized runtime output" value
        Right value

-- | Phase 239 — serve a supervised-graph checkpoint: apply the exact input
-- transform, run the reconstructed trained 'LayerGraph.LayerGraph' with its
-- injected parameters, then apply the exact output transform.  The transforms
-- ride OUTSIDE the graph; the graph is the sole topology and parameter owner.
executeSupervisedGraphRuntime
  :: SupervisedRuntimePayload
  -> LayerGraph.LayerGraph
  -> Vector Double
  -> Either Text (Vector Double)
executeSupervisedGraphRuntime payload graph rawInput = do
  input <- applyRuntimeInputTransform (supervisedRuntimeInputTransform runtime) rawInput
  tape <- LayerGraph.runLayerGraph graph input
  applyRuntimeOutputTransform
    (supervisedRuntimeTask runtime)
    (supervisedRuntimeOutputTransform runtime)
    (LayerGraph.layerTapeOutput tape)
 where
  runtime = payloadRuntime payload

-- Validation helpers ----------------------------------------------------------

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

checkedIntValue :: Text -> Integer -> Either Text Int
checkedIntValue label value
  | value <= 0 = Left (label <> " must be positive")
  | value > toInteger (maxBound :: Int) = Left (label <> " exceeds Int range")
  | otherwise = Right (fromInteger value)

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

outputWidthMismatch :: Text -> Int -> Int -> Either Text ()
outputWidthMismatch label expected actual =
  Left
    ( label
        <> " output width mismatch: expected "
        <> showText expected
        <> ", got "
        <> showText actual
    )

mapLeft :: (left -> other) -> Either left value -> Either other value
mapLeft transform result =
  case result of
    Left err -> Left (transform err)
    Right value -> Right value

showText :: (Show value) => value -> Text
showText = Text.pack . show

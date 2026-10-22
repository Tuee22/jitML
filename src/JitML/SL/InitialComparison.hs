{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A replayable named comparison with the actual initialization. Structural
-- refinement does not attest that training happened. Producer authentication
-- and the before-update capture belong to the execution evidence boundary.
-- Neither this value nor an initial model is an eligible checkpoint.
module JitML.SL.InitialComparison
  ( RawInitialComparisonSnapshot (..)
  , InitialComparisonSnapshot
  , SupervisedComparison
  , refineInitialComparisonSnapshot
  , initialComparisonSnapshotToRaw
  , encodeInitialComparisonSnapshot
  , decodeInitialComparisonSnapshot
  , initialComparisonSnapshotSha256
  , initialComparisonJmw1Sha256
  , prepareSupervisedComparison
  , comparisonInitialInference
  , comparisonFinalInference
  , comparisonInitialSnapshot
  , comparisonFinalJmw1Bytes
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Generics (Generic)

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.LayerGraphMetadata
  ( LayerGraphMetadata
  , layerGraphFromMetadata
  , layerGraphMetadataParameterCount
  )
import JitML.SL.RuntimeArtifact qualified as Runtime

data RawInitialComparisonSnapshot = RawInitialComparisonSnapshot
  { rawInitialComparisonVersion :: !Int
  , rawInitialComparisonRuntime :: !Runtime.RawSupervisedRuntime
  , rawInitialComparisonGraphMetadata :: !LayerGraphMetadata
  , rawInitialComparisonJmw1Bytes :: !ByteString
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data InitialComparisonSnapshot
  = InitialComparisonSnapshot
      !RawInitialComparisonSnapshot
      !Runtime.SupervisedRuntime
      !LayerGraph.LayerGraph
  deriving stock (Eq, Show)

data SupervisedComparison
  = SupervisedComparison
      !InitialComparisonSnapshot
      !ByteString
      !LayerGraph.LayerGraph
  deriving stock (Eq, Show)

refineInitialComparisonSnapshot
  :: RawInitialComparisonSnapshot
  -> Either Text InitialComparisonSnapshot
refineInitialComparisonSnapshot raw = do
  if rawInitialComparisonVersion raw == 1
    then Right ()
    else Left "unsupported initial comparison snapshot version"
  runtime <- Runtime.refineSupervisedRuntime (rawInitialComparisonRuntime raw)
  graph <- prepareGraph (rawInitialComparisonGraphMetadata raw) (rawInitialComparisonJmw1Bytes raw)
  validateRuntimeGraphDimensions runtime graph
  Right (InitialComparisonSnapshot raw runtime graph)

initialComparisonSnapshotToRaw
  :: InitialComparisonSnapshot
  -> RawInitialComparisonSnapshot
initialComparisonSnapshotToRaw (InitialComparisonSnapshot raw _ _) = raw

encodeInitialComparisonSnapshot
  :: InitialComparisonSnapshot
  -> ByteString
encodeInitialComparisonSnapshot = LazyByteString.toStrict . serialise . initialComparisonSnapshotToRaw

decodeInitialComparisonSnapshot
  :: ByteString
  -> Either Text InitialComparisonSnapshot
decodeInitialComparisonSnapshot bytes = do
  raw <-
    case deserialiseOrFail (LazyByteString.fromStrict bytes) of
      Left err -> Left ("initial comparison snapshot decode failed: " <> Text.pack (show err))
      Right value -> Right value
  snapshot <- refineInitialComparisonSnapshot raw
  if encodeInitialComparisonSnapshot snapshot == bytes
    then Right snapshot
    else Left "initial comparison snapshot encoding is not canonical"

initialComparisonSnapshotSha256 :: InitialComparisonSnapshot -> Text
initialComparisonSnapshotSha256 =
  WeightCodec.jmw1ContentSha . LazyByteString.fromStrict . encodeInitialComparisonSnapshot

initialComparisonJmw1Sha256 :: InitialComparisonSnapshot -> Text
initialComparisonJmw1Sha256 =
  WeightCodec.jmw1ContentSha
    . LazyByteString.fromStrict
    . rawInitialComparisonJmw1Bytes
    . initialComparisonSnapshotToRaw

-- | Bind both computations to the same exact static descriptor and fitted
-- transforms. Identical initial/final weights remain valid raw observations;
-- the strict paired learning predicate rejects their lack of improvement.
-- No completion/admission predicate is relaxed to construct this comparison.
prepareSupervisedComparison
  :: InitialComparisonSnapshot
  -> Runtime.RawSupervisedRuntime
  -> LayerGraphMetadata
  -> ByteString
  -> Either Text SupervisedComparison
prepareSupervisedComparison snapshot finalRuntime finalMetadata finalBytes = do
  let raw = initialComparisonSnapshotToRaw snapshot
  if serialise finalRuntime == serialise (rawInitialComparisonRuntime raw)
    then Right ()
    else Left "initial and final comparison runtime transforms differ"
  if serialise finalMetadata == serialise (rawInitialComparisonGraphMetadata raw)
    then Right ()
    else Left "initial and final comparison graph descriptors differ"
  graph <- prepareGraph finalMetadata finalBytes
  Right (SupervisedComparison snapshot finalBytes graph)

comparisonInitialSnapshot :: SupervisedComparison -> InitialComparisonSnapshot
comparisonInitialSnapshot (SupervisedComparison snapshot _ _) = snapshot

comparisonFinalJmw1Bytes :: SupervisedComparison -> ByteString
comparisonFinalJmw1Bytes (SupervisedComparison _ bytes _) = bytes

comparisonInitialInference
  :: SupervisedComparison
  -> [Double]
  -> Either Text [Double]
comparisonInitialInference (SupervisedComparison (InitialComparisonSnapshot _ runtime graph) _ _) =
  fmap VU.toList . Runtime.executeSupervisedRuntime runtime graph . VU.fromList

comparisonFinalInference
  :: SupervisedComparison
  -> [Double]
  -> Either Text [Double]
comparisonFinalInference (SupervisedComparison (InitialComparisonSnapshot _ runtime _) _ graph) =
  fmap VU.toList . Runtime.executeSupervisedRuntime runtime graph . VU.fromList

prepareGraph :: LayerGraphMetadata -> ByteString -> Either Text LayerGraph.LayerGraph
prepareGraph metadata bytes = do
  values <- WeightCodec.decodeJmw1 (LazyByteString.fromStrict bytes)
  if WeightCodec.encodeJmw1 values == LazyByteString.fromStrict bytes
    then Right ()
    else Left "comparison JMW1 encoding is not canonical"
  if length values == layerGraphMetadataParameterCount metadata
    then Right ()
    else Left "comparison JMW1 parameter count differs from its graph descriptor"
  if all (\value -> not (isNaN value || isInfinite value)) values
    then Right ()
    else Left "comparison JMW1 contains a non-finite parameter"
  graph <- layerGraphFromMetadata metadata
  injected <- LayerGraph.replaceGraphParameterVector graph (VU.fromList values)
  case LayerGraph.refineReloadedLayerGraph injected of
    Left err -> Left ("comparison graph refinement failed: " <> err)
    Right refined -> Right refined

validateRuntimeGraphDimensions
  :: Runtime.SupervisedRuntime
  -> LayerGraph.LayerGraph
  -> Either Text ()
validateRuntimeGraphDimensions runtime graph = do
  let inputWidth = product (LayerGraph.unTensorShape (LayerGraph.layerGraphInputShape graph))
      outputWidth = product (LayerGraph.unTensorShape (LayerGraph.layerGraphOutputShape graph))
      semanticWidth = Runtime.runtimeTaskSemanticWidth (Runtime.supervisedRuntimeTask runtime)
  if Runtime.supervisedRuntimeInputWidth runtime == inputWidth
    then Right ()
    else Left "initial comparison runtime input width differs from its graph"
  case Runtime.runtimeOutputTransformToRaw (Runtime.supervisedRuntimeOutputTransform runtime) of
    Runtime.RawSemanticPrefixOutput _
      | outputWidth >= semanticWidth -> Right ()
      | otherwise -> Left "initial comparison graph output is narrower than its semantic prefix"
    _
      | outputWidth == semanticWidth -> Right ()
      | otherwise -> Left "initial comparison graph output width differs from its semantic runtime"

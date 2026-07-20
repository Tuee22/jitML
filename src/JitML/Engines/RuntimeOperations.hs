{-# LANGUAGE OverloadedStrings #-}

-- | Pure deterministic oracle for focused supervised-runtime tests. This
-- module is not hardware acceleration, is never selected implicitly, and no
-- production engine record installs these callbacks. Production structural
-- operations cross the versioned generated CPU/CUDA ABI or fixed Metal bridge.
module JitML.Engines.RuntimeOperations
  ( hostAttention
  , hostInputTransform
  , hostLayerNorm
  , hostMeanPool
  , hostOutputTransform
  , hostPatchExtract
  , hostResidualAdd
  , hostTokenMix
  )
where

import Data.Foldable (traverse_)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

import JitML.Numerics.Mlp (MlpParams)
import JitML.SL.RuntimeArtifact qualified as Runtime

hostInputTransform :: Runtime.RuntimeInputTransformExecutor
hostInputTransform transform input =
  pure $ do
    validateVectorWidth "runtime input" (Runtime.runtimeInputWidth transform) input
    case Runtime.runtimeInputTransformToRaw transform of
      Runtime.RawIdentityInput _ -> Right input
      Runtime.RawUnitImageInput _ ->
        VU.mapM
          ( \value ->
              if value < 0.0 || value > 1.0
                then Left "unit-image input values must be in [0,1]"
                else Right value
          )
          input
      Runtime.RawStandardizeInput rawMeans rawScales -> do
        let means = VU.fromList rawMeans
            scales = VU.fromList rawScales
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

hostOutputTransform :: Runtime.RuntimeOutputTransformExecutor
hostOutputTransform task transform output =
  pure $ do
    traverse_ (requireFinite "runtime raw output") (VU.toList output)
    let semanticWidth = Runtime.runtimeTaskSemanticWidth task
    case Runtime.runtimeOutputTransformToRaw transform of
      Runtime.RawIdentityOutput -> do
        validateVectorWidth "runtime semantic output" semanticWidth output
        Right output
      Runtime.RawSemanticPrefixOutput width -> do
        if width /= semanticWidth || VU.length output < width
          then Left "semantic-prefix output width mismatch"
          else Right (VU.slice 0 width output)
      Runtime.RawDestandardizeOutput rawMeans rawScales -> do
        validateVectorWidth "destandardize raw output" semanticWidth output
        let means = VU.fromList rawMeans
            scales = VU.fromList rawScales
        decoded <-
          VU.generateM semanticWidth $ \index -> do
            let value = output VU.! index * scales VU.! index + means VU.! index
            requireFinite "destandardized runtime output" value
            Right value
        Right decoded

hostResidualAdd :: Runtime.RuntimeResidualAddExecutor
hostResidualAdd scale input residual =
  pure $ do
    requireFinitePositive "residual scale" scale
    traverse_ (requireFinite "residual input") (VU.toList input)
    validateVectorWidth "residual output" (VU.length input) residual
    let output = VU.zipWith (\value delta -> value + scale * delta) input residual
    traverse_ (requireFinite "residual result") (VU.toList output)
    Right output

hostLayerNorm :: Runtime.RuntimeLayerNormExecutor
hostLayerNorm input =
  pure $ do
    if VU.null input
      then Left "layernorm requires a positive token width"
      else Right ()
    traverse_ (requireFinite "layernorm input") (VU.toList input)
    let count = fromIntegral (VU.length input)
        meanValue = VU.sum input / count
        centered = VU.map (subtract meanValue) input
        variance = VU.sum (VU.map (\value -> value * value) centered) / count
        inverseStd = 1.0 / sqrt (variance + 1.0e-5)
        output = VU.map (* inverseStd) centered
    traverse_ (requireFinite "layernorm output") (VU.toList output)
    Right output

hostTokenMix :: Runtime.RuntimeTokenMixExecutor
hostTokenMix backend layer tokenCount width shape params tokens =
  case validateTokens tokenCount width tokens of
    Left err -> pure (Left err)
    Right () -> do
      let channels =
            [ VU.fromList [token VU.! channel | token <- tokens]
            | channel <- [0 .. width - 1]
            ]
      mixed <- traverse (runMlp backend layer shape params) channels
      case sequence mixed of
        Left err -> pure (Left err)
        Right outputs ->
          case traverse_ (validateVectorWidth "token-mix channel" tokenCount) outputs of
            Left err -> pure (Left err)
            Right () ->
              pure
                ( Right
                    [ VU.fromList
                        [ outputs !! channel VU.! tokenIndex
                        | channel <- [0 .. width - 1]
                        ]
                    | tokenIndex <- [0 .. tokenCount - 1]
                    ]
                )

hostPatchExtract :: Runtime.RuntimePatchExtractExecutor
hostPatchExtract geometry positions input =
  pure (traverse (extractPatch geometry input) positions)

hostAttention :: Runtime.RuntimeAttentionExecutor
hostAttention backend layer width shape params tokens
  | null tokens = pure (Left "attention requires a nonempty token sequence")
  | otherwise = do
      qkvResults <- traverse (runMlp backend layer shape params) tokens
      case sequence qkvResults of
        Left err -> pure (Left err)
        Right qkvs ->
          case attentionOutputs qkvs of
            Left err -> pure (Left err)
            Right attended -> pure (Right attended)
 where
  attentionOutputs qkvs = do
    triples <- traverse (splitQkvExact width) qkvs
    let queries = fmap firstOf3 triples
        keys = fmap secondOf3 triples
        values = fmap thirdOf3 triples
        scale = 1.0 / sqrt (fromIntegral width)
    attended <-
      traverse
        (\query -> attentionForQuery scale query keys values)
        queries
    if length attended /= length tokens
      then Left "attention output token count mismatch"
      else Right attended

hostMeanPool :: Runtime.RuntimeMeanPoolExecutor
hostMeanPool [] = pure (Left "mean-pool requires a nonempty token sequence")
hostMeanPool tokens@(first : _) =
  pure $ do
    let width = VU.length first
    if width <= 0
      then Left "mean-pool token width must be positive"
      else Right ()
    traverse_ (validateVectorWidth "mean-pool token" width) tokens
    let total = List.foldl' addVector (VU.replicate width 0.0) tokens
        output = VU.map (/ fromIntegral (length tokens)) total
    traverse_ (requireFinite "mean-pool output") (VU.toList output)
    Right output

runMlp
  :: Runtime.RuntimeBackendExecutor
  -> Runtime.RuntimeLayer
  -> Runtime.RuntimeMlpShape
  -> MlpParams
  -> Vector Double
  -> IO (Either Text (Vector Double))
runMlp backend layer shape params input =
  case validateVectorWidth "MLP input" (Runtime.runtimeMlpInputs shape) input of
    Left err -> pure (Left err)
    Right () -> do
      result <- Runtime.runtimeBackendMlpExecutor backend params input
      pure $ do
        output <- mapLeft (backendError backend "mlp") result
        mapLeft
          (\err -> Runtime.runtimeLayerName layer <> " callback: " <> err)
          (validateVectorWidth "MLP output" (Runtime.runtimeMlpOutputs shape) output)
        Right output

backendError :: Runtime.RuntimeBackendExecutor -> Text -> Text -> Text
backendError backend operation err =
  "runtime backend "
    <> Runtime.runtimeBackendLabel backend
    <> " "
    <> operation
    <> " failed: "
    <> err

extractPatch
  :: Runtime.RuntimeImageGeometry
  -> Vector Double
  -> [Int]
  -> Either Text (Vector Double)
extractPatch geometry input indices = do
  firstIndex <-
    case indices of
      first : _ -> Right first
      [] -> Left "patch position must contain pixels"
  values <-
    traverse
      ( \index ->
          if index < 0 || index >= VU.length input
            then Left "patch index is out of bounds"
            else Right (input VU.! index)
      )
      indices
  let pixel = firstIndex `div` Runtime.runtimeImageChannels geometry
      x = pixel `mod` Runtime.runtimeImageWidth geometry
      y = pixel `div` Runtime.runtimeImageWidth geometry
      normalized coordinate extent =
        if extent <= 1
          then 0.0
          else
            (fromIntegral coordinate / fromIntegral (extent - 1)) * 2.0 - 1.0
      coordinates =
        [ normalized x (Runtime.runtimeImageWidth geometry)
        , normalized y (Runtime.runtimeImageHeight geometry)
        ]
  Right (VU.fromList (values <> coordinates))

splitQkvExact
  :: Int
  -> Vector Double
  -> Either Text (Vector Double, Vector Double, Vector Double)
splitQkvExact width vector = do
  validateVectorWidth "attention QKV" (3 * width) vector
  Right
    ( VU.slice 0 width vector
    , VU.slice width width vector
    , VU.slice (2 * width) width vector
    )

attentionForQuery
  :: Double
  -> Vector Double
  -> [Vector Double]
  -> [Vector Double]
  -> Either Text (Vector Double)
attentionForQuery scale query keys values = do
  if null keys || length keys /= length values
    then Left "attention requires equal nonempty key/value sequences"
    else Right ()
  let scores = VU.fromList [dotVector query key * scale | key <- keys]
  weights <- softmaxExact scores
  weightedSumExact weights values

softmaxExact :: Vector Double -> Either Text (Vector Double)
softmaxExact values
  | VU.null values = Left "softmax requires a nonempty vector"
  | otherwise = do
      traverse_ (requireFinite "attention score") (VU.toList values)
      let maximumValue = VU.maximum values
          exponentials = VU.map (exp . subtract maximumValue) values
          denominator = VU.sum exponentials
      requireFinitePositive "attention softmax denominator" denominator
      let output = VU.map (/ denominator) exponentials
      traverse_ (requireFinite "attention softmax output") (VU.toList output)
      Right output

weightedSumExact
  :: Vector Double
  -> [Vector Double]
  -> Either Text (Vector Double)
weightedSumExact weights vectors = do
  first <-
    case vectors of
      value : _
        | VU.length weights == length vectors -> Right value
      _ -> Left "weighted sum requires equal nonempty weights and vectors"
  let width = VU.length first
  if width <= 0
    then Left "weighted sum vector width must be positive"
    else Right ()
  traverse_ (validateVectorWidth "weighted-sum value" width) vectors
  let output =
        VU.generate width $ \index ->
          sum
            [ weights VU.! vectorIndex * (vector VU.! index)
            | (vectorIndex, vector) <- zip [0 :: Int ..] vectors
            ]
  traverse_ (requireFinite "weighted-sum output") (VU.toList output)
  Right output

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

addVector :: Vector Double -> Vector Double -> Vector Double
addVector = VU.zipWith (+)

dotVector :: Vector Double -> Vector Double -> Double
dotVector left right = VU.sum (VU.zipWith (*) left right)

firstOf3 :: (a, b, c) -> a
firstOf3 (first, _, _) = first

secondOf3 :: (a, b, c) -> b
secondOf3 (_, second, _) = second

thirdOf3 :: (a, b, c) -> c
thirdOf3 (_, _, third) = third

mapLeft :: (left -> other) -> Either left value -> Either other value
mapLeft transform result =
  case result of
    Left err -> Left (transform err)
    Right value -> Right value

showText :: (Show value) => value -> Text
showText = Text.pack . show

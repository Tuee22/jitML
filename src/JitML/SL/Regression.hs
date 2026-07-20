{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Regression
  ( RegressionExample (..)
  , RegressionConfig (..)
  , RegressionRunMetrics (..)
  , RegressionStandardization
  , TrainedRegressor (..)
  , applyRegressionStandardization
  , applyRegressionStandardizationDataset
  , defaultRegressionConfig
  , decodeCaliforniaHousingArchiveBoundedData
  , decodeCaliforniaHousingBoundedData
  , fitRegressionStandardization
  , inverseRegressionTarget
  , parseCaliforniaHousingData
  , regressionFeatureMeans
  , regressionFeatureScales
  , regressionTargetMean
  , regressionTargetScale
  , standardizeRegressionExamples
  , trainRegressorWithDevice
  , predictRegressorWithDevice
  , meanSquaredErrorWithDevice
  )
where

import Control.Monad (foldM, when)
import Data.ByteString (ByteString)
import Data.Either (fromRight)
import Data.Foldable (traverse_)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import Text.Read qualified

import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , MlpGradient (..)
  , MlpParams
  , MlpShape (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  )
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.SL.Archive qualified as Archive

data RegressionExample = RegressionExample
  { regressionFeatures :: !(Vector Double)
  , regressionTarget :: !Double
  }
  deriving stock (Eq, Show)

data RegressionConfig = RegressionConfig
  { regSeed :: !Int
  , regInputs :: !Int
  , regHidden :: !Int
  , regEpochs :: !Int
  , regBatchSize :: !Int
  , regLearningRate :: !Double
  }
  deriving stock (Eq, Show)

-- | Statistics fitted from the training partition only.  The constructor is
-- deliberately hidden so checkpoint/runtime callers cannot pair arbitrary
-- means and scales or mint a zero-width transform.
data RegressionStandardization = RegressionStandardization
  { standardizationFeatureMeans :: !(Vector Double)
  , standardizationFeatureScales :: !(Vector Double)
  , standardizationTargetMean :: !Double
  , standardizationTargetScale :: !Double
  }
  deriving stock (Eq, Show)

regressionFeatureMeans :: RegressionStandardization -> [Double]
regressionFeatureMeans = VU.toList . standardizationFeatureMeans

regressionFeatureScales :: RegressionStandardization -> [Double]
regressionFeatureScales = VU.toList . standardizationFeatureScales

regressionTargetMean :: RegressionStandardization -> Double
regressionTargetMean = standardizationTargetMean

regressionTargetScale :: RegressionStandardization -> Double
regressionTargetScale = standardizationTargetScale

defaultRegressionConfig :: RegressionConfig
defaultRegressionConfig =
  RegressionConfig
    { regSeed = 42
    , regInputs = 8
    , regHidden = 32
    , regEpochs = 100
    , regBatchSize = 128
    , regLearningRate = 1.0e-3
    }

data TrainedRegressor = TrainedRegressor
  { trainedRegressorParams :: !MlpParams
  , trainedRegressorConfig :: !RegressionConfig
  }
  deriving stock (Eq, Show)

-- | Measurements owned by one successful regressor training call. The update
-- count advances in the mini-batch loop only after the device gradient and
-- optimizer step have succeeded; publication code must consume it directly.
data RegressionRunMetrics = RegressionRunMetrics
  { regressionTrainMse :: !Double
  , regressionOptimizerUpdatesExecuted :: !Word64
  }
  deriving stock (Eq, Show)

-- | Parse the extracted @CaliforniaHousing/cal_housing.data@ file from the
-- canonical scikit-learn/Figshare archive. Each non-empty row has eight
-- feature columns followed by the raw median-house-value target.
parseCaliforniaHousingData :: ByteString -> Either String [RegressionExample]
parseCaliforniaHousingData bytes =
  case Text.Encoding.decodeUtf8' bytes of
    Left err -> Left ("california-housing: invalid UTF-8: " <> show err)
    Right text ->
      traverse
        parseRow
        [ (lineNumber, line)
        | (lineNumber, line) <- zip [1 :: Int ..] (Text.lines text)
        , not (Text.null (Text.strip line))
        ]

parseRow :: (Int, Text.Text) -> Either String RegressionExample
parseRow (lineNumber, line) =
  case traverse parseDouble columns of
    Just [f1, f2, f3, f4, f5, f6, f7, f8, target] ->
      Right
        RegressionExample
          { regressionFeatures = VU.fromList [f1, f2, f3, f4, f5, f6, f7, f8]
          , regressionTarget = target
          }
    Just values ->
      Left
        ( "california-housing: line "
            <> show lineNumber
            <> " has "
            <> show (length values)
            <> " columns; expected 9"
        )
    Nothing ->
      Left ("california-housing: line " <> show lineNumber <> " contains a non-numeric field")
 where
  columns = Text.splitOn "," line
  parseDouble value = Text.Read.readMaybe (Text.unpack (Text.strip value))

decodeCaliforniaHousingBoundedData
  :: Maybe Int
  -> ByteString
  -> Either String [RegressionExample]
decodeCaliforniaHousingBoundedData subsetLimit bytes = do
  parsed <- parseCaliforniaHousingData bytes
  dataset <- case subsetLimit of
    Just limit
      | limit <= 0 -> Left "california-housing: subset limit must be positive"
      | otherwise -> Right (take limit parsed)
    Nothing -> Right parsed
  if null dataset
    then Left "california-housing: produced no regression examples"
    else Right dataset

decodeCaliforniaHousingArchiveBoundedData
  :: Maybe Int
  -> ByteString
  -> Either String [RegressionExample]
decodeCaliforniaHousingArchiveBoundedData subsetLimit archiveBytes = do
  dataBytes <- Archive.extractTarEntry "CaliforniaHousing/cal_housing.data" archiveBytes
  decodeCaliforniaHousingBoundedData subsetLimit dataBytes

-- | Fit population-variance statistics from one non-empty, finite,
-- fixed-width training partition.  A constant column uses scale @1@ so the
-- transform remains total without hiding a width mismatch.
fitRegressionStandardization
  :: [RegressionExample]
  -> Either Text.Text RegressionStandardization
fitRegressionStandardization [] =
  Left "fitRegressionStandardization: empty training partition"
fitRegressionStandardization dataset@(firstExample : _) = do
  let width = VU.length (regressionFeatures firstExample)
  when (width <= 0) $
    Left "fitRegressionStandardization: feature width must be positive"
  traverse_ (validateExample width) dataset
  featureStats <-
    traverse
      (populationStats . featureColumn dataset)
      [0 .. width - 1]
  (targetMean, targetScale) <-
    populationStats (fmap regressionTarget dataset)
  pure
    RegressionStandardization
      { standardizationFeatureMeans = VU.fromList (fmap fst featureStats)
      , standardizationFeatureScales = VU.fromList (fmap snd featureStats)
      , standardizationTargetMean = targetMean
      , standardizationTargetScale = targetScale
      }
 where
  featureColumn examples column =
    [regressionFeatures example VU.! column | example <- examples]

-- | Apply already-fitted statistics.  Evaluation rows use the same value
-- fitted from the training partition; this API intentionally cannot refit.
applyRegressionStandardization
  :: RegressionStandardization
  -> RegressionExample
  -> Either Text.Text RegressionExample
applyRegressionStandardization standardization example = do
  let means = standardizationFeatureMeans standardization
      scales = standardizationFeatureScales standardization
      features = regressionFeatures example
      width = VU.length means
  validateExample width example
  if VU.length scales /= width
    then Left "applyRegressionStandardization: invalid fitted scale width"
    else do
      transformedFeatures <-
        VU.generateM
          width
          ( \column ->
              standardizeFinite
                "feature"
                (means VU.! column)
                (scales VU.! column)
                (features VU.! column)
          )
      transformedTarget <-
        standardizeFinite
          "target"
          (standardizationTargetMean standardization)
          (standardizationTargetScale standardization)
          (regressionTarget example)
      pure
        RegressionExample
          { regressionFeatures = transformedFeatures
          , regressionTarget = transformedTarget
          }

applyRegressionStandardizationDataset
  :: RegressionStandardization
  -> [RegressionExample]
  -> Either Text.Text [RegressionExample]
applyRegressionStandardizationDataset standardization =
  traverse (applyRegressionStandardization standardization)

-- | Decode a standardized regression output back into the dataset's target
-- units.  This is the only output transform used by the persisted California
-- Housing runtime.
inverseRegressionTarget
  :: RegressionStandardization
  -> Double
  -> Either Text.Text Double
inverseRegressionTarget standardization standardized = do
  requireFinite "standardized target" standardized
  let decoded =
        standardized * standardizationTargetScale standardization
          + standardizationTargetMean standardization
  requireFinite "decoded target" decoded
  pure decoded

-- | Compatibility helper for callers that deliberately standardize one whole
-- collection.  Production training splits raw rows first and uses the refined
-- fit/apply APIs above so held-out rows never influence fitted statistics.
standardizeRegressionExamples :: [RegressionExample] -> [RegressionExample]
standardizeRegressionExamples [] = []
standardizeRegressionExamples dataset =
  case fitRegressionStandardization dataset of
    Left _ -> []
    Right standardization ->
      fromRight
        []
        (applyRegressionStandardizationDataset standardization dataset)

validateExample :: Int -> RegressionExample -> Either Text.Text ()
validateExample expectedWidth example = do
  let features = regressionFeatures example
  when (VU.length features /= expectedWidth) $
    Left
      ( "regression feature width mismatch: expected "
          <> Text.pack (show expectedWidth)
          <> ", got "
          <> Text.pack (show (VU.length features))
      )
  traverse_ (requireFinite "regression feature") (VU.toList features)
  requireFinite "regression target" (regressionTarget example)

populationStats :: [Double] -> Either Text.Text (Double, Double)
populationStats [] = Left "populationStats: empty input"
populationStats values = do
  traverse_ (requireFinite "statistics input") values
  let count = fromIntegral (length values)
      meanValue = sum values / count
      variance =
        sum (fmap (\value -> (value - meanValue) * (value - meanValue)) values)
          / count
      rawScale = sqrt variance
      scale = if rawScale > 1.0e-12 then rawScale else 1.0
  requireFinite "statistics mean" meanValue
  requireFinite "statistics variance" variance
  requireFinite "statistics scale" scale
  pure (meanValue, scale)

standardizeFinite
  :: Text.Text
  -> Double
  -> Double
  -> Double
  -> Either Text.Text Double
standardizeFinite label meanValue scale value = do
  requireFinite (label <> " mean") meanValue
  requireFinite (label <> " scale") scale
  requireFinite label value
  if scale <= 0.0
    then Left (label <> " scale must be positive")
    else do
      let standardized = (value - meanValue) / scale
      requireFinite (label <> " standardized value") standardized
      pure standardized

requireFinite :: Text.Text -> Double -> Either Text.Text ()
requireFinite label value
  | isNaN value || isInfinite value = Left (label <> " must be finite")
  | otherwise = Right ()

trainRegressorWithDevice
  :: MlpDevice
  -> RegressionConfig
  -> [RegressionExample]
  -> IO (Either Text.Text (TrainedRegressor, RegressionRunMetrics))
trainRegressorWithDevice device config dataset
  | null dataset = pure (Left "trainRegressorWithDevice: empty dataset")
  | regEpochs config <= 0 = pure (Left "trainRegressorWithDevice: epoch count must be positive")
  | regBatchSize config <= 0 = pure (Left "trainRegressorWithDevice: batch size must be positive")
  | regInputs config <= 0 = pure (Left "trainRegressorWithDevice: input width must be positive")
  | regHidden config <= 0 = pure (Left "trainRegressorWithDevice: hidden width must be positive")
  | isNaN (regLearningRate config)
      || isInfinite (regLearningRate config)
      || regLearningRate config <= 0.0 =
      pure (Left "trainRegressorWithDevice: learning rate must be finite and positive")
  | otherwise = do
      let shape =
            MlpShape
              { mlpInputs = regInputs config
              , mlpHidden = regHidden config
              , mlpOutputs = 1
              }
          params0 = mlpInit shape (regSeed config)
          adam0 = adamInit shape
          adamConfig = defaultAdamConfig {adamLearningRate = regLearningRate config}
          stepBatch (params, adam, updatesExecuted) batch =
            case checkedRegressionOptimizerUpdate updatesExecuted of
              Left err -> pure (Left err)
              Right nextUpdatesExecuted -> do
                let inputs = fmap regressionFeatures batch
                    targets = fmap regressionTarget batch
                    batchN = length batch
                fwdE <- mlpdForwardBatch device params inputs
                case fwdE of
                  Left err -> pure (Left err)
                  Right outputs
                    | length outputs /= batchN ->
                        pure (Left "trainRegressorWithDevice: output count mismatch")
                    | any VU.null outputs ->
                        pure (Left "trainRegressorWithDevice: empty output vector")
                    | otherwise -> do
                        let dys = zipWith regressionOutputGradient outputs targets
                        gradE <- mlpdBatchGradient device params (zip inputs dys)
                        case gradE of
                          Left err -> pure (Left err)
                          Right summedGrad ->
                            let meanGrad = scaleMlpGradient (1.0 / fromIntegral batchN) summedGrad
                                (updatedParams, updatedAdam) =
                                  adamStep adamConfig adam params meanGrad
                             in pure
                                  ( Right
                                      ( updatedParams
                                      , updatedAdam
                                      , nextUpdatesExecuted
                                      )
                                  )
          stepEpoch state =
            foldM
              ( \acc batch -> case acc of
                  Left err -> pure (Left err)
                  Right current -> stepBatch current batch
              )
              (Right state)
              (nonEmptyChunks (regBatchSize config) dataset)
          runEpoch acc _epoch = case acc of
            Left err -> pure (Left err)
            Right state -> stepEpoch state
      trainedE <- foldM runEpoch (Right (params0, adam0, 0)) [1 .. regEpochs config]
      case trainedE of
        Left err -> pure (Left err)
        Right (finalParams, _, updatesExecuted) -> do
          let trained =
                TrainedRegressor
                  { trainedRegressorParams = finalParams
                  , trainedRegressorConfig = config
                  }
          mseE <- meanSquaredErrorWithDevice device trained dataset
          pure $
            fmap
              ( \mse ->
                  ( trained
                  , RegressionRunMetrics
                      { regressionTrainMse = mse
                      , regressionOptimizerUpdatesExecuted = updatesExecuted
                      }
                  )
              )
              mseE

checkedRegressionOptimizerUpdate :: Word64 -> Either Text.Text Word64
checkedRegressionOptimizerUpdate updatesExecuted
  | updatesExecuted == maxBound =
      Left "trainRegressorWithDevice: optimizer-update count exceeds the Word64 range"
  | otherwise = Right (updatesExecuted + 1)

nonEmptyChunks :: Int -> [a] -> [[a]]
nonEmptyChunks size values =
  case splitAt size values of
    ([], _) -> []
    (chunk, rest) -> chunk : nonEmptyChunks size rest

predictRegressorWithDevice
  :: MlpDevice -> TrainedRegressor -> Vector Double -> IO (Either Text.Text Double)
predictRegressorWithDevice device trained features = do
  outE <- mlpdForwardBatch device (trainedRegressorParams trained) [features]
  pure $ case outE of
    Left err -> Left err
    Right (outputVec : _) ->
      case outputVec VU.!? 0 of
        Just value -> Right value
        Nothing -> Left "predictRegressorWithDevice: empty output vector"
    Right [] -> Left "predictRegressorWithDevice: device returned no output"

meanSquaredErrorWithDevice
  :: MlpDevice -> TrainedRegressor -> [RegressionExample] -> IO (Either Text.Text Double)
meanSquaredErrorWithDevice _ _ [] = pure (Left "meanSquaredErrorWithDevice: empty evaluation dataset")
meanSquaredErrorWithDevice device trained dataset = do
  outE <- mlpdForwardBatch device (trainedRegressorParams trained) (fmap regressionFeatures dataset)
  pure $ do
    outputs <- outE
    if length outputs /= length dataset
      then Left "meanSquaredErrorWithDevice: output count mismatch"
      else do
        predictions <-
          traverse
            ( \outputVec ->
                maybe
                  (Left "meanSquaredErrorWithDevice: empty output vector")
                  Right
                  (outputVec VU.!? 0)
            )
            outputs
        let squared =
              zipWith
                ( \prediction example ->
                    let err = prediction - regressionTarget example
                     in err * err
                )
                predictions
                dataset
        Right (sum squared / fromIntegral (length squared))

regressionOutputGradient :: Vector Double -> Double -> Vector Double
regressionOutputGradient outputVec target =
  VU.singleton (VU.head outputVec - target)

scaleMlpGradient :: Double -> MlpGradient -> MlpGradient
scaleMlpGradient s grad =
  MlpGradient
    { gradW1 = VU.map (* s) (gradW1 grad)
    , gradB1 = VU.map (* s) (gradB1 grad)
    , gradW2 = VU.map (* s) (gradW2 grad)
    , gradB2 = VU.map (* s) (gradB2 grad)
    }

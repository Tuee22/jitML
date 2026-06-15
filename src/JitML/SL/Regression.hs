{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Regression
  ( RegressionExample (..)
  , RegressionConfig (..)
  , TrainedRegressor (..)
  , defaultRegressionConfig
  , parseCaliforniaHousingData
  , decodeCaliforniaHousingBoundedData
  , decodeCaliforniaHousingArchiveBoundedData
  , standardizeRegressionExamples
  , trainRegressorWithDevice
  , predictRegressorWithDevice
  , meanSquaredErrorWithDevice
  )
where

import Control.Monad (foldM)
import Data.ByteString (ByteString)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
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
  , regLearningRate :: !Double
  }
  deriving stock (Eq, Show)

defaultRegressionConfig :: RegressionConfig
defaultRegressionConfig =
  RegressionConfig
    { regSeed = 42
    , regInputs = 8
    , regHidden = 32
    , regEpochs = 100
    , regLearningRate = 1.0e-3
    }

data TrainedRegressor = TrainedRegressor
  { trainedRegressorParams :: !MlpParams
  , trainedRegressorConfig :: !RegressionConfig
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
  let dataset = case subsetLimit of
        Just limit | limit >= 0 -> take limit parsed
        _ -> parsed
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

-- | Standardize each feature column and the target to zero mean / unit
-- variance. California Housing ships raw coordinates, population counts, and
-- dollar targets; training directly on those scales makes the MSE device path
-- numerically brittle and obscures whether the regression model is learning.
standardizeRegressionExamples :: [RegressionExample] -> [RegressionExample]
standardizeRegressionExamples [] = []
standardizeRegressionExamples dataset@(firstExample : _) =
  fmap standardizeOne dataset
 where
  featureCount = VU.length (regressionFeatures firstExample)
  featureStats =
    [ stats [regressionFeatures example VU.! column | example <- dataset]
    | column <- [0 .. featureCount - 1]
    ]
  targetStats = stats (fmap regressionTarget dataset)
  standardizeOne example =
    RegressionExample
      { regressionFeatures =
          VU.imap
            ( \column value ->
                case drop column featureStats of
                  ((meanValue, stdValue) : _) -> standardizeValue meanValue stdValue value
                  [] -> value
            )
            (regressionFeatures example)
      , regressionTarget =
          let (targetMean, targetStd) = targetStats
           in standardizeValue targetMean targetStd (regressionTarget example)
      }

  stats values =
    let n = max 1 (length values)
        meanValue = sum values / fromIntegral n
        variance = sum (fmap (\value -> (value - meanValue) * (value - meanValue)) values) / fromIntegral n
        stdValue = sqrt variance
     in (meanValue, stdValue)

  standardizeValue meanValue stdValue value =
    (value - meanValue) / if stdValue > 1.0e-12 then stdValue else 1.0

trainRegressorWithDevice
  :: MlpDevice
  -> RegressionConfig
  -> [RegressionExample]
  -> IO (Either Text.Text (TrainedRegressor, Double))
trainRegressorWithDevice device config dataset
  | null dataset = pure (Left "trainRegressorWithDevice: empty dataset")
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
          inputs = fmap regressionFeatures dataset
          targets = fmap regressionTarget dataset
          batchN = length dataset
          stepEpoch (params, adam) = do
            fwdE <- mlpdForwardBatch device params inputs
            case fwdE of
              Left err -> pure (Left err)
              Right outputs -> do
                let dys = zipWith regressionOutputGradient outputs targets
                gradE <- mlpdBatchGradient device params (zip inputs dys)
                case gradE of
                  Left err -> pure (Left err)
                  Right summedGrad ->
                    let meanGrad = scaleMlpGradient (1.0 / fromIntegral batchN) summedGrad
                     in pure (Right (adamStep adamConfig adam params meanGrad))
          runEpoch acc _epoch = case acc of
            Left err -> pure (Left err)
            Right state -> stepEpoch state
      trainedE <- foldM runEpoch (Right (params0, adam0)) [1 .. max 1 (regEpochs config)]
      case trainedE of
        Left err -> pure (Left err)
        Right (finalParams, _) -> do
          let trained =
                TrainedRegressor
                  { trainedRegressorParams = finalParams
                  , trainedRegressorConfig = config
                  }
          mseE <- meanSquaredErrorWithDevice device trained dataset
          pure (fmap (trained,) mseE)

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
meanSquaredErrorWithDevice _ _ [] = pure (Right 0.0)
meanSquaredErrorWithDevice device trained dataset = do
  outE <- mlpdForwardBatch device (trainedRegressorParams trained) (fmap regressionFeatures dataset)
  pure $ do
    outputs <- outE
    if length outputs /= length dataset
      then Left "meanSquaredErrorWithDevice: output count mismatch"
      else
        let squared =
              zipWith
                ( \outputVec example ->
                    let prediction = VU.head outputVec
                        err = prediction - regressionTarget example
                     in err * err
                )
                outputs
                dataset
         in Right (sum squared / fromIntegral (length squared))

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

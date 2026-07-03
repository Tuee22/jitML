{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Training.Budget
  ( BudgetKind (..)
  , CompletedTraining
  , ConvergenceObservation (..)
  , MetricGoal (..)
  , TensorBoardRunMetadata (..)
  , TrainingBudget (..)
  , completedTrainingBudget
  , completedTrainingDatasetShaAtRead
  , completedTrainingEvidence
  , completedTrainingFinalWeightHash
  , completedTrainingInitialWeightHash
  , completedTrainingMetrics
  , completedTrainingObservedUnits
  , completedTrainingTensorBoard
  , completedTrainingUpdateCount
  , completedTraining
  , convergencePassed
  , decodeCompletedTraining
  , encodeCompletedTraining
  , parseCompletedTraining
  , renderBudgetKind
  , renderCompletedTraining
  , renderTrainingBudget
  , trainingBudgetKind
  , trainingBudgetTargetUnits
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt, intToDigit, isHexDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Generics (Generic)

import JitML.Product.Evidence
  ( TrainingEvidence
  , evidenceDatasetShaAtRead
  , evidenceFinalWeightHash
  , evidenceInitialWeightHash
  , evidenceUpdateCount
  )

data BudgetKind
  = SupervisedEpochBudget
  | RlEnvironmentStepBudget
  | AlphaZeroSelfPlayBudget
  | TuningTrialBudget
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data TrainingBudget
  = TrainingBudget
  { tbKind :: BudgetKind
  , tbTargetUnits :: Word64
  , tbUnitLabel :: Text
  , tbSeed :: Maybe Word64
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data MetricGoal
  = MetricMaximise
  | MetricMinimise
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data ConvergenceObservation = ConvergenceObservation
  { coMetricName :: Text
  , coMetricValue :: Double
  , coMetricGoal :: MetricGoal
  , coThreshold :: Maybe Double
  , coPassed :: Bool
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data TensorBoardRunMetadata = TensorBoardRunMetadata
  { tbrRunId :: Text
  , tbrLogPrefix :: Text
  , tbrScalarTags :: [Text]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data CompletedTraining = CompletedTraining
  { completedTrainingBudget :: TrainingBudget
  , completedTrainingObservedUnits :: Word64
  , completedTrainingEvidence :: TrainingEvidence
  , completedTrainingMetrics :: [ConvergenceObservation]
  , completedTrainingTensorBoard :: TensorBoardRunMetadata
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

trainingBudgetKind :: TrainingBudget -> BudgetKind
trainingBudgetKind = tbKind

trainingBudgetTargetUnits :: TrainingBudget -> Word64
trainingBudgetTargetUnits = tbTargetUnits

renderBudgetKind :: BudgetKind -> Text
renderBudgetKind kind =
  case kind of
    SupervisedEpochBudget -> "supervised-epochs"
    RlEnvironmentStepBudget -> "rl-environment-steps"
    AlphaZeroSelfPlayBudget -> "alphazero-self-play-generations"
    TuningTrialBudget -> "tuning-trials"

renderTrainingBudget :: TrainingBudget -> Text
renderTrainingBudget budget =
  Text.intercalate
    ":"
    [ renderBudgetKind (tbKind budget)
    , Text.pack (show (tbTargetUnits budget))
    , tbUnitLabel budget
    , maybe "seedless" (("seed-" <>) . Text.pack . show) (tbSeed budget)
    ]

convergencePassed :: ConvergenceObservation -> Bool
convergencePassed = coPassed

completedTrainingInitialWeightHash :: CompletedTraining -> Text
completedTrainingInitialWeightHash =
  evidenceInitialWeightHash . completedTrainingEvidence

completedTrainingFinalWeightHash :: CompletedTraining -> Text
completedTrainingFinalWeightHash =
  evidenceFinalWeightHash . completedTrainingEvidence

completedTrainingUpdateCount :: CompletedTraining -> Word64
completedTrainingUpdateCount =
  evidenceUpdateCount . completedTrainingEvidence

completedTrainingDatasetShaAtRead :: CompletedTraining -> Text
completedTrainingDatasetShaAtRead =
  evidenceDatasetShaAtRead . completedTrainingEvidence

completedTraining
  :: TrainingBudget
  -> Word64
  -> TrainingEvidence
  -> [ConvergenceObservation]
  -> TensorBoardRunMetadata
  -> Either Text CompletedTraining
completedTraining budget observedUnits evidence observations tensorBoard
  | tbTargetUnits budget == 0 =
      Left "training budget must have a positive target"
  | observedUnits < tbTargetUnits budget =
      Left
        ( "training budget incomplete: observed "
            <> Text.pack (show observedUnits)
            <> " "
            <> tbUnitLabel budget
            <> " of "
            <> Text.pack (show (tbTargetUnits budget))
        )
  | null observations =
      Left "completed training requires at least one convergence observation"
  | otherwise =
      case filter (not . convergencePassed) observations of
        [] ->
          Right
            CompletedTraining
              { completedTrainingBudget = budget
              , completedTrainingObservedUnits = observedUnits
              , completedTrainingEvidence = evidence
              , completedTrainingMetrics = observations
              , completedTrainingTensorBoard = tensorBoard
              }
        failed ->
          Left
            ( "convergence metric failed: "
                <> Text.intercalate "," (fmap coMetricName failed)
            )

encodeCompletedTraining :: CompletedTraining -> ByteString
encodeCompletedTraining =
  LazyByteString.toStrict . serialise

decodeCompletedTraining :: ByteString -> Either Text CompletedTraining
decodeCompletedTraining bytes =
  case deserialiseOrFail (LazyByteString.fromStrict bytes) of
    Right completed -> Right completed
    Left err -> Left ("invalid completed-training witness: " <> Text.pack (show err))

renderCompletedTraining :: CompletedTraining -> Text
renderCompletedTraining =
  hexBytes . encodeCompletedTraining

parseCompletedTraining :: Text -> Maybe CompletedTraining
parseCompletedTraining encoded = do
  bytes <- unhexBytes encoded
  case decodeCompletedTraining bytes of
    Right completed -> Just completed
    Left _ -> Nothing

hexBytes :: ByteString -> Text
hexBytes =
  Text.pack . concatMap hexByte . ByteString.unpack
 where
  hexByte byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

unhexBytes :: Text -> Maybe ByteString
unhexBytes text =
  let chars = Text.unpack (Text.strip text)
   in if even (length chars) && all isHexDigit chars
        then ByteString.pack <$> bytesFromHex chars
        else Nothing
 where
  bytesFromHex [] = Just []
  bytesFromHex (hi : lo : rest) =
    (fromIntegral (digitToInt hi * 16 + digitToInt lo) :)
      <$> bytesFromHex rest
  bytesFromHex _ = Nothing

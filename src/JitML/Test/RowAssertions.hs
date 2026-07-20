{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.RowAssertions
  ( AlphaZeroRowEvidence (..)
  , LearnedStateEvidence (..)
  , SupervisedRowEvidence (..)
  , RlRowEvidence (..)
  , assertAlphaZeroRowEvidence
  , assertLearnedStateChanged
  , assertRealLoss
  , assertRlRowEvidence
  , assertSupervisedRowEvidence
  , evidencePassesConvergence
  , paramHash
  , rlEvidencePassesConvergence
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Training.Budget
  ( CompletedTraining
  , MetricGoal (..)
  , completedTrainingFinalWeightHash
  , completedTrainingInitialWeightHash
  , completedTrainingMetrics
  , completedTrainingObservedUnits
  , completedTrainingUpdateCount
  , convergencePassed
  )

data SupervisedRowEvidence = SupervisedRowEvidence
  { sreRowId :: !Text
  , sreInitialWeightHash :: !Text
  , sreFinalWeightHash :: !Text
  , sreUpdateCount :: !Word64
  , sreTrainExamples :: !Int
  , sreValidationExamples :: !Int
  , sreTestExamples :: !Int
  , sreExamplesSeen :: !Word64
  , sreThroughputExamples :: !Double
  , sreTrainLoss :: !Double
  , sreValidationLoss :: !Double
  , sreTestMetricName :: !Text
  , sreTestMetricGoal :: !MetricGoal
  , sreTestMetricValue :: !Double
  , sreConvergenceThreshold :: !Double
  , sreConvergenceSlack :: !Double
  , sreGradientNorm :: !Double
  , sreSmokeThreshold :: !Bool
  }
  deriving stock (Eq, Show)

data RlRowEvidence = RlRowEvidence
  { rleRowId :: !Text
  , rleAlgorithm :: !Text
  , rleEnvironment :: !Text
  , rleInitialPolicyHash :: !Text
  , rleFinalPolicyHash :: !Text
  , rleUpdateCount :: !Word64
  , rleObservedUnits :: !Word64
  , rleDeviceEvidence :: !Text
  , rleMetricName :: !Text
  , rleMetricGoal :: !MetricGoal
  , rleMetricValue :: !Double
  , rleConvergenceThreshold :: !Double
  , rleConvergenceSlack :: !Double
  , rleSyntheticTransitionEvidence :: !Bool
  }
  deriving stock (Eq, Show)

data AlphaZeroRowEvidence = AlphaZeroRowEvidence
  { azreRowId :: !Text
  , azreGame :: !Text
  , azreInitialNetworkHash :: !Text
  , azreFinalNetworkHash :: !Text
  , azreGenerationCount :: !Word64
  , azreArenaWinRate :: !Double
  , azreArenaThreshold :: !Double
  , azreConvergenceSlack :: !Double
  , azreCheckpointManifestSha :: !Text
  , azreCompletedTraining :: !(Maybe CompletedTraining)
  }
  deriving stock (Eq, Show)

-- AlphaZero completion is admitted from the opaque 'CompletedTraining'
-- witness plus the persisted checkpoint manifest identity below.  Registry
-- declaration handles are intentionally absent: a freely copied text label is
-- not execution evidence.

data LearnedStateEvidence = LearnedStateEvidence
  { lseRowId :: !Text
  , lseInitialParamHash :: !Text
  , lseFinalParamHash :: !Text
  , lseUpdateCount :: !Word64
  }
  deriving stock (Eq, Show)

paramHash :: [Double] -> Text
paramHash =
  hexBytes . SHA256.hash . LazyByteString.toStrict . Checkpoint.encodeJmw1

assertLearnedStateChanged :: LearnedStateEvidence -> [Text]
assertLearnedStateChanged evidence =
  concat
    [ requiredText "row id" lseRowId
    , requiredText "initial parameter hash" lseInitialParamHash
    , requiredText "final parameter hash" lseFinalParamHash
    , [ "final parameter hash equals initial parameter hash for row " <> lseRowId evidence
      | lseInitialParamHash evidence == lseFinalParamHash evidence
      ]
    , [ "update count must be positive for row " <> lseRowId evidence
      | lseUpdateCount evidence == 0
      ]
    ]
 where
  requiredText label selector =
    [ label <> " is required"
    | Text.null (Text.strip (selector evidence))
    ]

assertRealLoss :: Text -> [Double] -> [Text]
assertRealLoss rowId losses =
  case losses of
    [] -> ["loss trajectory is required for row " <> rowId]
    [_] -> ["loss trajectory needs at least two observations for row " <> rowId]
    initialLoss : _ ->
      let finalLoss = last losses
       in [ "loss trajectory contains a non-finite value for row " <> rowId
          | not (all finiteDouble losses)
          ]
            <> [ "loss trajectory contains a negative value for row " <> rowId
               | any (< 0.0) losses
               ]
            <> [ "loss trajectory does not decrease for row " <> rowId
               | finalLoss >= initialLoss
               ]
            <> [ "loss trajectory is constant for row " <> rowId
               | all (== initialLoss) losses
               ]

assertAlphaZeroRowEvidence :: AlphaZeroRowEvidence -> [Text]
assertAlphaZeroRowEvidence evidence =
  concat
    [ requiredText "row id" azreRowId
    , requiredText "game" azreGame
    , requiredText "initial network hash" azreInitialNetworkHash
    , requiredText "final network hash" azreFinalNetworkHash
    , [ "final network hash equals initial network hash"
      | azreInitialNetworkHash evidence == azreFinalNetworkHash evidence
      ]
    , positiveWord "generation count" azreGenerationCount
    , finiteMetric "arena win rate" azreArenaWinRate
    , finiteMetric "arena threshold" azreArenaThreshold
    , finiteNonNegative "arena convergence slack" azreConvergenceSlack
    , [ "arena win rate failed convergence: observed "
          <> showText (azreArenaWinRate evidence)
          <> " against "
          <> showText (azreArenaThreshold evidence)
          <> " +/- "
          <> showText (azreConvergenceSlack evidence)
      | not (alphaZeroEvidencePassesConvergence evidence)
      ]
    , requiredText "checkpoint manifest sha" azreCheckpointManifestSha
    , completedTrainingFailures
    ]
 where
  requiredText label selector =
    [ label <> " is required"
    | Text.null (Text.strip (selector evidence))
    ]
  positiveWord label selector =
    [ label <> " must be positive"
    | selector evidence == 0
    ]
  finiteMetric label selector =
    [ label <> " must be finite"
    | not (finiteDouble (selector evidence))
    ]
  finiteNonNegative label selector =
    [ label <> " must be finite and non-negative"
    | let value = selector evidence
    , not (finiteDouble value) || value < 0.0
    ]
  completedTrainingFailures =
    case azreCompletedTraining evidence of
      Nothing -> ["completed-training witness is required"]
      Just completed ->
        [ "completed-training initial hash mismatch"
        | completedTrainingInitialWeightHash completed /= azreInitialNetworkHash evidence
        ]
          <> [ "completed-training final hash mismatch"
             | completedTrainingFinalWeightHash completed /= azreFinalNetworkHash evidence
             ]
          <> [ "completed-training update count mismatch"
             | completedTrainingUpdateCount completed /= azreGenerationCount evidence
             ]
          <> [ "completed-training observed units are below generation count"
             | completedTrainingObservedUnits completed < azreGenerationCount evidence
             ]
          <> [ "completed-training witness has no convergence metrics"
             | null (completedTrainingMetrics completed)
             ]
          <> [ "completed-training witness has failed convergence metrics"
             | not (all convergencePassed (completedTrainingMetrics completed))
             ]

alphaZeroEvidencePassesConvergence :: AlphaZeroRowEvidence -> Bool
alphaZeroEvidencePassesConvergence evidence =
  azreArenaWinRate evidence >= azreArenaThreshold evidence - azreConvergenceSlack evidence

assertRlRowEvidence :: RlRowEvidence -> [Text]
assertRlRowEvidence evidence =
  concat
    [ requiredText "row id" rleRowId
    , requiredText "algorithm" rleAlgorithm
    , requiredText "environment" rleEnvironment
    , requiredText "initial policy/Q hash" rleInitialPolicyHash
    , requiredText "final policy/Q hash" rleFinalPolicyHash
    , [ "final policy/Q hash equals initial policy/Q hash"
      | rleInitialPolicyHash evidence == rleFinalPolicyHash evidence
      ]
    , positiveWord "update count" rleUpdateCount
    , positiveWord "observed units" rleObservedUnits
    , requiredText "device evidence" rleDeviceEvidence
    , requiredText "metric name" rleMetricName
    , finiteMetric "metric value" rleMetricValue
    , finiteMetric "convergence threshold" rleConvergenceThreshold
    , finiteNonNegative "convergence slack" rleConvergenceSlack
    , [ "synthetic-transition evidence is not valid product evidence"
      | rleSyntheticTransitionEvidence evidence
      ]
    , [ convergenceFailure
      | not (rlEvidencePassesConvergence evidence)
      ]
    ]
 where
  requiredText label selector =
    [ label <> " is required"
    | Text.null (Text.strip (selector evidence))
    ]
  positiveWord label selector =
    [ label <> " must be positive"
    | selector evidence == 0
    ]
  finiteMetric label selector =
    [ label <> " must be finite"
    | not (finiteDouble (selector evidence))
    ]
  finiteNonNegative label selector =
    [ label <> " must be finite and non-negative"
    | let value = selector evidence
    , not (finiteDouble value) || value < 0.0
    ]
  convergenceFailure =
    rleMetricName evidence
      <> " failed convergence: observed "
      <> showText (rleMetricValue evidence)
      <> " against "
      <> showText (rleConvergenceThreshold evidence)
      <> " +/- "
      <> showText (rleConvergenceSlack evidence)

assertSupervisedRowEvidence :: SupervisedRowEvidence -> [Text]
assertSupervisedRowEvidence evidence =
  concat
    [ requiredText "row id" sreRowId
    , requiredText "initial weight hash" sreInitialWeightHash
    , requiredText "final weight hash" sreFinalWeightHash
    , [ "final weight hash equals initial weight hash"
      | sreInitialWeightHash evidence == sreFinalWeightHash evidence
      ]
    , positiveWord "update count" sreUpdateCount
    , positiveInt "train examples" sreTrainExamples
    , positiveInt "validation examples" sreValidationExamples
    , positiveInt "test examples" sreTestExamples
    , positiveWord "examples seen" sreExamplesSeen
    , [ "examples seen is below train examples"
      | sreExamplesSeen evidence < fromIntegral (max 0 (sreTrainExamples evidence))
      ]
    , positiveFinite "throughput examples" sreThroughputExamples
    , finiteNonNegative "train loss" sreTrainLoss
    , finiteNonNegative "validation loss" sreValidationLoss
    , requiredText "test metric name" sreTestMetricName
    , finiteMetric "test metric value" sreTestMetricValue
    , finiteMetric "convergence threshold" sreConvergenceThreshold
    , finiteNonNegative "convergence slack" sreConvergenceSlack
    , positiveFinite "gradient norm" sreGradientNorm
    , [ "uses a smoke threshold rather than a literature/slack bar"
      | sreSmokeThreshold evidence
      ]
    , [ convergenceFailure
      | not (evidencePassesConvergence evidence)
      ]
    ]
 where
  requiredText label selector =
    [ label <> " is required"
    | Text.null (Text.strip (selector evidence))
    ]
  positiveWord label selector =
    [ label <> " must be positive"
    | selector evidence == 0
    ]
  positiveInt label selector =
    [ label <> " must be positive"
    | selector evidence <= 0
    ]
  positiveFinite label selector =
    [ label <> " must be finite and positive"
    | let value = selector evidence
    , not (finiteDouble value) || value <= 0.0
    ]
  finiteNonNegative label selector =
    [ label <> " must be finite and non-negative"
    | let value = selector evidence
    , not (finiteDouble value) || value < 0.0
    ]
  finiteMetric label selector =
    [ label <> " must be finite"
    | not (finiteDouble (selector evidence))
    ]
  convergenceFailure =
    sreTestMetricName evidence
      <> " failed convergence: observed "
      <> showText (sreTestMetricValue evidence)
      <> " against "
      <> showText (sreConvergenceThreshold evidence)
      <> " +/- "
      <> showText (sreConvergenceSlack evidence)

evidencePassesConvergence :: SupervisedRowEvidence -> Bool
evidencePassesConvergence evidence =
  case sreTestMetricGoal evidence of
    MetricMaximise ->
      sreTestMetricValue evidence
        >= sreConvergenceThreshold evidence - sreConvergenceSlack evidence
    MetricMinimise ->
      sreTestMetricValue evidence
        <= sreConvergenceThreshold evidence + sreConvergenceSlack evidence

rlEvidencePassesConvergence :: RlRowEvidence -> Bool
rlEvidencePassesConvergence evidence =
  case rleMetricGoal evidence of
    MetricMaximise ->
      rleMetricValue evidence
        >= rleConvergenceThreshold evidence - rleConvergenceSlack evidence
    MetricMinimise ->
      rleMetricValue evidence
        <= rleConvergenceThreshold evidence + rleConvergenceSlack evidence

finiteDouble :: Double -> Bool
finiteDouble value =
  not (isNaN value) && not (isInfinite value)

showText :: (Show a) => a -> Text
showText = Text.pack . show

hexBytes :: ByteString.ByteString -> Text
hexBytes =
  Text.Encoding.decodeUtf8 . ByteString.concatMap hexByte

hexByte :: Word8 -> ByteString.ByteString
hexByte byte =
  Text.Encoding.encodeUtf8 $
    Text.pack
      [ hexDigit (fromIntegral byte `div` 16)
      , hexDigit (fromIntegral byte `mod` 16)
      ]

hexDigit :: Int -> Char
hexDigit value
  | value < 10 = toEnum (fromEnum '0' + value)
  | otherwise = toEnum (fromEnum 'a' + value - 10)

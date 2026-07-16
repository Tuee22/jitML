{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Fixed-budget completion evidence.
--
-- The proof-bearing values in this module deliberately have no exported
-- constructors and no generic wire representation.  Bytes decode into the
-- versioned @Raw*@ DTOs first; refinement then rechecks finite measurements,
-- criterion predicates, budget identity, exact budget exhaustion, and training
-- evidence before a 'CompletedTraining' value can exist.
module JitML.Training.Budget
  ( BudgetKind (..)
  , CompletedTraining
  , ConvergenceObservation
  , FiniteMeasurement
  , MetricGoal (..)
  , MetricCriterion
  , PassedMeasurement
  , RawCompletedTraining (..)
  , RawConvergenceObservation (..)
  , RawCriterionRule (..)
  , RawTrainingBudget (..)
  , TensorBoardRunMetadata (..)
  , TrainingBudget
  , coMetricGoal
  , coMetricName
  , coMetricValue
  , coThreshold
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
  , completedTrainingWireVersion
  , convergenceObservationToRaw
  , convergencePassed
  , decodeCompletedTraining
  , encodeCompletedTraining
  , encodeRawCompletedTraining
  , measureCriterion
  , measureCriterionExcluding
  , mkTrainingBudget
  , parseCompletedTraining
  , refineCompletedTraining
  , refineConvergenceObservation
  , remeasureCriterion
  , renderBudgetKind
  , renderCompletedTraining
  , renderTrainingBudget
  , sameConvergenceCriterion
  , trainingBudgetKind
  , trainingBudgetSeed
  , trainingBudgetTargetUnits
  , trainingBudgetToRaw
  , trainingBudgetUnitLabel
  , refineTrainingBudget
  , tbKind
  , tbSeed
  , tbTargetUnits
  , tbUnitLabel
  )
where

import Codec.Serialise (Serialise (..), deserialiseOrFail, serialise)
import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt, intToDigit, isHexDigit)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Generics (Generic)

import JitML.Plan.Plan
  ( PlanId
  , planIdText
  , refinePlanIdText
  )
import JitML.Product.Evidence
  ( TrainingEvidence
  , evidenceDatasetShaAtRead
  , evidenceFinalWeightHash
  , evidenceInitialWeightHash
  , evidenceUpdateCount
  , mkTrainingEvidence
  )

data BudgetKind
  = SupervisedEpochBudget
  | RlEnvironmentStepBudget
  | AlphaZeroSelfPlayBudget
  | TuningTrialBudget
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data TrainingBudget = TrainingBudget
  { tbKind :: !BudgetKind
  , tbTargetUnits :: !Word64
  , tbSeed :: !(Maybe Word64)
  }
  deriving stock (Eq, Ord, Show)

-- | The new wire form does not accept a producer-supplied unit string.  The
-- unit is indexed by 'BudgetKind' and rendered canonically at every boundary.
data RawTrainingBudget = RawTrainingBudget
  { rawTrainingBudgetKind :: !BudgetKind
  , rawTrainingBudgetTargetUnits :: !Word64
  , rawTrainingBudgetSeed :: !(Maybe Word64)
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data MetricGoal
  = MetricMaximise
  | MetricMinimise
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

-- | The comparison is part of the criterion rather than a redundant stored
-- goal/verdict pair.  The exclusion form models gates such as AlphaZero's
-- all-draw sentinel while retaining one derivable pass predicate.
data CriterionRule
  = CriterionAtLeast
  | CriterionAtMost
  | CriterionAtLeastExcluding !Double !Double
  deriving stock (Eq, Show)

data MetricCriterion = MetricCriterion
  { criterionMetricName :: !Text
  , criterionRule :: !CriterionRule
  , criterionThreshold :: !Double
  }
  deriving stock (Eq, Show)

newtype FiniteMeasurement = FiniteMeasurement
  { finiteMeasurementValue :: Double
  }
  deriving stock (Eq, Show)

-- | An evaluated criterion.  It may describe a failed measurement so error
-- reporting remains useful; it does not itself carry a stored verdict.
data ConvergenceObservation = ConvergenceObservation
  { observationCriterion :: !MetricCriterion
  , observationMeasurement :: !FiniteMeasurement
  }
  deriving stock (Eq, Show)

-- | A convergence observation whose predicate has been evaluated and passed.
-- The constructor is intentionally hidden and no 'Serialise' instance exists.
newtype PassedMeasurement = PassedMeasurement
  { passedObservation :: ConvergenceObservation
  }
  deriving stock (Eq, Show)

data TensorBoardRunMetadata = TensorBoardRunMetadata
  { tbrRunId :: Text
  , tbrLogPrefix :: Text
  , tbrScalarTags :: [Text]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data CompletedTraining = CompletedTraining
  { completedPlanIdProof :: !PlanId
  , completedBudgetProof :: !TrainingBudget
  , completedObservedUnitsProof :: !Word64
  , completedEvidenceProof :: !TrainingEvidence
  , completedMeasurementsProof :: !(NonEmpty PassedMeasurement)
  , completedTensorBoardProof :: !TensorBoardRunMetadata
  }
  deriving stock (Eq, Show)

-- | Forgeable wire tags are acceptable only in the raw DTO.  Refinement maps
-- them to the hidden 'CriterionRule' after checking all embedded doubles.
data RawCriterionRule
  = RawCriterionAtLeast
  | RawCriterionAtMost
  | RawCriterionAtLeastExcluding !Double !Double
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawConvergenceObservation = RawConvergenceObservation
  { rawCriterionName :: !Text
  , rawCriterionRule :: !RawCriterionRule
  , rawCriterionThreshold :: !Double
  , rawMeasurementValue :: !Double
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Versioned, deliberately forgeable completion DTO.  The observed budget
-- kind and unit are repeated so a decoder can detect a producer that counted a
-- different unit than the resolved plan.  No stored @passed@ bit exists.
data RawCompletedTraining = RawCompletedTraining
  { rawCompletedTrainingVersion :: !Word64
  , rawCompletedTrainingPlanId :: !Text
  , rawCompletedTrainingBudget :: !RawTrainingBudget
  , rawCompletedTrainingObservedKind :: !BudgetKind
  , rawCompletedTrainingObservedUnits :: !Word64
  , rawCompletedTrainingObservedUnitLabel :: !Text
  , rawCompletedTrainingEvidence :: !TrainingEvidence
  , rawCompletedTrainingMeasurements :: ![RawConvergenceObservation]
  , rawCompletedTrainingTensorBoard :: !TensorBoardRunMetadata
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

completedTrainingWireVersion :: Word64
completedTrainingWireVersion = 1

-- The only serialisation instance for the proof type goes through the raw DTO
-- and invokes the same refinement used by explicit protocol decoders.
instance Serialise CompletedTraining where
  encode = encode . completedTrainingToRaw
  decode = do
    raw <- decode
    case refineCompletedTraining raw of
      Left err -> fail (Text.unpack err)
      Right completed -> pure completed

trainingBudgetKind :: TrainingBudget -> BudgetKind
trainingBudgetKind = tbKind

trainingBudgetTargetUnits :: TrainingBudget -> Word64
trainingBudgetTargetUnits = tbTargetUnits

trainingBudgetSeed :: TrainingBudget -> Maybe Word64
trainingBudgetSeed = tbSeed

trainingBudgetUnitLabel :: TrainingBudget -> Text
trainingBudgetUnitLabel = canonicalBudgetUnit . tbKind

-- Compatibility accessor.  The label is derived, never stored.
tbUnitLabel :: TrainingBudget -> Text
tbUnitLabel = trainingBudgetUnitLabel

mkTrainingBudget
  :: BudgetKind -> Word64 -> Maybe Word64 -> Either Text TrainingBudget
mkTrainingBudget kind target seed
  | target == 0 = Left "training budget must have a positive target"
  | otherwise =
      Right
        TrainingBudget
          { tbKind = kind
          , tbTargetUnits = target
          , tbSeed = seed
          }

trainingBudgetToRaw :: TrainingBudget -> RawTrainingBudget
trainingBudgetToRaw budget =
  RawTrainingBudget
    { rawTrainingBudgetKind = tbKind budget
    , rawTrainingBudgetTargetUnits = tbTargetUnits budget
    , rawTrainingBudgetSeed = tbSeed budget
    }

refineTrainingBudget :: RawTrainingBudget -> Either Text TrainingBudget
refineTrainingBudget raw =
  mkTrainingBudget
    (rawTrainingBudgetKind raw)
    (rawTrainingBudgetTargetUnits raw)
    (rawTrainingBudgetSeed raw)

canonicalBudgetUnit :: BudgetKind -> Text
canonicalBudgetUnit kind =
  case kind of
    SupervisedEpochBudget -> "epochs"
    RlEnvironmentStepBudget -> "environment-steps"
    AlphaZeroSelfPlayBudget -> "self-play-generations"
    TuningTrialBudget -> "trials"

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
    , trainingBudgetUnitLabel budget
    , maybe "seedless" (("seed-" <>) . Text.pack . show) (tbSeed budget)
    ]

coMetricName :: ConvergenceObservation -> Text
coMetricName = criterionMetricName . observationCriterion

coMetricValue :: ConvergenceObservation -> Double
coMetricValue = finiteMeasurementValue . observationMeasurement

coMetricGoal :: ConvergenceObservation -> MetricGoal
coMetricGoal observation =
  case criterionRule (observationCriterion observation) of
    CriterionAtMost -> MetricMinimise
    CriterionAtLeast -> MetricMaximise
    CriterionAtLeastExcluding _ _ -> MetricMaximise

coThreshold :: ConvergenceObservation -> Double
coThreshold = criterionThreshold . observationCriterion

convergencePassed :: ConvergenceObservation -> Bool
convergencePassed observation =
  let value = coMetricValue observation
      criterion = observationCriterion observation
   in case criterionRule criterion of
        CriterionAtLeast -> value >= criterionThreshold criterion
        CriterionAtMost -> value <= criterionThreshold criterion
        CriterionAtLeastExcluding excluded tolerance ->
          value >= criterionThreshold criterion
            && abs (value - excluded) > tolerance

sameConvergenceCriterion :: ConvergenceObservation -> ConvergenceObservation -> Bool
sameConvergenceCriterion left right =
  observationCriterion left == observationCriterion right

measureCriterion
  :: Text
  -> MetricGoal
  -> Double
  -- ^ finite threshold
  -> Double
  -- ^ finite measured value
  -> Either Text ConvergenceObservation
measureCriterion name goal threshold value = do
  criterion <-
    mkMetricCriterion
      name
      (case goal of MetricMaximise -> CriterionAtLeast; MetricMinimise -> CriterionAtMost)
      threshold
  measurement <- mkFiniteMeasurement value
  pure (ConvergenceObservation criterion measurement)

measureCriterionExcluding
  :: Text
  -> MetricGoal
  -> Double
  -- ^ finite threshold
  -> Double
  -- ^ excluded value
  -> Double
  -- ^ exclusion tolerance (non-negative)
  -> Double
  -- ^ finite measured value
  -> Either Text ConvergenceObservation
measureCriterionExcluding name goal threshold excluded tolerance value = do
  when (goal /= MetricMaximise) $
    Left "criterion exclusions are supported only for maximised metrics"
  ensureFinite "criterion excluded value" excluded
  ensureFinite "criterion exclusion tolerance" tolerance
  when (tolerance < 0) $
    Left "criterion exclusion tolerance must be non-negative"
  criterion <-
    mkMetricCriterion
      name
      (CriterionAtLeastExcluding excluded tolerance)
      threshold
  measurement <- mkFiniteMeasurement value
  pure (ConvergenceObservation criterion measurement)

remeasureCriterion :: Double -> ConvergenceObservation -> Either Text ConvergenceObservation
remeasureCriterion value observation = do
  measurement <- mkFiniteMeasurement value
  pure observation {observationMeasurement = measurement}

mkMetricCriterion :: Text -> CriterionRule -> Double -> Either Text MetricCriterion
mkMetricCriterion name rule threshold = do
  when (Text.null (Text.strip name)) $
    Left "convergence criterion requires a metric name"
  ensureFinite "convergence criterion threshold" threshold
  case rule of
    CriterionAtLeast -> pure ()
    CriterionAtMost -> pure ()
    CriterionAtLeastExcluding excluded tolerance -> do
      ensureFinite "criterion excluded value" excluded
      ensureFinite "criterion exclusion tolerance" tolerance
      when (tolerance < 0) $
        Left "criterion exclusion tolerance must be non-negative"
  pure
    MetricCriterion
      { criterionMetricName = Text.strip name
      , criterionRule = rule
      , criterionThreshold = threshold
      }

mkFiniteMeasurement :: Double -> Either Text FiniteMeasurement
mkFiniteMeasurement value = do
  ensureFinite "convergence measurement" value
  pure (FiniteMeasurement value)

requirePassedMeasurement :: ConvergenceObservation -> Either Text PassedMeasurement
requirePassedMeasurement observation
  | convergencePassed observation = Right (PassedMeasurement observation)
  | otherwise = Left ("convergence metric failed: " <> coMetricName observation)

completedTrainingBudget :: CompletedTraining -> TrainingBudget
completedTrainingBudget = completedBudgetProof

completedTrainingPlanId :: CompletedTraining -> PlanId
completedTrainingPlanId = completedPlanIdProof

completedTrainingObservedUnits :: CompletedTraining -> Word64
completedTrainingObservedUnits = completedObservedUnitsProof

completedTrainingEvidence :: CompletedTraining -> TrainingEvidence
completedTrainingEvidence = completedEvidenceProof

completedTrainingMetrics :: CompletedTraining -> [ConvergenceObservation]
completedTrainingMetrics =
  fmap passedObservation . NonEmpty.toList . completedMeasurementsProof

completedTrainingTensorBoard :: CompletedTraining -> TensorBoardRunMetadata
completedTrainingTensorBoard = completedTensorBoardProof

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
  :: PlanId
  -> TrainingBudget
  -> Word64
  -> TrainingEvidence
  -> [ConvergenceObservation]
  -> TensorBoardRunMetadata
  -> Either Text CompletedTraining
completedTraining planId budget observedUnits evidence observations tensorBoard = do
  validateBudget budget (tbKind budget) observedUnits (tbUnitLabel budget)
  validatedEvidence <- revalidateEvidence evidence
  passed <- traverse requirePassedMeasurement observations
  nonEmptyPassed <-
    maybe
      (Left "completed training requires at least one measured criterion")
      Right
      (NonEmpty.nonEmpty passed)
  pure
    CompletedTraining
      { completedPlanIdProof = planId
      , completedBudgetProof = budget
      , completedObservedUnitsProof = observedUnits
      , completedEvidenceProof = validatedEvidence
      , completedMeasurementsProof = nonEmptyPassed
      , completedTensorBoardProof = tensorBoard
      }

completedTrainingToRaw :: CompletedTraining -> RawCompletedTraining
completedTrainingToRaw completed =
  let budget = completedTrainingBudget completed
   in RawCompletedTraining
        { rawCompletedTrainingVersion = completedTrainingWireVersion
        , rawCompletedTrainingPlanId = planIdText (completedTrainingPlanId completed)
        , rawCompletedTrainingBudget = trainingBudgetToRaw budget
        , rawCompletedTrainingObservedKind = tbKind budget
        , rawCompletedTrainingObservedUnits = completedTrainingObservedUnits completed
        , rawCompletedTrainingObservedUnitLabel = trainingBudgetUnitLabel budget
        , rawCompletedTrainingEvidence = completedTrainingEvidence completed
        , rawCompletedTrainingMeasurements =
            fmap convergenceObservationToRaw (completedTrainingMetrics completed)
        , rawCompletedTrainingTensorBoard = completedTrainingTensorBoard completed
        }

refineCompletedTraining :: RawCompletedTraining -> Either Text CompletedTraining
refineCompletedTraining raw = do
  when (rawCompletedTrainingVersion raw /= completedTrainingWireVersion) $
    Left
      ( "unsupported completed-training version: "
          <> Text.pack (show (rawCompletedTrainingVersion raw))
      )
  planId <- refineRawPlanId (rawCompletedTrainingPlanId raw)
  budget <- refineTrainingBudget (rawCompletedTrainingBudget raw)
  validateBudget
    budget
    (rawCompletedTrainingObservedKind raw)
    (rawCompletedTrainingObservedUnits raw)
    (rawCompletedTrainingObservedUnitLabel raw)
  observations <-
    traverse refineConvergenceObservation (rawCompletedTrainingMeasurements raw)
  completedTraining
    planId
    budget
    (rawCompletedTrainingObservedUnits raw)
    (rawCompletedTrainingEvidence raw)
    observations
    (rawCompletedTrainingTensorBoard raw)

refineRawPlanId :: Text -> Either Text PlanId
refineRawPlanId raw =
  case refinePlanIdText raw of
    Right planId -> Right planId
    Left err -> Left ("invalid completed-training plan-id: " <> err)

convergenceObservationToRaw :: ConvergenceObservation -> RawConvergenceObservation
convergenceObservationToRaw observation =
  RawConvergenceObservation
    { rawCriterionName = coMetricName observation
    , rawCriterionRule =
        case criterionRule (observationCriterion observation) of
          CriterionAtLeast -> RawCriterionAtLeast
          CriterionAtMost -> RawCriterionAtMost
          CriterionAtLeastExcluding excluded tolerance ->
            RawCriterionAtLeastExcluding excluded tolerance
    , rawCriterionThreshold = coThreshold observation
    , rawMeasurementValue = coMetricValue observation
    }

refineConvergenceObservation
  :: RawConvergenceObservation
  -> Either Text ConvergenceObservation
refineConvergenceObservation raw =
  case rawCriterionRule raw of
    RawCriterionAtLeast ->
      measureCriterion
        (rawCriterionName raw)
        MetricMaximise
        (rawCriterionThreshold raw)
        (rawMeasurementValue raw)
    RawCriterionAtMost ->
      measureCriterion
        (rawCriterionName raw)
        MetricMinimise
        (rawCriterionThreshold raw)
        (rawMeasurementValue raw)
    RawCriterionAtLeastExcluding excluded tolerance ->
      measureCriterionExcluding
        (rawCriterionName raw)
        MetricMaximise
        (rawCriterionThreshold raw)
        excluded
        tolerance
        (rawMeasurementValue raw)

validateBudget
  :: TrainingBudget
  -> BudgetKind
  -> Word64
  -> Text
  -> Either Text ()
validateBudget budget observedKind observedUnits observedUnit = do
  when (tbTargetUnits budget == 0) $
    Left "training budget must have a positive target"
  when (observedKind /= tbKind budget) $
    Left
      ( "training budget kind mismatch: plan "
          <> renderBudgetKind (tbKind budget)
          <> ", observed "
          <> renderBudgetKind observedKind
      )
  when (Text.strip observedUnit /= trainingBudgetUnitLabel budget) $
    Left
      ( "training budget unit mismatch: plan "
          <> trainingBudgetUnitLabel budget
          <> ", observed "
          <> observedUnit
      )
  when (observedUnits /= tbTargetUnits budget) $
    Left
      ( "training budget incomplete or overrun: observed "
          <> Text.pack (show observedUnits)
          <> " "
          <> trainingBudgetUnitLabel budget
          <> ", required exactly "
          <> Text.pack (show (tbTargetUnits budget))
      )

revalidateEvidence :: TrainingEvidence -> Either Text TrainingEvidence
revalidateEvidence evidence =
  mkTrainingEvidence
    (evidenceInitialWeightHash evidence)
    (evidenceFinalWeightHash evidence)
    (evidenceUpdateCount evidence)
    (evidenceDatasetShaAtRead evidence)

ensureFinite :: Text -> Double -> Either Text ()
ensureFinite label value
  | isNaN value || isInfinite value = Left (label <> " must be finite")
  | otherwise = Right ()

encodeCompletedTraining :: CompletedTraining -> ByteString
encodeCompletedTraining =
  LazyByteString.toStrict . serialise . completedTrainingToRaw

encodeRawCompletedTraining :: RawCompletedTraining -> ByteString
encodeRawCompletedTraining = LazyByteString.toStrict . serialise

decodeCompletedTraining :: ByteString -> Either Text CompletedTraining
decodeCompletedTraining bytes =
  case deserialiseOrFail (LazyByteString.fromStrict bytes) of
    Right raw -> refineCompletedTraining raw
    Left err -> Left ("invalid completed-training DTO: " <> Text.pack (show err))

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

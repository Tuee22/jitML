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
  , RawProductScenarioInvocation (..)
  , RawTrainingBudget (..)
  , ProductScenarioInvocation
  , TensorBoardRunMetadata (..)
  , TrainingBudget
  , coMetricGoal
  , coMetricName
  , coMetricValue
  , coThreshold
  , completedTraining
  , completedTrainingBudget
  , completedTrainingDatasetShaAtRead
  , completedTrainingDeviceWitness
  , completedTrainingEvidence
  , completedTrainingFinalWeightHash
  , completedTrainingInitialWeightHash
  , completedTrainingMetrics
  , completedTrainingObservedUnits
  , completedTrainingPlanId
  , completedTrainingProductScenarioInvocation
  , completedTrainingTensorBoard
  , completedTrainingToRaw
  , completedTrainingUpdateCount
  , completedTrainingWireVersion
  , convergenceObservationToRaw
  , convergencePassed
  , decodeCompletedTraining
  , encodeCompletedTraining
  , encodeRawCompletedTraining
  , bindCompletedTrainingToProductScenarioInvocation
  , measureCriterion
  , measureCriterionExcluding
  , mkTrainingBudget
  , mkProductScenarioInvocation
  , parseCompletedTraining
  , parseProductScenarioInvocation
  , productScenarioInvocationChallenge
  , productScenarioInvocationCheckpointScopeDigest
  , productScenarioInvocationDigest
  , productScenarioInvocationExecutableSha256
  , productScenarioInvocationPlanId
  , productScenarioInvocationRowId
  , productScenarioInvocationRunId
  , productScenarioInvocationSubstrate
  , renderProductScenarioInvocation
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
import Codec.Serialise.Decoding (Decoder, decodeListLen, decodeWord)
import Codec.Serialise.Encoding (Encoding, encodeListLen, encodeWord)
import Control.Monad (when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt, intToDigit, isControl, isHexDigit, ord)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import GHC.Generics (Generic)

import JitML.Plan.Plan
  ( PlanId
  , planIdText
  , refinePlanIdText
  )
import JitML.Product.DeviceWitness (DeviceExecutionWitness)
import JitML.Product.Evidence
  ( TrainingEvidence
  , attachDeviceExecutionWitness
  , evidenceDatasetShaAtRead
  , evidenceDeviceWitness
  , evidenceFinalWeightHash
  , evidenceInitialWeightHash
  , evidenceUpdateCount
  , mkTrainingEvidence
  )
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

data BudgetKind
  = SupervisedEpochBudget
  | RlEnvironmentStepBudget
  | AlphaZeroSelfPlayBudget
  | TuningTrialBudget
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

data TrainingBudget = TrainingBudget
  { budgetKindValue :: !BudgetKind
  , budgetTargetUnitsValue :: !Word64
  , budgetSeedValue :: !(Maybe Word64)
  }
  deriving stock (Eq, Ord, Show)

-- Backwards-compatible ordinary accessors.  These deliberately are not the
-- private record labels: exporting a selector would make a refined budget
-- forgeable through record update despite the hidden constructor.
tbKind :: TrainingBudget -> BudgetKind
tbKind = budgetKindValue

tbTargetUnits :: TrainingBudget -> Word64
tbTargetUnits = budgetTargetUnitsValue

tbSeed :: TrainingBudget -> Maybe Word64
tbSeed = budgetSeedValue

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

-- | One command-owned ProductScenario invocation.  The constructor is hidden:
-- callers must provide the exact row, plan, substrate, physical checkpoint
-- scope, executable identity, and a fresh 32-byte challenge in canonical
-- form.  Its single canonical rendering is safe to pass atomically across the
-- process environment and its digest is the journal's public correlation
-- identity.  The raw challenge is retained only in the content-addressed
-- completion, so a prior checkpoint cannot satisfy a later invocation.
data ProductScenarioInvocation = ProductScenarioInvocation
  { invocationRunIdProof :: !Text
  , invocationRowIdProof :: !Text
  , invocationPlanIdProof :: !PlanId
  , invocationSubstrateProof :: !Substrate
  , invocationCheckpointScopeDigestProof :: !Text
  , invocationExecutableSha256Proof :: !Text
  , invocationChallengeProof :: !Text
  }
  deriving stock (Eq)

instance Show ProductScenarioInvocation where
  show invocation =
    "ProductScenarioInvocation {runId = "
      <> show (productScenarioInvocationRunId invocation)
      <> ", rowId = "
      <> show (productScenarioInvocationRowId invocation)
      <> ", planId = "
      <> show (productScenarioInvocationPlanId invocation)
      <> ", substrate = "
      <> show (productScenarioInvocationSubstrate invocation)
      <> ", checkpointScopeDigest = "
      <> show (productScenarioInvocationCheckpointScopeDigest invocation)
      <> ", executableSha256 = "
      <> show (productScenarioInvocationExecutableSha256 invocation)
      <> ", invocationDigest = "
      <> show (productScenarioInvocationDigest invocation)
      <> "}"

-- | Forgeable wire counterpart.  Refinement validates every canonical field
-- before it can enter a 'CompletedTraining'.
data RawProductScenarioInvocation = RawProductScenarioInvocation
  { rawProductScenarioInvocationRunId :: !Text
  , rawProductScenarioInvocationRowId :: !Text
  , rawProductScenarioInvocationPlanId :: !Text
  , rawProductScenarioInvocationSubstrate :: !Text
  , rawProductScenarioInvocationCheckpointScopeDigest :: !Text
  , rawProductScenarioInvocationExecutableSha256 :: !Text
  , rawProductScenarioInvocationChallenge :: !Text
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data CompletedTraining = CompletedTraining
  { completedPlanIdProof :: !PlanId
  , completedBudgetProof :: !TrainingBudget
  , completedObservedUnitsProof :: !Word64
  , completedEvidenceProof :: !TrainingEvidence
  , completedMeasurementsProof :: !(NonEmpty PassedMeasurement)
  , completedTensorBoardProof :: !TensorBoardRunMetadata
  , completedProductScenarioInvocationProof :: !(Maybe ProductScenarioInvocation)
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
  , rawCompletedTrainingProductScenarioInvocation :: !(Maybe RawProductScenarioInvocation)
  }
  deriving stock (Eq, Generic, Show)

-- Keep the pre-Phase-261 nine-field V1 tuple readable without making it
-- eligible for a fresh ProductScenario invocation.  Generic @Serialise@
-- encodes a one-constructor product as @[constructor-tag, fields...]@, so the
-- historical value has list length 10 and V2 has list length 11.  Encoding a
-- decoded V1 raw value reproduces its exact old shape; newly refined domain
-- values are always projected as V2 by 'completedTrainingToRaw'.
instance Serialise RawCompletedTraining where
  encode raw =
    case (rawCompletedTrainingVersion raw, rawCompletedTrainingProductScenarioInvocation raw) of
      (1, Nothing) -> encodeRawCompletedTrainingFields 10 raw mempty
      _ ->
        encodeRawCompletedTrainingFields
          11
          raw
          (encode (rawCompletedTrainingProductScenarioInvocation raw))

  decode = do
    encodedLength <- decodeListLen
    constructorTag <- decodeWord
    when (constructorTag /= 0) $
      fail "unexpected RawCompletedTraining constructor tag"
    case encodedLength of
      10 -> do
        raw <- decodeRawCompletedTrainingFields (pure Nothing)
        when (rawCompletedTrainingVersion raw /= 1) $
          fail "legacy RawCompletedTraining tuple must carry wire version 1"
        pure raw
      11 -> do
        raw <- decodeRawCompletedTrainingFields decode
        when (rawCompletedTrainingVersion raw /= completedTrainingWireVersion) $
          fail "current RawCompletedTraining tuple must carry the current wire version"
        pure raw
      _ ->
        fail
          ( "wrong RawCompletedTraining field count: expected 10 or 11, got "
              <> show encodedLength
          )

encodeRawCompletedTrainingFields
  :: Word
  -> RawCompletedTraining
  -> Encoding
  -> Encoding
encodeRawCompletedTrainingFields encodedLength raw encodedInvocation =
  encodeListLen encodedLength
    <> encodeWord 0
    <> encode (rawCompletedTrainingVersion raw)
    <> encode (rawCompletedTrainingPlanId raw)
    <> encode (rawCompletedTrainingBudget raw)
    <> encode (rawCompletedTrainingObservedKind raw)
    <> encode (rawCompletedTrainingObservedUnits raw)
    <> encode (rawCompletedTrainingObservedUnitLabel raw)
    <> encode (rawCompletedTrainingEvidence raw)
    <> encode (rawCompletedTrainingMeasurements raw)
    <> encode (rawCompletedTrainingTensorBoard raw)
    <> encodedInvocation

decodeRawCompletedTrainingFields
  :: Decoder s (Maybe RawProductScenarioInvocation)
  -> Decoder s RawCompletedTraining
decodeRawCompletedTrainingFields decodeInvocation =
  RawCompletedTraining
    <$> decode
    <*> decode
    <*> decode
    <*> decode
    <*> decode
    <*> decode
    <*> decode
    <*> decode
    <*> decode
    <*> decodeInvocation

completedTrainingWireVersion :: Word64
completedTrainingWireVersion = 2

productScenarioInvocationRunId :: ProductScenarioInvocation -> Text
productScenarioInvocationRunId = invocationRunIdProof

productScenarioInvocationRowId :: ProductScenarioInvocation -> Text
productScenarioInvocationRowId = invocationRowIdProof

productScenarioInvocationPlanId :: ProductScenarioInvocation -> PlanId
productScenarioInvocationPlanId = invocationPlanIdProof

productScenarioInvocationSubstrate :: ProductScenarioInvocation -> Substrate
productScenarioInvocationSubstrate = invocationSubstrateProof

productScenarioInvocationCheckpointScopeDigest
  :: ProductScenarioInvocation
  -> Text
productScenarioInvocationCheckpointScopeDigest = invocationCheckpointScopeDigestProof

productScenarioInvocationExecutableSha256
  :: ProductScenarioInvocation
  -> Text
productScenarioInvocationExecutableSha256 = invocationExecutableSha256Proof

productScenarioInvocationChallenge :: ProductScenarioInvocation -> Text
productScenarioInvocationChallenge = invocationChallengeProof

-- | The canonical public identity for journal correlation.  Length-delimited
-- ambiguity is avoided because every free-text component is refined to a
-- non-empty, control-free token and the rendering has a fixed eight-field
-- shape.
productScenarioInvocationDigest :: ProductScenarioInvocation -> Text
productScenarioInvocationDigest =
  hexBytes . SHA256.hash . Text.Encoding.encodeUtf8 . renderProductScenarioInvocation

renderProductScenarioInvocation :: ProductScenarioInvocation -> Text
renderProductScenarioInvocation invocation =
  Text.intercalate
    "\t"
    [ productScenarioInvocationWireTag
    , productScenarioInvocationRunId invocation
    , productScenarioInvocationRowId invocation
    , planIdText (productScenarioInvocationPlanId invocation)
    , renderSubstrate (productScenarioInvocationSubstrate invocation)
    , productScenarioInvocationCheckpointScopeDigest invocation
    , productScenarioInvocationExecutableSha256 invocation
    , productScenarioInvocationChallenge invocation
    ]

parseProductScenarioInvocation :: Text -> Either Text ProductScenarioInvocation
parseProductScenarioInvocation encoded =
  case Text.splitOn "\t" encoded of
    [ tag
      , runId
      , rowId
      , rawPlanId
      , rawSubstrate
      , checkpointScopeDigest
      , executableSha256
      , challenge
      ]
        | tag == productScenarioInvocationWireTag -> do
            planId <-
              firstText
                "invalid ProductScenario invocation PlanId: "
                (refinePlanIdText rawPlanId)
            substrate <-
              maybe
                (Left "invalid ProductScenario invocation substrate")
                Right
                (parseSubstrate rawSubstrate)
            mkProductScenarioInvocation
              runId
              rowId
              planId
              substrate
              checkpointScopeDigest
              executableSha256
              challenge
    _ -> Left "ProductScenario invocation must use the exact v1 eight-field encoding"

mkProductScenarioInvocation
  :: Text
  -> Text
  -> PlanId
  -> Substrate
  -> Text
  -> Text
  -> Text
  -> Either Text ProductScenarioInvocation
mkProductScenarioInvocation runId rowId planId substrate checkpointScopeDigest executableSha256 challenge = do
  validateInvocationToken "run identity" runId
  validateInvocationToken "row identity" rowId
  validateCanonicalSha256 "checkpoint-scope digest" checkpointScopeDigest
  validateCanonicalSha256 "executable SHA-256" executableSha256
  validateCanonicalSha256 "32-byte challenge" challenge
  Right
    ProductScenarioInvocation
      { invocationRunIdProof = runId
      , invocationRowIdProof = rowId
      , invocationPlanIdProof = planId
      , invocationSubstrateProof = substrate
      , invocationCheckpointScopeDigestProof = checkpointScopeDigest
      , invocationExecutableSha256Proof = executableSha256
      , invocationChallengeProof = challenge
      }

productScenarioInvocationToRaw
  :: ProductScenarioInvocation
  -> RawProductScenarioInvocation
productScenarioInvocationToRaw invocation =
  RawProductScenarioInvocation
    { rawProductScenarioInvocationRunId = productScenarioInvocationRunId invocation
    , rawProductScenarioInvocationRowId = productScenarioInvocationRowId invocation
    , rawProductScenarioInvocationPlanId =
        planIdText (productScenarioInvocationPlanId invocation)
    , rawProductScenarioInvocationSubstrate =
        renderSubstrate (productScenarioInvocationSubstrate invocation)
    , rawProductScenarioInvocationCheckpointScopeDigest =
        productScenarioInvocationCheckpointScopeDigest invocation
    , rawProductScenarioInvocationExecutableSha256 =
        productScenarioInvocationExecutableSha256 invocation
    , rawProductScenarioInvocationChallenge =
        productScenarioInvocationChallenge invocation
    }

refineProductScenarioInvocation
  :: RawProductScenarioInvocation
  -> Either Text ProductScenarioInvocation
refineProductScenarioInvocation raw = do
  planId <-
    firstText
      "invalid ProductScenario invocation PlanId: "
      (refinePlanIdText (rawProductScenarioInvocationPlanId raw))
  substrate <-
    maybe
      (Left "invalid ProductScenario invocation substrate")
      Right
      (parseSubstrate (rawProductScenarioInvocationSubstrate raw))
  mkProductScenarioInvocation
    (rawProductScenarioInvocationRunId raw)
    (rawProductScenarioInvocationRowId raw)
    planId
    substrate
    (rawProductScenarioInvocationCheckpointScopeDigest raw)
    (rawProductScenarioInvocationExecutableSha256 raw)
    (rawProductScenarioInvocationChallenge raw)

validateInvocationToken :: Text -> Text -> Either Text ()
validateInvocationToken label value
  | Text.null value = Left ("ProductScenario " <> label <> " must be non-empty")
  | Text.length value > 256 = Left ("ProductScenario " <> label <> " exceeds 256 characters")
  | Text.strip value /= value =
      Left ("ProductScenario " <> label <> " must not have surrounding whitespace")
  | Text.any isControl value =
      Left ("ProductScenario " <> label <> " must not contain control characters")
  | otherwise = Right ()

validateCanonicalSha256 :: Text -> Text -> Either Text ()
validateCanonicalSha256 label value
  | Text.length value /= 64 =
      Left ("ProductScenario " <> label <> " must contain exactly 64 characters")
  | not (Text.all isLowerHex value) =
      Left ("ProductScenario " <> label <> " must be lowercase hexadecimal")
  | otherwise = Right ()

isLowerHex :: Char -> Bool
isLowerHex character =
  isAsciiDecimalDigit character
    || ('a' <= character && character <= 'f')

isAsciiDecimalDigit :: Char -> Bool
isAsciiDecimalDigit character =
  let codepoint = ord character
   in codepoint >= ord '0' && codepoint <= ord '9'

firstText :: Text -> Either Text value -> Either Text value
firstText prefix = first (prefix <>)

productScenarioInvocationWireTag :: Text
productScenarioInvocationWireTag = "product-scenario-invocation-v1"

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
          { budgetKindValue = kind
          , budgetTargetUnitsValue = target
          , budgetSeedValue = seed
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

completedTrainingProductScenarioInvocation
  :: CompletedTraining
  -> Maybe ProductScenarioInvocation
completedTrainingProductScenarioInvocation = completedProductScenarioInvocationProof

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

-- | The device execution witness bound to this completion, if the training run
-- dispatched to a device.  'completedTraining' has already revalidated it, so a
-- 'Left' here cannot survive into an admitted checkpoint.
completedTrainingDeviceWitness
  :: CompletedTraining -> Either Text (Maybe DeviceExecutionWitness)
completedTrainingDeviceWitness =
  evidenceDeviceWitness . completedTrainingEvidence

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
      , completedProductScenarioInvocationProof = Nothing
      }

-- | Attach the command-owned invocation to an otherwise complete proof.  A
-- completion cannot be rebound, and its PlanId must already agree with the
-- invocation before the addressed checkpoint is written.
bindCompletedTrainingToProductScenarioInvocation
  :: ProductScenarioInvocation
  -> CompletedTraining
  -> Either Text CompletedTraining
bindCompletedTrainingToProductScenarioInvocation invocation completed
  | productScenarioInvocationPlanId invocation /= completedTrainingPlanId completed =
      Left "ProductScenario invocation PlanId differs from completed training"
  | Just observed <- completedTrainingProductScenarioInvocation completed =
      if observed == invocation
        then Right completed
        else Left "completed training is already bound to a different ProductScenario invocation"
  | otherwise =
      Right
        completed
          { completedProductScenarioInvocationProof = Just invocation
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
        , rawCompletedTrainingProductScenarioInvocation =
            productScenarioInvocationToRaw
              <$> completedTrainingProductScenarioInvocation completed
        }

refineCompletedTraining :: RawCompletedTraining -> Either Text CompletedTraining
refineCompletedTraining raw = do
  case rawCompletedTrainingVersion raw of
    1 ->
      when
        (isJust (rawCompletedTrainingProductScenarioInvocation raw))
        (Left "completed-training V1 cannot carry a ProductScenario invocation")
    version ->
      when (version /= completedTrainingWireVersion) $
        Left
          ( "unsupported completed-training version: "
              <> Text.pack (show version)
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
  completed <-
    completedTraining
      planId
      budget
      (rawCompletedTrainingObservedUnits raw)
      (rawCompletedTrainingEvidence raw)
      observations
      (rawCompletedTrainingTensorBoard raw)
  case rawCompletedTrainingProductScenarioInvocation raw of
    Nothing -> Right completed
    Just rawInvocation -> do
      invocation <- refineProductScenarioInvocation rawInvocation
      bindCompletedTrainingToProductScenarioInvocation invocation completed

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

-- | Re-run every observation check the evidence smart constructor enforces, and
-- carry the bound device execution witness across.  A stored witness that no
-- longer refines fails the revalidation rather than silently dropping to an
-- unwitnessed completion.
revalidateEvidence :: TrainingEvidence -> Either Text TrainingEvidence
revalidateEvidence evidence = do
  base <-
    mkTrainingEvidence
      (evidenceInitialWeightHash evidence)
      (evidenceFinalWeightHash evidence)
      (evidenceUpdateCount evidence)
      (evidenceDatasetShaAtRead evidence)
  witness <- evidenceDeviceWitness evidence
  maybe (Right base) (`attachDeviceExecutionWitness` base) witness

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

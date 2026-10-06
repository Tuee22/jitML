{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 285 — implementation of the opaque per-model completed-run evidence.
--
-- This module owns the hidden constructors and the raw, forgeable boundary. It
-- is deliberately not exposed by the cabal library: 'JitML.Test.ModelEvidence'
-- re-exports the safe surface (opaque evidence, typed failures, assertions, and
-- loading an /admitted/ lane journal), and 'JitML.Test.ModelEvidence.Raw'
-- re-exports the raw mint path that only the mutation controls may import.
module JitML.Test.ModelEvidence.Internal where

import Control.Exception (IOException, try)
import Data.ByteString qualified as ByteString
import Data.Either (lefts, rights)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Plan.Plan
  ( PlanId
  , RunKind (..)
  , RunKindWitness (..)
  , SeedCohort
  , Validation (..)
  , planIdText
  , runPlanSeeds
  , seedCohortValues
  )
import JitML.Product.Convergence
  ( ConvergenceBar
  , convergenceMetricGoal
  , convergenceMetricName
  , convergenceThreshold
  )
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Test.ProductAggregation (ProductLaneInput (..), productLaneInputs)
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as Budget

-- ---------------------------------------------------------------------------
-- Raw, forgeable boundary

-- | Which evidence channel a measurement arrived on. A learning-iteration
-- summary and a final-evaluation observation are different evidence and may
-- never stand in for one another, even when a learning counter happens to
-- clear a final-quality bar numerically.
data EvidenceChannel
  = LearningIterationChannel
  | FinalEvaluationChannel
  deriving stock (Eq, Show)

-- | The two slots a seed's evidence has, one per channel.
data EvidenceSlot
  = LearningSlot
  | FinalQualitySlot
  deriving stock (Eq, Show)

-- | The invocation identity the completion carries.
data RawInvocationIdentity = RawInvocationIdentity
  { riiRowId :: !Text
  , riiPlanId :: !PlanId
  , riiSubstrate :: !Substrate
  }
  deriving stock (Eq, Show)

-- | Identities recorded inside the completion itself, independently of the
-- journal row's own wire fields.
data RawCompletionIdentity = RawCompletionIdentity
  { rciPlanId :: !PlanId
  , rciExperimentHash :: !Text
  -- ^ The TensorBoard run identity the completion recorded.
  , rciInvocation :: !(Maybe RawInvocationIdentity)
  , rciDeviceSubstrate :: !(Maybe Substrate)
  }
  deriving stock (Eq, Show)

-- | Learning-channel counters for one seed.
data RawLearningTelemetry = RawLearningTelemetry
  { rltChannel :: !EvidenceChannel
  , rltBudgetKind :: !Budget.BudgetKind
  , rltObservedUnits :: !Word64
  , rltUpdateCount :: !Word64
  , rltInitialWeightHash :: !Text
  , rltFinalWeightHash :: !Text
  }
  deriving stock (Eq, Show)

-- | Final-evaluation-channel criterion observations for one seed.
data RawFinalQuality = RawFinalQuality
  { rfqChannel :: !EvidenceChannel
  , rfqObservations :: ![Budget.RawConvergenceObservation]
  }
  deriving stock (Eq, Show)

data RawSeedEvidence = RawSeedEvidence
  { rseSeed :: !Word64
  , rseLearning :: !RawLearningTelemetry
  , rseFinalQuality :: !RawFinalQuality
  }
  deriving stock (Eq, Show)

-- | Deliberately forgeable view of one lane-journal row. It carries no proof:
-- 'refineModelRowEvidence' re-checks every field against the projection.
data RawModelEvidence = RawModelEvidence
  { rmeRowId :: !Text
  , rmePlanId :: !PlanId
  , rmeLane :: !Substrate
  , rmeExperimentHash :: !Text
  , rmeManifestSha :: !Text
  -- ^ The admitted completed checkpoint's manifest identity.
  , rmeInferenceManifestSha :: !Text
  -- ^ The manifest the inference-performance counters are bound to. Lane
  -- admission proves it equals 'rmeManifestSha'; a foreign producer must too.
  , rmeContractDigest :: !Text
  , rmeCompletionJournalDigest :: !Text
  , rmeMeasuredDigest :: !Text
  , rmeRecomputedMeasuredDigest :: !Text
  -- ^ The digest recomputed from the completion payload the values below were
  -- read from.
  , rmeCompletion :: !RawCompletionIdentity
  , rmeSeeds :: ![RawSeedEvidence]
  }
  deriving stock (Eq, Show)

-- | The raw view of one /admitted/ journal row. Every field is read through the
-- admitted row's accessors; nothing is parsed or defaulted here.
rawModelEvidenceFromJournalRow :: Lane.ProductLaneJournalRow -> RawModelEvidence
rawModelEvidenceFromJournalRow row =
  RawModelEvidence
    { rmeRowId = Lane.productLaneJournalRowRowId row
    , rmePlanId = Lane.productLaneJournalRowPlanId row
    , rmeLane = Lane.productLaneJournalRowSubstrate row
    , rmeExperimentHash = Lane.productLaneJournalRowExperimentHash row
    , rmeManifestSha = Lane.productLaneJournalRowManifestSha row
    , -- Admission ('Lane.admitProductLaneJournal') already requires the wire's
      -- inference manifest to equal its admitted manifest and exposes that single
      -- retained identity.
      rmeInferenceManifestSha = Lane.productLaneJournalRowManifestSha row
    , rmeContractDigest = Lane.productLaneJournalRowContractDigest row
    , rmeCompletionJournalDigest = Lane.productLaneJournalRowJournalDigest row
    , rmeMeasuredDigest = Lane.productLaneJournalRowMeasuredDigest row
    , rmeRecomputedMeasuredDigest = Report.canonicalCompletedTrainingDigest completed
    , rmeCompletion =
        RawCompletionIdentity
          { rciPlanId = Budget.completedTrainingPlanId completed
          , rciExperimentHash = Budget.tbrRunId (Budget.completedTrainingTensorBoard completed)
          , rciInvocation = invocationIdentity <$> Budget.completedTrainingProductScenarioInvocation completed
          , rciDeviceSubstrate =
              case Budget.completedTrainingDeviceWitness completed of
                Right (Just witness) -> Just (DeviceWitness.witnessSubstrate witness)
                Right Nothing -> Nothing
                Left _ -> Nothing
          }
    , rmeSeeds =
        [ RawSeedEvidence
            { rseSeed = seed
            , rseLearning =
                RawLearningTelemetry
                  { rltChannel = LearningIterationChannel
                  , rltBudgetKind = Budget.trainingBudgetKind budget
                  , rltObservedUnits = Budget.completedTrainingObservedUnits completed
                  , rltUpdateCount = Budget.completedTrainingUpdateCount completed
                  , rltInitialWeightHash = Budget.completedTrainingInitialWeightHash completed
                  , rltFinalWeightHash = Budget.completedTrainingFinalWeightHash completed
                  }
            , rseFinalQuality =
                RawFinalQuality
                  { rfqChannel = FinalEvaluationChannel
                  , rfqObservations =
                      fmap Budget.convergenceObservationToRaw (Budget.completedTrainingMetrics completed)
                  }
            }
        | Just seed <- [Budget.trainingBudgetSeed budget]
        ]
    }
 where
  completed = Lane.productLaneJournalRowCompletedTraining row
  budget = Budget.completedTrainingBudget completed
  invocationIdentity invocation =
    RawInvocationIdentity
      { riiRowId = Budget.productScenarioInvocationRowId invocation
      , riiPlanId = Budget.productScenarioInvocationPlanId invocation
      , riiSubstrate = Budget.productScenarioInvocationSubstrate invocation
      }

-- | Raw views of every row of an admitted journal, in journal order.
rawModelEvidenceFromJournal :: Lane.AdmittedProductLaneJournal -> [RawModelEvidence]
rawModelEvidenceFromJournal =
  fmap rawModelEvidenceFromJournalRow . Lane.admittedProductLaneJournalRows

-- ---------------------------------------------------------------------------
-- Typed failures

-- | Which compared identity a binding failure concerns.
data BindingField
  = BindingRowId
  | BindingJournalPlan
  | BindingCompletionPlan
  | BindingInvocationPlan
  | BindingJournalLane
  | BindingInvocationLane
  | BindingDeviceWitnessLane
  | BindingJournalExperiment
  | BindingCompletionExperiment
  | BindingInvocationRow
  | BindingAdmittedManifest
  | BindingInferenceManifest
  | BindingContractDigest
  | BindingCompletionJournalDigest
  | BindingMeasuredDigest
  | BindingRunKind
  deriving stock (Eq, Show)

data SeedCoverageIssue
  = EmptySeedCohort
  | MissingSeedEvidence !Word64
  | DuplicateSeedEvidence !Word64
  | UnplannedSeedEvidence !Word64
  deriving stock (Eq, Show)

-- | Identity and cohort-coverage failures. 'BindingMismatch' carries the
-- expected value (from the validated projection) then the observed value.
data BindingFailure
  = BindingMismatch !BindingField !Text !Text
  | BindingMissing !BindingField
  | BindingDigestMalformed !BindingField !Text
  | BindingSeedCohort !SeedCoverageIssue
  deriving stock (Eq, Show)

-- | Failures that stop raw evidence from becoming 'ModelRowEvidence'.
data RowEvidenceError
  = RowBindingRejected !BindingFailure
  | -- | seed, metric name, field label
    RowNonFiniteEvidence !Word64 !Text !Text
  | -- | seed, the slot that was offered, the channel the payload declared
    RowChannelSubstituted !Word64 !EvidenceSlot !EvidenceChannel
  deriving stock (Eq, Show)

-- | Join-level failures, mirroring 'Report.ProductScenarioReportError'.
data ModelEvidenceError
  = MissingModelEvidence !Text !PlanId
  | DuplicateModelEvidence !Text
  | OrphanModelEvidence !Text !PlanId
  | WrongPlanModelEvidence !Text !PlanId !PlanId
  | WrongLaneModelEvidence !Text !Substrate !Substrate
  | StaleContractModelEvidence !Text
  | RowEvidenceRejected !Text !(NonEmpty RowEvidenceError)
  deriving stock (Eq, Show)

-- | Final-quality-channel assertion failures.
data FinalQualityFailure
  = NoIndependentCriterion !Text
  | RegistryBarDrift !ExternalBars.ExternalCriterion !ConvergenceBar
  | MissingMetric !Word64 !Text
  | DuplicateMetric !Word64 !Text
  | UnexpectedMetric !Word64 !Text
  | -- | seed, metric, expected (rule, threshold), observed (rule, threshold)
    CriterionMismatch
      !Word64
      !Text
      !(Budget.RawCriterionRule, Double)
      !(Budget.RawCriterionRule, Double)
  | -- | metric, cohort statistic, the independent criterion it failed
    BelowBar !Text !Double !ExternalBars.ExternalCriterion
  deriving stock (Eq, Show)

-- | Learning-channel assertion failures.
data LearningFailure
  = UnitKindMismatch !Word64 !Budget.BudgetKind !Budget.BudgetKind
  | -- | seed, planned units, observed units
    ObservedUnitsMismatch !Word64 !Integer !Word64
  | NoOptimizerUpdates !Word64
  | WeightHashMissing !Word64
  | WeightsUnchanged !Word64
  | -- | seed, planned optimizer updates, observed update count
    UpdateCountMismatch !Word64 !Integer !Word64
  deriving stock (Eq, Show)

-- | Performance-bound assertion failures.
data PerformanceFailure
  = PerformanceBoundViolated
      !Word64
      !ExternalBars.PerformanceMetric
      !ExternalBars.PerformanceBound
      !Integer
  | PerformanceMetricUnmeasured !Word64 !ExternalBars.PerformanceMetric
  deriving stock (Eq, Show)

-- | Why a set of performance receipts is not bound to the admitted journal row
-- it is graded against ('assertReceiptBinding').
data ReceiptBindingFailure
  = -- | The row's evidence produced no performance receipt at all; the row id.
    NoPerformanceReceipt !Text
  | -- | A receipt identity differs from the journal row: the field compared, the
    -- journal row's value, then the receipt's value.
    ReceiptNotBound !BindingField !Text !Text
  deriving stock (Eq, Show)

-- | The four assertion families, kept as distinct constructors.
data ModelAssertionFailure
  = FinalQualityFailed !FinalQualityFailure
  | LearningFailed !LearningFailure
  | PerformanceFailed !PerformanceFailure
  | BindingFailed !BindingFailure
  deriving stock (Eq, Show)

-- | Failures loading and admitting a lane's retained journal.
data ModelEvidenceLoadError
  = LaneJournalNotRegistered !Substrate
  | LaneJournalUnreadable !FilePath !Text
  | LaneProjectionRejected !Substrate !(NonEmpty ProductMatrix.ProductMatrixError)
  | LaneJournalRejected !Substrate !FilePath !Text !(NonEmpty Lane.ProductLaneJournalError)
  | LaneEvidenceRejected !Substrate !(NonEmpty ModelEvidenceError)
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Opaque evidence

-- | The learning-channel counters of one seed. Distinct from 'FinalQuality':
-- no assertion accepts one where the other is expected.
data LearningTelemetry = LearningTelemetry
  { telemetryBudgetKindValue :: !Budget.BudgetKind
  , telemetryObservedUnitsValue :: !Word64
  , telemetryUpdateCountValue :: !Word64
  , telemetryInitialWeightHashValue :: !Text
  , telemetryFinalWeightHashValue :: !Text
  }
  deriving stock (Eq, Show)

-- | The final-evaluation-channel observations of one seed.
newtype FinalQuality = FinalQuality
  { finalQualityObservationsValue :: [Budget.RawConvergenceObservation]
  }
  deriving stock (Eq, Show)

data SeedEvidence = SeedEvidence
  { seedEvidenceSeedValue :: !Word64
  , seedEvidenceLearningValue :: !LearningTelemetry
  , seedEvidenceFinalQualityValue :: !FinalQuality
  }
  deriving stock (Eq, Show)

seedEvidenceSeed :: SeedEvidence -> Word64
seedEvidenceSeed = seedEvidenceSeedValue

seedEvidenceLearning :: SeedEvidence -> LearningTelemetry
seedEvidenceLearning = seedEvidenceLearningValue

seedEvidenceFinalQuality :: SeedEvidence -> FinalQuality
seedEvidenceFinalQuality = seedEvidenceFinalQualityValue

learningTelemetryBudgetKind :: LearningTelemetry -> Budget.BudgetKind
learningTelemetryBudgetKind = telemetryBudgetKindValue

learningTelemetryObservedUnits :: LearningTelemetry -> Word64
learningTelemetryObservedUnits = telemetryObservedUnitsValue

learningTelemetryUpdateCount :: LearningTelemetry -> Word64
learningTelemetryUpdateCount = telemetryUpdateCountValue

finalQualityObservations :: FinalQuality -> [Budget.RawConvergenceObservation]
finalQualityObservations = finalQualityObservationsValue

-- | Identity facts retained from the raw evidence once they have been checked.
data ModelIdentity = ModelIdentity
  { identityRowIdValue :: !Text
  , identityPlanIdValue :: !PlanId
  , identityLaneValue :: !Substrate
  , identityExperimentHashValue :: !Text
  , identityManifestShaValue :: !Text
  , identityInferenceManifestShaValue :: !Text
  , identityContractDigestValue :: !Text
  , identityCompletionJournalDigestValue :: !Text
  , identityMeasuredDigestValue :: !Text
  , identityRecomputedMeasuredDigestValue :: !Text
  , identityCompletionValue :: !RawCompletionIdentity
  }
  deriving stock (Eq, Show)

-- | Opaque, kind-indexed completed-run evidence for one 'ProductMatrix.ProductRow'.
-- The constructor is hidden and the record labels are not exported; the only
-- producers are 'refineModelRowEvidence' and 'joinModelEvidence'.
data ModelRowEvidence (kind :: RunKind) = ModelRowEvidence
  { evidenceIdentityValue :: !ModelIdentity
  , evidenceRowClassValue :: !ProductMatrix.RowClass
  , evidenceFamilyValue :: !ProductMatrix.RowFamily
  , evidenceRegistryBarValue :: !ConvergenceBar
  , evidenceTrainingBudgetValue :: !Budget.TrainingBudget
  , evidenceResolvedPlanValue :: !(ProductMatrix.ProductResolvedPlan kind)
  , evidenceSeedsValue :: !(NonEmpty SeedEvidence)
  }
  deriving stock (Eq, Show)

modelEvidenceRowId :: ModelRowEvidence kind -> Text
modelEvidenceRowId = identityRowIdValue . evidenceIdentityValue

modelEvidencePlanId :: ModelRowEvidence kind -> PlanId
modelEvidencePlanId = identityPlanIdValue . evidenceIdentityValue

modelEvidenceLane :: ModelRowEvidence kind -> Substrate
modelEvidenceLane = identityLaneValue . evidenceIdentityValue

modelEvidenceExperimentHash :: ModelRowEvidence kind -> Text
modelEvidenceExperimentHash = identityExperimentHashValue . evidenceIdentityValue

modelEvidenceManifestSha :: ModelRowEvidence kind -> Text
modelEvidenceManifestSha = identityManifestShaValue . evidenceIdentityValue

modelEvidenceContractDigest :: ModelRowEvidence kind -> Text
modelEvidenceContractDigest = identityContractDigestValue . evidenceIdentityValue

modelEvidenceRowClass :: ModelRowEvidence kind -> ProductMatrix.RowClass
modelEvidenceRowClass = evidenceRowClassValue

modelEvidenceFamily :: ModelRowEvidence kind -> ProductMatrix.RowFamily
modelEvidenceFamily = evidenceFamilyValue

modelEvidenceSeedEvidence :: ModelRowEvidence kind -> NonEmpty SeedEvidence
modelEvidenceSeedEvidence = evidenceSeedsValue

modelEvidenceSeeds :: ModelRowEvidence kind -> [Word64]
modelEvidenceSeeds = fmap seedEvidenceSeedValue . NonEmpty.toList . evidenceSeedsValue

-- | Existential wrapper used by the heterogeneous registry-ordered set.
data SomeModelRowEvidence where
  SomeModelRowEvidence
    :: RunKindWitness kind
    -> ModelRowEvidence kind
    -> SomeModelRowEvidence

instance Eq SomeModelRowEvidence where
  SomeModelRowEvidence SupervisedTrainingWitness left
    == SomeModelRowEvidence SupervisedTrainingWitness right = left == right
  SomeModelRowEvidence ReinforcementLearningWitness left
    == SomeModelRowEvidence ReinforcementLearningWitness right = left == right
  SomeModelRowEvidence HyperparameterTuningWitness left
    == SomeModelRowEvidence HyperparameterTuningWitness right = left == right
  SomeModelRowEvidence AlphaZeroSelfPlayWitness left
    == SomeModelRowEvidence AlphaZeroSelfPlayWitness right = left == right
  _ == _ = False

instance Show SomeModelRowEvidence where
  show (SomeModelRowEvidence witness evidence) =
    case witness of
      SupervisedTrainingWitness -> show evidence
      ReinforcementLearningWitness -> show evidence
      HyperparameterTuningWitness -> show evidence
      AlphaZeroSelfPlayWitness -> show evidence

someModelEvidenceRowId :: SomeModelRowEvidence -> Text
someModelEvidenceRowId (SomeModelRowEvidence _ evidence) = modelEvidenceRowId evidence

-- | A registry-ordered set holding exactly one evidence value per projected
-- row of one lane. Its constructor is hidden; only 'joinModelEvidence' builds it.
data ModelEvidenceSet = ModelEvidenceSet
  { evidenceSetLaneValue :: !Substrate
  , evidenceSetRowsValue :: ![SomeModelRowEvidence]
  }
  deriving stock (Eq, Show)

modelEvidenceSetLane :: ModelEvidenceSet -> Substrate
modelEvidenceSetLane = evidenceSetLaneValue

modelEvidenceSetRows :: ModelEvidenceSet -> [SomeModelRowEvidence]
modelEvidenceSetRows = evidenceSetRowsValue

lookupModelEvidence :: Text -> ModelEvidenceSet -> Maybe SomeModelRowEvidence
lookupModelEvidence rowIdentity =
  List.find ((== rowIdentity) . someModelEvidenceRowId) . evidenceSetRowsValue

-- ---------------------------------------------------------------------------
-- Minting

-- | Mint evidence for one row directly from its validated projection and the
-- corresponding row of an /admitted/ lane journal. This is the typed statement
-- of the phase's rule: the only inputs are the projection the live executor was
-- planned from and a row the production reader has already admitted.
modelEvidenceFromJournalRow
  :: ProductMatrix.ProductProjection kind
  -> Lane.ProductLaneJournalRow
  -> Either (NonEmpty RowEvidenceError) (ModelRowEvidence kind)
modelEvidenceFromJournalRow projection =
  refineModelRowEvidence projection . rawModelEvidenceFromJournalRow

-- | Compare observed seeds with the plan's cohort ('runPlanSeeds'): an empty
-- observation, a planned seed with no evidence, a seed observed twice, and a
-- seed the plan never declared are each a typed issue.
checkSeedCoverage :: SeedCohort -> [Word64] -> [SeedCoverageIssue]
checkSeedCoverage cohort observed =
  [EmptySeedCohort | null observed]
    <> [MissingSeedEvidence seed | seed <- planned, seed `notElem` observed]
    <> [DuplicateSeedEvidence seed | seed <- repeated observed]
    <> [UnplannedSeedEvidence seed | seed <- List.nub observed, seed `notElem` planned]
 where
  planned = NonEmpty.toList (seedCohortValues cohort)
  repeated values =
    [ value
    | value : _ : _ <- List.group (List.sort values)
    ]

-- | Mint evidence for one row from its validated projection and raw view.
-- Every failure is accumulated. The evidence exists only when identity,
-- cohort coverage, finiteness, and channel separation all hold; grading it
-- against the criterion and bounds is the assertions' job.
refineModelRowEvidence
  :: ProductMatrix.ProductProjection kind
  -> RawModelEvidence
  -> Either (NonEmpty RowEvidenceError) (ModelRowEvidence kind)
refineModelRowEvidence projection raw =
  case (NonEmpty.nonEmpty identityErrors, seedCohort) of
    (Nothing, Right seeds) ->
      Right
        ModelRowEvidence
          { evidenceIdentityValue = identity
          , evidenceRowClassValue = ProductMatrix.productProjectionRowClass projection
          , evidenceFamilyValue = ProductMatrix.productProjectionFamily projection
          , evidenceRegistryBarValue = ProductMatrix.productProjectionConvergenceBar projection
          , evidenceTrainingBudgetValue = ProductMatrix.productProjectionTrainingBudget projection
          , evidenceResolvedPlanValue = ProductMatrix.productProjectionResolvedPlan projection
          , evidenceSeedsValue = seeds
          }
    (Just identityFailures, Right _) -> Left identityFailures
    (Nothing, Left seedFailures) -> Left seedFailures
    (Just identityFailures, Left seedFailures) -> Left (identityFailures <> seedFailures)
 where
  identity =
    ModelIdentity
      { identityRowIdValue = rmeRowId raw
      , identityPlanIdValue = rmePlanId raw
      , identityLaneValue = rmeLane raw
      , identityExperimentHashValue = rmeExperimentHash raw
      , identityManifestShaValue = rmeManifestSha raw
      , identityInferenceManifestShaValue = rmeInferenceManifestSha raw
      , identityContractDigestValue = rmeContractDigest raw
      , identityCompletionJournalDigestValue = rmeCompletionJournalDigest raw
      , identityMeasuredDigestValue = rmeMeasuredDigest raw
      , identityRecomputedMeasuredDigestValue = rmeRecomputedMeasuredDigest raw
      , identityCompletionValue = rmeCompletion raw
      }
  identityErrors =
    fmap RowBindingRejected (identityFailuresFor projection identity)
  seedCohort =
    refineSeedCohort
      (runPlanSeeds (ProductMatrix.productProjectionRunPlan projection))
      (rmeSeeds raw)

-- | Refine the per-seed raw evidence of one row against the plan's seed
-- cohort. Coverage is checked against the cohort ('checkSeedCoverage'), and
-- every seed is refined on its own (finite measurements, each payload on its
-- own channel), so a defect names the seed it belongs to whatever the cohort
-- size. The evidence exists only when all of that holds; the cohort is then
-- non-empty by construction.
refineSeedCohort
  :: SeedCohort
  -> [RawSeedEvidence]
  -> Either (NonEmpty RowEvidenceError) (NonEmpty SeedEvidence)
refineSeedCohort cohort rawSeeds =
  case NonEmpty.nonEmpty (coverageErrors <> seedErrors) of
    Just errors -> Left errors
    Nothing ->
      case NonEmpty.nonEmpty refinedSeeds of
        Just seeds -> Right seeds
        Nothing -> Left (RowBindingRejected (BindingSeedCohort EmptySeedCohort) :| [])
 where
  coverageErrors =
    fmap
      (RowBindingRejected . BindingSeedCohort)
      (checkSeedCoverage cohort (fmap rseSeed rawSeeds))
  seedResults = fmap refineSeedEvidence rawSeeds
  seedErrors = concat [NonEmpty.toList errors | Left errors <- seedResults]
  refinedSeeds = rights seedResults

refineSeedEvidence :: RawSeedEvidence -> Either (NonEmpty RowEvidenceError) SeedEvidence
refineSeedEvidence raw =
  case NonEmpty.nonEmpty errors of
    Just failures -> Left failures
    Nothing ->
      Right
        SeedEvidence
          { seedEvidenceSeedValue = seed
          , seedEvidenceLearningValue =
              LearningTelemetry
                { telemetryBudgetKindValue = rltBudgetKind learning
                , telemetryObservedUnitsValue = rltObservedUnits learning
                , telemetryUpdateCountValue = rltUpdateCount learning
                , telemetryInitialWeightHashValue = rltInitialWeightHash learning
                , telemetryFinalWeightHashValue = rltFinalWeightHash learning
                }
          , seedEvidenceFinalQualityValue = FinalQuality (rfqObservations final)
          }
 where
  seed = rseSeed raw
  learning = rseLearning raw
  final = rseFinalQuality raw
  errors =
    [ RowChannelSubstituted seed LearningSlot (rltChannel learning)
    | rltChannel learning /= LearningIterationChannel
    ]
      <> [ RowChannelSubstituted seed FinalQualitySlot (rfqChannel final)
         | rfqChannel final /= FinalEvaluationChannel
         ]
      <> [ RowNonFiniteEvidence seed name field
         | observation <- rfqObservations final
         , let name = Budget.rawCriterionName observation
         , (field, value) <- observationFiniteFields observation
         , not (finite value)
         ]

observationFiniteFields :: Budget.RawConvergenceObservation -> [(Text, Double)]
observationFiniteFields observation =
  [ ("value", Budget.rawMeasurementValue observation)
  , ("threshold", Budget.rawCriterionThreshold observation)
  ]
    <> case Budget.rawCriterionRule observation of
      Budget.RawCriterionAtLeastExcluding excluded tolerance ->
        [("exclusion sentinel", excluded), ("exclusion tolerance", tolerance)]
      Budget.RawCriterionAtLeast -> []
      Budget.RawCriterionAtMost -> []

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

-- | Identity comparisons plus cohort coverage of the observed seeds, for
-- re-checking evidence against a projection ('assertModelBinding'). Minting
-- runs the same two checks: 'identityFailuresFor' here and 'checkSeedCoverage'
-- inside 'refineSeedCohort', so a re-check cannot diverge from the mint-time
-- check.
bindingFailuresFor
  :: ProductMatrix.ProductProjection kind
  -> ModelIdentity
  -> [Word64]
  -> [BindingFailure]
bindingFailuresFor projection identity observedSeeds =
  identityFailuresFor projection identity
    <> fmap
      BindingSeedCohort
      ( checkSeedCoverage
          (runPlanSeeds (ProductMatrix.productProjectionRunPlan projection))
          observedSeeds
      )

-- | Every identity comparison, expected values taken from the validated
-- projection.
identityFailuresFor
  :: ProductMatrix.ProductProjection kind
  -> ModelIdentity
  -> [BindingFailure]
identityFailuresFor projection identity =
  concat
    [ expectText BindingRowId expectedRowId (identityRowIdValue identity)
    , expectPlan BindingJournalPlan (identityPlanIdValue identity)
    , expectPlan BindingCompletionPlan (rciPlanId completion)
    , invocationFailures
    , expectLane BindingJournalLane (identityLaneValue identity)
    , deviceFailures
    , expectText BindingJournalExperiment expectedExperiment (identityExperimentHashValue identity)
    , expectText BindingCompletionExperiment expectedExperiment (rciExperimentHash completion)
    , canonicalDigest BindingAdmittedManifest (identityManifestShaValue identity)
    , canonicalDigest BindingInferenceManifest (identityInferenceManifestShaValue identity)
    , [ BindingMismatch
          BindingInferenceManifest
          (identityManifestShaValue identity)
          (identityInferenceManifestShaValue identity)
      | identityManifestShaValue identity /= identityInferenceManifestShaValue identity
      ]
    , expectText BindingContractDigest expectedContract (identityContractDigestValue identity)
    , canonicalDigest BindingCompletionJournalDigest (identityCompletionJournalDigestValue identity)
    , canonicalDigest BindingMeasuredDigest (identityMeasuredDigestValue identity)
    , [ BindingMismatch
          BindingMeasuredDigest
          (identityRecomputedMeasuredDigestValue identity)
          (identityMeasuredDigestValue identity)
      | identityRecomputedMeasuredDigestValue identity /= identityMeasuredDigestValue identity
      ]
    ]
 where
  completion = identityCompletionValue identity
  expectedRowId = ProductMatrix.productProjectionRowId projection
  expectedPlan = ProductMatrix.productProjectionPlanId projection
  expectedLane = ProductMatrix.productProjectionSubstrate projection
  expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
  expectedContract = Report.productScenarioProjectionContractDigest projection
  expectText field expected observed =
    [BindingMismatch field expected observed | expected /= observed]
  expectPlan field observed =
    [ BindingMismatch field (planIdText expectedPlan) (planIdText observed)
    | expectedPlan /= observed
    ]
  expectLane field observed =
    [ BindingMismatch field (renderSubstrate expectedLane) (renderSubstrate observed)
    | expectedLane /= observed
    ]
  canonicalDigest field value =
    [BindingDigestMalformed field value | not (isCanonicalSha256 value)]
  invocationFailures =
    case rciInvocation completion of
      Nothing -> [BindingMissing BindingInvocationRow]
      Just invocation ->
        expectText BindingInvocationRow expectedRowId (riiRowId invocation)
          <> expectPlan BindingInvocationPlan (riiPlanId invocation)
          <> expectLane BindingInvocationLane (riiSubstrate invocation)
  deviceFailures =
    case rciDeviceSubstrate completion of
      Nothing -> [BindingMissing BindingDeviceWitnessLane]
      Just lane -> expectLane BindingDeviceWitnessLane lane

isCanonicalSha256 :: Text -> Bool
isCanonicalSha256 value =
  Text.length value == 64
    && Text.all (`elem` ("0123456789abcdef" :: String)) value

-- ---------------------------------------------------------------------------
-- Typed join

-- | Join raw evidence against one validated projection batch. Batch
-- construction owns raw-row projection; this join owns evidence coverage. The
-- join-level checks mirror 'Report.projectCompletedProductScenarioReport'
-- (missing, duplicate, orphan, wrong plan, wrong lane, stale contract); only
-- when they all pass is each row minted, and per-row failures then accumulate.
joinModelEvidence
  :: ProductMatrix.ProductProjectionBatch
  -> [RawModelEvidence]
  -> Either (NonEmpty ModelEvidenceError) ModelEvidenceSet
joinModelEvidence batch observed =
  case NonEmpty.nonEmpty joinFailures of
    Just errors -> Left errors
    Nothing ->
      case NonEmpty.nonEmpty rowFailures of
        Just errors -> Left errors
        Nothing ->
          Right
            ModelEvidenceSet
              { evidenceSetLaneValue = lane
              , evidenceSetRowsValue = rights minted
              }
 where
  lane = ProductMatrix.productProjectionBatchSubstrate batch
  projections = ProductMatrix.productProjectionBatchProjections batch
  expected = fmap projectedIdentity projections
  expectedRowIds = ProductMatrix.productProjectionBatchRowIds batch
  observedRowIds = fmap rmeRowId observed
  missingFailures =
    [ MissingModelEvidence rowId planId
    | (rowId, planId, _contract) <- expected
    , rowId `notElem` observedRowIds
    ]
  duplicateFailures =
    [ DuplicateModelEvidence rowId
    | rowId <- repeatedTexts observedRowIds
    ]
  orphanFailures =
    [ OrphanModelEvidence (rmeRowId evidence) (rmePlanId evidence)
    | evidence <- observed
    , rmeRowId evidence `notElem` expectedRowIds
    ]
  wrongPlanFailures =
    [ WrongPlanModelEvidence rowId expectedPlan (rmePlanId evidence)
    | evidence <- observed
    , let rowId = rmeRowId evidence
    , Just expectedPlan <- [lookupPlan rowId]
    , rmePlanId evidence /= expectedPlan
    ]
  wrongLaneFailures =
    [ WrongLaneModelEvidence (rmeRowId evidence) lane (rmeLane evidence)
    | evidence <- observed
    , rmeRowId evidence `elem` expectedRowIds
    , rmeLane evidence /= lane
    ]
  staleContractFailures =
    [ StaleContractModelEvidence rowId
    | evidence <- observed
    , let rowId = rmeRowId evidence
    , Just expectedContract <- [lookupContract rowId]
    , rmeContractDigest evidence /= expectedContract
    ]
  joinFailures =
    missingFailures
      <> duplicateFailures
      <> orphanFailures
      <> wrongPlanFailures
      <> wrongLaneFailures
      <> staleContractFailures
  lookupPlan rowId = lookup rowId [(row, plan) | (row, plan, _) <- expected]
  lookupContract rowId = lookup rowId [(row, contract) | (row, _, contract) <- expected]
  minted =
    [ mintRow someProjection evidence
    | someProjection <- projections
    , evidence <- take 1 (matching someProjection)
    ]
  matching someProjection =
    [ evidence
    | evidence <- observed
    , rmeRowId evidence == someProjectionRowId someProjection
    ]
  mintRow (ProductMatrix.SomeProductProjection witness projection) evidence =
    case refineModelRowEvidence projection evidence of
      Left errors ->
        Left (RowEvidenceRejected (rmeRowId evidence) errors)
      Right refined -> Right (SomeModelRowEvidence witness refined)
  rowFailures = lefts minted
  projectedIdentity (ProductMatrix.SomeProductProjection _ projection) =
    ( ProductMatrix.productProjectionRowId projection
    , ProductMatrix.productProjectionPlanId projection
    , Report.productScenarioProjectionContractDigest projection
    )
  repeatedTexts values =
    [ value
    | group@(value : _) <- List.group (List.sort values)
    , length group > 1
    ]

someProjectionRowId :: ProductMatrix.SomeProductProjection -> Text
someProjectionRowId (ProductMatrix.SomeProductProjection _ projection) =
  ProductMatrix.productProjectionRowId projection

-- ---------------------------------------------------------------------------
-- Assertions

-- | Median across a non-empty seed cohort. Odd cardinality takes the middle
-- value; even cardinality takes the mean of the two middle values.
cohortMedian :: NonEmpty Double -> Double
cohortMedian values =
  case splitAt half ascending of
    (lowerHalf, upper : _)
      | even count
      , lower : _ <- reverse lowerHalf ->
          lower / 2 + upper / 2
      | otherwise -> upper
    (_, []) -> NonEmpty.head sorted
 where
  sorted = NonEmpty.sort values
  ascending = NonEmpty.toList sorted
  count = length ascending
  half = count `div` 2

-- | Grade per-seed final observations against the independent criteria.
-- Structure is checked per seed and per criterion (exactly one observation,
-- the criterion's rule and threshold agree, no unexpected metric); the cohort
-- statistic (the median across seeds of each criterion's value) is then
-- graded with the criterion's own rule. For a singleton cohort the statistic
-- is the single value.
gradeCohortCriteria
  :: NonEmpty ExternalBars.ExternalCriterion
  -> [(Word64, [Budget.RawConvergenceObservation])]
  -> [FinalQualityFailure]
gradeCohortCriteria criteria seeds =
  concatMap gradeCriterion (NonEmpty.toList criteria) <> unexpected
 where
  criterionNames = fmap ExternalBars.externalCriterionName (NonEmpty.toList criteria)
  unexpected =
    [ UnexpectedMetric seed name
    | (seed, observations) <- seeds
    , observation <- observations
    , let name = Budget.rawCriterionName observation
    , name `notElem` criterionNames
    ]
  gradeCriterion criterion =
    structural <> statisticFailures
   where
    name = ExternalBars.externalCriterionName criterion
    perSeed =
      [ (seed, filter ((== name) . Budget.rawCriterionName) observations)
      | (seed, observations) <- seeds
      ]
    structural =
      concat
        [ case matches of
            [] -> [MissingMetric seed name]
            [observation] -> mismatchFailures seed criterion observation
            _ : _ : _ -> [DuplicateMetric seed name]
        | (seed, matches) <- perSeed
        ]
    usable = [Budget.rawMeasurementValue observation | (_, [observation]) <- perSeed]
    statisticFailures =
      [ BelowBar name statistic criterion
      | length usable == length seeds
      , Just values <- [NonEmpty.nonEmpty usable]
      , let statistic = cohortMedian values
      , not (ExternalBars.externalCriterionPasses criterion statistic)
      ]

mismatchFailures
  :: Word64
  -> ExternalBars.ExternalCriterion
  -> Budget.RawConvergenceObservation
  -> [FinalQualityFailure]
mismatchFailures seed criterion observation =
  [ CriterionMismatch
      seed
      (ExternalBars.externalCriterionName criterion)
      (ExternalBars.externalCriterionRule criterion, ExternalBars.externalCriterionThreshold criterion)
      (Budget.rawCriterionRule observation, Budget.rawCriterionThreshold observation)
  | Budget.rawCriterionRule observation /= ExternalBars.externalCriterionRule criterion
      || Budget.rawCriterionThreshold observation /= ExternalBars.externalCriterionThreshold criterion
  ]

-- | Grade the final-quality channel. The criterion is re-derived from the
-- canonical tables by row identity ('ExternalBars.externalCriteriaFor'), the
-- registry bar carried by the projection must agree with it, and each seed's
-- recorded criterion must equal it before the cohort statistic is graded.
assertModelConvergence :: ModelRowEvidence kind -> [FinalQualityFailure]
assertModelConvergence evidence =
  case ExternalBars.externalCriteriaFor
    (identityRowIdValue (evidenceIdentityValue evidence))
    (evidenceRowClassValue evidence) of
    Left reason -> [NoIndependentCriterion reason]
    Right criteria ->
      registryBarDrift (NonEmpty.head criteria) (evidenceRegistryBarValue evidence)
        <> gradeCohortCriteria
          criteria
          [ (seedEvidenceSeedValue seed, finalQualityObservationsValue (seedEvidenceFinalQualityValue seed))
          | seed <- NonEmpty.toList (evidenceSeedsValue evidence)
          ]

-- | The registry bar a row carries must agree with the row's independently
-- derived primary criterion in metric name, comparison goal, and threshold;
-- any one of the three differing is drift.
registryBarDrift
  :: ExternalBars.ExternalCriterion
  -> ConvergenceBar
  -> [FinalQualityFailure]
registryBarDrift primary bar =
  [ RegistryBarDrift primary bar
  | convergenceMetricName bar /= ExternalBars.externalCriterionName primary
      || convergenceMetricGoal bar /= ExternalBars.externalCriterionGoal primary
      || convergenceThreshold bar /= ExternalBars.externalCriterionThreshold primary
  ]

-- | Grade the learning channel: the planned budget was consumed exactly and in
-- the plan's unit, updates were applied, and the learned weights moved. Where
-- the plan defines an exact optimizer-update quantity the count must equal it.
-- Nothing here reads the final-quality channel.
assertModelLearning :: ModelRowEvidence kind -> [LearningFailure]
assertModelLearning evidence =
  concatMap gradeSeed (NonEmpty.toList (evidenceSeedsValue evidence))
 where
  planned = ExternalBars.plannedWorkFor (evidenceResolvedPlanValue evidence)
  expectedKind = Budget.trainingBudgetKind (evidenceTrainingBudgetValue evidence)
  gradeSeed seedEvidence =
    let seed = seedEvidenceSeedValue seedEvidence
        telemetry = seedEvidenceLearningValue seedEvidence
        observedUnits = telemetryObservedUnitsValue telemetry
        updates = telemetryUpdateCountValue telemetry
        initialHash = telemetryInitialWeightHashValue telemetry
        finalHash = telemetryFinalWeightHashValue telemetry
     in [ UnitKindMismatch seed expectedKind (telemetryBudgetKindValue telemetry)
        | telemetryBudgetKindValue telemetry /= expectedKind
        ]
          <> [ ObservedUnitsMismatch seed (ExternalBars.plannedUnits planned) observedUnits
             | toInteger observedUnits /= ExternalBars.plannedUnits planned
             ]
          <> [NoOptimizerUpdates seed | updates == 0]
          <> [ WeightHashMissing seed
             | Text.null (Text.strip initialHash) || Text.null (Text.strip finalHash)
             ]
          <> [ WeightsUnchanged seed
             | not (Text.null (Text.strip initialHash))
             , initialHash == finalHash
             ]
          <> [ UpdateCountMismatch seed plannedUpdates updates
             | Just plannedUpdates <- [ExternalBars.plannedOptimizerUpdates planned]
             , toInteger updates /= plannedUpdates
             ]

-- | Grade committed performance bounds over the deterministic work counts the
-- completed run recorded. The bounds come from the plan alone
-- ('ExternalBars.performanceRequirementsFor'); the counts come from the
-- evidence. Both are bound to the same plan, experiment, and manifest
-- identity (see 'modelPerformanceReceipts').
assertModelPerformance :: ModelRowEvidence kind -> [PerformanceFailure]
assertModelPerformance evidence =
  concatMap gradeSeed (NonEmpty.toList (evidenceSeedsValue evidence))
 where
  plan = evidenceResolvedPlanValue evidence
  requirements = ExternalBars.performanceRequirementsFor plan
  gradeSeed seedEvidence =
    gradePerformanceObservations
      (seedEvidenceSeedValue seedEvidence)
      requirements
      (ExternalBars.performanceObservationsFor plan (completedWorkOf seedEvidence))

-- | Grade one seed's recorded work counts against committed requirements. A
-- requirement whose metric the completed run did not record is a typed
-- failure, never a pass, and a recorded count that violates its bound names
-- the metric, the bound, and the count.
gradePerformanceObservations
  :: Word64
  -> [ExternalBars.PerformanceRequirement]
  -> [(ExternalBars.PerformanceMetric, Integer)]
  -> [PerformanceFailure]
gradePerformanceObservations seed requirements observations =
  concat
    [ case lookup metric observations of
        Nothing -> [PerformanceMetricUnmeasured seed metric]
        Just observed
          | ExternalBars.performanceBoundHolds bound observed -> []
          | otherwise -> [PerformanceBoundViolated seed metric bound observed]
    | ExternalBars.PerformanceRequirement metric bound <- requirements
    ]

completedWorkOf :: SeedEvidence -> ExternalBars.CompletedWork
completedWorkOf seedEvidence =
  ExternalBars.CompletedWork
    { ExternalBars.completedWorkObservedUnits = telemetryObservedUnitsValue telemetry
    , ExternalBars.completedWorkOptimizerUpdates = telemetryUpdateCountValue telemetry
    }
 where
  telemetry = seedEvidenceLearningValue seedEvidence

-- | A performance measurement bound to the completed artifact and plan it was
-- taken from: the row's PlanId, experiment hash, and admitted manifest identity
-- from the same lane-journal row.
data PerformanceReceipt = PerformanceReceipt
  { receiptRowId :: !Text
  , receiptPlanId :: !PlanId
  , receiptExperimentHash :: !Text
  , receiptManifestSha :: !Text
  , receiptSeed :: !Word64
  , receiptMetric :: !ExternalBars.PerformanceMetric
  , receiptBound :: !ExternalBars.PerformanceBound
  , receiptObserved :: !Integer
  }
  deriving stock (Eq, Show)

modelPerformanceReceipts :: ModelRowEvidence kind -> [PerformanceReceipt]
modelPerformanceReceipts evidence =
  [ PerformanceReceipt
      { receiptRowId = modelEvidenceRowId evidence
      , receiptPlanId = modelEvidencePlanId evidence
      , receiptExperimentHash = modelEvidenceExperimentHash evidence
      , receiptManifestSha = modelEvidenceManifestSha evidence
      , receiptSeed = seedEvidenceSeedValue seedEvidence
      , receiptMetric = metric
      , receiptBound = bound
      , receiptObserved = observed
      }
  | seedEvidence <- NonEmpty.toList (evidenceSeedsValue evidence)
  , let observations =
          ExternalBars.performanceObservationsFor plan (completedWorkOf seedEvidence)
  , ExternalBars.PerformanceRequirement metric bound <- requirements
  , Just observed <- [lookup metric observations]
  ]
 where
  plan = evidenceResolvedPlanValue evidence
  requirements = ExternalBars.performanceRequirementsFor plan

-- | Bind performance receipts to the completed artifact they were taken from.
-- The journal row is the /admitted/ one, read through the journal's own
-- accessors rather than through the evidence value: every receipt must carry
-- that row's id, PlanId, experiment hash, and admitted manifest identity, each
-- compared on its own so that a receipt for any other row, plan, experiment, or
-- manifest names exactly the identity it differs on. A row with no receipt has
-- nothing bound to it and fails.
assertReceiptBinding
  :: Lane.ProductLaneJournalRow
  -> [PerformanceReceipt]
  -> [ReceiptBindingFailure]
assertReceiptBinding row receipts =
  [NoPerformanceReceipt (Lane.productLaneJournalRowRowId row) | null receipts]
    <> List.nub (concatMap mismatches receipts)
 where
  mismatches receipt =
    concat
      [ differ
          BindingRowId
          (Lane.productLaneJournalRowRowId row)
          (receiptRowId receipt)
      , differ
          BindingJournalPlan
          (planIdText (Lane.productLaneJournalRowPlanId row))
          (planIdText (receiptPlanId receipt))
      , differ
          BindingJournalExperiment
          (Lane.productLaneJournalRowExperimentHash row)
          (receiptExperimentHash receipt)
      , differ
          BindingAdmittedManifest
          (Lane.productLaneJournalRowManifestSha row)
          (receiptManifestSha receipt)
      ]
  differ field expected observed =
    [ReceiptNotBound field expected observed | expected /= observed]

-- | Re-verify identity and cohort coverage against a projection. The evidence
-- was already bound when it was minted; this makes a per-row binding case fail
-- if the evidence is offered against any other projection.
assertModelBinding
  :: ProductMatrix.ProductProjection kind
  -> ModelRowEvidence kind
  -> [BindingFailure]
assertModelBinding projection evidence =
  bindingFailuresFor
    projection
    (evidenceIdentityValue evidence)
    (modelEvidenceSeeds evidence)

-- | 'assertModelBinding' across the existential wrappers. Evidence of one run
-- kind offered for a projection of another is a 'BindingRunKind' mismatch.
assertSomeModelBinding
  :: ProductMatrix.SomeProductProjection
  -> SomeModelRowEvidence
  -> [BindingFailure]
assertSomeModelBinding
  (ProductMatrix.SomeProductProjection projectionWitness projection)
  (SomeModelRowEvidence evidenceWitness evidence) =
    case (projectionWitness, evidenceWitness) of
      (SupervisedTrainingWitness, SupervisedTrainingWitness) -> assertModelBinding projection evidence
      (ReinforcementLearningWitness, ReinforcementLearningWitness) -> assertModelBinding projection evidence
      (HyperparameterTuningWitness, HyperparameterTuningWitness) -> assertModelBinding projection evidence
      (AlphaZeroSelfPlayWitness, AlphaZeroSelfPlayWitness) -> assertModelBinding projection evidence
      _ ->
        [ BindingMismatch
            BindingRunKind
            (renderKindWitness projectionWitness)
            (renderKindWitness evidenceWitness)
        ]

renderKindWitness :: RunKindWitness kind -> Text
renderKindWitness witness =
  case witness of
    SupervisedTrainingWitness -> "supervised-training"
    ReinforcementLearningWitness -> "reinforcement-learning"
    HyperparameterTuningWitness -> "hyperparameter-tuning"
    AlphaZeroSelfPlayWitness -> "alphazero-self-play"

-- | Every assertion family for one row, as distinct constructors.
assertModelRowEvidence
  :: ProductMatrix.ProductProjection kind
  -> ModelRowEvidence kind
  -> [ModelAssertionFailure]
assertModelRowEvidence projection evidence =
  fmap FinalQualityFailed (assertModelConvergence evidence)
    <> fmap LearningFailed (assertModelLearning evidence)
    <> fmap PerformanceFailed (assertModelPerformance evidence)
    <> fmap BindingFailed (assertModelBinding projection evidence)

-- | 'assertModelRowEvidence' across the existential wrappers. Evidence of one
-- run kind offered for a projection of another is a 'BindingRunKind' mismatch.
assertSomeModelRowEvidence
  :: ProductMatrix.SomeProductProjection
  -> SomeModelRowEvidence
  -> [ModelAssertionFailure]
assertSomeModelRowEvidence
  (ProductMatrix.SomeProductProjection projectionWitness projection)
  (SomeModelRowEvidence evidenceWitness evidence) =
    case (projectionWitness, evidenceWitness) of
      (SupervisedTrainingWitness, SupervisedTrainingWitness) -> assertModelRowEvidence projection evidence
      (ReinforcementLearningWitness, ReinforcementLearningWitness) -> assertModelRowEvidence projection evidence
      (HyperparameterTuningWitness, HyperparameterTuningWitness) -> assertModelRowEvidence projection evidence
      (AlphaZeroSelfPlayWitness, AlphaZeroSelfPlayWitness) -> assertModelRowEvidence projection evidence
      _ ->
        [ BindingFailed
            ( BindingMismatch
                BindingRunKind
                (renderKindWitness projectionWitness)
                (renderKindWitness evidenceWitness)
            )
        ]

-- ---------------------------------------------------------------------------
-- Loading admitted lane journals

-- | A lane's validated projection and the journal admitted against it by the
-- pinned production reader.
data LoadedLane = LoadedLane
  { loadedLaneBatch :: !ProductMatrix.ProductProjectionBatch
  , loadedLaneJournal :: !Lane.AdmittedProductLaneJournal
  }

-- | A loaded lane together with the evidence minted from it.
data LaneEvidence = LaneEvidence
  { laneEvidenceLoaded :: !LoadedLane
  , laneEvidenceSet :: !ModelEvidenceSet
  }

-- | Read the lane's registered, pinned journal ('productLaneInputs') and admit
-- it against the current projection with 'Lane.admitProductLaneJournal'. A
-- missing, altered, non-canonical, or stale journal is a typed error.
loadLaneJournal :: Substrate -> IO (Either ModelEvidenceLoadError LoadedLane)
loadLaneJournal = loadLaneJournalIn productLaneInputs ProductMatrix.allProductRows

-- | 'loadLaneJournal' over an explicit registry of pinned journal inputs and an
-- explicit ProductRow registry. Production reads through 'loadLaneJournal' with
-- the committed pins and the committed registry; this seam exists only so that
-- each fail-closed path (no registered input, an unreadable journal, a registry
-- that does not project, a journal the pinned production reader rejects) can be
-- offered a defective input by the mutation controls. It is exported through
-- "JitML.Test.ModelEvidence.Raw", not through the safe facade: a caller-chosen
-- pin can authenticate any internally valid journal.
loadLaneJournalIn
  :: [ProductLaneInput]
  -> [ProductMatrix.ProductRow state]
  -> Substrate
  -> IO (Either ModelEvidenceLoadError LoadedLane)
loadLaneJournalIn inputs rows substrate =
  case List.find ((== substrate) . productLaneInputSubstrate) inputs of
    Nothing -> pure (Left (LaneJournalNotRegistered substrate))
    Just input -> do
      let path = productLaneInputPath input
          pinned = productLaneInputSha256 input
      read' <- tryIO (ByteString.readFile path)
      pure $
        case read' of
          Left exception ->
            Left (LaneJournalUnreadable path (Text.pack (show exception)))
          Right bytes ->
            case ProductMatrix.projectProductRows substrate rows of
              Failure errors -> Left (LaneProjectionRejected substrate errors)
              Success batch ->
                case Lane.admitProductLaneJournal pinned batch bytes of
                  Left errors -> Left (LaneJournalRejected substrate path pinned errors)
                  Right journal -> Right (LoadedLane batch journal)

-- | Mint evidence for every row of an admitted lane journal through the typed
-- join.
admitLaneEvidence :: LoadedLane -> Either ModelEvidenceLoadError LaneEvidence
admitLaneEvidence loaded =
  case joinModelEvidence
    (loadedLaneBatch loaded)
    (rawModelEvidenceFromJournal (loadedLaneJournal loaded)) of
    Left errors ->
      Left
        ( LaneEvidenceRejected
            (ProductMatrix.productProjectionBatchSubstrate (loadedLaneBatch loaded))
            errors
        )
    Right set -> Right (LaneEvidence loaded set)

admitModelEvidence :: Substrate -> IO (Either ModelEvidenceLoadError LaneEvidence)
admitModelEvidence substrate = do
  loaded <- loadLaneJournal substrate
  pure (loaded >>= admitLaneEvidence)

tryIO :: IO value -> IO (Either IOException value)
tryIO = try

-- ---------------------------------------------------------------------------
-- Rendering

renderModelEvidenceLoadError :: ModelEvidenceLoadError -> Text
renderModelEvidenceLoadError err =
  case err of
    LaneJournalNotRegistered lane ->
      "no lane journal is registered for " <> renderSubstrate lane
    LaneJournalUnreadable path detail ->
      "lane journal " <> Text.pack path <> " is unreadable: " <> detail
    LaneProjectionRejected lane errors ->
      "the current registry does not project for "
        <> renderSubstrate lane
        <> ": "
        <> joinLines (fmap ProductMatrix.renderProductMatrixError (NonEmpty.toList errors))
    LaneJournalRejected lane path pinned errors ->
      "the pinned "
        <> renderSubstrate lane
        <> " lane journal is inadmissible under the current projection (path "
        <> Text.pack path
        <> ", pinned sha256 "
        <> pinned
        <> "): "
        <> joinLines (fmap renderJournalError (NonEmpty.toList errors))
    LaneEvidenceRejected lane errors ->
      "the admitted "
        <> renderSubstrate lane
        <> " lane journal does not join into per-model evidence: "
        <> joinLines (fmap renderModelEvidenceError (NonEmpty.toList errors))

-- | A one-line form of 'renderModelEvidenceLoadError' for the many cases that
-- depend on one lane: the full diagnostic is reported once by the admission
-- case, and each dependent case names the first reason and how many there are.
renderModelEvidenceLoadHeadline :: ModelEvidenceLoadError -> Text
renderModelEvidenceLoadHeadline err =
  case err of
    LaneJournalRejected lane _ _ errors ->
      "no admitted "
        <> renderSubstrate lane
        <> " evidence: the pinned lane journal is inadmissible ("
        <> showText (length errors)
        <> " error(s); first: "
        <> renderJournalError (NonEmpty.head errors)
        <> ")"
    LaneEvidenceRejected lane errors ->
      "no admitted "
        <> renderSubstrate lane
        <> " evidence: the journal does not join ("
        <> showText (length errors)
        <> " error(s); first: "
        <> renderModelEvidenceError (NonEmpty.head errors)
        <> ")"
    LaneJournalNotRegistered _ -> renderModelEvidenceLoadError err
    LaneJournalUnreadable _ _ -> renderModelEvidenceLoadError err
    LaneProjectionRejected _ _ -> renderModelEvidenceLoadError err

-- | The reason text of one journal rejection. Only the free-text source
-- rejection carries a sentence of its own; every other rejection is rendered
-- from its typed shape. That keeps this renderer independent of the closed set
-- of 'Lane.ProductLaneJournalError' constructors: a constructor the journal
-- module gains later (for example a typed stale-contract rejection) is still
-- rendered, exactly and totally, instead of breaking this module's build.
renderJournalError :: Lane.ProductLaneJournalError -> Text
renderJournalError err =
  case err of
    Lane.ProductLaneJournalSourceRejected detail -> detail
    other -> showText other

renderModelEvidenceError :: ModelEvidenceError -> Text
renderModelEvidenceError err =
  case err of
    MissingModelEvidence rowId planId ->
      "missing evidence for row " <> rowId <> " (expected plan " <> planIdText planId <> ")"
    DuplicateModelEvidence rowId -> "duplicate evidence for row " <> rowId
    OrphanModelEvidence rowId planId ->
      "orphan evidence for " <> rowId <> " (plan " <> planIdText planId <> ") is not a projected row"
    WrongPlanModelEvidence rowId expected observed ->
      "cross-plan evidence for row "
        <> rowId
        <> ": expected plan "
        <> planIdText expected
        <> ", observed "
        <> planIdText observed
    WrongLaneModelEvidence rowId expected observed ->
      "wrong-lane evidence for row "
        <> rowId
        <> ": expected "
        <> renderSubstrate expected
        <> ", observed "
        <> renderSubstrate observed
    StaleContractModelEvidence rowId ->
      "stale contract digest on evidence for row " <> rowId
    RowEvidenceRejected rowId errors ->
      "row "
        <> rowId
        <> " evidence rejected: "
        <> joinLines (fmap renderRowEvidenceError (NonEmpty.toList errors))

renderRowEvidenceError :: RowEvidenceError -> Text
renderRowEvidenceError err =
  case err of
    RowBindingRejected failure -> renderBindingFailure failure
    RowNonFiniteEvidence seed name field ->
      "seed " <> showText seed <> ": " <> name <> " " <> field <> " is not finite"
    RowChannelSubstituted seed slot channel ->
      "seed "
        <> showText seed
        <> ": a "
        <> renderChannel channel
        <> " payload was offered as "
        <> renderSlot slot
        <> " evidence"

renderChannel :: EvidenceChannel -> Text
renderChannel channel =
  case channel of
    LearningIterationChannel -> "learning-iteration"
    FinalEvaluationChannel -> "final-evaluation"

renderSlot :: EvidenceSlot -> Text
renderSlot slot =
  case slot of
    LearningSlot -> "learning-telemetry"
    FinalQualitySlot -> "final-quality"

renderBindingFailure :: BindingFailure -> Text
renderBindingFailure failure =
  case failure of
    BindingMismatch field expected observed ->
      showText field <> " mismatch: expected " <> expected <> ", observed " <> observed
    BindingMissing field -> showText field <> " is missing"
    BindingDigestMalformed field value ->
      showText field <> " is not a canonical SHA-256: " <> value
    BindingSeedCohort issue -> "seed cohort: " <> renderSeedIssue issue

renderSeedIssue :: SeedCoverageIssue -> Text
renderSeedIssue issue =
  case issue of
    EmptySeedCohort -> "no seed evidence"
    MissingSeedEvidence seed -> "planned seed " <> showText seed <> " has no evidence"
    DuplicateSeedEvidence seed -> "seed " <> showText seed <> " has more than one evidence record"
    UnplannedSeedEvidence seed -> "seed " <> showText seed <> " is not in the plan's cohort"

renderFinalQualityFailure :: FinalQualityFailure -> Text
renderFinalQualityFailure failure =
  case failure of
    NoIndependentCriterion reason -> "no independent criterion: " <> reason
    RegistryBarDrift primary bar ->
      "registry bar "
        <> convergenceMetricName bar
        <> " (threshold "
        <> showText (convergenceThreshold bar)
        <> ") disagrees with the canonical table criterion "
        <> renderCriterion primary
    MissingMetric seed name -> "seed " <> showText seed <> ": missing metric " <> name
    DuplicateMetric seed name -> "seed " <> showText seed <> ": duplicate metric " <> name
    UnexpectedMetric seed name -> "seed " <> showText seed <> ": unexpected metric " <> name
    CriterionMismatch seed name expected observed ->
      "seed "
        <> showText seed
        <> ": recorded criterion for "
        <> name
        <> " is "
        <> showText observed
        <> ", the canonical table requires "
        <> showText expected
    BelowBar name statistic criterion ->
      name
        <> " cohort statistic "
        <> showText statistic
        <> " fails the canonical criterion "
        <> renderCriterion criterion

renderCriterion :: ExternalBars.ExternalCriterion -> Text
renderCriterion criterion =
  ExternalBars.externalCriterionName criterion
    <> " "
    <> showText (ExternalBars.externalCriterionRule criterion)
    <> " "
    <> showText (ExternalBars.externalCriterionThreshold criterion)

renderLearningFailure :: LearningFailure -> Text
renderLearningFailure failure =
  case failure of
    UnitKindMismatch seed expected observed ->
      "seed "
        <> showText seed
        <> ": budget unit "
        <> Budget.renderBudgetKind observed
        <> " differs from the plan's "
        <> Budget.renderBudgetKind expected
    ObservedUnitsMismatch seed planned observed ->
      "seed "
        <> showText seed
        <> ": observed "
        <> showText observed
        <> " budget units, the plan requires exactly "
        <> showText planned
    NoOptimizerUpdates seed -> "seed " <> showText seed <> ": no optimizer update was applied"
    WeightHashMissing seed -> "seed " <> showText seed <> ": an initial or final weight hash is missing"
    WeightsUnchanged seed ->
      "seed " <> showText seed <> ": final weights equal the initial weights"
    UpdateCountMismatch seed planned observed ->
      "seed "
        <> showText seed
        <> ": observed "
        <> showText observed
        <> " optimizer updates, the plan requires exactly "
        <> showText planned

renderPerformanceFailure :: PerformanceFailure -> Text
renderPerformanceFailure failure =
  case failure of
    PerformanceBoundViolated seed metric bound observed ->
      "seed "
        <> showText seed
        <> ": "
        <> ExternalBars.renderPerformanceMetric metric
        <> " = "
        <> showText observed
        <> " violates the committed bound ("
        <> ExternalBars.renderPerformanceBound bound
        <> ")"
    PerformanceMetricUnmeasured seed metric ->
      "seed "
        <> showText seed
        <> ": "
        <> ExternalBars.renderPerformanceMetric metric
        <> " is not recorded by the completed run"

renderReceiptBindingFailure :: ReceiptBindingFailure -> Text
renderReceiptBindingFailure failure =
  case failure of
    NoPerformanceReceipt rowId -> "no performance receipt was produced for row " <> rowId
    ReceiptNotBound field expected observed ->
      "performance receipt is not bound to the admitted journal row: "
        <> showText field
        <> " is "
        <> expected
        <> " in the journal row, "
        <> observed
        <> " on the receipt"

renderModelAssertionFailure :: ModelAssertionFailure -> Text
renderModelAssertionFailure failure =
  case failure of
    FinalQualityFailed inner -> "final quality: " <> renderFinalQualityFailure inner
    LearningFailed inner -> "learning: " <> renderLearningFailure inner
    PerformanceFailed inner -> "performance: " <> renderPerformanceFailure inner
    BindingFailed inner -> "binding: " <> renderBindingFailure inner

joinLines :: [Text] -> Text
joinLines = Text.intercalate "; "

showText :: (Show value) => value -> Text
showText = Text.pack . show

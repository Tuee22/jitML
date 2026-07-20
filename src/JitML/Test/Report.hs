{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( BlockedBy
  , CompletedProductScenarioEvidence
  , CompletedProductScenarioReport
  , InvocationJournal
  , InvocationRecord
  , InvocationResult (..)
  , ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , ReportCardKnobs (..)
  , SuiteResult
  , SuiteStatus (..)
  , ProductRowReportEvidence (..)
  , ProductScenarioCompletion
  , ProductScenarioCompletionError (..)
  , ProductScenarioEvidenceError (..)
  , ProductScenarioReportError (..)
  , RowIntegrationEvidence (..)
  , aggregateProductLaneAttestations
  , appendInvocation
  , appendInvocationJournal
  , blockedByFailure
  , blockedByStanza
  , completedProductScenarioEvidence
  , completedProductScenarioLane
  , completedProductScenarioManifestSha
  , completedProductScenarioPlanId
  , completedProductScenarioRowId
  , defaultReportCardKnobs
  , deriveSuiteResult
  , emptyInvocationJournal
  , emptyReportMeasurements
  , failedInvocation
  , failedObservedInvocation
  , firstInvocationFailure
  , firstObservedInvocationFailure
  , invocationCommand
  , invocationJournalEntries
  , invocationResult
  , invocationStanza
  , loadAggregatedProductLaneAttestations
  , loadReportCardKnobs
  , notRunInvocation
  , notRunObservedInvocation
  , parseReportCardKnobs
  , passedInvocation
  , parseProductRowReportEvidenceTable
  , productScenarioCompletion
  , projectCompletedProductScenarioReport
  , productRowReportCoverageFailures
  , productLaneAttestationFailures
  , renderReportCardWithKnobs
  , renderProductRowReportEvidence
  , renderCompletedProductScenarioEvidence
  , renderRowIntegrationEvidence
  , reportStanzas
  , rowIntegrationCoverageFailures
  , suiteDuration
  , suiteFailed
  , suiteNotRun
  , suitePassed
  , suiteStatus
  , substrateRuntimeStanzas
  , substratePartitionedStanzas
  , substrateTestInvocations
  , renderReportCard
  )
where

import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import System.Exit (ExitCode (..))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Plan.Plan (PlanId, planIdText, quantityValue)
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence
  ( convergenceMetricGoal
  , convergenceMetricName
  , convergenceThreshold
  )
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.Architecture (ArchitectureFeature)
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessAttemptFailure (..)
  , ProcessDuration (..)
  , ProcessFailure
  , ProcessTranscript (..)
  , observedProcessFailureCommand
  , observedProcessFailureDuration
  , processFailureDuration
  , processFailureExitCode
  , processFailureStderr
  , processFailureStdout
  , processFailureWorkingDirectory
  )
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.LiveWorkflow
  ( CompletedRunEvidence
  , completedRunEvidence
  , completedRunPlanId
  )
import JitML.Test.RowAssertions qualified as RowAssertions
import JitML.Test.ScenarioJournal
  ( ScenarioDisposition (..)
  , ScenarioIssue
  , ScenarioJournal
  , ScenarioPhase (..)
  , ScenarioRecord
  , scenarioIssueDetail
  , scenarioIssuePhase
  , scenarioIssueStep
  , scenarioJournalIssues
  , scenarioJournalName
  , scenarioJournalRecords
  , scenarioRecordDisposition
  , scenarioRecordOutcome
  , scenarioRecordPhase
  , scenarioRecordStep
  )
import JitML.Training.Budget
  ( BudgetKind (..)
  , MetricGoal
  , TrainingBudget
  , coMetricGoal
  , coMetricName
  , coThreshold
  , completedTrainingBudget
  , completedTrainingMetrics
  , completedTrainingPlanId
  , completedTrainingUpdateCount
  , trainingBudgetKind
  )

-- | The observed result of one planned test-stanza invocation. A successful
-- invocation retains its complete transcript, a failure retains either the
-- opaque non-zero process failure or the exact synchronous runner exception,
-- and fail-fast work records the failure that kept it from running.
data InvocationResult
  = Passed !ProcessTranscript
  | Failed !ObservedProcessFailure
  | NotRun !BlockedBy
  deriving stock (Eq, Show)

-- | Structured reason an invocation was not run. The blocker is the complete
-- observed failure rather than a reconstructed command or prose reason.
data BlockedBy = BlockedBy
  { blockerStanzaValue :: !Text
  , blockerFailureValue :: !ObservedProcessFailure
  }
  deriving stock (Eq, Show)

-- | One append-only journal row. For executed rows the command is derived from
-- the retained outcome. For 'NotRun' rows it is the exact rendered command that
-- would have run.
data InvocationRecord = InvocationRecord
  { recordStanzaValue :: !Text
  , recordCommandValue :: !Text
  , recordResultValue :: !InvocationResult
  }
  deriving stock (Eq, Show)

-- | Chronological invocation evidence. The constructor stays hidden so callers
-- can only append rows; they cannot rewrite or delete earlier observations.
newtype InvocationJournal = InvocationJournal
  { journalEntryValues :: [InvocationRecord]
  }
  deriving stock (Eq, Show)

-- | Aggregate values projected only from invocation evidence.
data SuiteStatus
  = SuitePassed
  | SuiteFailed
  | SuiteNotRun
  deriving stock (Eq, Show)

data SuiteResult = SuiteResult
  { suiteStatusValue :: !SuiteStatus
  , suitePassedValue :: !Int
  , suiteFailedValue :: !Int
  , suiteNotRunValue :: !Int
  , suiteDurationValue :: !ProcessDuration
  }
  deriving stock (Eq, Show)

-- Hidden constructors alone do not prevent record update when their selectors
-- are exported.  Keep the labels private and expose ordinary read-only
-- functions for every journal/result observation.
blockedByStanza :: BlockedBy -> Text
blockedByStanza = blockerStanzaValue

blockedByFailure :: BlockedBy -> ObservedProcessFailure
blockedByFailure = blockerFailureValue

invocationStanza :: InvocationRecord -> Text
invocationStanza = recordStanzaValue

invocationCommand :: InvocationRecord -> Text
invocationCommand = recordCommandValue

invocationResult :: InvocationRecord -> InvocationResult
invocationResult = recordResultValue

invocationJournalEntries :: InvocationJournal -> [InvocationRecord]
invocationJournalEntries = journalEntryValues

suiteStatus :: SuiteResult -> SuiteStatus
suiteStatus = suiteStatusValue

suitePassed :: SuiteResult -> Int
suitePassed = suitePassedValue

suiteFailed :: SuiteResult -> Int
suiteFailed = suiteFailedValue

suiteNotRun :: SuiteResult -> Int
suiteNotRun = suiteNotRunValue

suiteDuration :: SuiteResult -> ProcessDuration
suiteDuration = suiteDurationValue

data ReportCard = ReportCard
  { reportInvocationJournal :: !InvocationJournal
  , reportScenarioJournals :: ![ScenarioJournal]
  , reportMeasurements :: ReportMeasurements
  }
  deriving stock (Eq, Show)

emptyInvocationJournal :: InvocationJournal
emptyInvocationJournal = InvocationJournal []

appendInvocation :: InvocationJournal -> InvocationRecord -> InvocationJournal
appendInvocation (InvocationJournal entries) entry =
  InvocationJournal (entries <> [entry])

appendInvocationJournal :: InvocationJournal -> InvocationJournal -> InvocationJournal
appendInvocationJournal (InvocationJournal left) (InvocationJournal right) =
  InvocationJournal (left <> right)

passedInvocation :: Text -> ProcessTranscript -> InvocationRecord
passedInvocation stanza transcript =
  InvocationRecord
    { recordStanzaValue = stanza
    , recordCommandValue = processTranscriptCommand transcript
    , recordResultValue = Passed transcript
    }

failedInvocation :: Text -> ProcessFailure -> InvocationRecord
failedInvocation stanza failure =
  failedObservedInvocation stanza (ObservedProcessExitFailure failure)

failedObservedInvocation :: Text -> ObservedProcessFailure -> InvocationRecord
failedObservedInvocation stanza failure =
  InvocationRecord
    { recordStanzaValue = stanza
    , recordCommandValue = observedProcessFailureCommand failure
    , recordResultValue = Failed failure
    }

notRunInvocation :: Text -> Text -> Text -> ProcessFailure -> InvocationRecord
notRunInvocation stanza command blockerStanza blocker =
  notRunObservedInvocation
    stanza
    command
    blockerStanza
    (ObservedProcessExitFailure blocker)

notRunObservedInvocation
  :: Text
  -> Text
  -> Text
  -> ObservedProcessFailure
  -> InvocationRecord
notRunObservedInvocation stanza command blockerStanza blocker =
  InvocationRecord
    { recordStanzaValue = stanza
    , recordCommandValue = command
    , recordResultValue = NotRun (BlockedBy blockerStanza blocker)
    }

deriveSuiteResult :: InvocationJournal -> SuiteResult
deriveSuiteResult (InvocationJournal entries) =
  SuiteResult
    { suiteStatusValue = status
    , suitePassedValue = passed
    , suiteFailedValue = failed
    , suiteNotRunValue = notRun
    , suiteDurationValue =
        ProcessDuration
          (sum (fmap (invocationDurationNanoseconds . invocationResult) entries))
    }
 where
  passed = length [() | InvocationRecord {recordResultValue = Passed _} <- entries]
  failed = length [() | InvocationRecord {recordResultValue = Failed _} <- entries]
  notRun = length [() | InvocationRecord {recordResultValue = NotRun _} <- entries]
  status
    | failed > 0 = SuiteFailed
    | notRun > 0 || null entries = SuiteNotRun
    | otherwise = SuitePassed

firstInvocationFailure :: InvocationJournal -> Maybe ProcessFailure
firstInvocationFailure (InvocationJournal entries) =
  firstFailure entries
 where
  firstFailure [] = Nothing
  firstFailure
    ( InvocationRecord
        { recordResultValue = Failed (ObservedProcessExitFailure failure)
        }
        : _
      ) = Just failure
  firstFailure (InvocationRecord {recordResultValue = Failed _} : _) = Nothing
  firstFailure (_ : rest) = firstFailure rest

firstObservedInvocationFailure
  :: InvocationJournal
  -> Maybe ObservedProcessFailure
firstObservedInvocationFailure (InvocationJournal entries) =
  firstFailure entries
 where
  firstFailure [] = Nothing
  firstFailure (InvocationRecord {recordResultValue = Failed failure} : _) =
    Just failure
  firstFailure (_ : rest) = firstFailure rest

invocationDurationNanoseconds :: InvocationResult -> Word64
invocationDurationNanoseconds (Passed transcript) =
  processDurationNanoseconds (processTranscriptDuration transcript)
invocationDurationNanoseconds (Failed failure) =
  processDurationNanoseconds (observedProcessFailureDuration failure)
invocationDurationNanoseconds (NotRun _) = 0

data ReportMeasurement
  = MeasurementAvailable Text
  | MeasurementUnavailable
  deriving stock (Eq, Show)

data ReportMeasurements = ReportMeasurements
  { measuredSlFinalLoss :: Maybe ReportMeasurement
  , measuredRlFinalReward :: Maybe ReportMeasurement
  , measuredAlphaZeroArenaWinRate :: Maybe ReportMeasurement
  , measuredTuneBestObjective :: Maybe ReportMeasurement
  , measuredJitCacheHitRate :: Maybe ReportMeasurement
  , measuredDaemonHealthz :: Maybe ReportMeasurement
  , measuredBrowserProductMatrix :: Maybe ReportMeasurement
  -- ^ No-caveat browser/product matrix (Sprint 12.13): the live Playwright
  -- product run over every model/product interaction cell. Reports
  -- 'MeasurementUnavailable' until Phase `17` exercises the matrix live, so a
  -- live report card that has not proven the browser product surface fails the
  -- no-caveat handoff rather than vacuously omitting the row.
  , measuredProductRowEvidence :: Maybe CompletedProductScenarioReport
  -- ^ Opaque live-interpreter completion projections keyed by ProductRow and
  -- semantic PlanId. Empty means the report received no cross-process
  -- completed-scenario journal; declarations and legacy lane attestations are
  -- intentionally not accepted here.
  }
  deriving stock (Eq, Show)

data ReportCardKnobs = ReportCardKnobs
  { knobSlEpochs :: Int
  , knobSlBatch :: Int
  , knobRlSteps :: Int
  , knobRlEvalEpisodes :: Int
  , knobAzGames :: Int
  , knobAzSims :: Int
  , knobTuneTrials :: Int
  , knobTuneBudgetPerTrial :: Int
  , knobCrossClusterKindNodes :: Int
  }
  deriving stock (Eq, Show)

data RowIntegrationEvidence = RowIntegrationEvidence
  { rieRowId :: !Text
  , rieIntegrationTest :: !Text
  , rieFamily :: !Text
  , rieInitialParamHash :: !Text
  , rieFinalParamHash :: !Text
  , rieUpdateCount :: !Word64
  , rieObservedUnits :: !Word64
  , rieCompletedMetricNames :: ![Text]
  , rieCompletedTrainingPassed :: !Bool
  , rieDatasetShaAtRead :: !Text
  , rieManifestSha :: !Text
  , rieRejectedBeforeCompletion :: !Bool
  }
  deriving stock (Eq, Show)

-- | Legacy Sprint 31.3 prose lane-fragment input.  These freely constructible
-- text cells exist only so committed seven-column attestations remain
-- readable until typed lane journals replace them; they cannot populate
-- 'ReportMeasurements' or prove a completed product scenario.
data ProductRowReportEvidence = ProductRowReportEvidence
  { prreRowId :: !Text
  , prreCatalog :: !Text
  , prreIntegration :: !Text
  , prreE2E :: !Text
  , prreNegative :: !Text
  , prreDeviceEvidence :: !Text
  , prreLane :: !Text
  }
  deriving stock (Eq, Show)

-- | Kind-indexed proof that a Store-admitted, physically bound completed
-- checkpoint satisfies the exact validated plan, budget, evidence family, and
-- convergence criterion of one ProductRow projection.  Retaining both opaque
-- values in the private constructor prevents the kind parameter or persisted
-- artifact identity from becoming forgeable phantoms.
data ProductScenarioCompletion kind
  = ProductScenarioCompletion
      !(ProductMatrix.ProductProjection kind)
      !CheckpointStore.AdmittedCompletedCheckpoint
  deriving stock (Eq, Show)

data ProductScenarioCompletionError
  = ProductCompletionExperimentMismatch !Text !Text !Text
  | ProductCompletionUnknownManifestExperiment !Text !Text
  | ProductCompletionCanonicalRowMismatch !Text !Text !Text
  | ProductCompletionPlanMismatch !Text !PlanId !PlanId
  | ProductCompletionManifestPlanMismatch !Text !PlanId !(Maybe PlanId)
  | ProductCompletionManifestWitnessMismatch !Text
  | ProductCompletionSupervisedRuntimeMissing !Text
  | ProductCompletionSupervisedRuntimeRowMismatch !Text !Text
  | ProductCompletionSupervisedRuntimeOriginMismatch !Text
  | ProductCompletionUnexpectedSupervisedRuntime !Text !Text
  | ProductCompletionBudgetMismatch !Text !TrainingBudget !TrainingBudget
  | ProductCompletionEvidenceKindMismatch !Text !BudgetKind !BudgetKind
  | ProductCompletionCriterionMismatch !Text !Text !MetricGoal !Double
  | ProductCompletionUpdateCountMismatch !Text !Word64 !Word64
  | ProductCompletionUpdateCountOverflow !Text !Word64 !Word64
  deriving stock (Eq, Show)

-- | Refine only Store-admitted completed checkpoint evidence into the exact
-- ProductRow kind.  The addressed manifest must name the projection's exact
-- experiment and PlanId and must retain the same completion witness exposed by
-- Store admission.  A caller-held completion, a merely decoded manifest, or an
-- unrelated passing metric therefore cannot satisfy the row's report bar.
productScenarioCompletion
  :: ProductMatrix.ProductProjection kind
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> Either
       (NonEmpty ProductScenarioCompletionError)
       (ProductScenarioCompletion kind)
productScenarioCompletion projection admittedCompleted =
  case NonEmpty.nonEmpty failures of
    Just errors -> Left errors
    Nothing ->
      Right (ProductScenarioCompletion projection admittedCompleted)
 where
  rowId = ProductMatrix.productProjectionRowId projection
  expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
  expectedPlanId = ProductMatrix.productProjectionPlanId projection
  admittedCheckpoint =
    CheckpointStore.admittedCompletedCheckpoint admittedCompleted
  manifest = CheckpointStore.admittedCheckpointManifest admittedCheckpoint
  observedExperiment = Checkpoint.manifestExperiment manifest
  observedManifestPlanId = Checkpoint.manifestPlanId manifest
  observedManifestCompleted = Checkpoint.manifestCompletedTraining manifest
  completed = CheckpointStore.admittedCompletedTraining admittedCompleted
  observedPlanId = completedTrainingPlanId completed
  expectedBudget = ProductMatrix.productProjectionTrainingBudget projection
  observedBudget = completedTrainingBudget completed
  observedUpdateCount = completedTrainingUpdateCount completed
  expectedKind =
    productEvidenceBudgetKind
      (ProductMatrix.productProjectionEvidenceRequirements projection)
  observedKind = trainingBudgetKind observedBudget
  bar = ProductMatrix.productProjectionConvergenceBar projection
  criterionMatches observation =
    coMetricName observation == convergenceMetricName bar
      && coMetricGoal observation == convergenceMetricGoal bar
      && coThreshold observation == convergenceThreshold bar
  failures =
    [ ProductCompletionExperimentMismatch
        rowId
        expectedExperiment
        observedExperiment
    | observedExperiment /= expectedExperiment
    ]
      <> [ ProductCompletionPlanMismatch rowId expectedPlanId observedPlanId
         | observedPlanId /= expectedPlanId
         ]
      <> productManifestRowFailures rowId observedExperiment
      <> [ ProductCompletionManifestPlanMismatch
             rowId
             expectedPlanId
             observedManifestPlanId
         | observedManifestPlanId /= Just expectedPlanId
         ]
      <> [ ProductCompletionManifestWitnessMismatch rowId
         | observedManifestCompleted /= Just completed
         ]
      <> productRuntimeBindingFailures rowId projection manifest
      <> [ ProductCompletionBudgetMismatch rowId expectedBudget observedBudget
         | observedBudget /= expectedBudget
         ]
      <> [ ProductCompletionEvidenceKindMismatch rowId expectedKind observedKind
         | observedKind /= expectedKind
         ]
      <> [ ProductCompletionCriterionMismatch
             rowId
             (convergenceMetricName bar)
             (convergenceMetricGoal bar)
             (convergenceThreshold bar)
         | not (any criterionMatches (completedTrainingMetrics completed))
         ]
      <> productCompletionUpdateCountFailures
        rowId
        projection
        observedUpdateCount

productManifestRowFailures :: Text -> Text -> [ProductScenarioCompletionError]
productManifestRowFailures expectedRowId manifestExperiment =
  case ProductMatrix.productRowForExperimentHash manifestExperiment of
    Nothing ->
      [ ProductCompletionUnknownManifestExperiment
          expectedRowId
          manifestExperiment
      ]
    Just row
      | ProductMatrix.rowId row == expectedRowId -> []
      | otherwise ->
          [ ProductCompletionCanonicalRowMismatch
              expectedRowId
              (ProductMatrix.rowId row)
              manifestExperiment
          ]

productRuntimeBindingFailures
  :: Text
  -> ProductMatrix.ProductProjection kind
  -> Checkpoint.CheckpointManifest
  -> [ProductScenarioCompletionError]
productRuntimeBindingFailures rowId projection manifest =
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedSupervisedProductPlan _plan ->
      case Checkpoint.manifestSupervisedRuntime manifest of
        Nothing -> [ProductCompletionSupervisedRuntimeMissing rowId]
        Just payload ->
          [ ProductCompletionSupervisedRuntimeRowMismatch
              rowId
              (RuntimeArtifact.payloadRowId payload)
          | RuntimeArtifact.payloadRowId payload /= rowId
          ]
            <> [ ProductCompletionSupervisedRuntimeOriginMismatch rowId
               | RuntimeArtifact.supervisedRuntimeOriginToRaw
                   (RuntimeArtifact.payloadOrigin payload)
                   /= RuntimeArtifact.RawProductRowProjectionOrigin
               ]
    ProductMatrix.ResolvedRlProductPlan _runPlan -> rejectRuntime
    ProductMatrix.ResolvedTuningProductPlan _plan -> rejectRuntime
    ProductMatrix.ResolvedAlphaZeroProductPlan _plan -> rejectRuntime
 where
  rejectRuntime =
    case Checkpoint.manifestSupervisedRuntime manifest of
      Nothing -> []
      Just payload ->
        [ ProductCompletionUnexpectedSupervisedRuntime
            rowId
            (RuntimeArtifact.payloadRowId payload)
        ]

-- | Validate the optimiser-step relation that Sprint 19.4 can derive exactly
-- from the kind-indexed resolved plan. Traditional RL intentionally has no
-- check here: its current descriptor mixes trainer iterations, environment
-- steps, and optimiser epochs, and Sprint 25.4 owns the dimensionally correct
-- compiled RL plan. Treating that field as an exact optimiser-step count here
-- would manufacture a stronger proof than the current RL plan can express.
productCompletionUpdateCountFailures
  :: Text
  -> ProductMatrix.ProductProjection kind
  -> Word64
  -> [ProductScenarioCompletionError]
productCompletionUpdateCountFailures rowId projection observed =
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedSupervisedProductPlan plan ->
      requireExact
        (quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan))
    ProductMatrix.ResolvedRlProductPlan _runPlan -> []
    ProductMatrix.ResolvedTuningProductPlan plan ->
      requireExact
        (quantityValue (WorkloadPlan.tuningPlanMaxPerTrialUpdates plan))
    ProductMatrix.ResolvedAlphaZeroProductPlan plan ->
      let generations =
            quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan)
          updatesPerGeneration =
            quantityValue (WorkloadPlan.alphaZeroPlanUpdates plan)
          total = toInteger generations * toInteger updatesPerGeneration
       in if total > toInteger (maxBound :: Word64)
            then
              [ ProductCompletionUpdateCountOverflow
                  rowId
                  generations
                  updatesPerGeneration
              ]
            else requireExact (fromInteger total)
 where
  requireExact expected
    | observed == expected = []
    | otherwise =
        [ProductCompletionUpdateCountMismatch rowId expected observed]

productEvidenceBudgetKind
  :: ProductMatrix.ProductEvidenceRequirements kind
  -> BudgetKind
productEvidenceBudgetKind requirements =
  case requirements of
    ProductMatrix.SupervisedProductEvidence -> SupervisedEpochBudget
    ProductMatrix.RlProductEvidence -> RlEnvironmentStepBudget
    ProductMatrix.TuningProductEvidence -> TuningTrialBudget
    ProductMatrix.AlphaZeroProductEvidence -> AlphaZeroSelfPlayBudget

-- | One reportable product scenario that was actually completed by the live
-- interpreter.  The constructor stays private: registry declarations and the
-- legacy seven-column lane-attestation parser cannot mint this value.
data CompletedProductScenarioEvidence = CompletedProductScenarioEvidence
  { scenarioEvidenceRowId :: !Text
  , scenarioEvidencePlanId :: !PlanId
  , scenarioEvidenceLane :: !Substrate
  , scenarioEvidenceManifestSha :: !Text
  , scenarioEvidenceContract :: !ProductScenarioReportContract
  }
  deriving stock (Eq, Show)

-- Ordinary accessors keep the hidden evidence constructor non-forgeable.
-- Exporting its record labels would permit downstream record update even
-- though the constructor itself is not exported.
completedProductScenarioRowId :: CompletedProductScenarioEvidence -> Text
completedProductScenarioRowId = scenarioEvidenceRowId

completedProductScenarioPlanId :: CompletedProductScenarioEvidence -> PlanId
completedProductScenarioPlanId = scenarioEvidencePlanId

completedProductScenarioLane :: CompletedProductScenarioEvidence -> Substrate
completedProductScenarioLane = scenarioEvidenceLane

completedProductScenarioManifestSha :: CompletedProductScenarioEvidence -> Text
completedProductScenarioManifestSha = scenarioEvidenceManifestSha

-- | Report-only axes do not belong to the worker RunPlan, but evidence minted
-- under an older criterion or scenario declaration must not be reusable after
-- those axes change.  Retain their exact structured values behind the opaque
-- evidence constructor instead of relying on a forgeable text hash.
data ProductScenarioReportContract = ProductScenarioReportContract
  { productContractIntegrationTest :: !Text
  , productContractE2ETest :: !Text
  , productContractMetricName :: !Text
  , productContractMetricGoal :: !MetricGoal
  , productContractMetricThreshold :: !Double
  , productContractDeviceClaim :: !ProductMatrix.DeviceClaim
  , productContractImplementation :: !Text
  , productContractArchitectureFeatures :: ![ArchitectureFeature]
  , productContractDemoPanel :: !Text
  }
  deriving stock (Eq, Show)

data ProductScenarioEvidenceError
  = ProductScenarioDidNotComplete !Text
  | ProductScenarioPlanMismatch !Text !PlanId !PlanId
  | ProductScenarioProjectionMismatch !Text
  deriving stock (Eq, Show)

-- | A validated, registry-ordered collection.  Its constructor and underlying
-- list remain private so 'ReportMeasurements' cannot carry unvalidated raw
-- evidence, duplicates, or orphan rows.
newtype CompletedProductScenarioReport
  = CompletedProductScenarioReport
      [CompletedProductScenarioEvidence]
  deriving stock (Eq, Show)

data ProductScenarioReportError
  = MissingCompletedProductScenario !Text !PlanId
  | DuplicateCompletedProductScenario !Text
  | OrphanCompletedProductScenario !Text !PlanId
  | WrongPlanCompletedProductScenario !Text !PlanId !PlanId
  | WrongLaneCompletedProductScenario !Text !Substrate !Substrate
  | StaleContractCompletedProductScenario !Text
  deriving stock (Eq, Show)

-- | Admit only a successful opaque interpreter result carrying the
-- kind-indexed completion for this exact projection.  A generic evidence type
-- such as @()@ cannot inhabit this signature.
completedProductScenarioEvidence
  :: ProductMatrix.ProductProjection kind
  -> Either
       failure
       ( CompletedRunEvidence
           terminal
           (ProductScenarioCompletion kind)
           violation
           missing
       )
  -> Either ProductScenarioEvidenceError CompletedProductScenarioEvidence
completedProductScenarioEvidence projection outcome =
  case outcome of
    Left _failure ->
      Left (ProductScenarioDidNotComplete expectedRowId)
    Right completed ->
      let ProductScenarioCompletion completionProjection admittedCheckpoint =
            completedRunEvidence completed
          observedPlanId = completedRunPlanId completed
          manifestSha =
            CheckpointStore.admittedCheckpointManifestSha
              (CheckpointStore.admittedCompletedCheckpoint admittedCheckpoint)
       in if observedPlanId /= expectedPlanId
            then
              Left
                ( ProductScenarioPlanMismatch
                    expectedRowId
                    expectedPlanId
                    observedPlanId
                )
            else
              if completionProjection /= projection
                then Left (ProductScenarioProjectionMismatch expectedRowId)
                else
                  Right
                    CompletedProductScenarioEvidence
                      { scenarioEvidenceRowId = expectedRowId
                      , scenarioEvidencePlanId = expectedPlanId
                      , scenarioEvidenceLane =
                          ProductMatrix.productProjectionSubstrate projection
                      , scenarioEvidenceManifestSha = manifestSha
                      , scenarioEvidenceContract =
                          productScenarioReportContract projection
                      }
 where
  expectedRowId = ProductMatrix.productProjectionRowId projection
  expectedPlanId = ProductMatrix.productProjectionPlanId projection

-- | Join already opaque scenario evidence against one validated projection
-- batch.  Batch construction owns raw-row projection, duplicate registry IDs,
-- and unprojectable rows; this join owns completed-evidence coverage.
projectCompletedProductScenarioReport
  :: ProductMatrix.ProductProjectionBatch
  -> [CompletedProductScenarioEvidence]
  -> Either
       (NonEmpty ProductScenarioReportError)
       CompletedProductScenarioReport
projectCompletedProductScenarioReport batch observed =
  case NonEmpty.nonEmpty failures of
    Just errors -> Left errors
    Nothing -> Right (CompletedProductScenarioReport orderedEvidence)
 where
  substrate = ProductMatrix.productProjectionBatchSubstrate batch
  expected = fmap projectedIdentity (ProductMatrix.productProjectionBatchProjections batch)
  expectedPlans = [(rowId, planId) | (rowId, planId, _contract) <- expected]
  expectedContracts = [(rowId, contract) | (rowId, _planId, contract) <- expected]
  expectedRowIds = ProductMatrix.productProjectionBatchRowIds batch
  observedRowIds = fmap completedProductScenarioRowId observed
  missingFailures =
    [ MissingCompletedProductScenario rowId planId
    | (rowId, planId, _contract) <- expected
    , rowId `notElem` observedRowIds
    ]
  duplicateEvidenceFailures =
    [ DuplicateCompletedProductScenario rowId
    | rowId <- repeatedTexts observedRowIds
    ]
  orphanFailures =
    [ OrphanCompletedProductScenario
        (completedProductScenarioRowId evidence)
        (completedProductScenarioPlanId evidence)
    | evidence <- observed
    , completedProductScenarioRowId evidence `notElem` expectedRowIds
    ]
  wrongPlanFailures =
    [ WrongPlanCompletedProductScenario rowId expectedPlan observedPlan
    | evidence <- observed
    , let rowId = completedProductScenarioRowId evidence
    , let observedPlan = completedProductScenarioPlanId evidence
    , Just expectedPlan <- [lookup rowId expectedPlans]
    , observedPlan /= expectedPlan
    ]
  wrongLaneFailures =
    [ WrongLaneCompletedProductScenario
        (completedProductScenarioRowId evidence)
        substrate
        (completedProductScenarioLane evidence)
    | evidence <- observed
    , completedProductScenarioRowId evidence `elem` expectedRowIds
    , completedProductScenarioLane evidence /= substrate
    ]
  staleContractFailures =
    [ StaleContractCompletedProductScenario rowId
    | evidence <- observed
    , let rowId = completedProductScenarioRowId evidence
    , Just expectedContract <- [lookup rowId expectedContracts]
    , scenarioEvidenceContract evidence /= expectedContract
    ]
  failures =
    missingFailures
      <> duplicateEvidenceFailures
      <> orphanFailures
      <> wrongPlanFailures
      <> wrongLaneFailures
      <> staleContractFailures
  orderedEvidence =
    [ evidence
    | (rowId, _planId, _contract) <- expected
    , evidence <- observed
    , completedProductScenarioRowId evidence == rowId
    ]

  projectedIdentity
    (ProductMatrix.SomeProductProjection _witness projection) =
      ( ProductMatrix.productProjectionRowId projection
      , ProductMatrix.productProjectionPlanId projection
      , productScenarioReportContract projection
      )

  repeatedTexts values =
    [ value
    | group@(value : _) <- List.group (List.sort values)
    , length group > 1
    ]

productScenarioReportContract
  :: ProductMatrix.ProductProjection kind
  -> ProductScenarioReportContract
productScenarioReportContract projection =
  ProductScenarioReportContract
    { productContractIntegrationTest =
        ProductMatrix.productProjectionIntegrationTest projection
    , productContractE2ETest =
        ProductMatrix.productProjectionE2ETest projection
    , productContractMetricName = convergenceMetricName bar
    , productContractMetricGoal = convergenceMetricGoal bar
    , productContractMetricThreshold = convergenceThreshold bar
    , productContractDeviceClaim =
        ProductMatrix.productProjectionDeviceClaim projection
    , productContractImplementation =
        ProductMatrix.productProjectionImplementation projection
    , productContractArchitectureFeatures =
        ProductMatrix.productProjectionArchitectureFeatures projection
    , productContractDemoPanel =
        ProductMatrix.productProjectionDemoPanel projection
    }
 where
  bar = ProductMatrix.productProjectionConvergenceBar projection

defaultReportCardKnobs :: ReportCardKnobs
defaultReportCardKnobs =
  ReportCardKnobs
    { knobSlEpochs = 5
    , knobSlBatch = 64
    , knobRlSteps = 100000
    , knobRlEvalEpisodes = 25
    , knobAzGames = 200
    , knobAzSims = 400
    , knobTuneTrials = 64
    , knobTuneBudgetPerTrial = 1000
    , knobCrossClusterKindNodes = 2
    }

emptyReportMeasurements :: ReportMeasurements
emptyReportMeasurements =
  ReportMeasurements
    { measuredSlFinalLoss = Nothing
    , measuredRlFinalReward = Nothing
    , measuredAlphaZeroArenaWinRate = Nothing
    , measuredTuneBestObjective = Nothing
    , measuredJitCacheHitRate = Nothing
    , measuredDaemonHealthz = Nothing
    , measuredBrowserProductMatrix = Nothing
    , measuredProductRowEvidence = Nothing
    }

reportStanzas :: [Text]
reportStanzas =
  [ "jitml-unit"
  , "jitml-integration"
  , "jitml-sl-canonicals"
  , "jitml-rl-canonicals"
  , "jitml-hyperparameter"
  , "jitml-backends"
  , "jitml-daemon-lifecycle"
  , "jitml-e2e"
  , "jitml-negative-controls"
  , "jitml-model-convergence"
  ]

-- | Stanzas whose cases are partitioned into per-substrate tasty lanes (named
-- @linux-cpu …@ / @linux-cuda …@ / @apple-silicon …@) and that fail when run on
-- the wrong substrate. Under an explicit substrate selector these run with
-- @--test-options '-p <substrate>'@; every other stanza runs in full so that a
-- substrate selector never silently drops non-backend coverage.
substratePartitionedStanzas :: [Text]
substratePartitionedStanzas =
  ["jitml-backends"]

-- | Stanzas that contain substrate-backed ML/device work and therefore require
-- the selected substrate runtime to be present before the test process starts.
-- Only 'substratePartitionedStanzas' are filtered by tasty pattern; the
-- canonical SL/RL/tuning stanzas run their full pure coverage and read
-- @JITML_SUBSTRATE@ for the device-backed cases.
substrateRuntimeStanzas :: [Text]
substrateRuntimeStanzas =
  [ "jitml-sl-canonicals"
  , "jitml-rl-canonicals"
  , "jitml-hyperparameter"
  ]
    <> substratePartitionedStanzas

-- | Build the ordered list of @cabal test@ argument vectors for a run. Each
-- element is the arguments passed after the @cabal@ executable.
--
-- Every stanza receives its own invocation. This makes the association between
-- an observed process outcome and its suite exact, permits fail-fast suffixes
-- to remain 'NotRun', and avoids Cabal-native parallel execution across live
-- stanzas that share one cluster, registry, object store, and host device. With
-- a substrate, 'substratePartitionedStanzas' additionally run under
-- @-p \<substrate\>@ (and @-fcuda@ on @linux-cuda@, so the cuBLAS/cuDNN bindings
-- link). Empty target lists produce no invocations.
substrateTestInvocations :: Maybe Substrate -> [Text] -> Maybe Text -> [[Text]]
substrateTestInvocations Nothing targets userOptions =
  ["test" : target : testOptionArgs userOptions | target <- targets]
substrateTestInvocations (Just substrate) targets userOptions =
  fmap invocationFor targets
 where
  cudaArgs = ["-fcuda" | substrate == LinuxCUDA]
  laneOption = "-p " <> renderSubstrate substrate
  partitionedOptions =
    case userOptions of
      Just opts | not (Text.null opts) -> laneOption <> " " <> opts
      _ -> laneOption
  invocationFor target
    | target `elem` substratePartitionedStanzas =
        "test" : cudaArgs <> [target, "--test-options", partitionedOptions]
    | otherwise = "test" : cudaArgs <> [target] <> testOptionArgs userOptions

testOptionArgs :: Maybe Text -> [Text]
testOptionArgs Nothing = []
testOptionArgs (Just opts)
  | Text.null opts = []
  | otherwise = ["--test-options", opts]

renderReportCard :: ReportCard -> Text
renderReportCard =
  renderReportCardWithKnobs defaultReportCardKnobs

loadReportCardKnobs :: FilePath -> IO (Either Text ReportCardKnobs)
loadReportCardKnobs path =
  parseReportCardKnobs <$> Text.IO.readFile path

parseReportCardKnobs :: Text -> Either Text ReportCardKnobs
parseReportCardKnobs content =
  ReportCardKnobs
    <$> lookupInt "sl_epochs"
    <*> lookupInt "sl_batch"
    <*> lookupInt "rl_steps"
    <*> lookupInt "rl_eval_episodes"
    <*> lookupInt "az_games"
    <*> lookupInt "az_sims"
    <*> lookupInt "tune_trials"
    <*> lookupInt "tune_budget_per_trial"
    <*> lookupInt "xcluster_kind_nodes"
 where
  entries =
    [ (Text.strip key, Text.strip (Text.drop 1 rest))
    | line <- Text.lines content
    , Just comment <- [Text.stripPrefix "-- " (Text.strip line)]
    , let (key, rest) = Text.breakOn ":" comment
    , not (Text.null rest)
    ]

  lookupInt key =
    case lookup key entries of
      Nothing -> Left ("missing report-card knob: " <> key)
      Just value -> parseInt key value

  parseInt key value =
    case reads (Text.unpack (Text.filter (/= '_') value)) of
      [(parsed, "")] -> Right parsed
      _ -> Left ("invalid report-card knob " <> key <> ": " <> value)

renderReportCardWithKnobs :: ReportCardKnobs -> ReportCard -> Text
renderReportCardWithKnobs knobs report =
  Text.unlines
    ( [ "jitML POC report card"
      , "knobs:"
      , "  sl_epochs: " <> showText (knobSlEpochs knobs)
      , "  sl_batch: " <> showText (knobSlBatch knobs)
      , "  rl_steps: " <> showText (knobRlSteps knobs)
      , "  rl_eval_episodes: " <> showText (knobRlEvalEpisodes knobs)
      , "  alphazero_games: " <> showText (knobAzGames knobs)
      , "  alphazero_sims: " <> showText (knobAzSims knobs)
      , "  tune_trials: " <> showText (knobTuneTrials knobs)
      , "  tune_budget_per_trial: " <> showText (knobTuneBudgetPerTrial knobs)
      , "  xcluster_kind_nodes: " <> showText (knobCrossClusterKindNodes knobs)
      , "stanzas:"
      ]
        <> fmap renderInvocationStatus entries
        <> renderMeasurements (reportMeasurements report)
        <> renderProductRowEvidenceTable (reportMeasurements report)
        <> renderScenarioJournals (reportScenarioJournals report)
        <> [ "cabal_test:"
           , "  status: " <> renderSuiteStatus (suiteStatus result)
           , "  passed: " <> showText (suitePassed result)
           , "  failed: " <> showText (suiteFailed result)
           , "  not_run: " <> showText (suiteNotRun result)
           , "  duration_seconds: " <> renderDurationSeconds (suiteDuration result)
           , "  duration_nanoseconds: "
               <> showText (processDurationNanoseconds (suiteDuration result))
           ]
        <> renderInvocationJournal entries
    )
 where
  journal = reportInvocationJournal report
  entries = invocationJournalEntries journal
  result = deriveSuiteResult journal

renderScenarioJournals :: [ScenarioJournal] -> [Text]
renderScenarioJournals [] = []
renderScenarioJournals journals =
  "scenario_journals:" : concatMap renderScenarioJournal journals

renderScenarioJournal :: ScenarioJournal -> [Text]
renderScenarioJournal journal =
  ["  - scenario: " <> scenarioJournalName journal, "    records:"]
    <> concatMap renderScenarioRecord (scenarioJournalRecords journal)
    <> renderScenarioIssues (scenarioJournalIssues journal)

renderScenarioRecord :: ScenarioRecord -> [Text]
renderScenarioRecord record =
  [ "      - phase: " <> renderScenarioPhase (scenarioRecordPhase record)
  , "        step: " <> scenarioRecordStep record
  , "        disposition: " <> renderScenarioDisposition (scenarioRecordDisposition record)
  ]
    <> if scenarioRecordPhase record == ScenarioBody
      then ["        transcript: invocation_journal/" <> scenarioRecordStep record]
      else case scenarioRecordOutcome record of
        ObservedProcessSucceeded transcript ->
          ("        command: " <> processTranscriptCommand transcript)
            : renderTranscript "        " ExitSuccess transcript
        ObservedProcessFailed failure ->
          ("        command: " <> observedProcessFailureCommand failure)
            : renderObservedFailureTranscript "        " failure

renderScenarioPhase :: ScenarioPhase -> Text
renderScenarioPhase ScenarioAcquire = "acquire"
renderScenarioPhase ScenarioBody = "body"
renderScenarioPhase ScenarioDiagnostics = "diagnostics"
renderScenarioPhase ScenarioRelease = "release"

renderScenarioDisposition :: ScenarioDisposition -> Text
renderScenarioDisposition ScenarioStepSucceeded = "succeeded"
renderScenarioDisposition ScenarioStepFailed = "failed"
renderScenarioDisposition ScenarioStepAcceptedNoop = "accepted-noop"

renderScenarioIssues :: [ScenarioIssue] -> [Text]
renderScenarioIssues [] = []
renderScenarioIssues issues =
  "    issues:" : concatMap renderScenarioIssue issues

renderScenarioIssue :: ScenarioIssue -> [Text]
renderScenarioIssue issue =
  [ "      - phase: " <> renderScenarioPhase (scenarioIssuePhase issue)
  , "        step: " <> scenarioIssueStep issue
  , "        detail:"
  ]
    <> fmap ("          " <>) (nonEmptyLines (scenarioIssueDetail issue))
 where
  nonEmptyLines detail
    | Text.null detail = ["(none)"]
    | otherwise = Text.lines detail

renderInvocationStatus :: InvocationRecord -> Text
renderInvocationStatus entry =
  "  " <> invocationStanza entry <> ": " <> status
 where
  status =
    case invocationResult entry of
      Passed _ -> "PASS"
      Failed _ -> "FAIL"
      NotRun blocker -> "NOT-RUN (blocked by " <> blockedByStanza blocker <> ")"

renderSuiteStatus :: SuiteStatus -> Text
renderSuiteStatus SuitePassed = "passed"
renderSuiteStatus SuiteFailed = "failed"
renderSuiteStatus SuiteNotRun = "not-run"

renderDurationSeconds :: ProcessDuration -> Text
renderDurationSeconds (ProcessDuration nanoseconds) =
  showText wholeSeconds
    <> "."
    <> Text.justifyRight 9 '0' (showText remainder)
 where
  (wholeSeconds, remainder) = nanoseconds `divMod` 1_000_000_000

renderInvocationJournal :: [InvocationRecord] -> [Text]
renderInvocationJournal [] = ["invocation_journal: []"]
renderInvocationJournal entries =
  "invocation_journal:" : concatMap renderInvocation entries

renderInvocation :: InvocationRecord -> [Text]
renderInvocation entry =
  [ "  - stanza: " <> invocationStanza entry
  , "    command: " <> invocationCommand entry
  ]
    <> case invocationResult entry of
      Passed transcript ->
        "    status: passed" : renderTranscript "    " ExitSuccess transcript
      Failed failure ->
        "    status: failed"
          : renderObservedFailureTranscript "    " failure
      NotRun blocker ->
        [ "    status: not-run"
        , "    blocked_by:"
        , "      stanza: " <> blockedByStanza blocker
        , "      command: " <> observedProcessFailureCommand (blockedByFailure blocker)
        ]
          <> renderObservedFailureTranscript "      " (blockedByFailure blocker)

renderObservedFailureTranscript
  :: Text
  -> ObservedProcessFailure
  -> [Text]
renderObservedFailureTranscript indentation failure =
  case failure of
    ObservedProcessExitFailure processFailure ->
      renderFailureTranscript indentation processFailure
    ObservedProcessAttemptFailure attemptFailure ->
      renderAttemptFailureTranscript indentation attemptFailure

renderAttemptFailureTranscript
  :: Text
  -> ProcessAttemptFailure
  -> [Text]
renderAttemptFailureTranscript indentation failure =
  [ indentation <> "exit: unavailable"
  , indentation
      <> "working_directory: "
      <> maybe
        "(inherited)"
        Text.pack
        (processAttemptFailureWorkingDirectory failure)
  , indentation
      <> "duration_nanoseconds: "
      <> showText
        (processDurationNanoseconds (processAttemptFailureDuration failure))
  ]
    <> renderOptionalOutput
      indentation
      "stdout"
      (processAttemptFailureStdout failure)
    <> renderOptionalOutput
      indentation
      "stderr"
      (processAttemptFailureStderr failure)
    <> [indentation <> "exception:"]
    <> fmap
      (\line -> indentation <> "  " <> line)
      (nonEmptyTextLines (processAttemptFailureException failure))

renderFailureTranscript :: Text -> ProcessFailure -> [Text]
renderFailureTranscript indentation failure =
  renderTranscriptWith
    indentation
    (processFailureExitCode failure)
    (processFailureWorkingDirectory failure)
    (processFailureDuration failure)
    (processFailureStdout failure)
    (processFailureStderr failure)

renderTranscript :: Text -> ExitCode -> ProcessTranscript -> [Text]
renderTranscript indentation exitCode transcript =
  renderTranscriptWith
    indentation
    exitCode
    (processTranscriptWorkingDirectory transcript)
    (processTranscriptDuration transcript)
    (processTranscriptStdout transcript)
    (processTranscriptStderr transcript)

renderTranscriptWith
  :: Text
  -> ExitCode
  -> Maybe FilePath
  -> ProcessDuration
  -> Text
  -> Text
  -> [Text]
renderTranscriptWith indentation exitCode workingDirectory duration stdout stderr =
  [ indentation <> "exit: " <> renderExitCode exitCode
  , indentation
      <> "working_directory: "
      <> maybe "(inherited)" Text.pack workingDirectory
  , indentation
      <> "duration_nanoseconds: "
      <> showText (processDurationNanoseconds duration)
  ]
    <> renderOutput indentation "stdout" stdout
    <> renderOutput indentation "stderr" stderr

renderOutput :: Text -> Text -> Text -> [Text]
renderOutput indentation label output =
  (indentation <> label <> ":")
    : fmap
      (indentation <>)
      (if Text.null output then ["  (none)"] else fmap ("  " <>) (Text.lines output))

renderOptionalOutput :: Text -> Text -> Maybe Text -> [Text]
renderOptionalOutput indentation label Nothing =
  [indentation <> label <> ": (unavailable; capture did not complete)"]
renderOptionalOutput indentation label (Just output) =
  renderOutput indentation label output

nonEmptyTextLines :: Text -> [Text]
nonEmptyTextLines value
  | Text.null value = ["(none)"]
  | otherwise = Text.lines value

renderExitCode :: ExitCode -> Text
renderExitCode ExitSuccess = "0"
renderExitCode (ExitFailure code) = showText code

renderMeasurements :: ReportMeasurements -> [Text]
renderMeasurements measurements
  | not (hasMeasurements measurements) = []
  | otherwise =
      [ "measurements:"
      ]
        <> measurementLine "sl_final_loss" (measuredSlFinalLoss measurements)
        <> measurementLine "rl_final_reward" (measuredRlFinalReward measurements)
        <> measurementLine "alphazero_arena_win_rate" (measuredAlphaZeroArenaWinRate measurements)
        <> measurementLine "tune_best_objective" (measuredTuneBestObjective measurements)
        <> measurementLine "jit_cache_hit_rate" (measuredJitCacheHitRate measurements)
        <> measurementLine "daemon_healthz" (measuredDaemonHealthz measurements)
        <> measurementLine "browser_product_matrix" (measuredBrowserProductMatrix measurements)

hasMeasurements :: ReportMeasurements -> Bool
hasMeasurements measurements =
  any
    isMeasured
    [ measuredSlFinalLoss measurements
    , measuredRlFinalReward measurements
    , measuredAlphaZeroArenaWinRate measurements
    , measuredTuneBestObjective measurements
    , measuredJitCacheHitRate measurements
    , measuredDaemonHealthz measurements
    , measuredBrowserProductMatrix measurements
    ]
 where
  isMeasured Nothing = False
  isMeasured (Just _) = True

measurementLine :: Text -> Maybe ReportMeasurement -> [Text]
measurementLine _ Nothing = []
measurementLine label (Just measurement) =
  ["  " <> label <> ": " <> renderMeasurement measurement]

renderMeasurement :: ReportMeasurement -> Text
renderMeasurement (MeasurementAvailable value) = value
renderMeasurement MeasurementUnavailable = "unavailable"

renderProductRowEvidenceTable :: ReportMeasurements -> [Text]
renderProductRowEvidenceTable measurements =
  case measuredProductRowEvidence measurements of
    Nothing -> []
    Just report ->
      "product_rows:"
        : fmap
          ("  " <>)
          ( Text.lines
              (renderCompletedProductScenarioEvidence report)
          )

renderCompletedProductScenarioEvidence
  :: CompletedProductScenarioReport
  -> Text
renderCompletedProductScenarioEvidence (CompletedProductScenarioReport evidence) =
  Text.unlines
    ( "row_id\tplan_id\tlane\tmanifest_sha\tevidence"
        : fmap renderEvidence evidence
    )
 where
  renderEvidence completed =
    Text.intercalate
      "\t"
      [ completedProductScenarioRowId completed
      , planIdText (completedProductScenarioPlanId completed)
      , renderSubstrate (completedProductScenarioLane completed)
      , completedProductScenarioManifestSha completed
      , "completed-scenario"
      ]

-- | Validate the legacy seven-column lane-fragment shape only.  Passing this
-- check is not completed-run evidence and cannot satisfy the live report path.
productRowReportCoverageFailures
  :: [ProductMatrix.ProductRow state]
  -> [ProductMatrix.NonProductRow]
  -> [ProductRowReportEvidence]
  -> [Text]
productRowReportCoverageFailures rows nonProductRows observed =
  missingFailures
    <> duplicateFailures
    <> orphanFailures
    <> concatMap cellFailures observed
 where
  expectedRowIds = fmap ProductMatrix.rowId rows
  nonProductReasons =
    [ (ProductMatrix.nonProductRowId row, ProductMatrix.nonProductRowReason row)
    | row <- nonProductRows
    ]
  observedRowIds = fmap prreRowId observed
  missingFailures =
    [ "missing product-row report evidence row: rowId=" <> rowId
    | rowId <- expectedRowIds
    , rowId `notElem` observedRowIds
    ]
  duplicateFailures =
    [ "duplicate product-row report evidence row: rowId="
        <> rowId
        <> " count="
        <> showText (length group)
    | group@(rowId : _) <- List.group (List.sort observedRowIds)
    , length group > 1
    ]
  orphanFailures =
    [ case lookup rowId nonProductReasons of
        Just reason ->
          "non-product row supplied as product evidence: rowId="
            <> rowId
            <> " reason="
            <> reason
        Nothing -> "orphan product-row report evidence row: rowId=" <> rowId
    | rowId <- observedRowIds
    , rowId `notElem` expectedRowIds
    ]
  cellFailures evidence =
    [ "missing report evidence cell: rowId="
        <> prreRowId evidence
        <> " column="
        <> column
    | prreRowId evidence `elem` expectedRowIds
    , (column, value) <-
        [ ("Catalog", prreCatalog evidence)
        , ("Integration", prreIntegration evidence)
        , ("E2E", prreE2E evidence)
        , ("Negative", prreNegative evidence)
        , ("DeviceEvidence", prreDeviceEvidence evidence)
        , ("Lane", prreLane evidence)
        ]
    , Text.null (Text.strip value)
    ]

-- | Render the legacy Sprint 31.3 seven-column lane fragment.  Live report
-- measurements render 'CompletedProductScenarioEvidence' instead.
renderProductRowReportEvidence
  :: [ProductMatrix.ProductRow state]
  -> [ProductMatrix.NonProductRow]
  -> [ProductRowReportEvidence]
  -> Text
renderProductRowReportEvidence rows nonProductRows evidence =
  Text.unlines
    ( [ "row_id\tCatalog\tIntegration\tE2E\tNegative\tDeviceEvidence\tLane"
      ]
        <> fmap renderProductRow rows
        <> fmap renderNonProductRow nonProductRows
    )
 where
  evidenceByRowId = fmap (\row -> (prreRowId row, row)) evidence
  renderProductRow row =
    case lookup (ProductMatrix.rowId row) evidenceByRowId of
      Nothing ->
        Text.intercalate
          "\t"
          [ ProductMatrix.rowId row
          , "MISSING"
          , "MISSING"
          , "MISSING"
          , "MISSING"
          , "MISSING"
          , "MISSING"
          ]
      Just observed ->
        Text.intercalate
          "\t"
          [ ProductMatrix.rowId row
          , prreCatalog observed
          , prreIntegration observed
          , prreE2E observed
          , prreNegative observed
          , prreDeviceEvidence observed
          , prreLane observed
          ]
  renderNonProductRow row =
    Text.intercalate
      "\t"
      [ ProductMatrix.nonProductRowId row
      , "non-product: " <> ProductMatrix.nonProductRowReason row
      , "not-required"
      , "not-required"
      , "not-required"
      , "not-required"
      , "not-required"
      ]

loadAggregatedProductLaneAttestations :: IO (Either Text [ProductRowReportEvidence])
loadAggregatedProductLaneAttestations =
  aggregateProductLaneAttestations
    <$> traverse
      ( \(lane, path) -> do
          content <- Text.IO.readFile path
          pure (lane, content)
      )
      productLaneAttestationInputs

productLaneAttestationInputs :: [(Text, FilePath)]
productLaneAttestationInputs =
  [ ("linux-cpu", "DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md")
  , ("linux-cuda", "DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md")
  , ("apple-silicon", "DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md")
  ]

aggregateProductLaneAttestations
  :: [(Text, Text)]
  -> Either Text [ProductRowReportEvidence]
aggregateProductLaneAttestations laneDocuments =
  case failures of
    [] -> Right evidence
    _ -> Left (Text.unlines failures)
 where
  parsed =
    [ (lane, parseProductRowReportEvidenceTable content)
    | (lane, content) <- laneDocuments
    ]
  parseFailures =
    [ "failed to parse product-row evidence table for lane " <> lane <> ": " <> err
    | (lane, Left err) <- parsed
    ]
  evidence = concat [rows | (_lane, Right rows) <- parsed]
  missingLaneFailures =
    [ "missing product-lane attestation: lane=" <> lane
    | (lane, _path) <- productLaneAttestationInputs
    , lane `notElem` fmap fst laneDocuments
    ]
  failures =
    parseFailures
      <> missingLaneFailures
      <> productLaneAttestationFailures
        (fmap fst productLaneAttestationInputs)
        ProductMatrix.allProductRows
        ProductMatrix.nonProductRows
        evidence

-- | Parse a legacy Sprint 31.3 prose lane fragment.  The result is deliberately
-- disjoint from the opaque completed-scenario type accepted by live reports.
parseProductRowReportEvidenceTable :: Text -> Either Text [ProductRowReportEvidence]
parseProductRowReportEvidenceTable content =
  traverse parseRow evidenceLines
 where
  evidenceLines =
    [ line
    | line <- Text.lines content
    , let stripped = Text.strip line
    , not (Text.null stripped)
    , "\t" `Text.isInfixOf` stripped
    , not ("row_id\t" `Text.isPrefixOf` stripped)
    , not ("non-product:" `Text.isInfixOf` stripped)
    , not ("not-required" `Text.isInfixOf` stripped)
    ]
  parseRow line =
    case Text.splitOn "\t" (Text.strip line) of
      [rowId', catalog', integration', e2e', negative', deviceEvidence', lane'] ->
        Right
          ProductRowReportEvidence
            { prreRowId = rowId'
            , prreCatalog = catalog'
            , prreIntegration = integration'
            , prreE2E = e2e'
            , prreNegative = negative'
            , prreDeviceEvidence = deviceEvidence'
            , prreLane = lane'
            }
      cells ->
        Left
          ( "expected 7 tab-separated product evidence cells, got "
              <> showText (length cells)
              <> ": "
              <> line
          )

productLaneAttestationFailures
  :: [Text]
  -> [ProductMatrix.ProductRow state]
  -> [ProductMatrix.NonProductRow]
  -> [ProductRowReportEvidence]
  -> [Text]
productLaneAttestationFailures lanes rows nonProductRows observed =
  missingFailures
    <> duplicateFailures
    <> orphanFailures
    <> laneMismatchFailures
    <> concatMap cellFailures observed
 where
  expectedRowIds = fmap ProductMatrix.rowId rows
  nonProductReasons =
    [ (ProductMatrix.nonProductRowId row, ProductMatrix.nonProductRowReason row)
    | row <- nonProductRows
    ]
  observedPairs = fmap (\evidence -> (prreLane evidence, prreRowId evidence)) observed
  missingFailures =
    [ "missing product-lane evidence row: lane=" <> lane <> " rowId=" <> rowId
    | lane <- lanes
    , rowId <- expectedRowIds
    , (lane, rowId) `notElem` observedPairs
    ]
  duplicateFailures =
    [ "duplicate product-lane evidence row: lane="
        <> lane
        <> " rowId="
        <> rowId
        <> " count="
        <> showText (length group)
    | group@((lane, rowId) : _) <- List.group (List.sort observedPairs)
    , length group > 1
    ]
  orphanFailures =
    [ case lookup rowId nonProductReasons of
        Just reason ->
          "non-product row supplied as lane evidence: lane="
            <> lane
            <> " rowId="
            <> rowId
            <> " reason="
            <> reason
        Nothing ->
          "orphan product-lane evidence row: lane=" <> lane <> " rowId=" <> rowId
    | (lane, rowId) <- observedPairs
    , rowId `notElem` expectedRowIds
    ]
  laneMismatchFailures =
    [ "unexpected product-lane evidence lane: lane=" <> lane <> " rowId=" <> prreRowId evidence
    | evidence <- observed
    , let lane = prreLane evidence
    , lane `notElem` lanes
    ]
  cellFailures evidence =
    [ "missing product-lane evidence cell: lane="
        <> prreLane evidence
        <> " rowId="
        <> prreRowId evidence
        <> " column="
        <> column
    | (column, value) <-
        [ ("Catalog", prreCatalog evidence)
        , ("Integration", prreIntegration evidence)
        , ("E2E", prreE2E evidence)
        , ("Negative", prreNegative evidence)
        , ("DeviceEvidence", prreDeviceEvidence evidence)
        , ("Lane", prreLane evidence)
        ]
    , Text.null (Text.strip value)
    ]

rowIntegrationCoverageFailures
  :: [ProductMatrix.ProductRow state]
  -> [RowIntegrationEvidence]
  -> [Text]
rowIntegrationCoverageFailures rows observed =
  missingFailures
    <> duplicateFailures
    <> orphanFailures
    <> concatMap evidenceFailures observed
 where
  expectedPairs =
    [ (ProductMatrix.rowId row, ProductMatrix.integrationTest row)
    | row <- rows
    ]
  observedPairs =
    [ (rieRowId evidence, rieIntegrationTest evidence)
    | evidence <- observed
    ]
  missingFailures =
    [ "missing integration evidence: rowId="
        <> rowId
        <> " testId="
        <> testId
    | (rowId, testId) <- expectedPairs
    , (rowId, testId) `notElem` observedPairs
    ]
  duplicateFailures =
    [ "duplicate integration evidence: rowId="
        <> rowId
        <> " testId="
        <> testId
        <> " count="
        <> showText (length group)
    | group@((rowId, testId) : _) <- List.group (List.sort observedPairs)
    , length group > 1
    ]
  orphanFailures =
    [ "orphan integration evidence: rowId="
        <> rowId
        <> " testId="
        <> testId
    | (rowId, testId) <- observedPairs
    , (rowId, testId) `notElem` expectedPairs
    ]
  evidenceFailures evidence =
    RowAssertions.assertLearnedStateChanged
      RowAssertions.LearnedStateEvidence
        { RowAssertions.lseRowId = rieRowId evidence
        , RowAssertions.lseInitialParamHash = rieInitialParamHash evidence
        , RowAssertions.lseFinalParamHash = rieFinalParamHash evidence
        , RowAssertions.lseUpdateCount = rieUpdateCount evidence
        }
      <> [ "completed-training observed units must be positive for row " <> rieRowId evidence
         | rieObservedUnits evidence == 0
         ]
      <> [ "completed-training convergence metrics are required for row " <> rieRowId evidence
         | null (rieCompletedMetricNames evidence)
         ]
      <> [ "completed-training convergence metrics failed for row " <> rieRowId evidence
         | not (rieCompletedTrainingPassed evidence)
         ]
      <> [ "dataset sha at read is required for row " <> rieRowId evidence
         | Text.null (Text.strip (rieDatasetShaAtRead evidence))
         ]
      <> [ "manifest sha is required for row " <> rieRowId evidence
         | Text.null (Text.strip (rieManifestSha evidence))
         ]
      <> [ "inference was not rejected before completion for row " <> rieRowId evidence
         | not (rieRejectedBeforeCompletion evidence)
         ]

renderRowIntegrationEvidence :: [RowIntegrationEvidence] -> Text
renderRowIntegrationEvidence rows =
  Text.unlines
    ( [ "row_id\tintegration_test\tfamily\tupdates\tobserved_units\tmetrics\tdataset_sha\tmanifest_sha"
      ]
        <> fmap renderRow rows
    )
 where
  renderRow row =
    Text.intercalate
      "\t"
      [ rieRowId row
      , rieIntegrationTest row
      , rieFamily row
      , showText (rieUpdateCount row)
      , showText (rieObservedUnits row)
      , Text.intercalate "," (rieCompletedMetricNames row)
      , rieDatasetShaAtRead row
      , rieManifestSha row
      ]

showText :: (Show a) => a -> Text
showText = Text.pack . show

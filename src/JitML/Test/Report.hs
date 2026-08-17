{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( BlockedBy
  , RefinementBlocker
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
  , AddressedProductScenarioCompletion
  , ProductScenarioPrecondition
  , ProductScenarioPreconditionError (..)
  , ExecutedProductScenarioCompletion
  , ProductScenarioCompletionError (..)
  , ProductScenarioEvidenceError (..)
  , ProductScenarioReportError (..)
  , aggregateProductLaneAttestations
  , appendInvocation
  , appendInvocationJournal
  , blockedByFailure
  , blockedByStanza
  , canonicalCompletedTrainingDigest
  , canonicalCompletedTrainingSummary
  , completedProductScenarioEvidence
  , completedProductScenarioReportEntries
  , completedProductScenarioLane
  , completedProductScenarioManifestSha
  , completedProductScenarioMeasuredDigest
  , completedProductScenarioMeasuredSummary
  , completedProductScenarioPlanId
  , completedProductScenarioRowId
  , completedProductScenarioRunId
  , completedProductScenarioCommand
  , completedProductScenarioDeviceWitness
  , completedProductScenarioCheckpointScopeDigest
  , completedProductScenarioContractDigest
  , completedProductScenarioExecutablePath
  , completedProductScenarioExecutableSha256
  , completedProductScenarioInvocationDigest
  , completedProductScenarioExperimentHash
  , completedProductScenarioInferenceManifestSha
  , completedProductScenarioJournalDigest
  , completedProductScenarioJournalReceipt
  , completedProductScenarioPreconditionRejected
  , completedProductScenarioPreconditionSequence
  , completedProductScenarioInferenceSequence
  , completedProductScenarioCompletionSequence
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
  , refinementBlockerDetail
  , refinementBlockerName
  , refinementBlockerStanza
  , loadAggregatedProductLaneAttestations
  , loadReportCardKnobs
  , notRunInvocation
  , notRunAfterRefinement
  , notRunObservedInvocation
  , parseReportCardKnobs
  , passedInvocation
  , parseProductRowReportEvidenceTable
  , productScenarioCompletion
  , admitAddressedProductScenarioCompletion
  , observeProductScenarioPrecondition
  , productScenarioPreconditionCheckpointRoot
  , productScenarioPreconditionExecutablePath
  , productScenarioPreconditionExecutableSha256
  , productScenarioPreconditionInvocation
  , productScenarioPreconditionPinnedExecutablePath
  , revalidateProductScenarioPinnedExecutable
  , renderProductScenarioPrecondition
  , renderProductScenarioExecutionAcknowledgement
  , executedProductScenarioCompletion
  , renderExecutedProductScenarioCompletion
  , journaledProductScenarioEvidence
  , projectCompletedProductScenarioReport
  , productScenarioCheckpointScopeDigest
  , productScenarioProjectionContractDigest
  , productRowReportCoverageFailures
  , productLaneAttestationFailures
  , productLaneAttestationFragmentDrift
  , productLaneAttestationInputs
  , renderReportCardWithKnobs
  , renderProductRowReportEvidence
  , renderProductLaneAttestationFragment
  , renderCompletedProductScenarioEvidence
  , validateCompletedProductScenarioLiveAdmission
  , reportStanzas
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

import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (isControl)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , renameFile
  )
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, normalise, takeDirectory, (</>))
import System.IO (hFlush)
import System.IO.Temp (withTempFile)
import System.Posix.Files
  ( ownerExecuteMode
  , ownerReadMode
  , ownerWriteMode
  , setFileMode
  , unionFileModes
  )

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Plan.Plan (PlanId, planIdText, quantityValue)
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Convergence
  ( convergenceMetricGoal
  , convergenceMetricName
  , convergenceThreshold
  )
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Pipeline qualified as ProductPipeline
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
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.BrowserEvidenceJournal qualified as BrowserEvidenceJournal
import JitML.Test.LiveWorkflow
  ( LiveDiagnostic (..)
  , LiveJournalEvent (..)
  , LiveJournalRecord (..)
  , LiveTerminalFact (..)
  , Placement (..)
  , completedRunEvidence
  , completedRunJournal
  , completedRunPlacement
  , completedRunPlanId
  , completedRunTerminal
  , hostRunHandleKey
  , hostRunHandlePlanId
  )
import JitML.Test.ProductScenarioAuthorization
  ( AuthenticatedProductScenarioJournalRow
  , authenticatedProductScenarioJournalRowMaterialMatches
  , authenticatedProductScenarioJournalRowRunId
  , generateProductScenarioJournalKey
  , productScenarioJournalEvidenceMaterial
  , renderProductScenarioJournalKey
  )
import JitML.Test.ProductScenarioInterpreter.Internal qualified as ProductScenarioInterpreter
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
  , CompletedTraining
  , MetricGoal
  , ProductScenarioInvocation
  , TrainingBudget
  , coMetricGoal
  , coMetricName
  , coMetricValue
  , coThreshold
  , completedTrainingBudget
  , completedTrainingMetrics
  , completedTrainingObservedUnits
  , completedTrainingPlanId
  , completedTrainingProductScenarioInvocation
  , completedTrainingTensorBoard
  , completedTrainingUpdateCount
  , encodeCompletedTraining
  , mkProductScenarioInvocation
  , productScenarioInvocationCheckpointScopeDigest
  , productScenarioInvocationDigest
  , productScenarioInvocationExecutableSha256
  , productScenarioInvocationPlanId
  , productScenarioInvocationRowId
  , productScenarioInvocationRunId
  , productScenarioInvocationSubstrate
  , renderTrainingBudget
  , tbrLogPrefix
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
  | NotRunAfterRefinement !RefinementBlocker
  deriving stock (Eq, Show)

-- | Structured reason an invocation was not run. The blocker is the complete
-- observed failure rather than a reconstructed command or prose reason.
data BlockedBy = BlockedBy
  { blockerStanzaValue :: !Text
  , blockerFailureValue :: !ObservedProcessFailure
  }
  deriving stock (Eq, Show)

-- | Honest non-process blocker: a preceding command may have exited zero but
-- failed to refine into the proof required by a downstream invocation.
data RefinementBlocker = RefinementBlocker
  { refinementBlockerStanzaValue :: !Text
  , refinementBlockerNameValue :: !Text
  , refinementBlockerDetailValue :: !Text
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

refinementBlockerStanza :: RefinementBlocker -> Text
refinementBlockerStanza = refinementBlockerStanzaValue

refinementBlockerName :: RefinementBlocker -> Text
refinementBlockerName = refinementBlockerNameValue

refinementBlockerDetail :: RefinementBlocker -> Text
refinementBlockerDetail = refinementBlockerDetailValue

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

-- | Record a downstream invocation as NotRun because a successful process did
-- not refine into the required proof.  This deliberately cannot carry an
-- 'ObservedProcessFailure'.
notRunAfterRefinement
  :: Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> InvocationRecord
notRunAfterRefinement stanza command blockerStanza refinementName detail =
  InvocationRecord
    { recordStanzaValue = stanza
    , recordCommandValue = command
    , recordResultValue =
        NotRunAfterRefinement
          (RefinementBlocker blockerStanza refinementName detail)
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
  notRun =
    length
      [ ()
      | InvocationRecord {recordResultValue = result} <- entries
      , case result of
          NotRun _ -> True
          NotRunAfterRefinement _ -> True
          _ -> False
      ]
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
invocationDurationNanoseconds (NotRunAfterRefinement _) = 0

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
  , measuredBrowserProductEvidence :: Maybe BrowserEvidenceJournal.BrowserEvidenceReport
  -- ^ Opaque authenticated browser results, exactly ordered and bound to the
  -- same catalogue rowId/PlanId/manifest/e2e identities.  A substring count or
  -- green child exit cannot inhabit this field.
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

-- | Exact-address completion physically re-admitted from one canonical local
-- checkpoint scope.  The root and its digest are retained behind the private
-- constructor so a freshness witness from one cache cannot be paired with an
-- admitted checkpoint read from another cache.
data AddressedProductScenarioCompletion kind
  = AddressedProductScenarioCompletion
      !FilePath
      !Text
      !(ProductScenarioCompletion kind)
  deriving stock (Eq, Show)

-- | Chronological negative-control witness for one fresh scenario cache.  It
-- can only be obtained by attempting the production local inference-admission
-- boundary for the exact row before execution, observing its typed rejection,
-- and then confirming that no latest pointer exists.  The constructor is
-- private so a post-hoc Boolean cannot stand in for that attempted read.
data ProductScenarioPrecondition kind
  = ProductScenarioPrecondition
      !ProductScenarioInvocation
      !FilePath
      !Text
      !FilePath
      !Text
      !FilePath
      !(ProductMatrix.ProductProjection kind)
      !CheckpointStore.CheckpointAdmissionError
  deriving stock (Eq, Show)

data ProductScenarioPreconditionError
  = ProductScenarioRunIdInvalid !Text
  | ProductScenarioCheckpointRootIdentityFailed !Text !FilePath !Text
  | ProductScenarioExecutableIdentityFailed !Text !FilePath !Text
  | ProductScenarioExecutableDigestMismatch !Text !Text !Text
  | ProductScenarioExecutablePinFailed !Text !FilePath !Text
  | ProductScenarioChallengeGenerationFailed !Text !Text
  | ProductScenarioInvocationInvalid !Text !Text
  | ProductScenarioPreconditionReadFailed !Text !Text
  | ProductScenarioCheckpointAlreadyExists !Text !Text
  | ProductScenarioInferenceUnexpectedlyEligible !Text !Text
  deriving stock (Eq, Show)

-- | Store admission and inference eligibility for the exact projection,
-- coupled to the earlier empty-cache witness.  This is the evidence carried by
-- the live executable reducer; an admitted checkpoint obtained without the
-- chronological negative control cannot inhabit it.
data ExecutedProductScenarioCompletion kind
  = ExecutedProductScenarioCompletion
      !(ProductScenarioPrecondition kind)
      !(ProductScenarioCompletion kind)
      !ProductPipeline.InferenceEligibleRef
  deriving stock (Eq, Show)

observeProductScenarioPrecondition
  :: Text
  -> FilePath
  -> Text
  -> FilePath
  -> ProductMatrix.ProductProjection kind
  -> IO
       ( Either
           ProductScenarioPreconditionError
           (ProductScenarioPrecondition kind)
       )
observeProductScenarioPrecondition runId executablePath expectedExecutableSha256 checkpointRoot projection
  | not (validProductScenarioRunId runId) =
      pure (Left (ProductScenarioRunIdInvalid runId))
  | not (canonicalSha256 expectedExecutableSha256) =
      pure
        ( Left
            ( ProductScenarioExecutableIdentityFailed
                rowId
                executablePath
                "caller-supplied executable SHA-256 is not canonical"
            )
        )
  | otherwise = do
      canonicalRootResult <- canonicalProductScenarioCheckpointRoot checkpointRoot
      case canonicalRootResult of
        Left detail ->
          pure
            ( Left
                (ProductScenarioCheckpointRootIdentityFailed rowId checkpointRoot detail)
            )
        Right canonicalRoot -> do
          executableIdentityResult <- productScenarioExecutableIdentity executablePath
          case executableIdentityResult of
            Left detail ->
              pure
                ( Left
                    (ProductScenarioExecutableIdentityFailed rowId executablePath detail)
                )
            Right (canonicalExecutablePath, executableSha256, executableBytes)
              | executableSha256 /= expectedExecutableSha256 ->
                  pure
                    ( Left
                        ( ProductScenarioExecutableDigestMismatch
                            rowId
                            expectedExecutableSha256
                            executableSha256
                        )
                    )
              | otherwise ->
                  observeAtCanonicalIdentities
                    canonicalRoot
                    canonicalExecutablePath
                    executableSha256
                    executableBytes
 where
  rowId = ProductMatrix.productProjectionRowId projection
  experimentHash = ProductMatrix.productProjectionExperimentHash projection
  pointerKey = Checkpoint.latestPointerKey experimentHash

  observeAtCanonicalIdentities canonicalRoot canonicalExecutablePath executableSha256 executableBytes = do
    let scopeDigest = productScenarioCheckpointScopeDigest canonicalRoot
    inferenceAttempt <-
      CheckpointStore.admitLocalLatestCheckpoint canonicalRoot experimentHash
    case inferenceAttempt of
      Right admitted ->
        pure
          ( Left
              ( ProductScenarioInferenceUnexpectedlyEligible
                  rowId
                  (CheckpointStore.admittedCheckpointManifestSha admitted)
              )
          )
      Left rejection -> do
        observed <- CheckpointStore.readCheckpointPointer canonicalRoot pointerKey
        case observed of
          Left err ->
            pure (Left (ProductScenarioPreconditionReadFailed rowId err))
          Right (Just manifestSha) ->
            pure (Left (ProductScenarioCheckpointAlreadyExists rowId manifestSha))
          Right Nothing -> do
            pinnedResult <-
              pinProductScenarioExecutable canonicalRoot executableSha256 executableBytes
            case pinnedResult of
              Left detail ->
                pure
                  ( Left
                      ( ProductScenarioExecutablePinFailed
                          rowId
                          canonicalExecutablePath
                          detail
                      )
                  )
              Right pinnedExecutablePath -> do
                generatedChallenge <- generateProductScenarioJournalKey
                case generatedChallenge of
                  Left err ->
                    pure
                      ( Left
                          ( ProductScenarioChallengeGenerationFailed
                              rowId
                              (Text.pack (show err))
                          )
                      )
                  Right challengeKey ->
                    case mkProductScenarioInvocation
                      runId
                      rowId
                      (ProductMatrix.productProjectionPlanId projection)
                      (ProductMatrix.productProjectionSubstrate projection)
                      scopeDigest
                      executableSha256
                      (renderProductScenarioJournalKey challengeKey) of
                      Left detail ->
                        pure
                          (Left (ProductScenarioInvocationInvalid rowId detail))
                      Right invocation ->
                        pure
                          ( Right
                              ( ProductScenarioPrecondition
                                  invocation
                                  canonicalRoot
                                  scopeDigest
                                  canonicalExecutablePath
                                  executableSha256
                                  pinnedExecutablePath
                                  projection
                                  rejection
                              )
                          )

productScenarioPreconditionCheckpointRoot
  :: ProductScenarioPrecondition kind
  -> FilePath
productScenarioPreconditionCheckpointRoot
  ( ProductScenarioPrecondition
      _invocation
      checkpointRoot
      _scope
      _path
      _sha
      _pinned
      _projection
      _rejection
    ) =
    checkpointRoot

productScenarioPreconditionExecutablePath
  :: ProductScenarioPrecondition kind
  -> FilePath
productScenarioPreconditionExecutablePath
  ( ProductScenarioPrecondition
      _invocation
      _root
      _scope
      executablePath
      _sha
      _pinned
      _projection
      _rejection
    ) =
    executablePath

productScenarioPreconditionExecutableSha256
  :: ProductScenarioPrecondition kind
  -> Text
productScenarioPreconditionExecutableSha256
  ( ProductScenarioPrecondition
      _invocation
      _root
      _scope
      _path
      executableSha256
      _pinned
      _projection
      _rejection
    ) =
    executableSha256

productScenarioPreconditionPinnedExecutablePath
  :: ProductScenarioPrecondition kind
  -> FilePath
productScenarioPreconditionPinnedExecutablePath
  (ProductScenarioPrecondition _invocation _root _scope _path _sha pinnedPath _projection _rejection) =
    pinnedPath

productScenarioPreconditionInvocation
  :: ProductScenarioPrecondition kind
  -> ProductScenarioInvocation
productScenarioPreconditionInvocation
  (ProductScenarioPrecondition invocation _root _scope _path _sha _pinned _projection _rejection) =
    invocation

-- | Canonical negative-control event payload.  The typed Store rejection is
-- retained privately in 'ProductScenarioPrecondition'; the persisted receipt
-- names the exact row, plan, lane, and checkpoint scope whose inference
-- admission failed before command execution.
renderProductScenarioPrecondition :: ProductScenarioPrecondition kind -> Text
renderProductScenarioPrecondition
  ( ProductScenarioPrecondition
      invocation
      _root
      scopeDigest
      executablePath
      executableSha256
      pinnedExecutablePath
      projection
      _rejection
    ) =
    expectedProductScenarioPreconditionReceipt
      projection
      (productScenarioInvocationRunId invocation)
      scopeDigest
      executablePath
      executableSha256
      pinnedExecutablePath
      (productScenarioInvocationDigest invocation)

renderProductScenarioExecutionAcknowledgement
  :: ProductScenarioPrecondition kind
  -> Text
  -> Text
renderProductScenarioExecutionAcknowledgement precondition =
  productScenarioExecutionAcknowledgement
    (productScenarioPreconditionExecutableSha256 precondition)
    ( productScenarioInvocationDigest
        (productScenarioPreconditionInvocation precondition)
    )

productScenarioExecutionAcknowledgement :: Text -> Text -> Text -> Text
productScenarioExecutionAcknowledgement executableSha256 invocationDigest actualCommand =
  Text.intercalate
    "\t"
    [ "process-exit:0"
    , actualCommand
    , executableSha256
    , invocationDigest
    ]

-- | Re-admit an immutable manifest address from one explicit local scope and
-- retain that scope nominally beside the completion.  Both the live runner and
-- the cross-process reader use this path.
admitAddressedProductScenarioCompletion
  :: FilePath
  -> ProductMatrix.ProductProjection kind
  -> Text
  -> IO
       ( Either
           (NonEmpty ProductScenarioCompletionError)
           (AddressedProductScenarioCompletion kind)
       )
admitAddressedProductScenarioCompletion checkpointRoot projection manifestSha = do
  canonicalRootResult <- canonicalProductScenarioCheckpointRoot checkpointRoot
  case canonicalRootResult of
    Left detail ->
      pure
        ( Left
            ( ProductCompletionCheckpointScopeResolutionFailed
                (ProductMatrix.productProjectionRowId projection)
                checkpointRoot
                detail
                NonEmpty.:| []
            )
        )
    Right canonicalRoot -> do
      admittedResult <-
        CheckpointStore.admitLocalCheckpointAt
          canonicalRoot
          (ProductMatrix.productProjectionExperimentHash projection)
          manifestSha
      pure $ do
        admitted <-
          case admittedResult of
            Left admissionError ->
              Left
                ( ProductCompletionStoreAdmissionFailed
                    (ProductMatrix.productProjectionRowId projection)
                    admissionError
                    NonEmpty.:| []
                )
            Right value -> Right value
        admittedCompleted <-
          case CheckpointStore.requireAdmittedCompletedCheckpoint admitted of
            Left admissionError ->
              Left
                ( ProductCompletionStoreAdmissionFailed
                    (ProductMatrix.productProjectionRowId projection)
                    admissionError
                    NonEmpty.:| []
                )
            Right value -> Right value
        completion <- productScenarioCompletion projection admittedCompleted
        Right
          ( AddressedProductScenarioCompletion
              canonicalRoot
              (productScenarioCheckpointScopeDigest canonicalRoot)
              completion
          )

executedProductScenarioCompletion
  :: ProductScenarioPrecondition kind
  -> ProductMatrix.ProductProjection kind
  -> AddressedProductScenarioCompletion kind
  -> Either
       (NonEmpty ProductScenarioCompletionError)
       (ExecutedProductScenarioCompletion kind)
executedProductScenarioCompletion precondition projection addressed = do
  let ProductScenarioPrecondition
        invocation
        _preconditionRoot
        preconditionScope
        _executablePath
        _executableSha256
        _pinnedExecutablePath
        preconditionProjection
        _inferenceRejection = precondition
      AddressedProductScenarioCompletion
        _addressedRoot
        addressedScope
        completion@(ProductScenarioCompletion completionProjection admitted) = addressed
      rowId = ProductMatrix.productProjectionRowId projection
      boundaryFailures =
        [ProductCompletionPreconditionMismatch rowId | preconditionProjection /= projection]
          <> [ProductCompletionProjectionMismatch rowId | completionProjection /= projection]
          <> [ ProductCompletionCheckpointScopeMismatch
                 rowId
                 preconditionScope
                 addressedScope
             | preconditionScope /= addressedScope
             ]
          <> [ ProductCompletionInvocationMismatch
                 rowId
                 (productScenarioInvocationDigest invocation)
                 (productScenarioInvocationDigest <$> observedInvocation)
             | observedInvocation /= Just invocation
             ]
      observedInvocation =
        completedTrainingProductScenarioInvocation
          (CheckpointStore.admittedCompletedTraining admitted)
  case NonEmpty.nonEmpty boundaryFailures of
    Just failures -> Left failures
    Nothing -> Right ()
  let inferenceRef = ProductPipeline.inferenceEligibleModelRef admitted
      expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
      expectedManifestSha =
        CheckpointStore.admittedCheckpointManifestSha
          (CheckpointStore.admittedCompletedCheckpoint admitted)
      inferenceFailures =
        [ ProductCompletionInferenceExperimentMismatch
            (ProductMatrix.productProjectionRowId projection)
            expectedExperiment
            (ProductPipeline.modelRefExperimentHash inferenceRef)
        | ProductPipeline.modelRefExperimentHash inferenceRef /= expectedExperiment
        ]
          <> [ ProductCompletionInferenceManifestMismatch
                 (ProductMatrix.productProjectionRowId projection)
                 expectedManifestSha
                 (ProductPipeline.modelRefManifestSha inferenceRef)
             | ProductPipeline.modelRefManifestSha inferenceRef /= Just expectedManifestSha
             ]
  case NonEmpty.nonEmpty inferenceFailures of
    Just failures -> Left failures
    Nothing ->
      Right
        ( ExecutedProductScenarioCompletion
            precondition
            completion
            inferenceRef
        )

renderExecutedProductScenarioCompletion
  :: ExecutedProductScenarioCompletion kind
  -> Text
renderExecutedProductScenarioCompletion
  ( ExecutedProductScenarioCompletion
      precondition
      (ProductScenarioCompletion projection admitted)
      _inferenceRef
    ) =
    Text.intercalate
      "\t"
      [ "product-publish-completed-v2"
      , ProductMatrix.productProjectionRowId projection
      , planIdText (ProductMatrix.productProjectionPlanId projection)
      , productScenarioInvocationDigest
          (productScenarioPreconditionInvocation precondition)
      , CheckpointStore.admittedCheckpointManifestSha
          (CheckpointStore.admittedCompletedCheckpoint admitted)
      ]

data ProductScenarioCompletionError
  = ProductCompletionStoreAdmissionFailed
      !Text
      !CheckpointStore.CheckpointAdmissionError
  | ProductCompletionCheckpointScopeResolutionFailed !Text !FilePath !Text
  | ProductCompletionExperimentMismatch !Text !Text !Text
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
  | ProductCompletionPreconditionMismatch !Text
  | ProductCompletionProjectionMismatch !Text
  | ProductCompletionCheckpointScopeMismatch !Text !Text !Text
  | ProductCompletionInvocationMismatch !Text !Text !(Maybe Text)
  | ProductCompletionInferenceExperimentMismatch !Text !Text !Text
  | ProductCompletionInferenceManifestMismatch !Text !Text !(Maybe Text)
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

-- | Validate optimiser-step relations that are statically derivable from a
-- kind-indexed plan. Traditional RL optimizer applications are measured-only:
-- Phase 252 removed the heterogeneous planned field, and the opaque trained
-- artifact checks its measured counter against TrainingEvidence before a
-- CompletedTraining value can be minted. Its environment-transition total is
-- independently exact-checked by the RL budget/completion witness.
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
  , scenarioEvidenceRunId :: !Text
  , scenarioEvidencePlanId :: !PlanId
  , scenarioEvidenceLane :: !Substrate
  , scenarioEvidenceExperimentHash :: !Text
  , scenarioEvidenceManifestSha :: !Text
  , scenarioEvidenceContract :: !ProductScenarioReportContract
  , scenarioEvidenceCommand :: !Text
  , scenarioEvidenceExecutablePath :: !FilePath
  , scenarioEvidenceExecutableSha256 :: !Text
  , scenarioEvidenceInvocationDigest :: !Text
  , scenarioEvidenceCheckpointScopeDigest :: !Text
  , scenarioEvidenceJournalReceipt :: !Text
  , scenarioEvidenceJournalDigest :: !Text
  , scenarioEvidenceInferenceManifestSha :: !Text
  , scenarioEvidencePreconditionRejected :: !Bool
  , scenarioEvidencePreconditionSequence :: !Word64
  , scenarioEvidenceInferenceSequence :: !Word64
  , scenarioEvidenceCompletionSequence :: !Word64
  , scenarioEvidenceAdmittedCompletion :: !CheckpointStore.AdmittedCompletedCheckpoint
  }
  deriving stock (Eq, Show)

-- Ordinary accessors keep the hidden evidence constructor non-forgeable.
-- Exporting its record labels would permit downstream record update even
-- though the constructor itself is not exported.
completedProductScenarioRowId :: CompletedProductScenarioEvidence -> Text
completedProductScenarioRowId = scenarioEvidenceRowId

completedProductScenarioRunId :: CompletedProductScenarioEvidence -> Text
completedProductScenarioRunId = scenarioEvidenceRunId

completedProductScenarioPlanId :: CompletedProductScenarioEvidence -> PlanId
completedProductScenarioPlanId = scenarioEvidencePlanId

completedProductScenarioLane :: CompletedProductScenarioEvidence -> Substrate
completedProductScenarioLane = scenarioEvidenceLane

completedProductScenarioManifestSha :: CompletedProductScenarioEvidence -> Text
completedProductScenarioManifestSha = scenarioEvidenceManifestSha

-- | SHA-256 of the exact Store-refined CompletedTraining CBOR retained by the
-- opaque evidence.  The digest binds every measured field, while the raw
-- invocation challenge remains private.
completedProductScenarioMeasuredDigest :: CompletedProductScenarioEvidence -> Text
completedProductScenarioMeasuredDigest =
  canonicalCompletedTrainingDigest
    . CheckpointStore.admittedCompletedTraining
    . scenarioEvidenceAdmittedCompletion

-- | Canonical, browser-safe measured projection.  It deliberately omits the
-- executable identity, checkpoint root, receipt, and invocation challenge.
completedProductScenarioMeasuredSummary :: CompletedProductScenarioEvidence -> Text
completedProductScenarioMeasuredSummary =
  canonicalCompletedTrainingSummary
    . CheckpointStore.admittedCompletedTraining
    . scenarioEvidenceAdmittedCompletion

completedProductScenarioExperimentHash :: CompletedProductScenarioEvidence -> Text
completedProductScenarioExperimentHash = scenarioEvidenceExperimentHash

completedProductScenarioCommand :: CompletedProductScenarioEvidence -> Text
completedProductScenarioCommand = scenarioEvidenceCommand

-- | The artifact witness the scenario's admitted completion carries.
--
-- Total: admission rejects an unwitnessed completion, so the lane fragment has
-- no no-evidence branch to render.
completedProductScenarioDeviceWitness
  :: CompletedProductScenarioEvidence -> DeviceWitness.DeviceExecutionWitness
completedProductScenarioDeviceWitness =
  CheckpointStore.admittedCompletedDeviceWitness . scenarioEvidenceAdmittedCompletion

completedProductScenarioExecutablePath :: CompletedProductScenarioEvidence -> FilePath
completedProductScenarioExecutablePath = scenarioEvidenceExecutablePath

completedProductScenarioExecutableSha256 :: CompletedProductScenarioEvidence -> Text
completedProductScenarioExecutableSha256 = scenarioEvidenceExecutableSha256

completedProductScenarioInvocationDigest :: CompletedProductScenarioEvidence -> Text
completedProductScenarioInvocationDigest = scenarioEvidenceInvocationDigest

completedProductScenarioCheckpointScopeDigest
  :: CompletedProductScenarioEvidence
  -> Text
completedProductScenarioCheckpointScopeDigest = scenarioEvidenceCheckpointScopeDigest

completedProductScenarioJournalReceipt :: CompletedProductScenarioEvidence -> Text
completedProductScenarioJournalReceipt = scenarioEvidenceJournalReceipt

completedProductScenarioJournalDigest :: CompletedProductScenarioEvidence -> Text
completedProductScenarioJournalDigest = scenarioEvidenceJournalDigest

completedProductScenarioInferenceManifestSha :: CompletedProductScenarioEvidence -> Text
completedProductScenarioInferenceManifestSha = scenarioEvidenceInferenceManifestSha

completedProductScenarioPreconditionRejected :: CompletedProductScenarioEvidence -> Bool
completedProductScenarioPreconditionRejected = scenarioEvidencePreconditionRejected

completedProductScenarioPreconditionSequence :: CompletedProductScenarioEvidence -> Word64
completedProductScenarioPreconditionSequence = scenarioEvidencePreconditionSequence

completedProductScenarioInferenceSequence :: CompletedProductScenarioEvidence -> Word64
completedProductScenarioInferenceSequence = scenarioEvidenceInferenceSequence

completedProductScenarioCompletionSequence :: CompletedProductScenarioEvidence -> Word64
completedProductScenarioCompletionSequence = scenarioEvidenceCompletionSequence

completedProductScenarioContractDigest :: CompletedProductScenarioEvidence -> Text
completedProductScenarioContractDigest =
  productScenarioReportContractDigest . scenarioEvidenceContract

-- | Re-check a live MinIO Store admission against the exact completion that
-- originally minted this opaque evidence and against the current projection.
-- Equality includes the addressed manifest, physical loaded weights, and the
-- refined CompletedTraining value.
validateCompletedProductScenarioLiveAdmission
  :: ProductMatrix.ProductProjection kind
  -> CompletedProductScenarioEvidence
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> Either Text ()
validateCompletedProductScenarioLiveAdmission projection evidence liveAdmission =
  case failures of
    [] -> Right ()
    failure : _ -> Left failure
 where
  rowId = ProductMatrix.productProjectionRowId projection
  liveCheckpoint = CheckpointStore.admittedCompletedCheckpoint liveAdmission
  liveManifestSha = CheckpointStore.admittedCheckpointManifestSha liveCheckpoint
  failures =
    [ "catalogue evidence row differs from current ProductProjection"
    | completedProductScenarioRowId evidence /= rowId
    ]
      <> [ "catalogue evidence PlanId differs from current ProductProjection"
         | completedProductScenarioPlanId evidence
             /= ProductMatrix.productProjectionPlanId projection
         ]
      <> [ "catalogue evidence substrate differs from current ProductProjection"
         | completedProductScenarioLane evidence
             /= ProductMatrix.productProjectionSubstrate projection
         ]
      <> [ "catalogue evidence experiment differs from current ProductProjection"
         | completedProductScenarioExperimentHash evidence
             /= ProductMatrix.productProjectionExperimentHash projection
         ]
      <> [ "catalogue evidence contract differs from current ProductProjection"
         | scenarioEvidenceContract evidence
             /= productScenarioReportContract projection
         ]
      <> [ "live Store admission manifest differs from authenticated evidence"
         | liveManifestSha /= completedProductScenarioManifestSha evidence
         ]
      <> [ "live Store admission differs from exact authenticated completion"
         | liveAdmission /= scenarioEvidenceAdmittedCompletion evidence
         ]

canonicalCompletedTrainingDigest :: CompletedTraining -> Text
canonicalCompletedTrainingDigest = sha256Bytes . encodeCompletedTraining

canonicalCompletedTrainingSummary :: CompletedTraining -> Text
canonicalCompletedTrainingSummary completed =
  Text.intercalate
    ";"
    [ "budget=" <> renderTrainingBudget (completedTrainingBudget completed)
    , "observed_units=" <> showText (completedTrainingObservedUnits completed)
    , "updates=" <> showText (completedTrainingUpdateCount completed)
    , "metrics="
        <> Text.intercalate
          ","
          [ coMetricName observation
              <> "="
              <> Text.pack (show (coMetricValue observation))
          | observation <- completedTrainingMetrics completed
          ]
    , "tensorboard="
        <> tbrLogPrefix (completedTrainingTensorBoard completed)
    ]

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
  | ProductScenarioCommandMismatch !Text !Text !Text
  | ProductScenarioAcknowledgementMismatch !Text !Text !Text
  | ProductScenarioNonExecutableTerminal !Text
  | ProductScenarioJournalInvalid !Text !Text
  | ProductScenarioJournalReceiptMismatch !Text !Text
  | ProductScenarioInferenceBindingMismatch !Text !Text !(Maybe Text)
  deriving stock (Eq, Show)

-- | A validated, registry-ordered collection.  Its constructor and underlying
-- list remain private so 'ReportMeasurements' cannot carry unvalidated raw
-- evidence, duplicates, or orphan rows.
newtype CompletedProductScenarioReport
  = CompletedProductScenarioReport
      [CompletedProductScenarioEvidence]
  deriving stock (Eq, Show)

completedProductScenarioReportEntries
  :: CompletedProductScenarioReport
  -> [CompletedProductScenarioEvidence]
completedProductScenarioReportEntries (CompletedProductScenarioReport evidence) = evidence

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
  -> ProductScenarioInterpreter.ProductScenarioInterpreterRun
       terminal
       (ExecutedProductScenarioCompletion kind)
       violation
       missing
  -> Either ProductScenarioEvidenceError CompletedProductScenarioEvidence
completedProductScenarioEvidence projection interpreterRun
  | observedPlanId /= expectedPlanId =
      Left
        ( ProductScenarioPlanMismatch
            expectedRowId
            expectedPlanId
            observedPlanId
        )
  | completionProjection /= projection =
      Left (ProductScenarioProjectionMismatch expectedRowId)
  | observedCommands /= [expectedCommand] =
      Left
        ( ProductScenarioCommandMismatch
            expectedRowId
            expectedCommand
            (Text.intercalate " | " observedCommands)
        )
  | otherwise = case completedRunTerminal completed of
      ExecutableCommandSucceeded acknowledgement
        | acknowledgement /= expectedAcknowledgement ->
            Left
              ( ProductScenarioAcknowledgementMismatch
                  expectedRowId
                  expectedAcknowledgement
                  acknowledgement
              )
        | observedInferenceManifest /= Just manifestSha ->
            Left
              ( ProductScenarioInferenceBindingMismatch
                  expectedRowId
                  manifestSha
                  observedInferenceManifest
              )
        | otherwise ->
            case productScenarioJournalReceipt
              projection
              runId
              checkpointRoot
              checkpointScopeDigest
              executablePath
              executableSha256
              pinnedExecutablePath
              invocationDigest
              manifestSha
              expectedCommand
              (renderProductScenarioPrecondition precondition)
              (completedRunPlacement completed)
              journal of
              Left detail ->
                Left (ProductScenarioJournalInvalid expectedRowId detail)
              Right journalReceipt ->
                Right
                  CompletedProductScenarioEvidence
                    { scenarioEvidenceRowId = expectedRowId
                    , scenarioEvidenceRunId = runId
                    , scenarioEvidencePlanId = expectedPlanId
                    , scenarioEvidenceLane =
                        ProductMatrix.productProjectionSubstrate projection
                    , scenarioEvidenceExperimentHash =
                        ProductMatrix.productProjectionExperimentHash projection
                    , scenarioEvidenceManifestSha = manifestSha
                    , scenarioEvidenceContract =
                        productScenarioReportContract projection
                    , scenarioEvidenceCommand = expectedCommand
                    , scenarioEvidenceExecutablePath = executablePath
                    , scenarioEvidenceExecutableSha256 = executableSha256
                    , scenarioEvidenceInvocationDigest = invocationDigest
                    , scenarioEvidenceCheckpointScopeDigest =
                        checkpointScopeDigest
                    , scenarioEvidenceJournalReceipt = journalReceipt
                    , scenarioEvidenceJournalDigest =
                        sha256Text journalReceipt
                    , scenarioEvidenceInferenceManifestSha = manifestSha
                    , scenarioEvidencePreconditionRejected = True
                    , scenarioEvidencePreconditionSequence =
                        requiredJournalSequence
                          (\case LocalPreconditionObserved {} -> True; _ -> False)
                          journal
                    , scenarioEvidenceInferenceSequence =
                        requiredJournalSequence
                          (\case LocalEvidenceObserved {} -> True; _ -> False)
                          journal
                    , scenarioEvidenceCompletionSequence =
                        requiredJournalSequence
                          (\case ProtocolEvidenceCompleted -> True; _ -> False)
                          journal
                    , scenarioEvidenceAdmittedCompletion = admittedCheckpoint
                    }
      _ -> Left (ProductScenarioNonExecutableTerminal expectedRowId)
 where
  completed =
    ProductScenarioInterpreter.productScenarioInterpreterCompletedRun interpreterRun
  ExecutedProductScenarioCompletion
    precondition
    (ProductScenarioCompletion completionProjection admittedCheckpoint)
    inferenceRef = completedRunEvidence completed
  ProductScenarioPrecondition
    invocation
    checkpointRoot
    checkpointScopeDigest
    executablePath
    executableSha256
    pinnedExecutablePath
    _preconditionProjection
    _preconditionRejection = precondition
  runId = productScenarioInvocationRunId invocation
  invocationDigest = productScenarioInvocationDigest invocation
  observedPlanId = completedRunPlanId completed
  manifestSha =
    CheckpointStore.admittedCheckpointManifestSha
      (CheckpointStore.admittedCompletedCheckpoint admittedCheckpoint)
  observedInferenceManifest = ProductPipeline.modelRefManifestSha inferenceRef
  journal = completedRunJournal completed
  observedCommands =
    [ payload
    | LiveJournalRecord _sequence (CommandPublicationStarted _address payload) <- journal
    ]
  expectedRowId = ProductMatrix.productProjectionRowId projection
  expectedPlanId = ProductMatrix.productProjectionPlanId projection
  expectedCommand =
    renderSubprocess
      (subprocess "jitml" (ProductMatrix.productProjectionCommand projection))
  expectedAcknowledgement =
    renderProductScenarioExecutionAcknowledgement
      precondition
      (productScenarioExecutedCommand projection checkpointRoot pinnedExecutablePath)

-- | Rehydrate one previously completed scenario only after the journal reader
-- has re-admitted its exact checkpoint address.  This is the explicit process
-- boundary: every persisted identity is compared again with the current
-- projection and the opaque Store completion before evidence is minted.
journaledProductScenarioEvidence
  :: AuthenticatedProductScenarioJournalRow
  -> ProductMatrix.ProductProjection kind
  -> Text
  -> FilePath
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Bool
  -> Word64
  -> Word64
  -> Word64
  -> AddressedProductScenarioCompletion kind
  -> Either ProductScenarioEvidenceError CompletedProductScenarioEvidence
journaledProductScenarioEvidence
  authenticatedJournalRow
  projection
  recordedRunId
  recordedExecutablePath
  recordedExecutableSha256
  recordedInvocationDigest
  recordedExperiment
  recordedManifestSha
  recordedCommand
  recordedContractDigest
  recordedCheckpointScopeDigest
  recordedJournalReceipt
  recordedJournalDigest
  recordedInferenceManifestSha
  preconditionRejected
  preconditionSequence
  inferenceSequence
  completionSequence
  ( AddressedProductScenarioCompletion
      checkpointRoot
      addressedCheckpointScopeDigest
      (ProductScenarioCompletion completionProjection admitted)
    ) =
    case failures of
      [] ->
        Right
          CompletedProductScenarioEvidence
            { scenarioEvidenceRowId = rowId
            , scenarioEvidenceRunId = recordedRunId
            , scenarioEvidencePlanId = ProductMatrix.productProjectionPlanId projection
            , scenarioEvidenceLane = ProductMatrix.productProjectionSubstrate projection
            , scenarioEvidenceExperimentHash = recordedExperiment
            , scenarioEvidenceManifestSha = recordedManifestSha
            , scenarioEvidenceContract = contract
            , scenarioEvidenceCommand = recordedCommand
            , scenarioEvidenceExecutablePath = recordedExecutablePath
            , scenarioEvidenceExecutableSha256 = recordedExecutableSha256
            , scenarioEvidenceInvocationDigest = recordedInvocationDigest
            , scenarioEvidenceCheckpointScopeDigest = recordedCheckpointScopeDigest
            , scenarioEvidenceJournalReceipt = recordedJournalReceipt
            , scenarioEvidenceJournalDigest = recordedJournalDigest
            , scenarioEvidenceInferenceManifestSha = recordedInferenceManifestSha
            , scenarioEvidencePreconditionRejected = preconditionRejected
            , scenarioEvidencePreconditionSequence = preconditionSequence
            , scenarioEvidenceInferenceSequence = inferenceSequence
            , scenarioEvidenceCompletionSequence = completionSequence
            , scenarioEvidenceAdmittedCompletion = admitted
            }
      detail : _ -> Left (ProductScenarioJournalReceiptMismatch rowId detail)
   where
    rowId = ProductMatrix.productProjectionRowId projection
    expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
    expectedManifestSha =
      CheckpointStore.admittedCheckpointManifestSha
        (CheckpointStore.admittedCompletedCheckpoint admitted)
    expectedCommand =
      renderSubprocess
        (subprocess "jitml" (ProductMatrix.productProjectionCommand projection))
    contract = productScenarioReportContract projection
    expectedContractDigest = productScenarioReportContractDigest contract
    completed = CheckpointStore.admittedCompletedTraining admitted
    admittedInvocation = completedTrainingProductScenarioInvocation completed
    pinnedExecutablePath =
      productScenarioPinnedExecutablePath checkpointRoot recordedExecutableSha256
    expectedPreconditionReceipt =
      expectedProductScenarioPreconditionReceipt
        projection
        recordedRunId
        addressedCheckpointScopeDigest
        recordedExecutablePath
        recordedExecutableSha256
        pinnedExecutablePath
        recordedInvocationDigest
    expectedJournalReceipt =
      expectedProductScenarioJournalReceipt
        projection
        recordedRunId
        checkpointRoot
        addressedCheckpointScopeDigest
        recordedExecutablePath
        recordedExecutableSha256
        pinnedExecutablePath
        recordedInvocationDigest
        recordedManifestSha
        recordedCommand
        expectedPreconditionReceipt
    expectedJournalDigest = sha256Text expectedJournalReceipt
    expectedAuthenticatedRowMaterial =
      productScenarioJournalEvidenceMaterial
        rowId
        recordedRunId
        (planIdText (ProductMatrix.productProjectionPlanId projection))
        (renderSubstrate (ProductMatrix.productProjectionSubstrate projection))
        recordedExecutablePath
        recordedExecutableSha256
        recordedInvocationDigest
        recordedExperiment
        recordedManifestSha
        recordedCommand
        recordedContractDigest
        recordedCheckpointScopeDigest
        recordedJournalReceipt
        recordedJournalDigest
        recordedInferenceManifestSha
        preconditionRejected
        preconditionSequence
        inferenceSequence
        completionSequence
    failures =
      [ "completion projection differs from current ProductProjection" | completionProjection /= projection
      ]
        <> [ "authenticated journal row run differs from persisted row run"
           | authenticatedProductScenarioJournalRowRunId authenticatedJournalRow
               /= recordedRunId
           ]
        <> [ "authenticated journal row material differs from Report's exact semantic row"
           | not
               ( authenticatedProductScenarioJournalRowMaterialMatches
                   authenticatedJournalRow
                   expectedAuthenticatedRowMaterial
               )
           ]
        <> ["journal run identity is invalid" | not (validProductScenarioRunId recordedRunId)]
        <> [ "journal executable path is not an absolute canonical path"
           | not (canonicalAbsolutePath recordedExecutablePath)
           ]
        <> [ "journal executable SHA-256 is not canonical lowercase hexadecimal"
           | not (canonicalSha256 recordedExecutableSha256)
           ]
        <> [ "journal invocation digest is not canonical lowercase hexadecimal"
           | not (canonicalSha256 recordedInvocationDigest)
           ]
        <> [ "Store-admitted completion has no ProductScenario invocation"
           | isNothing admittedInvocation
           ]
        <> [ "journal invocation digest differs from exact Store-admitted completion"
           | (productScenarioInvocationDigest <$> admittedInvocation)
               /= Just recordedInvocationDigest
           ]
        <> [ "Store-admitted invocation run differs from persisted row run"
           | (productScenarioInvocationRunId <$> admittedInvocation)
               /= Just recordedRunId
           ]
        <> [ "Store-admitted invocation row differs from current ProductProjection"
           | (productScenarioInvocationRowId <$> admittedInvocation)
               /= Just rowId
           ]
        <> [ "Store-admitted invocation PlanId differs from current ProductProjection"
           | (productScenarioInvocationPlanId <$> admittedInvocation)
               /= Just (ProductMatrix.productProjectionPlanId projection)
           ]
        <> [ "Store-admitted invocation substrate differs from current ProductProjection"
           | (productScenarioInvocationSubstrate <$> admittedInvocation)
               /= Just (ProductMatrix.productProjectionSubstrate projection)
           ]
        <> [ "Store-admitted invocation checkpoint scope differs from exact admission"
           | (productScenarioInvocationCheckpointScopeDigest <$> admittedInvocation)
               /= Just addressedCheckpointScopeDigest
           ]
        <> [ "Store-admitted invocation executable SHA differs from persisted executable"
           | (productScenarioInvocationExecutableSha256 <$> admittedInvocation)
               /= Just recordedExecutableSha256
           ]
        <> [ "journal experiment differs from current ProductProjection"
           | recordedExperiment /= expectedExperiment
           ]
        <> ["journal manifest differs from exact Store admission" | recordedManifestSha /= expectedManifestSha]
        <> [ "journal command differs from current ProductProjection command"
           | recordedCommand /= expectedCommand
           ]
        <> [ "journal contract digest differs from current report contract"
           | recordedContractDigest /= expectedContractDigest
           ]
        <> [ "journal checkpoint scope differs from the exact Store admission scope"
           | recordedCheckpointScopeDigest /= addressedCheckpointScopeDigest
           ]
        <> [ "persisted execution receipt differs from the exact current local-workflow receipt"
           | recordedJournalReceipt /= expectedJournalReceipt
           ]
        <> [ "persisted execution journal digest does not hash the exact execution receipt"
           | recordedJournalDigest /= expectedJournalDigest
           ]
        <> [ "journal inference receipt differs from exact admitted manifest"
           | recordedInferenceManifestSha /= recordedManifestSha
           ]
        <> ["pre-completion inference rejection is absent" | not preconditionRejected]
        <> [ "scenario receipt sequences are not the exact successful local-workflow chronology"
           | (preconditionSequence, inferenceSequence, completionSequence) /= (3, 7, 9)
           ]

requiredJournalSequence
  :: (LiveJournalEvent terminal violation missing -> Bool)
  -> [LiveJournalRecord terminal violation missing]
  -> Word64
requiredJournalSequence select journal =
  case [ liveJournalSequence record
       | record <- journal
       , select (liveJournalEvent record)
       ] of
    [sequenceNumber] -> sequenceNumber
    _ -> 0

productScenarioJournalReceipt
  :: ProductMatrix.ProductProjection kind
  -> Text
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> Text
  -> Text
  -> Text
  -> Placement
  -> [LiveJournalRecord terminal violation missing]
  -> Either Text Text
productScenarioJournalReceipt
  projection
  runId
  checkpointRoot
  checkpointScopeDigest
  executablePath
  executableSha256
  pinnedExecutablePath
  invocationDigest
  manifestSha
  expectedCommand
  expectedPreconditionReceipt
  placement
  journal =
    case journal of
      [ LiveJournalRecord 1 (PlacementAcquired acquired)
        , LiveJournalRecord 2 (LocalEvidenceSourceReady sourceName sourceAddress)
        , LiveJournalRecord 3 (LocalPreconditionObserved preconditionReceipt)
        , LiveJournalRecord 4 (CommandPublicationStarted commandAddress startedCommand)
        , LiveJournalRecord 5 (CommandPublished publishedAddress publishedCommand acknowledgement)
        , LiveJournalRecord 6 (LocalEvidenceResolutionStarted resolverCommand)
        , LiveJournalRecord 7 (LocalEvidenceObserved evidenceAddress evidencePayload)
        , LiveJournalRecord 8 ProtocolEvidenceAccepted
        , LiveJournalRecord 9 ProtocolEvidenceCompleted
        , LiveJournalRecord 10 (DiagnosticsGathered diagnostics)
        , LiveJournalRecord 11 (PlacementReleased released)
        ]
          | acquired == placement
          , isExpectedHostPlacement acquired
          , sourceName == expectedSourceName
          , sourceAddress == expectedSourceAddress
          , preconditionReceipt == expectedPreconditionReceipt
          , commandAddress == expectedCommandAddress
          , startedCommand == expectedCommand
          , publishedAddress == expectedCommandAddress
          , publishedCommand == expectedCommand
          , acknowledgement == expectedAcknowledgement
          , resolverCommand == expectedCommand
          , evidenceAddress == expectedSourceAddress
          , evidencePayload == expectedEvidencePayload
          , diagnostics == expectedDiagnostics
          , released == placement ->
              Right
                ( expectedProductScenarioJournalReceipt
                    projection
                    runId
                    checkpointRoot
                    checkpointScopeDigest
                    executablePath
                    executableSha256
                    pinnedExecutablePath
                    invocationDigest
                    manifestSha
                    expectedCommand
                    expectedPreconditionReceipt
                )
      _ ->
        Left
          "local scenario journal is not the exact 11-event successful executable receipt"
   where
    expectedSourceName = productScenarioSourceName projection
    expectedSourceAddress =
      productScenarioSourceAddress runId invocationDigest projection
    expectedCommandAddress = "subprocess:jitml"
    expectedAcknowledgement =
      productScenarioExecutionAcknowledgement
        executableSha256
        invocationDigest
        (productScenarioExecutedCommand projection checkpointRoot pinnedExecutablePath)
    expectedEvidencePayload =
      productScenarioEvidencePayload runId invocationDigest projection manifestSha
    expectedDiagnostics =
      [ LiveDiagnostic
          ( "product scenario working directory: "
              <> Text.pack (productScenarioWorkdir checkpointRoot)
          )
      ]
    isExpectedHostPlacement (HostRun handle) =
      hostRunHandlePlanId handle == ProductMatrix.productProjectionPlanId projection
        && hostRunHandleKey handle
          == "product-row-" <> ProductMatrix.productProjectionRowId projection
    isExpectedHostPlacement _ = False

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

productScenarioReportContractDigest :: ProductScenarioReportContract -> Text
productScenarioReportContractDigest contract =
  sha256Text
    ( "jitml-product-scenario-report-contract-v1\NUL"
        <> Text.pack (show contract)
    )

-- | Public read-only digest of the current projection's complete report-only
-- contract.  The structured contract and its constructor remain private.
productScenarioProjectionContractDigest
  :: ProductMatrix.ProductProjection kind
  -> Text
productScenarioProjectionContractDigest =
  productScenarioReportContractDigest . productScenarioReportContract

canonicalProductScenarioCheckpointRoot :: FilePath -> IO (Either Text FilePath)
canonicalProductScenarioCheckpointRoot checkpointRoot = do
  attempted <-
    try
      ( do
          createDirectoryIfMissing True checkpointRoot
          canonicalizePath checkpointRoot
      )
      :: IO (Either IOException FilePath)
  pure $ case attempted of
    Left exception -> Left (Text.pack (show exception))
    Right canonicalRoot -> Right canonicalRoot

productScenarioExecutableIdentity
  :: FilePath
  -> IO (Either Text (FilePath, Text, ByteString.ByteString))
productScenarioExecutableIdentity executablePath = do
  attempted <-
    try
      ( do
          canonicalExecutablePath <- canonicalizePath executablePath
          executableBytes <- ByteString.readFile canonicalExecutablePath
          pure (canonicalExecutablePath, sha256Bytes executableBytes, executableBytes)
      )
      :: IO (Either IOException (FilePath, Text, ByteString.ByteString))
  pure $ case attempted of
    Left exception -> Left (Text.pack (show exception))
    Right identity -> Right identity

pinProductScenarioExecutable
  :: FilePath
  -> Text
  -> ByteString.ByteString
  -> IO (Either Text FilePath)
pinProductScenarioExecutable checkpointRoot executableSha256 executableBytes = do
  attempted <-
    try
      ( do
          let pinDirectory =
                takeDirectory
                  (productScenarioPinnedExecutablePath checkpointRoot executableSha256)
              pinnedPath =
                productScenarioPinnedExecutablePath checkpointRoot executableSha256
              ownerDirectoryMode =
                ownerReadMode
                  `unionFileModes` ownerWriteMode
                  `unionFileModes` ownerExecuteMode
              ownerExecutableMode = ownerReadMode `unionFileModes` ownerExecuteMode
          createDirectoryIfMissing True pinDirectory
          setFileMode pinDirectory ownerDirectoryMode
          withTempFile pinDirectory ".jitml.tmp" $ \temporaryPath handle -> do
            ByteString.hPut handle executableBytes
            hFlush handle
            setFileMode temporaryPath ownerExecutableMode
            renameFile temporaryPath pinnedPath
          setFileMode pinnedPath ownerExecutableMode
          canonicalPinnedPath <- canonicalizePath pinnedPath
          pinnedBytes <- ByteString.readFile canonicalPinnedPath
          if sha256Bytes pinnedBytes == executableSha256
            then pure canonicalPinnedPath
            else ioError (userError "pinned executable bytes differ from the authorized digest")
      )
      :: IO (Either IOException FilePath)
  pure $ case attempted of
    Left exception -> Left (Text.pack (show exception))
    Right pinnedPath -> Right pinnedPath

-- | Re-read the mode-restricted private content-pinned copy immediately around
-- execution.  The configured parent path may be replaced after the
-- precondition, but it is never executed; only this copy may satisfy the
-- receipt.
revalidateProductScenarioPinnedExecutable
  :: ProductScenarioPrecondition kind
  -> IO (Either ProductScenarioPreconditionError ())
revalidateProductScenarioPinnedExecutable precondition = do
  observed <-
    productScenarioExecutableIdentity
      (productScenarioPreconditionPinnedExecutablePath precondition)
  pure $ case observed of
    Left detail ->
      Left
        ( ProductScenarioExecutablePinFailed
            rowId
            pinnedPath
            detail
        )
    Right (canonicalPath, observedSha256, _bytes)
      | canonicalPath /= pinnedPath ->
          Left
            ( ProductScenarioExecutablePinFailed
                rowId
                pinnedPath
                "pinned executable canonical path changed"
            )
      | observedSha256 /= expectedSha256 ->
          Left
            ( ProductScenarioExecutableDigestMismatch
                rowId
                expectedSha256
                observedSha256
            )
      | otherwise -> Right ()
 where
  ProductScenarioPrecondition
    _invocation
    _checkpointRoot
    _scopeDigest
    _configuredPath
    expectedSha256
    pinnedPath
    projection
    _rejection = precondition
  rowId = ProductMatrix.productProjectionRowId projection

validProductScenarioRunId :: Text -> Bool
validProductScenarioRunId runId =
  not (Text.null runId)
    && Text.strip runId == runId
    && Text.length runId <= 256
    && not (Text.any isControl runId)

canonicalAbsolutePath :: FilePath -> Bool
canonicalAbsolutePath path = isAbsolute path && normalise path == path

canonicalSha256 :: Text -> Bool
canonicalSha256 digest =
  Text.length digest == 64
    && Text.all (\char -> char `elem` (['0' .. '9'] <> ['a' .. 'f'])) digest

-- | Stable identity for one physically canonical local checkpoint namespace.
-- Admission paths create the directory and resolve every symlink before this
-- digest is computed, so retargeting a symlink cannot preserve the scope.
productScenarioCheckpointScopeDigest :: FilePath -> Text
productScenarioCheckpointScopeDigest checkpointRoot =
  sha256Text
    ( "jitml-product-scenario-checkpoint-scope-v1\NUL"
        <> Text.pack (normalise checkpointRoot)
    )

expectedProductScenarioPreconditionReceipt
  :: ProductMatrix.ProductProjection kind
  -> Text
  -> Text
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> Text
expectedProductScenarioPreconditionReceipt
  projection
  runId
  checkpointScopeDigest
  executablePath
  executableSha256
  pinnedExecutablePath
  invocationDigest =
    receiptLine
      0
      [ "product-inference-precondition-rejected-v3"
      , runId
      , ProductMatrix.productProjectionRowId projection
      , planIdText (ProductMatrix.productProjectionPlanId projection)
      , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
      , checkpointScopeDigest
      , Text.pack executablePath
      , executableSha256
      , Text.pack pinnedExecutablePath
      , invocationDigest
      ]

-- | Canonical, complete serialization of the successful local-interpreter
-- journal.  Each payload is length-delimited before tab separation, so a
-- command or path containing whitespace cannot alias another event stream.
expectedProductScenarioJournalReceipt
  :: ProductMatrix.ProductProjection kind
  -> Text
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
expectedProductScenarioJournalReceipt
  projection
  runId
  checkpointRoot
  checkpointScopeDigest
  executablePath
  executableSha256
  pinnedExecutablePath
  invocationDigest
  manifestSha
  command
  preconditionReceipt =
    Text.unlines
      [ "jitml-product-scenario-execution-receipt-v3"
      , "run-id\t" <> lengthDelimited runId
      , "checkpoint-scope\t" <> checkpointScopeDigest
      , "executable-path\t" <> lengthDelimited (Text.pack executablePath)
      , "executable-sha256\t" <> executableSha256
      , "pinned-executable-path\t" <> lengthDelimited (Text.pack pinnedExecutablePath)
      , "invocation-digest\t" <> invocationDigest
      , "actual-command\t"
          <> lengthDelimited
            (productScenarioExecutedCommand projection checkpointRoot pinnedExecutablePath)
      , receiptLine
          1
          [ "placement-acquired"
          , "host-run"
          , plan
          , hostKey
          ]
      , receiptLine
          2
          [ "local-evidence-source-ready"
          , sourceName
          , sourceAddress
          ]
      , receiptLine 3 ["local-precondition-observed", preconditionReceipt]
      , receiptLine
          4
          ["command-publication-started", commandAddress, command]
      , receiptLine
          5
          [ "command-published"
          , commandAddress
          , command
          , productScenarioExecutionAcknowledgement
              executableSha256
              invocationDigest
              (productScenarioExecutedCommand projection checkpointRoot pinnedExecutablePath)
          ]
      , receiptLine 6 ["local-evidence-resolution-started", command]
      , receiptLine
          7
          [ "local-evidence-observed"
          , sourceAddress
          , productScenarioEvidencePayload runId invocationDigest projection manifestSha
          ]
      , receiptLine 8 ["protocol-evidence-accepted"]
      , receiptLine 9 ["protocol-evidence-completed"]
      , receiptLine
          10
          [ "diagnostics-gathered"
          , "product scenario working directory: "
              <> Text.pack (productScenarioWorkdir checkpointRoot)
          ]
      , receiptLine
          11
          [ "placement-released"
          , "host-run"
          , plan
          , hostKey
          ]
      ]
   where
    plan = planIdText (ProductMatrix.productProjectionPlanId projection)
    hostKey = "product-row-" <> ProductMatrix.productProjectionRowId projection
    sourceName = productScenarioSourceName projection
    sourceAddress = productScenarioSourceAddress runId invocationDigest projection
    commandAddress = "subprocess:jitml"
    lengthDelimited value = Text.pack (show (Text.length value)) <> ":" <> value

receiptLine :: Word64 -> [Text] -> Text
receiptLine sequenceNumber fields =
  Text.intercalate
    "\t"
    (Text.pack (show sequenceNumber) : fmap lengthDelimited fields)
 where
  lengthDelimited value = Text.pack (show (Text.length value)) <> ":" <> value

productScenarioSourceName :: ProductMatrix.ProductProjection kind -> Text
productScenarioSourceName projection =
  "product-row-" <> ProductMatrix.productProjectionRowId projection <> "-completion"

productScenarioSourceAddress
  :: Text
  -> Text
  -> ProductMatrix.ProductProjection kind
  -> Text
productScenarioSourceAddress runId invocationDigest projection =
  Text.intercalate
    ":"
    [ "local-product-row"
    , runId
    , ProductMatrix.productProjectionRowId projection
    , planIdText (ProductMatrix.productProjectionPlanId projection)
    , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
    , invocationDigest
    ]

productScenarioEvidencePayload
  :: Text
  -> Text
  -> ProductMatrix.ProductProjection kind
  -> Text
  -> Text
productScenarioEvidencePayload runId invocationDigest projection manifestSha =
  Text.intercalate
    ":"
    [ "product-row-completed"
    , runId
    , ProductMatrix.productProjectionRowId projection
    , planIdText (ProductMatrix.productProjectionPlanId projection)
    , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
    , invocationDigest
    , manifestSha
    ]

productScenarioWorkdir :: FilePath -> FilePath
productScenarioWorkdir = takeDirectory . takeDirectory . normalise

productScenarioPinnedExecutablePath :: FilePath -> Text -> FilePath
productScenarioPinnedExecutablePath checkpointRoot executableSha256 =
  normalise
    ( takeDirectory checkpointRoot
        </> "product-scenario-executables"
        </> Text.unpack (productScenarioCheckpointScopeDigest checkpointRoot)
        </> Text.unpack executableSha256
        </> "jitml"
    )

productScenarioExecutedCommand
  :: ProductMatrix.ProductProjection kind
  -> FilePath
  -> FilePath
  -> Text
productScenarioExecutedCommand projection checkpointRoot executablePath =
  renderSubprocess
    ( (subprocess executablePath (ProductMatrix.productProjectionCommand projection))
        { subprocessWorkingDirectory =
            Just (productScenarioWorkdir checkpointRoot)
        }
    )

sha256Text :: Text -> Text
sha256Text = sha256Bytes . Text.Encoding.encodeUtf8

sha256Bytes :: ByteString.ByteString -> Text
sha256Bytes =
  Text.pack
    . concatMap byteHex
    . ByteString.unpack
    . SHA256.hash
 where
  byteHex byte =
    let digits = "0123456789abcdef"
        value = fromIntegral byte
     in [digits !! (value `div` 16), digits !! (value `mod` 16)]

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
    , measuredBrowserProductEvidence = Nothing
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
  , "jitml-integration"
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
      NotRunAfterRefinement blocker ->
        "NOT-RUN (blocked by "
          <> refinementBlockerStanza blocker
          <> " refinement "
          <> refinementBlockerName blocker
          <> ")"

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
      NotRunAfterRefinement blocker ->
        [ "    status: not-run"
        , "    blocked_by:"
        , "      stanza: " <> refinementBlockerStanza blocker
        , "      refinement: " <> refinementBlockerName blocker
        , "      detail: " <> refinementBlockerDetail blocker
        ]

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
        <> browserEvidenceMeasurementLine (measuredBrowserProductEvidence measurements)
        <> renderBrowserEvidenceTable (measuredBrowserProductEvidence measurements)

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
    ]
    || isJust (measuredBrowserProductEvidence measurements)
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

browserEvidenceMeasurementLine
  :: Maybe BrowserEvidenceJournal.BrowserEvidenceReport
  -> [Text]
browserEvidenceMeasurementLine Nothing = []
browserEvidenceMeasurementLine (Just report) =
  [ "  browser_product_matrix: "
      <> showText passed
      <> "/"
      <> showText (length entries)
      <> " Passed"
  ]
 where
  entries = BrowserEvidenceJournal.browserEvidenceReportEntries report
  passed =
    length
      [ ()
      | entry <- entries
      , BrowserEvidenceJournal.browserEvidenceResultStatus entry
          == BrowserEvidenceJournal.BrowserPassed
      ]

renderBrowserEvidenceTable
  :: Maybe BrowserEvidenceJournal.BrowserEvidenceReport
  -> [Text]
renderBrowserEvidenceTable Nothing = []
renderBrowserEvidenceTable (Just report) =
  "browser_rows:"
    : "  ordinal\trow_id\tplan_id\texperiment_hash\tmanifest_sha256\te2e_test\tstatus\tdetail"
    : fmap renderEntry (BrowserEvidenceJournal.browserEvidenceReportEntries report)
 where
  renderEntry entry =
    "  "
      <> Text.intercalate
        "\t"
        [ showText (BrowserEvidenceJournal.browserEvidenceResultOrdinal entry)
        , BrowserEvidenceJournal.browserEvidenceResultRowId entry
        , BrowserEvidenceJournal.browserEvidenceResultPlanId entry
        , BrowserEvidenceJournal.browserEvidenceResultExperimentHash entry
        , BrowserEvidenceJournal.browserEvidenceResultManifestSha256 entry
        , BrowserEvidenceJournal.browserEvidenceResultE2ETest entry
        , BrowserEvidenceJournal.renderBrowserEvidenceStatus
            (BrowserEvidenceJournal.browserEvidenceResultStatus entry)
        , BrowserEvidenceJournal.browserEvidenceResultDetail entry
        ]

renderProductRowEvidenceTable :: ReportMeasurements -> [Text]
renderProductRowEvidenceTable measurements =
  case measuredProductRowEvidence measurements of
    Nothing -> []
    Just report ->
      ( "product_rows:"
          : fmap
            ("  " <>)
            ( Text.lines
                (renderCompletedProductScenarioEvidence report)
            )
      )
        -- The compact five-column block above stays the machine summary. The
        -- issuable block below is the exact seven-column text a committed lane
        -- attestation must contain, so a re-issuance is a copy of measured
        -- evidence rather than a transcription.
        <> ( "product_lane_fragment:"
               : fmap
                 ("  " <>)
                 ( Text.lines
                     ( renderProductLaneAttestationFragment
                         report
                         ProductMatrix.nonProductRows
                     )
                 )
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

-- | Issue the committed seven-column lane fragment from completed scenario
-- evidence alone.
--
-- Every product cell is derived from the opaque 'CompletedProductScenarioReport',
-- which only the in-process interpreter receipt or the cross-process journal
-- re-mint can produce, so no prose table or hand-edited total can attest a row
-- the live lane did not prove. There is deliberately no @MISSING@ branch:
-- coverage, duplicates, orphans, plan identity, lane identity, and contract
-- staleness are already fail-closed in 'projectCompletedProductScenarioReport',
-- and the projection re-emits rows in canonical registry order. Non-product rows
-- carry no scenario evidence by construction, so they remain declared literals.
renderProductLaneAttestationFragment
  :: CompletedProductScenarioReport
  -> [ProductMatrix.NonProductRow]
  -> Text
renderProductLaneAttestationFragment report nonProductRows =
  Text.unlines
    ( productLaneAttestationHeader
        : fmap renderCompletedRow (completedProductScenarioReportEntries report)
          <> fmap renderNonProductRow nonProductRows
    )
 where
  renderCompletedRow completed =
    let contract = scenarioEvidenceContract completed
        lane = scenarioEvidenceLane completed
     in Text.intercalate
          "\t"
          [ scenarioEvidenceRowId completed
          , "generated-matrix:" <> scenarioEvidenceExperimentHash completed
          , productContractIntegrationTest contract
          , productContractE2ETest contract
          , negativeControlCell completed
          , DeviceWitness.renderDeviceExecutionWitness
              (completedProductScenarioDeviceWitness completed)
          , renderSubstrate lane
          ]
  -- The journal hard-gates this flag: a completed row whose pre-completion
  -- inference rejection is absent never refines into evidence. Emitting a
  -- distinct non-attesting token rather than the literal keeps the cell honest
  -- if that gate is ever loosened upstream.
  negativeControlCell completed
    | scenarioEvidencePreconditionRejected completed = "checkpoint-required-fail-closed"
    | otherwise = "negative-control-absent"
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

productLaneAttestationHeader :: Text
productLaneAttestationHeader =
  "row_id\tCatalog\tIntegration\tE2E\tNegative\tDeviceEvidence\tLane"

-- | Compare a committed lane attestation against the journal-derived issuance.
--
-- The committed document's table is extracted with the same predicate
-- 'parseProductRowReportEvidenceTable' uses, so the comparator and the parser
-- can never disagree about which lines are \"the table\". An empty result means
-- the committed fragment is exactly what the live lane issued.
productLaneAttestationFragmentDrift :: Text -> Text -> [Text]
productLaneAttestationFragmentDrift committed issued =
  headerFailures <> rowFailures
 where
  committedRows = attestationTableRows committed
  issuedRows = attestationTableRows issued
  headerFailures =
    [ "committed lane attestation is missing the canonical seven-column header"
    | not (any ((productLaneAttestationHeader ==) . Text.strip) (Text.lines committed))
    ]
  rowFailures =
    [ failure
    | rowId' <- orderedRowIds
    , failure <- compareRow rowId'
    ]
  orderedRowIds =
    fmap fst issuedRows
      <> [rowId' | (rowId', _) <- committedRows, rowId' `notElem` fmap fst issuedRows]
  compareRow rowId' =
    case (lookup rowId' issuedRows, lookup rowId' committedRows) of
      (Just _, Nothing) ->
        ["committed lane attestation is missing issued row: " <> rowId']
      (Nothing, Just _) ->
        ["committed lane attestation carries a row the live lane did not issue: " <> rowId']
      (Just issuedCells, Just committedCells) ->
        [ "row "
            <> rowId'
            <> " column "
            <> column
            <> ": committed "
            <> renderCell committedCell
            <> " but the live lane issued "
            <> renderCell issuedCell
        | (column, issuedCell, committedCell) <-
            zip3 productLaneAttestationColumns issuedCells committedCells
        , issuedCell /= committedCell
        ]
          <> [ "row "
                 <> rowId'
                 <> ": committed cell count "
                 <> showText (length committedCells)
                 <> " does not match the issued cell count "
                 <> showText (length issuedCells)
             | length committedCells /= length issuedCells
             ]
      (Nothing, Nothing) -> []
  renderCell cell
    | Text.null cell = "<empty>"
    | otherwise = cell

productLaneAttestationColumns :: [Text]
productLaneAttestationColumns =
  ["Catalog", "Integration", "E2E", "Negative", "DeviceEvidence", "Lane"]

-- | The tab-bearing product rows of a lane attestation, keyed by row id.
--
-- This mirrors 'parseProductRowReportEvidenceTable' exactly, including its
-- non-product and header exclusions, so a document the parser accepts and a
-- document the comparator inspects are the same set of lines.
attestationTableRows :: Text -> [(Text, [Text])]
attestationTableRows content =
  [ (rowId', cells)
  | line <- Text.lines content
  , let stripped = Text.strip line
  , not (Text.null stripped)
  , "\t" `Text.isInfixOf` stripped
  , not ("row_id\t" `Text.isPrefixOf` stripped)
  , not ("non-product:" `Text.isInfixOf` stripped)
  , not ("not-required" `Text.isInfixOf` stripped)
  , rowId' : cells <- [Text.splitOn "\t" stripped]
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

showText :: (Show a) => a -> Text
showText = Text.pack . show

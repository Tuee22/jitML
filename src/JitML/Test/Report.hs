{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( BlockedBy
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
  , RowIntegrationEvidence (..)
  , aggregateProductLaneAttestations
  , appendInvocation
  , appendInvocationJournal
  , blockedByFailure
  , blockedByStanza
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
  , productRowReportCoverageFailures
  , productLaneAttestationFailures
  , renderReportCardWithKnobs
  , renderProductRowReportEvidence
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
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import System.Exit (ExitCode (..))

import JitML.Product.Matrix qualified as ProductMatrix
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
  { blockedByStanza :: !Text
  , blockedByFailure :: !ObservedProcessFailure
  }
  deriving stock (Eq, Show)

-- | One append-only journal row. For executed rows the command is derived from
-- the retained outcome. For 'NotRun' rows it is the exact rendered command that
-- would have run.
data InvocationRecord = InvocationRecord
  { invocationStanza :: !Text
  , invocationCommand :: !Text
  , invocationResult :: !InvocationResult
  }
  deriving stock (Eq, Show)

-- | Chronological invocation evidence. The constructor stays hidden so callers
-- can only append rows; they cannot rewrite or delete earlier observations.
newtype InvocationJournal = InvocationJournal
  { invocationJournalEntries :: [InvocationRecord]
  }
  deriving stock (Eq, Show)

-- | Aggregate values projected only from invocation evidence.
data SuiteStatus
  = SuitePassed
  | SuiteFailed
  | SuiteNotRun
  deriving stock (Eq, Show)

data SuiteResult = SuiteResult
  { suiteStatus :: !SuiteStatus
  , suitePassed :: !Int
  , suiteFailed :: !Int
  , suiteNotRun :: !Int
  , suiteDuration :: !ProcessDuration
  }
  deriving stock (Eq, Show)

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
    { invocationStanza = stanza
    , invocationCommand = processTranscriptCommand transcript
    , invocationResult = Passed transcript
    }

failedInvocation :: Text -> ProcessFailure -> InvocationRecord
failedInvocation stanza failure =
  failedObservedInvocation stanza (ObservedProcessExitFailure failure)

failedObservedInvocation :: Text -> ObservedProcessFailure -> InvocationRecord
failedObservedInvocation stanza failure =
  InvocationRecord
    { invocationStanza = stanza
    , invocationCommand = observedProcessFailureCommand failure
    , invocationResult = Failed failure
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
    { invocationStanza = stanza
    , invocationCommand = command
    , invocationResult = NotRun (BlockedBy blockerStanza blocker)
    }

deriveSuiteResult :: InvocationJournal -> SuiteResult
deriveSuiteResult (InvocationJournal entries) =
  SuiteResult
    { suiteStatus = status
    , suitePassed = passed
    , suiteFailed = failed
    , suiteNotRun = notRun
    , suiteDuration =
        ProcessDuration
          (sum (fmap (invocationDurationNanoseconds . invocationResult) entries))
    }
 where
  passed = length [() | InvocationRecord {invocationResult = Passed _} <- entries]
  failed = length [() | InvocationRecord {invocationResult = Failed _} <- entries]
  notRun = length [() | InvocationRecord {invocationResult = NotRun _} <- entries]
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
        { invocationResult = Failed (ObservedProcessExitFailure failure)
        }
        : _
      ) = Just failure
  firstFailure (InvocationRecord {invocationResult = Failed _} : _) = Nothing
  firstFailure (_ : rest) = firstFailure rest

firstObservedInvocationFailure
  :: InvocationJournal
  -> Maybe ObservedProcessFailure
firstObservedInvocationFailure (InvocationJournal entries) =
  firstFailure entries
 where
  firstFailure [] = Nothing
  firstFailure (InvocationRecord {invocationResult = Failed failure} : _) =
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
  , measuredProductRowEvidence :: [ProductRowReportEvidence]
  -- ^ Sprint `28.3` per-ProductRow evidence table. Empty for non-live or
  -- non-row-complete target sets; complete live report cards fail before
  -- rendering if any required product-row cell is missing.
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
    , measuredProductRowEvidence = []
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
renderProductRowEvidenceTable measurements
  | null (measuredProductRowEvidence measurements) = []
  | otherwise =
      "product_rows:"
        : fmap
          ("  " <>)
          ( Text.lines
              ( renderProductRowReportEvidence
                  ProductMatrix.allProductRows
                  ProductMatrix.nonProductRows
                  (measuredProductRowEvidence measurements)
              )
          )

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

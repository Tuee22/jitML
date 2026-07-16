-- | Append-only subprocess evidence for one resource-scoped test scenario.
--
-- Test invocations are projected separately into 'JitML.Test.Report' so suite
-- counts cannot accidentally include bootstrap, diagnostics, or teardown.
-- This journal retains those lifecycle attempts alongside the body attempt,
-- including their complete process transcripts and non-zero failures.
module JitML.Test.ScenarioJournal
  ( ScenarioDisposition (..)
  , ScenarioIssue
  , ScenarioJournal
  , ScenarioPhase (..)
  , ScenarioRecord
  , appendScenarioJournal
  , appendScenarioIssue
  , appendScenarioRecord
  , emptyScenarioJournal
  , scenarioJournalName
  , scenarioJournalIssues
  , scenarioJournalRecords
  , scenarioRecordDisposition
  , scenarioRecordOutcome
  , scenarioRecordPhase
  , scenarioRecordStep
  , scenarioIssueDetail
  , scenarioIssuePhase
  , scenarioIssueStep
  )
where

import Data.Text (Text)

import JitML.Sub.Outcome (ObservedProcessOutcome)

data ScenarioPhase
  = ScenarioAcquire
  | ScenarioBody
  | ScenarioDiagnostics
  | ScenarioRelease
  deriving stock (Eq, Show)

-- | The original observed attempt remains authoritative.  An accepted no-op
-- is explicit rather than rewriting a real non-zero teardown transcript into
-- a synthetic success.
data ScenarioDisposition
  = ScenarioStepSucceeded
  | ScenarioStepFailed
  | ScenarioStepAcceptedNoop
  deriving stock (Eq, Show)

data ScenarioRecord = ScenarioRecord
  { scenarioRecordPhase :: !ScenarioPhase
  , scenarioRecordStep :: !Text
  , scenarioRecordDisposition :: !ScenarioDisposition
  , scenarioRecordOutcome :: !ObservedProcessOutcome
  }
  deriving stock (Eq, Show)

data ScenarioIssue = ScenarioIssue
  { scenarioIssuePhase :: !ScenarioPhase
  , scenarioIssueStep :: !Text
  , scenarioIssueDetail :: !Text
  }
  deriving stock (Eq, Show)

data ScenarioJournal = ScenarioJournal
  { scenarioJournalName :: !Text
  , scenarioJournalRecords :: ![ScenarioRecord]
  , scenarioJournalIssues :: ![ScenarioIssue]
  }
  deriving stock (Eq, Show)

emptyScenarioJournal :: Text -> ScenarioJournal
emptyScenarioJournal name =
  ScenarioJournal
    { scenarioJournalName = name
    , scenarioJournalRecords = []
    , scenarioJournalIssues = []
    }

appendScenarioRecord
  :: ScenarioJournal
  -> ScenarioPhase
  -> Text
  -> ScenarioDisposition
  -> ObservedProcessOutcome
  -> ScenarioJournal
appendScenarioRecord journal phase step disposition outcome =
  journal
    { scenarioJournalRecords =
        scenarioJournalRecords journal
          <> [ ScenarioRecord
                 { scenarioRecordPhase = phase
                 , scenarioRecordStep = step
                 , scenarioRecordDisposition = disposition
                 , scenarioRecordOutcome = outcome
                 }
             ]
    }

appendScenarioJournal :: ScenarioJournal -> ScenarioJournal -> ScenarioJournal
appendScenarioJournal left right =
  left
    { scenarioJournalRecords =
        scenarioJournalRecords left <> scenarioJournalRecords right
    , scenarioJournalIssues =
        scenarioJournalIssues left <> scenarioJournalIssues right
    }

appendScenarioIssue
  :: ScenarioJournal
  -> ScenarioPhase
  -> Text
  -> Text
  -> ScenarioJournal
appendScenarioIssue journal phase step detail =
  journal
    { scenarioJournalIssues =
        scenarioJournalIssues journal
          <> [ ScenarioIssue
                 { scenarioIssuePhase = phase
                 , scenarioIssueStep = step
                 , scenarioIssueDetail = detail
                 }
             ]
    }

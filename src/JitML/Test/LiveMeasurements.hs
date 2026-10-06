{-# LANGUAGE OverloadedStrings #-}

-- | The live report's measurements as pure projections of evidence the live
-- scope already captured.
--
-- The report never launches a probe, retrains a model, or issues a request
-- after the tests it labels.  What a run can say is exactly what its journals
-- hold: the authenticated ProductScenario journal, the authenticated browser
-- journal, and the invocation/scenario journals.  This module decides the
-- 'Measurement' state of each report field from those:
--
-- * a field no selected stage produces is 'NotRequested';
-- * a field whose evidence was not collected because the live scope stopped, or
--   because its journal was rejected, is 'Unavailable' with the reason, never
--   'NotRequested';
-- * a field with journal evidence is 'Available'.
--
-- Every decision the test command makes about a measurement lives here, in a
-- function the command calls verbatim, so the unit tests run the exact
-- composition the live command runs.  The command keeps only effects: it builds
-- the journal reader from its private scope, retires signing capabilities, and
-- threads the selected targets in.
module JitML.Test.LiveMeasurements
  ( LiveMeasurementRequest (..)
  , ProductScenarioRead
  , browserEvidenceGateFailure
  , browserRefinementOutcome
  , edgeHealthzNotJournaled
  , edgeMetricsNotJournaled
  , liveFailureMeasurements
  , liveMeasurementRequest
  , liveMeasurements
  , liveScopeFailureReason
  , liveScopeMeasurements
  , productRowsMeasurement
  , productRowsPostBody
  , refinedProductScenarioRead
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Test.BrowserEvidenceJournal qualified as BrowserEvidenceJournal
import JitML.Test.LiveE2EScope
  ( LiveE2EFailure (..)
  , LiveE2ERefinementOutcome (..)
  , LiveE2EScopeResult
  , liveE2EFailureBlockerName
  , liveE2EPostBodyFailure
  , liveE2EPostBodyResult
  , liveE2EScopeFailure
  )
import JitML.Test.Measurement
  ( Measurement (..)
  , UnavailableReason (..)
  )
import JitML.Test.Report
  ( CompletedProductScenarioReport
  , ReportMeasurements (..)
  , notRequestedMeasurements
  )

-- | Which journaled stages the selected targets ask the report to project.
data LiveMeasurementRequest = LiveMeasurementRequest
  { requestsProductRows :: !Bool
  -- ^ The ProductScenario journal (integration acquisition, which the browser
  -- lane always runs first as its producer).
  , requestsBrowserMatrix :: !Bool
  -- ^ The authenticated browser result journal (the e2e stanza).
  }
  deriving stock (Eq, Show)

liveMeasurementRequest :: [Text] -> LiveMeasurementRequest
liveMeasurementRequest targets =
  LiveMeasurementRequest
    { requestsProductRows = "jitml-integration" `elem` targets || browserRequested
    , requestsBrowserMatrix = browserRequested
    }
 where
  browserRequested = "jitml-e2e" `elem` targets

-- | The measurements of a live scope whose journals were read.  The two edge
-- observations are requested by every live run and have no journal to project
-- from, so they are unavailable for that reason, on every path.
liveMeasurements
  :: Measurement CompletedProductScenarioReport
  -> Measurement BrowserEvidenceJournal.BrowserEvidenceReport
  -> ReportMeasurements
liveMeasurements productRows browser =
  notRequestedMeasurements
    { measuredProductRowEvidence = productRows
    , measuredJitCacheHitRate = Unavailable edgeMetricsNotJournaled
    , measuredDaemonHealthz = Unavailable edgeHealthzNotJournaled
    , measuredBrowserProductEvidence = browser
    }

-- | The measurements of a live scope that produced no evidence.  Every
-- requested field is unavailable for the same reason; a failed live body is
-- therefore never indistinguishable from a run that requested nothing.
liveFailureMeasurements
  :: LiveMeasurementRequest
  -> UnavailableReason
  -> ReportMeasurements
liveFailureMeasurements request reason =
  liveMeasurements
    (requested (requestsProductRows request))
    (requested (requestsBrowserMatrix request))
 where
  requested :: Bool -> Measurement evidence
  requested True = Unavailable reason
  requested False = NotRequested

-- | The measurements a finished live scope contributes to the report: the
-- evidence its post-body refined, or the reasoned absence of it.  What is
-- requested is decided here from the selected targets, so the command cannot
-- hand the projection a request that disagrees with the selection.
liveScopeMeasurements
  :: [Text]
  -> LiveE2EScopeResult ReportMeasurements
  -> ReportMeasurements
liveScopeMeasurements targets scoped =
  case liveE2EPostBodyResult scoped of
    Just measurements -> measurements
    Nothing ->
      liveFailureMeasurements
        (liveMeasurementRequest targets)
        (liveScopeFailureReason scoped)

-- | Why a live scope has no post-body evidence.
--
-- A refinement's rejection is named first: the invocation journal blames the
-- same rejection for every row it kept from running (@NotRunAfterRefinement@),
-- so the measurements name the same cause even when a stage failed before the
-- refinement ran.  Otherwise the scope stopped at a process failure, and the
-- reason is that stage's blocker name exactly as the invocation journal's
-- @NOT-RUN@ rows spell it.  That names the stage that stopped collection, which
-- need not be the stage that produces a given measurement.
liveScopeFailureReason :: LiveE2EScopeResult body -> UnavailableReason
liveScopeFailureReason scoped =
  case (liveE2EPostBodyFailure scoped, liveE2EScopeFailure scoped) of
    (Just detail, _) -> EvidenceRejected detail
    (Nothing, Just (LiveE2EProcessFailure failure)) ->
      UpstreamNotRun (liveE2EFailureBlockerName failure)
    (Nothing, Just (LiveE2EPostBodyIssue detail)) -> EvidenceRejected detail
    (Nothing, Nothing) ->
      EvidenceRejected "the live scope returned neither report evidence nor a failure"

-- | The command-owned re-read of the authenticated cross-process ProductScenario
-- journal.  A 'Left' is the refinement's own rejection, already rendered.
type ProductScenarioRead = IO (Either Text CompletedProductScenarioReport)

-- | Adapt the journal reader's typed errors to the rejection text a report
-- issue carries.
refinedProductScenarioRead
  :: (Show err)
  => IO (Either (NonEmpty err) CompletedProductScenarioReport)
  -> ProductScenarioRead
refinedProductScenarioRead =
  fmap
    ( either
        ( \errors ->
            Left
              ( "live product scenario journal refinement failed: "
                  <> Text.pack (show (NonEmpty.toList errors))
              )
        )
        Right
    )

-- | The report's one training-evidence measurement.  Every green integration
-- run must yield product evidence, whether or not an E2E stanza follows it, so
-- the untrusted cross-process receipt is read and fully refined here and a
-- stale, missing, or foreign one fails closed as a typed 'Left' instead of a
-- partially measured report card.  Targets that select no producing stage
-- request nothing and never run the reader.
productRowsMeasurement
  :: [Text]
  -> Maybe ProductScenarioRead
  -> IO (Either Text (Measurement CompletedProductScenarioReport))
productRowsMeasurement targets reader
  | not (requestsProductRows (liveMeasurementRequest targets)) =
      pure (Right NotRequested)
  | otherwise =
      case reader of
        Nothing ->
          pure
            ( Left
                "live product evidence requires an initialized command-owned scenario scope"
            )
        Just readJournal -> do
          attempted <- tryAny readJournal
          pure $
            case attempted of
              Left exception ->
                Left
                  ( "live report measurement collection failed: "
                      <> Text.pack (displayException exception)
                  )
              Right (Left rejection) -> Left rejection
              Right (Right report) -> Right (Available report)

-- | The non-browser live scope's post-body: the measurements a scope with no
-- browser stage contributes once its tests passed.  A rejected journal is a
-- typed post-body issue, never a silently empty report.
productRowsPostBody
  :: [Text]
  -> Maybe ProductScenarioRead
  -> IO (Either Text ReportMeasurements)
productRowsPostBody targets reader = do
  productRows <- productRowsMeasurement targets reader
  pure (fmap (`liveMeasurements` NotRequested) productRows)

-- | The browser stage's final refinement once its authenticated journal has
-- been read.  The ProductScenario report is re-read for the card; when that
-- re-read fails, the report the parent authenticated before the browser stage
-- started is kept so no requested evidence is lost, and the failure is raised
-- as an issue.  A browser journal that is not all @Passed@ raises the gate
-- failure while retaining every explicit row status.
browserRefinementOutcome
  :: CompletedProductScenarioReport
  -> Either Text (Measurement CompletedProductScenarioReport)
  -> BrowserEvidenceJournal.BrowserEvidenceReport
  -> LiveE2ERefinementOutcome ReportMeasurements
browserRefinementOutcome authenticated reread browserReport =
  case reread of
    Left detail ->
      LiveE2ERefinedWithIssue
        (liveMeasurements (Available authenticated) browser)
        ( "live report measurement collection failed after browser refinement: "
            <> detail
        )
    Right productRows
      | BrowserEvidenceJournal.browserEvidenceReportAllPassed browserReport ->
          LiveE2ERefined (liveMeasurements productRows browser)
      | otherwise ->
          LiveE2ERefinedWithIssue
            (liveMeasurements productRows browser)
            (browserEvidenceGateFailure browserReport)
 where
  browser = Available browserReport

-- | The daemon edge @/metrics@ scrape.  The edge port is leased during
-- bootstrap, after the live plan is fixed, so no static plan step can name it
-- and no journal carries the response.
edgeMetricsNotJournaled :: UnavailableReason
edgeMetricsNotJournaled =
  NotJournaled "edge /metrics scrape: the live plan has no step that records it"

-- | The daemon edge @/healthz@ response, unjournaled for the same reason.
edgeHealthzNotJournaled :: UnavailableReason
edgeHealthzNotJournaled =
  NotJournaled "edge /healthz response: the live plan has no step that records it"

-- | The failure text of a browser gate whose journal is not all @Passed@.  The
-- required row count is the journal's own row count: 'readBrowserEvidenceJournal'
-- only refines a journal carrying exactly the rows of the published catalogue
-- expectation, so no separate literal denominator exists.
browserEvidenceGateFailure
  :: BrowserEvidenceJournal.BrowserEvidenceReport
  -> Text
browserEvidenceGateFailure report =
  "browser evidence gate requires exactly "
    <> Text.pack (show (length entries))
    <> " Passed rows; observed Passed="
    <> count BrowserEvidenceJournal.BrowserPassed
    <> ", Failed="
    <> count BrowserEvidenceJournal.BrowserFailed
    <> ", NotRun="
    <> count BrowserEvidenceJournal.BrowserNotRun
 where
  entries = BrowserEvidenceJournal.browserEvidenceReportEntries report
  count status =
    Text.pack
      ( show
          ( length
              ( filter
                  ((== status) . BrowserEvidenceJournal.browserEvidenceResultStatus)
                  entries
              )
          )
      )

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 289: report measurements are evidence-typed projections, not a second
-- measurement path.
--
-- These cases pin the measurement states, the derivation of every count and
-- line from journal rows, the composition the live command runs to turn its
-- journals into a report (every decision lives in
-- "JitML.Test.LiveMeasurements", which the command calls verbatim), and the
-- absence of any post-test probe.  Journal rows are synthesized only where the
-- property is about the projection (every row is a real
-- 'Budget.CompletedTraining' built through its smart constructor); other cases
-- admit the retained CUDA lane journal or read a journal a real executed
-- scenario wrote.
module ReportMeasurements
  ( ProductJournalSource (..)
  , WithProductJournal
  , reportMeasurementTests
  )
where

import Data.ByteString qualified as ByteString
import Data.Char (isAlphaNum, isDigit)
import Data.Foldable (toList, traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan (Validation (..), refinePlanIdText)
import JitML.Product.Convergence (convergenceMetricName)
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix (RowFamily (..))
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Sub.Outcome
  ( ProcessDuration (..)
  , ProcessOutcome
  , ProcessTranscript (..)
  , mkProcessFailure
  , processOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate qualified as Substrate
import JitML.Test.BrowserEvidenceJournal qualified as BrowserEvidenceJournal
import JitML.Test.LiveE2EScope qualified as LiveE2EScope
import JitML.Test.LiveMeasurements qualified as LiveMeasurements
import JitML.Test.LivePlan
  ( LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  )
import JitML.Test.Measurement
  ( Measurement (..)
  , UnavailableReason (..)
  , renderMeasurementLine
  , renderUnavailableReason
  )
import JitML.Test.ProductAggregation qualified as ProductAggregation
import JitML.Test.ProductLaneJournal qualified as ProductLaneJournal
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report qualified as Report
import JitML.Test.TrainingMeasurement (CompletedRowView (..))
import JitML.Test.TrainingMeasurement qualified as Training
import JitML.Training.Budget qualified as Budget

-- | The slice of the ProductScenario journal fixture the composition cases need.
-- The fixture executes real scenarios, so it lives in the unit main; these
-- cases see only the report those scenarios produced and a reader over the
-- journal they wrote.
data ProductJournalSource = ProductJournalSource
  { sourceReport :: !Report.CompletedProductScenarioReport
  -- ^ The report the executed scenarios produced and journaled.
  , sourceRunId :: !Text
  -- ^ The run id the journal is bound to.
  , sourceRead
      :: Text
      -> IO
           ( Either
               (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
               Report.CompletedProductScenarioReport
           )
  -- ^ Read and refine the journal on disk as a reader expecting the given run
  -- id, exactly as the command's re-read does.
  }

-- | Bracket a real journal fixture around one case.
type WithProductJournal = (ProductJournalSource -> Assertion) -> Assertion

reportMeasurementTests :: WithProductJournal -> TestTree
reportMeasurementTests withJournal =
  testGroup
    "Evidence-typed report measurements (Phase 289)"
    [ measurementStateTests
    , suiteCountTests
    , liveMeasurementTests
    , postBodyCompositionTests withJournal
    , trainingMeasurementTests
    , browserDenominatorTests
    , nonLiveCardTests withJournal
    , sourceGuardTests
    ]

-- ---------------------------------------------------------------------------
-- The measurement states
-- ---------------------------------------------------------------------------

measurementStateTests :: TestTree
measurementStateTests =
  testGroup
    "measurement states"
    [ testCase "NotRequested renders no line and requests no header" $ do
        renderMeasurementLine "label" id (NotRequested :: Measurement Text) @?= []
        let rendered = renderCard Report.notRequestedMeasurements
        assertBool
          "an unrequested report rendered a measurements block"
          ("measurements:" `notElem` rendered)
        assertBool
          "an unrequested report rendered an unavailable line"
          (not (any ("unavailable" `Text.isInfixOf`) rendered))
    , testCase "Unavailable renders one line naming the reason of every constructor" $ do
        let line reason =
              renderMeasurementLine "label" id (Unavailable reason :: Measurement Text)
        line (UpstreamNotRun "live-e2e-test/jitml-integration")
          @?= ["  label: unavailable (upstream not run: live-e2e-test/jitml-integration)"]
        line (EvidenceRejected "journal authentication failed")
          @?= ["  label: unavailable (evidence rejected: journal authentication failed)"]
        line (NotJournaled "edge /metrics scrape")
          @?= ["  label: unavailable (not journaled: edge /metrics scrape)"]
    , testCase "Available renders the evidence and only the evidence" $
        renderMeasurementLine "label" ("value=" <>) (Available "42")
          @?= ["  label: value=42"]
    , testCase "not-requested and unavailable are different report states" $ do
        let unavailable =
              Report.notRequestedMeasurements
                { Report.measuredBrowserProductEvidence =
                    Unavailable (UpstreamNotRun "live-e2e-test/jitml-e2e-playwright")
                }
            renderedUnavailable = renderCard unavailable
            renderedNotRequested = renderCard Report.notRequestedMeasurements
        assertBool
          "an unavailable measurement did not name its reason"
          ( "  browser_product_matrix: unavailable (upstream not run: live-e2e-test/jitml-e2e-playwright)"
              `elem` renderedUnavailable
          )
        assertBool
          "the measurements header is missing for a requested measurement"
          ("measurements:" `elem` renderedUnavailable)
        assertBool
          "an unrequested measurement rendered a browser line"
          (not (any ("browser_product_matrix" `Text.isInfixOf`) renderedNotRequested))
        assertBool
          "requested and unrequested reports rendered identically"
          (renderedUnavailable /= renderedNotRequested)
    , testCase "an available browser report renders its journal's own counts and rows" $ do
        report <- browserReport (mixedObservations 2 1)
        let rendered =
              renderCard
                Report.notRequestedMeasurements
                  { Report.measuredBrowserProductEvidence = Available report
                  }
            total = ProductMatrix.productRowCount
            tableRows =
              [ line
              | line <- rendered
              , "\tphase-289-e2e-" `Text.isInfixOf` line
              ]
        assertBool
          "the pass count is not the journal's own Passed/total"
          ( ( "  browser_product_matrix: "
                <> Text.pack (show (total - 3))
                <> "/"
                <> Text.pack (show total)
                <> " Passed"
            )
              `elem` rendered
          )
        assertBool "the browser row table header is missing" ("browser_rows:" `elem` rendered)
        length tableRows @?= total
        assertBool
          "an explicit Failed row lost its detail"
          (any ("Failed\tplaywright failure" `Text.isSuffixOf`) tableRows)
        assertBool
          "an explicit NotRun row lost its detail"
          (any ("NotRun\trow not started" `Text.isSuffixOf`) tableRows)
    , testCase "a multi-line rejection detail cannot corrupt the line-oriented report" $ do
        let detail = "first line\nsecond\tline\r\nthird\ESCline"
            rendered =
              renderCard
                Report.notRequestedMeasurements
                  { Report.measuredBrowserProductEvidence = Unavailable (EvidenceRejected detail)
                  }
        renderUnavailableReason (EvidenceRejected detail)
          @?= "evidence rejected: first line second line third line"
        assertBool
          "the rejection detail was split across report lines"
          ( "  browser_product_matrix: unavailable (evidence rejected: first line second line third line)"
              `elem` rendered
          )
    , testCase "the edge observations have no evidence type, so they are only unrequested or reasoned" $ do
        let live = LiveMeasurements.liveMeasurements NotRequested NotRequested
            rendered = renderCard live
        Report.measuredJitCacheHitRate live
          @?= Unavailable LiveMeasurements.edgeMetricsNotJournaled
        Report.measuredDaemonHealthz live
          @?= Unavailable LiveMeasurements.edgeHealthzNotJournaled
        assertBool
          "the jit cache did not render its journaling gap"
          ( "  jit_cache_hit_rate: unavailable (not journaled: edge /metrics scrape: the live plan has no step that records it)"
              `elem` rendered
          )
        assertBool
          "healthz did not render its journaling gap"
          ( "  daemon_healthz: unavailable (not journaled: edge /healthz response: the live plan has no step that records it)"
              `elem` rendered
          )
    ]

-- ---------------------------------------------------------------------------
-- Suite counts are a projection of the invocation journal
-- ---------------------------------------------------------------------------

suiteCountTests :: TestTree
suiteCountTests =
  testGroup
    "suite counts"
    [ testCase "suite counts and the rendered cabal_test block move with the invocation rows" $ do
        let transcript =
              ProcessTranscript
                { processTranscriptCommand = "cabal test"
                , processTranscriptStdout = "ok\n"
                , processTranscriptStderr = ""
                , processTranscriptWorkingDirectory = Just "/work/jitML"
                , processTranscriptDuration = ProcessDuration 5
                }
        failure <-
          maybe
            (assertFailure "could not construct a non-zero process failure")
            pure
            (mkProcessFailure (ExitFailure 7) transcript)
        let journalOf = foldl Report.appendInvocation Report.emptyInvocationJournal
            base =
              [ Report.passedInvocation "jitml-unit" transcript
              , Report.failedInvocation "jitml-integration" failure
              , Report.notRunInvocation "jitml-e2e" "cabal test jitml-e2e" "jitml-integration" failure
              ]
            counts rows =
              let suite = Report.deriveSuiteResult (journalOf rows)
               in (Report.suitePassed suite, Report.suiteFailed suite, Report.suiteNotRun suite)
            cabalTestBlock rows =
              [ line
              | line <-
                  Text.lines
                    ( Report.renderReportCardWithKnobs
                        Report.defaultReportCardKnobs
                        Report.ReportCard
                          { Report.reportInvocationJournal = journalOf rows
                          , Report.reportScenarioJournals = []
                          , Report.reportMeasurements = Report.notRequestedMeasurements
                          }
                    )
              , any (`Text.isPrefixOf` line) ["  passed:", "  failed:", "  not_run:"]
              ]
        counts base @?= (1, 1, 1)
        counts (base <> [Report.passedInvocation "jitml-backends" transcript]) @?= (2, 1, 1)
        counts (base <> [Report.failedInvocation "jitml-backends" failure]) @?= (1, 2, 1)
        counts
          ( base
              <> [Report.notRunInvocation "jitml-backends" "cabal test jitml-backends" "jitml-integration" failure]
          )
          @?= (1, 1, 2)
        cabalTestBlock base @?= ["  passed: 1", "  failed: 1", "  not_run: 1"]
        cabalTestBlock (base <> [Report.passedInvocation "jitml-backends" transcript])
          @?= ["  passed: 2", "  failed: 1", "  not_run: 1"]
    ]

-- ---------------------------------------------------------------------------
-- The live scope decides states from what its journals hold
-- ---------------------------------------------------------------------------

liveMeasurementTests :: TestTree
liveMeasurementTests =
  testGroup
    "live scope measurements"
    [ testCase "the request is derived from the selected targets" $ do
        LiveMeasurements.liveMeasurementRequest ["jitml-unit"]
          @?= LiveMeasurements.LiveMeasurementRequest False False
        LiveMeasurements.liveMeasurementRequest ["jitml-unit", "jitml-integration"]
          @?= LiveMeasurements.LiveMeasurementRequest True False
        -- The browser lane always runs integration acquisition first, so an
        -- e2e-only selection still requests the ProductScenario journal.
        LiveMeasurements.liveMeasurementRequest ["jitml-e2e"]
          @?= LiveMeasurements.LiveMeasurementRequest True True
    , testCase "a failed test invocation makes every requested measurement unavailable upstream" $ do
        result <-
          runScope
            (scopeBackend (\step -> livePlanStepName step == "jitml-integration"))
            []
            [plannedTest "jitml-integration", plannedTest "jitml-e2e"]
            (pure (Right Report.notRequestedMeasurements))
        let reason = UpstreamNotRun "live-e2e-test/jitml-integration"
            measurements =
              LiveMeasurements.liveScopeMeasurements ["jitml-integration", "jitml-e2e"] result
        LiveMeasurements.liveScopeFailureReason result @?= reason
        Report.measuredProductRowEvidence measurements @?= Unavailable reason
        Report.measuredBrowserProductEvidence measurements @?= Unavailable reason
        -- The selected targets, not a caller-built request, decide which fields
        -- a failed scope reports as requested.
        let integrationOnly =
              LiveMeasurements.liveScopeMeasurements ["jitml-integration"] result
        Report.measuredProductRowEvidence integrationOnly @?= Unavailable reason
        Report.measuredBrowserProductEvidence integrationOnly @?= NotRequested
        let browserOnly = LiveMeasurements.liveScopeMeasurements ["jitml-e2e"] result
        Report.measuredProductRowEvidence browserOnly @?= Unavailable reason
        Report.measuredBrowserProductEvidence browserOnly @?= Unavailable reason
        -- The measurement names the blocked stage exactly as the invocation
        -- journal's own NOT-RUN row does.
        case fmap
          Report.invocationResult
          (Report.invocationJournalEntries (LiveE2EScope.liveE2EInvocationJournal result)) of
          [Report.Failed _, Report.NotRun blocker] ->
            UpstreamNotRun (Report.blockedByStanza blocker) @?= reason
          observed -> assertFailure ("unexpected invocation journal: " <> show observed)
    , testCase "the named upstream stage is the one that stopped the scope, not necessarily the producer" $ do
        -- Integration (the producer of the product rows) passed; the stanza
        -- after it failed.  The interpreter skips its post-body after any
        -- failed invocation, so collection was stopped by that later stanza and
        -- the reason names it, as the NOT-RUN row of the stanza after it does.
        let selected = ["jitml-integration", "jitml-sl-canonicals", "jitml-rl-canonicals"]
        result <-
          runScope
            (scopeBackend (\step -> livePlanStepName step == "jitml-sl-canonicals"))
            []
            (fmap plannedTest selected)
            (pure (Right Report.notRequestedMeasurements))
        let reason = UpstreamNotRun "live-e2e-test/jitml-sl-canonicals"
            measurements = LiveMeasurements.liveScopeMeasurements selected result
        case fmap
          Report.invocationResult
          (Report.invocationJournalEntries (LiveE2EScope.liveE2EInvocationJournal result)) of
          [Report.Passed _, Report.Failed _, Report.NotRun blocker] ->
            UpstreamNotRun (Report.blockedByStanza blocker) @?= reason
          observed -> assertFailure ("unexpected invocation journal: " <> show observed)
        Report.measuredProductRowEvidence measurements @?= Unavailable reason
    , testCase "a rejected final refinement is named ahead of the failed stage before it" $ do
        let detail = "browser result journal refinement failed: [BrowserEvidenceJournalMissing]"
        result <-
          runStagedScope
            (scopeBackend (\step -> livePlanStepName step == "jitml-e2e-playwright"))
            [plannedTest "jitml-integration"]
            (refinement "jitml-integration" "product-browser-catalogue" (LiveE2EScope.LiveE2ERefined ()))
            [plannedTest "jitml-e2e-playwright"]
            ( refinement
                "jitml-e2e-playwright"
                "browser-result-journal"
                (LiveE2EScope.LiveE2ERefinementRejected detail)
            )
            [plannedTest "jitml-e2e"]
        let reason = EvidenceRejected detail
            measurements = LiveMeasurements.liveScopeMeasurements ["jitml-e2e"] result
        -- Both causes are present: Playwright failed, and its journal was then
        -- rejected before anything downstream could run.
        assertBool
          "the failed Playwright stage was not recorded"
          (isJust (LiveE2EScope.liveE2EPrimaryFailure result))
        LiveE2EScope.liveE2EPostBodyFailure result @?= Just detail
        LiveMeasurements.liveScopeFailureReason result @?= reason
        Report.measuredProductRowEvidence measurements @?= Unavailable reason
        Report.measuredBrowserProductEvidence measurements @?= Unavailable reason
        -- The invocation journal blames the same rejection for the row it kept
        -- from running.
        case fmap
          Report.invocationResult
          (Report.invocationJournalEntries (LiveE2EScope.liveE2EInvocationJournal result)) of
          [Report.Passed _, Report.Failed _, Report.NotRunAfterRefinement blocker] ->
            (Report.refinementBlockerName blocker, Report.refinementBlockerDetail blocker)
              @?= ("browser-result-journal", detail)
          observed -> assertFailure ("unexpected invocation journal: " <> show observed)
    , testCase "an unselected stage stays not-requested when the live body fails" $ do
        result <-
          runScope
            (scopeBackend (\step -> livePlanStepName step == "jitml-unit"))
            []
            [plannedTest "jitml-unit"]
            (pure (Right Report.notRequestedMeasurements))
        let measurements = LiveMeasurements.liveScopeMeasurements ["jitml-unit"] result
        Report.measuredProductRowEvidence measurements @?= NotRequested
        Report.measuredBrowserProductEvidence measurements @?= NotRequested
        -- The edge observations are requested by every live run.
        Report.measuredDaemonHealthz measurements
          @?= Unavailable LiveMeasurements.edgeHealthzNotJournaled
    , testCase "a failed acquisition names the acquire step as the blocked upstream" $ do
        result <-
          runScope
            (scopeBackend (\step -> livePlanStepName step == "bootstrap"))
            [scopeStep "bootstrap"]
            [plannedTest "jitml-integration"]
            (pure (Right Report.notRequestedMeasurements))
        LiveMeasurements.liveScopeFailureReason result
          @?= UpstreamNotRun "live-e2e-acquire/bootstrap"
    , testCase "a rejected post-body journal is rejected evidence, not an absent measurement" $ do
        let detail =
              "live product scenario journal refinement failed: [ProductScenarioJournalAuthenticationRejected]"
        result <-
          runScope
            (scopeBackend (const False))
            []
            [plannedTest "jitml-integration"]
            (pure (Left detail))
        let measurements =
              LiveMeasurements.liveScopeMeasurements ["jitml-integration"] result
        Report.measuredProductRowEvidence measurements @?= Unavailable (EvidenceRejected detail)
        Report.measuredBrowserProductEvidence measurements @?= NotRequested
    , testCase "evidence the post-body refined passes through unchanged" $ do
        let refined = LiveMeasurements.liveMeasurements NotRequested NotRequested
        result <-
          runScope
            (scopeBackend (const False))
            []
            [plannedTest "jitml-integration"]
            (pure (Right refined))
        LiveMeasurements.liveScopeMeasurements ["jitml-integration"] result @?= refined
    , testCase "a failed live scope's card names one blocker in its rows and its measurement lines" $ do
        let selected = ["jitml-integration", "jitml-e2e"]
            blocker = "live-e2e-test/jitml-integration"
            upstream = "unavailable (upstream not run: " <> blocker <> ")"
        result <-
          runScope
            (scopeBackend (\step -> livePlanStepName step == "jitml-integration"))
            []
            (fmap plannedTest selected)
            (pure (Right Report.notRequestedMeasurements))
        let rendered =
              Text.lines
                ( Report.renderReportCardWithKnobs
                    Report.defaultReportCardKnobs
                    Report.ReportCard
                      { Report.reportInvocationJournal = LiveE2EScope.liveE2EInvocationJournal result
                      , Report.reportScenarioJournals = []
                      , Report.reportMeasurements =
                          LiveMeasurements.liveScopeMeasurements selected result
                      }
                )
            measurementBlock =
              case dropWhile (/= "measurements:") rendered of
                _header : block -> takeWhile ("  " `Text.isPrefixOf`) block
                [] -> []
        assertBool
          "the fail-fast row does not name the blocker"
          (("  jitml-e2e: NOT-RUN (blocked by " <> blocker <> ")") `elem` rendered)
        -- The exact block, in report order, with no line missing or extra.
        measurementBlock
          @?= [ "  sl_final_loss: " <> upstream
              , "  rl_final_reward: " <> upstream
              , "  alphazero_arena_win_rate: " <> upstream
              , "  tune_best_objective: " <> upstream
              , "  product_row_counts: " <> upstream
              , "  jit_cache_hit_rate: unavailable (not journaled: edge /metrics scrape: the live plan has no step that records it)"
              , "  daemon_healthz: unavailable (not journaled: edge /healthz response: the live plan has no step that records it)"
              , "  browser_product_matrix: " <> upstream
              ]
    ]

-- ---------------------------------------------------------------------------
-- The composition the live command runs once its journals are written
-- ---------------------------------------------------------------------------

-- | The command retires its signing capability, builds the journal reader from
-- its private scope, and calls these functions with the selected targets; they
-- hold every decision, so these cases run the composition the command runs.
postBodyCompositionTests :: WithProductJournal -> TestTree
postBodyCompositionTests withJournal =
  testGroup
    "live post-body composition"
    [ testCase "the journal is read only when the selected targets request product rows" $
        withJournal $ \source -> do
          readCount <- newIORef (0 :: Int)
          let report = sourceReport source
              reader = Just (modifyIORef' readCount (+ 1) >> pure (Right report))
          LiveMeasurements.productRowsMeasurement ["jitml-unit"] reader
            >>= (@?= Right NotRequested)
          readIORef readCount >>= (@?= 0)
          LiveMeasurements.productRowsMeasurement ["jitml-integration"] reader
            >>= (@?= Right (Available report))
          -- An e2e-only selection still requests the ProductScenario journal:
          -- the browser lane runs integration acquisition first.
          LiveMeasurements.productRowsMeasurement ["jitml-e2e"] reader
            >>= (@?= Right (Available report))
          readIORef readCount >>= (@?= 2)
    , testCase "a requested journal without a command-owned scope fails closed" $ do
        LiveMeasurements.productRowsMeasurement ["jitml-unit"] Nothing
          >>= (@?= Right NotRequested)
        LiveMeasurements.productRowsMeasurement ["jitml-integration"] Nothing
          >>= ( @?=
                  Left "live product evidence requires an initialized command-owned scenario scope"
              )
    , testCase "a rejected or crashing journal read is a typed failure, never an empty measurement" $ do
        let rejection =
              "live product scenario journal refinement failed: [ProductScenarioJournalMissing \"journal.json\"]"
        LiveMeasurements.productRowsMeasurement
          ["jitml-integration"]
          (Just (pure (Left rejection)))
          >>= (@?= Left rejection)
        crashed <-
          LiveMeasurements.productRowsMeasurement
            ["jitml-integration"]
            (Just (ioError (userError "journal disk vanished")))
        case crashed of
          Left detail -> do
            assertBool
              ("a crashed read did not name the collection failure: " <> Text.unpack detail)
              ("live report measurement collection failed: " `Text.isPrefixOf` detail)
            assertBool
              ("a crashed read lost the exception: " <> Text.unpack detail)
              ("journal disk vanished" `Text.isInfixOf` detail)
          Right other -> assertFailure ("a crashed journal read produced " <> show other)
    , testCase "the non-browser post-body projects the journal rows into the report" $
        withJournal $ \source -> do
          let report = sourceReport source
          LiveMeasurements.productRowsPostBody
            ["jitml-integration"]
            (Just (pure (Right report)))
            >>= \case
              Right measurements -> do
                Report.measuredProductRowEvidence measurements @?= Available report
                Report.measuredBrowserProductEvidence measurements @?= NotRequested
                Report.measuredJitCacheHitRate measurements
                  @?= Unavailable LiveMeasurements.edgeMetricsNotJournaled
                Report.measuredDaemonHealthz measurements
                  @?= Unavailable LiveMeasurements.edgeHealthzNotJournaled
                let rendered = renderCard measurements
                assertBool
                  "the journal rows never reached the card"
                  ("product_rows:" `elem` rendered)
                assertBool
                  "the RL line lost the journal rows"
                  (any ("  rl_final_reward: DQN/cartpole:" `Text.isPrefixOf`) rendered)
              Left detail -> assertFailure ("the post-body failed: " <> Text.unpack detail)
          -- An unselected run requests no journal but still owns the edge lines.
          LiveMeasurements.productRowsPostBody ["jitml-unit"] Nothing
            >>= (@?= Right (LiveMeasurements.liveMeasurements NotRequested NotRequested))
          -- A rejected journal is a typed post-body failure, never an empty report.
          LiveMeasurements.productRowsPostBody
            ["jitml-integration"]
            (Just (pure (Left "journal rejected")))
            >>= (@?= Left "journal rejected")
    , testCase "the journal a real scenario wrote round-trips through the command's reader adapter" $
        withJournal $ \source -> do
          let reader runId =
                Just (LiveMeasurements.refinedProductScenarioRead (sourceRead source runId))
          LiveMeasurements.productRowsMeasurement
            ["jitml-integration"]
            (reader (sourceRunId source))
            >>= (@?= Right (Available (sourceReport source)))
          rejected <-
            LiveMeasurements.productRowsMeasurement
              ["jitml-integration"]
              (reader "phase-289-another-run")
          case rejected of
            Left detail -> do
              assertBool
                ("the rejection lost its refinement prefix: " <> Text.unpack detail)
                ("live product scenario journal refinement failed: " `Text.isPrefixOf` detail)
              assertBool
                ("the rejection does not name the journal's own error: " <> Text.unpack detail)
                ("ProductScenarioJournalRunIdMismatch" `Text.isInfixOf` detail)
            Right other ->
              assertFailure ("a journal bound to another run was read: " <> show other)
    , testCase "the browser refinement outcome follows the gate and keeps the evidence it holds" $
        withJournal $ \source -> do
          let fullReport = sourceReport source
          -- A report the parent authenticated earlier that differs from the
          -- re-read one, so which of the two a card carries is observable.
          authenticated <- oneRowReport fullReport
          assertBool
            "the authenticated and re-read ProductScenario reports must differ"
            (authenticated /= fullReport)
          passing <- browserReport (mixedObservations 0 0)
          mixed <- browserReport (mixedObservations 2 1)
          let outcome = LiveMeasurements.browserRefinementOutcome authenticated
              reread = Right (Available fullReport)
              expected browser =
                LiveMeasurements.liveMeasurements (Available fullReport) (Available browser)
          -- An all-Passed journal closes the gate and the rows come from the re-read.
          outcome reread passing @?= LiveE2EScope.LiveE2ERefined (expected passing)
          -- A non-green journal keeps every explicit row status and raises the gate.
          outcome reread mixed
            @?= LiveE2EScope.LiveE2ERefinedWithIssue
              (expected mixed)
              (LiveMeasurements.browserEvidenceGateFailure mixed)
          -- A failed re-read keeps the report the parent authenticated and the
          -- browser evidence, and raises the collection failure.
          outcome (Left "journal unreadable") passing
            @?= LiveE2EScope.LiveE2ERefinedWithIssue
              ( LiveMeasurements.liveMeasurements
                  (Available authenticated)
                  (Available passing)
              )
              "live report measurement collection failed after browser refinement: journal unreadable"
    ]

-- | A ProductScenario report of only the first row of a completed one: a real
-- report that differs from it.
oneRowReport
  :: Report.CompletedProductScenarioReport
  -> IO Report.CompletedProductScenarioReport
oneRowReport report =
  case Report.completedProductScenarioReportEntries report of
    firstEvidence : _rest -> do
      row <-
        maybe
          (assertFailure "the journal's first row is not in the registry")
          pure
          ( List.find
              ((== Report.completedProductScenarioRowId firstEvidence) . ProductMatrix.rowId)
              ProductMatrix.allProductRows
          )
      batch <-
        case ProductMatrix.projectProductRows Substrate.LinuxCPU [row] of
          Success projected -> pure projected
          Failure errors -> assertFailure ("one-row projection failed: " <> show errors)
      either
        (assertFailure . ("one-row report was rejected: " <>) . show)
        pure
        (Report.projectCompletedProductScenarioReport batch [firstEvidence])
    [] -> assertFailure "the journal source has no completed row"

-- ---------------------------------------------------------------------------
-- Cards without product evidence stay exactly what they were
-- ---------------------------------------------------------------------------

nonLiveCardTests :: WithProductJournal -> TestTree
nonLiveCardTests withJournal =
  testGroup
    "cards without product evidence"
    [ testCase "a card with no measurements renders exactly the pre-Phase-289 text" $ do
        -- Captured from the renderer before this phase changed it.  The text of
        -- a non-live card is committed to stay byte-identical for the same
        -- inputs, so this pins it in full.
        let transcript stanza =
              ProcessTranscript
                { processTranscriptCommand = "cabal test " <> stanza
                , processTranscriptStdout = "pod-a Running\n"
                , processTranscriptStderr = "kubectl failed"
                , processTranscriptWorkingDirectory = Just "/work/jitML"
                , processTranscriptDuration = ProcessDuration 125_000_000
                }
            journal =
              foldl
                Report.appendInvocation
                Report.emptyInvocationJournal
                [ Report.passedInvocation stanza (transcript stanza)
                | stanza <- ["jitml-unit", "jitml-integration", "jitml-e2e"]
                ]
        Report.renderReportCardWithKnobs
          Report.defaultReportCardKnobs
          Report.ReportCard
            { Report.reportInvocationJournal = journal
            , Report.reportScenarioJournals = []
            , Report.reportMeasurements = Report.notRequestedMeasurements
            }
          @?= Text.unlines
            [ "jitML POC report card"
            , "knobs:"
            , "  sl_epochs: 5"
            , "  sl_batch: 64"
            , "  rl_steps: 100000"
            , "  rl_eval_episodes: 25"
            , "  alphazero_games: 200"
            , "  alphazero_sims: 400"
            , "  tune_trials: 64"
            , "  tune_budget_per_trial: 1000"
            , "  xcluster_kind_nodes: 2"
            , "stanzas:"
            , "  jitml-unit: PASS"
            , "  jitml-integration: PASS"
            , "  jitml-e2e: PASS"
            , "cabal_test:"
            , "  status: passed"
            , "  passed: 3"
            , "  failed: 0"
            , "  not_run: 0"
            , "  duration_seconds: 0.375000000"
            , "  duration_nanoseconds: 375000000"
            , "invocation_journal:"
            , "  - stanza: jitml-unit"
            , "    command: cabal test jitml-unit"
            , "    status: passed"
            , "    exit: 0"
            , "    working_directory: /work/jitML"
            , "    duration_nanoseconds: 125000000"
            , "    stdout:"
            , "      pod-a Running"
            , "    stderr:"
            , "      kubectl failed"
            , "  - stanza: jitml-integration"
            , "    command: cabal test jitml-integration"
            , "    status: passed"
            , "    exit: 0"
            , "    working_directory: /work/jitML"
            , "    duration_nanoseconds: 125000000"
            , "    stdout:"
            , "      pod-a Running"
            , "    stderr:"
            , "      kubectl failed"
            , "  - stanza: jitml-e2e"
            , "    command: cabal test jitml-e2e"
            , "    status: passed"
            , "    exit: 0"
            , "    working_directory: /work/jitML"
            , "    duration_nanoseconds: 125000000"
            , "    stdout:"
            , "      pod-a Running"
            , "    stderr:"
            , "      kubectl failed"
            ]
    , testCase "unrequested and unavailable product evidence render no product block" $
        withJournal $ \source -> do
          let blocks = ["product_rows:", "product_lane_fragment:"]
              blockHeaders rendered =
                [line | line <- rendered, any (`Text.isPrefixOf` line) blocks]
              withRows evidence =
                renderCard
                  Report.notRequestedMeasurements
                    { Report.measuredProductRowEvidence = evidence
                    }
              unavailable =
                withRows (Unavailable (UpstreamNotRun "live-e2e-test/jitml-integration"))
          -- The probe sees both committed blocks on a card that has evidence,
          -- so its silence below is a real absence.
          blockHeaders (withRows (Available (sourceReport source))) @?= blocks
          blockHeaders (withRows NotRequested) @?= []
          blockHeaders unavailable @?= []
          -- The unavailable card still says why, so nothing was merely dropped.
          assertBool
            "the unavailable card lost its reason"
            ( "  product_row_counts: unavailable (upstream not run: live-e2e-test/jitml-integration)"
                `elem` unavailable
            )
    ]

-- ---------------------------------------------------------------------------
-- Lines and counts are derived from journal rows
-- ---------------------------------------------------------------------------

trainingMeasurementTests :: TestTree
trainingMeasurementTests =
  testGroup
    "training measurements and counts"
    [ testCase "a completion's budget kind proves the registry family of every ProductRow" $
        case ProductMatrix.projectProductRows Substrate.LinuxCPU ProductMatrix.allProductRows of
          Failure errors -> assertFailure ("registry projection failed: " <> show errors)
          Success batch ->
            traverse_
              ( \(ProductMatrix.SomeProductProjection _witness projection) ->
                  ( ProductMatrix.productProjectionRowId projection
                  , Training.familyOfBudgetKind
                      ( Budget.trainingBudgetKind
                          (ProductMatrix.productProjectionTrainingBudget projection)
                      )
                  )
                    @?= ( ProductMatrix.productProjectionRowId projection
                        , ProductMatrix.productProjectionFamily projection
                        )
              )
              (ProductMatrix.productProjectionBatchProjections batch)
    , testCase "per-family and total counts are derived from journal rows and registry denominators" $ do
        views <- registryRowViews
        let counts = Training.deriveProductRowCounts views
        fmap
          (\count -> (Training.familyCountFamily count, Training.familyCountCompleted count))
          (Training.productRowCountsByFamily counts)
          @?= [(family, registryCount family) | family <- allFamilies]
        fmap Training.familyCountEligible (Training.productRowCountsByFamily counts)
          @?= fmap registryCount allFamilies
        Training.productRowCountsCompleted counts @?= ProductMatrix.productRowCount
        Training.productRowCountsEligible counts @?= ProductMatrix.productRowCount
        assertBool
          "a family of the registry has no completed row, so the counts prove nothing"
          (all ((> 0) . Training.familyCountCompleted) (Training.productRowCountsByFamily counts))
    , testCase "removing one journal row moves exactly its family's count and the completed total" $ do
        views <- registryRowViews
        let baseline = Training.deriveProductRowCounts views
            mutated =
              Training.deriveProductRowCounts (dropFirstRowOf ReinforcementLearning views)
        completedOf mutated ReinforcementLearning
          @?= fmap (subtract 1) (completedOf baseline ReinforcementLearning)
        traverse_
          (\family -> completedOf mutated family @?= completedOf baseline family)
          [Supervised, AlphaZero, Tuning]
        Training.productRowCountsCompleted mutated
          @?= Training.productRowCountsCompleted baseline
          - 1
        -- The eligible side is the registry's, so a missing journal row cannot
        -- shrink the denominator to hide itself.
        Training.productRowCountsEligible mutated
          @?= Training.productRowCountsEligible baseline
        assertBool
          "the rendered counts did not change when a journal row was removed"
          ( Training.renderProductRowCounts mutated
              /= Training.renderProductRowCounts baseline
          )
        assertBool
          "the missing row is not visible as completed over eligible"
          ( ( "completed="
                <> Text.pack (show (ProductMatrix.productRowCount - 1))
                <> "/"
                <> Text.pack (show ProductMatrix.productRowCount)
            )
              `Text.isPrefixOf` Training.renderProductRowCounts mutated
          )
    , testCase "a repeated journal row is one completed row" $ do
        views <- registryRowViews
        Training.deriveProductRowCounts (views <> views)
          @?= Training.deriveProductRowCounts views
    , testCase "counts render completed over eligible for the total and every family" $ do
        views <- registryRowViews
        let rendered = Training.renderProductRowCounts (Training.deriveProductRowCounts views)
            total = Text.pack (show ProductMatrix.productRowCount)
        assertBool
          "the completed total is not rendered over the registry denominator"
          (("completed=" <> total <> "/" <> total) `Text.isPrefixOf` rendered)
        traverse_
          ( \family ->
              assertBool
                ("family " <> show family <> " is missing from the rendered counts")
                ( ( ProductMatrix.renderRowFamily family
                      <> "="
                      <> Text.pack (show (registryCount family))
                      <> "/"
                      <> Text.pack (show (registryCount family))
                  )
                    `Text.isInfixOf` rendered
                )
          )
          allFamilies
    , testCase "each family line projects its rows' own metrics in journal order" $ do
        views <- registryRowViews
        let measurements = Training.trainingFamilyMeasurements (Available views)
        fmap fst measurements
          @?= [ "sl_final_loss"
              , "rl_final_reward"
              , "alphazero_arena_win_rate"
              , "tune_best_objective"
              ]
        traverse_
          ( \(family, (_label, measurement)) ->
              case measurement of
                Available metrics -> do
                  let familyViews = viewsOfFamily family views
                      rows = toList (Training.familyMetricsRows metrics)
                  Training.familyMetricsFamily metrics @?= family
                  fmap Training.familyRowMetricsRowId rows @?= fmap completedRowId familyViews
                  -- Values are the journal's own observations, never re-measured.
                  fmap
                    (fmap Training.metricReadingValue . Training.familyRowMetricsReadings)
                    rows
                    @?= [ fmap
                            Budget.coMetricValue
                            (Budget.completedTrainingMetrics (completedRowTraining view))
                        | view <- familyViews
                        ]
                  -- The rendered line is the fixture's own observations in
                  -- order, row by row, built without the projection under test.
                  Training.renderFamilyMetrics metrics @?= expectedFamilyLine family
                other -> assertFailure ("family line was not available: " <> show other)
          )
          (zip allFamilies measurements)
        -- Rows with more than one observation exist, so the equality above
        -- pins the rendering of every reading of a row and not just the first.
        assertBool
          "no fixture row has more than one observation, so multi-observation rendering is unpinned"
          (any hasSeveralObservations views)
    , testCase "a family with no journal row is unavailable while the others stay available" $ do
        views <- registryRowViews
        let withoutTuning = [view | view <- views, Training.completedRowFamily view /= Tuning]
        case Training.trainingFamilyMeasurements (Available withoutTuning) of
          [sl, rl, az, tune] -> do
            assertAvailable sl
            assertAvailable rl
            assertAvailable az
            snd tune
              @?= Unavailable
                (NotJournaled "no completed tuning row in the ProductScenario journal")
          other -> assertFailure ("unexpected family measurements: " <> show other)
    , testCase "the family lines follow the state of the one journal measurement" $ do
        let reason = UpstreamNotRun "live-e2e-test/jitml-integration"
        fmap snd (Training.trainingFamilyMeasurements NotRequested)
          @?= replicate 4 NotRequested
        fmap snd (Training.trainingFamilyMeasurements (Unavailable reason))
          @?= replicate 4 (Unavailable reason)
        Training.productRowCountsMeasurement (Unavailable reason) @?= Unavailable reason
        Training.productRowCountsMeasurement NotRequested @?= NotRequested
    , testCase "the retained CUDA lane journal projects to the registry's family counts and lines" $ do
        rows <- retainedCudaViews
        let counts = Training.deriveProductRowCounts rows
        fmap Training.familyCountCompleted (Training.productRowCountsByFamily counts)
          @?= fmap registryCount allFamilies
        Training.productRowCountsCompleted counts @?= ProductMatrix.productRowCount
        traverse_
          ( \(family, (_label, measurement)) ->
              case measurement of
                Available metrics -> do
                  -- Every real family line is the journal's own observations,
                  -- row by row, grouped by the registry's declaration.
                  Training.renderFamilyMetrics metrics
                    @?= independentFamilyLine (viewsOfFamily family rows)
                  -- ... and carries the metric its own bar declares.
                  let names =
                        List.nub
                          [ Training.metricReadingName reading
                          | row <- toList (Training.familyMetricsRows metrics)
                          , reading <- Training.familyRowMetricsReadings row
                          ]
                      barNames =
                        List.nub
                          [ convergenceMetricName (ProductMatrix.convergenceBar row)
                          | row <- ProductMatrix.allProductRows
                          , ProductMatrix.family row == family
                          ]
                  assertBool
                    ( "family "
                        <> show family
                        <> " does not carry its bar metrics "
                        <> show barNames
                        <> "; observed "
                        <> show names
                    )
                    (all (`elem` names) barNames)
                other -> assertFailure ("real family line was not available: " <> show other)
          )
          (zip allFamilies (Training.trainingFamilyMeasurements (Available rows)))
        -- Real journals carry rows with more than one observation (a
        -- goal-conditioned row reports its success rate and its distance), so
        -- the equality above pins the rendering of every reading of a row.
        assertBool
          "no retained row has more than one observation, so multi-observation rendering is unpinned"
          (any hasSeveralObservations rows)
    ]
 where
  assertAvailable (label, measurement) =
    case measurement of
      Available _ -> pure ()
      other -> assertFailure (Text.unpack label <> " was not available: " <> show other)
  completedOf counts family =
    [ Training.familyCountCompleted count
    | count <- Training.productRowCountsByFamily counts
    , Training.familyCountFamily count == family
    ]

allFamilies :: [RowFamily]
allFamilies = fmap fst Training.reportFamilies

-- | Registry rows of a family, counted independently of the projection under
-- test.
registryCount :: RowFamily -> Int
registryCount family =
  length [() | row <- ProductMatrix.allProductRows, ProductMatrix.family row == family]

-- | The family the registry declares for a journal row id, independent of the
-- projection's own grouping.
registryFamilyOf :: Text -> Maybe RowFamily
registryFamilyOf rowIdentity =
  ProductMatrix.family
    <$> List.find ((== rowIdentity) . ProductMatrix.rowId) ProductMatrix.allProductRows

-- | The journal rows of one family, grouped by the registry's declaration.
viewsOfFamily :: RowFamily -> [CompletedRowView] -> [CompletedRowView]
viewsOfFamily family views =
  [view | view <- views, registryFamilyOf (completedRowId view) == Just family]

hasSeveralObservations :: CompletedRowView -> Bool
hasSeveralObservations =
  (> 1) . length . Budget.completedTrainingMetrics . completedRowTraining

-- | A family's line, spelled @row:metric=value@ for every observation of every
-- row in order, from the completions' own observations alone.
independentFamilyLine :: [CompletedRowView] -> Text
independentFamilyLine familyViews =
  Text.intercalate
    ", "
    [ completedRowId view
        <> ":"
        <> Budget.coMetricName observation
        <> "="
        <> Text.pack (show (Budget.coMetricValue observation))
    | view <- familyViews
    , observation <- Budget.completedTrainingMetrics (completedRowTraining view)
    ]

-- | A family's line built from the fixture's own definition of what each row
-- measured, before any completion exists.
expectedFamilyLine :: RowFamily -> Text
expectedFamilyLine family =
  Text.intercalate
    ", "
    [ ProductMatrix.rowId row
        <> ":"
        <> fixtureMetric observation
        <> "="
        <> Text.pack (show (fixtureValue observation))
    | (ordinal, row) <- zip [1 :: Int ..] ProductMatrix.allProductRows
    , ProductMatrix.family row == family
    , observation <- fixtureObservations ordinal row
    ]

-- | One measured criterion of a fixture row.
data FixtureObservation = FixtureObservation
  { fixtureMetric :: !Text
  , fixtureGoal :: !Budget.MetricGoal
  , fixtureThreshold :: !Double
  , fixtureValue :: !Double
  }

-- | What a fixture row completes with.  Every row is measured by the metric its
-- own bar declares; a goal-conditioned (HER) row also reports the distance
-- metric its real journal rows report, so rows with more than one observation
-- are represented.
fixtureObservations
  :: Int
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> [FixtureObservation]
fixtureObservations ordinal row =
  FixtureObservation
    (convergenceMetricName (ProductMatrix.convergenceBar row))
    Budget.MetricMaximise
    0
    (fromIntegral ordinal / 100)
    : [ FixtureObservation
          "achieved_goal_distance"
          Budget.MetricMinimise
          1
          (fromIntegral ordinal / 1000)
      | "HER/" `Text.isPrefixOf` ProductMatrix.rowId row
      ]

dropFirstRowOf :: RowFamily -> [CompletedRowView] -> [CompletedRowView]
dropFirstRowOf family views =
  case break ((== family) . Training.completedRowFamily) views of
    (before, _dropped : after) -> before <> after
    (_, []) -> views

-- | One journal row for every registry ProductRow, each a real refined
-- 'Budget.CompletedTraining' of the budget kind that row's family requires,
-- measured by 'fixtureObservations'.
registryRowViews :: IO [CompletedRowView]
registryRowViews =
  traverse rowView (zip [1 :: Int ..] ProductMatrix.allProductRows)
 where
  rowView (ordinal, row) = do
    completion <- syntheticCompletion ordinal row
    pure
      CompletedRowView
        { completedRowId = ProductMatrix.rowId row
        , completedRowTraining = completion
        }

syntheticCompletion
  :: Int
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> IO Budget.CompletedTraining
syntheticCompletion ordinal row = do
  planId <- orFail (refinePlanIdText (Text.replicate 64 "e"))
  budget <- orFail (Budget.mkTrainingBudget kind 1 Nothing)
  evidence <-
    orFail
      ( ProductEvidence.mkTrainingEvidence
          ("initial-" <> Text.pack (show ordinal))
          ("final-" <> Text.pack (show ordinal))
          1
          "dataset-sha"
      )
  observations <-
    traverse
      ( \observation ->
          orFail
            ( Budget.measureCriterion
                (fixtureMetric observation)
                (fixtureGoal observation)
                (fixtureThreshold observation)
                (fixtureValue observation)
            )
      )
      measured
  orFail
    ( Budget.completedTraining
        planId
        budget
        1
        evidence
        observations
        Budget.TensorBoardRunMetadata
          { Budget.tbrRunId = "phase-289-unit"
          , Budget.tbrLogPrefix = "jitml-tensorboard/phase-289-unit"
          , Budget.tbrScalarTags = fmap fixtureMetric measured
          }
    )
 where
  measured = fixtureObservations ordinal row
  -- Independent of the implementation's own mapping: the family the registry
  -- declares chooses the budget kind the row's completion must carry.
  kind =
    case ProductMatrix.family row of
      Supervised -> Budget.SupervisedEpochBudget
      ReinforcementLearning -> Budget.RlEnvironmentStepBudget
      AlphaZero -> Budget.AlphaZeroSelfPlayBudget
      Tuning -> Budget.TuningTrialBudget
  orFail = either (assertFailure . Text.unpack) pure

-- | The retained CUDA lane journal, admitted against its pinned digest exactly
-- as the aggregation admits it.
retainedCudaViews :: IO [CompletedRowView]
retainedCudaViews = do
  input <-
    case [ candidate
         | candidate <- ProductAggregation.productLaneInputs
         , ProductAggregation.productLaneInputSubstrate candidate == Substrate.LinuxCUDA
         ] of
      [only] -> pure only
      other -> assertFailure ("expected one CUDA lane input, got " <> show (length other))
  batch <-
    case ProductMatrix.projectProductRows Substrate.LinuxCUDA ProductMatrix.allProductRows of
      Failure errors -> assertFailure ("CUDA registry projection failed: " <> show errors)
      Success value -> pure value
  bytes <- ByteString.readFile (ProductAggregation.productLaneInputPath input)
  admitted <-
    case ProductLaneJournal.admitProductLaneJournal
      (ProductAggregation.productLaneInputSha256 input)
      batch
      bytes of
      Left errors -> assertFailure ("retained CUDA journal was not admitted: " <> show errors)
      Right journal -> pure journal
  pure
    [ CompletedRowView
        { completedRowId = ProductLaneJournal.productLaneJournalRowRowId row
        , completedRowTraining = ProductLaneJournal.productLaneJournalRowCompletedTraining row
        }
    | row <- ProductLaneJournal.admittedProductLaneJournalRows admitted
    ]

-- ---------------------------------------------------------------------------
-- The browser row denominator derives from the registry and the journal
-- ---------------------------------------------------------------------------

browserDenominatorTests :: TestTree
browserDenominatorTests =
  testGroup
    "browser row denominator"
    [ testCase "the canonical row count is the registry's row count" $
        BrowserEvidenceJournal.browserEvidenceCanonicalRowCount @?= ProductMatrix.productRowCount
    , testCase "an expectation with a fabricated row total cannot be constructed" $ do
        assertBool
          "the registry-sized expectation was rejected"
          (either (const False) (const True) (construct browserExpectedRows))
        construct (withoutFirst browserExpectedRows)
          `expectRowCountMismatch` (ProductMatrix.productRowCount, ProductMatrix.productRowCount - 1)
        construct (browserExpectedRows <> take 1 browserExpectedRows)
          `expectRowCountMismatch` (ProductMatrix.productRowCount, ProductMatrix.productRowCount + 1)
    , testCase "the gate failure text counts the journal's own rows and statuses" $ do
        twoFailedOneNotRun <- browserReport (mixedObservations 2 1)
        LiveMeasurements.browserEvidenceGateFailure twoFailedOneNotRun
          @?= gateText 2 1
        -- Moving journal rows between statuses moves the counts the text reports.
        oneFailedThreeNotRun <- browserReport (mixedObservations 1 3)
        LiveMeasurements.browserEvidenceGateFailure oneFailedThreeNotRun
          @?= gateText 1 3
        assertBool
          "the gate text did not change when the journal did"
          ( LiveMeasurements.browserEvidenceGateFailure twoFailedOneNotRun
              /= LiveMeasurements.browserEvidenceGateFailure oneFailedThreeNotRun
          )
    , testCase "an all-Passed journal closes the gate and a NotRun seed does not" $ do
        passing <- browserReport (mixedObservations 0 0)
        assertBool
          "an all-Passed journal did not close the browser gate"
          (BrowserEvidenceJournal.browserEvidenceReportAllPassed passing)
        seed <- browserReport (mixedObservations 0 ProductMatrix.productRowCount)
        assertBool
          "an all-NotRun seed closed the browser gate"
          (not (BrowserEvidenceJournal.browserEvidenceReportAllPassed seed))
        LiveMeasurements.browserEvidenceGateFailure seed
          @?= ( "browser evidence gate requires exactly "
                  <> rowCountText
                  <> " Passed rows; observed Passed=0, Failed=0, NotRun="
                  <> rowCountText
              )
    ]
 where
  construct =
    BrowserEvidenceJournal.browserEvidenceExpectation
      "phase-289-run"
      Substrate.LinuxCPU
      (Text.replicate 64 "a")
      (Text.replicate 64 "b")
  withoutFirst rows =
    case rows of
      [] -> []
      _ : rest -> rest
  expectRowCountMismatch outcome (expected, observed) =
    case outcome of
      Left errors ->
        assertBool
          ("expected a row-count mismatch of " <> show (expected, observed) <> ", got " <> show errors)
          ( any
              ( \case
                  BrowserEvidenceJournal.BrowserEvidenceJournalRowCountMismatch e o ->
                    (e, o) == (expected, observed)
                  _ -> False
              )
              errors
          )
      Right _ -> assertFailure "a fabricated browser row total constructed an expectation"
  rowCountText = Text.pack (show ProductMatrix.productRowCount)
  gateText failed notRun =
    "browser evidence gate requires exactly "
      <> rowCountText
      <> " Passed rows; observed Passed="
      <> Text.pack (show (ProductMatrix.productRowCount - failed - notRun))
      <> ", Failed="
      <> Text.pack (show failed)
      <> ", NotRun="
      <> Text.pack (show notRun)

-- | The first @failed@ rows Failed, the next @notRun@ rows NotRun, the rest
-- Passed, one observation for every registry row.
mixedObservations :: Int -> Int -> [BrowserEvidenceJournal.BrowserEvidenceObservation]
mixedObservations failed notRun =
  replicate
    failed
    ( BrowserEvidenceJournal.BrowserEvidenceObservation
        BrowserEvidenceJournal.BrowserFailed
        "playwright failure"
    )
    <> replicate
      notRun
      ( BrowserEvidenceJournal.BrowserEvidenceObservation
          BrowserEvidenceJournal.BrowserNotRun
          "row not started"
      )
    <> replicate
      (ProductMatrix.productRowCount - failed - notRun)
      (BrowserEvidenceJournal.BrowserEvidenceObservation BrowserEvidenceJournal.BrowserPassed "")

browserExpectedRows :: [BrowserEvidenceJournal.BrowserEvidenceExpectedRow]
browserExpectedRows =
  [ BrowserEvidenceJournal.BrowserEvidenceExpectedRow
      { BrowserEvidenceJournal.expectedBrowserOrdinal = ordinal
      , BrowserEvidenceJournal.expectedBrowserRowId = "phase-289-row-" <> Text.pack (show ordinal)
      , BrowserEvidenceJournal.expectedBrowserPlanId = digest ordinal
      , BrowserEvidenceJournal.expectedBrowserExperimentHash =
          "phase-289-experiment-" <> Text.pack (show ordinal)
      , BrowserEvidenceJournal.expectedBrowserManifestSha256 = digest (ordinal + 1000)
      , BrowserEvidenceJournal.expectedBrowserE2ETest = "phase-289-e2e-" <> Text.pack (show ordinal)
      }
  | ordinal <- [0 .. fromIntegral ProductMatrix.productRowCount - 1 :: Word64]
  ]
 where
  digest :: Word64 -> Text
  digest value = Text.justifyRight 64 '0' (Text.pack (show value))

-- | Write and re-read an authenticated browser journal, so the report under
-- test is one only the journal refinement can produce.
browserReport
  :: [BrowserEvidenceJournal.BrowserEvidenceObservation]
  -> IO BrowserEvidenceJournal.BrowserEvidenceReport
browserReport observations =
  withSystemTempDirectory "jitml-phase-289-browser" $ \root -> do
    key <-
      BrowserEvidenceJournal.generateBrowserEvidenceJournalKey
        >>= either (assertFailure . show) pure
    expectation <-
      either
        (assertFailure . show)
        pure
        ( BrowserEvidenceJournal.browserEvidenceExpectation
            "phase-289-run"
            Substrate.LinuxCPU
            (Text.replicate 64 "a")
            (Text.replicate 64 "b")
            browserExpectedRows
        )
    let path = root </> "result.json"
    BrowserEvidenceJournal.writeBrowserEvidenceJournalAtomic key path expectation observations
      >>= either (assertFailure . show) pure
    BrowserEvidenceJournal.readBrowserEvidenceJournal key path expectation
      >>= either (assertFailure . show) pure

-- ---------------------------------------------------------------------------
-- No probe remains and no denominator is a literal (source guards)
-- ---------------------------------------------------------------------------

sourceGuardTests :: TestTree
sourceGuardTests =
  testGroup
    "no second measurement path"
    [ testCase "the test command and the App own none of the removed probes" $ do
        command <- Text.IO.readFile "src/JitML/Test/Command.hs"
        app <- Text.IO.readFile "src/JitML/App.hs"
        traverse_
          ( \needle ->
              assertBool
                ("a removed post-test probe reappeared: " <> Text.unpack needle)
                (not (needle `Text.isInfixOf` command || needle `Text.isInfixOf` app))
          )
          [ "collectLiveReportMeasurements"
          , "measureSlFinalLoss"
          , "measureRlFinalReward"
          , "measureAlphaZeroArenaWinRate"
          , "measureTuneBestObjective"
          , "measureJitCacheHitRate"
          , "measureDaemonHealthz"
          , "measureTestSlFinalLossText"
          , "measureTestRlFinalRewardText"
          , "testCommandMeasureSlFinalLossText"
          , "testCommandMeasureRlFinalRewardText"
          , "httpGetLocal"
          , "runOneGenerationOfSelfPlay"
          , "trialObjectiveResultsWithDeviceForAxes"
          ]
        assertBool
          "the test command opens a raw socket again"
          (not ("Network.Socket" `Text.isInfixOf` command))
    , testCase "the report layer states no literal row denominator" $ do
        sources <-
          traverse
            (\path -> (,) path <$> Text.IO.readFile path)
            [ "src/JitML/Test/BrowserEvidenceJournal.hs"
            , "src/JitML/Test/Command.hs"
            , "src/JitML/Test/LiveMeasurements.hs"
            , "src/JitML/Test/Measurement.hs"
            , "src/JitML/Test/TrainingMeasurement.hs"
            ]
        traverse_
          ( \(path, source) ->
              assertBool
                (path <> " states a literal 55-row denominator")
                (not (any (mentionsLiteral "55" . codeOf) (Text.lines source)))
          )
          sources
    , testCase "the test command decides no measurement, it only supplies the effects" $ do
        command <- Text.IO.readFile "src/JitML/Test/Command.hs"
        let code = Text.unlines (fmap codeOf (Text.lines command))
            -- Comments dropped and every whitespace run, and the space inside a
            -- bracket pair, collapsed, so a pin survives reformatting.
            normalized =
              Text.replace " )" ")"
                . Text.replace "( " "("
                . Text.unwords
                . Text.words
                $ code
            tokens =
              Text.split
                (\character -> not (isAlphaNum character || character `elem` ("_'" :: String)))
                code
        -- Every measurement decision is a "JitML.Test.LiveMeasurements"
        -- function the cases above run.  The command's wiring is exactly these
        -- calls: the selected targets and the scope result go in, and the
        -- journal reader is built from the private scope in one place, in the
        -- journal API's own argument order.
        traverse_
          ( \call ->
              assertBool
                ("the test command's measurement wiring changed: " <> Text.unpack call)
                (call `Text.isInfixOf` normalized)
          )
          [ "LiveMeasurements.liveScopeMeasurements selectedTargets scoped"
          , "LiveMeasurements.productRowsPostBody selectedTargets (productScenarioRead <$> scenarioScope)"
          , "LiveMeasurements.productRowsMeasurement targets (productScenarioRead <$> scenarioScope)"
          , Text.unwords
              [ "LiveMeasurements.browserRefinementOutcome"
              , "(ProductScenarioJournal.authenticatedProductScenarioReport authenticatedSource)"
              , "reread browserReport"
              ]
          , Text.unwords
              [ "LiveMeasurements.refinedProductScenarioRead"
              , "(ProductScenarioJournal.readProductScenarioJournal"
              , "(productScenarioJournalKey scope)"
              , "(productScenarioJournalPath scope)"
              , "(productScenarioCheckpointRoot scope)"
              , "(productScenarioRunId scope)"
              , "(productScenarioExecutablePath scope)"
              , "(productScenarioExecutableSha256 scope)"
              , "(productScenarioProjectionBatch scope))"
              ]
          ]
        -- ... and it names no measurement state or field itself, so it cannot
        -- decide one by another route.
        traverse_
          ( \needle ->
              assertBool
                ("the test command decides a measurement itself: " <> Text.unpack needle)
                (needle `notElem` tokens)
          )
          [ "Available"
          , "Unavailable"
          , "NotRequested"
          , "liveMeasurements"
          , "liveFailureMeasurements"
          , "measuredProductRowEvidence"
          , "measuredBrowserProductEvidence"
          , "measuredJitCacheHitRate"
          , "measuredDaemonHealthz"
          ]
    ]
 where
  codeOf = fst . Text.breakOn "--"
  -- A numeric token on its own, so a value such as @0.55@ is not a mention.
  mentionsLiteral literal line =
    literal
      `elem` Text.split (\character -> not (isDigit character || character `elem` ("._" :: String))) line

-- ---------------------------------------------------------------------------
-- Fixtures shared by the cases above
-- ---------------------------------------------------------------------------

renderCard :: Report.ReportMeasurements -> [Text]
renderCard measurements =
  Text.lines
    ( Report.renderReportCardWithKnobs
        Report.defaultReportCardKnobs
        Report.ReportCard
          { Report.reportInvocationJournal = Report.emptyInvocationJournal
          , Report.reportScenarioJournals = []
          , Report.reportMeasurements = measurements
          }
    )

-- | A plan with the given acquire steps and no body or release steps.
scopePlan :: [LivePlanStep] -> ScopedLivePlan
scopePlan acquire =
  ScopedLivePlan
    { scopedLivePlanOwnership = OwnedEphemeralCluster
    , scopedLivePlanAcquire = acquire
    , scopedLivePlanBody = []
    , scopedLivePlanRelease = []
    }

runScope
  :: LiveE2EScope.LiveE2EScopeBackend
  -> [LivePlanStep]
  -> [LiveE2EScope.PlannedTestInvocation]
  -> IO (Either Text Report.ReportMeasurements)
  -> IO (LiveE2EScope.LiveE2EScopeResult Report.ReportMeasurements)
runScope backend acquire =
  LiveE2EScope.runLiveE2EScope backend (scopePlan acquire)

-- | The browser lane's two-stage scope: producer, its refinement, consumer,
-- the final refinement, then the post-refinement invocations.
runStagedScope
  :: LiveE2EScope.LiveE2EScopeBackend
  -> [LiveE2EScope.PlannedTestInvocation]
  -> LiveE2EScope.LiveE2ERefinement ()
  -> [LiveE2EScope.PlannedTestInvocation]
  -> LiveE2EScope.LiveE2ERefinement Report.ReportMeasurements
  -> [LiveE2EScope.PlannedTestInvocation]
  -> IO (LiveE2EScope.LiveE2EScopeResult Report.ReportMeasurements)
runStagedScope backend =
  LiveE2EScope.runStagedLiveE2EScope backend (scopePlan [])

-- | A refinement that always returns the given outcome.
refinement
  :: Text
  -> Text
  -> LiveE2EScope.LiveE2ERefinementOutcome value
  -> LiveE2EScope.LiveE2ERefinement value
refinement source name outcome =
  LiveE2EScope.LiveE2ERefinement
    { LiveE2EScope.liveE2ERefinementSourceStanza = source
    , LiveE2EScope.liveE2ERefinementName = name
    , LiveE2EScope.liveE2ERefinementAction = pure outcome
    }

-- | A backend whose steps all pass except those the predicate selects, which
-- exit 3 with an explanatory stderr.
scopeBackend :: (LivePlanStep -> Bool) -> LiveE2EScope.LiveE2EScopeBackend
scopeBackend fails =
  LiveE2EScope.LiveE2EScopeBackend
    { LiveE2EScope.liveE2ERunStep = \_environment step -> pure (outcomeFor step)
    , LiveE2EScope.liveE2ELifecycleEnvironment = defaultSubprocessEnv
    , LiveE2EScope.liveE2EDiagnosticSteps = []
    , LiveE2EScope.liveE2EAcceptReleaseFailure = const False
    }
 where
  outcomeFor :: LivePlanStep -> ProcessOutcome
  outcomeFor step
    | fails step =
        processOutcome
          (ExitFailure 3)
          (transcript step) {processTranscriptStderr = livePlanStepName step <> " failed\n"}
    | otherwise = processOutcome ExitSuccess (transcript step)
  transcript step =
    ProcessTranscript
      { processTranscriptCommand = renderSubprocess (livePlanStepCommand step)
      , processTranscriptStdout = livePlanStepName step <> " stdout\n"
      , processTranscriptStderr = ""
      , processTranscriptWorkingDirectory = Just "/work/jitML"
      , processTranscriptDuration = ProcessDuration 10
      }

scopeStep :: Text -> LivePlanStep
scopeStep name =
  LivePlanStep
    { livePlanStepName = name
    , livePlanStepCommand = subprocess "scope-fixture" [name]
    }

plannedTest :: Text -> LiveE2EScope.PlannedTestInvocation
plannedTest stanza =
  LiveE2EScope.PlannedTestInvocation
    { LiveE2EScope.plannedTestStanza = stanza
    , LiveE2EScope.plannedTestCommand = subprocess "scope-fixture" [stanza]
    , LiveE2EScope.plannedTestEnvironment = defaultSubprocessEnv
    }

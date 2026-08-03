{-# LANGUAGE OverloadedStrings #-}

-- | Resource-scoped interpreter for the live browser and Cabal test lane.
--
-- Bootstrap, diagnostics, and teardown are lifecycle evidence.  Playwright and
-- Cabal are test invocations.  Keeping those projections distinct prevents
-- resource commands from inflating suite counts while retaining every process
-- transcript needed to explain a failed or interrupted live scenario.
module JitML.Test.LiveE2EScope
  ( LiveE2EScopeBackend (..)
  , LiveE2EFailure (..)
  , LiveE2ERefinement (..)
  , LiveE2ERefinementOutcome (..)
  , LiveE2EScopeFailure (..)
  , LiveE2EScopePhase (..)
  , LiveE2EScopeResult
  , PlannedTestInvocation (..)
  , liveE2EInvocationJournal
  , liveE2EPostBodyResult
  , liveE2EPostBodyFailure
  , liveE2EPrimaryFailure
  , liveE2EScenarioJournal
  , liveE2EScopeFailure
  , liveE2ESecondaryFailures
  , liveE2EDiagnosticsRequired
  , runLiveE2EScope
  , runStagedLiveE2EScope
  )
where

import Control.Exception.Safe (displayException, generalBracket, tryAny)
import Control.Monad.Catch (ExitCase (..))
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessFailure
  , ProcessOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream
  ( SubprocessEnv
  , observeProcessAction
  )
import JitML.Sub.Subprocess (Subprocess)
import JitML.Test.LivePlan
  ( LivePlanStep (..)
  , ScopedLivePlan (..)
  )
import JitML.Test.Report
  ( InvocationJournal
  , appendInvocation
  , emptyInvocationJournal
  , failedObservedInvocation
  , notRunAfterRefinement
  , notRunObservedInvocation
  , passedInvocation
  )
import JitML.Test.ScenarioJournal
  ( ScenarioDisposition (..)
  , ScenarioJournal
  , ScenarioPhase (..)
  , appendScenarioIssue
  , appendScenarioJournal
  , appendScenarioRecord
  , emptyScenarioJournal
  )

data PlannedTestInvocation = PlannedTestInvocation
  { plannedTestStanza :: !Text
  , plannedTestCommand :: !Subprocess
  , plannedTestEnvironment :: !SubprocessEnv
  }
  deriving stock (Eq)

-- | One parent-owned refinement boundary between subprocess stages.  The
-- source stanza identifies the successful process whose output is being
-- refined; the name identifies the proof operation itself.  A refinement is
-- not a subprocess and therefore can never fabricate a process result.
data LiveE2ERefinement value = LiveE2ERefinement
  { liveE2ERefinementSourceStanza :: !Text
  , liveE2ERefinementName :: !Text
  , liveE2ERefinementAction :: IO (LiveE2ERefinementOutcome value)
  }

-- | A refinement can succeed, reject its input entirely, or retain an exact
-- refined value while also raising a gate issue.  The last case is required by
-- the browser report: 55 explicit row statuses remain renderable even when one
-- or more cells are Failed/NotRun and therefore fail the command.
data LiveE2ERefinementOutcome value
  = LiveE2ERefined !value
  | LiveE2ERefinedWithIssue !value !Text
  | LiveE2ERefinementRejected !Text
  deriving stock (Eq, Show)

data LiveE2EScopePhase
  = LiveE2EAcquire
  | LiveE2ETest
  | LiveE2EDiagnostics
  | LiveE2ERelease
  deriving stock (Eq, Show)

data LiveE2EScopeFailure = LiveE2EScopeFailure
  { liveE2EFailurePhase :: !LiveE2EScopePhase
  , liveE2EFailureStep :: !Text
  , liveE2EFailureProcess :: !ObservedProcessFailure
  }
  deriving stock (Eq, Show)

data LiveE2EScopeBackend = LiveE2EScopeBackend
  { liveE2ERunStep :: SubprocessEnv -> LivePlanStep -> IO ProcessOutcome
  , liveE2ELifecycleEnvironment :: !SubprocessEnv
  , liveE2EDiagnosticSteps :: ![LivePlanStep]
  , liveE2EAcceptReleaseFailure :: ProcessFailure -> Bool
  }

data LiveE2EScopeResult body = LiveE2EScopeResult
  { liveE2EInvocationJournal :: !InvocationJournal
  , liveE2EScenarioJournal :: !ScenarioJournal
  , liveE2EPrimaryFailure :: !(Maybe LiveE2EScopeFailure)
  , liveE2ESecondaryFailures :: ![LiveE2EScopeFailure]
  , liveE2EPostBodyFailure :: !(Maybe Text)
  , liveE2EPostBodyResult :: !(Maybe body)
  }

data LiveE2EFailure
  = LiveE2EProcessFailure !LiveE2EScopeFailure
  | LiveE2EPostBodyIssue !Text
  deriving stock (Eq, Show)

-- | Prefer the original acquire/test failure, then a typed post-body issue,
-- then diagnostics/release.  This single projection prevents cleanup evidence
-- from replacing the failure that caused cleanup to run.
liveE2EScopeFailure :: LiveE2EScopeResult body -> Maybe LiveE2EFailure
liveE2EScopeFailure result =
  case liveE2EPrimaryFailure result of
    Just primary -> Just (LiveE2EProcessFailure primary)
    Nothing ->
      case liveE2EPostBodyFailure result of
        Just failure -> Just (LiveE2EPostBodyIssue failure)
        Nothing -> LiveE2EProcessFailure <$> firstMaybe (liveE2ESecondaryFailures result)

-- | Interpret the complete owned-or-borrowed live scope.  The post-body action
-- runs only after every planned test invocation passes, and still runs before
-- diagnostics/release; this keeps live report measurements inside the owned
-- cluster lifetime.  Its typed 'Left' is retained as a scenario issue and
-- triggers diagnostics.  'generalBracket' guarantees diagnostics and release
-- when a synchronous or asynchronous exception escapes the body.  The
-- diagnostics decision is derived directly from the body's 'ExitCase': a clean
-- normal return may skip diagnostics, while an exception or abort always gathers
-- them before release.  There is therefore no mutable success flag that an
-- asynchronous exception can arrive after but before the body returns.
runLiveE2EScope
  :: LiveE2EScopeBackend
  -> ScopedLivePlan
  -> [PlannedTestInvocation]
  -> IO (Either Text body)
  -> IO (LiveE2EScopeResult body)
runLiveE2EScope backend plan invocations postBody = do
  (bodyResult, releaseResult) <-
    generalBracket
      (pure ())
      ( \() exitCase ->
          runDiagnosticsAndRelease
            backend
            plan
            (liveE2EDiagnosticsRequired hasPrimaryFailure exitCase)
      )
      (\() -> runAcquireAndBody backend plan invocations postBody)
  pure
    LiveE2EScopeResult
      { liveE2EInvocationJournal = bodyInvocationJournal bodyResult
      , liveE2EScenarioJournal =
          appendScenarioJournal
            (bodyScenarioJournal bodyResult)
            (releaseScenarioJournal releaseResult)
      , liveE2EPrimaryFailure = bodyPrimaryFailure bodyResult
      , liveE2ESecondaryFailures = releaseFailures releaseResult
      , liveE2EPostBodyFailure = bodyPostFailure bodyResult
      , liveE2EPostBodyResult = bodyPostResult bodyResult
      }

-- | Run the browser lane as two causally separated process stages.  The
-- producer must first exit successfully and refine into the exact proof needed
-- by the consumer stage.  A failed refinement records consumers as honest
-- 'NotRunAfterRefinement' rows; it is never rewritten into a failed process.
--
-- The final refinement always runs after an attempted consumer stage, even
-- when Playwright failed.  This admits the
-- authenticated all-'NotRun' seed (or the partial/final browser journal) before
-- the original process failure is propagated.  Post-refinement invocations
-- (the Haskell E2E stanza and, for @test all@, the remaining stanzas) run only
-- after that trust boundary.  The refinement and all post-refinement work stay
-- inside the live cluster bracket, before diagnostics and release.
runStagedLiveE2EScope
  :: LiveE2EScopeBackend
  -> ScopedLivePlan
  -> [PlannedTestInvocation]
  -> LiveE2ERefinement ()
  -> [PlannedTestInvocation]
  -> LiveE2ERefinement body
  -> [PlannedTestInvocation]
  -> IO (LiveE2EScopeResult body)
runStagedLiveE2EScope
  backend
  plan
  producerInvocations
  producerRefinement
  consumerInvocations
  finalRefinement
  postRefinementInvocations = do
    (bodyResult, releaseResult) <-
      generalBracket
        (pure ())
        ( \() exitCase ->
            runDiagnosticsAndRelease
              backend
              plan
              (liveE2EDiagnosticsRequired hasPrimaryFailure exitCase)
        )
        ( \() ->
            runAcquireAndStagedBody
              backend
              plan
              producerInvocations
              producerRefinement
              consumerInvocations
              finalRefinement
              postRefinementInvocations
        )
    pure
      LiveE2EScopeResult
        { liveE2EInvocationJournal = bodyInvocationJournal bodyResult
        , liveE2EScenarioJournal =
            appendScenarioJournal
              (bodyScenarioJournal bodyResult)
              (releaseScenarioJournal releaseResult)
        , liveE2EPrimaryFailure = bodyPrimaryFailure bodyResult
        , liveE2ESecondaryFailures = releaseFailures releaseResult
        , liveE2EPostBodyFailure = bodyPostFailure bodyResult
        , liveE2EPostBodyResult = bodyPostResult bodyResult
        }

hasPrimaryFailure :: BodyResult body -> Bool
hasPrimaryFailure result =
  case (bodyPrimaryFailure result, bodyPostFailure result) of
    (Nothing, Nothing) -> False
    _ -> True

-- | Decide whether diagnostics are required from the bracket's authoritative
-- exit evidence.  Only a normal return delegates to the body's failure
-- projection.  An exception (including asynchronous cancellation) or an aborted
-- transformer branch always requires diagnostics.
liveE2EDiagnosticsRequired :: (body -> Bool) -> ExitCase body -> Bool
liveE2EDiagnosticsRequired bodyRequiresDiagnostics exitCase =
  case exitCase of
    ExitCaseSuccess body -> bodyRequiresDiagnostics body
    ExitCaseException _exception -> True
    ExitCaseAbort -> True

data BodyResult body = BodyResult
  { bodyInvocationJournal :: !InvocationJournal
  , bodyScenarioJournal :: !ScenarioJournal
  , bodyPrimaryFailure :: !(Maybe LiveE2EScopeFailure)
  , bodyPostFailure :: !(Maybe Text)
  , bodyPostResult :: !(Maybe body)
  }

runAcquireAndBody
  :: LiveE2EScopeBackend
  -> ScopedLivePlan
  -> [PlannedTestInvocation]
  -> IO (Either Text body)
  -> IO (BodyResult body)
runAcquireAndBody backend plan invocations postBody = do
  acquisition <-
    runAcquireSteps
      backend
      (emptyScenarioJournal "live-e2e")
      (scopedLivePlanAcquire plan)
  case acquireFailure acquisition of
    Just failure ->
      pure
        BodyResult
          { bodyInvocationJournal =
              blockedInvocationJournal invocations failure
          , bodyScenarioJournal = acquireJournal acquisition
          , bodyPrimaryFailure = Just failure
          , bodyPostFailure = Nothing
          , bodyPostResult = Nothing
          }
    Nothing -> do
      body <-
        runTestInvocations
          backend
          (acquireJournal acquisition)
          emptyInvocationJournal
          invocations
      case testFailure body of
        Just failure ->
          pure
            BodyResult
              { bodyInvocationJournal = testInvocationJournal body
              , bodyScenarioJournal = testScenarioJournal body
              , bodyPrimaryFailure = Just failure
              , bodyPostFailure = Nothing
              , bodyPostResult = Nothing
              }
        Nothing -> do
          outcome <- postBody
          case outcome of
            Left failure ->
              pure
                BodyResult
                  { bodyInvocationJournal = testInvocationJournal body
                  , bodyScenarioJournal =
                      appendScenarioIssue
                        (testScenarioJournal body)
                        ScenarioBody
                        "live-report-measurements"
                        failure
                  , bodyPrimaryFailure = Nothing
                  , bodyPostFailure = Just failure
                  , bodyPostResult = Nothing
                  }
            Right value ->
              pure
                BodyResult
                  { bodyInvocationJournal = testInvocationJournal body
                  , bodyScenarioJournal = testScenarioJournal body
                  , bodyPrimaryFailure = Nothing
                  , bodyPostFailure = Nothing
                  , bodyPostResult = Just value
                  }

runAcquireAndStagedBody
  :: LiveE2EScopeBackend
  -> ScopedLivePlan
  -> [PlannedTestInvocation]
  -> LiveE2ERefinement ()
  -> [PlannedTestInvocation]
  -> LiveE2ERefinement body
  -> [PlannedTestInvocation]
  -> IO (BodyResult body)
runAcquireAndStagedBody
  backend
  plan
  producerInvocations
  producerRefinement
  consumerInvocations
  finalRefinement
  postRefinementInvocations = do
    acquisition <-
      runAcquireSteps
        backend
        (emptyScenarioJournal "live-e2e")
        (scopedLivePlanAcquire plan)
    case acquireFailure acquisition of
      Just failure ->
        pure
          BodyResult
            { bodyInvocationJournal =
                blockedInvocationJournal
                  ( producerInvocations
                      <> consumerInvocations
                      <> postRefinementInvocations
                  )
                  failure
            , bodyScenarioJournal = acquireJournal acquisition
            , bodyPrimaryFailure = Just failure
            , bodyPostFailure = Nothing
            , bodyPostResult = Nothing
            }
      Nothing -> do
        producer <-
          runTestInvocations
            backend
            (acquireJournal acquisition)
            emptyInvocationJournal
            producerInvocations
        case testFailure producer of
          Just failure ->
            pure
              BodyResult
                { bodyInvocationJournal =
                    appendBlockedInvocations
                      (testInvocationJournal producer)
                      (consumerInvocations <> postRefinementInvocations)
                      failure
                , bodyScenarioJournal = testScenarioJournal producer
                , bodyPrimaryFailure = Just failure
                , bodyPostFailure = Nothing
                , bodyPostResult = Nothing
                }
          Nothing -> do
            refinedProducer <- runRefinement producerRefinement
            case refinedProducer of
              LiveE2ERefinementRejected failure ->
                pure
                  BodyResult
                    { bodyInvocationJournal =
                        appendRefinementBlockedInvocations
                          (testInvocationJournal producer)
                          (consumerInvocations <> postRefinementInvocations)
                          producerRefinement
                          failure
                    , bodyScenarioJournal =
                        appendRefinementIssue
                          (testScenarioJournal producer)
                          producerRefinement
                          failure
                    , bodyPrimaryFailure = Nothing
                    , bodyPostFailure = Just failure
                    , bodyPostResult = Nothing
                    }
              LiveE2ERefinedWithIssue () failure ->
                pure
                  BodyResult
                    { bodyInvocationJournal =
                        appendRefinementBlockedInvocations
                          (testInvocationJournal producer)
                          (consumerInvocations <> postRefinementInvocations)
                          producerRefinement
                          failure
                    , bodyScenarioJournal =
                        appendRefinementIssue
                          (testScenarioJournal producer)
                          producerRefinement
                          failure
                    , bodyPrimaryFailure = Nothing
                    , bodyPostFailure = Just failure
                    , bodyPostResult = Nothing
                    }
              LiveE2ERefined () -> do
                consumers <-
                  runTestInvocations
                    backend
                    (testScenarioJournal producer)
                    (testInvocationJournal producer)
                    consumerInvocations
                refinedFinal <- runRefinement finalRefinement
                finishStagedBody
                  backend
                  consumers
                  finalRefinement
                  refinedFinal
                  postRefinementInvocations

finishStagedBody
  :: LiveE2EScopeBackend
  -> TestResult
  -> LiveE2ERefinement body
  -> LiveE2ERefinementOutcome body
  -> [PlannedTestInvocation]
  -> IO (BodyResult body)
finishStagedBody backend consumers finalRefinement refinedFinal postInvocations =
  case refinedFinal of
    LiveE2ERefinementRejected failure ->
      pure
        BodyResult
          { bodyInvocationJournal =
              appendRefinementBlockedInvocations
                (testInvocationJournal consumers)
                postInvocations
                finalRefinement
                failure
          , bodyScenarioJournal =
              appendRefinementIssue
                (testScenarioJournal consumers)
                finalRefinement
                failure
          , bodyPrimaryFailure = testFailure consumers
          , bodyPostFailure = Just failure
          , bodyPostResult = Nothing
          }
    LiveE2ERefinedWithIssue value failure ->
      pure
        BodyResult
          { bodyInvocationJournal =
              blockedPostRefinementInvocations
                consumers
                finalRefinement
                failure
                postInvocations
          , bodyScenarioJournal =
              appendRefinementIssue
                (testScenarioJournal consumers)
                finalRefinement
                failure
          , bodyPrimaryFailure = testFailure consumers
          , bodyPostFailure = Just failure
          , bodyPostResult = Just value
          }
    LiveE2ERefined value ->
      case testFailure consumers of
        Just processFailure ->
          pure
            BodyResult
              { bodyInvocationJournal =
                  appendBlockedInvocations
                    (testInvocationJournal consumers)
                    postInvocations
                    processFailure
              , bodyScenarioJournal = testScenarioJournal consumers
              , bodyPrimaryFailure = Just processFailure
              , bodyPostFailure = Nothing
              , bodyPostResult = Just value
              }
        Nothing -> do
          post <-
            runTestInvocations
              backend
              (testScenarioJournal consumers)
              (testInvocationJournal consumers)
              postInvocations
          pure
            BodyResult
              { bodyInvocationJournal = testInvocationJournal post
              , bodyScenarioJournal = testScenarioJournal post
              , bodyPrimaryFailure = testFailure post
              , bodyPostFailure = Nothing
              , bodyPostResult = Just value
              }

blockedPostRefinementInvocations
  :: TestResult
  -> LiveE2ERefinement body
  -> Text
  -> [PlannedTestInvocation]
  -> InvocationJournal
blockedPostRefinementInvocations consumers finalRefinement failure postInvocations =
  case testFailure consumers of
    Just processFailure ->
      appendBlockedInvocations
        (testInvocationJournal consumers)
        postInvocations
        processFailure
    Nothing ->
      appendRefinementBlockedInvocations
        (testInvocationJournal consumers)
        postInvocations
        finalRefinement
        failure

runRefinement
  :: LiveE2ERefinement value
  -> IO (LiveE2ERefinementOutcome value)
runRefinement refinement = do
  attempted <- tryAny (liveE2ERefinementAction refinement)
  pure $
    case attempted of
      Left exception ->
        LiveE2ERefinementRejected
          ( liveE2ERefinementName refinement
              <> " raised an exception: "
              <> Text.pack (displayException exception)
          )
      Right outcome -> outcome

appendRefinementBlockedInvocations
  :: InvocationJournal
  -> [PlannedTestInvocation]
  -> LiveE2ERefinement value
  -> Text
  -> InvocationJournal
appendRefinementBlockedInvocations journal invocations refinement failure =
  foldl appendBlocked journal invocations
 where
  appendBlocked observed planned =
    appendInvocation
      observed
      ( notRunAfterRefinement
          (plannedTestStanza planned)
          (renderSubprocess (plannedTestCommand planned))
          (liveE2ERefinementSourceStanza refinement)
          (liveE2ERefinementName refinement)
          failure
      )

appendRefinementIssue
  :: ScenarioJournal
  -> LiveE2ERefinement value
  -> Text
  -> ScenarioJournal
appendRefinementIssue journal refinement =
  appendScenarioIssue
    journal
    ScenarioBody
    (liveE2ERefinementName refinement)

data AcquireResult = AcquireResult
  { acquireJournal :: !ScenarioJournal
  , acquireFailure :: !(Maybe LiveE2EScopeFailure)
  }

runAcquireSteps
  :: LiveE2EScopeBackend
  -> ScenarioJournal
  -> [LivePlanStep]
  -> IO AcquireResult
runAcquireSteps _backend journal [] =
  pure (AcquireResult journal Nothing)
runAcquireSteps backend journal (step : remaining) = do
  outcome <-
    runObservedStep
      backend
      (liveE2ELifecycleEnvironment backend)
      step
  let observed =
        appendScenarioRecord
          journal
          ScenarioAcquire
          (livePlanStepName step)
          (outcomeDisposition outcome)
          outcome
  case outcome of
    ObservedProcessSucceeded _ -> runAcquireSteps backend observed remaining
    ObservedProcessFailed failure ->
      pure
        AcquireResult
          { acquireJournal = observed
          , acquireFailure =
              Just
                LiveE2EScopeFailure
                  { liveE2EFailurePhase = LiveE2EAcquire
                  , liveE2EFailureStep = livePlanStepName step
                  , liveE2EFailureProcess = failure
                  }
          }

data TestResult = TestResult
  { testInvocationJournal :: !InvocationJournal
  , testScenarioJournal :: !ScenarioJournal
  , testFailure :: !(Maybe LiveE2EScopeFailure)
  }

runTestInvocations
  :: LiveE2EScopeBackend
  -> ScenarioJournal
  -> InvocationJournal
  -> [PlannedTestInvocation]
  -> IO TestResult
runTestInvocations _backend scenarioJournal invocationJournal [] =
  pure
    TestResult
      { testInvocationJournal = invocationJournal
      , testScenarioJournal = scenarioJournal
      , testFailure = Nothing
      }
runTestInvocations backend scenarioJournal invocationJournal (planned : remaining) = do
  let step =
        LivePlanStep
          { livePlanStepName = plannedTestStanza planned
          , livePlanStepCommand = plannedTestCommand planned
          }
  outcome <-
    runObservedStep
      backend
      (plannedTestEnvironment planned)
      step
  let observedScenario =
        appendScenarioRecord
          scenarioJournal
          ScenarioBody
          (plannedTestStanza planned)
          (outcomeDisposition outcome)
          outcome
  case outcome of
    ObservedProcessSucceeded transcript ->
      runTestInvocations
        backend
        observedScenario
        (appendInvocation invocationJournal (passedInvocation (plannedTestStanza planned) transcript))
        remaining
    ObservedProcessFailed failure ->
      let scopeFailure =
            LiveE2EScopeFailure
              { liveE2EFailurePhase = LiveE2ETest
              , liveE2EFailureStep = plannedTestStanza planned
              , liveE2EFailureProcess = failure
              }
          failedJournal =
            appendInvocation
              invocationJournal
              (failedObservedInvocation (plannedTestStanza planned) failure)
       in pure
            TestResult
              { testInvocationJournal =
                  appendBlockedInvocations failedJournal remaining scopeFailure
              , testScenarioJournal = observedScenario
              , testFailure = Just scopeFailure
              }

blockedInvocationJournal
  :: [PlannedTestInvocation]
  -> LiveE2EScopeFailure
  -> InvocationJournal
blockedInvocationJournal =
  appendBlockedInvocations emptyInvocationJournal

appendBlockedInvocations
  :: InvocationJournal
  -> [PlannedTestInvocation]
  -> LiveE2EScopeFailure
  -> InvocationJournal
appendBlockedInvocations journal invocations failure =
  foldl appendBlocked journal invocations
 where
  appendBlocked observed planned =
    appendInvocation
      observed
      ( notRunObservedInvocation
          (plannedTestStanza planned)
          (renderSubprocess (plannedTestCommand planned))
          (failureBlockerName failure)
          (liveE2EFailureProcess failure)
      )

failureBlockerName :: LiveE2EScopeFailure -> Text
failureBlockerName failure =
  renderFailurePhase (liveE2EFailurePhase failure)
    <> "/"
    <> liveE2EFailureStep failure

renderFailurePhase :: LiveE2EScopePhase -> Text
renderFailurePhase LiveE2EAcquire = "live-e2e-acquire"
renderFailurePhase LiveE2ETest = "live-e2e-test"
renderFailurePhase LiveE2EDiagnostics = "live-e2e-diagnostics"
renderFailurePhase LiveE2ERelease = "live-e2e-release"

data ReleaseResult = ReleaseResult
  { releaseScenarioJournal :: !ScenarioJournal
  , releaseFailures :: ![LiveE2EScopeFailure]
  }

runDiagnosticsAndRelease
  :: LiveE2EScopeBackend
  -> ScopedLivePlan
  -> Bool
  -> IO ReleaseResult
runDiagnosticsAndRelease backend plan shouldGatherDiagnostics = do
  -- Diagnostics have their own bracket around the authoritative release.
  -- Synchronous runner exceptions are normally data via 'runObservedStep'; if
  -- any other exception escapes diagnostics, including asynchronous
  -- cancellation, release still runs before that same exception propagates.
  (diagnostics, release) <-
    generalBracket
      (pure ())
      ( \() _exitCase ->
          runLifecycleSteps
            backend
            ScenarioRelease
            LiveE2ERelease
            (liveE2EAcceptReleaseFailure backend)
            (emptyScenarioJournal "live-e2e")
            (scopedLivePlanRelease plan)
      )
      ( \() ->
          runLifecycleSteps
            backend
            ScenarioDiagnostics
            LiveE2EDiagnostics
            (const False)
            (emptyScenarioJournal "live-e2e")
            (if shouldGatherDiagnostics then liveE2EDiagnosticSteps backend else [])
      )
  pure
    ReleaseResult
      { releaseScenarioJournal =
          appendScenarioJournal
            (lifecycleJournal diagnostics)
            (lifecycleJournal release)
      , releaseFailures = lifecycleFailures diagnostics <> lifecycleFailures release
      }

data LifecycleResult = LifecycleResult
  { lifecycleJournal :: !ScenarioJournal
  , lifecycleFailures :: ![LiveE2EScopeFailure]
  }

runLifecycleSteps
  :: LiveE2EScopeBackend
  -> ScenarioPhase
  -> LiveE2EScopePhase
  -> (ProcessFailure -> Bool)
  -> ScenarioJournal
  -> [LivePlanStep]
  -> IO LifecycleResult
runLifecycleSteps backend journalPhase failurePhase acceptFailure = go []
 where
  go failures journal [] =
    pure
      LifecycleResult
        { lifecycleJournal = journal
        , lifecycleFailures = reverse failures
        }
  go failures journal (step : remaining) = do
    outcome <-
      runObservedStep
        backend
        (liveE2ELifecycleEnvironment backend)
        step
    let (disposition, nextFailures) =
          case outcome of
            ObservedProcessSucceeded _ -> (ScenarioStepSucceeded, failures)
            ObservedProcessFailed failure@(ObservedProcessExitFailure processFailure)
              | acceptFailure processFailure -> (ScenarioStepAcceptedNoop, failures)
              | otherwise ->
                  ( ScenarioStepFailed
                  , LiveE2EScopeFailure
                      { liveE2EFailurePhase = failurePhase
                      , liveE2EFailureStep = livePlanStepName step
                      , liveE2EFailureProcess = failure
                      }
                      : failures
                  )
            ObservedProcessFailed failure ->
              ( ScenarioStepFailed
              , LiveE2EScopeFailure
                  { liveE2EFailurePhase = failurePhase
                  , liveE2EFailureStep = livePlanStepName step
                  , liveE2EFailureProcess = failure
                  }
                  : failures
              )
        observed =
          appendScenarioRecord
            journal
            journalPhase
            (livePlanStepName step)
            disposition
            outcome
    go nextFailures observed remaining

runObservedStep
  :: LiveE2EScopeBackend
  -> SubprocessEnv
  -> LivePlanStep
  -> IO ObservedProcessOutcome
runObservedStep backend environment step =
  observeProcessAction
    (livePlanStepCommand step)
    (liveE2ERunStep backend environment step)

outcomeDisposition :: ObservedProcessOutcome -> ScenarioDisposition
outcomeDisposition (ObservedProcessSucceeded _) = ScenarioStepSucceeded
outcomeDisposition (ObservedProcessFailed _) = ScenarioStepFailed

firstMaybe :: [value] -> Maybe value
firstMaybe [] = Nothing
firstMaybe (value : _) = Just value

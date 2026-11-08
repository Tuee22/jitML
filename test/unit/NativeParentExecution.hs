{-# LANGUAGE OverloadedStrings #-}

-- Actual owned entry preflight only. No Policy/Store/launch/certificate or
-- successful parent result is constructed, parsed or supplied by these tests.
-- Diagnostic-rendering fixtures below are ordinary report DATA only.
module NativeParentExecution (nativeParentExecutionTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad (forM_)
import Control.Monad.Reader (runReaderT)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Env.Env (Env)
import JitML.Product.NativeParentEvaluationReplay qualified as Evaluation
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Test.ProductScenarioRunner qualified as Scenario

data InputFault = UnicodeFault | EndlessFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException UnicodeFault = "actual owned native parent input λ🙂"
  displayException EndlessFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeParentExecutionTests :: TestTree
nativeParentExecutionTests =
  testGroup
    "native parent owned execution preflight"
    [ testCase "poisoned request refuses before batch Env source FILE or owned launch" $ do
        report <- invoke (error "actual owned native parent request fault") >>= failureReport
        assertEqual "first stage" Parent.ParentExecutionInput (Parent.parentExecutionStage report)
        assertEqual "no partial request invented" Nothing (Parent.parentExecutionRequest report)
        assertEqual "no original allocation invented" Nothing (Parent.parentExecutionAllocationKey report)
        assertEqual "no source before invented" Nothing (Parent.parentExecutionSourceBefore report)
        assertEqual "no source after child invented" Nothing (Parent.parentExecutionSourceAfterChild report)
        assertEqual
          "no source after parent invented"
          Nothing
          (Parent.parentExecutionSourceAfterParent report)
        assertEqual
          "no executable FILE before invented"
          Nothing
          (Parent.parentExecutionExecutableBefore report)
        assertEqual "no parent process invented" Nothing (Parent.parentExecutionProcessBefore report)
        assertEqual "no actual owned spawn invented" Nothing (Parent.parentExecutionActualSpawn report)
        assertEqual "no launch fault invented" Nothing (Parent.parentExecutionLaunchDiagnostic report)
        assertEqual "no receipt reference invented" Nothing (Parent.parentExecutionReference report)
        assertEqual "no physical acquisition invented" Nothing (Parent.parentExecutionPhysical report)
        assertEqual "no policy verification invented" Nothing (Parent.parentExecutionPolicyFailure report)
        assertEqual
          "no selected device evaluation invented"
          Nothing
          (Parent.parentExecutionEvaluation report)
    , testCase "complete Unicode request diagnostic survives without a parent certificate" $ do
        report <- invoke (throw UnicodeFault) >>= failureReport
        assertEqual
          "exact Unicode diagnostic"
          (Just (Failure.CompleteNativeDiagnostic "actual owned native parent input λ🙂"))
          (Parent.parentExecutionDiagnostic report)
    , testCase "endless request renderer is bounded without a complete diagnostic prefix" $ do
        result <- timeout 10000000 (invoke (throw EndlessFault))
        case result of
          Just (Left failure) -> case Parent.parentExecutionDiagnostic (Parent.nativeParentExecutionFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
              assertEqual "cap plus one" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger count)
            _ -> assertFailure "endless renderer became complete or lost its bounded refusal"
          _ -> assertFailure "request renderer exceeded its bound or fabricated an executed parent"
    , testCase "request asynchronous cancellation propagates without an executed result" $ do
        result <-
          try (invoke (throw ThreadKilled))
            :: IO
                 (Either AsyncException (Either Parent.NativeParentExecutionFailure Parent.NativeParentExecutedCohort))
        assertAsync result
    , testCase "diagnostic renderer asynchronous cancellation propagates without refusal substitution" $ do
        result <-
          try (invoke (throw AsyncRendererFault))
            :: IO
                 (Either AsyncException (Either Parent.NativeParentExecutionFailure Parent.NativeParentExecutedCohort))
        assertAsync result
    , testCase
        "public parent refusal preserves nested evaluation stage and diagnostic before outer fallback without dumping payloads"
        $ do
          report <- diagnosticFixture
          detail <-
            Scenario.renderNativeParentExecutionRefusal
              report
                { Parent.parentExecutionEvaluation =
                    Just
                      evaluationFixture
                        { Evaluation.parentEvaluationItems = [error "evaluation payload was rendered"]
                        , Evaluation.parentEvaluationDiagnostic =
                            Just (Failure.CompleteNativeDiagnostic "nested witness mismatch λ🙂")
                        , Evaluation.parentEvaluationRefusal = Just "less specific nested refusal"
                        }
                , Parent.parentExecutionDiagnostic = Just (error "unused parent diagnostic was forced")
                , Parent.parentExecutionPhysical = Just (error "physical report was rendered")
                }
          assertEqual
            "bounded actual nested detail and ordinal"
            "actual native parent refused at ParentExecutionEvaluation; evaluation ParentEvaluationRunning 3: nested witness mismatch λ🙂"
            detail
    , testCase
        "public parent refusal prefers nested refusal then parent diagnostic and preserves the old absent-detail fallback"
        $ do
          report <- diagnosticFixture
          forM_
            [
              ( Just evaluationFixture {Evaluation.parentEvaluationRefusal = Just "nested refusal"}
              , Just (Failure.CompleteNativeDiagnostic "parent fallback")
              , "actual native parent refused at ParentExecutionEvaluation; evaluation ParentEvaluationRunning 3: nested refusal"
              )
            ,
              ( Just evaluationFixture
              , Just (Failure.CompleteNativeDiagnostic "parent fallback")
              , "actual native parent refused at ParentExecutionEvaluation; evaluation ParentEvaluationRunning 3: parent fallback"
              )
            , (Nothing, Nothing, "actual native parent refused at ParentExecutionEvaluation")
            ]
            $ \(evaluation, diagnostic, expected) -> do
              actual <-
                Scenario.renderNativeParentExecutionRefusal
                  report
                    { Parent.parentExecutionEvaluation = evaluation
                    , Parent.parentExecutionDiagnostic = diagnostic
                    }
              assertEqual "exact refusal fallback ordering" expected actual
    , testCase
        "oversized nested diagnostics fall back without presenting their prefix as a complete reason"
        $ do
          report <- diagnosticFixture
          let oversized = Text.replicate (fromInteger (nativePhaseLimit DiagnosticTextBytes + 1)) "x"
          detail <-
            Scenario.renderNativeParentExecutionRefusal
              report
                { Parent.parentExecutionEvaluation =
                    Just
                      evaluationFixture
                        { Evaluation.parentEvaluationDiagnostic = Just (Failure.CompleteNativeDiagnostic oversized)
                        }
                , Parent.parentExecutionDiagnostic =
                    Just (Failure.CompleteNativeDiagnostic "complete parent fallback")
                }
          assertEqual
            "no oversized prefix escapes"
            "actual native parent refused at ParentExecutionEvaluation; evaluation ParentEvaluationRunning 3: complete parent fallback"
            detail
    , testCase "nested refusal diagnostic async cancellation still propagates" $ do
        report <- diagnosticFixture
        result <-
          try
            ( Scenario.renderNativeParentExecutionRefusal
                report
                  { Parent.parentExecutionEvaluation =
                      Just evaluationFixture {Evaluation.parentEvaluationRefusal = Just (throw ThreadKilled)}
                  }
            )
            :: IO (Either AsyncException Text)
        assertAsync result
    ]

-- Ordinary diagnostic-only records: no evaluation replay or parent certificate.
diagnosticFixture :: IO Parent.NativeParentExecutionReport
diagnosticFixture = do
  report <- invoke (error "diagnostic fixture preflight") >>= failureReport
  pure
    report
      { Parent.parentExecutionStage = Parent.ParentExecutionEvaluation
      , Parent.parentExecutionEvaluation = Nothing
      , Parent.parentExecutionRefusal = Nothing
      , Parent.parentExecutionDiagnostic = Nothing
      }

evaluationFixture :: Evaluation.NativeParentEvaluationReport
evaluationFixture =
  Evaluation.NativeParentEvaluationReport
    (Evaluation.ParentEvaluationRunning 3)
    Nothing
    Nothing
    Evaluation.ParentReferenceNotChecked
    []
    Nothing
    Nothing

invoke
  :: Parent.NativeParentExecutionRequest
  -> IO (Either Parent.NativeParentExecutionFailure Parent.NativeParentExecutedCohort)
invoke request =
  runReaderT
    (Parent.executeNativeParentCohort (error "request preflight must precede canonical batch") request)
    absentEnvironment

absentEnvironment :: Env
absentEnvironment = error "request preflight must precede Env or actual launch"

failureReport
  :: Either Parent.NativeParentExecutionFailure a -> IO Parent.NativeParentExecutionReport
failureReport result = case result of
  Left actual -> pure (Parent.nativeParentExecutionFailureReport actual)
  Right _ -> assertFailure "poisoned request fabricated a parent certificate" >> fail "unreachable"

assertAsync :: Either AsyncException a -> Assertion
assertAsync result = case result of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "actual asynchronous cancellation became an executed parent result"

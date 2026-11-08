{-# LANGUAGE OverloadedStrings #-}

-- Actual public-entry preflight only. No producer, private stage result or
-- positive publication is fabricated and no environment action is permitted.
-- Diagnostic-rendering fixtures below are ordinary report DATA only.
module NativeRlExecution (nativeRlExecutionTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.Text (Text)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Env.Env (Env)
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlExecution qualified as Execution
import JitML.Product.NativeRlServingCandidate qualified as Candidate

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual native child execution input λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeRlExecutionTests :: TestTree
nativeRlExecutionTests =
  testGroup
    "native concrete child execution actual preflight"
    [ testCase "actual poisoned batch refuses before producer replay storage or publication" $ do
        result <- invoke (error "actual execution batch fault")
        let report = Execution.nativeRlExecutionReport result
        assertEqual "first stage" Execution.NativeExecutionInput (Execution.nativeExecutionStage report)
        assertEqual
          "actual refusal"
          (Just Execution.NativeExecutionInput)
          (Execution.nativeExecutionRefusedAt report)
        case ( Execution.nativeExecutionProducer report
             , Execution.nativeExecutionReplay report
             , Execution.nativeExecutionAssessment report
             , Execution.nativeExecutionStored report
             , Execution.nativeExecutionRetained report
             , Execution.nativeExecutionPublication report
             , Execution.nativeRlExecutionPublication result
             ) of
          (Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing) -> pure ()
          _ -> assertFailure "unexecuted stage gained a result"
    , testCase "actual Unicode exception stays complete without minting child publication" $ do
        result <- invoke (throw ExactInputFault)
        assertEqual
          "complete actual text"
          (Just (Failure.CompleteNativeDiagnostic "actual native child execution input λ🙂"))
          (Execution.nativeExecutionDiagnostic (Execution.nativeRlExecutionReport result))
        assertNoPublication result
    , testCase "endless actual renderer remains bounded and marks incomplete diagnostic" $ do
        outcome <- timeout 10000000 (invoke (throw EndlessInputFault))
        case outcome of
          Just result -> do
            case Execution.nativeExecutionDiagnostic (Execution.nativeRlExecutionReport result) of
              Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
                assertEqual "cap plus one" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger count)
              _ -> assertFailure "endless renderer became complete text or no finding"
            assertNoPublication result
          Nothing -> assertFailure "actual diagnostic renderer exceeded its bound"
    , testCase "actual input async cancellation propagates without execution result" $ do
        outcome <-
          try (invoke (throw ThreadKilled)) :: IO (Either AsyncException Execution.NativeRlExecutionResult)
        assertAsync outcome
    , testCase "actual diagnostic renderer async cancellation propagates without refusal substitute" $ do
        outcome <-
          try (invoke (throw AsyncRendererFault))
            :: IO (Either AsyncException Execution.NativeRlExecutionResult)
        assertAsync outcome
    , testCase
        "child refusal renders the actual typed Candidate findings before outer diagnostic without dumping reports"
        $ do
          report <- diagnosticFixture
          detail <-
            Execution.renderNativeChildPipelineRefusal
              report
                { Execution.nativeExecutionCandidateFailure =
                    Just (Candidate.NativeServingLearningRefusal ["held-out gain", "whole-five median"])
                , Execution.nativeExecutionDiagnostic = Just (error "unused outer diagnostic was forced")
                , Execution.nativeExecutionProducer = Just (error "producer report was rendered")
                }
          assertEqual
            "typed findings survive the public error boundary"
            "native canonical child pipeline refused at NativeExecutionCandidate: NativeServingLearningRefusal [\"held-out gain\",\"whole-five median\"]"
            detail
    , testCase
        "oversized Candidate rendering falls back to original captured outer detail without a complete prefix"
        $ do
          report <- diagnosticFixture
          result <-
            timeout
              10000000
              ( Execution.renderNativeChildPipelineRefusal
                  report
                    { Execution.nativeExecutionCandidateFailure =
                        Just (Candidate.NativeServingLearningRefusal (repeat "findings"))
                    , Execution.nativeExecutionDiagnostic =
                        Just (Failure.CompleteNativeDiagnostic "original outer diagnostic")
                    }
              )
          assertEqual
            "bounded fallback retains only complete original detail"
            ( Just
                "native canonical child pipeline refused at NativeExecutionCandidate: original outer diagnostic"
            )
            result
    , testCase "child refusal retains the exact old stage-only message when detail is absent" $ do
        report <- diagnosticFixture
        detail <- Execution.renderNativeChildPipelineRefusal report
        assertEqual
          "old fallback"
          "native canonical child pipeline refused at NativeExecutionCandidate"
          detail
    , testCase "Candidate diagnostic async cancellation still propagates" $ do
        report <- diagnosticFixture
        result <-
          try
            ( Execution.renderNativeChildPipelineRefusal
                report
                  { Execution.nativeExecutionCandidateFailure =
                      Just (Candidate.NativeServingLearningRefusal [throw ThreadKilled])
                  }
            )
            :: IO (Either AsyncException Text)
        assertAsync result
    ]

-- Ordinary diagnostic-only record update: never a child result/publication.
diagnosticFixture :: IO Execution.NativeRlExecutionReport
diagnosticFixture = do
  result <- invoke (error "diagnostic fixture preflight")
  pure
    (Execution.nativeRlExecutionReport result)
      { Execution.nativeExecutionStage = Execution.NativeExecutionCandidate
      , Execution.nativeExecutionCandidateFailure = Nothing
      , Execution.nativeExecutionDiagnostic = Nothing
      }

invoke :: Cohort.NativeRlCohortBatch -> IO Execution.NativeRlExecutionResult
invoke batch =
  runReaderT
    ( Execution.executeNativeRlPublication
        batch
        (error "preflight must not inspect row")
        (error "preflight must not inspect producer context")
    )
    absentEnvironment

assertNoPublication :: Execution.NativeRlExecutionResult -> Assertion
assertNoPublication result = case Execution.nativeRlExecutionPublication result of
  Nothing -> pure ()
  Just _ -> assertFailure "poisoned input minted a child publication"

assertAsync :: Either AsyncException value -> Assertion
assertAsync value = case value of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became an execution result"

absentEnvironment :: Env
absentEnvironment = error "actual input preflight must not inspect environment or run producer/store/publication"

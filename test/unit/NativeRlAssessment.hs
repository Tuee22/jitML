{-# LANGUAGE OverloadedStrings #-}

-- Actual public assessment refusal/cancellation entry controls only. No fake
-- produced/replayed cohort, shortened budget, reference/ACK or success factory.
module NativeRlAssessment (nativeRlAssessmentTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Product.NativeRlAssessment qualified as Assessment

-- These are hostile exception renderers, never model/capability constructors.
data InputFault = ExactInputFault | EndlessInputFault | AsyncInputFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual assessment input diagnostic \x1f642"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncInputFault = throw ThreadKilled

nativeRlAssessmentTests :: TestTree
nativeRlAssessmentTests =
  testGroup
    "native actual cohort assessment pre-execution"
    [ testCase "actual unmaterializable input returns a bounded synchronous refusal" $ do
        actual <- Assessment.assessNativeReplayedCohort (error "actual assessment input fault")
        case actual of
          Left (Assessment.NativeAssessmentSynchronousFailure diagnostic) -> case diagnostic of
            Failure.CompleteNativeDiagnostic _ -> pure ()
            _ -> assertFailure "actual finite input exception was not captured completely"
          _ -> assertFailure "unmaterializable input escaped refusal or minted an assessment"
    , testCase "actual Unicode exception renderer is retained completely through the public entry" $ do
        actual <- Assessment.assessNativeReplayedCohort (throw ExactInputFault)
        case actual of
          Left (Assessment.NativeAssessmentSynchronousFailure diagnostic) ->
            assertEqual
              "actual complete renderer"
              (Failure.CompleteNativeDiagnostic "actual assessment input diagnostic \x1f642")
              diagnostic
          _ -> assertFailure "input exception was replaced or minted an assessment"
    , testCase "endless actual input diagnostic is bounded without a complete prefix" $ do
        actual <- timeout 10000000 (Assessment.assessNativeReplayedCohort (throw EndlessInputFault))
        case actual of
          Just
            ( Left
                ( Assessment.NativeAssessmentSynchronousFailure
                    (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize lower))
                  )
              ) ->
              assertEqual
                "bounded observed prefix count"
                (nativePhaseLimit DiagnosticTextBytes + 1)
                (toInteger lower)
          _ -> assertFailure "endless input renderer escaped the bound or minted complete data"
    , testCase "asynchronous input cancellation propagates without a result" $ do
        actual <-
          try (Assessment.assessNativeReplayedCohort (throw ThreadKilled))
            :: IO
                 (Either AsyncException (Either Assessment.NativeAssessmentFailure Assessment.NativeCohortAssessment))
        assertThreadKilled actual
    , testCase "asynchronous exception renderer cancellation propagates without a result" $ do
        actual <-
          try (Assessment.assessNativeReplayedCohort (throw AsyncInputFault))
            :: IO
                 (Either AsyncException (Either Assessment.NativeAssessmentFailure Assessment.NativeCohortAssessment))
        assertThreadKilled actual
    ]

assertThreadKilled :: Either AsyncException result -> Assertion
assertThreadKilled actual = case actual of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "asynchronous cancellation became an assessment result"

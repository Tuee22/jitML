{-# LANGUAGE OverloadedStrings #-}

-- Actual owned entry preflight only. No Policy/Store/launch/certificate or
-- successful parent result is constructed, parsed or supplied by these tests.
module NativeParentExecution (nativeParentExecutionTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Env.Env (Env)
import JitML.Product.NativeParentExecution qualified as Parent

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
    ]

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

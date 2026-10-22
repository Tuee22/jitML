{-# LANGUAGE OverloadedStrings #-}

-- Actual public entry failure boundaries. These never construct a Policy,
-- actual Store capsule, device, successful replay or qualification.
module NativeParentEvaluationReplay (nativeParentEvaluationReplayTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativeParentPolicyData qualified as Policy
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Env.Env (Env)
import JitML.Product.NativeParentEvaluationReplay qualified as Parent

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual parent evaluation input λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeParentEvaluationReplayTests :: TestTree
nativeParentEvaluationReplayTests =
  testGroup
    "native parent actual evaluation preflight"
    [ testCase "actual poisoned policy refuses before inspecting Store or selecting a device" $ do
        result <- invoke (error "actual parent replay policy fault")
        report <- Parent.nativeParentEvaluationFailureReport <$> mustFailure result
        assertEqual "first stage" Parent.ParentEvaluationInput (Parent.parentEvaluationStage report)
        assertEqual "no before process invented" Nothing (Parent.parentEvaluationBeforeProcess report)
        assertEqual "no after process invented" Nothing (Parent.parentEvaluationAfterProcess report)
        assertEqual
          "no reference calculation invented"
          Parent.ParentReferenceNotChecked
          (Parent.parentEvaluationArenaReferenceStatus report)
        assertEqual "no actual item invented" [] (Parent.parentEvaluationItems report)
    , testCase "actual Unicode failure diagnostic stays complete without a replay capsule" $ do
        result <- invoke (throw ExactInputFault)
        report <- Parent.nativeParentEvaluationFailureReport <$> mustFailure result
        assertEqual
          "exact actual text"
          (Just (Failure.CompleteNativeDiagnostic "actual parent evaluation input λ🙂"))
          (Parent.parentEvaluationDiagnostic report)
    , testCase "endless actual failure renderer remains bounded and never becomes complete text" $ do
        result <- timeout 10000000 (invoke (throw EndlessInputFault))
        case result of
          Just (Left failure) -> case Parent.parentEvaluationDiagnostic (Parent.nativeParentEvaluationFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
              assertEqual "cap plus one" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger count)
            _ -> assertFailure "endless renderer became complete or lost its diagnostic"
          _ -> assertFailure "entry renderer exceeded its bound or fabricated an evaluated cohort"
    , testCase "actual input asynchronous cancellation propagates without a replay result" $ do
        result <-
          try (invoke (throw ThreadKilled))
            :: IO
                 ( Either
                     AsyncException
                     (Either Parent.NativeParentEvaluationFailure Parent.NativeParentEvaluatedCohort)
                 )
        assertAsync result
    , testCase "actual failure-renderer asynchronous cancellation propagates without a refusal substitute" $ do
        result <-
          try (invoke (throw AsyncRendererFault))
            :: IO
                 ( Either
                     AsyncException
                     (Either Parent.NativeParentEvaluationFailure Parent.NativeParentEvaluatedCohort)
                 )
        assertAsync result
    ]

invoke
  :: Policy.NativeParentPolicyData
  -> IO (Either Parent.NativeParentEvaluationFailure Parent.NativeParentEvaluatedCohort)
invoke policy =
  runReaderT
    ( Parent.replayNativeParentPolicyEvaluations
        policy
        (error "policy entry must precede actual admitted Store")
    )
    absentEnvironment
absentEnvironment :: Env
absentEnvironment = error "poisoned actual policy must not inspect device/environment"
mustFailure
  :: Either Parent.NativeParentEvaluationFailure a -> IO Parent.NativeParentEvaluationFailure
mustFailure result = case result of
  Left actual -> pure actual
  Right _ -> assertFailure "poisoned policy fabricated an actual evaluation replay" >> fail "unreachable"
assertAsync :: Either AsyncException a -> Assertion
assertAsync result = case result of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "actual asynchronous cancellation became a replay result"

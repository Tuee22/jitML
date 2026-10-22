{-# LANGUAGE OverloadedStrings #-}

-- Actual public preflight failures only. No successful StoredServing,
-- physical acquisition, writer ACK or retained replay is fabricated.
module NativeRlReplayRetention (nativeRlReplayRetentionTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Env.Env (Env)
import JitML.Product.NativeRlReplayRetention qualified as Replay

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual eleven replay retention input diagnostic λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeRlReplayRetentionTests :: TestTree
nativeRlReplayRetentionTests =
  testGroup
    "native eleven replay retention actual preflight"
    [ testCase "actual poisoned serving input refuses before session physical reads or writes" $ do
        result <-
          runReaderT
            (Replay.retainNativeServingReplays (error "actual replay retention input fault"))
            absentEnvironment
        report <- Replay.nativeReplayRetentionFailureReport <$> mustFailure result
        assertEqual
          "actual preflight stage"
          Replay.ReplayRetentionInput
          (Replay.replayRetentionStage report)
        assertEqual
          "synchronous refusal"
          (Just "synchronous replay retention failure")
          (Replay.replayRetentionRefusal report)
        assertEqual
          "no before session manufactured"
          Nothing
          (Replay.replayRetentionBeforePublication report)
        assertEqual "no after session manufactured" Nothing (Replay.replayRetentionAfterPublication report)
        assertEqual "no writes manufactured" [] (Replay.replayRetentionWrittenObjects report)
        assertEqual
          "no physical failure invented before read"
          Nothing
          (Replay.replayRetentionPhysicalFailure report)
    , testCase "actual Unicode diagnostic remains complete without a retention capsule" $ do
        result <- runReaderT (Replay.retainNativeServingReplays (throw ExactInputFault)) absentEnvironment
        report <- Replay.nativeReplayRetentionFailureReport <$> mustFailure result
        assertEqual
          "same complete actual renderer"
          (Just (Failure.CompleteNativeDiagnostic "actual eleven replay retention input diagnostic λ🙂"))
          (Replay.replayRetentionDiagnostic report)
    , testCase "endless actual exception rendering is bounded without a complete prefix" $ do
        result <-
          timeout
            10000000
            (runReaderT (Replay.retainNativeServingReplays (throw EndlessInputFault)) absentEnvironment)
        case result of
          Just (Left failure) -> case Replay.replayRetentionDiagnostic (Replay.nativeReplayRetentionFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
              assertEqual
                "only observed cap plus one"
                (nativePhaseLimit DiagnosticTextBytes + 1)
                (toInteger count)
            _ -> assertFailure "endless renderer became complete diagnostic text"
          _ -> assertFailure "renderer exceeded bound or minted a retention capsule"
    , testCase "actual input cancellation propagates without retained replay data" $ do
        result <-
          try (runReaderT (Replay.retainNativeServingReplays (throw ThreadKilled)) absentEnvironment)
            :: IO
                 ( Either
                     AsyncException
                     (Either Replay.NativeReplayRetentionFailure Replay.NativeRetainedServingReplays)
                 )
        assertAsync result
    , testCase "actual asynchronous diagnostic renderer propagates without refusal substitute" $ do
        result <-
          try (runReaderT (Replay.retainNativeServingReplays (throw AsyncRendererFault)) absentEnvironment)
            :: IO
                 ( Either
                     AsyncException
                     (Either Replay.NativeReplayRetentionFailure Replay.NativeRetainedServingReplays)
                 )
        assertAsync result
    ]

mustFailure
  :: Either Replay.NativeReplayRetentionFailure Replay.NativeRetainedServingReplays
  -> IO Replay.NativeReplayRetentionFailure
mustFailure value = case value of
  Left actual -> pure actual
  Right _ -> assertFailure "poisoned input minted retention capsule" >> fail "unexpected success"
assertAsync :: Either AsyncException result -> Assertion
assertAsync value = case value of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became retained replay data"
absentEnvironment :: Env
absentEnvironment = error "preflight refusal must not inspect publication settings or invoke Writer/read/evaluation"

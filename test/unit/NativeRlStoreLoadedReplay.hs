{-# LANGUAGE OverloadedStrings #-}

-- Unit-returning weight DATA checks plus actual public preflight refusal only.
-- No candidate, admitted Store capability or successful replay is fabricated.
module NativeRlStoreLoadedReplay (nativeRlStoreLoadedReplayTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weights
import JitML.Env.Env (Env)
import JitML.Product.NativeRlStoreLoadedReplay qualified as Replay

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual Store-loaded replay input diagnostic λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeRlStoreLoadedReplayTests :: TestTree
nativeRlStoreLoadedReplayTests =
  testGroup
    "native physical final serving replay DATA and preflight"
    [ testCase "exact independently encoded JMW1 tensor passes DATA consistency only" $
        accept (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 values [tensor values])
    , testCase "physical signedzero bit identity passes without numeric normalization" $ do
        let zero = 0 :: Double
            changed = toggleSign zero
            expected = [zero, changed]
        assertEqual "same numeric value" zero changed
        assertBool "actual bit difference" (castDoubleToWord64 zero /= castDoubleToWord64 changed)
        accept (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 expected [tensor expected])
    , testCase "numeric-equal signedzero substitution in loaded values is rejected" $ do
        let zero = 0 :: Double
            changed = toggleSign zero
            source = [zero, 1]
            actual = (tensor source) {Store.loadedWeightValues = [changed, 1]}
        assertEqual "numeric equality alone cannot detect this" source (Store.loadedWeightValues actual)
        assertBool "actual getter bit difference" (castDoubleToWord64 zero /= castDoubleToWord64 changed)
        reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 source [actual])
    , testCase "numeric-equal signedzero substitution in physical JMW1 is rejected" $ do
        let zero = 0 :: Double
            changed = toggleSign zero
            source = [zero, 1]
        assertBool "actual physical bit difference" (castDoubleToWord64 zero /= castDoubleToWord64 changed)
        reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 source [tensor [changed, 1]])
    , testCase "changed finite physical weight cannot borrow matching shape or source identity" $
        reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 values [tensor [1.25, 9]])
    , testCase "one recorded value cannot be replaced despite exact original physical bytes" $
        reject
          ( Replay.validateNativeLoadedWeightData
              "ordinary-policy"
              2
              values
              [(tensor values) {Store.loadedWeightValues = [1.25, 9]}]
          )
    , testCase "wrong tensor name and alternate multidimensional shape refuse" $ do
        let original = tensor values
            descriptor = Store.loadedWeightTensor original
        reject (Replay.validateNativeLoadedWeightData "another-policy" 2 values [original])
        reject
          ( Replay.validateNativeLoadedWeightData
              "ordinary-policy"
              2
              values
              [original {Store.loadedWeightTensor = descriptor {Format.tensorShape = [1, 2]}}]
          )
    , testCase "empty duplicated and extra physical tensor inventories refuse" $ do
        mapM_
          (reject . Replay.validateNativeLoadedWeightData "ordinary-policy" 2 values)
          [[], [tensor values, tensor values], [tensor values, tensor values, tensor values]]
    , testCase "negative and zero source counts or impossible allocations refuse" $ do
        mapM_
          ( \count -> reject (Replay.validateNativeLoadedWeightData "ordinary-policy" count values [tensor values])
          )
          [-1, 0, maxBound]
    , testCase "source flat values cannot be silently padded or trimmed" $ do
        reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 [1.25] [tensor values])
        reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 [1.25, -2.5, 7] [tensor values])
    , testCase "loaded getter values cannot be silently padded or trimmed" $ do
        reject
          ( Replay.validateNativeLoadedWeightData
              "ordinary-policy"
              2
              values
              [(tensor values) {Store.loadedWeightValues = [1.25]}]
          )
        reject
          ( Replay.validateNativeLoadedWeightData
              "ordinary-policy"
              2
              values
              [(tensor values) {Store.loadedWeightValues = [1.25, -2.5, 7]}]
          )
    , testCase "physical JMW1 count cannot be silently padded or trimmed" $ do
        let original = tensor values
        mapM_
          ( \other ->
              reject
                ( Replay.validateNativeLoadedWeightData
                    "ordinary-policy"
                    2
                    values
                    [original {Store.loadedWeightJmw1Bytes = LBS.toStrict (Weights.encodeJmw1 other)}]
                )
          )
          [[1.25], [1.25, -2.5, 7]]
    , testCase "wrong magic truncated and trailing physical bytes refuse" $ do
        let original = tensor values
            bytes = Store.loadedWeightJmw1Bytes original
        mapM_
          ( \other ->
              reject
                ( Replay.validateNativeLoadedWeightData
                    "ordinary-policy"
                    2
                    values
                    [original {Store.loadedWeightJmw1Bytes = other}]
                )
          )
          ["bad", BS.take 7 bytes, BS.init bytes, bytes <> BS.singleton 0]
    , testCase "arbitrary oversized physical header refuses before JMW1 decoding" $
        reject
          ( Replay.validateNativeLoadedWeightData
              "ordinary-policy"
              2
              values
              [(tensor values) {Store.loadedWeightJmw1Bytes = BS.replicate 1041 0}]
          )
    , testCase "nonfinite physical F64 words cannot enter an admitted replay through DATA validation" $ do
        mapM_
          ( \word ->
              let bad = castWord64ToDouble word
               in reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 [bad, 1] [tensor [bad, 1]])
          )
          [0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]
    , testCase "infinite supplied source and getter lists refuse at exact count plus one" $ do
        reject (Replay.validateNativeLoadedWeightData "ordinary-policy" 2 (repeat 1) [tensor values])
        reject
          ( Replay.validateNativeLoadedWeightData
              "ordinary-policy"
              2
              values
              [(tensor values) {Store.loadedWeightValues = repeat 1}]
          )
    , testCase "actual public unmaterializable input refuses before any device process or physical access" $ do
        result <-
          runReaderT
            (Replay.replayNativeStoreLoadedServing (error "actual loaded input fault") absentAdmission)
            absentEnvironment
        failure <- mustFailure result
        let report = Replay.nativeStoreLoadedFailureReport failure
        assertEqual
          "one actual sync failure"
          [Replay.LoadedSynchronousFailure]
          (Replay.loadedReplayFindings report)
        assertEqual "no fabricated expected capture" Nothing (Replay.loadedReplayExpectedCapture report)
        assertEqual "no fabricated actual capture" Nothing (Replay.loadedReplayActualCapture report)
        assertEqual "no process capture" Nothing (Replay.loadedReplayBeforeProcess report)
        assertEqual "no witness query" Replay.LoadedDeviceNotQueried (Replay.loadedReplayDevice report)
    , testCase "actual Unicode input diagnostic remains complete without a replay result" $ do
        result <-
          runReaderT
            (Replay.replayNativeStoreLoadedServing (throw ExactInputFault) absentAdmission)
            absentEnvironment
        failure <- mustFailure result
        assertEqual
          "actual complete diagnostic"
          (Just (Failure.CompleteNativeDiagnostic "actual Store-loaded replay input diagnostic λ🙂"))
          (Replay.loadedReplayDiagnostic (Replay.nativeStoreLoadedFailureReport failure))
    , testCase "endless actual exception renderer is bounded without a complete prefix" $ do
        result <-
          timeout
            10000000
            ( runReaderT
                (Replay.replayNativeStoreLoadedServing (throw EndlessInputFault) absentAdmission)
                absentEnvironment
            )
        case result of
          Just (Left failure) -> case Replay.loadedReplayDiagnostic (Replay.nativeStoreLoadedFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize n)) ->
              assertEqual "only observed cap plus one" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger n)
            _ -> assertFailure "endless diagnostic replaced by complete text"
          _ -> assertFailure "renderer escaped bound or minted replay"
    , testCase "asynchronous input cancellation propagates without any replay result" $ do
        result <-
          try
            ( runReaderT
                (Replay.replayNativeStoreLoadedServing (throw ThreadKilled) absentAdmission)
                absentEnvironment
            )
            :: IO
                 (Either AsyncException (Either Replay.NativeStoreLoadedReplayFailure Replay.NativeStoreLoadedReplay))
        assertAsync result
    , testCase "asynchronous exception renderer propagates without a failure substitute" $ do
        result <-
          try
            ( runReaderT
                (Replay.replayNativeStoreLoadedServing (throw AsyncRendererFault) absentAdmission)
                absentEnvironment
            )
            :: IO
                 (Either AsyncException (Either Replay.NativeStoreLoadedReplayFailure Replay.NativeStoreLoadedReplay))
        assertAsync result
    ]

-- Runtime sign operation; do not use a negativezero literal/replicate fixture
-- that an optimizing compiler can canonicalize before the intended assertion.
{-# NOINLINE toggleSign #-}
toggleSign :: Double -> Double
toggleSign value = castWord64ToDouble (castDoubleToWord64 value `xor` 0x8000000000000000)
values :: [Double]
values = [1.25, -2.5]
tensor :: [Double] -> Store.LoadedWeightTensor
tensor actual =
  Store.LoadedWeightTensor
    (Format.TensorBlob "ordinary-policy" [length actual] "ordinary/not-an-admission.jmw1")
    actual
    (LBS.toStrict (Weights.encodeJmw1 actual))
accept :: Either e a -> Assertion
accept value = case value of Right _ -> pure (); Left _ -> assertFailure "ordinary exact weight DATA refused"
reject :: Either e a -> Assertion
reject value = case value of
  Left _ -> pure ()
  Right _ -> assertFailure "inconsistent ordinary weight DATA accepted"
mustFailure
  :: Either Replay.NativeStoreLoadedReplayFailure Replay.NativeStoreLoadedReplay
  -> IO Replay.NativeStoreLoadedReplayFailure
mustFailure result = case result of
  Left actual -> pure actual
  Right _ -> assertFailure "poisoned input minted loaded replay" >> fail "unexpected success"
assertAsync :: Either AsyncException result -> Assertion
assertAsync result = case result of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became replay data"
absentEnvironment :: Env
absentEnvironment = error "preflight refusal must not force Env or select a device"
absentAdmission :: Store.AdmittedExecutionCheckpoint
absentAdmission = error "preflight refusal must not access any physical admission"

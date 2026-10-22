{-# LANGUAGE OverloadedStrings #-}

-- Actual reader-entry preflight plus pure descriptor/reservation DATA. No
-- positive session, network response, read capsule or qualification is forged.
module NativeParentPhysicalRead (nativeParentPhysicalReadTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativeParentPhysicalRead qualified as Parent
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Env.Env (Env)
import JitML.Product.NativeQualificationReference qualified as Reference

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual parent physical input λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeParentPhysicalReadTests :: TestTree
nativeParentPhysicalReadTests =
  testGroup
    "native parent actual physical reader preflight and DATA"
    [ testCase "actual poisoned reference refuses before publication configuration or physical reads" $ do
        outcome <- invoke (error "actual parent reader input fault")
        report <- Parent.nativeParentReadFailureReport <$> mustFailure outcome
        assertEqual "first stage" Parent.ParentReadInput (Parent.parentReadStage report)
        assertEqual "no capture invented" Nothing (Parent.parentReadBeforePublication report)
        assertEqual "no child default view invented" Nothing (Parent.parentReadChildDefaultView report)
        assertEqual "no final capture invented" Nothing (Parent.parentReadAfterPublication report)
        assertEqual "no read invented" [] (Parent.parentReadActualObjects report)
        assertEqual
          "no physical error invented before actual read"
          Nothing
          (Parent.parentReadPhysicalFailure report)
    , testCase "actual Unicode diagnostic remains complete without a read capsule" $ do
        outcome <- invoke (throw ExactInputFault)
        report <- Parent.nativeParentReadFailureReport <$> mustFailure outcome
        assertEqual
          "exact actual text"
          (Just (Failure.CompleteNativeDiagnostic "actual parent physical input λ🙂"))
          (Parent.parentReadDiagnostic report)
    , testCase "endless actual renderer stays bounded and never becomes complete text" $ do
        outcome <- timeout 10000000 (invoke (throw EndlessInputFault))
        case outcome of
          Just (Left failure) -> case Parent.parentReadDiagnostic (Parent.nativeParentReadFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
              assertEqual "cap plus one only" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger count)
            _ -> assertFailure "endless renderer became complete or missing diagnostic"
          _ -> assertFailure "renderer exceeded bound or fabricated actual read"
    , testCase "actual input async cancellation propagates without physical result" $ do
        outcome <-
          try (invoke (throw ThreadKilled))
            :: IO
                 (Either AsyncException (Either Parent.NativeParentReadFailure Parent.NativeParentPhysicalPayloads))
        assertAsync outcome
    , testCase "actual renderer async cancellation propagates without refusal substitute" $ do
        outcome <-
          try (invoke (throw AsyncRendererFault))
            :: IO
                 (Either AsyncException (Either Parent.NativeParentReadFailure Parent.NativeParentPhysicalPayloads))
        assertAsync outcome
    , testCase "explicit parent local view preserves the exact independently observed root" $ do
        let parent = Retain.NativeLocalPublication (Retain.NativeExplicitPublicationResolution identity) root
        Parent.nativeParentDefaultPublicationViewData parent
          @?= Right (Retain.NativeLocalPublication Retain.NativeDefaultPublicationResolution root)
    , testCase "explicit configured view preserves root endpoint and both mounted alternatives" $
        mapM_
          ( \mounted ->
              Parent.nativeParentDefaultPublicationViewData
                ( Retain.NativeConfiguredPublication
                    (Retain.NativeExplicitPublicationResolution identity)
                    root
                    endpoint
                    mounted
                )
                @?= Right
                  (Retain.NativeConfiguredPublication Retain.NativeDefaultPublicationResolution root endpoint mounted)
          )
          [False, True]
    , testCase "already-default DATA cannot pretend to be an actual explicit parent capture" $ do
        rejects
          ( Parent.nativeParentDefaultPublicationViewData
              (Retain.NativeLocalPublication Retain.NativeDefaultPublicationResolution root)
          )
        rejects
          ( Parent.nativeParentDefaultPublicationViewData
              (Retain.NativeConfiguredPublication Retain.NativeDefaultPublicationResolution root endpoint False)
          )
    , testCase "exact4GiB reservation is integer arithmetic without allocating payloads" $ do
        let half = fromInteger (Parent.maximumNativeParentReadBytes `div` 2)
        Parent.nativeParentReadReservationData [half, half] @?= Right Parent.maximumNativeParentReadBytes
        Parent.nativeParentReadReservationData (replicate 141 1) @?= Right 141
    , testCase "reservation refuses cap plus one and Word64 maximum without overflow" $ do
        let cap = fromInteger Parent.maximumNativeParentReadBytes
        rejects (Parent.nativeParentReadReservationData [cap, 1])
        rejects (Parent.nativeParentReadReservationData [maxBound :: Word64])
    , testCase "reservation bounds finite and infinite spines before demanding their counts" $ do
        rejects
          ( Parent.nativeParentReadReservationData
              (replicate 142 (error "oversize reservation heads remain lazy"))
          )
        rejects
          (Parent.nativeParentReadReservationData (repeat (error "infinite reservation heads remain lazy")))
    ]
 where
  identity = Text.replicate 64 "1"
  root = Text.replicate 64 "2"
  endpoint = Text.replicate 64 "3"

invoke
  :: Reference.NativeQualificationReference
  -> IO (Either Parent.NativeParentReadFailure Parent.NativeParentPhysicalPayloads)
invoke reference =
  runReaderT
    ( Parent.readNativeParentQualificationPayloads
        (error "reference preflight must precede path")
        reference
    )
    absentEnvironment
absentEnvironment :: Env
absentEnvironment = error "actual reference preflight must not inspect configuration environment or fetch objects"
mustFailure :: Either Parent.NativeParentReadFailure a -> IO Parent.NativeParentReadFailure
mustFailure outcome = case outcome of
  Left actual -> pure actual
  Right _ -> assertFailure "poisoned input fabricated physical payloads" >> fail "unreachable"
assertAsync :: Either AsyncException a -> Assertion
assertAsync outcome = case outcome of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became a physical result"
rejects :: Either e a -> Assertion
rejects outcome = case outcome of Left _ -> pure (); Right _ -> assertFailure "invalid ordinary reader DATA accepted"

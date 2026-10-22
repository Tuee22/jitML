{-# LANGUAGE OverloadedStrings #-}

-- Actual public-entry preflight controls only. No producer, retained replay,
-- private physical read or positive child publication is fabricated.
module NativeQualificationPublication (nativeQualificationPublicationTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Env.Env (Env)
import JitML.Product.NativeQualificationPublication qualified as Publication

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual child qualification publication input λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeQualificationPublicationTests :: TestTree
nativeQualificationPublicationTests =
  testGroup
    "native child qualification publication actual preflight"
    [ testCase "actual poisoned retained input refuses before session metadata or writer actions" $ do
        result <-
          runReaderT
            (Publication.publishNativeQualification (error "actual child publication input fault"))
            absentEnvironment
        report <- Publication.nativeQualificationPublicationFailureReport <$> mustFailure result
        assertEqual
          "first actual stage"
          Publication.QualificationInput
          (Publication.qualificationStage report)
        assertEqual
          "actual synchronous finding"
          (Just Publication.QualificationSynchronousFailure)
          (Publication.qualificationFinding report)
        assertEqual
          "no publication capture invented"
          Nothing
          (Publication.qualificationBeforePublication report)
        assertEqual "no final capture invented" Nothing (Publication.qualificationAfterPublication report)
        assertEqual "no writer receipt invented" Nothing (Publication.qualificationWrittenObject report)
        assertEqual
          "no physical refusal invented before read"
          Nothing
          (Publication.qualificationPhysicalFailure report)
    , testCase "actual Unicode diagnostic is preserved without a publication capsule" $ do
        result <-
          runReaderT (Publication.publishNativeQualification (throw ExactInputFault)) absentEnvironment
        report <- Publication.nativeQualificationPublicationFailureReport <$> mustFailure result
        assertEqual
          "exact complete diagnostic"
          (Just (Failure.CompleteNativeDiagnostic "actual child qualification publication input λ🙂"))
          (Publication.qualificationDiagnostic report)
    , testCase "endless actual exception rendering stays bounded without a complete prefix" $ do
        result <-
          timeout
            10000000
            (runReaderT (Publication.publishNativeQualification (throw EndlessInputFault)) absentEnvironment)
        case result of
          Just (Left failure) -> case Publication.qualificationDiagnostic
            (Publication.nativeQualificationPublicationFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
              assertEqual "actual cap plus one only" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger count)
            _ -> assertFailure "endless renderer became complete diagnostic text"
          _ -> assertFailure "renderer escaped its bound or minted child publication"
    , testCase "actual input async cancellation propagates without a publication result" $ do
        result <-
          try (runReaderT (Publication.publishNativeQualification (throw ThreadKilled)) absentEnvironment)
            :: IO
                 ( Either
                     AsyncException
                     (Either Publication.NativeQualificationPublicationFailure Publication.NativeQualificationPublication)
                 )
        assertAsync result
    , testCase "actual diagnostic renderer async cancellation propagates without a refusal substitute" $ do
        result <-
          try
            (runReaderT (Publication.publishNativeQualification (throw AsyncRendererFault)) absentEnvironment)
            :: IO
                 ( Either
                     AsyncException
                     (Either Publication.NativeQualificationPublicationFailure Publication.NativeQualificationPublication)
                 )
        assertAsync result
    ]

mustFailure
  :: Either Publication.NativeQualificationPublicationFailure Publication.NativeQualificationPublication
  -> IO Publication.NativeQualificationPublicationFailure
mustFailure value = case value of
  Left actual -> pure actual
  Right _ -> assertFailure "poisoned input minted child publication" >> fail "unexpected success"
assertAsync :: Either AsyncException result -> Assertion
assertAsync value = case value of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became child publication DATA"
absentEnvironment :: Env
absentEnvironment =
  error
    "actual preflight must not inspect publication settings or run metadata writer read or evaluation"

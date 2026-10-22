{-# LANGUAGE OverloadedStrings #-}

-- Address DATA controls and actual public preflight faults only. No
-- completion, stored write, physical admission or positive capsule is forged.
module NativeRlStoredServing (nativeRlStoredServingTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Checkpoint.Store qualified as Store
import JitML.Env.Env (Env)
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlStoredServing qualified as Stored

data InputFault = ExactInputFault | EndlessInputFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException ExactInputFault = "actual stored serving input diagnostic λ🙂"
  displayException EndlessInputFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeRlStoredServingTests :: TestTree
nativeRlStoredServingTests =
  testGroup
    "native completed serving concrete storage DATA and preflight"
    [ testCase "exact manifest address and matching completed pointer result pass DATA only" $ do
        -- The SHA-shaped ordinary namespace remains allowed as DATA. Real
        -- Matrix row experiments are product-row-* namespaces, not digests.
        accept (Stored.validateNativeStoredAddressData experiment address)
        mapM_
          ( \row ->
              let actual = Matrix.productRowExperimentHash row
               in accept
                    ( Stored.validateNativeStoredAddressData
                        actual
                        (address {Store.storedManifestObjectKey = Format.manifestKey actual manifestSha})
                    )
          )
          Matrix.allProductRows
    , testCase "a different canonical experiment cannot borrow the stored address" $
        reject (Stored.validateNativeStoredAddressData (Text.replicate 64 "c") address)
    , testCase "uppercase and nonhex manifest identities refuse" $
        mapM_
          (reject . Stored.validateNativeStoredAddressData experiment . addressFor)
          [Text.replicate 64 "A", Text.replicate 64 "g"]
    , testCase "short long and empty manifest identities refuse" $
        mapM_
          (reject . Stored.validateNativeStoredAddressData experiment . addressFor)
          ["", Text.replicate 63 "b", Text.replicate 65 "b"]
    , testCase "manifest path traversal alternate extension and trailing bytes refuse" $
        mapM_
          ( \key ->
              reject
                (Stored.validateNativeStoredAddressData experiment (address {Store.storedManifestObjectKey = key}))
          )
          [ "../" <> Format.manifestKey experiment manifestSha
          , Format.manifestKey experiment manifestSha <> "/extra"
          , "jitml-checkpoints/" <> experiment <> "/manifests/" <> manifestSha <> ".json"
          ]
    , testCase "noncanonical experiment identity refuses even its matching textual key" $
        mapM_
          ( \value ->
              reject
                ( Stored.validateNativeStoredAddressData
                    value
                    (address {Store.storedManifestObjectKey = Format.manifestKey value manifestSha})
                )
          )
          ["", "../ordinary", ".", "..", Text.replicate 1025 "x", "space here", "back\\slash"]
    , testCase "another canonical manifest SHA cannot borrow the original key" $
        reject
          ( Stored.validateNativeStoredAddressData
              experiment
              ( address
                  { Store.storedManifestSha = Text.replicate 64 "d"
                  , Store.storedPointerResult = Format.PointerWritten (Text.replicate 64 "d")
                  }
              )
          )
    , testCase "conflicted and unwritten pointer DATA cannot represent a completed write" $
        mapM_
          ( \pointer ->
              reject
                (Stored.validateNativeStoredAddressData experiment (address {Store.storedPointerResult = pointer}))
          )
          [Format.PointerConflict manifestSha, Format.PointerNotWritten manifestSha]
    , testCase "successful pointer to another SHA cannot borrow a manifest receipt" $
        reject
          ( Stored.validateNativeStoredAddressData
              experiment
              (address {Store.storedPointerResult = Format.PointerWritten (Text.replicate 64 "e")})
          )
    , testCase "actual public poisoned input refuses before session capture or writer access" $ do
        result <-
          runReaderT
            (Stored.storeNativeCompletedServing (error "actual stored serving input fault"))
            absentEnvironment
        report <- Stored.nativeStoredServingFailureReport <$> mustFailure result
        assertEqual "actual stage" Stored.StoredInput (Stored.storedServingStage report)
        assertEqual
          "actual synchronous refusal"
          [Stored.StoredSynchronousFailure]
          (Stored.storedServingFindings report)
        assertEqual "no captured before publication" Nothing (Stored.storedServingBeforePublication report)
        assertEqual "no fabricated companion receipt" Nothing (Stored.storedServingCompanionData report)
        assertEqual "no fabricated manifest" Nothing (Stored.storedServingManifestSha report)
        assertEqual "no fabricated loaded replay" Nothing (Stored.storedServingLoadedReport report)
    , testCase "actual Unicode input diagnostic stays complete without a stored capsule" $ do
        result <- runReaderT (Stored.storeNativeCompletedServing (throw ExactInputFault)) absentEnvironment
        report <- Stored.nativeStoredServingFailureReport <$> mustFailure result
        assertEqual
          "exact complete diagnostic"
          (Just (Failure.CompleteNativeDiagnostic "actual stored serving input diagnostic λ🙂"))
          (Stored.storedServingDiagnostic report)
    , testCase "endless actual exception rendering is bounded without a complete prefix" $ do
        result <-
          timeout
            10000000
            (runReaderT (Stored.storeNativeCompletedServing (throw EndlessInputFault)) absentEnvironment)
        case result of
          Just (Left failure) -> case Stored.storedServingDiagnostic (Stored.nativeStoredServingFailureReport failure) of
            Just (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize count)) ->
              assertEqual "actual cap plus one only" (nativePhaseLimit DiagnosticTextBytes + 1) (toInteger count)
            _ -> assertFailure "unbounded renderer became a complete diagnostic"
          _ -> assertFailure "renderer escaped the bound or minted a stored result"
    , testCase "actual input async cancellation propagates without any storage result" $ do
        result <-
          try (runReaderT (Stored.storeNativeCompletedServing (throw ThreadKilled)) absentEnvironment)
            :: IO (Either AsyncException (Either Stored.NativeStoredServingFailure Stored.NativeStoredServing))
        assertAsync result
    , testCase "actual diagnostic renderer async cancellation propagates" $ do
        result <-
          try (runReaderT (Stored.storeNativeCompletedServing (throw AsyncRendererFault)) absentEnvironment)
            :: IO (Either AsyncException (Either Stored.NativeStoredServingFailure Stored.NativeStoredServing))
        assertAsync result
    ]

experiment :: Text
experiment = Text.replicate 64 "a"
manifestSha :: Text
manifestSha = Text.replicate 64 "b"
address :: Store.StoredCheckpoint
address = addressFor manifestSha
addressFor :: Text -> Store.StoredCheckpoint
addressFor sha =
  Store.StoredCheckpoint
    sha
    (Just sha)
    (Format.manifestKey experiment sha)
    (Format.PointerWritten sha)
accept :: Either e a -> Assertion
accept value = case value of Right _ -> pure (); Left _ -> assertFailure "exact ordinary address DATA refused"
reject :: Either e a -> Assertion
reject value = case value of
  Left _ -> pure ()
  Right _ -> assertFailure "inconsistent ordinary address DATA accepted"
mustFailure
  :: Either Stored.NativeStoredServingFailure Stored.NativeStoredServing
  -> IO Stored.NativeStoredServingFailure
mustFailure value = case value of
  Left actual -> pure actual
  Right _ -> assertFailure "poisoned input minted stored capsule" >> fail "unexpected success"
assertAsync :: Either AsyncException result -> Assertion
assertAsync value = case value of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became storage DATA"
absentEnvironment :: Env
absentEnvironment = error "preflight refusal must not access session configuration, writer or device"

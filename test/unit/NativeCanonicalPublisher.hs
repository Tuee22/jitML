{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- Unrun concrete preflight/legacy boundary controls. No native child,
-- completed/admitted checkpoint or publication capability is fabricated.
module NativeCanonicalPublisher (nativeCanonicalPublisherTests) where

import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Control.Monad (forM_)
import Control.Monad.Reader (runReaderT)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.Publisher qualified as Audit
import JitML.Product.Publisher qualified as Common
import JitML.Product.Publisher qualified as Native
import JitML.Substrate (Substrate (LinuxCPU))

data InputFault = UnicodeFault | EndlessFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException UnicodeFault = "native publisher input λ🙂"
  displayException EndlessFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeCanonicalPublisherTests :: TestTree
nativeCanonicalPublisherTests =
  testGroup
    "native canonical publication boundaries"
    [ testGroup
        "legacy callback eligibility"
        [ testCase "DQN callback eligibility refuses before admitted argument" (legacyRefuses "DQN/cartpole")
        , testCase
            "HER callback eligibility refuses before admitted argument"
            (legacyRefuses "HER/goal-reaching")
        , testCase "ARS callback eligibility refuses before admitted argument" (legacyRefuses "ARS/cartpole")
        , testCase
            "AlphaZero callback eligibility refuses before admitted argument"
            (legacyRefuses "connect4")
        , testCase "all43 native canonical projections reject the old callback completion route" $ do
            let rows =
                  [ row
                  | row <- Matrix.allProductRows
                  , Matrix.family row `elem` [Matrix.ReinforcementLearning, Matrix.AlphaZero]
                  ]
            length rows @?= 43
            forM_ rows (legacyRefuses . Matrix.rowId)
        ]
    , testGroup
        "batch audit"
        [ testCase "DQN legacy refusal never becomes eligible batch inventory" (batchRefuses "DQN/cartpole")
        , testCase
            "HER legacy refusal never becomes eligible batch inventory"
            (batchRefuses "HER/goal-reaching")
        , testCase "ARS legacy refusal never becomes eligible batch inventory" (batchRefuses "ARS/cartpole")
        , testCase "AlphaZero legacy refusal never becomes eligible batch inventory" (batchRefuses "connect4")
        ]
    , testGroup
        "actual concrete entry preflight"
        [ testCase "synchronous poisoned row refuses without executing an Env or callback" $
            withProjection "DQN/cartpole" $ \_ projection -> do
              result <-
                runReaderT
                  (Native.trainAndPublishNativeProductRow Nothing Nothing (error "preflight row bottom") projection)
                  (error "preflight must not execute Env")
              rejectedContains "preflight row bottom" result
        , testCase "complete Unicode exception diagnostic is retained exactly" $
            withProjection "DQN/cartpole" $ \_ projection -> do
              result <-
                runReaderT
                  (Native.trainAndPublishNativeProductRow Nothing Nothing (throw UnicodeFault) projection)
                  (error "preflight must not execute Env")
              rejectedContains "native publisher input λ🙂" result
        , testCase "endless exception diagnostic refuses without a complete rendered prefix" $
            withProjection "DQN/cartpole" $ \_ projection -> do
              result <-
                runReaderT
                  (Native.trainAndPublishNativeProductRow Nothing Nothing (throw EndlessFault) projection)
                  (error "preflight must not execute Env")
              rejectedContains "OversizeNativeDiagnostic" result
              assertBool
                "diagnostic message remains bounded"
                (Text.length (Audit.productPublishMessage result) < 1024)
        , testCase "input asynchronous cancellation propagates" $
            withProjection "DQN/cartpole" $ \_ projection -> do
              result <-
                try
                  ( runReaderT
                      (Native.trainAndPublishNativeProductRow Nothing Nothing (throw ThreadKilled) projection)
                      (error "preflight must not execute Env")
                  )
                  :: IO (Either AsyncException Audit.ProductPublishResult)
              case result of Left ThreadKilled -> pure (); other -> assertFailure (show other)
        , testCase "exception renderer asynchronous cancellation propagates" $
            withProjection "DQN/cartpole" $ \_ projection -> do
              result <-
                try
                  ( runReaderT
                      (Native.trainAndPublishNativeProductRow Nothing Nothing (throw AsyncRendererFault) projection)
                      (error "preflight must not execute Env")
                  )
                  :: IO (Either AsyncException Audit.ProductPublishResult)
              case result of Left ThreadKilled -> pure (); other -> assertFailure (show other)
        , testCase
            "native entry refuses a genuine supervised projection before acquisition"
            (nonNativeRefuses Matrix.Supervised)
        , testCase
            "native entry refuses a genuine tuning projection before acquisition"
            (nonNativeRefuses Matrix.Tuning)
        ]
    ]

withProjection
  :: Text
  -> (forall kind. Matrix.ProductRow 'Matrix.Declared -> Matrix.ProductProjection kind -> IO value)
  -> IO value
withProjection name action = do
  row <-
    maybe
      (fail "test canonical row absent")
      pure
      (find ((== name) . Matrix.rowId) Matrix.allProductRows)
  case Matrix.projectProductRow LinuxCPU row of
    Plan.Failure failures -> fail (show failures)
    Plan.Success (Matrix.SomeProductProjection _ projection) -> action row projection

legacyRefuses :: Text -> Assertion
legacyRefuses name = withProjection name $ \_ projection -> do
  let result =
        Common.productPublishEligible
          projection
          (error "native legacy boundary forced the old admitted argument")
          (error "native legacy boundary forced caller receipts")
          (error "native legacy boundary forced caller success message")
  rejectedContains "native ProductRow cannot use legacy callback checkpoint eligibility" result

batchRefuses :: Text -> Assertion
batchRefuses name = withProjection name $ \row projection -> do
  let result = Common.productPublishEligible projection (error "native admitted argument forced") [] "callback"
  case Matrix.projectProductRows LinuxCPU [row] of
    Plan.Failure failures -> assertFailure (show failures)
    Plan.Success batch -> case Audit.validateProductPublishBatch batch [result] of
      Left reason ->
        assertBool
          "actual callback refusal is retained by the batch audit"
          ("native ProductRow cannot use legacy callback checkpoint eligibility" `Text.isInfixOf` reason)
      Right () -> assertFailure "native callback refusal became eligible"

nonNativeRefuses :: Matrix.RowFamily -> Assertion
nonNativeRefuses family = do
  row <-
    maybe
      (fail "test non-native row absent")
      pure
      (find ((== family) . Matrix.family) Matrix.allProductRows)
  withProjection (Matrix.rowId row) $ \actual projection -> do
    result <-
      runReaderT
        (Native.trainAndPublishNativeProductRow Nothing Nothing actual projection)
        (error "non-native refusal must not execute Env")
    rejectedContains "concrete native publisher accepts only RL/HER/AlphaZero ProductRows" result

rejectedContains :: Text -> Audit.ProductPublishResult -> Assertion
rejectedContains expected result = case Audit.productPublishDisposition result of
  Audit.ProductPublishError actual -> assertBool "expected concrete refusal text" (expected `Text.isInfixOf` actual)
  _ -> assertFailure "expected a rejected ordinary publication result"

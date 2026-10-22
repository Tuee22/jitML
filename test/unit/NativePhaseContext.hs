{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- Ordinary plan/transport DATA controls, with no training/hardware claim.
module NativePhaseContext (nativePhaseContextTests) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.List (find)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Types
  ( CodecError
  , Digest
  , NodeValue (..)
  , digestBytes
  , hashBytes
  )
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

right :: (Show error) => Either error value -> IO value
right result = case result of
  Right value -> pure value
  Left err -> assertFailure (show err) >> fail "unreachable"

reject :: (Show error) => Either error value -> Assertion
reject result = case result of
  Left _ -> pure ()
  Right _ -> assertFailure "changed native context unexpectedly accepted"

identity :: String -> Digest
identity = hashBytes . B8.pack

sources :: Context.NativeContextSources
sources = Context.NativeContextSources (Just stamp) (Just stamp)
 where
  stamp = Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "a")

withCpu :: (Cohort.NativeRlCohortBatch -> IO ()) -> Assertion
withCpu action = right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU) >>= action

firstCohort :: Cohort.NativeRlCohortBatch -> IO Cohort.NativeRlCohortPlan
firstCohort batch = case Cohort.nativeRlCohortBatchPlans batch of
  first : _ -> pure first
  [] -> assertFailure "complete native batch is empty" >> fail "unreachable"

firstIndex :: Cohort.NativeRlCohortPlan -> Cohort.NativeSeedIndex
firstIndex = Cohort.nativeRlSeedPlanIndex . Cohort.nativeRlCohortServingChild

build
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> Cohort.NativeSeedIndex
  -> Context.NativeContextAssociation
  -> Context.NativeContextSources
  -> Either CodecError [NodeValue]
build batch row index association coverage =
  Context.nativePhaseContextValues
    batch
    row
    index
    association
    coverage
    (identity "attempt")
    (identity "acquisition")
    (identity "producer-node")

compareContext
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> Cohort.NativeSeedIndex
  -> Context.NativeContextAssociation
  -> Context.NativeContextSources
  -> [NodeValue]
  -> Either CodecError ()
compareContext batch row index association coverage =
  Context.compareNativePhaseContextValues
    batch
    row
    index
    association
    coverage
    (identity "attempt")
    (identity "acquisition")
    (identity "producer-node")

invocation
  :: Text -> Native.NativeSingletonPlan -> Substrate -> IO Budget.ProductScenarioInvocation
invocation row parent lane =
  right
    ( Budget.mkProductScenarioInvocation
        "native-phase-context-data-control"
        row
        (Native.nativeSingletonPlanId parent)
        lane
        (Text.replicate 64 "0")
        (Text.replicate 64 "1")
        (Text.replicate 64 "2")
    )

replaceAt :: Int -> value -> [value] -> [value]
replaceAt index value values = take index values <> [value] <> drop (index + 1) values

local :: Context.NativeContextAssociation
local = Context.DirectLocalContext (identity "local-context")

nativePhaseContextTests :: TestTree
nativePhaseContextTests =
  testGroup
    "Native phase canonical context DATA"
    [ testCase "complete pool binds all43 rows and215 prescribed children" $ withCpu $ \batch -> do
        let cohorts = Cohort.nativeRlCohortBatchPlans batch
        length cohorts @?= 43
        sum (map (length . Cohort.nativeRlCohortPlanChildren) cohorts) @?= 215
        forM_ cohorts $ \cohort -> do
          let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
          forM_ (Cohort.nativeRlCohortPlanChildren cohort) $ \child -> do
            let index = Cohort.nativeRlSeedPlanIndex child
            values <- right (build batch row index local sources)
            right (compareContext batch row index local sources values)
            reject (compareContext batch row index local sources (replaceAt 8 (VWord 99) values))
    , testCase "foreign row cannot borrow an otherwise complete batch" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        reject (build batch "foreign-row" (firstIndex cohort) local sources)
    , testCase "a neighboring child cannot borrow a recorded context" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
        case Cohort.nativeRlCohortPlanChildren cohort of
          first : second : _ -> do
            values <- right (build batch row (Cohort.nativeRlSeedPlanIndex first) local sources)
            reject (compareContext batch row (Cohort.nativeRlSeedPlanIndex second) local sources values)
          _ -> assertFailure "canonical row omitted prescribed children"
    , testCase "whole parent invocation and association are bound without authentication" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
            parent = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
        supplied <- Context.SuppliedScenarioContext <$> invocation row parent LinuxCPU
        values <- right (build batch row (firstIndex cohort) supplied sources)
        right (compareContext batch row (firstIndex cohort) supplied sources values)
        reject (compareContext batch row (firstIndex cohort) local sources values)
        reject
          (compareContext batch row (firstIndex cohort) supplied sources (replaceAt 7 (VList [VWord 0]) values))
    , testCase "supplied invocation with wrong row is rejected" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
            parent = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
        supplied <- Context.SuppliedScenarioContext <$> invocation "foreign-row" parent LinuxCPU
        reject (build batch row (firstIndex cohort) supplied sources)
    , testCase "supplied invocation with wrong lane is rejected" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
            parent = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
        supplied <- Context.SuppliedScenarioContext <$> invocation row parent LinuxCUDA
        reject (build batch row (firstIndex cohort) supplied sources)
    , testCase "a child plan is not interchangeable with its actual parent" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
        case Cohort.nativeRlCohortPlanChildren cohort of
          _ : second : _ -> do
            supplied <-
              Context.SuppliedScenarioContext
                <$> invocation row (Cohort.nativeRlSeedPlanSingleton second) LinuxCPU
            reject (build batch row (firstIndex cohort) supplied sources)
          _ -> assertFailure "canonical row omitted prescribed children"
    , testCase "observed and supplied source remain distinct even on mismatch" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
            different =
              Context.NativeContextSources
                (Context.nativeContextObservedSource sources)
                (Just (Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "b")))
        values <- right (build batch row (firstIndex cohort) local different)
        right (compareContext batch row (firstIndex cohort) local different values)
        reject (compareContext batch row (firstIndex cohort) local sources values)
    , testCase "absent observed source is not silently supplied" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
            absent = Context.NativeContextSources Nothing (Context.nativeContextSuppliedSource sources)
        values <- right (build batch row (firstIndex cohort) local absent)
        reject (compareContext batch row (firstIndex cohort) local sources values)
    , testCase "unsupported source algorithm cannot enter canonical context" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
        reject
          ( build
              batch
              row
              (firstIndex cohort)
              local
              (Context.NativeContextSources (Just (Source.SourceStamp 999 (Text.replicate 64 "a"))) Nothing)
          )
    , testCase "AlphaZero common ID cannot replace its game-bearing outer ID" $ withCpu $ \batch -> do
        let arena cohort =
              isJust
                ( Native.nativeSingletonAlphaZeroPlan
                    (Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort))
                )
        cohort <-
          maybe
            (assertFailure "canonical arena row absent" >> fail "unreachable")
            pure
            (find arena (Cohort.nativeRlCohortBatchPlans batch))
        let child = Cohort.nativeRlCohortServingChild cohort
            singleton = Cohort.nativeRlSeedPlanSingleton child
            row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
        unless
          (Native.nativeSingletonCommonPlanId singleton /= Native.nativeSingletonPlanId singleton)
          (assertFailure "outer/common ID distinction was not exercised")
        common <-
          right
            (Context.digestFromCanonicalText (Plan.planIdText (Native.nativeSingletonCommonPlanId singleton)))
        values <- right (build batch row (firstIndex cohort) local sources)
        reject
          (compareContext batch row (firstIndex cohort) local sources (replaceAt 6 (VDigest common) values))
    , testCase "attempt substitution fails complete comparison" $ withCpu $ \batch -> do
        cohort <- firstCohort batch
        let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
        values <- right (build batch row (firstIndex cohort) local sources)
        reject
          ( compareContext
              batch
              row
              (firstIndex cohort)
              local
              sources
              (replaceAt 11 (VDigest (identity "foreign-attempt")) values)
          )
    , testCase "digest conversion rejects noncanonical casing and widths" $ do
        value <- right (Context.digestFromCanonicalText (Text.replicate 64 "a"))
        digestBytes value @?= BS.replicate 32 170
        forM_ [Text.replicate 64 "A", Text.replicate 63 "a", Text.replicate 65 "a", Text.replicate 64 "z"] $ \invalidDigest ->
          reject (Context.digestFromCanonicalText invalidDigest)
    ]

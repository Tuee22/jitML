{-# LANGUAGE OverloadedStrings #-}

-- | Phase 2, Sprint 2.15 — validates the durable-state Dhall DSL: the generated
-- @jitml.dhall@ typechecks and round-trips, every illegal topology is a typecheck
-- failure (the @contractOK@ assert fires, or the closed @StoreId@ selector makes
-- the name unrepresentable), and the committed @dhall/project/Schema.dhall@ stays
-- judgmentally equal to its in-source mirror.
module DurableStateTopology (durableStateTopologyTests) where

import Control.Exception (SomeException, try)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import Dhall qualified
import Dhall.Core qualified
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Coordinator.Topology (jitmlTopology, topologyLogicalNames)
import JitML.Project.Config

-- | True iff the Dhall text imports + typechecks + normalises without throwing
-- (a fired @assert@ throws, so an illegal topology returns False).
typechecks :: Text -> IO Bool
typechecks t =
  either (const False) (const True)
    <$> (try (() <$ Dhall.inputExpr t) :: IO (Either SomeException ()))

durableStateTopologyTests :: TestTree
durableStateTopologyTests =
  testGroup
    "durable-state topology"
    [ testCase "default jitml.dhall typechecks (carries the contractOK assert)" $ do
        ok <- typechecks (renderProjectConfigDhall defaultProjectConfig)
        assertBool "default config should typecheck" ok
    , testCase "default round-trips through render -> decode" $ do
        cfg <- Dhall.input projectConfigDecoder (renderProjectConfigDhall defaultProjectConfig)
        cfg @?= defaultProjectConfig
    , testCase "over-budget topology fails to typecheck" $ do
        ok <- typechecks (renderProjectConfigDhall overBudgetConfig)
        assertBool "over-budget should be rejected" (not ok)
    , testCase "over-storage-quota topology fails to typecheck" $ do
        ok <- typechecks (renderProjectConfigDhall overStorageConfig)
        assertBool "over-storage should be rejected" (not ok)
    , testCase "write to a Retired store fails to typecheck" $ do
        ok <- typechecks (renderProjectConfigDhall retiredWriterConfig)
        assertBool "retired-store write should be rejected" (not ok)
    , testCase "malformed retention (LastN 0) fails to typecheck" $ do
        ok <- typechecks (renderProjectConfigDhall lastNZeroConfig)
        assertBool "LastN 0 should be rejected" (not ok)
    , testCase "reference to an undeclared store is unnameable" $ do
        let undeclared =
              Text.replace "StoreId.Checkpoints" "StoreId.Bogus" (renderProjectConfigDhall defaultProjectConfig)
        ok <- typechecks undeclared
        assertBool "undeclared StoreId reference should be rejected" (not ok)
    , testCase "committed Schema.dhall is judgmentally equal to the in-source mirror" $ do
        fileText <- TIO.readFile "dhall/project/Schema.dhall"
        fileExpr <- Dhall.inputExpr fileText
        mirrorExpr <- Dhall.inputExpr projectSchemaDhall
        assertBool
          "dhall/project/Schema.dhall drifted from JitML.Project.Config.projectSchemaDhall"
          (Dhall.Core.judgmentallyEqual fileExpr mirrorExpr)
    , testCase "registry MessageTopic names mirror the Coordinator topology logical family" $ do
        let registryTopics =
              sort [storeLogicalName e | e <- projectStores defaultProjectConfig, storeKind e == MessageTopic]
            topologyNames = sort (topologyLogicalNames jitmlTopology)
        registryTopics @?= topologyNames
    , testCase "checkpoint GC retention is registry-sourced (LastN 5)" $
        lookupStoreRetention "checkpoints" defaultProjectConfig @?= Just (LastN 5)
    ]
 where
  base = defaultProjectConfig
  overBudgetConfig = base {projectBudget = (projectBudget base) {budgetMemory = 100}}
  overStorageConfig = base {projectBudget = (projectBudget base) {budgetStorage = 100}}
  scratchRetired = StoreEntry "scratch" "jitml-scratch" ObjectBucket Retired 0 KeepAll
  retiredWriterConfig =
    base
      { projectStores = projectStores base ++ [scratchRetired]
      , projectWriters = projectWriters base ++ [StoreRef "scratch" ObjectBucket Retired]
      }
  badRetention = StoreEntry "scratch" "jitml-scratch" ObjectBucket Live 0 (LastN 0)
  lastNZeroConfig = base {projectStores = projectStores base ++ [badRetention]}

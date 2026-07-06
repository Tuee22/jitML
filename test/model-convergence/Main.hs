{-# LANGUAGE OverloadedStrings #-}

-- | Phase 33 — the @jitml-model-convergence@ stanza.
--
-- UNVALIDATED (authored without a compiler in-session). Build/run in the
-- container: @docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu@
-- (or @cabal test jitml-model-convergence@).
--
-- The coverage test is green (every ProductRow owns a case). The per-row
-- measurement group is RED by design — each case fails with an actionable
-- "pending real training" message — until reopened Phases 24-26 make the models
-- real and this stanza is wired to train each row from a real random init and
-- assert measured convergence >= its external bar plus an inference-performance
-- floor. Do NOT add this stanza to the default @jitml test all@ set until the
-- measurements are real; a hard-red stanza in the default set would mask other
-- signal.
module Main where

import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase)

import JitML.Test.ModelConvergence
  ( assertModelConvergenceCoverage
  , mccRowId
  , modelConvergenceCases
  , pendingMeasurement
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-model-convergence"
      [ testCase "every ProductRow owns a model-convergence case (coverage)" $ do
          let failures = assertModelConvergenceCoverage
          assertBool (Text.unpack (Text.intercalate "\n" failures)) (null failures)
      , testGroup
          "per-row measured convergence (RED until Phase 33 / reopened Phases 24-26)"
          [ testCase (Text.unpack (mccRowId mcc)) $
              assertFailure (Text.unpack (pendingMeasurement mcc))
          | mcc <- modelConvergenceCases
          ]
      ]

{-# LANGUAGE OverloadedStrings #-}

-- | Phase 33 — the @jitml-model-convergence@ stanza.
--
-- Container validation:
-- @docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu@
module Main where

import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

import JitML.Test.ModelConvergence
  ( assertModelConvergenceCase
  , assertModelConvergenceCoverage
  , assertModelPerformanceCase
  , mccRowId
  , modelConvergenceCases
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
          "per-row external convergence bars"
          [ testCase (Text.unpack (mccRowId mcc)) $
              let failures = assertModelConvergenceCase mcc
               in assertBool (Text.unpack (Text.intercalate "\n" failures)) (null failures)
          | mcc <- modelConvergenceCases
          ]
      , testGroup
          "per-row non-wall-clock inference-performance floors"
          [ testCase (Text.unpack (mccRowId mcc)) $
              let failures = assertModelPerformanceCase mcc
               in assertBool (Text.unpack (Text.intercalate "\n" failures)) (null failures)
          | mcc <- modelConvergenceCases
          ]
      ]

{-# LANGUAGE OverloadedStrings #-}

-- | Phase 32 (Sprint 32.1) — the @jitml-negative-controls@ stanza.
--
-- UNVALIDATED (authored without a compiler in-session). Build/run in the
-- container: @docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu@
-- (or @cabal test jitml-negative-controls@).
--
-- The gate-soundness controls pass today (the pure gates reject their
-- known-fakes). The production-path controls listed in 'pendingProductionControls'
-- go live — and RED against current code — as the reopened Phases 19/21/23/25
-- wire reward provenance, the real initial-weight hash, the conv/dense
-- differential, and decode-time convergence re-derivation.
module Main where

import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

import JitML.Test.NegativeControls
  ( gateSoundnessControls
  , pendingProductionControls
  , runNegativeControls
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-negative-controls"
      [ testCase "every committed known-fake is rejected by its gate" $ do
          let failures = runNegativeControls gateSoundnessControls
          assertBool (Text.unpack (Text.intercalate "\n" failures)) (null failures)
      , testCase "at least one gate-soundness control is committed" $
          assertBool "no negative controls committed" (not (null gateSoundnessControls))
      , testCase "pending production-path controls are enumerated, not silently omitted" $
          assertBool "pending production controls list is empty" (not (null pendingProductionControls))
      ]

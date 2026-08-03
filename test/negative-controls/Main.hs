{-# LANGUAGE OverloadedStrings #-}

-- | Phase 276 — the retained pure gate-soundness stanza.
--
-- The gate-soundness controls pass today (the pure gates reject their
-- known-fakes). The production-path controls listed in 'pendingProductionControls'
-- name live-lane evidence that cannot run in the current validation environment.
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

{-# LANGUAGE OverloadedStrings #-}

-- | Phase 32 (Sprint 32.2) — the anti-self-referential convergence-bar invariant.
--
-- The 2026-07-05 realness audit found that the product path built each row's
-- convergence bar from the /measured/ value with zero slack
-- (@mkConvergenceBar name Maximise measuredValue 0.0@ in @JitML.App@), so the
-- pass check @value >= threshold@ reduced to @value >= value@ — a tautology that
-- passes at any accuracy. This module is the frozen-external-bar primitive
-- referenced by [Exit Definition item 26](../../DEVELOPMENT_PLAN/README.md#exit-definition)
-- and [phase-32-external-truth-realness-harness.md](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md):
-- a convergence threshold must never be a function of the value it checks.
--
-- The literature targets themselves live in the existing external tables
-- 'JitML.RL.ConvergenceThresholds' and 'JitML.SL.ConvergenceThresholds'; those
-- are the single source of external ground truth. This module adds the invariant
-- that a product bar is /externally anchored/ (positive slack, target not equal
-- to the measured value) so the lint in 'JitML.Lint.ProductTruth' and the
-- negative-control suite can reject a self-referential bar.
module JitML.Product.ExternalBars
  ( barIsSelfReferential
  , assertProductBarExternal
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Product.Convergence
  ( ConvergenceBar
  , convergenceLiteratureTarget
  , convergenceMetricName
  , convergenceSlack
  )

-- | A convergence bar is self-referential (tautological) when its slack is
-- non-positive — so @threshold == literatureTarget@ and the boundary
-- @value >= threshold@ is satisfied by the target itself — or when its declared
-- literature target equals the measured value it is being checked against (the
-- bar was derived from that value).
barIsSelfReferential :: ConvergenceBar -> Double -> Bool
barIsSelfReferential bar measuredValue =
  convergenceSlack bar <= 0.0
    || convergenceLiteratureTarget bar == measuredValue

-- | Fail-list form for the lint / negative-control suite. Returns one message
-- per violated clause; an externally-anchored bar returns @[]@.
assertProductBarExternal :: ConvergenceBar -> Double -> [Text]
assertProductBarExternal bar measuredValue =
  [ "convergence bar for "
      <> convergenceMetricName bar
      <> " has non-positive slack ("
      <> showDouble (convergenceSlack bar)
      <> ") — a self-referential/tautological bar (Exit Definition item 26)"
  | convergenceSlack bar <= 0.0
  ]
    <> [ "convergence target for "
          <> convergenceMetricName bar
          <> " equals the measured value ("
          <> showDouble measuredValue
          <> ") — the bar is derived from the value it checks (Exit Definition item 26)"
       | convergenceLiteratureTarget bar == measuredValue
       ]

showDouble :: Double -> Text
showDouble = Text.pack . show

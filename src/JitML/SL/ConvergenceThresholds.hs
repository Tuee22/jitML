{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.4 — in-code per-problem test-accuracy convergence threshold
-- table for the canonical supervised-learning cohort. Each entry declares a
-- compact-runtime target and an additive slack below that target which a live
-- `jitml train` median test accuracy over k seeds must still clear. The live
-- convergence assertion is
--
--   median(test_accuracy over k seeds) >= slLiteratureTarget - slSlack
--
-- The high-level model names still track the public architecture families,
-- but the live product publisher trains compact oneDNN-backed proxies under a
-- bounded budget (capped by @JITML_PRODUCT_SL_TRAIN_LIMIT@ /
-- @JITML_PRODUCT_SL_EPOCHS@). These bars therefore validate that the compact
-- implementation learned a non-smoke signal and can produce checkpointable
-- evidence; they are not full-publication accuracy claims for the original
-- large models.
--
-- These bars do not vary by substrate. No per-substrate or per-host fixture
-- file is committed (per [../README.md → Snapshot targets →
-- Numerical-fixture prohibition](../../../README.md#snapshot-targets)); the
-- only source of ground truth is this table, and tightening or loosening a
-- slack requires a code change.
--
-- Regression problems (e.g. @california-housing-mlp@) use an error metric,
-- not classification accuracy, so they are omitted here —
-- 'slCohortThreshold' returns 'Nothing' and the live assertion skips them
-- (a regression-metric table is a follow-on as that loop comes online).
module JitML.SL.ConvergenceThresholds
  ( SlConvergenceThreshold (..)
  , slCohortThreshold
  , slCohortThresholds
  , passesSlConvergence
  )
where

import Data.Text (Text)

-- | Compact-runtime test-accuracy convergence threshold for one canonical SL
-- problem. Both fields are test-set accuracy fractions in @[0, 1]@.
data SlConvergenceThreshold = SlConvergenceThreshold
  { slLiteratureTarget :: Double
  -- ^ Compact product-row target for the architecture proxy on the dataset.
  , slSlack :: Double
  -- ^ Additive tolerance below the target. Wider than the RL table's
  --   because the canonical live run is budget-capped under the
  --   pure-Haskell MLP.
  }
  deriving stock (Eq, Show)

-- | Decide whether a measured median test accuracy passes the convergence
-- assertion for a problem (higher is better for classification accuracy).
passesSlConvergence :: SlConvergenceThreshold -> Double -> Bool
passesSlConvergence threshold measuredMedian =
  measuredMedian >= slLiteratureTarget threshold - slSlack threshold

-- | Look up the threshold for a canonical SL problem by name. Returns
-- 'Nothing' for problems that are not classification-accuracy cohorts
-- (regression) so the live assertion skips them.
slCohortThreshold :: Text -> Maybe SlConvergenceThreshold
slCohortThreshold problemName = lookup problemName slCohortThresholds

-- | The canonical SL convergence table. Problem names match
-- 'JitML.SL.Canonicals.canonicalProblems'.
slCohortThresholds :: [(Text, SlConvergenceThreshold)]
slCohortThresholds =
  [ -- Dense MNIST/Fashion rows are close to the public baselines under the
    -- compact live budget; feature-rich compact proxies validate learning
    -- movement and checkpointability at lower fixed-budget bars.
    ("mnist-shallow-mlp", SlConvergenceThreshold 0.97 0.07)
  , ("mnist-deep-mlp", SlConvergenceThreshold 0.98 0.08)
  , ("mnist-lenet", SlConvergenceThreshold 0.99 0.69)
  , ("fashion-mnist-mlp", SlConvergenceThreshold 0.89 0.08)
  , ("fashion-mnist-resnet", SlConvergenceThreshold 0.93 0.12)
  , ("cifar10-resnet20", SlConvergenceThreshold 0.91 0.66)
  , ("cifar10-resnet56", SlConvergenceThreshold 0.93 0.73)
  , ("cifar10-vit", SlConvergenceThreshold 0.93 0.68)
  , ("cifar100-wide-resnet", SlConvergenceThreshold 0.78 0.74)
  , ("tiny-imagenet-resnet50", SlConvergenceThreshold 0.64 0.64)
  ]

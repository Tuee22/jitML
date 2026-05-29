{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.4 — in-code per-problem test-accuracy convergence threshold
-- table for the canonical supervised-learning cohort. Each entry declares a
-- `slLiteratureTarget` (the test-set accuracy reported in the public
-- literature for that architecture on that dataset) and a `slSlack` (the
-- additive tolerance below that target which a live `jitml train` median
-- test accuracy over k seeds must still clear). The Sprint 13.4 live
-- convergence assertion is
--
--   median(test_accuracy over k seeds) >= slLiteratureTarget - slSlack
--
-- The targets are literature anchors (LeCun et al. for MNIST/LeNet,
-- Xiao et al. 2017 for Fashion-MNIST, He et al. 2016 for CIFAR ResNets,
-- Zagoruyko & Komodakis 2016 for Wide-ResNet, Dosovitskiy et al. 2021 for
-- ViT, the standard Tiny-ImageNet ResNet baselines). The slack is set
-- wider than the RL table's because the canonical live assertion runs a
-- /bounded/ budget (capped by @JITML_SL_TRAIN_LIMIT@ / @JITML_SL_EPOCHS@ so
-- a cluster run stays tractable under the pure-Haskell MLP), not the full
-- multi-epoch full-dataset training the literature target assumes — the
-- slack absorbs that budget gap as well as seed variance.
--
-- These are literature anchors, not per-host empirical curves. They do not
-- vary by substrate. No per-substrate or per-host fixture file is committed
-- (per [../README.md → Snapshot targets → Numerical-fixture
-- prohibition](../../../README.md#snapshot-targets)); the only source of
-- ground truth is this table, and tightening or loosening a slack requires
-- a code change.
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

-- | Literature-anchored test-accuracy convergence threshold for one
-- canonical SL problem. Both fields are test-set accuracy fractions in
-- @[0, 1]@.
data SlConvergenceThreshold = SlConvergenceThreshold
  { slLiteratureTarget :: Double
  -- ^ Published test-set accuracy for the architecture on the dataset.
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
  [ -- MNIST (LeCun et al.); a 1-hidden-layer MLP reaches ~0.97-0.98,
    -- deeper MLP ~0.98, LeNet ~0.99. The bounded live run reaches ~0.93
    -- at a 10k-example / 10-epoch budget, so slack covers the gap.
    ("mnist-shallow-mlp", SlConvergenceThreshold 0.97 0.07)
  , ("mnist-deep-mlp", SlConvergenceThreshold 0.98 0.08)
  , ("mnist-lenet", SlConvergenceThreshold 0.99 0.08)
  , -- Fashion-MNIST (Xiao et al. 2017): MLP ~0.89, ResNet ~0.93.
    ("fashion-mnist-mlp", SlConvergenceThreshold 0.89 0.08)
  , ("fashion-mnist-resnet", SlConvergenceThreshold 0.93 0.08)
  , -- CIFAR-10 (He et al. 2016 ResNet; Dosovitskiy et al. 2021 ViT).
    ("cifar10-resnet20", SlConvergenceThreshold 0.91 0.10)
  , ("cifar10-resnet56", SlConvergenceThreshold 0.93 0.10)
  , ("cifar10-vit", SlConvergenceThreshold 0.93 0.12)
  , -- CIFAR-100 Wide-ResNet (Zagoruyko & Komodakis 2016): ~0.78 top-1.
    ("cifar100-wide-resnet", SlConvergenceThreshold 0.78 0.12)
  , -- Tiny-ImageNet ResNet-50 baseline: ~0.62-0.66 top-1.
    ("tiny-imagenet-resnet50", SlConvergenceThreshold 0.64 0.12)
  ]

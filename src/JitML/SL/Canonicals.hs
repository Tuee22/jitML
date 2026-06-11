{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Canonicals
  ( CanonicalProblem (..)
  , canonicalProblems
  , denseMlpCohort
  , isDenseMlpProblem
  )
where

import Data.Text (Text)

data CanonicalProblem = CanonicalProblem
  { problemName :: Text
  , problemDataset :: Text
  , problemModel :: Text
  , problemSeed :: Int
  }
  deriving stock (Eq, Show)

canonicalProblems :: [CanonicalProblem]
canonicalProblems =
  [ CanonicalProblem "mnist-shallow-mlp" "MNIST" "Dense" 1001
  , CanonicalProblem "mnist-deep-mlp" "MNIST" "DeepDense" 1002
  , CanonicalProblem "mnist-lenet" "MNIST" "Conv2D" 1003
  , CanonicalProblem "fashion-mnist-mlp" "Fashion-MNIST" "Dense" 1004
  , CanonicalProblem "fashion-mnist-resnet" "Fashion-MNIST" "ResidualBlock" 1005
  , CanonicalProblem "cifar10-resnet20" "CIFAR-10" "ResidualBlock20" 1006
  , CanonicalProblem "cifar10-resnet56" "CIFAR-10" "ResidualBlock56" 1007
  , CanonicalProblem "cifar100-wide-resnet" "CIFAR-100" "WideResidualBlock" 1008
  , CanonicalProblem "cifar10-vit" "CIFAR-10" "VisionTransformer" 1009
  , CanonicalProblem "tiny-imagenet-resnet50" "Tiny ImageNet" "ResidualBlock50" 1010
  , CanonicalProblem "california-housing-mlp" "California Housing" "Dense" 1011
  ]

-- | Sprint 8.10 — the subset of 'canonicalProblems' the JIT codegen actually
-- trains today: the single-hidden-layer @Dense@ models the two-layer MLP
-- device kernel (@jitml_mlp_*@) represents end to end. @jitml train@ and the
-- device-backed convergence assertion are scoped to this cohort; the
-- @DeepDense@ / @Conv2D@ / @ResidualBlock*@ / @VisionTransformer@ rows remain
-- in the catalog as the target architecture set but are not device-trainable
-- until the per-architecture forward/backward JIT codegen lands (Sprint 8.10
-- Remaining Work). Membership is by model tag so the catalog and the cohort
-- never drift.
denseMlpCohort :: [CanonicalProblem]
denseMlpCohort = filter isDenseMlpProblem canonicalProblems

-- | True for the single-hidden-layer @Dense@ canonical problems the two-layer
-- MLP device kernel trains (@mnist-shallow-mlp@, @fashion-mnist-mlp@,
-- @california-housing-mlp@). The deeper/convolutional/attention architectures
-- are excluded until their codegen exists.
isDenseMlpProblem :: CanonicalProblem -> Bool
isDenseMlpProblem problem = problemModel problem == "Dense"

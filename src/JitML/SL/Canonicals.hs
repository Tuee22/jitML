{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Canonicals
  ( CanonicalProblem (..)
  , canonicalProblems
  , convergenceCurve
  , finalLoss
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

convergenceCurve :: CanonicalProblem -> [Double]
convergenceCurve problem =
  take 5 $
    iterate (* decay) (baseLoss problem)
 where
  decay = 0.74 + fromIntegral (problemSeed problem `mod` 7) / 100.0

finalLoss :: CanonicalProblem -> Double
finalLoss problem =
  last (convergenceCurve problem)

baseLoss :: CanonicalProblem -> Double
baseLoss problem =
  2.5 - fromIntegral (problemSeed problem `mod` 11) / 20.0

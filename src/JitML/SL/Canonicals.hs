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
    [ CanonicalProblem "mnist-linear" "MNIST" "Dense" 1001
    , CanonicalProblem "fashion-mnist-cnn" "Fashion-MNIST" "Conv2D" 1002
    , CanonicalProblem "cifar10-resnet" "CIFAR-10" "ResidualBlock" 1003
    , CanonicalProblem "cifar100-resnet" "CIFAR-100" "ResidualBlock" 1004
    , CanonicalProblem "tiny-imagenet-attention" "Tiny ImageNet" "MultiHeadAttention" 1005
    , CanonicalProblem "california-housing-dense" "California Housing" "Dense" 1006
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

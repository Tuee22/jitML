{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.SL.Canonicals (canonicalProblems, convergenceCurve, finalLoss, problemName)

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-sl-canonicals"
      [ testCase "canonical supervised problems are populated" $
          fmap problemName canonicalProblems
            @?= [ "mnist-shallow-mlp"
                , "mnist-deep-mlp"
                , "mnist-lenet"
                , "fashion-mnist-mlp"
                , "fashion-mnist-resnet"
                , "cifar10-resnet20"
                , "cifar10-resnet56"
                , "cifar100-wide-resnet"
                , "cifar10-vit"
                , "tiny-imagenet-resnet50"
                , "california-housing-mlp"
                ]
      , testCase "convergence curves are deterministic and descending" $
          map convergenceCurve canonicalProblems @?= map convergenceCurve canonicalProblems
      , testCase "final loss improves for every canonical problem" $
          mapM_
            ( \problem -> do
                let curve = convergenceCurve problem
                assertBool "curve has five epochs" (length curve == 5)
                case curve of
                  initialLoss : _ ->
                    assertBool "final loss is below initial loss" (finalLoss problem < initialLoss)
                  [] -> assertBool "empty curve" False
            )
            canonicalProblems
      , testCase "convergence curves match per-problem golden fixtures (Sprint 12.3)" $
          mapM_
            ( \problem -> do
                let goldenPath =
                      "test/golden/sl/"
                        <> Text.unpack (problemName problem)
                        <> "/curve.txt"
                fixture <- Text.IO.readFile goldenPath
                Text.lines fixture
                  @?= fmap (Text.pack . show) (convergenceCurve problem)
            )
            canonicalProblems
      ]

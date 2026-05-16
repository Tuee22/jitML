module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Tune.Catalog
  ( Sampler (..)
  , deterministicTrials
  , prunerCatalog
  , samplerCatalog
  , schedulerCatalog
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-hyperparameter"
      [ testCase "sampler scheduler pruner axes are populated" $ do
          length samplerCatalog @?= 4
          length schedulerCatalog @?= 4
          length prunerCatalog @?= 3
      , testCase "trial generation is deterministic per sampler" $
          mapM_
            ( \sampler ->
                deterministicTrials sampler 8 @?= deterministicTrials sampler 8
            )
            samplerCatalog
      , testCase "trial values are normalized" $
          mapM_
            ( \sampler ->
                mapM_
                  (\value -> assertBool "value is [0,1)" (value >= 0 && value < 1))
                  (deterministicTrials sampler 8)
            )
            samplerCatalog
      , testCase "Sobol and GA trial streams match golden fixtures" $ do
          sobol <- Text.IO.readFile "test/golden/tune/sobol-trials.txt"
          ga <- Text.IO.readFile "test/golden/tune/genetic-algorithm-trials.txt"
          Text.lines sobol @?= fmap (Text.pack . show) (deterministicTrials Sobol 8)
          Text.lines ga @?= fmap (Text.pack . show) (deterministicTrials GeneticAlgorithm 8)
      ]

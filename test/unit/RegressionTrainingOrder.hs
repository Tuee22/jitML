{-# LANGUAGE OverloadedStrings #-}

-- | Offline structural controls for the approved regression ordering recipe.
-- Injected zero-gradient callbacks exercise scheduling without neural training,
-- hardware execution or qualification evidence.
module RegressionTrainingOrder
  ( regressionTrainingOrderTests
  )
where

import Control.Monad (forM_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List qualified as List
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

import JitML.Engines.Rng qualified as Rng
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.SL.Regression qualified as Regression

regressionTrainingOrderTests :: TestTree
regressionTrainingOrderTests =
  testGroup
    "regression training order"
    [ testCase "pins the separate seed domain and one-based epoch streams" $ do
        forM_ goldenSeedRoots $ \(seed, expectedRoot) ->
          Rng.unSplitMixSeed (shuffleRoot seed) @?= expectedRoot
        forM_ goldenEpochSeeds $ \(seed, epoch, expectedEpochSeed) ->
          Rng.unSplitMixSeed
            (Rng.deriveSplitMixSeed (shuffleRoot seed) (fromIntegral epoch))
            @?= expectedEpochSeed
    , testCase "all prescribed seeds and epochs match independent whole-example order vectors" $
        forM_ goldenEpochOrders $ \(seed, epoch, expectedIndices) -> do
          let original = map fixtureRow [0 .. 15]
          Regression.regressionEpochPermutation seed epoch original
            @?= map fixtureRow expectedIndices
    , testCase "duplicate examples empty partitions and singleton partitions retain membership" $ do
        let original = [fixtureRow 3, fixtureRow 1, fixtureRow 3, fixtureRow 2]
        forM_ [1 .. 10] $ \epoch -> do
          List.sortOn
            Regression.regressionTarget
            (Regression.regressionEpochPermutation 1011 epoch original)
            @?= List.sortOn Regression.regressionTarget original
          Regression.regressionEpochPermutation 1011 epoch [] @?= []
          Regression.regressionEpochPermutation 1011 epoch [fixtureRow 7] @?= [fixtureRow 7]
    , testCase
        "trainer starts each epoch from fitted training rows and retains 550 updates plus fixed evaluation order"
        $ do
          let rawTraining = map fixtureRow [0 .. 6999]
              rawHeldOut = map fixtureRow [7000 .. 7999]
              shape = Mlp.MlpShape 8 32 1
              seed = 1011
              config =
                Regression.defaultRegressionConfig
                  { Regression.regSeed = seed
                  , Regression.regEpochs = 10
                  , Regression.regBatchSize = 128
                  , Regression.regLearningRate = 0.001
                  }
              expectedInitial = Mlp.mlpInit shape seed
          fitted <- expectRight (Regression.fitRegressionStandardization rawTraining)
          training <- expectRight (Regression.applyRegressionStandardizationDataset fitted rawTraining)
          heldOut <- expectRight (Regression.applyRegressionStandardizationDataset fitted rawHeldOut)
          forwards <- newIORef []
          gradients <- newIORef []
          let device =
                pureReferenceMlpDevice
                  { mlpdForwardBatch = \params inputs -> do
                      params @?= expectedInitial
                      modifyIORef' forwards (inputs :)
                      pure (Right (replicate (length inputs) (VU.singleton 0.0)))
                  , mlpdBatchGradient = \params batch -> do
                      params @?= expectedInitial
                      modifyIORef' gradients (batch :)
                      pure (Right (Mlp.mlpZeroGradient shape))
                  }
          (trained, metrics) <-
            expectRight =<< Regression.trainRegressorWithDevice device config training
          Regression.regressionInitialParams metrics @?= expectedInitial
          Regression.trainedRegressorParams trained @?= expectedInitial
          Regression.trainedRegressorConfig trained @?= config
          Regression.regressionOptimizerUpdatesExecuted metrics @?= 550
          actualBatches <- reverse <$> readIORef gradients
          length actualBatches @?= 550
          map length actualBatches @?= concat (replicate 10 (replicate 54 128 <> [88]))
          let expectedExamples =
                concatMap
                  (\epoch -> Regression.regressionEpochPermutation seed epoch training)
                  [1 .. 10]
              expectedPairs =
                [ (Regression.regressionFeatures example, VU.singleton (negate (Regression.regressionTarget example)))
                | example <- expectedExamples
                ]
          concat actualBatches @?= expectedPairs
          actualForwards <- reverse <$> readIORef forwards
          take 550 actualForwards @?= map (map fst) actualBatches
          drop 550 actualForwards @?= [map Regression.regressionFeatures training]
          _ <- expectRight =<< Regression.meanSquaredErrorWithDevice device trained heldOut
          closingForwards <- reverse <$> readIORef forwards
          drop 551 closingForwards @?= [map Regression.regressionFeatures heldOut]
          readIORef gradients >>= (@?= 550) . length
    ]

shuffleRoot :: Int -> Rng.SplitMixSeed
shuffleRoot seed =
  Rng.deriveSplitMixSeed (Rng.SplitMixSeed (fromIntegral seed)) 0x7265672d6f726431

fixtureRow :: Int -> Regression.RegressionExample
fixtureRow index =
  let value = fromIntegral index
   in Regression.RegressionExample
        (VU.fromList [value, value + 1, value * 2, value - 3, value + 4, value * 3, value - 6, value + 7])
        (value * 7 + 0.25)

expectRight :: (Show problem) => Either problem value -> IO value
expectRight = either (\problem -> assertFailure (show problem) >> fail "unreachable fixture failure") pure

-- Literal vectors from an independent unsigned64 closed-form reference over
-- synthetic indices0..15, not from the production permutation implementation.
-- Full roots, epoch seeds and keys are retained as ordinary review DATA:
-- .build/phase278-current/reviews/regression-training-order-independent-synthetic-vectors-20261025.json
-- SHA256 8d2a472dc8a1d1e75c2e24c33723a08e9fe3765088910905e9f3d66e951544f5

goldenSeedRoots :: [(Int, Word64)]
goldenSeedRoots =
  [ (1011, 0x214875b492d58a17)
  , (1012, 0x85b6871e4d415b24)
  , (1013, 0xae40a209643b13b1)
  , (1014, 0xc0fc8e607f860163)
  , (1015, 0x1d6313bcd214d893)
  ]

goldenEpochSeeds :: [(Int, Int, Word64)]
goldenEpochSeeds =
  [ (1011, 1, 0xdf80a0bd4cd93503)
  , (1011, 2, 0x117cc81e2e8d8fdd)
  , (1011, 10, 0xf11767a23819ae17)
  , (1012, 1, 0x3b17b7bf837b3eb8)
  , (1012, 2, 0x682272fae3956793)
  , (1012, 10, 0x9b4c9798eacca175)
  , (1013, 1, 0xc54d0d9625294551)
  , (1013, 2, 0xbb64e21ee76fa488)
  , (1013, 10, 0xe50da64bb2575aec)
  , (1014, 1, 0x27c65ee481ec1ee1)
  , (1014, 2, 0xbd8a89e2a62fef1c)
  , (1014, 10, 0x7980f9cb4b78f045)
  , (1015, 1, 0x58f656ed2fac0df5)
  , (1015, 2, 0x90a91abf0425599c)
  , (1015, 10, 0xa566dedc5a5d6a48)
  ]

goldenEpochOrders :: [(Int, Int, [Int])]
goldenEpochOrders =
  [ (1011, 1, [10, 7, 1, 15, 12, 3, 11, 6, 2, 9, 14, 0, 4, 5, 13, 8])
  , (1011, 2, [0, 15, 6, 8, 1, 14, 9, 3, 13, 12, 11, 2, 10, 5, 7, 4])
  , (1011, 3, [5, 12, 13, 8, 2, 3, 11, 15, 0, 1, 10, 9, 4, 6, 7, 14])
  , (1011, 4, [5, 0, 4, 1, 9, 6, 8, 14, 12, 3, 11, 7, 10, 15, 2, 13])
  , (1011, 5, [0, 1, 10, 13, 4, 12, 14, 3, 9, 7, 5, 6, 2, 11, 8, 15])
  , (1011, 6, [12, 11, 9, 4, 15, 14, 0, 5, 7, 1, 10, 3, 2, 6, 8, 13])
  , (1011, 7, [9, 10, 1, 5, 14, 11, 12, 8, 3, 7, 0, 4, 15, 13, 2, 6])
  , (1011, 8, [15, 5, 3, 2, 1, 0, 9, 4, 14, 7, 11, 12, 6, 8, 10, 13])
  , (1011, 9, [5, 12, 6, 14, 1, 3, 0, 9, 13, 10, 7, 11, 8, 4, 2, 15])
  , (1011, 10, [1, 14, 12, 6, 13, 3, 4, 9, 0, 11, 10, 15, 2, 5, 8, 7])
  , (1012, 1, [7, 11, 1, 3, 8, 0, 4, 12, 15, 9, 10, 13, 5, 6, 14, 2])
  , (1012, 2, [13, 9, 15, 0, 5, 3, 7, 11, 10, 2, 12, 14, 1, 8, 4, 6])
  , (1012, 3, [15, 9, 11, 0, 1, 10, 2, 3, 4, 14, 6, 5, 12, 8, 13, 7])
  , (1012, 4, [12, 7, 6, 13, 4, 10, 14, 8, 0, 5, 15, 3, 2, 9, 1, 11])
  , (1012, 5, [0, 2, 4, 10, 9, 11, 1, 7, 12, 13, 5, 8, 15, 3, 14, 6])
  , (1012, 6, [13, 10, 15, 8, 4, 5, 6, 11, 3, 0, 7, 12, 1, 14, 9, 2])
  , (1012, 7, [0, 14, 4, 5, 7, 9, 15, 11, 6, 1, 10, 2, 13, 3, 8, 12])
  , (1012, 8, [14, 1, 12, 8, 10, 4, 2, 11, 3, 5, 7, 9, 6, 15, 13, 0])
  , (1012, 9, [0, 6, 13, 3, 2, 1, 7, 9, 12, 11, 4, 8, 10, 15, 14, 5])
  , (1012, 10, [13, 1, 3, 15, 9, 12, 10, 4, 14, 6, 7, 8, 2, 11, 5, 0])
  , (1013, 1, [7, 13, 5, 11, 14, 6, 15, 1, 10, 4, 8, 9, 3, 0, 12, 2])
  , (1013, 2, [9, 2, 10, 14, 7, 6, 8, 11, 5, 3, 4, 0, 12, 15, 13, 1])
  , (1013, 3, [11, 1, 15, 9, 7, 13, 3, 5, 2, 8, 10, 6, 4, 12, 14, 0])
  , (1013, 4, [12, 4, 5, 2, 0, 14, 6, 13, 8, 3, 15, 1, 9, 7, 10, 11])
  , (1013, 5, [4, 1, 5, 7, 11, 0, 12, 8, 2, 9, 6, 10, 3, 15, 14, 13])
  , (1013, 6, [1, 9, 6, 11, 13, 8, 4, 3, 2, 7, 0, 10, 12, 5, 14, 15])
  , (1013, 7, [14, 7, 3, 5, 11, 6, 12, 0, 9, 2, 4, 8, 1, 15, 10, 13])
  , (1013, 8, [11, 10, 8, 15, 4, 6, 14, 9, 12, 3, 1, 7, 13, 2, 5, 0])
  , (1013, 9, [4, 1, 7, 0, 3, 13, 12, 8, 14, 10, 11, 6, 5, 9, 15, 2])
  , (1013, 10, [9, 10, 14, 8, 13, 6, 4, 1, 15, 5, 7, 12, 0, 2, 3, 11])
  , (1014, 1, [0, 10, 6, 9, 1, 4, 14, 11, 2, 13, 15, 8, 3, 5, 7, 12])
  , (1014, 2, [9, 2, 11, 3, 13, 5, 0, 1, 12, 8, 7, 14, 4, 15, 10, 6])
  , (1014, 3, [5, 13, 9, 8, 12, 11, 14, 3, 1, 10, 0, 15, 2, 4, 7, 6])
  , (1014, 4, [9, 11, 0, 15, 1, 13, 4, 5, 8, 3, 10, 6, 2, 7, 14, 12])
  , (1014, 5, [8, 1, 9, 7, 0, 2, 10, 3, 12, 4, 14, 13, 11, 5, 6, 15])
  , (1014, 6, [15, 14, 9, 12, 7, 8, 0, 13, 10, 3, 1, 2, 5, 6, 11, 4])
  , (1014, 7, [9, 0, 2, 5, 4, 8, 10, 15, 7, 13, 11, 14, 3, 1, 12, 6])
  , (1014, 8, [7, 0, 9, 1, 12, 4, 13, 2, 15, 3, 10, 5, 6, 14, 8, 11])
  , (1014, 9, [14, 11, 4, 3, 5, 8, 10, 12, 15, 1, 7, 0, 13, 9, 2, 6])
  , (1014, 10, [9, 7, 3, 2, 15, 4, 11, 10, 13, 12, 0, 5, 6, 8, 14, 1])
  , (1015, 1, [8, 4, 10, 13, 7, 3, 15, 12, 0, 11, 1, 6, 14, 2, 9, 5])
  , (1015, 2, [9, 11, 0, 7, 4, 3, 6, 10, 5, 2, 14, 8, 12, 13, 1, 15])
  , (1015, 3, [4, 10, 3, 0, 12, 2, 13, 8, 1, 7, 9, 11, 15, 6, 14, 5])
  , (1015, 4, [1, 14, 9, 2, 7, 0, 8, 13, 15, 6, 10, 12, 3, 11, 5, 4])
  , (1015, 5, [14, 6, 11, 12, 1, 8, 4, 10, 7, 5, 15, 9, 13, 3, 0, 2])
  , (1015, 6, [0, 5, 12, 14, 8, 7, 10, 15, 13, 6, 3, 1, 2, 9, 11, 4])
  , (1015, 7, [4, 6, 13, 8, 2, 14, 9, 15, 3, 5, 1, 10, 7, 12, 11, 0])
  , (1015, 8, [9, 13, 12, 2, 6, 8, 7, 15, 0, 3, 10, 11, 4, 1, 5, 14])
  , (1015, 9, [11, 9, 12, 7, 0, 4, 14, 15, 1, 5, 3, 10, 13, 8, 6, 2])
  , (1015, 10, [10, 11, 13, 9, 14, 7, 0, 8, 15, 4, 1, 5, 3, 12, 2, 6])
  ]

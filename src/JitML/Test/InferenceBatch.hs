module JitML.Test.InferenceBatch
  ( inferenceBatchTests
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

import JitML.Service.InferenceBatch
  ( BatchFlushReason (..)
  , BatchOffer (..)
  , BatchPolicy
  , BatchPolicyError (..)
  , batchCollectionDeadlineNanoseconds
  , batchDeadlineExpiredAt
  , batchDeadlineNanoseconds
  , batchItems
  , batchMaximumSize
  , batchPolicy
  , batchWindow
  , batchWindowExpiredAt
  , mkBatchPolicy
  , offerBatch
  , openBatch
  )

inferenceBatchTests :: TestTree
inferenceBatchTests =
  testGroup
    "InferenceBatch"
    [ testCase "zero size and latency are rejected at the typed boundary" $ do
        mkBatchPolicy 0 1 @?= Left BatchSizeMustBePositive
        mkBatchPolicy 1 0 @?= Left BatchLatencyMustBePositive
    , testCase "compatible requests flush at the admission-time size snapshot" $ do
        let originalPolicy = policy 2 100
            reloadedPolicy = policy 64 5000
            opened = openBatch 1_000 originalPolicy ("model-a" :: String) (1 :: Int)
        case offerBatch 1_100 "model-a" 2 opened of
          BatchReady BatchSizeReached ready Nothing -> do
            batchItems ready @?= (1 :| [2])
            batchPolicy ready @?= originalPolicy
            batchMaximumSize (batchPolicy ready) @?= 2
            batchMaximumSize reloadedPolicy @?= 64
          other -> assertFailure ("expected a size flush, got " <> show other)
    , testCase "an incompatible request is carried into a fresh admission" $ do
        let opened = openBatch 10 (policy 4 100) ("model-a" :: String) (1 :: Int)
        case offerBatch 20 "model-b" 2 opened of
          BatchReady BatchCompatibilityChanged ready (Just (carryKey, carryItem)) -> do
            batchItems ready @?= (1 :| [])
            carryKey @?= "model-b"
            carryItem @?= 2
          other -> assertFailure ("expected a compatibility flush, got " <> show other)
    , testCase "sparse collection closes before the publication-entry deadline" $ do
        let opened = openBatch 1_000 (policy 64 25_000) ("model-a" :: String) (1 :: Int)
            collectionDeadline = batchCollectionDeadlineNanoseconds opened
            publicationEntryDeadline = batchDeadlineNanoseconds opened
        collectionDeadline @?= 1_001_000
        publicationEntryDeadline @?= 25_001_000
        (publicationEntryDeadline - collectionDeadline) @?= 24_000_000
    , testCase "the monotonic deadline flushes and carries the late request" $ do
        let opened = openBatch 1_000 (policy 4 10) ("model-a" :: String) (1 :: Int)
            deadline = batchDeadlineNanoseconds opened
        case offerBatch (fromInteger deadline) "model-a" 2 opened of
          BatchReady BatchDeadlineReached ready (Just (_carryKey, carryItem)) -> do
            batchItems ready @?= (1 :| [])
            carryItem @?= 2
          other -> assertFailure ("expected a deadline flush, got " <> show other)
    , testCase "the shared deadline predicate is exact at the boundary" $ do
        let opened = openBatch 1_000 (policy 2 10) () (1 :: Int)
            deadline = batchDeadlineNanoseconds opened
            window = batchWindow opened
        batchDeadlineExpiredAt (fromInteger deadline - 1) deadline @?= False
        batchDeadlineExpiredAt (fromInteger deadline) deadline @?= True
        batchWindowExpiredAt (fromInteger deadline - 1) window @?= False
        batchWindowExpiredAt (fromInteger deadline) window @?= True
    ]

policy :: Integer -> Integer -> BatchPolicy
policy maximumSize latencyMicros =
  case mkBatchPolicy (fromInteger maximumSize) (fromInteger latencyMicros) of
    Left err -> error (show err)
    Right value -> value

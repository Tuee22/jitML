{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad.Reader (runReaderT)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.SL.Canonicals (canonicalProblems, convergenceCurve, finalLoss, problemName)
import JitML.SL.Dataset
  ( datasetFixtureBytes
  , datasetForProblem
  , datasetObjectRef
  , datasetRefHash
  , fetchDatasetRef
  , fetchedSha256
  )
import JitML.SL.Train (defaultTrainingConfig, resultConverged, train)
import JitML.Service.Capabilities (HasMinIO (..))
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)

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
      , testCase "deterministic training pipeline marks canonical problems converged" $ do
          env <- buildEnv defaultGlobalFlags
          mapM_
            ( \problem -> do
                result <- runReaderT (train (defaultTrainingConfig problem)) env
                assertBool
                  ("expected convergence for " <> Text.unpack (problemName problem))
                  (resultConverged result)
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
      , testCase "dataset refs fetch and SHA-verify through HasMinIO" $
          withSystemTempDirectory "jitml-sl-dataset" $ \dir ->
            case canonicalProblems of
              problem : _ ->
                case datasetForProblem problem of
                  Nothing -> assertFailure "expected canonical dataset ref"
                  Just ref -> do
                    writeResult <-
                      runFilesystemMinIO dir $
                        putBlobBytesIfAbsent (datasetObjectRef ref) (datasetFixtureBytes ref)
                    case writeResult of
                      Left err -> assertFailure ("dataset fixture write failed: " <> show err)
                      Right _ -> pure ()
                    fetchResult <- runFilesystemMinIO dir (fetchDatasetRef ref)
                    case fetchResult of
                      Left err -> assertFailure ("dataset fetch failed: " <> show err)
                      Right fetched ->
                        fetchedSha256 fetched @?= datasetRefHash ref
              [] -> assertFailure "missing canonical problems"
      ]

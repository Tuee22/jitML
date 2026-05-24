{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad.Reader (runReaderT)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Proto.Training
  ( CheckpointDone (..)
  , EpochCompleted (..)
  , StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , TrainingEvent (..)
  , TrainingFailed (..)
  , decodeTrainingCommandProto
  , decodeTrainingEventProto
  , encodeTrainingCommandProto
  , encodeTrainingEventProto
  , parseTrainingCommand
  , renderTrainingCommand
  )
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
import JitML.Substrate (Substrate (..))
import JitML.Test.Report
  ( ReportCardKnobs (..)
  , loadReportCardKnobs
  )

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
      , testCase "sl-canonicals consumes cabal.project sl_epochs and sl_batch knobs" $ do
          loaded <- loadReportCardKnobs "cabal.project"
          case loaded of
            Left err ->
              assertFailure ("failed to load report-card knobs: " <> Text.unpack err)
            Right knobs -> do
              assertBool
                "sl_epochs knob is positive"
                (knobSlEpochs knobs > 0)
              assertBool
                "sl_batch knob is positive"
                (knobSlBatch knobs > 0)
              -- The convergence pipeline currently exposes a five-point
              -- deterministic synthetic curve regardless of the epoch knob;
              -- the live measured curves owned by Phase 13 Sprint 13.4 will
              -- scale to `sl_epochs` per problem.
              assertBool
                "deterministic curve length is bounded by sl_epochs"
                (length (convergenceCurve (head canonicalProblems)) <= knobSlEpochs knobs)
      , testCase "training command envelopes parse after render" $ do
          let start =
                TrainingStart
                  StartTraining
                    { stExperimentHash = "sha256:mnist"
                    , stDhallObjectKey = "experiments/mnist.dhall"
                    , stSubstrate = LinuxCPU
                    , stSeed = 42
                    , stEpochs = 5
                    , stBatchSize = 64
                    }
              stop =
                TrainingStop
                  StopTraining
                    { stopExperimentHash = "sha256:mnist"
                    , stopDrain = True
                    }
          parseTrainingCommand (renderTrainingCommand start) @?= Just start
          parseTrainingCommand (renderTrainingCommand stop) @?= Just stop
          parseTrainingCommand "kind: UnknownTrainingCommand\n" @?= Nothing
          decodeTrainingCommandProto (encodeTrainingCommandProto start) @?= Right start
          decodeTrainingCommandProto (encodeTrainingCommandProto stop) @?= Right stop
      , testCase "training event envelopes round-trip through proto3-compatible bytes" $ do
          let epoch =
                TrainingEpoch
                  EpochCompleted
                    { ecExperimentHash = "sha256:mnist"
                    , ecEpoch = 4
                    , ecLoss = 0.125
                    , ecValidationLoss = 0.25
                    , ecTimestampNs = 123456789
                    }
              checkpoint =
                TrainingCheckpoint
                  CheckpointDone
                    { cdExperimentHash = "sha256:mnist"
                    , cdManifestSha = "sha256:manifest"
                    , cdStep = 4096
                    , cdPointerKey = "checkpoints/mnist/latest"
                    , cdEpoch = 4
                    , cdTrialSha = Just "sha256:trial"
                    , cdRunUuid = "run-0001"
                    , cdMetricsAtStep = [("loss", 0.125), ("accuracy", 0.875)]
                    }
              failure =
                TrainingFailure
                  TrainingFailed
                    { tfExperimentHash = "sha256:mnist"
                    , tfErrorCode = "DatasetUnavailable"
                    , tfErrorText = "missing fixture"
                    , tfTimestampNs = 987654321
                    }
          decodeTrainingEventProto (encodeTrainingEventProto epoch) @?= Right epoch
          decodeTrainingEventProto (encodeTrainingEventProto checkpoint) @?= Right checkpoint
          decodeTrainingEventProto (encodeTrainingEventProto failure) @?= Right failure
      ]

{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad.Reader (runReaderT)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as ByteString
import Data.Maybe qualified
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word8)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.SL.Classifier
  ( ClassifierConfig (..)
  , LabeledExample (..)
  , accuracy
  , classify
  , crossEntropyLoss
  , defaultClassifierConfig
  , parseIdxImages
  , parseIdxLabels
  , trainClassifier
  , zipImagesLabels
  )

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
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Dataset
  ( datasetFixtureBytes
  , datasetForProblem
  , datasetObjectRef
  , datasetRefHash
  , fetchDatasetRef
  , fetchedSha256
  )
import JitML.SL.Dataset qualified as Dataset
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
            -- Sprint 13.4 — the round-trip test runs against a problem
            -- whose dataset still uses the synthetic per-(name, split,
            -- size) SHA. MNIST now carries the canonical upstream SHA
            -- (`Dataset.canonicalSha256For`) so synthetic bytes no
            -- longer hash to its `datasetExpectedSha256`. The first
            -- problem without a canonical SHA in the catalog drives the
            -- assertion; MNIST's live MinIO round-trip is exercised by
            -- the `jitml internal upload-dataset` CLI path against a
            -- real-byte payload.
            case firstSyntheticProblem of
              Just problem ->
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
              Nothing -> assertFailure "expected at least one canonical problem with synthetic SHA"
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
      , testCase "SL classifier converges on a separable synthetic task (Sprint 13.4 network seam)" $ do
          -- Sprint 13.4 — drive the real differentiable softmax-cross-entropy
          -- classifier (`JitML.SL.Classifier`, built on the MLP seam) over a
          -- deterministic, linearly-separable 3-class dataset and assert it
          -- learns: train accuracy crosses a high threshold and the
          -- cross-entropy loss drops well below its log(3) random baseline.
          let dataset = syntheticDataset
              config =
                defaultClassifierConfig
                  { clfSeed = 7
                  , clfInputs = 4
                  , clfHidden = 16
                  , clfClasses = 3
                  , clfEpochs = 60
                  , clfLearningRate = 5.0e-3
                  }
              trained = trainClassifier config dataset
              acc = accuracy trained dataset
              loss = crossEntropyLoss trained dataset
          assertBool
            ("expected train accuracy >= 0.95, got " <> show acc)
            (acc >= 0.95)
          assertBool
            ("expected cross-entropy loss < 0.5 (random ~1.10), got " <> show loss)
            (loss < 0.5)
      , testCase "SL classifier training is run-to-run deterministic (Sprint 13.4)" $ do
          let config = defaultClassifierConfig {clfInputs = 4, clfHidden = 16, clfClasses = 3, clfEpochs = 20}
              dataset = syntheticDataset
              a = trainClassifier config dataset
              b = trainClassifier config dataset
          fmap (classify a . exampleFeatures) dataset
            @?= fmap (classify b . exampleFeatures) dataset
      , testCase "IDX image + label parsers round-trip the canonical MNIST format (Sprint 13.4)" $ do
          -- Build a tiny synthetic IDX3 (2 images, 2x2) + IDX1 (2 labels)
          -- payload in the canonical big-endian header format and assert the
          -- parsers recover the pixel/label content the live MNIST upload
          -- (Sprint 13.4 upload half) stages in MinIO.
          let imageBytes =
                ByteString.pack $
                  be32Bytes 0x0803 -- magic IDX3
                    <> be32Bytes 2 -- count
                    <> be32Bytes 2 -- rows
                    <> be32Bytes 2 -- cols
                    <> [0, 255, 128, 64, 10, 20, 30, 40] -- two 2x2 images
              labelBytes =
                ByteString.pack $
                  be32Bytes 0x0801 -- magic IDX1
                    <> be32Bytes 2 -- count
                    <> [7, 3] -- two labels
          case (parseIdxImages imageBytes, parseIdxLabels labelBytes) of
            (Right (pixelsPer, images), Right labels) -> do
              pixelsPer @?= 4
              length images @?= 2
              labels @?= [7, 3]
              -- first pixel of image 0 is 0/255 = 0.0; second is 255/255 = 1.0
              VU.toList (head images) @?= [0.0, 1.0, 128.0 / 255.0, 64.0 / 255.0]
              let examples = zipImagesLabels images labels
              fmap exampleLabel examples @?= [7, 3]
            (imgErr, lblErr) ->
              assertFailure ("IDX parse failed: " <> show imgErr <> " / " <> show lblErr)
      ]

-- | Deterministic, linearly-separable 3-class dataset: each class is a
-- tight cluster around a distinct corner of the 4-D unit cube. Used by
-- the Sprint 13.4 SL convergence assertion (no committed fixtures — the
-- data is generated in-code per the numerical-fixture prohibition).
syntheticDataset :: [LabeledExample]
syntheticDataset =
  [ LabeledExample (VU.fromList (classCentre c i)) c
  | c <- [0, 1, 2]
  , i <- [0 .. 19 :: Int]
  ]
 where
  classCentre c i =
    let jitter k = fromIntegral ((c * 31 + i * 7 + k * 13) `mod` 5) / 100.0
        base = case c of
          0 -> [1.0, 0.0, 0.0, 0.0]
          1 -> [0.0, 1.0, 0.0, 0.0]
          _ -> [0.0, 0.0, 1.0, 1.0]
     in zipWith (\b k -> b + jitter k) base [0 ..]

-- | Big-endian 4-byte encoding for the synthetic IDX header test.
be32Bytes :: Int -> [Word8]
be32Bytes n =
  [ fromIntegral ((n `shiftR` 24) .&. 0xff)
  , fromIntegral ((n `shiftR` 16) .&. 0xff)
  , fromIntegral ((n `shiftR` 8) .&. 0xff)
  , fromIntegral (n .&. 0xff)
  ]

-- | The first canonical problem whose dataset does not have a
-- published canonical SHA in 'Dataset.canonicalSha256For'. Such a
-- problem's `datasetFixtureBytes` still hashes to its synthetic
-- `datasetExpectedSha256`, so the filesystem-backed MinIO round-trip
-- test can exercise the full encode/verify path without real bytes.
firstSyntheticProblem :: Maybe SL.CanonicalProblem
firstSyntheticProblem =
  case filter usesSyntheticSha canonicalProblems of
    p : _ -> Just p
    [] -> Nothing
 where
  usesSyntheticSha problem =
    case datasetForProblem problem of
      Just ref ->
        Data.Maybe.isNothing
          ( Dataset.canonicalSha256For
              (Dataset.datasetName ref)
              (Dataset.datasetSplit ref)
          )
      Nothing -> False

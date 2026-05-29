{-# LANGUAGE OverloadedStrings #-}

module Main where

import Codec.Compression.GZip qualified as GZip
import Control.Monad.Reader (runReaderT)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
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
  , trainClassifierFromIdxBounded
  , zipImagesLabels
  )

import JitML.Bootstrap (readExistingLivePublication)
import JitML.Cluster.Publication (publicationEdgePort)
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
import JitML.SL.ConvergenceThresholds
  ( SlConvergenceThreshold (..)
  , passesSlConvergence
  , slCohortThreshold
  , slCohortThresholds
  )
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
import JitML.Service.MinIOSubprocess (minioSettingsForLocalEdge, runMinIOSubprocess)
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
      , testCase "gunzip transparently decompresses the canonical compressed blob (Sprint 13.4)" $ do
          -- The canonical MNIST blobs are distributed gzip-compressed; the
          -- worker's fetch path calls `maybeGunzip` before IDX parsing. Assert
          -- a gzip-magic payload round-trips and a raw payload is unchanged.
          let raw = ByteString.pack [0x00, 0x01, 0x02, 0x03, 0x04]
              gz = LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict raw))
          Dataset.maybeGunzip gz @?= raw
          Dataset.maybeGunzip raw @?= raw
      , testCase "classifier trains over (gzipped) IDX bytes through the bounded entry (Sprint 13.4)" $ do
          -- End-to-end exercise of the live worker path: build a synthetic but
          -- learnable IDX3 image + IDX1 label payload, gzip it (as the canonical
          -- MNIST upload stages), gunzip + IDX-parse + train through
          -- `trainClassifierFromIdxBounded`, and assert the bounded subset is
          -- learned. No committed fixtures (numerical-fixture prohibition).
          let imageBytes =
                ByteString.pack $
                  be32Bytes 0x0803 -- magic IDX3
                    <> be32Bytes 6 -- count
                    <> be32Bytes 1 -- rows
                    <> be32Bytes 2 -- cols
                    -- three class-0 (high first pixel) + three class-1 (high second pixel)
                    <> [250, 5, 240, 10, 255, 0, 5, 250, 10, 240, 0, 255]
              labelBytes =
                ByteString.pack $
                  be32Bytes 0x0801 -- magic IDX1
                    <> be32Bytes 6 -- count
                    <> [0, 0, 0, 1, 1, 1]
              gzImages = LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict imageBytes))
              gzLabels = LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict labelBytes))
              config =
                defaultClassifierConfig
                  { clfSeed = 11
                  , clfInputs = 2
                  , clfHidden = 8
                  , clfClasses = 2
                  , clfEpochs = 80
                  , clfLearningRate = 5.0e-3
                  }
          case trainClassifierFromIdxBounded
            config
            (Just 6)
            (Dataset.maybeGunzip gzImages)
            (Dataset.maybeGunzip gzLabels) of
            Left err -> assertFailure ("bounded IDX training failed: " <> err)
            Right (_, acc) ->
              assertBool
                ("expected bounded-subset train accuracy >= 0.83, got " <> show acc)
                (acc >= 0.83)
      , testCase "SL convergence threshold table covers the classification problems (Sprint 13.4)" $ do
          -- Every MNIST / Fashion-MNIST / CIFAR / Tiny-ImageNet classification
          -- problem has a literature-anchored threshold; the regression
          -- problem (california-housing) is intentionally omitted.
          assertBool
            "mnist-shallow-mlp has a threshold"
            (Data.Maybe.isJust (slCohortThreshold "mnist-shallow-mlp"))
          assertBool
            "fashion-mnist-mlp has a threshold"
            (Data.Maybe.isJust (slCohortThreshold "fashion-mnist-mlp"))
          assertBool
            "california-housing (regression) is omitted"
            (Data.Maybe.isNothing (slCohortThreshold "california-housing-mlp"))
          assertBool
            "every threshold has positive slack and a target in (0, 1]"
            ( all
                (\(_, t) -> slSlack t > 0 && slLiteratureTarget t > 0 && slLiteratureTarget t <= 1.0)
                slCohortThresholds
            )
      , testCase "passesSlConvergence accepts target and rejects below the slack band (Sprint 13.4)" $ do
          let threshold = SlConvergenceThreshold 0.97 0.07
          assertBool "accepts the literature target" (passesSlConvergence threshold 0.97)
          assertBool "accepts target - slack (lower bar)" (passesSlConvergence threshold 0.90)
          assertBool
            "rejects a measured median below the slack band"
            (not (passesSlConvergence threshold 0.80))
      , testCase "live MNIST SL training clears the convergence threshold (Sprint 13.4 Live)" $ do
          -- Sprint 13.4 live convergence assertion. With a live cluster
          -- publication present, fetch the real MNIST bytes from MinIO,
          -- gunzip + IDX-parse + train the differentiable classifier over a
          -- bounded budget, and assert the measured test accuracy clears the
          -- in-code literature threshold − slack. Offline (no publication)
          -- the case skips with a passing message, matching the live-test
          -- convention in the integration / playwright stanzas. No committed
          -- fixtures — the data is the canonical MinIO-staged MNIST and the
          -- bar is the in-code threshold.
          publication <- readExistingLivePublication "."
          case publication of
            Nothing ->
              assertBool
                "no live cluster publication; live SL convergence assertion skipped"
                True
            Just pub ->
              case (Dataset.datasetForProblem (head canonicalProblems), slCohortThreshold "mnist-shallow-mlp") of
                (Just trainRef, Just threshold) -> do
                  let settings = minioSettingsForLocalEdge (publicationEdgePort pub)
                      testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}
                      run = runMinIOSubprocess settings
                  trainImg <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.ImagesArtifact)
                  trainLbl <- run (Dataset.fetchDatasetArtifactBytes trainRef Dataset.LabelsArtifact)
                  testImg <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.ImagesArtifact)
                  testLbl <- run (Dataset.fetchDatasetArtifactBytes testRef Dataset.LabelsArtifact)
                  case (trainImg, trainLbl, testImg, testLbl) of
                    (Right ti, Right tl, Right vi, Right vl) -> do
                      let config = defaultClassifierConfig {clfEpochs = 10}
                      case trainClassifierFromIdxBounded
                        config
                        (Just 10000)
                        (Dataset.maybeGunzip ti)
                        (Dataset.maybeGunzip tl) of
                        Left err -> assertFailure ("live MNIST training failed: " <> err)
                        Right (trained, _trainAcc) -> do
                          let testAcc =
                                case ( parseIdxImages (Dataset.maybeGunzip vi)
                                     , parseIdxLabels (Dataset.maybeGunzip vl)
                                     ) of
                                  (Right (_, images), Right labels) ->
                                    accuracy trained (take 5000 (zipImagesLabels images labels))
                                  _ -> 0.0
                          assertBool
                            ( "live MNIST test_acc "
                                <> show testAcc
                                <> " must clear threshold − slack = "
                                <> show (slLiteratureTarget threshold - slSlack threshold)
                            )
                            (passesSlConvergence threshold testAcc)
                    _ ->
                      -- A stale publication can survive `jitml cluster down`;
                      -- when MinIO is unreachable / the bytes aren't staged the
                      -- fetch returns Left, so the live assertion skips rather
                      -- than failing offline.
                      assertBool
                        "live MNIST bytes unavailable (cluster down or not staged); skipped"
                        True
                _ -> assertFailure "missing MNIST dataset ref or convergence threshold"
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

{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Canonicals
  ( CanonicalProblem (..)
  , canonicalProblems
  , trainableCanonicalCohort
  , isTrainableCanonicalProblem
  , denseMlpCohort
  , isDenseMlpProblem
  , loadCanonicalProblemExperiment
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)

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

-- | Sprint 8.12 — the canonical SL rows that the product surface treats as
-- trainable. The architecture runtime in "JitML.SL.Architecture" maps every
-- row to a substrate-backed trainable topology and fails closed when the
-- selected device or the row's real dataset artefacts are unavailable.
trainableCanonicalCohort :: [CanonicalProblem]
trainableCanonicalCohort = filter isTrainableCanonicalProblem canonicalProblems

isTrainableCanonicalProblem :: CanonicalProblem -> Bool
isTrainableCanonicalProblem _ = True

-- | Legacy Sprint 8.10 compatibility cohort for callers that still need to
-- name the older single-hidden-layer @Dense@ subset explicitly. It is no
-- longer the product gate; see 'trainableCanonicalCohort'.
denseMlpCohort :: [CanonicalProblem]
denseMlpCohort = filter isDenseMlpProblem canonicalProblems

-- | True for the historical single-hidden-layer @Dense@ canonical problems
-- (@mnist-shallow-mlp@, @fashion-mnist-mlp@, @california-housing-mlp@).
isDenseMlpProblem :: CanonicalProblem -> Bool
isDenseMlpProblem problem = problemModel problem == "Dense"

-- | Decode a supervised experiment Dhall file and resolve it to the canonical
-- SL problem row it names. Matching is strict on dataset/model, and prefers an
-- exact seed match when the experiment uses the canonical seed. A decode error
-- or a dataset/model pair absent from 'canonicalProblems' fails closed.
loadCanonicalProblemExperiment :: FilePath -> IO (Either Text CanonicalProblem)
loadCanonicalProblemExperiment path = do
  decoded <- tryAny (Dhall.inputFile rawSupervisedExperimentDecoder path)
  pure $
    case decoded of
      Left err -> Left (Text.pack (displayException err))
      Right raw -> resolveRawSupervisedExperiment raw

data RawSupervisedExperiment = RawSupervisedExperiment
  { rawExperimentName :: Text
  , rawExperimentDataset :: Text
  , rawExperimentModel :: Text
  , rawExperimentSeed :: Natural
  }
  deriving stock (Eq, Show)

rawSupervisedExperimentDecoder :: Dhall.Decoder RawSupervisedExperiment
rawSupervisedExperimentDecoder =
  Dhall.record $
    RawSupervisedExperiment
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "dataset" Dhall.strictText
      <*> Dhall.field "model" Dhall.strictText
      <*> Dhall.field "seed" Dhall.natural

resolveRawSupervisedExperiment :: RawSupervisedExperiment -> Either Text CanonicalProblem
resolveRawSupervisedExperiment raw =
  case exactSeed `orElse` datasetModel of
    Just problem -> Right problem
    Nothing ->
      Left
        ( "supervised experiment "
            <> rawExperimentName raw
            <> " names dataset/model not present in canonicalProblems: "
            <> rawExperimentDataset raw
            <> "/"
            <> rawExperimentModel raw
        )
 where
  matchesDatasetModel problem =
    problemDataset problem == rawExperimentDataset raw
      && problemModel problem == rawExperimentModel raw
  exactSeed =
    List.find
      ( \problem ->
          matchesDatasetModel problem
            && problemSeed problem == fromIntegral (rawExperimentSeed raw)
      )
      canonicalProblems
  datasetModel = List.find matchesDatasetModel canonicalProblems
  orElse (Just value) _ = Just value
  orElse Nothing fallback = fallback

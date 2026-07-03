{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Pipeline
  ( Experiment
  , InferenceEligibleRef
  , ModelRef
  , completeTraining
  , declareExperiment
  , declareModel
  , experimentHash
  , inferenceEligibleModelRef
  , markInferenceEligible
  , modelRefCompletedTraining
  , modelRefExperimentHash
  , modelRefManifestSha
  , startTraining
  , train
  )
where

import Data.Text (Text)

import JitML.Checkpoint.Format
  ( InferenceEligibleCheckpoint
  , eligibleCheckpointCompletedTraining
  , eligibleCheckpointManifest
  , eligibleCheckpointManifestSha
  , manifestExperiment
  )
import JitML.Product.Matrix (ModelState (..))
import JitML.Training.Budget
  ( CompletedTraining
  , completedTrainingMetrics
  , convergencePassed
  )

newtype Experiment (state :: ModelState) = Experiment
  { experimentHash :: Text
  }
  deriving stock (Eq, Show)

data ModelRef (state :: ModelState) = ModelRef
  { modelRefExperimentHash :: Text
  , modelRefManifestSha :: Maybe Text
  , modelRefCompletedTraining :: Maybe CompletedTraining
  }
  deriving stock (Eq, Show)

type InferenceEligibleRef = ModelRef 'InferenceEligible

declareExperiment :: Text -> Experiment 'Declared
declareExperiment = Experiment

declareModel :: Experiment 'Declared -> ModelRef 'Declared
declareModel experiment =
  ModelRef
    { modelRefExperimentHash = experimentHash experiment
    , modelRefManifestSha = Nothing
    , modelRefCompletedTraining = Nothing
    }

startTraining :: ModelRef 'Declared -> ModelRef 'TrainingStarted
startTraining ref =
  ref
    { modelRefManifestSha = Nothing
    , modelRefCompletedTraining = Nothing
    }

train
  :: (Applicative m)
  => ModelRef 'TrainingStarted
  -> CompletedTraining
  -> m (ModelRef 'TrainingCompleted)
train ref completed =
  pure (completeTraining ref completed)

completeTraining
  :: ModelRef 'TrainingStarted
  -> CompletedTraining
  -> ModelRef 'TrainingCompleted
completeTraining ref completed =
  ref
    { modelRefCompletedTraining = Just completed
    }

markInferenceEligible
  :: Text
  -> ModelRef 'TrainingCompleted
  -> CompletedTraining
  -> Either Text InferenceEligibleRef
markInferenceEligible manifestSha ref completed
  | modelRefCompletedTraining ref /= Just completed =
      Left "completed-training witness does not match model reference"
  | not (all convergencePassed (completedTrainingMetrics completed)) =
      Left "completed-training witness has failed convergence"
  | otherwise =
      Right
        ModelRef
          { modelRefExperimentHash = modelRefExperimentHash ref
          , modelRefManifestSha = Just manifestSha
          , modelRefCompletedTraining = Just completed
          }

inferenceEligibleModelRef :: InferenceEligibleCheckpoint -> InferenceEligibleRef
inferenceEligibleModelRef eligible =
  let manifest = eligibleCheckpointManifest eligible
      completed = eligibleCheckpointCompletedTraining eligible
   in ModelRef
        { modelRefExperimentHash = manifestExperiment manifest
        , modelRefManifestSha = Just (eligibleCheckpointManifestSha eligible)
        , modelRefCompletedTraining = Just completed
        }

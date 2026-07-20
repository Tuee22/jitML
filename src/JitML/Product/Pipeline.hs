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

import JitML.Checkpoint.Format (manifestExperiment)
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Product.Matrix (ModelState (..))
import JitML.Training.Budget
  ( CompletedTraining
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
  :: CheckpointStore.AdmittedCompletedCheckpoint
  -> ModelRef 'TrainingCompleted
  -> Either Text InferenceEligibleRef
markInferenceEligible eligible ref
  | modelRefCompletedTraining ref /= Just completed =
      Left "completed-training witness does not match model reference"
  | modelRefExperimentHash ref /= manifestExperiment manifest =
      Left "completed checkpoint does not match model experiment"
  | otherwise =
      Right (inferenceEligibleModelRef eligible)
 where
  admitted = CheckpointStore.admittedCompletedCheckpoint eligible
  manifest = CheckpointStore.admittedCheckpointManifest admitted
  completed = CheckpointStore.admittedCompletedTraining eligible

inferenceEligibleModelRef
  :: CheckpointStore.AdmittedCompletedCheckpoint
  -> InferenceEligibleRef
inferenceEligibleModelRef eligible =
  let admitted = CheckpointStore.admittedCompletedCheckpoint eligible
      manifest = CheckpointStore.admittedCheckpointManifest admitted
      completed = CheckpointStore.admittedCompletedTraining eligible
   in ModelRef
        { modelRefExperimentHash = manifestExperiment manifest
        , modelRefManifestSha =
            Just (CheckpointStore.admittedCheckpointManifestSha admitted)
        , modelRefCompletedTraining = Just completed
        }

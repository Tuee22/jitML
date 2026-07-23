{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

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

-- | A model reference indexed by its lifecycle state.  The constructors are
-- hidden: a 'ModelRef' can only be built through the smart constructors and
-- legal transitions below, and each state carries exactly the evidence that is
-- legal for it — a @'Declared'@/@'TrainingStarted'@ reference structurally
-- cannot carry a manifest SHA or completed-training witness, and only an
-- @'InferenceEligible'@ reference carries the admitted manifest SHA.  Optional
-- @Maybe@ evidence fields no longer exist, so a contradictory state payload is
-- unrepresentable rather than merely rejected at runtime.
data ModelRef (state :: ModelState) where
  DeclaredModelRef :: !Text -> ModelRef 'Declared
  TrainingStartedModelRef :: !Text -> ModelRef 'TrainingStarted
  TrainingCompletedModelRef
    :: !Text -> !CompletedTraining -> ModelRef 'TrainingCompleted
  InferenceEligibleModelRef
    :: !Text -> !Text -> !CompletedTraining -> ModelRef 'InferenceEligible

deriving stock instance Eq (ModelRef state)
deriving stock instance Show (ModelRef state)

type InferenceEligibleRef = ModelRef 'InferenceEligible

-- | The experiment hash is common to every lifecycle state.
modelRefExperimentHash :: ModelRef state -> Text
modelRefExperimentHash ref =
  case ref of
    DeclaredModelRef hash -> hash
    TrainingStartedModelRef hash -> hash
    TrainingCompletedModelRef hash _ -> hash
    InferenceEligibleModelRef hash _ _ -> hash

-- | Only an inference-eligible reference has an admitted manifest SHA.
modelRefManifestSha :: ModelRef state -> Maybe Text
modelRefManifestSha ref =
  case ref of
    InferenceEligibleModelRef _ manifestSha _ -> Just manifestSha
    _ -> Nothing

-- | Only a completed or inference-eligible reference carries the witness.
modelRefCompletedTraining :: ModelRef state -> Maybe CompletedTraining
modelRefCompletedTraining ref =
  case ref of
    TrainingCompletedModelRef _ completed -> Just completed
    InferenceEligibleModelRef _ _ completed -> Just completed
    _ -> Nothing

declareExperiment :: Text -> Experiment 'Declared
declareExperiment = Experiment

declareModel :: Experiment 'Declared -> ModelRef 'Declared
declareModel experiment = DeclaredModelRef (experimentHash experiment)

startTraining :: ModelRef 'Declared -> ModelRef 'TrainingStarted
startTraining (DeclaredModelRef hash) = TrainingStartedModelRef hash

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
completeTraining (TrainingStartedModelRef hash) =
  TrainingCompletedModelRef hash

markInferenceEligible
  :: CheckpointStore.AdmittedCompletedCheckpoint
  -> ModelRef 'TrainingCompleted
  -> Either Text InferenceEligibleRef
markInferenceEligible eligible (TrainingCompletedModelRef hash refCompleted)
  | refCompleted /= completed =
      Left "completed-training witness does not match model reference"
  | hash /= manifestExperiment manifest =
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
  InferenceEligibleModelRef
    (manifestExperiment manifest)
    (CheckpointStore.admittedCheckpointManifestSha admitted)
    completed
 where
  admitted = CheckpointStore.admittedCompletedCheckpoint eligible
  manifest = CheckpointStore.admittedCheckpointManifest admitted
  completed = CheckpointStore.admittedCompletedTraining eligible

{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Training
  ( CheckpointDone (..)
  , EpochCompleted (..)
  , StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , TrainingEvent (..)
  , TrainingFailed (..)
  , renderTrainingCommand
  , renderTrainingEvent
  , trainingCommandTopic
  , trainingEventTopic
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.Substrate (Substrate, renderSubstrate)

data StartTraining = StartTraining
  { stExperimentHash :: Text
  , stDhallObjectKey :: Text
  , stSubstrate :: Substrate
  , stSeed :: Word64
  , stEpochs :: Word32
  , stBatchSize :: Word32
  }
  deriving stock (Eq, Show)

data StopTraining = StopTraining
  { stopExperimentHash :: Text
  , stopDrain :: Bool
  }
  deriving stock (Eq, Show)

data EpochCompleted = EpochCompleted
  { ecExperimentHash :: Text
  , ecEpoch :: Word32
  , ecLoss :: Double
  , ecValidationLoss :: Double
  , ecTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data CheckpointDone = CheckpointDone
  { cdExperimentHash :: Text
  , cdManifestSha :: Text
  , cdStep :: Word64
  , cdPointerKey :: Text
  }
  deriving stock (Eq, Show)

data TrainingFailed = TrainingFailed
  { tfExperimentHash :: Text
  , tfErrorCode :: Text
  , tfErrorText :: Text
  , tfTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data TrainingCommand
  = TrainingStart StartTraining
  | TrainingStop StopTraining
  deriving stock (Eq, Show)

data TrainingEvent
  = TrainingEpoch EpochCompleted
  | TrainingCheckpoint CheckpointDone
  | TrainingFailure TrainingFailed
  deriving stock (Eq, Show)

trainingCommandTopic :: Substrate -> Text
trainingCommandTopic substrate =
  "training.command." <> renderSubstrate substrate

trainingEventTopic :: Substrate -> Text
trainingEventTopic substrate =
  "training.event." <> renderSubstrate substrate

renderTrainingCommand :: TrainingCommand -> Text
renderTrainingCommand command =
  case command of
    TrainingStart envelope ->
      Text.unlines
        [ "kind: StartTraining"
        , "experiment-hash: " <> stExperimentHash envelope
        , "dhall-object-key: " <> stDhallObjectKey envelope
        , "substrate: " <> renderSubstrate (stSubstrate envelope)
        , "seed: " <> Text.pack (show (stSeed envelope))
        , "epochs: " <> Text.pack (show (stEpochs envelope))
        , "batch-size: " <> Text.pack (show (stBatchSize envelope))
        ]
    TrainingStop envelope ->
      Text.unlines
        [ "kind: StopTraining"
        , "experiment-hash: " <> stopExperimentHash envelope
        , "drain: " <> Text.pack (show (stopDrain envelope))
        ]

renderTrainingEvent :: TrainingEvent -> Text
renderTrainingEvent envelope =
  case envelope of
    TrainingEpoch e ->
      Text.unlines
        [ "kind: EpochCompleted"
        , "experiment-hash: " <> ecExperimentHash e
        , "epoch: " <> Text.pack (show (ecEpoch e))
        , "loss: " <> Text.pack (show (ecLoss e))
        , "validation-loss: " <> Text.pack (show (ecValidationLoss e))
        ]
    TrainingCheckpoint c ->
      Text.unlines
        [ "kind: CheckpointDone"
        , "experiment-hash: " <> cdExperimentHash c
        , "manifest-sha: " <> cdManifestSha c
        , "step: " <> Text.pack (show (cdStep c))
        , "pointer-key: " <> cdPointerKey c
        ]
    TrainingFailure f ->
      Text.unlines
        [ "kind: TrainingFailed"
        , "experiment-hash: " <> tfExperimentHash f
        , "error-code: " <> tfErrorCode f
        , "error-text: " <> tfErrorText f
        ]

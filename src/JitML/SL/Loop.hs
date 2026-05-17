{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Loop
  ( EpochOutcome (..)
  , LoopConfig (..)
  , TrainPipeline (..)
  , defaultLoopConfig
  , epochOutcomes
  , runDeterministicLoop
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Framework
  ( TrainingLifecycle (..)
  , TrainingPhase (..)
  )
import JitML.SL.Canonicals (CanonicalProblem (..), convergenceCurve)
import JitML.SL.Dataset (DatasetRef, datasetForProblem)

data LoopConfig = LoopConfig
  { loopEpochs :: Int
  , loopBatchSize :: Int
  , loopCheckpointEvery :: Int
  , loopEvalEvery :: Int
  }
  deriving stock (Eq, Show)

defaultLoopConfig :: LoopConfig
defaultLoopConfig =
  LoopConfig
    { loopEpochs = 5
    , loopBatchSize = 64
    , loopCheckpointEvery = 1
    , loopEvalEvery = 1
    }

data EpochOutcome = EpochOutcome
  { epochIndex :: Int
  , epochPhase :: TrainingPhase
  , epochLoss :: Double
  , epochCheckpointed :: Bool
  }
  deriving stock (Eq, Show)

data TrainPipeline = TrainPipeline
  { pipelineProblem :: CanonicalProblem
  , pipelineDataset :: Maybe DatasetRef
  , pipelineConfig :: LoopConfig
  , pipelineEpochs :: [EpochOutcome]
  , pipelineFinalLoss :: Double
  , pipelinePhases :: [TrainingPhase]
  }
  deriving stock (Eq, Show)

runDeterministicLoop :: CanonicalProblem -> LoopConfig -> TrainPipeline
runDeterministicLoop problem config =
  TrainPipeline
    { pipelineProblem = problem
    , pipelineDataset = datasetForProblem problem
    , pipelineConfig = config
    , pipelineEpochs = outcomes
    , pipelineFinalLoss = case reverse outcomes of
        (last' : _) -> epochLoss last'
        [] -> 0.0
    , pipelinePhases = phasesFor (length outcomes)
    }
 where
  curve = take (loopEpochs config) (convergenceCurve problem ++ repeat (last (convergenceCurve problem)))
  outcomes = epochOutcomes config curve

epochOutcomes :: LoopConfig -> [Double] -> [EpochOutcome]
epochOutcomes config curve =
  [ EpochOutcome
      { epochIndex = ix
      , epochPhase = phaseForEpoch ix
      , epochLoss = loss
      , epochCheckpointed = loopCheckpointEvery config > 0 && ix `mod` loopCheckpointEvery config == 0
      }
  | (ix, loss) <- zip [0 ..] curve
  ]

phasesFor :: Int -> [TrainingPhase]
phasesFor n
  | n <= 0 = []
  | otherwise =
      [TrainingConfigured]
        <> replicate n TrainingCollecting
        <> [TrainingOptimizing, TrainingEvaluating, TrainingCheckpointing]

phaseForEpoch :: Int -> TrainingPhase
phaseForEpoch ix
  | ix == 0 = TrainingConfigured
  | otherwise = TrainingOptimizing

-- | Witness that the in-memory lifecycle matches the GADT singleton sequence.
_lifecycleWitness :: Text
_lifecycleWitness =
  Text.intercalate "->" (fmap singletonName lifecycle)
 where
  lifecycle :: [String]
  lifecycle =
    [ phaseTag STrainingConfigured
    , phaseTag STrainingCollecting
    , phaseTag STrainingOptimizing
    , phaseTag STrainingEvaluating
    , phaseTag STrainingCheckpointing
    ]
  singletonName = Text.pack
  phaseTag :: TrainingLifecycle p -> String
  phaseTag STrainingConfigured = "configured"
  phaseTag STrainingCollecting = "collecting"
  phaseTag STrainingOptimizing = "optimizing"
  phaseTag STrainingEvaluating = "evaluating"
  phaseTag STrainingCheckpointing = "checkpointing"

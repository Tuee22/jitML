{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Train
  ( TrainResult (..)
  , TrainingConfig (..)
  , defaultTrainingConfig
  , renderTrainResult
  , train
  )
where

import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ReaderT)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Env.Env (Env)
import JitML.SL.Canonicals (CanonicalProblem (..))
import JitML.SL.Loop
  ( LoopConfig (..)
  , TrainPipeline (..)
  , defaultLoopConfig
  , runDeterministicLoop
  )

data TrainingConfig = TrainingConfig
  { trainingProblem :: CanonicalProblem
  , trainingLoop :: LoopConfig
  , trainingEnableTensorBoard :: Bool
  }
  deriving stock (Eq, Show)

defaultTrainingConfig :: CanonicalProblem -> TrainingConfig
defaultTrainingConfig problem =
  TrainingConfig
    { trainingProblem = problem
    , trainingLoop = defaultLoopConfig
    , trainingEnableTensorBoard = False
    }

data TrainResult = TrainResult
  { resultProblemName :: Text
  , resultPipeline :: TrainPipeline
  , resultConvergenceThreshold :: Double
  , resultConverged :: Bool
  }
  deriving stock (Eq, Show)

train :: (MonadIO m) => TrainingConfig -> ReaderT Env m TrainResult
train config = pure (trainPure config)

trainPure :: TrainingConfig -> TrainResult
trainPure config =
  let pipeline = runDeterministicLoop (trainingProblem config) (trainingLoop config)
      threshold = convergenceThresholdFor (trainingProblem config)
   in TrainResult
        { resultProblemName = problemName (trainingProblem config)
        , resultPipeline = pipeline
        , resultConvergenceThreshold = threshold
        , resultConverged = pipelineFinalLoss pipeline <= threshold
        }

convergenceThresholdFor :: CanonicalProblem -> Double
convergenceThresholdFor problem =
  case problemDataset problem of
    "MNIST" -> 0.82
    "Fashion-MNIST" -> 0.87
    "CIFAR-10" -> 0.95
    "CIFAR-100" -> 1.40
    "Tiny ImageNet" -> 2.10
    "California Housing" -> 0.72
    _ -> 1.0

renderTrainResult :: TrainResult -> Text
renderTrainResult result =
  Text.unlines
    [ "problem: " <> resultProblemName result
    , "final-loss: " <> Text.pack (show (pipelineFinalLoss (resultPipeline result)))
    , "threshold: " <> Text.pack (show (resultConvergenceThreshold result))
    , "converged: " <> Text.pack (show (resultConverged result))
    ]

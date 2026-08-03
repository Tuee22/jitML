{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter (..)
  , AlgorithmModule (..)
  , AlgorithmUpdateContract (..)
  , EvaluationEpisodeResult (..)
  , MeasuredEnvironmentTransitions
  , MeasuredOptimizerUpdates
  , MeasuredTrainerCounters
  , hyperparameterRow
  , measuredEnvironmentTransitionCount
  , measuredOptimizerUpdateCount
  , mkMeasuredTrainerCounters
  , renderAlgorithmModule
  , renderHyperparameters
  , updateContract
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))

-- | One final-policy evaluator result before it is keyed into an
-- 'JitML.RL.Framework.EvaluationSet'.  @evaluationEpisodeTerminated@ is true
-- only when the environment emitted its terminal signal; exhausting the
-- evaluation horizon leaves it false even though the evaluator loop has
-- finished.
data EvaluationEpisodeResult = EvaluationEpisodeResult
  { evaluationEpisodeReward :: !Double
  , evaluationEpisodeSteps :: !Int
  , evaluationEpisodeTerminated :: !Bool
  }
  deriving stock (Eq, Show)

-- | Physical environment transitions observed by a trainer. This is a
-- measured result, not a planned rollout/episode/iteration field.
newtype MeasuredEnvironmentTransitions = MeasuredEnvironmentTransitions Word64
  deriving stock (Eq, Ord, Show)

-- | Optimizer applications executed against the exact learned tensor returned
-- by a trainer. Auxiliary optimizer state not represented by that tensor is
-- not included.
newtype MeasuredOptimizerUpdates = MeasuredOptimizerUpdates Word64
  deriving stock (Eq, Ord, Show)

data MeasuredTrainerCounters = MeasuredTrainerCounters
  { measuredTrainerTransitions :: !MeasuredEnvironmentTransitions
  , measuredTrainerUpdates :: !MeasuredOptimizerUpdates
  }
  deriving stock (Eq, Show)

measuredEnvironmentTransitionCount :: MeasuredTrainerCounters -> Word64
measuredEnvironmentTransitionCount counters =
  case measuredTrainerTransitions counters of
    MeasuredEnvironmentTransitions value -> value

measuredOptimizerUpdateCount :: MeasuredTrainerCounters -> Word64
measuredOptimizerUpdateCount counters =
  case measuredTrainerUpdates counters of
    MeasuredOptimizerUpdates value -> value

mkMeasuredTrainerCounters
  :: Integer
  -> Integer
  -> Either Text MeasuredTrainerCounters
mkMeasuredTrainerCounters transitions updates = do
  transitionCount <- checkedPositive "RL measured environment-transition count" transitions
  updateCount <- checkedPositive "RL measured optimizer-update count" updates
  pure
    MeasuredTrainerCounters
      { measuredTrainerTransitions = MeasuredEnvironmentTransitions transitionCount
      , measuredTrainerUpdates = MeasuredOptimizerUpdates updateCount
      }
 where
  checkedPositive label value
    | value <= 0 = Left (label <> " must be positive")
    | value > toInteger (maxBound :: Word64) = Left (label <> " exceeds the Word64 range")
    | otherwise = Right (fromInteger value)

data AlgorithmHyperparameter = AlgorithmHyperparameter
  { hyperName :: Text
  , hyperValue :: Text
  , hyperDeterministicOnly :: Bool
  }
  deriving stock (Eq, Show)

data AlgorithmModule = AlgorithmModule
  { moduleAlgorithm :: RLAlgorithm
  , moduleHyperparameters :: [AlgorithmHyperparameter]
  , moduleUpdateContract :: AlgorithmUpdateContract
  }

data AlgorithmUpdateContract = AlgorithmUpdateContract
  { updateIdentity :: Text
  , trainerEntryPoint :: Text
  , rolloutSurface :: Text
  , learnedArtifact :: Text
  , updateFeatures :: [Text]
  }
  deriving stock (Eq, Show)

hyperparameterRow :: Text -> Text -> Bool -> AlgorithmHyperparameter
hyperparameterRow = AlgorithmHyperparameter

updateContract :: Text -> Text -> Text -> Text -> [Text] -> AlgorithmUpdateContract
updateContract = AlgorithmUpdateContract

renderHyperparameters :: [AlgorithmHyperparameter] -> Text
renderHyperparameters hyperparameters =
  Text.unlines
    [ "  - " <> hyperName h <> " = " <> hyperValue h <> deterministicMarker h
    | h <- hyperparameters
    ]
 where
  deterministicMarker h
    | hyperDeterministicOnly h = "  [deterministic-only]"
    | otherwise = ""

renderAlgorithmModule :: AlgorithmModule -> Text
renderAlgorithmModule m =
  Text.unlines
    [ "algorithm: " <> algorithmName (moduleAlgorithm m)
    , "family: " <> renderFamily (algorithmFamily (moduleAlgorithm m))
    , "replay-based: " <> if algorithmReplayBased (moduleAlgorithm m) then "yes" else "no"
    , "update-identity: " <> updateIdentity (moduleUpdateContract m)
    , "trainer-entrypoint: " <> trainerEntryPoint (moduleUpdateContract m)
    , "rollout-surface: " <> rolloutSurface (moduleUpdateContract m)
    , "learned-artifact: " <> learnedArtifact (moduleUpdateContract m)
    , "update-features:"
    , renderUpdateFeatures (updateFeatures (moduleUpdateContract m))
    , "hyperparameters:"
    , renderHyperparameters (moduleHyperparameters m)
    ]
 where
  renderFamily OnPolicy = "on-policy"
  renderFamily OffPolicy = "off-policy"
  renderFamily Specialized = "specialised"
  renderFamily SelfPlay = "self-play"
  renderUpdateFeatures features =
    Text.unlines ["  - " <> feature | feature <- features]

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
  , ObservedTrainerCounters
  , RawTrainerResult (..)
  , mkObservedTrainerCounters
  , observedEnvironmentTransitionCount
  , observedOptimizerUpdateCount
  , refineObservedTrainerCounters
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

-- | Numerical observations only. Zero is retained; this does not establish
-- training eligibility, producer identity, device execution or convergence.
data ObservedTrainerCounters = ObservedTrainerCounters !Word64 !Word64
  deriving stock (Eq, Show)

observedEnvironmentTransitionCount :: ObservedTrainerCounters -> Word64
observedEnvironmentTransitionCount (ObservedTrainerCounters transitions _) = transitions

observedOptimizerUpdateCount :: ObservedTrainerCounters -> Word64
observedOptimizerUpdateCount (ObservedTrainerCounters _ updates) = updates

mkObservedTrainerCounters :: Integer -> Integer -> Either Text ObservedTrainerCounters
mkObservedTrainerCounters transitions updates = do
  t <- checkedNatural "RL measured environment-transition count" transitions
  u <- checkedNatural "RL measured optimizer-update count" updates
  pure (ObservedTrainerCounters t u)
 where
  checkedNatural label value
    | value < 0 = Left (label <> " must be non-negative")
    | value > toInteger (maxBound :: Word64) = Left (label <> " exceeds the Word64 range")
    | otherwise = Right (fromInteger value)

-- | Preserve the existing strict positive-count boundary for old callers.
refineObservedTrainerCounters :: ObservedTrainerCounters -> Either Text MeasuredTrainerCounters
refineObservedTrainerCounters counters =
  mkMeasuredTrainerCounters
    (toInteger (observedEnvironmentTransitionCount counters))
    (toInteger (observedOptimizerUpdateCount counters))

-- | Public raw DTO, deliberately not an authenticated or eligibility type.
-- Initial parameters are the actual lexical value passed into the training
-- loop. This is a policy snapshot, not complete resumable optimizer/RNG state.
data RawTrainerResult params stat config = RawTrainerResult
  { rawTrainerInitialParams :: !params
  , rawTrainerFinalParams :: !params
  , rawTrainerStats :: ![stat]
  , rawTrainerCounters :: !ObservedTrainerCounters
  , rawTrainerConfig :: !config
  }
  deriving stock (Eq, Show)

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

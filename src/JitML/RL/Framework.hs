{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Framework
  ( ActionDistribution (..)
  , ActionDomain (..)
  , ActionNoise (..)
  , AdvantageEstimator (..)
  , Callback (..)
  , Evaluator (..)
  , EpisodeOutcome
  , EvaluationEpisodeId
  , EvaluationSet
  , FiniteMeasurement
  , IterationSummary
  , LearningCurve
  , RLRunLifecycle (..)
  , RLRunPhase (..)
  , Schedule (..)
  , TargetNetwork (..)
  , TrainingLifecycle (..)
  , TrainingPhase (..)
  , TuneSweepLifecycle (..)
  , TuneSweepPhase (..)
  , rlRunPlan
  , episodeOutcomeDone
  , episodeOutcomeReward
  , episodeOutcomeSteps
  , evaluationEpisodeIdValue
  , evaluationSetMeanReward
  , evaluationSetMedianReward
  , evaluationSetOutcomes
  , finiteMeasurementValue
  , iterationSummaryIndex
  , iterationSummaryMetricName
  , iterationSummaryMetricValue
  , learningCurveSummaries
  , mkEvaluationSet
  , mkIterationSummary
  , mkLearningCurve
  , renderActionDomain
  , renderFrameworkCatalog
  , renderRLRunPhase
  , trainingLifecyclePlan
  , tuneSweepPlan
  )
where

import Data.List (sort)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

-- | A finite scalar admitted at the RL evidence boundary. The constructor is
-- deliberately private so NaN and infinities cannot enter either a learning
-- curve or a final evaluation set.
newtype FiniteMeasurement = FiniteMeasurement
  { finiteMeasurementValue :: Double
  }
  deriving stock (Eq, Ord, Show)

mkFiniteMeasurement :: Text -> Double -> Either Text FiniteMeasurement
mkFiniteMeasurement label value
  | isNaN value || isInfinite value = Left (label <> " must be finite")
  | otherwise = Right (FiniteMeasurement value)

-- | One trainer-produced learning observation. Its index is an ordinal in the
-- trainer's own sequence; it is never an evaluation-episode identifier.
data IterationSummary = IterationSummary
  { iterationSummaryIndex :: !Word64
  , iterationSummaryMetricName :: !Text
  , iterationSummaryMeasurement :: !FiniteMeasurement
  }
  deriving stock (Eq, Show)

iterationSummaryMetricValue :: IterationSummary -> Double
iterationSummaryMetricValue = finiteMeasurementValue . iterationSummaryMeasurement

mkIterationSummary :: Word64 -> Text -> Double -> Either Text IterationSummary
mkIterationSummary index metricName value
  | Text.null canonicalMetricName = Left "RL iteration summary requires a metric name"
  | otherwise =
      IterationSummary index canonicalMetricName
        <$> mkFiniteMeasurement "RL iteration-summary measurement" value
 where
  canonicalMetricName = Text.strip metricName

-- | A non-empty, strictly ordered trainer learning curve. Input order is
-- retained and validated; it is never reconstructed from final evaluations or
-- broker arrival order.
newtype LearningCurve = LearningCurve
  { learningCurveValues :: NonEmpty IterationSummary
  }
  deriving stock (Eq, Show)

learningCurveSummaries :: LearningCurve -> [IterationSummary]
learningCurveSummaries = NonEmpty.toList . learningCurveValues

mkLearningCurve :: [IterationSummary] -> Either Text LearningCurve
mkLearningCurve summaries = do
  nonEmpty <-
    maybe
      (Left "RL learning curve must contain at least one iteration summary")
      Right
      (NonEmpty.nonEmpty summaries)
  validateStrictOrder (fmap iterationSummaryIndex summaries)
  validateMetricNames summaries
  pure (LearningCurve nonEmpty)
 where
  validateStrictOrder [] = Right ()
  validateStrictOrder [_] = Right ()
  validateStrictOrder (left : right : rest)
    | right > left = validateStrictOrder (right : rest)
    | otherwise = Left "RL learning-curve iteration indexes must be strictly increasing"
  validateMetricNames [] = Right ()
  validateMetricNames (first : rest)
    | all ((== iterationSummaryMetricName first) . iterationSummaryMetricName) rest = Right ()
    | otherwise = Left "RL learning curve must contain one consistent metric"

-- | A final-evaluation key. Unlike an iteration ordinal, this identifies one
-- member of the exact evaluation cohort.
newtype EvaluationEpisodeId = EvaluationEpisodeId
  { evaluationEpisodeIdValue :: Word64
  }
  deriving stock (Eq, Ord, Show)

data EpisodeOutcome = EpisodeOutcome
  { episodeOutcomeMeasurement :: !FiniteMeasurement
  , episodeOutcomeSteps :: !Word64
  , episodeOutcomeDone :: !Bool
  }
  deriving stock (Eq, Show)

episodeOutcomeReward :: EpisodeOutcome -> Double
episodeOutcomeReward = finiteMeasurementValue . episodeOutcomeMeasurement

-- | The complete final-policy evaluation cohort. Map identity makes arrival
-- order irrelevant, while the smart constructor requires exactly the planned
-- zero-based keys with no duplicates or gaps.
newtype EvaluationSet = EvaluationSet
  { evaluationSetValues :: Map EvaluationEpisodeId EpisodeOutcome
  }
  deriving stock (Eq, Show)

evaluationSetOutcomes :: EvaluationSet -> [(EvaluationEpisodeId, EpisodeOutcome)]
evaluationSetOutcomes = Map.toAscList . evaluationSetValues

mkEvaluationSet
  :: Word64
  -> [(Word64, Double, Int, Bool)]
  -> Either Text EvaluationSet
mkEvaluationSet expected rawOutcomes
  | expected == 0 = Left "RL evaluation set requires a positive planned episode count"
  | toInteger (length rawOutcomes) /= toInteger expected =
      Left
        ( "RL evaluation set cardinality mismatch: expected "
            <> Text.pack (show expected)
            <> ", observed "
            <> Text.pack (show (length rawOutcomes))
        )
  | actualIds /= expectedIds =
      Left "RL evaluation set requires each zero-based episode id exactly once"
  | otherwise = EvaluationSet . Map.fromList <$> traverse refine rawOutcomes
 where
  actualIds = sort (fmap (\(episodeId, _, _, _) -> episodeId) rawOutcomes)
  expectedIds = fmap fromIntegral [0 .. length rawOutcomes - 1]
  refine (episodeId, reward, steps, done)
    | steps <= 0 =
        Left
          ( "RL evaluation episode "
              <> Text.pack (show episodeId)
              <> " must report positive steps"
          )
    | otherwise = do
        measurement <- mkFiniteMeasurement "RL evaluation reward" reward
        pure
          ( EvaluationEpisodeId episodeId
          , EpisodeOutcome measurement (fromIntegral steps) done
          )

evaluationSetMeanReward :: EvaluationSet -> Double
evaluationSetMeanReward evaluationSet =
  let rewards = fmap (episodeOutcomeReward . snd) (evaluationSetOutcomes evaluationSet)
      rewardCount = fromIntegral (length rewards)
   in sum (fmap (/ rewardCount) rewards)

evaluationSetMedianReward :: EvaluationSet -> Double
evaluationSetMedianReward evaluationSet =
  let rewards = sort (fmap (episodeOutcomeReward . snd) (evaluationSetOutcomes evaluationSet))
      count = length rewards
      middle = count `div` 2
   in if even count
        then rewards !! (middle - 1) / 2 + rewards !! middle / 2
        else rewards !! middle

data TrainingPhase
  = TrainingConfigured
  | TrainingCollecting
  | TrainingOptimizing
  | TrainingEvaluating
  | TrainingCheckpointing
  deriving stock (Eq, Show)

data TrainingLifecycle phase where
  STrainingConfigured :: TrainingLifecycle 'TrainingConfigured
  STrainingCollecting :: TrainingLifecycle 'TrainingCollecting
  STrainingOptimizing :: TrainingLifecycle 'TrainingOptimizing
  STrainingEvaluating :: TrainingLifecycle 'TrainingEvaluating
  STrainingCheckpointing :: TrainingLifecycle 'TrainingCheckpointing

data TuneSweepPhase
  = SweepConfigured
  | SweepScheduling
  | SweepRunningTrial
  | SweepPruning
  | SweepCompleted
  deriving stock (Eq, Show)

data TuneSweepLifecycle phase where
  SSweepConfigured :: TuneSweepLifecycle 'SweepConfigured
  SSweepScheduling :: TuneSweepLifecycle 'SweepScheduling
  SSweepRunningTrial :: TuneSweepLifecycle 'SweepRunningTrial
  SSweepPruning :: TuneSweepLifecycle 'SweepPruning
  SSweepCompleted :: TuneSweepLifecycle 'SweepCompleted

data RLRunPhase
  = RLCollect
  | RLComputeAdvantages
  | RLOptimise
  | RLEvaluate
  | RLCheckpoint
  deriving stock (Eq, Show)

data RLRunLifecycle phase where
  SRLCollect :: RLRunLifecycle 'RLCollect
  SRLComputeAdvantages :: RLRunLifecycle 'RLComputeAdvantages
  SRLOptimise :: RLRunLifecycle 'RLOptimise
  SRLEvaluate :: RLRunLifecycle 'RLEvaluate
  SRLCheckpoint :: RLRunLifecycle 'RLCheckpoint

data Schedule
  = ConstantSchedule Double
  | LinearSchedule Double Double
  | CosineSchedule Double Double
  deriving stock (Eq, Show)

data ActionDistribution
  = Categorical
  | DiagonalGaussian
  | DeterministicPolicy
  deriving stock (Eq, Show)

-- | Phase 250 — the action domain a canonical @(algorithm, environment)@ cohort
-- exercises. This is the type the typed cohort ('JitML.RL.Algorithms.Registry')
-- attaches to every admissible pair so that a discrete trainer can never be
-- paired with a continuous simulator (or a goal-conditioned relabelling trainer
-- with a non-goal environment). @lunar-lander@ is deliberately dual-domain: it
-- is 'DiscreteDomain' under the on-policy / ARS cohorts and 'ContinuousDomain'
-- under the DDPG/TD3/SAC/CrossQ/TQC cohorts, so the domain is a function of both
-- the algorithm and the environment, never the environment name alone.
data ActionDomain
  = DiscreteDomain
  | ContinuousDomain
  | GoalConditionedDomain
  deriving stock (Eq, Show)

renderActionDomain :: ActionDomain -> Text
renderActionDomain DiscreteDomain = "discrete"
renderActionDomain ContinuousDomain = "continuous"
renderActionDomain GoalConditionedDomain = "goal-conditioned"

data ActionNoise
  = NoActionNoise
  | GaussianNoise Double
  | OrnsteinUhlenbeckNoise Double
  deriving stock (Eq, Show)

data TargetNetwork
  = NoTargetNetwork
  | PeriodicTargetNetwork Int
  | PolyakTargetNetwork Double
  deriving stock (Eq, Show)

data AdvantageEstimator
  = MonteCarloReturn
  | GeneralizedAdvantageEstimation Double
  deriving stock (Eq, Show)

data Callback
  = CheckpointEvery Int
  | EvaluateEvery Int
  | StopOnReward Double
  deriving stock (Eq, Show)

newtype Evaluator = Evaluator
  { evaluatorEpisodes :: Int
  }
  deriving stock (Eq, Show)

trainingLifecyclePlan :: [TrainingPhase]
trainingLifecyclePlan =
  [ TrainingConfigured
  , TrainingCollecting
  , TrainingOptimizing
  , TrainingEvaluating
  , TrainingCheckpointing
  ]

tuneSweepPlan :: [TuneSweepPhase]
tuneSweepPlan =
  [ SweepConfigured
  , SweepScheduling
  , SweepRunningTrial
  , SweepPruning
  , SweepCompleted
  ]

rlRunPlan :: [RLRunPhase]
rlRunPlan =
  [RLCollect, RLComputeAdvantages, RLOptimise, RLEvaluate, RLCheckpoint]

renderRLRunPhase :: RLRunPhase -> Text
renderRLRunPhase RLCollect = "collect"
renderRLRunPhase RLComputeAdvantages = "compute-advantages"
renderRLRunPhase RLOptimise = "optimise"
renderRLRunPhase RLEvaluate = "evaluate"
renderRLRunPhase RLCheckpoint = "checkpoint"

renderFrameworkCatalog :: Text
renderFrameworkCatalog =
  Text.unlines
    [ "schedules: constant, linear, cosine"
    , "action_distributions: categorical, diagonal-gaussian, deterministic-policy"
    , "action_noise: none, gaussian, ornstein-uhlenbeck"
    , "target_networks: none, periodic, polyak"
    , "advantage_estimators: monte-carlo, gae"
    , "callbacks: checkpoint, evaluate, stop-on-reward"
    , "evaluator: fixed-episode"
    , "rl_run_plan: " <> Text.intercalate " -> " (fmap renderRLRunPhase rlRunPlan)
    ]

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
  , RLRunLifecycle (..)
  , RLRunPhase (..)
  , Schedule (..)
  , TargetNetwork (..)
  , TrainingLifecycle (..)
  , TrainingPhase (..)
  , TuneSweepLifecycle (..)
  , TuneSweepPhase (..)
  , rlRunPlan
  , renderActionDomain
  , renderFrameworkCatalog
  , renderRLRunPhase
  , trainingLifecyclePlan
  , tuneSweepPlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

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

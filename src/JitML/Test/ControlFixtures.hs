{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Fixtures private to the negative-control families.
--
-- "JitML.Test.ContractFixtures" owns the fixtures the unit-test tree shares
-- with the controls (plan identities, refined evidence, the Store-admitted
-- checkpoint).  This module adds the valid baselines the request and event
-- controls perturb: refined workload plans, completed-training proofs, and the
-- protocol events that carry them.  Every value is built through the same
-- smart constructors the product path uses, and every builder is total — a
-- baseline that cannot be built is reported as 'Left', which the harness turns
-- into a 'JitML.Test.NegativeControls.Core.FixtureFailed' control instead of a
-- crash.
module JitML.Test.ControlFixtures
  ( alphaZeroArenaEvent
  , alphaZeroGenerationEvent
  , alphaZeroPlanFixture
  , alphaZeroPlanFor
  , completedTrainingWithObserved
  , rawAlphaZeroPlanFor
  , rawTuningPlanFor
  , rlCompletedCheckpointFor
  , rlEvaluationEvent
  , rlMetricEvent
  , supervisedCompletedCheckpointFor
  , supervisedEpochWithLosses
  , sweepCompletedEvent
  , sweepFinishedRecord
  , tuneTrialFinishedEvent
  , tuneTrialStartedEvent
  , tuningPlanFixture
  , tuningPlanFor
  , tuningSeed
  , validCompletedTraining
  , withSweepProof
  )
where

import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.Plan.Plan
  ( PlanId
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , Validation (..)
  , planIdText
  , runPlanExperimentId
  , runPlanSeeds
  , seedCohortValues
  )
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , RawAlphaZeroPlan (..)
  , RawTuningPlan (..)
  , TuningPlan
  , alphaZeroPlanId
  , alphaZeroPlanRunPlan
  , resolveAlphaZeroPlan
  , resolveTuningPlan
  , tuningPlanId
  , tuningPlanRunPlan
  )
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as TrainingBudget

-- | A refined completed-training proof of exactly @units@ units of @kind@,
-- observed exactly, stamped with @planId@ and @seed@.  The evidence, measured
-- criterion, and TensorBoard metadata are minimal but valid: the constructor
-- re-checks every one of them.
validCompletedTraining
  :: PlanId
  -> TrainingBudget.BudgetKind
  -> Word64
  -> Maybe Word64
  -> Either Text TrainingBudget.CompletedTraining
validCompletedTraining planId kind units =
  completedTrainingWithObserved planId kind units units

-- | Like 'validCompletedTraining' but with an observed unit count that need
-- not equal the budget target, so a caller can ask the production constructor
-- to refuse an under- or overrun.
completedTrainingWithObserved
  :: PlanId
  -> TrainingBudget.BudgetKind
  -> Word64
  -> Word64
  -> Maybe Word64
  -> Either Text TrainingBudget.CompletedTraining
completedTrainingWithObserved planId kind target observed seed = do
  budget <- TrainingBudget.mkTrainingBudget kind target seed
  evidence <-
    ProductEvidence.mkTrainingEvidence
      "control-initial-weights"
      "control-final-weights"
      (max 1 observed)
      "control-dataset-sha"
  observation <-
    TrainingBudget.measureCriterion
      "control_metric"
      TrainingBudget.MetricMaximise
      0.5
      0.9
  TrainingBudget.completedTraining
    planId
    budget
    observed
    evidence
    [observation]
    TrainingBudget.TensorBoardRunMetadata
      { TrainingBudget.tbrRunId = "control-run"
      , TrainingBudget.tbrLogPrefix = "tensorboard/control-run"
      , TrainingBudget.tbrScalarTags = ["control_metric"]
      }

-- | A raw tuning plan with @trials@ trials, 1 promotion, 1 in parallel, and 10
-- updates per trial.  Sampler, scheduler, and pruner are fixed so only the
-- trial count varies.
rawTuningPlanFor :: Text -> Integer -> RawTuningPlan
rawTuningPlanFor experiment trials =
  RawTuningPlan
    { rawTuningRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = HyperparameterTuningWitness
          , rawRunExperimentId = experiment
          , rawRunSubjectId = "mnist/dense"
          , rawRunArtifactId = "best-checkpoint"
          , rawRunTopicId = "tune.event.linux-cpu"
          , rawRunSubstrate = LinuxCPU
          , rawRunPlacement = ClusterRun
          , rawRunSeeds = [7]
          , rawRunBudget = RawTuningBudget trials 1 1 10
          }
    , rawTuningSampler = "TPE"
    , rawTuningScheduler = "ASHA"
    , rawTuningPruner = "MedianPruner"
    }

tuningPlanFor :: Text -> Integer -> Either Text TuningPlan
tuningPlanFor experiment trials =
  case resolveTuningPlan (rawTuningPlanFor experiment trials) of
    Success plan -> Right plan
    Failure errors ->
      Left ("tuning plan fixture failed to resolve: " <> Text.pack (show errors))

-- | The standard three-trial tuning plan the event controls use.
tuningPlanFixture :: Either Text TuningPlan
tuningPlanFixture = tuningPlanFor "control-tuning" 3

-- | A raw AlphaZero plan with @generations@ generations of 4 self-play games
-- each and an arena of 6 games.
rawAlphaZeroPlanFor :: Text -> Integer -> RawAlphaZeroPlan
rawAlphaZeroPlanFor experiment generations =
  RawAlphaZeroPlan
    { rawAlphaZeroRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = AlphaZeroSelfPlayWitness
          , rawRunExperimentId = experiment
          , rawRunSubjectId = "connect4-policy-value"
          , rawRunArtifactId = "alphazero-checkpoint"
          , rawRunTopicId = "rl.event.linux-cpu"
          , rawRunSubstrate = LinuxCPU
          , rawRunPlacement = ClusterRun
          , rawRunSeeds = [11]
          , rawRunBudget = RawAlphaZeroBudget generations 4 16 42 8 6
          }
    , rawAlphaZeroGame = "connect4"
    }

alphaZeroPlanFor :: Text -> Integer -> Either Text AlphaZeroPlan
alphaZeroPlanFor experiment generations =
  case resolveAlphaZeroPlan (rawAlphaZeroPlanFor experiment generations) of
    Success plan -> Right plan
    Failure errors ->
      Left ("AlphaZero plan fixture failed to resolve: " <> Text.pack (show errors))

-- | The standard three-generation AlphaZero plan the event controls use.
alphaZeroPlanFixture :: Either Text AlphaZeroPlan
alphaZeroPlanFixture = alphaZeroPlanFor "control-alphazero" 3

-- Supervised protocol events ---------------------------------------------------

-- | An epoch summary with independent training and validation losses.
supervisedEpochWithLosses :: Text -> Word32 -> Double -> Double -> Training.TrainingEvent
supervisedEpochWithLosses experiment epoch loss validationLoss =
  Training.TrainingEpoch
    Training.EpochCompleted
      { Training.ecExperimentHash = experiment
      , Training.ecEpoch = epoch
      , Training.ecLoss = loss
      , Training.ecValidationLoss = validationLoss
      , Training.ecTimestampNs = fromIntegral epoch + 1
      }

-- | A completed supervised checkpoint whose proof is denominated in @kind@ and
-- carries exactly @units@ units, stamped with @planId@.  The checkpoint step
-- equals the observed units, as 'Training.completeCheckpointDone' requires.
supervisedCompletedCheckpointFor
  :: PlanId
  -> TrainingBudget.BudgetKind
  -> Word64
  -> Text
  -> Either Text Training.TrainingEvent
supervisedCompletedCheckpointFor planId kind units experiment = do
  completed <- validCompletedTraining planId kind units (Just 7)
  Training.TrainingCompletedCheckpoint
    <$> Training.completeCheckpointDone
      Training.CheckpointDone
        { Training.cdExperimentHash = experiment
        , Training.cdManifestSha = "supervised-control-manifest"
        , Training.cdStep = units
        , Training.cdPointerKey = "checkpoints/supervised-control/latest"
        , Training.cdEpoch = fromIntegral units
        , Training.cdTrialSha = Nothing
        , Training.cdRunUuid = "supervised-control-run"
        , Training.cdMetricsAtStep = [("control_metric", 0.9)]
        }
      completed

-- Reinforcement-learning protocol events ---------------------------------------

rlEvaluationEvent :: Text -> Text -> Word64 -> Double -> Word64 -> Rl.RlEvent
rlEvaluationEvent planText experiment episode reward steps =
  Rl.RlEvaluation
    Rl.EvaluationOutcome
      { Rl.eoPlanId = planText
      , Rl.eoExperimentHash = experiment
      , Rl.eoEpisodeId = episode
      , Rl.eoReward = reward
      , Rl.eoSteps = steps
      , Rl.eoDone = True
      , Rl.eoTimestampNs = episode + 1
      }

rlMetricEvent :: Text -> Text -> Double -> Rl.RlEvent
rlMetricEvent planText experiment value =
  Rl.RlMetric
    Rl.MetricUpdate
      { Rl.muPlanId = planText
      , Rl.muExperimentHash = experiment
      , Rl.muName = "median_final_reward"
      , Rl.muValue = value
      , Rl.muTimestampNs = 3
      }

-- | A completed RL checkpoint whose proof is denominated in @kind@ and carries
-- exactly @units@ units.
rlCompletedCheckpointFor
  :: PlanId
  -> TrainingBudget.BudgetKind
  -> Word64
  -> Text
  -> Either Text Rl.RlEvent
rlCompletedCheckpointFor planId kind units experiment = do
  completed <- validCompletedTraining planId kind units (Just 7)
  Rl.RlCompletedCheckpoint
    <$> Rl.completeCheckpointDoneRL
      Rl.CheckpointDoneRL
        { Rl.cdrlExperimentHash = experiment
        , Rl.cdrlManifestSha = "rl-control-manifest"
        , Rl.cdrlStep = units
        , Rl.cdrlPointerKey = "checkpoints/rl-control/latest"
        }
      completed

-- Tuning protocol events -------------------------------------------------------

-- | The run seed the tuning fixture plans carry (the head of their cohort).
tuningSeed :: TuningPlan -> Maybe Word64
tuningSeed plan =
  Just (NonEmpty.head (seedCohortValues (runPlanSeeds (tuningPlanRunPlan plan))))

tuneTrialFinishedEvent :: TuningPlan -> Word32 -> Double -> Tune.TuneEvent
tuneTrialFinishedEvent plan trial objective =
  Tune.TuneTrialFinished
    Tune.TrialFinished
      { Tune.tfTuneExperimentHash = runPlanExperimentId (tuningPlanRunPlan plan)
      , Tune.tfTunePlanId = planIdText (tuningPlanId plan)
      , Tune.tfTuneTrial = trial
      , Tune.tfTuneObjective = objective
      , Tune.tfTunePruned = False
      , Tune.tfTuneTranscriptObjectKey = "trials/" <> Text.pack (show trial) <> ".cbor"
      , Tune.tfTuneTimestampNs = fromIntegral trial + 100
      }

tuneTrialStartedEvent :: TuningPlan -> Word32 -> Tune.TuneEvent
tuneTrialStartedEvent plan trial =
  Tune.TuneTrialStarted
    Tune.TrialStarted
      { Tune.tsExperimentHash = runPlanExperimentId (tuningPlanRunPlan plan)
      , Tune.tsPlanId = planIdText (tuningPlanId plan)
      , Tune.tsTrial = trial
      , Tune.tsTrialSeed = 7 + fromIntegral trial
      , Tune.tsParametersJson = "{}"
      , Tune.tsTimestampNs = fromIntegral trial + 50
      }

-- | A sweep terminal for @plan@ reporting @completed@ trials, @promoted@
-- promotions, and the given best objective.
sweepFinishedRecord :: TuningPlan -> Word32 -> Word32 -> Double -> Tune.SweepFinished
sweepFinishedRecord plan completed promoted best =
  Tune.SweepFinished
    { Tune.sfExperimentHash = runPlanExperimentId (tuningPlanRunPlan plan)
    , Tune.sfPlanId = planIdText (tuningPlanId plan)
    , Tune.sfTrialsCompleted = completed
    , Tune.sfTrialsPruned = 0
    , Tune.sfTrialsPromoted = promoted
    , Tune.sfBestObjective = best
    }

-- | A completed sweep event: the sweep terminal joined with a tuning proof of
-- @proofUnits@ trials under @proofPlan@ and @proofSeed@.  Joining is the
-- production 'Tune.completeSweep', so a proof inconsistent with its sweep is
-- reported as 'Left' at construction.
sweepCompletedEvent
  :: Tune.SweepFinished
  -> PlanId
  -> TrainingBudget.BudgetKind
  -> Word64
  -> Maybe Word64
  -> Either Text Tune.TuneEvent
sweepCompletedEvent finished proofPlan kind proofUnits proofSeed = do
  proof <- validCompletedTraining proofPlan kind proofUnits proofSeed
  Tune.TuneSweepCompleted <$> Tune.completeSweep finished proof

-- | Replace the completion proof of a completed-sweep event by record update,
-- bypassing 'Tune.completeSweep'.
--
-- 'Tune.SweepCompleted' is exported abstractly, but its field selectors are
-- exported too, and a record update needs only a selector, so a caller can
-- forge a terminal whose proof disagrees with its sweep.  The tuning reducer
-- re-checks the proof for exactly that reason; this is the only way a control
-- can reach those re-checks, because a proof built through 'sweepCompletedEvent'
-- is refused at construction.  The baseline must already be a completed sweep.
withSweepProof
  :: TrainingBudget.CompletedTraining
  -> Tune.TuneEvent
  -> Either Text Tune.TuneEvent
withSweepProof proof tuneEvent =
  case tuneEvent of
    Tune.TuneSweepCompleted completed ->
      Right (Tune.TuneSweepCompleted completed {Tune.scCompletedTraining = proof})
    Tune.TuneTrialStarted _ -> Left notCompleted
    Tune.TuneTrialFinished _ -> Left notCompleted
    Tune.TuneSweepFinished _ -> Left notCompleted
 where
  notCompleted = "the baseline event is not a completed sweep, so its proof cannot be replaced"

-- AlphaZero protocol events ----------------------------------------------------

alphaZeroGenerationEvent :: AlphaZeroPlan -> Word32 -> Word32 -> Word64 -> Rl.RlEvent
alphaZeroGenerationEvent plan generation games samples =
  Rl.RlGenerationCompleted
    Rl.GenerationCompleted
      { Rl.gcPlanId = planIdText (alphaZeroPlanId plan)
      , Rl.gcExperimentHash = runPlanExperimentId (alphaZeroPlanRunPlan plan)
      , Rl.gcGeneration = generation
      , Rl.gcSelfPlayGames = games
      , Rl.gcSamples = samples
      }

alphaZeroArenaEvent :: AlphaZeroPlan -> Word32 -> Double -> Rl.RlEvent
alphaZeroArenaEvent plan games winRate =
  Rl.RlArenaCompleted
    Rl.ArenaCompleted
      { Rl.acPlanId = planIdText (alphaZeroPlanId plan)
      , Rl.acExperimentHash = runPlanExperimentId (alphaZeroPlanRunPlan plan)
      , Rl.acArenaGames = games
      , Rl.acWinRate = winRate
      }

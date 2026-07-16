{-# LANGUAGE OverloadedStrings #-}

-- | Exact protocol-evidence contracts shared by live supervised and
-- traditional-RL integration scenarios.  Tuning and AlphaZero use the
-- production contracts in "JitML.Run.WorkloadContract" directly.
module JitML.Test.LiveEvidence
  ( LiveEvidenceViolation (..)
  , RlEpisodeEvidence (..)
  , RlLiveContract
  , RlLiveEvidence (..)
  , RlLiveProgress
  , SupervisedEpochEvidence (..)
  , SupervisedLiveContract
  , SupervisedLiveEvidence (..)
  , SupervisedLiveProgress
  , ingestRlLiveEvent
  , ingestSupervisedLiveEvent
  , rlLiveContract
  , supervisedLiveContract
  )
where

import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Word (Word32, Word64)

import JitML.Plan.Plan
  ( FiniteMeasurement
  , PlanError
  , PlanId
  , Validation (..)
  , mkFiniteMeasurement
  )
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Run.Contract
  ( Contract
  , ContractViolation
  , EvidenceEvent
  , RequirementState
  , evidenceEvent
  , exactKeyedRange
  , exactKeyedValues
  , exactlyOne
  , exactlyOneValue
  , ingestEvent
  , mapContract
  , productContract
  , selectContract
  )
import JitML.Training.Budget
  ( completedTrainingPlanId
  )

data LiveEvidenceViolation
  = LiveEvidenceInvalidCardinality Text
  | LiveEvidenceExperimentMismatch Text Text
  | LiveEvidencePlanMismatch PlanId PlanId
  | LiveEvidenceMalformed (NonEmpty PlanError)
  | LiveEvidenceZeroSteps Word32
  | LiveEvidenceContractViolation ContractViolation
  | LiveWorkloadReportedFailure Training.TrainingFailed
  deriving stock (Eq, Show)

data SupervisedEpochEvidence = SupervisedEpochEvidence
  { supervisedEpochLoss :: FiniteMeasurement
  , supervisedEpochValidationLoss :: FiniteMeasurement
  , supervisedEpochTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data SupervisedLiveEvidence = SupervisedLiveEvidence
  { supervisedTerminalEpochSnapshot :: Map Word32 SupervisedEpochEvidence
  -- ^ The worker protocol emits one final epoch summary after the run.  This
  -- singleton map is a terminal snapshot, not a fabricated iteration curve.
  , supervisedCompletedCheckpoint :: Training.CompletedCheckpointDone
  }
  deriving stock (Eq, Show)

data SupervisedLiveEvent
  = SupervisedEpochEvent (EvidenceEvent Word32 SupervisedEpochEvidence)
  | SupervisedCheckpointEvent (EvidenceEvent () Training.CompletedCheckpointDone)
  deriving stock (Eq, Show)

type SupervisedLiveProgress =
  ( RequirementState Word32 SupervisedEpochEvidence
  , RequirementState () Training.CompletedCheckpointDone
  )

type SupervisedLiveContract =
  Contract
    SupervisedLiveEvent
    SupervisedLiveProgress
    SupervisedLiveEvidence

supervisedLiveContract
  :: PlanId
  -> Word32
  -> Either LiveEvidenceViolation SupervisedLiveContract
supervisedLiveContract planId epochs = do
  keys <- expectedPositiveSingleton "supervised terminal epoch snapshot" epochs
  let epochContract =
        selectContract
          (\case SupervisedEpochEvent event -> Just event; _ -> Nothing)
          (exactKeyedRange "supervised-terminal-epoch" planId keys)
      checkpointContract =
        selectContract
          (\case SupervisedCheckpointEvent event -> Just event; _ -> Nothing)
          (exactlyOne "supervised-completed-checkpoint" planId)
  pure
    ( mapContract
        ( \(epochEvidence, checkpointEvidence) ->
            SupervisedLiveEvidence
              { supervisedTerminalEpochSnapshot = exactKeyedValues epochEvidence
              , supervisedCompletedCheckpoint = exactlyOneValue checkpointEvidence
              }
        )
        (productContract epochContract checkpointContract)
    )

ingestSupervisedLiveEvent
  :: PlanId
  -> Text
  -> SupervisedLiveContract
  -> SupervisedLiveProgress
  -> Training.TrainingEvent
  -> Either LiveEvidenceViolation SupervisedLiveProgress
ingestSupervisedLiveEvent planId experimentId contract progress protocolEvent =
  case protocolEvent of
    Training.TrainingEpoch epoch
      | Training.ecExperimentHash epoch == experimentId -> do
          loss <- refineMeasurement "training-loss" (Training.ecLoss epoch)
          validationLoss <-
            refineMeasurement
              "validation-loss"
              (Training.ecValidationLoss epoch)
          event <-
            refineEvidence
              planId
              "training-epoch"
              (Training.ecEpoch epoch)
              SupervisedEpochEvidence
                { supervisedEpochLoss = loss
                , supervisedEpochValidationLoss = validationLoss
                , supervisedEpochTimestampNs = Training.ecTimestampNs epoch
                }
          ingest (SupervisedEpochEvent event)
    Training.TrainingCompletedCheckpoint completed
      | Training.cdExperimentHash (Training.ccdCheckpoint completed) == experimentId -> do
          let observedPlan =
                completedTrainingPlanId (Training.ccdCompletedTraining completed)
          if observedPlan /= planId
            then Left (LiveEvidencePlanMismatch planId observedPlan)
            else do
              event <-
                refineEvidence
                  planId
                  "training-completed-checkpoint"
                  ()
                  completed
              ingest (SupervisedCheckpointEvent event)
    Training.TrainingFailure failure
      | Training.tfExperimentHash failure == experimentId ->
          Left (LiveWorkloadReportedFailure failure)
    Training.TrainingCheckpoint checkpoint
      | Training.cdExperimentHash checkpoint == experimentId -> Right progress
    _ -> Right progress
 where
  ingest = first LiveEvidenceContractViolation . ingestEvent contract progress

data RlEpisodeEvidence = RlEpisodeEvidence
  { rlEpisodeReward :: FiniteMeasurement
  , rlEpisodeSteps :: Word32
  , rlEpisodeTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data RlLiveEvidence = RlLiveEvidence
  { rlCompletedEpisodes :: Map Word32 RlEpisodeEvidence
  , rlCompletedMedianReward :: FiniteMeasurement
  , rlCompletedCheckpoint :: Rl.CompletedCheckpointDoneRL
  }
  deriving stock (Eq, Show)

data RlLiveEvent
  = RlEpisodeEvent (EvidenceEvent Word32 RlEpisodeEvidence)
  | RlMetricEvent (EvidenceEvent () FiniteMeasurement)
  | RlCheckpointEvent (EvidenceEvent () Rl.CompletedCheckpointDoneRL)
  deriving stock (Eq, Show)

type RlLiveProgress =
  ( ( RequirementState Word32 RlEpisodeEvidence
    , RequirementState () FiniteMeasurement
    )
  , RequirementState () Rl.CompletedCheckpointDoneRL
  )

type RlLiveContract =
  Contract
    RlLiveEvent
    RlLiveProgress
    RlLiveEvidence

rlLiveContract
  :: PlanId
  -> Word32
  -> Either LiveEvidenceViolation RlLiveContract
rlLiveContract planId episodes = do
  keys <- expectedZeroBasedKeys "RL evaluation episodes" episodes
  let episodeContract =
        selectContract
          (\case RlEpisodeEvent event -> Just event; _ -> Nothing)
          (exactKeyedRange "rl-final-evaluation" planId keys)
      metricContract =
        selectContract
          (\case RlMetricEvent event -> Just event; _ -> Nothing)
          (exactlyOne "rl-median-final-reward" planId)
      checkpointContract =
        selectContract
          (\case RlCheckpointEvent event -> Just event; _ -> Nothing)
          (exactlyOne "rl-completed-checkpoint" planId)
  pure
    ( mapContract
        ( \((episodeEvidence, metricEvidence), checkpointEvidence) ->
            RlLiveEvidence
              { rlCompletedEpisodes = exactKeyedValues episodeEvidence
              , rlCompletedMedianReward = exactlyOneValue metricEvidence
              , rlCompletedCheckpoint = exactlyOneValue checkpointEvidence
              }
        )
        (productContract (productContract episodeContract metricContract) checkpointContract)
    )

-- | Traditional RL has not yet adopted a plan-bearing command/event surface;
-- Sprint 25.4 owns that domain migration.  The caller supplies the stable
-- semantic plan used by this exact live-test contract.  Proof-bearing
-- checkpoints remain mandatory; once the protocol carries its PlanId the
-- optional expected completion id is supplied and checked here without
-- changing the cardinality reducer.
ingestRlLiveEvent
  :: PlanId
  -> Maybe PlanId
  -> Text
  -> RlLiveContract
  -> RlLiveProgress
  -> Rl.RlEvent
  -> Either LiveEvidenceViolation RlLiveProgress
ingestRlLiveEvent contractPlanId expectedCompletionPlanId experimentId contract progress protocolEvent =
  case protocolEvent of
    Rl.RlEpisode episode
      | Rl.edExperimentHash episode == experimentId -> do
          if Rl.edSteps episode == 0
            then Left (LiveEvidenceZeroSteps (Rl.edEpisode episode))
            else Right ()
          reward <- refineMeasurement "rl-final-reward" (Rl.edReward episode)
          event <-
            refineEvidence
              contractPlanId
              "rl-final-evaluation"
              (Rl.edEpisode episode)
              RlEpisodeEvidence
                { rlEpisodeReward = reward
                , rlEpisodeSteps = Rl.edSteps episode
                , rlEpisodeTimestampNs = Rl.edTimestampNs episode
                }
          ingest (RlEpisodeEvent event)
    Rl.RlMetric metric
      | Rl.muExperimentHash metric == experimentId
      , Rl.muName metric == "median_final_reward" -> do
          measurement <- refineMeasurement "rl-median-final-reward" (Rl.muValue metric)
          event <-
            refineEvidence
              contractPlanId
              "rl-median-final-reward"
              ()
              measurement
          ingest (RlMetricEvent event)
    Rl.RlCompletedCheckpoint completed
      | Rl.cdrlExperimentHash (Rl.ccdrlCheckpoint completed) == experimentId -> do
          case expectedCompletionPlanId of
            Just expectedPlan ->
              let observedPlan =
                    completedTrainingPlanId (Rl.ccdrlCompletedTraining completed)
               in if observedPlan /= expectedPlan
                    then Left (LiveEvidencePlanMismatch expectedPlan observedPlan)
                    else Right ()
            Nothing -> Right ()
          event <-
            refineEvidence
              contractPlanId
              "rl-completed-checkpoint"
              ()
              completed
          ingest (RlCheckpointEvent event)
    Rl.RlCheckpoint checkpoint
      | Rl.cdrlExperimentHash checkpoint == experimentId -> Right progress
    _ -> Right progress
 where
  ingest = first LiveEvidenceContractViolation . ingestEvent contract progress

refineMeasurement
  :: Text
  -> Double
  -> Either LiveEvidenceViolation FiniteMeasurement
refineMeasurement label value =
  validationToEither (mkFiniteMeasurement label value)

refineEvidence
  :: (Show key)
  => PlanId
  -> Text
  -> key
  -> value
  -> Either LiveEvidenceViolation (EvidenceEvent key value)
refineEvidence planId kind key value =
  validationToEither (evidenceEvent planId kind key value)

validationToEither
  :: Validation (NonEmpty PlanError) value
  -> Either LiveEvidenceViolation value
validationToEither validation =
  case validation of
    Failure errors -> Left (LiveEvidenceMalformed errors)
    Success value -> Right value

expectedPositiveSingleton
  :: Text
  -> Word32
  -> Either LiveEvidenceViolation (NonEmpty Word32)
expectedPositiveSingleton label count
  | count == 0 = Left (LiveEvidenceInvalidCardinality label)
  | otherwise = Right (count :| [])

expectedZeroBasedKeys
  :: Text
  -> Word32
  -> Either LiveEvidenceViolation (NonEmpty Word32)
expectedZeroBasedKeys label count
  | count == 0 = Left (LiveEvidenceInvalidCardinality label)
  | otherwise = Right (0 :| [1 .. count - 1])

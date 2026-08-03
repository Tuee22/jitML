{-# LANGUAGE OverloadedStrings #-}

-- | Exact protocol-evidence contracts shared by live supervised and
-- traditional-RL integration scenarios.  Tuning and AlphaZero use the
-- production contracts in "JitML.Run.WorkloadContract" directly.
module JitML.Test.LiveEvidence
  ( LiveEvidenceViolation (..)
  , RlEvaluationEvidence (..)
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
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.Plan.Plan
  ( FiniteMeasurement
  , PlanError
  , PlanId
  , Validation (..)
  , finiteMeasurementValue
  , mkFiniteMeasurement
  , planIdText
  )
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Run.Contract
  ( Contract
  , ContractViolation
  , EvidenceEvent
  , ExactKeyed
  , ExactlyOne
  , RequirementState
  , evidenceEvent
  , exactKeyedRange
  , exactKeyedValues
  , exactlyOne
  , exactlyOneValue
  , ingestEvent
  , mapContract
  , productContract
  , refineContract
  , selectContract
  )
import JitML.Training.Budget
  ( completedTrainingPlanId
  )

data LiveEvidenceViolation
  = LiveEvidenceInvalidCardinality Text
  | LiveEvidenceExperimentMismatch Text Text
  | LiveEvidencePlanMismatch PlanId PlanId
  | LiveEvidenceRlPlanMismatch Text Text
  | LiveEvidenceMalformed (NonEmpty PlanError)
  | LiveEvidenceZeroSteps Word64
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

data RlEvaluationEvidence = RlEvaluationEvidence
  { rlEvaluationReward :: FiniteMeasurement
  , rlEvaluationSteps :: Word64
  , rlEvaluationDone :: Bool
  , rlEvaluationTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data RlLiveEvidence = RlLiveEvidence
  { rlCompletedEvaluationSet :: Map Word64 RlEvaluationEvidence
  , rlCompletedMedianReward :: FiniteMeasurement
  , rlCompletedCheckpoint :: Rl.CompletedCheckpointDoneRL
  }
  deriving stock (Eq, Show)

data RlLiveEvent
  = RlEvaluationEvent (EvidenceEvent Word64 RlEvaluationEvidence)
  | RlMetricEvent (EvidenceEvent () FiniteMeasurement)
  | RlCheckpointEvent (EvidenceEvent () Rl.CompletedCheckpointDoneRL)
  deriving stock (Eq, Show)

type RlLiveProgress =
  ( ( RequirementState Word64 RlEvaluationEvidence
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
          (\case RlEvaluationEvent event -> Just event; _ -> Nothing)
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
    ( refineContract
        refineRlLiveEvidence
        (productContract (productContract episodeContract metricContract) checkpointContract)
    )

refineRlLiveEvidence
  :: ( (ExactKeyed Word64 RlEvaluationEvidence, ExactlyOne FiniteMeasurement)
     , ExactlyOne Rl.CompletedCheckpointDoneRL
     )
  -> Either Text RlLiveEvidence
refineRlLiveEvidence ((episodeEvidence, metricEvidence), checkpointEvidence) = do
  let evaluationSet = exactKeyedValues episodeEvidence
      reportedMedian = exactlyOneValue metricEvidence
  cohortMedian <- medianReward evaluationSet
  if finiteMeasurementValue reportedMedian /= cohortMedian
    then
      Left
        ( "RL median_final_reward does not match the exact evaluation cohort: reported "
            <> Text.pack (show (finiteMeasurementValue reportedMedian))
            <> ", derived "
            <> Text.pack (show cohortMedian)
        )
    else
      Right
        RlLiveEvidence
          { rlCompletedEvaluationSet = evaluationSet
          , rlCompletedMedianReward = reportedMedian
          , rlCompletedCheckpoint = exactlyOneValue checkpointEvidence
          }

medianReward :: Map Word64 RlEvaluationEvidence -> Either Text Double
medianReward evaluationSet =
  case sort (fmap (finiteMeasurementValue . rlEvaluationReward) (Map.elems evaluationSet)) of
    [] -> Left "RL median_final_reward requires a non-empty evaluation cohort"
    rewards ->
      let count = length rewards
          middle = count `div` 2
       in Right
            ( if even count
                then rewards !! (middle - 1) / 2 + rewards !! middle / 2
                else rewards !! middle
            )

-- | Consume plan-bound keyed final-evaluation outcomes. The one refined
-- compiled RL plan identity binds event payloads, semantic event ids, and the
-- completed checkpoint; broker arrival order cannot substitute for an
-- event's logical episode key.
ingestRlLiveEvent
  :: PlanId
  -> Text
  -> RlLiveContract
  -> RlLiveProgress
  -> Rl.RlEvent
  -> Either LiveEvidenceViolation RlLiveProgress
ingestRlLiveEvent contractPlanId experimentId contract progress protocolEvent =
  case protocolEvent of
    Rl.RlEvaluation outcome
      | Rl.eoExperimentHash outcome == experimentId -> do
          if Rl.eoPlanId outcome /= planIdText contractPlanId
            then
              Left
                ( LiveEvidenceRlPlanMismatch
                    (planIdText contractPlanId)
                    (Rl.eoPlanId outcome)
                )
            else Right ()
          if Rl.eoSteps outcome == 0
            then Left (LiveEvidenceZeroSteps (Rl.eoEpisodeId outcome))
            else Right ()
          reward <- refineMeasurement "rl-final-reward" (Rl.eoReward outcome)
          event <-
            refineEvidence
              contractPlanId
              "rl-final-evaluation"
              (Rl.eoEpisodeId outcome)
              RlEvaluationEvidence
                { rlEvaluationReward = reward
                , rlEvaluationSteps = Rl.eoSteps outcome
                , rlEvaluationDone = Rl.eoDone outcome
                , rlEvaluationTimestampNs = Rl.eoTimestampNs outcome
                }
          ingest (RlEvaluationEvent event)
    Rl.RlMetric metric
      | Rl.muExperimentHash metric == experimentId
      , Rl.muName metric == "median_final_reward" -> do
          if Rl.muPlanId metric /= planIdText contractPlanId
            then
              Left
                ( LiveEvidenceRlPlanMismatch
                    (planIdText contractPlanId)
                    (Rl.muPlanId metric)
                )
            else Right ()
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
          let observedPlan =
                completedTrainingPlanId (Rl.ccdrlCompletedTraining completed)
          if observedPlan /= contractPlanId
            then Left (LiveEvidencePlanMismatch contractPlanId observedPlan)
            else Right ()
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
  -> Either LiveEvidenceViolation (NonEmpty Word64)
expectedZeroBasedKeys label count
  | count == 0 = Left (LiveEvidenceInvalidCardinality label)
  | otherwise =
      let upper = fromIntegral count - 1
       in Right (0 :| [1 .. upper])

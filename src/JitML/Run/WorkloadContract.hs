{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Pure completion contracts for tuning sweeps and AlphaZero self-play.
--
-- Protocol records deliberately remain raw at the transport boundary.  This
-- module correlates them with an already-resolved workload plan, refines every
-- completion measurement, derives semantic event identities, and feeds the
-- resulting evidence through "JitML.Run.Contract".  The exact keyed ranges are
-- zero-based: a plan for @n@ trials or generations requires keys @[0 .. n-1]@.
module JitML.Run.WorkloadContract
  ( AlphaZeroCompletion (..)
  , AlphaZeroCompletionContract
  , AlphaZeroCompletionEvent
  , AlphaZeroCompletionProgress
  , AlphaZeroGenerationCompletion (..)
  , AlphaZeroArenaCompletion (..)
  , TuningCompletion (..)
  , TuningCompletionContract
  , TuningCompletionEvent
  , TuningCompletionProgress
  , TuningSweepCompletion (..)
  , TuningTrialCompletion (..)
  , WorkloadContractViolation (..)
  , alphaZeroCompletionContract
  , ingestAlphaZeroEvent
  , ingestTuneEvent
  , tuningCompletionContract
  )
where

import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Word (Word32, Word64)

import JitML.Plan.Plan
  ( FiniteMeasurement
  , PlanError
  , PlanId
  , Validation (..)
  , mkFiniteMeasurement
  , planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSeeds
  , seedCohortValues
  )
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , TuningPlan
  , alphaZeroPlanArenaGames
  , alphaZeroPlanGenerations
  , alphaZeroPlanId
  , alphaZeroPlanRunPlan
  , alphaZeroPlanSelfPlayGames
  , tuningPlanId
  , tuningPlanPromotions
  , tuningPlanRunPlan
  , tuningPlanTrials
  )
import JitML.Proto.Rl
  ( ArenaCompleted (..)
  , GenerationCompleted (..)
  , RlEvent (..)
  )
import JitML.Proto.Tune
  ( SweepFinished (..)
  , TrialFinished (..)
  , TrialStarted (..)
  , TuneEvent (..)
  , scCompletedTraining
  , scFinished
  )
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
  ( BudgetKind (..)
  , CompletedTraining
  , completedTrainingBudget
  , completedTrainingPlanId
  , trainingBudgetKind
  , trainingBudgetSeed
  , trainingBudgetTargetUnits
  )

-- | A successfully refined tuning-trial completion.  Keeping the finite
-- objective in the value makes non-finite protocol input unrepresentable in
-- completed evidence.
data TuningTrialCompletion = TuningTrialCompletion
  { tuningTrialExperimentId :: Text
  , tuningTrialObjective :: FiniteMeasurement
  , tuningTrialPruned :: Bool
  , tuningTrialTranscriptObjectKey :: Text
  , tuningTrialTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data TuningSweepCompletion = TuningSweepCompletion
  { tuningSweepExperimentId :: Text
  , tuningSweepTrialsCompleted :: Word32
  , tuningSweepTrialsPruned :: Word32
  , tuningSweepTrialsPromoted :: Word32
  , tuningSweepBestObjective :: FiniteMeasurement
  , tuningSweepCompletedTraining :: CompletedTraining
  }
  deriving stock (Eq, Show)

data TuningCompletion = TuningCompletion
  { tuningCompletedTrials :: Map Word64 TuningTrialCompletion
  , tuningCompletedSweep :: TuningSweepCompletion
  }
  deriving stock (Eq, Show)

data TuningCompletionEvent
  = TuningTrialEvidence
      (EvidenceEvent Word64 TuningTrialCompletion)
  | TuningSweepEvidence
      (EvidenceEvent () TuningSweepCompletion)
  deriving stock (Eq, Show)

type TuningCompletionProgress =
  ( RequirementState Word64 TuningTrialCompletion
  , RequirementState () TuningSweepCompletion
  )

type TuningCompletionContract =
  Contract
    TuningCompletionEvent
    TuningCompletionProgress
    TuningCompletion

-- | One completion record for each generation.  The plan-prescribed number of
-- self-play games is checked before this evidence value can be constructed.
data AlphaZeroGenerationCompletion = AlphaZeroGenerationCompletion
  { alphaZeroGenerationExperimentId :: Text
  , alphaZeroGenerationSelfPlayGames :: Word32
  , alphaZeroGenerationSamples :: Word64
  }
  deriving stock (Eq, Show)

data AlphaZeroArenaCompletion = AlphaZeroArenaCompletion
  { alphaZeroArenaExperimentId :: Text
  , alphaZeroArenaGames :: Word32
  , alphaZeroArenaWinRate :: FiniteMeasurement
  }
  deriving stock (Eq, Show)

data AlphaZeroCompletion = AlphaZeroCompletion
  { alphaZeroCompletedGenerations :: Map Word64 AlphaZeroGenerationCompletion
  , alphaZeroCompletedArena :: AlphaZeroArenaCompletion
  }
  deriving stock (Eq, Show)

data AlphaZeroCompletionEvent
  = AlphaZeroGenerationEvidence
      (EvidenceEvent Word64 AlphaZeroGenerationCompletion)
  | AlphaZeroArenaEvidence
      (EvidenceEvent () AlphaZeroArenaCompletion)
  deriving stock (Eq, Show)

type AlphaZeroCompletionProgress =
  ( RequirementState Word64 AlphaZeroGenerationCompletion
  , RequirementState () AlphaZeroArenaCompletion
  )

type AlphaZeroCompletionContract =
  Contract
    AlphaZeroCompletionEvent
    AlphaZeroCompletionProgress
    AlphaZeroCompletion

data WorkloadContractViolation
  = WorkloadEventPlanMismatch
      { workloadRequirement :: Text
      , workloadExpectedPlanId :: Text
      , workloadObservedPlanId :: Text
      }
  | WorkloadEventExperimentMismatch
      { workloadRequirement :: Text
      , workloadExpectedExperimentId :: Text
      , workloadObservedExperimentId :: Text
      }
  | WorkloadEventBudgetMismatch
      { workloadRequirement :: Text
      , workloadExpectedBudget :: Word64
      , workloadObservedBudget :: Word64
      }
  | WorkloadEventBudgetKindMismatch
      { workloadRequirement :: Text
      , workloadExpectedBudgetKind :: BudgetKind
      , workloadObservedBudgetKind :: BudgetKind
      }
  | WorkloadEventSeedMismatch
      { workloadRequirement :: Text
      , workloadExpectedSeed :: Maybe Word64
      , workloadObservedSeed :: Maybe Word64
      }
  | WorkloadEventRefinementFailure
      { workloadRequirement :: Text
      , workloadPlanErrors :: NonEmpty PlanError
      }
  | WorkloadEvidenceViolation ContractViolation
  deriving stock (Eq, Show)

tuningCompletionContract :: TuningPlan -> TuningCompletionContract
tuningCompletionContract plan =
  mapContract
    ( \(trials, sweep) ->
        TuningCompletion
          { tuningCompletedTrials = exactKeyedValues trials
          , tuningCompletedSweep = exactlyOneValue sweep
          }
    )
    ( productContract
        ( selectContract
            selectTuningTrial
            ( exactKeyedRange
                tuningTrialRequirement
                (tuningPlanId plan)
                (zeroBasedKeys (quantityValue (tuningPlanTrials plan)))
            )
        )
        ( selectContract
            selectTuningSweep
            (exactlyOne tuningSweepRequirement (tuningPlanId plan))
        )
    )

alphaZeroCompletionContract :: AlphaZeroPlan -> AlphaZeroCompletionContract
alphaZeroCompletionContract plan =
  mapContract
    ( \(generations, arena) ->
        AlphaZeroCompletion
          { alphaZeroCompletedGenerations = exactKeyedValues generations
          , alphaZeroCompletedArena = exactlyOneValue arena
          }
    )
    ( productContract
        ( selectContract
            selectAlphaZeroGeneration
            ( exactKeyedRange
                alphaZeroGenerationRequirement
                (alphaZeroPlanId plan)
                (zeroBasedKeys (quantityValue (alphaZeroPlanGenerations plan)))
            )
        )
        ( selectContract
            selectAlphaZeroArena
            (exactlyOne alphaZeroArenaRequirement (alphaZeroPlanId plan))
        )
    )

-- | Correlate and ingest one raw tuning event.  Trial-started events establish
-- no completion evidence, but their plan and experiment correlation is still
-- checked rather than silently accepting cross-plan telemetry.
ingestTuneEvent
  :: TuningPlan
  -> TuningCompletionProgress
  -> TuneEvent
  -> Either WorkloadContractViolation TuningCompletionProgress
ingestTuneEvent plan progress event = do
  completionEvent <- adaptTuneEvent plan event
  case completionEvent of
    Nothing -> Right progress
    Just evidence ->
      first
        WorkloadEvidenceViolation
        (ingestEvent (tuningCompletionContract plan) progress evidence)

-- | Traditional RL events are unrelated to AlphaZero completion and are total
-- no-ops.  AlphaZero generation and arena records are correlated and refined
-- before they enter the shared algebra.
ingestAlphaZeroEvent
  :: AlphaZeroPlan
  -> AlphaZeroCompletionProgress
  -> RlEvent
  -> Either WorkloadContractViolation AlphaZeroCompletionProgress
ingestAlphaZeroEvent plan progress event = do
  completionEvent <- adaptAlphaZeroEvent plan event
  case completionEvent of
    Nothing -> Right progress
    Just evidence ->
      first
        WorkloadEvidenceViolation
        (ingestEvent (alphaZeroCompletionContract plan) progress evidence)

adaptTuneEvent
  :: TuningPlan
  -> TuneEvent
  -> Either WorkloadContractViolation (Maybe TuningCompletionEvent)
adaptTuneEvent plan event =
  case event of
    TuneTrialStarted started -> do
      validateCorrelation
        tuningTrialStartedRequirement
        expectedPlanId
        expectedExperimentId
        (tsPlanId started)
        (tsExperimentHash started)
      Right Nothing
    TuneTrialFinished finished -> do
      validateCorrelation
        tuningTrialRequirement
        expectedPlanId
        expectedExperimentId
        (tfTunePlanId finished)
        (tfTuneExperimentHash finished)
      objective <-
        refineMeasurement
          tuningTrialRequirement
          "tuning-trial-objective"
          (tfTuneObjective finished)
      let key = fromIntegral (tfTuneTrial finished)
          value =
            TuningTrialCompletion
              { tuningTrialExperimentId = tfTuneExperimentHash finished
              , tuningTrialObjective = objective
              , tuningTrialPruned = tfTunePruned finished
              , tuningTrialTranscriptObjectKey =
                  tfTuneTranscriptObjectKey finished
              , tuningTrialTimestampNs = tfTuneTimestampNs finished
              }
      Just . TuningTrialEvidence
        <$> refineEvidence expectedPlanId tuningTrialRequirement key value
    TuneSweepFinished finished -> do
      _ <- validateTuningSweep tuningSweepFinishedRequirement plan finished
      Right Nothing
    TuneSweepCompleted completed -> do
      let finished = scFinished completed
          proof = scCompletedTraining completed
      bestObjective <- validateTuningSweep tuningSweepRequirement plan finished
      validateTuningCompletionProof plan proof
      let value =
            TuningSweepCompletion
              { tuningSweepExperimentId = sfExperimentHash finished
              , tuningSweepTrialsCompleted = sfTrialsCompleted finished
              , tuningSweepTrialsPruned = sfTrialsPruned finished
              , tuningSweepTrialsPromoted = sfTrialsPromoted finished
              , tuningSweepBestObjective = bestObjective
              , tuningSweepCompletedTraining = proof
              }
      Just . TuningSweepEvidence
        <$> refineEvidence expectedPlanId tuningSweepRequirement () value
 where
  expectedPlanId = tuningPlanId plan
  expectedExperimentId = runPlanExperimentId (tuningPlanRunPlan plan)

validateTuningSweep
  :: Text
  -> TuningPlan
  -> SweepFinished
  -> Either WorkloadContractViolation FiniteMeasurement
validateTuningSweep requirement plan finished = do
  validateCorrelation
    requirement
    (tuningPlanId plan)
    (runPlanExperimentId (tuningPlanRunPlan plan))
    (sfPlanId finished)
    (sfExperimentHash finished)
  validateBudget
    requirement
    (quantityValue (tuningPlanTrials plan))
    (fromIntegral (sfTrialsCompleted finished))
  validateBudget
    "tuning-sweep-promoted-trials"
    (quantityValue (tuningPlanPromotions plan))
    (fromIntegral (sfTrialsPromoted finished))
  if sfTrialsPruned finished > sfTrialsCompleted finished
    then
      Left
        WorkloadEventBudgetMismatch
          { workloadRequirement = "tuning-sweep-pruned-trials"
          , workloadExpectedBudget =
              fromIntegral (sfTrialsCompleted finished)
          , workloadObservedBudget = fromIntegral (sfTrialsPruned finished)
          }
    else Right ()
  refineMeasurement
    requirement
    "tuning-best-objective"
    (sfBestObjective finished)

validateTuningCompletionProof
  :: TuningPlan
  -> CompletedTraining
  -> Either WorkloadContractViolation ()
validateTuningCompletionProof plan completed = do
  let expectedPlanId = tuningPlanId plan
      observedPlanId = completedTrainingPlanId completed
      budget = completedTrainingBudget completed
      expectedKind = TuningTrialBudget
      observedKind = trainingBudgetKind budget
      expectedTrials = quantityValue (tuningPlanTrials plan)
      observedTrials = trainingBudgetTargetUnits budget
      expectedSeed =
        Just
          ( NonEmpty.head
              (seedCohortValues (runPlanSeeds (tuningPlanRunPlan plan)))
          )
      observedSeed = trainingBudgetSeed budget
  if observedPlanId /= expectedPlanId
    then
      Left
        WorkloadEventPlanMismatch
          { workloadRequirement = tuningSweepCompletionProofRequirement
          , workloadExpectedPlanId = planIdText expectedPlanId
          , workloadObservedPlanId = planIdText observedPlanId
          }
    else Right ()
  if observedKind /= expectedKind
    then
      Left
        WorkloadEventBudgetKindMismatch
          { workloadRequirement = tuningSweepCompletionProofRequirement
          , workloadExpectedBudgetKind = expectedKind
          , workloadObservedBudgetKind = observedKind
          }
    else Right ()
  validateBudget
    tuningSweepCompletionProofRequirement
    expectedTrials
    observedTrials
  if observedSeed /= expectedSeed
    then
      Left
        WorkloadEventSeedMismatch
          { workloadRequirement = tuningSweepCompletionProofRequirement
          , workloadExpectedSeed = expectedSeed
          , workloadObservedSeed = observedSeed
          }
    else Right ()

adaptAlphaZeroEvent
  :: AlphaZeroPlan
  -> RlEvent
  -> Either WorkloadContractViolation (Maybe AlphaZeroCompletionEvent)
adaptAlphaZeroEvent plan event =
  case event of
    RlGenerationCompleted generation -> do
      validateCorrelation
        alphaZeroGenerationRequirement
        expectedPlanId
        expectedExperimentId
        (gcPlanId generation)
        (gcExperimentHash generation)
      validateBudget
        alphaZeroGenerationRequirement
        (quantityValue (alphaZeroPlanSelfPlayGames plan))
        (fromIntegral (gcSelfPlayGames generation))
      let key = fromIntegral (gcGeneration generation)
          value =
            AlphaZeroGenerationCompletion
              { alphaZeroGenerationExperimentId = gcExperimentHash generation
              , alphaZeroGenerationSelfPlayGames = gcSelfPlayGames generation
              , alphaZeroGenerationSamples = gcSamples generation
              }
      Just . AlphaZeroGenerationEvidence
        <$> refineEvidence expectedPlanId alphaZeroGenerationRequirement key value
    RlArenaCompleted arena -> do
      validateCorrelation
        alphaZeroArenaRequirement
        expectedPlanId
        expectedExperimentId
        (acPlanId arena)
        (acExperimentHash arena)
      validateBudget
        alphaZeroArenaRequirement
        (quantityValue (alphaZeroPlanArenaGames plan))
        (fromIntegral (acArenaGames arena))
      winRate <-
        refineMeasurement
          alphaZeroArenaRequirement
          "alphazero-arena-win-rate"
          (acWinRate arena)
      let value =
            AlphaZeroArenaCompletion
              { alphaZeroArenaExperimentId = acExperimentHash arena
              , alphaZeroArenaGames = acArenaGames arena
              , alphaZeroArenaWinRate = winRate
              }
      Just . AlphaZeroArenaEvidence
        <$> refineEvidence expectedPlanId alphaZeroArenaRequirement () value
    _ -> Right Nothing
 where
  expectedPlanId = alphaZeroPlanId plan
  expectedExperimentId = runPlanExperimentId (alphaZeroPlanRunPlan plan)

selectTuningTrial
  :: TuningCompletionEvent
  -> Maybe (EvidenceEvent Word64 TuningTrialCompletion)
selectTuningTrial event =
  case event of
    TuningTrialEvidence evidence -> Just evidence
    TuningSweepEvidence _ -> Nothing

selectTuningSweep
  :: TuningCompletionEvent
  -> Maybe (EvidenceEvent () TuningSweepCompletion)
selectTuningSweep event =
  case event of
    TuningTrialEvidence _ -> Nothing
    TuningSweepEvidence evidence -> Just evidence

selectAlphaZeroGeneration
  :: AlphaZeroCompletionEvent
  -> Maybe (EvidenceEvent Word64 AlphaZeroGenerationCompletion)
selectAlphaZeroGeneration event =
  case event of
    AlphaZeroGenerationEvidence evidence -> Just evidence
    AlphaZeroArenaEvidence _ -> Nothing

selectAlphaZeroArena
  :: AlphaZeroCompletionEvent
  -> Maybe (EvidenceEvent () AlphaZeroArenaCompletion)
selectAlphaZeroArena event =
  case event of
    AlphaZeroGenerationEvidence _ -> Nothing
    AlphaZeroArenaEvidence evidence -> Just evidence

validateCorrelation
  :: Text
  -> PlanId
  -> Text
  -> Text
  -> Text
  -> Either WorkloadContractViolation ()
validateCorrelation requirement expectedPlan expectedExperiment observedPlan observedExperiment
  | observedPlan /= planIdText expectedPlan =
      Left
        WorkloadEventPlanMismatch
          { workloadRequirement = requirement
          , workloadExpectedPlanId = planIdText expectedPlan
          , workloadObservedPlanId = observedPlan
          }
  | observedExperiment /= expectedExperiment =
      Left
        WorkloadEventExperimentMismatch
          { workloadRequirement = requirement
          , workloadExpectedExperimentId = expectedExperiment
          , workloadObservedExperimentId = observedExperiment
          }
  | otherwise = Right ()

validateBudget
  :: Text
  -> Word64
  -> Word64
  -> Either WorkloadContractViolation ()
validateBudget requirement expected observed
  | observed == expected = Right ()
  | otherwise =
      Left
        WorkloadEventBudgetMismatch
          { workloadRequirement = requirement
          , workloadExpectedBudget = expected
          , workloadObservedBudget = observed
          }

refineMeasurement
  :: Text
  -> Text
  -> Double
  -> Either WorkloadContractViolation FiniteMeasurement
refineMeasurement requirement label value =
  refinementResult requirement (mkFiniteMeasurement label value)

refineEvidence
  :: (Show key)
  => PlanId
  -> Text
  -> key
  -> value
  -> Either WorkloadContractViolation (EvidenceEvent key value)
refineEvidence planId kind key value =
  refinementResult kind (evidenceEvent planId kind key value)

refinementResult
  :: Text
  -> Validation (NonEmpty PlanError) value
  -> Either WorkloadContractViolation value
refinementResult requirement validation =
  case validation of
    Failure errors ->
      Left
        WorkloadEventRefinementFailure
          { workloadRequirement = requirement
          , workloadPlanErrors = errors
          }
    Success value -> Right value

zeroBasedKeys :: Word64 -> NonEmpty Word64
zeroBasedKeys count = 0 :| [1 .. count - 1]

tuningTrialStartedRequirement :: Text
tuningTrialStartedRequirement = "tuning-trial-started"

tuningTrialRequirement :: Text
tuningTrialRequirement = "tuning-trial-finished"

tuningSweepRequirement :: Text
tuningSweepRequirement = "tuning-sweep-completed"

tuningSweepFinishedRequirement :: Text
tuningSweepFinishedRequirement = "tuning-sweep-finished"

tuningSweepCompletionProofRequirement :: Text
tuningSweepCompletionProofRequirement = "tuning-sweep-completed-training"

alphaZeroGenerationRequirement :: Text
alphaZeroGenerationRequirement = "alphazero-generation-completed"

alphaZeroArenaRequirement :: Text
alphaZeroArenaRequirement = "alphazero-arena-completed"

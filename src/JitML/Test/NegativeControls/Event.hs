{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 280 — known-invalid event streams.
--
-- Each control feeds a stream through the production reducers — the generic
-- 'JitML.Run.Contract' cardinality combinators, the live supervised and RL
-- reducers ("JitML.Test.LiveEvidence"), and the tuning and AlphaZero
-- completion contracts ("JitML.Run.WorkloadContract") — and asserts the
-- specific rejection: a typed ingest violation for an event that is invalid on
-- arrival, or the exact missing-evidence diagnostic when the stream is
-- well-formed but incomplete.  Both are compared whole, so no other defect may
-- be reported alongside the injected one.  The protobuf wire controls are the
-- exception: a decoder renders its reason as free text, so they match the
-- start of the message that names the guard that fired.  Streams are built
-- from valid events by removing, duplicating, corrupting, or re-stamping
-- exactly one, so the rejection is attributable to that one defect.
--
-- Some illegal states cannot be produced by the production adapters and are
-- covered at the boundary that stops them:
--
-- * A same-key/different-'EventId' duplicate cannot be produced by the
--   supervised, RL, tuning, or AlphaZero adapters, because each derives the
--   'EventId' from the plan, a fixed event kind, and the logical key.  The
--   duplicate rule is exercised on the generic combinators instead, where a
--   caller chooses the kind.
-- * 'completeSweep' refuses to join a tuning terminal with a proof whose plan,
--   budget kind, or trial total disagrees with the sweep, so such a terminal
--   cannot be built through the smart constructor.  The reducer re-checks the
--   proof anyway: 'SweepCompleted' is exported abstractly, but its field
--   selectors are exported too, and a record update can swap a proof in after
--   the join.  The disagreements are therefore asserted at the join (the
--   @...-at-construction@ controls) and at the reducer, through a forged
--   terminal (the @...-at-reducer@ controls).
-- * A non-finite double never survives protobuf decoding, so non-finite
--   measurements are covered both at the wire and at each reducer.
module JitML.Test.NegativeControls.Event
  ( eventControls
  )
where

import Control.Monad (foldM)
import Data.Bifunctor (first)
import Data.ByteString qualified as ByteString
import Data.Functor (void)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.Plan.Plan
  ( PlanError (..)
  , Validation
  , deriveEventIdForPlanId
  , planIdText
  , runPlanExperimentId
  , validationToEither
  )
import JitML.Plan.Workload
  ( alphaZeroPlanId
  , alphaZeroPlanRunPlan
  , tuningPlanId
  , tuningPlanRunPlan
  )
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Run.Contract
  ( Contract
  , ContractViolation (..)
  , MissingEvidence (..)
  , atLeastOne
  , evidenceEvent
  , exactKeyedRange
  , exactlyOne
  , finishContract
  , ingestEvent
  , initialProgress
  , productContract
  )
import JitML.Run.WorkloadContract
  ( WorkloadContractViolation (..)
  , alphaZeroCompletionContract
  , ingestAlphaZeroEvent
  , ingestTuneEvent
  , tuningCompletionContract
  )
import JitML.Test.ContractFixtures
  ( AtLeastTextContract
  , ExactIntContract
  , ExactlyTextContract
  , eventId
  , planA
  , planB
  , refinedEvidence
  )
import JitML.Test.ControlFixtures
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Test.NegativeControls.Core
import JitML.Training.Budget qualified as TrainingBudget

-- | Every event control, grouped by the defect family it injects.
eventControls :: [NegativeControl]
eventControls =
  genericControls
    <> supervisedControls
    <> rlControls
    <> tuningControls
    <> alphaZeroControls
    <> malformedControls
    <> completionBudgetControls

event :: Text -> Text -> ControlOutcome -> NegativeControl
event = pureControl Event

-- Stream helpers -------------------------------------------------------------

-- | Ingest the accepted prefix, then one further event.  A prefix that is
-- itself rejected is a broken fixture ('Left'), not a verdict; otherwise the
-- result is the reducer's answer to the last event.
ingestThen
  :: (Show violation)
  => (progress -> event -> Either violation progress)
  -> progress
  -> [event]
  -> event
  -> Either Text (Either violation progress)
ingestThen ingest initial prefix offender =
  case foldM ingest initial prefix of
    Left violation ->
      Left ("the accepted prefix of the fixture was rejected: " <> Text.pack (show violation))
    Right progress -> Right (ingest progress offender)

-- | The last event of the stream must be rejected with exactly this violation.
rejectsLast
  :: (Eq violation, Show violation)
  => violation
  -> Either Text (Either violation progress)
  -> ControlOutcome
rejectsLast expected fixture = withFixture fixture (rejectedWith expected)

-- | Ingest a stream in which every event is accepted, then ask for completion.
-- The live reducers take protocol events but their contracts are over an
-- internal event sum, so the ingested and the contract's event types differ.
incompleteAfter
  :: (Show violation)
  => (progress -> raw -> Either violation progress)
  -> Contract internal progress evidence
  -> [raw]
  -> Either Text (Validation (NonEmpty MissingEvidence) evidence)
incompleteAfter ingest contract events =
  case foldM ingest (initialProgress contract) events of
    Left violation ->
      Left ("the fixture stream was rejected on ingest: " <> Text.pack (show violation))
    Right progress -> Right (finishContract contract progress)

-- | Completion must fail with exactly this missing-evidence list.
missingExactly
  :: NonEmpty MissingEvidence
  -> Either Text (Validation (NonEmpty MissingEvidence) evidence)
  -> ControlOutcome
missingExactly expected fixture =
  withFixture fixture (rejectedWith expected . validationToEither)

renderError :: (Show err) => Text -> err -> Text
renderError context err = context <> ": " <> Text.pack (show err)

-- Generic contract combinators -------------------------------------------------

-- | One value of each cardinality combinator, all bound to 'planA'.
exactlyOneTerminal :: ExactlyTextContract
exactlyOneTerminal = exactlyOne "terminal-checkpoint" planA

atLeastOneTelemetry :: AtLeastTextContract
atLeastOneTelemetry = atLeastOne "telemetry" planA

exactCohort :: ExactIntContract
exactCohort = exactKeyedRange "evaluation-cohort" planA (0 :| [1, 2])

genericControls :: [NegativeControl]
genericControls =
  [ event
      "event-wrong-plan-exactly-one"
      "an event stamped with another plan must be rejected before it is recorded (exactly-one)"
      ( rejectsLast
          (WrongPlan "terminal-checkpoint" planA planB)
          ( ingestThen
              (ingestEvent exactlyOneTerminal)
              (initialProgress exactlyOneTerminal)
              []
              (refinedEvidence planB "checkpoint" () ("manifest-a" :: Text))
          )
      )
  , event
      "event-wrong-plan-at-least-one"
      "an event stamped with another plan must be rejected before it is recorded (at-least-one)"
      ( rejectsLast
          (WrongPlan "telemetry" planA planB)
          ( ingestThen
              (ingestEvent atLeastOneTelemetry)
              (initialProgress atLeastOneTelemetry)
              []
              (refinedEvidence planB "telemetry" (0 :: Int) ("loss=1.0" :: Text))
          )
      )
  , event
      "event-wrong-plan-exact-keyed"
      "an event stamped with another plan must be rejected before it is recorded (exact-keyed)"
      ( rejectsLast
          (WrongPlan "evaluation-cohort" planA planB)
          ( ingestThen
              (ingestEvent exactCohort)
              (initialProgress exactCohort)
              []
              (refinedEvidence planB "evaluation" (0 :: Int) (1.0 :: Double))
          )
      )
  , event
      "event-conflicting-duplicate-same-event-id-exactly-one"
      "the same EventId carrying a different value must be rejected (exactly-one)"
      ( rejectsLast
          (ConflictingDuplicate "terminal-checkpoint" "()" checkpointId checkpointId)
          ( ingestThen
              (ingestEvent exactlyOneTerminal)
              (initialProgress exactlyOneTerminal)
              [refinedEvidence planA "checkpoint" () ("manifest-a" :: Text)]
              (refinedEvidence planA "checkpoint" () "manifest-b")
          )
      )
  , event
      "event-conflicting-duplicate-same-key-different-event-id-exactly-one"
      "a second EventId for the already-populated key must be rejected (exactly-one)"
      ( rejectsLast
          (ConflictingDuplicate "terminal-checkpoint" "()" checkpointId alternateId)
          ( ingestThen
              (ingestEvent exactlyOneTerminal)
              (initialProgress exactlyOneTerminal)
              [refinedEvidence planA "checkpoint" () ("manifest-a" :: Text)]
              (refinedEvidence planA "checkpoint-alternate" () "manifest-a")
          )
      )
  , event
      "event-conflicting-duplicate-same-key-different-event-id-exact-keyed"
      "a second EventId for an already-populated key must be rejected even with an equal value (exact-keyed)"
      ( rejectsLast
          (ConflictingDuplicate "evaluation-cohort" "0" evaluationId telemetryId)
          ( ingestThen
              (ingestEvent exactCohort)
              (initialProgress exactCohort)
              [refinedEvidence planA "evaluation" (0 :: Int) (10.0 :: Double)]
              (refinedEvidence planA "telemetry" 0 10.0)
          )
      )
  , event
      "event-out-of-range-key-exact-keyed"
      "a key outside the declared range must be rejected on arrival (exact-keyed)"
      ( rejectsLast
          (OutOfRangeKey "evaluation-cohort" "3")
          ( ingestThen
              (ingestEvent exactCohort)
              (initialProgress exactCohort)
              []
              (refinedEvidence planA "evaluation" (3 :: Int) (40.0 :: Double))
          )
      )
  , event
      "event-gap-exact-keyed-ascending"
      "the missing keys of an exact range are reported as the ascending difference"
      ( missingExactly
          (MissingKeys "evaluation-cohort" ("1" :| ["2"]) :| [])
          ( incompleteAfter
              (ingestEvent exactCohort)
              exactCohort
              [refinedEvidence planA "evaluation" (0 :: Int) (10.0 :: Double)]
          )
      )
  , event
      "event-missing-terminal-exactly-one"
      "an exactly-one requirement with no event is incomplete, not vacuously satisfied"
      ( missingExactly
          (MissingExactlyOne "terminal-checkpoint" :| [])
          (incompleteAfter (ingestEvent exactlyOneTerminal) exactlyOneTerminal [])
      )
  , event
      "event-missing-terminal-at-least-one"
      "an at-least-one requirement with no event is incomplete, not vacuously satisfied"
      ( missingExactly
          (MissingAtLeastOne "telemetry" :| [])
          (incompleteAfter (ingestEvent atLeastOneTelemetry) atLeastOneTelemetry [])
      )
  , event
      "event-missing-terminal-product-diagnostics-left-then-right"
      "a product of two requirements reports both missing diagnostics, left first"
      ( missingExactly
          (MissingExactlyOne "terminal-checkpoint" :| [MissingExactlyOne "terminal-metric"])
          ( incompleteAfter
              (ingestEvent productOfTwo)
              productOfTwo
              []
          )
      )
  ]
 where
  productOfTwo =
    productContract
      exactlyOneTerminal
      (exactlyOne "terminal-metric" planA :: ExactlyTextContract)
  checkpointId = eventId planA "checkpoint" "()"
  alternateId = eventId planA "checkpoint-alternate" "()"
  evaluationId = eventId planA "evaluation" "0"
  telemetryId = eventId planA "telemetry" "0"

-- Supervised (live) ------------------------------------------------------------

supervisedExperiment :: Text
supervisedExperiment = "control-supervised"

-- | The live supervised contract for a 3-epoch plan under 'planA'.
supervisedContract :: Either Text LiveEvidence.SupervisedLiveContract
supervisedContract = first (renderError "supervised contract") (LiveEvidence.supervisedLiveContract planA 3)

supervisedIngest
  :: LiveEvidence.SupervisedLiveContract
  -> LiveEvidence.SupervisedLiveProgress
  -> Training.TrainingEvent
  -> Either LiveEvidence.LiveEvidenceViolation LiveEvidence.SupervisedLiveProgress
supervisedIngest = LiveEvidence.ingestSupervisedLiveEvent planA supervisedExperiment

-- | A well-formed epoch event with equal training and validation loss.
epoch :: Word32 -> Double -> Training.TrainingEvent
epoch number loss = supervisedEpochWithLosses supervisedExperiment number loss loss

-- | A completed checkpoint for 'planA' of @units@ epochs.
checkpointOfEpochs :: Word64 -> Either Text Training.TrainingEvent
checkpointOfEpochs units =
  supervisedCompletedCheckpointFor
    planA
    TrainingBudget.SupervisedEpochBudget
    units
    supervisedExperiment

supervisedControls :: [NegativeControl]
supervisedControls =
  [ event
      "event-gap-supervised-epoch"
      "a supervised run whose terminal epoch snapshot never arrived is incomplete, naming the missing epoch"
      ( withFixture ((,) <$> supervisedContract <*> checkpointOfEpochs 3) $ \(contract, checkpoint) ->
          missingExactly
            (MissingKeys "supervised-terminal-epoch" ("3" :| []) :| [])
            (incompleteAfter (supervisedIngest contract) contract [checkpoint])
      )
  , event
      "event-missing-terminal-supervised-checkpoint"
      "a supervised run without its completed checkpoint is incomplete"
      ( withFixture supervisedContract $ \contract ->
          missingExactly
            (MissingExactlyOne "supervised-completed-checkpoint" :| [])
            (incompleteAfter (supervisedIngest contract) contract [epoch 3 0.25])
      )
  , event
      "event-conflicting-duplicate-supervised-epoch"
      "the terminal epoch redelivered with a different loss must be rejected"
      ( withFixture supervisedContract $ \contract ->
          rejectsLast
            ( LiveEvidence.LiveEvidenceContractViolation
                (ConflictingDuplicate "supervised-terminal-epoch" "3" epochId epochId)
            )
            ( ingestThen
                (supervisedIngest contract)
                (initialProgress contract)
                [epoch 3 0.25]
                (epoch 3 0.5)
            )
      )
  , event
      "event-conflicting-duplicate-supervised-checkpoint"
      "a second, different completed checkpoint must be rejected"
      ( withFixture ((,,) <$> supervisedContract <*> checkpointOfEpochs 3 <*> checkpointOfEpochs 5) $
          \(contract, first', second) ->
            rejectsLast
              ( LiveEvidence.LiveEvidenceContractViolation
                  (ConflictingDuplicate "supervised-completed-checkpoint" "()" checkpointId checkpointId)
              )
              (ingestThen (supervisedIngest contract) (initialProgress contract) [first'] second)
      )
  , event
      "event-wrong-plan-supervised-checkpoint"
      "a completed checkpoint proven under another plan must be rejected"
      ( withFixture
          ( (,)
              <$> supervisedContract
              <*> supervisedCompletedCheckpointFor planB TrainingBudget.SupervisedEpochBudget 3 supervisedExperiment
          )
          $ \(contract, checkpoint) ->
            rejectsLast
              (LiveEvidence.LiveEvidencePlanMismatch planA planB)
              (ingestThen (supervisedIngest contract) (initialProgress contract) [] checkpoint)
      )
  , event
      "event-completion-before-budget-supervised-terminal-epoch"
      "a terminal epoch below the planned epoch count must be rejected on arrival"
      ( withFixture supervisedContract $ \contract ->
          rejectsLast
            ( LiveEvidence.LiveEvidenceContractViolation
                (OutOfRangeKey "supervised-terminal-epoch" "2")
            )
            (ingestThen (supervisedIngest contract) (initialProgress contract) [] (epoch 2 0.5))
      )
  , event
      "event-out-of-range-supervised-terminal-epoch"
      "a terminal epoch beyond the planned epoch count must be rejected on arrival"
      ( withFixture supervisedContract $ \contract ->
          rejectsLast
            ( LiveEvidence.LiveEvidenceContractViolation
                (OutOfRangeKey "supervised-terminal-epoch" "4")
            )
            (ingestThen (supervisedIngest contract) (initialProgress contract) [] (epoch 4 0.5))
      )
  , nonFiniteEpoch
      "event-nonfinite-supervised-training-loss-nan"
      "a NaN training loss must be rejected"
      (0 / 0)
      1.0
      "training-loss"
  , nonFiniteEpoch
      "event-nonfinite-supervised-validation-loss-nan"
      "a NaN validation loss must be rejected"
      1.0
      (0 / 0)
      "validation-loss"
  , nonFiniteEpoch
      "event-nonfinite-supervised-validation-loss-infinity"
      "an infinite validation loss must be rejected"
      1.0
      (1 / 0)
      "validation-loss"
  , event
      "event-foreign-experiment-cannot-complete-supervised-evidence"
      "epoch and checkpoint events for another experiment must not satisfy this experiment's requirements"
      ( withFixture ((,) <$> supervisedContract <*> checkpointFor "some-other-experiment") $
          \(contract, foreignCheckpoint) ->
            missingExactly
              ( MissingKeys "supervised-terminal-epoch" ("3" :| [])
                  :| [MissingExactlyOne "supervised-completed-checkpoint"]
              )
              ( incompleteAfter
                  (supervisedIngest contract)
                  contract
                  [supervisedEpochWithLosses "some-other-experiment" 3 0.25 0.25, foreignCheckpoint]
              )
      )
  , event
      "event-workload-reported-failure-supervised"
      "a failure the workload reports for this experiment must be rejected, not skipped"
      ( withFixture supervisedContract $ \contract ->
          rejectsLast
            (LiveEvidence.LiveWorkloadReportedFailure reportedFailure)
            ( ingestThen
                (supervisedIngest contract)
                (initialProgress contract)
                []
                (Training.TrainingFailure reportedFailure)
            )
      )
  ]
 where
  epochId = eventId planA "training-epoch" "3"
  checkpointId = eventId planA "training-completed-checkpoint" "()"
  checkpointFor =
    supervisedCompletedCheckpointFor planA TrainingBudget.SupervisedEpochBudget 3
  reportedFailure =
    Training.TrainingFailed
      { Training.tfExperimentHash = supervisedExperiment
      , Training.tfErrorCode = "worker-oom"
      , Training.tfErrorText = "worker ran out of memory"
      , Training.tfTimestampNs = 9
      }
  nonFiniteEpoch name description loss validationLoss label =
    event name description $
      withFixture supervisedContract $ \contract ->
        rejectsLast
          (LiveEvidence.LiveEvidenceMalformed (NonFiniteMeasurement label :| []))
          ( ingestThen
              (supervisedIngest contract)
              (initialProgress contract)
              []
              (supervisedEpochWithLosses supervisedExperiment 3 loss validationLoss)
          )

-- Traditional RL (live) --------------------------------------------------------

rlExperiment :: Text
rlExperiment = "control-rl"

rlPlanText :: Text
rlPlanText = planIdText planA

rlIngest
  :: LiveEvidence.RlLiveContract
  -> LiveEvidence.RlLiveProgress
  -> Rl.RlEvent
  -> Either LiveEvidence.LiveEvidenceViolation LiveEvidence.RlLiveProgress
rlIngest = LiveEvidence.ingestRlLiveEvent planA rlExperiment

-- | The contract for an @episodes@-member evaluation cohort.
rlContractFor :: Word32 -> Either Text LiveEvidence.RlLiveContract
rlContractFor episodes =
  first (renderError "RL contract") (LiveEvidence.rlLiveContract planA episodes)

-- | Evaluation episode @n@ with a reward equal to @n + 1@.
episodeEvent :: Word64 -> Rl.RlEvent
episodeEvent n = rlEvaluationEvent rlPlanText rlExperiment n (fromIntegral n + 1) 4

-- | The median of rewards @1 .. n@.
medianOfFirst :: Word64 -> Double
medianOfFirst n = (1 + fromIntegral n) / 2

-- | A completed RL checkpoint for 'planA' of @units@ environment steps.
rlCheckpointOfSteps :: Word64 -> Either Text Rl.RlEvent
rlCheckpointOfSteps units =
  rlCompletedCheckpointFor planA TrainingBudget.RlEnvironmentStepBudget units rlExperiment

rlControls :: [NegativeControl]
rlControls =
  [ event
      "event-gap-rl-evaluation-episode"
      "an evaluation cohort missing one episode is incomplete, naming it"
      ( withFixture ((,) <$> rlContractFor 4 <*> rlCheckpointOfSteps 4) $ \(contract, checkpoint) ->
          missingExactly
            (MissingKeys "rl-final-evaluation" ("2" :| []) :| [])
            ( incompleteAfter
                (rlIngest contract)
                contract
                ( [episodeEvent 0, episodeEvent 1, episodeEvent 3]
                    <> [rlMetricEvent rlPlanText rlExperiment (medianOfFirst 4), checkpoint]
                )
            )
      )
  , event
      "event-gap-rl-evaluation-episodes-ascending"
      "several missing episodes are reported in numeric ascending order, not lexicographic order"
      ( withFixture ((,) <$> rlContractFor 12 <*> rlCheckpointOfSteps 4) $ \(contract, checkpoint) ->
          missingExactly
            ( MissingKeys
                "rl-final-evaluation"
                ("0" :| ["2", "4", "5", "6", "7", "8", "9", "10", "11"])
                :| []
            )
            ( incompleteAfter
                (rlIngest contract)
                contract
                ( [episodeEvent 1, episodeEvent 3]
                    <> [rlMetricEvent rlPlanText rlExperiment 2.0, checkpoint]
                )
            )
      )
  , event
      "event-missing-terminal-rl-checkpoint"
      "an RL run with a complete cohort and metric but no completed checkpoint is incomplete"
      ( withFixture (rlContractFor 4) $ \contract ->
          missingExactly
            (MissingExactlyOne "rl-completed-checkpoint" :| [])
            ( incompleteAfter
                (rlIngest contract)
                contract
                ( fmap episodeEvent [0 .. 3]
                    <> [rlMetricEvent rlPlanText rlExperiment (medianOfFirst 4)]
                )
            )
      )
  , event
      "event-missing-terminal-rl-metric"
      "an RL run with a complete cohort and checkpoint but no median metric is incomplete"
      ( withFixture ((,) <$> rlContractFor 4 <*> rlCheckpointOfSteps 4) $ \(contract, checkpoint) ->
          missingExactly
            (MissingExactlyOne "rl-median-final-reward" :| [])
            (incompleteAfter (rlIngest contract) contract (fmap episodeEvent [0 .. 3] <> [checkpoint]))
      )
  , event
      "event-conflicting-duplicate-rl-evaluation"
      "an evaluation episode redelivered with a different reward must be rejected"
      ( withFixture (rlContractFor 4) $ \contract ->
          rejectsLast
            ( LiveEvidence.LiveEvidenceContractViolation
                (ConflictingDuplicate "rl-final-evaluation" "1" evaluationId evaluationId)
            )
            ( ingestThen
                (rlIngest contract)
                (initialProgress contract)
                [rlEvaluationEvent rlPlanText rlExperiment 1 1.0 4]
                (rlEvaluationEvent rlPlanText rlExperiment 1 3.0 4)
            )
      )
  , event
      "event-conflicting-duplicate-rl-metric"
      "the median metric redelivered with a different value must be rejected"
      ( withFixture (rlContractFor 4) $ \contract ->
          rejectsLast
            ( LiveEvidence.LiveEvidenceContractViolation
                (ConflictingDuplicate "rl-median-final-reward" "()" metricId metricId)
            )
            ( ingestThen
                (rlIngest contract)
                (initialProgress contract)
                [rlMetricEvent rlPlanText rlExperiment 2.0]
                (rlMetricEvent rlPlanText rlExperiment 3.0)
            )
      )
  , event
      "event-conflicting-duplicate-rl-checkpoint"
      "a second, different completed RL checkpoint must be rejected"
      ( withFixture ((,,) <$> rlContractFor 4 <*> rlCheckpointOfSteps 4 <*> rlCheckpointOfSteps 8) $
          \(contract, first', second) ->
            rejectsLast
              ( LiveEvidence.LiveEvidenceContractViolation
                  (ConflictingDuplicate "rl-completed-checkpoint" "()" checkpointId checkpointId)
              )
              (ingestThen (rlIngest contract) (initialProgress contract) [first'] second)
      )
  , event
      "event-wrong-plan-rl-evaluation"
      "an evaluation outcome stamped with another plan must be rejected"
      ( withFixture (rlContractFor 4) $ \contract ->
          rejectsLast
            (LiveEvidence.LiveEvidenceRlPlanMismatch rlPlanText (planIdText planB))
            ( ingestThen
                (rlIngest contract)
                (initialProgress contract)
                []
                (rlEvaluationEvent (planIdText planB) rlExperiment 0 1.0 4)
            )
      )
  , event
      "event-wrong-plan-rl-metric"
      "a median metric stamped with another plan must be rejected"
      ( withFixture (rlContractFor 4) $ \contract ->
          rejectsLast
            (LiveEvidence.LiveEvidenceRlPlanMismatch rlPlanText (planIdText planB))
            ( ingestThen
                (rlIngest contract)
                (initialProgress contract)
                []
                (rlMetricEvent (planIdText planB) rlExperiment 2.0)
            )
      )
  , event
      "event-wrong-plan-rl-checkpoint"
      "a completed checkpoint proven under another plan must be rejected"
      ( withFixture
          ( (,)
              <$> rlContractFor 4
              <*> rlCompletedCheckpointFor planB TrainingBudget.RlEnvironmentStepBudget 4 rlExperiment
          )
          $ \(contract, checkpoint) ->
            rejectsLast
              (LiveEvidence.LiveEvidencePlanMismatch planA planB)
              (ingestThen (rlIngest contract) (initialProgress contract) [] checkpoint)
      )
  , event
      "event-malformed-zero-step-episode"
      "an evaluation episode that took zero steps must be rejected"
      ( withFixture (rlContractFor 4) $ \contract ->
          rejectsLast
            (LiveEvidence.LiveEvidenceZeroSteps 0)
            ( ingestThen
                (rlIngest contract)
                (initialProgress contract)
                []
                (rlEvaluationEvent rlPlanText rlExperiment 0 1.0 0)
            )
      )
  , event
      "event-out-of-range-rl-evaluation-episode"
      "an evaluation episode beyond the cohort must be rejected on arrival"
      ( withFixture (rlContractFor 4) $ \contract ->
          rejectsLast
            ( LiveEvidence.LiveEvidenceContractViolation
                (OutOfRangeKey "rl-final-evaluation" "4")
            )
            (ingestThen (rlIngest contract) (initialProgress contract) [] (episodeEvent 4))
      )
  , nonFiniteRl
      "event-nonfinite-rl-reward-nan"
      "a NaN evaluation reward must be rejected"
      (rlEvaluationEvent rlPlanText rlExperiment 0 (0 / 0) 4)
      "rl-final-reward"
  , nonFiniteRl
      "event-nonfinite-rl-reward-infinity"
      "an infinite evaluation reward must be rejected"
      (rlEvaluationEvent rlPlanText rlExperiment 0 (1 / 0) 4)
      "rl-final-reward"
  , nonFiniteRl
      "event-nonfinite-rl-median-metric-nan"
      "a NaN median metric must be rejected"
      (rlMetricEvent rlPlanText rlExperiment (0 / 0))
      "rl-median-final-reward"
  , event
      "event-completion-rl-median-mismatch"
      "a reported median that is not the median of the evaluation cohort must not complete the run"
      ( withFixture ((,) <$> rlContractFor 2 <*> rlCheckpointOfSteps 4) $ \(contract, checkpoint) ->
          missingExactly
            ( InvalidEvidence
                "RL median_final_reward does not match the exact evaluation cohort: reported 99.0, derived 1.5"
                :| []
            )
            ( incompleteAfter
                (rlIngest contract)
                contract
                ( fmap episodeEvent [0, 1]
                    <> [rlMetricEvent rlPlanText rlExperiment 99.0, checkpoint]
                )
            )
      )
  , event
      "event-foreign-experiment-cannot-complete-rl-evidence"
      "RL events for another experiment must not satisfy this experiment's requirements"
      ( withFixture (rlContractFor 1) $ \contract ->
          missingExactly
            ( MissingKeys "rl-final-evaluation" ("0" :| [])
                :| [ MissingExactlyOne "rl-median-final-reward"
                   , MissingExactlyOne "rl-completed-checkpoint"
                   ]
            )
            ( incompleteAfter
                (rlIngest contract)
                contract
                [ rlEvaluationEvent rlPlanText "some-other-experiment" 0 1.0 4
                , rlMetricEvent rlPlanText "some-other-experiment" 1.0
                ]
            )
      )
  ]
 where
  evaluationId = eventId planA "rl-final-evaluation" "1"
  metricId = eventId planA "rl-median-final-reward" "()"
  checkpointId = eventId planA "rl-completed-checkpoint" "()"
  nonFiniteRl name description offending label =
    event name description $
      withFixture (rlContractFor 4) $ \contract ->
        rejectsLast
          (LiveEvidence.LiveEvidenceMalformed (NonFiniteMeasurement label :| []))
          (ingestThen (rlIngest contract) (initialProgress contract) [] offending)

-- Tuning -----------------------------------------------------------------------

tuningControls :: [NegativeControl]
tuningControls =
  [ tuning
      "event-gap-tuning-trial"
      "a sweep missing one trial's result is incomplete, naming the trial"
      ( \plan -> do
          completed <- completedSweep plan 3 3
          pure
            ( missingFor
                plan
                (MissingKeys "tuning-trial-finished" ("1" :| []) :| [])
                [trial plan 0, trial plan 2, completed]
            )
      )
  , tuning
      "event-missing-terminal-tuning-sweep"
      "trial results without any sweep terminal are incomplete"
      ( \plan ->
          pure
            ( missingFor
                plan
                (MissingExactlyOne "tuning-sweep-completed" :| [])
                (fmap (trial plan) [0, 1, 2])
            )
      )
  , tuning
      "event-missing-terminal-tuning-proof-free-sweep"
      "a validated sweep terminal without its completed-training proof cannot complete the run"
      ( \plan ->
          pure
            ( missingFor
                plan
                (MissingExactlyOne "tuning-sweep-completed" :| [])
                (fmap (trial plan) [0, 1, 2] <> [Tune.TuneSweepFinished (sweepFinishedRecord plan 3 1 0.25)])
            )
      )
  , tuning
      "event-conflicting-duplicate-tuning-trial"
      "a trial redelivered with a different objective must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEvidenceViolation
                    ( ConflictingDuplicate
                        "tuning-trial-finished"
                        "0"
                        (eventId (tuningPlanId plan) "tuning-trial-finished" "0")
                        (eventId (tuningPlanId plan) "tuning-trial-finished" "0")
                    )
                )
                [tuneTrialFinishedEvent plan 0 1.0]
                (tuneTrialFinishedEvent plan 0 9.0)
            )
      )
  , tuning
      "event-conflicting-duplicate-tuning-sweep"
      "a completed sweep redelivered with a different best objective must be rejected"
      ( \plan -> do
          first' <- completedSweepWith plan 0.25
          second <- completedSweepWith plan 0.5
          pure
            ( rejectsTuning
                plan
                ( WorkloadEvidenceViolation
                    ( ConflictingDuplicate
                        "tuning-sweep-completed"
                        "()"
                        (eventId (tuningPlanId plan) "tuning-sweep-completed" "()")
                        (eventId (tuningPlanId plan) "tuning-sweep-completed" "()")
                    )
                )
                [first']
                second
            )
      )
  , tuning
      "event-wrong-plan-tuning-trial"
      "a trial result stamped with another plan must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventPlanMismatch
                    "tuning-trial-finished"
                    (planIdText (tuningPlanId plan))
                    "wrong-plan"
                )
                []
                (retargetTrial "wrong-plan" (tuneTrialFinishedEvent plan 0 1.0))
            )
      )
  , tuning
      "event-wrong-plan-tuning-trial-started"
      "a trial-started notice stamped with another plan must be rejected, not silently accepted"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventPlanMismatch
                    "tuning-trial-started"
                    (planIdText (tuningPlanId plan))
                    "wrong-plan"
                )
                []
                (retargetStarted "wrong-plan" (tuneTrialStartedEvent plan 0))
            )
      )
  , tuning
      "event-wrong-plan-tuning-sweep-finished"
      "a sweep terminal stamped with another plan must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventPlanMismatch
                    "tuning-sweep-finished"
                    (planIdText (tuningPlanId plan))
                    "wrong-plan"
                )
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 3 1 0.25) {Tune.sfPlanId = "wrong-plan"})
            )
      )
  , tuning
      "event-wrong-experiment-tuning-trial"
      "a trial result for another experiment under this plan must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventExperimentMismatch
                    "tuning-trial-finished"
                    (runPlanExperimentId (tuningPlanRunPlan plan))
                    "some-other-experiment"
                )
                []
                (retargetTrialExperiment "some-other-experiment" (tuneTrialFinishedEvent plan 0 1.0))
            )
      )
  , tuning
      "event-out-of-range-tuning-trial"
      "a trial index beyond the planned trial count must be rejected on arrival"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                (WorkloadEvidenceViolation (OutOfRangeKey "tuning-trial-finished" "3"))
                []
                (tuneTrialFinishedEvent plan 3 1.0)
            )
      )
  , tuning
      "event-nonfinite-tuning-trial-objective"
      "a NaN trial objective must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventRefinementFailure
                    "tuning-trial-finished"
                    (NonFiniteMeasurement "tuning-trial-objective" :| [])
                )
                []
                (tuneTrialFinishedEvent plan 0 (0 / 0))
            )
      )
  , tuning
      "event-nonfinite-tuning-best-objective"
      "an infinite best objective in a sweep terminal must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventRefinementFailure
                    "tuning-sweep-finished"
                    (NonFiniteMeasurement "tuning-best-objective" :| [])
                )
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 3 1 (1 / 0)))
            )
      )
  , tuning
      "event-completion-before-budget-tuning-sweep-trials"
      "a sweep that finished 2 of the planned 3 trials must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-finished" 3 2)
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 2 1 0.25))
            )
      )
  , tuning
      "event-completion-before-budget-tuning-completed-sweep-trials"
      "a completed sweep that finished 2 of the planned 3 trials must be rejected even with a matching 2-trial proof"
      ( \plan -> do
          shortSweep <- completedSweep plan 2 2
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-completed" 3 2)
                []
                shortSweep
            )
      )
  , tuning
      "event-completion-before-budget-tuning-promoted"
      "a sweep that promoted 0 of the planned 1 trial must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-promoted-trials" 1 0)
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 3 0 0.25))
            )
      )
  , tuning
      "event-completion-beyond-budget-tuning-sweep-trials"
      "a sweep that finished 4 trials of a planned 3 must be rejected: the budget is exact, not a floor"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-finished" 3 4)
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 4 1 0.25))
            )
      )
  , tuning
      "event-completion-beyond-budget-tuning-promoted"
      "a sweep that promoted 2 trials of a planned 1 must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-promoted-trials" 1 2)
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 3 2 0.25))
            )
      )
  , tuning
      "event-completion-before-budget-tuning-pruned-beyond-completed"
      "a sweep that pruned more trials than it completed must be rejected"
      ( \plan ->
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-pruned-trials" 3 4)
                []
                (Tune.TuneSweepFinished (sweepFinishedRecord plan 3 1 0.25) {Tune.sfTrialsPruned = 4})
            )
      )
  , tuning
      "event-completion-tuning-proof-seed-mismatch"
      "a completed sweep whose proof carries another deterministic seed must be rejected"
      ( \plan -> do
          proofOtherSeed <-
            sweepCompletedEvent
              (sweepFinishedRecord plan 3 1 0.25)
              (tuningPlanId plan)
              TrainingBudget.TuningTrialBudget
              3
              (Just 99)
          pure
            ( rejectsTuning
                plan
                (WorkloadEventSeedMismatch "tuning-sweep-completed-training" (tuningSeed plan) (Just 99))
                []
                proofOtherSeed
            )
      )
  , tuning
      "event-completion-tuning-proof-plan-mismatch-at-construction"
      "a sweep terminal cannot be joined with a proof stamped for another plan"
      ( \plan ->
          pure
            ( rejectedWith
                "sweep plan_id does not match completed-training plan identity"
                ( void
                    ( sweepCompletedEvent
                        (sweepFinishedRecord plan 3 1 0.25)
                        planB
                        TrainingBudget.TuningTrialBudget
                        3
                        (tuningSeed plan)
                    )
                )
            )
      )
  , tuning
      "event-completion-tuning-proof-unit-mismatch-at-construction"
      "a sweep terminal cannot be joined with a proof denominated in epochs"
      ( \plan ->
          pure
            ( rejectedWith
                "sweep completion requires a tuning-trial budget"
                ( void
                    ( sweepCompletedEvent
                        (sweepFinishedRecord plan 3 1 0.25)
                        (tuningPlanId plan)
                        TrainingBudget.SupervisedEpochBudget
                        3
                        (tuningSeed plan)
                    )
                )
            )
      )
  , tuning
      "event-completion-before-budget-tuning-proof-target-at-construction"
      "a sweep terminal cannot be joined with a proof whose target is below its trial count"
      ( \plan ->
          pure
            ( rejectedWith
                "completed sweep trials do not match completed-training target units"
                ( void
                    ( sweepCompletedEvent
                        (sweepFinishedRecord plan 3 1 0.25)
                        (tuningPlanId plan)
                        TrainingBudget.TuningTrialBudget
                        2
                        (tuningSeed plan)
                    )
                )
            )
      )
  , tuning
      "event-completion-tuning-proof-plan-mismatch-at-reducer"
      "a completed sweep whose proof was swapped, after the join, for one stamped with another plan must be rejected by the reducer"
      ( \plan -> do
          forged <- forgedSweep plan planB TrainingBudget.TuningTrialBudget 3 (tuningSeed plan)
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventPlanMismatch
                    "tuning-sweep-completed-training"
                    (planIdText (tuningPlanId plan))
                    (planIdText planB)
                )
                []
                forged
            )
      )
  , tuning
      "event-completion-tuning-proof-unit-mismatch-at-reducer"
      "a completed sweep whose proof was swapped, after the join, for one denominated in epochs must be rejected by the reducer"
      ( \plan -> do
          forged <-
            forgedSweep
              plan
              (tuningPlanId plan)
              TrainingBudget.SupervisedEpochBudget
              3
              (tuningSeed plan)
          pure
            ( rejectsTuning
                plan
                ( WorkloadEventBudgetKindMismatch
                    "tuning-sweep-completed-training"
                    TrainingBudget.TuningTrialBudget
                    TrainingBudget.SupervisedEpochBudget
                )
                []
                forged
            )
      )
  , tuning
      "event-completion-before-budget-tuning-proof-target-at-reducer"
      "a completed sweep whose proof was swapped, after the join, for one that targets 2 of the planned 3 trials must be rejected by the reducer"
      ( \plan -> do
          forged <-
            forgedSweep
              plan
              (tuningPlanId plan)
              TrainingBudget.TuningTrialBudget
              2
              (tuningSeed plan)
          pure
            ( rejectsTuning
                plan
                (WorkloadEventBudgetMismatch "tuning-sweep-completed-training" 3 2)
                []
                forged
            )
      )
  ]
 where
  tuning name description build =
    event name description $
      withFixture tuningPlanFixture $ \plan ->
        withFixture (build plan) id
  -- Trial @n@ finishes with objective 1 / (n + 1), as a real sweep's improving trials do.
  trial plan number = tuneTrialFinishedEvent plan number (1 / fromIntegral (number + 1))
  -- A completed sweep of @completed@ trials proven by a @proof@-trial budget.
  completedSweep plan completed proof =
    sweepCompletedEvent
      (sweepFinishedRecord plan completed 1 0.25)
      (tuningPlanId plan)
      TrainingBudget.TuningTrialBudget
      proof
      (tuningSeed plan)
  completedSweepWith plan best =
    sweepCompletedEvent
      (sweepFinishedRecord plan 3 1 best)
      (tuningPlanId plan)
      TrainingBudget.TuningTrialBudget
      3
      (tuningSeed plan)
  -- The planned 3-trial completed sweep with a proof that is valid on its own
  -- but disagrees with the plan, swapped in by record update after the
  -- production join accepted the baseline: the reducer must not trust the join.
  forgedSweep plan proofPlan kind proofUnits proofSeed = do
    baseline <- completedSweep plan 3 3
    proof <- validCompletedTraining proofPlan kind proofUnits proofSeed
    withSweepProof proof baseline
  missingFor plan expected events =
    missingExactly
      expected
      ( incompleteAfter
          (ingestTuneEvent plan)
          (tuningCompletionContract plan)
          events
      )
  rejectsTuning plan expected prefix offender =
    rejectsLast
      expected
      ( ingestThen
          (ingestTuneEvent plan)
          (initialProgress (tuningCompletionContract plan))
          prefix
          offender
      )
  retargetTrial planText tuneEvent =
    case tuneEvent of
      Tune.TuneTrialFinished finished -> Tune.TuneTrialFinished finished {Tune.tfTunePlanId = planText}
      other -> other
  retargetTrialExperiment experiment tuneEvent =
    case tuneEvent of
      Tune.TuneTrialFinished finished ->
        Tune.TuneTrialFinished finished {Tune.tfTuneExperimentHash = experiment}
      other -> other
  retargetStarted planText tuneEvent =
    case tuneEvent of
      Tune.TuneTrialStarted started -> Tune.TuneTrialStarted started {Tune.tsPlanId = planText}
      other -> other

-- AlphaZero --------------------------------------------------------------------

alphaZeroControls :: [NegativeControl]
alphaZeroControls =
  [ alphaZero
      "event-gap-alphazero-generation"
      "a self-play run missing one generation is incomplete, naming it"
      ( \plan ->
          missingFor
            plan
            (MissingKeys "alphazero-generation-completed" ("1" :| []) :| [])
            [generation plan 0, generation plan 2, arena plan 6 0.75]
      )
  , alphaZeroSized
      "event-gap-alphazero-generations-ascending"
      "several missing generations are reported in numeric ascending order, not lexicographic order"
      12
      ( \plan ->
          missingFor
            plan
            ( MissingKeys
                "alphazero-generation-completed"
                ("0" :| ["2", "4", "5", "6", "7", "8", "9", "10", "11"])
                :| []
            )
            [generation plan 1, generation plan 3, arena plan 6 0.75]
      )
  , alphaZero
      "event-missing-terminal-alphazero-arena"
      "a self-play run with every generation but no arena terminal is incomplete"
      ( \plan ->
          missingFor
            plan
            (MissingExactlyOne "alphazero-arena-completed" :| [])
            (fmap (generation plan) [0, 1, 2])
      )
  , alphaZero
      "event-conflicting-duplicate-alphazero-generation"
      "a generation redelivered with a different sample count must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            ( WorkloadEvidenceViolation
                ( ConflictingDuplicate
                    "alphazero-generation-completed"
                    "0"
                    (eventId (alphaZeroPlanId plan) "alphazero-generation-completed" "0")
                    (eventId (alphaZeroPlanId plan) "alphazero-generation-completed" "0")
                )
            )
            [alphaZeroGenerationEvent plan 0 4 1000]
            (alphaZeroGenerationEvent plan 0 4 2000)
      )
  , alphaZero
      "event-conflicting-duplicate-alphazero-arena"
      "the arena terminal redelivered with a different win rate must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            ( WorkloadEvidenceViolation
                ( ConflictingDuplicate
                    "alphazero-arena-completed"
                    "()"
                    (eventId (alphaZeroPlanId plan) "alphazero-arena-completed" "()")
                    (eventId (alphaZeroPlanId plan) "alphazero-arena-completed" "()")
                )
            )
            [arena plan 6 0.75]
            (arena plan 6 0.5)
      )
  , alphaZero
      "event-wrong-plan-alphazero-generation"
      "a generation stamped with another plan must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            ( WorkloadEventPlanMismatch
                "alphazero-generation-completed"
                (planIdText (alphaZeroPlanId plan))
                "wrong-plan"
            )
            []
            (retargetGeneration "wrong-plan" (generation plan 0))
      )
  , alphaZero
      "event-wrong-plan-alphazero-arena"
      "an arena terminal stamped with another plan must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            ( WorkloadEventPlanMismatch
                "alphazero-arena-completed"
                (planIdText (alphaZeroPlanId plan))
                "wrong-plan"
            )
            []
            (retargetArena "wrong-plan" (arena plan 6 0.75))
      )
  , alphaZero
      "event-wrong-experiment-alphazero-generation"
      "a generation for another experiment under this plan must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            ( WorkloadEventExperimentMismatch
                "alphazero-generation-completed"
                (runPlanExperimentId (alphaZeroPlanRunPlan plan))
                "some-other-experiment"
            )
            []
            (retargetGenerationExperiment "some-other-experiment" (generation plan 0))
      )
  , alphaZero
      "event-out-of-range-alphazero-generation"
      "a generation index beyond the planned count must be rejected on arrival"
      ( \plan ->
          rejectsAlphaZero
            plan
            (WorkloadEvidenceViolation (OutOfRangeKey "alphazero-generation-completed" "3"))
            []
            (generation plan 3)
      )
  , alphaZero
      "event-nonfinite-alphazero-arena-win-rate"
      "a NaN arena win rate must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            ( WorkloadEventRefinementFailure
                "alphazero-arena-completed"
                (NonFiniteMeasurement "alphazero-arena-win-rate" :| [])
            )
            []
            (arena plan 6 (0 / 0))
      )
  , alphaZero
      "event-completion-before-budget-alphazero-generation-games"
      "a generation that played 3 of the planned 4 self-play games must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            (WorkloadEventBudgetMismatch "alphazero-generation-completed" 4 3)
            []
            (alphaZeroGenerationEvent plan 0 3 1000)
      )
  , alphaZero
      "event-completion-beyond-budget-alphazero-generation-games"
      "a generation that played 5 self-play games of a planned 4 must be rejected: the budget is exact, not a floor"
      ( \plan ->
          rejectsAlphaZero
            plan
            (WorkloadEventBudgetMismatch "alphazero-generation-completed" 4 5)
            []
            (alphaZeroGenerationEvent plan 0 5 1000)
      )
  , alphaZero
      "event-completion-before-budget-alphazero-arena-games"
      "an arena that played 5 of the planned 6 games must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            (WorkloadEventBudgetMismatch "alphazero-arena-completed" 6 5)
            []
            (arena plan 5 0.75)
      )
  , alphaZero
      "event-completion-beyond-budget-alphazero-arena-games"
      "an arena that played 7 games of a planned 6 must be rejected"
      ( \plan ->
          rejectsAlphaZero
            plan
            (WorkloadEventBudgetMismatch "alphazero-arena-completed" 6 7)
            []
            (alphaZeroArenaEvent plan 7 0.75)
      )
  ]
 where
  alphaZero name description = alphaZeroSized name description 3
  alphaZeroSized name description generations build =
    event name description $
      withFixture (alphaZeroPlanFor "control-alphazero" generations) $ \plan ->
        build plan
  generation plan number = alphaZeroGenerationEvent plan number 4 (fromIntegral number + 1000)
  arena = alphaZeroArenaEvent
  missingFor plan expected events =
    missingExactly
      expected
      ( incompleteAfter
          (ingestAlphaZeroEvent plan)
          (alphaZeroCompletionContract plan)
          events
      )
  rejectsAlphaZero plan expected prefix offender =
    rejectsLast
      expected
      ( ingestThen
          (ingestAlphaZeroEvent plan)
          (initialProgress (alphaZeroCompletionContract plan))
          prefix
          offender
      )
  retargetGeneration planText rlEvent =
    case rlEvent of
      Rl.RlGenerationCompleted done -> Rl.RlGenerationCompleted done {Rl.gcPlanId = planText}
      other -> other
  retargetGenerationExperiment experiment rlEvent =
    case rlEvent of
      Rl.RlGenerationCompleted done -> Rl.RlGenerationCompleted done {Rl.gcExperimentHash = experiment}
      other -> other
  retargetArena planText rlEvent =
    case rlEvent of
      Rl.RlArenaCompleted done -> Rl.RlArenaCompleted done {Rl.acPlanId = planText}
      other -> other

-- Malformed payloads -----------------------------------------------------------

-- | A key whose rendering is empty, the only way to reach the empty-logical-key
-- error through 'evidenceEvent' (every ordinary 'Show' instance renders
-- something).
newtype BlankKey = BlankKey ()
  deriving stock (Eq, Ord)

instance Show BlankKey where
  show _ = ""

malformedControls :: [NegativeControl]
malformedControls =
  [ event
      "event-malformed-empty-event-kind"
      "an event with an empty kind has no semantic identity and must be rejected"
      ( rejectedWith
          (EmptyEventKind :| [])
          (validationToEither (void (evidenceEvent planA "" () ("payload" :: Text))))
      )
  , event
      "event-malformed-blank-event-kind"
      "an event whose kind is only whitespace must be rejected"
      ( rejectedWith
          (EmptyEventKind :| [])
          (validationToEither (void (evidenceEvent planA " \t " () ("payload" :: Text))))
      )
  , event
      "event-malformed-empty-logical-key-derivation"
      "an event identity derived from a blank logical key must be rejected"
      ( rejectedWith
          (EmptyEventLogicalKey :| [])
          (validationToEither (void (deriveEventIdForPlanId planA "kind" "  ")))
      )
  , event
      "event-malformed-empty-logical-key-through-evidence-event"
      "an event whose key renders as nothing must be rejected by evidenceEvent"
      ( rejectedWith
          (EmptyEventLogicalKey :| [])
          (validationToEither (void (evidenceEvent planA "kind" (BlankKey ()) ("payload" :: Text))))
      )
  , event
      "event-malformed-empty-kind-and-key-accumulate"
      "a blank kind and a blank key are both reported"
      ( rejectedWith
          (EmptyEventKind :| [EmptyEventLogicalKey])
          (validationToEither (void (deriveEventIdForPlanId planA " " "\t")))
      )
  , wire
      "event-malformed-undecodable-wire-training-empty"
      "an empty training event payload carries no oneof body and must be rejected"
      (Training.decodeTrainingEventProto "")
      "expected exactly one TrainingEvent oneof field"
  , wire
      "event-malformed-undecodable-wire-training-truncated-varint"
      "a training event payload cut off inside a varint must be rejected"
      (Training.decodeTrainingEventProto (ByteString.pack [0xff, 0xff]))
      "truncated protobuf varint"
  , wire
      "event-malformed-undecodable-wire-training-overlong-field"
      "a training event whose length prefix exceeds the payload must be rejected"
      (Training.decodeTrainingEventProto (ByteString.pack [0x0a, 0x05, 0x01]))
      "length-delimited field exceeds available protobuf bytes"
  , wire
      "event-malformed-undecodable-wire-training-wrong-wire-type"
      "a training event whose oneof body has the wrong wire type must be rejected"
      (Training.decodeTrainingEventProto (ByteString.pack [0x08, 0x01]))
      "TrainingEvent oneof body has the wrong protobuf wire type"
  , wire
      "event-malformed-undecodable-wire-rl-empty"
      "an empty RL event payload carries no oneof body and must be rejected"
      (Rl.decodeRlEventProto "")
      "expected exactly one RlEvent oneof field"
  , wire
      "event-malformed-undecodable-wire-tune-empty"
      "an empty tuning event payload carries no oneof body and must be rejected"
      (Tune.decodeTuneEventProto "")
      "expected exactly one TuneEvent oneof field"
  , wire
      "event-malformed-undecodable-wire-completed-training-garbage"
      "bytes that are not a completed-training DTO must be rejected"
      (TrainingBudget.decodeCompletedTraining (ByteString.pack [1, 2, 3]))
      "invalid completed-training DTO: "
  , wire
      "event-nonfinite-wire-rl-evaluation-reward"
      "a protobuf RL evaluation outcome carrying a NaN reward must not decode"
      ( Rl.decodeRlEventProto
          (Rl.encodeRlEventProto (rlEvaluationEvent rlPlanText rlExperiment 0 (0 / 0) 4))
      )
      "invalid protobuf field: reward must be finite"
  , wire
      "event-nonfinite-wire-rl-median-metric"
      "a protobuf RL metric update carrying a NaN value must not decode"
      ( Rl.decodeRlEventProto
          (Rl.encodeRlEventProto (rlMetricEvent rlPlanText rlExperiment (0 / 0)))
      )
      "invalid protobuf field: value must be finite"
  , wire
      "event-nonfinite-wire-tuning-trial-objective"
      "a protobuf tuning trial result carrying a NaN objective must not decode"
      ( Tune.decodeTuneEventProto
          ( Tune.encodeTuneEventProto
              ( Tune.TuneTrialFinished
                  Tune.TrialFinished
                    { Tune.tfTuneExperimentHash = "control-tuning"
                    , Tune.tfTunePlanId = "control-plan"
                    , Tune.tfTuneTrial = 0
                    , Tune.tfTuneObjective = 0 / 0
                    , Tune.tfTunePruned = False
                    , Tune.tfTuneTranscriptObjectKey = "trials/0.cbor"
                    , Tune.tfTuneTimestampNs = 1
                    }
              )
          )
      )
      "non-finite protobuf field: objective"
  , wire
      "event-nonfinite-wire-alphazero-arena-win-rate"
      "a protobuf arena terminal carrying a NaN win rate must not decode"
      ( Rl.decodeRlEventProto
          ( Rl.encodeRlEventProto
              ( Rl.RlArenaCompleted
                  Rl.ArenaCompleted
                    { Rl.acPlanId = "control-plan"
                    , Rl.acExperimentHash = "control-alphazero"
                    , Rl.acArenaGames = 6
                    , Rl.acWinRate = 0 / 0
                    }
              )
          )
      )
      "invalid protobuf field: win_rate must be finite"
  , wire
      "event-nonfinite-wire-training-epoch-loss"
      "a protobuf epoch summary carrying a NaN loss must not decode"
      ( Training.decodeTrainingEventProto
          ( Training.encodeTrainingEventProto
              (supervisedEpochWithLosses supervisedExperiment 1 (0 / 0) 0.5)
          )
      )
      "non-finite protobuf field: loss"
  ]
 where
  -- A decoder's rejection is compared by message; the wire decoders render
  -- their own reason, so the start of the text names the guard that fired.
  wire :: Text -> Text -> Either Text accepted -> Text -> NegativeControl
  wire name description decoded message =
    event name description $
      rejectedWhere
        ("a decode failure starting with: " <> message)
        (message `Text.isPrefixOf`)
        decoded

-- Completion before the declared budget ----------------------------------------

completionBudgetControls :: [NegativeControl]
completionBudgetControls =
  [ event
      "event-completion-before-budget-supervised-checkpoint-budget"
      "a completed supervised checkpoint whose own budget is 1 epoch, against a 3-epoch plan, must not complete the run"
      ( supervisedBudget
          1
          "supervised completed checkpoint budget does not match the plan: plan requires 3, completed budget targets 1 with 1 observed"
      )
  , event
      "event-completion-beyond-budget-supervised-checkpoint-budget"
      "a completed supervised checkpoint whose own budget is 5 epochs, against a 3-epoch plan, must not complete the run"
      ( supervisedBudget
          5
          "supervised completed checkpoint budget does not match the plan: plan requires 3, completed budget targets 5 with 5 observed"
      )
  , event
      "event-completion-wrong-unit-supervised-checkpoint-budget"
      "a completed supervised checkpoint denominated in environment steps must not complete the run"
      ( withFixture
          ( (,)
              <$> supervisedContract
              <*> supervisedCompletedCheckpointFor
                planA
                TrainingBudget.RlEnvironmentStepBudget
                3
                supervisedExperiment
          )
          $ \(contract, checkpoint) ->
            missingExactly
              ( InvalidEvidence
                  "supervised completed checkpoint budget kind mismatch: plan supervised-epochs, completed rl-environment-steps"
                  :| []
              )
              ( incompleteAfter
                  (supervisedIngest contract)
                  contract
                  [epoch 3 0.25, checkpoint]
              )
      )
  , event
      "event-completion-before-budget-rl-checkpoint-budget"
      "a completed RL checkpoint of 4 environment steps, against a plan that schedules 1000, must not complete the run"
      ( withFixture
          ( (,)
              <$> first (renderError "RL contract") (LiveEvidence.rlLiveContractForSteps planA 4 1000)
              <*> rlCheckpointOfSteps 4
          )
          $ \(contract, checkpoint) ->
            missingExactly
              ( InvalidEvidence
                  "RL completed checkpoint budget does not match the plan: plan requires 1000, completed budget targets 4 with 4 observed"
                  :| []
              )
              ( incompleteAfter
                  (rlIngest contract)
                  contract
                  ( fmap episodeEvent [0 .. 3]
                      <> [rlMetricEvent rlPlanText rlExperiment (medianOfFirst 4), checkpoint]
                  )
              )
      )
  , event
      "event-completion-wrong-unit-rl-checkpoint-budget"
      "a completed RL checkpoint denominated in epochs must not complete the run"
      ( withFixture
          ( (,)
              <$> rlContractFor 4
              <*> rlCompletedCheckpointFor planA TrainingBudget.SupervisedEpochBudget 4 rlExperiment
          )
          $ \(contract, checkpoint) ->
            missingExactly
              ( InvalidEvidence
                  "RL completed checkpoint budget kind mismatch: plan rl-environment-steps, completed supervised-epochs"
                  :| []
              )
              ( incompleteAfter
                  (rlIngest contract)
                  contract
                  ( fmap episodeEvent [0 .. 3]
                      <> [rlMetricEvent rlPlanText rlExperiment (medianOfFirst 4), checkpoint]
                  )
              )
      )
  , event
      "event-completion-before-budget-supervised-checkpoint-step"
      "a supervised checkpoint whose step disagrees with the completion's observed units cannot be sealed"
      ( withFixture (validCompletedTraining planA TrainingBudget.SupervisedEpochBudget 3 (Just 7)) $ \completed ->
          rejectedWith
            "checkpoint step does not match completed-training observed units"
            ( void
                ( Training.completeCheckpointDone
                    Training.CheckpointDone
                      { Training.cdExperimentHash = supervisedExperiment
                      , Training.cdManifestSha = "supervised-control-manifest"
                      , Training.cdStep = 2
                      , Training.cdPointerKey = "checkpoints/supervised-control/latest"
                      , Training.cdEpoch = 2
                      , Training.cdTrialSha = Nothing
                      , Training.cdRunUuid = "supervised-control-run"
                      , Training.cdMetricsAtStep = [("control_metric", 0.9)]
                      }
                    completed
                )
            )
      )
  , event
      "event-completion-before-budget-rl-checkpoint-step"
      "an RL checkpoint whose step disagrees with the completion's observed units cannot be sealed"
      ( withFixture (validCompletedTraining planA TrainingBudget.RlEnvironmentStepBudget 4 (Just 7)) $ \completed ->
          rejectedWith
            "RL checkpoint step does not match completed-training observed units"
            ( void
                ( Rl.completeCheckpointDoneRL
                    Rl.CheckpointDoneRL
                      { Rl.cdrlExperimentHash = rlExperiment
                      , Rl.cdrlManifestSha = "rl-control-manifest"
                      , Rl.cdrlStep = 3
                      , Rl.cdrlPointerKey = "checkpoints/rl-control/latest"
                      }
                    completed
                )
            )
      )
  , event
      "event-completion-before-budget-completed-training-underrun"
      "a completed-training proof of 2 epochs against a 3-epoch budget must not be minted"
      ( completedTrainingRejected
          2
          "training budget incomplete or overrun: observed 2 epochs, required exactly 3"
      )
  , event
      "event-completion-beyond-budget-completed-training-overrun"
      "a completed-training proof of 4 epochs against a 3-epoch budget must not be minted"
      ( completedTrainingRejected
          4
          "training budget incomplete or overrun: observed 4 epochs, required exactly 3"
      )
  ]
 where
  supervisedBudget units message =
    withFixture ((,) <$> supervisedContract <*> checkpointOfEpochs units) $ \(contract, checkpoint) ->
      missingExactly
        (InvalidEvidence message :| [])
        ( incompleteAfter
            (supervisedIngest contract)
            contract
            [epoch 3 0.25, checkpoint]
        )
  -- The smart constructor is given a 3-epoch budget but an observed count that
  -- differs from it.
  completedTrainingRejected observed message =
    rejectedWith
      message
      ( void
          ( completedTrainingWithObserved
              planA
              TrainingBudget.SupervisedEpochBudget
              3
              observed
              (Just 7)
          )
      )

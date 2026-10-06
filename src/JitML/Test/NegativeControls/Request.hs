{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | Phase 280 — known-invalid raw requests.
--
-- Every control here is a valid baseline request with one injected defect (or,
-- for the accumulation controls, a stated set of independent defects), driven
-- through the production refinement ('resolveRun', the workload plan resolvers
-- and transport parsers, 'projectProductRow', 'mkCohort') and compared against
-- the __exact__ rejection.  Because refinement accumulates independent errors,
-- comparing the whole error list also proves that the baseline contributes no
-- defect of its own, so no control can pass because its baseline was already
-- invalid for an unrelated reason ('baselineFailures' additionally proves
-- every baseline refines).
--
-- Dimensions are indexed by 'Unit' at the type level ('Quantity' 'Epoch' is not
-- a 'Quantity' 'Trial'), so a unit-swapped request cannot be written.  The
-- runtime dimensional relations that survive at the raw boundary are the ones
-- covered here: derived optimizer updates against epochs, examples, and batch
-- size; parallel trials and promotions against trials; a tuning execution spec
-- against its run budget; and a completed-training DTO's observed kind, unit,
-- and target against its budget.
module JitML.Test.NegativeControls.Request
  ( baselineFailures
  , requestControls
  )
where

import Data.Functor (void)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Plan.Plan
  ( PlanError (..)
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKind (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , Validation (..)
  , resolveRun
  , validationToEither
  )
import JitML.Plan.Workload
  ( RawAlphaZeroPlan (..)
  , RawSupervisedPlan (..)
  , RawTuningPlan (..)
  , WorkloadPlanError (..)
  , parseAlphaZeroPlanTransport
  , parseSupervisedPlanTransport
  , parseTuningPlanTransport
  , renderAlphaZeroPlanTransport
  , renderSupervisedPlanTransport
  , renderTuningPlanTransport
  , resolveAlphaZeroPlan
  , resolveSupervisedPlan
  , resolveTuningPlan
  , resolveTuningPlanWithExecutionSpec
  )
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.Algorithms.Registry qualified as Cohort
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.ContractFixtures (planA)
import JitML.Test.ControlFixtures (validCompletedTraining)
import JitML.Test.NegativeControls.Core
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Catalog

-- | Every request control, grouped by the defect family it injects.
requestControls :: [NegativeControl]
requestControls =
  quantityControls
    <> identityControls
    <> versionAndPlacementControls
    <> seedControls
    <> relationControls
    <> accumulationControls
    <> workloadAxisControls
    <> tuningSpecControls
    <> transportControls
    <> rlPlanTransportControls
    <> productRowControls
    <> cohortControls
    <> completionDimensionControls

request :: Text -> Text -> ControlOutcome -> NegativeControl
request = pureControl Request

-- Baselines ----------------------------------------------------------------

supervisedBaseline :: RawRunRequest 'SupervisedTraining
supervisedBaseline =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = SupervisedTrainingWitness
    , rawRunExperimentId = "negative-control-supervised"
    , rawRunSubjectId = "mnist"
    , rawRunArtifactId = "artifact-a"
    , rawRunTopicId = "training.command.linux-cpu"
    , rawRunSubstrate = LinuxCPU
    , rawRunPlacement = ClusterRun
    , rawRunSeeds = [7]
    , rawRunBudget = RawSupervisedBudget 2 32 4 8 8
    }

rlBaseline :: RawRunRequest 'ReinforcementLearning
rlBaseline =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = ReinforcementLearningWitness
    , rawRunExperimentId = "negative-control-rl"
    , rawRunSubjectId = "ppo/cartpole"
    , rawRunArtifactId = "rl-artifact"
    , rawRunTopicId = "rl.command.linux-cpu"
    , rawRunSubstrate = LinuxCPU
    , rawRunPlacement = ClusterRun
    , rawRunSeeds = [11, 13]
    , rawRunBudget = RawRlBudget 4096 128 8 500 20
    }

tuningBaseline :: RawRunRequest 'HyperparameterTuning
tuningBaseline =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = HyperparameterTuningWitness
    , rawRunExperimentId = "negative-control-tuning"
    , rawRunSubjectId = "mnist/dense"
    , rawRunArtifactId = "tune-best-checkpoint"
    , rawRunTopicId = "tune.event.linux-cpu"
    , rawRunSubstrate = LinuxCPU
    , rawRunPlacement = ClusterRun
    , rawRunSeeds = [11, 17]
    , rawRunBudget = RawTuningBudget 12 3 1 100
    }

alphaZeroBaseline :: RawRunRequest 'AlphaZeroSelfPlay
alphaZeroBaseline =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = AlphaZeroSelfPlayWitness
    , rawRunExperimentId = "negative-control-alphazero"
    , rawRunSubjectId = "connect4-policy-value"
    , rawRunArtifactId = "alphazero-checkpoint"
    , rawRunTopicId = "rl.event.linux-cpu"
    , rawRunSubstrate = LinuxCPU
    , rawRunPlacement = ClusterRun
    , rawRunSeeds = [31]
    , rawRunBudget = RawAlphaZeroBudget 2 8 32 42 4 16
    }

supervisedPlanBaseline :: RawSupervisedPlan
supervisedPlanBaseline = RawSupervisedPlan supervisedBaseline

tuningPlanBaseline :: RawTuningPlan
tuningPlanBaseline =
  RawTuningPlan
    { rawTuningRun = tuningBaseline
    , rawTuningSampler = "TPE"
    , rawTuningScheduler = "ASHA"
    , rawTuningPruner = "MedianPruner"
    }

alphaZeroPlanBaseline :: RawAlphaZeroPlan
alphaZeroPlanBaseline =
  RawAlphaZeroPlan
    { rawAlphaZeroRun = alphaZeroBaseline
    , rawAlphaZeroGame = "connect4"
    }

-- | The names of any baseline that does not refine.  Empty when every control
-- below starts from a valid request; a non-empty list means a control could be
-- passing only because its baseline was already invalid.
baselineFailures :: [Text]
baselineFailures =
  [ name
  | (name, refines) <-
      [ ("supervised", refined (resolveRun supervisedBaseline))
      , ("reinforcement-learning", refined (resolveRun rlBaseline))
      , ("hyperparameter-tuning", refined (resolveRun tuningBaseline))
      , ("alphazero", refined (resolveRun alphaZeroBaseline))
      , ("supervised-plan", refined (resolveSupervisedPlan supervisedPlanBaseline))
      , ("tuning-plan", refined (resolveTuningPlan tuningPlanBaseline))
      , ("alphazero-plan", refined (resolveAlphaZeroPlan alphaZeroPlanBaseline))
      ,
        ( "tuning-execution-spec"
        , refined (resolveTuningPlanWithExecutionSpec tuningSpecBaseline tuningPlanBaseline)
        )
      , ("completed-training", either (const False) (const True) completionBaseline)
      ]
  , not refines
  ]
 where
  refined result =
    case result of
      Success _ -> True
      Failure _ -> False

-- Outcome helpers ------------------------------------------------------------

-- | The refinement must fail with exactly this accumulated error list.
planRejected :: NonEmpty PlanError -> Validation (NonEmpty PlanError) plan -> ControlOutcome
planRejected expected = rejectedWith expected . validationToEither

singlePlanError :: PlanError -> Validation (NonEmpty PlanError) plan -> ControlOutcome
singlePlanError err = planRejected (err :| [])

workloadRejected
  :: NonEmpty WorkloadPlanError
  -> Validation (NonEmpty WorkloadPlanError) plan
  -> ControlOutcome
workloadRejected expected = rejectedWith expected . validationToEither

singleWorkloadError
  :: WorkloadPlanError
  -> Validation (NonEmpty WorkloadPlanError) plan
  -> ControlOutcome
singleWorkloadError err = workloadRejected (err :| [])

-- Quantities ---------------------------------------------------------------

-- | A run kind, one of its quantity labels, and the request that sets exactly
-- that quantity to a chosen integer while every other quantity keeps its valid
-- baseline value.
data QuantityCase = QuantityCase
  { qcKind :: Text
  , qcLabel :: Text
  , qcResolve :: Integer -> Validation (NonEmpty PlanError) ()
  }

quantityCases :: [QuantityCase]
quantityCases =
  [ supervised "epochs" (\v -> RawSupervisedBudget v 32 4 8 8)
  , supervised "training-examples" (\v -> RawSupervisedBudget 2 v 4 8 8)
  , supervised "evaluation-examples" (\v -> RawSupervisedBudget 2 32 v 8 8)
  , supervised "batch-examples" (\v -> RawSupervisedBudget 2 32 4 v 8)
  , supervised "optimizer-updates" (RawSupervisedBudget 2 32 4 8)
  , rl "environment-transitions" (\v -> RawRlBudget v 128 8 500 20)
  , rl "rollout-ticks-per-environment" (\v -> RawRlBudget 4096 v 8 500 20)
  , rl "vector-environments" (\v -> RawRlBudget 4096 128 v 500 20)
  , rl "episode-steps" (\v -> RawRlBudget 4096 128 8 v 20)
  , rl "evaluation-episodes" (RawRlBudget 4096 128 8 500)
  , tuning "trials" (\v -> RawTuningBudget v 3 1 100)
  , tuning "parallel-trials" (\v -> RawTuningBudget 12 v 1 100)
  , tuning "promotions" (\v -> RawTuningBudget 12 3 v 100)
  , tuning "per-trial-optimizer-updates" (RawTuningBudget 12 3 1)
  , alphaZero "generations" (\v -> RawAlphaZeroBudget v 8 32 42 4 16)
  , alphaZero "self-play-games-per-generation" (\v -> RawAlphaZeroBudget 2 v 32 42 4 16)
  , alphaZero "mcts-simulations-per-move" (\v -> RawAlphaZeroBudget 2 8 v 42 4 16)
  , alphaZero "max-plies-per-game" (\v -> RawAlphaZeroBudget 2 8 32 v 4 16)
  , alphaZero "optimizer-updates-per-generation" (\v -> RawAlphaZeroBudget 2 8 32 42 v 16)
  , alphaZero "arena-games" (RawAlphaZeroBudget 2 8 32 42 4)
  ]
 where
  supervised label budget =
    QuantityCase
      "supervised"
      label
      (\v -> void (resolveRun supervisedBaseline {rawRunBudget = budget v}))
  rl label budget =
    QuantityCase "rl" label (\v -> void (resolveRun rlBaseline {rawRunBudget = budget v}))
  tuning label budget =
    QuantityCase "tuning" label (\v -> void (resolveRun tuningBaseline {rawRunBudget = budget v}))
  alphaZero label budget =
    QuantityCase "alphazero" label (\v -> void (resolveRun alphaZeroBaseline {rawRunBudget = budget v}))

-- | Zero and negative quantities per run kind and label, plus a value beyond
-- 'Word64' for one label per kind.  The chosen labels take part in no derived
-- relation, so the out-of-range error stands alone.
quantityControls :: [NegativeControl]
quantityControls =
  [ request
      ("request-" <> qcKind quantityCase <> "-" <> qcLabel quantityCase <> "-" <> word)
      ( "a "
          <> qcKind quantityCase
          <> " request whose "
          <> qcLabel quantityCase
          <> " is "
          <> word
          <> " must be rejected as a non-positive quantity"
      )
      (singlePlanError (NonPositiveQuantity (qcLabel quantityCase)) (qcResolve quantityCase value))
  | quantityCase <- quantityCases
  , (word, value) <- [("zero", 0), ("negative", -1)]
  ]
    <> [ request
           ("request-" <> qcKind quantityCase <> "-" <> qcLabel quantityCase <> "-beyond-word64")
           ( "a "
               <> qcKind quantityCase
               <> " request whose "
               <> qcLabel quantityCase
               <> " exceeds Word64 must be rejected as out of range"
           )
           ( singlePlanError
               (QuantityOutOfRange (qcLabel quantityCase) beyondWord64)
               (qcResolve quantityCase beyondWord64)
           )
       | quantityCase <- quantityCases
       , (qcKind quantityCase, qcLabel quantityCase)
           `elem` [ ("supervised", "evaluation-examples")
                  , ("rl", "environment-transitions")
                  , ("tuning", "per-trial-optimizer-updates")
                  , ("alphazero", "generations")
                  ]
       ]

beyondWord64 :: Integer
beyondWord64 = toInteger (maxBound :: Word64) + 1

-- Identities ---------------------------------------------------------------

identityControls :: [NegativeControl]
identityControls =
  [ request
      ("request-empty-identity-" <> label <> "-" <> flavour)
      ( "a request whose "
          <> label
          <> " is "
          <> flavour
          <> " must be rejected as an empty identity"
      )
      (singlePlanError (EmptyPlanField label) (resolveRun (set blank)))
  | (label, set) <-
      [ ("experiment-id", \v -> supervisedBaseline {rawRunExperimentId = v})
      , ("subject-id", \v -> supervisedBaseline {rawRunSubjectId = v})
      , ("artifact-id", \v -> supervisedBaseline {rawRunArtifactId = v})
      , ("topic-id", \v -> supervisedBaseline {rawRunTopicId = v})
      ]
  , (flavour, blank) <- [("empty", ""), ("whitespace-only", " \t ")]
  ]

-- Versions and placement -----------------------------------------------------

versionAndPlacementControls :: [NegativeControl]
versionAndPlacementControls =
  [ request
      ("request-run-version-" <> Text.pack (show version))
      ( "a resolved-plan version of "
          <> Text.pack (show version)
          <> " is not the supported version 1 and must be rejected"
      )
      ( singlePlanError
          (UnsupportedRunPlanVersion version)
          (resolveRun supervisedBaseline {rawRunVersion = version})
      )
  | version <- [0, 2]
  ]
    <> [ request
           ("request-placement-" <> name)
           ( "a "
               <> renderSubstrate substrate
               <> " run cannot be placed "
               <> place
               <> ": the substrate/placement pair must be rejected"
           )
           ( singlePlanError
               (InvalidRunPlacement substrate placement)
               (resolveRun supervisedBaseline {rawRunSubstrate = substrate, rawRunPlacement = placement})
           )
       | (name, substrate, placement, place) <-
           [ ("apple-silicon-cluster", AppleSilicon, ClusterRun, "on the cluster")
           , ("linux-cpu-host", LinuxCPU, HostRun, "on the host")
           , ("linux-cuda-host", LinuxCUDA, HostRun, "on the host")
           ]
       ]

-- Seeds --------------------------------------------------------------------

seedControls :: [NegativeControl]
seedControls =
  [ request
      "request-seeds-empty"
      "an empty seed cohort must be rejected"
      (singlePlanError EmptySeedCohort (resolveRun supervisedBaseline {rawRunSeeds = []}))
  , request
      "request-seeds-duplicate"
      "a seed cohort naming the same seed twice must be rejected"
      ( singlePlanError
          (DuplicateSeed 3)
          (resolveRun supervisedBaseline {rawRunSeeds = [3, 3]})
      )
  , request
      "request-seeds-every-duplicate-reported"
      "every duplicated seed must be reported, in ascending order"
      ( planRejected
          (DuplicateSeed 3 :| [DuplicateSeed 5])
          (resolveRun supervisedBaseline {rawRunSeeds = [5, 3, 9, 5, 3]})
      )
  ]

-- Cross-quantity relations ---------------------------------------------------

relationControls :: [NegativeControl]
relationControls =
  [ request
      "request-derived-optimizer-updates-under"
      "optimizer updates below epochs x ceil(examples / batch) must be rejected"
      ( singlePlanError
          (DerivedQuantityMismatch "optimizer-updates" 8 7)
          (resolveRun supervisedBaseline {rawRunBudget = RawSupervisedBudget 2 32 4 8 7})
      )
  , request
      "request-derived-optimizer-updates-over"
      "optimizer updates above epochs x ceil(examples / batch) must be rejected"
      ( singlePlanError
          (DerivedQuantityMismatch "optimizer-updates" 8 9)
          (resolveRun supervisedBaseline {rawRunBudget = RawSupervisedBudget 2 32 4 8 9})
      )
  , request
      "request-derived-optimizer-updates-partial-batch"
      "a trailing partial batch counts as a step: 33 examples in batches of 8 is 5 steps an epoch, not 4"
      ( singlePlanError
          (DerivedQuantityMismatch "optimizer-updates" 10 8)
          (resolveRun supervisedBaseline {rawRunBudget = RawSupervisedBudget 2 33 4 8 8})
      )
  , request
      "request-tuning-parallel-trials-exceed-trials"
      "more parallel trials than trials must be rejected"
      ( singlePlanError
          (QuantityExceeds "parallel-trials" 4 "trials" 3)
          (resolveRun tuningBaseline {rawRunBudget = RawTuningBudget 3 4 1 100})
      )
  , request
      "request-tuning-promotions-exceed-trials"
      "more promotions than trials must be rejected"
      ( singlePlanError
          (QuantityExceeds "promotions" 5 "trials" 3)
          (resolveRun tuningBaseline {rawRunBudget = RawTuningBudget 3 1 5 100})
      )
  ]

-- | Independent defects accumulate: a request that short-circuited on its first
-- error would hide the rest from the operator.
accumulationControls :: [NegativeControl]
accumulationControls =
  [ request
      "request-every-independent-defect-reported"
      "a request with a bad version, four blank identities, a bad placement, no seeds, and five zero quantities must report all twelve, in field order"
      ( planRejected
          ( UnsupportedRunPlanVersion 0
              :| [ EmptyPlanField "experiment-id"
                 , EmptyPlanField "subject-id"
                 , EmptyPlanField "artifact-id"
                 , EmptyPlanField "topic-id"
                 , InvalidRunPlacement LinuxCPU HostRun
                 , EmptySeedCohort
                 , NonPositiveQuantity "epochs"
                 , NonPositiveQuantity "training-examples"
                 , NonPositiveQuantity "evaluation-examples"
                 , NonPositiveQuantity "batch-examples"
                 , NonPositiveQuantity "optimizer-updates"
                 ]
          )
          ( resolveRun
              RawRunRequest
                { rawRunVersion = 0
                , rawRunKind = SupervisedTrainingWitness
                , rawRunExperimentId = " "
                , rawRunSubjectId = ""
                , rawRunArtifactId = "\t"
                , rawRunTopicId = ""
                , rawRunSubstrate = LinuxCPU
                , rawRunPlacement = HostRun
                , rawRunSeeds = []
                , rawRunBudget = RawSupervisedBudget 0 0 0 0 0
                }
          )
      )
  ]

-- Closed workload axes -------------------------------------------------------

workloadAxisControls :: [NegativeControl]
workloadAxisControls =
  [ request
      "request-tuning-unknown-sampler"
      "a sampler outside the closed catalog must be rejected"
      ( singleWorkloadError
          (UnknownTuningSampler "simulated-annealing")
          (resolveTuningPlan tuningPlanBaseline {rawTuningSampler = " simulated-annealing "})
      )
  , request
      "request-tuning-unknown-scheduler"
      "a scheduler outside the closed catalog must be rejected"
      ( singleWorkloadError
          (UnknownTuningScheduler "round-robin")
          (resolveTuningPlan tuningPlanBaseline {rawTuningScheduler = "round-robin"})
      )
  , request
      "request-tuning-unknown-pruner"
      "a pruner outside the closed catalog must be rejected"
      ( singleWorkloadError
          (UnknownTuningPruner "oracle")
          (resolveTuningPlan tuningPlanBaseline {rawTuningPruner = "oracle"})
      )
  , request
      "request-alphazero-unknown-game"
      "a game outside the closed catalog must be rejected"
      ( singleWorkloadError
          (UnknownAlphaZeroGame "chess")
          (resolveAlphaZeroPlan alphaZeroPlanBaseline {rawAlphaZeroGame = "Chess"})
      )
  , request
      "request-tuning-every-unknown-axis-reported"
      "an unknown sampler, scheduler, and pruner must all be reported together"
      ( workloadRejected
          ( UnknownTuningSampler "a"
              :| [UnknownTuningScheduler "b", UnknownTuningPruner "c"]
          )
          ( resolveTuningPlan
              tuningPlanBaseline
                { rawTuningSampler = "a"
                , rawTuningScheduler = "b"
                , rawTuningPruner = "c"
                }
          )
      )
  ]

-- Tuning execution spec against its run budget ---------------------------------

-- | An execution spec consistent with 'tuningPlanBaseline' (12 trials, 3 in
-- parallel, 100 updates per trial, run seed 11).
tuningSpecBaseline :: Catalog.TuningExecutionSpec
tuningSpecBaseline =
  Catalog.legacyTuningExecutionSpec
    Catalog.TPE
    Catalog.ASHA
    Catalog.MedianPruner
    11
    12
    3
    100

tuningSpecControls :: [NegativeControl]
tuningSpecControls =
  [ specControl
      "request-dimension-tuning-spec-trials-mismatch"
      "an execution spec that plans 13 trials against a 12-trial run budget must be rejected"
      "trial count mismatch: plan=12, execution-spec=13"
      tuningSpecBaseline {Catalog.tuningExecutionTrials = 13}
      tuningPlanBaseline
  , specControl
      "request-dimension-tuning-spec-parallelism-mismatch"
      "an execution spec whose parallelism differs from its scheduler's must be rejected"
      "tuning scheduler parallelism must equal top-level parallelism"
      tuningSpecBaseline {Catalog.tuningExecutionParallelism = 4}
      tuningPlanBaseline
  , specControl
      "request-dimension-tuning-spec-updates-mismatch"
      "a run budget of 101 updates per trial against a 100-update scheduler ceiling must be rejected"
      "max optimizer updates per trial mismatch: plan=101, execution-spec=100"
      tuningSpecBaseline
      (withTuningBudget (RawTuningBudget 12 3 1 101))
  , specControl
      "request-dimension-tuning-spec-promotions-beyond-frontier"
      "promoting more trials than the scheduler and pruner guarantee reach the ceiling must be rejected"
      "promotion count exceeds the scheduler/pruner guaranteed frontier: plan=2, guaranteed=1"
      tuningSpecBaseline
      (withTuningBudget (RawTuningBudget 12 3 2 100))
  , specControl
      "request-dimension-tuning-spec-seed-mismatch"
      "a run whose first seed differs from the spec's sampler seed must be rejected"
      "run seed mismatch: plan=5, execution-spec=11"
      tuningSpecBaseline
      tuningPlanBaseline {rawTuningRun = tuningBaseline {rawRunSeeds = [5, 6]}}
  ]
 where
  specControl name description reason spec plan =
    request name description $
      singleWorkloadError
        (InvalidTuningExecutionSpec reason)
        (resolveTuningPlanWithExecutionSpec spec plan)
  withTuningBudget budget =
    tuningPlanBaseline {rawTuningRun = tuningBaseline {rawRunBudget = budget}}

-- Versioned plan transport -----------------------------------------------------

-- | One workload plan kind's rendered transport and the parser that must
-- re-refine it.
data TransportSubject = TransportSubject
  { tsKind :: Text
  , tsWireKind :: Text
  , tsOtherWireKind :: Text
  -- ^ The wire kind of a different workload, used to relabel the transport.
  , tsNumericField :: (Text, Text)
  -- ^ One numeric field of the transport and its rendered value.
  , tsText :: Either Text Text
  , tsParse :: Text -> Validation (NonEmpty WorkloadPlanError) ()
  }

transportSubjects :: [TransportSubject]
transportSubjects =
  [ TransportSubject
      { tsKind = "supervised"
      , tsWireKind = "supervised-training"
      , tsOtherWireKind = "alphazero-self-play"
      , tsNumericField = ("epochs", "2")
      , tsText =
          rendered
            (resolveSupervisedPlan supervisedPlanBaseline)
            renderSupervisedPlanTransport
      , tsParse = void . parseSupervisedPlanTransport
      }
  , TransportSubject
      { tsKind = "tuning"
      , tsWireKind = "hyperparameter-tuning"
      , tsOtherWireKind = "supervised-training"
      , tsNumericField = ("trials", "12")
      , tsText =
          rendered
            (resolveTuningPlan tuningPlanBaseline)
            renderTuningPlanTransport
      , tsParse = void . parseTuningPlanTransport
      }
  , TransportSubject
      { tsKind = "alphazero"
      , tsWireKind = "alphazero-self-play"
      , tsOtherWireKind = "hyperparameter-tuning"
      , tsNumericField = ("generations", "2")
      , tsText =
          rendered
            (resolveAlphaZeroPlan alphaZeroPlanBaseline)
            renderAlphaZeroPlanTransport
      , tsParse = void . parseAlphaZeroPlanTransport
      }
  ]
 where
  rendered result render =
    case result of
      Success plan -> Right (render plan)
      Failure errors ->
        Left ("workload plan baseline failed to resolve: " <> Text.pack (show errors))

transportControls :: [NegativeControl]
transportControls =
  concatMap subjectControls transportSubjects
    <> supervisedOnlyControls
 where
  subjectControls subject =
    [ subjectControl
        subject
        ("request-transport-version-" <> tsKind subject <> "-" <> Text.pack (show version))
        ( "a "
            <> tsKind subject
            <> " plan transport declaring version "
            <> Text.pack (show version)
            <> " is not the supported version 1 and must be rejected"
        )
        ( singleWorkloadError (UnsupportedTransportVersion version)
            . tsParse subject
            . Text.replace "transport-version=1" ("transport-version=" <> Text.pack (show version))
        )
    | version <- [0, 2]
    ]
      <> [ subjectControl
             subject
             ("request-transport-plan-id-mismatch-" <> tsKind subject)
             ( "a "
                 <> tsKind subject
                 <> " transport whose declared plan-id is not the re-derived identity must be rejected"
             )
             ( \text ->
                 let tampered = Text.replicate 64 "0"
                  in planIdMismatch
                       tampered
                       (tsParse subject (Text.replace (declaredPlanId text) tampered text))
             )
         , subjectControl
             subject
             ("request-transport-kind-mismatch-" <> tsKind subject)
             ( "a "
                 <> tsKind subject
                 <> " transport relabelled as another workload kind must be rejected as a kind mismatch"
             )
             ( singleWorkloadError (TransportKindMismatch (tsWireKind subject) (tsOtherWireKind subject))
                 . tsParse subject
                 . Text.replace ("kind=" <> tsWireKind subject) ("kind=" <> tsOtherWireKind subject)
             )
         , subjectControl
             subject
             ("request-transport-invalid-value-" <> tsKind subject)
             ( "a "
                 <> tsKind subject
                 <> " transport with a non-numeric quantity must be rejected"
             )
             ( \text ->
                 let (field, value) = tsNumericField subject
                  in singleWorkloadError
                       (InvalidTransportValue field "abc")
                       ( tsParse
                           subject
                           (Text.replace ("|" <> field <> "=" <> value) ("|" <> field <> "=abc") text)
                       )
             )
         ]
  subjectControl subject name description check =
    request name description $
      withFixture (tsText subject) check
  supervisedOnlyControls =
    [ supervisedControl
        "request-transport-run-version-supervised"
        "a supervised transport carrying run-version 9 must re-refine to an unsupported run-plan version"
        ( \text parse ->
            singleWorkloadError
              (CommonRunPlanError (UnsupportedRunPlanVersion 9))
              (parse (Text.replace "run-version=1" "run-version=9" text))
        )
    , supervisedControl
        "request-transport-missing-field-epochs"
        "a transport without its epochs field must be rejected"
        ( \text parse ->
            singleWorkloadError
              (MissingTransportField "epochs")
              (parse (Text.replace "|epochs=2" "" text))
        )
    , supervisedControl
        "request-transport-duplicate-field-epochs"
        "a transport repeating a field must be rejected"
        ( \text parse ->
            singleWorkloadError
              (DuplicateTransportField "epochs")
              (parse (text <> "|epochs=3"))
        )
    , supervisedControl
        "request-transport-unknown-field"
        "a transport carrying a field outside the schema must be rejected"
        ( \text parse ->
            singleWorkloadError
              (UnknownTransportField "future-field")
              (parse (text <> "|future-field=1"))
        )
    , supervisedControl
        "request-transport-derived-quantity-mismatch"
        "a transport whose optimizer-updates disagree with epochs x steps must re-refine to a derived-quantity mismatch"
        ( \text parse ->
            singleWorkloadError
              (CommonRunPlanError (DerivedQuantityMismatch "optimizer-updates" 8 9))
              (parse (Text.replace "optimizer-updates=8" "optimizer-updates=9" text))
        )
    , supervisedControl
        "request-transport-empty-text"
        "an empty transport must be rejected as a malformed line"
        (\_ parse -> singleWorkloadError (InvalidTransportLine 1 "") (parse ""))
    ]
  supervisedControl name description check =
    case transportSubjects of
      subject : _ -> subjectControl subject name description (\text -> check text (tsParse subject))
      [] -> request name description (fixtureFailed "no transport subject is registered")

-- | The plan-id field of a rendered transport.
declaredPlanId :: Text -> Text
declaredPlanId text =
  Text.takeWhile (/= '|') (Text.drop (Text.length marker) (snd (Text.breakOn marker text)))
 where
  marker = "plan-id="

planIdMismatch
  :: Text
  -> Validation (NonEmpty WorkloadPlanError) ()
  -> ControlOutcome
planIdMismatch tampered =
  rejectedOnlyWhere
    "TransportPlanIdMismatch naming the tampered declared id"
    ( \case
        TransportPlanIdMismatch observed _derived -> observed == tampered
        _ -> False
    )
    . validationToEither

-- RL compiled-plan transport -------------------------------------------------

rlPlanTransport :: Either Text Text
rlPlanTransport =
  ProductBudget.renderCompiledRlPlanTransport
    <$> ProductBudget.compileRlPlan
      ProductBudget.TrainingPlan
        { ProductBudget.trainingPlanTrainerKind = "ppo"
        , ProductBudget.trainingPlanEnvironment = "cartpole"
        , ProductBudget.trainingPlanSeed = 1
        , ProductBudget.trainingPlanMaxEpisodeSteps = 200
        , ProductBudget.trainingPlanEpisodeBudgetFloor = 20
        , ProductBudget.trainingPlanVectorEnvironments = Nothing
        , ProductBudget.trainingPlanRequestedTransitionFloor = Nothing
        , ProductBudget.trainingPlanExactTransitionTarget = Nothing
        }
      (ProductBudget.EvaluationPlan 5)

rlPlanTransportControls :: [NegativeControl]
rlPlanTransportControls =
  [ request
      "request-transport-rl-compiled-plan-version"
      "a compiled RL plan transport declaring version 2 must be rejected as non-canonical"
      ( withFixture rlPlanTransport $ \text ->
          rejectedWith
            "compiled RL plan transport is not canonical"
            ( void
                ( ProductBudget.parseCompiledRlPlanTransport
                    (Text.replace "transport-version=1" "transport-version=2" text)
                )
            )
      )
  , request
      "request-transport-rl-compiled-plan-id-mismatch"
      "a compiled RL plan transport whose declared id is not the re-derived id must be rejected"
      ( withFixture rlPlanTransport $ \text ->
          rejectedWith
            "compiled RL plan id does not match its declared transport id"
            (void (ProductBudget.parseCompiledRlPlanTransport (Text.replace "plan-id=" "plan-id=0000" text)))
      )
  , request
      "request-transport-rl-compiled-plan-malformed"
      "a compiled RL plan transport that is not key=value fields must be rejected"
      ( rejectedWith
          "malformed RL plan transport field: garbage"
          (void (ProductBudget.parseCompiledRlPlanTransport "garbage"))
      )
  ]

-- ProductRow projection ------------------------------------------------------

canonicalRow :: Text -> Either Text (ProductMatrix.ProductRow 'ProductMatrix.Declared)
canonicalRow ident =
  maybe
    (Left ("missing canonical ProductRow " <> ident))
    Right
    (find ((== ident) . ProductMatrix.rowId) ProductMatrix.allProductRows)

-- | Project a row for the linux-cpu lane; it must fail with exactly this list.
projectionRejected
  :: NonEmpty ProductMatrix.ProductProjectionError
  -> ProductMatrix.ProductRow state
  -> ControlOutcome
projectionRejected expected row =
  rejectedWith expected $
    case ProductMatrix.projectProductRow LinuxCPU row of
      Failure errors -> Left errors
      Success _ -> Right ()

-- | Rewrite the plan descriptor of an executable canonical row.  The rewrite is
-- polymorphic in the descriptor's run kind, so it can be applied to any row.
withDescriptor
  :: Text
  -> ( forall kind
        . ProductMatrix.ProductPlanDescriptor kind
       -> ProductMatrix.ProductPlanDescriptor kind
     )
  -> Either Text (ProductMatrix.ProductRow 'ProductMatrix.Declared)
withDescriptor ident rewrite = do
  row <- canonicalRow ident
  case ProductMatrix.productCapability row of
    ProductMatrix.ExecutableProduct descriptor requirements ->
      Right
        row
          { ProductMatrix.productCapability =
              ProductMatrix.ExecutableProduct (rewrite descriptor) requirements
          }
    ProductMatrix.UnsupportedProduct reason ->
      Left ("ProductRow " <> ident <> " is not executable: " <> reason)

-- | Re-declare a canonical RL row as a different algorithm/environment pair,
-- keeping the row's registry claims in step so the pair is the only defect.
withRlPair
  :: Text
  -> Text
  -> Text
  -> Either Text (ProductMatrix.ProductRow 'ProductMatrix.Declared)
withRlPair ident algorithm environment = do
  row <-
    withDescriptor ident $ \case
      ProductMatrix.RlProductDescriptor _ _ rollout vectors episode evaluation ->
        ProductMatrix.RlProductDescriptor algorithm environment rollout vectors episode evaluation
      other -> other
  Right
    row
      { ProductMatrix.rowClass =
          if Text.toCaseFold algorithm == "her"
            then ProductMatrix.RlGoalConditioned environment
            else ProductMatrix.RlAlgorithmEnvironment algorithm environment
      , ProductMatrix.implementation =
          if Text.toCaseFold algorithm == "her"
            then ProductMatrix.implementation row
            else "JitML.RL.Algorithms.Registry.moduleFor/" <> algorithm
      }

rlPairControl :: Text -> Text -> Text -> Text -> Text -> Text -> NegativeControl
rlPairControl name description ident algorithm environment message =
  request name description $
    withFixture (withRlPair ident algorithm environment) $
      projectionRejected (ProductMatrix.InvalidProductRlSchedule ident message :| [])

productRowControls :: [NegativeControl]
productRowControls =
  [ rlPairControl
      "request-rl-incompatible-pair-sac-cartpole"
      "SAC is a continuous-control trainer and cannot be projected onto discrete cartpole"
      "SAC/pendulum"
      "SAC"
      "cartpole"
      "RL trainer sac does not support environment cartpole; supported environments: pendulum, lunar-lander"
  , rlPairControl
      "request-rl-incompatible-pair-dqn-pendulum"
      "DQN is a discrete-action trainer and cannot be projected onto continuous pendulum"
      "DQN/cartpole"
      "DQN"
      "pendulum"
      "RL trainer dqn does not support environment pendulum; supported environments: cartpole, mountain-car, key-door-grid"
  , rlPairControl
      "request-rl-incompatible-pair-her-cartpole"
      "HER is goal-conditioned and cannot be projected onto cartpole"
      "HER/goal-reaching"
      "HER"
      "cartpole"
      "RL trainer her does not support environment cartpole; supported environments: goal-reaching"
  , rlPairControl
      "request-rl-incompatible-pair-ppo-pendulum"
      "PPO is a discrete-action trainer and cannot be projected onto continuous pendulum"
      "PPO/cartpole"
      "PPO"
      "pendulum"
      "RL trainer ppo does not support environment pendulum; supported environments: cartpole, mountain-car, acrobot, lunar-lander, key-door-grid, gridworld-deterministic"
  , rlPairControl
      "request-rl-unknown-environment"
      "a known trainer paired with an environment outside its supported set must be rejected"
      "PPO/cartpole"
      "PPO"
      "unknown-env"
      "RL trainer ppo does not support environment unknown-env; supported environments: cartpole, mountain-car, acrobot, lunar-lander, key-door-grid, gridworld-deterministic"
  , rlPairControl
      "request-rl-unknown-algorithm"
      "an unregistered algorithm passes the pair-compatibility relation, so the schedule planner must fail closed on it"
      "PPO/cartpole"
      "NOPE"
      "cartpole"
      "unknown RL trainer schedule: nope"
  , request
      "request-alphazero-unknown-game-product-row"
      "an AlphaZero row re-declared for a game outside the catalog must be rejected by workload refinement"
      ( withFixture unknownGameRow $
          projectionRejected
            ( ProductMatrix.InvalidProductWorkloadPlan
                "connect4"
                (UnknownAlphaZeroGame "chess")
                :| []
            )
      )
  , request
      "request-product-row-zero-training-examples"
      "a supervised row with zero training examples must be rejected, together with the update count derived from it"
      ( withFixture
          ( withDescriptor "mnist-shallow-mlp" $ \case
              ProductMatrix.SupervisedProductDescriptor _ evaluation batch rate ->
                ProductMatrix.SupervisedProductDescriptor 0 evaluation batch rate
              other -> other
          )
          ( projectionRejected
              ( ProductMatrix.InvalidProductWorkloadPlan
                  "mnist-shallow-mlp"
                  (CommonRunPlanError (NonPositiveQuantity "training-examples"))
                  :| [ ProductMatrix.InvalidProductWorkloadPlan
                         "mnist-shallow-mlp"
                         (CommonRunPlanError (NonPositiveQuantity "optimizer-updates"))
                     ]
              )
          )
      )
  , request
      "request-product-row-zero-evaluation-examples"
      "a supervised row with zero evaluation examples must be rejected"
      ( withFixture
          ( withDescriptor "mnist-shallow-mlp" $ \case
              ProductMatrix.SupervisedProductDescriptor training _ batch rate ->
                ProductMatrix.SupervisedProductDescriptor training 0 batch rate
              other -> other
          )
          ( projectionRejected
              ( ProductMatrix.InvalidProductWorkloadPlan
                  "mnist-shallow-mlp"
                  (CommonRunPlanError (NonPositiveQuantity "evaluation-examples"))
                  :| []
              )
          )
      )
  , request
      "request-product-row-zero-vector-environments"
      "an RL row with zero vector environments must be rejected by both the schedule and the plan"
      ( withFixture
          ( withDescriptor "PPO/cartpole" $ \case
              ProductMatrix.RlProductDescriptor algorithm environment rollout _ episode evaluation ->
                ProductMatrix.RlProductDescriptor algorithm environment rollout 0 episode evaluation
              other -> other
          )
          ( projectionRejected
              ( ProductMatrix.InvalidProductRlSchedule
                  "PPO/cartpole"
                  "RL vector-environment count must be positive"
                  :| [ ProductMatrix.InvalidProductRunPlan
                         "PPO/cartpole"
                         (NonPositiveQuantity "vector-environments")
                     ]
              )
          )
      )
  , request
      "request-product-row-zero-parallel-trials"
      "a tuning row with zero parallel trials must be rejected"
      ( withFixture
          ( withDescriptor "hyperparameter-tuning" $ \case
              ProductMatrix.TuningProductDescriptor spec _ promotions updates ->
                ProductMatrix.TuningProductDescriptor spec 0 promotions updates
              other -> other
          )
          ( projectionRejected
              ( ProductMatrix.InvalidProductWorkloadPlan
                  "hyperparameter-tuning"
                  (CommonRunPlanError (NonPositiveQuantity "parallel-trials"))
                  :| []
              )
          )
      )
  , request
      "request-product-row-zero-arena-games"
      "an AlphaZero row with zero arena games must be rejected"
      ( withFixture
          ( withDescriptor "connect4" $ \case
              ProductMatrix.AlphaZeroProductDescriptor game games simulations plies updates _ ->
                ProductMatrix.AlphaZeroProductDescriptor game games simulations plies updates 0
              other -> other
          )
          ( projectionRejected
              ( ProductMatrix.InvalidProductWorkloadPlan
                  "connect4"
                  (CommonRunPlanError (NonPositiveQuantity "arena-games"))
                  :| []
              )
          )
      )
  , request
      "request-batch-empty"
      "an empty registry slice must not project to an executable batch"
      ( batchRejected
          (ProductMatrix.EmptyProductProjectionBatch :| [])
          ( ProductMatrix.projectProductRows
              LinuxCPU
              ([] :: [ProductMatrix.ProductRow 'ProductMatrix.Declared])
          )
      )
  , request
      "request-batch-duplicate-row"
      "a registry slice naming one row twice must not project to an executable batch"
      ( withFixture (canonicalRow "mnist-shallow-mlp") $ \row ->
          batchRejected
            ( ProductMatrix.DuplicateProductRowId "mnist-shallow-mlp"
                :| [ ProductMatrix.DuplicateProductExperimentHash "product-row-mnist-shallow-mlp"
                   , ProductMatrix.DuplicateProductIntegrationTest "integration.product.mnist-shallow-mlp"
                   , ProductMatrix.DuplicateProductE2ETest "e2e.product.mnist-shallow-mlp"
                   ]
            )
            (ProductMatrix.projectProductRows LinuxCPU [row, row])
      )
  ]
 where
  batchRejected expected result =
    rejectedWith expected $
      case result of
        Failure errors -> Left errors
        Success _ -> Right ()

-- | The connect4 row re-declared for a game outside the catalog, with its row
-- class and descriptor kept in step.
unknownGameRow :: Either Text (ProductMatrix.ProductRow 'ProductMatrix.Declared)
unknownGameRow = do
  row <-
    withDescriptor "connect4" $ \case
      ProductMatrix.AlphaZeroProductDescriptor _ games simulations plies updates arena ->
        ProductMatrix.AlphaZeroProductDescriptor "chess" games simulations plies updates arena
      other -> other
  Right row {ProductMatrix.rowClass = ProductMatrix.AlphaZeroGame "chess"}

-- Typed cohort ---------------------------------------------------------------

cohortControls :: [NegativeControl]
cohortControls =
  [ cohort
      "request-cohort-sac-cartpole"
      "the typed cohort has no value for SAC on cartpole"
      "SAC"
      "cartpole"
      "RL trainer sac does not support environment cartpole; supported environments: pendulum, lunar-lander"
  , cohort
      "request-cohort-dqn-pendulum"
      "the typed cohort has no value for DQN on pendulum"
      "DQN"
      "pendulum"
      "RL trainer dqn does not support environment pendulum; supported environments: cartpole, mountain-car, key-door-grid"
  , cohort
      "request-cohort-her-cartpole"
      "the typed cohort has no value for HER on cartpole"
      "HER"
      "cartpole"
      "RL trainer her does not support environment cartpole; supported environments: goal-reaching"
  , cohort
      "request-cohort-ppo-pendulum"
      "the typed cohort has no value for PPO on pendulum"
      "PPO"
      "pendulum"
      "RL trainer ppo does not support environment pendulum; supported environments: cartpole, mountain-car, acrobot, lunar-lander, key-door-grid, gridworld-deterministic"
  , cohort
      "request-cohort-unknown-algorithm"
      "the typed cohort has no value for an unregistered algorithm"
      "NOPE"
      "cartpole"
      "unknown RL algorithm: NOPE"
  ]
 where
  cohort name description algorithm environment message =
    request name description $
      rejectedWith message (void (Cohort.mkCohort algorithm environment))

-- Completed-training dimensions ------------------------------------------------

-- | A valid supervised completion DTO: three epochs, observed three epochs.
completionBaseline :: Either Text TrainingBudget.RawCompletedTraining
completionBaseline =
  TrainingBudget.completedTrainingToRaw
    <$> validCompletedTraining planA TrainingBudget.SupervisedEpochBudget 3 (Just 7)

-- | Tampering with the DTO must make refinement fail with this exact message.
completionRejected
  :: Text
  -> (TrainingBudget.RawCompletedTraining -> TrainingBudget.RawCompletedTraining)
  -> ControlOutcome
completionRejected message tamper =
  withFixture completionBaseline $ \raw ->
    rejectedWith message (void (TrainingBudget.refineCompletedTraining (tamper raw)))

completionDimensionControls :: [NegativeControl]
completionDimensionControls =
  [ request
      "request-dimension-completion-observed-kind"
      "a completion that counted RL environment steps against an epoch budget must be rejected as a kind mismatch"
      ( completionRejected
          "training budget kind mismatch: plan supervised-epochs, observed rl-environment-steps"
          ( \raw ->
              raw
                { TrainingBudget.rawCompletedTrainingObservedKind =
                    TrainingBudget.RlEnvironmentStepBudget
                }
          )
      )
  , request
      "request-dimension-completion-observed-unit"
      "a completion that labelled its observed units environment-steps against an epoch budget must be rejected as a unit mismatch"
      ( completionRejected
          "training budget unit mismatch: plan epochs, observed environment-steps"
          (\raw -> raw {TrainingBudget.rawCompletedTrainingObservedUnitLabel = "environment-steps"})
      )
  , request
      "request-dimension-completion-zero-target"
      "a completion whose budget target is zero must be rejected"
      ( completionRejected
          "training budget must have a positive target"
          ( \raw ->
              raw
                { TrainingBudget.rawCompletedTrainingBudget =
                    (TrainingBudget.rawCompletedTrainingBudget raw)
                      { TrainingBudget.rawTrainingBudgetTargetUnits = 0
                      }
                }
          )
      )
  ]

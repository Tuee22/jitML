{-# LANGUAGE OverloadedStrings #-}

-- | Phase 32 (Sprint 32.1) — the external-truth negative-control suite.
--
-- The audit's root-cause finding was that "Done" was graded by self-authored,
-- self-referential gates. A negative control inverts that: it commits a
-- KNOWN-FAKE artifact and asserts the gate __rejects__ it. A gate that cannot
-- reject its known-fake is not a gate — the build fails.
-- See [Exit Definition item 25](../../../DEVELOPMENT_PLAN/README.md#exit-definition)
-- and [phase-32-external-truth-realness-harness.md](../../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md).
--
-- __Validation status:__ this module is UNVALIDATED — it was authored without a
-- compiler in-session and must be built in the container
-- (@docker compose build jitml@ / @jitml test jitml-negative-controls --linux-cpu@).
--
-- The controls below are __gate-soundness__ controls: they exercise the pure
-- gate logic (`RowAssertions`, `ExternalBars`) against hand-built known-fakes and
-- assert rejection. They pass today because those pure gates are sound in
-- isolation. The gates that are __broken in the production path__ (RL reward
-- provenance, the all-zeros initial-weight hash, the residual-MLP-as-CNN
-- topology) require production hooks that do not exist yet; those are enumerated
-- in 'pendingProductionControls' and become live controls as the reopened
-- Phases 19/21/23/24/25 wire them.
module JitML.Test.NegativeControls
  ( ControlOutcome (..)
  , NegativeControl (..)
  , controlRejected
  , gateSoundnessControls
  , runNegativeControls
  , pendingProductionControls
  )
where

import Data.Text (Text)

import JitML.Product.Convergence qualified as Convergence
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Test.RowAssertions qualified as RowAssertions
import JitML.Training.Budget (MetricGoal (..))

-- | Whether a gate accepted or rejected a known-fake artifact.
data ControlOutcome
  = Rejected
  | Accepted
  deriving stock (Eq, Show)

-- | A committed known-fake paired with the observed gate outcome. The control
-- passes iff the gate 'Rejected' the fake.
data NegativeControl = NegativeControl
  { ncName :: Text
  , ncDescription :: Text
  , ncOutcome :: ControlOutcome
  }
  deriving stock (Eq, Show)

controlRejected :: NegativeControl -> Bool
controlRejected nc = ncOutcome nc == Rejected

-- | Return one failure message per control whose gate ACCEPTED its known-fake
-- (i.e. the gate is broken). An empty list means every known-fake was rejected.
runNegativeControls :: [NegativeControl] -> [Text]
runNegativeControls = concatMap check
 where
  check nc
    | controlRejected nc = []
    | otherwise =
        [ "negative control ACCEPTED a known fake (gate is broken): "
            <> ncName nc
            <> " — "
            <> ncDescription nc
        ]

-- | A gate that returns a non-empty failure list has rejected the artifact.
outcomeOf :: [Text] -> ControlOutcome
outcomeOf failures
  | null failures = Accepted
  | otherwise = Rejected

gateSoundnessControls :: [NegativeControl]
gateSoundnessControls =
  [ NegativeControl
      "untrained-learned-state"
      "an init == final parameter hash (no weight movement) must be rejected"
      (outcomeOf (RowAssertions.assertLearnedStateChanged untrainedLearnedState))
  , NegativeControl
      "self-referential-convergence-bar"
      "a slack-0 bar built from the measured value (value >= value) must be rejected"
      (outcomeOf (ExternalBars.assertProductBarExternal selfReferentialBar selfReferentialMeasured))
  , NegativeControl
      "synthetic-rl-transition"
      "RL row evidence flagged as synthetic-transition must be rejected"
      (outcomeOf (RowAssertions.assertRlRowEvidence syntheticRlEvidence))
  , NegativeControl
      "below-threshold-supervised"
      "an SL test metric below (threshold - slack) must fail convergence"
      (outcomeOf (RowAssertions.assertSupervisedRowEvidence belowThresholdSl))
  , NegativeControl
      "untrained-supervised-weights"
      "an SL init == final weight hash (no weight movement) must be rejected"
      (outcomeOf (RowAssertions.assertSupervisedRowEvidence untrainedSl))
  ]

-- Known-fake fixtures -------------------------------------------------------

untrainedLearnedState :: RowAssertions.LearnedStateEvidence
untrainedLearnedState =
  RowAssertions.LearnedStateEvidence
    { RowAssertions.lseRowId = "negcontrol-untrained"
    , RowAssertions.lseInitialParamHash = "identical-hash"
    , RowAssertions.lseFinalParamHash = "identical-hash"
    , RowAssertions.lseUpdateCount = 10
    }

selfReferentialMeasured :: Double
selfReferentialMeasured = 0.42

-- | Exactly how the production path built its bar: target = measured value,
-- slack = 0 (see @convergenceObservationsForMetrics@ in @JitML.App@).
selfReferentialBar :: Convergence.ConvergenceBar
selfReferentialBar =
  Convergence.mkConvergenceBar "test_accuracy" MetricMaximise selfReferentialMeasured 0.0

syntheticRlEvidence :: RowAssertions.RlRowEvidence
syntheticRlEvidence =
  RowAssertions.RlRowEvidence
    { RowAssertions.rleRowId = "PPO/cartpole"
    , RowAssertions.rleAlgorithm = "PPO"
    , RowAssertions.rleEnvironment = "cartpole"
    , RowAssertions.rleInitialPolicyHash = "initial-policy-sha"
    , RowAssertions.rleFinalPolicyHash = "final-policy-sha"
    , RowAssertions.rleUpdateCount = 100
    , RowAssertions.rleObservedUnits = 25_600
    , RowAssertions.rleDeviceEvidence = "linux-cpu:oneDNN"
    , RowAssertions.rleMetricName = "median_final_reward"
    , RowAssertions.rleMetricGoal = MetricMaximise
    , RowAssertions.rleMetricValue = 460.0
    , RowAssertions.rleConvergenceThreshold = 475.0
    , RowAssertions.rleConvergenceSlack = 25.0
    , RowAssertions.rleSyntheticTransitionEvidence = True
    }

-- | A fully-valid supervised evidence record used as the baseline the fakes
-- perturb by a single field, so the rejection isolates one defect.
validSupervisedBase :: RowAssertions.SupervisedRowEvidence
validSupervisedBase =
  RowAssertions.SupervisedRowEvidence
    { RowAssertions.sreRowId = "mnist-shallow-mlp"
    , RowAssertions.sreInitialWeightHash = "initial-weight-sha"
    , RowAssertions.sreFinalWeightHash = "final-weight-sha"
    , RowAssertions.sreUpdateCount = 500
    , RowAssertions.sreTrainExamples = 60_000
    , RowAssertions.sreValidationExamples = 5_000
    , RowAssertions.sreTestExamples = 10_000
    , RowAssertions.sreExamplesSeen = 300_000
    , RowAssertions.sreThroughputExamples = 1200.0
    , RowAssertions.sreTrainLoss = 0.05
    , RowAssertions.sreValidationLoss = 0.06
    , RowAssertions.sreTestMetricName = "test_accuracy"
    , RowAssertions.sreTestMetricGoal = MetricMaximise
    , RowAssertions.sreTestMetricValue = 0.985
    , RowAssertions.sreConvergenceThreshold = 0.98
    , RowAssertions.sreConvergenceSlack = 0.02
    , RowAssertions.sreGradientNorm = 0.30
    , RowAssertions.sreSmokeThreshold = False
    }

belowThresholdSl :: RowAssertions.SupervisedRowEvidence
belowThresholdSl =
  validSupervisedBase {RowAssertions.sreTestMetricValue = 0.10}

untrainedSl :: RowAssertions.SupervisedRowEvidence
untrainedSl =
  validSupervisedBase
    { RowAssertions.sreFinalWeightHash =
        RowAssertions.sreInitialWeightHash validSupervisedBase
    }

-- | Controls that require production hooks not yet present. Each becomes a live
-- gate-soundness control once its owning reopened sprint lands; until then it is
-- documented here so the suite's coverage gap is explicit rather than silent.
pendingProductionControls :: [Text]
pendingProductionControls =
  [ "rl-reward-provenance: RlRowEvidence must carry a reward-source tag and reject a scripted-controller source (owned by reopened Phase 25 — delete canonicalDiscreteEvaluation / *ExpertAction in JitML.App)."
  , "real-initial-weight-hash: the training-evidence initial hash must be the real random-init weights, not an all-zeros vector, so an untrained checkpoint fails the movement check end-to-end (owned by reopened Phase 21 — checkpointTrainingEvidenceWithDatasetSha in JitML.App)."
  , "conv-not-dense differential: a Conv2D layer's output must differ from a dense layer of the same shape on a structured input (owned by reopened Phase 23 — JitML.Numerics.LayerGraph runLayerNode)."
  , "inference-eligible-rejects-untrained: decoding an untrained random-init checkpoint must fail InferenceEligible after coPassed is re-derived at decode against the external bar (owned by reopened Phase 21 — JitML.Checkpoint.Format)."
  ]

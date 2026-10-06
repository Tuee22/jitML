# Training Metrics and Data Splits

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [root README](../../README.md), [engineering index](README.md), [training workloads](training_workloads.md), [numerical core](numerical_core.md), [checkpoint format](checkpoint_format.md), [PureScript frontend](purescript_frontend.md), [typed run contract](run_contract.md), [legacy-to-new phase map](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [Phase 262](../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md), [Phase 278](../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md)
**Generated sections**: none

> **Purpose**: The single source of truth for jitML's supervised-learning
> train/test/validation split discipline and convergence/performance metric
> definitions for SL, RL, AlphaZero, and tuning.

## Current Status

The bar discipline below is the contract. Its anchoring invariant is enforced by
two predicates and a source lint (first point); what a literal constant's origin
is cannot be enforced mechanically (second point), so this section states that
boundary rather than letting the target read as implemented.

- **The no-self-referential-threshold invariant is enforced at three points.**
  `ExternalBars.assertProductBarExternal` rejects a bar with non-positive slack,
  non-finite fields, or a threshold that is not the target moved by its slack.
  `ExternalBars.assertConvergenceObservationsAgainstBar` grades a completed
  observation set against the ProductRow's *own* bar: exactly one observation of
  the row's metric, carrying the bar's goal and threshold, the value the bar was
  evaluated with, and a verdict re-derived from that value rather than trusted.
  The source lint (`JitML.Lint.ProductTruth`) rejects a bar target, slack, or
  threshold that mentions a measured value directly or through bindings, and any
  numeric bar argument that is neither a literal nor a projection of the
  canonical threshold tables (a selector applied as the whole argument); see
  [Product Completion Contract](product_completion_contract.md#realness-completion-bar-2026-07-05)
  for its coverage and limits.
- **Provenance of a literal is not something a predicate can establish.** A
  positive slack does not prove the target came from an external source, and a
  literal constant is accepted whatever its origin: the lint shows that a bar is
  not *computed* from a measurement, not that its constants were chosen
  independently of one. Positive slack also does not by itself make a bar
  meaningful: some committed cohorts carry slack wide enough that the resulting
  bar is not a real assertion against its environment.

The second point is owned by
[Phase 278](../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md),
which is where the current status and the closing work are tracked.

Per-model completed-run evidence has its own stated boundary. The
`jitml-model-convergence` stanza
([Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md))
grades opaque evidence minted only from the retained, pinned lane journals, so
it is exactly as current as those journals and fails closed on a stale one. The
journals retain no per-iteration learning curve, no per-episode evaluation set,
and no served-artifact inference measurement, and every current ProductRow plans
a singleton seed cohort; see
[Per-Model Completed-Run Evidence](#per-model-completed-run-evidence).

## Invariants

- **No hardcoded weights.** Every model — including checkpoints exposed by demo
  surfaces — uses weights produced by the model's declared training workflow with correct
  per-tensor shapes; synthetic, zero-padded, byte-identical, randomly
  initialized, or untrained payloads are prohibited (see
  [checkpoint_format.md](checkpoint_format.md)).
- **Real losses.** The published training loss is a real cross-entropy (classification) or
  MSE (regression) value computed from the model output — never `1 − accuracy`, and the
  validation loss is a real held-out measurement, not the final training loss.
- **Measured metrics, externally anchored bars.** The convergence and performance
  *metrics* are measured from real training runs, never literature-target
  placeholders. The *bar* each metric is graded against is structurally distinct
  from the measurement, and that separation is what forbids a self-referential
  `threshold = measured` gate. The bar is **externally anchored rather than wholly
  external**: it is `literatureTarget − slack`, where `literatureTarget` is an
  external published constant and `slack` is a project-calibrated per-cohort
  tolerance. `JitML.Product.ExternalBars`
  ([Phase 278](../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md))
  owns the anchoring invariant; the target and slack tables live in
  `JitML.SL.ConvergenceThresholds` and `JitML.RL.ConvergenceThresholds`.
- **Fixed terminating budgets.** A model is not trained "until converged."
  Each canonical model has a pure, reproducible, finite, unit-indexed training
  plan declared before execution. Training must perform exactly that budget
  unless a typed failure aborts the run; convergence is demonstrated by the
  metrics at the completed budget. Budget representation is owned by
  [Typed Plans and Dimensional Budgets](run_contract.md#typed-plans-and-dimensional-budgets).
  For supervised work, hidden `SupervisedPlan` binds epochs, training examples,
  evaluation examples, batch examples, and the derived optimizer-update count;
  its ProductRow projection also binds the exact finite-positive learning rate
  into semantic `PlanId` identity and passes it unchanged to execution;
  refinement requires
  `updates = epochs * ceil(trainingExamples / batchExamples)`. Its canonical
  version-`1` transport determines the `PlanId` used by execution and evidence.
- **Trainer-owned update observations.** The derived count declares the exact
  budget; it is not execution evidence. A successful supervised trainer return
  owns `tmOptimizerUpdatesExecuted` and records it only after every requested
  epoch and mini-batch update has completed. Writer and Product Publisher must
  carry that observed count unchanged and reject any mismatch with the
  `SupervisedPlan`, `CompletedTraining`, or supervised-graph manifest. Callers may not recreate
  a successful count from epochs, dataset size, or batch size after training.
- **Deterministic classification training order is split-local.** After the
  authoritative partitions are materialized, canonical classification training
  stable-sorts the training examples once per one-based epoch by
  `(SplitMixWord, originalZeroBasedIndex)`. The words come from
  `splitMixWords (length trainSet)` with seed
  `deriveSplitMixSeed (SplitMixSeed (fromIntegral clfSeed)) (fromIntegral epoch)`.
  Validation and test remain unpermuted. The permutation changes neither the
  examples in the partition nor the authoritative example/batch quantities,
  batch count/sizes, `examples_processed`, or actual optimizer-update counter.
  The tuning exact-update path remains fixed-order and cyclic.
- **Inference requires persisted completion admission.** Inference cannot accept
  a raw manifest, decoded completion payload, random initialization, or partially
  trained checkpoint. The only value that may flow into an inference runner is
  Store's opaque `AdmittedCompletedCheckpoint`, minted after exact persisted
  envelope, manifest, and blob admission plus completion revalidation.

## Metric Projection into Completed Runs

The generic planning, evidence-reduction, and completion-witness vocabulary
lives in [Typed Run Contract](run_contract.md). This document owns the
training-metric payload projected into that contract.
`JitML.Checkpoint.Format` performs structural completion validation only;
`JitML.Checkpoint.Store` alone combines it with exact persisted-address and
physical-blob evidence before any weight-only inference load.

| Concept | Meaning | Invariant |
|---|---|---|
| `RunPlan kind` | A pure declaration of exact terminating work using unit-indexed quantities and a non-empty seed cohort where required. | Known before execution; no adaptive "keep training until convergence" loop and no stringly unit label. |
| `SupervisedPlan` | The hidden supervised projection of one `RunPlan`, including exact epoch, train/evaluation-example, batch-example, and derived optimizer-update quantities plus its content-derived `PlanId`. | Producer and worker re-refine the same canonical transport; no primitive worker record, clamp, or default may redefine the budget. |
| `TrainingMetrics` successful return | The exact training-returned runtime program, exact initial/final JMW1 bytes, verified dataset-at-read SHA, finite held-out probe, completed budget units, and `tmOptimizerUpdatesExecuted`. | The update count exists only after all epoch/batch loops succeed. Writer and Publisher consume it; neither derives it from the plan. |
| `TrainingEvidence` | The smart-constructed weight-delta witness in `JitML.Product.Evidence`: initial weight hash, final weight hash, trainer-observed positive update count, and dataset SHA observed at read. For product SL rows this SHA is produced by `JitML.SL.Dataset.datasetReadShaForArtifacts` over payloads returned by `fetchVerifiedDatasetArtifactBytes`, after each artifact has matched its pinned SHA and before any decoder receives bytes. | `mkTrainingEvidence` rejects empty hashes, equal initial/final hashes, zero updates, and missing dataset-read provenance; the supervised publication boundary additionally requires exact equality with the successful trainer return and authoritative plan. |
| Product supervised metric projection | Exactly four finite, uniquely named rows in canonical order: `train_loss`, `validation_loss`, `examples_processed`, and the authoritative held-out metric named by the ProductRow convergence bar. | `examples_processed` must equal `epochs * trainingExamples`; extra, reordered, duplicated, renamed, or non-finite rows cannot become Product-origin completion evidence. |
| `CompletedRunEvidence kind` | The opaque result of terminal workload success plus the workload's complete pure evidence contract. | Failed, cancelled, partial, skipped, equal-weight, zero-update, smoke-only, missing-event, or hardcoded-pass runs cannot construct it. |
| `RawCompletedTraining` | The versioned, deliberately forgeable completion DTO: plan identity, raw budget, repeated observed kind/count/unit, training evidence, raw typed criteria/measurements, and TensorBoard metadata. | It is never proof; decode must re-refine it, and the wire carries no authoritative pass boolean. |
| `CompletedTraining` | The checkpoint-facing training projection of completed run evidence: originating `PlanId`, exact observed primary budget, moved learned state, a non-empty set of finite bar-evaluated measurements, and TensorBoard metadata. | Its constructor is hidden. Refinement rejects kind/unit mismatch, underrun, overrun, invalid evidence, zero criteria, and any failed criterion. |
| `AdmittedCheckpoint` | Store's opaque exact persisted checkpoint: addressed canonical outer envelope and typed payload plus independently fetched, address-checked physical blobs and any graph-derived flat layout. | Known-address admission performs no pointer read. Latest admission reads `P1`, verifies the exact addressed manifest, requires exact `P1 == P2`, and only then fetches/binds blobs. A decoded or caller-built manifest cannot construct it. |
| `AdmittedCompletedCheckpoint` | The only value accepted by the shared checkpoint inference loader before `eval`, `inference run`, demo routes, RL rollout/eval, or AlphaZero game endpoints consume weights. | `requireAdmittedCompletedCheckpoint` revalidates mandatory completion only on an `AdmittedCheckpoint`; its constructor is hidden and Product Pipeline consumes this Store value. |

The type boundary is the product requirement: an untrained initialization,
seed-only demo network, hardcoded fixture checkpoint, or transport-smoke
checkpoint cannot cross Store admission as `AdmittedCompletedCheckpoint`.

Persistence preserves the same distinction. Candidate writers accept only a
candidate manifest, return opaque `StoredCandidateCheckpoint`, and never write
the inference-selected `latest` pointer. Completed writers take
`CompletedTraining` directly, return opaque `StoredCompletedCheckpoint` only
after the exact pointer CAS adopts their manifest, and expose no optional-proof
upgrade path. An existing immutable object is idempotent success only when a
follow-up read proves exact byte equality. Local persistence reports
`CheckpointWriteError` with distinct object-conflict and pointer-conflict
constructors; MinIO uses typed `ServiceError` conflicts.

`JitML.Test.RowAssertions` is the executable supervised-row evidence gate used
by Sprint `24.2`. A row evidence record must carry non-empty and unequal
initial/final weight hashes, a positive update count, positive train,
validation, and test split sizes, positive examples seen and throughput,
finite non-negative train/validation losses, a finite held-out test metric, a
finite literature target/slack bar, and a finite positive gradient norm. It
also rejects smoke-threshold evidence and deliberately underpowered two-step
evidence whose held-out metric fails the row's literature/slack bar. Those
records are forgeable, hand-built values kept for the toy-configuration
canonical stanzas and the negative-control fixtures; completed ProductRow
evidence is graded through the opaque `ModelRowEvidence` described under
[Per-Model Completed-Run Evidence](#per-model-completed-run-evidence), for which
`RowAssertions.assertCompletedRowEvidence` is the entry point.

Dataset-read provenance is not an upload-time promise. Product and generic supervised-graph
training obtain artifact bytes through the verified read boundary, record the
observed image/label/archive digest for the row, and only then enter gunzip,
IDX, tar, Zip64/JPEG, or regression parsing. Refinement independently derives
`canonicalDatasetReadShaForProblem` for the exact origin row and requires the
training return, manifest, and completion evidence to equal it. Mirroring one
forged digest into all three values therefore cannot pass admission. Corrupt or
substituted canonical bytes are typed failures before decode and cannot produce
`TrainingEvidence`.

The completed checkpoint records:

- full budget fields;
- completed iteration counters (`completed_epochs`, `completed_env_steps`,
  `completed_self_play_generations`, or `completed_trials`, as applicable);
- initial/final weight hashes, positive update count, and dataset SHA observed
  at read;
- seed-cohort identity;
- substrate and device runner identity;
- convergence-statistics payload for the model;
- performance metric payload;
- TensorBoard run key and scalar tag prefix;
- readiness witness for the checkpoint store and inference loader.

For supervised-graph publication, “positive update count” above means the exact
successful trainer observation, not the mathematically projected budget. The
projection and observation are independent values that must be equal. A failed
or interrupted training call returns no successful `TrainingMetrics` value and
therefore cannot supply the count consumed by completion or checkpoint writing.

Convergence observations are derived by a total evaluator from an independent,
typed criterion and a finite measured payload. The criterion owns its finite
threshold and one closed comparison rule: at-least, at-most, or at-least while
excluding a finite sentinel within a finite non-negative tolerance. A passing
measurement is an opaque `PassedMeasurement` produced only by evaluating that
rule. `CompletedTraining` requires `NonEmpty PassedMeasurement`, so an empty
metric list cannot become a successful completion. The persisted raw
representation records the criterion inputs but carries no freely
constructible `passed` boolean or redundant threshold/verdict pair that can
disagree with the evaluator.

Checkpoint protocol events preserve the same distinction. Training and RL each
have a candidate checkpoint event without completion and a separate completed
checkpoint event whose hidden wrapper carries mandatory, re-refined
`CompletedTraining`. Tuning similarly separates proof-free `SweepFinished`
from proof-bearing `SweepCompleted`. A candidate remains useful for inspection,
resume, and telemetry, but it cannot satisfy product completion or inference
eligibility.

TensorBoard and the PureScript UI consume the same metric names that appear in
the checkpoint manifest. TensorBoard is the scalar history; the UI is the
workflow/control surface and checkpoint selector. Neither invents metrics that
are absent from the manifest.

## SL data splits (R4)

Supervised learning uses a **three-way** split (`JitML.SL.Dataset` `DataSplit`:
`TrainSplit | TestSplit | ValidationSplit`, parsed at `App.hs`, consumed by
`JitML.SL.Classifier` / `JitML.SL.TinyImageNet`):

| Partition | Role |
|---|---|
| **train** | gradient updates only; canonical classification stably permutes this complete partition from the fixed seed and one-based epoch before forming batches |
| **validation** | model **selection** / early-stop — the partition that picks the final model; never trained on |
| **test** | the held-out **final-evaluation** set, measured once on the selected model; never seen during training or selection |

The convergence assertion's final accuracy is reported on the **test** partition; model
selection runs against **validation**. (Datasets whose canonical archive ships no separate
validation partition, e.g. CIFAR-10/100, declare that explicitly rather than reusing test
as validation.) The epoch permutation is never a repartition: each training
example appears exactly once in that epoch's training order, while validation
and test retain their fixed decoder order and membership. Consequently no
split-size, budget, throughput, or observed-update evidence changes merely
because canonical classification training is shuffled.

The current `cifar10-vit` ProductRow keeps **2,000** training examples, forty
epochs, batch size 128, **80,000** processed examples, and **640** observed
successful mini-batch updates in its final typed recipe. Earlier
executable-topology diagnostics used their then-current plans and remain dated
evidence in Sprint `10.6`.
Validation and test values do not influence its RGB fit; all three model-input
partitions receive the transform fitted from training only, while the supervised-graph reload-parity
probe remains in raw `[0,1]` units. Fresh validation uses the descriptor-bound
finite-positive rate (`3e-3` for `fashion-mnist-resnet`, `1.1e-3` for
`cifar10-resnet20`, `1.5e-3` for `cifar10-vit`, and `1e-3` for the other eight
rows), whose value participates in `PlanId` and passes unchanged into
classification or California regression.
Measured diagnostic chronology for the superseded Mixer lives in Sprint
`10.6`; the literal small-ViT graph, its current budget, and its measured
closure evidence subsequently closed through Phases `240`–`246`.

## SL metrics (R3)

- **Convergence** — a cohort converges when the median held-out **test** accuracy
  over the fixed seed cohort clears its `literatureTarget − slack` bar. The
  anchoring invariant is owned by `JitML.Product.ExternalBars`
  ([Phase 278](../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md))
  and the target/slack table by `JitML.SL.ConvergenceThresholds`; the target is an
  external constant, the slack is project-calibrated, and neither is **derived
  from, or set equal to, the measured accuracy**. Regression rows use the declared
  regression metric rather than accuracy. Cross-entropy / MSE training loss and
  held-out validation loss are reported per run. The ProductScenario integration
  journal measures each row end-to-end from a real random initialization, and the
  retained lane journal is that run's committed completed-run evidence. The
  `jitml-model-convergence` stanza
  ([Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md))
  grades every row's opaque completed-run evidence against a criterion
  re-derived independently from `JitML.SL.ConvergenceThresholds`
  (classification) or the `rmse` bar (regression), never from the row's own
  registry bar.
- **Performance** — a **non-wall-clock** work count, never a rate. Wall-clock
  latency is excluded from the determinism contract (see
  [determinism_contract.md](determinism_contract.md)), so the performance metric
  is a distinct, deterministic, non-timing measure: `examples_seen`, the
  training examples the run consumed, which is the observed epoch count times
  the plan's fixed training-split size (every example is consumed exactly once
  per epoch). The committed bound is `AtLeast (epochs × training examples)` in
  `JitML.Product.ExternalBars`, built from the plan's exact planned quantities
  and never from the measured count. The trainer-observed optimizer-update
  count is graded separately, as learning telemetry, against the plan's exact
  `epochs × ceil(training / batch)`. The measurement is bound to the plan,
  experiment, and admitted manifest identity of the same lane-journal row; the
  stanza executes no inference, and the journals retain no served-artifact
  inference measurement. Because lane admission refines exact budget units, the
  observed epoch count of a retained row equals the plan, so this bound guards
  the evidence boundary rather than measuring a run (see
  [Per-Model Completed-Run Evidence](#per-model-completed-run-evidence)).

| Canonical SL model | Fixed budget unit | Stand-alone convergence metric |
|---|---|---|
| `mnist-shallow-mlp` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `mnist-deep-mlp` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `mnist-lenet` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `fashion-mnist-mlp` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `fashion-mnist-resnet` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `cifar10-resnet20` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `cifar10-resnet56` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `cifar100-wide-resnet` | epochs over the fixed train split | median held-out top-1 accuracy over the seed cohort |
| `cifar10-vit` | epochs over the fixed train split | median held-out test accuracy over the seed cohort |
| `tiny-imagenet-resnet50` | epochs over the fixed train split | median held-out top-1 accuracy plus top-5 accuracy over the seed cohort |
| `california-housing-mlp` | epochs over the fixed train split | median held-out RMSE and MSE over the seed cohort |

## RL metrics (R3 / R5)

- **Convergence** — a cohort converges when the **real measured-median** episode
  return over `k` seeds clears its per-cohort return threshold. That threshold is
  `literatureTarget − slack` — an external published target less a
  project-calibrated slack — anchored by `JitML.Product.ExternalBars`
  ([Phase 278](../../DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md))
  and tabulated by `JitML.RL.ConvergenceThresholds`, never derived from the
  measured return. The measured return is a **trained-policy rollout** — the learned policy
  acting in the environment — not a scripted expert controller. ProductScenario
  execution records the trained-policy result, and Phase `285` grades it: each
  per-model `jitml-model-convergence` case consumes that completed-run evidence
  from the retained lane journal and checks its median final reward against a
  criterion re-derived from the RL cohort table (and the HER and AlphaZero
  tables), not from the registry bar.
- **Trainer-owned counters** — every successful traditional trainer returns
  opaque positive `MeasuredEnvironmentTransitions` and
  `MeasuredOptimizerUpdates` values from the loop that executed the work.
  Callers do not reconstruct either value from iteration counts, rollout widths,
  episode horizons, fixed-step limits, or replay settings. The measured physical
  transition count must equal the compiled plan's exact transition target and is
  used unchanged as the checkpoint step and `CompletedTraining` observed budget.
  Traditional RL has no planned optimizer-update quantity: the removed field
  mixed iterations, transitions, and episodes across trainer families. The
  measured update count instead flows unchanged through `TrainingEvidence`,
  completion, and the persisted manifest.
- **Learning versus final evaluation** — `LearningCurve` is a non-empty,
  strictly iteration-ordered sequence of finite trainer-produced
  `IterationSummary` values. `EvaluationSet` is a complete map containing each
  planned zero-based evaluation episode id exactly once, with a finite reward
  and positive actual step count. Each `EpisodeOutcome` also preserves the
  environment's terminal bit: natural termination is `True`, while exhaustion
  of the evaluation episode-step horizon is a truncation and remains `False`.
  Evaluator adapters may not replace that distinction with the fact that their
  own loop finished. Final reward medians consume the full `EvaluationSet`; a
  partial set, tail subset, or broker arrival order is neither a final metric nor
  a learning curve.
- **Row evidence** — neural and learned-policy RL rows record deterministic
  initial/final policy-or-Q hashes, the trainer-owned positive measured counters,
  and `linux-cpu` device evidence before a `CompletedTraining` witness can enter
  the checkpoint manifest. The update count is measured by the trainer against
  the exact flattened tensor whose
  initial/final hashes are recorded: DQN, QR-DQN, and HER report online-Q Adam
  applications; PPO-family rows report combined policy/value minibatch Adam
  applications; TRPO also reports every accepted actor natural-gradient
  application; and continuous-control rows report actor Adam applications only,
  excluding auxiliary critic and temperature state that is not in the hashed
  checkpoint tensor. HER rows use goal success rate and achieved-goal distance
  as their convergence observations.
  Row assertions reject synthetic transitions, missing thresholds, missing
  device evidence, initialized-only checkpoints, and failed convergence.
- **AlphaZero** — convergence is measured by **arena win-rate** against the prior best
  network (a deliberate non-return metric), not an episode-return threshold.
- **Performance** — a non-wall-clock RL sample-efficiency count,
  `environment_transitions`: the physical transitions the trainer counted for
  the completed run, graded against a committed **ceiling** in
  `JitML.Product.ExternalBars`, `AtMost` the plan's environment-transition
  budget, that is never derived from the measured value. A lane journal retains
  no per-iteration curve, so a steps-to-threshold figure cannot be recovered from
  it; the tightest ceiling a final-only journal can prove is the exact budget
  the run consumed, and the Phase `285` case grades that count from the exact
  completed run, bound to its plan and admitted manifest identity. Because
  lane admission refines the exact transition budget, a retained row's count
  equals the plan and the ceiling guards the evidence boundary rather than
  measuring a run (see
  [Per-Model Completed-Run Evidence](#per-model-completed-run-evidence)). The
  same-seed reproducibility assertions stay in `jitml-rl-canonicals` and
  `jitml-backends`.

| RL / self-play model | Fixed budget unit | Stand-alone convergence metric |
|---|---|---|
| PPO, A2C, TRPO, MaskablePPO, RecurrentPPO | training: environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return per algorithm/environment cohort |
| DQN, QR-DQN | training: environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return on discrete-action cohorts |
| DDPG, TD3, SAC, CrossQ, TQC | training: environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return on continuous-control cohorts |
| ARS | training: physical perturbation-rollout environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return and accepted-direction improvement over the seed cohort |
| HER | training: goal-conditioned environment transitions; evaluation: keyed episodes with an episode-step horizon | goal success rate and mean achieved-goal distance |
| AlphaZero Connect 4, Othello, Hex, Gomoku | self-play generations, MCTS simulations per move, and arena games | arena win-rate against the baseline/prior checkpoint plus legal-move rate |
| Hyperparameter tuning | fixed trial count or fixed scheduler-rung budget | best validation objective at the completed budget plus replayable sampler state |

## Per-Model Completed-Run Evidence

[Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md)
makes every per-model assertion of `jitml-model-convergence` consume an opaque,
kind-indexed `ModelRowEvidence` (`JitML.Test.ModelEvidence`) instead of a
registry declaration. The value is completed-run evidence, not a claim that the
run passed: it can carry a below-bar measurement, and the assertions grade it.

**Where it comes from.** The lane journals
(`DEVELOPMENT_PLAN/attestations/<lane>-product-lane-journal.json`, pinned in
`JitML.Test.ProductAggregation.productLaneInputs`) are the committed,
authenticated, versioned completed-run evidence. `admitModelEvidence` reads the
selected lane's registered journal (`JITML_SUBSTRATE`, default `linux-cpu`),
admits it against the current validated projection with the production reader,
and mints one evidence value per ProductRow through a typed join that mirrors
the report join (`Missing`, `Duplicate`, `Orphan`, `WrongPlan`, `WrongLane`,
`StaleContract`). A stale, missing, altered, or inadmissible journal is a typed
failure of every lane-dependent case, by design: loading reports
`LaneJournalNotRegistered`, `LaneJournalUnreadable`, `LaneProjectionRejected`,
or `LaneJournalRejected` (the pinned production reader's own typed reason, such
as a digest mismatch), and a journal that admits but does not join reports
`LaneEvidenceRejected`.

The raw, forgeable view of a journal row, the refinement that mints evidence
from it, and the loader with its pins and registry as arguments
(`loadLaneJournalIn`, which lets a control offer a tampered, missing, or
unregistered journal to the same fail-closed path) are kept in
`JitML.Test.ModelEvidence.Raw`. The cabal library exposes that module, because
the evidence types are shared by the library modules `JitML.Test.RowAssertions`
and `JitML.Test.ModelConvergence` and by the stanza, so a barrier around it is
enforced by the compiler and then by scans rather than by visibility. The
module carries a `WARNING in "x-model-evidence-raw"`, so every importer is
reported whatever its import syntax, and the
`cabal build all --ghc-options=-Werror` pass that `jitml check-code` runs turns
the report into an error for any library or executable module that has not
opted out with an explicit `{-# OPTIONS_GHC -Wno-x-model-evidence-raw #-}`. The
stanza asserts that exactly its four control modules import `Raw` and exactly
those opt out, and that only the two evidence facades import the hidden
`Internal` module. The scan is tokenising: comments, pragmas, and string or
character literals are skipped; a package string, a `SOURCE` pragma, `safe`, a
post-positive `qualified`, and an import split across lines are all seen; and
sources are read as UTF-8 whatever the locale. Its reach is that of the stanza:
it runs only when the stanza runs, a stanza built without `-Werror` sees the
report as a warning, and a blanket `-w` silences the report, which only the
import scan detects.

**Identity binding.** Minting re-checks, against the validated projection, the
row id, `PlanId`, lane, experiment hash, admitted and inference manifest
identities, the report contract digest, the completion's own plan, experiment,
invocation, and device-witness identities, and that the measured digest is the
digest of the completion the values were read from. Any difference is a typed
`BindingMismatch`, not a silent repair.

**Seed cohorts.** Evidence must cover `runPlanSeeds` exactly: a gap, a
duplicate, an extra seed, or an empty cohort is a typed seed-coverage failure,
and every measurement must be finite. The cohort statistic of each criterion is
the median across seeds (the mean of the two middle values for an even cohort).
Every ProductRow plans a singleton cohort today, so for real rows the statistic
is the single value. The k > 1 path is exercised end to end against a real
three-seed plan cohort resolved through the plan contract: per-seed refinement
(`refineSeedCohort`: coverage, finiteness, channel) and cohort grading, with each
defect naming its seed. It is not exercised through a ProductRow, because
expanding a cohort would change every `PlanId` and invalidate the pinned journals.

**Independent criterion.** `JitML.Product.ExternalBars.externalCriteriaFor`
re-derives each row's criterion directly from the canonical tables (SL cohort
table, the `rmse` bar for regression, the RL cohort table, the HER goal metric
with its achieved-goal-distance companion, the AlphaZero arena threshold with
its all-draw exclusion, and the tuning objective), keyed by row identity. The
recorded criterion of each seed (metric name, rule, exclusion parameters,
threshold) must equal it, each required metric must appear exactly once, no
other metric may appear, and the cohort statistic must satisfy it; the registry
bar must also agree with it. These are separate typed failures
(`MissingMetric`, `DuplicateMetric`, `UnexpectedMetric`, `CriterionMismatch`,
`BelowBar`, `RegistryBarDrift`).

**RL learning telemetry versus final quality.** `LearningTelemetry` (observed
budget units, optimizer-update count, weight-hash delta) and `FinalQuality` (the
final-evaluation criterion observations) are distinct types, checked by
distinct assertions (`assertModelLearning`, `assertModelConvergence`) with
distinct failure sums, and neither can stand in for the other. The compiler
prevents passing one where the other is expected; at the raw boundary every
payload declares its channel and a payload offered in the wrong slot, such as a
transition counter that numerically clears the reward bar, is a typed
`RowChannelSubstituted`. `LearningCurve` (strictly ordered iteration summaries)
and `EvaluationSet` (the exact keyed final cohort) remain the per-iteration and
per-episode forms of the two channels; the lane journals retain only their
scalar summaries.

**Deterministic performance bounds.** Bounds live in
`JitML.Product.ExternalBars` as `PerformanceBound` (`AtLeast` | `AtMost`) values
built from the plan's exact planned quantities; nothing the run reports is an
input. The measured quantities are counts the completed evidence records:

| Family | Metric | Measured from the completed run | Committed bound |
|---|---|---|---|
| Supervised | `examples_seen` | observed epochs × plan training examples per epoch | `AtLeast` plan epochs × plan training examples |
| RL, HER | `environment_transitions` | physical transitions the trainer counted | `AtMost` plan environment-transition budget |
| AlphaZero | `alphazero_optimizer_updates` | trainer-observed optimizer applications | `AtLeast` plan generations × optimizer updates per generation |
| Tuning | `promoted_trial_optimizer_updates` | trainer-observed optimizer applications of the promoted trial | `AtLeast` and `AtMost` the plan's per-trial optimizer-update ceiling |

A rate or a quantity the completed evidence does not record is not a
performance metric: `examples_per_second` is a rate, `env_steps_to_threshold`
needs the per-iteration curve, and `arena_nodes_per_inference` and
`objective_evaluations_per_trial` have no measured source, so none of them is
used, and no literal `1.0` floor stands in for a bound. Each performance
measurement is emitted as a receipt bound to the row's `PlanId`, experiment
hash, and admitted manifest identity from the same journal row, never to a
latest pointer.

**What a bound can and cannot catch on retained evidence.** Lane admission
refines each embedded `CompletedTraining` (`Budget.parseCompletedTraining`), and
that refinement requires the observed budget units to equal the plan's target
exactly. On an admitted row the observed-unit counts therefore equal the plan by
construction, so the supervised `examples_seen` floor, the RL and HER
`environment_transitions` ceiling, and the learning check's exact-unit
comparison cannot fail on retained evidence; they guard the evidence boundary (a
raw or forged view, or a journal version that stopped refining exact units), and
each has a control that violates it. The optimizer-update counts differ in kind:
the trainer records them, the issuing scenario's completion projection requires
them to equal the plan (supervised, AlphaZero, and the tuning ceiling), and lane
admission does not re-check them, so the update-count comparison and the
AlphaZero and tuning bounds are the independent re-check of that quantity on
retained evidence. None of these is a measured performance figure. No inference
is executed and no served-artifact measurement is retained, so the receipt
binding compares a receipt with the `PlanId`, experiment hash, and admitted
manifest identity of the journal row it was built from (`assertReceiptBinding`,
one identity at a time): it detects a receipt attached to another row, plan,
experiment, or manifest, not a differently measured artifact.

**What the lane journals cannot carry.** A lane journal retains the refined
`CompletedTraining` of each row: observed units, optimizer-update count,
initial and final weight hashes, dataset digest, the passed cohort measurements,
and the invocation, digest, and device-witness bindings. It retains no
per-iteration learning curve, no per-episode evaluation set, no checkpoint bytes,
and no inference measurement of the served artifact. Consequently the stanza
grades only what those records prove: it cannot compute steps-to-threshold,
re-derive a median from episodes, recompute a served metric, or execute
inference, and it runs no rerun. Same-seed determinism assertions remain where
they were, in `jitml-sl-canonicals`, `jitml-rl-canonicals`, and
`jitml-backends`. Capturing those quantities would need new journal fields,
which re-issues every lane journal.

## Status

This document defines metric semantics, not implementation or closure status.
The current phase state, remaining work, blockers, and validation evidence live
only in the
[Development Plan](../../DEVELOPMENT_PLAN/README.md#closure-status).

## Cross-References

- [Typed Run Contract](run_contract.md)
- [Training Workloads](training_workloads.md)
- [Checkpoint Format](checkpoint_format.md)
- [Product Completion Contract](product_completion_contract.md)
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)

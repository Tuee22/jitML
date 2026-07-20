# Training Metrics and Data Splits

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](../../README.md), [documents/engineering/README.md](README.md), [training_workloads.md](training_workloads.md), [numerical_core.md](numerical_core.md), [checkpoint_format.md](checkpoint_format.md), [purescript_frontend.md](purescript_frontend.md), [run_contract.md](run_contract.md), [DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md](../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md), [DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md](../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md), [DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md](../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md), [DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md), [DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)
**Generated sections**: none

> **Purpose**: The single source of truth for jitML's supervised-learning
> train/test/validation split discipline and convergence/performance metric
> definitions for SL, RL, AlphaZero, and tuning.

## Invariants

- **No hardcoded weights.** Every model — including checkpoints exposed by demo
  surfaces — uses weights produced by the model's declared training workflow with correct
  per-tensor shapes; synthetic, zero-padded, byte-identical, randomly
  initialized, or untrained payloads are prohibited (see
  [checkpoint_format.md](checkpoint_format.md)).
- **Real losses.** The published training loss is a real cross-entropy (classification) or
  MSE (regression) value computed from the model output — never `1 − accuracy`, and the
  validation loss is a real held-out measurement, not the final training loss.
- **Measured metrics, frozen external bars.** The convergence and performance
  *metrics* are measured from real training runs, never literature-target
  placeholders. The *bar* each metric is graded against is the opposite: a **frozen
  external literature constant** held in `JitML.Product.ExternalBars`
  ([Phase 32](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md)) and
  never derived from, or set equal to, the measured value. A row passes only when its
  measured metric clears that independent external bar; keeping the two structurally
  distinct is what forbids a self-referential `threshold = measured` gate.
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
  `SupervisedPlan`, `CompletedTraining`, or V2 manifest. Callers may not recreate
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
  Store's opaque `AdmittedCompletedCheckpoint`, minted after exact persisted V2
  manifest/blob admission and completion revalidation.

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
| `AdmittedCheckpoint` | Store's opaque exact persisted V2 graph: addressed outer/body manifest plus independently fetched, address-checked physical blobs and graph-derived slices. | Known-address admission performs no pointer read. Latest admission reads `P1`, verifies the exact addressed manifest, requires exact `P1 == P2`, and only then fetches/binds blobs. A decoded or caller-built manifest cannot construct it. |
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
evidence whose held-out metric fails the row's literature/slack bar.

Dataset-read provenance is not an upload-time promise. Product and generic V2
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

For supervised V2 publication, “positive update count” above means the exact
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

The current `cifar10-vit` ProductRow keeps **2,000** training examples, five
epochs, batch size 128, **10,000** processed examples, and **80** observed
successful mini-batch updates in its final typed recipe. Earlier
executable-topology diagnostics used their then-current plans and remain dated
evidence in Sprint `10.6`.
Validation and test values do not influence its RGB fit; all three model-input
partitions receive the transform fitted from training only, while the V2 parity
probe remains in raw `[0,1]` units. Fresh validation uses the descriptor-bound
finite-positive rate (`3e-3` for `fashion-mnist-resnet`, `1.1e-3` for
`cifar10-resnet20`, `1.5e-3` for `cifar10-vit`, and `1e-3` for the other eight
rows), whose value participates in `PlanId` and passes unchanged into
classification or California regression.
Measured diagnostic chronology and closure evidence live in Sprint `10.6`;
those Mixer measurements cannot satisfy Blocked Phase `24`'s requirement to
remeasure the eventual literal small-ViT graph.

## SL metrics (R3)

- **Convergence** — a cohort converges when the median held-out **test** accuracy
  over the fixed seed cohort clears its `literatureTarget − slack` bar. That bar is a
  **frozen external literature constant** — owned by `JitML.Product.ExternalBars`
  ([Phase 32](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md)) and
  mirrored in the in-code `JitML.SL.ConvergenceThresholds` — and is **never derived
  from, or set equal to, the measured accuracy**. Regression rows use the declared
  regression metric rather than accuracy. Cross-entropy / MSE training loss and
  held-out validation loss are reported per run. Each row's convergence is measured
  end-to-end from a real random init by its per-model
  [Phase 33](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)
  `jitml-model-convergence` case, not asserted from a declared constant or an
  artifact read.
- **Performance** — a **non-wall-clock** throughput metric (examples/sec). Wall-clock latency
  is excluded from the determinism contract (see [determinism_contract.md](determinism_contract.md)),
  so the performance metric is a distinct, deterministic, non-timing measure.
  Sprint `24.2` treats the deterministic examples-seen count emitted by
  `JitML.SL.Architecture.SlRunMetrics` as the row throughput evidence; it is
  positive and reproducible for the same fixed budget and split. The throughput
  **floor** the metric is graded against is a committed constant in
  `JitML.Product.ExternalBars`
  ([Phase 32](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md)),
  never derived from the measured throughput; every row's non-wall-clock inference
  performance is measured on the trained artifact — and reproduced bit-identically on
  a same-seed re-run — by its per-model
  [Phase 33](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)
  `jitml-model-convergence` case.

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
  return over `k` seeds clears its per-cohort return threshold. That threshold is a
  **frozen external literature constant** (`JitML.Product.ExternalBars`,
  [Phase 32](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md);
  mirrored by `JitML.RL.ConvergenceThresholds`), never derived from the measured
  return. The measured return is a **trained-policy rollout** — the learned policy
  acting in the environment — not a scripted expert controller;
  [Phase 33](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)
  removes the expert-controller probe and evaluates the trained policy in the
  per-model `jitml-model-convergence` case.
- **Row evidence** — neural and learned-policy RL rows record deterministic
  initial/final policy-or-Q hashes, a positive update count, the fixed-budget
  observation count, and `linux-cpu` device evidence before a
  `CompletedTraining` witness can enter the checkpoint manifest. The update
  count is measured by the trainer against the exact flattened tensor whose
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
- **Performance** — a non-wall-clock RL performance metric (sample efficiency, i.e.
  env-steps-to-threshold), graded against a committed **ceiling** in
  `JitML.Product.ExternalBars`
  ([Phase 32](../../DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md)) that
  is never derived from the measured value and is exercised — and reproduced
  bit-identically on a same-seed re-run — by the same per-model
  [Phase 33](../../DEVELOPMENT_PLAN/phase-33-per-model-convergence-and-inference-tests.md)
  `jitml-model-convergence` case.

| RL / self-play model | Fixed budget unit | Stand-alone convergence metric |
|---|---|---|
| PPO, A2C, TRPO, MaskablePPO, RecurrentPPO | training: environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return per algorithm/environment cohort |
| DQN, QR-DQN | training: environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return on discrete-action cohorts |
| DDPG, TD3, SAC, CrossQ, TQC | training: environment transitions; evaluation: keyed episodes with an episode-step horizon | median evaluation return on continuous-control cohorts |
| ARS | training: candidate evaluations; evaluation: keyed episodes with an episode-step horizon | median evaluation return and accepted-direction improvement over the seed cohort |
| HER | training: goal-conditioned environment transitions; evaluation: keyed episodes with an episode-step horizon | goal success rate and median achieved-goal distance |
| AlphaZero Connect 4, Othello, Hex, Gomoku | self-play generations, MCTS simulations per move, and arena games | arena win-rate against the baseline/prior checkpoint plus legal-move rate |
| Hyperparameter tuning | fixed trial count or fixed scheduler-rung budget | best validation objective at the completed budget plus replayable sampler state |

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

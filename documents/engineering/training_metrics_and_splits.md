# Training Metrics and Data Splits

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](../../README.md), [documents/engineering/README.md](README.md), [training_workloads.md](training_workloads.md), [numerical_core.md](numerical_core.md), [checkpoint_format.md](checkpoint_format.md), [purescript_frontend.md](purescript_frontend.md), [DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md](../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md), [DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md](../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md), [DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md)
**Generated sections**: none

> **Purpose**: The single source of truth for jitML's supervised-learning
> train/test/validation split discipline, fixed-budget learning-completion
> witness, and convergence/performance metric definitions for SL, RL,
> AlphaZero, and tuning.

## Invariants

- **No hardcoded weights.** Every model — including checkpoints exposed by demo
  surfaces — uses weights produced by the model's declared training workflow with correct
  per-tensor shapes; synthetic, zero-padded, byte-identical, randomly
  initialized, or untrained payloads are prohibited (see
  [checkpoint_format.md](checkpoint_format.md)).
- **Real losses.** The published training loss is a real cross-entropy (classification) or
  MSE (regression) value computed from the model output — never `1 − accuracy`, and the
  validation loss is a real held-out measurement, not the final training loss.
- **Real metrics.** Convergence and performance metrics are measured from real training runs,
  not literature-target placeholders.
- **Fixed terminating budgets.** A model is not trained "until converged."
  Each canonical model has a pure, reproducible, finite training budget
  declared before execution. Training must perform exactly that budget unless a
  typed failure aborts the run; convergence is demonstrated by the metrics at
  the completed budget.
- **Inference requires completion.** Inference cannot accept a raw manifest,
  random initialization, or partially trained checkpoint. The only pure value
  that may flow into inference is an inference-eligible trained artifact witness
  minted from a completed budget plus its convergence statistics.

## Fixed-budget trained-artifact contract

The pure contract uses three distinct concepts. The fixed-budget and
completion-witness vocabulary lives in `JitML.Training.Budget`; checkpoint
eligibility is minted by `JitML.Checkpoint.Format` and enforced by
`JitML.Checkpoint.Store` before any weight-only inference load.

| Concept | Meaning | Invariant |
|---|---|---|
| `TrainingBudget` | A pure declaration of the exact terminating work: epochs / environment steps / self-play generations / tuning trials, seed cohort, and unit label. | Known before execution; no adaptive "keep training until convergence" loop. |
| `CompletedTraining` | The pure witness that the workflow executed the full budget and emitted all required metric observations plus TensorBoard scalar metadata. | Constructed only by `completedTraining`; failed, cancelled, partial, skipped, or smoke-only runs do not satisfy it. |
| `InferenceEligibleCheckpoint` | The value accepted by the shared checkpoint inference loader before `eval`, `inference run`, demo routes, RL rollout/eval, or AlphaZero game endpoints can consume weights. | Minted only from a manifest carrying `CompletedTraining`, passing convergence observations, and TensorBoard scalar tags. |

The type boundary is the product requirement: an untrained initialization,
seed-only demo network, hardcoded fixture checkpoint, or transport-smoke
checkpoint has no representation as `InferenceEligibleCheckpoint`.

The completed checkpoint records:

- full budget fields;
- completed iteration counters (`completed_epochs`, `completed_env_steps`,
  `completed_self_play_generations`, or `completed_trials`, as applicable);
- seed-cohort identity;
- substrate and device runner identity;
- convergence-statistics payload for the model;
- performance metric payload;
- TensorBoard run key and scalar tag prefix;
- readiness witness for the checkpoint store and inference loader.

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
| **train** | gradient updates only |
| **validation** | model **selection** / early-stop — the partition that picks the final model; never trained on |
| **test** | the held-out **final-evaluation** set, measured once on the selected model; never seen during training or selection |

The convergence assertion's final accuracy is reported on the **test** partition; model
selection runs against **validation**. (Datasets whose canonical archive ships no separate
validation partition, e.g. CIFAR-10/100, declare that explicitly rather than reusing test
as validation.)

## SL metrics (R3)

- **Convergence** — `JitML.SL.ConvergenceThresholds` holds the in-code,
  literature-derived thresholds; a cohort converges when the median test
  accuracy over the fixed seed cohort clears `slLiteratureTarget − slSlack`.
  Regression rows use the declared regression metric rather than accuracy.
  Cross-entropy / MSE training loss and held-out validation loss are reported
  per run.
- **Performance** — a **non-wall-clock** throughput metric (examples/sec). Wall-clock latency
  is excluded from the determinism contract (see [determinism_contract.md](determinism_contract.md)),
  so the performance metric is a distinct, deterministic, non-timing measure.

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

- **Convergence** — `JitML.RL.ConvergenceThresholds` holds the per-cohort return thresholds;
  a cohort converges when the **real measured-median** episode return over `k` seeds clears
  its threshold (replacing any literature-target placeholder probe).
- **AlphaZero** — convergence is measured by **arena win-rate** against the prior best
  network (a deliberate non-return metric), not an episode-return threshold.
- **Performance** — a non-wall-clock RL performance metric (sample efficiency, i.e.
  env-steps-to-threshold).

| RL / self-play model | Fixed budget unit | Stand-alone convergence metric |
|---|---|---|
| PPO, A2C, TRPO, MaskablePPO, RecurrentPPO | environment steps plus fixed evaluation episodes | median evaluation return per algorithm/environment cohort |
| DQN, QR-DQN | environment steps plus fixed evaluation episodes | median evaluation return on discrete-action cohorts |
| DDPG, TD3, SAC, CrossQ, TQC | environment steps plus fixed evaluation episodes | median evaluation return on continuous-control cohorts |
| ARS | candidate evaluations plus fixed evaluation episodes | median evaluation return and accepted-direction improvement over the seed cohort |
| HER | goal-conditioned environment steps plus fixed evaluation episodes | goal success rate and median achieved-goal distance |
| AlphaZero Connect 4, Othello, Hex, Gomoku | self-play generations, MCTS simulations per move, and arena games | arena win-rate against the baseline/prior checkpoint plus legal-move rate |
| Hyperparameter tuning | fixed trial count or fixed scheduler-rung budget | best validation objective at the completed budget plus replayable sampler state |

## Status

The phase status, sprint schedule, and validation evidence for these
requirements live in the DEVELOPMENT_PLAN; see
[DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md). This document
describes the contract, not the schedule. As of the 2026-06-26 model-runtime
audit, the fixed-budget trained-artifact witness and all-model convergence
matrix are reopened work, not closed evidence. The pure
`TrainingBudget`/`CompletedTraining` representation and shared checkpoint
loader eligibility gate are implemented, and the SL/RL/tuning completion
payloads now carry the witness on their command paths. Live all-model
convergence, infer-before-complete coverage for every surface, and browser
proof remain open in the DEVELOPMENT_PLAN.

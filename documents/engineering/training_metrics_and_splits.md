# Training Metrics and Data Splits

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](../../README.md), [documents/engineering/README.md](README.md), [training_workloads.md](training_workloads.md), [numerical_core.md](numerical_core.md), [checkpoint_format.md](checkpoint_format.md), [purescript_frontend.md](purescript_frontend.md), [DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md](../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md), [DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md](../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md), [DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md)
**Generated sections**: none

> **Purpose**: The single source of truth for jitML's supervised-learning train/test/validation split discipline and the convergence-**and-performance** metric definitions for SL and RL (no hardcoded weights, no faked metrics).

## Invariants

- **No hardcoded weights.** Every model — including the demo's seeded checkpoints — uses
  real trained weights with correct per-tensor shapes; synthetic/zero-padded/byte-identical
  weight payloads are prohibited (see [checkpoint_format.md](checkpoint_format.md)).
- **Real losses.** The published training loss is a real cross-entropy (classification) or
  MSE (regression) value computed from the model output — never `1 − accuracy`, and the
  validation loss is a real held-out measurement, not the final training loss.
- **Real metrics.** Convergence and performance metrics are measured from real training runs,
  not literature-target placeholders.

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

- **Convergence** — `JitML.SL.ConvergenceThresholds` holds the in-code, literature-derived
  thresholds; a cohort converges when the median test accuracy over `k` seeds clears
  `slLiteratureTarget − slSlack`. Cross-entropy / MSE training loss and held-out validation
  loss are reported per run.
- **Performance** — a **non-wall-clock** throughput metric (examples/sec). Wall-clock latency
  is excluded from the determinism contract (see [determinism_contract.md](determinism_contract.md)),
  so the performance metric is a distinct, deterministic, non-timing measure.

## RL metrics (R3 / R5)

- **Convergence** — `JitML.RL.ConvergenceThresholds` holds the per-cohort return thresholds;
  a cohort converges when the **real measured-median** episode return over `k` seeds clears
  its threshold (replacing any literature-target placeholder probe).
- **AlphaZero** — convergence is measured by **arena win-rate** against the prior best
  network (a deliberate non-return metric), not an episode-return threshold.
- **Performance** — a non-wall-clock RL performance metric (sample efficiency, i.e.
  env-steps-to-threshold).

## Status

The phase status, sprint schedule, and validation evidence for these requirements live in the
DEVELOPMENT_PLAN (Sprints 8.13 / 9.13 / 10.9 / 13.2 / 14.3 / 18.3); see
[DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md). This document describes the
contract, not the schedule.

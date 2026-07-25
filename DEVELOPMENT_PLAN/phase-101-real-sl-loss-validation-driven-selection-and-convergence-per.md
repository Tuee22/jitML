# Phase 101: Real SL Loss, Validation-Driven Selection, and Convergence+Performance Metrics

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real SL Loss, Validation-Driven Selection, and Convergence+Performance Metrics. Single-session phase migrated from legacy Sprint 8.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 101.1: Real SL Loss, Validation-Driven Selection, and Convergence+Performance Metrics [✅ Done]

**Status**: ✅ Done (reopened + re-closed 2026-06-24) — the foundation sprint every
consumer (Phases 9/10/13/14) needs, so every dependent `Blocked by` edge points down to
this sprint (rule M(a)). **Validated on both lanes: `jitml test jitml-sl-canonicals
--apple-silicon` 24/24 (real host Metal device) and `--linux-cpu` 24/24 (real oneDNN);
`jitml docs check: ok`; `jitml check-code` green in the `jitml:local` image build.**

**Implementation**: `src/JitML/SL/Architecture.hs`
(`SlRunMetrics`, `crossEntropyArchitectureWithDevice`,
`trainArchitectureWithDeviceSelected`), `src/JitML/App.hs` (`TrainingMetrics`,
`splitTrainValidation`, the three rewritten SL training runners + both training-event
publishers), `documents/engineering/training_metrics_and_splits.md`,
`test/sl-canonicals/Main.hs` (the real-metric device test).

**Dependencies**: none (foundation).

Supervised learning now reports real metrics and uses the held-out partitions
correctly, establishing the shared convergence-and-performance metric vocabulary:

- `trainArchitectureWithDeviceSelected` carves a held-out validation slice
  (`splitTrainValidation`, never folded into the gradient-update set), trains epoch
  by epoch, measures the held-out validation cross-entropy after each epoch, and
  returns the **lowest-validation-loss snapshot** — model **selection / early-stop on
  the validation partition**. The `test` partition stays the held-out final metric
  (`evaluateTestSplitDevice` / archive `TestSplit`), reported once on the selected
  model. Datasets whose canonical archive ships no separate validation partition
  (CIFAR-10/100) get an honest held-out slice carved from train, never test-as-validation.
- The faked SL "loss" (`1 − reportedAcc`; `ecValidationLoss = finalLoss`) is gone:
  `publishWorkerTrainingEvent` / `publishTrainingEpoch` now publish
  `ecLoss = tmTrainLoss` (real mean softmax cross-entropy via
  `crossEntropyArchitectureWithDevice`) and `ecValidationLoss = tmValidationLoss`
  (real held-out CE). Regression publishes the real train + held-out validation MSE
  (`meanSquaredErrorWithDevice`).
- A **non-wall-clock SL throughput performance metric** (`slmExamplesProcessed`
  = train examples × epochs) is computed and surfaced on the `jitml train` stdout line
  (`train_loss=… val_loss=… examples_processed=… test_acc=…`); it is deterministic, so
  it stays inside the determinism contract that excludes wall-clock timing.
- `documents/engineering/training_metrics_and_splits.md` is authored and registered
  (the SSoT for the train/test/validation methodology + SL/RL
  convergence-and-performance definitions).

### Exit Definition

- SL training selects on the validation partition; `test` is reported only as the
  held-out final metric; the published loss is a real CE/MSE value, not `1 − accuracy`. ✅
- An SL throughput performance metric is computed and surfaced. ✅
- `training_metrics_and_splits.md` exists, registered, with the convergence+performance
  definitions; Exit Definition item 6 carries the new performance clause. ✅

### Validation

- `jitml test jitml-sl-canonicals --apple-silicon`: **24/24 PASS** — the new
  "real SL metrics: validation-driven selection, real CE loss, throughput (Sprint 8.13)"
  case runs on the real host Metal device, asserting the published loss is a real
  cross-entropy below the `log(numClasses)` random baseline, a finite held-out
  validation loss, the deterministic throughput count, and that a fresh device
  cross-entropy reproduces the published train loss.
- `jitml test jitml-sl-canonicals --linux-cpu`: **24/24 PASS** — the same real-metric
  case runs on the real oneDNN device in the `jitml:local` container.
- `jitml docs check: ok`; `jitml check-code` green during the `jitml:local` image build.

### Remaining Work

- None. ✅

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

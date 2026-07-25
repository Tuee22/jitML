# Phase 226: Non-Fabricable Training Evidence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Non-Fabricable Training Evidence. Single-session phase migrated from legacy Sprint 21.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 226.1: Non-Fabricable Training Evidence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Evidence.hs`, `src/JitML/Training/Budget.hs`, `src/JitML/Checkpoint/Format.hs`, `src/JitML/SL/ConvergenceThresholds.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/training_metrics_and_splits.md`

### Objective

A `CompletedTraining` witness and a `CheckpointManifest` prove that learned
state moved. Evidence is constructible only through smart constructors that
require real weight movement, and convergence is evaluated against the same
per-row numeric bar table the RL rows already use.

### Deliverables

- `src/JitML/Product/Evidence.hs` owns the only constructors for training
  evidence. `CompletedTraining` (in `src/JitML/Training/Budget.hs`) and
  `CheckpointManifest` (in `src/JitML/Checkpoint/Format.hs`) gain
  `initialWeightHash`, `finalWeightHash`, `updateCount`, and `datasetShaAtRead`
  fields, populated only via smart constructors that reject empty hashes,
  `initialWeightHash == finalWeightHash`, `updateCount <= 0`, and missing
  dataset-read provenance; `attachCompletedTraining` mirrors the witness fields
  into the manifest and inference eligibility rejects missing or mismatched
  manifest evidence.
- The `coPassed = True` fabrication in `completedTrainingFromMetrics`
  (`src/JitML/Training/Budget.hs`) is deleted; the pass flag is replaced by
  `evaluateConvergence :: ConvergenceBar -> MeasuredMetrics -> Either Text ConvergenceObservation`,
  which compares measured metrics against a numeric bar and sets `coPassed` from
  the threshold result.
- `src/JitML/SL/ConvergenceThresholds.hs` carries a per-row numeric bar table
  mirroring the RL threshold table (`src/JitML/RL/ConvergenceThresholds.hs`), so
  every supervised row resolves to an explicit numeric `ConvergenceBar`.
- A unit test fails when evidence is constructed with equal init/final hashes,
  with a zero update count, or with a hardcoded pass flag; and fails when any
  product row lacks a numeric convergence bar.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu # passed, 253/253 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

The 2026-07-05 realness audit found this validation graded the surface against
self-authored gates: the per-row bar was slack-0 and the initial-weight hash was
taken over an all-zeros placeholder, so the unit test never exercised an untrained
checkpoint.

### Closure Evidence

closed obligation (Exit Definition — non-fabricable training evidence): the
weight-movement witness and the convergence outcome are self-referential, so an
untrained random-init model constructs valid evidence.

- **Hash the real random-init weights.** `initialWeightHash` must be taken over the
  actual randomly-initialized weight tensor, not the all-zeros placeholder in
  `src/JitML/App.hs` `checkpointTrainingEvidenceWithDatasetSha` (~line 3578); until
  then `initialWeightHash /= finalWeightHash` is satisfied by any nonzero final
  weights.
- **`updateCount` equals the real optimizer-step count.** The witness must carry the
  number of optimizer steps actually applied, not a positive constant.
- **Non-tautological convergence bar.** Replace the slack-0 per-row bar in
  `src/JitML/SL/ConvergenceThresholds.hs` (which makes `evaluateConvergence` compare
  a value against itself) with the frozen external constants from
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map)
  Sprint `32.2` (`src/JitML/Product/ExternalBars.hs`).

Closed by the [Phase 32](README.md#legacy-to-new-phase-map)
negative-control suite (`jitml-negative-controls`, Sprint `32.1`) that an untrained
random-init checkpoint is **rejected**, plus the no-self-referential-gate lint
(Sprint `32.2`).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 115: Real Hyperparameter Tuning Objective Executor

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real Hyperparameter Tuning Objective Executor. Single-session phase migrated from legacy Sprint 9.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 115.1: Real Hyperparameter Tuning Objective Executor [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Tune/Catalog.hs` (`deterministicTrials`,
`deterministicTrialsWithDevice` → `Tune.Trial` executor),
`src/JitML/Tune/Resume.hs` (`resumeMatchesFullRun`), `src/JitML/App.hs`
(`publishWorkerTuneEvent`, `measureTuneBestObjective`)
**Docs to update**: `../documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Replace the per-sampler LCG `deterministicTrials` with a real trial executor
that, for each sampled hyperparameter configuration, trains the substrate-backed
model and measures the real objective, and replace the `resumeMatchesFullRun`
tautology with a genuine resume-equality check. Owns the tuning slice of
[Exit Definition](README.md#exit-definition) item 6.

### Deliverables

- A `Tune.Trial` executor maps each sampled config (sampler × scheduler × pruner)
  to a real measured objective by training the substrate-backed model
  (`trainClassifierWithDevice` / the RL device trainers) over a bounded budget;
  no LCG-derived trial value remains.
- `resumeMatchesFullRun` compares a resumed sweep's trial objectives against the
  full-run objectives bit-for-bit (within-substrate determinism), not a
  structural tautology.
- The `jitml tune` summary and tuning transcript/report-card surfaces read the
  real measured objective; the old `inspect trial` / `inspect frontier`
  placeholders were retired by Phase `1` Sprint `1.16`.

### Validation

- `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu`
  (real measured objective; live half in Sprint 15.17 / 15.10).
- `jitml check-code` + `jitml docs check` green inside `jitml:local`.

### Current Validation State

Landed and validated (2026-06-10):

- `Tune.deterministicTrials` now returns __real measured objectives__:
  each trial samples a hyperparameter configuration, trains the reference
  classifier on a fixed separable dataset, and returns train accuracy in
  `[0, 1]`, matching the worked example's `valAcc:Maximise` direction. No
  LCG-derived trial value remains.
- `Tune.deterministicTrialsWithDevice` executes the same deterministic sampler
  stream through `Classifier.trainClassifierWithDevice`; the live worker path
  (`publishWorkerTuneEvent`) uses that substrate-selected JIT device and aborts
  on device failure, while `measureTuneBestObjective` reports unavailable rather
  than falling back when no live publication/device is usable.
- Sprint `9.12` extends the measured trial result with checkpointable trained
  weights. `jitml tune` writes the best local trial as a `.jmw1` checkpoint and
  a line-oriented `tune-trials` artifact; daemon-dispatched tune workers also
  promote each measured trial into the `jitml-checkpoints` bucket while keeping
  the `jitml-trials` transcript.
- Host: `jitml-hyperparameter` 14/14 (distinct per-sampler real objectives,
  values normalised, resume determinism), `jitml-unit` 196/196. Container:
  `check-code: ok`, `jitml test jitml-hyperparameter --linux-cpu` **14/14** and
  `jitml test jitml-hyperparameter --linux-cuda` **14/14** on 2026-06-11. Live
  tune trial persist/replay and daemon `StartSweep` dispatch passed in both
  linux-cpu and linux-cuda full integration suites (**67/67** each).
- Continuation validation (2026-06-11): `docker compose run --rm jitml jitml
  test jitml-hyperparameter --linux-cpu` → **15/15 PASS**, including
  `device-backed trial executor is deterministic through the substrate JIT
  device (Sprint 9.11 --linux-cpu): OK (0.12s)`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

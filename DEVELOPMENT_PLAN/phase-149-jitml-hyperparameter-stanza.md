# Phase 149: `jitml-hyperparameter` Stanza

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-hyperparameter Stanza. Single-session phase migrated from legacy Sprint 12.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 149.1: `jitml-hyperparameter` Stanza [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
per-sampler run-to-run bit-identity assertion plus the per-scheduler /
per-pruner cohort resume-equality assertions closed on 2026-05-24 —
`test/hyperparameter/Main.hs` invokes each sampler twice in-process
over the same seed, asserts bit-identity between the two trial-value
streams, and walks every scheduler/pruner catalog entry plus the
per-sampler `resumeMatchesFullRun` (no `test/golden/tune/` fixtures
per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)). Live `jitml tune`
against the full canonical sampler × scheduler × pruner grid through
the live tuner and resume-from-partial-sweep equality test against
live MinIO migrated to Phase `15` Sprint `15.10`.
**Implementation**: `test/hyperparameter/`,
`jitml.cabal` (the `jitml-hyperparameter` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-hyperparameter` for the sampler, scheduler, pruner,
and deterministic trial-value checks.

### Deliverables

- `test/hyperparameter/Main.hs` verifies the current axes are populated:
  eleven samplers, four schedulers, and three pruners.
- It asserts `deterministicTrials sampler 8` is bit-identical across
  two in-process invocations for every current sampler (run-to-run
  equality).
- It asserts generated trial values are normalized into `[0, 1)`.
- It does **not** compare against any `test/golden/tune/...` file per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets); sampler reproducibility
  is asserted as run-to-run equality plus sampler-state-purity
  property tests.
- It decodes `experiments/mnist-tune.dhall` and asserts the local tuning ADT
  carries the TPE / ASHA / MedianPruner worked-example axes.
- It consumes `tune_trials` and `tune_budget_per_trial` from the
  `cabal.project` report-card knob block for the local TPE trial-budget
  assertion.
- It covers `TuneCommand` text render/parse round-trips plus `TuneCommand` /
  `TuneEvent` proto3-compatible byte round-trips.
- Scheduler/pruner event semantics and resume equality are owned by
  `### Remaining Work` below. Report-card knob parsing is also covered through
  `src/JitML/Test/Report.hs` and `jitml-e2e`.

### Validation

1. `cabal test jitml-hyperparameter` exits `0` for the body.
2. Transferred live validation: the stanza runs real tuning sweeps with the
   `tune_trials` / `tune_budget_per_trial` knobs, asserts per-sampler /
   per-scheduler / per-pruner reproducibility, and asserts
   resume-from-partial-sweep equality against trial transcripts persisted
   to MinIO bucket `jitml-trials/`.

### Remaining Work

- The `every sampler is run-to-run bit-identical (Sprint 12.5)` case in
  `test/hyperparameter/Main.hs` walks the full sampler catalog (Grid,
  Sobol, Random, TPE, GPBO, GeneticAlgorithm, NSGA2, MuLambdaES, CMAES,
  EvolutionStrategies, and PBT), invokes each sampler twice in-process
  over the same seed, and asserts bit-identity between the two
  trial-value streams; the `every scheduler / pruner cohort reproduces
  under resume (Sprint 12.5)` case asserts every scheduler and pruner
  catalog entry plus the per-sampler resume equality from
  `resumeMatchesFullRun` (closed 2026-05-24). No `test/golden/tune/`
  fixtures are committed per [../README.md → Snapshot targets →
  Numerical-fixture prohibition](../README.md#snapshot-targets).
- Driving `jitml tune` against the full canonical sampler × scheduler ×
  pruner grid through the live tuner, extending knob consumption to the
  full grid, and the resume-from-partial-sweep equality test against
  live MinIO are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.10`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

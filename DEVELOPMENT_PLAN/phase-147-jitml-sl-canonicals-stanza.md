# Phase 147: `jitml-sl-canonicals` Stanza

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-sl-canonicals Stanza. Single-session phase migrated from legacy Sprint 12.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 147.1: `jitml-sl-canonicals` Stanza [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The
`sl_epochs` / `sl_batch` report-card knob consumption closed on
2026-05-24 — `test/sl-canonicals/Main.hs` reads the `cabal.project`
report-card knob block via `JitML.Test.Report.loadReportCardKnobs`
and asserts the SL epoch/batch knobs are positive for the device-backed
training surface.
Live `jitml train` against canonical SL cells with real MinIO
datasets and live statistical convergence assertions against in-code
literature-target thresholds (no per-substrate fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) migrated to Phase `15`
Sprint `15.4`.
**Implementation**: `test/sl-canonicals/`,
`jitml.cabal` (the `jitml-sl-canonicals` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/training_workloads.md`

### Objective

Use `jitml-sl-canonicals` for the current eleven-cell local supervised-learning
canonical workload exercised as property tests (finite-and-monotone
loss, run-to-run determinism, median over k seeds clears an in-code
literature-derived threshold). Live training thresholds remain target
runtime work; no per-substrate committed convergence fixtures will be
created per [../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets).

### Deliverables

- `test/sl-canonicals/Main.hs` verifies the eleven canonical
  cells from `src/JitML/SL/Canonicals.hs`.
- It asserts convergence curves are deterministic across two in-process
  invocations (run-to-run equality) and contain `sl_epochs` points.
- It asserts each final synthetic loss is lower than the initial loss
  by a per-problem-class margin (a property test, not a stored value).
- It does not compare against any `test/golden/sl/...` file per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- It covers `TrainingCommand` text render/parse round-trips plus
  `TrainingCommand` / `TrainingEvent` proto3-compatible byte round-trips.
- It does not run live training or consume `sl_epochs` / `sl_batch` yet.

### Validation

1. `cabal test jitml-sl-canonicals` exits `0` for the body.
2. Transferred live validation: the stanza runs real training against every
   canonical SL problem with the `sl_epochs` / `sl_batch` knobs from
   `cabal.project`, asserts the median test accuracy over a fixed-seed
   pool clears the in-code literature-derived threshold per problem, and
   asserts run-to-run determinism (two fresh same-substrate / same-seed
   runs produce bit-identical `sha256(weights.bin)`). No `test/golden/sl/`
   fixtures are created per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets).

### Remaining Work

- The `sl-canonicals consumes cabal.project sl_epochs and sl_batch
  knobs` case in `test/sl-canonicals/Main.hs` reads the
  `cabal.project` report-card knob block via
  `JitML.Test.Report.loadReportCardKnobs` and asserts the deterministic
  curve length is bounded by `sl_epochs` (closed 2026-05-24).
- Driving `jitml train` against every canonical SL cell with real
  datasets and asserting median accuracy clears the in-code
  literature-derived threshold (rather than against a per-substrate
  committed fixture) are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.4`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

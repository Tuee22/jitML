# Phase 107: Specialised Algorithm Metadata

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Specialised Algorithm Metadata. Single-session phase migrated from legacy Sprint 9.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 107.1: Specialised Algorithm Metadata [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only.
`jitml docs generate` for the catalog table (closed 2026-05-24 in
`JitML.Docs.Render.renderTrainingRlCatalog`) and per-algorithm
deterministic-stub run-to-run determinism for CrossQ, TQC, ARS, HER
(closed 2026-05-24 via re-running each rollout in-process and
comparing bit-for-bit) are both in place; no `test/golden/rl/`
files are committed per [../README.md → Snapshot targets →
Numerical-fixture prohibition](../README.md#snapshot-targets). Real
specialised algorithm execution through live CUDA migrated to
Phase `15` Sprint `15.8`.
**Implementation**: `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Algorithms/{CrossQ,Tqc,Ars,Her}.hs`,
`test/rl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Land the current specialised algorithm metadata rows.

### Deliverables

- `algorithmCatalog` includes specialised rows for `CrossQ`, `TQC`, `ARS`,
  and `HER`.
- `CrossQ`, `TQC`, and `HER` are marked replay-based; `ARS` is not.
- The four specialised algorithm modules expose typed deterministic
  hyperparameter rows and per-seed transcripts.
- The generated training-workload catalog table is actively rendered from the
  current Haskell catalog by `jitml docs generate`.

### Validation

1. `algorithmCatalog` exposes the four checked-in specialised rows.
2. `jitml docs check` validates the generated catalog table.
3. Transferred live validation: each specialised algorithm has a dedicated
   module exercised by `jitml-rl-canonicals` against run-to-run
   determinism plus rule-conformance properties (no committed numerical
   fixtures per [../README.md → Snapshot targets → Numerical-fixture
   prohibition](../README.md#snapshot-targets)).

### Remaining Work

- `jitml docs generate` now renders the catalog table with the
  per-module hyperparameter count and module file path from
  `JitML.RL.Algorithms.Registry` (closed 2026-05-24 in
  `JitML.Docs.Render.renderTrainingRlCatalog`). The regenerated
  `documents/engineering/training_workloads.md` catalog table now lists
  `Algorithm | Family | Replay-backed | Hyperparameters | Module`.
- Per-algorithm deterministic-stub run-to-run determinism for CrossQ,
  TQC, ARS, HER closed on 2026-05-24 — asserted by re-running the
  rollout in-process and comparing bit-for-bit; no `test/golden/rl/...`
  files are committed per [../README.md → Snapshot targets →
  Numerical-fixture prohibition](../README.md#snapshot-targets).
- Real CUDA specialised-update execution (CrossQ multi-critic, TQC
  quantile TD, ARS evolution strategy, HER hindsight relabel) is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.8`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

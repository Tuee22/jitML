# Phase 150: `jitml-cross-backend` Stanza

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-cross-backend Stanza. Single-session phase migrated from legacy Sprint 12.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 150.1: `jitml-cross-backend` Stanza [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Cross-substrate
cohort runs and per-tensor drift assertion against the **in-code**
per-layer-family tolerance band at `src/JitML/Engines/Tolerance.hs`
(no per-tensor stored fixtures per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)) migrated to Phase `17`
Sprint `17.1`.
**Implementation**: `test/cross-backend/`,
`jitml.cabal` (the `jitml-cross-backend` stanza),
`src/JitML/Test/Report.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`

### Objective

Use `jitml-cross-backend` for the engine-flag, checkpoint
manifest/weight-selection invariant, Linux CPU generated-kernel execution
checks, and local Linux CPU `HasEngine` smoke dispatch. Live
cross-substrate tolerance testing remains the overall handoff gate.

### Deliverables

- `test/cross-backend/Main.hs` verifies every substrate has non-empty
  deterministic engine flags.
- It verifies checkpoint weight-only tensor selection is substrate-independent.
- It compiles generated Linux CPU oneDNN primitive kernels, loads `jitml_kernel` and
  `jitml_kernel_family_name` / `jitml_kernel_output_count` with `dlopen`,
  verifies the reported family and output length, and asserts three successive
  FFI invocations produce bit-identical fixture output.
- It dispatches a generated family kernel through the local Linux CPU
  `HasEngine` interpreter and verifies the loaded family metadata.
- It does not train SL canon cohorts yet (the canon-cohort run lives
  in Phase `17` Sprint `17.1`). The in-code per-layer-family tolerance
  band at `src/JitML/Engines/Tolerance.hs` will be the **only** drift
  reference; no `test/golden/cross-backend/` fixtures will be created
  per [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).

### Validation

1. `cabal test jitml-cross-backend` exits `0` for the body.
2. `cabal test jitml-cross-backend` validates the generated Linux CPU oneDNN
   primitive compile/load/run paths plus exported family/output-count symbol
   metadata.
3. `docker compose run --rm jitml cabal test jitml-cross-backend` on
   2026-05-24 validates the local Linux CPU `HasEngine` dispatch over the
   generated oneDNN family FFI path in `jitml:local`.
4. Transferred live validation: the stanza runs the canonical SL cohorts
   on the `(linux-cpu, linux-cuda)` and `(linux-cpu, apple-silicon)`
   substrate pairs and asserts per-tensor drift fits the in-code
   per-layer-family tolerance band at
   `src/JitML/Engines/Tolerance.hs` per
   [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).
   No `test/golden/cross-backend/` fixtures are created.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The
  cross-substrate cohort runs and the per-tensor drift assertion
  against the in-code per-layer-family tolerance band are owned by
  [phase-17-cross-substrate-and-handoff.md](README.md#legacy-to-new-phase-map)
  Sprint `17.1`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

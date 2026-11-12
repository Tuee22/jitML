# Phase 323: CUDA qualification

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Frozen-candidate acceptance for cuda qualification in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: NVIDIA Linux host + linux-cpu.
**Change boundary**: Frozen-candidate acceptance.
**Inherited obligations**: [268.2](phase-268-contract-driven-cuda-lane-revalidation.md), [278.1](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [279.1](phase-279-measured-declared-type-split-behavioral-scaffold-lint.md), [285.1](phase-285-contract-driven-per-model-evidence.md), [289.1](phase-289-evidence-typed-report-measurements.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 324 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md) — review the frozen native CUDA build recipe and executable seal contract.
- [validation_execution.md](../documents/engineering/validation_execution.md) — review complete NVIDIA lane acquisition and preservation policy.
- [training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md) — review prescribed rows, seed cohorts and unchanged criteria.

Review these contracts against the already frozen implementation. Record actual
results and limitations in this phase; a needed source/schema/recipe or contract
change reopens its earliest engineering owner and creates a new epoch.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 323.1: Canonical rows 01–04: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `322.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 01–04: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 01–04: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **1–4** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.2: Canonical rows 05–08: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 05–08: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 05–08: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **5–8** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.3: Canonical rows 09–12: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 09–12: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 09–12: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **9–12** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.4: Canonical rows 13–16: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 13–16: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 13–16: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **13–16** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.5: Canonical rows 17–20: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.4`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 17–20: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 17–20: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **17–20** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.6: Canonical rows 21–24: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.5`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 21–24: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 21–24: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **21–24** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.7: Canonical rows 25–28: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.6`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 25–28: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 25–28: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **25–28** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.8: Canonical rows 29–32: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.7`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 29–32: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 29–32: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **29–32** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.9: Canonical rows 33–36: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.8`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 33–36: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 33–36: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **33–36** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.10: Canonical rows 37–40: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.9`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 37–40: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 37–40: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **37–40** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.11: Canonical rows 41–44: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.10`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 41–44: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 41–44: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **41–44** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.12: Canonical rows 45–48: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.11`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 45–48: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 45–48: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **45–48** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.13: Canonical rows 49–52: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.12`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 49–52: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 49–52: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **49–52** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.14: Canonical rows 53–55: whole prescribed cohorts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.13`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit canonical rows 53–55: whole prescribed cohorts, preserving all earlier completed contracts.

### Deliverables

- Own the `canonical rows 53–55: whole prescribed cohorts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Enumerate canonical Product.Matrix rows **53–55** in frozen catalogue order; listing performs no training. Execute every row in that group with all prescribed seeds and the actual selected device.
2. Reopen exact initial/final bytes, learning measurements, counters, inference timing and same-seed replay observations, journaled `/metrics` and `/healthz`, Store/replay and before/after preservation through the already implemented readers.
3. Seal each complete row cohort; retain every failed attempt. No mid-seed continuation, row omission, threshold reduction, seed replacement or cross-epoch splice qualifies.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 323.15: Seal complete lane catalogue and preservation evidence

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/Publisher/Orchestrator.hs`, `src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-323-cuda-qualification.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `323.14`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: NVIDIA Linux host + linux-cpu.

### Objective

Execute and admit seal complete lane catalogue and preservation evidence, preserving all earlier completed contracts.

### Deliverables

- Own the `seal complete lane catalogue and preservation evidence` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Validate the exact real inputs produced by earlier phases through the pre-freeze production implementation, including refusal controls for absent, stale, foreign, reordered, duplicated and tampered evidence.
2. Retain complete scoped transcripts and preservation receipts. The lane-local closing gate runs required selected-device backend/browser/Store/readback and preservation controls on this phase's real hardware, plus its CPU support, before issuing the lane catalogue/fragment. It requires neither the other accelerator nor later aggregation. It consumes the sealed row cohorts without secretly retraining them.
3. A scientific refusal or missing measurement blocks this sprint. A code/schema correction starts a new epoch through explicit reopening; it is not hidden in an acceptance phase.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Frozen lane admission

Before the first prescribed seed, build exact frozen source through the
predeclared lane recipe and seal the actual executable/image/runtime identity
under the Phase 320 slot protocol. A Linux string/render fixture cannot issue
a device seal. Byte-identical rebuild verification is permitted; source edits,
replacement digests or toolchain-policy changes return to the engineering
owner and a new common epoch. This phase records actual inference timings,
same-seed replay, metrics/health observations and preservation as declared
before freeze; later readers add no fields that force lane reissuance.

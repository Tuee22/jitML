# Phase 328: Complete standing engineering

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Frozen-candidate acceptance for complete standing engineering in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Frozen-candidate acceptance.
**Inherited obligations**: [277.2](phase-277-negative-control-suite.md), [280.1](phase-280-runcontract-negative-controls-request-and-event-fixtures.md), [280.2](phase-280-runcontract-negative-controls-request-and-event-fixtures.md), [281.1](phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md), [281.2](phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md), [282.1](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md), [282.2](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 329 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [unit_testing_policy.md](../documents/engineering/unit_testing_policy.md) — review complete standing-suite ownership and all original assertions.
- [validation_execution.md](../documents/engineering/validation_execution.md) — review full admitted-input execution, cleanup and capture obligations.

Review these contracts against the already frozen implementation. Record actual
results and limitations in this phase; a needed source/schema/recipe or contract
change reopens its earliest engineering owner and creates a new epoch.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [unit_testing_policy.md](../documents/engineering/unit_testing_policy.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 328.1: Full unit/integration transcripts

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Test/NegativeControls.hs`, `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Stack.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-328-complete-standing-engineering.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `327.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Execute and admit full unit/integration transcripts, preserving all earlier completed contracts.

### Deliverables

- Own the `full unit/integration transcripts` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Validate the exact real inputs produced by earlier phases through the pre-freeze production implementation, including refusal controls for absent, stale, foreign, reordered, duplicated and tampered evidence.
2. Retain complete scoped transcripts and preservation receipts. CPU aggregation consumes hardware records and starts no accelerator or replacement training.
3. A scientific refusal or missing measurement blocks this sprint. A code/schema correction starts a new epoch through explicit reopening; it is not hidden in an acceptance phase.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 328.2: Full negative-control transcript

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Test/NegativeControls.hs`, `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Stack.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-328-complete-standing-engineering.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `328.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Execute and admit full negative-control transcript, preserving all earlier completed contracts.

### Deliverables

- Own the `full negative-control transcript` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Validate the exact real inputs produced by earlier phases through the pre-freeze production implementation, including refusal controls for absent, stale, foreign, reordered, duplicated and tampered evidence.
2. Retain complete scoped transcripts and preservation receipts. CPU aggregation consumes hardware records and starts no accelerator or replacement training.
3. A scientific refusal or missing measurement blocks this sprint. A code/schema correction starts a new epoch through explicit reopening; it is not hidden in an acceptance phase.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 328.3: Remaining owned data-dependent assertion coverage

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Test/NegativeControls.hs`, `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Stack.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-328-complete-standing-engineering.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `328.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Execute and admit remaining owned data-dependent assertion coverage, preserving all earlier completed contracts.

### Deliverables

- Own the `remaining owned data-dependent assertion coverage` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Validate the exact real inputs produced by earlier phases through the pre-freeze production implementation, including refusal controls for absent, stale, foreign, reordered, duplicated and tampered evidence.
2. Retain complete scoped transcripts and preservation receipts. CPU aggregation consumes hardware records and starts no accelerator or replacement training.
3. A scientific refusal or missing measurement blocks this sprint. A code/schema correction starts a new epoch through explicit reopening; it is not hidden in an acceptance phase.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Required inherited detail

Complete every original applicable CPU test stanza and assertion at its real-data boundary, with an exact nonempty inventory and full transcripts. No original negative, lifecycle, unit, integration, model or browser case is omitted because it was previously fixture-dependent; selected-device stanzas were already exercised by their hardware owners.

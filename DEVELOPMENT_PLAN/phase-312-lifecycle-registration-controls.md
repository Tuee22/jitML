# Phase 312: Lifecycle registration controls

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for lifecycle registration controls in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [282.1](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md), [282.2](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 313 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [validation_execution.md](../documents/engineering/validation_execution.md) — document lifecycle, observer-loss and cancellation control boundaries.
- [execution_resources.md](../documents/engineering/execution_resources.md) — align child/helper cleanup and failed-observation accounting.
- [unit_testing_policy.md](../documents/engineering/unit_testing_policy.md) — publish unchanged lifecycle assertions and explicit gate registration.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [validation_execution.md](../documents/engineering/validation_execution.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 312.1: Campaign lifecycle failures

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/LaneRegistration.hs`, `src/JitML/Test/LifecycleFixtures.hs`, `src/JitML/Test/NegativeControls/Lifecycle.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-312-lifecycle-registration-controls.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `311.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify campaign lifecycle failures, preserving all earlier completed contracts.

### Deliverables

- Implement reply-cursor transport redesign, source-identical local no-op semantics and consolidate overlapping scripted fakes with explicit ownership.
- Boundary: Lifecycle transport and fakes.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Transport/cancel/cursor failures retain the exact receipt and never hide remote work; no-op is actually source-identical.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 312.2: Per-row assertion registration and selector inventory

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/LaneRegistration.hs`, `src/JitML/Test/LifecycleFixtures.hs`, `src/JitML/Test/NegativeControls/Lifecycle.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-312-lifecycle-registration-controls.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `312.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify per-row assertion registration and selector inventory, preserving all earlier completed contracts.

### Deliverables

- Publish the complete original assertion-to-row/sprint inventory and isolate selectable acquisition through the same production path.
- Boundary: Per-row selectable registration.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Listing trains nothing, selected-row controls do not acquire 55, and missing/duplicate/unsupported selectors fail. Real Apple forwarding proof remains 319.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Required inherited detail

Preserve the reply-cursor transport redesign, source-identical local no-op behavior and consolidation of overlapping scripted fakes from original 282.1. Real Apple forwarding/observer controls are owned by 319 before freezing.

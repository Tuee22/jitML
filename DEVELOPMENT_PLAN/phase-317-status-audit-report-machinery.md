# Phase 317: Status audit report machinery

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for status audit report machinery in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [287.2](phase-287-standing-adversarial-audit-thin-plan.md), [288.1](phase-288-journal-derived-status-registry.md), [288.2](phase-288-journal-derived-status-registry.md), [289.1](phase-289-evidence-typed-report-measurements.md), [289.2](phase-289-evidence-typed-report-measurements.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 318 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [product_completion_contract.md](../documents/engineering/product_completion_contract.md) — document derived status, final audit and report machinery.
- [unit_testing_policy.md](../documents/engineering/unit_testing_policy.md) — publish the hermetic/real-input consumer inventory.
- [cli_command_surface.md](../documents/engineering/cli_command_surface.md) — reconcile implemented status/report surfaces and generated references.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [product_completion_contract.md](../documents/engineering/product_completion_contract.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 317.1: Standing coherence and regression audit implementation

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Product/StatusLoader.hs`, `src/JitML/Test/Measurement.hs`, `src/JitML/Test/Report.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-317-status-audit-report-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `316.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify standing coherence and regression audit implementation, preserving all earlier completed contracts.

### Deliverables

- Implement doctrine/plan/ledger/contract contradiction checks and monotonic regression impact reporting.
- Boundary: Standing coherence audit.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** A later source edit preserving stale earlier passes or an undeclared cleanup dependency fails.

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

## Sprint 317.2: Current evidence-derived status and gate projection

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Product/StatusLoader.hs`, `src/JitML/Test/Measurement.hs`, `src/JitML/Test/Report.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-317-status-audit-report-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `317.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify current evidence-derived status and gate projection, preserving all earlier completed contracts.

### Deliverables

- Implement exact current catalogue, phase-scoped transcripts and complete real-input obligation projection without status literals.
- Boundary: Current evidence-derived status.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Historical Done cannot close current work; a passed early gate coexists with future Pending gates and final source-sensitive evidence refusal.

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

## Sprint 317.3: Typed report protocol with journaled metrics, health and timings

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Product/StatusLoader.hs`, `src/JitML/Test/Measurement.hs`, `src/JitML/Test/Report.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-317-status-audit-report-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `317.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify typed report protocol with journaled metrics, health and timings, preserving all earlier completed contracts.

### Deliverables

- Implement report fields and invocation-journal acquisition of actual metrics/health/timing observations plus operator handoff schema.
- Boundary: Typed final report observation producer.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Missing invocation observations remain unavailable; later probes, hand counts and declaration-only values cannot populate them.

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

All status, audit and report code lands before freezing, including actual invocation-journal acquisition of `/metrics` and `/healthz`, not post-test probes. Historical 288/289 obligations remain inherited.

## Cleanup ledger acceptance

317.3 retires post-test global/edge measurement probes as qualifying authority. Actual invocation-journal observations are produced before and during the owning run; later report rendering cannot reconstruct missing metrics.

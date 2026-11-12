# Phase 309: Fragment issuer machinery

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for fragment issuer machinery in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [263.2](phase-263-contract-driven-live-execution-fragment-issuance.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 310 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [run_contract.md](../documents/engineering/run_contract.md) — document fragment issuer authority and common epoch binding.
- [product_completion_contract.md](../documents/engineering/product_completion_contract.md) — define exact lane-fragment admission and refusal conditions.

**Product docs to create/update:**

- [Root README](../README.md) — summarize only the supported fragment issuance and admission workflow.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [run_contract.md](../documents/engineering/run_contract.md); retain historical source/evidence links with their original scope.
- Reconcile affected architecture and runtime ownership in [system-components.md](system-components.md).

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 309.1: Common authenticated fragment issuer

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Test/ProductLaneJournal.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`, `src/JitML/Product/LaneRegistration.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-309-fragment-issuer-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `308.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify common authenticated fragment issuer, preserving all earlier completed contracts.

### Deliverables

- Implement one maintained authenticated issuer binding complete row coverage, source/epoch/lane seal, preservation and exact portable objects.
- Boundary: Common fragment issuer.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Only production-admitted complete fixture inputs issue; a generic JSON writer or digest name cannot mint a fragment.

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

## Sprint 309.2: Scope/epoch/omission/tamper negatives

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Test/ProductLaneJournal.hs`, `src/JitML/Test/NativeLaneBundle/Write.hs`, `src/JitML/Product/LaneRegistration.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-309-fragment-issuer-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `309.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify scope/epoch/omission/tamper negatives, preserving all earlier completed contracts.

### Deliverables

- Exercise source/epoch/issuer/row-order/omission/duplicate/byte-tamper and retention failures through production admission.
- Boundary: Fragment refusal controls.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** All negatives refuse; independently issued valid protocol fixtures pass without requiring actual future qualification.

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

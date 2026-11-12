# Phase 290: Ordered plan and validation foundation

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for ordered plan and validation foundation in the current numerical sequence.

## Phase State

**Planned; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [221.2](phase-221-phase-status-registry.md), [288.1](phase-288-journal-derived-status-registry.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 291 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [unit_testing_policy.md](../documents/engineering/unit_testing_policy.md) — publish the scoped gate inventory and retained/full-suite ownership boundary.
- [code_quality.md](../documents/engineering/code_quality.md) — document phase-scoped documentation, lint and build checks.
- [run_contract.md](../documents/engineering/run_contract.md) — align current catalogue and evidence-obligation schemas.
- [documentation_standards.md](../documents/documentation_standards.md) — align executable current-plan, ownership and historical-evidence rules.

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


## Sprint 290.1: Catalogue and ownership schema

**Status**: Planned
**Implementation**: Planned targets: `src/JitML/Product/PlanDoc.hs`, `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Docs/Check.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-290-ordered-plan-and-validation-foundation.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify catalogue and ownership schema, preserving all earlier completed contracts.

### Deliverables

- Implement the minimal self-contained bootstrap verifier, archive/current parser boundary and schema/fixture inventory in this sprint. Validate it before 290.2 or 290.3 exists.
- Parse the current index separately from preserved 1–289 history; assign exact current IDs and immutable historical identities. Implement its own bootstrap fixture/schema runner in this sprint.
- Boundary: Current/archive catalogue and bootstrap verifier.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Accept a minimal current plan while all later code/journals are absent; reject unknown or duplicated current owners and accidental historical reactivation.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

Sprint 290.1 implements and validates its own minimal bootstrap gate using
existing selectable schema/fixture tests and structural documentation checks.
It requires neither 290.2 nor 290.3. Later sprints extend that passing boundary
with numeric/hardware and full assertion/transcript inventory checks; their new
obligations do not retroactively gate earlier bootstrap closure. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 290.2: Numeric forward-edge and hardware checks

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/PlanDoc.hs`, `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Docs/Check.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-290-ordered-plan-and-validation-foundation.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `290.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify numeric forward-edge and hardware checks, preserving all earlier completed contracts.

### Deliverables

- Validate phase/sprint keys, immediate predecessors, declared OS/device sets and deterministic numerical execution.
- Boundary: Numerical dependency and hardware verifier.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Accept earlier same-phase/lower-phase edges; reject higher/self/cyclic edges and a phase requiring two specific host/device sets.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

Sprint 290.1 implements and validates its own minimal bootstrap gate using
existing selectable schema/fixture tests and structural documentation checks.
It requires neither 290.2 nor 290.3. Later sprints extend that passing boundary
with numeric/hardware and full assertion/transcript inventory checks; their new
obligations do not retroactively gate earlier bootstrap closure. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Sprint 290.3: Scoped transcript obligations and baseline fixture classification

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/PlanDoc.hs`, `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Docs/Check.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-290-ordered-plan-and-validation-foundation.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `290.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify scoped transcript obligations and baseline fixture classification, preserving all earlier completed contracts.

### Deliverables

- Assign every original assertion an exact current sprint, fixture/runtime prerequisites, transcript/source identity and result class; implement supported selectable early gates and complete late gates.
- Boundary: Assertion inventory and scoped gate projection.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** An early scope can pass with future scopes Blocked; omitted/duplicate assertions, selected-as-full transcripts, fake hardware passes and future journal acquisition fail.

1. Run the owned selectable hermetic controls and bounded real runtime observations on the declared hardware, after publishing their exact inventory and selectors in the existing command machinery.
2. Verify a positive implementation path and independent negative controls for this work package; a fixture cannot satisfy a real-hardware or scientific assertion.
3. Pass phase-scoped documentation, generated-source, lint/build and gate-inventory checks. Planned future owners may remain unimplemented; none of their real lane records or complete aggregate suites is a prerequisite here.

Sprint 290.1 implements and validates its own minimal bootstrap gate using
existing selectable schema/fixture tests and structural documentation checks.
It requires neither 290.2 nor 290.3. Later sprints extend that passing boundary
with numeric/hardware and full assertion/transcript inventory checks; their new
obligations do not retroactively gate earlier bootstrap closure. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

## Required inherited detail

The catalogue must distinguish this current sequence from archived phases 1–289, retain every historical identity and receipt, reject all higher-numbered prerequisite edges, and classify every test assertion as hermetic, selected-lane or aggregate acceptance. Earlier phase-scoped gates must pass without later implementation, journals or science. Full historical/product gate obligations remain registered with their later real-input owners; a literal status never mints Done.

## Bootstrap validation boundary

290.1 uses the existing compiled test machinery plus an independent structural
plan/schema fixture verifier; it validates its own implementation without
future real journals or its successors. 290.2 adds strict lower-only and single
hardware checks. 290.3 owns the exhaustive assertion-to-sprint/transcript
partition and supported phase-gate projection. The phase closes only when all
three pass, but neither earlier sprint waits on later implementation. Existing
516 historical checkout-path violations are owned by 292.2: bootstrap validates
changed/new paths and reports the full check as failing, never allowlisting it
or requiring 292 to close 290. Final full-path acceptance remains 292.

## Cleanup ledger acceptance

Convert the current legacy-attested fallback into explicit historical-only evidence semantics before freezing. Preserve historical receipts, but no current phase may derive completion from that class or a literal status. Final projection 334 exercises this already-implemented distinction.

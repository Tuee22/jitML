# Phase 315: Evidence projection machinery

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for evidence projection machinery in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [283.2](phase-283-per-model-measured-convergence.md), [284.2](phase-284-inference-performance-determinism.md), [285.1](phase-285-contract-driven-per-model-evidence.md), [285.2](phase-285-contract-driven-per-model-evidence.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 316 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md) — document measured convergence/performance projection semantics.
- [product_completion_contract.md](../documents/engineering/product_completion_contract.md) — define accepted evidence inputs and output/report boundaries.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 315.1: Convergence projection

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/Convergence.hs`, `src/JitML/Product/Benchmark.hs`, `src/JitML/Test/ModelEvidence.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-315-evidence-projection-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `314.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify convergence projection, preserving all earlier completed contracts.

### Deliverables

- Implement current per-seed/cohort learning curves, final EvaluationSet and actual work/criterion observation fields plus CPU producers.
- Boundary: Convergence measurement protocol.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Empty, unchanged, below-policy, substituted cohort and wrong-data evidence cannot be complete; native producers close in 318/319.

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

## Sprint 315.2: Within-lane determinism/performance projection

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/Convergence.hs`, `src/JitML/Product/Benchmark.hs`, `src/JitML/Test/ModelEvidence.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-315-evidence-projection-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `315.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify within-lane determinism/performance projection, preserving all earlier completed contracts.

### Deliverables

- Implement actual inference timing and same-seed rerun acquisition/encoding before qualification, separating within-lane numeric and cross-lane wall-clock contracts.
- Boundary: Timing and rerun protocol.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Post-hoc probes or declared timing do not satisfy actual invocation observation; cross-device numerical equality is never asserted.

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

## Sprint 315.3: Complete per-model evidence coverage

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Product/Convergence.hs`, `src/JitML/Product/Benchmark.hs`, `src/JitML/Test/ModelEvidence.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-315-evidence-projection-machinery.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `315.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify complete per-model evidence coverage, preserving all earlier completed contracts.

### Deliverables

- Implement exact catalogue/model/outcome/retention coverage and all observation admission before freeze.
- Boundary: Complete per-model reader.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Missing metrics, artifacts, predicates or stale source fail on fixtures; later lanes populate this existing schema without adding fields.

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

Implement real measurement producers and all journal fields before freezing: inference timing, same-seed reruns, learning curves, final EvaluationSet and per-cohort fields. Later phases project those frozen-schema observations; they may not force lane reissuance by adding fields.

## Observation producer partition

Implement common schemas and actual CPU observation producers here. CUDA and
Metal implementations and real runtime probes close in 318/319. All fields exist
before 320; the later frozen lane executions populate them without source edits.

## Cleanup ledger acceptance

315.2 owns real CPU benchmark kernel probing and 315.3 owns replacement of forgeable RowAssertions evidence. These implementation/measurement boundaries close before source freeze; actual complete evidence acceptance 329–331 uses them unchanged.

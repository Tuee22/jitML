# Phase 298: Portable workload placement

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for portable workload placement in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [64.2](phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 299 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [cluster_topology.md](../documents/engineering/cluster_topology.md) — document the portable placement decision and numerical-worker constraints.
- [daemon_architecture.md](../documents/engineering/daemon_architecture.md) — describe host dispatch and the selected workload venue.
- [execution_resources.md](../documents/engineering/execution_resources.md) — align host/client/helper admission.

**Product docs to create/update:**

- [Root README](../README.md) — summarize supported workload placement and its actual host requirements.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [cluster_topology.md](../documents/engineering/cluster_topology.md); retain historical source/evidence links with their original scope.
- Reconcile affected architecture and runtime ownership in [system-components.md](system-components.md).

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 298.1: Resource-aware generic dispatch

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Plan/Workload.hs`, `src/JitML/Test/WorkloadPlan.hs`, `src/JitML/Test/HostWorkloadRegistry.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-298-portable-workload-placement.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `297.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify resource-aware generic dispatch, preserving all earlier completed contracts.

### Deliverables

- Bind selected workload/device scope, admission token, actual launch quota and source identity to the dispatch plan.
- Boundary: Generic admitted placement.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** CPU placement executes the selected real path; foreign admission, unsupported placement and unbudgeted helpers refuse.

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

## Sprint 298.2: Portable cancellation integration; apple real runtime deferred to apple engineering phase

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Plan/Workload.hs`, `src/JitML/Test/WorkloadPlan.hs`, `src/JitML/Test/HostWorkloadRegistry.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-298-portable-workload-placement.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `298.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify portable cancellation integration; Apple real runtime deferred to Apple engineering phase, preserving all earlier completed contracts.

### Deliverables

- Route launch/cancel/terminal capture through the maintained process and admission interfaces.
- Boundary: Dispatch cancellation integration.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Real Linux cancellation and missing reader/owner cases close all owned descendants; later actual Mac/NVIDIA adapters have separate 318/319 acceptance.

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

## Platform acceptance partition

This phase implements common/Linux CPU behavior and validates its actual Linux
runtime; it does not certify the Mac or NVIDIA host adapter. Corresponding
actual OS/device process/resource/lifecycle/producer controls remain mandatory
in 318/319 before the shared freeze. CPU hermetic checks cannot pass those
controls and those later observations cannot block this retained Linux scope.

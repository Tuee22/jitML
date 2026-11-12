# Phase 296: Lifecycle preservation

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for lifecycle preservation in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [43.2](phase-43-live-cluster-lifecycle-and-publication-truth.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 297 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [cluster_topology.md](../documents/engineering/cluster_topology.md) — document explicit lifecycle ownership, helpers and restore verification.
- [checkpoint_format.md](../documents/engineering/checkpoint_format.md) — align preservation and restored exact-object readback requirements.
- [execution_resources.md](../documents/engineering/execution_resources.md) — bound archive, scratch and helper overlap.

**Product docs to create/update:**

- [Root README](../README.md) — summarize supported lifecycle/preservation commands and their verified prerequisites.

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


## Sprint 296.1: Bounded image/snapshot helpers

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Cluster/Lifecycle.hs`, `src/JitML/Cluster/PVSnapshot.hs`, `src/JitML/Cluster/LifecycleFilesystem.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-296-lifecycle-preservation.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `295.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify bounded image/snapshot helpers, preserving all earlier completed contracts.

### Deliverables

- Admit caller+helper overlap, actual limits, packed/archive/host/node storage and canonical image identity before lifecycle actions.
- Boundary: Snapshot and image helpers.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Missing cached image, excessive unpacked allocation and helper-limit mismatch refuse without implicit VM/image startup.

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

## Sprint 296.2: Controlled interruption and original-data readback

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Cluster/Lifecycle.hs`, `src/JitML/Cluster/PVSnapshot.hs`, `src/JitML/Cluster/LifecycleFilesystem.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-296-lifecycle-preservation.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `296.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify controlled interruption and original-data readback, preserving all earlier completed contracts.

### Deliverables

- Run controlled archive/restore/readback and cancellation with exact generation selection and explicit VM retirement.
- Boundary: Preservation and interruption.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Original application data reads back after restore; partial/unproven preservation prevents destructive deletion and retains recovery data.

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

## Cleanup ledger acceptance

296.2 audits generic preservation and Harbor/Percona/API/portal removal claims against exact code, callers, validation and retention. Actual Mac default-VM recovery disk/OS/settings verification belongs to 319.2. Keep pending rows until evidence establishes retirement; preserve recovery data until verified restoration and an explicit human release. Never purge or automatically start the retired default VM.

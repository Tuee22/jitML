# Phase 292: Generated output portability

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for generated output portability in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: Windows host with dedicated WSL2 + linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [3.2](phase-3-governed-document-metadata-enforcement.md), [29.2](phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md), [278.2](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 293 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [execution_resources.md](../documents/engineering/execution_resources.md) — declare supported output roots, WSL2 host exposure and refusal boundaries.
- [checkpoint_format.md](../documents/engineering/checkpoint_format.md) — document portable local layouts and retained-data compatibility obligations.

**Product docs to create/update:**

- [Root README](../README.md) — state only the verified output-root and Windows/WSL2 support boundaries.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [execution_resources.md](../documents/engineering/execution_resources.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 292.1: Complete generated producer and root inventory

**Status**: Blocked
**Implementation**: Planned targets: `bootstrap/check-path-lengths.sh`, `bootstrap/check-generated-paths.py`, `src/JitML/Product/CriterionReviewData.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-292-generated-output-portability.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `291.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: Windows host with dedicated WSL2 + linux-cpu.

### Objective

Implement and verify complete generated producer and root inventory, preserving all earlier completed contracts.

### Deliverables

- Enumerate build/cache/dataset/download/test/runtime/third-party roots, final/staging names, exposure and temporary suffix ownership from actual callers.
- Boundary: Complete producer/root inventory.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Every producer has observed/path-budget scope or explicit unsupported boundary; ignored output is included and an empty tree is not observation.

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

## Sprint 292.2: Portable layouts, budgets and early refusal

**Status**: Blocked
**Implementation**: Planned targets: `bootstrap/check-path-lengths.sh`, `bootstrap/check-generated-paths.py`, `src/JitML/Product/CriterionReviewData.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-292-generated-output-portability.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `292.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: Windows host with dedicated WSL2 + linux-cpu.

### Objective

Implement and verify portable layouts, budgets and early refusal, preserving all earlier completed contracts.

### Deliverables

- Repair criterion-review path/data/reader/Docker layout together; preserve exact identities/legacy reads or implement verified migration. Declare root budgets and refuse unsafe planned names before writes.
- Boundary: Mechanical layout and admission refusal.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Overlong roots, invalid/device names, case/prefix collisions, temporary overflows and third-party overflow fail; human stages prepared index migration before full checkout guard can pass.

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

## Sprint 292.3: Real windows host-mounted output and wsl2 cpu venue acceptance

**Status**: Blocked
**Implementation**: Planned targets: `bootstrap/check-path-lengths.sh`, `bootstrap/check-generated-paths.py`, `src/JitML/Product/CriterionReviewData.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-292-generated-output-portability.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `292.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: Windows host with dedicated WSL2 + linux-cpu.

### Objective

Implement and verify real Windows host-mounted output and WSL2 CPU venue acceptance, preserving all earlier completed contracts.

### Deliverables

- Use a dedicated bounded CPU-only WSL2 distro with Docker/Kind/toolchain and a Windows-host repository bind mount; observe real host-exposed producers and Windows access semantics.
- Boundary: Actual Windows/WSL2 filesystem proof.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Validate final/temporary names, traditional path limits, readback and mount visibility on the real Windows host; a Linux string model or absent toolchain cannot close it.

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

Inventory every build/cache/data/download/runtime/test producer and temporary name, declare bounded Windows roots, shorten owned layouts without breaking retained data, and provide early refusal for unsupported tool/root combinations. Exercise real Windows host-mounted paths with the dedicated WSL2 CPU-only setup in AGENTS/CLAUDE; CPU string models alone cannot prove Windows I/O behavior. Check traditional path limits and actual filesystem semantics. This is Windows path/venue acceptance, not NVIDIA work or a Windows-native numerical substrate.

## Platform and mechanical migration boundary

This phase owns CPU/Windows-exposed outputs and WSL2 host-mounted path
semantics. Actual CUDA compiler/device outputs and Metal/native bridge outputs
are engineered and observed in 318/319 on their own hosts; they do not gate 292.
292.2 owns the existing 516-path mechanical criterion-data layout migration,
reader compatibility, deliberate data/identity retention and Docker inclusion.
301 owns prospective acceptance policy/review method, not a future repair needed
to pass 292. Preserve both logical keys and retained bytes or implement a verified
migration before any old name is retired. Agents prepare and validate the
working tree; the human must stage the intentional old-path removals/new paths
under Git policy before the complete tracked/unignored inventory can pass.
Waiting on that external human index operation is explicit, not a future phase.

Use existing explicit operator resource limits for this bounded Windows/WSL2
probe. The unified target admission implementation in 295 is not a prerequisite
for this phase; missing current CPU/RAM/storage reserves refuse the probe.

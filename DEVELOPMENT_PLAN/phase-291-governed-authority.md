# Phase 291: Governed authority

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Engineering implementation for governed authority in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Engineering implementation.
**Inherited obligations**: [3.2](phase-3-governed-document-metadata-enforcement.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 292 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [cli_command_surface.md](../documents/engineering/cli_command_surface.md) — reconcile root CLI authority, generated references and the explicit transfer boundary.
- [code_quality.md](../documents/engineering/code_quality.md) — register the governed metadata, authority, link and marker checks.
- [documentation_standards.md](../documents/documentation_standards.md) — reconcile canonical ownership, metadata, anchors and generated-region rules.

**Product docs to create/update:**

- [Root README](../README.md) — summarize only the validated authority migration and retain all binding CLI links.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [cli_command_surface.md](../documents/engineering/cli_command_surface.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 291.1: Canonical owner registry and root transfers

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Docs/Generate.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-291-governed-authority.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `290.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify canonical owner registry and root transfers, preserving all earlier completed contracts.

### Deliverables

- Inventory every durable contract, existing owner, root reference and transfer consumer; extend the source registry and migrate only reviewed authority with redirects.
- Boundary: Contract ownership and verified root references.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Missing/conflicting owners and unresolved inbound references fail; unchanged binding CLI doctrine remains enforceable.

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

## Sprint 291.2: Metadata and current/target boundaries

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Docs/Generate.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-291-governed-authority.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `291.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify metadata and current/target boundaries, preserving all earlier completed contracts.

### Deliverables

- Reconcile required nonempty unique headers, parsed purpose/section boundaries, canonical claims and explicit target owners.
- Boundary: Metadata and implemented/target boundary.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Fenced/header examples cannot supply metadata; targets stated as implemented without owned evidence fail their controls.

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

## Sprint 291.3: Link/anchor/generated-region controls

**Status**: Blocked
**Implementation**: Planned targets: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Docs/Generate.hs`, with this sprint's selectable controls in `test/`; changes stay within its declared work package.
**Docs to update**: `phase-291-governed-authority.md`, `ordered-execution-plan.md`, `ordered-plan-transfers.md`, and the governed owners listed in this phase's Documentation Requirements.
**Blocked by**: Sprint `291.2`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify link/anchor/generated-region controls, preserving all earlier completed contracts.

### Deliverables

- Resolve retained local targets/anchors, versioned heading slugs, generated ownership and actual marker replacement.
- Boundary: Real links and generated regions.
- Implement this package and its independently enumerated selectable controls, including a real positive path and rejection of missing, malformed or misleading inputs.
- Update the maintained source, generated references and documentation together. Use independent fixture credentials and bounded runtime probes where applicable; preserve all original cases in the gate inventory.

### Validation

**Required result:** Broken/encoded targets, duplicate/reversed/nested/crossing markers fail; valid Unicode headings and examples remain stable.

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

## Cleanup ledger acceptance

Audit and fix broken ExternalBars documentation references under 291.3, preserving exact historical meanings and current owner links.

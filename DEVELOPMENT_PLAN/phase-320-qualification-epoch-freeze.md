# Phase 320: Qualification epoch freeze

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Candidate freeze for qualification epoch freeze in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Candidate freeze.
**Inherited obligations**: [261.3](phase-261-contract-driven-live-execution-integration-journal.md), [278.1](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [278.2](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 321 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [validation_execution.md](../documents/engineering/validation_execution.md) — finalize common source/criterion/build-policy freeze and authorized lane executable seals.
- [run_contract.md](../documents/engineering/run_contract.md) — bind the immutable common epoch and append-only per-lane seal slots.
- [training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md) — freeze final independently reviewed criteria and canonical recipes.

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


## Sprint 320.1: Final independent source and criterion review

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/SourceDigest.hs`, `src/JitML/Product/ExecutionProvenance.hs`, `src/JitML/Test/RunContract.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-320-qualification-epoch-freeze.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `319.3`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify final independent source and criterion review, preserving all earlier completed contracts.

### Deliverables

- Independently review exact completed engineering source, criteria, datasets, recipes and policy; no qualifying outcomes are used to set bars.
- Boundary: Prospective final review.
- Verify all earlier engineering, hardware-readiness and consumer/schema obligations are closed; bind exact common source, per-lane build recipes/toolchain requirements and authorized executable-seal slots, criterion reviews, row order, datasets and finite execution policy.
- Seal one shared epoch only after final independent prospective review. Missing earlier evidence refuses freezing; no subsequent phase is a freeze prerequisite.

### Validation

**Required result:** Stale/copied review, altered source/policy or missing earlier engineering acceptance refuses candidate authorization.

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

## Sprint 320.2: Close engineering inputs and seal the immutable candidate

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Product/SourceDigest.hs`, `src/JitML/Product/ExecutionProvenance.hs`, `src/JitML/Test/RunContract.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-320-qualification-epoch-freeze.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `320.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Implement and verify close engineering inputs and seal the immutable candidate, preserving all earlier completed contracts.

### Deliverables

- Freeze the common source/criteria/build recipes/toolchain requirements and authorized immutable lane executable-seal slots.
- Boundary: Common source epoch and lane slots.
- Verify all earlier engineering, hardware-readiness and consumer/schema obligations are closed; bind exact common source, per-lane build recipes/toolchain requirements and authorized executable-seal slots, criterion reviews, row order, datasets and finite execution policy.
- Seal one shared epoch only after final independent prospective review. Missing earlier evidence refuses freezing; no subsequent phase is a freeze prerequisite.

### Validation

**Required result:** Missing earlier input refuses, but absent future qualifying journals or foreign-host binary measurements do not block common freeze; replacement sealed identities fail the lane-slot protocol.

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

## Lane executable seals

The common epoch freezes source and predeclared per-lane build recipes,
toolchain requirements and authorized seal slots. It need not possess
unbuildable foreign-host binaries or actual later qualifying journals. Before
its first qualifying seed, each real lane builds the exact frozen source on
its own host and authenticates one append-only executable/image/runtime seal
bound to that epoch and lane. Every row binds both core epoch and immutable
lane seal. A missing slot cannot admit a row. Filling an authorized slot
does not edit common source or invalidate earlier lane records; replacing a
sealed digest, changing a recipe/toolchain policy or reissuing a slot refuses
and requires a new epoch. See the [execution contract](../documents/engineering/validation_execution.md#lane-executable-seals).

Freeze acceptance requires only earlier engineering and prospective reviews.
It must refuse missing earlier controls but never demand qualification 321–324
or successful final aggregation/reporting 325–335 before issuing the epoch.

# Phase 331: Complete per model evidence

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Frozen-candidate acceptance for complete per model evidence in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Frozen-candidate acceptance.
**Inherited obligations**: [285.1](phase-285-contract-driven-per-model-evidence.md), [285.2](phase-285-contract-driven-per-model-evidence.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It closes before Phase 332 begins. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [product_completion_contract.md](../documents/engineering/product_completion_contract.md) — review complete per-model proof and no-omission admission.
- [training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md) — review all-row evidence completeness and authentic final observations.

Review these contracts against the already frozen implementation. Record actual
results and limitations in this phase; a needed source/schema/recipe or contract
change reopens its earliest engineering owner and creates a new epoch.

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


## Sprint 331.1: Complete current model evidence aggregate and retention

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Test/ModelEvidence.hs`, `src/JitML/Test/RowAssertions.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-331-complete-per-model-evidence.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `330.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Execute and admit complete current model evidence aggregate and retention, preserving all earlier completed contracts.

### Deliverables

- Own the `complete current model evidence aggregate and retention` work package from the transferred contracts; preserve the exact requirements and failure history linked above.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

1. Validate the exact real inputs produced by earlier phases through the pre-freeze production implementation, including refusal controls for absent, stale, foreign, reordered, duplicated and tampered evidence.
2. Retain complete scoped transcripts and preservation receipts. CPU aggregation consumes hardware records and starts no accelerator or replacement training.
3. A scientific refusal or missing measurement blocks this sprint. A code/schema correction starts a new epoch through explicit reopening; it is not hidden in an acceptance phase.

The scoped gate must be implemented in Phase 290 before it is invoked. Existing
`jitml test <stanza> --<substrate> --test-options=...` selectors remain the test
boundary; this plan does not invent an already-supported CLI flag. A scoped pass
never becomes a full-stanza pass. Every deferred assertion has an explicit later
owner in the transfer register, rather than a skip, allowlist or deleted case.

### Remaining Work

- Complete this work package and retain its declared acceptance evidence.
- Compare changed behavior with earlier contracts; reopen the earliest violated owner before continuing.

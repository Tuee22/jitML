# Phase 335: Final report handoff

**Status**: Authoritative source
**Supersedes**: Current execution ownership for the mapped obligations; historical evidence remains scoped to its original source.
**Referenced by**: [ordered execution plan](ordered-execution-plan.md), [transfer register](ordered-plan-transfers.md), [README](README.md)
**Generated sections**: none

> **Purpose**: Frozen-candidate acceptance for final report handoff in the current numerical sequence.

## Phase State

**Blocked; implementation and validation are open.** This planning refactor supplies
no software, hardware, scientific or qualification pass.

**Validation hardware**: linux-cpu.
**Change boundary**: Frozen-candidate acceptance.
**Inherited obligations**: [275.2](phase-275-no-caveat-closure-guard.md), [286.2](phase-286-evidence-derived-closure-guard.md), [289.1](phase-289-evidence-typed-report-measurements.md), [289.2](phase-289-evidence-typed-report-measurements.md).

The [execution contract](ordered-execution-plan.md#validation-contract) and
[transfer register](ordered-plan-transfers.md) define this phase's complete scope.
It completes the current execution sequence. Historical source receipts do not close it.

## Documentation Requirements

These are planned acceptance obligations; this planning edit does not mark any
documentation or implementation requirement complete.

**Engineering docs to create/update:**

- [product_completion_contract.md](../documents/engineering/product_completion_contract.md) — review final no-caveat handoff and retained evidence duties.
- [cli_command_surface.md](../documents/engineering/cli_command_surface.md) — review the frozen report command/output contract and generated reference.

Review these contracts against the already frozen implementation. Record actual
results and limitations in this phase; a needed source/schema/recipe or contract
change reopens its earliest engineering owner and creates a new epoch.

**Product docs to create/update:**

- [Root README](../README.md) — link the final admitted report and the authoritative plan handoff without duplicating its status ledger.

**Cross-references to add:**

- Reconcile this phase in the [ordered execution index](ordered-execution-plan.md) and [obligation transfer register](ordered-plan-transfers.md).
- Add or verify the relevant current-owner link from [product_completion_contract.md](../documents/engineering/product_completion_contract.md); retain historical source/evidence links with their original scope.

## Sprint sizing

Every sprint targets **2–4 engineer-days**, with compute time recorded separately.
A sprint has one reviewable boundary and its own passing positive and negative
controls. If discovery makes it more than twice the peer median, split its
remaining scope prospectively before execution; never lower scientific budgets,
seed counts, assertions or acceptance bars to meet an effort estimate.


## Sprint 335.1: Evidence-typed complete report and retained-data operator handoff

**Status**: Blocked
**Implementation**: Execute the already-implemented production paths in `src/JitML/Test/Report.hs`, `src/JitML/Product/Completion.hs`, `src/JitML/Product/StatusEvidence.hs`; retain evidence without executable-source, schema, recipe or criterion changes.
**Docs to update**: Evidence/status updates to `phase-335-final-report-handoff.md` and `ordered-execution-plan.md`; review the listed governed contracts without changing the frozen acceptance rules.
**Blocked by**: Sprint `334.1`.
**Effort**: 2–4 engineer-days; one bounded acceptance unit.
**Validation hardware**: linux-cpu.

### Objective

Execute and admit evidence-typed complete report and retained-data operator handoff, preserving all earlier completed contracts.

### Deliverables

- Validate actual final report, audit/status evidence, credential/data retention and restoration/readback, then independently issue the closing receipt.
- Boundary: Final typed report, independent closure and handoff.
- Consume the Phase 320 frozen candidate through existing production APIs; preserve source, schema, recipes, criteria, seed order, served index and execution policy.
- Retain actual observations, terminal outcomes, source/device bindings and preservation seals. Any discovered implementation defect reopens its earliest engineering owner and invalidates affected downstream evidence.

### Validation

**Required result:** Completion is derived after the final output passes, never from 335 already marked Done; missing output, circular status, stale source or incomplete handoff refuses.

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

## Required inherited detail

Deliver the typed complete report, retained-data/credential ownership, restoration/readback, finite retention release and operator handoff. Repository source is unchanged from the shared epoch; human performs any staging/commit/push.

## Final completion without self-reference

After actual audit 333 and status 334 inputs exist, validate the final typed
report/handoff and independently judge all retained acceptance receipts,
including this sprint's completed output, to issue the final closure decision.
Neither report generation nor its test requires 335 already to be declared
Done. The resulting receipt is the evidence used to derive 335 and product
closure. Missing output/receipt, a false prior Done, a circular gate or a
post-freeze source change must refuse closure. No 336 phase is required.

# Phase 286: Evidence-Derived Closure Guard

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Evidence-Derived Closure Guard. Originally migrated from legacy Sprint 34.1 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `286.2` → [316](phase-316-closure-machinery.md), [332](phase-332-real-closure-admission.md), [335](phase-335-final-report-handoff.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** on the expanded campaign obligations below. Historical closure
remains scoped to the execution and implementation it actually proved.

The [validation foundation refactor](README.md#validation-foundation-refactor)
owns the current execution order. Sprint `221.2` first updates the source
catalogue/checkers for the reopened sprint graph; those source changes are not
part of this documentation-only revision. Current machine projection still
reflects the old catalogue and must not be reported as validating these targets.

The [execution contract](../documents/engineering/validation_execution.md) and
[resource contract](../documents/engineering/execution_resources.md) state the
new targets. Atomic row recovery is not implemented or authorized by prose: until
`261.2` passes, existing qualification remains non-resumable. No historical partial
attempt, diagnostic review copy or readiness ledger is adopted as qualification.

## Sprint 286.2: Campaign-aware closure projection [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `275.2`, Sprint `285.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Closure is a projection of fulfilled current campaign and standing obligations, with no externally settable closed status.

### Deliverables

- Extend closure readers to the new source/row/campaign identities and explicit dependency graph.
- Preserve every absent, stale, failed, incomplete and pending-removal refusal.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Mutation controls prove no missing required obligation can be hidden by narrative or a status literal.
2. Pass current unit/negative controls and exact production status projection.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement the deliverables after the listed prerequisites; retain every failed or incomplete observation in its original scope.
- Complete the listed acceptance in its declared evidence scope, retain the required records, and reconcile the source status catalogue before claiming closure.

## Retained Historical Contract and Evidence

The remainder records prior implementation, commands, status and failures. Its
claims retain their original source, policy and date. Superseded launch ordering,
resource rules and uninterrupted-process requirements do not override the current
sprints above. Preserve these receipts; do not execute a historical recipe as a
current authorized campaign.

## Retained Historical Phase State

✅ **Done**.

## Sprint 286.1: Evidence-Derived Closure Guard [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Product/PhaseStatus.hs`, `test/unit/Main.hs`
**Docs to update**: `development_plan_standards.md`, `../documents/documentation_standards.md`, `system-components.md`

### Objective

The docs-check closure guard derives phase status from evidence (negative-control pass,
per-model convergence pass, empty ledger) instead of trusting a hand-edited registry.

### Deliverables

- `allProductPhasesDone` is computed from the `jitml-negative-controls` and
  `jitml-model-convergence` results and the ledger state, not a literal in
  `PhaseStatus.hs`; a hand edit to the registry that contradicts the evidence fails the
  build (this closes the Sprint `19.3` non-falsifiability gap reopened by the audit).
- The closure-claim scanner additionally rejects any `Real`-tagged row whose negative
  control is not green.

### Validation

```bash
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the evidence-derived guard.

## Historical Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- [Validation execution](../documents/engineering/validation_execution.md),
  [execution resources](../documents/engineering/execution_resources.md),
  [run contract](../documents/engineering/run_contract.md), and
  [testing policy](../documents/engineering/unit_testing_policy.md).

**Product docs to create/update:**

- [Plan](README.md#validation-foundation-refactor), [overview](00-overview.md),
  [component inventory](system-components.md), and the corresponding lane
  report/portable evidence after actual qualification.

**Cross-references to add:**

- The current typed catalogue and [legacy removal ledger](legacy-tracking-for-deletion.md)
  name every changed owner and deprecated active path; original evidence is retained.

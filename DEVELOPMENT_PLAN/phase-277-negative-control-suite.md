# Phase 277: Negative-Control Suite

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Negative-Control Suite. Originally migrated from legacy Sprint 32.1 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

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

## Sprint 277.2: Campaign authority and completion negative controls [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`, Sprint `225.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Every production row and campaign authority boundary has a deliberate negative control with the correct rejection reason.

### Deliverables

- Extend registered per-row controls to unfinished cohorts, omitted attempts, foreign epochs, stale review copies and substituted artifacts.
- Pair renamed/indirected constant-output negatives with trained-weight-dependent positives under 225.2; a name denylist is not behavioral assurance.
- Require baseline buildability and actual mutation sensitivity without allowlisting known failures.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Run targeted control regressions first, demonstrate rejection for the specified reason, then pass the complete unfiltered negative-control stanza.
2. Ensure missing row/control registration is a test failure rather than absent coverage.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
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

✅ **Done** for the retained pure gate-soundness scope. Production-path
request/event, journal/reducer, lifecycle, and mandatory per-row controls were
transferred to Phases `280`–`282`; this phase does not claim those later gates.

## Sprint 277.1: Negative-Control Suite [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/NegativeControls.hs`, `test/negative-controls/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

A committed set of hand-built known-fake records, each paired with the pure gate
that must reject it. The `jitml-negative-controls` stanza (wired into
`jitml test all`) fails the build if any retained gate-soundness fake is
accepted and, while that work was outstanding, separately required the
transferred production-path categories to remain explicitly enumerated (as of
2026-09-30 Phases `280`–`282` implement them and the stanza asserts the pending
list is empty).

### Deliverables

- Retain pure known-fake records for untrained learned state, self-referential or
  below-threshold convergence, synthetic RL evidence, invalid supervised
  evidence, collapsed operators, and algorithm-specific gate violations.
- Assert each pure gate returns *reject* for its known-fake; a gate that cannot
  reject its known-fake is a failure, not a pass.
- Keep the outstanding production-path categories explicit while they are
  outstanding. Phases `280`–`282` own invalid request/event fixtures, journal/reducer
  properties, lifecycle failures, and mandatory per-ProductRow registration.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented `NegativeControls.hs` and the retained pure gate-soundness stanza;
  the committed known-fakes were rejected and the transferred production-path
  work remained explicitly non-empty. `docker compose run --rm jitml env
  JITML_SUBSTRATE=linux-cpu cabal test jitml-negative-controls
  --test-options='--hide-successes --color=never'` passed **3 / 3** on
  2026-07-06. This evidence does not satisfy Phases `280`–`282`.

## Historical Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/unit_testing_policy.md`
- `../documents/engineering/product_completion_contract.md`

**Product docs to create/update:**

- `system-components.md`

**Cross-references to add:**

- Link the retained pure gate-soundness scope to the production-path controls
  owned by [Phase 280](phase-280-runcontract-negative-controls-request-and-event-fixtures.md),
  [Phase 281](phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md),
  and [Phase 282](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md).
- Record that the retained `jitml-negative-controls` stanza is a standing gate of
  [Phase 262](phase-262-contract-driven-live-execution-browser-and-playwright.md),
  which re-runs it against its final aligned `jitml:local` image. That re-run
  re-proves this phase's gate-soundness scope on the closing image; it does not
  extend the scope, and it does not satisfy Phases `280`–`282`.

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

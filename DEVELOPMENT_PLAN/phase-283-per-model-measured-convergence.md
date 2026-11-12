# Phase 283: Per-Model Measured Convergence

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Model Measured Convergence. Originally migrated from legacy Sprint 33.1 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `283.2` → [315](phase-315-evidence-projection-machinery.md), [329](phase-329-real-convergence-projections.md).

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

## Sprint 283.2: Current campaign convergence projections [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`, Sprint `263.3`, Sprint `268.2`, Sprint `273.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Per-model convergence reports derive measured outcomes from complete current row cohorts, with no declaration-to-measurement promotion.

### Deliverables

- Preserve every row-specific learning predicate and expose authentic initial/final and all-attempt evidence.
- Treat an independently revised criterion as a new prospective policy/source epoch; never retroactively relabel a retained failure.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Reject missing seed outcomes, changed served index, diagnostic reviews and stale plans through the production convergence reader.
2. Pass the complete convergence stanza using admitted current lane objects, with real underlying scientific execution retained.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-model-convergence --linux-cpu
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

## Sprint 283.1: Per-Model Measured Convergence [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RowAssertions.hs`, `test/model-convergence/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

Every SL/RL/AlphaZero product row has a case that trains from a real random init and
asserts the measured metric ≥ the external bar, feeding the already-sound
`RowAssertions` helpers with real training output rather than synthetic fixtures.

### Deliverables

- One `jitml-model-convergence` case per `ProductRow`, enumerated from
  `JitML.Product.Matrix.allProductRows`; a missing case fails the coverage assertion.
- SL: train through `JitML.SL.Architecture` on the real staged dataset (held-out test
  split); assert `assertSupervisedRowEvidence` against the measured test metric and a
  real, decreasing loss trajectory.
- RL: train the policy, evaluate the **trained policy** (never the removed expert
  controller), assert `assertRlRowEvidence` with `rleSyntheticTransitionEvidence = False`
  and median-over-`k`-seeds ≥ external bar.
- AlphaZero: real multi-generation self-play + full-`maxPlies` arena; assert
  `assertAlphaZeroRowEvidence` with a strict win-margin.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

- Implemented the row-complete model-convergence stanza; `docker compose run --rm jitml env JITML_SUBSTRATE=linux-cpu cabal test jitml-model-convergence --test-options='--hide-successes --color=never'` passed 111/111 on 2026-07-06.
- Revalidated after the widened architecture/vectorized-RL remediation:
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`
  passed **111 / 111** on 2026-07-10.

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

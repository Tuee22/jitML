# Phase 274: Attestation Join

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Attestation Join. Originally migrated from legacy Sprint 31.1 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `274.2` → [313](phase-313-aggregate-reader-machinery.md), [325](phase-325-real-lane-join.md).

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

## Sprint 274.2: Exact join of independent campaigns [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `263.3`, Sprint `268.2`, Sprint `273.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Join the independently admitted CPU, CUDA and Apple campaigns on CPU without executing an accelerator.

### Deliverables

- Require exact row coverage, source epoch, contract/criterion identities, lane/device identities and portable qualifying objects from every input.
- Keep within-substrate determinism obligations; an aggregate does not invent numerical parity between substrates.
- Reject stale legacy fragments, mixed campaigns, missing objects and hand-authored pass tables.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Exercise positive joins of real admitted records and negatives for stale, foreign, duplicate, omitted, corrupted or mismatched inputs.
2. Complete the CPU-only join and retain the production-reader result; no accelerator rerun is part of this validation.

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

## Sprint 274.1: Attestation Join [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/ProductAggregation.hs`, `DEVELOPMENT_PLAN/attestations/`
**Docs updated**: `system-components.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The retained obligation is exact row/lane coverage and a fail-closed join.
Phase `276` replaces the historical prose-fragment implementation with
`JitML.Test.ProductAggregation`, which reads the three pinned portable journals,
admits their complete current lane projections, and joins by ProductRow identity.
The expanded journal and completed-evidence obligations belong to Sprint `276.1`;
this ownership transfer does not introduce a backward dependency.

### Deliverables

- Every product row has exactly one admitted cell from each required lane.
  Missing, duplicated, stale, failed, and not-run cells fail admission.
- The versioned aggregate retains each cell's plan, admitted checkpoint identity,
  device witness, refined completion, measured counters, and convergence metrics.
- Markdown fragments are presentation artifacts checked against live issuance.
  They cannot supply a completion or aggregate cell.
- Aggregation runs on `linux-cpu`, consuming retained accelerator inputs without
  rerunning either accelerator.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu --test-options='-p "Journal-derived product aggregation"'
docker compose run --rm jitml cabal run exe:jitml -- docs check
```

### Historical Closure Evidence

Reopened 2026-07-05. The join closed on the three **withdrawn** per-lane
fragments (55 rows each) whose row evidence was fabricated, so the aggregator's
fail-closed contract is unmet: `src/JitML/Test/Report.hs` accepted fragments that
were not backed by real trained-state deltas, completed-training checkpoints,
verified dataset bytes, or real kernel dispatch. The negative-control suite
later covered fabricated evidence, Phase `29` committed a `linux-cuda`
fragment, and the committed-fragment join passed on `linux-cpu`. Those
fragments remain historical because they predate exact persisted admission.
Aggregation stays `linux-cpu`-only and re-runs no accelerator.

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
```

2026-07-10 validation:

```bash
docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct --test-options='-p "committed product-lane attestations aggregate without drift" --hide-successes --color=never'
```

The focused Phase `31.1` committed attestation join passed **1 / 1**, reading
`DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`, and
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md` and producing the
expected **165** lane-row evidence records.

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

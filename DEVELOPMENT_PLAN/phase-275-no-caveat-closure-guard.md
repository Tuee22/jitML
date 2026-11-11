# Phase 275: No-Caveat Closure Guard

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: No-Caveat Closure Guard. Originally migrated from legacy Sprint 31.2 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

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

## Sprint 275.2: Closure from complete campaign obligations [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `274.2`, Sprint `278.3`, Sprint `280.2`, Sprint `285.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Product closure is derived from complete current campaigns and all required clean engineering/scientific gates, never from a source literal or partial report.

### Deliverables

- Require all current lane admissions, exact aggregate, independent criterion/provenance audit, clean required suites and cleared owned legacy residue.
- An observer disconnect, incomplete row, missing after-state, unknown measurement or failed cleanup never becomes a pass.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Make every missing, stale or failed obligation independently force an unclosed result through the production status reader.
2. Verify that an all-green narrative and individually passing readiness ledger cannot manufacture closure.

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

## Sprint 275.1: No-Caveat Closure Guard [✅ Done]

**Status**: Done
**Implementation**: `README.md`, `DEVELOPMENT_PLAN/README.md`, `src/JitML/Lint/Docs.hs`
**Docs updated**: `README.md`, `00-overview.md`, `system-components.md`

### Objective

The no-caveat product claim is restored in the governed docs only from the
merged evidence. `src/JitML/Lint/Docs.hs` permits closure language through
`jitml docs check` only after the typed `PhaseStatus` registry reports every
Phase `19`–`34` sprint Done, every Exit-Definition obligation is met against the
merged report card, and the legacy ledger is empty.

### Deliverables

- `jitml test all --live --linux-cpu` passes with every product-matrix `rowId`
  present in the merged report card and no row reduced to a representative smoke
  check.
- All then-current eighteen [README.md → Exit Definition](README.md#exit-definition)
  items pass against the merged report card, and
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) holds zero
  `Pending Removal` entries.
- `jitml docs check` continues to reject product-closure language until the typed
  `PhaseStatus` registry reports every Phase `19`–`34` sprint Done, then permits
  the reopened→closed flip; stale "reopened" wording is rejected once the flip is
  eligible.
- The final status paragraph in `README.md`, `00-overview.md`, and
  `DEVELOPMENT_PLAN/README.md` names exact dates, the three real lanes
  (`linux-cpu`, `linux-cuda`, `apple-silicon`), the aggregated row count, and the
  committed report artifacts under `DEVELOPMENT_PLAN/attestations/`.

### Validation

```bash
docker compose run --rm jitml cabal run exe:jitml -- test jitml-unit --linux-cpu
docker compose run --rm jitml cabal run exe:jitml -- docs check
docker compose run --rm jitml cabal run exe:jitml -- check-code
```

### Historical Closure Evidence

Reopened 2026-07-05. The reopened→closed flip had previously been permitted on a
merged report card backed by fabricated evidence, and the typed `PhaseStatus`
registry reported every Phase `19`–`31` sprint Done while the underlying rows
were not real. The 2026-07-06 guard now extends through Phases
[`32`](README.md#legacy-to-new-phase-map)–[`34`](README.md#legacy-to-new-phase-map),
the standing negative-control and per-model convergence gates are closed, Phase
`29` had a current-source CUDA fragment, and Sprint `31.1` exercised the join.
The historical Sprint `31.2` run then exercised the governed status flip and
named the three lanes, **55** rows per lane, and the **165** lane-row aggregate.
That flip is no longer permitted on those fragments because their artifact
evidence predates Store admission. The retained closure-guard mechanism stays
Done; the current flip waits for Sprint `31.3`'s refreshed admitted journals and
the later governance chain. Aggregation stays `linux-cpu`-only and never reruns
an accelerator.

2026-07-11 validation:

```bash
docker compose run --rm jitml cabal run exe:jitml -- test jitml-unit --linux-cpu
docker compose run --rm jitml cabal run exe:jitml -- docs check
docker compose run --rm jitml cabal run exe:jitml -- check-code
```

Result: `jitml-unit --linux-cpu` passed **278 / 278**, `docs check: ok`, and
`check-code: ok`.

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

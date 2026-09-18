# Phase 274: Attestation Join

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Attestation Join. Single-session phase migrated from legacy Sprint 31.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

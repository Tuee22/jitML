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
**Implementation**: `src/JitML/Test/Report.hs`, `DEVELOPMENT_PLAN/attestations/`
**Docs updated**: `system-components.md`, `../documents/engineering/product_completion_contract.md`

### Objective

`src/JitML/Test/Report.hs` reads the three committed per-lane attestations and
joins them by `ProductRow.rowId` into one aggregated report card, failing closed
on any missing, stale, unclassified, or scaffold evidence so that no lane can be
silently skipped and no historical pass count can stand in for a real row.

### Deliverables

- The aggregator reads
  `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`,
  `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`, and
  `DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md` and joins them by
  `ProductRow.rowId` against the typed product matrix registry.
- The join fails on missing per-row evidence, on `rowId`s that are stale relative
  to the current typed matrix, on stale generated browser contracts, on
  unsupported rows that lack an explicit non-product classification, and on any
  active legacy-scaffold row.
- Every joined row carries the real-ML evidence fields — trained-state deltas
  (initial/final parameter hashes plus update count), completed-training
  checkpoint witness with convergence metrics, verified dataset SHA, demo render
  of the trained artifact, integration id, and e2e id — plus per-lane device
  evidence, with unsupported-lane rows distinguished from failed supported rows.
- This retained report-card schema does not establish current checkpoint
  eligibility. Sprint `31.3` accepts only refreshed journal rows carrying the
  opaque Store-admitted artifact identity produced through Sprint `10.12` and
  consumed by Sprint `19.4`.
- Aggregation uses no accelerator commands: it consumes only committed fragments
  and `--linux-cpu` runs.

### Validation

```bash
docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct --test-options='-p "committed product-lane attestations aggregate without drift" --hide-successes --color=never'
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

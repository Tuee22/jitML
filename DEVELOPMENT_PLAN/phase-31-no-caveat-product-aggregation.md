# Phase 31: No-Caveat Product Aggregation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-30-apple-silicon-product-lane.md](phase-30-apple-silicon-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Merge the three committed per-lane attestations by `rowId` on
> `linux-cpu` into one no-caveat product report card and flip the governed docs
> from reopened to closed only when every Phase `19`–`34` sprint is Done.

## Phase State

⏸️ **Blocked** (reopened 2026-07-12 for Sprint `31.3`). The current
aggregation joins report fragments that predate scenario journals and the exact
run-evidence contract. Sprint `31.3` is blocked directly by Sprint `30.4` and
remains a `linux-cpu`-only join. Sprints `31.1`–`31.2` remain Done on their
retained historical aggregation surface.

That direct blocker remains correct: its upstream chain now begins at
`10.6 -> 10.12 -> 19.4` before continuing through `21.4`, `25.4`, `28.4`,
`29.5`, and `30.4`. No historical lane fragment can bypass that chain.

**Historical retained closure (diagnostic only).** ✅ **Done** (2026-07-11).
The old join mechanics consumed three report-card fragments with **55** rows
each and produced **165** lane-row records on `linux-cpu`. The CUDA fragment
reported publisher **55 / 55**, integration **56 / 56**, and timing **55 / 55**.
Those fragments predate the exact V2 supervised artifact, Store admission, and
scenario-journal contract. Their `eligible` fields therefore record historical
storage/publisher outcomes, not admitted persisted checkpoints, and cannot be
current Sprint `31.3` inputs. Aggregation remains `linux-cpu` only and never
reruns an accelerator; refreshed accelerator journals are produced by Sprints
`29.5` and `30.4` after the upstream chain closes.

**Historical (withdrawn):** ✅ **Claimed Done on 2026-07-05** after Phase `30`
refreshed `DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md` with the
row-complete Phase `30` Apple fragment. The aggregation consumed three committed
fragments, each with 55 product rows and per-lane device evidence: `linux-cpu`,
`linux-cuda`, and `apple-silicon`. The 2026-07-05 realness audit withdrew those
fragments as fabricated evidence, so this closure is void.

**Validation substrate**: `linux-cpu` only — aggregation lane. This phase merges
the committed per-lane attestations produced by Phase `28` (`linux-cpu`), Phase
`29` (`linux-cuda`), and Phase `30` (`apple-silicon`); it does **not** re-run
`linux-cuda` or `apple-silicon`. Per rule M invariant (d), the `### Validation`
gates below contain only `--linux-cpu` invocations plus committed-fragment merge
steps, and never `-fcuda` or `--apple-silicon`.

## Objective

The no-caveat product claim is restored on one `linux-cpu` host from evidence
alone. `src/JitML/Test/Report.hs` joins the committed
`DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`, and
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md` by
`ProductRow.rowId` into one report card whose every row carries real evidence:
implemented deep architecture, verified dataset bytes, trained-state deltas,
Store-admitted checkpoint identity with convergence metrics, demo rendering of
the admitted artifact, integration coverage, e2e coverage, and per-lane device
evidence.
Every one of the eighteen Exit-Definition items passes against the merged card,
the [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) ledger is
empty, and `jitml docs check` permits the reopened→closed status flip only after
the typed `PhaseStatus` registry reports every Phase `19`–`34` sprint Done. The
final status paragraph in the governed docs names exact dates, the three real
lanes, the aggregated row count, and the report artifacts.

## Sprint 31.1: Attestation Join [✅ Done]

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

## Sprint 31.2: No-Caveat Closure Guard [✅ Done]

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
[`32`](phase-32-external-truth-realness-harness.md)–[`34`](phase-34-plan-truth-governance.md),
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

## Sprint 31.3: Journal-Derived Product Aggregation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Test/Report.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`,
`DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md`,
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md`
**Blocked by**: Sprint `30.4`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Join the three committed lane journals into one product result without
reconstructing evidence from prose, test ids, or post-hoc probes. This sprint
owns the aggregation portion of
[Exit Definition](README.md#exit-definition) item `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Decode and validate each committed lane fragment as a versioned scenario
  journal whose rows carry matching `rowId`, `PlanId`, opaque Store-admitted
  artifact identity, substrate, and completed evidence.
- Join the three fragments by product-row identity and fail on missing,
  duplicated, mismatched, failed, or not-run cells.
- Derive all aggregate counts and report measurements from the joined typed
  results; no prose table or hand-edited total can manufacture coverage.
- Keep aggregation `linux-cpu` only and consume the committed accelerator
  fragments without rerunning either accelerator.
- Emit the merged report and closure input consumed by the external-truth and
  status-governance phases.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `30.4` publishes its refreshed contract-driven lane
  fragment containing admitted artifact identities. Sprint `29.5` supplies the
  CUDA fragment transitively, and Sprint `28.4` supplies the refreshed
  `linux-cpu` fragment.
- Implement typed journal decode/join and regenerate the aggregate report.
- Retire post-hoc/prose-fragment aggregation only after the join rejects all
  negative fixtures and the CPU-only validation passes.

## Documentation Requirements

**Engineering docs updated:**
- `documents/engineering/run_contract.md` — typed lane-journal validation and
  CPU-only product aggregation.
- `documents/engineering/product_completion_contract.md` — record the final
  merged-evidence closure state and the Phase `19`–`34` validation boundary.
- `documents/engineering/unit_testing_policy.md` — ownership of the attestation
  join and the no-caveat closure gate tests.

**Product docs updated:**
- `README.md` — the final no-caveat product status paragraph with dates, lanes,
  row count, and report artifacts.

**Cross-references to add:**
- Consumes the committed per-lane attestations from Phase `28` (`linux-cpu`),
  Phase `29` (`linux-cuda`), and Phase `30` (`apple-silicon`); link the merged
  report artifacts from the root README after this phase closes.

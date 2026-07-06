# Phase 31: No-Caveat Product Aggregation

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-30-apple-silicon-product-lane.md](phase-30-apple-silicon-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Merge the three committed per-lane attestations by `rowId` on
> `linux-cpu` into one no-caveat product report card and flip the governed docs
> from reopened to closed only when every Phase `19`–`34` sprint is Done.

## Phase State

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). The prior
2026-07-05 aggregation consumed three **withdrawn** per-lane attestations
(`linux-cpu`/`linux-cuda`/`apple-silicon`, 55 rows each) whose row evidence was
not backed by real training, real inference, or real kernel dispatch. The current
closure is the reclosed Phase `19`–`34` chain: product-row checkpoint manifests
exist for 55 / 55 rows, the row-complete convergence and negative-control gates
pass, and the closure guard now covers the standing realness phases. This phase
remains a `linux-cpu`-only aggregation: it consumes committed real per-lane
fragments and **never re-runs an accelerator** (rule M enforcement scan 3 — no
`-fcuda` / `--apple-silicon` re-runs).

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
completed checkpoints with convergence metrics, demo rendering of the trained
artifact, integration coverage, e2e coverage, and per-lane device evidence.
Every one of the eighteen Exit-Definition items passes against the merged card,
the [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) ledger is
empty, and `jitml docs check` permits the reopened→closed status flip only after
the typed `PhaseStatus` registry reports every Phase `19`–`34` sprint Done. The
final status paragraph in the governed docs names exact dates, the three real
lanes, the aggregated row count, and the report artifacts.

## Sprint 31.1: Attestation Join [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/Report.hs`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `system-components.md`, `../documents/engineering/product_completion_contract.md`

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
- Aggregation uses no accelerator commands: it consumes only committed fragments
  and `--linux-cpu` runs.

### Validation

```bash
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-e2e --test-show-details=direct
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The join closed on the three **withdrawn** per-lane
fragments (55 rows each) whose row evidence was fabricated, so the aggregator's
fail-closed contract is unmet: `src/JitML/Test/Report.hs` accepted fragments that
were not backed by real trained-state deltas, completed-training checkpoints,
verified dataset bytes, or real kernel dispatch. This sprint reopens with the
Phase `19`–`30` chain and re-closes only after those phases recommit honest
per-lane fragments. The closed Exit-Definition obligation is closed by the
negative-control suite (`jitml-negative-controls`, Phase
[`32`](phase-32-external-truth-realness-harness.md)): the join must reject a
fabricated or evidence-empty fragment as a fail-closed error — proven against a
planted fake fragment — rather than merging it into a passing card. Aggregation
stays `linux-cpu`-only and re-runs no accelerator.

```bash
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
```

## Sprint 31.2: No-Caveat Closure [✅ Done]

**Status**: Done
**Implementation**: `README.md`, `DEVELOPMENT_PLAN/README.md`, `src/JitML/Lint/Docs.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`

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
- All eighteen [README.md → Exit Definition](../README.md#exit-definition) items
  pass against the merged report card, and
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
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-unit --test-show-details=direct
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The reopened→closed flip was permitted on a merged report
card backed by fabricated evidence, and the typed `PhaseStatus` registry reported
every Phase `19`–`31` sprint Done while the underlying rows were not real. The
2026-07-06 reclosure extends the guard through Phases
[`32`](phase-32-external-truth-realness-harness.md)–[`34`](phase-34-plan-truth-governance.md).
The closed obligations close when: the closure gate consumes the per-model
convergence suite (`jitml-model-convergence`, Phase
[`33`](phase-33-per-model-convergence-and-inference-tests.md)) so every product
row proves real convergence and inference before the flip; the negative-control
suite (`jitml-negative-controls`, Phase
[`32`](phase-32-external-truth-realness-harness.md)) rejects a fabricated
fragment; and the plan-truth governance gate (Phase
[`34`](phase-34-plan-truth-governance.md)) refuses any status flip whose registry
entry is not backed by a passing negative-control and per-model run. Aggregation
stays `linux-cpu`-only — it consumes committed real per-lane fragments and never
re-runs an accelerator.

```bash
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/product_completion_contract.md` — record the final
  merged-evidence closure state and the Phase `19`–`34` validation boundary.
- `documents/engineering/unit_testing_policy.md` — ownership of the attestation
  join and the no-caveat closure gate tests.

**Product docs to create/update:**
- `README.md` — the final no-caveat product status paragraph with dates, lanes,
  row count, and report artifacts.

**Cross-references to add:**
- Consumes the committed per-lane attestations from Phase `28` (`linux-cpu`),
  Phase `29` (`linux-cuda`), and Phase `30` (`apple-silicon`); link the merged
  report artifacts from the root README after this phase closes.

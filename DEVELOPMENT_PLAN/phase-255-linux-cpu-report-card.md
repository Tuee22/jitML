# Phase 255: linux-cpu Report Card

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: linux-cpu Report Card. Single-session phase migrated from legacy Sprint 28.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 255.1: linux-cpu Report Card [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/Report.hs`, `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`
**Docs to update**: `system-components.md`, `README.md`

### Objective

The `linux-cpu` report card is a per-row evidence table that fails on any missing
cell, and the committed attestation reflects a real, row-complete `linux-cpu`
run.

### Deliverables

- `src/JitML/Test/Report.hs` renders one row per `ProductRow` with the columns
  `Catalog` (generated matrix parity), `Integration` (real learned-state-changed
  test), `E2E` (live per-row Playwright test), `Negative` (fail-closed cases),
  and `Lane` (`linux-cpu` validated), and **fails on any missing cell**.
- The report distinguishes an explicitly non-product row from a missing-evidence
  row so a black-box/non-ANN row is never silently counted as complete.
- `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md` is committed only
  after the phase validation passes, and it carries dated, row-keyed evidence for
  the full matrix.

### Validation

```bash
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The report card's per-row cells attest **presence and green
exit codes** (a row has an integration id, an e2e id, a negative case, a
`linux-cpu` lane) rather than **measured** outcomes: the `Integration` cell is
backed by an artifact-read, the `E2E` cell by a stdout-prefix live cell, and the
RL `median_final_reward` by the expert-controller heuristic. A **55 / 55** green
card therefore does not certify learning or inference. The report card must fail
any row whose integration/e2e evidence is not a measured training/inference
outcome.

Closed by: the per-row **measured** convergence + inference-performance evidence
the card must consume is produced by new
[Phase 33](README.md#legacy-to-new-phase-map)
(`jitml-model-convergence`), and the standing negative-control that the card's
gate must not pass a faked cell is the
[Phase 32](README.md#legacy-to-new-phase-map) `jitml-negative-controls`
suite. The committed `linux-cpu` attestation is re-issued only after the card is
backed by measured per-row evidence and both suites are green on `linux-cpu`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

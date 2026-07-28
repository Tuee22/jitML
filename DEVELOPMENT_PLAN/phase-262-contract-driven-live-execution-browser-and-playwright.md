# Phase 262: Contract-Driven Live Execution - Browser and Playwright

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Browser and Playwright. Single-session phase migrated from legacy Sprint 28.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked**. Blocked by Phase 261 (Sprint 261.1).

## Sprint 262.1: Contract-Driven Live Execution - Browser and Playwright [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `playwright/jitml-demo.spec.ts`, `src/JitML/Test/Report.hs`
**Blocked by**: Sprint `261.1`
**Docs to update**: `../documents/engineering/purescript_frontend.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

The live Playwright suite consumes the completed row artifact and measured result
published by each scenario and renders explicit `Passed`, `Failed`, and `NotRun`
cells bound to the same `rowId` and `PlanId`, so no stdout-prefix or presence
check stands in for a measured browser outcome.

### Deliverables

- Make Playwright assertions consume the completed row artifact and measured
  result published by that scenario.
- Render `Passed`, `Failed`, and `NotRun` cells explicitly and fail the row card
  on missing or mismatched evidence, keyed to the same `rowId`/`PlanId` as the
  integration journal.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Blocked until Sprint `261.1` lands the scenario journal the browser cells read.
- Migrate all Playwright assertions and report cell projections to the completed
  row artifact and measured result.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

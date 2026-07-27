# Phase 256: Browser Fail-Closed

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Browser Fail-Closed. Single-session phase migrated from legacy Sprint 27.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 256.1: Browser Fail-Closed [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Web/Server.hs`, `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The browser never substitutes a fake response when a trained artifact is missing.
A product row with no inference-eligible checkpoint returns
`503 checkpoint-required`, and no product row is ever served from a
`*-demo-weights` artifact.

### Deliverables

- The server returns `503 checkpoint-required` for a product row that has no
  inference-eligible artifact, and the panel renders the fail-closed state.
- E2E covers missing artifact, untrained artifact, partial checkpoint, missing
  cluster, and unsupported substrate states.
- A unit guard and a live Playwright guard prove the browser can never serve a
  `*-demo-weights` artifact for a product row.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml lint purescript
docker compose run --rm jitml jitml check-code
```

Validation passed on 2026-07-03 for `jitml-e2e --linux-cpu` (24 / 24),
`jitml-unit --linux-cpu` (277 / 277), `jitml lint purescript`, and
`jitml check-code`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

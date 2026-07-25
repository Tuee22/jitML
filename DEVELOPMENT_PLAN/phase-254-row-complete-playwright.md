# Phase 254: Row-Complete Playwright

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Row-Complete Playwright. Single-session phase migrated from legacy Sprint 28.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 254.1: Row-Complete Playwright [✅ Done]

**Status**: Done
**Implementation**: `playwright/jitml-demo.spec.ts`, `src/JitML/Test/LivePlan.hs`, `src/JitML/App.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

The live demo has one Playwright test per product row, generated from the same
generated registry the integration matrix uses, and each test renders the row's
trained artifact against a live edge with fail-closed negative coverage.

### Deliverables

- `playwright/jitml-demo.spec.ts` loads the product rows from the generated
  contract registry and generates one test per row, titled by the row's
  `prowE2eTest` id, with family-specific renderer assertions (supervised
  prediction panel, RL rollout/return panel, AlphaZero board/policy panel,
  tuning trial-table panel).
- Each generated test asserts fail-closed negatives: missing artifact, untrained
  checkpoint, partial/failed-provenance checkpoint, missing cluster, and
  unsupported substrate each render the fail-closed state instead of a stale or
  synthetic panel.
- `src/JitML/Test/LivePlan.hs` exposes a substrate-parametrized `LivePlan` and
  `src/JitML/App.hs` wires the live Playwright run into
  `jitml test jitml-e2e --live --linux-cpu`, launching or selecting the live
  cluster and binding the run to `linux-cpu`.
- A fake browser-runtime route test remains a structural test only and cannot
  satisfy a row's `e2eTest` evidence.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The obligation — one live e2e test per row that drives the
row's real trained artifact through live per-row inference — is unmet in
substance: the live `runLiveWorkflowMatrixCell` cells assert **stdout prefixes**
(command-shape and presence strings), not the row's measured inference outcome,
so a well-formed log line passes a cell whose model learned nothing. The suite
must drive live per-row inference on the trained artifact and assert a measured
value, not a prefix.

Closed by: live per-row inference-performance measurement is owned by new
[Phase 33](README.md#legacy-to-new-phase-map)
(`jitml-model-convergence`, inference-performance floor); the standing guard that
rejects a stdout-prefix cell as passing evidence is the
[Phase 32](README.md#legacy-to-new-phase-map) `jitml-negative-controls`
suite. This sprint returned to Done after each live cell asserts a measured
inference outcome and both suites are green on `linux-cpu`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

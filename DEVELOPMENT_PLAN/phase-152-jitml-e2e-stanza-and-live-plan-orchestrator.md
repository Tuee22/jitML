# Phase 152: `jitml-e2e` Stanza and Live-Plan Orchestrator

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: jitml-e2e Stanza and Live-Plan Orchestrator. Single-session phase migrated from legacy Sprint 12.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 152.1: `jitml-e2e` Stanza and Live-Plan Orchestrator [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live phased
Helm + Pulsar rollout against a real Kind cluster, live Playwright
against the edge route, and full live teardown leak-detection migrated
to Phase `15` Sprints `15.1` and `15.14`.
**Implementation**: `src/JitML/Test/LivePlan.hs`,
`test/e2e/`,
`jitml.cabal` (the `jitml-e2e` stanza)
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Use `jitml-e2e` for the e2e scaffold and the typed live-plan
orchestration. The current body checks route, bucket, publication,
contract, report-card, and typed live-plan surfaces; the live body
brings up an ephemeral Kind stack via `jitml bootstrap`, runs the demo
cohorts against the real Envoy listener with Playwright, and tears the
stack down deterministically via `jitml cluster down`. This is the
doctrine's Ephemeral-Cluster Infrastructure test category. The live body
is an explicit opt-in gate, not part of default `cabal test all`,
because it creates Kind clusters, builds Helm dependencies, mutates
external container/runtime state, and validates teardown.

### Deliverables

- `JitML.Test.LivePlan.liveE2EPlan` declares the typed live-plan
  sequence — `helm dependency build chart` → `jitml bootstrap`
  (ephemeral Kind + phased Helm rollout) → substrate-bound
  pinned `mcr.microsoft.com/playwright:v1.49.1-noble` browser-image Playwright run →
  `jitml cluster down` — through typed `Subprocess` values, and
  `livePhasedClusterPlan` records the bootstrap rollout's typed
  subprocess list for the explicit live driver.
- `test/e2e/Main.hs` currently validates the route registry, bucket registry,
  `chart/values.yaml` MinIO bucket coverage, publication defaults, browser
  contract endpoint count, demo deployment command, demo HTTP route table
  coverage for generated stream endpoints, one-shot demo HTTP server,
  report-card rendering, typed report-card defaults, typed live plan rendering,
  and, when the `kind` binary is present and the active Docker context answers
  `docker info`, the absence of leaked `jitml-e2e-*` Kind clusters. When Docker
  is unreachable, the no-leak query fails closed instead of passing vacuously.
- The target live path runs typed `helm dependency build chart` before apply and
  records whether `Chart.lock` is part of the reproducible dependency surface.
- Default `cabal test jitml-e2e` remains local. The full live path is a separate
  explicit orchestration command, not a process-environment gate.
- Playwright invocation is represented in the typed live plan and is validated
  live against the demo edge route (Phase `15` Sprint `15.14`, 7/7 panel
  matrix).

### Validation

1. `cabal test jitml-e2e` exits `0` for the scaffold body.
2. `cabal test jitml-e2e` verifies the rendered live plan contains the
   Helm dependency-build and Playwright steps.
3. Transferred live validation: the explicit live e2e orchestration runs the full
   sequence: `helm dependency build chart`
   → `jitml bootstrap` (ephemeral Kind) → demo cohorts reach Ready behind the
   real Envoy listener →
   pinned `mcr.microsoft.com/playwright:v1.49.1-noble` browser-image Playwright run
   against every canonical panel → `jitml cluster down`. Teardown leaves no
   orphan Kind clusters, Harbor projects, PVs, or Docker
   volumes.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. Live phased Helm
  + Pulsar topic creation rollout against a real Kind cluster is owned
  by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.1`; live Playwright against the edge route and full live
  teardown leak-detection are owned by Phase `15` Sprint `15.14`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

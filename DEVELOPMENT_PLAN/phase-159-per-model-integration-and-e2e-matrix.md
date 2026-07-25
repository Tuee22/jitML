# Phase 159: Per-Model Integration and E2E Matrix

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Per-Model Integration and E2E Matrix. Single-session phase migrated from legacy Sprint 12.15 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 159.1: Per-Model Integration and E2E Matrix [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/WorkflowMatrix.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`,
`playwright/jitml-demo.spec.ts`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/purescript_frontend.md`, `system-components.md`

### Objective

Replace workflow-category coverage with per-model coverage. Every supported
SL, RL, and AlphaZero row must have integration/e2e proof that its fixed budget
can complete, its convergence statistics enter the checkpoint, and inference is
rejected before completion.

### Deliverables

- Expand `WorkflowMatrix` from coarse workflow cells to model cells for all 11
  SL rows, all RL algorithm rows, HER, and every AlphaZero game.
- Remove hardcoded transport-smoke checkpoints from live inference proof and
  replace them with trained-artifact fixtures produced by the workflow matrix.
- Add infer-before-complete and untrained-demo-checkpoint negative tests.
- Ensure `jitml-e2e` local fake-runtime tests are clearly structural only and
  cannot satisfy the live no-caveat model matrix.

### Validation

- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23**.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed all non-live integration cases, including the partial-checkpoint
  negative loader test. The live group failed fast because no bootstrapped
  cluster publication exists at `.build/runtime/cluster-publication.json`.
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  later passed **53** non-live integration cases after adding a
  checkpoint-browser selector negative test that omits incomplete manifests from
  the `CheckpointList` summary. The **19** live cases still fail fast without a
  bootstrapped cluster publication.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against the bootstrapped cluster. The live matrix now
  observes the new RL completion metric/checkpoint events through a single
  Pulsar subscription pass without losing completion frames while collecting
  episode frames.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- Rule-M deterministic scans over `DEVELOPMENT_PLAN/phase-*.md` report:
  **0** backward `Blocked by` edges, **0** dual-accelerator validation gates,
  and **0** accelerator reruns in aggregation-phase validation.
- `docker compose run --rm jitml cabal test jitml-daemon-lifecycle --test-show-details=direct`
  passed **32 / 32** after the synthetic daemon inference fixture gained a
  completed-training manifest.
- `docker compose run --rm jitml jitml test all --live --linux-cpu` passed the
  aggregate lane with **8 / 8** stanzas green, including `jitml-integration`
  **72 / 72**, `jitml-e2e` **23 / 23**, `jitml-daemon-lifecycle` **32 / 32**,
  and `jitml-backends` **23 / 23**.
- Live Playwright passed **15 / 15** against the rebuilt `linux-cpu` edge from a
  temporary repo copy with Playwright pinned to `@playwright/test` `1.49.1`.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

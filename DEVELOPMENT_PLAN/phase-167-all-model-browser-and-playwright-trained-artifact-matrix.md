# Phase 167: All-Model Browser and Playwright Trained-Artifact Matrix

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: All-Model Browser and Playwright Trained-Artifact Matrix. Single-session phase migrated from legacy Sprint 14.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 167.1: All-Model Browser and Playwright Trained-Artifact Matrix [✅ Done]

**Status**: Done
**Implementation**: `playwright/jitml-demo.spec.ts`, `test/e2e/Main.hs`,
`web/src/Panels/*.purs`, `src/JitML/Web/Server.hs`,
`src/JitML/Test/WorkflowMatrix.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`system-components.md`

### Objective

Playwright proves every supported model through the real browser, not merely
that representative panels and routes respond. The browser must reject
untrained artifacts, select trained artifacts, show convergence statistics, and
drive the model's natural interaction.

### Deliverables

- Add Playwright cells for every SL model row, every RL algorithm row, and every
  AlphaZero game.
- Assert the displayed checkpoint includes completed budget, convergence
  metric, substrate, TensorBoard link, and readiness status.
- Drive model-appropriate interactions: drawing for MNIST, upload for image
  classifiers, tensor/regression inputs for tabular/generic models, trajectory
  replay for RL, and legal board moves for AlphaZero games.
- Assert that partial, random, hardcoded, smoke, and fake-runtime checkpoints do
  not appear as selectable inference artifacts.

### Validation

- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- live Playwright against a bootstrapped `linux-cpu` edge
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23** with the regenerated trained-artifact contract present.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal run jitml -- lint purescript` passed
  (`jitml lint purescript: ok`).
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), leaving a live edge publication at `127.0.0.1:9091`.
- `docker compose build jitml` passed after the Phase `14.4` browser and
  generated-contract changes, including embedded `check-code: ok` and a clean
  PureScript bundle build.
- The rebuilt `jitml:local` / `jitml-demo:local` image was loaded into the
  `jitml-linux-cpu` Kind cluster, `deployment/jitml-service` and
  `deployment/jitml-demo` rolled out successfully, and
  `jitml internal seed-demo-checkpoints` seeded all eight completed demo
  checkpoints into live MinIO.
- Live Playwright passed **15 / 15** against `http://127.0.0.1:9091`. The
  checkpoint browse test asserts completed-budget, convergence, TensorBoard
  link, eligibility, absence of partial/untrained/smoke/fake artifacts, and
  every generated `WorkflowMatrix.allModelCells` browser row.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 144: All-Model Trained-Artifact UI and Admin Navigation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: All-Model Trained-Artifact UI and Admin Navigation. Single-session phase migrated from legacy Sprint 11.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 144.1: All-Model Trained-Artifact UI and Admin Navigation [✅ Done]

**Status**: Done
**Implementation**: `web/src/PanelRegistry.purs`,
`web/src/Panels/*.purs`, `web/src/Generated/Contracts.purs`,
`web/src/Generated/AdminPortals.purs`, `src/JitML/Web/Contracts.hs`,
`src/JitML/Web/Server.hs`, `src/JitML/Routes.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

The browser exposes only trained, inference-eligible artifacts and makes the
model's completed-budget convergence statistics visible. Admin consoles are
shown through a generated, consistent portal directory with top-level routed
links, not iframes.

### Deliverables

- Add checkpoint selectors that list only Store-admitted completed checkpoint
  records for inference/game/RL panels.
- Render budget counters, convergence metric values, pass/fail status, device,
  and TensorBoard links for the selected artifact.
- Provide model-appropriate interactions for every SL row, every RL algorithm
  row, and every AlphaZero game.
- Keep admin portals generated from `src/JitML/Routes.hs` and rendered as
  top-level links for Grafana, Prometheus, TensorBoard, Harbor, MinIO console,
  and Pulsar admin.

### Validation

- `docker compose run --rm jitml jitml lint purescript`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`
- `docker compose run --rm jitml jitml docs check`

### Current Validation State

- `docker compose run --rm jitml cabal run jitml -- lint purescript` passed.
- `docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`
  passed **23 / 23**.
- `docker compose run --rm jitml cabal run jitml -- test jitml-e2e --linux-cpu`
  passed through the project wrapper with **23 / 23** tests.
- `docker compose run --rm jitml cabal run jitml -- docs generate` refreshed
  `web/src/Generated/Contracts.purs` from `src/JitML/Web/Contracts.hs`.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`).
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`).
- `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **53** non-live cases after adding the checkpoint-browser selector
  negative test: incomplete manifests are omitted from the `CheckpointList`
  summary while completed inference-eligible manifests remain visible. The
  **19** live cases still fail fast without `.build/runtime/cluster-publication.json`.
- `./bootstrap/linux-cpu.sh up` completed the live `linux-cpu` rollout
  (**111** steps), and
  `docker compose run --rm jitml cabal test jitml-integration --test-show-details=direct`
  passed **72 / 72** against the bootstrapped cluster. This revalidates the
  daemon/browser-adjacent checkpoint-list and live workflow foundations, but not
  the all-model Playwright selector/product matrix.
- `docker compose run --rm jitml cabal run jitml -- lint purescript` passed
  after the trained-artifact selector rendered eligibility, completed budget,
  convergence metrics, TensorBoard links, and the generated all-model matrix.
- Live Playwright passed **15 / 15** against the rebuilt `linux-cpu` edge. The
  checkpoint browse test asserts eligible artifacts only, completed-budget and
  convergence text, TensorBoard anchors, absence of partial/untrained/smoke/fake
  artifacts, and every generated model-matrix row.
- `docker compose build jitml` passed, including the embedded PureScript bundle
  build and `check-code: ok`.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

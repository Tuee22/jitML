# Phase 137: Interactive Endpoint Contract Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Interactive Endpoint Contract Surface. Single-session phase migrated from legacy Sprint 11.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 137.1: Interactive Endpoint Contract Surface [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The Halogen
dependency + render machinery (slot + state + DOM diff) on each
`Panels.*` module closed on 2026-05-24; the Dockerfile runs the
PureScript build and esbuild bundle step to produce
`web/dist/Main/bundle.js`. `JitML.Web.Server.loadBundleEntry` +
`demoHttpRoutesWithBundle` serve the compiled bundle when present.
`playwright/jitml-demo.spec.ts` historically covered the canonical six-panel
DOM-shape matrix; the current file has expanded. The live `/api/ws` WebSocket proxy migrated to
Phase `15` Sprint `15.13`; live edge-route Playwright migrated to
Phase `15` Sprint `15.14`.
**Implementation**: `src/JitML/Web/Contracts.hs`,
`src/JitML/Web/Bundle.hs`,
`web/spago.yaml`, `web/src/Main.purs`, `web/src/Generated/Contracts.purs`,
`web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs`
**Docs to update**: `documents/engineering/purescript_frontend.md`

### Objective

Land the current endpoint-contract metadata and typed panel/bundle manifest that
the interactive panels consume. The current `jitml-demo` workload is the
Webapp role of the one `jitml` binary; it serves the API index and bundle
routes, publishes browser inference/command requests to the Engine when a live
publication is present, and fails closed without live handlers. Live WebSocket
proxying is validated by the later Webapp closure sprints.

### Deliverables

- `src/JitML/Web/Contracts.hs` declares endpoint metadata for `RunCommand`,
  `InferenceRun`, `UploadImage`, `Connect4Move`, and `MetricsStream`.
- `src/JitML/Web/Bundle.hs` declares the local bundle asset manifest, panel
  surfaces for MNIST inference, image upload, Connect 4, RL trajectory,
  training progress, and hyperparameter sweep rendering, and the demo route
  manifest for the full current Webapp HTTP surface:
  `/`, `/api`, `/api/inference`, `/api/inference/generic`, `/api/images`,
  `/api/checkpoints/compare`, `/api/connect4/move`,
  `/api/runs/{runId}/command`, `/api/ws`, `/api/ws/training`,
  `/api/ws/tune`, and `/api/ws/rl`.
- `web/src/Generated/Contracts.purs` contains the generated local PureScript
  contract output.
- `test/e2e/Main.hs` checks the browser contract endpoint count.
- `src/JitML/Web/Server.hs` exposes HTTP handlers for `/`,
  `/api`, `/api/inference`, `/api/images`, `/api/connect4/move`, and
  `/api/ws`, `/api/ws/training`, and `/api/ws/tune`.
- `web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs` carry the
  typed per-panel request / response payload shapes and the panel
  `mount` entry point; the Haskell `JitML.Web.Bundle.panelSurfaces`
  catalog enumerates all six panel names.
- The live WebSocket proxy bridges `/api/ws*` to real daemon Pulsar event
  topics when the cluster publication is present; plain HTTP stream GETs
  fail closed unless the client performs a WebSocket upgrade.

### Validation

1. `cabal test jitml-e2e` validates the browser contract endpoint
   count, the typed demo route manifest, and the demo HTTP route table
   for generated stream endpoints.
2. `docker compose run --rm jitml jitml lint purescript` validates the
   generated contract file exists.
3. `jitml-unit` verifies the bundle, panel, and demo-route metadata.
4. Transferred live validation: Phase `15` Sprint `15.13`, Phase `17`
   Sprint `17.3`, and Phase `14` validate the live WebSocket proxy, bundle
   serving, and panel request/response round-trips against the routed Webapp.

### Remaining Work

- The Halogen dependency closed on 2026-05-24: `web/spago.yaml`
  declares `halogen`, `halogen-vdom`, `aff`, `web-html`, `arrays`,
  `foldable-traversable`, `maybe`, `tuples`, plus the existing
  `console` / `effect` / `prelude`. Every `web/src/Panels/*.purs`
  module exports a typed Halogen `H.component` with state and DOM
  render plus a `mount :: Effect Unit` that drives `Halogen.Aff` +
  `Halogen.VDom.Driver.runUI`. `web/src/Main.purs` dispatches on the
  `location.hash` and mounts the matching panel (default: MNIST).
  `spago build --output dist` runs in `docker/Dockerfile`; Phase `15`
  adds the esbuild step that emits `web/dist/Main/bundle.js` for the
  demo image.
- The live `/api/ws` WebSocket proxy that bridges the demo server to
  the daemon's metric/event Pulsar topics is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.13`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

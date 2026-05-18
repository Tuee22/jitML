# Phase 11: PureScript Frontend and Demo

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the PureScript frontend surface under `web/`, the
> generated browser contracts from `src/JitML/Web/Contracts.hs`, typed bundle
> and panel/demo-route metadata from `src/JitML/Web/Bundle.hs`, the Playwright
> scaffold, the demo deployment template, and the `jitml-demo` executable shim.
> The target architecture later expands this into Halogen panels, live REST/WS
> handlers, and a compiled browser bundle.

## Phase Status

🔄 **Active**. The phase owns
[Exit Definition](README.md#exit-definition) item 8 (PureScript frontend
under `web/` generated from `src/JitML/Web/Contracts.hs` via
`purescript-bridge`; live MNIST handwriting panel, CIFAR/ImageNet upload
panel, and AlphaZero-vs-human Connect 4 panel exercised end-to-end by
Playwright; `jitml-demo` serves the bundle) and contributes the
PureScript-style half of item 15 (the `jitml-purescript-style` stanza
running `purs format` round-trip and `purescript-spec` smoke tests).
**Met today**: Sprints `11.1` and `11.2` close the minimal PureScript
scaffold and the typed contract renderer that produces
`web/src/Generated/Contracts.purs`. The six canonical panel payload
modules now live under `web/src/Panels/`:
`Panels.{Mnist,Cifar,Connect4,Rl,Training,Tune}` — each carries the
typed request/response payload shape for its endpoint. `web/test/Main.purs`
smokes every panel name + the generated contracts surface.
`playwright/jitml-demo.spec.ts` covers the seven-test canonical panel
matrix. `JitML.Web.Bundle.panelSurfaces` lists all six panel names.
**Unmet today**: Sprint `11.3` still owes the default/non-gated
`purs format` round-trip and `purescript-spec` smoke suite; the
`spago test` and `purs-tidy check` subprocess paths are present behind
`JITML_LIVE_E2E=1`. Sprint `11.4` owes Halogen render wiring and the
live `/api/ws` proxy against real daemon Pulsar topics; Sprint `11.5`
owes building the compiled bundle as part of the demo image and serving
it against real daemon state; Sprint `11.6` owes Playwright against the
live `jitml-demo` edge route rather than inline DOM stubs. Detailed
remaining work lives in each sprint's
`### Remaining Work` block below.

### Current Implementation Scope

The worktree implements a minimal PureScript entrypoint, generated
contract file, typed bundle/panel/demo-route metadata,
`web/package.json` script surface, `web/test/Main.purs`, six
`web/src/Panels/*.purs` payload modules, Playwright spec scaffold,
`jitml-demo` executable shim, and demo deployment template. Halogen
dependency/mount machinery, external `purescript-bridge` package
dependency, checked-in compiled browser bundle output, and live
WebSocket proxying live in the sprints' `### Remaining Work` blocks below.
`jitml-demo` serves the present route/API surface through
`src/JitML/Web/Server.hs`.

## Phase Summary

This phase delivers the browser-side shell: generated browser contracts from
typed Haskell ADTs in `src/JitML/Web/Contracts.hs`, typed bundle/panel/demo-route
metadata in `src/JitML/Web/Bundle.hs`, a PureScript entrypoint under `web/src/`, a
contract smoke test under `web/test/`, a Playwright scaffold under
`playwright/`, and the `jitml-demo` sibling binary that serves the generated
frontend/API surface from the same typed demo metadata. The
PureScript stack is
project-specific; command and build invocations are represented through the
typed `Subprocess` boundary from Phase `1`.

## Sprint 11.1: Minimal PureScript Application Scaffold ✅

**Status**: Done
**Implementation**: `web/package.json`, `web/src/Main.purs`
**Docs to update**: `documents/engineering/purescript_frontend.md`

### Objective

Stand up the minimal PureScript application skeleton and local frontend script
surface.

### Deliverables

- `web/package.json` declares the local frontend script surface.
- `web/src/Main.purs` is the minimal PureScript shell entrypoint.
- The frontend scaffold keeps build and test commands outside the Haskell
  library while the CLI owns command rendering.

### Validation

1. `web/src/Main.purs` remains a valid PureScript entrypoint.
2. The frontend package manifest exposes build/test/format script names for
   the later toolchain runner.

## Sprint 11.2: Browser-Contract ADTs and Local Contract Rendering ✅

**Status**: Done
**Implementation**: `src/JitML/Web/Contracts.hs`,
`web/src/Generated/Contracts.purs`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/code_quality.md`

### Objective

Stand up the browser-contract ADTs in `src/JitML/Web/Contracts.hs` and the
local renderer that produces `web/src/Generated/Contracts.purs`. The external
`purescript-bridge` package is not required for the renderer;
`web/src/Generated/Contracts.purs` is protected by `trackingGeneratedPaths`.

### Deliverables

- `src/JitML/Web/Contracts.hs` enumerates the current endpoint contract:
  `RunCommand`, `InferenceRun`, `UploadImage`, `Connect4Move`,
  `MetricsStream`, `TrainingStream`, and `TuneStream`.
- `src/JitML/Web/Contracts.hs` renders `web/src/Generated/Contracts.purs`
  through the local `renderPureScriptContracts` helper.
- `contractGeneratorName` identifies the local bridge-compatible renderer used
  by the current contract surface.
- `web/src/Generated/Contracts.purs` is an active `trackingGeneratedPaths`
  entry; hand edits fail `jitml docs check`.

### Validation

1. The renderer produces the same contract text byte-for-byte across runs.
2. `jitml-purescript-style` verifies the generated contract file exists and
   names the expected endpoint surface.

## Sprint 11.3: `jitml-purescript-style` Generated-Contract Smoke Stanza 🔄

**Status**: Active
**Implementation**: `web/test/Main.purs`, `test/purescript-style/`,
`jitml.cabal` (the `jitml-purescript-style` stanza)
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-purescript-style` as the generated-contract,
whitespace, and panel-contract smoke stanza. The target PureScript
`purs format` round-trip and `purescript-spec` panel tests remain future work.

### Deliverables

- `web/test/Main.purs` is present as a minimal PureScript test entrypoint.
- `test/purescript-style/Main.hs` verifies
  `web/src/Generated/Contracts.purs` exists and names the expected endpoint
  surface.
- The stanza also checks `renderPureScriptContracts` emits the PureScript
  module header.
- The stanza checks the current PureScript files for tab-free, final-newline
  source shape and verifies each typed panel endpoint is covered by the
  generated contract endpoint list.
- It invokes `spago test` and `purs-tidy check` through the typed
  `Subprocess` boundary when `JITML_LIVE_E2E=1` is set.
- It does not currently run a default/non-gated `purs format`
  round-trip or `purescript-spec` smoke suite.

### Validation

1. `cabal test jitml-purescript-style` exits `0` for the smoke body.
2. Missing generated-contract output fails the stanza.
3. PureScript whitespace and panel-contract validation run in the stanza.
4. Live-gated validation: with `JITML_LIVE_E2E=1`, the stanza invokes
   `spago test` and `purs-tidy check` through typed `Subprocess` values.
5. Target validation: the default style path adds a `purs format`
   round-trip byte-equality check and a `purescript-spec` smoke suite
   that touches every typed panel contract.

### Remaining Work

- Add the default/non-gated `purs format` round-trip byte-equality
  check and `purescript-spec` smoke suite once the frontend toolchain is
  installed as part of the normal developer/test environment.
- The smoke `web/test/Main.purs` exists and exercises all six typed
  panel names + the generated contracts surface.
- The stanza invokes `./node_modules/.bin/spago test` through the
  typed `Subprocess` boundary inside the stanza body when
  `JITML_LIVE_E2E=1` is set; validated locally (live build + test
  + `mnist-live-inference` substring assertion against the stdout).
- The stanza invokes `./node_modules/.bin/purs-tidy check
  'src/**/*.purs'` through the typed `Subprocess` boundary inside
  the stanza body when `JITML_LIVE_E2E=1` is set; validated locally
  (purs-tidy reports `All files are formatted` against
  `web/src/Main.purs`, `web/src/Generated/Contracts.purs`, and the
  six `web/src/Panels/*.purs` modules). The Haskell-side
  `renderPureScriptContracts` now produces purs-tidy-clean output so
  the generated contract file no longer needs an external format
  step.

## Sprint 11.4: Interactive Endpoint Contract Surface 🔄

**Status**: Active
**Implementation**: `src/JitML/Web/Contracts.hs`,
`src/JitML/Web/Bundle.hs`,
`web/src/Main.purs`, `web/src/Generated/Contracts.purs`
**Docs to update**: `documents/engineering/purescript_frontend.md`

### Objective

Land the current endpoint-contract metadata and typed panel/bundle manifest that
the future interactive panels will consume. The current `jitml-demo` server
serves deterministic local REST-style responses for the API index, inference,
image upload, Connect 4 move, and metrics stream routes; live WebSocket proxying
remains target runtime validation.

### Deliverables

- `src/JitML/Web/Contracts.hs` declares endpoint metadata for `RunCommand`,
  `InferenceRun`, `UploadImage`, `Connect4Move`, and `MetricsStream`.
- `src/JitML/Web/Bundle.hs` declares the local bundle asset manifest, panel
  surfaces for MNIST inference, image upload, Connect 4, RL trajectory,
  training progress, and hyperparameter sweep rendering, and the demo route
  manifest for `/`, `/api`, and `/api/ws`.
- `web/src/Generated/Contracts.purs` contains the generated local PureScript
  contract output.
- `test/e2e/Main.hs` checks the browser contract endpoint count.
- `src/JitML/Web/Server.hs` exposes HTTP handlers for `/`,
  `/api`, `/api/inference`, `/api/images`, `/api/connect4/move`, and
  `/api/ws`.
- `web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs` carry the
  typed per-panel request / response payload shapes and the panel
  `mount` entry point; the Haskell `JitML.Web.Bundle.panelSurfaces`
  catalog enumerates all six panel names.
- The live WebSocket proxy that bridges `/api/ws` to real daemon Pulsar
  topics remains target runtime validation.

### Validation

1. `cabal test jitml-e2e` validates the browser contract endpoint
   count.
2. `cabal test jitml-purescript-style` validates the generated contract
   file exists.
3. `jitml-unit` verifies the bundle, panel, and demo-route metadata.
4. Live validation (target): each Halogen panel module renders against
   live daemon state, the `/api/ws` WebSocket proxy streams real metric
   updates from the daemon, and panel uploads / inferences round-trip
   through the daemon's real handlers.

### Remaining Work

- All six `web/src/Panels/*.purs` modules are checked in with typed
  request/response or stream payload shapes and an Effectful `mount`
  placeholder. The pending work is adding the Halogen dependency and
  render machinery (slot + state + DOM diff), then wiring the normal
  `spago build --output web/dist` path so the demo image gets a compiled
  browser bundle rather than relying on a locally present `web/dist/`
  file.
- Implement the live `/api/ws` WebSocket proxy that bridges the demo
  server to the daemon's metric/event Pulsar topics. The typed
  panel frame shapes (`Panels.Rl.RlStreamFrame`,
  `Panels.Training.TrainingFrame`, `Panels.Tune.TuneTrialFrame`)
  describe the on-wire payloads.

## Sprint 11.5: `jitml-demo` Executable Shim 🔄

**Status**: Active
**Implementation**: `app/Demo.hs`, `src/JitML/App.hs`,
`chart/templates/deployment-jitml-demo.yaml`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Stand up the `jitml-demo` sibling executable shim, typed demo route manifest,
HTTP server, and chart deployment surface.

### Deliverables

- `app/Demo.hs` is a six-line shim into `App.demoMain`.
- `src/JitML/App.hs` owns `demoMain`, which prints the typed `demoStatusLine`
  from `src/JitML/Web/Bundle.hs` and then starts `WebServer.serveDemo`.
- `src/JitML/Web/Server.hs` serves the frontend/API route
  surface.
- `src/JitML/Web/Bundle.hs` declares `demoRoutes` for `/`, `/api`, and
  `/api/ws`.
- The `Deployment/jitml-demo` template is populated with the demo image,
  `jitml-demo` command, and `PORT=80`.
- HTTPRoutes for `/`, `/api`, `/api/ws` (Sprint `3.4`) point at
  `jitml-demo:80`.

### Validation

1. Running `jitml-demo` prints the generated-frontend status line and
   starts the HTTP listener.
2. The `Deployment/jitml-demo` chart template names the demo image and
   exposes container port `80`.
3. `jitml-e2e` verifies the demo route manifest covers `/`, `/api`, and
   `/api/ws`, that the deployment starts `jitml-demo`, and that a
   one-shot demo HTTP server serves the API index.
4. Live validation (target): `jitml-demo` serves the compiled Halogen
   bundle from `web/dist/`, the live `/api/ws` proxy is connected to the
   daemon's metric/event Pulsar topics, and each panel renders against
   real daemon state.

### Remaining Work

- Build the compiled Halogen bundle (`spago build --output web/dist/`)
  as part of the demo image build.
- The demo server now serves the compiled Halogen bundle from
  `web/dist/Main/index.js` when present:
  `JitML.Web.Server.loadBundleEntry` reads the file from the
  canonical path (`bundleEntryPath`), and
  `demoHttpRoutesWithBundle :: Maybe Text -> [HttpRoute]` appends a
  `/bundle/main.js` route serving the JS bytes whenever the bundle
  is on disk; without it, the routes fall back to the placeholder
  shim. Validated by `jitml-e2e`: when the bundle is present, the
  route table is one entry larger than `demoHttpRoutes`; when
  absent, it matches the placeholder length. The `spago`-driven
  bundle build itself stays gated on the `web/node_modules` install
  step.
- Implement the live `/api/ws` proxy that bridges browser WebSocket
  clients to Pulsar event topics.

## Sprint 11.6: Playwright E2E Suite 🔄

**Status**: Active
**Implementation**: `playwright/jitml-demo.spec.ts`,
`infra/pulumi/`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Land the Playwright scaffold for the future interactive panel suite.

### Deliverables

- `playwright/jitml-demo.spec.ts` exists as the current E2E scaffold.
- The target suite covers MNIST, CIFAR/ImageNet, Connect 4, RL trajectory,
  training, and tuning panel flows once those panels and the HTTP server land.
- The current `jitml-e2e` stanza invokes Playwright through the typed
  `Subprocess` boundary only when `JITML_LIVE_E2E=1` is set.
- Playwright execution stays out of the default local Cabal matrix until the
  panels consume fixture-backed or live-backed state through `jitml-demo`;
  static scaffold assertions remain covered by the current Haskell e2e and
  PureScript-style stanzas.

### Validation

1. `playwright/jitml-demo.spec.ts` remains present for the E2E runner.
2. `jitml-e2e` validates route, bucket, publication, contract, and
   report-card surfaces.
3. Live validation (target): under `JITML_LIVE_E2E=1`, `jitml-e2e`
   invokes Playwright against the live `jitml-demo` HTTP listener and
   each canonical panel (MNIST, CIFAR/ImageNet, Connect 4, RL
   trajectory, training, tuning) passes its end-to-end flow against
   real daemon state.

### Remaining Work

- `playwright/jitml-demo.spec.ts` now covers the full canonical panel
  matrix: the smoke shell test plus six per-panel DOM-shape tests
  (`mnist-live-inference`, `cifar-imagenet-upload`,
  `connect4-human-vs-alphazero`, `rl-trajectory`,
  `training-progress`, `hyperparameter-sweep`). The `jitml-e2e`
  stanza invokes `npx playwright test` through the typed `Subprocess`
  boundary when `JITML_LIVE_E2E=1` is set; the checked-in spec still
  drives inline `page.setContent` DOM stubs rather than the live edge
  route.
- The pending wiring is feeding Playwright the live edge port from
  `cluster-publication.json` so the panels load against
  `jitml-demo` rather than inline `page.setContent` stubs (gated on
  Sprint 11.5 compiled bundle).
- Playwright stays out of the default `cabal test all` matrix (the
  live invocation is env-gated).

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (target frontend tool invocations flow through `Subprocess`; current checked-in bodies are local smoke tests)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 11.2 — generated PureScript contracts)
- [../HASKELL_CLI_TOOL.md → Project Structure](../HASKELL_CLI_TOOL.md) (Sprint 11.5 — six-line `app/Demo.hs` shim)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (target demo server uses the full `Env`; current `demoMain` reads `PORT`, prints `demoStatusLine`, and starts the local HTTP server)
- [../HASKELL_CLI_TOOL.md → Test Categories](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — local project-specific smoke stanza via `jitml-purescript-style`; Sprint 11.6 — Playwright scaffold belongs to the target Pulumi-Orchestrated Infrastructure category via `jitml-e2e`)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — project-specific stanza under §Test Organization → project-specific stanzas)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/purescript_frontend.md` — current minimal PureScript
  shell, local contract renderer, bundle/panel/demo-route metadata, demo shim,
  and Playwright scaffold; target Halogen, live REST / WS, compiled bundle, and
  live panel surfaces.
- `documents/engineering/code_quality.md` — note that
  `web/src/Generated/Contracts.purs` is an active generated path.
- `documents/engineering/daemon_architecture.md` — `jitml-demo` server
  shape and its place in the deployment.
- `documents/engineering/unit_testing_policy.md` — Playwright belongs to
  the doctrine's target Pulumi-Orchestrated Infrastructure test category and
  is scaffolded for `jitml-e2e`; the current PureScript generated-contract
  smoke checks are owned by the `jitml-purescript-style` stanza (Sprint
  `11.3`).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Frontend Components` rows remain aligned with
  `src/JitML/Web/Contracts.hs`, `web/`, and `playwright/`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

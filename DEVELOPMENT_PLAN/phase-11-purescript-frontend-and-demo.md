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
`web/src/Generated/Contracts.purs`. **Unmet today**: Sprint `11.3` owes
real `purs format` / `purescript-spec` invocations from the stanza;
Sprint `11.4` owes the Halogen panel modules and live WebSocket proxy;
Sprint `11.5` owes a compiled bundle served from `jitml-demo` against
real daemon state; Sprint `11.6` owes Playwright actually running against
the live demo. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

### Current Implementation Scope

The worktree implements a minimal PureScript entrypoint, generated
contract file, typed bundle/panel/demo-route metadata,
`web/package.json` script surface, `web/test/Main.purs`, Playwright spec
scaffold, `jitml-demo` executable shim, and demo deployment template.
Halogen dependency, external `purescript-bridge` package dependency,
compiled browser bundle output, full panel modules, and live WebSocket
proxying live in the sprints' `### Remaining Work` blocks below.
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
`purescript-bridge` package is not required for the current local renderer;
`web/src/Generated/Contracts.purs` is protected by `trackingGeneratedPaths`.

### Deliverables

- `src/JitML/Web/Contracts.hs` enumerates the current endpoint contract:
  `RunCommand`, `InferenceRun`, `UploadImage`, `Connect4Move`, and
  `MetricsStream`.
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

Keep `jitml-purescript-style` as the current local generated-contract,
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
- It does not currently invoke `spago test`, `purs format`, `purs-tidy`, or
  `purescript-spec`.

### Validation

1. `cabal test jitml-purescript-style` exits `0` for the smoke body.
2. Missing generated-contract output fails the stanza.
3. PureScript whitespace and panel-contract validation run in the stanza.
4. Live validation (target): the stanza invokes `purs format` (or
   `purs-tidy`) for a round-trip byte-equality check across `web/src/`,
   runs `spago test`, and executes a `purescript-spec` smoke suite that
   touches every typed panel contract.

### Remaining Work

- Wire `purs format` (or `purs-tidy`) round-trip through the typed
  `Subprocess` boundary from inside the stanza.
- Wire `spago test` invocation through the typed `Subprocess` boundary.
- Add a `purescript-spec` smoke suite under `web/test/` that exercises
  every typed panel contract.

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
  surfaces for MNIST inference, image upload, Connect 4, and RL trajectory
  rendering, and the demo route manifest for `/`, `/api`, and `/api/ws`.
- `web/src/Generated/Contracts.purs` contains the generated local PureScript
  contract output.
- `test/e2e/Main.hs` checks the browser contract endpoint count.
- `src/JitML/Web/Server.hs` exposes current local HTTP handlers for `/`,
  `/api`, `/api/inference`, `/api/images`, `/api/connect4/move`, and
  `/api/ws`.
- `Mnist.purs`, `Cifar.purs`, `Connect4.purs`, `Rl.purs`, `Training.purs`,
  `Tune.purs`, and live WebSocket proxy handlers remain target runtime
  validation.

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

- Implement `web/src/Panels/Mnist.purs` (live inference round-trip
  against the daemon's MNIST checkpoint).
- Implement `web/src/Panels/Cifar.purs` (upload-then-inference round-trip
  for CIFAR/ImageNet).
- Implement `web/src/Panels/Connect4.purs` (AlphaZero-vs-human play with
  live MCTS move suggestions from the daemon).
- Implement `web/src/Panels/{Rl,Training,Tune}.purs` (live metric
  streams).
- Implement the live `/api/ws` WebSocket proxy that bridges the demo
  server to the daemon's metric/event Pulsar topics.

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
- `src/JitML/Web/Server.hs` serves the current local frontend/API route
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
- Serve `web/dist/` from `jitml-demo` instead of the placeholder shim.
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
- The current `jitml-e2e` stanza does not invoke Playwright.
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

- Grow `playwright/jitml-demo.spec.ts` to cover the full canonical panel
  matrix.
- Wire `jitml-e2e` Sprint `12.8` to invoke Playwright through the typed
  `Subprocess` boundary when `JITML_LIVE_E2E=1` is set.
- Confirm Playwright stays out of the default `cabal test all` matrix
  until the panels are live-backed.

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

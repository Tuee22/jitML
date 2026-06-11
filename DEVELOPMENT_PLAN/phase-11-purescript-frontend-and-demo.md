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
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the PureScript frontend surface under `web/`, the
> generated browser contracts from `src/JitML/Web/Contracts.hs`, typed bundle
> and panel/demo-route metadata from `src/JitML/Web/Bundle.hs`, the Playwright
> scaffold, the demo deployment template, and the `jitml-demo` executable shim.
> The target architecture later expands this into Halogen panels, live REST/WS
> handlers, and a compiled browser bundle.

## Phase Status

🔄 **Active** (reopened 2026-06-10 — real-workflow refactor). The PureScript
SPA, panels, and demo server shipped, but the demo HTTP endpoints returned
constants (`/api/inference` a synthetic `inferFromManifest` number,
`/api/connect4/move` a hard-coded column) and the panels issue no real fetches.
Sprint `11.8` routes the demo endpoints through real computation — `Web.Server`
`/api/inference` runs the real policy/value network forward and
`/api/connect4/move` runs the real MCTS tree search — and tracks the panel
fetch/typed-parse rewrite + live Playwright value assertions as Remaining Work
(they need the PureScript toolchain and a live cluster). See
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The prior
closure narrative below is retained as dated record.

✅ **Done** (reopened and re-closed 2026-06-05 after Sprint `11.7` —
SPA portals home and shared header; previously ✅ Done 2026-05-25 and
re-closed 2026-06-04 after Sprint `11.3`). Every prior owned
code-surface obligation remains closed: PureScript scaffold, generated
browser contracts under
`web/src/Generated/Contracts.purs`, six typed panel modules under
`web/src/Panels/`, Halogen dependency + render machinery on each panel,
`purescript-spec` smoke suite invoked through `jitml lint purescript` and the
Node `spec-node` runner,
demo HTTP server (the deterministic local stream-frame stand-in later
retired by Phase `15` Sprint `15.3`), compiled bundle baked into
`jitml:local`, and Playwright DOM-shape matrix at
`playwright/jitml-demo.spec.ts`. The later live work — `/api/ws`
WebSocket proxy bridging the demo server to Pulsar event topics, and
Playwright against the live edge route — closed in
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprints `13.13` / `13.14`; Phase `15` Sprint `15.3` removed the
offline Playwright and local stream fallbacks on 2026-06-04.
Phase `11` reopened and reclosed on 2026-06-04 for Sprint `11.3` runner
cleanup: `web/test/Main.purs` now uses
`Test.Spec.Runner.Node.runSpecAndExitProcess`, `web/spago.yaml` adds
`spec-node` to the test dependencies, and the deprecated generic `runSpec`
compatibility alias is removed. The 2026-06-05 Sprint `11.7` closure
exposes the bundled admin portals declared in the route registry as a
default-landing portals home plus a slim shared header on every panel,
generated from `src/JitML/Routes.hs` so the registry remains the single
source of truth. `Main.purs` now routes empty / unmatched hashes to
`Panels.Portals`, dispatches panel mounts through `PanelRegistry`, and
disposes the previous Halogen root before mounting the next hash route.

The phase owns
[Exit Definition](README.md#exit-definition) item 8 (PureScript frontend
under `web/` generated from `src/JitML/Web/Contracts.hs` via
`purescript-bridge`; live MNIST handwriting panel, CIFAR/ImageNet upload
panel, and AlphaZero-vs-human Connect 4 panel exercised end-to-end by
Playwright; `jitml-demo` serves the bundle) and contributes the
PureScript lint half of item 15 (the `jitml lint purescript` target
currently covering generated-contract, whitespace, panel-contract, and typed
frontend-tool command checks plus the `purescript-spec` smoke suite).
**Met today**: Sprints `11.1` and `11.2` close the minimal PureScript
scaffold and the typed contract renderer that produces
`web/src/Generated/Contracts.purs`. The six canonical panel payload
modules now live under `web/src/Panels/`:
`Panels.{Mnist,Cifar,Connect4,Rl,Training,Tune}` — each carries the
typed request/response payload shape for its endpoint. `web/test/Main.purs`
smokes every panel name + the generated contracts surface.
`playwright/jitml-demo.spec.ts` covers the seven-test canonical panel
matrix through the live edge route. `JitML.Web.Bundle.panelSurfaces`
lists all six panel names, and
`JitML.Web.Bundle.demoRoutes` now names the full local demo HTTP surface
(`/`, `/api`, `/api/inference`, `/api/images`, `/api/connect4/move`,
`/api/ws`, `/api/ws/training`, `/api/ws/rl`, `/api/ws/tune`).
`JitML.Web.Server.demoHttpRoutes` serves the same route family; stream
GETs require a WebSocket upgrade and return `503` when requested as
plain HTTP.
**Met on 2026-05-24 / refreshed on 2026-06-04**: Sprint `11.3` closed by
adding `spec` to the `web/spago.yaml` test deps, rewriting
`web/test/Main.purs` as a `describe`/`it` block that touches every typed
`Panels.*` payload-shape contract and the generated `Generated.Contracts`
endpoint catalog, and wiring `JitML.Lint.Stack.runPureScriptSpecSuite` to invoke
`/usr/local/bin/spago test` through the typed `Subprocess` on the default
`jitml lint purescript` path. The 2026-06-04 refresh adds `spec-node` and
uses `runSpecAndExitProcess`, so Node-local `spago test` exits via the current
runner API and no longer emits the `runSpec` deprecation warning. Sprint
`11.4` closed by adding `halogen`,
`halogen-vdom`, `aff`, `web-html`, `arrays`, `foldable-traversable`,
`maybe`, and `tuples` to `web/spago.yaml`, rewriting every
`web/src/Panels/*.purs` module as a typed Halogen `H.component` plus
`mount` driver, and updating `web/src/Main.purs` to dispatch on the URL
hash. The 2026-05-24 in-container `docker compose build jitml` produced
the initial PureScript output; later Phase `13` bundling emits the
browser-loadable `web/dist/Main/bundle.js`, and
`docker compose run --rm jitml jitml lint purescript` returned `ok`.
**Later closure**: the live `/api/ws` proxy against real daemon Pulsar
topics, compiled bundle serving from the Kind-deployed demo pod, and
Playwright against the live `jitml-demo` edge route closed in Phase `13`.
Phase `15` Sprint `15.3` retired the offline DOM and deterministic stream
fallbacks. Sprint `11.7` adds `Generated.AdminPortals`, the portals home,
the shared header, and live Playwright coverage for the portals/header
matrix.

### Current Implementation Scope

The worktree implements a minimal PureScript entrypoint, generated
contract file, typed bundle/panel/demo-route metadata,
`web/package.json` script surface, `web/test/Main.purs`, six
`web/src/Panels/*.purs` payload modules, live-only Playwright spec,
`jitml-demo` executable shim, and demo deployment template. Halogen
dependency/mount machinery, the browser-loadable bundle output, and live
WebSocket proxying have landed in later phase work; no Phase `11`
code-surface obligation remains open.
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
2. `jitml lint purescript` verifies the generated contract file exists and
   names the expected endpoint surface.

## Sprint 11.3: `jitml lint purescript` Generated-Contract Smoke Target ✅

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/spago.yaml`,
`src/JitML/Lint/Stack.hs`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml lint purescript` as the generated-contract, whitespace,
panel-contract, `purs-tidy`-formatting, and `purescript-spec` smoke target.
The smoke suite runs under Node through `spec-node`.

### Deliverables

- `web/test/Main.purs` is present as a `purescript-spec` test entrypoint.
- `web/spago.yaml` declares both `spec` and `spec-node` for the test target.
- `web/test/Main.purs` uses
  `Test.Spec.Runner.Node.runSpecAndExitProcess`, not the deprecated generic
  `Test.Spec.Runner.runSpec` compatibility alias.
- `src/JitML/Lint/Stack.hs` verifies
  `web/src/Generated/Contracts.purs` exists and names the expected endpoint
  surface.
- The lint target also checks `renderPureScriptContracts` emits the PureScript
  module header.
- The lint target recursively checks every checked-in `web/src/**/*.purs` and
  `web/test/**/*.purs` source for tab-free, final-newline source shape and
  verifies each typed panel endpoint is covered by the generated contract
  endpoint list.
- It validates the explicit `spago test` and `purs-tidy check` typed
  `Subprocess` values without invoking them through process-environment gates.
- The default lint path now invokes `purs-tidy check 'src/**/*.purs'` against
  the container-installed `/usr/local/bin/purs-tidy` (added to the
  `npm install -g` line in `docker/Dockerfile`). When the binary is missing
  (host invocation or a partial image), `runPureScriptTidyCheck` reports a
  `purescript.tools.missing` finding instead of silently skipping.
- `web/.gitignore` excludes `.spec-results`, the persistent Node runner state
  emitted by `spec-node`.

### Validation

1. `docker compose run --rm jitml jitml lint purescript` exits `0` for the smoke body.
2. Missing generated-contract output fails the lint target.
3. PureScript whitespace and panel-contract validation run in the lint target.
4. The lint target validates `spago test` and `purs-tidy check` as explicit typed
   `Subprocess` values with no process-environment gate.
5. The default lint path invokes `/usr/local/bin/purs-tidy check 'src/**/*.purs'`
   in `web/` through the typed `Subprocess` and surfaces formatting drift as a
   `purescript.purs-tidy.drift` finding. 2026-05-23 validation in `jitml:local`
   confirms `purs-tidy check` reports no drift on the checked-in
   `web/src/**/*.purs` set, and a deliberately mis-formatted source produces
   the expected `Some files are not formatted` finding.
6. Target validation: the default style path adds a `purescript-spec` smoke
   suite that touches every typed panel contract through
   `/usr/local/bin/spago test` in `web/`.
7. 2026-06-04 validation:
   `docker compose run --rm jitml sh -lc 'cd web && spago test'` passes
   7 / 7 with zero PureScript warnings after the `spec-node` runner update.

### Remaining Work

None. The `purescript-spec` smoke suite closed on 2026-05-24 and was refreshed
on 2026-06-04 to use the current Node runner API: `spec` and `spec-node` are
`web/spago.yaml` test dependencies, `web/test/Main.purs` is a `describe`/`it`
block that touches every typed `Panels.*` payload-shape contract and the
generated `Generated.Contracts` endpoint catalog, and
`JitML.Lint.Stack.runPureScriptSpecSuite` invokes `/usr/local/bin/spago test`
through the typed `Subprocess` boundary on the default
`jitml lint purescript` path. The in-container
`docker compose run --rm jitml sh -lc 'cd web && spago test'` validation
passed 7 / 7 with no PureScript warnings on 2026-06-04.

## Sprint 11.4: Interactive Endpoint Contract Surface ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The Halogen
dependency + render machinery (slot + state + DOM diff) on each
`Panels.*` module closed on 2026-05-24; the Dockerfile runs the
PureScript build and esbuild bundle step to produce
`web/dist/Main/bundle.js`. `JitML.Web.Server.loadBundleEntry` +
`demoHttpRoutesWithBundle` serve the compiled bundle when present.
`playwright/jitml-demo.spec.ts` covers the canonical six-panel
DOM-shape matrix. The live `/api/ws` WebSocket proxy migrated to
Phase `13` Sprint `13.13`; live edge-route Playwright migrated to
Phase `13` Sprint `13.14`.
**Implementation**: `src/JitML/Web/Contracts.hs`,
`src/JitML/Web/Bundle.hs`,
`web/spago.yaml`, `web/src/Main.purs`, `web/src/Generated/Contracts.purs`,
`web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs`
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
  manifest for the full current local HTTP surface:
  `/`, `/api`, `/api/inference`, `/api/images`, `/api/connect4/move`,
  `/api/ws`, `/api/ws/training`, and `/api/ws/tune`.
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
- The live WebSocket proxy that bridges `/api/ws` to real daemon Pulsar
  topics remains target runtime validation; the current stream routes return
  deterministic local scaffold frames.

### Validation

1. `cabal test jitml-e2e` validates the browser contract endpoint
   count, the typed demo route manifest, and the demo HTTP route table
   for generated stream endpoints.
2. `docker compose run --rm jitml jitml lint purescript` validates the
   generated contract file exists.
3. `jitml-unit` verifies the bundle, panel, and demo-route metadata.
4. Live validation (target): each Halogen panel module renders against
   live daemon state, the `/api/ws` WebSocket proxy streams real metric
   updates from the daemon, and panel uploads / inferences round-trip
   through the daemon's real handlers.

### Remaining Work

- The Halogen dependency closed on 2026-05-24: `web/spago.yaml`
  declares `halogen`, `halogen-vdom`, `aff`, `web-html`, `arrays`,
  `foldable-traversable`, `maybe`, `tuples`, plus the existing
  `console` / `effect` / `prelude`. Every `web/src/Panels/*.purs`
  module exports a typed Halogen `H.component` with state and DOM
  render plus a `mount :: Effect Unit` that drives `Halogen.Aff` +
  `Halogen.VDom.Driver.runUI`. `web/src/Main.purs` dispatches on the
  `location.hash` and mounts the matching panel (default: MNIST).
  `spago build --output dist` runs in `docker/Dockerfile`; Phase `13`
  adds the esbuild step that emits `web/dist/Main/bundle.js` for the
  demo image.
- The live `/api/ws` WebSocket proxy that bridges the demo server to
  the daemon's metric/event Pulsar topics is owned by
  [phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
  Sprint `13.13`.

## Sprint 11.5: `jitml-demo` Executable Shim ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The live
`/api/ws` proxy bridging browser clients to Pulsar event topics
migrated to Phase `13` Sprint `13.13`.
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
- `src/JitML/Web/Bundle.hs` declares `demoRoutes` for the full current
  local HTTP surface: `/`, `/api`, `/api/inference`, `/api/images`,
  `/api/connect4/move`, `/api/ws`, `/api/ws/training`, and `/api/ws/tune`.
- The `Deployment/jitml-demo` template is populated with the demo image,
  `jitml-demo` command, and explicit `--host 0.0.0.0 --port 80` arguments so
  Envoy can reach the pod IP.
- HTTPRoutes for `/`, `/api`, `/api/ws` (Sprint `3.4`) point at
  `jitml-demo:80`.

### Validation

1. Running `jitml-demo` prints the generated-frontend status line and
   starts the HTTP listener.
2. The `Deployment/jitml-demo` chart template names the demo image and
   exposes container port `80`.
3. `jitml-e2e` verifies the demo route manifest covers `/`, `/api`, and
   `/api/ws`, that the deployment starts `jitml-demo` with explicit host/port
   listener arguments, and that a
   one-shot demo HTTP server serves the API index. The same stanza verifies
   the typed demo route manifest covers the current local API surface.
4. 2026-05-23 validation: `docker run --rm jitml:local jitml-demo --host
   0.0.0.0 --port 8080` serves `/` with the bundle-script-tagged shell and
   `/bundle/main.js` from the baked image.
5. Later live validation: Phase `13` validated the live `/api/ws` proxy
   against daemon metric/event Pulsar topics and Phase `15` validated the
   live-only Playwright matrix after removing offline fallbacks.

### Remaining Work

- None remaining for Sprint `11.4`. The browser-loadable bundle path is
  `web/dist/Main/bundle.js`, the demo route appends `/bundle/main.js`
  when that file exists, and later Phase `13` / Phase `15` work closed
  the live WebSocket and fallback-removal surfaces.

## Sprint 11.6: Playwright E2E Suite ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live edge-route
Playwright execution against the running cluster migrated to Phase `13`
Sprint `13.14`; Phase `15` Sprint `15.3` removed the inline
`page.setContent` DOM fallback.
**Implementation**: `playwright/jitml-demo.spec.ts`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Land the Playwright scaffold for the future interactive panel suite.

### Deliverables

- `playwright/jitml-demo.spec.ts` exists as the current E2E scaffold.
- The target suite covers MNIST, CIFAR/ImageNet, Connect 4, RL trajectory,
  training, and tuning panel flows once those panels and the HTTP server land.
- The current `jitml-e2e` stanza validates the typed Playwright plan; live
  Playwright execution is target work on the explicit e2e orchestration path.
- Playwright execution stays out of the default local Cabal matrix until the
  panels consume fixture-backed or live-backed state through `jitml-demo`;
  static scaffold assertions remain covered by the current Haskell e2e and
  PureScript lint targets.

### Validation

1. `playwright/jitml-demo.spec.ts` remains present for the E2E runner.
2. `jitml-e2e` validates route, bucket, publication, contract, and
   report-card surfaces.
3. Later live validation: the explicit live orchestration path invokes
   Playwright against the live `jitml-demo` HTTP listener, and the
   canonical panel matrix passed 7 / 7 against the Apple Silicon edge
   route on 2026-06-04 after the offline fallback was removed.

### Remaining Work

- None remaining for Sprint `11.6`. `playwright/jitml-demo.spec.ts` now
  reads the live edge port from `cluster-publication.json`, fails fast
  when no live publication exists, and stays out of the default
  `cabal test all` matrix unless the live invocation is explicit.

## Sprint 11.7: SPA Portals Home and Shared Header ✅

**Status**: Done
**Implementation**: `src/JitML/Routes.hs`,
`src/JitML/Web/AdminPortals.hs`, `src/JitML/Generated/Paths.hs`,
`web/src/Generated/AdminPortals.purs`, `web/src/Chrome/Header.purs`,
`web/src/PanelRegistry.purs`, `web/src/Panels/Portals.purs`,
`web/src/Main.purs`, `web/src/Panels/{Mnist,Cifar,Training,Tune,Rl,Connect4}.purs`,
`web/test/Main.purs`, `playwright/jitml-demo.spec.ts`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`../README.md` (Panels section), `legacy-tracking-for-deletion.md`

### Objective

Close the SPA discoverability gap against the route registry. The six
bundled admin portals declared in `src/JitML/Routes.hs` (Grafana,
Prometheus, TensorBoard, Harbor, MinIO console, Pulsar admin) have no
in-app surface; the bundle's empty-hash landing currently mounts MNIST,
so a user opening `127.0.0.1:<edge-port>/` cannot reach any adjacent
platform UI without external knowledge of `../README.md` edge prefixes.
Per Plan Standards rule L, the doctrine prescription at
[../README.md → Routes Published at the Edge](../README.md#envoy-gateway-api-a-single-localhost-socket)
makes the demo bundle the single localhost surface; the bundle is
therefore the right place to host the directory.

### Deliverables

- Extend the `Route` record with `routeAdminPortalLabel :: Maybe Text`,
  tag the six portal entries with display labels, and expose
  `adminPortalRoutes` returning the labelled subset in display order
  (`src/JitML/Routes.hs`).
- New `src/JitML/Web/AdminPortals.hs` emitter `renderPureScriptAdminPortals`,
  mirroring `JitML.Web.Contracts.renderPureScriptContracts`; register the
  resulting `web/src/Generated/AdminPortals.purs` artifact in
  `JitML.Generated.Paths.trackingGeneratedPaths` so `jitml docs check`
  gates drift. The module is added to the library `exposed-modules`.
- New `web/src/Chrome/Header.purs` (slim shared header — wordmark plus a
  `[home]` link to `#portals`), `web/src/PanelRegistry.purs` (single
  hand-maintained list of demo panels), and `web/src/Panels/Portals.purs`
  (the home panel: header + two-column directory composed from
  `PanelRegistry.panels` and `Generated.AdminPortals.adminPortals`).
- `web/src/Main.purs` adds a `#portals` case and flips the unmatched /
  empty-hash fallback from `Mnist.mount` to `Portals.mount`. The named
  `#mnist-live-inference` route continues to work. Hash transitions run
  the previous Halogen disposer before mounting the new panel, so only
  one root remains attached.
- Each existing panel
  (`Panels.{Mnist,Cifar,Training,Tune,Rl,Connect4}`) prepends
  `Chrome.Header.render` to its top-level render tree.
- `web/test/Main.purs` covers the generated `AdminPortals` array (length
  + six expected `name`/`path` pairs).
- `playwright/jitml-demo.spec.ts` covers (a) empty-hash → portals home
  with both columns visible, (b) `[home]` header link present on every
  panel page, (c) every portal link carries the expected `href`.

### Validation

2026-06-05 validation:

1. `docker compose build jitml` exits 0 and bakes the current
   PureScript bundle plus `jitml check-code` into `jitml:local`.
2. `docker compose run --rm jitml jitml docs check` exits 0 — the new
   `web.admin-portals.purescript` tracked path matches the rendered
   `Generated.AdminPortals` and the `cluster.routes` block in
   `documents/engineering/cluster_topology.md` regenerates clean (the
   new `Route` field is metadata only and does not project into
   `renderRouteTable`).
3. `docker compose run --rm jitml cabal test jitml-unit --jobs=2`
   passes.
4. `docker compose run --rm jitml cabal test jitml-integration --jobs=2`
   passes, including the Apple Silicon node-local Postgres PV overlay
   rollout-plan assertion.
5. `docker compose run --rm jitml sh -lc 'cd web && spago test'`
   passes with the existing suite plus the `Generated.AdminPortals`
   round-trip.
6. `docker compose run --rm jitml jitml check-code` passes.
7. Live Apple Silicon Kind cluster: `./bootstrap/apple-silicon.sh up`
   completes the phased rollout with all publication components ready on
   the leased `edge_port: 9091`; `./bootstrap/apple-silicon.sh
   run-daemon` starts the host daemon, derives routed Pulsar/MinIO/Harbor
   settings from `./.build/conf/host/apple-silicon.dhall`, passes client
   probes, and subscribes to
   `persistent://public/default/inference.command.apple-silicon`.
8. Live Playwright passes 9 / 9 against
   `http://127.0.0.1:9091`: empty-hash portals home, portal link hrefs,
   shared header on every panel, and the six canonical panel hashes.

### Remaining Work

None. Sprint `11.7` closed on 2026-06-05; the matching
legacy-ledger row moved to `Completed`.

## Sprint 11.8: Demo Endpoints Render Real Substrate Output [Active]

**Status**: Active
**Implementation**: `src/JitML/Web/Server.hs` (`renderInferenceResponse`,
`renderConnect4Response`); panels under `web/src/Panels/*`,
`web/src/Panels/Stream.js`, `playwright/jitml-demo.spec.ts`
**Docs to update**: `../documents/engineering/frontend_bundle.md`, `system-components.md`

### Objective

Make the demo endpoints render real model output instead of constants, and make
the panels issue real fetches over the typed contracts. Owns the frontend slice
of [Exit Definition](README.md#exit-definition) item 6/7.

### Deliverables

- `Web.Server` `/api/inference` runs the real policy/value network forward
  (`PolicyValueNet.networkPolicyValue`) and reports the value/policy heads;
  `/api/connect4/move` runs the real MCTS tree search
  (`PolicyValueNet.mctsVisitDistribution`) and returns the highest-visit move —
  no hard-coded column, no synthetic `inferFromManifest`.
- The panels issue real HTTP fetches over the generated contracts and parse the
  typed responses; the dead `*Received` handlers, the raw `LiveFrame String`
  path, and the `Stream.js` socket-failure swallow are removed.
- Playwright asserts real rendered values (not just DOM visibility) against the
  live demo edge route.

### Validation

- `docker compose run --rm jitml jitml check-code` (the `Web.Server` change)
  and `jitml lint purescript` (the panel rewrite).
- Live: `playwright/jitml-demo.spec.ts` against `jitml bootstrap --<substrate>`.

### Current Validation State

Landed: the `Web.Server` `/api/inference` and `/api/connect4/move` endpoints now
run the real network forward / real MCTS (pure, host lib type-checks; container
`check-code` validated at the Phase 11 boundary). The unit tests assert endpoint
*paths/contracts*, not response bodies, so they hold.

### Remaining Work

- Rewrite the nine PureScript panels (`web/src/Panels/*`) to issue real fetches +
  typed parsing and delete the dead receive handlers / raw-frame / swallow paths.
  The panels currently make **no HTTP calls** (there is no Affjax / fetch client
  in `web/`), so this requires adding an HTTP client dependency + spago/package
  config and wiring each Halogen panel's action to fetch and typed-parse its
  generated contract. Build-validatable via `jitml lint purescript`.
- Live Playwright value assertions against the demo edge route — needs a live
  cluster (`jitml bootstrap`), not runnable on a memory-constrained host; owned
  jointly with Phase 13/14 live closure.

## Doctrine Sections Cited

- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (target frontend tool invocations flow through `Subprocess`; current checked-in bodies are local smoke tests)
- [../README.md → Generated Artifacts](../README.md#generated-documentation-flow) (Sprint 11.2 — generated PureScript contracts)
- [../README.md → Repository layout (target)](../README.md#repository-layout-target) (Sprint 11.5 — six-line `app/Demo.hs` shim)
- [../README.md → Application Environment](../README.md#doctrine-scope) (target demo server uses the full `Env`; current `demoMain` reads explicit `--port`, prints `demoStatusLine`, and starts the local HTTP server)
- [../README.md → Test-suite stanzas](../README.md#test-suite-stanzas) (Sprint 11.6 — Playwright scaffold belongs to the target Ephemeral-Cluster Infrastructure category via `jitml-e2e`)
- [../README.md → Lint matrix](../README.md#lint-matrix) (Sprint 11.3 — local project-specific lint target via `jitml lint purescript`)
- [../README.md → Routes Published at the Edge](../README.md#envoy-gateway-api-a-single-localhost-socket) (Sprint 11.7 — the demo bundle is the single localhost surface; the SPA owns the in-app directory for the bundled admin portals declared in the route registry)

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
  the doctrine's target Ephemeral-Cluster Infrastructure test category and
  is scaffolded for `jitml-e2e`; the current PureScript generated-contract
  smoke checks are owned by the `jitml lint purescript` target and run through
  `spec-node` (Sprint `11.3`).
- `documents/engineering/purescript_frontend.md` — Sprint `11.7` adds the
  `Chrome.Header` shared chrome, the `PanelRegistry` SPA-side panel list,
  the `Panels.Portals` default-landing home, and the generated
  `Generated.AdminPortals` artifact paired with
  `src/JitML/Web/AdminPortals.hs`. Update Stack / Layout / Panels and
  cross-link `src/JitML/Routes.hs` as the upstream source for the portal
  display labels.

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
- [../README.md](../README.md)

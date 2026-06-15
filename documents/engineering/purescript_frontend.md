# PureScript Frontend

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, ../../DEVELOPMENT_PLAN/phase-17-interactive-demo-and-playwright-closure.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/system-components.md
**Generated sections**: none

> **Purpose**: Project-specific PureScript frontend doctrine for jitML — the
> current local PureScript shell, browser-contract renderer, bundle/panel
> metadata, demo-route manifest, Playwright scaffold, demo deployment template,
> and `jitml-demo` HTTP server, including the Halogen panels, compiled bundle,
> live WebSocket proxy, and the reopened no-caveat Playwright product matrix.

## Stack

| Component | Current status | Owning module / path |
|-----------|----------------|----------------------|
| PureScript entrypoint | Halogen panel dispatcher keyed by URL hash; empty / unmatched hash routes to the portals home; hash transitions dispose the previous Halogen root before mounting the next panel | `web/src/Main.purs` |
| npm scripts | `build`, `test`, `format` wrappers plus checked-in Spago project | `web/package.json`, `web/spago.yaml` |
| Contract renderer | Local bridge-compatible renderer | `src/JitML/Web/Contracts.hs` |
| Generated contracts | Checked-in generated file protected by `trackingGeneratedPaths` | `web/src/Generated/Contracts.purs` |
| Admin-portal emitter | Bridge-compatible emitter for the bundled admin-portal directory; derived from the `routeAdminPortalLabel` metadata on the route registry | `src/JitML/Web/AdminPortals.hs` |
| Generated admin portals | Checked-in generated file protected by `trackingGeneratedPaths` | `web/src/Generated/AdminPortals.purs` |
| Bundle/panel/demo-route metadata | Local Haskell metadata | `src/JitML/Web/Bundle.hs` |
| Shared chrome | Slim header (`jitML` wordmark + `[home]` link to `#portals`) rendered by every panel | `web/src/Chrome/Header.purs` |
| SPA panel registry | Single hand-maintained list of demo panels consumed by both `Main.purs` and the portals home | `web/src/PanelRegistry.purs` |
| Portals home panel | Two-column directory composing `PanelRegistry.panels` with `Generated.AdminPortals.adminPortals`; default empty-hash landing | `web/src/Panels/Portals.purs` |
| Demo HTTP routes | Haskell HTTP server for API routes, compiled bundle serving, and live WebSocket bridge | `src/JitML/Web/Server.hs` |
| PureScript smoke file | Spec smoke file covering generated contracts and panel modules through the Node `spec-node` runner | `web/test/Main.purs` |
| Panel payload modules | Six Halogen panels with REST or live WebSocket actions; Sprint `11.9` replaces text-marker/default-value parsers with generated typed payloads for controls, metrics, animation, inference, and replay | `web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs` |
| Playwright | Current live-only spec covers portals/header/admin links, six panels, and selected REST response/rendered-value updates; Sprint `12.13` / Phase `17` expands this to a no-caveat product matrix that starts workflows, validates training/checkpoint/inference, observes RL animations, drives adversarial games, replays transcripts, and exercises tuning controls | `playwright/jitml-demo.spec.ts`, `src/JitML/Test/LivePlan.hs`, `test/e2e/Main.hs` |
| Demo executable | Status line plus HTTP/WebSocket server | `app/Demo.hs`, `src/JitML/App.hs` |

The PureScript stack is project-specific (the doctrine does not address
browser-side code). Npm / Spago / Playwright invocations flow through
the typed `Subprocess` boundary from doctrine `Architecture → Subprocesses as
Typed Values`; the checked-in Cabal bodies perform local smoke checks,
validate the `spago test`, `purs-tidy check`, and Playwright command shapes,
and keep the live browser run on the explicit live orchestration path.
`web/spago.yaml` keeps `spec` and `spec-node` in the test dependency set, and
`web/test/Main.purs` uses `Test.Spec.Runner.Node.runSpecAndExitProcess` so
Node-local smoke runs exit with the real test status without the deprecated
generic `runSpec` compatibility alias. The runner's `.spec-results` file is
ignored under `web/.gitignore`.

## Layout

Current checked-in layout:

```text
web/
├── spago.yaml
├── package.json
├── src/
│   ├── Main.purs
│   ├── PanelRegistry.purs
│   ├── Chrome/
│   │   └── Header.purs
│   ├── Panels/
│   │   ├── Api.js
│   │   ├── Api.purs
│   │   ├── Cifar.purs
│   │   ├── Connect4.purs
│   │   ├── Mnist.purs
│   │   ├── Portals.purs
│   │   ├── Rl.purs
│   │   ├── Stream.js
│   │   ├── Stream.purs
│   │   ├── Training.purs
│   │   └── Tune.purs
│   └── Generated/
│       ├── AdminPortals.purs
│       └── Contracts.purs
└── test/
    └── Main.purs

playwright/
└── jitml-demo.spec.ts
```

Build output under `web/dist/` is generated, not checked in. The Docker image
build runs `spago build --output dist` and esbuilds `dist/Main/index.js` into
the browser-loadable `web/dist/Main/bundle.js` served by `jitml-demo`.

## Current Local Surface

The current worktree contains `web/src/Main.purs`, generated
`web/src/Generated/Contracts.purs`, six Halogen panel modules under
`web/src/Panels/`, `web/test/Main.purs`, `src/JitML/Web/Contracts.hs`, and
`src/JitML/Web/Bundle.hs`. `Web.Bundle` records the bundle output paths, the
six canonical panel surfaces, the `demoStatusLine`, and the demo route
manifest for `/`, `/api`, `/api/inference`, `/api/images`,
`/api/connect4/move`, `/api/ws`, `/api/ws/training`, `/api/ws/rl`, and
`/api/ws/tune`. `web/src/Main.purs` dispatches through the SPA
`PanelRegistry`, stores the active Halogen disposer, and runs it before
mounting the next hash-selected panel so navigation does not leave
duplicate roots attached. `src/JitML/Web/Server.hs` serves the same HTTP surface,
returns `503` for plain stream GETs that do not upgrade to WebSocket, and
bridges upgraded `/api/ws*` clients to live Pulsar event topics.

## No-Caveat Closure Target

The final browser target is end-to-end rather than demonstrative. The demo app
must start or select real SL, RL, AlphaZero, and tuning runs; consume typed
payloads generated from Haskell-owned contracts; render model-appropriate
interactions; animate RL trajectories from real event frames; render all
canonical adversarial games with legal move handling, MCTS/value/policy details,
and interactive replay; and expose tuning sweep controls/frontiers tied to real
trial state. Playwright must prove those behaviors through the explicit live
`jitml-e2e` orchestration path before final handoff.

Current route reachability, panel mounting, and selected REST updates are
historical evidence, not final product closure. Temporary marker parsers,
inline demo responses, placeholder canvases, and text-only replay displays are
tracked for deletion in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## Browser-Contract ADTs

`src/JitML/Web/Contracts.hs` is the **source of truth** for every ADT
crossed by the REST / WebSocket surface. The current local renderer produces
`web/src/Generated/Contracts.purs` and identifies itself as
`local-purescript-bridge-compatible-renderer`. The generated contract path is
an active `trackingGeneratedPaths` entry; hand edits fail `jitml docs check`.

The current endpoint metadata covers:

- `RunCommand` at `POST /api/runs/{runId}/command`
- `InferenceRun` at `POST /api/inference`
- `UploadImage` at `POST /api/images`
- `Connect4Move` at `POST /api/connect4/move`
- `MetricsStream` at `GET /api/ws`
- `TrainingStream` at `GET /api/ws/training`
- `RlStream` at `GET /api/ws/rl`
- `TuneStream` at `GET /api/ws/tune`

Sprint `11.9` expands this endpoint list into the full generated payload
surface: training commands/events/checkpoint markers, RL frame/replay events,
AlphaZero game state/MCTS/value/policy/replay records, inference/image request
and result bodies, tuning trial/frontier/control events, and run-control
acknowledgements. Panel-side string marker parsing is not part of the final
contract. Phase `8` Sprint `8.12` now generates the RL animation/replay payload
records (`RlAnimationFrame`, `RlReplayFrame`) from
`src/JitML/Web/Contracts.hs`; the RL panel consumes `RlAnimationFrame`,
preserves unsigned hash/cursor/timestamp fields as exact strings, and rejects
the former catch-all `data:` placeholder.

## Panels

Every panel renders inside `Chrome.Header.render` (the slim shared header — `jitML` wordmark plus `[home]` link to `#portals`), so the directory is one click away from any panel view. `Main.purs`'s empty-hash fallback routes to the portals home; the named hashes below continue to address each panel directly. Panel mounts return their Halogen disposer to the hash dispatcher, which runs the previous disposer before mounting a new route. The portals home is itself a `Panels.Portals` Halogen component composing `PanelRegistry.panels` (left column) with `Generated.AdminPortals.adminPortals` (right column), the latter generated from `src/JitML/Routes.hs` via `JitML.Web.AdminPortals` so the registry remains the single source of truth.

`Panels.Api.requestText` is the dependency-free text request bridge used by the
REST panels. MNIST, CIFAR/ImageNet, and Connect 4 issue real `POST` calls to the
generated endpoint paths and convert the text replies into the panel-specific
typed response records before updating Halogen state. `Panels.Stream` opens the
live WebSocket route, reports connection failures through typed actions, and the
RL/training/tune panels convert incoming frame text into typed stream records
instead of storing raw frame strings. `Panels.Rl.parseRlFrame` now accepts only
the generated `RlAnimationFrame` envelope. The remaining training/tune/browser
text bridges are compatibility surfaces: final browser closure consumes
generated payload codecs and removes the catch-all/default parsers that can
synthesize values from incomplete frames.

| Panel | URL hash | REST handler | WebSocket subscription |
|-------|----------|--------------|------------------------|
| Portals home (default) | `#portals` (empty hash) | — | — |
| MNIST | `#mnist-live-inference` | `POST /api/inference` | — |
| CIFAR / ImageNet | `#cifar-imagenet-upload` | `POST /api/images` | — |
| Connect 4 | `#connect4-human-vs-alphazero` | `POST /api/connect4/move` | — |
| RL trajectory | `#rl-trajectory` | — | `/api/ws/rl` (proxies `rl.event.<mode>`) |
| Training | `#training-progress` | — | `/api/ws/training` (proxies `training.event.<mode>`) |
| Tune | `#hyperparameter-sweep` | — | `/api/ws/tune` (proxies `tune.event.<mode>`) |

## REST and WebSocket Surface

The HTTP handlers live in `src/JitML/Web/Server.hs`; they provide responses for
the API index, inference, image top-k classification, Connect 4 move, compiled
bundle serving, and live stream routes. A stream route requested as plain HTTP
returns `503 live stream requires WebSocket upgrade`; upgraded clients are
bridged to Pulsar event topics by `liveDemoWebSocketRoutes`.

| Surface | Method | Path | Payload type |
|---------|--------|------|--------------|
| Inference | POST | `/api/inference` | `InferenceRun` |
| Image upload | POST | `/api/images` | `UploadImage` |
| Connect 4 move | POST | `/api/connect4/move` | `Connect4Move` |
| Live event WS | GET | `/api/ws`, `/api/ws/training`, `/api/ws/rl`, `/api/ws/tune` | typed event envelopes |
| Checkpoint browse | GET | `/api/checkpoints/<experiment-hash>` | manifest list (cross-link to TB sidecars) |

## `jitml-demo` HTTP Server

`app/Demo.hs` is a six-line shim into `App.demoMain`. The current `demoMain`
prints `demoStatusLine` from `src/JitML/Web/Bundle.hs`:
`jitml-demo: serving generated frontend contract surface`, then starts the
low-level HTTP/WebSocket listener from `src/JitML/Web/Server.hs`. It serves the
current route/API surface, `/bundle/main.js` from `web/dist/Main/bundle.js`
when the bundle exists, and the held-open `/api/ws*` WebSocket bridge. When no
live publication exists the bridge sends a terminal error frame instead of an
offline deterministic stream.

The `Deployment/jitml-demo` template (Sprint `4.1`) is populated with the
demo image, `jitml-demo` command, and explicit `--host 0.0.0.0 --port 80`
arguments so Envoy can reach the pod IP. HTTPRoutes for `/`, `/api`, `/api/ws`
(Sprint `3.4`) point at `jitml-demo:80`.

## Playwright E2E

`playwright/jitml-demo.spec.ts` is the current TypeScript Playwright scaffold.
`JitML.Test.LivePlan` records the target `npx playwright test` step after the
Helm dependency build and the `jitml bootstrap` ephemeral-cluster rollout. The
default `jitml-e2e` Cabal body validates that typed Playwright command shape
without starting the live stack. The checked-in spec is live-only: it reads
`.build/runtime/cluster-publication.json`, navigates to the published edge
route, and fails fast when no live publication exists. The historical matrix
covers the smoke shell plus the six canonical panels:

- Portals home: load the empty-hash root and assert both the panels
  column (`#jitml-portals-panels`) and the admin-portals column
  (`#jitml-portals-admin`) mount, plus every admin-portal link carries
  the expected root-relative `href` matching the route registry.
- Shared header: for each named panel hash, assert `#jitml-chrome`
  mounts and the `#jitml-chrome-home` anchor links to `#portals`.
- MNIST: load the inference panel, assert its canvas mounts, click Predict,
  wait for `POST /api/inference`, verify the real response contains the
  policy/value output, and assert the rendered prediction badge updates.
- CIFAR: load the upload panel, click Classify, wait for `POST /api/images`,
  and assert the response plus attached result-list surface.
- Connect 4: load the AlphaZero-vs-human panel, click a column, wait for
  `POST /api/connect4/move`, and assert the rendered move list includes the
  returned MCTS move.
- RL trajectory: load the trajectory panel through the live edge route.
- Training / Tune: load the streaming metric panels through the live edge
  route.

Sprint `12.13` / Phase `17` replace that reachability matrix with the
no-caveat product matrix. The expanded spec starts real workflows, waits for
typed training/checkpoint/inference evidence, interacts with every supported
model family, observes non-identical RL animation frames, drives all canonical
adversarial-game boards, verifies legal engine moves, saves and replays
transcripts through step/scrub controls, launches and manipulates tuning sweeps,
and asserts that browser state is backed by live workflow artifacts rather than
fixture or inline demo state.

Playwright execution runs through the typed `Subprocess` boundary on the
explicit live orchestration path; it belongs to the doctrine's
Ephemeral-Cluster Infrastructure test category and does not have its own Cabal
stanza. Static route/API scaffold checks stay in the local Haskell e2e and
PureScript lint targets.
The 2026-06-11 CUDA-machine run used
`mcr.microsoft.com/playwright:v1.49.1-noble` with host networking against the
published `linux-cuda` edge and passed **9 / 9**.
The local PureScript smoke suite is `purescript-spec` executed through
`spec-node` by `spago test`; Playwright remains live-only and separate from the
default Cabal matrix.

## Cross-References

- [../../README.md → PureScript frontend](../../README.md#purescript-frontend)
- [../../README.md → Panels](../../README.md#panels)
- [../../README.md → Envoy Gateway API: a single localhost socket](../../README.md#envoy-gateway-api-a-single-localhost-socket) (`src/JitML/Routes.hs` is the upstream source for the generated `Generated.AdminPortals` artifact; the routes-published-at-the-edge table in that section is rendered from the same registry)
- [cluster_topology.md → Routes Published at the Edge](cluster_topology.md#routes-published-at-the-edge) (the canonical regenerated table)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)
- [../../DEVELOPMENT_PLAN/phase-17-interactive-demo-and-playwright-closure.md](../../DEVELOPMENT_PLAN/phase-17-interactive-demo-and-playwright-closure.md)

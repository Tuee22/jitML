# PureScript Frontend

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/system-components.md
**Generated sections**: none

> **Purpose**: Project-specific PureScript frontend doctrine for jitML — the
> current local PureScript shell, browser-contract renderer, bundle/panel
> metadata, demo-route manifest, Playwright scaffold, demo deployment template,
> and `jitml-demo` HTTP server, including the Halogen panels, compiled bundle,
> live WebSocket proxy, and live-only Playwright matrix.

## Stack

| Component | Current status | Owning module / path |
|-----------|----------------|----------------------|
| PureScript entrypoint | Halogen panel dispatcher keyed by URL hash | `web/src/Main.purs` |
| npm scripts | `build`, `test`, `format` wrappers plus checked-in Spago project | `web/package.json`, `web/spago.yaml` |
| Contract renderer | Local bridge-compatible renderer | `src/JitML/Web/Contracts.hs` |
| Generated contracts | Checked-in generated file protected by `trackingGeneratedPaths` | `web/src/Generated/Contracts.purs` |
| Bundle/panel/demo-route metadata | Local Haskell metadata | `src/JitML/Web/Bundle.hs` |
| Demo HTTP routes | Haskell HTTP server for API routes, compiled bundle serving, and live WebSocket bridge | `src/JitML/Web/Server.hs` |
| PureScript smoke file | Spec smoke file covering generated contracts and panel modules through the Node `spec-node` runner | `web/test/Main.purs` |
| Panel payload modules | Six typed Halogen panels with REST or live WebSocket actions | `web/src/Panels/{Mnist,Cifar,Connect4,Rl,Training,Tune}.purs` |
| Playwright | Live-only seven-panel spec plus typed live-plan step; no inline DOM fallback remains | `playwright/jitml-demo.spec.ts`, `src/JitML/Test/LivePlan.hs`, `test/e2e/Main.hs` |
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
│   ├── Panels/
│   │   ├── Cifar.purs
│   │   ├── Connect4.purs
│   │   ├── Mnist.purs
│   │   ├── Rl.purs
│   │   ├── Training.purs
│   │   └── Tune.purs
│   └── Generated/
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
`/api/ws/tune`. `src/JitML/Web/Server.hs` serves the same HTTP surface,
returns `503` for plain stream GETs that do not upgrade to WebSocket, and
bridges upgraded `/api/ws*` clients to live Pulsar event topics.

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

Richer typed training, RL, AlphaZero, inference, image-upload, Connect 4, and
tuning payload ADTs remain target browser-contract work.

## Panels

| Panel | URL | REST handler | WebSocket subscription |
|-------|-----|--------------|------------------------|
| MNIST | `/mnist` | `POST /api/inference` | — |
| CIFAR / ImageNet | `/cifar`, `/imagenet` | `POST /api/images` | — |
| Connect 4 | `/connect4` | `POST /api/connect4/move` | — |
| RL trajectory | `/rl/<run-id>` | — | `/api/ws/rl` (proxies `rl.event.<mode>`) |
| Training | `/training/<run-id>` | — | `/api/ws/training` (proxies `training.event.<mode>`) |
| Tune | `/tune/<sweep-id>` | — | `/api/ws/tune` (proxies `tune.event.<mode>`) |

## REST and WebSocket Surface

The HTTP handlers live in `src/JitML/Web/Server.hs`; they provide responses for
the API index, inference, upload acknowledgement, Connect 4 move, compiled
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
route, and fails fast when no live publication exists. The matrix covers the
smoke shell plus the six canonical panels:

- MNIST: load the inference panel and assert its canvas mounts.
- CIFAR: load the upload panel and assert the upload control surface mounts.
- Connect 4: load the AlphaZero-vs-human panel and assert the board mounts.
- RL trajectory: load the trajectory panel through the live edge route.
- Training / Tune: load the streaming metric panels through the live edge
  route.

Playwright execution runs through the typed `Subprocess` boundary on the
explicit live orchestration path; it belongs to the doctrine's
Ephemeral-Cluster Infrastructure test category and does not have its own Cabal
stanza. Static route/API scaffold checks stay in the local Haskell e2e and
PureScript lint targets.
The local PureScript smoke suite is `purescript-spec` executed through
`spec-node` by `spago test`; Playwright remains live-only and separate from the
default Cabal matrix.

## Cross-References

- [../../README.md → PureScript frontend](../../README.md#purescript-frontend)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)

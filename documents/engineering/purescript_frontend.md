# PureScript Frontend

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md, ../../DEVELOPMENT_PLAN/system-components.md
**Generated sections**: none

> **Purpose**: Project-specific PureScript frontend doctrine for jitML — the
> current local PureScript shell, browser-contract renderer, bundle/panel
> metadata, demo-route manifest, Playwright scaffold, demo deployment template,
> and `jitml-demo` HTTP server, plus the target Halogen / live WebSocket /
> compiled-bundle work that has not landed yet.

## Stack

| Component | Current status | Owning module / path |
|-----------|----------------|----------------------|
| PureScript entrypoint | Minimal shell | `web/src/Main.purs` |
| npm scripts | `build`, `test`, `format` wrappers declared; no checked-in `spago.yaml` yet | `web/package.json` |
| Contract renderer | Local bridge-compatible renderer | `src/JitML/Web/Contracts.hs` |
| Generated contracts | Checked-in generated file protected by `trackingGeneratedPaths` | `web/src/Generated/Contracts.purs` |
| Bundle/panel/demo-route metadata | Local Haskell metadata | `src/JitML/Web/Bundle.hs` |
| Demo HTTP routes | Local Haskell HTTP server for the current route/API surface | `src/JitML/Web/Server.hs` |
| PureScript smoke file | Minimal shell | `web/test/Main.purs` |
| Playwright | Scaffold spec only; not invoked by current `jitml-e2e` body | `playwright/jitml-demo.spec.ts` |
| Demo executable | Status line plus HTTP server | `app/Demo.hs`, `src/JitML/App.hs` |

The PureScript stack is project-specific (the doctrine does not address
browser-side code). Target npm / spago / Playwright invocations flow through
the typed `Subprocess` boundary from doctrine `Architecture → Subprocesses as
Typed Values`; the current checked-in Cabal bodies only perform local smoke
checks.

## Layout

Current checked-in layout:

```text
web/
├── package.json
├── src/
│   ├── Main.purs
│   └── Generated/
│       └── Contracts.purs
└── test/
    └── Main.purs

playwright/
└── jitml-demo.spec.ts
```

Target layout adds `web/spago.yaml`, Halogen root/router/panel modules,
compiled bundle output under `web/dist/`, and a fuller Playwright project once
the complete panels exist.

## Current Local Surface

The current worktree contains a minimal `web/src/Main.purs`, generated
`web/src/Generated/Contracts.purs`, `web/test/Main.purs`,
`src/JitML/Web/Contracts.hs`, and `src/JitML/Web/Bundle.hs`. `Web.Bundle`
records the bundle output paths, the MNIST, image-upload, Connect 4, and RL
trajectory panel metadata, the `demoStatusLine`, and the local demo route
manifest for `/`, `/api`, and `/api/ws`. `src/JitML/Web/Server.hs` serves the
current local HTTP surface for `/`, `/api`, `/api/inference`, `/api/images`,
`/api/connect4/move`, and `/api/ws`. A compiled `web/dist/` bundle, Halogen
panel modules, and live WebSocket proxying remain target runtime work.

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

Typed training, RL, AlphaZero, inference, image-upload, Connect 4, and tuning
payload ADTs remain target browser-contract work.

## Panels

| Panel | URL | REST handler | WebSocket subscription |
|-------|-----|--------------|------------------------|
| MNIST | `/mnist` | `POST /api/inference` | — |
| CIFAR / ImageNet | `/cifar`, `/imagenet` | `POST /api/images` | — |
| Connect 4 | `/connect4` | `POST /api/connect4/move` | — |
| RL trajectory | `/rl/<run-id>` | — | `/api/ws` (proxies `rl.event.<mode>`) |
| Training | `/training/<run-id>` | — | `/api/ws` (proxies `training.event.<mode>`) |
| Tune | `/tune/<sweep-id>` | — | `/api/ws` (proxies `tune.event.<mode>`) |

## REST and WebSocket Surface

The current local HTTP handlers live in `src/JitML/Web/Server.hs`; they provide
deterministic responses for the API index, inference, upload acknowledgement,
Connect 4 move, and metrics stream routes. The current worktree does not
contain a dedicated live `src/JitML/Web/Ws.hs` proxy; live WebSocket forwarding
from Pulsar event topics remains target runtime validation.

| Surface | Method | Path | Payload type |
|---------|--------|------|--------------|
| Inference | POST | `/api/inference` | `InferenceRun` |
| Image upload | POST | `/api/images` | `UploadImage` |
| Connect 4 move | POST | `/api/connect4/move` | `Connect4Move` |
| Live event WS | GET | `/api/ws?topic=…&substrate=…` | typed event envelopes |
| Checkpoint browse | GET | `/api/checkpoints/<experiment-hash>` | manifest list (cross-link to TB sidecars) |

## `jitml-demo` HTTP Server

`app/Demo.hs` is a six-line shim into `App.demoMain`. The current `demoMain`
prints `demoStatusLine` from `src/JitML/Web/Bundle.hs`:
`jitml-demo: serving generated frontend contract surface`, then starts the
low-level HTTP listener from `src/JitML/Web/Server.hs`. It serves the current
local route/API surface; target work swaps in the compiled bundle from
`web/dist/` and a live WebSocket proxy at `/api/ws`.

The `Deployment/jitml-demo` template (Sprint `4.1`) is populated with the
demo image, `jitml-demo` command, and `PORT=80`. HTTPRoutes for `/`, `/api`,
`/api/ws` (Sprint `3.4`) point at `jitml-demo:80`.

## Playwright E2E

`playwright/jitml-demo.spec.ts` is the current TypeScript Playwright scaffold.
The current `jitml-e2e` Cabal body does not invoke Playwright. Target work grows
this into one spec per panel covering the golden user flow:

- MNIST: draw a digit, assert top-1 matches the expected class against a
  fixture model.
- CIFAR: upload a fixture image, assert classification.
- Connect 4: play a fixture game against the AlphaZero policy and assert
  move sequence matches a golden game.
- RL trajectory: trigger a synthetic RL run and assert the trajectory panel
  renders frames.
- Training / Tune: trigger a synthetic training run and assert the live
  metric panel updates.

Target Playwright execution runs through the typed `Subprocess` boundary. The
target `jitml-e2e` stanza invokes the Playwright suite as part of its
end-to-end run; Playwright belongs to the doctrine's Pulumi-Orchestrated
Infrastructure test category and does not have its own Cabal stanza.

## Cross-References

- [../../README.md → PureScript frontend](../../README.md#purescript-frontend)
- [daemon_architecture.md](daemon_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md](../../DEVELOPMENT_PLAN/phase-11-purescript-frontend-and-demo.md)
- [../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md](../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md)

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

> **Purpose**: Stand up the PureScript frontend under `web/` (Halogen
> components, generated browser contracts from `purescript-bridge`,
> `purescript-spec` unit tests, Playwright E2E suite, bundle output), the
> interactive panels (live MNIST handwriting, CIFAR/ImageNet upload,
> AlphaZero-vs-human Connect 4, RL trajectory render), the REST surfaces, and
> the `jitml-demo` HTTP server shim that serves the bundle plus the inference
> REST surface.

## Phase Status

⏸️ **Blocked** on Phase `10` closure. The frontend's REST surfaces consume
the inference-only read path; the demo HTTP server (`jitml-demo`) is the
sibling binary that shares the `src/JitML/` library.

## Phase Summary

This phase delivers the browser-side stack: a Halogen application generated
from typed Haskell ADTs in `src/JitML/Web/Contracts.hs` via
`purescript-bridge`, panel components for the demo flows, REST surfaces for
each interactive panel, the bundle output in `web/dist/`, and the
`jitml-demo` HTTP server shim that serves the bundle plus the inference REST
surface. The PureScript stack is project-specific (the doctrine does not
address browser-side code); the build chain wraps every npm/spago invocation
through the typed `Subprocess` boundary from Phase `1`.

## Sprint 11.1: Halogen Application Scaffold ⏸️

**Status**: Blocked
**Blocked by**: phase-10
**Implementation**: `web/spago.yaml`, `web/src/Main.purs`,
`web/src/App.purs`, `web/src/Router.purs`,
`docker/playwright.Dockerfile`,
`src/JitML/Frontend/Build.hs`
**Docs to update**: `documents/engineering/purescript_frontend.md`

### Objective

Stand up the Halogen application skeleton, the spago dependency manifest,
the bundle output toolchain, and the Haskell-side build wrapper that drives
the spago invocation through the typed `Subprocess` boundary.

### Deliverables

- `web/spago.yaml` declares the Halogen + halogen-store + affjax deps at
  pinned versions.
- `web/src/Main.purs` boots the Halogen runtime and mounts the `App`
  component.
- `web/src/App.purs` is the root component carrying the panel registry.
- `web/src/Router.purs` routes the panels.
- `src/JitML/Frontend/Build.hs` invokes `spago build` and the bundler
  through the typed `Subprocess` boundary; the bundle is written to
  `web/dist/`.
- `docker/playwright.Dockerfile` is the separate Playwright runner image
  (Sprint `11.6`).

### Validation

1. `spago build --package-set <pinned-set>` succeeds against `web/`.
2. The built bundle loads in a smoke headless browser harness.

## Sprint 11.2: Browser-Contract ADTs and `purescript-bridge` Generation ⏸️

**Status**: Blocked
**Blocked by**: 11.1
**Implementation**: `src/JitML/Web/Contracts.hs`,
`src/JitML/Web/Bridge.hs`, `web/src/Generated/Contracts.purs`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/code_quality.md`

### Objective

Stand up the browser-contract ADTs in `src/JitML/Web/Contracts.hs` and the
`purescript-bridge` generator that produces `web/src/Generated/Contracts.purs`.
Sprint `1.3` reserved the future generated-path pattern; this sprint adds the
concrete `trackingGeneratedPaths` entry so hand edits fail `jitml lint files`.

### Deliverables

- `src/JitML/Web/Contracts.hs` enumerates every ADT crossed by the REST /
  WebSocket surface: training-run lifecycle events, RL episode events,
  AlphaZero arena events, MNIST inference request/response, CIFAR upload
  request/response, Connect 4 board / move / game state, trial events.
- `src/JitML/Web/Bridge.hs` invokes `purescript-bridge` to generate
  `web/src/Generated/Contracts.purs`; the generation is wrapped in the
  `jitml docs generate` reconciler.
- `web/src/Generated/Contracts.purs` is promoted from
  `futureTrackingGeneratedPathPatterns` into an active `trackingGeneratedPaths`
  entry; hand edits fail `jitml lint files`.

### Validation

1. `jitml docs generate` produces the same `Contracts.purs` byte-for-byte
   across runs.
2. Hand-editing `Contracts.purs` surfaces `AppError DocsCheckDrift` on the
   next `jitml lint files`.

## Sprint 11.3: `jitml-purescript-style` Stanza (`purescript-spec` + `purs format`) ⏸️

**Status**: Blocked
**Blocked by**: 11.2
**Implementation**: `web/test/Main.purs`, `web/test/Spec.purs`,
`web/test/Panels/`, `test/purescript-style/`,
`jitml.cabal` (the `jitml-purescript-style` stanza)
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Replace the current `jitml-purescript-style` sentinel body from Sprint `1.1`
with the Lint (project-specific) stanza per doctrine §Test Organization's
project-specific stanzas allowance — bundling the PureScript `purs format`
round-trip with the `purescript-spec` smoke tests, both run through the typed
`Subprocess` boundary.

### Deliverables

- `web/test/Main.purs` boots the spec runner.
- One test module per panel exercises the typed event handling against
  fixture payloads.
- `purs format` round-trip lint asserts every `web/src/**/*.purs` and
  `web/test/**/*.purs` file is unchanged by `purs format` (temp-file
  round-trip byte equality, mirroring the `cabal format` discipline in the
  `jitml-haskell-style` stanza).
- The `jitml-purescript-style` Cabal stanza shells out to `spago test` and
  `purs format` through the typed `Subprocess` boundary.

### Validation

1. `cabal test jitml-purescript-style` exits `0`.
2. The panel tests use only the generated contract types — hand-defined
   shapes are forbidden.
3. Introducing any non-formatted PureScript source fails the round-trip
   check with a structured diagnostic.

## Sprint 11.4: Interactive Panels and REST Surfaces ⏸️

**Status**: Blocked
**Blocked by**: 11.2, 10.4
**Implementation**: `web/src/Panels/Mnist.purs`,
`web/src/Panels/Cifar.purs`, `web/src/Panels/Connect4.purs`,
`web/src/Panels/Rl.purs`, `web/src/Panels/Training.purs`,
`web/src/Panels/Tune.purs`,
`src/JitML/Web/Rest.hs`,
`src/JitML/Web/Ws.hs`
**Docs to update**: `documents/engineering/purescript_frontend.md`

### Objective

Land the interactive panels and the REST + WebSocket surfaces they consume:
- training-run lifecycle (start/pause/stop, live metric stream),
- live MNIST inference (touchpad input → inference response),
- CIFAR/ImageNet upload (image → top-K labels),
- AlphaZero-vs-human Connect 4,
- RL trajectory render (live episode replay).

### Deliverables

- `Mnist.purs` exposes a touchpad canvas; on stroke commit, posts to
  `/api/inference/mnist` and renders the top-K classes.
- `Cifar.purs` exposes a file-upload widget; posts to
  `/api/inference/cifar` (or `/api/inference/imagenet`) and renders the
  classification.
- `Connect4.purs` exposes the game board, posts moves to
  `/api/games/connect4/move`, receives the AlphaZero policy via
  `/api/games/connect4/move` response (which references a checkpoint
  manifest SHA per [../README.md → AlphaZero-style self-play and persistent
  MCTS state](../README.md#alphazero-style-self-play-and-persistent-mcts-state)).
- `Rl.purs` subscribes to `/api/ws` (Pulsar `rl.event.<mode>` proxied) and
  renders trajectory frames.
- `Training.purs` subscribes to `training.event.<mode>` for live curves.
- `Tune.purs` subscribes to `tune.event.<mode>` for live trial telemetry.
- `src/JitML/Web/Rest.hs` declares the typed REST handlers (consumed by
  `jitml-demo`).
- `src/JitML/Web/Ws.hs` declares the typed WebSocket handler that proxies
  the Pulsar `rl.event.*` / `training.event.*` / `tune.event.*` /
  `inference.result.*` topics through `/api/ws`.

### Validation

1. `purescript-spec` exercises each panel's event handling against fixture
   payloads.
2. The REST handlers round-trip through the generated contract types.

## Sprint 11.5: `jitml-demo` HTTP Server ⏸️

**Status**: Blocked
**Blocked by**: 11.1, 11.4
**Implementation**: `app/Demo.hs`, `src/JitML/Demo/Server.hs`,
`src/JitML/Demo/Bundle.hs`,
`chart/templates/deployment-jitml-demo.yaml`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Stand up the `jitml-demo` sibling HTTP server shim that serves the
PureScript bundle plus the typed REST surface.

### Deliverables

- `app/Demo.hs` is a six-line shim into `App.demoMain`.
- `src/JitML/Demo/Server.hs` is the WAI/Warp HTTP server: serves the
  static bundle from `web/dist/` at `/`, mounts the typed REST handlers
  at `/api/`, mounts the WebSocket handler at `/api/ws`.
- `src/JitML/Demo/Bundle.hs` resolves the bundle path (in-pod via
  `embedDir`-style baking; in-dev via `web/dist/`).
- The `Deployment/jitml-demo` template (Sprint `4.1` placeholder) is now
  populated with the demo image.
- HTTPRoutes for `/`, `/api`, `/api/ws` (Sprint `3.4`) point at
  `jitml-demo:80`.

### Validation

1. `jitml-demo --port 8080` serves the bundle at `127.0.0.1:8080/` and
   responds to `/api/inference/mnist` against a fixture model.
2. After `jitml bootstrap --<substrate>`, `127.0.0.1:<edge-port>/` reaches the demo
   bundle through the Envoy listener.

## Sprint 11.6: Playwright E2E Suite ⏸️

**Status**: Blocked
**Blocked by**: 11.5
**Implementation**: `web/playwright/`,
`web/playwright/playwright.config.ts`,
`web/playwright/tests/`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Land the Playwright E2E suite covering every interactive panel.

### Deliverables

- `web/playwright/` is a TypeScript Playwright project.
- One spec per panel covers the golden user flow:
  - MNIST: draw a digit, assert top-1 matches the expected class against a
    fixture model.
  - CIFAR: upload a fixture image, assert classification.
  - Connect 4: play a fixture game against the AlphaZero policy and assert
    move sequence matches a golden game.
  - RL trajectory: trigger a synthetic RL run and assert the trajectory
    panel renders frames.
  - Training/Tune: trigger a synthetic training run and assert the live
    metric panel updates.
- Playwright runs through `docker/playwright.Dockerfile` (Sprint `11.1`)
  via the typed `Subprocess` boundary.
- The `jitml-e2e` stanza (Phase `12`) invokes the Playwright suite as part
  of its end-to-end run.

### Validation

1. `cabal test jitml-e2e` (after Phase `12` lands) drives the Playwright
   suite against the ephemeral Kind stack.
2. Each panel's golden flow asserts against the typed contract payloads.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (every sprint — every `spago` / `npm` / Playwright invocation flows through `Subprocess`)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 11.2 — generated PureScript contracts)
- [../HASKELL_CLI_TOOL.md → Project Structure](../HASKELL_CLI_TOOL.md) (Sprint 11.5 — six-line `app/Demo.hs` shim)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (Sprint 11.5 — demo server uses `Env`)
- [../HASKELL_CLI_TOOL.md → Test Categories](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — Lint (project-specific) via `jitml-purescript-style`; Sprint 11.6 — Playwright belongs to the Pulumi-Orchestrated Infrastructure category via `jitml-e2e`)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — project-specific stanza under §Test Organization → project-specific stanzas)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/purescript_frontend.md` — full Halogen + spago
  layout, `purescript-bridge` generation, panel inventory, REST / WS
  surface, Playwright suite.
- `documents/engineering/code_quality.md` — `trackingGeneratedPaths` entry
  for `web/src/Generated/Contracts.purs`.
- `documents/engineering/daemon_architecture.md` — `jitml-demo` server
  shape and its place in the deployment.
- `documents/engineering/unit_testing_policy.md` — Playwright belongs to
  the doctrine's Pulumi-Orchestrated Infrastructure test category and runs
  inside the `jitml-e2e` stanza; PureScript lint + `purescript-spec` smoke
  tests are owned by the `jitml-purescript-style` stanza (Sprint `11.3`).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → Frontend Components` rows move from `⏸️ Blocked`
  through `🔄 Active` to `✅ Done`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

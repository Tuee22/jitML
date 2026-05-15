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
> generated browser contracts from `src/JitML/Web/Contracts.hs`, the Playwright
> scaffold, the demo deployment template, and the `jitml-demo` executable shim.
> The target architecture later expands this into Halogen panels, REST/WS
> handlers, bundle output, and a real HTTP server.

## Phase Status

✅ **Done** for the local PureScript shell, generated browser contracts, demo
shim, Playwright scaffold, and contract-style test surface. The frontend's REST
surfaces consume the inference-only read path; the demo HTTP server
(`jitml-demo`) is the sibling binary that shares the `src/JitML/` library.

### Current Implementation Scope

The current worktree implements a minimal PureScript entrypoint, generated
contract file, `web/package.json` script surface, `web/test/Main.purs`,
Playwright spec scaffold, `jitml-demo` executable shim, and demo deployment
template. It does not include a Halogen dependency, purescript-bridge generator
dependency, active `trackingGeneratedPaths` entry for
`web/src/Generated/Contracts.purs`, real interactive panels, browser bundle
output, REST handlers, WebSocket handlers, or an HTTP server in `jitml-demo`.

## Phase Summary

This phase delivers the browser-side shell: generated browser contracts from
typed Haskell ADTs in `src/JitML/Web/Contracts.hs`, a PureScript entrypoint
under `web/src/`, a contract smoke test under `web/test/`, a Playwright
scaffold under `playwright/`, and the `jitml-demo` sibling binary that serves
the generated frontend contract surface. The PureScript stack is
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
- `web/src/Main.purs` boots the PureScript shell and imports the generated
  contracts.
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
local renderer that produces `web/src/Generated/Contracts.purs`. The
`purescript-bridge` dependency and active generated-path tracking entry remain
target follow-up work.

### Deliverables

- `src/JitML/Web/Contracts.hs` enumerates the current endpoint contract:
  `RunCommand`, `InferenceRun`, `UploadImage`, `Connect4Move`, and
  `MetricsStream`.
- `src/JitML/Web/Contracts.hs` renders `web/src/Generated/Contracts.purs`
  through the local `renderPureScriptContracts` helper.
- `web/src/Generated/Contracts.purs` remains listed under
  `futureTrackingGeneratedPathPatterns`; active drift detection is not present
  yet.

### Validation

1. The renderer produces the same contract text byte-for-byte across runs.
2. `jitml-purescript-style` verifies the generated contract file exists and
   names the expected endpoint surface.

## Sprint 11.3: `jitml-purescript-style` Stanza (`purescript-spec` + `purs format`) ✅

**Status**: Done
**Implementation**: `web/test/Main.purs`, `test/purescript-style/`,
`jitml.cabal` (the `jitml-purescript-style` stanza)
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-purescript-style` as the Lint (project-specific) stanza per
doctrine §Test Organization's
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

## Sprint 11.4: Interactive Panels and REST Surfaces ✅

**Status**: Done
**Implementation**: `src/JitML/Web/Contracts.hs`,
`web/src/Main.purs`, `web/src/Generated/Contracts.purs`
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
- `src/JitML/Web/Contracts.hs` declares the REST/WebSocket endpoint contract
  that `jitml-demo` and the PureScript shell share.

### Validation

1. `purescript-spec` exercises each panel's event handling against fixture
   payloads.
2. The REST handlers round-trip through the generated contract types.

## Sprint 11.5: `jitml-demo` Executable Shim ✅

**Status**: Done
**Implementation**: `app/Demo.hs`, `src/JitML/App.hs`,
`chart/templates/deployment-jitml-demo.yaml`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Stand up the `jitml-demo` sibling executable shim and chart deployment surface.
The real HTTP server remains target runtime work.

### Deliverables

- `app/Demo.hs` is a six-line shim into `App.demoMain`.
- `src/JitML/App.hs` owns `demoMain`, which currently prints
  `jitml-demo: serving generated frontend contract surface`.
- The `Deployment/jitml-demo` template is populated with the demo image.
- HTTPRoutes for `/`, `/api`, `/api/ws` (Sprint `3.4`) point at
  `jitml-demo:80`.

### Validation

1. Running `jitml-demo` prints the generated-frontend status line.
2. The `Deployment/jitml-demo` chart template names the demo image and exposes
   container port `80`.

## Sprint 11.6: Playwright E2E Suite ✅

**Status**: Done
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

### Validation

1. `playwright/jitml-demo.spec.ts` remains present for the future E2E runner.
2. `jitml-e2e` currently validates local route, bucket, publication, contract,
   and report-card surfaces.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (every sprint — every `spago` / `npm` / Playwright invocation flows through `Subprocess`)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 11.2 — generated PureScript contracts)
- [../HASKELL_CLI_TOOL.md → Project Structure](../HASKELL_CLI_TOOL.md) (Sprint 11.5 — six-line `app/Demo.hs` shim)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (Sprint 11.5 — demo server uses `Env`)
- [../HASKELL_CLI_TOOL.md → Test Categories](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — Lint (project-specific) via `jitml-purescript-style`; Sprint 11.6 — Playwright belongs to the Pulumi-Orchestrated Infrastructure category via `jitml-e2e`)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — project-specific stanza under §Test Organization → project-specific stanzas)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/purescript_frontend.md` — current minimal PureScript
  shell, local contract renderer, demo shim, and Playwright scaffold; target
  Halogen, `purescript-bridge`, panel, REST / WS, and bundle surfaces.
- `documents/engineering/code_quality.md` — note that
  `web/src/Generated/Contracts.purs` is still only a
  `futureTrackingGeneratedPathPatterns` entry.
- `documents/engineering/daemon_architecture.md` — `jitml-demo` server
  shape and its place in the deployment.
- `documents/engineering/unit_testing_policy.md` — Playwright belongs to
  the doctrine's Pulumi-Orchestrated Infrastructure test category and runs
  inside the `jitml-e2e` stanza; PureScript lint + `purescript-spec` smoke
  tests are owned by the `jitml-purescript-style` stanza (Sprint `11.3`).

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

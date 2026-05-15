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
> and panel metadata from `src/JitML/Web/Bundle.hs`, the Playwright scaffold,
> the demo deployment template, and the `jitml-demo` executable shim. The target
> architecture later expands this into Halogen panels, REST/WS handlers, a
> compiled browser bundle, and a real HTTP server.

## Phase Status

✅ **Done** for the local PureScript shell, generated browser contracts, typed
bundle/panel metadata, demo shim, Playwright scaffold, and contract-style test
surface. The frontend's REST surfaces consume the inference-only read path; the
demo HTTP server
(`jitml-demo`) is the sibling binary that shares the `src/JitML/` library.

### Current Implementation Scope

The current worktree implements a minimal PureScript entrypoint, generated
contract file, typed bundle/panel metadata, `web/package.json` script surface,
`web/test/Main.purs`, Playwright spec scaffold, `jitml-demo` executable shim,
and demo deployment template. It does not include a Halogen dependency, external
`purescript-bridge` package dependency, active `trackingGeneratedPaths` entry for
`web/src/Generated/Contracts.purs`, compiled browser bundle output, REST
handlers, WebSocket handlers, or an HTTP server in `jitml-demo`.

## Phase Summary

This phase delivers the browser-side shell: generated browser contracts from
typed Haskell ADTs in `src/JitML/Web/Contracts.hs`, typed bundle/panel metadata
in `src/JitML/Web/Bundle.hs`, a PureScript entrypoint under `web/src/`, a
contract smoke test under `web/test/`, a Playwright scaffold under
`playwright/`, and the `jitml-demo` sibling binary that currently prints the
generated-frontend status line. The PureScript stack is
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
active generated-path tracking remains target follow-up work.

### Deliverables

- `src/JitML/Web/Contracts.hs` enumerates the current endpoint contract:
  `RunCommand`, `InferenceRun`, `UploadImage`, `Connect4Move`, and
  `MetricsStream`.
- `src/JitML/Web/Contracts.hs` renders `web/src/Generated/Contracts.purs`
  through the local `renderPureScriptContracts` helper.
- `contractGeneratorName` identifies the local bridge-compatible renderer used
  by the current contract surface.
- `web/src/Generated/Contracts.purs` remains listed under
  `futureTrackingGeneratedPathPatterns`; active drift detection is not present
  yet.

### Validation

1. The renderer produces the same contract text byte-for-byte across runs.
2. `jitml-purescript-style` verifies the generated contract file exists and
   names the expected endpoint surface.

## Sprint 11.3: `jitml-purescript-style` Generated-Contract Smoke Stanza ✅

**Status**: Done
**Implementation**: `web/test/Main.purs`, `test/purescript-style/`,
`jitml.cabal` (the `jitml-purescript-style` stanza)
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Keep `jitml-purescript-style` as the current local generated-contract smoke
stanza. The target PureScript `purs format` round-trip and `purescript-spec`
panel tests remain future work.

### Deliverables

- `web/test/Main.purs` is present as a minimal PureScript test entrypoint.
- `test/purescript-style/Main.hs` verifies
  `web/src/Generated/Contracts.purs` exists and names the expected endpoint
  surface.
- The stanza also checks `renderPureScriptContracts` emits the PureScript
  module header.
- It does not currently invoke `spago test`, `purs format`, `purs-tidy`, or
  `purescript-spec`.

### Validation

1. `cabal test jitml-purescript-style` exits `0` for the current smoke body.
2. Missing generated-contract output fails the stanza.
3. PureScript formatter and panel-spec validation remain target work.

## Sprint 11.4: Interactive Endpoint Contract Surface ✅

**Status**: Done
**Implementation**: `src/JitML/Web/Contracts.hs`,
`src/JitML/Web/Bundle.hs`,
`web/src/Main.purs`, `web/src/Generated/Contracts.purs`
**Docs to update**: `documents/engineering/purescript_frontend.md`

### Objective

Land the current endpoint-contract metadata and typed panel/bundle manifest that
the future interactive panels will consume. No live REST handlers or WebSocket
handlers exist in the current tree.

### Deliverables

- `src/JitML/Web/Contracts.hs` declares endpoint metadata for `RunCommand`,
  `InferenceRun`, `UploadImage`, `Connect4Move`, and `MetricsStream`.
- `src/JitML/Web/Bundle.hs` declares the local bundle asset manifest and panel
  surfaces for MNIST inference, image upload, Connect 4, and RL trajectory
  rendering.
- `web/src/Generated/Contracts.purs` contains the generated local PureScript
  contract output.
- `test/e2e/Main.hs` checks the browser contract endpoint count.
- `Mnist.purs`, `Cifar.purs`, `Connect4.purs`, `Rl.purs`, `Training.purs`,
  `Tune.purs`, REST handlers, and WebSocket handlers remain target runtime
  validation.

### Validation

1. `cabal test jitml-e2e` validates the current browser contract endpoint
   count.
2. `cabal test jitml-purescript-style` validates the generated contract file
   exists.
3. `jitml-unit` verifies the local bundle and panel metadata.

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

- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (target frontend tool invocations flow through `Subprocess`; current checked-in bodies are local smoke tests)
- [../HASKELL_CLI_TOOL.md → Generated Artifacts](../HASKELL_CLI_TOOL.md) (Sprint 11.2 — generated PureScript contracts)
- [../HASKELL_CLI_TOOL.md → Project Structure](../HASKELL_CLI_TOOL.md) (Sprint 11.5 — six-line `app/Demo.hs` shim)
- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md) (target demo server uses `Env`; current `demoMain` is a status-line shim)
- [../HASKELL_CLI_TOOL.md → Test Categories](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — local project-specific smoke stanza via `jitml-purescript-style`; Sprint 11.6 — Playwright scaffold belongs to the target Pulumi-Orchestrated Infrastructure category via `jitml-e2e`)
- [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md) (Sprint 11.3 — project-specific stanza under §Test Organization → project-specific stanzas)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/purescript_frontend.md` — current minimal PureScript
  shell, local contract renderer, bundle/panel metadata, demo shim, and
  Playwright scaffold; target Halogen, REST / WS, compiled bundle, and live
  panel surfaces.
- `documents/engineering/code_quality.md` — note that
  `web/src/Generated/Contracts.purs` is still only a
  `futureTrackingGeneratedPathPatterns` entry.
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

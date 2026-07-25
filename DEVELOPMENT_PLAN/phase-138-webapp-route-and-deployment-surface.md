# Phase 138: Webapp Route and Deployment Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Webapp Route and Deployment Surface. Single-session phase migrated from legacy Sprint 11.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 138.1: Webapp Route and Deployment Surface [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. The live
`/api/ws` proxy bridging browser clients to Pulsar event topics
migrated to Phase `15` Sprint `15.13`.
**Implementation**: `src/JitML/App.hs`, `chart/local/jitml-demo/templates/deployment.yaml`
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Stand up the demo route manifest, HTTP server, and chart deployment surface.
Sprint `11.10` folds the historical two-binary shape into the Webapp role
workload, which is the current owned surface.

### Deliverables

- `src/JitML/App.hs` owns the Webapp role entrypoint, which starts
  `WebServer.serveDemoWithBridgeEndpointWithRuntime`.
- `src/JitML/Web/Server.hs` serves the frontend/API route
  surface.
- `src/JitML/Web/Bundle.hs` declares `demoRoutes` for the full current
  local HTTP surface: `/`, `/api`, `/api/inference`, `/api/images`,
  `/api/connect4/move`, `/api/ws`, `/api/ws/training`, and `/api/ws/tune`.
- The `Deployment/jitml-demo` local chart runs `jitml service` with
  `activeRole = Webapp`, using the mounted typed Dhall config so Envoy can
  reach the pod IP.
- HTTPRoutes for `/`, `/api`, `/api/ws` (Sprint `3.4`) point at
  `jitml-demo:80`.

### Validation

1. Running `jitml service` with a Webapp `BootConfig` prints the generated
   frontend status line and starts the HTTP listener.
2. The `Deployment/jitml-demo` local chart template names the demo image and
   exposes container port `80`.
3. `jitml-e2e` verifies the demo route manifest covers `/`, `/api`, and
   `/api/ws`, that the deployment starts `jitml service --config
   /etc/jitml/BootConfig.dhall`, and that a one-shot demo HTTP server serves the
   API index. The same stanza verifies the typed demo route manifest covers the
   current local API surface.
4. The old `jitml-demo --host ... --port ...` binary validation is superseded by
   Sprint `11.10`; the current live validation is the `jitml-demo` Webapp pod
   serving `/` and `/bundle/main.js` through the edge route.
5. Later live validation: Phase `15` validated the live `/api/ws` proxy
   against daemon metric/event Pulsar topics and Phase `17` validated the
   live-only Playwright matrix after removing offline fallbacks.

### Remaining Work

- None remaining for Sprint `11.4`. The browser-loadable bundle path is
  `web/dist/Main/bundle.js`, the demo route appends `/bundle/main.js`
  when that file exists, and later Phase `15` / Phase `17` work closed
  the live WebSocket and fallback-removal surfaces.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 140: SPA Portals Home and Shared Header

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: SPA Portals Home and Shared Header. Single-session phase migrated from legacy Sprint 11.7 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 140.1: SPA Portals Home and Shared Header [✅ Done]

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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

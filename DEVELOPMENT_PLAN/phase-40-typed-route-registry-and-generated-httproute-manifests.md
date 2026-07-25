# Phase 40: Typed Route Registry and Generated `HTTPRoute` Manifests

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Route Registry and Generated HTTPRoute Manifests. Single-session phase migrated from legacy Sprint 3.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 40.1: Typed Route Registry and Generated `HTTPRoute` Manifests [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Routes.hs`, `chart/templates/httproute-*.yaml`,
`src/JitML/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Stand up the typed route registry as the source of truth for every `HTTPRoute`
resource. Hand-edited HTTPRoute YAML in the chart is hlint-forbidden.

### Deliverables

- `src/JitML/Routes.hs` enumerates every routed surface from
  [system-components.md → CLI Doctrine
  Components](system-components.md#cli-doctrine-components) and the README's
  edge route table:
  - `/` → `jitml-demo:80`
  - `/api` → `jitml-demo:80`
  - `/api/ws` → `jitml-demo:80` (WebSocket)
  - `/tensorboard` → `tensorboard:80` (rewrite to `/`)
  - `/grafana` → `kube-prometheus-stack-grafana:80` (rewrite to `/`)
  - `/prometheus` → `kube-prometheus-stack-prometheus:9090` (rewrite to `/`)
  - `/harbor` → `harbor:80` (rewrite to `/`)
  - `/harbor/api` → `harbor:80` (rewrite to `/api`)
  - `/v2` → `harbor:80`
  - `/service` → `harbor:80`
  - `/minio/console` → `minio:9001` (rewrite to `/`)
  - `/minio/s3` → `minio:9000` (rewrite to `/`)
  - `/pulsar/admin` → `pulsar-proxy:80` (rewrite to `/admin`)
  - `/pulsar/ws` → `pulsar-broker:8080` (WebSocket; rewrite to `/ws`)
- `chart/templates/httproute-*.yaml` is rendered from the registry, tracked by
  `trackingGeneratedPaths`, and checked by `jitml lint chart`.
- `documents/engineering/cluster_topology.md` carries the route table inside a
  `<!-- jitml:cluster.routes:start -->` / `<!-- jitml:cluster.routes:end -->`
  block, regenerated from the registry.
- `src/JitML/Lint/Chart.hs` enforces route/manifest shape against
  `src/JitML/Routes.hs` so generated HTTPRoute YAML stays aligned.

### Validation

1. `jitml lint chart` compares `chart/templates/httproute-*.yaml` against
   `src/JitML/Routes.hs`.
2. `test/integration/Main.hs` verifies route registry rendering covers
   the registered routes.
3. Live route reachability through the Envoy listener is validated by Sprint
   `3.5`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

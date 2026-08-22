# Phase 269: `registry:2` Migration and Harbor Deprecation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Replace Harbor with a single `registry:2` deployment on the existing
> MinIO S3 backend, and remove Harbor and its Postgres from the chart, the code,
> the tests, and the governed documents.

## Phase State

🔄 **Active** (2026-08-22). The platform's container registry is `registry:2`
serving the Docker Registry v2 API from the MinIO bucket Harbor already used, so
no blob migration is required and previously pushed layers stay addressable.
Harbor is removed rather than deprecated in place: the chart release, its portal,
core, jobservice, nginx, Redis and Trivy components, its Percona Postgres cluster,
and the bootstrap ordering that sequenced them are all deleted.

The registry surface the daemon actually consumes is small — push, pull, tag,
existence, and catalogue listing — and everything Docker-shaped in it is already
registry-agnostic. Only three calls were Harbor-proprietary, and each has a direct
Registry v2 equivalent; the fourth, `docker login`, disappears because this local
single-node stack runs the registry without authentication.

Removing Harbor also empties
[`postgresRegistry`](../src/JitML/Cluster/PostgresRegistry.hs): `harbor-pg` was
its only row, so the Percona operator, both of its persistent volumes, and the
schema-ownership grant step exist for no remaining consumer.

## Sprint 269.1: `registry:2` Migration and Harbor Deprecation [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Service/RegistrySubprocess.hs`,
`src/JitML/Service/Capabilities.hs`, `src/JitML/Service/Clients.hs`,
`src/JitML/Service/BootConfig.hs`, `src/JitML/Cluster/Helm.hs`,
`src/JitML/Cluster/Readiness.hs`, `src/JitML/Cluster/PostgresRegistry.hs`,
`src/JitML/Cluster/Storage.hs`, `src/JitML/Routes.hs`, `src/JitML/Bootstrap.hs`,
`src/JitML/Docs/Check.hs`, `chart/`
**Docs to update**: `../documents/engineering/cluster_topology.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/cli_command_surface.md`,
`../documents/engineering/purescript_frontend.md`,
`../documents/engineering/unit_testing_policy.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

One `registry:2` Deployment is the platform's image registry. It serves the
Registry v2 API at the edge `/v2` route, stores blobs in the MinIO bucket Harbor
already wrote to, and requires no authentication on the local stack. Harbor, its
Postgres, and every reference to them are removed from the chart, the typed
cluster model, the daemon capability surface, the tests, and the governed
documents.

### Deliverables

- A `registry:2` Deployment and Service replace the Harbor chart release, backed
  by the existing MinIO S3 bucket so no blob migration is needed.
- `HasImageRegistry` replaces `HasHarbor`, and `RegistrySubprocess` implements
  catalogue listing, existence, and tagging against the Registry v2 API:
  `GET /v2/_catalog`, `HEAD /v2/{name}/manifests/{ref}` for existence and the
  `Docker-Content-Digest` header, and a manifest re-`PUT` for tagging, which
  Registry v2 has no dedicated API for. Push, pull, tag, and manifest inspection
  stay plain `docker` invocations because they are registry-agnostic.
- `postgresRegistry` is empty, the Percona operator release and both `harbor-pg`
  persistent volumes are gone, and the bootstrap's registry phase sequences MinIO
  and its bucket check straight into the registry rollout with no schema grant.
- The route registry drops `harbor-portal`, `harbor-api`, and `harbor-service`,
  and `/v2` points at the registry Service. The generated admin portals and the
  Playwright product matrix drop the Harbor portal with them.
- `jitml docs check` resolves every `phase-N-slug.md` citation in a governed
  document, so a renumber fails closed instead of leaving dangling references.

### Validation

```bash
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml-cuda jitml test all --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --live --linux-cuda
./bootstrap/linux-cuda.sh up
./bootstrap/linux-cuda.sh test
./bootstrap/linux-cuda.sh down
```

The bootstrap lifecycle is part of this gate rather than an afterthought: the
claim that Harbor is gone is only meaningful against a cluster brought up from
nothing, and a stale `jitml:local` or a surviving `harbor-*` object would
otherwise mask a missed reference.

### Remaining Work

- The chart, Haskell, frontend, test, and documentation edits are in progress; the
  validation block above has not yet been run end to end.
- The committed per-lane attestations record a live-component count and a browser
  test total that both move when Harbor's components and its admin portal are
  removed. They must be re-issued from a completed lane run through the
  `product_lane_fragment` block, never hand-edited — the standing
  `Phase 263 issues the committed lane fragment` case fails closed on drift.
- Phase [268](phase-268-contract-driven-cuda-lane-revalidation.md) owns the
  `bootstrap/linux-cuda.sh up`/`test`/`down` lifecycle evidence it still lacks.
  That teardown and rebuild is the same one this phase needs, so the two are
  sequenced together rather than run twice.

## Documentation Requirements

**Engineering docs to create/update:**

- [cluster_topology.md](../documents/engineering/cluster_topology.md) — component
  table, storage tree, and the bootstrap phase narrative.
- [daemon_architecture.md](../documents/engineering/daemon_architecture.md) —
  the registry capability class the daemon consumes.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) records the
  Harbor surfaces under `Pending Removal` until this phase closes.

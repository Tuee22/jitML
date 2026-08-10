# Phase 44: Harbor Subchart and Bootstrap-Phase Install

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Harbor Subchart and Bootstrap-Phase Install. Single-session phase migrated from legacy Sprint 4.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

**Current topology note (2026-08-09):** the Harbor dependency, routing,
external Postgres/S3 wiring, and client contract remain Done. Phase `53` owns
the one-instance-per-Harbor-component local count; the former replicated count
is not current topology closure evidence and does not reopen this phase.

## Sprint 44.1: Harbor Subchart and Bootstrap-Phase Install [✅ Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`,
`src/JitML/Cluster/Publication.hs`, `src/JitML/Bootstrap.hs`,
`src/JitML/Service/HarborSubprocess.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install Harbor as the in-cluster image registry, with MinIO as its S3 backend
and Percona PG (Sprint `4.2`) as its database. Routed at `/harbor` (portal),
`/harbor/api` (API), `/v2` (Docker registry), and `/service` (token service).

### Deliverables

- `chart/Chart.yaml` declares the `harbor` subchart dependency at a pinned
  version.
- Current `chart/values.yaml` provides the local Harbor values scaffold and uses
  the `jitml-manual` StorageClass for registry persistence.
- Current direct Harbor values configure the registry storage backend as S3
  against MinIO bucket `harbor-registry` with 128 MiB chunks and redirects
  disabled for MinIO compatibility. The live rollout now installs MinIO and
  checks the bucket before installing Harbor.
- Current `jitml bootstrap --<substrate>` installs Harbor in the first live
  Helm phase, then uses explicit Kind-loaded `jitml:local` /
  `jitml-demo:local` tags for the Phase `3` local workload rollout. The Harbor
  phase target is live registry readiness plus a validated image push/pull path
  through the `HasHarbor` capability surface.
- HTTPRoute manifests for `/harbor`, `/harbor/api`, `/v2`, and `/service` are
  generated from the route registry (Sprint `3.4`).
- `JitML.Service.HarborSubprocess` is the explicit local Harbor client:
  callers pass `HarborSettings` with Docker binary, optional Docker host,
  curl binary, registry, API base URL, username, password, and repo-local
  Docker config directory; no process environment or global Docker config is
  consulted.

### Validation

1. `chart/Chart.yaml` declares the Harbor subchart dependency.
2. The local route registry renders `/harbor`, `/harbor/api`, `/v2`, and
   `/service` routes against the live Harbor service names.
3. Live Linux CPU validation on 2026-05-19 confirms Harbor core, portal,
   registry, jobservice, redis, and trivy rollouts reach Ready against the
   external Percona `harbor-pg` database and the MinIO-backed S3 registry
   storage values.
4. `cabal test jitml-integration` covers the typed `HarborSubprocess` login,
   artifact-existence, manifest-inspect, and repository-list command surface,
   including explicit optional Docker host flag, repo-local Docker config path,
   stdin-piped Docker credentials, and the routed `/harbor/api` base.
5. Live Linux CPU validation on 2026-05-18 pushes/promotes
   `jitml:local` to `127.0.0.1:9091/library/jitml:phase4`, pulls it back
   with digest `sha256:ab610bc0672453ee42c1d4f6b052c36208c614ec7ff198eccf3f46ccf0e5710d`,
   lists `library/jitml` through `harborListImages`, and confirms
   `harborImageExists` via Harbor's artifact API.
6. `cabal test jitml-integration` confirms the live rollout installs MinIO
   and verifies bucket `harbor-registry` before installing Harbor, and that
   Harbor uses `chart/values/harbor.yaml`.
7. Live Linux CPU validation on 2026-05-19 pushes a tiny OCI artifact through
   Harbor's registry HTTP API to
   `library/jitml-phase4-validate:phase4-20260519120542`, reads it back from
   `/v2`, confirms Harbor's artifact API reports manifest digest
   `sha256:e763d768dd2fdee99d168ba9a7b0dfe6f6f0ceaabaa417241b6d79e27a7aee4c`,
   and confirms MinIO contains the repository's layer, manifest, and tag-link
   objects under `harbor-registry/docker/registry/v2/repositories/...`.
8. Live Linux CPU validation on 2026-05-19 through the rebuilt
   `jitml:local` validation container with host networking completes
   `jitml bootstrap --linux-cpu`, writes a ready
   publication on edge port `9091`, logs into
   `127.0.0.1:9091` with repo-local Docker config, pushes
   `ubuntu:24.04` as
   `127.0.0.1:9091/library/jitml-phase4-docker:phase4-docker-20260519195137`,
   pulls it back with digest
   `sha256:cdb5fd928fced577cfecf12c8966e830fcdf42ee481fb0b91904eeddc2fe5eff`,
   lists `library/jitml-phase4-docker` through `/harbor/api`, and confirms
   the tag's Harbor artifact API returns HTTP `200`. The 2026-05-23 Phase `3`
   revalidation refreshed the same single-node bootstrap shape with the current
   110-step live rollout before later Phase `4` Harbor-specific checks.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

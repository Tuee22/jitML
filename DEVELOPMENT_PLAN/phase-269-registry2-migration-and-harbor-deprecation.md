# Phase 269: `registry:2` Migration and Harbor Deprecation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Replace Harbor with a single `registry:2` deployment on the existing
> MinIO S3 backend, and remove Harbor and its Postgres from the chart, the code,
> the tests, and the governed documents.

## Phase State

✅ **Done** (2026-08-24). The platform's container registry is `registry:2`
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

## Sprint 269.1: `registry:2` Migration and Harbor Deprecation [✅ Done]

**Status**: Done
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

2026-08-24 measured evidence, on a cluster bootstrapped from nothing:

| Gate | Result |
|---|---|
| `./bootstrap/linux-cuda.sh up` | exit `0`, **112** steps; **21** pods Running/Completed; **0** `harbor-*`, `percona`, or `postgres` objects |
| `deployment/registry` | **1/1** Available; `GET /v2/_catalog` through the edge returns `{"repositories":[]}` |
| 12 canonical datasets | staged and SHA-verified, **0** failures |
| `jitml internal train-and-publish-product-rows --linux-cuda` | `rows: 55`, `eligible: 55`, `unsupported: 0`, `errors: 0` |
| `jitml test all --linux-cuda` | exit `0` — **10 / 10** stanzas: `jitml-unit` **904 / 904**, `jitml-integration` **197 / 197**, `jitml-model-convergence` **111 / 111**, `jitml-daemon-lifecycle` **54 / 54**, `jitml-rl-canonicals` **47 / 47**, `jitml-sl-canonicals` **36 / 36**, `jitml-e2e` **30 / 30**, `jitml-backends` **28 / 28**, `jitml-hyperparameter` **26 / 26**, `jitml-negative-controls` **3 / 3** |
| `jitml test jitml-e2e --live --linux-cuda` | exit `0` — `jitml-integration` **197 / 197**, Haskell e2e **30 / 30**, `jitml-e2e-playwright` **PASS** (**77** browser tests, **55** `e2e.product.*` selectors) |
| `jitml docs check` | PASS |

The Playwright total is **unchanged at 77**. The Harbor portal was one entry in
the `expected` array inside a single admin-portals test, so removing it removed
an assertion rather than a test case.

Five defects surfaced only once the lane ran against live infrastructure, none
of them reachable from the host suite:

- the daemon-lifecycle fixture's fake `curl` answered Harbor's catalogue URL, so
  the Coordinator's registry probe could not parse `/v2/_catalog`;
- `kindPrepareStatefulPvSubprocesses` emitted `chown -R 26:26` with no path
  operand once the Postgres registry emptied — its `linux-cuda` arm was never
  covered, because the existing assertion tested the `linux-cpu` arm;
- the registry Deployment was authored as a `chart/templates/` manifest, which
  the bootstrap applies with plain `kubectl apply` from an explicit list, so it
  was never applied and its Helm templating would never have rendered;
- `requiredPublicationComponents` still demanded a `postgres` component that no
  health check measures any more, so publication readiness could never be met;
- `writeSourceFile` staged rendered kernel sources at a shared `<path>.tmp`, so
  concurrent publishers of the same content-addressed source raced and all but
  one died on the rename. Sprint `78.1` fixed this class for compiled artifacts;
  the rendered-source path had the same defect and is now staged per invocation.

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

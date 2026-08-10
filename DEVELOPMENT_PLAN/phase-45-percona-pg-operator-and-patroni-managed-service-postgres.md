# Phase 45: Percona PG Operator and Patroni-Managed Service Postgres

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Percona PG Operator and Patroni-Managed Service Postgres. Single-session phase migrated from legacy Sprint 4.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

**Current topology note (2026-08-09):** the Percona operator, CR renderer,
schema grant, pgBouncer endpoint, and Harbor integration remain Done. Phase
`53` owns reducing the local Postgres/pgBouncer/pgBackRest counts and PV set;
the historical Patroni/three-instance shape is not current topology closure
evidence and does not reopen this phase.

## Sprint 45.1: Percona PG Operator and Patroni-Managed Service Postgres [✅ Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`,
`chart/templates/pv-platform-harbor-pg-*.yaml`,
`chart/templates/pv-platform-harbor-pg-repo1-0.yaml`,
`src/JitML/Cluster/PostgresRegistry.hs`,
`src/JitML/Cluster/Readiness.hs`, `src/JitML/Bootstrap.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Install the Percona Kubernetes Operator and Patroni-managed HA Postgres clusters
for packaged services that require Postgres. Harbor is the first consumer.
jitML itself never writes to a relational DB on its data path — durable state
lives in MinIO and Pulsar exclusively.

### Deliverables

- `pg-operator` subchart pinned in `chart/Chart.yaml`.
- Current local storage includes manual PV templates for the `platform/harbor-pg`
  data volumes and `platform/harbor-pg-repo1` pgBackRest repo volume.
- `PerconaPGCluster` resources are rendered from a typed service-Postgres
  registry; the first entry is `harbor-pg` in namespace `platform`, using the
  `jitml-manual` StorageClass and manual PVs from Sprint `3.2`. Percona data
  and pgBackRest PVCs bind through explicit `volumeName` fields because the
  operator-generated PVC names carry controller suffixes.
- Target Harbor database values point at `harbor-pg`.
- Target `jitml lint chart` rejects any `PerconaPGCluster` outside the typed
  service-Postgres registry.

### Validation

1. `chart/Chart.yaml` declares the `pg-operator` subchart dependency.
2. `chart/templates/pv-platform-harbor-pg-*.yaml` and
   `chart/templates/pv-platform-harbor-pg-repo1-0.yaml` provide the manual PV
   surface for service Postgres data and pgBackRest storage.
3. `cabal test jitml-integration` covers the rendered `PerconaPGCluster`,
   pinned Percona component images, explicit `volumeName` PV bindings,
   stdin-piped apply command, and readiness wait command.
4. Live Linux CPU validation on 2026-05-19 confirms `PerconaPGCluster`
   `harbor-pg` reaches `ready` in namespace `platform`, with
   `postgres=3/3`, `pgbouncer=1/1`, host
   `harbor-pg-pgbouncer.platform.svc`, and all four manual PVs bound.
5. `cabal test jitml-integration` confirms the live rollout installs the
   Percona operator, applies the registered `harbor-pg` CR, waits for
   `perconapgcluster/harbor-pg` readiness, grants the `harbor` role schema
   ownership on the current primary, and only then installs Harbor with
   `--values chart/values/harbor.yaml`.
6. `cabal run jitml -- lint chart` rejects any `PerconaPGCluster` outside
   the typed service-Postgres registry.
7. Live Linux CPU validation on 2026-05-19 confirms Harbor starts successfully
   against the external `harbor-pg-pgbouncer.platform.svc` database endpoint
   after the pre-Harbor schema ownership grant.

### Closure State

- `JitML.Cluster.PostgresRegistry.postgresRegistry` is the typed
  service-Postgres registry with `harbor-pg` in namespace `platform` as
  the first entry. `renderPerconaPGCluster` emits the `PerconaPGCluster`
  YAML; `validateRegisteredPostgres` is the lint helper that rejects
  unknown cluster names. **The lint rule is now wired into
  `JitML.Lint.Chart.checkPerconaCluster`** — `jitml lint chart` rejects
  any `PerconaPGCluster` in `chart/templates/*.yaml` whose name is not
  declared in `postgresRegistry`, with the remedy pointing at
  `src/JitML/Cluster/PostgresRegistry.hs`.
- The `helm install` of the Percona operator is sequenced in
  `JitML.Cluster.Helm.phasedReleases` (HarborPhase, `harbor-pg` row).
  The rendered `PerconaPGCluster` YAML now flows through the live bootstrap as
  a stdin-piped `kubectl --kubeconfig ./.build/jitml.kubeconfig apply -n
  platform -f -` after the operator CRD is installed. The CR pins Postgres,
  PgBouncer, and pgBackRest images for Percona Operator `2.5.1`; renders three
  single-replica instance volumes plus one pgBackRest repo volume; and binds
  all four manual PVs through explicit `volumeName` fields. Live Linux CPU
  validation on 2026-05-19 confirmed `harbor-pg` reaches `ready` with
  `postgres=3/3` and `pgbouncer=1/1`.
- `JitML.Cluster.Readiness.postgresReadinessSubprocesses` waits for
  `perconapgcluster/harbor-pg` to report `.status.state=ready` before
  Pulsar topic bootstrap.
- `chart/values/harbor.yaml` is the direct Harbor subchart values file, and
  `chart/values.yaml` carries the matching umbrella-chart values. Both set
  `database.type=external`, point at
  `harbor-pg-pgbouncer.platform.svc:5432`, use database/user `harbor`, and
  consume `harbor-pg-secrets` for the password with `sslmode=require`
  because PgBouncer requires TLS. The live rollout installs the Percona
  operator, applies the registered CR, waits for readiness, runs a typed
  `kubectl exec ... psql` schema grant on the current primary so Harbor's
  migration can create tables under `public`, and then installs Harbor with
  that values file.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

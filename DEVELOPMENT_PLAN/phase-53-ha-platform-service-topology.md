# Phase 53: HA Platform Service Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: HA Platform Service Topology. Single-session phase migrated from legacy Sprint 4.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 53.1: HA Platform Service Topology [✅ Done]

**Status**: Done (opened 2026-06-27; closed 2026-06-28)
**Implementation**: `chart/Chart.yaml`, `chart/values/*.yaml`,
`chart/templates/*.yaml`, `src/JitML/Cluster/Helm.hs`,
`src/JitML/Cluster/PostgresRegistry.hs`, `src/JitML/Cluster/Readiness.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Make the chart and typed rollout plan implement the documented HA platform
service topology instead of the compact/right-sized local profile.

### Deliverables

- MinIO direct/umbrella values reflect the target distributed MinIO topology and
  keep bucket provisioning sourced from the durable-state registry.
- Pulsar direct/umbrella values reflect 3 ZooKeeper, 3 BookKeeper, 3 Broker, and
  3 Proxy replicas, with the existing routed admin/WebSocket surfaces preserved.
- Percona Postgres rendering uses the target HA replica count and pgBackRest
  storage, with explicit manual PV bindings coordinated with Phase `3`.
- `chart/Chart.yaml` and docs distinguish actual third-party subchart
  dependencies from local charts and CR-rendered resources: HA Postgres is a
  PerconaPGCluster CR rendered by jitML, and TensorBoard is a local chart.
- Readiness gates and lint assertions fail on accidental drift back to compact
  replica counts unless an explicit local profile is introduced and documented.

### Validation

- `cabal build exe:jitml --ghc-options=-fasm`
- `cabal test jitml-integration --ghc-options=-fasm --test-options='-p HA'`
- `cabal test jitml-integration --ghc-options=-fasm --test-options='-p distributed'`
- Shared final gates: `jitml docs check`, `jitml lint chart`, and
  `docker compose run --rm jitml jitml check-code`.

### Remaining Work

- None. Live HA substrate revalidation is tracked by Phase `15` Sprint `15.22`
  and Phase `16` Sprint `16.14`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

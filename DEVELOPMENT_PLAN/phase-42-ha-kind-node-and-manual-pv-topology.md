# Phase 42: HA Kind Node and Manual-PV Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: HA Kind Node and Manual-PV Topology. Single-session phase migrated from legacy Sprint 3.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 42.1: HA Kind Node and Manual-PV Topology [✅ Done]

**Status**: Done (opened 2026-06-27; closed 2026-06-28)
**Implementation**: `kind/cluster-*.yaml`, `src/JitML/Cluster/Kind.hs`,
`src/JitML/Cluster/Storage.hs`, `chart/templates/pv-*.yaml`,
`src/JitML/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Make the documented HA cluster shape the implemented Kind/materialization
surface: control-plane plus worker nodes from the HA profile, HA-sized manual
PVs, single localhost Envoy edge socket, and no hidden single-node/right-sized
assumptions.

### Deliverables

- Render a target HA Kind topology for every substrate, including worker nodes
  that can host platform services and Engine compute while preserving the
  `127.0.0.1:<edge-port>` Envoy listener.
- Apply `kindest/node` pins, `extraMounts`, GPU labels/runtime material, and
  resource caps to the correct node set rather than only the compact
  control-plane node.
- Expand manual PV rendering and chart templates for the HA storage topology:
  distributed MinIO, Pulsar ZooKeeper/BookKeeper/Broker/Proxy where persistent,
  Percona Postgres replicas, and pgBackRest.
- Keep the scoped one-numerical-worker-per-node compute invariant coordinated
  with Phase `5` Sprint `5.16`; Phase `3` owns the node topology that makes
  that scheduling rule enforceable.

### Validation

- `cabal build exe:jitml --ghc-options=-fasm`
- `cabal test jitml-integration --ghc-options=-fasm --test-options='-p HA'`
  covers the HA Kind renderer and HA PV/service shape.
- `cabal run exe:jitml --ghc-options=-fasm -- internal materialize-substrate
  --substrate <apple-silicon|linux-cpu|linux-cuda>` regenerated the checked-in
  substrate fixtures from the HA renderer.
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

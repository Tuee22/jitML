# Phase 29: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight. Single-session phase migrated from legacy Sprint 2.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 29.1: Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight [✅ Done]

**Status**: Done (code-surface closed 2026-05-29; live node-cap exercise owned by Phase 15 Sprint 15.1)
**Implementation**: `dhall/cluster/Schema.dhall`, `dhall/cluster/resources.dhall`, `src/JitML/Cluster/Resources.hs`, `src/JitML/Bootstrap.hs`, `src/JitML/Prerequisite/Nodes/Cluster.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`, `system-components.md`

### Objective

Bound the kind cluster's memory and CPU so an over-budget bootstrap can never
exhaust the host (the 2026-05-29 OOM-storm incident), with the budget expressed as
typed Dhall rather than environment variables or shell arithmetic. Implements
doctrine `Application Environment` (typed config) and `Prerequisites as Typed
Effects`.

### Deliverables

- A typed `ClusterResources` Dhall schema (`dhall/cluster/Schema.dhall`) plus a
  concrete profile (`dhall/cluster/resources.dhall`) carrying `nodeMemoryMiB`,
  `nodeCpus`, and per-component `{ replicas, cpuRequest, cpuLimit, memoryRequest,
  memoryLimit }`, decoded by `JitML.Cluster.Resources.loadClusterResourcesOrDefault`
  (mirrors `JitML.Service.BootConfig.loadBootConfig` and `JitML.Numerics.Schema`).
- The bootstrap reconciler applies a typed `docker update
  --memory/--memory-swap/--cpus` cap to `jitml-<substrate>-control-plane` after
  `kind create`, fail-closed if the cap cannot be applied; the resolved profile is
  materialized to `./.build/conf/cluster/Resources.dhall`.
- A `cluster.host-memory` prerequisite added to the Sprint `2.2` registry that fails
  when host `MemTotal` is below `nodeMemoryMiB` + reserve (returns pass when
  `/proc/meminfo` is absent).

### Validation

- `jitml doctor --scope cluster` reports the `cluster.host-memory` node and fails
  with a remedy hint when `nodeMemoryMiB` exceeds host RAM.
- `jitml bootstrap --<substrate> --dry-run` renders the plan including the node-cap
  step and exits `0`.
- Live (owned by Phase `15`): after `kind create`, `docker inspect -f
  '{{.HostConfig.Memory}}' jitml-<substrate>-control-plane` reports the cap, and a
  forced over-budget cluster OOM-kills pods inside the node cgroup while the host
  stays up.

### Current Validation State

- `docker compose run --rm jitml cabal build all` succeeds (2026-05-29) — the new
  `JitML.Cluster.Resources` module and the wiring changes in
  `JitML.Bootstrap` / `JitML.Prerequisite.Nodes.Cluster` compile clean.
- `docker compose run --rm jitml jitml doctor --scope cluster` reports the new
  `cluster.host-memory` node and exits `0` on this host (15 GiB ≥ 10 GiB node cap +
  4 GiB reserve).
- Historical Phase `2` validation:
  `docker compose run --rm jitml jitml cluster up --substrate linux-cpu`
  materialized `./.build/conf/cluster/Resources.dhall` from the
  `dhall/cluster/` source. Phase `3` Sprint `3.7` subsequently validated the
  stricter live lifecycle contract for that command.
- `cabal test jitml-unit` passes; `cabal test jitml-integration` failures are
  isolated to pre-existing live-cluster Sprint 13.x tests (Pulsar timeouts —
  no cluster up).
- `jitml docs check` exits `0`.

### Remaining Work

- The live node-cap exercise and the host-survives-over-budget validation are owned
  by Phase `15` Sprint `15.1`'s Remaining Work.
- The per-pod limits + right-sized replicas that make the stack converge under the
  cap are owned by Phase `4` Sprint `4.8` (and the PV-layout change by Phase `3`
  Sprint `3.2`).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 69: One Numerical Worker per Kubernetes Node

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: One Numerical Worker per Kubernetes Node. Single-session phase migrated from legacy Sprint 5.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 69.1: One Numerical Worker per Kubernetes Node [✅ Done]

**Status**: Done (opened 2026-06-27; closed 2026-06-28)
**Implementation**: `chart/local/jitml-service`, `src/JitML/Service/*`,
`src/JitML/Cluster/Helm.hs`, `dhall/service/*`, daemon lifecycle/workload
placement tests
**Docs to update**: `documents/engineering/daemon_architecture.md`,
`documents/engineering/cluster_topology.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make the HA service topology enforce that only the Engine/numerical compute role
does ML work and that no Kubernetes node can host more than one numerical ML
compute worker for a substrate.

### Deliverables

- Separate numerical Engine worker scheduling from Coordinator, Webapp,
  observability, and platform-service replica scaling.
- Render required anti-affinity/topology-spread or equivalent placement rules so
  the Engine/numerical compute role is capped at one per Kubernetes node.
- Preserve Apple Silicon host-resident compute semantics: cluster replicas may
  forward/control work, but host Metal compute remains bound to the host topology
  and does not multiply with in-cluster replicas.
- Add tests that scaling noncompute roles does not add numerical compute workers
  and that Engine replicas cannot co-locate on a Kubernetes node.

### Validation

- `cabal test jitml-integration --ghc-options=-fasm --test-options='-p cardinality'`
- `cabal test jitml-daemon-lifecycle --ghc-options=-fasm --test-options='-p cardinality'`
- `cabal test jitml-integration --ghc-options=-fasm --test-options='-p HA'`
  re-ran the HA topology regressions after service placement changed.
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

# Phase 69: One Numerical Worker per Kubernetes Node

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: One Numerical Worker per Kubernetes Node. Single-session phase migrated from legacy Sprint 5.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-08-10). The typed resource profile now drives the root Engine
Deployment and local Helm values, with validation rejecting Engine overcommit.

## Sprint 69.1: One Numerical Worker per Kubernetes Node [✅ Done]

**Status**: Done (historical cardinality surface closed 2026-06-28; reopened and
revalidated 2026-08-10 for the profile-driven single-worker local target)
**Implementation**: `chart/local/jitml-service`, `src/JitML/Service/*`,
`src/JitML/Cluster/Helm.hs`, `dhall/service/*`, daemon lifecycle/workload
placement tests
**Docs to update**: `../documents/engineering/daemon_architecture.md`,
`../documents/engineering/cluster_topology.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Make the supported local service topology run one Linux Engine on its one
compute worker while retaining the general invariant that no Kubernetes node
can host more than one numerical ML compute worker of a scope. Apple Silicon
continues to run zero clustered Engines and one host Engine.

### Deliverables

- Separate numerical Engine worker scheduling from Coordinator, Webapp,
  observability, and platform-service replica scaling.
- Render required anti-affinity/topology-spread or equivalent placement rules so
  the Engine/numerical compute role is capped at one per Kubernetes node.
- Remove the independent hard-coded Linux Engine replica count. The loaded
  `ClusterResources.jitmlService.replicas` value drives the rendered root
  manifest, local chart runtime input, and readiness expectation, and validation
  rejects a positive Linux Engine count greater than `workerCount`.
- Preserve Apple Silicon host-resident compute semantics: cluster replicas may
  forward/control work, but host Metal compute remains bound to the host topology
  and does not multiply with in-cluster replicas.
- Validate the one-worker local default and the retained placement metadata.
  Arbitrary positive worker/Engine counts remain expressible for deployment
  owners, but this repository does not deploy or explicitly test a multi-worker
  topology.
- Preserve Pulsar's at-least-once delivery, negative-ack redelivery, semantic
  deduplication, and total settlement tests. The current `Failover`
  subscriptions permit active/standby ownership transfer; they do not claim
  concurrent load-balanced fan-out or make the single-instance platform HA.

### Validation

- `docker compose build jitml`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu
  --test-options='-p cardinality'` proves one Linux Engine, zero clustered Apple
  Engines, one Coordinator, profile-to-renderer equality, and retained
  compute-node/anti-affinity/rolling-update constraints.
- `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  retains the at-least-once redelivery, semantic-deduplication,
  total-settlement, and lifecycle gates.
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml lint chart`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

None. Closure evidence: the canonical image built successfully; the focused
cardinality case passed **1 / 1**; daemon lifecycle passed **54 / 54**; docs
check, chart lint, and `check-code` passed. Phase `262` is now Active. The
still-literal product status registry remains Sprint `34.3` work in the legacy
ledger.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/daemon_architecture.md` — profile-driven local
  Engine cardinality and retained multi-worker protocol boundary.
- `../documents/engineering/cluster_topology.md` — Engine-to-worker constraints.
- `../documents/engineering/pulsar_ml_workflow.md` — at-least-once compatibility
  without a repository-owned multi-worker acceptance claim.

**Product docs to create/update:**

- `../README.md` — one-worker local daemon orientation.

**Cross-references to add:**

- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned
  with the hard-coded three-Engine and HA-only test removal row.

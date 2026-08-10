# Phase 53: Single-Instance Local Platform Service Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Make the supported local platform use one instance of each
> stateful and application service while preserving the Pulsar workflow and
> typed readiness contracts. Single-session phase migrated from legacy Sprint
> 4.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in
> [README.md](README.md).

## Phase State

⏸️ **Blocked** by Phase `42`, which owns the one-worker Kind shape and
profile-driven manual-PV registry required by this rollout.

## Sprint 53.1: Single-Instance Local Platform Service Topology [⏸️ Blocked]

**Status**: Blocked (historical HA surface closed 2026-06-28; reopened
2026-08-09 for the single-instance local target)
**Blocked by**: Sprint `42.1` (Phase `42`)
**Implementation**: `chart/Chart.yaml`, `chart/values/*.yaml`,
`chart/templates/*.yaml`, `src/JitML/Cluster/Helm.hs`,
`src/JitML/Cluster/PostgresRegistry.hs`, `src/JitML/Cluster/Readiness.hs`
**Docs to update**: `../documents/engineering/cluster_topology.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Make the chart and typed rollout plan implement a resource-bounded
single-instance local platform. Kubernetes restart behavior, retained storage,
Pulsar at-least-once delivery, and semantic idempotency remain supported; this
topology does not claim broker, object-store, database, node, or storage
high availability.

### Deliverables

- MinIO direct/umbrella values use standalone mode with one replica and keep
  bucket provisioning sourced from the durable-state registry.
- Pulsar direct/umbrella values use one ZooKeeper, one BookKeeper, one Broker,
  one Proxy, and one autorecovery process. Managed-ledger ensemble, write
  quorum, and acknowledgement quorum are explicitly one; the existing routed
  admin/WebSocket surfaces and exact topic family remain unchanged.
- Percona Postgres rendering uses one database instance, one pgBouncer, and one
  pgBackRest repository with explicit manual PV bindings coordinated with Phase
  `42`.
- Regenerate the profile-driven checked-in PV set to the six replica-zero
  stateful PVs, delete every superseded higher-index PV manifest/assertion, and
  require a destructive `./bootstrap/<substrate>.sh purge` before the first
  target-shape `up`; `down` preserves the incompatible distributed `.data`
  layout.
- Harbor, Prometheus, Grafana, TensorBoard, Coordinator, and Webapp each use one
  local replica. Count-bearing direct values, umbrella values, typed Helm
  overrides/materialization, readiness expectations, and resource-profile
  fallbacks agree.
- `chart/Chart.yaml` and docs distinguish actual third-party subchart
  dependencies from local charts and CR-rendered resources: Postgres is a
  PerconaPGCluster CR rendered by jitML, and TensorBoard is a local chart.
- Add a drift guard over the actual Helm commands/materialized inputs, not only
  the checked-in source values, so a runtime overlay cannot silently restore HA
  counts.
- Retire explicit distributed/HA rollout and chaos acceptance. Expanded platform
  redundancy is deployment-owner configuration outside the repository's local
  acceptance contract.

### Validation

- `docker compose build jitml`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu
  --test-options='-p local-topology'` proves the single-instance direct,
  umbrella, generated, and runtime Helm inputs plus exact PV/PVC agreement.
- `./bootstrap/linux-cpu.sh purge` followed by
  `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up` proves a
  clean single-instance rollout, all
  required components Ready, the exact topic family present, every typed MinIO
  bucket provisioned, and no unexpected second replica. This destructive
  migration gate preserves `./.build/` but intentionally replaces `.data/`.
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml lint chart`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

- Blocked until Phase `42` closes.
- Change every count-bearing platform value, typed renderer, Haskell fallback,
  runtime Helm input, readiness assertion, and topology test to the
  single-instance target.
- Prove the clean `linux-cpu` rollout and shared final gates above. No
  multi-instance or failover run is required.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/cluster_topology.md` — single-instance target,
  non-HA boundary, storage reset, and readiness contract.
- `../documents/engineering/pulsar_ml_workflow.md` — at-least-once delivery and
  multi-worker compatibility without a local HA claim.

**Product docs to create/update:**

- `../README.md` — local platform orientation and migration warning.

**Cross-references to add:**

- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned
  with the distributed MinIO, multi-replica Pulsar/Postgres, and HA acceptance
  removal row.

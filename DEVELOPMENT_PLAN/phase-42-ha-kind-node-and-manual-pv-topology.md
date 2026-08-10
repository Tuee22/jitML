# Phase 42: Single-Worker Local Kind Node and Manual-PV Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Make the supported local Kind and manual-PV topology use one
> control-plane plus one worker, and make storage cardinality derive from the
> typed resource profile that Phase 53 will reduce. Single-session phase migrated from legacy Sprint 3.6
> in the 2026-07-24 phase-per-session renumber; see the old→new map in
> [README.md](README.md).

## Phase State

🔄 **Active**. Reopened on 2026-08-09 because the repository's supported local
validation topology changes from the historical HA-shaped four-node cluster to
one control-plane plus one worker. Phases `43`–`52` remain Done on their retained
lifecycle, routing, service-install, and capability surfaces; Phase `53` is the
next executable topology owner after this phase closes.

## Sprint 42.1: Single-Worker Local Kind Node and Manual-PV Topology [🔄 Active]

**Status**: Active (historical HA surface closed 2026-06-28; reopened
2026-08-09 for the single-worker local target)
**Implementation**: `kind/cluster-*.yaml`, `src/JitML/Cluster/Kind.hs`,
`src/JitML/Cluster/Storage.hs`, `chart/templates/pv-*.yaml`,
`src/JitML/Lint/Chart.hs`
**Docs to update**: `../documents/engineering/cluster_topology.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

Make one control-plane plus one worker the implemented and validated local
Kind/materialization surface for every substrate. Keep arbitrary positive
worker counts expressible by the typed renderer for deployment owners, but make
the repository's bootstrap, checked-in fixtures, resource caps, and local
validation depend only on the one-worker profile.

### Deliverables

- Set the typed `dhall/cluster/` profile, Haskell fallback, and checked-in Kind
  fixtures to one control-plane plus one compute worker while preserving the
  `127.0.0.1:<edge-port>` Envoy listener.
- Apply `kindest/node` pins, `extraMounts`, GPU labels/runtime material, and
  resource caps to the two materialized nodes.
- Make manual-PV rendering consume a supplied typed replica profile rather than
  a separate hard-coded HA inventory. A focused target-profile case renders one
  MinIO data PV, one BookKeeper journal PV, one BookKeeper ledger PV, one
  ZooKeeper data PV, one Percona Postgres data PV, and one pgBackRest repository
  PV. The checked-in higher-index platform PVs remain until Phase `53` changes
  the platform counts and regenerates the actual manifest set.
- Keep the scoped one-numerical-worker-per-node compute invariant coordinated
  with Phase `69`. Multi-worker renderability remains supported, but this phase
  owns no multi-worker or node-failover acceptance gate.

### Validation

- `docker compose build jitml`
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu
  --test-options='-p local-topology'` proves one control-plane, one worker, two
  capped/mounted node containers, profile-driven PV rendering including the
  exact six-PV target-profile case, and all three substrate renderers without
  requiring accelerator hardware.
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml lint chart`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

- Change the typed cluster profile and Haskell fallback from three workers to
  one.
- Parameterize the manual-PV registry from the typed replica profile, regenerate
  all three checked-in Kind fixtures, and remove assertions for `worker2`,
  `worker3`, or hard-coded storage cardinality. Phase `53` owns changing the
  platform counts, regenerating the reduced checked-in PV set, and deleting the
  higher-index manifests.
- Pass the Validation block above from one source/image state. Phase `53` then
  owns the live single-instance platform rollout.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/cluster_topology.md` — current-versus-target node
  shape, storage inventory, migration boundary, and validation scope.
- `../documents/engineering/daemon_architecture.md` — one-worker local daemon
  target and retained placement rules.

**Product docs to create/update:**

- `../README.md` — orient operators to the single-worker local target and the
  explicit non-HA availability boundary.

**Cross-references to add:**

- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned
  with the three-worker Kind and hard-coded manual-PV renderer row.

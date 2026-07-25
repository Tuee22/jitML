# Phase 38: `kubernetes.io/no-provisioner` Storage and Manual PVs

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: kubernetes.io/no-provisioner Storage and Manual PVs. Single-session phase migrated from legacy Sprint 3.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 38.1: `kubernetes.io/no-provisioner` Storage and Manual PVs [✅ Done]

**Status**: Done (re-closed 2026-05-29 after the right-sized PV layout landed; live hostPath-backed rollout owned by Phase 15 Sprint 15.1)
**Implementation**: `chart/templates/storageclass-jitml-manual.yaml`,
`chart/templates/pv-platform-minio-*.yaml`,
`chart/templates/pv-platform-pulsar-bookie-journal-*.yaml`,
`chart/templates/pv-platform-pulsar-bookie-ledgers-*.yaml`,
`chart/templates/pv-platform-pulsar-zookeeper-data-*.yaml`,
`chart/templates/pv-platform-harbor-pg-*.yaml`,
`src/JitML/Cluster/Storage.hs`, `src/JitML/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`

### Objective

Lay down the `jitml-manual` StorageClass (no provisioner), the manual PV
templates per StatefulSet replica, the on-disk layout
`./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`, and the chart-shape lint
that enforces the discipline.

### Deliverables

- `jitml-manual` StorageClass with `provisioner:
  kubernetes.io/no-provisioner`, `volumeBindingMode: WaitForFirstConsumer`, and
  no other provisioner anywhere in the chart.
- Manual PV templates per StatefulSet (MinIO 4 replicas, Pulsar BookKeeper 3
  replicas, Pulsar ZooKeeper 3 replicas) with explicit `claimRef.namespace` and
  `claimRef.name`. Registered Percona PG PVs are the exception: their generated
  PVC names carry an operator suffix, so the typed `PerconaPGCluster` pins
  those PVs from the PVC side with explicit `volumeName` fields. Each host
  directory is `./.data/<namespace>/<StatefulSet>/pv_<replica-int>/`, mounted
  into the Kind node at `/jitml/.data/...`.
- DNS-1123-compatible PV resource names:
  `<namespace>-<statefulset>-pv-<int>`.
- `src/JitML/Cluster/Storage.hs` is the typed source for the PV layout; the
  templates are present in the chart and checked by chart lint.
- `jitml lint chart` (the Sprint `1.4` scaffold plus this sprint's real chart
  checks) enforces every invariant: the only
  StorageClass is `jitml-manual`, every PV has explicit `claimRef` or a
  registered Percona `volumeName` binding, every PVC is created only by a
  StatefulSet's `volumeClaimTemplates` or by the registered Percona operator
  resource, every hostPath matches the regex.

### Validation

1. `jitml lint chart` exits `0` on the current chart.
2. Hand-introducing a non-conformant StorageClass, PV claimRef, or hostPath
   surfaces `AppError ChartLintFailed`.
3. Live hostPath-backed cluster rollout is validated by Sprint `3.5`.
4. After the right-sized layout lands, `src/JitML/Cluster/Storage.hs` emits the
   reduced PV set (MinIO `1–2`, Pulsar BookKeeper / ZooKeeper `1`) matching the
   Phase `4` Sprint `4.8` replica counts, and `jitml lint chart` still exits `0`.

### Remaining Work

- The manual-PV set was reduced to the right-sized replica counts in
  `JitML.Cluster.Storage` (MinIO `4→1`, Pulsar BookKeeper / ZooKeeper `3→1`,
  Postgres `3→1`), and the orphan `chart/templates/pv-*.yaml` files left from
  the larger replica set were deleted from the worktree. A new
  `JitML.Bootstrap.sweepStalePvManifests` runs during materialization, deleting
  any `pv-*.yaml` that is not in the current `manualPVs` list so future
  replica re-tunes never leave stale PV manifests behind (caught live when
  `jitml check-code` inside the Dockerfile rejected the orphan PVs as missing
  `claimRef`).
- The live hostPath-backed rollout with the reduced PV set is owned by Phase
  `15` Sprint `15.1`'s Remaining Work.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

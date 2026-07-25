# Phase 124: Bit-Determinism Contract and Retention Reconciler

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Bit-Determinism Contract and Retention Reconciler. Single-session phase migrated from legacy Sprint 10.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 124.1: Bit-Determinism Contract and Retention Reconciler [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live MinIO blob
deletion plus `gc_reaped` Pulsar event publication migrated to Phase `15`
Sprint `15.7`. The per-substrate ULP tolerance measurement migrated to
Phase `17` Sprint `17.1`.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Land the determinism documentation tie-in and `jitml internal gc`
summary surface; grow real retention graph traversal and MinIO deletion
per `### Remaining Work` below.

### Deliverables

- `documents/engineering/determinism_contract.md` records the target
  same-substrate and cross-substrate tolerance methodology.
- `jitml internal gc <experiment-hash> --dry-run` renders a generic
  Plan/Apply retention plan.
- Normal `jitml internal gc <experiment-hash>` scans
  `<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/`,
  prints the local retention summary (`gc: <experiment-hash> kept=<n>
  reaped=<n>`), and exits `3` on a no-op plan through
  `AppError ReconcilerNoop`.
- `JitML.Checkpoint.Store.{walkLiveSet,applyRetentionPolicy,buildGcPlan}`
  implement the pointer live-set traversal across the `latest` chain
  and `best/<m>` / `trial/<...>` always-live pointer targets,
  `LastN k` retention application, blob-reap event materialisation
  (`GcEvent` records the manifest SHA, blob SHAs, experiment hash,
  and step), and the steady-state no-op detection
  (`gcNoOp` flag flips when there are no reap events).
- `JitML.Checkpoint.Store.listCheckpointManifests` is the local manifest
  discovery hook used by the CLI reconciler. Live blob deletion through
  MinIO + Pulsar `gc_reaped` publish is owned by the checkpoint-GC closure
  path.

### Validation

1. `jitml internal gc <experiment-hash> --dry-run` emits the typed plan.
2. `jitml internal gc <experiment-hash>` prints the reconciliation
   summary.
3. Transferred live validation: the bit-determinism contract is verified by
   `jitml-cross-backend` running real cross-substrate cohorts and the
   resulting per-tensor drift fitting the committed ULP tolerance band;
   `jitml internal gc` traverses the pointer live set, applies a `LastN`
   retention policy, reaps unreferenced blobs from MinIO, emits
   `gc_reaped` events, and exits `3` when the cluster is already at the
   target retention state.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. `gc_reaped`
  Pulsar event publication and live HTTP MinIO deletion validation are
  owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.7`. The per-substrate ULP tolerance measurement is owned by
  [phase-17-cross-substrate-and-handoff.md](README.md#legacy-to-new-phase-map)
  Sprint `17.1`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

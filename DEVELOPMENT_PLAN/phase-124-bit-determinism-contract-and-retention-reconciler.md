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
**Owned obligations after refactor**: local deterministic planning and the
same-substrate bit-determinism doctrine only. Live MinIO deletion and Pulsar
publication moved to Phase `174`; immutable ProductRow/browser-catalogue roots,
snapshot-scoped writer ownership, committed-only eligibility, full
snapshot-owned deletion planning (the exact commit plus payload objects),
descriptor reconstruction/snapshot-id re-derivation, stale-intent cancellation, and durable
ready/published retry semantics moved to Phase `262`.
**Implementation**: `src/JitML/App.hs`, `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Plan/Plan.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Land the same-substrate determinism documentation tie-in and the pure/local
`jitml internal gc` planning surface. This retained phase does not own live
object deletion, event delivery, cross-substrate numerical equivalence, or a
cross-substrate tolerance measurement.

### Deliverables

- `documents/engineering/determinism_contract.md` requires exact-byte
  reproduction only for the same substrate, toolchain, inputs, and plan.
  Cross-substrate bit equality and numeric-parity fitting are out of contract.
- `jitml internal gc <experiment-hash> --dry-run` renders a generic
  Plan/Apply retention plan.
- Normal `jitml internal gc <experiment-hash>` scans
  `<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/`,
  prints the local retention summary (`gc: <experiment-hash> kept=<n>
  reaped=<n>`), and exits `3` on a no-op plan through
  `AppError ReconcilerNoop`.
- `JitML.Checkpoint.Store.{walkLiveSet,applyRetentionPolicy,buildGcPlan}`
  retain each caller-selected manifest plus its immediate parent, apply
  `LastN k` to candidates in canonical step-descending/SHA-ascending rank,
  accept independently admitted always-live roots, materialise deterministic
  `GcEvent` values, and detect a steady-state no-op.
- `JitML.Checkpoint.Store.listCheckpointManifests` is the local manifest
  discovery hook used by the offline CLI branch, which reports but does not
  delete. Phase `174` owns the original live MinIO/Pulsar closure; Phase `262`
  owns the active hardened-live target: deterministic snapshot namespaces,
  uniquely owned per-attempt reservation markers with attempt-independent
  commit recovery, canonical-original → exact-scoped → payload-SHA descriptor
  validation, one experiment-scoped full-reservation/per-event-generation CAS
  fence for cross-snapshot parent overlap and stale-executor exclusion,
  commit-inclusive one-snapshot event keys, complete ordered pagination and
  fresh root revalidation bracketed by an unchanged monotonic writer/root epoch,
  bounded whole-view restart on epoch churn or persistence of an absent exact
  fresh-plan intent, converged-plan-only kept/no-op accounting with exact
  initial/fresh intent creation counted as work, exact-epoch planning without
  sibling-GC invalidation, opaque-only destructive execution through
  `executeAuthorizedGcIntents` with no plan/raw-intent compatibility export,
  helpable `Planned` →
  `Cancelling` → `Cancelled` settlement through a stable immutable cancellation
  artifact without deleting the semantic intent before generation re-arm,
  and permanent publication tombstones. That later phase remains Active until
  its prescribed aligned-image and live validation passes.

### Validation

1. `jitml internal gc <experiment-hash> --dry-run` emits the typed plan.
2. Without a live publication, `jitml internal gc <experiment-hash>` scans the
   local manifest tree, prints the deterministic kept/reaped summary, performs
   no deletion, and exits `3` for a no-op plan.
3. Unit validation proves planning is independent of discovery order, including
   the manifest-SHA tie-break for equal steps.
4. The determinism contract asserts byte identity only within one substrate and
   toolchain. No `jitml-cross-backend` or cross-substrate ULP gate belongs to
   this phase.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/determinism_contract.md`
- `../documents/engineering/checkpoint_format.md`

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Link transferred live behavior to
  [Phase 174](phase-174-live-minio-checkpoint-round-trip-and-retention.md) and
  [Phase 262](phase-262-contract-driven-live-execution-browser-and-playwright.md).

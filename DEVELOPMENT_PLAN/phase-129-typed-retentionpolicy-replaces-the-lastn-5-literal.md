# Phase 129: Typed `RetentionPolicy` Replaces the `LastN 5` Literal

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed RetentionPolicy Replaces the LastN 5 Literal. Single-session phase migrated from legacy Sprint 10.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 129.1: Typed `RetentionPolicy` Replaces the `LastN 5` Literal [✅ Done]

**Status**: Done (reopened 2026-06-23; re-closed 2026-06-24) — unblocked by Phase 2
Sprint `2.15`.

Replace the hardcoded checkpoint-GC retention literal with the typed `RetentionPolicy`
declared per `StoreEntry` in the durable-state registry, so retention is a validated
config value (`LastN 0` etc. rejected at typecheck) rather than a magic constant:

- New `JitML.Project.Config.lookupStoreRetention` reads the `checkpoints` store's typed
  `RetentionPolicy` from the registry; `App.hs` `checkpointsGcRetention` maps it onto
  the GC-supported subset and feeds `runInternalGc`'s `buildGcPlan`.
- The hardcoded `retention = CheckpointStore.LastN 5` literal is gone; the GC retention
  is now registry-sourced (the registry declares `checkpoints` retention `LastN 5`).

### Exit Definition

- The checkpoint GC reads its retention from the registry-sourced `RetentionPolicy`;
  no hardcoded `LastN 5` retention value remains in `App.hs`.

### Validation State (2026-06-24)

- `cabal build exe:jitml` links; no `LastN 5` retention literal remains in `App.hs`
  (only doc-comment references).
- `jitml-unit` **219/219**, incl. "checkpoint GC retention is registry-sourced (LastN 5)".

### Remaining Work

- None on the retention source-of-truth surface. (Mapping the age/bytes
  `RetentionPolicy` variants onto an object-store ILM policy is a follow-on; the
  manifest-chain GC uses the `KeepAll`/`LastN` subset, registry-sourced.)
- Documentation Requirements: **met (2026-06-24)** — `checkpoint_format.md` notes the GC
  retention is a typed, registry-sourced `RetentionPolicy` (not the former `LastN 5`
  literal), cross-linking `durable_state_dsl.md`; the README durable-state registry note
  covers the retention prose.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

# Phase 52: Project the Durable-State `StoreRegistry` over MinIO Buckets

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Project the Durable-State StoreRegistry over MinIO Buckets. Single-session phase migrated from legacy Sprint 4.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 52.1: Project the Durable-State `StoreRegistry` over MinIO Buckets [✅ Done]

**Status**: Done (reopened 2026-06-23; re-closed 2026-06-24) — unblocked by Phase 2
Sprint `2.15` (the durable-state DSL foundation).

Source this phase's MinIO bucket set from the single `StoreRegistry` declared in
`dhall/project/Schema.dhall` / `JitML.Project.Config`, replacing the parallel
un-typed Haskell surface:

- `JitML.Storage.Buckets.bucketNames` is now a projection of the registry's
  `ObjectBucket` physical names (`projectStores defaultProjectConfig`), retiring the
  hand-written `[Text]` literal. The registry is the single source of truth for the
  bucket set, so a bucket exists only if it is a declared `Live` store.
- (The Pulsar `MessageTopic` projection onto `JitML.Coordinator.Topology` is owned by
  Phase 5 Sprint `5.15`, which owns topic derivation.)

### Exit Definition

- The MinIO bucket set is the registry projection; the bare `bucketNames :: [Text]`
  literal is gone (set-equal to the prior seven buckets, validated by `jitml-e2e`).
- The legacy-tracking row owned by this sprint (the `bucketNames :: [Text]` literal)
  moves to `Completed`.

### Validation State (2026-06-24)

- `cabal build lib:jitml` clean (`Storage.Buckets` + `Cluster.Readiness` recompile);
  `bucketNames` evaluates to the seven registry `ObjectBucket` physical names.
- `jitml-unit` 217/217; `jitml-e2e` 23/23 (incl. "chart values include every typed
  MinIO bucket" — the bucket-set drift guard holds against the projection).

### Remaining Work

- None on the bucket-set source-of-truth surface. Threading a per-write
  `RegisteredBucket` witness through every write site (so the hardcoded
  `BucketName "…"` literals also route through the registry) is a follow-on tracked by
  the legacy ledger's "Haskell-only bucket literals" row; the bucket *set* is now
  registry-sourced.
- Documentation Requirements: **met (2026-06-24)** — `cluster_topology.md` notes the
  bucket set is now the registry projection (`bucketNames` over `ObjectBucket` entries),
  cross-linking `durable_state_dsl.md`; the README durable-state registry note covers the
  MinIO bucket prose.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

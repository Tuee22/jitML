# Phase 13: Scoped `allow-newer` Retirement Gate

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Scoped allow-newer Retirement Gate. Single-session phase migrated from legacy Sprint 1.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 13.1: Scoped `allow-newer` Retirement Gate [✅ Done]

**Status**: Done
**Implementation**: `cabal.project`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Remove the scoped `allow-newer` block from `cabal.project`. This sprint first
closed the override by using temporary upstream source pins and local
`lens-family` compatibility packages; Sprint `1.11` later removed that helper
when the project baseline moved to GHC `9.12.4`.

### Deliverables

- `cabal.project` drops the compatibility override entirely.
- The `Scoped allow-newer for Dhall / CBOR transitive package bounds` row moves
  from Pending Removal to Completed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- The source-pin/vendor helper introduced during this sprint is no longer part
  of the current package set; Sprint `1.11` deletes it.

### Validation

1. `cabal build all --dry-run` solves with no `allow-newer` stanza in
   `cabal.project`.
2. `docker compose build jitml` passes and the image build runs the
   container-only `jitml check-code` gate.
3. `docker compose run --rm jitml jitml check-code` passes after the block is
   removed.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

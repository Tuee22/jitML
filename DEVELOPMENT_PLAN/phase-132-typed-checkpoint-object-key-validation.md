# Phase 132: Typed Checkpoint Object-Key Validation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Typed Checkpoint Object-Key Validation. Single-session phase migrated from legacy Sprint 10.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 132.1: Typed Checkpoint Object-Key Validation [✅ Done]

**Status**: Done (reopened 2026-06-29; re-closed 2026-06-30)
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Checkpoint/Format.hs`, `src/JitML/App.hs`,
`test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/haskell_code_guide.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `system-components.md`

### Objective

Keep the local filesystem-backed checkpoint store traversal-safe while returning
validation failures through typed command paths instead of `error`.

### Deliverables

- Change local object-key-to-path conversion to return `Either Text FilePath`
  for empty, absolute, or parent-traversing keys.
- Thread the typed validation result through local checkpoint read/write/list
  operations.
- Make local `jitml internal gc --experiment-hash ...` reject unsafe hashes with
  `InvalidConfig`, not process termination.
- Add tests for unsafe local keys and valid checkpoint prefixes.

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  **237 / 237**, including typed unsafe-key local store regressions.
- `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed **77 / 77**, including the spawned-binary `jitml internal gc
  ../escape` `InvalidConfig` regression and **19 / 19** `Live` cases.
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`).

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

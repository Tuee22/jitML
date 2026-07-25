# Phase 11: `Env` Record and `ReaderT Env IO` Runner

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Env Record and ReaderT Env IO Runner. Single-session phase migrated from legacy Sprint 1.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 11.1: `Env` Record and `ReaderT Env IO` Runner [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Env/Env.hs`, `src/JitML/Env/Build.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Establish the single `Env` record and the `ReaderT Env IO` runner that command
runners thread through, per doctrine `Application Environment`.

### Deliverables

- `Env` record in `src/JitML/Env/Env.hs` carrying:
  - `envCacheDir :: Path Abs Dir` (resolves explicit `--cache-dir <path>` or
    defaults to `./.build/`),
  - `envDataDir :: Path Abs Dir` (resolves explicit `--data-dir <path>` or
    defaults to `./.data/`),
  - `envFormat :: OutputFormat`, `envColor :: ColorMode`,
  - `envLogger :: ProcessOutcome -> IO ()` (defaults to structured JSON on
    stderr; daemon overrides),
  - `envClock :: IO MonotonicTime` (test-hook seam per doctrine
    [§Test hooks in Env](../README.md)).
- `buildEnv :: GlobalFlags -> IO Env` is the single entry point used by
  `App.main`.
- All command runners are `ReaderT Env IO` actions; raw `IO` is hlint-forbidden
  outside `runStreaming` / `capture` and the daemon main loop.

### Validation

1. `jitml --format json commands --json | jq '.format'` returns `"json"`.
2. `jitml --cache-dir /tmp/jitml internal gc <hash> --dry-run` resolves the
   cache against the explicit CLI override.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

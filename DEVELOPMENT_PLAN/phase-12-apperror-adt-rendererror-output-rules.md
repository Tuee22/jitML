# Phase 12: `AppError` ADT, `renderError`, Output Rules

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: AppError ADT, renderError, Output Rules. Single-session phase migrated from legacy Sprint 1.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 12.1: `AppError` ADT, `renderError`, Output Rules [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/CLI/Output.hs`, `src/JitML/AppError/AppError.hs`,
`src/JitML/AppError/Render.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Land the canonical `AppError` ADT, the single Text rendering boundary
`renderError`, exit codes including the `3`-on-no-op-on-match for reconcilers,
and the doctrine-mandated output flags `--format` and `--color`.

### Deliverables

- `AppError` ADT in `src/JitML/AppError/AppError.hs` carries the canonical
  20-variant set per [system-components.md → CLI Doctrine
  Components](system-components.md#cli-doctrine-components):
  `PrerequisiteUnmet`, `SubprocessFailed`, `MinIOFailed`, `PulsarFailed`,
  `HarborFailed`, `KubectlFailed`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidConfig`, `DhallTypeError`, `ChartLintFailed`, `RouteRegistryDrift`,
  `JitCacheMiss`, `CheckpointFormatUnsupported`,
  `CheckpointWriteConflict`, `InferenceCheckpointMissing`,
  `InferenceManifestShaMismatch`, `TrainingPrerequisiteUnmet`,
  `ReconcilerNoop`.
- `renderError :: AppError -> Text` is the only Text rendering at the CLI
  boundary, defined in `src/JitML/CLI/Output.hs`. Sprint `1.4` has `.hlint.yaml`
  hints and an in-repo primitive scan for direct terminal formatting and
  subprocess primitives outside their approved modules.
- Exit codes follow doctrine `Error Handling` plus `3` on `ReconcilerNoop`
  (already declared in [00-overview.md → Hard Constraints item
  11](00-overview.md#hard-constraints)).
- Global flags `--format json|table|plain` and `--color auto|always|never` plus
  `--no-color` are wired through `Env` per doctrine `Output Rules`. Default is
  `table` on TTY else `plain`.

### Validation

1. Each `AppError` variant has a snapshot render fixture under
   `test/snapshots/cli/` (pure renderer output — falls under
   [../README.md → Snapshot targets](../README.md#snapshot-targets)).
2. Exit code on a forced `ReconcilerNoop` is `3`.
3. `jitml --format json commands` emits valid JSON; `jitml --format plain
   commands` emits a deterministic plain-text list.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

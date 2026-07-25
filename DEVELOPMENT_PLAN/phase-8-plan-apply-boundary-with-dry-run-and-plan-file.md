# Phase 8: `Plan` / `apply` Boundary with `--dry-run` and `--plan-file`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Plan / apply Boundary with --dry-run and --plan-file. Single-session phase migrated from legacy Sprint 1.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 8.1: `Plan` / `apply` Boundary with `--dry-run` and `--plan-file` [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Plan/Plan.hs`, `src/JitML/Plan/Apply.hs`,
`src/JitML/Plan/Render.hs`
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Establish the `Plan` / `apply` separation per doctrine `Plan / Apply`, with
`--dry-run` and `--plan-file <path>` on every Plan/Apply command.

### Deliverables

- `Plan` ADT in `src/JitML/Plan/Plan.hs` parameterised over `inputs` and
  `result`. `build :: inputs -> Either AppError Plan` is pure; `apply :: Env ->
  Plan -> IO ExitCode` is the only IO-ful side.
- `--dry-run` renders the plan to stdout via `renderPlan` and exits `0`.
- `--plan-file <path>` writes the rendered plan to `<path>` for out-of-band
  review and exits `0`.
- The current Plan/Apply branch is wired for `jitml bootstrap`, `jitml service`,
  `jitml cluster up`, `jitml train`, `jitml tune`, `jitml rl train`,
  `jitml test all`, and `jitml internal gc` when `--dry-run` or `--plan-file` is
  requested. Normal command execution still uses local command implementations;
  live effectful application remains later-phase work.

### Validation

1. `jitml train --dry-run path/to/experiment.dhall` emits a typed plan and
   exits `0` without side effects.
2. `jitml train --plan-file /tmp/p.txt path/to/experiment.dhall` writes
   `/tmp/p.txt` and exits `0`.
3. `jitml-unit` exercises pure `build` invariants (snapshot render of the empty
   plan, idempotence of `--plan-file`).

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

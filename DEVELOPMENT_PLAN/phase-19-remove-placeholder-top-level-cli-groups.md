# Phase 19: Remove Placeholder Top-Level CLI Groups

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Remove Placeholder Top-Level CLI Groups. Single-session phase migrated from legacy Sprint 1.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 19.1: Remove Placeholder Top-Level CLI Groups [✅ Done]

**Status**: Done (closed 2026-06-27)
**Implementation**: `src/JitML/CLI/Spec.hs`, `src/JitML/App.hs`,
`test/unit/Main.hs`, generated CLI artifacts
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/cli/commands.md`, `README.md` generated command regions,
`share/man/man1/jitml.1`, shell completions

### Objective

Remove the top-level placeholder command groups whose behavior was either a
summary stub or a thin duplicate of better-owned surfaces: `verify`, `inspect`,
`bench`, and user-facing `kubectl`.

### Deliverables

- Delete the `verify`, `inspect`, `bench`, and `kubectl` command groups from
  `CommandSpec`, parser help, JSON/tree output, generated Markdown, manpage, and
  completions.
- Delete the corresponding `App.hs` dispatch handlers, including the
  `inspect replay` branch that duplicated checkpoint/inference verification
  now owned by `jitml inference run` and the test lanes.
- Keep effectful Kubernetes access inside bootstrap typed subprocesses and the
  daemon `HasKubectl` capability; no user-facing passthrough command remains.
- Keep benchmark/cache/daemon telemetry on `jitml test all --live` and `/metrics`.

### Validation

- `jitml docs generate`, then `jitml docs check`.
- `jitml commands --tree` contains no `verify`, `inspect`, `bench`, or `kubectl`
  top-level groups.
- `jitml-unit` parser/canonical-leaves snapshots pass.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

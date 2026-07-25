# Phase 18: Retire VM lifecycle commands for fixed-bridge Apple Metal

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Retire VM lifecycle commands for fixed-bridge Apple Metal. Single-session phase migrated from legacy Sprint 1.15 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 18.1: Retire VM lifecycle commands for fixed-bridge Apple Metal [✅ Done]

**Status**: Done (2026-06-12)
**Implementation**: `src/JitML/CLI/Spec.hs`, `src/JitML/App.hs`, generated CLI artifacts
**Docs to update**: `documents/engineering/cli_command_surface.md`, `documents/cli/commands.md`, `README.md` generated command regions

### Objective

Remove the Tart VM lifecycle command group from the canonical CLI surface and
make Apple fixed-bridge diagnostics visible through the existing prerequisite
introspection path. Adopts `CommandSpec`, `Generated documentation flow`, and
`Prerequisites as typed effects` from [../README.md](../README.md).

### Deliverables

- Delete the `internal vm` leaves from `CommandSpec`, their parser/app handlers,
  generated command docs, manpage, completions, and README generated command
  regions.
- Keep `internal list-prereqs` and `doctor --scope toolchain|container` as the
  operator-visible way to see `apple.metal-runtime`, `apple.metal-bridge`, and
  optional `apple.swiftc` / `apple.macos-sdk` capability state.
- Move the `jitml internal vm` row in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) to
  `Completed` when the generated docs and code agree.

### Validation

- `jitml docs generate`, then `jitml docs check`.
- `jitml commands --tree` contains no `internal vm` leaves and still contains
  `internal list-prereqs`.
- `jitml-unit` parser/canonical-leaves snapshots pass.

### Validation State (2026-06-12)

- `cabal run exe:jitml -- docs generate` regenerated the command artifacts from
  the edited `CommandSpec`.
- `docker compose build jitml` passed, including the in-image
  `jitml check-code` gate.
- `docker compose run --rm jitml jitml docs check` passed.
- `docker compose run --rm jitml jitml commands --tree` contains no
  `internal vm` leaves and still contains `internal list-prereqs`.
- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  196 / 196.
- A repo-wide search over `README.md`, generated CLI docs/manpage/completions,
  `src/`, and `test/` finds no `internal vm` command residue outside historical
  development-plan records.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

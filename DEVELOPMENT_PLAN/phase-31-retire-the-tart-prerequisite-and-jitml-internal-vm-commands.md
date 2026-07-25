# Phase 31: Retire the Tart Prerequisite and `jitml internal vm` Commands

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Retire the Tart Prerequisite and jitml internal vm Commands. Single-session phase migrated from legacy Sprint 2.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 31.1: Retire the Tart Prerequisite and `jitml internal vm` Commands [✅ Done]

**Status**: Done (2026-05-30)
**Implementation**: `src/JitML/Prerequisite/Nodes/Container.hs`
(`container.tart` node + `container.apple-silicon.jit-cache-miss` deps),
`src/JitML/CLI/Spec.hs` (`internal vm` command group),
`src/JitML/App.hs` (`runInternalVmLifecycle` / `runInternalVmExec`),
`src/JitML/Tart/*` (deleted)
**Docs to update**: `../documents/engineering/cli_command_surface.md`,
`../documents/engineering/haskell_code_guide.md`,
`documents/cli/commands.md` (regenerated via `jitml docs generate`)

### Objective

With the Apple Metal build moving to a host CommandLineTools `swift build` +
runtime `MTLDevice.makeLibrary(source:)` (Phase `7` Sprint `7.8`), the Tart VM is
no longer part of the prerequisite DAG or the CLI surface. Remove the
`container.tart` node, the `jitml internal vm` command group, and the lazy-tart
prerequisite contract. Adopts `Prerequisites as Typed Effects` and `CommandSpec`
from [../README.md](../README.md).

### Deliverables

- `container.tart` removed from `JitML.Prerequisite.Nodes.Container`; the
  `container.apple-silicon.jit-cache-miss` node drops its `container.tart`
  dependency (the Apple cache miss now needs only the host toolchain).
- The `jitml internal vm bootstrap|up|down|status|exec` command group removed from
  `CommandSpec` and its `App.hs` handlers; `documents/cli/commands.md` regenerated.
- `src/JitML/Tart/{Build,Lifecycle,Exec}.hs` deleted; `jitml.cabal` updated.
- The prerequisite-closure unit test and the Tart-plan unit test removed/updated.
- Removals tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `cabal build all` clean; `cabal test jitml-unit` green.
2. `jitml docs check` green after `jitml docs generate` (no `internal vm` verbs).
3. `grep -rn -i "tart" src` returns nothing after closure.

### Remaining Work

- None. Landed 2026-05-30: deleted `src/JitML/Tart/{Build,Lifecycle,Exec}.hs`,
  removed the `jitml internal vm` command group + `App.hs` handlers (commands.md /
  man / completions regenerated, `jitml docs check` ok), removed the
  `container.tart` prerequisite node + its `jit-cache-miss` dependency, and
  updated the unit tests (`grep -rn tart src` is clean; 183 `jitml-unit` pass;
  `cabal build all` clean).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

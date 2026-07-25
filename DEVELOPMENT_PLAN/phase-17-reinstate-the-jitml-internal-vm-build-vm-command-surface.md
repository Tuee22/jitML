# Phase 17: Reinstate the `jitml internal vm` build-VM command surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reinstate the jitml internal vm build-VM command surface. Single-session phase migrated from legacy Sprint 1.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 17.1: Reinstate the `jitml internal vm` build-VM command surface [✅ Done]

**Status**: Done (2026-06-10)
**Implementation**: `src/JitML/CLI/Spec.hs` (`vmCommand`), `src/JitML/App.hs` (`runInternalVmExec`, `runInternalVmLifecycle`)
**Docs to update**: `documents/engineering/cli_command_surface.md`, `documents/cli/commands.md`, `README.md` (generated command tree/registry)

### Objective

Reinstate the `jitml internal vm` command group that drives the `jitml`-managed
Tart build VM lifecycle, so the CLI surface matches the now-retired Apple Silicon
Tart-VM build-JIT doctrine (superseded by
[../documents/engineering/apple_silicon_metal_headless_builds.md → Why Tart Is Not Viable](../documents/engineering/apple_silicon_metal_headless_builds.md#why-tart-is-not-viable)).

### Deliverables

- `CommandSpec` leaf group `internal vm` with `up` / `down` / `status` / `exec`
  plus `create` / `delete`, rendered into the generated CLI mirror, `--help`,
  JSON schema, Markdown, manpages, and the README command tree / registry.
- Leaves dispatch through the typed `Subprocess` boundary to `tart` (the actual
  lifecycle is owned by Phase `2` Sprint `2.11`; this sprint owns only the surface).
- Regenerated CLI artifacts via `jitml docs generate`.

### Validation

- `jitml docs check` green (generated CLI mirror matches `CommandSpec`).
- Container `jitml check-code` green.
- `jitml-unit` parser snapshots updated and passing.

### Validation State (2026-06-10)

- `CommandSpec` carries the `internal vm` group (`create`/`up`/`down`/`status`/
  `delete`/`exec`); the generated CLI mirror, README command tree/registry, and
  `documents/cli/commands.md` were regenerated via `jitml docs generate` and
  `jitml docs check` passes.
- `jitml-unit` green (the canonical-leaves registry test includes the six new
  `internal vm` leaves).
- Exercised live on Apple M1 / macOS 26: `jitml internal vm status` →
  `jitml-build stopped`; `jitml internal vm up` boots the VM **headless** (the
  prior `VZErrorDomain … HostKey` blocker did not recur); `jitml internal vm down`
  stops it. `internal vm exec`'s live passthrough is exercised by Phase `7` Sprint
  `7.10`'s live closure (2026-06-10): the apple-silicon lane drove in-VM
  `swift build` through this surface and built/ran every Metal kernel family.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

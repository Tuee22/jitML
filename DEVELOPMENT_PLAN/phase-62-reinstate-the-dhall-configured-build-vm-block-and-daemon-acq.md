# Phase 62: Reinstate the Dhall-configured build-VM block and daemon acquire

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reinstate the Dhall-configured build-VM block and daemon acquire. Single-session phase migrated from legacy Sprint 5.9 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 62.1: Reinstate the Dhall-configured build-VM block and daemon acquire [✅ Done]

**Status**: Done (2026-06-10)
**Implementation**: `src/JitML/Service/LiveConfig.hs` (build-VM block + render), `dhall/service/LiveConfig.dhall` (schema), `src/JitML/App.hs` (`ensureHostBuildVm` at `runService` acquire)
**Docs to update**: `documents/engineering/daemon_architecture.md`, `documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Give the daemon a Dhall-configurable build-VM block and make the `acquire`
lifecycle ensure the Tart build VM is up before the first Apple Silicon JIT build,
per the now-retired Apple Silicon Tart-VM build-JIT doctrine (superseded by
[../documents/engineering/apple_silicon_metal_headless_builds.md → Why Tart Is Not Viable](../documents/engineering/apple_silicon_metal_headless_builds.md#why-tart-is-not-viable)).

### Deliverables

- `LiveConfig` build-VM block with Dhall-configurable CPU / memory / storage and an
  idle timeout, surfaced in the host Dhall config.
- `acquire` ensures the VM is up on Apple Silicon (idempotent; cache hits need no
  VM); idle timeout tears the VM down.

### Validation

- Host Dhall round-trips the build-VM block; `jitml-unit` config tests pass.
- `jitml-daemon-lifecycle` exercises VM-up-on-acquire on an Apple host.
- Container `jitml check-code` green.

### Validation State (2026-06-10)

- `LiveConfig` carries the build-VM block (`buildVmCpu` / `buildVmMemoryMib` /
  `buildVmDiskGib` / `buildVmIdleTimeout`); the Haskell record, defaults, Dhall
  schema (`dhall/service/LiveConfig.dhall`), and renderer are in sync, and
  `jitml-unit` / `jitml docs check` are green.
- `ensureHostBuildVm` runs at `runService` acquire: on `AppleSilicon` +
  `SelfInference` it builds a `BuildVmConfig` from the LiveConfig resources + cwd
  and calls `TartLifecycle.ensureBuildVmUp` (non-fatal). The ensure-up path is the
  same one validated live on Apple M1 (headless boot succeeds).

The downstream full in-VM build that this acquire precedes is owned by Phase `7`
Sprint `7.10`, which re-closed `✅ Done` (2026-06-10) after the apple-silicon lane
built and ran every Metal kernel family through the VM.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

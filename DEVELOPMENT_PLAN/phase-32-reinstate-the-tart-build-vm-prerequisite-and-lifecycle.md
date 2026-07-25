# Phase 32: Reinstate the Tart build-VM prerequisite and lifecycle

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Reinstate the Tart build-VM prerequisite and lifecycle. Single-session phase migrated from legacy Sprint 2.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 32.1: Reinstate the Tart build-VM prerequisite and lifecycle [✅ Done]

**Status**: Done (2026-06-10)
**Implementation**: `src/JitML/Tart/Lifecycle.hs`, `src/JitML/Tart/Exec.hs`, `src/JitML/Prerequisite/Nodes/Container.hs`, `bootstrap/_lib.sh` (`purge` deletes the VM)
**Docs to update**: `documents/engineering/cluster_topology.md`, `documents/engineering/haskell_code_guide.md`, `system-components.md`

### Objective

Reinstate the `container.tart` prerequisite node and the `jitml`-owned Tart
build-VM lifecycle (create / start / stop / delete; `brew install` Tart if absent)
so the Apple Silicon JIT cache miss can build inside the VM, per the now-retired
Apple Silicon Tart-VM build-JIT doctrine (superseded by
[../documents/engineering/apple_silicon_metal_headless_builds.md → Why Tart Is Not Viable](../documents/engineering/apple_silicon_metal_headless_builds.md#why-tart-is-not-viable)).

### Deliverables

- `container.tart` typed Homebrew package prerequisite (via
  `homebrewPackagePrerequisite`), with `container.apple-silicon.jit-cache-miss`
  re-pointed to depend on it.
- VM lifecycle helpers (create with Dhall-configured CPU/memory/storage, start,
  stop, delete) over the typed `Subprocess` boundary; bootstrap provisions the VM
  and `purge` deletes it (replacing the delete-only `tart delete jitml-build`
  residue in `bootstrap/_lib.sh`).

### Validation

- `jitml doctor --scope toolchain` reports the `container.tart` node on an Apple host.
- An Apple cache miss provisions/uses the VM and the prerequisite closure includes
  `container.tart`.
- Container `jitml check-code` and `jitml-unit` (prerequisite-closure tests) green.

### Validation State (2026-06-10)

- `container.tart` is back in the registry and the
  `container.apple-silicon.jit-cache-miss` closure depends on it (verified by the
  `jitml-unit` prerequisite-closure test, now flipped to require `container.tart`).
- `JitML.Tart.Lifecycle` reinstates the VM lifecycle (clone + `tart set`
  CPU/memory/disk, run headless with the repo mounted via `--dir`, stop, delete,
  status). Exercised live on Apple M1 / macOS 26: provision/`up` boots the
  `jitml-build` VM **headless** (no `HostKey` error), `status` and `down` work.
- `bootstrap/_lib.sh` `purge` deletes the VM (full create lifecycle now lives in
  the daemon acquire / `jitml internal vm`).

**Self-management hardening (2026-06-10).** The lifecycle was hardened so the
binary provisions and runs the VM end-to-end with no manual help, validated on
Apple M1 (`jitml internal vm delete` → `up` clones + configures + boots +
waits-exec-ready in ~20s → `exec`, and `jitml test jitml-backends --apple-silicon`
drives the in-VM `swift build` path 17 / 17):

- **Grow-only disk.** `provisionBuildVm` sets CPU/memory unconditionally and grows
  the disk only when the configured size exceeds the cloned image's current disk
  (`diskGrowthTarget`). `tart set --disk-size` can only grow, and cirruslabs base
  images already ship a large disk, so the previous fixed `--disk-size` smaller
  than the base failed provisioning outright.
- **Detached-start fd isolation.** `JitML.Sub.Stream.startDetached` wires the
  long-lived `tart run` process's stdin/stdout/stderr to `/dev/null` rather than
  inheriting them, so the VM process cannot hold a parent's captured output pipe
  open. Without this, starting the VM from inside an output-captured context (a
  `jitml test` cabal run, the daemon) deadlocked the parent's stream reader, which
  never saw EOF.
- **Generous boot wait + reproducible base image.** `waitForTartExec` allows ample
  headroom for a cold first-clone boot, and `defaultTartBaseImage` is pinned to
  `macos-sequoia-xcode:16` (reproducible toolchain, reused from the local image)
  rather than a moving `:latest`. New `jitml-unit` cases cover `diskGrowthTarget`
  and the `tart list` status/disk parser.

The downstream Apple cache-miss build *using* this VM lifecycle is owned by Phase
`7` Sprint `7.10`, which re-closed `✅ Done` (2026-06-10) after the apple-silicon
lane drove the in-VM `swift build` for real.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

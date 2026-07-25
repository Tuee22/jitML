# Phase 33: Replace Tart prerequisites with fixed-bridge Apple cache prerequisites

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Replace Tart prerequisites with fixed-bridge Apple cache prerequisites. Single-session phase migrated from legacy Sprint 2.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 33.1: Replace Tart prerequisites with fixed-bridge Apple cache prerequisites [✅ Done]

**Status**: Done (2026-06-12)
**Implementation**: `src/JitML/Prerequisite/Nodes/Container.hs`, `src/JitML/Engines/MetalRuntime.hs`, `src/JitML/Cache/Layout.hs`, `bootstrap/_lib.sh`, `test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`, `documents/engineering/jit_codegen_architecture.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `system-components.md`

### Objective

Make the Apple Silicon prerequisite and cache model match the fixed-bridge
architecture: core execution requires an OS Metal runtime probe and a fixed
bridge probe, not Tart, a keychain, SwiftPM, full Xcode, or the offline `metal`
compiler. Adopts `Prerequisites as typed effects`, `Subprocesses as typed
values`, and `Built-artifact and JIT-cache discipline` from
[../README.md](../README.md).

### Deliverables

- Replace the core `container.tart` / `container.apple-silicon.jit-cache-miss`
  closure with `apple.metal-runtime` and `apple.metal-bridge` nodes. The runtime
  probe is device-only and avoids Swift/Xcode/keychain subprocesses; the bridge
  probe `dlopen`s/calls the fixed bridge's probe symbol, where the bridge owns
  the tiny runtime Metal compilation check.
- Add optional, non-core `apple.swiftc` and `apple.macos-sdk` nodes for future
  generated Swift modules. These nodes are not dependencies of training,
  inference, backend tests, or `jitml service`.
- Remove VM lifecycle cleanup from `bootstrap purge`; no bootstrap or cache-miss
  path starts/stops/deletes Tart.
- Change the Apple cache layout to persist source metadata at
  `./.build/jit/apple-silicon/<hash>.metal.json`, keyed by rendered MSL,
  launch metadata, bridge ABI version, Metal runtime policy, determinism
  options, and tuning choice.

### Validation

- `jitml doctor --scope toolchain` / `--scope container` reports the fixed-bridge
  Apple nodes and no core `container.tart` dependency.
- A synthetic Apple host with `xcrun -find metal` failing and no usable login
  keychain still passes the Metal runtime/bridge probes.
- `jitml-unit` prerequisite-closure and cache-layout tests pass.
- `bootstrap/apple-silicon.sh purge` preserves `./.build/jit/apple-silicon/` and
  invokes no `tart` subprocess.

### Validation State (2026-06-12)

- `cabal build lib:jitml test:jitml-unit` compiles the updated Metal runtime,
  prerequisite graph, cache-layout helper, and unit test executable.
- `docker compose build jitml` passes; the image build reports
  `check-code: ok` and the PureScript bundle build succeeds.
- `docker compose run --rm jitml jitml internal list-prereqs` shows
  `apple.metal-runtime`, `apple.metal-bridge`, `apple.swiftc`, and
  `apple.macos-sdk`, and contains no `container.tart` node.
- Static residue assertions pass: `bootstrap/` contains no `tart delete`,
  `run_command tart`, or `have tart`; `src/` and `bootstrap/` contain no
  `container.tart`; `JitML.Engines.MetalRuntime` contains no `swift` or
  `xcrun -find` subprocess.
- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passes
  **197 / 197** from a clean container Cabal build directory. The added cases
  cover the fixed-bridge prerequisite closure, device-only Metal runtime probe,
  and `<hash>.metal.json` cache path.
- `docker compose run --rm jitml jitml docs check` passes.
- `git diff --check` passes.

### Remaining Work

None. The remaining Tart lifecycle module, generated Swift package / VM
`swift build` cache-miss path, and Apple generated dylib symlink surface are not
Sprint `2.12` obligations; they remain tracked in Sprints `7.11` and `16.9`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

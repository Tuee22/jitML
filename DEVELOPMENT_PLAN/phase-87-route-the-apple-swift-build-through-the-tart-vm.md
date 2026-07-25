# Phase 87: Route the Apple `swift build` through the Tart VM

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Route the Apple swift build through the Tart VM. Single-session phase migrated from legacy Sprint 7.10 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 87.1: Route the Apple `swift build` through the Tart VM [✅ Done]

**Status**: Done (re-closed 2026-06-10 — live VM-built path exercised on Apple M1)
**Implementation**: `src/JitML/Engines/Engine.hs` (`compileSubprocess`), `src/JitML/Engines/Loader.hs` (`publishAppleArtifact`), `src/JitML/Engines/MetalLocal.hs` (`metalToolchainFingerprint`), `src/JitML/Engines/MetalRuntime.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`, `documents/engineering/determinism_contract.md`

### Objective

Build the Apple Silicon Swift glue dylib **inside the Tart VM** and copy the
artifact out to the host, per the now-retired Apple Silicon Tart-VM build-JIT
doctrine (superseded by
[../documents/engineering/apple_silicon_metal_headless_builds.md → Why Tart Is Not Viable](../documents/engineering/apple_silicon_metal_headless_builds.md#why-tart-is-not-viable)).
Execution stays host-native via `MTLDevice.makeLibrary(source:)`.

### Deliverables

- `compileSubprocess` for `AppleSilicon` dispatches `swift build` into the VM
  through the typed `Subprocess` boundary.
- `publishAppleArtifact` copies `libJitMLMetal.dylib` out of the VM into the
  content-addressed cache (atomic `tmp + rename`), repoints the stable FFI symlink.
- `metalToolchainFingerprint` keys on the VM image id + the VM `swiftc`/Metal
  toolchain version; `metalRuntimeAvailable` no longer requires a host
  `swiftc`/`metal` toolchain — only a visible host Metal device gates execution.

### Validation

- A forced Apple cache miss builds in the VM and produces a working host dylib;
  three runs of the identity + weighted Dense2D kernels are bit-equal.
- Container `jitml check-code` and `jitml-unit` Metal-probe snapshots green.

### Validation State (2026-06-10)

- Code landed and validated: `compileSubprocess` dispatches `swift build` into the
  VM via `tartExecSubprocess` against the shared-mount package path
  (`guestSourcePath`); `Loader.ensureKernelArtifact` ensures the build VM is up
  (`ensureBuildVmForSubstrate`) before the build and `publishAppleArtifact` copies
  the dylib out of the VM's `.build/release/`; `metalToolchainFingerprint` keys on
  `metal-build-vm-runtime-makelibrary`; `metalRuntimeAvailable` is relaxed to a
  visible-device-only gate (no host `swiftc`/`metal`). Host build clean,
  `jitml docs check` and `jitml-unit` green (including a new Metal-probe
  regression: device-visible + no host toolchain ⇒ available).

### Live Closure (2026-06-10)

The live JIT-build-through-VM path was exercised end-to-end on the Apple M1 host
and **passed**. The prior "Tart guest agent unreachable / `tart exec`
control-socket GRPC error" symptom traced to a deeper root cause: a stale host
`ctkd` (CryptoTokenKit) daemon had deadlocked the Virtualization.framework
auxiliary-storage (nvram) decryption, so the `jitml-build` macOS guest never
finished booting (no guest agent over vsock, no DHCP lease). Restarting `ctkd`
and launching the build VM in the host GUI (`gui/501`) launchd session let the
guest boot; `tart exec` then connected, and the in-VM `swift build` ran against
the shared-mount package path (`/Volumes/My Shared Files/jitml/.build/jit-src/...`).

- Forced Apple cache miss: `jitml test jitml-backends --apple-silicon` drove the
  in-VM `swift build` (Xcode 16 `swift-build`) of the generated Swift glue
  package; `publishAppleArtifact` copied `libJitMLMetal.dylib` out of the VM's
  `.build/release/` into the content-addressed cache, and the host `dlopen`ed it
  and JIT-compiled the embedded MSL via `MTLDevice.makeLibrary(source:)`.
- All **17** within-substrate apple-silicon cases PASS (62.84s, no skip
  sentinels): the identity kernel is **bit-equal across three runs** (Sprint
  16.2), the weighted Dense2D GEMM is **bit-deterministic across three runs**
  (Sprint 16.5), and the live Metal benchmark candidate runner produces a
  measurement (Sprint 16.3).
- `jitml-unit` 194 / 194 host-native (incl. the Metal-probe regression:
  device-visible + no host toolchain ⇒ available); container `jitml check-code`
  green.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

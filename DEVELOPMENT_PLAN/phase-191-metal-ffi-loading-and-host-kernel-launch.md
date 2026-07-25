# Phase 191: Metal FFI Loading and Host Kernel Launch

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Metal FFI Loading and Host Kernel Launch. Single-session phase migrated from legacy Sprint 16.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 191.1: Metal FFI Loading and Host Kernel Launch [✅ Done]

**Status**: Done (validated headless 2026-05-30, Apple M1 / macOS 26)
**Blocked by**: Sprint `190.1`
**Implementation**: `src/JitML/Engines/MetalRuntime.hs`,
`src/JitML/Engines/Local.hs` (Apple branch), new
`src/JitML/Engines/MetalLocal.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Load the symlinked `.dylib` produced by Sprint `16.1`, look up
`jitml_kernel`, `jitml_kernel_family_name`, and `jitml_kernel_output_count`
through `dlopen`, build an `MTLDevice` + pipeline + command buffer, launch
the kernel against a host input buffer, and copy the output back through
the FFI. Adopts `Capability Classes` from [../README.md](../README.md).

### Deliverables

- `JitML.Engines.MetalLocal.runMetalKernel` loads the symlinked dylib,
  resolves the three exported symbols, calls into `MTLDevice` /
  `MTLCommandQueue` / `MTLComputePipelineState` through the typed
  `JitML.Engines.MetalRuntime` boundary, and returns the output buffer
  to Haskell.
- `JitML.Engines.HasEngine` dispatches `apple-silicon` to
  `runMetalKernel` when the runtime probe reports Metal device
  visibility.
- The same-host bit-equality property holds: three successive
  invocations of the identity kernel produce bit-identical output (in
  the spirit of the closed Linux CPU same-host equality in
  `jitml-cross-backend`).

### Validation

1. On Apple Silicon, after Sprint `16.1` completes: `cabal test
   jitml-cross-backend --test-options='-p Apple'` exits `0` and asserts
   three successive identity-kernel runs produce bit-identical output.
2. `JitML.Engines.MetalRuntime.probeMetalRuntime` reports Metal device
   visibility on the same host.

### Code Surface Landed (2026-05-30)

- `JitML.Engines.MetalLocal.runMetalKernel` is implemented: it drives
  `ensureKernelArtifact` (Apple path; Phase `7` Sprint `7.8` moves this to a
  host `swift build`), `dlopen`s the cached `<hash>.dylib`, resolves
  `jitml_kernel_family_name` / `jitml_kernel_output_count` / `jitml_kernel`,
  and marshals the input / output buffers across the FFI — the mirror of
  `JitML.Engines.CudaLocal.runCudaKernel`.
- `JitML.Codegen.Metal` emits the host-callable launcher: a singleton
  `JitMLMetalLauncher` owning the `MTLDevice` / `MTLCommandQueue` and
  dispatching simd-aligned full threadgroups in single-stream launch order
  with bounded `jitml_kernel` shaders. (Phase `7` Sprint `7.8` switches the
  `MTLLibrary` source from the relocated metallib to in-process runtime
  `makeLibrary(source:)` with fast-math off.)
- `JitML.Engines.HasEngine` adds `LocalAppleSiliconEngine` +
  `runAppleSiliconEngine`, dispatching `apple-silicon` through
  `MetalLocal.runMetalFamilyKernel` when the Metal device is visible.
- `jitml-cross-backend` adds the Apple same-host bit-equality case
  ("apple-silicon kernel output is bit-equal across repeated runs
  (Sprint 16.2)"); it skips unless a Metal device is usable headless.
- All of the above compile host-native (`cabal build lib:jitml` +
  `cabal build jitml-cross-backend`, GHC `9.12.4`, exit 0).

### Remaining Work

- None. Validated headless 2026-05-30:
  `cabal run jitml-cross-backend -- -p apple-silicon` ran the real host build →
  `dlopen` → runtime `makeLibrary` → Metal launch → copy-back path and asserted
  three bit-identical identity-kernel runs. No objC class collision (the launcher
  is free functions over `let` globals).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

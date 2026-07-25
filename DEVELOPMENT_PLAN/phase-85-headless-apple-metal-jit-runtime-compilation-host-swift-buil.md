# Phase 85: Headless Apple Metal JIT — Runtime Compilation + Host Swift Build

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Headless Apple Metal JIT — Runtime Compilation + Host Swift Build. Single-session phase migrated from legacy Sprint 7.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 85.1: Headless Apple Metal JIT — Runtime Compilation + Host Swift Build [✅ Done]

**Status**: Done (validated headless 2026-05-30 on Apple M1, macOS 26, CommandLineTools `swiftc`)
**Implementation**: `src/JitML/Codegen/Metal.hs`, `src/JitML/Engines/Engine.hs`
(`compileSubprocess` AppleSilicon), `src/JitML/Engines/Loader.hs`
(`ensureKernelArtifact` AppleSilicon branch), `src/JitML/Engines/MetalLocal.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/determinism_contract.md`

### Objective

Replace the Tart-VM ahead-of-time Metal build with a fully headless JIT: the host
builds the generated Swift glue dylib with CommandLineTools `swift build` and the
generated launcher JIT-compiles the embedded Metal Shading Language at runtime via
`MTLDevice.makeLibrary(source:options:)`. Closes the Apple Silicon half of
[Exit Definition](README.md#exit-definition) item 1 (per-substrate JIT execution)
on the headless path. Adopts `Subprocesses as Typed Values` and `Generated
Artifacts → generated-on-demand` from [../README.md](../README.md).

### Deliverables

- `JitML.Codegen.Metal` drops the `Kernels.metal` `SourceFile` and the
  `.process("Kernels.metal")` resource; the generated Swift embeds the MSL as a
  string and the launcher calls `device.makeLibrary(source:options:)` with
  `MTLCompileOptions.fastMathEnabled = false` (Metal-4 `mathMode = .safe`). The
  `@_cdecl` C ABI (`jitml_kernel` / `jitml_weighted_kernel` / metadata) is
  unchanged.
- `compileSubprocess` AppleSilicon renders a host `swift build --package-path
  <dir> -c release` (no `tart exec`); `ensureKernelArtifact` runs it on the host,
  copies `<dir>/.build/release/libJitMLMetal.dylib` →
  `.build/jit/apple-silicon/<hash>.dylib`, and repoints the stable symlink. The
  metallib-publish step and `JITML_METALLIB_PATH` env are removed.
- `MetalLocal.metalToolchainFingerprint` is bumped
  (`metal-offline-metallib-in-vm` → `metal-runtime-makelibrary-host`) to
  invalidate stale cache entries.
- The Tart cache-miss build path (`src/JitML/Tart/*`) is retired; its removal is
  owned by Phase `2` Sprint `2.10` and tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- The `cabal.project` codegen-toolchain pin comment is renamed `Xcode/Metal` →
  `Metal/swiftc` to reflect the host CommandLineTools `swiftc` + OS Metal
  framework (no Xcode); the docs already use the new label.

### Validation

1. A one-time headless probe confirms `MTLCreateSystemDefaultDevice()` +
   `makeLibrary(source:)` + a compute dispatch succeed in jitML's execution
   context (a `Background` launchd session); fallback if not: run the host daemon
   in the user's login session.
2. `cabal test jitml-cross-backend --test-options='-p apple-silicon'` runs (not
   skips) headless and asserts three bit-identical identity-kernel runs plus the
   weighted Dense2D result, with no Tart VM present.
3. `cabal build all` clean; `cabal test jitml-unit` green.

### Validation (passed 2026-05-30, Apple M1 / macOS 26, headless `Background` session)

1. Headless Metal probe: CommandLineTools `swiftc` built a Metal-linking Swift
   program; `MTLCreateSystemDefaultDevice()` returned `Apple M1`;
   `makeLibrary(source:)` compiled MSL at runtime; the dispatch returned the
   expected output — no Xcode, no Tart VM.
2. `cabal run jitml-cross-backend -- -p apple-silicon` ran (not skipped) and
   passed both cases: identity-kernel output bit-identical across three runs, and
   weighted Dense2D == `[1, 4, 9]`, via the real host `swift build` → `dlopen` →
   runtime `makeLibrary` → Metal dispatch path. No objC class collision (the
   launcher is free functions over `let` globals, not a named class).
3. `cabal build all` clean; `cabal test jitml-unit` 185 / 185 (cache-key golden
   regenerated for the runtime-compile source).

### Remaining Work

- None. The Tart-VM build path is superseded; its module/CLI/config removal is
  owned by Phase `2` Sprint `2.10` and Phase `5` Sprint `5.8`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

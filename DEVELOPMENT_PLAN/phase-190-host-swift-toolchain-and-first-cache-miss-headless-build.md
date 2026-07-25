# Phase 190: Host Swift Toolchain and First-Cache-Miss Headless Build

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Host Swift Toolchain and First-Cache-Miss Headless Build. Single-session phase migrated from legacy Sprint 16.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 190.1: Host Swift Toolchain and First-Cache-Miss Headless Build [✅ Done]

**Status**: Done (validated headless 2026-05-30, Apple M1 / macOS 26)
**Implementation**: `src/JitML/Engines/Engine.hs` (`compileSubprocess`
AppleSilicon), `src/JitML/Engines/Loader.hs` (`ensureKernelArtifact`
AppleSilicon branch + `publishAppleArtifact`), `src/JitML/Engines/MetalRuntime.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/cluster_topology.md`
**Blocked by**: Phase `7` Sprint `85.1` (runtime-compile codegen + host build)

### Objective

Validate the headless host build on a real Apple Silicon machine: a first
`apple-silicon` JIT cache miss drives a host CommandLineTools `swift build` of the
generated Swift glue dylib (no Tart VM), and the runtime `MTLDevice.makeLibrary`
launcher compiles the embedded Metal shader in-process. Adopts `Subprocesses as
Typed Values` and `Prerequisites as Typed Effects` from
[../README.md](../README.md).

### Deliverables

- A one-time headless probe (`swiftc` + `MTLCreateSystemDefaultDevice()` +
  `makeLibrary(source:)` + a compute dispatch) confirms host Swift+Metal works in
  jitML's execution context; the fallback (run the daemon in the user's login
  session) is recorded if a pure `Background` session cannot reach the GPU.
- The first `apple-silicon` JIT cache miss drives `ensureKernelArtifact` →
  host `swift build --package-path <generated-source-dir> -c release` through the
  typed `Subprocess` boundary, copies the produced `libJitMLMetal.dylib` into
  `./.build/jit/apple-silicon/<hash>.dylib`, and repoints the stable symlink at
  `./.build/host/apple-silicon/<model-id>.dylib` via
  `JitML.Cache.Symlink.repointSymlink`.
- The cache-miss run completed headless without `AppError PrerequisiteUnmet` and
  at the time needed only the host Swift developer-tool gate (no full Xcode, no
  Tart VM). Sprint `16.9` supersedes this with the fixed-bridge core path, which
  does not require SwiftPM or Xcode for training/inference cache misses.

### Validation

1. On Apple Silicon, headless: the probe prints the expected compute result.
2. A controlled first cache miss (any `apple-silicon` kernel not yet under
   `./.build/jit/apple-silicon/`) drives the host build and writes the `.dylib`
   plus the symlink, headless, with no Tart VM present.

### Remaining Work

- None. Validated headless 2026-05-30: the first `apple-silicon` cache miss drove
  the host `swift build`, `publishAppleArtifact` copied the dylib to
  `./.build/jit/apple-silicon/<hash>.dylib` and repointed the symlink, and the
  kernel ran with no `AppError PrerequisiteUnmet` and no Tart VM. The prior
  Tart-VM provisioning obligation is retired (tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

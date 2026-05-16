# Phase 7: JIT Codegen and Per-Substrate Execution

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Stand up the per-substrate Haskell JIT source renderers (Metal,
> oneDNN C++, CUDA), the engine ABI between the Haskell daemon and the
> substrate-specific kernels, the content-addressed cache key inputs from the
> numerical core, the Apple Silicon hybrid pattern (host daemon + lazy tart
> spin-up + cluster RPC envelope), and the hardware auto-tuning surface that
> preserves the per-substrate determinism contract.

## Phase Status

✅ **Done** — Sprints `7.1` through `7.7` are `✅ Done` for the local
engine/catalog/runtime-source surface. The Haskell binary generates every JIT
compiler input source file on demand under
`./.build/jit-src/<substrate>/<hash>/`; static checked-in source/build
artefacts are removed from the build path and forbidden by lint.

## Phase Summary

This phase delivers substrate engine metadata under `src/JitML/Engines/`,
typed kernel handles, cache hit/miss decisions, deterministic launch envelopes,
deterministic engine flags, runtime source renderers under `src/JitML/Codegen/`,
cache key derivation from `KernelSpec`, canonical rendered source payload, and
`TuningChoice`, plus Tart command/state helpers. The local build plan surface
renders CUDA / oneDNN C++ / Metal-Swift compiler inputs under
`./.build/jit-src/<substrate>/<hash>/` and routes the compile command through
typed `Subprocess` values.

## Sprint 7.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface ✅

**Status**: Done
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Populate the local cache-key input surface and kernel-handle/cache-decision
surface, and lock the cache key derivation over `KernelSpec`, `Kind`,
`Substrate`, `ToolchainFingerprint`, `RuntimeSourcePayload`, and
`TuningChoice`. Real FFI loading remains target runtime work.

### Deliverables

- `KernelSpec` is the current local cache-key payload wrapper.
- `Kind` distinguishes `Training` from `Inference`.
- `ToolchainFingerprint`, `RuntimeSourcePayload`, and `TuningChoice` are typed
  cache-key inputs.
- `cacheKey` hashes the serialized kernel spec, kind, substrate, fingerprint,
  rendered-source payload, and tuning choice into a SHA-256 digest.
- `KernelHandle` names the engine, content hash, and canonical artifact path.
- `resolveKernelCache` returns a typed `JitCacheHit` or `JitCacheMiss` with the
  compile `Subprocess` needed to fill the cache.
- `loadKernel`, `HasJitCache`, and FFI `dlopen` behavior remain target runtime
  work.

### Validation

1. `jitml-unit` verifies the cache-key golden under `test/golden/cache/`.
2. `jitml-unit` verifies changing the rendered runtime-source payload changes
   the cache key.
3. `jitml-unit` verifies the typed cache-hit/cache-miss decision surface.

## Sprint 7.2: Engine ABI and `Engines` Module Skeleton ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`

### Objective

Define the current local engine metadata shared by every substrate: backend
name, artifact extension, deterministic flags, typed kernel input/output
shapes, deterministic launch envelope, and renderable build plan.

### Deliverables

- `Engine` records `engineSubstrate`, `engineBackend`, and
  `engineArtifactExtension`.
- `engineForSubstrate` maps `apple-silicon` to `metal` / `.dylib`,
  `linux-cpu` to `onednn` / `.so`, and `linux-cuda` to `cuda` / `.so`.
- `deterministicFlags` records the current per-substrate determinism summary.
- `renderEnginePlan` renders the local engine metadata.
- `KernelInputs`, `KernelOutputs`, and `EngineEnvelope` record the local launch
  ABI and reproducibility witness surface.
- `renderEngineEnvelope` renders the envelope for deterministic inspection.
- `HasEngine` live execution remains target runtime work.

### Validation

1. `cabal test jitml-cross-backend` verifies every substrate has
   deterministic flags.
2. `jitml-unit` validates local engine envelope rendering.

## Sprint 7.3: Linux CPU Engine and oneDNN Codegen Driver ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the current `linux-cpu` engine metadata and generated oneDNN-style C++
source renderer. Real oneDNN graph wrappers and runtime execution remain
target work.

### Deliverables

- `engineForSubstrate LinuxCPU` records backend `onednn` and artifact
  extension `.so`.
- `renderOneDnnSource` emits generated `kernel.cc` source with a fixed local
  reduction-block constant.
- `compileSubprocess` renders the `g++ -std=c++20 -O2 -fPIC -shared` command
  against the generated source directory.
- oneDNN runtime graph wrappers, AVX detection, and FFI loading are not
  implemented yet.

### Validation

1. `jitml build --dry-run --substrate linux-cpu` renders a generated-source
   directory and `g++` compile plan.
2. Live same-host reduction equality remains target validation.

## Sprint 7.4: Linux CUDA Engine and CUDA Codegen Driver ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the current `linux-cuda` engine metadata and generated CUDA C source
renderer. cuBLAS/cuDNN bindings and runtime execution remain target work.

### Deliverables

- `engineForSubstrate LinuxCUDA` records backend `cuda` and artifact extension
  `.so`.
- `renderCudaSource` emits generated `kernel.cu` source under the runtime
  source bundle.
- `compileSubprocess` renders the `nvcc --shared --compiler-options=-fPIC
  --use_fast_math=false -arch=sm_70` command against the generated source
  directory.
- cuBLAS/cuDNN bindings, deterministic algorithm-id capture, splitmix RNG, and
  FFI loading are not implemented yet.

### Validation

1. `jitml build --dry-run --substrate linux-cuda` renders a generated-source
   directory and `nvcc` compile plan.
2. Live CUDA transcript determinism remains target validation.

## Sprint 7.5: Apple Silicon Engine, Metal Codegen, Hybrid Host↔Cluster RPC ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Tart/Lifecycle.hs`, `src/JitML/Tart/Exec.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the current `apple-silicon` engine metadata, generated Swift/Metal package
renderer, Tart subprocess rendering, and Apple RPC topic names. Real Metal
execution and host↔cluster message flow remain target work.

### Deliverables

- `engineForSubstrate AppleSilicon` records backend `metal` and artifact
  extension `.dylib`.
- `renderMetalPackage` emits `Package.swift`, a Swift source file, and
  `Kernels.metal` into the runtime source bundle.
- `compileSubprocess` renders `tart ssh jitml-build -- swift build
  --package-path <generated-source-dir> -c release`.
- The route/topic documentation records `inference.command.apple-silicon` and
  `inference.event.apple-silicon` as the target host↔cluster RPC topics.
- Metal FFI loading, actual Tart VM execution, MinIO tensor handoff, and live
  Pulsar RPC are not implemented yet.

### Validation

1. `jitml build --dry-run --substrate apple-silicon` renders a generated
   Swift/Metal source directory and Tart `swift build` subprocess.
2. Live Tart cache-miss behavior and host↔cluster RPC remain target
   validation.

## Sprint 7.6: Hardware Auto-Tuning Within the Determinism Contract ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Expose `TuningChoice` as a cache-key input and deterministic metadata string.
Real hardware benchmarking and auto-tuning remain target work.

### Deliverables

- `TuningChoice` is a typed cache-key input in `src/JitML/Cache/Key.hs`.
- `defaultTuningChoice` is the current local choice.
- Runtime source renderers embed the tuning choice into generated source
  payloads.
- `cacheKey` includes the tuning choice and rendered-source payload, so changes
  invalidate the local cache key.
- Per-substrate knob spaces, benchmark selection, and deterministic-only cuDNN
  algorithm selection are not implemented yet.

### Validation

1. `jitml-unit` verifies the rendered runtime-source payload participates in
   the cache key.
2. Same-host kernel-output equality remains target validation.

## Sprint 7.7: Haskell-Owned Runtime JIT Source Generation ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/RuntimeSource.hs`,
`src/JitML/Codegen/{Cuda,OneDnn,Metal,SourceFile}.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the Haskell `jitml` binary the only source of JIT compiler inputs. Static
checked-in JIT build scripts and kernel source files are forbidden: no
checked-in CUDA `.cu`, no checked-in oneDNN C/C++ source, and no checked-in
Metal / Swift package source participates in a JIT build.

### Deliverables

- `RuntimeSource` ADT describes generated source bundles:
  `GeneratedCudaSource`, `GeneratedOneDnnSource`, `GeneratedMetalPackage`.
- `renderRuntimeSource :: KernelSpec -> Kind -> Substrate -> TuningChoice ->
  RuntimeSource` is pure and deterministic.
- `materializeRuntimeSource :: Env -> RuntimeSource -> Hash -> IO (Path Abs Dir)`
  writes compiler inputs under `./.build/jit-src/<substrate>/<hash>/` using
  temp-file + rename discipline.
- The compile plans invoke `nvcc`, the oneDNN C++ compiler path, or
  `swift build` only against the generated directory through `Subprocess`.
- `cacheKey` includes the canonical rendered source payload and the
  `TuningChoice`, so changing a renderer invalidates the compiled artefact.
- Static source/script scaffolds are removed, as tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#completed).
- `jitml lint files` rejects future checked-in JIT build scripts and checked-in
  substrate source extensions unless they are explicit golden fixtures under
  `test/golden/`.

### Validation

1. `jitml build --dry-run --substrate linux-cuda` shows a generated-source
   directory under `./.build/jit-src/linux-cuda/<hash>`.
2. `jitml build --dry-run --substrate linux-cpu` shows oneDNN C++ generated
   under `./.build/jit-src/linux-cpu/<hash>/`.
3. `jitml build --dry-run --substrate apple-silicon` shows Swift / Metal
   generated under `./.build/jit-src/apple-silicon/<hash>/` before the tart
   `swift build` command.
4. Removing documentation-only substrate folders does not change any JIT build
   plan or cache key.
5. `jitml-unit` golden tests prove `renderRuntimeSource` is deterministic and
   that renderer changes alter the generated-source hash.

### Remaining Work

- [x] Add the Haskell `RuntimeSource` renderers for CUDA, oneDNN C++, and
  Metal / Swift package generation.
- [x] Route every JIT compile plan through generated source under
  `./.build/jit-src/<substrate>/<hash>/`.
- [x] Remove checked-in JIT build scripts, checked-in `.cu`, checked-in `.cc`
  / `.cpp`, and checked-in Metal / Swift package inputs from the build path.
- [x] Add lint coverage that rejects future static JIT source/build artefacts.
- [x] Move the static-codegen pending-removal ledger row to `Completed` once
  the generated-source path validates.

## Doctrine Sections Cited

- [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values](../HASKELL_CLI_TOOL.md) (Sprints 7.3, 7.4, 7.5)
- [../HASKELL_CLI_TOOL.md → Long-Running Daemons in the Same Binary](../HASKELL_CLI_TOOL.md) (Sprint 7.5 — target host/cluster split represented by local config/topic surfaces)
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprint 7.5 — target host↔cluster RPC topics documented; live consumer remains target work)
- [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md) (Sprints 7.3, 7.4, 7.5)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/jit_codegen_architecture.md` — current local
  `KernelSpec` cache-key payload, cache key derivation, Haskell runtime source
  renderers, and per-substrate compile plans; target FFI loader, Apple hybrid
  runtime, host↔cluster RPC, and real auto-tuning surface.
- `documents/engineering/determinism_contract.md` — populate with the per-
  substrate floating-point semantics (Metal single-stream, oneDNN blocked
  reduction, CUDA warp-shuffle + `--use_fast_math=false` + cuDNN explicit
  algorithm-id pinning), the engine envelope shape, the cross-substrate
  tolerance methodology.
- `documents/engineering/daemon_architecture.md` — link to the
  `InferenceProxy` Apple-only surface.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → JIT Codegen Components` and `Substrates` rows
  remain aligned with `src/JitML/Engines/Engine.hs`, the Haskell runtime source
  generator target, and the static-codegen cleanup ledger.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

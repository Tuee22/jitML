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

🔄 **Active**. The phase owns
[Exit Definition](README.md#exit-definition) item 1 (three substrate JIT
source renderers behind one `jitml` binary: `apple-silicon` via generated
Metal/Swift, `linux-cpu` via generated oneDNN C++, `linux-cuda` via
generated CUDA), the per-substrate-execution half of item 5 (content
addressing + no static JIT inputs + the per-substrate determinism
contract holding), and contributes to item 12 (typed `Subprocess` for
`metal` / `nvcc` / `g++`). **Met today**: Sprints `7.1`, `7.2`, `7.7`
close the typed engine/kernel-handle/envelope surface, the
content-addressed cache key, and Haskell-owned runtime JIT source
generation (no static checked-in inputs; lint enforces). The Haskell
`KernelFamily` ADT under `src/JitML/Codegen/KernelFamily.hs` and the
per-substrate knob spaces under `src/JitML/Engines/Tuning.hs` are in
place; the family-aware renderers under `src/JitML/Codegen/{OneDnn,Cuda,Metal}.hs`
emit substrate-specific source for `identity`, `reduction`, `dense`,
`conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`, and `embedding`
families, embedding the kernel family, deterministic flags, and
deterministic-only cuDNN algorithm pin into the generated source payload.
**Unmet today**: Sprint `7.3` owes the live oneDNN graph wiring through
`HasEngine` production loading (needs `libdnnl` on the build host plus
the runtime graph driver beyond the family source scaffold); Sprint `7.4`
owes CUDA FFI loading + live `nvcc`/cuBLAS/cuDNN execution (gated by
absent NVIDIA hardware); Sprint `7.5` owes real Tart spin-up + Metal FFI
loading + live host↔cluster RPC (gated by absent Tart toolchain); Sprint
`7.6` owes the benchmark driver against real hardware + the same-host
equality assertion. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

## Phase Summary

This phase delivers substrate engine metadata under `src/JitML/Engines/`,
typed kernel handles, cache hit/miss decisions, deterministic launch envelopes,
deterministic engine flags, runtime source renderers under `src/JitML/Codegen/`,
cache key derivation from `KernelSpec`, canonical rendered source payload, and
`TuningChoice`, plus Tart command/state helpers. The local build plan surface
renders CUDA / oneDNN C++ / Metal-Swift compiler inputs under
`./.build/jit-src/<substrate>/<hash>/` and routes the compile command through
typed `Subprocess` values. `src/JitML/Engines/Local.hs` provides the first
same-host execution loop for `linux-cpu`: generated source materialization,
shared-object compilation, `dlopen`, symbol lookup, and deterministic fixture
execution.

The implemented execution path is intentionally narrow: it validates the
generated Linux CPU identity kernel through the real FFI boundary before the
production `HasEngine` loaders grow real oneDNN graph kernels, Apple Metal, and
Linux CUDA.

## Sprint 7.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface ✅

**Status**: Done
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Populate the local cache-key input surface and kernel-handle/cache-decision
surface, and lock the cache key derivation over `KernelSpec`, `Kind`,
`Substrate`, `ToolchainFingerprint`, `RuntimeSourcePayload`, and
`TuningChoice`. General production FFI loading remains target runtime work; the
local Linux CPU identity runner is owned by Sprint `7.3`.

### Deliverables

- `KernelSpec` is the cache-key payload wrapper.
- `Kind` distinguishes `Training` from `Inference`.
- `ToolchainFingerprint`, `RuntimeSourcePayload`, and `TuningChoice` are typed
  cache-key inputs.
- `cacheKey` hashes the serialized kernel spec, kind, substrate, fingerprint,
  rendered-source payload, and tuning choice into a SHA-256 digest.
- `KernelHandle` names the engine, content hash, and canonical artifact path.
- `resolveKernelCache` returns a typed `JitCacheHit` or `JitCacheMiss` with the
  compile `Subprocess` needed to fill the cache.
- `loadKernel` and `HasJitCache` remain target runtime work. Local `dlopen`
  behavior exists only for the Linux CPU identity fixture through
  `JitML.Engines.Local`.

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

Define the engine metadata shared by every substrate: backend
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
- `HasEngine` production execution remains target runtime work; the local Linux
  CPU identity execution path is implemented separately in
  `JitML.Engines.Local`.

### Validation

1. `cabal test jitml-cross-backend` verifies every substrate has
   deterministic flags.
2. `jitml-unit` validates local engine envelope rendering.

## Sprint 7.3: Linux CPU Engine and oneDNN Codegen Driver 🔄

**Status**: Active
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/Local.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cpu` engine metadata, generated oneDNN-style C++ source
renderer, and first same-host compile/load/run path for the generated
identity kernel; grow real oneDNN graph wrappers and production
`HasEngine` execution per `### Remaining Work` below.

### Deliverables

- `engineForSubstrate LinuxCPU` records backend `onednn` and artifact
  extension `.so`.
- `renderOneDnnSource` emits generated `kernel.cc` source with a fixed local
  reduction-block constant.
- `compileSubprocess` renders the `g++ -std=c++20 -O2 -fPIC -shared` command
  against the generated source directory.
- `JitML.Engines.Local` materializes the generated Linux CPU source, compiles
  it, loads `jitml_kernel` with `dlopen`, and executes a deterministic identity
  fixture through the Haskell FFI.
- `renderOneDnnFamilySource` extends the local renderer to emit
  `reduction`, `dense`, `conv2d`, `conv3d`, `batchnorm`, `layernorm`,
  `mha`, and `embedding` family scaffolds with deterministic
  block-stride reductions and layernorm with double-precision
  accumulation, embedding the kernel family into the generated payload.
- oneDNN runtime graph wrappers wired into `HasEngine` production
  loading and AVX-512 detection beyond the metadata surface are not
  implemented yet.

### Validation

1. `jitml build --dry-run --substrate linux-cpu` renders a
   generated-source directory and `g++` compile plan.
2. `cabal test jitml-cross-backend` compiles, loads, and executes the
   generated Linux CPU identity kernel.
3. Live validation (target): real oneDNN graph wrappers execute
   representative reduction / convolution / matmul kernels and reproduce
   bit-deterministic results within the per-substrate ULP tolerance.

### Remaining Work

- Wire the family-aware oneDNN sources into `HasEngine` production
  loading so `jitml service` actually executes generated SL/RL kernels
  on `linux-cpu`. The runtime graph driver needs a `libdnnl` link
  surface plus an FFI loader that dispatches by kernel family. The
  family-aware source renderer (`renderOneDnnFamilySource`) and
  deterministic-only primitive selection (`Engines.Tuning.linuxCpuKnobs`
  with `reduction-block`, `micro-kernel`, `thread-count`, and `fastmath
  = off`) already exist.
- Grow the AVX-512 detection beyond the metadata surface so generated
  source picks the right ISA path. The micro-kernel knob axis
  enumerates `onednn-jit-avx2`, `onednn-jit-avx512`, and
  `onednn-reference` already; the runtime needs to query CPUID and
  pick.
- Add the live oneDNN integration test behind `JITML_LIVE_E2E=1` once
  the production runtime graph driver lands.

## Sprint 7.4: Linux CUDA Engine and CUDA Codegen Driver 🔄

**Status**: Active
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cuda` engine metadata and generated CUDA C source
renderer; grow cuBLAS/cuDNN bindings, FFI loading, and runtime
execution per `### Remaining Work` below.

### Deliverables

- `engineForSubstrate LinuxCUDA` records backend `cuda` and artifact extension
  `.so`.
- `renderCudaSource` emits generated `kernel.cu` source under the runtime
  source bundle.
- `compileSubprocess` renders the `nvcc --shared --compiler-options=-fPIC
  --use_fast_math=false -arch=sm_70` command against the generated source
  directory.
- `renderCudaFamilySource` extends the local renderer to emit
  `reduction` (warp-shuffle), `dense` (cuBLAS scaffold), `conv2d`/`conv3d`
  (cuDNN scaffold pinning `CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM`),
  `batchnorm` (cuDNN `BATCHNORM_SPATIAL_PERSISTENT`), and `mha`
  (deterministic cuBLAS GEMM chain) families. The deterministic cuDNN
  algorithm pin is recorded in `Engines.Tuning.cuDnnDeterministicAlgorithms`
  and embedded in the generated source payload (which participates in
  the cache key).
- Live cuBLAS/cuDNN execution, FFI loading of the compiled `.so`,
  splitmix RNG path wiring, and the live transcript-determinism test
  remain blocked by absent NVIDIA hardware on the development host.

### Validation

1. `jitml build --dry-run --substrate linux-cuda` renders a
   generated-source directory and `nvcc` compile plan.
2. Live validation (target): generated `.cu` compiles via real `nvcc` on a
   GPU-backed Kind worker, the resulting `.so` loads through the Haskell
   FFI, cuBLAS/cuDNN-backed kernels execute, and a same-seed run produces
   a bit-identical transcript when deterministic algorithm IDs are pinned.

### Remaining Work

- Wire the family-aware CUDA source renderer into `HasEngine`
  production loading once NVIDIA hardware is reachable from the
  bootstrap host. The deterministic algorithm-id capture
  (`Engines.Tuning.cuDnnDeterministicAlgorithms`) and the
  no-`_FAST_MATH` / no-TF32 knob defaults are already in place.
- Add real cuBLAS/cuDNN typed bindings under the engine surface (the
  source-level scaffold pins the algorithm but the runtime driver still
  needs the binding crate equivalent in Haskell, e.g. `inline-c`).
- Wire the splitmix-based RNG path for any kernel using stochastic
  initialisation.
- Implement FFI loading of the compiled CUDA `.so` and plug it into
  `HasEngine` production loading.
- Add the live CUDA transcript-determinism integration test behind
  `JITML_LIVE_E2E=1` (Sprint `12.6`) — blocked by absent NVIDIA
  hardware.

## Sprint 7.5: Apple Silicon Engine, Metal Codegen, Hybrid Host↔Cluster RPC 🔄

**Status**: Active
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Tart/Lifecycle.hs`, `src/JitML/Tart/Exec.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the `apple-silicon` engine metadata, generated Swift/Metal package
renderer, Tart subprocess rendering, and Apple RPC topic names; grow real
Metal execution, Tart spin-up, and host↔cluster message flow per
`### Remaining Work` below.

### Deliverables

- `engineForSubstrate AppleSilicon` records backend `metal` and artifact
  extension `.dylib`.
- `renderMetalPackage` emits `Package.swift`, a Swift source file, and
  `Kernels.metal` into the runtime source bundle.
- `compileSubprocess` renders `tart ssh jitml-build -- swift build
  --package-path <generated-source-dir> -c release`.
- The route/topic documentation records `inference.command.apple-silicon` and
  `inference.event.apple-silicon` as the target host↔cluster RPC topics.
- `renderMetalFamilyPackage` extends the local Metal renderer to embed
  the per-substrate threadgroup-size knob into the generated Swift
  enum and emits family-aware Metal kernels (the `reduction` family
  uses `simd_sum` with single-stream launch ordering). The threadgroup
  axis is enumerated by `Engines.Tuning.appleSiliconKnobs`.
- Metal FFI loading, actual Tart VM execution, MinIO tensor handoff, and live
  Pulsar RPC are not implemented yet.

### Validation

1. `jitml build --dry-run --substrate apple-silicon` renders a generated
   Swift/Metal source directory and Tart `swift build` subprocess.
2. Live validation (target): on the first JIT cache miss for `apple-silicon`,
   the typed lifecycle spins up the `jitml-build` Tart VM, runs
   `swift build` inside it, atomically writes the resulting `.dylib` under
   `./.build/jit/apple-silicon/`, repoints the host-stable symlink, and
   the host daemon loads the kernel through the FFI. The cluster orchestrator
   round-trips a typed `(call-id, kind, model-id, inputs)` envelope on
   `inference.command.apple-silicon` and gets a typed reply on
   `inference.event.apple-silicon`.

### Remaining Work

- Implement real lazy Tart VM spin-up on first JIT cache miss, with
  postcondition validation of the VM's `swift build` toolchain.
- Implement Metal FFI loading of the compiled `.dylib` through the
  symlinked `./.build/host/apple-silicon/<model-id>.dylib`.
- Implement the typed host↔cluster RPC envelope flow (real Pulsar
  produce/consume on the `inference.command.apple-silicon` and
  `inference.event.apple-silicon` topics) with MinIO-staged tensor
  payloads.
- Add the live test that exercises the full host-resident inference path
  behind `JITML_LIVE_E2E=1` (Sprint `12.6`).

## Sprint 7.6: Hardware Auto-Tuning Within the Determinism Contract 🔄

**Status**: Active
**Implementation**: `src/JitML/Engines/Engine.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Expose `TuningChoice` as a cache-key input and deterministic metadata
string; grow real hardware benchmarking and per-substrate auto-tuning
per `### Remaining Work` below.

### Deliverables

- `TuningChoice` is a typed cache-key input in `src/JitML/Cache/Key.hs`.
- `defaultTuningChoice` is the default choice.
- Runtime source renderers embed the tuning choice into generated source
  payloads.
- `cacheKey` includes the tuning choice and rendered-source payload, so changes
  invalidate the local cache key.
- `src/JitML/Engines/Tuning.hs` defines per-substrate `KnobSpace`
  values: `appleSiliconKnobs` (threadgroup-size, matmul-tile,
  reduction-strategy, command-queue-discipline), `linuxCpuKnobs`
  (micro-kernel, reduction-block, thread-count, fastmath off),
  `linuxCudaKnobs` (matmul-tile, block-dim, cuDNN deterministic algo,
  reduction-strategy, no-TF32, no-fast-math). `selectDeterministic`
  picks the deterministic default per axis; `tuningChoiceForResult`
  emits the cache-key payload string.
- Benchmark-driven selection on real hardware and the same-host
  equality assertion against repeated runs remain open.

### Validation

1. `jitml-unit` verifies the rendered runtime-source payload participates
   in the cache key.
2. Live validation (target): per-substrate knob spaces drive
   benchmark-based selection on real hardware (matmul tile sizes,
   reduction strategies, cuDNN deterministic algorithm IDs) and the
   chosen tuning influences the cache key without breaking determinism.

### Remaining Work

- Implement a benchmark driver that picks the chosen knob set on first
  cache miss and records it for cache-key derivation. The
  deterministic default selection (`Engines.Tuning.selectDeterministic`)
  is in place; the missing piece is the on-hardware micro-benchmark
  loop that ranks the deterministic-only choices.
- Add a same-host kernel-output equality test that holds across repeated
  runs with the same tuning choice. Requires live hardware to be
  meaningful.

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

### Closure Checklist

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
- [../HASKELL_CLI_TOOL.md → At-Least-Once Event Processing](../HASKELL_CLI_TOOL.md) (Sprint 7.5 — host↔cluster RPC topics documented; live consumer owned by Sprint 7.5's Remaining Work)
- [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md) (Sprints 7.3, 7.4, 7.5)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/jit_codegen_architecture.md` — current local
  `KernelSpec` cache-key payload, cache key derivation, Haskell runtime source
  renderers, per-substrate compile plans, and Linux CPU identity
  compile/load/run path; target production FFI loader, Apple hybrid runtime,
  host↔cluster RPC, and real auto-tuning surface.
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

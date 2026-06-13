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
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Stand up the per-substrate Haskell JIT source renderers (Metal,
> oneDNN C++, CUDA), the engine ABI between the Haskell daemon and the
> substrate-specific kernels, the content-addressed cache key inputs from the
> numerical core, the Apple Silicon hybrid pattern (host daemon + fixed Metal
> bridge + cluster RPC envelope), and the hardware auto-tuning surface that
> preserves the per-substrate determinism contract.

## Phase Status

✅ **Done** (reopened 2026-06-12 for the true-headless Apple Metal
fixed-bridge doctrine; **re-closed the same day** after Sprint `7.11`). The
Apple engine renders canonical MSL plus launch metadata, persists
`<hash>.metal.json`, calls a fixed host Metal bridge, and keeps an in-process
pipeline cache keyed by source/function/launch policy. The core path does not
invoke `tart`, `swift build`, full Xcode, the offline `metal` compiler, or
keychain-dependent VM state. The Sprint `7.11` legacy rows moved to
[legacy-tracking-for-deletion.md → Completed](legacy-tracking-for-deletion.md#completed).
Prior closure history follows.

**Re-validation note (2026-06-06)**: this phase stays ✅ **Done** on its owned
code-surface obligations (the per-substrate source renderers, cache, typed
Subprocess plans, runtime probes), which are unchanged. The historical
RTX 3090 live-CUDA validation records in Sprint `7.4` and below (the
`nvcc → .so → dlopen → kernel launch → copy-back` path proven on
2026-05-24) are retained as dated history but no longer reflect the current
hardware: the live Linux CUDA execution obligation is owned by
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md),
which reopened 2026-06-06 for full re-validation on the current **RTX 5090**
host. See that phase's `## Phase Status` for the re-validation surface and the
`-arch=sm_70` / Blackwell `sm_120` risk that `JitML.Engines.Engine`'s CUDA
compile plan must re-clear.

✅ **Done** (reopened 2026-06-04 for the compose service split; **re-closed the
same day** after Sprint `7.9` moved GPU exposure to `jitml-cuda` while keeping
the default `jitml` service headless for code-quality and bootstrap commands).

✅ **Done** (reopened 2026-05-30 for the headless Apple Metal JIT workstream;
**re-closed the same day** after Sprint `7.8` landed and validated headless on
Apple M1). The Apple Silicon Metal build now uses a host CommandLineTools
`swift build` plus runtime `MTLDevice.makeLibrary(source:)` shader compilation
(no Tart VM, no full Xcode); the `.process("Kernels.metal")` /
`JITML_METALLIB_PATH` offline-metallib path is gone, and the `JitML.Tart.*`
modules are retired by Phase `2` Sprint `2.10` / Phase `5` Sprint `5.8` (see
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) and
[Reopened phases (2026-05-30)](README.md#reopened-phases-2026-05-30)). The
code-surface status text below predates the reopen.

✅ **Done** (code-surface only). After the 2026-05-24 refactor, this
phase carries only the code-surface portion of its owned obligations:
the per-substrate source renderers, content-addressed cache key +
storage, the typed Subprocess plans for `metal` / `nvcc` / `g++`, the
typed runtime probes, the typed candidate-runner scaffold, and the
benchmark-runner wiring into the first-cache-miss path. The live Apple
Metal execution path migrated to
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md);
the live Linux CPU full-tensor benchmark payload + first-cache-miss
execution path migrated to
[phase-13-linux-cuda-and-cluster-closure.md](phase-13-linux-cuda-and-cluster-closure.md)
Sprint `13.15`; cross-substrate equality / per-substrate ULP tolerance
migrated to
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md)
Sprint `15.1`.

The phase owns
[Exit Definition](README.md#exit-definition) item 1 (three substrate JIT
source renderers behind one `jitml` binary: `apple-silicon` via generated
Metal/Swift, `linux-cpu` via generated oneDNN C++, `linux-cuda` via
generated CUDA), the per-substrate-execution half of item 5 (content
addressing + no static JIT inputs + the per-substrate determinism
contract holding), and contributes to item 12 (typed `Subprocess` for
`metal` / `nvcc` / `g++`). **Met today**: Sprints `7.1`, `7.2`, `7.7`
close the typed engine/kernel-handle/envelope surface, the
content-addressed cache key, generic cache-hit/cache-miss artifact loading,
and Haskell-owned runtime JIT source generation (no static checked-in inputs;
lint enforces). Sprint `7.3` closes the local Linux CPU oneDNN runtime path:
the container image installs `libdnnl-dev`, generated Linux CPU sources include
oneDNN C++ headers, the compile plan links `-ldnnl`, and the local
`HasEngine` interpreter runs the generated family kernels through oneDNN
primitive launches behind the stable FFI metadata ABI. Sprint `7.4` closes
the live Linux CUDA runtime path: `jitml:local` installs `cuda-toolkit-12-8`
and `libcudnn9-dev-cuda-12`, `compose.yaml` exposes every host NVIDIA GPU
through the `jitml-cuda` service's `gpus: all` mapping, the CUDA compile plan now links the produced `.so`
against `libcudart` / `libcublas` / `libcudnn` (DT_NEEDED resolves at
`dlopen` time), `JitML.Engines.CublasBindings` / `CudnnBindings` provide
the typed Haskell binding surface behind the `cuda` cabal flag, and the
2026-05-24 in-container `cabal test -fcuda jitml-cross-backend` validation
on an RTX 3090 + CUDA 12.8 host exercises the full
nvcc → `.so` → `dlopen` → kernel launch → copy-back path with
bit-identical output across three repeated runs. The Haskell
`KernelFamily` ADT under `src/JitML/Codegen/KernelFamily.hs` and the
per-substrate knob spaces under `src/JitML/Engines/Tuning.hs` are in
place; the family-aware renderers under `src/JitML/Codegen/{OneDnn,Cuda,Metal}.hs`
emit substrate-specific source for `identity`, `reduction`, `dense`,
`conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`, and `embedding`
families, embedding the kernel family, deterministic flags, and
deterministic-only cuDNN algorithm pin into the generated source payload. The
CUDA reduction renderer emits one partial per warp with no device-side atomics,
and the generated CUDA FFI wrapper now exports a host-callable
`jitml_kernel(float*, const float*, size_t)` entrypoint that allocates device
buffers, launches the deterministic device kernel, synchronizes, and copies
outputs back to the host. `JitML.Engines.CudaRuntime` mirrors that launch
geometry to validate partial counts and fold CUDA reduction partials on the
host in canonical index order.
The generated Apple Swift package now exports the same
`jitml_kernel_family_name` metadata symbol and
`jitml_kernel_output_count` shape symbol; its reduction metadata reports the
ceiling number of simdgroup partial outputs produced by the generated Metal
kernel.
`JitML.Engines.Local.runLinuxCpuFamilyKernel` now drives every generated
Linux CPU oneDNN family kernel through the shared cache artifact loader and
local FFI symbol boundary, including the exported
`jitml_kernel_family_name` and `jitml_kernel_output_count` symbols used to
confirm the loaded artifact's family and output length. The local Linux CPU
toolchain fingerprint now includes `artifact-abi=<os>-<arch>` so host-native
Darwin artifacts and Linux container artifacts do not collide in the shared
`.build/jit/linux-cpu/` cache.
`JitML.Engines.HasEngine` defines the current typed engine capability surface
(`EngineRequest`, `EngineRun`, `HasEngine`) and the local
`LocalLinuxCpuEngine` interpreter that dispatches requested `KernelFamily`
values through that generated-family FFI path while rejecting loaded-family
metadata mismatches. It also exposes a `LocalCudaEngine` interpreter:
`JitML.Engines.CudaLocal` consumes a positive CUDA runtime probe before
materializing, compiling, `dlopen`ing, and running a generated CUDA artifact
through the same family/output-count metadata ABI. In `jitml:local` the
2026-05-24 live RTX 3090 run validated the full path end-to-end including
the typed Haskell cuBLAS / cuDNN binding initialization.
Sprint `7.6` now also has a deterministic benchmark-plan and measurement
selection surface: `JitML.Engines.Tuning.benchmarkPlan` enumerates the
per-substrate deterministic-only candidate `TuningResult`s, and
`selectMeasuredTuning` deterministically selects the lowest-latency measured
candidate with stable plan-order tie-breaking. `JitML.Engines.TuningStore`
persists a supplied measured selection under the JIT cache tree by substrate
and base hash so the chosen `TuningChoice` can be loaded by later runtime
cache-key wiring. `JitML.Engines.TuningBenchmark` collects benchmark
measurements through a typed candidate runner, captures SHA-256 output digests,
and persists the selected result through `TuningStore`. `JitML.Engines.TuningCache`
now derives the default base hash, loads any persisted selection for that base
hash, and renders the final runtime source/cache key from the selected
`TuningChoice`. `JitML.Engines.TuningBenchmark` also exposes guarded
`cudaBenchmarkCandidateRunner` and `metalBenchmarkCandidateRunner` boundaries:
they reject wrong-substrate candidates, probe CUDA/Metal runtime availability,
and run only when the local host exposes the matching runtime. Sprint `7.8`
historically replaced the former Tart VM cache-miss path with host
CommandLineTools `swift build` plus runtime `MTLDevice.makeLibrary(source:)`.
Sprint `7.11` supersedes that path with `.metal.json` source metadata and
fixed-bridge execution.

## Phase Summary

This phase delivers substrate engine metadata under `src/JitML/Engines/`,
typed kernel handles, cache hit/miss decisions, deterministic launch envelopes,
deterministic engine flags, runtime source renderers under `src/JitML/Codegen/`,
cache key derivation from `KernelSpec`, canonical rendered source payload,
`TuningChoice`, deterministic benchmark measurement selection, persisted
measured tuning selections, generic benchmark measurement collection with
output-digest capture, persisted-choice cache-key derivation, and a shared
`JitML.Engines.Loader` artifact path that materializes source, fills cache
misses through typed compile subprocesses, reports cache hits, and provides the
local `dlopen` symbol boundary. The local build
plan surface renders CUDA / oneDNN C++ compiler inputs under
`./.build/jit-src/<substrate>/<hash>/`; Sprint `7.11` changes Apple from
Metal-Swift package generation to `.metal.json` MSL source metadata consumed by
the fixed bridge. Linux compile commands route through typed `Subprocess`
values. `src/JitML/Engines/Local.hs` provides the first
same-host execution loop for `linux-cpu`: generated oneDNN source
materialization, shared-object compilation, `dlopen`, symbol lookup, and
deterministic execution for identity/reorder, reduction, dense/matmul,
2D/3D convolution, batchnorm, layernorm, attention/matmul, and embedding/reorder
families, and records the family name reported by the loaded artifact.
`JitML.Engines.HasEngine` exposes that Linux CPU generated-family path through
a typed `HasEngine` capability and local interpreter.

No Phase `7` execution gap remains. The Linux CUDA FFI / cuBLAS / cuDNN gap
closed in Sprint `7.4` on 2026-05-24, and the Apple generated Swift/Tart
cache-miss path was replaced by fixed-bridge source metadata in Sprint `7.11`.

## Sprint 7.1: `KernelSpec`, Cache Key Inputs, FFI Loader Surface ✅

**Status**: Done
**Implementation**: `src/JitML/Cache/Key.hs`, `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/Loader.hs`
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
- `JitML.Engines.Loader.ensureKernelArtifact` is the generic cache-hit/cache-miss
  artifact boundary: it materializes generated source, detects existing cache
  artifacts, runs the typed compile `Subprocess` on misses, and returns a
  `KernelArtifact` with the chosen `KernelHandle`.
- `JitML.Engines.Loader.withKernelSymbol` owns the reusable `dlopen`/`dlsym`
  helper used by the local Linux CPU FFI fixture.
- The production `HasEngine` graph-launch capability remains target runtime
  work.

### Validation

1. `jitml-unit` verifies the cache-key snapshot under `test/snapshots/cache/`
   (pure-renderer output; see [../README.md → Snapshot
   targets](../README.md#snapshot-targets)).
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
- Full production non-CPU `HasEngine` graph execution remains target runtime
  work; the local Linux CPU oneDNN primitive execution path is implemented in
  `JitML.Engines.Local` and exposed through
  `JitML.Engines.HasEngine.LocalLinuxCpuEngine`.

### Validation

1. `cabal test jitml-cross-backend` verifies every substrate has
   deterministic flags.
2. `jitml-unit` validates local engine envelope rendering.

## Sprint 7.3: Linux CPU Engine and oneDNN Codegen Driver ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/HasEngine.hs`, `src/JitML/Engines/Loader.hs`,
`src/JitML/Engines/Local.hs`, `src/JitML/Engines/OneDnnRuntime.hs`,
`src/JitML/Codegen/OneDnn.hs`, `docker/Dockerfile`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cpu` engine metadata, generated oneDNN-style C++ source
renderer, and first same-host compile/load/run path for the generated
identity kernel; grow the path into libdnnl-linked oneDNN primitive launches
behind the local production `HasEngine` execution surface.

### Deliverables

- `engineForSubstrate LinuxCPU` records backend `onednn` and artifact
  extension `.so`.
- `renderOneDnnSource` emits generated `kernel.cc` source with oneDNN C++
  headers, a fixed local reduction-block constant, and the exported
  `jitml_kernel_family_name` metadata symbol plus `jitml_kernel_output_count`
  for family-specific output length reporting.
- `docker/Dockerfile` installs `libdnnl-dev`, and `compileSubprocess` renders
  the `g++ -std=c++20 -O2 -fPIC -shared ... -ldnnl` command against the
  generated source directory.
- `JitML.Engines.Local` routes generated Linux CPU source through
  `JitML.Engines.Loader.ensureKernelArtifact`, loads `jitml_kernel` with the
  shared `withKernelSymbol` helper, loads `jitml_kernel_family_name` and
  `jitml_kernel_output_count`, and executes a deterministic identity fixture
  through the Haskell FFI while recording the family reported by the artifact
  and reading exactly the output count reported by the artifact.
- `JitML.Engines.Local.linuxCpuToolchainFingerprint` includes the local
  `artifact-abi=<os>-<arch>` plus `reduction-block=256` in the cache-key
  input so host/container loader ABIs and fixed reduction-block changes do not
  share a Linux CPU artifact path. `jitml build` uses that fingerprint for
  `--substrate linux-cpu` cache-key selection.
- `renderOneDnnFamilySource` extends the local renderer to emit
  `identity`, `reduction`, `dense`, `conv2d`, `conv3d`, `batchnorm`,
  `layernorm`, `mha`, and `embedding` family kernels backed by oneDNN C++
  primitive launches under the current flat fixture ABI: reorder for
  identity/embedding, reduction for reduction, matmul for dense and MHA,
  unit 2D/3D convolution for convolution families, and oneDNN
  batch/layer-normalization primitives for normalization families. The kernel
  family and tuning metadata remain embedded in the generated source payload.
- `JitML.Engines.Local.runLinuxCpuFamilyKernel` materializes, compiles, loads,
  and executes each generated oneDNN family kernel through the same
  cache-artifact loader and FFI symbol boundary, validating the reported family
  name and family-specific output length against the requested `KernelFamily`
  in `jitml-cross-backend`.
- `JitML.Engines.HasEngine` defines `EngineRequest`, `EngineRun`, and the
  `HasEngine` class plus a `LocalLinuxCpuEngine` interpreter. `runLinuxCpuEngine`
  dispatches requested `KernelFamily` values through the generated-family FFI
  path and rejects any loaded artifact whose exported
  `jitml_kernel_family_name` differs from the request.
- `JitML.Engines.OneDnnRuntime.probeOneDnnRuntime` establishes the typed
  `libdnnl` runtime/link availability boundary: it probes
  `pkg-config --modversion dnnl`, `pkg-config --modversion onednn`, readable
  oneDNN headers at `/usr/include/oneapi/dnnl/dnnl.hpp` /
  `/usr/include/dnnl.hpp`, and `ldconfig -p` through typed subprocesses,
  renders the selected package/header/library visibility, and reports
  availability when either package metadata or headers plus dynamic-linker
  `libdnnl` visibility are present.
- `JitML.Service.Workload` exposes an injectable checkpoint inference runner,
  `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference` threads that
  runner through parsed `RunInference` workload effects and inference-domain
  command envelopes, and `jitml service` selects
  `JitML.Engines.Local.runLinuxCpuCheckpointInference` for
  `linux-cpu` + `SelfInference` daemon configs. This wires the Linux CPU
  service path to the generated-kernel FFI runner after the latest pointer and
  manifest are loaded from MinIO.
- The local Linux CPU path is the first production engine interpreter. Future
  model-specific tensor ABI growth can pass real weight/table/QKV payloads into
  the same generated oneDNN primitive-launch boundary without changing the
  stable FFI metadata contract.

### Validation

1. `jitml build --dry-run --substrate linux-cpu` renders a
   generated-source directory and `g++ ... -ldnnl` compile plan.
2. `jitml-unit` verifies `JitML.Engines.Loader.ensureKernelArtifact`
   recognizes an existing content-addressed artifact as a cache hit and does
   not recompile it.
3. `jitml-unit` verifies the Linux CPU local toolchain fingerprint includes
   the host artifact ABI used to separate host/container cache artifacts and
   the fixed `reduction-block=256` value; revalidated on 2026-05-22 in
   `jitml:local`.
4. `cabal test jitml-cross-backend` compiles, loads, and executes the
   generated Linux CPU identity kernel through a oneDNN reorder primitive;
   revalidated on 2026-05-24 with linkable `libdnnl`.
5. `cabal test jitml-cross-backend` compiles, loads, and executes the
   generated Linux CPU reduction kernel through a oneDNN reduction primitive;
   revalidated on 2026-05-24 with linkable `libdnnl`.
6. `cabal test jitml-cross-backend` compiles, loads, and executes every
   generated Linux CPU oneDNN family kernel through
   `runLinuxCpuFamilyKernel` and checks the exported
   `jitml_kernel_family_name` and `jitml_kernel_output_count` metadata;
   revalidated on 2026-05-24 with linkable `libdnnl`.
7. `docker compose run --rm jitml cabal test jitml-cross-backend` on
   2026-05-24 validates the local Linux CPU `HasEngine` boundary dispatching
   a generated oneDNN family kernel through the same artifact loader and FFI
   metadata checks.
8. `jitml-unit` validates deterministic `JitML.Engines.CpuFeatures` parser
   fixtures for Linux AVX-512, Linux AVX2, reference fallback, Apple Silicon,
   and Intel Darwin text. `jitml-integration -p CpuFeatures` validates the
   live host probe through typed subprocesses in `jitml:local`; revalidated on
   2026-05-22.
9. `jitml-unit` validates deterministic `JitML.Engines.OneDnnRuntime`
   parser/rendering fixtures for `pkg-config` version output, readable oneDNN
   headers, and dynamic-linker `libdnnl` visibility. `docker compose run --rm
   jitml cabal test jitml-integration --test-options='-p oneDNN'` on
   2026-05-24 validates the live typed subprocess probe for CPU features plus
   linkable oneDNN runtime availability.
10. `docker compose run --rm jitml cabal test jitml-daemon-lifecycle` on
    2026-05-22 validates that the daemon workload dispatcher can inject an
    engine-backed checkpoint inference runner between MinIO manifest loading
    and Pulsar `InferenceResult` publication.
11. `docker compose run --rm jitml cabal test jitml-cross-backend` on
    2026-05-24 validates representative oneDNN reduction, matmul, and
    convolution primitive launches, plus repeated same-host bit equality under
    the local Linux CPU `HasEngine` path.

### Remaining Work

- No sprint-owned Phase `7.3` Remaining Work remains. Linux CPU tensor-parameter
  payload growth for real model weights, embedding tables, and QKV tensors can
  extend the same oneDNN primitive-launch ABI from later checkpoint/inference
  work without reopening the Linux CPU engine/codegen closure.

## Sprint 7.4: Linux CUDA Engine and CUDA Codegen Driver ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/Cuda.hs`, `src/JitML/Engines/CudaLocal.hs`,
`src/JitML/Engines/CudaRuntime.hs`, `src/JitML/Engines/CublasBindings.hs`,
`src/JitML/Engines/CudnnBindings.hs`,
`src/JitML/Engines/HasEngine.hs`, `src/JitML/Engines/Rng.hs`,
`src/JitML/Engines/Tuning.hs`, `docker/Dockerfile`, `compose.yaml`,
`jitml.cabal` (`cuda` flag)
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Land the `linux-cuda` engine metadata, the generated CUDA C source
renderer, the guarded local runner that compiles/loads/launches that
source on a CUDA validation host, the typed Haskell cuBLAS/cuDNN
binding surface used by the engine for runtime initialization, and the
container-resident validation environment (CUDA 12.8 toolkit in
`jitml:local`, GPU mapping in `compose.yaml`). Adopts
`Capability Classes`, `Subprocesses as Typed Values`, and the
`Generated Artifacts → The generated-section registry` doctrine
sections from [../README.md](../README.md).

### Deliverables

- `engineForSubstrate LinuxCUDA` records backend `cuda` and artifact extension
  `.so`.
- `renderCudaSource` emits generated `kernel.cu` source under the runtime
  source bundle.
- `compileSubprocess` renders the `nvcc --shared --compiler-options=-fPIC
  --use_fast_math=false -arch=sm_70` command against the generated source
  directory.
- `renderCudaFamilySource` extends the local renderer to emit
  `reduction` (warp-shuffle with one deterministic partial per warp and no
  `atomicAdd`), `dense` (cuBLAS scaffold), `conv2d`/`conv3d` (cuDNN scaffold
  pinning `CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM`),
  `batchnorm` (cuDNN `BATCHNORM_SPATIAL_PERSISTENT`), and `mha`
  (deterministic cuBLAS GEMM chain) families. The deterministic cuDNN
  algorithm pin is recorded in `Engines.Tuning.cuDnnDeterministicAlgorithms`
  and embedded in the generated source payload (which participates in
  the cache key).
- Generated CUDA source exports a host-callable
  `jitml_kernel(float*, const float*, size_t)` FFI wrapper plus
  `jitml_kernel_family_name` and `jitml_kernel_output_count` metadata symbols.
  The wrapper allocates device input/output buffers, copies host input to the
  device, launches the deterministic device kernel, synchronizes, and copies
  the generated output buffer back to the host through the same ABI shape used
  by the Linux CPU local runner.
- `JitML.Engines.Rng` implements the host SplitMix64 stream used by the CUDA
  determinism contract, including stream derivation and `[0,1)` projection.
  Generated CUDA source records `host-splitmix64-no-curand` so the no-curand
  policy participates in the rendered source payload.
- `JitML.Engines.CudaRuntime` owns the host-side reduction finalization helper
  for CUDA FFI launchers: it mirrors the generated reduction geometry
  (`block=256`, `warp=32`, eight partials per block), computes the expected
  partial count, rejects mismatched partial vectors, and folds partials in
  canonical index order.
- `JitML.Engines.CudaRuntime.probeCudaRuntime` establishes the typed CUDA
  runtime/toolchain availability boundary for guarded production CUDA loading:
  it probes `nvcc --version`, `nvidia-smi -L`, and `ldconfig -p` through typed
  subprocesses, parses CUDA compiler version and visible GPU devices, reports
  `libcuda` / `libcublas` / `libcudnn` dynamic-linker visibility, and renders a
  stable probe summary.
- `JitML.Engines.CudaLocal` owns the guarded local CUDA loader path: it builds
  the family-aware CUDA runtime source/hash, requires a positive
  `probeCudaRuntime` before compiling, loads the compiled `.so` through
  `JitML.Engines.Loader.withKernelSymbol`, resolves `jitml_kernel`,
  `jitml_kernel_family_name`, and `jitml_kernel_output_count`, and returns
  `CudaKernelRun` diagnostics. `JitML.Engines.HasEngine.LocalCudaEngine` wraps
  that path and rejects loaded-family metadata mismatches.
- `jitml service` dispatches `linux-cuda` + `SelfInference` configs through the
  guarded CUDA checkpoint runner. In an unavailable runtime it reports a
  transient inference error before compile; on a CUDA host it uses the same
  cache/loader/metadata ABI as the local runner.
- `Engine.compileSubprocess` for `LinuxCUDA` now renders the typed
  `nvcc --shared --compiler-options=-fPIC --use_fast_math=false -arch=sm_70
  -DJITML_USE_CUBLAS=1 -DJITML_USE_CUDNN=1 -o <artifact> <generated-source-dir>/kernel.cu
  -lcudart -lcublas -lcudnn` command so the produced `.so` carries DT_NEEDED
  entries for the CUDA runtime, cuBLAS, and cuDNN. The dynamic linker
  therefore resolves the three libraries at `dlopen` time, which proves they
  are visible on the host before the kernel is launched.
- `CudaLocal.cudaToolchainFingerprint` records the additional
  `link=-lcudart,-lcublas,-lcudnn;cublas=v2-deterministic-gemm;
  cudnn=algo-implicit-precomp-gemm` segments so the produced artifact ABI
  participates in the JIT cache key.
- `src/JitML/Engines/CublasBindings.hs` and
  `src/JitML/Engines/CudnnBindings.hs` are the typed Haskell binding
  surface that wraps libcublas / libcudnn through `foreign import ccall`
  behind the `cuda` cabal flag. They expose `withCublasHandle`,
  `verifyCublasRuntime`, `withCudnnHandle`, and `verifyCudnnRuntime`
  plus the `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn`
  compile-time switches so non-CUDA hosts can branch on availability
  without importing the libraries. When the flag is off the bindings
  return a typed `CublasStatus (-2)` / `CudnnStatus (-2)` from every
  entrypoint. This is the "binding crate equivalent in Haskell"
  obligation called out in earlier remaining-work blocks.
- `jitml:local` (`docker/Dockerfile`) installs the CUDA 12.8 toolkit
  (`cuda-toolkit-12-8`) and matching cuDNN 9 dev headers
  (`libcudnn9-dev-cuda-12`), exposes `/usr/local/cuda/bin` /
  `/usr/local/cuda/lib64` on `PATH` / `LD_LIBRARY_PATH`, and runs
  `cabal build -fcuda exe:jitml exe:jitml-demo` so the installed
  `/usr/local/bin/jitml` binary carries the real cuBLAS/cuDNN bindings.
- `compose.yaml` keeps the default `jitml` service headless for code-quality,
  bootstrap, and non-GPU command runs, and exposes every host NVIDIA GPU to the
  `jitml-cuda` companion service via the modern `gpus: all` shorthand so live
  in-container CUDA validation (`docker compose run --rm jitml-cuda cabal test
  ...`) can launch real device kernels through `nvidia-container-toolkit`.
- The single-node live CUDA `RuntimeClass/nvidia` and pod-visible GPU
  validation closed on 2026-05-23 in Phase `4` Sprint `4.7` and Phase
  `5` Sprint `5.6` against a Linux CUDA host (NVIDIA GeForce RTX 5090,
  CUDA 12.8), so Phase `7` no longer waits on GPU scheduler discovery.

### Validation

1. `jitml build --dry-run --substrate linux-cuda` renders a
   generated-source directory and `nvcc` compile plan.
2. `jitml-unit` verifies the SplitMix64 host RNG vector, deterministic stream
   derivation, `[0,1)` projection, generated CUDA source metadata forbidding
   curand, deterministic reduction source that avoids `atomicAdd`, and exported
   CUDA host FFI wrapper/device-buffer copyback surface, and exported CUDA
   family/output-count metadata. It also verifies the host CUDA reduction
   partial-count geometry, negative input rejection, canonical partial
   accumulation, mismatch diagnostics, deterministic CUDA runtime-probe
   parsing/rendering fixtures for `nvcc`, `nvidia-smi`, and `ldconfig`, and
   the guarded CUDA local runner fail-closed path when the runtime probe is
   unavailable.
3. `docker compose run --rm jitml cabal test jitml-integration
   --test-options='-p CUDA'` validates the live typed subprocess
   probe logs CUDA toolchain, device, and dynamic-linker attempts even when the
   local validation environment lacks the runtime.
4. `cabal test jitml-unit` on 2026-05-24 validates the pure-Haskell
   binding invariants: `renderCublasStatus` / `renderCudnnStatus`
   format codes deterministically, `cublasBindingsCompiledIn` /
   `cudnnBindingsCompiledIn` reflect the cabal flag, and the
   `-f-cuda` binding stubs return typed `CublasStatus (-2)` /
   `CudnnStatus (-2)` from every entrypoint so non-CUDA hosts cannot
   silently no-op the cuBLAS/cuDNN path.
5. `cabal test jitml-cross-backend` on 2026-05-24 exercises the live
   CUDA tests behind the `probeCudaRuntime` guard. On a host without
   `nvcc` / `nvidia-smi` the four new cases log a typed skip and pass;
   on a CUDA host they execute the generated `kernel.cu` for
   `Identity` and `Reduction` through `runCudaFamilyKernel`, verify
   identity bit-equality and reduction sums, and exercise
   `verifyCublasRuntime` / `verifyCudnnRuntime` to confirm libcublas
   and libcudnn are linked and initialize.
6. `docker compose build jitml` + `docker compose run --rm jitml-cuda cabal
   test -fcuda jitml-cross-backend` on 2026-05-24 against a Linux
   CUDA validation host (NVIDIA GeForce RTX 3090, CUDA 12.8 driver,
   `cuda-toolkit-12-8` + `libcudnn9-dev-cuda-12` inside `jitml:local`)
   passes the live CUDA Sprint 7.4 cases under the `gpus: all`
   compose mapping: the generated `kernel.cu` compiles via real
   `nvcc`, links against `libcudart` / `libcublas` / `libcudnn`,
   `dlopen`s through the guarded Haskell FFI, the identity and
   reduction kernels execute (reduction sums `[4, -2, 1, 3] = 6.0`
   through the warp-shuffle device kernel + host
   `finalizeCudaReductionPartials`), repeated identity runs against
   `[0.0, 1.5, -2.25, 3.875, -4.125]` produce bit-identical output
   across three invocations, and `verifyCublasRuntime` /
   `verifyCudnnRuntime` create + destroy real cuBLAS / cuDNN handles
   reporting positive version numbers. The same run also closes the
   Sprint 7.6 live `linux-cuda benchmark candidate runner measures
   generated FFI output` case.
7. `docker compose run --rm jitml cabal test -fcuda jitml-unit` on
   2026-05-24 passes all 86 unit tests against the same `jitml:local`
   image, including the pure-Haskell binding invariants.

### Remaining Work

- No sprint-owned Phase `7.4` Remaining Work remains. The host
  SplitMix64 generator (`Engines.Rng`) and generated CUDA no-curand
  metadata are in place; when real stochastic CUDA kernels land, the
  production kernel ABI will need host-provided random-stream buffers
  wired into those kernels rather than using device-side RNG. That
  work is owned by the future production-kernel sprint that retires
  the cuBLAS / cuDNN identity scaffolds tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
  not by Sprint `7.4`.

## Sprint 7.5: Apple Silicon Engine, Metal Codegen, Hybrid Host↔Cluster RPC Scaffolding ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. Every live
Apple-Silicon obligation (retired Tart provisioning, Metal FFI loading,
host↔cluster Pulsar RPC, Apple Metal candidate runner, Apple Metal
production weight loading) migrated to Phase `14`. See
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md).
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/Metal.hs`, `src/JitML/Engines/MetalRuntime.hs`,
`src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Service/AppleInferenceRpc.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/daemon_architecture.md`

### Objective

Land the `apple-silicon` engine metadata, generated Swift/Metal package
renderer, host CommandLineTools `swift build` cache-miss path, runtime
`MTLDevice.makeLibrary(source:)` shader compilation, and Apple RPC topic names.
The deleted Tart VM executor and `jitml internal vm` command group are no
longer part of this surface.

### Deliverables

- `engineForSubstrate AppleSilicon` records backend `metal` and artifact
  extension `.dylib`.
- `renderMetalPackage` emits `Package.swift` and
  `Sources/JitMLMetal/JitMLMetal.swift`; the Swift source embeds the MSL string
  instead of writing a separate `Kernels.metal` resource.
- `compileSubprocess` renders host CommandLineTools `swift build
  --package-path <generated-source-dir> -c release`; the generated Swift
  launcher embeds the MSL source and compiles it at runtime with
  `MTLDevice.makeLibrary(source:)` and fast-math disabled.
- The route/topic documentation records `inference.command.apple-silicon` and
  `inference.event.apple-silicon` as the target host↔cluster RPC topics.
  `JitML.Proto.Inference` defines typed Apple-only command/event envelopes for
  those topics: `AppleInferenceCommand` carries
  `(call-id, kind, model-id, starting-snapshot, reply-topic, inputs)`, and
  `AppleInferenceEvent` carries `(call-id, kind, output-refs, error-code,
  message)`.
- `renderMetalFamilyPackage` extends the local Metal renderer to embed
  the per-substrate threadgroup-size knob into the generated Swift
  enum and emits family-aware Metal kernels (the `reduction` family
  uses `simd_sum` with single-stream launch ordering). The threadgroup
  axis is enumerated by `Engines.Tuning.appleSiliconKnobs`.
- Generated Swift source exports `jitml_kernel_family_name` and
  `jitml_kernel_output_count` metadata symbols so Metal FFI loading can inspect
  the loaded family and output shape through the same metadata contract used by
  the Linux CPU local runner. Reduction metadata reports the deterministic
  simdgroup partial-output count (`ceil(n / 32)`).
- `JitML.Engines.Loader.ensureKernelArtifact` runs the ordered Apple
  first-cache-miss plan on the host: validate the CommandLineTools Swift
  toolchain, run `swift build` against the generated package, publish
  `libJitMLMetal.dylib` into `./.build/jit/apple-silicon/<hash>.dylib`, and
  repoint the host-stable FFI symlink through
  `JitML.Cache.Symlink.repointSymlink`.
- `JitML.Engines.MetalRuntime.probeMetalRuntime` establishes the typed host
  Metal runtime availability boundary for the host FFI launcher: it probes
  `swift --version`, `xcrun -find metal`, `xcrun -find swiftc`, and
  `system_profiler SPDisplaysDataType` through typed subprocesses, parses Swift
  version/tool paths and Metal device visibility, and renders a stable probe
  summary.
- `JitML.Service.AppleInferenceRpc` owns the local Apple host↔cluster RPC
  planning boundary: it converts a demo-facing `InferenceRequest` plus starting
  snapshot into an `AppleInferenceCommand`, records the command/event/client
  reply topics, publishes the command through `HasPulsar.pulsarPublish`, and
  correlates completed/error `AppleInferenceEvent` envelopes back to the
  original call id.
- Metal FFI loading, MinIO tensor handoff, and live Pulsar RPC are live-closed
  by [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
  Sprints `14.2` and `14.4`; this sprint's current code-surface obligations
  (Swift package renderer, host build plan, Metal probe, RPC planning surface)
  are met.

### Validation

1. `docker compose run --rm jitml jitml build --dry-run --substrate
   apple-silicon` renders a generated Swift/Metal source directory and host
   `swift build` subprocess.
2. `docker compose run --rm jitml cabal test jitml-unit` on 2026-05-22
   validates that the generated Swift package exports
   `jitml_kernel_family_name` and `jitml_kernel_output_count`, that reduction
   output-count metadata matches the simdgroup partial-output shape, and that
   the Apple Silicon rendered-source cache-key snapshot changes when the Swift
   payload changes. The same test stanza validates the host build/cache
   publication boundary and the absence of the retired Tart prerequisite.
3. `docker compose build jitml` and
   `docker compose run --rm jitml jitml build --dry-run --substrate
   apple-silicon` on 2026-05-22 validate the installed container CLI renders
   the `apple_cache_miss` plan with host Swift-version validation, generated
   package build, content-addressed `.dylib` publish, and stable FFI symlink
   repoint steps.
4. `docker compose run --rm jitml cabal test jitml-daemon-lifecycle` on
   2026-05-22 validates the typed Apple command/event envelope render/parse
   round-trip, canonical Apple internal topic names, Apple RPC command
   planning, synthetic `HasPulsar` command publication, and completed/error
   event correlation by call id.
5. `jitml-unit` validates deterministic `JitML.Engines.MetalRuntime`
   parser/rendering fixtures for Swift version output, `xcrun -find` output,
   and Metal device visibility. `docker compose run --rm jitml cabal test
   jitml-integration --test-options='-p Metal'` validates the live typed
   subprocess probe logs Swift, `xcrun`, and `system_profiler` attempts even
   when the local validation environment is not macOS.
6. Live validation: on the first JIT cache miss for `apple-silicon`, the host
   CommandLineTools build atomically writes the resulting `.dylib` under
   `./.build/jit/apple-silicon/`, repoints the host-stable symlink, and the
   host daemon loads the kernel through FFI. The cluster orchestrator
   round-trips a typed `(call-id, kind, model-id, inputs)` envelope on
   `inference.command.apple-silicon` and gets a typed reply on
   `inference.event.apple-silicon`.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains for Sprint `7.5`.
  Apple Silicon live validation (first-cache-miss host build, Metal FFI
  loading, host↔cluster Pulsar RPC, full host-resident inference) is closed by
  [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
  Sprints `14.1`, `14.2`, `14.4`.

## Sprint 7.6: Hardware Auto-Tuning Within the Determinism Contract ✅

**Status**: Done
**Owned obligations after refactor**: code-surface only. The Metal
candidate runner live execution migrated to Phase `14` Sprint `14.3`.
The Linux CPU full-tensor benchmark payload migration and live
first-cache-miss measurement migrated to Phase `13` Sprint `13.15`.
The cross-substrate equality test migrated to Phase `15` Sprint `15.1`.
The code-only benchmark-runner wiring into `ensureKernelArtifact`'s
first-cache-miss path closed on 2026-05-24 through
`JitML.Engines.TuningBenchmark.{ensureKernelArtifactWithBenchmarkTuning,
ensureTuningSelection,candidateRunnerForSubstrate}`; the live runtime
validation remains owned by Phase `13` Sprint `13.15`.
**Implementation**: `src/JitML/Cache/Key.hs`,
`src/JitML/Engines/Tuning.hs`, `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/TuningStore.hs`,
`src/JitML/Engines/TuningCache.hs`, `src/JitML/App.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`

### Objective

Expose `TuningChoice` as a cache-key input and deterministic metadata
string, plus the deterministic measurement-ranking boundary for benchmark
results and the persisted selected-choice record; grow real hardware
benchmarking and per-substrate auto-tuning per `### Remaining Work` below.

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
- `benchmarkPlan` enumerates the deterministic-only candidate
  `TuningResult`s for a `KnobSpace`, and `renderBenchmarkPlan` renders their
  cache-key `TuningChoice` payloads in stable order.
- `BenchmarkMeasurement` records a candidate `TuningResult`, measured
  latency in microseconds, and output digest; `selectMeasuredTuning`
  rejects measurements outside the plan or with negative latency, then
  selects the lowest-latency candidate with stable plan-order tie-breaking.
- `JitML.Engines.TuningStore` persists the selected measured result as JSON
  under `jit/tuning/<substrate>/<base-hash>.json`, records the selected
  `TuningChoice`, latency, and output digest, and validates that reads match
  the requested substrate and base hash.
- `JitML.Engines.TuningBenchmark` collects candidate measurements in stable
  benchmark-plan order through a typed candidate runner, records latency and
  SHA-256 output digests for float/double outputs, and can persist the selected
  measurement by base hash through `TuningStore`.
- `JitML.Engines.TuningCache` derives the default tuning base hash, reads a
  persisted selected `TuningChoice` for that base hash when present, renders the
  tuned runtime source, and computes the final cache key from the selected
  choice. `jitml build --dry-run` prints the base hash, selected tuning choice,
  and whether the choice came from the default or persisted path.
- `JitML.Engines.TuningBenchmark.linuxCpuBenchmarkCandidateRunner` supplies the
  first concrete candidate runner: for `linux-cpu` candidates it renders the
  tuned oneDNN-style source, computes the candidate cache key, compiles/loads
  through `JitML.Engines.Local.runLinuxCpuKernel`, measures elapsed time, and
  records the SHA-256 digest of the FFI output.
- `JitML.Engines.TuningBenchmark.cudaBenchmarkCandidateRunner` provides the
  live CUDA candidate runner: it rejects wrong-substrate candidates, refuses
  to compile when `probeCudaRuntime` reports the runtime is unavailable
  (returning the typed unavailable summary), and otherwise renders the tuned
  CUDA runtime source, computes the candidate cache key, compiles/loads
  through `JitML.Engines.CudaLocal.runCudaKernel`, measures elapsed time, and
  records the SHA-256 digest of the FFI output. The signature matches
  `linuxCpuBenchmarkCandidateRunner`, including the `Env` parameter that
  carries the JIT cache root.
- In the historical Sprint `7.6` snapshot,
  `JitML.Engines.TuningBenchmark.metalBenchmarkCandidateRunner` was still a
  guarded preflight. Later Sprint `14.3`/`14.9` validation superseded that
  snapshot: live Metal candidate measurement now runs through the fixed bridge
  on Apple Silicon.

### Validation

1. `jitml-unit` verifies the rendered runtime-source payload participates
   in the cache key, the CUDA benchmark plan enumerates 72 deterministic
   candidates and includes the deterministic default `TuningChoice`, and
   measured selection chooses the fastest deterministic candidate with stable
   tie-breaking and empty-plan rejection.
2. `jitml-unit` verifies selected measured choices persist by base hash and
   round-trip through `JitML.Engines.TuningStore`, then
   `JitML.Engines.TuningCache` loads the persisted choice and derives a
   distinct final cache key from it.
3. `jitml-unit` verifies `JitML.Engines.TuningBenchmark` collects measurements
   in plan order, captures content-sensitive float output digests, measures
   non-negative elapsed time, and persists the lowest-latency selected
   measurement.
4. `cabal test jitml-cross-backend` revalidated on 2026-05-21 that the
   Linux CPU generated identity kernel produces bit-identical output
   across repeated FFI executions.
5. `docker compose run --rm jitml cabal test jitml-cross-backend` on
   2026-05-22 validates the Linux CPU benchmark candidate runner against the
   generated-kernel FFI path and verifies candidate-output digest capture.
6. `docker compose run --rm jitml cabal test jitml-unit --test-options='-p CUDA'`
   and `docker compose run --rm jitml cabal test jitml-unit --test-options='-p Metal'`
   on 2026-05-23 validate the guarded CUDA/Metal benchmark runner preflight
   boundaries, including wrong-substrate rejection and unavailable-runtime
   summaries. The CUDA preflight case for "available runtime" now routes
   into the live CUDA FFI candidate runner; the explicit
   not-implemented-yet assertion remains only on the Metal preflight path.
7. `docker compose run --rm jitml jitml build --dry-run --substrate linux-cpu`,
   `linux-cuda`, and `apple-silicon` revalidated on 2026-05-21 that the current
   runtime-source renderers still emit the expected oneDNN, CUDA, and
   Metal/Swift compile plans, including the selected tuning metadata
   (`tuning_base_hash`, `tuning_choice`, `tuning_selection`).
8. `docker compose build jitml`,
   `docker compose run --rm jitml jitml docs check`, and
   `docker compose run --rm jitml jitml check-code` passed on 2026-05-21,
   confirming the container-owned documentation and code-quality path.
9. Live validation (target): per-substrate knob spaces drive
   benchmark-based selection on real hardware (matmul tile sizes,
   reduction strategies, cuDNN deterministic algorithm IDs) and the
   chosen tuning influences the cache key without breaking determinism.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The
  `ensureKernelArtifactWithBenchmarkTuning` /
  `ensureKernelArtifactWithBenchmarkTuningWithRunner` /
  `ensureTuningSelection` wiring in
  `JitML.Engines.TuningBenchmark` selects the substrate-specific candidate
  runner (`linuxCpuBenchmarkCandidateRunner`,
  `cudaBenchmarkCandidateRunner`, `metalBenchmarkCandidateRunner`),
  drives the deterministic benchmark plan, persists the lowest-latency
  selection through `TuningStore`, and re-resolves the tuned
  `TuningCachePlan` before invoking `ensureKernelArtifact`. `jitml build`
  routes Linux CPU and Linux CUDA non-dry-run builds through the tuned ensure
  path; Phase `14` Sprint `14.3` closed the Apple Metal candidate-runner live
  path on top of the same headless Swift/Metal build surface. The 2026-05-24 in-container
  `cabal test jitml-unit -p "ensureTuningSelection"` validates the
  synthetic runner is invoked exactly once per candidate on first call
  and is not invoked again on the cached re-resolution. The live runtime
  validation that hardware-tuned choices get selected during real
  compilation is owned by Phase `13` Sprint `13.15` (Linux CPU) and Phase
  `14` Sprint `14.3` (Metal). The cross-substrate equality test (linux-cpu
  vs apple-silicon vs linux-cuda) and the full-tensor benchmark payload
  migration moved to Phase `15` Sprint `15.1` and Phase `13` Sprint
  `13.15` respectively.

## Sprint 7.7: Haskell-Owned Runtime JIT Source Generation ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/RuntimeSource.hs`,
`src/JitML/Codegen/{Cuda,OneDnn,Metal,SourceFile}.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the Haskell `jitml` binary the only source of JIT compiler inputs and
project-owned native adapter source. Static checked-in JIT build scripts,
kernel source files, and native adapter shims are forbidden: no checked-in CUDA
`.cu`, no checked-in oneDNN C/C++ source, no checked-in C/C++ adapter source,
and no checked-in Metal / Swift package source participates in a JIT build or
runtime adapter path.

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
- Cache-key fixtures derive their `RuntimeSourcePayload` from
  `renderRuntimeSource`; the old `runtime-source:phase-2-placeholder` marker is
  gone from the worktree.
- Static source/script scaffolds are removed, as tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#completed).
- `jitml lint files` rejects future checked-in JIT build scripts, checked-in
  substrate source extensions, and native adapter shims. It additionally
  rejects any new file under `test/golden/` per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).

### Validation

1. `jitml build --dry-run --substrate linux-cuda` shows a generated-source
   directory under `./.build/jit-src/linux-cuda/<hash>`.
2. `jitml build --dry-run --substrate linux-cpu` shows oneDNN C++ generated
   under `./.build/jit-src/linux-cpu/<hash>/`.
3. `jitml build --dry-run --substrate apple-silicon` shows Swift / Metal
   generated under `./.build/jit-src/apple-silicon/<hash>/` before the host
   CommandLineTools `swift build --package-path <generated-source-dir> -c release`
   command; the former Tart executor path is retired.
4. Removing documentation-only substrate folders does not change any JIT build
   plan or cache key.
5. `jitml-unit` snapshot tests prove `renderRuntimeSource` is deterministic and
   that renderer changes alter the generated-source hash.
6. `cabal test jitml-unit --test-options='-p cacheKey'` on 2026-05-21 passes
   with the cache-key snapshot backed by rendered runtime source instead of the
   retired placeholder fixture.
7. `cabal test jitml-cross-backend` on 2026-05-21 passes the local
   generated-source FFI path: deterministic engine flags, manifest-read
   independence, Linux CPU identity compile/load/run, reduction-family
   compile/load/run, all-family scaffold compile/load/run, family/output-count
   symbol validation, repeated-run bit equality, and local Linux CPU
   `HasEngine` dispatch.

### Closure Checklist

- [x] Add the Haskell `RuntimeSource` renderers for CUDA, oneDNN C++, and
  Metal / Swift package generation.
- [x] Route every JIT compile plan through generated source under
  `./.build/jit-src/<substrate>/<hash>/`.
- [x] Remove checked-in JIT build scripts, checked-in `.cu`, checked-in `.cc`
  / `.cpp`, checked-in native adapter shims, and checked-in Metal / Swift
  package inputs from the build path.
- [x] Add lint coverage that rejects future static JIT source/build artefacts.
- [x] Move the static-codegen pending-removal ledger row to `Completed` once
  the generated-source path validates.
- [x] Move the default runtime-source placeholder ledger row to `Completed`
  once cache-key fixtures consume rendered `RuntimeSourcePayload`s.

## Sprint 7.8: Headless Apple Metal JIT — Runtime Compilation + Host Swift Build ✅

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

## Sprint 7.9: Compose GPU Service Split ✅

**Status**: Done (reopened and re-closed 2026-06-04).

### Intent

Keep the container-only code-quality path runnable on non-NVIDIA hosts while
preserving live in-container CUDA validation. The default `jitml` service is the
headless host-networked command wrapper; `jitml-cuda` is the GPU-enabled
companion for direct CUDA tests.

### Implementation

- `compose.yaml` now factors the shared `jitml:local` image/build/mount/network
  settings into one service template.
- `jitml` uses the shared template with no GPU request, so
  `docker compose run --rm jitml jitml check-code` reaches the CLI on CPU-only
  hosts.
- `jitml-cuda` uses the same image and mounts plus `gpus: all`, preserving the
  live CUDA validation path for commands that need device exposure in the outer
  container.

### Validation

1. `docker compose build jitml` passes after the no-`allow-newer` dependency
   replacement and runs `jitml check-code` during image construction.
2. A fresh `docker compose run --rm jitml jitml check-code` rebuilds/exports
   `jitml:local`, builds the PureScript bundle, and completes the final
   headless command with `check-code: ok` without requesting a GPU device
   driver.

### Remaining Work

- None.

## Doctrine Sections Cited

- [../README.md → Subprocesses as Typed Values](../README.md#doctrine-scope) (Sprints 7.3, 7.4, 7.5)
- [../README.md → Long-Running Daemons in the Same Binary](../README.md#doctrine-scope) (Sprint 7.5 — target host/cluster split represented by local config/topic surfaces)
- [../README.md → At-Least-Once Event Processing](../README.md#doctrine-scope) (Sprint 7.5 — host↔cluster RPC topics documented; live consumer owned by [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md) Sprint `14.4`)
- [../README.md → Toolchain pinning](../README.md#toolchain-pinning) (Sprints 7.3, 7.4, 7.5)

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/jit_codegen_architecture.md` — current local
  `KernelSpec` cache-key payload, cache key derivation, Haskell runtime source
  renderers, per-substrate compile plans, Linux CPU libdnnl-linked oneDNN
  primitive compile/load/run paths with exported family/output-count symbol
  validation, local Linux CPU artifact-ABI fingerprinting, and the local Linux
  CPU `HasEngine` interpreter; Apple fixed-bridge runtime source artifact,
  host↔cluster RPC, and real auto-tuning surface.
- `documents/engineering/determinism_contract.md` — populate with the per-
  substrate floating-point semantics (Metal single-stream and fast-math-disabled
  runtime source compilation through the bridge, oneDNN blocked reduction, CUDA
  warp-shuffle + `--use_fast_math=false` + cuDNN explicit algorithm-id pinning),
  and the engine envelope shape.
- `documents/engineering/daemon_architecture.md` — link to the
  `InferenceProxy` Apple-only surface.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md → JIT Codegen Components` and `Substrates` rows
  remain aligned with `src/JitML/Engines/Engine.hs`, the Haskell runtime source
  generator target, and the static-codegen cleanup ledger.

## Sprint 7.10: Route the Apple `swift build` through the Tart VM [✅ Done]

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
  14.2), the weighted Dense2D GEMM is **bit-deterministic across three runs**
  (Sprint 14.5), and the live Metal benchmark candidate runner produces a
  measurement (Sprint 14.3).
- `jitml-unit` 194 / 194 host-native (incl. the Metal-probe regression:
  device-visible + no host toolchain ⇒ available); container `jitml check-code`
  green.

## Sprint 7.11: Fixed host Metal bridge and source-metadata Apple cache ✅

**Status**: Done
**Implementation**: `src/JitML/Engines/{MetalBridge,MetalLocal,MetalRuntime,Engine,Loader}.hs`, `src/JitML/Codegen/{Metal,RuntimeSource}.hs`
**Docs to update**: `documents/engineering/jit_codegen_architecture.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Replace per-kernel generated Swift packages and Tart/SwiftPM cache misses with a
fixed host Metal bridge that runtime-compiles generated MSL source through the
OS Metal framework. Adopts `Built-artifact and JIT-cache discipline`,
`Subprocesses as typed values`, and `Toolchain pinning` from
[../README.md](../README.md).

### Deliverables

- Add `JitML.Engines.MetalBridge` exposing a stable Haskell-facing ABI over the
  fixed bridge: probe, source compile, pipeline creation, buffer binding,
  dispatch, wait, and structured error capture.
- Replace `GeneratedMetalPackage` / Swift package rendering with a canonical MSL
  source renderer and launch-metadata encoder whose persistent cache artifact is
  `./.build/jit/apple-silicon/<hash>.metal.json`.
- Remove the Apple `compileSubprocess` / `tart exec swift build` branch from the
  core cache-miss path. Filling an Apple cache miss writes source metadata; the
  bridge compiles the MSL in-process on first use.
- Replace generated-dylib `dlopen` in `MetalLocal` with bridge calls and an
  in-process pipeline cache keyed by `(device-registry-id, source-sha256,
  function-name, launch-policy)`.
- Key Apple toolchain fingerprints on bridge ABI, OS/Metal runtime policy,
  rendered MSL, launch metadata, determinism options, and tuning choice.

### Validation

- A headless bridge probe compiles and dispatches a tiny MSL kernel with
  `xcrun -find metal` failing and no usable login keychain.
- `jitml test jitml-backends --apple-silicon` fills a fresh cache miss as
  `<hash>.metal.json`, runs identity/weighted kernels through the fixed bridge,
  and proves same-substrate bit-equality.
- `tart`, `swift build`, and the offline `metal` compiler are not invoked by
  `jitml service`, `jitml train`, `jitml inference run`, or the Apple backend
  tests.
- Container `jitml check-code`, `jitml docs check`, and relevant host-native
  `jitml-unit` / backend tests pass.

### Validation State (2026-06-12)

- `cabal run exe:jitml -- internal install-metal-bridge` built
  `.build/host/apple-silicon/libJitMLMetalBridge.dylib` and the bridge probe
  returned `ok`.
- `cabal test jitml-unit` passed 195 / 195, including the Apple source-metadata
  cache-fill regression and Metal metadata renderer checks.
- `cabal test jitml-daemon-lifecycle` passed 33 / 33, including the fixed
  Apple Metal acquire status.
- Focused backend checks passed through the fixed bridge:
  `apple-silicon kernel output is bit-equal`, `apple-silicon weighted Dense2D`,
  and the Metal MLP forward/backward/batched/determinism cases.
- `jitml test jitml-backends --apple-silicon` passed all 17 / 17 apple-silicon
  cases through the fixed bridge, including the benchmark candidate runner,
  tuning cache reuse, MLP, RL trainer, and AlphaZero PolicyValueNet cases.
- `docker compose build jitml` passed after the fixed-bridge source and docs
  changes; the image-local gate reported `check-code: ok` and the PureScript
  bundle rebuilt successfully.
- `docker compose run --rm jitml jitml docs check`,
  `docker compose run --rm jitml jitml check-code`, and `git diff --check`
  passed after the final validation sweep.

### Remaining Work

- None.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)

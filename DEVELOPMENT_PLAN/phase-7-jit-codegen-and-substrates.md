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
> numerical core, the Apple Silicon hybrid pattern (host daemon + lazy tart
> spin-up + cluster RPC envelope), and the hardware auto-tuning surface that
> preserves the per-substrate determinism contract.

## Phase Status

🔄 **Active**. After the 2026-05-24 refactor, this phase carries only
the code-surface portion of its owned obligations: the per-substrate
source renderers, content-addressed cache key + storage, the typed
Subprocess plans for `metal` / `nvcc` / `g++`, the typed runtime
probes, and the typed candidate-runner scaffold. The live Apple Metal
execution path migrated to
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
through `gpus: all`, the CUDA compile plan now links the produced `.so`
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
and fail closed until the live FFI candidate execution paths exist.
**Unmet today**:
Sprint `7.5` owes Metal FFI loading + live host↔cluster RPC
(`JitML.Tart.Build` now renders and executes the ordered Apple cache-miss
plan from VM ensure/postcondition validation through Swift build, cache
publication, and stable symlink repointing; `JitML.Tart.Lifecycle` probes
`tart list --source local --format json`, starts stopped VMs with
`tart run --no-graphics`, and polls `tart exec <vm> true`; the
synthetic executor tests still validate ordered success and failure
short-circuiting; generated Swift metadata symbols are present;
`JitML.Engines.MetalRuntime` probes host Swift / `xcrun` compiler tools and
Metal device visibility; local Tart `2.31.0` is present, but no `jitml-build`
VM exists and the live Metal FFI / RPC runtime is still absent);
Sprint `7.6` owes the live Metal candidate measurement implementation
behind the Metal preflight runner boundary, first-cache-miss benchmark
invocation, and cross-substrate equality once the Apple Silicon runtime
exists; the live CUDA candidate measurement closed on 2026-05-24 alongside
Sprint `7.4`. Detailed remaining work lives in each sprint's
`### Remaining Work` block below.

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
local `dlopen` symbol boundary, plus
Tart command/state helpers and the Apple cache-miss build plan/executor
boundary. The local build
plan surface renders CUDA / oneDNN C++ / Metal-Swift compiler inputs under
`./.build/jit-src/<substrate>/<hash>/` and routes the compile command through
typed `Subprocess` values. `src/JitML/Engines/Local.hs` provides the first
same-host execution loop for `linux-cpu`: generated oneDNN source
materialization, shared-object compilation, `dlopen`, symbol lookup, and
deterministic execution for identity/reorder, reduction, dense/matmul,
2D/3D convolution, batchnorm, layernorm, attention/matmul, and embedding/reorder
families, and records the family name reported by the loaded artifact.
`JitML.Engines.HasEngine` exposes that Linux CPU generated-family path through
a typed `HasEngine` capability and local interpreter.

The remaining execution gaps are now Apple Metal FFI/RPC, the live Metal
auto-tuning candidate runner, and first-cache-miss benchmark invocation on
the production cache-miss path. The Linux CUDA FFI / cuBLAS / cuDNN gap
closed in Sprint `7.4` on 2026-05-24.

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
- `compose.yaml` exposes every host NVIDIA GPU to the `jitml`
  service via the modern `gpus: all` shorthand so live in-container
  validation (`docker compose run --rm jitml cabal test ...`) can launch
  real device kernels through `nvidia-container-toolkit`.
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
6. `docker compose build jitml` + `docker compose run --rm jitml cabal
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
Apple-Silicon obligation (Tart VM provisioning, Metal FFI loading,
host↔cluster Pulsar RPC, Apple Metal candidate runner, Apple Metal
production weight loading) migrated to Phase `14`. See
[phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md).
**Implementation**: `src/JitML/Engines/Engine.hs`,
`src/JitML/Codegen/Metal.hs`, `src/JitML/Engines/MetalRuntime.hs`,
`src/JitML/Service/AppleInferenceRpc.hs`,
`src/JitML/Tart/Build.hs`, `src/JitML/Tart/Lifecycle.hs`,
`src/JitML/Tart/Exec.hs`
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
- `compileSubprocess` renders `tart exec jitml-build swift build
  --package-path <generated-source-dir> -c release`.
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
  `jitml_kernel_output_count` metadata symbols so future Metal FFI loading can
  inspect the loaded family and output shape through the same metadata contract
  used by the Linux CPU local runner. Reduction metadata reports the
  deterministic simdgroup partial-output count (`ceil(n / 32)`).
- `JitML.Tart.Build.tartCacheMissBuildPlan` renders the ordered Apple
  first-cache-miss plan: ensure the `jitml-build` VM, validate the VM Swift
  toolchain with `tart exec jitml-build swift --version`, run `swift build`
  against the generated package, copy the produced
  `libJitMLMetal.dylib` into `./.build/jit/apple-silicon/<hash>.dylib`, and
  repoint the host-stable FFI symlink through
  `JitML.Cache.Symlink.repointSymlink`. The companion
  `executeTartCacheMissBuildPlan` API supplies the concrete IO executor used
  by `JitML.Engines.Loader.ensureKernelArtifact` for Apple cache misses:
  `JitML.Tart.Lifecycle.ensureVmUpLive` inspects `tart list --source local
  --format json`, starts a stopped VM with `tart run --no-graphics`, polls
  `tart exec <vm> true` for readiness, then executes the Swift validation /
  build / cache-publish subprocesses and repoints the stable symlink. The
  lower-level `executeTartCacheMissBuildPlanWith` API remains available for
  synthetic unit tests and alternate executors.
- `JitML.Tart.Lifecycle` also owns the user-facing live VM lifecycle helpers:
  `bootstrapTartVmLive` clones the default Tart source image
  (`ghcr.io/cirruslabs/macos-sequoia-xcode:16`) into `jitml-build` when
  missing, `queryTartVmStatus` reports missing/stopped/running from
  `tart list --source local --format json`, and `stopTartVmLive` stops a
  running VM through `tart stop`. `jitml internal vm bootstrap|up|down|status`
  now dispatch to those helpers and report the resulting status instead of
  writing the old repo-local VM state marker.
- `JitML.Engines.MetalRuntime.probeMetalRuntime` establishes the typed host
  Metal runtime availability boundary for the future host FFI launcher: it
  probes `swift --version`, `xcrun -find metal`, `xcrun -find swiftc`, and
  `system_profiler SPDisplaysDataType` through typed subprocesses, parses Swift
  version/tool paths and Metal device visibility, and renders a stable probe
  summary.
- `JitML.Service.AppleInferenceRpc` owns the local Apple host↔cluster RPC
  planning boundary: it converts a demo-facing `InferenceRequest` plus starting
  snapshot into an `AppleInferenceCommand`, records the command/event/client
  reply topics, publishes the command through `HasPulsar.pulsarPublish`, and
  correlates completed/error `AppleInferenceEvent` envelopes back to the
  original call id.
- Metal FFI loading, MinIO tensor handoff, and live Pulsar RPC are owned
  by [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
  Sprints `14.2` and `14.4` after the refactor; this sprint's code-surface
  obligations (Swift package renderer, Tart command plan, lifecycle helpers,
  Metal probe, RPC planning surface) are met.

### Validation

1. `docker compose run --rm jitml jitml build --dry-run --substrate
   apple-silicon` on 2026-05-22 renders a generated Swift/Metal source
   directory and Tart `swift build` subprocess.
2. `docker compose run --rm jitml cabal test jitml-unit` on 2026-05-22
   validates that the generated Swift package exports
   `jitml_kernel_family_name` and `jitml_kernel_output_count`, that reduction
   output-count metadata matches the simdgroup partial-output shape, and that
   the Apple Silicon rendered-source cache-key golden changes when the Swift
   payload changes. The same test stanza validates the typed
   `JitML.Tart.Build` executor boundary by checking ordered host/command
   execution and failure short-circuiting at the copy step.
   `docker compose run --rm jitml cabal test jitml-unit
   --test-options='-p Tart'` on 2026-05-22 also validates the
   `JitML.Tart.Lifecycle` parser for missing/stopped/running VM states and
   the rendered live `tart clone`, `tart list`, `tart run --no-graphics`, and
   `tart stop` command boundaries plus status rendering.
3. `docker compose build jitml` and
   `docker compose run --rm jitml jitml build --dry-run --substrate
   apple-silicon` on 2026-05-22 validate the installed container CLI renders
   the `apple_cache_miss` plan with VM Swift-version validation, generated
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
6. Live validation (target): on the first JIT cache miss for `apple-silicon`,
   the typed lifecycle spins up the `jitml-build` Tart VM, runs
   `swift build` inside it, atomically writes the resulting `.dylib` under
   `./.build/jit/apple-silicon/`, repoints the host-stable symlink, and
   the host daemon loads the kernel through the FFI. The cluster orchestrator
   round-trips a typed `(call-id, kind, model-id, inputs)` envelope on
   `inference.command.apple-silicon` and gets a typed reply on
   `inference.event.apple-silicon`.

### Remaining Work

- No sprint-owned code-surface Remaining Work remains for Sprint `7.5`.
  Apple Silicon live validation (Tart VM provisioning + first-cache-miss
  build, Metal FFI loading, host↔cluster Pulsar RPC, full host-resident
  inference) is owned by
  [phase-14-apple-silicon-closure.md](phase-14-apple-silicon-closure.md)
  Sprints `14.1`, `14.2`, `14.4`.

## Sprint 7.6: Hardware Auto-Tuning Within the Determinism Contract 🔄

**Status**: Active
**Owned obligations after refactor**: code-surface only. The Metal
candidate runner live execution migrated to Phase `14` Sprint `14.3`.
The Linux CPU full-tensor benchmark payload migration and live
first-cache-miss measurement migrated to Phase `13` Sprint `13.15`.
The cross-substrate equality test migrated to Phase `15` Sprint `15.1`.
This sprint retains the code-only obligation of wiring the benchmark
runner into `ensureKernelArtifact`'s first-cache-miss path; the live
runtime validation of that wiring is owned by Phase `13` Sprint `13.15`.
**Implementation**: `src/JitML/Cache/Key.hs`,
`src/JitML/Engines/Tuning.hs`, `src/JitML/Engines/TuningBenchmark.hs`,
`src/JitML/Engines/TuningStore.hs`,
`src/JitML/Engines/TuningCache.hs`
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
- `JitML.Engines.TuningBenchmark.metalBenchmarkCandidateRunner` is still a
  guarded preflight: it rejects wrong-substrate candidates, summarizes the
  Metal runtime probe, and fails closed with an explicit
  `metal FFI candidate execution is not implemented yet` error once the
  Metal runtime is available. Live Metal candidate measurement remains open
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

- Wire `Engines.TuningBenchmark.collectAndPersistBenchmarkSelection` into
  `JitML.Engines.Loader.ensureKernelArtifact`'s first-cache-miss path so
  the typed runner is invoked during real compilation. Pure Haskell IO
  wiring: select the candidate runner per substrate
  (`linuxCpuBenchmarkCandidateRunner`, `cudaBenchmarkCandidateRunner`,
  `metalBenchmarkCandidateRunner`), thread it through the cache-miss
  branch, and persist the selection via `TuningStore`. The live runtime
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
- Cache-key fixtures derive their `RuntimeSourcePayload` from
  `renderRuntimeSource`; the old `runtime-source:phase-2-placeholder` marker is
  gone from the worktree.
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
   generated under `./.build/jit-src/apple-silicon/<hash>/` before the
   `tart exec jitml-build swift build` command; revalidated on 2026-05-21
   against local Tart `2.31.0`.
4. Removing documentation-only substrate folders does not change any JIT build
   plan or cache key.
5. `jitml-unit` golden tests prove `renderRuntimeSource` is deterministic and
   that renderer changes alter the generated-source hash.
6. `cabal test jitml-unit --test-options='-p cacheKey'` on 2026-05-21 passes
   with the cache-key golden backed by rendered runtime source instead of the
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
  / `.cpp`, and checked-in Metal / Swift package inputs from the build path.
- [x] Add lint coverage that rejects future static JIT source/build artefacts.
- [x] Move the static-codegen pending-removal ledger row to `Completed` once
  the generated-source path validates.
- [x] Move the default runtime-source placeholder ledger row to `Completed`
  once cache-key fixtures consume rendered `RuntimeSourcePayload`s.

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
  CPU `HasEngine` interpreter; target non-CPU FFI loaders, Apple hybrid
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
- [../README.md](../README.md)

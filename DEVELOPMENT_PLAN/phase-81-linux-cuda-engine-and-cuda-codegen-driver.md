# Phase 81: Linux CUDA Engine and CUDA Codegen Driver

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Linux CUDA Engine and CUDA Codegen Driver. Single-session phase migrated from legacy Sprint 7.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 81.1: Linux CUDA Engine and CUDA Codegen Driver [✅ Done]

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
  a CUDA-enabled build of `exe:jitml` so the installed `/usr/local/bin/jitml`
  binary carries the real cuBLAS/cuDNN bindings.
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

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

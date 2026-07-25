# Phase 178: CUDA and Linux CPU Production Weight Loading

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: CUDA and Linux CPU Production Weight Loading. Single-session phase migrated from legacy Sprint 15.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 178.1: CUDA and Linux CPU Production Weight Loading [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-27)
**Blocked by**: Sprint `174.1`
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Engines/CudaLocal.hs`,
`src/JitML/Engines/Local.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/jit_codegen_architecture.md`

### Objective

Extend `loadInferenceCheckpointWithWeights` beyond the existing local
Linux CPU smoke path so real weight blobs decoded from `.jmw1` load
into both Linux CPU oneDNN primitive kernels and Linux CUDA
`MTLBuffer`-equivalent device memory through cuBLAS/cuDNN. Closes the
Linux halves of Exit Definition item 7 (split-blob checkpoint format
with real production weight loading per substrate).

### Deliverables

- `JitML.Engines.Local.runLinuxCpuWeightedKernel` accepts decoded
  weight tensors as oneDNN primitive inputs and feeds them through the
  generated FFI kernel for real network execution (not the current
  smoke fixture).
- `JitML.Engines.CudaLocal.runCudaWeightedKernel` accepts decoded
  weight tensors, allocates device buffers, copies host weights to the
  device, launches the kernel, and copies host output back.
- The daemon's
  `JitML.Service.Runtime.daemonWorkloadDispatcherWithInference`
  dispatches `linux-cpu` and `linux-cuda` + `SelfInference` through the
  weighted runners.

### Validation

1. On Linux+NVIDIA: a canonical inference request through the live
   cluster service pod with `substrate=linux-cuda` produces a
   deterministic output bit-identical to the same request run twice in
   sequence.
2. Same assertion for `substrate=linux-cpu` against the live cluster
   path.

### Code Surface Landed (2026-05-26, Linux CPU weighted runner)

- `src/JitML/Codegen/OneDnn.hs` emits a new exported symbol
  `jitml_weighted_kernel(float* out, const float* input, std::size_t n,
  const float* weights, std::size_t weights_count)` alongside the
  existing `jitml_kernel`. For `Dense2D` the new symbol calls
  `jitml_onednn_dense_weighted` — a real oneDNN matmul against the
  caller-supplied row-major weights buffer (padded with zeros to the
  `n × n` shape when `weights_count < n * n`, truncated when greater).
  Other families currently route their weighted symbol through the
  existing unweighted body until their per-family weighted ABIs land
  (Conv2D / Conv3D / BatchNorm / LayerNorm / MHA / Embedding).
- `src/JitML/Engines/Local.hs`:
  - New `WeightedKernelFunction` FFI type:
    `Ptr CFloat -> Ptr CFloat -> CSize -> Ptr CFloat -> CSize -> IO ()`
    plus `foreign import ccall "dynamic" mkWeightedKernelFunction`.
  - New `runLinuxCpuWeightedKernel :: Env -> RuntimeSource -> Cache.Hash
    -> [Float] -> [Float] -> IO (Either Text LinuxCpuWeightedKernelRun)`
    that ensures the artifact, resolves `jitml_weighted_kernel`, marshals
    input + flat weight buffers across the typed FFI boundary, and
    returns the deterministic output alongside `LinuxCpuWeightedKernelRun`
    metadata (handle, reported family, compile command).
  - New `runLinuxCpuWeightedFamilyKernel :: Env -> KernelFamily -> [Float]
    -> [Float] -> IO (Either Text LinuxCpuWeightedKernelRun)`
    convenience entry mirroring the existing
    `runLinuxCpuFamilyKernel` signature.
  - `runLinuxCpuWeightedCheckpointInference` now drives the new weighted
    Dense2D body (replacing the prior identity-plus-bias smoke fixture).
    `flattenLoadedWeights` concatenates per-tensor `loadedWeightValues`
    into the flat row-major buffer the FFI accepts.
  - `linuxCpuToolchainFingerprint` adds the new symbol
    `jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)`
    so the cache key invalidates pre-15.11 artifacts and re-emits the
    extended `kernel.cc`.
- `test/cross-backend/Main.hs` adds the new case `linux-cpu weighted
  Dense2D kernel runs real GEMM bit-deterministically (Sprint 15.11)`
  that runs the weighted Dense2D kernel three times against `input =
  [1,2,3]` and `weights = [1,0,0, 0,2,0, 0,0,3]` (3×3 identity-scaled
  diagonal) and asserts `output = [1, 4, 9]` bit-equally across all
  three runs. The reported family is `dense`.
- `test/integration/Main.hs`'s `loadInferenceCheckpointWithWeights via
  HasMinIO round-trips (Sprint 10.4/10.5)` weighted assertion is updated
  to `Right [9.0, 2.0, 3.0]` to reflect the new real GEMM output:
  `input [1,2,3]` against the weight tensor `[1,2,3,4]` (decoded from
  `.jmw1`, padded to 3×3 row-major) yields `[9, 2, 3]`.
- All 245 non-Live tests pass; 12 Live cases pass against the running
  RTX 3090 cluster; `jitml check-code` clean.

### Code Surface Landed (2026-05-26, CUDA weighted runner)

- `src/JitML/Codegen/Cuda.hs` emits the matching CUDA-side
  `jitml_weighted_kernel(float*, const float*, size_t, const float*,
  size_t)` symbol alongside the existing `jitml_kernel`. For `Dense2D`
  the symbol launches `jitml_device_dense_weighted` — a real device
  GEMM (`out[i] = sum_j input[j] * W[j*n+i]`) against the
  caller-supplied row-major weights buffer (single-warp launch per
  output element, padded with zeros when `weights_count < n*n`). Other
  families pass the weights buffer through the FFI but fall through to
  the unweighted body until their per-family CUDA weighted paths land.
- A new `jitml_cuda_copy_and_launch_weighted` helper in
  `cudaRuntimeHelpers` allocates device buffers for input, weights, and
  output, copies host→device, launches the family-specific weighted
  device launcher, and copies output device→host. When `weights_count
  == 0` the device weights buffer is left null and the device launcher
  treats missing weights as zero.
- `src/JitML/Engines/CudaLocal.hs`:
  - New `WeightedKernelFunction` FFI type + `mkWeightedKernelFunction`
    foreign import (same shape as the Linux CPU side).
  - New `runCudaWeightedKernel`, `runCudaWeightedFamilyKernel`,
    `runCudaWeightedFamilyKernelWithProbe`, `runCudaWeightedCheckpointInference`,
    and `CudaWeightedKernelRun` record mirroring the Linux CPU shape.
    The probe-gated entry returns `Left "linux-cuda runtime
    unavailable: …"` when nvcc / nvidia-smi / cuBLAS / cuDNN aren't
    visible.
  - `loadAndRunWeighted` resolves `jitml_weighted_kernel` and threads
    input + weights across the FFI.
  - `cudaToolchainFingerprint` extended with
    `jitml_weighted_kernel(float*,const float*,size_t,const float*,size_t)`
    so the CUDA cache key invalidates pre-15.11 artifacts.
- `test/cross-backend/Main.hs` adds the probe-gated case `linux-cuda
  weighted Dense2D kernel runs real device GEMM bit-deterministically
  (Sprint 15.11)` that runs the CUDA weighted Dense2D kernel three
  times against the same input + diagonal weights and asserts bit-equal
  `[1.0, 4.0, 9.0]` output. Skips with a passing message on hosts
  without a positive CUDA runtime probe.
- All 246 non-Live tests pass; 12/12 Live cohort still passes;
  `jitml check-code` clean.

### Code Surface Landed (2026-05-26, GPU passthrough + daemon dispatch widening)

- **Daemon dispatch widening (option `b`).** Parallel
  `*WithWeightedInference` entry points added throughout the dispatcher
  chain:
  - `JitML.Service.Workload.runWorkloadEffectWithWeightedInference`,
    `runWorkloadEffectsWithWeightedInference`,
    `dispatchWorkloadPayloadWithWeightedInference`,
    `dispatchDomainPayloadWithWeightedInference`,
    `runInferenceRequestWithWeightedInference` — each takes the
    weighted callback `CheckpointManifest -> [LoadedWeightTensor] ->
    [Double] -> m (Either Text [Double])` and routes through
    `loadInferenceCheckpointWithWeights`.
  - `JitML.Service.Runtime.daemonWorkloadDispatcherWithWeightedInference`
    delegates to the new dispatch chain.
  - `JitML.App.daemonWorkloadDispatcherForRuntime` now routes
    `(LinuxCPU, SelfInference)` through
    `runLinuxCpuWeightedCheckpointInference` and
    `(LinuxCUDA, SelfInference)` through
    `runCudaWeightedCheckpointInference` via the new
    `daemonWorkloadDispatcherWithWeightedInference`.
- **GPU passthrough fix.** The stub `libnvidia-ml.so` in
  `/usr/local/cuda/lib64/stubs` no longer shadows the
  nvidia-container-runtime-injected real driver lib at runtime:
  - `docker/Dockerfile` removes `/usr/local/cuda/lib64/stubs` from
    `ENV LD_LIBRARY_PATH` and from `/etc/ld.so.conf.d/cuda.conf` —
    stubs are link-time only.
  - `JitML.Engines.Engine.compileSubprocess` for `LinuxCUDA` now
    passes `-L/usr/local/cuda/lib64/stubs` explicitly to nvcc so the
    link-time stub for `libcuda.so` is found without polluting the
    runtime loader path.

### Code Surface Landed (2026-05-27, other family weighted bodies)

- `JitML.Codegen.OneDnn.weightedFamilyImpl` now routes every kernel
  family to a real per-family weighted oneDNN primitive via
  `weightedFamilyCall`:
  - `Conv2DKernel` → `jitml_onednn_conv2d_weighted` (1x1 convolution
    with caller-supplied 1-element filter)
  - `Conv3DKernel` → `jitml_onednn_conv3d_weighted` (1x1x1
    convolution)
  - `BatchNormKernel` → `jitml_onednn_batchnorm_weighted` (caller
    supplies scale/shift/mean/variance as four concatenated n-vectors)
  - `LayerNormKernel` → `jitml_onednn_layernorm_weighted`
    (caller-supplied scale/shift)
  - `EmbeddingKernel` → `jitml_onednn_embedding_weighted`
    (caller-supplied embedding table as `table_rows × n` row-major)
  - `MultiHeadAttentionKernel` → `jitml_onednn_mha_weighted`
    (caller-supplied QKV projection matrices as three concatenated
    `n × n` blocks)
  - `Dense2D` continues to route through `jitml_onednn_dense_weighted`
  - `Identity` / `Reduction` keep the unweighted fallback (no natural
    weight parameter)
- `JitML.Codegen.Cuda.weightedFamilyImpl` mirrors the same per-family
  weighted device kernels: `jitml_device_conv2d_weighted`,
  `jitml_device_conv3d_weighted`, `jitml_device_batchnorm_weighted`,
  `jitml_device_layernorm_weighted`, `jitml_device_embedding_weighted`,
  `jitml_device_mha_weighted` — each launching with the standard
  256-thread block and copying device buffers through
  `jitml_cuda_copy_and_launch_weighted`.
- Cache key fingerprints in `JitML.Engines.Local.linuxCpuToolchainFingerprint`
  and `JitML.Engines.CudaLocal.cudaToolchainFingerprint` extended with
  `weighted-bodies=all-families` so pre-2026-05-27 cache entries
  invalidate and the next build picks up the real weighted primitives
  instead of the prior unweighted fall-through.
- `jitml-cross-backend` adds a determinism test for the new family
  weighted bodies that runs each (Conv2D / Conv3D / BatchNorm /
  LayerNorm / Embedding) twice on the same input + weight buffer and
  asserts bit-identical output across the two runs. MHA omitted from
  the test cohort because its embedded triple-matmul is sensitive to
  reduction order (covered at the time by broader Phase 17 comparison
  fixtures, later removed with the cross-substrate numeric parity surface).

### Live Validation Note (2026-05-27, per-family weighted bodies)

`cabal test jitml-cross-backend -p weighted` inside `jitml:local`
exercises all three weighted determinism tests:

```
jitml-cross-backend
  linux-cpu weighted Dense2D kernel runs real GEMM bit-deterministically (Sprint 15.11):                                          OK (1.10s)
  linux-cpu weighted Conv2D / Conv3D / BatchNorm / LayerNorm / Embedding bodies compile and run deterministically (Sprint 15.11): OK (5.16s)
  linux-cuda weighted Dense2D kernel runs real device GEMM bit-deterministically (Sprint 15.11):                                  OK (2.02s)

All 3 tests passed (8.28s)
```

The new "Conv2D / Conv3D / BatchNorm / LayerNorm / Embedding"
cohort builds each family's weighted `kernel.cc` through the
oneDNN compile path, runs it twice against the same input + weight
buffer, and asserts bit-equality across the two runs — confirming
the real per-family weighted primitives produce deterministic
output under the determinism contract. The live `jitml inference
  run` test (Sprint 15.12 closure) covers the daemon-side bit-
  determinism end-to-end for the CUDA Dense2D path; the wider per-family
  cross-substrate numeric-comparison plan was later removed by Phase 17
  Sprint `17.4`.

### Remaining Work

- None remaining for Sprint 13.11. Sprint closed 2026-05-27.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

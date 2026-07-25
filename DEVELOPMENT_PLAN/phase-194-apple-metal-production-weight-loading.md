# Phase 194: Apple Metal Production Weight Loading

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Metal Production Weight Loading. Single-session phase migrated from legacy Sprint 16.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 194.1: Apple Metal Production Weight Loading [✅ Done]

**Status**: Done (same-host determinism validated headless 2026-05-30; cross-substrate ULP parity is Phase `17`)
**Blocked by**: Sprint `191.1`, Phase `15` Sprint `174.1` (live MinIO
checkpoint round-trip)
**Implementation**: `src/JitML/Checkpoint/Store.hs`,
`src/JitML/Engines/MetalLocal.hs`,
`src/JitML/Engines/Loader.hs`
**Docs to update**: `documents/engineering/checkpoint_format.md`,
`documents/engineering/determinism_contract.md`

### Objective

Extend `loadInferenceCheckpointWithWeights` to the Apple Metal runner so
real weight blobs decoded from `.jmw1` load into Metal `MTLBuffer`
device memory and feed `MTLComputePipelineState` execution. Closes the
Apple-Metal portion of Exit Definition item 7 (production weight
loading per substrate).

### Deliverables

- `JitML.Engines.MetalLocal.runMetalWeightedKernel` accepts decoded
  weight tensors from `loadInferenceCheckpointWithWeights` and binds
  them to the Metal kernel as `MTLBuffer` inputs.
- The daemon dispatches `apple-silicon` + `SelfInference` (Apple
  host-native) and `apple-silicon` + `ForwardToHost` (cluster-side
  forward) through the new weighted runner.

### Validation

1. A canonical Apple-Silicon inference request with weighted checkpoint
   produces a deterministic output bit-identical to the same request
   run twice in sequence.
2. The weighted output matches the cross-substrate ULP tolerance band
   pinned by Phase `17` Sprint `17.1`.

### Code Surface Landed (2026-05-30)

- `JitML.Engines.MetalLocal.runMetalWeightedKernel` /
  `runMetalWeightedFamilyKernel` / `runMetalWeightedCheckpointInference`
  are implemented (mirror of the CUDA weighted path): they resolve
  `jitml_weighted_kernel` and thread the input + flattened weight buffers
  across the FFI to the generated launcher.
- `JitML.Codegen.Metal` emits the **per-family** weighted shaders mirroring
  `JitML.Codegen.Cuda.weightedFamilyImpl`: Dense2D GEMM
  (`out[i] = sum_j input[j] * W[j*n + i]`), Conv2D / Conv3D 1×1 scaling,
  BatchNorm (`[scale, shift, mean, var]`), LayerNorm (input-mean/var +
  `[scale, shift]`), Embedding (row-major table lookup), and MHA
  (`Wq`/`Wk`/`Wv` blocks, no softmax). The `weighted-bodies=all-families`
  fingerprint tag invalidates the prior Dense2D-baseline cache entries.
- `JitML.App.daemonWorkloadDispatcherForRuntime` routes
  `(AppleSilicon, SelfInference)` through
  `daemonWorkloadDispatcherWithWeightedInference` →
  `runMetalWeightedCheckpointInference`; `JitML.App.inferenceForSubstrate`
  routes the `apple-silicon` `jitml inference run` CLI path through
  `loadInferenceCheckpointWithWeights` + the Metal weighted runner.
- `jitml-cross-backend` adds the weighted Dense2D bit-determinism case
  (skips unless a Metal device is usable headless); all 185 `jitml-unit`
  tests pass. (Phase `7` Sprint `7.8` moves the `MTLLibrary` source from the
  relocated metallib to in-process runtime `makeLibrary(source:)`.)

### Remaining Work

- Same-host determinism is validated headless 2026-05-30: the weighted Dense2D
  Metal kernel runs bit-identically across three runs and equals `[1, 4, 9]`
  through the host build → runtime `makeLibrary` → FFI path. The cross-substrate
  ULP tolerance comparison of these Apple outputs against Linux CPU / CUDA is
  owned by Phase `17` Sprint `17.1`; the `(AppleSilicon, ForwardToHost)`
  cluster-side dispatch is owned by Sprint `16.4`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

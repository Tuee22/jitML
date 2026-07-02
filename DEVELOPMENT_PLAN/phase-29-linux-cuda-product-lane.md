# Phase 29: linux-cuda Product Lane

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-28-per-model-integration-and-e2e.md](phase-28-per-model-integration-and-e2e.md), [phase-30-apple-silicon-product-lane.md](phase-30-apple-silicon-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md)
**Generated sections**: none

> **Purpose**: Implement the real cuDNN/cuBLAS conv, attention, GEMM, pool, and
> norm kernels and validate the row-complete product matrix on the real
> `linux-cuda` substrate without requiring Apple Silicon in the same phase.

## Phase State

⏸️ **Blocked by** Phase `28`.

**Validation substrate**: `linux-cpu` plus `linux-cuda`; no `apple-silicon`
validation is part of this phase.

## Objective

The CUDA codegen path emits real device kernels: convolution runs through
`cudnnConvolutionForward`/`cudnnConvolutionBackward*`, attention and dense layers
run through `cublasSgemm`, and pooling and normalization run through their cuDNN
descriptors. The `cublasSgemm`/`cudnnConvolutionForward` call sites and the
runtime handles live on the update-critical path instead of being linked,
version-probed, and never invoked. Every product row that `linux-cpu` validates
also runs on the real NVIDIA lane where CUDA is supported, and each CUDA-supported
row records real GPU device evidence — probe, compile, load, launch, and
trained-state updates — completed checkpoints, demo rendering, integration
coverage, and e2e coverage for the same product matrix. Runtime absence fails up
front, and the report distinguishes unsupported rows from failed supported rows.

## Sprint 29.1: Real cuDNN/cuBLAS Kernels [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Codegen/Cuda.hs`, `src/JitML/Engines/CudaLocal.hs`, `src/JitML/Engines/CublasBindings.hs`, `src/JitML/Engines/CudnnBindings.hs`, `test/backends/Main.hs`
**Blocked by**: Phase `28`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

### Objective

`src/JitML/Codegen/Cuda.hs` renders real device kernels for the whole CUDA
family. Convolution forward and backward call `cudnnConvolutionForward` and the
`cudnnConvolutionBackwardData`/`cudnnConvolutionBackwardFilter` pair, attention
and dense/GEMM layers call `cublasSgemm`, and pooling and spatial/layer
normalization call their cuDNN descriptor APIs. The `verifyCublasRuntime` and
`verifyCudnnRuntime` handles in `src/JitML/Engines/CublasBindings.hs` and
`src/JitML/Engines/CudnnBindings.hs` are extended past version probing into the
live launch handles the rendered kernels dispatch through, so the bindings are no
longer dead code that is linked and version-probed but never invoked.

### Deliverables

- Real convolution kernels replace the identity-copy `identityLikeFamilyImpl`
  Conv2D/Conv3D bodies and the degenerate weighted 1x1 (`multiply by weights[0]`)
  path with `cudnnConvolutionForward` forward passes and
  `cudnnConvolutionBackwardData`/`cudnnConvolutionBackwardFilter` backward passes
  over real filter, stride, padding, and dilation descriptors.
- Real attention and dense/GEMM kernels replace the identity-copy MHA, GEMM, and
  Embedding family bodies with `cublasSgemm` calls chained for the QKV linear,
  the scaled scores, and the output projection.
- Real pooling and normalization kernels replace the identity-copy pool,
  Spatial BatchNorm, and LayerNorm bodies with their cuDNN pooling and
  normalization descriptors instead of pre-baked-stat readback.
- `src/JitML/Engines/CublasBindings.hs` and `src/JitML/Engines/CudnnBindings.hs`
  expose the handle-create, workspace, launch, and handle-destroy bindings the
  rendered kernels invoke, so `cublasSgemm` and `cudnnConvolutionForward` are on
  the update-critical path rather than version-probe-only dead code.
- The misleading `cuBLAS-backed GEMM scaffold`, `cuDNN-backed Conv2D scaffold`,
  `cuDNN-backed Conv3D scaffold`, `cuDNN Spatial BN scaffold`, `LayerNorm
  scaffold`, and `MHA scaffold` comments in `src/JitML/Codegen/Cuda.hs` are
  removed or rewritten to describe the real device kernels.
- `test/backends/Main.hs` asserts the rendered CUDA source calls the real cuDNN
  and cuBLAS entry points, that a forward/backward pair changes device output for
  a non-degenerate filter, and that the run fails closed when the CUDA runtime is
  absent.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement the real `cudnnConvolutionForward`/backward, `cublasSgemm`, pool,
  and norm kernels in `src/JitML/Codegen/Cuda.hs` and
  `src/JitML/Engines/CudaLocal.hs`.
- Wire the `CublasBindings`/`CudnnBindings` launch handles into the rendered
  kernels and retire the version-probe-only dead code.
- Rewrite the `scaffold` comments and add the `test/backends/Main.hs` real-kernel
  assertions and runtime-absence negative test.

## Sprint 29.2: CUDA Row Device Evidence [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Product/Matrix.hs`, `test/backends/Main.hs`
**Blocked by**: Sprint `29.1`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Every CUDA-supported product row in `src/JitML/Product/Matrix.hs` records real
GPU device evidence for the update-critical operations. The evidence proves the
device was probed, the kernel compiled, loaded, and launched, and the row's
trained state updated on the GPU. Runtime absence fails up front, and the report
distinguishes an unsupported row from a failed supported row.

### Deliverables

- Every CUDA-supported product row records real GPU device evidence — probe,
  compile, load, launch, and the update-critical forward/backward/update
  operations — drawn from the real kernels of Sprint `29.1`, not from
  identity-copy readback.
- The linux-cuda runtime is required up front: an absent CUDA runtime, driver, or
  GPU fails the lane immediately, and no CUDA row passes vacuously.
- The report distinguishes rows the matrix classifies as CUDA-unsupported from
  CUDA-supported rows that ran and failed, so a missing device claim never reads
  as a pass.
- `test/backends/Main.hs` asserts each CUDA-supported row carries device evidence
  bound to the real kernel launch and that an unsupported row is reported as
  unsupported rather than passed.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Add CUDA product-row device-evidence collection bound to the real kernels.
- Add the up-front runtime-absence failure and the unsupported-vs-failed row
  reporting.

## Sprint 29.3: CUDA Integration, E2E, and Attestation [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `DEVELOPMENT_PLAN/attestations/`
**Blocked by**: Sprint `29.2`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`

### Objective

`jitml test all --linux-cuda` runs every CUDA-supported product row for real
through the training, checkpoint, integration, and e2e paths. Live Playwright
hits the CUDA edge and renders row-specific trained artifacts, and the refreshed
`linux-cuda` attestation is committed under `DEVELOPMENT_PLAN/attestations/`.

### Deliverables

- `jitml test all --linux-cuda` runs every CUDA-supported product row for real,
  covering training, completed checkpoints, integration, and e2e.
- Live Playwright hits the CUDA edge and renders each row's inference-eligible
  trained artifact, not a static generated name list.
- The CUDA report card records row ids, real device evidence, integration
  evidence, and e2e evidence, and separates unsupported rows from failed
  supported rows.
- The refreshed `linux-cuda` attestation is committed to
  `DEVELOPMENT_PLAN/attestations/linux-cuda-report-card.md` after the lane passes.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test all --linux-cuda
docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Run and fix the CUDA product matrix across integration and e2e.
- Commit the refreshed `linux-cuda` attestation after validation.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/jit_codegen_architecture.md` — record the real
  cuDNN/cuBLAS conv, attention, GEMM, pool, and norm kernels and the retired
  version-probe-only bindings.
- `documents/engineering/numerical_core.md` — record the real CUDA layer kernels
  replacing the identity-copy family and degenerate 1x1 conv bodies.
- `documents/engineering/unit_testing_policy.md` — ownership of the CUDA
  real-kernel, device-evidence, integration, and e2e tests.
- `documents/engineering/purescript_frontend.md` — the CUDA-edge Playwright
  coverage of row-specific trained artifacts.

**Product docs to create/update:**
- `README.md` — current product status after the `linux-cuda` lane validates.

**Cross-references to add:**
- Link the `linux-cuda` attestation from Phase `31`.

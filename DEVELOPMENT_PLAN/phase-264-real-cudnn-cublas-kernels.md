# Phase 264: Real cuDNN/cuBLAS Kernels

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real cuDNN/cuBLAS Kernels. Single-session phase migrated from legacy Sprint 29.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-08-12). Reopened: the weighted family renderer ends in a wildcard, and
the unweighted multi-head-attention family renders an elementwise square that
disagrees with the `linux-cpu` renderer for the same family. The generated CUDA
family sources remain real; what is missing is a CUDA path for the typed layer
graph, so the accelerator lane cannot execute the operators the product rows
use.

## Sprint 264.1: Real cuDNN/cuBLAS Kernels [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Codegen/Cuda.hs`, `src/JitML/Engines/CudaLocal.hs`, `src/JitML/Engines/CublasBindings.hs`, `src/JitML/Engines/CudnnBindings.hs`, `test/backends/Main.hs`
**Docs updated**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

### Objective

`src/JitML/Codegen/Cuda.hs` renders generated CUDA family sources whose
operation-critical bodies call cuBLAS/cuDNN instead of carrying product-reachable
identity-copy placeholder bodies for Dense, Conv2D, Conv3D, BatchNorm,
LayerNorm, and MHA. The generated source owns the native CUDA/cuBLAS/cuDNN
handles inside the compiled artifact, while the Haskell binding modules keep the
typed compile/runtime probes that fail closed when the CUDA cabal flag or runtime
is absent.

### Deliverables

- Dense2D and MHA generated CUDA bodies route the flat-vector GEMM ABI through
  deterministic `cublasSgemm` calls. MHA chains Q/K projections, a CUDA
  score-product kernel, and an output projection through the same cuBLAS helper.
- Conv2D and Conv3D generated CUDA bodies route the weighted and unweighted
  flat-vector family ABI through cuDNN tensor/filter/convolution descriptors and
  `cudnnConvolutionForward` with
  `CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM`.
- BatchNorm and LayerNorm generated CUDA bodies route through cuDNN
  batch-normalization descriptors; LayerNorm uses per-activation mode and
  generated mean/variance parameter filling.
- Embedding keeps its explicit CUDA table-lookup kernel because cuBLAS/cuDNN do
  not provide an embedding lookup primitive; the unweighted embedding case copies
  indices through by design.
- The old `scaffold` comments are removed from generated CUDA source, and the
  Sprint `29.1` future-owned CUDA scaffold entries are removed from
  `ProductTruth`.
- `test/backends/Main.hs` asserts the rendered CUDA source calls
  `cublasSgemm`, `cudnnConvolutionForward`, cuDNN tensor descriptors, and cuDNN
  normalization APIs, and `jitml-backends --linux-cuda` compiles and executes
  the generated source on the attached GPU.

### Validation

```bash
docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

2026-07-10 live validation: `docker compose run --rm jitml-cuda jitml test
jitml-backends --linux-cuda` passed **22 / 22** on the attached RTX 5090,
including real `cublasSgemm` / `cudnnConvolutionForward` execution,
bit-deterministic device GEMM, nvcc + FFI compile/run, and the persistent MLP
weight-buffer source guard.

### Historical Validation

- **Closed Exit-Definition obligation (real device cuBLAS/cuDNN kernels).** The
  Dense/MHA/Conv2D/Conv3D/BatchNorm/LayerNorm generated CUDA bodies must call
  `cublasSgemm` / `cudnnConvolutionForward` and run real GEMM/convolution on the
  attached GPU for every CUDA-supported product row, and the
  `CublasBindings.hs` / `CudnnBindings.hs` probes must be live on that path
  instead of dead imports — a rendered-source text match must not stand in for
  device execution.
- **Negative-control validation that closes it.** Re-run
  `docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda`
  gated by the
  [`jitml-negative-controls`](README.md#legacy-to-new-phase-map)
  differential that rejects an identity-copy result as cuBLAS/cuDNN evidence, so
  a row cannot pass on rendered-source text alone. Validation stays single
  accelerator: `linux-cuda` plus `linux-cpu`, never `apple-silicon`.

### Remaining Work

- Close the weighted-family wildcard.
- Render the unweighted attention family against the shared semantics contract from
  Sprint `84.1`.
- Implement the CUDA arm of the total lowering so every `LayerOp` executes on the
  GPU rather than falling back to the pure executor.

### Historical Phase State

> ✅ **Done**.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

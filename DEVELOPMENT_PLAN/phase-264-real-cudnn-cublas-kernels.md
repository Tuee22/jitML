# Phase 264: Real cuDNN/cuBLAS Kernels

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Real cuDNN/cuBLAS Kernels. Single-session phase migrated from legacy Sprint 29.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-16). The typed layer graph has a CUDA arm: the
accelerator lane executes every declared `LayerOp` through cuBLAS/cuDNN
primitives under the same total lowering `linux-cpu` uses, rather than falling
back to the pure host executor.

## Sprint 264.1: Real cuDNN/cuBLAS Kernels [✅ Done]

**Status**: Done
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

### Closure Evidence

The three reopened obligations are closed. The weighted-family wildcard and the
unweighted multi-head-attention divergence were closed by Sprint `84.1`:
`weightedFamilyImpl` in `src/JitML/Codegen/Cuda.hs` enumerates every
`KernelFamily` with no wildcard arm, and `assertUnweightedMatchesContract` holds
each lane's unweighted body to the weighted reference evaluated at
`FamilyReference.defaultFamilyWeights`, so the three renderers cannot disagree
for one family.

The third — a CUDA arm for the typed layer graph — is this sprint's work.
`JitML.Codegen.LayerTraining` owns the backend-agnostic operator layer (kind
dispatch, GeGLU, normalization, patch embedding, multi-head attention, residual,
and the unified `jitml_op_train` opcode entry), and each lane supplies only its
*primitive* layer: `JitML.Codegen.OneDnn` renders `dnnl` matmul/convolution/
pooling, `JitML.Codegen.CudaLayerTraining` renders cuBLAS `CUBLAS_PEDANTIC_MATH`
GEMM plus deterministic cuDNN algorithms with Nd descriptors for 2-D and 3-D.
Because the operator bodies are one shared string rather than a per-lane copy,
two lanes cannot drift in operator semantics.

`JitML.Numerics.LayerGraphOneDnn` is renamed `LayerGraphDevice` and
parameterised on `Substrate`. A narrower `LayerTrainingBackend`
(`OneDnnLayerTraining` / `CudaLayerTraining`) makes every function behind it
total, and `layerTrainingBackendFor` is the single boundary where a substrate
becomes a backend. `apple-silicon` has no layer-graph training kernel, so it
fails closed naming Sprint `269.1` rather than silently executing the
`linux-cpu` artifact and attributing the run to hardware that did not execute
it. The execution witness is minted from `layerTrainingBackendSubstrate` — the
substrate the backend *is*, read off what executed, not the one requested.

**The `linux-cpu` rendered text is byte-identical**, which is a hard requirement
rather than a nicety: Sprint `263.1` pins `Text.take 16` of this artifact's
SHA-256 into the committed lane fragment, so appending the shared layer after
the primitives would relocate the kind-dispatch block (measured: 941 rendered
lines become 943, with 228 relocated) and restamp an attested `linux-cpu` digest
for a CUDA-only feature. The shared layer is therefore split into three
positional chunks that each backend splices at its own offsets. Rendered
`kernel.cc` SHA-256 is
`42f20f9acfe24021a1298a299b09fa43c1344bc9deb837b54b45b7dcd163c407` before and
after the split, and the `jitml-unit` case `the linux-cpu lane keeps its
attested emission order` pins six anchor offsets so the mistake is a failing
unit case rather than a failed twelve-hour live gate.

Validation on 2026-08-16 against image
`jitml:local@sha256:7c83829d1fa4f67e5ea06e85082290339ea0689ccde2d45b890e9aeaf890a90b`:
`jitml test jitml-backends --linux-cuda` passed **25 / 25** on the attached RTX
5090, including `linux-cuda LayerGraph training kernels match the pure oracle and
record device evidence`, `linux-cuda real 3-D convolution executes its own cuDNN
device kernel`, and `linux-cuda LayerGraph classification training reduces
cross-entropy loss`; `jitml test jitml-unit --linux-cpu` passed **891 / 891**,
including the four-case `Layer-graph training lanes (Phase 264)` group;
`jitml lint haskell`, `jitml docs check`, and `jitml check-code` all passed, so
every stanza builds at `-Werror` both with and without `-fcuda`. The retained
transcript is the gitignored `.build/gate-logs/phase264-closure-gate.log`,
SHA-256 `d182e11379844cf6fd2a66db4442d66a00ac1b526035541f39b040d7f38cdf0c`.

Two defects in the arm were found and fixed by validating it rather than
trusting it. The shared layer was first appended after the primitives, which
relocated 228 lines of `linux-cpu` text and would have restamped that lane's
attested digest — caught by rendering both trees and diffing, and now prevented
by the positional split plus the emission-order unit case, which is
mutation-verified to fail on the naive concatenation. Separately, the CUDA
classification-training case trained over the one-node-per-declared-kind
gradient fixture, whose `PoolGlobal` collapses the width-4 activation to a
single value; its output is uniform and its parameter gradient vanishes, so the
assertion was unsatisfiable on any backend. Running the identical fixture and
hyperparameters through the oneDNN arm returned bit-identical
`before = after = 5.545177444479562` (4 × ln 4), proving the CUDA arm correct and
the assertion wrong, so the case now mirrors the `linux-cpu` `mixed-correct-op`
graph, which learns.

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

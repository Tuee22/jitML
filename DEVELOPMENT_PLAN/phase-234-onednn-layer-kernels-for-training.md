# Phase 234: oneDNN Layer Kernels for Training

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: oneDNN Layer Kernels for Training. Single-session phase migrated from legacy Sprint 23.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (batched kernels landed + validated 2026-07-27). The oneDNN layer
kernels compute the update-critical forward/backward over a **batch** of N
examples in one device call per layer: the generated C ABI (`jitml_layer_forward`
/ `jitml_layer_backward_data` / `jitml_layer_backward_weights`) and the
`LayerGraphOneDnn` dispatch carry a batch dimension, `jitml_matmul_backward_weights`
reduces the weight/bias gradient over the batch (transposed-`d_pre` GEMM
contraction over N), and `convolution_backward_weights` reduces natively — so the
former per-example device round-trips collapse to one batched call per layer,
making layer-graph training tractable once [Phase 235](phase-235-one-self-describing-checkpoint-envelope.md)
onward make the typed `LayerGraph` IR the supervised executor. Validated on the
`linux-cpu` container lane 2026-07-27: `jitml test jitml-backends --linux-cpu`
**26 / 26** (including "batched LayerGraph oneDNN gradient matches the per-example
summed oracle (Phase 234)"), `jitml test jitml-unit --linux-cpu` **771 / 771**,
and `jitml check-code` **ok**. Earlier per-example kernel evidence is retained
under [Historical Validation](#historical-validation).

## Sprint 234.1: oneDNN Layer Kernels for Training [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Codegen/OneDnn.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/Numerics/MlpOneDnn.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Engines/OneDnnRuntime.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

### Objective

Wire the layer graph's parameterized forward pre-activation and backward
parameter/input-gradient operations to generated oneDNN kernels through the JIT
device. `src/JitML/Codegen/OneDnn.hs` renders the training ABI, and
`src/JitML/Numerics/LayerGraphOneDnn.hs` binds it to the pure `Autodiff` tape so
the backend computes update-critical gradients rather than only the pure oracle.

### Deliverables

- `src/JitML/Codegen/OneDnn.hs` renders a layer-graph training shared object
  with a stable `jitml_layer_forward`, `jitml_layer_backward_data`, and
  `jitml_layer_backward_weights` ABI. Dense and other affine graph nodes execute
  oneDNN matmul primitives; `Conv2D` and `Conv3D` execute real
  `convolution_forward` (`forward_training`),
  `convolution_backward_data`, and `convolution_backward_weights` primitives
  over the graph's flat 1x1 channel projection.
- `JitML.Numerics.LayerGraphOneDnn` dispatches each parameterized layer node to
  that generated oneDNN ABI, reusing the pure `Autodiff` tape for activation,
  residual, and parameterless graph semantics. The returned evidence records the
  backend, artifact, and primitive name used for every parameterized node.
- A backends test asserts backend-vs-pure-oracle agreement within tolerance for
  every layer node's forward and backward, and records that the oneDNN device
  executed the update-critical operations (device evidence for the product row).
- Runtime absence of `libdnnl` fails the lane up front; no layer kernel passes
  vacuously.
- The generated ABI and the `LayerGraphOneDnn` dispatch run forward/backward over
  a **batch** of N examples in one device call per layer (oneDNN batched matmul
  and convolution): `jitml_matmul_backward_weights` reduces the weight/bias
  gradient over the batch and `convolution_backward_weights` reduces natively,
  replacing the former per-example device round-trips. The pure `Autodiff` oracle
  still runs per example to seed each layer's pre-activation gradient. A backends
  test asserts the batched device gradient reproduces the per-example summed
  oracle within tolerance, with one evidence entry per parameterized node (not per
  example); the training loop takes one batched device call per mini-batch.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation

The initial 2026-07-02 backend comparison was withdrawn when the audit found
that its reference shared the same dense approximation. The 2026-07-06
reclosure moved Conv2D/Conv3D update-critical work through real oneDNN
convolution training primitives and compared the backend against the corrected
per-kind reference algebra. The retained validation is summarized in
[Phase State](#phase-state); absence of `libdnnl` still fails the lane up front.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

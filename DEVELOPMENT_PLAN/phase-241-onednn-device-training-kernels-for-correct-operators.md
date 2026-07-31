# Phase 241: oneDNN Device Training Kernels for Correct Operators

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Give the typed `LayerGraph` IR real device (oneDNN) forward +
> backward-weights training kernels for every parameterised correct operator —
> spatial `ConvOp`, `NormOp`, `GeGLUOp`, multi-head `AttentionOp` (with `W_O`),
> `PatchOp`, and the `ResidualOp`/`BlockOp` compositions — so the literal
> architectures (Phases `242`–`244`) can be trained on device, not just served.

## Phase State

✅ **Done** (closed 2026-07-30; gate-validated on the live linux-cpu cluster).
Every parameterised correct operator now trains on the oneDNN device: the
generated kernel renders a real `dnnl` primitive per operator kind — spatial
`ConvOp` (forward / backward-data / backward-weights), `NormOp`, `GeGLUOp`,
multi-head `AttentionOp` with `W_O`, `PatchOp`, `ResidualOp`, and the
BasicBlock/Bottleneck `BlockOp` composed from dense+norm device sub-kernels — and
`deviceLayerGradient` dispatches on the layer's `LayerOp`. Each device kernel is
validated against the pure `backwardLayerGraph` oracle within float32 tolerance
in the backends lane (jitml-backends 35/35, incl. the BlockOp and strided-conv
oracle cases).

## Sprint 241.1: oneDNN Device Training Kernels for Correct Operators [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Codegen/OneDnn.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/jit_codegen_architecture.md`

### Objective

Every parameterised operator the correct-operator architectures use trains on the
oneDNN device: the generated kernel renders real `dnnl` primitives for each
operator's forward, backward-data, and backward-weights, the FFI passes the
operator's true geometry (spatial dims, kernel dims, strides, padding, head
count, per-projection widths) rather than a flat `(inputs, outputs)` pair, and
`runDeviceLayer` / `deviceLayerGradient` dispatch on the layer's `LayerOp` to the
matching kernel with the operator's real packed-parameter layout. The pure
`backwardLayerGraph` gradient (FD-validated in Phase `233`) is the **oracle** each
device kernel is checked against within float32 tolerance; it is never a runtime
fallback (the hardware-native determinism contract forbids a pure fallback on the
execution path).

### Deliverables

- **Real spatial Conv2D** (`ConvOp`): the generated kernel renders
  `dnnl::convolution_{forward,backward_data,backward_weights}` over the true
  `[C_in, H, W]` / `[C_out, C_in, Kh, Kw]` / strides / padding, replacing the 1×1
  stand-in; the FFI carries the conv geometry; validated against `convForward` /
  `convBackward`.
- **Normalization** (`NormOp`): batch / layer / group norm forward + backward for
  the `gamma`/`beta` affine parameters via `dnnl` normalization primitives;
  validated against `normForward` / `normBackward`.
- **GeGLU** (`GeGLUOp`): the three-projection gated-GELU forward + backward
  (compose `dnnl` matmul + GELU eltwise); validated against `gegluForward` /
  `gegluBackward`.
- **Multi-head Attention with `W_O`** (`AttentionOp`): Q/K/V/O projections,
  scaled dot-product with softmax, and the per-projection weight gradients
  (compose `dnnl` matmul + softmax); validated against `attentionForward` /
  `attentionBackward`.
- **Patch-embed** (`PatchOp`) and the **Residual/Block** compositions
  (`ResidualOp` / `BlockOp`): forward + backward-weights over their real packed
  layouts; validated against `patchForward`/`patchBackward` and
  `residualForward`/`blockForward` / `residualBackward`/`blockBackward`.
- `runDeviceLayer` / `deviceLayerGradient` / `layerKindCode` dispatch on the
  layer's `LayerOp` and accept the operator's true parameter-segment layout
  (`opWeightSegments`/`opBiasSegments`), so `trainLayerGraphClassifierOneDnn`
  trains a graph containing any mix of the correct operators.
- Backends tests train a small graph built from each correct operator end to end
  through the batched oneDNN loop and assert (a) the device parameter gradient
  matches the pure `backwardLayerGraph` oracle within float32 tolerance and
  (b) cross-entropy decreases; device evidence recorded.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Validated 2026-07-30 (container `jitml:local`, live linux-cpu cluster):
jitml-backends 35/35 — including the BlockOp (BasicBlock/Bottleneck)
device-training oracle case and the strided-conv oracle case, each asserting the
device parameter gradient matches the pure `backwardLayerGraph` oracle within
float32 tolerance and that cross-entropy decreases. jitml-unit passed with 0
failures, `jitml check-code` ok, and `jitml docs check` ok; the full product run
`jitml internal train-and-publish-product-rows --linux-cpu` exited 0 with 55/55
admitted, training every literal graph on these device kernels.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/numerical_core.md` — record the device training
  kernels for the correct operators (prose only; generated `numerics.*` catalog
  tables are regenerated via `jitml docs generate`).
- `../documents/engineering/jit_codegen_architecture.md` — the layer-graph oneDNN
  training kernel renders a real `dnnl` primitive per operator kind with the
  operator's true geometry and packed-parameter layout.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

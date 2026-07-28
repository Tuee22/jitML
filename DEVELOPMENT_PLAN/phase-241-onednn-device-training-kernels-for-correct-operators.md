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

⏸️ **Blocked**. Blocked by Phase 240 (Sprint 240.1). Inserted 2026-07-28 after the
IR-training audit found that `trainLayerGraphClassifierOneDnn`'s device gradient
(`runDeviceLayer`) is **dense-only**: it hard-requires
`length(weights) == inputs*outputs`, and the generated `jitml_conv2d_*` kernels
are actually 1×1 convolutions (dense-equivalent). `runLayerGraph` **serving**
already executes every correct operator (multi-head attention with `W_O`, GeGLU,
conv, patch, norm — forward and backward FD-validated in Phase `233`), but the
device **training** loop cannot train any parameterised non-dense layer, so the
literal correct-operator architectures could be served but not trained. This
phase supplies the missing device training kernels. It sits between the IR
plumbing (Phases `237`–`240`, which train the all-dense graph) and the literal
architectures (Phases `242`–`244`, which train the real operators). The unmet
obligations are in [Remaining Work](#remaining-work); see the old→new map in
[README.md](README.md).

## Sprint 241.1: oneDNN Device Training Kernels for Correct Operators [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `240.1`
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

### Remaining Work

- Every item in [Deliverables](#deliverables) is unmet. `runDeviceLayer`
  (`src/JitML/Numerics/LayerGraphOneDnn.hs`) still gates on
  `length(weights) == inputs*outputs` (dense-only) and the generated kernel in
  `src/JitML/Codegen/OneDnn.hs` renders only matmul + 1×1 "conv"; there are no
  device training kernels for `ConvOp` (spatial) / `NormOp` / `GeGLUOp` /
  `AttentionOp` / `PatchOp` / `ResidualOp` / `BlockOp`. Build them in the order
  above, each validated against its pure oracle in the backends lane, then close
  with the `### Validation` gate below.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

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

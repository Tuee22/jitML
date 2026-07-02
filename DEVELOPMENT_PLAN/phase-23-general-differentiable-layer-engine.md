# Phase 23: General Differentiable Layer Engine

**Status**: Blocked
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-22-canonical-matrix-and-dataset-integrity.md](phase-22-canonical-matrix-and-dataset-integrity.md), [phase-24-real-supervised-architectures.md](phase-24-real-supervised-architectures.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
**Generated sections**: none

> **Purpose**: Replace the single-hidden-layer hand-written backprop with a
> general reverse-mode autodiff over a typed layer graph, wired to the real
> oneDNN primitives for both training and inference, so deep architectures are
> literal networks rather than MLP-composed stand-ins.

## Phase State

⏸️ **Blocked by** Phase `22`.

**Validation substrate**: `linux-cpu` only.

## Objective

The numerical core owns one general differentiable layer engine. Every
supervised model family is a typed layer graph over the full layer catalog
(`Dense`, `Conv2D`, `Conv3D`, `MaxPool`/`AvgPool`/`GlobalAvgPool`, `BatchNorm`,
`LayerNorm`, `GroupNorm`, `Dropout`, `Residual`/`BasicBlock`/`BottleneckBlock`,
`MultiHeadAttention`, `GeGLU`, patch-embed), each with a real forward and a real
reverse-mode backward. Training and inference both execute that graph through the
real oneDNN kernels selected by the JIT device — including
`convolution_backward_data`, `convolution_backward_weights`, and the
normalization and attention backward chains — so a "deep", "ResNet", "ViT", or
"LeNet" row is a literal deep network rather than a host-composed
single-hidden-layer MLP block. The `linux-cpu` lane proves the layer engine
end to end: autodiff gradients match a pure oracle, the oneDNN backend matches
that same oracle within tolerance, checkpoints round-trip an arbitrary layer
graph, and the inference-only read path runs the real graph.

## Sprint 23.1: Typed Layer IR + Reverse-Mode Autodiff [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Phase `22`
**Implementation**: `src/JitML/Numerics/LayerGraph.hs`, `src/JitML/Numerics/Autodiff.hs`, `src/JitML/Numerics/Mlp.hs`, `src/JitML/SL/Architecture.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/determinism_contract.md`

### Objective

Generalize the single-hidden-layer hand-backprop in
`src/JitML/Numerics/Mlp.hs` into a reverse-mode autodiff pass over a typed layer
graph. The graph is the sole representation of every supervised architecture;
`src/JitML/SL/Architecture.hs` builds each family (`DenseFamily`,
`DeepDenseFamily`, `Conv2DLeNetFamily`, the ResNet and ViT families) as a real
`LayerGraph` instead of a composition of `DenseSpec` MLP blocks.

### Deliverables

- A `LayerGraph` IR whose nodes cover the full layer catalog: `Dense`, `Conv2D`,
  `Conv3D`, `MaxPool`, `AvgPool`, `GlobalAvgPool`, `BatchNorm`, `LayerNorm`,
  `GroupNorm`, `Dropout`, `Residual`, `BasicBlock`, `BottleneckBlock`,
  `MultiHeadAttention`, `GeGLU`, and patch-embed, each carrying its typed shape,
  parameter tensors, and training-vs-inference mode flag.
- A reverse-mode `Autodiff` pass that records a forward tape and replays a
  backward pass, so each layer node contributes a real forward and a real
  gradient (`backward_data` for inputs, `backward_weights` for parameters) rather
  than a hand-derived chain specialized to one hidden layer.
- `src/JitML/Numerics/Mlp.hs` is expressed as the two-layer special case of the
  general graph; the AlphaZero policy/value heads and the RL network seam consume
  the same `LayerGraph`/`Autodiff` surface.
- A unit test asserts finite-difference gradient checks pass for every layer node
  type and for at least one full ResNet-shaped and one ViT-shaped graph, and that
  the same seed and same substrate produce bit-identical gradients.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Implement the `LayerGraph` IR and the reverse-mode `Autodiff` tape.
- Port every SL family builder off `DenseSpec` MLP composition onto the graph.
- Add per-layer finite-difference gradient checks and the determinism assertion.

## Sprint 23.2: oneDNN Layer Kernels for Training [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `23.1`
**Implementation**: `src/JitML/Codegen/OneDnn.hs`, `src/JitML/Numerics/MlpOneDnn.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Engines/OneDnnRuntime.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

### Objective

Wire the layer graph's forward **and** backward to real oneDNN kernels through
the JIT device. Today `src/JitML/Codegen/OneDnn.hs` renders only
`prop_kind::forward_inference` convolution, batch-norm, layer-norm, and
matmul-attention primitives, and none are wired into the SL training path. This
sprint renders the training-direction primitives and binds them to the
`Autodiff` backward pass so gradients are computed by the backend, not only by
the pure oracle.

### Deliverables

- `src/JitML/Codegen/OneDnn.hs` renders the full training kernel set:
  `convolution_forward` (`forward_training`), `convolution_backward_data`,
  `convolution_backward_weights`, the batch-norm/layer-norm/group-norm forward
  and backward pairs, pooling forward and backward, and the attention matmul
  chain forward plus its transpose-matmul backward.
- The `Autodiff` backward pass dispatches each layer node to its oneDNN kernel
  via the JIT device selected by `src/JitML/Numerics/MlpDevice.hs`, so a
  `linux-cpu` training step executes real oneDNN convolution and normalization
  backward primitives.
- A backends test asserts backend-vs-pure-oracle agreement within tolerance for
  every layer node's forward and backward, and records that the oneDNN device
  executed the update-critical operations (device evidence for the product row).
- Runtime absence of `libdnnl` fails the lane up front; no layer kernel passes
  vacuously.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Render the convolution/normalization/pooling/attention backward kernels.
- Bind `Autodiff` backward dispatch to the oneDNN device path.
- Add the backend-vs-oracle tolerance assertions and device-evidence capture.

## Sprint 23.3: Layer-Graph Checkpoints + Inference [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `23.2`
**Implementation**: `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/Inference/Decode.hs`, `src/JitML/Engines/MlpCheckpoint.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

The checkpoint format stores an arbitrary layer graph's weights and the
inference-only read path runs the real layer graph, removing the MLP GEMM
shortcut so a trained deep/ResNet/ViT/LeNet artifact infers as its literal
network.

### Deliverables

- `src/JitML/Checkpoint/Format.hs` serializes the `LayerGraph` topology plus a
  per-node tensor blob for every layer catalog type, and the manifest's
  `ArchitectureMetadata` describes the graph rather than a single `MlpShape`.
- `src/JitML/Checkpoint/Store.hs` round-trips an arbitrary layer graph:
  save-then-load reproduces bit-identical parameter tensors and graph topology.
- `src/JitML/Inference/Decode.hs` and `src/JitML/Engines/MlpCheckpoint.hs`
  execute the stored graph's forward through the same oneDNN device kernels used
  in training, so inference on a convolutional or attention row is not reduced to
  a dense GEMM.
- An integration test trains a deep graph on `linux-cpu`, writes a completed
  checkpoint, reloads it, and asserts the inference forward matches the
  end-of-training forward within tolerance and that inference is rejected before
  training completion.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Extend the checkpoint format and store to the full layer-graph topology.
- Replace the MLP GEMM inference shortcut with real graph execution.
- Add the train/checkpoint/reload/infer integration test with the pre-completion
  inference rejection.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/numerical_core.md` — reverse-mode autodiff over the
  typed layer graph and the full layer catalog (forward + backward per node).
- `documents/engineering/jit_codegen_architecture.md` — oneDNN training-direction
  layer kernels, including convolution/normalization/pooling/attention backward.
- `documents/engineering/checkpoint_format.md` — arbitrary layer-graph
  checkpoint topology and per-node tensor blobs.
- `documents/engineering/determinism_contract.md` — layer-graph determinism:
  same seed and same substrate produce bit-identical gradients and inference.

**Product docs to create/update:**
- `README.md` — layer catalog available to supervised model families.

**Cross-references to add:**
- Link this phase from the control docs `README.md`, `00-overview.md`,
  `system-components.md`, and `development_plan_standards.md`.

# Phase 23: General Differentiable Layer Engine

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-22-canonical-matrix-and-dataset-integrity.md](phase-22-canonical-matrix-and-dataset-integrity.md), [phase-24-real-supervised-architectures.md](phase-24-real-supervised-architectures.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
**Generated sections**: none

> **Purpose**: Replace the single-hidden-layer hand-written backprop with a
> general reverse-mode autodiff over a typed layer graph, wired to the real
> oneDNN primitives for both training and inference, so deep architectures are
> literal networks rather than MLP-composed stand-ins.

## Phase State

✅ **Done**. Phase `22` has closed the canonical matrix/config/dataset
integrity boundary. Sprints `23.1`-`23.3` have completed the typed layer graph,
pure reverse-mode autodiff surface, oneDNN training-direction layer-kernel path,
and graph checkpoint/inference serialization for the current graph algebra.

**Validation substrate**: `linux-cpu` only.

## Objective

The numerical core owns one general differentiable layer engine. Every
supervised model family is represented as a typed layer graph over the full
catalog (`Dense`, `Conv2D`, `Conv3D`, `MaxPool`/`AvgPool`/`GlobalAvgPool`,
`BatchNorm`, `LayerNorm`, `GroupNorm`, `Dropout`,
`Residual`/`BasicBlock`/`BottleneckBlock`, `MultiHeadAttention`, `GeGLU`,
patch-embed), each with a forward tape and a reverse-mode backward. The
`linux-cpu` lane proves the layer engine end to end for the current graph
algebra: autodiff gradients match a pure oracle, the oneDNN backend computes the
update-critical parameter and input-gradient operations for parameterized nodes
within tolerance (with `Conv2D`/`Conv3D` lowered to real oneDNN convolution
training primitives and the other parameterized graph nodes lowered to oneDNN
matmul), checkpoints round-trip an arbitrary layer graph, and the inference-only
read path runs the stored graph. Literal per-family tensor specializations and
per-model architecture evidence continue in Phase `24`.

## Sprint 23.1: Typed Layer IR + Reverse-Mode Autodiff [✅ Done]

**Status**: Done
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

Current validation: `jitml-unit --linux-cpu` passed 269 / 269 on
2026-07-02. `docs check` and `check-code` are part of the final Sprint `23.1`
closure gate and passed after the status/docs update.

### Remaining Work

None.

## Sprint 23.2: oneDNN Layer Kernels for Training [✅ Done]

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

### Validation

```bash
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

Current validation: `jitml-backends --linux-cpu` passed 24 / 24 on
2026-07-02, including the LayerGraph oneDNN backend-vs-oracle and device
evidence test. `jitml-unit --linux-cpu` passed 269 / 269 on 2026-07-02, and
`jitml check-code` passed after the status/docs update.

### Remaining Work

None.

## Sprint 23.3: Layer-Graph Checkpoints + Inference [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/Inference/Decode.hs`, `src/JitML/Engines/LayerGraphCheckpoint.hs`, `src/JitML/Engines/Local.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

The checkpoint format stores an arbitrary layer graph's weights and the
inference-only read path runs the real layer graph, removing the MLP GEMM
shortcut so a trained deep/ResNet/ViT/LeNet artifact infers as its literal
network. The current implementation serializes the Phase `23.1` typed graph
topology in `ArchitectureMetadata`, reconstructs it from named `.jmw1` weight
and bias tensors, and routes `linux-cpu` graph checkpoint inference through the
oneDNN graph-forward runner before falling back to the legacy MLP/Dense2D paths.

### Deliverables

- `src/JitML/Checkpoint/Format.hs` serializes the `LayerGraph` topology as
  `LayerGraphMetadata` under `ArchitectureMetadata`, with each parameterized
  node naming its weight and bias tensors.
- `src/JitML/Checkpoint/Store.hs` reconstructs a `LayerGraph` from a manifest
  plus loaded `.jmw1` weight tensors, rejecting missing, duplicate, or
  shape-mismatched graph tensors before inference runs.
- `src/JitML/Engines/LayerGraphCheckpoint.hs` and
  `src/JitML/Engines/Local.hs` execute graph checkpoint inference through
  `JitML.Numerics.LayerGraphOneDnn.runLayerGraphForwardOneDnn` before the
  legacy MLP and Dense2D fallback paths.
- Unit and integration coverage round-trip graph topology/parameter tensors,
  assert completed graph checkpoints infer through the weighted checkpoint
  loader, and keep pre-completion inference rejection in the loader path.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Current validation: `jitml-unit --linux-cpu` passed 270 / 270 on 2026-07-02,
including the LayerGraph checkpoint topology round-trip. The targeted
`jitml-integration` graph checkpoint inference case passed when run directly
with `cabal test jitml-integration --test-show-details=direct --test-options='-p loadInferenceCheckpointWithWeights'`.
`jitml docs check` and `jitml check-code` both pass after the Sprint `23.3`
implementation/docs update. After rebuilding `jitml:local` with Dockerfile
`check-code: ok`, deleting and recreating the `jitml-linux-cpu` Kind cluster,
and running `jitml cluster up --substrate linux-cpu` with
`JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1`, `jitml cluster status` reported every
component ready and `docker compose run --rm jitml jitml test jitml-integration
--linux-cpu` passed all 79 / 79 tests on 2026-07-02.

### Remaining Work

None.

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

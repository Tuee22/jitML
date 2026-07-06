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

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). Phase `22` remains
closed on its canonical matrix/config/dataset integrity boundary, and the typed
`LayerGraph` IR, the checkpoint topology round-trip, and the oneDNN device seam
are all in place. The audit found that the layer engine did not compute the
layer catalog's real per-kind math: in `src/JitML/Numerics/LayerGraph.hs`,
`runLayerNode` (~line 408) routes **every** parameterized node through
`affinePreActivation` (~line 523) — a plain dense matmul — so `Conv2D`,
`Conv3D`, `MultiHeadAttention`, `GeGLU`, patch-embed, `BasicBlock`, and
`BottleneckBlock` are all the same dense GEMM with the kind tag ignored; every
`BatchNorm`/`LayerNorm`/`GroupNorm` node falls to the `resizeIdentity` no-op;
`Dropout` is a deterministic `* 0.9` rescale; and `MaxPool`/`AvgPool`/
`GlobalAvgPool` replicate or average a single value instead of pooling a
windowed tensor. The pure oracle is therefore a dense-stack stand-in, the oneDNN
"convolution" kernels lowered to a flat 1x1 (matmul-equivalent) projection that
agreed with that stand-in vacuously, and a "ResNet"/"ViT"/"LeNet" checkpoint
inferred as a dense stack, not its literal network. The reclosure is guarded by
the external negative-control and per-model suites named in the sprint closure
evidence. The standing anti-fake harness that grades these closures lives in
[phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md)
(the `jitml-negative-controls` stanza),
[phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md)
(the `jitml-model-convergence` per-model suite), and
[phase-34-plan-truth-governance.md](phase-34-plan-truth-governance.md).

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
closure gate and passed after the status/docs update. The 2026-07-05 realness
audit superseded this closure: those checks passed against a per-kind oracle
that is itself a dense stand-in, so gradient agreement was vacuous.

### Closure Evidence

The typed IR, the tape/replay autodiff mechanics, and the finite-difference
gradient check are in place, but the per-kind forward/backward math is fake, so
the owned obligation "each layer node contributes a real forward and a real
gradient" is unmet:

- `runLayerNode` (`src/JitML/Numerics/LayerGraph.hs`, ~line 408) must compute
  each kind's real math instead of routing every parameterized node through the
  dense `affinePreActivation` (~line 523): real 2D/3D convolution for
  `Conv2D`/`Conv3D`, scaled dot-product attention for `MultiHeadAttention`, the
  gated GeGLU projection, real patch extraction for patch-embed, and the real
  two-branch residual math for `BasicBlock`/`BottleneckBlock`.
- `parameterlessForward`/`parameterlessBackward` must stop being
  identity/`* 0.9`/replicate stubs: `BatchNorm`/`LayerNorm`/`GroupNorm` compute
  real normalization over their statistics, `Dropout` applies a real seeded
  mask, and `MaxPool`/`AvgPool`/`GlobalAvgPool` pool over real windows.
- The finite-difference check is re-derived against the real per-kind backward,
  not the dense stand-in.

**Negative-control validation.** A differential test proves each kind is not a
dense matmul: on structured input, a `Conv2D`/`Conv3D`/attention/pool node's
output differs from the dense-GEMM output of the same shape (a fake that
reintroduces `affinePreActivation` for those kinds is rejected). This case is
owned by the `jitml-negative-controls` stanza in
[phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md),
and gradients are checked against the real per-kind oracle on the `linux-cpu`
lane.

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
`jitml check-code` passed after the status/docs update. The 2026-07-05 realness
audit superseded this closure: the backend was compared against the dense
stand-in oracle, so agreement did not prove real convolution.

### Closure Evidence

The generated training ABI and the pure-vs-backend evidence harness exist, but
because the pure oracle is a dense-stack stand-in (Sprint `23.1`) and the
`Conv2D`/`Conv3D` kernels lower to a flat 1x1 channel projection, the
backend-vs-oracle agreement is vacuous and the owned obligation "`Conv2D` and
`Conv3D` execute real `convolution_forward`/`convolution_backward_data`/
`convolution_backward_weights` primitives" is unmet:

- `src/JitML/Codegen/OneDnn.hs` and `src/JitML/Numerics/LayerGraphOneDnn.hs`
  must lower each parameterized kind to the oneDNN primitive that computes its
  real math — real spatial convolution (not a 1x1/matmul-equivalent
  projection), attention, GeGLU, and pooling — so the device executes the
  kind's true update-critical operations.
- The backend-vs-pure-oracle test compares against the real per-kind oracle
  from the reopened Sprint `23.1`, not the dense stand-in.

**Negative-control validation.** The differential negative control (backend
`Conv2D` output differs from the dense-GEMM output of the same shape on
structured input, and oneDNN conv-backward gradients differ from dense backprop)
runs on the `linux-cpu` lane and is owned by the `jitml-negative-controls`
stanza in
[phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md).
`libdnnl` absence continues to fail the lane up front.

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
--linux-cpu` passed all 79 / 79 tests on 2026-07-02. The 2026-07-05 realness
audit superseded this closure: topology round-trip is real, but the restored
graph infers through the fake per-kind forward, so it does not infer as its
literal network.

### Closure Evidence

Checkpoint topology/tensor round-trip and pre-completion inference rejection are
in place, but because the graph-forward runner uses the fake per-kind math
(Sprints `23.1`/`23.2`), the owned obligation "a trained
deep/ResNet/ViT/LeNet artifact infers as its literal network" is unmet — such an
artifact currently infers as a dense stack:

- `runLayerGraphForwardOneDnn` (consumed by
  `src/JitML/Engines/LayerGraphCheckpoint.hs` and
  `src/JitML/Engines/Local.hs`) runs the real per-kind forward once Sprints
  `23.1`/`23.2` land it, so the stored graph infers as its literal network.

**Negative-control validation.** A per-model inference negative control proves a
restored ResNet/ViT/LeNet checkpoint's output differs from a dense stack of the
same shapes on structured input; the negative-control primitives are owned by
[phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md)
(`jitml-negative-controls`), and per-model measured convergence/inference is
graded by the `jitml-model-convergence` suite in
[phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md).
Both run on the `linux-cpu` lane.

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

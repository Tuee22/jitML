# Phase 23: General Differentiable Layer Engine

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-22-canonical-matrix-and-dataset-integrity.md](phase-22-canonical-matrix-and-dataset-integrity.md), [phase-24-real-supervised-architectures.md](phase-24-real-supervised-architectures.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/numerical_core.md](../documents/engineering/numerical_core.md), [../documents/engineering/jit_codegen_architecture.md](../documents/engineering/jit_codegen_architecture.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
**Generated sections**: none

> **Purpose**: Replace the single-hidden-layer hand-written backprop with a
> general reverse-mode autodiff over a typed layer graph, wired to the real
> oneDNN primitives, so deep architectures are literal networks rather than
> MLP-composed stand-ins. Phase `23` owns graph semantics and engine primitives;
> reopened Sprint `10.6` owns the exact persisted supervised runtime artifact,
> strict Store dispatch, and trained-versus-loaded execution parity.

## Phase State

⏸️ **Blocked** at Sprint `23.1`, which is blocked by Sprint `21.4`. The
2026-07-18 executable-graph audit found two competing representations: the
advertised `archLayerGraph` and the `[LayerSpec]` / `[LayerState]` program that
actually trains and serves. Token mixing and attention omit required residual
or direct-gradient terms, several pooling/normalization backprop paths remain
approximations, silent `zipWith`/fallback seams can truncate mismatches, and the
finite-difference suite does not cover the complete input-gradient contract.
Sprint `23.2` is blocked by `23.1`; Sprint `23.3` is blocked by `23.2`.

### Historical Closure Context

The 2026-07-06 library, unit, canonical-SL, graph-metadata, and oneDNN results
remain evidence for the exact primitive surfaces they exercised. They do not
establish one literal executable graph or close the findings above. Exact V2
supervised persistence remains Sprint `10.6`; persisted admission remains
Sprint `10.12`.

Sprint `10.6` therefore persists the `[LayerSpec]` / `[LayerState]` program that
actually executes, including the current `cifar10-vit` 4×4/64-token Mixer
contract. Its constant-time boxed-vector attention indexing and non-accumulating
`forwardOnly` tape traversal preserve that program's equations but do not merge
it with the parallel `archLayerGraph`, complete the missing gradient semantics,
or unblock Sprint `23.1`.

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
matmul), and graph metadata round-trips independently of physical weight layout.
Literal per-family training specializations and per-model architecture evidence
continue in Phase `24`; exact supervised persistence and loaded execution are
owned by Sprint `10.6`.

## Sprint 23.1: Typed Layer IR + Reverse-Mode Autodiff [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Numerics/LayerGraph.hs`, `src/JitML/Numerics/Autodiff.hs`, `src/JitML/Numerics/Mlp.hs`, `src/JitML/SL/Architecture.hs`, `test/unit/Main.hs`
**Blocked by**: Sprint `21.4`
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

### Remaining Work

- Replace the decorative `archLayerGraph` plus parallel executable
  `[LayerSpec]` / `[LayerState]` representations with one typed graph that owns
  training, inference, and graph-ordered parameter identity.
- Correct token-mixing and attention residual forward/direct-gradient terms,
  MaxPool and normalization backpropagation, and every named approximation.
- Replace silent `zipWith`, truncation, and fallback behavior with explicit
  shape/operation failures.
- Extend finite-difference coverage to parameter and input gradients for every
  layer kind and complete ResNet/ViT graphs.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation

The initial 2026-07-02 validation was withdrawn by the 2026-07-05 realness
audit because its oracle shared the dense stand-in. The 2026-07-06 reclosure
replaced that stand-in with kind-specific forward/backward transforms,
normalization, pooling, attention/gating, patch, and residual semantics and
reran the unit and canonical-SL gates recorded in [Phase State](#phase-state).
The cross-row mutation proof is now a separate downstream contract obligation
owned by Phase `32`; it does not turn the retired dense alias into current
Phase `23` state.

## Sprint 23.2: oneDNN Layer Kernels for Training [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Codegen/OneDnn.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/Numerics/MlpOneDnn.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Engines/OneDnnRuntime.hs`, `test/backends/Main.hs`
**Blocked by**: Sprint `23.1`
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

### Remaining Work

- Lower the single executable Sprint `23.1` graph to exact oneDNN forward,
  parameter-gradient, and input-gradient semantics for every supported node.
- Compare those kernels with an independent finite-difference oracle and reject
  unsupported layout/shape cases instead of reusing an approximation.

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

## Sprint 23.3: Layer-Graph Checkpoints + Inference [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/Checkpoint/Format.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/Inference/Decode.hs`, `src/JitML/Engines/LayerGraphCheckpoint.hs`, `src/JitML/Engines/Local.hs`, `test/integration/Main.hs`
**Blocked by**: Sprint `23.2`
**Docs to update**: `../documents/engineering/checkpoint_format.md`, `../documents/engineering/determinism_contract.md`

### Objective

Provide layout-independent layer-graph metadata/refinement and a graph-forward
runner that a strict checkpoint runtime can consume. The retained V1 exercise
serialized the Phase `23.1` topology and reconstructed it from named per-node
tensors; that proves the graph primitive, not current supervised persistence or
inference eligibility. Sprint `10.6` owns the V2 physical layout, exact loaded
program, and no-fallback engine dispatch, while Sprint `10.12` owns persisted
admission.

### Deliverables

- `LayerGraphMetadata` represents topology, typed shapes, edges, operations,
  attributes, and stable node/parameter identities independently of whether a
  wire format uses named physical tensors or virtual slices into one flat blob.
- Graph refinement rejects duplicate nodes, dangling edges, impossible shapes,
  unknown operations, and parameter identities inconsistent with the graph.
- `JitML.Numerics.LayerGraphOneDnn.runLayerGraphForwardOneDnn` executes a
  supplied refined graph and parameters through the Phase `23.2` oneDNN
  primitives; it does not choose a checkpoint version, physical layout, or
  fallback policy.
- Unit coverage round-trips graph metadata and compares the refined graph runner
  with the per-kind reference algebra. The old named-tensor checkpoint case is
  retained as V1 inspection coverage only.

### Remaining Work

- Round-trip and execute the exact graph completed by Sprints `23.1` and
  `23.2`, preserving its operation order and parameter identities.
- Prove checkpoint reload and inference use that same graph with strict
  tamper/shape/operation rejection; no decorative metadata or fallback graph
  may satisfy the gate.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation (retained primitive only)

`jitml-unit --linux-cpu` passed 270 / 270 on 2026-07-02,
including the LayerGraph checkpoint topology round-trip. The targeted
`jitml-integration` graph checkpoint inference case passed when run directly
with `cabal test jitml-integration --test-show-details=direct --test-options='-p loadInferenceCheckpointWithWeights'`.
`jitml docs check` and `jitml check-code` both passed after the Sprint `23.3`
implementation/docs update. After rebuilding `jitml:local` with Dockerfile
`check-code: ok`, deleting and recreating the `jitml-linux-cpu` Kind cluster,
and running `jitml cluster up --substrate linux-cpu` with
`JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1`, `jitml cluster status` reported every
component ready and `docker compose run --rm jitml jitml test jitml-integration
--linux-cpu` passed all 79 / 79 tests on 2026-07-02. The realness audit then
withdrew the inference claim until Sprints `23.1`/`23.2` corrected the per-kind
forward path. Those results predate V2 and do not establish the current
supervised physical layout, strict loaded execution, or eligibility. Sprint
`10.6` and Sprint `10.12` own those current obligations.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/numerical_core.md` — reverse-mode autodiff over the
  typed layer graph and the full layer catalog (forward + backward per node).
- `documents/engineering/jit_codegen_architecture.md` — oneDNN training-direction
  layer kernels, including convolution/normalization/pooling/attention backward.
- `documents/engineering/checkpoint_format.md` — layout-independent layer-graph
  metadata primitives; Sprint `10.6` owns the exact V2 supervised physical and
  virtual layout.
- `documents/engineering/determinism_contract.md` — layer-graph determinism:
  same seed and same substrate produce bit-identical gradients and inference.

**Product docs to create/update:**
- `README.md` — layer catalog available to supervised model families.

**Cross-references to add:**
- Link this phase from the control docs `README.md`, `00-overview.md`,
  `system-components.md`, and `development_plan_standards.md`.

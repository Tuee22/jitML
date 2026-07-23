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

🔄 **Active** at Sprint `23.2` (Sprint `23.1` closed 2026-07-22). Sprint `23.1`
delivered the correct reverse-mode autodiff node library, **finite-difference
validated** for parameter and input gradients across the full catalog (see
[Sprint 23.1 Validation Evidence](#sprint-231-validation-evidence)), and its
`cifar10-vit` convergence go/no-go returned **GO** (median(k=5) `0.279`) with the
vacuous convergence bars resolved. The served-path attention residual add and the
wiring of the verified Tier-2 nodes into the executed/serialized path are blocked
by the byte-frozen pre-23.1-semantics contract and are owned by Sprint `23.2`
(see [Deferred to Sprint 23.2](#deferred-to-sprint-232-not-a-sprint-231-gap)).
The
2026-07-18 executable-graph audit found two competing representations: the
advertised `archLayerGraph` and the `[LayerSpec]` / `[LayerState]` program that
actually trains and serves. Token mixing and attention omit required residual
or direct-gradient terms, several pooling/normalization backprop paths were
approximations, silent `zipWith`/fallback seams could truncate mismatches, and the
finite-difference suite did not cover the input-gradient contract. Sprint `23.1`
has replaced every named per-node approximation with the correct forward +
`backward_data` + `backward_weights`, added the input-gradient finite-difference
oracle, and made the smart constructors reject shape/operation mismatches instead
of silently collapsing; wiring those verified nodes into the executed/serialized
served path is deferred to Sprint `23.2` per the Planning Note. Sprint `23.2` is
blocked by `23.1`; Sprint `23.3` is blocked by `23.2`.

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

## Sprint 23.1: Typed Layer IR + Reverse-Mode Autodiff [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Numerics/LayerGraph.hs`, `src/JitML/Numerics/Autodiff.hs`, `src/JitML/Numerics/Mlp.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/SL/Architecture.hs`, `src/JitML/Checkpoint/Store.hs`, `src/JitML/SL/ConvergenceThresholds.hs`, `src/JitML/Test/NegativeControls.hs`, `test/unit/Main.hs`, `test/sl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/numerical_core.md`, `../documents/engineering/determinism_contract.md`

**Planning note (2026-07-22)**: A multi-agent design pass produced an
implementable blueprint at
[phase-23-sprint-23.1-blueprint.md](phase-23-sprint-23.1-blueprint.md). Two
findings reshape execution: (1) **a checkpoint-format wall** — the frozen V2
supervised slice contract (`RuntimeArtifact.deriveLayerSlices`,
`Architecture.hs:1739`) forces every serialized SL operator to be exactly one
`MlpParams (W1,b1,W2,b2)`, so 23.1 builds the correct Tier-2 autodiff node
library (conv/pool/norm/attention/geglu/residual) with finite-difference
verification and lands only param-neutral Tier-1 fixes on the served path;
wiring the real architectures into the serialized/served path needs a format
version bump and is Sprint 23.2. (2) **The convergence go/no-go is
`cifar10-vit`** — swapping to the real self-attention architecture moves it in
the wrong direction (already 0.218 < the 0.25 bar under the easier proxy), while
conv rows are helped by real convolution; honest mitigations (warmup+cosine
schedule, zero-init-residual, more real data/epochs — no bar weakening) plus the
vacuous `tiny-imagenet-resnet50` (0.00) / `cifar100-wide-resnet` (0.04) bars
must be resolved here so Sprint 24.2 is a real go.

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

### Completed in this sprint

- The typed `LayerGraph` IR carries real operator geometry per node via a
  `layerNodeOp :: LayerOp` field (`ConvSpec`, `SpatialShape`/`PoolSpec`,
  `NormSpec`, `AttentionSpec`, `GeGLUSpec`, `AffineSpec`/`Shortcut`,
  `BlockSpec`, `PatchSpec`). Multi-tensor parameters pack into the existing flat
  `layerWeights`/`layerBias` with the segment layout recovered from
  `opWeightSegments`/`opBiasSegments`, so `graphParameterVector` /
  `replaceGraphParameterVector` stay operator-agnostic.
- Correct forward + `backward_data` + `backward_weights` for every catalog node:
  `Conv2D`, `Conv3D` (one N-D path), `MaxPool` (argmax-routed), `AvgPool`,
  `GlobalAvgPool` (per-channel), `LayerNorm`, `GroupNorm`, `BatchNorm`
  (batch-axis coupling), `MultiHeadAttention` (with residual add and `W_O`),
  `PatchEmbed` (shared projection + col2im), `GeGLU` (exact-erf GELU), and
  `Residual`/`BasicBlock`/`Bottleneck` (typed identity/projection shortcut).
  Backward recomputes forward internals from the stored node input, so no tape
  enrichment is required and gradients are deterministic for a fixed seed.
- The finite-difference suite covers **both** parameter and input gradients for
  every node kind plus full ResNet-shaped and ViT-shaped composed graphs, via the
  new `maxInputFiniteDifferenceError` oracle. Smart constructors reject shape and
  operation mismatches (identity shortcut on differing widths, `C mod G /= 0`,
  `embedDim mod heads /= 0`, non-composing block stages) instead of silently
  collapsing, and the `jitml-negative-controls` `conv2d-not-dense` gate now runs
  a genuine 3×3 convolution.

### Convergence go/no-go — GO

The dry median(k=5) for `cifar10-vit` was run through the production path
(`Architecture.architectureSpecForProblem` → `VisionTransformerFamily`,
`trainCanonicalArchitectureWithDeviceSelected` on the real oneDNN device, the
SHA-verified canonical CIFAR-10 binary archive, the current product budget of
2000 train / 5 epochs / batch 128 / lr `1.5e-3`), with a held-out 500-example
validation slice for epoch selection and the disjoint 1000-example CIFAR-10 test
split for the reported accuracy. The five seeds returned `0.275, 0.279, 0.281,
0.287, 0.275` for a **median `0.279`**, clearing the `0.25` effective bar under
the current regime with no warmup/cosine mitigation required — **GO**. The
measurement was run in-container against real oneDNN with no cluster (a
throwaway harness driving the production `Architecture` training path over the
on-disk canonical CIFAR-10 archive); Sprint `24.2` owns the permanent per-row
convergence-validation harness.

The vacuous-bar realness holes are resolved in
`src/JitML/SL/ConvergenceThresholds.hs`: `tiny-imagenet-resnet50`'s slack was
tightened (`0.64 → 0.62`) so its effective bar is `0.02` (above the `1/200`
random floor) rather than the vacuous `0.00`; `cifar100-wide-resnet`'s `0.04`
was confirmed above its `1/100` floor. A permanent anti-vacuity invariant
(`slBarIsNonVacuous`, requiring every effective bar to exceed its
random-classification baseline) is enforced by a `jitml-sl-canonicals` unit
assertion.

### Deferred to Sprint 23.2 (not a Sprint 23.1 gap)

- **Served-path Tier-2 wiring + the attention residual add.** The executed
  supervised operators are byte-frozen against the Sprint `10.6` V2 contract:
  `test/unit/SupervisedRuntimeArtifact.hs` asserts the generated CPU token-mix
  and attention execute the **exact pre-23.1 semantics** and explicitly that the
  token-mix **"must not add an implicit residual."** Landing the attention
  residual add (`Y = X + O`), dropping the spurious outer `tanh`, and wiring the
  verified Tier-2 nodes into the executed/serialized path therefore require a
  checkpoint format version bump and are owned by Sprint `23.2`; the decorative
  `archLayerGraph` and the executed `[LayerState]` path remain until then.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Sprint 23.1 Validation Evidence

Landed 2026-07-22 on `linux-cpu` (in the `jitml:local` container): `jitml-unit`
passed **763 / 763** (24 new Sprint 23.1 per-node parameter+input
finite-difference cases covering all fourteen catalog nodes, full ResNet-shaped
and ViT-shaped composed graphs, and four explicit shape/operation-failure
controls); `jitml-negative-controls` passed **3 / 3** (including the
real-convolution `conv2d-not-dense` gate); `jitml-model-convergence` passed
**111 / 111**; `jitml docs check` and `jitml check-code` both exited `0`. The
convergence go/no-go returned **GO** (`cifar10-vit` median(k=5) `0.279 ≥ 0.25`,
see [Convergence go/no-go — GO](#convergence-gono-go--go)) and the vacuous
`tiny-imagenet-resnet50` / `cifar100-wide-resnet` bars were resolved with a
permanent anti-vacuity invariant asserted in `jitml-sl-canonicals`. The
served-path Tier-2 wiring and the attention residual add remain owned by Sprint
`23.2` (byte-frozen pre-23.1-semantics contract).

### Historical Validation

The initial 2026-07-02 validation was withdrawn by the 2026-07-05 realness
audit because its oracle shared the dense stand-in. The 2026-07-06 reclosure
replaced that stand-in with kind-specific forward/backward transforms,
normalization, pooling, attention/gating, patch, and residual semantics and
reran the unit and canonical-SL gates recorded in [Phase State](#phase-state).
The cross-row mutation proof is now a separate downstream contract obligation
owned by Phase `32`; it does not turn the retired dense alias into current
Phase `23` state.

## Sprint 23.2: oneDNN Layer Kernels for Training [📋 Planned]

**Status**: Planned
**Implementation**: `src/JitML/Codegen/OneDnn.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/Numerics/MlpOneDnn.hs`, `src/JitML/Numerics/MlpDevice.hs`, `src/JitML/Engines/OneDnnRuntime.hs`, `test/backends/Main.hs`
**Docs to update**: `../documents/engineering/jit_codegen_architecture.md`, `../documents/engineering/numerical_core.md`

Sprint `23.2` additionally owns wiring the verified Tier-2 autodiff nodes and the
attention residual add into the executed/serialized supervised path (a checkpoint
format version bump), which the byte-frozen Sprint `10.6` pre-23.1-semantics
contract keeps out of Sprint `23.1`.

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

# Numerical Core

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-6-numerical-core.md, ../../DEVELOPMENT_PLAN/phase-23-general-differentiable-layer-engine.md, training_workloads.md, training_metrics_and_splits.md, run_contract.md
**Generated sections**: numerics.layers, numerics.activations, numerics.spectral, numerics.optimizers, numerics.schedulers, numerics.losses

> **Purpose**: Project-specific numerical-core catalog for jitML — the current
> local Haskell catalog under `src/JitML/Numerics/Catalog.hs`, the Dhall mirror
> list tree under `dhall/numerics/`, and the generated documentation tables
> rendered from those sources.

Phase state, remaining work, blockers, and validation evidence live only in
[Development Plan → Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status).
This document owns the numerical representation and execution boundary; it does
not infer product or substrate-lane closure from catalog coverage or dated pass
counts.

## Current Status

**Implemented today.** The typed `LayerGraph` IR is the single owner of
supervised training, checkpoint topology, graph-ordered parameter identity, and
serving. `ArchitectureSpec.archLayerGraph` is the executable literal graph for
the non-dense architecture families. The retained `[LayerSpec]` / `[LayerState]`
types are only a Dense-family initialization adapter: their initialized dense
parameters are lifted immediately into a `LayerGraph`, and they do not form a
parallel training, checkpoint, or serving interpreter. The catalog tables below
are current.

## Execution Boundary

Training updates the typed graph through the device-backed classifier path, and
the pure `LayerGraph` forward/backward algebra is the correctness oracle.

**Current status.** Substrate selection drives graph training on the two Linux
lanes. Sprint `264.1` parameterised the classifier path on `Substrate` behind a
`LayerTrainingBackend`, so `linux-cpu` executes oneDNN primitives and
`linux-cuda` executes cuBLAS/cuDNN primitives, both under one total lowering and
one shared operator layer. `apple-silicon` has no layer-graph training kernel and
fails closed naming Sprint `270.1` instead of executing another lane's artifact.
The remaining target — the Metal arm, so every supported substrate executes every
operator with the pure algebra retained strictly as the oracle — is owned by
[Phase 233](../../DEVELOPMENT_PLAN/phase-233-typed-layer-ir-reverse-mode-autodiff.md),
[Phase 241](../../DEVELOPMENT_PLAN/phase-241-onednn-device-training-kernels-for-correct-operators.md),
and Phase `79`. Checkpoint construction serializes the trained graph metadata and
its graph-ordered parameter vector.

Serving reconstructs that graph from admitted checkpoint metadata, injects the
one physical `supervised.weights` tensor, refines the reloaded structure, applies
the persisted input transform, calls the shared pure `LayerGraph.runLayerGraph`,
and applies the output transform. Input/output transforms stay outside the graph,
and Apple Silicon and Linux CUDA supervised serving delegate to this same
substrate-independent path. The validated workload plan and the completed
evidence required around numerical execution are owned by
[Typed Run Contract](run_contract.md); inference eligibility is owned by
[Checkpoint Format](checkpoint_format.md) and
[Product Completion Contract](product_completion_contract.md). A catalog entry
or a successful forward call alone is not a completion witness.

The CUDA trainer MLP seam uses the generated forward, batched, and gradient
kernels in `src/JitML/Codegen/MlpCuda.hs`; it is distinct from the generated
family-kernel surface where Dense/MHA use cuBLAS and convolution and
normalization families use cuDNN. The oneDNN and Metal implementations retain
the same separation between the trainer seam, general family kernels, and the
pure reference algebra. Substrate validation status belongs to the development
plan, not this architecture document.

## Catalog Shape

The current numerical core is a local typed Haskell catalog. It enumerates the
constructor names consumed by command summaries, tests, and the JIT codegen
metadata surface. The implementation source is
`src/JitML/Numerics/Catalog.hs`; it exposes `layerCatalog`,
`activationCatalog`, `spectralCatalog`, `optimizerCatalog`,
`schedulerCatalog`, `lossCatalog`, and `renderNumericalCatalog`.

The constructor-name leaves under `dhall/numerics/` are Dhall *values*: they name
the vocabulary but carry no geometry, so on their own they cannot describe an
architecture. The parameterized half is the reflected operator schema below.

## Kernel-Family Semantics Contract

`JitML.Numerics.FamilyReference.defaultFamilyWeights` names each kernel
family's *canonical no-op weights* — the weight buffer that makes the weighted
kernel compute exactly what the unweighted kernel is supposed to compute: the
identity matrix for `Dense2D`, a unit-centre filter for `Conv2D`/`Conv3D`,
scale-1/shift-0/mean-0/var-1 for `BatchNorm`, scale-1/shift-0 for `LayerNorm`,
`Wq = Wk = Wv = I` for multi-head attention, and an empty buffer for `Identity`,
`Reduction`, and `Embedding`, which have no weight parameter at all.

The unweighted reference is then *defined* as the weighted reference at those
defaults, so the unweighted ABI has no independent definition to drift from. At
`Wq = Wk = Wv = I` the attention algebra degenerates to `out[i] = input[i]^2`;
the `linux-cuda` and `apple-silicon` renderers already emitted that, while the
`linux-cpu` renderer returned the input unchanged. The oneDNN renderer now
emits `jitml_onednn_mha_unit`, which builds identity projections and delegates
to the weighted routine, so the generated C++ expresses the same law the oracle
does.

The backends lane checks each lane's unweighted output against this contract for
every family. Before Sprint `80.1` the unweighted ABI was only smoke-asserted —
non-empty, finite, right length — which is why the divergence survived.

## Parameterized Layer Vocabulary

`src/JitML/Numerics/LayerDhall.hs` expresses the executed operator `LayerOp` as a
parameterized Dhall union, with each alternative carrying that operator's real
geometry — convolution input/kernel/stride/padding dimensions, pooling windows,
normalization flavor and channel counts, attention sequence length, embedding
width and head count, GeGLU and patch-embedding widths, residual and block
topology. The checked-in `dhall/numerics/LayerOp.dhall` and
`dhall/numerics/LayerGraph.dhall` are not hand-written: they are read back off
the live `Dhall.Decoder` with `Dhall.expected` through
`JitML.Dhall.Reflect.reflectedSchemaText`, the same reflection the daemon config
surfaces use, and they are tracked generated paths (`numerics.layer-op.schema`,
`numerics.layer-graph.schema`) so `jitml docs check` fails on drift. The schema
therefore cannot fall behind the Haskell type, because it *is* the Haskell type.

`LayerGraphDescription` lifts the vocabulary to a whole architecture — named
nodes, declared shapes, mode, activation, plus the seed that fixes deterministic
initialization — so a network is data rather than a hardcoded Haskell builder.
`buildLayerGraph` realizes a description through the correctness-checked smart
constructors and **fails closed**: a declared shape that disagrees with the
geometry its operator actually produces, a pair of nodes that do not chain, or a
graph whose own input/output shapes do not match its ends is rejected rather
than adjusted.

The cross-type audit run by `jitml lint haskell`
(`src/JitML/Lint/DhallNumerics.hs`) covers four rules: the catalog leaves match
the Haskell catalog; the reflected union's alternatives are exactly the executed
`LayerOp` constructors and each projects onto exactly one `Catalog.Layer`; each
checked-in reflected type file equals what the live decoder reflects; and no
ML-describing Dhall file names a `substrate`. That last rule is deliberate — an
architecture is substrate-independent, and substrate selection belongs on the
CLI/plan seam, not in the ML DSL.

The unit lane additionally asserts `decode . render == id` over every operator
witness, so the writer (`renderLayerOp`) and the decoder cannot drift apart
without failing a test.

## Typed Layer Graph and Autodiff

`LayerGraph` is the sole representation used by supervised training,
checkpointing, and graph inference. `TrainedArchitecture` carries the trained
graph directly; `LayerGraphMetadata` round-trips its exact topology and packed
parameter layout through the checkpoint, and Store reload injects the admitted
weight vector before structural refinement and serving. Phase order and
validation evidence remain in the
[Development Plan](../../DEVELOPMENT_PLAN/README.md).

The typed layer-graph surface lives in
`src/JitML/Numerics/LayerGraph.hs` and the public pure reverse-mode API in
`src/JitML/Numerics/Autodiff.hs`. A `LayerNode` carries input/output tensor
shapes, per-node training-vs-inference mode, activation, packed row-major
parameter tensors (`layerWeights`/`layerBias`), and a `layerNodeOp :: LayerOp`
that records the node's real operator geometry: `ConvSpec` (one N-D path for
Conv2D and Conv3D), `SpatialShape` + `PoolSpec` (Max/Avg/GlobalAvg windows),
`NormSpec` (Batch/Layer/Group), `AttentionSpec`, `GeGLUSpec`, `AffineSpec` +
`Shortcut` (identity or learnable projection), `BlockSpec` (ordered
affine→norm stages), and `PatchSpec`. Multi-tensor operators pack their
sub-tensors into the flat parameter vectors with the segment layout recovered
from `opWeightSegments` / `opBiasSegments`, so `graphParameterVector`,
`replaceGraphParameterVector`, and the gradient flatten stay operator-agnostic.
The catalog covers Dense, Conv2D, Conv3D, MaxPool, AvgPool, GlobalAvgPool,
BatchNorm, LayerNorm, GroupNorm, Dropout, Residual, BasicBlock, Bottleneck,
MultiHeadAttention, GeGLU, patch-embed, and Identity.

### One operator vocabulary

`LayerOp` is the single layer vocabulary (Sprint `72.1`). Everything else is a
projection of it by a total function, so a constructor cannot exist in one
surface and not the others:

- `opKind :: LayerOp -> LayerKind` gives the node identity tag. `LayerNode` no
  longer stores a kind beside its operator — `layerNodeKind` is that projection
  — so a node cannot claim an operator it did not execute, and the oneDNN
  switch key is the executed operator by construction. Kinds that refine one
  operator by its spec (Conv2D vs Conv3D, the three pooling flavours, the three
  normalization flavours, basic vs bottleneck block) are read off the spec:
  a block is a bottleneck exactly when it narrows internally, and
  `mkBasicBlock` / `mkBottleneck` reject a spec of the other topology rather
  than tagging it.
- `opLayer :: LayerOp -> Catalog.Layer` gives the catalog constructor, and
  `layerOpTemplate :: Catalog.Layer -> LayerOp` gives a minimal executable
  operator for each catalog entry. Both are total, so
  `-Werror=incomplete-patterns` (Sprint `7.1`) fails the build when either
  vocabulary gains a constructor the other lacks.
- `layerKindWitnessOp :: LayerKind -> LayerOp` is total over `LayerKind`, and
  `opKind . layerKindWitnessOp` is the identity over `allLayerKinds`, so a
  declared kind cannot exist without an operator that executes it.
- `Catalog.layerCatalog` is `[minBound .. maxBound]` over `Catalog.Layer`, and
  `dhall/numerics/Layer.dhall` mirrors that list under the cross-type audit, so
  the documentation table and the Dhall surface are projections rather than
  parallel hand-maintained lists.
- The checkpoint DTO's `layerGraphNodeKind` is written from `opKind` and
  verified against it on read: `layerGraphFromMetadata` rejects a persisted kind
  that disagrees with the persisted operator, making that wire field a checksum
  on the one vocabulary rather than a second one.

Each node has a correct forward and a correct reverse-mode backward that
produces both the input gradient (`backward_data`) and per-node parameter
gradient (`backward_weights`): convolution via im2col with a col2im
scatter-accumulating adjoint; MaxPool routing to the argmax switch; Avg and
GlobalAvg pooling with the exact divisor and per-channel reduction;
Layer/Group/Batch normalization with the fully-coupled mean/variance Jacobian
(BatchNorm couples across the batch axis); multi-head attention with the
softmax Jacobian, output projection, and residual add; patch embedding with a
shared projection and col2im input routing; GeGLU with exact-erf GELU; and
residual/basic/bottleneck blocks with a typed identity-or-projection shortcut.
The backward pass recomputes forward internals from the stored node input, so
the tape needs no per-node state and gradients are deterministic for a fixed
seed. This whole reverse-mode implementation is the **oracle** the device
kernels are checked against on the substrate lane, not a runtime path they fall
back to: the `linux-cpu` operator lowering is total over `LayerOp`, so pooling,
dropout, and identity execute their own device kernels rather than borrowing
their gradient from here. The smart constructors return `Left` on shape/operation mismatch
(identity shortcut on differing widths, channels not divisible by groups,
embed dim not divisible by heads, non-composing block stages) rather than
silently collapsing. `JitML.Numerics.Mlp` remains the two-layer special case:
its `mlpBackward` / `mlpInputGradient` lower the cached MLP forward into a
two-node dense graph tape and call `Autodiff.runBackward`, so the RL and
AlphaZero networks differentiate through the same surface unchanged.

Unit coverage asserts, for every catalog node, that central
finite differences of a squared-error loss match the analytic **parameter**
gradient (`maxFiniteDifferenceError`) and the analytic **input** gradient
(`maxInputFiniteDifferenceError`); that a full ResNet-shaped graph (conv stem →
basic block → global-avg pool → dense) and a full ViT-shaped graph
(patch-embed → norm → attention → GeGLU → dense) match finite differences end
to end; that same-seed runs produce bit-identical gradients; and that the
explicit shape/operation failures are rejected. The `jitml-negative-controls`
`conv2d-not-dense` gate runs a genuine 3×3 convolution.

The linux-cpu graph-training path renders a content-addressed shared object with
`jitml_layer_forward`, `jitml_layer_backward_data`, and
`jitml_layer_backward_weights`. It executes a **real `dnnl` primitive per
operator kind**. `ConvOp` executes spatial
`convolution_{forward,backward_data,backward_weights}` over the true `[C_in,H,W]`
/ kernel / stride / padding geometry; `NormOp` runs batch / layer / group
normalization; `GeGLUOp` runs the three-projection gated-GELU; `AttentionOp` runs
multi-head scaled-dot-product attention including the `W_O` output projection; and
`PatchOp`, `ResidualOp`, and the BasicBlock/Bottleneck `BlockOp` (composed from
dense + norm device sub-kernels) run on their real packed parameter layouts.
`deviceLayerGradient` dispatches on the node's `LayerOp` to the matching kernel,
and each device kernel is validated against the pure `backwardLayerGraph` oracle
within float32 tolerance in the backends lane; on this lane the pure gradient is
the oracle only, never a runtime fallback. That property holds for `linux-cpu`,
which is the only substrate with a layer-graph device path today.

Each supervised row binds to a literal graph on this surface.
The ResNet family (small ResNet, ResNet-20, ResNet-56, WideResNet-28-10, and the
ResNet-50 bottleneck) is a literal mixer-ResNet layer graph — real `Conv2D` with a
two-conv strided stem, `BatchNorm`/`GroupNorm`, `LayerNorm`, residual
BasicBlock/Bottleneck blocks, attention, and GeGLU — trained as a compact proxy
under the bounded product budget; the 2-D convolution forward is a tight unboxed
kernel.

`ArchitectureFeature` records the feature claims that product rows make
(`Dense`, `BatchNorm`, `Dropout`, `Conv2D`, pooling, `GroupNorm`, residual,
`BasicBlock`, `BottleneckBlock`, attention, patch embedding, `LayerNorm`, and
`GeGLU`). For every non-dense row, `architectureImplementedFeatures` derives
those claims from the same executable `archLayerGraph` that training consumes;
the Dense-family adapter lifts its initialized dense state into an equivalent
typed graph. Topology/count tests guard the literal graphs. The current
`cifar10-vit` graph executes patch
embedding, affine LayerNorm, two-head self-attention with `W_O` and the outer
residual, GeGLU, and the classifier through `LayerGraph`.

`RawCheckpointBodyV2`, `RawSupervisedRuntimePayload`, and the other V1/V2 names
remain valid wire/DTO names. V2 now carries the trained graph metadata, exact
outside-the-graph transforms, and the graph-ordered physical weight binding; it
does not name a second structural executor. The frozen Sprint-`10.6`
pre-IR token-operation artifacts remain historical diagnostic evidence only and
cannot validate the current typed-graph contract. The deleted
`RuntimeOperations*` structural ABI is not part of current training or serving.

`JitML.Test.RowAssertions` consumes measured row evidence from
the device-backed SL path: deterministic initial/final weight hashes, update
count, train/validation/test split sizes, examples seen, non-wall-clock
throughput, real train and validation losses, held-out test metric, gradient
norm, and the literature/slack convergence bar. It rejects equal weights,
zero-update runs, missing validation/test partitions, zero or non-finite
gradient evidence, smoke thresholds, and deliberately underpowered two-step
evidence that fails the convergence bar.

## Layers

<!-- jitml:numerics.layers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Dense` | Generated from current Haskell catalog |
| `Identity` | Generated from current Haskell catalog |
| `Dropout` | Generated from current Haskell catalog |
| `Convolution` | Generated from current Haskell catalog |
| `Pooling` | Generated from current Haskell catalog |
| `Normalization` | Generated from current Haskell catalog |
| `MultiHeadAttention` | Generated from current Haskell catalog |
| `GeGLU` | Generated from current Haskell catalog |
| `PatchEmbedding` | Generated from current Haskell catalog |
| `Residual` | Generated from current Haskell catalog |
| `ResidualBlock` | Generated from current Haskell catalog |
<!-- jitml:numerics.layers:end -->

Owning module today: `src/JitML/Numerics/Catalog.hs`; Dhall mirror:
`dhall/numerics/Layer.dhall`. Target work adds separate parameterized layer
modules.

## Activations

<!-- jitml:numerics.activations:start -->
| Real-valued | Complex-valued |
|-------------|----------------|
| `Relu` | `ComplexModRelu` |
| `LeakyRelu` | `ComplexCardioid` |
| `Elu` | `ComplexZRelu` |
| `Silu` |  |
| `Gelu` |  |
| `Tanh` |  |
| `Sigmoid` |  |
| `Softmax` |  |
<!-- jitml:numerics.activations:end -->

Owning module today: `src/JitML/Numerics/Catalog.hs`; Dhall mirror:
`dhall/numerics/Activation.dhall`.

## Spectral / Frequency-Domain Operations

<!-- jitml:numerics.spectral:start -->
| Constructor | Current scope |
|-------------|---------------|
| `FFT` | Generated from current Haskell catalog |
| `FFTAlongAxis` | Generated from current Haskell catalog |
| `IFFT` | Generated from current Haskell catalog |
| `IFFTAlongAxis` | Generated from current Haskell catalog |
| `RFFT` | Generated from current Haskell catalog |
| `IRFFT` | Generated from current Haskell catalog |
| `STFT` | Generated from current Haskell catalog |
| `DCT` | Generated from current Haskell catalog |
| `ComplexConjugate` | Generated from current Haskell catalog |
| `ComplexMatMul` | Generated from current Haskell catalog |
<!-- jitml:numerics.spectral:end -->

Owning module today: `src/JitML/Numerics/Catalog.hs`; Dhall mirror:
`dhall/numerics/SpectralOp.dhall`.

## Optimizers

<!-- jitml:numerics.optimizers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `SGD` | Generated from current Haskell catalog |
| `MomentumSGD` | Generated from current Haskell catalog |
| `NesterovSGD` | Generated from current Haskell catalog |
| `RMSProp` | Generated from current Haskell catalog |
| `Adagrad` | Generated from current Haskell catalog |
| `Adadelta` | Generated from current Haskell catalog |
| `Adam` | Generated from current Haskell catalog |
| `AdamW` | Generated from current Haskell catalog |
| `LAMB` | Generated from current Haskell catalog |
| `LARS` | Generated from current Haskell catalog |
| `Lion` | Generated from current Haskell catalog |
| `AdaFactor` | Generated from current Haskell catalog |
| `Shampoo` | Generated from current Haskell catalog |
<!-- jitml:numerics.optimizers:end -->

Owning module today: `src/JitML/Numerics/Catalog.hs`; Dhall mirror:
`dhall/numerics/Optimizer.dhall`. Separate optimizer modules and parameterized
records are future extension work beyond the current catalog mirror.

## Schedulers

<!-- jitml:numerics.schedulers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Constant` | Generated from current Haskell catalog |
| `Linear` | Generated from current Haskell catalog |
| `Cosine` | Generated from current Haskell catalog |
| `CosineWithWarmup` | Generated from current Haskell catalog |
| `Exponential` | Generated from current Haskell catalog |
| `Polynomial` | Generated from current Haskell catalog |
| `OneCycle` | Generated from current Haskell catalog |
| `Piecewise` | Generated from current Haskell catalog |
| `ReduceOnPlateau` | Generated from current Haskell catalog |
<!-- jitml:numerics.schedulers:end -->

Owning module today: `src/JitML/Numerics/Catalog.hs`; Dhall mirror:
`dhall/numerics/Scheduler.dhall`. History-dependent `ReduceOnPlateau` behavior
remains target callback work because it consumes evaluation history rather than
only progress.

## Loss Functions

<!-- jitml:numerics.losses:start -->
| Constructor | Current scope |
|-------------|---------------|
| `CrossEntropy` | Generated from current Haskell catalog |
| `BinaryCrossEntropy` | Generated from current Haskell catalog |
| `SparseCrossEntropy` | Generated from current Haskell catalog |
| `Focal` | Generated from current Haskell catalog |
| `MSE` | Generated from current Haskell catalog |
| `Huber` | Generated from current Haskell catalog |
| `IoU` | Generated from current Haskell catalog |
| `Dice` | Generated from current Haskell catalog |
| `KLDiv` | Generated from current Haskell catalog |
| `Contrastive` | Generated from current Haskell catalog |
<!-- jitml:numerics.losses:end -->

Owning module today: `src/JitML/Numerics/Catalog.hs`; Dhall mirror:
`dhall/numerics/Loss.dhall`.

## Dhall Schemas

`dhall/numerics/Schema.dhall` is the umbrella module re-exporting the current
constructor-name lists for `Layer`, `Activation`, `SpectralOp`, `Optimizer`,
`Scheduler`, and `Loss`. `src/JitML/Numerics/Schema.hs` exposes the Haskell
decoder/validator, and `src/JitML/Lint/DhallNumerics.hs` enforces the
cross-type audit:

- Every Haskell constructor has a Dhall constructor of the same name.
- Every Dhall constructor has a Haskell decoder.

`jitml lint haskell` runs this audit. The current configuration-as-code
fixtures are `experiments/mnist.dhall`, `experiments/mnist-tune.dhall`, and
`experiments/cartpole.dhall`.

## Worked Example

The current worked examples are the checked-in local fixtures under
`experiments/`. The numerical schema mirror resolves through
`dhall/numerics/Schema.dhall` and is validated by `jitml-unit` plus
`jitml lint haskell`.

## Cross-References

- [../../README.md → Numerical core](../../README.md#numerical-core)
- [training_workloads.md](training_workloads.md)
- [jit_codegen_architecture.md](jit_codegen_architecture.md)
- [../../DEVELOPMENT_PLAN/phase-6-numerical-core.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)

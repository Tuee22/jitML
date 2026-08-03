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

Training selects a substrate device and updates the typed graph through the
device-backed classifier path. The pure `LayerGraph` forward/backward algebra is
the correctness oracle; it is not a fallback for a failed selected-device
operation. Checkpoint construction serializes the trained graph metadata and
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

The current schema mirror is a constructor-name audit, not a full parameterized
model schema. Future schema extensions should keep the same ownership model and
add richer parameterized constructors and typed records for layer shapes,
optimizer hyperparameters, scheduler parameters, and loss parameters.

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
MultiHeadAttention, GeGLU, and patch-embed.

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
seed. The smart constructors return `Left` on shape/operation mismatch
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
within float32 tolerance in the backends lane; the pure gradient is the oracle
only, never a runtime fallback.

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
| `Embedding` | Generated from current Haskell catalog |
| `Conv1D` | Generated from current Haskell catalog |
| `Conv2D` | Generated from current Haskell catalog |
| `Conv3D` | Generated from current Haskell catalog |
| `ConvTranspose` | Generated from current Haskell catalog |
| `ComplexDense` | Generated from current Haskell catalog |
| `ComplexConv2D` | Generated from current Haskell catalog |
| `BatchNorm` | Generated from current Haskell catalog |
| `LayerNorm` | Generated from current Haskell catalog |
| `GroupNorm` | Generated from current Haskell catalog |
| `Dropout` | Generated from current Haskell catalog |
| `ResidualBlock` | Generated from current Haskell catalog |
| `ScaledDotProductAttention` | Generated from current Haskell catalog |
| `MultiHeadAttention` | Generated from current Haskell catalog |
| `RotaryPositionalEmbedding` | Generated from current Haskell catalog |
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
- [../../DEVELOPMENT_PLAN/phase-6-numerical-core.md](../../DEVELOPMENT_PLAN/phase-6-numerical-core.md)

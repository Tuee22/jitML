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

## Execution Boundary

Training and evaluation select a substrate device and run the current
`[LayerSpec]` / `[LayerState]` executable through that device. Sprint `10.6`
persists this exact executed program; it does not substitute the parallel
descriptive `archLayerGraph`. Active Sprint `23.1` has landed the correct
reverse-mode autodiff node library on the typed graph (below); replacing the
descriptive `archLayerGraph` and the executed `[LayerSpec]` / `[LayerState]`
program with that one typed graph in the served/serialized path needs a
checkpoint format version bump and is deferred to Sprint `23.2`, and Blocked
Sprint `24.1` owns constructing each literal named architecture on that graph. The validated workload plan and the completed
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

The target `LayerGraph` is the sole representation used by training,
checkpointing, and graph inference. The current tree has landed the correct
autodiff engine on that graph but has not yet unified the served path onto it:
`archLayerGraph` describes the advertised feature topology, while the separate
`[LayerSpec]` / `[LayerState]` program actually trains, serves, and is projected
into supervised V2. Wiring the verified nodes into the executed/serialized path
needs a checkpoint format version bump and is Sprint `23.2`; the `cifar10-vit`
convergence go/no-go is the other open Sprint `23.1` obligation. Audit and
validation details remain in
[Phase 23](../../DEVELOPMENT_PLAN/phase-23-general-differentiable-layer-engine.md).

Sprint `23.1` implements the typed layer-graph surface in
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

Sprint `23.1` unit coverage asserts, for every catalog node, that central
finite differences of a squared-error loss match the analytic **parameter**
gradient (`maxFiniteDifferenceError`) and the analytic **input** gradient
(`maxInputFiniteDifferenceError`); that a full ResNet-shaped graph (conv stem →
basic block → global-avg pool → dense) and a full ViT-shaped graph
(patch-embed → norm → attention → GeGLU → dense) match finite differences end
to end; that same-seed runs produce bit-identical gradients; and that the
explicit shape/operation failures are rejected. The `jitml-negative-controls`
`conv2d-not-dense` gate runs a genuine 3×3 convolution.

Sprint `23.2` adds the linux-cpu oneDNN training path for the current graph
algebra. `JitML.Codegen.OneDnn.renderOneDnnLayerTrainingSource` emits a
content-addressed shared object with `jitml_layer_forward`,
`jitml_layer_backward_data`, and `jitml_layer_backward_weights`; dense and other
affine graph nodes execute oneDNN matmul, while `Conv2D` and `Conv3D` execute
oneDNN `convolution_forward` in `forward_training` mode plus
`convolution_backward_data` and `convolution_backward_weights` over the graph's
flat 1x1 channel projection. `JitML.Numerics.LayerGraphOneDnn` reuses the pure
forward tape for activation/residual/parameterless semantics and replaces each
parameterized node's update-critical gradients with backend-computed values. The
backend test compares that device gradient against the pure oracle across the
full `LayerGraph.allLayerKinds` catalog and records per-node primitive evidence.
Sprint `23.3` serializes that graph topology into checkpoints and runs
checkpoint inference through the stored graph.

Blocked Sprint `24.1` must bind the canonical supervised rows to literal graph
topology and feature metadata. `ArchitectureFeature` records the feature claims
that product rows make (`Dense`, `BatchNorm`, `Dropout`, `Conv2D`, pooling,
`GroupNorm`, residual, `BasicBlock`, `BottleneckBlock`, attention, patch
embedding, `LayerNorm`, and `GeGLU`), while the current
`architectureImplementedFeatures` derives its answer from the non-executable
`archLayerGraph`. The existing topology-count test therefore describes the
intended graph; it does not prove what trained. The exact current
`cifar10-vit` executable persisted by Sprint `10.6` uses patch size/stride
`4/4` over `32×32×3`, 64-token mixing, executed LayerNorm, a token-mixing
MLP, single-head attention, mean pooling, and a classifier. That is a real
current Mixer computation rather than the earlier unnormalized patch bag, but
it is not the declared two-head MultiHeadAttention/GeGLU small ViT and cannot
close Phase `24`. Its V2 algebra is deliberately the pre-Sprint-`23.1`
executable: token mixing replaces its input with the mixed result, attention
returns attended values without an outer skip, and only an explicit residual
layer adds a skip. Sprint `23.1` owns distinguishable corrected operations; it
cannot reinterpret these V2 bytes.

Within that current executable, attention backward stores Q/K/V, softmax
weights, and output gradients in boxed vectors so indexed lookup is
constant-time while preserving the original arithmetic and summation order.
Inference/evaluation `forwardOnly` may transiently create the current layer's
tape through `forwardLayer`, but projects the output immediately and does not
accumulate tapes across the graph. The 4×4/64-token numerical path fits its RGB
transform from the training partition only. Its measured diagnostic chronology
and current validation state live in Sprint `10.6`; pre-algebra-correction
artifacts cannot validate this contract. Exact V2 persistence does not repair
the parallel descriptive `archLayerGraph` representation.

Sprint `24.2` adds the supervised learning-evidence assertion layer in
`JitML.Test.RowAssertions`. The assertion consumes measured row evidence from
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
